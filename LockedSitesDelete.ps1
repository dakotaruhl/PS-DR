$TenantAdminURL = "https://enchantedrock-admin.sharepoint.com/"
$Thumbprint = "C47B91EB62634CA61FA8146DDA83B8BF605C0962"
$ClientID = "ea2ca49b-d0df-4774-b611-86cf9dc9629f"
$TenantID = "0bdf0e1f-a359-4b5c-9b79-9357e35ff8c6"
Connect-MgGraph -ClientId $ClientID -TenantId $TenantID -CertificateThumbprint $Thumbprint
Connect-SPOService -Url $TenantAdminURL -ClientId $ClientID -TenantId $TenantID -CertificateThumbprint $Thumbprint
Connect-PnPOnline -Url $TenantAdminURL -ClientId $ClientID -Tenant $TenantID -Thumbprint $Thumbprint

$SitesCollection = Get-PnPTenantSite | Where-Object {$_.Template -eq "GROUP#0" -and $_.Lockstate -eq "NoAccess"}

foreach ($site in $SitesCollection) {
    Write-Host "Unlocking site group: $($site.Url)" -ForegroundColor Green
    Set-PnPTenantSite -Identity $site.Url -LockState "Unlock"
}

$groupsToDelete = Import-Excel -Path "C:\Users\DakotaRuhl\Documents\Reports\LockedSites123.xlsx" -WorksheetName "Locked Sites" | Select-Object -ExpandProperty GroupId
$count = 0
foreach ($group in $groupsToDelete) {
    Write-Host "Deleting site group ($count of $($groupsToDelete.Count)): $($group)" -ForegroundColor Green
    Remove-MgGroup -GroupId $group -Confirm:$false
    $count++
}

Export-Excel -InputObject $SitesCollection -Path "C:\Users\DakotaRuhl\Documents\Reports\LockedSites123.xlsx" -WorksheetName "Locked Sites" -AutoSize

#$SitesCollection | Export-Excel -Path "C:\Users\DakotaRuhl\Documents\Reports\LockedSites.xlsx" -WorksheetName "Locked Sites" -AutoSize

<#Unlock and delete single site
$singleSite = Get-PnPTenantSite -Identity https://enchantedrock.sharepoint.com/sites/AirLiquidePlan
Set-PnPTenantSite -Identity $singleSite.Url -LockState "Unlock"
Remove-MgGroup -GroupId "a0da3c13-96c0-4909-90bb-c9afbfd55fec" -Confirm:$false
Remove-PnPTenantSite $singleSite.Url -Confirm:$false
Remove-SPOSite -Identity https://sharepoint.com -Confirm:$false
#>

$Thumbprint = "C47B91EB62634CA61FA8146DDA83B8BF605C0962"
$ClientID = "ea2ca49b-d0df-4774-b611-86cf9dc9629f"
$TenantID = "0bdf0e1f-a359-4b5c-9b79-9357e35ff8c6"
Connect-MgGraph -ClientId $ClientID -TenantId $TenantID -CertificateThumbprint $Thumbprint

Get-MgUser -UserId sstraight@enchantedrock.com | Select-Object DisplayName, UserPrincipalName, LastPasswordChangeDateTime

