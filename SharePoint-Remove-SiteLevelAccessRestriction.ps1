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
# $TestSiteUrl = "https://enchantedrock.sharepoint.com/sites/ContentTesting"
$WhatIfMode = -not [string]::IsNullOrWhiteSpace($TestSiteUrl)

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

        if ($CurrentSite.RestrictedAccessControl -ne $false -or $CurrentGroups.Count -gt 0) {
            $NeedsUpdate = $true
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
            Write-Log "WHATIF: Would disable RAC  on $($Site.Url)" "WARN"

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
            -ClearRestrictedAccessControl `
            -ErrorAction Stop

        $UpdatedSite = Get-SPOSite `
            -Identity $Site.Url `
            -ErrorAction Stop

        Write-Log "Disabled RAC on $($Site.Url)" "SUCCESS"

        $Results.Add([pscustomobject]@{
            Url                             = $Site.Url
            Status                          = "Updated"
            RestrictedAccessControl          = $UpdatedSite.RestrictedAccessControl
            RestrictedAccessControlGroups    = (@($UpdatedSite.RestrictedAccessControlGroups) -join ";")
            Message                         = "RAC disabled"
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

# Disable tenant-level RAC
Write-Log "Disabling tenant-level Restricted Access Control." "INFO"

if ($WhatIfMode) {
    Write-Log "WHATIF: Would run Set-SPOTenant -EnableRestrictedAccessControl `$false" "WARN"
}
else {
    Set-SPOTenant -EnableRestrictedAccessControl $true -ErrorAction Stop
    Write-Log "Disabled tenant-level Restricted Access Control." "SUCCESS"
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