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
.\Teams-UpdateExternalAllowList.ps1 -Mode Propose -ReportPath .\ExternalDomains.csv

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
    [string]$AccountId
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

function Normalize-Domain {
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

    if ($ExplicitExclude -and $ExplicitExclude -contains $Domain) {
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

function Get-CurrentFederationState {
    $cfg = Get-CsTenantFederationConfiguration
    $allowedRaw = $cfg.AllowedDomains

    $mode = "AllowList"
    $current = @()

    if ($null -eq $allowedRaw) {
        # Explicit allow list, currently empty
        $mode = "AllowList"
        $current = @()
    }
    elseif ($allowedRaw -is [string]) {
        if ($allowedRaw -eq "AllowAllKnownDomains") {
            $mode = "AllowAllKnownDomains"
            $current = @()
        } else {
            $current = @(
                $allowedRaw -split "," |
                ForEach-Object {
                    Normalize-Domain ($_ -replace "^domain=", "")
                } |
                Where-Object { $_ }
            )
        }
    }
    elseif ($allowedRaw -is [System.Collections.IEnumerable]) {
        foreach ($item in $allowedRaw) {
            if ($item -is [string]) {
                if ($item -eq "AllowAllKnownDomains") {
                    $mode = "AllowAllKnownDomains"
                    $current = @()
                    break
                }
                $d = Normalize-Domain ($item -replace "^domain=", "")
                if ($d) { $current += $d }
            }
            elseif ($item.PSObject.Properties.Match("Domain").Count -gt 0) {
                $d = Normalize-Domain $item.Domain
                if ($d) { $current += $d }
            }
            else {
                $d = Normalize-Domain ($item.ToString())
                if ($d) { $current += $d }
            }
        }
    }

    $current = $current | Sort-Object -Unique

    [pscustomobject]@{
        Config         = $cfg
        Mode           = $mode
        AllowedDomains = $current
        BlockedDomains = @(
            $cfg.BlockedDomains |
            ForEach-Object {
                if ($_.PSObject.Properties.Match("Domain").Count -gt 0) {
                    $_.Domain
                } else {
                    $_.ToString()
                }
            }
        )
    }
}


function Ensure-AllowDomainsAsAListSupported {
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

        $d = Normalize-Domain $domainVal
        if (-not $d) { continue }

        $n = 0
        if ($userCountVal -ne $null -and $userCountVal -ne "") {
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
        $includeNormalized = $IncludeDomains | ForEach-Object { Normalize-Domain $_ } | Where-Object { $_ }
        $filtered = $filtered | Where-Object { $includeNormalized -contains $_.Domain }
    }

    $filtered | Sort-Object Users -Descending
}

function Write-PlanFile {
    param(
        [Parameter(Mandatory=$true)][pscustomobject]$Plan,
        [Parameter(Mandatory=$true)][string]$Folder
    )

    $ts = Get-Date -Format "yyyy-MM-dd"
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

function Set-AllowList {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory=$true)][string[]]$FinalAllowedDomains
    )

    Ensure-AllowDomainsAsAListSupported

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
    Write-Log ("Current federation mode: {0}" -f $state.Mode)

    # If mode is AllowAllKnownDomains, current allow list is empty by definition for diff purposes
    $currentAllow = @($state.AllowedDomains)

    $adds = @($candidateDomains | Where-Object { $currentAllow -notcontains $_ })
    $removes = @($currentAllow | Where-Object { $candidateDomains -notcontains $_ })

    $plan = [pscustomobject]@{
        GeneratedAt = (Get-Date).ToString("o")
        ReportPath = (Resolve-Path -LiteralPath $ReportPath).Path
        MinUserCount = $MinUserCount
        ExcludePatterns = $ExcludePatterns
        IncludeDomains = $IncludeDomains
        ExcludeDomains = $ExcludeDomains

        CurrentFederationMode = $state.Mode
        CurrentAllowedDomains = $currentAllow
        CurrentBlockedDomains = $state.BlockedDomains

        CandidateDomains = $candidate
        ProposedAdds = $adds
        ProposedRemovals = $removes

        FinalAllowedDomains = $candidateDomains

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
    Write-Host "3) Run Apply: .\Teams-UpdateExternalAllowList.ps1 -Mode Apply -PlanPath `"$writtenPlan`""
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

    $final = @($plan.FinalAllowedDomains | ForEach-Object { Normalize-Domain $_ } | Where-Object { $_ } | Sort-Object -Unique)

    Write-Log ("Final allow list domains in plan: {0}" -f $final.Count)

    $state = Get-CurrentFederationState
    Backup-CurrentConfig -State $state -Folder $OutputFolder

    # This is the key control behavior: allow list means everything else is blocked. [1](https://enchantedrock.sharepoint.com/sites/itdepartment/_layouts/15/Doc.aspx?action=edit&mobileredirect=true&wdorigin=Sharepoint&DefaultItemOpen=1&sourcedoc={d7d84aad-b9e9-48c0-bb88-74797c938961}&wd=target(/M365.one/)&wdpartid={01b5ff38-aa9d-4f91-8900-669d7f0ef919}{11}&wdsectionfileid={44f30d7c-29ea-4626-a04c-fa17ae750dc1})
    Write-Log "Applying allow list. Reminder: allow list blocks all other external domains." 'WARN'

    Set-AllowList -FinalAllowedDomains $final

    $stateAfter = Get-CurrentFederationState
    Write-Log ("Post-change federation mode: {0}" -f $stateAfter.Mode)
    $allowedCount = @($stateAfter.AllowedDomains).Count
    Write-Log ("Post-change allowed domains count: {0}" -f $allowedCount)


    Write-Log "Completed Apply."
    exit 0
}

# .\Teams-UpdateExternalAllowList.ps1 -Mode Propose -ReportPath .\ExternalDomains.csv
# apply
# .\Teams-UpdateExternalAllowList.ps1 -Mode Apply -PlanPath .\output\TeamsExternalDomains-AllowListPlan_2026-04-27.json

#(Get-CsTenantFederationConfiguration).AllowedDomains.AllowedDomain | Export-Excel -Path "C:\Users\DakotaRuhl\Documents\Reports\CurrentAllowedDomains.xlsx" -AutoSize -WorksheetName "AllowedDomains"