<#
    .SYNOPSIS
        Removes Opera browser from specified local user profiles (non-interactive).
    
    .DESCRIPTION
        This script removes Opera browser installation files and registry entries
        from one or more local user profiles. Designed for automated execution.
    
    .PARAMETER UserProfiles
        Array of usernames to process. Required.
    
    .PARAMETER OperaPath
        Custom Opera installation path pattern. Default is "Opera*"
    
    .PARAMETER RemoveRoamingData
        Switch to also remove Opera roaming data. Default is false.
    
    .PARAMETER LogPath
        Path to log file. If not specified, logs to console only.
    
    .EXAMPLE
        .\Remove-Opera.ps1 -UserProfiles "Administrator","westadmin"
    
    .EXAMPLE
        .\Remove-Opera.ps1 -UserProfiles "Administrator" -RemoveRoamingData -LogPath "C:\Logs\opera-removal.log"
#>

param(
    [Parameter(Mandatory=$true)]
    [string[]]$UserProfiles,
    
    [Parameter(Mandatory=$false)]
    [string]$OperaPath = "Opera*",
    
    [Parameter(Mandatory=$false)]
    [switch]$RemoveRoamingData,
    
    [Parameter(Mandatory=$false)]
    [string]$LogPath
)

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('Info','Warning','Error','Success')]
        [string]$Level = 'Info'
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    
    # Console output with colors
    switch ($Level) {
        'Info'    { Write-Host $logMessage -ForegroundColor White }
        'Warning' { Write-Host $logMessage -ForegroundColor Yellow }
        'Error'   { Write-Host $logMessage -ForegroundColor Red }
        'Success' { Write-Host $logMessage -ForegroundColor Green }
    }
    
    # File output if specified
    if ($LogPath) {
        Add-Content -Path $LogPath -Value $logMessage
    }
}

function Remove-OperaFromProfile {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Username
    )
    
    $UserProfilePath = "C:\Users\$Username"
    $success = $true
    
    # Check if profile exists
    if (-not (Test-Path $UserProfilePath)) {
        Write-Log "Profile path not found: $UserProfilePath" -Level Warning
        return $false
    }
    
    Write-Log "================================================" -Level Info
    Write-Log "Processing user: $Username" -Level Info
    Write-Log "================================================" -Level Info
    
    # Remove Opera installation files
    $OperaInstallPath = Join-Path $UserProfilePath "AppData\Local\Programs\$OperaPath"
    Write-Log "Checking for Opera installation at: $OperaInstallPath" -Level Info
    
    $OperaFolders = Get-Item $OperaInstallPath -ErrorAction SilentlyContinue
    
    if ($OperaFolders) {
        foreach ($folder in $OperaFolders) {
            try {
                Write-Log "Removing folder: $($folder.FullName)" -Level Info
                Remove-Item -Path $folder.FullName -Recurse -Force -ErrorAction Stop
                Write-Log "Successfully removed: $($folder.FullName)" -Level Success
            }
            catch {
                Write-Log "Failed to remove $($folder.FullName): $_" -Level Error
                $success = $false
            }
        }
    }
    else {
        Write-Log "No Opera installation found in Programs folder" -Level Info
    }
    
    # Remove registry entries
    $NTUserDat = Join-Path $UserProfilePath "NTUSER.DAT"
    
    if (-not (Test-Path $NTUserDat)) {
        Write-Log "NTUSER.DAT not found for $Username" -Level Warning
        return $false
    }
    
    $HiveName = "HKU\TempHive_$Username"
    
    try {
        Write-Log "Loading registry hive: $NTUserDat" -Level Info
        $result = reg load $HiveName $NTUserDat 2>&1
        
        if ($LASTEXITCODE -ne 0) {
            Write-Log "Failed to load registry hive for $Username. User may be logged in. Error: $result" -Level Warning
            $success = $false
            return $false
        }
        
        Write-Log "Registry hive loaded successfully" -Level Success
        
        # Remove Opera uninstall entries
        $UninstallRoot = "Registry::$HiveName\Software\Microsoft\Windows\CurrentVersion\Uninstall"
        
        if (Test-Path $UninstallRoot) {
            Write-Log "Searching for Opera registry keys..." -Level Info
            
            $OperaKeys = Get-ChildItem $UninstallRoot -ErrorAction SilentlyContinue | Where-Object {
                $_.PSChildName -match "Opera"
            }
            
            if ($OperaKeys) {
                foreach ($key in $OperaKeys) {
                    try {
                        Write-Log "Removing registry key: $($key.PSChildName)" -Level Info
                        Remove-Item -LiteralPath $key.PSPath -Recurse -Force -ErrorAction Stop
                        Write-Log "Successfully removed: $($key.PSChildName)" -Level Success
                    }
                    catch {
                        Write-Log "Failed to remove registry key $($key.PSChildName): $_" -Level Error
                        $success = $false
                    }
                }
            }
            else {
                Write-Log "No Opera registry keys found" -Level Info
            }
        }
        else {
            Write-Log "Uninstall registry path not found" -Level Info
        }
        
        # Remove Opera roaming data if switch is enabled
        if ($RemoveRoamingData) {
            $OperaRoamingPath = Join-Path $UserProfilePath "AppData\Roaming\Opera Software"
            if (Test-Path $OperaRoamingPath) {
                try {
                    Write-Log "Removing Opera roaming data at: $OperaRoamingPath" -Level Info
                    Remove-Item -Path $OperaRoamingPath -Recurse -Force -ErrorAction Stop
                    Write-Log "Successfully removed Opera roaming data" -Level Success
                }
                catch {
                    Write-Log "Failed to remove roaming data: $_" -Level Error
                    $success = $false
                }
            }
        }
    }
    catch {
        Write-Log "Error processing registry for $Username : $_" -Level Error
        $success = $false
    }
    finally {
        # Unload the registry hive
        Write-Log "Unloading registry hive..." -Level Info
        [gc]::Collect()
        Start-Sleep -Milliseconds 500
        
        $unloadResult = reg unload $HiveName 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-Log "Registry hive unloaded successfully" -Level Success
        }
        else {
            Write-Log "Failed to unload registry hive. Error: $unloadResult" -Level Warning
            Write-Log "System may need restart to fully unload the hive" -Level Warning
            $success = $false
        }
    }
    
    Write-Log "Completed processing for: $Username" -Level Info
    return $success
}

# Main execution
Write-Log "Opera Browser Removal Script - Starting" -Level Info
Write-Log "=========================================" -Level Info

# Check if running as administrator
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Log "This script must be run as Administrator!" -Level Error
    exit 1
}

# Initialize counters
$totalProfiles = $UserProfiles.Count
$successCount = 0
$failureCount = 0

Write-Log "Processing $totalProfiles user profile(s): $($UserProfiles -join ', ')" -Level Info

# Process each profile
foreach ($profile in $UserProfiles) {
    $result = Remove-OperaFromProfile -Username $profile
    
    if ($result) {
        $successCount++
    }
    else {
        $failureCount++
    }
}

# Summary
Write-Log "=========================================" -Level Info
Write-Log "Opera removal process completed" -Level Info
Write-Log "Total profiles processed: $totalProfiles" -Level Info
Write-Log "Successful: $successCount" -Level Success
Write-Log "Failed: $failureCount" -Level $(if ($failureCount -gt 0) { 'Warning' } else { 'Info' })
Write-Log "=========================================" -Level Info

# Exit with appropriate code
if ($failureCount -gt 0) {
    exit 1
}
else {
    exit 0
}