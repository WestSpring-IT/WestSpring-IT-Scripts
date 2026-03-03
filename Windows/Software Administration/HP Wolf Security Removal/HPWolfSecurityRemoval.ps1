#       Copyright © WESTSPRING IT LIMITED
#       Author: Thomas Samuel
#       Support: thomassamuel@westspring-it.co.uk

# Add script name here for logging purposes
$ScriptName = "HPWolfSecurityRemoval"

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
    New-LogMessage -Level INFO -Message "Script started. Removing HP security packages."

    # Collect installed packages once to avoid repeated provider queries
    $Packages = Get-Package -AllVersions -ErrorAction Stop

    # Remove HP Client Security Manager v10.0.0+ (if present)
    $HpClientSecurityPackages = $Packages |
        Where-Object { $_.Name -match "HP Client Security Manager" } |
        Where-Object { [version]$_.Version -ge [version]"10.0.0" }

    foreach ($Package in $HpClientSecurityPackages) {
        New-LogMessage -Level WARN -Message "Uninstalling package: $($Package.Name) ($($Package.Version))"
        Uninstall-Package -InputObject $Package -Force -ErrorAction Stop
        New-LogMessage -Level SUCCESS -Message "Uninstalled package: $($Package.Name) ($($Package.Version))"
    }

    # Remove additional HP security components by name patterns (if present)
    $PackageNamePatterns = @(
        "HP Wolf Security(?!.*Console)",
        "HP Wolf Security.*Console",
        "HP Security Update Service"
    )

    foreach ($PackageNamePattern in $PackageNamePatterns) {
        $MatchedPackages = $Packages | Where-Object { $_.Name -match $PackageNamePattern }

        if (-not $MatchedPackages) {
            New-LogMessage -Level INFO -Message "No matches found for pattern: $PackageNamePattern"
            continue
        }

        foreach ($Package in $MatchedPackages) {
            New-LogMessage -Level WARN -Message "Uninstalling package: $($Package.Name) ($($Package.Version))"
            Uninstall-Package -InputObject $Package -Force -ErrorAction Stop
            New-LogMessage -Level SUCCESS -Message "Uninstalled package: $($Package.Name) ($($Package.Version))"
        }
    }

    New-LogMessage -Level SUCCESS -Message "Script completed successfully. HP security packages removal complete."
    exit 0
} catch {
    $ErrorMessage = $_.Exception.Message
    New-LogMessage -Level ERROR -Message "Script failed. Error: $ErrorMessage"
    exit 1
}