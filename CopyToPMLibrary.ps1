<#
 Sets a target site to copy files to, using a list of site collections from an Excel file, with a list of target site folders
#>

#Start-Transcript -Path "C:\Users\DakotaRuhl\Documents\ProjectManagement\CopySiteFiles_Transcript_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt" -Append 

# Set up Excel module and read in file 
 Import-Module ImportExcel
 $filePath = "C:\Users\DakotaRuhl\Documents\SP Portfolio\"
 $Worksheet = ""
 $sourceColumnName = ""
 $targetColumnName = ""
 $excelData = Import-Excel -Path $filePath -WorksheetName $Worksheet

 $sourceColumnValues = $excelData | Select-Object -ExpandProperty $sourceColumnName
 $targetColumnValues = $excelData | Select-Object -ExpandProperty $targetColumnName

# Connect to SharePoint Online
$TenantAdminURL = "https://enchantedrock-admin.sharepoint.com/"
Connect-PnPOnline -Url $TenantAdminURL -Interactive -ClientId 4ac6eede-e81e-4d22-abad-0d43c51486f2 

# Set Destination for Copy
$CopyToSiteUrl = "https://enchantedrock.sharepoint.com/sites/erintranet"
$CopyToTargetFolder = "/EPC/ERE/00 ERE Projects/HEB (EREJB161012)/01 Stores"
Connect-PnPOnline -Url $CopyToSiteUrl -Interactive -ClientId 4ac6eede-e81e-4d22-abad-0d43c51486f2

# Initialize collection to store Site Collections
$SourceSitesCollections = @()
foreach ($item in $sourceColumnValues) 
{
    try 
    {
        $CurrentSite = Get-PnPTenantSite $item -ErrorAction Stop
        $SourceSitesCollections += $CurrentSite
        Write-Host -ForegroundColor Green "Added Source Site: $($CurrentSite.Url)"
    }
    catch 
    {
        Write-Host -ForegroundColor Red "Site for $item not found. Skipping."
    }
}

$TargetSiteFolders = @()
foreach ($item in $targetColumnValues) 
{
        $TargetSiteFolders += $item
        Write-Host -ForegroundColor Green "Added Target Site Folder: $($item)"  
}


#Initialize collections to store found and missing files, and overall report
$errorFolderResults = @()
$s = 0
foreach ($Site in $SourceSitesCollections) 
{
    $s++
    Write-Host -foregroundcolor Magenta "`nProcessing Site Collection number $s of $($SourceSitesCollections.Count)"
    Connect-PnPOnline -Url $Site.Url -Interactive -ClientId 4ac6eede-e81e-4d22-abad-0d43c51486f2  

    #Determine destination folder based on site URL
    $DestFolder = "$CopyToTargetFolder/$($targetColumnValues[$s-1])"
    $destFolderURL = get-pnpfolder -Url $DestFolder
    Write-Host -foregroundcolor Magenta "`nCopying files from $($Site.url) to $($DestFolder)"

    #Set target folder to check for files in current site target
    $SiteLibrary = "/Shared Documents/General"
    $FolderList = Get-PnPFolderInFolder -FolderSiteRelativeUrl $SiteLibrary
    $i=0
    foreach ($folder in $FolderList) 
    {
        $i++
        Write-Host -foregroundcolor Yellow "`nCopying folder number $i of $($FolderList.Count): $($folder.Name)"
        try 
        {
            Copy-PnPFolder -SourceUrl $folder.ServerRelativeUrl -TargetUrl $destfolderurl.serverrelativeurl -Force -IgnoreVersionHistory -ErrorAction Stop
            Write-Host -ForegroundColor Green "Successfully copied folder $($folder.Name)."
        }
        catch 
        {
            Write-Host -ForegroundColor Red "Error copying folder $($folder.Name). Skipping."
            $errorFolderResults += [PSCustomObject]@{
                    SiteCollection = $Site.Url
                    FolderName     = $folder.Name
                    ErrorMessage   = $_.Exception.Message
                }
            continue
        }
    }
}

#Export report of site collections processed
$reportPath = "C:\Users\DakotaRuhl\Documents\SP Portfolio\Project Management\errorFolderResults_$(Get-Date -Format 'yyyyMMdd_HHmmss').xlsx"
$errorFolderResults | Export-Excel -Path $reportPath  

#Debug
#$Site = $SitesCollections[0]
#$Folder = $FolderList[2]


https://enchantedrock.sharepoint.com/sites/erintranet/EPC/ERE/00%20ERE%20Projects/HEB%20(EREJB161012)/01%20Stores/HEB%20815%20-%20Irving
https://enchantedrock.sharepoint.com/sites/erintranet/EPC/Forms/AllItems.aspx?id=%2Fsites%2Ferintranet%2FEPC%2FERE%2F00%20ERE%20Projects%2FHEB%20%28EREJB161012%29%2F01%20Stores%2FHEB%20815%20%2D%20Irving&viewid=b7a6b272%2D8163%2D44e1%2Daa39%2D7e60f451a3b2&csf=1&web=1&e=hl4KA5&CID=9e3e638c%2D77f7%2D4474%2Db0e2%2D47dda0fdce7f&FolderCTID=0x012000C02409524BF7364C8EAB0263A001E833
https://enchantedrock.sharepoint.com/:f:/r/sites/erintranet/EPC/ERE/00%20ERE%20Projects/HEB%20(EREJB161012)/01%20Stores/HEB%20815%20-%20Irving

https://enchantedrock.sharepoint.com/sites/HEB815DFWSS3-Irving/Shared%20Documents/General

Connect-PnPOnline -Url "https://enchantedrock.sharepoint.com/sites/HEB815DFWSS3-Irving" -Interactive -ClientId 4ac6eede-e81e-4d22-abad-0d43c51486f2
Copy-PnPFolder -SourceUrl "Shared%20Documents/General" -TargetUrl "https://enchantedrock.sharepoint.com/sites/erintranet/EPC/ERE/00 ERE Projects/HEB (EREJB161012)/01 Stores/HEB 815 - Irving" -Force -IgnoreVersionHistory