# Copyright © WESTSPRING IT LIMITED
# Author:        Thomas Samuel
# Support:       thomassamuel@westspring-it.co.uk

# Define variables for script name and log directory
$Script:ScriptName = "DOTNETRemediations"
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

# Upgrade Chocolatey if installed, install if not installed, and log the outcome
try {
    if (Get-Command choco -ErrorAction SilentlyContinue) {
        New-LogMessage -Level "INFO" -Message "Chocolatey is already installed. Attempting to upgrade Chocolatey."
        choco upgrade chocolatey -y --no-progress | Out-Null
        New-LogMessage -Level "SUCCESS" -Message "Successfully upgraded Chocolatey."
    }
    else {
        New-LogMessage -Level "INFO" -Message "Chocolatey is not installed. Attempting to install Chocolatey."
        Set-ExecutionPolicy Bypass -Scope Process -Force
        Invoke-Expression (Invoke-WebRequest -Uri "https://community.chocolatey.org/install.ps1" -UseBasicParsing).Content
        New-LogMessage -Level "SUCCESS" -Message "Successfully installed Chocolatey."
    }
}
catch {
    New-LogMessage -Level "ERROR" -Message "An error occurred while installing or upgrading Chocolatey: $($_.Exception.Message)"
    New-LogMessage -Level "END" -Message "Completed $Script:ScriptName script execution."
    exit 1
}

# Install .NET uninstall tool using Chocolatey and log the outcome
try {
    New-LogMessage -Level "INFO" -Message "Attempting to install the .NET uninstall tool using Chocolatey."
    choco install dotnet-uninstaller -y --no-progress --force | Out-Null
    New-LogMessage -Level "SUCCESS" -Message "Successfully installed the .NET uninstall tool."
}
catch {
    New-LogMessage -Level "ERROR" -Message "An error occurred while installing the .NET uninstall tool: $($_.Exception.Message)"
    New-LogMessage -Level "END" -Message "Completed $Script:ScriptName script execution."
    exit 1
}

# Attempt to cleanup all .NET SDKs and runtimes using the installed uninstall tool and log the outcome
try {
    New-LogMessage -Level "INFO" -Message "Attempting to uninstall all .NET SDK versions."
    Start-Process -FilePath "C:\Program Files (x86)\dotnet-core-uninstall\dotnet-core-uninstall.exe" -ArgumentList "remove --all --sdk --force --yes" -Wait -ErrorAction Stop
    New-LogMessage -Level "SUCCESS" -Message "Successfully cleaned up all .NET SDK versions."
    New-LogMessage -Level "INFO" -Message "Attempting to uninstall all .NET runtime versions."
    Start-Process -FilePath "C:\Program Files (x86)\dotnet-core-uninstall\dotnet-core-uninstall.exe" -ArgumentList "remove --all --runtime --force --yes" -Wait -ErrorAction Stop
    New-LogMessage -Level "SUCCESS" -Message "Successfully cleaned up all .NET runtime versions."
    New-LogMessage -Level "INFO" -Message "Attempting to uninstall all .NET desktop runtime versions."
    Start-Process -FilePath "C:\Program Files (x86)\dotnet-core-uninstall\dotnet-core-uninstall.exe" -ArgumentList "remove --all --windows-desktop-runtime --force --yes" -Wait -ErrorAction Stop
    New-LogMessage -Level "SUCCESS" -Message "Successfully cleaned up all .NET desktop runtime versions."
    New-LogMessage -Level "INFO" -Message "Attempting to uninstall all ASP.NET versions."
    Start-Process -FilePath "C:\Program Files (x86)\dotnet-core-uninstall\dotnet-core-uninstall.exe" -ArgumentList "remove --all --aspnet-runtime --force --yes" -Wait -ErrorAction Stop
    New-LogMessage -Level "SUCCESS" -Message "Successfully cleaned up all ASP.NET versions."
}
catch {
    # If an error occurs during the cleanup process, log the error message but continue with the script execution
    New-LogMessage -Level "ERROR" -Message "An error occurred while cleaning up .NET SDKs and runtimes: $($_.Exception.Message)"
}

# Attempt to remove any remaining .NET SDKs and runtimes that may not have been removed by the uninstall tool and log the outcome
try {
    Get-ChildItem "C:\Program Files\dotnet\shared\Microsoft.NETCore.App" -Directory -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    Get-ChildItem "C:\Program Files\dotnet\shared\Microsoft.WindowsDesktop.App" -Directory -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    Get-ChildItem "C:\Program Files\dotnet\shared\Microsoft.AspNetCore.App" -Directory -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    Get-ChildItem "C:\Program Files (x86)\dotnet\shared\Microsoft.NETCore.App" -Directory -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    Get-ChildItem "C:\Program Files (x86)\dotnet\shared\Microsoft.WindowsDesktop.App" -Directory -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    Get-ChildItem "C:\Program Files (x86)\dotnet\shared\Microsoft.AspNetCore.App" -Directory -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    New-LogMessage -Level "SUCCESS" -Message "Successfully removed remaining .NET SDKs and runtimes."
}
catch {
    New-LogMessage -Level "WARN" -Message "Failed to remove remaining .NET SDKs and runtimes: $($_.Exception.Message)"
}

# Cleanup .NET bundles within Chocolatey, allows it to re-install
try {
    New-LogMessage -Level "INFO" -Message "Attempting to remove any pre-existing .NET bundles within Chocolatey."
    Get-ChildItem "C:\ProgramData\chocolatey\lib" -Directory -Filter "dotnet*" -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne "dotnet-uninstaller" } | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    New-LogMessage -Level "SUCCESS" -Message "Successfully removed pre-existing .NET bundles within Chocolatey."
}
catch {
    New-LogMessage -Level "WARN" -Message "Failed to remove pre-existing .NET bundles within Chocolatey: $($_.Exception.Message)"
    New-LogMessage -Level "ERROR" -Message "Completed $Script:ScriptName script execution."
    exit 1
}

# Attempt to re-install latest .NET SDK and runtime versions using Chocolatey and log the outcome
try {
    New-LogMessage -Level "INFO" -Message "Attempting to install the latest .NET SDK version using Chocolatey."
    choco install dotnet-sdk -y --no-progress --force | Out-Null
    New-LogMessage -Level "SUCCESS" -Message "Successfully installed the latest .NET SDK version."
}
catch {
    New-LogMessage -Level "ERROR" -Message "An error occurred while installing the latest .NET SDK and runtime versions: $($_.Exception.Message)"
    New-LogMessage -Level "END" -Message "Completed $Script:ScriptName script execution."
    exit 1
}

# Uninstall .NET uninstall tool and log the outcome
try {
    New-LogMessage -Level "INFO" -Message "Attempting to uninstall the .NET uninstall tool using Chocolatey."
    choco uninstall dotnet-uninstaller -y --no-progress --force | Out-Null
    New-LogMessage -Level "SUCCESS" -Message "Successfully uninstalled the .NET uninstall tool."
}
catch {
    # If an error occurs during the uninstallation process, log the error message but continue with the script execution
    New-LogMessage -Level "WARN" -Message "An error occurred while uninstalling the .NET uninstall tool: $($_.Exception.Message)"
}

# Log the successful completion of the script execution
New-LogMessage -Level "END" -Message "Completed $Script:ScriptName script execution."