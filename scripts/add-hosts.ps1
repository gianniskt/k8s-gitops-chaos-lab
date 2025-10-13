<#
  Adds host entries on Windows if missing. Safe and idempotent.
  Run PowerShell as Administrator:
	.\add-hosts.ps1

  Behavior:
  - Creates a timestamped backup of the hosts file
  - Appends only missing entries
  - Writes via a temp file and replaces the hosts file with retries to avoid "file in use" errors
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

# Generate timestamp for backup
$rawTs = (Get-Date -UFormat %s) 2>$null
if ($rawTs) {
	$timestamp = ($rawTs -split '[,\.]')[0]
} else {
	$timestamp = (Get-Date).ToString('yyyyMMddHHmmss')
}

$backup = "${hostsFile}.bak.$timestamp"
Copy-Item -Path $hostsFile -Destination $backup -Force
Write-Output "Backup created: $backup"

# Logging setup
$logTs = (Get-Date).ToString('yyyyMMdd-HHmmss')
$logFile = Join-Path $env:TEMP ("hosts-script-add-hosts-$logTs.log")
function Write-Log([string]$msg) { "$((Get-Date).ToString('o')) - $msg" | Out-File -FilePath $logFile -Append -Encoding utf8 }
Write-Log "START add-hosts.ps1"
Write-Log "hostsFile=$hostsFile backup=$backup"

$entries = @(
	"127.0.0.1 grafana.local.test",
	"127.0.0.1 chaos.local.test",
	"127.0.0.1 linkerd.local.test",
	"127.0.0.1 frontend.local.test"
)

# Read hosts file into memory
$raw = Get-Content -Path $hostsFile -ErrorAction Stop -Raw
$lines = if ($raw -eq '') { @() } else { $raw -split "\r?\n" }

$toAdd = @()
foreach ($entry in $entries) {
	$hostName = ($entry -split '\s+')[1]
	$present = $false
	foreach ($l in $lines) {
		if ($l -match "\b$([regex]::Escape($hostName))\b") { $present = $true; break }
	}
	if ($present) {
		Write-Output "OK: $hostName already present"
	} else {
		Write-Output "Will add: $entry"
		$toAdd += $entry
	}
}

if ($toAdd.Count -eq 0) {
	Write-Output "No changes required."
	Write-Log "No changes required. Exiting."
	Write-Log "END add-hosts.ps1"
	Write-Output "Log saved to: $logFile"
	exit 0
}

# Create a temporary file in the same directory to avoid cross-volume move issues
$tempDir = Split-Path -Parent $hostsFile
$tmp = Join-Path $tempDir ("hosts.tmp.$timestamp")

# Compose final content: original lines + blank line + additions
$finalLines = @()
if ($lines.Count -gt 0) { $finalLines += $lines }
$finalLines += ''
$finalLines += $toAdd

# Write final content to temp file using ASCII encoding
$finalLines | Out-File -FilePath $tmp -Encoding ASCII -Force

# Try to replace the hosts file with retries (handles 'file in use' transient locks)
$maxRetries = 6
$attempt = 0
while ($true) {
	try {
		Copy-Item -Path $tmp -Destination $hostsFile -Force
		break
	} catch {
		$attempt++
		if ($attempt -ge $maxRetries) {
			Write-Error "Failed to replace hosts file after $attempt attempts: $_"
			Remove-Item -Path $tmp -ErrorAction SilentlyContinue
			exit 1
		}
		Write-Output "File busy, retrying in 1s (attempt $attempt/$maxRetries)..."
		Start-Sleep -Seconds 1
	}
}

# Clean up temp file
Remove-Item -Path $tmp -ErrorAction SilentlyContinue

Write-Output "Hosts file updated (backup: $backup)."
Write-Log "Hosts file updated (backup: $backup)."
Write-Log "END add-hosts.ps1"
Write-Output "Log saved to: $logFile"

# flush DNS cache (best-effort)
try { ipconfig /flushdns | Out-Null } catch { }