Connect-ExchangeOnline -CertificateThumbprint $env:AZURE_CLIENT_CERTIFICATE_THUMBPRINT  -AppId $env:AZURE_CLIENT_ID -Organization $env:AZURE_TENANT_DOMAIN

$group = "ea_mail_app_access@erock.com"
$appId = "562603c1-f979-4ab8-9f1b-00eab83a9dd2"
$testUserApproved = "pp-automations@erock.com"
$testUserDenied = "druhl@erock.com"

New-ApplicationAccessPolicy `
    -AppId $appId `
    -PolicyScopeGroupId $group `
    -AccessRight RestrictAccess `
    -Description "Restrict application access to approved mailboxes"

## Test access for the denied user first
Test-ApplicationAccessPolicy `
    -Identity $testUserDenied `
    -AppId $appId

## Should show granted access for the approved user
Test-ApplicationAccessPolicy `
    -Identity $testUserApproved `
    -AppId $appId
