#!/bin/sh
echo "WSA Mac install script"

# Default values
DEFAULT_WORKDIR="$(mktemp -d /tmp/webroot_edr_install.XXXXXX)"
DEFAULT_PKG="/tmp/WSAMAC.pkg"
DEFAULT_SILENT="true"
DEFAULT_KEYCODE=""
DEFAULT_LANGUAGE="en"
DEFAULT_PROXYAUTH=""
DEFAULT_PROXYHOST=""
DEFAULT_PROXYPORT=""
DEFAULT_PROXYUSER=""
DEFAULT_PROXYPASS=""
DEFAULT_LOG="$DEFAULT_WORKDIR/install_webroot_edr.log"

# Initialize variables with defaults
package="$DEFAULT_PKG"
silent="$DEFAULT_SILENT"
keycode="$DEFAULT_KEYCODE"
language="$DEFAULT_LANGUAGE"
proxy_auth="$DEFAULT_PROXYAUTH"
proxy_host="$DEFAULT_PROXYHOST"
proxy_port="$DEFAULT_PROXYPORT"
proxy_user="$DEFAULT_PROXYUSER"
proxy_pass="$DEFAULT_PROXYPASS"
logfile="$DEFAULT_LOG"

# Parse command-line arguments
for arg in "$@"; do
  case $arg in
    --pkg=*)        package="${arg#*=}" ;;
    --silent=*)      silent="${arg#*=}" ;;
    --keycode=*)     keycode="${arg#*=}" ;;
    --language=*)    language="${arg#*=}" ;;
    --proxy_auth=*)  proxy_auth="${arg#*=}" ;;
    --proxy_host=*)  proxy_host="${arg#*=}" ;;
    --proxy_port=*)  proxy_port="${arg#*=}" ;;
    --proxy_user=*)  proxy_user="${arg#*=}" ;;
    --proxy_pass=*)  proxy_pass="${arg#*=}" ;;
    --log=*)        logfile="${arg#*=}" ;;
    *) echo "Unknown option: $arg" ;;
  esac
done

echo "Final configuration:"
echo "Package: $package"
echo "Silent: $silent"
echo "Keycode: $keycode"
echo "Language: $language"
echo "Proxy Auth: $proxy_auth"
echo "Proxy Host: $proxy_host"
echo "Proxy Port: $proxy_port"
echo "Proxy User: $proxy_user"
echo "Proxy Pass: $proxy_pass"
echo "Logfile: $logfile"

# Download package if needed
cd "$DEFAULT_WORKDIR" || exit 1
WSA_URL='https://mac.webrootmultiplatform.com/production/wsa-mac/versions/latest/WSAMACSME.pkg'
echo "Downloading WSA Mac package from $WSA_URL"
curl -L -o "$package" "$WSA_URL"

# Write configuration to defaults (root only)
defaults write group.com.webroot.wsa silent -string "$silent"
defaults write group.com.webroot.wsa keycode -string "$keycode"
defaults write group.com.webroot.wsa language -string "$language"
defaults write group.com.webroot.wsa proxy_auth -string "$proxy_auth"
defaults write group.com.webroot.wsa proxy_host -string "$proxy_host"
defaults write group.com.webroot.wsa proxy_port -string "$proxy_port"
defaults write group.com.webroot.wsa proxy_user -string "$proxy_user"
defaults write group.com.webroot.wsa proxy_pass -string "$proxy_pass"
defaults write group.com.webroot.wsa installerTempFile -string "$logfile"

# Kick off install
echo "Starting installation..."
installer -dumplog -verboseR -pkg "$package" -target / >> "$logfile" 2>&1
echo "Install finished. Log output:"
cat "$logfile"
exit 0
