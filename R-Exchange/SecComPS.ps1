Import-Module ExchangeOnlineManagement
Connect-IPPSSession -UserPrincipalName admin-dr@enchantedrock.com

Import-Module Microsoft.Graph.Beta.Identity.DirectoryManagement
Connect-MgGraph -Scopes "Directory.ReadWrite.All"

$grpUnifiedSetting = Get-MgBetaDirectorySetting | Where-Object { $_.Values.Name -eq "EnableMIPLabels" }
$grpUnifiedSetting.Values

$params = @{
     Values = @(
 	    @{
 		    Name = "EnableMIPLabels"
 		    Value = "True"
 	    }
     )
}
Update-MgBetaDirectorySetting -DirectorySettingId $grpUnifiedSetting.Id -BodyParameter $params

Execute-AzureAdLabelSync

(user.accountEnabled -eq true) 
and (user.userType -eq "member") 
and (user.employeeId -ne "svcaccount") 
and (user.employeeId -ne "adminaccount") 
and (user.displayName -notContains "DIS HOLD") 
and (user.displayName -notContains "DIS on") 
and (user.jobtitle -notContains "Contractor") 
and (user.UserPrincipalName -notContains "-sc") 
and (user.UserPrincipalName -notContains "admin-") 
and (user.extensionAttribute15 -ne "EORemoveException") 
or (user.extensionAttribute15 -eq "EOAddException")