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

# Check/install/update 7-Zip (x64) — uses helper 7_zip.ps1 if present for download/logging

# Dot-source helper if available (provides download_file and write_log_message)
$helperPath = Join-Path -Path $PSScriptRoot -ChildPath '7_zip.ps1'
if (Test-Path $helperPath) {
    . $helperPath
}


function get_installed_7zip_version {
    # Check common executable locations first
    $candidates = @(
        Join-Path $env:ProgramFiles '7-Zip\7z.exe',
        Join-Path $env:ProgramFiles(x86) '7-Zip\7z.exe'
    ) | Where-Object { $_ -and (Test-Path $_) }

    foreach ($exe in $candidates) {
        try {
            $ver = (Get-Item $exe).VersionInfo.ProductVersion
            if ($ver) { return @{ Path=$exe; Version=$ver } }
        } catch {}
    }

    # Fall back to registry uninstall entries (64-bit and 32-bit views)
    $regPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    foreach ($rp in $regPaths) {
        try {
            $items = Get-ChildItem -Path $rp -ErrorAction SilentlyContinue
            foreach ($it in $items) {
                try {
                    $props = Get-ItemProperty -Path $it.PSPath -ErrorAction SilentlyContinue
                    if ($props.DisplayName -and ($props.DisplayName -like '7-Zip*')) {
                        return @{ Path = $null; Version = $props.DisplayVersion }
                    }
                } catch {}
            }
        } catch {}
    }

    return $null
}

function get_latest_7zip_info {
    param()
    $url = 'https://www.7-zip.org/'
    try {
        $r = Invoke-WebRequest -Uri $url -UseBasicParsing -ErrorAction Stop
        $html = $r.Content

        # Try to find a version like "Download 7-Zip 22.01" or similar
        if ($html -match 'Download\s+7-Zip\s+([0-9]+\.[0-9]+)') {
            $ver = $matches[1]
        } else {
            # fallback: find any 7z{digits}-x64.exe anchor
            $ver = $null
        }

        # Prefer extracting a direct installer href for x64
        $href = ($r.Links | Where-Object { $_.href -match '7z\d+-x64\.exe$' } | Select-Object -First 1).href
        if (-not $href) {
            # Try scanning raw html for a/7z...-x64.exe
            if ($html -match 'href="(?<h>.*?7z(?<digits>\d+)-x64\.exe)"') {
                $href = $matches['h']
            }
        }

        if ($href) {
            # normalize relative -> absolute
            if ($href -notmatch '^https?://') {
                $installerUrl = [uri]::new($url, $href).AbsoluteUri
            } else {
                $installerUrl = $href
            }
            # Derive version from filename if not found earlier
            if (-not $ver) {
                if ($installerUrl -match '7z(?<digits>\d+)-x64\.exe') {
                    $digits = $matches['digits']
                    # reconstruct version like 2201 -> 22.01
                    if ($digits.Length -ge 3) {
                        $major = $digits.Substring(0, $digits.Length - 2)
                        $minor = $digits.Substring($digits.Length - 2)
                        $ver = "$major.$minor"
                    } else {
                        $ver = $digits
                    }
                }
            }

            return [PSCustomObject]@{ Version = $ver; Url = $installerUrl }
        }

        write_log_message "Unable to locate 7-Zip installer link on $url" "Warning"
        return $null
    } catch {
        write_log_message "Failed to query 7-Zip website: $_" "Error"
        return $null
    }
}

function comapre_version_strings {
    param($a, $b)
    try {
        # normalize like "22.01" => "22.1" so [version] comparison works
        $na = ($a -replace '\.0+([0-9])','$1') -replace '\.(\d+)$',{'0'.$matches[1]} # best-effort
        $nb = ($b -replace '\.0+([0-9])','$1') -replace '\.(\d+)$',{'0'.$matches[1]}
        return ([version]$na).CompareTo([version]$nb)
    } catch {
        # fallback string compare
        return $a.CompareTo($b)
    }
}

write_log_message "Checking installed 7-Zip version..." "Info"
$installed = get_installed_7zip_version
if ($installed) {
    write_log_message ("Detected installed 7-Zip version: {0} (path: {1})" -f ($installed.Version -or '<unknown>'), ($installed.Path -or '<registry>')) "Info"
} else {
    write_log_message "7-Zip not detected on this system." "Info"
}

write_log_message "Querying latest 7-Zip information from official site..." "Info"
$latest = get_latest_7zip_info
if (-not $latest) {
    write_log_message "Cannot determine latest 7-Zip version. Aborting." "Error"
    exit 2
}
write_log_message ("Latest available 7-Zip version: {0}" -f $latest.Version) "Info"

$needInstall = $false
if (-not $installed) { $needInstall = $true }
else {
    try {
        $cmp = comapre_version_strings $installed.Version $latest.Version
        if ($cmp -lt 0) { $needInstall = $true }
    } catch {
        $needInstall = $true
    }
}

if (-not $needInstall) {
    write_log_message "Installed 7-Zip is up to date. No action required." "Success"
    exit 0
}

# Download installer
$tempDir = Join-Path $env:TEMP '7zip_update'
if (-not (Test-Path $tempDir)) { New-Item -Path $tempDir -ItemType Directory | Out-Null }
$installerName = Split-Path -Path $latest.Url -Leaf
$installerPath = Join-Path $tempDir $installerName

write_log_message ("Downloading {0} -> {1}" -f $latest.Url, $installerPath) "Info"
$dlResult = $null
if (Get-Command -Name download_file -ErrorAction SilentlyContinue) {
    $dlResult = download_file -Uri $latest.Url -filePath $tempDir -MaxTries 3
    if ($dlResult -and $dlResult.success) { $installerPath = $dlResult.fullPath } else { $dlResult = $null }
}

if (-not (Test-Path $installerPath)) {
    write_log_message "Installer not present after download. Aborting." "Error"
    exit 4
}

write_log_message "Running installer (silent) ..." "Info"
try {
    $proc = Start-Process -FilePath $installerPath -ArgumentList '/S' -Wait -PassThru -NoNewWindow -ErrorAction Stop
    $exit = $proc.ExitCode
    write_log_message ("Installer exited with code {0}" -f $exit) "Info"
} catch {
    write_log_message "Failed to run installer: $_" "Error"
    exit 5
}

# Verify updated version
Start-Sleep -Seconds 5
$installedAfter = get_installed_7zip_version
if ($installedAfter) {
    write_log_message ("Post-install detected 7-Zip version: {0}" -f $installedAfter.Version) "Info"
    try {
        if ((comapre_version_strings $installedAfter.Version $latest.Version) -ge 0) {
            write_log_message "7-Zip successfully updated to latest version." "Success"
            exit 0
        } else {
            write_log_message "7-Zip installed version does not match latest version. Manual check recommended." "Warning"
            exit 6
        }
    } catch {
        write_log_message "Could not compare post-install version. Installed: $($installedAfter.Version) Latest: $($latest.Version)" "Warning"
        exit 7
    }
} else {
    write_log_message "7-Zip not detected after install. Install may have failed." "Error"
    exit 8
}