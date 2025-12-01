#Parameters
$SiteURL = "https://enchantedrock.sharepoint.com/sites/erintranet"
$FileURL= "https://enchantedrock.sharepoint.com/sites/erintranet/OM/12.%20Work%20Instruction%20Guidelines/Corrective%20Actions%20&%20CSI/CSI%20Process%20and%20Log/ERO%20CSI%20Review%20Request%20Log.xlsx"

$file = Get-PnPFile  -Url $FileURL -AsFileObject -ErrorAction Stop

  
#Connect to PnP Online
Connect-PnPOnline -Url $SiteURL -Interactive -ClientId 4ac6eede-e81e-4d22-abad-0d43c51486f2
  
#Get all versions of the File
$versions = Get-PnPProperty  -ClientObject $file -Property Versions 
$versions = $versions | Sort-Object -Property Created 

$i = 0
foreach ($version in $versions) 
{
    if ($version.Created -lt (Get-Date).AddDays(-200)) 
    {
        $i++
        Write-Host -ForegroundColor Green "version $($version.VersionLabel) created on $($version.Created)"
        $version.DeleteObject()
        Invoke-PnPQuery
    }
}
Write-Host -ForegroundColor Yellow "Total versions older than 200 days to be deleted: #$i"

$versions = Get-PnPProperty  -ClientObject $file -Property Versions 
$versions = $versions | Sort-Object -Property Created 
Write-Host -ForegroundColor Yellow "Deleted versions older than 200 days. There are #$($versions.Count) versions remaining."