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