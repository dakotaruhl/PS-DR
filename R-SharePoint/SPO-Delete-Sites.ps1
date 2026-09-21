# Load SharePoint Online module
Import-Module Microsoft.Online.SharePoint.PowerShell -ErrorAction SilentlyContinue

# Connect to SharePoint Online Admin Center
$adminUrl = "https://yourtenant-admin.sharepoint.com"
Connect-SPOService -Url $adminUrl

# Path to your CSV file
$csvPath = "C:\Path\To\SitesToDelete.csv"

# Import CSV
$sites = Import-Csv -Path $csvPath

foreach ($site in $sites) {
    $siteUrl = $site.SiteUrl
    Write-Host "Attempting to delete site: $siteUrl" -ForegroundColor Yellow

    try {
        Remove-SPOSite -Identity $siteUrl -Confirm:$false
        Write-Host "Deleted: $siteUrl" -ForegroundColor Green
    } catch {
        Write-Host "Failed to delete: $siteUrl. Error: $_" -ForegroundColor Red
    }
}
