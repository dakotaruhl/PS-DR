<#
.SYNOPSIS
Create-M365OnboardingUser

.DESCRIPTION
MOC child script that creates Microsoft 365 onboarding user accounts from either a
single HR-style two-column paste block, single-user manual entry, or a multi-user XLSX/CSV onboarding import
file. The script reuses the parent MOC Microsoft Graph session, creates Entra ID
user accounts, maps onboarding fields to standard Entra user attributes, combines
Cost Center and Home Department into the Entra Department attribute, leaves Company Name empty, resolves
and sets the Manager attribute from the Leader value, and can create Temporary
Access Passes that either activate on the DOH date for three days or activate immediately for three days, based on the operator selection. DOH-based TAP activation uses the script default local start time, and UsageLocation defaults to US unless provided in bulk input. Manager ambiguity prompts now allow numbered selection, exit menu numbering is sequential, and automatic UPN selection uses the enterprise naming order before requiring manual entry.

The enterprise workflow is:
- Single paste mode: paste the two-column onboarding block copied from the request.
- Single manual mode: enter Employee Name, Title, DOH, Home Department, Cost Center, Business Unit, Leader, and Office Location through MOC-safe prompts.
- Bulk user mode: import an XLSX or CSV file with one onboarding record per row.
- Template mode: generate an XLSX intake template for repeatable bulk onboarding.

.VERSION
1.0.16

.AUTHOR
Long

.CATEGORY
Entra ID

.OUTPUTFORMAT
XLSX

.REQUIREDGRAPHAPPSCOPES
User.ReadWrite.All
Directory.Read.All
Domain.Read.All
UserAuthenticationMethod.ReadWrite.All
LicenseAssignment.ReadWrite.All
Organization.Read.All

.REQUIREDPOWERSHELLMODULES
Microsoft.Graph.Authentication
Microsoft.Graph.Users
Microsoft.Graph.Identity.DirectoryManagement
Microsoft.Graph.Identity.SignIns
Microsoft.Graph.Users.Actions
ImportExcel

.CREATED
2026-07-08

.LASTMODIFIED
2026-08-12

.CHANGELOG
v1.0.16 - 2026-08-12
- Fixed blank output-line handling so empty separator lines cannot be mis-bound to the severity Level parameter in the MOC run pane.
- Added explicit positional binding for child output/status message parameters to prevent ValidateSet errors when writing blank or positional output.

v1.0.15 - 2026-08-06
- Aligned MOC-safe output/input helper behavior with MOC-ChildScript-Skeleton v1.6.2.
- Added Write-ChildOutputLine -Level support for parent-owned severity highlighting.
- Changed child output/progress fallback behavior to fail closed/no-op instead of leaking raw output outside the MOC panes.
- Updated menu prompts to render once in Area 5 and use parent text input helpers only for Area 7 input.
- Removed child-side duplicate "Selected option" status lines from menu prompts.
- Added q/Esc/exit/cancel handling for prompts so the current onboarding workflow stops cleanly and tells the technician to press Esc or Enter again to return to MOC.
- Corrected ScriptFile metadata from New-M365OnboardingUser.ps1 to Create-M365OnboardingUser.ps1.

v1.0.14 - 2026-07-21
- Updated mailbox license prompt wording to match the MOC child-script standard: enter one or more choices separated by commas, example input, and default selection.

v1.0.13 - 2026-07-21
- Updated mailbox license assignment prompt to support multiple mailbox-capable license selections in one run.
- License assignment now sends all selected SKU IDs in a single Graph license update and records comma-separated selected license details in the workbook.

v1.0.12 - 2026-07-21
- Changed XLSX report and template export to safe worksheet-only mode without Excel structured tables to avoid Excel repair prompts when opening generated workbooks.
- Added workbook package integrity validation after export and before automatic open.

v1.0.11 - 2026-07-21
- Fixed exit handling so choosing Exit from the onboarding mode menu completes gracefully without writing an error.
- Added single-user manual input mode with MOC-safe prompts for the basic onboarding fields.
- Added manual-mode UPN confirmation: the script suggests the first available generated UPN and lets the operator accept it or type a different available UPN.

v1.0.10 - 2026-07-08
- Added mailbox-capable Microsoft 365 license discovery from current tenant subscribed SKUs.
- Added MOC-safe prompt to select no license or one or more mailbox-capable license SKUs for assignment during onboarding.
- Assigns the selected license(s) after user creation and records license assignment status in the workbook.

v1.0.7 - 2026-07-08
- Changed auto-generated UPN order to first initial dot last name, then first name dot last name, then first name dot middle initial dot last name.
- Added manual UPN entry when preferred generated UPN formats are not available.

v1.0.9 - 2026-07-08
- Corrected generated UPN naming standards to firstinitiallastname, then firstname.lastname, then firstname.middleinitial.lastname before manual entry.

1.0.8 - 2026-07-08
- Corrected generated UPN naming standards to firstinitial.lastname, firstname.lastname, then firstname.middleinitial.lastname before manual entry.

v1.0.6 - 2026-07-08
- Changed Entra Department mapping to combine Cost Center and Home Department as "Cost Center - Home Department".
- Stopped populating Entra Company Name from Cost Center; Company Name is intentionally left blank.

v1.0.5 - 2026-07-08
- Removed end-user prompts for TAP activation time and default UsageLocation country code.
- Defaults DOH-based TAP activation to 08:00 local time and default UsageLocation to US unless the import record provides a UsageLocation value.

v1.0.3 - 2026-07-08
- Added Windows clipboard intake for single-user HR paste blocks when the parent MOC session does not expose a multi-line paste helper.
- Added required input validation so blank single-user intake cannot proceed to parsing as an empty Employee Name.

v1.0.2 - 2026-07-08
- Reworked menu selection prompts to write options once to Area 5 and collect input through the MOC text input helper to avoid parent menu-choice redraw output line growth during wheel scrolling.

v1.0.1 - 2026-07-08
- Fixed verified domain sorting syntax that caused a parser error in PowerShell.
- Added TAP activation selection with option 1 as the default DOH-based three-day TAP and option 2 as immediate three-day TAP.
- Updated DOH validation so DOH is required only for DOH-based TAP activation.

v1.0.0 - 2026-07-08
- Initial MOC child script for Microsoft 365 user onboarding.
- Supports single-user paste intake, bulk XLSX/CSV intake, and XLSX template generation.
- Creates Entra ID users with display name, given name, surname, job title, department, office location, and employee type. Department is populated as "Cost Center - Home Department" when both source fields are available; Company Name is intentionally left blank.
- Resolves Leader to Manager by Entra ID display name or UPN and prompts for unresolved leaders.
- Creates DOH-delayed Temporary Access Passes valid for three days when selected.
- Generates XLSX workbook with Summary, Onboarded Users, Review Flags, Errors, Sensitive Access, and Source Records worksheets.
- Applies MOC workbook styling, auto-width, wrapped long columns, and safe Excel text handling.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$UseExistingSession,

    [Parameter(Mandatory = $false)]
    [switch]$SkipSessionValidation,

    [Parameter(Mandatory = $false)]
    [switch]$DoNotOpenOutput,

    [Parameter(Mandatory = $false)]
    [string]$ReportsRoot
)

$ScriptDisplayName = 'Create-M365OnboardingUser'
$ScriptFileName = 'Create-M365OnboardingUser.ps1'
$ScriptVersion = '1.0.16'
$ScriptBuild = '2026.08.12.001'
$ScriptCategory = 'Entra ID'
$RunFolderPrefix = 'M365-Onboarding'
$RequiredGraphScopes = @(
    'User.ReadWrite.All',
    'Directory.Read.All',
    'Domain.Read.All',
    'UserAuthenticationMethod.ReadWrite.All',
    'LicenseAssignment.ReadWrite.All',
    'Organization.Read.All'
)
$RequiredModules = @(
    'Microsoft.Graph.Authentication',
    'Microsoft.Graph.Users',
    'Microsoft.Graph.Identity.DirectoryManagement',
    'Microsoft.Graph.Identity.SignIns',
    'Microsoft.Graph.Users.Actions',
    'ImportExcel'
)
$TotalSteps = 7

$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $script:MyInvocation.MyCommand.Path }
$MOCRootVar = Get-Variable -Name MOC_RootPath -Scope Script -ErrorAction SilentlyContinue
if ($MOCRootVar -and -not [string]::IsNullOrWhiteSpace([string]$MOCRootVar.Value)) {
    $MOCRootPath = [string]$MOCRootVar.Value
}
else {
    $ParentOfScriptDir = Split-Path -Parent $ScriptDir
    if (-not [string]::IsNullOrWhiteSpace($ParentOfScriptDir)) { $MOCRootPath = $ParentOfScriptDir }
    else { $MOCRootPath = $ScriptDir }
}

if ([string]::IsNullOrWhiteSpace($ReportsRoot)) {
    $CurrentScriptReportsRootVar = Get-Variable -Name MOC_CurrentScriptReportsRoot -Scope Script -ErrorAction SilentlyContinue
    if ($CurrentScriptReportsRootVar -and -not [string]::IsNullOrWhiteSpace([string]$CurrentScriptReportsRootVar.Value)) {
        $ReportsRoot = [string]$CurrentScriptReportsRootVar.Value
    }
    else {
        $MOCReportsRootVar = Get-Variable -Name MOC_ReportsRootPath -Scope Script -ErrorAction SilentlyContinue
        if ($MOCReportsRootVar -and -not [string]::IsNullOrWhiteSpace([string]$MOCReportsRootVar.Value)) {
            $ReportsRoot = Join-Path ([string]$MOCReportsRootVar.Value) $ScriptCategory
        }
        else {
            $ReportsRoot = Join-Path (Join-Path $MOCRootPath 'Reports') $ScriptCategory
        }
    }
}

$RunStamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
$ReportsDir = Join-Path $ReportsRoot ("{0}-{1}" -f $RunFolderPrefix, $RunStamp)
$WorkbookPath = Join-Path $ReportsDir ("{0}-{1}.xlsx" -f $RunFolderPrefix, $RunStamp)
$SummaryPath = Join-Path $ReportsDir ("{0}-Summary-{1}.json" -f $RunFolderPrefix, $RunStamp)
$TemplatePath = Join-Path $ReportsDir ("{0}-Import-Template-{1}.xlsx" -f $RunFolderPrefix, $RunStamp)

$script:AuditNotes = [System.Collections.ArrayList]::new()
$script:WorkbookSheets = [System.Collections.ArrayList]::new()
$script:OnboardedRows = [System.Collections.ArrayList]::new()
$script:SensitiveRows = [System.Collections.ArrayList]::new()
$script:ReviewRows = [System.Collections.ArrayList]::new()
$script:ErrorRows = [System.Collections.ArrayList]::new()
$script:SourceRows = [System.Collections.ArrayList]::new()
$script:LicenseRows = [System.Collections.ArrayList]::new()
$script:RunSucceeded = $false
$script:ExitRequested = $false
$script:SelectedMode = ''
$script:CreateTemporaryAccessPass = $true
$script:TemporaryAccessPassLifetimeMinutes = 4320
$script:TemporaryAccessPassActivationMode = 'DOH'
$script:DefaultTapStartTime = '08:00'
$script:DefaultUpnDomain = ''
$script:AccountEnabled = $true
$script:PreferredUsageLocation = 'US'
$script:SelectedMailboxLicenseSkus = @()
$script:SelectedMailboxLicenseName = 'No mailbox/M365 license selected'
$script:ChildPromptCancellationRequested = $false
$script:ChildPromptCancellationReason = ''

$script:Summary = [ordered]@{
    ScriptName = $ScriptDisplayName
    ScriptFile = $ScriptFileName
    Version = $ScriptVersion
    Build = $ScriptBuild
    RunDateTime = (Get-Date).ToString('o')
    OutputFolder = $ReportsDir
    Counts = [ordered]@{}
    Files = [ordered]@{}
    Warnings = [System.Collections.ArrayList]::new()
}

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
    Write-ChildOutputLine 'STOPPED: Create-M365OnboardingUser.ps1 stopped processing the current step because q/Esc was selected.' -Level Warning
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

    Update-ChildProgress -Activity 'Waiting for input' -Percent 0 -Status 'Waiting for technician input.' -CurrentOperation 'Use the MOC input pane.'

    foreach ($CommandName in @('Read-MOCText', 'Read-MOCTextPrompt', 'Read-MOCInputLine')) {
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
                Write-ChildOutputLine "WARNING: Parent MOC text input helper '$CommandName' failed. Trying next available input helper. $($_.Exception.Message)" -Level Warning
            }
        }
    }

    throw 'MOC parent text input helper was not found or failed. Return to MOC and run this child script from the menu so input remains inside the MOC run window.'
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
        [Parameter(Mandatory = $false)][string[]]$ValidChoices = @('1','2'),
        [Parameter(Mandatory = $false)][switch]$AllowExit,
        [Parameter(Mandatory = $false)][string]$DefaultChoice
    )

    $script:LastChildMenuChoice = $null
    $NumericChoices = @($ValidChoices | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ })
    $ExitChoice = if ($AllowExit) {
        if ($NumericChoices.Count -gt 0) { [string](($NumericChoices | Measure-Object -Maximum).Maximum + 1) } else { '0' }
    }
    else { $null }

    Write-ChildOutputLine $Title -Level Prompt
    Write-ChildOutputLine ('-' * $Title.Length) -Level Prompt
    foreach ($Option in $Options) { Write-ChildOutputLine $Option -Level Prompt }
    if ($AllowExit) { Write-ChildOutputLine ("{0}. Exit and return to MOC menu" -f $ExitChoice) -Level Prompt }
    if (-not [string]::IsNullOrWhiteSpace($DefaultChoice)) { Write-ChildOutputLine ("Default selection: {0}" -f $DefaultChoice) -Level Prompt }

    $ChoiceHelp = if ($AllowExit) { (($ValidChoices + @($ExitChoice,'q','Esc')) -join '/') } else { ($ValidChoices -join '/') }
    $PromptText = if (-not [string]::IsNullOrWhiteSpace($DefaultChoice)) {
        ('{0} ({1}; default {2})' -f $Prompt, $ChoiceHelp, $DefaultChoice)
    }
    else {
        ('{0} ({1})' -f $Prompt, $ChoiceHelp)
    }
    Write-ChildOutputLine $PromptText -Level Prompt

    while ($true) {
        Update-ChildProgress -Activity 'Waiting for input' -Percent 0 -Status 'Waiting for user selection.' -CurrentOperation $PromptText

        $ChoiceText = Read-ChildText -Prompt $PromptText -AllowEmpty:([bool](-not [string]::IsNullOrWhiteSpace($DefaultChoice)))
        $ChoiceText = if ($null -eq $ChoiceText) { '' } else { $ChoiceText.Trim() }

        if ([string]::IsNullOrWhiteSpace($ChoiceText) -and -not [string]::IsNullOrWhiteSpace($DefaultChoice)) {
            $ChoiceText = $DefaultChoice
        }

        if ($AllowExit -and $ChoiceText -eq $ExitChoice) {
            $script:LastChildMenuChoice = 'ExitToMenu'
            return $script:LastChildMenuChoice
        }

        if ($ChoiceText -in $ValidChoices) {
            $script:LastChildMenuChoice = $ChoiceText
            # Do not write another "Selected option" line here. Some MOC parent text-input helpers already echo
            # the selected value, and child-side duplication can clutter or break the output pane.
            return $script:LastChildMenuChoice
        }

        $InvalidHelp = if ($AllowExit) { (($ValidChoices + @($ExitChoice,'q','Esc')) -join ', ') } else { ($ValidChoices -join ', ') }
        if (-not [string]::IsNullOrWhiteSpace($DefaultChoice)) {
            Write-ChildOutputLine ("Invalid selection. Please enter {0}, or press Enter for {1}." -f $InvalidHelp, $DefaultChoice) -Level Warning
        }
        else {
            Write-ChildOutputLine ("Invalid selection. Please enter {0}." -f $InvalidHelp) -Level Warning
        }
    }
}

function Get-ChildClipboardText {
    [CmdletBinding()]
    param()

    if (-not (Get-Command Get-Clipboard -ErrorAction SilentlyContinue)) { return '' }
    try {
        $ClipboardText = Get-Clipboard -Raw -ErrorAction Stop
        if ($null -eq $ClipboardText) { return '' }
        return [string]$ClipboardText
    }
    catch {
        try {
            $ClipboardLines = @(Get-Clipboard -ErrorAction Stop)
            return [string]($ClipboardLines -join [Environment]::NewLine)
        }
        catch { return '' }
    }
}

function Read-ChildMultilineText {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Prompt)

    foreach ($CommandName in @('Read-MOCMultiLineText','Read-MOCTextBlock','Read-MOCTextArea','Read-MOCClipboardPaste')) {
        if (Get-Command $CommandName -ErrorAction SilentlyContinue) {
            try {
                $TextBlock = [string](& $CommandName -Prompt $Prompt)
                if (-not [string]::IsNullOrWhiteSpace($TextBlock)) { return $TextBlock }
                Write-ChildOutputLine 'No paste text was received from the multi-line helper.'
            }
            catch { }
        }
    }

    Write-ChildOutputLine 'Multi-line paste helper was not found in the parent MOC session.'
    Write-ChildOutputLine 'For single-user intake, copy the full HR block to the Windows clipboard first.'
    Write-ChildOutputLine 'Then choose option 1 below. This avoids using raw console input outside MOC.'
    Write-ChildOutputLine 'Fallback option 2 accepts one semicolon-delimited key=value line.'
    Write-ChildOutputLine 'Example: Employee Name=Test User; Title=Analyst; DOH=7/14/26; Home Department=IT; Cost Center=227; Leader=Sathya Long; Office Location=Vine'

    $ClipboardAvailable = [bool](Get-Command Get-Clipboard -ErrorAction SilentlyContinue)
    if ($ClipboardAvailable) {
        $SourceChoice = Read-ChildMenuChoice -Title 'Single User Intake Source' -Options @('1. Use current Windows clipboard content','2. Type one semicolon-delimited onboarding line') -Prompt 'Select intake source' -ValidChoices @('1','2') -DefaultChoice '1'
        if ($SourceChoice -eq '1') {
            $ClipboardText = Get-ChildClipboardText
            if ([string]::IsNullOrWhiteSpace($ClipboardText)) {
                Write-ChildOutputLine 'Clipboard is empty or unreadable. Copy the onboarding block now, then press Enter.'
                [void](Read-ChildText -Prompt 'Press Enter after copying the onboarding block to clipboard' -AllowEmpty)
                $ClipboardText = Get-ChildClipboardText
            }
            if ([string]::IsNullOrWhiteSpace($ClipboardText)) {
                throw 'Clipboard intake was selected, but no onboarding text was found. Copy the onboarding block to Windows clipboard and rerun this script, or use bulk import/template mode.'
            }
            Write-ChildStatusLine 'Onboarding paste block captured from Windows clipboard.'
            return $ClipboardText
        }
    }
    else {
        Write-ChildOutputLine 'Get-Clipboard is unavailable in this PowerShell session; using one-line input fallback.'
    }

    return [string](Read-ChildText -Prompt 'Paste one-line onboarding block')
}

function Add-AuditNote {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Severity,
        [Parameter(Mandatory = $true)][string]$Area,
        [Parameter(Mandatory = $true)][string]$Message
    )

    $Row = [pscustomobject][ordered]@{
        Timestamp = (Get-Date).ToString('o')
        Severity = $Severity
        Area = $Area
        Message = $Message
    }
    [void]$script:AuditNotes.Add($Row)
    if ($Severity -match 'Warning|Error') { [void]$script:Summary.Warnings.Add("[$Severity] $Area - $Message") }
    Write-ChildStatusLine ("AUDIT NOTE [{0}] {1} - {2}" -f $Severity, $Area, $Message)
    Write-ChildTranscriptLine ("AUDIT NOTE [{0}] {1} - {2}" -f $Severity, $Area, $Message)
}

function Add-ReviewFlag {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$EmployeeName,
        [Parameter(Mandatory = $true)][string]$Severity,
        [Parameter(Mandatory = $true)][string]$Area,
        [Parameter(Mandatory = $true)][string]$Message,
        [Parameter(Mandatory = $false)][string]$Recommendation = ''
    )

    [void]$script:ReviewRows.Add([pscustomobject][ordered]@{
        EmployeeName = $EmployeeName
        Severity = $Severity
        Area = $Area
        ReviewReason = $Message
        Recommendation = $Recommendation
    })

    if ($Severity -match 'Warning|Error') { [void]$script:Summary.Warnings.Add("[$Severity] $EmployeeName - $Message") }
}

function Add-ErrorRow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$EmployeeName,
        [Parameter(Mandatory = $true)][string]$Stage,
        [Parameter(Mandatory = $true)][string]$Message,
        [Parameter(Mandatory = $false)][string]$Details = ''
    )

    [void]$script:ErrorRows.Add([pscustomobject][ordered]@{
        EmployeeName = $EmployeeName
        Stage = $Stage
        ErrorMessage = $Message
        Details = $Details
        Timestamp = (Get-Date).ToString('o')
    })
}

function Set-MOCUtf8FileContent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Content
    )

    $Parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($Parent) -and -not (Test-Path -LiteralPath $Parent)) {
        New-Item -ItemType Directory -Path $Parent -Force | Out-Null
    }
    $Utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($Path, $Content, $Utf8NoBom)
}

function Get-ReportDisplayPath {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    $Leaf = Split-Path -Leaf $Path
    $RunFolder = Split-Path -Leaf (Split-Path -Parent $Path)
    return ("Reports\{0}\{1}\{2}" -f $ScriptCategory, $RunFolder, $Leaf)
}

function ConvertTo-ExcelSafeText {
    [CmdletBinding()]
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) { return '' }
    $Text = [string]$Value
    $Text = $Text -replace '[\x00-\x08\x0B\x0C\x0E-\x1F]', ' '
    $MaxCellLength = 32000
    if ($Text.Length -gt $MaxCellLength) {
        $Text = $Text.Substring(0, $MaxCellLength) + ' ... [truncated for Excel cell safety]'
    }
    return $Text
}

function ConvertTo-ExcelSafeValue {
    [CmdletBinding()]
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) { return '' }
    if ($Value -is [string]) { return (ConvertTo-ExcelSafeText -Value $Value) }
    if ($Value -is [datetime]) { return $Value.ToString('yyyy-MM-dd HH:mm:ss') }
    if ($Value -is [bool]) { return $Value.ToString() }
    if ($Value -is [int] -or $Value -is [long] -or $Value -is [double] -or $Value -is [decimal]) { return $Value }

    if ($Value -is [System.Collections.IDictionary]) {
        $Parts = foreach ($Key in $Value.Keys) { '{0}={1}' -f $Key, (ConvertTo-ExcelSafeValue -Value $Value[$Key]) }
        return (ConvertTo-ExcelSafeText -Value (@($Parts) -join '; '))
    }

    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        $Parts = foreach ($Item in $Value) { if ($null -ne $Item) { [string](ConvertTo-ExcelSafeValue -Value $Item) } }
        return (ConvertTo-ExcelSafeText -Value (@($Parts) -join '; '))
    }

    try {
        $Json = $Value | ConvertTo-Json -Depth 12 -Compress -ErrorAction Stop
        if (-not [string]::IsNullOrWhiteSpace($Json) -and $Json -notmatch '^".*"$') { return (ConvertTo-ExcelSafeText -Value $Json) }
    }
    catch { }
    return (ConvertTo-ExcelSafeText -Value $Value)
}

function ConvertTo-ExcelSafeRows {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)][AllowNull()]$Rows,
        [Parameter(Mandatory = $false)][string[]]$ColumnOrder = @()
    )

    $InputRows = @($Rows)
    $Columns = [System.Collections.ArrayList]::new()
    foreach ($Column in @($ColumnOrder)) {
        if (-not [string]::IsNullOrWhiteSpace($Column) -and -not $Columns.Contains($Column)) { [void]$Columns.Add($Column) }
    }

    if ($InputRows.Count -eq 0) {
        if ($Columns.Count -eq 0) { [void]$Columns.Add('Note') }
        $Object = [ordered]@{}
        foreach ($Column in $Columns) { $Object[$Column] = '' }
        if ($Object.Contains('Note')) { $Object['Note'] = 'No rows returned for this worksheet.' }
        elseif ($Columns.Count -gt 0) { $Object[$Columns[0]] = 'No rows returned for this worksheet.' }
        return @([pscustomobject]$Object)
    }

    foreach ($Row in $InputRows) {
        if ($null -eq $Row) { continue }
        foreach ($Property in @($Row.PSObject.Properties)) {
            if (-not [string]::IsNullOrWhiteSpace($Property.Name) -and -not $Columns.Contains($Property.Name)) { [void]$Columns.Add($Property.Name) }
        }
    }

    if ($Columns.Count -eq 0) { [void]$Columns.Add('Value') }

    $Output = foreach ($Row in $InputRows) {
        $Object = [ordered]@{}
        foreach ($Column in $Columns) {
            $Value = $null
            if ($null -ne $Row) {
                $Property = $Row.PSObject.Properties[$Column]
                if ($null -ne $Property) { $Value = $Property.Value }
            }
            $Object[$Column] = ConvertTo-ExcelSafeValue -Value $Value
        }
        [pscustomobject]$Object
    }
    return @($Output)
}

function Get-SafeExcelWorksheetName {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Name)

    $Safe = $Name -replace '[:\\/\?\*\[\]]', ' '
    $Safe = ($Safe -replace '\s+', ' ').Trim()
    if ([string]::IsNullOrWhiteSpace($Safe)) { $Safe = 'Sheet' }
    if ($Safe.Length -gt 31) { $Safe = $Safe.Substring(0, 31) }
    return $Safe
}

function Get-SafeExcelTableName {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Name)

    $Safe = $Name -replace '[^A-Za-z0-9_]', '_'
    $Safe = $Safe.Trim('_')
    if ([string]::IsNullOrWhiteSpace($Safe)) { $Safe = 'Table1' }
    if ($Safe -notmatch '^[A-Za-z_]') { $Safe = 'T_' + $Safe }
    if ($Safe.Length -gt 200) { $Safe = $Safe.Substring(0, 200) }
    return $Safe
}

function Add-WorkbookWorksheet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)]$Rows,
        [Parameter(Mandatory = $false)][string[]]$ColumnOrder = @(),
        [Parameter(Mandatory = $false)][string]$Description = ''
    )

    $SafeRows = @(ConvertTo-ExcelSafeRows -Rows $Rows -ColumnOrder $ColumnOrder)
    [void]$script:WorkbookSheets.Add([pscustomobject][ordered]@{
        Name = $Name
        Rows = $SafeRows
        ColumnOrder = $ColumnOrder
        Description = $Description
    })
    $script:Summary.Counts[$Name] = $SafeRows.Count
    Write-ChildStatusLine ("Staged {0} row(s) for worksheet '{1}'." -f $SafeRows.Count, $Name)
}

function Assert-ImportExcelAvailable {
    [CmdletBinding()]
    param()

    if (-not (Get-Command Export-Excel -ErrorAction SilentlyContinue)) {
        try { Import-Module ImportExcel -ErrorAction Stop }
        catch {
            throw "The ImportExcel PowerShell module is required. Install it for the account running MOC with: Install-Module ImportExcel -Scope CurrentUser. Details: $($_.Exception.Message)"
        }
    }
}

function Get-WorkbookSummaryRows {
    [CmdletBinding()]
    param()

    $Rows = [System.Collections.ArrayList]::new()
    [void]$Rows.Add([pscustomobject][ordered]@{ Section = 'Run'; Name = 'Script'; Count = ''; Worksheet = ''; Description = 'Script name.'; Value = $ScriptDisplayName })
    [void]$Rows.Add([pscustomobject][ordered]@{ Section = 'Run'; Name = 'Version'; Count = ''; Worksheet = ''; Description = 'Script version.'; Value = $ScriptVersion })
    [void]$Rows.Add([pscustomobject][ordered]@{ Section = 'Run'; Name = 'Build'; Count = ''; Worksheet = ''; Description = 'Script build identifier.'; Value = $ScriptBuild })
    [void]$Rows.Add([pscustomobject][ordered]@{ Section = 'Run'; Name = 'Generated'; Count = ''; Worksheet = ''; Description = 'Report generation timestamp.'; Value = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') })
    [void]$Rows.Add([pscustomobject][ordered]@{ Section = 'Run'; Name = 'Mode'; Count = ''; Worksheet = ''; Description = 'Selected onboarding mode.'; Value = $script:SelectedMode })
    [void]$Rows.Add([pscustomobject][ordered]@{ Section = 'Run'; Name = 'OutputFolder'; Count = ''; Worksheet = ''; Description = 'Folder where all output files were written.'; Value = $ReportsDir })
    [void]$Rows.Add([pscustomobject][ordered]@{ Section = 'TAP'; Name = 'CreateTAP'; Count = ''; Worksheet = ''; Description = 'Whether Temporary Access Pass creation was requested.'; Value = [string]$script:CreateTemporaryAccessPass })
    [void]$Rows.Add([pscustomobject][ordered]@{ Section = 'TAP'; Name = 'ActivationMode'; Count = ''; Worksheet = ''; Description = 'TAP activation mode selected for this run.'; Value = [string]$script:TemporaryAccessPassActivationMode })
    [void]$Rows.Add([pscustomobject][ordered]@{ Section = 'TAP'; Name = 'LifetimeMinutes'; Count = ''; Worksheet = ''; Description = 'Temporary Access Pass lifetime. 4320 minutes equals 3 days.'; Value = $script:TemporaryAccessPassLifetimeMinutes })
    [void]$Rows.Add([pscustomobject][ordered]@{ Section = 'License'; Name = 'SelectedMailboxLicense'; Count = ''; Worksheet = ''; Description = 'Mailbox-capable Microsoft 365 license selected for assignment.'; Value = [string]$script:SelectedMailboxLicenseName })
    foreach ($Sheet in @($script:WorkbookSheets)) {
        [void]$Rows.Add([pscustomobject][ordered]@{
            Section = 'Worksheet'
            Name = $Sheet.Name
            Count = @($Sheet.Rows).Count
            Worksheet = (Get-SafeExcelWorksheetName -Name $Sheet.Name)
            Description = $Sheet.Description
            Value = ''
        })
    }
    return @($Rows)
}

function Set-MOCWorkbookStyle {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    try {
        $Package = Open-ExcelPackage -Path $Path
        foreach ($Worksheet in $Package.Workbook.Worksheets) {
            if ($null -eq $Worksheet.Dimension) { continue }
            $HeaderRange = $Worksheet.Cells[1, 1, 1, $Worksheet.Dimension.End.Column]
            $HeaderRange.Style.Font.Bold = $true
            $HeaderRange.Style.Font.Color.SetColor([System.Drawing.Color]::White)
            $HeaderRange.Style.Fill.PatternType = [OfficeOpenXml.Style.ExcelFillStyle]::Solid
            $HeaderRange.Style.Fill.BackgroundColor.SetColor([System.Drawing.Color]::FromArgb(31, 78, 121))
            $Worksheet.View.FreezePanes(2, 1)

            for ($Column = 1; $Column -le $Worksheet.Dimension.End.Column; $Column++) {
                $Worksheet.Column($Column).AutoFit()
                if ($Worksheet.Column($Column).Width -gt 70) { $Worksheet.Column($Column).Width = 70 }
            }

            $LongColumnNames = @('ReviewReason','Recommendation','ErrorMessage','Details','TemporaryAccessPass','InitialPassword','SourceText','Notes','Description','Value')
            for ($Column = 1; $Column -le $Worksheet.Dimension.End.Column; $Column++) {
                $HeaderText = [string]$Worksheet.Cells[1, $Column].Text
                if ($LongColumnNames -contains $HeaderText) {
                    $Worksheet.Column($Column).Style.WrapText = $true
                    if ($Worksheet.Column($Column).Width -lt 35) { $Worksheet.Column($Column).Width = 35 }
                }
            }
            $Worksheet.TabColor = [System.Drawing.Color]::FromArgb(91, 155, 213)
        }
        Close-ExcelPackage $Package
    }
    catch {
        Add-AuditNote -Severity Warning -Area 'Workbook formatting' -Message ("Workbook was exported, but post-formatting could not be applied. Details: {0}" -f $_.Exception.Message)
    }
}


function Test-XlsxPackageIntegrity {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { throw "Workbook package was not found: $Path" }
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
        $Archive = [System.IO.Compression.ZipFile]::OpenRead($Path)
        try {
            $RequiredEntries = @('[Content_Types].xml','xl/workbook.xml')
            foreach ($EntryName in $RequiredEntries) {
                $Entry = $Archive.Entries | Where-Object { $_.FullName -eq $EntryName } | Select-Object -First 1
                if ($null -eq $Entry) { throw "Required XLSX package entry is missing: $EntryName" }
                if ($Entry.Length -le 0) { throw "Required XLSX package entry is empty: $EntryName" }
            }
        }
        finally { $Archive.Dispose() }
    }
    catch {
        throw "Workbook package integrity validation failed. Excel may show a repair prompt. Details: $($_.Exception.Message)"
    }
}

function Export-MOCWorkbook {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $false)][switch]$OpenAfterExport
    )

    Assert-ImportExcelAvailable
    $WorkbookDirectory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $WorkbookDirectory)) { New-Item -ItemType Directory -Path $WorkbookDirectory -Force | Out-Null }
    if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue }

    $SummaryRows = @(ConvertTo-ExcelSafeRows -Rows @(Get-WorkbookSummaryRows) -ColumnOrder @('Section','Name','Count','Worksheet','Description','Value'))
    $SummaryRows | Export-Excel -Path $Path -WorksheetName 'Summary' -AutoSize -FreezeTopRow -BoldTopRow -ClearSheet

    $UsedTables = @{ Summary = $true }
    $UsedWorksheets = @{ Summary = $true }
    foreach ($Sheet in @($script:WorkbookSheets)) {
        $WorksheetNameBase = Get-SafeExcelWorksheetName -Name ([string]$Sheet.Name)
        $WorksheetName = $WorksheetNameBase
        $WorksheetSuffix = 1
        while ($UsedWorksheets.ContainsKey($WorksheetName)) {
            $WorksheetSuffix++
            $SuffixText = " $WorksheetSuffix"
            $BaseMaxLength = 31 - $SuffixText.Length
            if ($BaseMaxLength -lt 1) { $BaseMaxLength = 1 }
            $ShortBase = if ($WorksheetNameBase.Length -gt $BaseMaxLength) { $WorksheetNameBase.Substring(0, $BaseMaxLength) } else { $WorksheetNameBase }
            $WorksheetName = $ShortBase + $SuffixText
        }
        $UsedWorksheets[$WorksheetName] = $true

        $TableNameBase = Get-SafeExcelTableName -Name $WorksheetName
        $TableName = $TableNameBase
        $Suffix = 1
        while ($UsedTables.ContainsKey($TableName)) {
            $Suffix++
            $TableName = Get-SafeExcelTableName -Name ("{0}_{1}" -f $TableNameBase, $Suffix)
        }
        $UsedTables[$TableName] = $true

        $Rows = @(ConvertTo-ExcelSafeRows -Rows @($Sheet.Rows) -ColumnOrder @($Sheet.ColumnOrder))
        Write-ChildStatusLine ("Writing worksheet '{0}' ({1} row(s))" -f $WorksheetName, $Rows.Count)
        $Rows | Export-Excel -Path $Path -WorksheetName $WorksheetName -AutoSize -FreezeTopRow -BoldTopRow -Append
    }

    Set-MOCWorkbookStyle -Path $Path
    Test-XlsxPackageIntegrity -Path $Path
    if (-not (Test-Path -LiteralPath $Path)) { throw "Workbook was not found after export: $Path" }
    $WorkbookItem = Get-Item -LiteralPath $Path -ErrorAction Stop
    if ($WorkbookItem.Length -le 0) { throw "Workbook file was created but its size is 0 bytes: $Path" }
    $script:Summary.Files['Workbook'] = $Path
    Write-ChildStatusLine ("Excel workbook written and package-validated -> {0}" -f (Get-ReportDisplayPath -Path $Path))
    if ($OpenAfterExport) { Open-MOCOutputFile -Path $Path -Description 'Excel workbook' }
    return $Path
}

function Open-MOCOutputFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $false)][string]$Description = 'output file'
    )

    if ($DoNotOpenOutput) {
        Write-ChildStatusLine ("Automatic open skipped for {0} because -DoNotOpenOutput was specified." -f $Description)
        return
    }
    try {
        if (-not (Test-Path -LiteralPath $Path)) {
            Add-AuditNote -Severity Warning -Area 'Open output file' -Message ("Could not open {0}; file was not found: {1}" -f $Description, $Path)
            return
        }
        Invoke-Item -LiteralPath $Path -ErrorAction Stop
        Write-ChildStatusLine ("Opened {0}." -f $Description)
    }
    catch {
        Add-AuditNote -Severity Warning -Area 'Open output file' -Message ("{0} was created but could not be opened automatically. {1}" -f $Description, $_.Exception.Message)
    }
}

function Assert-RequiredModules {
    [CmdletBinding()]
    param()

    $Missing = [System.Collections.ArrayList]::new()
    foreach ($ModuleName in $RequiredModules) {
        if (-not (Get-Module -ListAvailable -Name $ModuleName)) { [void]$Missing.Add($ModuleName) }
    }

    if ($Missing.Count -gt 0) {
        $InstallText = ($Missing | ForEach-Object { "Install-Module $_ -Scope CurrentUser" }) -join '; '
        throw "Missing required PowerShell module(s): $($Missing -join ', '). Remediation: $InstallText. Then return to MOC and rerun the script."
    }

    foreach ($ModuleName in $RequiredModules) {
        Import-Module $ModuleName -ErrorAction Stop
    }
    Write-ChildStatusLine ("Validated required modules: {0}" -f ($RequiredModules -join ', '))
}

function Get-MOCGraphConnectionMode {
    try {
        if (-not (Get-Command Get-MgContext -ErrorAction SilentlyContinue)) { return 'NotConnected' }
        $Context = Get-MgContext -ErrorAction SilentlyContinue
        if ($null -eq $Context) { return 'NotConnected' }
        if (-not [string]::IsNullOrWhiteSpace([string]$Context.Account)) { return 'Delegated' }
        if (-not [string]::IsNullOrWhiteSpace([string]$Context.ClientId) -and -not [string]::IsNullOrWhiteSpace([string]$Context.TenantId)) { return 'AppOnly' }
        return 'Unknown'
    }
    catch { return 'Unknown' }
}

function Assert-MOCGraphSession {
    [CmdletBinding()]
    param()

    if ($SkipSessionValidation -or $UseExistingSession) {
        Write-ChildStatusLine 'Using existing Microsoft Graph session by parameter.'
    }

    if (-not (Get-Command Get-MgContext -ErrorAction SilentlyContinue)) {
        throw "Microsoft Graph context is not available. Return to MOC, press A to authenticate, and rerun this script. Required Graph permissions: $($RequiredGraphScopes -join ', ')."
    }

    $Context = Get-MgContext -ErrorAction SilentlyContinue
    if ($null -eq $Context) {
        throw "Microsoft Graph session was not detected. Return to MOC, press A to authenticate, and rerun this script. Required Graph permissions: $($RequiredGraphScopes -join ', ')."
    }

    $Mode = Get-MOCGraphConnectionMode
    if ($Mode -eq 'Delegated') {
        $AvailableScopes = @($Context.Scopes)
        $MissingScopes = @($RequiredGraphScopes | Where-Object { $AvailableScopes -notcontains $_ })
        if ($MissingScopes.Count -gt 0) {
            throw "Microsoft Graph delegated session is missing required scope(s): $($MissingScopes -join ', '). Grant these permissions to the MOC app registration, provide admin consent, return to MOC, press A to authenticate, and rerun this script."
        }
        Write-ChildStatusLine ("Validated Microsoft Graph delegated session for {0}." -f $Context.Account)
    }
    elseif ($Mode -eq 'AppOnly') {
        Write-ChildStatusLine ("Graph app-only session detected. Required app permissions: {0}" -f ($RequiredGraphScopes -join ', '))
    }
    else {
        throw 'Microsoft Graph connection state is unknown. Return to MOC, press A to authenticate, and rerun this script.'
    }
}

function ConvertTo-SafeODataString {
    [CmdletBinding()]
    param([Parameter(Mandatory = $false)][AllowNull()][string]$Value)

    if ($null -eq $Value) { return '' }
    return $Value.Replace("'", "''")
}

function Normalize-OnboardingKey {
    [CmdletBinding()]
    param([Parameter(Mandatory = $false)][AllowNull()][string]$Key)

    $Safe = ([string]$Key).Trim().ToLowerInvariant()
    $Safe = $Safe -replace '[^a-z0-9]', ''
    switch ($Safe) {
        'employeename' { return 'EmployeeName' }
        'displayname' { return 'EmployeeName' }
        'eecontractor' { return 'EmployeeType' }
        'employeetype' { return 'EmployeeType' }
        'title' { return 'Title' }
        'jobtitle' { return 'Title' }
        'doh' { return 'DOH' }
        'dateofhire' { return 'DOH' }
        'homedepartment' { return 'HomeDepartment' }
        'department' { return 'HomeDepartment' }
        'costcenter' { return 'CostCenter' }
        'companyname' { return 'CostCenter' }
        'businessunit' { return 'BusinessUnit' }
        'leader' { return 'Leader' }
        'manager' { return 'Leader' }
        'managerupn' { return 'ManagerUPN' }
        'officelocation' { return 'OfficeLocation' }
        'office' { return 'OfficeLocation' }
        'laptoptype' { return 'LaptopType' }
        'cellyn' { return 'CellYN' }
        'cellphoneyn' { return 'CellYN' }
        'companyvehicleyn' { return 'CompanyVehicleYN' }
        'workingremotewfh' { return 'WorkingRemoteWFH' }
        'wfh' { return 'WorkingRemoteWFH' }
        'upn' { return 'UserPrincipalName' }
        'userprincipalname' { return 'UserPrincipalName' }
        'mailnickname' { return 'MailNickname' }
        'alias' { return 'MailNickname' }
        'usagelocation' { return 'UsageLocation' }
        default { return $Key }
    }
}

function New-EmptyOnboardingRecord {
    [CmdletBinding()]
    param()

    return [ordered]@{
        EmployeeName = ''
        EmployeeType = ''
        Title = ''
        DOH = ''
        HomeDepartment = ''
        CostCenter = ''
        BusinessUnit = ''
        Leader = ''
        ManagerUPN = ''
        OfficeLocation = ''
        LaptopType = ''
        CellYN = ''
        CompanyVehicleYN = ''
        WorkingRemoteWFH = ''
        UserPrincipalName = ''
        MailNickname = ''
        UsageLocation = ''
        SourceText = ''
    }
}

function Parse-OnboardingPasteBlock {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$PasteText)

    $Record = New-EmptyOnboardingRecord
    $Record.SourceText = $PasteText
    $NormalizedText = $PasteText -replace "`r`n", "`n"
    $Segments = [System.Collections.ArrayList]::new()

    foreach ($Line in ($NormalizedText -split "`n")) {
        $Trimmed = $Line.Trim()
        if ([string]::IsNullOrWhiteSpace($Trimmed)) { continue }
        if ($Trimmed -match ';') {
            foreach ($Part in ($Trimmed -split ';')) {
                if (-not [string]::IsNullOrWhiteSpace($Part.Trim())) { [void]$Segments.Add($Part.Trim()) }
            }
        }
        else {
            [void]$Segments.Add($Trimmed)
        }
    }

    foreach ($Segment in @($Segments)) {
        $Key = ''
        $Value = ''
        if ($Segment -match "^(?<key>[^\t:=]+)[\t:=]+(?<value>.*)$") {
            $Key = $matches.key.Trim()
            $Value = $matches.value.Trim()
        }
        elseif ($Segment -match "^(?<key>Employee Name|EE/Contractor|Title|DOH|Home Department|Cost Center|Business Unit|Leader|Office Location|Laptop Type|Cell Y/N|Company Vehicle Y/N|Working Remote/WFH)\s{2,}(?<value>.*)$") {
            $Key = $matches.key.Trim()
            $Value = $matches.value.Trim()
        }
        else {
            Add-ReviewFlag -EmployeeName '' -Severity Warning -Area 'Input parsing' -Message ("Could not parse input line: {0}" -f $Segment) -Recommendation 'Use tab, colon, equals sign, or semicolon key=value formatting.'
            continue
        }

        $NormalizedKey = Normalize-OnboardingKey -Key $Key
        if ($Record.Contains($NormalizedKey)) { $Record[$NormalizedKey] = $Value }
        else {
            Add-ReviewFlag -EmployeeName $Record.EmployeeName -Severity Informational -Area 'Unmapped input' -Message ("Input key was not mapped to Entra ID: {0}" -f $Key) -Recommendation 'Add a mapping if this value should be written to Entra ID.'
        }
    }

    if ([string]::IsNullOrWhiteSpace($Record.EmployeeName)) {
        throw 'No Employee Name was parsed from the onboarding input. For single-user mode, copy the full two-column HR block to the Windows clipboard and choose clipboard intake, or enter one semicolon-delimited key=value line.'
    }

    return [pscustomobject]$Record
}

function Convert-ImportRowToOnboardingRecord {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Row)

    $Record = New-EmptyOnboardingRecord
    foreach ($Property in @($Row.PSObject.Properties)) {
        $NormalizedKey = Normalize-OnboardingKey -Key $Property.Name
        if ($Record.Contains($NormalizedKey)) { $Record[$NormalizedKey] = [string]$Property.Value }
    }
    $Record.SourceText = 'Bulk import row'
    return [pscustomobject]$Record
}

function Split-EmployeeName {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$DisplayName)

    $Clean = ($DisplayName -replace '\s+', ' ').Trim()
    if ([string]::IsNullOrWhiteSpace($Clean)) {
        return [pscustomobject]@{ GivenName = ''; MiddleInitial = ''; Surname = '' }
    }

    $Parts = @($Clean -split ' ' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($Parts.Count -eq 1) {
        return [pscustomobject]@{ GivenName = $Parts[0]; MiddleInitial = ''; Surname = '' }
    }

    $Given = $Parts[0]
    $Surname = $Parts[$Parts.Count - 1]
    $MiddleInitial = ''
    if ($Parts.Count -gt 2 -and -not [string]::IsNullOrWhiteSpace($Parts[1])) {
        $MiddleInitial = ([string]$Parts[1]).Substring(0, 1)
    }

    return [pscustomobject]@{ GivenName = $Given; MiddleInitial = $MiddleInitial; Surname = $Surname }
}

function ConvertTo-MailAlias {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Value)

    $Text = $Value.Normalize([System.Text.NormalizationForm]::FormD)
    $Builder = [System.Text.StringBuilder]::new()
    foreach ($Char in $Text.ToCharArray()) {
        $Category = [System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($Char)
        if ($Category -ne [System.Globalization.UnicodeCategory]::NonSpacingMark) { [void]$Builder.Append($Char) }
    }
    $Alias = $Builder.ToString().Normalize([System.Text.NormalizationForm]::FormC).ToLowerInvariant()
    $Alias = $Alias -replace "['`"]", ''
    $Alias = $Alias -replace '[^a-z0-9._-]', '.'
    $Alias = $Alias -replace '\.+', '.'
    $Alias = $Alias.Trim('.')
    if ([string]::IsNullOrWhiteSpace($Alias)) { $Alias = 'new.user' }
    if ($Alias.Length -gt 60) { $Alias = $Alias.Substring(0, 60).Trim('.') }
    return $Alias
}

function New-StrongRandomPassword {
    [CmdletBinding()]
    param([Parameter(Mandatory = $false)][int]$Length = 24)

    $Upper = 'ABCDEFGHJKLMNPQRSTUVWXYZ'.ToCharArray()
    $Lower = 'abcdefghijkmnopqrstuvwxyz'.ToCharArray()
    $Digits = '23456789'.ToCharArray()
    $Symbols = '!@#$%^&*-_+='.ToCharArray()
    $All = @($Upper + $Lower + $Digits + $Symbols)

    function Get-RandomCharFromSet {
        param([char[]]$Set)
        $Bytes = [byte[]]::new(4)
        [System.Security.Cryptography.RandomNumberGenerator]::Fill($Bytes)
        $Number = [BitConverter]::ToUInt32($Bytes, 0)
        return $Set[$Number % $Set.Length]
    }

    $Chars = [System.Collections.Generic.List[char]]::new()
    [void]$Chars.Add((Get-RandomCharFromSet -Set $Upper))
    [void]$Chars.Add((Get-RandomCharFromSet -Set $Lower))
    [void]$Chars.Add((Get-RandomCharFromSet -Set $Digits))
    [void]$Chars.Add((Get-RandomCharFromSet -Set $Symbols))
    while ($Chars.Count -lt $Length) { [void]$Chars.Add((Get-RandomCharFromSet -Set $All)) }

    for ($Index = 0; $Index -lt $Chars.Count; $Index++) {
        $Bytes = [byte[]]::new(4)
        [System.Security.Cryptography.RandomNumberGenerator]::Fill($Bytes)
        $SwapIndex = [BitConverter]::ToUInt32($Bytes, 0) % $Chars.Count
        $Temp = $Chars[$Index]
        $Chars[$Index] = $Chars[$SwapIndex]
        $Chars[$SwapIndex] = $Temp
    }

    return -join $Chars
}

function Resolve-DateOfHire {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Value,
        [Parameter(Mandatory = $true)][string]$EmployeeName
    )

    if ([string]::IsNullOrWhiteSpace($Value)) { throw "DOH is required for $EmployeeName because TAP activation is based on DOH." }
    $Culture = [System.Globalization.CultureInfo]::GetCultureInfo('en-US')
    $Styles = [System.Globalization.DateTimeStyles]::AssumeLocal
    $Formats = @('M/d/yy','M/d/yyyy','MM/dd/yy','MM/dd/yyyy','yyyy-MM-dd')
    $Parsed = [datetime]::MinValue
    if ([datetime]::TryParseExact($Value.Trim(), $Formats, $Culture, $Styles, [ref]$Parsed)) { return $Parsed.Date }
    if ([datetime]::TryParse($Value.Trim(), $Culture, $Styles, [ref]$Parsed)) { return $Parsed.Date }
    throw "Unable to parse DOH '$Value' for $EmployeeName. Use a date such as 7/14/26 or 2026-07-14."
}

function Get-TapStartDateTimeUtc {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][datetime]$DateOfHire,
        [Parameter(Mandatory = $true)][string]$StartTimeText
    )

    $Hour = 8
    $Minute = 0
    if (-not [string]::IsNullOrWhiteSpace($StartTimeText)) {
        if ($StartTimeText -match '^(?<hour>\d{1,2})(:(?<minute>\d{2}))?$') {
            $Hour = [int]$matches.hour
            $Minute = if ($matches.minute) { [int]$matches.minute } else { 0 }
        }
        else {
            throw "Invalid TAP start time '$StartTimeText'. Use HH:mm, such as 08:00."
        }
    }
    if ($Hour -lt 0 -or $Hour -gt 23 -or $Minute -lt 0 -or $Minute -gt 59) { throw "Invalid TAP start time '$StartTimeText'. Use HH:mm." }
    $LocalStart = [datetime]::SpecifyKind($DateOfHire.Date.AddHours($Hour).AddMinutes($Minute), [System.DateTimeKind]::Local)
    return $LocalStart.ToUniversalTime()
}

function Get-VerifiedUpnDomains {
    [CmdletBinding()]
    param()

    $Domains = @(Get-MgDomain -All -ErrorAction Stop | Where-Object { $_.IsVerified -eq $true })
    $Preferred = @($Domains | Where-Object { $_.IsDefault -eq $true -or $_.IsInitial -eq $false } | Sort-Object -Property IsDefault -Descending)
    if ($Preferred.Count -eq 0) { $Preferred = $Domains }
    return @($Preferred | Sort-Object -Property @{ Expression = 'IsDefault'; Descending = $true }, @{ Expression = 'Id'; Ascending = $true })
}

function Select-DefaultUpnDomain {
    [CmdletBinding()]
    param()

    $Domains = @(Get-VerifiedUpnDomains)
    if ($Domains.Count -eq 0) { throw 'No verified Entra ID domains were returned. Cannot generate a UPN domain.' }

    Write-ChildOutputLine 'Available verified Entra ID domains:'
    for ($Index = 0; $Index -lt $Domains.Count; $Index++) {
        $Marker = if ($Domains[$Index].IsDefault) { ' default' } else { '' }
        Write-ChildOutputLine ("{0}. {1}{2}" -f ($Index + 1), $Domains[$Index].Id, $Marker)
    }

    $ValidChoices = 1..([Math]::Min($Domains.Count, 9)) | ForEach-Object { [string]$_ }
    if ($Domains.Count -gt 9) { Write-ChildOutputLine 'Only the first 9 domains are selectable in this MOC-safe menu.' }
    $Choice = Read-ChildMenuChoice -Title 'Default UPN Domain' -Options @('Select the domain used when UPN is not supplied in the onboarding input.') -Prompt 'Select the default UPN domain number' -ValidChoices $ValidChoices -AllowExit
    if ($Choice -eq 'ExitToMenu') { return '__MOC_EXIT__' }
    $Selected = $Domains[[int]$Choice - 1].Id
    Write-ChildStatusLine ("Default UPN domain selected: {0}" -f $Selected)
    return $Selected
}

function Test-GraphUserExists {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$UserPrincipalName)

    try {
        $Existing = Get-MgUser -UserId $UserPrincipalName -Property Id -ErrorAction Stop
        return ($null -ne $Existing)
    }
    catch {
        if ($_.Exception.Message -match 'Request_ResourceNotFound|ResourceNotFound|not found') { return $false }
        return $false
    }
}

function New-UniqueUserPrincipalName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$EmployeeName,
        [Parameter(Mandatory = $true)][string]$Domain,
        [Parameter(Mandatory = $false)][string]$PreferredAlias = ''
    )

    $NameParts = Split-EmployeeName -DisplayName $EmployeeName
    $CandidateAliases = [System.Collections.Generic.List[string]]::new()

    $FirstName = if ($null -ne $NameParts.GivenName) { ([string]$NameParts.GivenName).Trim() } else { '' }
    $MiddleInitial = if ($null -ne $NameParts.MiddleInitial) { ([string]$NameParts.MiddleInitial).Trim() } else { '' }
    $LastName = if ($null -ne $NameParts.Surname) { ([string]$NameParts.Surname).Trim() } else { '' }

    if (-not [string]::IsNullOrWhiteSpace($FirstName) -and -not [string]::IsNullOrWhiteSpace($LastName)) {
        [void]$CandidateAliases.Add((ConvertTo-MailAlias -Value (('{0}{1}' -f $FirstName.Substring(0, 1), $LastName))))
        [void]$CandidateAliases.Add((ConvertTo-MailAlias -Value (('{0}.{1}' -f $FirstName, $LastName))))
        if (-not [string]::IsNullOrWhiteSpace($MiddleInitial)) {
            [void]$CandidateAliases.Add((ConvertTo-MailAlias -Value (('{0}.{1}.{2}' -f $FirstName, $MiddleInitial.Substring(0, 1), $LastName))))
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($PreferredAlias)) {
        $PreferredCandidate = ConvertTo-MailAlias -Value $PreferredAlias
        if (-not $CandidateAliases.Contains($PreferredCandidate)) { [void]$CandidateAliases.Add($PreferredCandidate) }
    }

    if ($CandidateAliases.Count -eq 0) {
        [void]$CandidateAliases.Add((ConvertTo-MailAlias -Value $EmployeeName))
    }

    $CheckedCandidates = [System.Collections.Generic.List[string]]::new()
    foreach ($Alias in $CandidateAliases) {
        if ([string]::IsNullOrWhiteSpace($Alias)) { continue }
        if ($CheckedCandidates.Contains($Alias)) { continue }
        [void]$CheckedCandidates.Add($Alias)

        $CandidateUpn = ('{0}@{1}' -f $Alias, $Domain)
        Write-ChildStatusLine ("Checking UPN availability: {0}" -f $CandidateUpn)
        if (-not (Test-GraphUserExists -UserPrincipalName $CandidateUpn)) {
            return [pscustomobject]@{
                UserPrincipalName = $CandidateUpn
                MailNickname = $Alias
                GenerationMethod = 'Automatic'
                CandidateOrder = ($CheckedCandidates -join '; ')
            }
        }
    }

    Write-ChildOutputLine ("Preferred UPN formats are already in use for {0}." -f $EmployeeName)
    Write-ChildOutputLine ("Checked: {0}" -f (($CheckedCandidates | ForEach-Object { '{0}@{1}' -f $_, $Domain }) -join ', '))
    Write-ChildOutputLine 'Manual UPN entry is required. Use a full UPN such as firstname.lastname@domain.com.'

    while ($true) {
        $ManualUpn = (Read-ChildText -Prompt ("Manual UPN for '$EmployeeName'")).Trim()
        if ($ManualUpn -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') {
            Write-ChildOutputLine 'Manual UPN is not in a valid UPN format. Example: test.user@enchantedrock.com'
            continue
        }
        if (Test-GraphUserExists -UserPrincipalName $ManualUpn) {
            Write-ChildOutputLine ("Manual UPN already exists: {0}" -f $ManualUpn)
            continue
        }
        $ManualAlias = ConvertTo-MailAlias -Value ($ManualUpn.Split('@')[0])
        return [pscustomobject]@{
            UserPrincipalName = $ManualUpn
            MailNickname = $ManualAlias
            GenerationMethod = 'Manual'
            CandidateOrder = ($CheckedCandidates -join '; ')
        }
    }
}


function Get-PreferredUpnCandidateAliases {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$EmployeeName)

    $NameParts = Split-EmployeeName -DisplayName $EmployeeName
    $CandidateAliases = [System.Collections.Generic.List[string]]::new()
    $FirstName = if ($null -ne $NameParts.GivenName) { ([string]$NameParts.GivenName).Trim() } else { '' }
    $MiddleInitial = if ($null -ne $NameParts.MiddleInitial) { ([string]$NameParts.MiddleInitial).Trim() } else { '' }
    $LastName = if ($null -ne $NameParts.Surname) { ([string]$NameParts.Surname).Trim() } else { '' }

    if (-not [string]::IsNullOrWhiteSpace($FirstName) -and -not [string]::IsNullOrWhiteSpace($LastName)) {
        [void]$CandidateAliases.Add((ConvertTo-MailAlias -Value ('{0}{1}' -f $FirstName.Substring(0, 1), $LastName)))
        [void]$CandidateAliases.Add((ConvertTo-MailAlias -Value ('{0}.{1}' -f $FirstName, $LastName)))
        if (-not [string]::IsNullOrWhiteSpace($MiddleInitial)) {
            [void]$CandidateAliases.Add((ConvertTo-MailAlias -Value ('{0}.{1}.{2}' -f $FirstName, $MiddleInitial.Substring(0, 1), $LastName)))
        }
    }
    else {
        [void]$CandidateAliases.Add((ConvertTo-MailAlias -Value $EmployeeName))
    }

    $UniqueAliases = [System.Collections.Generic.List[string]]::new()
    foreach ($Alias in $CandidateAliases) {
        if ([string]::IsNullOrWhiteSpace($Alias)) { continue }
        if (-not $UniqueAliases.Contains($Alias)) { [void]$UniqueAliases.Add($Alias) }
    }
    return @($UniqueAliases)
}

function Get-FirstAvailableGeneratedUpn {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$EmployeeName,
        [Parameter(Mandatory = $true)][string]$Domain
    )

    $CheckedCandidates = [System.Collections.Generic.List[string]]::new()
    foreach ($Alias in @(Get-PreferredUpnCandidateAliases -EmployeeName $EmployeeName)) {
        $CandidateUpn = ('{0}@{1}' -f $Alias, $Domain)
        [void]$CheckedCandidates.Add($CandidateUpn)
        Write-ChildStatusLine ("Checking UPN availability: {0}" -f $CandidateUpn)
        if (-not (Test-GraphUserExists -UserPrincipalName $CandidateUpn)) {
            return [pscustomobject][ordered]@{
                UserPrincipalName = $CandidateUpn
                MailNickname = $Alias
                GenerationMethod = 'ManualModeSuggested'
                CandidateOrder = ($CheckedCandidates -join '; ')
                FoundAvailable = $true
            }
        }
    }

    return [pscustomobject][ordered]@{
        UserPrincipalName = ''
        MailNickname = ''
        GenerationMethod = 'ManualRequired'
        CandidateOrder = ($CheckedCandidates -join '; ')
        FoundAvailable = $false
    }
}

function Read-AvailableManualUpn {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$EmployeeName)

    while ($true) {
        $ManualUpn = (Read-ChildText -Prompt ("Manual UPN for '$EmployeeName'")).Trim()
        if ($ManualUpn -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') {
            Write-ChildOutputLine 'Manual UPN is not in a valid UPN format. Example: test.user@enchantedrock.com'
            continue
        }
        if (Test-GraphUserExists -UserPrincipalName $ManualUpn) {
            Write-ChildOutputLine ("Manual UPN already exists: {0}" -f $ManualUpn)
            continue
        }
        $ManualAlias = ConvertTo-MailAlias -Value ($ManualUpn.Split('@')[0])
        return [pscustomobject][ordered]@{
            UserPrincipalName = $ManualUpn
            MailNickname = $ManualAlias
            GenerationMethod = 'Manual'
            CandidateOrder = ''
            FoundAvailable = $true
        }
    }
}

function Select-ManualModeUserPrincipalName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$EmployeeName,
        [Parameter(Mandatory = $true)][string]$Domain
    )

    $Suggested = Get-FirstAvailableGeneratedUpn -EmployeeName $EmployeeName -Domain $Domain
    if ($Suggested.FoundAvailable -eq $true -and -not [string]::IsNullOrWhiteSpace($Suggested.UserPrincipalName)) {
        Write-ChildOutputLine ("Suggested UPN: {0}" -f $Suggested.UserPrincipalName)
        $Choice = Read-ChildMenuChoice -Title 'Manual Input UPN Confirmation' -Options @(("1. Accept suggested UPN: {0}" -f $Suggested.UserPrincipalName),'2. Type a different UPN manually') -Prompt 'Select UPN option' -ValidChoices @('1','2') -DefaultChoice '1'
        if ($Choice -eq '1') { return $Suggested }
        return (Read-AvailableManualUpn -EmployeeName $EmployeeName)
    }

    Write-ChildOutputLine ("No preferred generated UPN was available for {0}." -f $EmployeeName)
    if (-not [string]::IsNullOrWhiteSpace($Suggested.CandidateOrder)) {
        Write-ChildOutputLine ("Checked: {0}" -f $Suggested.CandidateOrder)
    }
    return (Read-AvailableManualUpn -EmployeeName $EmployeeName)
}

function Read-ChildOptionalText {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Prompt)

    return ([string](Read-ChildText -Prompt $Prompt -AllowEmpty)).Trim()
}

function New-ManualOnboardingRecord {
    [CmdletBinding()]
    param()

    Write-ChildOutputLine 'Single-user manual intake will begin now.'
    Write-ChildOutputLine 'Enter the onboarding values requested below. Optional values may be left blank.'

    $Record = New-EmptyOnboardingRecord
    $Record.SourceText = 'Manual single-user input'
    $Record.EmployeeName = ([string](Read-ChildText -Prompt 'Employee Name')).Trim()
    $Record.Title = Read-ChildOptionalText -Prompt 'Title'
    if ($script:CreateTemporaryAccessPass -and $script:TemporaryAccessPassActivationMode -eq 'DOH') {
        $Record.DOH = ([string](Read-ChildText -Prompt 'Date of Hire / DOH')).Trim()
    }
    else {
        $Record.DOH = Read-ChildOptionalText -Prompt 'Date of Hire / DOH'
    }
    $Record.HomeDepartment = Read-ChildOptionalText -Prompt 'Home Department'
    $Record.CostCenter = Read-ChildOptionalText -Prompt 'Cost Center'
    $Record.BusinessUnit = Read-ChildOptionalText -Prompt 'Business Unit'
    $Record.Leader = Read-ChildOptionalText -Prompt 'Leader'
    $Record.OfficeLocation = Read-ChildOptionalText -Prompt 'Office Location'

    $UpnInfo = Select-ManualModeUserPrincipalName -EmployeeName $Record.EmployeeName -Domain $script:DefaultUpnDomain
    $Record.UserPrincipalName = $UpnInfo.UserPrincipalName
    $Record.MailNickname = $UpnInfo.MailNickname
    return [pscustomobject]$Record
}

function Resolve-ManagerUser {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$LeaderValue,
        [Parameter(Mandatory = $false)][string]$ManualUpn = ''
    )

    if (-not [string]::IsNullOrWhiteSpace($ManualUpn)) {
        try { return Get-MgUser -UserId $ManualUpn -Property Id,DisplayName,UserPrincipalName -ErrorAction Stop }
        catch { throw "Manager UPN '$ManualUpn' was not found in Entra ID." }
    }

    if ([string]::IsNullOrWhiteSpace($LeaderValue)) { return $null }

    if ($LeaderValue -match '@') {
        try { return Get-MgUser -UserId $LeaderValue -Property Id,DisplayName,UserPrincipalName -ErrorAction Stop }
        catch { return $null }
    }

    $SafeLeader = ConvertTo-SafeODataString -Value $LeaderValue.Trim()
    try {
        $Exact = @(Get-MgUser -Filter "displayName eq '$SafeLeader'" -Property Id,DisplayName,UserPrincipalName -All -ErrorAction Stop)
        if ($Exact.Count -eq 1) { return $Exact[0] }
        if ($Exact.Count -gt 1) { return [pscustomobject]@{ Ambiguous = $true; Matches = $Exact } }
    }
    catch { }

    try {
        $Searched = @(Get-MgUser -Search "`"displayName:$($LeaderValue.Trim())`"" -ConsistencyLevel eventual -Property Id,DisplayName,UserPrincipalName -Top 10 -ErrorAction Stop)
        if ($Searched.Count -eq 1) { return $Searched[0] }
        if ($Searched.Count -gt 1) { return [pscustomobject]@{ Ambiguous = $true; Matches = $Searched } }
    }
    catch { }

    return $null
}

function Resolve-RequiredManagers {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Records)

    $Resolved = @{}
    $DistinctLeaderKeys = @(
        @($Records) |
        ForEach-Object {
            if (-not [string]::IsNullOrWhiteSpace($_.ManagerUPN)) { "UPN::$($_.ManagerUPN.Trim())" }
            elseif (-not [string]::IsNullOrWhiteSpace($_.Leader)) { "NAME::$($_.Leader.Trim())" }
        } |
        Sort-Object -Unique
    )

    foreach ($Key in $DistinctLeaderKeys) {
        $IsUpn = $Key.StartsWith('UPN::')
        $LeaderValue = if ($IsUpn) { $Key.Substring(5) } else { $Key.Substring(6) }
        $ManualUpn = if ($IsUpn) { $LeaderValue } else { '' }
        $Result = Resolve-ManagerUser -LeaderValue $LeaderValue -ManualUpn $ManualUpn

        if ($null -eq $Result -or ($Result.PSObject.Properties['Ambiguous'] -and $Result.Ambiguous)) {
            Write-ChildOutputLine -Message ''
            Write-ChildOutputLine ("Leader could not be resolved uniquely: {0}" -f $LeaderValue)
            $PossibleMatches = @()
            if ($Result -and $Result.PSObject.Properties['Matches']) {
                $PossibleMatches = @($Result.Matches)
                Write-ChildOutputLine 'Possible manager matches:'
                for ($Index = 0; $Index -lt $PossibleMatches.Count; $Index++) {
                    $MatchNumber = $Index + 1
                    $Match = $PossibleMatches[$Index]
                    Write-ChildOutputLine ("{0}. {1} <{2}>" -f $MatchNumber, $Match.DisplayName, $Match.UserPrincipalName)
                }
            }
            Write-ChildOutputLine 'Enter a match number, type a manager UPN, or leave blank to skip manager assignment and flag for review.'
            $ManagerSelection = Read-ChildText -Prompt ("Manager selection for leader '$LeaderValue'") -AllowEmpty
            if (-not [string]::IsNullOrWhiteSpace($ManagerSelection)) {
                $ManagerSelection = $ManagerSelection.Trim()
                $SelectedNumber = 0
                if ([int]::TryParse($ManagerSelection, [ref]$SelectedNumber) -and $SelectedNumber -ge 1 -and $SelectedNumber -le $PossibleMatches.Count) {
                    $Result = $PossibleMatches[$SelectedNumber - 1]
                    Write-ChildStatusLine ("Selected manager: {0} <{1}>" -f $Result.DisplayName, $Result.UserPrincipalName)
                }
                else {
                    try { $Result = Resolve-ManagerUser -LeaderValue $LeaderValue -ManualUpn $ManagerSelection }
                    catch {
                        Add-ReviewFlag -EmployeeName '' -Severity Warning -Area 'Manager resolution' -Message $_.Exception.Message -Recommendation 'Set the manager manually in Entra ID after onboarding.'
                        $Result = $null
                    }
                }
            }
            else { $Result = $null }
        }

        $Resolved[$Key] = $Result
    }

    return $Resolved
}

function Get-ManagerKeyForRecord {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Record)

    if (-not [string]::IsNullOrWhiteSpace($Record.ManagerUPN)) { return "UPN::$($Record.ManagerUPN.Trim())" }
    if (-not [string]::IsNullOrWhiteSpace($Record.Leader)) { return "NAME::$($Record.Leader.Trim())" }
    return ''
}

function New-OnboardingTemplateWorkbook {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    Assert-ImportExcelAvailable
    $Rows = @(
        [pscustomobject][ordered]@{
            EmployeeName = 'Test This Onboarding'
            EmployeeType = 'EE'
            Title = "Long's Test Script"
            DOH = '7/14/26'
            HomeDepartment = 'IT'
            CostCenter = '227'
            BusinessUnit = 'IT'
            Leader = 'Sathya Long'
            ManagerUPN = ''
            OfficeLocation = 'Vine'
            LaptopType = 'Admin'
            CellYN = 'N'
            CompanyVehicleYN = 'N'
            WorkingRemoteWFH = 'N/A'
            UserPrincipalName = ''
            MailNickname = ''
            UsageLocation = ''
        }
    )
    $Instructions = @(
        [pscustomobject][ordered]@{ Field = 'EmployeeName'; Required = 'Yes'; Notes = 'Maps to Display Name. Also used to derive First name and Last name.' },
        [pscustomobject][ordered]@{ Field = 'DOH'; Required = 'Yes when TAP is created'; Notes = 'Used as the TAP start date. Example: 7/14/26.' },
        [pscustomobject][ordered]@{ Field = 'Leader'; Required = 'Recommended'; Notes = 'Display name to resolve as Manager.' },
        [pscustomobject][ordered]@{ Field = 'ManagerUPN'; Required = 'Optional'; Notes = 'Use when Leader is ambiguous or not found.' },
        [pscustomobject][ordered]@{ Field = 'UserPrincipalName'; Required = 'Optional'; Notes = 'Leave blank to auto-generate using firstinitiallastname, then firstname.lastname, then firstname.middleinitial.lastname.' },
        [pscustomobject][ordered]@{ Field = 'UsageLocation'; Required = 'Optional'; Notes = 'Two-letter country code. Defaults to US when blank.' }
    )

    $Directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $Directory)) { New-Item -ItemType Directory -Path $Directory -Force | Out-Null }
    if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue }
    $Instructions | Export-Excel -Path $Path -WorksheetName 'Instructions' -AutoSize -FreezeTopRow -BoldTopRow -ClearSheet
    $Rows | Export-Excel -Path $Path -WorksheetName 'Onboarding Import' -AutoSize -FreezeTopRow -BoldTopRow -Append
    Set-MOCWorkbookStyle -Path $Path
    return $Path
}

function Import-OnboardingRecordsFromFile {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { throw "Import file was not found: $Path" }
    $Extension = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
    if ($Extension -eq '.xlsx') {
        Assert-ImportExcelAvailable
        $Rows = @(Import-Excel -Path $Path -WorksheetName 'Onboarding Import' -ErrorAction Stop)
        if ($Rows.Count -eq 0) { $Rows = @(Import-Excel -Path $Path -ErrorAction Stop) }
    }
    elseif ($Extension -eq '.csv') {
        $Rows = @(Import-Csv -Path $Path -ErrorAction Stop)
    }
    else {
        throw 'Bulk import supports .xlsx or .csv files only.'
    }

    $Records = foreach ($Row in $Rows) { Convert-ImportRowToOnboardingRecord -Row $Row }
    return @($Records)
}

function Convert-RecordToSourceRow {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Record)

    return [pscustomobject][ordered]@{
        EmployeeName = $Record.EmployeeName
        EmployeeType = $Record.EmployeeType
        Title = $Record.Title
        DOH = $Record.DOH
        HomeDepartment = $Record.HomeDepartment
        CostCenter = $Record.CostCenter
        BusinessUnit = $Record.BusinessUnit
        Leader = $Record.Leader
        ManagerUPN = $Record.ManagerUPN
        OfficeLocation = $Record.OfficeLocation
        LaptopType = $Record.LaptopType
        CellYN = $Record.CellYN
        CompanyVehicleYN = $Record.CompanyVehicleYN
        WorkingRemoteWFH = $Record.WorkingRemoteWFH
        UserPrincipalName = $Record.UserPrincipalName
        MailNickname = $Record.MailNickname
        UsageLocation = $Record.UsageLocation
        SourceText = $Record.SourceText
    }
}


function Get-OnboardingDepartmentValue {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Record)

    $CostCenter = if ($null -ne $Record.CostCenter) { ([string]$Record.CostCenter).Trim() } else { '' }
    $HomeDepartment = if ($null -ne $Record.HomeDepartment) { ([string]$Record.HomeDepartment).Trim() } else { '' }

    if (-not [string]::IsNullOrWhiteSpace($CostCenter) -and -not [string]::IsNullOrWhiteSpace($HomeDepartment)) {
        return ('{0} - {1}' -f $CostCenter, $HomeDepartment)
    }
    if (-not [string]::IsNullOrWhiteSpace($CostCenter)) { return $CostCenter }
    if (-not [string]::IsNullOrWhiteSpace($HomeDepartment)) { return $HomeDepartment }
    return ''
}

function Validate-OnboardingRecord {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Record)

    $Errors = [System.Collections.ArrayList]::new()
    if ([string]::IsNullOrWhiteSpace($Record.EmployeeName)) { [void]$Errors.Add('Employee Name is required.') }
    if ($script:CreateTemporaryAccessPass -and $script:TemporaryAccessPassActivationMode -eq 'DOH' -and [string]::IsNullOrWhiteSpace($Record.DOH)) { [void]$Errors.Add('DOH is required when DOH-based TAP activation is selected.') }
    if (-not [string]::IsNullOrWhiteSpace($Record.UserPrincipalName) -and $Record.UserPrincipalName -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') { [void]$Errors.Add('UserPrincipalName is not a valid UPN format.') }
    return @($Errors)
}


function Get-MailboxLicenseDisplayName {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$SkuPartNumber)

    $Map = @{
        'EXCHANGESTANDARD' = 'Exchange Online Plan 1'
        'EXCHANGEENTERPRISE' = 'Exchange Online Plan 2'
        'ENTERPRISEPACK' = 'Office 365 E3'
        'ENTERPRISEPREMIUM' = 'Office 365 E5'
        'SPE_E3' = 'Microsoft 365 E3'
        'SPE_E5' = 'Microsoft 365 E5'
        'O365_BUSINESS_ESSENTIALS' = 'Microsoft 365 Business Basic'
        'O365_BUSINESS_PREMIUM' = 'Microsoft 365 Business Standard'
        'SPB' = 'Microsoft 365 Business Premium'
        'SMB_BUSINESS_PREMIUM' = 'Microsoft 365 Business Standard'
        'M365EDU_A3_FACULTY' = 'Microsoft 365 A3 Faculty'
        'M365EDU_A5_FACULTY' = 'Microsoft 365 A5 Faculty'
        'STANDARDPACK' = 'Office 365 E1'
        'STANDARDWOFFPACK' = 'Office 365 E2'
        'DESKLESSPACK' = 'Office 365 F3'
        'SPE_F1' = 'Microsoft 365 F3'
    }

    if ($Map.ContainsKey($SkuPartNumber)) { return $Map[$SkuPartNumber] }
    return $SkuPartNumber
}

function Get-MailboxCapableLicenseSkus {
    [CmdletBinding()]
    param()

    if (-not (Get-Command Get-MgSubscribedSku -ErrorAction SilentlyContinue)) {
        throw 'Required cmdlet Get-MgSubscribedSku was not found. Install or update Microsoft.Graph.Identity.DirectoryManagement.'
    }

    $Skus = @(Get-MgSubscribedSku -All -ErrorAction Stop)
    $Options = [System.Collections.ArrayList]::new()

    foreach ($Sku in $Skus) {
        $ServicePlans = @($Sku.ServicePlans)
        $ExchangePlans = @($ServicePlans | Where-Object {
            $PlanName = [string]$_.ServicePlanName
            $PlanStatus = [string]$_.ProvisioningStatus
            ($PlanName -match 'EXCHANGE|EXCHANGESTANDARD|EXCHANGEENTERPRISE') -and
            ($PlanStatus -notmatch 'Disabled|Deleted|Suspended')
        })
        if ($ExchangePlans.Count -eq 0) { continue }

        $EnabledUnits = 0
        if ($Sku.PrepaidUnits -and $null -ne $Sku.PrepaidUnits.Enabled) { $EnabledUnits = [int]$Sku.PrepaidUnits.Enabled }
        $ConsumedUnits = if ($null -ne $Sku.ConsumedUnits) { [int]$Sku.ConsumedUnits } else { 0 }
        $AvailableUnits = $EnabledUnits - $ConsumedUnits
        if ($AvailableUnits -lt 0) { $AvailableUnits = 0 }

        $DisplayName = Get-MailboxLicenseDisplayName -SkuPartNumber ([string]$Sku.SkuPartNumber)
        [void]$Options.Add([pscustomobject][ordered]@{
            SkuId = [string]$Sku.SkuId
            SkuPartNumber = [string]$Sku.SkuPartNumber
            DisplayName = $DisplayName
            EnabledUnits = $EnabledUnits
            ConsumedUnits = $ConsumedUnits
            AvailableUnits = $AvailableUnits
            ExchangeServicePlans = (($ExchangePlans | ForEach-Object { [string]$_.ServicePlanName }) -join ', ')
        })
    }

    return @($Options | Sort-Object -Property DisplayName, SkuPartNumber)
}

function Select-MailboxLicenseSkus {
    [CmdletBinding()]
    param()

    Write-ChildStatusLine 'Pulling current mailbox-capable Microsoft 365 license SKUs from Entra ID.'
    $LicenseOptions = @(Get-MailboxCapableLicenseSkus)
    foreach ($LicenseOption in @($LicenseOptions)) {
        [void]$script:LicenseRows.Add([pscustomobject][ordered]@{
            Selected = ''
            DisplayName = $LicenseOption.DisplayName
            SkuPartNumber = $LicenseOption.SkuPartNumber
            SkuId = $LicenseOption.SkuId
            AvailableUnits = $LicenseOption.AvailableUnits
            EnabledUnits = $LicenseOption.EnabledUnits
            ConsumedUnits = $LicenseOption.ConsumedUnits
            ExchangeServicePlans = $LicenseOption.ExchangeServicePlans
        })
    }

    if ($LicenseOptions.Count -eq 0) {
        Write-ChildStatusLine 'No mailbox-capable Microsoft 365 license SKUs were found in the tenant.'
        Add-ReviewFlag -EmployeeName 'Run' -Severity Warning -Area 'License' -Message 'No mailbox-capable Microsoft 365 license SKUs were found.' -Recommendation 'Assign licensing manually after onboarding if needed.'
        return @()
    }

    $MenuOptions = [System.Collections.ArrayList]::new()
    [void]$MenuOptions.Add('1. Do not assign a mailbox/M365 license during onboarding')
    for ($Index = 0; $Index -lt $LicenseOptions.Count; $Index++) {
        $Number = $Index + 2
        $Sku = $LicenseOptions[$Index]
        $AvailabilityText = if ($Sku.AvailableUnits -gt 0) { ('available {0} of {1}' -f $Sku.AvailableUnits, $Sku.EnabledUnits) } else { ('none available; consumed {0} of {1}' -f $Sku.ConsumedUnits, $Sku.EnabledUnits) }
        [void]$MenuOptions.Add(('{0}. {1} ({2}) - {3}' -f $Number, $Sku.DisplayName, $Sku.SkuPartNumber, $AvailabilityText))
    }

    Write-ChildOutputLine 'Mailbox License Assignment'
    Write-ChildOutputLine '--------------------------'
    foreach ($Option in @($MenuOptions)) { Write-ChildOutputLine $Option }
    Write-ChildOutputLine 'Enter one or more choices separated by commas.'
    Write-ChildOutputLine 'Example: 2,4'
    Write-ChildOutputLine 'Default: 1'

    $ValidNumbers = @(1..($LicenseOptions.Count + 1))
    while ($true) {
        $ChoiceRaw = Read-ChildText -Prompt 'Select mailbox license option(s) [1]' -AllowEmpty
        $ChoiceText = if ([string]::IsNullOrWhiteSpace($ChoiceRaw)) { '1' } else { $ChoiceRaw.Trim() }
        $Parts = @($ChoiceText -split '[,;\s]+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        $InvalidParts = @($Parts | Where-Object { $_ -notmatch '^\d+$' -or ([int]$_) -notin $ValidNumbers })
        if ($InvalidParts.Count -gt 0 -or $Parts.Count -eq 0) {
            Write-ChildOutputLine ("Invalid license selection. Enter 1 for none, or one or more license numbers from 2 through {0}." -f ($LicenseOptions.Count + 1))
            continue
        }

        $SelectedNumbers = @($Parts | ForEach-Object { [int]$_ } | Sort-Object -Unique)
        if (1 -in $SelectedNumbers -and $SelectedNumbers.Count -gt 1) {
            Write-ChildOutputLine 'Invalid license selection. Option 1 means no license and cannot be combined with license choices.'
            continue
        }

        if ($SelectedNumbers.Count -eq 1 -and $SelectedNumbers[0] -eq 1) {
            [void]$script:LicenseRows.Add([pscustomobject][ordered]@{ Selected = 'True'; DisplayName = 'No mailbox/M365 license selected'; SkuPartNumber = ''; SkuId = ''; AvailableUnits = ''; EnabledUnits = ''; ConsumedUnits = ''; ExchangeServicePlans = '' })
            Write-ChildStatusLine 'License selection: no mailbox/M365 license will be assigned.'
            return @()
        }

        $Selected = @($SelectedNumbers | ForEach-Object { $LicenseOptions[$_ - 2] })
        foreach ($SelectedSku in @($Selected)) {
            if ($SelectedSku.AvailableUnits -le 0) {
                Add-ReviewFlag -EmployeeName 'Run' -Severity Warning -Area 'License' -Message ("Selected license has no available units: {0} ({1})." -f $SelectedSku.DisplayName, $SelectedSku.SkuPartNumber) -Recommendation 'Purchase or free a license before running onboarding, or choose no license and assign manually later.'
                Write-ChildStatusLine ("WARNING: Selected license has no available units: {0}" -f $SelectedSku.SkuPartNumber)
            }
            foreach ($LicenseRow in @($script:LicenseRows)) {
                if ($LicenseRow.SkuId -eq $SelectedSku.SkuId) { $LicenseRow.Selected = 'True' }
            }
        }

        $SelectionText = (@($Selected | ForEach-Object { '{0} ({1})' -f $_.DisplayName, $_.SkuPartNumber }) -join ', ')
        Write-ChildStatusLine ("License selection: {0}" -f $SelectionText)
        return @($Selected)
    }
}

function Add-MailboxLicenseToUser {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$UserId,
        [Parameter(Mandatory = $false)]$LicenseSkus
    )

    $SelectedSkus = @($LicenseSkus | Where-Object { $null -ne $_ })
    if ($SelectedSkus.Count -eq 0) {
        return [pscustomobject][ordered]@{
            Assigned = $false
            LicenseName = 'No mailbox/M365 license selected'
            SkuPartNumber = ''
            SkuId = ''
            Status = 'Skipped'
            ErrorMessage = ''
        }
    }

    if (-not (Get-Command Set-MgUserLicense -ErrorAction SilentlyContinue)) {
        throw 'Required cmdlet Set-MgUserLicense was not found. Install or update Microsoft.Graph.Users.Actions.'
    }

    $AddLicenses = @($SelectedSkus | ForEach-Object { @{ skuId = [guid]$_.SkuId } })
    Set-MgUserLicense -UserId $UserId -AddLicenses $AddLicenses -RemoveLicenses @() -ErrorAction Stop | Out-Null
    return [pscustomobject][ordered]@{
        Assigned = $true
        LicenseName = (@($SelectedSkus | ForEach-Object { [string]$_.DisplayName }) -join ', ')
        SkuPartNumber = (@($SelectedSkus | ForEach-Object { [string]$_.SkuPartNumber }) -join ', ')
        SkuId = (@($SelectedSkus | ForEach-Object { [string]$_.SkuId }) -join ', ')
        Status = 'Assigned'
        ErrorMessage = ''
    }
}

function New-EntraOnboardingUser {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Record,
        [Parameter(Mandatory = $false)]$ManagerUser
    )

    $EmployeeName = $Record.EmployeeName.Trim()
    $NameParts = Split-EmployeeName -DisplayName $EmployeeName
    $UpnInfo = $null

    if (-not [string]::IsNullOrWhiteSpace($Record.UserPrincipalName)) {
        $ProvidedUpn = $Record.UserPrincipalName.Trim()
        $Alias = if (-not [string]::IsNullOrWhiteSpace($Record.MailNickname)) { ConvertTo-MailAlias -Value $Record.MailNickname } else { ConvertTo-MailAlias -Value ($ProvidedUpn.Split('@')[0]) }
        if (Test-GraphUserExists -UserPrincipalName $ProvidedUpn) { throw "UserPrincipalName already exists: $ProvidedUpn" }
        $UpnInfo = [pscustomobject]@{ UserPrincipalName = $ProvidedUpn; MailNickname = $Alias; GenerationMethod = 'Provided'; CandidateOrder = '' }
    }
    else {
        $PreferredAlias = if (-not [string]::IsNullOrWhiteSpace($Record.MailNickname)) { $Record.MailNickname } else { $EmployeeName }
        $UpnInfo = New-UniqueUserPrincipalName -EmployeeName $EmployeeName -Domain $script:DefaultUpnDomain -PreferredAlias $PreferredAlias
    }

    $InitialPassword = New-StrongRandomPassword -Length 24
    $Body = [ordered]@{
        accountEnabled = [bool]$script:AccountEnabled
        displayName = $EmployeeName
        mailNickname = $UpnInfo.MailNickname
        userPrincipalName = $UpnInfo.UserPrincipalName
        passwordProfile = @{
            forceChangePasswordNextSignIn = $true
            password = $InitialPassword
        }
    }

    $DepartmentValue = Get-OnboardingDepartmentValue -Record $Record

    if (-not [string]::IsNullOrWhiteSpace($NameParts.GivenName)) { $Body.givenName = $NameParts.GivenName }
    if (-not [string]::IsNullOrWhiteSpace($NameParts.Surname)) { $Body.surname = $NameParts.Surname }
    if (-not [string]::IsNullOrWhiteSpace($Record.Title)) { $Body.jobTitle = $Record.Title.Trim() }
    if (-not [string]::IsNullOrWhiteSpace($DepartmentValue)) { $Body.department = $DepartmentValue }
    if (-not [string]::IsNullOrWhiteSpace($Record.OfficeLocation)) { $Body.officeLocation = $Record.OfficeLocation.Trim() }
    if (-not [string]::IsNullOrWhiteSpace($Record.EmployeeType)) { $Body.employeeType = $Record.EmployeeType.Trim() }
    if (-not [string]::IsNullOrWhiteSpace($Record.UsageLocation)) { $Body.usageLocation = $Record.UsageLocation.Trim().ToUpperInvariant() }
    elseif (-not [string]::IsNullOrWhiteSpace($script:PreferredUsageLocation)) { $Body.usageLocation = $script:PreferredUsageLocation.Trim().ToUpperInvariant() }

    $NewUser = New-MgUser -BodyParameter $Body -ErrorAction Stop
    $ManagerSet = $false
    $ManagerUpn = ''
    if ($null -ne $ManagerUser -and $ManagerUser.PSObject.Properties['Id']) {
        $RefBody = @{ '@odata.id' = "https://graph.microsoft.com/v1.0/users/$($ManagerUser.Id)" }
        Set-MgUserManagerByRef -UserId $NewUser.Id -BodyParameter $RefBody -ErrorAction Stop
        $ManagerSet = $true
        $ManagerUpn = $ManagerUser.UserPrincipalName
    }

    $TapCreated = $false
    $TapValue = ''
    $TapStartUtc = ''
    $TapLifetimeMinutes = ''
    if ($script:CreateTemporaryAccessPass) {
        if ($script:TemporaryAccessPassActivationMode -eq 'Immediate') {
            $TapStart = [datetime]::UtcNow
        }
        else {
            $DateOfHire = Resolve-DateOfHire -Value $Record.DOH -EmployeeName $EmployeeName
            $TapStart = Get-TapStartDateTimeUtc -DateOfHire $DateOfHire -StartTimeText $script:DefaultTapStartTime
        }
        $TapBody = @{
            startDateTime = $TapStart.ToString('yyyy-MM-ddTHH:mm:ssZ')
            lifetimeInMinutes = [int]$script:TemporaryAccessPassLifetimeMinutes
            isUsableOnce = $false
        }
        $Tap = New-MgUserAuthenticationTemporaryAccessPassMethod -UserId $NewUser.Id -BodyParameter $TapBody -ErrorAction Stop
        $TapCreated = $true
        $TapValue = [string]$Tap.TemporaryAccessPass
        $TapStartUtc = $TapStart.ToString('yyyy-MM-dd HH:mm:ss UTC')
        $TapLifetimeMinutes = [string]$script:TemporaryAccessPassLifetimeMinutes
    }

    $LicenseAssigned = $false
    $LicenseName = 'No mailbox/M365 license selected'
    $LicenseSkuPartNumber = ''
    $LicenseSkuId = ''
    $LicenseStatus = 'Skipped'
    if (@($script:SelectedMailboxLicenseSkus).Count -gt 0) {
        try {
            $LicenseResult = Add-MailboxLicenseToUser -UserId $NewUser.Id -LicenseSkus $script:SelectedMailboxLicenseSkus
            $LicenseAssigned = [bool]$LicenseResult.Assigned
            $LicenseName = [string]$LicenseResult.LicenseName
            $LicenseSkuPartNumber = [string]$LicenseResult.SkuPartNumber
            $LicenseSkuId = [string]$LicenseResult.SkuId
            $LicenseStatus = [string]$LicenseResult.Status
        }
        catch {
            $LicenseStatus = 'Failed'
            $LicenseName = if (@($script:SelectedMailboxLicenseSkus).Count -gt 0) { (@($script:SelectedMailboxLicenseSkus | ForEach-Object { [string]$_.DisplayName }) -join ', ') } else { 'Selected license' }
            $LicenseSkuPartNumber = if (@($script:SelectedMailboxLicenseSkus).Count -gt 0) { (@($script:SelectedMailboxLicenseSkus | ForEach-Object { [string]$_.SkuPartNumber }) -join ', ') } else { '' }
            $LicenseSkuId = if (@($script:SelectedMailboxLicenseSkus).Count -gt 0) { (@($script:SelectedMailboxLicenseSkus | ForEach-Object { [string]$_.SkuId }) -join ', ') } else { '' }
            $FriendlyLicenseError = Get-FriendlyFailureMessage -Message $_.Exception.Message
            Add-ReviewFlag -EmployeeName $EmployeeName -Severity Error -Area 'License' -Message ("License assignment failed: {0}" -f $FriendlyLicenseError) -Recommendation 'Assign the selected mailbox/M365 license(s) manually after remediation.'
            Add-ErrorRow -EmployeeName $EmployeeName -Stage 'License assignment' -Message $FriendlyLicenseError -Details ($_.ScriptStackTrace | Out-String)
        }
    }

    [void]$script:OnboardedRows.Add([pscustomobject][ordered]@{
        EmployeeName = $EmployeeName
        UserPrincipalName = $UpnInfo.UserPrincipalName
        DisplayName = $EmployeeName
        GivenName = $NameParts.GivenName
        Surname = $NameParts.Surname
        JobTitle = $Record.Title
        Department = $DepartmentValue
        CompanyName = ''
        OfficeLocation = $Record.OfficeLocation
        EmployeeType = $Record.EmployeeType
        UsageLocation = if ($Body.Contains('usageLocation')) { $Body.usageLocation } else { '' }
        AccountEnabled = [string]$script:AccountEnabled
        ManagerSet = [string]$ManagerSet
        ManagerUPN = $ManagerUpn
        LicenseAssigned = [string]$LicenseAssigned
        LicenseName = $LicenseName
        LicenseSkuPartNumber = $LicenseSkuPartNumber
        LicenseSkuId = $LicenseSkuId
        LicenseStatus = $LicenseStatus
        TemporaryAccessPassCreated = [string]$TapCreated
        TapStartUtc = $TapStartUtc
        TapLifetimeMinutes = $TapLifetimeMinutes
        ObjectId = $NewUser.Id
        Status = 'Created'
    })

    [void]$script:SensitiveRows.Add([pscustomobject][ordered]@{
        EmployeeName = $EmployeeName
        UserPrincipalName = $UpnInfo.UserPrincipalName
        InitialPassword = $InitialPassword
        TemporaryAccessPass = $TapValue
        TapStartUtc = $TapStartUtc
        TapLifetimeMinutes = $TapLifetimeMinutes
        Notes = 'Sensitive values. Store securely and delete this workbook when no longer needed.'
    })

    if (-not $ManagerSet) {
        Add-ReviewFlag -EmployeeName $EmployeeName -Severity Warning -Area 'Manager' -Message 'Manager was not set because Leader was blank or unresolved.' -Recommendation 'Set Manager manually in Entra ID.'
    }

    if (-not [string]::IsNullOrWhiteSpace($Record.BusinessUnit)) {
        Add-ReviewFlag -EmployeeName $EmployeeName -Severity Informational -Area 'Business Unit' -Message 'Business Unit does not have a default standard Entra ID user attribute in this script.' -Recommendation 'Consider extension attributes or custom security attributes if this value must be stored.'
    }

    return $NewUser
}

function Invoke-ScriptStep {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][int]$StepNumber,
        [Parameter(Mandatory = $true)][int]$TotalSteps,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$ScriptBlock
    )

    $Percent = (($StepNumber - 1) / [Math]::Max($TotalSteps, 1)) * 100
    Update-ChildProgress -Activity $ScriptDisplayName -Percent $Percent -Status ("Step {0} of {1} - {2}" -f $StepNumber, $TotalSteps, $Name) -CurrentOperation ''
    Write-ChildOutputLine -Message ''
    Write-ChildOutputLine '========================================================================'
    Write-ChildOutputLine ("[Step {0} of {1}] {2}" -f $StepNumber, $TotalSteps, $Name)
    Write-ChildOutputLine '========================================================================'
    $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        & $ScriptBlock
        $Stopwatch.Stop()
        Write-ChildStatusLine ("SUCCESS: {0} completed in {1:N1} seconds." -f $Name, $Stopwatch.Elapsed.TotalSeconds)
    }
    catch {
        $Stopwatch.Stop()
        if ($script:ChildPromptCancellationRequested -or ([string]$_ -eq '__MOC_CHILD_PROMPT_CANCELLED__')) {
            Write-ChildStatusLine ("STOPPED: {0}" -f $Name) -Level Warning
            throw
        }
        $Message = "ERROR during step '{0}': {1}" -f $Name, $_.Exception.Message
        Add-AuditNote -Severity Error -Area $Name -Message $Message
        throw
    }
    $Percent = ($StepNumber / [Math]::Max($TotalSteps, 1)) * 100
    Update-ChildProgress -Activity $ScriptDisplayName -Percent $Percent -Status ("Completed Step {0} of {1} - {2}" -f $StepNumber, $TotalSteps, $Name) -CurrentOperation ''
}

function Get-FriendlyFailureMessage {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Message)

    if ($Message -match 'Authorization_RequestDenied|Insufficient privileges|Forbidden|does not have authorization|Authentication_RequestFromUnsupportedUserRole') {
        return "Microsoft Graph permission failure. Required MOC app permissions: $($RequiredGraphScopes -join ', '). Grant these application or delegated permissions to the MOC app registration, provide admin consent, return to MOC, press A to authenticate, and rerun this script. Original error: $Message"
    }
    if ($Message -match 'InvalidAuthenticationToken|Access token has expired|Lifetime validation failed|token is expired|CompactToken') {
        return "Microsoft Graph access token appears expired or invalid. Return to MOC, press A to authenticate again, and rerun this script. Original error: $Message"
    }
    return $Message
}

try {
    if (-not (Test-Path -LiteralPath $ReportsDir)) { New-Item -ItemType Directory -Path $ReportsDir -Force | Out-Null }

    Update-ChildProgress -Activity $ScriptDisplayName -Percent 0 -Status 'Starting' -CurrentOperation ''
    Write-ChildOutputLine 'ERock M365 Operations Console (MOC)'
    Write-ChildOutputLine ("Startup: {0} | Version {1} | Build {2}" -f $ScriptFileName, $ScriptVersion, $ScriptBuild)
    Write-ChildOutputLine ("Run started: {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
    Write-ChildOutputLine ("Output folder: {0}" -f (Get-ReportDisplayPath -Path $WorkbookPath))
    Write-ChildTranscriptLine ("Full output folder: {0}" -f $ReportsDir)

    Invoke-ScriptStep -StepNumber 1 -TotalSteps $TotalSteps -Name 'Validate modules and parent Graph session' -ScriptBlock {
        Assert-RequiredModules
        Assert-MOCGraphSession
    }

    Invoke-ScriptStep -StepNumber 2 -TotalSteps $TotalSteps -Name 'Select onboarding mode' -ScriptBlock {
        Write-ChildOutputLine 'Choose the onboarding intake mode.'
        Write-ChildOutputLine 'Single paste mode accepts a two-column HR paste block.'
        Write-ChildOutputLine 'Single manual mode prompts for the basic onboarding fields.'
        Write-ChildOutputLine 'Bulk mode reads one row per user from an XLSX or CSV file.'
        Write-ChildOutputLine 'Template mode creates the XLSX import template and exits without creating users.'
        $Choice = Read-ChildMenuChoice -Title 'M365 Onboarding Mode' -Options @('1. Single user from paste block','2. Single user manual input','3. Multiple users from XLSX or CSV import file','4. Generate XLSX import template only') -Prompt 'Select onboarding mode' -ValidChoices @('1','2','3','4') -AllowExit
        if ($Choice -eq 'ExitToMenu') {
            $script:ExitRequested = $true
            $script:SelectedMode = 'ExitToMenu'
            Write-ChildStatusLine 'User selected Exit. No onboarding changes will be made.'
            return
        }
        switch ($Choice) {
            '1' { $script:SelectedMode = 'SinglePaste' }
            '2' { $script:SelectedMode = 'SingleManual' }
            '3' { $script:SelectedMode = 'BulkImport' }
            '4' { $script:SelectedMode = 'TemplateOnly' }
        }
        Write-ChildStatusLine ("Selected onboarding mode: {0}" -f $script:SelectedMode)
    }

    if ($script:ExitRequested) {
        $script:RunSucceeded = $true
        Update-ChildProgress -Activity $ScriptDisplayName -Percent 100 -Status 'Exited by user. Press Enter to return to the menu.' -CurrentOperation ''
        Write-ChildOutputLine 'User selected Exit. No users were created and no tenant changes were made.'
        return
    }

    Invoke-ScriptStep -StepNumber 3 -TotalSteps $TotalSteps -Name 'Collect onboarding settings and input' -ScriptBlock {
        if ($script:SelectedMode -eq 'TemplateOnly') {
            New-OnboardingTemplateWorkbook -Path $TemplatePath | Out-Null
            $script:Summary.Files['Template'] = $TemplatePath
            Write-ChildStatusLine ("Template written -> {0}" -f (Get-ReportDisplayPath -Path $TemplatePath))
            Open-MOCOutputFile -Path $TemplatePath -Description 'onboarding import template'
            return
        }

        $script:DefaultUpnDomain = Select-DefaultUpnDomain
        if ($script:DefaultUpnDomain -eq '__MOC_EXIT__') {
            $script:ExitRequested = $true
            Write-ChildStatusLine 'User selected Exit. No onboarding changes will be made.'
            return
        }
        $TapChoice = Read-ChildMenuChoice -Title 'Temporary Access Pass Settings' -Options @('1. Create TAP using DOH activation date; valid for three days','2. Create TAP active immediately; valid for three days','3. Do not create TAP') -Prompt 'Select TAP option' -ValidChoices @('1','2','3') -DefaultChoice '1'
        $script:CreateTemporaryAccessPass = ($TapChoice -ne '3')
        switch ($TapChoice) {
            '1' { $script:TemporaryAccessPassActivationMode = 'DOH' }
            '2' { $script:TemporaryAccessPassActivationMode = 'Immediate' }
            '3' { $script:TemporaryAccessPassActivationMode = 'None' }
        }
        Write-ChildStatusLine ("TAP selection: {0}" -f $script:TemporaryAccessPassActivationMode)
        if ($script:CreateTemporaryAccessPass -and $script:TemporaryAccessPassActivationMode -eq 'DOH') {
            Write-ChildStatusLine ("TAP DOH activation time defaults to {0} local time." -f $script:DefaultTapStartTime)
        }

        $EnableChoice = Read-ChildMenuChoice -Title 'Account Enabled State' -Options @('1. Create accounts enabled','2. Create accounts disabled') -Prompt 'Select account state' -ValidChoices @('1','2') -AllowExit
        if ($EnableChoice -eq 'ExitToMenu') {
            $script:ExitRequested = $true
            Write-ChildStatusLine 'User selected Exit. No onboarding changes will be made.'
            return
        }
        $script:AccountEnabled = ($EnableChoice -eq '1')

        Write-ChildStatusLine ("Default UsageLocation country code: {0}" -f $script:PreferredUsageLocation)

        $script:SelectedMailboxLicenseSkus = @(Select-MailboxLicenseSkus)
        if (@($script:SelectedMailboxLicenseSkus).Count -gt 0) {
            $script:SelectedMailboxLicenseName = (@($script:SelectedMailboxLicenseSkus | ForEach-Object { '{0} ({1})' -f $_.DisplayName, $_.SkuPartNumber }) -join ', ')
        }
        else {
            $script:SelectedMailboxLicenseName = 'No mailbox/M365 license selected'
$script:ChildPromptCancellationRequested = $false
$script:ChildPromptCancellationReason = ''
        }

        if ($script:SelectedMode -eq 'SinglePaste') {
            Write-ChildOutputLine 'Single-user HR paste intake will begin now.'
            Write-ChildOutputLine 'Paste the onboarding request block. Supported formats are tab-separated key/value lines or key=value separated by semicolons.'
            $Paste = Read-ChildMultilineText -Prompt 'Paste onboarding block'
            $script:OnboardingRecords = @(Parse-OnboardingPasteBlock -PasteText $Paste)
        }
        elseif ($script:SelectedMode -eq 'SingleManual') {
            $script:OnboardingRecords = @(New-ManualOnboardingRecord)
        }
        elseif ($script:SelectedMode -eq 'BulkImport') {
            Write-ChildOutputLine 'Bulk import intake will begin now.'
            Write-ChildOutputLine 'Bulk import requires an XLSX or CSV file. Use Template mode first if you need the import format.'
            $ImportPath = Read-ChildText -Prompt 'Full path to completed onboarding XLSX or CSV file'
            $script:OnboardingRecords = @(Import-OnboardingRecordsFromFile -Path $ImportPath)
            $script:Summary.Files['ImportFile'] = $ImportPath
        }

        foreach ($Record in @($script:OnboardingRecords)) { [void]$script:SourceRows.Add((Convert-RecordToSourceRow -Record $Record)) }
        Write-ChildStatusLine ("Collected {0} onboarding record(s)." -f @($script:OnboardingRecords).Count)
    }

    if ($script:ExitRequested) {
        $script:RunSucceeded = $true
        Update-ChildProgress -Activity $ScriptDisplayName -Percent 100 -Status 'Exited by user. Press Enter to return to the menu.' -CurrentOperation ''
        Write-ChildOutputLine 'User selected Exit. No users were created and no tenant changes were made.'
        return
    }

    if ($script:SelectedMode -ne 'TemplateOnly') {
        Invoke-ScriptStep -StepNumber 4 -TotalSteps $TotalSteps -Name 'Validate onboarding records' -ScriptBlock {
            $ValidRecords = [System.Collections.ArrayList]::new()
            foreach ($Record in @($script:OnboardingRecords)) {
                $Errors = @(Validate-OnboardingRecord -Record $Record)
                if ($Errors.Count -gt 0) {
                    foreach ($ValidationError in $Errors) {
                        Add-ErrorRow -EmployeeName $Record.EmployeeName -Stage 'Validation' -Message $ValidationError
                        Add-ReviewFlag -EmployeeName $Record.EmployeeName -Severity Error -Area 'Validation' -Message $ValidationError -Recommendation 'Correct the onboarding input and rerun for this user.'
                    }
                }
                else { [void]$ValidRecords.Add($Record) }
            }
            $script:OnboardingRecords = @($ValidRecords)
            if (@($script:OnboardingRecords).Count -eq 0) { throw 'No valid onboarding records remain after validation.' }
            Write-ChildStatusLine ("Validated {0} onboarding record(s)." -f @($script:OnboardingRecords).Count)
        }

        Invoke-ScriptStep -StepNumber 5 -TotalSteps $TotalSteps -Name 'Resolve managers' -ScriptBlock {
            $script:ResolvedManagers = Resolve-RequiredManagers -Records $script:OnboardingRecords
            Write-ChildStatusLine ("Resolved manager references for {0} distinct leader value(s)." -f @($script:ResolvedManagers.Keys).Count)
        }

        Invoke-ScriptStep -StepNumber 6 -TotalSteps $TotalSteps -Name 'Create Entra ID users' -ScriptBlock {
            $Records = @($script:OnboardingRecords)
            $Total = $Records.Count
            for ($Index = 0; $Index -lt $Total; $Index++) {
                $Record = $Records[$Index]
                $CurrentPercent = 70 + (($Index / [Math]::Max($Total, 1)) * 20)
                Update-ChildProgress -Activity $ScriptDisplayName -Percent $CurrentPercent -Status ("Creating user {0} of {1}" -f ($Index + 1), $Total) -CurrentOperation $Record.EmployeeName
                try {
                    $ManagerKey = Get-ManagerKeyForRecord -Record $Record
                    $Manager = if (-not [string]::IsNullOrWhiteSpace($ManagerKey) -and $script:ResolvedManagers.ContainsKey($ManagerKey)) { $script:ResolvedManagers[$ManagerKey] } else { $null }
                    New-EntraOnboardingUser -Record $Record -ManagerUser $Manager | Out-Null
                    Write-ChildStatusLine ("Created user: {0}" -f $Record.EmployeeName)
                }
                catch {
                    $Friendly = Get-FriendlyFailureMessage -Message $_.Exception.Message
                    Add-ErrorRow -EmployeeName $Record.EmployeeName -Stage 'Create user' -Message $Friendly -Details ($_.ScriptStackTrace | Out-String)
                    Add-ReviewFlag -EmployeeName $Record.EmployeeName -Severity Error -Area 'Create user' -Message $Friendly -Recommendation 'Review the Errors worksheet and retry after remediation.'
                    Write-ChildStatusLine ("Failed to create user: {0}" -f $Record.EmployeeName)
                }
            }
        }
    }

    Invoke-ScriptStep -StepNumber 7 -TotalSteps $TotalSteps -Name 'Finalize workbook output' -ScriptBlock {
        if ($script:SelectedMode -eq 'TemplateOnly') {
            $script:RunSucceeded = $true
            return
        }

        Add-WorkbookWorksheet -Name 'Onboarded Users' -Rows $script:OnboardedRows -ColumnOrder @('EmployeeName','UserPrincipalName','DisplayName','GivenName','Surname','JobTitle','Department','CompanyName','OfficeLocation','EmployeeType','UsageLocation','AccountEnabled','ManagerSet','ManagerUPN','LicenseAssigned','LicenseName','LicenseSkuPartNumber','LicenseSkuId','LicenseStatus','TemporaryAccessPassCreated','TapStartUtc','TapLifetimeMinutes','ObjectId','Status') -Description 'Main detail worksheet for created Entra ID users.'
        Add-WorkbookWorksheet -Name 'Review Flags' -Rows $script:ReviewRows -ColumnOrder @('EmployeeName','Severity','Area','ReviewReason','Recommendation') -Description 'Items that require manual review after onboarding.'
        Add-WorkbookWorksheet -Name 'License Catalog' -Rows $script:LicenseRows -ColumnOrder @('Selected','DisplayName','SkuPartNumber','SkuId','AvailableUnits','EnabledUnits','ConsumedUnits','ExchangeServicePlans') -Description 'Mailbox-capable tenant license SKUs that were available for selection during onboarding.'
        Add-WorkbookWorksheet -Name 'Errors' -Rows $script:ErrorRows -ColumnOrder @('EmployeeName','Stage','ErrorMessage','Details','Timestamp') -Description 'Errors encountered during validation or user creation.'
        Add-WorkbookWorksheet -Name 'Sensitive Access' -Rows $script:SensitiveRows -ColumnOrder @('EmployeeName','UserPrincipalName','InitialPassword','TemporaryAccessPass','TapStartUtc','TapLifetimeMinutes','Notes') -Description 'Sensitive one-time onboarding access values. Store securely.'
        Add-WorkbookWorksheet -Name 'Source Records' -Rows $script:SourceRows -ColumnOrder @('EmployeeName','EmployeeType','Title','DOH','HomeDepartment','CostCenter','BusinessUnit','Leader','ManagerUPN','OfficeLocation','LaptopType','CellYN','CompanyVehicleYN','WorkingRemoteWFH','UserPrincipalName','MailNickname','UsageLocation','SourceText') -Description 'Normalized source input records used for this run.'

        Export-MOCWorkbook -Path $WorkbookPath -OpenAfterExport | Out-Null
        $script:Summary.CompletedDateTime = (Get-Date).ToString('o')
        $script:Summary.Counts['CreatedUsers'] = @($script:OnboardedRows).Count
        $script:Summary.Counts['Errors'] = @($script:ErrorRows).Count
        $script:Summary.Counts['ReviewFlags'] = @($script:ReviewRows).Count
        Set-MOCUtf8FileContent -Path $SummaryPath -Content ($script:Summary | ConvertTo-Json -Depth 8)
        $script:Summary.Files['Summary'] = $SummaryPath
        Write-ChildStatusLine ("Summary saved -> {0}" -f (Get-ReportDisplayPath -Path $SummaryPath))
    }

    $script:RunSucceeded = $true
    Update-ChildProgress -Activity $ScriptDisplayName -Percent 100 -Status 'Completed successfully. Press Enter to return to the menu.' -CurrentOperation ''
    Write-ChildOutputLine -Message ''
    Write-ChildOutputLine 'Run Summary'
    Write-ChildOutputLine '==========='
    if ($script:SelectedMode -eq 'TemplateOnly') {
        Write-ChildOutputLine ("Template: {0}" -f $TemplatePath)
    }
    else {
        Write-ChildOutputLine ("Created users: {0}" -f @($script:OnboardedRows).Count)
        Write-ChildOutputLine ("Review flags: {0}" -f @($script:ReviewRows).Count)
        Write-ChildOutputLine ("Errors: {0}" -f @($script:ErrorRows).Count)
        Write-ChildOutputLine ("Workbook: {0}" -f $WorkbookPath)
    }
    Write-ChildOutputLine ("Output folder: {0}" -f $ReportsDir)
}
catch {
    if ($script:ChildPromptCancellationRequested -or ([string]$_ -eq '__MOC_CHILD_PROMPT_CANCELLED__')) {
        $Reason = if (-not [string]::IsNullOrWhiteSpace($script:ChildPromptCancellationReason)) { $script:ChildPromptCancellationReason } else { 'Technician requested cancellation from an input prompt.' }
        $script:ExitRequested = $true
        Update-ChildProgress -Activity $ScriptDisplayName -Percent 100 -Status 'Stopped. Press Esc or Enter to return to the menu.' -CurrentOperation ''
        Write-ChildPromptCancellationMessage -Reason $Reason
        return
    }

    $FriendlyMessage = Get-FriendlyFailureMessage -Message $_.Exception.Message
    Update-ChildProgress -Activity $ScriptDisplayName -Percent 100 -Status 'Failed. Press Enter to return to the menu.' -CurrentOperation ''
    Write-ChildOutputLine -Message ''
    Write-ChildOutputLine ("ERROR: {0}" -f $FriendlyMessage) -Level Error
    Write-ChildOutputLine ("Troubleshooting folder retained: {0}" -f $ReportsDir) -Level Warning
    Write-ChildTranscriptLine ($_.ScriptStackTrace | Out-String)
    try {
        if (-not (Test-Path -LiteralPath $ReportsDir)) { New-Item -ItemType Directory -Path $ReportsDir -Force | Out-Null }
        if (@($script:OnboardedRows).Count -gt 0 -or @($script:ReviewRows).Count -gt 0 -or @($script:ErrorRows).Count -gt 0 -or @($script:SourceRows).Count -gt 0) {
            Add-WorkbookWorksheet -Name 'Onboarded Users' -Rows $script:OnboardedRows -ColumnOrder @('EmployeeName','UserPrincipalName','DisplayName','GivenName','Surname','JobTitle','Department','CompanyName','OfficeLocation','EmployeeType','UsageLocation','AccountEnabled','ManagerSet','ManagerUPN','LicenseAssigned','LicenseName','LicenseSkuPartNumber','LicenseSkuId','LicenseStatus','TemporaryAccessPassCreated','TapStartUtc','TapLifetimeMinutes','ObjectId','Status') -Description 'Main detail worksheet for created Entra ID users.'
            Add-WorkbookWorksheet -Name 'Review Flags' -Rows $script:ReviewRows -ColumnOrder @('EmployeeName','Severity','Area','ReviewReason','Recommendation') -Description 'Items that require manual review after onboarding.'
        Add-WorkbookWorksheet -Name 'License Catalog' -Rows $script:LicenseRows -ColumnOrder @('Selected','DisplayName','SkuPartNumber','SkuId','AvailableUnits','EnabledUnits','ConsumedUnits','ExchangeServicePlans') -Description 'Mailbox-capable tenant license SKUs that were available for selection during onboarding.'
            Add-WorkbookWorksheet -Name 'Errors' -Rows $script:ErrorRows -ColumnOrder @('EmployeeName','Stage','ErrorMessage','Details','Timestamp') -Description 'Errors encountered during validation or user creation.'
            Add-WorkbookWorksheet -Name 'Sensitive Access' -Rows $script:SensitiveRows -ColumnOrder @('EmployeeName','UserPrincipalName','InitialPassword','TemporaryAccessPass','TapStartUtc','TapLifetimeMinutes','Notes') -Description 'Sensitive one-time onboarding access values. Store securely.'
            Add-WorkbookWorksheet -Name 'Source Records' -Rows $script:SourceRows -ColumnOrder @('EmployeeName','EmployeeType','Title','DOH','HomeDepartment','CostCenter','BusinessUnit','Leader','ManagerUPN','OfficeLocation','LaptopType','CellYN','CompanyVehicleYN','WorkingRemoteWFH','UserPrincipalName','MailNickname','UsageLocation','SourceText') -Description 'Normalized source input records used for this run.'
            Export-MOCWorkbook -Path $WorkbookPath | Out-Null
        }
        $script:Summary.FailedDateTime = (Get-Date).ToString('o')
        $script:Summary.Failure = $FriendlyMessage
        Set-MOCUtf8FileContent -Path $SummaryPath -Content ($script:Summary | ConvertTo-Json -Depth 8)
    }
    catch {
        Write-ChildOutputLine ("Unable to write failure workbook or summary: {0}" -f $_.Exception.Message) -Level Warning
    }
    throw
}
finally {
    $FinalStatus = if ($script:ChildPromptCancellationRequested) { 'Stopped. Press Esc or Enter to return to the menu.' } elseif ($script:RunSucceeded) { 'Completed. Press Enter to return to the menu.' } else { 'Failed. Press Enter to return to the menu.' }
    Update-ChildProgress -Activity $ScriptDisplayName -Percent 100 -Status $FinalStatus -CurrentOperation ''
}