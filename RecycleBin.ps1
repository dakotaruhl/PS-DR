Import-module ImportExcel

Connect-PnPOnline -URL $SiteURL -Interactive -ClientId 4ac6eede-e81e-4d22-abad-0d43c51486f2
$SiteURL="https://enchantedrock.sharepoint.com/sites/erintranet/"
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
$deletedBy = "Tyler Lauw"
$recycleBinItemsFirstStage | Where-Object { $_.DeletedByName -eq $deletedBy} | Export-Excel -Path "$ReportFile-$($deletedBy -replace ' ','-').xlsx" -WorkSheetname 'FirstStage'
$recycleBinItemsSecondStage | Where-Object { $_.DeletedByName -eq $deletedBy} | Export-Excel -Path "$ReportFile-$($deletedBy -replace ' ','-').xlsx" -WorkSheetname 'SecondStage'


<# 
# Sort by directory path of deleted items
$directory = "sites/erintranet/"
$library = "Sales  Marketing/Branding"
$recycleBinItemsFirstStage | Where-Object { $_.DirName -eq $directory$library} | Export-Excel -Path "$ReportFile-$($library -replace '/','-').xlsx" -WorkSheetname 'FirstStage'
$recycleBinItemsSecondStage | Where-Object { $_.DirName -eq $directory$library} | Export-Excel -Path "$ReportFile-$($library -replace '/','-').xlsx" -WorkSheetname 'SecondStage'
#>

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


