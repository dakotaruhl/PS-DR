#Connect-ExchangeOnline -DisableWam

#Get-DistributionGroup -RecipientTypeDetails RoomList | Format-Table DisplayName, Identity, PrimarySmtpAddress –AutoSize


# Get all room lists
$roomLists = Get-DistributionGroup -ResultSize Unlimited -RecipientTypeDetails RoomList

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


# Exact path to remove (your OneDrive modules path)
#$oneDriveModules = 'C:\Users\DakotaRuhl\OneDrive - Enchanted Rock\Documents\PowerShell\Modules'

# Split, filter out the exact OneDrive path (handles duplicates), and rejoin
#$env:PSModulePath = ($env:PSModulePath -split ';' | Where-Object { $_ -and ($_ -ne $oneDriveModules) } ) -join ';'

# Verify
#$env:PSModulePath -split ';'

# for machine level 
# Build the exact set you want to keep (no OneDrive path)
#$desired = @(
  #'C:\Program Files\PowerShell\7\Modules',
  #'C:\Program Files\PowerShell\Modules',
  #'C:\Program Files\WindowsPowerShell\Modules',
  #'C:\WINDOWS\system32\WindowsPowerShell\v1.0\Modules',
  #'C:\Program Files\SharePoint Online Management Shell\',
  #'c:\Users\DakotaRuhl\.vscode\extensions\ms-vscode.powershell-2025.4.0\modules'
#) | Select-Object -Unique

#[Environment]::SetEnvironmentVariable('PSModulePath', ($desired -join ';'), 'Machine')

#"Updated Machine PSModulePath. Restart PowerShell (or sign out/in) for it to apply."

#[Environment]::SetEnvironmentVariable('PSModulePath', $null, 'User')


#Remove-Item "C:\Program Files\PowerShell\7\Modules\ExchangeOnlineManagement" -Recurse -Force -ErrorAction SilentlyContinue
#Remove-Item "C:\Program Files\WindowsPowerShell\Modules\ExchangeOnlineManagement" -Recurse -Force -ErrorAction SilentlyContinue
#Remove-Item "$env:USERPROFILE\Documents\PowerShell\Modules\ExchangeOnlineManagement" -Recurse -Force -ErrorAction SilentlyContinue
#Remove-Item "C:\Users\DakotaRuhl\OneDrive - Enchanted Rock\Documents\PowerShell\Modules\ExchangeOnlineManagement" -Recurse -Force -ErrorAction SilentlyContinue
#Get-Module ExchangeOnlineManagement -ListAvailable
