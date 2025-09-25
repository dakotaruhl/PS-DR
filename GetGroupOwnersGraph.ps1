#Install-Module Microsoft.Graph 
#Import-Module Microsoft.Graph
#Update-Module -Name Microsoft.Graph
#PNP PowerShell uses outdated graph module for some commands. If previously using PNP in your session, you must kill terminal and re-import these to work properly
Import-Module Microsoft.Graph.Authentication
Import-Module Microsoft.Graph.Groups

# Connect to Microsoft Graph
Connect-MgGraph -Scopes "Group.Read.All", "User.Read.All"

# Get all M365 groups
$groups = Get-MgGroup -Filter "groupTypes/any(c:c eq 'Unified')" -All

# Create an array to store results
$results = @()

foreach ($group in $groups) {
    $owners = Get-MgGroupOwner -GroupId $group.Id

    foreach ($owner in $owners) {
        $results += [PSCustomObject]@{
            GroupName   = $group.DisplayName
            GroupId     = $group.Id
            OwnerName   = $owner.DisplayName
            OwnerEmail  = $owner.Mail
        }
    }
}

# Export to CSV
$results | Export-Csv -Path "C:\Users\DakotaRuhl\Documents\Reports\SiteLifeCyclePolicy\M365GroupOwnersGraph.csv" -NoTypeInformation

Write-Host "Export complete. File saved as M365GroupOwnersGraph.csv"
