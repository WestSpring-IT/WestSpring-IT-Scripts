<#
.SYNOPSIS
Installs a list of required PowerShell modules if they are not already present.

.DESCRIPTION
The `install_required_modules` function checks for the presence of each module specified in the input array.
If a module is not found, it attempts to install it using `Install-Module` with the `CurrentUser` scope.
The function provides console output indicating whether each module was already installed or successfully installed.
If a module fails to install, an error message is displayed and the function returns `$false`.

.PARAMETER modules
An array of module names to check and install if they are not already available.
**Type:** Array  
**Mandatory:** Yes  

.EXAMPLE
install_required_modules -modules @("PSReadLine", "Az.Accounts")

#>
function install_required_modules {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [array]$modules
    )

    foreach ($module in $modules) {
        $modulePresent = Get-Module -Name $module -ListAvailable
        If (!($modulePresent)) {
            $moduleInstall = Install-Module -Name $module -Scope CurrentUser -Force -AllowClobber
            write-host $moduleInstall
            If (!(Get-Module -Name $module -ListAvailable)) {
                Write-Host "Module $module could not be installed." -ForegroundColor Red
                return $false
            }
        }
        Else {
            write-host "Module $module is already installed." -ForegroundColor Green
        }
    }
}