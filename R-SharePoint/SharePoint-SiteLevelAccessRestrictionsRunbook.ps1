param(
    [boolean]$WhatIfMode = $true,

    [string]$TestSiteUrl = $null,

    [string]$LogSiteUrl = "https://enchantedrock.sharepoint.com/sites/itdepartment",

    [string]$OutputFolder = "Shared Documents/Infrastructure/M365/SPO Site Restrictions Logs",

    [string]$AllUsersRestrictedGroupID = "31f49681-76cf-41e2-81cb-b306a2c38ce1"
)

#Requires -Modules Microsoft.Online.SharePoint.PowerShell

# App settings
$AdminUrl   = "https://enchantedrock-admin.sharepoint.com"

$ErrorActionPreference = "Stop"
$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"

$TranscriptPath = "$env:TEMP\SiteAccessRestrictionsTranscript-$Timestamp.txt"
$ReportPath = "$env:TEMP\SharePoint-SiteLevelAccessRestrictionsRunbook-$Timestamp.xlsx"

$RestrictedAccessGroupIds = @(
    [guid]$AllUsersRestrictedGroupID
)

# Sites to exclude
# Add admin, app catalog, search, redirect, or any sites where you do not want RAC changed
$ExcludedSiteUrlPatterns = @(
    "-admin.sharepoint.com",
    "/sites/appcatalog",
    "/search",
    "/sites/redirect",
    "/portals"
)

function Write-Log {
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet("INFO", "WARN", "ERROR", "SUCCESS")]
        [string]$Level = "INFO"
    )

    $color = switch ($Level) {
        "INFO"    { "Cyan" }
        "WARN"    { "Yellow" }
        "ERROR"   { "Red" }
        "SUCCESS" { "Green" }
    }

    Write-Host "[$Level] $Message" -ForegroundColor $color
}

function Test-ExcludedSite { 
    param(
        [Parameter(Mandatory)]
        [string]$Url
    )

    foreach ($pattern in $ExcludedSiteUrlPatterns) {
        if ($Url -like "*$pattern*") {
            return $true
        }
    }

    return $false
}


Start-Transcript -Path $TranscriptPath
# Import SPO module natively in PowerShell 7
Import-Module Microsoft.Online.SharePoint.PowerShell -ErrorAction Stop

Write-Log "Connecting to SharePoint Online admin center." "INFO"

Connect-SPOService `
    -Url $AdminUrl `
    -ManagedIdentity

Write-Log "Connected to SharePoint Online." "SUCCESS"


# Get target sites
if ([string]::IsNullOrWhiteSpace($TestSiteUrl)) {
    Write-Log "Getting all SharePoint sites, excluding OneDrive." "INFO"

    $Sites = Get-SPOSite `
        -Limit All `
        -ErrorAction Stop |
        Where-Object {
            $_.Url -notlike "https://*-my.sharepoint.com/*" -and
            -not (Test-ExcludedSite -Url $_.Url)
        }
}
else {
    Write-Log "Test mode enabled. Targeting only $TestSiteUrl" "WARN"

    $Sites = @(
        Get-SPOSite `
            -Identity $TestSiteUrl `
            -ErrorAction Stop
    )
}

Write-Log "Found $($Sites.Count) site(s) to process." "INFO"

$Results = New-Object System.Collections.Generic.List[object]

foreach ($Site in $Sites) {
    Write-Log "Processing $($Site.Url)" "INFO"

    try {
        $CurrentSite = Get-SPOSite `
            -Identity $Site.Url `
            -ErrorAction Stop

        $CurrentGroups = @($CurrentSite.RestrictedAccessControlGroups)

        $NeedsUpdate = $false

        if ($CurrentSite.RestrictedAccessControl -ne $true) {
            $NeedsUpdate = $true
        }

        foreach ($GroupId in $RestrictedAccessGroupIds) {
            if ($CurrentGroups -notcontains $GroupId) {
                $NeedsUpdate = $true
            }
        }

        if (-not $NeedsUpdate) {
            Write-Log "Already configured correctly: $($Site.Url)" "SUCCESS"

            $Results.Add([pscustomobject]@{
                Url                             = $Site.Url
                Status                          = "Skipped"
                RestrictedAccessControl          = $CurrentSite.RestrictedAccessControl
                RestrictedAccessControlGroups    = ($CurrentGroups -join ";")
                Message                         = "Already configured"
            })

            continue
        }

        if ($WhatIfMode) {
            Write-Log "WHATIF: Would enable RAC and set groups on $($Site.Url)" "WARN"

            $Results.Add([pscustomobject]@{
                Url                             = $Site.Url
                Status                          = "WhatIf"
                RestrictedAccessControl          = $CurrentSite.RestrictedAccessControl
                RestrictedAccessControlGroups    = ($CurrentGroups -join ";")
                Message                         = "Would set RAC groups"
            })

            continue
        }

        Set-SPOSite `
            -Identity $Site.Url `
            -RestrictedAccessControl $true `
            -RestrictedAccessControlGroups $RestrictedAccessGroupIds `
            -ErrorAction Stop

        $UpdatedSite = Get-SPOSite `
            -Identity $Site.Url `
            -ErrorAction Stop

        Write-Log "Applied RAC to $($Site.Url)" "SUCCESS"

        $Results.Add([pscustomobject]@{
            Url                             = $Site.Url
            Status                          = "Updated"
            RestrictedAccessControl          = $UpdatedSite.RestrictedAccessControl
            RestrictedAccessControlGroups    = (@($UpdatedSite.RestrictedAccessControlGroups) -join ";")
            Message                         = "RAC applied"
        })
    }
    catch {
        Write-Log "Failed on $($Site.Url): $($_.Exception.Message)" "ERROR"

        $Results.Add([pscustomobject]@{
            Url                             = $Site.Url
            Status                          = "Failed"
            RestrictedAccessControl          = $null
            RestrictedAccessControlGroups    = $null
            Message                         = $_.Exception.Message
        })
    }
}


## Upload Logs
$Results |
    Group-Object Status |
    Select-Object Name, Count

$Results |
    Group-Object Status |
    ForEach-Object {
        Write-Log "$($_.Name): $($_.Count)" "INFO"
    }

$Results |
    Export-Excel `
        -Path $ReportPath `
        -WorksheetName "SPO-RAC-Results"

Stop-Transcript
try {
        Write-Log "Connecting to log site for upload: $LogSiteUrl" "INFO"

        $LogConnection = Connect-PnPOnline `
            -Url $LogSiteUrl `
            -ManagedIdentity `
            -ReturnConnection `
            -ErrorAction Stop

        Write-Log "Uploading report files to $LogSiteUrl/$OutputFolder" "INFO"

        if (Test-Path $ReportPath) {
            Add-PnPFile `
                -Path $ReportPath `
                -Folder $OutputFolder `
                -Connection $LogConnection `
                -ErrorAction Stop

            Write-Log "Uploaded report: $ReportPath" "SUCCESS"
        }
        else {
            Write-Log "Report file not found: $ReportPath" "ERROR"
        }

        if (Test-Path $TranscriptPath) {
            Add-PnPFile `
                -Path $TranscriptPath `
                -Folder $OutputFolder `
                -Connection $LogConnection `
                -ErrorAction Stop

            Write-Log "Uploaded transcript: $TranscriptPath" "SUCCESS"
        }
        else {
            Write-Log "Transcript file not found: $TranscriptPath" "WARN"
        }
    }
    catch {
        Write-Log "Failed uploading report files to SharePoint. $($_.Exception.Message)" "ERROR"
    }

Write-Log "Report written to $ReportPath" "SUCCESS"