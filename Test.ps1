
Import-Module Microsoft.Graph.Authentication
Import-Module Microsoft.Graph.Groups


$SiteName = "https://enchantedrock.sharepoint.com/sites/erintranet" # Name of the SharePoint Online site to process

# Connect to the Microsoft Graph
Connect-MgGraph -Scopes "Sites.Read.All", "InformationProtectionPolicy.Read", "RecordsManagement.Read.All" -NoWelcome

Write-Host "Setting up for the SharePoint Online site files report..."

# Find the site
Write-Host "Looking for matching sites..."
[array]$Sites = Get-MgSite -Search ($SiteName)
if (!($Sites)) {
    Write-Host "No matching sites found - exiting"
    break
}
if ($Sites.Count -eq 1) {
    $Global:Site = $Sites[0]
    $SiteName = $Site.DisplayName
    Write-Host "Found site to process:" $SiteName
}
elseif ($Sites.Count -gt 1) {
    Clear-Host
    [int]$i = 1
    Write-Host "More than one matching site was found. We need you to select a site to report."
    foreach ($SiteOption in $Sites) {
        Write-Host ("{0}: {1} ({2})" -f $i, $SiteOption.DisplayName, $SiteOption.Name)
        $i++
    }
    [Int]$Answer = Read-Host "Enter the number of the site to use"
    if (($Answer -gt 0) -and ($Answer -le $i)) {
        [int]$Si = ($Answer-1)
        $SiteName = $Sites[$Si].DisplayName
        Write-Host ("OK. Selected site is {0}" -f $Sites[$Si].DisplayName)
        $Global:Site = $Sites[$Si]
    }
}

if (!($Site)) {
    Write-Host ("Can't find the {0} site - script exiting" -f $Uri)
    break
}

# Find ALL document libraries (drives) in the site
[array]$Drives = Get-MgSiteDrive -SiteId $Site.Id
if (!($Drives)) {
    Write-Host "No document libraries found in the site" -ForegroundColor Red
    Break
}


# Request which drive to use instead of all drives
Write-Host "Select a document library to process:"
[int]$i = 1
foreach ($DriveOption in $Drives) {
    Write-Host ("{0}: {1}" -f $i, $DriveOption.Name)
    $i++
}
[Int]$Answer = Read-Host "Enter the number of the document library to use"
if (($Answer -gt 0) -and ($Answer -le $i)) {
    [int]$Si = ($Answer-1)
    $DriveName = $Drives[$Si].Name
    Write-Host ("OK. Selected document library is {0}" -f $Drives[$Si].Name)
    $DriveId = $Drives[$Si].Id
    Write-Host "Fetching file information from drive:" $DriveName
    #Get-DriveItems -Drive $DriveId -FolderId "root"
}
else {
    Write-Host "Invalid selection - exiting"
    Break
}