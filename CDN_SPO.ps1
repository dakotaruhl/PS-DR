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

https://enchantedrock.sharepoint.com/sites/BrandGuide/Image Assets/Office Templates Thumbnail.jpg

#Brand Center - Add an asset library to the organization assets
Add-SPOOrgAssetsLibrary -LibraryUrl "https://enchantedrock.sharepoint.com/sites/BrandGuide/Office Template Assets" -OrgAssetType OfficeTemplateLibrary -CdnType Public -ThumbnailUrl "https://enchantedrock.sharepoint.com/sites/BrandGuide/Image Assets/Office Templates Thumbnail.jpg"
get-SPOOrgAssetsLibrary
Set-SPOOrgAssetsLibrary -LibraryUrl "https://enchantedrock.sharepoint.com/sites/BrandGuide/Image Assets" -ThumbnailUrl "https://enchantedrock.sharepoint.com/sites/BrandGuide/Image Assets/Logos/ER-Arch-Color.jpg"