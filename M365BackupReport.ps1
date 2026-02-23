#for all mailbox archives
#Get-MailboxStatistics -Identity "user@example.com" -Archive | Select DisplayName, TotalItemSize, ItemCount

#for all sites including OneDrives
#Get-PnPRecycleBinItem -SecondStage

#Live data is below
#Exchange 6.2TB
#SharePoint 9.1TB
#OneDrive 6.0 TB

$TenantAdminURL = "https://enchantedrock-admin.sharepoint.com/"
Connect-PnPOnline -Url $TenantAdminURL -Interactive -ClientId 4ac6eede-e81e-4d22-abad-0d43c51486f2  

#$storageUsed = (Get-PnPTenantRecycleBinItem | Measure-Object -Property Size -Sum).Sum

$sitescollection = Get-PnPTenantSite -IncludeOneDriveSites
$TotalStorageUsed = 0
$i=0
foreach ($site in $sitescollection) {

    write-host "Processing site $($site.Url) ($i of $($sitescollection.Count))"

    Connect-PnPOnline -Url $site.Url -Interactive -ClientId 4ac6eede-e81e-4d22-abad-0d43c51486f2 
    #calculate second stage storage usage

    Get-PnPRecycleBinItem -SecondStage 
    $storageUsed = (Get-PnPRecycleBinItem -SecondStage | Measure-Object -Property Size -Sum).Sum

    Write-Host "Storage used in second stage recycle bin for site $($site.Url): $($storageUsed / 1GB) GB"   
    $TotalStorageUsed += $storageUsed
    $i++
}
Write-Host "Total storage used in second stage recycle bin across all sites: $($TotalStorageUsed / 1GB) GB"