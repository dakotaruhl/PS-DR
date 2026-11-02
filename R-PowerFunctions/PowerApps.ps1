Install-Module -Name Microsoft.PowerApps.Administration.PowerShell -scope CurrentUser
Get-Module -ListAvailable Microsoft.PowerApps.Administration.PowerShell
Import-Module Microsoft.PowerApps.Administration.PowerShell
Import-Module Microsoft.PowerApps.PowerShell
import-module microsoft.graph.education 
Add-PowerAppsAccount

Get-AdminPowerAppEnvironmentRoleAssignment `
  -EnvironmentName "Enchanted Rock (default)" |
  Where-Object { $_.PrincipalEmail -eq "ndemattei@enchantedrock.com" } |
  Select PrincipalEmail, RoleName

Get-AdminPowerAppEnvironmentRoleAssignment `
  -EnvironmentName Default-0bdf0e1f-a359-4b5c-9b79-9357e35ff8c6 |
  Where-Object { $_.RoleName -eq "Environment Maker" } |
  Select PrincipalEmail, RoleName

  Get-MgPolicyAuthorizationPolicy | Select DefaultUserRolePermissions

  Get-AdminPowerAppEnvironment

  
Add-PowerAppsAccount

Set-AdminPowerAppEnvironmentRoleAssignment `
  -EnvironmentName Default-0bdf0e1f-a359-4b5c-9b79-9357e35ff8c6 `
  -PrincipalType User `
  -PrincipalObjectId 38d611d7-065d-49bc-aa51-4bb3793267fa `
  -RoleName "EnvironmentAdmin"

  Set-AdminPowerAppEnvironmentRoleAssignment -EnvironmentName 0bdf0e1f-a359-4b5c-9b79-9357e35ff8c6 -RoleName EnvironmentAdmin -PrincipalType User -PrincipalObjectId 38d611d7-065d-49bc-aa51-4bb3793267fa
