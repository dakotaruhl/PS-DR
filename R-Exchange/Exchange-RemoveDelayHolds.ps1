# ============================================================
# Remove Delay Hold Script
# Reads from Excel column: RemoveHold_UPN
# Removes DelayHoldApplied and DelayReleaseHoldApplied
# ============================================================

# -----------------------------
# Import Modules
# -----------------------------
Import-Module ExchangeOnlineManagement -ErrorAction Stop
Import-Module ImportExcel -ErrorAction Stop

# -----------------------------
# Config
# -----------------------------
$ExcelPath = "C:\Users\DakotaRuhl\OneDrive - Enchanted Rock\Projects\Mailboxes On Hold\MailboxHoldsUpdate.xlsx"
$WorksheetName = "Resolved UPNs"

$ReportFolder = "C:\Users\DakotaRuhl\OneDrive - Enchanted Rock\Projects\Mailboxes On Hold"
$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$ReportPath = Join-Path $ReportFolder "Remove-DelayHold-Report-$Timestamp.xlsx"

$WhatIfMode = $true

if (-not (Test-Path -Path $ExcelPath)) {
    throw "Excel file does not exist: $ExcelPath"
}

if (-not (Test-Path -Path $ReportFolder)) {
    throw "Report folder does not exist: $ReportFolder"
}

# -----------------------------
# Read Excel
# -----------------------------
try {
    $Rows = Import-Excel -Path $ExcelPath -WorksheetName $WorksheetName -ErrorAction Stop
}
catch {
    throw "Failed to read Excel file. Path: $ExcelPath. Worksheet: $WorksheetName. Error: $($_.Exception.Message)"
}

# -----------------------------
# Connect to Exchange Online
# -----------------------------
try {
    $existing = Get-ConnectionInformation -ErrorAction SilentlyContinue |
        Where-Object { $_.State -eq "Connected" -and $_.TokenStatus -eq "Active" }

    if ($existing) {
        Write-Host "Exchange Online already connected" -ForegroundColor Green
    }
    else {
        Write-Host "Connecting to Exchange Online" -ForegroundColor DarkYellow
        Connect-ExchangeOnline -ShowBanner:$false -ErrorAction Stop
    }
}
catch {
    throw "Failed to connect to Exchange Online: $($_.Exception.Message)"
}

# -----------------------------
# Helper function Add-ReportRow
# -----------------------------
function Add-ReportRow {
    param(
        [string]$Action,
        [string]$MailboxIdentity,
        [string]$Status,
        [string]$Message,
        [object]$InPlaceHolds,
        [object]$ComplianceTagHoldApplied,
        [object]$RetentionHoldEnabled,
        [object]$LitigationHoldEnabled,
        [object]$DelayHoldApplied,
        [object]$DelayReleaseHoldApplied,
        [object]$PreviousDelayHoldApplied,
        [object]$PreviousDelayReleaseHoldApplied,
        [string]$PrimarySmtpAddress,
        [string]$DisplayName
    )

    [PSCustomObject]@{
        Timestamp                         = Get-Date
        Action                            = $Action
        MailboxIdentity                   = $MailboxIdentity
        Status                            = $Status
        Message                           = $Message
        LitigationHoldEnabled             = $LitigationHoldEnabled
        DelayHoldApplied                  = $DelayHoldApplied
        DelayReleaseHoldApplied           = $DelayReleaseHoldApplied
        PreviousDelayHoldApplied          = $PreviousDelayHoldApplied
        PreviousDelayReleaseHoldApplied   = $PreviousDelayReleaseHoldApplied
        PrimarySmtpAddress                = $PrimarySmtpAddress
        DisplayName                       = $DisplayName
        InPlaceHolds                      = ($InPlaceHolds -join ";")
        ComplianceTagHoldApplied          = $ComplianceTagHoldApplied
        RetentionHoldEnabled              = $RetentionHoldEnabled
    }
}

# -----------------------------
# Helper function Get-MailboxWithRetry
# -----------------------------
function Get-MailboxWithRetry {
    param(
        [Parameter(Mandatory)]
        [string]$Identity,

        [int]$MaxAttempts = 3,

        [int]$DelaySeconds = 5
    )

    for ($Attempt = 1; $Attempt -le $MaxAttempts; $Attempt++) {
        try {
            return Get-Mailbox -Identity $Identity -ErrorAction Stop
        }
        catch {
            if ($Attempt -eq $MaxAttempts) {
                throw
            }

            Write-Warning "Get-Mailbox failed for $($Identity). Attempt $Attempt of $MaxAttempts. Retrying in $DelaySeconds seconds. Error: $($_.Exception.Message)"
            Start-Sleep -Seconds $DelaySeconds
        }
    }
}

# -----------------------------
# Helper function SetMailboxSwitchWithRetry
# -----------------------------
function Invoke-SetMailboxSwitchWithRetry {
    param(
        [Parameter(Mandatory)]
        [string]$Identity,

        [Parameter(Mandatory)]
        [ValidateSet("RemoveDelayHoldApplied", "RemoveDelayReleaseHoldApplied")]
        [string]$SwitchName,

        [int]$MaxAttempts = 3,

        [int]$DelaySeconds = 5
    )

    for ($Attempt = 1; $Attempt -le $MaxAttempts; $Attempt++) {
        try {
            if ($SwitchName -eq "RemoveDelayHoldApplied") {
                Set-Mailbox -Identity $Identity -RemoveDelayHoldApplied -ErrorAction Stop
            }

            if ($SwitchName -eq "RemoveDelayReleaseHoldApplied") {
                Set-Mailbox -Identity $Identity -RemoveDelayReleaseHoldApplied -ErrorAction Stop
            }

            return
        }
        catch {
            if ($Attempt -eq $MaxAttempts) {
                throw
            }

            Write-Warning "Set-Mailbox $($SwitchName) failed for $($Identity). Attempt $Attempt of $MaxAttempts. Retrying in $DelaySeconds seconds. Error: $($_.Exception.Message)"
            Start-Sleep -Seconds $DelaySeconds
        }
    }
}

$Report = New-Object System.Collections.Generic.List[object]

# -----------------------------
# Get users from RemoveHold_UPN column
# -----------------------------
$Users = @(
    $Rows |
        ForEach-Object { $_.'RemoveHold_UPN' } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        ForEach-Object { $_.ToString().Trim() } |
        Sort-Object -Unique
)

if ($Users.Count -eq 0) {
    Write-Warning "No users found in RemoveHold_UPN. Nothing to process."
}

# -----------------------------
# Remove Delay Holds
# -----------------------------
foreach ($User in $Users) {
    $MailboxBefore = $null
    $MailboxAfter = $null
    $MailboxErrorState = $null
    $PreviousDelayHoldApplied = $null
    $PreviousDelayReleaseHoldApplied = $null
    
    if ($WhatIfMode) {
        Write-Host "WhatIf: would check/remove delay hold: $User" -ForegroundColor Yellow
    }
    else {
        Write-Host "Checking/removing delay hold: $User" -ForegroundColor Cyan
    }

    try {
        $MailboxBefore = Get-MailboxWithRetry -Identity $User

        $PreviousDelayHoldApplied = $MailboxBefore.DelayHoldApplied
        $PreviousDelayReleaseHoldApplied = $MailboxBefore.DelayReleaseHoldApplied

        if ($MailboxBefore.LitigationHoldEnabled -eq $true) {
            $Report.Add((Add-ReportRow `
                -Action "Remove Delay Hold" `
                -MailboxIdentity $User `
                -Status "Skipped" `
                -Message "Skipped because LitigationHoldEnabled is still True. Remove litigation hold first, then rerun delay hold removal." `
                -LitigationHoldEnabled $MailboxBefore.LitigationHoldEnabled `
                -DelayHoldApplied $MailboxBefore.DelayHoldApplied `
                -DelayReleaseHoldApplied $MailboxBefore.DelayReleaseHoldApplied `
                -PreviousDelayHoldApplied $PreviousDelayHoldApplied `
                -PreviousDelayReleaseHoldApplied $PreviousDelayReleaseHoldApplied `
                -PrimarySmtpAddress $MailboxBefore.PrimarySmtpAddress `
                -InPlaceHolds $MailboxBefore.InPlaceHolds `
                -ComplianceTagHoldApplied $MailboxBefore.ComplianceTagHoldApplied `
                -RetentionHoldEnabled $MailboxBefore.RetentionHoldEnabled `
                -DisplayName $MailboxBefore.DisplayName))

            continue
        }

        if ($MailboxBefore.DelayHoldApplied -ne $true -and $MailboxBefore.DelayReleaseHoldApplied -ne $true) {
            $Report.Add((Add-ReportRow `
                -Action "Remove Delay Hold" `
                -MailboxIdentity $User `
                -Status "Skipped" `
                -Message "Skipped because both DelayHoldApplied and DelayReleaseHoldApplied are false." `
                -LitigationHoldEnabled $MailboxBefore.LitigationHoldEnabled `
                -DelayHoldApplied $MailboxBefore.DelayHoldApplied `
                -DelayReleaseHoldApplied $MailboxBefore.DelayReleaseHoldApplied `
                -PreviousDelayHoldApplied $PreviousDelayHoldApplied `
                -PreviousDelayReleaseHoldApplied $PreviousDelayReleaseHoldApplied `
                -PrimarySmtpAddress $MailboxBefore.PrimarySmtpAddress `
                -InPlaceHolds $MailboxBefore.InPlaceHolds `
                -ComplianceTagHoldApplied $MailboxBefore.ComplianceTagHoldApplied `
                -RetentionHoldEnabled $MailboxBefore.RetentionHoldEnabled `
                -DisplayName $MailboxBefore.DisplayName))

            continue
        }

        if ($WhatIfMode) {
            $Report.Add((Add-ReportRow `
                -Action "Remove Delay Hold" `
                -MailboxIdentity $User `
                -Status "WhatIf" `
                -Message "Would remove delay hold. No change made because WhatIfMode is enabled." `
                -LitigationHoldEnabled $MailboxBefore.LitigationHoldEnabled `
                -DelayHoldApplied $MailboxBefore.DelayHoldApplied `
                -DelayReleaseHoldApplied $MailboxBefore.DelayReleaseHoldApplied `
                -PreviousDelayHoldApplied $PreviousDelayHoldApplied `
                -PreviousDelayReleaseHoldApplied $PreviousDelayReleaseHoldApplied `
                -PrimarySmtpAddress $MailboxBefore.PrimarySmtpAddress `
                -InPlaceHolds $MailboxBefore.InPlaceHolds `
                -ComplianceTagHoldApplied $MailboxBefore.ComplianceTagHoldApplied `
                -RetentionHoldEnabled $MailboxBefore.RetentionHoldEnabled `
                -DisplayName $MailboxBefore.DisplayName))

            continue
        }

        if ($MailboxBefore.DelayHoldApplied -eq $true) {
            Invoke-SetMailboxSwitchWithRetry -Identity $User -SwitchName "RemoveDelayHoldApplied"
        }
        if ($MailboxBefore.DelayReleaseHoldApplied -eq $true) {
            Invoke-SetMailboxSwitchWithRetry -Identity $User -SwitchName "RemoveDelayReleaseHoldApplied"
        }

        Start-Sleep -Seconds 10
        $MailboxAfter = Get-MailboxWithRetry -Identity $User

        if ($MailboxAfter.DelayHoldApplied -eq $false -and $MailboxAfter.DelayReleaseHoldApplied -eq $false) {
            $Status = "Success"
            $Message = "Delay hold removed."
        }
        else {
            $Status = "Warning"
            $Message = "Remove delay hold command completed, but immediate verification still shows one or more delay hold properties as True. This may be replication delay; recheck later."
        }

        $Report.Add((Add-ReportRow `
            -Action "Remove Delay Hold" `
            -MailboxIdentity $User `
            -Status $Status `
            -Message $Message `
            -LitigationHoldEnabled $MailboxAfter.LitigationHoldEnabled `
            -DelayHoldApplied $MailboxAfter.DelayHoldApplied `
            -DelayReleaseHoldApplied $MailboxAfter.DelayReleaseHoldApplied `
            -PreviousDelayHoldApplied $PreviousDelayHoldApplied `
            -PreviousDelayReleaseHoldApplied $PreviousDelayReleaseHoldApplied `
            -PrimarySmtpAddress $MailboxAfter.PrimarySmtpAddress `
            -InPlaceHolds $MailboxAfter.InPlaceHolds `
            -ComplianceTagHoldApplied $MailboxAfter.ComplianceTagHoldApplied `
            -RetentionHoldEnabled $MailboxAfter.RetentionHoldEnabled `
            -DisplayName $MailboxAfter.DisplayName))
    }
    catch {
        $ErrorMessage = $_.Exception.Message
        try {
            $MailboxErrorState = Get-MailboxWithRetry -Identity $User

            $Report.Add((Add-ReportRow `
                -Action "Remove Delay Hold" `
                -MailboxIdentity $User `
                -Status "Failed" `
                -Message $ErrorMessage `
                -LitigationHoldEnabled $MailboxErrorState.LitigationHoldEnabled `
                -DelayHoldApplied $MailboxErrorState.DelayHoldApplied `
                -DelayReleaseHoldApplied $MailboxErrorState.DelayReleaseHoldApplied `
                -PreviousDelayHoldApplied $PreviousDelayHoldApplied `
                -PreviousDelayReleaseHoldApplied $PreviousDelayReleaseHoldApplied `
                -PrimarySmtpAddress $MailboxErrorState.PrimarySmtpAddress `
                -InPlaceHolds $MailboxErrorState.InPlaceHolds `
                -ComplianceTagHoldApplied $MailboxErrorState.ComplianceTagHoldApplied `
                -RetentionHoldEnabled $MailboxErrorState.RetentionHoldEnabled `
                -DisplayName $MailboxErrorState.DisplayName))
        }
        catch {
            $Report.Add((Add-ReportRow `
                -Action "Remove Delay Hold" `
                -MailboxIdentity $User `
                -Status "Failed" `
                -Message $ErrorMessage `
                -LitigationHoldEnabled $null `
                -DelayHoldApplied $null `
                -DelayReleaseHoldApplied $null `
                -PreviousDelayHoldApplied $PreviousDelayHoldApplied `
                -PreviousDelayReleaseHoldApplied $PreviousDelayReleaseHoldApplied `
                -InPlaceHolds $null `
                -ComplianceTagHoldApplied $null `
                -RetentionHoldEnabled $null `
                -PrimarySmtpAddress $null `
                -DisplayName $null))
        }   
    }
}

# -----------------------------
# Export Report
# -----------------------------
Write-Host ""
Write-Host "Remove delay hold script completed." -ForegroundColor Green

if ($Report.Count -gt 0) {
    Write-Host "Summary:" -ForegroundColor Cyan
    $Summary = $Report | Group-Object Action, Status | Select-Object Count, Name
    $Summary | Format-Table -AutoSize

    try {
        $Report | Export-Excel -Path $ReportPath -WorksheetName "Report" -AutoSize -TableName "RemoveDelayHoldReport" -ErrorAction Stop
        Write-Host "Report exported to: $ReportPath" -ForegroundColor Green
    }
    catch {
        Write-Warning "Failed to export report to: $ReportPath"
        Write-Warning $_.Exception.Message
    }
}
else {
    Write-Warning "No report was exported because no rows were processed."
}

# Optional
# Disconnect-ExchangeOnline -Confirm:$false