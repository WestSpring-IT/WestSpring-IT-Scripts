#!/bin/bash

# Usage, this script can either be run: 
## Interactivly: configure_maclogon.sh [--pkg /path/to/pkg] [--ikey IKEY] [--skey SKEY] [--api HOST] [--fail-open true|false] [--smartcard-bypass true|false] [--auto-push true|false] [--install true|false]
## Non-interactively: Configure the DEFAULT_* variables near the top of this script, then run without any arguments.
# If any of ikey/skey/api are omitted they will be prompted for interactively.
# Boolean options can be provided or will be prompted (with defaults where appropriate).

# Allows the overriding of the version to download and use. If not provided, latest version is used.
version=""

# Hardcoded defaults. Set these to your values to avoid interactive prompts. Any values parsed interactivly or via CLI will override these.
# WARNING: Storing secrets in plaintext in scripts can be a security risk. Consider
# using environment variables or secure storage when possible.
DEFAULT_IKEY=""
DEFAULT_SKEY=""
DEFAULT_API=""
DEFAULT_FAIL_OPEN="true"
DEFAULT_SMARTCARD_BYPASS="false"
DEFAULT_AUTO_PUSH="true"
DEFAULT_INSTALL="true"

# echo "Duo Security Mac Logon configuration tool v${version}."
# echo "See https://duo.com/docs/macos for documentation"

read_bool() {
    local bool_val
    read -r bool_val
    while ! [[ "$bool_val" == "true" || "$bool_val" == "false" ]]; do
        read -rp "Invalid value. Enter true or false: " bool_val
    done
    echo "$bool_val"
}

read_bool_default_false() {
    local bool_val
    read -r bool_val
    while ! [[ -z "$bool_val" ]] && ! [[ "$bool_val" == "true" || "$bool_val" == "false" ]]; do
        read -rp "Invalid value. Enter true or false or leave it empty for false: " bool_val
    done
    if [[ -z "$bool_val" ]]; then
        echo "false"
    else
        echo "$bool_val"
    fi
}

show_usage() {s
    cat <<EOF
Usage: $0 [options]

Options:
    --version-override VERSION     Specify version string for output package (default: latest)
    --pkg PATH                     Path to MacLogon-NotConfigured-x.x.pkg (optional)
    (Defaults can be set by editing DEFAULT_IKEY, DEFAULT_SKEY, DEFAULT_API near the top of this script.)
    --ikey IKEY                    Integration key (IKEY)
    --skey SKEY                    Secret key (SKEY)
    --api HOST                     API hostname
    --fail-open true|false         Fail open (default: false)
    --smartcard-bypass true|false  Smartcard bypass (default: false)
    --auto-push true|false         Auto push (default: true)
    --install true|false           Install after configuring (default: false)
    -h, --help                     Show this help
EOF
}

# Track whether values were explicitly provided on the CLI so defaults don't override them
ikey_provided=false
skey_provided=false
api_provided=false
fail_open_provided=false
smartcard_bypass_provided=false
auto_push_provided=false
install_pkg_provided=false
pkg_provided=false
version_override_provided=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --version-override) version="$2"; version_override_provided=true; shift 2;;
        --pkg) pkg_path="$2"; pkg_provided=true; shift 2;;
        --ikey|-i) ikey="$2"; ikey_provided=true; shift 2;;
        --skey|-k) skey="$2"; skey_provided=true; shift 2;;
        --api|--api-hostname|-a) api_hostname="$2"; api_provided=true; shift 2;;
        --fail-open) fail_open="$2"; fail_open_provided=true; shift 2;;
        --smartcard-bypass) smartcard_bypass="$2"; smartcard_bypass_provided=true; shift 2;;
        --auto-push) auto_push="$2"; auto_push_provided=true; shift 2;;
        --install) install_pkg="$2"; install_pkg_provided=true; shift 2;;
        -h|--help) show_usage; exit 0;;
        *) echo "Unknown argument: $1"; show_usage; exit 1;;
    esac
done


if [[ -n "${version:-}" ]]; then
# validate version is in x.x.x format
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
WORKING_DIR="/Users/Shared/"
cd "$WORKING_DIR"
curl -LO "${DUO_URL}"
unzip -nq "$(basename "${DUO_URL}")"

# if a package was passed in, always use it
if [[ -n "${pkg_path:-}" ]]; then
    :
else
    # otherwise try to find the default package in this dir
    pkgs=( $(find ./MacLogon* -name 'MacLogon-NotConfigured-*.pkg') )
    num_pkgs=${#pkgs[@]}

    if [[ "$num_pkgs" -eq "1" ]]; then
        pkg_path=${pkgs[0]}
    elif [[ "$num_pkgs" -eq "0" ]]; then
        echo "No packages found. Please provide a package via --pkg."
        exit 1
    else
        echo "Multiple packages found. Please specify one via --pkg."
        echo "Usage: configure_maclogon.sh --pkg /path/to/MacLogon-NotConfigured-x.x.pkg"
        exit 1
    fi
fi

if [ ! -f "${pkg_path}" ]; then
    echo "No package found at $pkg_path. Exiting."
    exit 1
fi

# Prompt for required values if not provided
# Apply hardcoded defaults (if no flags provided; flags override defaults)
ikey="${ikey:-$DEFAULT_IKEY}"
skey="${skey:-$DEFAULT_SKEY}"
api_hostname="${api_hostname:-$DEFAULT_API}"

# Ensure boolean defaults are set so we can report effective values
fail_open="${fail_open:-$DEFAULT_FAIL_OPEN}"
smartcard_bypass="${smartcard_bypass:-$DEFAULT_SMARTCARD_BYPASS}"
auto_push="${auto_push:-$DEFAULT_AUTO_PUSH}"
install_pkg="${install_pkg:-$DEFAULT_INSTALL}"

# Report which values are in effect and whether they came from CLI or DEFAULTs
if [[ "$ikey_provided" == "true" ]]; then
    echo "Using ikey from CLI (provided): ${ikey}" >&2
elif [[ -n "${DEFAULT_IKEY}" ]]; then
    echo "Using ikey from DEFAULT_IKEY (script default)." >&2
else
    echo "ikey not provided; will be prompted interactively if needed." >&2
fi
if [[ "$skey_provided" == "true" ]]; then
    echo "Using skey from CLI (provided)." >&2
elif [[ -n "${DEFAULT_SKEY}" ]]; then
    echo "Using skey from DEFAULT_SKEY (script default)." >&2
else
    echo "skey not provided; will be prompted interactively if needed." >&2
fi
if [[ "$api_provided" == "true" ]]; then
    echo "Using API hostname from CLI (provided): ${api_hostname}" >&2
elif [[ -n "${DEFAULT_API}" ]]; then
    echo "Using API hostname from DEFAULT_API (script default): ${DEFAULT_API}" >&2
else
    echo "API hostname not provided; will be prompted interactively if needed." >&2
fi
if [[ "$fail_open_provided" == "true" ]]; then
    echo "Using fail_open from CLI: ${fail_open}" >&2
else
    echo "Using fail_open default: ${fail_open}" >&2
fi
if [[ "$smartcard_bypass_provided" == "true" ]]; then
    echo "Using smartcard_bypass from CLI: ${smartcard_bypass}" >&2
else
    echo "Using smartcard_bypass default: ${smartcard_bypass}" >&2
fi
if [[ "$auto_push_provided" == "true" ]]; then
    echo "Using auto_push from CLI: ${auto_push}" >&2
else
    echo "Using auto_push default: ${auto_push}" >&2
fi
if [[ "$install_pkg_provided" == "true" ]]; then
    echo "Using install flag from CLI: ${install_pkg}" >&2
else
    echo "Using install default: ${install_pkg}" >&2
fi

if [[ -z "${ikey:-}" ]]; then
    echo -n "Enter ikey: "
    read -r ikey
fi

if [[ -z "${skey:-}" ]]; then
    echo -n "Enter skey: "
    read -r skey
fi

if [[ -z "${api_hostname:-}" ]]; then
    echo -n "Enter API Hostname: "
    read -r api_hostname
fi

# Validate/handle boolean args or prompt if missing
validate_bool_or_prompt() {
    local varname="$1"; local prompt_fn="$2"; local default_fn="$3"
    local val="${!varname}"
    if [[ -n "$val" ]]; then
        if ! [[ "$val" == "true" || "$val" == "false" ]]; then
            echo "Invalid value for $varname: $val. Expected true or false."
            exit 1
        fi
    else
        # call prompt function (pass through)
        if [[ "$prompt_fn" == "read_bool" ]]; then
            echo -n "Should ${varname//_/ } (true or false): "
            read -r tmp
            val=$(read_bool <<<"$tmp")
        else
            # default_false variant
            echo -n "Should ${varname//_/ } (true or false) [default: false]: "
            read -r tmp
            val=$(read_bool_default_false <<<"$tmp")
        fi
        eval "$varname='$val'"
    fi
}

# For fail_open and smartcard_bypass default to false when omitted
if [[ -n "${fail_open:-}" ]]; then
    if ! [[ "$fail_open" == "true" || "$fail_open" == "false" ]]; then
        echo "Invalid --fail-open value: $fail_open"
        exit 1
    fi
else
    # Default to false if the flag is omitted
    fail_open="false"
    echo "Fail open not provided; defaulting to 'false'."
fi

if [[ -n "${smartcard_bypass:-}" ]]; then
    if ! [[ "$smartcard_bypass" == "true" || "$smartcard_bypass" == "false" ]]; then
        echo "Invalid --smartcard-bypass value: $smartcard_bypass"
        exit 1
    fi
else
    # Default to false if the flag is omitted
    smartcard_bypass="false"
    echo "Smartcard bypass not provided; defaulting to 'false'."
fi

# auto_push: if provided validate; otherwise default to true
if [[ -n "${auto_push:-}" ]]; then
    if ! [[ "$auto_push" == "true" || "$auto_push" == "false" ]]; then
        echo "Invalid --auto-push value: $auto_push"
        exit 1
    fi
else
    # Default auto_push to true when omitted
    auto_push="true"
    echo "Auto-push not provided; defaulting to 'true'."
fi

pkg_dir=$(dirname "${pkg_path}")
pkg_name=$(basename "${pkg_path}" | awk -F\. '{print $1 "." $2}')
tmp_path="/tmp/${pkg_name}"

echo -e "\nModifying ${pkg_path}...\n"

pkgutil --expand "${pkg_path}" "${tmp_path}"

echo -e "Updating config.plist ikey, skey, api_hostname, fail_open, smartcard_bypass, and auto_push config...\n"

defaults write "${tmp_path}"/Scripts/config.plist ikey -string "${ikey}"
defaults write "${tmp_path}"/Scripts/config.plist skey -string "${skey}"
defaults write "${tmp_path}"/Scripts/config.plist api_hostname -string "${api_hostname}"
defaults write "${tmp_path}"/Scripts/config.plist fail_open -bool "${fail_open}"
defaults write "${tmp_path}"/Scripts/config.plist smartcard_bypass -bool "${smartcard_bypass}"
defaults write "${tmp_path}"/Scripts/config.plist auto_push -bool "${auto_push}"
defaults write "${tmp_path}"/Scripts/config.plist twofa_unlock -bool false
plutil -convert xml1 "${tmp_path}/Scripts/config.plist"

out_pkg="${pkg_dir}/MacLogon-${version}.pkg"
echo -e "Finalizing package, saving as ${out_pkg}\n"
pkgutil --flatten "${tmp_path}" "${out_pkg}"

echo -e "Cleaning up temp files...\n"
rm -rf "${tmp_path}"

if [[ -n "${install_pkg:-}" ]]; then
    if ! [[ "$install_pkg" == "true" || "$install_pkg" == "false" ]]; then
        echo "Invalid --auto-push value: $install_pkg"
        exit 1
    fi
else
    # Default auto_push to true when omitted
    install_pkg="true"
    echo "Install not provided; defaulting to 'true'."
fi

echo -e "Done! The package ${out_pkg} has been configured for your use."

if [[ "$install_pkg" == "true" ]]; then
    echo -e "\nInstalling MacLogon package...\n"
    sudo installer -pkg "${out_pkg}" -target /
    if [[ $? -eq 0 ]]; then
        echo -e "MacLogon package installed successfully."
    else
        echo -e "MacLogon package installation failed. Exit code: $?"
        exit 1
    fi
fi
exit 0