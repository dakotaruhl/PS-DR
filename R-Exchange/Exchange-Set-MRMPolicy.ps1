<#
.SYNOPSIS
    Migrates Exchange Online user mailboxes from the source MRM policy to the
    target MRM policy, removes unintended retention holds, and requests Managed
    Folder Assistant processing.

.DESCRIPTION
    1. Connects to Exchange Online.
    2. Verifies the target retention policy exists.
    3. Finds UserMailbox recipients currently assigned the source policy.
    4. Applies the target policy.
    5. Removes RetentionHoldEnabled when it is enabled.
    6. Does not modify Litigation Hold.
    7. Reports LitigationHoldEnabled, RetentionHoldEnabled, and
       ElcProcessingDisabled before and after the change.
    8. Requests Managed Folder Assistant processing when policy assignment and
       retention-hold removal are verified and ELC processing is enabled.
    9. Exports detailed results to a timestamped Excel workbook.

.NOTES
    Requires the ExchangeOnlineManagement and ImportExcel modules.
#>

Start-Transcript -Path ".\output\Exchange-Set-MRMPolicy_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt" -Append
# Ensure the transcript is stopped when the script exits
Register-EngineEvent PowerShell.Exiting -Action { Stop-Transcript } | Out-Null

$Thumbprint = "C47B91EB62634CA61FA8146DDA83B8BF605C0962"
$ClientID   = "ea2ca49b-d0df-4774-b611-86cf9dc9629f"
$Tenant     = "enchantedrock.onmicrosoft.com"

try {
    $Connection = Get-ConnectionInformation -ErrorAction SilentlyContinue |
        Where-Object { $_.State -eq "Connected" } |
        Select-Object -First 1

    if (-not $Connection) {
        Connect-ExchangeOnline `
            -CertificateThumbprint $Thumbprint `
            -AppId $ClientID `
            -Organization $Tenant `
            -ShowBanner:$false `
            -ErrorAction Stop
    }
    else {
        Write-Host "Already connected to Exchange Online." -ForegroundColor Green
    }
}
catch {
    throw "Unable to connect to Exchange Online: $($_.Exception.Message)"
}

$SourcePolicy = "Default MRM Policy"
$TargetPolicy = "ERock Compliance"

# ============================================================
# Verify target retention policy
# ============================================================

$Policy = Get-RetentionPolicy -Identity $TargetPolicy -ErrorAction Stop

Write-Host "`nTarget Retention Policy:" -ForegroundColor Cyan
$Policy |
    Select-Object Name, RetentionPolicyTagLinks, Guid |
    Format-List

# ============================================================
# Find mailboxes currently using the source policy
# ============================================================

Write-Host "`nFinding mailboxes assigned '$SourcePolicy'..." -ForegroundColor Cyan

$Mailboxes = @(
    Get-Mailbox -ResultSize Unlimited -RecipientTypeDetails UserMailbox |
        Where-Object { $_.RetentionPolicy -eq $SourcePolicy }
)

Write-Host "Mailboxes found: $($Mailboxes.Count)" -ForegroundColor Yellow

$Mailboxes |
    Select-Object DisplayName, PrimarySmtpAddress, RetentionPolicy,
        LitigationHoldEnabled, RetentionHoldEnabled, ElcProcessingDisabled |
    Format-Table -AutoSize

# ============================================================
# Change retention policy and remove unintended retention hold
# ============================================================

$Results = foreach ($Mailbox in $Mailboxes) {
    Write-Host "`nProcessing: $($Mailbox.PrimarySmtpAddress)" -ForegroundColor Cyan

    $PolicyVerified               = $false
    $RetentionHoldRemovalRequired = [bool]$Mailbox.RetentionHoldEnabled
    $RetentionHoldRemoved         = $false
    $MFARequested                 = $false
    $MFAError                     = $null

    try {
        Set-Mailbox -Identity $Mailbox.Identity `
            -RetentionPolicy $TargetPolicy `
            -ErrorAction Stop

        if ($RetentionHoldRemovalRequired) {
            Write-Warning "  RetentionHoldEnabled is TRUE. Removing the unintended retention hold."

            Set-Mailbox -Identity $Mailbox.Identity `
                -RetentionHoldEnabled $false `
                -ErrorAction Stop
        }

        # Retrieve the mailbox again so all verification uses current values.
        $UpdatedMailbox = Get-Mailbox -Identity $Mailbox.Identity -ErrorAction Stop

        $PolicyVerified = $UpdatedMailbox.RetentionPolicy -eq $TargetPolicy
        $RetentionHoldRemoved = -not [bool]$UpdatedMailbox.RetentionHoldEnabled

        if ($PolicyVerified) {
            Write-Host "  Retention policy updated successfully." -ForegroundColor Green
        }
        else {
            Write-Warning "  Retention policy verification FAILED."
        }

        if ($RetentionHoldRemovalRequired) {
            if ($RetentionHoldRemoved) {
                Write-Host "  Retention hold removed successfully." -ForegroundColor Green
            }
            else {
                Write-Warning "  Retention hold removal verification FAILED."
            }
        }

        if ($UpdatedMailbox.LitigationHoldEnabled) {
            Write-Warning "  LitigationHoldEnabled is TRUE. Litigation Hold was not modified."
        }

        if ($UpdatedMailbox.ElcProcessingDisabled) {
            Write-Warning "  ElcProcessingDisabled is TRUE. Managed Folder Assistant was not requested."
        }

        # ====================================================
        # Request Managed Folder Assistant processing
        # ====================================================

        if (
            $PolicyVerified -and
            $RetentionHoldRemoved -and
            -not $UpdatedMailbox.ElcProcessingDisabled
        ) {
            try {
                Start-ManagedFolderAssistant `
                    -Identity $UpdatedMailbox.ExchangeGuid `
                    -ErrorAction Stop

                $MFARequested = $true
                Write-Host "  Managed Folder Assistant requested." -ForegroundColor Green
            }
            catch {
                $MFAError = $_.Exception.Message
                Write-Warning "  Failed to request Managed Folder Assistant: $MFAError"
            }
        }

        $Status = if (-not $PolicyVerified) {
            "Policy verification failed"
        }
        elseif (-not $RetentionHoldRemoved) {
            "Retention hold removal failed"
        }
        elseif ($UpdatedMailbox.ElcProcessingDisabled) {
            "Policy updated; ELC processing disabled"
        }
        elseif (-not $MFARequested) {
            "Policy updated; MFA request failed"
        }
        else {
            "Success"
        }

        [PSCustomObject]@{
            DisplayName                   = $UpdatedMailbox.DisplayName
            PrimarySmtpAddress            = $UpdatedMailbox.PrimarySmtpAddress
            PreviousPolicy                = $SourcePolicy
            CurrentPolicy                 = $UpdatedMailbox.RetentionPolicy
            PolicyVerified                = $PolicyVerified
            LitigationHoldEnabled         = [bool]$UpdatedMailbox.LitigationHoldEnabled
            RetentionHoldPreviouslyEnabled = $RetentionHoldRemovalRequired
            RetentionHoldEnabled          = [bool]$UpdatedMailbox.RetentionHoldEnabled
            RetentionHoldRemoved          = $RetentionHoldRemoved
            ElcProcessingDisabled         = [bool]$UpdatedMailbox.ElcProcessingDisabled
            ExchangeGuid                  = $UpdatedMailbox.ExchangeGuid
            MFARequested                  = $MFARequested
            MFAError                      = $MFAError
            Status                        = $Status
        }
    }
    catch {
        $ProcessingError = $_.Exception.Message
        Write-Warning "Failed processing $($Mailbox.PrimarySmtpAddress): $ProcessingError"

        [PSCustomObject]@{
            DisplayName                   = $Mailbox.DisplayName
            PrimarySmtpAddress            = $Mailbox.PrimarySmtpAddress
            PreviousPolicy                = $SourcePolicy
            CurrentPolicy                 = $null
            PolicyVerified                = $false
            LitigationHoldEnabled         = [bool]$Mailbox.LitigationHoldEnabled
            RetentionHoldPreviouslyEnabled = $RetentionHoldRemovalRequired
            RetentionHoldEnabled          = $null
            RetentionHoldRemoved          = $false
            ElcProcessingDisabled         = [bool]$Mailbox.ElcProcessingDisabled
            ExchangeGuid                  = $Mailbox.ExchangeGuid
            MFARequested                  = $false
            MFAError                      = $null
            Status                        = "ERROR: $ProcessingError"
        }
    }
}

# ============================================================
# Results
# ============================================================

Write-Host "`n===============================================" -ForegroundColor Cyan
Write-Host "Migration Results" -ForegroundColor Cyan
Write-Host "===============================================" -ForegroundColor Cyan

$Results |
    Format-Table `
        DisplayName,
        PrimarySmtpAddress,
        CurrentPolicy,
        PolicyVerified,
        LitigationHoldEnabled,
        RetentionHoldPreviouslyEnabled,
        RetentionHoldEnabled,
        RetentionHoldRemoved,
        ElcProcessingDisabled,
        MFARequested,
        Status `
        -AutoSize

# ============================================================
# Summary
# ============================================================

$SuccessCount              = @($Results | Where-Object PolicyVerified).Count
$FailureCount              = @($Results | Where-Object { -not $_.PolicyVerified }).Count
$LitigationHoldCount       = @($Results | Where-Object LitigationHoldEnabled).Count
$RetentionHoldRemovedCount = @($Results | Where-Object {
    $_.RetentionHoldPreviouslyEnabled -and $_.RetentionHoldRemoved
}).Count
$RetentionHoldFailureCount = @($Results | Where-Object {
    $_.RetentionHoldPreviouslyEnabled -and -not $_.RetentionHoldRemoved
}).Count
$ElcDisabledCount          = @($Results | Where-Object ElcProcessingDisabled).Count
$MFARequestedCount         = @($Results | Where-Object MFARequested).Count
$MFAFailedCount            = @($Results | Where-Object { $_.MFAError }).Count

Write-Host "`nSummary:" -ForegroundColor Cyan
Write-Host "  Mailboxes targeted        : $($Mailboxes.Count)"
Write-Host "  Policy verified           : $SuccessCount" -ForegroundColor Green
Write-Host "  Policy failures           : $FailureCount" -ForegroundColor $(if ($FailureCount) { "Red" } else { "Green" })
Write-Host "  Litigation holds retained : $LitigationHoldCount"
Write-Host "  Retention holds removed   : $RetentionHoldRemovedCount" -ForegroundColor Green
Write-Host "  Hold removal failures     : $RetentionHoldFailureCount" -ForegroundColor $(if ($RetentionHoldFailureCount) { "Red" } else { "Green" })
Write-Host "  ELC processing disabled   : $ElcDisabledCount" -ForegroundColor $(if ($ElcDisabledCount) { "Yellow" } else { "Green" })
Write-Host "  MFA requested             : $MFARequestedCount"
Write-Host "  MFA request failures      : $MFAFailedCount" -ForegroundColor $(if ($MFAFailedCount) { "Yellow" } else { "Green" })

# ============================================================
# Export detailed results
# ============================================================

$OutputFolder = "C:\Users\DakotaRuhl\Documents\PS-DR\output"

if (-not (Test-Path -LiteralPath $OutputFolder)) {
    New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null
}

$OutputFile = "{0}_MigrationResults.xlsx" -f (Get-Date -Format "yyyy-MM-dd_HH-mm-ss")
$OutputPath = Join-Path -Path $OutputFolder -ChildPath $OutputFile

$Results |
    Export-Excel `
        -Path $OutputPath `
        -WorksheetName "Migration Results" `
        -TableName "MigrationResults" `
        -AutoSize `
        -AutoFilter `
        -FreezeTopRow `
        -BoldTopRow

Write-Host "`nResults exported to: $OutputPath" -ForegroundColor Green

# ============================================================
# Final verification
# ============================================================

$RemainingOnOldPolicy = @(
    Get-Mailbox -ResultSize Unlimited -RecipientTypeDetails UserMailbox |
        Where-Object { $_.RetentionPolicy -eq $SourcePolicy }
)

$RemainingRetentionHolds = @(
    Get-Mailbox -ResultSize Unlimited -RecipientTypeDetails UserMailbox |
        Where-Object { $_.RetentionHoldEnabled }
)

Write-Host "`nMailboxes still assigned '$SourcePolicy': $($RemainingOnOldPolicy.Count)" `
    -ForegroundColor $(if ($RemainingOnOldPolicy.Count -eq 0) { "Green" } else { "Yellow" })

if ($RemainingOnOldPolicy.Count -gt 0) {
    $RemainingOnOldPolicy |
        Select-Object DisplayName, PrimarySmtpAddress, RetentionPolicy |
        Format-Table -AutoSize
}

Write-Host "`nUser mailboxes still having RetentionHoldEnabled: $($RemainingRetentionHolds.Count)" `
    -ForegroundColor $(if ($RemainingRetentionHolds.Count -eq 0) { "Green" } else { "Yellow" })

if ($RemainingRetentionHolds.Count -gt 0) {
    $RemainingRetentionHolds |
        Select-Object DisplayName, PrimarySmtpAddress, RetentionPolicy,
            LitigationHoldEnabled, RetentionHoldEnabled, ElcProcessingDisabled |
        Format-Table -AutoSize
}

<#
# Optional verification commands

# Review every mailbox assigned the target policy.
$MailboxesWithTargetPolicy = Get-Mailbox -ResultSize Unlimited -RecipientTypeDetails UserMailbox |
    Where-Object { $_.RetentionPolicy -eq $TargetPolicy } |
    Select-Object DisplayName,
                  PrimarySmtpAddress,
                  RetentionPolicy,
                  LitigationHoldEnabled,
                  RetentionHoldEnabled,
                  ElcProcessingDisabled |
    Format-table -AutoSize



# Export to Excel instead
$MailboxesWithTargetPolicy | Export-Excel -Path ".\output\MailboxesWithTargetPolicy.xlsx" -FreezeTopRow -BoldTopRow

# Inspect the tags linked to the target policy.
Get-RetentionPolicy -Identity $TargetPolicy |
    Select-Object -ExpandProperty RetentionPolicyTagLinks |
    ForEach-Object {
        Get-RetentionPolicyTag -Identity $_ |
            Select-Object Name,
                          Type,
                          RetentionEnabled,
                          AgeLimitForRetention,
                          RetentionAction
    } |
    Format-Table -AutoSize

# Fix remaining retention holds for mailboxes
foreach ($mailbox in $RemainingRetentionHolds) {
    Set-Mailbox -Identity $mailbox.Identity -RetentionHoldEnabled $false
    Write-Host "Cleared RetentionHoldEnabled for mailbox: $($mailbox.DisplayName)" -ForegroundColor Green
}
Write-Host "`nFinished clearing RetentionHoldEnabled for all applicable mailboxes." -ForegroundColor Green

# Check who does not have new policy applied
$MailboxesWithoutTargetPolicy = Get-Mailbox -ResultSize Unlimited -RecipientTypeDetails UserMailbox |
    Where-Object { $_.RetentionPolicy -ne $TargetPolicy }

$MailboxesWithoutTargetPolicy |
    Select-Object DisplayName, PrimarySmtpAddress, RetentionPolicy |
    Format-Table -AutoSize

# Fix mailboxes without the target policy
foreach ($mailbox in $MailboxesWithoutTargetPolicy) {
    Set-Mailbox -Identity $mailbox.Identity -RetentionPolicy $TargetPolicy
    Write-Host "Applied target retention policy to mailbox: $($mailbox.DisplayName)" -ForegroundColor Green
}
Write-Host "`nFinished applying target retention policy to all applicable mailboxes." -ForegroundColor Green
#>
