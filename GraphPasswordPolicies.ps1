## Azure AD App Registration Details ##
$Thumbprint = "C47B91EB62634CA61FA8146DDA83B8BF605C0962"
$ClientID   = "ea2ca49b-d0df-4774-b611-86cf9dc9629f"
$TenantID   = "0bdf0e1f-a359-4b5c-9b79-9357e35ff8c6"

# Connect to Microsoft Graph using the app registration credentials
Connect-MgGraph `
    -ClientId $ClientID `
    -TenantId $TenantID `
    -CertificateThumbprint $Thumbprint `
    -NoWelcome

$user = "aschurr@erock.com"

Update-MgUser -UserId $user -passwordProfile @{forceChangePasswordNextSignIn = $false}
Update-MgUser -UserId $user -PasswordPolicies "DisablePasswordExpiration"


Get-MgUser -UserId $user | select-object DisplayName, UserPrincipalName
Get-MgUser -UserId $user -Property PasswordPolicies | Select-Object PasswordPolicies
Get-MgUser -UserId $user -Property PasswordProfile | Select-Object -ExpandProperty PasswordProfile