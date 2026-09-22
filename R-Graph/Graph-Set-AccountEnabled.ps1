function Enable-Users {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
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

    $RequiredColumns = @(
        'DisplayName',
        'UPN',
        'Offboard -SC account'
    )

    $AvailableColumns = @($Rows[0].PSObject.Properties.Name)
    $MissingColumns = @(
        $RequiredColumns |
            Where-Object { $_ -notin $AvailableColumns }
    )

    if ($MissingColumns.Count -gt 0) {
        throw "Missing required column(s): $($MissingColumns -join ', ')"
    }

    $EnabledCount = 0
    $AlreadyEnabledCount = 0
    $DeletedScCount = 0
    $ScNotFoundCount = 0
    $ScNotApplicableCount = 0
    $FailedCount = 0
    $SkippedCount = 0

    foreach ($Row in $Rows) {
        $UPN = ([string]$Row.UPN).Trim()
        $DisplayName = ([string]$Row.DisplayName).Trim()
        $ScAccountUPN = ([string]$Row.'Offboard -SC account').Trim()

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

            $NewAccountReady = $false

            if ($User.AccountEnabled -eq $true) {
                $AlreadyEnabledCount++
                $NewAccountReady = $true
                Write-Host 'New account is already enabled. No enablement change required.' -ForegroundColor DarkGreen
            }
            else {
                if ($PSCmdlet.ShouldProcess($UPN, 'Enable Microsoft Entra user account')) {
                    Update-MgUser `
                        -UserId $User.Id `
                        -AccountEnabled:$true `
                        -ErrorAction Stop

                    $VerifiedUser = Get-MgUser `
                        -UserId $User.Id `
                        -Property Id,UserPrincipalName,AccountEnabled `
                        -ErrorAction Stop

                    if ($VerifiedUser.AccountEnabled -ne $true) {
                        throw 'Update completed, but AccountEnabled did not verify as TRUE.'
                    }

                    $EnabledCount++
                    $NewAccountReady = $true
                    Write-Host 'New account enabled and verified.' -ForegroundColor Green
                }
                elseif ($WhatIfPreference) {
                    # In a dry run, continue so the proposed SC-account deletion is also displayed.
                    $NewAccountReady = $true
                }
            }

            if (
                [string]::IsNullOrWhiteSpace($ScAccountUPN) -or
                $ScAccountUPN -ieq 'N/A'
            ) {
                $ScNotApplicableCount++
                Write-Host 'No SC account is listed for deletion.' -ForegroundColor DarkGray
                continue
            }

            if ($ScAccountUPN -ieq $UPN) {
                throw "Safety check stopped deletion because the SC account value matches the new account UPN: $UPN"
            }

            if (-not $NewAccountReady) {
                throw "The new account was not enabled and verified. SC account '$ScAccountUPN' was not deleted."
            }

            $ScUser = $null

            try {
                $ScUser = Get-MgUser `
                    -UserId $ScAccountUPN `
                    -Property Id,DisplayName,UserPrincipalName,AccountEnabled `
                    -ErrorAction Stop
            }
            catch {
                if (
                    $_.Exception.Message -match 'Request_ResourceNotFound|does not exist|404|NotFound|ResourceNotFound'
                ) {
                    $ScNotFoundCount++
                    Write-Warning "SC account '$ScAccountUPN' was not found. Nothing was deleted."
                    continue
                }

                throw "Failed to look up SC account '$ScAccountUPN': $($_.Exception.Message)"
            }

            if ($ScUser.UserPrincipalName -ine $ScAccountUPN) {
                throw "Safety check failed. Requested '$ScAccountUPN', but Graph returned '$($ScUser.UserPrincipalName)'."
            }

            if ($PSCmdlet.ShouldProcess($ScAccountUPN, "Delete SC account paired with '$UPN'")) {
                Remove-MgUser `
                    -UserId $ScUser.Id `
                    -Confirm:$false `
                    -ErrorAction Stop

                # Verify the active user object is no longer retrievable.
                $ScAccountStillExists = $false

                try {
                    Get-MgUser `
                        -UserId $ScUser.Id `
                        -Property Id `
                        -ErrorAction Stop | Out-Null

                    $ScAccountStillExists = $true
                }
                catch {
                    if (
                        $_.Exception.Message -notmatch 'Request_ResourceNotFound|does not exist|404|NotFound|ResourceNotFound'
                    ) {
                        throw "SC account deletion could not be verified: $($_.Exception.Message)"
                    }
                }

                if ($ScAccountStillExists) {
                    throw "Delete request completed, but SC account '$ScAccountUPN' is still retrievable."
                }

                $DeletedScCount++
                Write-Host "SC account deleted and verified: $ScAccountUPN" -ForegroundColor Green
            }
        }
        catch {
            $FailedCount++
            Write-Error "Failed processing '$UPN': $($_.Exception.Message)"
        }
    }

    Write-Host ''
    Write-Host '==================== Summary ====================' -ForegroundColor Cyan
    Write-Host "New accounts enabled:         $EnabledCount" -ForegroundColor Green
    Write-Host "New accounts already enabled: $AlreadyEnabledCount" -ForegroundColor DarkGreen
    Write-Host "SC accounts deleted:          $DeletedScCount" -ForegroundColor Green
    Write-Host "SC accounts not found:        $ScNotFoundCount" -ForegroundColor Yellow
    Write-Host "No SC account listed:         $ScNotApplicableCount" -ForegroundColor DarkGray
    Write-Host "Rows skipped:                 $SkippedCount" -ForegroundColor Yellow
    Write-Host "Rows failed:                  $FailedCount" -ForegroundColor Red
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
    -CertThumbprint "C47B91EB62634CA61FA8146DDA83B8BF605C0962" `
    -Confirm:$false
#>
