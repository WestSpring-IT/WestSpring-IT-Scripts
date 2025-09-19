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

.FUNCTION Write-Log
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
    [Parameter(Mandatory = $true)]
    [string]$installString = "",
    [string]$Uri = "https://wsprodfileuksouth.blob.core.windows.net/clients/qualys-agent-installers/QualysCloudAgent-Windows.exe"

)
$LogFile = "$env:TEMP\QualysAgentInstall.log"
$DirPath = "$env:TEMP"
$InstallerName = "QualysCloudAgent-Windows.exe"
$InstallerPath = "$DirPath\$InstallerName"
if ($installString -match 'CustomerId=\{([^\}]+)\}') {
    $customerID = $matches[1]
} else {
    Write-Log "CustomerId not found in installString" "ERROR"
}
if ($installString -match 'ActivationId=\{([^\}]+)\}') {
    $activationID = $matches[1]
} else {
    Write-Log "ActivationId not found in installString" "ERROR"
}
if ($installString -match 'WebServiceUri=([^\s]+)') {
    $webServiceUri = $matches[1]
} else {
    Write-Log "WebServiceUri not found in installString" "ERROR"
}
$windowsVersion = (Get-ItemPropertyValue -LiteralPath "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name 'DisplayVersion')

# Function Definitions
# The Write-Log function is used to log messages with a timestamp and severity level.
# Parameters:
# - Message: The message to log.
# - Level: The severity level of the log message (default is "INFO").
function Write-Log {
    param (
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] [$Level] $Message"
    Add-Content -Path $LogFile -Value "[$timestamp] [$Level] $Message"
}

# Temporarily bypass the execution policy for this process to ensure the script runs without being blocked.
# This change is limited to the current process and does not affect the system-wide policy.
# Note: Bypassing the execution policy can pose security risks as it allows the execution of potentially harmful scripts.
Write-Log "Bypassing execution policy for this process" "INFO"
Set-ExecutionPolicy Bypass -Scope Process -Force

# Download the Qualys Agent
$downloadSuccess = $false
try {
    Write-Log "Downloading the Qualys Agent from $Uri"
    Invoke-RestMethod -Uri $Uri -OutFile $InstallerPath
    $downloadSuccess = $true
}
catch {
    Write-Log "Failed to download the Qualys Agent: $($_.Exception.Message)" "ERROR"
    if ($_.Exception.Response) {
        Write-Log "Status Code: $($_.Exception.Response.StatusCode.value__)" "ERROR"
        Write-Log "Status Description: $($_.Exception.Response.StatusDescription)" "ERROR"
    }
    else {
        Write-Log "No Response object available in the exception." "ERROR"
    }
    Write-Log "Stack Trace: $($_.Exception.StackTrace)" "ERROR"
    Exit 1
}

If ($downloadSuccess -and (Test-Path $InstallerPath)) {
    Write-Log "The file, $InstallerName, successfully downloaded"
    $installString = "CustomerId={$($customerID)} ActivationId={$($activationID)} WebServiceUri=$($webServiceUri)"    # Install Qualys Agent
    Write-Log "CustomerID: $($customerID)"
    Write-Log "ActivationID: $($activationID)"
    Write-Log "WebServiceUri: $($webServiceUri)"
    Write-Log "Windows Version: $($windowsVersion)"
    Write-Log "Installing the Qualys Agent from $InstallerPath"
    $installSuccess = $false
    try {
        Write-Log "Invoking the following command: cmd.exe /c $($InstallerPath) $($installString)" "INFO" 
        Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$InstallerPath $installString`"" -Wait -NoNewWindow -ErrorAction Stop
        Start-Sleep -Seconds 5
        $msiProduct = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" | Where-Object { $_.DisplayName -eq 'Qualys Cloud Security Agent' }
        if ($msiProduct) {
            $installSuccess = $true
            Write-Log "Qualys Agent ($($msiProduct.Version)) installation completed"
            Start-Sleep -Seconds 5
            Write-Log "Starting the initial scan"
            if ((Test-Path -LiteralPath "HKLM:\SOFTWARE\Qualys\QualysAgent\ScanOnDemand\Vulnerability") -ne $true) {  
                New-Item "HKLM:\SOFTWARE\Qualys\QualysAgent\ScanOnDemand\Vulnerability" -force -ea SilentlyContinue - | Out-Null
            };
            New-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Qualys\QualysAgent\ScanOnDemand\Vulnerability' -Name 'ScanOnDemand' -Value 1 -PropertyType DWord -Force -ea SilentlyContinue | Out-Null;
        } 
        
    }
    catch {
        Write-Log "Failed to install the Qualys Agent: $($_.Exception.Message)" "ERROR"
        Write-Log "Stack Trace: $($_.Exception.StackTrace)" "ERROR"
        Exit 1
    }
    
    Start-Sleep -Seconds 5
    
    # Clean up
    try {
        Remove-Item -Path $InstallerPath -ErrorAction Stop
        If (!(Test-Path $InstallerPath)) {
            Write-Log "Installation files successfully removed"
        }
    }
    catch {
        Write-Log "Error occurred while removing installation files: $($_.Exception.Message)" "ERROR"
        Write-Log "Stack Trace: $($_.Exception.StackTrace)" "ERROR"
        Write-Log "Please remove the installation files manually" "WARNING"
    }
}
else {
    Write-Log "The file download failed, please try again" "ERROR"
    Exit 1
}
