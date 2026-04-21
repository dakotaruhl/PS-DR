$TenantAdminURL = "https://enchantedrock-admin.sharepoint.com/"
$Thumbprint = "C47B91EB62634CA61FA8146DDA83B8BF605C0962"
$ClientID = "ea2ca49b-d0df-4774-b611-86cf9dc9629f"
$TenantID = "0bdf0e1f-a359-4b5c-9b79-9357e35ff8c6"
Connect-MgGraph -ClientId $ClientID -TenantId $TenantID -CertificateThumbprint $Thumbprint
Connect-PnPOnline -Url $TenantAdminURL -ClientId $ClientID -Tenant $TenantID -Thumbprint $Thumbprint

$SitesCollection = Get-PnPTenantSite | Where-Object {$_.Template -eq "GROUP#0" -and $_.Lockstate -eq "NoAccess"}

foreach ($site in $SitesCollection) {
    Write-Host "Deleting site group: $($site.Url)" -ForegroundColor Green
    Remove-MgGroup -GroupId $site.GroupId -Confirm:$false
}

#AbbVie - Texas
Remove-MgGroup -GroupId $SitesCollection[1].GroupId -Confirm:$false


$SitesCollection | Export-Excel -Path "C:\Users\DakotaRuhl\Documents\Reports\LockedSites.xlsx" -WorksheetName "Locked Sites" -AutoSize












