Import-Module -Name Microsoft.Graph.DeviceManagement
Import-Module -Name ImportExcel

Connect-MgGraph -Scopes "DeviceManagementManagedDevices.ReadWrite.All"

$devices = Get-MgDeviceManagementManagedDevice
# Filter for the specific device, for example, by its current name or serial number
#$device = $devices | Where-Object {$_.DeviceName -eq "MalloryBlackwell"}


#manual import device user names 
$DisplayNamesExcel = Import-Excel -Path "C:\Users\DakotaRuhl\Documents\Reports\Devices\ManufDeviceReport.xlsx"  -WorksheetName "User Display Names"
$device = $devices | Where-Object {$_.UserDisplayName -eq "Tyler Lauw"}

##Invoke Option
#Doing last 7 of serial number - First 3 of First Name, First 4 of Last Name

$summary = @{
    SuccessfullyRenamed = 0
    AlreadyCorrectName = 0
    NotFound = 0
    Errors = 0
}

Connect-MgGraph -Scopes "DeviceManagementManagedDevices.PrivilegedOperations.All" 

foreach ($user in $DisplayNamesExcel) {
    $device = $devices | Where-Object {$_.UserDisplayName -eq $user.DisplayName}
    if ($device) 
    {
        $firstName = $device.UserDisplayName.Split(' ')[0]
        $lastName = $device.UserDisplayName.Split(' ')[1]
        $FirstNameLetters = $firstName.Substring(0,1).ToUpper() + ($firstName.Substring(1,2)).ToLower()
        $LastNameLetters = ($lastName.Substring(0,1)).ToUpper() + ($lastName.Substring(1,3)).ToLower()
        $newDeviceName = "$($device.SerialNumber.Substring($device.SerialNumber.Length - 7))-$FirstNameLetters$LastNameLetters"
        
        if ($device.DeviceName -ne $newDeviceName) 
        {
            Write-Host "Renaming device with serial $($user.SerialNumber) from $($device.DeviceName) to $newDeviceName" -ForegroundColor Green
            
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
            }
            catch 
            {
                Write-Host "Error processing device with serial $serialNumber : $_" -ForegroundColor Red
                $summary.Errors++
            }
        } 
        else 
        {
            Write-Host "Device with serial $serialNumber already has the correct name: $currentDeviceName" -ForegroundColor Cyan
            $summary.AlreadyCorrectName++
            continue
        }
    } 
    else 
    {
        Write-Host "No device found with serial number: $serialNumber" -ForegroundColor Yellow
        $summary.NotFound++
        continue
    }
}


#output serial numbers with length of serial numbers 
$SerialNumbers = @()
foreach ($device in $devices) {
    $SerialNumbers += [PSCustomObject]@{
        deviceModel = $device.Model
        deviceUser = $device.UserDisplayName
        deviceName = $device.DeviceName
        SerialNumber = $device.Serialnumber
        Length = $device.Serialnumber.Length
        Manufacturer = $device.Manufacturer
    }
}

$SerialNumbers | Export-Excel "C:\Users\DakotaRuhl\Documents\Reports\Devices\ManufDeviceReport.xlsx" -WorksheetName "SerialNumbers" -AutoSize -TableName "SerialNumbersData" -ClearSheet