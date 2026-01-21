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
function test_protected_path {
    <#
    .SYNOPSIS
        Check if provided path(s) are inside protected/system locations (e.g. C:\Windows).
    .OUTPUTS
        Array of protected paths that were detected (empty if none).
    #>
    param(
        [Parameter(Mandatory = $true)][string[]]$Path
    )

    # Common protected locations (expanded)
    $protectedBases = @()
    if ($env:SystemRoot) { $protectedBases += (Get-Item -Path $env:SystemRoot -ErrorAction SilentlyContinue).FullName }
    if ($env:ProgramFiles) { $protectedBases += (Get-Item -Path $env:ProgramFiles -ErrorAction SilentlyContinue).FullName }
    if (${env:ProgramFiles(x86)}) { $protectedBases += (Get-Item -Path ${env:ProgramFiles(x86)} -ErrorAction SilentlyContinue).FullName }
    if ($env:ProgramW6432) { $protectedBases += (Get-Item -Path $env:ProgramW6432 -ErrorAction SilentlyContinue).FullName }

    $protectedBases = $protectedBases | Where-Object { $_ } | ForEach-Object { $_.TrimEnd('\') + '\' } | Select-Object -Unique

    $detectedProtectedPaths = @()
    foreach ($p in $Path) {
        $exp = expand_cmd_path -Path $p
        # Try to resolve items (supports wildcards)
        $items = Get-ChildItem -Path $exp -Force -ErrorAction SilentlyContinue
        if ($items) {
            foreach ($it in $items) {
                foreach ($base in $protectedBases) {
                    if ($it.FullName.StartsWith($base, [System.StringComparison]::InvariantCultureIgnoreCase)) {
                        $detectedProtectedPaths += $it.FullName
                        break
                    }
                }
            }
        }
        else {
            # Try Resolve-Path, fallback to expanded string
            $resolved = (Resolve-Path -Path $exp -ErrorAction SilentlyContinue).Path
            if (-not $resolved) { $resolved = $exp }
            foreach ($base in $protectedBases) {
                if ($resolved.StartsWith($base, [System.StringComparison]::InvariantCultureIgnoreCase)) {
                    $detectedProtectedPaths += $resolved
                    break
                }
            }
        }
    }
    return $detectedProtectedPaths | Select-Object -Unique
}
function remove_file {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $false)][switch]$WhatIf = $false,
        [Parameter(Mandatory = $false)][switch]$Force = $false
    )

    $expandedPath = expand_cmd_path -Path $FilePath

    # Check for protected/system paths and require -Force to proceed
    $protectedMatches = test_protected_path -Path $expandedPath
    if ($protectedMatches -and $protectedMatches.Count -gt 0) {
        if (-not $Force) {
            write_log_message "Protected/system path detected: $($protectedMatches -join ', '). Use -Force to override." -Level "Error" -WriteToConsole $true
            return
        }
        else {
            write_log_message "Protected/system path detected but -Force specified. Proceeding to remove: $($protectedMatches -join ', ')" -Level "Warning" -WriteToConsole $true
        }
    }

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
function ConvertTo-BoolFlag {
    param(
        [object]$Value,
        [bool]$Default = $false
    )

    if ($null -eq $Value) { return $Default }
    if ($Value -is [bool]) { return [bool]$Value }
    if ($Value -is [int] -or $Value -is [long] -or $Value -is [double]) { return ($Value -ne 0) }

    $s = [string]$Value
    if (-not $s) { return $Default }
    $s = $s.Trim().ToLowerInvariant()

    if ($s -in @('1','true','yes','y','on')) { return $true }
    if ($s -in @('0','false','no','n','off','')) { return $false }

    # Fallback: non-empty string => true
    if ($s) { return $true }
    return $Default
}

$forced = ConvertTo-BoolFlag ${ForceFlag}
$WhatIf = ConvertTo-BoolFlag ${WhatIfFlag}

# Call remove_file with explicit boolean parameter binding (works for switch or bool parameters)
remove_file -FilePath ${Full File Path} -WhatIf:$WhatIf -Force:$forced


#remove_file -FilePath "C:\Windows\notepad - Copy.exe"