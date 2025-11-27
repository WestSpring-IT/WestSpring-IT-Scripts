# Update pre-2000 (sAMAccountName) values that look like "$GO2000-..." to match existing first.last username
param(
    [switch]$WhatIf = $true,
    [switch]$Verbose
)

## functions
function write_log_message {
<#
    .SYNOPSIS
        Writes a formatted log message to a daily log file and optionally to the console.

    .DESCRIPTION
        The write_log_message function logs messages with a timestamp and severity level.
        It writes the log entry to a log file located in the user's TEMP directory, named
        after the script and the current date. Optionally, it can also output the message
        to the console in a color corresponding to the severity level.

    .PARAMETER message
        The message text to log. This parameter is mandatory.

    .PARAMETER level
        The severity level of the message. Valid values are:
        - Info (default)
        - Warning
        - Error
        - Success

    .PARAMETER writeToConsole
        If set to $false (default), the message is only written to the log file.
        If set to $true, the message will also be written to the console with color coding.

    .EXAMPLE
        write_log_message -message "Script started."

        Logs an informational message to the log file.

    .EXAMPLE
        write_log_message -message "Operation completed successfully." -level "Success" -writeToConsole $true

        Logs a success message to the log file and displays it in green in the console.

    .EXAMPLE
        write_log_message -message "An error occurred." -level "Error"

        Logs an error message to the log file in red (if displayed in console).

    .NOTES
        Log files are stored in the TEMP directory with the format:
        yyyy-MM-dd_<ScriptName>.log

        Example: C:\Users\<User>\AppData\Local\Temp\2025-08-01_write_log_message.log
#>
    param(
        [Parameter(Mandatory = $true)]
        [string]$message,
        [Parameter(Mandatory = $false)]
        [ValidateSet("Info", "Warning", "Error", "Success")]
        [string]$level = "Info",
        [Parameter(Mandatory = $false)]
        [Boolean]$writeToConsole = $false
    )
    $scriptName = $($Script:MyInvocation.MyCommand.Name).TrimEnd(".ps1")
    $timestamp = Get-Date -Format "yyyy-MM-dd_THHmmss"
    $logEntry = "[$timestamp] [$level] $message"
    
    switch ($level) {
        "Success" {$consoleColour = "Green"}
        "Info"    {$consoleColour = "Cyan"}
        "Warning" {$consoleColour = "Yellow"}
        "Error"   {$consoleColour = "Red"}
    }
    if ($writeToConsole) {
        Write-Host $logEntry -ForegroundColor $consoleColour
    }
    # Append to log file
    $logFilePath = "$env:TEMP\$(get-date -f "yyyy-MM-dd")_$($scriptName).log"
    Add-Content -Path $logFilePath -Value $logEntry
}

# Helper: normalize candidate and enforce sAMAccountName rules (max 20 chars)
function Get-CandidateSam {
    param(
        [string]$raw
    )
    if (-not $raw) { return $null }
    $cand = $raw.ToLower().Trim()

    # Replace spaces with dot, remove invalid chars (allow letters, digits, dot, underscore, hyphen)
    $cand = $cand -replace '\s+','.'
    $cand = $cand -replace '[^a-z0-9\._-]',''

    # sAMAccountName max length 20
    if ($cand.Length -gt 20) { $cand = $cand.Substring(0,20) }
    return $cand
}

# Helper: get unique name (append numeric suffix if required)
function Get-UniqueSam {
    param(
        [string]$base,
        [string]$currentDistinguishedName
    )
    if (-not $base) { return $null }
    $candidate = $base
    $i = 1
    while ($true) {
        $existing = Get-ADUser -Filter "SamAccountName -eq '$candidate'" -Properties DistinguishedName -ErrorAction SilentlyContinue
        if (-not $existing) { break }                     # available
        if ($existing.DistinguishedName -eq $currentDistinguishedName) { break } # belongs to same account
        # need suffix - ensure room for digits (max 20)
        $suffix = "$i"
        $maxBaseLen = 20 - $suffix.Length
        $truncated = if ($base.Length -gt $maxBaseLen) { $base.Substring(0,$maxBaseLen) } else { $base }
        $candidate = "$truncated$suffix"
        $i++
        if ($i -gt 9999) { throw "Unable to find unique sAMAccountName for base '$base' after 9999 attempts." }
    }
    return $candidate
}
if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
    write_log_message "ActiveDirectory module not available. Run this on a domain-joined host with RSAT/AD PowerShell installed." -level Error
    exit 1
}
Import-Module ActiveDirectory -ErrorAction Stop

# Find accounts with pre-2000 style names (handle optional leading $)
$filter = "SamAccountName -like '`$*' -and serialNumber -eq 'Synced from HiBob'"
$users = Get-ADUser -Filter $filter -Properties SamAccountName,UserPrincipalName,Mail,GivenName,Surname,DisplayName,serialNumber -ResultSetSize $null

if (-not $users -or $users.Count -eq 0) {
    write_log_message "No accounts found matching pre-2000 pattern." -level Info
    exit 0
}

write_log_message "Found $($users.Count) account(s) to evaluate." -level Info


$changes = @()

foreach ($u in $users) {
    $currentSam = $u.SamAccountName
    # prefer userPrincipalName, then mail
    $src = $u.UserPrincipalName
    if (-not $src) { $src = $u.Mail }
    if (-not $src) {
        write_log_message "Skipping $($u.DistinguishedName): no UserPrincipalName or Mail to derive username." -level Warning
        continue
    }

    $localPart = $src.Split('@')[0]
    if (-not $localPart) {
        write_log_message "Skipping $($u.DistinguishedName): could not parse local part from '$src'." -level Warning
        continue
    }

    $base = Get-CandidateSam -raw $localPart
    if (-not $base) {
        write_log_message "Skipping $($u.DistinguishedName): candidate username empty after normalization." -level Warning
        continue
    }

    $newSam = Get-UniqueSam -base $base -currentDistinguishedName $u.DistinguishedName

    if ($newSam -eq $currentSam) {
        write_log_message "No change for $($u.SamAccountName) (already matches desired '$newSam')." -level Info
        continue
    }

    $changes += [PSCustomObject]@{
        DistinguishedName = $u.DistinguishedName
        CurrentSam = $currentSam
        ProposedSam = $newSam
        UPN = $u.UserPrincipalName
    }

    if ($WhatIf) {
        write_log_message "WhatIf: Would set sAMAccountName for '$($u.DistinguishedName)' from '$currentSam' => '$newSam'" -level Info
    } else {
        try {
            Set-ADUser -Identity $u -SamAccountName $newSam -ErrorAction Stop
            write_log_message "Updated sAMAccountName for '$($u.DistinguishedName)' from '$currentSam' => '$newSam'" -level Success
        } catch {
            Write-Error "Failed to update $($u.DistinguishedName): $($_.Exception.Message)" -level Error
        }
    }
}

write_log_message "Processed $($users.Count) accounts. Proposed/Applied changes: $($changes.Count)" -level Info
if ($changes.Count -gt 0) {
    $changes | Format-Table -AutoSize
}