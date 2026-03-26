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
Add-MailboxFolderPermission -Identity "Aimee Middleton:\Calendar" -User "Jessica Rohrbaugh" -AccessRights Editor
Remove-MailboxFolderPermission -Identity "Aimee Middleton:\Calendar" -User "Jessica Rohrbaugh" -Confirm:$false
 #>

Add-MailboxFolderPermission -Identity "Allen Schurr:\Calendar" -User "Jessica Rohrbaugh" -AccessRights Editor

Get-MailboxFolderPermission -Identity $calendarIdentity | Format-Table User,AccessRights -AutoSize