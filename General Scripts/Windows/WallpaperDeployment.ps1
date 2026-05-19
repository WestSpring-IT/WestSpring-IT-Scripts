# Copyright © WESTSPRING IT LIMITED
# Author:        Thomas Samuel
# Support:       thomassamuel@westspring-it.co.uk

# Define variables for script name and log directory
$Script:ScriptName = "WallpaperDeployment"
$Script:LogDirectory = "C:\WestSpring IT\LogFiles"

function New-LogMessage {
    param(
        [ValidateSet("START", "SUCCESS", "INFO", "WARN", "ERROR", "END")]
        [string]$Level = "INFO",

        [Parameter(Mandatory)]
        [string]$Message
    )

    try {
        # Create log directory if it doesn't exist
        New-Item -Path $Script:LogDirectory -ItemType Directory -Force -ErrorAction Stop | Out-Null

        # Format log entry
        $LogDay = Get-Date -Format 'dd-MM-yyyy'
        $LogTime = Get-Date -Format 'HH:mm:ss'
        $SafeScriptName = $Script:ScriptName -replace '[<>:"/\\|?*]', '_'
        $LogFile = Join-Path $Script:LogDirectory "$LogDay-$SafeScriptName.log"
        $PaddedLevel = $Level.PadRight(7)
        $Entry = "$LogTime | $PaddedLevel | $Message"

        # Write log entry to file
        Add-Content -Path $LogFile -Value $Entry -Encoding utf8 -ErrorAction Stop

        # Write log entry to console with color based on level
        switch ($Level) {
            "START" { Write-Host $Entry -ForegroundColor Cyan }
            "END" { Write-Host $Entry -ForegroundColor Cyan }
            "ERROR" { Write-Error $Entry }
            "SUCCESS" { Write-Host $Entry -ForegroundColor Green }
            "WARN" { Write-Warning $Entry }
            default { Write-Host $Entry }
        }
    }
    catch {
        # If logging fails, write error to console but continue script execution
        Write-Error "Failed to write log entry: $($_.Exception.Message)"
    }
}

# Log the start of the script execution
New-LogMessage -Level "START" -Message "Starting $Script:ScriptName script execution."

# Define variables for registry key path, directory path, wallpaper URL, and registry value names
$RegKeyPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP"
$DirectoryPath = "C:\WestSpring IT\WallpaperDeployment"
$WallpaperUrl = "{[WallpaperURL]}"

$DesktopImagePathName = "DesktopImagePath"
$DesktopImageStatusName = "DesktopImageStatus"
$DesktopImageUrlName = "DesktopImageUrl"
$StatusValue = 1

$DesktopImageValue = Join-Path $DirectoryPath "desktop-wallpaper.jpeg"

try {
    New-LogMessage -Level "INFO" -Message "Script started. Applying desktop wallpaper via PersonalizationCSP."

    # Clean existing CSP values (avoids stale paths/URLs)
    if (Test-Path -Path $RegKeyPath) {
        New-LogMessage -Level "INFO" -Message "Clearing existing PersonalizationCSP wallpaper registry values."
        Remove-ItemProperty -Path $RegKeyPath -Name $DesktopImagePathName   -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path $RegKeyPath -Name $DesktopImageStatusName -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path $RegKeyPath -Name $DesktopImageUrlName    -ErrorAction SilentlyContinue
    }
    else {
        New-LogMessage -Level "INFO" -Message "PersonalizationCSP registry key not present. Will be created."
    }

    # Remove old wallpaper images to keep the folder clean and predictable
    if (Test-Path -Path $DirectoryPath) {
        try {
            New-LogMessage -Level "INFO" -Message "Removing existing wallpaper images from: $DirectoryPath"
            Get-ChildItem -Path $DirectoryPath -Include *.png, *.jpg, *.jpeg -Recurse -ErrorAction SilentlyContinue |
            Remove-Item -Force -ErrorAction SilentlyContinue
        }
        catch {
            New-LogMessage -Level "ERROR" -Message "Failed to remove existing wallpaper images. Error: $($_.Exception.Message)"
        }
    }

    # Ensure destination directory exists
    if (-not (Test-Path -Path $DirectoryPath)) {
        New-LogMessage -Level "INFO" -Message "Creating directory: $DirectoryPath"
        New-Item -Path $DirectoryPath -ItemType Directory -Force | Out-Null
    }
    else {
        New-LogMessage -Level "INFO" -Message "Directory already exists: $DirectoryPath"
    }

    # Download wallpaper
    New-LogMessage -Level "INFO" -Message "Downloading wallpaper from: $WallpaperUrl"
    try {
        Invoke-WebRequest -Uri $WallpaperUrl -OutFile $DesktopImageValue -ErrorAction Stop
        New-LogMessage -Level "INFO" -Message "Wallpaper downloaded successfully to: $DesktopImageValue"
    }
    catch {
        New-LogMessage -Level "ERROR" -Message "Failed to download wallpaper. Error: $($_.Exception.Message)"
        exit 1
    }

    # Validate download (exists and non-zero)
    if (-not (Test-Path -Path $DesktopImageValue)) {
        New-LogMessage -Level "ERROR" -Message "Wallpaper download failed: file not found at $DesktopImageValue"
        exit 1
    }

    $DesktopImageItem = Get-Item -Path $DesktopImageValue -ErrorAction Stop
    if ($DesktopImageItem.Length -eq 0) {
        New-LogMessage -Level "ERROR" -Message "Wallpaper download failed: file is empty at $DesktopImageValue"
        exit 1
    }

    # Ensure CSP registry key exists before setting properties
    if (-not (Test-Path -Path $RegKeyPath)) {
        New-LogMessage -Level "INFO" -Message "Creating registry path: $RegKeyPath"
        New-Item -Path $RegKeyPath -Force | Out-Null
    }

    # Set PersonalizationCSP values (used by MDM/Intune to apply desktop wallpaper)
    try {
        New-LogMessage -Level "INFO" -Message "Setting PersonalizationCSP wallpaper registry values."
        New-ItemProperty -Path $RegKeyPath -Name $DesktopImageStatusName -Value $StatusValue        -PropertyType DWORD  -Force | Out-Null
        New-ItemProperty -Path $RegKeyPath -Name $DesktopImagePathName   -Value $DesktopImageValue  -PropertyType STRING -Force | Out-Null
        New-ItemProperty -Path $RegKeyPath -Name $DesktopImageUrlName    -Value $DesktopImageValue  -PropertyType STRING -Force | Out-Null
    }
    catch {
        New-LogMessage -Level "ERROR" -Message "Failed to set PersonalizationCSP registry values. Error: $($_.Exception.Message)"
        exit 1
    }

    # Brief pause before forcing wallpaper refresh (gives registry write a moment to settle)
    Start-Sleep -Seconds 2

    # Force refresh using Windows API to apply immediately in the current session
    Add-Type @"
using System.Runtime.InteropServices;
public class Wallpaper {
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
}
"@

    $SpiSetDesktopWallpaper = 20
    $SpifUpdateIniFile = 0x01
    $SpifSendChange = 0x02

    $Result = [Wallpaper]::SystemParametersInfo(
        $SpiSetDesktopWallpaper,
        0,
        $DesktopImageValue,
        ($SpifUpdateIniFile -bor $SpifSendChange)
    )

    if (-not $Result) {
        $LastError = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        New-LogMessage -Level "WARN" -Message "Wallpaper API call returned false. LastWin32Error: $LastError"
    }
    else {
        New-LogMessage -Level "SUCCESS" -Message "Wallpaper applied successfully: $DesktopImageValue"
    }

    New-LogMessage -Level "SUCCESS" -Message "Script completed successfully."
    exit 0
}
catch {
    $ErrorMessage = $_.Exception.Message
    New-LogMessage -Level "ERROR" -Message "Script failed. Error: $ErrorMessage"
    exit 1
}

# Log the successful completion of the script execution
New-LogMessage -Level "END" -Message "Completed $Script:ScriptName script execution."