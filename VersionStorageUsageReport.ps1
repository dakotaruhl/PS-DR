#import PS7 version
Import-Module Microsoft.Online.SharePoint.PowerShell -UseWindowsPowerShell

#Connect SPO Site
Connect-SPOService -Url https://enchantedrock-admin.sharepoint.com

#Configure Target Site and Report URL
$siteUrl = "https://enchantedrock.sharepoint.com/sites/erintranet"
$reportUrl = "https://enchantedrock.sharepoint.com/sites/erintranet/IT Corporate/Reports in progress - restricted/VersionStorageUsageReport_EPCLibrary.csv"
$libName = "EPC"

#Generate a version storage usage report for a site or OneDrive account 	
####New-SPOSiteFileVersionExpirationReportJob -Identity $siteUrl -ReportUrl $reportUrl 

#Track progress of the job to generate report for a site or OneDrive account 	
##Get-SPOSiteFileVersionExpirationReportJobProgress -Identity $siteUrl -ReportUrl $reportUrl

#Generate a version storage usage report for a library 	
####New-SPOListFileVersionExpirationReportJob -Site $siteUrl -List $libName -ReportUrl $reportUrl

#Track progress of the job to generate report for a library 
<#
#Current Jobs
$libName = "EPC"
$libName = "O&M"	
Get-SPOListFileVersionExpirationReportJobProgress -Site $siteUrl -List $libName -ReportUrl $reportUrl
#>