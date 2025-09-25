Install-Module Microsoft.Graph 
Import-Module Microsoft.Graph
Update-Module -Name Microsoft.Graph
Connect-MgGraph -Scopes "Group.Read.All", "User.Read.All"

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
