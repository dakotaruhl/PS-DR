Connect-ExchangeOnline

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

<#
$user = "arohan@enchantedrock.com"
Enable-Mailbox $user -Archive
Enable-Mailbox $user -AutoExpandingArchive
Set-Mailbox $user -RetentionPolicy "Archive after 24 months"

Get-Mailbox $user | Select-Object ArchiveStatus,AutoExpandingArchiveEnabled
Get-Mailbox $user | Select-Object RetentionPolicy

Start-ManagedFolderAssistant -Identity $user

$retentionPolicy = Get-Mailbox $user | fl RetentionPolicy
Get-RetentionPolicy $retentionPolicy.RetentionPolicy | fl RetentionPolicyTagLinks
Get-RetentionPolicyTag "Default 2 year move to archive" | fl Name,Type,AgeLimitForRetention,RetentionAction
Start-ManagedFolderAssistant -Identity $user

$Log = Export-MailboxDiagnosticLogs -Identity $user -ExtendedProperties
$xml = [xml]($Log.MailboxLog)
$LastProcessed = ($xml.Properties.MailboxTable.Property | Where-Object {$_.Name -like "*ELCLastSuccessTimestamp*"}).Value
Write-Host "Last MFA Processed Time: $LastProcessed"



Get-mdmMailboxFolderStatistics -Identity $user -FolderScope All | Select-Object Name,ItemsInFolder,FolderSize


$stats = Get-EXOMailboxStatistics -Identity "Emontoya@enchantedrock.com"
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

#>