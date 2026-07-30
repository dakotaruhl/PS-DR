##############
# https://morgantechspace.com/2018/07/export-odfb-users-storage-size-report-powershell.html
# This powershell script get and export all personal sites and storage details to csv file.
##############

#Sets the Script Directory to the location the .ps1 file is located
$ScriptDir = Split-Path $script:MyInvocation.MyCommand.Path


$AdminSiteURL="https://enchantedrock-admin.sharepoint.com"
#Connect to SharePoint Online Admin Site
Connect-SPOService -Url $AdminSiteURL


$Result=@()
#Get all OneDrive for Business sites
$oneDriveSites = Get-SPOSite -IncludePersonalSite $true -Limit All -Filter "Url -like '-my.sharepoint.com/personal/'"
$oneDriveSites | ForEach-Object {
$site = $_
$Result += New-Object PSObject -property @{ 
UserName = $site.Owner
Size_inGB = $site.StorageUsageCurrent/1024
StorageQuota_inGB = $site.StorageQuota/1024
WarningSize_inGB =  $site.StorageQuotaWarningLevel/1024
OneDriveSiteUrl = $site.URL
}
}
$Result | Select UserName, Size_inGB, StorageQuota_inGB, WarningSize_inGB, OneDriveSiteUrl |
Export-CSV "$ScriptDir\Reports\OneDrive-for-Business-Size-Report.csv" -NoTypeInformation -Encoding UTF8