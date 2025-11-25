Import-Module Microsoft.Online.SharePoint.PowerShell -UseWindowsPowerShell
Connect-SPOService -Url "https://enchantedrock-admin.sharepoint.com"

# Import-Module ImportExcel
# $filePath = "C:\Users\DakotaRuhl\Documents\Reports\GroupsCreatedByApp\Plans with TeamsURL.xlsx"
# $Worksheet = "Sheet2"
# #$columnName = "UniqueGroupsWithExclusions"
# $columnName = "Unique IDs that appear more than once"
# $excelData = Import-Excel -Path $filePath -WorksheetName $Worksheet
# $columnValues = $excelData | Select-Object -ExpandProperty $columnName

# $TenantAdminURL = "https://enchantedrock-admin.sharepoint.com/"
# Connect-PnPOnline -Url $TenantAdminURL -Interactive -ClientId 4ac6eede-e81e-4d22-abad-0d43c51486f2 

#$SitesCollections = @()
# foreach ($item in $columnValues) 
# {
#     try 
#     {
#         $groupdId = $item
#         $CurrentSite = Get-PnPTenantSite | Where-Object {$_.RelatedGroupID -eq $groupdId} -ErrorAction Stop
#         $SitesCollections += $CurrentSite
#         Write-Host -ForegroundColor Green "Added Site Collection for GroupID: $groupdId, and Site URL: $($CurrentSite.Url)"
#     }
#     catch 
#     {
#         Write-Host -ForegroundColor Red "Site for $groupdId not found. Skipping."
#     }
# }

#Get all Team Sites
$LoginName = "admin-dr@enchantedrock.com"
#$SearchTerm = "HEB"
#$Sites = Get-SPOSite -limit all -Template "GROUP#0" | Where-Object { $_.Url -like "*$SearchTerm*" -and $_.IsTeamsConnected -eq $true }


foreach ($site in $SitesCollections) 
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