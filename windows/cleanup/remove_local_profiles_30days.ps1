$profiles = Get-CimInstance -ClassName Win32_UserProfile | Where-Object { $_.Special -eq $false }
$profileList = @()

foreach ($x in $profiles) {
    $sid = $x.SID
    $localPath = $x.LocalPath
    $lastUseTime = $null

    if ($x.LastUseTime) {
        try {
            $lastUseTime = [System.Management.ManagementDateTimeConverter]::ToDateTime($x.LastUseTime)
        } catch {
            $lastUseTime = $null
        }
    }

    # Try to resolve the username from the SID
    try {
        $ntAccount = (New-Object System.Security.Principal.SecurityIdentifier($sid)).Translate([System.Security.Principal.NTAccount]).Value
    } catch {
        $ntAccount = $sid
    }

    # Check NTUSER.DAT LastWriteTime
    $ntuserPath = Join-Path $localPath "NTUSER.DAT"
    $ntuserLastWrite = $null
    if (Test-Path $ntuserPath) {
        $ntuserLastWrite = (Get-Item $ntuserPath).LastWriteTime
    }

    $profileList += [PSCustomObject]@{
        Username        = $ntAccount
        SID             = $sid
        LocalPath       = $localPath
        LastUseTime     = $lastUseTime
        NTUserLastWrite = $ntuserLastWrite
    }
}

$profileList | Select Username, NTUserLastWrite | Sort-Object NTUserLastWrite | Format-Table -AutoSize