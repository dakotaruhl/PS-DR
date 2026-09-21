function Enable-Users {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory)]
        [string]$ExcelPath,

        [string]$WorksheetName = 'Results',

        [Parameter(Mandatory)]
        [string]$TenantId,

        [Parameter(Mandatory)]
        [string]$ClientId,

        [Parameter(Mandatory)]
        [string]$CertThumbprint
    )

    $RequiredModules = @(
        'ImportExcel',
        'Microsoft.Graph.Authentication',
        'Microsoft.Graph.Users'
    )

    foreach ($ModuleName in $RequiredModules) {
        if (-not (Get-Module -ListAvailable -Name $ModuleName)) {
            throw "Required module '$ModuleName' is not installed."
        }
        Import-Module $ModuleName -ErrorAction Stop
    }

    if (-not (Test-Path -LiteralPath $ExcelPath)) {
        throw "Excel file not found: $ExcelPath"
    }

    if ([System.IO.Path]::GetExtension($ExcelPath) -ine '.xlsx') {
        throw "Input must be an .xlsx file: $ExcelPath"
    }

    Connect-MgGraph `
        -TenantId $TenantId `
        -ClientId $ClientId `
        -CertificateThumbprint $CertThumbprint `
        -NoWelcome

    $Rows = @(
        Import-Excel `
            -Path $ExcelPath `
            -WorksheetName $WorksheetName `
            -ErrorAction Stop
    )

    if ($Rows.Count -eq 0) {
        throw "No data rows were found on worksheet '$WorksheetName'."
    }

    $AvailableColumns = @($Rows[0].PSObject.Properties.Name)
    if ('UPN' -notin $AvailableColumns) {
        throw "Required column 'UPN' was not found on worksheet '$WorksheetName'."
    }

    $EnabledCount = 0
    $AlreadyEnabledCount = 0
    $FailedCount = 0
    $SkippedCount = 0

    foreach ($Row in $Rows) {
        $UPN = ([string]$Row.UPN).Trim()
        $DisplayName = ([string]$Row.DisplayName).Trim()

        if ([string]::IsNullOrWhiteSpace($UPN)) {
            $SkippedCount++
            Write-Warning 'Skipping row because UPN is blank.'
            continue
        }

        if ([string]::IsNullOrWhiteSpace($DisplayName)) {
            $DisplayName = $UPN
        }

        Write-Host ''
        Write-Host '==================================================' -ForegroundColor DarkGray
        Write-Host "Processing: $DisplayName <$UPN>" -ForegroundColor Cyan
        Write-Host '==================================================' -ForegroundColor DarkGray

        try {
            $User = Get-MgUser `
                -UserId $UPN `
                -Property Id,DisplayName,UserPrincipalName,AccountEnabled `
                -ErrorAction Stop

            if ($User.AccountEnabled -eq $true) {
                $AlreadyEnabledCount++
                Write-Host 'Account is already enabled. No change required.' -ForegroundColor DarkGreen
                continue
            }

            if ($PSCmdlet.ShouldProcess($UPN, 'Enable Microsoft Entra user account')) {
                Update-MgUser `
                    -UserId $User.Id `
                    -AccountEnabled:$true `
                    -ErrorAction Stop

                # Verify the resulting state rather than assuming the update succeeded.
                $VerifiedUser = Get-MgUser `
                    -UserId $User.Id `
                    -Property Id,UserPrincipalName,AccountEnabled `
                    -ErrorAction Stop

                if ($VerifiedUser.AccountEnabled -ne $true) {
                    throw 'Update completed, but AccountEnabled did not verify as TRUE.'
                }

                $EnabledCount++
                Write-Host 'Account enabled and verified.' -ForegroundColor Green
            }
        }
        catch {
            $FailedCount++
            Write-Error "Failed processing '$UPN': $($_.Exception.Message)"
        }
    }

    Write-Host ''
    Write-Host '==================== Summary ====================' -ForegroundColor Cyan
    Write-Host "Enabled:         $EnabledCount" -ForegroundColor Green
    Write-Host "Already enabled: $AlreadyEnabledCount" -ForegroundColor DarkGreen
    Write-Host "Skipped:         $SkippedCount" -ForegroundColor Yellow
    Write-Host "Failed:          $FailedCount" -ForegroundColor Red
    Write-Host '=================================================' -ForegroundColor Cyan
}

# Example dry run:
<#
Enable-Users `
    -ExcelPath '.\Input Data\Aerotek FTE.xlsx' `
    -WorksheetName 'Results' `
    -TenantId "0bdf0e1f-a359-4b5c-9b79-9357e35ff8c6" `
    -ClientId "ea2ca49b-d0df-4774-b611-86cf9dc9629f" `
    -CertThumbprint "C47B91EB62634CA61FA8146DDA83B8BF605C0962" `
    -WhatIf
#>

# Example live run:
<#
Enable-Users `
    -ExcelPath '.\Input Data\Aerotek FTE.xlsx' `
    -WorksheetName 'Results' `
    -TenantId "0bdf0e1f-a359-4b5c-9b79-9357e35ff8c6" `
    -ClientId "ea2ca49b-d0df-4774-b611-86cf9dc9629f" `
    -CertThumbprint "C47B91EB62634CA61FA8146DDA83B8BF605C0962"
#>
