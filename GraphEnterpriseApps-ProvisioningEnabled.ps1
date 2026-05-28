# Requires Microsoft.Graph.Authentication and Microsoft.Graph.Applications
# Permissions needed:
#   Application.Read.All
#   Synchronization.Read.All
#
# This script connects to Microsoft Graph using certificate-based authentication, 
# retrieves all enterprise applications (service principals), checks for Provisioning (SCIM) jobs, and checks for SSO enablement. 
# The results are output to the console and exported to an Excel file.

$Thumbprint = "C47B91EB62634CA61FA8146DDA83B8BF605C0962"
$ClientID = "ea2ca49b-d0df-4774-b611-86cf9dc9629f"
$TenantID = "0bdf0e1f-a359-4b5c-9b79-9357e35ff8c6"
Connect-MgGraph -ClientId $ClientID -TenantId $TenantID -CertificateThumbprint $Thumbprint

# Get all enterprise apps / service principals
$servicePrincipals = Get-MgServicePrincipal -All

$results = foreach ($sp in $servicePrincipals) {
    $jobs = $null

    try {
        $jobs = Get-MgServicePrincipalSynchronizationJob -ServicePrincipalId $sp.Id -ErrorAction Stop
    }
    catch {
        $jobs = $null
    }

    [pscustomobject]@{
        DisplayName              = $sp.DisplayName
        ServicePrincipalId       = $sp.Id
        AppId                    = $sp.AppId
        ServicePrincipalType     = $sp.ServicePrincipalType
        AccountEnabled           = $sp.AccountEnabled
        SSOEnabled               = [bool]($sp.PreferredSingleSignOnMode -and $sp.PreferredSingleSignOnMode -ne 'notSupported')
        SSOMode                  = $sp.PreferredSingleSignOnMode
        ProvisioningEnabled      = [bool]($jobs -and $jobs.Count -gt 0)
        SyncJobCount             = if ($jobs) { $jobs.Count } else { 0 }
        SyncJobIds               = if ($jobs) { $jobs.Id -join '; ' } else { $null }
        ProvisioningJobStatus    = if ($jobs) { $jobs.Status.Code -join '; ' } else { $null }
        Tags                     = if ($sp.Tags) { $sp.Tags -join '; ' } else { $null }
    }
}

$results | Sort-Object DisplayName | Format-Table -AutoSize

# Show only apps with provisioning enabled
$enabled = $results | Where-Object { $_.ProvisioningEnabled -eq $true } | Sort-Object DisplayName
$enabled | Format-Table -AutoSize

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$csvPath = "C:\Users\DakotaRuhl\Documents\Reports\DomainMigration\EnterpriseApps-SSO-Provisioning-$timestamp.xlsx"
$results | Export-Excel -Path $csvPath 

Write-Host "Exported to: $csvPath"




$params = @{
    passwordPolicies = "DisablePasswordExpiration"
}

Update-MgUser -UserId svc_fat_ipads@enchantedrock.com -BodyParameter $params


Update-MgUser -UserId svc_fat_ipads@enchantedrock.com -BodyParameter @{
    passwordPolicies = "None"
}


Update-MgUser -UserId svc_fat_ipads@enchantedrock.com -BodyParameter @{
    passwordPolicies = "DisablePasswordExpiration"
}


Get-MgUser -UserId svc_fat_ipads@enchantedrock.com | Select PasswordPolicies



$user = "svc_fat_ipads@enchantedrock.com"

# Step 1: explicitly set None
Update-MgUser -UserId $user -PasswordPolicies "None"

# Step 2: set DisablePasswordExpiration
Update-MgUser -UserId $user -PasswordPolicies "DisablePasswordExpiration"

# Step 3: verify FULL object (not Select)
Get-MgUser -UserId $user | fl PasswordPolicies
