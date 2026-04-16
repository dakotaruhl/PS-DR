#Connect-ExchangeOnline

Get-EXOMailbox -ResultSize Unlimited -RecipientTypeDetails UserMailbox |
ForEach-Object {
    $stats = Get-EXOMailboxStatistics -Identity $_.UserPrincipalName
    [PSCustomObject]@{
        DisplayName  = $_.DisplayName
        UPN          = $_.UserPrincipalName
        TotalSizeGB  = [math]::Round(($stats.TotalItemSize.Value.ToBytes() / 1GB),2)
        ArchiveGB    = if ($stats.ArchiveTotalItemSize) {
            [math]::Round(($stats.ArchiveTotalItemSize.Value.ToBytes() / 1GB),2)
        } else {
            0
        }
    }
} | Where-Object { $_.TotalSizeGB -gt 90 } | Sort-Object TotalSizeGB -Descending | Export-Excel -Path "C:\Users\DakotaRuhl\Documents\Reports\Full Mailboxes\MailboxSizes.xlsx" -AutoSize -WorksheetName "NearFullMailboxes"