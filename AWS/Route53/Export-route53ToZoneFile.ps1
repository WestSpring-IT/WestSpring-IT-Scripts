#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Export AWS Route 53 DNS records to zone files using AWS PowerShell modules

.DESCRIPTION
    This script exports DNS records from AWS Route 53 hosted zones to standard BIND zone files.
    It can process single or multiple domains. Uses AWS.Tools.Route53 or AWSPowerShell modules.

.PARAMETER Domains
    One or more domain names to export. Can be a single domain or an array of domains.

.PARAMETER OutputDirectory
    Directory where zone files will be saved. Defaults to current directory.

.PARAMETER ProfileName
    AWS PowerShell profile name to use. If not specified, uses the default profile.

.PARAMETER Region
    AWS region. Defaults to us-east-1.

.EXAMPLE
    .\Export-Route53ToZoneFile.ps1 -Domains "example.com"

.EXAMPLE
    .\Export-Route53ToZoneFile.ps1 -Domains @("example.com", "example.org") -OutputDirectory "C:\DNS\Backups"

.EXAMPLE
    .\Export-Route53ToZoneFile.ps1 -Domains "example.com" -ProfileName "AWS_ACCESS_KEYS"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true, Position=0)]
    [string[]]$Domains,
    
    [Parameter(Mandatory=$false)]
    [string]$OutputDirectory = ".",
    
    [Parameter(Mandatory=$false)]
    [string]$ProfileName = "",
    
    [Parameter(Mandatory=$false)]
    [string]$Region = "us-east-1"
)

# Function to check if AWS PowerShell modules are installed
function Test-AWSPowerShellModule {
    $modules = @(
        "AWS.Tools.Route53",
        "AWSPowerShell.NetCore",
        "AWSPowerShell"
    )
    
    foreach ($module in $modules) {
        if (Get-Module -ListAvailable -Name $module) {
            Write-Host "Found AWS PowerShell module: $module" -ForegroundColor Green
            try {
                Import-Module $module -ErrorAction Stop
                return $module
            }
            catch {
                Write-Warning "Failed to import $module : $_"
            }
        }
    }
    
    return $null
}

# Function to find hosted zone ID for a domain
function Get-HostedZoneId {
    param(
        [string]$DomainName
    )
    
    Write-Host "Looking up hosted zone for domain: $DomainName" -ForegroundColor Cyan
    
    try {
        # Get all hosted zones
        $zones = Get-R53HostedZoneList
        
        # Find the zone that matches the domain (with or without trailing dot)
        $zone = $zones | Where-Object { 
            $_.Name -eq "$DomainName." -or $_.Name -eq $DomainName 
        } | Select-Object -First 1
        
        if ($zone) {
            # Extract zone ID (format: /hostedzone/Z1234567890ABC)
            $zoneId = $zone.Id -replace '/hostedzone/', ''
            return @{
                ZoneId = $zoneId
                ZoneName = $zone.Name.TrimEnd('.')
            }
        }
        
        return $null
    }
    catch {
        Write-Error "Error retrieving hosted zones: $_"
        return $null
    }
}

# Function to get record sets from a hosted zone
function Get-RecordSets {
    param(
        [string]$ZoneId
    )
    
    Write-Host "Fetching DNS records..." -ForegroundColor Cyan
    
    try {
        $records = Get-R53ResourceRecordSet -HostedZoneId $ZoneId
        return $records.ResourceRecordSets
    }
    catch {
        Write-Error "Error retrieving record sets: $_"
        return $null
    }
}

# Function to format TTL
function Format-TTL {
    param([int]$TTL)
    if ($TTL) { return $TTL }
    return 300  # Default TTL
}

# Function to convert record to zone file format
function Convert-RecordToZoneFormat {
    param(
        [PSCustomObject]$Record,
        [string]$ZoneName
    )
    
    $lines = @()
    $name = $Record.Name.TrimEnd('.')
    
    # Remove zone name from FQDN to get relative name
    if ($name -eq $ZoneName) {
        $name = "@"
    }
    elseif ($name.EndsWith(".$ZoneName")) {
        $name = $name.Substring(0, $name.Length - $ZoneName.Length - 1)
    }
    
    $ttl = Format-TTL -TTL $Record.TTL
    $type = $Record.Type
    
    # Handle different record types
    if ($Record.ResourceRecords) {
        foreach ($rr in $Record.ResourceRecords) {
            $value = $rr.Value
            
            # Special formatting for different record types
            switch ($type) {
                "TXT" {
                    # Ensure TXT records are properly quoted
                    if (-not $value.StartsWith('"')) {
                        $value = "`"$value`""
                    }
                }
                "SOA" {
                    # SOA records are already formatted correctly
                }
                "MX" {
                    # MX records are already formatted correctly
                }
                "SRV" {
                    # SRV records are already formatted correctly
                }
            }
            
            $lines += "$name`t$ttl`tIN`t$type`t$value"
        }
    }
    
    # Handle alias records
    if ($Record.AliasTarget) {
        $aliasTarget = $Record.AliasTarget.DNSName.TrimEnd('.')
        $comment = "; ALIAS record pointing to $aliasTarget (AWS specific - $($Record.AliasTarget.HostedZoneId))"
        $lines += $comment
        # Note: Standard zone files don't support ALIAS records, so we add as comment
        $lines += "; $name`t$ttl`tIN`tALIAS`t$aliasTarget"
    }
    
    return $lines
}

# Function to create zone file
function Export-ZoneFile {
    param(
        [PSCustomObject[]]$Records,
        [string]$ZoneName,
        [string]$OutputPath
    )
    
    Write-Host "Creating zone file: $OutputPath" -ForegroundColor Cyan
    
    $content = @()
    
    # Zone file header
    $content += "; Zone file for $ZoneName"
    $content += "; Generated on $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $content += "; Exported from AWS Route 53"
    $content += ""
    $content += "`$ORIGIN $ZoneName."
    $content += "`$TTL 300"
    $content += ""
    
    # Sort records by name and type for better readability
    $sortedRecords = $Records | Sort-Object Name, Type
    
    $lastType = ""
    foreach ($record in $sortedRecords) {
        # Add blank line between different record types for readability
        if ($record.Type -ne $lastType -and $lastType -ne "") {
            $content += ""
        }
        $lastType = $record.Type
        
        $recordLines = Convert-RecordToZoneFormat -Record $record -ZoneName $ZoneName
        if ($recordLines) {
            $content += $recordLines
        }
    }
    
    # Write to file
    $content | Out-File -FilePath $OutputPath -Encoding UTF8
    
    Write-Host "Successfully exported $($Records.Count) records to $OutputPath" -ForegroundColor Green
}

# Main script execution
try {
    Write-Host "AWS Route 53 Zone File Exporter (PowerShell Modules)" -ForegroundColor Yellow
    Write-Host "====================================================" -ForegroundColor Yellow
    Write-Host ""
    
    # Check if AWS PowerShell modules are installed
    $moduleLoaded = Test-AWSPowerShellModule
    
    if (-not $moduleLoaded) {
        Write-Error @"
AWS PowerShell modules are not installed. Please install one of:
- AWS.Tools.Route53 (recommended, modular)
- AWSPowerShell.NetCore (cross-platform, monolithic)
- AWSPowerShell (Windows only, monolithic)

To install AWS.Tools.Route53:
    Install-Module -Name AWS.Tools.Route53 -Scope CurrentUser

To install AWSPowerShell.NetCore:
    Install-Module -Name AWSPowerShell.NetCore -Scope CurrentUser
"@
        exit 1
    }
    
    # Set AWS credentials if profile specified
    if ($ProfileName) {
        Write-Host "Using AWS profile: $ProfileName" -ForegroundColor Cyan
        try {
            Set-AWSCredential -ProfileName $ProfileName
        }
        catch {
            Write-Error "Failed to set AWS credentials for profile '$ProfileName': $_"
            Write-Host "`nAvailable profiles:" -ForegroundColor Yellow
            Get-AWSCredential -ListProfileDetail | Format-Table -AutoSize
            exit 1
        }
    }
    
    # Set region if specified
    if ($Region) {
        Write-Host "Using AWS region: $Region" -ForegroundColor Cyan
        Set-DefaultAWSRegion -Region $Region
    }
    
    # Create output directory if it doesn't exist
    if (-not (Test-Path $OutputDirectory)) {
        New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
        Write-Host "Created output directory: $OutputDirectory" -ForegroundColor Green
    }
    
    Write-Host ""
    
    # Process each domain
    foreach ($domain in $Domains) {
        Write-Host "========================================" -ForegroundColor Yellow
        Write-Host "Processing domain: $domain" -ForegroundColor Yellow
        Write-Host "========================================" -ForegroundColor Yellow
        
        # Get hosted zone ID
        $zoneInfo = Get-HostedZoneId -DomainName $domain
        
        if (-not $zoneInfo) {
            Write-Warning "Could not find hosted zone for domain: $domain"
            Write-Host ""
            continue
        }
        
        Write-Host "Found hosted zone ID: $($zoneInfo.ZoneId)" -ForegroundColor Green
        
        # Get all records
        $records = Get-RecordSets -ZoneId $zoneInfo.ZoneId
        
        if (-not $records) {
            Write-Warning "No records found for domain: $domain"
            Write-Host ""
            continue
        }
        
        # Create zone file
        $outputFile = Join-Path $OutputDirectory "$($zoneInfo.ZoneName).zone"
        Export-ZoneFile -Records $records -ZoneName $zoneInfo.ZoneName -OutputPath $outputFile
        Write-Host ""
    }
    
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "Export completed successfully!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
}
catch {
    Write-Error "An error occurred: $_"
    Write-Error $_.ScriptStackTrace
    exit 1
}