Get-CalendarProcessing -Identity "Owl Rock" | Format-List AllowDistributionGroup,BookInPolicy,RequestInPolicy,RequestOutOfPolicy

Get-DistributionGroup -identity "/o=ExchangeLabs/ou=Exchange Administrative Group (FYDIBOHF23SPDLT)/cn=Recipients/cn=d72ddffa90cb4129afd36639e698c064-OwlRockSG20" | FL
Get-DistributionGroupMember -identity "/o=ExchangeLabs/ou=Exchange Administrative Group (FYDIBOHF23SPDLT)/cn=Recipients/cn=d72ddffa90cb4129afd36639e698c064-OwlRockSG20"