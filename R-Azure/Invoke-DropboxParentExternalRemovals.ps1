#requires -Version 7.2
<#
.SYNOPSIS
Generates and executes parent-level external-member removals for Dropbox folders whose
external access is inherited outside a shared team root.

.DESCRIPTION
ParentAudit is read-only. It reads the latest allowlist and inheritance audit produced by
Invoke-DropboxAllowlistEnforcement, resolves each unsupported child's controlling shared
folder through files/get_metadata sharing_info.parent_shared_folder_id, audits the parent ACL,
and exports immutable ParentExternalRemovals approvals. ParentRemove requires Approval=APPROVED,
a valid RowHash, and an explicit confirmation string.

Required environment variables:
  DROPBOX_REFRESH_TOKEN
  DROPBOX_APP_KEY
  DROPBOX_APP_SECRET

Required scopes:
  members.read, team_data.member, files.metadata.read, sharing.read, sharing.write
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('ParentAudit','ParentRemove','ParentVerify','Status')]
    [string]$Mode,

    [string]$AdminEmail = 'druhl@enchantedrock.com',
    [string]$AllowlistReportPath = (Join-Path $PSScriptRoot 'DropboxAllowlistEnforcement\Reports'),
    [string]$WorkPath = (Join-Path $PSScriptRoot 'DropboxParentExternalRemovals'),
    [string]$ApprovalCsv,

    [ValidateSet('APPROVE-DROPBOX-PARENT-EXTERNAL-REMOVALS')]
    [string]$Confirmation,

    [ValidateRange(0,1000)]
    [int]$MaxItems = 0,

    [ValidateRange(1,20)]
    [int]$MaxRetry = 8
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ReportPath = Join-Path $WorkPath 'Reports'
$StatePath = Join-Path $WorkPath 'State'
$LedgerPath = Join-Path $StatePath 'OperationLedger.csv'
New-Item -ItemType Directory -Path $ReportPath,$StatePath -Force | Out-Null

function Get-ConfiguredEnvironmentVariable {
    param([Parameter(Mandatory)][string]$Name)
    foreach($scope in @('Process','User','Machine')){
        $value=[Environment]::GetEnvironmentVariable($Name,$scope)
        if(-not[string]::IsNullOrWhiteSpace($value)){return [string]$value}
    }
    return $null
}

$script:RefreshToken=Get-ConfiguredEnvironmentVariable 'DROPBOX_REFRESH_TOKEN'
$script:AppKey=Get-ConfiguredEnvironmentVariable 'DROPBOX_APP_KEY'
$script:AppSecret=Get-ConfiguredEnvironmentVariable 'DROPBOX_APP_SECRET'
$script:AccessToken=$null
$script:TokenExpiresAt=[datetime]::MinValue
$script:AdminMemberId=$null
$script:SuccessKeys=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)

function Get-OptionalProperty {
    param([object]$Object,[string]$Name)
    if($null-ne$Object-and$Object.PSObject.Properties.Name-contains$Name){return $Object.$Name}
    return $null
}

function ConvertTo-Boolean {
    param([object]$Value)
    return ([string]$Value).Trim().ToLowerInvariant()-eq'true'
}

function Assert-Credentials {
    $missing=@()
    if([string]::IsNullOrWhiteSpace($script:RefreshToken)){$missing+='DROPBOX_REFRESH_TOKEN'}
    if([string]::IsNullOrWhiteSpace($script:AppKey)){$missing+='DROPBOX_APP_KEY'}
    if([string]::IsNullOrWhiteSpace($script:AppSecret)){$missing+='DROPBOX_APP_SECRET'}
    if($missing.Count){throw "Missing environment variables: $($missing-join', ')"}
}

function Get-DropboxAccessToken {
    param([switch]$ForceRefresh)
    if(-not$ForceRefresh-and$script:AccessToken-and$script:TokenExpiresAt-gt(Get-Date).AddMinutes(5)){return$script:AccessToken}
    Assert-Credentials
    $basic=[Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$($script:AppKey):$($script:AppSecret)"))
    $response=Invoke-RestMethod -Method Post -Uri 'https://api.dropboxapi.com/oauth2/token' `
        -Headers @{Authorization="Basic $basic"} -ContentType 'application/x-www-form-urlencoded' `
        -Body @{grant_type='refresh_token';refresh_token=$script:RefreshToken}
    $script:AccessToken=[string]$response.access_token
    $script:TokenExpiresAt=(Get-Date).AddSeconds([int]$response.expires_in)
    return$script:AccessToken
}

function Get-HttpStatusCode {
    param([object]$ErrorRecord)
    try{return[int]$ErrorRecord.Exception.Response.StatusCode}catch{return 0}
}

function Invoke-DropboxApi {
    param(
        [Parameter(Mandatory)][string]$Uri,
        [AllowNull()][object]$Body,
        [string]$SelectUser,
        [string]$SelectAdmin,
        [string]$NamespaceId
    )
    $refreshed=$false
    for($attempt=1;$attempt-le$MaxRetry;$attempt++){
        try{
            $headers=@{Authorization="Bearer $(Get-DropboxAccessToken)"}
            if($SelectUser){$headers['Dropbox-API-Select-User']=$SelectUser}
            if($SelectAdmin){$headers['Dropbox-API-Select-Admin']=$SelectAdmin}
            if($NamespaceId){$headers['Dropbox-API-Path-Root']=(@{'.tag'='namespace_id';namespace_id=$NamespaceId}|ConvertTo-Json -Compress)}
            $json=if($null-eq$Body){'null'}else{$Body|ConvertTo-Json -Depth 20 -Compress}
            return Invoke-RestMethod -Method Post -Uri $Uri -Headers $headers -ContentType 'application/json' -Body $json
        }catch{
            $status=Get-HttpStatusCode $_
            if($status-eq401){
                if(-not$refreshed){$refreshed=$true;[void](Get-DropboxAccessToken -ForceRefresh);continue}
                throw "AUTH_FATAL: Dropbox authorization failed after refresh. API: $Uri. $($_.Exception.Message)"
            }
            $retryable=$status-in@(0,408,429)-or$status-ge500
            if(-not$retryable-or$attempt-eq$MaxRetry){throw}
            $delay=0;try{$delay=[int]$_.Exception.Response.Headers.RetryAfter.Delta.TotalSeconds}catch{}
            if($delay-le0){$delay=[int][Math]::Min(300,[Math]::Pow(2,$attempt)+(Get-Random -Minimum 0 -Maximum 4))}
            Write-Warning "$Uri failed (HTTP $status), attempt $attempt/$MaxRetry. Retrying in $delay seconds."
            Start-Sleep -Seconds $delay
        }
    }
}

function Get-TeamMembers {
    param([bool]$IncludeRemoved=$true)
    $response=Invoke-DropboxApi -Uri 'https://api.dropboxapi.com/2/team/members/list_v2' -Body @{include_removed=$IncludeRemoved;limit=1000}
    $items=[Collections.Generic.List[object]]::new();foreach($item in @($response.members)){$items.Add($item)}
    while([bool](Get-OptionalProperty $response 'has_more')){
        $response=Invoke-DropboxApi -Uri 'https://api.dropboxapi.com/2/team/members/list/continue_v2' -Body @{cursor=$response.cursor}
        foreach($item in @($response.members)){$items.Add($item)}
    }
    return$items
}

function Get-FolderMembers {
    param([string]$SharedFolderId,[string]$SelectUser)
    $response=Invoke-DropboxApi -Uri 'https://api.dropboxapi.com/2/sharing/list_folder_members' `
        -SelectUser $SelectUser -Body @{shared_folder_id=$SharedFolderId;actions=@();limit=1000}
    $pages=[Collections.Generic.List[object]]::new();$pages.Add($response)
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    while($true){
        $cursor=[string](Get-OptionalProperty $response 'cursor');if([string]::IsNullOrWhiteSpace($cursor)){break}
        if(-not$seen.Add($cursor)){throw "Repeated member cursor for '$SharedFolderId'."}
        $response=Invoke-DropboxApi -Uri 'https://api.dropboxapi.com/2/sharing/list_folder_members/continue' `
            -SelectUser $SelectUser -Body @{cursor=$cursor};$pages.Add($response)
    }
    return$pages
}

function Get-LatestReport {
    param([string]$Filter)
    $file=Get-ChildItem -LiteralPath $AllowlistReportPath -Filter $Filter -File -ErrorAction SilentlyContinue|Sort-Object LastWriteTime -Descending|Select-Object -First 1
    if(-not$file){throw "No report matching '$Filter' was found under '$AllowlistReportPath'."}
    return$file
}

function Get-ImmutableValue {
    param([object]$Row,[string]$Name)
    $value=Get-OptionalProperty $Row $Name;if($null-eq$value){return''};return([string]$value).Trim()
}

function Get-RowHash {
    param([object]$Row)
    $fields=@('Action','OperationKey','ParentSharedFolderId','ParentOwnerTeamMemberId','PrincipalType','PrincipalId','Email','IsExternal','IsInherited','Eligible','LeaveACopy','AffectedChildren')
    $canonical=($fields|ForEach-Object{"$_=$(Get-ImmutableValue $Row $_)"})-join"`n"
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return([Convert]::ToHexString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($canonical)))).ToLowerInvariant()}finally{$sha.Dispose()}
}

function Add-RowHash {
    param([object]$Row)
    $Row|Add-Member -NotePropertyName RowHash -NotePropertyValue (Get-RowHash $Row) -Force;return$Row
}

function Add-LedgerRow {
    param([string]$Key,[string]$Status,[string]$Message)
    [pscustomobject]@{Timestamp=(Get-Date).ToString('o');Key=$Key;Action='ParentRemoveExternal';Status=$Status;Message=$Message}|Export-Csv $LedgerPath -Append -NoTypeInformation -Encoding utf8
    if($Status-eq'Success'){[void]$script:SuccessKeys.Add($Key)}
}

function Initialize-Ledger {
    if(Test-Path $LedgerPath){foreach($row in @(Import-Csv $LedgerPath|Where-Object Status -eq'Success')){[void]$script:SuccessKeys.Add([string]$row.Key)}}
}

function Get-MemberSelector {
    param([object]$Row)
    if($Row.PrincipalType-in@('user','group')-and$Row.PrincipalId){$selector=@{dropbox_id=$Row.PrincipalId};$selector['.tag']='dropbox_id';return $selector}
    $selector=@{email=$Row.Email};$selector['.tag']='email';return $selector
}

function Assert-Approval {
    if($Confirmation-ne'APPROVE-DROPBOX-PARENT-EXTERNAL-REMOVALS'){throw'Required confirmation was not supplied.'}
    if([string]::IsNullOrWhiteSpace($ApprovalCsv)-or-not(Test-Path $ApprovalCsv -PathType Leaf)){throw'Valid -ApprovalCsv required.'}
    $rows=@(Import-Csv $ApprovalCsv)
    foreach($column in @('Action','Approval','OperationKey','Eligible','RowHash')){if($rows.Count-eq0-or$rows[0].PSObject.Properties.Name-notcontains$column){throw"Approval CSV missing '$column'."}}
    $approved=@($rows|Where-Object{$_.Action-eq'ParentRemoveExternal'-and([string]$_.Approval).Trim().ToUpperInvariant()-eq'APPROVED'})
    foreach($row in $approved){if((Get-RowHash $row)-ne([string]$row.RowHash).Trim().ToLowerInvariant()){throw"Immutable fields changed for '$($row.OperationKey)'."};if(-not(ConvertTo-Boolean $row.Eligible)){throw"Row '$($row.OperationKey)' is not eligible."}}
    if($MaxItems-gt0){$approved=@($approved|Select-Object -First $MaxItems)}
    if($approved.Count-eq0){throw'No approved eligible rows found.'};return$approved
}

function Invoke-ParentAudit {
    param([string]$Label='Audit')
    $stamp=Get-Date -Format 'yyyyMMdd-HHmmss'
    $members=@(Get-TeamMembers -IncludeRemoved $true)
    $active=@($members|Where-Object{[string]$_.profile.status.'.tag'-eq'active'})
    $admin=$active|Where-Object{$_.profile.email-eq$AdminEmail}|Select-Object -First 1;if(-not$admin){throw"Active admin '$AdminEmail' not found."}

    $allowedAccounts=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $allowedMembers=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $allowedEmails=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($member in $active){if($member.profile.account_id){[void]$allowedAccounts.Add([string]$member.profile.account_id)};[void]$allowedMembers.Add([string]$member.profile.team_member_id);[void]$allowedEmails.Add([string]$member.profile.email)}

    $inheritanceReport=Get-LatestReport 'Audit-InheritanceBreaks-*.csv'
    $children=@(Import-Csv $inheritanceReport.FullName|Where-Object{$_.AccessInheritance-eq'inherit'})
    $candidateMap=@{};$exceptions=[Collections.Generic.List[object]]::new();$failures=[Collections.Generic.List[object]]::new()
    $i=0
    foreach($child in $children){
        $i++;Write-Progress -Activity "$($Label): resolve controlling parents" -Status "$i/$($children.Count): $($child.FolderName)" -PercentComplete (($i/[Math]::Max($children.Count,1))*100)
        try{
            if([string]::IsNullOrWhiteSpace($child.OwnerTeamMemberId)-or[string]::IsNullOrWhiteSpace($child.SharedFolderId)){throw'Child row lacks owner or folder ID.'}
            $sharedMetadata=Invoke-DropboxApi -Uri 'https://api.dropboxapi.com/2/sharing/get_folder_metadata' -SelectUser $child.OwnerTeamMemberId -Body @{shared_folder_id=$child.SharedFolderId}
            $path=[string](Get-OptionalProperty $sharedMetadata 'path_lower')
            if([string]::IsNullOrWhiteSpace($path)){throw'Folder metadata did not return path_lower.'}
            $fileMetadata=Invoke-DropboxApi -Uri 'https://api.dropboxapi.com/2/files/get_metadata' -SelectUser $child.OwnerTeamMemberId `
                -Body @{path=$path;include_deleted=$false;include_has_explicit_shared_members=$true}
            $sharingInfo=Get-OptionalProperty $fileMetadata 'sharing_info'
            $parentId=[string](Get-OptionalProperty $sharingInfo 'parent_shared_folder_id')
            if([string]::IsNullOrWhiteSpace($parentId)){throw'files/get_metadata did not return sharing_info.parent_shared_folder_id.'}

            $parentMetadata=Invoke-DropboxApi -Uri 'https://api.dropboxapi.com/2/sharing/get_folder_metadata' -SelectUser $child.OwnerTeamMemberId -Body @{shared_folder_id=$parentId}
            $parentName=[string](Get-OptionalProperty $parentMetadata 'name')
            $parentPages=@(Get-FolderMembers -SharedFolderId $parentId -SelectUser $child.OwnerTeamMemberId)
            $parentOwnerId='';$parentOwnerEmail='';$externalRows=[Collections.Generic.List[object]]::new()
            foreach($page in $parentPages){
                foreach($entry in @((Get-OptionalProperty $page 'users'))){
                    $accountId=[string](Get-OptionalProperty $entry.user 'account_id');$memberId=[string](Get-OptionalProperty $entry.user 'team_member_id');$email=[string](Get-OptionalProperty $entry.user 'email');$access=[string]$entry.access_type.'.tag';$inherited=[bool](Get-OptionalProperty $entry 'is_inherited')
                    $allowed=$allowedAccounts.Contains($accountId)-or$allowedMembers.Contains($memberId)-or$allowedEmails.Contains($email)
                    if($access-eq'owner'){$parentOwnerId=$memberId;$parentOwnerEmail=$email}
                    if(-not$allowed-and-not$inherited-and$access-ne'owner'){$externalRows.Add([pscustomobject]@{Type='user';Id=$accountId;Email=$email;Name=$entry.user.display_name;Access=$access})}
                }
                foreach($entry in @((Get-OptionalProperty $page 'groups'))){
                    $groupId=[string](Get-OptionalProperty $entry.group 'group_id');$sameTeam=[bool](Get-OptionalProperty $entry.group 'same_team');$inherited=[bool](Get-OptionalProperty $entry 'is_inherited')
                    if(-not$sameTeam-and-not$inherited){$externalRows.Add([pscustomobject]@{Type='group';Id=$groupId;Email='';Name=$entry.group.group_name;Access=[string]$entry.access_type.'.tag'})}
                }
                foreach($entry in @((Get-OptionalProperty $page 'invitees'))){
                    $email=[string](Get-OptionalProperty $entry.invitee 'email');$inherited=[bool](Get-OptionalProperty $entry 'is_inherited')
                    if(-not$allowedEmails.Contains($email)-and-not$inherited){$externalRows.Add([pscustomobject]@{Type='invitee';Id='';Email=$email;Name=$email;Access=[string]$entry.access_type.'.tag'})}
                }
            }
            $ownerActive=$allowedMembers.Contains($parentOwnerId)
            foreach($external in $externalRows){
                $principalKey=if($external.Id){$external.Id}else{$external.Email}
                $key="ParentRemoveExternal|$parentId|$($external.Type)|$principalKey"
                if(-not$candidateMap.ContainsKey($key)){
                    $row=[pscustomobject]@{Action='ParentRemoveExternal';Approval='';OperationKey=$key;ParentFolderName=$parentName;ParentSharedFolderId=$parentId;ParentOwnerEmail=$parentOwnerEmail;ParentOwnerTeamMemberId=$parentOwnerId;PrincipalType=$external.Type;PrincipalName=$external.Name;PrincipalId=$external.Id;Email=$external.Email;AccessType=$external.Access;IsExternal=$true;IsInherited=$false;Eligible=$ownerActive;LeaveACopy=$false;AffectedChildren=1;AffectedChildNames=$child.FolderName;Notes=if($ownerActive){'Remove explicit external principal at controlling parent.'}else{'Parent owner is not an active allowlisted member.'}}
                    $candidateMap[$key]=Add-RowHash $row
                }else{
                    $existing=$candidateMap[$key];$existing.AffectedChildren=[int]$existing.AffectedChildren+1;$existing.AffectedChildNames="$($existing.AffectedChildNames); $($child.FolderName)";$existing.RowHash=Get-RowHash $existing
                }
            }
            if($externalRows.Count-eq0){$exceptions.Add([pscustomobject]@{ChildFolderName=$child.FolderName;ChildSharedFolderId=$child.SharedFolderId;ChildPath=$path;ParentFolderName=$parentName;ParentSharedFolderId=$parentId;Reason='NoExplicitExternalPrincipalFoundAtResolvedParent';Resolution='Walk farther upward or verify group membership manually.'})}
        }catch{
            if($_.Exception.Message-like'AUTH_FATAL:*'){throw}
            $failures.Add([pscustomobject]@{ChildFolderName=$child.FolderName;ChildSharedFolderId=$child.SharedFolderId;Error=$_.Exception.Message;Timestamp=(Get-Date).ToString('o')})
        }
    }
    Write-Progress -Activity "$($Label): resolve controlling parents" -Completed

    $approvalPath=Join-Path $ReportPath "$Label-ParentExternalRemovals-$stamp.csv"
    $exceptionPath=Join-Path $ReportPath "$Label-ParentRemediationExceptions-$stamp.csv"
    $failurePath=Join-Path $ReportPath "$Label-Failures-$stamp.csv"
    @($candidateMap.Values|Sort-Object ParentFolderName,PrincipalName)|Export-Csv $approvalPath -NoTypeInformation -Encoding utf8
    $exceptions|Export-Csv $exceptionPath -NoTypeInformation -Encoding utf8
    $failures|Export-Csv $failurePath -NoTypeInformation -Encoding utf8
    $summary=[pscustomobject]@{GeneratedAt=Get-Date;AuditComplete=($failures.Count-eq0);AuditFailures=$failures.Count;AllowlistedActiveMembers=$active.Count;InheritedChildRows=$children.Count;ParentRemovalApprovals=$candidateMap.Count;ParentRemediationExceptions=$exceptions.Count;ApprovalCsv=$approvalPath;ExceptionCsv=$exceptionPath;FailureCsv=$failurePath}
    $summary|Export-Csv (Join-Path $ReportPath "$Label-Summary-$stamp.csv") -NoTypeInformation -Encoding utf8;$summary|Format-List
    if($failures.Count){throw"Parent audit is incomplete. Review '$failurePath'."}
}

function Invoke-ParentRemove {
    $rows=@(Assert-Approval);Initialize-Ledger;$i=0
    foreach($row in $rows){
        $i++;$key=[string]$row.OperationKey;Write-Progress -Activity 'ParentRemoveExternal' -Status "$i/$($rows.Count): $key" -PercentComplete (($i/[Math]::Max($rows.Count,1))*100)
        if($script:SuccessKeys.Contains($key)){continue}
        try{
            if([string]::IsNullOrWhiteSpace($row.ParentOwnerTeamMemberId)){throw'Parent owner ID is missing.'}
            $selector=Get-MemberSelector $row
            [void](Invoke-DropboxApi -Uri 'https://api.dropboxapi.com/2/sharing/remove_folder_member' -SelectUser $row.ParentOwnerTeamMemberId `
                -Body @{shared_folder_id=$row.ParentSharedFolderId;member=$selector;leave_a_copy=$false})
            Add-LedgerRow $key 'Success' 'External principal removed from controlling parent.'
        }catch{
            if($_.Exception.Message-like'AUTH_FATAL:*'){throw}
            Add-LedgerRow $key 'Failed' $_.Exception.Message;Write-Warning "$key failed: $($_.Exception.Message)"
        }
    }
    Write-Progress -Activity 'ParentRemoveExternal' -Completed
}

Assert-Credentials
$active=@(Get-TeamMembers -IncludeRemoved $false|Where-Object{[string]$_.profile.status.'.tag'-eq'active'})
$admin=$active|Where-Object{$_.profile.email-eq$AdminEmail}|Select-Object -First 1;if(-not$admin){throw"Active admin '$AdminEmail' not found."}
$script:AdminMemberId=[string]$admin.profile.team_member_id

switch($Mode){
    'ParentAudit'{Invoke-ParentAudit 'Audit'}
    'ParentVerify'{Invoke-ParentAudit 'Verify'}
    'ParentRemove'{Invoke-ParentRemove}
    'Status'{
        $rows=@(if(Test-Path $LedgerPath){Import-Csv $LedgerPath})
        [pscustomobject]@{LedgerRows=$rows.Count;Success=@($rows|Where-Object Status-eq'Success').Count;Failed=@($rows|Where-Object Status-eq'Failed').Count;WorkPath=$WorkPath;LedgerPath=$LedgerPath}|Format-List
    }
}
