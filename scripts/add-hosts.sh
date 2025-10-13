#!/usr/bin/env bash
# Cross-platform launcher: adds local.test host mappings if missing.
# Usage:
#   Linux/macOS/WSL: sudo ./add-hosts.sh
#   Windows (Git Bash): ./add-hosts.sh (will call PowerShell) - PowerShell must run elevated

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PS1="$SCRIPT_DIR/add-hosts.ps1"

# Detect WSL (Linux running on Windows) and warn user
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
  echo "Note: running this script in WSL will update WSL's /etc/hosts only."
  echo "To update the Windows host file for Windows apps/browsers, run the PowerShell script as Administrator on Windows: $(cygpath -w "$PS1" 2>/dev/null || echo "$PS1")"
fi

HOSTS_ENTRIES=(
  "127.0.0.1 grafana.local.test"
  "127.0.0.1 chaos.local.test"
  "127.0.0.1 linkerd.local.test"
  "127.0.0.1 frontend.local.test"
)

# Detect Windows/MSYS/Cygwin
unameOut="$(uname -s 2>/dev/null || echo Unknown)"
case "${unameOut}" in
  MINGW*|MSYS*)
    # prefer pwsh (PowerShell Core), fallback to powershell.exe
    echo "Detected Git Bash / MSYS on Windows. Invoking PowerShell as Administrator to perform host updates..."
    # Convert POSIX path to Windows path for PowerShell
    if command -v cygpath >/dev/null 2>&1; then
      PS_WIN_PATH="$(cygpath -w "$PS1")"
    else
      PS_WIN_PATH="$(echo "$PS1" | sed -E 's#^/([a-zA-Z])/#\1:/#; s#/#\\\\#g')"
    fi
    if command -v pwsh >/dev/null 2>&1; then
      pwsh -NoProfile -Command "Start-Process pwsh -ArgumentList \"-NoProfile -ExecutionPolicy Bypass -Command & { try { & '${PS_WIN_PATH}' } catch { Write-Host 'ERROR:'; Write-Host \$_; Read-Host 'Press ENTER to close'; exit 1 } }\" -Verb RunAs -Wait; exit \$LASTEXITCODE"
      exit $?
    elif command -v powershell.exe >/dev/null 2>&1; then
      powershell.exe -NoProfile -Command "Start-Process powershell.exe -ArgumentList \"-NoProfile -ExecutionPolicy Bypass -Command & { try { & '${PS_WIN_PATH}' } catch { Write-Host 'ERROR:'; Write-Host \$_; Read-Host 'Press ENTER to close'; exit 1 } }\" -Verb RunAs -Wait; exit \$LASTEXITCODE"
      exit $?
    else
      echo "Error: PowerShell not found. Please run the PS script manually as Administrator: $PS1" >&2
      exit 2
    fi
    ;;
  CYGWIN*)
    echo "Detected Cygwin on Windows. Invoking PowerShell as Administrator to perform host updates..."
    if command -v cygpath >/dev/null 2>&1; then
      PS_WIN_PATH="$(cygpath -w "$PS1")"
    else
      PS_WIN_PATH="$(echo "$PS1" | sed -E 's#^/([a-zA-Z])/#\1:/#; s#/#\\\\#g')"
    fi
    if command -v pwsh >/dev/null 2>&1; then
      pwsh -NoProfile -Command "Start-Process pwsh -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','${PS_WIN_PATH}' -Verb RunAs -Wait; exit \$LASTEXITCODE"
      exit $?
    elif command -v powershell.exe >/dev/null 2>&1; then
      powershell.exe -NoProfile -Command "Start-Process powershell.exe -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','${PS_WIN_PATH}' -Verb RunAs -Wait; exit \$LASTEXITCODE"
      exit $?
    else
      echo "Error: PowerShell not found. Please run the PS script manually as Administrator: $PS1" >&2
      exit 2
    fi
    ;;
  Windows_NT)
    echo "Detected native Windows environment. Please run the PowerShell script as Administrator: $PS1" >&2
    exit 2
    ;;
  *)
    HOSTS_FILE="/etc/hosts"
    if [ ! -r "$HOSTS_FILE" ]; then
      echo "Error: cannot read $HOSTS_FILE" >&2
      exit 1
    fi

    missing=()
    for entry in "${HOSTS_ENTRIES[@]}"; do
      hostname="$(printf "%s" "$entry" | awk '{print $2}')"
      # word-boundary safe check
      if grep -E -q "(^|[[:space:]])$hostname([[:space:]]|$)" "$HOSTS_FILE"; then
        printf "OK: %s present\n" "$hostname"
      else
        missing+=("$entry")
      fi
    done

    if [ "${#missing[@]}" -eq 0 ]; then
      echo "No changes required."
      exit 0
    fi

  BACKUP="${HOSTS_FILE}.bak.$(date +%s)"
  echo "Creating backup: $BACKUP"
  sudo cp "$HOSTS_FILE" "$BACKUP"

    echo "Appending missing entries to $HOSTS_FILE (requires sudo)..."
    TMP="$(mktemp)"
    for e in "${missing[@]}"; do printf "%s\n" "$e" >> "$TMP"; done
    sudo sh -c "cat '$TMP' >> '$HOSTS_FILE'"
    rm -f "$TMP"

    echo "Done. Backup saved at: $BACKUP"
    # Remove the interim backup file now that changes are applied
    if [ -f "$BACKUP" ]; then
      sudo rm -f "$BACKUP" && echo "Removed backup: $BACKUP"
    fi
    echo "You may need to flush DNS or restart your browser for changes to take effect."
    exit 0
    ;;
esac
