# Copyright © WESTSPRING IT LIMITED
# Author:        Thomas Samuel
# Support:       thomassamuel@westspring-it.co.uk

# Define variables for script name and log directory
$Script:ScriptName = "LocalAdministrators"
$Script:LogDirectory = "C:\WestSpring IT\LogFiles"

function New-LogMessage {
    param(
        [ValidateSet("START", "SUCCESS", "INFO", "WARN", "ERROR", "END")]
        [string]$Level = "INFO",

        [Parameter(Mandatory)]
        [string]$Message
    )

    try {
        # Create log directory if it doesn't exist
        New-Item -Path $Script:LogDirectory -ItemType Directory -Force -ErrorAction Stop | Out-Null

        # Format log entry
        $LogDay = Get-Date -Format 'dd-MM-yyyy'
        $LogTime = Get-Date -Format 'HH:mm:ss'
        $SafeScriptName = $Script:ScriptName -replace '[<>:"/\\|?*]', '_'
        $LogFile = Join-Path $Script:LogDirectory "$LogDay-$SafeScriptName.log"
        $PaddedLevel = $Level.PadRight(7)
        $Entry = "$LogTime | $PaddedLevel | $Message"

        # Write log entry to file
        Add-Content -Path $LogFile -Value $Entry -Encoding utf8 -ErrorAction Stop

        # Write log entry to console with color based on level
        switch ($Level) {
            "START" { Write-Host $Entry -ForegroundColor Cyan }
            "END" { Write-Host $Entry -ForegroundColor Cyan }
            "ERROR" { Write-Error $Entry }
            "SUCCESS" { Write-Host $Entry -ForegroundColor Green }
            "WARN" { Write-Warning $Entry }
            default { Write-Host $Entry }
        }
    }
    catch {
        # If logging fails, write error to console but continue script execution
        Write-Error "Failed to write log entry: $($_.Exception.Message)"
    }
}

# Log the start of the script execution
New-LogMessage -Level "START" -Message "Starting $Script:ScriptName script execution."

# Define the list of local administrators to be added to the Administrators group
$Admins = @(
    @{ Name = "wsadmin"; Password = "{[WSADMINPassword]}" },
    @{ Name = "{[ClientLocalAdminUsername]}"; Password = "{[ClientLocalAdminPassword]}" }
)
# Iterate through each admin account, create or update as needed, and ensure they are in the local Administrators group
try {
    foreach ($Admin in $Admins) {
        # Convert provided password to SecureString
        $SecurePassword = ConvertTo-SecureString $Admin.Password -AsPlainText -Force

        # Check if admin already exists on system
        $ExistingUser = Get-LocalUser -Name $Admin.Name -ErrorAction SilentlyContinue
        if (-not $ExistingUser) {
            # Account doesn't exist, creating it now
            New-LogMessage -Level "INFO" -Message "Account does not exist: $($Admin.Name). Creating now."

            $UserParameters = @{
                Name     = $Admin.Name
                Password = $SecurePassword
            }
            New-LocalUser @UserParameters | Out-Null

            New-LogMessage -Level "SUCCESS" -Message "Created local user: $($Admin.Name)"
        }
        else {
            # Account already exists, aligning password
            New-LogMessage -Level "INFO" -Message "Account already exists: $($Admin.Name). Updating password."
            Set-LocalUser -Name $Admin.Name -Password $SecurePassword
            New-LogMessage -Level "SUCCESS" -Message "Password updated for: $($Admin.Name)"
        }

        # Enforce password never expires
        Set-LocalUser -Name $Admin.Name -PasswordNeverExpires $true
        New-LogMessage -Level "SUCCESS" -Message "Set PasswordNeverExpires for: $($Admin.Name)"

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
            New-LogMessage -Level "WARN" -Message "Account is not in local Administrators group: $($Admin.Name). Adding now."
            Add-LocalGroupMember -Group "Administrators" -Member $Admin.Name
            New-LogMessage -Level "SUCCESS" -Message "Added to local Administrators group: $($Admin.Name)"
        }
        else {
            # User is already in Administrators group
            New-LogMessage -Level "INFO" -Message "Account already in local Administrators group: $($Admin.Name)"
        }
        # Continue to next admin account
    }

    New-LogMessage -Level "SUCCESS" -Message "Local administrator configuration complete."
    exit 0
}
catch {
    $ErrorMessage = $_.Exception.Message
    New-LogMessage -Level "ERROR" -Message "Script failed. Error: $ErrorMessage"
    exit 1
}

# Log the successful completion of the script execution
New-LogMessage -Level "END" -Message "Completed $Script:ScriptName script execution."