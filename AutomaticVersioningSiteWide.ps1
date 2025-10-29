Import-Module Microsoft.Online.SharePoint.PowerShell -UseWindowsPowerShell
Connect-SPOService -Url https://enchantedrock-admin.sharepoint.com

#Set site URL
$siteUrl = "https://enchantedrock.sharepoint.com/sites/marketing2"

#View version history limits set on a site
Get-SPOSite -Identity $siteUrl | fl Url, EnableAutoExpirationVersionTrim, ExpireVersionsAfterDays, MajorVersionLimit

#Enable automatic versioning on the site (Not trimming versions, but should set policy to new and existing libraries)
Set-SPOSite -Identity $siteUrl -EnableAutoExpirationVersionTrim $true

#Check the status of the version changes to existing libraries on the site
Get-SPOSiteVersionPolicyJobProgress -Identity $siteUrl

<#Status 	            Description
  NoRequestFound 	    There are no requests on the site to set or update version settings on existing document libraries.
  New 	                The update request is New and is not processed yet.
  InProgress 	        The update request is processed and the settings update request is in progress.
  CompleteSuccess       The update request is completed successfully.
  CompleteWithFailure   The update request is completed, but setting update on some document libraries has failed.
#>

Set-SPOSite -Identity https://enchantedrock-my.sharepoint.com/personal/camthor_enchantedrock_com -DefaultShareLinkRole Edit