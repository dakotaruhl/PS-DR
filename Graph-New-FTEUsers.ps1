#requires -Modules Microsoft.Graph.Authentication, Microsoft.Graph.Users, ImportExcel

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$Thumbprint = "C47B91EB62634CA61FA8146DDA83B8BF605C0962"
$ClientId   = "ea2ca49b-d0df-4774-b611-86cf9dc9629f"
$TenantId   = "0bdf0e1f-a359-4b5c-9b79-9357e35ff8c6"

$InputPath  = ".\Input Data\UserList.xlsx"
$ReportPath = ".\UserCreationResults_{0}.xlsx" -f (Get-Date -Format "yyyyMMdd_HHmmss")

function Get-TrimmedValue {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Value) {
        return ""
    }

    return $Value.ToString().Trim()
}

function ConvertTo-EmployeeHireDate {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace($Value.ToString())) {
        return $null
    }

    if ($Value -is [datetime]) {
        return [datetime]$Value
    }

    # Handle an Excel serial date.
    $excelSerial = 0.0

    if ([double]::TryParse(
            $Value.ToString(),
            [System.Globalization.NumberStyles]::Any,
            [System.Globalization.CultureInfo]::InvariantCulture,
            [ref]$excelSerial
        )) {

        try {
            return [datetime]::FromOADate($excelSerial)
        }
        catch {
            throw "Hire date '$Value' is not a valid Excel serial date."
        }
    }

    $parsedDate = [datetime]::MinValue

    if ([datetime]::TryParse(
            $Value.ToString(),
            [System.Globalization.CultureInfo]::GetCultureInfo("en-US"),
            [System.Globalization.DateTimeStyles]::AssumeLocal,
            [ref]$parsedDate
        )) {
        return $parsedDate
    }

    throw "Hire date '$Value' is not a recognized date."
}

# Validate the input file.
if (-not (Test-Path -LiteralPath $InputPath)) {
    throw "Input file was not found: $InputPath"
}

# Validate and establish the intended Graph connection.
$graphContext = Get-MgContext -ErrorAction SilentlyContinue

$connectionMatches = (
    $null -ne $graphContext -and
    $graphContext.TenantId -eq $TenantId -and
    $graphContext.ClientId -eq $ClientId -and
    $graphContext.AuthType -eq "AppOnly"
)

if (-not $connectionMatches) {
    if ($graphContext) {
        Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
    }

    Connect-MgGraph `
        -ClientId $ClientId `
        -TenantId $TenantId `
        -CertificateThumbprint $Thumbprint `
        -NoWelcome
}

$graphContext = Get-MgContext

if (
    $graphContext.TenantId -ne $TenantId -or
    $graphContext.ClientId -ne $ClientId -or
    $graphContext.AuthType -ne "AppOnly"
) {
    throw "Microsoft Graph connected with an unexpected tenant, client, or authentication type."
}

Write-Host "Connected to Microsoft Graph using application authentication." `
    -ForegroundColor Green

# Validate the input Excel file for required columns.

$userList = @(Import-Excel -Path $InputPath)

if ($userList.Count -eq 0) {
    throw "The input workbook contains no user rows."
}
$requiredColumns = @(
    "displayName"
    "UPN"
    "mailnickname"
    "givenName"
    "surname"
    "usageLocation"
    "Password"
)

$availableColumns = @(
    $userList[0].PSObject.Properties.Name
)

$missingColumns = @(
    $requiredColumns |
        Where-Object { $_ -notin $availableColumns }
)

if ($missingColumns.Count -gt 0) {
    throw "The workbook is missing required column(s): $($missingColumns -join ', ')."
}

# main loop 
$results = [System.Collections.Generic.List[object]]::new()

$rowNumber = 1

foreach ($user in $userList) {
    $rowNumber++

    $displayName   = Get-TrimmedValue $user.displayName
    $upn           = Get-TrimmedValue $user.UPN
    $mailNickname  = Get-TrimmedValue $user.mailnickname
    $givenName     = Get-TrimmedValue $user.givenName
    $surname       = Get-TrimmedValue $user.surname
    $department    = Get-TrimmedValue $user.department
    $employeeType  = Get-TrimmedValue $user.employeeType
    $companyName   = Get-TrimmedValue $user.companyName
    $usageLocation = (Get-TrimmedValue $user.usageLocation).ToUpperInvariant()
    $jobTitle      = Get-TrimmedValue $user.jobTitle
    $employeeId    = Get-TrimmedValue $user.employeeId
    $userPassword  = Get-TrimmedValue $user.Password

    $result = [ordered]@{
        RowNumber      = $rowNumber
        DisplayName    = $displayName
        UPN            = $upn
        EmployeeId     = $employeeId
        Action         = ""
        Status         = ""
        UserId         = ""
        EmployeeHireDate = ""
        Error          = ""
        ProcessedAt    = Get-Date
    }

    try {
        # Validate required spreadsheet values.
        $missingFields = [System.Collections.Generic.List[string]]::new()

        if ([string]::IsNullOrWhiteSpace($displayName)) {
            $missingFields.Add("displayName")
        }

        if ([string]::IsNullOrWhiteSpace($upn)) {
            $missingFields.Add("UPN")
        }

        if ([string]::IsNullOrWhiteSpace($mailNickname)) {
            $missingFields.Add("mailnickname")
        }

        if ([string]::IsNullOrWhiteSpace($givenName)) {
            $missingFields.Add("givenName")
        }

        if ([string]::IsNullOrWhiteSpace($surname)) {
            $missingFields.Add("surname")
        }

        if ([string]::IsNullOrWhiteSpace($usageLocation)) {
            $missingFields.Add("usageLocation")
        }

        if ([string]::IsNullOrWhiteSpace($userPassword)) {
            $missingFields.Add("Password")
        }

        if ($missingFields.Count -gt 0) {
            throw "Missing required field(s): $($missingFields -join ', ')."
        }

        if ($upn -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') {
            throw "UPN is not in a valid email-style format: $upn"
        }

        if ($usageLocation -notmatch '^[A-Z]{2}$') {
            throw "UsageLocation must be a two-letter country code, such as US."
        }

        $employeeHireDate = ConvertTo-EmployeeHireDate $user.hireDate

        if ($employeeHireDate) {
            $result.EmployeeHireDate = $employeeHireDate.ToString("yyyy-MM-dd")
        }

        # Check whether the user exists.
        # Request_ResourceNotFound is expected when the UPN is available.
        $existingUser = $null
        try {
            $existingUser = Get-MgUser `
                -UserId $upn `
                -Property Id,DisplayName,UserPrincipalName,EmployeeHireDate `
                -ErrorAction Stop
        }
        catch {
            $lookupError = $_

            $graphErrorCode = $null
            $codeProperty = $lookupError.Exception.PSObject.Properties["Code"]

            if ($codeProperty -and $codeProperty.Value) {
                $graphErrorCode = $codeProperty.Value.ToString()
            }

            $fullyQualifiedErrorId = $lookupError.FullyQualifiedErrorId.ToString()

            $userWasNotFound = (
                $graphErrorCode -eq "Request_ResourceNotFound" -or
                $fullyQualifiedErrorId -like "Request_ResourceNotFound*"
            )

            if ($userWasNotFound) {
                $existingUser = $null

                Write-Host "User does not exist and will be created: $upn" `
                    -ForegroundColor DarkGray
            }
            else {
                throw
            }
        }

        if ($existingUser) {
            $result.Action = "Skipped"
            $result.Status = "Already exists"
            $result.UserId = $existingUser.Id

            Write-Host "User already exists: $displayName ($upn). Skipping creation." `
                -ForegroundColor Yellow

            # Intentionally do not update existing users from this creation script.
            $results.Add([pscustomobject]$result)
            continue
        }

        $passwordProfile = @{
            Password                      = $userPassword
            ForceChangePasswordNextSignIn = $true
        }

        $accountEnabled = $true
        if (
            $null -ne $employeeHireDate -and
            $employeeHireDate.Date -gt (Get-Date).Date
        ) {
            $accountEnabled = $false
        }

        $newUserParameters = @{
            DisplayName       = $displayName
            MailNickname      = $mailNickname
            UserPrincipalName = $upn
            AccountEnabled    = $accountEnabled
            GivenName         = $givenName
            Surname           = $surname
            UsageLocation     = $usageLocation
            PasswordProfile   = $passwordProfile
        }

        # Only send optional properties when values are present.
        if ($department) {
            $newUserParameters.Department = $department
        }

        if ($employeeType) {
            $newUserParameters.EmployeeType = $employeeType
        }

        if ($companyName) {
            $newUserParameters.CompanyName = $companyName
        }

        if ($jobTitle) {
            $newUserParameters.JobTitle = $jobTitle
        }

        if ($employeeId) {
            $newUserParameters.EmployeeId = $employeeId
        }

        if ($employeeHireDate) {
            $newUserParameters.EmployeeHireDate = $employeeHireDate
        }

        Write-Host "Creating user: $displayName ($upn)" -ForegroundColor Cyan

        $createdUser = New-MgUser @newUserParameters -ErrorAction Stop

        $result.Action = "Created"
        $result.Status = "Success"
        $result.UserId = $createdUser.Id

        Write-Host "Created user: $displayName ($upn)" -ForegroundColor Green
    }
    catch {
        $caughtError = $_

        $result.Action = if ($result.Action) {
            $result.Action
        }
        else {
            "Create"
        }

        $result.Status = "Failed"

        $errorCodeProperty = $caughtError.Exception.PSObject.Properties["Code"]

        if ($errorCodeProperty -and $errorCodeProperty.Value) {
            $errorCode = $errorCodeProperty.Value.ToString()
        }
        elseif ($caughtError.FullyQualifiedErrorId) {
            $errorCode = $caughtError.FullyQualifiedErrorId.ToString().Split(",")[0]
        }
        else {
            $errorCode = "UnknownError"
        }

        $errorMessage = $caughtError.Exception.Message
        $result.Error = "[$errorCode] $errorMessage"

        Write-Host "Failed to process $displayName ($upn): $($result.Error)" `
            -ForegroundColor Red
    }

    $results.Add([pscustomobject]$result)
}

$results |
    Export-Excel `
        -Path $ReportPath `
        -WorksheetName "Results" `
        -AutoSize `
        -AutoFilter `
        -FreezeTopRow `
        -BoldTopRow

$createdCount = @($results | Where-Object Status -eq "Success").Count
$skippedCount = @($results | Where-Object Status -eq "Already exists").Count
$failedCount  = @($results | Where-Object Status -eq "Failed").Count

Write-Host ""
Write-Host "Processing complete." -ForegroundColor Green
Write-Host "Created: $createdCount"
Write-Host "Skipped: $skippedCount"
Write-Host "Failed: $failedCount"
Write-Host "Report: $ReportPath"