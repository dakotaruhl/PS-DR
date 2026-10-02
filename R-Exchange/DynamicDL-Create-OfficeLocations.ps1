
$VineFilter = "(Office -like 'Vine*') -and (RecipientTypeDetails -eq 'UserMailbox') -and (HiddenFromAddressListsEnabled -eq `$false)"
$TitanFilter = "(Office -like '*Titan*') -and (RecipientTypeDetails -eq 'UserMailbox') -and (HiddenFromAddressListsEnabled -eq `$false)"
$HyperionFilter = "(Office -like '*Hyperion*') -and (RecipientTypeDetails -eq 'UserMailbox') -and (HiddenFromAddressListsEnabled -eq `$false)"
$StocktonFilter = "(Office -like '*Stockton*') -and (RecipientTypeDetails -eq 'UserMailbox') -and (HiddenFromAddressListsEnabled -eq `$false)"
$CliftonFilter = "(Office -like '*Clifton*') -and (RecipientTypeDetails -eq 'UserMailbox') -and (HiddenFromAddressListsEnabled -eq `$false)"
$RemoteFilter = "(Office -like '*Remote*') -and (RecipientTypeDetails -eq 'UserMailbox') -and (HiddenFromAddressListsEnabled -eq `$false)"  
$otherFilter = "(Office -like '*Other*') -and (RecipientTypeDetails -eq 'UserMailbox') -and (HiddenFromAddressListsEnabled -eq `$false)"


$VineUsers = Get-Recipient -ResultSize Unlimited -Filter $VineFilter
$TitanUsers = Get-Recipient -ResultSize Unlimited -Filter $TitanFilter
$HyperionUsers = Get-Recipient -ResultSize Unlimited -Filter $HyperionFilter
$StocktonUsers = Get-Recipient -ResultSize Unlimited -Filter $StocktonFilter
$CliftonUsers = Get-Recipient -ResultSize Unlimited -Filter $CliftonFilter
$RemoteUsers = Get-Recipient -ResultSize Unlimited -Filter $RemoteFilter
$OtherUsers = Get-Recipient -ResultSize Unlimited -Filter $otherFilter
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


New-DynamicDistributionGroup `
    -Name "Titan Users" `
    -DisplayName "Titan Users" `
    -Alias "TitanUsers" `
    -PrimarySmtpAddress "TitanUsers@erock.com" `
    -RecipientFilter $TitanFilter

New-DynamicDistributionGroup `
    -Name "Hyperion Users" `
    -DisplayName "Hyperion Users" `
    -Alias "HyperionUsers" `
    -PrimarySmtpAddress "HyperionUsers@erock.com" `
    -RecipientFilter $HyperionFilter

New-DynamicDistributionGroup `
    -Name "Stockton Users" `
    -DisplayName "Stockton Users" `
    -Alias "StocktonUsers" `
    -PrimarySmtpAddress "StocktonUsers@erock.com" `
    -RecipientFilter $StocktonFilter

New-DynamicDistributionGroup `
    -Name "Clifton Users" `
    -DisplayName "Clifton Users" `
    -Alias "CliftonUsers" `
    -PrimarySmtpAddress "CliftonUsers@erock.com" `
    -RecipientFilter $CliftonFilter

New-DynamicDistributionGroup `
    -Name "Remote Users" `
    -DisplayName "Remote Users" `
    -Alias "RemoteUsers" `
    -PrimarySmtpAddress "RemoteUsers@erock.com" `
    -RecipientFilter $RemoteFilter

New-DynamicDistributionGroup `
    -Name "Other Users" `
    -DisplayName "Other Users" `
    -Alias "OtherUsers" `
    -PrimarySmtpAddress "OtherUsers@erock.com" `
    -RecipientFilter $otherFilter

New-DynamicDistributionGroup `
    -Name "Vine" `
    -DisplayName "Vine" `
    -Alias "Vine" `
    -PrimarySmtpAddress "Vine@erock.com" `
    -RecipientFilter $VineFilter

    Get-DynamicDistributionGroup -Identity "Vine" |
    Format-List Name,DisplayName,PrimarySmtpAddress,RecipientFilter


Set-Mailbox druhl@erock.com -ExtensionCustomAttribute1 @( 
    "Titan"
    "Hyperion"
    "Vine"
    )
Get-Mailbox druhl@erock.com |
Select-Object DisplayName, ExtensionCustomAttribute1

$VineFilter = "(ExtensionCustomAttribute1 -eq 'Vine') -and (RecipientTypeDetails -eq 'UserMailbox') -and (HiddenFromAddressListsEnabled -eq `$false)"

Get-Recipient -Filter $VineFilter |
    Select-Object DisplayName, Office, ExtensionCustomAttribute1, PrimarySmtpAddress |
    Sort-Object DisplayName

