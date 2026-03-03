#       Copyright © WESTSPRING IT LIMITED
#       Author: Thomas Samuel
#       Support: thomassamuel@westspring-it.co.uk

# Add script name here for logging purposes
$ScriptName = "SystemTimeReSync"

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

$NtpServer = "time.windows.com"

try {
    New-LogMessage -Level INFO -Message "Script started. Configuring Windows Time (w32time) to use manual NTP peer: $NtpServer"

    # Configure Windows Time to use a manual NTP peer (w32tm is the supported interface for w32time config)
    & w32tm /config /manualpeerlist:$NtpServer /syncfromflags:manual /reliable:yes /update | Out-Null
    New-LogMessage -Level SUCCESS -Message "Configured w32time manual peer list to: $NtpServer"

    # Restart Windows Time to apply configuration cleanly
    Restart-Service -Name "w32time" -Force -ErrorAction Stop
    New-LogMessage -Level INFO -Message "Restarted w32time service. Waiting for Running state."

    # Wait for service to reach Running state (avoids arbitrary sleeps)
    $Service  = Get-Service -Name "w32time" -ErrorAction Stop
    $Timeout  = (Get-Date).AddSeconds(30)

    while ($Service.Status -ne "Running") {
        if ((Get-Date) -gt $Timeout) {
            New-LogMessage -Level ERROR -Message "w32time did not reach Running state within 30 seconds."
            exit 1
        }

        Start-Sleep -Milliseconds 250
        $Service.Refresh()
    }

    New-LogMessage -Level SUCCESS -Message "w32time is Running."

    # Force rediscovery and resync to validate configuration immediately
    & w32tm /resync /rediscover | Out-Null
    New-LogMessage -Level SUCCESS -Message "Triggered w32time resync and peer rediscovery."

    # Capture verification output into the log for troubleshooting
    $StatusOutput = (& w32tm /query /status 2>&1) | Out-String
    New-LogMessage -Level INFO -Message "w32tm /query /status output:`n$StatusOutput"

    $PeersOutput = (& w32tm /query /peers 2>&1) | Out-String
    New-LogMessage -Level INFO -Message "w32tm /query /peers output:`n$PeersOutput"

    New-LogMessage -Level SUCCESS -Message "Script completed successfully."
    exit 0
} catch {
    $ErrorMessage = $_.Exception.Message
    New-LogMessage -Level ERROR -Message "Script failed. Error: $ErrorMessage"
    exit 1
}