<# 
This script retrieves all devices from Intune, compares them to a list of users from Excel, 
and renames the devices in Intune to match the expected format. 

It also generates a comprehensive report of the results.

Currently the option to actually rename the device is commented out on line 206 to allow for testing and validation of the script without making changes to Intune.
#>

Start-Transcript -Path "C:\Users\DakotaRuhl\Documents\Reports\Devices\Transcripts\SetDeviceName_$(Get-Date -Format 'yyyyMMdd-HHmmss').txt" -NoClobber
Import-Module -Name ImportExcel
Connect-MgGraph -Scopes "DeviceManagementManagedDevices.PrivilegedOperations.All" -NoWelcome
$ErrorActionPreference = 'Stop'

#Get all devices
Write-Host "Retrieving devices from Intune..." -ForegroundColor Blue
$devices = Get-MgDeviceManagementManagedDevice -All

<# $Workbook = Import-Excel -Path "C:\Users\DakotaRuhl\Documents\Reports\Devices\ManufDeviceReport.xlsx"  -WorksheetName "Sheet1" | 
    Select-Object DeviceUser, SerialNumber
$user = $Workbook[8]
$brokenDevice = $devices | Where-Object {$_.SerialNumber.Split(" ")[0] -eq "1H852048V4"}
$user = $null
$brokenDevice = $null

$devicetestlist = @()
Foreach ($user in $Workbook) 
{
    $brokenDevice = $devices | Where-Object {$_.SerialNumber.Split(" ")[0] -eq $user.SerialNumber}
    $serialNumber = $brokenDevice.SerialNumber.Split(" ")[0]
    if ($brokenDevice) 
    {
        
        $apiUrl = "https://graph.microsoft.com/beta/deviceManagement/managedDevices?`$filter=serialNumber eq '$serialNumber'"  
        $deviceResult = Invoke-MgGraphRequest -Method GET -Uri $apiUrl -ErrorAction Stop 

        $lastuserIDs = $deviceResult.value.usersLoggedOn.userId -join (', ')
        $lastuserTimes = $deviceResult.value.usersLoggedOn.lastLogOnDateTime -join (', ')
        
        If((($deviceResult.value.usersLoggedOn.userId).count -gt 1) -or ($brokenDevice.DeviceName.Count -gt 1)) {
            Write-Host "Multiple users found for serial $($serialNumber). Last signed-in users: $($lastuserIDs)" -ForegroundColor Yellow
            $devicetestlist += [PSCustomObject]@{
                User = $user.DeviceUser
                SerialNumber = $serialNumber
                DeviceName1 = $brokenDevice.DeviceName[0]
                DeviceName2 = $brokenDevice.DeviceName[1]
                OperatingSystem = $brokenDevice.OperatingSystem[0]
                LastSignedInUsers = $lastuserIDs
                LastSignedInTimes = $lastuserTimes
            }
        }
        else {
            Write-Host "Single user found for serial $($serialNumber). Last signed-in user: $($lastuserIDs)" -ForegroundColor Yellow
            $devicetestlist += [PSCustomObject]@{
                User = $user.DeviceUser
                SerialNumber = $serialNumber
                DeviceName1 = $brokenDevice.DeviceName
                OperatingSystem = $brokenDevice.OperatingSystem
                LastSignedInUsers = $lastuserIDs
                LastSignedInTimes = $lastuserTimes
            }
        }
    }
    else {
        continue
    }
}
$devicetestlist | Export-Excel -Path "C:\Users\DakotaRuhl\Documents\Reports\Devices\DeviceTestList.xlsx" -AutoSize -WorksheetName "DeviceTestList"   #>

#Import device user names and ID's from Excel report. Remove empty rows, only select specific column in specific sheet
$Workbook = Import-Excel -Path "C:\Users\DakotaRuhl\Documents\Reports\Devices\ManufDeviceReport.xlsx"  -WorksheetName "User Display Names with ID" | 
    Select-Object UniqueDisplayName, UniqueUserID | 
    Where-Object { $_.UniqueDisplayName -ne $null -and $_.UniqueDisplayName -ne "" }


#Create tracking variables for summary and details of results
$summary = @{
    SuccessfullyRenamed = 0
    AlreadyCorrectName = 0
    NotFound = 0
    ExceptionsCaught = 0
    SignedInUserMismatch = 0
    UnsupportedOS = 0
}
$unsupportedOSList = @()
$SuccessfullyRenamedList = @()
$ErrorsList = @()

#Function to export results to Excel with timestamp in filename and run details in header
function Export-ReportWorkbookWithTimestamp {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][hashtable]$Sheets,   # SheetName -> Data
        [int]$StartRow = 3,
        [hashtable]$SummaryHash = $null             # optional: your $summary hashtable
    )

    # Ensure folder exists
    $dir = Split-Path $Path -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }

    $runDT = Get-Date

    function Has-Records($Data) {
        if ($null -eq $Data) { return $false }
        if ($Data -is [System.Collections.ICollection]) { return ($Data.Count -gt 0) }
        return $true
    }

    function Stamp-Timestamp([OfficeOpenXml.ExcelWorksheet]$ws, [datetime]$dt) {
        $ws.Cells["A1"].Value = "Run Timestamp (Local):"
        $ws.Cells["B1"].Value = $dt
        $ws.Cells["B1"].Style.Numberformat.Format = "m/d/yyyy h:mm:ss AM/PM"
        $ws.Cells["A1:B1"].Style.Font.Bold = $true
    }

    function Write-NoRecords([OfficeOpenXml.ExcelWorksheet]$ws, [int]$row) {
        $cell = $ws.Cells["A$row"]
        $cell.Value = "No records"
        $cell.Style.Font.Italic = $true
        $cell.Style.Font.Color.SetColor([System.Drawing.Color]::Gray)
    }

    function Add-SummarySheet {
        param(
            [Parameter(Mandatory)][OfficeOpenXml.ExcelPackage]$Pkg,
            [Parameter(Mandatory)][hashtable]$Sheets,
            [datetime]$RunDT,
            [hashtable]$SummaryHash
        )

        # Create/clear summary sheet
        $sumWs = Add-Worksheet -ExcelPackage $Pkg -WorksheetName "Summary" -ClearSheet
        Stamp-Timestamp -ws $sumWs -dt $RunDT

        # Title
        $sumWs.Cells["A2"].Value = "Device Rename Report Summary"
        $sumWs.Cells["A2"].Style.Font.Bold = $true
        $sumWs.Cells["A2"].Style.Font.Size = 14

        # Headers
        $sumWs.Cells["A4"].Value = "Report"
        $sumWs.Cells["B4"].Value = "Count"
        $sumWs.Cells["C4"].Value = "Link"
        $sumWs.Cells["A4:C4"].Style.Font.Bold = $true

        $row = 5

        foreach ($name in $Sheets.Keys) {
            $data = $Sheets[$name]
            $count = if ($data -is [System.Collections.ICollection]) { $data.Count } elseif ($null -ne $data) { 1 } else { 0 }

            $sumWs.Cells["A$row"].Value = $name
            $sumWs.Cells["B$row"].Value = $count

            # Hyperlink to the sheet (internal Excel link)
            # Format: '#''Sheet Name''!A1'
            $safeSheet = $name.Replace("'", "''")
            $linkTarget = "#'$safeSheet'!A1"

            $sumWs.Cells["C$row"].Value = "Go to sheet"
            $sumWs.Cells["C$row"].Hyperlink = $linkTarget
            $sumWs.Cells["C$row"].Style.Font.Color.SetColor([System.Drawing.Color]::Blue)
            $sumWs.Cells["C$row"].Style.Font.UnderLine = $true

            $row++
        }

        # Optional: dump your $summary hashtable as a small table
        if ($SummaryHash) {
            $row += 2
            $sumWs.Cells["A$row"].Value = "Script Summary Counters"
            $sumWs.Cells["A$row"].Style.Font.Bold = $true
            $row++

            $sumWs.Cells["A$row"].Value = "Metric"
            $sumWs.Cells["B$row"].Value = "Value"
            $sumWs.Cells["A$row:B$row"].Style.Font.Bold = $true
            $row++

            foreach ($k in $SummaryHash.Keys) {
                $sumWs.Cells["A$row"].Value = $k
                $sumWs.Cells["B$row"].Value = $SummaryHash[$k]
                $row++
            }
        }

        # Auto size columns
        $sumWs.Cells[$sumWs.Dimension.Address].AutoFitColumns()
    }

    # Create/open workbook once
    $pkg = Open-ExcelPackage -Path $Path -Create
    if (-not $pkg) { throw "Open-ExcelPackage returned null. Is the file locked/open? Path: $Path" }

    # 1) Create Summary first (so it’s always present even if some sheets are empty)
    Add-SummarySheet -Pkg $pkg -Sheets $Sheets -RunDT $runDT -SummaryHash $SummaryHash

    # 2) Create each data sheet
    foreach ($sheetName in $Sheets.Keys) {
        $data = $Sheets[$sheetName]

        $ws = Add-Worksheet -ExcelPackage $pkg -WorksheetName $sheetName -ClearSheet
        Stamp-Timestamp -ws $ws -dt $runDT

        if (Has-Records $data) {
            # Use -PassThru to keep working with the package after export [1](https://www.tbone.se/2023/02/16/update-intune-primary-user-with-powershell-or-azure-automation/)[2](https://mikemdm.de/2023/02/19/automatically-set-intune-primary-user-based-on-the-logged-on-user/)[3](https://learn.microsoft.com/en-us/intune/intune-service/fundamentals/find-primary-user)
            $pkg = $data | Export-Excel -ExcelPackage $pkg `
                -WorksheetName $sheetName `
                -StartRow $StartRow `
                -AutoSize `
                -PassThru

            # Stamp again for safety
            $ws = $pkg.Workbook.Worksheets[$sheetName]
            Stamp-Timestamp -ws $ws -dt $runDT
        }
        else {
            Write-NoRecords -ws $ws -row $StartRow
        }
    }

    Close-ExcelPackage $pkg
}

##Invoke API to rename devices - Format: SerialNumber-FirstInitialLastName (up to 6 characters of last name)
Function Rename-DeviceForUser ([Microsoft.Graph.PowerShell.Models.IMicrosoftGraphManagedDevice]$device, [string]$newDeviceName)
{
    if ($device.DeviceName -ne $newDeviceName) 
    {
        $serialNumber = $device.Serialnumber
        try 
        {   
            $apiUrl = "https://graph.microsoft.com/beta/deviceManagement/managedDevices?`$filter=serialNumber eq '$serialNumber'"
            $deviceResult = Invoke-MgGraphRequest -Method GET -Uri $apiUrl -ErrorAction Stop
    
            $intuneDeviceId = $deviceResult.value[0].id
            $currentDeviceName = $deviceResult.value[0].deviceName
            $lastUserId = ($deviceResult.value[0].usersLoggedOn | Sort-Object -Property lastSignInDateTime -Descending | Select-Object -First 1).userId
            $lastUser = ($Workbook | Where-Object {$_.UniqueUserId -eq $lastUserId} | Select-Object -First 1).UniqueDisplayName

            #Check user is the last signedin user on the device before renaming to avoid renaming shared devices with multiple users.
            if ($lastUserId -ne $device.UserId) 
            {
                Write-Host "Skipping rename for device with serial $serialNumber because the last signed-in user ($($lastUser)) does not match the expected user ($($device.UserDisplayName)). This may be a shared device." -ForegroundColor Yellow
                $script:summary.SignedInUserMismatch++
                $script:ErrorsList += [PSCustomObject]@{
                    DeviceUser = $device.UserDisplayName
                    LastSignedInUser = $lastUser
                    SerialNumber = $device.Serialnumber
                    ErrorMessage = "Last signed-in user ($($lastUser)) does not match expected user ($($device.UserDisplayName)). Possible shared device."
                }
                return
            }

            $body = @{ deviceName = $newDeviceName } | ConvertTo-Json
            $updateUrl = "https://graph.microsoft.com/beta/deviceManagement/managedDevices/$intuneDeviceId/setDeviceName"

            #Invoke-MgGraphRequest -Method POST -Uri $updateUrl -Body $body -ErrorAction Stop
            Write-Host "Successfully renamed device with serial $serialNumber from $currentDeviceName to $newDeviceName" -ForegroundColor Green

            $script:summary.SuccessfullyRenamed++
            $script:SuccessfullyRenamedList += [PSCustomObject]@{
                DeviceUser = $device.UserDisplayName
                SerialNumber = $device.Serialnumber
                OldDeviceName = $currentDeviceName
                NewDeviceName = $newDeviceName
                OperatingSystem = $device.OperatingSystem
            }
        }
        catch 
        {
            Write-Host ("Error processing device with serial {0}: {1}" -f $device.SerialNumber, $_.Exception.Message) -ForegroundColor Red
            $script:summary.ExceptionsCaught++
            $script:ErrorsList += [PSCustomObject]@{
                DeviceUser = $device.UserDisplayName
                SerialNumber = $device.Serialnumber
                ErrorMessage = $_.Exception.Message
            }
            
            
        }
    } 
    else 
    {
        Write-Host "Device with serial $($device.Serialnumber) already has the correct name: $($device.DeviceName)" -ForegroundColor Cyan
        $script:summary.AlreadyCorrectName++
        $script:ErrorsList += [PSCustomObject]@{
            DeviceUser = $device.UserDisplayName
            SerialNumber = $device.Serialnumber
            DeviceName = $device.DeviceName
            ErrorMessage = "Device already has the correct name"
        }
        continue
    }

}

$count = 0
$totalUsers = $Workbook.Count
$stopWatch = [System.Diagnostics.Stopwatch]::StartNew()

#Main loop to process each user and their devices
foreach ($user in $Workbook) 
{

    $count++
    $device = $devices | Where-Object {$_.UserDisplayName -eq $user.UniqueDisplayName}
    Write-Host "Processing $($device.Count) devices for user $($user.UniqueDisplayName) ($count of $totalUsers)" -ForegroundColor Blue
    
    $userDeviceCount = 0
    foreach ($d in $device) 
    {
        ##Check if device is MacOS/Windows 
        If($d.OperatingSystem -notmatch '^(Windows|macOS)$')
        {
            Write-Host "Skipping device with serial $($d.SerialNumber) for user $($user.UniqueDisplayName) due to unsupported OS: $($d.OperatingSystem)" -ForegroundColor Yellow
            $script:summary.UnsupportedOS++
            $script:unsupportedOSList += [PSCustomObject]@{
                User = $user.UniqueDisplayName
                SerialNumber = $d.SerialNumber
                OperatingSystem = $d.OperatingSystem
            }
            continue
        }

        If (($null -ne $d.SerialNumber) -and ($d)) 
        {
            $userDeviceCount++
            Write-Host "($($userDeviceCount)/$($device.Count)) for user: $($user.UniqueDisplayName)" -ForegroundColor Yellow

            #Determine first and last names
            #remove whitespace and trim display name, then split on space to get first and last names 
            $trimmedDisplayName = ($user.UniqueDisplayName -replace '\s+', ' ').Trim()
            $firstName = $trimmedDisplayName.Split(' ')[0]
            $lastName = $trimmedDisplayName.Substring($trimmedDisplayName.IndexOf(' ') + 1)
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

            
        }
        else 
        {
            Write-Host "Device not found: $($d)" -ForegroundColor Yellow
            $script:summary.NotFound++
            $script:ErrorsList += [PSCustomObject]@{
                User = $user.UniqueDisplayName
                ErrorMessage = "Device not found for user"
            }
            continue
        }
    }
    # Compute progress
    $percent = [int][math]::Round(($count / $totalUsers) * 100, 0)
            
    # Simple ETA (avoid divide-by-zero)
    $elapsed = $stopWatch.Elapsed.TotalSeconds / $count
    $etaSec  = if ($count -gt 0) 
    {
        $elapsed * ($totalUsers - $count)
    } 
    else {0}

    # Format ETA as HH:MM:SS (supports >24 hours)
    $ts = [TimeSpan]::FromSeconds([math]::Max(0,$etaSec))
    $etaHMS  = ('{0:00}:{1:00}:{2:00}' -f [int]$ts.TotalHours, $ts.Minutes, $ts.Seconds)

    
    Write-Progress -Activity "Processing Devices" `
        -Status "User $count of $totalUsers ($percent`%) ETA: $etaHMS" `
        -PercentComplete $percent
}

Write-Progress -Completed
Write-Host "Device renaming process completed. Total time: $($stopWatch.Elapsed.ToString("hh\:mm\:ss"))" -ForegroundColor Green
Write-Host "Summary: $($summary | ConvertTo-Json -Depth 5)" -ForegroundColor Magenta

$runStampFile = Get-Date -Format "yyyyMMdd-HHmmss"
$basePath = "C:\Users\DakotaRuhl\Documents\Reports\Devices"
$reportPath = "$basePath\DeviceRenameReport_$runStampFile.xlsx"

Export-ReportWorkbookWithTimestamp -Path $reportPath -Sheets @{
    "Unsupported OS Devices"  = $unsupportedOSList
    "Errors Renaming Devices" = $ErrorsList
    "Renamed Devices"         = $SuccessfullyRenamedList
} -SummaryHash $summary

Write-Host "Comprehensive report with summary exported to: $reportPath" -ForegroundColor Magenta
Stop-Transcript

################

<#Import-Module Microsoft.Graph.Users
Connect-Graph -scopes "User.Read.All"

 $userIDs = Import-Excel -Path "C:\Users\DakotaRuhl\Documents\Reports\Devices\DeviceTestList.xlsx"  -WorksheetName "DeviceTestList" | 
    Select-Object SerialNumber, LastSignedInUsers

##$obj = $userids[0]
##$obj = $null

$displayNames = @()
foreach ($obj in $userIDs)
{
    
    $i = 0
    $ids = $obj.LastSignedInUsers.Split(',').Trim()
    if(-not($obj.LastSignedInUsers))
    {
        continue
    }
    else 
    {
        while ($i -lt $ids.Count) 
        {
            $name = Get-MgUser -userid $obj.LastSignedInUsers.Split(',').Trim()[$i] | Select-Object DisplayName
            $displayNames += [PSCustomObject]@{ 
                SerialNumber = $obj.SerialNumber.Split(" ")[0]
                UserID = $obj.LastSignedInUsers.Split(',').Trim()[$i]
                DisplayName = $name.DisplayName 
            }
            $i++
        }
    }
    
}

$displayNames | Export-Excel -Path "C:\Users\DakotaRuhl\Documents\Reports\Devices\DeviceTestListNames.xlsx" -AutoSize -WorksheetName "DeviceTestListNames"    #>