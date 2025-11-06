function get_update_catalog_links {
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )
    $kb = $Name.Replace("KB", "")
    $results = Invoke-WebRequest -Uri "http://www.catalog.update.microsoft.com/Search.aspx?q=KB$kb"
    $kbids = $results.InputFields |
    Where-Object { $_.type -eq 'Button' -and $_.Value -eq 'Download' } |
    Select-Object -ExpandProperty  ID

    Write-Verbose -Message "$kbids"

    if (-not $kbids) {
        Write-Warning -Message "No results found for $Name"
        return
    }

    $guids = $results.Links |
    Where-Object ID -match '_link' |
    Where-Object { $_.OuterHTML -match ( "(?=.*" + ( $Filter -join ")(?=.*" ) + ")" ) } |
    ForEach-Object { $_.id.replace('_link', '') } |
    Where-Object { $_ -in $kbids }

    if (-not $guids) {
        Write-Warning -Message "No file found for $Name"
        return
    }

    foreach ($guid in $guids) {
        Write-Verbose -Message "Downloading information for $guid"
        $post = @{ size = 0; updateID = $guid; uidInfo = $guid } | ConvertTo-Json -Compress
        $body = @{ updateIDs = "[$post]" }
        $links = Invoke-WebRequest -Uri 'http://www.catalog.update.microsoft.com/DownloadDialog.aspx' -Method Post -Body $body |
        Select-Object -ExpandProperty Content |
        Select-String -AllMatches -Pattern "(http[s]?\://download\.windowsupdate\.com\/[^\'\""]*)" |
        Select-Object -Unique

        if (-not $links) {
            Write-Warning -Message "No file found for $Name"
            return
        }

        foreach ($link in $links) {
            $link.matches.value
        }
    }
}