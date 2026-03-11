Import-Module -Name ImportExcel
Connect-MgGraph -Scopes "DeviceManagementManagedDevices.PrivilegedOperations.All"
$ErrorActionPreference = 'Stop'
$runStamp = Get-Date -Format "ddmmyyyy-HHmmss"

#Get all devices
Write-Host "Retrieving devices from Intune..." -ForegroundColor Blue
$devices = Get-MgDeviceManagementManagedDevice -All
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

#Function to export results to Excel with timestamp in filename and run details in header
function Export-ReportWithTimestamp {
    param(
        [Parameter(Mandatory)] $Data,
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $WorksheetName
    )

    $runDT = Get-Date

    $pkg = $Data | Export-Excel -Path $Path `
        -WorksheetName $WorksheetName `
        -AutoSize `
        -StartRow 3 `
        -PassThru

    $ws = $pkg.Workbook.Worksheets[$WorksheetName]

    $ws.Cells["A1"].Value = "Run Timestamp (Local):"
    $ws.Cells["B1"].Value = $runDT
    $ws.Cells["B1"].Style.Numberformat.Format = "m/d/yyyy h:mm:ss AM/PM"
    $ws.Cells["A1:B1"].Style.Font.Bold = $true

    Close-ExcelPackage $pkg
}

##Invoke API to rename devices - Format: SerialNumber-FirstInitialLastName (up to 6 characters of last name)
Function Rename-DeviceForUser ([Microsoft.Graph.PowerShell.Models.IMicrosoftGraphManagedDevice]$device, [string]$newDeviceName)
{
    if ($device.DeviceName -ne $newDeviceName) 
    {
        $serialNumber = $device.Serialnumber
        Write-Host "Renaming device '$($device.DeviceName)'($($serialNumber)) to $newDeviceName" -ForegroundColor Green
        try 
        {
            $apiUrl = "https://graph.microsoft.com/beta/deviceManagement/managedDevices?`$filter=serialNumber eq '$serialNumber'"
            $deviceResult = Invoke-MgGraphRequest -Method GET -Uri $apiUrl -ErrorAction Stop
    
            $intuneDeviceId = $deviceResult.value[0].id
            $currentDeviceName = $deviceResult.value[0].deviceName
        
            $body = @{ deviceName = $newDeviceName } | ConvertTo-Json
            $updateUrl = "https://graph.microsoft.com/beta/deviceManagement/managedDevices/$intuneDeviceId/setDeviceName"

            Invoke-MgGraphRequest -Method POST -Uri $updateUrl -Body $body -ErrorAction Stop
            Write-Host "Successfully renamed device with serial $serialNumber from $currentDeviceName to $newDeviceName" -ForegroundColor Green

            $script:summary.SuccessfullyRenamed++
            $script:SuccessfullyRenamedList += [PSCustomObject]@{
                DeviceUser = $device.UserDisplayName
                SerialNumber = $device.Serialnumber
                OldDeviceName = $currentDeviceName
                NewDeviceName = $newDeviceName
            }
        }
        catch 
        {
            Write-Host ("Error processing device with serial {0}: {1}" -f $device.SerialNumber, $_.Exception.Message) -ForegroundColor Red
            $script:ErrorsList += [PSCustomObject]@{
                DeviceUser = $device.UserDisplayName
                SerialNumber = $device.Serialnumber
                ErrorMessage = $_.Exception.Message
            }
            $script:summary.Errors++
            
        }
    } 
    else 
    {
        Write-Host "Device with serial $($device.Serialnumber) already has the correct name: $($device.DeviceName)" -ForegroundColor Cyan
        $script:summary.AlreadyCorrectName++
        $script:AlreadyCorrectNameList += [PSCustomObject]@{
            DeviceUser = $device.UserDisplayName
            SerialNumber = $device.Serialnumber
            DeviceName = $device.DeviceName
        }
        continue
    }

}

$count = 0
$totalUsers = $DisplayNamesExcel.Count

#Main loop to process each user and their devices
foreach ($user in $DisplayNamesExcel) 
{
    $count++
    $start = Get-Date

    $device = $devices | Where-Object {$_.UserDisplayName -eq $user.DisplayName}
    Write-Host "Processing user $($user.DisplayName) ($count of $totalUsers)" -ForegroundColor Blue

    foreach ($d in $device) 
    {
        If (($null -ne $d.SerialNumber) -and ($d)) 
        {
            Write-Host "Processing $($device.Count) devices for user: $($user.DisplayName)" -ForegroundColor Yellow

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

            $newDeviceName = "$($d.SerialNumber.Substring($d.SerialNumber.Length - 7))-$fnlnCapLetters$lnRemLetters"
            
            #call function to rename device
            Rename-DeviceForUser -device $d -newDeviceName $newDeviceName

            # Compute progress
            $percent = [int][math]::Round(($count / $totalUsers) * 100, 0)
            
            # Simple ETA (avoid divide-by-zero)
            $elapsed = (Get-Date) - $start
            $etaSec  = if ($count -gt 0) 
            {
                [int]([double]$elapsed.TotalSeconds * ($totalUsers - $count) / $count)
            } 
            else {0}

            # Format ETA as HH:MM:SS (supports >24 hours)
            $ts      = [TimeSpan]::FromSeconds($etaSec)
            $etaHMS  = ('{0:00}:{1:00}:{2:00}' -f [int]$ts.TotalHours, $ts.Minutes, $ts.Seconds)

            Write-Progress -Activity "Processing Devices for user: $($user.DisplayName)" `
            -Status "Processing device $count of $totalUsers ($percent`%) ETA: $etaHMS"`
            -PercentComplete $percent `
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
    Write-Progress -Completed
}

Write-Host "Summary: $($summary | ConvertTo-Json -Depth 5)" -ForegroundColor Magenta

$runStampFile = Get-Date -Format "yyyyMMdd-HHmmss"
$basePath = "C:\Users\DakotaRuhl\Documents\Reports\Devices"

Export-ReportWithTimestamp -Data $ErrorsList `
  -Path "$basePath\Errors\ErrorsRenamingDevices_$runStampFile.xlsx" `
  -WorksheetName "Errors Renaming Devices"

Export-ReportWithTimestamp -Data $SuccessfullyRenamedList `
  -Path "$basePath\Success\RenamedDevices_$runStampFile.xlsx" `
  -WorksheetName "Renamed Devices"

Export-ReportWithTimestamp -Data $AlreadyCorrectNameList `
  -Path "$basePath\AlreadyCorrectName\AlreadyCorrectNameDevices_$runStampFile.xlsx" `
  -WorksheetName "Already Correct Name Devices"

Export-ReportWithTimestamp -Data $NotFoundList `
  -Path "$basePath\NotFound\NotFoundDevices_$runStampFile.xlsx" `
  -WorksheetName "Not Found Devices"

Write-Host "Detailed results exported to Excel files in C:\Users\DakotaRuhl\Documents\Reports\Devices\" -ForegroundColor Magenta



