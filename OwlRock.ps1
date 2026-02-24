Connect-ExchangeOnline

Get-CalendarProcessing -Identity "Owl Rock" | Format-List AllowDistributionGroup,BookInPolicy,RequestInPolicy,RequestOutOfPolicy

Get-DistributionGroup -identity "/o=ExchangeLabs/ou=Exchange Administrative Group (FYDIBOHF23SPDLT)/cn=Recipients/cn=d72ddffa90cb4129afd36639e698c064-OwlRockSG20" | FL
Get-DistributionGroupMember -identity "/o=ExchangeLabs/ou=Exchange Administrative Group (FYDIBOHF23SPDLT)/cn=Recipients/cn=d72ddffa90cb4129afd36639e698c064-OwlRockSG20"


#access to room calendars
$calendarIdentity = "owlrock@enchantedrock.com:\Calendar"
$userIdentityAdd = "kparekh@enchantedrock.com"
$userIdentityRemove = "Nikole Elliott-Harvest"

Add-MailboxFolderPermission -Identity $calendarIdentity -User $userIdentityAdd -AccessRights editor
Get-MailboxFolderPermission -Identity $calendarIdentity | Format-Table User,AccessRights -AutoSize 
Remove-MailboxFolderPermission -Identity $calendarIdentity -User $userIdentityRemove
