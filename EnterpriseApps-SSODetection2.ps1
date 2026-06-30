#Connect-MgGraph -Scopes "Application.Read.All", "Directory.Read.All", "AuditLog.Read.All"


$DaysBack = 30
$StartDate = (Get-Date).AddDays(-$DaysBack).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

Write-Host "Getting service principals..." -ForegroundColor Cyan

# Get all enterprise apps, excluding MSFT native
$microsoftOwnerTenantIds = @(
    'f8cdef31-a31e-4b4a-93e4-5f571e91255a', # Microsoft Services
    '72f988bf-86f1-41af-91ab-2d7cd011db47'  # Microsoft
)

$filter = "servicePrincipalType eq 'Application'"

$ServicePrincipalsRaw = Get-MgServicePrincipal -All -Property @(
    "id",
    "appId",
    "displayName",
    "preferredSingleSignOnMode",
    "servicePrincipalType",
    "tags",
    "replyUrls",
    "homepage",
    "loginUrl",
    "accountEnabled",
    "appOwnerOrganizationId",
    "publisherName"
) -Filter $filter

$ServicePrincipals = $ServicePrincipalsRaw | Where-Object {
    $_.AppOwnerOrganizationId -notin $microsoftOwnerTenantIds
}


Write-Host "Getting app registrations..." -ForegroundColor Cyan

$Applications = Get-MgApplication -All -Property @(
    "id",
    "appId",
    "displayName",
    "web",
    "spa",
    "publicClient",
    "signInAudience",
    "requiredResourceAccess"
)

$AppByAppId = @{}
foreach ($App in $Applications) {
    if ($App.AppId) {
        $AppByAppId[$App.AppId] = $App
    }
}

Write-Host "Getting sign-in logs from last $DaysBack days..." -ForegroundColor Cyan

$Uri = "https://graph.microsoft.com/beta/auditLogs/signIns?`$filter=createdDateTime ge $StartDate&`$top=1000"

$SignIns = @()
$KnownApps = @{}   # <-- initialize BEFORE the loop
$PageCount = 0
$MaxPages = 200

do {
    $PageCount++

    Write-Host "Fetching page $PageCount..." -ForegroundColor Cyan

    try {
        $Response = Invoke-MgGraphRequest -Method GET -Uri $Uri
    }
    catch {
        Write-Host "Graph request failed. Exiting loop." -ForegroundColor Red
        break
    }

    if ($Response.value) {
        $SignIns += $Response.value

        Write-Host "Total records: $($SignIns.Count)"

        # ===== ADD THIS BLOCK RIGHT HERE =====
        foreach ($s in $Response.value) {
            if ($s.appId) {
                $KnownApps[$s.appId] = $true
            }
        }

        Write-Host "Unique apps discovered: $($KnownApps.Count)"

        if ($KnownApps.Count -gt 150) {
            Write-Host "Enough app coverage reached. Stopping early."
            break
        }
        # ===== END BLOCK =====
    }

    $NextLink = $Response.'@odata.nextLink'

    if (-not $NextLink) {
        Write-Host "No more pages."
        break
    }

    if ($NextLink -eq $Uri) {
        Write-Host "NextLink did not change. Breaking to avoid infinite loop."
        break
    }

    if ($PageCount -ge $MaxPages) {
        Write-Host "Reached max page limit ($MaxPages). Stopping."
        break
    }

    $Uri = $NextLink

    Start-Sleep -Milliseconds 200

}
while ($true)


$SignInSummary = $SignIns |
    Where-Object { $_.appId } |
    Group-Object appId |
    ForEach-Object {
        $First = $_.Group | Select-Object -First 1

        [PSCustomObject]@{
            AppId                  = $_.Name
            LastSeenAppName        = $First.appDisplayName
            SignInCount            = $_.Count
            ProtocolsSeen          = ($_.Group.authenticationProtocol | Where-Object { $_ } | Sort-Object -Unique) -join "; "
            LastSignIn             = ($_.Group.createdDateTime | Sort-Object -Descending | Select-Object -First 1)
        }
    }

$SignInByAppId = @{}
foreach ($Item in $SignInSummary) {
    $SignInByAppId[$Item.AppId] = $Item
}

$Report = foreach ($Sp in $ServicePrincipals) {

    $App = $null
    if ($Sp.AppId -and $AppByAppId.ContainsKey($Sp.AppId)) {
        $App = $AppByAppId[$Sp.AppId]
    }

    $Usage = $null
    if ($Sp.AppId -and $SignInByAppId.ContainsKey($Sp.AppId)) {
        $Usage = $SignInByAppId[$Sp.AppId]
    }

    $RedirectUriCount = 0

    if ($App) {
        if ($App.Web.RedirectUris) {
            $RedirectUriCount += $App.Web.RedirectUris.Count
        }

        if ($App.Spa.RedirectUris) {
            $RedirectUriCount += $App.Spa.RedirectUris.Count
        }

        if ($App.PublicClient.RedirectUris) {
            $RedirectUriCount += $App.PublicClient.RedirectUris.Count
        }
    }

    $ConfiguredSsoType = "Unknown"

    if ($Sp.PreferredSingleSignOnMode -eq "saml") {
        $ConfiguredSsoType = "SAML"
    }
    elseif ($Sp.PreferredSingleSignOnMode -eq "oidc") {
        $ConfiguredSsoType = "OIDC"
    }
    elseif ($Sp.PreferredSingleSignOnMode -eq "password") {
        $ConfiguredSsoType = "Password-based"
    }
    elseif ($Sp.PreferredSingleSignOnMode -eq "notSupported") {
        $ConfiguredSsoType = "Not supported"
    }
    elseif ($RedirectUriCount -gt 0) {
        $ConfiguredSsoType = "OIDC/OAuth likely"
    }

    $RuntimeSsoType = "No recent sign-in found"

    if ($Usage -and $Usage.ProtocolsSeen) {
        $RuntimeSsoType = $Usage.ProtocolsSeen
    }
    elseif ($Usage) {
        $RuntimeSsoType = "Recent sign-in found, protocol blank"
    }

    $DomainMigrationRisk = "Unknown"

    if ($ConfiguredSsoType -eq "SAML" -or $RuntimeSsoType -match "saml") {
        $DomainMigrationRisk = "High"
    }
    elseif ($ConfiguredSsoType -match "OIDC|OAuth" -or $RuntimeSsoType -match "oidc|oauth") {
        $DomainMigrationRisk = "Medium"
    }
    elseif ($ConfiguredSsoType -eq "Password-based") {
        $DomainMigrationRisk = "Low/Medium"
    }
    elseif ($Usage) {
        $DomainMigrationRisk = "Review"
    }
    else {
        $DomainMigrationRisk = "Low unless business owner says active"
    }

    [PSCustomObject]@{
        DisplayName                = $Sp.DisplayName
        AppId                      = $Sp.AppId
        ServicePrincipalId         = $Sp.Id
        AccountEnabled             = $Sp.AccountEnabled
        PreferredSingleSignOnMode  = $Sp.PreferredSingleSignOnMode
        ConfiguredSsoType          = $ConfiguredSsoType
        RuntimeSsoType             = $RuntimeSsoType
        RedirectUriCount           = $RedirectUriCount
        SignInCountLastXDays       = if ($Usage) { $Usage.SignInCount } else { 0 }
        LastSignIn                 = if ($Usage) { $Usage.LastSignIn } else { $null }
        DomainMigrationRisk        = $DomainMigrationRisk
        Homepage                   = $Sp.Homepage
        LoginUrl                   = $Sp.LoginUrl
    }
}

$Report |
    Sort-Object DomainMigrationRisk, SignInCountLastXDays -Descending |
    Export-Csv "C:\Users\DakotaRuhl\Documents\Reports\DomainMigration\EnterpriseApps-SSO-DomainMigration-Inventory.csv" -NoTypeInformation

$Report |
    Group-Object ConfiguredSsoType |
    Sort-Object Count -Descending |
    Select-Object Name, Count |
    Format-Table -AutoSize

$Report |
    Group-Object RuntimeSsoType |
    Sort-Object Count -Descending |
    Select-Object Name, Count |
    Format-Table -AutoSize

Write-Host "Export complete: .\EnterpriseApps-SSO-DomainMigration-Inventory.csv" -ForegroundColor Green