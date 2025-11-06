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
        Write-Host $logEntry -ConsoleColour $consoleColour
    }
    # Append to log file
    $logFilePath = "$env:TEMP\$(get-date -f "yyyy-MM-dd")_$($scriptName).log"
    Add-Content -Path $logFilePath -Value $logEntry
}

# Variables: adjust as required
$installFolder = "C:\Program Files*\Dell\SupportAssist"  # adjust if x64 only or different path
$exeName = "SupportAssistApp.exe"
$downloadUrl = "https://downloads.dell.com/serviceability/catalog/SupportAssistBusinessInstaller.exe"  # put correct URL here
$tempInstaller = "$env:TEMP\SupportAssist_Update.exe"
$silentArgs = "/S /v /qn /norestart"  # Example silent install arguments – adjust per installer

write_log_message "Checking for existing SupportAssist installation..." -writeToConsole $true

# Check if the folder/exe exists
if (Test-Path (Join-Path $installFolder $exeName)) {
    write_log_message "SupportAssist appears installed at $installFolder" -writeToConsole $true
} else {
    write_log_message "SupportAssist not found at expected location. Exiting." -writeToConsole $true
    exit 1
}

# Download new installer
write_log_message "Downloading installer from $downloadUrl..." -writeToConsole $true
Invoke-WebRequest -Uri $downloadUrl -OutFile $tempInstaller

# Verify download
if (-not (Test-Path $tempInstaller)) {
    write_log_message "Download failed."
    exit 1
}

# Optionally stop any running instance/service
write_log_message "Stopping running SupportAssist processes..." -writeToConsole $true
Get-Process -Name "SupportAssist*" -ErrorAction SilentlyContinue | Stop-Process -Force

# Run installer
write_log_message "Launching installer..." -writeToConsole $true
$process = Start-Process -FilePath $tempInstaller -ArgumentList $silentArgs -Wait -PassThru
if ($process.ExitCode -eq 0) {
    write_log_message "Update installation succeeded." -writeToConsole $true 
} else {
    write_log_message "Installer returned exit code $($process.ExitCode)." -writeToConsole $true     
    exit 1
}

# Clean up
write_log_message "Cleaning up installer file..." -writeToConsole $true
Remove-Item -Path $tempInstaller -Force

write_log_message "Update of SupportAssist complete. A reboot may be required." -writeToConsole $true
exit 0
