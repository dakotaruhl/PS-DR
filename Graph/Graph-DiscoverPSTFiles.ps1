<#
Testing

.\Graph-DiscoverPSTFiles.ps1 -TenantId "0bdf0e1f-a359-4b5c-9b79-9357e35ff8c6" `
                             -ClientId "ea2ca49b-d0df-4774-b611-86cf9dc9629f" `
                             -CertificateThumbprint "C47B91EB62634CA61FA8146DDA83B8BF605C0962" `
                             -OutputPath "C:\Users\DakotaRuhl\OneDrive - Enchanted Rock\IT Department - M365\Reporting\PSTInventory.xlsx"

.SYNOPSIS
    Finds PST files across SharePoint Online and OneDrive, then exports a migration/compliance workbook.

.DESCRIPTION
    - Enumerates SharePoint and OneDrive sites through Microsoft Graph.
    - Enumerates document libraries/drives for each site.
    - Searches each drive for .pst files.
    - Filters results to true .pst file names.
    - Exports:
        1. PST Files
        2. Largest PSTs
        3. Abandoned PSTs
        4. Remediation
        5. By Location
        6. Summary
        7. Errors

.NOTES
    Recommended auth:
    - App-only auth with certificate.

    Required Graph application permissions:
    - Sites.Read.All
    - Files.Read.All

    Recommended PowerShell modules:
    - Microsoft.Graph.Authentication
    - ImportExcel
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$TenantId,

    [Parameter(Mandatory)]
    [string]$ClientId,

    [Parameter(Mandatory)]
    [string]$CertificateThumbprint,

    [Parameter()]
    [string]$OutputPath = ".\PSTInventory.xlsx",

    [Parameter()]
    [int]$AbandonedYears = 3,

    [Parameter()]
    [double]$LargePstThresholdGB = 10,

    [Parameter()]
    [int]$RetryCount = 5,

    [Parameter()]
    [int]$RetrySeconds = 5,

    [Parameter()]
    [switch]$IncludeVerboseProgress
)

Start-Transcript -Path $OutputPath.Replace(".xlsx", "_run_$(Get-Date -Format 'yyyyMMdd_HHmmss').log") -Append | Out-Null
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-GraphProp {
    param(
        [Parameter(Mandatory)][AllowNull()]$Object,
        [Parameter(Mandatory)][string]$Name
    )

    if ($null -eq $Object) { return $null }

    # Invoke-MgGraphRequest returns hashtables; nested facets are hashtables too.
    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) { return $Object[$Name] }
        return $null
    }

    # PSObject fallback.
    $prop = $Object.PSObject.Properties[$Name]
    if ($prop) { return $prop.Value }
    return $null
}

function Get-AllOneDrives {
    [CmdletBinding()]
    param()

    # Directly enumerates OneDrive for every user, independent of whether
    # getAllSites happens to surface their personal site.
    $oneDrives = New-Object System.Collections.Generic.List[object]

    $users = Get-GraphPagedResults -Uri "/v1.0/users?`$select=id,displayName,userPrincipalName,accountEnabled&`$top=999" 

    Write-Info "Users returned by Graph: $($users.Count)"

    foreach ($user in $users) {
        if (-not $user.accountEnabled) {
            continue
        }

        try {
            $driveUri = "/v1.0/users/$($user.id)/drive?`$select=id,name,driveType,webUrl,owner"
            $drive = Invoke-GraphRequestWithRetry -Method GET -Uri $driveUri

            if ($drive -and $drive.id) {
                # Wrap in a pseudo-site object so it matches the shape
                # Get-PstFilesFromDrive already expects for -Site.
                $pseudoSite = [PSCustomObject]@{
                    id          = "onedrive-$($user.id)"
                    name        = $user.displayName
                    displayName = $user.displayName
                    webUrl      = $drive.webUrl
                }

                $oneDrives.Add([PSCustomObject]@{
                    Site  = $pseudoSite
                    Drive = $drive
                })
            }
        }
        catch {
            # A 404 here usually just means the user has never provisioned OneDrive.
            # That's expected for many accounts (shared mailboxes, disabled users, etc.)
            # and shouldn't be treated as a real error.
            if ($_.Exception.Message -notmatch "404") {
                Write-Warning "Could not resolve OneDrive for $($user.userPrincipalName): $($_.Exception.Message)"
            }
        }
    }

    Write-Info "OneDrives resolved directly via /users/{id}/drive: $($oneDrives.Count)"

    return $oneDrives
}

function Get-PreviousRemediationState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    # Returns a hashtable keyed by GraphDriveItemId so we can look up
    # prior HelpDeskStatus/HelpDeskNotes before overwriting the workbook.
    $previousState = @{}

    if (-not (Test-Path $Path)) {
        Write-Info "No previous workbook found at '$Path'. Starting fresh."
        return $previousState
    }

    try {
        $previousRows = Import-Excel -Path $Path -WorksheetName "Remediation" -ErrorAction Stop

        foreach ($row in $previousRows) {
            if ($row.PSObject.Properties.Name -contains "GraphDriveItemId" -and $row.GraphDriveItemId) {
                $previousState[$row.GraphDriveItemId] = [PSCustomObject]@{
                    HelpDeskStatus = $row.HelpDeskStatus
                    HelpDeskNotes  = $row.HelpDeskNotes
                }
            }
        }

        Write-Info "Loaded $($previousState.Count) prior remediation entries from '$Path'."
    }
    catch {
        Write-Warning "Could not read previous Remediation sheet from '$Path'. Starting fresh. Error: $($_.Exception.Message)"
    }

    return $previousState
}

function Export-SafeExcelSheet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [array]$Data,

        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$WorksheetName,

        [Parameter(Mandatory)]
        [string]$TableName,

        [Parameter()]
        [switch]$Append
    )

    $exportParams = @{
        Path          = $Path
        WorksheetName = $WorksheetName
        TableName     = $TableName
        AutoSize      = $true
        FreezeTopRow  = $true
        AutoFilter    = $true
        BoldTopRow    = $true
    }

    if ($Append) {
        $exportParams["Append"] = $true
    }

    if ($null -eq $Data -or $Data.Count -eq 0) {
        Write-Info "No rows for worksheet '$WorksheetName'. Writing placeholder row."

        @([PSCustomObject]@{
            Status  = "No data found"
            Details = "This report ran successfully but found zero matching rows for this tab."
            RanAt   = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        }) | Export-Excel @exportParams

        return
    }

    $Data | Export-Excel @exportParams
}

function Write-Info {
    param([string]$Message)
    Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message"
}

function Invoke-GraphRequestWithRetry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet("GET", "POST", "PATCH", "PUT", "DELETE")]
        [string]$Method,

        [Parameter(Mandatory)]
        [string]$Uri,

        [Parameter()]
        [object]$Body,

        [Parameter()]
        [int]$MaxRetries = $RetryCount,

        [Parameter()]
        [int]$BaseDelaySeconds = $RetrySeconds
    )

    $attempt = 0
    $retryableStatusCodes = @(429, 500, 502, 503, 504)

    while ($true) {
        $attempt++

        # -SkipHttpErrorCheck + -StatusCodeVariable is the reliable way to get the real
        # HTTP status from Invoke-MgGraphRequest. Reading $_.Exception.Response.StatusCode
        # does NOT work with this cmdlet and throws under Set-StrictMode.
        $statusCode = $null
        $response = $null
        $callFailedLocally = $false
        $localErrorMessage = $null

        try {
            if ($PSBoundParameters.ContainsKey("Body") -and $null -ne $Body) {
                $response = Invoke-MgGraphRequest -Method $Method -Uri $Uri -Body $Body -SkipHttpErrorCheck -StatusCodeVariable statusCode
            }
            else {
                $response = Invoke-MgGraphRequest -Method $Method -Uri $Uri -SkipHttpErrorCheck -StatusCodeVariable statusCode
            }
        }
        catch {
            $callFailedLocally = $true
            $localErrorMessage = $_.Exception.Message
        }

        if (-not $callFailedLocally -and $statusCode -ge 200 -and $statusCode -lt 300) {
            return $response
        }

        $graphErrorMessage = $null
        if ($response -is [System.Collections.IDictionary] -and $response.Contains('error') -and $response['error']) {
            $graphErrorMessage = "$($response['error'].code): $($response['error'].message)"
        }
        elseif ($response -and $response.PSObject.Properties.Name -contains 'error' -and $response.error) {
            $graphErrorMessage = "$($response.error.code): $($response.error.message)"
        }


        $effectiveMessage = if ($graphErrorMessage) { $graphErrorMessage } elseif ($localErrorMessage) { $localErrorMessage } else { "No further error detail was returned." }

        $isRetryableStatus = ($null -ne $statusCode -and $statusCode -in $retryableStatusCodes)

        if ($attempt -gt $MaxRetries -or (-not $isRetryableStatus -and -not $callFailedLocally)) {
            $finalStatusText = if ($statusCode) { $statusCode } else { "N/A (client-side failure)" }
            throw "Graph request failed permanently after $attempt attempt(s). Status: $finalStatusText. Error: $effectiveMessage. URI: $Uri"
        }

        $delay = [math]::Min(($BaseDelaySeconds * [math]::Pow(2, ($attempt - 1))), 120)

        $displayStatus = if ($statusCode) { $statusCode } else { "N/A (client-side failure)" }
        Write-Warning "Graph request failed. Attempt $attempt of $MaxRetries. Status: $displayStatus. Error: $effectiveMessage. Retrying after $delay seconds. URI: $Uri"
        Start-Sleep -Seconds $delay
    }
}

function Get-GraphPagedResults {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Uri
    )

    $allResults = New-Object System.Collections.Generic.List[object]
    $nextUri = $Uri

    while ($nextUri) {
        $response = Invoke-GraphRequestWithRetry -Method GET -Uri $nextUri

        if ($null -eq $response) {
            break
        }

        # Invoke-MgGraphRequest returns a Hashtable by default. Under Set-StrictMode -Version
        # Latest, reading a key/property that doesn't exist throws instead of returning $null.
        # So we must check for existence before accessing 'value' and '@odata.nextLink'.

        $value = $null
        $next  = $null

        if ($response -is [System.Collections.IDictionary]) {
            if ($response.Contains('value')) {
                $value = $response['value']
            }
            if ($response.Contains('@odata.nextLink')) {
                $next = $response['@odata.nextLink']
            }
        }
        else {
            # PSObject fallback (e.g. if -OutputType PSObject is ever used).
            $props = $response.PSObject.Properties.Name
            if ($props -contains 'value') {
                $value = $response.value
            }
            if ($props -contains '@odata.nextLink') {
                $next = $response.'@odata.nextLink'
            }
        }

        if ($value) {
            foreach ($item in $value) {
                $allResults.Add($item)
            }
        }

        $nextUri = $next
    }

    return $allResults
}

function Convert-BytesToGB {
    param([Nullable[double]]$Bytes)

    if ($null -eq $Bytes) {
        return $null
    }

    return [math]::Round(($Bytes / 1GB), 2)
}

function Convert-BytesToMB {
    param([Nullable[double]]$Bytes)

    if ($null -eq $Bytes) {
        return $null
    }

    return [math]::Round(($Bytes / 1MB), 2)
}

function Get-OneDriveOwnerFromUrl {
    param([string]$WebUrl)

    if ([string]::IsNullOrEmpty($WebUrl)) {
        return $null
    }

    # Common OneDrive personal site pattern:
    # https://tenant-my.sharepoint.com/personal/first_last_domain_com/...
    if ($WebUrl -match "/personal/([^/]+)") {
        $raw = $Matches[1]

        # This is only a best-effort owner candidate.
        # Do not treat this as authoritative for remediation without validation.
        return $raw
    }

    return $null
}

function Get-LocationType {
    param([string]$WebUrl)

    if ([string]::IsNullOrEmpty($WebUrl)) {
        return "Unknown"
    }

    if ($WebUrl -match "-my\.sharepoint\.com/personal/") {
        return "OneDrive"
    }

    return "SharePoint"
}

function Get-DriveDisplayName {
    param($Drive)

    if ($Drive.name) {
        return $Drive.name
    }

    if ($Drive.driveType) {
        return $Drive.driveType
    }

    return "Unknown Drive"
}

function Get-PstFilesFromDrive {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Site,

        [Parameter(Mandatory)]
        [object]$Drive,

        [Parameter()]
        [hashtable]$PreviousState = @{}
    )

    $results = New-Object System.Collections.Generic.List[object]
    $encodedQuery = [System.Uri]::EscapeDataString("pst")

    $uri = "/v1.0/drives/$($Drive.id)/root/search(q='$encodedQuery')?`$top=200&`$select=id,name,size,webUrl,createdDateTime,lastModifiedDateTime,createdBy,lastModifiedBy,file,parentReference"

    $searchResults = Get-GraphPagedResults -Uri $uri

    foreach ($item in $searchResults) {
        try {
            $fileFacet = Get-GraphProp $item 'file'
            if (-not $fileFacet) { continue }

            $name = Get-GraphProp $item 'name'
            if (-not $name) { continue }
            if ($name -notmatch "\.pst$") { continue }

            $webUrl = Get-GraphProp $item 'webUrl'
            $size   = Get-GraphProp $item 'size'

            $locationType           = Get-LocationType -WebUrl $webUrl
            $oneDriveOwnerCandidate = Get-OneDriveOwnerFromUrl -WebUrl $webUrl
            $sizeGB = Convert-BytesToGB -Bytes $size
            $sizeMB = Convert-BytesToMB -Bytes $size

            $lastModRaw = Get-GraphProp $item 'lastModifiedDateTime'
            $createdRaw = Get-GraphProp $item 'createdDateTime'

            $modifiedDate = $null
            if ($lastModRaw) { $modifiedDate = [datetime]$lastModRaw }

            $createdDate = $null
            if ($createdRaw) { $createdDate = [datetime]$createdRaw }

            $abandonedCutoff = (Get-Date).AddYears(-1 * $AbandonedYears)
            $isAbandoned = ($modifiedDate -and $modifiedDate -lt $abandonedCutoff)

            $isLarge = ($null -ne $sizeGB -and $sizeGB -ge $LargePstThresholdGB)

            $recommendedAction = switch ($true) {
                { $isLarge -and $isAbandoned } { "Priority review: large and abandoned PST. Validate owner, migrate or archive, then remove from SharePoint/OneDrive if approved."; break }
                { $isLarge }     { "Review for migration: large PST. Validate business owner and migration target."; break }
                { $isAbandoned } { "Review for cleanup: PST not modified within abandoned threshold. Validate retention/compliance requirements before deletion."; break }
                default          { "Review: validate owner and determine whether migration, retention, or removal is needed."; break }
            }

            $createdBy      = Get-GraphProp $item 'createdBy'
            $createdByUser  = Get-GraphProp $createdBy 'user'
            $modifiedBy     = Get-GraphProp $item 'lastModifiedBy'
            $modifiedByUser = Get-GraphProp $modifiedBy 'user'
            $parentRef      = Get-GraphProp $item 'parentReference'
            $itemId         = Get-GraphProp $item 'id'

            $helpDeskStatus = "Not Started"
            $helpDeskNotes  = $null
            if ($itemId -and $PreviousState.ContainsKey($itemId)) {
                $helpDeskStatus = $PreviousState[$itemId].HelpDeskStatus
                $helpDeskNotes  = $PreviousState[$itemId].HelpDeskNotes
            }

            $results.Add([PSCustomObject]@{
                FileName                = $name
                FileExtension           = "pst"
                SizeBytes               = $size
                SizeMB                  = $sizeMB
                SizeGB                  = $sizeGB
                IsLarge                 = $isLarge
                LargeThresholdGB        = $LargePstThresholdGB
                IsAbandoned             = $isAbandoned
                AbandonedThresholdYears = $AbandonedYears
                CreatedDateTime         = $createdDate
                LastModifiedDateTime    = $modifiedDate
                CreatedBy               = (Get-GraphProp $createdByUser  'displayName')
                CreatedByUPN            = (Get-GraphProp $createdByUser  'email')
                LastModifiedBy          = (Get-GraphProp $modifiedByUser 'displayName')
                LastModifiedByUPN       = (Get-GraphProp $modifiedByUser 'email')
                LocationType            = $locationType
                OneDriveOwnerCandidate  = $oneDriveOwnerCandidate
                SiteName                = $Site.name
                SiteDisplayName         = $Site.displayName
                SiteUrl                 = $Site.webUrl
                SiteId                  = $Site.id
                DriveName               = Get-DriveDisplayName -Drive $Drive
                DriveId                 = $Drive.id
                DriveType               = $Drive.driveType
                FileWebUrl              = $webUrl
                ParentDriveId           = (Get-GraphProp $parentRef 'driveId')
                ParentSiteId            = (Get-GraphProp $parentRef 'siteId')
                ParentPath              = (Get-GraphProp $parentRef 'path')
                GraphDriveItemId        = $itemId
                RecommendedAction       = $recommendedAction
                HelpDeskStatus          = $helpDeskStatus
                HelpDeskNotes           = $helpDeskNotes
            })
        }
        catch {
            Write-Warning "Skipping a search hit on drive '$($Drive.id)' due to: $($_.Exception.Message)"
            continue
        }
    }

    return $results
}

function Export-PstInventoryWorkbook {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [array]$PstFiles,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [array]$Errors,

        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter()]
        [hashtable]$PreviousState = @{}
    )
    # Removed duplicate CmdletBinding and param block as it was redundant.

    if (Test-Path $Path) {
        Remove-Item $Path -Force
    }

    $largest = $PstFiles |
        Sort-Object SizeGB -Descending |
        Select-Object -First 100

    $abandoned = $PstFiles |
        Where-Object { $_.IsAbandoned -eq $true } |
        Sort-Object LastModifiedDateTime

    $remediation = $PstFiles |
    Where-Object { $_.IsLarge -eq $true -or $_.IsAbandoned -eq $true } |
    Sort-Object @{ Expression = "IsLarge"; Descending = $true }, @{ Expression = "SizeGB"; Descending = $true }, LastModifiedDateTime |
    Select-Object `
        FileName,
        GraphDriveItemId,
        SizeGB,
        IsLarge,
        IsAbandoned,
        LastModifiedDateTime,
        LocationType,
        OneDriveOwnerCandidate,
        SiteDisplayName,
        SiteUrl,
        DriveName,
        LastModifiedBy,
        LastModifiedByUPN,
        FileWebUrl,
        RecommendedAction,
        HelpDeskStatus,
        HelpDeskNotes

    $byLocation = $PstFiles |
        Group-Object LocationType, SiteUrl |
        ForEach-Object {
            $group = $_.Group
            [PSCustomObject]@{
                LocationType   = $group[0].LocationType
                SiteUrl        = $group[0].SiteUrl
                SiteDisplayName = $group[0].SiteDisplayName
                PstCount       = $group.Count
                TotalSizeGB    = [math]::Round((($group | Measure-Object SizeGB -Sum).Sum), 2)
                LargestFileGB  = [math]::Round((($group | Measure-Object SizeGB -Maximum).Maximum), 2)
                AbandonedCount = @($group | Where-Object { $_.IsAbandoned }).Count
                LargeCount     = @($group | Where-Object { $_.IsLarge }).Count
            }
        } |
        Sort-Object TotalSizeGB -Descending
    
    $totalSizeGB = 0
    $largestGB = 0
    if ($PstFiles.Count -gt 0) {
        $totalSizeGB = [math]::Round((($PstFiles | Measure-Object SizeGB -Sum).Sum), 2)
        $largestGB = [math]::Round((($PstFiles | Measure-Object SizeGB -Maximum).Maximum), 2)
    }    
    $summary = @(
        [PSCustomObject]@{ Metric = "Report Generated"; Value = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss") }
        [PSCustomObject]@{ Metric = "Total PST Files"; Value = $PstFiles.Count }
        [PSCustomObject]@{ Metric = "Total PST Size GB"; Value = $totalSizeGB }
        [PSCustomObject]@{ Metric = "Largest PST GB"; Value = $largestGB }
        [PSCustomObject]@{ Metric = "Large PST Threshold GB"; Value = $LargePstThresholdGB }
        [PSCustomObject]@{ Metric = "Large PST Count"; Value = @($PstFiles | Where-Object { $_.IsLarge }).Count }
        [PSCustomObject]@{ Metric = "Abandoned Threshold Years"; Value = $AbandonedYears }
        [PSCustomObject]@{ Metric = "Abandoned PST Count"; Value = @($PstFiles | Where-Object { $_.IsAbandoned }).Count }
        [PSCustomObject]@{ Metric = "OneDrive PST Count"; Value = @($PstFiles | Where-Object { $_.LocationType -eq "OneDrive" }).Count }
        [PSCustomObject]@{ Metric = "SharePoint PST Count"; Value = @($PstFiles | Where-Object { $_.LocationType -eq "SharePoint" }).Count }
        [PSCustomObject]@{ Metric = "Locations With PSTs"; Value = @($PstFiles | Select-Object -ExpandProperty SiteUrl -Unique).Count }
        [PSCustomObject]@{ Metric = "Errors"; Value = $Errors.Count }
    )

    Export-SafeExcelSheet -Data ($PstFiles | Sort-Object SizeGB -Descending) `
        -Path $Path -WorksheetName "PST Files" -TableName "PSTFiles"

    Export-SafeExcelSheet -Data $largest `
        -Path $Path -WorksheetName "Largest PSTs" -TableName "LargestPSTs" -Append

    Export-SafeExcelSheet -Data $abandoned `
        -Path $Path -WorksheetName "Abandoned PSTs" -TableName "AbandonedPSTs" -Append

    Export-SafeExcelSheet -Data $remediation `
        -Path $Path -WorksheetName "Remediation" -TableName "Remediation" -Append

    Export-SafeExcelSheet -Data $byLocation `
        -Path $Path -WorksheetName "By Location" -TableName "ByLocation" -Append

    Export-SafeExcelSheet -Data $summary `
        -Path $Path -WorksheetName "Summary" -TableName "Summary" -Append

    Export-SafeExcelSheet -Data $Errors `
        -Path $Path -WorksheetName "Errors" -TableName "Errors" -Append

    # Add conditional formatting after export.
    $package = Open-ExcelPackage -Path $Path

    foreach ($wsName in @("PST Files", "Largest PSTs", "Abandoned PSTs", "Remediation", "By Location", "Summary", "Errors")) {
        $ws = $package.Workbook.Worksheets[$wsName]
        if ($null -eq $ws) {
            continue
        }

        $ws.View.FreezePanes(2, 1)
    }

    # Highlight large and abandoned values in PST Files.
    $pstWs = $package.Workbook.Worksheets["PST Files"]
    if ($pstWs -and $pstWs.Dimension.Rows -gt 1) {
        $headerMap = @{}

        for ($col = 1; $col -le $pstWs.Dimension.Columns; $col++) {
            $headerMap[$pstWs.Cells[1, $col].Text] = $col
        }

        if ($headerMap.ContainsKey("IsLarge")) {
            $col = $headerMap["IsLarge"]
            Add-ConditionalFormatting -Worksheet $pstWs -Range "$($pstWs.Cells[2,$col].Address):$($pstWs.Cells[$pstWs.Dimension.Rows,$col].Address)" -RuleType Equal -ConditionValue '"TRUE"' -BackgroundColor LightPink
        }

        if ($headerMap.ContainsKey("IsAbandoned")) {
            $col = $headerMap["IsAbandoned"]
            Add-ConditionalFormatting -Worksheet $pstWs -Range "$($pstWs.Cells[2,$col].Address):$($pstWs.Cells[$pstWs.Dimension.Rows,$col].Address)" -RuleType Equal -ConditionValue '"TRUE"' -BackgroundColor Khaki
        }
    }

    Close-ExcelPackage $package
}

# Main
$allPstFiles = New-Object System.Collections.Generic.List[object]
$errors = New-Object System.Collections.Generic.List[object]

Write-Info "Connecting to Microsoft Graph."

Connect-MgGraph -TenantId $TenantId -ClientId $ClientId -CertificateThumbprint $CertificateThumbprint -NoWelcome

try {
    $context = Get-MgContext
    if (-not $context) {
        throw "Microsoft Graph connection failed. No Graph context was returned."
    }

    Write-Info "Connected to tenant $($context.TenantId)."

    # Load prior remediation tracking data BEFORE anything overwrites the old file.
    $previousRemediationState = Get-PreviousRemediationState -Path $OutputPath

    Write-Info "Enumerating all SharePoint and OneDrive-backed sites."

    $sites = Get-GraphPagedResults -Uri "/v1.0/sites/getAllSites?`$select=id,name,displayName,webUrl,siteCollection"

    Write-Info "Sites returned by Graph: $($sites.Count)"

    # Track which drive IDs we've already queued, so the direct user-drive
    # fallback doesn't scan a OneDrive twice if getAllSites already caught it.
    $processedDriveIds = New-Object System.Collections.Generic.HashSet[string]

    $siteCounter = 0

    foreach ($site in $sites) {
        $siteCounter++
        
        Write-Progress -Id 1 -Activity "Scanning SharePoint/OneDrive sites" `
            -Status "Site $siteCounter of $($sites.Count): $($site.webUrl)" `
            -PercentComplete (($siteCounter / $sites.Count) * 100)
        
        if ($IncludeVerboseProgress) {
            Write-Info "Processing site $siteCounter of $($sites.Count): $($site.webUrl)"
        }

        try {
            $drives = Get-GraphPagedResults -Uri "/v1.0/sites/$($site.id)/drives?`$select=id,name,driveType,webUrl"

            foreach ($drive in $drives) {
                try {
                    [void]$processedDriveIds.Add($drive.id)

                    $pstFiles = Get-PstFilesFromDrive -Site $site -Drive $drive -PreviousState $previousRemediationState
                    foreach ($pst in $pstFiles) {
                        $allPstFiles.Add($pst)
                        if ($allPstFiles.Count -gt 0 -and $allPstFiles.Count % 25 -eq 0) {
                            Write-Info "PSTs found so far: $($allPstFiles.Count) (site $siteCounter of $($sites.Count))"
                        }
                    }
                }
                catch {
                    $errors.Add([PSCustomObject]@{
                        Scope        = "Drive"
                        SiteUrl      = $site.webUrl
                        SiteId       = $site.id
                        DriveName    = $drive.name
                        DriveId      = $drive.id
                        ErrorMessage = $_.Exception.Message
                    })
                }
            }
        }
        catch {
            $errors.Add([PSCustomObject]@{
                Scope        = "Site"
                SiteUrl      = $site.webUrl
                SiteId       = $site.id
                DriveName    = $null
                DriveId      = $null
                ErrorMessage = $_.Exception.Message
            })
        }
    }
    Write-Progress -Id 1 -Activity "Scanning SharePoint/OneDrive sites" -Completed

    # Fallback pass: directly enumerate every user's OneDrive to catch
    # personal sites that getAllSites may have missed.
    Write-Info "Running direct OneDrive fallback enumeration."

    $directOneDrives = Get-AllOneDrives
    $oneDriveCounter = 0
    $oneDriveTotal = $directOneDrives.Count


    foreach ($entry in $directOneDrives) {
        $oneDriveCounter++

        Write-Progress -Id 2 -Activity "Scanning OneDrive fallback" `
            -Status "OneDrive $oneDriveCounter of $($oneDriveTotal): $($entry.Site.webUrl)" `
            -PercentComplete (($oneDriveCounter / $oneDriveTotal) * 100)

        if ($processedDriveIds.Contains($entry.Drive.id)) {
            continue
        }

        [void]$processedDriveIds.Add($entry.Drive.id)
        
        try {
            $pstFiles = Get-PstFilesFromDrive -Site $entry.Site -Drive $entry.Drive -PreviousState $previousRemediationState
            foreach ($pst in $pstFiles) {
                $allPstFiles.Add($pst)
            }
        }
        catch {
            $errors.Add([PSCustomObject]@{
                Scope        = "OneDrive Fallback"
                SiteUrl      = $entry.Site.webUrl
                SiteId       = $entry.Site.id
                DriveName    = $entry.Drive.name
                DriveId      = $entry.Drive.id
                ErrorMessage = $_.Exception.Message
            })
        }
    }
    Write-Progress -Id 2 -Activity "Scanning OneDrive fallback" -Completed

    Write-Info "Total unique drives scanned: $($processedDriveIds.Count)"
    Write-Info "PST files discovered: $($allPstFiles.Count)"
    Write-Info "Errors captured: $($errors.Count)"
    Write-Info "Exporting workbook to $OutputPath"

    if ($errors.Count -gt 0) {
    Write-Info "Sample of errors encountered (showing up to 15):"$errors | Group-Object ErrorMessage | Sort-Object Count -Descending |
    Select-Object -First 15 Count, Name | Format-Table -AutoSize | Out-String | Write-Host
}

    Export-PstInventoryWorkbook -PstFiles $allPstFiles -Errors $errors -Path $OutputPath -PreviousState $previousRemediationState

    Write-Info "Done. Workbook created: $OutputPath"
}
finally {
    Disconnect-MgGraph | Out-Null
    Stop-Transcript | Out-Null
}

# View transcript live Get-Content "$OutputPath.Replace('.xlsx', '_run_*.log')" -Tail 20 -Wait