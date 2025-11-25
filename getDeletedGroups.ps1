Import-Module Microsoft.Graph.Authentication
Import-Module Microsoft.Graph.Groups
Import-Module Microsoft.Graph.Sites

Import-Module ImportExcel

# Connect to Microsoft Graph
Connect-MgGraph -Scopes "Group.ReadWrite.All"

# Get all deleted M365 groups
$deletedGroups = Get-MgDirectoryDeletedItemAsGroup -All 

# Create an array to store results
$results = @()  
foreach ($group in $deletedGroups) 
{
    $results += [PSCustomObject]@{
        GroupName       = $group.DisplayName
        GroupId         = $group.Id
        DeletedDateTime = $group.DeletedDateTime
    }
    Write-Host -ForegroundColor Cyan "Deleted Group: $($group.DisplayName) Deleted On: $($group.DeletedDateTime)"
}
# Export to Excel
$results | Export-Excel -Path "C:\Users\DakotaRuhl\Documents\Reports\Deleted Groups\DeletedGroups1125_2.xlsx" -AutoSize
Write-Host "Export complete. File saved as DeletedGroups1125_2.xlsx"

#restore deleted groups from excel file
$filePath = "C:\Users\DakotaRuhl\Documents\Reports\Deleted Groups\DeletedGroups1125.xlsx"
$Worksheet = "Deleted on 1125"
$columnName = "Restore Plain"
$excelData = Import-Excel -Path $filePath -WorksheetName $Worksheet
$columnValues = $excelData | Select-Object -ExpandProperty $columnName

$TenantAdminURL = "https://enchantedrock-admin.sharepoint.com/"
Connect-PnPOnline -Url $TenantAdminURL -Interactive -ClientId 4ac6eede-e81e-4d22-abad-0d43c51486f2

$item = "0ba20a19-b616-4062-91dd-d5945df6c08c"
Restore-MgDirectoryDeletedItem -DirectoryObjectId "0ba20a19-b616-4062-91dd-d5945df6c08c"

$SitesCollections = @()
foreach ($item in $columnValues) 
{
    try 
    {
        #restore group
        Restore-MgDirectoryDeletedItem -DirectoryObjectId $item -ErrorAction Stop
        Write-Host -ForegroundColor Green "Restored Group with ID: $item"
        $item
        $CurrentSite = Get-PnPTenantSite | Where-Object {$_.RelatedGroupID -eq $item} -ErrorAction Stop
        $SitesCollections += $CurrentSite
        Write-Host -ForegroundColor Green "Added Site Collection for GroupID: $item, and Site URL: $($CurrentSite.Url)"
    }
    catch 
    {
        Write-Host -ForegroundColor Red "Site or Group for $item not found. Skipping."
    }
}

