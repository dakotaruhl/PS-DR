#Requires -Modules ExchangeOnlineManagement,ImportExcel

param(
    [int]$DaysBack = 180,
    [string]$ReportPath = ".\output\DisabledUsersAudit.xlsx"
)

Connect-ExchangeOnline

$StartDate = (Get-Date).AddDays(-$DaysBack)
$EndDate   = Get-Date

$SessionId = [Guid]::NewGuid().ToString()
Write-Host "Retrieving audit logs..." -ForegroundColor Cyan

$Records = @()

do {
    $Batch = Search-UnifiedAuditLog `
        -StartDate $StartDate `
        -EndDate $EndDate `
        -Operations "Update user" `
        -SessionId $SessionId `
        -SessionCommand ReturnLargeSet `
        -ResultSize 5000

    $Records += $Batch

    Write-Progress `
        -Activity "Downloading Audit Logs" `
        -Status "$($Records.Count) records retrieved"

} while ($Batch.Count -gt 0)

Write-Host "Processing $($Records.Count) audit records..." -ForegroundColor Cyan

$Results = foreach ($Record in $Records) {

    try {
        $AuditData = $Record.AuditData | ConvertFrom-Json

        $AccountEnabledProperty = $AuditData.ModifiedProperties |
            Where-Object {
                $_.Name -eq 'AccountEnabled'
            }

        if (-not $AccountEnabledProperty) {
            continue
        }

        $OldValue = ($AccountEnabledProperty.OldValue | Out-String).Trim()
        $NewValue = ($AccountEnabledProperty.NewValue | Out-String).Trim()

        $WasDisabled =
            ($OldValue -match 'true') -and
            ($NewValue -match 'false')

        if (-not $WasDisabled) {
            continue
        }

        [PSCustomObject]@{
            DisabledDate      = $Record.CreationDate
            DisabledUser      = $AuditData.ObjectId
            DisabledBy        = $AuditData.UserId
            ClientIP          = $AuditData.ClientIP
            ResultStatus      = $AuditData.ResultStatus
            Operation         = $Record.Operations
            Workload          = $Record.Workload
            CorrelationId     = $AuditData.Id
            UserAgent         = $AuditData.UserAgent
        }
    }
    catch {
        Write-Warning "Failed to process record"
    }
}

$Results =
    $Results |
    Sort-Object DisabledDate -Descending

$Results | Export-Excel `
    -Path $ReportPath `
    -WorksheetName "Disabled Users" `
    -TableName DisabledUsers `
    -AutoSize `
    -FreezeTopRow `
    -BoldTopRow `
    -AutoFilter

Write-Host ""
Write-Host "Disable events found: $($Results.Count)" -ForegroundColor Green
Write-Host "Report saved to: $ReportPath" -ForegroundColor Green