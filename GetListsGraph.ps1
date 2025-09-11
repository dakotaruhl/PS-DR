##Install Module if needed
#Install-Module Microsoft.Graph -Scope CurrentUser -Repository PSGallery -Force

##Update module if needed
Import-Module Microsoft.Graph.Sites

##Connect to Microsoft Graph
Connect-MgGraph -Scopes "Sites.Read.All"

$siteid = "enchantedrock.sharepoint.com/sites/erintranet"
#OM Library
$listid = "62a63195-dd56-4447-ab75-1386877a4fa7"

Get-MgSiteList -SiteId $siteId -ListId $listId

