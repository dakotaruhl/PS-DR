# ============================================================
# Remove Litigation Hold Script
# Reads from Excel column: "Remove Hold"
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
if (-not (Test-Path -Path $ExcelPath)) {
    throw "Excel file does not exist: $ExcelPath"
}

$ReportFolder = "C:\Users\DakotaRuhl\OneDrive - Enchanted Rock\Projects\Mailboxes On Hold"
$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$ReportPath = Join-Path $ReportFolder "Remove-LitigationHold-Report-$Timestamp.xlsx"
if (-not (Test-Path -Path $ReportFolder)) {
    throw "Report folder does not exist: $ReportFolder"
}

$WhatIfMode = $false
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
# Check for conflicts in excel sheet
# -----------------------------
$Apply = @(
    $Rows |
        ForEach-Object { $_.'ApplyHold_UPN' } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        ForEach-Object { $_.ToString().Trim().ToLower() } |
        Sort-Object -Unique
)

$Remove = @(
    $Rows |
        ForEach-Object { $_.'RemoveHold_UPN' } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        ForEach-Object { $_.ToString().Trim().ToLower() } |
        Sort-Object -Unique
)

if ($Apply.Count -gt 0 -and $Remove.Count -gt 0) {
    $Conflict = Compare-Object -ReferenceObject $Apply -DifferenceObject $Remove -IncludeEqual -ExcludeDifferent |
        Select-Object -ExpandProperty InputObject
    }
else {
    $Conflict = @()
}


if ($Conflict) {
    Write-Warning "These users are listed in both Apply Hold and Remove Hold:"
    $Conflict | ForEach-Object { Write-Warning $_ }

    throw "Conflict detected. Fix the Excel sheet before removing litigation holds."
}
else {
    Write-Host "No Apply/Remove conflicts found." -ForegroundColor Green
}
# ============================================================

# -----------------------------
# Connect to Exchange Online
# -----------------------------
try {
    $existing = Get-ConnectionInformation -ErrorAction SilentlyContinue |
        Where-Object { $_.State -eq "Connected" -and $_.TokenStatus -eq "Active" }

    if ($existing) {
        Write-Host "Exchange Online already connected" -ForegroundColor Green
    } else {
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
        [object]$LitigationHoldEnabled,
        [object]$LitigationHoldDuration,
        [string]$PrimarySmtpAddress,
        [string]$DisplayName,
        [object]$PreviousLitigationHoldEnabled,
        [object]$PreviousLitigationHoldDuration
    )

    [PSCustomObject]@{
        Timestamp                       = Get-Date
        Action                          = $Action
        MailboxIdentity                 = $MailboxIdentity
        Status                          = $Status
        Message                         = $Message
        LitigationHoldEnabled           = $LitigationHoldEnabled
        LitigationHoldDuration          = $LitigationHoldDuration
        PrimarySmtpAddress              = $PrimarySmtpAddress
        DisplayName                     = $DisplayName       
        PreviousLitigationHoldEnabled   = $PreviousLitigationHoldEnabled
        PreviousLitigationHoldDuration  = $PreviousLitigationHoldDuration

    }
}
# -----------------------------
# Helper function Set-LitigationHoldWithRetry
# -----------------------------
function Set-LitigationHoldWithRetry {
    param(
        [Parameter(Mandatory)]
        [string]$Identity,

        [Parameter(Mandatory)]
        [bool]$Enabled,

        [int]$MaxAttempts = 3,

        [int]$DelaySeconds = 5
    )

    for ($Attempt = 1; $Attempt -le $MaxAttempts; $Attempt++) {
        try {
            Set-Mailbox -Identity $Identity -LitigationHoldEnabled $Enabled -ErrorAction Stop
            return
        }
        catch {
            if ($Attempt -eq $MaxAttempts) {
                throw
            }

            Write-Warning "Set-Mailbox failed for $Identity. Attempt $Attempt of $MaxAttempts. Retrying in $DelaySeconds seconds. Error: $($_.Exception.Message)"
            Start-Sleep -Seconds $DelaySeconds
        }
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

            Write-Warning "Get-Mailbox failed for $Identity. Attempt $Attempt of $MaxAttempts. Retrying in $DelaySeconds seconds. Error: $($_.Exception.Message)"
            Start-Sleep -Seconds $DelaySeconds
        }
    }
}

$Report = New-Object System.Collections.Generic.List[object]

# -----------------------------
# Get users from Remove Hold column
# -----------------------------
$RemoveHoldUsers = $Rows |
    ForEach-Object { $_.'RemoveHold_UPN' } |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
    ForEach-Object { $_.ToString().Trim() } |
    Sort-Object -Unique

# -----------------------------
# Remove Litigation Hold
# -----------------------------
foreach ($User in $RemoveHoldUsers) {
    if ($WhatIfMode) {
        Write-Host "WhatIf: would remove litigation hold: $User" -ForegroundColor Yellow
    }
    else {
        Write-Host "Removing litigation hold: $User" -ForegroundColor Cyan
    }

    try {
        # Confirm mailbox exists first
        $MailboxBefore = Get-MailboxWithRetry -Identity $User

        if ($MailboxBefore.LitigationHoldEnabled -eq $false) {
            $Report.Add((Add-ReportRow `
                -Action "Remove Hold" `
                -MailboxIdentity $User `
                -Status $Status `
                -Message $Message `
                -LitigationHoldEnabled $MailboxAfter.LitigationHoldEnabled `
                -LitigationHoldDuration $MailboxAfter.LitigationHoldDuration `
                -PrimarySmtpAddress $MailboxAfter.PrimarySmtpAddress `
                -DisplayName $MailboxAfter.DisplayName `
                -PreviousLitigationHoldEnabled $MailboxBefore.LitigationHoldEnabled `
                -PreviousLitigationHoldDuration $MailboxBefore.LitigationHoldDuration))

            continue
        }

        if ($WhatIfMode) {
            $Status = "WhatIf"
            $Message = "Would remove litigation hold. No change made because WhatIfMode is enabled."
            $Report.Add((Add-ReportRow `
                -Action "Remove Hold" `
                -MailboxIdentity $User `
                -Status $Status `
                -Message $Message `
                -LitigationHoldEnabled $MailboxAfter.LitigationHoldEnabled `
                -LitigationHoldDuration $MailboxAfter.LitigationHoldDuration `
                -PrimarySmtpAddress $MailboxAfter.PrimarySmtpAddress `
                -DisplayName $MailboxAfter.DisplayName `
                -PreviousLitigationHoldEnabled $MailboxBefore.LitigationHoldEnabled `
                -PreviousLitigationHoldDuration $MailboxBefore.LitigationHoldDuration))

            continue
        }

        # Remove hold
        Set-LitigationHoldWithRetry -Identity $User -Enabled $false

        # Verify result
        $MailboxAfter = Get-MailboxWithRetry -Identity $User

        if ($MailboxAfter.LitigationHoldEnabled -eq $false) {
            $Status = "Success"
            $Message = "Litigation hold removed."
        }
        else {
            $Status = "Warning"
            $Message = "Set-Mailbox completed, but verification still shows LitigationHoldEnabled as True."
        }

        $Report.Add((Add-ReportRow `
            -Action "Remove Hold" `
            -MailboxIdentity $User `
            -Status $Status `
            -Message $Message `
            -LitigationHoldEnabled $MailboxAfter.LitigationHoldEnabled `
            -LitigationHoldDuration $MailboxAfter.LitigationHoldDuration `
            -PrimarySmtpAddress $MailboxAfter.PrimarySmtpAddress `
            -DisplayName $MailboxAfter.DisplayName))
    }
    catch {
        $Report.Add((Add-ReportRow `
            -Action "Remove Hold" `
            -MailboxIdentity $User `
            -Status "Failed" `
            -Message $_.Exception.Message `
            -LitigationHoldEnabled $null `
            -LitigationHoldDuration $null `
            -PrimarySmtpAddress $null `
            -DisplayName $null))
    }
}

# -----------------------------
# Export Report
# -----------------------------

Write-Host ""
Write-Host "Remove litigation hold script completed." -ForegroundColor Green

if ($Report.Count -gt 0) {
    Write-Host "Summary:" -ForegroundColor Cyan
    $Summary = $Report | Group-Object Action, Status | Select-Object Count, Name
    $Summary | Format-Table -AutoSize
    $Report | Export-Excel -Path $ReportPath -WorksheetName "Report" -AutoSize -TableName "RemoveHoldReport"
    Write-Host "Report exported to: $ReportPath" -ForegroundColor Green
}
else {
    Write-Warning "No report was exported because no rows were processed."
}

# Optional
# Disconnect-ExchangeOnline -Confirm:$false