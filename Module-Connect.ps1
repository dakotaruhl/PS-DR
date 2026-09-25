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
        -TenantId $env:AZURE_TENANT_ID `
        -ClientId $env:AZURE_CLIENT_ID `
        -CertificateThumbprint $env:AZURE_CLIENT_CERTIFICATE_THUMBPRINT `
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

# =====================================================
# Get Certificate 
# =====================================================  

$Cert = Get-ChildItem Cert:\CurrentUser\My, Cert:\LocalMachine\My |
    Where-Object Thumbprint -eq $Thumbprint

$Cert | Select-Object Subject, Thumbprint, HasPrivateKey, PSPath


#these credentials can be used by other scripts or modules to authenticate with Azure services
$env:AZURE_CLIENT_ID
$env:AZURE_TENANT_DOMAIN
$env:AZURE_CLIENT_CERTIFICATE_THUMBPRINT 
$env:AZURE_CLIENT_CERTIFICATE_PATH
$env:AZURE_TENANT_ID

Update-MgGroup -GroupId "00a68b7a-3e61-4b6d-93e8-d8229bb21a18" -SecurityEnabled:$true