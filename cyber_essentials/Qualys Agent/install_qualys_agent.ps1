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
    [string]$installString = "QualysCloudAgent.exe CustomerId={4CED42B6-21B2-E6D5-80A3-BF1F6D2597F6} ActivationId={58082617-84FB-4800-A8B1-57DCD97FD709} WebServiceUri=https://qagpublic.qg1.apps.qualys.co.uk/CloudAgent/", #"{[InstallString]}",
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


# Function Definitions
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

$msiProduct = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" | Where-Object { $_.DisplayName -eq 'Qualys Cloud Security Agent' }
$agentInfo = Get-ItemProperty -Path "HKLM:\SOFTWARE\Qualys" -ErrorAction SilentlyContinue

if ($msiProduct) {
    write_log_message "Qualys Agent is already installed. Version: $($msiProduct.Version)" "INFO" -writeToConsole $true
    write_log_message "Configured CustomerID: $($agentInfo.CustomerID)" "INFO" -writeToConsole $true
    write_log_message "Configured ActivationID: $($agentInfo.ActivationID)" "INFO" -writeToConsole $true
    if (($agentInfo.customerID -eq $customerID) -and ($agentInfo.activationID -eq $activationID)) {
        write_log_message "The installed Qualys Agent matches the provided CustomerID and ActivationID. No action needed." "INFO" -writeToConsole $true
        Exit 0
    } else {
        write_log_message "The installed Qualys Agent does not match the provided CustomerID and/or ActivationID." "WARNING" -writeToConsole $true
        write_log_message " -- Configured customerID: $($agentInfo.customerID)" "WARNING" -writeToConsole $true
        write_log_message " -- Configured activationID: $($agentInfo.activationID)" "WARNING" -writeToConsole $true
    }
    write_log_message "If the endpoint needs to be re-registered, please uninstall the existing agent first." "INFO" -writeToConsole $true
    write_log_message "Uninstall command: msiexec /X$($msiProduct.PSChildName) /qn" "INFO" -writeToConsole $true
    Exit 0
}

# Temporarily bypass the execution policy for this process to ensure the script runs without being blocked.
# This change is limited to the current process and does not affect the system-wide policy.
# Note: Bypassing the execution policy can pose security risks as it allows the execution of potentially harmful scripts.
write_log_message "Bypassing execution policy for this process" "INFO" -writeToConsole $true
Set-ExecutionPolicy Bypass -Scope Process -Force

# Download the Qualys Agent
$downloadSuccess = $false
try {
    write_log_message "Downloading the Qualys Agent from $Uri" -level "INFO" -writeToConsole $true
    Invoke-RestMethod -Uri $Uri -OutFile $InstallerPath
    $downloadSuccess = $true
}
catch {
    write_log_message "Failed to download the Qualys Agent: $($_.Exception.Message)" "ERROR" -writeToConsole $true
    if ($_.Exception.Response) {
        write_log_message "Status Code: $($_.Exception.Response.StatusCode.value__)" "ERROR" -writeToConsole $true
        write_log_message "Status Description: $($_.Exception.Response.StatusDescription)" "ERROR" -writeToConsole $true
    }
    else {
        write_log_message "No Response object available in the exception." "ERROR" -writeToConsole $true
    }
    write_log_message "Stack Trace: $($_.Exception.StackTrace)" "ERROR" -writeToConsole $true
    Exit 1
}

If ($downloadSuccess -and (Test-Path $InstallerPath)) {
    write_log_message "The file, $InstallerName, successfully downloaded" -level "SUCCESS" -writeToConsole $true
    $installString = "CustomerId={$($customerID)} ActivationId={$($activationID)} WebServiceUri=$($webServiceUri)"    # Install Qualys Agent
    write_log_message "CustomerID: $($customerID)" -level "INFO" -writeToConsole $true
    write_log_message "ActivationID: $($activationID)" -level "INFO" -writeToConsole $true
    write_log_message "WebServiceUri: $($webServiceUri)" -level "INFO" -writeToConsole $true
    write_log_message "Windows Version: $($windowsVersion)" -level "INFO" -writeToConsole $true
    write_log_message "Installing the Qualys Agent from $InstallerPath" -level "INFO" -writeToConsole $true
    try {
        write_log_message "Invoking the following command: cmd.exe /c $($InstallerPath) $($installString)" "INFO" -writeToConsole $true
        Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$InstallerPath $installString`"" -Wait -NoNewWindow -ErrorAction Stop
        Start-Sleep -Seconds 5
        $msiProduct = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" | Where-Object { $_.DisplayName -eq 'Qualys Cloud Security Agent' }
        if ($msiProduct) {
            $installSuccess = $true
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
        write_log_message "Failed to install the Qualys Agent: $($_.Exception.Message)" -level "ERROR" -writeToConsole $true
        write_log_message "Stack Trace: $($_.Exception.StackTrace)" -level "ERROR" -writeToConsole $true
        Exit 1
    }
    
    Start-Sleep -Seconds 5
    
    # Clean up
    try {
        Remove-Item -Path $InstallerPath -ErrorAction Stop
        If (!(Test-Path $InstallerPath)) {
            write_log_message "Installation files successfully removed" -level "SUCCESS" -writeToConsole $true
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
