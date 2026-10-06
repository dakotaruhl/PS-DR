
# Auth with PnP Online using certificate-based authentication
Connect-PnPOnline `
    -Url "https://enchantedrock-admin.sharepoint.com" `
    -ClientId $env:AZURE_CLIENT_ID `
    -Thumbprint $env:AZURE_CLIENT_CERTIFICATE_THUMBPRINT `
    -Tenant $env:AZURE_TENANT_ID

# Grant the specified app site permissions
Grant-PnPEntraIDAppSitePermission `
    -AppId "c537a64e-a533-4bb4-9545-992cb25b14ab" `
    -DisplayName "Granite-Storage-Transfer" `
    -Site "https://enchantedrock.sharepoint.com/sites/Granite" `
    -Permissions "Write"