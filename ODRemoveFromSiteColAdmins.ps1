Import-Module Microsoft.Online.SharePoint.PowerShell -UseWindowsPowerShell
$Thumbprint = "C47B91EB62634CA61FA8146DDA83B8BF605C0962"
$ClientID = "ea2ca49b-d0df-4774-b611-86cf9dc9629f"
$TenantID = "0bdf0e1f-a359-4b5c-9b79-9357e35ff8c6"
Connect-SPOService -Url https://enchantedrock-admin.sharepoint.com -ClientId $ClientID -TenantId $TenantID -CertificateThumbprint $Thumbprint
Connect-PnPOnline -Url https://enchantedrock-admin.sharepoint.com -ClientId $ClientID -Tenant $TenantID -Thumbprint $Thumbprint


$OneDriveSites = Get-SPOSite -IncludePersonalSite $true -Limit All -Template "SPSPERS"
#$OneDriveSites = Get-PnPTenantSite -IncludePersonalSite $true -Limit All -Template "SPSPERS"

$UserToRemove = "admin-dr@enchantedrock.com"

$results = @()
foreach ($site in $OneDriveSites) 
{
    try 
    {
        $siteAdmins = Get-SPOUser -Site $site.Url -Limit All -ErrorAction Stop | Where-Object { $_.IsSiteAdmin -eq $True }
        if ($siteAdmins.LoginName -contains $UserToRemove) 
        {
            Write-Host "User $UserToRemove is a site admin for $($site.Url). Removing admin rights..."
            Set-SPOUser -Site $site.Url -LoginName $UserToRemove -IsSiteCollectionAdmin $false -ErrorAction Stop
            Write-Host "Removed $UserToRemove as site admin for $($site.Url)."
        }
        #Recalculate site admins after potential removal
        $siteAdmins = Get-SPOUser -Site $site.Url -Limit All -ErrorAction Stop | Where-Object { $_.IsSiteAdmin -eq $True }
        $results += [PSCustomObject]@{
            SiteUrl      = $site.Url
            SiteAdminNames  = ($siteAdmins | Select-Object -ExpandProperty DisplayName) -join "; " 
            SiteAdminLogins = ($siteAdmins | Select-Object -ExpandProperty LoginName) -join "; "
        }
        Write-Host "Processed site: $($site.Url)"  
    }
    catch 
    {
        If ($_.Exception.Message -like "*Access is denied*")
        {
            Write-Error "$($site.Url): $($_.Exception.Message)"
        }
        else {
            Write-Error "An unexpected error occurred while processing site $($site.Url): $($_.Exception.Message)"
        }
    }
}

$results | Export-Csv -Path "C:\Users\DakotaRuhl\Documents\Reports\OneDrive Admins\AdminJOAllOneDriveSiteAdmins.csv" -NoTypeInformation

#Get-SPOUser -Site https://enchantedrock-my.sharepoint.com/personal/slong_enchantedrock_com -Limit All | Where-Object {$_.IsSiteAdmin -eq $True} | Select-Object -ExpandProperty DisplayName

##Remove from a single site
$userToRemove = "admin-dr@erock.com"
$singleSite = "https://enchantedrock-my.sharepoint.com/personal/kparekh_erock_com"

$site = Get-PnPTenantSite -Identity $singleSite 
Connect-PnPOnline -Url $site.Url -ClientId $ClientID -Tenant $TenantID -Thumbprint $Thumbprint


try 
{
    $siteAdmins = Get-PnPUser | Where-Object { $_.IsSiteAdmin -eq $True }
    foreach ($admin in $siteAdmins) 
    {
        $userToRemoveFormatted = "i:0#.f|membership|" +  $userToRemove
        Write-Host "Current site admin: $($admin.DisplayName) ($($admin.LoginName))"
        if ($admin.LoginName -eq $userToRemoveFormatted) 
        {
            Write-Host "User $userToRemove is a site admin for $($site.Url). Removing admin rights..."
            Get-PnPUser | ? LoginName -Like $userToRemoveFormatted | Remove-PnPSiteCollectionAdmin -ErrorAction Stop
            Write-Host "Removed $userToRemove as site admin for $($site.Url)."
        }
    }
    
    #Recalculate site admins after potential removal
    $siteAdmins = Get-PnPUser | Where-Object { $_.IsSiteAdmin -eq $True }
    $results += [PSCustomObject]@{
        SiteUrl      = $site.Url
        SiteAdminNames  = ($siteAdmins | Select-Object -ExpandProperty Title) -join "; " 
        SiteAdminLogins = ($siteAdmins | Select-Object -ExpandProperty LoginName) -join "; "
    }
    Write-Host "Processed site: $($site.Url)"  
}
catch 
{
    If ($_.Exception.Message -like "*Access is denied*")
    {
        Write-Error "$($site.Url): $($_.Exception.Message)"
    }
    else {
        Write-Error "An unexpected error occurred while processing site $($site.Url): $($_.Exception.Message)"
    }
}
