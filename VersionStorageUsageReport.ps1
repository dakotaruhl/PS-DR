Import-Module Microsoft.Online.SharePoint.PowerShell -ErrorAction Stop

$TenantId   = "0bdf0e1f-a359-4b5c-9b79-9357e35ff8c6"
$ClientId   = "97d01716-c2a3-4311-9b73-09ac8579cbf1"
$Thumbprint = "94EF4B57723E2E90CD56F2F407EF6AFBEF275392"
$AdminUrl   = "https://enchantedrock-admin.sharepoint.com"

# Certificate object method
$cert = Get-Item "Cert:\LocalMachine\My\$Thumbprint" -ErrorAction Stop

Connect-SPOService `
    -Url $AdminUrl `
    -ClientId $ClientId `
    -TenantId $TenantId `
    -Certificate $cert `
    -ErrorAction Stop

#Confgure Target Sites, all sites except /erintranet 
$AllSites = Get-SPOSite -Limit All
$TargetSites = $AllSites | Where-Object { $_.Url -notlike "https://enchantedrock.sharepoint.com/sites/erintranet" }

$siteUrl = "https://enchantedrock.sharepoint.com/sites/erintranet"

###REPORT JOBS###
$reportLibName = "Culture Committee"
$reportUrl = "https://enchantedrock.sharepoint.com/sites/erintranet/IT Corporate/Reports in progress - restricted/VersionStorageUsageReport_$reportLibName.csv"

$reportLibName = "Asset Mgmt."
$reportUrl = "https://enchantedrock.sharepoint.com/sites/erintranet/IT Corporate/Reports in progress - restricted/VersionStorageUsageReport_$reportLibName.csv"

$reportLibName = "Employee Services"
$reportUrl = "https://enchantedrock.sharepoint.com/sites/erintranet/IT Corporate/Reports in progress - restricted/VersionStorageUsageReport_$reportLibName.csv"

$reportLibName = "Building Management"
$reportUrl = "https://enchantedrock.sharepoint.com/sites/erintranet/IT Corporate/Reports in progress - restricted/VersionStorageUsageReport_$reportLibName.csv"

#Generate a version storage usage report for a library 
New-SPOListFileVersionExpirationReportJob -Site $siteUrl -List $reportLibName -ReportUrl $reportUrl
#Track progress of the job to generate report for a library 
Get-SPOListFileVersionExpirationReportJobProgress -Site $siteUrl -List $reportLibName -ReportUrl $reportUrl

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

#####TRIM JOBS#####
$trimLibName = "Asset Mgmt."

#Trim Versions using Automatic Policy for a library 
New-SPOListFileVersionBatchDeleteJob -Site $siteUrl -List $trimLibName -Automatic

#Stop processing an in-progress library level trim job:
Remove-SPOListFileVersionBatchDeleteJob -Site $siteUrl -List $trimLibName

#Get status of a library level trimming job:
Get-SPOListFileVersionBatchDeleteJobProgress -Site $siteUrl -List $trimLibName 

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