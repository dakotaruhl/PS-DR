<#
.SYNOPSIS
    Configures litigation hold mailboxes to use the ERock Compliance Archive MRM policy.

.DESCRIPTION
    For each Exchange Online user or shared mailbox with LitigationHoldEnabled set to True, the script:
      1. Enables the online archive when it is not active.
      2. Sets the archive display name to "Online Archive".
      3. Enables auto-expanding archiving when it is not already enabled.
      4. Assigns the "ERock Compliance Archive" MRM policy.
      5. Requests Managed Folder Assistant processing.
      6. Exports before-and-after results to CSV.

    Auto-expanding archiving cannot be disabled after it is enabled. Use -WhatIf first.

.NOTES
    Certificate authentication is used when AppId, CertificateThumbprint, and Organization are supplied.
    Otherwise, the script uses delegated interactive authentication.
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [string]$RetentionPolicy = 'ERock Compliance Archive',

    [string]$ArchiveDisplayName = 'Online Archive',

    [string]$AppId,

    [string]$CertificateThumbprint,

    [string]$Organization,

    [string]$ReportPath = ".\LitigationHoldArchiveConfiguration_{0}.csv" -f (Get-Date -Format 'yyyyMMdd_HHmmss')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-ExchangeOnlineConnection {
    $connection = Get-ConnectionInformation -ErrorAction SilentlyContinue |
        Where-Object { $_.State -eq 'Connected' } |
        Select-Object -First 1

    return $null -ne $connection
}

function Connect-ERExchangeOnline {
    if (Test-ExchangeOnlineConnection) {
        Write-Verbose 'An active Exchange Online connection already exists.'
        return
    }

    $certificateValues = @($AppId, $CertificateThumbprint, $Organization)
    $certificateValueCount = @($certificateValues | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count

    if ($certificateValueCount -eq 3) {
        Connect-ExchangeOnline `
            -AppId $AppId `
            -CertificateThumbprint $CertificateThumbprint `
            -Organization $Organization `
            -ShowBanner:$false
    }
    elseif ($certificateValueCount -eq 0) {
        Connect-ExchangeOnline -ShowBanner:$false
    }
    else {
        throw 'For certificate authentication, AppId, CertificateThumbprint, and Organization must all be supplied. Otherwise, omit all three for delegated authentication.'
    }
}

function Get-ArchiveState {
    param(
        [Parameter(Mandatory)]
        [string]$Identity
    )

    Get-Mailbox -Identity $Identity -ErrorAction Stop |
        Select-Object DisplayName, PrimarySmtpAddress, RecipientTypeDetails,
            LitigationHoldEnabled, RetentionPolicy, ArchiveStatus, ArchiveState,
            ArchiveName, AutoExpandingArchiveEnabled
}

Import-Module ExchangeOnlineManagement -ErrorAction Stop
Connect-ERExchangeOnline

# Fail before changing mailboxes if the policy or required tag is missing.
$policy = Get-RetentionPolicy -Identity $RetentionPolicy -ErrorAction Stop
$linkedTagNames = @(
    $policy.RetentionPolicyTagLinks |
        ForEach-Object {
            if ($_ -is [string]) { $_ } else { $_.Name }
        }
)

$requiredTag = 'Recoverable Items 14 days move to archive'
if ($linkedTagNames -notcontains $requiredTag) {
    throw "Retention policy '$RetentionPolicy' does not contain the required tag '$requiredTag'. No mailboxes were changed."
}

$mailboxes = @(
    Get-Mailbox -ResultSize Unlimited -RecipientTypeDetails UserMailbox,SharedMailbox |
        Where-Object { $_.LitigationHoldEnabled -eq $true } |
        Sort-Object PrimarySmtpAddress
)

if ($mailboxes.Count -eq 0) {
    Write-Warning 'No litigation hold mailboxes were found.'
    return
}

Write-Host "Found $($mailboxes.Count) litigation hold mailbox(es)." -ForegroundColor Cyan
Write-Host "Target policy: $RetentionPolicy" -ForegroundColor Cyan
Write-Warning 'Auto-expanding archiving cannot be disabled after it is enabled.'

$results = foreach ($mailbox in $mailboxes) {
    $identity = $mailbox.PrimarySmtpAddress.ToString()
    $before = Get-ArchiveState -Identity $identity
    $actions = [System.Collections.Generic.List[string]]::new()
    $errors = [System.Collections.Generic.List[string]]::new()

    Write-Host "`nProcessing: $identity" -ForegroundColor Yellow

    try {
        if ($before.ArchiveStatus -ne 'Active') {
            if ($PSCmdlet.ShouldProcess($identity, 'Enable online archive')) {
                Enable-Mailbox -Identity $identity -Archive -ErrorAction Stop
                $actions.Add('Enabled online archive')
            }
            else {
                $actions.Add('WhatIf: Enable online archive')
            }
        }
        else {
            $actions.Add('Online archive already active')
        }

        # ArchiveName is a multi-valued property, so compare its values explicitly.
        if (@($before.ArchiveName) -notcontains $ArchiveDisplayName) {
            if ($PSCmdlet.ShouldProcess($identity, "Set archive name to '$ArchiveDisplayName'")) {
                Set-Mailbox -Identity $identity -ArchiveName $ArchiveDisplayName -ErrorAction Stop
                $actions.Add("Set archive name to '$ArchiveDisplayName'")
            }
            else {
                $actions.Add("WhatIf: Set archive name to '$ArchiveDisplayName'")
            }
        }
        else {
            $actions.Add('Archive name already correct')
        }

        if ($before.AutoExpandingArchiveEnabled -ne $true) {
            if ($PSCmdlet.ShouldProcess($identity, 'Permanently enable auto-expanding archiving')) {
                # The archive must exist before this operation. Enable-Mailbox -Archive is submitted first above.
                Enable-Mailbox -Identity $identity -AutoExpandingArchive -ErrorAction Stop
                $actions.Add('Enabled auto-expanding archiving')
            }
            else {
                $actions.Add('WhatIf: Enable auto-expanding archiving')
            }
        }
        else {
            $actions.Add('Auto-expanding archiving already enabled')
        }

        if ($before.RetentionPolicy -ne $RetentionPolicy) {
            if ($PSCmdlet.ShouldProcess($identity, "Assign MRM policy '$RetentionPolicy'")) {
                Set-Mailbox -Identity $identity -RetentionPolicy $RetentionPolicy -ErrorAction Stop
                $actions.Add("Assigned MRM policy '$RetentionPolicy'")
            }
            else {
                $actions.Add("WhatIf: Assign MRM policy '$RetentionPolicy'")
            }
        }
        else {
            $actions.Add('MRM policy already assigned')
        }

        if ($PSCmdlet.ShouldProcess($identity, 'Start Managed Folder Assistant processing')) {
            try {
                Start-ManagedFolderAssistant -Identity $identity -ErrorAction Stop
                $actions.Add('Started Managed Folder Assistant')
            }
            catch {
                $errors.Add("Managed Folder Assistant: $($_.Exception.Message)")
                Write-Warning "Failed to start Managed Folder Assistant for $identity`: $($_.Exception.Message)"
            }
        }
        else {
            $actions.Add('WhatIf: Start Managed Folder Assistant')
        }
    }
    catch {
        $errors.Add($_.Exception.Message)
        Write-Warning "Configuration failed for $identity`: $($_.Exception.Message)"
    }

    $after = Get-ArchiveState -Identity $identity

    [pscustomobject]@{
        DisplayName                       = $after.DisplayName
        PrimarySmtpAddress                = $after.PrimarySmtpAddress
        RecipientTypeDetails              = $after.RecipientTypeDetails
        LitigationHoldEnabled             = $after.LitigationHoldEnabled
        PreviousRetentionPolicy           = $before.RetentionPolicy
        CurrentRetentionPolicy            = $after.RetentionPolicy
        PreviousArchiveStatus             = $before.ArchiveStatus
        CurrentArchiveStatus              = $after.ArchiveStatus
        CurrentArchiveState               = $after.ArchiveState
        CurrentArchiveName                = (@($after.ArchiveName) -join '; ')
        PreviousAutoExpandingArchive       = $before.AutoExpandingArchiveEnabled
        CurrentAutoExpandingArchive        = $after.AutoExpandingArchiveEnabled
        Actions                            = ($actions -join '; ')
        Errors                             = ($errors -join '; ')
        Successful                        = ($errors.Count -eq 0)
    }
}

$results | Export-Csv -Path $ReportPath -NoTypeInformation -Encoding UTF8

$results |
    Sort-Object Successful, PrimarySmtpAddress |
    Format-Table PrimarySmtpAddress, CurrentRetentionPolicy, CurrentArchiveStatus,
        CurrentAutoExpandingArchive, Successful -AutoSize

$failedCount = @($results | Where-Object { -not $_.Successful }).Count
Write-Host "`nReport: $ReportPath" -ForegroundColor Cyan
Write-Host "Processed: $($results.Count) | Successful: $($results.Count - $failedCount) | With errors: $failedCount" -ForegroundColor Cyan

<#
EXAMPLE DRY RUN

.\Exchange-Set-LitigationHoldArchivePolicy.ps1 `
    -AppId 'ea2ca49b-d0df-4774-b611-86cf9dc9629f' `
    -CertificateThumbprint 'C47B91EB62634CA61FA8146DDA83B8BF605C0962' `
    -Organization 'enchantedrock.onmicrosoft.com' `
    -WhatIf

EXAMPLE LIVE RUN

.\Exchange-Set-LitigationHoldArchivePolicy.ps1 `
    -AppId 'ea2ca49b-d0df-4774-b611-86cf9dc9629f' `
    -CertificateThumbprint 'C47B91EB62634CA61FA8146DDA83B8BF605C0962' `
    -Organization 'enchantedrock.onmicrosoft.com' `
    -Confirm:$false

DELEGATED DRY RUN

.\Exchange-Set-LitigationHoldArchivePolicy.ps1 -WhatIf

Check the litigation hold mailboxes
$mailboxesWithLitigationHold = Get-Mailbox -ResultSize Unlimited -RecipientTypeDetails UserMailbox |
    Where-Object { $_.LitigationHoldEnabled -eq $true } |
    Select-Object DisplayName, PrimarySmtpAddress, RetentionPolicy, LitigationHoldEnabled |
    Format-Table -AutoSize

$mailboxesWithLitigationHold.count

$mailboxes | 
    Select-Object DisplayName, PrimarySmtpAddress, RetentionPolicy, LitigationHoldEnabled |
    Format-Table -AutoSize

$mailboxes.count

#Find mailboxes in $mailboxes, but not in $mailboxesWithLitigationHold
$mailboxesWithoutLitigationHold = $mailboxes | Where-Object { $_.LitigationHoldEnabled -eq $false }
$mailboxesWithoutLitigationHold |
    Select-Object DisplayName, PrimarySmtpAddress, RetentionPolicy, LitigationHoldEnabled |
    Format-Table -AutoSize

$mailboxesWithoutLitigationHold.count
#>
