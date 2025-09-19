$counter = 0
Write-Host "Starting Unquoted Service Path Checking" -ForegroundColor Green
#Collect a list of IndividualServices running on the machine being checked
$installedServices = Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Services"
#Check each and every service
foreach ($individualService in $installedServices) {
    $imagePathExists = $false
    foreach ($Property in $individualService.Property) {
        #Does the service have an image path?
        if ($Property -eq "ImagePath") {
            $imagePathExists = $true 
            break;
        }
    }
    #If we cannot find an Image Path on the service we can move on and ignore
    if (-not($imagePathExists)) {
        continue
    }

    # Only process services set to auto start (Start = 2)
    $startValue = $individualService.GetValue("Start")
    if ($startValue -ne 2) {
        continue
    }

    #Copy the image path variable so we can work with it in the scipt
    $imagePathCopy = [string]$individualService.GetValue("ImagePath")

    # If the imagePathCopy has no spaces we can ignore it
    if (-not ($imagePathCopy.Contains(" ")))
    { continue }

    #Variables for executable and parameters
    $executables = ""
    #$parameters = ""

    #Is this a driver with .SYS extension
    if ($imagePathCopy.Contains('.sys')) {
        # Split executable path and arguments for drivers
        if ($imagePathCopy.Contains('.sys"')) {
            $splitPoint = $imagePathCopy.IndexOf(".sys") + 5
            $executables = $imagePathCopy.Substring(0, $splitPoint)
            $arguments = ($imagePathCopy.Substring($splitPoint - 1))
        }
        else {
            $splitPoint = $imagePathCopy.IndexOf(".sys") + 4
            $executables = $imagePathCopy.Substring(0, $splitPoint)
            $arguments = ($imagePathCopy.Substring($splitPoint)) 
        }
        #Is this an executable file with a .exe extension
    }
    elseif ($imagePathCopy.Contains('.exe')) {
        # Split executable path and arguments for drivers
        if ($imagePathCopy.Contains('.exe"')) {
            $splitPoint = $imagePathCopy.IndexOf(".exe") + 5
            $executables = $imagePathCopy.Substring(0, $splitPoint)
            $arguments = ($imagePathCopy.Substring($splitPoint - 1))
        }
        else {
            $splitPoint = $imagePathCopy.IndexOf(".exe") + 4
            $executables = $imagePathCopy.Substring(0, $splitPoint)
            $arguments = ($imagePathCopy.Substring($splitPoint))
        }
    }

    #Check for spaces in the executable path
    If ($executables.Contains(' ')) {
        #Are there spaced and no quotes
        if (-not(($executables.StartsWith('"') -and $executables.EndsWith('"')))) {
            $counter++
            Write-Host "-----------------------------------"
            # Add quotes
            "$($Individualservice.name) was identified with an unquoted path ($imagePathCopy)"
            $executables = "`"$executables`""
            $NewImagePath = "$executables$arguments"
            # Change registry path to add the quotes
            $IndividualServicePath = $individualService.Name.Replace("HKEY_LOCAL_MACHINE", "HKLM:")
            # Update the ImagePath
            "changing to $NewImagePath"
            Set-ItemProperty -Path $IndividualServicePath -Name "ImagePath" -Value $newImagePath
        }
    }
}
Write-Host "Completed Unquoted Service Path Checking" -ForegroundColor Green
Write-Host "$counter services were identified and remediated" -ForegroundColor Green