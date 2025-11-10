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
        "Success" { $consoleColour = "Green" }
        "Info" { $consoleColour = "Cyan" }
        "Warning" { $consoleColour = "Yellow" }
        "Error" { $consoleColour = "Red" }
    }
    if ($writeToConsole) {
        Write-Host $logEntry -ForegroundColor $consoleColour
    }
    # Append to log file
    $logFilePath = "$env:TEMP\$(get-date -f "yyyy-MM-dd")_$($scriptName).log"
    Add-Content -Path $logFilePath -Value $logEntry
}
function expand_cmd_path {
    param([string]$Path)
    if (-not $Path) { return $Path }
    $p = $Path.Trim()
    # Expand %ENV% style variables
    try {
        $expanded = [Environment]::ExpandEnvironmentVariables($p)
    }
    catch {
        $expanded = $p
    }
    # Expand leading ~ to user profile
    if ($expanded -like '~*') {
        $expanded = $expanded -replace '^~', $env:USERPROFILE
    }
    return $expanded
}
function remove_file {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $false)][switch]$WhatIf = $false
    )

    $expandedPath = expand_cmd_path -Path $FilePath

    # Resolve wildcards for directories
    $resolvedDirs = Get-ChildItem -Path $expandedPath -Directory -ErrorAction SilentlyContinue

    if ($resolvedDirs) {
        foreach ($dir in $resolvedDirs) {
            if ($WhatIf) {
                write_log_message "WhatIf: Would remove directory: $($dir.FullName)" -Level "Info" -WriteToConsole $true
                continue
            }
            else {
                write_log_message "Removing directory: $($dir.FullName)" -Level "Info" -WriteToConsole $true
                Remove-Item -Path $dir.FullName -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    # Resolve wildcards for files
    $resolvedFiles = Get-ChildItem -Path $expandedPath -File -ErrorAction SilentlyContinue

    if ($resolvedFiles) {
        foreach ($file in $resolvedFiles) {
            if ($WhatIf) {
                write_log_message "WhatIf: Would remove file: $($file.FullName)" -Level "Info" -WriteToConsole $true
                continue
            }
            else {
                write_log_message "Removing file: $($file.FullName)" -Level "Info" -WriteToConsole $true
                Remove-Item -Path $file.FullName -Force -ErrorAction SilentlyContinue
            }
        }

        if ((-not $resolvedDirs -or $resolvedDirs.Count -eq 0) -and (-not $resolvedFiles -or $resolvedFiles.Count -eq 0)) {
            write_log_message "No files or directories found matching: $FilePath (expanded: $expandedPath)" -Level "Warning" -WriteToConsole $true
        }
    }
}

remove_file -FilePath "{[FullFilePath]}"