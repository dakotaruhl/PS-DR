Connect-ExchangeOnline `
    -AppId $env:AZURE_CLIENT_ID `
    -Organization $env:AZURE_TENANT_DOMAIN `
    -CertificateThumbprint $env:AZURE_CLIENT_CERTIFICATE_THUMBPRINT

$roomList = Get-DistributionGroupMember -Identity "Hyperion Rooms"
$calendarPermission = "Editor"
$userAdd = "HYP-Rooms-CalendarAccess"


foreach ($room in $roomList) {
    Write-output "Current Room: $room"
    Write-output "Setting calendar permissions for $userAdd with $calendarPermission access rights."
    
    $existingPermission = Get-MailboxFolderPermission -Identity "$($room.PrimarySmtpAddress):\Calendar" -User $userAdd
    Write-output "Existing permissions for $($room.PrimarySmtpAddress):"
    Get-MailboxFolderPermission -Identity "$($room.PrimarySmtpAddress):\Calendar" | Format-Table -AutoSize
    Write-output "----------------------------------------"
    Start-Sleep -Seconds 1


    If($null -eq $existingPermission.AccessRights -or $existingPermission.AccessRights.Count -eq 0) {
        Write-output "$userAdd does not have $calendarPermission access to $($room.PrimarySmtpAddress):\Calendar"
        Add-MailboxFolderPermission -Identity "$($room.PrimarySmtpAddress):\Calendar" -User $userAdd -AccessRights $calendarPermission -foregroundcolor Green
    }
    elseif($existingPermission.AccessRights -notcontains $calendarPermission) {
        Write-output "$userAdd has some permissions but not $calendarPermission access to $($room.PrimarySmtpAddress):\Calendar" 
        Set-MailboxFolderPermission -Identity "$($room.PrimarySmtpAddress):\Calendar" -User $userAdd -AccessRights $calendarPermission -foregroundcolor Yellow
    }
    else {
            Write-output "$userAdd already has $calendarPermission access to $($room.PrimarySmtpAddress):\Calendar" -foregroundcolor blue
            Continue
    }

    Start-Sleep -Seconds 3
    Write-output "Final permissions for $($room.PrimarySmtpAddress):"
    Get-MailboxFolderPermission -Identity "$($room.PrimarySmtpAddress):\Calendar" | Format-Table -AutoSize
    Write-output "----------------------------------------"
}