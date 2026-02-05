#Requires -Version 5.1
#Requires -Modules ExchangeOnlineManagement

<#
    .SYNOPSIS
        Configures Microsoft 365 tenant for Phished.io security awareness training.

    .DESCRIPTION
        Automates setup of transport rules, phishing simulation overrides, and 
        Phished.io partner API integration for security awareness training deployment.

    .PARAMETER PhishedAPIUsername
        Partner API username for Phished.io

    .PARAMETER PhishedAPIToken
        Partner API token (will prompt securely if not provided)

    .PARAMETER PhishedAPISecret
        Partner API secret (will prompt securely if not provided)

    .PARAMETER ClientEmail
        Email address for new client creation

    .PARAMETER ConfigPath
        Path to configuration JSON file (optional)

    .EXAMPLE
        .\New-PhishedSetup.ps1 -ClientEmail "phished+<client>@westspring-it.co.uk"

    .NOTES
        Author: Fergus Barker - WestSpring IT
        Version: 1.1.0
        Requires: Exchange Online Management PowerShell module
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$PhishedAPIUsername,

    [Parameter(Mandatory = $false)]
    [SecureString]$PhishedAPIToken,

    [Parameter(Mandatory = $false)]
    [SecureString]$PhishedAPISecret,

    [Parameter(Mandatory = $false)]
    [ValidatePattern('^[\w\.-]+@[\w\.-]+\.\w+$')]
    [string]$ClientEmail,

    [Parameter(Mandatory = $false)]
    [ValidateScript({Test-Path $_ -PathType Leaf})]
    [string]$ConfigPath,

    [switch]$SkipAdminCheck
)

#region Configuration
$script:Config = @{
    Version = "1.1.0"
    PhishedIPs = @(
        "143.55.236.227"
        "143.55.236.228"
        "143.55.236.247"
        "34.140.69.192"
        "34.22.133.124"
    )
    PhishedDomains = @(
        "psr.phished.io"
        "phished.io"
    )
    TransportRules = @(
        @{
            Name = "Phished - Bypass Junk Folder"
            HeaderName = "X-Forefront-Antispam-Report"
            HeaderValue = "SKV: SKI;"
        },
        @{
            Name = "Phished - Bypass Spam Folder"
            HeaderName = "X-MS-Exchange-Organization-BypassClutter"
            HeaderValue = "1"
        },
        @{
            Name = "Phished - ATP Safe Links Bypass"
            HeaderName = "X-MS-Exchange-Organization-SkipSafeLinksProcessing"
            HeaderValue = "1"
        },
        @{
            Name = "Phished - ATP Attachments Bypass"
            HeaderName = "X-MS-Exchange-Organization-SkipSafeAttachmentProcessing"
            HeaderValue = "1"
        }
    )
    APIEndpoint = "https://partners.phished.io/api"
    LogPath = Join-Path $env:TEMP "PhishedSetup-$(Get-Date -Format 'yyyy-MM-dd').log"
}

# Load custom config if provided
if ($ConfigPath) {
    $customConfig = Get-Content $ConfigPath | ConvertFrom-Json
    $script:Config = $customConfig
}
#endregion

#region Logging Functions
function Write-LogMessage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter()]
        [ValidateSet("Info", "Warning", "Error", "Success", "Debug")]
        [string]$Level = "Info",

        [Parameter()]
        [switch]$WriteToConsole
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    
    $consoleColors = @{
        Success = "Green"
        Info = "Cyan"
        Warning = "Yellow"
        Error = "Red"
        Debug = "Gray"
    }
    
    if ($WriteToConsole -or $VerbosePreference -eq 'Continue') {
        Write-Host $logEntry -ForegroundColor $consoleColors[$Level]
    }
    
    # Only log non-sensitive information
    if ($Message -notmatch "(token|secret|password|credential)") {
        Add-Content -Path $script:Config.LogPath -Value $logEntry -ErrorAction SilentlyContinue
    }
}
#endregion

#region Admin and Prerequisites
function Test-AdminPrivileges {
    [CmdletBinding()]
    param()

    if ($SkipAdminCheck) {
        Write-LogMessage "Admin check skipped by parameter" -Level Warning -WriteToConsole
        return $true
    }

    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal(
        [Security.Principal.WindowsIdentity]::GetCurrent()
    )
    
    $isAdmin = $currentPrincipal.IsInRole(
        [Security.Principal.WindowsBuiltinRole]::Administrator
    )

    if (-not $isAdmin) {
        Write-LogMessage "This script requires Administrator privileges" -Level Error -WriteToConsole
        
        if ($PSCmdlet.ShouldProcess("PowerShell", "Restart as Administrator")) {
            Start-Process powershell.exe -Verb RunAs -ArgumentList "-File `"$PSCommandPath`""
            exit
        }
        return $false
    }

    Write-LogMessage "Running with Administrator privileges" -Level Success -WriteToConsole
    return $true
}

function Initialize-RequiredModules {
    [CmdletBinding()]
    param()

    try {
        if (-not (Get-Module -Name ExchangeOnlineManagement -ListAvailable)) {
            Write-LogMessage "Installing ExchangeOnlineManagement module..." -Level Info -WriteToConsole
            
            if ($PSCmdlet.ShouldProcess("ExchangeOnlineManagement", "Install Module")) {
                Install-Module -Name ExchangeOnlineManagement -Force -AllowClobber -Scope CurrentUser
            }
        }

        Import-Module ExchangeOnlineManagement -ErrorAction Stop
        Write-LogMessage "ExchangeOnlineManagement module loaded" -Level Success -WriteToConsole

        # Verify critical cmdlets
        $requiredCmdlets = @(
            'Get-DkimSigningConfig'
            'Get-ExoPhishSimOverrideRule'
            'Get-TransportRule'
        )

        foreach ($cmdlet in $requiredCmdlets) {
            if (-not (Get-Command $cmdlet -ErrorAction SilentlyContinue)) {
                throw "Required cmdlet $cmdlet not found"
            }
        }

        return $true
    }
    catch {
        Write-LogMessage "Failed to initialize modules: $_" -Level Error -WriteToConsole
        return $false
    }
}

function Connect-ExchangeOnlineSession {
    [CmdletBinding()]
    param()

    try {
        $connectionState = Get-ConnectionInformation -ErrorAction SilentlyContinue | 
            Select-Object -First 1 -ExpandProperty State

        if ($connectionState -ne "Connected") {
            Write-LogMessage "Connecting to Exchange Online..." -Level Info -WriteToConsole
            
            if ($PSCmdlet.ShouldProcess("Exchange Online", "Connect")) {
                Connect-ExchangeOnline -ShowBanner:$false -ErrorAction Stop
                
                $defaultDomain = (Get-AcceptedDomain | Where-Object Default).DomainName
                Write-LogMessage "Connected to tenant: $defaultDomain" -Level Success -WriteToConsole
            }
        }
        else {
            $defaultDomain = (Get-AcceptedDomain | Where-Object Default).DomainName
            Write-LogMessage "Already connected to: $defaultDomain" -Level Info -WriteToConsole
        }

        return $true
    }
    catch {
        Write-LogMessage "Failed to connect to Exchange Online: $_" -Level Error -WriteToConsole
        return $false
    }
}
#endregion

#region Validation Functions
function Test-PhishedConfiguration {
    [CmdletBinding()]
    param()

    Write-LogMessage "Validating Phished configuration..." -Level Info -WriteToConsole

    # Check IP whitelisting
    $transportRules = Get-TransportRule
    $missingIPs = $script:Config.PhishedIPs | Where-Object {
        $ip = $_
        -not ($transportRules | Where-Object { $_.SenderIpRanges -contains $ip })
    }

    if ($missingIPs) {
        Write-LogMessage "Missing Phished IPs in transport rules: $($missingIPs -join ', ')" -Level Warning -WriteToConsole
    }
    else {
        Write-LogMessage "All Phished IPs are configured" -Level Success -WriteToConsole
    }

    # Check DKIM
    $dkimDisabled = Get-DkimSigningConfig | Where-Object { -not $_.Enabled }
    if ($dkimDisabled) {
        Write-LogMessage "DKIM not enabled for: $($dkimDisabled.Domain -join ', ')" -Level Warning -WriteToConsole
    }
    else {
        Write-LogMessage "DKIM properly configured" -Level Success -WriteToConsole
    }

    return @{
        MissingIPs = $missingIPs
        DKIMDisabled = $dkimDisabled
    }
}
#endregion

#region Phished Configuration Functions
function Set-PhishedDomainsAndIPs {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    try {
        Write-LogMessage "Configuring Phished domains and IPs..." -Level Info -WriteToConsole

        $existingRule = Get-ExoPhishSimOverrideRule -ErrorAction SilentlyContinue
        $existingPolicy = Get-PhishSimOverridePolicy -ErrorAction SilentlyContinue

        if ($existingRule) {
            Write-LogMessage "Updating existing rule: $($existingRule.Name)" -Level Info -WriteToConsole
            
            if ($PSCmdlet.ShouldProcess($existingRule.Name, "Update with Phished domains and IPs")) {
                $existingRule | Set-ExoPhishSimOverrideRule `
                    -AddDomains $script:Config.PhishedDomains `
                    -AddSenderIpRanges $script:Config.PhishedIPs
            }
        }
        elseif ($existingPolicy -and -not $existingRule) {
            Write-LogMessage "Creating override rule for existing policy" -Level Info -WriteToConsole
            
            if ($PSCmdlet.ShouldProcess("Phished", "Create new override rule")) {
                New-ExoPhishSimOverrideRule `
                    -Name 'Phished' `
                    -Policy $existingPolicy.Identity `
                    -Domains $script:Config.PhishedDomains `
                    -SenderIpRanges $script:Config.PhishedIPs `
                    -Comment 'Phished.io simulation bypass'
            }
        }
        else {
            Write-LogMessage "Creating new policy and rule" -Level Info -WriteToConsole
            
            if ($PSCmdlet.ShouldProcess("PhishingOverridePolicy", "Create policy and rule")) {
                New-PhishSimOverridePolicy -Name 'PhishingOverridePolicy'
                Start-Sleep -Seconds 5

                $newPolicy = Get-PhishSimOverridePolicy
                New-ExoPhishSimOverrideRule `
                    -Name 'Phished' `
                    -Policy $newPolicy.Identity `
                    -Domains $script:Config.PhishedDomains `
                    -SenderIpRanges $script:Config.PhishedIPs `
                    -Comment 'Phished.io simulation bypass'
            }
        }

        Write-LogMessage "Phished domains and IPs configured successfully" -Level Success -WriteToConsole
        return $true
    }
    catch {
        Write-LogMessage "Failed to configure domains and IPs: $_" -Level Error -WriteToConsole
        return $false
    }
}

function New-PhishedTransportRules {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$SecurityHeader
    )

    try {
        Write-LogMessage "Creating transport rules with header: $SecurityHeader" -Level Info -WriteToConsole

        foreach ($rule in $script:Config.TransportRules) {
            try {
                $existingRule = Get-TransportRule -Identity $rule.Name -ErrorAction SilentlyContinue

                if ($existingRule) {
                    if ($PSCmdlet.ShouldProcess($rule.Name, "Remove existing rule")) {
                        Remove-TransportRule -Identity $rule.Name -Confirm:$false
                        Write-LogMessage "Removed existing rule: $($rule.Name)" -Level Info -WriteToConsole
                    }
                }

                if ($PSCmdlet.ShouldProcess($rule.Name, "Create transport rule")) {
                    $ruleParams = @{
                        Name = $rule.Name
                        HeaderContainsMessageHeader = "X-PHISHTEST"
                        HeaderContainsWords = $SecurityHeader
                        HeaderMatchesMessageHeader = "Authentication-Results"
                        HeaderMatchesPatterns = "dkim=pass"
                        SetHeaderName = $rule.HeaderName
                        SetHeaderValue = $rule.HeaderValue
                        SenderIpRanges = $script:Config.PhishedIPs
                    }

                    New-TransportRule @ruleParams | Enable-TransportRule
                    Write-LogMessage "Created rule: $($rule.Name)" -Level Success -WriteToConsole
                }
            }
            catch {
                Write-LogMessage "Failed to create rule $($rule.Name): $_" -Level Error -WriteToConsole
            }
        }

        return $true
    }
    catch {
        Write-LogMessage "Failed to create transport rules: $_" -Level Error -WriteToConsole
        return $false
    }
}

function Update-PhishedTransportRuleHeaders {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$NewSecurityHeader
    )

    try {
        Write-LogMessage "Updating security headers on transport rules..." -Level Info -WriteToConsole

        foreach ($rule in $script:Config.TransportRules) {
            if ($PSCmdlet.ShouldProcess($rule.Name, "Update security header")) {
                Get-TransportRule -Identity $rule.Name -ErrorAction Stop | 
                    Set-TransportRule -HeaderContainsWords $NewSecurityHeader
                
                Write-LogMessage "Updated header for: $($rule.Name)" -Level Success -WriteToConsole
            }
        }

        return $true
    }
    catch {
        Write-LogMessage "Failed to update headers: $_" -Level Error -WriteToConsole
        return $false
    }
}
#endregion

#region API Functions
function Invoke-PhishedAPIAuth {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Username,

        [Parameter(Mandatory)]
        [SecureString]$Token,

        [Parameter(Mandatory)]
        [SecureString]$Secret
    )

    try {
        # Convert SecureStrings to plain text for API call
        $tokenPlain = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
            [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Token)
        )
        $secretPlain = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
            [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secret)
        )

        $body = @{
            username = $Username
            token = $tokenPlain
            secret = $secretPlain
        } | ConvertTo-Json

        $response = Invoke-RestMethod `
            -Uri "$($script:Config.APIEndpoint)/authorize" `
            -Method Post `
            -ContentType "application/json" `
            -Body $body `
            -ErrorAction Stop

        # Clear sensitive variables
        $tokenPlain = $null
        $secretPlain = $null
        $body = $null

        if ($response.status -eq "Authorized") {
            Write-LogMessage "API authentication successful" -Level Success -WriteToConsole
            return $response.token
        }
        else {
            throw "Authorization failed: $($response.status)"
        }
    }
    catch {
        Write-LogMessage "API authentication failed: $_" -Level Error -WriteToConsole
        return $null
    }
}

function New-PhishedClient {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$AuthToken,

        [Parameter(Mandatory)]
        [hashtable]$ClientDetails
    )

    try {
        if ($PSCmdlet.ShouldProcess($ClientDetails.organisationName, "Create Phished client")) {
            $response = Invoke-RestMethod `
                -Uri "$($script:Config.APIEndpoint)/clients" `
                -Method Post `
                -Headers @{ Authorization = "Bearer $AuthToken" } `
                -ContentType "application/json" `
                -Body ($ClientDetails | ConvertTo-Json) `
                -ErrorAction Stop

            Write-LogMessage "Client created: $($response.id)" -Level Success -WriteToConsole
            return $response
        }
    }
    catch {
        Write-LogMessage "Failed to create client: $_" -Level Error -WriteToConsole
        return $null
    }
}

function Add-PhishedClientDomain {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$AuthToken,

        [Parameter(Mandatory)]
        [string]$ClientId,

        [Parameter(Mandatory)]
        [string]$Domain,

        [Parameter(Mandatory)]
        [string]$ForwardEmail
    )

    try {
        if ($PSCmdlet.ShouldProcess($Domain, "Add domain to client")) {
            $body = @{
                domain = $Domain
                forward_email = $ForwardEmail
            } | ConvertTo-Json

            Invoke-RestMethod `
                -Uri "$($script:Config.APIEndpoint)/clients/$ClientId/domains" `
                -Method Post `
                -Headers @{ Authorization = "Bearer $AuthToken" } `
                -ContentType "application/json" `
                -Body $body `
                -ErrorAction Stop

            # Retrieve the email header
            $domains = Invoke-RestMethod `
                -Uri "$($script:Config.APIEndpoint)/clients/$ClientId/domains" `
                -Method Get `
                -Headers @{ Authorization = "Bearer $AuthToken" } `
                -ErrorAction Stop

            $emailHeader = ($domains.data | Where-Object { $_.name -eq $Domain }).email_header

            Write-LogMessage "Domain added successfully" -Level Success -WriteToConsole
            return $emailHeader
        }
    }
    catch {
        Write-LogMessage "Failed to add domain: $_" -Level Error -WriteToConsole
        return $null
    }
}
#endregion

#region Interactive Functions
function Start-PhishedClientCreation {
    [CmdletBinding()]
    param()

    Write-Host "`n=== Phished Client Creation ===" -ForegroundColor Cyan

    # Get credentials securely
    if (-not $PhishedAPIUsername) {
        $PhishedAPIUsername = Read-Host "Enter Partner API username"
    }

    if (-not $PhishedAPIToken) {
        $PhishedAPIToken = Read-Host "Enter Partner API token" -AsSecureString
    }

    if (-not $PhishedAPISecret) {
        $PhishedAPISecret = Read-Host "Enter Partner API secret" -AsSecureString
    }

    # Authenticate
    $authToken = Invoke-PhishedAPIAuth `
        -Username $PhishedAPIUsername `
        -Token $PhishedAPIToken `
        -Secret $PhishedAPISecret

    if (-not $authToken) {
        Write-LogMessage "Authentication failed. Aborting." -Level Error -WriteToConsole
        return
    }

    # Collect client details
    $clientDetails = @{
        email = Read-Host "Enter client email address"
        firstName = Read-Host "Enter client first name"
        lastName = Read-Host "Enter client last name"
        organisationName = Read-Host "Enter organisation name"
        wants_onboarding_wizard = (Read-Host "Enable onboarding wizard? (yes/no)") -eq "yes"
    }

    # Create client
    $client = New-PhishedClient -AuthToken $authToken -ClientDetails $clientDetails

    if ($client) {
        # Add domain
        $domain = Read-Host "Enter domain to associate"
        $forwardEmail = Read-Host "Enter forwarding email for reports"

        $emailHeader = Add-PhishedClientDomain `
            -AuthToken $authToken `
            -ClientId $client.id `
            -Domain $domain `
            -ForwardEmail $forwardEmail

        if ($emailHeader) {
            Write-Host "`nEmail Header: $emailHeader" -ForegroundColor Green
            
            $setupWhitelist = Read-Host "`nProceed with whitelisting setup? (yes/no)"
            if ($setupWhitelist -eq "yes") {
                Test-PhishedConfiguration
                Set-PhishedDomainsAndIPs
                New-PhishedTransportRules -SecurityHeader $emailHeader
            }
        }
    }
}

function Show-PhishedMenu {
    [CmdletBinding()]
    param()

    while ($true) {
        Write-Host "`n=== Phished Setup Menu ===" -ForegroundColor Cyan
        Write-Host "1 - Create Phished Customer"
        Write-Host "2 - Configure Phished Domains and IPs"
        Write-Host "3 - Create Transport Rules"
        Write-Host "4 - Update Security Headers"
        Write-Host "5 - Validate Configuration"
        Write-Host "6 - Exit"
        
        $choice = Read-Host "`nSelect option"

        switch ($choice) {
            1 { Start-PhishedClientCreation }
            2 { Set-PhishedDomainsAndIPs }
            3 {
                $header = Read-Host "Enter security header"
                New-PhishedTransportRules -SecurityHeader $header
            }
            4 {
                $header = Read-Host "Enter new security header"
                Update-PhishedTransportRuleHeaders -NewSecurityHeader $header
            }
            5 { Test-PhishedConfiguration }
            6 {
                Write-LogMessage "Exiting..." -Level Info -WriteToConsole
                return
            }
            default {
                Write-Host "Invalid selection" -ForegroundColor Red
            }
        }
    }
}
#endregion

#region Main Execution
# Banner
Write-Host @"

╔═══════════════════════════════════════╗
║   Phished Setup Script v$($script:Config.Version)         ║
║   WestSpring IT                       ║
╚═══════════════════════════════════════╝

"@ -ForegroundColor Cyan

# Prerequisites
if (-not (Test-AdminPrivileges)) { exit }
if (-not (Initialize-RequiredModules)) { exit }
if (-not (Connect-ExchangeOnlineSession)) { exit }

# Start menu
Show-PhishedMenu
#endregion