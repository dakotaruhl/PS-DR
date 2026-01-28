<#
 Sets a target site to copy files to, using a list of site collections from an Excel file, with a list of target site folders
#>

#Start-Transcript -Path "C:\Users\DakotaRuhl\Documents\ProjectManagement\CopySiteFiles_Transcript_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt" -Append 

# Set up Excel module and read in file 
 Import-Module ImportExcel
 $filePath = "C:\Users\DakotaRuhl\Documents\SP Portfolio\Project Management\HEB Sites.xlsx"
 $Worksheet = "Sources"
 $sourceColumnName = "SiteCollection"
 #$targetColumnName = ""
 $excelData = Import-Excel -Path $filePath -WorksheetName $Worksheet

 $sourceColumnValues = $excelData | Select-Object -ExpandProperty $sourceColumnName
 #$targetColumnValues = $excelData | Select-Object -ExpandProperty $targetColumnName

# Connect to SharePoint Online
$TenantAdminURL = "https://enchantedrock-admin.sharepoint.com/"
Connect-PnPOnline -Url $TenantAdminURL -Interactive -ClientId 4ac6eede-e81e-4d22-abad-0d43c51486f2 

# Set Destination for Copy
$CopyToSiteUrl = "https://enchantedrock.sharepoint.com/sites/erintranet/"
$CopyToTargetFolder = "EPC/ERE/00 ERE Projects/HEB (EREJB161012)/PRELIMINARY FOLDERS - DO NOT USE"
#$CopyToTargetFolder = "/EPC/ERE/00 ERE Projects/HEB (EREJB161012)/01 Stores"
Connect-PnPOnline -Url $CopyToSiteUrl -Interactive -ClientId 4ac6eede-e81e-4d22-abad-0d43c51486f2

#Initialize collection to store Site Collections
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

#$TargetSiteFolders = @()
#foreach ($item in $targetColumnValues) 
#{
#        $TargetSiteFolders += $item
#        Write-Host -ForegroundColor Green "Added Target Site Folder: $($item)"  
#}


#Initialize collections 
$errorFolderResults = @()
$s = 0
foreach ($Site in $SourceSitesCollections) 
{
    $s++
    Connect-PnPOnline -Url $CopyToSiteUrl -Interactive -ClientId 4ac6eede-e81e-4d22-abad-0d43c51486f2
    Add-PnPFolder -Name $Site.Title -Folder $CopyToTargetFolder | Out-Null
    $destFolderURL = get-pnpfolder -Url "$CopyToTargetFolder/$($Site.Title)"
    Write-Host -ForegroundColor Magenta "Created destination folder: $($destFolderURL.ServerRelativeUrl)"

    Write-Host -foregroundcolor Magenta "`nProcessing Site Collection number $s of $($SourceSitesCollections.Count)"
    Connect-PnPOnline -Url $Site.Url -Interactive -ClientId 4ac6eede-e81e-4d22-abad-0d43c51486f2  
    #Determine destination folder based on site URL
    #$DestFolder = "$CopyToTargetFolder/$($targetColumnValues[$s-1])"
    #$destFolderURL = get-pnpfolder -Url $DestFolder
    Write-Host -foregroundcolor Magenta "`nCopying files from $($Site.url)"

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





#Debugging single site copy
# $site = Get-PnPTenantSite  "https://enchantedrock.sharepoint.com/sites/HEB810Rockwall-Project" 
# $PMTargetSiteUrl = "https://enchantedrock.sharepoint.com/sites/erintranet/"
# $PMTempLocation = "EPC/ERE/00 ERE Projects/HEB (EREJB161012)/PRELIMINARY FOLDERS - DO NOT USE"
# Connect-PnPOnline -Url $PMTargetSiteUrl -Interactive -ClientId 4ac6eede-e81e-4d22-abad-0d43c51486f2
# Add-PnPFolder -Name $site.Title -Folder $PMTempLocation
# $destFolderURL = get-pnpfolder -Url "$PMTempLocation/$($site.Title)"

# Connect-PnPOnline -Url "https://enchantedrock.sharepoint.com/sites/HEB810Rockwall-Project" -Interactive -ClientId 4ac6eede-e81e-4d22-abad-0d43c51486f2
# $SiteLibrary = "/Shared Documents/General"
# $FolderList = Get-PnPFolderInFolder -FolderSiteRelativeUrl $SiteLibrary
# $i=0
# foreach ($folder in $FolderList) 
# {
#     $i++
#     Write-Host -foregroundcolor Yellow "`nCopying folder number $i of $($FolderList.Count): $($folder.Name)"
#     try 
#     {
#         Copy-PnPFolder -SourceUrl $folder.ServerRelativeUrl -TargetUrl $destfolderurl.serverrelativeurl -Force -IgnoreVersionHistory -ErrorAction Stop
#         Write-Host -ForegroundColor Green "Successfully copied folder $($folder.Name)."
#     }
#     catch 
#     {
#         Write-Host -ForegroundColor Red "Error copying folder $($folder.Name). Skipping."
#         $errorFolderResults += [PSCustomObject]@{
#                 SiteCollection = $Site.Url
#                 FolderName     = $folder.Name
#                 ErrorMessage   = $_.Exception.Message
#             }
#         continue
#     }
# }

# set-pnptenantsite $site -lockstate readonly