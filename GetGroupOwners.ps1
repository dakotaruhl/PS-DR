# using ExchangeOnlineManagement PS module after running Connect-ExchangeOnline
#Connect-ExchangeOnline

$arrUGs = Get-UnifiedGroup -ResultSize Unlimited
# yes I know I'm resorting to += for this but the many:1 relationship of owners to groups
# means it's hard to do it better
$arrGroupOwners = @()
ForEach ($objGroup in $arrUGs) {
    Get-UnifiedGroupLinks $objGroup -LinkType Owner | ForEach-Object {
        $arrGroupOwners += [PSCustomObject]@{
            GroupOwnerDisplayName = $_.Name
            GroupOwnerSMTP = $_.PrimarySMTPAddress
            GroupSMTP = $objGroup.PrimarySMTPAddress
            GroupDisplayName = $objGroup.DisplayName
        }
    }
}
$arrOrphanedGroups = ForEach ($objGroup in ($arrUGs | Where-Object {$_.PrimarySMTPAddress -notin $arrGroupOwners.GroupSMTP})) {
    [PSCustomObject]@{
        GroupSMTP = $_.PrimarySMTPAddress
        GroupDisplayName = $_.DisplayName
    }
}

$arrOrphanedGroups | Export-Csv -Path "C:\Users\DakotaRuhl\Documents\Reports\SiteLifeCyclePolicy\OrphanedGroups.csv" -NoTypeInformation 
$arrGroupOwners | Export-Csv -Path "C:\Users\DakotaRuhl\Documents\Reports\SiteLifeCyclePolicy\GroupOwners.csv" -NoTypeInformation 


#$arrGroupOwners += [PSCustomObject]@{GroupOwner = $_.Name; GroupSMTP = $_.PrimarySMTPAddress; GroupDisplayName = $_.DisplayName}