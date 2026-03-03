#       Copyright © WESTSPRING IT LIMITED
#       Author: Thomas Samuel
#       Support: thomassamuel@westspring-it.co.uk

# Add script name here for logging purposes (Atera and Intune change the file name when running)
$ScriptName = "LocalAdministrators"

# Function to log messages
function New-LogMessage {
    param(
        [Parameter()]
        [ValidateSet("INFO", "ERROR", "SUCCESS", "WARN")]
        [string]$Level = "INFO",

        [Parameter(Mandatory)]
        [string]$Message
    )

    # Checks if the logging folder exists
    if (-not (Test-Path -Path "C:\WestSpring IT\LogFiles")) {
        # Log path doesn't exist, creating now
        New-Item -Path "C:\WestSpring IT\LogFiles" -ItemType Directory -Force | Out-Null
    }

    #Get current date and time
    $LogDay = Get-Date -UFormat %Y-%m-%d
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
        Write-Host "$LogTime | $Level | $Message" -ForegroundColor Cyan
    }
}

<# Start script logic from here #>

$Admins = @(
    @{ Name = "wsadmin"; Password = "{[WSADMINPassword]}" },
    @{ Name = "{[ClientLocalAdminUsername]}"; Password = "{[ClientLocalAdminPassword]}" }
)

try {
    New-LogMessage -Level INFO -Message "Script started. Configuring local administrator accounts."

    foreach ($Admin in $Admins) {

        # Convert provided password to SecureString (required by *-LocalUser cmdlets)
        $SecurePassword = ConvertTo-SecureString $Admin.Password -AsPlainText -Force
        $AdminName      = $Admin.Name

        # Create account if missing, otherwise align password
        $ExistingUser = Get-LocalUser -Name $AdminName -ErrorAction SilentlyContinue
        if (-not $ExistingUser) {
            New-LogMessage -Level INFO -Message "Account does not exist: $AdminName. Creating now."

            $UserParameters = @{
                Name     = $AdminName
                Password = $SecurePassword
            }

            New-LocalUser @UserParameters | Out-Null
            New-LogMessage -Level SUCCESS -Message "Created local user: $AdminName"
        } else {
            New-LogMessage -Level INFO -Message "Account already exists: $AdminName. Updating password."
            Set-LocalUser -Name $AdminName -Password $SecurePassword
            New-LogMessage -Level SUCCESS -Message "Password updated for: $AdminName"
        }

        # Enforce password never expires (service/admin account stability)
        Set-LocalUser -Name $AdminName -PasswordNeverExpires $true
        New-LogMessage -Level SUCCESS -Message "Set PasswordNeverExpires for: $AdminName"

        # Ensure membership of local Administrators group
        $AdminGroupMembers = Get-LocalGroupMember -Group "Administrators" -ErrorAction SilentlyContinue
        $IsAdministrator   = $false

        foreach ($Member in $AdminGroupMembers) {
            # Member.Name typically looks like "MACHINE\username"; match the username tail
            if ($Member.Name -match "\\$([regex]::Escape($AdminName))$") {
                $IsAdministrator = $true
                break
            }
        }

        if (-not $IsAdministrator) {
            New-LogMessage -Level WARN -Message "Account is not in local Administrators group: $AdminName. Adding now."
            Add-LocalGroupMember -Group "Administrators" -Member $AdminName
            New-LogMessage -Level SUCCESS -Message "Added to local Administrators group: $AdminName"
        } else {
            New-LogMessage -Level INFO -Message "Account already in local Administrators group: $AdminName"
        }
    }

    New-LogMessage -Level SUCCESS -Message "Script completed successfully. Local administrator configuration complete."
    exit 0
} catch {
    $ErrorMessage = $_.Exception.Message
    New-LogMessage -Level ERROR -Message "Script failed. Error: $ErrorMessage"
    exit 1
}