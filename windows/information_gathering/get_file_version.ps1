$filePath = "C:\IntuneWIN\IntuneWinAppUtil.exe"

##TODO add function to handle cmd formated relative paths like %systemroot%, %prgramfiles% etc
Write-host "Getting Versioninfo for the following file(s): $($filePath)"
$filesFound = (Get-Item -Path $filePath -ErrorAction SilentlyContinue) #| Select originalFilename,ProductName,ProductVersionraw

if ($filesFound.Count -lt 1) {
    Write-host "No files found for the given file path: $($filePath)"
} else {
    foreach ($x in $filesFound) {
        Write-host "----"
        Write-Host "File: $($x.Versioninfo.OriginalFilename)"
        write-host "File location: $($x.Versioninfo.FileName)"
        write-host "Version info: $($x.Versioninfo.FileVersion)"

    }
}
#Write-host "Hostname: "(hostname)
