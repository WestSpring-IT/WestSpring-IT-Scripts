param (
    [string]$duoInstallerUrl = "https://dl.duosecurity.com/duo-win-login-latest.exe",
    [string]$duoIntegrationKey = "{[DUO_INTEGRATION_KEY]}",
    [string]$duoSecretKey = "{[DUO_SECRET_KEY]}",
    [string]$duoApiHost = "{[DUO_API_HOST]}",
    [bool]$duoAutoPush = $true,
    [bool]$duoFailOpen = $true,
    [bool]$duoEnableSmartCard = $true,
    [bool]$duoRdpOnly = $false
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
        [ValidateSet("Info", "Warning", "Error", "Success", "Debug", "Verbose")]
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
    $Script:logFilePath = "$env:TEMP\$(get-date -f "yyyy-MM-dd")_$($scriptName).log"
    Add-Content -Path $Script:logFilePath -Value $logEntry
}
function get_installed_duo_config {
    param(
        [Parameter(Mandatory=$true)]
        [string]$RegistryUninstallPath
    )

    # Helper to normalise registry flag values (1, '#1', 'true' => $true; 0/'#0'/'false' => $false)
    $parseFlag = {
        param($v)
        if ($null -eq $v) { return $null }
        $s = $v.ToString().Trim().ToLower()
        if ($s -eq '1' -or $s -eq '#1' -or $s -eq 'true') { return $true }
        if ($s -eq '0' -or $s -eq '#0' -or $s -eq 'false') { return $false }
        return $null
    }

    $config = [PSCustomObject]@{
        IntegrationKey = $null
        SecretKey = $null
        ApiHost = $null
        AutoPush = $null
        FailOpen = $null
        SmartCard = $null
        RDPOnly = $null
    }

    try {
        $props = Get-ItemProperty -Path $RegistryUninstallPath -ErrorAction SilentlyContinue
    } catch { $props = $null }

    if ($props) {
        foreach ($k in 'IKEY','IKey','Ikey','IntegrationKey') {
            if ($props.PSObject.Properties.Name -contains $k) { $config.IntegrationKey = $props.$k; break }
        }
        foreach ($k in 'SKEY','SKey','Skey','SecretKey') {
            if ($props.PSObject.Properties.Name -contains $k) { $config.SecretKey = $props.$k; break }
        }
        foreach ($k in 'HOST','Host','APIHOST','API_HOST','API Host','HostName') {
            if ($props.PSObject.Properties.Name -contains $k) { $config.ApiHost = $props.$k; break }
        }
        # flags
        foreach ($k in 'AUTOPUSH','AutoPush','AUTO_PUSH') { if ($props.PSObject.Properties.Name -contains $k) { $config.AutoPush = & $parseFlag $props.$k; break } }
        foreach ($k in 'FAILOPEN','FailOpen','FAIL_OPEN') { if ($props.PSObject.Properties.Name -contains $k) { $config.FailOpen = & $parseFlag $props.$k; break } }
        foreach ($k in 'SMARTCARD','SmartCard','SMART_CARD') { if ($props.PSObject.Properties.Name -contains $k) { $config.SmartCard = & $parseFlag $props.$k; break } }
        foreach ($k in 'RDPONLY','RDP_ONLY','RdpOnly') { if ($props.PSObject.Properties.Name -contains $k) { $config.RDPOnly = & $parseFlag $props.$k; break } }
    }

    # Also check known Duo config locations
    $possiblePaths = @(
        'HKLM:\SOFTWARE\Duo Security\DuoCredProv',
        'HKLM:\SOFTWARE\WOW6432Node\Duo Security\DuoCredProv'
    )
    foreach ($path in $possiblePaths) {
        if (Test-Path $path) {
            try {
                $p = Get-ItemProperty -Path $path -ErrorAction SilentlyContinue
                if ($p) {
                    if (-not $config.IntegrationKey) {
                        foreach ($k in 'IKEY','IKey','IntegrationKey') { if ($p.PSObject.Properties.Name -contains $k) { $config.IntegrationKey = $p.$k; break } }
                    }
                    if (-not $config.SecretKey) {
                        foreach ($k in 'SKEY','SKey','SecretKey') { if ($p.PSObject.Properties.Name -contains $k) { $config.SecretKey = $p.$k; break } }
                    }
                    if (-not $config.ApiHost) {
                        foreach ($k in 'HOST','Host','APIHOST','API_HOST') { if ($p.PSObject.Properties.Name -contains $k) { $config.ApiHost = $p.$k; break } }
                    }
                    if ($null -eq $config.AutoPush) { foreach ($k in 'AUTOPUSH','AutoPush','AUTO_PUSH') { if ($p.PSObject.Properties.Name -contains $k) { $config.AutoPush = & $parseFlag $p.$k; break } } }
                    if ($null -eq $config.FailOpen) { foreach ($k in 'FAILOPEN','FailOpen','FAIL_OPEN') { if ($p.PSObject.Properties.Name -contains $k) { $config.FailOpen = & $parseFlag $p.$k; break } } }
                    if ($null -eq $config.SmartCard) { foreach ($k in 'SMARTCARD','SmartCard','SMART_CARD') { if ($p.PSObject.Properties.Name -contains $k) { $config.SmartCard = & $parseFlag $p.$k; break } } }
                    if ($null -eq $config.RDPOnly) { foreach ($k in 'RDPONLY','RDP_ONLY','RdpOnly') { if ($p.PSObject.Properties.Name -contains $k) { $config.RDPOnly = & $parseFlag $p.$k; break } } }
                }
            } catch {}
        }
    }
    return $config
}

# Build configuration object from supplied parameters for clarity
$config = [PSCustomObject]@{
    IKey = $duoIntegrationKey
    SKey = $duoSecretKey
    Host = $duoApiHost
    AutoPush = [bool]$duoAutoPush
    FailOpen = [bool]$duoFailOpen
    EnableSmartCard = [bool]$duoEnableSmartCard
    RDPOnly = [bool]$duoRdpOnly
}

$maskedConfigIkey = if ($config.IKey) { $config.IKey.Substring(0,[Math]::Min(8,$config.IKey.Length)) + '...' } else { 'null' }
write_log_message -message "Using configuration: IKEY=$maskedConfigIkey, HOST=$($config.Host), AutoPush=$($config.AutoPush), FailOpen=$($config.FailOpen), SmartCard=$($config.EnableSmartCard), RDPOnly=$($config.RDPOnly)" -level "Info" -writeToConsole $true

#Check for existing DUO installation
$currentInstall = @{}
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
    $currentInstall.RegistryPath = $foundKey
    try {
        $currentInstall.InstalledVersion = (Get-ItemProperty -Path $foundKey -ErrorAction SilentlyContinue).DisplayVersion
    } catch { $currentInstall.InstalledVersion = $null }
    write_log_message -message "DUO Authentication for Windows Logon is currently installed. Registry key: $foundKey. Version: $($currentInstall.InstalledVersion)" -level "Info" -writeToConsole $true

    # Read installed configuration and compare with provided parameters
    $installedConfig = get_installed_duo_config -RegistryUninstallPath $foundKey
    $maskedIkey = if ($installedConfig.IntegrationKey) { $installedConfig.IntegrationKey.Substring(0, [Math]::Min(8, $installedConfig.IntegrationKey.Length)) + '...' } else { 'null' }
    $secretPresent = if ($installedConfig.SecretKey) { $true } else { $false }

    $installedAutoPush = if ($installedConfig.AutoPush -eq $true) { 1 } elseif ($installedConfig.AutoPush -eq $false) { 0 } else { 'null' }
    $installedFailOpen = if ($installedConfig.FailOpen -eq $true) { 1 } elseif ($installedConfig.FailOpen -eq $false) { 0 } else { 'null' }
    $installedSmartCard = if ($installedConfig.SmartCard -eq $true) { 1 } elseif ($installedConfig.SmartCard -eq $false) { 0 } else { 'null' }
    $installedRdpOnly = if ($installedConfig.RDPOnly -eq $true) { 1 } elseif ($installedConfig.RDPOnly -eq $false) { 0 } else { 'null' }

    write_log_message -message "Detected installed configuration: IKEY=$maskedIkey, HOST=$($installedConfig.ApiHost), SecretPresent=$secretPresent, AutoPush=$installedAutoPush, FailOpen=$installedFailOpen, SmartCard=$installedSmartCard, RDPOnly=$installedRdpOnly" -level "Debug" -writeToConsole $false

    $ikeyMatch = ($installedConfig.IntegrationKey -and ($installedConfig.IntegrationKey -eq $config.IKey))
    $skeyMatch = ($installedConfig.SecretKey -and ($installedConfig.SecretKey -eq $config.SKey))
    $hostMatch = ($installedConfig.ApiHost -and ($installedConfig.ApiHost -eq $config.Host))

    $autopushMatch = ($null -ne $installedConfig.AutoPush -and $installedConfig.AutoPush -eq $config.AutoPush)
    $failopenMatch = ($null -ne $installedConfig.FailOpen -and $installedConfig.FailOpen -eq $config.FailOpen)
    $smartcardMatch = ($null -ne $installedConfig.SmartCard -and $installedConfig.SmartCard -eq $config.EnableSmartCard)
    $rdponlyMatch = ($null -ne $installedConfig.RDPOnly -and $installedConfig.RDPOnly -eq $config.RDPOnly)

    if ($ikeyMatch -and $skeyMatch -and $hostMatch -and $autopushMatch -and $failopenMatch -and $smartcardMatch -and $rdponlyMatch) {
        write_log_message -message "Installed DUO configuration matches supplied parameters (including flags). No update required." -level "Info" -writeToConsole $true
        exit 0
    }

    # If config does not match, proceed to install latest
    write_log_message -message "Installed DUO configuration differs from supplied parameters (will perform install). Matches: IKEY=$ikeyMatch, SKEY=$skeyMatch, HOST=$hostMatch, AutoPush=$autopushMatch, FailOpen=$failopenMatch, SmartCard=$smartcardMatch, RDPOnly=$rdponlyMatch" -level "Info" -writeToConsole $true
} else {
    write_log_message -message "DUO Authentication for Windows Logon not found in registry (DisplayName search). Proceeding with fresh install." -level "Info" -writeToConsole $true
}

# Proceed to download and install DUO (this script targets fresh installs; it only skips when installed config matches)
#Download DUO installer
$downloadResult = download_file -Uri $duoInstallerUrl -filePath "$env:TEMP" -MaxTries 3 -ProgressPreference "SilentlyContinue"
if ($downloadResult.success) {
    write_log_message -message "DUO installer downloaded successfully: $($downloadResult.fullPath) (Size: $($downloadResult.fileSize) MB, Time: $($downloadResult.totalTime) seconds)" -level "Success" -writeToConsole $true
    write_log_message -message "Downloaded version: $((Get-ItemProperty -Path $downloadResult.fullPath).VersionInfo.ProductVersion)" -level "Info" -writeToConsole $true
}
else {
    write_log_message -message "Failed to download DUO installer after $($downloadResult.attempt) attempts." -level "Error" -writeToConsole $true
    exit 1
}

#Install DUO with silent parameters (built from $config)

$autopush = if ($config.AutoPush) { '#1' } else { '#0' }
$failopen = if ($config.FailOpen) { '#1' } else { '#0' }
$smartcard = if ($config.EnableSmartCard) { '#1' } else { '#0' }
$rdponly = if ($config.RDPOnly) { '#1' } else { '#0' }

$msiInner = "/qn IKEY=`"$($config.IKey)`" SKEY=`"$($config.SKey)`" HOST=`"$($config.Host)`" AUTOPUSH=`"$autopush`" FAILOPEN=`"$failopen`" SMARTCARD=`"$smartcard`" RDPONLY=`"$rdponly`""
$installArgs = "/S /V`"$msiInner`"" # /l*v! $($Script:logFilePath)
write_log_message -message "Starting DUO installation with arguments: $installArgs" -level "Info" -writeToConsole $true
$installProcess = Start-Process -FilePath $downloadResult.fullPath -ArgumentList $installArgs -Wait -PassThru

if ($installProcess.ExitCode -eq 0) {
    write_log_message -message $Script:logFilePath -level "Debug" -writeToConsole $false
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
        write_log_message -message "Logs may be found at: $($Script:logFilePath)" -level "Info" -writeToConsole $true

    }
    write_log_message -message "Logs may be found at: $($Script:logFilePath)" -level "Info" -writeToConsole $true
    exit 0
}
else {
    write_log_message -message "DUO installation failed with exit code: $($installProcess.ExitCode)" -level "Error" -writeToConsole $true
    write_log_message -message "Logs may be found at: $($Script:logFilePath)" -level "Info" -writeToConsole $true
    exit 1
}