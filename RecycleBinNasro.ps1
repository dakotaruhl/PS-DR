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
$deletedBy = "Shreeram Kalyanakrishnan"
$recycleBinItemsFirstStage | Where-Object { $_.DeletedByName -eq $deletedBy} | Export-Excel -Path "$ReportFile-$($deletedBy -replace ' ','-').xlsx" -WorkSheetname 'FirstStage'
$recycleBinItemsSecondStage | Where-Object { $_.DeletedByName -eq $deletedBy} | Export-Excel -Path "$ReportFile-$($deletedBy -replace ' ','-').xlsx" -WorkSheetname 'SecondStage'



$ShreeramKalyanakrishnanDeletesFS = $recycleBinItemsFirstStage | Where-Object { $_.DeletedByName -eq $deletedBy}
$ShreeramKalyanakrishnanDeletesSS = $recycleBinItemsSecondStage | Where-Object { $_.DeletedByName -eq $deletedBy}

###BETA - No Profile temp load in session needed for -itemID
pwsh -NoProfile
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
Import-Module "C:\Temp\PnP-Nightly\PnP.PowerShell.psd1" -Force
# Check it worked
Get-Module PnP.PowerShell | Select Name, Version, Path
Get-Command Restore-PnPRecycleBinItem -Syntax
###

$itemIds = $PaulAndrewDeletesFS | Select-Object -ExpandProperty Id
$itemIds = $PaulAndrewDeletesSS | Select-Object -ExpandProperty Id

#Break into batches of 1000 to avoid throttling and restore items deleted by Paul Andrews, and track progress in console
$batchSize     = 1000
$itemIds       = @($itemIds)  # ensure it's an array
$totalItems    = $itemIds.Count
$totalBatches  = [math]::Ceiling($totalItems / $batchSize)

$processedBatches    = 0
$processedItems      = 0
$totalBatchSeconds   = 0.0
$overallStart        = Get-Date

for ($offset = 0; $offset -lt $totalItems; $offset += $batchSize) {

    $endIndex = [math]::Min($offset + $batchSize - 1, $totalItems - 1)
    $batch    = $itemIds[$offset..$endIndex]

    # --- Restore this batch and time it ---
    $batchStart = Get-Date
    try {
        Restore-PnPRecycleBinItem -IdList $batch
    }
    catch {
        # Optional: log & continue. Change to "throw" if you want to stop on first failure.
        Write-Warning "Batch $($processedBatches + 1) failed: $($_.Exception.Message)"
        # continue
    }
    $batchElapsed = (Get-Date) - $batchStart

    # --- Update counters ---
    $processedBatches++
    $processedItems += $batch.Count
    $totalBatchSeconds += $batchElapsed.TotalSeconds

    # --- Progress + ETA ---
    $progress = [math]::Round(($processedBatches / [math]::Max($totalBatches,1)) * 100, 2)
    $avgBatchSec = $totalBatchSeconds / [math]::Max($processedBatches,1)
    $remainingBatches = $totalBatches - $processedBatches
    $etaSec = [math]::Max(0, $avgBatchSec * $remainingBatches)

    $ts     = [TimeSpan]::FromSeconds($etaSec)
    $etaHMS = ('{0:00}:{1:00}:{2:00}' -f [int]$ts.TotalHours, $ts.Minutes, $ts.Seconds)

    $elapsedTotal = (Get-Date) - $overallStart
    $elapsedHMS   = ('{0:00}:{1:00}:{2:00}' -f [int]$elapsedTotal.TotalHours, $elapsedTotal.Minutes, $elapsedTotal.Seconds)

    Write-Progress -Activity "Restoring Recycle Bin Items (IdList batches of $batchSize)" `
        -Status "Batch $processedBatches/$totalBatches | Items $processedItems/$totalItems | Last batch: $([math]::Round($batchElapsed.TotalSeconds,1))s | Elapsed: $elapsedHMS | ETA: $etaHMS" `
        -PercentComplete $progress `
        -Id 1
}

Write-Progress -Completed -Id 1

Write-Host "Done. Restored $processedItems items in $processedBatches batches. Total time: $((Get-Date) - $overallStart)"

## Alternative: Restore items one by one with progress (slower but can show per-item progress and handle errors individually)
$itemTotal = $PaulAndrewDeletesFS.Count
$itemCount = 0
$start = Get-Date
#restore first stage items deleted by Paul Andrews and show progress in console
Foreach ($item in $PaulAndrewDeletesFS) 
{
    
    #compute progress
    $progress = [math]::Round(($itemCount / $itemTotal * 100), 2)

    # Simple ETA (avoid divide-by-zero)
    $elapsed = (Get-Date) - $start
    $etaSec  = if ($itemCount -gt 0) 
    {
        $avgSec = $elapsed.TotalSeconds / $itemCount
        [int]($avgSec * ($itemTotal - $itemCount))
    } 
    else {0}

    # Format ETA as HH:MM:SS (supports >24 hours)
    $ts      = [TimeSpan]::FromSeconds($etaSec)
    $etaHMS  = ('{0:00}:{1:00}:{2:00}' -f [int]$ts.TotalHours, $ts.Minutes, $ts.Seconds)

    Write-Progress -Activity "Restoring Recycle Bin Items" `
        -Status "Processing restores $itemCount of $itemTotal ($progress`%) ETA: $etaHMS"`
        -PercentComplete $progress `
        -Id 1

    Restore-PnPRecycleBinItem -Identity $item.Id -Force
    $itemCount++
}
Write-Progress -Completed -Id 1


# Sort by directory path of deleted items
$directory = "sites/erintranet/"
$library = "Accounting and Finance/1. Accounting - General/Sales Tax/Sales Tax Filings/ER LLC"
$recycleBinItemsFirstStage | Where-Object { $_.DirName -eq "$directory$library" } | Export-Excel -Path "$ReportFile-$($library -replace '/','-').xlsx" -WorkSheetname 'FirstStage'
$recycleBinItemsSecondStage | Where-Object { $_.DirName -eq "$directory$library" } | Export-Excel -Path "$ReportFile-$($library -replace '/','-').xlsx" -WorkSheetname 'SecondStage'

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

#passwords.xlsx
Restore-PnPRecycleBinItem -Identity a3da4aeb-f738-487f-8db8-4db049e43db6 -force

export-excel -path "$ReportFile\$($deletedBy)" -WorksheetName "FirstStage" -AutoSize -TableName "FirstStageItems" -InputObject $recycleBinItemsFirstStage
export-excel -path "$ReportFile\$($deletedBy)" -WorksheetName "SecondStage" -AutoSize -TableName "SecondStageItems" -InputObject $recycleBinItemsSecondStage