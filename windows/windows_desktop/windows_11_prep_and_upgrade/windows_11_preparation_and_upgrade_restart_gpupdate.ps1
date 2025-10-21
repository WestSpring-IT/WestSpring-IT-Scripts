$gpProcess =  Get-Process | where {$_.ProcessName -like "*gpupdate*"}

if ($gpProcess) {
    Stop-Process -Name $gpProcess.ProcessName -Force
    Write-Host "Stopped existing gpupdate process: $($gpProcess.ProcessName) (ID: $($gpProcess.Id))"
    start-sleep -Seconds 2
    write-Host "Restarting gpupdate"
    Start-Process -FilePath $process.Path -noNewWindow
} else {
    write-host "No existing gpupdate process found."
}