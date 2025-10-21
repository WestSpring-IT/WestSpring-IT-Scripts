##NOTE: THIS HAS TO RUN IN 64-BIT MODE!
##Set this URL
$url = ""
$directory = "C:\Users\Public\Pictures"

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
    $Global:scriptName = $null
    $Global:scriptName = $(Split-Path $MyInvocation.ScriptName -Leaf).TrimEnd(".ps1")
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
    $Global:logFilePath = $null
    $Global:logFilePath = "$env:TEMP\$(get-date -f "yyyy-MM-dd")_$($Global:scriptName).log"
    Add-Content -Path $Global:logFilePath -Value $logEntry
}
function download_file {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri,
        [string]$Destination = "$env:TEMP\$(Split-Path $Uri -Leaf)",
        [int]$MaxTries = 3,
        [string]$ProgressPreference = "SilentlyContinue"
    )

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $fileName = [System.IO.Path]::GetFileName($Uri)
    $fullPath = Join-Path -Path $directory -ChildPath $fileName
    $attempt = 0
    $success = $false

    Write-Host "Starting download of $fileName from $Uri to $Destination" -ForegroundColor Cyan
    while (-not $success -and $attempt -lt $MaxTries) {
        try {
            $attempt++
            Invoke-WebRequest -Uri $Uri -OutFile $fullPath -UseBasicParsing -ErrorAction Stop
            Write-Host "Download succeeded on attempt $($attempt): $Destination" -ForegroundColor Green
            $success = $true
        } catch {
            Write-Host "Download failed on attempt $($attempt): $($_.Exception.Message)" -ForegroundColor Yellow
            Start-Sleep -Seconds 2
        }
    }

    if (-not $success) {
        Write-Host "Failed to download file after $MaxTries attempts." -ForegroundColor Red
        return $false
    }
    $result = [PSCustomObject]@{
        fileName    = $fileName
        destination = $destination
        fullPath    = $fullPath
        fileSize    = [math]::Round((Get-Item $Destination).Length /1MB, 2)
        attempts    = $attempt
        success     = $success
    }
    return $result
}

if (!(Test-Path -Path $directory)) {
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    write_log_message "Created directory: $directory"
} else {
    write_log_message "Directory already exists: $directory"
}
$result = download_file -Uri $url -destination $directory -MaxTries 3

$regKeyPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP"
$desktopPath = "DesktopImagePath"
$desktopStatus = "DesktopImageStatus"
$desktopUrl = "DesktopImageUrl"
$statusValue = "1"

if (!($result.destination)) {
    write_log_message "Download failed, exiting script." -level "Error" -writeToConsole $true
    exit 1
}

$desktopImageValue = Join-Path -Path $result.destination -ChildPath $result.fileName

if (!(Test-Path $regKeyPath))
{
write_log_message "Creating registry path $($regKeyPath)."
New-Item -Path $regKeyPath -Force | Out-Null
}
try {
    New-ItemProperty -Path $regKeyPath -Name $desktopStatus -Value $statusvalue -PropertyType DWORD -Force | Out-Null
    New-ItemProperty -Path $regKeyPath -Name $desktopPath -Value $desktopImageValue -PropertyType STRING -Force | Out-Null
    New-ItemProperty -Path $regKeyPath -Name $desktopUrl -Value $desktopImageValue -PropertyType STRING -Force | Out-Null
    write_log_message "Successfully set custom wallpaper to $desktopImageValue" -level "Success" -writeToConsole $true
    write_log_message "New wallpaper will be applied on next user login or after a restart."  -level "Info" -writeToConsole $true
}
catch {
    write_log_message "Error setting registry values: $_" -level "Error" -writeToConsole $true
    exit 1
}
write_log_message "Script completed. Log file located at $Global:logFilePath" -level "Info" -writeToConsole $true
