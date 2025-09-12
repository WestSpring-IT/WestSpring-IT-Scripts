#!/bin/bash
# Actvation command
InstallerString="Full Insatller String from CybaVerse"

# Split and extract values
activationID=$(echo "$InstallerString" | grep -o 'ActivationId=[^ ]*' | cut -d'=' -f2)
customerID=$(echo "$InstallerString" | grep -o 'CustomerId=[^ ]*' | cut -d'=' -f2)
webServiceUri=$(echo "$InstallerString" | grep -o 'ServerUri=[^ ]*' | cut -d'=' -f2)

# Output for verification
echo "Activation ID: $activationID"
echo "Customer ID: $customerID"
echo "Web Service URI: $webServiceUri"

# Detect system architecture
ARCH=$(uname -m)
if [[ "$ARCH" == "arm64" ]]; then
    INSTALLER_URL="https://wsprodfileuksouth.blob.core.windows.net/clients/qualys-agent-installers/QualysCloudAgent-MAC-ARM.pkg"
    echo "Detected ARM architecture."
elif [[ "$ARCH" == "x86_64" ]]; then
    INSTALLER_URL="https://wsprodfileuksouth.blob.core.windows.net/clients/qualys-agent-installers/QualysCloudAgent-MAC-INTEL.pkg"
    echo "Detected Intel architecture."
else
    echo "Unsupported architecture: $ARCH"
    exit 1
fi

# Download the installer
echo "Downloading installer from $INSTALLER_URL..."
#curl -o QualysCloudAgent.pkg "$INSTALLER_URL"

# Install the package
echo "Installing Qualys Cloud Agent..."
sudo installer -pkg ./QualysCloudAgent.pkg -target /

# Activate the agent
echo "Activating Qualys Cloud Agent..."
sudo /Applications/QualysCloudAgent.app/Contents/MacOS/qualys-cloud-agent.sh \
    ActivationId=$activationID \
    CustomerId=$customerID \
    ServerUri=$webServiceUri

echo "Installation and activation complete."