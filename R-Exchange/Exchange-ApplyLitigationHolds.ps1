# ============================================================
# Apply Litigation Hold Script
# Reads from Excel column: "ApplyHold_UPN"
# Also verifies column: "KeepHoldActive_UPN"
# ============================================================

# -----------------------------
# Config
# -----------------------------
$ExcelPath = "C:\Users\DakotaRuhl\OneDrive - Enchanted Rock\Projects\Mailboxes On Hold\MailboxHoldsUpdate.xlsx"
$WorksheetName = "Resolved UPNs"
$ReportFolder = "C:\Users\DakotaRuhl\OneDrive - Enchanted Rock\Projects\Mailboxes On Hold"

if (-not (Test-Path $ReportFolder)) {
    New-Item -ItemType Directory -Path $ReportFolder | Out-Null
}

$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$ReportPath = Join-Path $ReportFolder "Apply-LitigationHold-Report-$Timestamp.xlsx"

# Optional hold settings
# Leave $LitigationHoldDurationDays as $null for indefinite hold
$LitigationHoldDurationDays = $null
$LitigationHoldOwner = "IT ($($env:USERNAME))"

$WhatIfMode = $false
# -----------------------------
# Import Modules
# -----------------------------
Import-Module ExchangeOnlineManagement -ErrorAction Stop
Import-Module ImportExcel -ErrorAction Stop

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
# Read Excel
# -----------------------------
try {
    $Rows = Import-Excel -Path $ExcelPath -WorksheetName $WorksheetName -ErrorAction Stop
}
catch {
    throw "Failed to read Excel file. Path: $ExcelPath. Worksheet: $WorksheetName. Error: $($_.Exception.Message)"
}

# -----------------------------
# Helper: Get-Mailbox with retry
# -----------------------------
function Invoke-GetMailboxWithRetry {
    param(
        [Parameter(Mandatory)][string]$Identity,
        [int]$MaxAttempts = 3,
        [int]$InitialDelaySeconds = 2,
        [switch]$IncludeInactive,
        [scriptblock]$UntilCondition  # Optional: retry until this returns $true
    )

    $attempt = 0
    $delay = $InitialDelaySeconds
    $lastError = $null

    while ($attempt -lt $MaxAttempts) {
        $attempt++
        try {
            $mbx = Get-Mailbox -Identity $Identity -ErrorAction Stop
        }
        catch {
            $lastError = $_
            $errType = $_.Exception.GetType().Name
            $errMsg  = $_.Exception.Message

            # Hard fail: mailbox truly does not exist. Try inactive fallback once if requested.
            if ($errType -match "ManagementObjectNotFound" -or $errMsg -match "couldn't be found|ManagementObjectNotFound") {
                if ($IncludeInactive) {
                    try {
                        $mbx = Get-Mailbox -Identity $Identity -IncludeInactiveMailbox -ErrorAction Stop
                    }
                    catch {
                        throw $_
                    }
                }
                else {
                    throw $_
                }
            }
            else {
                # Transient: throttling, timeout, connection drop. Backoff and retry.
                if ($attempt -lt $MaxAttempts) {
                    Write-Host "  Transient error on Get-Mailbox '$Identity' (attempt $attempt of $MaxAttempts): $errType. Retrying in ${delay}s..." -ForegroundColor DarkGray
                    Start-Sleep -Seconds $delay
                    $delay = $delay * 2
                    continue
                }
                else {
                    throw $lastError
                }
            }
        }

        # If caller passed an UntilCondition, evaluate it. If true, return. Otherwise retry.
        if ($UntilCondition) {
            if (& $UntilCondition $mbx) {
                return $mbx
            }
            elseif ($attempt -lt $MaxAttempts) {
                Write-Host "  Condition not yet met for '$Identity' (attempt $attempt of $MaxAttempts). Retrying in ${delay}s..." -ForegroundColor DarkGray
                Start-Sleep -Seconds $delay
                $delay = $delay * 2
                continue
            }
        }

        return $mbx
    }

    return $mbx
}

# -----------------------------
# Helper: Determine whether mailbox should be skipped for missing license
# -----------------------------
function Test-MailboxHasHoldLicense {
    param(
        [Parameter(Mandatory)][object]$Mailbox
    )

    # Inactive mailboxes do not use normal active-user licensing checks.
    if ($Mailbox.IsInactiveMailbox -eq $true) {
        return $true
    }

    # SKUAssigned is usually the cleanest quick signal from Get-Mailbox.
    if ($Mailbox.SKUAssigned -eq $true) {
        return $true
    }

    # Some objects may still show PersistedCapabilities even when SKUAssigned is false.
    # This is not a perfect license validation, but it helps avoid false skips.
    if ($Mailbox.PersistedCapabilities -and $Mailbox.PersistedCapabilities.Count -gt 0) {
        return $true
    }

    return $false
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
        [Nullable[bool]]$LitigationHoldEnabled,
        [object]$LitigationHoldDuration,
        [string]$PrimarySmtpAddress,
        [string]$DisplayName
    )

    [PSCustomObject]@{
        Timestamp                 = Get-Date
        Action                    = $Action
        MailboxIdentity           = $MailboxIdentity
        Status                    = $Status
        Message                   = $Message
        LitigationHoldEnabled     = $LitigationHoldEnabled
        LitigationHoldDuration    = $LitigationHoldDuration
        PrimarySmtpAddress        = $PrimarySmtpAddress
        DisplayName               = $DisplayName
    }
}

$Report = New-Object System.Collections.Generic.List[object]

# -----------------------------
# Get users from ApplyHold_UPN column
# -----------------------------
$ApplyHoldUsers = $Rows |
    Where-Object {
        -not [string]::IsNullOrWhiteSpace($_.'ApplyHold_UPN')
    } |
    ForEach-Object {
        [PSCustomObject]@{
            User      = $_.'ApplyHold_UPN'.ToString().Trim().ToLower()
            ApplyNote = if ($null -ne $_.'Apply_Note') { $_.'Apply_Note'.ToString().Trim() } else { "" }
        }
    } |
    Sort-Object User -Unique

# -----------------------------
# Apply Litigation Hold
# -----------------------------

foreach ($Item in $ApplyHoldUsers) {
    $User = $Item.User
    $ApplyNote = $Item.ApplyNote
    $TreatAsInactive = (("$ApplyNote").Trim() -ieq "Inactive")


    Write-Host "Applying litigation hold: $User" -ForegroundColor Cyan

    try {   
        # Confirm mailbox exists first.
        # If the Excel row is marked inactive, include inactive mailbox lookup.
        if ($TreatAsInactive) {
            $MailboxBefore = Invoke-GetMailboxWithRetry -Identity $User -IncludeInactive
        }
        else {
            $MailboxBefore = Invoke-GetMailboxWithRetry -Identity $User
        }

        if ($MailboxBefore.LitigationHoldEnabled -eq $true) {
            $Report.Add((Add-ReportRow `
                -Action "Apply Hold" `
                -MailboxIdentity $User `
                -Status "Skipped" `
                -Message "Mailbox already has litigation hold enabled." `
                -LitigationHoldEnabled $MailboxBefore.LitigationHoldEnabled `
                -LitigationHoldDuration $MailboxBefore.LitigationHoldDuration `
                -PrimarySmtpAddress $MailboxBefore.PrimarySmtpAddress `
                -DisplayName $MailboxBefore.DisplayName))

            continue
        }

        # Skip active/non-inactive mailboxes that appear to be missing licensing.
        if ($MailboxBefore.IsInactiveMailbox -ne $true -and -not (Test-MailboxHasHoldLicense -Mailbox $MailboxBefore)) {
            $Report.Add((Add-ReportRow `
                -Action "Apply Hold" `
                -MailboxIdentity $User `
                -Status "Skipped" `
                -Message "Skipped because mailbox is not inactive and appears to be missing a license required for litigation hold. SKUAssigned is False and no PersistedCapabilities were found." `
                -LitigationHoldEnabled $MailboxBefore.LitigationHoldEnabled `
                -LitigationHoldDuration $MailboxBefore.LitigationHoldDuration `
                -PrimarySmtpAddress $MailboxBefore.PrimarySmtpAddress `
                -DisplayName $MailboxBefore.DisplayName))

            continue
        }

        # Apply hold
        if ($MailboxBefore.IsInactiveMailbox -eq $true) {
            Write-Host "Applying litigation hold to inactive mailbox: $User" -ForegroundColor Magenta

            if ($null -eq $LitigationHoldDurationDays) {
                Set-Mailbox -InactiveMailbox -Identity $MailboxBefore.ExchangeGuid `
                    -LitigationHoldEnabled $true `
                    -ErrorAction Stop
            }
            else {
                Set-Mailbox -InactiveMailbox -Identity $MailboxBefore.ExchangeGuid `
                    -LitigationHoldEnabled $true `
                    -LitigationHoldDuration $LitigationHoldDurationDays `
                    -ErrorAction Stop
            }
        }
        else {
            Write-Host "Applying litigation hold to active mailbox: $User" -ForegroundColor Cyan
            if ($null -eq $LitigationHoldDurationDays) {
                Set-Mailbox -Identity $MailboxBefore.Identity `
                    -LitigationHoldEnabled $true `
                    -LitigationHoldOwner $LitigationHoldOwner `
                    -ErrorAction Stop
            }
            else {
                Set-Mailbox -Identity $MailboxBefore.Identity `
                    -LitigationHoldEnabled $true `
                    -LitigationHoldDuration $LitigationHoldDurationDays `
                    -LitigationHoldOwner $LitigationHoldOwner `
                    -ErrorAction Stop
            }
        }

        # Verify result. Retry until LitigationHoldEnabled flips to true, or attempts exhausted.
        if ($MailboxBefore.IsInactiveMailbox -eq $true) {
            $MailboxAfter = Invoke-GetMailboxWithRetry -Identity $MailboxBefore.ExchangeGuid -IncludeInactive -UntilCondition {
                param($m) $m.LitigationHoldEnabled -eq $true
            }
        }
        else {  
            $MailboxAfter = Invoke-GetMailboxWithRetry -Identity $MailboxBefore.Identity -UntilCondition {
                param($m) $m.LitigationHoldEnabled -eq $true
            }
        }

        if ($MailboxAfter.LitigationHoldEnabled -eq $true) {
            $Status = "Success"

            if ($MailboxBefore.IsInactiveMailbox -eq $true) {
                $Message = "Litigation hold enabled on inactive mailbox. LitigationHoldOwner was not set."
            }
            else {
                $Message = "Litigation hold enabled."
            }
        }
        else {
            $Status = "Warning"
            $Message = "Set-Mailbox completed, but verification did not show LitigationHoldEnabled as True."
        }


        $Report.Add((Add-ReportRow `
            -Action "Apply Hold" `
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
            -Action "Apply Hold" `
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
# Verify KeepHoldActive_UPN column
# -----------------------------
$KeepHoldActiveUsers = $Rows |
    ForEach-Object { $_.'KeepHoldActive_UPN' } |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
    ForEach-Object { $_.ToString().Trim().ToLower() } |
    Sort-Object -Unique

foreach ($User in $KeepHoldActiveUsers) {
    Write-Host "Verifying hold remains active: $User" -ForegroundColor Yellow

    try {
        $Mailbox = Invoke-GetMailboxWithRetry -Identity $User -IncludeInactive

        if ($Mailbox.LitigationHoldEnabled -eq $true) {
            $Status = "Success"
            $Message = "Litigation hold is active."
        }
        else {
            $Status = "Failed"
            $Message = "Expected litigation hold to be active, but it is not enabled."
        }

        $Report.Add((Add-ReportRow `
            -Action "Verify Keep Hold Active" `
            -MailboxIdentity $User `
            -Status $Status `
            -Message $Message `
            -LitigationHoldEnabled $Mailbox.LitigationHoldEnabled `
            -LitigationHoldDuration $Mailbox.LitigationHoldDuration `
            -PrimarySmtpAddress $Mailbox.PrimarySmtpAddress `
            -DisplayName $Mailbox.DisplayName))
    }
    catch {
        $Report.Add((Add-ReportRow `
            -Action "Verify Keep Hold Active" `
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
Write-Host "Apply litigation hold script completed." -ForegroundColor Green
Write-Host ""

if ($Report.Count -eq 0) {
    Write-Warning "No rows processed. Skipping report export."
} 
else {
    Write-Host "Summary:" -ForegroundColor Cyan
    $Summary = $Report | Group-Object Action, Status | Select-Object Count, Name
    $Summary | Format-Table -AutoSize
    $Report | Export-Excel -Path $ReportPath -WorksheetName "Report" -AutoSize -TableName "ApplyHoldReport"
    Write-Host "Report exported to: $ReportPath" -ForegroundColor Green
}


# Optional
# Disconnect-ExchangeOnline -Confirm:$false