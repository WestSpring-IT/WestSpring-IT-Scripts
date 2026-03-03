# Define the list of Appx package *Names* (not PackageFullName)
$AppxPackage = ${Appx Package Name}

# 1) Remove installed instances for all users
$Packages = Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $AppxPackage }
if (-not $Packages) {
    Write-Host "`nNo installed Appx packages found for: $AppxPackage" -ForegroundColor Yellow
} else {
    foreach ($Package in $Packages) {
        try {
            Write-Output "`nAttempting to remove Appx package (installed): $($Package.PackageFullName)"
            Remove-AppxPackage -Package $Package.PackageFullName -AllUsers -ErrorAction Stop | Out-Null
            Write-Output "`nRemoved installed Appx package: $($Package.PackageFullName)"
        }
        catch {
            Write-Output "`nError removing installed Appx package '$($Package.PackageFullName)': $($_.Exception.Message)"
        }
    }
}
# 2) De-provision for new users (different inventory than installed apps)
try {
    $ProvMatches = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -eq $AppxPackage }
    if (-not $ProvMatches) {
        Write-Host "`nNo provisioned package found for: $AppxPackage" -ForegroundColor Yellow
    } else {
        foreach ($prov in $ProvMatches) {
            Write-Output "`nAttempting to de-provision: $($prov.DisplayName) [$($prov.PackageName)]"
            Remove-AppxProvisionedPackage -Online -PackageName $prov.PackageName -ErrorAction Stop | Out-Null
            Write-Output "`nDe-provisioned: $($prov.PackageName)"
        }
    }
}
catch {
    Write-Output "`nError de-provisioning '$AppxPackage': $($_.Exception.Message)"
}
