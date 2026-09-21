# Room List (distribution group containing room mailboxes)
# Get-DistributionGroup -RecipientTypeDetails RoomList |
#    Format-Table DisplayName,PrimarySmtpAddress
$RoomList = "Hyperion Rooms"

# Mail-enabled security group receiving Editor access
$AccessGroup = "HYP-Rooms-CalendarAccess"

# Get all rooms in the room list
$Rooms = Get-DistributionGroupMember -Identity $RoomList |
    Where-Object { $_.RecipientTypeDetails -eq 'RoomMailbox' }

foreach ($Room in $Rooms) {
    $CalendarFolder = "$($Room.PrimarySmtpAddress):\Calendar"

    try {
        # Check if permission already exists
        $Existing = Get-MailboxFolderPermission `
            -Identity $CalendarFolder `
            -User $AccessGroup `
            -ErrorAction SilentlyContinue

        if (-not $Existing) {
            Add-MailboxFolderPermission `
                -Identity $CalendarFolder `
                -User $AccessGroup `
                -AccessRights Editor `
                -ErrorAction Stop

            Write-Host "Added Editor to $CalendarFolder" -ForegroundColor Green
        }
        elseif ($Existing.AccessRights -notcontains "Editor") {
            Set-MailboxFolderPermission `
                -Identity $CalendarFolder `
                -User $AccessGroup `
                -AccessRights Editor `
                -ErrorAction Stop

            Write-Host "Updated to Editor on $CalendarFolder" -ForegroundColor Yellow
        }
        else {
            Write-Host "Already Editor on $CalendarFolder" -ForegroundColor Cyan
        }
    }
    catch {
        Write-Warning "Failed on $CalendarFolder : $_"
    }
}

# Remove old room
Remove-DistributionGroupMember `
    -Identity $RoomList `
    -Member "White Sands" `
    -Confirm:$false

# Add new room
Add-DistributionGroupMember `
    -Identity $RoomList `
    -Member "Banff"