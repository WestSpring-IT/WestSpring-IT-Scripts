#!/bin/bash
# CybaAgent installer for macOS
# Downloads the CybaAgent zip, extracts, makes executable, clears quarantine, and runs the installer.

set -euo pipefail

# Configuration — set these values or pass as arguments.
# Usage: ./install_cyba_agent.sh <TOKEN> [SERVER]
# If TOKEN not supplied, edit CYBA_TOKEN below.

CYBA_URL="https://wsprodfileuksouth.blob.core.windows.net/clients/cyber_essentials/agents/cybaagent/CybaAgent-Mac.zip"
CYBA_INSTALL="sudo ./CybaAgent -i -t tt-cdf4e01b4e2d1e554abdc898032d6810-763e69d0561dcc06ca1e30678b9cad222d66209b090756302db74ef3bacb3439da3401ce64dab79e7d3840518b8b8fa84ed6369d5d2696b80a0daba350257cc94f2a5eac7bf785213b93184741e64db5b68c8d3e086d7fe3d7d2c92640e72322024c4b3da2b5089d3ce3e5426492a3b6c662c068a2e09cc2df6ee8f0b28d6e16 -s https://westspring.cybaops.com/"#"{[Cyba_Install_Command]}"
#CYBA_TOKEN="{[Cyba_Token]}"
#CYBA_SERVER="https://westspring.cybaops.com/"

if [[ $# -ge 1 && "$1" != "" ]]; then
    CYBA_TOKEN="$1"
fi
if [[ $# -ge 2 && "$2" != "" ]]; then
    CYBA_SERVER="$2"
fi

# If user passed a third arg, treat it as the raw install command to run (single quoted if complex)
if [[ $# -ge 3 && -n "$3" ]]; then
    CYBA_INSTALL="$3"
fi

# If the user provided a full installer command (e.g.:
# sudo ./CybaAgent -i -t <token> -s https://server/ ) then extract token/server via regex
if [[ $# -ge 1 ]]; then
    Cyba_Install_Command="$*"
    if [[ "$Cyba_Install_Command" =~ CybaAgent ]] && [[ "$Cyba_Install_Command" =~ -t[[:space:]]*([^[:space:]]+) ]]; then
        # If the user passed a quoted full install command as the first argument, capture it as CYBA_INSTALL
        if [[ $# -eq 1 ]]; then
            CYBA_INSTALL="$Cyba_Install_Command"
        fi
        CYBA_TOKEN="${BASH_REMATCH[1]}"
        # If -s provided, capture that too
        if [[ "$Cyba_Install_Command" =~ -s[[:space:]]*([^[:space:]]+) ]]; then
            CYBA_SERVER="${BASH_REMATCH[1]}"
        fi
        echo "Parsed token and server from supplied installer command."
        mask_token="${CYBA_TOKEN:0:8}..."
        echo "Token: $mask_token"
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

if [[ -z "$CYBA_TOKEN" || "$CYBA_TOKEN" == "{[Cyba_Token]}" ]]; then
    echo "ERROR: Cyba token is not set. Provide token as first argument or edit the script variable CYBA_TOKEN."
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

# Ensure we have privileges for installer execution
RUN_CMD=""
if [[ $(id -u) -ne 0 ]]; then
    echo "Installer requires elevated privileges; using sudo to run the agent installer. You may be prompted for your password."
    RUN_CMD="sudo"
fi

echo "Running installer..."

# If user supplied a full install command, run that from the agent directory.
AGENT_DIR="$(dirname "$AGENT_PATH")"
if [[ -n "$CYBA_INSTALL" ]]; then
    echo "Using user-specified install command: $CYBA_INSTALL"
    pushd "$AGENT_DIR" >/dev/null || exit 1
    # If command doesn't start with sudo and we are not root, prefix with sudo
    if [[ $(id -u) -ne 0 && ! "$CYBA_INSTALL" =~ ^sudo ]]; then
        EXEC_CMD="sudo $CYBA_INSTALL"
    else
        EXEC_CMD="$CYBA_INSTALL"
    fi
    echo "Executing: $EXEC_CMD"
    if eval "$EXEC_CMD"; then
        echo "CybaAgent installer completed successfully (via user command)."
    else
        echo "CybaAgent installer failed (user command) with exit code $?" >&2
        popd >/dev/null
        exit 1
    fi
    popd >/dev/null
else
    echo "$RUN_CMD $AGENT_PATH -i -t <token hidden> -s $CYBA_SERVER"
    # Execute installer directly
    if $RUN_CMD "$AGENT_PATH" -i -t "$CYBA_TOKEN" -s "$CYBA_SERVER"; then
        echo "CybaAgent installer completed successfully."
    else
        echo "CybaAgent installer failed with exit code $?" >&2
        exit 1
    fi
fi

echo "Cleaning up temporary files..."
rm -rf "$TMPDIR"

echo "=============================="
echo "CybaAgent installation complete."
echo "=============================="

exit 0