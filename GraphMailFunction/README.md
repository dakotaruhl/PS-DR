# GraphMailFunction

PowerShell Azure Function (HTTP trigger) that sends mail through Microsoft
Graph using an app-only (client credentials) token from a service principal
that has `Mail.Send` application permission.

## Project layout

```
GraphMailFunction/
├── host.json
├── profile.ps1
├── requirements.psd1
├── local.settings.json      # local testing only - never deploy/commit real secrets
├── .gitignore
└── SendMail/
    ├── function.json        # HTTP trigger, POST, function-level auth
    └── run.ps1              # the mail-sending logic
```

## 1. App settings the function expects

The function reads everything from environment variables (Function App
Application Settings). Don't put secrets in the code or in App Settings as
plain text - use Key Vault references so the value is resolved by Azure at
runtime and never stored in the Function App config itself.

| App setting name     | Value |
|-----------------------|-------|
| `GraphTenantId`        | Key Vault reference to your tenant ID secret |
| `GraphClientId`        | Key Vault reference to the app registration's client ID |
| `GraphClientSecret`    | Key Vault reference to the app registration's client secret |
| `MailFromAddress`      | e.g. `SSRSreport@enchantedrock.com` (plain value, not a secret) |

## 2. Give the Function App access to Key Vault (Managed Identity)

Since the code now runs *inside* Azure, use the Function App's own
system-assigned managed identity instead of a bootstrap client id/secret.
This avoids the "secret to get a secret" problem.

```powershell
$rg      = "M365-Infrastructure"
$appName = "graph-mail-sendAs"        # your existing Function App name
$vault   = "kv-summittrail"         # your Key Vault name

# Enable system-assigned identity on the Function App and grab the principal ID
# from the returned object (same Identity.PrincipalId pattern Az uses for Get-AzWebApp)
$app         = Update-AzFunctionApp -ResourceGroupName $rg -Name $appName -IdentityType SystemAssigned -Force
$principalId = $app.Identity.PrincipalId

# RBAC-style vault (recommended)
$vaultResourceId = (Get-AzKeyVault -VaultName $vault -ResourceGroupName $rg).ResourceId
New-AzRoleAssignment -ObjectId $principalId -RoleDefinitionName "Key Vault Secrets User" -Scope $vaultResourceId

# --- OR, if the vault still uses access policies instead of RBAC ---
# Set-AzKeyVaultAccessPolicy -VaultName $vault -ObjectId $principalId -PermissionsToSecrets get,list
```

> If `$app.Identity.PrincipalId` comes back empty (identity can take a few seconds to
> propagate, or the object shape differs by Az module version), fall back to Azure CLI,
> which is documented and reliable: `az functionapp identity assign -g $rg -n $appName
> --query principalId -o tsv`.

Then set the app settings as Key Vault references (this is what actually
tells the Function App to resolve the value from the vault at startup):

```powershell
$settings = @{
    "GraphTenantId"     = "@Microsoft.KeyVault(SecretUri=https://$vault.vault.azure.net/secrets/AzureAD--TenantId/)"
    "GraphClientId"     = "@Microsoft.KeyVault(SecretUri=https://$vault.vault.azure.net/secrets/IT-OAuth-Mail-ClientId/)"
    "GraphClientSecret" = "@Microsoft.KeyVault(SecretUri=https://$vault.vault.azure.net/secrets/IT-OAuth-Mail-Secret/)"
    "MailFromAddress"   = "it_notifications@enchantedrock.com"
}

Update-AzFunctionAppSetting -ResourceGroupName $rg -Name $appName -AppSetting $settings
```

> Adjust the secret names above to whatever you actually named them in
> Key Vault. If you don't want to deal with Key Vault references at all,
> you can instead just put the plain values in App Settings - it works,
> it's just less secure since anyone with "read app settings" rights can
> see the client secret in cleartext.

## 3. Test locally (optional but recommended before publishing)

Requires [Azure Functions Core Tools v4](https://learn.microsoft.com/azure/azure-functions/functions-run-local)
and PowerShell 7.x.

```powershell
cd GraphMailFunction
# fill in real values in local.settings.json first (never commit this file)
func start
```

Then in another terminal:

```powershell
Invoke-RestMethod -Method Post -Uri "http://localhost:7071/api/SendMail" -Body (@{
    To      = "druhl@erock.com"
    Subject = "Local test"
    Body    = "<p>Hello from local Functions host.</p>"
} | ConvertTo-Json)
```

## 4. Publish to the existing Function App

### Option A - Azure Functions Core Tools (simplest, recommended)

```powershell
# one-time install
npm install -g azure-functions-core-tools@4 --unsafe-perm true

# from the GraphMailFunction folder
az login          # or Connect-AzAccount if you prefer, core tools uses az cli auth
func azure functionapp publish func-graph-mail
```

This zips the project, uploads it, and syncs the triggers for you. Nothing
else required.

### Option B - Pure PowerShell / Az module zip deploy (no Node.js needed)

Useful if you want this in a CI/CD runbook without installing Core Tools.

```powershell
$rg      = "rg-enchantedrock-it"
$appName = "func-graph-mail"
$src     = "C:\path\to\GraphMailFunction"
$zipPath = "C:\path\to\GraphMailFunction.zip"

# Zip the CONTENTS of the folder, not the folder itself
Compress-Archive -Path "$src\*" -DestinationPath $zipPath -Force

Publish-AzWebApp -ResourceGroupName $rg -Name $appName -ArchivePath $zipPath -Force

# Zip deploy syncs triggers automatically on a Consumption plan. If the new
# function doesn't show up right away, restart the app as a fallback:
Restart-AzFunctionApp -ResourceGroupName $rg -Name $appName -Force
```

(`az functionapp deployment source config-zip -g $rg -n $appName --src $zipPath`
via Azure CLI does the exact same zip deploy if you'd rather not touch Az PowerShell.)

## 5. Confirm the Function App runtime matches

The app was already created, so double check its settings match what this
project expects (Function App > Configuration > General settings):

- **Runtime stack**: PowerShell Core
- **Major version**: 7.2 or 7.4 (whatever `host.json`'s bundle supports)
- **FUNCTIONS_WORKER_RUNTIME** app setting = `powershell`

If any of those are off, deployment succeeds but the function won't load.

## 6. Calling it after publish

The trigger uses `authLevel: function`, so you need the function key. There's no
native Az PowerShell cmdlet for this (checked - it doesn't exist), so use Azure CLI
or the portal:

```powershell
# Azure CLI - returns JSON with the "default" key
az functionapp function keys list --resource-group $rg --name $appName --function-name SendMail

# or grab just the value:
$code = az functionapp function keys list -g $rg -n $appName --function-name SendMail --query default -o tsv
```

(Portal path: Function App > Functions > SendMail > Function Keys.)

```powershell
Invoke-RestMethod -Method Post -Uri "https://$appName.azurewebsites.net/api/SendMail?code=$code" -Body (@{
    To      = "druhl@erock.com"
    Subject = "Prod test"
    Body    = "<p>Sent from the Function App.</p>"
} | ConvertTo-Json)
```

If this will only ever be called from inside your network (e.g. SSRS
server), also consider adding IP restrictions or VNet integration on the
Function App rather than relying on the function key alone.
