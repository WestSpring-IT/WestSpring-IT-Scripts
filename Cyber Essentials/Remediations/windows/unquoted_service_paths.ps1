<#
.SYNOPSIS
Remediates unquoted ImagePath registry entries for automatically-starting Windows services by adding quotes around executable paths that contain spaces.

.DESCRIPTION
This script scans HKLM:\SYSTEM\CurrentControlSet\Services for services that:
 - have an ImagePath value,
 - are configured to start automatically (Start = 2),
 - contain spaces in the ImagePath, and
 - do not already have the executable portion fully quoted.

For identified services the script attempts to split the ImagePath into an executable portion and arguments (special-casing common ".exe" and ".sys" patterns), wraps the executable portion in quotes, and writes the new ImagePath back to the service registry key. Actions and results are emitted via write_log_message and Write-Host. A counter of remediated services is maintained.

.PARAMETER ProcessAllServices
This script reads the value set by the RMM in the variable `${Process All Services}` (string). Supported true values include: `1`, `y`, `yes`, `true` (case-insensitive). Supported false values include: `0`, `n`, `no`, `false`. If the variable is not set, the script defaults to processing only automatic services (`Start = 2`).

.INPUTS
None. The script reads registry values directly and does not accept pipeline input.

.OUTPUTS
- Writes log and informational messages via write_log_message and Write-Host.
- Updates the ImagePath value in HKLM for affected services.

.REQUIREMENTS
- Must run with administrative privileges to modify service registry entries under HKLM.
- A write_log_message function or equivalent must be defined and available in the session.
- Intended for Windows PowerShell/PowerShell on Windows.

.BEHAVIOR AND LIMITATIONS
- Only services with Start = 2 (automatic start) are processed.
- Only ImagePath values containing spaces are considered; paths already enclosed in matching starting and ending quotes are skipped.
- Parsing logic targets ".exe" and ".sys" occurrences to separate executable path from arguments. Complex ImagePath formats (environment-variable-based paths, UNC paths, nonstandard extensions, nested/escaped quotes, or multiple quoted segments) may not be parsed correctly.
- The current parsing may be case-sensitive and might mis-handle edge cases; verify results manually after changes.
- No dry-run/report-only mode is provided in the current implementation; the script updates the registry in-place.

.POTENTIAL RISKS
- Incorrect parsing and quoting can change service behavior or prevent services from starting. Always test in a non-production environment first.
- Modifying registry values can be disruptive; back up keys or create a system restore point before running.

.RECOMMENDATIONS
- Backup affected registry keys or create a system restore point before executing.
- Run the script from an elevated PowerShell session.
- Inspect the list of identified services and the new ImagePath values before and after remediation.
- Consider enhancing the script to:
    - Normalize case when searching for extensions (.exe/.sys).
    - Add a dry-run/report-only mode.
    - Improve parsing for environment variables, UNC paths and more complex quoting scenarios.
    - Log original and new values to an audit file.

.EXAMPLE
    .\unquoted_service_paths.ps1

    Scans and remediates unquoted service paths for automatically-starting services on the local machine.

.NOTES
Author: Fergus Barker
Date: June 2024
Version: 1.0
#>

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

function ConvertTo-BoolFromString {
    param([Parameter(Mandatory=$true)][string]$Value)
    if (-not $Value) { return $false }
    switch ($Value.Trim().ToLower()) {
        '1'     { return $true }
        'y'     { return $true }
        'yes'   { return $true }
        'true'  { return $true }
        't'     { return $true }
        'on'    { return $true }
        '0'     { return $false }
        'n'     { return $false }
        'no'    { return $false }
        'false' { return $false }
        'f'     { return $false }
        'off'   { return $false }
        default {
            try { return [bool]::Parse($Value) } catch { return $false }
        }
    }
}

# Read RMM-provided variable `${Process All Services}` and normalize to boolean
$ProcessAllServicesEffective = $false
try {
    $rmmValue = ${Process All Services}
} catch {
    $rmmValue = $null
}
if ($rmmValue) {
    $ProcessAllServicesEffective = ConvertTo-BoolFromString -Value ([string]$rmmValue)
}

$counter = 0
write_log_message "Starting Unquoted Service Path Checking" -Level "Info" -writeToConsole $true
if ($ProcessAllServicesEffective) { write_log_message "Processing all services regardless of 'Start' value." -Level "Info" -writeToConsole $true }
#Collect a list of IndividualServices running on the machine being checked
$installedServices = Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Services"
#Check each and every service
foreach ($individualService in $installedServices) {
    $imagePathExists = $false
    foreach ($Property in $individualService.Property) {
        #Does the service have an image path?
        if ($Property -eq "ImagePath") {
            $imagePathExists = $true 
            break;
        }
    }
    #If we cannot find an Image Path on the service we can move on and ignore
    if (-not($imagePathExists)) {
        continue
    }

    # Only process services set to auto start (Start = 2), unless $ProcessAllServices is set
    $startValue = $individualService.GetValue("Start")
    if (-not $ProcessAllServicesEffective) {
        if ($startValue -ne 2) {
            continue
        }
    }

    #Copy the image path variable so we can work with it in the scipt
    $imagePathCopy = [string]$individualService.GetValue("ImagePath")

    # If the imagePathCopy has no spaces we can ignore it
    if (-not ($imagePathCopy.Contains(" ")))
    { continue }

    #Variables for executable and parameters
    $executables = ""
    #$parameters = ""

    #Is this a driver with .SYS extension
    if ($imagePathCopy.Contains('.sys')) {
        # Split executable path and arguments for drivers
        if ($imagePathCopy.Contains('.sys"')) {
            $splitPoint = $imagePathCopy.IndexOf(".sys") + 5
            $executables = $imagePathCopy.Substring(0, $splitPoint)
            $arguments = ($imagePathCopy.Substring($splitPoint - 1))
        }
        else {
            $splitPoint = $imagePathCopy.IndexOf(".sys") + 4
            $executables = $imagePathCopy.Substring(0, $splitPoint)
            $arguments = ($imagePathCopy.Substring($splitPoint)) 
        }
        #Is this an executable file with a .exe extension
    }
    elseif ($imagePathCopy.Contains('.exe')) {
        # Split executable path and arguments for drivers
        if ($imagePathCopy.Contains('.exe"')) {
            $splitPoint = $imagePathCopy.IndexOf(".exe") + 5
            $executables = $imagePathCopy.Substring(0, $splitPoint)
            $arguments = ($imagePathCopy.Substring($splitPoint - 1))
        }
        else {
            $splitPoint = $imagePathCopy.IndexOf(".exe") + 4
            $executables = $imagePathCopy.Substring(0, $splitPoint)
            $arguments = ($imagePathCopy.Substring($splitPoint))
        }
    }

    #Check for spaces in the executable path
    If ($executables.Contains(' ')) {
        #Are there spaced and no quotes
        if (-not(($executables.StartsWith('"') -and $executables.EndsWith('"')))) {
            $counter++
            Write-Host "-----------------------------------"
            # Add quotes
            write_log_message "$($Individualservice.name) was identified with an unquoted path ($imagePathCopy)" -level "Warning" -writeToConsole $true
            $executables = "`"$executables`""
            $NewImagePath = "$executables$arguments"
            # Change registry path to add the quotes
            $IndividualServicePath = $individualService.Name.Replace("HKEY_LOCAL_MACHINE", "HKLM:")
            # Update the ImagePath
            write_log_message "changing to $NewImagePath" -level "Info" -writeToConsole $true
            Set-ItemProperty -Path $IndividualServicePath -Name "ImagePath" -Value $newImagePath
            write_log_message "$($Individualservice.name) has been remediated to use quoted path ($NewImagePath)" -level "Success" -writeToConsole $true
        }
    }
}

#TODO: list all services that were changed and their new paths
write_log_message "Completed Unquoted Service Path Checking" -Level "Info" -writeToConsole $true
write_log_message "$counter services were identified and remediated" -Level "Success" -writeToConsole $true