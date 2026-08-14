<#
.SYNOPSIS
Disable Microsoft 365 accounts using the established offboarding workflow.

.DESCRIPTION
MOC-compatible version of DisableM365Accounts based on the working 1.4.1 script. This revision removes child-owned Exchange Online, Azure login, and transcript ownership while preserving the separate offboarding Enterprise Application variables. For this child script only, the script intentionally disconnects the parent MOC Microsoft Graph session and reconnects to Microsoft Graph using the dedicated offboarding Enterprise Application variables.

.VERSION
1.5.10

.AUTHOR
Long

.CATEGORY
Entra ID

.OUTPUTFORMAT
Console / parent MOC transcript

.REQUIREDGRAPHAPPSCOPES
User.ReadWrite.All, Directory.ReadWrite.All, Group.ReadWrite.All, Device.ReadWrite.All, Organization.Read.All

.REQUIREDPOWERSHELLMODULES
Microsoft.Graph.Authentication, Microsoft.Graph.Users, Microsoft.Graph.Groups, Microsoft.Graph.Identity.DirectoryManagement, ExchangeOnlineManagement, Az.Accounts, Az.KeyVault

.CREATED
2024-05-23

.LASTMODIFIED
2026-08-13

.CHANGELOG
1.5.10 - Added durable MOC progress tracking across setup and offboarding steps. Prompt/input rendering now preserves the current step percent instead of resetting the parent MOC progress pane to 0.0%.
1.5.9 - Added progress updates for each offboarding workflow step so the MOC progress pane advances during setup, Graph/Exchange validation, and user offboarding actions.
1.5.8 - Fixed MOC-safe output helper positional binding so blank spacer lines are treated as message text instead of being mis-bound to the Level parameter. This prevents the "Cannot validate argument on parameter Level" failure during final cleanup.
1.5.7 - Aligned MOC-safe output/input helper block with MOC-ChildScript-Skeleton v1.6.2. Added child output severity support, fail-closed output behavior, parent-owned progress no-op fallback, one-time menu rendering through Read-ChildText, default-choice support, and removed the duplicate Read-ChildMenuChoice parameter definition. Preserved q/Esc cancellation handling and long-line wrapping for the MOC Run Output Pane.
1.5.6 - Updated mailbox forwarding to prefer internal Exchange recipient forwarding. Manager/default forwarding now resolves the manager as an internal Exchange recipient and uses Set-Mailbox -ForwardingAddress. Manual forwarding first attempts internal recipient resolution, warns/confirms before external SMTP forwarding, and clears the opposite forwarding property when switching modes.
1.5.5 - Reworked child menu prompts to avoid Read-MOCMenuChoice output duplication during MOC refresh/scroll events. Menu options now render once in the run-output pane while Read-MOCText captures the answer in the MOC input pane, and the child no longer writes duplicate "Selected option" lines.
1.5.4 - Fixed Exchange group cleanup when the Exchange recipient lookup returns no groups. The cleanup step now treats an empty/null group result as "no matching Exchange recipient groups" instead of throwing a parameter binding warning.
1.5.3 - Added universal technician-cancel handling for all child prompts. Entering q, Esc, escape, exit, or quit now stops the active offboarding workflow cleanly, writes a cancellation message, and prompts the technician to press Enter or Esc to return to the MOC menu.
1.4.2 - Updated app-only Graph connection to use ContextScope Process to avoid corrupted CurrentUser MSAL cache deserialization.
1.4.3 - MOC compatibility update. Removed child-owned Exchange Online connection, Azure login connection, transcript start/stop, and disconnect cleanup. Kept dedicated app-only Microsoft Graph Enterprise Application variables and connection path.
1.4.4 - For this child script only, intentionally disconnect the parent MOC Microsoft Graph session before reconnecting with the dedicated offboarding Enterprise Application variables.
1.4.6 - Updated interactive prompts to use MOC child-script prompt helpers so choices/options render inside the MOC run window instead of under the terminal.
1.4.7 - Aligned prompt rendering with Export-M365ActiveUsersAndRoles child-script pattern: parent Read-MOCMenuChoice first, run-window output helper order, LastChildMenuChoice storage, and no raw host prompts.
1.5.2 - Added manager-first mailbox forwarding workflow. When mailbox forwarding is selected, option 1 now uses the disabled user's manager as the forwarding recipient with confirmation; option 2 allows manual forwarding recipient entry.
1.5.1 - Corrected metadata version label. Ensured child menu prompts do not render a separate Write-ChildPromptPanel before delegating to the parent MOC Read-MOCMenuChoice helper, preventing duplicate prompt blocks in the run-output pane. Includes 1.5.0 updates: Graph permission guidance for registered device failures, retry handling for license concurrency conflicts, improved cloud security group cleanup, and M365 group owner replacement handling when the replacement owner is already an owner.
1.4.9 - Moved prompt detail and the visible Input/Selection cursor into the run-output pane; removed parent top-pane prompt helpers for this child script and wrapped long output lines to protect the MOC frame.
#>

<#
Version 1.4.1-clean-hotfix - 06/02/2026
- Reliability - Added clearer Microsoft Graph user-not-found handling so invalid accounts are displayed, skipped, and the script continues to the next entered account.
- Usability - Added a final Press ENTER prompt so the PowerShell window stays open long enough for technicians to review errors and completion messages.

Version 1.4.1-clean - 06/02/2026
- Refactor - Created a clean/optimized execution flow while preserving the DisableM365Accounts workflow and visible intent from Version 1.4.1.
- Maintainability - Added explicit script parameters, resolved each user once per offboarding run, and passed user context into functions instead of relying on parent-scope $ID.
- Maintainability - Split the large group-removal workflow into smaller helper functions for Exchange recipient groups, Entra ID security groups, and Microsoft 365 group ownership/member cleanup.
- Reliability - Added per-step error handling so one non-critical failure does not stop the entire offboarding process.
- Reliability - Moved Microsoft Graph, Exchange Online, and transcript cleanup into the finally block so cleanup runs even if an offboarding step errors.
- Security Enhancement - Keeps Disable-UserRegisteredDevices early in the access-cutoff workflow.

Version 1.4.1 - 06/02/2026
- Security Enhancement - Added Disable-UserRegisteredDevices to disable all devices registered to the offboarded user using Microsoft Graph.
- Documentation Improvement - Added DESCRIPTION and WHY THIS MATTERS comments under each function to make the workflow easier to review, maintain, and audit.
- Documentation Improvement - Updated the high-level script description so Helpdesk and administrators can quickly understand the full DisableM365Accounts workflow.

Version 1.4.0 - 04/07/2026
- Security Enhancement - Updated Microsoft Graph authentication to use App-Only access with an Azure App Registration.
- Security Enhancement - Client Secret is now securely retrieved from Azure Key Vault instead of interactive login.
- Security Enhancement - Eliminates usage of delegated scopes and aligns with Microsoft security best practices.
- No functional changes to offboarding workflow logic.

Version 1.3.1 - 10/21/2025
- Improvements - Added an additional check prior to running this script, to check if the proper version of Microsoft Graph PowerShell module is installed (version 2.30.0 or higher).

Version 1.3 - 08/28/2025
- Improvements - Some cases, terminated user was an owner of M365 groups as well as a member of those groups. In these rare cases, Microsoft would not allow you remove the user as a member or the owner, without initially replacing the owner of the group. This has been resolved.
- Deprecation - AzureAD PowerShell module is no longer supported, therefore, this script was updated to utilize Microsoft Graph commands.
- Deprecation - Updated account disable, session revoke, and group removal steps to Microsoft Graph commands.

Version 1.2 - 05/06/2025

Version 1.1 - 04/02/2025
- Updated Update-DisplayName to ask whether the account should be retained for 60 days, 365 days, or indefinitely.
- Added RemoveProfilePic.
- Added AutoReply.

Version 1.0.1 - 02/25/2025
- Updated InstallPowerShellModules.ps1 to install/grab the latest PowerShell versions.

Version 1.0 - 05/23/2024
- Initial release after creating the Cybersecurity Runbook - Offboarding users via Offboarding PowerShell Script.

Version 0.9 - 10/18/2023
- Updated Remove-UserLicense from MSOL/AzureAD-era commands to Microsoft Graph commands.

Role Based Access Control (RBAC) Minimum Requirements:
User Administrator
Required to perform the following functions:
- DisableUserAccount
- Disable-UserRegisteredDevices
- Update-DisplayName
- Remove-UserLicense
- Remove-UserFromAllGroups

Exchange Administrator
Required to perform the following functions:
- CancelMeetings
- ConvertTo-SharedMailbox
- Remove-UserFromAllGroups
- Set-MailForwarding
- AutoReply

.DESCRIPTION
DisableM365Accounts is a Microsoft 365 / Entra ID offboarding script that helps administrators consistently remove access for terminated or departing users.

High-level workflow:
1. Validates the existing Azure/Key Vault context, retrieves the Microsoft Graph app registration client secret from Azure Key Vault, and connects to Microsoft Graph using the dedicated offboarding Enterprise Application.
2. Reuses the MOC-owned Exchange Online parent session for mailbox, calendar, forwarding, distribution group, and auto-reply tasks.
3. Resolves each target user once and uses that context across the workflow.
4. Disables the user's Entra ID account, revokes active Microsoft Graph sign-in sessions, and disables the user's registered Entra ID devices.
5. Converts the user's mailbox to a shared mailbox and hides it from the Global Address List.
6. Updates the display name with the disabled date and the selected deletion/hold timeframe.
7. Removes Microsoft 365 licenses from the account.
8. Removes the user from Exchange recipient groups, distribution groups, Microsoft 365 groups, and Entra ID security groups where possible.
9. Handles Microsoft 365 group ownership replacement when the offboarded user is an owner.
10. Optionally configures mailbox forwarding.
11. Removes the user's Microsoft 365 profile picture.
12. Enables an automatic reply on the mailbox.
13. Relies on the parent MOC menu for transcript logging and report folder ownership.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string[]]$Identity,

    [Parameter(Mandatory = $false)]
    [switch]$CancelOrganizedMeetings
)

############################################################################
# Script Variables
############################################################################

$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path $script:MyInvocation.MyCommand.Path }
$ReportsDir = Join-Path $ScriptDir 'Reports'

$TenantId = '0bdf0e1f-a359-4b5c-9b79-9357e35ff8c6'
$ClientId = '53bc912e-7f60-49bd-a8ea-3e27035e7fea'
$KeyVaultName = 'kv-offboardingM365script'
$SecretName = 'MgGraph-Client-Secret'
$DesiredSubscriptionId = '03866bcc-752b-4fd1-b5bb-cdd66aed21fb' # Erock MS Subscription


############################################################################
# MOC-Safe Output and Input Helpers
############################################################################


function Write-ChildOutputLine {
    <#
    .SYNOPSIS
    Writes a child-script line to MOC Area 5 only.

    .DESCRIPTION
    This follows the MOC-ChildScript-Skeleton 1.6.2 output contract. The child
    script classifies message severity, while the parent MOC renderer owns
    styling. This helper intentionally fails closed when no MOC-safe renderer is
    available so output does not leak below or outside the MOC frame.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false, Position = 0, ValueFromPipeline = $true, ValueFromRemainingArguments = $true)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]]$Message,

        [ValidateSet('Info','Success','Warning','Error','Critical','Action','Prompt','Header','Muted')]
        [string]$Level = 'Info'
    )

    process {
        $Text = (@($Message) | ForEach-Object { if ($null -eq $_) { '' } else { [string]$_ } }) -join ' '
        if ([string]::IsNullOrWhiteSpace($Text)) { return }

        # Keep long lines inside the Run Output Pane so the frame/borders are not damaged.
        $MaxWidth = 112
        $LinesToWrite = New-Object System.Collections.Generic.List[string]
        foreach ($RawLine in ($Text -split "`r?`n")) {
            $Line = if ($null -eq $RawLine) { '' } else { [string]$RawLine }
            if ($Line.Length -le $MaxWidth) {
                [void]$LinesToWrite.Add($Line)
                continue
            }

            while ($Line.Length -gt $MaxWidth) {
                $BreakAt = $Line.LastIndexOf(' ', [math]::Min($MaxWidth, $Line.Length - 1))
                if ($BreakAt -lt 40) { $BreakAt = $MaxWidth }
                [void]$LinesToWrite.Add($Line.Substring(0, $BreakAt).TrimEnd())
                $Line = $Line.Substring($BreakAt).TrimStart()
            }
            [void]$LinesToWrite.Add($Line)
        }

        foreach ($OutLine in $LinesToWrite) {
            if (Get-Command -Name Write-MOCOutputLine -ErrorAction SilentlyContinue) {
                try { $null = Write-MOCOutputLine -Message $OutLine -Level $Level; continue } catch { }
                try { $null = Write-MOCOutputLine $OutLine -Level $Level; continue } catch { }
                try { $null = Write-MOCOutputLine -Message $OutLine; continue } catch { }
                try { $null = Write-MOCOutputLine $OutLine; continue } catch { }
            }

            if (Get-Command -Name Write-MOCStatusLine -ErrorAction SilentlyContinue) {
                try { $null = Write-MOCStatusLine -Message $OutLine -Level $Level; continue } catch { }
                try { $null = Write-MOCStatusLine $OutLine -Level $Level; continue } catch { }
                try { $null = Write-MOCStatusLine -Message $OutLine; continue } catch { }
                try { $null = Write-MOCStatusLine $OutLine; continue } catch { }
            }

            throw 'No MOC-safe output renderer is available. Refusing to write outside the MOC Run Output Pane.'
        }
    }
}

function Write-ChildStatusLine {
    # Writes concise MOC-safe status text. Prefer Write-ChildOutputLine for detailed output in Area 5.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false, Position = 0, ValueFromPipeline = $true, ValueFromRemainingArguments = $true)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]]$Message,

        [ValidateSet('Info','Success','Warning','Error','Critical','Action','Prompt','Header','Muted')]
        [string]$Level = 'Info'
    )

    process {
        $Text = (@($Message) | ForEach-Object { if ($null -eq $_) { '' } else { [string]$_ } }) -join ' '
        if ([string]::IsNullOrWhiteSpace($Text)) { return }

        if (Get-Command -Name Write-MOCStatusLine -ErrorAction SilentlyContinue) {
            try { $null = Write-MOCStatusLine -Message $Text -Level $Level; return } catch { }
            try { $null = Write-MOCStatusLine $Text -Level $Level; return } catch { }
            try { $null = Write-MOCStatusLine -Message $Text; return } catch { }
            try { $null = Write-MOCStatusLine $Text; return } catch { }
        }

        Write-ChildOutputLine -Message $Text -Level $Level
    }
}

function Write-ChildTranscriptLine {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Message)

    if (Get-Command Write-MOCTranscriptLine -ErrorAction SilentlyContinue) {
        try { Write-MOCTranscriptLine $Message; return }
        catch { }
    }

    # Transcript-only helper intentionally does not write to UI or raw host.
    return
}

function Update-ChildProgress {
    <#
    .SYNOPSIS
    Updates MOC Area 4 only.

    .DESCRIPTION
    Child scripts call this helper for progress/activity state. The parent MOC
    owns the actual rendering. If the parent progress renderer is unavailable,
    this helper safely no-ops instead of throwing or writing progress text into
    the Run Output Pane/raw console.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Activity,
        [Parameter(Mandatory = $false)][double]$Percent = 0,
        [Parameter(Mandatory = $false)][string]$Status = '',
        [Parameter(Mandatory = $false)][string]$CurrentOperation = ''
    )

    $SafePercent = [Math]::Max(0, [Math]::Min(100, [int][Math]::Round($Percent, 0)))

    $script:ChildProgressCurrentActivity = $Activity
    $script:ChildProgressCurrentPercent = $SafePercent
    $script:ChildProgressCurrentStatus = $Status
    $script:ChildProgressCurrentOperation = $CurrentOperation

    if (Get-Command -Name Update-MOCProgress -ErrorAction SilentlyContinue) {
        $Params = @{
            Activity = $Activity
            PercentComplete = $SafePercent
            Status = $Status
        }
        if ($PSBoundParameters.ContainsKey('CurrentOperation') -and -not [string]::IsNullOrWhiteSpace($CurrentOperation)) {
            $Params.CurrentOperation = $CurrentOperation
        }
        try { $null = Update-MOCProgress @Params; return } catch { }
    }

    # Progress is helpful, but it must never leak into raw output or Area 5 as a fallback.
    return
}

$script:ChildProgressStepIndex = 0
$script:ChildProgressTotalSteps = 20
$script:ChildProgressCurrentPercent = 0
$script:ChildProgressCurrentActivity = 'Initializing'
$script:ChildProgressCurrentStatus = ''
$script:ChildProgressCurrentOperation = ''

function Set-ChildProgressPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][int]$TotalSteps
    )

    $script:ChildProgressTotalSteps = [Math]::Max(1, $TotalSteps)
}

function Get-ChildProgressPercentForStep {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)][int]$Offset = 0
    )

    $Total = [Math]::Max(1, [int]$script:ChildProgressTotalSteps)
    $Step = [Math]::Max(0, ([int]$script:ChildProgressStepIndex + $Offset))
    $Percent = [Math]::Floor(($Step / $Total) * 100)
    return [Math]::Max(1, [Math]::Min(99, [int]$Percent))
}

function Start-ChildProgressStep {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Name
    )

    $script:ChildProgressStepIndex = [Math]::Max(0, [int]$script:ChildProgressStepIndex) + 1
    $Percent = Get-ChildProgressPercentForStep -Offset -1
    Update-ChildProgress -Activity $Name -Percent $Percent -Status 'Running' -CurrentOperation $Name
}

function Complete-ChildProgressStep {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Name
    )

    $Percent = Get-ChildProgressPercentForStep
    Update-ChildProgress -Activity $Name -Percent $Percent -Status 'Completed' -CurrentOperation $Name
}

function Show-ChildInputProgress {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Prompt,
        [Parameter(Mandatory = $false)][string]$Status = 'Waiting for technician input.'
    )

    $Activity = if ([string]::IsNullOrWhiteSpace($script:ChildProgressCurrentActivity)) { 'Waiting for input' } else { [string]$script:ChildProgressCurrentActivity }
    $Percent = [Math]::Max(1, [int]$script:ChildProgressCurrentPercent)
    Update-ChildProgress -Activity $Activity -Percent $Percent -Status $Status -CurrentOperation $Prompt
}

function Complete-ChildProgress {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)][string]$Status = 'Complete'
    )

    Update-ChildProgress -Activity 'DisableM365Accounts.ps1' -Percent 100 -Status $Status -CurrentOperation 'Finished'
}

function Write-ChildPromptPanel {
    # Renders prompt instructions once in the run-output pane. Input remains parent-owned in MOC Area 7.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Title,
        [Parameter(Mandatory = $false)][string[]]$Options = @(),
        [Parameter(Mandatory = $false)][string]$Prompt = '',
        [Parameter(Mandatory = $false)][string]$Hint = ''
    )

    $SafeTitle = if ([string]::IsNullOrWhiteSpace($Title)) { 'Input required' } else { $Title.Trim() }
    Write-ChildOutputLine $SafeTitle -Level Prompt
    Write-ChildOutputLine ('-' * $SafeTitle.Length) -Level Prompt

    foreach ($Option in @($Options)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$Option)) {
            Write-ChildOutputLine ([string]$Option) -Level Prompt
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($Prompt)) {
        Write-ChildOutputLine -Message ''
        Write-ChildOutputLine $Prompt -Level Prompt
    }

    if (-not [string]::IsNullOrWhiteSpace($Hint)) {
        Write-ChildOutputLine ('Hint: {0}' -f $Hint) -Level Muted
    }
}

function Test-ChildCancelInput {
    # Returns true when technician input indicates the current child-script workflow should stop and return to the MOC menu.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$InputValue
    )

    if ($null -eq $InputValue) { return $false }

    $Text = ([string]$InputValue).Trim()
    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }

    return ($Text.ToLowerInvariant() -in @('q','quit','exit','esc','escape','exittomenu','cancel','cancelled','canceled'))
}

function Stop-ChildPromptWorkflow {
    # Throws a controlled cancellation signal that is handled by the main execution block.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)][string]$Reason = 'Technician requested cancellation from an input prompt.'
    )

    $script:ChildPromptCancellationRequested = $true
    $script:ChildPromptCancellationReason = $Reason
    throw '__MOC_CHILD_PROMPT_CANCELLED__'
}

function Write-ChildPromptCancellationMessage {
    # Writes the standard prompt-cancellation message for the MOC run-output pane.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)][string]$Reason = 'Technician requested cancellation from an input prompt.'
    )

    Write-ChildOutputLine -Message ''
    Write-ChildOutputLine 'STOPPED: DisableM365Accounts.ps1 stopped processing the current step because q/Esc was selected.' -Level Warning
    if (-not [string]::IsNullOrWhiteSpace($Reason)) {
        Write-ChildOutputLine ('Reason: {0}' -f $Reason) -Level Muted
    }
    Write-ChildOutputLine 'Press Esc or Enter again to return to the MOC menu.' -Level Action
}

function Read-ChildText {
    # Uses parent MOC input helpers so prompt/input behavior remains contained by MOC.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Prompt,
        [Parameter(Mandatory = $false)][switch]$AllowEmpty
    )

    Show-ChildInputProgress -Prompt $Prompt -Status 'Waiting for technician input.'

    foreach ($CommandName in @('Read-MOCText', 'Read-MOCTextPrompt')) {
        if (Get-Command -Name $CommandName -ErrorAction SilentlyContinue) {
            try {
                $Value = [string](& $CommandName -Prompt $Prompt -AllowEmpty:$AllowEmpty)
                if (Test-ChildCancelInput -InputValue $Value) {
                    Stop-ChildPromptWorkflow -Reason ('Technician cancelled at prompt: {0}' -f $Prompt)
                }
                if ($AllowEmpty -or -not [string]::IsNullOrWhiteSpace($Value)) { return $Value.Trim() }
            }
            catch {
                if ($script:ChildPromptCancellationRequested -or ([string]$_ -eq '__MOC_CHILD_PROMPT_CANCELLED__')) { throw }
                Write-ChildOutputLine "WARNING: Parent MOC text input helper '$CommandName' failed. Falling back to standalone input. $_" -Level Warning
                break
            }
        }
    }

    # Standalone-only fallback for development outside MOC.
    return [string](Read-Host $Prompt)
}

function Read-ChildMenuChoice {
    <#
    .SYNOPSIS
    MOC-safe numbered menu prompt for child scripts.

    .DESCRIPTION
    Writes the menu body exactly once to Area 5 using Write-ChildOutputLine, then
    collects the user selection through Read-ChildText so the parent MOC input
    state remains contained in Area 7. This intentionally does not call
    Read-MOCMenuChoice directly because some parent menu-choice renderers repaint
    while waiting for input, causing duplicate output during mouse-wheel scrolling.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Title,
        [Parameter(Mandatory = $true)][string[]]$Options,
        [Parameter(Mandatory = $false)][string]$Prompt = 'Select an option',
        [Parameter(Mandatory = $false)][string[]]$ValidChoices = @('1','2','3'),
        [Parameter(Mandatory = $false)][switch]$AllowExit,
        [Parameter(Mandatory = $false)][string]$DefaultChoice
    )

    $script:LastChildMenuChoice = $null
    $Allowed = @($ValidChoices)
    if ($AllowExit) { $Allowed += @('4','q','Esc') }

    Write-ChildOutputLine $Title -Level Prompt
    Write-ChildOutputLine ('-' * $Title.Length) -Level Prompt
    foreach ($Option in $Options) { Write-ChildOutputLine $Option -Level Prompt }
    if ($AllowExit) { Write-ChildOutputLine '4. Exit and return to MOC menu' -Level Prompt }

    $ChoiceHelp = if ($AllowExit) { (($ValidChoices + @('4','q','Esc')) -join '/') } else { ($ValidChoices -join '/') }
    $PromptText = if (-not [string]::IsNullOrWhiteSpace($DefaultChoice)) {
        ('{0} ({1}; default {2})' -f $Prompt, $ChoiceHelp, $DefaultChoice)
    }
    else {
        ('{0} ({1})' -f $Prompt, $ChoiceHelp)
    }
    Write-ChildOutputLine $PromptText -Level Prompt

    while ($true) {
        Show-ChildInputProgress -Prompt $PromptText -Status 'Waiting for user selection.'

        $ChoiceText = Read-ChildText -Prompt $PromptText -AllowEmpty
        $ChoiceText = if ($null -eq $ChoiceText) { '' } else { $ChoiceText.Trim() }

        if ([string]::IsNullOrWhiteSpace($ChoiceText) -and -not [string]::IsNullOrWhiteSpace($DefaultChoice)) {
            $ChoiceText = $DefaultChoice
        }

        $ChoiceLower = $ChoiceText.ToLowerInvariant()

        if (Test-ChildCancelInput -InputValue $ChoiceText) {
            $script:LastChildMenuChoice = 'ExitToMenu'
            Stop-ChildPromptWorkflow -Reason ('Technician cancelled at menu prompt: {0}' -f $Title)
        }

        if ($AllowExit -and ($ChoiceLower -eq '4')) {
            $script:LastChildMenuChoice = 'ExitToMenu'
            Stop-ChildPromptWorkflow -Reason ('Technician selected Exit at menu prompt: {0}' -f $Title)
        }

        if ($ChoiceText -in $ValidChoices) {
            $script:LastChildMenuChoice = $ChoiceText
            # Do not write another "Selected option" line here. Some MOC parent text-input helpers already echo
            # the selected value, and child-side duplication can clutter or break the output pane.
            return $script:LastChildMenuChoice
        }

        $InvalidHelp = if ($AllowExit) { (($ValidChoices + @('4','q','Esc')) -join ', ') } else { ($ValidChoices -join ', ') }
        if (-not [string]::IsNullOrWhiteSpace($DefaultChoice)) {
            Write-ChildOutputLine ("Invalid selection. Please enter {0}, or press Enter for {1}." -f $InvalidHelp, $DefaultChoice) -Level Warning
        }
        else {
            Write-ChildOutputLine ("Invalid selection. Please enter {0}." -f $InvalidHelp) -Level Warning
        }
    }
}

function Read-ChildEnterToContinue {
    [CmdletBinding()]
    param([Parameter(Mandatory = $false)][string]$Message = 'Press ENTER to return to the MOC menu')

    try { [void](Read-ChildText -Prompt $Message -AllowEmpty) }
    catch {
        if ($script:ChildPromptCancellationRequested -or ([string]$_ -eq '__MOC_CHILD_PROMPT_CANCELLED__')) { return }
        throw
    }
}

############################################################################
# Utility Functions
############################################################################

function Invoke-OffboardingStep {
    # DESCRIPTION: Runs an individual offboarding step with consistent logging and error handling.
    # WHY THIS MATTERS: One non-critical failure should be visible in the transcript without necessarily stopping every remaining offboarding action.

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,

        [Parameter(Mandatory = $false)]
        [switch]$Critical
    )

    Start-ChildProgressStep -Name $Name
    Write-ChildOutputLine "`n--- Starting: $Name ---"

    try {
        & $ScriptBlock
        Complete-ChildProgressStep -Name $Name
        Write-ChildOutputLine "--- Completed: $Name ---"
    }
    catch {
        if ($script:ChildPromptCancellationRequested -or ([string]$_ -eq '__MOC_CHILD_PROMPT_CANCELLED__')) {
            Update-ChildProgress -Activity $Name -Percent ([Math]::Max(1, [int]$script:ChildProgressCurrentPercent)) -Status 'Stopped' -CurrentOperation $Name
            Write-ChildStatusLine ("--- Stopped: $Name ---")
            throw
        }

        Update-ChildProgress -Activity $Name -Percent ([Math]::Max(1, [int]$script:ChildProgressCurrentPercent)) -Status 'Failed' -CurrentOperation $Name
        Write-ChildOutputLine "ERROR during step '$Name': $_"
        if ($Critical) {
            throw
        }
    }
}


function Get-GraphExceptionSummary {
    # DESCRIPTION: Converts verbose Microsoft Graph exceptions into a compact message suitable for the MOC run pane.
    [CmdletBinding()]
    param([Parameter(Mandatory = $false)][object]$ErrorRecord)

    if ($null -eq $ErrorRecord) { return '' }

    $Pieces = New-Object System.Collections.Generic.List[string]
    $Exception = $ErrorRecord.Exception

    if ($Exception -and -not [string]::IsNullOrWhiteSpace($Exception.Message)) {
        [void]$Pieces.Add($Exception.Message.Trim())
    }

    foreach ($PropertyName in @('StatusCode','ResponseStatusCode','ErrorCode','Code')) {
        try {
            $Value = $Exception.$PropertyName
            if ($null -ne $Value -and -not [string]::IsNullOrWhiteSpace([string]$Value)) {
                [void]$Pieces.Add(('{0}: {1}' -f $PropertyName, $Value))
            }
        }
        catch { }
    }

    $Text = (($Pieces | Select-Object -Unique) -join ' | ')
    if ([string]::IsNullOrWhiteSpace($Text)) { $Text = [string]$ErrorRecord }
    return ($Text -replace '\s+', ' ').Trim()
}

function Test-GraphExceptionText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)][object]$ErrorRecord,
        [Parameter(Mandatory = $true)][string]$Pattern
    )

    $Text = Get-GraphExceptionSummary -ErrorRecord $ErrorRecord
    return ($Text -match $Pattern)
}

function Invoke-GraphOperationWithRetry {
    # DESCRIPTION: Runs transient Graph operations with retry handling for common tenant concurrency conflicts and throttling.
    # WHY THIS MATTERS: License removal can intermittently return Directory_ConcurrencyViolation / 409 when the tenant is processing another account update.

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][scriptblock]$ScriptBlock,
        [Parameter(Mandatory = $true)][string]$OperationName,
        [Parameter(Mandatory = $false)][int]$MaxAttempts = 5,
        [Parameter(Mandatory = $false)][int]$InitialDelaySeconds = 3
    )

    for ($Attempt = 1; $Attempt -le $MaxAttempts; $Attempt++) {
        try {
            return & $ScriptBlock
        }
        catch {
            $IsRetryable = Test-GraphExceptionText -ErrorRecord $_ -Pattern '(?i)(409|Conflict|Directory_ConcurrencyViolation|TooManyRequests|429|throttl|temporarily)'
            if (-not $IsRetryable -or $Attempt -ge $MaxAttempts) { throw }

            $Delay = [math]::Min(60, ($InitialDelaySeconds * [math]::Pow(2, ($Attempt - 1))))
            Write-ChildOutputLine ("Retryable Graph issue during {0}. Attempt {1} of {2} failed. Waiting {3} second(s). Details: {4}" -f $OperationName, $Attempt, $MaxAttempts, $Delay, (Get-GraphExceptionSummary -ErrorRecord $_))
            Start-Sleep -Seconds $Delay
        }
    }
}

function Write-GraphPermissionGuidance {
    # DESCRIPTION: Writes targeted app permission and role guidance for known Graph permission failures.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Area,
        [Parameter(Mandatory = $true)][string[]]$RequiredGraphApplicationPermissions,
        [Parameter(Mandatory = $false)][string[]]$LikelyDirectoryRoles = @(),
        [Parameter(Mandatory = $false)][string]$ExtraNote = ''
    )

    Write-ChildOutputLine ("PERMISSION CHECK: {0}" -f $Area)
    Write-ChildOutputLine ("Required Microsoft Graph application permission(s) for the MOC/offboarding Enterprise App: {0}" -f ($RequiredGraphApplicationPermissions -join ', '))
    Write-ChildOutputLine 'Confirm admin consent has been granted after changing permissions.'
    if ($LikelyDirectoryRoles.Count -gt 0) {
        Write-ChildOutputLine ("If using delegated/role-based execution, verify the technician/admin context has one of these Entra roles as appropriate: {0}" -f ($LikelyDirectoryRoles -join ', '))
    }
    if (-not [string]::IsNullOrWhiteSpace($ExtraNote)) { Write-ChildOutputLine $ExtraNote }
}

function Initialize-MOCReportFolder {
    # DESCRIPTION: Ensures the local Reports folder exists when the script is run through MOC or directly.
    # WHY THIS MATTERS: The parent MOC menu owns transcript logging; this child script only ensures its local output path exists.

    if (-not (Test-Path $ReportsDir)) {
        New-Item -Path $ReportsDir -ItemType Directory -Force | Out-Null
    }
}

function Import-RequiredModules {
    # DESCRIPTION: Imports the Azure modules required to authenticate and read the Graph client secret from Key Vault.
    # WHY THIS MATTERS: Loading the required modules early provides a clear failure point before any account changes are attempted.

    Import-Module Az.Accounts -ErrorAction Stop
    Import-Module Az.KeyVault -ErrorAction Stop
}

function Set-DefaultAzureSubscription {
    # DESCRIPTION: Sets the preferred Azure subscription for the current PowerShell process.
    # WHY THIS MATTERS: Key Vault lookup depends on the script using the expected subscription context.

    try {
        $azConfig = Get-AzConfig -ErrorAction SilentlyContinue

        if (-not $azConfig.DefaultSubscriptionForLogin -or $azConfig.DefaultSubscriptionForLogin -ne $DesiredSubscriptionId) {
            Write-ChildOutputLine "Setting DefaultSubscriptionForLogin to 'Erock MS Subscription'..."
            Update-AzConfig -DefaultSubscriptionForLogin $DesiredSubscriptionId -Scope Process | Out-Null
        }
    }
    catch {
        Write-ChildOutputLine "WARNING: Could not set DefaultSubscriptionForLogin. $_"
    }
}

function Assert-AzureKeyVaultContext {
    # DESCRIPTION: Validates that an Azure context is already available for Key Vault access.
    # WHY THIS MATTERS: MOC child scripts should not start Azure login flows. If Key Vault access is missing, authenticate from MOC or establish the Azure context before running this child script.

    $AzContext = Get-AzContext -ErrorAction SilentlyContinue
    if (-not $AzContext) {
        throw "Azure context was not detected for Key Vault access. Return to MOC and authenticate with the parent menu, or establish the Azure context before running this child script. Required Key Vault: $KeyVaultName; secret: $SecretName."
    }

    Write-ChildOutputLine "Azure context validated for Key Vault access: $($AzContext.Account.Id)"
}

function Get-GraphClientSecretCredential {
    # DESCRIPTION: Retrieves the Graph app registration client secret from Azure Key Vault and builds a PSCredential object.
    # WHY THIS MATTERS: Keeping the secret in Key Vault avoids hardcoding credentials in the offboarding script.

    Write-ChildOutputLine 'Retrieving Microsoft Graph client secret from Azure Key Vault...'

    $ClientSecret = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $SecretName -AsPlainText -WarningAction SilentlyContinue

    if (-not $ClientSecret) {
        throw 'Unable to retrieve client secret from Azure Key Vault.'
    }

    $SecureSecret = ConvertTo-SecureString -String $ClientSecret -AsPlainText -Force
    return New-Object System.Management.Automation.PSCredential ($ClientId, $SecureSecret)
}

function Connect-MicrosoftGraphAppOnly {
    # DESCRIPTION: Disconnects the parent MOC Microsoft Graph context and reconnects using the offboarding Enterprise Application and Key Vault secret.
    # WHY THIS MATTERS: This child script is a special exception to the normal MOC parent Graph-session rule because the offboarding app registration already has the required application permissions. Exchange Online and Azure/Key Vault context still remain MOC-owned.

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSCredential]$ClientSecretCredential
    )

    Write-ChildOutputLine 'Disconnecting parent MOC Microsoft Graph session for this offboarding child script...'

    try {
        Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
    }
    catch {
        Write-ChildOutputLine "WARNING: Existing Microsoft Graph session could not be cleanly disconnected. Continuing with dedicated offboarding app authentication. $($_.Exception.Message)"
    }

    Start-Sleep -Milliseconds 500

    Write-ChildOutputLine 'Connecting to Microsoft Graph using offboarding Enterprise Application variables...'

    try {
        # This script intentionally uses the dedicated offboarding Enterprise Application rather than the parent MOC Graph context.
        # ContextScope Process keeps the app-only connection isolated to this child-script run.
        Connect-MgGraph -TenantId $TenantId -ClientSecretCredential $ClientSecretCredential -ContextScope Process -NoWelcome -ErrorAction Stop | Out-Null

        $GraphContext = Get-MgContext -ErrorAction Stop
        if (-not $GraphContext -or $GraphContext.TenantId -ne $TenantId) {
            throw "Microsoft Graph app-only authentication did not return the expected tenant context. Expected TenantId: $TenantId."
        }

        Write-ChildOutputLine "Microsoft Graph connected with offboarding Enterprise Application. TenantId: $($GraphContext.TenantId); AuthType: $($GraphContext.AuthType)."
    }
    catch {
        $Message = $_.Exception.Message
        if ($Message -match 'MSAL deserialization failed|cache contents|JsonReaderException|Unexpected character encountered') {
            throw "Microsoft Graph app-only authentication failed because the Microsoft Graph token cache appears corrupted or encoded in the current session. This script now disconnects the parent MOC Graph session first and reconnects with the dedicated offboarding Enterprise Application. Close all PowerShell windows, reopen MOC, press A to authenticate, and rerun. If it persists, clear the Microsoft Graph PowerShell token cache for the Windows profile, then rerun. Original error: $Message"
        }
        throw
    }
}

function Assert-ExchangeOnlineParentSession {
    # DESCRIPTION: Validates that the MOC-owned Exchange Online parent session is available.
    # WHY THIS MATTERS: Several offboarding steps still rely on Exchange Online cmdlets, but the child script must reuse the parent MOC Exchange session instead of creating its own.

    $ExchangeCommand = Get-Command Get-ConnectionInformation -ErrorAction SilentlyContinue
    if ($ExchangeCommand) {
        $ConnectionInfo = Get-ConnectionInformation -ErrorAction SilentlyContinue
        if ($ConnectionInfo) {
            Write-ChildOutputLine 'Exchange Online parent session validated.'
            return
        }
    }

    try {
        Get-EXOMailbox -ResultSize 1 -ErrorAction Stop | Out-Null
        Write-ChildOutputLine 'Exchange Online parent session validated.'
        return
    }
    catch {
        throw 'Exchange Online parent session was not detected. Return to MOC, press A to authenticate, then rerun this script.'
    }
}

function Resolve-OffboardingUser {
    # DESCRIPTION: Resolves the entered account name into a Microsoft Graph user object one time for the workflow.
    # WHY THIS MATTERS: Reusing the resolved user object reduces duplicate lookups and makes downstream functions more predictable.

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$UserId
    )

    try {
        return Get-MgUser -UserId $UserId -ErrorAction Stop
    }
    catch {
        Write-ChildOutputLine -Message ''
        Write-ChildOutputLine '=================================================================='
        Write-ChildOutputLine "ERROR: User '$UserId' was not found in Microsoft Graph."
        Write-ChildOutputLine 'The account may already be deleted, misspelled, or not synced.'
        Write-ChildOutputLine 'Skipping this account and continuing to the next entered account.'
        Write-ChildOutputLine '=================================================================='
        Write-ChildOutputLine -Message ''
        return $null
    }
}

function Get-TargetIdentities {
    # DESCRIPTION: Returns identities passed by parameter or interactively collects one or more accounts from the technician.
    # WHY THIS MATTERS: This preserves the original multi-account Helpdesk workflow by allowing the technician to enter accounts one at a time, then press Enter on a blank prompt to begin processing the full batch.

    if ($Identity -and $Identity.Count -gt 0) {
        return $Identity
    }

    Write-ChildOutputLine 'Enter account names to disable in Entra ID.'
    Write-ChildOutputLine 'Enter one account per prompt. Leave blank and press Enter when finished.'

    $Users = @()

    do {
        $User = Read-ChildText -Prompt 'Enter account to disable (leave blank when finished)' -AllowEmpty

        if (![string]::IsNullOrWhiteSpace($User)) {
            $Users += $User.Trim()
        }

    } until ([string]::IsNullOrWhiteSpace($User))

    return $Users
}

############################################################################
# Offboarding Functions
############################################################################

function SessionInfo {
    # DESCRIPTION: Stores the current Microsoft Graph session context in a script-scoped variable.
    # WHY THIS MATTERS: Capturing the Graph context helps confirm the script is connected to Microsoft Graph before account changes are attempted.

    $script:CurrentSessionInfo = Get-MgContext
}

function DisableUserAccount {
    # DESCRIPTION: Blocks Microsoft 365 sign-in for the user and revokes the user's active sign-in sessions.
    # WHY THIS MATTERS: Disabling the account and revoking sessions are the first access-control steps that help prevent continued access with existing tokens.

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $User
    )

    Write-ChildOutputLine "Disabling '$($User.UserPrincipalName)'"
    Update-MgUser -UserId $User.Id -AccountEnabled:$false -ErrorAction Stop
    Revoke-MgUserSignInSession -UserId $User.Id -ErrorAction Stop | Out-Null
}

function Disable-UserRegisteredDevices {
    # DESCRIPTION: Finds every device registered to the user in Entra ID and disables each device object.
    # WHY THIS MATTERS: Microsoft notes that access revocation can require multiple actions; disabling registered devices helps reduce the chance that a user's known devices continue to be trusted during offboarding.

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $User
    )

    Write-ChildOutputLine "Disabling registered devices for '$($User.UserPrincipalName)'"

    $RegisteredDevices = Get-MgUserRegisteredDevice -UserId $User.Id -All -ErrorAction Stop

    if (-not $RegisteredDevices) {
        Write-ChildOutputLine "No registered devices found for '$($User.UserPrincipalName)'."
        return
    }

    foreach ($Device in $RegisteredDevices) {
        try {
            $DeviceId = [string]$Device.Id
            $DeviceName = if ($Device.AdditionalProperties.displayName) { [string]$Device.AdditionalProperties.displayName } else { $DeviceId }
            Write-ChildOutputLine "Disabling registered device '$DeviceName' ($DeviceId)"
            Update-MgDevice -DeviceId $DeviceId -AccountEnabled:$false -ErrorAction Stop
            Write-ChildOutputLine "Disabled registered device '$DeviceName'."
        }
        catch {
            Write-ChildOutputLine "WARNING: Unable to disable registered device '$($Device.Id)' for '$($User.UserPrincipalName)'. $(Get-GraphExceptionSummary -ErrorRecord $_)"
            if (Test-GraphExceptionText -ErrorRecord $_ -Pattern '(?i)Insufficient privileges|Authorization_RequestDenied|Forbidden|403') {
                Write-GraphPermissionGuidance `
                    -Area 'Disable registered Entra devices' `
                    -RequiredGraphApplicationPermissions @('Device.ReadWrite.All', 'Directory.ReadWrite.All') `
                    -LikelyDirectoryRoles @('Cloud Device Administrator', 'Intune Administrator', 'Global Administrator') `
                    -ExtraNote 'For this child script, update the dedicated offboarding Enterprise Application and/or the MOC menu permission checklist so Device.ReadWrite.All is present and admin-consented.'
            }
        }
    }
}

function CancelMeetings {
    # DESCRIPTION: Cancels meetings where the offboarded user is the organizer.
    # WHY THIS MATTERS: Removing organizer-owned meetings helps prevent abandoned calendar events from remaining on attendee calendars.

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$UserId
    )

    Write-ChildOutputLine "Cancelling all meetings where '$UserId' is set as the organizer"
    Remove-CalendarEvents -Identity $UserId -CancelOrganizedMeetings -QueryWindowInDays 1825 -Confirm:$False -ErrorAction Stop
}

function ConvertTo-SharedMailbox {
    # DESCRIPTION: Converts the user's mailbox to a shared mailbox and hides it from the Global Address List.
    # WHY THIS MATTERS: Shared mailboxes preserve business email history while hiding the disabled mailbox from normal address book discovery.

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$UserId
    )

    $UserMailbox = Get-Mailbox $UserId -ErrorAction Stop
    Write-ChildOutputLine "Changing the user mailbox to a shared mailbox for '$UserId'"
    $UserMailbox | Set-Mailbox -Type Shared -ErrorAction Stop

    Write-ChildOutputLine "Hiding mailbox from the GAL for '$UserId'"
    $UserMailbox | Set-Mailbox -HiddenFromAddressListsEnabled $true -ErrorAction Stop
}

function Update-DisplayName {
    # DESCRIPTION: Prompts for the retention timeframe and updates the user's display name with the disabled date and deletion/hold marker.
    # WHY THIS MATTERS: A consistent display-name marker makes disabled accounts easy to identify and helps administrators know when the account should be deleted or retained.

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $User
    )

    $Choice = Read-ChildMenuChoice `
        -Title 'Select disabled account retention timeframe' `
        -Options @('1. 60 days','2. 365 days','3. HOLD (Indefinitely)') `
        -Prompt 'Enter the number corresponding to your choice' `
        -ValidChoices @('1','2','3')

    switch ($Choice) {
        '1' { $DisableUntil = (Get-Date).AddDays(60) }
        '2' { $DisableUntil = (Get-Date).AddDays(365) }
        '3' { $DisableUntil = '(HOLD)' }
    }

    Write-ChildOutputLine "Adding *DIS on and *DEL on dates to DisplayName of '$($User.UserPrincipalName)'"

    if ($User.DisplayName.StartsWith('*DIS')) {
        Write-ChildOutputLine "Note: *DIS already present on the DisplayName of '$($User.UserPrincipalName)', no update necessary."
        return
    }

    $NewDisplayName = if ($DisableUntil -eq '(HOLD)') {
        "*DIS on $(Get-Date -f 'MM/dd/yyyy') - (HOLD) - $($User.DisplayName)"
    }
    else {
        "*DIS on $(Get-Date -f 'MM/dd/yyyy') - *DEL on $($DisableUntil.ToString('MM/dd/yyyy')) - $($User.DisplayName)"
    }

    Update-MgUser -UserId $User.Id -DisplayName $NewDisplayName -ErrorAction Stop
    Write-ChildOutputLine "Updated DisplayName: $NewDisplayName"
}

function Remove-UserLicense {
    # DESCRIPTION: Removes all Microsoft 365 licenses currently assigned to the user.
    # WHY THIS MATTERS: Removing licenses helps reclaim subscription capacity and prevents paid services from remaining assigned to disabled accounts.

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $User
    )

    Write-ChildOutputLine "Removing all Microsoft 365 licenses from '$($User.UserPrincipalName)'"

    $Licenses = @(Get-MgUserLicenseDetail -UserId $User.Id -ErrorAction Stop)

    if ($Licenses.Count -eq 0) {
        Write-ChildOutputLine "No Microsoft 365 licenses found for '$($User.UserPrincipalName)'."
        return
    }

    foreach ($License in $Licenses) {
        $SkuId = [string]$License.SkuId
        try {
            Invoke-GraphOperationWithRetry -OperationName "remove license SKU $SkuId from $($User.UserPrincipalName)" -MaxAttempts 6 -InitialDelaySeconds 4 -ScriptBlock {
                Set-MgUserLicense -UserId $User.Id -AddLicenses @() -RemoveLicenses @($SkuId) -ErrorAction Stop | Out-Null
            } | Out-Null
            Write-ChildOutputLine "Removed license SKU '$SkuId'"
            Start-Sleep -Milliseconds 750
        }
        catch {
            Write-ChildOutputLine "WARNING: Unable to remove license SKU '$SkuId' from '$($User.UserPrincipalName)' after retry handling. $(Get-GraphExceptionSummary -ErrorRecord $_)"
            if (Test-GraphExceptionText -ErrorRecord $_ -Pattern '(?i)Directory_ConcurrencyViolation|409|Conflict') {
                Write-ChildOutputLine 'Recommendation: wait a few minutes and rerun only the license-removal portion or rerun this script for the same user. The tenant was still processing another directory update.'
            }
        }
    }
}

function Resolve-ExchangeUserReference {
    # DESCRIPTION: Resolves the Exchange user object used for Exchange recipient group membership checks.
    # WHY THIS MATTERS: Exchange group-removal cmdlets need DistinguishedName and ExternalDirectoryObjectId values.

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$UserId
    )

    $ExchangeUser = Get-User $UserId -ErrorAction Stop | Select-Object DistinguishedName, ExternalDirectoryObjectId

    if (-not $ExchangeUser) {
        throw "Security principal with identifier '$UserId' was not found."
    }

    if ($ExchangeUser.Count -gt 1) {
        throw "Multiple users matching identifier '$UserId' were found."
    }

    return $ExchangeUser
}

function Get-ExchangeRecipientGroupsForUser {
    # DESCRIPTION: Gets Exchange recipient groups where the user is currently a member.
    # WHY THIS MATTERS: Exchange and distribution group membership can continue to grant mail flow, collaboration, or access even after sign-in is blocked.

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $ExchangeUser
    )

    $GroupTypes = @('GroupMailbox', 'MailUniversalDistributionGroup', 'MailUniversalSecurityGroup')

    return Get-Recipient -Filter "Members -eq '$($ExchangeUser.DistinguishedName)'" -RecipientTypeDetails $GroupTypes -ErrorAction Stop |
        Select-Object DisplayName, ExternalDirectoryObjectId, RecipientTypeDetails |
        Where-Object { $_.DisplayName -ne 'Enchanted Rock' }
}

function Remove-UserFromExchangeRecipientGroups {
    # DESCRIPTION: Removes the user from Exchange recipient groups found by Exchange Online.
    # WHY THIS MATTERS: Keeping this step separate makes group membership cleanup easier to maintain and troubleshoot.

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$UserId,

        [Parameter(Mandatory = $true)]
        $ExchangeUser,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        $Groups
    )

    $SafeGroups = @($Groups) | Where-Object { $null -ne $_ }

    if ($SafeGroups.Count -eq 0) {
        Write-ChildOutputLine "No matching Exchange recipient groups found for '$UserId'."
        return
    }

    $UnifiedGroups = @($SafeGroups | Where-Object { [string]$_.RecipientTypeDetails -eq 'GroupMailbox' -or [string]$_.RecipientTypeDetails.Value -eq 'GroupMailbox' })
    $DistributionGroups = @($SafeGroups | Where-Object { [string]$_.RecipientTypeDetails -ne 'GroupMailbox' -and [string]$_.RecipientTypeDetails.Value -ne 'GroupMailbox' })

    Write-ChildOutputLine "Removing '$UserId' from Unified/M365 groups returned by Exchange recipient lookup"
    foreach ($Group in $UnifiedGroups) {
        try {
            Remove-UnifiedGroupLinks -Identity $Group.ExternalDirectoryObjectId -Links $ExchangeUser.DistinguishedName -LinkType Member -Confirm:$false -WhatIf:$WhatIfPreference -ErrorAction Stop
            Write-ChildOutputLine "Removed '$UserId' from Unified/M365 group '$($Group.DisplayName)'"
        }
        catch {
            Write-ChildOutputLine "WARNING: Unable to remove '$UserId' from Unified/M365 group '$($Group.DisplayName)'. $_"
        }
    }

    Write-ChildOutputLine "Removing '$UserId' from distribution and mail-enabled security groups"
    foreach ($Group in $DistributionGroups) {
        try {
            Remove-DistributionGroupMember -Identity $Group.ExternalDirectoryObjectId -Member $ExchangeUser.DistinguishedName -Confirm:$false -ErrorAction Stop
            Write-ChildOutputLine "Removed '$UserId' from distribution/mail-enabled security group '$($Group.DisplayName)'"
        }
        catch {
            Write-ChildOutputLine "WARNING: Unable to remove '$UserId' from distribution/mail-enabled security group '$($Group.DisplayName)'. $_"
        }
    }
}

function Remove-UserFromEntraSecurityGroups {
    # DESCRIPTION: Removes the user from directly assigned cloud Entra ID security groups where Microsoft Graph allows direct membership removal.
    # WHY THIS MATTERS: Security group memberships can preserve access to apps and resources even after the account is disabled.

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $User
    )

    Write-ChildOutputLine "Reviewing directly assigned cloud security groups for '$($User.UserPrincipalName)'"

    $MemberObjects = @(Get-MgUserMemberOf -UserId $User.Id -All -ErrorAction Stop | Where-Object {
        $_.Id -and (($_.'@odata.type' -eq '#microsoft.graph.group') -or ($_.AdditionalProperties.'@odata.type' -eq '#microsoft.graph.group'))
    })

    if ($MemberObjects.Count -eq 0) {
        Write-ChildOutputLine "No direct Entra ID group memberships found for '$($User.UserPrincipalName)'."
        return
    }

    $CandidateGroups = New-Object System.Collections.Generic.List[object]
    foreach ($MemberObject in $MemberObjects) {
        try {
            $Group = Get-MgGroup -GroupId $MemberObject.Id -Property 'id,displayName,securityEnabled,mailEnabled,groupTypes,onPremisesSyncEnabled,membershipRule' -ErrorAction Stop
            $GroupTypes = @($Group.GroupTypes)
            $IsUnified = $GroupTypes -contains 'Unified'
            $IsCloudOnly = ($Group.OnPremisesSyncEnabled -ne $true)
            $IsAssignedMembership = [string]::IsNullOrWhiteSpace([string]$Group.MembershipRule)

            if ($Group.SecurityEnabled -eq $true -and -not $IsUnified -and $IsCloudOnly -and $IsAssignedMembership -and $Group.DisplayName -ne 'All Users') {
                [void]$CandidateGroups.Add($Group)
            }
            elseif ($Group.SecurityEnabled -eq $true -and -not $IsAssignedMembership) {
                Write-ChildOutputLine "Skipped dynamic security group '$($Group.DisplayName)'. Update the membership rule instead of removing the user directly."
            }
            elseif ($Group.SecurityEnabled -eq $true -and -not $IsCloudOnly) {
                Write-ChildOutputLine "Skipped on-premises synchronized security group '$($Group.DisplayName)'. Remove membership from the source directory."
            }
        }
        catch {
            Write-ChildOutputLine "WARNING: Unable to inspect group '$($MemberObject.Id)' for '$($User.UserPrincipalName)'. $(Get-GraphExceptionSummary -ErrorRecord $_)"
        }
    }

    if ($CandidateGroups.Count -eq 0) {
        Write-ChildOutputLine "No removable directly assigned cloud security groups found for '$($User.UserPrincipalName)'."
        return
    }

    foreach ($Group in $CandidateGroups) {
        try {
            Remove-MgGroupMemberByRef -GroupId $Group.Id -DirectoryObjectId $User.Id -ErrorAction Stop
            Write-ChildOutputLine "Removed '$($User.UserPrincipalName)' from cloud security group '$($Group.DisplayName)'"
        }
        catch {
            Write-ChildOutputLine "WARNING: Unable to remove '$($User.UserPrincipalName)' from cloud security group '$($Group.DisplayName)'. $(Get-GraphExceptionSummary -ErrorRecord $_)"
            if (Test-GraphExceptionText -ErrorRecord $_ -Pattern '(?i)Insufficient privileges|Authorization_RequestDenied|Forbidden|403') {
                Write-GraphPermissionGuidance `
                    -Area 'Remove user from cloud security groups' `
                    -RequiredGraphApplicationPermissions @('Group.ReadWrite.All', 'Directory.ReadWrite.All') `
                    -LikelyDirectoryRoles @('Groups Administrator', 'User Administrator', 'Global Administrator') `
                    -ExtraNote 'Role-assignable groups may also require Privileged Role Administrator or a more privileged admin context.'
            }
        }
    }
}

function Resolve-ReplacementM365GroupOwner {
    # DESCRIPTION: Prompts for and validates a replacement owner for a Microsoft 365 group.
    # WHY THIS MATTERS: Microsoft 365 groups cannot be left without valid ownership when removing an offboarded owner.

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $User,

        [Parameter(Mandatory = $true)]
        $Group
    )

    do {
        $Choice = Read-ChildMenuChoice `
            -Title "Choose replacement owner for '$($Group.DisplayName)'" `
            -Options @("1. Use the manager of $($User.UserPrincipalName) as the new/replacement owner.",'2. Manually enter the new UPN of the owner.') `
            -Prompt 'Enter 1 or 2' `
            -ValidChoices @('1','2')

        $Valid = $false
        $NewOwnerObj = $null

        switch ($Choice) {
            '1' {
                try {
                    $ManagerRef = Get-MgUserManager -UserId $User.Id -ErrorAction Stop
                    if ($null -ne $ManagerRef) {
                        $ManagerObj = Get-MgUser -UserId $ManagerRef.Id -ErrorAction Stop
                        Write-ChildOutputLine "Manager found: $($ManagerObj.DisplayName) <$($ManagerObj.UserPrincipalName)>"
                        $Confirm = Read-ChildMenuChoice -Title 'Confirm replacement owner' -Options @('1. Use this manager as the new owner','2. Choose another owner') -Prompt 'Press 1 or 2' -ValidChoices @('1','2')
                        if ($Confirm -eq '1') {
                            $NewOwnerObj = $ManagerObj
                            $Valid = $true
                        }
                    }
                }
                catch {
                    Write-ChildOutputLine "No manager found for $($User.UserPrincipalName). Please manually enter a replacement owner."
                }
            }
            '2' {
                $NewOwnerUPN = Read-ChildText -Prompt "Enter the UPN of the new owner for '$($Group.DisplayName)'"
                try {
                    $NewOwnerObj = Get-MgUser -UserId $NewOwnerUPN -ErrorAction Stop
                    $Valid = $true
                }
                catch {
                    Write-ChildOutputLine 'User not found. Please enter a valid UPN.'
                }
            }
            Default {
                Write-ChildOutputLine 'Invalid selection. Please enter 1 or 2.'
            }
        }
    } while (-not $Valid)

    return $NewOwnerObj
}

function Remove-UserFromOwnedM365Groups {
    # DESCRIPTION: Finds Microsoft 365 groups owned by the user, adds a replacement owner when needed, removes the user as owner, and removes membership when applicable.
    # WHY THIS MATTERS: Ownership cleanup prevents orphaned groups and resolves cases where Microsoft blocks member removal while the user is still an owner.

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $User
    )

    $Groups = Get-MgGroup -Filter "groupTypes/any(c:c eq 'Unified')" -All -ErrorAction Stop
    $TotalGroups = @($Groups).Count
    $Counter = 0

    foreach ($Group in $Groups) {
        $Counter++

        if (($TotalGroups -gt 0) -and (($Counter -eq 1) -or ($Counter -eq $TotalGroups) -or (($Counter % 25) -eq 0))) {
            Write-ChildOutputLine ("Processing M365 group {0} of {1}: {2}" -f $Counter, $TotalGroups, $Group.DisplayName)
        }

        $Owners = @(Get-MgGroupOwner -GroupId $Group.Id -All -ErrorAction SilentlyContinue)
        $IsOwner = @($Owners | Where-Object {
            $_.Id -eq $User.Id -or $_.AdditionalProperties.userPrincipalName -eq $User.UserPrincipalName
        })

        if ($IsOwner.Count -eq 0) { continue }

        Write-ChildOutputLine "`nGroup Name: $($Group.DisplayName) ($($Group.Id))"
        Write-ChildOutputLine "$($User.UserPrincipalName) is an OWNER of this group."

        $NewOwnerObj = Resolve-ReplacementM365GroupOwner -User $User -Group $Group
        $ReplacementAlreadyOwner = @($Owners | Where-Object { $_.Id -eq $NewOwnerObj.Id -or $_.AdditionalProperties.userPrincipalName -eq $NewOwnerObj.UserPrincipalName }).Count -gt 0

        if ($ReplacementAlreadyOwner) {
            Write-ChildOutputLine "Replacement owner '$($NewOwnerObj.UserPrincipalName)' is already an owner of '$($Group.DisplayName)'. Skipping add-owner step."
        }
        else {
            try {
                $NewGroupOwner = @{ '@odata.id' = "https://graph.microsoft.com/v1.0/users/$($NewOwnerObj.Id)" }
                New-MgGroupOwnerByRef -GroupId $Group.Id -BodyParameter $NewGroupOwner -ErrorAction Stop
                Write-ChildOutputLine "Added new owner: $($NewOwnerObj.UserPrincipalName)"
            }
            catch {
                if (Test-GraphExceptionText -ErrorRecord $_ -Pattern '(?i)added object references already exist|already exist|ObjectConflict|Request_BadRequest') {
                    Write-ChildOutputLine "Replacement owner '$($NewOwnerObj.UserPrincipalName)' already appears to be an owner. Continuing with removal of disabled user."
                }
                else {
                    Write-ChildOutputLine "WARNING: Unable to add replacement owner '$($NewOwnerObj.UserPrincipalName)' to '$($Group.DisplayName)'. $(Get-GraphExceptionSummary -ErrorRecord $_)"
                    if (Test-GraphExceptionText -ErrorRecord $_ -Pattern '(?i)Insufficient privileges|Authorization_RequestDenied|Forbidden|403') {
                        Write-GraphPermissionGuidance -Area 'Add Microsoft 365 group replacement owner' -RequiredGraphApplicationPermissions @('Group.ReadWrite.All', 'Directory.ReadWrite.All') -LikelyDirectoryRoles @('Groups Administrator', 'Global Administrator')
                    }
                    continue
                }
            }
        }

        foreach ($Owner in $IsOwner) {
            try {
                Remove-MgGroupOwnerByRef -GroupId $Group.Id -DirectoryObjectId $Owner.Id -ErrorAction Stop
                Write-ChildOutputLine "Removed $($User.UserPrincipalName) from owners of '$($Group.DisplayName)'."
            }
            catch {
                Write-ChildOutputLine "WARNING: Unable to remove $($User.UserPrincipalName) as owner of '$($Group.DisplayName)'. $(Get-GraphExceptionSummary -ErrorRecord $_)"
            }
        }

        try {
            $Members = @(Get-MgGroupMember -GroupId $Group.Id -All -ErrorAction SilentlyContinue)
            $IsMember = @($Members | Where-Object {
                $_.Id -eq $User.Id -or $_.AdditionalProperties.userPrincipalName -eq $User.UserPrincipalName
            })

            if ($IsMember.Count -eq 0) {
                Write-ChildOutputLine "$($User.UserPrincipalName) is not a member of '$($Group.DisplayName)'."
                continue
            }

            foreach ($Member in $IsMember) {
                try {
                    Remove-MgGroupMemberByRef -GroupId $Group.Id -DirectoryObjectId $Member.Id -ErrorAction Stop
                    Write-ChildOutputLine "Removed $($User.UserPrincipalName) from members of '$($Group.DisplayName)'."
                }
                catch {
                    Write-ChildOutputLine "WARNING: Unable to remove $($User.UserPrincipalName) as member of '$($Group.DisplayName)'. $(Get-GraphExceptionSummary -ErrorRecord $_)"
                }
            }
        }
        catch {
            Write-ChildOutputLine "WARNING: Unable to review membership for '$($Group.DisplayName)'. $(Get-GraphExceptionSummary -ErrorRecord $_)"
        }
    }

    Write-ChildOutputLine 'Completed M365 group ownership/member review.'
}

function Remove-UserFromAllGroups {
    # DESCRIPTION: Coordinates Exchange group, distribution group, Entra ID security group, and Microsoft 365 group ownership/member removal.
    # WHY THIS MATTERS: Group membership and ownership can preserve access to mail, files, Teams, SharePoint, and other resources even after sign-in is blocked.

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $User,

        [Parameter(Mandatory = $true)]
        [string]$OriginalInput
    )

    Write-ChildOutputLine "Removing group memberships for '$($User.UserPrincipalName)'"

    try {
        $ExchangeUser = Resolve-ExchangeUserReference -UserId $OriginalInput
        $ExchangeGroups = @(Get-ExchangeRecipientGroupsForUser -ExchangeUser $ExchangeUser)
        Remove-UserFromExchangeRecipientGroups -UserId $OriginalInput -ExchangeUser $ExchangeUser -Groups $ExchangeGroups
    }
    catch {
        Write-ChildOutputLine "WARNING: Exchange group cleanup did not complete for '$OriginalInput'. $_"
    }

    try {
        Remove-UserFromEntraSecurityGroups -User $User
    }
    catch {
        Write-ChildOutputLine "WARNING: Entra security group cleanup did not complete for '$($User.UserPrincipalName)'. $_"
    }

    try {
        Remove-UserFromOwnedM365Groups -User $User
    }
    catch {
        Write-ChildOutputLine "WARNING: M365 group owner/member cleanup did not complete for '$($User.UserPrincipalName)'. $_"
    }
}

function Resolve-MailForwardingExchangeRecipient {
    # DESCRIPTION: Attempts to resolve a mailbox forwarding target as an internal Exchange recipient.
    # WHY THIS MATTERS: Using -ForwardingAddress for internal recipients keeps forwarding visible in Exchange Admin Center as "Forward to an internal email address" instead of external SMTP forwarding.

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Identity
    )

    try {
        $Recipient = Get-Recipient -Identity $Identity -ErrorAction Stop
        if ($null -eq $Recipient) { return $null }

        $AllowedRecipientTypes = @(
            'UserMailbox',
            'SharedMailbox',
            'RoomMailbox',
            'EquipmentMailbox',
            'MailUser',
            'MailContact',
            'GroupMailbox'
        )

        $RecipientTypeDetails = [string]$Recipient.RecipientTypeDetails
        if ($AllowedRecipientTypes -notcontains $RecipientTypeDetails) {
            Write-ChildOutputLine "WARNING: Forwarding target '$Identity' resolved to Exchange recipient type '$RecipientTypeDetails', which is not allowed for this offboarding forwarding workflow."
            return $null
        }

        return $Recipient
    }
    catch {
        return $null
    }
}

function New-MailForwardingTargetResult {
    # DESCRIPTION: Creates a consistent return object for internal or external mailbox forwarding targets.
    # WHY THIS MATTERS: The final Set-Mailbox call needs to know whether to use -ForwardingAddress or -ForwardingSmtpAddress.

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][ValidateSet('Internal','External')][string]$Mode,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Address,
        [Parameter(Mandatory = $false)]$Recipient
    )

    [pscustomobject]@{
        Mode      = $Mode
        Address   = $Address
        Recipient = $Recipient
    }
}

function Get-ExchangeRecipientDisplayText {
    # DESCRIPTION: Returns a technician-friendly display string for an Exchange recipient.
    # WHY THIS MATTERS: Confirmation prompts should clearly show who will receive forwarded mail.

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Recipient
    )

    $Name = [string]$Recipient.DisplayName
    if ([string]::IsNullOrWhiteSpace($Name)) { $Name = [string]$Recipient.Name }

    $Address = [string]$Recipient.PrimarySmtpAddress
    if ([string]::IsNullOrWhiteSpace($Address)) { $Address = [string]$Recipient.WindowsEmailAddress }
    if ([string]::IsNullOrWhiteSpace($Address)) { $Address = [string]$Recipient.ExternalEmailAddress }

    if (-not [string]::IsNullOrWhiteSpace($Address)) {
        return ("{0} <{1}>" -f $Name, $Address)
    }

    return $Name
}

function Resolve-ManagerForwardingRecipient {
    # DESCRIPTION: Resolves and confirms the disabled user's manager as an internal mailbox forwarding recipient.
    # WHY THIS MATTERS: Forwarding to the manager is the most common business-continuity path. Resolving the manager as an Exchange recipient allows the script to use -ForwardingAddress instead of external SMTP forwarding.

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $User
    )

    try {
        $ManagerRef = Get-MgUserManager -UserId $User.Id -ErrorAction Stop
        if ($null -eq $ManagerRef -or [string]::IsNullOrWhiteSpace([string]$ManagerRef.Id)) {
            Write-ChildOutputLine "No manager is assigned to '$($User.UserPrincipalName)'. Please manually enter a forwarding recipient."
            return $null
        }

        $ManagerObj = Get-MgUser -UserId $ManagerRef.Id -Property 'id,displayName,userPrincipalName,mail,accountEnabled' -ErrorAction Stop
        $ManagerAddress = if (-not [string]::IsNullOrWhiteSpace([string]$ManagerObj.Mail)) { [string]$ManagerObj.Mail } else { [string]$ManagerObj.UserPrincipalName }

        if ([string]::IsNullOrWhiteSpace($ManagerAddress)) {
            Write-ChildOutputLine "Manager '$($ManagerObj.DisplayName)' does not have a usable mail address or UPN. Please manually enter a forwarding recipient."
            return $null
        }

        $ManagerRecipient = Resolve-MailForwardingExchangeRecipient -Identity $ManagerAddress
        if ($null -eq $ManagerRecipient -and -not [string]::IsNullOrWhiteSpace([string]$ManagerObj.UserPrincipalName)) {
            $ManagerRecipient = Resolve-MailForwardingExchangeRecipient -Identity ([string]$ManagerObj.UserPrincipalName)
        }

        if ($null -eq $ManagerRecipient) {
            Write-ChildOutputLine "WARNING: Manager found in Entra ID, but '$ManagerAddress' did not resolve to an internal Exchange recipient. Please manually enter a forwarding recipient."
            Write-ChildOutputLine 'The script will only use manager forwarding as option 1 when the manager can be resolved by Exchange and configured with -ForwardingAddress.'
            return $null
        }

        $ManagerDisplay = Get-ExchangeRecipientDisplayText -Recipient $ManagerRecipient
        Write-ChildOutputLine "Manager found as internal Exchange recipient: $ManagerDisplay"

        $Confirm = Read-ChildMenuChoice `
            -Title 'Confirm mailbox forwarding recipient' `
            -Options @("1. Forward mailbox to this manager: $ManagerDisplay",'2. Choose another forwarding recipient') `
            -Prompt 'Press 1 or 2' `
            -ValidChoices @('1','2')

        if ($Confirm -eq '1') {
            $RecipientAddress = [string]$ManagerRecipient.PrimarySmtpAddress
            if ([string]::IsNullOrWhiteSpace($RecipientAddress)) { $RecipientAddress = $ManagerAddress }
            return (New-MailForwardingTargetResult -Mode Internal -Address $RecipientAddress -Recipient $ManagerRecipient)
        }

        return $null
    }
    catch {
        Write-ChildOutputLine "WARNING: Unable to resolve manager for '$($User.UserPrincipalName)'. Please manually enter a forwarding recipient. $(Get-GraphExceptionSummary -ErrorRecord $_)"
        if (Test-GraphExceptionText -ErrorRecord $_ -Pattern '(?i)Insufficient privileges|Authorization_RequestDenied|Forbidden|403') {
            Write-GraphPermissionGuidance `
                -Area 'Resolve manager for mailbox forwarding' `
                -RequiredGraphApplicationPermissions @('User.Read.All', 'Directory.Read.All') `
                -LikelyDirectoryRoles @('User Administrator', 'Directory Reader', 'Global Reader', 'Global Administrator') `
                -ExtraNote 'The offboarding Enterprise Application must be able to read the user manager relationship and manager user object.'
        }
        return $null
    }
}

function Read-ExternalForwardingConfirmation {
    # DESCRIPTION: Requires a second confirmation before setting mailbox forwarding with an external SMTP address.
    # WHY THIS MATTERS: External auto-forwarding can create data-loss and abuse risk. The technician should explicitly confirm when the target is not an internal Exchange recipient.

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Address
    )

    Write-ChildOutputLine "WARNING: '$Address' did not resolve to an internal Exchange recipient."
    Write-ChildOutputLine 'If you continue, Exchange will configure this as external SMTP forwarding by using -ForwardingSmtpAddress.'
    Write-ChildOutputLine 'Use this only when external forwarding is intentionally approved by policy.'

    $ConfirmExternal = Read-ChildMenuChoice `
        -Title 'Confirm external mailbox forwarding' `
        -Options @("1. Continue and forward externally to $Address",'2. Choose another forwarding recipient') `
        -Prompt 'Press 1 or 2' `
        -ValidChoices @('1','2')

    return ($ConfirmExternal -eq '1')
}

function Read-ForwardingRecipient {
    # DESCRIPTION: Prompts for the forwarding recipient, with the disabled user's manager as option 1 and manual entry as option 2.
    # WHY THIS MATTERS: Manager forwarding and manual internal forwarding now use Exchange internal forwarding when possible. External SMTP forwarding requires explicit confirmation.

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $User
    )

    do {
        $Choice = Read-ChildMenuChoice `
            -Title "Choose mailbox forwarding recipient for '$($User.UserPrincipalName)'" `
            -Options @("1. Use the manager of $($User.UserPrincipalName) as the forwarding recipient.",'2. Manually enter the forwarding recipient email address or UPN.') `
            -Prompt 'Enter 1 or 2' `
            -ValidChoices @('1','2')

        switch ($Choice) {
            '1' {
                $ManagerRecipient = Resolve-ManagerForwardingRecipient -User $User
                if ($null -ne $ManagerRecipient) {
                    return $ManagerRecipient
                }
            }
            '2' {
                $ManualRecipient = Read-ChildText -Prompt 'Enter the forwarding email address or UPN'
                if (-not [string]::IsNullOrWhiteSpace($ManualRecipient)) {
                    $ManualRecipient = $ManualRecipient.Trim()
                    $InternalRecipient = Resolve-MailForwardingExchangeRecipient -Identity $ManualRecipient

                    if ($null -ne $InternalRecipient) {
                        $RecipientAddress = [string]$InternalRecipient.PrimarySmtpAddress
                        if ([string]::IsNullOrWhiteSpace($RecipientAddress)) { $RecipientAddress = $ManualRecipient }
                        $Display = Get-ExchangeRecipientDisplayText -Recipient $InternalRecipient
                        Write-ChildOutputLine "Forwarding target resolved as internal Exchange recipient: $Display"
                        return (New-MailForwardingTargetResult -Mode Internal -Address $RecipientAddress -Recipient $InternalRecipient)
                    }

                    if (Read-ExternalForwardingConfirmation -Address $ManualRecipient) {
                        return (New-MailForwardingTargetResult -Mode External -Address $ManualRecipient)
                    }
                }
            }
            Default {
                Write-ChildOutputLine 'Invalid selection. Please enter 1 or 2.'
            }
        }
    } while ($true)
}

function Set-MailForwarding {
    # DESCRIPTION: Prompts whether mailbox forwarding should be configured and, when requested, sets the forwarding address.
    # WHY THIS MATTERS: Internal recipients are configured with -ForwardingAddress so Exchange treats them as internal forwarding. External SMTP forwarding is used only after explicit confirmation.

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$UserId,

        [Parameter(Mandatory = $true)]
        $User
    )

    $MailboxForwardingPrompt = Read-ChildMenuChoice `
        -Title "Mailbox forwarding for '$UserId'" `
        -Options @('1. Set mailbox forwarding','2. Do not set mailbox forwarding') `
        -Prompt 'Press 1 or 2' `
        -ValidChoices @('1','2')

    if ($MailboxForwardingPrompt -ne '1') {
        Write-ChildOutputLine "Mailbox forwarding not configured for '$UserId'."
        return
    }

    $ForwardingTarget = Read-ForwardingRecipient -User $User
    if ($null -eq $ForwardingTarget) {
        Write-ChildOutputLine "Mailbox forwarding not configured for '$UserId' because no forwarding target was selected."
        return
    }

    if ($ForwardingTarget.Mode -eq 'Internal') {
        $Display = Get-ExchangeRecipientDisplayText -Recipient $ForwardingTarget.Recipient
        Write-ChildOutputLine "Setting internal mailbox forwarding for '$UserId' to '$Display'."
        Set-Mailbox -Identity $UserId `
            -DeliverToMailboxAndForward $true `
            -ForwardingAddress $ForwardingTarget.Recipient.DistinguishedName `
            -ForwardingSmtpAddress $null `
            -ErrorAction Stop
        return
    }

    Write-ChildOutputLine "Setting external SMTP mailbox forwarding for '$UserId' to '$($ForwardingTarget.Address)'."
    Set-Mailbox -Identity $UserId `
        -DeliverToMailboxAndForward $true `
        -ForwardingAddress $null `
        -ForwardingSmtpAddress $ForwardingTarget.Address `
        -ErrorAction Stop
}

function RemoveProfilePic {
    # DESCRIPTION: Removes the user's Microsoft 365 profile picture.
    # WHY THIS MATTERS: Removing the profile picture helps visually distinguish disabled accounts and reduces stale user presence across Microsoft 365 experiences.

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $User
    )

    Write-ChildOutputLine "Removing profile picture of '$($User.UserPrincipalName)'"
    Remove-MgUserPhoto -UserId $User.Id -ErrorAction Stop
}

function AutoReply {
    # DESCRIPTION: Enables an automatic reply that tells senders the mailbox is no longer monitored.
    # WHY THIS MATTERS: Auto-replies reduce confusion for internal and external senders and support consistent offboarding communication.

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$UserId
    )

    Write-ChildOutputLine "Setting an automatic reply for emails sent to '$UserId'"

    $AutoReplyMessage = 'This mailbox is no longer being monitored. Your email has been forwarded if applicable.'

    Set-MailboxAutoReplyConfiguration -Identity $UserId `
        -AutoReplyState Enabled `
        -InternalMessage $AutoReplyMessage `
        -ExternalMessage $AutoReplyMessage `
        -ExternalAudience All `
        -ErrorAction Stop
}

function Write-Confirmation {
    # DESCRIPTION: Writes a completion message after the user's offboarding steps finish.
    # WHY THIS MATTERS: A clear completion message helps the technician identify that the account workflow has finished in the transcript log.

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$UserId
    )

    Write-ChildOutputLine "------------------------User '$UserId' has been disabled------------------------"
}

function Disable-Everywhere {
    # DESCRIPTION: Runs the full offboarding workflow for each account entered into the script.
    # WHY THIS MATTERS: This function controls the order of operations so each disabled user receives the same repeatable offboarding steps.

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$TargetIdentity
    )

    foreach ($Target in $TargetIdentity) {
        Write-ChildOutputLine "`n========================================================================"
        Write-ChildOutputLine "Starting offboarding workflow for '$Target'"
        Write-ChildOutputLine "========================================================================"

        $User = Resolve-OffboardingUser -UserId $Target
        if (-not $User) {
            continue
        }

        Invoke-OffboardingStep -Name 'SessionInfo' -ScriptBlock { SessionInfo } -Critical
        Invoke-OffboardingStep -Name 'Disable user account and revoke sessions' -ScriptBlock { DisableUserAccount -User $User } -Critical
        Invoke-OffboardingStep -Name 'Disable registered devices' -ScriptBlock { Disable-UserRegisteredDevices -User $User }

        if ($CancelOrganizedMeetings) {
            Invoke-OffboardingStep -Name 'Cancel organized meetings' -ScriptBlock { CancelMeetings -UserId $Target }
        }
        else {
            Write-ChildOutputLine 'Skipping meeting cancellation. Run with -CancelOrganizedMeetings to enable this optional step.'
        }

        Invoke-OffboardingStep -Name 'Convert mailbox to shared and hide from GAL' -ScriptBlock { ConvertTo-SharedMailbox -UserId $Target }
        Invoke-OffboardingStep -Name 'Update display name' -ScriptBlock { Update-DisplayName -User $User }
        Invoke-OffboardingStep -Name 'Remove Microsoft 365 licenses' -ScriptBlock { Remove-UserLicense -User $User }
        Invoke-OffboardingStep -Name 'Remove from all groups' -ScriptBlock { Remove-UserFromAllGroups -User $User -OriginalInput $Target }
        Invoke-OffboardingStep -Name 'Set mailbox forwarding' -ScriptBlock { Set-MailForwarding -UserId $Target -User $User }
        Invoke-OffboardingStep -Name 'Remove profile picture' -ScriptBlock { RemoveProfilePic -User $User }
        Invoke-OffboardingStep -Name 'Configure automatic reply' -ScriptBlock { AutoReply -UserId $Target }
        Invoke-OffboardingStep -Name 'Write confirmation' -ScriptBlock { Write-Confirmation -UserId $Target }
    }
}

############################################################################
# Main Execution
############################################################################

try {
    Initialize-MOCReportFolder
    Set-ChildProgressPlan -TotalSteps 20
    Update-ChildProgress -Activity 'DisableM365Accounts.ps1' -Percent 1 -Status 'Starting' -CurrentOperation 'Initializing offboarding workflow'

    Invoke-OffboardingStep -Name 'Import required Azure modules' -ScriptBlock { Import-RequiredModules } -Critical
    Invoke-OffboardingStep -Name 'Set default Azure subscription' -ScriptBlock { Set-DefaultAzureSubscription }
    Invoke-OffboardingStep -Name 'Validate Azure Key Vault context' -ScriptBlock { Assert-AzureKeyVaultContext } -Critical

    $ClientSecretCredential = $null
    Invoke-OffboardingStep -Name 'Retrieve Graph client secret credential' -ScriptBlock { $script:ClientSecretCredential = Get-GraphClientSecretCredential } -Critical
    Invoke-OffboardingStep -Name 'Connect to Microsoft Graph using offboarding Enterprise Application' -ScriptBlock { Connect-MicrosoftGraphAppOnly -ClientSecretCredential $script:ClientSecretCredential } -Critical
    Invoke-OffboardingStep -Name 'Validate Exchange Online parent session' -ScriptBlock { Assert-ExchangeOnlineParentSession } -Critical

    Start-ChildProgressStep -Name 'Collect target identities'
    $Targets = Get-TargetIdentities
    if (-not $Targets -or $Targets.Count -eq 0) {
        throw 'No target identities were provided.'
    }
    Complete-ChildProgressStep -Name 'Collect target identities'

    $TargetCount = @($Targets).Count
    $RemainingSteps = [Math]::Max(1, ($TargetCount * 12))
    Set-ChildProgressPlan -TotalSteps ([Math]::Max(([int]$script:ChildProgressStepIndex + $RemainingSteps + 1), [int]$script:ChildProgressTotalSteps))

    Disable-Everywhere -TargetIdentity $Targets
    Complete-ChildProgress -Status 'Complete'
}
catch {
    if ($script:ChildPromptCancellationRequested -or ([string]$_ -eq '__MOC_CHILD_PROMPT_CANCELLED__')) {
        Write-ChildPromptCancellationMessage -Reason $script:ChildPromptCancellationReason
    }
    else {
        Write-ChildOutputLine "ERROR: $_"
        throw
    }
}
finally {
    Write-ChildOutputLine -Message ''
    if ($script:ChildPromptCancellationRequested) {
        Write-ChildOutputLine 'Script execution stopped by technician request.'
        try { Read-ChildEnterToContinue -Message 'Press ENTER or Esc to return to the MOC menu' } catch { }
    }
    else {
        Write-ChildOutputLine 'Script execution complete.'
        try { Read-ChildEnterToContinue -Message 'Press ENTER to return to the MOC menu' } catch { }
    }
}