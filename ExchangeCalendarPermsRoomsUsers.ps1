#Connect-ExchangeOnline

#User to add/Remove
$userIdentityAdd = "Room Calendar Editors"
$userIdentityRemove = "Tiffany Amaya"

# Get all rooms
$teamsRooms = Get-Mailbox -RecipientTypeDetails RoomMailbox
#$room = $teamsRooms[0]
$calendarPermissions = @()
# Iterate through each room and update permissions 
foreach ($room in $teamsRooms) 
{
    $calendarIdentity = "$($room.primarySmtpAddress):\Calendar"
    $newPermissions = Get-MailboxFolderPermission -Identity $calendarIdentity

    if( ($newPermissions.user | ForEach-Object { $_.ToString() }) -notcontains $userIdentityAdd) 
    {
        # Add the user with Editor permissions if they don't already have permissions
        Add-MailboxFolderPermission -Identity $calendarIdentity -User $userIdentityAdd -AccessRights Editor
        $newPermissions = Get-MailboxFolderPermission -Identity $calendarIdentity
        Write-Host "Added $userIdentityAdd to $($room.DisplayName) permissions." -ForegroundColor Green
    }
    else {
         Write-Host "$userIdentityAdd already has permissions for $($room.DisplayName). Skipping..." -ForegroundColor Yellow
    }

    if( ($newPermissions.user | ForEach-Object { $_.ToString() }) -contains $userIdentityRemove) 
    {
        # Remove the user if they have permissions
        Remove-MailboxFolderPermission -Identity $calendarIdentity -User $userIdentityRemove -Confirm:$false
        $newPermissions = Get-MailboxFolderPermission -Identity $calendarIdentity
        Write-Host "Removed $userIdentityRemove from $($room.DisplayName) permissions." -ForegroundColor Red
    }
    else {
         Write-Host "$userIdentityRemove does not have permissions for $($room.DisplayName). Skipping..." -ForegroundColor Yellow
    }
    
    Write-Host "Updated permissions for $($room.DisplayName):" -ForegroundColor Green
    $newPermissions | Format-Table User,AccessRights -AutoSize 
    $calendarPermissions += $newPermissions |
        Where-Object { $_.AccessRights -and ($_.AccessRights -notcontains 'None') } |
        ForEach-Object {
            [PSCustomObject]@{
                Room         = $room.DisplayName
                User         = $_.User.ToString()
                AccessRights = ($_.AccessRights -join ', ')
            }
        }
}

Export-Excel -Path "C:\Users\DakotaRuhl\Documents\Reports\Calendar Permissions\AllRooms3.xlsx" -WorksheetName "Permissions" -AutoSize -TableName "CalendarPermissions" -InputObject $calendarPermissions

#Remove-MailboxFolderPermission -Identity $calendarIdentity -User $userIdentityRemove
#Get-MailboxFolderPermission -Identity $calendarIdentity | Format-Table User,AccessRights -AutoSize 

#expand the "Er Calendar Owners" user
#Get-MailboxFolderPermission -Identity $calendarIdentity -User "ER Calender Owners"

#$allRooms = $teamsRooms | ForEach-Object { $_.DisplayName }

<# Get-MailboxFolderPermission -Identity "Aimee Middleton:\Calendar" | Format-Table User,AccessRights -AutoSize 
Add-MailboxFolderPermission -Identity "Octavio :\Calendar" -User "Dakota Ruhl" -AccessRights Owner
Remove-MailboxFolderPermission -Identity "Aimee Middleton:\Calendar" -User "Jessica Rohrbaugh" -Confirm:$false
 #>



$UPN = "nherr@erock.com"
$calendarIdentity = "$($UPN):\Calendar"
$userIdentityAdd = "tamaya@erock.com"
Get-MailboxFolderPermission -Identity $calendarIdentity | Format-Table -AutoSize 
Get-MailboxPermission -Identity $UPN
Get-Mailbox $UPN | FL

Remove-MailboxFolderPermission -Identity $calendarIdentity -User $userIdentityAdd -Confirm:$false
Remove-MailboxFolderPermission -Identity $calendarIdentity -User "Joseph Obebeduo" -Confirm:$false
Set-MailboxFolderPermission -Identity "IBlakely@enchantedrock.com:\Calendar" -User "Default" -AccessRights AvailabilityOnly 
Set-MailboxFolderPermission -Identity $calendarIdentity -User $userIdentityAdd -AccessRights Owner
Add-MailboxFolderPermission -Identity $calendarIdentity -User $userIdentityAdd -AccessRights Owner -SharingPermissionFlags Delegate, CanViewPrivateItems

Add-MailboxFolderPermission -Identity $calendarIdentity -User $userIdentityAdd -AccessRights Owner

Sales solution meeting prep
Sales solution meeting

$title = "Sales solution meeting prep"
$adminEmail = "admin-dr@enchantedrock.com"
$meetings = Get-Mailbox -ResultSize Unlimited | Get-CalendarDiagnosticObjects -ResultSize Unlimited | Where-Object { $_.Subject -eq $title }
$meetings | Select-Object OrganizerName, OrganizerSmtpAddress, StartTime, EndTime 

Get-MailboxAutoReplyConfiguration -Identity $UPN

$guid = (get-mailbox -Identity "nherr@erock.com" | select-object -ExpandProperty exchangeguid)
Get-InboxRule -Mailbox $guid.Guid -includehidden

Get-InboxRule -Mailbox nherr@erock.com -IncludeHidden |
    Where-Object {$_.Name -like "Delegate Rule*"} |
    Format-List *