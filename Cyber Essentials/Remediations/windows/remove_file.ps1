function remove_file {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath
    )

    # Resolve wildcards for directories
    $resolvedDirs = Get-ChildItem -Path $FilePath -Directory -ErrorAction SilentlyContinue

    foreach ($dir in $resolvedDirs) {
        Write-Host "Removing directory: $($dir.FullName)" -ForegroundColor Magenta
        Remove-Item -Path $dir.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }

    # Resolve wildcards for files
    $resolvedFiles = Get-ChildItem -Path $FilePath -File -ErrorAction SilentlyContinue

    foreach ($file in $resolvedFiles) {
        Write-Host "Removing file: $($file.FullName)" -ForegroundColor Cyan
        Remove-Item -Path $file.FullName -Force -ErrorAction SilentlyContinue
    }

    if ($resolvedDirs.Count -eq 0 -and $resolvedFiles.Count -eq 0) {
        Write-Host "No files or directories found matching: $FilePath" -ForegroundColor Yellow
    }
}