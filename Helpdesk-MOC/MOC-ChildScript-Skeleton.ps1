<#
.SYNOPSIS
MOC child-script skeleton for custom reporting/auditing scripts.

.DESCRIPTION
Use this as the baseline for new MOC child scripts. It is designed to be launched
from MOC.ps1, but can also run standalone for development.

Design standards learned from production MOC child scripts:
- MOC terminal window terminology and child-script responsibilities:

  ASCII reference layout:

  +--------------------------------------------------------------------------------+
  | 1. MOC Header / Tenant Status Header                                           |
  |    Logo, organization, menu version, tenant, auth state, current user.          |
  +--------------------------------------------------------------------------------+
  | 2. Breadcrumb / Navigation Path                                                 |
  |    Example: Home > Entra ID                                                     |
  +--------------------------------------------------------------------------------+
  | 3. Script Title Bar                                                             |
  |    Example: Running: Export-Something.ps1                                       |
  +--------------------------------------------------------------------------------+
  | 4. Progress / Activity Status Pane                                              |
  |    Overall activity, progress bar, percent, concise status/current operation.   |
  +--------------------------------------------------------------------------------+
  | 5. Run Output Pane                                                              |
  |    Script logs, detailed progress, prompt instructions/options, results, errors. |
  +--------------------------------------------------------------------------------+
  | 6. Output Scroll / Line Status Bar                                              |
  |    Parent-owned line count and visible range.                                   |
  +--------------------------------------------------------------------------------+
  | 7. Input / Run Footer Pane                                                      |
  |    Parent-owned input state, no-input state, run footer/status hints.            |
  +--------------------------------------------------------------------------------+
  | 8. Global Navigation / Command Bar                                              |
  |    Parent-owned keyboard shortcuts and global actions for the current screen.     |
  +--------------------------------------------------------------------------------+

  Strict child-script UI behavior:
  - Area 1 is parent-owned. Child scripts must not redraw or overwrite it.
  - Area 2 is parent-owned. Child scripts must not write breadcrumb text.
  - Area 3 is parent-owned from MOC script selection/metadata.
  - Area 4 is for Update-ChildProgress only: activity, percent, status, and short CurrentOperation text.
  - Area 5 is for Write-ChildOutputLine: logs, results, detailed prompts, prompt options, warnings, and errors. Child scripts may pass -Level to request parent-owned highlighting.
  - Area 6 is parent-owned. Child scripts must not attempt to write line counts or scroll state.
  - Area 7 is parent-owned input/footer state. Child scripts must use MOC parent prompt helpers for interactive input.
  - Area 8 is parent-owned global navigation/command reference. Child scripts must not write prompts, status, results, errors, or script output there.
  - MOC child scripts must never write UI messages directly to the raw host, console, output stream, warning stream, information stream, error stream, progress stream, or Out-Host during MOC execution.
  - Forbidden for MOC UI output: [Console]::Write(), [Console]::WriteLine(), [System.Console]::Out.WriteLine(), Write-Host, Write-Output, Write-Information, Write-Warning, Write-Error for display-only messages, Write-Progress, and Out-Host.
  - Allowed MOC UI paths: Write-ChildOutputLine for Area 5, Update-ChildProgress for Area 4, and approved MOC parent prompt helpers for Area 7.
  - Do not use Read-Host, [Console]::ReadLine(), [Console]::ReadKey(), [Console]::Write(), or [Console]::WriteLine() for MOC-run interactive input unless explicitly building a standalone-only fallback outside MOC.
  - For prompts, write the prompt title/options/instructions to Area 5, then call the approved MOC parent input helper so the active input state remains contained by MOC.
  - Keep prompt labels short; do not put long questions in Area 4.
  - Wrap or shorten long output lines before writing them to Area 5 so they do not break the run-window border.
- Parent MOC menu owns authentication, transcripts, terminal rendering, and live progress UI.
- Child scripts validate/reuse parent sessions only. Do not Connect-* or Disconnect-* from child scripts for services owned by MOC.
- Child scripts should not call Start-Transcript, Stop-Transcript, Clear-Host, Write-Host, Write-Output, Write-Warning, Write-Information, Write-Progress, Out-Host, [Console]::WriteLine(), [System.Console]::Out.WriteLine(), or other raw host/output stream calls for MOC UI messages.
- Use Write-ChildOutputLine for normal multi-line output in the script pane. Use -Level for important messages that need parent-owned visual emphasis.
- Use Write-ChildStatusLine only for concise status messages.
- Use Update-ChildProgress for overall child-script progress. Use -CurrentOperation for per-item details.
- Use Read-ChildMenuChoice for numbered menus. It writes the menu once to Area 5 and then uses the parent text input helper for Area 7. Do not use parent menu-choice helpers that repaint while waiting for input, because mouse-wheel or key activity can repeatedly add lines to the Run Output Pane.
- Reports are saved under: MOC\Reports\<Category>\<TimestampedRunFolder>\
- Transcripts are saved by the parent menu under: MOC\Transcript Logs\
- Script identity metadata should live in this comment block and be read with Get-MOCScriptMetadata.
- For XLSX output, use ImportExcel's Export-Excel pattern that is known to work in MOC:
  first worksheet with -ClearSheet, then additional worksheets with -Append.
- Flatten Graph/Exchange/Purview objects to simple scalar strings before exporting to Excel.
- Sanitize XLSX cell text before export: remove invalid Excel/XML control characters and cap oversized cells.
- Preserve expected worksheet schemas for empty worksheets by using the requested ColumnOrder.
- Keep worksheet names and table names safe and unique before writing.
- Apply MOC-consistent workbook formatting after Export-Excel writes the workbook: blue headers, wrapped long columns, auto-fit widths, and max-width caps.
- Auto-open only the final primary artifact after validating the file exists and is non-empty.
- If interactive Microsoft connections need -DisableWAM, add it in the MOC parent menu connection logic, not in child scripts.

.VERSION
1.6.2

.AUTHOR
Long

.CATEGORY
Template

.OUTPUTFORMAT
XLSX

.REQUIREDPOWERSHELLMODULES
Microsoft.Graph.Authentication
ImportExcel

.CREATED
2026-06-09

.LASTMODIFIED
2026-07-21

.REQUIREDGRAPHAPPSCOPES
None

.CHANGELOG
v1.6.2 - 2026-07-21
- Added child-output severity support. Future scripts can call Write-ChildOutputLine -Level Error/Warning/Critical/Action/Success/Prompt/Header/Muted so the parent MOC renderer highlights important Area 5 output consistently.
- Clarified that child scripts decide message severity while the parent MOC menu owns color/style rendering.

v1.6.1 - 2026-07-10
- Made the child skeleton the authoritative implementation for MOC UI/output behavior. Future prompts should reference this contract instead of duplicating helper logic.
- Updated Write-ChildOutputLine to use lower-level MOC renderers using either positional or -Message parameter forms, with no raw console/output fallback.
- Updated Update-ChildProgress to no-op safely when the parent progress renderer is unavailable instead of throwing or leaking progress text outside MOC panes.
- Clarified that prompt wording should require use of the skeleton helpers but not reimplement their internal behavior.

v1.6.0 - 2026-07-10
- Added strict output-boundary contract: child scripts must not use raw host/console/output/warning/error/progress/information streams for UI messages during MOC execution.
- Updated Write-ChildOutputLine so missing parent renderers fail closed instead of falling back to Write-Output and leaking text outside MOC panes.
- Updated Update-ChildProgress so missing parent progress renderers fail closed instead of writing progress text into the Run Output Pane or raw host.

v1.5.0 - 2026-07-08
- Updated Read-ChildMenuChoice to write menu options once to Area 5 and collect input through Read-ChildText/parent text input helpers.
- Avoids parent menu-choice repaint behavior that can increase Run Output Pane line counts while waiting for input or during mouse-wheel scrolling.
- Added explicit future-script standard: child prompts must not call parent repainting menu-choice helpers directly; use the skeleton wrapper only.

v1.4.0 - 2026-07-08
- Added Excel/XML-safe text sanitization for XLSX exports to prevent Excel repair prompts.
- Added cell text length capping to avoid oversized sharedStrings.xml entries.
- Updated empty worksheet handling so placeholder rows preserve the intended worksheet schema.
- Added unique worksheet-name handling for duplicate or truncated sheet names.
- Added post-export MOC workbook styling with blue headers, auto-fit widths, max-width caps, and wrap text for long columns.

v1.3.0 - 2026-06-29
- Added Area 8: Global Navigation / Command Bar to the MOC terminal window terminology.
- Clarified that child scripts must not write prompts, status, results, or errors to the parent-owned Global Navigation / Command Bar.

v1.2.0 - 2026-06-29
- Added MOC terminal window terminology for areas 1 through 7.
- Added ASCII reference layout documenting where prompts, progress, output, and input state belong.
- Added strict child-script UI behavior rules for future script creation.
- Added OUTPUTFORMAT and REQUIREDPOWERSHELLMODULES metadata fields to the skeleton standard.

v1.1.0 - 2026-06-25
- Replaced the prior native XLSX guidance with the ImportExcel Export-Excel pattern proven to work in MOC.
- Added Write-ChildOutputLine for main script-pane output separate from concise status/progress updates.
- Added Read-ChildMenuChoice wrapper for numbered menu prompts and 4/q/Esc return-to-menu behavior. In v1.5.0 this wrapper was updated to avoid direct parent repainting menu-choice calls.
- Added CurrentOperation support to Update-ChildProgress for enterprise-style overall progress plus per-item detail.
- Added scalar-safe Excel row normalization for complex Graph/Exchange/Purview objects.
- Added Export-MOCWorkbook helper using Summary first, -ClearSheet first, and -Append for additional worksheets.
- Added workbook validation before reporting success or auto-opening.
- Clarified that -DisableWAM belongs in MOC parent menu connection calls, not child scripts.

v1.0.5 - 2026-06-15
- Added reusable native XLSX helper standard for future child scripts.

v1.0.4 - 2026-06-10
- Removed example child-script Connect-* guidance.
- Clarified that child scripts validate/reuse MOC parent sessions only.

v1.0.3 - 2026-06-10
- Added REQUIREDGRAPHAPPSCOPES metadata standard.
- Added Assert-MOCGraphPermission helper for validating/reusing parent MOC Graph sessions without child Connect-* calls.
- Updated author standard to Long.

v1.0.2 - 2026-06-10
- Added standardized MOC metadata block fields.
- Added Get-MOCScriptMetadata helper.

v1.0.1 - 2026-06-09
- Added VERSION metadata guidance.

v1.0.0 - 2026-06-09
- Initial MOC child script skeleton.

.NOTES
CUSTOMIZATION CHECKLIST
1. Update this comment-based metadata block.
2. Update $RunFolderPrefix and $TotalSteps.
3. Add script-specific parameters.
4. Replace sample Invoke-ScriptStep blocks with your real workflow.
5. Stage report rows with Add-WorkbookWorksheet or export a single workbook with Export-MOCWorkbook.
6. If exporting XLSX, flatten rows first and use ConvertTo-ExcelSafeRows plus Export-MOCWorkbook.
7. Use Write-ChildOutputLine for visible script-pane text and Write-ChildStatusLine for compact status only. Use Write-ChildOutputLine -Level for parent-owned highlighting of errors, warnings, required permissions, and action steps.
8. Use Update-ChildProgress -CurrentOperation for per-item detail while keeping the main progress bar overall.
9. Follow the MOC terminal window area rules: progress in Area 4, prompt details/results in Area 5, input state in Area 7.
10. Do not use raw console input for MOC-run prompts; use parent MOC prompt helpers.
11. Do not add Connect-* or Disconnect-* calls for services owned by MOC.
12. Do not add -DisableWAM in child scripts. Put WAM suppression in MOC parent connection helpers.
13. Do not write raw Graph JSON directly into XLSX cells without ConvertTo-ExcelSafeValue/ConvertTo-ExcelSafeRows.
14. Keep long worksheet text columns wrapped and width-capped through Set-MOCWorkbookStyle.
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
# Metadata
############################################################################

function Get-MOCScriptMetadata {
    [CmdletBinding()]
    param([Parameter(Mandatory = $false)][string]$Path)

    $Metadata = [ordered]@{
        Synopsis = ''
        Description = ''
        Version = 'Unknown'
        Author = ''
        Category = ''
        Created = ''
        LastModified = ''
        ChangeLog = ''
        RequiredGraphAppScopes = @()
    }

    try {
        if ([string]::IsNullOrWhiteSpace($Path)) {
            if (-not [string]::IsNullOrWhiteSpace($PSCommandPath)) { $Path = $PSCommandPath }
            elseif ($MyInvocation.MyCommand.Path) { $Path = $MyInvocation.MyCommand.Path }
        }

        if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
            return [pscustomobject]$Metadata
        }

        $Raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
        $Header = $Raw
        if ($Raw -match '(?s)^\s*<#(?<header>.*?)#>') { $Header = $matches.header }

        foreach ($Name in @('SYNOPSIS','DESCRIPTION','VERSION','AUTHOR','CATEGORY','CREATED','LASTMODIFIED','CHANGELOG','REQUIREDGRAPHAPPSCOPES')) {
            $Pattern = "(?ims)^\s*\.$Name\s*(?<value>.*?)(?=^\s*\.[A-Z][A-Z0-9]*\s*|\z)"
            if ($Header -match $Pattern) {
                $Value = $matches.value.Trim()
                switch ($Name) {
                    'SYNOPSIS' { $Metadata.Synopsis = $Value }
                    'DESCRIPTION' { $Metadata.Description = $Value }
                    'VERSION' { $Metadata.Version = ($Value -split '\r?\n')[0].Trim() }
                    'AUTHOR' { $Metadata.Author = $Value }
                    'CATEGORY' { $Metadata.Category = $Value }
                    'CREATED' { $Metadata.Created = ($Value -split '\r?\n')[0].Trim() }
                    'LASTMODIFIED' { $Metadata.LastModified = ($Value -split '\r?\n')[0].Trim() }
                    'CHANGELOG' { $Metadata.ChangeLog = $Value }
                    'REQUIREDGRAPHAPPSCOPES' {
                        $Metadata.RequiredGraphAppScopes = @(
                            ($Value -split '\r?\n') |
                            ForEach-Object { $_.Trim() } |
                            Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and $_ -notmatch '^(None|N/A|NotRequired)$' }
                        )
                    }
                }
            }
        }
    }
    catch {
        $Metadata.Description = 'Unable to read script metadata.'
    }

    return [pscustomobject]$Metadata
}

############################################################################
# Script Identity
############################################################################

$ScriptMetadata = Get-MOCScriptMetadata -Path $PSCommandPath
$ScriptName = if (-not [string]::IsNullOrWhiteSpace($ScriptMetadata.Synopsis)) { $ScriptMetadata.Synopsis } else { 'MOC Child Script' }
$Version = $ScriptMetadata.Version
$ScriptCategory = if (-not [string]::IsNullOrWhiteSpace($ScriptMetadata.Category)) { $ScriptMetadata.Category } else { 'Uncategorized' }
$RunFolderPrefix = 'Custom-Report'
$TotalSteps = 4

############################################################################
# MOC / Standalone Path Bootstrap
############################################################################

$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path $script:MyInvocation.MyCommand.Path }

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
        $CategoryName = if (-not [string]::IsNullOrWhiteSpace($ScriptCategory)) { $ScriptCategory } else { Split-Path -Leaf $ScriptDir }
        if ([string]::IsNullOrWhiteSpace($CategoryName)) { $CategoryName = 'Uncategorized' }

        if ($MOCReportsRootVar -and -not [string]::IsNullOrWhiteSpace([string]$MOCReportsRootVar.Value)) {
            $ReportsRoot = Join-Path ([string]$MOCReportsRootVar.Value) $CategoryName
        }
        else {
            $ReportsRoot = Join-Path (Join-Path $MOCRootPath 'Reports') $CategoryName
        }
    }
}

$RunStamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
$ReportsDir = Join-Path $ReportsRoot ("{0}-{1}" -f $RunFolderPrefix, $RunStamp)
$SummaryPath = Join-Path $ReportsDir ("{0}-Summary-{1}.json" -f $RunFolderPrefix, $RunStamp)
$AuditNotesPath = Join-Path $ReportsDir ("{0}-Audit-Notes-{1}.csv" -f $RunFolderPrefix, $RunStamp)
$WorkbookPath = Join-Path $ReportsDir ("{0}-{1}.xlsx" -f $RunFolderPrefix, $RunStamp)

$script:MOCRootPath = $MOCRootPath
$script:ReportsRoot = $ReportsRoot
$script:ReportsDir = $ReportsDir
$script:AuditNotes = [System.Collections.ArrayList]::new()
$script:WorkbookSheets = [System.Collections.ArrayList]::new()
$script:Summary = [ordered]@{
    ScriptName = $ScriptName
    Version = $Version
    RunDateTime = (Get-Date).ToString('o')
    OutputFolder = $ReportsDir
    UseExistingSession = [bool]$UseExistingSession
    Counts = [ordered]@{}
    Files = [ordered]@{}
    Warnings = [System.Collections.ArrayList]::new()
}

############################################################################
# MOC-Safe Output Helpers
############################################################################

function Write-ChildOutputLine {
    <#
    .SYNOPSIS
    Writes a child-script line to MOC Area 5 only.

    .DESCRIPTION
    This is the authoritative output boundary for MOC child scripts. It supports
    MOC parent versions that expose either Write-MOCOutputLine or
    Write-MOCStatusLine, and it supports both positional and -Message parameter
    forms used across MOC builds.

    The optional -Level parameter lets child scripts classify message importance
    while the parent MOC renderer owns color/style decisions. Use Error/Critical
    for stop conditions, Warning for caution headings, Action for remediation
    steps, Success for successful outcomes, Prompt for input guidance, Header for
    section headings, and Muted for secondary detail.

    It must never fall back to Write-Output, Write-Host, raw console writes,
    warning/information streams, or Out-Host. If no MOC-safe renderer is
    available, it fails closed to avoid leaking text outside the Run Output Pane.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false, ValueFromPipeline = $true, ValueFromRemainingArguments = $true)]
        [AllowNull()]
        [object[]]$Message,

        [ValidateSet('Info','Success','Warning','Error','Critical','Action','Prompt','Header','Muted')]
        [string]$Level = 'Info'
    )

    process {
        $Text = (@($Message) | ForEach-Object { if ($null -eq $_) { '' } else { [string]$_ } }) -join ' '
        if ([string]::IsNullOrWhiteSpace($Text)) { return }

        if (Get-Command -Name Write-MOCOutputLine -ErrorAction SilentlyContinue) {
            try { $null = Write-MOCOutputLine -Message $Text -Level $Level; return } catch { }
            try { $null = Write-MOCOutputLine $Text -Level $Level; return } catch { }
            try { $null = Write-MOCOutputLine -Message $Text; return } catch { }
            try { $null = Write-MOCOutputLine $Text; return } catch { }
        }

        if (Get-Command -Name Write-MOCStatusLine -ErrorAction SilentlyContinue) {
            try { $null = Write-MOCStatusLine -Message $Text -Level $Level; return } catch { }
            try { $null = Write-MOCStatusLine $Text -Level $Level; return } catch { }
            try { $null = Write-MOCStatusLine -Message $Text; return } catch { }
            try { $null = Write-MOCStatusLine $Text; return } catch { }
        }

        throw 'No MOC-safe output renderer is available. Refusing to write outside the MOC Run Output Pane.'
    }
}

function Write-ChildStatusLine {
    # Writes concise MOC-safe status text. Prefer Write-ChildOutputLine for detailed output in Area 5.
    [CmdletBinding()]
    param([Parameter(Mandatory = $false, ValueFromPipeline = $true, ValueFromRemainingArguments = $true)][AllowNull()][object[]]$Message)

    process {
        $Text = (@($Message) | ForEach-Object { if ($null -eq $_) { '' } else { [string]$_ } }) -join ' '
        if ([string]::IsNullOrWhiteSpace($Text)) { return }

        if (Get-Command -Name Write-MOCStatusLine -ErrorAction SilentlyContinue) {
            try { $null = Write-MOCStatusLine $Text; return } catch { }
            try { $null = Write-MOCStatusLine -Message $Text; return } catch { }
        }

        Write-ChildOutputLine $Text
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
        [Parameter(Mandatory = $true)][double]$Percent,
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

function Get-ReportDisplayPath {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    $Leaf = Split-Path -Leaf $Path
    $Category = Split-Path -Leaf $ReportsRoot
    if ([string]::IsNullOrWhiteSpace($Category)) { $Category = 'Reports' }
    return ("Reports\{0}\{1}" -f $Category, $Leaf)
}

############################################################################
# Input Helpers
############################################################################

function Read-ChildMenuChoice {
    <#
    .SYNOPSIS
    MOC-safe numbered menu prompt for child scripts.

    .DESCRIPTION
    Writes the menu body exactly once to Area 5 using Write-ChildOutputLine, then
    collects the user selection through Read-ChildText so the parent MOC input
    state remains contained in Area 7. This intentionally does not call
    Read-MOCMenuChoice directly. Some parent menu-choice renderers repaint their
    menu while waiting for input; when a user mouse-wheel scrolls during the
    prompt, that repaint behavior can append duplicate menu lines and increase
    the Run Output Pane line count.
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

    $Allowed = @($ValidChoices)
    if ($AllowExit) { $Allowed += @('4','q','esc') }

    Write-ChildOutputLine $Title
    Write-ChildOutputLine ('-' * $Title.Length)
    foreach ($Option in $Options) { Write-ChildOutputLine $Option }
    if ($AllowExit) { Write-ChildOutputLine '4. Exit and return to MOC menu' }

    $ChoiceHelp = if ($AllowExit) { (($ValidChoices + @('4','q','Esc')) -join '/') } else { ($ValidChoices -join '/') }
    if (-not [string]::IsNullOrWhiteSpace($DefaultChoice)) {
        Write-ChildOutputLine ("{0} ({1}; default {2})" -f $Prompt, $ChoiceHelp, $DefaultChoice)
    }
    else {
        Write-ChildOutputLine ("{0} ({1})" -f $Prompt, $ChoiceHelp)
    }

    while ($true) {
        $RawChoice = Read-ChildText -Prompt $Prompt -AllowEmpty
        $Choice = ([string]$RawChoice).Trim()

        if ([string]::IsNullOrWhiteSpace($Choice) -and -not [string]::IsNullOrWhiteSpace($DefaultChoice)) {
            $Choice = $DefaultChoice
        }

        $ChoiceLower = $Choice.ToLowerInvariant()
        if ($AllowExit -and ($ChoiceLower -in @('4','q','esc'))) {
            Write-ChildOutputLine 'Selected option: Exit and return to MOC menu'
            return 'ExitToMenu'
        }

        if ($Choice -in $ValidChoices) {
            Write-ChildOutputLine ("Selected option: {0}" -f $Choice)
            return $Choice
        }

        $Help = if ($AllowExit) { (($ValidChoices + @('4','q','Esc')) -join ', ') } else { ($ValidChoices -join ', ') }
        if (-not [string]::IsNullOrWhiteSpace($DefaultChoice)) {
            Write-ChildOutputLine ("Invalid selection. Please enter {0}, or press Enter for {1}." -f $Help, $DefaultChoice)
        }
        else {
            Write-ChildOutputLine ("Invalid selection. Please enter {0}." -f $Help)
        }
    }
}

function Read-ChildText {
    # Uses parent MOC input helpers so prompt/input behavior remains contained by MOC.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Prompt,
        [Parameter(Mandatory = $false)][switch]$AllowEmpty
    )

    if (Get-Command Read-MOCText -ErrorAction SilentlyContinue) {
        return [string](Read-MOCText -Prompt $Prompt -AllowEmpty:$AllowEmpty)
    }

    if (Get-Command Read-MOCTextPrompt -ErrorAction SilentlyContinue) {
        return [string](Read-MOCTextPrompt -Prompt $Prompt -AllowEmpty:$AllowEmpty)
    }

    return [string](Read-Host $Prompt)
}

############################################################################
# Session Validation Helpers
############################################################################

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

function Assert-MOCGraphPermission {
    [CmdletBinding()]
    param([Parameter(Mandatory = $false)][string[]]$RequiredScopes = @($ScriptMetadata.RequiredGraphAppScopes))

    $RequiredScopes = @(($RequiredScopes | Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and $_ -notmatch '^(None|N/A|NotRequired)$' }) | Select-Object -Unique)
    if ($RequiredScopes.Count -eq 0) { return $true }

    if (-not (Get-Command Get-MgContext -ErrorAction SilentlyContinue)) {
        throw "Microsoft Graph PowerShell context is not available. Authenticate from the MOC menu and try again. Required Graph permissions: $($RequiredScopes -join ', ')."
    }

    $Context = Get-MgContext -ErrorAction SilentlyContinue
    if ($null -eq $Context) {
        throw "Microsoft Graph connection not detected. Authenticate from the MOC menu and try again. Required Graph permissions: $($RequiredScopes -join ', ')."
    }

    $Mode = Get-MOCGraphConnectionMode
    if ($Mode -eq 'Delegated') {
        $AvailableScopes = @($Context.Scopes)
        $MissingScopes = @($RequiredScopes | Where-Object { $AvailableScopes -notcontains $_ })
        if ($MissingScopes.Count -gt 0) {
            throw "Microsoft Graph delegated session is missing required scope(s): $($MissingScopes -join ', ')."
        }
    }
    elseif ($Mode -eq 'AppOnly') {
        Write-ChildStatusLine "Graph app-only session detected. Required app permissions: $($RequiredScopes -join ', ')"
    }
    else {
        throw "Microsoft Graph connection state is unknown. Authenticate from the MOC menu and try again."
    }

    return $true
}

############################################################################
# Audit / Summary Helpers
############################################################################

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

function Export-AuditCsv {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Rows,
        [Parameter(Mandatory = $true)][string]$FileName,
        [Parameter(Mandatory = $false)][string]$SummaryKey
    )

    if (-not (Test-Path -LiteralPath $ReportsDir)) { New-Item -ItemType Directory -Path $ReportsDir -Force | Out-Null }

    $CsvPath = Join-Path $ReportsDir $FileName
    $ArrayRows = @($Rows)
    $ArrayRows | Export-Csv -Path $CsvPath -NoTypeInformation -Encoding UTF8

    $RowCount = @($ArrayRows).Count
    Write-ChildStatusLine ("Exported {0} row(s) -> {1}" -f $RowCount, (Get-ReportDisplayPath -Path $CsvPath))
    Write-ChildTranscriptLine ("Exported {0} row(s) to {1}" -f $RowCount, $CsvPath)

    if (-not [string]::IsNullOrWhiteSpace($SummaryKey)) {
        $script:Summary.Counts[$SummaryKey] = $RowCount
        $script:Summary.Files[$SummaryKey] = $CsvPath
    }

    return $CsvPath
}

############################################################################
# XLSX Helpers - ImportExcel pattern proven to work in MOC
############################################################################

function ConvertTo-ExcelSafeText {
    [CmdletBinding()]
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) { return '' }

    $Text = [string]$Value

    # XLSX workbooks are XML packages. Some Microsoft Graph/Exchange/Purview values can
    # include control characters that are valid in PowerShell strings but invalid in Excel XML.
    # Leaving these in sharedStrings.xml can trigger Excel's repair prompt on open.
    $Text = $Text -replace '[\x00-\x08\x0B\x0C\x0E-\x1F]', ' '

    # Excel's documented cell text limit is 32,767 characters. Keep a small buffer so
    # large raw JSON values do not create borderline workbook repair issues.
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
        $Parts = foreach ($Key in $Value.Keys) {
            '{0}={1}' -f $Key, (ConvertTo-ExcelSafeValue -Value $Value[$Key])
        }
        return (ConvertTo-ExcelSafeText -Value (@($Parts) -join '; '))
    }

    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        $Parts = foreach ($Item in $Value) {
            if ($null -ne $Item) { [string](ConvertTo-ExcelSafeValue -Value $Item) }
        }
        return (ConvertTo-ExcelSafeText -Value (@($Parts) -join '; '))
    }

    try {
        $Json = $Value | ConvertTo-Json -Depth 12 -Compress -ErrorAction Stop
        if (-not [string]::IsNullOrWhiteSpace($Json) -and $Json -notmatch '^".*"$') {
            return (ConvertTo-ExcelSafeText -Value $Json)
        }
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
        if (-not [string]::IsNullOrWhiteSpace($Column) -and -not $Columns.Contains($Column)) {
            [void]$Columns.Add($Column)
        }
    }

    if ($InputRows.Count -eq 0) {
        if ($Columns.Count -eq 0) { [void]$Columns.Add('Note') }

        $Object = [ordered]@{}
        foreach ($Column in $Columns) { $Object[$Column] = '' }

        if ($Object.Contains('Note')) {
            $Object['Note'] = 'No rows returned for this worksheet.'
        }
        elseif ($Columns.Count -gt 0) {
            $Object[$Columns[0]] = 'No rows returned for this worksheet.'
        }

        return @([pscustomobject]$Object)
    }

    foreach ($Row in $InputRows) {
        if ($null -eq $Row) { continue }
        foreach ($Property in @($Row.PSObject.Properties)) {
            if (-not [string]::IsNullOrWhiteSpace($Property.Name) -and -not $Columns.Contains($Property.Name)) {
                [void]$Columns.Add($Property.Name)
            }
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
    Write-ChildStatusLine ("Staged {0} row(s) for workbook worksheet '{1}'." -f $SafeRows.Count, $Name)
}

function Assert-ImportExcelAvailable {
    [CmdletBinding()]
    param()

    if (-not (Get-Command Export-Excel -ErrorAction SilentlyContinue)) {
        try { Import-Module ImportExcel -ErrorAction Stop }
        catch {
            throw "The ImportExcel PowerShell module is required for XLSX output. Install ImportExcel or add it to the MOC module load path. Details: $($_.Exception.Message)"
        }
    }
}

function Get-WorkbookSummaryRows {
    [CmdletBinding()]
    param()

    $Rows = [System.Collections.ArrayList]::new()
    [void]$Rows.Add([pscustomobject][ordered]@{ Section = 'Run'; Name = 'Script'; Count = ''; Worksheet = ''; Description = $ScriptName; Value = $ScriptName })
    [void]$Rows.Add([pscustomobject][ordered]@{ Section = 'Run'; Name = 'Version'; Count = ''; Worksheet = ''; Description = 'Script version executed.'; Value = $Version })
    [void]$Rows.Add([pscustomobject][ordered]@{ Section = 'Run'; Name = 'Generated'; Count = ''; Worksheet = ''; Description = 'Report generation timestamp.'; Value = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') })
    [void]$Rows.Add([pscustomobject][ordered]@{ Section = 'Run'; Name = 'OutputFolder'; Count = ''; Worksheet = ''; Description = 'Folder where all output files were written.'; Value = $ReportsDir })

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
                if ($Worksheet.Column($Column).Width -gt 70) {
                    $Worksheet.Column($Column).Width = 70
                }
            }

            $LongColumnNames = @(
                'SettingValue',
                'PolicyAValue',
                'PolicyBValue',
                'AssignmentSummary',
                'ReviewReason',
                'RawValueJson',
                'Error',
                'ErrorMessage',
                'Exception',
                'Uri',
                'Description',
                'Notes'
            )

            for ($Column = 1; $Column -le $Worksheet.Dimension.End.Column; $Column++) {
                $HeaderText = [string]$Worksheet.Cells[1, $Column].Text
                if ($LongColumnNames -contains $HeaderText) {
                    $Worksheet.Column($Column).Style.WrapText = $true
                    if ($Worksheet.Column($Column).Width -lt 35) {
                        $Worksheet.Column($Column).Width = 35
                    }
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

function Export-MOCWorkbook {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $false)][switch]$OpenAfterExport
    )

    Assert-ImportExcelAvailable

    $WorkbookDirectory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $WorkbookDirectory)) {
        New-Item -ItemType Directory -Path $WorkbookDirectory -Force | Out-Null
    }
    if (Test-Path -LiteralPath $Path) {
        Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    }

    Write-ChildStatusLine "Creating Excel workbook: $Path"

    $SummaryRows = @(ConvertTo-ExcelSafeRows -Rows @(Get-WorkbookSummaryRows) -ColumnOrder @('Section','Name','Count','Worksheet','Description','Value'))
    $SummaryRows |
        Export-Excel -Path $Path -WorksheetName 'Summary' -TableName 'Summary' -TableStyle Light9 -AutoSize -FreezeTopRow -BoldTopRow -ClearSheet

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
            $ShortBase = if ($WorksheetNameBase.Length -gt $BaseMaxLength) {
                $WorksheetNameBase.Substring(0, $BaseMaxLength)
            }
            else {
                $WorksheetNameBase
            }
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
        $Rows |
            Export-Excel -Path $Path -WorksheetName $WorksheetName -TableName $TableName -TableStyle Light9 -AutoSize -FreezeTopRow -BoldTopRow -Append
    }

    Set-MOCWorkbookStyle -Path $Path

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Workbook writer completed without error, but file was not found: $Path"
    }

    $WorkbookItem = Get-Item -LiteralPath $Path -ErrorAction Stop
    if ($WorkbookItem.Length -le 0) {
        throw "Workbook file was created but its size is 0 bytes: $Path"
    }

    $script:Summary.Files['Workbook'] = $Path
    Write-ChildStatusLine ("Excel workbook written -> {0}" -f (Get-ReportDisplayPath -Path $Path))
    Write-ChildStatusLine ("Workbook size: {0:N0} bytes" -f $WorkbookItem.Length)

    if ($OpenAfterExport) {
        Open-MOCOutputFile -Path $Path -Description 'Excel workbook'
    }

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
            Add-AuditNote -Severity 'Warning' -Area 'Open output file' -Message ("Could not open {0} automatically because the file was not found: {1}" -f $Description, $Path)
            return
        }

        Invoke-Item -LiteralPath $Path -ErrorAction Stop
        Write-ChildStatusLine ("Opened {0}." -f $Description)
        Write-ChildTranscriptLine ("Opened {0}: {1}" -f $Description, $Path)
    }
    catch {
        Add-AuditNote -Severity 'Warning' -Area 'Open output file' -Message ("{0} was created but could not be opened automatically. {1}" -f $Description, $_.Exception.Message)
    }
}

############################################################################
# Step Runner
############################################################################

function Invoke-ScriptStep {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][int]$StepNumber,
        [Parameter(Mandatory = $true)][int]$TotalSteps,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$ScriptBlock
    )

    $Percent = (($StepNumber - 1) / [Math]::Max($TotalSteps, 1)) * 100
    Update-ChildProgress -Activity $ScriptName -Percent $Percent -Status ("Step {0} of {1} - {2}" -f $StepNumber, $TotalSteps, $Name) -CurrentOperation ''

    Write-ChildOutputLine ''
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
        $Message = "ERROR during step '{0}': {1}" -f $Name, $_.Exception.Message
        Add-AuditNote -Severity 'Error' -Area $Name -Message $Message
        throw
    }

    $Percent = ($StepNumber / [Math]::Max($TotalSteps, 1)) * 100
    Update-ChildProgress -Activity $ScriptName -Percent $Percent -Status ("Completed Step {0} of {1} - {2}" -f $StepNumber, $TotalSteps, $Name) -CurrentOperation ''
}

############################################################################
# Main
############################################################################

$script:RunSucceeded = $false

try {
    if (-not (Test-Path -LiteralPath $ReportsDir)) { New-Item -ItemType Directory -Path $ReportsDir -Force | Out-Null }

    # Example menu. Remove this block if the child script does not need an option prompt.
    $Choice = Read-ChildMenuChoice `
        -Title 'Example Export Options' `
        -Options @('1. Export all rows','2. Export filtered rows','3. Export summary only') `
        -Prompt 'Select export option' `
        -ValidChoices @('1','2','3') `
        -DefaultChoice '1' `
        -AllowExit

    if ($Choice -eq 'ExitToMenu') {
        Write-ChildStatusLine 'User selected exit. Returning to MOC menu without creating a report.'
        return
    }

    Update-ChildProgress -Activity $ScriptName -Percent 0 -Status 'Starting' -CurrentOperation ''
    Write-ChildOutputLine 'ERock M365 Operations Console (MOC)'
    Write-ChildOutputLine $ScriptName
    Write-ChildOutputLine ('Run started:   {0}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
    Write-ChildOutputLine ('Output folder: {0}' -f (Get-ReportDisplayPath -Path $ReportsDir))
    Write-ChildTranscriptLine ('Full output folder: {0}' -f $ReportsDir)

    Invoke-ScriptStep -StepNumber 1 -TotalSteps $TotalSteps -Name 'Initialize script' -ScriptBlock {
        # Add required module checks/imports here. Do not connect to MOC-owned services here.
        Write-ChildStatusLine 'Initialization completed.'
    }

    Invoke-ScriptStep -StepNumber 2 -TotalSteps $TotalSteps -Name 'Validate parent session' -ScriptBlock {
        if ($script:MOC_Authenticated -eq $true -or $UseExistingSession) {
            Write-ChildStatusLine 'Reusing parent MOC authentication session.'
        }
        elseif ($SkipConnect) {
            Write-ChildStatusLine 'Connection validation skipped by parameter.'
        }
        else {
            throw 'Parent MOC authentication session was not detected. Authenticate from the MOC menu and try again.'
        }
    }

    Invoke-ScriptStep -StepNumber 3 -TotalSteps $TotalSteps -Name 'Collect evidence' -ScriptBlock {
        $Rows = @(
            [pscustomobject][ordered]@{ Name = 'Example Item 1'; Status = 'Review'; Notes = 'Replace this sample data with real audit output.' },
            [pscustomobject][ordered]@{ Name = 'Example Item 2'; Status = 'OK'; Notes = 'Second sample row.' }
        )

        Add-WorkbookWorksheet -Name 'Example Report' -Rows $Rows -ColumnOrder @('Name','Status','Notes') -Description 'Example worksheet showing how to stage rows for the final workbook.'

        # Per-item detail should go to CurrentOperation while the main bar remains overall progress.
        Update-ChildProgress -Activity $ScriptName -Percent 75 -Status 'Step 3 of 4 - Collect evidence' -CurrentOperation 'Processed example rows.'
    }

    Invoke-ScriptStep -StepNumber 4 -TotalSteps $TotalSteps -Name 'Finalize outputs' -ScriptBlock {
        if ($script:AuditNotes.Count -gt 0) {
            Export-AuditCsv -Rows $script:AuditNotes -FileName (Split-Path -Leaf $AuditNotesPath) -SummaryKey 'AuditNotes' | Out-Null
        }

        Export-MOCWorkbook -Path $WorkbookPath -OpenAfterExport | Out-Null

        $script:Summary.CompletedDateTime = (Get-Date).ToString('o')
        Set-MOCUtf8FileContent -Path $SummaryPath -Content ($script:Summary | ConvertTo-Json -Depth 8)
        Write-ChildStatusLine ("Summary saved -> {0}" -f (Get-ReportDisplayPath -Path $SummaryPath))
    }

    $script:RunSucceeded = $true
    Update-ChildProgress -Activity $ScriptName -Percent 100 -Status 'Completed successfully. Press Enter to return to the menu.' -CurrentOperation ''

    Write-ChildOutputLine ''
    Write-ChildOutputLine 'Run Summary'
    Write-ChildOutputLine '==========='
    Write-ChildOutputLine ("Workbook: {0}" -f $WorkbookPath)
    Write-ChildOutputLine ("Output folder: {0}" -f $ReportsDir)
}
catch {
    Update-ChildProgress -Activity $ScriptName -Percent 100 -Status 'Failed. Press Enter to return to the menu.' -CurrentOperation ''
    Write-ChildOutputLine ''
    Write-ChildOutputLine ("ERROR: {0}" -f $_.Exception.Message)
    Write-ChildTranscriptLine ($_.ScriptStackTrace | Out-String)
    throw
}
finally {
    # Do not Stop-Transcript here. The parent MOC menu owns transcripts.
    # Do not Disconnect-* here for parent-owned services.
    # Do not Clear-Host here. The parent MOC menu owns terminal rendering.
}
