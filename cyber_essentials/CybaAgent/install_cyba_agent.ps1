Param(
    [Parameter(Mandatory = $false, HelpMessage = "URI to download the Cyba Agent installer from.")]
    [string]$Uri = "https://wsprodfileuksouth.blob.core.windows.net/clients/cyber_essentials/agents/cybaagent/CybaAgent-Windows.exe",
    [Parameter(Mandatory = $false, HelpMessage = "Installation string for the Cyba Agent.")]
    [string]$installString = "{[InstallString]}"
)

$installString = $installString.Replace(".\CybaAgent.exe ", "").Trim()

function download_file {
    <#
        .SYNOPSIS
        Downloads a file from a specified URI with retry logic and returns download details.

        .DESCRIPTION
        The download_file function downloads a file from the provided URI to a specified fullPath path.
        It follows redirects to get the actual download URL, supports retrying the download on failure,
        and returns an object containing file details such as name, fullPath, size, and download time.

        .PARAMETER Uri
        The URI of the file to download. This parameter is mandatory.

        .PARAMETER fileName
        The name of the downloaded file. If not specified, defaults to the name extracted from the URI.

        .PARAMETER fullPath
        The path where the downloaded file will be saved. If not specified, defaults to the TEMP path.

        .PARAMETER MaxTries
        The maximum number of download attempts in case of failure. Defaults to 3.

        .PARAMETER ProgressPreference
        Specifies how progress is displayed during download. Defaults to "SilentlyContinue".

        .OUTPUTS
        [PSCustomObject]
        Returns an object with the following properties:
        - fileName: Name of the downloaded file.
        - fullPath: Path of the downloaded file.
        - fileSize: Size of the downloaded file in megabytes.
        - totalTime: Time taken to complete the download in seconds.

        .EXAMPLE
        download_file -Uri "https://example.com/file.zip" -fullPath "C:\Downloads\file.zip"

        .EXAMPLE
        download_file -Uri "https://example.com/file.zip"

        .EXAMPLE
        $result = download_file -Uri "https://example.com/file.zip" -MaxTries 5
        Write-Host "Downloaded file size: $($result.fileSize) MB"

        .NOTES
        Requires PowerShell 5.0 or later.
        #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri,
        [string]$fileName,
        [string]$filePath = "$env:TEMP",
        [int]$MaxTries = 3,
        [string]$ProgressPreference = "SilentlyContinue"
    )

    # If no filename provided, extract from final redirected URL
    if (-not $fileName) {
        $Link = [System.Net.HttpWebRequest]::Create($Uri).GetResponse().ResponseUri.AbsoluteUri
        Write-Host $link #debug
        $fileName = [uri]::UnescapeDataString($Link) | Split-Path -Leaf
    }
    # Create target path if it doesn't exist
    if (!(Test-Path -Path $filePath)) {
        try {
            New-Item -ItemType Directory -Path $filePath | Out-Null
        }
        catch {
            Write-Host "Failed to create path $($filePath): $($_.Exception.Message)" -ForegroundColor Red
            return $false
        }
    }

    # Ensure fullPath uses the provided or derived filename
    $fullPath = Join-Path -Path $filePath -ChildPath $fileName

    # Set TLS 1.2 for secure downloads
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $attempt = 0
    $success = $false
    $startTime = Get-Date -Format "HH:mm:ss"


    
    Write-Host "Starting download of $fileName from $Uri to $fullPath" -ForegroundColor Cyan
    while (-not $success -and $attempt -lt $MaxTries) {
        try {
            $attempt++
            Invoke-WebRequest -Uri $Uri -OutFile $fullPath -ErrorAction Stop
            Write-Host "Download succeeded on attempt $($attempt): $fullPath" -ForegroundColor Green
            $success = $true
        }
        catch {
            Write-Host "Download failed on attempt $($attempt): $($_.Exception.Message)" -ForegroundColor Yellow
            Start-Sleep -Seconds 2
        }
    }
    $endTime = Get-Date -Format "HH:mm:ss"
    $totalTime = (New-TimeSpan -Start $startTime -End $endTime).TotalSeconds
    if (-not $success) {
        Write-Host "Failed to download file after $MaxTries attempts." -ForegroundColor Red
        $result = [PSCustomObject]@{
            success   = $false
            fileName  = $fileName
            fullPath  = $fullPath
            fileSize  = [math]::Round((Get-Item $fullPath).Length / 1MB, 4)
            totalTime = [math]::Round($totalTime, 2)
            attempt   = $attempt
        } 
    }
    else {
        $result = [PSCustomObject]@{
            success   = $true
            fileName  = $fileName
            fullPath  = $fullPath
            fileSize  = [math]::Round((Get-Item $fullPath).Length / 1MB, 4)
            totalTime = [math]::Round($totalTime, 2)
            attempt   = $attempt
        }
    }
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
write_log_message -message "Starting Cyba Agent installation script." -level "Info" -writeToConsole $true
$downloadRestult = download_file -Uri $Uri -fileName "CybaAgent.exe" -filePath "$env:TEMP" -MaxTries 5 -ProgressPreference "SilentlyContinue"

if ($downloadRestult.success) {
    write_log_message -message "Downloaded Cyba Agent installer to $($downloadRestult.fullPath) in $($downloadRestult.totalTime) seconds (Size: $($downloadRestult.fileSize) MB)" -level "Success" -writeToConsole $true
    # Install the agent
    write_log_message -message "Starting Cyba Agent installation..." -level "Info" -writeToConsole $true
    try {
        $process = Start-Process -FilePath $downloadRestult.fullPath -ArgumentList $installString -Wait -PassThru
        while ($process -and $process.HasExited -eq $false) {
            Start-Sleep -Seconds 1
        }

        # Retrieve child process exit code (fall back to 1 if unavailable)
        $exitCode = 1
        if ($process -and $process -is [System.Diagnostics.Process]) {
            try { $exitCode = [int]$process.ExitCode } catch { $exitCode = 1 }
        }

        $service = Get-Service -Name "CybaVerse CybaAgent" -ErrorAction SilentlyContinue
        $serviceRunning = $false
        if ($service) { $serviceRunning = $service.Status -eq 'Running' }

        # Log details but always preserve and return the child's exit code
        if ($exitCode -eq 0 -and $serviceRunning) {
            write_log_message -message "Cyba Agent installed successfully (ExitCode: $exitCode; ServiceRunning: $serviceRunning)." -level "Success" -writeToConsole $true
        }
        else {
            $level = if ($exitCode -ne 0) { 'Error' } elseif (-not $serviceRunning) { 'Warning' } else { 'Info' }
            write_log_message -message "Cyba Agent installation completed (ExitCode: $exitCode; ServiceRunning: $serviceRunning)." -level $level -writeToConsole $true
        }

        # Preserve exit code from child process in all cases
        $global:LASTEXITCODE = $exitCode
        [Environment]::Exit($exitCode)
    }
    catch {
        write_log_message -message "Exception during Cyba Agent installation: $($_.Exception.Message)" -level "Error" -writeToConsole $true
        $errCode = 1
        if ($process -and $process -is [System.Diagnostics.Process]) {
            try { $errCode = [int]$process.ExitCode } catch { $errCode = 1 }
        }
        $global:LASTEXITCODE = $errCode
        [Environment]::Exit($errCode)
    }
}
else {
    write_log_message -message "Failed to download Cyba Agent installer after $($downloadRestult.attempt) attempts." -level "Error" -writeToConsole $true
    $global:LASTEXITCODE = 2
    [Environment]::Exit(2)
}
