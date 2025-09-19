# Define the ciphers to disable
$ciphers = @(
    "DES 56/56",
    "Triple DES 168",
    "IDEA 128/128",
    "RC2 128/128",
    "RC4 128/128",
    "RC4 56/128",
    "RC4 40/128"
)

# Function to disable a cipher
function Disable-Cipher {
    param (
        [string]$cipher
    )
    $regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Ciphers\$cipher"
    if (-Not (Test-Path $regPath)) {
        New-Item -Path $regPath -Force | Out-Null
    }
    Set-ItemProperty -Path $regPath -Name "Enabled" -Value 0
    Write-Output "$cipher cipher has been disabled."
}

# Disable each cipher
foreach ($cipher in $ciphers) {
    Disable-Cipher -cipher $cipher
}

Write-Host "All specified ciphers have been disabled."