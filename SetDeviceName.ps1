Import-Module -Name ImportExcel
Connect-MgGraph -Scopes "DeviceManagementManagedDevices.PrivilegedOperations.All"
$ErrorActionPreference = 'Stop'

#Get all devices
$devices = Get-MgDeviceManagementManagedDevice
#$device = $devices | Where-Object {$_.DeviceName -eq "DESKTOP-OIO36FL"}
#$device | FL

#Import device user names 
$DisplayNamesExcel = Import-Excel -Path "C:\Users\DakotaRuhl\Documents\Reports\Devices\ManufDeviceReport.xlsx"  -WorksheetName "Test Display Names"
$DisplayNamesExcel.count 

#Create tracking variables for summary and details of results
$summary = @{
    SuccessfullyRenamed = 0
    AlreadyCorrectName = 0
    NotFound = 0
    Errors = 0
}

$SuccessfullyRenamedList = @()
$AlreadyCorrectNameList = @()
$NotFoundList = @()
$ErrorsList = @()

##Invoke API to rename devices - Format: SerialNumber-FirstInitialLastName (up to 6 characters of last name)
Function Rename-DeviceForUser ([Microsoft.Graph.PowerShell.Models.IMicrosoftGraphManagedDevice]$device, $newDeviceName)
{
    if ($device.DeviceName -ne $newDeviceName) 
    {
        Write-Host "Renaming device '$($device.DeviceName)'($($device.SerialNumber)) to $newDeviceName" -ForegroundColor Green
        try 
        {
            $serialNumber = $device.Serialnumber
            $apiUrl = "https://graph.microsoft.com/beta/deviceManagement/managedDevices?`$filter=serialNumber eq '$serialNumber'"
            $deviceResult = Invoke-MgGraphRequest -Method GET -Uri $apiUrl
    
            $intuneDeviceId = $deviceResult.value[0].id
            $currentDeviceName = $deviceResult.value[0].deviceName
        
            $body = @{ deviceName = $newDeviceName } | ConvertTo-Json
            $updateUrl = "https://graph.microsoft.com/beta/deviceManagement/managedDevices/$intuneDeviceId/setDeviceName"

            Invoke-MgGraphRequest -Method POST -Uri $updateUrl -Body $body
            Write-Host "Successfully renamed device with serial $serialNumber from $currentDeviceName to $newDeviceName" -ForegroundColor Green

            $summary.SuccessfullyRenamed++
            $SuccessfullyRenamedList += [PSCustomObject]@{
                DeviceUser = $device.UserDisplayName
                SerialNumber = $serialNumber
                OldDeviceName = $currentDeviceName
                NewDeviceName = $newDeviceName
            }
        }
        catch 
        {
            Write-Host "Error processing device with serial $($device.Serialnumber) : $_.Exception.Message" -ForegroundColor Red
            $summary.Errors++
            $ErrorsList += [PSCustomObject]@{
                DeviceUser = $device.UserDisplayName
                SerialNumber = $serialNumber
                ErrorMessage = $_.Exception.Message
            }
        }
    } 
    else 
    {
        Write-Host "Device with serial $($device.Serialnumber) already has the correct name: $currentDeviceName" -ForegroundColor Cyan
        $summary.AlreadyCorrectName++
        $AlreadyCorrectNameList += [PSCustomObject]@{
            DeviceUser = $device.UserDisplayName
            SerialNumber = $device.Serialnumber
            DeviceName = $currentDeviceName
        }
        continue
    }

}

#Main loop to process each user and their devices
foreach ($user in $DisplayNamesExcel) 
{
    $device = $devices | Where-Object {$_.UserDisplayName -eq $user.DisplayName}

    foreach ($d in $device) 
    {
        If (($null -ne $d.SerialNumber) -and ($d)) 
        {
            Write-Host "Processing $((@($device)).Count) devices for user: $($user.DisplayName)" -ForegroundColor Blue

            #Determine first and last names
            $firstName = $user.DisplayName.Split(' ')[0]
            $lastName = $user.DisplayName.Split(' ')[1]

            ##testing
            #$firstName = "Jason"
            #$lastName = "O’Roark"

            #replace anything that is not a number, letter, or - with nothing
            $firstName = $firstName -replace '[^a-zA-Z0-9-]', ''
            $lastName = $lastName -replace '[^a-zA-Z0-9-]', ''
            
            #Format first initial of First Name
            $fnlnCapLetters = $firstName.Substring(0,1).ToUpper() + $lastName.Substring(0,1).ToUpper()
            #Format up to 6 characters of last name (first letter uppercase, rest lowercase)
            switch ($lastName.Length) 
            {
                2 {$lnRemLetters = $lastName.Substring(1,1).ToLower()} 
                3 {$lnRemLetters = $lastName.Substring(1,2).ToLower()    }
                4 {$lnRemLetters = $lastName.Substring(1,3).ToLower()    }
                5 {$lnRemLetters = $lastName.Substring(1,4).ToLower()    }
                Default {$lnRemLetters = $lastName.Substring(1,5).ToLower()}
            }

            $newDeviceName = "$($device.SerialNumber.Substring($device.SerialNumber.Length - 7))-$fnlnCapLetters$lnRemLetters"
            #call function to rename device
            Rename-DeviceForUser -device $device
        }
        else 
        {
            Write-Host "Device not found: $($d)" -ForegroundColor Yellow
            $summary.NotFound++
            $NotFoundList += [PSCustomObject]@{
                User = $user.DisplayName
            }
            continue
        }
    }
}

Write-Host "Summary: $($summary | ConvertTo-Json -Depth 5)" -ForegroundColor Magenta
$SuccessfullyRenamedList | Export-Excel -Path "C:\Users\DakotaRuhl\Documents\Reports\Devices\SuccessfullyRenamedDevices.xlsx" -WorksheetName "Renamed Devices" -AutoSize
$AlreadyCorrectNameList | Export-Excel -Path "C:\Users\DakotaRuhl\Documents\Reports\Devices\AlreadyCorrectNameDevices.xlsx" -WorksheetName "Already Correct Name Devices" -AutoSize
$NotFoundList | Export-Excel -Path "C:\Users\DakotaRuhl\Documents\Reports\Devices\NotFoundDevices.xlsx" -WorksheetName "Not Found Devices" -AutoSize
$ErrorsList | Export-Excel -Path "C:\Users\DakotaRuhl\Documents\Reports\Devices\ErrorsRenamingDevices.xlsx" -WorksheetName "Errors Renaming Devices" -AutoSize
Write-Host "Detailed results exported to Excel files in C:\Users\DakotaRuhl\Documents\Reports\Devices\" -ForegroundColor Magenta