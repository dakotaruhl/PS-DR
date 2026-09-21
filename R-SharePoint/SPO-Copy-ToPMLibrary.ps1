<#
 Sets a target site to copy files to, using a list of site collections from an Excel file, with a list of target site folders
#>
$TenantAdminURL = "https://enchantedrock-admin.sharepoint.com/"
$Thumbprint = "C47B91EB62634CA61FA8146DDA83B8BF605C0962"
$ClientID = "ea2ca49b-d0df-4774-b611-86cf9dc9629f"
$TenantID = "0bdf0e1f-a359-4b5c-9b79-9357e35ff8c6"

#Start-Transcript -Path "C:\Users\DakotaRuhl\Documents\ProjectManagement\CopySiteFiles_Transcript_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt" -Append 

# Set up Excel module and read in file 
 Import-Module ImportExcel
 $filePath = "C:\Users\DakotaRuhl\Documents\Reports\LockedSites.xlsx"
 $Worksheet = "Locked Sites"
 $sourceColumnName = "Url"
 #$targetColumnName = ""
 $excelData = Import-Excel -Path $filePath -WorksheetName $Worksheet

 $sourceColumnValues = $excelData | Select-Object -ExpandProperty $sourceColumnName
 #$targetColumnValues = $excelData | Select-Object -ExpandProperty $targetColumnName

# Connect to SharePoint Online
Connect-PnPOnline -Url $TenantAdminURL -ClientId $ClientID -Tenant $TenantID -Thumbprint $Thumbprint 

# Unlock Sites
foreach ($site in $sourceColumnValues) 
{
    Write-Host "locking site: $($site)" -ForegroundColor Green
    Set-PnPTenantSite -Url $site -LockState "noaccess"
}

# Set Destination for Copy
$CopyToSiteUrl = "https://enchantedrock.sharepoint.com/sites/erintranet/"
$CopyToTargetFolder = "EPC/ERE/00 ERE Projects/OnePlan Sites/With Folders"
#$CopyToTargetFolder = "/EPC/ERE/00 ERE Projects/HEB (EREJB161012)/01 Stores"
Connect-PnPOnline -Url $CopyToSiteUrl -ClientId $ClientID -Tenant $TenantID -Thumbprint $Thumbprint

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
    Connect-PnPOnline -Url $CopyToSiteUrl -ClientId $ClientID -Tenant $TenantID -Thumbprint $Thumbprint
    Add-PnPFolder -Name $Site.Title -Folder $CopyToTargetFolder | Out-Null
    $destFolderURL = get-pnpfolder -Url "$CopyToTargetFolder/$($Site.Title)"
    Write-Host -ForegroundColor Magenta "Created destination folder: $($destFolderURL.ServerRelativeUrl)"

    Write-Host -foregroundcolor Magenta "`nProcessing Site Collection number $s of $($SourceSitesCollections.Count)"
    Connect-PnPOnline -Url $Site.Url -ClientId $ClientID -Tenant $TenantID -Thumbprint $Thumbprint
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

# Lock Sites
foreach ($site in $sourceColumnValues) 
{
    Write-Host "Locking site: $($site)" -ForegroundColor Green
    Set-PnPTenantSite -Url $site -LockState "NoAccess"
}





#Debugging single site copy
# $site = Get-PnPTenantSite  "https://enchantedrock.sharepoint.com/sites/HEB810Rockwall-Project" 
# $PMTargetSiteUrl = "https://enchantedrock.sharepoint.com/sites/erintranet/"
# $PMTempLocation = "EPC/ERE/00 ERE Projects/HEB (EREJB161012)/PRELIMINARY FOLDERS - DO NOT USE"
# Connect-PnPOnline -Url $PMTargetSiteUrl -ClientId $ClientID -Tenant $TenantID -Thumbprint $Thumbprint
# Add-PnPFolder -Name $site.Title -Folder $PMTempLocation
# $destFolderURL = get-pnpfolder -Url "$PMTempLocation/$($site.Title)"

# Connect-PnPOnline -Url "https://enchantedrock.sharepoint.com/sites/HEB810Rockwall-Project" -ClientId $ClientID -Tenant $TenantID -Thumbprint $Thumbprint
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