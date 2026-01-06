# required module: Microsoft.WinGet.Client
# This script updates a specific winget package

param(
    [Parameter(Mandatory = $false)]
    [string]$packageName = "{[PACKAGE_NAME]}"  # e.g., "Mozilla.Firefox"
)

# functions
function write_log_message {
    <#
.SYNOPSIS
    Writes a formatted log message to a daily log file and optionally to the console.

.DESCRIPTION
    The write_log_message function logs messages with a timestamp and severity level.
    It writes the log entry to a log file located in the user's TEMP directory, named
    after the script and the current date. Optionally, it can also output the message
    to the console in a color corresponding to the severity level.

.PARAMETER message
    The message text to log. This parameter is mandatory.

.PARAMETER level
    The severity level of the message. Valid values are:
    - Info (default)
    - Warning
    - Error
    - Success

.PARAMETER writeToConsole
    If set to $false (default), the message is only written to the log file.
    If set to $true, the message will also be written to the console with color coding.

.EXAMPLE
    write_log_message -message "Script started."

    Logs an informational message to the log file.

.EXAMPLE
    write_log_message -message "Operation completed successfully." -level "Success" -writeToConsole $true

    Logs a success message to the log file and displays it in green in the console.

.EXAMPLE
    write_log_message -message "An error occurred." -level "Error"

    Logs an error message to the log file in red (if displayed in console).

.NOTES
    Log files are stored in the TEMP directory with the format:
    yyyy-MM-dd_<ScriptName>.log

    Example: C:\Users\<User>\AppData\Local\Temp\2025-08-01_write_log_message.log
#>
    param(
        [Parameter(Mandatory = $true)]
        [string]$message,
        [Parameter(Mandatory = $false)]
        [ValidateSet("Info", "Warning", "Error", "Success")]
        [string]$level = "Info",
        [Parameter(Mandatory = $false)]
        [Boolean]$writeToConsole = $false
    )
    $scriptName = $($Script:MyInvocation.MyCommand.Name).TrimEnd(".ps1")
    $timestamp = Get-Date -Format "yyyy-MM-dd_THHmmss"
    $logEntry = "[$timestamp] [$level] $message"
    
    switch ($level) {
        "Success" {$consoleColour = "Green"}
        "Info"    {$consoleColour = "Cyan"}
        "Warning" {$consoleColour = "Yellow"}
        "Error"   {$consoleColour = "Red"}
    }
    if ($writeToConsole) {
        Write-Host $logEntry -ForegroundColor $consoleColour
    }
    # Append to log file
    $logFilePath = "$env:TEMP\$(get-date -f "yyyy-MM-dd")_$($scriptName).log"
    Add-Content -Path $logFilePath -Value $logEntry
}

function install_required_modules {
        <#
.SYNOPSIS
Installs a list of required PowerShell modules if they are not already present.

.DESCRIPTION
The `install_required_modules` function checks for the presence of each module specified in the input array.
If a module is not found, it attempts to install it using `Install-Module` with the `CurrentUser` scope.
The function provides console output indicating whether each module was already installed or successfully installed.
If a module fails to install, an error message is displayed and the function returns `$false`.

.PARAMETER modules
An array of module names to check and install if they are not already available.
**Type:** Array  
**Mandatory:** Yes  

.EXAMPLE
install_required_modules -modules @("PSReadLine", "Az.Accounts")

#>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [array]$modules
    )

    foreach ($module in $modules) {
        $modulePresent = Get-Module -Name $module -ListAvailable
        If (!($modulePresent)) {
            $moduleInstall = Install-Module -Name $module -Scope CurrentUser -Force -AllowClobber
            #write-host $moduleInstall
            If (!(Get-Module -Name $module -ListAvailable)) {
                Write-Host "Module $module could not be installed." -ForegroundColor Red
                return $false
            }
        }
        Else {
            #write-host "Module $module is already installed." -ForegroundColor Green
        }
    }
}

$requiredModules = @("Microsoft.WinGet.Client")

foreach ($module in $requiredModules) {
    If (-not (Get-Module -Name $module -ListAvailable)) {
        write_log_message "Required module $($module) is not installed. Attempting to install..." -level "Info" -writeToConsole $true
        try {
            $install = install_required_modules -modules $module
            if ($install -eq $false) {
                write_log_message "Failed to install required module $($module)." -level "Error" -writeToConsole $true
                exit 1
            } else {
                write_log_message "Successfully installed required module $($module)." -level "Success" -writeToConsole $true
            }
        }
        catch {
            write_log_message "Exception occurred while installing module $($module): $_" -level "Error" -writeToConsole $true
            exit 1
        }
    }
    else {
        write_log_message "Required module Microsoft.WinGet.Client is already installed." -level "Info" -writeToConsole $true
    }
    
}



$packageStatus = Get-WinGetPackage -Name $packageName
if (-not $packageStatus) {
    write_log_message "Package $packageName not found in winget package list." -level "Error" -writeToConsole $true
    exit 1
}
write_log_message "Current status of package $($packageStatus.Name): `n 
    Installed Version: $($packageStatus.InstalledVersion) `n
    Available Version: $($packageStatus.AvailableVersions[0]) `n
    Source: $($packageStatus.Source)" -level "Info" -writeToConsole $true

    # Compare installed version against available versions array
    $installedVersion = [version]$packageStatus.InstalledVersion
    # Filter out invalid version strings
    $availableVersions = @($packageStatus.AvailableVersions) | Where-Object { $_ -match '^\d+(\.\d+){0,3}$' } | ForEach-Object { [version]$_ } | Sort-Object -Descending

    $versionIndex = $availableVersions.IndexOf($installedVersion)

    if ($versionIndex -eq -1) {
        write_log_message "Installed version $installedVersion not found in available versions array." -level "Warning" -writeToConsole $true
    } else {
        write_log_message "Installed version is at index $versionIndex in available versions (0 = newest)." -level "Info" -writeToConsole $true
    }

    # Update to latest available version if not already installed
    if ($availableVersions[0] -gt $installedVersion) {
        write_log_message "Updating $($packageStatus.Id) from $installedVersion to $($availableVersions[0])..." -level "Info" -writeToConsole $true
        try {
            $packageUpdate = Update-WinGetPackage -Id $packageStatus.Id -Version $availableVersions[0] -Force
        }
        catch {
            write_log_message "Exception occurred while updating package: `n 
            $($packageUpdate.ExtendedErrorCode)" -level "Error" -writeToConsole $true
            exit 1
        } finally {
            # Verify update
            $updatedPackageStatus = Get-WinGetPackage -Name $packageName
            if ($updatedPackageStatus.InstalledVersion -eq $availableVersions[0].ToString()) {
                write_log_message "Package $($packageStatus.Id) successfully updated to version $($updatedPackageStatus.InstalledVersion)." -level "Success" -writeToConsole $true
                if ($packageUpdate.RebootRequired) {
                    write_log_message "A system reboot is required to complete the installation of $($packageStatus.Id)." -level "Warning" -writeToConsole $true
                }
            } else {
                write_log_message "Package $($packageStatus.Id) update failed. Current version is still $($updatedPackageStatus.InstalledVersion)." -level "Error" -writeToConsole $true
                exit 1
            }
        }
        
    } else {
        write_log_message "Package $($packageStatus.Id) is already at the latest version." -level "Success" -writeToConsole $true
    }