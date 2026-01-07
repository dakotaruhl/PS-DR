<#

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
$CopyToSiteUrl = "https://enchantedrock.sharepoint.com/sites/accountmanagement"
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
$s = 0
foreach ($Site in $SitesCollections) 
{
    $s++
    Write-Host -foregroundcolor Magenta "`nProcessing Site Collection number $s of $($SitesCollections.Count)"
    
    #Determine destination folder based on site URL
    $topFolder = $Site.Url.Split("/")[-1]
    $DestFolder = "$CopyToTargetFolder/$($topFolder)"
    Write-Host -foregroundcolor Yellow "Creating Folder: $DestFolder"
    Connect-PnPOnline -Url $CopyToSiteUrl -Interactive -ClientId 4ac6eede-e81e-4d22-abad-0d43c51486f2
    Add-PnPFolder -Name $topFolder -Folder $CopyToTargetFolder | Out-Null #Supress output

    #Set target folder to check for files in current site target
    $SiteLibrary = "/Shared Documents/General"
    Connect-PnPOnline -Url $Site.Url -Interactive -ClientId 4ac6eede-e81e-4d22-abad-0d43c51486f2
    $FolderList = Get-PnPFolderInFolder -FolderSiteRelativeUrl $SiteLibrary
    foreach ($folder in $FolderList) 
    {
        Write-Host -ForegroundColor Cyan "Found Folder: $($folder.Name)"
        $FilesList = Get-PnPFileInFolder -Identity $folder -Recurse -ExcludeSystemFolders | Where-Object {$_.Name -notlike "*.aspx" -and $_.Name -notlike "*.dotx" }
        if ($FilesList.Count -eq 0) 
        {
            Write-Host -ForegroundColor Yellow "No files found in folder: $($folder.Name). Skipping to next folder."
            continue
        }
        Connect-PnPOnline -Url $CopyToSiteUrl -Interactive -ClientId 4ac6eede-e81e-4d22-abad-0d43c51486f2  
        Add-PnPFolder -Name $folder.name -Folder $DestFolder | Out-Null #Supress output
    }
}