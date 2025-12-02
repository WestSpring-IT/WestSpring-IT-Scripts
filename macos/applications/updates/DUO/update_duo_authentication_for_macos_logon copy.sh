param (
    [string]$duoInstallerUrl = "https://dl.duosecurity.com/duo-win-login-latest.exe",
    [string]$duoIntegrationKey = "DIL4TGIOWG1XHC7HWQN2", #"{[DUO_INTEGRATION_KEY]}",
    [string]$duoSecretKey = "bNMyBuPwmNpNcCnXBwCWYdGke5cWj4s0ydAR7cjr",#"{[DUO_SECRET_KEY]}",
    [string]$duoApiHost = "api-4a817029.duosecurity.com"#"{[DUO_API_HOST]}"
)
## Define Functions
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
        [bool]$whatIf = $false,
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
    if ($whatIf) {
        Write-Host "WhatIf is enabled. Download simulation complete." -ForegroundColor Yellow
        $success = $true
            } else {
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

#Check for existing DUO installation
$oldDuo = @{}
$targetDisplayName = 'Duo Authentication for Windows Logon*'
$searchPaths = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
)

$foundKey = $null
foreach ($p in $searchPaths) {
    try {
        $children = Get-ChildItem -Path $p -ErrorAction SilentlyContinue
        foreach ($c in $children) {
            try {
                $props = Get-ItemProperty -Path $c.PSPath -ErrorAction SilentlyContinue
                if ($props.DisplayName -like $targetDisplayName) {
                    $foundKey = $c.PSPath
                    break
                }
            } catch {}
        }
        if ($foundKey) { break }
    } catch {}
}

if ($foundKey) {
    $oldDuo.RegistryPath = $foundKey
    try {
        $oldDuo.InstalledVersion = (Get-ItemProperty -Path $foundKey -ErrorAction SilentlyContinue).DisplayVersion
    } catch { $oldDuo.InstalledVersion = $null }
    write_log_message -message "DUO Authentication for Windows Logon is currently installed. Registry key: $foundKey. Version: $($oldDuo.InstalledVersion)" -level "Info" -writeToConsole $true
    if ([version]$oldDuo.InstalledVersion -ge [version]"5.1.1") {
        write_log_message -message "DUO Authentication for Windows Logon is already at version $($oldDuo.InstalledVersion) or higher. No upgrade needed." -level "Info" -writeToConsole $true
        exit 0
    }
    $oldDuo.Upgrade = $true
} else {
    write_log_message -message "DUO Authentication for Windows Logon not found in registry (DisplayName search)." -level "Warning" -writeToConsole $true
    $oldDuo.Upgrade = $false
}

if ($oldDuo.Upgrade) {
    #Download DUO installer
    $downloadResult = download_file -Uri $duoInstallerUrl -filePath "$env:TEMP" -MaxTries 3 -ProgressPreference "SilentlyContinue"
    if ($downloadResult.success) {
        write_log_message -message "DUO installer downloaded successfully: $($downloadResult.fullPath) (Size: $($downloadResult.fileSize) MB, Time: $($downloadResult.totalTime) seconds)" -level "Success" -writeToConsole $true
        write_log_message -message "Downloaded version: $(Get-ItemProperty -Path $downloadResult.fullPath).VersionInfo.ProductVersion" -level "Info" -writeToConsole $true
    }
    else {
        write_log_message -message "Failed to download DUO installer after $($downloadResult.attempt) attempts." -level "Error" -writeToConsole $true
        exit 1
    }

    #Install DUO with silent parameters
    
    $msiInner = "/qn IKEY=`"$duoIntegrationKey`" SKEY=`"$duoSecretKey`" HOST=`"$duoApiHost`" AUTOPUSH=`"#1`" FAILOPEN=`"#1`" SMARTCARD=`"#1`" RDPONLY=`"#0`""
    $installArgs = "/S /V`"$msiInner`""
    write_log_message -message "Starting DUO installation with arguments: $installArgs" -level "Info" -writeToConsole $true
    $installProcess = Start-Process -FilePath $downloadResult.fullPath -ArgumentList $installArgs -Wait -PassThru

    if ($installProcess.ExitCode -eq 0) {
        # Search registry again for the updated version (in case the registry path changed)
        $newDuo = @{}
        $foundNewKey = $null
        foreach ($p in $searchPaths) {
            try {
                $children = Get-ChildItem -Path $p -ErrorAction SilentlyContinue
                foreach ($c in $children) {
                    try {
                        $props = Get-ItemProperty -Path $c.PSPath -ErrorAction SilentlyContinue
                        if ($props.DisplayName -like 'Duo Authentication for Windows Logon*') {
                            $foundNewKey = $c.PSPath
                            break
                        }
                    } catch {}
                }
                if ($foundNewKey) { break }
            } catch {}
        }

        if ($foundNewKey) {
            try {
                $newDuo.InstalledVersion = (Get-ItemProperty -Path $foundNewKey -ErrorAction SilentlyContinue).DisplayVersion
            } catch { $newDuo.InstalledVersion = $null }
            write_log_message -message "DUO Authentication for Windows Logon updated successfully to version $($newDuo.InstalledVersion)." -level "Success" -writeToConsole $true
        } else {
            write_log_message -message "DUO installation completed but could not verify version in registry." -level "Warning" -writeToConsole $true
        }
        exit 0
    }
    else {
        write_log_message -message "DUO installation failed with exit code: $($installProcess.ExitCode)" -level "Error" -writeToConsole $true
        exit 1
    }
}