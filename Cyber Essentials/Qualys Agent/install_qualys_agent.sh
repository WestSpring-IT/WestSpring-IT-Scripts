#!/bin/bash
# Qualys Cloud Agent Installer — Universal (Intel + Apple Silicon) — Atera Safe
# v2025.11

set -e

# ---- CONFIGURATION ----
# Replace this with your actual activation string from Qualys / CybaVerse
InstallerString="{[InstallerString]}"
# -----------------------

echo "=============================="
echo "Starting Qualys Cloud Agent installation"
echo "=============================="

# ---- Parse activation info ----
activationID=$(echo "$InstallerString" | grep -o 'ActivationId=[^ ]*' | cut -d'=' -f2)
customerID=$(echo "$InstallerString" | grep -o 'CustomerId=[^ ]*' | cut -d'=' -f2)
webServiceUri=$(echo "$InstallerString" | grep -o 'ServerUri=[^ ]*' | cut -d'=' -f2)

echo "Activation ID: $activationID"
echo "Customer ID: $customerID"
echo "Web Service URI: $webServiceUri"

# ---- Detect true hardware architecture ----
if [[ "$(sysctl -n hw.optional.arm64)" == "1" ]]; then
    TRUE_ARCH="arm64"
else
    TRUE_ARCH="x86_64"
fi

echo "Reported shell architecture: $(uname -m)"
echo "Detected hardware architecture: $TRUE_ARCH"
echo "CPU model: $(sysctl -n machdep.cpu.brand_string)"

# ---- Choose proper installer ----
if [[ "$TRUE_ARCH" == "arm64" ]]; then
    INSTALLER_URL="https://wsprodfileuksouth.blob.core.windows.net/clients/qualys-agent-installers/QualysCloudAgent-MAC-ARM.pkg"
    echo "Detected Apple Silicon (ARM64). Will use ARM installer."
else
    INSTALLER_URL="https://wsprodfileuksouth.blob.core.windows.net/clients/qualys-agent-installers/QualysCloudAgent-MAC-INTEL.pkg"
    echo "Detected Intel (x86_64). Will use Intel installer."
fi

# ---- Download installer ----
echo "Downloading Qualys installer from:"
echo "$INSTALLER_URL"
curl -L -o /tmp/QualysCloudAgent.pkg "$INSTALLER_URL"

# ---- Run installer ----
echo "Installing Qualys Cloud Agent..."
if [[ "$TRUE_ARCH" == "arm64" ]]; then
    echo "Running installer under ARM64 mode..."
    /usr/bin/arch -arm64 /usr/sbin/installer -pkg /tmp/QualysCloudAgent.pkg -target /
else
    echo "Running installer natively (Intel)..."
    /usr/sbin/installer -pkg /tmp/QualysCloudAgent.pkg -target /
fi

# ---- Activation ----
echo "Activating Qualys Cloud Agent..."
if [[ "$TRUE_ARCH" == "arm64" ]]; then
    /usr/bin/arch -arm64 /Applications/QualysCloudAgent.app/Contents/MacOS/qualys-cloud-agent.sh \
        ActivationId=$activationID \
        CustomerId=$customerID \
        ServerUri=$webServiceUri
else
    /Applications/QualysCloudAgent.app/Contents/MacOS/qualys-cloud-agent.sh \
        ActivationId=$activationID \
        CustomerId=$customerID \
        ServerUri=$webServiceUri
fi

# ---- Verify installation ----
if [[ -d "/Applications/QualysCloudAgent.app" ]]; then
    echo "Qualys Cloud Agent successfully installed."
else
    echo "Istallation failed — Qualys app not found in /Applications."
    exit 1
fi

echo "=============================="
echo "Qualys Cloud Agent installation and activation complete."
echo "=============================="

exit 0