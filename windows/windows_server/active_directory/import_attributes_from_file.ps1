foreach ($row in $csv) {
    $user = Get-ADUser -Identity $row.sAMAccountName -Properties * -ErrorAction SilentlyContinue

    if ($user.Enabled) {
        # Prepare new values
        $oldUser = @{}
        $propsReplace = @{}
        $propsSet = @{}

        if ($null -ne $user.GivenName) { $oldUser.GivenName = $user.GivenName; $propsReplace["GivenName"] = $row.newGivenName }
        else {
            $propsSet["GivenName"] = $row.newGivenName
        }

        if ($null -ne $user.sn) { $oldUser.sn = $user.sn; $propsReplace["sn"] = $row.newSurname }
        else {
            $propsSet["sn"] = $row.newSurname
        }

        if ($null -ne $user.DisplayName) { $oldUser.DisplayName = $user.DisplayName; $propsReplace["DisplayName"] = $row.newDisplayName }
        else {
            $propsSet["DisplayName"] = $row.newDisplayName
        }

        if ($null -ne $user.Title) { $oldUser.Title = $user.Title; $propsReplace["Title"] = $row.newTitle }
        else {
            $propsSet["Title"] = $row.newTitle
        }

        if ($null -ne $user.Department) { $oldUser.Department = $user.Department; $propsReplace["Department"] = $row.newDepartment }
        else {
            $propsSet["Department"] = $row.newDepartment
        }

        if ($null -ne $user.Manager) { $oldUser.Manager = (Get-ADUser -Identity $user.Manager).DisplayName; $propsReplace["Manager"] = (Get-ADUser -Filter "displayName -eq '$($row.newManager)'").DistinguishedName }
        else {
            $propsSet["Manager"] = (Get-ADUser -Filter "displayName -eq '$($row.newManager)'").DistinguishedName
        }

        if ($null -ne $user.physicalDeliveryOfficeName) { $oldUser.physicalDeliveryOfficeName = $user.physicalDeliveryOfficeName; $propsReplace["physicalDeliveryOfficeName"] = $row.newphysicalDeliveryOfficeName }
        else {
            $propsSet["physicalDeliveryOfficeName"] = $row.newphysicalDeliveryOfficeName
        }


        # Update user in one call
        if ($propsSet.Count -gt 0) {
            Set-ADUser -Identity $user -Add $propsSet -Replace $propsReplace
        }
        elseif ($propsReplace.Count -gt 0) {
            Set-ADUser -Identity $user -Replace $propsReplace
        }
        else {
            continue
        }
        
        # Output changes
        Write-Host "Updated user: $($user.sAMAccountName)"
        foreach ($key in $propsReplace.Keys + $propsSet.Keys) {
            $oldValue = $user.$key
            $newValue = $propsReplace[$key]
            if ($null -eq $newValue) { $newValue = $propsSet[$key] }
            Write-Host "${key}: $oldValue -> $newValue"
        }
        Write-Host "-----------------------------------"
    }
    else {
        Write-Host "User not found: $($row.sAMAccountName)"
    }
} 
