#!/bin/bash

# Usage: configure_maclogon.sh [--pkg /path/to/pkg] [--ikey IKEY] [--skey SKEY] [--api HOST] [--fail-open true|false] [--smartcard-bypass true|false] [--auto-push true|false] [--install true|false]
# If any of ikey/skey/api are omitted they will be prompted for interactively.
# You can hardcode defaults for IKEY, SKEY, and API by editing the DEFAULT_* variables below.

# Hardcoded defaults. Set these to your values to avoid interactive prompts.
# WARNING: Storing secrets in plaintext in scripts can be a security risk.
# Consider using environment variables or secure storage when possible.
DEFAULT_IKEY="{[DUO_INTEGRATION_KEY]}"
DEFAULT_SKEY="{[DUO_SECRET_KEY]}"
DEFAULT_API="{[DUO_API_HOST]}"

show_usage() {
    cat <<EOF
Usage: $0 [options]

Options:
    --version-override VERSION     Specify version string for output package (default: latest)
    --pkg PATH                     Path to MacLogon-NotConfigured-x.x.pkg (optional)
    --ikey IKEY                    Integration key (IKEY)
    --skey SKEY                    Secret key (SKEY)
    --api HOST                     API hostname
    --fail-open true|false         Fail open (default: false)
    --smartcard-bypass true|false  Smartcard bypass (default: false)
    --auto-push true|false         Auto push (default: true)
    --install true|false           Install after configuring (default: true)
    -h, --help                     Show this help

Defaults can be set by editing DEFAULT_IKEY, DEFAULT_SKEY, DEFAULT_API at the top of this script.
See https://duo.com/docs/macos for documentation.
EOF
}

validate_bool() {
    local varname="$1"
    local val="$2"
    if ! [[ "$val" == "true" || "$val" == "false" ]]; then
        echo "Invalid --${varname} value: $val. Expected 'true' or 'false'."
        exit 1
    fi
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --version-override) version="$2"; shift 2;;
        --pkg) pkg_path="$2"; shift 2;;
        --ikey|-i) ikey="$2"; shift 2;;
        --skey|-k) skey="$2"; shift 2;;
        --api|--api-hostname|-a) api_hostname="$2"; shift 2;;
        --fail-open) fail_open="$2"; shift 2;;
        --smartcard-bypass) smartcard_bypass="$2"; shift 2;;
        --auto-push) auto_push="$2"; shift 2;;
        --install) install_pkg="$2"; shift 2;;
        -h|--help) show_usage; exit 0;;
        *) echo "Unknown argument: $1"; show_usage; exit 1;;
    esac
done

# Validate and set version
if [[ -n "${version:-}" ]]; then
    if [[ ! "${version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "Invalid version format: '${version}'. Expected format: x.x.x (e.g. 2.0.5)"
        exit 1
    fi
    echo "Using version override: ${version}"
    DUO_URL="https://dl.duosecurity.com/MacLogon-${version}.zip"
else
    DUO_URL="https://dl.duosecurity.com/MacLogon-latest.zip"
fi

# Download DUO MacLogon package if not already present
echo "Downloading Duo MacLogon package..."
curl -LO "${DUO_URL}"
unzip -nq "$(basename "${DUO_URL}")"

# Determine package path
if [[ -n "${pkg_path:-}" ]]; then
    # Use provided package path
    :
else
    # Find package in current directory
    pkgs=( $(find ./MacLogon* -name 'MacLogon-NotConfigured-*.pkg' 2>/dev/null) )
    num_pkgs=${#pkgs[@]}

    if [[ "$num_pkgs" -eq 0 ]]; then
        echo "No packages found. Please provide a package via --pkg."
        exit 1
    elif [[ "$num_pkgs" -gt 1 ]]; then
        echo "Multiple packages found. Please specify one via --pkg."
        echo "Usage: $0 --pkg /path/to/MacLogon-NotConfigured-x.x.pkg"
        exit 1
    fi
    pkg_path="${pkgs[0]}"
fi

if [[ ! -f "${pkg_path}" ]]; then
    echo "No package found at $pkg_path. Exiting."
    exit 1
fi

# Prompt for required values if not provided
ikey="${ikey:-$DEFAULT_IKEY}"
skey="${skey:-$DEFAULT_SKEY}"
api_hostname="${api_hostname:-$DEFAULT_API}"

if [[ -z "${ikey:-}" ]]; then
    read -rp "Enter ikey: " ikey
fi

if [[ -z "${skey:-}" ]]; then
    read -rp "Enter skey: " skey
fi

if [[ -z "${api_hostname:-}" ]]; then
    read -rp "Enter API Hostname: " api_hostname
fi

# Validate and set boolean options with defaults
if [[ -n "${fail_open:-}" ]]; then
    validate_bool "fail-open" "$fail_open"
else
    fail_open="false"
    echo "Fail open not provided; defaulting to 'false'."
fi

if [[ -n "${smartcard_bypass:-}" ]]; then
    validate_bool "smartcard-bypass" "$smartcard_bypass"
else
    smartcard_bypass="false"
    echo "Smartcard bypass not provided; defaulting to 'false'."
fi

if [[ -n "${auto_push:-}" ]]; then
    validate_bool "auto-push" "$auto_push"
else
    auto_push="true"
    echo "Auto-push not provided; defaulting to 'true'."
fi

if [[ -n "${install_pkg:-}" ]]; then
    validate_bool "install" "$install_pkg"
else
    install_pkg="true"
    echo "Install not provided; defaulting to 'true'."
fi

# Configure package
pkg_dir=$(dirname "${pkg_path}")
pkg_name=$(basename "${pkg_path}" | awk -F\. '{print $1 "." $2}')
tmp_path="/tmp/${pkg_name}"

echo -e "\nModifying ${pkg_path}...\n"

pkgutil --expand "${pkg_path}" "${tmp_path}"

echo "Updating config.plist with provided values..."

defaults write "${tmp_path}/Scripts/config.plist" ikey -string "${ikey}"
defaults write "${tmp_path}/Scripts/config.plist" skey -string "${skey}"
defaults write "${tmp_path}/Scripts/config.plist" api_hostname -string "${api_hostname}"
defaults write "${tmp_path}/Scripts/config.plist" fail_open -bool "${fail_open}"
defaults write "${tmp_path}/Scripts/config.plist" smartcard_bypass -bool "${smartcard_bypass}"
defaults write "${tmp_path}/Scripts/config.plist" auto_push -bool "${auto_push}"
defaults write "${tmp_path}/Scripts/config.plist" twofa_unlock -bool false
plutil -convert xml1 "${tmp_path}/Scripts/config.plist"

out_pkg="${pkg_dir}/MacLogon-${version}.pkg"
echo -e "\nFinalizing package, saving as ${out_pkg}..."
pkgutil --flatten "${tmp_path}" "${out_pkg}"

echo "Cleaning up temp files..."
rm -rf "${tmp_path}"

echo -e "\nDone! The package ${out_pkg} has been configured."

# Install if requested
if [[ "$install_pkg" == "true" ]]; then
    echo -e "\nInstalling MacLogon package..."
    sudo installer -pkg "${out_pkg}" -target /
    if [[ $? -eq 0 ]]; then
        echo "MacLogon package installed successfully."
    else
        echo "MacLogon package installation failed. Exit code: $?"
        exit 1
    fi
fi

exit 0