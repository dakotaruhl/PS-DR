#CSOM based attempt

# Load required assemblies
Add-Type -Path "C:\Program Files\Common Files\Microsoft Shared\Web Server Extensions\16\ISAPI\Microsoft.SharePoint.Client.dll"
Add-Type -Path "C:\Program Files\Common Files\Microsoft Shared\Web Server Extensions\16\ISAPI\Microsoft.SharePoint.Client.Runtime.dll"

# Set parameters
$SiteUrl = "https://enchantedrock.sharepoint.com/sites/erintranet"
$FolderServerRelativeUrl = "/sites/erintranet/Tech Wiki"

# Install Microsoft.Identity.Client via NuGet
#Add-Type -Path "C:\Program Files\PowerShell\7\Modules\Microsoft.PowerShell.PSResourceGet\dependencies\Microsoft.Identity.Client.dll"

#Auth1
$ClientId = "4ac6eede-e81e-4d22-abad-0d43c51486f2"
$TenantId = "0bdf0e1f-a359-4b5c-9b79-9357e35ff8c6"
$Scopes = @("https://enchantedrock.sharepoint.com/.default")

$TokenResponse = Get-MsalToken -ClientId $ClientId -TenantId $TenantId -Scopes $Scopes
$AccessToken = $TokenResponse.AccessToken

$Ctx = New-Object Microsoft.SharePoint.Client.ClientContext("https://enchantedrock.sharepoint.com/sites/erintranet")
$Ctx.ExecutingWebRequest += {
    param ($sender, $e)
    $e.WebRequestExecutor.WebRequest.Headers.Add("Authorization", "Bearer $AccessToken")
}

#Auth2
Add-Type -Path "C:\Program Files\WindowsPowerShell\Modules\SharePointPnPPowerShellOnline\<version>\OfficeDevPnP.Core.dll"

$siteUrl = "https://enchantedrock.sharepoint.com/sites/erintranet"
$authManager = New-Object PnP.Framework.AuthenticationManager
$ctx = $authManager.GetWebLoginClientContext($siteUrl)

# Now you can use CSOM as usual
$web = $ctx.Web
$ctx.Load($web)
$ctx.ExecuteQuery()
Write-Host "Connected to site: $($web.Title)"

#auth3
#Add required references to OfficeDevPnP.Core and SharePoint client assembly
[System.Reflection.Assembly]::LoadFrom("C:\Program Files\WindowsPowerShell\Modules\SharePointPnPPowerShellOnline\3.29.2101.0\OfficeDevPnP.Core.dll") 
[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SharePoint.Client")
[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SharePoint.Client.Runtime")
 
$siteURL = "https://contoso.sharepoint.com/sites/siten_name"
  
$AuthenticationManager = new-object OfficeDevPnP.Core.AuthenticationManager
$ctx = $AuthenticationManager.GetWebLoginClientContext($siteURL)
$ctx.Load($ctx.Web)
$ctx.ExecuteQuery()
  
Write-Host "Title: " $ctx.Web.Title -ForegroundColor Green
Write-Host "Description: " $ctx.Web.Description -ForegroundColor Green


# Create client context
$Context = New-Object Microsoft.SharePoint.Client.ClientContext($SiteUrl)
$Context.Credentials = $Credentials

# Get the folder
$Web = $Context.Web
$Folder = $Web.GetFolderByServerRelativeUrl($FolderServerRelativeUrl)
$Context.Load($Folder)
$Context.Load($Folder.ListItemAllFields)
$Context.ExecuteQuery()

# Check if folder has unique permissions
$ListItem = $Folder.ListItemAllFields
$Context.Load($ListItem.RoleAssignments)
$Context.Load($ListItem, "HasUniqueRoleAssignments")
$Context.ExecuteQuery()

Write-Host "Folder: $($Folder.Name)"
Write-Host "Has Unique Permissions: $($ListItem.HasUniqueRoleAssignments)"

# Loop through role assignments
foreach ($roleAssignment in $ListItem.RoleAssignments) {
    $Context.Load($roleAssignment.Member)
    $Context.Load($roleAssignment.RoleDefinitionBindings)
    $Context.ExecuteQuery()

    $MemberName = $roleAssignment.Member.Title
    $PermissionLevels = $roleAssignment.RoleDefinitionBindings | ForEach-Object { $_.Name }

    Write-Host "User/Group: $MemberName"
    Write-Host "Permissions: $($PermissionLevels -join ', ')"
}
