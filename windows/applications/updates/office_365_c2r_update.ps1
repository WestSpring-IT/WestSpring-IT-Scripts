<#
.SYNOPSIS
    Automates the update process for Microsoft Office Click-To-Run installations, determining update channel priority and initializing the update client.

.DESCRIPTION
    This script checks if Microsoft Office is installed as a Click-To-Run application and retrieves update channel information from various registry locations.
    It determines the priority of update channels, constructs the appropriate arguments, and launches the OfficeC2RClient.exe to initiate the update process.
    The script also provides detailed output regarding the update channel configuration and the status of the update initialization.

.PARAMETER Show_update_dialog
    Specifies whether to display the update dialog to the user. Accepts 'yes', 'no', or empty string. Default is $true.

.PARAMETER force_application_close
    Specifies whether to force close Office applications during the update. Accepts 'yes', 'no', or empty string. Default is $false.

.FUNCTIONS
    test_value
        Returns the input value or 'Not set' if the value is null or empty.

    get_input_value
        Converts user input to boolean values based on 'yes' or 'no', or returns the default value.

.NOTES
    - Only applicable to Office Click-To-Run installations.
    - Provides feedback if Office is installed via Windows Installer or if required files/paths are missing.
    - Maps update channel registry values to friendly names using a predefined list.

.EXAMPLE
    .\office_365_c2r_update.ps1 -Show_update_dialog "yes" -force_application_close "no"

    Runs the script, displaying the update dialog and not forcing application closure.

#>
function test_value {
    param (
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Value
    )
    if ([string]::IsNullOrEmpty($Value)) {
        $Value = 'Not set'
    }
    return $Value
}

function get_input_value {
    param (
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Value,
        [Parameter(Mandatory)]
        [bool]$DefaultValue
    )
    if ([string]::IsNullOrEmpty($Value)) { return $DefaultValue }
    $Value = $Value.Trim(' ', "'", '"').ToLower()
    switch ($Value) {
        'yes' { return $true }
        'no' { return $false }
        Default { return $DefaultValue }
    }
}


$Show_update_dialog = "{[show_update_dialog]}"
$force_application_close = "{[force_application_close]}"

$Host.UI.WriteLine("The script is running with the following parameters: Show update dialog - $Show_update_dialog, Force application close - $force_application_close.")

$displayLevel = get_input_value -Value $Show_update_dialog -DefaultValue $true
$forceAppShutdown = get_input_value -Value $force_application_close -DefaultValue $false

$displayLevel = 'displaylevel=' + ([string]$displayLevel).ToLower()
$forceAppShutdown = 'forceappshutdown=' + ([string]$forceAppShutdown).ToLower()

$c2rRegPath = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration" -ErrorAction SilentlyContinue

if ($null -eq $c2rRegPath) {
    $Host.UI.WriteLine("Microsoft Office is installed using Windows Installer, not as a Click-To-Run application. Please use Action1 Deploy Update policy to install the latest updates.")
    return
}

if ([string]::IsNullOrEmpty($c2rRegPath.ClientFolder)) {
    $Host.UI.WriteLine("The Click-To-Run directory is not specified in the registry.")
    return
}

if (-not(Test-Path -Path $c2rRegPath.ClientFolder -PathType Container)) {
    $Host.UI.WriteLine("The Click-To-Run directory does not exist.")
    return
}

$updateChannelsObject = @(
    [PSCustomObject]@{ 'Name' = 'Current Channel'; 'Policy Name' = 'Current'; 'GUID' = '492350f6-3a01-4f97-b9c0-c7c6ddf67d60' },
    [PSCustomObject]@{ 'Name' = 'Current Channel (Preview)'; 'Policy Name' = 'FirstReleaseCurrent'; 'GUID' = '64256afe-f5d9-4f86-8936-8840a6a4f5be' },
    [PSCustomObject]@{ 'Name' = 'Monthly Enterprise Channel'; 'Policy Name' = 'MonthlyEnterprise'; 'GUID' = '55336b82-a18d-4dd6-b5f6-9e5095c314a6' },
    [PSCustomObject]@{ 'Name' = 'Semi-Annual Enterprise Channel'; 'Policy Name' = 'Deferred'; 'GUID' = '7ffbc6bf-bc32-4f92-8982-f9dd17fd3114' },
    [PSCustomObject]@{ 'Name' = 'Semi-Annual Enterprise Channel (Preview)'; 'Policy Name' = 'FirstReleaseDeferred'; 'GUID' = 'b8f9b850-328d-4355-9145-c59439a0c4cf' },
    [PSCustomObject]@{ 'Name' = 'Beta Channel'; 'Policy Name' = 'InsiderFast'; 'GUID' = '5440fd1f-7ecb-4221-8110-145efaa6372f' }
)

$cloudUCRegPath = 'HKLM:\SOFTWARE\Policies\Microsoft\cloud\office\16.0\Common\officeupdate'
$policyUCRegPath = 'HKLM:\SOFTWARE\Policies\Microsoft\office\16.0\Common\officeupdate'
$odtUCRegPath = 'HKLM:\SOFTWARE\Microsoft\office\ClickToRun\Configuration'
$unmanagedUCRegPath = 'HKLM:\SOFTWARE\Microsoft\office\ClickToRun\Configuration'

$cloudUC = Get-ItemProperty -Path $cloudUCRegPath -ErrorAction SilentlyContinue
$policyUC = Get-ItemProperty -Path $policyUCRegPath -ErrorAction SilentlyContinue
$odtUC = Get-ItemProperty -Path $odtUCRegPath -ErrorAction SilentlyContinue
$unmanagedUC = Get-ItemProperty -Path $unmanagedUCRegPath -ErrorAction SilentlyContinue

$1Priority = test_value -Value $cloudUC.UpdatePath
$2PriorityRaw = test_value -Value $cloudUC.UpdateBranch
$3Priority = test_value -Value $policyUC.UpdatePath
$4PriorityRaw = test_value -Value $policyUC.UpdateBranch
$5Priority = test_value -Value $odtUC.UpdateUrl
$6Priority = test_value -Value $odtUC.UpdatePath
$7Priority = test_value -Value $unmanagedUC.UnmanagedUpdateURL
$8PriorityRaw = test_value -Value $unmanagedUC.CDNBaseUrl
if ($8PriorityRaw.Contains('http://') -or $8PriorityRaw.Contains('https://')) {
    $8PriorityRaw = $8PriorityRaw -split '/' | Select-Object -Last 1
}

$2Priority = ($updateChannelsObject | Where-Object { $_.'Policy Name' -eq $2PriorityRaw } | Select-Object Name).Name
if ([string]::IsNullOrEmpty($2Priority)) { $2Priority = $2PriorityRaw }
$4Priority = ($updateChannelsObject | Where-Object { $_.'Policy Name' -eq $4PriorityRaw } | Select-Object Name).Name
if ([string]::IsNullOrEmpty($4Priority)) { $4Priority = $4PriorityRaw }
$8Priority = ($updateChannelsObject | Where-Object { $_.GUID -eq $8PriorityRaw } | Select-Object Name).Name
if ([string]::IsNullOrEmpty($8Priority)) { $8Priority = $8PriorityRaw }

$array = @($1Priority, $2Priority, $3Priority, $4Priority, $5Priority, $6Priority, $7Priority, $8Priority)

$priorityString = ''
foreach ($item in $array) {
    if ($item -ne 'Not set') {
        $priorityString += $item
    }
}

$Host.UI.WriteLine("The Click-To-Run update channel priority: $priorityString.")

$c2rExecutable = 'OfficeC2RClient.exe'
$c2rFullPath = Join-Path -Path $c2rRegPath.ClientFolder -ChildPath $c2rExecutable -ErrorAction SilentlyContinue

if (-not(Test-Path -Path $c2rFullPath -PathType Leaf)) {
    $Host.UI.WriteLine("The Click-To-Run executable file does not exist.")
    return
}

$argumentList = '/update user', $forceAppShutdown, $displayLevel -join ' '

$c2rProc = Start-Process $c2rFullPath -ArgumentList $argumentList -Wait -PassThru -ErrorAction SilentlyContinue

if ($c2rProc.ExitCode -eq 0) {
    $Host.UI.WriteLine("The update process of Microsoft Office is initialized.")
}
else {
    $Host.UI.WriteLine("The update process returned an error $($c2rProc.ExitCode).")
}
