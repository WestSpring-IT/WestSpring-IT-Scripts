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
        Path  = "C:\WestSpring IT\LogFiles\$($LogDay)-$($ScriptName).log"
        Value = "$LogTime | $Level | $Message"
    }
    Add-Content @LogMessage

    # Output log message to console with appropriate color
    if ($Level -eq "ERROR") {
        Write-Host "$LogTime | $Level | $Message" -ForegroundColor Red
    }
    elseif ($Level -eq "SUCCESS") {
        Write-Host "$LogTime | $Level | $Message" -ForegroundColor Green
    }
    elseif ($Level -eq "WARN") {
        Write-Host "$LogTime | $Level | $Message" -ForegroundColor Yellow
    }
    else {
        Write-Host "$LogTime | $Level | $Message"
    }
}

# Add script name here for logging purposes (Atera and Intune often overwrite the script name)
$ScriptName = "#ScriptName#"

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
        }
        catch {
            # Failed to install module, log error and exit with code 1
            New-LogMessage -Level ERROR -Message "Failed to install module $($Name). Error: $_"
            exit 1
        }
    }
    else {
        # Module is already installed, continue
        New-LogMessage -Level INFO -Message "Module $($Name) is already installed."
    }
}

# Import file with tenant details - should have headers of TenantName, TenantId, and DomainName
$Tenants = Import-Csv -Path "Tenants.csv"
New-LogMessage -Level "INFO" -Message "Starting bulk tenant changes for $($Tenants.Count) tenants from Tenants.csv"

# Array to collect created admin credentials for CSV export
$CreatedAdmins = @()

# Check for required modules and install if missing
Check-InstalledModules -Name "Microsoft.Graph.Users"
Check-InstalledModules -Name "Microsoft.Graph.Authentication"
Check-InstalledModules -Name "Microsoft.Graph.Identity.DirectoryManagement"

foreach ($Tenant in $Tenants) {
    # Connect to Microsoft Graph with appropriate scopes for user and role management
    Connect-MgGraph -TenantId $Tenants.TenantId -Scopes "User.ReadWrite.All","RoleManagement.ReadWrite.Directory" -UseDeviceAuthentication

    # Get the initial domain for the tenant to construct the user principal name
    $InitialDomain = Get-MgDomain | Where-Object { $_.Id -like "*.onmicrosoft.com" }
    New-LogMessage -Level "INFO" -Message "MODRD for tenant $($Tenant.TenantName) ($($Tenant.TenantId)) - Initial domain identified as $($InitialDomain.Id)"

    # Get a random password for account
    $RandomPassword = (Invoke-WebRequest -Uri "https://passwordwolf.com/api/?length=16&numbers=on&upper=on&lower=on&special=on" -UseBasicParsing | ConvertFrom-Json).Password[1]
    New-LogMessage -Level "INFO" -Message "Generated random password for new account in tenant $($Tenant.TenantName)"

    try {
        # Create the new user account
        New-LogMessage -Level "INFO" -Message "Attempting to create user 'WhiteLabel Global Administrator' in tenant $($Tenant.TenantName) with UPN whitelabel@$($InitialDomain.Id)"
        $NewUser = New-MgUser -DisplayName "WhiteLabel Global Administrator" -UserPrincipalName "whitelabel@$($InitialDomain.Id)" -MailNickname "whitelabel" -AccountEnabled -PasswordProfile @{ ForceChangePasswordNextSignIn = $false; Password = $RandomPassword }
        New-LogMessage -Level "SUCCESS" -Message "Created user 'WhiteLabel Global Administrator' in tenant $($Tenant.TenantName) with UPN whitelabel@$($InitialDomain.Id)"

        # Track the created admin details for CSV export
        $CreatedAdmins += [PSCustomObject]@{
            TenantName        = $Tenant.TenantName
            UserPrincipalName = "whitelabel@$($InitialDomain.Id)"
            Password          = $RandomPassword
        }
    }
    catch {
        New-LogMessage -Level "ERROR" -Message "Failed to create user in tenant $($Tenant.TenantName). Error: $_"
        continue
    }

    try {
        # Assign the new user to the Global Administrator role
        New-LogMessage -Level "INFO" -Message "Attempting to assign 'WhiteLabel Global Administrator' to Global Administrator role in tenant $($Tenant.TenantName)"
        $TargetRole = Get-MgDirectoryRole | Where-Object DisplayName -eq "Global Administrator"
        if ($TargetRole) {
            # Add the new user to the role
            Add-MgDirectoryRoleMember -DirectoryRoleId $TargetRole.Id -DirectoryObjectId $NewUser.Id
            New-LogMessage -Level "SUCCESS" -Message "Assigned 'WhiteLabel Global Administrator' to Global Administrator role in tenant $($Tenant.TenantName)"
        }
        else {
            # Global Administrator role not found, log error
            New-LogMessage -Level "ERROR" -Message "Global Administrator role not found in tenant $($Tenant.TenantName). Cannot assign role to user."
        }
    }
    catch {
        # Failed to assign role, log error but continue to next tenant
        New-LogMessage -Level "ERROR" -Message "Failed to create user in tenant $($Tenant.TenantName). Error: $_"
    }
}

# Export created admin details to CSV
if ($CreatedAdmins.Count -gt 0) {
    $CSVPath = "CreatedAdmins_$(Get-Date -Format 'yyyy-MM-dd_HHmmss').csv"
    $CreatedAdmins | Export-Csv -Path $CSVPath -NoTypeInformation
    New-LogMessage -Level "SUCCESS" -Message "Exported details for $($CreatedAdmins.Count) created admin accounts to $CSVPath"
}
else {
    New-LogMessage -Level "WARN" -Message "No admin accounts were successfully created. CSV export skipped."
}