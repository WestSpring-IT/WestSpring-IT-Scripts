# Define the threshold for inactive profiles (30 days)
[int]$daysInactive = 30 
$thresholdDate = (Get-Date).AddDays(-$daysInactive)
# Define the path to the Teams folder inside user profiles
$teamsFolderSubPath = "AppData\Local\Microsoft\Teams"
# Specify admin accounts to always clear
#$adminAccounts = @("Administrator", "*admin*")

# Get all user profiles from Win32_UserProfile
$profiles = Get-CimInstance Win32_UserProfile | Where-Object {
    $_.Special -eq $false -and $_.LocalPath -match "C:\\Users\\"
}
foreach ($userProfile in $profiles) {
    try {
        $profilePath = $userProfile.LocalPath
        $profileName = Split-Path $profilePath -Leaf
        $lastLoginDate = $userProfile.LastUseTime

        # If LastUseTime is missing, treat as inactive and clear cache
        # OR if profile is in the adminAccounts array, always clear
        if (-not $lastLoginDate -or ($lastLoginDate -lt $thresholdDate) -or ($profileName -like "*admin*")) {
            $teamsFolderPath = Join-Path -Path $profilePath -ChildPath $teamsFolderSubPath
            if (Test-Path $teamsFolderPath) {
                Write-Host "------------------------"
                Write-Host "Clearing Teams cache for profile: $profilePath" -ForegroundColor Yellow
                Remove-Item -Path $teamsFolderPath -Recurse -Force -ErrorAction SilentlyContinue
            } else {
                Write-Host "No Teams cache found for profile: $profilePath" -ForegroundColor Gray
            }
        } else {
            Write-Host "Skipping active profile: $profilePath" -ForegroundColor Gray
        }
    }
    catch {
        Write-Host "Error processing profile $($userProfile.LocalPath): $_" -ForegroundColor Red
    }
}