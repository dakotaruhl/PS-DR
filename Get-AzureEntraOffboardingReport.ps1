#requires -Version 7.2
<#
.SYNOPSIS
Creates a read-only Azure and Microsoft Entra offboarding access report for one user.

.DESCRIPTION
Uses certificate-based application authentication for Microsoft Graph and Azure.
Produces CSV detail files, a JSON evidence file, and an HTML summary.
No access is changed.

The script checks:
- Entra account state, licenses, authentication methods, devices, groups, and directory roles
- Active and eligible Entra PIM role assignments
- Owned applications, service principals, groups, and devices
- Enterprise application assignments
- Azure RBAC assignments, including assignments inherited through transitive groups
- Azure resource PIM eligible assignments when supported by the installed Az.Resources module
- Key Vault legacy access policies
- Azure SQL Microsoft Entra administrator configuration
- Optional Exchange Online shared mailbox delegation

Some platforms require their own API and credentials and are recorded as manual checks:
Azure DevOps, Power Platform ownership, database-contained users, ADLS Gen2 ACLs,
local application accounts, secrets/certificates copied to personal devices, and third-party SaaS. 

$params = @{
    UserPrincipalName    = 'jhull@graniteproject.dev'
    TenantId             = 'a76bf141-b9f9-4f32-ad2a-060b5991730f'
    ClientId             = 'ddbd94ea-ad86-46f0-84af-24998ed86d2d'
    CertificateThumbprint = 'A1D8B302230D51274ED54FB6E1C182B890D560BC'
    ExchangeOrganization = 'enchantedrock.onmicrosoft.com'
    OutputPath           = 'C:\Users\DakotaRuhl\Documents\Reports\Elevated User Offboarding'
}

.\Get-AzureEntraOffboardingReport.ps1 @params


#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$UserPrincipalName,

    [Parameter(Mandatory)]
    [string]$TenantId,

    [Parameter(Mandatory)]
    [string]$ClientId,

    [Parameter(Mandatory)]
    [string]$CertificateThumbprint,

    [string]$ExchangeOrganization,

    [string]$OutputPath = (Join-Path $PWD ("OffboardingReport-{0}-{1}" -f ($UserPrincipalName -replace '[^a-zA-Z0-9._-]','_'), (Get-Date -Format 'yyyyMMdd-HHmmss'))),

    [switch]$SkipAzure,
    [switch]$SkipExchange
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Add-Finding {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Area,
        [Parameter(Mandatory)][ValidateSet('Critical','High','Medium','Low','Info','Manual','Error')][string]$Severity,
        [Parameter(Mandatory)][string]$Finding,
        [string]$Source,
        [string]$ObjectId,
        [string]$Scope,
        [string]$Details
    )
    $script:Findings.Add([pscustomobject]@{
        Area = $Area
        Severity = $Severity
        Finding = $Finding
        Source = $Source
        ObjectId = $ObjectId
        Scope = $Scope
        Details = $Details
    }) | Out-Null
}

function Invoke-CheckedSection {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][scriptblock]$ScriptBlock)
    Write-Host "Checking $Name..." -ForegroundColor Cyan
    try { & $ScriptBlock }
    catch {
        Add-Finding `
            -Area $Name `
            -Severity Error `
            -Finding 'Check failed' `
            -Source 'Script' `
            -ObjectId $_.Exception.TargetObject.Id `
            -Scope $a.Scope `
            -Details $_.Exception.Message
        Write-Warning "$Name check failed: $($_.Exception.Message)"
    }
}

function Get-AllGraphPages {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Uri)
    $items = [System.Collections.Generic.List[object]]::new()
    $next = $Uri
    while ($next) {
        $response = Invoke-MgGraphRequest -Method GET -Uri $next -OutputType PSObject
        if ($null -ne $response.value) {
            foreach ($item in $response.value) { $items.Add($item) | Out-Null }
            $next = $response.'@odata.nextLink'
        }
        else {
            $items.Add($response) | Out-Null
            $next = $null
        }
    }
    return $items
}

function Resolve-DirectoryObjectName {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Id)
    if ($script:ObjectNameCache.ContainsKey($Id)) { return $script:ObjectNameCache[$Id] }
    try {
        $obj = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/directoryObjects/$Id" -OutputType PSObject
        $name = @($obj.displayName, $obj.userPrincipalName, $obj.appId, $Id) | Where-Object { $_ } | Select-Object -First 1
    }
    catch { $name = $Id }
    $script:ObjectNameCache[$Id] = $name
    return $name
}

function Get-SeverityRank {
    param([string]$Severity)
    switch ($Severity) {
        Critical { 1 }
        High     { 2 }
        Medium   { 3 }
        Error    { 4 }
        Manual   { 5 }
        Low      { 6 }
        Info     { 7 }
        default  { 8 }
    }
}

$script:Findings = [System.Collections.Generic.List[object]]::new()
$script:ObjectNameCache = @{}
New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
$TranscriptPath = Join-Path $OutputPath 'ExecutionTranscript.txt'
Start-Transcript -Path $TranscriptPath -Force | Out-Null

try {
    foreach ($module in 'Microsoft.Graph.Authentication','Microsoft.Graph.Users','Az.Accounts','Az.Resources') {
        if (-not (Get-Module -ListAvailable -Name $module)) {
            throw "Required module '$module' is not installed. Install it from PowerShell Gallery before running this script."
        }
    }

    Import-Module Microsoft.Graph.Authentication
    Import-Module Microsoft.Graph.Users
    Connect-MgGraph -TenantId $TenantId -ClientId $ClientId -CertificateThumbprint $CertificateThumbprint -NoWelcome

    $user = Get-MgUser `
        -Filter "userPrincipalName eq '$UserPrincipalName'" `
        -Property Id,DisplayName,UserPrincipalName,Mail,AccountEnabled,UserType,CreatedDateTime,EmployeeId,JobTitle,Department,AssignedLicenses `
        -ConsistencyLevel eventual

    $user = $user | Select-Object -First 1

    if (-not $user) {
        throw "Unable to locate user: $UserPrincipalName"
    }
    $userId = $user.Id

    Add-Finding `
        -Area 'Identity' `
        -Severity ($(if ($user.AccountEnabled) {'Critical'} else {'Info'})) `
        -Finding ($(if ($user.AccountEnabled) {'Account is enabled'} else {'Account is disabled'})) `
        -Source 'Microsoft Graph' `
        -ObjectId $a.ObjectId `
        -Scope $a.Scope
        -Details @"
Role: $($a.RoleDefinitionName)
AssignmentId: $($a.RoleAssignmentId)
PrincipalObjectId: $($a.ObjectId)
PrincipalType: $($a.ObjectType)
DisplayName: $($a.DisplayName)
"@

    if (@($user.AssignedLicenses).Count -gt 0) {
        Add-Finding `
            -Area 'Licensing' `
            -Severity Medium `
            -Finding 'User still has assigned licenses' `
            -Source 'Microsoft Graph' `
            -ObjectId $a.ObjectId `
            -Scope $a.Scope `
            -Details @"
Role: $($a.RoleDefinitionName)
AssignmentId: $($a.RoleAssignmentId)
PrincipalObjectId: $($a.ObjectId)
PrincipalType: $($a.ObjectType)
DisplayName: $($a.DisplayName)
"@
    }
    else { Add-Finding `
            -Area 'Licensing' `
            -Severity Info `
            -Finding 'No assigned licenses found' `
            -Source 'Microsoft Graph' `
            -ObjectId $a.ObjectId `
            -Scope $a.Scope `
            -Details @"
Role: $($a.RoleDefinitionName)
AssignmentId: $($a.RoleAssignmentId)
PrincipalObjectId: $($a.ObjectId)
PrincipalType: $($a.ObjectType)
DisplayName: $($a.DisplayName)
"@ 
    }

    Invoke-CheckedSection -Name 'Authentication methods' -ScriptBlock {
        $methods = Get-AllGraphPages -Uri "https://graph.microsoft.com/v1.0/users/$userId/authentication/methods"
        foreach ($method in $methods) {
            $type = $method.'@odata.type' -replace '#microsoft.graph.',''
            Add-Finding -Area 'Authentication methods' `
                        -Severity High `
                        -Finding 'Authentication method remains registered' `
                        -Source 'Microsoft Graph' `
                        -ObjectId $a.ObjectId `
                        -Scope $a.Scope `
                        -Details @"
Role: $($a.RoleDefinitionName)
AssignmentId: $($a.RoleAssignmentId)
PrincipalObjectId: $($a.ObjectId)
PrincipalType: $($a.ObjectType)
DisplayName: $($a.DisplayName)
"@
        }
        if ($methods.Count -eq 0) { Add-Finding -Area 'Authentication methods' `
                        -Severity Info `
                        -Finding 'No authentication methods found' `
                        -Source 'Microsoft Graph' `
                        -ObjectId $a.ObjectId `
                        -Scope $a.Scope `
                        -Details @"
Role: $($a.RoleDefinitionName)
AssignmentId: $($a.RoleAssignmentId)
PrincipalObjectId: $($a.ObjectId)
PrincipalType: $($a.ObjectType)
DisplayName: $($a.DisplayName)
"@ 
        }
    }

    Invoke-CheckedSection -Name 'Group memberships' -ScriptBlock {
        $groups = Get-AllGraphPages -Uri "https://graph.microsoft.com/v1.0/users/$userId/transitiveMemberOf/microsoft.graph.group?`$select=id,displayName,securityEnabled,mailEnabled,isAssignableToRole,groupTypes"
        $script:TransitiveGroupIds = @($groups.id)
        foreach ($group in $groups) {
            $severity = if ($group.isAssignableToRole) {'High'} else {'Medium'}
            Add-Finding `
                -Area 'Group memberships' `
                -Severity $severity `
                -Finding 'Transitive group membership remains' `
                -Source 'Microsoft Graph' `
                -ObjectId $group.id `
                -Details @"
GroupName: $($group.displayName)
GroupObjectId: $($group.id)
RoleAssignable: $($group.isAssignableToRole)
SecurityEnabled: $($group.securityEnabled)
MailEnabled: $($group.mailEnabled)
"@
        }
        if ($groups.Count -eq 0) { Add-Finding -Area 'Group memberships' `
            -Severity Info `
            -Finding 'No transitive group memberships found' `
            -Source 'Microsoft Graph' `
            -ObjectId $a.ObjectId `
            -Scope $a.Scope `
            -Details @"
Role: $($a.RoleDefinitionName)
AssignmentId: $($a.RoleAssignmentId)
PrincipalObjectId: $($a.ObjectId)
PrincipalType: $($a.ObjectType)
DisplayName: $($a.DisplayName)
"@ }
    }

    Invoke-CheckedSection -Name 'Enterprise application assignments' -ScriptBlock {
        $assignments = Get-AllGraphPages -Uri "https://graph.microsoft.com/v1.0/users/$userId/appRoleAssignments?`$select=id,resourceId,resourceDisplayName,appRoleId,createdDateTime"
        foreach ($a in $assignments) {
            Add-Finding `
            -Area 'Enterprise application assignments' `
            -Severity High `
            -Finding 'Direct enterprise application assignment remains' `
            -Source 'Microsoft Graph' `
            -ObjectId $a.resourceId `
            -Details @"
Application: $($a.resourceDisplayName)
ServicePrincipalId: $($a.resourceId)
AppRoleId: $($a.appRoleId)
AssignmentId: $($a.id)
"@
        }
        if ($assignments.Count -eq 0) { Add-Finding -Area 'Enterprise application assignments' `
            -Severity Info `
            -Finding 'No direct enterprise application assignments found' `
            -Source 'Microsoft Graph' `
            -ObjectId $a.ObjectId `
            -Scope $a.Scope `
            -Details @"
Role: $($a.RoleDefinitionName)
AssignmentId: $($a.RoleAssignmentId)
PrincipalObjectId: $($a.ObjectId)
PrincipalType: $($a.ObjectType)
DisplayName: $($a.DisplayName)
"@ }
        }

    Invoke-CheckedSection -Name 'Directory roles' -ScriptBlock {
        $definitions = Get-AllGraphPages -Uri 'https://graph.microsoft.com/v1.0/roleManagement/directory/roleDefinitions?$select=id,displayName,isBuiltIn'
        $roleMap = @{}; foreach ($d in $definitions) { $roleMap[$d.id] = $d.displayName }
        $principalIds = @($userId) + @($script:TransitiveGroupIds)
        $active = Get-AllGraphPages -Uri "https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignmentScheduleInstances?`$filter=principalId eq '$userId'&`$select=id,principalId,roleDefinitionId,directoryScopeId,assignmentType,startDateTime,endDateTime"
        $eligible = Get-AllGraphPages -Uri "https://graph.microsoft.com/v1.0/roleManagement/directory/roleEligibilityScheduleInstances?`$filter=principalId eq '$userId'&`$select=id,principalId,roleDefinitionId,directoryScopeId,memberType,startDateTime,endDateTime"
        foreach ($r in $active) {
            Add-Finding -Area 'Entra PIM' -Severity Critical -Finding 'Active Entra role assignment remains' -Source 'Microsoft Graph' -ObjectId $r.id -Scope $r.directoryScopeId -Details $roleMap[$r.roleDefinitionId]
        }
        foreach ($r in $eligible) {
            Add-Finding -Area 'Entra PIM' -Severity High -Finding 'Eligible Entra role assignment remains' -Source 'Microsoft Graph' -ObjectId $r.id -Scope $r.directoryScopeId -Details $roleMap[$r.roleDefinitionId]
        }
        foreach ($groupId in @($script:TransitiveGroupIds)) {
            $groupAssignments = Get-AllGraphPages -Uri "https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignments?`$filter=principalId eq '$groupId'&`$select=id,principalId,roleDefinitionId,directoryScopeId"
            foreach ($r in $groupAssignments) {
                Add-Finding -Area 'Directory roles' -Severity Critical -Finding 'Entra role inherited through group' -Source 'Microsoft Graph' -ObjectId $r.id -Scope $r.directoryScopeId -Details ((Resolve-DirectoryObjectName $groupId) + ' -> ' + $roleMap[$r.roleDefinitionId])
            }
        }
        if (($active.Count + $eligible.Count) -eq 0) { Add-Finding -Area 'Entra PIM' -Severity Info -Finding 'No direct active or eligible Entra PIM assignments found' -Source 'Microsoft Graph' -ObjectId $userId }
    }

    Invoke-CheckedSection -Name 'Owned directory objects' -ScriptBlock {
        $owned = Get-AllGraphPages -Uri "https://graph.microsoft.com/v1.0/users/$userId/ownedObjects?`$select=id,displayName"
        foreach ($obj in $owned) {
            $type = $obj.'@odata.type' -replace '#microsoft.graph.',''
            Add-Finding `
                -Area 'Owned directory objects' `
                -Severity High `
                -Finding 'User remains an object owner' `
                -Source 'Microsoft Graph' `
                -ObjectId $obj.id `
                -Details @"
Type: $type
DisplayName: $($obj.displayName)
ObjectId: $($obj.id)
"@

        }
        if ($owned.Count -eq 0) { Add-Finding -Area 'Owned directory objects' -Severity Info -Finding 'No owned directory objects found' -Source 'Microsoft Graph' -ObjectId $userId }
    }

    Invoke-CheckedSection -Name 'Registered and owned devices' -ScriptBlock {
        $devices = Get-AllGraphPages -Uri "https://graph.microsoft.com/v1.0/users/$userId/registeredDevices?`$select=id,displayName,accountEnabled,operatingSystem,approximateLastSignInDateTime"
        foreach ($device in $devices) {
            Add-Finding -Area 'Devices' -Severity Medium -Finding 'Registered device relationship remains' -Source 'Microsoft Graph' -ObjectId $device.id -Details ("{0}; {1}; Enabled={2}" -f $device.displayName,$device.operatingSystem,$device.accountEnabled)
        }
        if ($devices.Count -eq 0) { Add-Finding -Area 'Devices' -Severity Info -Finding 'No registered devices found' -Source 'Microsoft Graph' -ObjectId $userId }
    }

    if (-not $SkipAzure) {
        Import-Module Az.Accounts
        Import-Module Az.Resources
        Connect-AzAccount -ServicePrincipal -Tenant $TenantId -ApplicationId $ClientId -CertificateThumbprint $CertificateThumbprint | Out-Null
        $subscriptions = Get-AzSubscription -TenantId $TenantId | Where-Object State -eq 'Enabled'
        foreach ($subscription in $subscriptions) {
            Invoke-CheckedSection -Name "Azure RBAC - $($subscription.Name)" -ScriptBlock {
                Set-AzContext -SubscriptionId $subscription.Id -TenantId $TenantId | Out-Null
                $assignments = Get-AzRoleAssignment -Scope "/subscriptions/$($subscription.Id)" -IncludeClassicAdministrators -ErrorAction Stop
                $matching = $assignments | Where-Object { $_.ObjectId -eq $userId -or $_.ObjectId -in @($script:TransitiveGroupIds) }
                foreach ($a in $matching) {
                    $via = if ($a.ObjectId -eq $userId) {'Direct'} else {"Via group: $(Resolve-DirectoryObjectName $a.ObjectId)"}
                    Add-Finding -Area 'Azure RBAC' -Severity Critical -Finding 'Azure role assignment grants access' -Source 'Az PowerShell' -ObjectId $a.RoleAssignmentId -Scope $a.Scope -Details ("{0}; {1}; Subscription={2}" -f $a.RoleDefinitionName,$via,$subscription.Name)
                }
            }

            Invoke-CheckedSection -Name "Azure resource PIM - $($subscription.Name)" -ScriptBlock {
                if (Get-Command Get-AzRoleEligibilityScheduleInstance -ErrorAction SilentlyContinue) {
                    $eligible = Get-AzRoleEligibilityScheduleInstance -Scope "/subscriptions/$($subscription.Id)" | Where-Object { $_.PrincipalId -eq $userId -or $_.PrincipalId -in @($script:TransitiveGroupIds) }
                    foreach ($e in $eligible) {
                        $via = if ($e.PrincipalId -eq $userId) {'Direct'} else {"Via group: $(Resolve-DirectoryObjectName $e.PrincipalId)"}
                        Add-Finding -Area 'Azure resource PIM' -Severity High -Finding 'Eligible Azure resource role remains' -Source 'Az PowerShell' -ObjectId $e.Id -Scope $e.Scope -Details ("RoleDefinitionId={0}; {1}; Subscription={2}" -f $e.RoleDefinitionId,$via,$subscription.Name)
                    }
                }
                else { Add-Finding -Area 'Azure resource PIM' -Severity Manual -Finding 'Installed Az.Resources module does not expose Get-AzRoleEligibilityScheduleInstance' -Source 'Az PowerShell' -Scope $subscription.Id -Details 'Review Azure resource PIM manually or update Az.Resources.' }
            }

            Invoke-CheckedSection -Name "Key Vault access policies - $($subscription.Name)" -ScriptBlock {
                if (Get-Command Get-AzKeyVault -ErrorAction SilentlyContinue) {
                    foreach ($vault in Get-AzKeyVault) {
                        foreach ($policy in @($vault.AccessPolicies)) {
                            if ($policy.ObjectId -eq $userId -or $policy.ObjectId -in @($script:TransitiveGroupIds)) {
                                Add-Finding -Area 'Key Vault legacy access policies' -Severity Critical -Finding 'Key Vault access policy grants access' -Source 'Az PowerShell' -ObjectId $policy.ObjectId -Scope $vault.ResourceId -Details ("Vault={0}; Key={1}; Secret={2}; Certificate={3}; Storage={4}" -f $vault.VaultName,($policy.PermissionsToKeys -join ','),($policy.PermissionsToSecrets -join ','),($policy.PermissionsToCertificates -join ','),($policy.PermissionsToStorage -join ','))
                            }
                        }
                    }
                }
                else { Add-Finding -Area 'Key Vault legacy access policies' -Severity Manual -Finding 'Az.KeyVault module not installed' -Source 'Script' -Scope $subscription.Id -Details 'RBAC-based Key Vault access is already represented by Azure RBAC. Install Az.KeyVault to inspect legacy policies.' }
            }

            Invoke-CheckedSection -Name "Azure SQL administrators - $($subscription.Name)" -ScriptBlock {
                if (Get-Command Get-AzSqlServer -ErrorAction SilentlyContinue) {
                    foreach ($server in Get-AzSqlServer) {
                        try {
                            $admin = Get-AzSqlServerActiveDirectoryAdministrator -ResourceGroupName $server.ResourceGroupName -ServerName $server.ServerName -ErrorAction Stop
                            if ($admin.ObjectId -eq $userId -or $admin.ObjectId -in @($script:TransitiveGroupIds)) {
                                Add-Finding -Area 'Azure SQL' -Severity Critical -Finding 'User or group is configured as Azure SQL Entra administrator' -Source 'Az PowerShell' -ObjectId $admin.ObjectId -Scope $server.ResourceId -Details $admin.DisplayName
                            }
                        } catch { }
                    }
                }
                else { Add-Finding -Area 'Azure SQL' -Severity Manual -Finding 'Az.Sql module not installed' -Source 'Script' -Scope $subscription.Id -Details 'Install Az.Sql to inspect Azure SQL Entra administrators. Database-contained users still require a database query.' }
            }
        }
    }
    else { Add-Finding -Area 'Azure' -Severity Manual -Finding 'Azure checks were skipped' -Source 'Parameter' }

    if (-not $SkipExchange -and $ExchangeOrganization) {
        Invoke-CheckedSection -Name 'Exchange shared mailbox delegation' -ScriptBlock {
            if (-not (Get-Module -ListAvailable ExchangeOnlineManagement)) { throw 'ExchangeOnlineManagement module is not installed.' }
            Import-Module ExchangeOnlineManagement
            Connect-ExchangeOnline -AppId $ClientId -CertificateThumbprint $CertificateThumbprint -Organization $ExchangeOrganization -ShowBanner:$false
            foreach ($mailbox in Get-EXOMailbox -RecipientTypeDetails SharedMailbox -ResultSize Unlimited -Properties GrantSendOnBehalfTo) {
                $fullAccess = Get-EXOMailboxPermission -Identity $mailbox.PrimarySmtpAddress -ResultSize Unlimited | Where-Object { $_.User -eq $UserPrincipalName -and -not $_.Deny }
                foreach ($p in $fullAccess) { Add-Finding -Area 'Exchange delegation' -Severity High -Finding 'Shared mailbox Full Access remains' -Source 'Exchange Online' -Scope $mailbox.PrimarySmtpAddress -Details ($p.AccessRights -join ',') }
                $sendAs = Get-EXORecipientPermission -Identity $mailbox.PrimarySmtpAddress -ResultSize Unlimited | Where-Object { $_.Trustee -eq $UserPrincipalName -and -not $_.Deny }
                foreach ($p in $sendAs) { Add-Finding -Area 'Exchange delegation' -Severity High -Finding 'Shared mailbox Send As remains' -Source 'Exchange Online' -Scope $mailbox.PrimarySmtpAddress -Details ($p.AccessRights -join ',') }
                if (@($mailbox.GrantSendOnBehalfTo) -match [regex]::Escape($UserPrincipalName)) { Add-Finding -Area 'Exchange delegation' -Severity High -Finding 'Shared mailbox Send on Behalf remains' -Source 'Exchange Online' -Scope $mailbox.PrimarySmtpAddress }
            }
            Disconnect-ExchangeOnline -Confirm:$false
        }
    }
    else { Add-Finding -Area 'Exchange delegation' -Severity Manual -Finding 'Exchange shared mailbox check not run' -Source 'Parameter' -Details 'Provide -ExchangeOrganization and do not use -SkipExchange to run it.' }

    foreach ($manual in @(
        @{Area='Azure DevOps'; Item='Review organization membership, project groups, repository permissions, pipelines, service connections, variable groups, SSH keys, and personal access tokens.'},
        @{Area='Power Platform'; Item='Review environment roles, Power Apps ownership, Power Automate ownership, connections, connection references, custom connectors, and Dataverse roles.'},
        @{Area='Azure SQL'; Item='Query each database for contained users and role memberships. Control-plane inspection cannot prove database-level access is absent.'},
        @{Area='ADLS Gen2'; Item='Review filesystem and path ACLs. Azure RBAC alone does not cover all data-plane ACL access.'},
        @{Area='Credentials'; Item='Rotate shared secrets, certificates, SSH keys, storage keys, SAS tokens, publishing profiles, and passwords the user could have copied.'},
        @{Area='Third-party SaaS'; Item='Review local accounts and tokens in 1Password, GitHub, ChatGPT, Claude, vendor portals, and other non-Entra systems.'},
        @{Area='Cross-tenant access'; Item='Run this report in every tenant where the person has a member, guest, admin, or service account.'}
    )) { Add-Finding -Area $manual.Area -Severity Manual -Finding 'Manual validation required' -Source 'Checklist' -Details $manual.Item }

    $sorted = $script:Findings | Sort-Object @{Expression={Get-SeverityRank $_.Severity}},Area,Finding
    $sorted | Export-Csv -Path (Join-Path $OutputPath 'Findings.csv') -NoTypeInformation -Encoding utf8
    $evidence = [ordered]@{
        GeneratedAt = (Get-Date).ToString('o')
        TenantId = $TenantId
        TargetUser = $user
        Findings = $sorted
        GraphContext = Get-MgContext
        AzContexts = if (-not $SkipAzure) { Get-AzContext -ListAvailable | Select-Object Account,Tenant,Subscription,Name } else { @() }
    }
    $evidence | ConvertTo-Json -Depth 10 | Set-Content -Path (Join-Path $OutputPath 'Evidence.json') -Encoding utf8

    $summary = $sorted | Group-Object Severity | Sort-Object { Get-SeverityRank $_.Name }
    $summaryRows = ($summary | ForEach-Object { "<tr><td>$($_.Name)</td><td>$($_.Count)</td></tr>" }) -join "`n"
    $findingRows = ($sorted | ForEach-Object {
        $values = @($_.Severity,$_.Area,$_.Finding,$_.Details,$_.Scope) | ForEach-Object { [System.Net.WebUtility]::HtmlEncode([string]$_) }
        "<tr class='$($values[0].ToLower())'><td>$($values[0])</td><td>$($values[1])</td><td>$($values[2])</td><td>$($values[3])</td><td>$($values[4])</td></tr>"
    }) -join "`n"
    $html = @"
<!doctype html><html><head><meta charset='utf-8'><title>Azure Entra Offboarding Report</title>
<style>body{font-family:Segoe UI,Arial,sans-serif;margin:32px;color:#222}table{border-collapse:collapse;width:100%;margin:16px 0}th,td{border:1px solid #ccc;padding:8px;text-align:left;vertical-align:top}th{background:#f3f3f3}.critical,.high{background:#ffe3e3}.medium,.error{background:#fff2cc}.manual{background:#e8f0fe}.info,.low{background:#e7f4e4}code{background:#f3f3f3;padding:2px 4px}</style></head><body>
<h1>Azure and Entra Offboarding Report</h1><p><b>User:</b> $([System.Net.WebUtility]::HtmlEncode($user.UserPrincipalName))<br><b>Object ID:</b> $userId<br><b>Generated:</b> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss K')<br><b>Read-only:</b> This report did not change access.</p>
<h2>Summary</h2><table><thead><tr><th>Severity</th><th>Count</th></tr></thead><tbody>$summaryRows</tbody></table>
<h2>Findings</h2><table><thead><tr><th>Severity</th><th>Area</th><th>Finding</th><th>Details</th><th>Scope</th></tr></thead><tbody>$findingRows</tbody></table>
</body></html>
"@
    $html | Set-Content -Path (Join-Path $OutputPath 'OffboardingReport.html') -Encoding utf8

    Write-Host "Report created: $OutputPath" -ForegroundColor Green
    Write-Host "Open: $(Join-Path $OutputPath 'OffboardingReport.html')" -ForegroundColor Green
}
finally {
    try { Disconnect-MgGraph | Out-Null } catch { }
    try { if (-not $SkipAzure) { Disconnect-AzAccount -ErrorAction SilentlyContinue | Out-Null } } catch { }
    try { Stop-Transcript | Out-Null } catch { }
}
