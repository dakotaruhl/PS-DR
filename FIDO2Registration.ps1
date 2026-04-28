Connect-Graph -scopes "UserAuthenticationMethod.ReadWrite.All"

$androidAAGuid = "de1e552d-db1d-4423-a619-566b625cdc84"
$iosAAGuid = "90a3ccdf-635c-4729-a248-9b709135078f"

$authApp = $false
$passKeysFoundCount =0
$passKeysMissingCount = 0
$authAppFoundCount = 0
$authAppMissingCount = 0

$path = "C:\Users\DakotaRuhl\Downloads\exportERockTeamGroupMembers.xlsx"
$users = Import-Excel -Path $path
$results = @()
foreach ($user in $users) 
{
    try 
    {
        $fido2Methods = Get-MgUserAuthenticationFido2Method -UserId $user.id -ErrorAction Stop
        $authMethods = Get-MgUserAuthenticationMethod -UserId $user.id -ErrorAction Stop
        foreach ($method in $fido2Methods) 
        {
            if ($method.aaGuid -eq $androidAAGuid)
            {
                $results += [PSCustomObject]@{
                    UserPrincipalName    = $user.userPrincipalName
                    MethodType           = "Passkey Android"
                    DisplayName          = $method.DisplayName
                    CreatedDateTime      = $method.CreatedDateTime
                    AdditionalProperties = ($method.AdditionalProperties.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join "; "
                }
                $passKeysFoundCount++
            }
            elseif ($method.aaGuid -eq $iosAAGuid) 
            {
                $results += [PSCustomObject]@{
                    UserPrincipalName    = $user.userPrincipalName
                    MethodType           = "Passkey iOS"
                    DisplayName          = $method.DisplayName
                    CreatedDateTime      = $method.CreatedDateTime
                    AdditionalProperties = ($method.AdditionalProperties.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join "; "
                }
                $passKeysFoundCount++
            }
        }
        if ($fido2Methods.Count -eq 0) 
        {
            $passKeysMissingCount++
            foreach ($authMethod in $authMethods)
            {
                if ($authMethod.AdditionalProperties['@odata.type'] -eq '#microsoft.graph.microsoftAuthenticatorAuthenticationMethod') 
                {
                    $results += [PSCustomObject]@{
                        UserPrincipalName = $user.userPrincipalName
                        MethodType        = "Authenticator App"
                        DisplayName       = $authMethod.AdditionalProperties['displayName']
                        CreatedDateTime   = $authMethod.CreatedDateTime
                        AdditionalProperties = ($authMethod.AdditionalProperties.GetEnumerator() |
                                                Where-Object { $_.Key -notin '@odata.type', 'displayName' } | 
                                                ForEach-Object { "$($_.Key)=$($_.Value)" }) -join "; "
                    }
                    $authAppFoundCount++
                    $authApp = $true 
                    break
                }
                elseif($authMethod.AdditionalProperties['@odata.type'] -eq '#microsoft.graph.softwareOathAuthenticationMethod')
                {
                    $results += [PSCustomObject]@{
                        UserPrincipalName = $user.userPrincipalName
                        MethodType        = "Authenticator App (Software OATH)"
                        DisplayName       = $authMethod.AdditionalProperties['displayName']
                        CreatedDateTime   = $authMethod.CreatedDateTime
                        AdditionalProperties = ($authMethod.AdditionalProperties.GetEnumerator() |
                                                Where-Object { $_.Key -notin '@odata.type', 'displayName' } | 
                                                ForEach-Object { "$($_.Key)=$($_.Value)" }) -join "; "
                    }
                    $authAppFoundCount++
                    $authApp = $true 
                    break
                }
            }
            if (-not $authApp) {
                $authAppMissingCount++
                $results += [PSCustomObject]@{
                    UserPrincipalName = $user.userPrincipalName
                    MethodType        = "No Authenticator App!"
                    DisplayName      = $null
                    CreatedDateTime  = $null
                    AdditionalProperties = $null
                }
            }
        }
        $authApp = $false
    }
    catch 
    {
        Write-Warning "Failed to retrieve auth methods for user: $($user.userPrincipalName). Error: $_"
        $results += [PSCustomObject]@{
            UserPrincipalName = $user.userPrincipalName
            MethodType        = "Error"
            DisplayName      = $null
            CreatedDateTime  = $null
            AdditionalProperties = $_.ToString()
        }
    }
}

$resultsPath = "C:\Users\DakotaRuhl\Documents\Reports\FIDO2Results.xlsx"

if(Test-Path -Path $resultsPath) 
{
    Remove-Item -Path $resultsPath -Force
}


$excel = $results | Export-Excel -Path $resultsPath -AutoSize -WorksheetName "FIDO2Results" -PassThru
$sheet = $excel.Workbook.Worksheets["FIDO2Results"]
$lastRow = $sheet.Dimension.End.Row
$lastCol = $sheet.Dimension.End.Column
$fullRange = "A2:E$lastRow"

Add-ConditionalFormatting -WorkSheet $sheet -Range $fullRange -RuleType Expression `
    -ConditionValue '$B2="Passkey Android"' `
    -BackgroundColor ([System.Drawing.Color]::LightGreen) `
    -ForegroundColor ([System.Drawing.Color]::DarkGreen)

Add-ConditionalFormatting -WorkSheet $sheet -Range $fullRange -RuleType Expression `
    -ConditionValue '$B2="Passkey iOS"' `
    -BackgroundColor ([System.Drawing.Color]::LightGreen) `
    -ForegroundColor ([System.Drawing.Color]::DarkGreen)

    
Add-ConditionalFormatting -WorkSheet $sheet -Range $fullRange -RuleType Expression `
    -ConditionValue '$B2="Authenticator App"' `
    -BackgroundColor ([System.Drawing.Color]::AliceBlue) `
    -ForegroundColor ([System.Drawing.Color]::SteelBlue)

Add-ConditionalFormatting -WorkSheet $sheet -Range $fullRange -RuleType Expression `
    -ConditionValue '$B2="No Authenticator App!"' `
    -BackgroundColor ([System.Drawing.Color]::MistyRose) `
    -ForegroundColor ([System.Drawing.Color]::DarkRed)

$sheet.Cells[$sheet.Dimension.Address].Style.HorizontalAlignment = [OfficeOpenXml.Style.ExcelHorizontalAlignment]::Left
$sheet.Cells[$sheet.Dimension.Address].Style.VerticalAlignment   = [OfficeOpenXml.Style.ExcelVerticalAlignment]::Top
Close-ExcelPackage $excel 


$summary = @(
    [PSCustomObject]@{ Metric = "Passkeys Found";   Count = $passKeysFoundCount }
    [PSCustomObject]@{ Metric = "Passkeys Missing"; Count = $passKeysMissingCount }
    [PSCustomObject]@{ Metric = "Auth App Found";   Count = $authAppFoundCount }
    [PSCustomObject]@{ Metric = "Auth App Missing"; Count = $authAppMissingCount }
)

# Summary written after, appends a new sheet to the already-saved file
$summary | Export-Excel -Path $resultsPath -AutoSize -WorksheetName "Summary"

<#
    testing
$methodtest = Get-MgUserAuthenticationFido2Method -UserId 38d611d7-065d-49bc-aa51-4bb3793267fa
$methodtest = Get-MgUserAuthenticationFido2Method -UserId bb50140f-eb59-4e6f-b8be-b7b84fb4c223
$methodtest.count
($method.AdditionalProperties.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join "; "
$method = $null
Get-MgUserAuthenticationMethod -UserId 38d611d7-065d-49bc-aa51-4bb3793267fa | FL
#>
