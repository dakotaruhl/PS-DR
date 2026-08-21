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


#Get room info from Excel
$roomList = @()
$roomList = Import-Excel -Path ".\Input Data\RoomList.xlsx"

# Configuration for Microsoft Teams Rooms Basic license assignment
$SkuId = "50509a35-f0bd-4c5e-89ac-22f0e16a00f8" # Microsoft Teams Rooms Basic

# Build the license assignment object
$AddLicenses = @(
    @{
        SkuId = $SkuId
    }
)
$RemoveLicenses = @()
    
ForEach ($room in $roomList) {
    $RoomName = $room.RoomName.Trim()
    $RoomEmail = $room.RoomEmail.Trim()

    if($room.update -eq "no") {
        Write-Host "Skipping room mailbox: $RoomName ($RoomEmail) as per the update flag." -ForegroundColor Yellow
        continue
    }

    # Set password to never expire for the room mailbox, remove change password flag
    <# Update-MgUser -UserId $RoomEmail `
        -OfficeLocation $room.location.trim() `
        -JobTitle "Teams Room" `
        -GivenName $RoomName `
        -Surname "Room" `
        -EmployeeID $room.employeeId.trim() `
        -UsageLocation "US" #>


    # Assign the license to the resource account
    Set-MgUserLicense -UserId $RoomEmail -AddLicenses $AddLicenses -RemoveLicenses $RemoveLicenses
}