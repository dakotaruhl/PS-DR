connect-exchangeonline 
$Mailboxes = Get-Mailbox -ResultSize Unlimited


function Expand-Recipients {
    param ($Recipients)

    if (-not $Recipients) { return $null }

    ($Recipients |
        ForEach-Object {
            $_.PrimarySmtpAddress ??
            $_.ExternalEmailAddress ??
            $_.Name ??
            $_.ToString()
        } |
        Where-Object { $_ } |
        Sort-Object -Unique
    ) -join '; '
}




Write-Host "Checking $($Mailboxes.Count) mailboxes for forwards and rules..." -ForegroundColor Cyan
$ForwardResults = @()
##Mailbox Forwards
$Mailboxes |
Where-Object {
    ($_.ForwardingSmtpAddress -ne $null ) -or
    ($_.ForwardingAddress -ne $null)
} |
ForEach-Object {
    $ForwardResults += [PSCustomObject]@{
        DisplayName = $_.DisplayName
        RecipientTypeDetails = $_.RecipientTypeDetails
        ForwardingAddress = $_.ForwardingAddress
        ForwardingSmtpAddress = $_.ForwardingSmtpAddress
        DeliverToMailboxAndForward = $_.DeliverToMailboxAndForward
    }
}

Write-Host "Checking inbox rules for forwards..." -ForegroundColor Cyan
$RuleResults = @()
##Inbox rules 

foreach ($Mailbox in $Mailboxes) {
    try {
        $Rules = Get-InboxRule -Mailbox $Mailbox.UserPrincipalName -ErrorAction Stop
    }
    catch {
        # Could not enumerate rules at all for this mailbox
        $RuleResults += [PSCustomObject]@{
            Mailbox        = $Mailbox.UserPrincipalName
            RuleName       = "<Failed to enumerate rules>"
            ForwardTo      = $null
            RedirectTo     = $null
            Enabled        = $null
            ErrorType      = "Get-InboxRule failed"
            ErrorMessage   = $_.Exception.Message
        }
        continue
    }

    foreach ($Rule in $Rules) {
        try {
            if (
                ($null -ne $Rule.ForwardTo) -or
                ($null -ne $Rule.RedirectTo) -or
                ($null -ne $Rule.ForwardAsAttachmentTo)
            ) {
                $RuleResults += [PSCustomObject]@{
                    Mailbox      = $Mailbox.UserPrincipalName
                    RuleName     = $Rule.Name
                    ForwardTo    = Expand-Recipients $Rule.ForwardTo
                    RedirectTo   = Expand-Recipients $Rule.RedirectTo
                    ForwardAsAttachmentTo = Expand-Recipients $Rule.ForwardAsAttachmentTo
                    Enabled      = $Rule.Enabled
                    ErrorType    = $null
                    ErrorMessage = $null
                }
            }
        }
        catch {
            $RuleResults += [PSCustomObject]@{
                Mailbox        = $Mailbox.UserPrincipalName
                RuleName       = $Rule.Name
                ForwardTo      = "Recipient expansion failure"
                RedirectTo     = "Recipient expansion failure"
                ForwardAsAttachmentTo = "Recipient expansion failure"
                Enabled        = $Rule.Enabled
                ErrorType      = "Recipient expansion failure"
                ErrorMessage   = $_.Exception.Message
            }
        }
    }
}

$DLExternalMemberResults = @()
Write-Host "Checking distribution list members for external addresses..." -ForegroundColor Cyan
##Find external members in groups 
Get-DistributionGroup | ForEach-Object {
    $Group = $_
    try {
        $Members = Get-DistributionGroupMember $Group.Identity -ErrorAction Stop
    }
    catch {
        Write-Warning "Fallback to Get-Recipient for $($Group.Identity)"
        $Members = Get-Recipient -RecipientPreviewFilter "(MemberOfGroup -eq '$($Group.DistinguishedName)')"
    }
    $Members |
    Where-Object { $_.PrimarySmtpAddress -notlike "*@enchantedrock.com" } | 
    ForEach-Object {
        $DLExternalMemberResults += [PSCustomObject]@{
            Group = $Group.DisplayName
            Name = $_.Name
            PrimarySmtpAddress = $_.PrimarySmtpAddress
        }
    }
}

$ForwardResults | Export-Excel -Path "C:\Users\DakotaRuhl\Documents\Reports\MailboxForwardsAny.xlsx" -AutoSize -WorksheetName "Forwards"
$RuleResults | Export-Excel -Path "C:\Users\DakotaRuhl\Documents\Reports\MailboxForwardsAny.xlsx" -AutoSize -WorksheetName "Inbox Rules"
$DLExternalMemberResults | Export-Excel -Path "C:\Users\DakotaRuhl\Documents\Reports\MailboxForwardsAny.xlsx" -AutoSize -WorksheetName "DG External Members"

# Testing or single deletes
Get-InboxRule -Mailbox jobebeduo@enchantedrock.com
Remove-InboxRule -Mailbox jobebeduo@enchantedrock.com -Identity "1200474222900543489" -Confirm:$false
Remove-InboxRule -Mailbox jobebeduo@enchantedrock.com -Identity "1272531816938471425" -Confirm:$false


###### 
$groupIds = @(
  "8b116900-4e9f-455b-a43c-da928ff5db17",   # ERE Accounts Payable
  "0bfb9636-fe3b-4de4-bee5-9bd77527d474"   # ERO Accounts Recievable 
)

Get-Mailbox -SoftDeletedMailbox -GroupMailbox -ResultSize Unlimited |
  Where-Object { $_.ExternalDirectoryObjectId -in $groupIds } |
  Format-List DisplayName, PrimarySmtpAddress, ExchangeGuid

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