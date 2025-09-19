function download_file {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri,
        [string]$Destination = "$env:TEMP\$(Split-Path $Uri -Leaf)",
        [int]$MaxTries = 3,
        [string]$ProgressPreference = "SilentlyContinue"
    )

    $fileName = [System.IO.Path]::GetFileName($Uri)
    $attempt = 0
    $success = $false

    Write-Host "Starting download of $fileName from $Uri to $Destination" -ForegroundColor Cyan
    while (-not $success -and $attempt -lt $MaxTries) {
        try {
            $attempt++
            Invoke-WebRequest -Uri $Uri -OutFile $Destination -ErrorAction Stop
            Write-Host "Download succeeded on attempt $($attempt): $Destination" -ForegroundColor Green
            $success = $true
        } catch {
            Write-Host "Download failed on attempt $($attempt): $($_.Exception.Message)" -ForegroundColor Yellow
            Start-Sleep -Seconds 2
        }
    }

    if (-not $success) {
        Write-Host "Failed to download file after $MaxTries attempts." -ForegroundColor Red
        return $false
    }
    return $Destination
}