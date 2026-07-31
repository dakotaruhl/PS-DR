<#
.SYNOPSIS
Monthly automation to maintain the Microsoft Teams external access allow list
based on the Teams Admin Center "External domains" usage export.

.DESCRIPTION
Phase 1 (Propose):
- Imports usage report (CSV or XLSX)
- Normalizes and filters domains
- Pulls current Teams tenant federation configuration
- Computes adds and removals
- Writes a Plan JSON that must be approved before apply

Phase 2 (Apply):
- Loads an approved Plan JSON
- Updates Teams tenant federation allow list

IMPORTANT:
When you configure an Allow list for external domains, all other domains are blocked. [1](https://enchantedrock.sharepoint.com/sites/itdepartment/_layouts/15/Doc.aspx?action=edit&mobileredirect=true&wdorigin=Sharepoint&DefaultItemOpen=1&sourcedoc={d7d84aad-b9e9-48c0-bb88-74797c938961}&wd=target(/M365.one/)&wdpartid={01b5ff38-aa9d-4f91-8900-669d7f0ef919}{11}&wdsectionfileid={44f30d7c-29ea-4626-a04c-fa17ae750dc1})

.PARAMETER Mode
Propose or Apply

.PARAMETER ReportPath
Path to the TAC export file (CSV or XLSX). For Apply, you can omit this if you supply -PlanPath.

.PARAMETER PlanPath
Path to the Plan JSON (output from Propose). Required for Apply.

.PARAMETER OutputFolder
Folder for logs, backups, and plan outputs.

.PARAMETER MinUserCount
Minimum "Users in your org" count to include a domain.

.PARAMETER ExcludePatterns
Wildcard patterns to exclude (default blocks *.onmicrosoft.com and common consumer mail domains).

.PARAMETER TenantId, AppId, CertificateThumbprint
Optional app-based auth for unattended runs. If omitted, the script uses interactive auth.

.EXAMPLE
.\Teams-UpdateExternalAllowList.ps1 -Mode Propose -ReportPath ".\Input Data\ActiveDomains_2026-07-31.csv" -OutputFolder ".\Output"

.EXAMPLE
# After reviewing the plan JSON and setting Approved=true
.\Teams-UpdateExternalAllowList.ps1 -Mode Apply -PlanPath .\output\TeamsExternalDomains-AllowListPlan_2026-04-27.json

#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Propose','Apply')]
    [string]$Mode,

    [Parameter(Mandatory = $false)]
    [string]$ReportPath,

    [Parameter(Mandatory = $false)]
    [string]$PlanPath,

    [Parameter(Mandatory = $false)]
    [string]$OutputFolder = ".\output",

    [Parameter(Mandatory = $false)]
    [int]$MinUserCount = 2,

    [Parameter(Mandatory = $false)]
    [string[]]$ExcludePatterns = @(
        "*.onmicrosoft.com",
        "gmail.com","yahoo.com","outlook.com","hotmail.com","live.com","aol.com"
    ),

    [Parameter(Mandatory = $false)]
    [string[]]$IncludeDomains = @(),

    [Parameter(Mandatory = $false)]
    [string[]]$ExcludeDomains = @(),

    # Auth options
    [Parameter(Mandatory = $false)]
    [string]$TenantId,

    [Parameter(Mandatory = $false)]
    [string]$AppId,

    [Parameter(Mandatory = $false)]
    [string]$CertificateThumbprint,

    [Parameter(Mandatory = $false)]
    [switch]$UseDeviceAuthentication,

    [Parameter(Mandatory = $false)]
    [string]$AccountId,

    [Parameter(Mandatory = $false)]
    [int]$MinimumFinalDomainCount = 10,

    [Parameter(Mandatory = $false)]
    [switch]$ApplyRemovals
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function New-FolderIfMissing {
    param([Parameter(Mandatory=$true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path | Out-Null
    }
}

function Write-Log {
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [Parameter(Mandatory=$false)][ValidateSet('INFO','WARN','ERROR')][string]$Level = 'INFO'
    )
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts][$Level] $Message"
    Write-Host $line
    if ($script:LogFile) { Add-Content -LiteralPath $script:LogFile -Value $line }
}

function Format-Domain {
    param([Parameter(Mandatory=$true)][string]$Domain)

    $d = $Domain.Trim().ToLowerInvariant()

    if ($d.StartsWith("@")) { $d = $d.Substring(1) }
    $d = $d.Trim(".")
    $d = ($d -replace "\s+", "")

    # Basic sanity: must contain at least one dot and valid characters
    if ($d -notmatch "^[a-z0-9][a-z0-9\.\-]*\.[a-z0-9][a-z0-9\-]*$") {
        return $null
    }
    return $d
}

function Test-Excluded {
    param(
        [Parameter(Mandatory=$true)][string]$Domain,
        [Parameter(Mandatory=$true)][string[]]$Patterns,
        [Parameter(Mandatory=$false)][string[]]$ExplicitExclude
    )

    foreach ($p in $Patterns) {
        if ($Domain -like $p) { return $true }
        if ($Domain -eq $p)  { return $true }
    }

    $normalizedExplicitExclude = @(
    $ExplicitExclude | ForEach-Object { Format-Domain $_ } | Where-Object { $_ }
    )

    if ($normalizedExplicitExclude -contains $Domain) {
        return $true
    }

    return $false
}


function Get-ReportRows {
    param([Parameter(Mandatory=$true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "ReportPath not found: $Path"
    }

    $ext = [IO.Path]::GetExtension($Path).ToLowerInvariant()

    if ($ext -eq ".csv") {
        return Import-Csv -LiteralPath $Path
    }

    if ($ext -eq ".xlsx") {
        if (-not (Get-Module -ListAvailable -Name ImportExcel)) {
            throw "XLSX input requires the ImportExcel module. Install-Module ImportExcel -Scope CurrentUser"
        }
        Import-Module ImportExcel -ErrorAction Stop
        return Import-Excel -Path $Path
    }

    throw "Unsupported report extension: $ext. Use CSV or XLSX."
}

function Connect-Teams {
    Write-Log "Loading MicrosoftTeams module"
    if (-not (Get-Module -ListAvailable -Name MicrosoftTeams)) {
        throw "MicrosoftTeams module is not installed. Install-Module MicrosoftTeams -Scope CurrentUser"
    }
    Import-Module MicrosoftTeams -ErrorAction Stop

    Write-Log "Connecting to Microsoft Teams"
    if ($TenantId -and $AppId -and $CertificateThumbprint) {
        # App-based auth (unattended) if your environment supports it
        Connect-MicrosoftTeams -TenantId $TenantId -ApplicationId $AppId -CertificateThumbprint $CertificateThumbprint | Out-Null
        Write-Log "Connected using app-based auth (TenantId/AppId/CertificateThumbprint)."
        return
    }

    if ($UseDeviceAuthentication) {
        Connect-MicrosoftTeams -UseDeviceAuthentication | Out-Null
        Write-Log "Connected using device authentication."
        return
    }

    if ($AccountId) {
        Connect-MicrosoftTeams -AccountId $AccountId | Out-Null
        Write-Log "Connected using interactive auth (AccountId)."
        return
    }

    Connect-MicrosoftTeams | Out-Null
    Write-Log "Connected using interactive auth."
}

function Get-FederationDomainValue {
    param(
        [Parameter(Mandatory = $false)]
        [object]$InputObject
    )

    if ($null -eq $InputObject) {
        return $null
    }

    $raw = $null

    if ($InputObject -is [string]) {
        $raw = $InputObject
    }
    else {
        # Teams federation objects commonly expose AllowedDomain.
        # Other object shapes may expose Domain, Name, or Value.
        foreach ($propertyName in @("AllowedDomain", "Domain", "Name", "Value")) {
            if ($InputObject.PSObject.Properties.Name -contains $propertyName) {
                $raw = [string]$InputObject.$propertyName
                break
            }
        }

        if (-not $raw) {
            $raw = [string]$InputObject
        }
    }

    if (-not $raw) {
        return $null
    }

    $raw = $raw.Trim()

    # Handles display strings like:
    # Domain=contoso.com
    # domain=contoso.com
    $raw = $raw -replace '(?i)^\s*domain\s*=\s*', ''

    return Format-Domain $raw
}

function Get-CurrentFederationState {
    $cfg = Get-CsTenantFederationConfiguration

    $mode = "AllowList"
    $current = New-Object System.Collections.Generic.List[string]
    $blocked = New-Object System.Collections.Generic.List[string]

    function Add-ParsedFederationDomain {
        param(
            [Parameter(Mandatory = $true)]
            [object]$Item,

            [AllowEmptyCollection()]
            [System.Collections.Generic.List[string]]$TargetList
        )

        if ($null -eq $Item) {
            return
        }

        $text = [string]$Item

        if ($text.Trim() -eq "AllowAllKnownDomains") {
            $script:DetectedAllowAllKnownDomains = $true
            return
        }

        # Sometimes Teams renders a collection as:
        # Domain=contoso.com, Domain=fabrikam.com
        if ($text -match "(?i)\bdomain\s*=" -and $text -match ",") {
            $parts = $text -split ","
            foreach ($part in $parts) {
                $d = Get-FederationDomainValue -InputObject $part
                if ($d) {
                    [void]$TargetList.Add($d)
                }
            }
            return
        }

        $d = Get-FederationDomainValue -InputObject $Item
        if ($d) {
            [void]$TargetList.Add($d)
        }
    }

    $script:DetectedAllowAllKnownDomains = $false

    if ($null -ne $cfg.AllowedDomains) {
        foreach ($item in @($cfg.AllowedDomains)) {
            Add-ParsedFederationDomain -Item $item -TargetList $current
        }
    }

    if ($script:DetectedAllowAllKnownDomains) {
        $mode = "AllowAllKnownDomains"
        $current.Clear()
    }

    if ($null -ne $cfg.BlockedDomains) {
        foreach ($item in @($cfg.BlockedDomains)) {
            Add-ParsedFederationDomain -Item $item -TargetList $blocked
        }
    }

    $currentFinal = @($current | Sort-Object -Unique)
    $blockedFinal = @($blocked | Sort-Object -Unique)

    [pscustomobject]@{
        Config         = $cfg
        Mode           = $mode
        AllowedDomains = $currentFinal
        BlockedDomains = $blockedFinal
    }
}

function Get-AllowDomainsAsAListSupported {
    $cmd = Get-Command Set-CsTenantFederationConfiguration -ErrorAction Stop
    if (-not $cmd.Parameters.ContainsKey("AllowedDomainsAsAList")) {
        throw "Your Set-CsTenantFederationConfiguration does not expose -AllowedDomainsAsAList. Update the MicrosoftTeams module to a newer version."
    }
}

function Build-CandidateDomains {
    param([Parameter(Mandatory=$true)][object[]]$Rows)

    # Expected columns from TAC export:
    # "Domain Name"
    # "Users in your org"
    $domains = @()

    foreach ($r in $Rows) {
        $domainVal = $null
        $userCountVal = $null

        if ($r.PSObject.Properties.Name -contains "Domain Name") { $domainVal = $r."Domain Name" }
        elseif ($r.PSObject.Properties.Name -contains "Domain") { $domainVal = $r."Domain" }

        if ($r.PSObject.Properties.Name -contains "Users in your org") { $userCountVal = $r."Users in your org" }
        elseif ($r.PSObject.Properties.Name -contains "Users") { $userCountVal = $r."Users" }

        if (-not $domainVal) { continue }

        $d = Format-Domain $domainVal
        if (-not $d) { continue }

        $n = 0
        if ($null -ne $userCountVal -and $userCountVal -ne "") {
            [void][int]::TryParse($userCountVal.ToString(), [ref]$n)
        }

        $domains += [pscustomobject]@{
            Domain = $d
            Users = $n
        }
    }

    # Aggregate by domain, keep max Users observed
    $grouped = $domains | Group-Object Domain | ForEach-Object {
        [pscustomobject]@{
            Domain = $_.Name
            Users  = (($_.Group | Measure-Object Users -Maximum).Maximum)
        }
    }

    # Apply filters
    $filtered = $grouped | Where-Object { $_.Users -ge $MinUserCount }

    $filtered = $filtered | Where-Object {
        -not (Test-Excluded -Domain $_.Domain -Patterns $ExcludePatterns -ExplicitExclude $ExcludeDomains)
    }

    if ($IncludeDomains.Count -gt 0) {
        $includeNormalized = $IncludeDomains | ForEach-Object { Format-Domain $_ } | Where-Object { $_ }
        $filtered = $filtered | Where-Object { $includeNormalized -contains $_.Domain }
    }

    $filtered | Sort-Object Users -Descending
}

function Write-PlanFile {
    param(
        [Parameter(Mandatory=$true)][pscustomobject]$Plan,
        [Parameter(Mandatory=$true)][string]$Folder
    )

    $ts = Get-Date -Format "yyyyMMdd_HHmmss"
    $file = Join-Path $Folder ("TeamsExternalDomains-AllowListPlan_{0}.json" -f $ts)


    $Plan | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $file -Encoding UTF8
    Write-Log "Wrote plan: $file"
    return $file
}

function Backup-CurrentConfig {
    param(
        [Parameter(Mandatory=$true)][pscustomobject]$State,
        [Parameter(Mandatory=$true)][string]$Folder
    )
    $ts = Get-Date -Format "yyyyMMdd_HHmmss"
    $file = Join-Path $Folder ("TeamsFederationConfigBackup_{0}.json" -f $ts)
    $obj = [pscustomobject]@{
        CapturedAt = (Get-Date).ToString("o")
        Mode = $State.Mode
        AllowedDomains = $State.AllowedDomains
        BlockedDomains = $State.BlockedDomains
        Raw = $State.Config
    }
    $obj | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $file -Encoding UTF8
    Write-Log "Backed up current federation config: $file"
}

function Export-CurrentAllowedDomains {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$State,

        [Parameter(Mandatory = $true)]
        [string]$Folder,

        [Parameter(Mandatory = $false)]
        [string]$Prefix = "CurrentTeamsAllowedDomains"
    )

    $ts = Get-Date -Format "yyyyMMdd_HHmmss"

    $csvPath  = Join-Path $Folder ("{0}_{1}.csv" -f $Prefix, $ts)
    $txtPath  = Join-Path $Folder ("{0}_{1}.txt" -f $Prefix, $ts)
    $jsonPath = Join-Path $Folder ("{0}_{1}.json" -f $Prefix, $ts)

    $domainObjects = @($State.AllowedDomains | ForEach-Object {
        [pscustomobject]@{
            Domain = $_
        }
    })

    $domainObjects | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8
    $State.AllowedDomains | Set-Content -LiteralPath $txtPath -Encoding UTF8

    [pscustomobject]@{
        CapturedAt = (Get-Date).ToString("o")
        Mode = $State.Mode
        AllowedDomainCount = @($State.AllowedDomains).Count
        AllowedDomains = $State.AllowedDomains
        BlockedDomainCount = @($State.BlockedDomains).Count
        BlockedDomains = $State.BlockedDomains
    } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

    Write-Log ("Exported current allowed domains CSV: {0}" -f $csvPath)
    Write-Log ("Exported current allowed domains TXT: {0}" -f $txtPath)
    Write-Log ("Exported current allowed domains JSON: {0}" -f $jsonPath)

    [pscustomobject]@{
        CsvPath = $csvPath
        TxtPath = $txtPath
        JsonPath = $jsonPath
    }
}

function Set-AllowList {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory=$true)][string[]]$FinalAllowedDomains
    )

    Get-AllowDomainsAsAListSupported

    $list = New-Object 'System.Collections.Generic.List[string]'
    foreach ($d in ($FinalAllowedDomains | Sort-Object -Unique)) {
        [void]$list.Add($d)
    }

    if ($PSCmdlet.ShouldProcess("Teams tenant federation configuration", "Set AllowedDomainsAsAList to $($list.Count) domains")) {
        Set-CsTenantFederationConfiguration -AllowedDomainsAsAList $list | Out-Null
        Write-Log "Applied allow list with $($list.Count) domains."
    }
}

# Main
New-FolderIfMissing -Path $OutputFolder
$script:LogFile = Join-Path $OutputFolder ("TeamsExternalDomains-AllowList_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
Write-Log "Starting Mode=$Mode"
Write-Log "OutputFolder=$OutputFolder"

Connect-Teams

if ($Mode -eq "Propose") {
    if (-not $ReportPath) { throw "ReportPath is required for Propose." }

    Write-Log "Loading report: $ReportPath"
    $rows = Get-ReportRows -Path $ReportPath
    Write-Log ("Loaded {0} rows from report" -f ($rows.Count))

    $candidate = Build-CandidateDomains -Rows $rows
    $candidateDomains = @($candidate | Select-Object -ExpandProperty Domain)

    Write-Log ("Candidate domains after filters: {0}" -f $candidateDomains.Count)

    $state = Get-CurrentFederationState
    $currentAllowedExports = Export-CurrentAllowedDomains -State $state -Folder $OutputFolder

    Write-Log ("Current allowed domains detected: {0}" -f @($state.AllowedDomains).Count)

    if ($state.Mode -eq "AllowList" -and @($state.AllowedDomains).Count -eq 0) {
        Write-Log "AllowList mode detected, but zero current allowed domains were parsed. This may indicate an object parsing issue." "WARN"

        $rawCfg = Get-CsTenantFederationConfiguration
        $sampleAllowed = @($rawCfg.AllowedDomains) | Select-Object -First 10

        foreach ($sample in $sampleAllowed) {
            if ($null -eq $sample) {
                Write-Log "AllowedDomains sample was null." "WARN"
                continue
            }

            Write-Log ("AllowedDomains sample type: {0}" -f $sample.GetType().FullName) "WARN"
            Write-Log ("AllowedDomains sample ToString: {0}" -f $sample.ToString()) "WARN"

            $propertyNames = ($sample.PSObject.Properties.Name -join ", ")
            Write-Log ("AllowedDomains sample properties: {0}" -f $propertyNames) "WARN"

            foreach ($prop in $sample.PSObject.Properties) {
                Write-Log ("AllowedDomains property {0}: {1}" -f $prop.Name, $prop.Value) "WARN"
            }
        }
    }

    Write-Log ("Current federation mode: {0}" -f $state.Mode)

    # If mode is AllowAllKnownDomains, current allow list is empty by definition for diff purposes
    $currentAllow = @($state.AllowedDomains)

    $adds = @(
        $candidateDomains |
        Where-Object { $currentAllow -notcontains $_ }
    )

    $removes = @(
        $currentAllow |
        Where-Object { $candidateDomains -notcontains $_ }
    )

    # Default Apply behavior: add new domains and preserve existing domains.
    $finalAllowedDomainsWithoutRemovals = @(
        $currentAllow
        $candidateDomains
    ) | Sort-Object -Unique

    # Destructive Apply behavior when -ApplyRemovals is used.
    $finalAllowedDomainsWithRemovals = @(
        $candidateDomains
    ) | Sort-Object -Unique

    $plan = [pscustomobject]@{
        GeneratedAt = (Get-Date).ToString("o")
        ReportPath = (Resolve-Path -LiteralPath $ReportPath).Path
        MinUserCount = $MinUserCount
        ExcludePatterns = $ExcludePatterns
        IncludeDomains = $IncludeDomains
        ExcludeDomains = $ExcludeDomains

        CurrentAllowedDomainCount = @($currentAllow).Count
        CandidateDomainCount = @($candidateDomains).Count
        ProposedAddCount = @($adds).Count
        ProposedRemovalCount = @($removes).Count
        FinalAllowedDomainCountWithoutRemovals = @($finalAllowedDomainsWithoutRemovals).Count
        FinalAllowedDomainCountWithRemovals = @($finalAllowedDomainsWithRemovals).Count

        CurrentFederationMode = $state.Mode
        CurrentAllowedDomains = $currentAllow
        CurrentBlockedDomains = $state.BlockedDomains
        CurrentAllowedDomainsCsv = $currentAllowedExports.CsvPath
        CurrentAllowedDomainsTxt = $currentAllowedExports.TxtPath
        CurrentAllowedDomainsJson = $currentAllowedExports.JsonPath

        CandidateDomainDetails = $candidate

        ProposedAdds = $adds
        ProposedRemovals = $removes
        FinalAllowedDomainsWithoutRemovals = $finalAllowedDomainsWithoutRemovals
        FinalAllowedDomainsWithRemovals = $finalAllowedDomainsWithRemovals
        DefaultApplyBehavior = "Preserve existing domains. Use -ApplyRemovals to apply ProposedRemovals."

        Approved = $false
        ApprovedBy = ""
        ApprovedAt = ""
        Notes = "Set Approved=true after review, then run Apply with -PlanPath."
    }

    Backup-CurrentConfig -State $state -Folder $OutputFolder
    $writtenPlan = Write-PlanFile -Plan $plan -Folder $OutputFolder

    Write-Log "Summary:"
    Write-Log ("Adds: {0}" -f $adds.Count)
    Write-Log ("Removals: {0}" -f $removes.Count)
    Write-Log ("Plan file: {0}" -f $writtenPlan)

    Write-Host ""
    Write-Host "Next steps:"
    Write-Host "1) Open the plan JSON and review ProposedAdds and ProposedRemovals."
    Write-Host "2) Set Approved=true, populate ApprovedBy and ApprovedAt."
    Write-Host "3) To add only and retain existing domains:"
    Write-Host "   .\Teams-UpdateExternalAllowList.ps1 -Mode Apply -PlanPath `"$writtenPlan`""
    Write-Host "4) To add and remove proposed removals:"
    Write-Host "   .\Teams-UpdateExternalAllowList.ps1 -Mode Apply -PlanPath `"$writtenPlan`" -ApplyRemovals"
    exit 0
}

if ($Mode -eq "Apply") {
    if (-not $PlanPath) { throw "PlanPath is required for Apply." }
    if (-not (Test-Path -LiteralPath $PlanPath)) { throw "PlanPath not found: $PlanPath" }

    Write-Log "Loading plan: $PlanPath"
    $plan = Get-Content -LiteralPath $PlanPath -Raw | ConvertFrom-Json

    if (-not $plan.Approved) {
        throw "Plan is not approved. Set Approved=true in the plan JSON before applying."
    }
    if ([string]::IsNullOrWhiteSpace($plan.ApprovedBy)) {
        throw "Plan is approved but ApprovedBy is empty."
    }

    if ([string]::IsNullOrWhiteSpace($plan.ApprovedAt)) {
        throw "Plan is approved but ApprovedAt is empty."
    }

    try {
        [datetime]::Parse($plan.ApprovedAt) | Out-Null
    }
    catch {
        throw "ApprovedAt must be a valid datetime value."
    }

    $state = Get-CurrentFederationState
    $currentAllow = @($state.AllowedDomains)

    if (-not $ApplyRemovals) {
        $final = @(
            $currentAllow
            $plan.ProposedAdds
        ) |
        ForEach-Object { Format-Domain $_ } |
        Where-Object { $_ } |
        Sort-Object -Unique

        $selectedApplyMode = "AddOnlyPreserveExisting"
        Write-Log "ApplyRemovals not specified. Existing domains will be retained."
    }
    else {
        $final = @(
            $plan.FinalAllowedDomainsWithRemovals
        ) |
        ForEach-Object { Format-Domain $_ } |
        Where-Object { $_ } |
        Sort-Object -Unique

        $selectedApplyMode = "AddAndRemove"
        Write-Log ("ApplyRemovals specified. This run will remove {0} domain(s) from the allow list." -f @($plan.ProposedRemovals).Count) "WARN"
    }

    $minimumPercentage = 0.5
    if ($currentAllow.Count -gt 0 -and $final.Count -lt ($currentAllow.Count * $minimumPercentage)) {
        throw "Final allow list is unexpectedly small compared to current state."
    }
    if ($final.Count -lt $MinimumFinalDomainCount) {
        throw "Refusing to apply. Final allow list contains only $($final.Count) domains, below safety floor of $MinimumFinalDomainCount."
    }

    Write-Log ("Selected apply mode: {0}" -f $selectedApplyMode)
    Write-Log ("Current domains: {0}" -f $currentAllow.Count)
    Write-Log ("Proposed adds: {0}" -f $plan.ProposedAdds.Count)
    Write-Log ("Proposed removals: {0}" -f $plan.ProposedRemovals.Count)
    Write-Log ("Final domains after processing: {0}" -f $final.Count)

    Backup-CurrentConfig -State $state -Folder $OutputFolder

    # This is the key control behavior: allow list means everything else is blocked. [1](https://enchantedrock.sharepoint.com/sites/itdepartment/_layouts/15/Doc.aspx?action=edit&mobileredirect=true&wdorigin=Sharepoint&DefaultItemOpen=1&sourcedoc={d7d84aad-b9e9-48c0-bb88-74797c938961}&wd=target(/M365.one/)&wdpartid={01b5ff38-aa9d-4f91-8900-669d7f0ef919}{11}&wdsectionfileid={44f30d7c-29ea-4626-a04c-fa17ae750dc1})
    Write-Log "Applying allow list. Reminder: allow list blocks all other external domains." 'WARN'

    Set-AllowList -FinalAllowedDomains $final
    if ($WhatIfPreference) {
    Write-Log "WhatIf mode detected. Skipping post-change validation because no change was applied." "WARN"
    Write-Log "Completed Apply in WhatIf mode."
    exit 0
}
    $stateAfter = Get-CurrentFederationState

    $postAllowed = @($stateAfter.AllowedDomains | Sort-Object -Unique)
    $expectedAllowed = @($final | Sort-Object -Unique)

    $missingAfterApply = @($expectedAllowed | Where-Object { $postAllowed -notcontains $_ })
    $unexpectedAfterApply = @($postAllowed | Where-Object { $expectedAllowed -notcontains $_ })

    if ($missingAfterApply.Count -gt 0 -or $unexpectedAfterApply.Count -gt 0) {
        Write-Log ("Post-change validation failed. Missing={0}; Unexpected={1}" -f $missingAfterApply.Count, $unexpectedAfterApply.Count) "ERROR"

        if ($missingAfterApply.Count -gt 0) {
            Write-Log ("Missing after apply: {0}" -f ($missingAfterApply -join ", ")) "ERROR"
        }

        if ($unexpectedAfterApply.Count -gt 0) {
            Write-Log ("Unexpected after apply: {0}" -f ($unexpectedAfterApply -join ", ")) "ERROR"
        }

        throw "Post-change validation failed. Review the backup, log, and post-change export."
    }

    Write-Log ("Post-change validation passed. Actual allowed domains match selected apply mode: {0}" -f $selectedApplyMode)


    $postAllowedExports = Export-CurrentAllowedDomains -State $stateAfter -Folder $OutputFolder -Prefix "PostChangeTeamsAllowedDomains"

    Write-Log ("Post-change federation mode: {0}" -f $stateAfter.Mode)
    $allowedCount = @($stateAfter.AllowedDomains).Count
    Write-Log ("Post-change allowed domains count: {0}" -f $allowedCount)
    Write-Log ("Post-change allowed domains CSV: {0}" -f $postAllowedExports.CsvPath)
    Write-Log ("Post-change allowed domains TXT: {0}" -f $postAllowedExports.TxtPath)
    Write-Log ("Post-change allowed domains JSON: {0}" -f $postAllowedExports.JsonPath)


    Write-Log "Completed Apply."
    exit 0
}