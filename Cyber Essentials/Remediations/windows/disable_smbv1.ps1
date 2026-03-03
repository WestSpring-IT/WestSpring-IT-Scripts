$isEnabled = (Get-SmbServerConfiguration).EnableSMB1Protocol
if ($isEnabled) {
    Write-Host "SMBv1 is enabled. Disabling it now..." -ForegroundColor Yellow
    Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force
    Write-Host "SMBv1 has been disabled." -ForegroundColor Green
} else {
    Write-Host "SMBv1 is already disabled." -ForegroundColor Green
}