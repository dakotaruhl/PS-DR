<#
.SYNOPSIS
Send guest invitations from external sharing requests

.DESCRIPTION
Reads pending guest invitation requests from the External sharing request responses SharePoint list, lets the operator select request rows, previews parsed guest recipients, sends Microsoft Graph guest invitations, and records invitation results.

.CATEGORY
Helpdesk

.OUTPUTFORMAT
XLSX

.REQUIREDPOWERSHELLMODULES
Microsoft.Graph.Authentication
Microsoft.Graph.Users
Microsoft.Graph.Identity.SignIns
Microsoft.Graph.Sites
ImportExcel

.REQUIREDGRAPHAPPSCOPES
User.Invite.All
User.Read.All
Sites.Read.All

.CREATED
2026-08-14

.LASTMODIFIED
2026-08-14

.CHANGELOG
v1.0.0
- Initial version.

.NOTES
CUSTOMIZATION CHECKLIST

1. Update metadata.
2. Update $RunFolderPrefix.
3. Update $TotalSteps.
4. Add parameters.
5. Replace sample Invoke-ScriptStep blocks.
6. Add worksheets using Add-WorkbookWorksheet.
7. Export workbook using Export-MOCWorkbook.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$UseExistingSession,

    [Parameter(Mandatory = $false)]
    [switch]$SkipConnect,

    [Parameter(Mandatory = $false)]
    [switch]$DoNotOpenOutput,

    [Parameter(Mandatory = $false)]
    [string]$ReportsRoot
)

############################################################################
# Load MOCChildTools
############################################################################

$CandidateModulePaths = @()

if (-not [string]::IsNullOrWhiteSpace([string]$script:MOC_RootPath)) {
    $CandidateModulePaths += Join-Path $script:MOC_RootPath 'Modules\MOCChildTools\MOCChildTools.psd1'
}

if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
    $CandidateModulePaths += Join-Path $PSScriptRoot '..\Modules\MOCChildTools\MOCChildTools.psd1'
    $CandidateModulePaths += Join-Path $PSScriptRoot 'Modules\MOCChildTools\MOCChildTools.psd1'
}

$CandidateModulePaths += Join-Path (Get-Location).Path 'Helpdesk-MOC\Modules\MOCChildTools\MOCChildTools.psd1'
$CandidateModulePaths += Join-Path (Get-Location).Path 'Modules\MOCChildTools\MOCChildTools.psd1'

$ModulePath = $CandidateModulePaths |
    Where-Object { Test-Path -LiteralPath $_ } |
    Select-Object -First 1

if (-not $ModulePath) {
    throw "MOCChildTools module not found. Checked paths: $($CandidateModulePaths -join '; ')"
}

Import-Module $ModulePath -Force -DisableNameChecking

############################################################################
# Script Configuration
############################################################################

$RunFolderPrefix = 'Guest-Invitations'
$TotalSteps = 6

$TenantId = '0bdf0e1f-a359-4b5c-9b79-9357e35ff8c6'
$SiteId   = '0928e022-420f-4bc6-a606-c62799696eb1'
$ListName = 'External sharing request responses'

$GuestFieldName    = 'Enter external guest email(s)'
$SponsorFieldName  = 'Email'
$CompleteFieldName = 'Complete'

$FieldMap = @{
    SponsorEmail  = 'field_3'
    GuestEmails   = 'field_6'
    Justification = 'field_7'
}

$Run = Initialize-MOCChildRun `
    -ScriptPath $PSCommandPath `
    -ScriptRoot $PSScriptRoot `
    -ReportsRoot $ReportsRoot `
    -RunFolderPrefix $RunFolderPrefix `
    -TotalSteps $TotalSteps `
    -UseExistingSession:$UseExistingSession `
    -DoNotOpenOutput:$DoNotOpenOutput

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
        Write-ChildOutputLine `
            -Level Error `
            -Message "Error retrieving list items: $($_.Exception.Message)"

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

                Write-ChildOutputLine `
                    -Level Warning `
                    -Message "Guest already exists: $inviteEmail"

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

            Write-ChildOutputLine `
                -Level Success `
                -Message "SUCCESS: $displayName <$inviteEmail>"

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

            Write-ChildOutputLine `
                -Level Error `
                -Message "FAILED: $displayName <$inviteEmail> - $($_.Exception.Message)"

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

############################################################################
# Main
############################################################################

try {

    Invoke-ScriptStep `
    -StepNumber 1 `
    -Name 'Validate Graph Session' `
    -ScriptBlock {

        Assert-MOCGraphPermission `
            -RequiredScopes @(
                'User.Invite.All'
                'User.Read.All'
                'Sites.Read.All'
            )

        Write-ChildStatusLine 'Graph permissions validated.'
    }

    Invoke-ScriptStep `
    -StepNumber 2 `
    -Name 'Load SharePoint Requests' `
    -ScriptBlock {

        $script:ListResult = Get-GraphSiteListItems `
            -SiteId $SiteId `
            -ListName $ListName `
            -CompleteFieldName $CompleteFieldName

        $script:PendingItems = @($script:ListResult.Items)

        if (-not $script:PendingItems) {
            throw 'No pending guest requests found.'
        }

        Write-ChildOutputLine `
            -Level Success `
            -Message "$($script:PendingItems.Count) pending request(s) found."
    }

    Invoke-ScriptStep `
    -StepNumber 3 `
    -Name 'Select Requests' `
    -ScriptBlock {

        $script:MenuItems = @()

        $counter = 1

        foreach ($item in $script:PendingItems) {

            $script:MenuItems += [pscustomobject]@{
                Number      = $counter++
                GuestEmail  = $item.Fields.AdditionalProperties[$FieldMap.GuestEmails]
                Sponsor     = $item.Fields.AdditionalProperties[$FieldMap.SponsorEmail]
                RequestDate = $item.CreatedDateTime
                ListItem    = $item
            }
        }

        Write-ChildOutputLine `
            -Message 'Pending Guest Invitations' `
            -Level Header
            

        foreach ($item in $script:MenuItems) {

            Write-ChildOutputLine `
                -Message ("{0}. {1} | {2}" -f
                $item.Number,
                $item.GuestEmail,
                $item.Sponsor)
        }

        $script:Selection = Read-ChildText `
            -Prompt 'Enter invitation number(s)'
    }

    Invoke-ScriptStep `
    -StepNumber 4 `
    -Name 'Preview Guests' `
    -ScriptBlock {

        $script:SelectedItems = $script:MenuItems |
            Where-Object { $_.Number -in ($script:Selection.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ } | ForEach-Object { [int]$_ }) }

        foreach ($selected in $script:SelectedItems) {

            Write-ChildOutputLine `
                -Level Header `
                -Message "Request $($selected.Number)"

            $parsedGuests = ConvertTo-GuestRecord `
                -InputString $selected.ListItem.Fields.AdditionalProperties[$FieldMap.GuestEmails]

            foreach ($guest in $parsedGuests) {

                Write-ChildOutputLine `
                    -Message ("{0} <{1}>" -f $guest.DisplayName, $guest.Email)
                
            }
        }

        $Confirm = Read-ChildText `
            -Prompt 'Proceed with invitations? (Y/N)'

        if ($Confirm -ne 'Y') {
            throw 'Invitation process aborted by operator.'
        }
    }

    Invoke-ScriptStep `
    -StepNumber 5 `
    -Name 'Send Invitations' `
    -ScriptBlock {

        $messageInfo = New-InviteMessageInfo

        $script:Results = @(
        foreach ($selected in $script:SelectedItems) {

            New-GuestInvitesFromListItem `
                -ListItem $selected.ListItem `
                -MessageInfo $messageInfo `
                -TenantId $TenantId `
                -GuestFieldName $FieldMap.GuestEmails `
                -SponsorFieldName $FieldMap.SponsorEmail
            }
        )
    }

    Invoke-ScriptStep `
    -StepNumber 6 `
    -Name 'Finalize Results' `
    -ScriptBlock {

        Write-ChildOutputLine `
            -Level Header `
            -Message 'Invitation Results'

        foreach ($result in @($script:Results)) {

            Write-ChildOutputLine `
                -Message ("{0} | {1} | {2}" -f $result.Email, $result.Status, $result.Reason)
        }

        $FailedResults = @(
            $script:Results |
                Where-Object Status -eq 'Failed'
        )

        $SkippedResults = @(
            $script:Results |
                Where-Object Status -eq 'Skipped'
        )

        $InvitedResults = @(
            $script:Results |
                Where-Object Status -eq 'Invited'
        )

        Write-ChildOutputLine `
            -Level Success `
            -Message ("Invited: {0}; Skipped: {1}; Failed: {2}" -f $InvitedResults.Count, $SkippedResults.Count, $FailedResults.Count)

        Add-WorkbookWorksheet `
            -Name 'Invitation Results' `
            -Rows $script:Results `
            -ColumnOrder @(
                'Email',
                'DisplayName',
                'Status',
                'Reason',
                'GuestId',
                'GuestUPN',
                'Sponsor',
                'ListItemId'
            ) `
            -Description 'Guest invitation processing results.'

        if ($FailedResults.Count -gt 0) {

            Add-WorkbookWorksheet `
                -Name 'Failed Invitations' `
                -Rows $FailedResults `
                -ColumnOrder @(
                    'Email',
                    'DisplayName',
                    'Status',
                    'Reason',
                    'Sponsor',
                    'ListItemId'
                ) `
                -Description 'Failed guest invitation attempts.'
        }

        Export-MOCWorkbook `
            -Path $Run.WorkbookPath `
            -OpenAfterExport | Out-Null

        Complete-MOCChildRun `
            -ExportAuditNotes | Out-Null
    }
            
    Update-ChildProgress `
        -Activity $Run.ScriptName `
        -Percent 100 `
        -Status 'Completed successfully.'
}
catch {

    Update-ChildProgress `
        -Activity $Run.ScriptName `
        -Percent 100 `
        -Status 'Failed.'

    Write-ChildOutputLine `
        -Level Error `
        -Message $_.Exception.Message

    throw
}
finally {
    # Parent MOC owns transcripts, service disconnects, and terminal rendering.
}