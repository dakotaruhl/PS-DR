#Set Parameters
$AdminCenterURL="https://enchantedrock-admin.sharepoint.com/"
#user with the ID mismatch
$UserLoginID = "i:0#.f|membership|manguiano@yourcompany.com"
#enter user, that is sharepoint admin
$SiteCollectionAdmin = "admin-dr@enchantedrock.com"

#import PowerShell 7 SPO
Import-Module Microsoft.Online.SharePoint.PowerShell -UseWindowsPowerShell

#Connect to SharePoint Online
Connect-SPOService -Url $AdminCenterURL
 

#Get all Personal Site collections
$PSitesUrl = Get-SPOSite -Template "SPSPERS" -limit ALL -includepersonalsite $True | Select URL

Foreach ($PSiteUrl in $PSitesUrl.url)
{
	#Add Site collection Admin
	Set-SPOUser -site $PSiteUrl -LoginName $SiteCollectionAdmin -IsSiteCollectionAdmin $True
    
	#remove the user from "All people" personal site
	Remove-SPOUser -Site $PSiteUrl -LoginName $UserLoginID

	#Remove Site collection Admin
	Set-SPOUser -site $PSiteUrl -LoginName $SiteCollectionAdmin -IsSiteCollectionAdmin $False
}

#Remove admin from single site collection
$PSiteUrl = "https://enchantedrock-my.sharepoint.com/personal/ggiles_enchantedrock_com"
$SiteCollectionAdmin = "admin-dr@enchantedrock.com"

Get-SPOUser -Site $PSiteUrl -LoginName $SiteCollectionAdmin | FL
Set-SPOUser -site $PSiteUrl -LoginName $SiteCollectionAdmin -IsSiteCollectionAdmin $False