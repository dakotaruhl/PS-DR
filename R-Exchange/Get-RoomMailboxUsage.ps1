#requires -Version 7.2
<#
.SYNOPSIS
    Exports detailed and summary usage statistics for Microsoft 365 room mailboxes to one formatted Excel workbook.
    Use -RoomList to report an Exchange room list, or -RoomEmailAddress for selected rooms.

.DESCRIPTION
    Uses Microsoft Graph v1.0 to list room places and retrieve each room's calendar view.
    By default, the report covers the previous 30 days through the end of today.

    All-day meetings use a reporting convention of 480 business-usage minutes. This is
    intentionally labeled as Business Usage Duration rather than the event's elapsed duration.

.REQUIRED GRAPH PERMISSIONS
    Delegated: Place.Read.All, Calendars.Read.Shared
    Application: Place.Read.All, Calendars.Read

.NOTES
    Certificate authentication defaults to these environment variables:
      AZURE_TENANT_ID
      AZURE_CLIENT_ID
      AZURE_CLIENT_CERTIFICATE_THUMBPRINT

    Exit codes:
      0 = completed successfully
      1 = fatal error
      2 = completed with one or more room-level errors

.USAGE
    All available parameters
    .\R-Exchange\RoomMailboxUsageReport.ps1 [-DaysBack <int>] [-OnlineMeetingOnly] [-ShowTodaysMeetingsOnly] [-OrganizerEmailAddress <string>] 
                                            [-OutputPath <string>] [-ReportTimeZoneId <string>] [-AllDayBusinessUsageMinutes <int>] [-OpenReport] 
                                            [-Interactive] [-TenantId <string>] [-ClientId <string>] [-CertificateThumbprint <string>] [RoomList <string>]
                                            [-RoomEmailAddress <string[]>]
    Example:
    .\R-Exchange\Get-RoomMailboxUsage.ps1 `                       (Specific rooms)
        -RoomEmailAddress @(
            "HoustonConfRoom@enchantedrock.com",
            "VineConferenceRoom@enchantedrock.com",
            "AustinConfRoom@enchantedrock.com"
        )
    .\R-Exchange\Get-RoomMailboxUsage.ps1 -RoomList "Vine Rooms"  (Scope to a room list)

    .\R-Exchange\Get-RoomMailboxUsage.ps1 -RoomList "Vine Rooms" -OutputPath "C:\Users\DakotaRuhl\OneDrive - Enchanted Rock\Reports\Room Devices" -DaysBack 90

    OutputPath examples:
      -OutputPath ".\outputs"                                (relative directory)
      -OutputPath "D:\Reports\RoomUsage"                     (absolute directory)
      -OutputPath "D:\Reports\VineRoomUsage.xlsx"            (complete workbook path)
#>

[CmdletBinding()]
param(
    [ValidateRange(1, 3650)]
    [int]$DaysBack = 30,

    [string[]]$RoomEmailAddress,

    [string]$RoomList,

    [switch]$OnlineMeetingOnly,

    [switch]$ShowTodaysMeetingsOnly,

    [Alias('OrgEmailId')]
    [ValidatePattern('^[^@\s]+@[^@\s]+\.[^@\s]+$')]
    [string]$OrganizerEmailAddress,

    [ValidateNotNullOrEmpty()]
    [string]$OutputPath = (Join-Path -Path $PWD -ChildPath 'RoomMailboxUsageReports'),

    [ValidateNotNullOrEmpty()]
    [string]$ReportTimeZoneId = 'Central Standard Time',

    [ValidateRange(1, 1440)]
    [int]$AllDayBusinessUsageMinutes = 480,

    [switch]$OpenReport,

    [switch]$Interactive,

    [string]$TenantId = $env:AZURE_TENANT_ID,

    [string]$ClientId = $env:AZURE_CLIENT_ID,

    [string]$CertificateThumbprint = $env:AZURE_CLIENT_CERTIFICATE_THUMBPRINT
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Normalize optional collection parameters for StrictMode safety.
$RoomEmailAddress = @(
    $RoomEmailAddress |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
)

if (
    -not [string]::IsNullOrWhiteSpace($RoomList) -and
    $RoomEmailAddress.Count -gt 0
) {
    throw 'Use either -RoomList or -RoomEmailAddress, not both.'
}

function ConvertTo-ReportDateTime {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DateTimeText,

        [Parameter(Mandatory)]
        [System.TimeZoneInfo]$ReportTimeZone
    )

    $parsedDateTime = [datetime]::Parse(
        $DateTimeText,
        [System.Globalization.CultureInfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::AllowWhiteSpaces
    )

    # The request uses Prefer: outlook.timezone, so Graph returns wall-clock values in the
    # requested report time zone. Mark the value as Unspecified to prevent an accidental
    # second conversion based on the machine's local time zone.
    return [datetime]::SpecifyKind($parsedDateTime, [System.DateTimeKind]::Unspecified)
}

function Resolve-ExcelOutputPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$OutputPath,

        [Parameter(Mandatory)]
        [string]$Timestamp
    )

    $expandedOutputPath = [Environment]::ExpandEnvironmentVariables($OutputPath.Trim())
    if ([string]::IsNullOrWhiteSpace($expandedOutputPath)) {
        throw 'OutputPath cannot be empty.'
    }

    $resolvedCandidate = if ([System.IO.Path]::IsPathRooted($expandedOutputPath)) {
        [System.IO.Path]::GetFullPath($expandedOutputPath)
    }
    else {
        [System.IO.Path]::GetFullPath((Join-Path -Path $PWD -ChildPath $expandedOutputPath))
    }

    $extension = [System.IO.Path]::GetExtension($resolvedCandidate)
    if ([string]::Equals($extension, '.xlsx', [System.StringComparison]::OrdinalIgnoreCase)) {
        $workbookPath = $resolvedCandidate
        $outputDirectory = Split-Path -Path $workbookPath -Parent
    }
    elseif (-not [string]::IsNullOrWhiteSpace($extension)) {
        throw "OutputPath must be a directory or a file ending in .xlsx. Received: $OutputPath"
    }
    else {
        $outputDirectory = $resolvedCandidate
        $workbookPath = Join-Path -Path $outputDirectory -ChildPath "RoomMailboxUsage_$Timestamp.xlsx"
    }

    if ([string]::IsNullOrWhiteSpace($outputDirectory)) {
        $outputDirectory = $PWD.Path
        $workbookPath = Join-Path -Path $outputDirectory -ChildPath ([System.IO.Path]::GetFileName($workbookPath))
    }

    New-Item -Path $outputDirectory -ItemType Directory -Force -ErrorAction Stop | Out-Null
    return $workbookPath
}

function Connect-RoomUsageGraph {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [bool]$UseInteractive,

        [string]$TenantId,
        [string]$ClientId,
        [string]$CertificateThumbprint
    )

    $requiredModules = @(
        'Microsoft.Graph.Authentication',
        'Microsoft.Graph.Calendar',
        'ImportExcel'
    )

    foreach ($moduleName in $requiredModules) {
        if (-not (Get-Module -Name $moduleName -ListAvailable)) {
            if ($moduleName -eq 'ImportExcel') {
                throw "Required module 'ImportExcel' is not installed. Install it with: Install-Module ImportExcel -Scope CurrentUser"
            }
            throw "Required module '$moduleName' is not installed. Install the Microsoft Graph PowerShell SDK before running this script."
        }
    }

    Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
    Import-Module Microsoft.Graph.Calendar -ErrorAction Stop
    Import-Module ImportExcel -ErrorAction Stop

    Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null

    if ($UseInteractive) {
        Connect-MgGraph `
            -Scopes 'Place.Read.All', 'Calendars.Read.Shared' `
            -NoWelcome `
            -ErrorAction Stop | Out-Null
    }
    else {
        $missingAuthenticationValues = @()
        if ([string]::IsNullOrWhiteSpace($TenantId)) { $missingAuthenticationValues += 'TenantId/AZURE_TENANT_ID' }
        if ([string]::IsNullOrWhiteSpace($ClientId)) { $missingAuthenticationValues += 'ClientId/AZURE_CLIENT_ID' }
        if ([string]::IsNullOrWhiteSpace($CertificateThumbprint)) { $missingAuthenticationValues += 'CertificateThumbprint/AZURE_CLIENT_CERTIFICATE_THUMBPRINT' }

        if (@($missingAuthenticationValues).Count -gt 0) {
            throw "Certificate authentication is incomplete. Missing: $($missingAuthenticationValues -join ', '). Use -Interactive or provide all certificate authentication values."
        }

        Connect-MgGraph `
            -TenantId $TenantId `
            -ClientId $ClientId `
            -CertificateThumbprint $CertificateThumbprint `
            -NoWelcome `
            -ErrorAction Stop | Out-Null
    }

    $graphContext = Get-MgContext
    if ($null -eq $graphContext) {
        throw 'Microsoft Graph authentication completed without returning a connection context.'
    }

    Write-Host "Connected to Microsoft Graph as $($graphContext.AuthType) authentication." -ForegroundColor Green
}

function Get-AllGraphRoomPlaces {
    [CmdletBinding()]
    param()

    $rooms = [System.Collections.Generic.List[object]]::new()
    $requestUri = 'https://graph.microsoft.com/v1.0/places/microsoft.graph.room?$top=100'

    while (-not [string]::IsNullOrWhiteSpace($requestUri)) {
        $response = Invoke-MgGraphRequest -Method GET -Uri $requestUri -OutputType PSObject -ErrorAction Stop

        foreach ($room in @($response.value)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$room.emailAddress)) {
                $rooms.Add($room)
            }
        }

        $nextLinkProperty = $response.PSObject.Properties['@odata.nextLink']
        if ($null -ne $nextLinkProperty) {
            $requestUri = [string]$nextLinkProperty.Value
        }
        else {
            $requestUri = $null
        }
    }

    return $rooms
}

function Get-GraphRoomList {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RoomList
    )

    $roomLists = [System.Collections.Generic.List[object]]::new()
    $requestUri = 'https://graph.microsoft.com/v1.0/places/microsoft.graph.roomlist?$top=100'

    while (-not [string]::IsNullOrWhiteSpace($requestUri)) {
        $response = Invoke-MgGraphRequest -Method GET -Uri $requestUri -OutputType PSObject -ErrorAction Stop
        foreach ($item in @($response.value)) { $roomLists.Add($item) }
        $nextLinkProperty = $response.PSObject.Properties['@odata.nextLink']
        $requestUri = if ($null -ne $nextLinkProperty) { [string]$nextLinkProperty.Value } else { $null }
    }

    $matchedRoomLists = @(
        $roomLists | Where-Object {
            [string]::Equals([string]$_.displayName, $RoomList, [System.StringComparison]::OrdinalIgnoreCase) -or
            [string]::Equals([string]$_.emailAddress, $RoomList, [System.StringComparison]::OrdinalIgnoreCase)
        }
    )

    if (@($matchedRoomLists).Count -eq 0) {
        throw "Room list '$RoomList' was not found. Specify its display name or email address."
    }
    if (@($matchedRoomLists).Count -gt 1) {
        throw "More than one room list matched '$RoomList'. Specify the room list email address to make the selection unambiguous."
    }

    return $matchedRoomLists[0]
}

function Get-RoomsInGraphRoomList {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RoomListEmailAddress
    )

    $rooms = [System.Collections.Generic.List[object]]::new()
    $encodedRoomListAddress = [System.Uri]::EscapeDataString($RoomListEmailAddress)
    $requestUri = "https://graph.microsoft.com/v1.0/places/$encodedRoomListAddress/microsoft.graph.roomlist/rooms?`$top=100"

    while (-not [string]::IsNullOrWhiteSpace($requestUri)) {
        $response = Invoke-MgGraphRequest -Method GET -Uri $requestUri -OutputType PSObject -ErrorAction Stop
        foreach ($room in @($response.value)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$room.emailAddress)) { $rooms.Add($room) }
        }
        $nextLinkProperty = $response.PSObject.Properties['@odata.nextLink']
        $requestUri = if ($null -ne $nextLinkProperty) { [string]$nextLinkProperty.Value } else { $null }
    }

    return $rooms
}

try {
    $reportTimeZone = [System.TimeZoneInfo]::FindSystemTimeZoneById($ReportTimeZoneId)

    $hasCertificateValues =
        -not [string]::IsNullOrWhiteSpace($TenantId) -and
        -not [string]::IsNullOrWhiteSpace($ClientId) -and
        -not [string]::IsNullOrWhiteSpace($CertificateThumbprint)

    # Default to certificate authentication when all three certificate values are available.
    # Otherwise use delegated authentication. Supplying only part of the certificate settings
    # is rejected by Connect-RoomUsageGraph rather than silently falling back.
    $useInteractiveAuthentication = $Interactive.IsPresent -or -not $hasCertificateValues

    Connect-RoomUsageGraph `
        -UseInteractive $useInteractiveAuthentication `
        -TenantId $TenantId `
        -ClientId $ClientId `
        -CertificateThumbprint $CertificateThumbprint

    $nowInReportTimeZone = [System.TimeZoneInfo]::ConvertTime([datetimeoffset]::Now, $reportTimeZone).DateTime
    if ($ShowTodaysMeetingsOnly) {
        $windowStartLocal = $nowInReportTimeZone.Date
    }
    else {
        $windowStartLocal = $nowInReportTimeZone.Date.AddDays(-$DaysBack)
    }
    $windowEndLocal = $nowInReportTimeZone.Date.AddDays(1)

    $windowStartOffset = [datetimeoffset]::new(
        $windowStartLocal,
        $reportTimeZone.GetUtcOffset($windowStartLocal)
    )
    $windowEndOffset = [datetimeoffset]::new(
        $windowEndLocal,
        $reportTimeZone.GetUtcOffset($windowEndLocal)
    )

    $startDateTime = $windowStartOffset.ToString('yyyy-MM-ddTHH:mm:sszzz', [System.Globalization.CultureInfo]::InvariantCulture)
    $endDateTime = $windowEndOffset.ToString('yyyy-MM-ddTHH:mm:sszzz', [System.Globalization.CultureInfo]::InvariantCulture)
    $requestHeaders = @{ Prefer = "outlook.timezone=`"$ReportTimeZoneId`"" }

    $timestamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
    $workbookPath = Resolve-ExcelOutputPath -OutputPath $OutputPath -Timestamp $timestamp
    if (Test-Path -LiteralPath $workbookPath) {
        Remove-Item -LiteralPath $workbookPath -Force -ErrorAction Stop
    }

    $detailedResults = [System.Collections.Generic.List[object]]::new()
    $summaryResults = [System.Collections.Generic.List[object]]::new()
    $errorResults = [System.Collections.Generic.List[object]]::new()

    if (-not [string]::IsNullOrWhiteSpace($RoomList) -and @($RoomEmailAddress).Count -gt 0) {
        throw 'Use either -RoomList or -RoomEmailAddress, not both.'
    }

    if (-not [string]::IsNullOrWhiteSpace($RoomList)) {
        $selectedRoomList = Get-GraphRoomList -RoomList $RoomList.Trim()
        $rooms = @(
            Get-RoomsInGraphRoomList -RoomListEmailAddress ([string]$selectedRoomList.emailAddress) |
                Sort-Object -Property displayName, emailAddress
        )
        if (@($rooms).Count -eq 0) {
            throw "Room list '$($selectedRoomList.displayName)' contains no rooms returned by Microsoft Graph."
        }
        Write-Host "Selected room list: $($selectedRoomList.displayName) <$($selectedRoomList.emailAddress)> ($(@($rooms).Count) rooms)" -ForegroundColor Cyan
    }
    else {
        $allRooms = @(Get-AllGraphRoomPlaces | Sort-Object -Property displayName, emailAddress)
        if (@($allRooms).Count -eq 0) {
            throw 'Microsoft Graph returned no room places with an email address.'
        }
    }

    if ([string]::IsNullOrWhiteSpace($RoomList) -and @($RoomEmailAddress).Count -gt 0) {
        $requestedRoomAddresses = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($requestedRoomAddress in $RoomEmailAddress) {
            if (-not [string]::IsNullOrWhiteSpace($requestedRoomAddress)) {
                $null = $requestedRoomAddresses.Add($requestedRoomAddress.Trim())
            }
        }

        $rooms = @(
            $allRooms | Where-Object { $requestedRoomAddresses.Contains([string]$_.emailAddress) }
        )

        $matchedRoomAddresses = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($matchedRoom in $rooms) {
            $null = $matchedRoomAddresses.Add([string]$matchedRoom.emailAddress)
        }

        $missingRoomAddresses = @(
            $requestedRoomAddresses | Where-Object { -not $matchedRoomAddresses.Contains($_) }
        )
        if (@($missingRoomAddresses).Count -gt 0) {
            throw "The following requested room address(es) were not returned by Microsoft Graph Places: $($missingRoomAddresses -join ', ')"
        }
    }
    elseif ([string]::IsNullOrWhiteSpace($RoomList)) {
        $rooms = $allRooms
    }

    $roomIndex = 0
    foreach ($room in $rooms) {
        $roomIndex++
        $roomName = if ([string]::IsNullOrWhiteSpace([string]$room.displayName)) { [string]$room.emailAddress } else { [string]$room.displayName }
        $roomAddress = [string]$room.emailAddress

        Write-Progress `
            -Activity 'Retrieving room mailbox usage' `
            -Status "Room $roomIndex of $(@($rooms).Count): $roomName" `
            -PercentComplete (($roomIndex / @($rooms).Count) * 100)

        try {
            $calendarEvents = @(
                Get-MgUserCalendarView `
                    -UserId $roomAddress `
                    -StartDateTime $startDateTime `
                    -EndDateTime $endDateTime `
                    -Headers $requestHeaders `
                    -Property @(
                        'id', 'subject', 'organizer', 'start', 'end', 'isAllDay',
                        'isCancelled', 'isOnlineMeeting', 'attendees',
                        'originalStartTimeZone', 'createdDateTime', 'lastModifiedDateTime'
                    ) `
                    -All `
                    -ErrorAction Stop
            )

            $filteredMeetingCount = 0
            $onlineMeetingCount = 0
            $allDayMeetingCount = 0
            $businessUsageMinutes = [double]0
            $elapsedDurationMinutes = [double]0
            $uniqueOrganizers = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

            foreach ($objEvent in $calendarEvents) {
                if ($objEvent.IsCancelled) {
                    continue
                }

                $organizer = [string]$objEvent.Organizer.EmailAddress.Address
                if ($OnlineMeetingOnly -and -not $objEvent.IsOnlineMeeting) {
                    continue
                }
                if (-not [string]::IsNullOrWhiteSpace($OrganizerEmailAddress) -and
                    -not [string]::Equals($OrganizerEmailAddress, $organizer, [System.StringComparison]::OrdinalIgnoreCase)) {
                    continue
                }

                $meetingStart = ConvertTo-ReportDateTime -DateTimeText $objEvent.Start.DateTime -ReportTimeZone $reportTimeZone
                $meetingEnd = ConvertTo-ReportDateTime -DateTimeText $objEvent.End.DateTime -ReportTimeZone $reportTimeZone

                # Defensive boundary check. CalendarView can include events that overlap the requested window.
                if ($meetingEnd -le $windowStartLocal -or $meetingStart -ge $windowEndLocal) {
                    continue
                }

                $eventElapsedMinutes = [math]::Max(0, ($meetingEnd - $meetingStart).TotalMinutes)
                $eventBusinessUsageMinutes = if ($objEvent.IsAllDay) {
                    [double]$AllDayBusinessUsageMinutes
                }
                else {
                    $eventElapsedMinutes
                }

                $requiredAttendees = @(
                    $objEvent.Attendees |
                        Where-Object { $_.Type -eq 'required' } |
                        ForEach-Object { $_.EmailAddress.Address } |
                        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
                )
                $optionalAttendees = @(
                    $objEvent.Attendees |
                        Where-Object { $_.Type -eq 'optional' } |
                        ForEach-Object { $_.EmailAddress.Address } |
                        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
                )
                $nonResourceAttendeeCount = @(
                    $objEvent.Attendees | Where-Object { $_.Type -ne 'resource' }
                ).Count

                $filteredMeetingCount++
                if ($objEvent.IsOnlineMeeting) { $onlineMeetingCount++ }
                if ($objEvent.IsAllDay) { $allDayMeetingCount++ }
                $businessUsageMinutes += $eventBusinessUsageMinutes
                $elapsedDurationMinutes += $eventElapsedMinutes
                if (-not [string]::IsNullOrWhiteSpace($organizer)) {
                    $null = $uniqueOrganizers.Add($organizer)
                }

                $detailedResults.Add([PSCustomObject][ordered]@{
                    RoomName                         = $roomName
                    RoomEmailAddress                 = $roomAddress
                    Organizer                        = $organizer
                    Subject                          = [string]$objEvent.Subject
                    StartTime                        = $meetingStart
                    EndTime                          = $meetingEnd
                    ReportTimeZone                   = $ReportTimeZoneId
                    ElapsedDurationMinutes           = [math]::Round($eventElapsedMinutes, 2)
                    BusinessUsageDurationMinutes     = [math]::Round($eventBusinessUsageMinutes, 2)
                    BusinessUsageDurationRule        = if ($objEvent.IsAllDay) { "All-day convention: $AllDayBusinessUsageMinutes minutes" } else { 'Actual elapsed minutes' }
                    TotalNonResourceAttendeeCount    = $nonResourceAttendeeCount
                    RequiredAttendees                = $requiredAttendees -join ','
                    OptionalAttendees                = $optionalAttendees -join ','
                    IsOnlineMeeting                  = [bool]$objEvent.IsOnlineMeeting
                    IsAllDayMeeting                  = [bool]$objEvent.IsAllDay
                    OriginalStartTimeZone            = [string]$objEvent.OriginalStartTimeZone
                    CreatedDateTime                  = $objEvent.CreatedDateTime
                    LastModifiedDateTime             = $objEvent.LastModifiedDateTime
                    EventId                          = [string]$objEvent.Id
                })
            }

            $summaryResults.Add([PSCustomObject][ordered]@{
                RoomName                             = $roomName
                RoomEmailAddress                     = $roomAddress
                FilteredMeetingCount                 = $filteredMeetingCount
                OnlineMeetingCount                   = $onlineMeetingCount
                AllDayMeetingCount                   = $allDayMeetingCount
                UniqueOrganizerCount                 = $uniqueOrganizers.Count
                TotalElapsedDurationMinutes          = [math]::Round($elapsedDurationMinutes, 2)
                TotalBusinessUsageDurationMinutes    = [math]::Round($businessUsageMinutes, 2)
                TotalBusinessUsageDurationHours      = [math]::Round(($businessUsageMinutes / 60), 2)
                AllDayBusinessUsageMinutesConvention = $AllDayBusinessUsageMinutes
                ReportWindowStart                    = $windowStartLocal
                ReportWindowEndExclusive             = $windowEndLocal
                ReportTimeZone                       = $ReportTimeZoneId
            })
        }
        catch {
            $errorResults.Add([PSCustomObject][ordered]@{
                Timestamp        = Get-Date
                RoomName         = $roomName
                RoomEmailAddress = $roomAddress
                Operation        = 'Get-MgUserCalendarView'
                ErrorMessage     = $_.Exception.Message
            })

            Write-Warning "Unable to process '$roomName' <$roomAddress>: $($_.Exception.Message)"
        }
    }

    Write-Progress -Activity 'Retrieving room mailbox usage' -Completed

    # Export one formatted Excel workbook. The Errors sheet is added only when room-level failures occur.
    $excelCommonParameters = @{
        Path          = $workbookPath
        TableStyle    = 'Medium2'
        AutoSize      = $true
        FreezeTopRow  = $true
        AutoFilter    = $true
        BoldTopRow    = $true
    }

    if (@($detailedResults).Count -gt 0) {
        $detailedResults | Export-Excel @excelCommonParameters -WorksheetName 'Detail' -TableName 'RoomUsageDetail'
    }
    else {
        $detailHeaders = [PSCustomObject][ordered]@{
            RoomName = $null; RoomEmailAddress = $null; Organizer = $null; Subject = $null
            StartTime = $null; EndTime = $null; ReportTimeZone = $null
            ElapsedDurationMinutes = $null; BusinessUsageDurationMinutes = $null
            BusinessUsageDurationRule = $null; TotalNonResourceAttendeeCount = $null
            RequiredAttendees = $null; OptionalAttendees = $null; IsOnlineMeeting = $null
            IsAllDayMeeting = $null; OriginalStartTimeZone = $null; CreatedDateTime = $null
            LastModifiedDateTime = $null; EventId = $null
        }
        $detailHeaders | Export-Excel @excelCommonParameters -WorksheetName 'Detail' -TableName 'RoomUsageDetail'
    }

    $summaryResults | Export-Excel @excelCommonParameters -WorksheetName 'Summary' -TableName 'RoomUsageSummary' -Append

    if (@($errorResults).Count -gt 0) {
        $errorResults | Export-Excel @excelCommonParameters -WorksheetName 'Errors' -TableName 'RoomUsageErrors' -Append
    }

    # Apply workbook-level formatting that is easier to manage after all sheets exist.
    $excelPackage = Open-ExcelPackage -Path $workbookPath
    try {
        foreach ($worksheetName in @('Detail', 'Summary', 'Errors')) {
            $worksheet = $excelPackage.Workbook.Worksheets[$worksheetName]
            if ($null -eq $worksheet) { continue }

            $worksheet.View.ShowGridLines = $false
            $worksheet.View.FreezePanes(2, 1)
            $worksheet.Row(1).Height = 24

            if ($null -ne $worksheet.Dimension) {
                $worksheet.Cells[$worksheet.Dimension.Address].Style.VerticalAlignment = 'Center'
            }
        }

        $detailWorksheet = $excelPackage.Workbook.Worksheets['Detail']
        if ($null -ne $detailWorksheet -and $null -ne $detailWorksheet.Dimension) {
            $detailWorksheet.Column(4).Width = 38
            $detailWorksheet.Column(5).Style.Numberformat.Format = 'yyyy-mm-dd hh:mm AM/PM'
            $detailWorksheet.Column(6).Style.Numberformat.Format = 'yyyy-mm-dd hh:mm AM/PM'
            $detailWorksheet.Column(12).Width = 35
            $detailWorksheet.Column(13).Width = 35
            $detailWorksheet.Column(18).Style.Numberformat.Format = 'yyyy-mm-dd hh:mm AM/PM'
            $detailWorksheet.Column(19).Style.Numberformat.Format = 'yyyy-mm-dd hh:mm AM/PM'
        }

        $summaryWorksheet = $excelPackage.Workbook.Worksheets['Summary']
        if ($null -ne $summaryWorksheet -and $null -ne $summaryWorksheet.Dimension) {
            $summaryWorksheet.Column(1).Width = 28
            $summaryWorksheet.Column(2).Width = 34
            $summaryWorksheet.Column(10).Style.Numberformat.Format = '0.00'
            $summaryWorksheet.Column(12).Style.Numberformat.Format = 'yyyy-mm-dd hh:mm AM/PM'
            $summaryWorksheet.Column(13).Style.Numberformat.Format = 'yyyy-mm-dd hh:mm AM/PM'
        }

        Close-ExcelPackage -ExcelPackage $excelPackage
    }
    catch {
        if ($null -ne $excelPackage) {
            Close-ExcelPackage -ExcelPackage $excelPackage -NoSave
        }
        throw
    }

    Write-Host ''
    Write-Host 'Room mailbox usage report completed.' -ForegroundColor Green
    Write-Host "Rooms discovered:             $(@($rooms).Count)"
    Write-Host "Rooms summarized:             $(@($summaryResults).Count)"
    Write-Host "Matching meetings exported:   $(@($detailedResults).Count)"
    Write-Host "Room-level errors:             $(@($errorResults).Count)"
    Write-Host "Excel workbook:                $workbookPath"

    if ($OpenReport -and $IsWindows) {
        Invoke-Item -LiteralPath $workbookPath
    }
    elseif ($OpenReport) {
        Write-Warning '-OpenReport is only implemented for Windows.'
    }

    Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null

    if (@($errorResults).Count -gt 0) {
        exit 2
    }
    exit 0
}
catch {
    Write-Error "Room mailbox usage report failed: $($_.Exception.Message)"
    Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
    exit 1
}
