#!/bin/bash

################################################################################
# Canon IR-ADV C3930i Printer Setup with Driver Installation
# LPD-only version with silent driver deployment
################################################################################

# Printer Configuration
PRINTER_NAME="SaintNicks_Canon"
PRINTER_DISPLAY_NAME="SaintNicks Canon"
PRINTER_LOCATION="Berkely Square"
PRINTER_IP="10.5.32.122"

# Driver Configuration
DRIVER_URL="https://wsprodfileuksouth.blob.core.windows.net/clients/Saint-Nicks/Printer/Macs/Canon/IR-ADV_3930/mac-ppd-v540-ukEN-11.dmg"
DRIVER_DMG_NAME="canon_ppd_driver.dmg"
DRIVER_INSTALL_PATH="/Library/Printers/PPDs/Contents/Resources"

# Logging
LOG_FILE="/var/log/canon_printer_setup.log"

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    log_message "ERROR: This script must be run as root or with sudo"
    exit 1
fi

log_message "===== Starting Canon Printer Setup (LPD-only) ====="

# Check if printer already exists
if lpstat -p "$PRINTER_NAME" &>/dev/null; then
    log_message "Printer '$PRINTER_NAME' already exists. Exiting."
    exit 0
fi

# Function to check if Canon driver is installed
check_driver_installed() {
    local driver_locations=(
        "/Library/Printers/PPDs/Contents/Resources/CNMCIRAC3930S2.ppd.gz"
        "/Library/Printers/PPDs/Contents/Resources/CNMCIRAC3930S2.ppd"
        "/Library/Printers/Canon/UFR2/PPD/CNMCIRAC3930S2.ppd.gz"
        "/Library/Printers/Canon/UFR2/PPD/CNMCIRAC3930S2.ppd"
    )
    
    for path in "${driver_locations[@]}"; do
        if [ -f "$path" ]; then
            log_message "Canon driver found at: $path"
            return 0
        fi
    done
    
    # Check for any Canon IR-ADV C3930 driver (case-insensitive)
    if find /Library/Printers/PPDs/Contents/Resources -type f \( -iname "*C3930*" -a \( -iname "*.ppd" -o -iname "*.ppd.gz" \) \) 2>/dev/null | grep -q .; then
        log_message "Canon IR-ADV C3930 series driver found"
        return 0
    fi
    
    if find /Library/Printers -type f \( -iname "*CIRAC3930*" -a \( -iname "*.ppd" -o -iname "*.ppd.gz" \) \) 2>/dev/null | grep -q .; then
        log_message "Canon IR-ADV C3930 series driver found"
        return 0
    fi
    
    log_message "Canon driver not found"
    return 1
}

# Function to download and install driver
install_driver() {
    local temp_dir="/tmp/canon_driver_$$"
    mkdir -p "$temp_dir"
    
    log_message "Downloading Canon PPD drivers from Azure storage..."
    
    # Download with error handling
    if ! curl -L -f -o "$temp_dir/$DRIVER_DMG_NAME" "$DRIVER_URL" 2>&1 | tee -a "$LOG_FILE"; then
        log_message "ERROR: Failed to download driver"
        log_message "URL: $DRIVER_URL"
        rm -rf "$temp_dir"
        return 1
    fi
    
    log_message "Driver downloaded successfully ($(du -h "$temp_dir/$DRIVER_DMG_NAME" | cut -f1))"
    
    # Mount the DMG
    log_message "Mounting driver DMG..."
    local mount_output=$(hdiutil attach "$temp_dir/$DRIVER_DMG_NAME" -nobrowse -noverify -noautoopen 2>&1)
    local mount_point=$(echo "$mount_output" | grep "/Volumes" | sed 's/.*\(\/Volumes\/.*\)/\1/' | head -n 1)
    
    if [ -z "$mount_point" ]; then
        log_message "ERROR: Failed to mount driver DMG"
        log_message "$mount_output"
        rm -rf "$temp_dir"
        return 1
    fi
    
    log_message "Driver mounted at: $mount_point"
    
    # Find all PPD files in the DMG (including in subdirectories)
    # Use -iname for case-insensitive matching (Canon uses .PPD.gz uppercase)
    log_message "Searching for PPD files in DMG..."
    local ppd_files=$(find "$mount_point" -type f \( -iname "*.ppd" -o -iname "*.ppd.gz" \) 2>/dev/null)
    
    # Check if we found any PPD files
    if [ -z "$ppd_files" ]; then
        log_message "ERROR: No PPD files found in DMG"
        log_message "Listing DMG contents for diagnostic purposes:"
        ls -laR "$mount_point" 2>&1 | tee -a "$LOG_FILE"
        hdiutil detach "$mount_point" -force 2>/dev/null
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Count files
    local file_count=$(echo "$ppd_files" | wc -l | tr -d ' ')
    log_message "Found $file_count PPD file(s) to install"
    
    # Ensure target directory exists
    if [ ! -d "$DRIVER_INSTALL_PATH" ]; then
        log_message "Creating driver directory: $DRIVER_INSTALL_PATH"
        mkdir -p "$DRIVER_INSTALL_PATH"
    fi
    
    # Copy all PPD files to the target directory
    local installed_count=0
    while IFS= read -r ppd_file; do
        local filename=$(basename "$ppd_file")
        local target_path="$DRIVER_INSTALL_PATH/$filename"
        
        log_message "Installing: $filename"
        
        if cp "$ppd_file" "$target_path" 2>&1 | tee -a "$LOG_FILE"; then
            # Set proper permissions
            chmod 644 "$target_path"
            chown root:wheel "$target_path" 2>/dev/null
            installed_count=$((installed_count + 1))
            log_message "  ✓ Installed: $filename"
        else
            log_message "  ✗ Failed to install: $filename"
        fi
    done <<< "$ppd_files"
    
    log_message "Successfully installed $installed_count of $file_count PPD files"
    
    # Update CUPS PPD cache
    log_message "Updating CUPS driver cache..."
    if [ -f "/usr/sbin/cupstestppd" ]; then
        # Restart CUPS to recognize new drivers
        log_message "Restarting CUPS service..."
        launchctl stop org.cups.cupsd 2>/dev/null
        sleep 2
        launchctl start org.cups.cupsd 2>/dev/null
        sleep 2
    fi
    
    # Unmount and cleanup
    log_message "Unmounting DMG..."
    hdiutil detach "$mount_point" -force 2>/dev/null
    rm -rf "$temp_dir"
    
    log_message "Driver installation complete"
    
    # Give the system a moment to register the drivers
    sleep 3
    
    return 0
}

# Check and install driver if needed
if ! check_driver_installed; then
    log_message "Canon driver not found. Installing from Azure storage..."
    
    if ! install_driver; then
        log_message "ERROR: Driver installation failed"
        exit 1
    fi
    
    # Verify driver was installed
    if ! check_driver_installed; then
        log_message "ERROR: Driver still not found after installation"
        exit 1
    fi
else
    log_message "Canon driver already installed"
fi

# Find the Canon driver PPD
log_message "Locating Canon driver PPD..."
PPD_PATH=""
DRIVER_LOCATIONS=(
    "/Library/Printers/PPDs/Contents/Resources/CNMCIRAC3930S2.ppd.gz"
    "/Library/Printers/PPDs/Contents/Resources/CNMCIRAC3930S2.ppd"
    "/Library/Printers/PPDs/Contents/Resources/en.lproj/CNMCIRAC3930S2.ppd.gz"
    "/Library/Printers/PPDs/Contents/Resources/en.lproj/CNMCIRAC3930S2.ppd"
    "/Library/Printers/Canon/UFR2/PPD/CNMCIRAC3930S2.ppd.gz"
    "/Library/Printers/Canon/UFR2/PPD/CNMCIRAC3930S2.ppd"
    "/Library/Printers/Canon/CUPS_Printer/PPD/CNMCIRAC3930S2.ppd.gz"
)

for path in "${DRIVER_LOCATIONS[@]}"; do
    if [ -f "$path" ]; then
        log_message "Found Canon driver at: $path"
        PPD_PATH="$path"
        break
    fi
done

# If exact model not found, try to find similar Canon IR-ADV C3930 driver
if [ -z "$PPD_PATH" ]; then
    log_message "Exact model PPD not found, searching for compatible driver..."
    PPD_PATH=$(find /Library/Printers/PPDs/Contents/Resources -type f \( -iname "*C3930*" -a \( -iname "*.ppd" -o -iname "*.ppd.gz" \) \) 2>/dev/null | head -n 1)
    
    if [ -z "$PPD_PATH" ]; then
        PPD_PATH=$(find /Library/Printers -type f \( -iname "*CIRAC3930*" -a \( -iname "*.ppd" -o -iname "*.ppd.gz" \) \) 2>/dev/null | head -n 1)
    fi
    
    if [ -n "$PPD_PATH" ]; then
        log_message "Found compatible driver: $PPD_PATH"
    else
        log_message "ERROR: No suitable Canon driver found"
        exit 1
    fi
fi

# Add the printer using LPD protocol
log_message "Adding printer '$PRINTER_DISPLAY_NAME' via LPD..."
PRINTER_URI="lpd://${PRINTER_IP}/"

if lpadmin -p "$PRINTER_NAME" \
    -v "$PRINTER_URI" \
    -P "$PPD_PATH" \
    -D "$PRINTER_DISPLAY_NAME" \
    -L "$PRINTER_LOCATION" \
    -E \
    -o printer-is-shared=false 2>&1 | tee -a "$LOG_FILE"; then
    
    log_message "Printer added successfully"
    
    # Enable the printer and set it to accept jobs
    cupsenable "$PRINTER_NAME" 2>&1 | tee -a "$LOG_FILE"
    cupsaccept "$PRINTER_NAME" 2>&1 | tee -a "$LOG_FILE"
    
    # Set some common options for Canon printers
    lpadmin -p "$PRINTER_NAME" -o media=Letter 2>/dev/null
    lpadmin -p "$PRINTER_NAME" -o ColorModel=RGB 2>/dev/null
    
    log_message "Printer enabled and accepting jobs"
    log_message "===== Setup completed successfully ====="
    
    # Display printer info
    lpstat -p "$PRINTER_NAME" 2>&1 | tee -a "$LOG_FILE"
    
    exit 0
else
    log_message "ERROR: Failed to add printer"
    log_message "===== Setup failed ====="
    exit 1
fi
