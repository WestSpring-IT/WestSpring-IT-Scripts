function write_log_message {
    param(
        [Parameter(Mandatory = $true)]
        [string]$message,
        [Parameter(Mandatory = $false)]
        [ValidateSet("Info", "Warning", "Error", "Success")]
        [string]$level = "Info",
        [Parameter(Mandatory = $false)]
        [Boolean]$writeToConsole = $true
    )
    $Global:scriptName = "windows_11_preparation_and_upgrade" #$(Split-Path $MyInvocation.ScriptName -Leaf).TrimEnd(".ps1")
    $timestamp = Get-Date -Format "yyyy-MM-dd_THH:mm:ss"
    $logEntry = "[$timestamp] [$level] $message"
    
    switch ($level) {
        "Success" {$consoleColour = "Green"}
        "Info"    {$consoleColour = "Cyan"}
        "Warning" {$consoleColour = "Yellow"}
        "Error"   {$consoleColour = "Red"}
    }
    if ($writeToConsole) {
        Write-Host $logEntry -ForegroundColor $consoleColour
    }
    # Append to log file
    if (-not $Global:logFilePath) {
        $Global:logFilePath = "$env:TEMP\$(get-date -f "yyyy-MM-dd")_$($Global:scriptName).log"
    }
    Add-Content -Path $Global:logFilePath -Value $logEntry
}
function start_cleanup {
<# 
.SYNOPSIS
   Automate cleaning up the C:\ drive with low disk space warning.

.DESCRIPTION
   Cleans the C: drive's Windows Temporary files, Windows SoftwareDistribution folder, 
   the local users Temporary folder, IIS logs(if applicable) and empties the recycle bin. 
   All deleted files will go into a log transcript in $env:TEMP. By default this 
   script leaves files that are newer than 7 days old however this variable can be edited.

.EXAMPLE
   PS C:\> .\Win_Start_Cleanup.ps1
   Save the file to your hard drive with a .PS1 extention and run the file from an elavated PowerShell prompt.

.NOTES
   This script will typically clean up anywhere from 1GB up to 15GB of space from a C: drive.

.FUNCTIONALITY
   PowerShell v3+
#>

## Allows the use of -WhatIf
[CmdletBinding(SupportsShouldProcess=$True)]

param(
    ## Delete data older then $daystodelete
    [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true,Position=0)]
    $DaysToDelete = 7,

    ## LogFile path for the transcript to be written to
    [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true,Position=1)]
    $LogFile = ("$env:TEMP\" + (get-date -format "MM-d-yy-HH-mm") + '.log'),

    ## All verbose outputs will get logged in the transcript($logFile)
    [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true,Position=2)]
    $VerbosePreference = "SilentlyContinue",

    ## All errors should be withheld from the console
    [Parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true,Position=3)]
    $ErrorActionPreference = "SilentlyContinue"
)

    ## Begin the timer
    $Starters = (Get-Date)
    ## Writes a verbose output to the screen for user information
    write_log_message "Retriving current disk percent free for comparison once the script has completed."

    ## Gathers the amount of disk space used before running the script
    $Before = Get-WmiObject Win32_LogicalDisk | Where-Object { $_.DriveType -eq "3" } | Select-Object SystemName,
    @{ Name = "Drive" ; Expression = { ( $_.DeviceID ) } },
    @{ Name = "Size (GB)" ; Expression = {"{0:N1}" -f ( $_.Size / 1gb)}},
    @{ Name = "FreeSpace (GB)" ; Expression = {"{0:N1}" -f ( $_.Freespace / 1gb ) } },
    @{ Name = "PercentFree" ; Expression = {"{0:P1}" -f ( $_.FreeSpace / $_.Size ) } } |
        Format-Table -AutoSize |
        Out-String

    ## Stops the windows update service so that c:\windows\softwaredistribution can be cleaned up
    Get-Service -Name wuauserv | Stop-Service -Force -ErrorAction SilentlyContinue -WarningAction SilentlyContinue

    # Sets the SCCM cache size to 1 GB if it exists.
    if ((Get-WmiObject -namespace root\ccm\SoftMgmtAgent -class CacheConfig) -ne "$null"){
        # if data is returned and sccm cache is configured it will shrink the size to 1024MB.
        $cache = Get-WmiObject -namespace root\ccm\SoftMgmtAgent -class CacheConfig
        $Cache.size = 1024 | Out-Null
        $Cache.Put() | Out-Null
        Restart-Service ccmexec -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
    }

    ## Deletes the contents of Windows Software Distribution.
    Get-ChildItem "C:\Windows\SoftwareDistribution\*" -Recurse -Force -ErrorAction SilentlyContinue | Remove-Item -recurse -ErrorAction SilentlyContinue
    write_log_message "The Contents of Windows SoftwareDistribution have been removed successfully!" -level "Success"

    ## Deletes the contents of the Windows Temp folder.
    Get-ChildItem "C:\Windows\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue |
        Where-Object { ($_.CreationTime -lt $(Get-Date).AddDays( - $DaysToDelete)) } | Remove-Item -force -recurse -ErrorAction SilentlyContinue
    write_log_message "The Contents of Windows Temp have been removed successfully!" -level "Success"


    ## Deletes all files and folders in user's Temp folder older then $DaysToDelete
    Get-ChildItem "C:\users\*\AppData\Local\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue |
        Where-Object { ($_.CreationTime -lt $(Get-Date).AddDays( - $DaysToDelete))} |
        Remove-Item -force -recurse -ErrorAction SilentlyContinue
    write_log_message "The contents of `$env:TEMP have been removed successfully!" -level "Success"

        ## Deletes all files and folders in CSBack folder older then $DaysToDelete
    Get-ChildItem "C:\csback\*" -Recurse -Force -ErrorAction SilentlyContinue |
        Where-Object { ($_.CreationTime -lt $(Get-Date).AddDays( - $DaysToDelete))} |
        Remove-Item -force -recurse -ErrorAction SilentlyContinue
    write_log_message "The contents of csback have been removed successfully!" -level "Success"

    ## Removes all files and folders in user's Temporary Internet Files older then $DaysToDelete
    Get-ChildItem "C:\users\*\AppData\Local\Microsoft\Windows\Temporary Internet Files\*" `
        -Recurse -Force -ErrorAction SilentlyContinue |
        Where-Object {($_.CreationTime -lt $(Get-Date).AddDays( - $DaysToDelete))} |
        Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
    write_log_message "All Temporary Internet Files have been removed successfully!" -level Success

    ## Removes *.log from C:\windows\CBS
    if(Test-Path C:\Windows\logs\CBS\){
    Get-ChildItem "C:\Windows\logs\CBS\*.log" -Recurse -Force -ErrorAction SilentlyContinue |
        remove-item -force -recurse -ErrorAction SilentlyContinue
    write_log_message "All CBS logs have been removed successfully!" -level "Success"
    } else {
        write_log_message "C:\inetpub\logs\LogFiles\ does not exist, there is nothing to cleanup." -level "Warning"
    }

    ## Cleans IIS Logs older then $DaysToDelete
    if (Test-Path C:\inetpub\logs\LogFiles\) {
        Get-ChildItem "C:\inetpub\logs\LogFiles\*" -Recurse -Force -ErrorAction SilentlyContinue |
            Where-Object { ($_.CreationTime -lt $(Get-Date).AddDays(-60)) } | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
        write_log_message "All IIS Logfiles over $DaysToDelete days old have been removed Successfully!" -level "Success"
    }
    else {
        write_log_message "C:\Windows\logs\CBS\ does not exist, there is nothing to cleanup." -level "Warning"
    }

    ## Removes C:\Config.Msi
    if (test-path C:\Config.Msi){
        remove-item -Path C:\Config.Msi -force -recurse -ErrorAction SilentlyContinue
    } else {
        write_log_message "C:\Config.Msi does not exist, there is nothing to cleanup." -level "Warning"
    }

    ## Removes c:\Intel
    if (test-path c:\Intel){
        remove-item -Path c:\Intel -force -recurse -ErrorAction SilentlyContinue
    } else {
        write_log_message "c:\Intel does not exist, there is nothing to cleanup." -level "Warning"
    }

    ## Removes c:\PerfLogs
    if (test-path c:\PerfLogs){
        remove-item -Path c:\PerfLogs -force -recurse -ErrorAction SilentlyContinue
    } else {
        write_log_message "c:\PerfLogs does not exist, there is nothing to cleanup." -level "Warning"
    }

    ## Removes $env:windir\memory.dmp
    if (test-path $env:windir\memory.dmp){
        remove-item $env:windir\memory.dmp -force -ErrorAction SilentlyContinue
    } else {
        write_log_message "C:\Windows\memory.dmp does not exist, there is nothing to cleanup." -level "Warning"
    }

    ## Removes rouge folders
    write_log_message "Deleting Rouge folders" 

    ## Removes Windows Error Reporting files
    if (test-path C:\ProgramData\Microsoft\Windows\WER){
        Get-ChildItem -Path C:\ProgramData\Microsoft\Windows\WER -Recurse | Remove-Item -force -recurse -ErrorAction SilentlyContinue
            write_log_message "Deleting Windows Error Reporting files" 
        } else {
            write_log_message "C:\ProgramData\Microsoft\Windows\WER does not exist, there is nothing to cleanup." -level "Warning"
    }

    ## Removes System and User Temp Files - lots of access denied will occur.
    ## Cleans up c:\windows\temp
    if (Test-Path $env:windir\Temp\) {
        Remove-Item -Path "$env:windir\Temp\*" -Force -Recurse -ErrorAction SilentlyContinue
    } else {
            write_log_message "C:\Windows\Temp does not exist, there is nothing to cleanup." -level "Warning"
    }

    ## Cleans up minidump
    if (Test-Path $env:windir\minidump\) {
        Remove-Item -Path "$env:windir\minidump\*" -Force -Recurse -ErrorAction SilentlyContinue
    } else {
            write_log_message "$env:windir\minidump\ does not exist, there is nothing to cleanup." -level "Warning"
    }

    ## Cleans up prefetch
    if (Test-Path $env:windir\Prefetch\) {
        Remove-Item -Path "$env:windir\Prefetch\*" -Force -Recurse -ErrorAction SilentlyContinue
    } else {
            write_log_message "$env:windir\Prefetch\ does not exist, there is nothing to cleanup." -level "Warning"
    }

    ## Cleans up each user's temp folder
    if (Test-Path "C:\Users\*\AppData\Local\Temp\") {
        Remove-Item -Path "C:\Users\*\AppData\Local\Temp\*" -Force -Recurse -ErrorAction SilentlyContinue
    } else {
            write_log_message "C:\Users\*\AppData\Local\Temp\ does not exist, there is nothing to cleanup." -level "Warning"
    }

    ## Cleans up all user's Windows error reporting
    if (Test-Path "C:\Users\*\AppData\Local\Microsoft\Windows\WER\") {
        Remove-Item -Path "C:\Users\*\AppData\Local\Microsoft\Windows\WER\*" -Force -Recurse -ErrorAction SilentlyContinue
    } else {
            write_log_message "C:\ProgramData\Microsoft\Windows\WER does not exist, there is nothing to cleanup." -level "Warning"
    }

    ## Cleans up user's temporary internet files
    if (Test-Path "C:\Users\*\AppData\Local\Microsoft\Windows\Temporary Internet Files\") {
        Remove-Item -Path "C:\Users\*\AppData\Local\Microsoft\Windows\Temporary Internet Files\*" -Force -Recurse -ErrorAction SilentlyContinue
    } else {
            write_log_message "C:\Users\*\AppData\Local\Microsoft\Windows\Temporary Internet Files\ does not exist." -level "Warning"
    }

    ## Cleans up Internet Explorer cache
    if (Test-Path "C:\Users\*\AppData\Local\Microsoft\Windows\IECompatCache\") {
        Remove-Item -Path "C:\Users\*\AppData\Local\Microsoft\Windows\IECompatCache\*" -Force -Recurse -ErrorAction SilentlyContinue
    } else {
            write_log_message "C:\Users\*\AppData\Local\Microsoft\Windows\IECompatCache\ does not exist." -level "Warning"
    }

    ## Cleans up Internet Explorer cache
    if (Test-Path "C:\Users\*\AppData\Local\Microsoft\Windows\IECompatUaCache\") {
        Remove-Item -Path "C:\Users\*\AppData\Local\Microsoft\Windows\IECompatUaCache\*" -Force -Recurse -ErrorAction SilentlyContinue
    } else {
            write_log_message "C:\Users\*\AppData\Local\Microsoft\Windows\IECompatUaCache\ does not exist." -level "Warning"
    }

    ## Cleans up Internet Explorer download history
    if (Test-Path "C:\Users\*\AppData\Local\Microsoft\Windows\IEDownloadHistory\") {
        Remove-Item -Path "C:\Users\*\AppData\Local\Microsoft\Windows\IEDownloadHistory\*" -Force -Recurse -ErrorAction SilentlyContinue
    } else {
            write_log_message "C:\Users\*\AppData\Local\Microsoft\Windows\IEDownloadHistory\ does not exist." -level "Warning"
    }

    ## Cleans up Internet Cache
    if (Test-Path "C:\Users\*\AppData\Local\Microsoft\Windows\INetCache\") {
        Remove-Item -Path "C:\Users\*\AppData\Local\Microsoft\Windows\INetCache\*" -Force -Recurse -ErrorAction SilentlyContinue
    } else {
            write_log_message "C:\Users\*\AppData\Local\Microsoft\Windows\INetCache\ does not exist." -level "Warning"
    }

    ## Cleans up Internet Cookies
    if (Test-Path "C:\Users\*\AppData\Local\Microsoft\Windows\INetCookies\") {
        Remove-Item -Path "C:\Users\*\AppData\Local\Microsoft\Windows\INetCookies\*" -Force -Recurse -ErrorAction SilentlyContinue
    } else {
            write_log_message "C:\Users\*\AppData\Local\Microsoft\Windows\INetCookies\ does not exist." -level "Warning"
    }

    ## Cleans up terminal server cache
    if (Test-Path "C:\Users\*\AppData\Local\Microsoft\Terminal Server Client\Cache\") {
        Remove-Item -Path "C:\Users\*\AppData\Local\Microsoft\Terminal Server Client\Cache\*" -Force -Recurse -ErrorAction SilentlyContinue
    } else {
            write_log_message "C:\Users\*\AppData\Local\Microsoft\Terminal Server Client\Cache\ does not exist." -level "Warning"
    }

    write_log_message "Removing System and User Temp Files" 

    ## Removes the hidden recycle bin.
    if (Test-path 'C:\$Recycle.Bin'){
        Remove-Item 'C:\$Recycle.Bin' -Recurse -Force -ErrorAction SilentlyContinue
    } else {
        write_log_message "C:\`$Recycle.Bin does not exist, there is nothing to cleanup." -level "Warning"
    }

    ## Cleans up the Atera Office package cache
    if (Test-Path 'C:\Program Files*\ATERA Networks\AteraAgent\Office') {
        Remove-Item -Path 'C:\Program Files*\ATERA Networks\AteraAgent\Office' -Force -Recurse -ErrorAction SilentlyContinue
    } else {
        write_log_message "C:\Program Files\ATERA Networks*\AteraAgent\Office does not exist." -level "Warning" -level Warning
    }
    ## Turns errors back on
    $ErrorActionPreference = "Continue"

    ## Checks the version of PowerShell
    ## If PowerShell version 4 or below is installed the following will process
    if ($PSVersionTable.PSVersion.Major -le 4) {

        ## Empties the recycle bin, the desktop recycle bin
        $Recycler = (New-Object -ComObject Shell.Application).NameSpace(0xa)
        $Recycler.items() | ForEach-Object { 
            ## If PowerShell version 4 or below is installed the following will process
            Remove-Item -Include $_.path -Force -Recurse
            write_log_message "The recycling bin has been cleaned up successfully!                                        " 
        }
    } elseif ($PSVersionTable.PSVersion.Major -ge 5) {
         ## If PowerShell version 5 is running on the machine the following will process
         Clear-RecycleBin -DriveLetter C:\ -Force
         write_log_message "The recycling bin has been cleaned up successfully!                                               " 
    }

    ## gathers disk usage after running the cleanup cmdlets.
    $After = Get-WmiObject Win32_LogicalDisk | Where-Object { $_.DriveType -eq "3" } | Select-Object SystemName,
    @{ Name = "Drive" ; Expression = { ( $_.DeviceID ) } },
    @{ Name = "Size (GB)" ; Expression = {"{0:N1}" -f ( $_.Size / 1gb)}},
    @{ Name = "FreeSpace (GB)" ; Expression = {"{0:N1}" -f ( $_.Freespace / 1gb ) } },
    @{ Name = "PercentFree" ; Expression = {"{0:P1}" -f ( $_.FreeSpace / $_.Size ) } } |
        Format-Table -AutoSize | Out-String

    ## Restarts wuauserv
    Get-Service -Name wuauserv | Start-Service -ErrorAction SilentlyContinue

    ## Stop timer
    $Enders = (Get-Date)

    ## Calculate amount of seconds your code takes to complete.
    write_log_message "Elapsed Time: $(($Enders - $Starters).totalseconds) seconds"
    ## Sends hostname to the console for ticketing purposes.
    write_log_message (Hostname) 

    ## Sends the date and time to the console for ticketing purposes.
    write_log_message (Get-Date | Select-Object -ExpandProperty DateTime)

    ## Sends the disk usage before running the cleanup script to the console for ticketing purposes.
    write_log_message "Before: $Before"

    ## Sends the disk usage after running the cleanup script to the console for ticketing purposes.
    write_log_message "After: $After"

    ## Completed Successfully!
}

function download_file {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri,
        [string]$destination,
        [int]$MaxTries = 3,
        [string]$ProgressPreference = "SilentlyContinue"
    )
    # Get the actual download URL (after any redirects)
    $response = Invoke-WebRequest $Uri -Method Head
    $finalUrl = $response.BaseResponse.RequestMessage.RequestUri.AbsoluteUri
    $uriObj = [System.Uri]$finalUrl
    $fileName = [System.IO.Path]::GetFileName($uriObj.AbsolutePath)

    # Set default destination if not provided
    if (-not $Destination) {
        $Destination = "$env:TEMP\$fileName"
    }

    $attempt = 0
    $success = $false

    Write-Host "Starting download of $fileName from $Uri to $destination" -ForegroundColor Cyan
    while (-not $success -and $attempt -lt $MaxTries) {
        try {
            $attempt++
            Invoke-WebRequest -Uri $Uri -OutFile $destination -ErrorAction Stop
            Write-Host "Download succeeded on attempt $($attempt): $destination" -ForegroundColor Green
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
$response = [PSCustomObject]@{
    FileName     = $fileName
    Destination  = $destination
    FileSizeMB   = [Math]::Round((Get-Item $destination).Length / 1MB, 2)
    DownloadTime = (Get-Date)
}
    return $response
}


function get_current_windows_version {
    $info = Get-ComputerInfo | select-object OsName
    if ($info -like "*Windows 11*") {
        write_log_message "Current windows version is: $($info) No need to upgrade..."
        [Environment]::Exit(1)
    }
}

