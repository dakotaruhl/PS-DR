#for all mailbox archives
Get-MailboxStatistics -Identity "user@example.com" -Archive | Select DisplayName, TotalItemSize, ItemCount

#for all sites including OneDrives
Get-PnPRecycleBinItem -SecondStage

#Live data is below
#Exchange 6.2TB
#SharePoint 9.1TB
#OneDrive 6.0 TB
