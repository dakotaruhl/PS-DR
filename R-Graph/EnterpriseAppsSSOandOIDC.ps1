try {
    $existing = Get-MgContext -ErrorAction SilentlyContinue

    if ($existing) {
        Write-Host "Graph already connected" -ForegroundColor Green
    } else {
        Write-Host "Connecting to Graph" -ForegroundColor DarkYellow
        $Thumbprint = "C47B91EB62634CA61FA8146DDA83B8BF605C0962"
        $ClientID = "ea2ca49b-d0df-4774-b611-86cf9dc9629f"
        $TenantID = "0bdf0e1f-a359-4b5c-9b79-9357e35ff8c6"
        Connect-MgGraph -ClientId $ClientID -TenantId $TenantID -CertificateThumbprint $Thumbprint
    }
}
catch {
    throw "Failed to connect to Graph: $($_.Exception.Message)"
}

# Get all enterprise apps, excluding MSFT native
$microsoftOwnerTenantIds = @(
    'f8cdef31-a31e-4b4a-93e4-5f571e91255a', # Microsoft Services
    '72f988bf-86f1-41af-91ab-2d7cd011db47'  # Microsoft
)

$filter = @(
    "servicePrincipalType eq 'Application'"
    "appOwnerOrganizationId ne $($microsoftOwnerTenantIds[0])"
    "appOwnerOrganizationId ne $($microsoftOwnerTenantIds[1])"
) -join ' and '

$spns = Get-MgServicePrincipal -All `
    -ConsistencyLevel eventual `
    -CountVariable spCount `
    -Filter $filter `
    -Property 'id,displayName,appId,appOwnerOrganizationId,verifiedPublisher,tags'

$apps = Get-MgApplication -All
$appHash = @{}
foreach ($app in $apps) {
    $appHash[$app.AppId] = $app
}

$result = foreach ($sp in $spns) {

    $app = $appHash[$sp.AppId]

    $ssoType = "Unknown"

    # --- SAML detection ---
    if ($sp.PreferredSingleSignOnMode -eq "saml" -or $sp.KeyCredentials.Count -gt 0) {
        $ssoType = "SAML"
    }

    # --- Password vault ---
    elseif ($sp.PreferredSingleSignOnMode -eq "password") {
        $ssoType = "PasswordVault"
    }

    # --- OIDC / OAuth detection ---
    elseif ($app -and (
        $app.Web.RedirectUris.Count -gt 0 -or
        $app.Spa.RedirectUris.Count -gt 0 -or
        $app.PublicClient.RedirectUris.Count -gt 0
    )) {
        $ssoType = "OIDC/OAuth"
    }

    # --- No SSO ---
    else {
        $ssoType = "None/Unknown"
    }

    [PSCustomObject]@{
        DisplayName = $sp.DisplayName
        AppId       = $sp.AppId
        ObjectId    = $sp.Id
        SSOType     = $ssoType
    }
}


$result | export-excel -path "C:\Users\DakotaRuhl\Documents\Reports\DomainMigration\SSOandOIDC2.xlsx" -WorksheetName "SSOandOIDC"




