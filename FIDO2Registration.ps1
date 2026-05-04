Connect-Graph -scopes "UserAuthenticationMethod.ReadWrite.All"

$androidAAGuid = "de1e552d-db1d-4423-a619-566b625cdc84"
$iosAAGuid = "90a3ccdf-635c-4729-a248-9b709135078f"

$passKeysFoundCount =0
$passKeysMissingCount = 0
$authAppFoundCount = 0
$authAppFoundOAuthCount = 0
$phoneAuthOnlyCount = 0
$noAuthAppOrPhoneCount = 0
$noAuthMethodsCount = 0

$path = "C:\Users\DakotaRuhl\Downloads\exportERockTeamGroupMembers.xlsx"
$users = Import-Excel -Path $path
$results = @()
foreach ($user in $users) 
{
    try 
    {
        $passkeyRecorded = $false
        $fido2Methods = @(Get-MgUserAuthenticationFido2Method -UserId $user.id -ErrorAction Stop)
        $authMethods = @(Get-MgUserAuthenticationMethod -UserId $user.id -ErrorAction Stop)

        if ($fido2Methods.Count -eq 0) 
        {
            $passKeysMissingCount++
        }
        else 
        {
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
                    $passkeyRecorded = $true
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
                    $passkeyRecorded = $true
                }
            }
            if ($passkeyRecorded) 
            {
                $passKeysFoundCount++
                continue
            }

        }

        # Pull specific methods (first match is fine for classification)
        $authAppMethod = $authMethods | Where-Object {
            $_.AdditionalProperties['@odata.type'] -eq '#microsoft.graph.microsoftAuthenticatorAuthenticationMethod'
            } | Select-Object -First 1

        $oathMethod = $authMethods | Where-Object {
            $_.AdditionalProperties['@odata.type'] -eq '#microsoft.graph.softwareOathAuthenticationMethod'
            } | Select-Object -First 1

        $phoneMethod = $authMethods | Where-Object {
            $_.AdditionalProperties['@odata.type'] -eq '#microsoft.graph.phoneAuthenticationMethod'
            } | Select-Object -First 1

        if ($authMethods.Count -eq 0) 
        {
            $results += [PSCustomObject]@{
                UserPrincipalName       = $user.userPrincipalName
                MethodType              = "No Auth Methods!"
                DisplayName             = $null
                CreatedDateTime         = $null
                AdditionalProperties    = $null
            }
            $noAuthMethodsCount++
        }
        elseif ($authAppMethod) 
        {
            $results += [PSCustomObject]@{
                UserPrincipalName       = $user.userPrincipalName
                MethodType              = "Authenticator App"
                DisplayName             = $authAppMethod.AdditionalProperties['displayName']
                CreatedDateTime         = $authAppMethod.CreatedDateTime
                AdditionalProperties    = ($authAppMethod.AdditionalProperties.GetEnumerator() |
                                        Where-Object { $_.Key -notin '@odata.type', 'displayName' } |
                                        ForEach-Object { "$($_.Key)=$($_.Value)" }) -join "; "
            }
            $authAppFoundCount++
        }
        elseif ($oathMethod) 
        {
            $results += [PSCustomObject]@{
                UserPrincipalName       = $user.userPrincipalName
                MethodType              = "Authenticator App (Software OATH)"
                DisplayName             = $oathMethod.AdditionalProperties['displayName']
                CreatedDateTime         = $oathMethod.CreatedDateTime
                AdditionalProperties    = ($oathMethod.AdditionalProperties.GetEnumerator() |
                                        Where-Object { $_.Key -notin '@odata.type', 'displayName' } |
                                        ForEach-Object { "$($_.Key)=$($_.Value)" }) -join "; "
            }
            $authAppFoundOAuthCount++
        }
        elseif ($phoneMethod) 
        {
            # phone method often doesn't have displayName; use phoneNumber/phoneType
            $results += [PSCustomObject]@{
                UserPrincipalName       = $user.userPrincipalName
                MethodType              = "Phone Auth Only"
                DisplayName             = "$($phoneMethod.AdditionalProperties['phoneType']) $($phoneMethod.AdditionalProperties['phoneNumber'])"
                CreatedDateTime         = $phoneMethod.CreatedDateTime
                AdditionalProperties    = ($phoneMethod.AdditionalProperties.GetEnumerator() |
                                        ForEach-Object { "$($_.Key)=$($_.Value)" }) -join "; "
                }
            $phoneAuthOnlyCount++
        }
        else 
        {
            # They have auth methods, but none of the ones we care about
            $results += [PSCustomObject]@{
                UserPrincipalName       = $user.userPrincipalName
                MethodType              = "No Authenticator App or Phone!"
                DisplayName             = $null
                CreatedDateTime         = $null
                AdditionalProperties    = ($authMethods | ForEach-Object {
                    ($_.AdditionalProperties.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join "; "
                }) -join " | "
            }
            $noAuthAppOrPhoneCount++
        }
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
    -ForegroundColor ([System.Drawing.Color]::DarkBlue)

Add-ConditionalFormatting -WorkSheet $sheet -Range $fullRange -RuleType Expression `
    -ConditionValue '$B2="Authenticator App (Software OATH)"' `
    -BackgroundColor ([System.Drawing.Color]::AliceBlue) `
    -ForegroundColor ([System.Drawing.Color]::DarkBlue)

Add-ConditionalFormatting -WorkSheet $sheet -Range $fullRange -RuleType Expression `
    -ConditionValue '$B2="Phone Auth Only"' `
    -BackgroundColor ([System.Drawing.Color]::LightYellow) `
    -ForegroundColor ([System.Drawing.Color]::DarkGoldenrod)

Add-ConditionalFormatting -WorkSheet $sheet -Range $fullRange -RuleType Expression `
    -ConditionValue '$B2="No Authenticator App or Phone!"' `
    -BackgroundColor ([System.Drawing.Color]::LightCoral) `
    -ForegroundColor ([System.Drawing.Color]::DarkRed)

Add-ConditionalFormatting -WorkSheet $sheet -Range $fullRange -RuleType Expression `
    -ConditionValue '$B2="No Auth Methods!"' `
    -BackgroundColor ([System.Drawing.Color]::MistyRose) `
    -ForegroundColor ([System.Drawing.Color]::DarkRed)

$sheet.Cells[$sheet.Dimension.Address].Style.HorizontalAlignment = [OfficeOpenXml.Style.ExcelHorizontalAlignment]::Left
$sheet.Cells[$sheet.Dimension.Address].Style.VerticalAlignment   = [OfficeOpenXml.Style.ExcelVerticalAlignment]::Top
Close-ExcelPackage $excel 


$summary = @(
    [PSCustomObject]@{ Metric = "Passkeys Found";   Count = $passKeysFoundCount }
    [PSCustomObject]@{ Metric = "Passkeys Missing"; Count = $passKeysMissingCount }
    [PSCustomObject]@{ Metric = "Auth App Found";   Count = $authAppFoundCount }
    [PSCustomObject]@{ Metric = "Auth App Found (Software OATH)";   Count = $authAppFoundOAuthCount }
    [PSCustomObject]@{ Metric = "Phone Auth Only"; Count = $phoneAuthOnlyCount }
    [PSCustomObject]@{ Metric = "No Authenticator App or Phone!"; Count = $noAuthAppOrPhoneCount }
    [PSCustomObject]@{ Metric = "No Auth Methods!"; Count = $noAuthMethodsCount }

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
