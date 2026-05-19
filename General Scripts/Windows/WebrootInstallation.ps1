# Copyright © WESTSPRING IT LIMITED
# Author:        Thomas Samuel
# Support:       thomassamuel@westspring-it.co.uk

# Define variables for script name and log directory
$Script:ScriptName = "WebrootInstallation"
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

$InstallerDownloadSource = "https://wsprodfileuksouth.blob.core.windows.net/clients/wsasme.msi"
$InstallerDownloadDestination = "C:\WestSpring IT\WebrootInstaller"
$MsiPath = Join-Path $InstallerDownloadDestination "wsasme.msi"
$InstallLogPath = Join-Path $InstallerDownloadDestination "install.log"

try {
    New-LogMessage -Level INFO -Message "Script started. Beginning Webroot Endpoint Protection installation."

    # Ensure working directory exists (idempotent)
    if (-not (Test-Path -Path $InstallerDownloadDestination)) {
        New-LogMessage -Level INFO -Message "Creating destination path: $InstallerDownloadDestination"
        New-Item -Path $InstallerDownloadDestination -ItemType Directory -Force | Out-Null
        New-LogMessage -Level SUCCESS -Message "Created destination path: $InstallerDownloadDestination"
    }
    else {
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
    }
    else {
        New-LogMessage -Level SUCCESS -Message "Webroot Endpoint Protection installed successfully."
    }

    New-LogMessage -Level SUCCESS -Message "Script completed successfully."
    exit 0
}
catch {
    $ErrorMessage = $_.Exception.Message
    New-LogMessage -Level ERROR -Message "Script failed. Error: $ErrorMessage"
    exit 1
}

# Log the successful completion of the script execution
New-LogMessage -Level "END" -Message "Completed $Script:ScriptName script execution."