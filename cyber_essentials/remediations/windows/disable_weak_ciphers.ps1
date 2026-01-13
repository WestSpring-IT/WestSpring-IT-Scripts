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
[int]$Global:I = 0

# Function to disable a cipher
function disable_cipher {
    param (
        [string]$cipher
    )
    $regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Ciphers\$cipher"
    if (-Not (Test-Path $regPath)) {
        New-Item -Path $regPath -Force | Out-Null
    }
    try {
        Set-ItemProperty -Path $regPath -Name "Enabled" -Value 0
        Write-Output "$cipher cipher has been disabled."
        $Global:I++
    }
    catch {
        Write-Output "Failed to disable $cipher cipher: $_"
    } 
    
}

# Disable each cipher
foreach ($cipher in $ciphers) {
    disable_cipher -cipher $cipher
}

Write-Host " $($Global:I)/$(($ciphers | Measure-Object).Count) specified ciphers have been disabled."