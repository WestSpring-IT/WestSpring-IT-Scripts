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

New-LogMessage -Level "INFO" -Message "Starting Local Administrator Configuration"

foreach ($Admin in $Admins) {
    try {
        # Convert provided password to a secure string
        $securePassword = ConvertTo-SecureString $Admin.Password -AsPlainText -Force

        # Check account exists, create if not
        if (-not (Get-LocalUser -Name $Admin.Name -ErrorAction SilentlyContinue)) {
            New-LogMessage -Level "INFO" -Message "$($Admin.Name) does not exist"
            New-LogMessage -Level "INFO" -Message "Creating account $($Admin.Name) with provided password"
            # Create the local user account
            $UserParams = @{
                Name     = $Admin.Name
                Password = $SecurePassword
            }
            New-LocalUser @UserParams | Out-Null
            New-LogMessage -Level "SUCCESS" -Message "Created $($Admin.Name)"
        }
        else {
            # User does exist, align password
            New-LogMessage -Level "WARN" -Message "Account $($Admin.Name) already exists"
            New-LogMessage -Level "INFO" -Message "Updating password for $($Admin.Name)"
            Set-LocalUser -Name $Admin.Name -Password $SecurePassword
            New-LogMessage -Level "SUCCESS" -Message "Password updated for $($Admin.Name)"
        }

        # Set password to never expire
        Set-LocalUser -Name $Admin.Name -PasswordNeverExpires $true
        New-LogMessage -Level "SUCCESS" -Message "Set password never expires for $($Admin.Name)"

        # Add to Administrators only if not already a member
        $AdminGroupMembers = Get-LocalGroupMember -Group "Administrators" -ErrorAction SilentlyContinue
        $AlreadyMember = $false
        foreach ($Member in $AdminGroupMembers) {
            # Name typically like "MACHINE\\wsadmin"; match the tail
            if ($Member.Name -match "\\$($Admin.Name)$") {
                $AlreadyMember = $true
                break 
            }
        }

        if (-not $AlreadyMember) {
            # Add user to Administrators group
            New-LogMessage -Level "WARN" -Message "Account $($Admin.Name) is not in Administrators group"
            Add-LocalGroupMember -Group "Administrators" -Member $Admin.Name
            New-LogMessage -Level "SUCCESS" -Message "Added $($Admin.Name) to Administrators"
        }
        else {
            # Already a member, no action needed
            New-LogMessage -Level "INFO" -Message "Account $($Admin.Name) is already in Administrators group"
        }
    }
    catch {
        New-LogMessage -Level "ERROR" -Message "Failed to configure account $($Admin.Name): $($_.Exception.Message)"
        # Continue to next admin
    }
}

New-LogMessage -Level "INFO" -Message "Local admin account setup completed"