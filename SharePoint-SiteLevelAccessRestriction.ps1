# Run as admin
# Required Settings - Check
#Get-SPOTenant | Select EnableRestrictedAccessControl
#Get-SPOTenant | Select AllowSharingOutsideRestrictedAccessControlGroups

#Requires -Modules Microsoft.Online.SharePoint.PowerShell

# Tenant/app settings
$TenantId   = "0bdf0e1f-a359-4b5c-9b79-9357e35ff8c6"
$ClientId   = "97d01716-c2a3-4311-9b73-09ac8579cbf1"
$Thumbprint = "94EF4B57723E2E90CD56F2F407EF6AFBEF275392"
$AdminUrl   = "https://enchantedrock-admin.sharepoint.com"

# RAC group object IDs
$AllUsersRestrictedGroupID = "31f49681-76cf-41e2-81cb-b306a2c38ce1"

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

# Optional test mode
# Set to one site URL to test one site only
  $TestSiteUrl = $null
#  $TestSiteUrl = "https://enchantedrock.sharepoint.com/sites/ContentTesting"

# Safety switch
$WhatIfMode = $false

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

# Import SPO module natively in PowerShell 7
Import-Module Microsoft.Online.SharePoint.PowerShell -ErrorAction Stop

# Certificate object method
$cert = Get-Item "Cert:\LocalMachine\My\$Thumbprint" -ErrorAction Stop

Write-Log "Connecting to SharePoint Online admin center." "INFO"

Connect-SPOService `
    -Url $AdminUrl `
    -ClientId $ClientId `
    -TenantId $TenantId `
    -Certificate $cert `
    -ErrorAction Stop

Write-Log "Connected to SharePoint Online." "SUCCESS"

# Confirm tenant-level RAC status
$TenantSettings = Get-SPOTenant
if (-not $TenantSettings.EnableRestrictedAccessControl) {
    Write-Log "Tenant-level Restricted Access Control is not enabled. Enabling now." "WARN"

    if ($WhatIfMode) {
        Write-Log "WHATIF: Would run Set-SPOTenant -EnableRestrictedAccessControl `$true" "WARN"
    }
    else {
        Set-SPOTenant -EnableRestrictedAccessControl $true -ErrorAction Stop
        Write-Log "Enabled tenant-level Restricted Access Control. It may take up to one hour to apply." "SUCCESS"
    }
}

# Strongly recommended for your use case
if ($TenantSettings.AllowSharingOutsideRestrictedAccessControlGroups -ne $false) {
    Write-Log "Tenant currently allows sharing outside RAC groups. Recommended setting is false for your use case." "WARN"

    if ($WhatIfMode) {
        Write-Log "WHATIF: Would run Set-SPOTenant -AllowSharingOutsideRestrictedAccessControlGroups `$false" "WARN"
    }
    else {
        Set-SPOTenant -AllowSharingOutsideRestrictedAccessControlGroups $false -ErrorAction Stop
        Write-Log "Disabled sharing outside Restricted Access Control groups." "SUCCESS"
    }
}

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

$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$ReportPath = "C:\Users\DakotaRuhl\Documents\Reports\SPOSiteRestrictions\SPO-RAC-Results-$Timestamp.csv"

$Results |
    Export-Csv `
        -Path $ReportPath `
        -NoTypeInformation `
        -Encoding UTF8

Write-Log "Report written to $ReportPath" "SUCCESS"

<# Get-SPOSite -Identity "https://enchantedrock.sharepoint.com/sites/ContentTesting" |
    Select-Object Url, RestrictedAccessControl, RestrictedAccessControlGroups #>

    <# Make a guest group, confirm all objects#>