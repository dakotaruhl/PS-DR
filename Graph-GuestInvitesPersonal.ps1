########################
## Check Dependencies ##
########################

$RequiredModules = @(
    "Microsoft.Graph.Authentication"
    "Microsoft.Graph.Users"
    "Microsoft.Graph.Identity.SignIns"
    "Microsoft.Graph.Sites"
)

foreach ($module in $RequiredModules) {
    if (-not (Get-Module -ListAvailable -Name $module)) {
        Install-Module $module -Scope CurrentUser -Force
    }

    Import-Module $module -Force
}

###################
## Configuration ##
###################

$TenantId = "0bdf0e1f-a359-4b5c-9b79-9357e35ff8c6"
$SiteId   = "0928e022-420f-4bc6-a606-c62799696eb1"
$ListName = "External sharing request responses"

$GuestFieldName    = "Enter external guest email(s)"
$SponsorFieldName  = "Email"
$CompleteFieldName = "Complete"

function Get-GraphSiteListItems {
    param (
        [Parameter(Mandatory)]
        [string]$SiteId,

        [Parameter(Mandatory)]
        [string]$ListName,

        [Parameter(Mandatory)]
        [string]$CompleteFieldName
    )

    try {
        $list = Get-MgSiteList -SiteId $SiteId -ErrorAction Stop |
            Where-Object { $_.DisplayName -eq $ListName } |
            Select-Object -First 1

        if (-not $list) {
            throw "List '$ListName' not found in site '$SiteId'."
        }

        $items = Get-MgSiteListItem `
            -SiteId $SiteId `
            -ListId $list.Id `
            -ExpandProperty Fields `
            -All `
            -ErrorAction Stop

        $pendingItems = $items |
            Where-Object {
                $completeValue = $_.Fields.AdditionalProperties[$CompleteFieldName]
                $completeValue -ne $true
            } |
            Sort-Object CreatedDateTime -Descending

        return [PSCustomObject]@{
            ListId = $list.Id
            Items  = $pendingItems
        }
    }
    catch {
        Write-Warning "Error retrieving list items: $($_.Exception.Message)"

        return [PSCustomObject]@{
            ListId = $null
            Items  = @()
        }
    }
}

function New-InviteMessageInfo {
    $messageInfo = New-Object Microsoft.Graph.PowerShell.Models.MicrosoftGraphInvitedUserMessageInfo

    $messageInfo.CustomizedMessageBody = @"
Hello,

This is the IT dept at ERock. Your guest account has been created for access to content in our organization, pending your activation.

Please click the `"Accept Invitation`" link below and follow the prompts to activate the guest account and set up multi-factor authentication. A corresponding file share link will be sent to you following this email.

If you have any questions, please feel free to send us an email at itdepartment@erock.com.
"@

    return $messageInfo
}

function ConvertTo-GuestRecord {
    param(
        [Parameter(Mandatory)]
        [string]$InputString
    )

    $records = @()

    if ([string]::IsNullOrWhiteSpace($InputString)) {
        return @()
    }

    # Finds email addresses anywhere in the input
    $emailPattern = '(?i)[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}'
    $emailMatches = [regex]::Matches($InputString, $emailPattern)

    foreach ($emailMatch in $emailMatches) {
        $email = $emailMatch.Value.Trim()
        $displayName = $null

        $emailStart = $emailMatch.Index
        $emailEnd   = $emailMatch.Index + $emailMatch.Length

        $beforeEmail = $InputString.Substring(0, $emailStart)
        $afterEmail  = $InputString.Substring($emailEnd)

        # Format:
        # magee.amber@heb.com (Amber Magee)
        if ($afterEmail -match '^\s*\((?<Name>[^)]+)\)') {
            $displayName = $matches.Name.Trim()
        }

        # Format:
        # "Jason Bickel" <Jason.Bickel@strategyeng.com>
        elseif ($beforeEmail -match '"(?<Name>[^"]+)"\s*<\s*$') {
            $displayName = $matches.Name.Trim()
        }

        # Format:
        # Galle, Nicholas D. <gallend@bv.com>
        # Murtagh \ Edward <emurtagh@nisource.com>
        elseif ($beforeEmail -match '(?<Name>[^;`r`n<>]+?)\s*<\s*$') {
            $displayName = $matches.Name.Trim()
        }

        # Format:
        # Alderman, Chris A AAlderman@mcguirewoods.com
        else {
            $lastSemicolon = $beforeEmail.LastIndexOf(';')
            $lastNewLine   = $beforeEmail.LastIndexOf("`n")
            $boundary      = [Math]::Max($lastSemicolon, $lastNewLine)

            if ($boundary -ge 0) {
                $candidate = $beforeEmail.Substring($boundary + 1)
            }
            else {
                $candidate = $beforeEmail
            }

            $displayName = $candidate.Trim()
        }

        $displayName = $displayName `
            -replace '\\', ' ' `
            -replace '[<>"]', '' `
            -replace '\s+', ' '

        $displayName = $displayName.Trim(" ", ",", ";")

        # Fallback to email-derived name if we still don't have one
        if ([string]::IsNullOrWhiteSpace($displayName)) {

            $displayName = ($email -split '@')[0]

            $displayName = $displayName `
                -replace '[._\-]+', ' ' `
                -replace '\s+', ' '

            $displayName = (Get-Culture).TextInfo.ToTitleCase(
                $displayName.ToLower()
            )
        }

        $displayName = $displayName `
            -replace '\\', ' ' `
            -replace '[<>"]', '' `
            -replace '\s+', ' '

        $displayName = $displayName.Trim(" ", ",", ";")

        $records += [PSCustomObject]@{
            DisplayName = $displayName
            Email       = $email.ToLower()
        }
    }

    return $records | Sort-Object Email -Unique
}

function New-GuestInvitesFromListItem {
    param (
        [Parameter(Mandatory)]
        $ListItem,

        [Parameter(Mandatory)]
        $MessageInfo,

        [Parameter(Mandatory)]
        [string]$TenantId,

        [Parameter(Mandatory)]
        [string]$GuestFieldName,

        [Parameter(Mandatory)]
        [string]$SponsorFieldName
    )

    $results = @()

    $rawGuestInput = $ListItem.Fields.AdditionalProperties[$GuestFieldName]
    $sponsorEmail  = $ListItem.Fields.AdditionalProperties[$SponsorFieldName]

    if ([string]::isNullOrWhiteSpace($rawGuestInput)) {
        throw "Guest field '$GuestFieldName' is blank for list item $($ListItem.Id)."
    }

    if ([string]::isNullOrWhiteSpace($sponsorEmail)) {
        throw "Sponsor field '$SponsorFieldName' is blank for list item $($ListItem.Id)."
    }

    $sponsorEmail = $sponsorEmail.Trim()

    $sponsor = Get-MgUser `
        -UserId $sponsorEmail `
        -Property Id,DisplayName,UserPrincipalName `
        -ErrorAction Stop

    $guests = ConvertTo-GuestRecord -InputString $rawGuestInput

    foreach ($guest in $guests) {

        $inviteEmail = $guest.Email
        $displayName = $guest.DisplayName

        try {

            $escapedInviteEmail = $inviteEmail.Replace("'", "''")

            $existingGuest = Get-MgUser `
                -Filter "userType eq 'Guest' and mail eq '$escapedInviteEmail'" `
                -Property Id,DisplayName,UserPrincipalName,Mail `
                -ErrorAction Stop

            if ($existingGuest) {

                Write-Warning "Guest already exists: $inviteEmail"

                $results += [PSCustomObject]@{
                    Email       = $inviteEmail
                    DisplayName = $displayName
                    Status      = "Skipped"
                    Reason      = "Guest already exists"
                    GuestId     = $existingGuest.Id
                    GuestUPN    = $existingGuest.UserPrincipalName
                    Sponsor     = $sponsor.UserPrincipalName
                    ListItemId  = $ListItem.Id
                }

                continue
            }

            $invite = New-MgInvitation `
                -InvitedUserEmailAddress $inviteEmail `
                -InvitedUserDisplayName $displayName `
                -InviteRedirectUrl "https://myapplications.microsoft.com/?tenantid=$TenantId" `
                -InvitedUserMessageInfo $MessageInfo `
                -InvitedUserSponsors @($sponsor) `
                -SendInvitationMessage `
                -ErrorAction Stop

            Write-Host "SUCCESS: $displayName <$inviteEmail>" -ForegroundColor Green

            $results += [PSCustomObject]@{
                Email       = $inviteEmail
                DisplayName = $displayName
                Status      = "Invited"
                Reason      = "Invitation sent"
                GuestId     = $invite.InvitedUser.Id
                GuestUPN    = $invite.InvitedUser.UserPrincipalName
                Sponsor     = $sponsor.UserPrincipalName
                ListItemId  = $ListItem.Id
            }
        }
        catch {

            Write-Warning "FAILED: $displayName <$inviteEmail> - $($_.Exception.Message)"

            $results += [PSCustomObject]@{
                Email       = $inviteEmail
                DisplayName = $displayName
                Status      = "Failed"
                Reason      = $_.Exception.Message
                GuestId     = $null
                GuestUPN    = $null
                Sponsor     = $sponsorEmail
                ListItemId  = $ListItem.Id
            }
        }
    }

    return $results
}


## Connection Check ##
# Connect to Microsoft Graph using the personal credentials, if not already connected with these scopes.
$RequiredScopes = @(
    "User.Invite.All"
    "User.Read.All"
    "Sites.Read.All"
)

$ctx = Get-MgContext
$NeedReconnect = $false

if (-not $ctx) {
    $NeedReconnect = $true
}
else {
    foreach ($scope in $RequiredScopes) {
        if ($scope -notin $ctx.Scopes) {
            $NeedReconnect = $true
            break
        }
    }
}
if ($NeedReconnect) {
    Disconnect-MgGraph -ErrorAction SilentlyContinue

    Connect-MgGraph `
        -TenantId $TenantId `
        -Scopes $RequiredScopes `
        -NoWelcome
}

##########
## Main ##
##########

$listResult = Get-GraphSiteListItems `
    -SiteId $SiteId `
    -ListName $ListName `
    -CompleteFieldName $CompleteFieldName

$pendingItems = @($listResult.Items)


if (-not $pendingItems -or $pendingItems.Count -eq 0) {
    Write-Host "No pending guest requests found." -ForegroundColor Yellow
    return
}

$FieldMap = @{
    SponsorEmail = "field_3"
    GuestEmails  = "field_6"
    Justification = "field_7"
}

$menuItems = @()
$counter = 1

foreach ($item in @($pendingItems)) {

    $menuItems += [PSCustomObject]@{
        Number      = $counter++
        GuestEmail  = $item.Fields.AdditionalProperties[$FieldMap.GuestEmails]
        Sponsor     = $item.Fields.AdditionalProperties[$FieldMap.SponsorEmail]
        RequestDate = $item.CreatedDateTime
        ListItem    = $item
    }
}

Write-Host ""
Write-Host "Pending Guest Invitations" -ForegroundColor Cyan
Write-Host ""

$menuItems |
    Select-Object Number, GuestEmail, Sponsor, RequestDate |
    Format-Table -AutoSize

$selection = Read-Host "Enter invitation number(s) separated by commas"

try {
    $numbers = $selection.Split(',') |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ } |
        ForEach-Object { [int]$_ }
}
catch {
    throw "Invalid selection. Enter one or more numbers separated by commas. Example: 1,3,5"
}

$selectedItems = $menuItems |
    Where-Object { $_.Number -in $numbers }

if (-not $selectedItems -or $selectedItems.Count -eq 0) {
    throw "No valid invitation rows selected."
}

$messageInfo = New-InviteMessageInfo

$previewHasErrors = $false

foreach ($selected in $selectedItems) {
    $rawGuestInput = $selected.ListItem.Fields.AdditionalProperties[$FieldMap.GuestEmails]

    $parsedGuests = ConvertTo-GuestRecord `
        -InputString $rawGuestInput

    Write-Host ""
    Write-Host "Request $($selected.Number)" -ForegroundColor Cyan

    if (-not $parsedGuests -or $parsedGuests.Count -eq 0) {
        Write-Warning "No guests could be parsed from this request."
        $previewHasErrors = $true
        continue
    }

    $parsedGuests | Format-Table DisplayName, Email -AutoSize
}

if ($previewHasErrors) {
    throw "One or more selected requests could not be parsed. No invitations were sent."
}

$confirm = Read-Host "Proceed with invitations? (Y/N)"

if ($confirm -ne 'Y') {
    Write-Host "Invitation process aborted." -ForegroundColor Yellow
    return
}
else {
    Write-Host "Proceeding with invitations..." -ForegroundColor Green
    $results = foreach ($selected in $selectedItems) {
    New-GuestInvitesFromListItem `
        -ListItem $selected.ListItem `
        -MessageInfo $messageInfo `
        -TenantId $TenantId `
        -GuestFieldName $FieldMap.GuestEmails `
        -SponsorFieldName $FieldMap.SponsorEmail
    }
}

Write-Host ""
Write-Host "Invitation Results" -ForegroundColor Cyan
Write-Host ""

$results | Format-Table -AutoSize

