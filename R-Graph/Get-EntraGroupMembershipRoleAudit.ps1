<#
.SYNOPSIS
    Audits Microsoft Entra users and principals that can change security-group membership.

.DESCRIPTION
    Detects qualifying Microsoft Entra roles through both:

    1. Explicit role permissions that update group membership.
    2. A reviewed list of broad built-in roles whose authority might not be represented
       by the narrow permission strings used for custom-role detection.

    Reports active assignment instances, eligible PIM assignment instances, direct
    users, role-assigned groups and their current transitive users, non-user principals,
    directory scope, detection reason, and assignment timing.

    Authentication uses:
        AZURE_CLIENT_ID
        AZURE_TENANT_DOMAIN
        AZURE_CLIENT_CERTIFICATE_THUMBPRINT
        AZURE_CLIENT_CERTIFICATE_PATH
        AZURE_TENANT_ID

.REQUIREMENTS
    PowerShell 7+
    Microsoft.Graph.Authentication
    ImportExcel only when -ExportExcel is used

    Microsoft Graph application permissions:
        RoleManagement.Read.Directory
        Directory.Read.All
#>

[CmdletBinding()]
param(
    [string]$OutputDirectory = (Join-Path $PWD 'Entra-GroupMembershipRoleAudit'),
    [switch]$IncludeDisabledUsers,
    [switch]$ExportExcel,
    [switch]$DisconnectWhenComplete
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-GraphPropertyValue {
    param(
        [Parameter(Mandatory)][AllowNull()][object]$InputObject,
        [Parameter(Mandatory)][string]$PropertyName,
        [AllowNull()][object]$DefaultValue = $null
    )

    if ($null -eq $InputObject) { return $DefaultValue }
    $property = $InputObject.PSObject.Properties[$PropertyName]
    if ($null -eq $property) { return $DefaultValue }
    return $property.Value
}

function Assert-EnvironmentVariables {
    $required = @('AZURE_CLIENT_ID', 'AZURE_TENANT_ID')
    $missing = foreach ($name in $required) {
        if ([string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($name))) { $name }
    }

    if (
        [string]::IsNullOrWhiteSpace($env:AZURE_CLIENT_CERTIFICATE_THUMBPRINT) -and
        [string]::IsNullOrWhiteSpace($env:AZURE_CLIENT_CERTIFICATE_PATH)
    ) {
        $missing += 'AZURE_CLIENT_CERTIFICATE_THUMBPRINT or AZURE_CLIENT_CERTIFICATE_PATH'
    }

    if ($missing) { throw "Missing environment variable values: $($missing -join ', ')" }
}

function Connect-EntraAuditGraph {
    if (-not (Get-Module -ListAvailable Microsoft.Graph.Authentication)) {
        throw 'Install Microsoft.Graph.Authentication with: Install-Module Microsoft.Graph.Authentication -Scope CurrentUser'
    }

    Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
    Assert-EnvironmentVariables

    $parameters = @{
        TenantId  = $env:AZURE_TENANT_ID
        ClientId  = $env:AZURE_CLIENT_ID
        NoWelcome = $true
    }

    $thumbprint = $env:AZURE_CLIENT_CERTIFICATE_THUMBPRINT
    $certificatePath = $env:AZURE_CLIENT_CERTIFICATE_PATH
    $storeCertificateFound = $false

    if (-not [string]::IsNullOrWhiteSpace($thumbprint)) {
        $thumbprint = $thumbprint.Replace(' ', '').ToUpperInvariant()
        foreach ($location in @("Cert:\CurrentUser\My\$thumbprint", "Cert:\LocalMachine\My\$thumbprint")) {
            if (Test-Path -LiteralPath $location) {
                $storeCertificateFound = $true
                break
            }
        }
    }

    if ($storeCertificateFound) {
        $parameters.CertificateThumbprint = $thumbprint
    }
    else {
        if ([string]::IsNullOrWhiteSpace($certificatePath) -or -not (Test-Path -LiteralPath $certificatePath -PathType Leaf)) {
            throw 'Certificate was not found in the certificate stores and AZURE_CLIENT_CERTIFICATE_PATH is invalid.'
        }

        $certificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($certificatePath)
        if (-not $certificate.HasPrivateKey) { throw "Certificate '$certificatePath' has no private key." }
        $parameters.Certificate = $certificate
    }

    Connect-MgGraph @parameters
    $context = Get-MgContext
    if ($null -eq $context) { throw 'Microsoft Graph connection was not established.' }

    $connectedTenantId = Get-GraphPropertyValue $context 'TenantId'
    Write-Host "Connected to tenant ID $connectedTenantId." -ForegroundColor Green
    if (-not [string]::IsNullOrWhiteSpace($env:AZURE_TENANT_DOMAIN)) {
        Write-Host "Tenant domain: $($env:AZURE_TENANT_DOMAIN)" -ForegroundColor DarkGray
    }
}

function Invoke-GraphCollectionRequest {
    param([Parameter(Mandatory)][string]$Uri)

    $results = [System.Collections.Generic.List[object]]::new()
    $nextLink = $Uri

    while (-not [string]::IsNullOrWhiteSpace($nextLink)) {
        $response = Invoke-MgGraphRequest -Method GET -Uri $nextLink -OutputType PSObject
        $values = Get-GraphPropertyValue $response 'value' @()
        foreach ($value in @($values)) { $results.Add($value) }
        $nextLink = [string](Get-GraphPropertyValue $response '@odata.nextLink')
    }

    return $results.ToArray()
}

function Get-ODataTypeName {
    param([AllowNull()][object]$GraphObject)
    $typeName = [string](Get-GraphPropertyValue $GraphObject '@odata.type')
    if ([string]::IsNullOrWhiteSpace($typeName)) { return 'Unresolved' }
    return $typeName.TrimStart('#').Split('.')[-1]
}

function Test-AllowedActionMatchesTarget {
    param([string]$AllowedAction, [string]$TargetAction)
    if ([string]::IsNullOrWhiteSpace($AllowedAction)) { return $false }
    if ($AllowedAction -eq '*') { return $true }
    $pattern = '^' + [Regex]::Escape($AllowedAction).Replace('\*', '.*') + '$'
    return [Regex]::IsMatch($TargetAction, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
}

function Get-RoleDetection {
    param([Parameter(Mandatory)][object]$RoleDefinition)

    # Template IDs are immutable identifiers for built-in roles.
    # Scope notes distinguish general security-group authority from role-assignable-group authority.
    $knownBuiltInRoles = @{
        '62e90394-69f5-4237-9190-012177145e10' = @{
            Name = 'Global Administrator'
            Scope = 'Broad tenant administration, including group management'
        }
        'fe930be7-5e62-47db-91af-98c3a49a38b1' = @{
            Name = 'User Administrator'
            Scope = 'User and group administration; role-assignable groups remain specially protected'
        }
        'fdd7a751-b60b-444a-984c-02652fe8fa1c' = @{
            Name = 'Groups Administrator'
            Scope = 'Group administration; role-assignable groups remain specially protected'
        }
        '9360feb5-f418-4baa-8175-e2a00bac4301' = @{
            Name = 'Directory Writers'
            Scope = 'Broad directory write authority including group membership operations'
        }
        'e8611ab8-c189-46e8-94e1-60213ab1f814' = @{
            Name = 'Privileged Role Administrator'
            Scope = 'Includes management of role assignments and role-assignable group membership'
        }
        'e00e864a-17c5-4a4b-9c06-f5b95a8d5bd8' = @{
            Name = 'Partner Tier2 Support'
            Scope = 'Legacy broad role containing group membership update authority'
        }
    }

    $targetActions = @(
        'microsoft.directory/groups/members/update'
        'microsoft.directory/groups.security/members/update'
        'microsoft.directory/groups.security.assignedMembership/members/update'
        'microsoft.directory/groups.unified/members/update'
        'microsoft.directory/groups.unified.assignedMembership/members/update'
    )

    $matchedPermissions = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $permissionSets = Get-GraphPropertyValue $RoleDefinition 'rolePermissions' @()

    foreach ($permissionSet in @($permissionSets)) {
        $allowedActions = Get-GraphPropertyValue $permissionSet 'allowedResourceActions' @()
        foreach ($allowedAction in @($allowedActions)) {
            foreach ($targetAction in $targetActions) {
                if (Test-AllowedActionMatchesTarget ([string]$allowedAction) $targetAction) {
                    [void]$matchedPermissions.Add([string]$allowedAction)
                }
            }
        }
    }

    $templateId = [string](Get-GraphPropertyValue $RoleDefinition 'templateId')
    $knownRole = $null
    if (-not [string]::IsNullOrWhiteSpace($templateId) -and $knownBuiltInRoles.ContainsKey($templateId)) {
        $knownRole = $knownBuiltInRoles[$templateId]
    }

    $reasons = [System.Collections.Generic.List[string]]::new()
    if ($null -ne $knownRole) { $reasons.Add('Known broad built-in role') }
    if ($matchedPermissions.Count -gt 0) { $reasons.Add('Explicit group-membership permission') }

    return [PSCustomObject]@{
        IsInScope          = ($reasons.Count -gt 0)
        DetectionReason    = $reasons -join '; '
        CapabilityScope    = if ($null -ne $knownRole) { $knownRole.Scope } else { 'Explicit role permission matched' }
        MatchedPermissions = @($matchedPermissions | Sort-Object)
    }
}

function Get-DirectoryObject {
    param([Parameter(Mandatory)][string]$ObjectId)

    if ($script:ObjectCache.ContainsKey($ObjectId)) { return $script:ObjectCache[$ObjectId] }
    try {
        $id = [Uri]::EscapeDataString($ObjectId)
        $object = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/directoryObjects/$id" -OutputType PSObject
    }
    catch {
        Write-Warning "Could not resolve directory object '$ObjectId': $($_.Exception.Message)"
        $object = [PSCustomObject]@{ id = $ObjectId; displayName = 'Unresolved object' }
    }

    $script:ObjectCache[$ObjectId] = $object
    return $object
}

function Get-PrincipalDetails {
    param([Parameter(Mandatory)][string]$PrincipalId)
    $object = Get-DirectoryObject $PrincipalId
    return [PSCustomObject]@{
        Id                = $PrincipalId
        Type              = Get-ODataTypeName $object
        DisplayName       = Get-GraphPropertyValue $object 'displayName' 'Unresolved object'
        UserPrincipalName = Get-GraphPropertyValue $object 'userPrincipalName'
        Mail              = Get-GraphPropertyValue $object 'mail'
        AccountEnabled    = Get-GraphPropertyValue $object 'accountEnabled'
        RawObject         = $object
    }
}

function Get-GroupTransitiveUsers {
    param([Parameter(Mandatory)][string]$GroupId)
    if ($script:GroupUserCache.ContainsKey($GroupId)) { return $script:GroupUserCache[$GroupId] }

    try {
        $id = [Uri]::EscapeDataString($GroupId)
        $uri = "https://graph.microsoft.com/v1.0/groups/$id/transitiveMembers/microsoft.graph.user?`$select=id,displayName,userPrincipalName,mail,accountEnabled&`$top=999"
        $users = @(Invoke-GraphCollectionRequest $uri)
    }
    catch {
        Write-Warning "Could not expand role-assigned group '$GroupId': $($_.Exception.Message)"
        $users = @()
    }

    $script:GroupUserCache[$GroupId] = $users
    return $users
}

function Get-ScopeDetails {
    param([AllowNull()][string]$DirectoryScopeId)
    if ([string]::IsNullOrWhiteSpace($DirectoryScopeId)) { $DirectoryScopeId = '/' }
    if ($script:ScopeCache.ContainsKey($DirectoryScopeId)) { return $script:ScopeCache[$DirectoryScopeId] }

    if ($DirectoryScopeId -eq '/') {
        $scope = [PSCustomObject]@{ ScopeId = '/'; ScopeType = 'Tenant'; ScopeDisplayName = 'Entire tenant'; ScopeObjectId = $null }
        $script:ScopeCache[$DirectoryScopeId] = $scope
        return $scope
    }

    $scopeObjectId = $null
    $scopeType = 'Directory object'
    $scopeName = $DirectoryScopeId
    $administrativeUnitMatch = [Regex]::Match($DirectoryScopeId, '^/administrativeUnits/(?<ObjectId>[0-9a-fA-F-]{36})$')
    $directoryObjectMatch = [Regex]::Match($DirectoryScopeId, '^/[^/]+/(?<ObjectId>[0-9a-fA-F-]{36})$')

    if ($administrativeUnitMatch.Success) {
        $scopeObjectId = $administrativeUnitMatch.Groups['ObjectId'].Value
        $scopeType = 'Administrative unit'
    }
    elseif ($directoryObjectMatch.Success) {
        $scopeObjectId = $directoryObjectMatch.Groups['ObjectId'].Value
    }

    if ($scopeObjectId) {
        $scopeObject = Get-DirectoryObject $scopeObjectId
        $scopeName = Get-GraphPropertyValue $scopeObject 'displayName' $DirectoryScopeId
        $resolvedType = Get-ODataTypeName $scopeObject
        if ($resolvedType -ne 'Unresolved') { $scopeType = $resolvedType }
    }

    $scope = [PSCustomObject]@{ ScopeId = $DirectoryScopeId; ScopeType = $scopeType; ScopeDisplayName = $scopeName; ScopeObjectId = $scopeObjectId }
    $script:ScopeCache[$DirectoryScopeId] = $scope
    return $scope
}

function Get-TimingStatus {
    param([AllowNull()][string]$StartDateTime, [AllowNull()][string]$EndDateTime)
    $now = [DateTimeOffset]::UtcNow
    $start = if ($StartDateTime) { [DateTimeOffset]::Parse($StartDateTime) } else { $null }
    $end = if ($EndDateTime) { [DateTimeOffset]::Parse($EndDateTime) } else { $null }
    if ($start -and $start -gt $now) { return 'Future' }
    if ($end -and $end -lt $now) { return 'Expired' }
    if (-not $end) { return 'Permanent or open-ended' }
    return 'Current'
}

$script:ObjectCache = @{}
$script:GroupUserCache = @{}
$script:ScopeCache = @{}
New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$rolesCsv = Join-Path $OutputDirectory "Entra-InScope-Roles-$timestamp.csv"
$assignmentsCsv = Join-Path $OutputDirectory "Entra-InScope-Assignments-$timestamp.csv"
$usersCsv = Join-Path $OutputDirectory "Entra-InScope-EffectiveUsers-$timestamp.csv"
$summaryPath = Join-Path $OutputDirectory "Entra-GroupMembership-Audit-Summary-$timestamp.txt"
$xlsxPath = Join-Path $OutputDirectory "Entra-GroupMembership-Audit-$timestamp.xlsx"

Connect-EntraAuditGraph

try {
    Write-Host 'Retrieving role definitions...' -ForegroundColor Cyan
    $roleDefinitions = @(Invoke-GraphCollectionRequest 'https://graph.microsoft.com/v1.0/roleManagement/directory/roleDefinitions')

    $roleLookup = @{}
    $detectionLookup = @{}
    $roleRows = [System.Collections.Generic.List[object]]::new()

    foreach ($role in $roleDefinitions) {
        $roleId = [string](Get-GraphPropertyValue $role 'id')
        if ([string]::IsNullOrWhiteSpace($roleId)) { continue }
        $detection = Get-RoleDetection $role
        if (-not $detection.IsInScope) { continue }

        $roleLookup[$roleId] = $role
        $detectionLookup[$roleId] = $detection
        $roleRows.Add([PSCustomObject]@{
            RoleDisplayName     = Get-GraphPropertyValue $role 'displayName'
            RoleDefinitionId    = $roleId
            RoleTemplateId      = Get-GraphPropertyValue $role 'templateId'
            IsBuiltIn           = Get-GraphPropertyValue $role 'isBuiltIn'
            IsEnabled           = Get-GraphPropertyValue $role 'isEnabled'
            DetectionReason     = $detection.DetectionReason
            CapabilityScope     = $detection.CapabilityScope
            MatchedPermissions  = $detection.MatchedPermissions -join '; '
            Description         = Get-GraphPropertyValue $role 'description'
        })
    }

    Write-Host "Found $($roleRows.Count) in-scope role definitions." -ForegroundColor Green
    Write-Host 'Retrieving active assignments...' -ForegroundColor Cyan
    $activeUri = 'https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignmentScheduleInstances?$top=999'
    $activeAssignments = @(Invoke-GraphCollectionRequest $activeUri)
    Write-Host 'Retrieving eligible assignments...' -ForegroundColor Cyan
    $eligibleUri = 'https://graph.microsoft.com/v1.0/roleManagement/directory/roleEligibilityScheduleInstances?$top=999'
    $eligibleAssignments = @(Invoke-GraphCollectionRequest $eligibleUri)

    $assignmentRows = [System.Collections.Generic.List[object]]::new()
    $userRows = [System.Collections.Generic.List[object]]::new()
    $sets = @(
        [PSCustomObject]@{ State = 'Active'; Items = $activeAssignments }
        [PSCustomObject]@{ State = 'Eligible'; Items = $eligibleAssignments }
    )

    foreach ($set in $sets) {
        foreach ($assignment in @($set.Items)) {
            $roleId = [string](Get-GraphPropertyValue $assignment 'roleDefinitionId')
            if (-not $roleLookup.ContainsKey($roleId)) { continue }

            $role = $roleLookup[$roleId]
            $detection = $detectionLookup[$roleId]
            $principalId = [string](Get-GraphPropertyValue $assignment 'principalId')
            if ([string]::IsNullOrWhiteSpace($principalId)) { continue }
            $principal = Get-PrincipalDetails $principalId

            $scopeId = [string](Get-GraphPropertyValue $assignment 'directoryScopeId')
            if ([string]::IsNullOrWhiteSpace($scopeId)) { $scopeId = [string](Get-GraphPropertyValue $assignment 'appScopeId') }
            $scope = Get-ScopeDetails $scopeId
            $startDateTime = [string](Get-GraphPropertyValue $assignment 'startDateTime')
            $endDateTime = [string](Get-GraphPropertyValue $assignment 'endDateTime')
            $assignmentId = Get-GraphPropertyValue $assignment 'id'
            $roleName = Get-GraphPropertyValue $role 'displayName'

            $base = [ordered]@{
                AssignmentState       = $set.State
                RoleDisplayName       = $roleName
                RoleDefinitionId      = $roleId
                RoleTemplateId        = Get-GraphPropertyValue $role 'templateId'
                RoleIsBuiltIn         = Get-GraphPropertyValue $role 'isBuiltIn'
                DetectionReason       = $detection.DetectionReason
                CapabilityScope       = $detection.CapabilityScope
                MatchedPermissions    = $detection.MatchedPermissions -join '; '
                DirectoryScopeId      = $scope.ScopeId
                ScopeType             = $scope.ScopeType
                ScopeDisplayName      = $scope.ScopeDisplayName
                ScopeObjectId         = $scope.ScopeObjectId
                AssignmentInstanceId  = $assignmentId
                AssignmentScheduleId  = Get-GraphPropertyValue $assignment 'roleAssignmentScheduleId'
                EligibilityScheduleId = Get-GraphPropertyValue $assignment 'roleEligibilityScheduleId'
                AssignmentType        = Get-GraphPropertyValue $assignment 'assignmentType'
                MemberType            = Get-GraphPropertyValue $assignment 'memberType'
                StartDateTimeUtc      = $startDateTime
                EndDateTimeUtc        = $endDateTime
                TimingStatus          = Get-TimingStatus $startDateTime $endDateTime
            }

            $assignmentRows.Add([PSCustomObject]($base + [ordered]@{
                PrincipalDisplayName = $principal.DisplayName
                PrincipalType        = $principal.Type
                PrincipalId          = $principal.Id
                PrincipalUPN         = $principal.UserPrincipalName
                PrincipalMail        = $principal.Mail
                PrincipalEnabled     = $principal.AccountEnabled
            }))

            if ($principal.Type -eq 'user') {
                if (-not $IncludeDisabledUsers -and $principal.AccountEnabled -eq $false) { continue }
                $userRows.Add([PSCustomObject]([ordered]@{
                    UserDisplayName      = $principal.DisplayName
                    UserPrincipalName    = $principal.UserPrincipalName
                    UserMail             = $principal.Mail
                    UserId               = $principal.Id
                    UserAccountEnabled   = $principal.AccountEnabled
                    AssignmentPath       = 'Direct user assignment'
                    AssignedGroupId      = $null
                    AssignedGroupName    = $null
                } + $base))
            }
            elseif ($principal.Type -eq 'group') {
                foreach ($user in @(Get-GroupTransitiveUsers $principal.Id)) {
                    $enabled = Get-GraphPropertyValue $user 'accountEnabled'
                    if (-not $IncludeDisabledUsers -and $enabled -eq $false) { continue }
                    $userRows.Add([PSCustomObject]([ordered]@{
                        UserDisplayName      = Get-GraphPropertyValue $user 'displayName'
                        UserPrincipalName    = Get-GraphPropertyValue $user 'userPrincipalName'
                        UserMail             = Get-GraphPropertyValue $user 'mail'
                        UserId               = Get-GraphPropertyValue $user 'id'
                        UserAccountEnabled   = $enabled
                        AssignmentPath       = 'Inherited through role-assigned group'
                        AssignedGroupId      = $principal.Id
                        AssignedGroupName    = $principal.DisplayName
                    } + $base))
                }
            }
        }
    }

    $deduplicatedUsers = @($userRows | Sort-Object UserId, AssignmentState, RoleDefinitionId, DirectoryScopeId, AssignedGroupId, AssignmentInstanceId -Unique)
    $sortedRoles = @($roleRows | Sort-Object RoleDisplayName)
    $sortedAssignments = @($assignmentRows | Sort-Object AssignmentState, RoleDisplayName, PrincipalDisplayName)

    $sortedRoles | Export-Csv $rolesCsv -NoTypeInformation -Encoding utf8BOM
    $sortedAssignments | Export-Csv $assignmentsCsv -NoTypeInformation -Encoding utf8BOM
    $deduplicatedUsers | Export-Csv $usersCsv -NoTypeInformation -Encoding utf8BOM

    if ($ExportExcel) {
        if (-not (Get-Module -ListAvailable ImportExcel)) {
            throw 'The -ExportExcel option requires: Install-Module ImportExcel -Scope CurrentUser'
        }
        Import-Module ImportExcel -ErrorAction Stop
        $excel = @{ Path = $xlsxPath; AutoSize = $true; AutoFilter = $true; FreezeTopRow = $true; BoldTopRow = $true; TableStyle = 'Medium2' }
        $sortedRoles | Export-Excel @excel -WorksheetName 'Roles' -TableName 'InScopeRoles'
        $sortedAssignments | Export-Excel @excel -WorksheetName 'Assignments' -TableName 'Assignments' -Append
        $deduplicatedUsers | Export-Excel @excel -WorksheetName 'EffectiveUsers' -TableName 'EffectiveUsers' -Append
    }

    $uniqueActiveUsers = @($deduplicatedUsers | Where-Object AssignmentState -eq 'Active' | Select-Object -ExpandProperty UserId -Unique).Count
    $uniqueEligibleUsers = @($deduplicatedUsers | Where-Object AssignmentState -eq 'Eligible' | Select-Object -ExpandProperty UserId -Unique).Count
    $summary = @"
Microsoft Entra Security-Group Membership Privilege Audit
Generated UTC: $([DateTimeOffset]::UtcNow.ToString('u'))
Tenant domain: $($env:AZURE_TENANT_DOMAIN)
Tenant ID: $($env:AZURE_TENANT_ID)

Role definitions reviewed: $($roleDefinitions.Count)
In-scope roles: $($sortedRoles.Count)
In-scope active assignments: $(@($sortedAssignments | Where-Object AssignmentState -eq 'Active').Count)
In-scope eligible assignments: $(@($sortedAssignments | Where-Object AssignmentState -eq 'Eligible').Count)
Unique active users: $uniqueActiveUsers
Unique eligible users: $uniqueEligibleUsers
Disabled users included: $($IncludeDisabledUsers.IsPresent)

Detection combines known broad built-in role template IDs with explicit role permissions.
Privileged Role Administrator is included because of role-assignable group authority.
Assignment scope must be considered when interpreting effective access.
PIM-for-Groups eligible members are not included unless currently active group members.

Reports:
$rolesCsv
$assignmentsCsv
$usersCsv
$(if ($ExportExcel) { $xlsxPath })
"@
    $summary | Set-Content $summaryPath -Encoding utf8

    Write-Host 'Audit completed.' -ForegroundColor Green
    Write-Host "Roles:       $rolesCsv"
    Write-Host "Assignments: $assignmentsCsv"
    Write-Host "Users:       $usersCsv"
    Write-Host "Summary:     $summaryPath"
    if ($ExportExcel) { Write-Host "Workbook:    $xlsxPath" }
}
finally {
    if ($DisconnectWhenComplete) { Disconnect-MgGraph | Out-Null }
}