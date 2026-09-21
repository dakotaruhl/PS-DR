<#
 Sets a target site to copy files to, using a list of site collections from an Excel file. 
#>

#Start-Transcript -Path "C:\Users\DakotaRuhl\Documents\ProjectManagement\CopySiteFiles_Transcript_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt" -Append 

# Set up Excel module and read in file 
 Import-Module ImportExcel
 $filePath = "C:\Users\DakotaRuhl\Documents\SP Portfolio\Account Management\ComparePMtoAM.xlsx"
 $Worksheet = "Revised AM List"
 $columnName = "Link fixes"
 $excelData = Import-Excel -Path $filePath -WorksheetName $Worksheet
 $columnValues = $excelData | Select-Object -ExpandProperty $columnName

# Connect to SharePoint Online
$TenantAdminURL = "https://enchantedrock-admin.sharepoint.com/"
Connect-PnPOnline -Url $TenantAdminURL -Interactive -ClientId 4ac6eede-e81e-4d22-abad-0d43c51486f2 

# Set Destination for Copy
$CopyToSiteUrl = "https://enchantedrock.sharepoint.com/sites/communicationsexternal"
$CopyToTargetFolder = "Shared Documents/Archive"
Connect-PnPOnline -Url $CopyToSiteUrl -Interactive -ClientId 4ac6eede-e81e-4d22-abad-0d43c51486f2

# Initialize collection to store Site Collections
$SitesCollections = @()
foreach ($item in $columnValues) 
{
    try 
    {
        $CurrentSite = Get-PnPTenantSite $item -ErrorAction Stop
        $SitesCollections += $CurrentSite
        Write-Host -ForegroundColor Green "Added Site Collection: $($CurrentSite.Url)"
    }
    catch 
    {
        Write-Host -ForegroundColor Red "Site for $item not found. Skipping."
    }
}

#Initialize collections to store found and missing files, and overall report
$siteCollectionsResults = @()
$s = 0
foreach ($Site in $SitesCollections) 
{
    $s++
    Write-Host -foregroundcolor Magenta "`nProcessing Site Collection number $s of $($SitesCollections.Count)"
    Connect-PnPOnline -Url $Site.Url -Interactive -ClientId 4ac6eede-e81e-4d22-abad-0d43c51486f2
    $SiteFilesList = Get-PnPFolderItem -FolderSiteRelativeUrl $SiteLibrary -ItemType File -Recurse

    if($sitefilesList.count -eq 0) 
    {
        Write-Host -ForegroundColor Yellow "No files found in site: $($Site.Url). Skipping to next site."
        $siteCollectionsResults += [PSCustomObject]@{
                    SiteCollection = $Site.Url
                    FileCount  = "No files found"
                }
        continue
    }
    else {
        Write-Host -ForegroundColor Green "Found $($SiteFilesList.Count) files in site: $($Site.Url). Proceeding to copy files."
        $siteCollectionsResults += [PSCustomObject]@{
                    SiteCollection = $Site.Url
                    FileCount  = $SiteFilesList.Count
                }
    }

    #Determine destination folder based on site URL
    $topFolder = $Site.Url.Split("/")[-1]
    $DestFolder = "$CopyToTargetFolder/$($topFolder)"

    Connect-PnPOnline -Url $CopyToSiteUrl -Interactive -ClientId 4ac6eede-e81e-4d22-abad-0d43c51486f2
    
    Write-Host -foregroundcolor Yellow "Creating Folder: $DestFolder"
    Add-PnPFolder -Name $topFolder -Folder $CopyToTargetFolder | Out-Null #Supress output
    $destFolderURL = get-pnpfolder -Url $DestFolder

    #Set target folder to check for files in current site target
    $SiteLibrary = "/Shared Documents/General"
    Connect-PnPOnline -Url $Site.Url -Interactive -ClientId 4ac6eede-e81e-4d22-abad-0d43c51486f2
    $FolderList = Get-PnPFolderInFolder -FolderSiteRelativeUrl $SiteLibrary
    foreach ($folder in $FolderList) 
    {
        #Connect back to source site to get files
        Connect-PnPOnline -Url $Site.Url -Interactive -ClientId 4ac6eede-e81e-4d22-abad-0d43c51486f2
        $FilesList = Get-PnPFolderItem -FolderSiteRelativeUrl "$($SiteLibrary)/$($folder.Name)" -ItemType File -Recurse
        if ($FilesList.count -eq 0) 
        {
            #No files found, skip to next folder
            Write-Host -ForegroundColor Yellow "No files found in folder: $($folder.Name). Skipping to next folder."
            continue
        }
        else 
        {
            #Files found, proceed to copy
            Copy-PnPFolder -SourceUrl $folder.ServerRelativeUrl -TargetUrl $destfolderurl.serverrelativeurl -Force -IgnoreVersionHistory -Overwrite
            Write-Host -ForegroundColor Green "Found $($FilesList.Count) files in folder: $($folder.Name). Proceeding to copy files."
        }
        
    }
}

#Export report of site collections processed
$reportPath = "C:\Users\DakotaRuhl\Documents\SP Portfolio\Account Management\SiteCollections_CopyReport_$(Get-Date -Format 'yyyyMMdd_HHmmss').xlsx"
$siteCollectionsResults | Export-Excel -Path $reportPath  

#Debug
#$Site = $SitesCollections[0]
#$Folder = $FolderList[2]