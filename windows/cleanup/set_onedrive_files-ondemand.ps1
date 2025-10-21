$hiveRoot = "Registry::HKEY_USERS"
$providerKey = "Software\SyncEngines\Providers\OneDrive"

$loadedSIDs = Get-ChildItem $hiveRoot | Where-Object { $_.Name -match 'S-\d-\d+-(\d+-){1,14}\d+$' }

foreach ($sid in $loadedSIDs) {
    $userHive = $sid.PSChildName
    $fullProviderKey = "$hiveRoot\$userHive\$providerKey"
    if (Test-Path $fullProviderKey) {
        Get-ChildItem $fullProviderKey | ForEach-Object {
            $mountPoint = (Get-ItemProperty $_.PSPath).MountPoint
            if ($mountPoint -and (Test-Path $mountPoint)) {
                Write-Host "Setting Files On-Demand for synced folder: $mountPoint" -ForegroundColor Green
                try {
                    $files = Get-ChildItem $mountPoint -Force -File -Recurse -ErrorAction SilentlyContinue | `
                    Where-Object { ($_.Attributes -match 'ReparsePoint' -or $_.Attributes -eq '525344') `
                    -and ($_.Name -notlike "*.url") `
                    -and ($_.PSIsContainer -eq $false) }
                    foreach ($file in $files) {
                        if ($file.Attributes -match 'Hidden' -or $file.Attributes -match 'System') {
                            Write-Host "Not resetting hidden/system file - $($file.FullName)"
                            continue
                        }
                        try {
                            Write-Host "Setting attributes for file - $($file.FullName)"
                            attrib.exe +U -P "`"$($file.FullName)`""
                        }
                        catch {
                            Write-Host "Failed to set attributes for file - $($file.FullName). Error: $($_.Exception.Message)" -ForegroundColor Red
                        } 
                    }
                    Write-Host "Successfully set Files On-Demand for: $mountPoint"
                } catch {
                    Write-Host "Failed to set Files On-Demand for: $mountPoint. Error: $($_.Exception.Message)" -ForegroundColor Red
                }
            }
        }
    }
}