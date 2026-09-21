$AdminCenterURL = "https://enchantedrock-admin.sharepoint.com"

$Thumbprint = "C47B91EB62634CA61FA8146DDA83B8BF605C0962"
$ClientID   = "ea2ca49b-d0df-4774-b611-86cf9dc9629f"
$TenantName = "enchantedrock.onmicrosoft.com"
Connect-PnPOnline `
    -Url $AdminCenterURL `
    -ClientId $ClientID `
    -Tenant $TenantName `
    -Thumbprint $Thumbprint

$SitesCollection = Get-PnPTenantSite | Where-Object {$_.Template -eq "GROUP#0" -and $_.Lockstate -ne "Unlock"}
$SitesCollectionSOP = Get-PnPTenantSite | Where-Object {$_.url -like "*SOP_*" -or $_.url -like "*ERMSCM*" -or $_.url -like "*SCMInventory*"}

#display first 10
$SitesCollectionSOP | Format-Table Url, LockState
$SitesCollection = $SitesCollectionSOP
foreach ($site in $SitesCollection) {
    if($site.LockState -ne "ReadOnly") {
        Write-Host "Site is not ReadOnly locked: $($site.Url) LockState: $($site.LockState)" -ForegroundColor Yellow
        continue
    }
    Write-Host "Setting site to No Access: $($site.Url)" -ForegroundColor Green
    Set-PnPTenantSite -Url $site.Url -LockState "NoAccess"
}

foreach ($site in $SitesCollection) {
    if($site.LockState -eq "Unlock") {
        Write-Host "Site is already unlocked: $($site.Url) LockState: $($site.LockState)" -ForegroundColor Yellow
        continue
    }
    Write-Host "Setting site to unlock: $($site.Url)" -ForegroundColor Green
    Set-PnPTenantSite -Url $site.Url -LockState "Unlock"
}

Set-PnPTenantSite -Url https://enchantedrock.sharepoint.com/sites/FieldPoint -LockState "Unlock"
#delete site
Remove-PnPTenantSite -Url https://enchantedrock.sharepoint.com/sites/SOP_ERE_Commissioning -Force