param(
    [Parameter(Mandatory = $false, ValueFromRemainingArguments = $true)]
    [string[]]$filePath = "{[filePaths]}"
)

function expand_cmd_path {
    param([string]$Path)
    if (-not $Path) { return $Path }
    $p = $Path.Trim()
    # Expand %ENV% style variables
    try {
        $expanded = [Environment]::ExpandEnvironmentVariables($p)
    }
    catch {
        $expanded = $p
    }
    # Expand leading ~ to user profile
    if ($expanded -like '~*') {
        $expanded = $expanded -replace '^~', $env:USERPROFILE
    }
    return $expanded
}

$expandedPaths = @()
foreach ($p in $filePath) {
    $ep = expand_cmd_path -Path $p
    if ($ep) { $expandedPaths += $ep }
}

Write-Host "Getting Versioninfo for the following expanded path(s): $($expandedPaths -join ', ')"

# Resolve to files using Get-ChildItem so wildcards are handled and multiple matches returned
$filesFound = @()
foreach ($p in $expandedPaths) {
    try {
        $items = Get-ChildItem -Path $p -ErrorAction SilentlyContinue -Force
        if ($items) { $filesFound += $items | Where-Object { -not $_.PSIsContainer } }
    } catch {}
}

if ($filesFound.Count -lt 1) {
    Write-Host "No files found for the given file path(s): $($filePath -join ', ')"
} else {
    foreach ($x in $filesFound) {
        Write-host "----"
        Write-Host "File: $($x.Versioninfo.OriginalFilename)"
        Write-Host "File location: $($x.Versioninfo.FileName)"
        Write-Host "Version info: $($x.Versioninfo.FileVersion)"
    }
}