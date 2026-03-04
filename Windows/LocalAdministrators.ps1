<#
.SYNOPSIS
Configures local administrator accounts on a Windows system.

.DESCRIPTION
This script is designed to be deployed via Atera and manages local administrator accounts by creating new accounts, updating passwords, and ensuring they are members of the local Administrators group. It uses Atera variables for account credentials and logs all operations to a log file.

.PARAMETER None
This script does not accept parameters. Configuration is defined within the script using the $Admins array.

.NOTES
- The script requires administrative privileges to execute successfully.
- Atera and Intune may overwrite the script name, so the $ScriptName variable is explicitly defined as "LocalAdministrators".
- Credentials are passed as plaintext variables from Atera deployment and converted to SecureString objects.
- Log files are created in "C:\WestSpring IT\LogFiles\" with the filename format: "DD-MM-YYYY-LocalAdministrators.log"
- Passwords for created accounts are set to never expire.
- The script uses color-coded console output: Red for errors, Green for success, Yellow for warnings.

.EXAMPLE
.\LocalAdministrators.ps1

This example runs the script to configure local administrator accounts as defined in the $Admins array.

.FUNCTIONALITY
1. Creates or updates local user accounts specified in the $Admins array.
2. Sets account passwords to never expire.
3. Adds accounts to the local Administrators group if not already present.
4. Logs all operations (creation, updates, group membership) to a dated log file.
5. Returns exit code 0 on success or exit code 1 on failure.

.AUTHOR
Thomas Samuel
WESTSPRING IT LIMITED

.LASTMODIFIED
03/03/2026
#>

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
$ScriptName = "LocalAdministrators"

# This script is designed to be deployed via Atera, and uses variables for the local administrator account names and passwords.

New-LogMessage -Level INFO -Message "Script started. Configuring local administrator accounts."

$Admins = @(
    @{ Name = "wsadmin"; Password = "{[WSADMINPassword]}" },
    @{ Name = "{[ClientLocalAdminUsername]}"; Password = "{[ClientLocalAdminPassword]}" }
)

try {
    foreach ($Admin in $Admins) {
        # Convert provided password to SecureString
        $SecurePassword = ConvertTo-SecureString $Admin.Password -AsPlainText -Force

        # Check if admin already exists on system
        $ExistingUser = Get-LocalUser -Name $Admin.Name -ErrorAction SilentlyContinue
        if (-not $ExistingUser) {
            # Account doesn't exist, creating it now
            New-LogMessage -Level INFO -Message "Account does not exist: $($Admin.Name). Creating now."

            $UserParameters = @{
                Name = $Admin.Name
                Password = $SecurePassword
            }
            New-LocalUser @UserParameters | Out-Null

            New-LogMessage -Level SUCCESS -Message "Created local user: $($Admin.Name)"
        } else {
            # Account already exists, aligning password
            New-LogMessage -Level INFO -Message "Account already exists: $($Admin.Name). Updating password."
            Set-LocalUser -Name $Admin.Name -Password $SecurePassword
            New-LogMessage -Level SUCCESS -Message "Password updated for: $($Admin.Name)"
        }

        # Enforce password never expires
        Set-LocalUser -Name $Admin.Name -PasswordNeverExpires $true
        New-LogMessage -Level SUCCESS -Message "Set PasswordNeverExpires for: $($Admin.Name)"

        # Checks if user is already in local Administrators group
        $AdminGroupMembers = Get-LocalGroupMember -Group "Administrators" -ErrorAction SilentlyContinue
        $IsAdministrator = $false

        foreach ($Member in $AdminGroupMembers) {
            # Member.Name typically looks like "MACHINE\username"; match the username tail
            if ($Member.Name -match "\\$([regex]::Escape($Admin.Name))$") {
                $IsAdministrator = $true
                break
            }
        }

        if (-not $IsAdministrator) {
            # User is not in Administrators group, adding now
            New-LogMessage -Level WARN -Message "Account is not in local Administrators group: $($Admin.Name). Adding now."
            Add-LocalGroupMember -Group "Administrators" -Member $Admin.Name
            New-LogMessage -Level SUCCESS -Message "Added to local Administrators group: $($Admin.Name)"
        } else {
            # User is already in Administrators group
            New-LogMessage -Level INFO -Message "Account already in local Administrators group: $($Admin.Name)"
        }
        # Continue to next admin account
    }

    New-LogMessage -Level SUCCESS -Message "Script completed successfully. Local administrator configuration complete."
    exit 0
} catch {
    $ErrorMessage = $_.Exception.Message
    New-LogMessage -Level ERROR -Message "Script failed. Error: $ErrorMessage"
    exit 1
}