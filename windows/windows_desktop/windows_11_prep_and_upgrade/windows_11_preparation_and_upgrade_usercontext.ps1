function write_log_message {
    param(
        [Parameter(Mandatory = $true)]
        [string]$message,
        [Parameter(Mandatory = $false)]
        [ValidateSet("Info", "Warning", "Error", "Success")]
        [string]$level = "Info",
        [Parameter(Mandatory = $false)]
        [Boolean]$writeToConsole = $true
    )
    $Global:scriptName = $null
    $Global:scriptName = "windows_11_preparation_and_upgrade_usercontext" #$(Split-Path $MyInvocation.ScriptName -Leaf).TrimEnd(".ps1")
    $timestamp = Get-Date -Format "yyyy-MM-dd_THH:mm:ss"
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
    if (-not $Global:logFilePath) {
        $Global:logFilePath = $null
        $Global:logFilePath = "$env:TEMP\$(get-date -f "yyyy-MM-dd")_$($Global:scriptName).log"
    }
    Add-Content -Path $Global:logFilePath -Value $logEntry
}
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
        [string]$fileName,
        [string]$filePath = "$env:TEMP",
        [int]$MaxTries = 3,
        [string]$ProgressPreference = "SilentlyContinue"
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
function get_current_windows_version {
    $info = Get-ComputerInfo    
        $result = [PSCustomObject]@{
            osName = $info.OsName
            osVersion = $info.OsVersion
            osBuildNumber = $info.OsBuildNumber
        }
        return $result
}

$osInfo = get_current_windows_version

write_log_message "Current OS: $($osInfo.osName) Version: $($osInfo.osVersion) Build: $($osInfo.osBuildNumber)"
if ([version]$osInfo.osVersion -gt [version]"10.0.20000") {
    write_log_message "This device is already running Windows 11. No upgrade necessary." -level "Warning"
    exit 0
}
else {
    write_log_message "This device is running $($osInfo.osName). Proceeding with Windows 11 upgrade preparation."
    if (Get-process | Where-Object {$_.Name -like "Windows10*" -or $_.Name -like "Windows11*"}) {
        write_log_message "Another installation or upgrade process is currently running." -level "Warning"
        break
    }
    # Download the Windows 11 Installation Assistant
    $downloadUrl = "https://go.microsoft.com/fwlink/?linkid=2171764"
    $downloadResult = download_file -Uri $downloadUrl -filePath "C:\IT\Windows11" -MaxTries 3
    $arguments = @("/ShowProgressInTaskBarIcon", "/SkipEULA", "/Auto Upgrade")
    $username = "$($env:COMPUTERNAME)\Windows11Upgrade"
    $password = "$((Get-WmiObject -class win32_bios).SerialNumber)_W1nd0w5!!"
    $credentials = New-Object System.Management.Automation.PSCredential -ArgumentList @($username, (ConvertTo-SecureString -String $password -AsPlainText -Force))
    if ($downloadResult.success -eq $true) {
        try {
           #Start-Process powershell.exe -Credential $credentials -WindowStyle Hidden -ArgumentList "$($downloadResult.fullPath) $($arguments -join " ")" -ErrorAction Stop
           #Start-Process powershell.exe -Credential $credentials -ArgumentList "Start-Process -FilePath $($downloadResult.fullPath) -ArgumentList $arguments -Verb runAs"
           #Start-Process $downloadResult.fullPath -ArgumentList $arguments -WindowStyle Hidden #-Credential $credentials
        }
        catch {
            write_log_message "Error starting upgrade process: $($_.Exception.Message)" -level "Error"
            break
        }
    }
    else {
        write_log_message "Failed to download Windows 11 Installation Assistant." -level "Error"
        break
    }
    write_log_message "Upgrade process initiated. Please monitor the system for completion." -level "Success"
    write_log_message "log file located at $Global:logFilePath"
}


