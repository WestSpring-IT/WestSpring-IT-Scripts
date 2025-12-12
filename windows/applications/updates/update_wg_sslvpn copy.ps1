#Parameter definitions and function declarations
[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [ValidateSet('yes','y','no','n')]
    [string]$forceInstall = 'yes',#"{[Force_Install]}",
    [Parameter(Mandatory=$false)]
    [string]$Uri = "https://cdn.watchguard.com/SoftwareCenter/Files/MUVPN_SSL/12_11_5/WG-MVPN-SSL_12_11_5.exe"
)


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

        .NOTES
        Requires PowerShell 5.0 or later.
        #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri,
        [Parameter(Mandatory = $false)]
        [string]$fileName,
        [Parameter(Mandatory = $false)]
        [string]$filePath = "$env:TEMP",
        [Parameter(Mandatory = $false)]
        [int]$MaxTries = 3,
        [Parameter(Mandatory = $false)]
        [string]$Script:ProgressPreference = "SilentlyContinue"
    )

    # If no filename provided, extract from final redirected URL
    if (-not $fileName) {
        $Link = [System.Net.HttpWebRequest]::Create($Uri).GetResponse().ResponseUri.AbsoluteUri
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
        } 
    }
    else {
        $result = [PSCustomObject]@{
            success   = $true
            fileName  = $fileName
            fullPath  = $fullPath
            fileSize  = [math]::Round((Get-Item $fullPath).Length / 1MB, 4)
            totalTime = [math]::Round($totalTime, 2)
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


if ($forceInstall -like "yes" -or $forceInstall -like "y") {
        $forceInstallFlag = $true
    } else {
    $forceInstallFlag = $false
}

# --- Main script ---
$wgVpnRegPath = "HKLM:SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Mobile VPN with SSL client*"
$wgVpnVersion = $null

if (Test-Path $wgVpnRegPath) {
    try {
        $wgVpnVersion = (Get-ItemProperty -Path $wgVpnRegPath -ErrorAction Stop).DisplayVersion
        write_log_message -message "Current installed WG SSL VPN Client version (from registry): $wgVpnVersion" -level "Info" -writeToConsole $true
    } catch {
        write_log_message -message "Unable to retrieve WG SSL VPN Client version from registry: $($_.Exception.Message)" -level "Warning" -writeToConsole $true
    }
} else {
    write_log_message -message "WG SSL VPN Client is not currently installed (no registry entry found)." -level "Warning" -writeToConsole $true
}

# If force install requested, stop the VPN client and disable the TAP adapter BEFORE downloading
$preppedForInstall = $false

if ($forceInstallFlag) {
    write_log_message -message "Force install requested. Preparing system: stopping VPN client and disabling adapter before download." -level "Info" -writeToConsole $true

    $appRunning = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "wgsslvpnc" }
    $NetAdapter = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.InterfaceDescription -eq "TAP-Windows Adapter V9" }

    # Stop client (up to 3 attempts: graceful then forced)
    if ($null -ne $appRunning) {
        write_log_message -message "WatchGuard SSL VPN Client is currently running. Attempting to stop (up to 3 attempts)." -level "Warning" -writeToConsole $true
        $stopAttempt = 0
        $maxAttempts = 3
        $stopped = $false
        while ($stopAttempt -lt $maxAttempts) {
            $stopAttempt++
            if ($stopAttempt -eq 1) {
                try { Stop-Process -Id $appRunning.Id -ErrorAction SilentlyContinue } catch {}
            } else {
                try { Stop-Process -Id $appRunning.Id -Force -ErrorAction SilentlyContinue } catch {}
            }
            Start-Sleep -Seconds 5
            $appRunning = Get-Process -Id $appRunning.Id -ErrorAction SilentlyContinue
            if (-not $appRunning) { $stopped = $true; break }
        }
        if (-not $stopped) {
            write_log_message -message "Failed to stop WatchGuard SSL VPN Client after $maxAttempts attempts. Aborting before download." -level "Error" -writeToConsole $true
            Exit 1
        }
        write_log_message -message "WatchGuard SSL VPN Client stopped successfully." -level "Success" -writeToConsole $true
    } else {
        write_log_message -message "WatchGuard SSL VPN Client not running; no stop required." -level "Info" -writeToConsole $true
    }

    # Disable TAP adapter if active
    if ($NetAdapter -and $NetAdapter.Status -eq "Up") {
        write_log_message -message "TAP-Windows Adapter V9 is active. Disabling adapter before download." -level "Warning" -writeToConsole $true
        Disable-NetAdapter -Name $NetAdapter.Name -Confirm:$false -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 5
    } else {
        write_log_message -message "TAP-Windows Adapter V9 not present or already down; no adapter action required." -level "Info" -writeToConsole $true
    }

    $preppedForInstall = $true
}

# download installer
$wgDownloadResult = download_file -Uri $Uri -filePath "$env:TEMP\wg_sslvpn" -MaxTries 3
if (-not $wgDownloadResult.success) {
    write_log_message -message "Failed to download WG installer. Aborting." -level "Error" -writeToConsole $true
    exit 1
}

try { $downloadVersion = (Get-ItemProperty -Path $wgDownloadResult.fullPath).VersionInfo.ProductVersion } catch { $downloadVersion = $null }

# Determine whether installer should run, but continue with webview copy regardless
$installRequired = $true
if ($wgVpnVersion -and $downloadVersion) {
    try {
        if ([version]$wgVpnVersion -ge [version]$downloadVersion) {
            write_log_message -message "Installed WG SSL VPN Client version $wgVpnVersion is up to date." -level "Info" -writeToConsole $true
            $installRequired = $false
        } else {
            write_log_message -message "A newer version of WG SSL VPN Client is available. Proceeding with update." -level "Info" -writeToConsole $true
            $installRequired = $true
        }
    } catch {
        write_log_message -message "Version comparison failed: $($_.Exception.Message) — proceeding with install." -level "Warning" -writeToConsole $true
        $installRequired = $true
    }
} else {
    write_log_message -message "Proceeding with install/update (version info unavailable)." -level "Info" -writeToConsole $true
    $installRequired = $true
}

# installer handling (only if needed)
$appRunning = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "wgsslvpnc" }
$NetAdapter = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.InterfaceDescription -eq "TAP-Windows Adapter V9" }
$arguments = '/silent /verysilent'
$process = $null

if ($installRequired) {
    if ($NetAdapter -and $NetAdapter.Status -eq "Up") {
        if ($forceInstallFlag) {
            write_log_message -message "TAP-Windows Adapter V9 is currently active. Disabling the network adapter before installation (forced)." -level "Warning" -writeToConsole $true
            Disable-NetAdapter -Name $NetAdapter.Name -Confirm:$false -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 5
        } else {
            write_log_message -message "TAP-Windows Adapter V9 is active but force install not requested; skipping adapter disable." -level "Info" -writeToConsole $true
        }
    } else {
        write_log_message -message "TAP-Windows Adapter V9 is not active or not present. No action needed." -level "Info" -writeToConsole $true
    }

    if ($null -eq $appRunning) {
        write_log_message -message "WatchGuard SSL VPN Client is not running. Proceeding with installation." -level "Info" -writeToConsole $true
        $process = Start-Process -FilePath $wgDownloadResult.fullPath -ArgumentList $arguments -PassThru -Wait -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 60
    } else {
        write_log_message -message "WatchGuard SSL VPN Client is currently running." -level "Warning" -writeToConsole $true
        if ($forceInstallFlag) {
                write_log_message -message "Stopping the application for installation (forced)." -level "Warning" -writeToConsole $true
                # Attempt to stop the running process up to 3 times before failing.
                $stopAttempt = 0
                $maxAttempts = 3
                $stopped = $false
                while ($stopAttempt -lt $maxAttempts) {
                    $stopAttempt++
                    if ($stopAttempt -eq 1) {
                        # First attempt: graceful stop
                        try { Stop-Process -Id $appRunning.Id -ErrorAction SilentlyContinue } catch {}
                    } else {
                        # Subsequent attempts: force stop
                        try { Stop-Process -Id $appRunning.Id -Force -ErrorAction SilentlyContinue } catch {}
                    }
                    Start-Sleep -Seconds 5
                    $appRunning = Get-Process -Id $appRunning.Id -ErrorAction SilentlyContinue
                    if (-not $appRunning) { $stopped = $true; break }
                }
                if (-not $stopped) {
                    write_log_message -message "Failed to stop WatchGuard SSL VPN Client after $maxAttempts attempts. Aborting installation." -level "Error" -writeToConsole $true
                    $installRequired = $false
                } else {
                    write_log_message -message "WatchGuard SSL VPN Client stopped successfully." -level "Success" -writeToConsole $true
                    Start-Sleep -Seconds 5
                    write_log_message -message "Installing WatchGuard SSL VPN Client." -level "Info" -writeToConsole $true
                    $process = Start-Process -FilePath $wgDownloadResult.fullPath -ArgumentList $arguments -PassThru -Wait -ErrorAction SilentlyContinue
                }
        } else {
            write_log_message -message "Not forcing application stop because force install not requested; skipping installation." -level "Warning" -writeToConsole $true
            $installRequired = $false
        }
    }
} else {
    write_log_message -message "Installation skipped (already up to date). Continuing with WebView per-user copy." -level "Info" -writeToConsole $true
}

if ($process -and $process.HasExited) {
    if ($process.ExitCode -eq 0) {
        write_log_message -message "WatchGuard SSL VPN Client installation process completed with exit code 0." -level "Success" -writeToConsole $true
    } else {
        write_log_message -message "WatchGuard SSL VPN Client installation process failed with exit code $($process.ExitCode)." -level "Error" -writeToConsole $true
    }
} else {
    if ($installRequired) {
        write_log_message -message "Installer process information not available." -level "Warning" -writeToConsole $true
    }
}

$appInstalled = Get-Item "C:\Program Files*\WatchGuard\WatchGuard Mobile VPN with SSL\wgsslvpnc.exe" -ErrorAction SilentlyContinue
if ($null -ne $appInstalled) {
    write_log_message -message "WatchGuard SSL VPN Client installed successfully." -level "Success" -writeToConsole $true
} else {
    if ($installRequired) {
        write_log_message -message "WatchGuard SSL VPN Client installation may have failed (executable not found)." -level "Error" -writeToConsole $true
    }
}
