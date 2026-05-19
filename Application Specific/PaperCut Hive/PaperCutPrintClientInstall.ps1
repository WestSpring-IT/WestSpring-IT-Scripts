# Copyright © WESTSPRING IT LIMITED
# Author:        Thomas Samuel
# Support:       thomassamuel@westspring-it.co.uk

# Define variables for script name and log directory
$Script:ScriptName = "PaperCutPrintClientInstall"
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

# Checking if PaperCut Hive is already installed
if (-not (Test-Path -Path "$env:LOCALAPPDATA\Programs\PaperCut Hive\pc-print-client-service.exe")) {
    New-LogMessage -Level "INFO" -Message "PaperCut Hive is not installed. Proceeding with installation."

    # Check if PaperCut Hive installer exists
    if (-not (Test-Path -Path "C:\WestSpring IT\PaperCutHive\papercut-hive.exe")) {
        New-LogMessage -Level "INFO" -Message "PaperCut Hive installer not found. Downloading installer."

        # Create the directory for the installer if it doesn't exist (will skip if it already exists)
        New-Item -Path "C:\WestSpring IT\PaperCutHive" -ItemType Directory -Force -ErrorAction Stop | Out-Null

        # Download the installer
        try {
            Invoke-WebRequest -Uri "https://wsprodfileuksouth.blob.core.windows.net/clients/papercut-hive.exe" -OutFile "C:\WestSpring IT\PaperCutHive\papercut-hive.exe" -ErrorAction Stop
            New-LogMessage -Level "SUCCESS" -Message "Successfully downloaded PaperCut Hive installer."
        }
        catch {
            New-LogMessage -Level "ERROR" -Message "Failed to download PaperCut Hive installer: $($_.Exception.Message)"
            return
        }
    }
    else {
        # Installer already exists, skipping download
        New-LogMessage -Level "INFO" -Message "PaperCut Hive installer already exists. Skipping download."
    }

    # Define installation parameters
    $Folder = "$env:LOCALAPPDATA\Programs\PaperCut Hive"
    $Arguments = @{
        FilePath     = "C:\WestSpring IT\papercut-hive.exe"
        ArgumentList = @(
            '/VERYSILENT',
            '/region="uk"',
            '/CURRENTUSER',
            '/userkey="UyBVtIY8voCUNo3NiPCUsVCCS6Etcqf0TF22B7uQcviobrklYUdbJDbQcS2M4WGpGftMQp9lpGiNwiM4Mm83tPybWD0uTEoXAMNy"',
            '/orgid="3538c0d1"'
        )
    }

    # Install PaperCut Hive
    try {
        New-LogMessage -Level "INFO" -Message "Executing installer with arguments: $($Arguments.ArgumentList -join ' ')"
        Start-Process @Arguments -ErrorAction Stop
        # Wait for the installation to complete before proceeding (adjust the sleep duration as needed)
        Start-Sleep -Seconds 60
    }
    catch {
        New-LogMessage -Level "ERROR" -Message "Failed to execute installer: $($_.Exception.Message)"
    }

    # Attempt to auto-link user to the print client
    try {
        $UserPrincipalName = whoami /upn
        New-LogMessage -Level "INFO" -Message "Attempting to auto-link user $UserPrincipalName to the print client."
        Start-Process -FilePath "$env:LOCALAPPDATA\Programs\PaperCut Hive\pc-print-client-service.exe" -ArgumentList "command", "link-with-email", "bqQOHRyyoZEaMmt1LfQ7iykj9hb1mmwlpeY7vQkBnebttNLKzL5UZSs08ZwvKZMUAsUf5AkfjUyP60379TdPs82BQc0mejjbIt0d", $UserPrincipalName, "uk" -ErrorAction Stop
    }
    catch {
        New-LogMessage -Level "ERROR" -Message "Failed to auto-link user to the print client: $($_.Exception.Message)"
    }

    New-LogMessage -Level "INFO" -Message "Installation process completed. Please verify the installation and user linking manually if necessary."
}
else {
    # PaperCut Hive is already installed, skipping installation
    New-LogMessage -Level "SUCCESS" -Message "PaperCut Hive is already installed. Skipping installation."
}


# Log the successful completion of the script execution
New-LogMessage -Level "END" -Message "Completed $Script:ScriptName script execution."