# Set up Excel module and read in file 
Import-Module ImportExcel

# Connect to SharePoint Online
$TenantAdminURL = "https://enchantedrock-admin.sharepoint.com/"
Connect-PnPOnline -Url $TenantAdminURL -Interactive -ClientId 4ac6eede-e81e-4d22-abad-0d43c51486f2 

#Get files from Target Site and Folder
$targetSiteUrl = "https://enchantedrock.sharepoint.com/sites/erintranet"
$TargetFolder = "/EPC/ERE/00 ERE Projects/HEB (EREJB161012)/01 Stores"
Connect-PnPOnline -Url $targetSiteUrl -Interactive -ClientId 4ac6eede-e81e-4d22-abad-0d43c51486f2
Write-Host -ForegroundColor Yellow "`nConnected to Target Site: $targetSiteUrl`nGetting all files from Target Folder: $TargetFolder"
$storesFolderList = Get-PnPFolderInFolder -FolderSiteRelativeUrl $TargetFolder

#Set base report path
$reportPath = "C:\Users\DakotaRuhl\Documents\ProjectManagement"

$folderListResults = @()
foreach ($folder in $storesFolderList) { 
    $folderListResults += [PSCustomObject]@{
                    folderName = $folder.Name
                    URL         = "https://enchantedrock.sharepoint.com$($folder.ServerRelativeUrl)"
                }
}

$folderListResults | Export-Excel -Path "$reportPath\folderCollectionsReport.xlsx"
