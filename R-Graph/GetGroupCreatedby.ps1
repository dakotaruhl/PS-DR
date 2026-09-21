#Install-Module Microsoft.Graph 
#Import-Module Microsoft.Graph
#Update-Module -Name Microsoft.Graph
#PNP PowerShell uses outdated graph module for some commands. If previously using PNP in your session, you must kill terminal and re-import these to work properly
Import-Module Microsoft.Graph.Authentication
Import-Module Microsoft.Graph.Groups
Import-Module Microsoft.Graph.Sites

#Set terminating error for catch to catch error
$ErrorActionPreference = "Stop"

# Connect to Microsoft Graph
Connect-MgGraph -Scopes "Group.ReadWrite.All", "User.Read.All"


# Get all M365 groups
$groups = Get-MgGroup -Filter "groupTypes/any(c:c eq 'Unified')" -All

# Create an array to store results
$results = @()

foreach ($group in $groups) 
{
    try 
    {
        $CreatedBehalf = Get-MgGroupCreatedOnBehalfOf -GroupId $group.Id  
        $CreatedBehalfId = $CreatedBehalf | select-Object -ExpandProperty Id
    }
    catch {
        Write-host -ForegroundColor Red "Error Details for $($group.DisplayName): $($_.Exception.Message)"
        $CreatedBehalfId = $null
    }
    if ($CreatedBehalfId) { 
        $name = Get-MgUser -UserId $CreatedBehalfId | Select-Object -ExpandProperty DisplayName 
        $results += [PSCustomObject]@{
        GroupName   = $group.DisplayName
        GroupId     = $group.Id
        CreatedBehalfName   = $name
        CreatedBehalfEmail  = Get-MgUser -userId $CreatedBehalfId | Select-Object -ExpandProperty Mail
        }
        Write-Host -ForegroundColor Cyan "Group: $($group.DisplayName) Created On Behalf Of User: $name"
    }
}
# Export to CSV
$results | Export-Csv -Path "C:\Users\DakotaRuhl\Documents\Reports\GroupsCreatedByApp\BehalfOfOnePlan.csv" -NoTypeInformation

Write-Host "Export complete. File saved as BehalfOfOnePlan.csv"

#Get-MgGroupCreatedOnBehalfOf -GroupId 0f25a173-e9b7-445c-ac15-5b2644b8e4d1
#$test = Get-MgGroup -GroupId 0f25a173-e9b7-445c-ac15-5b2644b8e4d1