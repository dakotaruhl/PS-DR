#Requires -Modules Microsoft.Graph.Authentication, Microsoft.Graph.Groups, Microsoft.Graph.Identity.SignIns

<#
.SYNOPSIS
    Classifies erockteam members by auth method and syncs them into
    conditional access security groups. Intended to run daily.

.DESCRIPTION
    1. Pulls members from erockteam@enchantedrock.com via Graph
    2. Checks each user's registered authentication methods
    3. Sorts each user into exactly one target group:
         MFA-FIDO2-Complete          - FIDO2 passkey registered (highest priority)
         MFA-AuthApp-Complete        - Authenticator push or Software OATH
         MFA-Registration-Required   - Everything else (phone only, none, errors)
    4. Syncs memberships (adds + removes) so groups stay current each run
    5. Exports audit report to Excel

.NOTES
    Required Graph application permissions:
      UserAuthenticationMethod.Read.All
      GroupMember.ReadWrite.All
      Group.Read.All
#>

$Thumbprint = "C47B91EB62634CA61FA8146DDA83B8BF605C0962"
$ClientID = "ea2ca49b-d0df-4774-b611-86cf9dc9629f"
$TenantID = "0bdf0e1f-a359-4b5c-9b79-9357e35ff8c6"

# --- Connect ---
Connect-MgGraph  -ClientId $ClientID -TenantId $TenantID -CertificateThumbprint $Thumbprint

# ================================================================
#  CONFIGURATION
# ================================================================

$androidAAGuid = "de1e552d-db1d-4423-a619-566b625cdc84"
$iosAAGuid     = "90a3ccdf-635c-4729-a248-9b709135078f"

$sourceGroupMail  = "erockteam@enchantedrock.com"
$fido2GroupName   = "MFA-FIDO2-Complete"
$authAppGroupName = "MFA-AuthApp-Complete"
$regReqGroupName  = "MFA-Registration-Required"
$resultsPath      = "C:\Users\DakotaRuhl\Documents\Reports\FIDO2Results.xlsx"

# ================================================================
#  RESOLVE GROUPS
# ================================================================

Write-Host "Resolving groups..." -ForegroundColor Cyan

$sourceGroup  = Get-MgGroup -Filter "mail eq '$sourceGroupMail'" -ErrorAction Stop
if (-not $sourceGroup) { throw "Source group '$sourceGroupMail' not found." }

$fido2Group   = Get-MgGroup -Filter "displayName eq '$fido2GroupName'"  -ErrorAction Stop
$authAppGroup = Get-MgGroup -Filter "displayName eq '$authAppGroupName'" -ErrorAction Stop
$regReqGroup  = Get-MgGroup -Filter "displayName eq '$regReqGroupName'"  -ErrorAction Stop

if (-not $fido2Group)   { throw "Group '$fido2GroupName' not found. Create it first." }
if (-not $authAppGroup) { throw "Group '$authAppGroupName' not found. Create it first." }
if (-not $regReqGroup)  { throw "Group '$regReqGroupName' not found. Create it first." }

Write-Host "  Source:  $($sourceGroup.DisplayName)  ($($sourceGroup.Id))"  -ForegroundColor Gray
Write-Host "  FIDO2:   $($fido2Group.DisplayName)   ($($fido2Group.Id))"   -ForegroundColor Gray
Write-Host "  AuthApp: $($authAppGroup.DisplayName)  ($($authAppGroup.Id))" -ForegroundColor Gray
Write-Host "  RegReq:  $($regReqGroup.DisplayName)   ($($regReqGroup.Id))"  -ForegroundColor Gray

# ================================================================
#  PULL SOURCE GROUP MEMBERS (users only)
# ================================================================

Write-Host "`nFetching members from $sourceGroupMail ..." -ForegroundColor Cyan
$sourceMembers = Get-MgGroupMember -GroupId $sourceGroup.Id -All

$users = foreach ($m in $sourceMembers) {
    if ($m.AdditionalProperties['@odata.type'] -eq '#microsoft.graph.user') {
        [PSCustomObject]@{
            Id                = $m.Id
            UserPrincipalName = $m.AdditionalProperties['userPrincipalName']
        }
    }
}

if (-not $users -or $users.Count -eq 0) { throw "No user members found in source group." }

# Track all source user IDs so the sync knows which members it "owns"
$allSourceUserIds = [System.Collections.Generic.HashSet[string]]::new([string[]]($users.Id))
Write-Host "Found $($users.Count) user(s) in source group.`n" -ForegroundColor Cyan

# ================================================================
#  CLASSIFICATION
# ================================================================

$fido2UserIds   = [System.Collections.Generic.HashSet[string]]::new()
$authAppUserIds = [System.Collections.Generic.HashSet[string]]::new()
$regReqUserIds  = [System.Collections.Generic.HashSet[string]]::new()

$passKeysFoundCount     = 0
$passKeysMissingCount   = 0
$authAppFoundCount      = 0
$authAppFoundOAuthCount = 0
$phoneAuthOnlyCount     = 0
$noAuthAppOrPhoneCount  = 0
$noAuthMethodsCount     = 0

$results = @()

foreach ($user in $users) {
    try {
        $passkeyRecorded = $false
        $fido2Methods = @(Get-MgUserAuthenticationFido2Method -UserId $user.Id -ErrorAction Stop)
        $authMethods  = @(Get-MgUserAuthenticationMethod     -UserId $user.Id -ErrorAction Stop)

        # --- FIDO2 (highest priority) ---
        if ($fido2Methods.Count -gt 0) {
            foreach ($method in $fido2Methods) {
                if ($method.AaGuid -eq $androidAAGuid) {
                    $results += [PSCustomObject]@{
                        UserPrincipalName    = $user.UserPrincipalName
                        MethodType           = "Passkey Android"
                        DisplayName          = $method.DisplayName
                        CreatedDateTime      = $method.CreatedDateTime
                        AdditionalProperties = ($method.AdditionalProperties.GetEnumerator() |
                            ForEach-Object { "$($_.Key)=$($_.Value)" }) -join "; "
                    }
                    $passkeyRecorded = $true
                }
                elseif ($method.AaGuid -eq $iosAAGuid) {
                    $results += [PSCustomObject]@{
                        UserPrincipalName    = $user.UserPrincipalName
                        MethodType           = "Passkey iOS"
                        DisplayName          = $method.DisplayName
                        CreatedDateTime      = $method.CreatedDateTime
                        AdditionalProperties = ($method.AdditionalProperties.GetEnumerator() |
                            ForEach-Object { "$($_.Key)=$($_.Value)" }) -join "; "
                    }
                    $passkeyRecorded = $true
                }
            }

            if ($passkeyRecorded) {
                $passKeysFoundCount++
                [void]$fido2UserIds.Add($user.Id)
                continue
            }
        }

        # No passkey matched
        $passKeysMissingCount++

        # --- Authenticator / OATH / Phone ---
        $authAppMethod = $authMethods | Where-Object {
            $_.AdditionalProperties['@odata.type'] -eq '#microsoft.graph.microsoftAuthenticatorAuthenticationMethod'
        } | Select-Object -First 1

        $oathMethod = $authMethods | Where-Object {
            $_.AdditionalProperties['@odata.type'] -eq '#microsoft.graph.softwareOathAuthenticationMethod'
        } | Select-Object -First 1

        $phoneMethod = $authMethods | Where-Object {
            $_.AdditionalProperties['@odata.type'] -eq '#microsoft.graph.phoneAuthenticationMethod'
        } | Select-Object -First 1

        if ($authMethods.Count -eq 0) {
            $results += [PSCustomObject]@{
                UserPrincipalName    = $user.UserPrincipalName
                MethodType           = "No Auth Methods!"
                DisplayName          = $null
                CreatedDateTime      = $null
                AdditionalProperties = $null
            }
            $noAuthMethodsCount++
            [void]$regReqUserIds.Add($user.Id)
        }
        elseif ($authAppMethod) {
            $results += [PSCustomObject]@{
                UserPrincipalName    = $user.UserPrincipalName
                MethodType           = "Authenticator App"
                DisplayName          = $authAppMethod.AdditionalProperties['displayName']
                CreatedDateTime      = $authAppMethod.CreatedDateTime
                AdditionalProperties = ($authAppMethod.AdditionalProperties.GetEnumerator() |
                    Where-Object { $_.Key -notin '@odata.type', 'displayName' } |
                    ForEach-Object { "$($_.Key)=$($_.Value)" }) -join "; "
            }
            $authAppFoundCount++
            [void]$authAppUserIds.Add($user.Id)
        }
        elseif ($oathMethod) {
            $results += [PSCustomObject]@{
                UserPrincipalName    = $user.UserPrincipalName
                MethodType           = "Authenticator App (Software OATH)"
                DisplayName          = $oathMethod.AdditionalProperties['displayName']
                CreatedDateTime      = $oathMethod.CreatedDateTime
                AdditionalProperties = ($oathMethod.AdditionalProperties.GetEnumerator() |
                    Where-Object { $_.Key -notin '@odata.type', 'displayName' } |
                    ForEach-Object { "$($_.Key)=$($_.Value)" }) -join "; "
            }
            $authAppFoundOAuthCount++
            [void]$authAppUserIds.Add($user.Id)
        }
        elseif ($phoneMethod) {
            $results += [PSCustomObject]@{
                UserPrincipalName    = $user.UserPrincipalName
                MethodType           = "Phone Auth Only"
                DisplayName          = "$($phoneMethod.AdditionalProperties['phoneType']) $($phoneMethod.AdditionalProperties['phoneNumber'])"
                CreatedDateTime      = $phoneMethod.CreatedDateTime
                AdditionalProperties = ($phoneMethod.AdditionalProperties.GetEnumerator() |
                    ForEach-Object { "$($_.Key)=$($_.Value)" }) -join "; "
            }
            $phoneAuthOnlyCount++
            [void]$regReqUserIds.Add($user.Id)
        }
        else {
            $results += [PSCustomObject]@{
                UserPrincipalName    = $user.UserPrincipalName
                MethodType           = "No Authenticator App or Phone!"
                DisplayName          = $null
                CreatedDateTime      = $null
                AdditionalProperties = ($authMethods | ForEach-Object {
                    ($_.AdditionalProperties.GetEnumerator() |
                        ForEach-Object { "$($_.Key)=$($_.Value)" }) -join "; "
                }) -join " | "
            }
            $noAuthAppOrPhoneCount++
            [void]$regReqUserIds.Add($user.Id)
        }
    }
    catch {
        Write-Warning "Failed to retrieve auth methods for $($user.UserPrincipalName): $_"
        $results += [PSCustomObject]@{
            UserPrincipalName    = $user.UserPrincipalName
            MethodType           = "Error"
            DisplayName          = $null
            CreatedDateTime      = $null
            AdditionalProperties = $_.ToString()
        }
        # Errors default to registration-required so CA still covers them
        [void]$regReqUserIds.Add($user.Id)
    }
}

# ================================================================
#  GROUP MEMBERSHIP SYNC
#  Only adds/removes users who are in the source group (ManagedIds).
#  Anyone added to a target group outside this script is untouched.
# ================================================================


# Remove the $allSourceUserIds line (no longer used)
# $allSourceUserIds = $users.Id

# Simplified function signature
function Sync-TargetGroup {
    param(
        [string]$GroupId,
        [string]$GroupName,
        [System.Collections.Generic.HashSet[string]]$DesiredIds
    )

    $currentMembers = Get-MgGroupMember -GroupId $GroupId -All
    $currentIds = [System.Collections.Generic.HashSet[string]]::new(
        [string[]]@($currentMembers | ForEach-Object { $_.Id })
    )


    $toAdd    = @($DesiredIds | Where-Object { -not $currentIds.Contains($_) })
    $toRemove = @($currentIds | Where-Object { -not $DesiredIds.Contains($_) })

    $addOk = 0; $removeOk = 0

    foreach ($id in $toAdd) {
        try {
            New-MgGroupMember -GroupId $GroupId -DirectoryObjectId $id -ErrorAction Stop
            $addOk++
        }
        catch {
            Write-Warning "  ADD FAILED [$GroupName] $id : $_"
        }
    }

    foreach ($id in $toRemove) {
        try {
            Remove-MgGroupMemberByRef -GroupId $GroupId -DirectoryObjectId $id -ErrorAction Stop
            $removeOk++
        }
        catch {
            Write-Warning "  REMOVE FAILED [$GroupName] $id : $_"
        }
    }

    Write-Host "$GroupName  |  Desired: $($DesiredIds.Count)  Added: $addOk  Removed: $removeOk" -ForegroundColor Cyan
}

# Updated calls (no more -ManagedIds parameter)
Sync-TargetGroup -GroupId $fido2Group.Id   -GroupName $fido2GroupName   -DesiredIds $fido2UserIds
Sync-TargetGroup -GroupId $authAppGroup.Id -GroupName $authAppGroupName -DesiredIds $authAppUserIds
Sync-TargetGroup -GroupId $regReqGroup.Id  -GroupName $regReqGroupName  -DesiredIds $regReqUserIds

# ================================================================
#  EXCEL AUDIT REPORT
# ================================================================

if (Test-Path -Path $resultsPath) {
    Remove-Item -Path $resultsPath -Force
}

$excel    = $results | Export-Excel -Path $resultsPath -AutoSize -WorksheetName "FIDO2Results" -PassThru
$sheet    = $excel.Workbook.Worksheets["FIDO2Results"]
$lastRow  = $sheet.Dimension.End.Row
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

Add-ConditionalFormatting -WorkSheet $sheet -Range $fullRange -RuleType Expression `
    -ConditionValue '$B2="Error"' `
    -BackgroundColor ([System.Drawing.Color]::MistyRose) `
    -ForegroundColor ([System.Drawing.Color]::DarkRed)

$sheet.Cells[$sheet.Dimension.Address].Style.HorizontalAlignment = [OfficeOpenXml.Style.ExcelHorizontalAlignment]::Left
$sheet.Cells[$sheet.Dimension.Address].Style.VerticalAlignment   = [OfficeOpenXml.Style.ExcelVerticalAlignment]::Top
Close-ExcelPackage $excel

# --- Summary sheet ---
$summary = @(
    [PSCustomObject]@{ Metric = "Passkeys Found";                 Count = $passKeysFoundCount }
    [PSCustomObject]@{ Metric = "Passkeys Missing";               Count = $passKeysMissingCount }
    [PSCustomObject]@{ Metric = "Auth App Found";                 Count = $authAppFoundCount }
    [PSCustomObject]@{ Metric = "Auth App Found (Software OATH)"; Count = $authAppFoundOAuthCount }
    [PSCustomObject]@{ Metric = "Phone Auth Only";                Count = $phoneAuthOnlyCount }
    [PSCustomObject]@{ Metric = "No Authenticator App or Phone!"; Count = $noAuthAppOrPhoneCount }
    [PSCustomObject]@{ Metric = "No Auth Methods!";               Count = $noAuthMethodsCount }
    [PSCustomObject]@{ Metric = "---";                            Count = "---" }
    [PSCustomObject]@{ Metric = "FIDO2 Group Target";             Count = $fido2UserIds.Count }
    [PSCustomObject]@{ Metric = "AuthApp Group Target";           Count = $authAppUserIds.Count }
    [PSCustomObject]@{ Metric = "Reg Required Group Target";      Count = $regReqUserIds.Count }
)

$summary | Export-Excel -Path $resultsPath -AutoSize -WorksheetName "Summary"

Write-Host "`nDone. Report saved to $resultsPath" -ForegroundColor Green
Disconnect-MgGraph