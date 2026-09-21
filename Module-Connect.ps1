# =====================================================
# Credentials
# =====================================================

$Thumbprint = "C47B91EB62634CA61FA8146DDA83B8BF605C0962"
$ClientID   = "ea2ca49b-d0df-4774-b611-86cf9dc9629f"
$TenantId = "0bdf0e1f-a359-4b5c-9b79-9357e35ff8c6"
$Tenant = "enchantedrock.onmicrosoft.com"



# =====================================================
# Exchange
# =====================================================   

Connect-ExchangeOnline -CertificateThumbprint $Thumbprint -AppId $ClientID -Organization $Tenant

# =====================================================
# Graph API
# =====================================================

Connect-MgGraph `
        -TenantId $TenantId `
        -ClientId $ClientID `
        -CertificateThumbprint $Thumbprint `
        -NoWelcome


# =====================================================
# Azure 
# =====================================================       

Connect-AzAccount -ServicePrincipal `
        -Tenant $TenantId `
        -ApplicationId $ClientID `
        -CertificateThumbprint $Thumbprint | Out-Null


#CLI 
az login --service-principal -u $ClientID -p <path-to-cert.pem> --tenant $Tenant