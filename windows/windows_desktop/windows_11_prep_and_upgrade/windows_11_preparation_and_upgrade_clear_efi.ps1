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

# Mount the EFI System Partition to Y:
write_log_message -message "Mounting EFI System Partition to Y: drive." -level "Info" -writeToConsole $true
try {
    mountvol Y: /s
    write_log_message -message "EFI System Partition mounted successfully." -level "Success" -writeToConsole $true
} catch {
    write_log_message -message "Failed to mount EFI System Partition: $_" -level "Error" -writeToConsole $true
    throw
}

# Delete all files in the Fonts folder
write_log_message -message "Clearing EFI Fonts folder." -level "Info" -writeToConsole $true
$fontsPath = "Y:\EFI\Microsoft\Boot\Fonts"
if (Test-Path $fontsPath) {
    try {
        Get-ChildItem -Path $fontsPath -Recurse | Remove-Item -Force -Recurse
        write_log_message -message "EFI Fonts folder cleared successfully." -level "Success" -writeToConsole $true
    } catch {
        write_log_message -message "Failed to clear EFI Fonts folder: $_" -level "Error" -writeToConsole $true
        throw
    }
}

# Create destination folder if it doesn't exist
write_log_message -message "Preparing destination folder for HP DEVFW files." -level "Info" -writeToConsole $true
$destPath = "C:\Install\HPDEVFW"
if (-not (Test-Path $destPath)) {
    write_log_message -message "Creating directory $destPath." -level "Info" -writeToConsole $true
    try {
        New-Item -Path $destPath -ItemType Directory -Force | Out-Null
        write_log_message -message "Directory $destPath created successfully." -level "Success" -writeToConsole $true
    } catch {
        write_log_message -message "Failed to create directory $($destPath): $_" -level "Error" -writeToConsole $true
        throw
    }
}

# Move HP DEVFW files to C:\Install\HPDEVFW
write_log_message -message "Moving HP DEVFW files to $destPath." -level "Info" -writeToConsole $true
$sourcePath = "Y:\EFI\HP\DEVFW"
if (Test-Path $sourcePath) {
    try {
        Get-ChildItem -Path $sourcePath -Recurse | ForEach-Object {
            $destination = Join-Path -Path $destPath -ChildPath $_.FullName.Substring($sourcePath.Length).TrimStart('\')
            $destinationDir = Split-Path -Path $destination -Parent
            if (-not (Test-Path $destinationDir)) {
                New-Item -Path $destinationDir -ItemType Directory -Force | Out-Null
            }
            Move-Item -Path $_.FullName -Destination $destination -Force
        }
        write_log_message -message "HP DEVFW files moved successfully to $($destPath)." -level "Success" -writeToConsole $true
    } catch {
        write_log_message -message "Failed to move HP DEVFW files: $_" -level "Error" -writeToConsole $true
        throw
    }
}

# Dismount the EFI System Partition
write_log_message -message "Dismounting EFI System Partition from Y: drive." -level "Info" -writeToConsole $true
try {
    mountvol Y: /d
    write_log_message -message "EFI System Partition dismounted successfully." -level "Success" -writeToConsole $true
} catch {
    write_log_message -message "Failed to dismount EFI System Partition: $_" -level "Error" -writeToConsole $true
    throw
}
