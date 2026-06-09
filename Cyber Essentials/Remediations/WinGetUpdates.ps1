# Copyright © WESTSPRING IT LIMITED
# Author:        Thomas Samuel
# Support:       thomassamuel@westspring-it.co.uk

# Define variables for script name and log directory
$Script:ScriptName = "WinGetUpdates"
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

# Locate Winget executable
$WingetPath = Get-ChildItem -Path "C:\Program Files\WindowsApps" -Filter "winget.exe" -Recurse -ErrorAction SilentlyContinue |
Where-Object { $_.FullName -like "*Microsoft.DesktopAppInstaller*" } |
Sort-Object FullName -Descending |
Select-Object -First 1 -ExpandProperty FullName

if (-not $WingetPath) {
    New-LogMessage -Level "ERROR" -Message "Winget was not found. Microsoft App Installer may not be installed or available in SYSTEM context."
    New-LogMessage -Level "END" -Message "Completed $Script:ScriptName script execution."
    exit 1
}

# Log the located Winget path
New-LogMessage -Level "SUCCESS" -Message "Winget found at: $WingetPath"

# Define applications to update using Winget package IDs
$AppsToUpdate = @(
    "Google.Chrome",
    "Mozilla.Firefox"
)

foreach ($App in $AppsToUpdate) {
    try {
        New-LogMessage -Level "INFO" -Message "Checking for update: $App"

        # Check whether Winget can see an available update for the application
        $WingetOutput = & $WingetPath upgrade --id $App --exact --accept-source-agreements 2>&1
        $WingetExitCode = $LASTEXITCODE

        if ($WingetOutput -match "No installed package found matching input criteria") {
            # This exit code indicates that the application is not installed, or not detected by Winget
            New-LogMessage -Level "INFO" -Message "$App is not installed, not detected by Winget, or no update is available."
        }
        elseif ($WingetExitCode -ne 0 -and $WingetExitCode -ne -1978335189 -and $WingetExitCode -ne 1978332107) {
            # This exit code indicates an error occurred while checking for updates
            New-LogMessage -Level "ERROR" -Message "Failed to check update status for $App with exit code $WingetExitCode"

            $WingetOutput | ForEach-Object {
                if (-not [string]::IsNullOrWhiteSpace($_)) {
                    New-LogMessage -Level "ERROR" -Message $_
                }
            }
        }
        else {
            New-LogMessage -Level "WARN" -Message "Update available for $App. Starting upgrade."

            # Install the available application update silently
            $UpgradeOutput = & $WingetPath upgrade --id $App --exact --silent --accept-package-agreements --accept-source-agreements 2>&1
            $UpgradeExitCode = $LASTEXITCODE

            if ($UpgradeExitCode -eq 0) {
                # This exit code indicates the update was installed successfully
                New-LogMessage -Level "SUCCESS" -Message "$App updated successfully."
            }
            elseif ($UpgradeExitCode -eq -1978335189 -or $UpgradeExitCode -eq 1978332107) {
                # This exit codes indicate that the application is already up to date
                New-LogMessage -Level "SUCCESS" -Message "$App is already up to date."
            }
            else {
                # This exit code indicates an error occurred while installing the update
                New-LogMessage -Level "ERROR" -Message "$App update failed with exit code $UpgradeExitCode"

                $UpgradeOutput | ForEach-Object {
                    if (-not [string]::IsNullOrWhiteSpace($_)) {
                        New-LogMessage -Level "ERROR" -Message $_
                    }
                }
            }
        }
    }
    catch {
        # Catch any unexpected exceptions and log them as errors
        New-LogMessage -Level "ERROR" -Message "Failed to process $App`: $($_.Exception.Message)"
    }
}

# Log the successful completion of the script execution
New-LogMessage -Level "END" -Message "Completed $Script:ScriptName script execution."