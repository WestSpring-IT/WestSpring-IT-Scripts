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
function check_windows_version {

    $osVersion = (Get-CimInstance -ClassName Win32_OperatingSystem).Version
    $major, $minor, $build = $osVersion.Split('.')
    $result = [PSCustomObject]@{
        major = $major
        minor = $minor
        build = $build
    }
    return $result
}
function check_efi_partition {
    $disk = Get-Disk | Where-Object { $_.IsSystem -eq $true }
    if ($disk.PartitionStyle -eq 'GPT') {
        write_log_message "System disk is GPT. EFI partition should be present." -level "Info"
        $efiVolume = Get-Volume -UniqueId "\\?\Volume$(((Get-Partition).Where{$_.GptType -eq '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}'}.Guid))\"
        if ($null -eq $efiVolume) {
            write_log_message "EFI partition not found. Aborting." -level "Error"
            exit
        } else {
            write_log_message "EFI partition found." -level "Success"
            $result = [PSCustomObject]@{
                volumeType = "GPT"
                totalSpaceMB = [math]::Round(($efiVolume.Size /1MB), 2)
                freeSpaceMB  = [math]::Round(($efiVolume.SizeRemaining /1MB) ,2) 
                usedSpace    = 100 - ([math]::Round(($efiVolume.SizeRemaining / $efiVolume.Size) * 100 ,2))
            }
            return $result
        }
    } elseif ($disk.PartitionStyle -eq 'MBR') {
        write_log_message "System disk is MBR. System Reserved partition should be present." -level "Info"
        $sysReserved = Get-Partition | Where-Object { $_.Type -eq 'System' -and $_.Size -le 550MB }
        if ($null -eq $sysReserved) {
            write_log_message "System Reserved partition not found. Aborting." -level "Error"
            exit
        } else {
            write_log_message "System Reserved partition found." -level "Success"
            $result = [PSCustomObject]@{
                totalSpaceMB = [math]::Round($sysReserved.Size / 1MB, 2)
                freeSpaceMB = [math]::Round(($sysReserved.Offset) / 1MB, 2)
                usedSpace = 100 - ([math]::Round((($sysReserved.Size - $sysReserved.Offset) / $sysReserved.Size) * 100, 2))
            }
            return $result
        }
    } else {
        write_log_message "Unknown partition style. Aborting." -level "Error"
        exit
    }
}
function clear_efi_fonts {

$disk = Get-Disk | Where-Object { $_.IsSystem -eq $true }
if ($disk.PartitionStyle -eq 'GPT') {
    write_log_message "System disk is GPT. Proceeding with EFI partition cleanup..." -level "Info" 

    # Mount EFI System Partition as Y:
    write_log_message -message "Mounting EFI partition"
    mountvol Y: /s

    $fontsPath = "Y:\EFI\Microsoft\Boot\Fonts"
    if (Test-Path $fontsPath) {
        write_log_message "Deleting all files in $fontsPath..." -level "Info"
        Remove-Item "$fontsPath\*" -Force -ErrorAction SilentlyContinue
        write_log_message "Font files deleted from EFI partition." -level "Success" 
    } else {
        write_log_message "Fonts folder not found at $fontsPath." -level "Warning"
    }

    # Dismount the Y: drive
    write_log_message -message "Unmounting EFI partition"
    mountvol Y: /d
}
elseif ($disk.PartitionStyle -eq 'MBR') {
    write_log_message "System disk is MBR. Proceeding with System Reserved Partition cleanup..." -level "Info"

    $fontsPath = "Y:\Boot\Fonts"
    if (-not (Test-Path $fontsPath)) {
        write_log_message "Fonts folder not found at $fontsPath. Make sure System Reserved is mounted as Y:." -level "Error" 
        exit
    }

    # Take ownership
    write_log_message "Taking ownership of $fontsPath..." -level "Info"
    Start-Process -FilePath "takeown.exe" -ArgumentList "/d y /r /f . " -WorkingDirectory $fontsPath -Wait -WindowStyle Hidden

    # Backup ACLs
    $aclBackup = "$env:SystemDrive\NTFSp.txt"
    write_log_message "Backing up ACLs to $aclBackup..." -level "Info"
    Start-Process -FilePath "icacls.exe" -ArgumentList "Y:\* /save $aclBackup /c /t" -Wait -WindowStyle Hidden

    # Grant full control to current user
    $whoami = whoami
    write_log_message "Granting full control to $whoami..." -level "Info" 
    Start-Process -FilePath "icacls.exe" -ArgumentList ". /grant $whoami`:F /t" -WorkingDirectory $fontsPath -Wait -WindowStyle Hidden

    # Delete font files
    write_log_message "Deleting all files in $fontsPath..." -level "Info" 
    Remove-Item "$fontsPath\*" -Force -ErrorAction SilentlyContinue
    write_log_message "Font files deleted from System Reserved partition." -level "Success" 

    # Restore ACLs
    write_log_message "Restoring ACLs from $aclBackup..." -level "Info"
    Start-Process -FilePath "icacls.exe" -ArgumentList "Y:\ /restore $aclBackup /c /t" -Wait -WindowStyle Hidden

    # Grant SYSTEM full control
    write_log_message "Granting SYSTEM full control..." -level "Info"
    Start-Process -FilePath "icacls.exe" -ArgumentList ". /grant system`:f /t" -WorkingDirectory $fontsPath -Wait -WindowStyle Hidden

    # Set owner back to SYSTEM
    write_log_message "Setting owner back to SYSTEM..." -level "Info"
    Start-Process -FilePath "icacls.exe" -ArgumentList "Y: /setowner `"SYSTEM`" /t /c" -Wait -WindowStyle Hidden

    write_log_message "Cleanup complete. You may now remove the Y: drive letter in Disk Management." -level "Success"
}
else {
    write_log_message "Unknown partition style. Aborting." -level "Error"
    exit
}
}
Function start_cleanup {
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
    <#
.SYNOPSIS
Downloads a file from a specified URI with retry logic and returns download details.

.DESCRIPTION
The download_file function downloads a file from the provided URI to a specified destination path.
It follows redirects to get the actual download URL, supports retrying the download on failure,
and returns an object containing file details such as name, destination, size, and download time.

.PARAMETER Uri
The URI of the file to download. This parameter is mandatory.

.PARAMETER Destination
The path where the downloaded file will be saved. If not specified, defaults to the TEMP directory.

.PARAMETER MaxTries
The maximum number of download attempts in case of failure. Defaults to 3.

.PARAMETER ProgressPreference
Specifies how progress is displayed during download. Defaults to "SilentlyContinue".

.OUTPUTS
[PSCustomObject]
Returns an object with the following properties:
- FileName: Name of the downloaded file.
- Destination: Path to the downloaded file.
- FileSizeMB: Size of the downloaded file in megabytes.
- DownloadTime: Timestamp of when the download completed.

.EXAMPLE
download_file -Uri "https://example.com/file.zip" -Destination "C:\Downloads\file.zip"

.EXAMPLE
download_file -Uri "https://example.com/file.zip"

.NOTES
Requires PowerShell 5.0 or later.
#>
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
<# function get_current_windows_version {
    $info = Get-ComputerInfo | select-object OsName
    if ($info -like "*Windows 11*") {
        write_log_message "Current windows version is: $($info) No need to upgrade..."
        [Environment]::Exit(1)
    }
} #>
function set_custom_registry_value {
    param (
        [string]$regValueName,
        [int]$regValueData = 1
    )
    if ( !$bypassCheck ) {
        return
    }
    foreach ($path in $regKeyPaths) {
        try {
            if (-not (Test-Path $path)) {
                write_log_message "Creating registry path: $path"
                New-Item -Path $path -Force | Out-Null
            }
            Set-ItemProperty -Path $path -Name $regValueName -Value $regValueData -Type DWord
            write_log_message "Set '$regValueName' to '$regValueData' at '$path'"
        } catch {
            write_log_message "Failed to set registry value at $path. Error: $_"
        }
    }
}
# check functions
function check_cpu {
    param (
        [ref]$Issues
    )
    write_log_message "Checking processor..."
    try {
        $cpu = Get-WmiObject -Class Win32_Processor
        $cpuName = $cpu.Name
        $cpuCores = $cpu.NumberOfCores
        $cpuSpeed = [math]::Round($cpu.MaxClockSpeed / 1000, 2) # GHz
        write_log_message "CPU: $cpuName, Cores: $cpuCores, Speed: $cpuSpeed GHz" -writeToConsole $true
        if ($cpuCores -lt 2 -or $cpuSpeed -lt 1) {
            $Issues.Value += "CPU does not meet requirements (needs 2+ cores, 1+ GHz)."
            set_custom_registry_value "AllowUpgradesWithUnsupportedCPU"
            return $false
        } else {
            write_log_message "CPU meets basic requirements. Verify against Microsoft's supported CPU list."
            return $true
        }
    } catch {
        write_log_message "Error checking CPU: $($_.Exception.Message)" "Error"
        $Issues.Value += "Failed to check CPU."
        set_custom_registry_value "AllowUpgradesWithUnsupportedCPU"
        return $false
    }
}
function check_ram {
    param (
        [ref]$Issues
    )
    write_log_message "Checking RAM..."
    try {
        $ram = [math]::Round((Get-WmiObject -Class Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 2)
        write_log_message "RAM: $ram GB"
        if ($ram -lt 4) {
            $Issues.Value += "RAM is less than 4 GB."
            set_custom_registry_value "AllowUpgradesWithUnsupportedRAM"
            return $false
        }
        return $true
    } catch {
        write_log_message "Error checking RAM: $($_.Exception.Message)" "Error"
        $Issues.Value += "Failed to check RAM."
        set_custom_registry_value "AllowUpgradesWithUnsupportedRAM"
        return $false
    }
}
function check_storage {
    param (
        [ref]$Issues
    )
    write_log_message "Checking storage of system drive..."
    try {
        $systemDrive = $env:SystemDrive
        $disk = Get-WmiObject -Class Win32_LogicalDisk -Filter "DeviceID='$systemDrive'"
        if (-not $disk) {
            throw "System drive $systemDrive not found."
        }
        $freeSpace = [math]::Round($disk.FreeSpace / 1GB, 2)
        write_log_message "$systemDrive Free Space: $freeSpace GB"
        if ($freeSpace -ge 64) {
            return $true
        }
        write_log_message "Less than 64 GB free. Attempting cleanup..." -writeToConsole $true
        try {
            start_cleanup
            $disk = Get-WmiObject -Class Win32_LogicalDisk -Filter "DeviceID='$systemDrive'"
            $freeSpace = [math]::Round($disk.FreeSpace / 1GB, 2)
            write_log_message "Post-cleanup $systemDrive Free Space: $freeSpace GB" -writeToConsole $true
            if ($freeSpace -ge 64) {
                write_log_message "Cleanup successful. Sufficient free space available." -writeToConsole $true
                return $true
            } else {
                $Issues.Value += "Free storage on $systemDrive is less than 64 GB after cleanup."
                set_custom_registry_value "AllowUpgradesWithUnsupportedDisk"
                return $false
            }
        } catch {
            write_log_message "Cleanup failed: $($_.Exception.Message)" "Error"
            $Issues.Value += "Cleanup failed: $($_.Exception.Message)"
            set_custom_registry_value "AllowUpgradesWithUnsupportedDisk"
            return $false
        }
    } catch {
        write_log_message "Error checking storage: $($_.Exception.Message)" "Error"
        $Issues.Value += "Failed to check storage on $systemDrive."
        set_custom_registry_value "AllowUpgradesWithUnsupportedDisk"
        return $false
    }
    write_log_message "Checking storage of EFI/System Reserved partition..."
    $efiResult = check_efi_partition
    # Threshold: usedSpace must be less than 20% (i.e., at least 80% free)
    if ($null -eq $efiResult -or $null -eq $efiResult.usedSpace) {
        write_log_message "Failed to retrieve EFI/System Reserved partition information." "Error"
        $Issues.Value += "Failed to retrieve EFI/System Reserved partition information."
        set_custom_registry_value "AllowUpgradesWithUnsupportedDisk"
        return $false
    }
    if ($efiResult.usedSpace -ge 20) {
        try {
            write_log_message "EFI/System Reserved partition has less than 80% free space. Attempting cleanup..." -writeToConsole $true
            start_efi_cleanup
            $efiResult = check_efi_partition
            if ($null -eq $efiResult -or $null -eq $efiResult.usedSpace) {
                write_log_message "Failed to retrieve EFI/System Reserved partition information after cleanup." "Error"
                $Issues.Value += "Failed to retrieve EFI/System Reserved partition information after cleanup."
                set_custom_registry_value "AllowUpgradesWithUnsupportedDisk"
                return $false
            }
            if ($efiResult.usedSpace -lt 20) {
                write_log_message "EFI/System Reserved partition cleanup successful. Sufficient free space available." -writeToConsole $true
                return $true
            }
            $Issues.Value += "EFI/System Reserved partition has less than 80% free space after cleanup."
            set_custom_registry_value "AllowUpgradesWithUnsupportedDisk"
            return $false
        }
        catch {
            write_log_message "EFI/System Reserved partition cleanup failed: $($_.Exception.Message)" "Error"
            $Issues.Value += "EFI/System Reserved partition cleanup failed: $($_.Exception.Message)"
            set_custom_registry_value "AllowUpgradesWithUnsupportedDisk"
            return $false
        }
    } else {
        write_log_message "EFI/System Reserved partition has sufficient free space."
        return $true
    }
}
function check_tpm {
    param (
        [ref]$Issues
    )
    write_log_message "Checking TPM..."
    try {
        $tpm = Get-WmiObject -Namespace "Root\CIMV2\Security\MicrosoftTpm" -Class Win32_Tpm
        if ($tpm) {
            $tpmVersion = $tpm.SpecVersion
            write_log_message "TPM Version: $tpmVersion"
            if ($tpmVersion -notlike "*2.0*") {
                $Issues.Value += "TPM version is not 2.0."
                set_custom_registry_value "AllowUpgradesWithUnsupportedTPMOrCPU"
                return $false
            }
            return $true
        } else {
            $Issues.Value += "No TPM detected."
            set_custom_registry_value "AllowUpgradesWithUnsupportedTPMOrCPU"
            write_log_message "TPM not found. Check BIOS/UEFI settings."
            return $false
        }
    } catch {
        write_log_message "Error checking TPM: $($_.Exception.Message)" "Error"
        $Issues.Value += "Failed to check TPM."
        set_custom_registry_value "AllowUpgradesWithUnsupportedTPMOrCPU"
        return $false
    }
}
function check_secure_boot {
    param (
        [ref]$Issues
    )
    write_log_message "Checking Secure Boot..."
    try {
        $secureBoot = Confirm-SecureBootUEFI
        write_log_message "Secure Boot Enabled: $secureBoot"
        if (-not $secureBoot) {
            $Issues.Value += "Secure Boot is not enabled."
            set_custom_registry_value "AllowUpgradesWithUnsupportedSecureBoot"
            return $false
        }
        return $true
    } catch {
        write_log_message "Error checking Secure Boot: $($_.Exception.Message)" "Error"
        $Issues.Value += "Secure Boot not supported or disabled. Check BIOS/UEFI."
        set_custom_registry_value "AllowUpgradesWithUnsupportedSecureBoot"
        return $false
    }
}
function check_boot_state {
    param (
        [ref]$Issues
    )
    write_log_message "Checking Bootup State..."
    try {
        $firmware = Get-WmiObject -Class Win32_ComputerSystem
        $bootMode = $firmware.BootupState
        write_log_message "Boot Mode: $bootMode"
        if ($bootMode -notlike "*Normal boot*") {
            $Issues.Value += "System has not booted normally."
            return $false
        }
        return $true
    } catch {
        write_log_message "Error checking Bootup Sate: $($_.Exception.Message)" "Error"
        $Issues.Value += "Failed to check Bootup State."
        return $false
    }
}
function check_windows_version {
    param (
        [ref]$Issues
    )
    write_log_message "Checking Windows version..."
    try {
        $os = Get-WmiObject -Class Win32_OperatingSystem
        $osVersion = $os.Version
        write_log_message "Windows Version: $osVersion"
        if (([version]$osVersion -lt [version]"10.0.19041") -or ([version]$osVersion -gt [version]"10.0.22000")) {
            $Issues.Value += "Windows 10 version is older than 2004 or has already been upgraded to Windows 11. Windows $($osVersion) detected."
            return $false
        }
        return $true
    } catch {
        write_log_message "Error checking Windows version: $($_.Exception.Message)" "Error"
        $Issues.Value += "Failed to check Windows version - $($_.Exception.Message)"
        return $false
    }
}
function check_compatability {
    # Initialize compatibility status and issues list
    $IsCompatible = $true
    $Issues = @()
    # Run individual checks
    $cpuResult = check_cpu -Issues ([ref]$Issues)
    Write-Host $cpuResult
    $ramResult = check_ram -Issues ([ref]$Issues)
    Write-Host $ramResult
    $storageResult = check_storage -Issues ([ref]$Issues)
    write-host $storageResult
    $tpmResult = check_tpm -Issues ([ref]$Issues)
    write-host $tpmResult
    $secureBootResult = check_secure_boot -Issues ([ref]$Issues)
    write-host $secureBootResult
    $bootupStateResult = check_boot_state -Issues ([ref]$Issues)
    write-host $bootupStateResult
    $windowsVersionResult = check_windows_version -Issues ([ref]$Issues)
    write-host $windowsVersionResult

    # Combine results to determine overall compatibility
    $IsCompatible = $cpuResult -and $ramResult -and $storageResult -and $tpmResult -and $secureBootResult -and $windowsVersionResult -and $bootupStateResult
    # Summary
    write_log_message "Compatibility Check Summary:" -writeToConsole $true
    if ($IsCompatible) {
        write_log_message "System appears compatible with this Windows 11 upgrade" "Success" -writeToConsole $true
        return $true
    } else {
        write_log_message "System is NOT compatible with Windows 11." "Error" -writeToConsole $true
        write_log_message "Issues found:" -writeToConsole $true
        foreach ($issue in $Issues) {
            write_log_message " - $issue" "Error" -writeToConsole $true
        }
        return $false
    }
}

## MAIN ##
$compatabilityCheck = check_compatability
if (-not $compatabilityCheck) {
    write_log_message "Compatibility check failed. Exiting upgrade process." "Error" -writeToConsole $true
    exit 1
}
else {
    # start upgrade procedure
    write_log_message "Starting download for Windows 11 Upgrade Assistant" -level "Info" -writeToConsole $true
    $downloadResult = download_file -Uri "https://go.microsoft.com/fwlink/?linkid=2171764" -Destination "$env:TEMP\Windows11Upgrade.exe"
    if ($downloadResult) {
        $arguments = @("/QuietInstall", "/ShowProgressInTaskBarIcon", "/SkipEULA", "/Auto Upgrade")
        write_log_message "Starting Windows 11 Upgrade Assistant with the following arguments: "  -level "Info" -writeToConsole $true
        foreach ($arg in $arguments) {
            write_log_message "  $arg" -level "Info" -writeToConsole $true
        }
        write_log_message "This process may take a while, please be patient..." -level "Info" -writeToConsole $true
        ## Start the Windows 11 Upgrade Assistant
        try {
            Start-Process -FilePath $downloadResult.destination -ArgumentList $arguments -Wait
        }
        catch {
            $e = $_.Exception
            $msg = $e.Message
            while ($e.InnerException) {
                $e = $e.InnerException
                $msg += "`n" + $e.Message
                write_log_message "  $($msg)"
                write_log_message "An error as occured, please check the log file - $($Global:logFilePath)"
            } 
        }
    }
}

