<#
.SYNOPSIS
    ULTIMATE Microsoft 365 user report export - exports 130+ attributes.

.DESCRIPTION
    This is the ultimate comprehensive user export script with EVERYTHING available:
    - 100+ standard attributes across 15 categories
    - Optional detailed features (Admin Units, App Permissions, OneDrive, etc.)
    - License GUID translation to friendly names
    - Shared mailbox detection
    - Service provisioning error detection
    - On-premises sync information
    - Identity federation details
    - Age/compliance attributes
    
.PARAMETER Attributes
    Specifies which attribute categories to export:
    - All: Everything (standard attributes, not optional)
    - Basic, Contact, Employee, Security, Hierarchy, etc.
    - Custom array: Mix and match categories
    - Individual fields: Specify exact field names (e.g., 'DisplayName', 'LastSignIn')
    
    You can mix categories and individual fields:
    @('Basic', 'Manager', 'LastSignIn', 'UsageLocation')
    
    Common field name aliases:
    - 'LastLogin' or 'LastSignInDateTime' → 'LastSignIn'
    - 'Title' → 'JobTitle'
    - 'Office' → 'OfficeLocation'

.PARAMETER IncludeAdminUnits
    Include Administrative Unit memberships (1 extra API call per user)

.PARAMETER IncludeAppPermissions
    Include OAuth app permission grants (1 extra API call per user)
    Shows which apps users have consented to - important for security audits

.PARAMETER IncludeMFAPhoneNumbers
    Include actual MFA phone numbers and email addresses (2 extra API calls per user)

.PARAMETER IncludeProfilePhoto
    Check if user has a profile photo (1 extra API call per user)

.PARAMETER IncludeOneDrive
    Include OneDrive quota and usage information (1 extra API call per user)

.PARAMETER IncludeServicePlans
    Include detailed service plan information for licenses (disabled services, etc.)

.PARAMETER IncludeAllOptionalFeatures
    Enable ALL optional features at once (slower but most comprehensive)

.EXAMPLE
    .\Export-MgUserReport-Ultimate.ps1 -Attributes All
    Standard comprehensive export (100+ attributes)
    
.EXAMPLE
    .\Export-MgUserReport-Ultimate.ps1 -Attributes All -IncludeAllOptionalFeatures
    Export EVERYTHING including all optional features (130+ attributes)
    
.EXAMPLE
    .\Export-MgUserReport-Ultimate.ps1 -Attributes Security -IncludeAppPermissions -IncludeMFAPhoneNumbers
    Security-focused export with app permissions and MFA details

.EXAMPLE
    .\Export-MgUserReport-Ultimate.ps1 -Attributes @('DisplayName', 'UserPrincipalName', 'LastSignIn', 'ManagerName', 'UsageLocation')
    Export ONLY specific fields - perfect for custom reports
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    $Attributes = 'Basic',
    
    [Parameter(Mandatory=$false)]
    [string]$OutputPath = "",
    
    [Parameter(Mandatory=$false)]
    [ValidateSet('CSV', 'JSON')]
    [string]$OutputFormat = 'CSV',
    
    [Parameter(Mandatory=$false)]
    [string]$UserFilter = $null,
    
    [Parameter(Mandatory=$false)]
    [switch]$UseDeviceCode,
    
    [Parameter(Mandatory=$false)]
    [switch]$IncludeServicePlans,
    
    [Parameter(Mandatory=$false)]
    [switch]$IncludeAdminUnits,
    
    [Parameter(Mandatory=$false)]
    [switch]$IncludeAppPermissions,
    
    [Parameter(Mandatory=$false)]
    [switch]$IncludeMFAPhoneNumbers,
    
    [Parameter(Mandatory=$false)]
    [switch]$IncludeProfilePhoto,
    
    [Parameter(Mandatory=$false)]
    [switch]$IncludeOneDrive,
    
    [Parameter(Mandatory=$false)]
    [switch]$IncludeAllOptionalFeatures
)

# Handle IncludeAllOptionalFeatures flag
if ($IncludeAllOptionalFeatures) {
    $IncludeAdminUnits = $true
    $IncludeAppPermissions = $true
    $IncludeMFAPhoneNumbers = $true
    $IncludeProfilePhoto = $true
    $IncludeOneDrive = $true
    $IncludeServicePlans = $true
}

# Required permissions
$RequiredScopes = @(
    'User.Read.All',
    'UserAuthenticationMethod.Read.All',
    'Group.Read.All',
    'Directory.Read.All',
    'Organization.Read.All',
    'Policy.Read.All',
    'AuditLog.Read.All',
    'Device.Read.All'
)

# Add conditional scopes based on optional features
if ($IncludeAdminUnits) {
    $RequiredScopes += 'AdministrativeUnit.Read.All'
}
if ($IncludeAppPermissions) {
    $RequiredScopes += 'DelegatedPermissionGrant.ReadWrite.All'
}
if ($IncludeOneDrive) {
    $RequiredScopes += 'Files.Read.All'
}

# Global cache variables
$script:LicenseMappingCache = $null
$script:DirectReportsCache = @{}
$script:FilterToRequestedFields = $false
$script:RequestedFields = @()

#region Helper Functions

function Connect-MgGraphIfNeeded {
    param([bool]$UseDeviceAuth = $false)
    
    Write-Host "Checking Microsoft Graph connection..." -ForegroundColor Cyan
    
    try {
        $context = Get-MgContext
        if (-not $context) {
            Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Yellow
            
            if ($UseDeviceAuth) {
                Connect-MgGraph -Scopes $RequiredScopes -NoWelcome -UseDeviceCode
            } else {
                Connect-MgGraph -Scopes $RequiredScopes -NoWelcome
            }
            
            $context = Get-MgContext
            if (-not $context) {
                Write-Error "Failed to establish connection to Microsoft Graph."
                exit 1
            }
        } else {
            Write-Host "Already connected to Microsoft Graph as $($context.Account)" -ForegroundColor Green
            
            $missingScopes = $RequiredScopes | Where-Object { $_ -notin $context.Scopes }
            if ($missingScopes) {
                Write-Host "Reconnecting with additional required scopes..." -ForegroundColor Yellow
                
                if ($UseDeviceAuth) {
                    Connect-MgGraph -Scopes $RequiredScopes -NoWelcome -UseDeviceCode
                } else {
                    Connect-MgGraph -Scopes $RequiredScopes -NoWelcome
                }
            }
        }
        
        Write-Host "Successfully connected to Microsoft Graph" -ForegroundColor Green
        
    } catch {
        Write-Error "Failed to connect to Microsoft Graph: $_"
        exit 1
    }
}

function Get-AttributesToExport {
    param($AttributeParam)
    
    # Define field name to category mappings
    $fieldMapping = @{
        # Basic fields
        'DisplayName' = 'Basic'
        'UserPrincipalName' = 'Basic'
        'Mail' = 'Basic'
        'GivenName' = 'Basic'
        'Surname' = 'Basic'
        'JobTitle' = 'Basic'
        'Department' = 'Basic'
        'OfficeLocation' = 'Basic'
        'AccountEnabled' = 'Basic'
        'UserType' = 'Basic'
        'CreatedDateTime' = 'Basic'
        'OnPremisesSyncEnabled' = 'Basic'
        'Aliases' = 'Basic'
        
        # Contact fields
        'BusinessPhones' = 'Contact'
        'MobilePhone' = 'Contact'
        'FaxNumber' = 'Contact'
        'StreetAddress' = 'Contact'
        'City' = 'Contact'
        'State' = 'Contact'
        'PostalCode' = 'Contact'
        'Country' = 'Contact'
        'UsageLocation' = 'Contact'
        'PreferredLanguage' = 'Contact'
        
        # Employee fields
        'EmployeeId' = 'Employee'
        'EmployeeHireDate' = 'Employee'
        'EmployeeType' = 'Employee'
        'CompanyName' = 'Employee'
        'Division' = 'Employee'
        'CostCenter' = 'Employee'
        
        # MFA fields
        'MFAEnabled' = 'MFA'
        'MFAMethods' = 'MFA'
        'MFAMethodCount' = 'MFA'
        'PhoneAuthEnabled' = 'MFA'
        'EmailAuthEnabled' = 'MFA'
        'FIDOKeyEnabled' = 'MFA'
        'AuthenticatorAppEnabled' = 'MFA'
        'WindowsHelloEnabled' = 'MFA'
        'SoftwareOathEnabled' = 'MFA'
        
        # Manager fields
        'ManagerName' = 'Manager'
        'ManagerEmail' = 'Manager'
        'ManagerUPN' = 'Manager'
        'ManagerId' = 'Manager'
        
        # DirectReports fields
        'DirectReportCount' = 'DirectReports'
        'DirectReports' = 'DirectReports'
        
        # Groups fields
        'TotalGroups' = 'Groups'
        'DirectGroups' = 'Groups'
        'SecurityGroups' = 'Groups'
        'M365Groups' = 'Groups'
        'DynamicGroups' = 'Groups'
        'DistributionGroups' = 'Groups'
        
        # License fields
        'LicenseCount' = 'Licenses'
        'Licenses' = 'Licenses'
        'AssignmentPaths' = 'Licenses'
        'DisabledServicePlans' = 'Licenses'
        'ServiceProvisioningErrors' = 'Licenses'
        
        # MailboxType fields
        'MailboxType' = 'MailboxType'
        'IsSharedMailbox' = 'MailboxType'
        'MailNickname' = 'MailboxType'
        
        # Device fields
        'RegisteredDeviceCount' = 'Devices'
        'RegisteredDevices' = 'Devices'
        'OwnedDeviceCount' = 'Devices'
        'OwnedDevices' = 'Devices'
        
        # SignInActivity fields
        'LastSignIn' = 'SignInActivity'
        'LastSignInDateTime' = 'SignInActivity'
        'LastLogin' = 'SignInActivity'
        'LastNonInteractiveSignIn' = 'SignInActivity'
        'LastSuccessfulSignIn' = 'SignInActivity'
        
        # Security fields
        'PasswordNeverExpires' = 'Security'
        'PasswordLastChanged' = 'Security'
        'AccountLocked' = 'Security'
        'ShowInAddressList' = 'Security'
        'ExternalUserState' = 'Security'
        'ExternalUserStateChangeDateTime' = 'Security'
        'RefreshTokensValidFrom' = 'Security'
        'SecurityIdentifier' = 'Security'
        
        # Guest fields
        'IsGuest' = 'Guest'
        'GuestInvitationStatus' = 'Guest'
        'GuestInvitedDateTime' = 'Guest'
        'ExternalEmailAddress' = 'Guest'
        'AgeGroup' = 'Guest'
        'ConsentProvidedForMinor' = 'Guest'
        'LegalAgeGroupClassification' = 'Guest'
        
        # Identity fields
        'Identities' = 'Identity'
        'IMAddresses' = 'Identity'
        'OtherMails' = 'Identity'
        'CreationType' = 'Identity'
        
        # OnPremises fields
        'OnPremisesDistinguishedName' = 'OnPremises'
        'OnPremisesDomainName' = 'OnPremises'
        'OnPremisesSamAccountName' = 'OnPremises'
        'OnPremisesSecurityIdentifier' = 'OnPremises'
        'OnPremisesUserPrincipalName' = 'OnPremises'
        'OnPremisesImmutableId' = 'OnPremises'
        'OnPremisesLastSyncDateTime' = 'OnPremises'
        'OnPremisesExtensionAttributes' = 'OnPremises'
        'OnPremisesProvisioningErrors' = 'OnPremises'
    }
    
    $allAttributes = @('Basic', 'Contact', 'Employee', 'MFA', 'Manager', 'DirectReports', 
                       'Groups', 'Licenses', 'MailboxType', 'Devices', 'SignInActivity', 
                       'Security', 'Guest', 'Extensions', 'Identity', 'OnPremises')
    
    # Handle preset configurations
    if ($AttributeParam -is [string]) {
        if ($AttributeParam -eq 'All') {
            return $allAttributes
        } elseif ($AttributeParam -eq 'Basic') {
            return @('Basic', 'MailboxType')
        } elseif ($AttributeParam -eq 'Detailed') {
            return @('Basic', 'Contact', 'Employee', 'MFA', 'Manager', 'Groups', 'Licenses', 'MailboxType')
        } elseif ($AttributeParam -eq 'Contact') {
            return @('Basic', 'Contact')
        } elseif ($AttributeParam -eq 'Employee') {
            return @('Basic', 'Employee', 'Manager', 'DirectReports')
        } elseif ($AttributeParam -eq 'Security') {
            return @('Basic', 'MFA', 'Security', 'SignInActivity')
        } elseif ($AttributeParam -eq 'Hierarchy') {
            return @('Basic', 'Employee', 'Manager', 'DirectReports')
        } else {
            # Single category
            if ($AttributeParam -in $allAttributes) {
                return @($AttributeParam)
            } else {
                Write-Warning "Unknown attribute preset: $AttributeParam. Using Basic."
                return @('Basic')
            }
        }
    }
    
    # Handle arrays - can contain categories or individual field names
    $categoriesToInclude = @()
    $requestedFields = @()
    
    foreach ($item in $AttributeParam) {
        if ($item -in $allAttributes) {
            # It's a category
            $categoriesToInclude += $item
        } elseif ($fieldMapping.ContainsKey($item)) {
            # It's an individual field - add its category
            $category = $fieldMapping[$item]
            if ($category -notin $categoriesToInclude) {
                $categoriesToInclude += $category
            }
            $requestedFields += $item
        } else {
            Write-Warning "Unknown attribute or field: $item (ignoring)"
        }
    }
    
    # Store requested fields in script scope for filtering later
    if ($requestedFields.Count -gt 0) {
        $script:RequestedFields = $requestedFields
        $script:FilterToRequestedFields = $true
    } else {
        $script:FilterToRequestedFields = $false
    }
    
    if ($categoriesToInclude.Count -eq 0) {
        Write-Warning "No valid attributes specified. Using Basic."
        return @('Basic')
    }
    
    return $categoriesToInclude
}

function Initialize-LicenseMapping {
    if ($null -ne $script:LicenseMappingCache) {
        return $script:LicenseMappingCache
    }
    
    Write-Host "Building license GUID to name mapping..." -ForegroundColor Cyan
    
    # Microsoft's official SKU Part Number to Friendly Name mapping
    # Source: https://learn.microsoft.com/en-us/entra/identity/users/licensing-service-plan-reference
    $skuFriendlyNames = @{
        'AAD_BASIC' = 'Microsoft Entra Basic'
        'AAD_PREMIUM' = 'Microsoft Entra ID P1'
        'AAD_PREMIUM_P2' = 'Microsoft Entra ID P2'
        'DEVELOPERPACK_E5' = 'Microsoft 365 E5 Developer (without Windows and Audio Conferencing)'
        'ENTERPRISEPACK' = 'Office 365 E3'
        'ENTERPRISEPREMIUM' = 'Office 365 E5'
        'ENTERPRISEPREMIUM_NOPSTNCONF' = 'Office 365 E5 (without Audio Conferencing)'
        'SPE_E3' = 'Microsoft 365 E3'
        'SPE_E5' = 'Microsoft 365 E5'
        'SPE_F1' = 'Microsoft 365 F1'
        'SPE_F3' = 'Microsoft 365 F3'
        'Microsoft_365_Copilot' = 'Microsoft 365 Copilot'
        'POWER_BI_PRO' = 'Power BI Pro'
        'POWER_BI_STANDARD' = 'Power BI (free)'
        'PROJECTPREMIUM' = 'Project Plan 5'
        'PROJECTPROFESSIONAL' = 'Project Plan 3'
        'PROJECTESSENTIALS' = 'Project Online Essentials'
        'VISIOCLIENT' = 'Visio Plan 2'
        'VISIOONLINE_PLAN1' = 'Visio Plan 1'
        'TEAMS_EXPLORATORY' = 'Microsoft Teams Exploratory'
        'PHONESYSTEM_VIRTUALUSER' = 'Phone System - Virtual User'
        'MCOSTANDARD' = 'Skype for Business Online (Plan 2)'
        'MCOEV' = 'Phone System'
        'MCOPSTN1' = 'Domestic Calling Plan'
        'MCOPSTN2' = 'International Calling Plan'
        'MCOPSTN5' = 'Domestic Calling Plan (120 min)'
        'MCOPSTNC' = 'Communications Credits'
        'MCOMEETADV' = 'Microsoft 365 Audio Conferencing'
        'EXCHANGESTANDARD' = 'Exchange Online (Plan 1)'
        'EXCHANGEENTERPRISE' = 'Exchange Online (Plan 2)'
        'EXCHANGEARCHIVE' = 'Exchange Online Archiving'
        'EXCHANGEARCHIVE_ADDON' = 'Exchange Online Archiving for Exchange Online'
        'EXCHANGEDESKLESS' = 'Exchange Online Kiosk'
        'EXCHANGE_S_ESSENTIALS' = 'Exchange Essentials'
        'SHAREPOINTSTANDARD' = 'SharePoint Online (Plan 1)'
        'SHAREPOINTENTERPRISE' = 'SharePoint Online (Plan 2)'
        'ONEDRIVESTANDARD' = 'OneDrive for Business (Plan 1)'
        'OFFICESUBSCRIPTION' = 'Microsoft 365 Apps for Enterprise'
        'O365_BUSINESS' = 'Microsoft 365 Apps for Business'
        'O365_BUSINESS_ESSENTIALS' = 'Microsoft 365 Business Basic'
        'O365_BUSINESS_PREMIUM' = 'Microsoft 365 Business Standard'
        'SMB_BUSINESS' = 'Microsoft 365 Business Basic'
        'SMB_BUSINESS_ESSENTIALS' = 'Microsoft 365 Business Basic'
        'SMB_BUSINESS_PREMIUM' = 'Microsoft 365 Business Premium'
        'SPB' = 'Microsoft 365 Business Premium'
        'INTUNE_A' = 'Intune'
        'EMSPREMIUM' = 'Enterprise Mobility + Security E5'
        'EMS' = 'Enterprise Mobility + Security E3'
        'RIGHTSMANAGEMENT' = 'Azure Information Protection Plan 1'
        'RIGHTSMANAGEMENT_ADHOC' = 'Azure Information Protection Premium P1'
        'DYN365_ENTERPRISE_PLAN1' = 'Dynamics 365 Plan 1'
        'DYN365_ENTERPRISE_SALES' = 'Dynamics 365 for Sales'
        'DYN365_ENTERPRISE_CUSTOMER_SERVICE' = 'Dynamics 365 for Customer Service'
        'DYN365_FINANCIALS_BUSINESS_SKU' = 'Dynamics 365 Business Central Essentials'
        'DYN365_ENTERPRISE_TEAM_MEMBERS' = 'Dynamics 365 Team Members'
        'STREAM' = 'Microsoft Stream'
        'FLOW_FREE' = 'Power Automate Free'
        'FLOW_P1' = 'Power Automate per user plan'
        'FLOW_P2' = 'Power Automate per user with attended RPA plan'
        'POWERAPPS_VIRAL' = 'Power Apps Plan 2 Trial'
        'POWERAPPS_PER_USER' = 'Power Apps per user plan'
        'POWER_VIRTUAL_AGENTS_VIRAL' = 'Power Virtual Agents Viral Trial'
        'TEAMS_FREE' = 'Microsoft Teams (Free)'
        'TEAMS1' = 'Microsoft Teams'
        'MICROSOFT_BUSINESS_CENTER' = 'Microsoft Business Center'
        'PROJECTONLINE_PLAN_1' = 'Project Online Essentials'
        'PROJECTONLINE_PLAN_2' = 'Project Online Professional'
        'WINDOWS_STORE' = 'Windows Store for Business'
        'WIN10_VDA_E3' = 'Windows 10/11 Enterprise E3'
        'WIN10_VDA_E5' = 'Windows 10/11 Enterprise E5'
        'WINDOWS_DEFENDER_ATP' = 'Microsoft Defender for Endpoint'
        'THREAT_INTELLIGENCE' = 'Microsoft Defender for Office 365 (Plan 2)'
        'ATP_ENTERPRISE' = 'Microsoft Defender for Office 365 (Plan 1)'
        'EQUIVIO_ANALYTICS' = 'Microsoft 365 Advanced eDiscovery'
        'INFORMATION_PROTECTION_COMPLIANCE' = 'Microsoft 365 E5 Compliance'
        'IDENTITY_THREAT_PROTECTION' = 'Microsoft 365 E5 Security'
        'M365_F1' = 'Microsoft 365 F1'
        'M365EDU_A3_FACULTY' = 'Microsoft 365 A3 for faculty'
        'M365EDU_A3_STUDENT' = 'Microsoft 365 A3 for students'
        'M365EDU_A5_FACULTY' = 'Microsoft 365 A5 for faculty'
        'M365EDU_A5_STUDENT' = 'Microsoft 365 A5 for students'
        'STANDARDPACK' = 'Office 365 E1'
        'STANDARDWOFFPACK' = 'Office 365 E2'
        'ENTERPRISEPACKLRG' = 'Office 365 E3'
        'ENTERPRISEWITHSCAL' = 'Office 365 E4'
        'DESKLESSPACK' = 'Office 365 F3'
        'MIDSIZEPACK' = 'Office 365 Midsize Business'
        'LITEPACK' = 'Office 365 Small Business'
        'LITEPACK_P2' = 'Office 365 Small Business Premium'
        'WACONEDRIVESTANDARD' = 'OneDrive for Business (Plan 1)'
        'WACONEDRIVEENTERPRISE' = 'OneDrive for Business (Plan 2)'
        'POWERAPPS_PER_APP' = 'Power Apps per app plan'
        'CRMSTANDARD' = 'Dynamics 365 Sales Professional'
        'CRMPLAN2' = 'Dynamics 365 Customer Engagement Plan'
        'BUSINESS_VOICE_MED' = 'Microsoft 365 Business Voice'
        'MICROSOFT_REMOTE_ASSIST' = 'Dynamics 365 Remote Assist'
        'COMMUNICATIONS_DYN365_FRAUDPROTECTION_MGR' = 'Dynamics 365 Fraud Protection'
        'PBI_PREMIUM_P1_ADDON' = 'Power BI Premium P1'
        'POWER_PAGES_INTERNAL_USER' = 'Power Pages Internal User'
    }
    
    $mapping = @{}
    
    try {
        $skus = Get-MgSubscribedSku -All -ErrorAction Stop
        
        foreach ($sku in $skus) {
            $skuPartNumber = $sku.SkuPartNumber
            
            # Try to get friendly name from our mapping, otherwise use the part number
            $friendlyName = if ($skuFriendlyNames.ContainsKey($skuPartNumber)) {
                $skuFriendlyNames[$skuPartNumber]
            } else {
                # Fallback: make the part number more readable
                $skuPartNumber -replace '_', ' '
            }
            
            if (-not $mapping.ContainsKey($sku.SkuId)) {
                $mapping[$sku.SkuId] = @{
                    Name = $friendlyName
                    PartNumber = $skuPartNumber
                    SKU = $sku
                }
            }
        }
        
        Write-Host "Successfully mapped $($mapping.Count) license SKUs to friendly names" -ForegroundColor Green
        
    } catch {
        Write-Warning "Could not retrieve license SKUs: $_"
    }
    
    $script:LicenseMappingCache = $mapping
    return $mapping
}

function Get-UserContactInfo {
    param($User)
    
    try {
        return @{
            BusinessPhones = ($User.BusinessPhones -join '; ')
            MobilePhone = $User.MobilePhone
            FaxNumber = $User.FaxNumber
            StreetAddress = $User.StreetAddress
            City = $User.City
            State = $User.State
            PostalCode = $User.PostalCode
            Country = $User.Country
            UsageLocation = $User.UsageLocation
            PreferredLanguage = $User.PreferredLanguage
        }
    } catch {
        return @{
            BusinessPhones = 'N/A'
            MobilePhone = 'N/A'
        }
    }
}

function Get-UserEmployeeInfo {
    param($User)
    
    try {
        return @{
            EmployeeId = $User.EmployeeId
            EmployeeHireDate = $User.EmployeeHireDate
            EmployeeType = $User.EmployeeType
            CompanyName = $User.CompanyName
            Division = $User.AdditionalProperties.division
            CostCenter = $User.AdditionalProperties.costCenter
        }
    } catch {
        return @{
            EmployeeId = 'N/A'
            EmployeeType = 'N/A'
        }
    }
}

function Get-UserMFAStatus {
    param($UserId)
    
    try {
        $authMethods = Get-MgUserAuthenticationMethod -UserId $UserId -ErrorAction SilentlyContinue
        
        $mfaDetails = @{
            MFAEnabled = $false
            MFAMethods = @()
            MFAMethodCount = 0
            PhoneAuthEnabled = $false
            EmailAuthEnabled = $false
            FIDOKeyEnabled = $false
            AuthenticatorAppEnabled = $false
            WindowsHelloEnabled = $false
            SoftwareOathEnabled = $false
        }
        
        foreach ($method in $authMethods) {
            $mfaDetails.MFAMethodCount++
            
            switch ($method.AdditionalProperties.'@odata.type') {
                '#microsoft.graph.phoneAuthenticationMethod' {
                    $mfaDetails.MFAEnabled = $true
                    $mfaDetails.PhoneAuthEnabled = $true
                    $mfaDetails.MFAMethods += 'Phone'
                }
                '#microsoft.graph.emailAuthenticationMethod' {
                    $mfaDetails.EmailAuthEnabled = $true
                    $mfaDetails.MFAMethods += 'Email'
                }
                '#microsoft.graph.fido2AuthenticationMethod' {
                    $mfaDetails.MFAEnabled = $true
                    $mfaDetails.FIDOKeyEnabled = $true
                    $mfaDetails.MFAMethods += 'FIDO2 Key'
                }
                '#microsoft.graph.microsoftAuthenticatorAuthenticationMethod' {
                    $mfaDetails.MFAEnabled = $true
                    $mfaDetails.AuthenticatorAppEnabled = $true
                    $mfaDetails.MFAMethods += 'Authenticator App'
                }
                '#microsoft.graph.windowsHelloForBusinessAuthenticationMethod' {
                    $mfaDetails.MFAEnabled = $true
                    $mfaDetails.WindowsHelloEnabled = $true
                    $mfaDetails.MFAMethods += 'Windows Hello'
                }
                '#microsoft.graph.softwareOathAuthenticationMethod' {
                    $mfaDetails.MFAEnabled = $true
                    $mfaDetails.SoftwareOathEnabled = $true
                    $mfaDetails.MFAMethods += 'Software Token'
                }
            }
        }
        
        $mfaDetails.MFAMethods = $mfaDetails.MFAMethods -join ', '
        return $mfaDetails
        
    } catch {
        Write-Warning "Could not retrieve MFA status for user $UserId : $_"
        return @{
            MFAEnabled = 'Error'
            MFAMethods = 'Error'
        }
    }
}

function Get-UserMFAPhoneNumbers {
    param($UserId)
    
    try {
        $phoneNumbers = @()
        $emailAddresses = @()
        
        # Get phone auth methods
        try {
            $phoneMethods = Get-MgUserAuthenticationPhoneMethod -UserId $UserId -ErrorAction SilentlyContinue
            foreach ($phone in $phoneMethods) {
                if ($phone.PhoneNumber) {
                    $phoneNumbers += "$($phone.PhoneType): $($phone.PhoneNumber)"
                }
            }
        } catch {
            Write-Verbose "Could not retrieve phone methods for $UserId"
        }
        
        # Get email auth methods
        try {
            $emailMethods = Get-MgUserAuthenticationEmailMethod -UserId $UserId -ErrorAction SilentlyContinue
            foreach ($email in $emailMethods) {
                if ($email.EmailAddress) {
                    $emailAddresses += $email.EmailAddress
                }
            }
        } catch {
            Write-Verbose "Could not retrieve email methods for $UserId"
        }
        
        return @{
            MFAPhoneNumbers = if ($phoneNumbers.Count -gt 0) { ($phoneNumbers -join '; ') } else { 'None' }
            MFAEmailAddresses = if ($emailAddresses.Count -gt 0) { ($emailAddresses -join '; ') } else { 'None' }
        }
        
    } catch {
        return @{
            MFAPhoneNumbers = 'Error'
            MFAEmailAddresses = 'Error'
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
                ManagerId = $manager.Id
            }
        }
    } catch {
        Write-Verbose "No manager found for user $UserId"
    }
    
    return @{
        ManagerName = 'N/A'
        ManagerEmail = 'N/A'
        ManagerUPN = 'N/A'
        ManagerId = 'N/A'
    }
}

function Get-UserDirectReports {
    param($UserId)
    
    if ($script:DirectReportsCache.ContainsKey($UserId)) {
        return $script:DirectReportsCache[$UserId]
    }
    
    try {
        $directReports = Get-MgUserDirectReport -UserId $UserId -All -ErrorAction SilentlyContinue
        
        $reportNames = @()
        foreach ($report in $directReports) {
            if ($report.AdditionalProperties.displayName) {
                $reportNames += $report.AdditionalProperties.displayName
            }
        }
        
        $result = @{
            DirectReportCount = $reportNames.Count
            DirectReports = ($reportNames -join '; ')
        }
        
        $script:DirectReportsCache[$UserId] = $result
        return $result
        
    } catch {
        return @{
            DirectReportCount = 0
            DirectReports = 'N/A'
        }
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
        $distributionGroups = @()
        
        foreach ($group in $groups) {
            if ($group.AdditionalProperties.'@odata.type' -eq '#microsoft.graph.group') {
                $groupName = $group.AdditionalProperties.displayName
                $directGroups += $groupName
                
                if ($group.AdditionalProperties.groupTypes -contains 'Unified') {
                    $m365Groups += $groupName
                }
                if ($group.AdditionalProperties.groupTypes -contains 'DynamicMembership') {
                    $dynamicGroups += $groupName
                }
                if ($group.AdditionalProperties.securityEnabled) {
                    $securityGroups += $groupName
                }
                if ($group.AdditionalProperties.mailEnabled -and -not ($group.AdditionalProperties.groupTypes -contains 'Unified')) {
                    $distributionGroups += $groupName
                }
            }
        }
        
        return @{
            TotalGroups = $directGroups.Count
            DirectGroups = ($directGroups -join '; ')
            SecurityGroups = ($securityGroups -join '; ')
            M365Groups = ($m365Groups -join '; ')
            DynamicGroups = ($dynamicGroups -join '; ')
            DistributionGroups = ($distributionGroups -join '; ')
        }
        
    } catch {
        Write-Warning "Could not retrieve group memberships for user $UserId : $_"
        return @{
            TotalGroups = 'Error'
            DirectGroups = 'Error'
        }
    }
}

function Get-UserAdminUnits {
    param($UserId)
    
    try {
        $adminUnits = Get-MgUserMemberOf -UserId $UserId -All -ErrorAction SilentlyContinue | 
            Where-Object { $_.AdditionalProperties.'@odata.type' -eq '#microsoft.graph.administrativeUnit' }
        
        $auNames = @()
        foreach ($au in $adminUnits) {
            if ($au.AdditionalProperties.displayName) {
                $auNames += $au.AdditionalProperties.displayName
            }
        }
        
        return @{
            AdminUnitCount = $auNames.Count
            AdminUnits = ($auNames -join '; ')
        }
        
    } catch {
        Write-Warning "Could not retrieve admin units for user $UserId : $_"
        return @{
            AdminUnitCount = 0
            AdminUnits = 'Error'
        }
    }
}

function Get-UserLicenses {
    param(
        $User,
        [hashtable]$LicenseMapping,
        [bool]$IncludeServicePlans = $false
    )
    
    try {
        $licenses = $User.AssignedLicenses
        $licenseDetails = @()
        $assignmentPaths = @()
        $disabledPlans = @()
        
        foreach ($license in $licenses) {
            $skuData = $LicenseMapping[$license.SkuId]
            
            if ($skuData) {
                $licenseDetails += $skuData.Name
                
                try {
                    $licenseAssignment = Get-MgUserLicenseDetail -UserId $User.Id -ErrorAction SilentlyContinue | 
                        Where-Object { $_.SkuId -eq $license.SkuId }
                    
                    if ($licenseAssignment) {
                        $assignmentPath = if ($licenseAssignment.AssignedByGroup) { 
                            "Group: $($licenseAssignment.AssignedByGroup)" 
                        } else { 
                            "Direct" 
                        }
                        $assignmentPaths += "$($skuData.Name) ($assignmentPath)"
                    }
                } catch {
                    $assignmentPaths += "$($skuData.Name) (Unknown)"
                }
                
                if ($IncludeServicePlans -and $license.DisabledPlans.Count -gt 0) {
                    $sku = $skuData.SKU
                    foreach ($disabledPlanId in $license.DisabledPlans) {
                        $servicePlan = $sku.ServicePlans | Where-Object { $_.ServicePlanId -eq $disabledPlanId }
                        if ($servicePlan) {
                            $disabledPlans += "$($skuData.Name): $($servicePlan.ServicePlanName)"
                        }
                    }
                }
            } else {
                $licenseDetails += $license.SkuId
                $assignmentPaths += "$($license.SkuId) (Unknown)"
            }
        }
        
        # Get service provisioning errors
        $provisioningErrors = @()
        if ($User.ServiceProvisioningErrors -and $User.ServiceProvisioningErrors.Count -gt 0) {
            foreach ($error in $User.ServiceProvisioningErrors) {
                $provisioningErrors += "$($error.ServiceInstance): $($error.ErrorDetail)"
            }
        }
        
        return @{
            LicenseCount = $licenseDetails.Count
            Licenses = ($licenseDetails -join '; ')
            AssignmentPaths = ($assignmentPaths -join '; ')
            DisabledServicePlans = if ($disabledPlans.Count -gt 0) { ($disabledPlans -join '; ') } else { 'None' }
            ServiceProvisioningErrors = if ($provisioningErrors.Count -gt 0) { ($provisioningErrors -join '; ') } else { 'None' }
        }
        
    } catch {
        Write-Warning "Could not retrieve licenses for user $($User.Id) : $_"
        return @{
            LicenseCount = 0
            Licenses = 'Error'
        }
    }
}

function Get-UserMailboxType {
    param($User)
    
    try {
        $mailboxType = "User Mailbox"
        $isSharedMailbox = $false
        
        $isDisabled = -not $User.AccountEnabled
        $hasLicenses = ($User.AssignedLicenses.Count -gt 0)
        $hasMailbox = -not [string]::IsNullOrEmpty($User.Mail)
        
        # Check if resource account
        if ($User.AdditionalProperties.isResourceAccount -eq $true) {
            $mailboxType = "Resource Account"
        }
        elseif ($hasMailbox -and $isDisabled -and -not $hasLicenses) {
            $mailboxType = "Shared Mailbox (Likely)"
            $isSharedMailbox = $true
        }
        elseif ($User.AdditionalProperties.resourceType) {
            $resourceType = $User.AdditionalProperties.resourceType
            if ($resourceType -eq 'Room') {
                $mailboxType = "Room Mailbox"
            } elseif ($resourceType -eq 'Equipment') {
                $mailboxType = "Equipment Mailbox"
            }
        }
        elseif ($User.UserType -eq 'Guest') {
            $mailboxType = "Guest"
        }
        
        return @{
            MailboxType = $mailboxType
            IsSharedMailbox = $isSharedMailbox
            MailNickname = $User.MailNickname
        }
        
    } catch {
        return @{
            MailboxType = "Unknown"
            IsSharedMailbox = $false
            MailNickname = 'N/A'
        }
    }
}

function Get-UserDeviceInfo {
    param($UserId)
    
    try {
        $registeredDevices = Get-MgUserRegisteredDevice -UserId $UserId -All -ErrorAction SilentlyContinue
        $registeredDeviceList = @()
        
        foreach ($device in $registeredDevices) {
            if ($device.AdditionalProperties.displayName) {
                $registeredDeviceList += $device.AdditionalProperties.displayName
            }
        }
        
        $ownedDevices = Get-MgUserOwnedDevice -UserId $UserId -All -ErrorAction SilentlyContinue
        $ownedDeviceList = @()
        
        foreach ($device in $ownedDevices) {
            if ($device.AdditionalProperties.displayName) {
                $ownedDeviceList += $device.AdditionalProperties.displayName
            }
        }
        
        return @{
            RegisteredDeviceCount = $registeredDeviceList.Count
            RegisteredDevices = ($registeredDeviceList -join '; ')
            OwnedDeviceCount = $ownedDeviceList.Count
            OwnedDevices = ($ownedDeviceList -join '; ')
        }
        
    } catch {
        return @{
            RegisteredDeviceCount = 0
            RegisteredDevices = 'Error'
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
            LastSuccessfulSignIn = if ($User.SignInActivity.LastSuccessfulSignInDateTime) {
                $User.SignInActivity.LastSuccessfulSignInDateTime
            } else { 'Never' }
        }
    } catch {
        return @{
            LastSignIn = 'N/A'
        }
    }
}

function Get-UserSecurityInfo {
    param($User)
    
    try {
        return @{
            PasswordNeverExpires = $User.PasswordPolicies -contains 'DisablePasswordExpiration'
            PasswordLastChanged = if ($User.LastPasswordChangeDateTime) { 
                $User.LastPasswordChangeDateTime 
            } else { 'Unknown' }
            AccountLocked = $User.AccountEnabled -eq $false
            ShowInAddressList = if ($null -ne $User.ShowInAddressList) { 
                $User.ShowInAddressList 
            } else { $true }
            ExternalUserState = $User.ExternalUserState
            ExternalUserStateChangeDateTime = $User.ExternalUserStateChangeDateTime
            RefreshTokensValidFrom = $User.RefreshTokensValidFromDateTime
            SecurityIdentifier = $User.SecurityIdentifier
        }
    } catch {
        return @{
            PasswordNeverExpires = 'Unknown'
        }
    }
}

function Get-UserGuestInfo {
    param($User)
    
    try {
        if ($User.UserType -eq 'Guest') {
            return @{
                IsGuest = $true
                GuestInvitationStatus = $User.ExternalUserState
                GuestInvitedDateTime = $User.CreatedDateTime
                ExternalEmailAddress = $User.Mail
                AgeGroup = $User.AgeGroup
                ConsentProvidedForMinor = $User.ConsentProvidedForMinor
                LegalAgeGroupClassification = $User.LegalAgeGroupClassification
            }
        } else {
            return @{
                IsGuest = $false
                GuestInvitationStatus = 'N/A'
                AgeGroup = $User.AgeGroup
                ConsentProvidedForMinor = $User.ConsentProvidedForMinor
                LegalAgeGroupClassification = $User.LegalAgeGroupClassification
            }
        }
    } catch {
        return @{
            IsGuest = $false
        }
    }
}

function Get-UserIdentityInfo {
    param($User)
    
    try {
        # Parse identities
        $identityProviders = @()
        if ($User.Identities) {
            foreach ($identity in $User.Identities) {
                $identityProviders += "$($identity.SignInType): $($identity.Issuer)"
            }
        }
        
        return @{
            Identities = ($identityProviders -join '; ')
            IMAddresses = ($User.ImAddresses -join '; ')
            OtherMails = ($User.OtherMails -join '; ')
            CreationType = $User.CreationType
        }
    } catch {
        return @{
            Identities = 'N/A'
        }
    }
}

function Get-UserOnPremisesInfo {
    param($User)
    
    try {
        # Get on-premises extension attributes
        $onPremExtensions = @()
        for ($i = 1; $i -le 15; $i++) {
            $attrName = "onPremisesExtensionAttributes.extensionAttribute$i"
            if ($User.AdditionalProperties.onPremisesExtensionAttributes) {
                $value = $User.AdditionalProperties.onPremisesExtensionAttributes."extensionAttribute$i"
                if ($value) {
                    $onPremExtensions += "Attr$i=$value"
                }
            }
        }
        
        # Get provisioning errors
        $provisioningErrors = @()
        if ($User.OnPremisesProvisioningErrors -and $User.OnPremisesProvisioningErrors.Count -gt 0) {
            foreach ($error in $User.OnPremisesProvisioningErrors) {
                $provisioningErrors += $error.Value
            }
        }
        
        return @{
            OnPremisesDistinguishedName = $User.OnPremisesDistinguishedName
            OnPremisesDomainName = $User.OnPremisesDomainName
            OnPremisesSamAccountName = $User.OnPremisesSamAccountName
            OnPremisesSecurityIdentifier = $User.OnPremisesSecurityIdentifier
            OnPremisesUserPrincipalName = $User.OnPremisesUserPrincipalName
            OnPremisesImmutableId = $User.OnPremisesImmutableId
            OnPremisesLastSyncDateTime = $User.OnPremisesLastSyncDateTime
            OnPremisesExtensionAttributes = if ($onPremExtensions.Count -gt 0) { 
                ($onPremExtensions -join '; ') 
            } else { 'None' }
            OnPremisesProvisioningErrors = if ($provisioningErrors.Count -gt 0) { 
                ($provisioningErrors -join '; ') 
            } else { 'None' }
        }
    } catch {
        return @{
            OnPremisesDistinguishedName = 'Error'
        }
    }
}

function Get-UserExtensionAttributes {
    param($User)
    
    try {
        $extensions = @{}
        
        for ($i = 1; $i -le 15; $i++) {
            $attrName = "extensionAttribute$i"
            if ($User.AdditionalProperties.ContainsKey($attrName)) {
                $extensions["ExtensionAttribute$i"] = $User.AdditionalProperties[$attrName]
            } else {
                $extensions["ExtensionAttribute$i"] = ''
            }
        }
        
        return $extensions
        
    } catch {
        return @{
            ExtensionAttribute1 = 'Error'
        }
    }
}

function Get-UserAppPermissions {
    param($UserId)
    
    try {
        $grants = Get-MgUserOauth2PermissionGrant -UserId $UserId -All -ErrorAction SilentlyContinue
        
        $appList = @()
        $scopeList = @()
        $riskApps = @()
        
        foreach ($grant in $grants) {
            # Get app name
            try {
                $sp = Get-MgServicePrincipal -ServicePrincipalId $grant.ClientId -ErrorAction SilentlyContinue
                if ($sp) {
                    $appList += $sp.DisplayName
                    
                    # Check for risky permissions
                    if ($grant.Scope) {
                        $scopes = $grant.Scope -split ' '
                        $scopeList += "$($sp.DisplayName): $($grant.Scope)"
                        
                        # Flag risky permissions
                        $riskyScopes = @('Mail.ReadWrite', 'Files.ReadWrite.All', 'Directory.ReadWrite.All', 
                                        'User.ReadWrite.All', 'Mail.Send', 'Calendars.ReadWrite')
                        foreach ($scope in $scopes) {
                            if ($scope -in $riskyScopes) {
                                $riskApps += "$($sp.DisplayName) ($scope)"
                            }
                        }
                    }
                }
            } catch {
                $appList += $grant.ClientId
            }
        }
        
        return @{
            ConsentedAppCount = $appList.Count
            ConsentedApps = if ($appList.Count -gt 0) { ($appList -join '; ') } else { 'None' }
            AppPermissions = if ($scopeList.Count -gt 0) { ($scopeList -join ' | ') } else { 'None' }
            RiskyAppPermissions = if ($riskApps.Count -gt 0) { ($riskApps -join '; ') } else { 'None' }
        }
        
    } catch {
        return @{
            ConsentedAppCount = 0
            ConsentedApps = 'Error'
        }
    }
}

function Get-UserProfilePhoto {
    param($UserId)
    
    try {
        $photo = Get-MgUserPhoto -UserId $UserId -ErrorAction SilentlyContinue
        return @{
            HasProfilePhoto = $null -ne $photo
        }
    } catch {
        return @{
            HasProfilePhoto = $false
        }
    }
}

function Get-UserOneDriveInfo {
    param($UserId)
    
    try {
        $drive = Get-MgUserDrive -UserId $UserId -ErrorAction SilentlyContinue
        
        if ($drive) {
            $quotaGB = [math]::Round($drive.Quota.Total / 1GB, 2)
            $usedGB = [math]::Round($drive.Quota.Used / 1GB, 2)
            $percentUsed = if ($drive.Quota.Total -gt 0) { 
                [math]::Round(($drive.Quota.Used / $drive.Quota.Total) * 100, 2) 
            } else { 0 }
            
            return @{
                OneDriveQuotaGB = $quotaGB
                OneDriveUsedGB = $usedGB
                OneDrivePercentUsed = $percentUsed
            }
        } else {
            return @{
                OneDriveQuotaGB = 'N/A'
                OneDriveUsedGB = 'N/A'
                OneDrivePercentUsed = 'N/A'
            }
        }
        
    } catch {
        return @{
            OneDriveQuotaGB = 'Error'
        }
    }
}

function Get-TenantName {
    try {
        $context = Get-MgContext
        if ($context) {
            $org = Get-MgOrganization -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($org -and $org.DisplayName) {
                $tenantName = $org.DisplayName -replace '[\\/:*?"<>|]', '_'
                return $tenantName
            }
            
            if ($context.TenantId) {
                return $context.TenantId
            }
        }
        
        return "Unknown"
        
    } catch {
        return "Unknown"
    }
}

#endregion

#region Main Script

Write-Host "`n╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║     ULTIMATE Microsoft 365 User Report Export (v3.0)           ║" -ForegroundColor Cyan
Write-Host "║            130+ Attributes Available                           ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

# Show enabled optional features
$optionalFeatures = @()
if ($IncludeAdminUnits) { $optionalFeatures += "Admin Units" }
if ($IncludeAppPermissions) { $optionalFeatures += "App Permissions" }
if ($IncludeMFAPhoneNumbers) { $optionalFeatures += "MFA Phone Numbers" }
if ($IncludeProfilePhoto) { $optionalFeatures += "Profile Photos" }
if ($IncludeOneDrive) { $optionalFeatures += "OneDrive Usage" }
if ($IncludeServicePlans) { $optionalFeatures += "Service Plans" }

if ($optionalFeatures.Count -gt 0) {
    Write-Host "Optional Features Enabled: $($optionalFeatures -join ', ')" -ForegroundColor Yellow
    Write-Host "Note: Optional features add API calls and increase processing time`n" -ForegroundColor Yellow
}

# Connect to Microsoft Graph
Connect-MgGraphIfNeeded -UseDeviceAuth $UseDeviceCode

# Initialize license mapping
Write-Host "`nInitializing license name mappings..." -ForegroundColor Cyan
$licenseMapping = Initialize-LicenseMapping

# Generate default output path
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $tenantName = Get-TenantName
    $dateStamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $OutputPath = ".\${dateStamp}_${tenantName}_UltimateUserReport"
}

Write-Host "Output Format: $OutputFormat" -ForegroundColor Cyan
Write-Host "Output Path: $OutputPath.$($OutputFormat.ToLower())" -ForegroundColor Cyan

# Determine attributes to export
$attributesToExport = Get-AttributesToExport -AttributeParam $Attributes
Write-Host "`nExporting attribute categories: $($attributesToExport -join ', ')" -ForegroundColor Cyan

# Get users with ALL properties
Write-Host "`nRetrieving users..." -ForegroundColor Yellow

try {
    $propertyList = @(
        'Id', 'DisplayName', 'UserPrincipalName', 'Mail', 'MailNickname',
        'GivenName', 'Surname', 'JobTitle', 'Department', 
        'OfficeLocation', 'AccountEnabled', 'CreatedDateTime',
        'AssignedLicenses', 'SignInActivity', 'ProxyAddresses',
        'UserType', 'OnPremisesSyncEnabled',
        'BusinessPhones', 'MobilePhone', 'FaxNumber',
        'StreetAddress', 'City', 'State', 'PostalCode', 'Country',
        'UsageLocation', 'PreferredLanguage',
        'EmployeeId', 'EmployeeHireDate', 'EmployeeType', 'CompanyName',
        'PasswordPolicies', 'LastPasswordChangeDateTime',
        'ShowInAddressList', 'ExternalUserState', 'ExternalUserStateChangeDateTime',
        'RefreshTokensValidFromDateTime', 'SecurityIdentifier',
        'Identities', 'ImAddresses', 'OtherMails', 'CreationType',
        'OnPremisesDistinguishedName', 'OnPremisesDomainName', 
        'OnPremisesSamAccountName', 'OnPremisesSecurityIdentifier',
        'OnPremisesUserPrincipalName', 'OnPremisesImmutableId',
        'OnPremisesLastSyncDateTime', 'OnPremisesProvisioningErrors',
        'AgeGroup', 'ConsentProvidedForMinor', 'LegalAgeGroupClassification',
        'ServiceProvisioningErrors'
    )
    
    $getUserParams = @{
        All = $true
        Property = $propertyList
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
$startTime = Get-Date

foreach ($user in $users) {
    $counter++
    $percentComplete = ($counter / $users.Count) * 100
    $elapsed = (Get-Date) - $startTime
    $estimatedTotal = if ($counter -gt 0) { $elapsed.TotalSeconds / $counter * $users.Count } else { 0 }
    $remaining = $estimatedTotal - $elapsed.TotalSeconds
    
    Write-Progress -Activity "Processing users" `
        -Status "Processing $($user.DisplayName) ($counter of $($users.Count))" `
        -PercentComplete $percentComplete `
        -SecondsRemaining $remaining
    
    $userReport = [PSCustomObject]@{}
    
    # Basic attributes
    if ('Basic' -in $attributesToExport) {
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
        
        $aliases = $user.ProxyAddresses | Where-Object { $_ -like 'smtp:*' } | ForEach-Object { $_.Replace('smtp:', '') }
        $userReport | Add-Member -NotePropertyName 'Aliases' -NotePropertyValue ($aliases -join '; ')
    }
    
    # Contact
    if ('Contact' -in $attributesToExport) {
        $contactInfo = Get-UserContactInfo -User $user
        foreach ($key in $contactInfo.Keys) {
            $userReport | Add-Member -NotePropertyName $key -NotePropertyValue $contactInfo[$key]
        }
    }
    
    # Employee
    if ('Employee' -in $attributesToExport) {
        $employeeInfo = Get-UserEmployeeInfo -User $user
        foreach ($key in $employeeInfo.Keys) {
            $userReport | Add-Member -NotePropertyName $key -NotePropertyValue $employeeInfo[$key]
        }
    }
    
    # Mailbox Type
    if ('MailboxType' -in $attributesToExport) {
        $mailboxInfo = Get-UserMailboxType -User $user
        foreach ($key in $mailboxInfo.Keys) {
            $userReport | Add-Member -NotePropertyName $key -NotePropertyValue $mailboxInfo[$key]
        }
    }
    
    # MFA Status
    if ('MFA' -in $attributesToExport) {
        $mfaStatus = Get-UserMFAStatus -UserId $user.Id
        foreach ($key in $mfaStatus.Keys) {
            $userReport | Add-Member -NotePropertyName $key -NotePropertyValue $mfaStatus[$key]
        }
        
        # Optional: Detailed MFA phone numbers/emails
        if ($IncludeMFAPhoneNumbers) {
            $mfaDetails = Get-UserMFAPhoneNumbers -UserId $user.Id
            foreach ($key in $mfaDetails.Keys) {
                $userReport | Add-Member -NotePropertyName $key -NotePropertyValue $mfaDetails[$key]
            }
        }
    }
    
    # Manager
    if ('Manager' -in $attributesToExport) {
        $manager = Get-UserManager -UserId $user.Id
        foreach ($key in $manager.Keys) {
            $userReport | Add-Member -NotePropertyName $key -NotePropertyValue $manager[$key]
        }
    }
    
    # Direct Reports
    if ('DirectReports' -in $attributesToExport) {
        $directReports = Get-UserDirectReports -UserId $user.Id
        foreach ($key in $directReports.Keys) {
            $userReport | Add-Member -NotePropertyName $key -NotePropertyValue $directReports[$key]
        }
    }
    
    # Groups
    if ('Groups' -in $attributesToExport) {
        $groups = Get-UserGroupMemberships -UserId $user.Id
        foreach ($key in $groups.Keys) {
            $userReport | Add-Member -NotePropertyName $key -NotePropertyValue $groups[$key]
        }
        
        # Optional: Admin Units
        if ($IncludeAdminUnits) {
            $adminUnits = Get-UserAdminUnits -UserId $user.Id
            foreach ($key in $adminUnits.Keys) {
                $userReport | Add-Member -NotePropertyName $key -NotePropertyValue $adminUnits[$key]
            }
        }
    }
    
    # Licenses
    if ('Licenses' -in $attributesToExport) {
        $licenses = Get-UserLicenses -User $user -LicenseMapping $licenseMapping -IncludeServicePlans $IncludeServicePlans
        foreach ($key in $licenses.Keys) {
            $userReport | Add-Member -NotePropertyName $key -NotePropertyValue $licenses[$key]
        }
    }
    
    # Sign-in Activity
    if ('SignInActivity' -in $attributesToExport) {
        $signIn = Get-UserSignInActivity -User $user
        foreach ($key in $signIn.Keys) {
            $userReport | Add-Member -NotePropertyName $key -NotePropertyValue $signIn[$key]
        }
    }
    
    # Security
    if ('Security' -in $attributesToExport) {
        $security = Get-UserSecurityInfo -User $user
        foreach ($key in $security.Keys) {
            $userReport | Add-Member -NotePropertyName $key -NotePropertyValue $security[$key]
        }
        
        # Optional: App Permissions
        if ($IncludeAppPermissions) {
            $appPerms = Get-UserAppPermissions -UserId $user.Id
            foreach ($key in $appPerms.Keys) {
                $userReport | Add-Member -NotePropertyName $key -NotePropertyValue $appPerms[$key]
            }
        }
    }
    
    # Devices
    if ('Devices' -in $attributesToExport) {
        $devices = Get-UserDeviceInfo -UserId $user.Id
        foreach ($key in $devices.Keys) {
            $userReport | Add-Member -NotePropertyName $key -NotePropertyValue $devices[$key]
        }
        
        # Optional: Profile Photo
        if ($IncludeProfilePhoto) {
            $photo = Get-UserProfilePhoto -UserId $user.Id
            foreach ($key in $photo.Keys) {
                $userReport | Add-Member -NotePropertyName $key -NotePropertyValue $photo[$key]
            }
        }
        
        # Optional: OneDrive
        if ($IncludeOneDrive) {
            $oneDrive = Get-UserOneDriveInfo -UserId $user.Id
            foreach ($key in $oneDrive.Keys) {
                $userReport | Add-Member -NotePropertyName $key -NotePropertyValue $oneDrive[$key]
            }
        }
    }
    
    # Guest
    if ('Guest' -in $attributesToExport) {
        $guestInfo = Get-UserGuestInfo -User $user
        foreach ($key in $guestInfo.Keys) {
            $userReport | Add-Member -NotePropertyName $key -NotePropertyValue $guestInfo[$key]
        }
    }
    
    # Identity
    if ('Identity' -in $attributesToExport) {
        $identityInfo = Get-UserIdentityInfo -User $user
        foreach ($key in $identityInfo.Keys) {
            $userReport | Add-Member -NotePropertyName $key -NotePropertyValue $identityInfo[$key]
        }
    }
    
    # OnPremises
    if ('OnPremises' -in $attributesToExport) {
        $onPremInfo = Get-UserOnPremisesInfo -User $user
        foreach ($key in $onPremInfo.Keys) {
            $userReport | Add-Member -NotePropertyName $key -NotePropertyValue $onPremInfo[$key]
        }
    }
    
    # Extensions
    if ('Extensions' -in $attributesToExport) {
        $extensions = Get-UserExtensionAttributes -User $user
        foreach ($key in $extensions.Keys) {
            $userReport | Add-Member -NotePropertyName $key -NotePropertyValue $extensions[$key]
        }
    }
    
    $exportData += $userReport
}

Write-Progress -Activity "Processing users" -Completed

# Filter to requested fields if individual fields were specified
if ($script:FilterToRequestedFields -and $script:RequestedFields) {
    Write-Host "`nFiltering to requested fields: $($script:RequestedFields -join ', ')" -ForegroundColor Cyan
    
    # Map some common aliases
    $fieldAliases = @{
        'LastLogin' = 'LastSignIn'
        'LastSignInDateTime' = 'LastSignIn'
        'Title' = 'JobTitle'
        'Office' = 'OfficeLocation'
    }
    
    # Build list of fields to select
    $fieldsToSelect = @()
    foreach ($field in $script:RequestedFields) {
        # Check if there's an alias
        if ($fieldAliases.ContainsKey($field)) {
            $fieldsToSelect += $fieldAliases[$field]
        } else {
            $fieldsToSelect += $field
        }
    }
    
    # Filter the export data
    try {
        $exportData = $exportData | Select-Object $fieldsToSelect
    } catch {
        Write-Warning "Could not filter to specific fields. Some requested fields may not exist. Exporting all fields from requested categories."
    }
}

# Export data
Write-Host "`nExporting data..." -ForegroundColor Yellow

$expectedExtension = ".$($OutputFormat.ToLower())"
if ($OutputPath.EndsWith($expectedExtension)) {
    $outputFile = $OutputPath
} else {
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
    
    Write-Host "`n╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "║              Export Completed Successfully!                    ║" -ForegroundColor Green
    Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Green
    
    Write-Host "`nFile saved to: $outputFile" -ForegroundColor Green
    Write-Host "Total users exported: $($exportData.Count)" -ForegroundColor Green
    Write-Host "Total columns: $($exportData[0].PSObject.Properties.Name.Count)" -ForegroundColor Green
    
    # Calculate processing time
    $totalTime = (Get-Date) - $startTime
    Write-Host "Processing time: $($totalTime.ToString('mm\:ss'))" -ForegroundColor Cyan
    
    # Show statistics
    Write-Host "`n╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║                    Summary Statistics                          ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    
    if ('MailboxType' -in $attributesToExport) {
        $sharedMailboxCount = ($exportData | Where-Object { $_.IsSharedMailbox -eq $true }).Count
        $guestCount = ($exportData | Where-Object { $_.UserType -eq 'Guest' }).Count
        Write-Host "`nMailbox Types:" -ForegroundColor Yellow
        Write-Host "  • Shared Mailboxes: $sharedMailboxCount" -ForegroundColor White
        Write-Host "  • Guest Users: $guestCount" -ForegroundColor White
    }
    
    if ('Licenses' -in $attributesToExport) {
        $licensedUsers = ($exportData | Where-Object { $_.LicenseCount -gt 0 }).Count
        $unlicensedUsers = ($exportData | Where-Object { $_.LicenseCount -eq 0 }).Count
        $usersWithErrors = ($exportData | Where-Object { $_.ServiceProvisioningErrors -ne 'None' }).Count
        Write-Host "`nLicensing:" -ForegroundColor Yellow
        Write-Host "  • Licensed Users: $licensedUsers" -ForegroundColor White
        Write-Host "  • Unlicensed Users: $unlicensedUsers" -ForegroundColor White
        if ($usersWithErrors -gt 0) {
            Write-Host "  • Users with Provisioning Errors: $usersWithErrors" -ForegroundColor Red
        }
    }
    
    if ('MFA' -in $attributesToExport) {
        $mfaEnabled = ($exportData | Where-Object { $_.MFAEnabled -eq $true }).Count
        $mfaDisabled = ($exportData | Where-Object { $_.MFAEnabled -eq $false }).Count
        Write-Host "`nMFA Status:" -ForegroundColor Yellow
        Write-Host "  • MFA Enabled: $mfaEnabled" -ForegroundColor White
        Write-Host "  • MFA Disabled: $mfaDisabled" -ForegroundColor White
    }
    
    if ('Security' -in $attributesToExport) {
        $passwordNeverExpires = ($exportData | Where-Object { $_.PasswordNeverExpires -eq $true }).Count
        Write-Host "`nSecurity:" -ForegroundColor Yellow
        Write-Host "  • Passwords Set to Never Expire: $passwordNeverExpires" -ForegroundColor White
        
        if ($IncludeAppPermissions) {
            $usersWithRiskyApps = ($exportData | Where-Object { $_.RiskyAppPermissions -ne 'None' }).Count
            if ($usersWithRiskyApps -gt 0) {
                Write-Host "  • Users with Risky App Permissions: $usersWithRiskyApps" -ForegroundColor Red
            }
        }
    }
    
    if ('DirectReports' -in $attributesToExport) {
        $managers = ($exportData | Where-Object { $_.DirectReportCount -gt 0 }).Count
        Write-Host "`nOrganization:" -ForegroundColor Yellow
        Write-Host "  • Users with Direct Reports: $managers" -ForegroundColor White
    }
    
    if ('OnPremises' -in $attributesToExport) {
        $syncedUsers = ($exportData | Where-Object { $_.OnPremisesSyncEnabled -eq $true }).Count
        $syncErrors = ($exportData | Where-Object { $_.OnPremisesProvisioningErrors -ne 'None' }).Count
        Write-Host "`nOn-Premises Sync:" -ForegroundColor Yellow
        Write-Host "  • Synced from On-Premises: $syncedUsers" -ForegroundColor White
        if ($syncErrors -gt 0) {
            Write-Host "  • Users with Sync Errors: $syncErrors" -ForegroundColor Red
        }
    }
    
} catch {
    Write-Error "Failed to export data: $_"
    exit 1
}

Write-Host "`n╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║            Report Generation Complete!                         ║" -ForegroundColor Green
Write-Host "╚════════════════════════════════════════════════════════════════╝`n" -ForegroundColor Green

#endregion