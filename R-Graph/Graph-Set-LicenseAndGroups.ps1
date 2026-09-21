function Invoke-FTEProvisioning {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory)]
        [string]$ExcelPath,

        [string]$WorksheetName,

        [Parameter(Mandatory)]
        [string]$TenantId,

        [Parameter(Mandatory)]
        [string]$ClientId,

        [Parameter(Mandatory)]
        [string]$CertThumbprint,

        [string]$DefaultUsageLocation = 'US'
    )

    $RequiredModules = @(
        'ImportExcel',
        'Microsoft.Graph.Authentication',
        'Microsoft.Graph.Users',
        'Microsoft.Graph.Users.Actions',
        'Microsoft.Graph.Groups',
        'Microsoft.Graph.Identity.DirectoryManagement'
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

    if ([string]::IsNullOrWhiteSpace($WorksheetName)) {
        $Rows = @(Import-Excel -Path $ExcelPath -ErrorAction Stop)
    }
    else {
        $Rows = @(
            Import-Excel `
                -Path $ExcelPath `
                -WorksheetName $WorksheetName `
                -ErrorAction Stop
        )
    }

    if ($Rows.Count -eq 0) {
        throw 'No data rows were found in the worksheet.'
    }

    $RequiredColumns = @(
        'DisplayName',
        'UPN',
        'Group Assignments',
        'Groups Complete',
        'License',
        'License Complete'
    )

    $AvailableColumns = @($Rows[0].PSObject.Properties.Name)
    $MissingColumns = @(
        $RequiredColumns |
            Where-Object { $_ -notin $AvailableColumns }
    )

    if ($MissingColumns.Count -gt 0) {
        throw "Missing required column(s): $($MissingColumns -join ', ')"
    }

    # Friendly workbook values mapped to exact tenant SkuPartNumber values.
    $LicenseMap = @{
        'Microsoft 365 E5'                    = @('SPE_E5')
        'Microsoft 365 Business Premium'      = @('SPB')
        'Defender Suite for Business Premium' = @('DEFENDER_SUITE_FOR_BUSINESS_PREMIUM_NEW')
    }

    $SubscribedSkus = @(Get-MgSubscribedSku -All -ErrorAction Stop)
    $SkuLookup = @{}

    foreach ($Sku in $SubscribedSkus) {
        $SkuLookup[$Sku.SkuPartNumber] = $Sku
    }

    foreach ($Row in $Rows) {
        $UPN = ([string]$Row.UPN).Trim()

        if ([string]::IsNullOrWhiteSpace($UPN)) {
            Write-Warning 'Skipping row because UPN is blank.'
            continue
        }

        Write-Host ''
        Write-Host '==================================================' -ForegroundColor DarkGray
        Write-Host "Processing: $($Row.DisplayName) <$UPN>" -ForegroundColor Cyan
        Write-Host '==================================================' -ForegroundColor DarkGray

        try {
            try {
                $User = Get-MgUser `
                    -UserId $UPN `
                    -Property Id,DisplayName,UserPrincipalName,UsageLocation,AssignedLicenses `
                    -ErrorAction Stop
            }
            catch {
                Write-Warning "User '$UPN' was not found: $($_.Exception.Message)"
                continue
            }

            # ----------------------------------------------------
            # License assignment
            # ----------------------------------------------------
            $LicenseComplete =
                ([string]$Row.'License Complete').Trim() -ieq 'TRUE'

            if (-not $LicenseComplete) {
                $LicenseCell = ([string]$Row.License).Trim()

                if (
                    -not [string]::IsNullOrWhiteSpace($LicenseCell) -and
                    $LicenseCell -ine 'N/A'
                ) {
                    $FriendlyLicenseNames = @(
                        $LicenseCell -split ',' |
                            ForEach-Object { $_.Trim() } |
                            Where-Object {
                                -not [string]::IsNullOrWhiteSpace($_)
                            }
                    )

                    $RequestedSkuPartNumbers = @()

                    foreach ($FriendlyName in $FriendlyLicenseNames) {
                        if (-not $LicenseMap.ContainsKey($FriendlyName)) {
                            Write-Warning "No SKU mapping exists for '$FriendlyName'."
                            continue
                        }

                        $RequestedSkuPartNumbers += $LicenseMap[$FriendlyName]
                    }

                    $RequestedSkuPartNumbers = @(
                        $RequestedSkuPartNumbers |
                            Select-Object -Unique
                    )

                    if (
                        $RequestedSkuPartNumbers.Count -gt 0 -and
                        [string]::IsNullOrWhiteSpace($User.UsageLocation)
                    ) {
                        if (
                            $PSCmdlet.ShouldProcess(
                                $UPN,
                                "Set UsageLocation to $DefaultUsageLocation"
                            )
                        ) {
                            Update-MgUser `
                                -UserId $User.Id `
                                -UsageLocation $DefaultUsageLocation `
                                -ErrorAction Stop

                            Write-Host `
                                "Set UsageLocation: $DefaultUsageLocation" `
                                -ForegroundColor Green
                        }
                    }

                    $CurrentSkuIds = @(
                        $User.AssignedLicenses |
                            ForEach-Object { $_.SkuId.ToString() }
                    )

                    $LicensesToAdd = @()
                    $SkuNamesToAdd = @()

                    foreach ($SkuPartNumber in $RequestedSkuPartNumbers) {
                        if (-not $SkuLookup.ContainsKey($SkuPartNumber)) {
                            Write-Warning "Tenant SKU not found: $SkuPartNumber"
                            continue
                        }

                        $Sku = $SkuLookup[$SkuPartNumber]

                        if ($CurrentSkuIds -contains $Sku.SkuId.ToString()) {
                            Write-Host `
                                "Already licensed: $SkuPartNumber" `
                                -ForegroundColor DarkGreen
                            continue
                        }

                        $Enabled = [int]$Sku.PrepaidUnits.Enabled
                        $Consumed = [int]$Sku.ConsumedUnits
                        $Available = $Enabled - $Consumed

                        if ($Available -le 0) {
                            Write-Warning `
                                "No available seats for $SkuPartNumber. Enabled=$Enabled, Consumed=$Consumed."
                            continue
                        }

                        $LicensesToAdd += @{
                            SkuId = $Sku.SkuId
                        }

                        $SkuNamesToAdd += $SkuPartNumber
                    }

                    if ($LicensesToAdd.Count -gt 0) {
                        if (
                            $PSCmdlet.ShouldProcess(
                                $UPN,
                                "Assign licenses: $($SkuNamesToAdd -join ', ')"
                            )
                        ) {
                            Set-MgUserLicense `
                                -UserId $User.Id `
                                -AddLicenses $LicensesToAdd `
                                -RemoveLicenses @() `
                                -ErrorAction Stop | Out-Null

                            Write-Host `
                                "Assigned licenses: $($SkuNamesToAdd -join ', ')" `
                                -ForegroundColor Green
                        }
                    }
                    else {
                        Write-Host `
                            'No license changes required.' `
                            -ForegroundColor DarkGreen
                    }
                }
                else {
                    Write-Host `
                        'No license assignment requested.' `
                        -ForegroundColor DarkGray
                }
            }
            else {
                Write-Host `
                    'License Complete = TRUE. Skipping licenses.' `
                    -ForegroundColor DarkGray
            }

            # ----------------------------------------------------
            # Group assignment
            # ----------------------------------------------------
            $GroupsComplete =
                ([string]$Row.'Groups Complete').Trim() -ieq 'TRUE'

            if (-not $GroupsComplete) {
                $GroupCell = ([string]$Row.'Group Assignments').Trim()

                if (
                    -not [string]::IsNullOrWhiteSpace($GroupCell) -and
                    $GroupCell -ine 'N/A'
                ) {
                    # Use semicolons between multiple group names.
                    $GroupNames = @(
                        $GroupCell -split ';' |
                            ForEach-Object { $_.Trim() } |
                            Where-Object {
                                -not [string]::IsNullOrWhiteSpace($_)
                            }
                    )

                    foreach ($GroupName in $GroupNames) {
                        Write-Host `
                            "Checking group: $GroupName" `
                            -ForegroundColor Yellow

                        $EscapedGroupName = $GroupName.Replace("'", "''")

                        $MatchingGroups = @(
                            Get-MgGroup `
                                -Filter "displayName eq '$EscapedGroupName'" `
                                -Property Id,DisplayName,GroupTypes `
                                -All `
                                -ErrorAction Stop
                        )

                        if ($MatchingGroups.Count -eq 0) {
                            Write-Warning "Group not found: $GroupName"
                            continue
                        }

                        if ($MatchingGroups.Count -gt 1) {
                            Write-Warning `
                                "Multiple groups named '$GroupName' were found. Skipping for safety."
                            continue
                        }

                        $Group = $MatchingGroups[0]

                        if ($Group.GroupTypes -contains 'DynamicMembership') {
                            Write-Warning `
                                "Dynamic group '$GroupName' cannot be directly updated."
                            continue
                        }

                        # Use checkMemberGroups instead of relying on a 404 response
                        # from a direct group-member reference request.
                        try {
                            $MembershipResult = @(
                                Confirm-MgUserMemberGroup `
                                    -UserId $User.Id `
                                    -GroupIds @($Group.Id) `
                                    -ErrorAction Stop
                            )

                            $AlreadyMember =
                                $MembershipResult -contains $Group.Id
                        }
                        catch {
                            throw `
                                "Failed to check membership in group '$GroupName': $($_.Exception.Message)"
                        }

                        if ($AlreadyMember) {
                            Write-Host `
                                "Already member: $GroupName" `
                                -ForegroundColor DarkGreen
                            continue
                        }

                        if (
                            $PSCmdlet.ShouldProcess(
                                $UPN,
                                "Add to group '$GroupName'"
                            )
                        ) {
                            $Body = @{
                                '@odata.id' =
                                    "https://graph.microsoft.com/v1.0/directoryObjects/$($User.Id)"
                            }

                            New-MgGroupMemberByRef `
                                -GroupId $Group.Id `
                                -BodyParameter $Body `
                                -ErrorAction Stop

                            Write-Host `
                                "Added to group: $GroupName" `
                                -ForegroundColor Green
                        }
                    }
                }
                else {
                    Write-Host `
                        'No group assignment requested.' `
                        -ForegroundColor DarkGray
                }
            }
            else {
                Write-Host `
                    'Groups Complete = TRUE. Skipping groups.' `
                    -ForegroundColor DarkGray
            }
        }
        catch {
            Write-Error "Failed processing '$UPN': $($_.Exception.Message)"
        }
    }

    Write-Host ''
    Write-Host 'Processing complete.' -ForegroundColor Green
}

# Example dry run:
<# 
Invoke-FTEProvisioning `
    -ExcelPath 'C:\Users\DakotaRuhl\Documents\PS-DR\Input Data\Aerotek FTE.xlsx' `
    -WorksheetName 'Results' `
    -TenantId "0bdf0e1f-a359-4b5c-9b79-9357e35ff8c6" `
    -ClientId "ea2ca49b-d0df-4774-b611-86cf9dc9629f" `
    -CertThumbprint "C47B91EB62634CA61FA8146DDA83B8BF605C0962"
#>
