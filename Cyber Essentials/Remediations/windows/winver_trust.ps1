if((Test-Path -LiteralPath "HKLM:\SOFTWARE\Microsoft\Cryptography\Wintrust\Config") -ne $true) {  New-Item "HKLM:\SOFTWARE\Microsoft\Cryptography\Wintrust\Config" -force -ea SilentlyContinue | Out-Null };
if((Test-Path -LiteralPath "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Cryptography\Wintrust\Config") -ne $true) {  New-Item "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Cryptography\Wintrust\Config" -force -ea SilentlyContinue | Out-Null };
try {
    New-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Cryptography\Wintrust\Config' -Name 'EnableCertPaddingCheck' -Value 1 -PropertyType String -Force -ea SilentlyContinue | Out-Null
    Write-Output "Successfully set EnableCertPaddingCheck in 64-bit registry path."
}
catch {
    Write-Error "Failed to set EnableCertPaddingCheck in 64-bit registry path: $_"
} 
try {
    New-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Cryptography\Wintrust\Config' -Name 'EnableCertPaddingCheck' -Value 1 -PropertyType String -Force -ea SilentlyContinue | Out-Null
    Write-Output "Successfully set EnableCertPaddingCheck in 32-bit registry path."
}
catch {
    Write-Error "Failed to set EnableCertPaddingCheck in 32-bit registry path: $_"
}
