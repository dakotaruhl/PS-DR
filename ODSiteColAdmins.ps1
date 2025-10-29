#Import-Module Microsoft.Online.SharePoint.PowerShell -UseWindowsPowerShell
#Connect-SPOService -Url https://enchantedrock-admin.sharepoint.com

$OneDriveSites = Get-SPOSite -IncludePersonalSite $true -Limit All -Template "SPSPERS"
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

$results | Export-Csv -Path "C:\Users\DakotaRuhl\Documents\Reports\OneDrive Admins\AllOneDriveSiteAdmins.csv" -NoTypeInformation

#Get-SPOUser -Site https://enchantedrock-my.sharepoint.com/personal/slong_enchantedrock_com -Limit All | Where-Object {$_.IsSiteAdmin -eq $True} | Select-Object -ExpandProperty DisplayName
