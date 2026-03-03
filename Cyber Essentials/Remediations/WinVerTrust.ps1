#       Copyright © WESTSPRING IT LIMITED
#       Author: Thomas Samuel
#       Support: thomassamuel@westspring-it.co.uk

# Add script name here for logging purposes
$ScriptName = "EnableCertPaddingCheck"

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
    New-LogMessage -Level INFO -Message "Script started. Enabling WinTrust EnableCertPaddingCheck (64-bit + 32-bit)."

    $RegistryPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Cryptography\Wintrust\Config",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Cryptography\Wintrust\Config"
    )

    $FailedPaths = @()

    foreach ($RegistryPath in $RegistryPaths) {
        try {
            # Ensure key exists before writing policy value
            if (-not (Test-Path -LiteralPath $RegistryPath)) {
                New-LogMessage -Level INFO -Message "Creating registry path: $RegistryPath"
                New-Item -Path $RegistryPath -Force | Out-Null
            }

            New-ItemProperty -LiteralPath $RegistryPath -Name "EnableCertPaddingCheck" -Value 1 -PropertyType String -Force -ErrorAction Stop | Out-Null
            New-LogMessage -Level SUCCESS -Message "Set EnableCertPaddingCheck=1 at: $RegistryPath"
        } catch {
            $ErrorMessage = $_.Exception.Message
            New-LogMessage -Level ERROR -Message "Failed to set EnableCertPaddingCheck at: $RegistryPath. Error: $ErrorMessage"
            $FailedPaths += $RegistryPath
        }
    }

    if ($FailedPaths.Count -gt 0) {
        New-LogMessage -Level ERROR -Message "Script completed with failures. Failed paths: $($FailedPaths -join '; ')"
        exit 1
    } else {
        New-LogMessage -Level SUCCESS -Message "Script completed successfully."
        exit 0
    }
} catch {
    $ErrorMessage = $_.Exception.Message
    New-LogMessage -Level ERROR -Message "Script failed. Error: $ErrorMessage"
    exit 1
}