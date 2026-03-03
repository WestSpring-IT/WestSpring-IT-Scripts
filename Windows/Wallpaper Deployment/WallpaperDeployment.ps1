#       Copyright © WESTSPRING IT LIMITED
#       Author: Thomas Samuel
#       Support: thomassamuel@westspring-it.co.uk

# Add script name here for logging purposes
$ScriptName = "WallpaperDeployment"

# Function to log messages
function New-LogMessage {
    param(
        [Parameter()]
        [ValidateSet("INFO", "ERROR", "SUCCESS", "WARN")]
        [string]$Level = "INFO",

        [Parameter(Mandatory)]
        [string]$Message
    )

    # Checks if the logging folder exists
    if (-not (Test-Path -Path "C:\WestSpring IT\LogFiles")) {
        # Log path doesn't exist, creating now
        New-Item -Path "C:\WestSpring IT\LogFiles" -ItemType Directory -Force | Out-Null
    }

    #Get current date and time
    $LogDay = Get-Date -UFormat %Y-%m-%d
    $LogTime = Get-Date -UFormat %T

    # Create log entry
    $LogMessage = @{
        Path = "C:\WestSpring IT\LogFiles\$($LogDay)-$($ScriptName).log"
        Value = "$LogTime | $Level | $Message"
    }
    Add-Content @LogMessage

    # Output log message to console with appropriate color
    if ($Level -eq "ERROR") {
        Write-Host "$LogTime | $Level | $Message" -ForegroundColor Red
    } elseif ($Level -eq "SUCCESS") {
        Write-Host "$LogTime | $Level | $Message" -ForegroundColor Green
    } elseif ($Level -eq "WARN") {
        Write-Host "$LogTime | $Level | $Message" -ForegroundColor Yellow
    } else {
        Write-Host "$LogTime | $Level | $Message"
    }
}

<# Start script logic from here #>

$RegKeyPath     = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP"
$DirectoryPath  = "C:\Users\Public\wallpaper"
$WallpaperUrl   = "{[WallpaperURL]}"

$DesktopImagePathName   = "DesktopImagePath"
$DesktopImageStatusName = "DesktopImageStatus"
$DesktopImageUrlName    = "DesktopImageUrl"
$StatusValue            = 1

$DesktopImageValue = Join-Path $DirectoryPath "desktop-wallpaper.jpeg"

try {
    New-LogMessage -Level INFO -Message "Script started. Applying desktop wallpaper via PersonalizationCSP."

    # Clean existing CSP values (avoids stale paths/URLs)
    if (Test-Path -Path $RegKeyPath) {
        New-LogMessage -Level INFO -Message "Clearing existing PersonalizationCSP wallpaper registry values."
        Remove-ItemProperty -Path $RegKeyPath -Name $DesktopImagePathName   -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path $RegKeyPath -Name $DesktopImageStatusName -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path $RegKeyPath -Name $DesktopImageUrlName    -ErrorAction SilentlyContinue
    } else {
        New-LogMessage -Level INFO -Message "PersonalizationCSP registry key not present. Will be created."
    }

    # Remove old wallpaper images to keep the folder clean and predictable
    if (Test-Path -Path $DirectoryPath) {
        New-LogMessage -Level INFO -Message "Removing existing wallpaper images from: $DirectoryPath"
        Get-ChildItem -Path $DirectoryPath -Include *.png, *.jpg, *.jpeg -Recurse -ErrorAction SilentlyContinue |
            Remove-Item -Force -ErrorAction SilentlyContinue
    }

    # Ensure destination directory exists
    if (-not (Test-Path -Path $DirectoryPath)) {
        New-LogMessage -Level INFO -Message "Creating directory: $DirectoryPath"
        New-Item -Path $DirectoryPath -ItemType Directory -Force | Out-Null
    } else {
        New-LogMessage -Level INFO -Message "Directory already exists: $DirectoryPath"
    }

    # Download wallpaper (TLS 1.2 forced for older .NET defaults)
    New-LogMessage -Level INFO -Message "Downloading wallpaper from: $WallpaperUrl"
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    $WebClient = New-Object System.Net.WebClient
    $WebClient.Proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
    $WebClient.DownloadFile($WallpaperUrl, $DesktopImageValue)

    # Validate download (exists and non-zero)
    if (-not (Test-Path -Path $DesktopImageValue)) {
        New-LogMessage -Level ERROR -Message "Wallpaper download failed: file not found at $DesktopImageValue"
        exit 1
    }

    $DesktopImageItem = Get-Item -Path $DesktopImageValue -ErrorAction Stop
    if ($DesktopImageItem.Length -eq 0) {
        New-LogMessage -Level ERROR -Message "Wallpaper download failed: file is empty at $DesktopImageValue"
        exit 1
    }

    # Ensure CSP registry key exists before setting properties
    if (-not (Test-Path -Path $RegKeyPath)) {
        New-LogMessage -Level INFO -Message "Creating registry path: $RegKeyPath"
        New-Item -Path $RegKeyPath -Force | Out-Null
    }

    # Set PersonalizationCSP values (used by MDM/Intune to apply desktop wallpaper)
    New-LogMessage -Level INFO -Message "Setting PersonalizationCSP wallpaper registry values."
    New-ItemProperty -Path $RegKeyPath -Name $DesktopImageStatusName -Value $StatusValue        -PropertyType DWORD  -Force | Out-Null
    New-ItemProperty -Path $RegKeyPath -Name $DesktopImagePathName   -Value $DesktopImageValue  -PropertyType STRING -Force | Out-Null
    New-ItemProperty -Path $RegKeyPath -Name $DesktopImageUrlName    -Value $DesktopImageValue  -PropertyType STRING -Force | Out-Null

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
    $SpifUpdateIniFile      = 0x01
    $SpifSendChange         = 0x02

    $Result = [Wallpaper]::SystemParametersInfo(
        $SpiSetDesktopWallpaper,
        0,
        $DesktopImageValue,
        ($SpifUpdateIniFile -bor $SpifSendChange)
    )

    if (-not $Result) {
        $LastError = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        New-LogMessage -Level WARN -Message "Wallpaper API call returned false. LastWin32Error: $LastError"
    } else {
        New-LogMessage -Level SUCCESS -Message "Wallpaper applied successfully: $DesktopImageValue"
    }

    New-LogMessage -Level SUCCESS -Message "Script completed successfully."
    exit 0
} catch {
    $ErrorMessage = $_.Exception.Message
    New-LogMessage -Level ERROR -Message "Script failed. Error: $ErrorMessage"
    exit 1
}