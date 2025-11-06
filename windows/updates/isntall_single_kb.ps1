<#
.SYNOPSIS
    Download and install a single Microsoft update (MSU or CAB) from either a direct URL or a KB number.

.DESCRIPTION
    - Accepts either a direct download URL or a KB number (e.g. KB5006670).
    - If a KB is provided, tries to retrieve download links from Microsoft Update Catalog using an Internet Explorer COM automation fallback.
    - Downloads the chosen file and installs it silently without forcing a reboot.
    - Handles MSU and CAB packages specially (wusa.exe for MSU, DISM for CAB).
    - Performs a quick "already installed?" check before and after install.
    - Requires elevated (Administrator) privileges.

.PARAMETER kbInput
    A full download URL or a KB id (e.g. KB5006670 or 5006670).

.PARAMETER OutDir
    Directory to place downloaded files. Defaults to user's temp folder.

.PARAMETER TimeoutSeconds
    Timeout for web requests/downloads. Default 300 seconds.

.EXAMPLE
    .\install_single_kb.ps1 -Input KB5006670
    .\install_single_kb.ps1 -Input "https://download.windowsupdate.com/..." -OutDir C:\Temp

.NOTES
    - Uses Internet Explorer COM to query the Microsoft Update Catalog when given a KB. This works on Windows systems that have IE and COM support.
    - If automatic catalog retrieval fails, the script will prompt for a direct download URL.
#>

param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$kbInput,

    [Parameter(Mandatory=$false)]
    [string]$OutDir = $env:TEMP,

    [Parameter(Mandatory=$false)]
    [int]$TimeoutSeconds = 300
)


# Normalize KB id like '5006670' => 'KB5006670'
function normalise_kb {
    param([string]$kb)
    if ($kb -match '^(KB)?(\d+)$') {
        return ('KB' + $Matches[2])
    }
    return $null
}

# Quick check if KB is installed (tries multiple ways)
function test_kb_installed {
    param([string]$kb)

    if (-not $kb) { return $false }

    # Try Get-HotFix
    try {
        $hf = Get-HotFix -Id $kb -ErrorAction SilentlyContinue
        if ($hf) { return $true }
    } catch {}

    # WMI/Win32_QuickFixEngineering
    try {
        $qfe = Get-WmiObject -Class Win32_QuickFixEngineering -Filter "HotFixID='$kb'" -ErrorAction SilentlyContinue
        if ($qfe) { return $true }
    } catch {}

    # DISM package list (covers feature packs and some updates)
    try {
        $dismOut = & dism /online /get-packages 2>$null
        if ($dismOut -and ($dismOut -match [regex]::Escape($kb))) { return $true }
    } catch {}

    return $false
}

# Download a file (uses BITS if available for reliability)
function download_file {
    <#
        .SYNOPSIS
        Downloads a file from a specified URI with retry logic and returns download details.

        .DESCRIPTION
        The download_file function downloads a file from the provided URI to a specified fullPath path.
        It follows redirects to get the actual download URL, supports retrying the download on failure,
        and returns an object containing file details such as name, fullPath, size, and download time.

        .PARAMETER Uri
        The URI of the file to download. This parameter is mandatory.

        .PARAMETER fileName
        The name of the downloaded file. If not specified, defaults to the name extracted from the URI.

        .PARAMETER fullPath
        The path where the downloaded file will be saved. If not specified, defaults to the TEMP path.

        .PARAMETER MaxTries
        The maximum number of download attempts in case of failure. Defaults to 3.

        .PARAMETER ProgressPreference
        Specifies how progress is displayed during download. Defaults to "SilentlyContinue".

        .OUTPUTS
        [PSCustomObject]
        Returns an object with the following properties:
        - fileName: Name of the downloaded file.
        - fullPath: Path of the downloaded file.
        - fileSize: Size of the downloaded file in megabytes.
        - totalTime: Time taken to complete the download in seconds.

        .EXAMPLE
        download_file -Uri "https://example.com/file.zip" -fullPath "C:\Downloads\file.zip"

        .EXAMPLE
        download_file -Uri "https://example.com/file.zip"

        .EXAMPLE
        $result = download_file -Uri "https://example.com/file.zip" -MaxTries 5
        Write-Host "Downloaded file size: $($result.fileSize) MB"

        .NOTES
        Requires PowerShell 5.0 or later.
        #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri,
        [string]$fileName,
        [string]$filePath = "$env:TEMP",
        [int]$MaxTries = 3,
        [string]$ProgressPreference = "SilentlyContinue"
    )

    # If no filename provided, extract from final redirected URL
    if (-not $fileName) {
        $Link = [System.Net.HttpWebRequest]::Create($Uri).GetResponse().ResponseUri.AbsoluteUri
        $fileName = [uri]::UnescapeDataString($Link) | Split-Path -Leaf
    }
    # Create target path if it doesn't exist
    if (!(Test-Path -Path $filePath)) {
        try {
            New-Item -ItemType Directory -Path $filePath | Out-Null
        }
        catch {
            Write-Host "Failed to create path $($filePath): $($_.Exception.Message)" -ForegroundColor Red
            return $false
        }
    }

    # Ensure fullPath uses the provided or derived filename
    $fullPath = Join-Path -Path $filePath -ChildPath $fileName

    # Set TLS 1.2 for secure downloads
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $attempt = 0
    $success = $false
    $startTime = Get-Date -Format "HH:mm:ss"


    
    Write-Host "Starting download of $fileName from $Uri to $fullPath" -ForegroundColor Cyan
    while (-not $success -and $attempt -lt $MaxTries) {
        try {
            $attempt++
            Invoke-WebRequest -Uri $Uri -OutFile $fullPath -ErrorAction Stop
            Write-Host "Download succeeded on attempt $($attempt): $fullPath" -ForegroundColor Green
            $success = $true
        }
        catch {
            Write-Host "Download failed on attempt $($attempt): $($_.Exception.Message)" -ForegroundColor Yellow
            Start-Sleep -Seconds 2
        }
    }
    $endTime = Get-Date -Format "HH:mm:ss"
    $totalTime = (New-TimeSpan -Start $startTime -End $endTime).TotalSeconds
    if (-not $success) {
        Write-Host "Failed to download file after $MaxTries attempts." -ForegroundColor Red
        $result = [PSCustomObject]@{
            success   = $false
            fileName  = $fileName
            fullPath  = $fullPath
            fileSize  = [math]::Round((Get-Item $fullPath).Length / 1MB, 4)
            totalTime = [math]::Round($totalTime, 2)
        } 
    }
    else {
        $result = [PSCustomObject]@{
            success   = $true
            fileName  = $fileName
            fullPath  = $fullPath
            fileSize  = [math]::Round((Get-Item $fullPath).Length / 1MB, 4)
            totalTime = [math]::Round($totalTime, 2)
        }
    }
    return $result

}

# Attempt to extract download links from Microsoft Update Catalog using IE COM automation
## currently not working, so will need to provide the full uri for now
function get_update_catalog_links {
    param([string]$kb)

    Write-Output "Attempting to retrieve download links from Microsoft Update Catalog for $kb ..."
    $ie = $null
    try {
        $ie = New-Object -ComObject InternetExplorer.Application
        $searchUrl = "https://www.catalog.update.microsoft.com/Search.aspx?q=$kb"
        $ie.Navigate2($searchUrl)
        $ie.Visible = $false

        $sw = [DateTime]::UtcNow.AddSeconds(30)
        while (($ie.Busy -or $ie.ReadyState -ne 4) -and ([DateTime]::UtcNow -lt $sw)) { Start-Sleep -Milliseconds 300 }
        Start-Sleep -Milliseconds 500

        # Try clicking the page 'Download' button (if present) which opens the download dialog/window
        try {
            $downloadBtn = $ie.Document.getElementsByTagName('a') | Where-Object { $_.innerText -and ($_.innerText.Trim() -eq 'Download') } | Select-Object -First 1
            if ($downloadBtn) {
                $downloadBtn.click()
                Start-Sleep -Milliseconds 800
            }
        } catch {}

        # Prefer using the IHTMLDocument2_links collection (works for the catalog download dialog)
        $links = @()
        try {
            $docLinks = $ie.Document.IHTMLDocument2_links
            if ($docLinks) {
                foreach ($l in $docLinks) {
                    try {
                        if ($l.href -and ($l.href -match 'download.windowsupdate.com')) { $links += $l.href }
                    } catch {}
                }
            }
        } catch {}

        # If none found, attempt to page through search results to trigger download UI or find embedded links
        if ($links.Count -eq 0) {
            try {
                $next = $ie.Document.getElementById("ctl00_catalogBody_nextPageLinkText")
                $pageAttempts = 0
                while ($next -and $pageAttempts -lt 3 -and $links.Count -eq 0) {
                    $next.click()
                    Start-Sleep -Milliseconds 800
                    # scan current document links quickly
                    try {
                        $docLinks = $ie.Document.IHTMLDocument2_links
                        foreach ($l in $docLinks) {
                            try { if ($l.href -and ($l.href -match 'download.windowsupdate.com')) { $links += $l.href } } catch {}
                        }
                    } catch {}
                    $pageAttempts++
                    $next = $ie.Document.getElementById("ctl00_catalogBody_nextPageLinkText")
                }
            } catch {}
        }

        # If still nothing, scan other IE windows (download dialog often opens a separate IE window)
        if ($links.Count -eq 0) {
            try {
                $shell = New-Object -ComObject "Shell.Application"
                $sw2 = [DateTime]::UtcNow.AddSeconds(15)
                while ([DateTime]::UtcNow -lt $sw2 -and $links.Count -eq 0) {
                    $wins = $shell.Windows()
                    foreach ($w in $wins) {
                        try {
                            if ($w -and $w.Document) {
                                try {
                                    $wlinks = $w.Document.IHTMLDocument2_links
                                    foreach ($wl in $wlinks) {
                                        try { if ($wl.href -and ($wl.href -match 'download.windowsupdate.com')) { $links += $wl.href } } catch {}
                                    }
                                } catch {}
                            }
                        } catch {}
                    }
                    if ($links.Count -gt 0) { break }
                    Start-Sleep -Milliseconds 300
                }
            } catch {}
        }

        try { if ($ie) { $ie.Quit() } } catch {}

        if ($links.Count -gt 0) { return $links | Select-Object -Unique }
        Write-Warning "Failed to discover download links from the catalog page."
        return $null
    } catch {
        Write-Warning "Catalog retrieval failed: $_"
        try { if ($ie) { $ie.Quit() } } catch {}
        return $null
    } finally {
        try { [System.Runtime.Interopservices.Marshal]::ReleaseComObject($ie) | Out-Null } catch {}
        try { [System.GC]::Collect(); [System.GC]::WaitForPendingFinalizers() } catch {}
    }
}

# Install functions for MSU and CAB
function install_msu {
    param([string]$Path)
    Write-Output "Installing MSU: $Path (quiet, no restart)"
    $psi = Start-Process -FilePath "$env:windir\System32\wusa.exe" -ArgumentList "`"$Path`" /quiet /norestart" -Wait -PassThru -NoNewWindow
    return $psi.ExitCode
}

function install_cab {
    param([string]$Path)
    Write-Output "Installing CAB via DISM: $Path (quiet, no restart)"
    $arguments = "/online /add-package /packagepath:`"$Path`" /quiet /norestart"
    $psi = Start-Process -FilePath "$env:SystemRoot\System32\dism.exe" -ArgumentList $arguments -Wait -PassThru -NoNewWindow
    return $psi.ExitCode
}

function extract_kb_from_string {
    param([string]$s)
    if (-not $s) { return $null }

    # Prefer explicit "KB" matches, case-insensitive
    if ($s -match '(?i)\bKB(\d{4,7})\b') { return "KB$($matches[1])" }

    # Common filename patterns: windows10.0-kb5006670-x64.msu or -kb5006670-
    if ($s -match '(?i)[-_]kb[-_]?(\d{4,7})') { return "KB$($matches[1])" }

    # Fallback: numeric segment in URL that looks like a KB number (/1234567/). Less reliable.
    if ($s -match '/(\d{4,7})(?:/|$)') { return "KB$($matches[1])" }

    return $null
}


## MAIN ##
# Ensure running elevated
# Determine if input is URL or KB
$isUrl = $kbInput -match '^https?://'
$kb = $null
$downloadUrl = $null

if ($isUrl) {
    $downloadUrl = $kbInput
} else {
    $kb = normalise_kb -kb $kbInput
    if (-not $kb) {
        Write-Host "Unable to parse input as a KB id or URL: $kbInput" -ForegroundColor Red
        exit 2
    }

    Write-Host "Normalized KB: $kb"

    # Quick pre-check: is KB already installed?
    if (test_kb_installed -kb $kb) {
        Write-Host "$kb already appears to be installed. Exiting." -ForegroundColor Green
        exit 0
    }

    # Get system info for compatibility checks
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem
        $osCaption = $os.Caption
        $osVersion = $os.Version
        $osArch = $os.OSArchitecture    # e.g. "64-bit"
    } catch {
        $osCaption = "Unknown"
        $osVersion = "0.0"
        $osArch = if ($env:PROCESSOR_ARCHITECTURE -match '64') { '64-bit' } else { '32-bit' }
    }
    Write-Host "System: $osCaption ($osVersion) Architecture: $osArch"

    # Try to retrieve catalog links
    $links = get_update_catalog_links -kb $kb
    if ($links -and $links.Count -gt 0) {
        Write-Host "Found $($links.Count) candidate download link(s) from Update Catalog."
        # Prefer link that matches architecture
        $preferredKeyword = if ($osArch -match '64') { 'x64','amd64','x86_64' } else { 'x86','wow' }
        $selected = $null
        foreach ($kw in $preferredKeyword) {
            $selected = $links | Where-Object { $_ -match $kw } | Select-Object -First 1
            if ($selected) { break }
        }
        if (-not $selected) {
            # try arm64
            $selected = $links | Where-Object { $_ -match 'arm64' } | Select-Object -First 1
        }
        if (-not $selected) {
            # fallback to first
            $selected = $links[0]
        }

        $downloadUrl = $selected
        Write-Host "Selected download URL: $downloadUrl"
    } else {
        Write-Warning "Could not retrieve download links automatically for $kb."
        $resp = Read-Host "Please paste a direct download URL for $kb (or press Enter to abort)"
        if ([string]::IsNullOrWhiteSpace($resp)) {
            Write-Host "No download URL provided. Aborting." -ForegroundColor Yellow
            exit 3
        }
        $downloadUrl = $resp.Trim()
    }
}


# If a direct URL was provided, try to extract a KB id and test installation before downloading
if ($isUrl -and $downloadUrl) {
    $kbFromUrl = extract_kb_from_string -s $downloadUrl
    if ($kbFromUrl) {
        Write-Host "Derived KB id from URL: $kbFromUrl"
        if (test_kb_installed -kb $kbFromUrl) {
            Write-Host "$kbFromUrl already appears to be installed. Skipping download/install." -ForegroundColor Green
            exit 0
        } else {
            Write-Host "$kbFromUrl not detected as installed. Proceeding with download/install." -ForegroundColor Cyan
            # Also set $kb so later verification after install will check this KB
            $kb = $kbFromUrl
        }
    } else {
        Write-Host "No KB id could be derived from the provided URL. Proceeding without pre-check." -ForegroundColor Yellow
    }
}

# Validate download URL
if (-not $downloadUrl) {
    Write-Host "No download URL available. Exiting." -ForegroundColor Red
    exit 4
}
if (-not ($downloadUrl -match '^https?://')) {
    Write-Host "Download URL does not appear to be valid: $downloadUrl" -ForegroundColor Red
    exit 5
}

# Derive filename
try {
    $uriObj = [System.Uri]::new($downloadUrl)
    $fileName = [System.Uri]::UnescapeDataString(($uriObj.Segments | Select-Object -Last 1))
    if (-not $fileName) {
        $fileName = "$($kb -replace '[^0-9A-Za-z\-]','')_update"
    }
} catch {
    $fileName = "$($kb -replace '[^0-9A-Za-z\-]','')_update"
}

# Ensure OutDir exists
if (-not (Test-Path -Path $OutDir)) {
    try { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null } catch {}
}

# Download the file
$dl = download_file -Uri $downloadUrl -fileName $fileName -filePath $OutDir -MaxTries 3
if (-not $dl -or -not $dl.success) {
    Write-Host "Download failed. Aborting." -ForegroundColor Red
    exit 6
}
$fullPath = $dl.fullPath
Write-Host "Downloaded to: $fullPath"

# Determine package type by extension
$ext = [IO.Path]::GetExtension($fullPath).ToLowerInvariant()
if ($ext -eq '.msu') {
    Write-Host "Detected MSU package."
    $exitCode = install_msu -Path $fullPath
} elseif ($ext -eq '.cab') {
    Write-Host "Detected CAB package."
    $exitCode = install_cab -Path $fullPath
} else {
    # Some catalog downloads are wrapped (e.g. .exe or .msu disguised). Try to inspect file header for MSU (PKG?) fallback to MSU or prompt user.
    Write-Host "Unknown file extension: $ext. Attempting to handle as MSU first."
    $exitCode = install_msu -Path $fullPath
    if ($exitCode -ne 0) {
        Write-Host "MSU installer failed (exit $exitCode). Trying DISM CAB install as fallback."
        $exitCode = install_cab -Path $fullPath
    }
}

Write-Host "Installer returned exit code: $exitCode"

# Wait a short time and re-check installation state if we had a KB value
if ($kb) {
    Start-Sleep -Seconds 6
    if (test_kb_installed -kb $kb) {
        Write-Host "$kb appears to be installed after installation." -ForegroundColor Green
        exit 0
    } else {
        Write-Host "$kb does not appear to be installed after installation." -ForegroundColor Yellow
        exit 7
    }
} else {
    # If we installed from a direct URL and no KB known, try to infer KB id from filename and check; otherwise just return exit code
    Write-Host "No KB id provided to verify installation. Installer exit code: $exitCode"
    exit $exitCode
}

