<#
Version 1.4.0 - 04/07/2026
- Security Enhancement - Updated Microsoft Graph authentication to use App-Only access with an Azure App Registration.
- Security Enhancement - Client Secret is now securely retrieved from Azure Key Vault instead of interactive login.
- Security Enhancement - Eliminates usage of delegated scopes and aligns with Microsoft security best practices.
- No functional changes to offboarding workflow logic.

Version 1.3.1 - 10/21/2025
- Improvements - Added proper logging of all terminal output via the 'Start-Transcript' cmdlet and removed all unnecessary 'write-output' cmdlet.
- Improvements - Added an additional check prior to running this script, to check if the proper version of Microsoft Graph PowerShell module is installed (version 2.30.0 or higher)

Version 1.3 - 08/28/2025
- Improvements - Some cases, terminated user was an owner of M365 groups as well as a member of those groups. In these rare cases, Microsoft 
  would not allow you remove the user as a member or the owner, without initially replacing the owner of the group. This has been resolved.
- Deprecation - AzureAD powershell module is no longer supported, therefore, we've updated this script to utilize the new "Graph" commands.
- Deprecation - Updated "$Get-AzureADCurrentSessionInfo" to "$CurrentSessionInfo = Get-MGContext"
- Deprecation - Updated Account Disabled function to the new "Graph" command.
- Deprecation - Updated Revoking of Sessions to new Graph command "Revoke-MgUserSignInSession".
- Deprecation - Updated all AzureAD commands in the function "Remove-UserFromAllGroups" to Graph PowerShell commands.

Version 1.2 - 5/06/2025
- Microsoft has finally deprecated the Connect-MsolService command. Although this script no longer relied on any MSOL commands, the "Connect-MsolService" function was still in this script, causing it to error out as of 05/06/2025. We simply removed that line from this script.

Version 1.1 - 04/02/2025
- Updated the function "Update-DisplayName" to ask the end-user running the script how long (60, 365, or indefinitely) we should keep this account will append "60", "365", or "HOLD" respectively to the Display Name"
- Added the function "RemoveProfilePic" to remove the end-user's profile picture upon offboarding.
- Added the function "AutoReply" to set an automatic reply on the shared mailbox while it's in the disabled state.

Version 1.0.1 - 02/25/2025
- Added the Disconnect-MgGraph command to run at the end of this script to manually disconnect any saved session. 
- Updated the 'InstallPowerShellModules.ps1' script to install/grab the latest PowerShell versions
Version 1.0 - 05/23/2024 - After creating our "Cybersecurity Runbook – Offboarding users via Offboarding PowerShell Script" runbook, we are ready to release it to our Helpdesk team.
Version 0.9 - 10/18/2023: 
10/18/2023 - Since the deprecation of MSOL commands, the function "Remove-UserLicense" started failing. 
			 Therefore, we called the new "Connect-MgGraph" command, and updated the function to use Get-MgUserLicenseDetail and Set-MgUserLicense

Role Based Access Control (RBAC) Minimum Requirements: 
User Administrator
Required to perform the following functions in the Offboarding script:
•	DisableUserAccount
•	UpdateDisplayName
•	Remove-UserLicense
•	Remove-UserFromAllGroups
Exchange Administrator
Required to perform the following functions in the Offboarding script:
•	CancelMeetings
•	ConvertTo-SharedMailbox
•	Remove-UserFromAllGroups
•	Set-MailboxForwarding

<#
.DESCRIPTION
Disables a user in Microsoft 365.
1. Grabs the user/usernames from what you entered and blocks sign-in to Microsoft 365.
2. Cancels all meetings which the user is set as the organizer (Currently turned off)
3. Revokes Azure AD Refresh Tokens via the "Revoke-AzureADUserAllRefreshToken" command to end all users token.
4. Converts the Mailbox to a Shared Mailbox.
5. Updates the Display Name appending "*DIS on 'todays date' - *DEL on 'date'"
6. Hides the mailbox from our GAL.
7. Finally, removes all Microsoft 365 licenses from the user.
8. Removes the user from all groups.
9. Asks if you want to forward email of this disabled user.
10. Removes the end-users profile picture.
11. Set an Auto Reply email for the mailbox.
12. Logs all output to a .txt file to be uploaded to the ticket.
#>


# Possible #11. Set Auto Reply on the mailbox? https://morgantechspace.com/2017/12/set-auto-reply-on-mailbox-in-office-365-powershell.html
#>

############################################################################
# Script Directory
############################################################################

$ScriptDir = Split-Path $script:MyInvocation.MyCommand.Path

############################################################################
# Azure / Graph / Key Vault Variables (NEW – App-Only Auth)
############################################################################

$TenantId      = "0bdf0e1f-a359-4b5c-9b79-9357e35ff8c6"
$ClientId      = "53bc912e-7f60-49bd-a8ea-3e27035e7fea"
$KeyVaultName  = "kv-offboardingM365script"
$SecretName    = "MgGraph-Client-Secret"

############################################################################
# Script Variables
############################################################################

$totaltime = 0

############################################################################
# Begin Script Logging
############################################################################

Start-Transcript -Path "$ScriptDir\Reports\EntraID-DisabledUser-$(Get-Date -Format yyyy-MM-dd_HH-mm-ss).txt" -Append

############################################################################
# CONNECT TO AZURE (Required for Key Vault Access)
############################################################################

Write-Host "Connecting to Azure..."

# Force-load required Az submodules (NoProfile-safe)
Import-Module Az.Accounts -ErrorAction Stop
Import-Module Az.KeyVault -ErrorAction Stop


# ------------------------------------------------------------
# Ensure correct DefaultSubscriptionForLogin (silent, idempotent)
# ------------------------------------------------------------

$DesiredSubscriptionId = "03866bcc-752b-4fd1-b5bb-cdd66aed21fb"  # Erock MS Subscription

try {
    $azConfig = Get-AzConfig -ErrorAction SilentlyContinue

    if (-not $azConfig.DefaultSubscriptionForLogin -or
        $azConfig.DefaultSubscriptionForLogin -ne $DesiredSubscriptionId) {

        Write-Host "Setting DefaultSubscriptionForLogin to 'Erock MS Subscription'..." -ForegroundColor Yellow

        Update-AzConfig `
            -DefaultSubscriptionForLogin $DesiredSubscriptionId `
            -Scope Process | Out-Null
    }
}
catch {
    Write-Host "WARNING: Could not set DefaultSubscriptionForLogin. $_" -ForegroundColor Yellow
}


Connect-AzAccount
# For automation use:
# Connect-AzAccount -Identity

############################################################################
# RETRIEVE CLIENT SECRET FROM AZURE KEY VAULT
############################################################################

Write-Host "Retrieving Microsoft Graph client secret from Azure Key Vault..."

$ClientSecret = Get-AzKeyVaultSecret `
    -VaultName $KeyVaultName `
    -Name $SecretName `
    -AsPlainText

if (-not $ClientSecret) {
    Write-Host "ERROR: Unable to retrieve client secret from Azure Key Vault." -ForegroundColor Red
    Stop-Transcript
    Exit 1
}

############################################################################
# CONNECT TO MICROSOFT GRAPH (APP-ONLY)
############################################################################

Write-Host "Connecting to Microsoft Graph using App Registration & Key Vault secret..."

$SecureSecret = ConvertTo-SecureString `
    -String $ClientSecret `
    -AsPlainText `
    -Force

$ClientSecretCredential = New-Object `
    System.Management.Automation.PSCredential `
    ($ClientId, $SecureSecret)

Connect-MgGraph `
    -TenantId $TenantId `
    -ClientSecretCredential $ClientSecretCredential `
    -NoWelcome

############################################################################
# CONNECT TO EXCHANGE ONLINE (UNCHANGED)
############################################################################

Write-Host "Connecting to Exchange Online..."
Connect-ExchangeOnline

############################################################################
# Begin Offboarding Logic (UNCHANGED)
############################################################################

Write-Host "`n`tEnter account names to disable in Entra ID." -ForegroundColor Yellow

function Disable-Everywhere {
    [cmdletbinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string[]]$Identity
    )

    foreach ($ID in $Identity) {
        SessionInfo
        DisableUserAccount
        ConvertTo-SharedMailbox
        Update-DisplayName
        Remove-UserLicense
        Remove-UserFromAllGroups
        Set-MailForwarding
        RemoveProfilePic
        AutoReply
        Write-Confirmation
    }
}

function SessionInfo {
    $script:CurrentSessionInfo = Get-MgContext
}

function DisableUserAccount {
    Write-Host "Disabling '$ID'"
    Update-MgUser -UserId $ID -AccountEnabled:$false
    Revoke-MgUserSignInSession -UserId $ID
}

function CancelMeetings {
	write-host "Cancelling all meetings where ""$($ID)"" is set as the organizer"
	Remove-CalendarEvents -Identity $ID -CancelOrganizedMeetings -QueryWindowInDays 1825 -Confirm:$False
}

function ConvertTo-SharedMailbox {
	$UserMailbox = get-mailbox $ID
	write-host "Changing the User Mailbox to a Shared Mailbox of ""$($ID)"""
	$UserMailbox | Set-Mailbox -type Shared
	write-host "Hiding mailbox from the GAL (Global Address List) of ""$($ID)"""
	$UserMailbox | Set-Mailbox -HiddenFromAddressListsEnabled $true	
		}


function Update-DisplayName {
    # Prompt the user for the time frame
    do {
        Write-Host "Select the time frame you want to disable this user?"
        Write-Host "(1) 60 days"
        Write-Host "(2) 365 days"
        Write-Host "(3) HOLD (Indefinitely)"
        
        $choice = Read-Host "Enter the number corresponding to your choice"

        if ($choice -notin "1", "2", "3") {
            Write-Host "Invalid selection. Please enter 1, 2, or 3."
        }
    } while ($choice -notin "1", "2", "3")

    # Determine the expiration date based on selection
    switch ($choice) {
        "1" { $DisableUntil = (Get-Date).AddDays(60) }
        "2" { $DisableUntil = (Get-Date).AddDays(365) }
        "3" { $DisableUntil = "(HOLD)" }
    }

    # Fetch the user
    Write-Host "Adding *DIS on and *DEL on dates to DisplayName of '$ID'"
    $User =  Get-MgUser -UserId $ID

    if ($User.DisplayName.StartsWith("*DIS")) {
        Write-Host "Note: *DIS already present on the DisplayName of '$ID', no update necessary."
    } else {
        # Construct the new display name
        $NewDisplayName = if ($DisableUntil -eq "(HOLD)") {
            "*DIS on $(Get-Date -f "MM/dd/yyyy") - (HOLD) - $($User.DisplayName)" 
        } else {
            "*DIS on $(Get-Date -f "MM/dd/yyyy") - *DEL on $($DisableUntil.ToString('MM/dd/yyyy')) - $($User.DisplayName)"
        }

        # Update the user
        Update-MgUser -UserId $ID -DisplayName $NewDisplayName
        Write-Host "Updated DisplayName: $NewDisplayName"
    }
}
function Remove-UserLicense {
	write-host "Removing all Microsoft 365 Licenses from ""$($ID)"""
		(Get-MgUserLicenseDetail -UserId $ID).SkuId |
		foreach{
			Set-MgUserLicense -UserId $ID -AddLicenses @() -RemoveLicenses @($_) -ErrorAction 'SilentlyContinue'
		}
}

function Remove-UserFromAllGroups {
	
		#Needed to handle pipeline input
		$GUIDs = @{}
		
			Start-Sleep -Milliseconds 80 #Add some delay to avoid throttling...
			#Make sure a matching security principal object is found and return its UPN
			write-host "Removing Group Memberships of ""$($ID)"""
			$GUID = Get-User $ID | Select-Object DistinguishedName, ExternalDirectoryObjectId
			if (!$GUID) { Write-Verbose "Security principal with identifier $ID not found, skipping..."; continue }
			elseif (($GUID.count -gt 1) -or ($GUIDs[$ID]) -or ($GUIDs.ContainsValue($GUID))) { Write-Verbose "Multiple users matching the identifier $ID found, skipping..."; continue }
			else { $GUIDs[$ID] = $GUID | Select-Object DistinguishedName, ExternalDirectoryObjectId }
		

			#Needed to handle array values for the Identity parameter
			foreach ($user in $GUIDs.GetEnumerator()) {
			Write-Verbose "Processing user ""$($user.Name)""..."
			Start-Sleep -Milliseconds 80 #Add some delay to avoid throttling...

			#Handle Exchange groups
			Write-Verbose "Obtaining group list for user ""$($user.Name)""..."
			$GroupTypes = @('GroupMailbox', 'MailUniversalDistributionGroup', 'MailUniversalSecurityGroup')
			$Groups = Get-Recipient -Filter "Members -eq '$($user.Value.DistinguishedName)'" -RecipientTypeDetails $GroupTypes | Select-Object DisplayName, ExternalDirectoryObjectId, RecipientTypeDetails | Where-Object { $_.DisplayName -ne 'Enchanted Rock'}
			if (!$Groups) { Write-Verbose "No matching groups found for ""$($user.Name)"", skipping..." }
			else { Write-Verbose "User ""$($user.Name)"" is a member of $(($Groups | Measure-Object).count) group(s)." }

			#Handling Unified/M365 Groups
 			write-host "Removing ""$($user.Name)"" from all Unified/M365 Groups"
			foreach ($Group in $Groups) {
				Write-Verbose "Removing user ""$($user.Name)"" from group ""$($Group.DisplayName)"""
				if ($Group.RecipientTypeDetails.Value -ne 'GroupMailbox') {
					try {Remove-UnifiedGroupLinks -Identity $Group.ExternalDirectoryObjectId -Links $user.Value.DistinguishedName -LinkType Member -Confirm:$false -WhatIf:$WhatIfPreference -ErrorAction 'SilentlyContinue'}
 					catch [System.Management.Automation.RemoteException] {
						#Some exceptions return the same category.reason RecipientTaskException. Using "exception" string match instead
						if ($_.CategoryInfo.Reason -eq 'ManagementObjectNotFoundException') { Write-Host 'ERROR: The specified object not found, this should not happen...' -ForegroundColor Red }
						#Seems they've updated the cmdlets to have unique error codes now, so account for that
						elseif ($_.CategoryInfo.Reason -eq 'RecipientTaskException' -and $_.Exception -match "Couldn't find object") { Write-Host "ERROR: User object ""$($user.Name)"" not found, this should not happen..." -ForegroundColor Red }
						elseif ($_.CategoryInfo.Reason -eq 'GroupOwnersCannotBeRemovedException' -or ($_.CategoryInfo.Reason -eq 'RecipientTaskException' -and $_.Exception -match 'Only Members who are not owners')) { Write-Host "ERROR: User object ""$($user.Name)"" is Owner of the ""$($Group.DisplayName)"" group and cannot be removed..." -ForegroundColor Red }
						elseif ($_.CategoryInfo.Reason -eq 'MinGroupOwnersCriteriaBreachedException' -or ($_.CategoryInfo.Reason -eq 'RecipientTaskException' -and $_.Exception -match "the person you're removing is currently the only owner")) { Write-Host "ERROR: User object ""$($user.Name)"" is the only Owner of the ""$($Group.DisplayName)"" group and cannot be removed..." -ForegroundColor Red }
						#no error is thrown if trying to remove a user that is not a member
						else { $_ | Format-List * -Force; continue } #catch-all for any unhandled errors
					}
					catch { $_ | Format-List * -Force; continue } #catch-all for any unhandled errors 
				}
				
			}
			
			#Handling Distribution Groups
			write-host "Removing ""$($user.Name)"" from all Distribution Groups"
			foreach ($Group in $Groups) {
				Write-Verbose "Removing user ""$($user.Name)"" from group ""$($Group.DisplayName)"""
				if ($Group.RecipientTypeDetails.Value -ne 'GroupMailbox') {
					try {Remove-DistributionGroupMember -Identity $Group.ExternalDirectoryObjectId -Member $user.Value.DistinguishedName -Confirm:$false -ErrorAction 'SilentlyContinue'}
  					 catch [System.Management.Automation.RemoteException] {
						if ($_.CategoryInfo.Reason -eq 'RecipientTaskException') { Write-Host 'ERROR: The specified object not found, this should not happen...' -ForegroundColor Red }
						elseif ($_.CategoryInfo.Reason -eq 'MemberNotFoundException') { Write-Host "ERROR: User ""$($user.Name)"" is not a member of the ""$($Group.DisplayName)"" group..." -ForegroundColor Red }
						else { $_ | Format-List * -Force; continue } #catch-all for any unhandled errors
					} 
					catch { $_ | Format-List * -Force; continue } #catch-all for any unhandled errors 
				}
			}

				# Handle Entra ID security groups using Microsoft Graph
				Write-Verbose "Obtaining security group list for user ""$($user.Name)""..."
				$GroupsEntraID = Get-MgUserMemberOf -UserId $user.Value.ExternalDirectoryObjectId -All | Where-Object {
					$_.'@odata.type' -eq "#microsoft.graph.group" -and $_.securityEnabled -eq $true -and $_.mailEnabled -eq $false -and $_.displayName -ne 'All Users'
				}

				if (!$GroupsEntraID) {
					Write-Verbose "No matching security groups found for ""$($user.Name)"", skipping..."
				} else {
					Write-Verbose "User ""$($user.Name)"" is a member of $(($GroupsEntraID | Measure-Object).count) security group(s)."
				}

				# Cycle over each Entra ID group
				foreach ($groupEntraID in $GroupsEntraID) {
					Write-Verbose "Removing user ""$($user.Name)"" from group ""$($groupEntraID.displayName)"""

					if (!$WhatIfPreference) {
						try {
							$uri = "https://graph.microsoft.com/v1.0/groups/$($groupEntraID.Id)/members/$($user.Value.ExternalDirectoryObjectId)/`$ref"
							Invoke-MgGraphRequest -Method DELETE -Uri $uri
						}
						catch {
							if ($_.Exception.Message -match '.*Insufficient privileges to complete the operation') {
								Write-Host "ERROR: You cannot remove members of the ""$($groupEntraID.DisplayName)"" Dynamic group, adjust the membership filter instead..." -ForegroundColor Red
							}
							elseif ($_.Exception.Message -match '.*Invalid object identifier') {
								Write-Host "ERROR: Group ""$($groupEntraID.DisplayName)"" not found, this should not happen..." -ForegroundColor Red
							}
							elseif ($_.Exception.Message -match '.*Unsupported referenced-object resource identifier') {
								Write-Host "ERROR: User ""$($user.Name)"" not found, this should not happen..." -ForegroundColor Red
							}
							elseif ($_.Exception.Message -match '.*does not exist or one of its queried reference-property') {
								Write-Host "ERROR: User ""$($user.Name)"" is not a member of the ""$($groupEntraID.DisplayName)"" group..." -ForegroundColor Red
							}
							else {
								$_ | Format-List * -Force
								continue
							}
						}
					}
					else {
						Write-Host 'WARNING: Microsoft Graph cmdlets do not natively support -WhatIf, action was skipped...'
					}
				}

			#Handle M365 Groups where the $ID is the owner of the group, requiring a new owner, before successful removal of $ID
			# Resolve $ID to ObjectId and UPN for consistent comparisons
			try {
    			$userObj = Get-MgUser -UserId $ID -ErrorAction Stop
    			$userObjectId = $userObj.Id
    			$userUPN = $userObj.UserPrincipalName
			} catch {
    			Write-Host "User $ID not found in Microsoft Graph." -ForegroundColor Red
    			return
			}

			# Get all Unified (M365) groups
			$groups = Get-MgGroup -Filter "groupTypes/any(c:c eq 'Unified')" -All
			$totalGroups = $groups.Count
			$counter = 0

			foreach ($group in $groups) {
				$counter++
				Write-Progress -PercentComplete (($counter / $totalGroups) * 100) `
					-Activity "Processing Groups" `
					-Status "Processing group $counter of $totalGroups $($group.DisplayName)"

				# Get all owners of this group
				$owners = Get-MgGroupOwner -GroupId $group.Id -All

				# Check if target user is an owner
				$isOwner = $owners | Where-Object {
					$_.Id -eq $userObjectId -or $_.AdditionalProperties.userPrincipalName -eq $userUPN
				}

				if ($isOwner) {
					Write-Host "`nGroup Name: $($group.DisplayName) ($($group.Id))" -ForegroundColor Yellow
					Write-Host "$userUPN is an OWNER of this group." -ForegroundColor Yellow

							# Prompt for replacement owner until valid
					do {
						Write-Host "`nChoose how to set the replacement owner for '$($group.DisplayName)':" -ForegroundColor Cyan
						Write-Host "1. Use the manager of $userUPN as the new/replacement owner."
						Write-Host "2. Manually enter the new UPN of the owner."
						$choice = Read-Host "Enter 1 or 2"

						$valid = $false

						switch ($choice) {
							"1" {
								try {
									# Get manager reference (only returns Id)
									$managerRef = Get-MgUserManager -UserId $userObjectId -ErrorAction Stop
									
									if ($null -ne $managerRef) {
										# Expand into full user object
										$managerObj  = Get-MgUser -UserId $managerRef.Id -ErrorAction Stop
										$managerUPN  = $managerObj.UserPrincipalName
										$managerName = $managerObj.DisplayName

										Write-Host "Manager found: $managerName <$managerUPN>" -ForegroundColor Green
										$confirm = Read-Host "Use this manager as the new owner? (Y/N)"
										if ($confirm -match "^[Yy]$") {
											$newOwnerObj = $managerObj
											$newOwnerUPN = $managerUPN
											$newOwnerId  = $managerObj.Id
											$valid = $true
										}
									} else {
										Write-Host "No manager found for $userUPN. Falling back to manual entry..." -ForegroundColor Yellow
										$choice = "2"
									}
								} catch {
									Write-Host "No manager found for $userUPN. Falling back to manual entry..." -ForegroundColor Yellow
									$choice = "2"
								}
							}
							"2" {
								$newOwnerUPN = Read-Host "Enter the UPN of the new owner for '$($group.DisplayName)'"
								try {
									$newOwnerObj = Get-MgUser -UserId $newOwnerUPN -ErrorAction Stop
									$newOwnerId = $newOwnerObj.Id
									$valid = $true
								} catch {
									Write-Host "User not found. Please enter a valid UPN." -ForegroundColor Yellow
									$valid = $false
								}
							}
							Default {
								Write-Host "Invalid selection. Please enter 1 or 2." -ForegroundColor Yellow
							}
						}
					} while (-not $valid)

					# Add new owner
					try {
						$newGroupOwner =@{
						"@odata.id"= "https://graph.microsoft.com/v1.0/users/{$newOwnerId}"
						}
						New-MgGroupOwnerByRef -GroupId $group.Id -BodyParameter $newGroupOwner
						Write-Host "Added new owner: $newOwnerUPN" -ForegroundColor Yellow

						# Remove original owner(s)
						foreach ($owner in $isOwner) {
							Remove-MgGroupOwnerByRef -GroupId $group.Id -DirectoryObjectId $owner.Id
							Write-Host "Removed $userUPN from owners." -ForegroundColor Yellow
						}

						# Remove as member if applicable
						$members = Get-MgGroupMember -GroupId $group.Id -All
						$isMember = $members | Where-Object {
							$_.Id -eq $userObjectId -or $_.AdditionalProperties.userPrincipalName -eq $userUPN
						}

						foreach ($member in $isMember) {
							Remove-MgGroupMemberByRef -GroupId $group.Id -DirectoryObjectId $member.Id
							Write-Host "Removed $userUPN from group members." -ForegroundColor Yellow
						}

						if (-not $isMember) {
							Write-Host "$userUPN is not a member of this group." -ForegroundColor Yellow
						}

					} catch {
						Write-Host "Failed to add/remove owner/member: $_" -ForegroundColor Red
					}
				}
			}

			Write-Progress -PercentComplete 100 -Activity "Processing Groups" -Status "Finished processing groups."
			Write-Host "Processing complete." -ForegroundColor Green



}
}
function Set-MailForwarding {
	while ($mailboxforwardingprompt -ne 'y' -and $mailboxforwardingprompt -ne 'n') {
	$mailboxforwardingprompt = read-host -prompt "Would you like to set mailbox forwarding for this user [y/n]?"}
	if ($mailboxforwardingprompt -eq 'y') {
    $forwardingmailbox = read-host -prompt "Enter the forwarding email address"
	Set-Mailbox -Identity $ID -DeliverToMailboxAndForward $true -ForwardingSMTPAddress $forwardingmailbox
	}
	elseif ($mailboxforwardingprompt -eq 'n') {
    }
}

function RemoveProfilePic {
	write-host "Removing profile picture of ""$($ID)"""
	Remove-MgUserPhoto -UserID $ID
}

function AutoReply {
	write-host "Setting an automatic reply for emails sent to: ""$($ID)"""
	$AutoReplyMessage = "This mailbox is no longer being monitored. Your email has been forwarded if applicable."
	Set-MailboxAutoReplyConfiguration -Identity $ID `
    -AutoReplyState Enabled `
    -InternalMessage $AutoReplyMessage `
    -ExternalMessage $AutoReplyMessage `
    -ExternalAudience All
}


function Write-Confirmation {
	write-host "------------------------User ""$($ID)"" has been disabled------------------------"
}


try {
    # First functions that will execute
    Disable-Everywhere
    Disconnect-MgGraph
}
finally {
    # Always release the transcript file handle
    try { Stop-Transcript | Out-Null } catch {}
}


