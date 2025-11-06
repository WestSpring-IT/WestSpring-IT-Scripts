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

write_log_message "Enabling Reputation-Based Protection settings..."

try {
    # Enable PUA protection: block mode
    Set-MpPreference -PUAProtection Enabled
    write_log_message "PUAProtection set to Enabled."

    # Ensure SmartScreen “Check apps and files” is enabled via registry policy:
    # HKLM\SOFTWARE\Policies\Microsoft\Windows\System\EnableSmartScreen = 1 (DWORD)
    $regPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
    If (-not (Test-Path $regPath)) {
        New-Item -Path $regPath -Force | Out-Null
    }
    Set-ItemProperty -Path $regPath -Name "EnableSmartScreen" -Value 1 -Type DWord -Force
    write_log_message "SmartScreen 'Check apps and files' enabled."

    # (Optional) SmartScreen for Edge – block bypass:
    # HKLM\SOFTWARE\Policies\Microsoft\Edge\SafeBrowsingEnabled = 1
    $edgeRegPath = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
    If (-not (Test-Path $edgeRegPath)) {
        New-Item -Path $edgeRegPath -Force | Out-Null
    }
    Set-ItemProperty -Path $edgeRegPath -Name "SafeBrowsingEnabled" -Value 1 -Type DWord -Force
    write_log_message "Edge SmartScreen enabled via policy."

    # Force a policy update / refresh (optional)
    gpupdate /force | Out-Null

    write_log_message "Reputation-based protection has been configured. A restart may be required for all settings to take full effect." -ForegroundColor Green
}
catch {
    write_log_message "Error occurred: $_" "Error"
}