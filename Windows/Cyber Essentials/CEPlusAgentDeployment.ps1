#       Copyright © WESTSPRING IT LIMITED
#       Author: Thomas Samuel
#       Support: thomassamuel@westspring-it.co.uk

# Function to log messages
function New-LogMessage {
    param(
        [Parameter()]
        [ValidateSet("SUCCESS", "INFO", "WARN", "ERROR")]
        [string]$Level = "INFO",

        [Parameter(Mandatory)]
        [string]$Message
    )

    # Checks if the logging folder exists
    if (-not (Test-Path -Path "C:\WestSpring IT\LogFiles")) {
        # Log path doesn't exist, creating now
        New-Item -Path "C:\WestSpring IT\LogFiles" -ItemType Directory -Force | Out-Null
    }

    # Get current date and time
    $LogDay = Get-Date -UFormat %d-%m-%Y
    $LogTime = Get-Date -UFormat %T

    # Create log entry
    $LogMessage = @{
        Path = "C:\WestSpring IT\LogFiles\$($LogDay)-$($ScriptName).log"
        Value = "$LogTime | $Level | $Message"
    }
    Add-Content @LogMessage

    # Output log message to console with appropriate color
    if ($Level -eq "ERROR") {
        Write-Host "$LogTime | $Level | $Message" -ForegroundColor Red
    } elseif ($Level -eq "SUCCESS") {
        Write-Host "$LogTime | $Level | $Message" -ForegroundColor Green
    } elseif ($Level -eq "WARN") {
        Write-Host "$LogTime | $Level | $Message" -ForegroundColor Yellow
    } else {
        Write-Host "$LogTime | $Level | $Message"
    }
}

# Add script name here for logging purposes (Atera and Intune often overwrite the script name)
$ScriptName = "CEPlusAgentDeployment"

# Function to check Temp directory exists
function Test-TempDirectory {
    if (-not (Test-Path -Path "C:\Temp")) {
        New-LogMessage -Level INFO -Message "Temp directory does not exist. Creating now."
        New-Item -Path "C:\Temp" -ItemType Directory -Force | Out-Null
        New-LogMessage -Level SUCCESS -Message "Temp directory created successfully."
    } else {
        New-LogMessage -Level INFO -Message "Temp directory already exists."
    }
}

# Function to check if relevant Microsoft Graph modules are installed and install if not
function Check-InstalledModules {
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    $InstalledModule = Get-InstalledModule -Name $Name -ErrorAction SilentlyContinue
    if (-not $InstalledModule) {
        # Module is not installed, attempt to install from PSGallery
        New-LogMessage -Level INFO -Message "Module $($Name) is not installed. Installing now."
        try {
            Install-Module -Name $Name -Scope CurrentUser -Force -ErrorAction Stop
            New-LogMessage -Level SUCCESS -Message "Module $($Name) installed successfully."
        } catch {
            # Failed to install module, log error and exit with code 1
            New-LogMessage -Level ERROR -Message "Failed to install module $($Name). Error: $_"
            exit 1
        }
    } else {
        # Module is already installed, continue
        New-LogMessage -Level INFO -Message "Module $($Name) is already installed."
    }
}

# Check if Microsoft Graph modules are installed and attempt to install if not
Check-InstalledModules -Name "Microsoft.Graph.Authentication"
Check-InstalledModules -Name "IntuneWin32App"

# Ingest install strings from CybaOps portal
$CybaAgentInstallString = Read-Host "Please enter the CybaAgent install command line string from the CybaOps portal"
$QualysAgentInstallString = Read-Host "Please enter the QualysCloudAgent install command line string from the CybaOps portal"

# Connects to Microsoft Graph
Connect-MgGraph -Scopes "DeviceManagementApps.ReadWrite.All" -NoWelcome -ErrorAction Stop
$Organization = Get-MgOrganization
$Context = Get-MgContext
Connect-MSIntuneGraph -TenantID $Organization.Id -ClientId e09c9d6c-af10-4113-a1c9-f6edb76cd0e5 -ErrorAction Stop | Out-Null
New-LogMessage -Level INFO -Message "Connected to tenant $($Organization.DisplayName) as $($Context.Account)"

# Checks if Temp directory exists and creates it if not
Test-TempDirectory

# Agent installer URLs
$CybaAgentInstaller = "https://wsprodfileuksouth.blob.core.windows.net/clients/cyber_essentials/intunewin/CybaAgent.intunewin"
$QualysCloudAgentInstaller = "https://wsprodfileuksouth.blob.core.windows.net/clients/cyber_essentials/intunewin/QualysCloudAgent.intunewin"

# Attempt to download .intunewin files to Temp directory
try {
    # Attempt to download CybaAgent installer
    New-LogMessage -Level INFO -Message "Attempting to download CybaAgent installer."
    Invoke-WebRequest -Uri $CybaAgentInstaller -OutFile "C:\Temp\CybaAgent.intunewin" -UseBasicParsing
    New-LogMessage -Level SUCCESS -Message "CybaAgent installer downloaded successfully."

    # Attempt to download QualysCloudAgent installer 
    New-LogMessage -Level INFO -Message "Attempting to download QualysCloudAgent installer."
    Invoke-WebRequest -Uri $QualysCloudAgentInstaller -OutFile "C:\Temp\QualysCloudAgent.intunewin" -UseBasicParsing
    New-LogMessage -Level SUCCESS -Message "QualysCloudAgent installer downloaded successfully."
} catch {
    # Download failed, log error and exit with code 1
    New-LogMessage -Level ERROR -Message "Failed to download one or more installers. Error: $_"
    exit 1
}

# Attempt to add CybaAgent to Intune
$LocalCybaAgentInstallerPath = "C:\Temp\CybaAgent.intunewin"
try {
    New-LogMessage -Level INFO -Message "Attempting to add CybaAgent to Intune."
    # Set system requirements for the app
    $RequirementRule = New-IntuneWin32AppRequirementRule -Architecture "x64x86" -MinimumSupportedWindowsRelease "W11_21H2"

    # Set detection rule for the app
    $DetectionRule = New-IntuneWin32AppDetectionRuleFile -Path "C:\Program Files\CybaVerse" -FileOrFolder "CybaAgentd.exe" -DetectionType "exists" -Existence

    # Add the app to Intune
    $Win32App = Add-IntuneWin32App -FilePath $LocalCybaAgentInstallerPath -DisplayName "CybaAgent" -Description "CybaAgent" -Publisher "CybaVerse" -InstallExperience "system" -RestartBehavior "suppress" -DetectionRule $DetectionRule -RequirementRule $RequirementRule -InstallCommandLine $CybaAgentInstallString -UninstallCommandLine "CybaAgent.exe -u"
    New-LogMessage -Level SUCCESS -Message "CybaAgent added to Intune successfully."

    # Add assignment to the app for All Devices with Required install intent
    Add-IntuneWin32AppAssignmentAllDevices -ID $Win32App.id -Intent "required" -Notification "hideAll" | Out-Null
} catch {
    # Failed to add CybaAgent to Intune, log error and exit with code 1
    New-LogMessage -Level ERROR -Message "Failed to add CybaAgent to Intune. Error: $_"
    exit 1
}

# Attempt to add QualysCloudAgent to Intune
$LocalQualysCloudAgentInstallerPath = "C:\Temp\QualysCloudAgent.intunewin"
try {
    New-LogMessage -Level INFO -Message "Attempting to add QualysCloudAgent to Intune."
    # Set system requirements for the app
    $RequirementRule = New-IntuneWin32AppRequirementRule -Architecture "x64x86" -MinimumSupportedWindowsRelease "W11_21H2"

    # Set detection rule for the app
    $DetectionRule = New-IntuneWin32AppDetectionRuleFile -Path "C:\Program Files\Qualys\QualysAgent" -FileOrFolder "QualysAgent.exe" -DetectionType "exists" -Existence

    # Add the app to Intune
    $Win32App = Add-IntuneWin32App -FilePath $LocalQualysCloudAgentInstallerPath -DisplayName "Qualys Cloud Security Agent" -Description "Qualys Cloud Security Agent" -AppVersion "6.3.0.81" -InformationURL "https://www.qualys.com/" -PrivacyURL "https://www.qualys.com/company/privacy#your-ability-to-access-or-delete-personal-information" -Publisher "Qualys, Inc." -InstallExperience "system" -RestartBehavior "suppress" -DetectionRule $DetectionRule -RequirementRule $RequirementRule -InstallCommandLine $QualysAgentInstallString -UninstallCommandLine "`"C:\Program Files\Qualys\QualysAgent\Uninstall.exe`" Uninstall=True Force=True"
    New-LogMessage -Level SUCCESS -Message "QualysCloudAgent added to Intune successfully."

    # Add assignment to the app for All Devices with Required install intent
    Add-IntuneWin32AppAssignmentAllDevices -ID $Win32App.id -Intent "required" -Notification "hideAll" | Out-Null
} catch {
    # Failed to add QualysCloudAgent to Intune, log error and exit with code 1
    New-LogMessage -Level ERROR -Message "Failed to add QualysCloudAgent to Intune. Error: $_"
    exit 1
}