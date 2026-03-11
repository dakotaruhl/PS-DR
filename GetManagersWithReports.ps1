Connect-MgGraph -Scopes "User.Read.All","Directory.Read.All"
import-module Microsoft.Graph.Users

# Get all users (adjust properties as needed)
$users = Get-MgUser -All -Property Id,DisplayName,UserPrincipalName

$managersWithReports = foreach ($u in $users) {
    # Get direct reports for this user (if any)
    $reports = Get-MgUserDirectReport -UserId $u.Id -All -ErrorAction SilentlyContinue

    if ($reports.Count -gt 0 -and $u.DisplayName -notlike "*DIS*") {
        [pscustomobject]@{
            ManagerDisplayName   = $u.DisplayName
            ManagerUPN           = $u.UserPrincipalName
            DirectReportCount    = $reports.Count
        }
    }
}
$managersWithReports | Export-Csv "C:\Users\DakotaRuhl\Documents\Reports\Managers\EntraManagersWithDirectReports.csv" -NoTypeInformation

$newManagers = @()
Connect-ExchangeOnline
Foreach ($manager in $managersWithReports) {
    $recipient = Get-Recipient -Identity $manager.ManagerUPN
    if($recipient.RecipientTypeDetails -eq "UserMailbox" -and $recipient.CustomAttribute15 -ne "Manager") 
    {
        Set-Mailbox -Identity $manager.ManagerUPN -CustomAttribute15 "Manager"
        $newManagers += [pscustomobject]@{
            ManagerDisplayName   = $manager.ManagerDisplayName
            ManagerUPN           = $manager.ManagerUPN
        }
        Write-Host "Updated $($manager.ManagerDisplayName) with CustomAttribute15 = 'Manager'" -ForegroundColor Green
    }
    elseif ($recipient.CustomAttribute15 -eq "Manager") 
    {
        Write-Host " $($manager.ManagerDisplayName) already has CustomAttribute15 = 'Manager'" -ForegroundColor Yellow

    }
    else
    {
        Write-Host "Skipping $($manager.ManagerDisplayName) as they do not have a User Mailbox." -ForegroundColor Yellow
    }
}

$newManagers | Export-Csv "C:\Users\DakotaRuhl\Documents\Reports\Managers\NewManagers.csv" -NoTypeInformation
Set-DynamicDistributionGroup -Identity "peoplemanagers@enchantedrock.com" -ForceMembershipRefresh

$ddg = Get-DynamicDistributionGroup -Identity "PeopleManagers"
(Get-Recipient -RecipientPreviewFilter $ddg.RecipientFilter -ResultSize Unlimited | Measure-Object).Count

(Get-DynamicDistributionGroup -Identity "PeopleManagers").CalculatedMembershipUpdateTime
