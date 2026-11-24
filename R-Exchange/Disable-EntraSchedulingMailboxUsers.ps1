<#
.SYNOPSIS
Disables Entra accounts associated with Exchange SchedulingMailbox users.

.DESCRIPTION
This script identifies all Exchange SchedulingMailbox recipients and disables their corresponding Entra accounts using app-only authentication with Microsoft Graph.

.PARAMETER ReportPath
Specifies the path to the CSV report that will be generated. Defaults to ".\SchedulingMailbox-EntraAudit-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv".

.EXAMPLE
.\R-Exchange\Disable-EntraSchedulingMailboxUsers.ps1 -WhatIf 
.\R-Exchange\Disable-EntraSchedulingMailboxUsers.ps1 -Confirm:$false -ReportPath ".\output\SchedulingMailbox-EntraAudit-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"

#>


[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [string]$ReportPath = ".\SchedulingMailbox-EntraAudit-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Confirm the required sessions already exist.
$mgContext = Get-MgContext

if (-not $mgContext -or $mgContext.AuthType -ne 'AppOnly') {
    throw 'Microsoft Graph is not connected with app-only authentication.'
}

if (-not (Get-ConnectionInformation -ErrorAction SilentlyContinue)) {
    throw 'Exchange Online is not connected. Run Connect-ExchangeOnline first.'
}

Write-Host 'Finding Exchange SchedulingMailbox recipients...' -ForegroundColor Cyan

$schedulingMailboxes = @(
    Get-EXOMailbox `
        -ResultSize Unlimited `
        -Filter "RecipientTypeDetails -eq 'SchedulingMailbox'" `
        -Properties ExternalDirectoryObjectId,RecipientTypeDetails
)

Write-Host "Found $($schedulingMailboxes.Count) scheduling mailbox(es)." -ForegroundColor Cyan

$results = foreach ($mailbox in $schedulingMailboxes) {
    $result = [ordered]@{
        DisplayName               = $mailbox.DisplayName
        PrimarySmtpAddress        = $mailbox.PrimarySmtpAddress.ToString()
        UserPrincipalName         = $mailbox.UserPrincipalName
        ExternalDirectoryObjectId = $mailbox.ExternalDirectoryObjectId
        RecipientTypeDetails      = $mailbox.RecipientTypeDetails
        AccountEnabledBefore      = $null
        Action                    = $null
        AccountEnabledAfter       = $null
        Status                    = $null
        ErrorMessage              = $null
    }

    try {
        if ([string]::IsNullOrWhiteSpace($mailbox.ExternalDirectoryObjectId)) {
            throw 'Scheduling mailbox does not have an ExternalDirectoryObjectId.'
        }

        # Use the immutable Entra object ID, not UPN or SMTP address.
        $entraUser = Get-MgUser `
            -UserId $mailbox.ExternalDirectoryObjectId `
            -Property Id,DisplayName,UserPrincipalName,AccountEnabled `
            -ErrorAction Stop

        $result.AccountEnabledBefore = $entraUser.AccountEnabled

        if ($entraUser.AccountEnabled -eq $false) {
            $result.Action = 'None'
            $result.AccountEnabledAfter = $entraUser.AccountEnabled
            $result.Status = 'Already disabled'
        }
        elseif (
            $PSCmdlet.ShouldProcess(
                "$($mailbox.DisplayName) [$($mailbox.ExternalDirectoryObjectId)]",
                'Disable Entra account associated with Exchange SchedulingMailbox'
            )
        ) {
            $result.Action = 'Disabled'

        # Entra is eventually consistent. Retry verification to allow
        # the AccountEnabled change to propagate across directory replicas.
        $maxVerificationAttempts = 6
        $verificationDelaySeconds = 5
        $verified = $false

        for ($attempt = 1; $attempt -le $maxVerificationAttempts; $attempt++) {

            if ($attempt -gt 1) {
                Start-Sleep -Seconds $verificationDelaySeconds
            }

            $verifiedUser = Get-MgUser `
                -UserId $mailbox.ExternalDirectoryObjectId `
                -Property AccountEnabled `
                -ErrorAction Stop

            $result.AccountEnabledAfter = $verifiedUser.AccountEnabled

            if ($verifiedUser.AccountEnabled -eq $false) {
                $verified = $true
                break
            }

            Write-Verbose "Verification attempt $attempt/$maxVerificationAttempts for '$($mailbox.DisplayName)' still returned AccountEnabled=True."
        }

        if ($verified) {
            $result.Status = 'Success'
        }
        else {
            throw "Graph accepted the update, but AccountEnabled still returned true after $maxVerificationAttempts verification attempts."
        }
        }
        else {
            $result.Action = 'WhatIf'
            $result.AccountEnabledAfter = $entraUser.AccountEnabled
            $result.Status = 'No change'
        }
    }
    catch {
        $result.Action = if ($result.Action) { $result.Action } else { 'Failed' }
        $result.Status = 'Error'
        $result.ErrorMessage = $_.Exception.Message
    }

    [pscustomobject]$result
}

$results |
    Export-Csv `
        -Path $ReportPath `
        -Encoding UTF8 `
        -WhatIf:$false

$results |
    Sort-Object Status, DisplayName |
    Format-Table `
        DisplayName,
        PrimarySmtpAddress,
        AccountEnabledBefore,
        Action,
        AccountEnabledAfter,
        Status `
        -AutoSize

Write-Host ""
Write-Host "Report written to: $ReportPath" -ForegroundColor Green

$summary = $results |
    Group-Object Status |
    Sort-Object Name |
    Select-Object Name, Count

$summary | Format-Table -AutoSize

if ($results.Status -contains 'Error') {
    Write-Warning 'One or more scheduling mailboxes could not be processed. Review ErrorMessage in the CSV report.'
}