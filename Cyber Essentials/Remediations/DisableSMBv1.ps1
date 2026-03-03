#       Copyright © WESTSPRING IT LIMITED
#       Author: Thomas Samuel
#       Support: thomassamuel@westspring-it.co.uk

# Add script name here for logging purposes
$ScriptName = "LocalAdministrators"

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

try {
    New-LogMessage -Level INFO -Message "Script started. Evaluating SMBv1 configuration."

    # Retrieve SMB server configuration once for consistency
    $SmbConfiguration = Get-SmbServerConfiguration
    $IsSmb1Enabled    = $SmbConfiguration.EnableSMB1Protocol

    # SMBv1 is legacy and should remain disabled
    if ($IsSmb1Enabled) {
        New-LogMessage -Level WARN -Message "SMBv1 is enabled. Attempting to disable."

        # -Force suppresses confirmation prompts for automation contexts
        Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force

        New-LogMessage -Level SUCCESS -Message "SMBv1 successfully disabled."
    } else {
        New-LogMessage -Level INFO -Message "SMBv1 already disabled. No remediation required."
    }

    New-LogMessage -Level SUCCESS -Message "Script completed successfully."
    exit 0
} catch {
    $ErrorMessage = $_.Exception.Message
    New-LogMessage -Level ERROR -Message "Script failed. Error: $ErrorMessage"
    exit 1
}