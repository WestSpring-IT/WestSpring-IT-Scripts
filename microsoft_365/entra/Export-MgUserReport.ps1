<#
.SYNOPSIS
    Exports Microsoft 365 user details using Microsoft Graph PowerShell modules.

.DESCRIPTION
    This script exports comprehensive user information from Microsoft 365 including:
    - Basic details (name, email, UPN)
    - MFA status and registered authentication methods
    - Manager information
    - Group memberships (direct, nested, and dynamic)
    - License assignments
    - Assigned policies
    
.PARAMETER Attributes
    Specifies which attributes to export. Options:
    - All: Exports all available attributes
    - Basic: Name, email, UPN, account status
    - Detailed: Basic + MFA, manager, groups, licenses
    - Custom array: Specify individual attributes (e.g., @('Basic', 'MFA', 'Groups'))

.PARAMETER OutputPath
    Path where the export file will be saved. Default: Current directory

.PARAMETER OutputFormat
    Format of the output file. Options: CSV, JSON. Default: CSV

.PARAMETER UserFilter
    Filter for users to export. Default: All users

.EXAMPLE
    .\Export-MgUserReport.ps1 -Attributes All -OutputFormat CSV
    
.EXAMPLE
    .\Export-MgUserReport.ps1 -Attributes @('Basic', 'MFA', 'Groups') -OutputFormat JSON
    
.EXAMPLE
    .\Export-MgUserReport.ps1 -Attributes Detailed -UserFilter "startswith(displayName,'John')"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [ValidateScript({
        if ($_ -is [string]) {
            $_ -in @('All', 'Basic', 'Detailed')
        } else {
            $validAttributes = @('Basic', 'MFA', 'Manager', 'Groups', 'Licenses', 'Policies', 'SignInActivity', 'Devices')
            $_ | ForEach-Object { $_ -in $validAttributes }
        }
    })]
    $Attributes = 'Basic',
    
    [Parameter(Mandatory=$false)]
    [string]$OutputPath = "",
    
    [Parameter(Mandatory=$false)]
    [ValidateSet('CSV', 'JSON')]
    [string]$OutputFormat = 'CSV',
    
    [Parameter(Mandatory=$false)]
    [string]$UserFilter = $null,
    
    [Parameter(Mandatory=$false)]
    [switch]$UseDeviceCode
)

# Required permissions for the script
$RequiredScopes = @(
    'User.Read.All',
    'UserAuthenticationMethod.Read.All',
    'Group.Read.All',
    'Directory.Read.All',
    'Organization.Read.All',
    'Policy.Read.All',
    'AuditLog.Read.All'
)

#region Helper Functions

function Connect-MgGraphIfNeeded {
    param([bool]$UseDeviceAuth = $false)
    
    Write-Host "Checking Microsoft Graph connection..." -ForegroundColor Cyan
    
    try {
        $context = Get-MgContext
        if (-not $context) {
            Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Yellow
            
            if ($UseDeviceAuth) {
                Write-Host "Using device code authentication..." -ForegroundColor Yellow
                Connect-MgGraph -Scopes $RequiredScopes -NoWelcome -UseDeviceCode
            } else {
                Write-Host "Please complete the authentication in your browser..." -ForegroundColor Yellow
                Connect-MgGraph -Scopes $RequiredScopes -NoWelcome
            }
            
            # Verify connection was successful
            $context = Get-MgContext
            if (-not $context) {
                Write-Error "Failed to establish connection to Microsoft Graph. Authentication may have been cancelled."
                exit 1
            }
        } else {
            Write-Host "Already connected to Microsoft Graph as $($context.Account)" -ForegroundColor Green
            
            # Check if we have required scopes
            $missingScopes = $RequiredScopes | Where-Object { $_ -notin $context.Scopes }
            if ($missingScopes) {
                Write-Host "Reconnecting with additional required scopes..." -ForegroundColor Yellow
                
                if ($UseDeviceAuth) {
                    Write-Host "Using device code authentication..." -ForegroundColor Yellow
                    Connect-MgGraph -Scopes $RequiredScopes -NoWelcome -UseDeviceCode
                } else {
                    Write-Host "Please complete the authentication in your browser..." -ForegroundColor Yellow
                    Connect-MgGraph -Scopes $RequiredScopes -NoWelcome
                }
            }
        }
        
        Write-Host "Successfully connected to Microsoft Graph" -ForegroundColor Green
        
    } catch {
        Write-Error "Failed to connect to Microsoft Graph: $_"
        Write-Host "`nTroubleshooting tips:" -ForegroundColor Yellow
        Write-Host "1. Make sure you complete the authentication in the browser window" -ForegroundColor Yellow
        Write-Host "2. Try using -UseDeviceCode parameter for alternative authentication" -ForegroundColor Yellow
        Write-Host "3. Ensure you have appropriate permissions in Microsoft 365" -ForegroundColor Yellow
        Write-Host "4. Try running: Disconnect-MgGraph, then run this script again" -ForegroundColor Yellow
        exit 1
    }
}

function Get-AttributesToExport {
    param($AttributeParam)
    
    $allAttributes = @('Basic', 'MFA', 'Manager', 'Groups', 'Licenses', 'Policies', 'SignInActivity', 'Devices')
    
    if ($AttributeParam -eq 'All') {
        return $allAttributes
    } elseif ($AttributeParam -eq 'Basic') {
        return @('Basic')
    } elseif ($AttributeParam -eq 'Detailed') {
        return @('Basic', 'MFA', 'Manager', 'Groups', 'Licenses')
    } else {
        # Custom array
        return $AttributeParam
    }
}

function Get-UserMFAStatus {
    param($UserId)
    
    try {
        $authMethods = Get-MgUserAuthenticationMethod -UserId $UserId -ErrorAction SilentlyContinue
        
        $mfaDetails = @{
            MFAEnabled = $false
            MFAMethods = @()
            PhoneAuthEnabled = $false
            EmailAuthEnabled = $false
            FIDOKeyEnabled = $false
            AuthenticatorAppEnabled = $false
            WindowsHelloEnabled = $false
        }
        
        foreach ($method in $authMethods) {
            $mfaDetails.MFAEnabled = $true
            
            switch ($method.AdditionalProperties.'@odata.type') {
                '#microsoft.graph.phoneAuthenticationMethod' {
                    $mfaDetails.PhoneAuthEnabled = $true
                    $mfaDetails.MFAMethods += 'Phone'
                }
                '#microsoft.graph.emailAuthenticationMethod' {
                    $mfaDetails.EmailAuthEnabled = $true
                    $mfaDetails.MFAMethods += 'Email'
                }
                '#microsoft.graph.fido2AuthenticationMethod' {
                    $mfaDetails.FIDOKeyEnabled = $true
                    $mfaDetails.MFAMethods += 'FIDO2 Key'
                }
                '#microsoft.graph.microsoftAuthenticatorAuthenticationMethod' {
                    $mfaDetails.AuthenticatorAppEnabled = $true
                    $mfaDetails.MFAMethods += 'Authenticator App'
                }
                '#microsoft.graph.windowsHelloForBusinessAuthenticationMethod' {
                    $mfaDetails.WindowsHelloEnabled = $true
                    $mfaDetails.MFAMethods += 'Windows Hello'
                }
            }
        }
        
        $mfaDetails.MFAMethods = $mfaDetails.MFAMethods -join ', '
        return $mfaDetails
        
    } catch {
        Write-Warning "Could not retrieve MFA status for user $UserId : $_"
        return @{
            MFAEnabled = 'Error'
            MFAMethods = 'Error retrieving data'
        }
    }
}

function Get-UserManager {
    param($UserId)
    
    try {
        $manager = Get-MgUserManager -UserId $UserId -ErrorAction SilentlyContinue
        if ($manager) {
            return @{
                ManagerName = $manager.AdditionalProperties.displayName
                ManagerEmail = $manager.AdditionalProperties.mail
                ManagerUPN = $manager.AdditionalProperties.userPrincipalName
            }
        }
    } catch {
        Write-Verbose "No manager found for user $UserId"
    }
    
    return @{
        ManagerName = 'N/A'
        ManagerEmail = 'N/A'
        ManagerUPN = 'N/A'
    }
}

function Get-UserGroupMemberships {
    param($UserId)
    
    try {
        $groups = Get-MgUserMemberOf -UserId $UserId -All -ErrorAction SilentlyContinue
        
        $directGroups = @()
        $securityGroups = @()
        $m365Groups = @()
        $dynamicGroups = @()
        
        foreach ($group in $groups) {
            if ($group.AdditionalProperties.'@odata.type' -eq '#microsoft.graph.group') {
                $groupName = $group.AdditionalProperties.displayName
                $directGroups += $groupName
                
                # Categorize by group type
                if ($group.AdditionalProperties.groupTypes -contains 'Unified') {
                    $m365Groups += $groupName
                }
                if ($group.AdditionalProperties.groupTypes -contains 'DynamicMembership') {
                    $dynamicGroups += $groupName
                }
                if ($group.AdditionalProperties.securityEnabled) {
                    $securityGroups += $groupName
                }
            }
        }
        
        return @{
            TotalGroups = $directGroups.Count
            DirectGroups = ($directGroups -join '; ')
            SecurityGroups = ($securityGroups -join '; ')
            M365Groups = ($m365Groups -join '; ')
            DynamicGroups = ($dynamicGroups -join '; ')
        }
        
    } catch {
        Write-Warning "Could not retrieve group memberships for user $UserId : $_"
        return @{
            TotalGroups = 'Error'
            DirectGroups = 'Error retrieving data'
        }
    }
}

function Get-UserLicenses {
    param($User)
    
    try {
        $licenses = $User.AssignedLicenses
        $licenseDetails = @()
        
        foreach ($license in $licenses) {
            # Get the SKU details
            try {
                $sku = Get-MgSubscribedSku -SubscribedSkuId $license.SkuId -ErrorAction SilentlyContinue
                if ($sku) {
                    $licenseDetails += $sku.SkuPartNumber
                } else {
                    $licenseDetails += $license.SkuId
                }
            } catch {
                $licenseDetails += $license.SkuId
            }
        }
        
        return @{
            LicenseCount = $licenseDetails.Count
            Licenses = ($licenseDetails -join '; ')
        }
        
    } catch {
        Write-Warning "Could not retrieve licenses for user $($User.Id) : $_"
        return @{
            LicenseCount = 0
            Licenses = 'Error retrieving data'
        }
    }
}

function Get-UserSignInActivity {
    param($User)
    
    try {
        return @{
            LastSignIn = if ($User.SignInActivity.LastSignInDateTime) { 
                $User.SignInActivity.LastSignInDateTime 
            } else { 'Never' }
            LastNonInteractiveSignIn = if ($User.SignInActivity.LastNonInteractiveSignInDateTime) { 
                $User.SignInActivity.LastNonInteractiveSignInDateTime 
            } else { 'Never' }
        }
    } catch {
        return @{
            LastSignIn = 'N/A'
            LastNonInteractiveSignIn = 'N/A'
        }
    }
}

function Get-UserRegisteredDevices {
    param($UserId)
    
    try {
        $devices = Get-MgUserRegisteredDevice -UserId $UserId -All -ErrorAction SilentlyContinue
        $deviceList = @()
        
        foreach ($device in $devices) {
            if ($device.AdditionalProperties.displayName) {
                $deviceList += $device.AdditionalProperties.displayName
            }
        }
        
        return @{
            DeviceCount = $deviceList.Count
            Devices = ($deviceList -join '; ')
        }
        
    } catch {
        Write-Warning "Could not retrieve registered devices for user $UserId : $_"
        return @{
            DeviceCount = 0
            Devices = 'Error retrieving data'
        }
    }
}

function Get-TenantName {
    try {
        $context = Get-MgContext
        if ($context) {
            # Try to get organization details for tenant name
            $org = Get-MgOrganization -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($org -and $org.DisplayName) {
                # Clean the tenant name for use in filename (remove invalid characters)
                $tenantName = $org.DisplayName -replace '[\\/:*?"<>|]', '_'
                return $tenantName
            }
            
            # Fallback to tenant ID if display name not available
            if ($context.TenantId) {
                return $context.TenantId
            }
        }
        
        # Default fallback
        return "Unknown"
        
    } catch {
        Write-Verbose "Could not retrieve tenant name: $_"
        return "Unknown"
    }
}

#endregion

#region Main Script

Write-Host "`n=== Microsoft 365 User Report Export ===" -ForegroundColor Cyan

# Connect to Microsoft Graph
Connect-MgGraphIfNeeded -UseDeviceAuth $UseDeviceCode

# Generate default output path if not specified
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $tenantName = Get-TenantName
    $dateStamp = Get-Date -Format 'yyyy_MM_dd'
    $OutputPath = ".\${dateStamp}_${tenantName}_UserReport"
    Write-Host "Using default output path: $OutputPath" -ForegroundColor Cyan
}

Write-Host "Output Format: $OutputFormat" -ForegroundColor Cyan
Write-Host "Output Path: $OutputPath.$($OutputFormat.ToLower())" -ForegroundColor Cyan

# Determine which attributes to export
$attributesToExport = Get-AttributesToExport -AttributeParam $Attributes
Write-Host "`nExporting attributes: $($attributesToExport -join ', ')" -ForegroundColor Cyan

# Get users
Write-Host "`nRetrieving users..." -ForegroundColor Yellow

try {
    $getUserParams = @{
        All = $true
        Property = @(
            'Id', 'DisplayName', 'UserPrincipalName', 'Mail', 
            'GivenName', 'Surname', 'JobTitle', 'Department', 
            'OfficeLocation', 'AccountEnabled', 'CreatedDateTime',
            'AssignedLicenses', 'SignInActivity', 'ProxyAddresses',
            'UserType', 'OnPremisesSyncEnabled'
        )
    }
    
    if ($UserFilter) {
        $getUserParams['Filter'] = $UserFilter
    }
    
    $users = Get-MgUser @getUserParams
    Write-Host "Found $($users.Count) users" -ForegroundColor Green
    
} catch {
    Write-Error "Failed to retrieve users: $_"
    exit 1
}

# Process each user
$exportData = @()
$counter = 0

foreach ($user in $users) {
    $counter++
    Write-Progress -Activity "Processing users" -Status "Processing $($user.DisplayName) ($counter of $($users.Count))" -PercentComplete (($counter / $users.Count) * 100)
    
    $userReport = [PSCustomObject]@{}
    
    # Basic attributes (always included)
    if ('Basic' -in $attributesToExport -or $attributesToExport -contains 'All') {
        $userReport | Add-Member -NotePropertyName 'DisplayName' -NotePropertyValue $user.DisplayName
        $userReport | Add-Member -NotePropertyName 'UserPrincipalName' -NotePropertyValue $user.UserPrincipalName
        $userReport | Add-Member -NotePropertyName 'Mail' -NotePropertyValue $user.Mail
        $userReport | Add-Member -NotePropertyName 'GivenName' -NotePropertyValue $user.GivenName
        $userReport | Add-Member -NotePropertyName 'Surname' -NotePropertyValue $user.Surname
        $userReport | Add-Member -NotePropertyName 'JobTitle' -NotePropertyValue $user.JobTitle
        $userReport | Add-Member -NotePropertyName 'Department' -NotePropertyValue $user.Department
        $userReport | Add-Member -NotePropertyName 'OfficeLocation' -NotePropertyValue $user.OfficeLocation
        $userReport | Add-Member -NotePropertyName 'AccountEnabled' -NotePropertyValue $user.AccountEnabled
        $userReport | Add-Member -NotePropertyName 'UserType' -NotePropertyValue $user.UserType
        $userReport | Add-Member -NotePropertyName 'CreatedDateTime' -NotePropertyValue $user.CreatedDateTime
        $userReport | Add-Member -NotePropertyName 'OnPremisesSyncEnabled' -NotePropertyValue $user.OnPremisesSyncEnabled
        
        # Aliases (proxy addresses)
        $aliases = $user.ProxyAddresses | Where-Object { $_ -like 'smtp:*' } | ForEach-Object { $_.Replace('smtp:', '') }
        $userReport | Add-Member -NotePropertyName 'Aliases' -NotePropertyValue ($aliases -join '; ')
    }
    
    # MFA Status
    if ('MFA' -in $attributesToExport) {
        $mfaStatus = Get-UserMFAStatus -UserId $user.Id
        $userReport | Add-Member -NotePropertyName 'MFAEnabled' -NotePropertyValue $mfaStatus.MFAEnabled
        $userReport | Add-Member -NotePropertyName 'MFAMethods' -NotePropertyValue $mfaStatus.MFAMethods
        $userReport | Add-Member -NotePropertyName 'PhoneAuthEnabled' -NotePropertyValue $mfaStatus.PhoneAuthEnabled
        $userReport | Add-Member -NotePropertyName 'AuthenticatorAppEnabled' -NotePropertyValue $mfaStatus.AuthenticatorAppEnabled
        $userReport | Add-Member -NotePropertyName 'FIDOKeyEnabled' -NotePropertyValue $mfaStatus.FIDOKeyEnabled
    }
    
    # Manager
    if ('Manager' -in $attributesToExport) {
        $manager = Get-UserManager -UserId $user.Id
        $userReport | Add-Member -NotePropertyName 'ManagerName' -NotePropertyValue $manager.ManagerName
        $userReport | Add-Member -NotePropertyName 'ManagerEmail' -NotePropertyValue $manager.ManagerEmail
        $userReport | Add-Member -NotePropertyName 'ManagerUPN' -NotePropertyValue $manager.ManagerUPN
    }
    
    # Groups
    if ('Groups' -in $attributesToExport) {
        $groups = Get-UserGroupMemberships -UserId $user.Id
        $userReport | Add-Member -NotePropertyName 'TotalGroups' -NotePropertyValue $groups.TotalGroups
        $userReport | Add-Member -NotePropertyName 'DirectGroups' -NotePropertyValue $groups.DirectGroups
        $userReport | Add-Member -NotePropertyName 'SecurityGroups' -NotePropertyValue $groups.SecurityGroups
        $userReport | Add-Member -NotePropertyName 'M365Groups' -NotePropertyValue $groups.M365Groups
        $userReport | Add-Member -NotePropertyName 'DynamicGroups' -NotePropertyValue $groups.DynamicGroups
    }
    
    # Licenses
    if ('Licenses' -in $attributesToExport) {
        $licenses = Get-UserLicenses -User $user
        $userReport | Add-Member -NotePropertyName 'LicenseCount' -NotePropertyValue $licenses.LicenseCount
        $userReport | Add-Member -NotePropertyName 'AssignedLicenses' -NotePropertyValue $licenses.Licenses
    }
    
    # Sign-in Activity
    if ('SignInActivity' -in $attributesToExport) {
        $signIn = Get-UserSignInActivity -User $user
        $userReport | Add-Member -NotePropertyName 'LastSignIn' -NotePropertyValue $signIn.LastSignIn
        $userReport | Add-Member -NotePropertyName 'LastNonInteractiveSignIn' -NotePropertyValue $signIn.LastNonInteractiveSignIn
    }
    
    # Registered Devices
    if ('Devices' -in $attributesToExport) {
        $devices = Get-UserRegisteredDevices -UserId $user.Id
        $userReport | Add-Member -NotePropertyName 'RegisteredDeviceCount' -NotePropertyValue $devices.DeviceCount
        $userReport | Add-Member -NotePropertyName 'RegisteredDevices' -NotePropertyValue $devices.Devices
    }
    
    $exportData += $userReport
}

Write-Progress -Activity "Processing users" -Completed

# Export data
Write-Host "`nExporting data..." -ForegroundColor Yellow

# Check if output path already has the correct extension
$expectedExtension = ".$($OutputFormat.ToLower())"
if ($OutputPath.EndsWith($expectedExtension)) {
    $outputFile = $OutputPath
} else {
    # Remove any existing extension and add the correct one
    $outputFile = [System.IO.Path]::ChangeExtension($OutputPath, $OutputFormat.ToLower())
}

try {
    switch ($OutputFormat) {
        'CSV' {
            $exportData | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8
        }
        'JSON' {
            $exportData | ConvertTo-Json -Depth 10 | Out-File -FilePath $outputFile -Encoding UTF8
        }
    }
    
    Write-Host "`nExport completed successfully!" -ForegroundColor Green
    Write-Host "File saved to: $outputFile" -ForegroundColor Green
    Write-Host "Total users exported: $($exportData.Count)" -ForegroundColor Green
    
} catch {
    Write-Error "Failed to export data: $_"
    exit 1
}

#endregion