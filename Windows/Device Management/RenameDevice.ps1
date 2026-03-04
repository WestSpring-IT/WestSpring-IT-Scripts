#       Copyright © WESTSPRING IT LIMITED
#       Author: Thomas Samuel
#       Support: thomassamuel@westspring-it.co.uk

# Function to log messages
function New-LogMessage {
    param(
        [Parameter()]
        [ValidateSet("SUCCESS", "INFO", "WARN", "ERROR")]
        [string]$Level = "INFO",

        [Parameter(Mandatory)]
        [string]$Message
    )

    # Checks if the logging folder exists
    if (-not (Test-Path -Path "C:\WestSpring IT\LogFiles")) {
        # Log path doesn't exist, creating now
        New-Item -Path "C:\WestSpring IT\LogFiles" -ItemType Directory -Force | Out-Null
    }

    # Get current date and time
    $LogDay = Get-Date -UFormat %d-%m-%Y
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

# Add script name here for logging purposes (Atera and Intune often overwrite the script name)
$ScriptName = "RenameDevice"

# Add client slug (for example, client initials)
$Slug = "WS"

# Get the computer's serial number
$SerialNumber = (Get-WmiObject -Class Win32_BIOS).SerialNumber
New-LogMessage -Level INFO -Message "Device serial number is $($SerialNumber)."

# Set the new computer name
$NewComputerName = "$Slug-$SerialNumber"
New-LogMessage -Level INFO -Message "New computer name will be $($NewComputerName)."

# Rename the computer without forcing a restart
try {
    Rename-Computer -NewName $NewComputerName -ErrorAction Stop
    New-LogMessage -Level SUCCESS -Message "Computer renamed to $($NewComputerName) successfully. Please restart the device to apply changes."
} catch {
    New-LogMessage -Level ERROR -Message "Failed to rename computer: $_"
}