<#
.SYNOPSIS
    Imports users from an XLSX workbook and updates the Microsoft Entra ID
    officeLocation attribute through Microsoft Graph.

.DESCRIPTION
    The workbook must contain an Email column.

    The workbook may optionally contain an "Office Location" column. If that
    column is present and populated, its value is used for that row. Otherwise,
    the value supplied through -DefaultOfficeLocation is used.

    When the existing officeLocation contains Titan, Hyperion, Stockton, Clifton, or Remote, the requested
    office location is appended instead of replacing the existing value.

    Examples when the requested location is Vine:
        Hyperion       -> Hyperion/Vine
        Titan          -> Titan/Vine
        Stockton       -> Stockton/Vine
        Clifton        -> Clifton/Vine
        Remote         -> Vine/Remote
        Titan/Hyperion -> Titan/Hyperion/Vine
        Stockton/Vine  -> No change required
        Other value    -> Vine

.REQUIREMENTS
    PowerShell modules:
        ImportExcel
        Microsoft.Graph.Authentication
        Microsoft.Graph.Users

    Microsoft Graph application permission:
        User.ReadWrite.All

.EXAMPLE
    .\R-Graph\Set-User-OfficeLocation.ps1 `
        -ExcelPath ".\Input Data\Vine Distribution List.xlsx" `
        -DefaultOfficeLocation "Vine" `
        -WhatIf

.EXAMPLE
    .\R-Graph\Set-User-OfficeLocation.ps1 `
        -ExcelPath ".\Input Data\Vine Distribution List.xlsx" `
        -DefaultOfficeLocation "Vine"
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidateScript({
        if (-not (Test-Path -LiteralPath $_ -PathType Leaf)) {
            throw "The Excel file was not found: $_"
        }

        if ([System.IO.Path]::GetExtension($_) -ne ".xlsx") {
            throw "The input file must have an .xlsx extension."
        }

        $true
    })]
    [string]$ExcelPath,

    [Parameter()]
    [string]$WorksheetName,

    [Parameter()]
    [string]$DefaultOfficeLocation
)

$ErrorActionPreference = "Stop"

# Certificate-based Microsoft Graph authentication using environment variables.
$TenantId = $env:AZURE_TENANT_ID
$ClientId = $env:AZURE_CLIENT_ID
$CertificateThumbprint = $env:AZURE_CLIENT_CERTIFICATE_THUMBPRINT

function Get-CombinedOfficeLocation {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$CurrentOfficeLocation,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$RequestedOfficeLocation
    )

    $CurrentOfficeLocation = $CurrentOfficeLocation.Trim()
    $RequestedOfficeLocation = $RequestedOfficeLocation.Trim()

    if ([string]::IsNullOrWhiteSpace($CurrentOfficeLocation)) {
        return $RequestedOfficeLocation
    }

    $CurrentLocations = @(
        $CurrentOfficeLocation -split "/" |
            ForEach-Object { $_.Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )

    $RequestedLocations = @(
        $RequestedOfficeLocation -split "/" |
            ForEach-Object { $_.Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )

    $ContainsPreservedLocation = @(
        $CurrentLocations | Where-Object {
            $_ -ieq "Titan" -or
            $_ -ieq "Hyperion" -or
            $_ -ieq "Stockton" -or
            $_ -ieq "Clifton" -or
            $_ -ieq "Remote"
        }
    ).Count -gt 0

    if (-not $ContainsPreservedLocation) {
        return ($RequestedLocations -join "/")
    }

    $CombinedLocations = [System.Collections.Generic.List[string]]::new()

    foreach ($Location in $CurrentLocations) {
        if ($CombinedLocations -notcontains $Location) {
            $CombinedLocations.Add($Location)
        }
    }

    foreach ($Location in $RequestedLocations) {
        $LocationAlreadyExists = @(
            $CombinedLocations | Where-Object { $_ -ieq $Location }
        ).Count -gt 0

        if (-not $LocationAlreadyExists) {
            $CombinedLocations.Add($Location)
        }
    }

    # Remote is always placed last so adding Vine to Remote produces Vine/Remote.
    $OrderedLocations = @(
        $CombinedLocations | Where-Object { $_ -ine "Remote" }
    )

    if (@($CombinedLocations | Where-Object { $_ -ieq "Remote" }).Count -gt 0) {
        $OrderedLocations += "Remote"
    }

    return ($OrderedLocations -join "/")
}

# ---------------------------------------------------------------------------
# Validate environment variables
# ---------------------------------------------------------------------------

$RequiredEnvironmentVariables = [ordered]@{
    AZURE_TENANT_ID                    = $TenantId
    AZURE_CLIENT_ID                    = $ClientId
    AZURE_CLIENT_CERTIFICATE_THUMBPRINT = $CertificateThumbprint
}

$MissingEnvironmentVariables = @(
    foreach ($EnvironmentVariable in $RequiredEnvironmentVariables.GetEnumerator()) {
        if ([string]::IsNullOrWhiteSpace([string]$EnvironmentVariable.Value)) {
            $EnvironmentVariable.Key
        }
    }
)

if ($MissingEnvironmentVariables.Count -gt 0) {
    throw "Missing required environment variables: $($MissingEnvironmentVariables -join ', ')"
}

# ---------------------------------------------------------------------------
# Validate and import modules
# ---------------------------------------------------------------------------

$RequiredModules = @(
    "ImportExcel"
    "Microsoft.Graph.Authentication"
    "Microsoft.Graph.Users"
)

foreach ($ModuleName in $RequiredModules) {
    if (-not (Get-Module -ListAvailable -Name $ModuleName)) {
        throw "Required module '$ModuleName' is not installed. Run: Install-Module -Name $ModuleName -Scope CurrentUser"
    }

    Import-Module -Name $ModuleName -ErrorAction Stop
}

# ---------------------------------------------------------------------------
# Import the Excel workbook
# ---------------------------------------------------------------------------

$ResolvedExcelPath = (Resolve-Path -LiteralPath $ExcelPath).Path

$ImportParameters = @{
    Path        = $ResolvedExcelPath
    DataOnly    = $true
    ErrorAction = "Stop"
}

if (-not [string]::IsNullOrWhiteSpace($WorksheetName)) {
    $ImportParameters.WorksheetName = $WorksheetName
}

Write-Host "Reading workbook: $ResolvedExcelPath" -ForegroundColor Cyan

$ImportedRows = @(Import-Excel @ImportParameters)

if ($ImportedRows.Count -eq 0) {
    throw "No data rows were found in the workbook."
}

$ColumnNames = @($ImportedRows[0].PSObject.Properties.Name)

if ($ColumnNames -notcontains "Email") {
    throw "The workbook must contain a column named 'Email'."
}

$HasOfficeLocationColumn = $ColumnNames -contains "Office Location"

if (-not $HasOfficeLocationColumn -and [string]::IsNullOrWhiteSpace($DefaultOfficeLocation)) {
    throw "No office location was provided. Add an 'Office Location' column or use -DefaultOfficeLocation."
}

$UsersToProcess = @(
    $ImportedRows | Where-Object {
        -not [string]::IsNullOrWhiteSpace([string]$_.Email)
    }
)

if ($UsersToProcess.Count -eq 0) {
    throw "No rows containing an Email value were found."
}

$DuplicateEmailAddresses = @(
    $UsersToProcess |
        Group-Object { ([string]$_.Email).Trim().ToLowerInvariant() } |
        Where-Object Count -gt 1
)

if ($DuplicateEmailAddresses.Count -gt 0) {
    $DuplicateList = $DuplicateEmailAddresses.Name -join ", "
    throw "Duplicate email addresses were found in the workbook: $DuplicateList"
}

Write-Host "Rows containing email addresses: $($UsersToProcess.Count)" -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# Connect to Microsoft Graph
# ---------------------------------------------------------------------------

Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Cyan

Connect-MgGraph `
    -TenantId $TenantId `
    -ClientId $ClientId `
    -CertificateThumbprint $CertificateThumbprint `
    -NoWelcome `
    -ErrorAction Stop

if ($null -eq (Get-MgContext)) {
    throw "The Microsoft Graph connection could not be verified."
}

Write-Host "Connected to Microsoft Graph." -ForegroundColor Green

# ---------------------------------------------------------------------------
# Process users
# ---------------------------------------------------------------------------

$Results = [System.Collections.Generic.List[object]]::new()
$ProcessedCount = 0
$TotalRows = $UsersToProcess.Count

foreach ($ExcelRow in $UsersToProcess) {
    $ProcessedCount++
    $ExcelRowNumber = $ProcessedCount + 1
    $EmailAddress = ([string]$ExcelRow.Email).Trim()

    if ($HasOfficeLocationColumn) {
        $RowOfficeLocation = ([string]$ExcelRow.'Office Location').Trim()
    }
    else {
        $RowOfficeLocation = $null
    }

    if (-not [string]::IsNullOrWhiteSpace($RowOfficeLocation)) {
        $RequestedOfficeLocation = $RowOfficeLocation
        $LocationSource = "Excel"
    }
    else {
        $RequestedOfficeLocation = $DefaultOfficeLocation
        $LocationSource = "Default"
    }

    $PercentComplete = [math]::Round(
        ($ProcessedCount / $TotalRows) * 100,
        0
    )

    Write-Progress `
        -Activity "Updating Microsoft Entra office locations" `
        -Status "Processing $EmailAddress" `
        -PercentComplete $PercentComplete

    $Result = [ordered]@{
        ExcelRow                = $ExcelRowNumber
        FirstName               = [string]$ExcelRow.'First Name'
        LastName                = [string]$ExcelRow.'Last Name'
        Email                   = $EmailAddress
        UserPrincipalName       = $null
        DisplayName             = $null
        PreviousOfficeLocation  = $null
        RequestedOfficeLocation = $RequestedOfficeLocation
        FinalOfficeLocation     = $null
        VerifiedOfficeLocation  = $null
        LocationSource          = $LocationSource
        UpdateMode              = $null
        Status                  = $null
        Error                   = $null
    }

    try {
        if ([string]::IsNullOrWhiteSpace($RequestedOfficeLocation)) {
            throw "No office location was provided for this row."
        }

        try {
            $GraphUser = Get-MgUser `
                -UserId $EmailAddress `
                -Property @(
                    "id"
                    "displayName"
                    "userPrincipalName"
                    "mail"
                    "officeLocation"
                    "onPremisesSyncEnabled"
                ) `
                -ErrorAction Stop
        }
        catch {
            $EscapedEmailAddress = $EmailAddress.Replace("'", "''")

            $MatchingUsers = @(
                Get-MgUser `
                    -Filter "mail eq '$EscapedEmailAddress'" `
                    -Property @(
                        "id"
                        "displayName"
                        "userPrincipalName"
                        "mail"
                        "officeLocation"
                        "onPremisesSyncEnabled"
                    ) `
                    -All `
                    -ErrorAction Stop
            )

            if ($MatchingUsers.Count -eq 0) {
                throw "No Microsoft Entra user was found using the UPN or mail address."
            }

            if ($MatchingUsers.Count -gt 1) {
                throw "Multiple Microsoft Entra users matched the mail address."
            }

            $GraphUser = $MatchingUsers[0]
        }

        $CurrentOfficeLocation = ([string]$GraphUser.OfficeLocation).Trim()
        $FinalOfficeLocation = Get-CombinedOfficeLocation `
            -CurrentOfficeLocation $CurrentOfficeLocation `
            -RequestedOfficeLocation $RequestedOfficeLocation

        $ExistingLocationParts = @(
            $CurrentOfficeLocation -split "/" |
                ForEach-Object { $_.Trim() }
        )

        $ContainsPreservedLocation = @(
            $ExistingLocationParts | Where-Object {
                $_ -ieq "Titan" -or
            $_ -ieq "Hyperion" -or
            $_ -ieq "Stockton" -or
            $_ -ieq "Clifton" -or
            $_ -ieq "Remote"
            }
        ).Count -gt 0

        $Result.UserPrincipalName = $GraphUser.UserPrincipalName
        $Result.DisplayName = $GraphUser.DisplayName
        $Result.PreviousOfficeLocation = $CurrentOfficeLocation
        $Result.FinalOfficeLocation = $FinalOfficeLocation
        $Result.UpdateMode = if ($ContainsPreservedLocation) { "Append" } else { "Replace" }

        if ($CurrentOfficeLocation -ieq $FinalOfficeLocation) {
            $Result.Status = "No change required"
            $Result.VerifiedOfficeLocation = $CurrentOfficeLocation

            Write-Host (
                "[SKIPPED] {0} already has office location '{1}'." -f
                $EmailAddress,
                $FinalOfficeLocation
            ) -ForegroundColor DarkGray
        }
        elseif ($PSCmdlet.ShouldProcess(
            $EmailAddress,
            "Set officeLocation from '$CurrentOfficeLocation' to '$FinalOfficeLocation'"
        )) {
            Update-MgUser `
                -UserId $GraphUser.Id `
                -OfficeLocation $FinalOfficeLocation `
                -ErrorAction Stop

            Start-Sleep -Seconds 2
            
            $UpdatedUser = Get-MgUser `
                -UserId $GraphUser.Id `
                -Property @(
                    "id"
                    "officeLocation"
                ) `
                -ErrorAction Stop

            $Result.VerifiedOfficeLocation = $UpdatedUser.OfficeLocation

            if ($UpdatedUser.OfficeLocation -ieq $FinalOfficeLocation) {
                $Result.Status = "Updated and verified"

                Write-Host (
                    "[UPDATED] {0}: '{1}' to '{2}'." -f
                    $EmailAddress,
                    $CurrentOfficeLocation,
                    $FinalOfficeLocation
                ) -ForegroundColor Green
            }
            else {
                $Result.Status = "Verification failed"
                $Result.Error = "Graph returned officeLocation '$($UpdatedUser.OfficeLocation)' after the update."
                Write-Warning "Verification failed for $EmailAddress."
            }
        }
        else {
            $Result.Status = "WhatIf"
            $Result.VerifiedOfficeLocation = $CurrentOfficeLocation
        }
    }
    catch {
        $Result.Status = "Failed"
        $Result.Error = $_.Exception.Message

        Write-Warning (
            "Failed to process row {0}, email {1}. {2}" -f
            $ExcelRowNumber,
            $EmailAddress,
            $_.Exception.Message
        )
    }

    $Results.Add([pscustomobject]$Result)
}

Write-Progress `
    -Activity "Updating Microsoft Entra office locations" `
    -Completed

# ---------------------------------------------------------------------------
# Export results
# ---------------------------------------------------------------------------

$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$InputDirectory = Split-Path -Path $ResolvedExcelPath -Parent
$InputBaseName = [System.IO.Path]::GetFileNameWithoutExtension($ResolvedExcelPath)

$CsvReportPath = Join-Path `
    -Path $InputDirectory `
    -ChildPath "$InputBaseName-OfficeLocationResults-$Timestamp.csv"

$ExcelReportPath = "C:\Users\DakotaRuhl\OneDrive - Enchanted Rock\Reports\Users\$InputBaseName-OfficeLocationResults-$Timestamp.xlsx"
##$ExcelReportPath = Join-Path `
#    -Path $InputDirectory `
#    -ChildPath "$InputBaseName-OfficeLocationResults-$Timestamp.xlsx"

$Results |
    Export-Csv `
        -LiteralPath $CsvReportPath `
        -NoTypeInformation `
        -Encoding UTF8

$Results |
    Export-Excel `
        -Path $ExcelReportPath `
        -WorksheetName "Results" `
        -TableName "OfficeLocationResults" `
        -AutoSize `
        -AutoFilter `
        -FreezeTopRow `
        -BoldTopRow `
        -ClearSheet

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

$UpdatedCount = @(
    $Results | Where-Object Status -eq "Updated and verified"
).Count

$NoChangeCount = @(
    $Results | Where-Object Status -eq "No change required"
).Count

$WhatIfCount = @(
    $Results | Where-Object Status -eq "WhatIf"
).Count

$FailedCount = @(
    $Results | Where-Object {
        $_.Status -in @(
            "Failed"
            "Verification failed"
        )
    }
).Count

Write-Host ""
Write-Host "Processing complete." -ForegroundColor Cyan
Write-Host "Total input rows: $($UsersToProcess.Count)"
Write-Host "Updated and verified: $UpdatedCount" -ForegroundColor Green
Write-Host "No change required: $NoChangeCount" -ForegroundColor Gray
Write-Host "WhatIf preview: $WhatIfCount" -ForegroundColor Yellow
Write-Host "Failed: $FailedCount" -ForegroundColor Red
Write-Host ""
Write-Host "Excel report: $ExcelReportPath" -ForegroundColor Cyan
Write-Host "CSV report:   $CsvReportPath" -ForegroundColor Cyan

Disconnect-MgGraph | Out-Null
