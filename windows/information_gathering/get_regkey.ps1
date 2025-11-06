param(
    [Parameter(Mandatory=$false, ValueFromRemainingArguments=$true)]
    [string[]]$Queries
)

function normalise_regpath {
    param([string]$path)
    if (-not $path) { return $null }
    # Accept forms like HKLM\...\Key or HKLM:\...\Key or HKEY_LOCAL_MACHINE\...\Key
    $p = $path.Trim()
    $p = $p -replace '^HKEY_LOCAL_MACHINE','HKLM'
    $p = $p -replace '^HKEY_CURRENT_USER','HKCU'
    $p = $p -replace '^HKEY_CLASSES_ROOT','HKCR'
    $p = $p -replace '^HKEY_USERS','HKU'
    $p = $p -replace '^HKEY_CURRENT_CONFIG','HKCC'

    if ($p -match '^[A-Za-z]{2,4}\\') {
        # convert HKLM\... => HKLM:\...
        $p = $p -replace '^([A-Za-z]{2,4})\\', '$1:\'
    }
    return $p
}

if (-not $Queries -or $Queries.Count -eq 0) {
    Write-Host "Usage: .\get_regkey.ps1 'HKLM\Path\To\Key ValueName' 'HKCU\Path\To\AnotherKey' ..."
    Write-Host "If ValueName is omitted, the script will list all values under the key."
    exit 0
}

foreach ($q in $Queries) {
    # Split into key and optional value name (max 2 parts to preserve spaces in valuename if any)
    $parts = $q -split '\s+',2
    $rawKey = $parts[0]
    $valueName = if ($parts.Count -gt 1) { $parts[1].Trim() } else { $null }

    $regPath = normalise_regpath -path $rawKey
    if (-not $regPath) {
        Write-Host "Invalid registry path: $rawKey" -ForegroundColor Yellow
        continue
    }

    try {
        if (-not (Test-Path -Path $regPath -ErrorAction SilentlyContinue)) {
            Write-Host "Registry key not found: $regPath" -ForegroundColor Yellow
            continue
        }

        if ($valueName) {
            try {
                $prop = Get-ItemProperty -Path $regPath -Name $valueName -ErrorAction Stop
                $val = $prop.$valueName
                Write-Host "$regPath` [$valueName] = $val"
            } catch {
                Write-Host "Value '$valueName' not found under $regPath" -ForegroundColor Yellow
            }
        }
        else {
            $props = Get-ItemProperty -Path $regPath -ErrorAction Stop
            Write-Host "Values under $regPath :"
            $props.PSObject.Properties |
                Where-Object { $_.Name -notmatch '^PS(Path|ParentPath|ChildName|Drive|Provider)$' } |
                ForEach-Object { Write-Host "  $($_.Name) = $($_.Value)" }
        }
    } catch {
        Write-Host "Error reading $regPath : $($_.Exception.Message)" -ForegroundColor Red
    }
}
