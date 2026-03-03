# Define the ciphers to disable
$ciphers = @(
    "DES 56/56",
    "Triple DES 168",
    "IDEA 128/128",
    "RC2 128/128",
    "RC4 128/128",
    "RC4 56/128",
    "RC4 40/128"
)
[int]$Script:DisabledCiphers = 0

# Function to disable a cipher
function disable_cipher {
    param (
        [string]$cipher
    )
    $regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Ciphers\$cipher"

    # Build a result object to return for logging/processing
    $result = [PSCustomObject]@{
        Cipher = $cipher
        RegPath = $regPath
        Created = $false
        PreviousEnabled = $null
        Disabled = $false
        Success = $false
        Error = $null
        Timestamp = (Get-Date).ToString("o")
        SetValue = 0
        Messages = @()
    }

    # helper to append messages with level and timestamp
    $addMessage = {
        param($level, $msg)
        $result.Messages += [PSCustomObject]@{
            Level = $level
            Message = $msg
            Timestamp = (Get-Date).ToString("o")
        }
    }

    & $addMessage -level 'Info' -msg "Starting disable operation for cipher '$cipher'"

    if (-Not (Test-Path $regPath)) {
        try {
            New-Item -Path $regPath -Force | Out-Null
            $result.Created = $true
            & $addMessage -level 'Verbose' -msg "Created registry key '$regPath'"
        }
        catch {
            $result.Error = "Failed to create registry key: $_"
            & $addMessage -level 'Error' -msg $result.Error
            return $result
        }
    }

    try {
        $existing = Get-ItemProperty -Path $regPath -Name "Enabled" -ErrorAction SilentlyContinue
        if ($null -eq $existing) {
            $result.PreviousEnabled = $existing.Enabled
            & $addMessage -level 'Debug' -msg "Previous 'Enabled' value: $($existing.Enabled)"
        }
        else {
            & $addMessage -level 'Debug' -msg "No previous 'Enabled' value found"
        }
    }
    catch {
        & $addMessage -level 'Warning' -msg "Unable to read existing 'Enabled' value: $_"
        $result.PreviousEnabled = $null
    }

    try {
        Set-ItemProperty -Path $regPath -Name "Enabled" -Value 0 -ErrorAction Stop
        $Script:DisabledCiphers++
        $result.Disabled = $true
        $result.Success = $true
        $result.SetValue = 0
        & $addMessage -level 'Info' -msg "Set 'Enabled' to 0 on '$regPath'"
        & $addMessage -level 'Success' -msg "Cipher '$cipher' disabled successfully"
    }
    catch {
        $result.Error = $_.Exception.Message
        & $addMessage -level 'Error' -msg "Failed to set 'Enabled' to 0: $($result.Error)"
    }

    # capture a final debug snapshot
    & $addMessage -level 'Debug' -msg ("Result summary: Created={0}, PreviousEnabled={1}, Disabled={2}, Success={3}, Error={4}" -f $result.Created, $result.PreviousEnabled, $result.Disabled, $result.Success, $result.Error)

    return $result
}
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
# Disable each cipher and collect results
$cipherResults = foreach ($cipher in $ciphers) {
    $result = disable_cipher -cipher $cipher
    if ($result.Disabled) {
        write_log_message -message "Processed cipher '$cipher'. Disabled: $($Script:DisabledCiphers)/$($ciphers.Count)" -level "Info" -writeToConsole $true
    }
    else {
        write_log_message -message "Failed to disable cipher '$cipher'. Error: $($result.Error)" -level "Error" -writeToConsole $true
    }
}


# Summary: report using the collected results
$disabledCount = ($cipherResults | Where-Object { $_.Disabled } | Measure-Object).Count
write_log_message -message "$disabledCount/$($ciphers.Count) specified ciphers have been disabled."
# Return the results so a logging function can parse them
#return $cipherResults