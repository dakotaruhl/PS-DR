Connect-MgGraph -Scopes "Group.Read.All"
Import-Module Microsoft.Graph.Authentication
Import-Module Microsoft.Graph.Groups

$AllGroups = Get-MgGroup -All 

#Parameters
#$TenantURL =  "https://enchantedrock.sharepoint.com"
$UserID= "i:0#.f|membership|druhl@enchantedrock.com"

#Frame Tenant Admin URL from Tenant URL
#$TenantAdminURL = $TenantURL.Insert($TenantURL.IndexOf("."),"-admin")
#Connect to PnP Online
#Connect-PnPOnline -URL $TenantAdminURL -Interactive -ClientId 4ac6eede-e81e-4d22-abad-0d43c51486f2

#establish permissions collection
#$PermissionCollection = @()
$singleSite = "https://enchantedrock.sharepoint.com/sites/contenttesting"
Connect-PnPOnline -Url $singleSite -Interactive -ClientId 4ac6eede-e81e-4d22-abad-0d43c51486f2

#Get All Site collections - Filter BOT and MySite Host
#$Sites = Get-PnPTenantSite -Filter "Url -like '$TenantURL'"
 
<#Iterate through all sites
$Sites | ForEach-Object { 
    Write-host "Searching in Site Collection:"$_.URL -f Yellow
    #Connect to each site collection
    Connect-PnPOnline -Url $_.URL -Interactive -ClientId 4ac6eede-e81e-4d22-abad-0d43c51486f2
#>
    #If((Get-PnPUser | Where {$_.LoginName -eq $UserID}) -ne $NULL)
    If($NULL -ne (Get-PnPUser | Where-Object {$_.LoginName -eq $UserID}))
    {
        $SPGroups = Get-PnPGroup 
        foreach ($Group in $SPGroups) 
        {
            Write-Host "Checking SP Group:"$Group.Title -f Yellow
            $SPGroupMembers = Get-PnPGroupMember -Identity $Group.Title
            foreach ($SPMember in $SPGroupMembers) 
            {
                #Check if user is a member of the Site Entra Group
                if($SPMember.Title -contains "Members" -or $SPMember.Title -contains "Owners")         #Check if user is a member of the group
                {
                $EntraGroupName = $SPMember.Title.Replace(" Members","").Replace(" Owners","")
                Get-MgGroup -Filter "DisplayName eq '$EntraGroupName'" | ForEach-Object { $EntraGroupID = $_.Id }
                $NestedGroupMembers = Get-MgGroupMember -GroupId $EntraGroupID
                $NestedGroupOwners = Get-MgGroupOwner -GroupId $EntraGroupID
                #User is found as member in Entra Group
                foreach ($user in $NestedGroupMembers) 
                {
                    $user = Get-MgUser -UserId $user.Id
                    if ($user.UserPrincipalName -eq $UserID.Replace("i:0#.f|membership|","")) 
                    {
                        Write-host "`tUser " $user.UserPrincipalName " Found in SP Group:" $Group.Title " within Entra Group: " $EntraGroupName "as a member"-f Green
                        #Remove user from nested group
                        Remove-MgGroupMemberByRef -GroupId $EntraGroupID -DirectoryObjectId $user.Id
                        Write-host "`tRemoved the User from Nested Group:"$EntraGroupName "within Group:"$Group.Title -f Green
                    }
                }
                #User is found as Owner in Entra Group
                foreach ($user in $NestedGroupOwners) 
                {
                    $user = Get-MgUser -UserId $user.Id
                    if ($user.UserPrincipalName -eq $UserID.Replace("i:0#.f|membership|","")) 
                    {
                        Write-host "`tUser " $user.UserPrincipalName " Found in SP Group:" $Group.Title " within Entra Group: " $EntraGroupName "as an Owner"-f Green
                        if($NestedGroupOwners.Count -le 1)
                        {
                            Write-host "`tCannot remove the User from Nested Group:"$EntraGroupName " within Group:"$Group.Title "as they are the only Owner"-f Red
                            continue
                        }
                        else {
                            #Remove user from nested group
                            Remove-MgGroupOwnerDirectoryObjectByRef -GroupId $EntraGroupID -DirectoryObjectId $user.Id
                            Write-host "`tRemoved the User:" $user.UserPrincipalName " Found in SP Group:" $Group.Title " within Entra Group:" $EntraGroupName " as an Owner" -f Green
                        }
                        
                    }
                }
                #User is member of SharePoint Group directly
                else 
                {
                    $NestedGroupMembers = @($SPMember)
                    foreach ($user in $NestedGroupMembers) 
                    {
                        if ($user.LoginName -eq $UserID) 
                        {
                            Write-host "`tUser " $user.LoginName " Found in Nested Group:" $Group.Title -f Green
                            #Remove user from nested group
                            Remove-PnPGroupMember -Group $member.LoginName -LoginName $UserID
                            Write-host "`tRemoved the User: " $member.LoginName " from Nested Group:"  "within Group:" $Group.Title -f Green
                        }
                    }
                }
                
            }
            #User is added directly to SharePoint Site 
            Write-host "`tUser Found in Group:"$Group.Title -f Green
            #Remove user from group
            Remove-PnPGroupMember -Group $Group.Title -LoginName $UserID
            Write-host "`tRemoved the User from Group:"$Group.Title -f Green
        }
        <#Report user from site collection
        $Permissions = New-Object PSObject
        $Permissions | Add-Member NoteProperty User($_.Title)
        $Permissions | Add-Member NoteProperty URL($_.URL)
        $PermissionCollection += $Permissions
        $ReportFile = "C:\Users\DakotaRuhl\Documents\Reports\Permission Reports\PDiSanto\$($_.Title)_Permissions.csv"
        Write-host "`tUser Found in Site:"$_.URL -f Green
        $PermissionCollection | Export-CSV $ReportFile -NoTypeInformation -Append
        #Remove-PnPUser -Identity $UserID -Confirm:$false
        #Write-host "`tRemoved the User from Site:"$_.URL -f Green
        #>
    }
} 
Connect-ExchangeOnline
Set-UnifiedGroup -Identity 2775d79c-5894-4306-89ce-b033b32a78b2 -HiddenFromExchangeClientsEnabled:$false -HiddenFromAddressListsEnabled:$false

