# Users or groups to add/remove
$userIdentityAdd = "Room Calendar Editors"
$userIdentitiesRemove = @(
    "Alexis Campbell"
    "Charity Cortez"
    "Randy Atkinson"
)

#Room list to process
# Vine Rooms 
# Titan Rooms
# Hyperion Rooms
$roomListName = "Titan Rooms"

# Get all rooms
$roomList = Get-DistributionGroup `
    -RecipientTypeDetails RoomList `
    -Identity $roomListName 

$teamsRooms = Get-DistributionGroupMember -Identity $roomList.Identity |
    Where-Object { $_.RecipientTypeDetails -eq "RoomMailbox" }

$calendarPermissions = @()

# Iterate through each room and update permissions
foreach ($room in $teamsRooms) {
    $calendarIdentity = "$($room.PrimarySmtpAddress):\Calendar"

    Write-Host "`nProcessing $($room.DisplayName)..." -ForegroundColor Cyan

    try {
        $newPermissions = Get-MailboxFolderPermission `
            -Identity $calendarIdentity `
            -ErrorAction Stop
    }
    catch {
        Write-Warning "Could not retrieve permissions for $($room.DisplayName): $($_.Exception.Message)"
        continue
    }

    $currentPermissionUsers = @(
        $newPermissions.User |
            ForEach-Object { $_.ToString() }
    )

    # Add the requested identity when it does not already have permissions
    if ($currentPermissionUsers -notcontains $userIdentityAdd) {
        try {
            Add-MailboxFolderPermission `
                -Identity $calendarIdentity `
                -User $userIdentityAdd `
                -AccessRights Editor `
                -ErrorAction Stop

            Write-Host "Added $userIdentityAdd to $($room.DisplayName)." -ForegroundColor Green
        }
        catch {
            Write-Warning "Could not add $userIdentityAdd to $($room.DisplayName): $($_.Exception.Message)"
        }
    }
    else {
        Write-Host "$userIdentityAdd already has permissions for $($room.DisplayName). Skipping..." -ForegroundColor Yellow
    }

    # Remove each requested identity when it has permissions
    foreach ($userIdentityRemove in $userIdentitiesRemove) {
        if ($currentPermissionUsers -contains $userIdentityRemove) {
            try {
                Remove-MailboxFolderPermission `
                    -Identity $calendarIdentity `
                    -User $userIdentityRemove `
                    -Confirm:$false `
                    -ErrorAction Stop

                Write-Host "Removed $userIdentityRemove from $($room.DisplayName)." -ForegroundColor Red
            }
            catch {
                Write-Warning "Could not remove $userIdentityRemove from $($room.DisplayName): $($_.Exception.Message)"
            }
        }
        else {
            Write-Host "$userIdentityRemove does not have permissions for $($room.DisplayName). Skipping..." -ForegroundColor Yellow
        }
    }

    # Retrieve the final permission state once after all changes
    try {
        $newPermissions = Get-MailboxFolderPermission `
            -Identity $calendarIdentity `
            -ErrorAction Stop
    }
    catch {
        Write-Warning "Could not retrieve final permissions for $($room.DisplayName): $($_.Exception.Message)"
        continue
    }

    Write-Host "Final permissions for $($room.DisplayName):" -ForegroundColor Green
    $newPermissions | Format-Table User, AccessRights -AutoSize

    $calendarPermissions += $newPermissions |
        Where-Object {
            $_.AccessRights -and
            $_.AccessRights -notcontains "None"
        } |
        ForEach-Object {
            [PSCustomObject]@{
                Room         = $room.DisplayName
                User         = $_.User.ToString()
                AccessRights = $_.AccessRights -join ", "
            }
        }
}

$exportPath = "C:\Users\DakotaRuhl\Documents\Reports\Calendar Permissions\$($roomListName).xlsx"

$calendarPermissions |
    Export-Excel `
        -Path $exportPath `
        -WorksheetName "Permissions" `
        -AutoSize `
        -TableName "CalendarPermissions"

Write-Host "`nPermission report exported to: $exportPath" -ForegroundColor Cyan