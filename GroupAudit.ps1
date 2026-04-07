<#
.SYNOPSIS
  Reverse-lookup where an Entra group is referenced across M365 workloads:
  - Conditional Access
  - Enterprise App (Service Principal) assignments
  - Entra Directory Role assignments
  - Intune assignments (common policy/app types)
  - Optional SharePoint site permissions scan (PnP)

.PARAMETER Group
  Group display name OR ObjectId (GUID).

.PARAMETER OutputCsv
  Path to export results CSV.

.PARAMETER IncludeSharePoint
  Also scan SharePoint Online site-level permissions (site collections).

.PARAMETER SPOAdminUrl
  Required if -IncludeSharePoint and you want to enumerate sites (e.g. https://contoso-admin.sharepoint.com).

.PARAMETER SiteUrls
  Optional explicit site URLs to scan (skips tenant enumeration).

.PARAMETER MaxSites
  When enumerating, limit number of sites scanned (default 200).

.PARAMETER UseBetaForIntune
  Use beta endpoints for some Intune objects (Settings catalog/configurationPolicies and some assignment sets).
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory)]
  [string]$Group,

  [string]$OutputCsv = ".\GroupUsageReport.csv",

  [switch]$IncludeSharePoint,

  [string]$SPOAdminUrl,

  [string[]]$SiteUrls,

  [int]$MaxSites = 200,

  [switch]$UseBetaForIntune
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Ensure-Module {
  param([Parameter(Mandatory)][string]$Name)
  if (-not (Get-Module -ListAvailable -Name $Name)) {
    throw "Required module '$Name' not found. Install with: Install-Module $Name -Scope CurrentUser"
  }
}

function Invoke-GraphPaged {
  param(
    [Parameter(Mandatory)][string]$Uri,
    [ValidateSet("v1.0","beta")][string]$ApiVersion = "v1.0"
  )
  $items = New-Object System.Collections.Generic.List[object]
  $next = $Uri

  while ($next) {
    $resp = Invoke-MgGraphRequest -Method GET -Uri $next -ApiVersion $ApiVersion
    if ($resp.value) { $resp.value | ForEach-Object { [void]$items.Add($_) } }
    $next = $resp.'@odata.nextLink'
  }
  return $items
}

function Add-Result {
  param(
    [string]$Workload,
    [string]$ObjectType,
    [string]$Name,
    [string]$Id,
    [string]$ScopeOrUrl,
    [string]$Assignment,
    [string]$Notes
  )
  [PSCustomObject]@{
    Workload   = $Workload
    ObjectType = $ObjectType
    Name       = $Name
    Id         = $Id
    ScopeOrUrl = $ScopeOrUrl
    Assignment = $Assignment
    Notes      = $Notes
  }
}

# --- Modules ---
Ensure-Module -Name Microsoft.Graph
if ($IncludeSharePoint) { Ensure-Module -Name PnP.PowerShell }

# --- Connect Graph ---
$scopes = @(
  "Group.Read.All",
  "Directory.Read.All",
  "Policy.Read.All",
  "Application.Read.All",
  "AppRoleAssignment.Read.All",
  "DeviceManagementConfiguration.Read.All",
  "DeviceManagementApps.Read.All",
  "DeviceManagementManagedDevices.Read.All"
)

Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Cyan
Connect-MgGraph -Scopes $scopes -NoWelcome | Out-Null

# --- Resolve group ---
Write-Host "Resolving group '$Group'..." -ForegroundColor Cyan
$groupObj = $null

if ($Group -match "^[0-9a-fA-F-]{36}$") {
  $groupObj = Get-MgGroup -GroupId $Group -ErrorAction Stop
} else {
  # try exact match on displayName
  $escaped = $Group.Replace("'","''")
  $groupObj = Get-MgGroup -Filter "displayName eq '$escaped'" -ConsistencyLevel eventual -CountVariable c -All |
              Select-Object -First 1
}

if (-not $groupObj) { throw "Group not found: $Group" }

$groupId = $groupObj.Id
$groupName = $groupObj.DisplayName

Write-Host "Group: $groupName ($groupId)" -ForegroundColor Green

$results = New-Object System.Collections.Generic.List[object]

# =========================
# 1) Conditional Access
# =========================
Write-Host "Scanning Conditional Access policies..." -ForegroundColor Cyan
$caPolicies = Invoke-GraphPaged -Uri "https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies?$select=id,displayName,state,conditions" -ApiVersion "v1.0"

foreach ($p in $caPolicies) {
  $include = @()
  $exclude = @()

  try {
    $include = @($p.conditions.users.includeGroups)
    $exclude = @($p.conditions.users.excludeGroups)
  } catch {}

  if ($include -contains $groupId) {
    [void]$results.Add((Add-Result -Workload "Entra" -ObjectType "ConditionalAccessPolicy" -Name $p.displayName -Id $p.id -ScopeOrUrl "Tenant" -Assignment "Include" -Notes "Group included in policy; State=$($p.state)"))
  }
  if ($exclude -contains $groupId) {
    [void]$results.Add((Add-Result -Workload "Entra" -ObjectType "ConditionalAccessPolicy" -Name $p.displayName -Id $p.id -ScopeOrUrl "Tenant" -Assignment "Exclude" -Notes "Group excluded in policy; State=$($p.state)"))
  }
}

# =========================
# 2) Enterprise Apps (Group -> AppRoleAssignments)
# =========================
Write-Host "Scanning Enterprise App / Service Principal assignments..." -ForegroundColor Cyan
$appRoleAssignments = Invoke-GraphPaged -Uri "https://graph.microsoft.com/v1.0/groups/$groupId/appRoleAssignments" -ApiVersion "v1.0"

# Cache SP display names
$spCache = @{}

foreach ($a in $appRoleAssignments) {
  $spId = $a.resourceId
  if (-not $spCache.ContainsKey($spId)) {
    try {
      $sp = Get-MgServicePrincipal -ServicePrincipalId $spId
      $spCache[$spId] = $sp.DisplayName
    } catch {
      $spCache[$spId] = "<unknown servicePrincipal $spId>"
    }
  }

  $roleNote = if ($a.appRoleId -and $a.appRoleId -ne "00000000-0000-0000-0000-000000000000") {
    "AppRoleId=$($a.appRoleId)"
  } else {
    "App assignment (no explicit app role)"
  }

  [void]$results.Add((Add-Result -Workload "Entra" -ObjectType "EnterpriseAppAssignment" -Name $spCache[$spId] -Id $spId -ScopeOrUrl "ServicePrincipal" -Assignment "Assigned" -Notes $roleNote))
}

# =========================
# 3) Entra Directory Role assignments (group assigned roles)
# =========================
Write-Host "Scanning Entra directory role assignments..." -ForegroundColor Cyan
$roleAssignments = Invoke-GraphPaged -Uri "https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignments?`$filter=principalId eq '$groupId'" -ApiVersion "v1.0"

# Cache roleDefinitionId -> displayName
$roleDefCache = @{}

foreach ($ra in $roleAssignments) {
  $roleDefId = $ra.roleDefinitionId
  if (-not $roleDefCache.ContainsKey($roleDefId)) {
    try {
      $rd = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/roleManagement/directory/roleDefinitions/$roleDefId"
      $roleDefCache[$roleDefId] = $rd.displayName
    } catch {
      $roleDefCache[$roleDefId] = "<unknown roleDefinition $roleDefId>"
    }
  }

  [void]$results.Add((Add-Result -Workload "Entra" -ObjectType "DirectoryRoleAssignment" -Name $roleDefCache[$roleDefId] -Id $ra.id -ScopeOrUrl ($ra.directoryScopeId ?? "Tenant") -Assignment "Assigned" -Notes "RoleDefinitionId=$roleDefId"))
}

# =========================
# 4) Intune assignments
# =========================
Write-Host "Scanning Intune assignments (common policy/app types)..." -ForegroundColor Cyan

function Get-IntuneAssignmentsForObject {
  param(
    [Parameter(Mandatory)][string]$ListUri,
    [Parameter(Mandatory)][string]$AssignmentsUriTemplate, # e.g. https://graph.../deviceConfigurations/{id}/assignments
    [Parameter(Mandatory)][string]$ObjectType,
    [ValidateSet("v1.0","beta")][string]$ApiVersion = "v1.0"
  )

  $objs = Invoke-GraphPaged -Uri $ListUri -ApiVersion $ApiVersion

  foreach ($o in $objs) {
    $id = $o.id
    $name = $o.displayName ?? $o.name ?? $id
    $assignUri = $AssignmentsUriTemplate.Replace("{id}", $id)

    $assignments = @()
    try {
      $assignments = Invoke-GraphPaged -Uri $assignUri -ApiVersion $ApiVersion
    } catch {
      continue
    }

    foreach ($as in $assignments) {
      $t = $as.target
      if (-not $t) { continue }

      $targetType = $t.'@odata.type'
      $targetGroupId = $t.groupId

      if ($targetGroupId -eq $groupId) {
        $assignmentKind = if ($targetType -match "exclusion") { "Exclude" } else { "Include" }
        $filterId = $t.deviceAndAppManagementAssignmentFilterId
        $filterType = $t.deviceAndAppManagementAssignmentFilterType

        $notes = @()
        $notes += "TargetType=$targetType"
        if ($filterId) { $notes += "FilterId=$filterId ($filterType)" }
        if ($as.source) { $notes += "Source=$($as.source) SourceId=$($as.sourceId)" }

        [void]$results.Add((Add-Result -Workload "Intune" -ObjectType $ObjectType -Name $name -Id $id -ScopeOrUrl $ListUri -Assignment $assignmentKind -Notes ($notes -join "; ")))
      }
    }
  }
}

# v1.0 Intune objects
Get-IntuneAssignmentsForObject `
  -ListUri "https://graph.microsoft.com/v1.0/deviceManagement/deviceConfigurations" `
  -AssignmentsUriTemplate "https://graph.microsoft.com/v1.0/deviceManagement/deviceConfigurations/{id}/assignments" `
  -ObjectType "DeviceConfigurationProfile" `
  -ApiVersion "v1.0"

Get-IntuneAssignmentsForObject `
  -ListUri "https://graph.microsoft.com/v1.0/deviceManagement/deviceCompliancePolicies" `
  -AssignmentsUriTemplate "https://graph.microsoft.com/v1.0/deviceManagement/deviceCompliancePolicies/{id}/assignments" `
  -ObjectType "DeviceCompliancePolicy" `
  -ApiVersion "v1.0"

Get-IntuneAssignmentsForObject `
  -ListUri "https://graph.microsoft.com/v1.0/deviceManagement/deviceManagementScripts" `
  -AssignmentsUriTemplate "https://graph.microsoft.com/v1.0/deviceManagement/deviceManagementScripts/{id}/assignments" `
  -ObjectType "DeviceManagementScript" `
  -ApiVersion "v1.0"

Get-IntuneAssignmentsForObject `
  -ListUri "https://graph.microsoft.com/v1.0/deviceManagement/deviceHealthScripts" `
  -AssignmentsUriTemplate "https://graph.microsoft.com/v1.0/deviceManagement/deviceHealthScripts/{id}/assignments" `
  -ObjectType "DeviceHealthScript" `
  -ApiVersion "v1.0"

Get-IntuneAssignmentsForObject `
  -ListUri "https://graph.microsoft.com/v1.0/deviceManagement/intents" `
  -AssignmentsUriTemplate "https://graph.microsoft.com/v1.0/deviceManagement/intents/{id}/assignments" `
  -ObjectType "EndpointSecurityIntent" `
  -ApiVersion "v1.0"

Get-IntuneAssignmentsForObject `
  -ListUri "https://graph.microsoft.com/v1.0/deviceAppManagement/mobileApps" `
  -AssignmentsUriTemplate "https://graph.microsoft.com/v1.0/deviceAppManagement/mobileApps/{id}/assignments" `
  -ObjectType "MobileApp" `
  -ApiVersion "v1.0"

# Settings catalog / configurationPolicies (often beta in many tenants)
if ($UseBetaForIntune) {
  Get-IntuneAssignmentsForObject `
    -ListUri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies" `
    -AssignmentsUriTemplate "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies/{id}/assignments" `
    -ObjectType "SettingsCatalogConfigurationPolicy" `
    -ApiVersion "beta"
}

# =========================
# 5) SharePoint site permissions (optional)
# =========================
if ($IncludeSharePoint) {
  if (-not $SiteUrls -and -not $SPOAdminUrl) {
    throw "For -IncludeSharePoint, provide -SPOAdminUrl (e.g. https://contoso-admin.sharepoint.com) or -SiteUrls."
  }

  Write-Host "Scanning SharePoint site permissions..." -ForegroundColor Cyan

  $sitesToScan = @()

  if ($SiteUrls) {
    $sitesToScan = $SiteUrls
  } else {
    # Connect to admin center and enumerate sites (tenant admin permissions required)
    Connect-PnPOnline -Url $SPOAdminUrl -Interactive
    $tenantSites = Get-PnPTenantSite | Select-Object -First $MaxSites
    $sitesToScan = $tenantSites.Url
  }

  foreach ($siteUrl in $sitesToScan) {
    Write-Host "  -> $siteUrl" -ForegroundColor DarkCyan
    try {
      Connect-PnPOnline -Url $siteUrl -Interactive

      $web = Get-PnPWeb -Includes RoleAssignments
      foreach ($ra in $web.RoleAssignments) {
        $member = Get-PnPProperty -ClientObject $ra -Property Member
        $loginName = Get-PnPProperty -ClientObject $member -Property LoginName
        $roleBindings = Get-PnPProperty -ClientObject $ra -Property RoleDefinitionBindings
        $roles = ($roleBindings | ForEach-Object { $_.Name }) -join "; "

        # AAD groups usually show up with login name containing the object id (varies by claim format)
        $hit =
          ($member.Title -eq $groupName) -or
          ($loginName -match [regex]::Escape($groupId))

        if ($hit) {
          [void]$results.Add((Add-Result -Workload "SharePoint" -ObjectType "SiteRoleAssignment" -Name $member.Title -Id $loginName -ScopeOrUrl $siteUrl -Assignment "Granted" -Notes "Roles=$roles"))
        }
      }
    } catch {
      [void]$results.Add((Add-Result -Workload "SharePoint" -ObjectType "ScanError" -Name $siteUrl -Id "" -ScopeOrUrl $siteUrl -Assignment "" -Notes $_.Exception.Message))
    }
  }
}

# --- Output ---
Write-Host "Found $($results.Count) references." -ForegroundColor Green

$results |
  Sort-Object Workload,ObjectType,Name |
  Export-Csv -Path $OutputCsv -NoTypeInformation -Encoding UTF8

Write-Host "Exported: $OutputCsv" -ForegroundColor Green

# Also return objects to pipeline
$results