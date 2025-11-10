Import-Module Microsoft.Online.SharePoint.PowerShell -UseWindowsPowerShell
Connect-SPOService -Url https://enchantedrock-admin.sharepoint.com

#Get all Team Sites
$LoginName = "admin-dr@enchantedrock.com"
$SearchTerm = "HEB"
$Sites = Get-SPOSite -limit all -Template "GROUP#0" | Where-Object { $_.Url -like "*$SearchTerm*" -and $_.IsTeamsConnected -eq $true }

foreach ($site in $Sites) 
{
    try 
    {
        Write-Host -foregroundcolor "Green" "Adding $LoginName as a site admin for $($site.Url)."
        Set-SPOUser -Site $site.Url -LoginName $LoginName -IsSiteCollectionAdmin $true
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