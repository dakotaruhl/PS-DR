##Install Module if needed
#Install-Module Microsoft.Graph -Scope CurrentUser -Repository PSGallery -Force

##Update module if needed
Import-Module Microsoft.Graph.Sites

##Connect to Microsoft Graph
Connect-MgGraph -Scopes "Sites.Read.All"

#MGSitePermission for objects https://learn.microsoft.com/en-us/powershell/module/microsoft.graph.sites/get-mgsitepermission?view=graph-powershell-1.0

# Get the site ID (replace with your site name or ID)
$site = Get-MgSite -Search "Erintranet"

# Get the list (document library) ID (replace with your library name or ID)
#$list = Get-MgSiteList -SiteId $site.Id 
$list = "62a63195-dd56-4447-ab75-1386877a4fa7"

$listitemid = "e1b34312-abc7-4fca-9ad3-c725e9574e20"

# Get the list item by its ID
$listItem = Get-MgSiteListItem -SiteId $site.Id -ListId $list -ListItemId $listitemid

# Display the properties of the item
$listItem.WebUrl