#PNP PowerShell uses outdated graph module for some commands. If previously using PNP in your session, you must kill terminal and re-import these to work properly
Import-Module Microsoft.Graph.Authentication
Import-Module Microsoft.Graph.Groups

# Connect to Microsoft Graph
Connect-MgGraph -Scopes "Group.Read.All", "User.Read.All"

Import-Module ImportExcel
$GroupResults = @()
$GroupRange = @()
$NoGroupFound = @()
$GroupRangeExcel = Import-Excel -Path "C:\Users\DakotaRuhl\Documents\Reports\Ownerless Groups\NoOwnerGroups.xlsx" -WorksheetName "Data" -EndRow 130 | Select-Object -ExpandProperty "Group names"
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
        $EachGroupMembers = @()
        $EachMemberEmail = @()
        $GroupMembers = Get-MgGroupMember -GroupId $EGroup.Id
        foreach ($member in $GroupMembers) 
        {
            $EachGroupMembers += Get-MgUser -UserId $member.Id | Select-Object -ExpandProperty DisplayName
            $EachMemberEmail += Get-MgUser -UserId $member.Id | Select-Object -ExpandProperty Mail
        }
        $GroupResults += [PSCustomObject]@{
                GroupName   = $EGroup.DisplayName
                GroupId     = $EGroup.Id
                MemberNames = $EachGroupMembers -join "; "
                MemberEmails= $EachMemberEmail -join "; "   
            }
    }
    else {
        Write-Host "No valid Group found for processing: $Group"
    }
}

$GroupResults | Export-Csv -Path "C:\Users\DakotaRuhl\Documents\Reports\SiteLifeCyclePolicy\GroupMembers.csv" -NoTypeInformation
$NoGroupFound | Export-Csv -Path "C:\Users\DakotaRuhl\Documents\Reports\SiteLifeCyclePolicy\NoGroupMemberFound.csv" -NoTypeInformation
