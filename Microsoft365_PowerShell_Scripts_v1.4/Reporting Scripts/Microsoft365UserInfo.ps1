$ScriptDir = Split-Path $script:MyInvocation.MyCommand.Path
write-Output "EmployeeID,Display Name,Job Title,Email Address,ManagerUPN" | Out-file -encoding UTF8 $ScriptDir\Reports\Microsoft365_userinfo-$(get-date -f yyyy-MM-dd).csv

# Check Azure AD Access token
# Connect-AzureAD
if ($null -eq $AzureADSession::AccessTokens){
    Connect-AzureAD
} else {
    $token = $AzureADSession::AccessTokens
    Write-Verbose "Connected to tenant: $($token.AccessToken.TenantId) with user: $($token.AccessToken.UserId)"
}
$AD=(get-azureaduser -all $true -Filter "userType eq 'Member' and AccountEnabled eq true").userprincipalname 
foreach ($user in $AD){
			$empinfo = Get-AzureADUser -ObjectId $user | Select-Object displayname,jobtitle,mail, extensionproperty, @{l='ManagerUPN';e={($_ | Get-AzureADUserManager).UserPrincipalName}}
			$empid = $empinfo.extensionproperty.get_item("employeeId")
			$dispname = $empinfo.displayname
			$jobtitle = $empinfo.jobtitle
			$mailaddress = $empinfo.mail
			$managerUPN = $empinfo.ManagerUPN
	
	#write information out in shell
			write-host EmployeeID: $empid
			write-host Displayname: $dispname
			write-host JobTitle: $jobtitle
			write-host Email Address: $mailaddress
			write-host Manager: $managerUPN
			write-host
	
	#send information to file
			write-Output $empid","$dispname","$jobtitle","$mailaddress","$managerUPN | Out-file -encoding UTF8 $ScriptDir\Reports\Microsoft365_userinfo-$(get-date -f yyyy-MM-dd).csv -Append
}
