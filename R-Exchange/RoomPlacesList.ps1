

#Get-DistributionGroup -RecipientTypeDetails RoomList | Format-Table DisplayName, Identity, PrimarySmtpAddress –AutoSize


# Get all room lists
$roomLists = Get-DistributionGroup -ResultSize Unlimited -RecipientTypeDetails RoomList
$roomList = $roomLists[0]
# Iterate through each room list, then each room in the list, and assign rooms to 24/7 availability. 
foreach ($roomList in $roomLists) 
{
    Write-Host "Room List: $($roomList.DisplayName)" -ForegroundColor Cyan
    Get-DistributionGroupMember -Identity $roomList.Identity | Format-Table DisplayName, PrimarySmtpAddress
    Write-Host ""
    $rooms = Get-DistributionGroupMember -Identity $roomList.Identity | Where-Object {$_.RecipientTypeDetails -eq "RoomMailbox"}

    foreach ($room in $rooms) 
    {
        Write-Host "Setting Room: $($room.DisplayName) working hours/days." -ForegroundColor Green
        Set-MailboxCalendarConfiguration -Identity $room.PrimarySmtpAddress -WorkingHoursStartTime 00:00:00 -WorkingHoursEndTime 23:59:59 -workdays AllDays -WorkingHoursTimeZone "Central Standard Time"
        Write-Host "New working hours/days for $($room.DisplayName): $((Get-MailboxCalendarConfiguration -Identity $room.PrimarySmtpAddress).WorkingHoursStartTime) to $((Get-MailboxCalendarConfiguration -Identity $room.PrimarySmtpAddress).WorkingHoursEndTime)" -ForegroundColor Yellow
    }
}

#Central Standard Time           (UTC-06:00) Central Time (US & Canada)
#Get-DistributionGroupMember -Identity $roomList.Identity | Format-Table DisplayName, PrimarySmtpAddress
#Remove-DistributionGroupMember -Identity "Vine Rooms" -Member ""
#Set-MailboxCalendarConfiguration -Identity  -WorkingHoursStartTime 09:00:00 -WorkingHoursEndTime 18:00:00

$room = "Beacon Rock"
Get-place -Identity $room | Format-Table Identity, DisplayName, Floor, Building, Type, IsManaged, BookingType, MTREnabled, Capacity
Set-place -Identity $room -Floor 2 

$rooms | Format-Table DisplayName, PrimarySmtpAddress, WorkingHoursStartTime, WorkingHoursEndTime, building, floor, MTREnabled

foreach ($room in $rooms)
{
    #Set the missing floor and MTREnabled properties for each room. All missing floors are floor 1 (Ground)
    Write-Host "Processing Room: $($room.DisplayName)" -ForegroundColor Cyan
    $place = Get-place -Identity $room.DisplayName
    if (-not $place.Floor) {
        Write-Host "Setting default floor for $($room.DisplayName) to Ground (1)." -ForegroundColor Green
        Set-place -Identity $room.DisplayName -Floor 1 -FloorLabel "Ground"
    }
    if (-not $place.MTREnabled) {
        Write-Host "Enabling MTR for $($room.DisplayName)." -ForegroundColor Green
        Set-place -Identity $room.DisplayName -MTREnabled $true
    }
}

foreach ($room in $rooms)
{
    Write-Host "Retrieving place information for $($room.DisplayName)." -ForegroundColor Cyan
    $place = Get-place -Identity $room.DisplayName
    $place | Format-Table Identity, DisplayName, Floor, Building, Type, IsManaged, BookingType, MTREnabled, Capacity
}

