#!/usr/bin/env bash
# Delete k3d cluster and remove hosts entries added by add-hosts.sh
# Usage: sudo ./cleanup-k3d-and-hosts.sh

set -euo pipefail
CLUSTER_NAME="gitops-chaos"
HOSTS_FILE="/etc/hosts"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Detect WSL (Linux running on Windows) so we can inform the user about where /etc/hosts will be modified
is_wsl=false
if [ -f /proc/version ]; then
  if grep -qi microsoft /proc/version 2>/dev/null; then
    is_wsl=true
  fi
fi
if [ -n "${WSL_DISTRO_NAME:-}" ] || [ -d /run/WSL ]; then
  is_wsl=true
fi

if [ "$is_wsl" = true ]; then
  echo "Environment detected: WSL (Linux on Windows)."
  echo "Note: modifying $HOSTS_FILE here will change the hosts inside the WSL instance only."
  echo "If you need the hostnames reachable from Windows apps/browsers too, run 'cleanup-k3d-and-hosts.ps1' as Administrator on the Windows host to update C:\\Windows\\System32\\drivers\\etc\\hosts."
fi

# Detect Windows-like environments (Git Bash / MSYS / Cygwin) and delegate to PowerShell
unameOut="$(uname -s 2>/dev/null || echo Unknown)"
case "${unameOut}" in
  MINGW*|MSYS*)
    PS_SCRIPT="$SCRIPT_DIR/cleanup-k3d-and-hosts.ps1"
    echo "Detected Git Bash / MSYS on Windows. Invoking Windows PowerShell as Administrator to perform cleanup..."
    # Convert the POSIX path to a Windows path for powershell. Prefer cygpath if available.
    if command -v cygpath >/dev/null 2>&1; then
      PS_WIN_PATH="$(cygpath -w "$PS_SCRIPT")"
    else
      # Fallback: try a simple conversion: /c/dir -> C:\dir and replace / with \\.
      PS_WIN_PATH="$(echo "$PS_SCRIPT" | sed -E 's#^/([a-zA-Z])/#\1:/#; s#/#\\\\#g')"
    fi
    # Use Start-Process -Wait so the caller waits for the elevated PowerShell to finish instead of returning immediately
    if command -v pwsh >/dev/null 2>&1; then
      pwsh -NoProfile -Command "Start-Process pwsh -ArgumentList \"-NoProfile -ExecutionPolicy Bypass -Command & { try { & '${PS_WIN_PATH}' } catch { Write-Host 'ERROR:'; Write-Host \$_; Read-Host 'Press ENTER to close'; exit 1 } }\" -Verb RunAs -Wait; exit \$LASTEXITCODE"
      exit $?
    elif command -v powershell.exe >/dev/null 2>&1; then
      powershell.exe -NoProfile -Command "Start-Process powershell.exe -ArgumentList \"-NoProfile -ExecutionPolicy Bypass -Command & { try { & '${PS_WIN_PATH}' } catch { Write-Host 'ERROR:'; Write-Host \$_; Read-Host 'Press ENTER to close'; exit 1 } }\" -Verb RunAs -Wait; exit \$LASTEXITCODE"
      exit $?
    else
      echo "PowerShell not found; please run cleanup-k3d-and-hosts.ps1 as Administrator on Windows"
      exit 2
    fi
    ;;
  CYGWIN*)
    PS_SCRIPT="$SCRIPT_DIR/cleanup-k3d-and-hosts.ps1"
    echo "Detected Cygwin on Windows. Invoking Windows PowerShell as Administrator to perform cleanup..."
    if command -v cygpath >/dev/null 2>&1; then
      PS_WIN_PATH="$(cygpath -w "$PS_SCRIPT")"
    else
      PS_WIN_PATH="$(echo "$PS_SCRIPT" | sed -E 's#^/([a-zA-Z])/#\1:/#; s#/#\\\\#g')"
    fi
    if command -v pwsh >/dev/null 2>&1; then
      pwsh -NoProfile -Command "Start-Process pwsh -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','${PS_WIN_PATH}' -Verb RunAs -Wait; exit \$LASTEXITCODE"
      exit $?
    elif command -v powershell.exe >/dev/null 2>&1; then
      powershell.exe -NoProfile -Command "Start-Process powershell.exe -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','${PS_WIN_PATH}' -Verb RunAs -Wait; exit \$LASTEXITCODE"
      exit $?
    else
      echo "PowerShell not found; please run cleanup-k3d-and-hosts.ps1 as Administrator on Windows"
      exit 2
    fi
    ;;
  Windows_NT)
    PS_SCRIPT="$SCRIPT_DIR/cleanup-k3d-and-hosts.ps1"
    echo "Detected native Windows environment. Please run the PowerShell cleanup script as Administrator: $PS_SCRIPT"
    exit 2
    ;;
  *)
    ;;
esac

# If we're not root on Unix-like systems, re-run with sudo
if [ "${unameOut}" != "MINGW" ] && [ "${unameOut}" != "MSYS" ] && [ "${unameOut}" != "CYGWIN" ] && [ "${unameOut}" != "Windows_NT" ]; then
  if [ "$(id -u)" -ne 0 ]; then
    if command -v sudo >/dev/null 2>&1; then
      echo "Re-running with sudo to modify $HOSTS_FILE"
      exec sudo bash "$0" "$@"
    else
      echo "This script needs root privileges to modify $HOSTS_FILE. Please run with sudo."
      exit 1
    fi
  fi
fi

HOSTS_TO_REMOVE=(
  "grafana.local.test"
  "chaos.local.test"
  "linkerd.local.test"
  "frontend.local.test"
)

# Delete k3d cluster if k3d exists
if command -v k3d >/dev/null 2>&1; then
  if k3d cluster list | grep -q "^${CLUSTER_NAME}\b"; then
    echo "Deleting k3d cluster: ${CLUSTER_NAME}"
    k3d cluster delete "${CLUSTER_NAME}" || echo "Failed to delete k3d cluster (continuing)"
  else
    echo "k3d cluster '${CLUSTER_NAME}' not found"
  fi
else
  echo "k3d not installed or not in PATH"
fi

# Remove host entries safely
if [ ! -w "$HOSTS_FILE" ]; then
  echo "Need sudo to modify $HOSTS_FILE"
  echo "Re-run with sudo"
  exit 1
fi

BACKUP_FILE="${HOSTS_FILE}.bak.$(date +%s)"
cp "$HOSTS_FILE" "$BACKUP_FILE"

echo "Backup of hosts file saved to: $BACKUP_FILE"

# Create a temp file without the entries to remove
TMPFILE=$(mktemp)
awk -v hosts="${HOSTS_TO_REMOVE[*]}" '
BEGIN {
  n = split(hosts, arr, " ")
  for (i=1;i<=n;i++) rm[arr[i]] = 1
}
{
  line = $0
  skip = 0
  for (h in rm) {
    pattern = "\\<" h "\\>"
    if (line ~ pattern) { skip = 1; break }
  }
  if (!skip) print $0
}
' "$HOSTS_FILE" > "$TMPFILE"

# Replace hosts file
mv "$TMPFILE" "$HOSTS_FILE"
chmod 644 "$HOSTS_FILE"

echo "Removed host entries: ${HOSTS_TO_REMOVE[*]}"

echo "Done."

# Remove the backup that was created for this cleanup run
if [ -f "$BACKUP_FILE" ]; then
  rm -f "$BACKUP_FILE" && echo "Removed cleanup backup: $BACKUP_FILE"
fi

exit 0

# Windows path: detect MSYS/Cygwin and invoke elevated PowerShell cleanup
MINGWMSYS="$(uname -s 2>/dev/null || echo Unknown)"
case "$MINGWMSYS" in
  MINGW*|MSYS*|CYGWIN*|Windows_NT)
    PS_SCRIPT="$SCRIPT_DIR/cleanup-k3d-and-hosts.ps1"
    if command -v pwsh >/dev/null 2>&1; then
      echo "Running Windows PowerShell cleanup elevated via pwsh..."
      pwsh -NoProfile -Command "Start-Process pwsh -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','$PS_SCRIPT' -Verb RunAs"
      exit $?
    elif command -v powershell.exe >/dev/null 2>&1; then
      echo "Running Windows PowerShell cleanup elevated via powershell.exe..."
      powershell.exe -NoProfile -Command "Start-Process powershell.exe -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','$PS_SCRIPT' -Verb RunAs"
      exit $?
    else
      echo "PowerShell not found; please run cleanup-k3d-and-hosts.ps1 as Administrator on Windows"
      exit 2
    fi
    ;;
  *)
    ;;
esac