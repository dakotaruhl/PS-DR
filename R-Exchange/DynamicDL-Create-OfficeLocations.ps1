##Filters
$VineFilter = "(ExtensionCustomAttribute1 -eq 'Vine') -and (RecipientTypeDetails -eq 'UserMailbox') -and (HiddenFromAddressListsEnabled -eq `$false)"
$TitanFilter = "(ExtensionCustomAttribute1 -eq 'Titan') -and (RecipientTypeDetails -eq 'UserMailbox') -and (HiddenFromAddressListsEnabled -eq `$false)"
$HyperionFilter = "(ExtensionCustomAttribute1 -eq 'Hyperion') -and (RecipientTypeDetails -eq 'UserMailbox') -and (HiddenFromAddressListsEnabled -eq `$false)"
$StocktonFilter = "(ExtensionCustomAttribute1 -eq 'Stockton') -and (RecipientTypeDetails -eq 'UserMailbox') -and (HiddenFromAddressListsEnabled -eq `$false)"
$CliftonFilter = "(ExtensionCustomAttribute1 -eq 'Clifton') -and (RecipientTypeDetails -eq 'UserMailbox') -and (HiddenFromAddressListsEnabled -eq `$false)"
$RemoteFilter = "(ExtensionCustomAttribute1 -eq 'Remote') -and (RecipientTypeDetails -eq 'UserMailbox') -and (HiddenFromAddressListsEnabled -eq `$false)"  
$OtherFilter = "(ExtensionCustomAttribute1 -eq 'Other') -and (RecipientTypeDetails -eq 'UserMailbox') -and (HiddenFromAddressListsEnabled -eq `$false)"


$VineUsers = Get-Recipient -ResultSize Unlimited -Filter $VineFilter
$TitanUsers = Get-Recipient -ResultSize Unlimited -Filter $TitanFilter
$HyperionUsers = Get-Recipient -ResultSize Unlimited -Filter $HyperionFilter
$StocktonUsers = Get-Recipient -ResultSize Unlimited -Filter $StocktonFilter
$CliftonUsers = Get-Recipient -ResultSize Unlimited -Filter $CliftonFilter
$RemoteUsers = Get-Recipient -ResultSize Unlimited -Filter $RemoteFilter
$OtherUsers = Get-Recipient -ResultSize Unlimited -Filter $OtherFilter
$VineUsers.Count
$TitanUsers.Count
$HyperionUsers.Count
$StocktonUsers.Count
$CliftonUsers.Count
$RemoteUsers.Count
$OtherUsers.Count

# Export results into one workbook, with multiple sheets showing the different office locations
$ExportPath = ".\output\OfficeLocationUsers.xlsx"

$VineUsers |
    Export-Excel -Path $ExportPath -WorksheetName "Vine" `
        -AutoSize -AutoFilter -FreezeTopRow -BoldTopRow

$TitanUsers |
    Export-Excel -Path $ExportPath -WorksheetName "Titan" `
        -AutoSize -AutoFilter -FreezeTopRow -BoldTopRow

$HyperionUsers |
    Export-Excel -Path $ExportPath -WorksheetName "Hyperion" `
        -AutoSize -AutoFilter -FreezeTopRow -BoldTopRow

$StocktonUsers |
    Export-Excel -Path $ExportPath -WorksheetName "Stockton" `
        -AutoSize -AutoFilter -FreezeTopRow -BoldTopRow

$CliftonUsers |
    Export-Excel -Path $ExportPath -WorksheetName "Clifton" `
        -AutoSize -AutoFilter -FreezeTopRow -BoldTopRow

$RemoteUsers |
    Export-Excel -Path $ExportPath -WorksheetName "Remote" `
        -AutoSize -AutoFilter -FreezeTopRow -BoldTopRow

$OtherUsers |
    Export-Excel -Path $ExportPath -WorksheetName "Other" `
        -AutoSize -AutoFilter -FreezeTopRow -BoldTopRow

<# 
$titanCount = Get-Recipient -Filter $TitanFilter |
    Select-Object DisplayName, Office, ExtensionCustomAttribute1, PrimarySmtpAddress |
    Sort-Object DisplayName
$titanCount.Count

$vineCount = Get-Recipient -Filter $VineFilter |
    Select-Object DisplayName, Office, ExtensionCustomAttribute1, PrimarySmtpAddress |
    Sort-Object DisplayName
$vineCount.Count

$hyperionCount = Get-Recipient -Filter $HyperionFilter |
    Select-Object DisplayName, Office, ExtensionCustomAttribute1, PrimarySmtpAddress |
    Sort-Object DisplayName
$hyperionCount.Count

$stocktonCount = Get-Recipient -Filter $StocktonFilter |
    Select-Object DisplayName, Office, ExtensionCustomAttribute1, PrimarySmtpAddress |
    Sort-Object DisplayName
$stocktonCount.Count

$cliftonCount = Get-Recipient -Filter $CliftonFilter |
    Select-Object DisplayName, Office, ExtensionCustomAttribute1, PrimarySmtpAddress |
    Sort-Object DisplayName
$cliftonCount.Count

$remoteCount = Get-Recipient -Filter $RemoteFilter |
    Select-Object DisplayName, Office, ExtensionCustomAttribute1, PrimarySmtpAddress |
    Sort-Object DisplayName
$remoteCount.Count

$otherCount = Get-Recipient -Filter $OtherFilter |
    Select-Object DisplayName, Office, ExtensionCustomAttribute1, PrimarySmtpAddress |
    Sort-Object DisplayName
$otherCount.Count
 #>       
###################
## Create Groups ##
###################
<# 
New-DynamicDistributionGroup `
    -Name "Vine" `
    -DisplayName "Vine" `
    -Alias "Vine" `
    -PrimarySmtpAddress "Vine@erock.com" `
    -RecipientFilter $VineFilter       

New-DynamicDistributionGroup `
    -Name "Titan" `
    -DisplayName "Titan" `
    -Alias "Titan" `
    -PrimarySmtpAddress "Titan@erock.com" `
    -RecipientFilter $TitanFilter 
#>


New-DynamicDistributionGroup `
    -Name "Hyperion" `
    -DisplayName "Hyperion" `
    -Alias "Hyperion" `
    -PrimarySmtpAddress "Hyperion@erock.com" `
    -RecipientFilter $HyperionFilter

New-DynamicDistributionGroup `
    -Name "Stockton" `
    -DisplayName "Stockton" `
    -Alias "Stockton" `
    -PrimarySmtpAddress "Stockton@erock.com" `
    -RecipientFilter $StocktonFilter

New-DynamicDistributionGroup `
    -Name "Clifton" `
    -DisplayName "Clifton" `
    -Alias "Clifton" `
    -PrimarySmtpAddress "Clifton@erock.com" `
    -RecipientFilter $CliftonFilter

New-DynamicDistributionGroup `
    -Name "Remote" `
    -DisplayName "Remote" `
    -Alias "Remote" `
    -PrimarySmtpAddress "Remote@erock.com" `
    -RecipientFilter $RemoteFilter

New-DynamicDistributionGroup `
    -Name "Other" `
    -DisplayName "Other" `
    -Alias "Other" `
    -PrimarySmtpAddress "Other@erock.com" `
    -RecipientFilter $OtherFilter

##########################
# Existing Hyperion distribution list members
$CurrentMembers = Get-DistributionGroupMember `
    -Identity "hyperion@erock.com" `
    -ResultSize Unlimited

# Users currently matching your proposed dynamic filter
$DynamicMembers = Get-Recipient `
    -Filter $HyperionFilter `
    -ResultSize Unlimited

# Compare using ExternalDirectoryObjectId
$DynamicIds = @(
    $DynamicMembers |
        Where-Object { $_.ExternalDirectoryObjectId } |
        ForEach-Object { $_.ExternalDirectoryObjectId }
)

$MissingMembers = $CurrentMembers |
    Where-Object {
        $_.ExternalDirectoryObjectId -notin $DynamicIds
    } |
    Select-Object DisplayName,
        PrimarySmtpAddress,
        RecipientTypeDetails,
        ExternalDirectoryObjectId |
    Sort-Object DisplayName

$MissingMembers

Write-Host ""
Write-Host "Current DL members:  $($CurrentMembers.Count)"
Write-Host "Dynamic matches:      $($DynamicMembers.Count)"
Write-Host "Missing from filter:  $($MissingMembers.Count)"

$MissingMemberDetails = foreach ($Member in $MissingMembers) {

    Get-Recipient `
        -Identity $Member.ExternalDirectoryObjectId |
        Select-Object DisplayName,
            PrimarySmtpAddress,
            RecipientTypeDetails,
            Office,
            ExtensionCustomAttribute1,
            ExternalDirectoryObjectId
}

$MissingMemberDetails |
    Sort-Object DisplayName |
    Format-Table -AutoSize

## Check reverse
$CurrentIds = @(
    $CurrentMembers |
        Where-Object { $_.ExternalDirectoryObjectId } |
        ForEach-Object { $_.ExternalDirectoryObjectId }
)

$ExtraDynamicMembers = $DynamicMembers |
    Where-Object {
        $_.ExternalDirectoryObjectId -notin $CurrentIds
    } |
    Select-Object DisplayName,
        PrimarySmtpAddress,
        RecipientTypeDetails,
        Office,
        ExtensionCustomAttribute1 |
    Sort-Object DisplayName

$ExtraDynamicMembers

Write-Host "Dynamic matches not in current DL: $($ExtraDynamicMembers.Count)"

