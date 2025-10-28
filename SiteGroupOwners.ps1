#PNP PowerShell uses outdated graph module for some commands. If previously using PNP in your session, you must kill terminal and re-import these to work properly
Import-Module Microsoft.Graph.Authentication
Import-Module Microsoft.Graph.Groups

# Connect to Microsoft Graph
Connect-MgGraph -Scopes "Group.Read.All", "User.Read.All"

Import-Module ImportExcel
$SiteResults = @()
$GroupRange = @()
$NoGroupFound = @()
$GroupRangeExcel = Import-Excel -Path "C:\Users\DakotaRuhl\Documents\Reports\Site Creation\All Sites.xlsx" -WorksheetName "Final Sheet" -EndRow 130 | Select-Object -ExpandProperty Created
$count = $GroupRangeExcel.Count
Write-Host "Total Groups to Process: $count"

foreach ($Group in $GroupRangeExcel) 
{
    $Group = $Group -replace "'","''"

    if($null -ne $Group -and $Group -ne "" -and $Group -ne " " -and $null -ne (Get-MgGroup -Filter "startswith(DisplayName, '$Group')"))
    {
        $GroupRange += Get-MgGroup -Filter "startswith(DisplayName, '$Group')" -All
        Write-Host "Found Groups for: $Group"
    } 
    else 
    {
        Write-Host "No Group Found: $Group"
        $NoGroupFound += $Group
    }  
}

foreach ($EGroup in $GroupRange) 
{
    if($null -ne $EGroup -and $EGroup -ne "" -and $null -ne $EGroup.Id)
    {
        $SiteGroupOwners = Get-MgGroupOwner -GroupId $EGroup.Id
        foreach ($owner in $SiteGroupOwners) 
        {
            $SiteResults += [PSCustomObject]@{
                GroupName   = $EGroup.DisplayName
                GroupId     = $EGroup.Id
                OwnerName   = Get-MgUser -UserId $owner.Id | Select-Object -ExpandProperty DisplayName
                OwnerEmail  = Get-MgUser -userId $owner.Id | Select-Object -ExpandProperty Mail
            }
        }
    }
    else {
        Write-Host "No valid Group found for processing: $Group"
    }
}

$SiteResults | Export-Csv -Path "C:\Users\DakotaRuhl\Documents\Reports\SiteLifeCyclePolicy\SiteGroupOwners.csv" -NoTypeInformation
$NoGroupFound | Export-Csv -Path "C:\Users\DakotaRuhl\Documents\Reports\SiteLifeCyclePolicy\NoGroupFound.csv" -NoTypeInformation


<# Step 1: Define the group name
$groupName = "Amazon"

# Step 2: Get the group's Object ID
$groupId = (Get-MgGroup -Filter "DisplayName eq '$groupName'").Id

Connect-MgGraph -Scopes "AuditLog.Read.All"

# Step 3: Search the audit logs for the group creation event
# 'Add group' is the operation type for group creation
$logs = Get-MgAuditLogDirectoryAudit -Filter "activityDisplayName eq 'Add group'" -All | FL
$creationEvent = $logs | Where-Object {
    $_.TargetResources.Id -eq $groupId -and
    $_.InitiatedBy.App.DisplayName -notmatch 'Microsoft'
} | Select-Object -First 1

#$creationEvent = Get-MgAuditLogDirectoryAudit -Filter "TargetResources/any(t:t/id eq '$groupId') and initiatedBy/any(i:i/app/displayName ne 'Microsoft App' and i/app/displayName ne 'System Application')" -Top 1 | Where-Object { $_.InitiatedBy.App.DisplayName -notmatch 'Microsoft' }

# Step 4: Display the group creator's details
if ($creationEvent) {
    $creator = $creationEvent.InitiatedBy.User
    if ($creator) {
        Write-Host "Group '$groupName' was created by:"
        Write-Host "Display Name: $($creator.DisplayName)"
        Write-Host "User Principal Name: $($creator.UserPrincipalName)"
    } else {
        Write-Host "Could not determine the user who created the group. The action was likely performed by a system service."
    }
} else {
    Write-Host "No creation event found for group '$groupName'."
}

Connect-ExchangeOnline -UserPrincipalName admin-dr@enchantedrock.com -InlineCredential
Import-Module ExchangeOnlineManagement
Search-UnifiedAuditLog -Operations "Added group" -StartDate (Get-Date).AddDays(-90) -EndDate (Get-Date) -ResultSize 1000 | Where-Object {$_.AuditData -like "*$groupName*"} | Select-Object CreationDate, UserIds, Operations, AuditData
#>

Get-MgAuditLogDirectoryAudit -Filter "ActivityDisplayName eq 'Add group' and TargetResources/any(t:t/displayName eq 'Amazon')" -All | Select-Object ActivityDisplayName, InitiatedBy, TargetResources, ActivityDateTime