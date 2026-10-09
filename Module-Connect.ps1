# =====================================================
# Credentials
# =====================================================

$Thumbprint = $env:AZURE_CLIENT_CERTIFICATE_THUMBPRINT
$ClientID   = $env:AZURE_CLIENT_ID
$TenantId = $env:AZURE_TENANT_ID
$Tenant = $env:AZURE_TENANT_DOMAIN



# =====================================================
# Exchange
# =====================================================   

Connect-ExchangeOnline -CertificateThumbprint $env:AZURE_CLIENT_CERTIFICATE_THUMBPRINT  -AppId $env:AZURE_CLIENT_ID -Organization $env:AZURE_TENANT_DOMAIN

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

Connect-AzAccount -Subscription "03866bcc-752b-4fd1-b5bb-cdd66aed21fb" `
        -ServicePrincipal `
        -Tenant $env:AZURE_TENANT_ID `
        -ApplicationId $env:AZURE_CLIENT_ID `
        -CertificateThumbprint $env:AZURE_CLIENT_CERTIFICATE_THUMBPRINT | Out-Null


#CLI 
az login --service-principal -u $env:AZURE_CLIENT_ID -p <path-to-cert.pem> --tenant $env:AZURE_TENANT_ID

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