Connect-ExchangeOnline

<#
DisplayName        : ERO Accounts Payable
PrimarySmtpAddress : EROAccountsPayable@enchantedrock.com
ExchangeGuid       : 26336906-f5e1-48d6-b6e2-53de8cb1611a

DisplayName        : ERO Accounts Receivable
PrimarySmtpAddress : EROAccountsReceivable@enchantedrock.com
ExchangeGuid       : 849a67b8-3744-4980-81bc-587c3ca26c45

DisplayName        : ERE Accounts Payable
PrimarySmtpAddress : EREAccountsPayable@enchantedrock.com
ExchangeGuid       : 7aabe51b-4b70-45c6-b48a-c726dd1930a1
#>

$groupIds = @(
  "8b116900-4e9f-455b-a43c-da928ff5db17",   # ERE Accounts Payable
  "0bfb9636-fe3b-4de4-bee5-9bd77527d474"   # ERO Accounts Recievable 
)

Get-Mailbox -SoftDeletedMailbox -GroupMailbox -ResultSize Unlimited |
  Where-Object { $_.ExternalDirectoryObjectId -in $groupIds } |
  Format-List DisplayName, PrimarySmtpAddress, ExchangeGuid

New-MailboxRestoreRequest `
  -SourceMailbox "849a67b8-3744-4980-81bc-587c3ca26c45" `
  -TargetMailbox (Get-Mailbox "EROAccountsReceivable@enchantedrock.com").ExchangeGuid `
  -TargetRootFolder "Restored-GroupMail" `
  -AllowLegacyDNMismatch

New-MailboxRestoreRequest `
  -SourceMailbox "7aabe51b-4b70-45c6-b48a-c726dd1930a1" `
  -TargetMailbox (Get-Mailbox "EREAccountsPayable@enchantedrock.com").ExchangeGuid `
  -TargetRootFolder "Restored-GroupMail" `
  -AllowLegacyDNMismatch

  Get-MailboxRestoreRequest | Get-MailboxRestoreRequestStatistics

  
Get-MailboxRestoreRequest | ForEach-Object {
    $stats = Get-MailboxRestoreRequestStatistics $_.RequestGuid
    [PSCustomObject]@{
        Name            = $_.Name
        TargetMailbox     = $_.TargetMailbox
        Status          = $stats.StatusDetail
        PercentComplete = $stats.PercentComplete
        RequestGuid     = $_.RequestGuid
    }
} | Format-Table -AutoSize


get-mailbox 