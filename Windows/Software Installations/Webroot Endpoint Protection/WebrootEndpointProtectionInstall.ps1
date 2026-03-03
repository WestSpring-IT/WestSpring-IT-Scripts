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

$InstallerDownloadSource      = "https://wsprodfileuksouth.blob.core.windows.net/clients/wsasme.msi"
$InstallerDownloadDestination = "C:\Temp"
$MsiPath                      = Join-Path $InstallerDownloadDestination "wsasme.msi"
$InstallLogPath               = Join-Path $InstallerDownloadDestination "install.log"

try {
    New-LogMessage -Level INFO -Message "Script started. Beginning Webroot Endpoint Protection installation."

    # Ensure working directory exists (idempotent)
    if (-not (Test-Path -Path $InstallerDownloadDestination)) {
        New-LogMessage -Level INFO -Message "Creating destination path: $InstallerDownloadDestination"
        New-Item -Path $InstallerDownloadDestination -ItemType Directory -Force | Out-Null
        New-LogMessage -Level SUCCESS -Message "Created destination path: $InstallerDownloadDestination"
    } else {
        New-LogMessage -Level INFO -Message "Destination path already exists: $InstallerDownloadDestination"
    }

    # Download installer (ErrorAction Stop ensures failures are caught)
    New-LogMessage -Level INFO -Message "Downloading installer to: $MsiPath"
    Invoke-WebRequest -Uri $InstallerDownloadSource -OutFile $MsiPath -UseBasicParsing -ErrorAction Stop

    # Validate download completed as expected
    if (-not (Test-Path -Path $MsiPath)) {
        New-LogMessage -Level ERROR -Message "Installer not found after download: $MsiPath"
        exit 1
    }

    # Install MSI silently and capture a verbose MSI log for troubleshooting
    New-LogMessage -Level INFO -Message "Installing MSI (msiexec logging to: $InstallLogPath)"

    $MsiArguments = "/i `"$MsiPath`" GUILIC={[WebrootKeyCode]} CMDLINE=SME,quiet /qn /l*v `"$InstallLogPath`""

    # Wait for completion so we can evaluate the msiexec exit code reliably
    $Process = Start-Process -FilePath "msiexec.exe" -ArgumentList $MsiArguments -Wait -PassThru -NoNewWindow
    $ExitCode = $Process.ExitCode

    if ($ExitCode -ne 0) {
        New-LogMessage -Level ERROR -Message "MSI install failed. ExitCode: $ExitCode. See MSI log: $InstallLogPath"
        exit $ExitCode
    } else {
        New-LogMessage -Level SUCCESS -Message "Webroot Endpoint Protection installed successfully."
    }

    New-LogMessage -Level SUCCESS -Message "Script completed successfully."
    exit 0
} catch {
    $ErrorMessage = $_.Exception.Message
    New-LogMessage -Level ERROR -Message "Script failed. Error: $ErrorMessage"
    exit 1
}