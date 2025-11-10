Import-Module Microsoft.Online.SharePoint.PowerShell -UseWindowsPowerShell
$AdminCenterURL = "https://enchantedrock-admin.sharepoint.com/"
Connect-SPOService -url $AdminCenterURL 

$SiteCollection = Get-SPOSite -limit ALL 
$FilteredSites = $SiteCollection | Where-Object { $_.Template -eq "STS#3" -and $_.StorageUsageCurrent -gt 1000 }

$FilteredSites | Where-Object { $_.Description -eq $_.Title } | Select-Object Url, Title, Owner, StorageUsageCurrent, Template, Description
$FilteredSites = $SiteCollection | Select-Object Url, Title, Owner, StorageUsageCurrent, Template, Description 

Connect-MicrosoftTeams
$teamcollection = get-team 
$test = get-team -groupid 27c3dc7c-f524-4df1-9f85-d70110e0e492

Connect-Graph -Scopes "Group.Read.All","User.Read.All", "https://enchantedrock.oneplanacademy.com/wp-content/plugins/miniorange-saml-20-single-sign-on//user_impersonation"
invoke-webrequest -uri "https://graph.microsoft.com/v1.0/groups/27c3dc7c-f524-4df1-9f85-d70110e0e492/members" -Method GET 
Connect-Graph -Scopes "https://enchantedrock.oneplanacademy.com/wp-content/plugins/miniorange-saml-20-single-sign-on//user_impersonation"