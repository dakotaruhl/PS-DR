<# 

## Set azcopypath *this is an EXE not a module*
# $azcopypath = "C:\Users\DakotaRuhl\AppData\Local\Microsoft\WinGet\Packages\Microsoft.Azure.AZCopy.10_Microsoft.Winget.Source_8wekyb3d8bbwe\azcopy_windows_amd64_10.34.1\azcopy.exe"
## Set your enviromnet variable to access token

###
# 1. Run discovery
.\R-Azure\Copy-DropboxToAzureStorage-v5.ps1 `
    -Mode Discover `
    -AdminEmail 'druhl@enchantedrock.com'

# 2. Create migration plan
.\R-Azure\Copy-DropboxToAzureStorage-v5.ps1 `
    -Mode Plan `
    -AdminEmail 'druhl@enchantedrock.com'

    # Review the migration plan
    DropboxMigrationV5\Reports\MigrationPlan-<timestamp>.csv

# 3. Test one direct shared folder
    $Plan = Import-Csv (
        Get-ChildItem ".\R-Azure\DropboxMigrationV5\Reports\MigrationPlan-*.csv" |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    ).FullName

    $Plan |
        Where-Object Type -eq 'shared_folder' |
        Select-Object -First 20 `
            Name,
            NamespaceId,
            CanonicalAzurePrefix |
        Format-Table -AutoSize

    # One small test namespace
    .\R-Azure\Copy-DropboxToAzureStorage-v5.ps1 `
        -Mode Migrate `
        -AdminEmail 'druhl@enchantedrock.com' `
        -StorageAccountName 'erockdropboxstorage' `
        -ContainerName 'dropbox-migration' `
        -AzCopyPath $azcopypath `
        -NamespaceId '7803651056' `
        -BatchSizeGB 2 `
        -BatchFileLimit 250 `
        -VerifyContentHash `
        -ResetFailedNamespaces

# 4. Inspect status
    .\R-Azure\Copy-DropboxToAzureStorage-v5.ps1 `
        -Mode Status

# Final production plan
    .\R-Azure\Copy-DropboxToAzureStorage-v5.ps1 `
        -Mode Plan `
        -AdminEmail 'druhl@enchantedrock.com'

# Start production
    $env:AZCOPY_AUTO_LOGIN_TYPE = "AZCLI"

    .\R-Azure\Copy-DropboxToAzureStorage-v5.ps1 `
        -Mode Migrate `
        -AdminEmail 'druhl@enchantedrock.com' `
        -StorageAccountName 'erockdropboxstorage' `
        -ContainerName 'dropbox-migration' `
        -AzCopyPath $azcopypath `
        -BatchSizeGB 25 `
        -BatchFileLimit 5000 `
        -VerifyContentHash `
        -SkipAzCopyLogin
    
# Monitor
    .\R-Azure\Copy-DropboxToAzureStorage-v5.ps1 -Mode Status
# Check failed namespaces
    $CheckpointPath = ".\R-Azure\DropboxMigrationV5\State\Checkpoints"

    $Failed = Get-ChildItem $CheckpointPath -Filter "*.json" |
        ForEach-Object {
            Get-Content $_.FullName -Raw |
                ConvertFrom-Json
        } |
        Where-Object Failed

    $Failed |
        Select-Object `
            NamespaceName,
            NamespaceType,
            PagesCompleted,
            FilesUploaded,
            @{N="GBUploaded"; E={
                [Math\]::Round($_.BytesUploaded / 1GB, 2)
            }},
            LastError |
        Format-Table -Wrap

# resume later 
    $env:AZCOPY_AUTO_LOGIN_TYPE = "AZCLI"
    .\R-Azure\Copy-DropboxToAzureStorage-v5.ps1 `
    -Mode Migrate `
    -AdminEmail 'druhl@enchantedrock.com' `
    -StorageAccountName 'erockdropboxstorage' `
    -ContainerName 'dropbox-migration' `
    -AzCopyPath $azcopypath `
    -BatchSizeGB 25 `
    -BatchFileLimit 5000 `
    -VerifyContentHash `
    -SkipAzCopyLogin `
    -ResetFailedNamespaces
#>

#requires -Version 7.2
<#
.SYNOPSIS
Canonical, resumable Dropbox Business to Azure Blob migration engine.

.DESCRIPTION
Discover and Plan are metadata-only. Migrate processes authoritative Dropbox namespaces
(team_folder, shared_folder, and team_member_folder) directly, in that order. Team member
roots are excluded by default because they mount shared/team content and would create an
ambiguous Azure layout. Files are globally deduplicated by Dropbox EntryId.

Each successful AzCopy batch gets an atomic committed-batch manifest. Namespace cursors
advance only after every file on a Dropbox page is uploaded or explicitly skipped. Re-run
the same command to resume.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Discover','Plan','Migrate','Status')]
    [string]$Mode,

    [string]$AdminEmail = 'druhl@enchantedrock.com',
    [ValidatePattern('^[a-z0-9]{3,24}$')]
    [string]$StorageAccountName,
    [ValidatePattern('^[a-z0-9-]{3,63}$')]
    [string]$ContainerName,
    [string]$AzCopyPath = 'azcopy',
    [string]$WorkPath = (Join-Path $PSScriptRoot 'DropboxMigrationV5'),
    [string]$StagingPath = (Join-Path $env:TEMP 'ERock-Dropbox-Migration-v5'),

    [ValidateRange(1,1024)]
    [int]$BatchSizeGB = 25,
    [ValidateRange(1,100000)]
    [int]$BatchFileLimit = 5000,
    [ValidateRange(0,100000)]
    [int]$MaxNamespaces = 0,
    [ValidateRange(1,20)]
    [int]$MaxRetry = 8,

    [string[]]$NamespaceId,
    [ValidateSet('team_folder','shared_folder','team_member_folder','team_member_root','app_folder')]
    [string[]]$NamespaceType,
    [switch]$IncludeMemberRoots,
    [switch]$IncludeAppFolders,
    [switch]$VerifyContentHash,
    [switch]$SkipAzCopyLogin,
    [switch]$KeepStagingFiles,
    [switch]$ResetFailedNamespaces
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$StatePath = Join-Path $WorkPath 'State'
$CheckpointPath = Join-Path $StatePath 'Checkpoints'
$CommittedBatchPath = Join-Path $StatePath 'CommittedBatches'
$ReportPath = Join-Path $WorkPath 'Reports'
$SkippedPath = Join-Path $StatePath 'SkippedEntries.csv'
$AggregateManifestPath = Join-Path $StatePath 'MigratedFiles.csv'
$script:StaticAccessToken = [Environment]::GetEnvironmentVariable('DROPBOX_ACCESS_TOKEN')
$script:RefreshToken = [Environment]::GetEnvironmentVariable('DROPBOX_REFRESH_TOKEN')
$script:AppKey = [Environment]::GetEnvironmentVariable('DROPBOX_APP_KEY')
$script:AppSecret = [Environment]::GetEnvironmentVariable('DROPBOX_APP_SECRET')
$script:OAuthAccessToken = $null
$script:OAuthExpiresAt = [datetime]::MinValue
$script:CompletedEntryIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)

New-Item -ItemType Directory -Path $CheckpointPath,$CommittedBatchPath,$ReportPath,$StagingPath -Force | Out-Null

function Get-OptionalProperty {
    param([object]$Object,[string]$Name)
    if ($null -ne $Object -and $Object.PSObject.Properties.Name -contains $Name) { return $Object.$Name }
    return $null
}

function Get-DropboxAccessToken {
    if (-not [string]::IsNullOrWhiteSpace($script:RefreshToken)) {
        if ([string]::IsNullOrWhiteSpace($script:AppKey) -or [string]::IsNullOrWhiteSpace($script:AppSecret)) {
            throw 'DROPBOX_REFRESH_TOKEN requires DROPBOX_APP_KEY and DROPBOX_APP_SECRET.'
        }
        if ($script:OAuthAccessToken -and $script:OAuthExpiresAt -gt (Get-Date).AddMinutes(5)) {
            return $script:OAuthAccessToken
        }
        $basic = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$($script:AppKey):$($script:AppSecret)"))
        $tokenResponse = Invoke-RestMethod -Method Post -Uri 'https://api.dropboxapi.com/oauth2/token' `
            -Headers @{ Authorization = "Basic $basic" } -ContentType 'application/x-www-form-urlencoded' `
            -Body @{ grant_type='refresh_token'; refresh_token=$script:RefreshToken }
        $script:OAuthAccessToken = [string]$tokenResponse.access_token
        $script:OAuthExpiresAt = (Get-Date).AddSeconds([int]$tokenResponse.expires_in)
        return $script:OAuthAccessToken
    }
    if ([string]::IsNullOrWhiteSpace($script:StaticAccessToken)) {
        throw 'Set DROPBOX_ACCESS_TOKEN, or set DROPBOX_REFRESH_TOKEN, DROPBOX_APP_KEY, and DROPBOX_APP_SECRET.'
    }
    return $script:StaticAccessToken.Trim()
}

function Get-HttpStatusCode {
    param([object]$ErrorRecord)
    try { return [int]$ErrorRecord.Exception.Response.StatusCode } catch { return 0 }
}

function Invoke-WithRetry {
    param([scriptblock]$Operation,[string]$Description)
    for ($attempt=1; $attempt -le $MaxRetry; $attempt++) {
        try { return & $Operation }
        catch {
            $status = Get-HttpStatusCode $_
            $retryable = $status -in @(0,408,429) -or $status -ge 500
            if (-not $retryable -or $attempt -eq $MaxRetry) { throw }
            $delay = 0
            try { $delay = [int]$_.Exception.Response.Headers.RetryAfter.Delta.TotalSeconds } catch {}
            if ($delay -le 0) { $delay = [int][Math]::Min(300,[Math]::Pow(2,$attempt)+(Get-Random -Minimum 0 -Maximum 4)) }
            Write-Warning "$Description failed (HTTP $status), attempt $attempt/$MaxRetry. Retrying in $delay seconds."
            Start-Sleep -Seconds $delay
        }
    }
}

function New-DropboxHeaders {
    param([string]$SelectorType,[string]$SelectorId,[string]$NamespaceIdValue)
    $headers = @{ Authorization = "Bearer $(Get-DropboxAccessToken)" }
    if ($SelectorType -eq 'User') { $headers['Dropbox-API-Select-User'] = $SelectorId }
    elseif ($SelectorType -eq 'Admin') { $headers['Dropbox-API-Select-Admin'] = $SelectorId }
    if ($NamespaceIdValue) {
        $headers['Dropbox-API-Path-Root'] = (@{ '.tag'='namespace_id'; namespace_id=$NamespaceIdValue } | ConvertTo-Json -Compress)
    }
    return $headers
}

function Invoke-DropboxJsonApi {
    param([string]$Uri,[AllowNull()][object]$Body,[string]$SelectorType,[string]$SelectorId,[string]$NamespaceIdValue)
    Invoke-WithRetry -Description $Uri -Operation {
        $headers = New-DropboxHeaders -SelectorType $SelectorType -SelectorId $SelectorId -NamespaceIdValue $NamespaceIdValue
        $json = if ($null -eq $Body) { 'null' } else { $Body | ConvertTo-Json -Depth 12 -Compress }
        Invoke-RestMethod -Method Post -Uri $Uri -Headers $headers -ContentType 'application/json' -Body $json
    }
}

function Get-TeamMembers {
    $response = Invoke-DropboxJsonApi -Uri 'https://api.dropboxapi.com/2/team/members/list_v2' -Body @{ include_removed=$false; limit=1000 }
    $items = [Collections.Generic.List[object]]::new()
    foreach ($item in $response.members) { $items.Add($item) }
    while ($response.has_more) {
        $response = Invoke-DropboxJsonApi -Uri 'https://api.dropboxapi.com/2/team/members/list/continue_v2' -Body @{ cursor=$response.cursor }
        foreach ($item in $response.members) { $items.Add($item) }
    }
    return $items
}

function Get-TeamNamespaces {
    $response = Invoke-DropboxJsonApi -Uri 'https://api.dropboxapi.com/2/team/namespaces/list' -Body @{ limit=1000 }
    $items = [Collections.Generic.List[object]]::new()
    foreach ($item in $response.namespaces) { $items.Add($item) }
    while ($response.has_more) {
        $response = Invoke-DropboxJsonApi -Uri 'https://api.dropboxapi.com/2/team/namespaces/list/continue' -Body @{ cursor=$response.cursor }
        foreach ($item in $response.namespaces) { $items.Add($item) }
    }
    return @($items | Sort-Object namespace_id -Unique)
}

function ConvertTo-SafeName {
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Value
    )

    $safe = if ([string]::IsNullOrWhiteSpace($Value)) {
        '_'
    }
    else {
        $Value
    }

    foreach ($character in [IO.Path]::GetInvalidFileNameChars()) {
        $safe = $safe.Replace([string]$character, '_')
    }

    $safe = $safe.Trim().TrimEnd('.')

    if ([string]::IsNullOrWhiteSpace($safe)) {
        return '_'
    }

    return $safe
}

function ConvertTo-SafeRelativePath {
    param([string]$PathDisplay,[string]$FallbackName)
    $candidate = if ($PathDisplay) { $PathDisplay.TrimStart('/') } else { $FallbackName }
    $segments = foreach ($segment in ($candidate -split '/')) { ConvertTo-SafeName $segment }
    return ($segments -join [IO.Path]::DirectorySeparatorChar)
}

function Get-NamespaceCategory {
    param([string]$Type)
    switch ($Type) {
        'team_folder'        { 'Team-Folders' }
        'shared_folder'      { 'Shared-Folders' }
        'team_member_folder' { 'Member-Content' }
        'team_member_root'   { 'Member-Roots' }
        'app_folder'         { 'App-Folders' }
        default              { 'Other' }
    }
}

function Get-NamespacePriority {
    param([string]$Type)
    switch ($Type) {
        'team_folder' { 10 }; 'shared_folder' { 20 }; 'team_member_folder' { 30 }
        'app_folder' { 40 }; 'team_member_root' { 90 }; default { 80 }
    }
}

function Get-CanonicalAzurePrefix {
    param([object]$Namespace)
    $type = [string]$Namespace.namespace_type.'.tag'
    return "$(Get-NamespaceCategory $type)/$([string]$Namespace.namespace_id)-$(ConvertTo-SafeName ([string]$Namespace.name))"
}

function Get-NamespaceSelector {
    param([object]$Namespace,[string]$AdminMemberId)
    $memberId = [string](Get-OptionalProperty $Namespace 'team_member_id')
    if ($memberId) { return [pscustomobject]@{ Type='User'; Id=$memberId } }
    return [pscustomobject]@{ Type='Admin'; Id=$AdminMemberId }
}

function Get-DropboxContentHash {
    param([string]$Path)
    $allBlockHashes = [Collections.Generic.List[byte]]::new()
    $stream = [IO.File]::OpenRead($Path)
    try {
        $buffer = [byte[]]::new(4MB)
        while (($read=$stream.Read($buffer,0,$buffer.Length)) -gt 0) {
            $sha=[Security.Cryptography.SHA256]::Create()
            try {
                $digest=$sha.ComputeHash($buffer,0,$read)
                foreach ($byte in $digest) { $allBlockHashes.Add($byte) }
            } finally { $sha.Dispose() }
        }
    } finally { $stream.Dispose() }
    $finalSha=[Security.Cryptography.SHA256]::Create()
    try { return ([Convert]::ToHexString($finalSha.ComputeHash($allBlockHashes.ToArray()))).ToLowerInvariant() }
    finally { $finalSha.Dispose() }
}

function Save-JsonAtomic {
    param([object]$Value,[string]$Path)
    $temp="$Path.tmp"
    $Value | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $temp -Encoding utf8
    Move-Item -LiteralPath $temp -Destination $Path -Force
}

function Get-CheckpointPath { param([string]$Id) return (Join-Path $CheckpointPath "$Id.json") }
function Get-Checkpoint {
    param([object]$Namespace)
    $path=Get-CheckpointPath ([string]$Namespace.namespace_id)
    if (Test-Path -LiteralPath $path) { return (Get-Content -LiteralPath $path -Raw | ConvertFrom-Json) }
    return [pscustomobject]@{
        NamespaceId=[string]$Namespace.namespace_id; NamespaceName=[string]$Namespace.name
        NamespaceType=[string]$Namespace.namespace_type.'.tag'; CanonicalAzurePrefix=Get-CanonicalAzurePrefix $Namespace
        Cursor=$null; Started=$false; Completed=$false; Failed=$false; PagesCompleted=0
        FilesUploaded=0; BytesUploaded=0; FilesSkipped=0; LastUpdated=(Get-Date).ToString('o'); LastError=$null
    }
}

function Initialize-CompletedEntryIds {
    $batchFiles=@(Get-ChildItem -LiteralPath $CommittedBatchPath -Filter '*.csv' -File -ErrorAction SilentlyContinue)
    foreach ($batchFile in $batchFiles) {
        foreach ($row in (Import-Csv -LiteralPath $batchFile.FullName)) {
            if ($row.EntryId) { [void]$script:CompletedEntryIds.Add([string]$row.EntryId) }
        }
    }
    if ($batchFiles.Count -eq 0 -and (Test-Path -LiteralPath $AggregateManifestPath)) {
        foreach ($row in (Import-Csv -LiteralPath $AggregateManifestPath)) {
            if ($row.EntryId) { [void]$script:CompletedEntryIds.Add([string]$row.EntryId) }
        }
    }
}

function Save-SkippedRows {
    param([object[]]$Rows)
    if ($Rows.Count -gt 0) { $Rows | Export-Csv -LiteralPath $SkippedPath -Append -NoTypeInformation -Encoding utf8 }
}

function Get-DropboxFile {
    param([object]$Entry,[object]$Selector,[string]$NamespaceIdValue,[string]$Destination)
    New-Item -ItemType Directory -Path (Split-Path -Parent $Destination) -Force | Out-Null
    Invoke-WithRetry -Description "Download $($Entry.path_display)" -Operation {
        $headers=New-DropboxHeaders -SelectorType $Selector.Type -SelectorId $Selector.Id -NamespaceIdValue $NamespaceIdValue
        $headers['Dropbox-API-Arg']=(@{ path=[string]$Entry.id } | ConvertTo-Json -Compress)
        Invoke-WebRequest -Method Post -Uri 'https://content.dropboxapi.com/2/files/download' -Headers $headers -OutFile $Destination
    } | Out-Null
}

function Invoke-AzCopyBatch {
    param(
        [Parameter(Mandatory)]
        [string]$BatchPath,

        [Parameter(Mandatory)]
        [string]$DestinationUrl
    )

    $azCopyOutput = @(
        & $script:AzCopyExecutable copy `
            (Join-Path $BatchPath '*') `
            $DestinationUrl `
            '--recursive=true' `
            '--overwrite=ifSourceNewer' `
            '--from-to=LocalBlob' 2>&1
    )

    $azCopyExitCode = $LASTEXITCODE

    foreach ($outputLine in $azCopyOutput) {
        Write-Host $outputLine
    }

    if ($azCopyExitCode -ne 0) {
        throw "AzCopy failed with exit code $azCopyExitCode for '$BatchPath'."
    }
}

function Invoke-MigrationBatch {
    param([object[]]$Files,[object]$Namespace,[object]$Selector)
    if ($Files.Count -eq 0) { return [pscustomobject]@{ Files=0; Bytes=0 } }
    $batchId=[guid]::NewGuid().ToString('N')
    $batchPath=Join-Path $StagingPath $batchId
    New-Item -ItemType Directory -Path $batchPath -Force | Out-Null
    $rows=[Collections.Generic.List[object]]::new()
    $committed=$false
    try {
        for ($i=0; $i -lt $Files.Count; $i++) {
            $file=$Files[$i]
            $relative=ConvertTo-SafeRelativePath -PathDisplay ([string]$file.path_display) -FallbackName ([string]$file.name)
            $local=Join-Path $batchPath $relative
            Write-Progress -Activity "Downloading batch $batchId" -Status "$($i+1)/$($Files.Count): $($file.path_display)" -PercentComplete ((($i+1)/$Files.Count)*100)
            Get-DropboxFile -Entry $file -Selector $Selector -NamespaceIdValue ([string]$Namespace.namespace_id) -Destination $local
            $actualSize=(Get-Item -LiteralPath $local).Length
            if ($actualSize -ne [int64]$file.size) { throw "Size mismatch for '$($file.path_display)': expected $($file.size), got $actualSize." }
            $expectedHash=[string](Get-OptionalProperty $file 'content_hash')
            if ($VerifyContentHash -and $expectedHash) {
                $actualHash=Get-DropboxContentHash $local
                if ($actualHash -ne $expectedHash) { throw "Dropbox content hash mismatch for '$($file.path_display)'." }
            }
            $prefix=Get-CanonicalAzurePrefix $Namespace
            $rows.Add([pscustomobject]@{
                MigratedAt=(Get-Date).ToString('o'); BatchId=$batchId
                NamespaceId=$Namespace.namespace_id; NamespaceName=$Namespace.name; NamespaceType=$Namespace.namespace_type.'.tag'
                EntryId=$file.id; DropboxPath=$file.path_display; RelativePath=$relative
                Size=[int64]$file.size; ContentHash=$expectedHash; AzurePrefix=$prefix; Verification=$(if($VerifyContentHash){'Size+DropboxContentHash'}else{'Size'})
            })
        }
        Write-Progress -Activity "Downloading batch $batchId" -Completed
        $prefix=Get-CanonicalAzurePrefix $Namespace
        $destination="https://$StorageAccountName.blob.core.windows.net/$ContainerName/$prefix"
        Invoke-AzCopyBatch -BatchPath $batchPath -DestinationUrl $destination

        $committedPath=Join-Path $CommittedBatchPath "$batchId.csv"
        $temp="$committedPath.tmp"
        $rows | Export-Csv -LiteralPath $temp -NoTypeInformation -Encoding utf8
        Move-Item -LiteralPath $temp -Destination $committedPath -Force
        $rows | Export-Csv -LiteralPath $AggregateManifestPath -Append -NoTypeInformation -Encoding utf8
        foreach ($row in $rows) { [void]$script:CompletedEntryIds.Add([string]$row.EntryId) }
        $committed=$true
        return [pscustomobject]@{ Files=$rows.Count; Bytes=[int64](($rows | Measure-Object Size -Sum).Sum ?? 0) }
    }
    finally {
        if ($committed -and -not $KeepStagingFiles -and (Test-Path -LiteralPath $batchPath)) { Remove-Item -LiteralPath $batchPath -Recurse -Force }
    }
}

function Get-PageEntries {
    param([object[]]$Entries,[object]$Namespace,[object]$Selector)
    $files=@($Entries | Where-Object { $_.'.tag' -eq 'file' })
    $pending=[Collections.Generic.List[object]]::new()
    $pendingBytes=[int64]0; $uploadedFiles=0; $uploadedBytes=[int64]0; $skipped=0
    $skipRows=[Collections.Generic.List[object]]::new()

    foreach ($file in $files) {
        $entryId=[string]$file.id
        $downloadable=Get-OptionalProperty $file 'is_downloadable'
        if ($script:CompletedEntryIds.Contains($entryId)) {
            $skipRows.Add([pscustomobject]@{ CheckedAt=(Get-Date).ToString('o'); NamespaceId=$Namespace.namespace_id; NamespaceName=$Namespace.name; EntryId=$entryId; DropboxPath=$file.path_display; Reason='Already migrated by EntryId' })
            $skipped++; continue
        }
        if ($downloadable -eq $false) {
            $skipRows.Add([pscustomobject]@{ CheckedAt=(Get-Date).ToString('o'); NamespaceId=$Namespace.namespace_id; NamespaceName=$Namespace.name; EntryId=$entryId; DropboxPath=$file.path_display; Reason='Not downloadable' })
            $skipped++; continue
        }
        $wouldExceed=$pending.Count -gt 0 -and (($pendingBytes+[int64]$file.size) -gt ([int64]$BatchSizeGB*1GB) -or $pending.Count -ge $BatchFileLimit)
        if ($wouldExceed) {
            $result = Invoke-MigrationBatch `
                -Files $pending.ToArray() `
                -Namespace $Namespace `
                -Selector $Selector

            $uploadedFiles += [int64]$result.Files
            $uploadedBytes += [int64]$result.Bytes

            $pending.Clear()
            $pendingBytes = 0
        }
        $pending.Add($file); $pendingBytes+=[int64]$file.size
    }
    if ($pending.Count -gt 0) {
        $result=Invoke-MigrationBatch -Files $pending.ToArray() -Namespace $Namespace -Selector $Selector
        $uploadedFiles+=$result.Files; $uploadedBytes+=$result.Bytes
    }
    Save-SkippedRows -Rows $skipRows.ToArray()
    return [pscustomobject]@{ Files=$uploadedFiles; Bytes=$uploadedBytes; Skipped=$skipped }
}

if ($Mode -eq 'Status') {
    $checkpoints=@(Get-ChildItem -LiteralPath $CheckpointPath -Filter '*.json' -File -ErrorAction SilentlyContinue | ForEach-Object { Get-Content $_.FullName -Raw | ConvertFrom-Json })
    $batchFiles=@(Get-ChildItem -LiteralPath $CommittedBatchPath -Filter '*.csv' -File -ErrorAction SilentlyContinue)
    $committedRows = @(
        foreach ($batchFile in $batchFiles) {
            Import-Csv -LiteralPath $batchFile.FullName
        }
    )

    $committedMeasure = $committedRows |
        Measure-Object -Property Size -Sum

    $committedBytes = if (
        $null -ne $committedMeasure -and
        $null -ne $committedMeasure.Sum
    ) {
        [int64]$committedMeasure.Sum
    }
    else {
        [int64]0
    }
    [pscustomobject]@{
        NamespacesTracked=$checkpoints.Count; Completed=@($checkpoints|Where-Object Completed).Count
        Failed=@($checkpoints|Where-Object Failed).Count; InProgress=@($checkpoints|Where-Object{-not $_.Completed -and -not $_.Failed}).Count
        CommittedBatches=$batchFiles.Count; FilesUploaded=@($committedRows).Count
        BytesUploaded=$committedBytes; TBUploaded=[Math]::Round($committedBytes/1TB,3); WorkPath=$WorkPath
    } | Format-List
    return
}

Write-Host 'Discovering Dropbox Business members and namespaces...'
$members=@(Get-TeamMembers); $namespaces=@(Get-TeamNamespaces)
$admin=$members | Where-Object { $_.profile.email -eq $AdminEmail } | Select-Object -First 1
if (-not $admin) { throw "Admin '$AdminEmail' was not returned by Dropbox." }
$adminMemberId=[string]$admin.profile.team_member_id

$namespaceReport = foreach ($ns in $namespaces) {

    $type = [string]$ns.namespace_type.'.tag'

    [pscustomobject]@{
        Name = if ([string]::IsNullOrWhiteSpace([string]$ns.name)) {
            "_unnamed_$($ns.namespace_id)"
        }
        else {
            [string]$ns.name
        }

        NamespaceId = $ns.namespace_id
        Type = $type
        Category = Get-NamespaceCategory $type
        Priority = Get-NamespacePriority $type
        CanonicalAzurePrefix = Get-CanonicalAzurePrefix $ns
        TeamMemberId = Get-OptionalProperty $ns 'team_member_id'

        DefaultMigrationSource = (
            $type -in @(
                'team_folder',
                'shared_folder',
                'team_member_folder'
            )
        )
    }
}
$stamp=Get-Date -Format 'yyyyMMdd-HHmmss'
$discoveryPath=Join-Path $ReportPath "Discovery-$stamp.csv"
$namespaceReport | Export-Csv -LiteralPath $discoveryPath -NoTypeInformation -Encoding utf8
Write-Host "Team members: $($members.Count)"; Write-Host "Unique namespaces: $($namespaces.Count)"
$namespaces | Group-Object { $_.namespace_type.'.tag' } | Sort-Object Count -Descending | Format-Table Count,Name -AutoSize
Write-Host "Discovery report: $discoveryPath"
if ($Mode -eq 'Discover') { return }

$plan = @(
    $namespaceReport |
        Where-Object DefaultMigrationSource |
        Sort-Object `
            @{ Expression = { [int]$_.Priority } },
            @{ Expression = {
                if ([string]::IsNullOrWhiteSpace([string]$_.Name)) {
                    ''
                }
                else {
                    [string]$_.Name
                }
            } }
)
$planPath=Join-Path $ReportPath "MigrationPlan-$stamp.csv"
$plan | Export-Csv -LiteralPath $planPath -NoTypeInformation -Encoding utf8
if ($Mode -eq 'Plan') {
    Write-Host "Planned authoritative namespaces: $($plan.Count)"
    $plan | Group-Object Type | Sort-Object Name | Format-Table Count,Name -AutoSize
    Write-Host "Migration plan: $planPath"; return
}

if (-not $StorageAccountName -or -not $ContainerName) { throw 'Migrate requires -StorageAccountName and -ContainerName.' }
$script:AzCopyExecutable=(Get-Command $AzCopyPath -ErrorAction Stop).Source
if (-not $SkipAzCopyLogin) { & $script:AzCopyExecutable login; if ($LASTEXITCODE -ne 0) { throw "AzCopy login failed: $LASTEXITCODE" } }

if ($NamespaceId) { $selected=@($namespaces|Where-Object{$NamespaceId -contains [string]$_.namespace_id}) }
elseif ($NamespaceType) { $selected=@($namespaces|Where-Object{$NamespaceType -contains $_.namespace_type.'.tag'}) }
else { $selected=@($namespaces|Where-Object{$_.namespace_type.'.tag' -in @('team_folder','shared_folder','team_member_folder')}) }
if (-not $IncludeMemberRoots) { $selected=@($selected|Where-Object{$_.namespace_type.'.tag' -ne 'team_member_root'}) }
if (-not $IncludeAppFolders) { $selected=@($selected|Where-Object{$_.namespace_type.'.tag' -ne 'app_folder'}) }
$selected = @(
    $selected |
        Sort-Object `
            @{
                Expression = {
                    Get-NamespacePriority `
                        ([string]$_.namespace_type.'.tag')
                }
            },
            @{
                Expression = {
                    if (
                        $_.PSObject.Properties.Name -contains 'name' -and
                        -not [string]::IsNullOrWhiteSpace([string]$_.name)
                    ) {
                        [string]$_.name
                    }
                    else {
                        ''
                    }
                }
            }
)
if($MaxNamespaces -gt 0){$selected=@($selected|Select-Object -First $MaxNamespaces)}
if($selected.Count -eq 0){throw 'No namespaces matched the migration filters.'}

Initialize-CompletedEntryIds
Write-Host "Selected namespaces: $($selected.Count)"; Write-Host "Previously committed unique file IDs: $($script:CompletedEntryIds.Count)"

for($index=0;$index -lt $selected.Count;$index++){
    $ns=$selected[$index]; $checkpoint=Get-Checkpoint $ns
    if($checkpoint.Completed){Write-Host "[$($index+1)/$($selected.Count)] Completed, skipping: $($ns.name)";continue}
    if($checkpoint.Failed -and -not $ResetFailedNamespaces){Write-Warning "Failed namespace skipped: $($ns.name). Use -ResetFailedNamespaces.";continue}
    if($ResetFailedNamespaces){$checkpoint.Failed=$false;$checkpoint.LastError=$null}
    $selector=Get-NamespaceSelector -Namespace $ns -AdminMemberId $adminMemberId
    Write-Host "[$($index+1)/$($selected.Count)] Migrating $($ns.name) [$($ns.namespace_type.'.tag')] -> $(Get-CanonicalAzurePrefix $ns)"
    try{
        if(-not $checkpoint.Started){
            $response=Invoke-DropboxJsonApi -Uri 'https://api.dropboxapi.com/2/files/list_folder' -SelectorType $selector.Type -SelectorId $selector.Id -NamespaceIdValue ([string]$ns.namespace_id) -Body @{path='';recursive=$true;include_deleted=$false;include_non_downloadable_files=$true;limit=2000}
            $checkpoint.Started=$true
        }else{
            $response=Invoke-DropboxJsonApi -Uri 'https://api.dropboxapi.com/2/files/list_folder/continue' -SelectorType $selector.Type -SelectorId $selector.Id -NamespaceIdValue ([string]$ns.namespace_id) -Body @{cursor=$checkpoint.Cursor}
        }
        while($true){
            $result=Get-PageEntries -Entries @($response.entries) -Namespace $ns -Selector $selector
            $checkpoint.PagesCompleted=[int]$checkpoint.PagesCompleted+1; $checkpoint.FilesUploaded=[int64]$checkpoint.FilesUploaded+$result.Files
            $checkpoint.BytesUploaded=[int64]$checkpoint.BytesUploaded+$result.Bytes; $checkpoint.FilesSkipped=[int64]$checkpoint.FilesSkipped+$result.Skipped
            $checkpoint.Cursor=[string]$response.cursor; $checkpoint.LastUpdated=(Get-Date).ToString('o'); $checkpoint.Failed=$false; $checkpoint.LastError=$null
            if(-not $response.has_more){$checkpoint.Completed=$true}
            Save-JsonAtomic -Value $checkpoint -Path (Get-CheckpointPath ([string]$ns.namespace_id))
            Write-Host "  Page $($checkpoint.PagesCompleted): uploaded $($checkpoint.FilesUploaded), skipped $($checkpoint.FilesSkipped), $([Math]::Round($checkpoint.BytesUploaded/1GB,2)) GB."
            if($checkpoint.Completed){break}
            $response=Invoke-DropboxJsonApi -Uri 'https://api.dropboxapi.com/2/files/list_folder/continue' -SelectorType $selector.Type -SelectorId $selector.Id -NamespaceIdValue ([string]$ns.namespace_id) -Body @{cursor=$checkpoint.Cursor}
        }
    }catch{
        if ([int]$checkpoint.PagesCompleted -eq 0 -and [string]::IsNullOrWhiteSpace([string]$checkpoint.Cursor)) { $checkpoint.Started=$false }
        $checkpoint.Failed=$true;$checkpoint.LastError=$_.Exception.Message;$checkpoint.LastUpdated=(Get-Date).ToString('o')
        Save-JsonAtomic -Value $checkpoint -Path (Get-CheckpointPath ([string]$ns.namespace_id))
        Write-Error "Namespace '$($ns.name)' failed and was checkpointed: $($_.Exception.Message)" -ErrorAction Continue
    }
}
Write-Host 'Migration pass finished. Re-run the same command to resume, or use -Mode Status.'


