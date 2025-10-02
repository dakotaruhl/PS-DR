#import PS7 version
Import-Module Microsoft.Online.SharePoint.PowerShell -UseWindowsPowerShell

#Connect SPO Site
Connect-SPOService -Url https://enchantedrock-admin.sharepoint.com

#Configure Target Site
$siteUrl = "https://enchantedrock.sharepoint.com/sites/erintranet"

<#
#Generate a version storage usage report for a site or OneDrive account 	
New-SPOSiteFileVersionExpirationReportJob -Identity $siteUrl -ReportUrl $reportUrl 
#>

<#
#Track progress of the job to generate report for a site or OneDrive account 
#Current Jobs
$reportUrl = "https://enchantedrock.sharepoint.com/sites/erintranet/IT Corporate/Reports in progress - restricted/VersionStorageUsageReport_FullSite.csv"	
Get-SPOSiteFileVersionExpirationReportJobProgress -Identity $siteUrl -ReportUrl $reportUrl
#>


<#
Generate a version storage usage report for a library 
$libName = <libName>
$reportUrl = "https://enchantedrock.sharepoint.com/sites/erintranet/IT Corporate/Reports in progress - restricted/VersionStorageUsageReport_<libName>.csv"
New-SPOListFileVersionExpirationReportJob -Site $siteUrl -List $libName -ReportUrl $reportUrl
#>

<#
#Track progress of the job to generate report for a library 
#Current Jobs
$reportUrl = "https://enchantedrock.sharepoint.com/sites/erintranet/IT Corporate/Reports in progress - restricted/VersionStorageUsageReport_<libName>.csv"
$libName = <libName>
Get-SPOListFileVersionExpirationReportJobProgress -Site $siteUrl -List $libName -ReportUrl $reportUrl
#>

<#
Completed Jobs
#Libraries
$libName = "O&M"	
$reportUrl = "https://enchantedrock.sharepoint.com/sites/erintranet/IT Corporate/Reports in progress - restricted/VersionStorageUsageReport_OMLibrary.csv"
$libName = "EPC"
$reportUrl = "https://enchantedrock.sharepoint.com/sites/erintranet/IT Corporate/Reports in progress - restricted/VersionStorageUsageReport_EPCLibrary.csv"
Get-SPOListFileVersionExpirationReportJobProgress -Site $siteUrl -List $libName -ReportUrl $reportUrl
$libName = "Marketing"
$reportUrl = "https://enchantedrock.sharepoint.com/sites/erintranet/IT Corporate/Reports in progress - restricted/VersionStorageUsageReport_Marketing.csv"
Get-SPOListFileVersionExpirationReportJobProgress -Site $siteUrl -List $libName -ReportUrl $reportUrl

#Sites
$reportUrl = "https://enchantedrock.sharepoint.com/sites/erintranet/IT Corporate/Reports in progress - restricted/VersionStorageUsageReport_FullSite.csv"	
Get-SPOSiteFileVersionExpirationReportJobProgress -Identity $siteUrl -ReportUrl $reportUrl
#>

<#
#Trim Versions using Automatic Policy for a library 
$libName = "EPC"
New-SPOListFileVersionBatchDeleteJob -Site $siteUrl -List $libName -Automatic
#>

#Stop processing an in-progress library level trim job:
#Remove-SPOListFileVersionBatchDeleteJob -Site $siteUrl -List $libName

#Get status of a library level trimming job:
$libName = "EPC"
Get-SPOListFileVersionBatchDeleteJobProgress -Site $siteUrl -List $libName

<#
#Set Automatic version history limits on a site
$siteUrl = "https://enchantedrock.sharepoint.com/sites/MarketingTeamExternal"
Set-SPOSite -Identity $siteUrl -EnableAutoExpirationVersionTrim $true

The setting for new document libraries takes effect immediately. Please run Get-SPOSite to check the newly set values on properties EnableAutoExpirationVersionTrim, ExpireVersionsAfterDays,
MajorVersionLimit. The setting for existing document libraries may take 24 hours to take effect. Please run Get-SPOSiteVersionPolicyJobProgress to check the progress. The setting for existing libraries 
does not trim existing versions to meet the newly set limits.
#>

<#
#Get status of site level version policy job:
$siteUrl = "https://enchantedrock.sharepoint.com/sites/MarketingTeam"
Get-SPOSiteVersionPolicyJobProgress -Identity $siteUrl
Get-SPOSite -Identity $siteUrl | Select-Object EnableAutoExpirationVersionTrim, ExpireVersionsAfterDays, MajorVersionLimit
#>