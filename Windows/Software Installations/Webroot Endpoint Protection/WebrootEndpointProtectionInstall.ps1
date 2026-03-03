#       Copyright © WESTSPRING IT LIMITED
#       Author: Thomas Samuel
#       Support: thomassamuel@westspring-it.co.uk

# Add script name here for logging purposes
$ScriptName = "WebrootEndpointProtectionInstall"

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

$InstallerDownloadSource = "https://wsprodfileuksouth.blob.core.windows.net/clients/wsasme.msi"
$InstallerDownloadDestination = "C:\Temp"
$MsiPath = Join-Path $InstallerDownloadDestination "wsasme.msi"
$LogPath = Join-Path $InstallerDownloadDestination "install.log"

New-LogMessage -Level "INFO" -Message "Starting Webroot Endpoint Protection Installation"

try {
    if (-not (Test-Path -Path $InstallerDownloadDestination)) {
        # Temp directory doesn't exist, creating now
        New-LogMessage -Level "INFO" -Message "Creating path $InstallerDownloadDestination"
        New-Item -Path $InstallerDownloadDestination -ItemType Directory -Force | Out-Null
        New-LogMessage -Level "SUCCESS" -Message "Created $InstallerDownloadDestination"
    }
    else {
        # Temp directory already exists, logging warning and continuing
        New-LogMessage -Level "WARN" -Message "Destination $InstallerDownloadDestination already exists"
    }

    # Download installer
    New-LogMessage -Level "INFO" -Message "Downloading installer to $MsiPath"
    Invoke-WebRequest -Uri $InstallerDownloadSource -OutFile $MsiPath -UseBasicParsing -ErrorAction Stop

    if (-not (Test-Path -Path $MsiPath)) {
        # MSI file not found after download, logging error and exiting
        New-LogMessage -Level "ERROR" -Message "File not found after download: $MsiPath"
        Exit 1
    }

    # Install MSI
    New-LogMessage -Level "INFO" -Message "Installing MSI (logging to $LogPath)"
    $Args = "/i `"$MsiPath`" GUILIC={[WebrootKeyCode]} CMDLINE=SME,quiet /qn /l*v `"$LogPath`""

    # Start the installation process and wait for it to complete
    $p = Start-Process -FilePath "msiexec.exe" -ArgumentList $Args -Wait -PassThru -NoNewWindow

    if ($p.ExitCode -ne 0) {
        # MSI installation failed, logging error and exiting with the same code
        New-LogMessage -Level "ERROR" -Message "MSI install failed. ExitCode: $($p.ExitCode). See log: $LogPath"
        Exit $p.ExitCode
    }

    # MSI installation succeeded, logging success message and exiting
    New-LogMessage -Level "SUCCESS" -Message "Webroot Endpoint Protection installed successfully"
    Exit 0
}
catch {
    # An error occurred during the installation process, logging error message and exiting with code 1
    New-LogMessage -Level "ERROR" -Message $_.Exception.Message
    Exit 1
}