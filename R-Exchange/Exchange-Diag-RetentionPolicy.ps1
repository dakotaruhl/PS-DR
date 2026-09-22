## Review retention applied to the user
$user = "ratkinson@erock.com"
#start-managedfolderassistant -identity $user
#Get-MailboxStatistics $user | Format-List TotalDeletedItemSize,ItemCount

## Complete MRM Diagnostic snapshot
Write-Host "`n=== MAILBOX MRM CONFIGURATION ===" -ForegroundColor Cyan

Get-Mailbox $user | Format-List `
    RetentionPolicy,
    RetentionHoldEnabled,
    ElcProcessingDisabled,
    LitigationHoldEnabled,
    DelayHoldApplied,
    DelayReleaseHoldApplied,
    ComplianceTagHoldApplied,
    InPlaceHolds

Write-Host "`n=== MANAGED FOLDER ASSISTANT DIAGNOSTICS ===" -ForegroundColor Cyan

[xml]$diag = (Export-MailboxDiagnosticLogs -Identity $user -ExtendedProperties).MailboxLog

$diag.Properties.MailboxTable.Property |
    Where-Object { $_.Name -like "ELC*" } |
    Sort-Object Name |
    Format-Table Name, Value -AutoSize

Write-Host "`n=== RETENTION POLICY ===" -ForegroundColor Cyan

$mbx = Get-Mailbox $user

Get-RetentionPolicy $mbx.RetentionPolicy |
    Format-List Name, RetentionPolicyTagLinks

## Inspect the retention tags applied to the mailbox
Get-Mailbox $user | Select-Object RetentionPolicy

$policy = Get-RetentionPolicy (Get-Mailbox $user).RetentionPolicy

$policy.RetentionPolicyTagLinks | ForEach-Object {
    Get-RetentionPolicyTag $_
} | Format-Table Name, Type, AgeLimitForRetention, RetentionAction, RetentionEnabled -AutoSize

## Check deleted items tag 
Get-RetentionPolicyTag |
    Where-Object {$_.Type -eq "DeletedItems"} |
    Format-Table Name, Type, AgeLimitForRetention, RetentionAction, RetentionEnabled -AutoSize

## Add it to policy
Set-RetentionPolicy "Default MRM Policy" -RetentionPolicyTagLinks "Deleted Items"

## Verify it worked
Get-RetentionPolicy "Erock Compliance" |
    Format-List Name, RetentionPolicyTagLinks

$PolicyName = "Erock Compliance"

Get-Mailbox -ResultSize Unlimited -RecipientTypeDetails UserMailbox |
    Set-Mailbox -RetentionPolicy $PolicyName

## Verify the recoverable items settings

Get-Mailbox -identity $user |
    Select-Object `
        DisplayName,
        PrimarySmtpAddress,
        RetentionPolicy,
        RetainDeletedItemsFor,
        SingleItemRecoveryEnabled,
        LitigationHoldEnabled |
    Format-Table -AutoSize

Get-Mailbox -ResultSize Unlimited -RecipientTypeDetails UserMailbox |
    Select-Object `
        DisplayName,
        PrimarySmtpAddress,
        RetentionPolicy,
        RetainDeletedItemsFor,
        SingleItemRecoveryEnabled,
        LitigationHoldEnabled |
    Format-Table -AutoSize

## Count of mailboxes with incorrect recoverable items settings
Get-Mailbox -ResultSize Unlimited -RecipientTypeDetails UserMailbox |
    Where-Object {
        $_.SingleItemRecoveryEnabled -ne $true -or
        $_.RetainDeletedItemsFor -ne (New-TimeSpan -Days 14)
    } |
    Select-Object `
        DisplayName,
        PrimarySmtpAddress,
        RetentionPolicy,
        RetainDeletedItemsFor,
        SingleItemRecoveryEnabled,
        LitigationHoldEnabled |
    Format-Table -AutoSize

# Count of mailboxes with correct recoverable items settings
(Get-Mailbox -ResultSize Unlimited -RecipientTypeDetails UserMailbox |
    Where-Object {
        $_.SingleItemRecoveryEnabled -eq $true -and
        $_.RetainDeletedItemsFor -eq (New-TimeSpan -Days 14)
    }).Count

# check randy mailbox deleted item count
