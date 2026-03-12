Start-Transcript -Path "C:\Users\DakotaRuhl\Documents\Reports\Devices\Transcripts\SetDeviceName_$(Get-Date -Format 'yyyyMMdd-HHmmss').txt" -NoClobber

Import-Module -Name ImportExcel
Connect-MgGraph -Scopes "DeviceManagementManagedDevices.PrivilegedOperations.All" -NoWelcome
$ErrorActionPreference = 'Stop'

#Get all devices
Write-Host "Retrieving devices from Intune..." -ForegroundColor Blue
$devices = Get-MgDeviceManagementManagedDevice -All
#$device = $devices | Where-Object {$_.Serialnumber -eq "5CD116H4Z6"}
#$device | FL

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

Import-Module ImportExcel

function Export-ReportWorkbookWithTimestamp {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][hashtable]$Sheets,   # SheetName -> Data
        [int]$StartRow = 3
    )

    if (-not $Sheets -or $Sheets.Count -eq 0) {
        throw "Sheets hashtable is empty. Provide at least one sheet name and dataset."
    }

    # Ensure folder exists
    $dir = Split-Path $Path -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }

    $runDT = Get-Date

    function Has-Records {
        param($Data)
        if ($null -eq $Data) { return $false }
        if ($Data -is [System.Collections.ICollection]) { return ($Data.Count -gt 0) }
        return $true  # single object
    }

    function Ensure-Worksheet {
        param(
            [Parameter(Mandatory)]$ExcelPackage,
            [Parameter(Mandatory)][string]$WorksheetName
        )
        $ws = $ExcelPackage.Workbook.Worksheets[$WorksheetName]
        if (-not $ws) {
            $ws = Add-Worksheet -ExcelPackage $ExcelPackage -WorksheetName $WorksheetName
        }
        return $ws
    }

    function Set-TimestampHeader {
        param(
            [Parameter(Mandatory)][OfficeOpenXml.ExcelWorksheet]$Worksheet,
            [Parameter(Mandatory)][datetime]$DateTime
        )
        $Worksheet.Cells["A1"].Value = "Run Timestamp (Local):"
        $Worksheet.Cells["B1"].Value = $DateTime
        $Worksheet.Cells["B1"].Style.Numberformat.Format = "m/d/yyyy h:mm:ss AM/PM"
        $Worksheet.Cells["A1:B1"].Style.Font.Bold = $true
    }

    function Write-NoRecords {
        param(
            [Parameter(Mandatory)][OfficeOpenXml.ExcelWorksheet]$Worksheet,
            [Parameter(Mandatory)][int]$Row
        )
        $cell = $Worksheet.Cells["A$Row"]
        $cell.Value = "No records"
        $cell.Style.Font.Italic = $true
        $cell.Style.Font.Color.SetColor([System.Drawing.Color]::Gray)
    }

    # Create / open workbook package (works even with no data)
    $pkg = Open-ExcelPackage -Path $Path -Create

    foreach ($sheetName in $Sheets.Keys) {
        $data = $Sheets[$sheetName]

        # Ensure sheet exists and clear it
        $ws = Ensure-Worksheet -ExcelPackage $pkg -WorksheetName $sheetName
        $ws.Cells.Clear()

        # Always stamp timestamp
        Set-TimestampHeader -Worksheet $ws -DateTime $runDT

        if (Has-Records $data) {
            # Write dataset starting at StartRow (keeps our header row 1)
            $null = $data | Export-Excel -ExcelPackage $pkg `
                -WorksheetName $sheetName `
                -StartRow $StartRow `
                -AutoSize `
                -ClearSheet
            # Re-stamp timestamp because -ClearSheet recreates/overwrites worksheet content
            $ws = $pkg.Workbook.Worksheets[$sheetName]
            Set-TimestampHeader -Worksheet $ws -DateTime $runDT
        }
        else {
            # No data: write “No records”
            Write-NoRecords -Worksheet $ws -Row $StartRow
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

Export-ReportWithTimestamp -Data $unsupportedOSList `
  -Path "$basePath\UnsupportedOS\UnsupportedOSDevices_$runStampFile.xlsx" `
  -WorksheetName "Unsupported OS Devices"

Export-ReportWithTimestamp -Data $ErrorsList `
  -Path "$basePath\Errors\ErrorDevices_$runStampFile.xlsx" `
  -WorksheetName "Errors Renaming Devices"

Export-ReportWithTimestamp -Data $SuccessfullyRenamedList `
  -Path "$basePath\Success\SuccessfulDevices_$runStampFile.xlsx" `
  -WorksheetName "Renamed Devices"

Write-Host "Detailed results exported to Excel files in C:\Users\DakotaRuhl\Documents\Reports\Devices\" -ForegroundColor Magenta


$reportPath = "$basePath\DeviceRenameReport_$runStampFile.xlsx"
Export-ReportWorkbookWithTimestamp -Path $reportPath -Sheets @{
    "Unsupported OS Devices"  = $unsupportedOSList
    "Errors Renaming Devices" = $ErrorsList
    "Renamed Devices"         = $SuccessfullyRenamedList
}

Stop-Transcript