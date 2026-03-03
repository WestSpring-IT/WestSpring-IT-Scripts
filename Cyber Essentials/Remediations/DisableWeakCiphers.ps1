#       Copyright © WESTSPRING IT LIMITED
#       Author: Thomas Samuel
#       Support: thomassamuel@westspring-it.co.uk

# Add script name here for logging purposes
$ScriptName = "DisableWeakCiphers"

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

$Ciphers = @(
    "DES 56/56",
    "Triple DES 168",
    "IDEA 128/128",
    "RC2 128/128",
    "RC4 128/128",
    "RC4 56/128",
    "RC4 40/128"
)

function Disable-Cipher {
    param(
        [Parameter(Mandatory)]
        [string]$Cipher
    )

    # SCHANNEL cipher configuration lives here; setting Enabled=0 disables the cipher
    $RegistryPath = "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Ciphers\$Cipher"

    if (-not (Test-Path -Path $RegistryPath)) {
        New-LogMessage -Level INFO -Message "Registry key missing for cipher '$Cipher'. Creating: $RegistryPath"
        New-Item -Path $RegistryPath -Force | Out-Null
    }

    $PreviousEnabledValue = $null
    try {
        $Existing = Get-ItemProperty -Path $RegistryPath -Name "Enabled" -ErrorAction SilentlyContinue
        $PreviousEnabledValue = $Existing.Enabled
    } catch {
        # Non-fatal; we can still attempt to set Enabled=0
        New-LogMessage -Level WARN -Message "Unable to read existing 'Enabled' value for '$Cipher'. Continuing."
    }

    Set-ItemProperty -Path $RegistryPath -Name "Enabled" -Value 0 -ErrorAction Stop

    if ($null -eq $PreviousEnabledValue) {
        New-LogMessage -Level SUCCESS -Message "Disabled cipher '$Cipher' (Enabled was not previously set)."
    } else {
        New-LogMessage -Level SUCCESS -Message "Disabled cipher '$Cipher' (Enabled was: $PreviousEnabledValue)."
    }
}

try {
    New-LogMessage -Level INFO -Message "Script started. Disabling weak SCHANNEL ciphers."

    $DisabledCipherCount = 0

    foreach ($Cipher in $Ciphers) {
        try {
            Disable-Cipher -Cipher $Cipher
            $DisabledCipherCount++
            New-LogMessage -Level INFO -Message "Progress: $DisabledCipherCount/$($Ciphers.Count) ciphers processed."
        } catch {
            $ErrorMessage = $_.Exception.Message
            New-LogMessage -Level ERROR -Message "Failed to disable cipher '$Cipher'. Error: $ErrorMessage"
        }
    }

    New-LogMessage -Level SUCCESS -Message "Script completed successfully. Processed $DisabledCipherCount/$($Ciphers.Count) ciphers."
    exit 0
} catch {
    $ErrorMessage = $_.Exception.Message
    New-LogMessage -Level ERROR -Message "Script failed. Error: $ErrorMessage"
    exit 1
}