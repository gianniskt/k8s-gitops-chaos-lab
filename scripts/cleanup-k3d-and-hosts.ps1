<#
  Deletes k3d cluster (if present) and removes host entries added by add-hosts.ps1
  Run as Administrator.
#>

param()

# elevation check
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "This script must be run as Administrator."
    exit 1
}

$hostsFile = Join-Path $env:SystemRoot "System32\drivers\etc\hosts"
if (-not (Test-Path $hostsFile)) {
    Write-Error "Hosts file not found at $hostsFile"
    exit 1
}

try {
    $rawTs = (Get-Date -UFormat %s) 2>$null
} catch {
    $rawTs = $null
}
$timestamp = if ($rawTs) { ($rawTs -split '[,\.]')[0] } else { (Get-Date).ToString('yyyyMMddHHmmss') }
$backup = "${hostsFile}.bak.$timestamp"
Copy-Item -Path $hostsFile -Destination $backup -Force
Write-Output "Backup created: $backup"

# Logging setup
$logTs = (Get-Date).ToString('yyyyMMdd-HHmmss')
$logFile = Join-Path $env:TEMP ("hosts-script-cleanup-$logTs.log")
function Write-Log([string]$msg) { "$((Get-Date).ToString('o')) - $msg" | Out-File -FilePath $logFile -Append -Encoding utf8 }
Write-Log "START cleanup-k3d-and-hosts.ps1"
Write-Log "hostsFile=$hostsFile backup=$backup"

$entries = @('grafana.local.test','chaos.local.test','linkerd.local.test','frontend.local.test')

# Remove matching lines from hosts file atomically
$raw = Get-Content -Path $hostsFile -ErrorAction Stop -Raw
$lines = if ($raw -eq '') { @() } else { $raw -split "\r?\n" }

$filtered = @()
foreach ($l in $lines) {
    $keep = $true
    foreach ($h in $entries) {
        if ($l -match "\b$([regex]::Escape($h))\b") { $keep = $false; break }
    }
    if ($keep) { $filtered += $l }
}

# Write back
$tmp = Join-Path (Split-Path $hostsFile -Parent) ("hosts.tmp.$timestamp")
$filtered | Out-File -FilePath $tmp -Encoding ASCII -Force
Copy-Item -Path $tmp -Destination $hostsFile -Force
Remove-Item -Path $tmp -ErrorAction SilentlyContinue

Write-Output "Removed host entries: $($entries -join ', ')"
Write-Log "Removed host entries: $($entries -join ', ')"

# Delete k3d cluster if available
if (Get-Command k3d -ErrorAction SilentlyContinue) {
    $clusterName = 'gitops-chaos'
    $clusters = k3d cluster list --no-headers 2>$null | ForEach-Object { ($_ -split '\s+')[0] }
    if ($clusters -contains $clusterName) {
        Write-Output "Deleting k3d cluster: $clusterName"
        k3d cluster delete $clusterName
    } else {
        Write-Output "k3d cluster '$clusterName' not found"
    }
} else {
    Write-Output "k3d not installed or not in PATH"
}

# Flush DNS cache
try { ipconfig /flushdns | Out-Null } catch { }

Write-Output "Done."
Write-Log "Done."

# Remove backup file created for this run so it doesn't remain in the Windows hosts folder
try {
    if (Test-Path -Path $backup) {
        Remove-Item -Path $backup -Force -ErrorAction Stop
        Write-Output "Removed backup: $backup"
        Write-Log "Removed backup: $backup"
    }
} catch {
    Write-Warning "Failed to remove backup file $backup: $($_.Exception.Message)"
    Write-Log "Failed to remove backup file $backup: $($_.Exception.Message)"
}

Write-Log "END cleanup-k3d-and-hosts.ps1"
Write-Output "Log saved to: $logFile"

# Remove backup file created for this run so it doesn't remain in the Windows hosts folder
try {
    if (Test-Path -Path $backup) {
        Remove-Item -Path $backup -Force -ErrorAction Stop
        Write-Output "Removed backup: $backup"
    }
} catch {
    Write-Warning "Failed to remove backup file $backup: $($_.Exception.Message)"
}