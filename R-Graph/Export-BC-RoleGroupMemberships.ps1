#requires -Version 7.0
<#
.SYNOPSIS
Exports owners and direct user members of Entra security groups whose display name starts with BC-ROLE.

.REQUIREMENTS
- Microsoft.Graph.Authentication
- Microsoft.Graph.Groups
- ImportExcel
- The script requires an Azure AD app registration with certificate-based authentication.
- Environment variables:
  AZURE_CLIENT_ID
  AZURE_TENANT_ID
  AZURE_CLIENT_CERTIFICATE_THUMBPRINT

.EXAMPLE
    .\R-Graph\Export-BC-RoleGroupMemberships.ps1

    .\R-Graph\Export-BC-RoleGroupMemberships.ps1 `
        -GroupDisplayNamePrefix 'BC-ROLE' `
        -OutputDirectory '.\output'
#>

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$GroupDisplayNamePrefix = 'BC-ROLE',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$OutputDirectory = '.\output'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$runStart = Get-Date
$fileTimestamp = $runStart.ToString('yyyy-MM-dd_HH-mm-ss')
$displayTimestamp = $runStart.ToString('MM/dd/yyyy hh:mm:ss tt zzz')

if (-not (Test-Path -LiteralPath $OutputDirectory)) {
    $null = New-Item -Path $OutputDirectory -ItemType Directory -Force
}

$resolvedOutputDirectory = (Resolve-Path -LiteralPath $OutputDirectory).Path
$exportPath = Join-Path $resolvedOutputDirectory "SecGroup_Memberships_$fileTimestamp.xlsx"
$transcriptPath = Join-Path $resolvedOutputDirectory "SecGroup_Memberships_$fileTimestamp.log"

$transcriptStarted = $false
$graphConnected = $false
$excelPackage = $null

try {
    Start-Transcript -Path $transcriptPath -Force | Out-Null
    $transcriptStarted = $true

    Write-Host "Run started: $displayTimestamp"
    Write-Host "Excel output: $exportPath"
    Write-Host "Transcript: $transcriptPath"

    $requiredModules = @(
        'Microsoft.Graph.Authentication',
        'Microsoft.Graph.Groups',
        'ImportExcel'
    )

    foreach ($moduleName in $requiredModules) {
        if (-not (Get-Module -ListAvailable -Name $moduleName)) {
            throw "Required module '$moduleName' is not installed. Install it with: Install-Module $moduleName -Scope CurrentUser"
        }
        Import-Module $moduleName -ErrorAction Stop
    }

    $requiredEnvironmentVariables = @(
        'AZURE_CLIENT_ID',
        'AZURE_TENANT_ID',
        'AZURE_CLIENT_CERTIFICATE_THUMBPRINT'
    )

    foreach ($variableName in $requiredEnvironmentVariables) {
        $variableValue = [Environment]::GetEnvironmentVariable($variableName)
        if ([string]::IsNullOrWhiteSpace($variableValue)) {
            throw "Required environment variable '$variableName' is not set."
        }
    }

    Connect-MgGraph `
        -ClientId $env:AZURE_CLIENT_ID `
        -TenantId $env:AZURE_TENANT_ID `
        -CertificateThumbprint $env:AZURE_CLIENT_CERTIFICATE_THUMBPRINT `
        -ContextScope Process `
        -NoWelcome

    $graphConnected = $true

    $escapedPrefix = $GroupDisplayNamePrefix.Replace("'", "''")
    $groupFilter = "securityEnabled eq true and startsWith(displayName,'$escapedPrefix')"

    Write-Host "Finding security groups whose display name begins with '$GroupDisplayNamePrefix'..."

    $groups = @(
        Get-MgGroup `
            -Filter $groupFilter `
            -ConsistencyLevel eventual `
            -All `
            -Property Id,DisplayName,SecurityEnabled |
        Sort-Object DisplayName
    )

    if ($groups.Count -eq 0) {
        throw "No security groups were found with a display name beginning with '$GroupDisplayNamePrefix'."
    }

    Write-Host "Found $($groups.Count) matching security groups."

    if (Test-Path -LiteralPath $exportPath) {
        Remove-Item -LiteralPath $exportPath -Force
    }

    # Build the workbook through one open Excel package. 
    $excelPackage = Open-ExcelPackage -Path $exportPath -Create
    $worksheet = $excelPackage.Workbook.Worksheets.Add('Security Group Memberships')

    $currentRow = 1
    $groupNumber = 0
    $errorRecords = [System.Collections.Generic.List[object]]::new()

    foreach ($group in $groups) {
        $groupNumber++
        Write-Host "[$groupNumber/$($groups.Count)] Processing $($group.DisplayName)"

        try {
            $owners = @(
                Get-MgGroupOwnerAsUser `
                    -GroupId $group.Id `
                    -All `
                    -Property Id,DisplayName,UserPrincipalName
            )

            $members = @(
                Get-MgGroupMemberAsUser `
                    -GroupId $group.Id `
                    -All `
                    -Property Id,DisplayName,UserPrincipalName
            )

            $rows = [System.Collections.Generic.List[object]]::new()

            foreach ($owner in ($owners | Sort-Object DisplayName, UserPrincipalName)) {
                $rows.Add([PSCustomObject][ordered]@{
                    'Display Name'    = $owner.DisplayName
                    'UPN'             = $owner.UserPrincipalName
                    'Membership Type' = 'Owner'
                })
            }

            foreach ($member in ($members | Sort-Object DisplayName, UserPrincipalName)) {
                $rows.Add([PSCustomObject][ordered]@{
                    'Display Name'    = $member.DisplayName
                    'UPN'             = $member.UserPrincipalName
                    'Membership Type' = 'Member'
                })
            }

            if ($rows.Count -eq 0) {
                $rows.Add([PSCustomObject][ordered]@{
                    'Display Name'    = '(No user owners or direct user members found)'
                    'UPN'             = $null
                    'Membership Type' = $null
                })
            }

            # Group title
            $worksheet.Cells[$currentRow, 1].Value = $group.DisplayName
            $worksheet.Cells[$currentRow, 1, $currentRow, 3].Merge = $true
            $worksheet.Cells[$currentRow, 1, $currentRow, 3].Style.Font.Bold = $true
            $worksheet.Cells[$currentRow, 1, $currentRow, 3].Style.Font.Size = 12
            $worksheet.Cells[$currentRow, 1, $currentRow, 3].Style.Fill.PatternType = 'Solid'
            $worksheet.Cells[$currentRow, 1, $currentRow, 3].Style.Fill.BackgroundColor.SetColor([System.Drawing.Color]::FromArgb(31, 78, 121))
            $worksheet.Cells[$currentRow, 1, $currentRow, 3].Style.Font.Color.SetColor([System.Drawing.Color]::White)

            $headerRow = $currentRow + 1
            $dataStartRow = $headerRow + 1
            $dataEndRow = $dataStartRow + $rows.Count - 1

            $worksheet.Cells[$headerRow, 1].Value = 'Display Name'
            $worksheet.Cells[$headerRow, 2].Value = 'UPN'
            $worksheet.Cells[$headerRow, 3].Value = 'Membership Type'

            $rowIndex = $dataStartRow
            foreach ($row in $rows) {
                $worksheet.Cells[$rowIndex, 1].Value = $row.'Display Name'
                $worksheet.Cells[$rowIndex, 2].Value = $row.UPN
                $worksheet.Cells[$rowIndex, 3].Value = $row.'Membership Type'
                $rowIndex++
            }

            $tableRange = $worksheet.Cells[$headerRow, 1, $dataEndRow, 3]
            Add-ExcelTable `
                -Range $tableRange `
                -TableName ('BCROLE_{0:D3}' -f $groupNumber) `
                -TableStyle Medium2 `
                -ShowHeader `
                -ShowFilter `
                -ShowRowStripes | Out-Null

            # Title + header + data + one empty separator row.
            $currentRow = $dataEndRow + 2
        }
        catch {
            $errorMessage = $_.Exception.Message
            Write-Warning "Failed to process '$($group.DisplayName)': $errorMessage"

            $errorRecords.Add([PSCustomObject][ordered]@{
                'Group Display Name' = $group.DisplayName
                'Group Object ID'    = $group.Id
                'Error'              = $errorMessage
            })
        }
    }

    if ($worksheet.Dimension) {
        $worksheet.Cells[$worksheet.Dimension.Address].AutoFitColumns()
        $worksheet.Column(1).Width = [Math]::Min([Math]::Max($worksheet.Column(1).Width, 25), 55)
        $worksheet.Column(2).Width = [Math]::Min([Math]::Max($worksheet.Column(2).Width, 30), 60)
        $worksheet.Column(3).Width = [Math]::Min([Math]::Max($worksheet.Column(3).Width, 18), 25)
    }

    if ($errorRecords.Count -gt 0) {
        $errorWorksheet = $excelPackage.Workbook.Worksheets.Add('Errors')
        $errorWorksheet.Cells[1, 1].Value = 'Group Display Name'
        $errorWorksheet.Cells[1, 2].Value = 'Group Object ID'
        $errorWorksheet.Cells[1, 3].Value = 'Error'

        $errorRow = 2
        foreach ($errorRecord in $errorRecords) {
            $errorWorksheet.Cells[$errorRow, 1].Value = $errorRecord.'Group Display Name'
            $errorWorksheet.Cells[$errorRow, 2].Value = $errorRecord.'Group Object ID'
            $errorWorksheet.Cells[$errorRow, 3].Value = $errorRecord.Error
            $errorRow++
        }

        $errorRange = $errorWorksheet.Cells[1, 1, $errorRow - 1, 3]
        Add-ExcelTable `
            -Range $errorRange `
            -TableName 'ExportErrors' `
            -TableStyle Medium6 `
            -ShowHeader `
            -ShowFilter `
            -ShowRowStripes | Out-Null

        $errorWorksheet.Cells[$errorWorksheet.Dimension.Address].AutoFitColumns()
        $errorWorksheet.View.FreezePanes(2, 1)
    }

    Close-ExcelPackage -ExcelPackage $excelPackage
    $excelPackage = $null

    Write-Host 'Export complete.'
    Write-Host "Groups found: $($groups.Count)"
    Write-Host "Groups with errors: $($errorRecords.Count)"
    Write-Host "Excel output: $exportPath"
}
catch {
    Write-Error $_
    throw
}
finally {
    if ($null -ne $excelPackage) {
        try {
            Close-ExcelPackage -ExcelPackage $excelPackage -NoSave
        }
        catch {
            Write-Warning "Could not close the Excel package cleanly: $($_.Exception.Message)"
        }
    }

    if ($graphConnected) {
        Disconnect-MgGraph | Out-Null
    }

    if ($transcriptStarted) {
        Stop-Transcript | Out-Null
    }
}
