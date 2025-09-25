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

foreach ($group in $groups) 
{
    $owners = Get-MgGroupOwner -GroupId $group.Id
    foreach ($owner in $owners) {
        $results += [PSCustomObject]@{
            GroupName   = $group.DisplayName
            GroupId     = $group.Id
            OwnerName   = Get-MgUser -UserId $owner.Id | Select-Object -ExpandProperty DisplayName
            OwnerEmail  = Get-MgUser -userId $owner.Id | Select-Object -ExpandProperty Mail
        }
    }
}

# Export to CSV
$results | Export-Csv -Path "C:\Users\DakotaRuhl\Documents\Reports\SiteLifeCyclePolicy\M365GroupOwnersGraph.csv" -NoTypeInformation

Write-Host "Export complete. File saved as M365GroupOwnersGraph.csv"

<#Debug
Get-MgGroupOwner -GroupId c3efcd87-457a-4741-9f44-b34dda0cade3
    ccfe1420-b7d9-4d70-b347-372997c770e7
Get-MgGroup -GroupId c3efcd87-457a-4741-9f44-b34dda0cade3 | fl

Get-MgUser -UserId ccfe1420-b7d9-4d70-b347-372997c770e7 | Select-Object -ExpandProperty Mail
#>