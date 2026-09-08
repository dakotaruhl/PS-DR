# Azure Functions PowerShell profile.ps1
# Runs once when the Functions host starts (cold start).
#
# This app does not call any Az PowerShell cmdlets, so there is no
# Connect-AzAccount -Identity here. Secrets are pulled in automatically
# via Key Vault references configured in the Function App's Application
# Settings (GraphTenantId / GraphClientId / GraphClientSecret) - see
# README.md for the setup steps.

<# TESTING

try {
    Invoke-RestMethod -Method Post -Uri "http://localhost:7071/api/SendMail" -ContentType 'application/json' -Body (@{
        To      = "druhl@erock.com"
        Subject = "Local test"
        Body    = "<p>Hello from local Functions host.</p>"
    } | ConvertTo-Json)
} catch {
    $_.ErrorDetails.Message
}

#>