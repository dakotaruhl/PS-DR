<#
.SYNOPSIS
Discovers sharing links on a user's OneDrive that reference an old OneDrive URL,
extracts known recipients, and optionally recreates sharing against the user's
current OneDrive.

.DESCRIPTION
This script:
1. Connects to Microsoft Graph.
2. Recursively scans the target user's OneDrive.
3. Checks each DriveItem's permissions.
4. Finds sharing links that contain the old OneDrive URL.
5. Extracts users/groups from the permission object when available.
6. Optionally:
   - Recreates organization or anonymous links using createLink.
   - Re-shares specific people permissions using invite.
7. Exports a CSV report.

.NOTES
Recommended Graph permissions:
- Delegated testing: Files.ReadWrite.All, Sites.ReadWrite.All, User.Read.All
- App-only production: Files.ReadWrite.All or Sites.ReadWrite.All with admin consent

The account or app must be allowed to access the target user's OneDrive.
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$TargetUserPrincipalName,

    [Parameter(Mandatory = $true)]
    [string]$OldOneDriveUrl,

    [Parameter(Mandatory = $false)]
    [string]$ReportPath = ".\OneDrive-Reshare-Report.csv",

    [Parameter(Mandatory = $false)]
    [switch]$Execute,

    [Parameter(Mandatory = $false)]
    [switch]$SendInvitation,

    [Parameter(Mandatory = $false)]
    [string]$InvitationMessage = "This file or folder was reshared because the owner's OneDrive URL changed."
)

# ----------------------------
# Helper functions
# ----------------------------

function Invoke-GraphRequestWithRetry {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("GET", "POST", "PATCH", "DELETE")]
        [string]$Method,

        [Parameter(Mandatory = $true)]
        [string]$Uri,

        [Parameter(Mandatory = $false)]
        [object]$Body,

        [Parameter(Mandatory = $false)]
        [int]$MaxRetries = 6
    )

    $attempt = 0

    while ($true) {
        try {
            if ($PSBoundParameters.ContainsKey("Body")) {
                return Invoke-MgGraphRequest `
                    -Method $Method `
                    -Uri $Uri `
                    -Body ($Body | ConvertTo-Json -Depth 20) `
                    -ContentType "application/json" `
                    -OutputType PSObject
            }
            else {
                return Invoke-MgGraphRequest `
                    -Method $Method `
                    -Uri $Uri `
                    -OutputType PSObject
            }
        }
        catch {
            $attempt++

            $statusCode = $null
            if ($_.Exception.Response) {
                $statusCode = [int]$_.Exception.Response.StatusCode
            }

            if ($attempt -ge $MaxRetries -or ($statusCode -notin @(429, 500, 502, 503, 504))) {
                throw
            }

            $sleepSeconds = :Min(:Pow(2, $attempt), 60)
            Write-Warning "Graph request failed with status [$statusCode]. Retry $attempt of $MaxRetries in $sleepSeconds seconds. URI: $Uri"
            Start-Sleep -Seconds $sleepSeconds
        }
    }
}

function Get-GraphPagedItems {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri
    )

    $items = New-Object System.Collections.Generic.List[object]
    $nextUri = $Uri

    while ($nextUri) {
        $response = Invoke-GraphRequestWithRetry -Method GET -Uri $nextUri

        if ($response.value) {
            foreach ($item in $response.value) {
                $items.Add($item)
            }
        }

        $nextUri = $response.'@odata.nextLink'
    }

    return $items
}

function Get-DriveItemTree {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DriveId,

        [Parameter(Mandatory = $true)]
        [string]$ParentItemId
    )

    $encodedDriveId = :EscapeDataString($DriveId)
    $encodedParentItemId = :EscapeDataString($ParentItemId)

    $select = "id,name,webUrl,folder,file,package,parentReference,shared"
    $childrenUri = "/v1.0/drives/$encodedDriveId/items/$encodedParentItemId/children?`$select=$select&`$top=200"

    $children = Get-GraphPagedItems -Uri $childrenUri

    foreach ($child in $children) {
        $child

        $isFolder = $null -ne $child.folder
        $isPackage = $null -ne $child.package

        if ($isFolder -or $isPackage) {
            Get-DriveItemTree -DriveId $DriveId -ParentItemId $child.id
        }
    }
}

function Get-PermissionRecipients {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Permission
    )

    $recipients = New-Object System.Collections.Generic.List[string]

    # Modern Graph fields
    if ($Permission.grantedToV2) {
        foreach ($identityType in @("user", "group", "siteUser")) {
            if ($Permission.grantedToV2.$identityType) {
                $identity = $Permission.grantedToV2.$identityType
                if ($identity.email) { $recipients.Add($identity.email) }
                elseif ($identity.userPrincipalName) { $recipients.Add($identity.userPrincipalName) }
                elseif ($identity.loginName -and $identity.loginName -like "*@*") { $recipients.Add($identity.loginName) }
            }
        }
    }

    if ($Permission.grantedToIdentitiesV2) {
        foreach ($grantedIdentity in $Permission.grantedToIdentitiesV2) {
            foreach ($identityType in @("user", "group", "siteUser")) {
                if ($grantedIdentity.$identityType) {
                    $identity = $grantedIdentity.$identityType
                    if ($identity.email) { $recipients.Add($identity.email) }
                    elseif ($identity.userPrincipalName) { $recipients.Add($identity.userPrincipalName) }
                    elseif ($identity.loginName -and $identity.loginName -like "*@*") { $recipients.Add($identity.loginName) }
                }
            }
        }
    }

    # Older Graph fields
    if ($Permission.grantedTo) {
        foreach ($identityType in @("user", "group")) {
            if ($Permission.grantedTo.$identityType) {
                $identity = $Permission.grantedTo.$identityType
                if ($identity.email) { $recipients.Add($identity.email) }
            }
        }
    }

    if ($Permission.grantedToIdentities) {
        foreach ($grantedIdentity in $Permission.grantedToIdentities) {
            foreach ($identityType in @("user", "group")) {
                if ($grantedIdentity.$identityType) {
                    $identity = $grantedIdentity.$identityType
                    if ($identity.email) { $recipients.Add($identity.email) }
                }
            }
        }
    }

    # Invitation field sometimes contains the original recipient
    if ($Permission.invitation -and $Permission.invitation.email) {
        $recipients.Add($Permission.invitation.email)
    }

    return $recipients |
        Where-Object { $_ -and $_.Trim() -ne "" } |
        Sort-Object -Unique
}

function Convert-PermissionRoleToInviteRole {
    param(
        [Parameter(Mandatory = $false)]
        [object[]]$Roles
    )

    if ($Roles -contains "write") {
        return "write"
    }

    return "read"
}

function Convert-LinkTypeToCreateLinkType {
    param(
        [Parameter(Mandatory = $false)]
        [string]$LinkType
    )

    switch ($LinkType) {
        "edit" { return "edit" }
        "view" { return "view" }
        default { return "view" }
    }
}

# ----------------------------
# Connect to Graph
# ----------------------------
$Thumbprint = "C47B91EB62634CA61FA8146DDA83B8BF605C0962"
$ClientID   = "ea2ca49b-d0df-4774-b611-86cf9dc9629f"
$TenantID   = "0bdf0e1f-a359-4b5c-9b79-9357e35ff8c6"

$context = Get-MgContext -ErrorAction SilentlyContinue

if (-not $context) {
    Write-Host "Connecting to Microsoft Graph..."
    Connect-MgGraph `
    -ClientId $ClientID `
    -TenantId $TenantID `
    -CertificateThumbprint $Thumbprint
}

# ----------------------------
# Resolve target OneDrive
# ----------------------------

$escapedUser = [System.Uri]::EscapeDataString($TargetUserPrincipalName)

Write-Host "Resolving OneDrive for $TargetUserPrincipalName..."

$drive = Invoke-GraphRequestWithRetry -Method GET -Uri "/v1.0/users/$escapedUser/drive"
$driveId = $drive.id

if (-not $driveId) {
    throw "Could not resolve OneDrive drive ID for $TargetUserPrincipalName."
}

$root = Invoke-GraphRequestWithRetry -Method GET -Uri "/v1.0/drives/$([System.Uri]::EscapeDataString($driveId))/root"
$rootItemId = $root.id

if (-not $rootItemId) {
    throw "Could not resolve root item for OneDrive drive ID $driveId."
}

$oldUrlNormalized = $OldOneDriveUrl.TrimEnd("/")

Write-Host "Drive ID: $driveId"
Write-Host "Old OneDrive URL filter: $oldUrlNormalized"
Write-Host "Mode: $(if ($Execute) { "EXECUTE" } else { "REPORT ONLY" })"

# ----------------------------
# Scan items
# ----------------------------

$results = New-Object System.Collections.Generic.List[object]

# Include the root item and all descendants
$allItems = New-Object System.Collections.Generic.List[object]
$allItems.Add($root)

Write-Host "Enumerating OneDrive items..."
foreach ($item in Get-DriveItemTree -DriveId $driveId -ParentItemId $rootItemId) {
    $allItems.Add($item)
}

Write-Host "Found $($allItems.Count) total items. Checking permissions..."

$itemCounter = 0

foreach ($item in $allItems) {
    $itemCounter++

    if ($itemCounter % 100 -eq 0) {
        Write-Host "Checked $itemCounter of $($allItems.Count) items..."
    }

    $encodedDriveId = [System.Uri]::EscapeDataString($driveId)
    $encodedItemId = [System.Uri]::EscapeDataString($item.id)

    try {
        $permissionsResponse = Invoke-GraphRequestWithRetry `
            -Method GET `
            -Uri "/v1.0/drives/$encodedDriveId/items/$encodedItemId/permissions"

        $permissions = @($permissionsResponse.value)
    }
    catch {
        $results.Add([pscustomobject]@{
            ItemName        = $item.name
            ItemWebUrl      = $item.webUrl
            ItemId          = $item.id
            PermissionId    = $null
            LinkScope       = $null
            LinkType        = $null
            OldLinkWebUrl   = $null
            Recipients      = $null
            Action          = "PermissionReadFailed"
            NewLinkWebUrl   = $null
            Error           = $_.Exception.Message
        })

        continue
    }

    foreach ($permission in $permissions) {
        if (-not $permission.link -or -not $permission.link.webUrl) {
            continue
        }

        $oldLink = [string]$permission.link.webUrl

        if ($oldLink -notlike "$oldUrlNormalized*") {
            continue
        }

        $linkScope = [string]$permission.link.scope
        $linkType = [string]$permission.link.type
        $inviteRole = Convert-PermissionRoleToInviteRole -Roles $permission.roles
        $createLinkType = Convert-LinkTypeToCreateLinkType -LinkType $linkType
        $recipients = @(Get-PermissionRecipients -Permission $permission)

        $action = "ReportOnly"
        $newLinkWebUrl = $null
        $errorMessage = $null

        if ($Execute) {
            try {
                if ($linkScope -in @("anonymous", "organization")) {
                    $createLinkBody = @{
                        type  = $createLinkType
                        scope = $linkScope
                    }

                    $newPermission = Invoke-GraphRequestWithRetry `
                        -Method POST `
                        -Uri "/v1.0/drives/$encodedDriveId/items/$encodedItemId/createLink" `
                        -Body $createLinkBody

                    $newLinkWebUrl = $newPermission.link.webUrl
                    $action = "CreatedReplacementLink"
                }
                elseif ($linkScope -eq "users") {
                    if ($recipients.Count -eq 0) {
                        $action = "NeedsReviewNoRecipientsFound"
                    }
                    else {
                        $recipientPayload = @()

                        foreach ($recipient in $recipients) {
                            $recipientPayload += @{
                                email = $recipient
                            }
                        }

                        $inviteBody = @{
                            recipients                 = $recipientPayload
                            requireSignIn              = $true
                            sendInvitation             = [bool]$SendInvitation
                            roles                      = @($inviteRole)
                            message                    = $InvitationMessage
                            retainInheritedPermissions = $true
                        }

                        $inviteResponse = Invoke-GraphRequestWithRetry `
                            -Method POST `
                            -Uri "/v1.0/drives/$encodedDriveId/items/$encodedItemId/invite" `
                            -Body $inviteBody

                        $returnedLinks = @(
                            $inviteResponse.value |
                            Where-Object { $_.link -and $_.link.webUrl } |
                            ForEach-Object { $_.link.webUrl }
                        ) | Sort-Object -Unique

                        if ($returnedLinks.Count -gt 0) {
                            $newLinkWebUrl = ($returnedLinks -join "; ")
                        }
                        else {
                            $newLinkWebUrl = $item.webUrl
                        }

                        $action = if ($SendInvitation) {
                            "ResharedSpecificPeopleAndSentInvitation"
                        }
                        else {
                            "ResharedSpecificPeopleNoEmail"
                        }
                    }
                }
                else {
                    $action = "SkippedUnsupportedScope"
                }
            }
            catch {
                $action = "Failed"
                $errorMessage = $_.Exception.Message
            }
        }

        $results.Add([pscustomobject]@{
            ItemName        = $item.name
            ItemWebUrl      = $item.webUrl
            ItemId          = $item.id
            PermissionId    = $permission.id
            LinkScope       = $linkScope
            LinkType        = $linkType
            OldLinkWebUrl   = $oldLink
            Recipients      = ($recipients -join "; ")
            Action          = $action
            NewLinkWebUrl   = $newLinkWebUrl
            Error           = $errorMessage
        })
    }
}

# ----------------------------
# Export report
# ----------------------------

$results |
    Sort-Object ItemWebUrl, PermissionId |
    Export-Csv -Path $ReportPath -NoTypeInformation -Encoding UTF8

Write-Host ""
Write-Host "Done."
Write-Host "Report written to: $ReportPath"
Write-Host "Matching old links found: $($results.Count)"

if (-not $Execute) {
    Write-Host ""
    Write-Host "This was report-only. Re-run with -Execute to reshare/create replacement links."
}
