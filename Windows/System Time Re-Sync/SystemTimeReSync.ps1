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
    New-LogMessage -Level INFO -Message "Script started."

    # Enable "Set time zone automatically" toggle prerequisites
    try {
        New-LogMessage -Level INFO -Message "Enabling 'Set time zone automatically' and required Location permission."

        # Enable Auto Time Zone Updater (tzautoupdate)
        $TzAutoUpdateKey = "HKLM:\SYSTEM\CurrentControlSet\Services\tzautoupdate"
        if (-not (Test-Path $TzAutoUpdateKey)) {
            New-LogMessage -Level WARN -Message "tzautoupdate registry key missing. Creating: $TzAutoUpdateKey"
            New-Item -Path $TzAutoUpdateKey -Force | Out-Null
        }
        Set-ItemProperty -Path $TzAutoUpdateKey -Name "Start" -Type DWord -Value 3 -Force
        New-LogMessage -Level SUCCESS -Message "Set tzautoupdate Start=3 (enabled)."

        # Allow Location capability (needed for automatic time zone determination)
        $LocationConsentKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location"
        if (-not (Test-Path $LocationConsentKey)) {
            New-LogMessage -Level WARN -Message "Location consent key missing. Creating: $LocationConsentKey"
            New-Item -Path $LocationConsentKey -Force | Out-Null
        }
        Set-ItemProperty -Path $LocationConsentKey -Name "Value" -Type String -Value "Allow" -Force
        New-LogMessage -Level SUCCESS -Message "Set Location consent to Allow."

        # Best-effort: start related services (may not exist on all SKUs / images)
        foreach ($svcName in @("tzautoupdate", "lfsvc")) {
            try {
                $svc = Get-Service -Name $svcName -ErrorAction Stop

                if ($svc.StartType -eq "Disabled") {
                    Set-Service -Name $svcName -StartupType Manual -ErrorAction Stop
                    New-LogMessage -Level INFO -Message "Set service '$svcName' StartupType to Manual."
                }

                if ($svc.Status -ne "Running") {
                    Start-Service -Name $svcName -ErrorAction SilentlyContinue
                }

                New-LogMessage -Level INFO -Message "Service '$svcName' status: $((Get-Service -Name $svcName).Status)"
            } catch {
                New-LogMessage -Level WARN -Message "Could not adjust/start service '$svcName': $($_.Exception.Message)"
            }
        }

        New-LogMessage -Level SUCCESS -Message "'Set time zone automatically' prerequisites configured."
    } catch {
        New-LogMessage -Level WARN -Message "Failed to enable auto time zone settings (continuing with time resync). Error: $($_.Exception.Message)"
    }

    New-LogMessage -Level INFO -Message "Configuring Windows Time (w32time) to use manual NTP peer: $NtpServer"

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

    # Optional: log the effective settings we set
    try {
        $TzStart = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\tzautoupdate" -Name "Start" -ErrorAction Stop).Start
        $LocVal  = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location" -Name "Value" -ErrorAction Stop).Value
        New-LogMessage -Level INFO -Message "Auto TZ check: tzautoupdate Start=$TzStart; Location consent='$LocVal'"
    } catch {
        New-LogMessage -Level WARN -Message "Auto TZ check failed: $($_.Exception.Message)"
    }

    New-LogMessage -Level SUCCESS -Message "Script completed successfully."
    exit 0
} catch {
    $ErrorMessage = $_.Exception.Message
    New-LogMessage -Level ERROR -Message "Script failed. Error: $ErrorMessage"
    exit 1
}