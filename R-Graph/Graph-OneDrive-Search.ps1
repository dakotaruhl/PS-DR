function Get-OneDriveItemsRecursive {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$DriveId,

        [Parameter()]
        [string]$ItemId,

        [Parameter()]
        [string]$CurrentPath = ""
    )

    if ($ItemId) {
        $Uri = "https://graph.microsoft.com/v1.0/drives/$DriveId/items/$ItemId/children"
    }
    else {
        $Uri = "https://graph.microsoft.com/v1.0/drives/$DriveId/root/children"
    }

    do {
        try {
            $Response = Invoke-MgGraphRequest -Method GET -Uri $Uri -ErrorAction Stop
        }
        catch {
            Write-Error "Unable to enumerate OneDrive path '$CurrentPath'. $($_.Exception.Message)"
            return
        }

        foreach ($Item in $Response.value) {
            $ItemPath = if ($CurrentPath) { "$CurrentPath/$($Item.name)" } else { $Item.name }

            if ($Item.file) {
                [PSCustomObject]@{
                    Name           = $Item.name
                    Path           = $ItemPath
                    Extension      = [System.IO.Path]::GetExtension($Item.name)
                    Size           = $Item.size
                    LastModified   = $Item.lastModifiedDateTime
                    LastModifiedBy = $Item.lastModifiedBy.user.displayName
                    WebUrl         = $Item.webUrl
                    DriveId        = $DriveId
                    ItemId         = $Item.id
                }
            }

            if ($Item.folder) {
                Write-Verbose "Enumerating folder: $ItemPath"
                Get-OneDriveItemsRecursive -DriveId $DriveId -ItemId $Item.id -CurrentPath $ItemPath
            }
        }

        $Uri = $Response.'@odata.nextLink'
    } while ($Uri)
}

function Find-OneDriveContent {
    [CmdletBinding(DefaultParameterSetName = "ByUser")]
    param (
        [Parameter(Mandatory, ParameterSetName = "ByUser")]
        [ValidateNotNullOrEmpty()]
        [string]$UserPrincipalName,

        [Parameter(Mandatory, ParameterSetName = "ByUrl")]
        [ValidateNotNullOrEmpty()]
        [string]$OneDriveUrl,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]]$Keywords,

        [Parameter()]
        [ValidateSet("Content", "FileName")]
        [string]$SearchMode = "Content",

        [Parameter()]
        [ValidateSet("Any", "All")]
        [string]$MatchMode = "Any",

        [Parameter()]
        [string]$TenantId,

        [Parameter()]
        [string]$ClientId,

        [Parameter()]
        [Alias("CertThumb")]
        [string]$CertificateThumbprint
    )

    $AppOnlyParameterCount = @(
        @($TenantId, $ClientId, $CertificateThumbprint) |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    ).Count

    if ($AppOnlyParameterCount -notin @(0, 3)) {
        throw "For certificate authentication, provide TenantId, ClientId, and CertificateThumbprint. Otherwise omit all three for delegated authentication."
    }

    if ($AppOnlyParameterCount -eq 3) {
        Write-Verbose "Using certificate-based app-only authentication."
        Connect-MgGraph -TenantId $TenantId -ClientId $ClientId -CertificateThumbprint $CertificateThumbprint -NoWelcome -ErrorAction Stop
    }
    else {
        Write-Verbose "Using delegated user authentication."
        Connect-MgGraph -Scopes "Files.Read.All" -NoWelcome -ErrorAction Stop
    }

    $Context = Get-MgContext
    Write-Verbose "Connected to Microsoft Graph"
    Write-Verbose "Account:  $($Context.Account)"
    Write-Verbose "Tenant:   $($Context.TenantId)"
    Write-Verbose "AuthType: $($Context.AuthType)"

    $DriveId = $null
    $RootItemId = $null
    $RootItem = $null

    switch ($PSCmdlet.ParameterSetName) {
        "ByUser" {
            Write-Verbose "Resolving OneDrive for user: $UserPrincipalName"
            $EncodedUser = [uri]::EscapeDataString($UserPrincipalName)
            $Drive = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/users/$EncodedUser/drive" -ErrorAction Stop
            $DriveId = $Drive.id
            Write-Verbose "OneDrive resolved successfully."
            Write-Verbose "Drive Name: $($Drive.name)"
            Write-Verbose "Drive ID:   $DriveId"
            Write-Verbose "Web URL:    $($Drive.webUrl)"
        }

        "ByUrl" {
            Write-Verbose "Resolving OneDrive sharing URL."
            $Bytes = [System.Text.Encoding]::UTF8.GetBytes($OneDriveUrl)
            $Base64 = [Convert]::ToBase64String($Bytes)
            $ShareId = "u!" + $Base64.TrimEnd('=').Replace('/', '_').Replace('+', '-')

            $RootItem = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/shares/$ShareId/driveItem" -ErrorAction Stop
            $DriveId = $RootItem.parentReference.driveId
            $RootItemId = $RootItem.id

            if (-not $RootItem.folder) {
                throw "The supplied OneDrive URL points to a file. Supply a folder sharing URL for recursive searches."
            }
        }
    }

    $CleanKeywords = @($Keywords | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
    if ($CleanKeywords.Count -eq 0) {
        throw "At least one non-empty keyword is required."
    }

    if ($SearchMode -eq "FileName") {
        Write-Verbose "Recursively enumerating OneDrive files."

        if ($PSCmdlet.ParameterSetName -eq "ByUrl") {
            $Files = @(Get-OneDriveItemsRecursive -DriveId $DriveId -ItemId $RootItemId -CurrentPath $RootItem.name)
        }
        else {
            $Files = @(Get-OneDriveItemsRecursive -DriveId $DriveId)
        }

        Write-Verbose "Finished enumerating $($Files.Count) files."

        foreach ($File in $Files) {
            $FileMatches = @(
                foreach ($Keyword in $CleanKeywords) {
                    if ($File.Name -like "*$Keyword*") { $Keyword }
                }
            )

            $ShouldReturn = if ($MatchMode -eq "All") {
                $FileMatches.Count -eq $CleanKeywords.Count
            }
            else {
                $FileMatches.Count -gt 0
            }

            if ($ShouldReturn) {
                [PSCustomObject]@{
                    Name            = $File.Name
                    Path            = $File.Path
                    Extension       = $File.Extension
                    MatchedKeywords = $FileMatches -join ", "
                    MatchCount      = $FileMatches.Count
                    LastModified    = $File.LastModified
                    LastModifiedBy  = $File.LastModifiedBy
                    Size            = $File.Size
                    WebUrl          = $File.WebUrl
                    DriveId         = $File.DriveId
                    ItemId          = $File.ItemId
                }
            }
        }
        return
    }

    # Content mode uses Microsoft's indexed DriveItem search.
    # It can match filename, metadata, and indexed file content.
    $AllResults = [System.Collections.Generic.List[object]]::new()

    foreach ($Keyword in $CleanKeywords) {
        Write-Verbose "Searching indexed content for keyword: $Keyword"
        $SafeKeyword = $Keyword.Replace("'", "''")

        if ($PSCmdlet.ParameterSetName -eq "ByUrl") {
            $Uri = "https://graph.microsoft.com/v1.0/drives/$DriveId/items/$RootItemId/search(q='$SafeKeyword')"
        }
        else {
            $Uri = "https://graph.microsoft.com/v1.0/drives/$DriveId/root/search(q='$SafeKeyword')"
        }

        do {
            try {
                $Response = Invoke-MgGraphRequest -Method GET -Uri $Uri -ErrorAction Stop
            }
            catch {
                Write-Error "Indexed search failed for '$Keyword'. $($_.Exception.Message)"
                break
            }

            foreach ($Result in $Response.value) {
                if ($Result.folder) { continue }

                $AllResults.Add([PSCustomObject]@{
                    Keyword        = $Keyword
                    Name           = $Result.name
                    Extension      = [System.IO.Path]::GetExtension($Result.name)
                    Size           = $Result.size
                    LastModified   = $Result.lastModifiedDateTime
                    LastModifiedBy = $Result.lastModifiedBy.user.displayName
                    WebUrl         = $Result.webUrl
                    DriveId        = $DriveId
                    ItemId         = $Result.id
                    ParentPath     = $Result.parentReference.path
                })
            }

            $Uri = $Response.'@odata.nextLink'
        } while ($Uri)
    }

    $GroupedResults = @(
        $AllResults |
            Group-Object ItemId |
            ForEach-Object {
                $ResultGroup = $_.Group
                $MatchedKeywords = @($ResultGroup.Keyword | Sort-Object -Unique)

                [PSCustomObject]@{
                    Name            = $ResultGroup[0].Name
                    Extension       = $ResultGroup[0].Extension
                    MatchedKeywords = $MatchedKeywords -join ", "
                    MatchCount      = $MatchedKeywords.Count
                    LastModified    = $ResultGroup[0].LastModified
                    LastModifiedBy  = $ResultGroup[0].LastModifiedBy
                    ParentPath      = $ResultGroup[0].ParentPath
                    Size            = $ResultGroup[0].Size
                    WebUrl          = $ResultGroup[0].WebUrl
                    DriveId         = $ResultGroup[0].DriveId
                    ItemId          = $ResultGroup[0].ItemId
                }
            }
    )

    if ($MatchMode -eq "All") {
        $GroupedResults = @($GroupedResults | Where-Object { $_.MatchCount -eq $CleanKeywords.Count })
    }

    $GroupedResults |
        Sort-Object @{ Expression = "MatchCount"; Descending = $true }, @{ Expression = "Name"; Descending = $false }
}

<#
EXAMPLES

# Recursive filename search, entire user's OneDrive
$Results = Find-OneDriveContent `
    -UserPrincipalName "mbutler@erock.com" `
    -Keywords @("preferences.edge") `
    -SearchMode FileName `
    -MatchMode All `
    -Verbose

$Results | Format-Table Name, Path, MatchedKeywords, LastModified, WebUrl -AutoSize

# Partial filename search
$Results = Find-OneDriveContent `
    -UserPrincipalName "mbutler@erock.com" `
    -Keywords @("PPE", "PP&E", "Policy") `
    -SearchMode FileName `
    -MatchMode Any `
    -Verbose

$Results | Export-Excel -Path ".\output\PartialFilenameSearchResults.xlsx" -AutoSize

# Indexed content search
$Results = Find-OneDriveContent `
    -UserPrincipalName "mbutler@erock.com" `
    -Keywords @("PPE", "PP&E", "Policy") `
    -SearchMode Content `
    -MatchMode All `
    -Verbose

$Results | Export-Excel -Path ".\output\IndexedContentSearchResults.xlsx" -AutoSize

# Certificate authentication: add all three parameters to any call
# -TenantId $TenantId -ClientId $ClientId -CertificateThumbprint $CertThumb
#>
