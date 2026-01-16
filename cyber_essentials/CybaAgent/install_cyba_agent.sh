#!/bin/bash
# CybaAgent installer for macOS
# Downloads the CybaAgent zip, extracts, makes executable, clears quarantine, and runs the installer.

set -euo pipefail

# Configuration — set these values or pass the installer command using --install-command
# Usage: ./install_cyba_agent.sh --install-command '<full install command>'
# Example:
# ./install_cyba_agent.sh --install-command 'sudo ./CybaAgent -i -t <token> -s https://westspring.cybaops.com/'
# For backward compatibility you can still pass the full command as a single quoted positional argument.

CYBA_URL="https://wsprodfileuksouth.blob.core.windows.net/clients/cyber_essentials/agents/cybaagent/CybaAgent-Mac.zip"
# Allow the RMM to replace the placeholder {[CYBA_INSTALL_COMMAND]} directly in the script
# Precedence: 1) CLI `--install-command`, 2) environment variable `CYBA_INSTALL`, 3) hardcoded RMM placeholder
CYBA_INSTALL="${CYBA_INSTALL:-{[CYBA_INSTALL_COMMAND]}}"

# Parse arguments — prefer --install-command; positional single-argument fallback kept for backward compatibility
function usage() {
    cat <<'USAGE' >&2
Usage: $0 --install-command '<full install command>'
Example: $0 --install-command 'sudo ./CybaAgent -i -t <token> -s https://westspring.cybaops.com/'
USAGE
}

# Parse long option --install-command and also accept positional fallback
while [[ $# -gt 0 ]]; do
    case "$1" in
        --install-command)
            shift
            if [[ $# -eq 0 ]]; then
                echo "ERROR: --install-command requires an argument" >&2
                usage; exit 1
            fi
            CYBA_INSTALL="$1"
            shift
            ;;
        --install-command=*)
            CYBA_INSTALL="${1#*=}"
            shift
            ;;
        -h|--help)
            usage; exit 0
            ;;
        *)
            # positional fallback: capture remaining args as the install command (single-arg style)
            if [[ -z "${CYBA_INSTALL:-}" ]]; then
                CYBA_INSTALL="$*"
                break
            else
                shift
            fi
            ;;
    esac
done

# Extract token/server for display (if present) — used only for masking/logging
if [[ -n "$CYBA_INSTALL" && "$CYBA_INSTALL" =~ CybaAgent ]]; then
    if [[ "$CYBA_INSTALL" =~ -t[[:space:]]*([^[:space:]]+) ]]; then
        CYBA_TOKEN="${BASH_REMATCH[1]}"
    fi
    if [[ "$CYBA_INSTALL" =~ -s[[:space:]]*([^[:space:]]+) ]]; then
        CYBA_SERVER="${BASH_REMATCH[1]}"
    fi
    echo "Parsed token and server from supplied installer command."
    if [[ -n "${CYBA_TOKEN:-}" ]]; then
        mask_token="${CYBA_TOKEN:0:8}..."
        echo "Token: $mask_token"
    fi
    if [[ -n "${CYBA_SERVER:-}" ]]; then
        echo "Server: $CYBA_SERVER"
    fi
fi

TMPDIR="/tmp/cybaagent_install_$(date +%s)"
mkdir -p "$TMPDIR"

echo "=============================="
echo "CybaAgent installation"
echo "Download URL: $CYBA_URL"
echo "Server: $CYBA_SERVER"
echo "Temp dir: $TMPDIR"
echo "=============================="

## Detect missing installer command or an unreplaced RMM placeholder
if [[ -z "$CYBA_INSTALL" || "$CYBA_INSTALL" =~ \{\[.*INSTALL.*\]\} ]]; then
    echo "ERROR: CYBA_INSTALL not provided. Provide the full installer command via --install-command, environment variable CYBA_INSTALL, or have your RMM replace {[CYBA_INSTALL_COMMAND]} in the script." >&2
    exit 1
fi

ZIPPATH="$TMPDIR/CybaAgent-Mac.zip"
echo "Downloading CybaAgent..."
curl -fsSL -o "$ZIPPATH" "$CYBA_URL"

echo "Extracting archive..."
unzip -o "$ZIPPATH" -d "$TMPDIR" >/dev/null

# Locate the CybaAgent executable
AGENT_PATH="$(find "$TMPDIR" -type f -name 'CybaAgent' -print -quit || true)"
if [[ -z "$AGENT_PATH" ]]; then
    echo "ERROR: CybaAgent executable not found inside the zip." >&2
    ls -la "$TMPDIR"
    exit 1
fi

echo "Found agent: $AGENT_PATH"

echo "Adding executable permission..."
chmod +x "$AGENT_PATH"

echo "Clearing quarantine attribute..."
xattr -rd com.apple.quarantine "$AGENT_PATH" || true

# Prepare for installer execution (we will require a full install command via CYBA_INSTALL)
# If needed, sudo will be prefixed when executing the provided command (unless it already starts with sudo)

echo "Running installer..."

# If user supplied a full install command, run that from the agent directory.
AGENT_DIR="$(dirname "$AGENT_PATH")"
if [[ -n "$CYBA_INSTALL" ]]; then
    pushd "$AGENT_DIR" >/dev/null || exit 1

# Prepare execution command; prefix sudo if needed and not already present
EXEC_CMD="$CYBA_INSTALL"
if [[ $(id -u) -ne 0 && ! "$EXEC_CMD" =~ ^sudo ]]; then
    EXEC_CMD="sudo $EXEC_CMD"
fi

# Mask token in the logged command if present
mask_exec_cmd="$CYBA_INSTALL"
if [[ -n "${CYBA_TOKEN:-}" ]]; then
    mask_exec_cmd="${mask_exec_cmd//$CYBA_TOKEN/${CYBA_TOKEN:0:8}...}"
fi

echo "Executing: $mask_exec_cmd"
if eval "$EXEC_CMD"; then
    echo "CybaAgent installer completed successfully."
else
    rc=$?
    echo "CybaAgent installer failed with exit code $rc" >&2
    popd >/dev/null
    exit $rc
fi
popd >/dev/null
fi
# Fallback removed — the script requires a single installer command provided in CYBA_INSTALL

echo "Cleaning up temporary files..."
rm -rf "$TMPDIR"

echo "=============================="
echo "CybaAgent installation complete."
echo "=============================="

exit 0