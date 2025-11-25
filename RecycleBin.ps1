Import-module ImportExcel

$SiteURL="https://enchantedrock.sharepoint.com/sites/erintranet"
Connect-PnPOnline -URL $SiteURL -Interactive -ClientId 4ac6eede-e81e-4d22-abad-0d43c51486f2

$ReportFile = "C:\Users\DakotaRuhl\Documents\Reports\RecycleBin\RecycleBinReport"

# Can use a -RowLimit 10000, get all from first stage, or second stage
$recycleBinItemsFirstStage = Get-PnPRecycleBinItem -FirstStage 
$recycleBinItemsSecondStage = Get-PnPRecycleBinItem -SecondStage

# Generate reports based on filters
<#
# All parameter options
# Where-Object { $_.Title -or $_.DeletedByName -or $_.DeletedDate -or $_.ItemType -or $_.DirName -or $_.Size } 
#>

 
# Sort by Name of person who deleted item
$deletedBy = "Jennifer McQuilken"
$recycleBinItemsFirstStage | Where-Object { $_.DeletedByName -eq $deletedBy} | Export-Excel -Path "$ReportFile-$($deletedBy -replace ' ','-').xlsx" -WorkSheetname 'FirstStage'
$recycleBinItemsSecondStage | Where-Object { $_.DeletedByName -eq $deletedBy} | Export-Excel -Path "$ReportFile-$($deletedBy -replace ' ','-').xlsx" -WorkSheetname 'SecondStage'



# Sort by directory path of deleted items
$directory = "sites/erintranet/"
$library = "OM"
$recycleBinItemsFirstStage | Where-Object { $_.DirName -eq "$directory$library" } | Export-Excel -Path "$ReportFile-$($library -replace '/','-').xlsx" -WorkSheetname 'FirstStage'
$recycleBinItemsSecondStage | Where-Object { $_.DirName -eq "$directory$library" } | Export-Excel -Path "$ReportFile-$($library -replace '/','-').xlsx" -WorkSheetname 'SecondStage'

$recycleBinItemsFirstStage | Where-Object { $_.DirName -eq "$directory$library/Special Projects/2024 Employee Video Project" }

# Restore all items from First Stage bin based on filters selected above in the export-csv commands
Foreach ($item in $recycleBinItemsFirstStage) {
    Write-Host "Title: $($item.Title), Deleted By: $($item.DeletedByName), Deleted Date: $($item.DeletedDate), Item Type: $($item.ItemType), Dir Name: $($item.DirName), Size: $($item.Size), Id: $($item.Id)"
    Restore-PnPRecycleBinItem -Identity $item.Id -Force
}

# Restore all items from Second Stage bin based on filters selected above in the export-csv commands
Foreach ($item in $recycleBinItemsSecondStage) {
    Write-Host "Title: $($item.Title), Deleted By: $($item.DeletedByName), Deleted Date: $($item.DeletedDate), Item Type: $($item.ItemType), Dir Name: $($item.DirName), Size: $($item.Size), Id: $($item.Id)"
    Restore-PnPRecycleBinItem -Identity $item.Id -Force
}


##Special scenario restores##

#Restore 2024 Employee Video Project files
Restore-PnPRecycleBinItem -Identity 12cc6036-8bc7-4c0a-ac95-ac781f8f6621 -Force
#Restore Special Projects Folder
Restore-PnPRecycleBinItem -Identity cc2bfcea-0b01-494d-a08a-610e8167cf70 -Force

#all items under the special projects 2024 employee video project folder
$RestoreItems = $recycleBinItemsFirstStage | Where-Object { $_.DirName -eq "$directory$library/Special Projects/2024 Employee Video Project/2024 Employee Videos" }
foreach ($item in $RestoreItems) {
    $subfolder = "$directory$library/Special Projects/2024 Employee Video Project/2024 Employee Videos/$($item.Title)"
    foreach ($subitem in $recycleBinItemsFirstStage | Where-Object { $_.DirName -eq $subfolder }) {
        Write-Host "Title: $($subitem.Title), Deleted By: $($subitem.DeletedByName), Deleted Date: $($subitem.DeletedDate), Item Type: $($subitem.ItemType), Dir Name: $($subitem.DirName), Size: $($subitem.Size), Id: $($subitem.Id)"
        Restore-PnPRecycleBinItem -Identity $subitem.Id -Force
    }
}
