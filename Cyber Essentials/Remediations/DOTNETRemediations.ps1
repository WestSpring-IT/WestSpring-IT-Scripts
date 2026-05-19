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

# Ensure the temporary directory exists before proceeding with any operations
New-Item -Path "C:\WestSpring IT\DOTNET" -ItemType Directory -Force -ErrorAction Stop | Out-Null
New-LogMessage -Level "INFO" -Message "Ensured temporary directory 'C:\WestSpring IT\DOTNET' exists."

# Check if the windowsdesktop-runtime-win-x64.exe script already exists before attempting to download it
try {
    if (-not (Test-Path -Path "C:\WestSpring IT\DOTNET\windowsdesktop-runtime-win-x64.exe")) {
        New-LogMessage -Level "INFO" -Message "Downloading .NET installer."
        Invoke-WebRequest -Uri "https://aka.ms/dotnet/LTS/windowsdesktop-runtime-win-x64.exe" -OutFile "C:\WestSpring IT\DOTNET\windowsdesktop-runtime-win-x64.exe" -UseBasicParsing -ErrorAction Stop
        New-LogMessage -Level "SUCCESS" -Message "Successfully downloaded .NET installer."
    }
    else {
        New-LogMessage -Level "INFO" -Message "windowsdesktop-runtime-win-x64.exe already exists. Skipping download."
    }

    # Additional check to ensure the downloaded file exists at the expected location
    if (-not (Test-Path -Path "C:\WestSpring IT\DOTNET\windowsdesktop-runtime-win-x64.exe")) {
        New-LogMessage -Level "ERROR" -Message "Downloaded .NET installer file not found at expected location."

        # Attempt to download the file again and save it with a temporary name (WatchGuard commonly blocks MSI downloads, so this is a workaround to bypass that issue)
        try {
            Invoke-WebRequest -Uri "https://aka.ms/dotnet/LTS/windowsdesktop-runtime-win-x64.exe" -OutFile "C:\WestSpring IT\DOTNET\windowsdesktop-runtime-win-x64.txt" -UseBasicParsing -ErrorAction Stop
            New-LogMessage -Level "ERROR" -Message "Downloaded .NET installer content saved to temporary.txt file."

            # Rename the temporary file to the correct .exe extension
            Rename-Item -Path "C:\WestSpring IT\DOTNET\windowsdesktop-runtime-win-x64.txt" -NewName "windowsdesktop-runtime-win-x64.exe" -ErrorAction Stop
            New-LogMessage -Level "ERROR" -Message "Renamed temporary.txt to windowsdesktop-runtime-win-x64.exe."
        }
        catch {
            New-LogMessage -Level "ERROR" -Message "Failed to download .NET installer on second attempt: $($_.Exception.Message)"
            exit 1
        }
    }
}
catch {
    New-LogMessage -Level "ERROR" -Message "Failed to download .NET installer: $($_.Exception.Message)"
    exit 1
}

# Check if the dotnet-core-uninstall.msi script already exists before attempting to download it
try {
    if (-not (Test-Path -Path "C:\WestSpring IT\DOTNET\dotnet-core-uninstall.msi")) {
        New-LogMessage -Level "INFO" -Message "Downloading .NET uninstaller."
        Invoke-WebRequest -Uri "https://github.com/dotnet/cli-lab/releases/download/1.7.661902/dotnet-core-uninstall.msi" -OutFile "C:\WestSpring IT\DOTNET\dotnet-core-uninstall.msi" -UseBasicParsing -ErrorAction Stop
        New-LogMessage -Level "SUCCESS" -Message "Successfully downloaded .NET uninstaller."
        # Additional check to ensure the downloaded file exists at the expected location
        if (-not (Test-Path -Path "C:\WestSpring IT\DOTNET\dotnet-core-uninstall.msi")) {
            New-LogMessage -Level "ERROR" -Message "Downloaded .NET uninstaller file not found at expected location."

            # Attempt to download the file again and save it with a temporary name (WatchGuard commonly blocks MSI downloads, so this is a workaround to bypass that issue)
            try {
                Invoke-WebRequest -Uri "https://github.com/dotnet/cli-lab/releases/download/1.7.661902/dotnet-core-uninstall.msi" -OutFile "C:\WestSpring IT\DOTNET\dotnet-core-uninstall.txt" -UseBasicParsing -ErrorAction Stop
                New-LogMessage -Level "ERROR" -Message "Downloaded .NET uninstaller content saved to temporary.txt file."
            
                # Rename the temporary file to the correct .exe extension
                Rename-Item -Path "C:\WestSpring IT\DOTNET\dotnet-core-uninstall.txt" -NewName "dotnet-core-uninstall.msi" -ErrorAction Stop
                New-LogMessage -Level "ERROR" -Message "Renamed temporary.txt to dotnet-core-uninstall.msi."
            }
            catch {
                New-LogMessage -Level "ERROR" -Message "Failed to download .NET uninstaller on second attempt: $($_.Exception.Message)"
                exit 1
            }
        }
    }
    else {
        New-LogMessage -Level "INFO" -Message "dotnet-core-uninstall.msi already exists. Skipping download."
    } 
}
catch {
    New-LogMessage -Level "ERROR" -Message "Failed to download .NET uninstaller: $($_.Exception.Message)"
    exit 1
}

# Install the .NET uninstaller
try {
    New-LogMessage -Level "INFO" -Message "Installing .NET uninstaller."
    Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"C:\WestSpring IT\DOTNET\dotnet-core-uninstall.msi`" /qn" -Wait -ErrorAction Stop
    New-LogMessage -Level "SUCCESS" -Message "Successfully installed .NET uninstaller."
}
catch {
    New-LogMessage -Level "ERROR" -Message "Failed to install .NET uninstaller: $($_.Exception.Message)"
    exit 1
}

# Uninstall all .NET versions using the uninstaller tool
try {
    Start-Process "cmd.exe" -ArgumentList "/c", "dotnet-core-uninstall", "remove --sdk --all --force --yes" -Wait -ErrorAction Stop
    New-LogMessage -Level "SUCCESS" -Message "Successfully uninstalled all .NET SDK versions."
    Start-Process "cmd.exe" -ArgumentList "/c", "dotnet-core-uninstall", "remove --runtime --all --force --yes" -Wait -ErrorAction Stop
    New-LogMessage -Level "SUCCESS" -Message "Successfully uninstalled all .NET runtime versions."
    Start-Process "cmd.exe" -ArgumentList "/c", "dotnet-core-uninstall", "remove --aspnet-runtime --all --force --yes" -Wait -ErrorAction Stop
    New-LogMessage -Level "SUCCESS" -Message "Successfully uninstalled all .NET ASP.NET runtime versions."
}
catch {
    New-LogMessage -Level "ERROR" -Message "Failed to uninstall .NET versions: $($_.Exception.Message)"
    exit 1
}

# Remove any remaining .NET SDKs and runtimes from the system
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
    New-LogMessage -Level "ERROR" -Message "Failed to remove remaining .NET SDKs and runtimes: $($_.Exception.Message)"
}

# Install the latest .NET SDK
try {
    New-LogMessage -Level "INFO" -Message "Installing .NET SDK."
    Start-Process -FilePath "C:\WestSpring IT\DOTNET\windowsdesktop-runtime-win-x64.exe" -ArgumentList "/install", "/quiet", "/norestart" -Wait -ErrorAction Stop
    New-LogMessage -Level "SUCCESS" -Message "Successfully installed .NET SDK."
}
catch {
    New-LogMessage -Level "ERROR" -Message "Failed to install .NET SDK: $($_.Exception.Message)"
    exit 1
}

# Uninstall the .NET uninstaller
try {
    New-LogMessage -Level "INFO" -Message "Uninstalling .NET uninstaller."
    Start-Process -FilePath "msiexec.exe" -ArgumentList "/x `"C:\WestSpring IT\DOTNET\dotnet-core-uninstall.msi`" /qn" -Wait -ErrorAction Stop
    New-LogMessage -Level "SUCCESS" -Message "Successfully uninstalled .NET uninstaller."
}
catch {
    New-LogMessage -Level "ERROR" -Message "Failed to uninstall .NET uninstaller: $($_.Exception.Message)"
    exit 1
}

# Clean up the temporary directory and its contents
try {
    Remove-Item -Path "C:\WestSpring IT\DOTNET" -Recurse -Force -ErrorAction Stop
    New-LogMessage -Level "SUCCESS" -Message "Successfully cleaned up temporary files."
}
catch {
    New-LogMessage -Level "ERROR" -Message "Failed to clean up temporary files: $($_.Exception.Message)"
}

# Log the successful completion of the script execution
New-LogMessage -Level "END" -Message "Completed $Script:ScriptName script execution."