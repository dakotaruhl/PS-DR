#Set Parameters
$AdminCenterURL="https://enchantedrock-admin.sharepoint.com/"
#user with the ID mismatch
$UserLoginID = "i:0#.f|membership|test.user@enchantedrock.com"
#enter user, that is sharepoint admin
$SiteCollectionAdmin = "admin-dr@enchantedrock.com"

#import PowerShell 7 SPO
Import-Module Microsoft.Online.SharePoint.PowerShell -UseWindowsPowerShell

$Thumbprint = "C47B91EB62634CA61FA8146DDA83B8BF605C0962"
$ClientID = "ea2ca49b-d0df-4774-b611-86cf9dc9629f"
$TenantID = "0bdf0e1f-a359-4b5c-9b79-9357e35ff8c6"

$credential = Get-Credential -Credential "admin-dr@enchantedrock.com"
#Connect to SharePoint Online
Connect-SPOService -Url $AdminCenterURL -ClientId $ClientID -TenantId $TenantID -CertificateThumbprint $Thumbprint 
Connect-SPOService -Url $AdminCenterURL -Credential $credential -ModernAuth $true -AuthenticationUrl "https://login.microsoftonline.com/"
#Get all Personal Site collections`
$PSitesUrl = Get-SPOSite -Template "SPSPERS" -limit ALL -includepersonalsite $True | Select URL, LockState

$count = 0
$disabledUsersFound = @()
Foreach ($PSite in $PSitesUrl)
{	
	$count++
	Write-Host "Processing $count of $($PSitesUrl.Count): $($PSite.URL)" -ForegroundColor Cyan

	If($PSite.LockState -ne "Unlock") 
	{
		Write-Host "Site $($PSite.URL) is locked. Skipping..." -ForegroundColor Yellow
		continue
	}	

	try 
	{
        # Add Site Collection Admin
        Set-SPOUser -Site $PSite.Url -LoginName $SiteCollectionAdmin -IsSiteCollectionAdmin $true -ErrorAction Stop | Out-Null

        # Collect disabled users
		$disabledUsers = Get-SPOUser -Limit All -Site $PSite.Url | Where-Object { $_.DisplayName -like '*DIS*' }
        $disabledUsersFound += $disabledUsers | ForEach-Object {
                [PSCustomObject]@{
                    Name      = $_.DisplayName
                    LoginName = $_.LoginName
                    Site      = $PSite.Url
                }
            }

		#remove the user from "All people" personal site
		Foreach ($user in $disabledUsersFound) 
		{
			Write-Host "Removing $($user.LoginName) from $($user.Site)" -ForegroundColor Red
			Remove-SPOUser -Site $PSite.URL -LoginName $user.LoginName
    	}
    }
    catch 
	{
        Write-Warning "Error processing $($PSite.Url): $($_.Exception.Message)"
    }
    finally 
	{
        # Always remove admin if it was added
        try 
		{
            Set-SPOUser -Site $PSite.Url -LoginName $SiteCollectionAdmin -IsSiteCollectionAdmin $false -ErrorAction SilentlyContinue | Out-Null
        }
        catch {}
    }
}


Export-Excel -InputObject ($disabledUsersFound | Sort-Object LoginName, Site -Unique) -Path "C:\Users\DakotaRuhl\Documents\Reports\OneDrive DisabledUsers\DisabledUsersFound.xlsx" -AutoSize

#Remove admin from single site collection
<# $PSiteUrl = "https://enchantedrock-my.sharepoint.com/personal/bsatterfield_enchantedrock_com"
$SiteCollectionAdmin = "admin-dr@enchantedrock.com"

Get-SPOUser -Site $PSiteUrl -LoginName $SiteCollectionAdmin | FL
Set-SPOUser -site $PSiteUrl -LoginName $SiteCollectionAdmin -IsSiteCollectionAdmin $False

### Single Site Removal ###

##Check UPN on site access list
Get-SPOUser https://enchantedrock-my.sharepoint.com/personal/druhl_enchantedrock_com | Where-Object -Property LoginName -eq 'test.user@enchantedrock.com'
Get-SPOUser https://enchantedrock-my.sharepoint.com/personal/bsatterfield_enchantedrock_com | Where-Object -Property LoginName -like 'DIS'

##Set OneDrive site, admin, and User to remove
$PSiteUrl = "https://enchantedrock-my.sharepoint.com/personal/bsatterfield_enchantedrock_com"
$SiteCollectionAdmin = "admin-dr@enchantedrock.com"
$UserLoginID = "i:0#.f|membership|manguiano@enchantedrock.com"

#Remove user from access list
Remove-SPOUser -Site $PSiteUrl -LoginName $UserLoginID

#Remove yourself from SiteCollectionAdmins
Set-SPOUser -site $PSiteUrl -LoginName $SiteCollectionAdmin -IsSiteCollectionAdmin $False
Get-SPOUser -Site $PSiteUrl -LoginName $SiteCollectionAdmin | FL #>


Get-ChildItem Cert:\CurrentUser\My | Where-Object {$_.Thumbprint -eq "C47B91EB62634CA61FA8146DDA83B8BF605C0962"}

Get-ChildItem Cert:\LocalMachine\My | Where-Object {$_.Thumbprint -eq "C47B91EB62634CA61FA8146DDA83B8BF605C0962"}

$cert = Get-ChildItem Cert:\CurrentUser\My\C47B91EB62634CA61FA8146DDA83B8BF605C0962
$cert.HasPrivateKey

$cert = Get-ChildItem Cert:\CurrentUser\My\C47B91EB62634CA61FA8146DDA83B8BF605C0962
$cert | Format-List *
