<#
.SYNOPSIS
This script automates the download, installation, and initial configuration of the Qualys Cloud Agent on a Windows system.

.DESCRIPTION
The script performs the following tasks:
1. Downloads the Qualys Cloud Agent installer from a specified URI.
2. Installs the Qualys Cloud Agent using provided Customer ID, Activation ID, and Web Service URI.
3. Logs all actions and errors to a log file for auditing and troubleshooting purposes.
4. Configures the agent to perform an initial vulnerability scan.
5. Cleans up installation files after successful installation.

.PARAMETER LogFile
Specifies the path to the log file where all actions and errors will be recorded.

.PARAMETER Uri
The URI from which the Qualys Cloud Agent installer will be downloaded.

.PARAMETER DirPath
The directory path where the installer will be saved temporarily.

.PARAMETER InstallerName
The name of the Qualys Cloud Agent installer file.

.PARAMETER InstallerPath
The full path to the installer file, combining DirPath and InstallerName.

.PARAMETER installString
The command-line arguments used to install the Qualys Cloud Agent, including Customer ID, Activation ID, and Web Service URI.

.PARAMETER customerID
The Customer ID extracted from the installString.

.PARAMETER activationID
The Activation ID extracted from the installString.

.PARAMETER webServiceUri
The Web Service URI extracted from the installString.

.PARAMETER windowsVersion
The version of the Windows operating system on which the script is being executed.

.FUNCTION write_log_message
Logs messages with a timestamp and severity level to both the console and the log file.

.NOTES
- The script temporarily bypasses the PowerShell execution policy to ensure it runs without being blocked.
- It verifies the successful download of the installer before proceeding with the installation.
- If the installation fails, detailed error messages and stack traces are logged for troubleshooting.
- After installation, the script initiates an initial vulnerability scan by modifying the registry.
- Installation files are removed after successful installation to clean up the system.

.EXAMPLE
# Run the script to install the Qualys Cloud Agent
.\QualysAgent.ps1

# Ensure the script is executed with administrative privileges to allow registry modifications and software installation.
#>

Param(
    [Parameter(Mandatory = $false)]
    [string]$installString = "{[InstallString]}",
    [Parameter(Mandatory = $false)]
    [ValidateSet('yes','y','no','n')]
    [string]$forceInstall = "{[ForceInstall]}",
    [Parameter(Mandatory = $false)]
    [string]$Uri = "https://wsprodfileuksouth.blob.core.windows.net/clients/qualys-agent-installers/QualysCloudAgent-Windows.exe"
)
#$LogFile = "$env:TEMP\QualysAgentInstall.log"
$DirPath = "$env:TEMP"
$InstallerName = "QualysCloudAgent-Windows.exe"
$InstallerPath = "$DirPath\$InstallerName"
#$installSuccess = $false
if ($installString -match 'CustomerId=\{([^\}]+)\}') {
    $customerID = $matches[1]
} else {
    write_log_message "CustomerId not found in installString" "ERROR"
    Exit 1
}
if ($installString -match 'ActivationId=\{([^\}]+)\}') {
    $activationID = $matches[1]
} else {
    write_log_message "ActivationId not found in installString" "ERROR"
    Exit 2
}
if ($installString -match 'WebServiceUri=([^\s]+)') {
    $webServiceUri = $matches[1]
} else {
    write_log_message "WebServiceUri not found in installString" "ERROR"
    Exit 3
}


## Function Definitions ##
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
            Invoke-WebRequest -UseBasicParsing -Uri $Uri -OutFile $fullPath -ErrorAction Stop
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
## /Function Definitions ##

# Normalize forceInstall parameter into boolean flag
$forceInstallFlag = $false
if ($null -ne $forceInstall) {
    try {
        if ($forceInstall -is [string]) {
            if ($forceInstall.ToLower() -in @('yes','y')) { $forceInstallFlag = $true }
        } elseif ($forceInstall -is [bool]) {
            $forceInstallFlag = [bool]$forceInstall
        }
    } catch {
        $forceInstallFlag = $false
    }
}

$msiProduct = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" | Where-Object { $_.DisplayName -eq 'Qualys Cloud Security Agent' }
$agentInfo = Get-ItemProperty -Path "HKLM:\SOFTWARE\Qualys" -ErrorAction SilentlyContinue

if ($msiProduct) {
    write_log_message "Qualys Agent is already installed. Version: $($msiProduct.Version)" "INFO" -writeToConsole $true
    write_log_message "Configured CustomerID: $($agentInfo.CustomerID)" "INFO" -writeToConsole $true
    write_log_message "Configured ActivationID: $($agentInfo.ActivationID)" "INFO" -writeToConsole $true

    $installedMatches = ($agentInfo.customerID -eq $customerID) -and ($agentInfo.activationID -eq $activationID)
    if ($installedMatches) {
        write_log_message "The installed Qualys Agent matches the provided CustomerID and ActivationID." "INFO" -writeToConsole $true
        if (-not $forceInstallFlag) {
            write_log_message "No action requested. Exiting." "INFO" -writeToConsole $true
            Exit 0
        } else {
            write_log_message "Force install requested: will uninstall existing agent and proceed to install." "WARNING" -writeToConsole $true
        }
    } else {
        write_log_message "The installed Qualys Agent does not match the provided CustomerID and/or ActivationID." "WARNING" -writeToConsole $true
        write_log_message " -- Configured customerID: $($agentInfo.customerID)" "WARNING" -writeToConsole $true
        write_log_message " -- Configured activationID: $($agentInfo.activationID)" "WARNING" -writeToConsole $true
        if (-not $forceInstallFlag) {
            write_log_message "No force requested; leaving existing agent in place and exiting." "INFO" -writeToConsole $true
            write_log_message "If you want to replace the agent, re-run with -forceInstall yes" "INFO" -writeToConsole $true
            Exit 0
        } else {
            write_log_message "Force install requested: will uninstall existing agent and proceed to install." "WARNING" -writeToConsole $true
        }
    }

    # Uninstall existing agent before proceeding
    try {
        $productCode = $msiProduct.PSChildName
        if ($productCode) {
            write_log_message "Uninstalling existing Qualys Agent (ProductCode: $productCode)" "INFO" -writeToConsole $true
            $uninstallArgs = "/x$productCode /qn /norestart"
            $uninstall = Start-Process -FilePath "msiexec.exe" -ArgumentList $uninstallArgs -Wait -PassThru -ErrorAction Stop
            if ($uninstall.ExitCode -eq 0) {
                write_log_message "Uninstall completed successfully." "SUCCESS" -writeToConsole $true
            } else {
                write_log_message "Uninstall returned exit code $($uninstall.ExitCode). Aborting." "ERROR" -writeToConsole $true
                Exit 1
            }
        } else {
            write_log_message "Could not determine product code for uninstall. Aborting." "ERROR" -writeToConsole $true
            Exit 1
        }
    }
    catch {
        write_log_message "Failed to uninstall existing Qualys Agent: $($_.Exception.Message)" "ERROR" -writeToConsole $true
        Exit 1
    }

    # Refresh state
    Start-Sleep -Seconds 5
    $msiProduct = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" | Where-Object { $_.DisplayName -eq 'Qualys Cloud Security Agent' }
}

# Temporarily bypass the execution policy for this process to ensure the script runs without being blocked.
# This change is limited to the current process and does not affect the system-wide policy.
# Note: Bypassing the execution policy can pose security risks as it allows the execution of potentially harmful scripts.
write_log_message "Bypassing execution policy for this process" "INFO" -writeToConsole $true
Set-ExecutionPolicy Bypass -Scope Process -Force

# Download the Qualys Agent
write_log_message "Downloading the Qualys Agent from $Uri" -level "INFO" -writeToConsole $true
$qualysDownload = download_file -Uri $Uri -MaxTries 3 -ProgressPreference "SilentlyContinue"


If ($qualysDownload.success) {
    write_log_message "The file, $($qualysDownload.fileName), successfully downloaded" -level "SUCCESS" -writeToConsole $true
    $installString = "CustomerId={$($customerID)} ActivationId={$($activationID)} WebServiceUri=$($webServiceUri)"    # Install Qualys Agent
    write_log_message "CustomerID: $($customerID)" -level "INFO" -writeToConsole $true
    write_log_message "ActivationID: $($activationID)" -level "INFO" -writeToConsole $true
    write_log_message "WebServiceUri: $($webServiceUri)" -level "INFO" -writeToConsole $true
    write_log_message "Windows Version: $($windowsVersion)" -level "INFO" -writeToConsole $true
    write_log_message "Installing the Qualys Agent from $($qualysDownload.fullPath)" -level "INFO" -writeToConsole $true
    try {
        write_log_message "Invoking the following command: cmd.exe /c $($InstallerPath) $($installString)" "INFO" -writeToConsole $true
        $process = Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$($qualysDownload.fullPath) $installString`"" -Wait -NoNewWindow -ErrorAction Stop
        while ($process.HasExited -ne $true) {
            Start-Sleep -Seconds 1
        } 
        $msiProduct = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" | Where-Object { $_.DisplayName -eq 'Qualys Cloud Security Agent' }
        if ($msiProduct -and $process.ExitCode -eq 0) {
            #$installSuccess = $true
            write_log_message "Qualys Agent ($($msiProduct.Version)) installation completed" -level "SUCCESS" -writeToConsole $true
            Start-Sleep -Seconds 5
            write_log_message "Starting the initial scan" -level "INFO" -writeToConsole $true
            if ((Test-Path -LiteralPath "HKLM:\SOFTWARE\Qualys\QualysAgent\ScanOnDemand\Vulnerability") -ne $true) {  
                New-Item "HKLM:\SOFTWARE\Qualys\QualysAgent\ScanOnDemand\Vulnerability" -force -ea SilentlyContinue - | Out-Null
            };
            New-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Qualys\QualysAgent\ScanOnDemand\Vulnerability' -Name 'ScanOnDemand' -Value 1 -PropertyType DWord -Force -ea SilentlyContinue | Out-Null;
        } 
        
    }
    catch {
        write_log_message "Failed to install the Qualys Agent, ExitCode $($process.ExitCode): $($_.Exception.Message)" -level "ERROR" -writeToConsole $true
        write_log_message "Stack Trace: $($_.Exception.StackTrace)" -level "ERROR" -writeToConsole $true
        Exit 1
    }
    
    Start-Sleep -Seconds 5
    
    # Clean up
    try {
        Remove-Item -Path $InstallerPath -ErrorAction Stop
        If (!(Test-Path $InstallerPath)) {
            write_log_message "Installation files successfully removed" -level "SUCCESS" -writeToConsole $true
            Exit $process.ExitCode
        }
    }
    catch {
        write_log_message "Error occurred while removing installation files: $($_.Exception.Message)" -level "ERROR" -writeToConsole $true
        write_log_message "Stack Trace: $($_.Exception.StackTrace)" -level "ERROR" -writeToConsole $true
        write_log_message "Please remove the installation files manually" -level "WARNING" -writeToConsole $true
    }
}
else {
    write_log_message "The file download failed, please try again" -level "ERROR" -writeToConsole $true
    Exit 1
}
