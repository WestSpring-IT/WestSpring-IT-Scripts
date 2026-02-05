<#

.PARAMETER phishedAPIUsername
    The username for the Phished Partner API.
.PARAMETER phishedAPIToken
    The API token for the Phished Partner API.
.PARAMETER phishedAPISecret
    The API secret for the Phished Partner API.
.PARAMETER clientEmail
    The email address of the client to be created.

.EXAMPLE
    .\phished-setup-v1.0.1.ps1 -phishedAPIUsername "your_username" -phishedAPIToken "your_token" -phishedAPISecret "your_secret" -clientEmail "phished+client@westwpring-it.co.uk"

.SYNOPSIS
    Sets up the environment and necessary configurations for the "phished" script version 1.0.1.

.DESCRIPTION
    This script automates the setup process for the "phished" tool, including environment preparation, dependency installation, and configuration steps required for proper operation.

.NOTES
    File Name : phished-setup-v1.0.1.ps1
    Author    : Fergus Barker - WestSpring IT
    Version   : 1.0.1
    Last Updated : 2025-08-22
#>
# Set parameters
Param(
    [Parameter(Mandatory = $false)]
    [string]$phishedAPIUsername,
    [Parameter(Mandatory = $false)]
    [string]$phishedAPIToken,
    [Parameter(Mandatory = $false)]
    [string]$phishedAPISecret,
    [Parameter(Mandatory = $false)]
    [string]$clientEmail,
    [switch]$help
)

if ($help) {
    Write-Host @"
Phished Setup Script v1.0.1

.PARAMETER phishedAPIUsername
    The username for the Phished Partner API.
.PARAMETER phishedAPIToken
    The API token for the Phished Partner API.
.PARAMETER phishedAPISecret
    The API secret for the Phished Partner API.
.PARAMETER clientEmail
    The email address of the client to be created.
.PARAMETER help
    Displays this help message.

.EXAMPLE
    .\phished-setup-v1.0.1.ps1 -phishedAPIUsername "your_username" -phishedAPIToken "your_token" -phishedAPISecret "your_secret" -clientEmail "phished+client@westwpring-it.co.uk"

"@ -ForegroundColor Cyan
    Exit
}

function write_log_message {
    param(
        [Parameter(Mandatory = $true)]
        [string]$message,
        [Parameter(Mandatory = $false)]
        [ValidateSet("Info", "Warning", "Error", "Success")]
        [string]$level = "Info",
        [Parameter(Mandatory = $false)]
        [Boolean]$writeToConsole = $false
    )
    $scriptName = $MyInvocation.MyCommand.Name
    $timestamp = Get-Date -Format "yyyy-MM-dd_THH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    
    switch ($level) {
        "Success" {$consoleColour = "Green"}
        "Info"    {$consoleColour = "Cyan"}
        "Warning" {$consoleColour = "Yellow"}
        "Error"   {$consoleColour = "Red"}
    }
    if ($writeToConsole) {
        write-host $logEntry -ForegroundColor $consoleColour
    }
    # Append to log file
    $logFilePath = "$env:TEMP\$(get-date -f "yyyy-MM-dd")_$($scriptName).log"
    Add-Content -Path $logFilePath -Value $logEntry
}

Function check_admin_privileges {
    $CurrentUser = New-Object Security.Principal.WindowsPrincipal $([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $CurrentUser.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
        $scriptPath = $MyInvocation.MyCommand.Path
        if (-not $scriptPath) {
            $scriptPath = $PSCommandPath
        }
        if ($scriptPath) {
            $ElevatedProcess = New-Object System.Diagnostics.ProcessStartInfo "PowerShell"
            $ElevatedProcess.Arguments = "& '" + $scriptPath + "'"
            $ElevatedProcess.Verb = "runas"
            [System.Diagnostics.Process]::Start($ElevatedProcess)
        } else {
            write_log_message "Cannot self-elevate: script path not found. Please run this script from a .ps1 file." -level "Error" -writeToConsole $true
        }
        Exit
    }
    write_log_message "Script is running with Administrator privileges!" -level "Success" -writeToConsole $true
}
#check_admin_privileges

# Script version
$scriptversion = "V1.0.1"
write_log_message "Phished - Synchronisation Tool $scriptversion `n
Loading..." -level "Info" -writeToConsole $true

# ensure_exchange_connection must be defined before load_required_modules
Function ensure_exchange_connection {
    try {
        # Check if already connected
        $connectionState = Get-ConnectionInformation | Select-Object -ExpandProperty State -ErrorAction SilentlyContinue
        if ($connectionState -ne "Connected") {
            write_log_message "Connecting to Exchange Online..." -level "Info" -writeToConsole $true
            Connect-ExchangeOnline -ShowBanner:$false 
            write_log_message "Connected to Exchange Online successfully." -level "Success" -writeToConsole $true
        } else {
            $defaultDomain = (Get-AcceptedDomain | Where-Object {$_.Default -eq $true}).DomainName
            write_log_message "Already connected to Exchange Online." -level "Info" -writeToConsole $true
            write_log_message "Connected tenant: $defaultDomain" -level "Info" -writeToConsole $true
        }
    } catch {
        write_log_message "Failed to connect to Exchange Online. Please check your credentials and network." -level "Error" -writeToConsole $true
        write_log_message "Error: $($_.Exception.Message)" -level "Error" -writeToConsole $true
        Read-Host
    }
}

Function load_required_modules {
    try {
        # Ensure the module is imported
        if (-not (Get-Module -Name ExchangeOnlineManagement -ListAvailable)) {
            write_log_message "ExchangeOnlineManagement module not found. Attempting to install..." -level "Warning" -writeToConsole $true
            Install-Module -Name ExchangeOnlineManagement -Force -ErrorAction Stop | Out-Null
        }
        write_log_message "ExchangeOnlineManagement module found." -level "Info" -writeToConsole $true
        Import-Module ExchangeOnlineManagement -ErrorAction Stop | Out-Null
        write_log_message "ExchangeOnlineManagement module loaded successfully." -level "Success" -writeToConsole $true

        # Ensure connection to Exchange Online
        #ensure_exchange_connection

        # Validate required cmdlets
        @(
            @{ Name = "Get-DkimSigningConfig"; Description = "DKIM cmdlet" },
            @{ Name = "Get-ExoPhishSimOverrideRule"; Description = "Phishing simulation cmdlet" },
            @{ Name = "Get-MailFlowRules"; Description = "Mail flow cmdlet" }
        ) | ForEach-Object {
            if (-not (Get-Command -Name $_.Name -ErrorAction SilentlyContinue)) {
                write_log_message "$($_.Description) ($($_.Name)) is not available. Please ensure you have the necessary permissions." -level "Warning" -writeToConsole $true
            } else {
                write_log_message "$($_.Description) ($($_.Name)) is available." -level "Info" -writeToConsole $true
            }
        }
    } catch {
        write_log_message "Failed to load ExchangeOnlineManagement module or connect to Exchange Online."-level "Error" -writeToConsole $true
        write_log_message "Error: $($_.Exception.Message)" -level "Error" -writeToConsole $true
        Exit
    }
}

# Call load_required_modules
load_required_modules

# call ensure_exchange_connection
ensure_exchange_connection

# Check Phished IPs and DKIM setup
Function validate_phished_configuration {
    write_log_message "Validating Phished IPs and DKIM setup..." -level "Info" -writeToConsole $true

    $phishedIPs = @("143.55.236.227", "143.55.236.228", "143.55.236.247", "34.140.69.192", "34.22.133.124")
    $missingIPs = $phishedIPs | Where-Object { -not (Get-TransportRule | Where-Object { $_.Description -contains $_ }) }

    if ($missingIPs.Count -gt 0) {
        write_log_message "The following Phished IPs are not whitelisted:" -level "Warning" -writeToConsole $true
        $missingIPs | ForEach-Object { write_log_message $_ -level "Warning" -writeToConsole $true }
    } else {
        write_log_message "All required Phished IPs are whitelisted." -level "Success" -writeToConsole $true
    }

    $dkimStatus = Get-DkimSigningConfig | Where-Object { $_.Enabled -eq $false }
    if ($dkimStatus) {
        write_log_message "DKIM is not enabled for the following domains:" -level "Warning" -writeToConsole $true
        $dkimStatus | ForEach-Object { write_log_message $_.Domain -level "Warning" -writeToConsole $true }
    } else {
        write_log_message "DKIM is properly configured for all domains." -level "Success" -writeToConsole $true
    }
}

# Add required domains and IPs
Function configure_phished_domains_and_ips {
    # Define IPs and domains as arrays
    $phishedIPs= @("143.55.236.227", "143.55.236.228", "143.55.236.247", "34.140.69.192", "34.22.133.124")
    $phishedDomains = @("psr.phished.io", "phished.io")

    write_log_message "Adding domains and IPs..." -level "Info" -writeToConsole $true

    # Set the domains and IPs using the proper format
    If ((Get-ExoPhishSimOverrideRule).Name.count -ne 0) {
        write_log_message "A Phising Override Rule already exists ($((Get-ExoPhishSimOverrideRule).Name)), adding the Phished Domains and IPs" -level "Info" -writeToConsole $true
        Get-ExoPhishSimOverrideRule | Set-ExoPhishSimOverrideRule -AddDomains $PhishedDomains -AddSenderIpRanges $PhishedIPs
    }
    elseif (((Get-PhishSimOverridePolicy).Count -ne 0) -and ((Get-ExoPhishSimOverrideRule).Count -eq 0)) {
        write_log_message "A Phishing Override Policy exists ($((Get-PhishSimOverridePolicy).Identity)), but there isn't a rule. Creating the rule 'Phished'" -level "Info" -writeToConsole $true
        New-ExoPhishSimOverrideRule -Name 'Phished' -Policy $((Get-PhishSimOverridePolicy).Identity) -Domains $PhishedDomains -SenderIpRanges $PhishedIPs -Comment 'Created to allow Phished.io simulation email to bypass the spam filter'
    }
    else {
        write_log_message "There is no Policy or Rule, creating a Policy (PhishingOverridePolicy), and Rule (Phished)" -level "Info" -writeToConsole $true
        New-PhishSimOverridePolicy -Name 'PhishingOverridePolicy'
        Start-Sleep 5
        New-ExoPhishSimOverrideRule -Name 'Phished' -Policy $((Get-PhishSimOverridePolicy).Identity) -Domains $PhishedDomains -SenderIpRanges $PhishedIPs -Comment 'Created to allow Phished.io simulation email to bypass the spam filter'
        write_log_message "The Phishing Override Policy ($((Get-PhishSimOverridePolicy).Identity)) and Rule ($((Get-ExoPhishSimOverrideRule).Name)) have been created" -level "Success" -writeToConsole $true
    } 
}

# Create transport rules
Function create_transport_rules {
    if (-not $Script:CustomerSecurityHeader) {
        $Script:CustomerSecurityHeader = Read-Host "Enter the domain Security Header"
    }

    $securityHeader = $Script:CustomerSecurityHeader

    write_log_message "Creating transport rules using Security Header: $securityHeader" -level "Info" -writeToConsole $true
    $rules = @(
        @{ Name = "Phished - Bypass Junk Folder"; HeaderName = "X-Forefront-Antispam-Report"; HeaderValue = "SKV: SKI;" },
        @{ Name = "Phished - Bypass Spam Folder"; HeaderName = "X-MS-Exchange-Organization-BypassClutter"; HeaderValue = "1" },
        @{ Name = "Phished - ATP Safe Links bypass spam filter"; HeaderName = "X-MS-Exchange-Organization-SkipSafeLinksProcessing"; HeaderValue = "1" },
        @{ Name = "Phished - ATP Safe Links bypass junk folder"; HeaderName = "X-MS-Exchange-Organization-SkipSafeLinksProcessing"; HeaderValue = "1;" },
        @{ Name = "Phished - ATP Attachments bypass"; HeaderName = "X-MS-Exchange-Organization-SkipSafeAttachmentProcessing"; HeaderValue = "1" }
    )

    foreach ($rule in $rules) {
        try {
            # Check if the rule already exists
            $existingRule = Get-TransportRule -Identity $rule.Name -ErrorAction SilentlyContinue

            # If the rule exists, remove it
            if ($existingRule) {
                write_log_message "A rule with the name '$($rule.Name)' already exists. Removing it..." -level "Warning" -writeToConsole $true
                Remove-TransportRule -Identity $rule.Name -Confirm:$false
                write_log_message "Existing rule '$($rule.Name)' removed successfully." -level "Success" -writeToConsole $true
            }

            # Create the new transport rule with conditions for DKIM and sender IP verification
            New-TransportRule -Name $rule.Name `
                -HeaderContainsMessageHeader "X-PHISHTEST" `
                -HeaderContainsWords $securityHeader `
                -HeaderMatchesMessageHeader "Authentication-Results" `
                -HeaderMatchesPatterns "dkim=pass" `
                -SetHeaderName $rule.HeaderName `
                -SetHeaderValue $rule.HeaderValue `
                -SenderIpRanges @("143.55.236.227", "143.55.236.228", "143.55.236.247", "34.140.69.192", "34.22.133.124")

            Get-TransportRule -Identity $rule.Name | Enable-TransportRule
            write_log_message "Transport rule '$($rule.Name)' created and enabled successfully." -level "Success" -writeToConsole $true
        } catch {
            write_log_message "Failed to create transport rule '$($rule.Name)': $($_.Exception.Message)" -level "Error" -writeToConsole $true
        }
    }
}

# Update existing transport rules with a new security header
Function update_transport_rules_security_header {
    $securityHeader = Read-Host "Enter the new domain Security Header"

    write_log_message "Updating transport rules with new Security Header..." -level "Info" -writeToConsole $true
    $rules = @(
        "Phished - Bypass Junk Folder",
        "Phished - Bypass Spam Folder",
        "Phished - ATP Safe Links bypass spam filter",
        "Phished - ATP Safe Links bypass junk folder",
        "Phished - ATP Attachments bypass"
    )

    foreach ($rule in $rules) {
        Get-TransportRule -Identity $rule | Set-TransportRule -HeaderContainsWords $securityHeader
    }
}

# Create a new Phished customer via Partner API
Function create_phished_customer {
    $username = Read-Host "Enter your Partner API username"
    write_log_message "Username entered: $username" -level "Info" -writeToConsole $false
    $apiToken = Read-Host "Enter your Partner API token"
    write_log_message "API Token entered: $apiToken" -level "Info" -writeToConsole $false
    $apiSecret = Read-Host "Enter your Partner API secret"
    write_log_message "API Secret entered: $apiSecret" -level "Info" -writeToConsole $false

    write_log_message "Authorizing with Partner API..." -level "Info" -writeToConsole $true
    $authResponse = Invoke-RestMethod -Uri "https://partners.phished.io/api/authorize" -Method POST -ContentType "application/json" -Body (@{
        username = $username
        token = $apiToken
        secret = $apiSecret
    } | ConvertTo-Json -Depth 10)

    if ($authResponse.status -eq "Authorized") {
        write_log_message "Authorization successful. Proceeding to create a new client..." -level "Success" -writeToConsole $true
        $authToken = $authResponse.token

        $email = Read-Host "Enter client email"
        write_log_message "Client email entered: $email" -level "Info" -writeToConsole $false
        $firstName = Read-Host "Enter client first name"
        write_log_message "Client first name entered: $firstName" -level "Info" -writeToConsole $false
        $lastName = Read-Host "Enter client last name"
        write_log_message "Client last name entered: $lastName" -level "Info" -writeToConsole $false
        $organisationName = Read-Host "Enter client organisation name"
        write_log_message "Client organisation name entered: $organisationName" -level "Info" -writeToConsole $false
        $wantsOnboardingInput = Read-Host "Does the client want the onboarding wizard? (yes/no)"
        write_log_message "Client onboarding preference entered: $wantsOnboardingInput" -level "Info" -writeToConsole $false
        $wantsOnboarding = if ($wantsOnboardingInput -eq "yes") { $true } else { $false }

        $clientResponse = Invoke-RestMethod -Uri "https://partners.phished.io/api/clients" -Method POST -Headers @{ Authorization = "Bearer $authToken" } -ContentType "application/json" -Body (@{
            email = $email
            firstName = $firstName
            lastName = $lastName
            organisationName = $organisationName
            wants_onboarding_wizard = $wantsOnboarding
        } | ConvertTo-Json -Depth 10)

        write_log_message "Client created successfully:" -level "Success" -writeToConsole $true
        Write-Output $clientResponse
        write_log_message "Client ID: $($clientResponse.id)" -level "Info" -writeToConsole $false

        $clientName = $organisationName
        write_log_message "Fetching client ID for $clientName..." -level "Info" -writeToConsole $true

        $clients = Invoke-RestMethod -Uri "https://partners.phished.io/api/clients" -Method GET -Headers @{ Authorization = "Bearer $authToken" }
        $clientId = ($clients | Where-Object { $_.name -eq $clientName }).id

        if ($clientId) {
            write_log_message "Client ID retrieved: $clientId" -level "Success" -writeToConsole $true

            $domain = Read-Host "Enter the domain to associate with the client"
            write_log_message "Domain entered: $domain" -level "Info" -writeToConsole $false
            $forwardEmail = Read-Host "Enter the forwarding email (where do reports end up)"
            write_log_message "Forwarding email entered: $forwardEmail" -level "Info" -writeToConsole $false

            $domainBody = @{
                domain = $domain
                forward_email = $forwardEmail
            } | ConvertTo-Json -Depth 10

            # Create the domain
            Invoke-RestMethod -Uri "https://partners.phished.io/api/clients/$clientId/domains" -Method POST -Headers @{ Authorization = "Bearer $authToken" } -ContentType "application/json" -Body $domainBody

            write_log_message "Domain associated with client successfully." -level "Success" -writeToConsole $true

            # Retrieve the domains to get the email_header
            write_log_message "Retrieving domains for client to fetch email header..." -level "Info" -writeToConsole $true
            $domainsResponse = Invoke-RestMethod -Uri "https://partners.phished.io/api/clients/$clientId/domains" -Method GET -Headers @{ Authorization = "Bearer $authToken" }

            # Extract the data array from the response
            $domains = $domainsResponse.data

            # Find the domain just added and extract the email_header
            if ($domains -is [System.Collections.IEnumerable]) {
                $addedDomain = $domains | Where-Object { $_.name -eq $domain }

                if ($addedDomain -and $addedDomain.email_header) {
                    $emailHeader = $addedDomain.email_header
                    if ($null -ne $emailHeader -and $emailHeader -ne "") {
                        write_log_message "Email Header retrieved: $emailHeader" -level "Success" -writeToConsole $true
                        $Script:CustomerSecurityHeader = $emailHeader
                        write_log_message "Customer Security Header set to: $Script:CustomerSecurityHeader" -level "Info" -writeToConsole $true
                    } else {
                        write_log_message "Email Header not found. Please enter it manually." -level "Warning" -writeToConsole $true
                        $Script:CustomerSecurityHeader = Read-Host "Enter the domain Security Header"
                    }
                } else {
                    write_log_message "Failed to retrieve email header. Please enter it manually." -level "Warning" -writeToConsole $true
                    $Script:CustomerSecurityHeader = Read-Host "Enter the domain Security Header"
                }
            $setupWhitelist = Read-Host "Do you want to proceed with whitelisting setup for this client? (yes/no)"
            if ($setupWhitelist.ToLower() -eq "yes") {
                validate_phished_configuration
                configure_phished_domains_and_ips
                create_transport_rules
                write_log_message "Whitelisting setup completed successfully." -level "Success" -writeToConsole $true
            }
                <# validate_phished_configuration
                configure_phished_domains_and_ips
                create_transport_rules
                write_log_message "Whitelisting setup completed successfully." -level "Success" -writeToConsole $true #>
            }
        } else {
            write_log_message "Failed to retrieve Client ID. Please verify the client name." -level "Error" -writeToConsole $true
        }
    } else {
        write_log_message "Authorization failed. Please check your credentials." -level "Error" -writeToConsole $true
    }
}

##TODO Add fucntions to create security groups, create enterprise apps, configure SSO and provisioning, add and deploy Outlook Add-in



# Display menu options
Function open_menu {
    while ($true) {
        $selection = Read-Host @"
Select an option:
1 - Create Phished Customer
2 - Add Domains and IPs for Phished
3 - Create Transport Rules for Phished
4 - Add Security Header to Transport Rules
5 - Replace Current Security Header on Transport Rules
6 - Exit
What would you like to do
"@

        switch ($selection) {
            1 {
                create_phished_customer
            }
            2 {
                #ensure_exchange_connection
                condfigure_phished_domains_and_ips
                write_log_message "Completed." -level "Success" -writeToConsole $true
            }
            3 {
                #ensure_exchange_connection
                create_transport_rules
                write_log_message "Completed." -level "Success" -writeToConsole $true
            }
            4 {
                #ensure_exchange_connection
                update_transport_rules_security_header
                write_log_message "Completed." -level "Success" -writeToConsole $true
            }
            5 {
                #ensure_exchange_connection
                update_transport_rules_security_header
                write_log_message "Completed." -level "Success" -writeToConsole $true
            }
            6 { 
                write_log_message "Exiting Phished setup script. Goodbye!" -level "Info" -writeToConsole $true
                Exit 
            }
            default {
                write_log_message "Invalid selection. Please try again." -level "Warning" -writeToConsole $true
            }
        }
    }
}

# Start the menu
open_menu
