param(
    [Parameter(Mandatory = $true)]
    [string]$TenantId,

    [Parameter(Mandatory = $true)]
    [string]$ClientId,

    [Parameter(Mandatory = $true)]
    [string]$CertificateThumbprint,

    [int]$DaysOld = 30,

    [ValidateSet("ReportOnly", "Purge")]
    [string]$Mode = "ReportOnly",

    [string]$OutputFolder = ".",

    [int]$RecycleBinRowLimit = 5000
)


$TenantId = "0bdf0e1f-a359-4b5c-9b79-9357e35ff8c6"
$ClientId = "97d01716-c2a3-4311-9b73-09ac8579cbf1"
$Thumbprint = "94EF4B57723E2E90CD56F2F407EF6AFBEF275392"

Connect-AzAccount `
    -ServicePrincipal `
    -Tenant $TenantId `
    -ApplicationId $ClientId `
    -CertificateThumbprint $Thumbprint


$Username = $ClientId 

$Password = Get-AzKeyVaultSecret `
    -VaultName "SharePoint-Credentials" `
    -Name "EntraID-ClientSecret" `
    -AsPlainText

$SecurePassword = ConvertTo-SecureString $Password -AsPlainText -Force

$Credential = New-Object System.Management.Automation.PSCredential(
    $Username,
    $SecurePassword
)



$ErrorActionPreference = "Stop"

$RunStart = Get-Date
$CutoffUtc = (Get-Date).ToUniversalTime().AddDays(-$DaysOld)

$AdminUrl = "https://enchantedrock-admin.sharepoint.com"

$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$ReportPath = Join-Path $OutputFolder "TeamsRecordingRecycleBinPurge-$Timestamp.csv"
$ErrorPath = Join-Path $OutputFolder "TeamsRecordingRecycleBinPurge-Errors-$Timestamp.csv"

$Results = New-Object System.Collections.Generic.List[object]
$Errors = New-Object System.Collections.Generic.List[object]

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )

    $now = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$now][$Level] $Message"
}

function Connect-SitePnP {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url
    )

    Connect-PnPOnline `
        -Url $Url `
        -ClientId $ClientId `
        -Tenant $TenantId `
        -Thumbprint $CertificateThumbprint `
        -ErrorAction Stop
}

function Test-IsLikelyTeamsRecordingOrTranscript {
    param(
        [Parameter(Mandatory = $true)]
        $RecycleBinItem
    )

    $leafName = [string]$RecycleBinItem.LeafName
    $dirName = [string]$RecycleBinItem.DirName

    $extension = [System.IO.Path]::GetExtension($leafName).ToLowerInvariant()

    $isRecordingExtension = $extension -in @(".mp4")
    $isTranscriptExtension = $extension -in @(".vtt", ".docx")

    $nameLooksLikeTeamsArtifact =
        $leafName -match "(?i)recording" -or
        $leafName -match "(?i)transcript" -or
        $leafName -match "(?i)meeting"

    $pathLooksLikeRecordingsFolder =
        $dirName -match "(?i)(^|/|\\)Recordings($|/|\\)" -or
        $dirName -match "(?i)(^|/|\\)Documents(/|\\)Recordings($|/|\\)" -or
        $dirName -match "(?i)(^|/|\\)Shared Documents(/|\\)Recordings($|/|\\)"

    return (
        ($isRecordingExtension -or $isTranscriptExtension) -and
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

function Process-RecycleBinStage {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SiteUrl,

        [Parameter(Mandatory = $true)]
        [string]$Stage,

        [Parameter(Mandatory = $true)]
        [array]$Items
    )

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

        $ageDays = :Round(((Get-Date).ToUniversalTime() - $deletedUtc).TotalDays, 2)
        $isOldEnough = $deletedUtc -le $CutoffUtc
        $isTeamsArtifact = Test-IsLikelyTeamsRecordingOrTranscript -RecycleBinItem $item

        if (-not ($isOldEnough -and $isTeamsArtifact)) {
            continue
        }

        $action = "ReportOnly"
        $reason = "Matched Teams recording/transcript purge criteria"

        if ($Mode -eq "Purge") {
            try {
                Clear-PnPRecycleBinItem -Identity $item -Force -ErrorAction Stop
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
                    Error          = $_.Exception.Message
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

Write-Log "Starting Teams recording/transcript recycle bin purge job"
Write-Log "Mode: $Mode"
Write-Log "Cutoff UTC: $CutoffUtc"
Write-Log "Connecting to SharePoint admin: $AdminUrl"

Connect-SitePnP -Url $AdminUrl

Write-Log "Getting SharePoint and OneDrive sites"

$Sites = Get-PnPTenantSite -IncludeOneDriveSites -Detailed -ErrorAction Stop |
    Where-Object {
        $_.Url -notmatch "-admin\.sharepoint\.com" -and
        $_.Url -notmatch "/portals/" -and
        $_.Url -notmatch "/search"
    } |
    Sort-Object Url

Write-Log "Found $($Sites.Count) site collections to scan"

$siteCounter = 0

foreach ($site in $Sites) {
    $siteCounter++
    $siteUrl = $site.Url

    Write-Log "[$siteCounter/$($Sites.Count)] Scanning $siteUrl"

    try {
        Connect-SitePnP -Url $siteUrl

        $firstStageItems = @()
        $secondStageItems = @()

        try {
            $firstStageItems = @(Get-PnPRecycleBinItem -FirstStage -RowLimit $RecycleBinRowLimit -ErrorAction Stop)
        }
        catch {
            $Errors.Add([pscustomobject]@{
                SiteUrl        = $siteUrl
                Stage          = "FirstStage"
                ItemId         = $null
                LeafName       = $null
                DirName        = $null
                Error          = $_.Exception.Message
                TimeUtc        = (Get-Date).ToUniversalTime()
            })
        }

        try {
            $secondStageItems = @(Get-PnPRecycleBinItem -SecondStage -RowLimit $RecycleBinRowLimit -ErrorAction Stop)
        }
        catch {
            $Errors.Add([pscustomobject]@{
                SiteUrl        = $siteUrl
                Stage          = "SecondStage"
                ItemId         = $null
                LeafName       = $null
                DirName        = $null
                Error          = $_.Exception.Message
                TimeUtc        = (Get-Date).ToUniversalTime()
            })
        }

        Process-RecycleBinStage -SiteUrl $siteUrl -Stage "FirstStage" -Items $firstStageItems
        Process-RecycleBinStage -SiteUrl $siteUrl -Stage "SecondStage" -Items $secondStageItems
    }
    catch {
        Write-Log "Failed scanning $siteUrl. $($_.Exception.Message)" "ERROR"

        $Errors.Add([pscustomobject]@{
            SiteUrl        = $siteUrl
            Stage          = "SiteConnection"
            ItemId         = $null
            LeafName       = $null
            DirName        = $null
            Error          = $_.Exception.Message
            TimeUtc        = (Get-Date).ToUniversalTime()
        })
    }
}

$Results |
    Sort-Object SiteUrl, Stage, DeletedDateUtc |
    Export-Csv -Path $ReportPath -NoTypeInformation -Encoding UTF8

$Errors |
    Export-Csv -Path $ErrorPath -NoTypeInformation -Encoding UTF8

Write-Log "Completed"
Write-Log "Matched item report: $ReportPath"
Write-Log "Error report: $ErrorPath"
Write-Log "Matched count: $($Results.Count)"
Write-Log "Error count: $($Errors.Count)"

if ($Mode -eq "ReportOnly") {
    Write-Log "No items were deleted because Mode is ReportOnly"
}

