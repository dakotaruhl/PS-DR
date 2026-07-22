## .\Purge-ExpiredTeamsRecordings.ps1 -Mode ReportOnly -OutputFolder "C:\Users\DakotaRuhl\Documents\Reports\ExpiredRecordings"

param(
    [ValidateSet("ReportOnly", "Purge")]
    [string]$Mode = "ReportOnly",

    [string]$OutputFolder = ".",

    [int]$RecycleBinRowLimit = 5000
)

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )

    $Color = switch ($Level.ToUpper()) {
        "INFO"    { "White" }
        "SUCCESS" { "Green" }
        "WARN"    { "Yellow" }
        "ERROR"   { "Red" }
        "START"   { "Cyan" }
        default   { "Gray" }
    }

    $now = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$now][$Level] $Message" -ForegroundColor $Color
}

function Test-IsAccessDeniedError {
    param(
        [Parameter(Mandatory = $true)]
        $ErrorRecord
    )

    $text = $ErrorRecord.Exception.ToString()

    return (
        $text -match "0x80070005" -or
        $text -match "E_ACCESSDENIED" -or
        $text -match "Access is denied" -or
        $text -match 'status code is "Forbidden"'
    )
}

function Add-SiteAdminsFromTenantAdmin {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SiteUrl,

        [Parameter(Mandatory = $true)]
        $AdminConnection,

        [Parameter(Mandatory = $true)]
        [string[]]$Owners
    )

    try {
        Write-Log "Attempting to add site collection admin(s) to $($SiteUrl): $($Owners -join ', ')" "WARN"

        Set-PnPTenantSite `
            -Identity $SiteUrl `
            -Owners $Owners `
            -Connection $AdminConnection `
            -ErrorAction Stop

        Write-Log "Submitted site collection admin update for $SiteUrl" "SUCCESS"

        # Give SharePoint a little time to reflect the permission change
        Start-Sleep -Seconds 10

        return $true
    }
    catch {
        Write-Log "Failed adding site collection admin(s) to $SiteUrl. $($_.Exception.Message)" "ERROR"
        $Errors.Add([pscustomobject]@{
            SiteUrl      = $SiteUrl
            Stage        = "AddSiteCollectionAdmin"
            ItemId       = $null
            LeafName     = $null
            DirName      = $null
            ErrorType    = $_.Exception.GetType().FullName
            ErrorMessage = $_.Exception.Message
            FullError    = $_.Exception.ToString()
            TimeUtc      = (Get-Date).ToUniversalTime()
        })
        return $false
    }
}

function Connect-SitePnP {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url,

        [int]$RetryCount = 3,

        [int]$RetryDelaySeconds = 5,

        $AdminConnection = $null,

        [string[]]$OwnersToAddOnAccessDenied = @()
    )

    $normalizedUrl = $Url.TrimEnd('/')

    for ($attempt = 1; $attempt -le $RetryCount; $attempt++) {
        try {
            Write-Log "Connecting to $normalizedUrl. Attempt $attempt of $RetryCount" "INFO"

            $connection = Connect-PnPOnline `
                -Url $normalizedUrl `
                -ClientId $ClientId `
                -Tenant $TenantId `
                -Thumbprint $Thumbprint `
                -ReturnConnection `
                -ValidateConnection `
                -ErrorAction Stop

            $web = Get-PnPWeb `
                -Connection $connection `
                -ErrorAction Stop

            Write-Log "Connected to $normalizedUrl. Web title: $($web.Title)" "SUCCESS"

            return $connection
        }
        catch {
            $errorText = $_.Exception.ToString()
            $isAccessDenied = Test-IsAccessDeniedError -ErrorRecord $_

            if (
                $isAccessDenied -and
                $attempt -eq 1 -and
                $null -ne $AdminConnection -and
                $OwnersToAddOnAccessDenied.Count -gt 0 -and 
                $SitesSuccessfullyElevated.Contains($normalizedUrl) -eq $false
            ) 
            {
                Write-Log "Access denied connecting to $normalizedUrl. Trying to add site admin(s) before next retry." "WARN"

                $added = Add-SiteAdminsFromTenantAdmin `
                    -SiteUrl $normalizedUrl `
                    -AdminConnection $AdminConnection `
                    -Owners $OwnersToAddOnAccessDenied
                
                if ($added) {
                    $SitesSuccessfullyElevated.Add($normalizedUrl) | Out-Null
                    Write-Log "Site admin elevation recorded for $normalizedUrl" "SUCCESS"
                }
                else {
                    return $null
                }
            }

            if ($attempt -ge $RetryCount) {
                Write-Log "Failed to connect to $normalizedUrl after $RetryCount attempts. Skipping. Error: $($_.Exception.Message)" "ERROR"

                $Errors.Add([pscustomobject]@{
                    SiteUrl      = $normalizedUrl
                    Stage        = "SiteConnection"
                    ItemId       = $null
                    LeafName     = $null
                    DirName      = $null
                    ErrorType    = $_.Exception.GetType().FullName
                    ErrorMessage = $_.Exception.Message
                    FullError    = $errorText
                    TimeUtc      = (Get-Date).ToUniversalTime()
                })

                return $null
            }

            Write-Log "Connection attempt $attempt failed for $normalizedUrl. Retrying in $RetryDelaySeconds seconds. Error: $($_.Exception.Message)" "WARN"
            Start-Sleep -Seconds $RetryDelaySeconds
        }
    }
}

function Test-IsLikelyTeamsRecordingOrTranscript {
    param(
        [Parameter(Mandatory = $true)]
        $RecycleBinItem
    )

    $leafName = [string]$RecycleBinItem.LeafName
    $dirName = [string]$RecycleBinItem.DirName

    $extension = [System.IO.Path]::GetExtension($leafName).ToLowerInvariant()

    $isMatchedExtension = $extension -in @(".mp4", ".vtt", ".mp3")

    $nameLooksLikeTeamsArtifact =
        $leafName -match "(?i)channel meeting" -or
        $leafName -match "(?i)meeting in" -or
        $leafName -match "(?i)audio recap" -or 
        $leafName -match '(?i)-Meeting Recording(?: \d+)?\.mp4$' -or
        $leafName -match '(?i)-Meeting Transcript(?: \d+)?\.mp4$' -or
        $leafName -match '(?i)-Meeting Transcript(?: \d+)?\.vtt$' 

    $pathLooksLikeRecordingsFolder =
        $dirName -match "(?i)(^|/|\\)Recordings($|/|\\)" -or
        $dirName -match "(?i)(^|/|\\)Documents(/|\\)Recordings($|/|\\)" -or
        $dirName -match "(?i)(^|/|\\)Shared Documents(/|\\)Recordings($|/|\\)"

    return (
        ($isMatchedExtension) -and
        ($pathLooksLikeRecordingsFolder -or $nameLooksLikeTeamsArtifact)
    )
}

function Get-DeletedDateUtc {
    param($RecycleBinItem)

    if ($null -ne $RecycleBinItem.DeletedDate) {
        return ([datetime]$RecycleBinItem.DeletedDate).ToUniversalTime()
    }

    if ($null -ne $RecycleBinItem.DeletedDateLocalFormatted) {
        return ([datetime]$RecycleBinItem.DeletedDateLocalFormatted).ToUniversalTime()
    }

    return $null
}

function Invoke-RecycleBinStage {  
    param(
            [Parameter(Mandatory = $true)]
            [string]$SiteUrl,

            [Parameter(Mandatory = $true)]
            [string]$Stage,
  
            [Parameter(Mandatory = $false)]
            [array]$Items = @(),

            [Parameter(Mandatory = $true)]
            $Connection
        )
    
    if ($null -eq $Items -or $Items.Count -eq 0) {
            Write-Log "$Stage recycle bin is empty for $SiteUrl" "INFO"
            return
        }


    foreach ($item in $Items) {
        $deletedUtc = Get-DeletedDateUtc -RecycleBinItem $item

        if ($null -eq $deletedUtc) {
            $Results.Add([pscustomobject]@{
                RunStartUtc      = $RunStart.ToUniversalTime()
                SiteUrl          = $SiteUrl
                Stage            = $Stage
                ItemId           = $item.Id
                LeafName         = $item.LeafName
                DirName          = $item.DirName
                DeletedDateUtc   = $null
                AgeDays          = $null
                Matched          = $false
                Action           = "Skipped"
                Reason           = "Deleted date unavailable"
                Mode             = $Mode
            })
            continue
        }

        
        $ageDays = [math]::Round(($NowUtc - $deletedUtc).TotalDays, 2)
        $isTeamsArtifact = Test-IsLikelyTeamsRecordingOrTranscript -RecycleBinItem $item

        if (-not $isTeamsArtifact) {
            continue
        }

        $action = "ReportOnly"
        $reason = "Matched Teams recording/transcript purge criteria"

        if ($Mode -eq "Purge") {
            try {
                Clear-PnPRecycleBinItem `
                    -Identity $item.Id `
                    -Force `
                    -Connection $Connection `
                    -ErrorAction Stop
                $action = "Purged"
            }
            catch {
                $action = "Failed"
                $reason = $_.Exception.Message

                $Errors.Add([pscustomobject]@{
                    SiteUrl        = $SiteUrl
                    Stage          = $Stage
                    ItemId         = $item.Id
                    LeafName       = $item.LeafName
                    DirName        = $item.DirName
                    ErrorType    = $_.Exception.GetType().FullName
                    ErrorMessage = $_.Exception.Message
                    FullError    = $_.Exception.ToString()
                    TimeUtc        = (Get-Date).ToUniversalTime()
                })
            }
        }

        $Results.Add([pscustomobject]@{
            RunStartUtc      = $RunStart.ToUniversalTime()
            SiteUrl          = $SiteUrl
            Stage            = $Stage
            ItemId           = $item.Id
            LeafName         = $item.LeafName
            DirName          = $item.DirName
            DeletedDateUtc   = $deletedUtc
            AgeDays          = $ageDays
            Matched          = $true
            Action           = $action
            Reason           = $reason
            Mode             = $Mode
        })
    }
}

# -----------------------------
# Configuration
# -----------------------------

$TenantId = "0bdf0e1f-a359-4b5c-9b79-9357e35ff8c6"
$ClientId = "97d01716-c2a3-4311-9b73-09ac8579cbf1"
$Thumbprint = "94EF4B57723E2E90CD56F2F407EF6AFBEF275392"
$AdminUrl = "https://enchantedrock-admin.sharepoint.com"
$SiteAdminsToAddOnAccessDenied = @(
    "SharePoint Administrator"
)

$ErrorActionPreference = "Stop"
$RunStart = Get-Date

if (-not (Test-Path $OutputFolder)) {
    New-Item `
        -Path $OutputFolder `
        -ItemType Directory `
        -Force | Out-Null
}

$NowUtc = (Get-Date).ToUniversalTime()
$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$ReportPath = Join-Path $OutputFolder "TeamsRecordingRecycleBinPurge-$Timestamp.xlsx"

$Results = New-Object System.Collections.Generic.List[object]
$Errors = New-Object System.Collections.Generic.List[object]
$SitesSuccessfullyElevated = [System.Collections.Generic.HashSet[string]]::new()

# -----------------------------
# Main
# -----------------------------

# Connect to SharePoint Admin Center
Write-Log "Starting Teams recording/transcript recycle bin purge job" "START"
Write-Log "Mode: $Mode" "START"
Write-Log "Connecting to SharePoint admin: $AdminUrl" "START"

$AdminConnection = Connect-SitePnP -Url $AdminUrl
if ($null -eq $AdminConnection) {
    throw "Failed to connect to SharePoint Admin Center."
}
Write-Log "Connected to SharePoint admin center successfully" "SUCCESS"

# Get all SharePoint and OneDrive sites
Write-Log "Getting SharePoint and OneDrive sites" "START"
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$AllSites = Get-PnPTenantSite `
    -IncludeOneDriveSites `
    -Detailed `
    -Connection $AdminConnection `
    -ErrorAction Stop

Write-Log "Retrieved $($AllSites.Count) sites from SharePoint and OneDrive" "SUCCESS"

# Filter sites into included and excluded lists
$IncludedSites = [System.Collections.Generic.List[object]]::new()
$ExcludedSites = [System.Collections.Generic.List[object]]::new()
foreach ($site in $AllSites) {

    $reason = $null

    if ($site.Url -match "/personal/admin-") {
        $reason = "Admin OneDrive"
    }
    elseif ($site.Url -match "/portals/") {
        $reason = "Portal Site"
    }
    elseif ($site.Url -match "/search") {
        $reason = "Search Site"
    }
    elseif ([string]::IsNullOrWhiteSpace($site.Url)) {
        $reason = "MissingUrl"
    }
    elseif ($site.Url.TrimEnd("/") -eq "https://enchantedrock-my.sharepoint.com") {
        $reason = "OneDrive Root"
    }
    elseif ($site.Url.TrimEnd("/") -eq "https://enchantedrock.sharepoint.com") {
        $reason = "SharePoint Root"
    }
    elseif ($site.LockState -eq "NoAccess") {
        $reason = "LockState=NoAccess"
    }
    elseif ($site.LockState -eq "ReadOnly") {
        $reason = "LockState=ReadOnly"
    }

    if ($reason) { 
        $ExcludedSites.Add([pscustomobject]@{
            Url       = $site.Url
            Title     = $site.Title
            LockState = $site.LockState
            Reason    = $reason
        })
    }
    else {
        $IncludedSites.Add($site)
    }
}

$IncludedSites = $IncludedSites | Sort-Object Url -Unique
$AllSites = $AllSites | Sort-Object Url -Unique
$ExcludedSites = $ExcludedSites | Sort-Object Url -Unique

if ($IncludedSites.Count -eq 0) {
    throw "No sites matched filtering logic."
}
if (($IncludedSites.Count + $ExcludedSites.Count) -ne $AllSites.Count) {
    Write-Log "WARNING: Site counts do not reconcile!" "WARN"
}
else {
    Write-Log "Site counts reconcile correctly." "SUCCESS"
}

Write-Log "Total sites discovered: $($AllSites.Count)"
Write-Log "Included sites: $($IncludedSites.Count)"
Write-Log "Excluded sites: $($ExcludedSites.Count)"

$ExcludedSites | Export-Excel $ReportPath -WorksheetName "ExcludedSites" -AutoSize -AutoFilter -FreezeTopRow -BoldTopRow
$IncludedSites | Select-Object Url, Title, LockState | Export-Excel $ReportPath -WorksheetName "IncludedSites" -AutoSize -AutoFilter -FreezeTopRow -BoldTopRow -Append
$sw.Stop()
Write-Log "Found $($IncludedSites.Count) eligible site collections to scan. Took $($sw.Elapsed.TotalSeconds) seconds" "INFO"

# Scan included sites
$siteCounter = 0
foreach ($site in $IncludedSites) {
    $siteCounter++
    $siteUrl = $site.Url
    Write-Log "[$siteCounter/$($IncludedSites.Count)] Scanning $siteUrl" "START"

    try {
        $SiteConnection = Connect-SitePnP `
            -Url $siteUrl `
            -AdminConnection $AdminConnection `
            -OwnersToAddOnAccessDenied $SiteAdminsToAddOnAccessDenied

        if ($null -eq $SiteConnection) {
            Write-Log "Skipping $siteUrl because no valid PnP connection was returned" "WARN"
            continue
        }

        $firstStageItems = @()
        $secondStageItems = @()

        try {
            $firstStageItems = @(
                Get-PnPRecycleBinItem `
                    -FirstStage `
                    -RowLimit $RecycleBinRowLimit `
                    -Connection $SiteConnection `
                    -ErrorAction Stop
            )
            Write-Log "Retrieved $($firstStageItems.Count) first-stage items for $siteUrl" "INFO"
        }
        catch {
            Write-Log "Failed getting first-stage recycle bin items for $siteUrl. $($_.Exception.Message)" "ERROR"

            $Errors.Add([pscustomobject]@{
                SiteUrl       = $siteUrl
                Stage         = "FirstStage"
                ItemId        = $null
                LeafName      = $null
                DirName       = $null
                ErrorType     = $_.Exception.GetType().FullName
                ErrorMessage  = $_.Exception.Message
                FullError     = $_.Exception.ToString()
                TimeUtc       = (Get-Date).ToUniversalTime()
            })
        }
        try {
            $secondStageItems = @(
                Get-PnPRecycleBinItem `
                    -SecondStage `
                    -RowLimit $RecycleBinRowLimit `
                    -Connection $SiteConnection `
                    -ErrorAction Stop
            )
            Write-Log "Retrieved $($secondStageItems.Count) second-stage items for $siteUrl" "INFO"
        }
        catch {
            Write-Log "Failed getting second-stage recycle bin items for $siteUrl. $($_.Exception.Message)" "ERROR"

            $Errors.Add([pscustomobject]@{
                SiteUrl       = $siteUrl
                Stage         = "SecondStage"
                ItemId        = $null
                LeafName      = $null
                DirName       = $null
                ErrorType     = $_.Exception.GetType().FullName
                ErrorMessage  = $_.Exception.Message
                FullError     = $_.Exception.ToString()
                TimeUtc       = (Get-Date).ToUniversalTime()
            })
        }

        Invoke-RecycleBinStage `
            -SiteUrl $siteUrl `
            -Stage "FirstStage" `
            -Items $firstStageItems `
            -Connection $SiteConnection

        Invoke-RecycleBinStage `
            -SiteUrl $siteUrl `
            -Stage "SecondStage" `
            -Items $secondStageItems `
            -Connection $SiteConnection
    }
    catch {
        Write-Log "Failed scanning $siteUrl. $($_.Exception.Message)" "ERROR"

        $Errors.Add([pscustomobject]@{
            SiteUrl       = $siteUrl
            Stage         = "SiteScan"
            ItemId        = $null
            LeafName      = $null
            DirName       = $null
            ErrorType     = $_.Exception.GetType().FullName
            ErrorMessage  = $_.Exception.Message
            FullError     = $_.Exception.ToString()
            TimeUtc       = (Get-Date).ToUniversalTime()
        })

        continue
    }
}

# Export results
$Results |
    Sort-Object SiteUrl, Stage, DeletedDateUtc |
    Export-Excel -Path $ReportPath -WorksheetName "MatchedItems" -AutoSize -AutoFilter -FreezeTopRow -BoldTopRow -Append 
Write-Log "Exported MatchedItems to Excel" "SUCCESS"

$Errors |
    Export-Excel -Path $ReportPath -WorksheetName "Errors" -AutoSize -AutoFilter -FreezeTopRow -BoldTopRow -Append
Write-Log "Exported Errors to Excel" "SUCCESS"

$SitesSuccessfullyElevated | ForEach-Object {[pscustomobject]@{SiteUrl = $_}} | 
    Export-Excel -Path $ReportPath -WorksheetName "SitesSuccessfullyElevated" -AutoSize -AutoFilter -FreezeTopRow -BoldTopRow -Append
Write-Log "Exported SitesSuccessfullyElevated to Excel" "SUCCESS"

Write-Log "Completed" "SUCCESS" 
Write-Log "Full Report: $ReportPath" "SUCCESS"
Write-Log "Matched count: $($Results.Count)" "SUCCESS"
Write-Log "Error count: $($Errors.Count)" "SUCCESS"
Write-Log "Sites successfully elevated count: $($SitesSuccessfullyElevated.Count)" "SUCCESS"

if ($Mode -eq "ReportOnly") {
    Write-Log "No items were deleted because Mode is ReportOnly" "INFO"
}



<## Testing ##

$siteUrl = "https://enchantedrock.sharepoint.com/sites/erintranet"
$siteUrl = "https://enchantedrock-admin.sharepoint.com"


Connect-PnPOnline `
    -Url $siteUrl `
    -ClientId $ClientId `
    -Tenant $TenantId `
    -Thumbprint $Thumbprint

Get-PnPSiteCollectionAdmin
$PSVersionTable.PSEdition
$PSVersionTable.PSVersion
$PSVersionTable.OS

Add-PnPSiteCollectionAdmin `
    -Owners "SharePoint Administrator" 
    
    
$Items = Get-PnPRecycleBinItem `
    -FirstStage `
    -RowLimit 5000 `
    -Connection $SiteConnection

$Items.Count

##
Connect-MgGraph -Scopes RoleManagement.ReadWrite.Directory

$ServicePrincipalId = (Get-MgServicePrincipal -Filter "displayName eq 'Teams-RecordingRetention-Scrubber'").Id

$RoleId = (Get-MgDirectoryRole |
    Where-Object DisplayName -eq "SharePoint Administrator").Id

New-MgDirectoryRoleMemberByRef `
    -DirectoryRoleId $RoleId `
    -OdataId "https://graph.microsoft.com/v1.0/directoryObjects/$($ServicePrincipalId)"

##verify 
Get-MgDirectoryRoleMember -DirectoryRoleId $RoleId -All | FL

Connect-PnPOnline -Url "https://enchantedrock-admin.sharepoint.com" -ManagedIdentity

Get-PnPWeb
##
Get-PnPContext
Get-PnPTenantSite -Identity "https://enchantedrock.sharepoint.com/sites/itdepartment"
## End testing ##>
