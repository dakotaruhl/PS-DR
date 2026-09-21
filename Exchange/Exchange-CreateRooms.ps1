$Thumbprint = "C47B91EB62634CA61FA8146DDA83B8BF605C0962"
$ClientID   = "ea2ca49b-d0df-4774-b611-86cf9dc9629f"
$TenantId = "0bdf0e1f-a359-4b5c-9b79-9357e35ff8c6"

# Connect to Microsoft Graph using the app registration credentials, if not already connected. For password expiration. 
$graphConnection = Get-MgContext -ErrorAction SilentlyContinue
if (-not $graphConnection) {
    Connect-MgGraph `
        -ClientId $ClientID `
        -TenantId $TenantId `
        -CertificateThumbprint $Thumbprint
}
else {
    Write-Host "Already connected to Microsoft Graph." -ForegroundColor Green
}

#Connect Exchange if not already connected
try {
    $Connection = Get-ConnectionInformation -ErrorAction SilentlyContinue

    if (-not $Connection -or $Connection.State -ne "Connected") {
        Connect-ExchangeOnline
    }
    else {
        Write-Host "Already connected to Exchange Online." -ForegroundColor Green
    }
}
catch {
    Connect-ExchangeOnline
}

#Get room info from Excel
$roomList = @()
$roomList = Import-Excel -Path ".\Input Data\RoomList.xlsx"
    
ForEach ($room in $roomList) {
    $RoomName = $room.RoomName.Trim()
    $RoomEmail = $room.RoomEmail.Trim()
    [int]$RoomCapacity = $room.RoomCapacity
    $RoomPassword = ConvertTo-SecureString -String $room.Password -AsPlainText -Force

    Write-Host "Preparing to create room mailbox: $RoomName ($RoomEmail) with capacity: $RoomCapacity" -ForegroundColor Yellow

    New-Mailbox -MicrosoftOnlineServicesID $RoomEmail `
                -Name $RoomName `
                -Room -EnableRoomMailboxAccount $true `
                -ResetPasswordOnNextLogon $false `
                -RoomMailboxPassword $RoomPassword | Out-Null

    Write-Host "Created room mailbox: $RoomName ($RoomEmail) with capacity: $RoomCapacity"

    # Wait for mailbox to be prepared 
    $Mailbox = $null
    for ($i = 1; $i -le 30; $i++) {
        $Mailbox = Get-EXOMailbox $RoomEmail -ErrorAction SilentlyContinue

        if ($Mailbox) {
            break
        }

        Start-Sleep -Seconds 5
    }

    if (-not $Mailbox) {
        throw "Mailbox failed to become available."
    }
    
    # Set place
    Set-Place $RoomEmail -CountryOrRegion "US" -State "Texas" -City "Houston" -Floor 1 -FloorLabel "Ground" -Capacity $RoomCapacity

    # Add to room list
    Add-DistributionGroupMember -Identity "Hyperion Rooms" -Member $RoomEmail

    # Set the Calendar Processing settings for the room mailbox
    Set-CalendarProcessing -Identity $RoomEmail `
        -AutomateProcessing AutoAccept `
        -AddOrganizerToSubject $false `
        -AllowRecurringMeetings $true `
        -DeleteAttachments $true `
        -DeleteComments $false `
        -DeleteSubject $false `
        -ProcessExternalMeetingMessages $true `
        -RemovePrivateProperty $false

    # Update to Central Time
    Set-MailboxCalendarConfiguration -Identity $RoomEmail -WorkingHoursTimeZone "Central Standard Time" `
        -WorkingHoursStartTime "00:00:00" -WorkingHoursEndTime "23:59:00" `
        -WorkDays AllDays

    # Set password to never expire for the room mailbox, remove change password flag
    Update-MgUser -UserId $RoomEmail -PasswordPolicies "DisablePasswordExpiration"

    # update a few attributes for the room mailbox
    Update-MgUser -UserId $RoomEmail `
        -OfficeLocation $room.location.trim() `
        -JobTitle "Teams Room" `
        -GivenName $RoomName `
        -Surname "Room" `
        -EmployeeID $room.employeeId.trim() `
        -UsageLocation "US"
}


## Hyp updates
$FormatEnumerationLimit=-1

Get-DistributionGroup -Identity "Vine Rooms"

Get-DistributionGroupMember -Identity "Vine Rooms"

$members = Get-DistributionGroupMember -Identity "Vine Rooms"
foreach ($member in $members) {
    $place = Get-Place -Identity $member.Name
    if ($place.Building -ne "Hyperion") {
        Write-Host "Updating building for $($member.Name) to Hyperion" -ForegroundColor Green
        Set-Place -Identity $member.Name -Building "Hyperion"
    }
    else {
        Write-Host "$($member.Name) is already set to building Hyperion" -ForegroundColor Yellow
    }
}
$members



## Vine Updates
Add-DistributionGroup
$FormatEnumerationLimit=-1

Get-DistributionGroup -Identity "Vine Rooms"

Get-DistributionGroupMember -Identity "Vine Rooms"

$members = Get-DistributionGroupMember -Identity "Vine Rooms"
$member = $members[0]
foreach ($member in $members) {
    $place = Get-Place -Identity $member.Name
    if ($place.Building -ne "Vine") {
        Write-Host "Updating building for $($member.Name) to Vine" -ForegroundColor Green
        Set-Place -Identity $member.Name -Building "Vine"
    }
    else {
        Write-Host "$($member.Name) is already set to building Vine" -ForegroundColor Yellow
    }
}
$members

$firstfloor = @("Big Bend", "Castle Rock", "Death Valley", "Rocky Mountain", 
                "Red Rock", "Basaltic Prism", "El Captain", "Los Arcos", 
                "Plymouth Rock", "Eagle Rock", "Owl Rock", "Mount Rushmore")
$secondfloor = @("Grand Canyon", "Yellowstone", "Beacon Rock", "Granite2")
$firstfloorrooms = Get-DistributionGroupMember -Identity "Vine Rooms" | Where-Object { $firstfloor -contains $_.Name }
$secondfloorrooms = Get-DistributionGroupMember -Identity "Vine Rooms" | Where-Object { $secondfloor -contains $_.Name }