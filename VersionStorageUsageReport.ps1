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


#Track progress of the job to generate report for a site or OneDrive account 
#Current Jobs
$reportUrl = "https://enchantedrock.sharepoint.com/sites/erintranet/IT Corporate/Reports in progress - restricted/VersionStorageUsageReport_FullSite.csv"	
Get-SPOSiteFileVersionExpirationReportJobProgress -Identity $siteUrl -ReportUrl $reportUrl


<#
#Generate a version storage usage report for a library 	
New-SPOListFileVersionExpirationReportJob -Site $siteUrl -List $libName -ReportUrl $reportUrl
#>

#Track progress of the job to generate report for a library 
#Current Jobs
#$libName = "EPC"
#$reportUrl = "https://enchantedrock.sharepoint.com/sites/erintranet/IT Corporate/Reports in progress - restricted/VersionStorageUsageReport_EPCLibrary.csv"
#Get-SPOListFileVersionExpirationReportJobProgress -Site $siteUrl -List $libName -ReportUrl $reportUrl

<#Completed Jobs
$libName = "O&M"	
$reportUrl = "https://enchantedrock.sharepoint.com/sites/erintranet/IT Corporate/Reports in progress - restricted/VersionStorageUsageReport_OMLibrary.csv"
Get-SPOListFileVersionExpirationReportJobProgress -Site $siteUrl -List $libName -ReportUrl $reportUrl
#>

#Trim Versions using Automatic Policy for a library 
#$libName = "O&M"
#New-SPOListFileVersionBatchDeleteJob -Site $siteUrl -List $libName -Automatic

#Stop processing an in-progress library level trim job:
#Remove-SPOListFileVersionBatchDeleteJob -Site $siteUrl -List $libName

#Get status of a library level trimming job:
$libName = "O&M"
Get-SPOListFileVersionBatchDeleteJobProgress -Site $siteUrl -List $libName