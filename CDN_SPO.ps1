#Connect 
Import-Module Microsoft.Online.SharePoint.PowerShell -UseWindowsPowerShell
Connect-SPOService -Url https://enchantedrock-admin.sharepoint.com

#Enable CDN
Set-SPOTenantCdnEnabled -CdnType Public -Enable $true
Get-SPOTenantCdnEnabled -CdnType Public


#Add a CDN Origin
Add-SPOTenantCdnOrigin -CdnType Public -OriginUrl "*/SiteAssets/CDNAssets"
Get-SPOTenantCdnOrigins -CdnType Public

#Policy
Get-SPOTenantCdnPolicies -CdnType Public