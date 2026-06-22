Connect-ExchangeOnline

Get-Mailbox -ResultSize Unlimited |
Select-Object DisplayName,UserPrincipalName,
    LitigationHoldEnabled,
    InPlaceHolds,
    RetentionHoldEnabled,
    DelayHoldApplied,
    DelayReleaseHoldApplied


Get-Mailbox -ResultSize Unlimited | Where-Object {
    $_.LitigationHoldEnabled -eq $true -or
    $_.InPlaceHolds.Count -gt 0 -or
    $_.RetentionHoldEnabled -eq $true -or
    $_.DelayHoldApplied -eq $true -or
    $_.DelayReleaseHoldApplied -eq $true
} | Select-Object DisplayName,UserPrincipalName,
    LitigationHoldEnabled,
    InPlaceHolds,
    RetentionHoldEnabled,
    DelayHoldApplied,
    DelayReleaseHoldApplied

Get-Mailbox -ResultSize Unlimited |
Where-Object {$_.InPlaceHolds -ne $null} |
Select DisplayName,InPlaceHolds

Get-RetentionCompliancePolicy | Select Name,Guid

Get-Mailbox -ResultSize Unlimited | Where-Object {
    $_.LitigationHoldEnabled -or
    $_.InPlaceHolds.Count -gt 0 -or
    $_.RetentionHoldEnabled -or
    $_.DelayHoldApplied -or
    $_.DelayReleaseHoldApplied
} | Select DisplayName,UserPrincipalName,
    LitigationHoldEnabled,
    InPlaceHolds,
    RetentionHoldEnabled,
    DelayHoldApplied,
    DelayReleaseHoldApplied |
Export-Excel -path "C:\Users\DakotaRuhl\Documents\Reports\MailboxHolds.xlsx" 


# Connect to Exchange Online
Connect-ExchangeOnline

# Connect to Purview Compliance PowerShell
Connect-IPPSSession

# Export mailbox holds with readable InPlaceHolds
Get-Mailbox -ResultSize Unlimited | Where-Object {
    $_.LitigationHoldEnabled -or
    $_.InPlaceHolds.Count -gt 0 -or
    $_.RetentionHoldEnabled -or
    $_.DelayHoldApplied -or
    $_.DelayReleaseHoldApplied
} | Select-Object DisplayName, UserPrincipalName,
    LitigationHoldEnabled,
    @{Name="InPlaceHolds";Expression={$_.InPlaceHolds -join "; "}},
    RetentionHoldEnabled,
    DelayHoldApplied,
    DelayReleaseHoldApplied |
Export-Excel -path "C:\Users\DakotaRuhl\Documents\Reports\MailboxHolds\MailboxHolds.xlsx" 

# Export Purview retention policies for GUID mapping
Get-RetentionCompliancePolicy |
Select-Object Name,Guid,Enabled,Mode |
Export-Csv -Excel -path "C:\Users\DakotaRuhl\Documents\Reports\MailboxHolds\RetentionCompliancePolicies.xlsx"

# Export soft deleted mailbox holds with readable InPlaceHolds
Get-Mailbox -SoftDeletedMailbox -ResultSize Unlimited | Where-Object {
    $_.LitigationHoldEnabled -or
    $_.InPlaceHolds.Count -gt 0 -or
    $_.RetentionHoldEnabled -or
    $_.DelayHoldApplied -or
    $_.DelayReleaseHoldApplied
} | Select-Object DisplayName, UserPrincipalName,
    LitigationHoldEnabled,
    @{Name="InPlaceHolds";Expression={$_.InPlaceHolds -join "; "}},
    RetentionHoldEnabled,
    DelayHoldApplied,
    DelayReleaseHoldApplied |
Export-Excel -path "C:\Users\DakotaRuhl\Documents\Reports\MailboxHolds\MailboxHolds.xlsx" -WorksheetName "Soft Deleted"

Get-Mailbox -InactiveMailboxOnly -ResultSize Unlimited | Where-Object {
    $_.LitigationHoldEnabled -or
    $_.InPlaceHolds.Count -gt 0 -or
    $_.RetentionHoldEnabled -or
    $_.DelayHoldApplied -or
    $_.DelayReleaseHoldApplied
} | Select-Object DisplayName, UserPrincipalName,
    LitigationHoldEnabled,
    @{Name="InPlaceHolds";Expression={$_.InPlaceHolds -join "; "}},
    RetentionHoldEnabled,
    DelayHoldApplied,
    DelayReleaseHoldApplied |
Export-Excel -path "C:\Users\DakotaRuhl\Documents\Reports\MailboxHolds\MailboxHolds.xlsx" -WorksheetName "Inactive"