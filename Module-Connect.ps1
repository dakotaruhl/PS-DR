# =====================================================
# Credentials
# =====================================================

$Thumbprint = "C47B91EB62634CA61FA8146DDA83B8BF605C0962"
$ClientID   = "ea2ca49b-d0df-4774-b611-86cf9dc9629f"
$Tenant = "enchantedrock.onmicrosoft.com"
$TenantId = "0bdf0e1f-a359-4b5c-9b79-9357e35ff8c6"

# =====================================================
# Exchange
# =====================================================   

Connect-ExchangeOnline -CertificateThumbprint $Thumbprint -AppId $ClientID -Organization $Tenant -NoWelcome

# =====================================================
# Graph API
# =====================================================

 Connect-MgGraph `
        -TenantId $TenantId `
        -ClientId $ClientID `
        -CertificateThumbprint $Thumbprint `
        -NoWelcome