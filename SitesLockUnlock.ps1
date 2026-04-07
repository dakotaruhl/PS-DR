$TenantAdminURL = "https://enchantedrock-admin.sharepoint.com/"
Connect-PnPOnline -Url $TenantAdminURL -Interactive -ClientId 4ac6eede-e81e-4d22-abad-0d43c51486f2

$SitesCollection = Get-PnPTenantSite | Where-Object {$_.Template -eq "GROUP#0" -and $_.Lockstate -ne "Unlock"}

#display first 10
$SitesCollection | Select-Object -First 10 | Format-Table Url, LockState

foreach ($site in $SitesCollection) {
    if($site.LockState -ne "ReadOnly") {
        Write-Host "Site is not ReadOnly locked: $($site.Url) LockState: $($site.LockState)" -ForegroundColor Yellow
        continue
    }
    Write-Host "Setting site to No Access: $($site.Url)" -ForegroundColor Green
    Set-PnPTenantSite -Url $site.Url -LockState "NoAccess"
}

