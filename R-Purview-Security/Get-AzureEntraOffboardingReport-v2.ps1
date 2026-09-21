#requires -Version 7.2
<#
.SYNOPSIS
Creates a read-only Azure and Microsoft Entra offboarding report for one user.

.DESCRIPTION
Uses certificate-based application authentication. Produces Findings.csv,
Evidence.json, OffboardingReport.html, and ExecutionTranscript.txt.
No access is changed.

# Granite
$UserPrincipalName     = 'jhull@graniteproject.dev'
$UserPrincipalName     = 'admin-jh@graniteproject.dev'
$TenantId              = 'a76bf141-b9f9-4f32-ad2a-060b5991730f'
$ClientId              = 'ddbd94ea-ad86-46f0-84af-24998ed86d2d'
$CertificateThumbprint = 'A1D8B302230D51274ED54FB6E1C182B890D560BC'
$ExchangeOrganization  = $null

# Erock
$UserPrincipalName     = 'JHull@erock.com'
$TenantId              = '0bdf0e1f-a359-4b5c-9b79-9357e35ff8c6'
$ClientId              = 'ea2ca49b-d0df-4774-b611-86cf9dc9629f'
$CertificateThumbprint = 'C47B91EB62634CA61FA8146DDA83B8BF605C0962'
$ExchangeOrganization  = 'enchantedrock.onmicrosoft.com'

$params = @{
    UserPrincipalName     = $UserPrincipalName
    TenantId              = $TenantId
    ClientId              = $ClientId
    CertificateThumbprint = $CertificateThumbprint
    ExchangeOrganization  = $ExchangeOrganization
    OutputPath            = 'C:\Users\DakotaRuhl\Documents\Reports\Elevated User Offboarding'
    SkipExchange          = $true
}

.\Get-AzureEntraOffboardingReport-v2.ps1 @params
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$UserPrincipalName,
    [Parameter(Mandatory)][string]$TenantId,
    [Parameter(Mandatory)][string]$ClientId,
    [Parameter(Mandatory)][string]$CertificateThumbprint,
    [string]$ExchangeOrganization,
    [string]$OutputPath = (Join-Path $PWD ("OffboardingReport-{0}-{1}" -f ($UserPrincipalName -replace '[^a-zA-Z0-9._-]','_'), (Get-Date -Format 'yyyyMMdd-HHmmss'))),
    [switch]$SkipAzure,
    [switch]$SkipExchange
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:Findings = [System.Collections.Generic.List[object]]::new()
$script:ObjectNameCache = @{}
$script:TransitiveGroupIds = @()
$script:CurrentUserObjectId = $null

function Add-Finding {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Area,
        [Parameter(Mandatory)][ValidateSet('Critical','High','Medium','Low','Info','Manual','Error')][string]$Severity,
        [Parameter(Mandatory)][string]$Finding,
        [string]$Source,
        [string]$TargetUserObjectId,
        [string]$PrincipalObjectId,
        [string]$ResourceObjectId,
        [string]$AssignmentObjectId,
        [string]$Scope,
        [string]$Details
    )
    $script:Findings.Add([pscustomobject]@{
        Area               = $Area
        Severity           = $Severity
        Finding            = $Finding
        Source             = $Source
        TargetUserObjectId = if ($TargetUserObjectId) { $TargetUserObjectId } else { $script:CurrentUserObjectId }
        PrincipalObjectId  = $PrincipalObjectId
        ResourceObjectId   = $ResourceObjectId
        AssignmentObjectId = $AssignmentObjectId
        Scope              = $Scope
        Details            = $Details
    }) | Out-Null
}

function Invoke-CheckedSection {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name,[Parameter(Mandatory)][scriptblock]$ScriptBlock)
    Write-Host "Checking $Name..." -ForegroundColor Cyan
    try { & $ScriptBlock }
    catch {
        Add-Finding -Area $Name -Severity Error -Finding 'Check failed' -Source 'Script' -Details $_.Exception.Message
        Write-Warning "$Name check failed: $($_.Exception.Message)"
    }
}

function Get-AllGraphPages {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Uri)

    $items = [System.Collections.Generic.List[object]]::new()
    $next = $Uri

    while (-not [string]::IsNullOrWhiteSpace($next)) {
        $response = Invoke-MgGraphRequest -Method GET -Uri $next -OutputType PSObject

        $valueProperty = $response.PSObject.Properties['value']
        if ($null -ne $valueProperty) {
            foreach ($item in @($valueProperty.Value)) {
                if ($null -ne $item) {
                    $items.Add($item) | Out-Null
                }
            }
        }
        elseif ($null -ne $response) {
            $items.Add($response) | Out-Null
        }

        $nextLinkProperty = $response.PSObject.Properties['@odata.nextLink']
        if ($null -ne $nextLinkProperty -and -not [string]::IsNullOrWhiteSpace([string]$nextLinkProperty.Value)) {
            $next = [string]$nextLinkProperty.Value
        }
        else {
            $next = $null
        }
    }

    return @($items)
}
function Resolve-DirectoryObjectName {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Id)
    if ($script:ObjectNameCache.ContainsKey($Id)) { return $script:ObjectNameCache[$Id] }
    try {
        $obj = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/directoryObjects/$Id" -OutputType PSObject
        $name = @($obj.displayName,$obj.userPrincipalName,$obj.appId,$Id) | Where-Object { $_ } | Select-Object -First 1
    }
    catch { $name = $Id }
    $script:ObjectNameCache[$Id] = $name
    return $name
}

function Get-SeverityRank {
    param([string]$Severity)
    switch ($Severity) {
        Critical { 1 }; High { 2 }; Medium { 3 }; Error { 4 }
        Manual { 5 }; Low { 6 }; Info { 7 }; default { 8 }
    }
}

New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
$TranscriptPath = Join-Path $OutputPath 'ExecutionTranscript.txt'
Start-Transcript -Path $TranscriptPath -Force | Out-Null

try {
    foreach ($module in 'Microsoft.Graph.Authentication','Microsoft.Graph.Users','Az.Accounts','Az.Resources') {
        if (-not (Get-Module -ListAvailable -Name $module)) { throw "Required module '$module' is not installed." }
    }

    Import-Module Microsoft.Graph.Authentication
    Import-Module Microsoft.Graph.Users
    Connect-MgGraph -TenantId $TenantId -ClientId $ClientId -CertificateThumbprint $CertificateThumbprint -NoWelcome

    $escapedUpn = $UserPrincipalName.Replace("'","''")
    $users = @(Get-MgUser -Filter "userPrincipalName eq '$escapedUpn'" -Property Id,DisplayName,UserPrincipalName,Mail,AccountEnabled,UserType,CreatedDateTime,EmployeeId,JobTitle,Department,AssignedLicenses -ConsistencyLevel eventual)
    if ($users.Count -eq 0) { throw "Unable to locate user: $UserPrincipalName" }
    if ($users.Count -gt 1) { throw "Multiple users matched UPN: $UserPrincipalName" }
    $user = $users[0]
    $userId = $user.Id
    $script:CurrentUserObjectId = $userId

    Add-Finding -Area 'Identity' -Severity $(if ($user.AccountEnabled) {'Critical'} else {'Info'}) -Finding $(if ($user.AccountEnabled) {'Account is enabled'} else {'Account is disabled'}) -Source 'Microsoft Graph' -PrincipalObjectId $userId -Details "DisplayName=$($user.DisplayName); UPN=$($user.UserPrincipalName); UserType=$($user.UserType)"

    if (@($user.AssignedLicenses).Count -gt 0) {
        Add-Finding -Area 'Licensing' -Severity Medium -Finding 'User still has assigned licenses' -Source 'Microsoft Graph' -PrincipalObjectId $userId -Details ("SkuIds=" + (@($user.AssignedLicenses.SkuId) -join ','))
    }
    else { Add-Finding -Area 'Licensing' -Severity Info -Finding 'No assigned licenses found' -Source 'Microsoft Graph' -PrincipalObjectId $userId }

    Invoke-CheckedSection -Name 'Authentication methods' -ScriptBlock {
        $methods = @(Get-AllGraphPages -Uri "https://graph.microsoft.com/v1.0/users/$userId/authentication/methods")
        foreach ($method in $methods) {
            $type = $method.'@odata.type' -replace '#microsoft.graph.',''
            Add-Finding -Area 'Authentication methods' -Severity High -Finding 'Authentication method remains registered' -Source 'Microsoft Graph' -PrincipalObjectId $userId -ResourceObjectId $method.id -Details "MethodType=$type; MethodObjectId=$($method.id)"
        }
        if ($methods.Count -eq 0) { Add-Finding -Area 'Authentication methods' -Severity Info -Finding 'No authentication methods found' -Source 'Microsoft Graph' -PrincipalObjectId $userId }
    }

    Invoke-CheckedSection -Name 'Group memberships' -ScriptBlock {
        $groups = @(Get-AllGraphPages -Uri "https://graph.microsoft.com/v1.0/users/$userId/transitiveMemberOf/microsoft.graph.group?`$select=id,displayName,securityEnabled,mailEnabled,isAssignableToRole,groupTypes")
        $script:TransitiveGroupIds = @($groups | ForEach-Object id)
        foreach ($group in $groups) {
            $severity = if ($group.isAssignableToRole) {'High'} else {'Medium'}
            Add-Finding -Area 'Group memberships' -Severity $severity -Finding 'Transitive group membership remains' -Source 'Microsoft Graph' -PrincipalObjectId $userId -ResourceObjectId $group.id -Details "GroupName=$($group.displayName); GroupObjectId=$($group.id); RoleAssignable=$($group.isAssignableToRole); SecurityEnabled=$($group.securityEnabled); MailEnabled=$($group.mailEnabled)"
        }
        if ($groups.Count -eq 0) { Add-Finding -Area 'Group memberships' -Severity Info -Finding 'No transitive group memberships found' -Source 'Microsoft Graph' -PrincipalObjectId $userId }
    }

    Invoke-CheckedSection -Name 'Enterprise application assignments' -ScriptBlock {
        $assignments = @(Get-AllGraphPages -Uri "https://graph.microsoft.com/v1.0/users/$userId/appRoleAssignments?`$select=id,principalId,resourceId,resourceDisplayName,appRoleId,createdDateTime")
        foreach ($assignment in $assignments) {
            Add-Finding -Area 'Enterprise application assignments' -Severity High -Finding 'Direct enterprise application assignment remains' -Source 'Microsoft Graph' -PrincipalObjectId $assignment.principalId -ResourceObjectId $assignment.resourceId -AssignmentObjectId $assignment.id -Details "Application=$($assignment.resourceDisplayName); ServicePrincipalObjectId=$($assignment.resourceId); AppRoleId=$($assignment.appRoleId); AssignmentObjectId=$($assignment.id)"
        }
        if ($assignments.Count -eq 0) { Add-Finding -Area 'Enterprise application assignments' -Severity Info -Finding 'No direct enterprise application assignments found' -Source 'Microsoft Graph' -PrincipalObjectId $userId }
    }

    Invoke-CheckedSection -Name 'Directory roles and Entra PIM' -ScriptBlock {
        $definitions = @(Get-AllGraphPages -Uri 'https://graph.microsoft.com/v1.0/roleManagement/directory/roleDefinitions?$select=id,displayName,isBuiltIn')
        $roleMap = @{}; foreach ($definition in $definitions) { $roleMap[$definition.id] = $definition.displayName }

        $active = @(Get-AllGraphPages -Uri "https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignmentScheduleInstances?`$filter=principalId eq '$userId'&`$select=id,principalId,roleDefinitionId,directoryScopeId,assignmentType,startDateTime,endDateTime")
        $eligible = @(Get-AllGraphPages -Uri "https://graph.microsoft.com/v1.0/roleManagement/directory/roleEligibilityScheduleInstances?`$filter=principalId eq '$userId'&`$select=id,principalId,roleDefinitionId,directoryScopeId,memberType,startDateTime,endDateTime")
        foreach ($role in $active) {
            Add-Finding -Area 'Entra PIM' -Severity Critical -Finding 'Active Entra role assignment remains' -Source 'Microsoft Graph' -PrincipalObjectId $role.principalId -ResourceObjectId $role.roleDefinitionId -AssignmentObjectId $role.id -Scope $role.directoryScopeId -Details "RoleName=$($roleMap[$role.roleDefinitionId]); RoleDefinitionObjectId=$($role.roleDefinitionId); AssignmentObjectId=$($role.id); Start=$($role.startDateTime); End=$($role.endDateTime)"
        }
        foreach ($role in $eligible) {
            Add-Finding -Area 'Entra PIM' -Severity High -Finding 'Eligible Entra role assignment remains' -Source 'Microsoft Graph' -PrincipalObjectId $role.principalId -ResourceObjectId $role.roleDefinitionId -AssignmentObjectId $role.id -Scope $role.directoryScopeId -Details "RoleName=$($roleMap[$role.roleDefinitionId]); RoleDefinitionObjectId=$($role.roleDefinitionId); EligibilityObjectId=$($role.id); Start=$($role.startDateTime); End=$($role.endDateTime)"
        }
        foreach ($groupId in $script:TransitiveGroupIds) {
            $groupRoles = @(Get-AllGraphPages -Uri "https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignments?`$filter=principalId eq '$groupId'&`$select=id,principalId,roleDefinitionId,directoryScopeId")
            foreach ($role in $groupRoles) {
                Add-Finding -Area 'Directory roles' -Severity Critical -Finding 'Entra role inherited through group' -Source 'Microsoft Graph' -PrincipalObjectId $groupId -ResourceObjectId $role.roleDefinitionId -AssignmentObjectId $role.id -Scope $role.directoryScopeId -Details "GroupName=$(Resolve-DirectoryObjectName $groupId); GroupObjectId=$groupId; RoleName=$($roleMap[$role.roleDefinitionId]); RoleDefinitionObjectId=$($role.roleDefinitionId); AssignmentObjectId=$($role.id)"
            }
        }
        if (($active.Count + $eligible.Count) -eq 0) { Add-Finding -Area 'Entra PIM' -Severity Info -Finding 'No direct active or eligible Entra PIM assignments found' -Source 'Microsoft Graph' -PrincipalObjectId $userId }
    }

    Invoke-CheckedSection -Name 'Owned directory objects' -ScriptBlock {
        $owned = @(Get-AllGraphPages -Uri "https://graph.microsoft.com/v1.0/users/$userId/ownedObjects")
        foreach ($object in $owned) {
            $type = $object.'@odata.type' -replace '#microsoft.graph.',''
            switch ($type) {
                'application' {
                    $severity = 'Critical'
                    $finding  = 'User owns application'
                }

                'servicePrincipal' {
                    $severity = 'Critical'
                    $finding  = 'User owns service principal'
                }

                'group' {
                    $severity = 'Medium'
                    $finding  = 'User owns group'
                }

                'device' {
                    $severity = 'Low'
                    $finding  = 'User owns device'
                }

                default {
                    $severity = 'Medium'
                    $finding  = 'User owns directory object'
                }
            }
            $appId = $null

            if ($type -eq 'application') {
                try {
                    $app = Invoke-MgGraphRequest `
                        -Method GET `
                        -Uri "https://graph.microsoft.com/v1.0/applications/$($object.id)"

                    $appId = $app.appId
                }
                catch {
                    $appId = 'Unable to retrieve'
                }
            }
            

            Add-Finding `
                -Area 'Owned directory objects' `
                -Severity $severity `
                -Finding $finding `
                -Source 'Microsoft Graph' `
                -PrincipalObjectId $userId `
                -ResourceObjectId $object.id `
                -Details @"
Type=$type
DisplayName=$($object.displayName)
ObjectId=$($object.id)
AppId=$appId
"@
        }

        if ($owned.Count -eq 0) {
            Add-Finding `
                -Area 'Owned directory objects' `
                -Severity Info `
                -Finding 'No owned directory objects found' `
                -Source 'Microsoft Graph' `
                -PrincipalObjectId $userId
        }
    }


    Invoke-CheckedSection -Name 'Registered devices' -ScriptBlock {
        $devices = @(Get-AllGraphPages -Uri "https://graph.microsoft.com/v1.0/users/$userId/registeredDevices?`$select=id,deviceId,displayName,accountEnabled,operatingSystem,trustType,approximateLastSignInDateTime")
        foreach ($device in $devices) {
            Add-Finding -Area 'Devices' -Severity Medium -Finding 'Registered device relationship remains' -Source 'Microsoft Graph' -PrincipalObjectId $userId -ResourceObjectId $device.id -Details "DisplayName=$($device.displayName); DirectoryObjectId=$($device.id); DeviceId=$($device.deviceId); OS=$($device.operatingSystem); TrustType=$($device.trustType); Enabled=$($device.accountEnabled); LastSignIn=$($device.approximateLastSignInDateTime)"
        }
        if ($devices.Count -eq 0) { Add-Finding -Area 'Devices' -Severity Info -Finding 'No registered devices found' -Source 'Microsoft Graph' -PrincipalObjectId $userId }
    }

    if (-not $SkipAzure) {
        Import-Module Az.Accounts
        Import-Module Az.Resources
        Connect-AzAccount -ServicePrincipal -Tenant $TenantId -ApplicationId $ClientId -CertificateThumbprint $CertificateThumbprint | Out-Null
        $subscriptions = @(Get-AzSubscription -TenantId $TenantId | Where-Object State -eq 'Enabled')
        foreach ($subscription in $subscriptions) {
            Invoke-CheckedSection -Name "Azure RBAC - $($subscription.Name)" -ScriptBlock {
                Set-AzContext -SubscriptionId $subscription.Id -TenantId $TenantId | Out-Null
                $assignments = @(Get-AzRoleAssignment -Scope "/subscriptions/$($subscription.Id)" -IncludeClassicAdministrators)
                $matching = @($assignments | Where-Object { $_.ObjectId -eq $userId -or $_.ObjectId -in $script:TransitiveGroupIds })
                foreach ($assignment in $matching) {
                    $via = if ($assignment.ObjectId -eq $userId) {'Direct'} else {"ViaGroup=$(Resolve-DirectoryObjectName $assignment.ObjectId)"}
                    Add-Finding -Area 'Azure RBAC' -Severity Critical -Finding 'Azure role assignment grants access' -Source 'Az PowerShell' -PrincipalObjectId $assignment.ObjectId -ResourceObjectId $assignment.RoleDefinitionId -AssignmentObjectId $assignment.RoleAssignmentId -Scope $assignment.Scope -Details "Role=$($assignment.RoleDefinitionName); RoleDefinitionId=$($assignment.RoleDefinitionId); AssignmentId=$($assignment.RoleAssignmentId); PrincipalObjectId=$($assignment.ObjectId); PrincipalType=$($assignment.ObjectType); $via; Subscription=$($subscription.Name); SubscriptionId=$($subscription.Id)"
                }
            }

            Invoke-CheckedSection -Name "Azure resource PIM - $($subscription.Name)" -ScriptBlock {
                if (Get-Command Get-AzRoleEligibilityScheduleInstance -ErrorAction SilentlyContinue) {
                    $eligible = @(Get-AzRoleEligibilityScheduleInstance -Scope "/subscriptions/$($subscription.Id)" | Where-Object { $_.PrincipalId -eq $userId -or $_.PrincipalId -in $script:TransitiveGroupIds })
                    foreach ($role in $eligible) {
                        $via = if ($role.PrincipalId -eq $userId) {'Direct'} else {"ViaGroup=$(Resolve-DirectoryObjectName $role.PrincipalId)"}
                        Add-Finding -Area 'Azure resource PIM' -Severity High -Finding 'Eligible Azure resource role remains' -Source 'Az PowerShell' -PrincipalObjectId $role.PrincipalId -ResourceObjectId $role.RoleDefinitionId -AssignmentObjectId $role.Id -Scope $role.Scope -Details "RoleDefinitionId=$($role.RoleDefinitionId); EligibilityObjectId=$($role.Id); $via; Subscription=$($subscription.Name); SubscriptionId=$($subscription.Id)"
                    }
                }
                else { Add-Finding -Area 'Azure resource PIM' -Severity Manual -Finding 'Get-AzRoleEligibilityScheduleInstance is unavailable' -Source 'Az PowerShell' -ResourceObjectId $subscription.Id -Scope "/subscriptions/$($subscription.Id)" -Details 'Update Az.Resources or review Azure resource PIM manually.' }
            }

            Invoke-CheckedSection -Name "Key Vault access policies - $($subscription.Name)" -ScriptBlock {
                if (Get-Command Get-AzKeyVault -ErrorAction SilentlyContinue) {
                    foreach ($vault in @(Get-AzKeyVault)) {
                        foreach ($policy in @($vault.AccessPolicies)) {
                            if ($policy.ObjectId -eq $userId -or $policy.ObjectId -in $script:TransitiveGroupIds) {
                                Add-Finding -Area 'Key Vault legacy access policies' -Severity Critical -Finding 'Key Vault access policy grants access' -Source 'Az PowerShell' -PrincipalObjectId $policy.ObjectId -ResourceObjectId $vault.ResourceId -Scope $vault.ResourceId -Details "Vault=$($vault.VaultName); VaultResourceId=$($vault.ResourceId); PrincipalObjectId=$($policy.ObjectId); Keys=$($policy.PermissionsToKeys -join ','); Secrets=$($policy.PermissionsToSecrets -join ','); Certificates=$($policy.PermissionsToCertificates -join ','); Storage=$($policy.PermissionsToStorage -join ',')"
                            }
                        }
                    }
                }
                else { Add-Finding -Area 'Key Vault legacy access policies' -Severity Manual -Finding 'Az.KeyVault module is not installed' -Source 'Script' -ResourceObjectId $subscription.Id -Scope "/subscriptions/$($subscription.Id)" }
            }
        }
    }
    else { Add-Finding -Area 'Azure' -Severity Manual -Finding 'Azure checks were skipped' -Source 'Parameter' -PrincipalObjectId $userId }

    if (-not $SkipExchange -and $ExchangeOrganization) {
        Invoke-CheckedSection -Name 'Exchange shared mailbox delegation' -ScriptBlock {
            if (-not (Get-Module -ListAvailable ExchangeOnlineManagement)) { throw 'ExchangeOnlineManagement module is not installed.' }
            Import-Module ExchangeOnlineManagement
            Connect-ExchangeOnline -AppId $ClientId -CertificateThumbprint $CertificateThumbprint -Organization $ExchangeOrganization -ShowBanner:$false
            foreach ($mailbox in @(Get-EXOMailbox -RecipientTypeDetails SharedMailbox -ResultSize Unlimited -Properties ExternalDirectoryObjectId,GrantSendOnBehalfTo)) {
                foreach ($permission in @(Get-EXOMailboxPermission -Identity $mailbox.PrimarySmtpAddress -ResultSize Unlimited | Where-Object { $_.User -eq $UserPrincipalName -and -not $_.Deny })) {
                    Add-Finding -Area 'Exchange delegation' -Severity High -Finding 'Shared mailbox Full Access remains' -Source 'Exchange Online' -PrincipalObjectId $userId -ResourceObjectId $mailbox.ExternalDirectoryObjectId -Scope $mailbox.PrimarySmtpAddress -Details "MailboxObjectId=$($mailbox.ExternalDirectoryObjectId); Rights=$($permission.AccessRights -join ',')"
                }
                foreach ($permission in @(Get-EXORecipientPermission -Identity $mailbox.PrimarySmtpAddress -ResultSize Unlimited | Where-Object { $_.Trustee -eq $UserPrincipalName -and -not $_.Deny })) {
                    Add-Finding -Area 'Exchange delegation' -Severity High -Finding 'Shared mailbox Send As remains' -Source 'Exchange Online' -PrincipalObjectId $userId -ResourceObjectId $mailbox.ExternalDirectoryObjectId -Scope $mailbox.PrimarySmtpAddress -Details "MailboxObjectId=$($mailbox.ExternalDirectoryObjectId); Rights=$($permission.AccessRights -join ',')"
                }
                if (@($mailbox.GrantSendOnBehalfTo) -match [regex]::Escape($UserPrincipalName)) {
                    Add-Finding -Area 'Exchange delegation' -Severity High -Finding 'Shared mailbox Send on Behalf remains' -Source 'Exchange Online' -PrincipalObjectId $userId -ResourceObjectId $mailbox.ExternalDirectoryObjectId -Scope $mailbox.PrimarySmtpAddress -Details "MailboxObjectId=$($mailbox.ExternalDirectoryObjectId)"
                }
            }
            Disconnect-ExchangeOnline -Confirm:$false
        }
    }
    else { Add-Finding -Area 'Exchange delegation' -Severity Manual -Finding 'Exchange shared mailbox check was not run' -Source 'Parameter' -PrincipalObjectId $userId }

    foreach ($manual in @(
        @{Area='Azure DevOps';Item='Review organization membership, project groups, repositories, pipelines, service connections, variable groups, SSH keys, and personal access tokens.'},
        @{Area='Power Platform';Item='Review environment roles, app and flow ownership, connections, connection references, custom connectors, and Dataverse roles.'},
        @{Area='Azure SQL';Item='Query each database for contained users and database role memberships.'},
        @{Area='ADLS Gen2';Item='Review filesystem and path ACLs.'},
        @{Area='Credentials';Item='Rotate shared secrets, certificates, SSH keys, storage keys, SAS tokens, publishing profiles, and passwords the user could have copied.'},
        @{Area='Third-party SaaS';Item='Review local accounts and tokens in non-Entra systems.'},
        @{Area='Cross-tenant access';Item='Run this report in every tenant containing a member, guest, admin, or service account for the person.'}
    )) { Add-Finding -Area $manual.Area -Severity Manual -Finding 'Manual validation required' -Source 'Checklist' -PrincipalObjectId $userId -Details $manual.Item }

    $sorted = @($script:Findings | Sort-Object @{Expression={Get-SeverityRank $_.Severity}},Area,Finding)
    $sorted | Export-Csv -Path (Join-Path $OutputPath 'Findings.csv') -NoTypeInformation -Encoding utf8

    $evidence = [ordered]@{
        GeneratedAt = (Get-Date).ToString('o')
        TenantId = $TenantId
        TargetUser = [ordered]@{ DisplayName=$user.DisplayName; UserPrincipalName=$user.UserPrincipalName; ObjectId=$userId; AccountEnabled=$user.AccountEnabled }
        Findings = $sorted
        GraphContext = Get-MgContext
        AzContexts = if (-not $SkipAzure) { @(Get-AzContext -ListAvailable | Select-Object Account,Tenant,Subscription,Name) } else { @() }
    }
    $evidence | ConvertTo-Json -Depth 12 | Set-Content -Path (Join-Path $OutputPath 'Evidence.json') -Encoding utf8

    $summaryRows = (@($sorted | Group-Object Severity | Sort-Object { Get-SeverityRank $_.Name }) | ForEach-Object { "<tr><td>$($_.Name)</td><td>$($_.Count)</td></tr>" }) -join "`n"
    $findingRows = ($sorted | ForEach-Object {
        $values = @($_.Severity,$_.Area,$_.Finding,$_.PrincipalObjectId,$_.ResourceObjectId,$_.AssignmentObjectId,$_.Details,$_.Scope) | ForEach-Object { [System.Net.WebUtility]::HtmlEncode([string]$_) }
        "<tr class='$($values[0].ToLower())'><td>$($values[0])</td><td>$($values[1])</td><td>$($values[2])</td><td>$($values[3])</td><td>$($values[4])</td><td>$($values[5])</td><td>$($values[6])</td><td>$($values[7])</td></tr>"
    }) -join "`n"
    $html = @"
<!doctype html><html><head><meta charset='utf-8'><title>Azure Entra Offboarding Report</title>
<style>body{font-family:Segoe UI,Arial,sans-serif;margin:32px;color:#222}table{border-collapse:collapse;width:100%;margin:16px 0;font-size:12px}th,td{border:1px solid #ccc;padding:7px;text-align:left;vertical-align:top;overflow-wrap:anywhere}th{background:#f3f3f3}.critical,.high{background:#ffe3e3}.medium,.error{background:#fff2cc}.manual{background:#e8f0fe}.info,.low{background:#e7f4e4}</style></head><body>
<h1>Azure and Entra Offboarding Report</h1><p><b>User:</b> $([System.Net.WebUtility]::HtmlEncode($user.UserPrincipalName))<br><b>User Object ID:</b> $userId<br><b>Generated:</b> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss K')<br><b>Read-only:</b> This report did not change access.</p>
<h2>Summary</h2><table><thead><tr><th>Severity</th><th>Count</th></tr></thead><tbody>$summaryRows</tbody></table>
<h2>Findings</h2><table><thead><tr><th>Severity</th><th>Area</th><th>Finding</th><th>Principal Object ID</th><th>Resource Object ID</th><th>Assignment Object ID</th><th>Details</th><th>Scope</th></tr></thead><tbody>$findingRows</tbody></table>
</body></html>
"@
    $html | Set-Content -Path (Join-Path $OutputPath 'OffboardingReport.html') -Encoding utf8
    Write-Host "Report created: $OutputPath" -ForegroundColor Green
}
finally {
    try { Disconnect-MgGraph | Out-Null } catch { }
    try { if (-not $SkipAzure) { Disconnect-AzAccount -ErrorAction SilentlyContinue | Out-Null } } catch { }
    try { Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue } catch { }
    try { Stop-Transcript | Out-Null } catch { }
}

