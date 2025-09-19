function remove_appx_package {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackageName
    )

    $packages = Get-AppxPackage -AllUsers | Where-Object { $_.Name -eq $PackageName }
    if ($packages.Count -eq 0) {
        Write-Host "No packages found with name: $PackageName" -ForegroundColor Yellow
        return
    }

    foreach ($pkg in $packages) {
        Write-Host "Removing package: $($pkg.Name) for user SID: $($pkg.PackageUserInformation.UserSecurityId)" -ForegroundColor Cyan
        Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction
    }
}