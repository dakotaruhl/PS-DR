<#
.SYNOPSIS
Helpdesk - M365 Operations Console (Helpdesk-MOC)

.DESCRIPTION
PowerShell terminal UI launcher for Microsoft 365 administration scripts.

The MOC menu owns authentication, progress rendering, input prompts, parent-level
transcripts, root Reports storage, and child-script launch orchestration.

.VERSION
1.13.83

.AUTHOR
Long

.CATEGORY
MOC Core

.OUTPUTFORMAT
N/A

.CREATED
2026-06-08

.LASTMODIFIED
2026-08-13

.CHANGELOG
See CHANGELOG.md in the HelpDesk-MOC folder for the full release history.
Current: v1.13.82 - U: Update now reports one combined menu/CHANGELOG/child-script summary and allows output review scrolling before returning to the menu.
#>

#Requires -Version 7.2

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

function Get-MOCScriptMetadata {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Path
    )

    $Metadata = [ordered]@{
        Synopsis     = ''
        Description  = ''
        Version      = 'Unknown'
        Author       = ''
        Category     = ''
        Created      = ''
        LastModified = ''
        ChangeLog    = ''
        RequiredGraphAppScopes = @()
        RequiredPowerShellModules = @()
        OutputFormat = ''
    }

    try {
        if ([string]::IsNullOrWhiteSpace($Path)) {
            if (-not [string]::IsNullOrWhiteSpace($PSCommandPath)) {
                $Path = $PSCommandPath
            }
            elseif ($MyInvocation.MyCommand.Path) {
                $Path = $MyInvocation.MyCommand.Path
            }
        }

        if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
            return [pscustomobject]$Metadata
        }

        $Raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop

        $Header = $Raw
        if ($Raw -match '(?s)^\s*<#(?<header>.*?)#>') {
            $Header = $matches.header
        }

        foreach ($Name in @('SYNOPSIS','DESCRIPTION','VERSION','AUTHOR','CATEGORY','CREATED','LASTMODIFIED','OUTPUTFORMAT','CHANGELOG','REQUIREDGRAPHAPPSCOPES','REQUIREDPOWERSHELLMODULES')) {
            $Pattern = "(?ims)^\s*\.$Name\s*(?<value>.*?)(?=^\s*\.[A-Z][A-Z0-9]*\s*|\z)"
            if ($Header -match $Pattern) {
                $Value = $matches.value.Trim()
                switch ($Name) {
                    'SYNOPSIS'     { $Metadata.Synopsis = $Value }
                    'DESCRIPTION'  { $Metadata.Description = $Value }
                    'VERSION'      { $Metadata.Version = ($Value -split '\r?\n')[0].Trim() }
                    'AUTHOR'       { $Metadata.Author = $Value }
                    'CATEGORY'     { $Metadata.Category = $Value }
                    'CREATED'      { $Metadata.Created = ($Value -split '\r?\n')[0].Trim() }
                    'LASTMODIFIED' { $Metadata.LastModified = ($Value -split '\r?\n')[0].Trim() }
                    'OUTPUTFORMAT' { $Metadata.OutputFormat = ($Value -split '\r?\n')[0].Trim() }
                    'CHANGELOG'    { $Metadata.ChangeLog = $Value }
                    'REQUIREDGRAPHAPPSCOPES' {
                        $Metadata.RequiredGraphAppScopes = @(
                            ($Value -split '\r?\n') |
                            ForEach-Object { $_.Trim() } |
                            Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and $_ -notmatch '^(None|N/A|NotRequired)$' }
                        )
                    }
                    'REQUIREDPOWERSHELLMODULES' {
                        $Metadata.RequiredPowerShellModules = @(
                            ($Value -split '\r?\n') |
                            ForEach-Object { $_.Trim() } |
                            Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and $_ -notmatch '^(None|N/A|NotRequired)$' }
                        )
                    }
                }
            }
        }

        if ([string]::IsNullOrWhiteSpace($Metadata.Description)) {
            $Metadata.Description = 'No .DESCRIPTION metadata found in this script.'
        }
    }
    catch {
        $Metadata.Description = 'Unable to read script metadata.'
    }

    return [pscustomobject]$Metadata
}

# ------------------------------------------------------------
# Cursor safety
# ------------------------------------------------------------
try {
    $OriginalCursorSize = $Host.UI.RawUI.CursorSize
    $Host.UI.RawUI.CursorSize = 0
} catch {}

# ------------------------------------------------------------
# Config
# ------------------------------------------------------------
$RootPath       = $PSScriptRoot
$RunFirstFolder = '+InstallModules - Run First'
$LogDir         = Join-Path $RootPath 'Launcher-Reports'
$TranscriptLogDir = Join-Path $RootPath 'Transcript Logs'
$ReportsRootDir = Join-Path $RootPath 'Reports'
$HiddenMenuFolders = @(
    'Transcript Logs',
    'Transcript',
    'Launcher-Reports',
    'Reports',
    '.MOC-Update-Staging',
    '.MOC-Update-Backups'
)

# Transcript logging is line/event based during child script runs.
# Earlier versions mirrored every live MOC redraw frame, which made transcript
# logs huge and repetitive. The transcript now records each output/status line
# once as it enters the run-console buffer, plus explicit transcript-only detail
# from child scripts.
$script:MOC_FrameTranscriptMirrorEnabled = $false
$script:MOC_ActiveTranscriptPath = $null
$script:MOC_SoftRedrawEnabled = $true
$script:MOC_CurrentFrameLineCount = 0
$script:MOC_LastFrameLineCount = 0
$script:MOC_CurrentFrameBuffer = [System.Collections.Generic.List[string]]::new()
$script:MOC_LastFrameBuffer = @()
$script:MOC_FrameBufferActive = $false
$script:MOC_AlternateScreenActive = $false
$script:MOC_ExitRequested = $false
$script:MOC_ExitCompleted = $false
$script:MOC_RestartRequested = $false
$script:MOC_RestartScriptPath = ''
$script:MOC_RestartReason = ''
$script:MOC_RestartCountdownSeconds = 15
    $script:MOC_CurrentScriptCategory = $null
    $script:MOC_CurrentScriptReportsRoot = $null

if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir | Out-Null
}

if (-not (Test-Path $TranscriptLogDir)) {
    New-Item -ItemType Directory -Path $TranscriptLogDir | Out-Null
}

# Root Reports folder is created lazily by Get-MOCScriptReportsRoot when a child script runs.

$LogFile = Join-Path $LogDir ("Launcher-{0}.log" -f (Get-Date -Format 'yyyy-MM-dd'))
$script:MOC_LocalSessionUser = if (-not [string]::IsNullOrWhiteSpace($env:USERNAME)) { $env:USERNAME } elseif (-not [string]::IsNullOrWhiteSpace($env:USER)) { $env:USER } else { [System.Environment]::UserName }
$CurrentUser = $script:MOC_LocalSessionUser

$script:MOC_Metadata = Get-MOCScriptMetadata -Path $PSCommandPath
$script:MOC_Version = if (-not [string]::IsNullOrWhiteSpace($script:MOC_Metadata.Version)) { $script:MOC_Metadata.Version } else { 'Unknown' }
$script:MOC_RootPath = $RootPath
$script:MOC_ReportsRootPath = $ReportsRootDir
$script:MOC_Authenticated = $false
$script:MOC_GraphTenantId = ''
$script:MOC_OrganizationName = ''
$script:MOC_LastScript = ''
$script:MOC_LastDuration = ''
$script:MOC_LastStatus = 'Ready'
$script:MOC_SessionId = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
$script:MOC_SessionStarted = Get-Date
$script:MOC_SessionIndexPath = $null
$script:MOC_SessionIndexEntries = [System.Collections.Generic.List[object]]::new()

$script:MOC_TargetWidth = 140
$script:MOC_TargetHeight = 44
$script:MOC_MinWidth = 100
$script:MOC_MinHeight = 30
$script:MOC_CompactWidth = 118
$script:MOC_CompactHeight = 36
$script:MOC_LastWindowWidth = 0
$script:MOC_LastWindowHeight = 0
$script:MOC_TerminalSizeChanged = $false
$script:MOC_ResizeDebounceMilliseconds = 175
$script:MOC_PendingWindowWidth = 0
$script:MOC_PendingWindowHeight = 0
$script:MOC_PendingResizeSince = $null
$script:MOC_CompactLayout = $false
$script:MOC_PageSize = 10
$script:MOC_MenuMinRows = 6
$script:MOC_RunOutputBufferSize = 2000
$script:MOC_RunViewportHeight = 16
$script:MOC_HorizontalMargin = 2
$script:MOC_View = 'Home'
$script:MOC_CurrentFolder = $null
$script:MOC_ConfigPath = $null
$script:MOC_ConfigLoadedFromFile = $false
$script:MOC_ConfigWasMissingAtLaunch = $false

# ------------------------------------------------------------
# MOC shared authentication configuration
# ------------------------------------------------------------
# Environment-specific values are intentionally blank here.
# They are loaded from .\Config\MOC.config.json or .\Config\HelpDesk-MOC.config.json.
# Use C: Configure on first run to create/update the local config file.
$script:MOC_TenantId              = ''
# TODO: Replace this with the HelpDesk-specific app registration client ID before production rollout.
$script:MOC_ClientId              = ''
$script:MOC_KeyVaultName          = ''
$script:MOC_SecretName            = ''
$script:MOC_DesiredSubscriptionId = ''


# ------------------------------------------------------------
# MOC SharePoint self-update configuration
# ------------------------------------------------------------
# Environment-specific update locations are intentionally blank here and are loaded from the local config file.
# The update package is stored in SharePoint and retrieved with the authenticated
# Microsoft Graph session after A: Auth. U: Update uses these values.
$script:MOC_UpdateEnabled         = $false
$script:MOC_UpdateSiteHostname    = ''
$script:MOC_UpdateSitePath        = ''
$script:MOC_UpdateDriveName       = ''
$script:MOC_UpdateFolderPath      = ''
$script:MOC_UpdateFileName        = ''
$script:MOC_UpdateItemPath        = ''
$script:MOC_UpdateChangelogFileName = 'CHANGELOG.md'
$script:MOC_UpdateBackupRetention = 5
$script:MOC_UpdateUnblockDownloadedFiles = $true

# Child-script update source. When U: Update is selected, MOC scans this same
# SharePoint folder recursively and updates matching local child scripts.
# Missing child scripts/folders are listed and require Y/N confirmation before install.
$script:MOC_UpdateChildScriptsEnabled       = $false
$script:MOC_UpdateChildScriptsRecursive     = $true
$script:MOC_UpdateChildScriptsCreateMissing = $false
$script:MOC_UpdateChildScriptsRootPath      = ''
$script:MOC_UpdateChildScriptIncludePattern = '*.ps1'
$script:MOC_UpdateChildScriptExcludeNames   = @(
    'HelpDesk-MOC.ps1',
    'MOC.ps1'
)

# HelpDesk-MOC script visibility/update allow-list. Leave empty in the full MOC menu.
$script:MOC_AllowedChildScriptNamePatterns = @(
    'DisableM365*.ps1',
    'Create-M365OnboardingUser*.ps1'
)
$script:MOC_UpdateChildScriptAllowedNamePatterns = @(
    'DisableM365*.ps1',
    'Create-M365OnboardingUser*.ps1'
)

# ------------------------------------------------------------
# ANSI / Theme
# ------------------------------------------------------------
$script:Esc = [char]27
# Catppuccin Mocha-inspired ANSI 24-bit color palette.
# Colors based on https://terminalcolors.com/themes/catppuccin/mocha/
$script:Ansi = @{
    Reset  = "$script:Esc[0m"
    Bold   = "$script:Esc[1m"
    Dim    = "$script:Esc[2m"
    Cyan   = "$script:Esc[36m"
    Blue   = "$script:Esc[34m"
    Green  = "$script:Esc[32m"
    Yellow = "$script:Esc[33m"
    Red    = "$script:Esc[31m"
    Gray   = "$script:Esc[90m"
    White  = "$script:Esc[97m"
    Magenta = "$script:Esc[35m"
}


# ------------------------------------------------------------
# MOC local configuration overlay / first-run configuration wizard
# ------------------------------------------------------------
function Get-MOCConfigurationProfileName {
    $MenuName = ''
    try { $MenuName = [System.IO.Path]::GetFileNameWithoutExtension($PSCommandPath) } catch { $MenuName = '' }
    if ([string]::IsNullOrWhiteSpace($MenuName)) { $MenuName = if ($script:MOC_UpdateFileName) { [System.IO.Path]::GetFileNameWithoutExtension([string]$script:MOC_UpdateFileName) } else { 'MOC' } }
    if ($MenuName -match 'HelpDesk|Helpdesk') { return 'HelpDesk-MOC' }
    return 'MOC'
}

function Get-MOCConfigurationDirectory {
    return (Join-Path $script:MOC_RootPath 'Config')
}

function Get-MOCConfigurationPath {
    return (Join-Path (Get-MOCConfigurationDirectory) ((Get-MOCConfigurationProfileName) + '.config.json'))
}

function Get-MOCConfigurationSchema {
    $Schema = @(
        [pscustomobject]@{ Key='TenantId'; Label='Tenant ID'; Variable='MOC_TenantId'; Type='String'; Required=$true; Help='Microsoft Entra tenant ID used by this menu.' },
        [pscustomobject]@{ Key='ClientId'; Label='Application client ID'; Variable='MOC_ClientId'; Type='String'; Required=$true; Help='App registration client/application ID used for delegated Graph sign-in.' },
        [pscustomobject]@{ Key='KeyVaultName'; Label='Key Vault name'; Variable='MOC_KeyVaultName'; Type='String'; Required=$true; Help='Azure Key Vault containing the Graph client secret used by app-only flows.' },
        [pscustomobject]@{ Key='SecretName'; Label='Key Vault secret name'; Variable='MOC_SecretName'; Type='String'; Required=$true; Help='Secret name in Key Vault. The secret value itself is never stored in this file.' },
        [pscustomobject]@{ Key='DesiredSubscriptionId'; Label='Azure subscription ID'; Variable='MOC_DesiredSubscriptionId'; Type='String'; Required=$false; Help='Subscription used when selecting the Azure context for Key Vault.' },
        [pscustomobject]@{ Key='UpdateEnabled'; Label='SharePoint self-update enabled'; Variable='MOC_UpdateEnabled'; Type='Bool'; Required=$false; Help='Controls whether U: Update can check SharePoint for menu updates.' },
        [pscustomobject]@{ Key='UpdateSiteHostname'; Label='SharePoint hostname'; Variable='MOC_UpdateSiteHostname'; Type='String'; Required=$false; Help='Example: contoso.sharepoint.com.' },
        [pscustomobject]@{ Key='UpdateSitePath'; Label='SharePoint site path'; Variable='MOC_UpdateSitePath'; Type='String'; Required=$false; Help='Example: /sites/itdepartment.' },
        [pscustomobject]@{ Key='UpdateDriveName'; Label='SharePoint library/drive'; Variable='MOC_UpdateDriveName'; Type='String'; Required=$false; Help='Document library or drive display name.' },
        [pscustomobject]@{ Key='UpdateFolderPath'; Label='SharePoint update folder'; Variable='MOC_UpdateFolderPath'; Type='String'; Required=$false; Help='Folder containing the menu script and child scripts.' },
        [pscustomobject]@{ Key='UpdateFileName'; Label='Menu update filename'; Variable='MOC_UpdateFileName'; Type='String'; Required=$false; Help='Expected menu file name in SharePoint, such as MOC.ps1 or HelpDesk-MOC.ps1.' },
        [pscustomobject]@{ Key='UpdateItemPath'; Label='Menu update item path'; Variable='MOC_UpdateItemPath'; Type='String'; Required=$false; Help='Full path to the menu script in the SharePoint library.' },
        [pscustomobject]@{ Key='UpdateChildScriptsEnabled'; Label='Child-script updates enabled'; Variable='MOC_UpdateChildScriptsEnabled'; Type='Bool'; Required=$false; Help='Controls whether U: Update also checks child scripts.' },
        [pscustomobject]@{ Key='UpdateChildScriptsRootPath'; Label='Child-script update root'; Variable='MOC_UpdateChildScriptsRootPath'; Type='String'; Required=$false; Help='SharePoint root folder used for child-script update scans.' },
        [pscustomobject]@{ Key='UpdateChildScriptIncludePattern'; Label='Child-script include pattern'; Variable='MOC_UpdateChildScriptIncludePattern'; Type='String'; Required=$false; Help='Usually *.ps1.' },
        [pscustomobject]@{ Key='UpdateChildScriptsCreateMissing'; Label='Auto-create missing child scripts'; Variable='MOC_UpdateChildScriptsCreateMissing'; Type='Bool'; Required=$false; Help='False is safer. Missing scripts will be prompted before install.' },
        [pscustomobject]@{ Key='UpdateUnblockDownloadedFiles'; Label='Unblock downloaded scripts'; Variable='MOC_UpdateUnblockDownloadedFiles'; Type='Bool'; Required=$false; Help='Windows only: removes Mark-of-the-Web from validated downloaded scripts.' },
        [pscustomobject]@{ Key='AllowedChildScriptNamePatterns'; Label='Visible child-script patterns'; Variable='MOC_AllowedChildScriptNamePatterns'; Type='StringArray'; Required=$false; Help='Comma-separated allow list. Empty means all discovered scripts are visible.' },
        [pscustomobject]@{ Key='UpdateChildScriptAllowedNamePatterns'; Label='Update-managed child-script patterns'; Variable='MOC_UpdateChildScriptAllowedNamePatterns'; Type='StringArray'; Required=$false; Help='Comma-separated allow list. Empty means all included child scripts are update-managed.' }
    )
    return $Schema
}

function Get-MOCConfigVariableValue {
    param([Parameter(Mandatory=$true)][string]$VariableName)
    try { return (Get-Variable -Name $VariableName -Scope Script -ErrorAction Stop).Value } catch { return $null }
}

function Set-MOCConfigVariableValue {
    param(
        [Parameter(Mandatory=$true)][string]$VariableName,
        [AllowNull()]$Value
    )
    Set-Variable -Name $VariableName -Scope Script -Value $Value -Force
}

function ConvertTo-MOCConfigDisplayValue {
    param(
        [AllowNull()]$Value,
        [Parameter(Mandatory=$true)][string]$Type
    )
    if ($null -eq $Value) { return '' }
    if ($Type -eq 'Bool') {
        if ([bool]$Value) { return 'true' }
        return 'false'
    }
    if ($Type -eq 'StringArray') { return (@($Value) | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join ', ' }
    return [string]$Value
}

function ConvertFrom-MOCConfigInputValue {
    param(
        [AllowNull()][string]$InputText,
        [AllowNull()]$CurrentValue,
        [Parameter(Mandatory=$true)][string]$Type
    )
    if ($Type -eq 'Bool') {
        $Text = if ($null -eq $InputText) { '' } else { [string]$InputText }
        if ([string]::IsNullOrWhiteSpace($Text)) { return [bool]$CurrentValue }
        if ($Text -match '^(?i:true|t|yes|y|1|on)$') { return $true }
        if ($Text -match '^(?i:false|f|no|n|0|off)$') { return $false }
        throw "Invalid boolean value '$Text'. Use true/false, yes/no, or 1/0."
    }
    if ($Type -eq 'StringArray') {
        $Text = if ($null -eq $InputText) { '' } else { [string]$InputText }
        if ([string]::IsNullOrWhiteSpace($Text)) { return @() }
        return @($Text -split ',' | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }
    return [string]$InputText
}

function Get-MOCLocalConfigurationObject {
    $Object = [ordered]@{
        Profile = Get-MOCConfigurationProfileName
        LastUpdated = (Get-Date).ToString('o')
        Warning = 'This file stores non-secret MOC configuration only. Do not store client secrets here. Store secret values in Azure Key Vault and reference the vault/secret names.'
    }

    foreach ($Item in Get-MOCConfigurationSchema) {
        $Object[$Item.Key] = Get-MOCConfigVariableValue -VariableName $Item.Variable
    }

    return [pscustomobject]$Object
}

function Save-MOCLocalConfiguration {
    $ConfigDir = Get-MOCConfigurationDirectory
    $ConfigPath = Get-MOCConfigurationPath
    if (-not (Test-Path -LiteralPath $ConfigDir)) {
        New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null
    }
    if (Test-Path -LiteralPath $ConfigPath) {
        $BackupPath = ('{0}.bak-{1}' -f $ConfigPath, (Get-Date -Format 'yyyyMMdd-HHmmss'))
        Copy-Item -LiteralPath $ConfigPath -Destination $BackupPath -Force
    }
    $Json = Get-MOCLocalConfigurationObject | ConvertTo-Json -Depth 6
    Set-Content -LiteralPath $ConfigPath -Value $Json -Encoding UTF8 -Force
    $script:MOC_ConfigPath = $ConfigPath
    $script:MOC_ConfigLoadedFromFile = $true
    $script:MOC_ConfigWasMissingAtLaunch = $false
    return $ConfigPath
}

function Import-MOCLocalConfiguration {
    $ConfigPath = Get-MOCConfigurationPath
    $script:MOC_ConfigPath = $ConfigPath
    $script:MOC_ConfigLoadedFromFile = $false
    $script:MOC_ConfigWasMissingAtLaunch = -not (Test-Path -LiteralPath $ConfigPath)

    if (-not (Test-Path -LiteralPath $ConfigPath)) { return $false }

    try {
        $Raw = Get-Content -LiteralPath $ConfigPath -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($Raw)) { return $false }
        $Config = $Raw | ConvertFrom-Json -ErrorAction Stop
        foreach ($Item in Get-MOCConfigurationSchema) {
            if ($Config.PSObject.Properties.Name -contains $Item.Key) {
                $Value = $Config.$($Item.Key)
                if ($Item.Type -eq 'StringArray') {
                    $Value = @($Value | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
                }
                elseif ($Item.Type -eq 'Bool') {
                    $Value = [bool]$Value
                }
                elseif ($null -ne $Value) {
                    $Value = [string]$Value
                }
                Set-MOCConfigVariableValue -VariableName $Item.Variable -Value $Value
            }
        }
        $script:MOC_ConfigLoadedFromFile = $true
        return $true
    }
    catch {
        $script:MOC_LastStatus = 'Configuration load failed'
        return $false
    }
}

function Test-MOCLocalConfiguration {
    $Missing = [System.Collections.Generic.List[string]]::new()
    foreach ($Item in Get-MOCConfigurationSchema | Where-Object { $_.Required }) {
        $Value = Get-MOCConfigVariableValue -VariableName $Item.Variable
        $Display = ConvertTo-MOCConfigDisplayValue -Value $Value -Type $Item.Type
        if ([string]::IsNullOrWhiteSpace($Display) -or $Display -match '^(?i:todo|replace|changeme|placeholder)$') {
            [void]$Missing.Add($Item.Label)
        }
    }
    return [pscustomobject]@{
        IsComplete = ($Missing.Count -eq 0)
        Missing = @($Missing)
        Path = Get-MOCConfigurationPath
        LoadedFromFile = [bool]$script:MOC_ConfigLoadedFromFile
    }
}

function Write-MOCConfigurationScreen {
    param(
        [Parameter(Mandatory=$false)][string]$Message = '',
        [Parameter(Mandatory=$false)][string]$MessageColor = ''
    )

    Write-Header
    Write-Breadcrumb
    $Width = Get-TerminalWidth
    $ConfigPath = Get-MOCConfigurationPath
    $Validation = Test-MOCLocalConfiguration
    $Schema = @(Get-MOCConfigurationSchema)

    Write-MOCBorderLine -Kind Top -Width $Width -Color $script:MOC_BorderSecondary
    Write-PanelLine -Text ('MOC Configuration - {0}' -f (Get-MOCConfigurationProfileName)) -Width $Width -Color "$($script:Ansi.Bold)$($script:Ansi.Cyan)"
    Write-MOCBorderLine -Kind Middle -Width $Width -Color $script:MOC_BorderSecondary
    Write-PanelLine -Text 'WARNING: Configuration changes can affect authentication, updates, and available child scripts.' -Width $Width -Color "$($script:Ansi.Bold)$($script:Ansi.Yellow)"
    Write-PanelLine -Text 'Do not change these values unless you understand the impact or were instructed by an administrator.' -Width $Width -Color "$($script:Ansi.Bold)$($script:Ansi.Red)"
    Write-PanelLine -Text 'Client secrets are not stored here. Store secret values in Azure Key Vault only.' -Width $Width -Color $script:Ansi.Yellow
    Write-PanelLine -Text '' -Width $Width -Color $script:Ansi.White
    Write-PanelWrappedLabelValue -Label 'Config file: ' -Value $ConfigPath -Width $Width -Color $script:Ansi.Gray -MaxLines 2
    Write-PanelLine -Text ('Loaded from file: {0}' -f ([bool]$script:MOC_ConfigLoadedFromFile)) -Width $Width -Color $(if ($script:MOC_ConfigLoadedFromFile) { $script:Ansi.Green } else { $script:Ansi.Yellow })
    if (-not $Validation.IsComplete) {
        Write-PanelLine -Text ('Missing required values: {0}' -f ($Validation.Missing -join ', ')) -Width $Width -Color $script:Ansi.Red
    }
    else {
        Write-PanelLine -Text 'Required values: Complete' -Width $Width -Color $script:Ansi.Green
    }
    if (-not [string]::IsNullOrWhiteSpace($Message)) {
        if ([string]::IsNullOrWhiteSpace($MessageColor)) { $MessageColor = $script:Ansi.Cyan }
        Write-PanelLine -Text $Message -Width $Width -Color $MessageColor
    }
    Write-MOCBorderLine -Kind Middle -Width $Width -Color $script:MOC_BorderSecondary

    $Index = 1
    foreach ($Item in $Schema) {
        $Value = Get-MOCConfigVariableValue -VariableName $Item.Variable
        $Display = ConvertTo-MOCConfigDisplayValue -Value $Value -Type $Item.Type
        if ([string]::IsNullOrWhiteSpace($Display)) { $Display = '<blank>' }
        $RequiredMark = if ($Item.Required) { '*' } else { ' ' }
        $Line = ('{0,2}: {1} {2,-39} = {3}' -f $Index, $RequiredMark, $Item.Label, $Display)
        $Color = if ($Item.Required -and $Display -eq '<blank>') { $script:Ansi.Red } elseif ($Item.Type -eq 'Bool') { $script:Ansi.Cyan } else { $script:Ansi.White }
        Write-PanelLine -Text $Line -Width $Width -Color $Color
        $Index++
    }

    Write-MOCBorderLine -Kind Middle -Width $Width -Color $script:MOC_BorderSecondary
    Write-PanelLine -Text 'Type a number to edit. S: Save  L: Reload  T: Test  Esc/Backspace: Return' -Width $Width -Color $script:Ansi.Yellow
    Write-MOCBorderLine -Kind Bottom -Width $Width -Color $script:MOC_BorderSecondary
    Write-Footer
}

function Read-MOCConfigurationEditorInput {
    param(
        [Parameter(Mandatory=$true)][object]$Item,
        [Parameter(Mandatory=$false)][AllowNull()][object]$OutputBuffer = $null
    )

    if ($OutputBuffer -is [System.Collections.Generic.List[string]]) {
        $EditorOutputBuffer = $OutputBuffer
    }
    else {
        $EditorOutputBuffer = [System.Collections.Generic.List[string]]::new()
        if ($null -ne $OutputBuffer) {
            if ($OutputBuffer -is [array]) {
                foreach ($Line in $OutputBuffer) {
                    [void]$EditorOutputBuffer.Add([string]$Line)
                }
            }
            elseif (-not [string]::IsNullOrWhiteSpace([string]$OutputBuffer)) {
                [void]$EditorOutputBuffer.Add([string]$OutputBuffer)
            }
        }
    }
    $OutputBuffer = $EditorOutputBuffer

    $CurrentValue = Get-MOCConfigVariableValue -VariableName $Item.Variable
    $CurrentDisplay = ConvertTo-MOCConfigDisplayValue -Value $CurrentValue -Type $Item.Type
    $Prompt = ('{0} [{1}]' -f $Item.Label, $CurrentDisplay)
    $Help = if ($Item.Type -eq 'Bool') { 'Enter true/false, yes/no, 1/0. Empty keeps the current value. Esc cancels.' } elseif ($Item.Type -eq 'StringArray') { 'Enter comma-separated values. Empty clears the list. Esc cancels.' } else { 'Enter the new value. Empty is allowed. Esc cancels.' }

    [void]$OutputBuffer.Add(('Editing: {0}' -f $Item.Label))
    [void]$OutputBuffer.Add(('Help: {0}' -f $Item.Help))
    $Response = Read-MOCTerminalInlineInput -ScriptName 'MOC Configuration' -Prompt $Prompt -InitialValue $CurrentDisplay -OutputBuffer $OutputBuffer -Help $Help
    if ($Response.Cancelled) { return [pscustomobject]@{ Changed=$false; Message='Edit cancelled.'; Color=$script:Ansi.Yellow } }

    try {
        $NewValue = ConvertFrom-MOCConfigInputValue -InputText $Response.Value -CurrentValue $CurrentValue -Type $Item.Type
        Set-MOCConfigVariableValue -VariableName $Item.Variable -Value $NewValue
        return [pscustomobject]@{ Changed=$true; Message=('Updated {0}. Press S to save changes to disk.' -f $Item.Label); Color=$script:Ansi.Green }
    }
    catch {
        return [pscustomobject]@{ Changed=$false; Message=$_.Exception.Message; Color=$script:Ansi.Red }
    }
}

function Invoke-MOCConfigurationMenu {
    $PreviousView = $script:MOC_View
    $PreviousFolder = $script:MOC_CurrentFolder
    $script:MOC_View = 'Configuration'
    $script:MOC_CurrentFolder = $null
    $Message = ''
    $MessageColor = ''

    try {
        while ($true) {
            Write-MOCConfigurationScreen -Message $Message -MessageColor $MessageColor
            $Key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
            Hide-MOCCursor
            if ($Key.VirtualKeyCode -in @(8,27)) { break }

            if ($Key.Character -match '[Ss]') {
                try {
                    $SavedPath = Save-MOCLocalConfiguration
                    $Message = ('Saved configuration: {0}' -f $SavedPath)
                    $MessageColor = $script:Ansi.Green
                }
                catch {
                    $Message = ('Failed to save configuration: {0}' -f $_.Exception.Message)
                    $MessageColor = $script:Ansi.Red
                }
                continue
            }

            if ($Key.Character -match '[Ll]') {
                if (Import-MOCLocalConfiguration) {
                    $Message = 'Reloaded configuration from disk.'
                    $MessageColor = $script:Ansi.Green
                }
                else {
                    $Message = 'No configuration file was loaded. Current in-memory values are still shown.'
                    $MessageColor = $script:Ansi.Yellow
                }
                continue
            }

            if ($Key.Character -match '[Tt]') {
                $Validation = Test-MOCLocalConfiguration
                if ($Validation.IsComplete) {
                    $Message = 'Configuration test passed: required values are populated.'
                    $MessageColor = $script:Ansi.Green
                }
                else {
                    $Message = ('Configuration test failed. Missing: {0}' -f ($Validation.Missing -join ', '))
                    $MessageColor = $script:Ansi.Red
                }
                continue
            }

            if (($Key.VirtualKeyCode -ge 49 -and $Key.VirtualKeyCode -le 57) -or ($Key.VirtualKeyCode -ge 97 -and $Key.VirtualKeyCode -le 105)) {
                $Digit = if ($Key.VirtualKeyCode -ge 97) { $Key.VirtualKeyCode - 96 } else { $Key.VirtualKeyCode - 48 }
                $NumberText = [string]$Digit
                Write-MOCConfigurationScreen -Message ('Selected {0}. Press Enter to edit, or type another digit for multi-digit items.' -f $NumberText) -MessageColor $script:Ansi.Cyan
                $NextKey = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
                Hide-MOCCursor
                if (($NextKey.VirtualKeyCode -ge 48 -and $NextKey.VirtualKeyCode -le 57) -or ($NextKey.VirtualKeyCode -ge 96 -and $NextKey.VirtualKeyCode -le 105)) {
                    $NextDigit = if ($NextKey.VirtualKeyCode -ge 96) { $NextKey.VirtualKeyCode - 96 } else { $NextKey.VirtualKeyCode - 48 }
                    $NumberText += [string]$NextDigit
                }
                elseif ($NextKey.VirtualKeyCode -notin @(13)) {
                    $Message = 'Edit cancelled.'
                    $MessageColor = $script:Ansi.Yellow
                    continue
                }

                $Index = 0
                if ([int]::TryParse($NumberText, [ref]$Index)) {
                    $Schema = @(Get-MOCConfigurationSchema)
                    if ($Index -ge 1 -and $Index -le $Schema.Count) {
                        $Buffer = [System.Collections.Generic.List[string]]::new()
                        [void]$Buffer.Add('MOC Configuration Editor')
                        [void]$Buffer.Add('WARNING: Be careful. Changing the wrong value can break authentication or update behavior.')
                        [void]$Buffer.Add('Do not enter client secrets here. Store client secret values in Azure Key Vault only.')
                        [void]$Buffer.Add('')
                        $Result = Read-MOCConfigurationEditorInput -Item $Schema[$Index - 1] -OutputBuffer $Buffer
                        $Message = $Result.Message
                        $MessageColor = $Result.Color
                    }
                    else {
                        $Message = 'Invalid configuration item number.'
                        $MessageColor = $script:Ansi.Yellow
                    }
                }
                continue
            }
        }
    }
    finally {
        $script:MOC_View = $PreviousView
        $script:MOC_CurrentFolder = $PreviousFolder
        Hide-MOCCursor
    }
}

function Invoke-MOCFirstRunConfigurationIfNeeded {
    if (-not $script:MOC_ConfigWasMissingAtLaunch) { return }

    $PreviousView = $script:MOC_View
    $PreviousFolder = $script:MOC_CurrentFolder
    $script:MOC_View = 'Configuration'
    $script:MOC_CurrentFolder = $null

    try {
        while ($true) {
            Write-Header
            Write-Breadcrumb
            $Width = Get-TerminalWidth
            Write-MOCBorderLine -Kind Top -Width $Width -Color $script:MOC_BorderSecondary
            Write-PanelLine -Text ('First-run configuration - {0}' -f (Get-MOCConfigurationProfileName)) -Width $Width -Color "$($script:Ansi.Bold)$($script:Ansi.Cyan)"
            Write-MOCBorderLine -Kind Middle -Width $Width -Color $script:MOC_BorderSecondary
            Write-PanelLine -Text 'WARNING: This menu has not saved a local configuration file yet.' -Width $Width -Color "$($script:Ansi.Bold)$($script:Ansi.Yellow)"
            Write-PanelLine -Text 'Be careful. Do not change anything unless you know what the setting controls.' -Width $Width -Color "$($script:Ansi.Bold)$($script:Ansi.Red)"
            Write-PanelLine -Text 'Client secrets should remain in Azure Key Vault. This menu stores only vault and secret names.' -Width $Width -Color $script:Ansi.Yellow
            Write-PanelLine -Text '' -Width $Width -Color $script:Ansi.White
            Write-PanelWrappedLabelValue -Label 'Config file: ' -Value (Get-MOCConfigurationPath) -Width $Width -Color $script:Ansi.Gray -MaxLines 2
            $Validation = Test-MOCLocalConfiguration
            if ($Validation.IsComplete) {
                Write-PanelLine -Text 'Current built-in/default values contain the required fields.' -Width $Width -Color $script:Ansi.Green
            }
            else {
                Write-PanelLine -Text ('Missing required values: {0}' -f ($Validation.Missing -join ', ')) -Width $Width -Color $script:Ansi.Red
            }
            Write-PanelLine -Text '' -Width $Width -Color $script:Ansi.White
            Write-PanelLine -Text 'C: Configure now' -Width $Width -Color $script:Ansi.Cyan
            Write-PanelLine -Text 'S: Save current values as the local config file' -Width $Width -Color $script:Ansi.Cyan
            Write-PanelLine -Text 'K: Skip for this session' -Width $Width -Color $script:Ansi.Yellow
            Write-PanelLine -Text 'Q: Quit' -Width $Width -Color $script:Ansi.Red
            Write-MOCBorderLine -Kind Bottom -Width $Width -Color $script:MOC_BorderSecondary
            Write-Footer

            $Key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
            Hide-MOCCursor
            if ($Key.Character -match '[Cc]') {
                Invoke-MOCConfigurationMenu
                if (-not $script:MOC_ConfigWasMissingAtLaunch) { break }
                continue
            }
            if ($Key.Character -match '[Ss]') {
                try { [void](Save-MOCLocalConfiguration) } catch { $script:MOC_LastStatus = 'Config save failed' }
                break
            }
            if ($Key.Character -match '[Kk]') { break }
            if ($Key.Character -match '[Qq]') {
                $script:MOC_ExitRequested = $true
                $script:MOC_ExitCompleted = $true
                $script:MOC_LastStatus = 'Launch cancelled from first-run configuration'
                return
            }
        }
    }
    finally {
        $script:MOC_View = $PreviousView
        $script:MOC_CurrentFolder = $PreviousFolder
        Hide-MOCCursor
    }
}


# Pane border colors are intentionally separate from message text colors.
# This keeps the MOC frame visually stable while allowing each pane type to
# use its own consistent border color.
$script:MOC_BorderDefault   = $script:Ansi.Green
$script:MOC_BorderPrimary   = $script:Ansi.Blue
$script:MOC_BorderSecondary = $script:Ansi.Cyan
$script:MOC_BorderInput     = $script:Ansi.Cyan

function Hide-MOCCursor {
    [CmdletBinding()]
    param()

    try {
        [Console]::CursorVisible = $false
        [Console]::Out.Write("$($script:Esc)[?25l")
        [Console]::Out.Flush()
    }
    catch { }
}

function Show-MOCCursor {
    [CmdletBinding()]
    param()

    try {
        [Console]::CursorVisible = $true
        [Console]::Out.Write("$($script:Esc)[?25h")
        [Console]::Out.Flush()
    }
    catch { }
}

function Reset-MOCTerminalSessionState {
    [CmdletBinding()]
    param(
        [switch]$BeforeLaunch
    )

    try {
        # If a previous MOC run was interrupted with Ctrl+C, Windows Terminal can
        # remain in the alternate screen buffer while this new script instance has
        # no memory of it. Force-return to the normal screen, reset ANSI styles,
        # and clear stale frame content before entering a fresh MOC frame.
        [Console]::Out.Write("$($script:Esc)[0m$($script:Esc)[?25h$($script:Esc)[?1049l$($script:Esc)[2J$($script:Esc)[H")
        [Console]::Out.Flush()
    }
    catch { }

    $script:MOC_AlternateScreenActive = $false
    $script:MOC_CurrentFrameLineCount = 0
    $script:MOC_LastFrameLineCount = 0
    $script:MOC_CurrentFrameBuffer = [System.Collections.Generic.List[string]]::new()
    $script:MOC_LastFrameBuffer = @()

    if ($BeforeLaunch) {
        Hide-MOCCursor
    }
}


function Enter-MOCAlternateScreenBuffer {
    [CmdletBinding()]
    param()

    if ($script:MOC_AlternateScreenActive) {
        return
    }

    try {
        # Alternate screen buffer keeps the interactive MOC UI out of the
        # terminal scrollback. This is the same general model used by full-screen
        # terminal applications. The normal scrollback is restored on exit.
        [Console]::Out.Write("$($script:Esc)[?1049h$($script:Esc)[?25l$($script:Esc)[2J$($script:Esc)[H")
        [Console]::Out.Flush()
        $script:MOC_AlternateScreenActive = $true
        $script:MOC_CurrentFrameLineCount = 0
        $script:MOC_LastFrameLineCount = 0
        $script:MOC_CurrentFrameBuffer = [System.Collections.Generic.List[string]]::new()
        $script:MOC_LastFrameBuffer = @()
    }
    catch {
        $script:MOC_AlternateScreenActive = $false
    }
}

function Exit-MOCAlternateScreenBuffer {
    [CmdletBinding()]
    param()

    Show-MOCCursor

    if (-not $script:MOC_AlternateScreenActive) {
        return
    }

    try {
        [Console]::Out.Write("$($script:Esc)[?25h$($script:Esc)[?1049l")
        [Console]::Out.Flush()
    }
    catch { }

    $script:MOC_AlternateScreenActive = $false
    $script:MOC_CurrentFrameLineCount = 0
    $script:MOC_LastFrameLineCount = 0
    $script:MOC_CurrentFrameBuffer = [System.Collections.Generic.List[string]]::new()
    $script:MOC_LastFrameBuffer = @()
}

function Get-MOCPlainHeaderLines {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [string]$ScriptName = ''
    )

    $Width = Get-TerminalWidth
    $AuthState = if ($script:MOC_Authenticated) { 'Connected' } else { 'Not Connected' }
    $OrganizationDisplay = if ([string]::IsNullOrWhiteSpace($script:MOC_OrganizationName)) { 'Organization:' } else { "Organization: $($script:MOC_OrganizationName)" }

    function Center-PlainText {
        param([string]$Text, [int]$LineWidth)
        if ($null -eq $Text) { $Text = '' }
        $Left = [Math]::Max(0, [Math]::Floor(($LineWidth - $Text.Length) / 2))
        return ((' ' * $Left) + $Text)
    }

    $Lines = New-Object System.Collections.Generic.List[string]
    [void]$Lines.Add((New-Line -Width $Width -Char '─'))
    [void]$Lines.Add((Center-PlainText -Text '██╗  ██╗███████╗██╗     ██████╗ ██████╗ ███████╗███████╗██╗  ██╗      ███╗   ███╗ ██████╗  ██████╗' -LineWidth $Width))
    [void]$Lines.Add((Center-PlainText -Text '██║  ██║██╔════╝██║     ██╔══██╗██╔══██╗██╔════╝██╔════╝██║ ██╔╝      ████╗ ████║██╔═══██╗██╔════╝' -LineWidth $Width))
    [void]$Lines.Add((Center-PlainText -Text '███████║█████╗  ██║     ██████╔╝██║  ██║█████╗  ███████╗█████╔╝       ██╔████╔██║██║   ██║██║     ' -LineWidth $Width))
    [void]$Lines.Add((Center-PlainText -Text '██╔══██║██╔══╝  ██║     ██╔═══╝ ██║  ██║██╔══╝  ╚════██║██╔═██╗       ██║╚██╔╝██║██║   ██║██║     ' -LineWidth $Width))
    [void]$Lines.Add((Center-PlainText -Text '██║  ██║███████╗███████╗██║     ██████╔╝███████╗███████║██║  ██╗      ██║ ╚═╝ ██║╚██████╔╝╚██████╗' -LineWidth $Width))
    [void]$Lines.Add((Center-PlainText -Text '╚═╝  ╚═╝╚══════╝╚══════╝╚═╝     ╚═════╝ ╚══════╝╚══════╝╚═╝  ╚═╝      ╚═╝     ╚═╝ ╚═════╝  ╚═════╝' -LineWidth $Width))
    [void]$Lines.Add((Center-PlainText -Text 'Helpdesk - M365 Operations Console' -LineWidth $Width))
    [void]$Lines.Add('')
    [void]$Lines.Add((Center-PlainText -Text ("{0}     Menu: v{1}" -f $OrganizationDisplay, $script:MOC_Version) -LineWidth $Width))
    [void]$Lines.Add((Center-PlainText -Text ("Tenant: {0}     Auth: {1}     User: {2}" -f (Get-MaskedTenant), $AuthState, $CurrentUser) -LineWidth $Width))
    if (-not [string]::IsNullOrWhiteSpace($ScriptName)) {
        [void]$Lines.Add((Center-PlainText -Text ("Script: {0}" -f $ScriptName) -LineWidth $Width))
    }
    [void]$Lines.Add((New-Line -Width $Width -Char '─'))
    [void]$Lines.Add(('Breadcrumb: {0}' -f (Get-Breadcrumb)))
    [void]$Lines.Add('')
    return @($Lines)
}

function Complete-MOCFrameRender {
    [CmdletBinding()]
    param()

    if (-not $script:MOC_SoftRedrawEnabled) { return }

    try {
        $Width = [Math]::Max(1, [int](Get-MOCTerminalSize).Width)
        $ClearToEndOfLine = "$($script:Esc)[0K"
        $CurrentFrame = @($script:MOC_CurrentFrameBuffer)
        $LastFrame = @($script:MOC_LastFrameBuffer)
        $Current = [int]$CurrentFrame.Count
        $Last = [int]$LastFrame.Count
        $Max = [Math]::Max($Current, $Last)

        for ($Line = 0; $Line -lt $Max; $Line++) {
            $NewLine = if ($Line -lt $Current) { [string]$CurrentFrame[$Line] } else { '' }
            $OldLine = if ($Line -lt $Last) { [string]$LastFrame[$Line] } else { $null }

            if ($NewLine -ne $OldLine) {
                try {
                    [Console]::SetCursorPosition(0, $Line)
                    if ([string]::IsNullOrEmpty($NewLine)) {
                        [Console]::Out.Write((' ' * [Math]::Max(1, $Width - 1)) + $ClearToEndOfLine)
                    }
                    else {
                        # Clear-to-end avoids remnants from longer prior content. The render width
                        # already leaves one terminal column unused, preventing auto-wrap and lost borders.
                        [Console]::Out.Write($NewLine + $ClearToEndOfLine)
                    }
                }
                catch { }
            }
        }

        $script:MOC_LastFrameBuffer = @($CurrentFrame)
        $script:MOC_LastFrameLineCount = $Current
        $script:MOC_FrameBufferActive = $false
        try { [Console]::SetCursorPosition(0, [Math]::Max(0, $Current)) } catch { }
        Hide-MOCCursor
        [Console]::Out.Flush()
    }
    catch {
        $script:MOC_FrameBufferActive = $false
    }
}

function Add-MOCTranscriptText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [string]$Path,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$Text,

        [switch]$NoNewLine
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { return }

    $Value = if ($null -eq $Text) { '' } else { [string]$Text }
    if (-not $NoNewLine) { $Value += [Environment]::NewLine }

    for ($Attempt = 1; $Attempt -le 5; $Attempt++) {
        try {
            $Folder = Split-Path -Parent $Path
            if (-not [string]::IsNullOrWhiteSpace($Folder) -and -not (Test-Path $Folder)) {
                New-Item -ItemType Directory -Path $Folder -Force | Out-Null
            }

            [System.IO.File]::AppendAllText($Path, $Value, [System.Text.Encoding]::UTF8)
            return
        }
        catch {
            if ($Attempt -lt 5) {
                Start-Sleep -Milliseconds (100 * $Attempt)
            }
        }
    }
}

function Initialize-MOCManualTranscript {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $false)]
        [string]$ScriptName = ''
    )

    try {
        $Folder = Split-Path -Parent $Path
        if (-not [string]::IsNullOrWhiteSpace($Folder) -and -not (Test-Path $Folder)) {
            New-Item -ItemType Directory -Path $Folder -Force | Out-Null
        }

        $TranscriptUser = [Environment]::UserName
        try {
            if ($IsWindows) {
                $TranscriptUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
            }
            elseif (-not [string]::IsNullOrWhiteSpace($env:USER)) {
                $TranscriptUser = $env:USER
            }
        }
        catch {
            if ([string]::IsNullOrWhiteSpace($TranscriptUser)) { $TranscriptUser = 'Unknown' }
        }

        $TranscriptMachine = if (-not [string]::IsNullOrWhiteSpace($env:COMPUTERNAME)) { $env:COMPUTERNAME } elseif (-not [string]::IsNullOrWhiteSpace($env:HOSTNAME)) { $env:HOSTNAME } else { [System.Environment]::MachineName }

        $Header = @(
            '**********************',
            'MOC transcript start',
            ('Start time: {0}' -f (Get-Date -Format 'yyyyMMddHHmmss')),
            ('User: {0}' -f $TranscriptUser),
            ('Machine: {0}' -f $TranscriptMachine),
            ('Host: {0}' -f $Host.Name),
            ('PowerShell: {0}' -f $PSVersionTable.PSVersion),
            ('Script: {0}' -f $ScriptName),
            '**********************',
            ''
        ) -join [Environment]::NewLine

        [System.IO.File]::WriteAllText($Path, ($Header + [Environment]::NewLine), [System.Text.Encoding]::UTF8)

        try {
            Add-MOCTranscriptText -Path $Path -Text 'MOC terminal banner snapshot'
            Add-MOCTranscriptText -Path $Path -Text '-----------------------------'
            foreach ($Line in (Get-MOCPlainHeaderLines -ScriptName $ScriptName)) {
                Add-MOCTranscriptText -Path $Path -Text $Line
            }
        }
        catch {
            # Transcript banner context must never block child-script execution.
        }

        return $true
    }
    catch {
        return $false
    }
}

function Complete-MOCManualTranscript {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { return }

    Add-MOCTranscriptText -Path $Path -Text ''
    Add-MOCTranscriptText -Path $Path -Text '**********************'
    Add-MOCTranscriptText -Path $Path -Text 'MOC transcript end'
    Add-MOCTranscriptText -Path $Path -Text ('End time: {0}' -f (Get-Date -Format 'yyyyMMddHHmmss'))
    Add-MOCTranscriptText -Path $Path -Text '**********************'
}


function Save-MOCSessionIndex {
    [CmdletBinding()]
    param()

    if ([string]::IsNullOrWhiteSpace([string]$script:MOC_SessionIndexPath)) { return }

    try {
        $Folder = Split-Path -Parent $script:MOC_SessionIndexPath
        if (-not [string]::IsNullOrWhiteSpace($Folder) -and -not (Test-Path $Folder)) {
            New-Item -ItemType Directory -Path $Folder -Force | Out-Null
        }

        $Payload = [pscustomobject][ordered]@{
            sessionId = [string]$script:MOC_SessionId
            sessionStarted = if ($null -ne $script:MOC_SessionStarted) { ([datetime]$script:MOC_SessionStarted).ToString('o') } else { '' }
            sessionIndexPath = [string]$script:MOC_SessionIndexPath
            machine = [string]$env:COMPUTERNAME
            user = [string][System.Security.Principal.WindowsIdentity]::GetCurrent().Name
            host = [string]$Host.Name
            powerShell = [string]$PSVersionTable.PSVersion
            MOCVersion = [string]$script:MOC_Version
            rootPath = [string]$script:MOC_RootPath
            transcriptLogRoot = [string]$TranscriptLogDir
            reportsRoot = [string]$script:MOC_ReportsRootPath
            runs = @($script:MOC_SessionIndexEntries)
        }

        $Payload |
            ConvertTo-Json -Depth 8 |
            Set-Content -LiteralPath $script:MOC_SessionIndexPath -Encoding UTF8
    }
    catch {
        # The session index is useful audit metadata, but it must never block MOC.
    }
}

function Initialize-MOCSessionIndex {
    [CmdletBinding()]
    param()

    try {
        if (-not (Test-Path $TranscriptLogDir)) {
            New-Item -ItemType Directory -Path $TranscriptLogDir -Force | Out-Null
        }

        if ([string]::IsNullOrWhiteSpace([string]$script:MOC_SessionIndexPath)) {
            $script:MOC_SessionIndexPath = Join-Path $TranscriptLogDir ("MOC-SessionIndex-{0}.json" -f [string]$script:MOC_SessionId)
        }

        Save-MOCSessionIndex
    }
    catch {
        # Session index initialization should not prevent MOC from starting.
    }
}

function Get-MOCBufferLastMatchValue {
    [CmdletBinding()]
    param(
        [AllowNull()]$OutputBuffer,
        [Parameter(Mandatory = $true)]
        [string]$Pattern
    )

    $Value = ''

    try {
        foreach ($Line in @($OutputBuffer)) {
            $Text = [string]$Line
            if ($Text -match $Pattern) {
                $Value = [string]$Matches[1]
            }
        }
    }
    catch { }

    return $Value
}

function Add-MOCSessionIndexEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Script,

        [Parameter(Mandatory = $true)]
        [string]$Status,

        [Parameter(Mandatory = $true)]
        [datetime]$StartTime,

        [Parameter(Mandatory = $true)]
        [datetime]$EndTime,

        [Parameter(Mandatory = $true)]
        [int]$ExitCode,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [string]$TranscriptPath,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        $OutputBuffer
    )

    try {
        if ($null -eq $script:MOC_SessionIndexEntries) {
            $script:MOC_SessionIndexEntries = [System.Collections.Generic.List[object]]::new()
        }

        $OutputFolderDisplay = Get-MOCBufferLastMatchValue -OutputBuffer $OutputBuffer -Pattern '^Output folder:\s*(.+)$'
        $FullOutputFolder = Get-MOCBufferLastMatchValue -OutputBuffer $OutputBuffer -Pattern '^Full output folder:\s*(.+)$'
        $ReportRootDisplay = Get-MOCBufferLastMatchValue -OutputBuffer $OutputBuffer -Pattern '^Report root:\s*(.+)$'
        $WorkbookPath = Get-MOCBufferLastMatchValue -OutputBuffer $OutputBuffer -Pattern '^(?:Workbook created|Readable XLSX workbook saved|XLSX report|Exported \d+ row\(s\) ->)[:\s-]*>?\s*(.+\.xlsx)'
        $SummaryPath = Get-MOCBufferLastMatchValue -OutputBuffer $OutputBuffer -Pattern '^(?:Summary saved|Summary JSON|Run summary saved)\s*[-:>]*\s*(.+\.json)$'

        $Duration = New-TimeSpan -Start $StartTime -End $EndTime

        $Entry = [pscustomobject][ordered]@{
            runNumber = @($script:MOC_SessionIndexEntries).Count + 1
            scriptName = [string]$Script.Name
            scriptPath = [string]$Script.Path
            category = [string]$Script.Folder
            status = [string]$Status
            exitCode = [int]$ExitCode
            started = $StartTime.ToString('o')
            ended = $EndTime.ToString('o')
            durationSeconds = [math]::Round($Duration.TotalSeconds, 3)
            transcriptPath = [string]$TranscriptPath
            reportRoot = [string]$ReportRootDisplay
            outputFolder = [string]$OutputFolderDisplay
            fullOutputFolder = [string]$FullOutputFolder
            workbookPath = [string]$WorkbookPath
            summaryPath = [string]$SummaryPath
        }

        [void]$script:MOC_SessionIndexEntries.Add($Entry)
        Save-MOCSessionIndex
    }
    catch {
        # Session indexing must never interfere with child-script execution.
    }
}

Initialize-MOCSessionIndex

function Write-Color {
    param(
        [AllowNull()][string]$Text,
        [AllowNull()][string]$Color = $script:Ansi.Reset,
        [switch]$NoNewLine
    )

    # Render through a frame buffer when MOC is in soft-redraw mode. This lets
    # Complete-MOCFrameRender update only changed lines, which greatly reduces
    # flicker during menu selection movement, refresh, and output scrolling.
    if ($null -eq $Text) { $Text = '' }
    if ([string]::IsNullOrEmpty($Color)) { $Color = $script:Ansi.Reset }
    $Rendered = "$Color$Text$($script:Ansi.Reset)"

    if ($script:MOC_SoftRedrawEnabled -and $script:MOC_FrameBufferActive -and -not $NoNewLine) {
        try {
            $margin = Get-MOCHorizontalMargin
            if ($margin -gt 0) {
                $Rendered = ((' ' * $margin) + $Rendered)
            }
            [void]$script:MOC_CurrentFrameBuffer.Add($Rendered)
            $script:MOC_CurrentFrameLineCount = [int]$script:MOC_CurrentFrameLineCount + 1
            return
        }
        catch { }
    }

    try {
        if ($NoNewLine) {
            [Console]::Out.Write($Rendered)
        }
        else {
            $ClearToEndOfLine = "$($script:Esc)[0K"
            [Console]::Out.Write($Rendered + $ClearToEndOfLine + [Environment]::NewLine)
            if ($script:MOC_SoftRedrawEnabled) {
                $script:MOC_CurrentFrameLineCount = [int]$script:MOC_CurrentFrameLineCount + 1
            }
        }
        [Console]::Out.Flush()
    }
    catch {
        if ($NoNewLine) { [System.Console]::Write($Rendered) }
        else {
            [System.Console]::WriteLine($Rendered)
            if ($script:MOC_SoftRedrawEnabled) {
                $script:MOC_CurrentFrameLineCount = [int]$script:MOC_CurrentFrameLineCount + 1
            }
        }
    }

    # Do not mirror live redraw frames to the transcript here.
    # Run-console output is written to the transcript once in Add-RunConsoleLine.
}

function Initialize-ConsoleLayout {
    # MOC is now responsive. Do not force the user terminal to a fixed size.
    # Only keep the buffer wide/tall enough for the current window when the host allows it.
    try {
        $raw = $Host.UI.RawUI
        $window = $raw.WindowSize
        $buffer = $raw.BufferSize
        $newWidth = [Math]::Max($buffer.Width, $window.Width)
        $newHeight = [Math]::Max($buffer.Height, $window.Height)
        if ($newWidth -ne $buffer.Width -or $newHeight -ne $buffer.Height) {
            $raw.BufferSize = New-Object System.Management.Automation.Host.Size($newWidth, $newHeight)
        }
    }
    catch { }

    Update-MOCResponsiveLayout -Force
}

function Get-MOCTerminalSize {
    try {
        $raw = $Host.UI.RawUI
        return [pscustomobject]@{
            Width = [Math]::Max(1, [int]$raw.WindowSize.Width)
            Height = [Math]::Max(1, [int]$raw.WindowSize.Height)
        }
    }
    catch {
        try {
            return [pscustomobject]@{
                Width = [Math]::Max(1, [int][Console]::WindowWidth)
                Height = [Math]::Max(1, [int][Console]::WindowHeight)
            }
        }
        catch {
            return [pscustomobject]@{
                Width = [int]$script:MOC_TargetWidth
                Height = [int]$script:MOC_TargetHeight
            }
        }
    }
}

function Set-MOCResponsiveLayoutValues {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [int]$Width,

        [Parameter(Mandatory = $true)]
        [int]$Height,

        [switch]$MarkSizeChanged
    )

    $script:MOC_TerminalSizeChanged = [bool]$MarkSizeChanged
    $script:MOC_LastWindowWidth = [int]$Width
    $script:MOC_LastWindowHeight = [int]$Height

    $script:MOC_CompactLayout = (
        [int]$Width -lt [int]$script:MOC_CompactWidth -or
        [int]$Height -lt [int]$script:MOC_CompactHeight
    )

    # Recalculate dynamic row budgets from the visible terminal size.
    # The footer owns the bottom three rows. Everything above it is distributed
    # between the active menu/detail or run-console panes so taller terminals do
    # not leave large unused areas above the navigation bar.
    $headerRows = if ($script:MOC_CompactLayout) { 7 } else { 12 }
    $footerRows = 3
    $breadcrumbRows = 2
    $generalGaps = 4

    $minimumDetailsRows = if ($script:MOC_CompactLayout) { 6 } else { 8 }
    $availableContentRows = [int]$Height - $headerRows - $breadcrumbRows - $footerRows - $generalGaps
    $availableForMenu = [int]$availableContentRows - $minimumDetailsRows
    $script:MOC_PageSize = [Math]::Max(4, [Math]::Min(60, $availableForMenu))

    # Run-console chrome includes the run title, progress block, separators,
    # line/status rows, and borders. Do not cap the viewport at 30 rows; let it
    # grow with the terminal while preserving enough space for the fixed footer.
    $runChromeRows = if ($script:MOC_CompactLayout) { 11 } else { 12 }
    $availableForRunOutput = [int]$Height - $headerRows - $breadcrumbRows - $footerRows - $runChromeRows
    $script:MOC_RunViewportHeight = [Math]::Max(6, [Math]::Min(160, $availableForRunOutput))
}

function Update-MOCResponsiveLayout {
    [CmdletBinding()]
    param([switch]$Force)

    $size = Get-MOCTerminalSize
    $currentWidth = [int]$size.Width
    $currentHeight = [int]$size.Height

    if ($Force -or [int]$script:MOC_LastWindowWidth -le 0 -or [int]$script:MOC_LastWindowHeight -le 0) {
        $script:MOC_PendingWindowWidth = 0
        $script:MOC_PendingWindowHeight = 0
        $script:MOC_PendingResizeSince = $null
        Set-MOCResponsiveLayoutValues -Width $currentWidth -Height $currentHeight -MarkSizeChanged:$Force
        return
    }

    $sameAsCommitted = (
        $currentWidth -eq [int]$script:MOC_LastWindowWidth -and
        $currentHeight -eq [int]$script:MOC_LastWindowHeight
    )

    if ($sameAsCommitted) {
        $script:MOC_TerminalSizeChanged = $false
        $script:MOC_PendingWindowWidth = 0
        $script:MOC_PendingWindowHeight = 0
        $script:MOC_PendingResizeSince = $null
        return
    }

    $now = Get-Date
    $pendingChanged = (
        $currentWidth -ne [int]$script:MOC_PendingWindowWidth -or
        $currentHeight -ne [int]$script:MOC_PendingWindowHeight -or
        $null -eq $script:MOC_PendingResizeSince
    )

    if ($pendingChanged) {
        $script:MOC_PendingWindowWidth = $currentWidth
        $script:MOC_PendingWindowHeight = $currentHeight
        $script:MOC_PendingResizeSince = $now
        $script:MOC_TerminalSizeChanged = $false
        return
    }

    $elapsedMs = ($now - [datetime]$script:MOC_PendingResizeSince).TotalMilliseconds

    if ($elapsedMs -lt [double]$script:MOC_ResizeDebounceMilliseconds) {
        $script:MOC_TerminalSizeChanged = $false
        return
    }

    $script:MOC_PendingWindowWidth = 0
    $script:MOC_PendingWindowHeight = 0
    $script:MOC_PendingResizeSince = $null
    Set-MOCResponsiveLayoutValues -Width $currentWidth -Height $currentHeight -MarkSizeChanged
}

function Get-MOCHorizontalMargin {
    [CmdletBinding()]
    param()

    try {
        if ([int]$script:MOC_HorizontalMargin -lt 0) { return 0 }
        return [int]$script:MOC_HorizontalMargin
    }
    catch {
        return 0
    }
}

function Get-TerminalWidth {
    Update-MOCResponsiveLayout
    try {
        # Build frames from an inner content width and let the renderer add an
        # equal left/right margin. This preserves right-edge safety without making
        # the layout look offset to the left.
        $physicalWidth = [int](Get-MOCTerminalSize).Width
        $margin = Get-MOCHorizontalMargin
        return [Math]::Max(60, ($physicalWidth - ($margin * 2)))
    }
    catch { return [int]$script:MOC_TargetWidth }
}

function Get-TerminalHeight {
    Update-MOCResponsiveLayout
    try { return [Math]::Max(20, [int](Get-MOCTerminalSize).Height) }
    catch { return [int]$script:MOC_TargetHeight }
}

function Test-ConsoleSize {
    try {
        $size = Get-MOCTerminalSize
        return ([int]$size.Width -ge [int]$script:MOC_MinWidth -and [int]$size.Height -ge [int]$script:MOC_MinHeight)
    }
    catch { return $true }
}

function Test-MOCCompactLayout {
    Update-MOCResponsiveLayout
    return [bool]$script:MOC_CompactLayout
}


function Write-MOCBorderLine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [ValidateSet('Top','Middle','Bottom')]
        [string]$Kind = 'Middle',

        [Parameter(Mandatory = $false)]
        [int]$Width = (Get-TerminalWidth),

        [Parameter(Mandatory = $false)]
        [string]$Color = $script:MOC_BorderDefault
    )

    if ([string]::IsNullOrEmpty($Color)) { $Color = $script:MOC_BorderDefault }
    $SafeWidth = [Math]::Max(4, [int]$Width)
    $Left = '├'
    $Right = '┤'
    if ($Kind -eq 'Top') {
        $Left = '┌'
        $Right = '┐'
    }
    elseif ($Kind -eq 'Bottom') {
        $Left = '└'
        $Right = '┘'
    }

    # Start from a clean reset before applying the pane border color. This prevents
    # previous status/message colors from bleeding into the box corners or right edge
    # during soft redraws in Windows Terminal, GNOME Terminal, and other ANSI hosts.
    $LineText = $Left + (New-Line -Width ($SafeWidth - 2)) + $Right
    Write-Color -Text $LineText -Color ("$($script:Ansi.Reset)$Color")
}

function New-Line {
    param([int]$Width = (Get-TerminalWidth), [string]$Char = '─')
    return ($Char * [Math]::Max(1, $Width))
}

function Format-Duration {
    param([double]$Seconds)
    $ts = [TimeSpan]::FromSeconds([Math]::Round($Seconds))
    return ('{0:00}:{1:00}:{2:00}' -f [Math]::Floor($ts.TotalHours), $ts.Minutes, $ts.Seconds)
}

function Convert-LoggedDurationToSeconds {
    param([string]$Duration)

    if ([string]::IsNullOrWhiteSpace($Duration)) { return 0 }

    # Supports both old mm:ss logs and new hh:mm:ss logs.
    $Parts = $Duration.Split(':')
    try {
        if ($Parts.Count -eq 2) {
            return ([int]$Parts[0] * 60) + [int]$Parts[1]
        }
        elseif ($Parts.Count -eq 3) {
            return ([int]$Parts[0] * 3600) + ([int]$Parts[1] * 60) + [int]$Parts[2]
        }
    }
    catch {
        return 0
    }

    return 0
}

function Truncate-Text {
    param([string]$Text, [int]$MaxLength)
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    if ($Text.Length -le $MaxLength) { return $Text }
    if ($MaxLength -le 1) { return '…' }
    return ($Text.Substring(0, $MaxLength - 1) + '…')
}

function Wrap-Text {
    param([string]$Text, [int]$Width, [int]$MaxLines = 8)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return @('No description found. Add a comment-help .DESCRIPTION block to this script.')
    }

    $Words = $Text -split '\s+'
    $Lines = New-Object System.Collections.Generic.List[string]
    $Current = ''

    foreach ($Word in $Words) {
        if (($Current.Length + $Word.Length + 1) -le $Width) {
            if ($Current) { $Current += " $Word" } else { $Current = $Word }
        }
        else {
            if ($Current) { $Lines.Add($Current) }
            $Current = $Word
        }
        if ($Lines.Count -ge $MaxLines) { break }
    }

    if ($Current -and $Lines.Count -lt $MaxLines) { $Lines.Add($Current) }
    if ($Lines.Count -eq 0) { $Lines.Add((Truncate-Text -Text $Text -MaxLength $Width)) }
    return @($Lines)
}

function Write-PanelLine {
    param(
        [string]$Text = '',
        [int]$Width = (Get-TerminalWidth),
        [string]$Color = $script:Ansi.Reset,
        [string]$BorderColor = $script:MOC_BorderDefault
    )

    $InnerWidth = [Math]::Max(1, $Width - 4)
    $Text = Truncate-Text -Text $Text -MaxLength $InnerWidth
    $Padded = $Text.PadRight($InnerWidth)

    # Keep MOC panel borders visually stable. Only the inner message text inherits
    # status coloring; pane borders use the explicit pane border color supplied by
    # the caller, such as primary blue for title/progress panes and light-blue/cyan
    # for output/input panes.
    if ([string]::IsNullOrEmpty($Color)) { $Color = $script:Ansi.Reset }
    if ([string]::IsNullOrEmpty($BorderColor)) { $BorderColor = $script:MOC_BorderDefault }
    $Rendered = "$($script:Ansi.Reset)$BorderColor│ $Color$Padded$($script:Ansi.Reset)$BorderColor │$($script:Ansi.Reset)"

    if ($script:MOC_SoftRedrawEnabled -and $script:MOC_FrameBufferActive) {
        try {
            $margin = Get-MOCHorizontalMargin
            if ($margin -gt 0) {
                $Rendered = ((' ' * $margin) + $Rendered)
            }
            [void]$script:MOC_CurrentFrameBuffer.Add($Rendered)
            $script:MOC_CurrentFrameLineCount = [int]$script:MOC_CurrentFrameLineCount + 1
            return
        }
        catch { }
    }

    try {
        $ClearToEndOfLine = "$($script:Esc)[0K"
        [Console]::Out.Write($Rendered + $ClearToEndOfLine + [Environment]::NewLine)
        if ($script:MOC_SoftRedrawEnabled) {
            $script:MOC_CurrentFrameLineCount = [int]$script:MOC_CurrentFrameLineCount + 1
        }
        [Console]::Out.Flush()
    }
    catch {
        [System.Console]::WriteLine($Rendered)
        if ($script:MOC_SoftRedrawEnabled) {
            $script:MOC_CurrentFrameLineCount = [int]$script:MOC_CurrentFrameLineCount + 1
        }
    }
}


function Get-MOCPreferredWrapBreakIndex {
    param(
        [Parameter(Mandatory = $false)][string]$Text = '',
        [Parameter(Mandatory = $true)][int]$Width
    )

    $SafeWidth = [Math]::Max(1, $Width)
    if ([string]::IsNullOrEmpty($Text)) { return 0 }
    if ($Text.Length -le $SafeWidth) { return $Text.Length }

    $SearchLength = [Math]::Min($SafeWidth, $Text.Length)
    $SearchText = $Text.Substring(0, $SearchLength)
    $IsPathLike = ($Text -match '^[A-Za-z]:[\\/]' -or $Text -match '^\\\\' -or $Text -match '[\\/]')

    # For Windows paths, prefer breaking after a path separator so lines look like:
    # Installer: C:\Users\...
    #            Documents\Scripts\...
    # rather than splitting after just C: or in the middle of a folder name.
    if ($IsPathLike) {
        for ($i = $SearchLength - 1; $i -ge 0; $i--) {
            if (($SearchText[$i] -eq '\' -or $SearchText[$i] -eq '/') -and $i -ge 2) {
                return ($i + 1)
            }
        }
    }

    # Normal prose still prefers whitespace wrapping.
    for ($i = $SearchLength - 1; $i -ge 0; $i--) {
        if ($SearchText[$i] -match '\s') {
            return $i
        }
    }

    # If this looks path-like but the current segment is too long, try whitespace inside
    # that segment before falling back to a hard width split.
    if ($IsPathLike) {
        for ($i = $SearchLength - 1; $i -ge 0; $i--) {
            if ($SearchText[$i] -match '\s') {
                return $i
            }
        }
    }

    return $SafeWidth
}

function Split-MOCTextByWidth {
    param(
        [Parameter(Mandatory = $false)][string]$Text = '',
        [Parameter(Mandatory = $true)][int]$Width,
        [Parameter(Mandatory = $false)][int]$MaxLines = 4
    )

    $SafeWidth = [Math]::Max(1, $Width)
    $SafeMaxLines = [Math]::Max(1, $MaxLines)
    $Remaining = [string]$Text
    $Lines = New-Object System.Collections.Generic.List[string]

    while ($Remaining.Length -gt 0 -and $Lines.Count -lt $SafeMaxLines) {
        if ($Remaining.Length -le $SafeWidth) {
            $Lines.Add($Remaining)
            $Remaining = ''
            break
        }

        $BreakIndex = Get-MOCPreferredWrapBreakIndex -Text $Remaining -Width $SafeWidth
        if ($BreakIndex -lt 1) { $BreakIndex = [Math]::Min($SafeWidth, $Remaining.Length) }

        $Chunk = $Remaining.Substring(0, [Math]::Min($BreakIndex, $Remaining.Length)).TrimEnd()
        if ([string]::IsNullOrWhiteSpace($Chunk)) {
            $Chunk = $Remaining.Substring(0, [Math]::Min($SafeWidth, $Remaining.Length))
            $BreakIndex = $Chunk.Length
        }

        $Lines.Add($Chunk)
        $Remaining = $Remaining.Substring([Math]::Min($BreakIndex, $Remaining.Length)).TrimStart()
    }

    if ($Remaining.Length -gt 0 -and $Lines.Count -ge $SafeMaxLines) {
        $LastIndex = $Lines.Count - 1
        $Separator = if (($Lines[$LastIndex] -match '[\\/]$') -or ($Remaining -match '^[\\/]')) { '' } else { ' ' }
        $Lines[$LastIndex] = Truncate-Text -Text ($Lines[$LastIndex] + $Separator + $Remaining) -MaxLength $SafeWidth
    }

    if ($Lines.Count -eq 0) { $Lines.Add('') }
    return @($Lines)
}

function Write-PanelWrappedLabelValue {
    param(
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $false)][string]$Value = '',
        [Parameter(Mandatory = $false)][int]$Width = (Get-TerminalWidth),
        [Parameter(Mandatory = $false)][string]$Color = $script:Ansi.Reset,
        [Parameter(Mandatory = $false)][int]$MaxLines = 4
    )

    $InnerWidth = [Math]::Max(1, $Width - 4)
    $FirstValueWidth = [Math]::Max(1, $InnerWidth - $Label.Length)
    $ContinuationIndent = ' ' * [Math]::Min($Label.Length, [Math]::Max(0, $InnerWidth - 1))
    $ContinuationWidth = [Math]::Max(1, $InnerWidth - $ContinuationIndent.Length)

    $IsWindowsDrivePath = ($Value -match '^[A-Za-z]:[\\/]')
    $DriveRootMinimumWidth = 4
    if ($IsWindowsDrivePath -and $Value -match '^[A-Za-z]:[\\/][^\\/]+') {
        # Prefer keeping at least C:\Users together on the first value line.
        $DriveRootMinimumWidth = [Math]::Min(16, [Math]::Max(4, $Matches[0].Length))
    }

    # For Windows paths, never allow a tiny first-line value area to split the
    # drive root as "C" / ":\Users". If the space after the label cannot fit
    # at least "C:\x", put the label on its own line and wrap the complete path
    # on aligned continuation lines.
    if ($IsWindowsDrivePath -and $FirstValueWidth -lt $DriveRootMinimumWidth) {
        Write-PanelLine -Text ($Label.TrimEnd()) -Width $Width -Color $Color
        if ($MaxLines -gt 1) {
            $MoreLines = Split-MOCTextByWidth -Text $Value -Width $ContinuationWidth -MaxLines ($MaxLines - 1)
            foreach ($Line in $MoreLines) {
                Write-PanelLine -Text ($ContinuationIndent + $Line) -Width $Width -Color $Color
            }
        }
        return
    }

    $FirstChunks = Split-MOCTextByWidth -Text $Value -Width $FirstValueWidth -MaxLines 1

    # Safety net: if a path-like value still came back as only the drive letter,
    # restart with the label-only/continuation format instead of rendering
    # "Installer: C" followed by ":\Users...".
    if ($IsWindowsDrivePath -and $FirstChunks.Count -gt 0 -and $FirstChunks[0] -match '^[A-Za-z]$') {
        Write-PanelLine -Text ($Label.TrimEnd()) -Width $Width -Color $Color
        if ($MaxLines -gt 1) {
            $MoreLines = Split-MOCTextByWidth -Text $Value -Width $ContinuationWidth -MaxLines ($MaxLines - 1)
            foreach ($Line in $MoreLines) {
                Write-PanelLine -Text ($ContinuationIndent + $Line) -Width $Width -Color $Color
            }
        }
        return
    }

    Write-PanelLine -Text ($Label + $FirstChunks[0]) -Width $Width -Color $Color

    $Consumed = $FirstChunks[0].Length
    $Remaining = if ($Value.Length -gt $Consumed) { $Value.Substring($Consumed).TrimStart() } else { '' }
    if (-not [string]::IsNullOrWhiteSpace($Remaining) -and $MaxLines -gt 1) {
        $MoreLines = Split-MOCTextByWidth -Text $Remaining -Width $ContinuationWidth -MaxLines ($MaxLines - 1)
        foreach ($Line in $MoreLines) {
            Write-PanelLine -Text ($ContinuationIndent + $Line) -Width $Width -Color $Color
        }
    }
}

function Split-MOCRunConsoleOutputLine {
    # DESCRIPTION: Wraps long run-console lines without allowing paths to spill past the pane border.
    # WHY THIS MATTERS: Child/auth output often includes full transcript, session index, and report paths that are wider than the terminal.

    param(
        [Parameter(Mandatory = $false)][AllowNull()][string]$Line,
        [Parameter(Mandatory = $true)][int]$Width,
        [Parameter(Mandatory = $false)][int]$MaxLines = 4
    )

    $SafeWidth = [Math]::Max(1, $Width)
    $SafeMaxLines = [Math]::Max(1, $MaxLines)
    if ($null -eq $Line) { $Line = '' }
    $Text = [string]$Line

    if ($Text.Length -le $SafeWidth) { return @($Text) }

    # Label/value metadata lines get aligned continuation wrapping, especially paths.
    # Examples: Transcript log: C:\..., Session index: C:\..., Output folder: Reports\...
    if ($Text -match '^(?<Label>(Transcript log|Transcript log saved to|Session index|Report root|Output folder|Full output folder|Run Summary|XML backup|XLSX report|CSV report|Summary saved|Diagnostics file|Script build|Script version|Script file|File|Path)\s*:\s*)(?<Value>.+)$') {
        $Label = [string]$Matches['Label']
        $Value = [string]$Matches['Value']
        $FirstValueWidth = [Math]::Max(1, $SafeWidth - $Label.Length)
        $ContinuationIndent = ' ' * [Math]::Min($Label.Length, [Math]::Max(0, $SafeWidth - 1))
        $ContinuationWidth = [Math]::Max(1, $SafeWidth - $ContinuationIndent.Length)
        $IsPathLike = ($Value -match '^[A-Za-z]:[\\/]' -or $Value -match '^\\' -or $Value -match '[\\/]')
        $Rows = [System.Collections.Generic.List[string]]::new()

        if ($IsPathLike -and $FirstValueWidth -lt 8) {
            $Rows.Add($Label.TrimEnd())
            $WrappedValue = Split-MOCTextByWidth -Text $Value -Width $ContinuationWidth -MaxLines ($SafeMaxLines - 1)
            foreach ($WrappedLine in $WrappedValue) { $Rows.Add($ContinuationIndent + $WrappedLine) }
            return @($Rows)
        }

        $FirstChunks = Split-MOCTextByWidth -Text $Value -Width $FirstValueWidth -MaxLines 1
        if ($IsPathLike -and $FirstChunks.Count -gt 0 -and $FirstChunks[0] -match '^[A-Za-z]$') {
            $Rows.Add($Label.TrimEnd())
            $WrappedValue = Split-MOCTextByWidth -Text $Value -Width $ContinuationWidth -MaxLines ($SafeMaxLines - 1)
            foreach ($WrappedLine in $WrappedValue) { $Rows.Add($ContinuationIndent + $WrappedLine) }
            return @($Rows)
        }

        $Rows.Add($Label + $FirstChunks[0])
        $Consumed = $FirstChunks[0].Length
        $Remaining = if ($Value.Length -gt $Consumed) { $Value.Substring($Consumed).TrimStart() } else { '' }
        if (-not [string]::IsNullOrWhiteSpace($Remaining) -and $Rows.Count -lt $SafeMaxLines) {
            $WrappedRemaining = Split-MOCTextByWidth -Text $Remaining -Width $ContinuationWidth -MaxLines ($SafeMaxLines - $Rows.Count)
            foreach ($WrappedLine in $WrappedRemaining) { $Rows.Add($ContinuationIndent + $WrappedLine) }
        }

        return @($Rows)
    }

    # If an arbitrary line contains a very long path, use path-aware wrapping instead of clipping.
    if ($Text -match '[A-Za-z]:[\\/]' -or $Text -match '^\\' -or $Text -match '[\\/]') {
        return @(Split-MOCTextByWidth -Text $Text -Width $SafeWidth -MaxLines $SafeMaxLines)
    }

    return @((Truncate-Text -Text $Text -MaxLength $SafeWidth))
}

function Write-Centered {
    param([string]$Text, [int]$Width = (Get-TerminalWidth), [string]$Color = $script:Ansi.Reset)
    $CleanLength = $Text.Length
    $Left = [Math]::Max(0, [Math]::Floor(($Width - $CleanLength) / 2))
    Write-Color ((' ' * $Left) + $Text) $Color
}

function Get-MaskedTenant {
    # Do not display the configured tenant ID before authentication.
    # The tenant header should behave like Organization: blank until the parent
    # MOC authentication flow validates the session and resolves the tenant.
    if (-not $script:MOC_Authenticated) { return '' }

    $TenantToDisplay = if (-not [string]::IsNullOrWhiteSpace([string]$script:MOC_GraphTenantId)) {
        [string]$script:MOC_GraphTenantId
    } else {
        [string]$script:MOC_TenantId
    }

    if ([string]::IsNullOrWhiteSpace($TenantToDisplay) -or $TenantToDisplay.Length -lt 8) { return '' }
    return ($TenantToDisplay.Substring(0, 8) + '**********************' + $TenantToDisplay.Substring($TenantToDisplay.Length - 4))
}


function Invoke-MOCClearHost {
    # Soft redraw for same-size frames and debounced resize frames. Avoid hard clearing
    # during routine navigation/resize because it causes visible flicker in Windows Terminal.
    # Major screen-mode transitions should call Invoke-MOCHardClearHost directly.
    Update-MOCResponsiveLayout

    if ($script:MOC_SoftRedrawEnabled) {
        try {
            [Console]::CursorVisible = $false
            $script:MOC_CurrentFrameLineCount = 0
            $script:MOC_CurrentFrameBuffer = [System.Collections.Generic.List[string]]::new()
            $script:MOC_FrameBufferActive = $true
            if ($script:MOC_TerminalSizeChanged) {
                $script:MOC_TerminalSizeChanged = $false
            }
            return
        }
        catch { }
    }

    Invoke-MOCHardClearHost
}

function Invoke-MOCHardClearHost {
    # Use for major screen-mode transitions and once after terminal resize.
    try {
        [Console]::CursorVisible = $false
        [Console]::Clear()
        $script:MOC_CurrentFrameLineCount = 0
        $script:MOC_LastFrameLineCount = 0
        $script:MOC_CurrentFrameBuffer = [System.Collections.Generic.List[string]]::new()
        $script:MOC_LastFrameBuffer = @()
        $script:MOC_FrameBufferActive = $false
        return
    }
    catch { }

    try {
        $Esc = [char]27
        [Console]::Out.Write("$Esc[3J$Esc[2J$Esc[H")
        [Console]::Out.Flush()
        $script:MOC_CurrentFrameLineCount = 0
        $script:MOC_LastFrameLineCount = 0
        $script:MOC_CurrentFrameBuffer = [System.Collections.Generic.List[string]]::new()
        $script:MOC_LastFrameBuffer = @()
        $script:MOC_FrameBufferActive = $false
        return
    }
    catch { }

    try {
        $raw = $Host.UI.RawUI
        $raw.CursorPosition = New-Object System.Management.Automation.Host.Coordinates 0, 0
        $script:MOC_CurrentFrameLineCount = 0
        $script:MOC_LastFrameLineCount = 0
        $script:MOC_CurrentFrameBuffer = [System.Collections.Generic.List[string]]::new()
        $script:MOC_LastFrameBuffer = @()
        $script:MOC_FrameBufferActive = $false
    }
    catch { }
}

function Write-Header {
    Update-MOCResponsiveLayout
    Invoke-MOCClearHost

    $Width = Get-TerminalWidth
    $AuthState = if ($script:MOC_Authenticated) { 'Connected' } else { 'Not Connected' }
    $AuthColor = if ($script:MOC_Authenticated) { $script:Ansi.Green } else { $script:Ansi.Yellow }
    $OrganizationDisplay = if ([string]::IsNullOrWhiteSpace($script:MOC_OrganizationName)) { 'Organization:' } else { "Organization: $($script:MOC_OrganizationName)" }

    Write-Color (New-Line -Width $Width -Char '─') $script:Ansi.Blue

    if (Test-MOCCompactLayout) {
        Write-Centered 'Helpdesk - M365 Operations Console' -Width $Width -Color "$($script:Ansi.Bold)$($script:Ansi.Blue)"
        Write-Centered ("{0}     Menu: v{1}" -f $OrganizationDisplay, $script:MOC_Version) -Width $Width -Color $script:Ansi.Cyan
        Write-Centered ("Tenant: {0}     Auth: {1}     User: {2}" -f (Get-MaskedTenant), $AuthState, $CurrentUser) -Width $Width -Color $AuthColor
        if ($script:MOC_LastScript) {
            Write-Centered ("Last Run: {0} ({1})     Status: {2}" -f $script:MOC_LastScript, $script:MOC_LastDuration, $script:MOC_LastStatus) -Width $Width -Color $script:Ansi.Gray
        }
    }
    else {
        Write-Centered '██╗  ██╗███████╗██╗     ██████╗ ██████╗ ███████╗███████╗██╗  ██╗      ███╗   ███╗ ██████╗  ██████╗' -Width $Width -Color "$($script:Ansi.Bold)$($script:Ansi.Green)"
        Write-Centered '██║  ██║██╔════╝██║     ██╔══██╗██╔══██╗██╔════╝██╔════╝██║ ██╔╝      ████╗ ████║██╔═══██╗██╔════╝' -Width $Width -Color "$($script:Ansi.Bold)$($script:Ansi.Green)"
        Write-Centered '███████║█████╗  ██║     ██████╔╝██║  ██║█████╗  ███████╗█████╔╝       ██╔████╔██║██║   ██║██║     ' -Width $Width -Color "$($script:Ansi.Bold)$($script:Ansi.Cyan)"
        Write-Centered '██╔══██║██╔══╝  ██║     ██╔═══╝ ██║  ██║██╔══╝  ╚════██║██╔═██╗       ██║╚██╔╝██║██║   ██║██║     ' -Width $Width -Color "$($script:Ansi.Bold)$($script:Ansi.Cyan)"
        Write-Centered '██║  ██║███████╗███████╗██║     ██████╔╝███████╗███████║██║  ██╗      ██║ ╚═╝ ██║╚██████╔╝╚██████╗' -Width $Width -Color "$($script:Ansi.Bold)$($script:Ansi.Blue)"
        Write-Centered '╚═╝  ╚═╝╚══════╝╚══════╝╚═╝     ╚═════╝ ╚══════╝╚══════╝╚═╝  ╚═╝      ╚═╝     ╚═╝ ╚═════╝  ╚═════╝' -Width $Width -Color "$($script:Ansi.Bold)$($script:Ansi.Blue)"
        Write-Centered 'Helpdesk - M365 Operations Console' -Width $Width -Color $script:Ansi.Blue
        Write-Color ''
        Write-Centered ("{0}     Menu: v{1}" -f $OrganizationDisplay, $script:MOC_Version) -Width $Width -Color $script:Ansi.Cyan
        Write-Centered ("Tenant: {0}     Auth: {1}     User: {2}" -f (Get-MaskedTenant), $AuthState, $CurrentUser) -Width $Width -Color $AuthColor
        if ($script:MOC_LastScript) {
            Write-Centered ("Last Run: {0} ({1})     Status: {2}" -f $script:MOC_LastScript, $script:MOC_LastDuration, $script:MOC_LastStatus) -Width $Width -Color $script:Ansi.Gray
        }
    }

    Write-Color (New-Line -Width $Width -Char '─') $script:Ansi.Blue

    if (-not (Test-ConsoleSize)) {
        $size = Get-MOCTerminalSize
        Write-Color ("MOC terminal window is too small. Current: {0} x {1}. Minimum: {2} x {3}. Resize the terminal to continue comfortably." -f $size.Width, $size.Height, $script:MOC_MinWidth, $script:MOC_MinHeight) $script:Ansi.Yellow
    }
}

function Get-Breadcrumb {
    if ($script:MOC_View -eq 'Home') { return 'Home' }
    if ($script:MOC_View -eq 'ModuleMaintenance') { return 'Home > Module Maintenance' }
    if ($script:MOC_View -eq 'Terminal') { return 'Home > Terminal' }
    if ($script:MOC_View -eq 'Configuration') { return 'Home > Configuration' }
    return "Home > $script:MOC_CurrentFolder"
}

function Write-Breadcrumb {
    Write-Color (Get-Breadcrumb) $script:Ansi.Green
    Write-Color ''
}

function Get-MOCFooterTopRow {
    [CmdletBinding()]
    param()

    try {
        $Size = Get-MOCTerminalSize
        $VisibleHeight = [int]$Size.Height
        try {
            $ConsoleHeight = [int][Console]::WindowHeight
            if ($ConsoleHeight -gt 0) { $VisibleHeight = [Math]::Min($VisibleHeight, $ConsoleHeight) }
        }
        catch { }
        return [Math]::Max(0, $VisibleHeight - 3)
    }
    catch {
        return [Math]::Max(0, [int]$script:MOC_TargetHeight - 3)
    }
}

function Get-MOCDynamicPaneBlankRows {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [int]$MinimumRows = 2,

        [Parameter(Mandatory = $false)]
        [int]$ReservedRows = 1
    )

    try {
        $FooterTop = Get-MOCFooterTopRow
        $CurrentRows = 0
        if ($script:MOC_SoftRedrawEnabled -and $script:MOC_FrameBufferActive -and $null -ne $script:MOC_CurrentFrameBuffer) {
            $CurrentRows = [int]$script:MOC_CurrentFrameBuffer.Count
        }
        else {
            $CurrentRows = [int]$script:MOC_CurrentFrameLineCount
        }

        $Remaining = [int]$FooterTop - [int]$CurrentRows - [int]$ReservedRows
        return [Math]::Max([int]$MinimumRows, [int]$Remaining)
    }
    catch {
        return [Math]::Max(0, [int]$MinimumRows)
    }
}

function Get-FooterHintText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [int]$AvailableWidth,

        [Parameter(Mandatory = $false)]
        [string]$View = $script:MOC_View
    )

    $innerWidth = [Math]::Max(1, $AvailableWidth)

    # Build navigation help as prioritized items rather than one long string.
    # This prevents narrow windows from clipping important controls like Q Quit.
    # Priority 1 items are essential and are kept first. Higher priorities drop first.
    if ($View -eq 'Home') {
        $items = @(
            [pscustomobject]@{ Priority = 1; Full = 'Up/Down: Move';    Short = 'Up/Down: Move';     Mini = 'U/D: Move' },
            [pscustomobject]@{ Priority = 1; Full = 'Enter: Open Folder'; Short = 'Enter: Open'; Mini = 'Ent: Open' },
            [pscustomobject]@{ Priority = 2; Full = 'A: Auth';          Short = 'A: Auth';      Mini = 'A: Auth' },
            [pscustomobject]@{ Priority = 2; Full = 'M: Modules';       Short = 'M: Modules';   Mini = 'M: Mods' },
            [pscustomobject]@{ Priority = 2; Full = 'T: Terminal';      Short = 'T: Terminal';  Mini = 'T: Term' },
            [pscustomobject]@{ Priority = 2; Full = 'U: Update';        Short = 'U: Update';    Mini = 'U: Upd' },
            [pscustomobject]@{ Priority = 2; Full = 'C: Configure';     Short = 'C: Config';    Mini = 'C: Cfg' },
            [pscustomobject]@{ Priority = 2; Full = 'R: Refresh';       Short = 'R: Refresh';   Mini = 'R: Ref' },
            [pscustomobject]@{ Priority = 1; Full = 'Q: Quit';          Short = 'Q: Quit';      Mini = 'Q: Quit' },
            [pscustomobject]@{ Priority = 3; Full = 'Number+Enter: Jump'; Short = 'Num+Enter: Jump'; Mini = '#: Jump' }
        )
    }
    elseif ($View -eq 'AuthReview') {
        $items = @(
            [pscustomobject]@{ Priority = 1; Full = 'PgUp/PgDn: Page'; Short = 'PgUp/PgDn: Page'; Mini = 'Pg: Page' },
            [pscustomobject]@{ Priority = 1; Full = 'Up/Down: Scroll'; Short = 'Up/Down: Scroll'; Mini = 'U/D: Scroll' },
            [pscustomobject]@{ Priority = 2; Full = 'Home/End: Jump'; Short = 'Home/End: Jump'; Mini = 'H/E: Jump' },
            [pscustomobject]@{ Priority = 1; Full = 'Enter: Return'; Short = 'Enter: Return'; Mini = 'Ent: Return' },
            [pscustomobject]@{ Priority = 1; Full = 'Esc: Return'; Short = 'Esc: Return'; Mini = 'Esc: Back' }
        )
    }
    elseif ($View -eq 'RunConsole') {
        $items = @(
            [pscustomobject]@{ Priority = 1; Full = 'PgUp/PgDn: Page';      Short = 'PgUp/PgDn: Page';  Mini = 'Pg: Page' },
            [pscustomobject]@{ Priority = 1; Full = 'Up/Down: Scroll';      Short = 'Up/Down: Scroll';  Mini = 'U/D: Scroll' },
            [pscustomobject]@{ Priority = 2; Full = 'Home: Top / End: Latest'; Short = 'Home/End: Jump';   Mini = 'H/E: Jump' },
            [pscustomobject]@{ Priority = 1; Full = 'Enter: Submit/Return'; Short = 'Enter: Submit';    Mini = 'Ent: Submit' },
            [pscustomobject]@{ Priority = 2; Full = 'Esc: Cancel/Back';     Short = 'Esc: Back';        Mini = 'Esc: Back' }
        )
    }
    elseif ($View -eq 'Terminal') {
        $items = @(
            [pscustomobject]@{ Priority = 1; Full = 'PgUp/PgDn: Page';       Short = 'PgUp/PgDn: Page'; Mini = 'Pg: Page' },
            [pscustomobject]@{ Priority = 1; Full = 'Up/Down: Scroll';       Short = 'Up/Down: Scroll'; Mini = 'U/D: Scroll' },
            [pscustomobject]@{ Priority = 2; Full = 'Home/End: Jump';        Short = 'Home/End: Jump';  Mini = 'H/E: Jump' },
            [pscustomobject]@{ Priority = 1; Full = 'Enter: Run';            Short = 'Enter: Run';      Mini = 'Ent: Run' },
            [pscustomobject]@{ Priority = 3; Full = 'Paste Editor: E/Edit D/Delete I/Insert'; Short = 'Paste Edit: E/D/I'; Mini = 'Edit: E/D/I' },
            [pscustomobject]@{ Priority = 2; Full = 'Clear/Cls: Clear';      Short = 'Clear: Clear';    Mini = 'Cls: Clear' },
            [pscustomobject]@{ Priority = 1; Full = 'Exit/Back/Quit: Return'; Short = 'Exit: Return';   Mini = 'Exit: Ret' }
        )
    }
    elseif ($View -eq 'Configuration') {
        $items = @(
            [pscustomobject]@{ Priority = 1; Full = 'Number: Edit'; Short = 'Number: Edit'; Mini = '#: Edit' },
            [pscustomobject]@{ Priority = 1; Full = 'S: Save'; Short = 'S: Save'; Mini = 'S: Save' },
            [pscustomobject]@{ Priority = 2; Full = 'L: Reload'; Short = 'L: Reload'; Mini = 'L: Load' },
            [pscustomobject]@{ Priority = 2; Full = 'T: Test'; Short = 'T: Test'; Mini = 'T: Test' },
            [pscustomobject]@{ Priority = 1; Full = 'Esc: Return'; Short = 'Esc: Return'; Mini = 'Esc: Back' }
        )
    }
    elseif ($View -eq 'ModuleMaintenance') {
        $items = @(
            [pscustomobject]@{ Priority = 1; Full = 'I: Install Missing'; Short = 'I: Install'; Mini = 'I: Inst' },
            [pscustomobject]@{ Priority = 1; Full = 'U: Upgrade Latest';  Short = 'U: Upgrade'; Mini = 'U: Upg' },
            [pscustomobject]@{ Priority = 2; Full = 'R: Recheck PSGallery'; Short = 'R: Recheck'; Mini = 'R: Rechk' },
            [pscustomobject]@{ Priority = 1; Full = 'Esc: Return';       Short = 'Esc: Return'; Mini = 'Esc: Back' }
        )
    }
    else {
        $items = @(
            [pscustomobject]@{ Priority = 1; Full = 'Up/Down: Move';      Short = 'Up/Down: Move';     Mini = 'U/D: Move' },
            [pscustomobject]@{ Priority = 1; Full = 'Enter: Run';         Short = 'Enter: Run';   Mini = 'Ent: Run' },
            [pscustomobject]@{ Priority = 2; Full = 'Backspace: Home';    Short = 'Back: Home';   Mini = 'Bksp: Home' },
            [pscustomobject]@{ Priority = 2; Full = 'A: Auth';            Short = 'A: Auth';      Mini = 'A: Auth' },
            [pscustomobject]@{ Priority = 2; Full = 'M: Modules';         Short = 'M: Modules';   Mini = 'M: Mods' },
            [pscustomobject]@{ Priority = 2; Full = 'T: Terminal';        Short = 'T: Terminal';  Mini = 'T: Term' },
            [pscustomobject]@{ Priority = 2; Full = 'U: Update';          Short = 'U: Update';    Mini = 'U: Upd' },
            [pscustomobject]@{ Priority = 2; Full = 'C: Configure';       Short = 'C: Config';    Mini = 'C: Cfg' },
            [pscustomobject]@{ Priority = 2; Full = 'R: Refresh';         Short = 'R: Refresh';   Mini = 'R: Ref' },
            [pscustomobject]@{ Priority = 1; Full = 'Q: Quit';            Short = 'Q: Quit';      Mini = 'Q: Quit' },
            [pscustomobject]@{ Priority = 3; Full = 'PgUp/PgDn: Page';    Short = 'PgUp/PgDn: Page';   Mini = 'Pg: Page' },
            [pscustomobject]@{ Priority = 3; Full = 'Number+Enter: Jump'; Short = 'Num+Enter: Jump';   Mini = '#: Jump' }
        )
    }

    function Join-FooterItems {
        param(
            [Parameter(Mandatory = $true)]
            [object[]]$Items,

            [Parameter(Mandatory = $true)]
            [ValidateSet('Full','Short','Mini')]
            [string]$LabelProperty
        )

        return (($Items | ForEach-Object { [string]$_.$LabelProperty }) -join '   ')
    }

    foreach ($labelMode in @('Full', 'Short', 'Mini')) {
        foreach ($maxPriority in @(3, 2, 1)) {
            $candidateItems = @($items | Where-Object { $_.Priority -le $maxPriority } | Sort-Object Priority)

            # Keep Quit at the far right when possible by reordering within the final selected set.
            $nonQuit = @($candidateItems | Where-Object { $_.Full -ne 'Q: Quit' })
            $quit = @($candidateItems | Where-Object { $_.Full -eq 'Q: Quit' })
            $candidateItems = @($nonQuit + $quit)

            $candidate = Join-FooterItems -Items $candidateItems -LabelProperty $labelMode

            if ($candidate.Length -le $innerWidth) {
                return $candidate
            }
        }
    }

    # Last-resort compact footer. Preserve quit guidance and avoid partial truncation.
    if ($innerWidth -ge 24) {
        return 'Enter: Select   Q: Quit'
    }

    if ($innerWidth -ge 10) {
        return 'Q: Quit'
    }

    return 'Q'
}

function Write-Footer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [switch]$NoComplete,

        [Parameter(Mandatory = $false)]
        [switch]$NoAnchor
    )

    Update-MOCResponsiveLayout
    $Width = Get-TerminalWidth
    $SafeWidth = [Math]::Max(60, $Width)

    # Keep the navigation footer visible even when a pane above it is taller than expected.
    # Windows Terminal/RawUI can occasionally report a usable height that differs from the
    # visible viewport. Anchoring the footer to the bottom three rows prevents it from being
    # pushed below the visible screen by Home, Authentication, or Module Maintenance panes.
    $FooterTop = -1
    if (-not $NoAnchor) {
        try {
            $Size = Get-MOCTerminalSize
            $VisibleHeight = [int]$Size.Height
            try {
                $ConsoleHeight = [int][Console]::WindowHeight
                if ($ConsoleHeight -gt 0) { $VisibleHeight = [Math]::Min($VisibleHeight, $ConsoleHeight) }
            }
            catch { }
            $FooterTop = [Math]::Max(0, $VisibleHeight - 3)

            # In soft-redraw mode, Write-Color writes to an off-screen frame buffer.
            # Moving the console cursor alone does not anchor buffered footer lines.
            # Reserve the bottom three buffer rows for the footer so it is always
            # visible inside the current terminal viewport.
            if ($script:MOC_SoftRedrawEnabled -and $script:MOC_FrameBufferActive -and $null -ne $script:MOC_CurrentFrameBuffer) {
                while ([int]$script:MOC_CurrentFrameBuffer.Count -gt $FooterTop) {
                    $script:MOC_CurrentFrameBuffer.RemoveAt([int]$script:MOC_CurrentFrameBuffer.Count - 1)
                }
                while ([int]$script:MOC_CurrentFrameBuffer.Count -lt $FooterTop) {
                    [void]$script:MOC_CurrentFrameBuffer.Add('')
                }
                $script:MOC_CurrentFrameLineCount = [int]$script:MOC_CurrentFrameBuffer.Count
            }
            else {
                [Console]::SetCursorPosition(0, $FooterTop)
            }
        }
        catch { }
    }

    function Write-FooterPanelLine {
        param(
            [Parameter(Mandatory = $false)]
            [string]$Text = '',

            [Parameter(Mandatory = $true)]
            [int]$PanelWidth,

            [Parameter(Mandatory = $false)]
            [string]$Color = $script:Ansi.Gray
        )

        # Keep footer text ASCII-only and avoid glyphs with ambiguous display width.
        # This prevents Windows Terminal from misaligning the right border.
        $InnerWidth = [Math]::Max(1, $PanelWidth - 4)
        $SafeText = if ($null -eq $Text) { '' } else { [string]$Text }
        $SafeText = $SafeText -replace '[↑↓←→]', ''

        # Do not blindly truncate a full command string. Footer text is already
        # built to fit by Get-FooterHintText, so this is only a final safety guard.
        if ($SafeText.Length -gt $InnerWidth) {
            $SafeText = Get-FooterHintText -AvailableWidth $InnerWidth -View $script:MOC_View
        }

        if ($SafeText.Length -gt $InnerWidth) {
            $SafeText = Truncate-Text -Text $SafeText -MaxLength $InnerWidth
        }

        $Padded = $SafeText.PadRight($InnerWidth)
        Write-Color ("│ $Padded │") $Color
    }

    $FooterColor = "$($script:Ansi.Bold)$($script:Ansi.Yellow)"
    $FooterText = Get-FooterHintText -AvailableWidth ([Math]::Max(1, $SafeWidth - 4)) -View $script:MOC_View

    Write-Color ("┌" + ('─' * [Math]::Max(1, $SafeWidth - 2)) + "┐") $FooterColor
    Write-FooterPanelLine -Text $FooterText -PanelWidth $SafeWidth -Color $FooterColor
    Write-Color ("└" + ('─' * [Math]::Max(1, $SafeWidth - 2)) + "┘") $FooterColor
    if (-not $NoComplete) {
        Complete-MOCFrameRender
    }
}

# ------------------------------------------------------------
# Logging helpers
# ------------------------------------------------------------
function Write-LauncherLog {
    param([string]$Action, [string]$ScriptName, [string]$Duration = '', [int]$ExitCode = 0)

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

    if ($Action -eq 'FAIL') {
        "$timestamp | User=$CurrentUser | Action=FAIL | Script=$ScriptName | ExitCode=$ExitCode | Duration=$Duration" | Out-File -Append -Encoding utf8 $LogFile
    }
    elseif ($Action -eq 'END') {
        "$timestamp | User=$CurrentUser | Action=END | Script=$ScriptName | Duration=$Duration" | Out-File -Append -Encoding utf8 $LogFile
    }
    else {
        "$timestamp | User=$CurrentUser | Action=$Action | Script=$ScriptName" | Out-File -Append -Encoding utf8 $LogFile
    }
}

function Write-DailyTotal {
    if (-not (Test-Path $LogFile)) { return }

    $totalSeconds = 0
    foreach ($line in Get-Content $LogFile) {
        if ($line -match 'Duration=(\d+:\d+(?::\d+)?)') {
            $totalSeconds += Convert-LoggedDurationToSeconds -Duration $matches[1]
        }
    }

    $totalFormatted = Format-Duration $totalSeconds
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    "$timestamp | User=$CurrentUser | DAILY_TOTAL | Runtime=$totalFormatted" | Out-File -Append -Encoding utf8 $LogFile
}

# ------------------------------------------------------------
# Script metadata parsing
# ------------------------------------------------------------
function Get-ScriptMetadata {
    [CmdletBinding()]
    param([string]$Path)

    return Get-MOCScriptMetadata -Path $Path
}


function Update-MOCOrganizationName {
    $script:MOC_OrganizationName = ''

    try {
        if (Get-Command Get-MgOrganization -ErrorAction SilentlyContinue) {
            $Org = Get-MgOrganization -ErrorAction Stop | Select-Object -First 1
            if ($null -ne $Org -and -not [string]::IsNullOrWhiteSpace($Org.DisplayName)) {
                $script:MOC_OrganizationName = [string]$Org.DisplayName
            }
        }
    }
    catch {
        $script:MOC_OrganizationName = ''
    }
}

function Test-MOCBenignAuthLoggingError {
    param([object]$ErrorRecord)

    $Message = ''
    try { $Message = [string]$ErrorRecord.Exception.Message } catch { $Message = [string]$ErrorRecord }
    return ($Message -match 'Error to log cannot be null/empty')
}

# ------------------------------------------------------------
# MOC shared session
# ------------------------------------------------------------

function Add-MOCDisableWAMParameter {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$CommandName,
        [Parameter(Mandatory = $true)][hashtable]$Parameters
    )

    try {
        $Command = Get-Command -Name $CommandName -ErrorAction Stop
        if ($Command.Parameters.ContainsKey('DisableWAM') -and -not $Parameters.ContainsKey('DisableWAM')) {
            $Parameters['DisableWAM'] = $true
        }
    }
    catch {
        # Older modules or unavailable commands may not expose -DisableWAM. Keep authentication compatible.
    }
}

function Set-MOCAzProcessAuthBehavior {
    [CmdletBinding()]
    param()

    $ConfiguredAny = $false

    try {
        $Command = Get-Command -Name 'Update-AzConfig' -ErrorAction Stop
        $CommonParams = @{
            Scope             = 'Process'
            ErrorAction       = 'SilentlyContinue'
            WarningAction     = 'SilentlyContinue'
            InformationAction = 'SilentlyContinue'
            Verbose           = $false
            Debug             = $false
        }

        $ConfigAttempts = @(
            @{ Name = 'DisplayBreakingChangeWarning'; Value = $false },
            @{ Name = 'DisplaySurveyMessage';          Value = $false },
            @{ Name = 'LoginExperienceV2';             Value = 'Off' },
            @{ Name = 'EnableLoginByWam';              Value = $false }
        )

        foreach ($Attempt in $ConfigAttempts) {
            if ($Command.Parameters.ContainsKey($Attempt.Name)) {
                try {
                    $Params = @{} + $CommonParams
                    $Params[$Attempt.Name] = $Attempt.Value

                    # Az.Accounts returns PSConfig objects and may emit information/warning text.
                    # Suppress all module chatter here and let MOC print one clean status line.
                    $null = Update-AzConfig @Params 3>$null 4>$null 5>$null 6>$null
                    $ConfiguredAny = $true
                }
                catch {
                    # Keep authentication compatible across Az.Accounts versions.
                }
            }
        }
    }
    catch {
        # Az.Accounts versions without Update-AzConfig should continue using default behavior.
    }

    return [bool]$ConfiguredAny
}

function Add-MOCQuietAuthParameters {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$CommandName,
        [Parameter(Mandatory = $true)][hashtable]$Parameters
    )

    try {
        $Command = Get-Command -Name $CommandName -ErrorAction Stop

        foreach ($CommonName in @('WarningAction','InformationAction')) {
            if ($Command.Parameters.ContainsKey($CommonName) -and -not $Parameters.ContainsKey($CommonName)) {
                $Parameters[$CommonName] = 'SilentlyContinue'
            }
        }

        if ($Command.Parameters.ContainsKey('DisableWAM') -and -not $Parameters.ContainsKey('DisableWAM')) {
            $Parameters['DisableWAM'] = $true
        }

        # Do not automatically add -UseDeviceAuthentication here. When its informational device-code
        # instructions are suppressed or redirected by a framed terminal UI, authentication can appear
        # stuck because the technician never sees the code. Prefer WAM-disabled browser authentication
        # through Az.Accounts configuration and keep all emitted text controlled by MOC.
    }
    catch {
        # Keep authentication compatible if command metadata cannot be read.
    }
}

function Reset-MOCHeaderUserToLocalSession {
    [CmdletBinding()]
    param()

    if (-not [string]::IsNullOrWhiteSpace($script:MOC_LocalSessionUser)) {
        $script:CurrentUser = $script:MOC_LocalSessionUser
        Set-Variable -Name CurrentUser -Scope Script -Value $script:MOC_LocalSessionUser -ErrorAction SilentlyContinue
    }
}

function Set-MOCHeaderUserFromAuthenticatedContext {
    [CmdletBinding()]
    param()

    $ResolvedUser = $null

    try {
        $ExoConnection = Get-ConnectionInformation -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -ne $ExoConnection) {
            foreach ($PropertyName in @('UserPrincipalName','UserPrincipalNameFromClaims','TokenSubject','Name')) {
                if ($ExoConnection.PSObject.Properties.Name -contains $PropertyName) {
                    $Candidate = [string]$ExoConnection.$PropertyName
                    if ($Candidate -match '@' -and -not [string]::IsNullOrWhiteSpace($Candidate)) {
                        $ResolvedUser = $Candidate
                        break
                    }
                }
            }
        }
    }
    catch {}

    if ([string]::IsNullOrWhiteSpace($ResolvedUser)) {
        try {
            $AzContext = Get-AzContext -ErrorAction SilentlyContinue
            if ($null -ne $AzContext -and $AzContext.Account -and -not [string]::IsNullOrWhiteSpace([string]$AzContext.Account.Id)) {
                $ResolvedUser = [string]$AzContext.Account.Id
            }
        }
        catch {}
    }

    if ([string]::IsNullOrWhiteSpace($ResolvedUser)) {
        try {
            $MgContext = Get-MgContext -ErrorAction SilentlyContinue
            if ($null -ne $MgContext -and -not [string]::IsNullOrWhiteSpace([string]$MgContext.Account)) {
                $ResolvedUser = [string]$MgContext.Account
            }
        }
        catch {}
    }

    if (-not [string]::IsNullOrWhiteSpace($ResolvedUser)) {
        $script:CurrentUser = $ResolvedUser
        Set-Variable -Name CurrentUser -Scope Script -Value $ResolvedUser -ErrorAction SilentlyContinue
    }
}

function Invoke-MOCPostInteractiveAuthRedraw {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()]
        [Parameter(Mandatory = $true)][System.Collections.Generic.List[string]]$OutputBuffer,
        [string]$ScriptName = 'MOC Shared Authentication Session',
        [string]$Status = 'Running'
    )

    try {
        # Some authentication modules write account-selection text directly to the host. Hard-clearing and
        # redrawing after the interactive step returns keeps that text from remaining below the MOC frame.
        Invoke-MOCHardClearHost
        Write-RunConsoleFrame -ScriptName $ScriptName -OutputBuffer $OutputBuffer -ScrollOffset (Get-MOCRunConsoleScrollMaxOffset -OutputBuffer $OutputBuffer) -Status $Status -FooterView 'AuthReview'
    }
    catch {}
}

function Test-MOCGraphAccessTokenRefreshNeeded {
    [CmdletBinding()]
    param()

    try {
        if ($null -eq $script:MOC_GraphTokenExpiresUtc) { return $false }

        $ExpiresUtc = [datetime]$script:MOC_GraphTokenExpiresUtc
        $RefreshThresholdUtc = (Get-Date).ToUniversalTime().AddMinutes(5)

        return ($ExpiresUtc -le $RefreshThresholdUtc)
    }
    catch {
        return $false
    }
}

function Test-MOCGraphSession {
    try {
        if (-not (Get-Command -Name Get-MgContext -ErrorAction SilentlyContinue)) { return $false }

        $Context = Get-MgContext -ErrorAction SilentlyContinue
        if ($null -eq $Context) { return $false }
        if ([string]::IsNullOrWhiteSpace([string]$Context.TenantId)) { return $false }
        if ([string]$Context.TenantId -ne [string]$script:MOC_TenantId) { return $false }
        if (-not [string]::IsNullOrWhiteSpace([string]$script:MOC_ClientId) -and -not [string]::IsNullOrWhiteSpace([string]$Context.ClientId)) {
            if ([string]$Context.ClientId -ne [string]$script:MOC_ClientId) { return $false }
        }

        # Do not call an arbitrary Graph endpoint here. A permission/transient failure can be
        # misclassified as token expiry. Actual token-expired responses are handled when a
        # child script makes its real Graph call, and A-auth always gets a fresh token.
        if (Test-MOCGraphAccessTokenRefreshNeeded) { return $false }

        return $true
    }
    catch { return $false }
}

function Test-MOCExchangeSession {
    try {
        if (-not (Get-Command Get-ConnectionInformation -ErrorAction SilentlyContinue)) { return $false }

        $ExchangeConnection = @(Get-ConnectionInformation -ErrorAction SilentlyContinue | Where-Object {
            ($_.Name -like 'ExchangeOnline*' -or $_.ConnectionUri -like '*outlook.office365.com*') -and
            ([string]$_.State -notmatch 'Disconnected|Closed|Broken' -or [string]$_.TokenStatus -eq 'Active')
        })
        if ($ExchangeConnection.Count -eq 0) { return $false }

        # HelpDesk-MOC intentionally uses limited Exchange Online validation.
        # Some HelpDesk Exchange RBAC role assignments can connect successfully but do not include
        # tenant-wide validation commands such as Get-OrganizationConfig. Do not require that command
        # here; child scripts will still fail with their own RBAC error if a script-specific cmdlet is unavailable.
        $ValidationCommandNames = @(
            'Get-EXOMailbox',
            'Get-Mailbox',
            'Set-Mailbox',
            'Set-MailboxAutoReplyConfiguration'
        )

        foreach ($ValidationCommandName in $ValidationCommandNames) {
            if (Get-Command -Name $ValidationCommandName -ErrorAction SilentlyContinue) {
                return $true
            }
        }

        # If Exchange reports an active connection but no sampled cmdlets are visible, still treat the
        # parent session as connected. This avoids blocking limited RBAC operators during global auth.
        return $true
    }
    catch { return $false }
}

function Test-MOCPurviewSession {
    try {
        if (-not (Get-Command Get-ERSCRoleGroup -ErrorAction SilentlyContinue)) { return $false }
        if (-not (Get-Command Get-ERSCComplianceSearch -ErrorAction SilentlyContinue)) { return $false }

        # Prove the prefixed Purview session can execute a lightweight command. The
        # compliance-search command check also confirms that the parent connection
        # was created with EnableSearchOnlySession for eDiscovery child scripts.
        $null = Get-ERSCRoleGroup -ErrorAction Stop | Select-Object -First 1
        return $true
    }
    catch { return $false }
}



function Test-MOCScriptRequiresPurview {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [pscustomobject]$Script
    )

    if ($null -eq $Script) { return $false }

    try {
        if ($Script.PSObject.Properties.Name -contains 'RequiredPowerShellModules') {
            foreach ($ModuleName in @($Script.RequiredPowerShellModules)) {
                if ([string]$ModuleName -match '(?i)(purview|compliance|ipps|security\s*&\s*compliance)') {
                    return $true
                }
            }
        }
    }
    catch { }

    try {
        $ScriptPath = [string]$Script.Path
        if ([string]::IsNullOrWhiteSpace($ScriptPath) -or -not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)) {
            return $false
        }

        $Raw = Get-Content -LiteralPath $ScriptPath -Raw -ErrorAction Stop

        # Detect common Purview / Security & Compliance cmdlets and the MOC-prefixed
        # search-only command names created through Connect-IPPSSession -Prefix ERSC.
        $PurviewPattern = '(?i)\b(Connect-IPPSSession|Start-ComplianceSearch|New-ComplianceSearch|Get-ComplianceSearch|Set-ComplianceSearch|Remove-ComplianceSearch|New-ComplianceSearchAction|Get-ComplianceSearchAction|Start-ComplianceSearchAction|Get-CaseHoldPolicy|Get-CaseHoldRule|Get-ComplianceCase|Get-ComplianceSearch|Get-ERSCRoleGroup|Get-ERSCComplianceSearch|Start-ERSCComplianceSearch|New-ERSCComplianceSearch|New-ERSCComplianceSearchAction|Start-ERSCComplianceSearchAction|Get-ERSCComplianceSearchAction)\b'
        if ($Raw -match $PurviewPattern) { return $true }
    }
    catch { }

    return $false
}

function Initialize-MOCLazyPurviewSession {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[string]]$OutputBuffer,

        [Parameter(Mandatory = $false)]
        [string]$ScriptName = 'MOC child script',

        [switch]$ForceRefresh
    )

    function Add-MOCLazyPurviewLine {
        param([AllowNull()][string]$Line)

        if ($null -ne $OutputBuffer) {
            Add-RunConsoleLine -OutputBuffer $OutputBuffer -Line $Line
            try {
                Write-RunConsoleFrame -ScriptName $ScriptName -OutputBuffer $OutputBuffer -ScrollOffset (Get-MOCRunConsoleScrollMaxOffset -OutputBuffer $OutputBuffer) -Status 'Running'
            }
            catch { }
        }
        elseif (-not [string]::IsNullOrWhiteSpace($Line)) {
            Write-Host $Line
        }
    }

    if (-not $ForceRefresh -and (Test-MOCPurviewSession)) {
        Add-MOCLazyPurviewLine 'Microsoft Purview / Security & Compliance search-only session already connected.'
        return $true
    }

    Add-MOCLazyPurviewLine 'Lazy-loading Microsoft Purview / Security & Compliance search-only session...'
    Add-MOCLazyPurviewLine 'Removing any stale prefixed Purview connection...'
    try {
        Disconnect-ExchangeOnline -ModulePrefix 'ERSC' -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
    }
    catch { }

    Add-MOCLazyPurviewLine 'Connecting to Microsoft Purview / Security & Compliance PowerShell only because this child script requires it...'
    $PurviewConnectParams = @{
        Prefix                  = 'ERSC'
        EnableSearchOnlySession = $true
        ErrorAction             = 'Stop'
        WarningAction           = 'SilentlyContinue'
        InformationAction       = 'SilentlyContinue'
    }

    Add-MOCQuietAuthParameters -CommandName 'Connect-IPPSSession' -Parameters $PurviewConnectParams
    Connect-IPPSSession @PurviewConnectParams 3>$null 4>$null 5>$null 6>$null

    if (-not (Test-MOCPurviewSession)) {
        throw 'Purview / Security & Compliance lazy authentication completed, but the search-only session did not pass validation.'
    }

    Add-MOCLazyPurviewLine 'Microsoft Purview / Security & Compliance search-only session connected and validated.'
    return $true
}

function Test-MOCSharedSessionHealth {
    [CmdletBinding()]
    param()

    $GraphOk = Test-MOCGraphSession
    $ExchangeOk = Test-MOCExchangeSession

    $script:MOC_GraphConnected = $GraphOk
    if ($GraphOk) {
        $Context = Get-MgContext -ErrorAction SilentlyContinue
        $script:MOC_GraphTenantId = [string]$Context.TenantId
        $script:MOC_GraphClientId = [string]$Context.ClientId
    }
    else {
        $script:MOC_GraphTenantId = ''
        $script:MOC_GraphClientId = ''
    }

    return ($GraphOk -and $ExchangeOk)
}


function Initialize-MOCSharedSession {
    [CmdletBinding()]
    param(
        [switch]$ForceRefresh
    )

    $AuthScriptName = 'MOC Shared Authentication Session'
    $AuthOutput = [System.Collections.Generic.List[string]]::new()
    $AuthScrollOffset = 0

    function Set-MOCAuthProgress {
        param(
            [int]$Percent = 0,
            [string]$Activity = 'Authentication Session',
            [string]$Status = 'Running',
            [string]$Operation = ''
        )

        if ($Percent -lt 0) { $Percent = 0 }
        if ($Percent -gt 100) { $Percent = 100 }

        $script:MOC_RunConsole_ProgressPercent = $Percent
        $script:MOC_RunConsole_ProgressActivity = $Activity
        $script:MOC_RunConsole_ProgressStatus = $Status
        $script:MOC_RunConsole_ProgressOperation = $Operation

        Write-RunConsoleFrame -ScriptName $AuthScriptName -OutputBuffer $AuthOutput -ScrollOffset (Get-MOCRunConsoleScrollMaxOffset -OutputBuffer $AuthOutput) -Status $Status -FooterView 'AuthReview'
    }

    function Add-MOCAuthLine {
        param(
            [AllowNull()]
            [AllowEmptyString()]
            [string]$Line = '',
            [int]$Percent = -1,
            [string]$Activity = '',
            [string]$Status = 'Running',
            [string]$Operation = ''
        )

        if (-not [string]::IsNullOrWhiteSpace($Line)) {
            [void]$AuthOutput.Add($Line)
        }

        if ($Percent -ge 0) {
            if ([string]::IsNullOrWhiteSpace($Activity)) { $Activity = 'Authentication Session' }
            Set-MOCAuthProgress -Percent $Percent -Activity $Activity -Status $Status -Operation $Operation
        }
        else {
            Write-RunConsoleFrame -ScriptName $AuthScriptName -OutputBuffer $AuthOutput -ScrollOffset (Get-MOCRunConsoleScrollMaxOffset -OutputBuffer $AuthOutput) -Status $Status -FooterView 'AuthReview'
        }
    }

    function Complete-MOCAuthPane {
        param(
            [string]$Status = 'Completed',
            [int]$Percent = 100,
            [string]$Activity = 'Authentication Session',
            [string]$Message = ''
        )

        if (-not [string]::IsNullOrWhiteSpace($Message)) {
            [void]$AuthOutput.Add($Message)
        }

        $script:MOC_RunConsole_ProgressPercent = $Percent
        $script:MOC_RunConsole_ProgressActivity = $Activity
        $script:MOC_RunConsole_ProgressStatus = $Status
        $script:MOC_RunConsole_ProgressOperation = ''
        Write-RunConsoleFrame -ScriptName $AuthScriptName -OutputBuffer $AuthOutput -ScrollOffset (Get-MOCRunConsoleScrollMaxOffset -OutputBuffer $AuthOutput) -Status $Status -FooterView 'AuthReview'
    }

    function Write-MOCAuthReviewFrame {
        param(
            [string]$Status = 'Completed',
            [int]$ScrollOffset = 0
        )

        $PreviousView = $script:MOC_View
        try {
            $script:MOC_View = 'AuthReview'
            Write-RunConsoleFrame -ScriptName $AuthScriptName -OutputBuffer $AuthOutput -ScrollOffset $ScrollOffset -Status $Status -FooterView 'AuthReview'
        }
        finally {
            $script:MOC_View = $PreviousView
        }
    }

    function Wait-MOCAuthPaneReview {
        param(
            [string]$Status = 'Completed'
        )

        $MaxOffset = Get-MOCRunConsoleScrollMaxOffset -OutputBuffer $AuthOutput
        $ViewportHeight = Get-MOCRunConsoleOutputViewportHeight
        $AuthScrollOffset = $MaxOffset

        while ($true) {
            Write-MOCAuthReviewFrame -Status $Status -ScrollOffset $AuthScrollOffset

            $Key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
            Hide-MOCCursor

            if ($Key.VirtualKeyCode -eq 13 -or $Key.VirtualKeyCode -eq 27 -or $Key.Character -match '[Qq]') {
                break
            }
            elseif ($Key.VirtualKeyCode -eq 33) {
                $MaxOffset = Get-MOCRunConsoleScrollMaxOffset -OutputBuffer $AuthOutput
                $ViewportHeight = Get-MOCRunConsoleOutputViewportHeight
                $AuthScrollOffset = [Math]::Max(0, $AuthScrollOffset - $ViewportHeight)
            }
            elseif ($Key.VirtualKeyCode -eq 34) {
                $MaxOffset = Get-MOCRunConsoleScrollMaxOffset -OutputBuffer $AuthOutput
                $ViewportHeight = Get-MOCRunConsoleOutputViewportHeight
                $AuthScrollOffset = [Math]::Min($MaxOffset, $AuthScrollOffset + $ViewportHeight)
            }
            elseif ($Key.VirtualKeyCode -eq 38) {
                $AuthScrollOffset = [Math]::Max(0, $AuthScrollOffset - 1)
            }
            elseif ($Key.VirtualKeyCode -eq 40) {
                $MaxOffset = Get-MOCRunConsoleScrollMaxOffset -OutputBuffer $AuthOutput
                $AuthScrollOffset = [Math]::Min($MaxOffset, $AuthScrollOffset + 1)
            }
            elseif ($Key.VirtualKeyCode -eq 36) {
                $AuthScrollOffset = 0
            }
            elseif ($Key.VirtualKeyCode -eq 35) {
                $AuthScrollOffset = Get-MOCRunConsoleScrollMaxOffset -OutputBuffer $AuthOutput
            }
        }
    }

    if ($script:MOC_Authenticated -and -not $ForceRefresh) {
        if (Test-MOCSharedSessionHealth) {
            $script:MOC_LastStatus = 'Session already connected'
            return
        }

        # The authenticated flag can survive after modules are removed, sessions expire,
        # or a prior authentication attempt only partially completed. Reconnect rather
        # than returning a false-positive parent session to child scripts.
        $script:MOC_Authenticated = $false
        $script:MOC_LastStatus = 'Refreshing shared session'
    }
    elseif ($ForceRefresh) {
        # Pressing A should always refresh Graph access-token authentication. Exchange
        # and Azure sessions are still reused when their live health checks pass. Purview is lazy-loaded per child script.
        $script:MOC_LastStatus = 'Refreshing shared session'
    }

    # Authentication is a major screen-mode transition. Use a hard clear once, then render
    # authentication inside the same framed MOC progress pane used for child scripts.
    # Temporarily switch the global view so header, breadcrumb, and footer are auth-specific.
    $PriorMOCView = $script:MOC_View
    $PriorMOCCurrentFolder = $script:MOC_CurrentFolder
    $script:MOC_View = 'AuthReview'
    $script:MOC_CurrentFolder = $null
    Invoke-MOCHardClearHost
    $script:MOC_RunConsole_ProgressPercent = 0
    $script:MOC_RunConsole_ProgressActivity = 'Authentication Session'
    [void](Import-MOCLocalConfiguration)
    $AuthConfigValidation = Test-MOCLocalConfiguration
    if (-not $AuthConfigValidation.IsComplete) {
        Add-MOCAuthLine -Line 'Configuration is incomplete. Authentication cannot start yet.' -Percent 100 -Activity 'Authentication Session' -Status 'Configuration Required' -Operation 'Run C: Configure'
        Add-MOCAuthLine -Line ('Missing required values: {0}' -f ($AuthConfigValidation.Missing -join ', ')) -Percent 100 -Activity 'Authentication Session' -Status 'Configuration Required' -Operation 'Run C: Configure'
        Add-MOCAuthLine -Line ('Config file: {0}' -f $AuthConfigValidation.Path) -Percent 100 -Activity 'Authentication Session' -Status 'Configuration Required' -Operation 'Run C: Configure'
        Add-MOCAuthLine -Line 'Press Enter to return to MOC, then press C to open Configure.' -Percent 100 -Activity 'Authentication Session' -Status 'Configuration Required' -Operation 'Run C: Configure'
        $script:MOC_LastStatus = 'Auth blocked - configure required values first'
        Write-RunConsoleFrame -ScriptName $AuthScriptName -OutputBuffer $AuthOutput -ScrollOffset (Get-MOCRunConsoleScrollMaxOffset -OutputBuffer $AuthOutput) -Status 'Configuration Required' -FooterView 'AuthReview'
        try { [void]$Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown') } catch { }
        throw 'MOC configuration is incomplete. Run C: Configure before authenticating.'
    }

    $script:MOC_RunConsole_ProgressStatus = 'Initializing'
    $script:MOC_RunConsole_ProgressOperation = 'Preparing parent-owned MOC sessions'
    Write-RunConsoleFrame -ScriptName $AuthScriptName -OutputBuffer $AuthOutput -ScrollOffset $AuthScrollOffset -Status 'Running' -FooterView 'AuthReview'

    try {
        Add-MOCAuthLine -Line 'Initializing shared MOC authentication session...' -Percent 3 -Activity 'Authentication Session' -Status 'Initializing' -Operation 'Loading required PowerShell modules'

        Import-Module Az.Accounts -ErrorAction Stop
        Import-Module Az.KeyVault -ErrorAction Stop
        Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
        Import-Module Microsoft.Graph.Users -ErrorAction Stop
        Import-Module Microsoft.Graph.Groups -ErrorAction Stop
        Import-Module Microsoft.Graph.Identity.DirectoryManagement -ErrorAction Stop
        Import-Module Microsoft.Graph.Identity.Governance -ErrorAction SilentlyContinue
        Import-Module ExchangeOnlineManagement -ErrorAction Stop -WarningAction SilentlyContinue -InformationAction SilentlyContinue 3>$null 4>$null 5>$null 6>$null

        $AzConfigApplied = Set-MOCAzProcessAuthBehavior
        if ($AzConfigApplied) {
            Add-MOCAuthLine -Line 'Az.Accounts configuration validated.' -Percent 9 -Activity 'Authentication Session' -Status 'Running' -Operation 'Configuring quiet Azure sign-in behavior'
        }

        Add-MOCAuthLine -Line 'Required PowerShell modules loaded.' -Percent 10 -Activity 'Authentication Session' -Status 'Running' -Operation 'Checking Azure subscription context'

        try {
            if (-not [string]::IsNullOrWhiteSpace([string]$script:MOC_DesiredSubscriptionId)) {
                $azConfig = Get-AzConfig -ErrorAction SilentlyContinue
                if (-not $azConfig.DefaultSubscriptionForLogin -or $azConfig.DefaultSubscriptionForLogin -ne $script:MOC_DesiredSubscriptionId) {
                    Add-MOCAuthLine -Line "Setting DefaultSubscriptionForLogin to '$script:MOC_DesiredSubscriptionId'..." -Percent 13 -Activity 'Azure Session' -Status 'Running' -Operation 'Setting default subscription'
                    $null = Update-AzConfig -DefaultSubscriptionForLogin $script:MOC_DesiredSubscriptionId -Scope Process -ErrorAction SilentlyContinue -WarningAction SilentlyContinue -InformationAction SilentlyContinue 3>$null 4>$null 5>$null 6>$null
                }
            }
            else {
                Add-MOCAuthLine -Line 'No Azure subscription ID configured. Skipping DefaultSubscriptionForLogin.' -Percent 13 -Activity 'Azure Session' -Status 'Running' -Operation 'Skipping optional subscription default'
            }
        }
        catch {
            Add-MOCAuthLine -Line "WARNING: Could not set DefaultSubscriptionForLogin. $($_.Exception.Message)" -Percent 13 -Activity 'Azure Session' -Status 'Running' -Operation 'Continuing with Azure context validation'
        }

        $AzContext = Get-AzContext -ErrorAction SilentlyContinue
        if (-not $AzContext -or $AzContext.Tenant.Id -ne $script:MOC_TenantId) {
            Add-MOCAuthLine -Line 'Connecting to Azure...' -Percent 18 -Activity 'Azure Session' -Status 'Running' -Operation 'Interactive Azure authentication'
            $AzConnectParams = @{
                TenantId    = $script:MOC_TenantId
                ErrorAction = 'Stop'
            }
            if (-not [string]::IsNullOrWhiteSpace([string]$script:MOC_DesiredSubscriptionId)) {
                $AzConnectParams['SubscriptionId'] = $script:MOC_DesiredSubscriptionId
            }
            Add-MOCQuietAuthParameters -CommandName 'Connect-AzAccount' -Parameters $AzConnectParams
            Add-MOCAuthLine -Line 'If prompted, complete the Azure sign-in flow. MOC will redraw after authentication returns.' -Percent 19 -Activity 'Azure Session' -Status 'Running' -Operation 'Waiting for Azure sign-in'
            Add-MOCAuthLine -Line 'If no sign-in window appears within a few seconds, check the browser or existing Az session window.' -Percent 19 -Activity 'Azure Session' -Status 'Running' -Operation 'Waiting for Azure sign-in'
            Invoke-MOCPostInteractiveAuthRedraw -OutputBuffer $AuthOutput -ScriptName $AuthScriptName -Status 'Running'
            Connect-AzAccount @AzConnectParams 3>$null 4>$null 5>$null 6>$null | Out-Null
            Invoke-MOCPostInteractiveAuthRedraw -OutputBuffer $AuthOutput -ScriptName $AuthScriptName -Status 'Running'
            if (-not [string]::IsNullOrWhiteSpace([string]$script:MOC_DesiredSubscriptionId)) {
                Set-AzContext -SubscriptionId $script:MOC_DesiredSubscriptionId -TenantId $script:MOC_TenantId -ErrorAction Stop -WarningAction SilentlyContinue -InformationAction SilentlyContinue | Out-Null
            }
            Add-MOCAuthLine -Line 'Azure session connected.' -Percent 25 -Activity 'Azure Session' -Status 'Running' -Operation 'Azure context ready'
        }
        else {
            Add-MOCAuthLine -Line 'Azure session already connected.' -Percent 22 -Activity 'Azure Session' -Status 'Running' -Operation 'Validating Azure subscription context'
            try {
                if (-not [string]::IsNullOrWhiteSpace([string]$script:MOC_DesiredSubscriptionId)) {
                    Set-AzContext -SubscriptionId $script:MOC_DesiredSubscriptionId -TenantId $script:MOC_TenantId -ErrorAction Stop -WarningAction SilentlyContinue -InformationAction SilentlyContinue | Out-Null
                    Add-MOCAuthLine -Line 'Azure subscription context validated.' -Percent 25 -Activity 'Azure Session' -Status 'Running' -Operation 'Azure context ready'
                }
                else {
                    Add-MOCAuthLine -Line 'Azure session tenant validated. No subscription context was configured.' -Percent 25 -Activity 'Azure Session' -Status 'Running' -Operation 'Azure context ready'
                }
            }
            catch {
                Add-MOCAuthLine -Line "WARNING: Existing Azure session could not set the MOC subscription context. $($_.Exception.Message)" -Percent 25 -Activity 'Azure Session' -Status 'Running' -Operation 'Continuing with current Azure context'
            }
        }

        Add-MOCAuthLine -Line 'Retrieving Microsoft Graph client secret from Azure Key Vault...' -Percent 30 -Activity 'Azure Key Vault' -Status 'Running' -Operation 'Reading MOC Graph client secret'
        try {
            $SecretValue = Get-AzKeyVaultSecret -VaultName $script:MOC_KeyVaultName -Name $script:MOC_SecretName -AsPlainText -WarningAction SilentlyContinue -ErrorAction Stop
        }
        catch {
            $KeyVaultErrorMessage = [string]$_.Exception.Message
            $RequiresKeyVaultAuthScope = (
                $KeyVaultErrorMessage -match 'AzureKeyVaultServiceEndpointResourceId' -or
                $KeyVaultErrorMessage -match 'Azure credentials have not been set up or have expired' -or
                $KeyVaultErrorMessage -match 'User interaction is required' -or
                $KeyVaultErrorMessage -match 'Connect-AzAccount'
            )

            if (-not $RequiresKeyVaultAuthScope) { throw }

            Add-MOCAuthLine -Line 'Azure Key Vault access requires interactive Azure reauthentication.' -Percent 32 -Activity 'Azure Key Vault' -Status 'Running' -Operation 'Key Vault scoped authentication required'
            Add-MOCAuthLine -Line 'Reconnecting Azure with Key Vault auth scope...' -Percent 34 -Activity 'Azure Key Vault' -Status 'Running' -Operation 'Interactive Azure authentication'

            try {
                $AzKeyVaultConnectParams = @{
                    TenantId    = $script:MOC_TenantId
                    AuthScope   = 'AzureKeyVaultServiceEndpointResourceId'
                    ErrorAction = 'Stop'
                }
                if (-not [string]::IsNullOrWhiteSpace([string]$script:MOC_DesiredSubscriptionId)) {
                    $AzKeyVaultConnectParams['SubscriptionId'] = $script:MOC_DesiredSubscriptionId
                }
                Add-MOCQuietAuthParameters -CommandName 'Connect-AzAccount' -Parameters $AzKeyVaultConnectParams
                Add-MOCAuthLine -Line 'If prompted, complete the Azure Key Vault sign-in flow. MOC will redraw after authentication returns.' -Percent 35 -Activity 'Azure Key Vault' -Status 'Running' -Operation 'Waiting for Key Vault auth'
                Add-MOCAuthLine -Line 'If no sign-in window appears within a few seconds, check the browser or existing Az session window.' -Percent 35 -Activity 'Azure Key Vault' -Status 'Running' -Operation 'Waiting for Key Vault auth'
                Invoke-MOCPostInteractiveAuthRedraw -OutputBuffer $AuthOutput -ScriptName $AuthScriptName -Status 'Running'
                Connect-AzAccount @AzKeyVaultConnectParams 3>$null 4>$null 5>$null 6>$null | Out-Null
                Invoke-MOCPostInteractiveAuthRedraw -OutputBuffer $AuthOutput -ScriptName $AuthScriptName -Status 'Running'
            }
            catch {
                Add-MOCAuthLine -Line "WARNING: Key Vault scoped Azure authentication failed. Retrying standard Azure authentication. $($_.Exception.Message)" -Percent 36 -Activity 'Azure Key Vault' -Status 'Running' -Operation 'Retrying standard Azure authentication'
                $AzConnectParams = @{
                    TenantId    = $script:MOC_TenantId
                    ErrorAction = 'Stop'
                }
                if (-not [string]::IsNullOrWhiteSpace([string]$script:MOC_DesiredSubscriptionId)) {
                    $AzConnectParams['SubscriptionId'] = $script:MOC_DesiredSubscriptionId
                }
            Add-MOCQuietAuthParameters -CommandName 'Connect-AzAccount' -Parameters $AzConnectParams
            Add-MOCAuthLine -Line 'If prompted, complete the Azure sign-in flow. MOC will redraw after authentication returns.' -Percent 19 -Activity 'Azure Session' -Status 'Running' -Operation 'Waiting for Azure sign-in'
            Add-MOCAuthLine -Line 'If no sign-in window appears within a few seconds, check the browser or existing Az session window.' -Percent 19 -Activity 'Azure Session' -Status 'Running' -Operation 'Waiting for Azure sign-in'
            Invoke-MOCPostInteractiveAuthRedraw -OutputBuffer $AuthOutput -ScriptName $AuthScriptName -Status 'Running'
            Connect-AzAccount @AzConnectParams 3>$null 4>$null 5>$null 6>$null | Out-Null
            Invoke-MOCPostInteractiveAuthRedraw -OutputBuffer $AuthOutput -ScriptName $AuthScriptName -Status 'Running'
            }

            if (-not [string]::IsNullOrWhiteSpace([string]$script:MOC_DesiredSubscriptionId)) {
                Set-AzContext -SubscriptionId $script:MOC_DesiredSubscriptionId -TenantId $script:MOC_TenantId -ErrorAction Stop -WarningAction SilentlyContinue -InformationAction SilentlyContinue | Out-Null
            }
            $SecretValue = Get-AzKeyVaultSecret -VaultName $script:MOC_KeyVaultName -Name $script:MOC_SecretName -AsPlainText -WarningAction SilentlyContinue -ErrorAction Stop
        }

        Add-MOCAuthLine -Line 'Microsoft Graph client secret retrieved from Azure Key Vault.' -Percent 40 -Activity 'Microsoft Graph' -Status 'Running' -Operation 'Preparing Graph app-only token'

        $MgContext = Get-MgContext -ErrorAction SilentlyContinue
        $ExistingGraphContextMatches = (
            $null -ne $MgContext -and
            [string]$MgContext.TenantId -eq [string]$script:MOC_TenantId -and
            (
                [string]::IsNullOrWhiteSpace([string]$MgContext.ClientId) -or
                [string]$MgContext.ClientId -eq [string]$script:MOC_ClientId
            )
        )

        if ($ForceRefresh) {
            if ($null -ne $MgContext) {
                Add-MOCAuthLine -Line 'Refreshing Microsoft Graph access token...' -Percent 44 -Activity 'Microsoft Graph' -Status 'Running' -Operation 'Disconnecting old Graph context'
                try { Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null } catch {}
            }
            $ExistingGraphContextMatches = $false
        }
        elseif ($ExistingGraphContextMatches -and (Test-MOCGraphAccessTokenRefreshNeeded)) {
            Add-MOCAuthLine -Line 'Microsoft Graph access token is near expiration. Refreshing token...' -Percent 44 -Activity 'Microsoft Graph' -Status 'Running' -Operation 'Disconnecting old Graph context'
            try { Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null } catch {}
            $ExistingGraphContextMatches = $false
        }

        if (-not $ExistingGraphContextMatches) {
            Add-MOCAuthLine -Line 'Requesting fresh Microsoft Graph access token...' -Percent 48 -Activity 'Microsoft Graph' -Status 'Running' -Operation 'Requesting app-only token from Entra ID'

            # Do not use Connect-MgGraph -ClientSecretCredential here.
            # In mixed Az + Microsoft.Graph sessions, older identity assemblies can already be loaded,
            # which can produce ClientSecretCredential/MSAL method-not-found errors such as:
            # BaseAbstractApplicationBuilder.WithLogging(IIdentityLogger, Boolean).
            # Request the Graph app-only token directly, then give that token to Microsoft.Graph.
            $TokenUri = "https://login.microsoftonline.com/$($script:MOC_TenantId)/oauth2/v2.0/token"
            $TokenBody = @{
                client_id     = $script:MOC_ClientId
                client_secret = $SecretValue
                scope         = 'https://graph.microsoft.com/.default'
                grant_type    = 'client_credentials'
            }

            try {
                $TokenResponse = Invoke-RestMethod -Method Post -Uri $TokenUri -Body $TokenBody -ContentType 'application/x-www-form-urlencoded' -ErrorAction Stop
            }
            catch {
                throw "Microsoft Graph token request failed. $($_.Exception.Message)"
            }

            if ($null -eq $TokenResponse -or [string]::IsNullOrWhiteSpace([string]$TokenResponse.access_token)) {
                throw 'Microsoft Graph token request did not return an access token.'
            }

            try {
                $script:MOC_GraphTokenAcquiredUtc = (Get-Date).ToUniversalTime()
                if ($TokenResponse.expires_in) {
                    $script:MOC_GraphTokenExpiresUtc = $script:MOC_GraphTokenAcquiredUtc.AddSeconds([int]$TokenResponse.expires_in)
                }
                else {
                    $script:MOC_GraphTokenExpiresUtc = $script:MOC_GraphTokenAcquiredUtc.AddMinutes(55)
                }
            }
            catch {
                $script:MOC_GraphTokenAcquiredUtc = $null
                $script:MOC_GraphTokenExpiresUtc = $null
            }

            Add-MOCAuthLine -Line 'Connecting to Microsoft Graph...' -Percent 55 -Activity 'Microsoft Graph' -Status 'Running' -Operation 'Connecting Graph PowerShell with access token'
            try {
                $SecureGraphAccessToken = ConvertTo-SecureString ([string]$TokenResponse.access_token) -AsPlainText -Force
                Connect-MgGraph -AccessToken $SecureGraphAccessToken -NoWelcome -ErrorAction Stop | Out-Null
            }
            catch {
                try {
                    Connect-MgGraph -AccessToken ([string]$TokenResponse.access_token) -NoWelcome -ErrorAction Stop | Out-Null
                }
                catch {
                    throw "Microsoft Graph access-token connection failed. $($_.Exception.Message)"
                }
            }
        }
        else {
            Add-MOCAuthLine -Line 'Microsoft Graph session already connected.' -Percent 55 -Activity 'Microsoft Graph' -Status 'Running' -Operation 'Existing Graph context is reusable'
        }

        $MgContext = Get-MgContext -ErrorAction SilentlyContinue
        if ($null -eq $MgContext -or [string]::IsNullOrWhiteSpace([string]$MgContext.TenantId)) {
            throw 'Microsoft Graph authentication did not produce a usable parent context.'
        }
        $script:MOC_GraphConnected = $true
        $script:MOC_GraphTenantId = [string]$MgContext.TenantId
        if (-not [string]::IsNullOrWhiteSpace([string]$MgContext.ClientId)) {
            $script:MOC_GraphClientId = [string]$MgContext.ClientId
        }
        else {
            $script:MOC_GraphClientId = [string]$script:MOC_ClientId
        }

        Add-MOCAuthLine -Line 'Microsoft Graph connected.' -Percent 62 -Activity 'Microsoft Graph' -Status 'Running' -Operation 'Retrieving organization name'
        Add-MOCAuthLine -Line 'Retrieving organization name from Microsoft Entra ID...' -Percent 65 -Activity 'Microsoft Graph' -Status 'Running' -Operation 'Reading tenant organization display name'
        Update-MOCOrganizationName
        if (-not [string]::IsNullOrWhiteSpace($script:MOC_OrganizationName)) {
            Add-MOCAuthLine -Line ("Organization: {0}" -f $script:MOC_OrganizationName) -Percent 68 -Activity 'Microsoft Graph' -Status 'Running' -Operation 'Organization context ready'
        }

        if (-not (Test-MOCExchangeSession)) {
            Add-MOCAuthLine -Line 'Connecting to Exchange Online...' -Percent 74 -Activity 'Exchange Online' -Status 'Running' -Operation 'Connecting Exchange Online PowerShell'
            $ExchangeConnectParams = @{
                ShowBanner        = $false
                ErrorAction       = 'Stop'
                WarningAction     = 'SilentlyContinue'
                InformationAction = 'SilentlyContinue'
            }
            Add-MOCQuietAuthParameters -CommandName 'Connect-ExchangeOnline' -Parameters $ExchangeConnectParams
            Connect-ExchangeOnline @ExchangeConnectParams 3>$null 4>$null 5>$null 6>$null
            if (-not (Test-MOCExchangeSession)) {
                throw 'Exchange Online authentication completed, but the limited HelpDesk validation did not find an active connection.'
            }
            Add-MOCAuthLine -Line 'Exchange Online session connected. Limited HelpDesk validation passed.' -Percent 82 -Activity 'Exchange Online' -Status 'Running' -Operation 'Exchange Online session ready'
        }
        else {
            Add-MOCAuthLine -Line 'Exchange Online session already connected. Limited HelpDesk validation passed.' -Percent 82 -Activity 'Exchange Online' -Status 'Running' -Operation 'Exchange Online session ready'
        }

        # Microsoft Purview / Security & Compliance is intentionally lazy-loaded.
        # HelpDesk-MOC skips Purview during A: Auth because the current approved HelpDesk
        # scripts do not require it. If a future allowed HelpDesk script requires Purview,
        # MOC will connect the prefixed search-only session immediately before that script runs.
        Add-MOCAuthLine -Line 'Skipping Microsoft Purview during A: Auth. Purview will be lazy-loaded only when a child script requires it.' -Percent 96 -Activity 'Microsoft Purview' -Status 'Running' -Operation 'Purview lazy-loaded'

        Set-MOCHeaderUserFromAuthenticatedContext
        $script:MOC_Authenticated = $true
        $script:MOC_LastStatus = 'Connected'
        Add-MOCAuthLine -Line 'SUCCESS: MOC shared authentication session is ready.' -Percent 100 -Activity 'Authentication Session' -Status 'Completed' -Operation 'Core parent-owned sessions are ready'
        Complete-MOCAuthPane -Status 'Completed' -Percent 100 -Activity 'Authentication Session' -Message 'Press Enter to return to MOC.'
        Wait-MOCAuthPaneReview -Status 'Completed'
        $script:MOC_View = $PriorMOCView
        $script:MOC_CurrentFolder = $PriorMOCCurrentFolder
        Hide-MOCCursor
    }
    catch {
        $script:MOC_Authenticated = $false
        Reset-MOCHeaderUserToLocalSession
        $script:MOC_OrganizationName = ''
        $script:MOC_LastStatus = 'Auth failed - press A to retry'

        $AuthMessage = [string]$_.Exception.Message
        if ([string]::IsNullOrWhiteSpace($AuthMessage)) { $AuthMessage = [string]$_ }

        Add-MOCAuthLine -Line ("ERROR: Authentication failed. {0}" -f $AuthMessage) -Percent 100 -Activity 'Authentication Session' -Status 'Failed' -Operation 'Authentication failed'
        Complete-MOCAuthPane -Status 'Failed' -Percent 100 -Activity 'Authentication Session' -Message 'Press Enter to return to MOC, then press A to authenticate again.'
        Wait-MOCAuthPaneReview -Status 'Failed'
        $script:MOC_View = $PriorMOCView
        $script:MOC_CurrentFolder = $PriorMOCCurrentFolder
        Hide-MOCCursor
        throw
    }
}

function Show-MOCQuitConfirmation {
    [CmdletBinding()]
    param()

    $PreviousStatus = $script:MOC_LastStatus
    $script:MOC_LastStatus = 'Confirm quit'

    function Write-MOCQuitModalLine {
        param(
            [string]$Text = '',
            [int]$Width = (Get-TerminalWidth),
            [string]$Color = $script:Ansi.Reset
        )

        $InnerWidth = [Math]::Max(1, $Width - 4)
        $Text = Truncate-Text -Text $Text -MaxLength $InnerWidth
        Write-Color ("│ " + $Text.PadRight($InnerWidth) + " │") $Color
    }

    function Render-MOCQuitModal {
        Invoke-MOCHardClearHost
        Write-Header
        Write-Breadcrumb

        $Width = Get-TerminalWidth
        Write-Color ("┌" + (New-Line -Width ($Width - 2)) + "┐") $script:Ansi.Yellow
        Write-MOCQuitModalLine -Text 'Confirm Quit' -Width $Width -Color "$($script:Ansi.Bold)$($script:Ansi.Yellow)"
        Write-Color ("├" + (New-Line -Width ($Width - 2)) + "┤") $script:Ansi.Yellow
        Write-MOCQuitModalLine -Text 'Quit MOC and disconnect shared sessions?' -Width $Width -Color $script:Ansi.White
        Write-MOCQuitModalLine -Text '' -Width $Width -Color $script:Ansi.White
        Write-MOCQuitModalLine -Text 'This will terminate parent-owned MOC sessions for:' -Width $Width -Color $script:Ansi.White
        Write-MOCQuitModalLine -Text '  - Microsoft Graph' -Width $Width -Color $script:Ansi.Gray
        Write-MOCQuitModalLine -Text '  - Exchange Online' -Width $Width -Color $script:Ansi.Gray
        Write-MOCQuitModalLine -Text '  - Microsoft Purview / Security & Compliance' -Width $Width -Color $script:Ansi.Gray
        Write-MOCQuitModalLine -Text '  - Azure / Az context used by MOC' -Width $Width -Color $script:Ansi.Gray
        Write-MOCQuitModalLine -Text '' -Width $Width -Color $script:Ansi.White
        Write-MOCQuitModalLine -Text 'Y / Enter  Quit and disconnect' -Width $Width -Color $script:Ansi.Green
        Write-MOCQuitModalLine -Text 'N / Esc / Backspace  Cancel and return to MOC' -Width $Width -Color $script:Ansi.Gray
        Write-Color ("└" + (New-Line -Width ($Width - 2)) + "┘") $script:Ansi.Yellow
        Write-Color ''
        Write-Color ("┌" + (New-Line -Width ($Width - 2)) + "┐") $script:Ansi.Gray
        Write-PanelLine -Text 'Status: CONFIRM QUIT | Y/Enter disconnects | N/Esc/Backspace cancels' -Width $Width -Color $script:Ansi.Yellow
        Write-Color ("└" + (New-Line -Width ($Width - 2)) + "┘") $script:Ansi.Gray
        Complete-MOCFrameRender
    }

    Render-MOCQuitModal

    while ($true) {
        $key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        Hide-MOCCursor

        if ($key.VirtualKeyCode -eq 13 -or $key.Character -match '[Yy]') {
            $script:MOC_LastStatus = 'Disconnecting'
            return $true
        }

        if ($key.VirtualKeyCode -eq 27 -or $key.VirtualKeyCode -eq 8 -or $key.Character -match '[NnQq]') {
            $script:MOC_LastStatus = $PreviousStatus
            return $false
        }
    }
}

function Disconnect-MOCSharedSession {
    [CmdletBinding()]
    param()

    Invoke-MOCHardClearHost
    $script:MOC_LastStatus = 'Disconnecting'
    Write-Header
    Write-Color 'Home > Quit' $script:Ansi.Green
    Write-Color ''
    $Width = Get-TerminalWidth
    Write-MOCBorderLine -Kind Top -Width $Width -Color $script:MOC_BorderSecondary
    Write-PanelLine -Text 'Disconnecting MOC Shared Sessions' -Width $Width -Color "$($script:Ansi.Bold)$($script:Ansi.Cyan)"
    Write-MOCBorderLine -Kind Middle -Width $Width -Color $script:MOC_BorderSecondary
    Write-PanelLine -Text 'Disconnecting parent-owned Microsoft 365 sessions...' -Width $Width -Color $script:Ansi.White
    Write-PanelLine -Text 'Session output is shown below. MOC will exit when disconnect is complete.' -Width $Width -Color $script:Ansi.Gray
    Write-MOCBorderLine -Kind Bottom -Width $Width -Color $script:MOC_BorderSecondary
    Write-Color ''

    if (-not $script:MOC_Authenticated) {
        Write-Color 'No active MOC shared authentication session was marked as connected.' $script:Ansi.Gray
    }

    Write-Color 'Disconnecting Exchange Online session...' $script:Ansi.Cyan
    try {
        Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
        Write-Color 'Exchange Online disconnected or no active session was present.' $script:Ansi.Green
    }
    catch {
        Write-Color ("Exchange Online disconnect warning: {0}" -f $_.Exception.Message) $script:Ansi.Yellow
    }

    Write-Color 'Disconnecting Microsoft Graph session...' $script:Ansi.Cyan
    try {
        Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
        Write-Color 'Microsoft Graph disconnected or no active session was present.' $script:Ansi.Green
    }
    catch {
        Write-Color ("Microsoft Graph disconnect warning: {0}" -f $_.Exception.Message) $script:Ansi.Yellow
    }

    Write-Color 'Disconnecting Azure / Az context...' $script:Ansi.Cyan
    try {
        Disconnect-AzAccount -ErrorAction SilentlyContinue | Out-Null
        Write-Color 'Azure / Az disconnected or no active context was present.' $script:Ansi.Green
    }
    catch {
        Write-Color ("Azure disconnect warning: {0}" -f $_.Exception.Message) $script:Ansi.Yellow
    }

    $script:MOC_Authenticated = $false
    Reset-MOCHeaderUserToLocalSession
    $script:MOC_OrganizationName = ''
    $script:MOC_GraphConnected = $false
    $script:MOC_GraphTenantId = ''
    $script:MOC_GraphClientId = ''
    $script:MOC_LastStatus = 'Disconnected'

    Write-Color ''
    Write-Color 'MOC shared sessions have been disconnected. Exiting MOC.' $script:Ansi.Green
    Complete-MOCFrameRender
}

# ------------------------------------------------------------
# Discover scripts
# ------------------------------------------------------------

function Remove-MOCUpdateStagingDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [object]$OutputBuffer = $null
    )

    if ([string]::IsNullOrWhiteSpace([string]$script:MOC_RootPath)) { return }

    $StageRoot = Join-Path $script:MOC_RootPath '.MOC-Update-Staging'
    if (-not (Test-Path -LiteralPath $StageRoot)) { return }

    try {
        Remove-Item -LiteralPath $StageRoot -Recurse -Force -ErrorAction Stop
        if ($null -ne $OutputBuffer -and (Get-Command Add-RunConsoleLine -ErrorAction SilentlyContinue)) {
            Add-RunConsoleLine -OutputBuffer $OutputBuffer -Line 'Cleaned temporary MOC update staging folder.'
        }
    }
    catch {
        if ($null -ne $OutputBuffer -and (Get-Command Add-RunConsoleLine -ErrorAction SilentlyContinue)) {
            Add-RunConsoleLine -OutputBuffer $OutputBuffer -Line ('WARNING: Could not clean temporary MOC update staging folder: {0}' -f $_.Exception.Message)
        }
    }
}

function Get-MOCScripts {
    $items = @()

    $AllowedPatterns = @($script:MOC_AllowedChildScriptNamePatterns | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $ExcludedNames = @('menu.ps1', 'MOC.ps1', 'HelpDesk-MOC.ps1')
    if ($script:MOC_UpdateChildScriptExcludeNames) {
        $ExcludedNames += @($script:MOC_UpdateChildScriptExcludeNames | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }
    $ExcludedNames = @($ExcludedNames | Select-Object -Unique)

    Get-ChildItem -Path $RootPath -Filter *.ps1 -File -Recurse -ErrorAction SilentlyContinue |
    Where-Object {
        $ScriptFile = $_
        $RelativePath = try {
            [System.IO.Path]::GetRelativePath($RootPath, $ScriptFile.FullName)
        }
        catch {
            $ScriptFile.Name
        }

        if ($ScriptFile.Name -in $ExcludedNames) { return $false }
        if ($ScriptFile.Name -notmatch '\.ps1$') { return $false }
        if ($ScriptFile.Name -notmatch '\(\d+\)\.ps1$') {
            # Continue below.
        }
        else {
            return $false
        }

        $RelativeDirectory = Split-Path -Path $RelativePath -Parent
        if ([string]::IsNullOrWhiteSpace($RelativeDirectory)) {
            # Keep the launcher root clean. Child scripts should live in a folder.
            return $false
        }

        $Segments = @($RelativeDirectory -split '[\\/]')
        foreach ($Segment in $Segments) {
            if ($HiddenMenuFolders -contains $Segment) { return $false }
            if ($Segment.StartsWith('.')) { return $false }
        }

        if ($AllowedPatterns.Count -eq 0) {
            return $true
        }

        foreach ($Pattern in $AllowedPatterns) {
            if ($ScriptFile.Name -like $Pattern) { return $true }
            if ($RelativePath -like $Pattern) { return $true }
        }

        return $false
    } |
    Sort-Object FullName |
    ForEach-Object {
        $RelativePath = try {
            [System.IO.Path]::GetRelativePath($RootPath, $_.FullName)
        }
        catch {
            $_.Name
        }
        $RelativeDirectory = Split-Path -Path $RelativePath -Parent
        $FolderName = if ([string]::IsNullOrWhiteSpace($RelativeDirectory)) { 'Root' } else { $RelativeDirectory -replace '\\', '/' }

        $meta = Get-MOCScriptMetadata -Path $_.FullName
        $items += [pscustomobject]@{
            Folder      = $FolderName
            Name        = $_.Name
            Path        = $_.FullName
            Version     = $meta.Version
            Synopsis    = $meta.Synopsis
            Description = $meta.Description
            Author      = $meta.Author
            Category    = $meta.Category
            Created     = $meta.Created
            LastModified = $meta.LastModified
            OutputFormat = $meta.OutputFormat
            RequiredGraphAppScopes = @($meta.RequiredGraphAppScopes)
            RequiredPowerShellModules = @($meta.RequiredPowerShellModules)
        }
    }

    return $items
}
function Get-MOCFolders {
    param([object[]]$Scripts)

    return @(
        $Scripts |
        Group-Object Folder |
        Sort-Object Name |
        ForEach-Object {
            [pscustomobject]@{
                Name = $_.Name
                Count = $_.Count
            }
        }
    )
}

function Get-CurrentScripts {
    if ($script:MOC_View -eq 'Home') { return @() }
    return @($Scripts | Where-Object { $_.Folder -eq $script:MOC_CurrentFolder } | Sort-Object Name)
}

# ------------------------------------------------------------
# Renderers
# ------------------------------------------------------------
function Write-HomeMenu {
    param([object[]]$Folders, [int]$Index, [string]$NumberBuffer)

    $Width = Get-TerminalWidth
    Write-MOCBorderLine -Kind Top -Width $Width -Color $script:MOC_BorderPrimary
    Write-PanelLine -BorderColor $script:MOC_BorderPrimary -Text ("Folders discovered: {0}" -f $Folders.Count) -Width $Width -Color $script:Ansi.Blue
    Write-MOCBorderLine -Kind Middle -Width $Width -Color $script:MOC_BorderPrimary

    $MinimumMenuRows = if ([int]$script:MOC_MenuMinRows -gt 0) { [int]$script:MOC_MenuMinRows } else { 6 }
    $DisplayRows = [Math]::Min([Math]::Max([int]$Folders.Count, $MinimumMenuRows), [int]$script:MOC_PageSize)

    for ($i = 0; $i -lt $Folders.Count; $i++) {
        $Prefix = if ($i -eq $Index) { '  >' } else { '   ' }
        $Line = "{0} [{1}] {2} ({3})" -f $Prefix, ($i + 1), $Folders[$i].Name, $Folders[$i].Count

        if ($i -eq $Index) {
            Write-PanelLine -BorderColor $script:MOC_BorderPrimary -Text $Line -Width $Width -Color "$($script:Ansi.Bold)$($script:Ansi.Green)"
        }
        else {
            Write-PanelLine -BorderColor $script:MOC_BorderPrimary -Text $Line -Width $Width -Color $script:Ansi.White
        }
    }

    $RowsRendered = [Math]::Min([int]$Folders.Count, [int]$DisplayRows)
    for ($pad = $RowsRendered; $pad -lt $DisplayRows; $pad++) {
        Write-PanelLine -BorderColor $script:MOC_BorderPrimary -Text '' -Width $Width -Color $script:Ansi.White
    }

    Write-MOCBorderLine -Kind Bottom -Width $Width -Color $script:MOC_BorderPrimary

    if ($NumberBuffer) {
        Write-Color "Jump to #: $NumberBuffer  (Enter to confirm)" $script:Ansi.Yellow
    }
}

function Write-ScriptMenu {
    param([object[]]$FolderScripts, [int]$Index, [string]$NumberBuffer)

    $Width = Get-TerminalWidth
    $PageSize = $script:MOC_PageSize
    $MinimumMenuRows = if ([int]$script:MOC_MenuMinRows -gt 0) { [int]$script:MOC_MenuMinRows } else { 6 }
    $Page = [Math]::Floor($Index / $PageSize)
    $TotalPages = [Math]::Max(1, [Math]::Ceiling($FolderScripts.Count / $PageSize))
    $Start = $Page * $PageSize
    $End = [Math]::Min($FolderScripts.Count - 1, $Start + $PageSize - 1)

    Write-MOCBorderLine -Kind Top -Width $Width -Color $script:MOC_BorderPrimary
    Write-PanelLine -BorderColor $script:MOC_BorderPrimary -Text ("Scripts in {0}: {1}  |  Page {2} of {3}" -f $script:MOC_CurrentFolder, $FolderScripts.Count, ($Page + 1), $TotalPages) -Width $Width -Color $script:Ansi.Blue
    Write-MOCBorderLine -Kind Middle -Width $Width -Color $script:MOC_BorderPrimary

    for ($i = $Start; $i -le $End; $i++) {
        $Prefix = if ($i -eq $Index) { '  >' } else { '   ' }
        $VersionText = if ($FolderScripts[$i].Version -and $FolderScripts[$i].Version -ne 'Unknown') { "v$($FolderScripts[$i].Version)" } else { 'vUnknown' }
        $Line = "{0} [{1}] {2}  ({3})" -f $Prefix, ($i + 1), $FolderScripts[$i].Name, $VersionText

        if ($i -eq $Index) {
            Write-PanelLine -BorderColor $script:MOC_BorderPrimary -Text $Line -Width $Width -Color "$($script:Ansi.Bold)$($script:Ansi.Green)"
        }
        else {
            Write-PanelLine -BorderColor $script:MOC_BorderPrimary -Text $Line -Width $Width -Color $script:Ansi.White
        }
    }

    $RowsShown = if ($FolderScripts.Count -eq 0) { 0 } else { $End - $Start + 1 }
    $DisplayRows = [Math]::Min([Math]::Max([int]$RowsShown, $MinimumMenuRows), [int]$PageSize)

    for ($pad = $RowsShown; $pad -lt $DisplayRows; $pad++) {
        Write-PanelLine -BorderColor $script:MOC_BorderPrimary -Text '' -Width $Width -Color $script:Ansi.White
    }

    Write-MOCBorderLine -Kind Bottom -Width $Width -Color $script:MOC_BorderPrimary

    if ($NumberBuffer) {
        Write-Color "Jump to #: $NumberBuffer  (Enter to confirm)" $script:Ansi.Yellow
    }
}

function Write-DetailsPane {
    param([pscustomobject]$Item)

    $Width = Get-TerminalWidth
    $InnerWidth = [Math]::Max(1, $Width - 4)

    Write-MOCBorderLine -Kind Top -Width $Width -Color $script:MOC_BorderSecondary

    if ($script:MOC_View -eq 'Home') {
        Write-PanelLine -BorderColor $script:MOC_BorderSecondary -Text 'Selected Folder Details' -Width $Width -Color "$($script:Ansi.Bold)$($script:Ansi.Cyan)"
        Write-MOCBorderLine -Kind Middle -Width $Width -Color $script:MOC_BorderSecondary
        Write-PanelLine -BorderColor $script:MOC_BorderSecondary -Text ("Folder:  {0}" -f $Item.Name) -Width $Width -Color $script:Ansi.White
        Write-PanelLine -BorderColor $script:MOC_BorderSecondary -Text ("Scripts: {0}" -f $Item.Count) -Width $Width -Color $script:Ansi.White
        Write-PanelLine -BorderColor $script:MOC_BorderSecondary -Text 'Press Enter to open this folder.' -Width $Width -Color $script:Ansi.Gray
        $BlankRows = Get-MOCDynamicPaneBlankRows -MinimumRows $(if (Test-MOCCompactLayout) { 2 } else { 4 }) -ReservedRows 1
        for ($i = 0; $i -lt $BlankRows; $i++) { Write-PanelLine -BorderColor $script:MOC_BorderSecondary -Text '' -Width $Width -Color $script:Ansi.White }
    }
    else {
        # Description rows are rendered with a two-space indent below. Wrap to the
        # remaining visible width before adding that indent so Write-PanelLine does
        # not have to truncate the final word at the right pane edge.
        $DescriptionIndent = '  '
        $DescriptionWrapWidth = [Math]::Max(1, $InnerWidth - $DescriptionIndent.Length)
        $DescriptionLines = Wrap-Text -Text $Item.Description -Width $DescriptionWrapWidth -MaxLines 8
        Write-PanelLine -BorderColor $script:MOC_BorderSecondary -Text 'Selected Script Details' -Width $Width -Color "$($script:Ansi.Bold)$($script:Ansi.Cyan)"
        Write-MOCBorderLine -Kind Middle -Width $Width -Color $script:MOC_BorderSecondary
        Write-PanelLine -BorderColor $script:MOC_BorderSecondary -Text ("Name:    {0}" -f $Item.Name) -Width $Width -Color $script:Ansi.White
        Write-PanelLine -BorderColor $script:MOC_BorderSecondary -Text ("Version: {0}" -f $Item.Version) -Width $Width -Color $script:Ansi.White
        Write-PanelLine -BorderColor $script:MOC_BorderSecondary -Text ("Folder:  {0}" -f $Item.Folder) -Width $Width -Color $script:Ansi.Gray
        if ($Item.PSObject.Properties.Name -contains 'OutputFormat' -and -not [string]::IsNullOrWhiteSpace([string]$Item.OutputFormat)) {
            Write-PanelLine -BorderColor $script:MOC_BorderSecondary -Text ("Output:  {0}" -f $Item.OutputFormat) -Width $Width -Color $script:Ansi.Gray
        }
        $GraphScopes = @($Item.RequiredGraphAppScopes)
        $GraphScopeText = if ($GraphScopes.Count -gt 0) { $GraphScopes -join ', ' } else { 'None' }
        Write-PanelLine -BorderColor $script:MOC_BorderSecondary -Text ("Graph app permissions: {0}" -f $GraphScopeText) -Width $Width -Color $script:Ansi.Gray
        $RequiredModules = @()
        if ($Item.PSObject.Properties.Name -contains 'RequiredPowerShellModules') { $RequiredModules = @($Item.RequiredPowerShellModules) }
        $RequiredModuleText = if ($RequiredModules.Count -gt 0) { $RequiredModules -join ', ' } else { 'None' }
        Write-PanelLine -BorderColor $script:MOC_BorderSecondary -Text ("PowerShell modules: {0}" -f $RequiredModuleText) -Width $Width -Color $script:Ansi.Gray
        Write-PanelLine -BorderColor $script:MOC_BorderSecondary -Text 'Description:' -Width $Width -Color $script:Ansi.Yellow

        foreach ($Line in $DescriptionLines) {
            Write-PanelLine -BorderColor $script:MOC_BorderSecondary -Text ("{0}{1}" -f $DescriptionIndent, $Line) -Width $Width -Color $script:Ansi.White
        }

        $TargetDescriptionRows = if (Test-MOCCompactLayout) { 3 } else { 7 }
        for ($i = $DescriptionLines.Count; $i -lt $TargetDescriptionRows; $i++) {
            Write-PanelLine -BorderColor $script:MOC_BorderSecondary -Text '' -Width $Width -Color $script:Ansi.White
        }

        $ExtraBlankRows = Get-MOCDynamicPaneBlankRows -MinimumRows 0 -ReservedRows 1
        for ($i = 0; $i -lt $ExtraBlankRows; $i++) {
            Write-PanelLine -BorderColor $script:MOC_BorderSecondary -Text '' -Width $Width -Color $script:Ansi.White
        }
    }

    Write-MOCBorderLine -Kind Bottom -Width $Width -Color $script:MOC_BorderSecondary
}



function New-MOCProgressBarText {
    param(
        [Parameter(Mandatory = $false)]
        [int]$PercentComplete = 0,

        [Parameter(Mandatory = $false)]
        [int]$Width = 34
    )

    if ($PercentComplete -lt 0) { $PercentComplete = 0 }
    if ($PercentComplete -gt 100) { $PercentComplete = 100 }
    if ($Width -lt 10) { $Width = 10 }

    $Filled = [Math]::Round(($PercentComplete / 100) * $Width, 0)
    if ($Filled -lt 0) { $Filled = 0 }
    if ($Filled -gt $Width) { $Filled = $Width }
    $Empty = $Width - $Filled

    return (('█' * $Filled) + ('░' * $Empty))
}

function Write-RunConsoleProgressPanel {
    param(
        [Parameter(Mandatory = $false)]
        [int]$Width = (Get-TerminalWidth),

        [Parameter(Mandatory = $false)]
        [string]$Status = 'Running',

        [Parameter(Mandatory = $false)]
        [string]$BorderColor = $script:MOC_BorderPrimary
    )

    $Percent = 0
    if ($null -ne $script:MOC_RunConsole_ProgressPercent) {
        $Percent = [int]$script:MOC_RunConsole_ProgressPercent
    }
    if ($Percent -lt 0) { $Percent = 0 }
    if ($Percent -gt 100) { $Percent = 100 }

    $Activity = if ([string]::IsNullOrWhiteSpace($script:MOC_RunConsole_ProgressActivity)) { 'Script Progress' } else { [string]$script:MOC_RunConsole_ProgressActivity }
    $ProgressStatus = if ([string]::IsNullOrWhiteSpace($script:MOC_RunConsole_ProgressStatus)) { $Status } else { [string]$script:MOC_RunConsole_ProgressStatus }
    $Operation = if ([string]::IsNullOrWhiteSpace($script:MOC_RunConsole_ProgressOperation)) { '' } else { [string]$script:MOC_RunConsole_ProgressOperation }

    $BarWidth = [Math]::Min(44, [Math]::Max(18, $Width - 76))
    $Bar = New-MOCProgressBarText -PercentComplete $Percent -Width $BarWidth
    $PercentText = ('{0,5:N1}%' -f ([double]$Percent))

    Write-PanelLine -BorderColor $BorderColor -Text $Activity -Width $Width -Color "$($script:Ansi.Bold)$($script:Ansi.Green)"
    Write-PanelLine -BorderColor $BorderColor -Text ('  {0}  {1}' -f $Bar, $PercentText) -Width $Width -Color $script:Ansi.Green

    # For final states, keep the progress area clean. The action guidance is now
    # rendered once in the bottom footer by Write-RunConsoleFrame.
    if ($Status -match '^(Completed|Failed)$') {
        Write-PanelLine -BorderColor $BorderColor -Text '' -Width $Width -Color $script:Ansi.Gray
        return
    }

    if (-not [string]::IsNullOrWhiteSpace($ProgressStatus)) {
        Write-PanelLine -BorderColor $BorderColor -Text ('+ {0}' -f $ProgressStatus) -Width $Width -Color $script:Ansi.White
    }
    else {
        Write-PanelLine -BorderColor $BorderColor -Text '' -Width $Width -Color $script:Ansi.Gray
    }

    if (-not [string]::IsNullOrWhiteSpace($Operation)) {
        Write-PanelLine -BorderColor $BorderColor -Text ('  {0}' -f $Operation) -Width $Width -Color "$($script:Ansi.Bold)$($script:Ansi.Yellow)"
    }
}


function Get-MOCOutputLevelColor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [string]$Level = 'Info'
    )

    switch ([string]$Level) {
        'Success'  { return "$($script:Ansi.Bold)$($script:Ansi.Green)" }
        'Warning'  { return "$($script:Ansi.Bold)$($script:Ansi.Yellow)" }
        'Error'    { return "$($script:Ansi.Bold)$($script:Ansi.Red)" }
        'Critical' { return "$($script:Ansi.Bold)$($script:Ansi.Red)" }
        'Action'   { return "$($script:Ansi.Bold)$($script:Ansi.Cyan)" }
        'Prompt'   { return "$($script:Ansi.Bold)$($script:Ansi.Cyan)" }
        'Header'   { return "$($script:Ansi.Bold)$($script:Ansi.Blue)" }
        'Muted'    { return $script:Ansi.Gray }
        default    { return $script:Ansi.White }
    }
}

function New-MOCOutputLineWithLevel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [string]$Line = '',

        [ValidateSet('Info','Success','Warning','Error','Critical','Action','Prompt','Header','Muted')]
        [string]$Level = 'Info'
    )

    if ([string]::IsNullOrWhiteSpace($Level) -or $Level -eq 'Info') {
        return [string]$Line
    }

    return ('[[MOCLEVEL:{0}]]{1}' -f $Level, [string]$Line)
}

function Get-MOCOutputLineLevel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [string]$Line = ''
    )

    if ([string]::IsNullOrEmpty($Line)) { return '' }
    if ($Line -match '^\[\[MOCLEVEL:(Info|Success|Warning|Error|Critical|Action|Prompt|Header|Muted)\]\]') {
        return [string]$Matches[1]
    }
    return ''
}

function Remove-MOCOutputLineLevelMarker {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [string]$Line = ''
    )

    if ([string]::IsNullOrEmpty($Line)) { return '' }
    return ([string]$Line -replace '^\[\[MOCLEVEL:(Info|Success|Warning|Error|Critical|Action|Prompt|Header|Muted)\]\]', '')
}

function ConvertTo-MOCGraphDriveRelativePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $Segments = @($Path -split '/' | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    $EncodedSegments = foreach ($Segment in $Segments) {
        [System.Uri]::EscapeDataString([string]$Segment)
    }
    return ($EncodedSegments -join '/')
}

function Get-MOCVersionObject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [string]$VersionText
    )

    if ([string]::IsNullOrWhiteSpace($VersionText)) { return $null }
    try { return [version]$VersionText }
    catch {
        try { return [version](($VersionText -replace '[^0-9.]', '').Trim('.')) }
        catch { return $null }
    }
}

function Add-MOCSelfUpdateLine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[string]]$OutputBuffer,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [string]$Line,

        [Parameter(Mandatory = $false)]
        [double]$Percent = -1,

        [Parameter(Mandatory = $false)]
        [string]$Status = 'Running',

        [Parameter(Mandatory = $false)]
        [string]$Operation = ''
    )

    if ($Percent -ge 0) { $script:MOC_RunConsole_ProgressPercent = [double]$Percent }
    $script:MOC_RunConsole_ProgressActivity = 'MOC Self Update'
    $script:MOC_RunConsole_ProgressStatus = $Status
    $script:MOC_RunConsole_ProgressOperation = $Operation

    if ($PSBoundParameters.ContainsKey('Line')) {
        Add-RunConsoleLine -OutputBuffer $OutputBuffer -Line $Line
    }

    $ScrollOffset = Get-MOCRunConsoleScrollMaxOffset -OutputBuffer $OutputBuffer
    Write-RunConsoleFrame -ScriptName 'MOC Self Update' -OutputBuffer $OutputBuffer -ScrollOffset $ScrollOffset -Status $Status -FooterView 'RunConsole'
}


function Read-MOCSelfUpdateYesNoPrompt {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[string]]$OutputBuffer,

        [Parameter(Mandatory = $true)]
        [string]$Prompt,

        [Parameter(Mandatory = $false)]
        [string]$Help = 'Y: Yes   N: No   PgUp/PgDn: Review output',

        [Parameter(Mandatory = $false)]
        [string]$Status = 'Running'
    )

    $PreviousInputRequired = $script:MOC_RunConsole_InputRequired
    $PreviousInputPrompt = $script:MOC_RunConsole_InputPrompt
    $PreviousInputValue = $script:MOC_RunConsole_InputValue
    $PreviousInputHelp = $script:MOC_RunConsole_InputHelp
    $PreviousInputPreviewLines = $script:MOC_RunConsole_InputPreviewLines

    try {
        $script:MOC_RunConsole_InputRequired = $true
        $script:MOC_RunConsole_InputPrompt = $Prompt
        $script:MOC_RunConsole_InputValue = ''
        $script:MOC_RunConsole_InputHelp = $Help
        $script:MOC_RunConsole_InputPreviewLines = @()

        while ($true) {
            $Offset = if ($null -ne $script:MOC_RunConsole_UserScrollOffset) { [int]$script:MOC_RunConsole_UserScrollOffset } else { Get-MOCRunConsoleScrollMaxOffset -OutputBuffer $OutputBuffer }
            Write-RunConsoleFrame -ScriptName 'MOC Update' -OutputBuffer $OutputBuffer -ScrollOffset $Offset -Status $Status -FooterView 'RunConsole'

            try { $KeyInfo = [System.Console]::ReadKey($true) }
            catch {
                $Fallback = Read-Host $Prompt
                return ($Fallback -match '^(?i:y|yes)$')
            }

            if (Move-MOCRunConsoleScrollOffset -KeyInfo $KeyInfo -OutputBuffer $OutputBuffer) {
                if ($null -eq $script:MOC_RunConsole_UserScrollOffset) {
                    $script:MOC_RunConsole_InputHelp = 'Auto-follow resumed. Y: Yes   N: No'
                }
                else {
                    $script:MOC_RunConsole_InputHelp = 'Reviewing output. PgUp/PgDn page, Up/Down scroll, End resumes latest output. Y: Yes   N: No'
                }
                continue
            }

            $Char = [string]$KeyInfo.KeyChar
            if ($KeyInfo.Key -eq [System.ConsoleKey]::Y -or $Char -match '^(?i)y$') {
                $script:MOC_RunConsole_InputValue = 'Y'
                Write-RunConsoleFrame -ScriptName 'MOC Update' -OutputBuffer $OutputBuffer -ScrollOffset (Get-MOCRunConsoleScrollMaxOffset -OutputBuffer $OutputBuffer) -Status $Status -FooterView 'RunConsole'
                return $true
            }
            if ($KeyInfo.Key -eq [System.ConsoleKey]::N -or $Char -match '^(?i)n$') {
                $script:MOC_RunConsole_InputValue = 'N'
                Write-RunConsoleFrame -ScriptName 'MOC Update' -OutputBuffer $OutputBuffer -ScrollOffset (Get-MOCRunConsoleScrollMaxOffset -OutputBuffer $OutputBuffer) -Status $Status -FooterView 'RunConsole'
                return $false
            }
        }
    }
    finally {
        $script:MOC_RunConsole_InputRequired = $PreviousInputRequired
        $script:MOC_RunConsole_InputPrompt = $PreviousInputPrompt
        $script:MOC_RunConsole_InputValue = $PreviousInputValue
        $script:MOC_RunConsole_InputHelp = $PreviousInputHelp
        $script:MOC_RunConsole_InputPreviewLines = $PreviousInputPreviewLines
    }
}


function Get-MOCGraphRequestStatusFromError {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$ErrorRecord
    )

    $Message = ''
    try { $Message = [string]$ErrorRecord.Exception.Message } catch { $Message = [string]$ErrorRecord }

    try {
        $Response = $ErrorRecord.Exception.Response
        if ($null -ne $Response -and $null -ne $Response.StatusCode) {
            $Status = [string]$Response.StatusCode
            if (-not [string]::IsNullOrWhiteSpace($Status)) { return $Status }
        }
    }
    catch {}

    if ($Message -match '(?i)Unauthorized|\b401\b') { return 'Unauthorized' }
    if ($Message -match '(?i)Forbidden|\b403\b') { return 'Forbidden' }
    if ($Message -match '(?i)NotFound|Not Found|\b404\b') { return 'NotFound' }
    if ($Message -match '(?i)BadRequest|Bad Request|\b400\b') { return 'BadRequest' }
    return 'Unknown'
}

function Add-MOCSelfUpdateSharePointAuthorizationGuidance {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$Operation = 'access the SharePoint update source',

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$Status = 'Unauthorized',

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$Uri = ''
    )

    if ([bool]$script:MOC_SelfUpdateGraphAuthorizationGuidanceShown) { return }
    $script:MOC_SelfUpdateGraphAuthorizationGuidanceShown = $true

    $OutputBuffer = $script:MOC_SelfUpdateOutputBuffer
    if ($null -eq $OutputBuffer) { $OutputBuffer = [System.Collections.Generic.List[string]]::new() }

    Add-RunConsoleLine -OutputBuffer $OutputBuffer -Line ('ERROR: SharePoint update access failed while attempting to {0}. Microsoft Graph returned {1}.' -f $Operation, $Status)
    Add-RunConsoleLine -OutputBuffer $OutputBuffer -Line 'What this means: U: Update is using the configured Microsoft Graph app-only token for the menu app registration.'
    Add-RunConsoleLine -OutputBuffer $OutputBuffer -Line 'Delegated Sites.Read.All alone is not enough for this app-only update flow.'
    Add-RunConsoleLine -OutputBuffer $OutputBuffer -Line 'Fix option 1: Add Microsoft Graph APPLICATION permission Sites.Read.All to the menu app registration, then grant admin consent.'
    Add-RunConsoleLine -OutputBuffer $OutputBuffer -Line 'Fix option 2: Use Microsoft Graph APPLICATION permission Sites.Selected, grant admin consent, then grant the app read access to the configured SharePoint site.'
    Add-RunConsoleLine -OutputBuffer $OutputBuffer -Line ('Configured SharePoint source: {0}{1} / {2} / {3}' -f $script:MOC_UpdateSiteHostname, $script:MOC_UpdateSitePath, $script:MOC_UpdateDriveName, $script:MOC_UpdateItemPath)
    if (-not [string]::IsNullOrWhiteSpace($Uri)) {
        Add-RunConsoleLine -OutputBuffer $OutputBuffer -Line ('Graph request: {0}' -f $Uri)
    }
    Add-RunConsoleLine -OutputBuffer $OutputBuffer -Line 'After changing API permissions or site grants, press A: Auth again so MOC receives a fresh Graph token, then retry U: Update.'

    $script:MOC_RunConsole_ProgressPercent = 100
    $script:MOC_RunConsole_ProgressActivity = 'MOC Update'
    $script:MOC_RunConsole_ProgressStatus = 'Failed'
    $script:MOC_RunConsole_ProgressOperation = 'SharePoint update access is not authorized'
    try {
        Write-RunConsoleFrame -ScriptName 'MOC Update' -OutputBuffer $OutputBuffer -ScrollOffset (Get-MOCRunConsoleScrollMaxOffset -OutputBuffer $OutputBuffer) -Status 'Failed' -FooterView 'RunConsole'
    }
    catch {}
}

function Invoke-MOCSelfUpdateGraphRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Method,

        [Parameter(Mandatory = $true)]
        [string]$Uri,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$Operation = 'access the SharePoint update source',

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$OutputFilePath = ''
    )

    try {
        if ($PSBoundParameters.ContainsKey('OutputFilePath') -and -not [string]::IsNullOrWhiteSpace($OutputFilePath)) {
            return (Invoke-MgGraphRequest -Method $Method -Uri $Uri -OutputFilePath $OutputFilePath -ErrorAction Stop)
        }
        return (Invoke-MgGraphRequest -Method $Method -Uri $Uri -ErrorAction Stop)
    }
    catch {
        $Status = Get-MOCGraphRequestStatusFromError -ErrorRecord $_
        if ($Status -in @('Unauthorized', 'Forbidden')) {
            Add-MOCSelfUpdateSharePointAuthorizationGuidance -Operation $Operation -Status $Status -Uri $Uri
            throw 'SharePoint self-update could not access the configured update source. Review the permission guidance above.'
        }
        throw
    }
}

function Get-MOCGraphPagedValues {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri
    )

    $Values = @()
    $NextUri = $Uri
    while (-not [string]::IsNullOrWhiteSpace($NextUri)) {
        $Page = Invoke-MOCSelfUpdateGraphRequest -Method GET -Uri $NextUri -Operation 'list SharePoint update folder contents'
        if ($null -ne $Page.value) { $Values += @($Page.value) }
        $NextUri = [string]$Page.'@odata.nextLink'
    }
    return @($Values)
}

function Get-MOCGraphDriveChildrenRecursive {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DriveId,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$FolderPath = '',

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$RelativeRoot = ''
    )

    $EncodedFolderPath = ConvertTo-MOCGraphDriveRelativePath -Path $FolderPath
    if ([string]::IsNullOrWhiteSpace($EncodedFolderPath)) {
        $ChildrenUri = 'https://graph.microsoft.com/v1.0/drives/{0}/root/children' -f $DriveId
    }
    else {
        $ChildrenUri = 'https://graph.microsoft.com/v1.0/drives/{0}/root:/{1}:/children' -f $DriveId, $EncodedFolderPath
    }

    $Items = Get-MOCGraphPagedValues -Uri $ChildrenUri
    $Results = @()
    foreach ($Item in @($Items)) {
        $Name = [string]$Item.name
        if ([string]::IsNullOrWhiteSpace($Name)) { continue }

        $RelativePath = if ([string]::IsNullOrWhiteSpace($RelativeRoot)) { $Name } else { '{0}/{1}' -f $RelativeRoot.Trim('/'), $Name }
        $RemotePath = if ([string]::IsNullOrWhiteSpace($FolderPath)) { $Name } else { '{0}/{1}' -f $FolderPath.Trim('/'), $Name }

        if ($null -ne $Item.folder) {
            if ([bool]$script:MOC_UpdateChildScriptsRecursive) {
                $Results += @(Get-MOCGraphDriveChildrenRecursive -DriveId $DriveId -FolderPath $RemotePath -RelativeRoot $RelativePath)
            }
            continue
        }

        $Results += [pscustomobject]@{
            Item         = $Item
            Name         = $Name
            RelativePath = $RelativePath
            RemotePath   = $RemotePath
        }
    }
    return @($Results)
}

function Save-MOCGraphDriveItemToPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DriveId,

        [Parameter(Mandatory = $true)]
        [object]$Item,

        [Parameter(Mandatory = $true)]
        [string]$DestinationPath
    )

    $Parent = Split-Path -Path $DestinationPath -Parent
    if (-not [string]::IsNullOrWhiteSpace($Parent) -and -not (Test-Path -LiteralPath $Parent)) {
        New-Item -ItemType Directory -Path $Parent -Force | Out-Null
    }

    $DownloadUrl = [string]$Item.'@microsoft.graph.downloadUrl'
    if (-not [string]::IsNullOrWhiteSpace($DownloadUrl)) {
        Invoke-WebRequest -Uri $DownloadUrl -OutFile $DestinationPath -UseBasicParsing -ErrorAction Stop | Out-Null
    }
    else {
        $ContentUri = 'https://graph.microsoft.com/v1.0/drives/{0}/items/{1}/content' -f $DriveId, $Item.id
        Invoke-MOCSelfUpdateGraphRequest -Method GET -Uri $ContentUri -Operation 'download SharePoint update file' -OutputFilePath $DestinationPath | Out-Null
    }
}

function Get-MOCMenuUpdateFolderPath {
    [CmdletBinding()]
    param()

    $ItemPath = [string]$script:MOC_UpdateItemPath
    if (-not [string]::IsNullOrWhiteSpace($ItemPath)) {
        $NormalizedItemPath = $ItemPath.Replace('\\', '/').Trim('/')
        $LastSlash = $NormalizedItemPath.LastIndexOf('/')
        if ($LastSlash -gt 0) {
            return $NormalizedItemPath.Substring(0, $LastSlash).Trim('/')
        }
    }

    $FolderPath = [string]$script:MOC_UpdateFolderPath
    if (-not [string]::IsNullOrWhiteSpace($FolderPath)) {
        return $FolderPath.Replace('\\', '/').Trim('/')
    }

    return ''
}

function Invoke-MOCChangelogUpdate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[string]]$OutputBuffer,

        [Parameter(Mandatory = $true)]
        [object]$Drive,

        [Parameter(Mandatory = $true)]
        [string]$StageRoot,

        [Parameter(Mandatory = $true)]
        [string]$BackupRoot
    )

    $ChangelogFileName = [string]$script:MOC_UpdateChangelogFileName
    if ([string]::IsNullOrWhiteSpace($ChangelogFileName)) { $ChangelogFileName = 'CHANGELOG.md' }

    $RemoteFolderPath = Get-MOCMenuUpdateFolderPath
    $RemoteChangelogPath = if ([string]::IsNullOrWhiteSpace($RemoteFolderPath)) {
        $ChangelogFileName
    }
    else {
        '{0}/{1}' -f $RemoteFolderPath.Trim('/'), $ChangelogFileName
    }

    $Summary = [ordered]@{
        Checked   = 1
        Updated   = 0
        Installed = 0
        Skipped   = 0
        Failed    = 0
    }

    Add-MOCSelfUpdateLine -OutputBuffer $OutputBuffer -Line ('Checking changelog file: {0}' -f $RemoteChangelogPath) -Percent 84 -Status 'Running' -Operation 'Checking changelog'

    try {
        $EncodedDrivePath = ConvertTo-MOCGraphDriveRelativePath -Path $RemoteChangelogPath
        $RemoteItemUri = 'https://graph.microsoft.com/v1.0/drives/{0}/root:/{1}' -f $Drive.id, $EncodedDrivePath
        $RemoteItem = Invoke-MOCSelfUpdateGraphRequest -Method GET -Uri $RemoteItemUri -Operation 'read the remote CHANGELOG.md metadata'
        if ($null -eq $RemoteItem -or [string]::IsNullOrWhiteSpace([string]$RemoteItem.id)) {
            Add-RunConsoleLine -OutputBuffer $OutputBuffer -Line ('WARNING: Remote CHANGELOG.md was not found at {0}. Changelog update skipped.' -f $RemoteChangelogPath)
            $Summary.Skipped = 1
            return [pscustomobject]$Summary
        }

        $ChangelogStageRoot = Join-Path $StageRoot 'Changelog'
        if (-not (Test-Path -LiteralPath $ChangelogStageRoot)) { New-Item -ItemType Directory -Path $ChangelogStageRoot -Force | Out-Null }
        $StagePath = Join-Path $ChangelogStageRoot ('{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), $ChangelogFileName)

        Save-MOCGraphDriveItemToPath -DriveId ([string]$Drive.id) -Item $RemoteItem -DestinationPath $StagePath
        if (-not (Test-Path -LiteralPath $StagePath) -or (Get-Item -LiteralPath $StagePath).Length -lt 1) {
            Add-RunConsoleLine -OutputBuffer $OutputBuffer -Line ('WARNING: Downloaded CHANGELOG.md was missing or empty. Changelog update skipped: {0}' -f $RemoteChangelogPath)
            $Summary.Skipped = 1
            return [pscustomobject]$Summary
        }

        $LocalChangelogPath = Join-Path $script:MOC_RootPath $ChangelogFileName
        $LocalExists = Test-Path -LiteralPath $LocalChangelogPath -PathType Leaf
        if ($LocalExists) {
            try {
                $LocalHash = (Get-FileHash -LiteralPath $LocalChangelogPath -Algorithm SHA256 -ErrorAction Stop).Hash
                $RemoteHash = (Get-FileHash -LiteralPath $StagePath -Algorithm SHA256 -ErrorAction Stop).Hash
                if ($LocalHash -eq $RemoteHash) {
                    Add-RunConsoleLine -OutputBuffer $OutputBuffer -Line ('OK: {0} is current.' -f $ChangelogFileName)
                    $Summary.Skipped = 1
                    return [pscustomobject]$Summary
                }
            }
            catch {
                Add-RunConsoleLine -OutputBuffer $OutputBuffer -Line ('WARNING: Could not compare existing {0}; it will be refreshed. {1}' -f $ChangelogFileName, $_.Exception.Message)
            }

            $BackupName = ('{0}.{1}.bak' -f $ChangelogFileName, (Get-Date -Format 'yyyyMMdd-HHmmss'))
            $BackupPath = Join-Path $BackupRoot $BackupName
            Copy-Item -LiteralPath $LocalChangelogPath -Destination $BackupPath -Force -ErrorAction Stop
        }

        Copy-Item -LiteralPath $StagePath -Destination $LocalChangelogPath -Force -ErrorAction Stop
        if ($LocalExists) {
            Add-RunConsoleLine -OutputBuffer $OutputBuffer -Line ('UPDATED: {0} from SharePoint.' -f $ChangelogFileName)
            $Summary.Updated = 1
        }
        else {
            Add-RunConsoleLine -OutputBuffer $OutputBuffer -Line ('INSTALLED: {0} from SharePoint.' -f $ChangelogFileName)
            $Summary.Installed = 1
        }
    }
    catch {
        $Status = Get-MOCGraphRequestStatusFromError -ErrorRecord $_
        if ($Status -eq 'NotFound') {
            Add-RunConsoleLine -OutputBuffer $OutputBuffer -Line ('WARNING: Remote CHANGELOG.md was not found at {0}. Changelog update skipped.' -f $RemoteChangelogPath)
            $Summary.Skipped = 1
            return [pscustomobject]$Summary
        }
        Add-RunConsoleLine -OutputBuffer $OutputBuffer -Line ('WARNING: Changelog update failed and was skipped: {0}' -f $_.Exception.Message)
        $Summary.Failed = 1
    }

    return [pscustomobject]$Summary
}


function Unblock-MOCDownloadedScriptFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[string]]$OutputBuffer,

        [Parameter(Mandatory = $false)]
        [string]$DisplayName = ''
    )

    if (-not [bool]$script:MOC_UpdateUnblockDownloadedFiles) { return }
    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }

    $Extension = [System.IO.Path]::GetExtension($Path)
    if ($Extension -notin @('.ps1', '.psm1', '.psd1')) { return }

    $NameForLog = if ([string]::IsNullOrWhiteSpace($DisplayName)) { Split-Path -Leaf $Path } else { $DisplayName }

    if ($IsLinux) {
        if ($null -ne $OutputBuffer) {
            Add-RunConsoleLine -OutputBuffer $OutputBuffer -Line ("Linux detected; no Windows security-zone unblock required for: {0}" -f $NameForLog)
        }
        return
    }

    if ($IsWindows -or $IsMacOS) {
        try {
            Unblock-File -LiteralPath $Path -ErrorAction Stop
            if ($null -ne $OutputBuffer) {
                Add-RunConsoleLine -OutputBuffer $OutputBuffer -Line ("Unblocked downloaded script file: {0}" -f $NameForLog)
            }
        }
        catch {
            if ($null -ne $OutputBuffer) {
                Add-RunConsoleLine -OutputBuffer $OutputBuffer -Line ("WARNING: Could not unblock downloaded script file: {0}. {1}" -f $NameForLog, $_.Exception.Message)
            }
        }
    }
}

function Test-MOCPowerShellFileSyntax {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $false)]
        [ref]$ParseErrors
    )

    $Tokens = $null
    $Errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$Tokens, [ref]$Errors) | Out-Null
    if ($null -ne $ParseErrors) { $ParseErrors.Value = $Errors }
    return ($null -eq $Errors -or @($Errors).Count -eq 0)
}

function ConvertTo-MOCLocalChildScriptPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RelativePath
    )

    $SafeRelative = ([string]$RelativePath).Trim('/').Replace('/', [System.IO.Path]::DirectorySeparatorChar)
    return (Join-Path $script:MOC_RootPath $SafeRelative)
}


function Get-MOCChildScriptUpdateRootCandidates {
    [CmdletBinding()]
    param()

    $Candidates = New-Object System.Collections.Generic.List[string]

    foreach ($Candidate in @(
        [string]$script:MOC_UpdateChildScriptsRootPath,
        [string]$script:MOC_UpdateFolderPath
    )) {
        if ([string]::IsNullOrWhiteSpace($Candidate)) { continue }
        $CleanCandidate = $Candidate.Replace('\\', '/').Trim('/')
        if ([string]::IsNullOrWhiteSpace($CleanCandidate)) { continue }
        if (-not $Candidates.Contains($CleanCandidate)) { [void]$Candidates.Add($CleanCandidate) }
    }

    $ItemPath = [string]$script:MOC_UpdateItemPath
    if (-not [string]::IsNullOrWhiteSpace($ItemPath)) {
        $NormalizedItemPath = $ItemPath.Replace('\\', '/').Trim('/')
        $LastSlash = $NormalizedItemPath.LastIndexOf('/')
        if ($LastSlash -gt 0) {
            $ParentPath = $NormalizedItemPath.Substring(0, $LastSlash).Trim('/')
            if (-not [string]::IsNullOrWhiteSpace($ParentPath) -and -not $Candidates.Contains($ParentPath)) {
                [void]$Candidates.Add($ParentPath)
            }
        }
    }

    return @($Candidates)
}

function Invoke-MOCChildScriptUpdates {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[string]]$OutputBuffer,

        [Parameter(Mandatory = $true)]
        [object]$Drive,

        [Parameter(Mandatory = $true)]
        [string]$StageRoot,

        [Parameter(Mandatory = $true)]
        [string]$BackupRoot
    )

    if (-not [bool]$script:MOC_UpdateChildScriptsEnabled) {
        Add-MOCSelfUpdateLine -OutputBuffer $OutputBuffer -Line 'Child-script update check is disabled in configuration.' -Percent 92 -Status 'Running' -Operation 'Skipping child scripts'
        return [pscustomobject]@{ Checked = 0; Updated = 0; Installed = 0; Skipped = 0; Failed = 0 }
    }

    $ChildRootCandidates = @(Get-MOCChildScriptUpdateRootCandidates)
    if (@($ChildRootCandidates).Count -eq 0) {
        Add-MOCSelfUpdateLine -OutputBuffer $OutputBuffer -Line 'WARNING: No child-script SharePoint update root is configured. Skipping child-script updates.' -Percent 92 -Status 'Running' -Operation 'Skipping child scripts'
        return [pscustomobject]@{ Checked = 0; Updated = 0; Installed = 0; Skipped = 0; Failed = 0 }
    }

    $RemoteFiles = @()
    $ResolvedChildRoot = ''
    $LastChildRootError = $null

    foreach ($ChildRootCandidate in @($ChildRootCandidates)) {
        $ChildRoot = [string]$ChildRootCandidate
        Add-MOCSelfUpdateLine -OutputBuffer $OutputBuffer -Line ('Checking child scripts under SharePoint path: {0}' -f $ChildRoot) -Percent 88 -Status 'Running' -Operation 'Scanning child scripts'

        try {
            $RemoteFiles = @(Get-MOCGraphDriveChildrenRecursive -DriveId ([string]$Drive.id) -FolderPath $ChildRoot)
            $ResolvedChildRoot = $ChildRoot
            break
        }
        catch {
            $LastChildRootError = $_
            $Status = Get-MOCGraphRequestStatusFromError -ErrorRecord $_
            if ($Status -eq 'NotFound') {
                Add-RunConsoleLine -OutputBuffer $OutputBuffer -Line ('WARNING: Configured child-script update path was not found: {0}' -f $ChildRoot)
                continue
            }
            throw
        }
    }

    if ([string]::IsNullOrWhiteSpace($ResolvedChildRoot)) {
        Add-MOCSelfUpdateLine -OutputBuffer $OutputBuffer -Line 'WARNING: None of the configured child-script SharePoint update paths were found. Menu update check completed, but child-script updates were skipped.' -Percent 95 -Status 'Running' -Operation 'Child scripts skipped'
        foreach ($Candidate in @($ChildRootCandidates)) {
            Add-RunConsoleLine -OutputBuffer $OutputBuffer -Line ('  Missing path checked: {0}' -f [string]$Candidate)
        }
        Add-RunConsoleLine -OutputBuffer $OutputBuffer -Line 'Update the local configuration field "Child-script update root" or create the matching SharePoint folder, then run U: Update again.'
        return [pscustomobject]@{ Checked = 0; Updated = 0; Installed = 0; Skipped = 0; Failed = 0 }
    }

    if (@($ChildRootCandidates).Count -gt 1 -and ([string]$ChildRootCandidates[0]) -ne $ResolvedChildRoot) {
        Add-RunConsoleLine -OutputBuffer $OutputBuffer -Line ('INFO: Child-script update scan recovered by using fallback path: {0}' -f $ResolvedChildRoot)
    }
    $IncludePattern = if ([string]::IsNullOrWhiteSpace([string]$script:MOC_UpdateChildScriptIncludePattern)) { '*.ps1' } else { [string]$script:MOC_UpdateChildScriptIncludePattern }
    $ExcludeNames = @($script:MOC_UpdateChildScriptExcludeNames | ForEach-Object { [string]$_ })

    $RemoteScripts = @(
        $RemoteFiles |
        Where-Object { $_.Name -like $IncludePattern } |
        Where-Object { $_.Name -notin $ExcludeNames }
    )

    $AllowedUpdatePatterns = @($script:MOC_UpdateChildScriptAllowedNamePatterns | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($AllowedUpdatePatterns.Count -gt 0) {
        $RemoteScripts = @(
            $RemoteScripts | Where-Object {
                $RemoteScriptName = [string]$_.Name
                $Matched = $false
                foreach ($Pattern in $AllowedUpdatePatterns) {
                    if ($RemoteScriptName -like $Pattern) { $Matched = $true; break }
                }
                $Matched
            }
        )
    }

    if (@($RemoteScripts).Count -eq 0) {
        Add-MOCSelfUpdateLine -OutputBuffer $OutputBuffer -Line 'No remote child scripts were found for update comparison.' -Percent 95 -Status 'Running' -Operation 'Child scripts checked'
        return [pscustomobject]@{ Checked = 0; Updated = 0; Installed = 0; Skipped = 0; Failed = 0 }
    }

    $RemoteScripts = @($RemoteScripts | Sort-Object RelativePath)
    $MissingRemoteScripts = @(
        $RemoteScripts | Where-Object {
            $LocalPathForCheck = ConvertTo-MOCLocalChildScriptPath -RelativePath ([string]$_.RelativePath)
            -not (Test-Path -LiteralPath $LocalPathForCheck)
        }
    )

    $InstallMissingScripts = [bool]$script:MOC_UpdateChildScriptsCreateMissing
    if (@($MissingRemoteScripts).Count -gt 0) {
        Add-MOCSelfUpdateLine -OutputBuffer $OutputBuffer -Line 'New child scripts were found:' -Percent 90 -Status 'Running' -Operation 'Confirm missing child scripts'
        foreach ($MissingScript in @($MissingRemoteScripts)) {
            Add-RunConsoleLine -OutputBuffer $OutputBuffer -Line ('  {0}' -f [string]$MissingScript.RelativePath)
        }

        if ($InstallMissingScripts) {
            Add-RunConsoleLine -OutputBuffer $OutputBuffer -Line 'Configuration allows missing child scripts to be installed automatically.'
        }
        else {
            $InstallMissingScripts = Read-MOCSelfUpdateYesNoPrompt -OutputBuffer $OutputBuffer -Prompt 'Install missing scripts? Y/N' -Help 'Y: Install missing scripts and folders   N: Skip missing scripts   PgUp/PgDn: Review output' -Status 'Running'
            if ($InstallMissingScripts) {
                Add-RunConsoleLine -OutputBuffer $OutputBuffer -Line 'CONFIRMED: Missing child scripts will be installed.'
            }
            else {
                Add-RunConsoleLine -OutputBuffer $OutputBuffer -Line 'SKIP: Missing child scripts will not be installed.'
            }
        }
    }

    $Checked = 0
    $Updated = 0
    $Installed = 0
    $Skipped = 0
    $Failed = 0
    $ChildStageRoot = Join-Path $StageRoot 'ChildScripts'
    if (-not (Test-Path -LiteralPath $ChildStageRoot)) { New-Item -ItemType Directory -Path $ChildStageRoot -Force | Out-Null }

    foreach ($RemoteScript in @($RemoteScripts)) {
        $Checked++
        $RelativePath = [string]$RemoteScript.RelativePath
        $LocalPath = ConvertTo-MOCLocalChildScriptPath -RelativePath $RelativePath
        $LocalExists = Test-Path -LiteralPath $LocalPath
        $Progress = [Math]::Min(98, 88 + [int](($Checked / [Math]::Max(1, @($RemoteScripts).Count)) * 9))

        Add-MOCSelfUpdateLine -OutputBuffer $OutputBuffer -Line ('Child script: {0}' -f $RelativePath) -Percent $Progress -Status 'Running' -Operation 'Comparing child scripts'

        if (-not $LocalExists -and -not $InstallMissingScripts) {
            Add-RunConsoleLine -OutputBuffer $OutputBuffer -Line ('SKIP: Local child script is missing and was not approved for installation: {0}' -f $RelativePath)
            $Skipped++
            continue
        }

        $SafeStageName = (($RelativePath -replace '[\/]+', '__') -replace '[^A-Za-z0-9._-]', '_')
        $StagePath = Join-Path $ChildStageRoot ('{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), $SafeStageName)

        try {
            Save-MOCGraphDriveItemToPath -DriveId ([string]$Drive.id) -Item $RemoteScript.Item -DestinationPath $StagePath
            Unblock-MOCDownloadedScriptFile -Path $StagePath -OutputBuffer $OutputBuffer -DisplayName $RelativePath
            if (-not (Test-Path -LiteralPath $StagePath) -or (Get-Item -LiteralPath $StagePath).Length -lt 64) {
                Add-RunConsoleLine -OutputBuffer $OutputBuffer -Line ('ERROR: Downloaded child script was missing or unexpectedly small: {0}' -f $RelativePath)
                $Failed++
                continue
            }

            $RemoteMetadata = Get-MOCScriptMetadata -Path $StagePath
            $RemoteVersion = Get-MOCVersionObject -VersionText ([string]$RemoteMetadata.Version)
            if ($null -eq $RemoteVersion) {
                Add-RunConsoleLine -OutputBuffer $OutputBuffer -Line ('SKIP: Remote child script does not contain a valid .VERSION value: {0}' -f $RelativePath)
                $Skipped++
                continue
            }

            $LocalVersion = $null
            if ($LocalExists) {
                $LocalMetadata = Get-MOCScriptMetadata -Path $LocalPath
                $LocalVersion = Get-MOCVersionObject -VersionText ([string]$LocalMetadata.Version)
            }

            if ($LocalExists -and $null -ne $LocalVersion -and $RemoteVersion -le $LocalVersion) {
                Add-RunConsoleLine -OutputBuffer $OutputBuffer -Line ('OK: {0} is current. Local v{1}; remote v{2}.' -f $RelativePath, $LocalVersion, $RemoteMetadata.Version)
                $Skipped++
                continue
            }

            $ParseErrors = $null
            if (-not (Test-MOCPowerShellFileSyntax -Path $StagePath -ParseErrors ([ref]$ParseErrors))) {
                Add-RunConsoleLine -OutputBuffer $OutputBuffer -Line ('ERROR: Parser validation failed for remote child script: {0}' -f $RelativePath)
                foreach ($ParseError in @($ParseErrors | Select-Object -First 3)) {
                    Add-RunConsoleLine -OutputBuffer $OutputBuffer -Line ('Line {0}, Column {1}: {2}' -f $ParseError.Extent.StartLineNumber, $ParseError.Extent.StartColumnNumber, $ParseError.Message)
                }
                $Failed++
                continue
            }

            if ($LocalExists) {
                $BackupName = ('child-{0}.{1}.bak' -f (($RelativePath -replace '[\/]+', '__') -replace '[^A-Za-z0-9._-]', '_'), (Get-Date -Format 'yyyyMMdd-HHmmss'))
                $BackupPath = Join-Path $BackupRoot $BackupName
                Copy-Item -LiteralPath $LocalPath -Destination $BackupPath -Force -ErrorAction Stop
            }
            else {
                $LocalParent = Split-Path -Path $LocalPath -Parent
                if (-not (Test-Path -LiteralPath $LocalParent)) { New-Item -ItemType Directory -Path $LocalParent -Force | Out-Null }
            }

            Copy-Item -LiteralPath $StagePath -Destination $LocalPath -Force -ErrorAction Stop
            Unblock-MOCDownloadedScriptFile -Path $LocalPath -OutputBuffer $OutputBuffer -DisplayName $RelativePath
            if ($LocalExists) {
                Add-RunConsoleLine -OutputBuffer $OutputBuffer -Line ('UPDATED: {0} to v{1}.' -f $RelativePath, $RemoteMetadata.Version)
                $Updated++
            }
            else {
                Add-RunConsoleLine -OutputBuffer $OutputBuffer -Line ('INSTALLED: {0} v{1}.' -f $RelativePath, $RemoteMetadata.Version)
                $Installed++
            }
        }
        catch {
            Add-RunConsoleLine -OutputBuffer $OutputBuffer -Line ('ERROR: Child script update failed for {0}: {1}' -f $RelativePath, $_.Exception.Message)
            $Failed++
        }
    }

    return [pscustomobject]@{
        Checked   = $Checked
        Updated   = $Updated
        Installed = $Installed
        Skipped   = $Skipped
        Failed    = $Failed
    }
}


function Get-MOCRelaunchPowerShellPath {
    [CmdletBinding()]
    param()

    try {
        $CurrentProcessPath = [string](Get-Process -Id $PID -ErrorAction Stop).Path
        if (-not [string]::IsNullOrWhiteSpace($CurrentProcessPath) -and (Test-Path -LiteralPath $CurrentProcessPath)) {
            return $CurrentProcessPath
        }
    }
    catch {}

    $PreferredName = if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh' } else { 'powershell' }
    foreach ($Name in @($PreferredName, 'pwsh', 'powershell')) {
        try {
            $Command = Get-Command $Name -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($null -ne $Command) {
                if (-not [string]::IsNullOrWhiteSpace([string]$Command.Source) -and (Test-Path -LiteralPath ([string]$Command.Source))) { return [string]$Command.Source }
                if (-not [string]::IsNullOrWhiteSpace([string]$Command.Path) -and (Test-Path -LiteralPath ([string]$Command.Path))) { return [string]$Command.Path }
            }
        }
        catch {}
    }

    return $null
}

function Start-MOCMenuRelaunchProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptPath
    )

    if ([string]::IsNullOrWhiteSpace($ScriptPath) -or -not (Test-Path -LiteralPath $ScriptPath)) {
        Write-Host 'Automatic relaunch failed because the updated menu script path could not be resolved.' -ForegroundColor Yellow
        return $false
    }

    $PowerShellPath = Get-MOCRelaunchPowerShellPath
    if ([string]::IsNullOrWhiteSpace($PowerShellPath)) {
        Write-Host 'Automatic relaunch failed because PowerShell could not be found.' -ForegroundColor Yellow
        Write-Host ('Run this manually: pwsh -NoLogo -NoProfile -File "{0}"' -f $ScriptPath) -ForegroundColor DarkGray
        return $false
    }

    try {
        $EscapedScriptPath = $ScriptPath.Replace('"', '\"')
        $ArgumentList = [System.Collections.Generic.List[string]]::new()
        [void]$ArgumentList.Add('-NoLogo')
        [void]$ArgumentList.Add('-NoProfile')
        if ($IsWindows) {
            [void]$ArgumentList.Add('-ExecutionPolicy')
            [void]$ArgumentList.Add('Bypass')
        }
        [void]$ArgumentList.Add('-File')
        [void]$ArgumentList.Add(('"{0}"' -f $EscapedScriptPath))

        $WorkingDirectory = if (-not [string]::IsNullOrWhiteSpace([string]$script:MOC_RootPath) -and (Test-Path -LiteralPath $script:MOC_RootPath)) { [string]$script:MOC_RootPath } else { [System.IO.Path]::GetDirectoryName($ScriptPath) }
        Start-Process -FilePath $PowerShellPath -ArgumentList $ArgumentList.ToArray() -WorkingDirectory $WorkingDirectory -ErrorAction Stop | Out-Null
        return $true
    }
    catch {
        Write-Host ('Automatic relaunch failed: {0}' -f $_.Exception.Message) -ForegroundColor Yellow
        Write-Host ('Run this manually: "{0}" -NoLogo -NoProfile -File "{1}"' -f $PowerShellPath, $ScriptPath) -ForegroundColor DarkGray
        return $false
    }
}

function Invoke-MOCSelfUpdate {
    [CmdletBinding()]
    param()

    $OutputBuffer = [System.Collections.Generic.List[string]]::new()
    $script:MOC_SelfUpdateGraphAuthorizationGuidanceShown = $false
    $script:MOC_SelfUpdateOutputBuffer = $OutputBuffer
    $script:MOC_View = 'RunConsole'
    $script:MOC_RunConsole_IsActive = $true
    $script:MOC_RunConsole_InputRequired = $false
    $script:MOC_RunConsole_InputPrompt = ''
    $script:MOC_RunConsole_InputHelp = 'No input required while update check is running.'
    $script:MOC_RunConsole_InputPreviewLines = @()
    $script:MOC_RunConsole_ProgressPercent = 0
    $script:MOC_RunConsole_ProgressActivity = 'MOC Update'
    $script:MOC_RunConsole_ProgressStatus = 'Starting'
    $script:MOC_RunConsole_ProgressOperation = 'Preparing update check'

    try {
        do {
            Add-MOCSelfUpdateLine -OutputBuffer $OutputBuffer -Line 'MOC update check starting...' -Percent 2 -Status 'Running' -Operation 'Preparing update configuration'

            if (-not [bool]$script:MOC_UpdateEnabled) {
                Add-MOCSelfUpdateLine -OutputBuffer $OutputBuffer -Line 'WARNING: MOC update is disabled in configuration.' -Percent 100 -Status 'Completed' -Operation 'Update disabled'
                break
            }

            if (-not [bool]$script:MOC_Authenticated) {
                Add-MOCSelfUpdateLine -OutputBuffer $OutputBuffer -Line 'ERROR: Authenticate first with A: Auth before checking SharePoint for updates.' -Percent 100 -Status 'Failed' -Operation 'Authentication required'
                break
            }

            $LocalScriptPath = $PSCommandPath
            if ([string]::IsNullOrWhiteSpace($LocalScriptPath)) { $LocalScriptPath = $MyInvocation.MyCommand.Path }
            if ([string]::IsNullOrWhiteSpace($LocalScriptPath) -or -not (Test-Path -LiteralPath $LocalScriptPath)) {
                Add-MOCSelfUpdateLine -OutputBuffer $OutputBuffer -Line 'ERROR: Could not resolve the running MOC script path. Update cannot continue.' -Percent 100 -Status 'Failed' -Operation 'Local script path unavailable'
                break
            }

            if (-not (Get-Command Invoke-MgGraphRequest -ErrorAction SilentlyContinue)) {
                Add-MOCSelfUpdateLine -OutputBuffer $OutputBuffer -Line 'ERROR: Invoke-MgGraphRequest is not available. Load Microsoft.Graph.Authentication through MOC module maintenance first.' -Percent 100 -Status 'Failed' -Operation 'Microsoft Graph PowerShell unavailable'
                break
            }

            $LocalVersion = Get-MOCVersionObject -VersionText ([string]$script:MOC_Version)
            Add-MOCSelfUpdateLine -OutputBuffer $OutputBuffer -Line ('Local MOC path: {0}' -f $LocalScriptPath) -Percent 8 -Status 'Running' -Operation 'Resolved local script'
            Add-MOCSelfUpdateLine -OutputBuffer $OutputBuffer -Line ('Local menu version: v{0}' -f $script:MOC_Version) -Percent 10 -Status 'Running' -Operation 'Checking local version'
            Add-MOCSelfUpdateLine -OutputBuffer $OutputBuffer -Line ('Remote source: {0}{1} / {2} / {3}' -f $script:MOC_UpdateSiteHostname, $script:MOC_UpdateSitePath, $script:MOC_UpdateDriveName, $script:MOC_UpdateItemPath) -Percent 12 -Status 'Running' -Operation 'Checking SharePoint update source'

            $SiteUri = 'https://graph.microsoft.com/v1.0/sites/{0}:{1}:' -f $script:MOC_UpdateSiteHostname, $script:MOC_UpdateSitePath
            Add-MOCSelfUpdateLine -OutputBuffer $OutputBuffer -Line 'Resolving SharePoint site through Microsoft Graph...' -Percent 18 -Status 'Running' -Operation 'Resolving SharePoint site'
            $Site = Invoke-MOCSelfUpdateGraphRequest -Method GET -Uri $SiteUri -Operation 'resolve the configured SharePoint site'
            if ($null -eq $Site -or [string]::IsNullOrWhiteSpace([string]$Site.id)) {
                Add-MOCSelfUpdateLine -OutputBuffer $OutputBuffer -Line 'ERROR: Microsoft Graph did not return a valid SharePoint site id.' -Percent 100 -Status 'Failed' -Operation 'SharePoint site not found'
                break
            }

            Add-MOCSelfUpdateLine -OutputBuffer $OutputBuffer -Line ('SharePoint site resolved: {0}' -f $Site.webUrl) -Percent 25 -Status 'Running' -Operation 'Resolving document library'
            $Drives = Invoke-MOCSelfUpdateGraphRequest -Method GET -Uri ('https://graph.microsoft.com/v1.0/sites/{0}/drives' -f $Site.id) -Operation 'list SharePoint document libraries'
            $Drive = @($Drives.value | Where-Object { $_.name -eq [string]$script:MOC_UpdateDriveName } | Select-Object -First 1)
            if ($null -eq $Drive -or [string]::IsNullOrWhiteSpace([string]$Drive.id)) {
                $DriveNames = @($Drives.value | ForEach-Object { [string]$_.name }) -join ', '
                Add-MOCSelfUpdateLine -OutputBuffer $OutputBuffer -Line ('ERROR: Could not find SharePoint library/drive "{0}". Available drives: {1}' -f $script:MOC_UpdateDriveName, $DriveNames) -Percent 100 -Status 'Failed' -Operation 'Document library not found'
                break
            }

            Add-MOCSelfUpdateLine -OutputBuffer $OutputBuffer -Line ('Library resolved: {0}' -f $Drive.name) -Percent 32 -Status 'Running' -Operation 'Checking menu package'

            Remove-MOCUpdateStagingDirectory -OutputBuffer $OutputBuffer
            $StageRoot = Join-Path $script:MOC_RootPath '.MOC-Update-Staging'
            if (-not (Test-Path -LiteralPath $StageRoot)) { New-Item -ItemType Directory -Path $StageRoot -Force | Out-Null }
            $BackupRoot = Join-Path $script:MOC_RootPath '.MOC-Update-Backups'
            if (-not (Test-Path -LiteralPath $BackupRoot)) { New-Item -ItemType Directory -Path $BackupRoot -Force | Out-Null }

            $MenuUpdateApplied = $false
            $MenuSummary = [ordered]@{
                Checked   = 1
                Updated   = 0
                Installed = 0
                Skipped   = 0
                Failed    = 0
            }
            $EncodedDrivePath = ConvertTo-MOCGraphDriveRelativePath -Path ([string]$script:MOC_UpdateItemPath)
            $RemoteItemUri = 'https://graph.microsoft.com/v1.0/drives/{0}/root:/{1}' -f $Drive.id, $EncodedDrivePath
            $RemoteItem = Invoke-MOCSelfUpdateGraphRequest -Method GET -Uri $RemoteItemUri -Operation 'read the remote MOC menu update file metadata'
            if ($null -eq $RemoteItem -or [string]::IsNullOrWhiteSpace([string]$RemoteItem.id)) {
                Add-MOCSelfUpdateLine -OutputBuffer $OutputBuffer -Line ('ERROR: Remote MOC menu update file was not found at {0}.' -f $script:MOC_UpdateItemPath) -Percent 100 -Status 'Failed' -Operation 'Remote menu not found'
                break
            }

            Add-MOCSelfUpdateLine -OutputBuffer $OutputBuffer -Line ('Remote menu file: {0}' -f $RemoteItem.name) -Percent 40 -Status 'Running' -Operation 'Downloading menu package'
            Add-MOCSelfUpdateLine -OutputBuffer $OutputBuffer -Line ('Remote menu modified: {0}' -f $RemoteItem.lastModifiedDateTime) -Percent 42 -Status 'Running' -Operation 'Downloading menu package'

            $StagePath = Join-Path $StageRoot ('{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), [string]$script:MOC_UpdateFileName)
            Save-MOCGraphDriveItemToPath -DriveId ([string]$Drive.id) -Item $RemoteItem -DestinationPath $StagePath
            Unblock-MOCDownloadedScriptFile -Path $StagePath -OutputBuffer $OutputBuffer -DisplayName ([string]$script:MOC_UpdateFileName)

            if (-not (Test-Path -LiteralPath $StagePath) -or (Get-Item -LiteralPath $StagePath).Length -lt 1024) {
                Add-MOCSelfUpdateLine -OutputBuffer $OutputBuffer -Line 'ERROR: Downloaded menu update file is missing or unexpectedly small.' -Percent 100 -Status 'Failed' -Operation 'Menu download validation failed'
                break
            }

            Add-MOCSelfUpdateLine -OutputBuffer $OutputBuffer -Line 'Reading staged menu metadata...' -Percent 50 -Status 'Running' -Operation 'Reading remote menu metadata'
            $RemoteMetadata = Get-MOCScriptMetadata -Path $StagePath
            $RemoteVersion = Get-MOCVersionObject -VersionText ([string]$RemoteMetadata.Version)
            if ($null -eq $RemoteVersion) {
                Add-MOCSelfUpdateLine -OutputBuffer $OutputBuffer -Line 'ERROR: Remote menu script does not contain a valid .VERSION metadata value.' -Percent 100 -Status 'Failed' -Operation 'Remote menu metadata validation failed'
                break
            }

            Add-MOCSelfUpdateLine -OutputBuffer $OutputBuffer -Line ('Remote menu version: v{0}' -f $RemoteMetadata.Version) -Percent 56 -Status 'Running' -Operation 'Comparing menu version'
            if ($null -ne $LocalVersion -and $RemoteVersion -le $LocalVersion) {
                Add-MOCSelfUpdateLine -OutputBuffer $OutputBuffer -Line 'OK: Local MOC menu is already the same version or newer. No menu update was applied.' -Percent 62 -Status 'Running' -Operation 'Menu is current'
                $MenuSummary.Skipped = 1
            }
            else {
                Add-MOCSelfUpdateLine -OutputBuffer $OutputBuffer -Line 'Validating staged menu PowerShell syntax...' -Percent 66 -Status 'Running' -Operation 'Menu parser validation'
                $ParseErrors = $null
                if (-not (Test-MOCPowerShellFileSyntax -Path $StagePath -ParseErrors ([ref]$ParseErrors))) {
                    Add-MOCSelfUpdateLine -OutputBuffer $OutputBuffer -Line ('ERROR: Remote menu script parser validation failed with {0} error(s).' -f @($ParseErrors).Count) -Percent 100 -Status 'Failed' -Operation 'Menu parser validation failed'
                    foreach ($ParseError in @($ParseErrors | Select-Object -First 5)) {
                        Add-RunConsoleLine -OutputBuffer $OutputBuffer -Line ('Line {0}, Column {1}: {2}' -f $ParseError.Extent.StartLineNumber, $ParseError.Extent.StartColumnNumber, $ParseError.Message)
                    }
                    Write-RunConsoleFrame -ScriptName 'MOC Update' -OutputBuffer $OutputBuffer -ScrollOffset (Get-MOCRunConsoleScrollMaxOffset -OutputBuffer $OutputBuffer) -Status 'Failed' -FooterView 'RunConsole'
                    break
                }

                $LocalName = [System.IO.Path]::GetFileName($LocalScriptPath)
                $BackupPath = Join-Path $BackupRoot ('{0}.{1}.bak' -f $LocalName, (Get-Date -Format 'yyyyMMdd-HHmmss'))
                Add-MOCSelfUpdateLine -OutputBuffer $OutputBuffer -Line ('Backing up current MOC menu to: {0}' -f $BackupPath) -Percent 72 -Status 'Running' -Operation 'Creating menu backup'
                Copy-Item -LiteralPath $LocalScriptPath -Destination $BackupPath -Force -ErrorAction Stop

                Add-MOCSelfUpdateLine -OutputBuffer $OutputBuffer -Line 'Replacing local MOC menu script with staged update...' -Percent 78 -Status 'Running' -Operation 'Replacing menu script'
                Copy-Item -LiteralPath $StagePath -Destination $LocalScriptPath -Force -ErrorAction Stop
                Unblock-MOCDownloadedScriptFile -Path $LocalScriptPath -OutputBuffer $OutputBuffer -DisplayName $LocalName
                $MenuUpdateApplied = $true
                $MenuSummary.Updated = 1
                Add-RunConsoleLine -OutputBuffer $OutputBuffer -Line ('UPDATED: MOC menu from v{0} to v{1}.' -f $script:MOC_Version, $RemoteMetadata.Version)
            }

            $ChangelogSummary = Invoke-MOCChangelogUpdate -OutputBuffer $OutputBuffer -Drive $Drive -StageRoot $StageRoot -BackupRoot $BackupRoot
            $ChildSummary = Invoke-MOCChildScriptUpdates -OutputBuffer $OutputBuffer -Drive $Drive -StageRoot $StageRoot -BackupRoot $BackupRoot
            Remove-MOCUpdateStagingDirectory -OutputBuffer $OutputBuffer

            $Retention = [Math]::Max(1, [int]$script:MOC_UpdateBackupRetention)
            Get-ChildItem -LiteralPath $BackupRoot -Filter '*.bak' -File -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending |
                Select-Object -Skip $Retention |
                Remove-Item -Force -ErrorAction SilentlyContinue

            $FinalOperation = if ($MenuUpdateApplied) { 'Restarting menu' } else { 'Update check completed' }
            $MenuSummaryName = if ([string]::IsNullOrWhiteSpace([string]$script:MOC_UpdateFileName)) { [System.IO.Path]::GetFileName($LocalScriptPath) } else { [string]$script:MOC_UpdateFileName }
            $ChangelogSummaryName = if ([string]::IsNullOrWhiteSpace([string]$script:MOC_UpdateChangelogFileName)) { 'CHANGELOG.md' } else { [string]$script:MOC_UpdateChangelogFileName }
            $MenuSummaryState = if ([int]$MenuSummary.Failed -gt 0) { 'failed' } elseif ([int]$MenuSummary.Updated -gt 0) { 'updated' } elseif ([int]$MenuSummary.Installed -gt 0) { 'installed' } elseif ([int]$MenuSummary.Skipped -gt 0) { 'current' } else { 'checked' }
            $ChangelogSummaryState = if ([int]$ChangelogSummary.Failed -gt 0) { 'failed' } elseif ([int]$ChangelogSummary.Updated -gt 0) { 'updated' } elseif ([int]$ChangelogSummary.Installed -gt 0) { 'installed' } elseif ([int]$ChangelogSummary.Skipped -gt 0) { 'current' } else { 'checked' }
            $ChildSummaryState = if ([int]$ChildSummary.Failed -gt 0) { 'failed' } elseif (([int]$ChildSummary.Updated + [int]$ChildSummary.Installed) -gt 0) { 'updated' } elseif ([int]$ChildSummary.Checked -gt 0) { 'current' } else { 'not checked' }
            Add-MOCSelfUpdateLine -OutputBuffer $OutputBuffer -Line ('Update summary: menu {0} is {1} (checked {2}, updated {3}, failed {4}); {5} is {6} (checked {7}, updated {8}, skipped {9}, failed {10}); child scripts are {11} (checked {12}, updated {13}, installed {14}, skipped {15}, failed {16}).' -f $MenuSummaryName, $MenuSummaryState, $MenuSummary.Checked, $MenuSummary.Updated, $MenuSummary.Failed, $ChangelogSummaryName, $ChangelogSummaryState, $ChangelogSummary.Checked, $ChangelogSummary.Updated, $ChangelogSummary.Skipped, $ChangelogSummary.Failed, $ChildSummaryState, $ChildSummary.Checked, $ChildSummary.Updated, $ChildSummary.Installed, $ChildSummary.Skipped, $ChildSummary.Failed) -Percent 100 -Status 'Completed' -Operation $FinalOperation
            if ($MenuUpdateApplied) {
                $script:MOC_RestartRequested = $true
                $script:MOC_RestartScriptPath = $LocalScriptPath
                $script:MOC_RestartReason = 'Menu update applied'
                Add-RunConsoleLine -OutputBuffer $OutputBuffer -Line 'UPDATE APPLIED: The MOC menu script has been updated.'
                Add-RunConsoleLine -OutputBuffer $OutputBuffer -Line 'A forced menu restart is required so the updated script is the only running menu instance.'
                Add-RunConsoleLine -OutputBuffer $OutputBuffer -Line 'MOC will close this menu session and reopen automatically in a new PowerShell window.'
                Add-RunConsoleLine -OutputBuffer $OutputBuffer -Line 'No Ctrl+C action is needed; the current menu process will exit cleanly.'
            }
            Write-RunConsoleFrame -ScriptName 'MOC Update' -OutputBuffer $OutputBuffer -ScrollOffset (Get-MOCRunConsoleScrollMaxOffset -OutputBuffer $OutputBuffer) -Status 'Completed' -FooterView 'RunConsole'
            if ($MenuUpdateApplied) {
                $RestartCountdownSeconds = [Math]::Max(5, [int]$script:MOC_RestartCountdownSeconds)
                Add-MOCSelfUpdateLine -OutputBuffer $OutputBuffer -Line ('Automatic restart countdown started: {0} seconds. Review this update screen now; MOC will close and reopen automatically.' -f $RestartCountdownSeconds) -Percent 100 -Status 'Completed' -Operation ('Restarting in {0}s' -f $RestartCountdownSeconds)
                for ($RestartRemaining = $RestartCountdownSeconds; $RestartRemaining -gt 0; $RestartRemaining--) {
                    Add-MOCSelfUpdateLine -OutputBuffer $OutputBuffer -Line ('Restarting automatically in {0} second(s)...' -f $RestartRemaining) -Percent 100 -Status 'Completed' -Operation ('Restarting in {0}s' -f $RestartRemaining)
                    Start-Sleep -Seconds 1
                }
                Add-MOCSelfUpdateLine -OutputBuffer $OutputBuffer -Line 'Restart countdown complete. Closing this menu session and reopening the updated menu now...' -Percent 100 -Status 'Completed' -Operation 'Restarting now'
                Start-Sleep -Milliseconds 500
                return
            }
        } while ($false)
    }
    catch {
        Add-RunConsoleLine -OutputBuffer $OutputBuffer -Line ('ERROR: MOC update failed: {0}' -f $_.Exception.Message)
        if (-not [bool]$script:MOC_SelfUpdateGraphAuthorizationGuidanceShown) {
            if ($_.ScriptStackTrace) { Add-RunConsoleLine -OutputBuffer $OutputBuffer -Line $_.ScriptStackTrace }
        }
        Remove-MOCUpdateStagingDirectory -OutputBuffer $OutputBuffer
        $script:MOC_RunConsole_ProgressPercent = 100
        $script:MOC_RunConsole_ProgressActivity = 'MOC Update'
        $script:MOC_RunConsole_ProgressStatus = 'Failed'
        $script:MOC_RunConsole_ProgressOperation = if ([bool]$script:MOC_SelfUpdateGraphAuthorizationGuidanceShown) { 'SharePoint update access is not authorized' } else { 'Review the error details' }
        Write-RunConsoleFrame -ScriptName 'MOC Update' -OutputBuffer $OutputBuffer -ScrollOffset (Get-MOCRunConsoleScrollMaxOffset -OutputBuffer $OutputBuffer) -Status 'Failed' -FooterView 'RunConsole'
    }
    finally {
        $script:MOC_SelfUpdateOutputBuffer = $null
        $script:MOC_RunConsole_IsActive = $false
        $script:MOC_RunConsole_InputRequired = $false
        $script:MOC_RunConsole_InputPrompt = ''
        $script:MOC_RunConsole_InputHelp = 'Press Enter to return to the MOC menu.'
        $script:MOC_RunConsole_InputPreviewLines = @()
    }

    if (-not [bool]$script:MOC_RestartRequested) {
        $ReviewStatus = if ([string]$script:MOC_RunConsole_ProgressStatus -match 'Failed') { 'Failed' } else { 'Completed' }
        Wait-MOCRunConsoleReviewOrReturn -ScriptName 'MOC Update' -OutputBuffer $OutputBuffer -Status $ReviewStatus
        $script:MOC_View = 'Home'
        $script:MOC_LastStatus = 'Update check completed'
    }
}

function Get-RunConsoleLineColor {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$Line = ''
    )

    $MarkedLevel = Get-MOCOutputLineLevel -Line $Line
    if (-not [string]::IsNullOrWhiteSpace($MarkedLevel)) {
        return (Get-MOCOutputLevelColor -Level $MarkedLevel)
    }

    $Line = Remove-MOCOutputLineLevelMarker -Line $Line

    if ([string]::IsNullOrWhiteSpace($Line)) {
        return $script:Ansi.Gray
    }

    $trimmed = $Line.Trim()

    # High-confidence failure/error signals.
    if ($trimmed -match '^(ERROR|FAILED|FAILURE|EXCEPTION):|^ERROR\b|^FAILED\b|Authentication failed|Script Failed|Missing required|not installed|not usable|token expired|InvalidAuthenticationToken') {
        return "$($script:Ansi.Bold)$($script:Ansi.Red)"
    }

    # Warnings and remediation messages.
    if ($trimmed -match '^(WARNING|WARN|CAUTION):|WARNING\b|requires|What to do:|How to grant|Grant admin consent|Retrying') {
        return "$($script:Ansi.Bold)$($script:Ansi.Yellow)"
    }

    # Success/connected/validated signals.
    if ($trimmed -match '^(SUCCESS|COMPLETED):|SUCCESS\b|completed successfully|session is ready|already connected|connected and validated|Graph connected|Microsoft Graph connected|Organization:|Exported \d+ row|Workbook created|saved ->|opened .*workbook') {
        return "$($script:Ansi.Bold)$($script:Ansi.Green)"
    }

    # Active work / current operation lines.
    if ($trimmed -match '^(Step \d+ of \d+|\[Step \d+ of \d+\]|Initializing|Connecting|Retrieving|Requesting|Refreshing|Collecting|Building|Exporting|Formatting|Validating|Importing|Setting |Opening |Writing |Resolved |Rows exported|Collected \d+ row)') {
        return "$($script:Ansi.Bold)$($script:Ansi.Cyan)"
    }

    # Path, transcript, and summary lines are useful but secondary.
    if ($trimmed -match '^(Transcript log|Session index|Report root|Output folder|Full output folder|Run Summary|XML backup|XLSX report|Summary saved|Diagnostics file|Script build|Script version|Script file|Tenant|Graph tenant|Graph client|Graph auth type)') {
        return $script:Ansi.Gray
    }

    return $script:Ansi.White
}



function Get-MOCRunConsoleOutputViewportHeight {
    [CmdletBinding()]
    param()

    Update-MOCResponsiveLayout
    $ViewportHeight = [int]$script:MOC_RunViewportHeight

    # Reserve space for the bottom navigation footer and persistent input pane.
    $ViewportHeight = [Math]::Max(4, $ViewportHeight - 4)
    $ViewportHeight = [Math]::Max(3, $ViewportHeight - 4)
    return [int]$ViewportHeight
}

function Get-MOCRunConsoleDisplayRowCount {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$OutputBuffer = $null
    )

    if ($null -eq $OutputBuffer) { return 0 }

    $Width = Get-TerminalWidth
    $InnerWidth = [Math]::Max(1, $Width - 4)
    $Count = 0

    foreach ($RawLine in @($OutputBuffer)) {
        $DisplayLine = Remove-MOCOutputLineLevelMarker -Line ([string]$RawLine)
        $WrappedLines = Split-MOCRunConsoleOutputLine -Line $DisplayLine -Width $InnerWidth -MaxLines 4
        $Count += [Math]::Max(1, @($WrappedLines).Count)
    }

    return [int]$Count
}

function Get-MOCRunConsoleScrollMaxOffset {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$OutputBuffer = $null
    )

    $DisplayRowCount = Get-MOCRunConsoleDisplayRowCount -OutputBuffer $OutputBuffer
    $ViewportHeight = Get-MOCRunConsoleOutputViewportHeight
    return [Math]::Max(0, $DisplayRowCount - $ViewportHeight)
}

function Get-MOCConsoleInputKeyName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$KeyInfo = $null
    )

    if ($null -eq $KeyInfo) { return '' }

    # Supports both System.ConsoleKeyInfo from [Console]::ReadKey() and
    # System.Management.Automation.Host.KeyInfo from $Host.UI.RawUI.ReadKey().
    try {
        $KeyProperty = $KeyInfo.PSObject.Properties['Key']
        if ($null -ne $KeyProperty -and $null -ne $KeyProperty.Value) {
            return [string]$KeyProperty.Value
        }
    }
    catch { }

    try {
        $VirtualKeyProperty = $KeyInfo.PSObject.Properties['VirtualKeyCode']
        if ($null -ne $VirtualKeyProperty -and $null -ne $VirtualKeyProperty.Value) {
            switch ([int]$VirtualKeyProperty.Value) {
                8  { return 'Backspace' }
                13 { return 'Enter' }
                27 { return 'Escape' }
                33 { return 'PageUp' }
                34 { return 'PageDown' }
                35 { return 'End' }
                36 { return 'Home' }
                37 { return 'LeftArrow' }
                38 { return 'UpArrow' }
                39 { return 'RightArrow' }
                40 { return 'DownArrow' }
                default { return ('VirtualKeyCode:{0}' -f [int]$VirtualKeyProperty.Value) }
            }
        }
    }
    catch { }

    return ''
}

function Get-MOCConsoleInputKeyCharText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$KeyInfo = $null
    )

    if ($null -eq $KeyInfo) { return '' }

    foreach ($PropertyName in @('KeyChar','Character')) {
        try {
            $Property = $KeyInfo.PSObject.Properties[$PropertyName]
            if ($null -ne $Property -and $null -ne $Property.Value) {
                $Value = $Property.Value
                if ($Value -is [char]) {
                    if ([int][char]$Value -eq 0) { return '' }
                    return [string][char]$Value
                }
                if ($Value -is [int]) {
                    if ([int]$Value -eq 0) { return '' }
                    return [string][char][int]$Value
                }
                $Text = [string]$Value
                if ($Text -eq [string][char]0) { return '' }
                return $Text
            }
        }
        catch { }
    }

    return ''
}

function Move-MOCRunConsoleScrollOffset {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$KeyInfo,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$OutputBuffer = $null
    )

    $ViewportHeight = Get-MOCRunConsoleOutputViewportHeight
    $MaxOffset = Get-MOCRunConsoleScrollMaxOffset -OutputBuffer $OutputBuffer

    $CurrentOffset = 0
    if ($null -ne $script:MOC_RunConsole_UserScrollOffset) {
        try { $CurrentOffset = [int]$script:MOC_RunConsole_UserScrollOffset } catch { $CurrentOffset = $MaxOffset }
    }
    else {
        $CurrentOffset = $MaxOffset
    }

    $KeyName = Get-MOCConsoleInputKeyName -KeyInfo $KeyInfo

    switch ($KeyName) {
        'PageUp'   { $CurrentOffset = [Math]::Max(0, $CurrentOffset - $ViewportHeight) }
        'PageDown' { $CurrentOffset = [Math]::Min($MaxOffset, $CurrentOffset + $ViewportHeight) }
        'UpArrow'  { $CurrentOffset = [Math]::Max(0, $CurrentOffset - 1) }
        'DownArrow'{ $CurrentOffset = [Math]::Min($MaxOffset, $CurrentOffset + 1) }
        'Home'     { $CurrentOffset = 0 }
        'End'      {
            # End resumes auto-follow mode. New child-script output will keep the pane at the newest rows.
            $script:MOC_RunConsole_UserScrollOffset = $null
            return $true
        }
        default    { return $false }
    }

    $script:MOC_RunConsole_UserScrollOffset = [int]$CurrentOffset
    return $true
}


function Wait-MOCRunConsoleReviewOrReturn {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$ScriptName = 'MOC Update',

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$OutputBuffer = $null,

        [Parameter(Mandatory = $false)]
        [string]$Status = 'Completed'
    )

    # DESCRIPTION: Keeps a completed update/result screen open while allowing output review.
    # WHY THIS MATTERS: Windows Terminal may translate mouse-wheel activity into
    # console input while MOC is in the alternate screen. RawUI.ReadKey() returns
    # System.Management.Automation.Host.KeyInfo, so input is normalized before
    # it is compared with ConsoleKey names. A single ReadKey() would otherwise
    # treat wheel input as "return to menu" or raise a type-conversion error.
    # This loop consumes scroll keys
    # for output review and only exits on Enter, Esc, Backspace, or Q.
    $script:MOC_RunConsole_IsActive = $false
    $script:MOC_RunConsole_InputRequired = $false
    $script:MOC_RunConsole_InputPrompt = 'Input'
    $script:MOC_RunConsole_InputValue = ''
    $script:MOC_RunConsole_InputHelp = 'Press Enter to return to the MOC menu. PgUp/PgDn, Up/Down, Home/End, or mouse wheel review output.'
    $script:MOC_RunConsole_InputPreviewLines = @()

    $ScrollOffset = Get-MOCRunConsoleScrollMaxOffset -OutputBuffer $OutputBuffer
    $script:MOC_RunConsole_UserScrollOffset = [int]$ScrollOffset

    while ($true) {
        Write-RunConsoleFrame -ScriptName $ScriptName -OutputBuffer $OutputBuffer -ScrollOffset $ScrollOffset -Status $Status -FooterView 'RunConsole'

        try {
            $KeyInfo = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        }
        catch {
            Read-Host 'Press Enter to return to MOC' | Out-Null
            break
        }

        Hide-MOCCursor

        if (Move-MOCRunConsoleScrollOffset -KeyInfo $KeyInfo -OutputBuffer $OutputBuffer) {
            if ($null -eq $script:MOC_RunConsole_UserScrollOffset) {
                $ScrollOffset = Get-MOCRunConsoleScrollMaxOffset -OutputBuffer $OutputBuffer
                $script:MOC_RunConsole_InputHelp = 'Auto-follow resumed. Newest output is shown. Press Enter to return to MOC.'
            }
            else {
                $ScrollOffset = [int]$script:MOC_RunConsole_UserScrollOffset
                $script:MOC_RunConsole_InputHelp = 'Reviewing update output. PgUp/PgDn page, Up/Down or mouse wheel scroll, End resumes latest output.'
            }
            continue
        }

        $KeyName = Get-MOCConsoleInputKeyName -KeyInfo $KeyInfo
        $KeyCharText = Get-MOCConsoleInputKeyCharText -KeyInfo $KeyInfo
        if ($KeyName -in @('Enter','Escape','Backspace') -or $KeyCharText -match '^[Qq]$') {
            break
        }

        # Ignore unrelated keys and any non-scroll mouse/terminal artifacts so they
        # do not accidentally close the update review screen.
    }

    $script:MOC_RunConsole_UserScrollOffset = $null
}

function Invoke-MOCRunConsoleLiveReviewKeys {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$OutputBuffer = $null
    )

    # Child scripts usually run without reading keys. This lets technicians review
    # the output pane during execution without waiting for completion. Avoid
    # consuming keys while a MOC-managed input prompt is active because those prompts
    # already handle PgUp/PgDn/Up/Down/Home/End themselves.
    if ($script:MOC_RunConsole_InputRequired) { return $false }

    $Handled = $false

    try {
        while ([System.Console]::KeyAvailable) {
            $KeyInfo = [System.Console]::ReadKey($true)
            Hide-MOCCursor

            if (Move-MOCRunConsoleScrollOffset -KeyInfo $KeyInfo -OutputBuffer $OutputBuffer) {
                $Handled = $true

                if ($null -eq $script:MOC_RunConsole_UserScrollOffset) {
                    $script:MOC_RunConsole_InputHelp = 'Auto-follow resumed. Newest output is shown.'
                }
                else {
                    $script:MOC_RunConsole_InputHelp = 'Reviewing output. PgUp/PgDn page, Up/Down scroll, End resumes latest output.'
                }
                continue
            }

            # Ignore unrelated keystrokes while a child script is running without a
            # MOC input prompt. This prevents random keys from leaking below the UI.
            $Handled = $true
        }
    }
    catch {
        # Key polling is best-effort only. Never let it interfere with child execution.
        return $Handled
    }

    return $Handled
}


function Clear-MOCRunConsoleInputState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Help = 'Waiting for script output or completion.'
    )

    # Area 7 is parent MOC-owned. Clear stale prompt/input text as soon as
    # a MOC-managed prompt accepts input so the next child-script step does not
    # continue while the previous prompt remains displayed.
    $script:MOC_RunConsole_InputRequired = $false
    $script:MOC_RunConsole_InputPrompt = 'Input'
    $script:MOC_RunConsole_InputValue = ''
    $script:MOC_RunConsole_InputHelp = $Help
    $script:MOC_RunConsole_InputPreviewLines = @()
}


function Write-RunConsoleInputPanel {
    # DESCRIPTION: Renders the persistent input pane at the bottom of the run console.
    # WHY THIS MATTERS: Child-script prompts stay inside the MOC frame instead of dropping below the terminal UI.

    param(
        [Parameter(Mandatory = $false)]
        [int]$Width = (Get-TerminalWidth),

        [Parameter(Mandatory = $false)]
        [string]$Status = 'Running',

        [Parameter(Mandatory = $false)]
        [string]$BorderColor = $script:MOC_BorderInput
    )

    $InputRequired = $false
    if ($null -ne $script:MOC_RunConsole_InputRequired) {
        $InputRequired = [bool]$script:MOC_RunConsole_InputRequired
    }

    $Prompt = if ([string]::IsNullOrWhiteSpace([string]$script:MOC_RunConsole_InputPrompt)) { 'Input' } else { [string]$script:MOC_RunConsole_InputPrompt }
    $Value = if ($null -eq $script:MOC_RunConsole_InputValue) { '' } else { [string]$script:MOC_RunConsole_InputValue }
    $Help = if ([string]::IsNullOrWhiteSpace([string]$script:MOC_RunConsole_InputHelp)) { 'No input required.' } else { [string]$script:MOC_RunConsole_InputHelp }
    $PreviewLines = @()
    if ($null -ne $script:MOC_RunConsole_InputPreviewLines) {
        $PreviewLines = @($script:MOC_RunConsole_InputPreviewLines)
    }

    if ($Status -match '^(Completed|Failed)$') {
        Write-PanelLine -BorderColor $BorderColor -Text 'Input' -Width $Width -Color "$($script:Ansi.Bold)$($script:Ansi.Cyan)"
        Write-PanelLine -BorderColor $BorderColor -Text '  Press Enter to return to the MOC menu.' -Width $Width -Color "$($script:Ansi.Bold)$($script:Ansi.Yellow)"
        Write-PanelLine -BorderColor $BorderColor -Text '  PgUp/PgDn review output.' -Width $Width -Color $script:Ansi.Gray
        return
    }

    if ($InputRequired) {
        $DisplayValue = $Value
        $MaxValueLength = [Math]::Max(12, $Width - $Prompt.Length - 10)
        if ($DisplayValue.Length -gt $MaxValueLength) {
            $DisplayValue = '...' + $DisplayValue.Substring($DisplayValue.Length - $MaxValueLength + 3)
        }

        $PromptText = [string]$Prompt
        if ($null -eq $PromptText) { $PromptText = 'Input' }
        $PromptText = $PromptText.TrimEnd()

        if ($PromptText.EndsWith(':')) {
            $RenderedPromptLine = ("  {0} {1}_" -f $PromptText, $DisplayValue)
        }
        else {
            $RenderedPromptLine = ("  {0}: {1}_" -f $PromptText, $DisplayValue)
        }

        Write-PanelLine -BorderColor $BorderColor -Text 'Input required' -Width $Width -Color "$($script:Ansi.Bold)$($script:Ansi.Cyan)"
        Write-PanelLine -BorderColor $BorderColor -Text $RenderedPromptLine -Width $Width -Color "$($script:Ansi.Bold)$($script:Ansi.Yellow)"

        foreach ($PreviewLine in $PreviewLines) {
            $PreviewText = [string]$PreviewLine
            $PreviewColor = if ($PreviewText -match '^\s*>') { "$($script:Ansi.Bold)$($script:Ansi.Yellow)" } elseif ($PreviewText -match '(?i)parser|error|invalid|missing') { $script:Ansi.Red } else { $script:Ansi.Gray }
            Write-PanelLine -BorderColor $BorderColor -Text ("  {0}" -f $PreviewText) -Width $Width -Color $PreviewColor
        }

        Write-PanelLine -BorderColor $BorderColor -Text ("  {0}" -f $Help) -Width $Width -Color $script:Ansi.Gray
    }
    else {
        Write-PanelLine -BorderColor $BorderColor -Text 'Input' -Width $Width -Color "$($script:Ansi.Bold)$($script:Ansi.Cyan)"
        Write-PanelLine -BorderColor $BorderColor -Text '  No input required.' -Width $Width -Color $script:Ansi.Gray
        Write-PanelLine -BorderColor $BorderColor -Text '  PgUp/PgDn review output while running. End resumes latest output.' -Width $Width -Color $script:Ansi.Gray
    }
}

function Get-MOCRunConsoleInputPaneReservedRows {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Status = 'Running'
    )

    if ($Status -match '^(Completed|Failed)$') { return 4 }

    $PreviewCount = 0
    if ($null -ne $script:MOC_RunConsole_InputPreviewLines) {
        try { $PreviewCount = @($script:MOC_RunConsole_InputPreviewLines).Count } catch { $PreviewCount = 0 }
    }

    if ([bool]$script:MOC_RunConsole_InputRequired) {
        return [Math]::Min(18, [Math]::Max(4, 3 + [int]$PreviewCount + 1))
    }

    return 4
}

function Write-RunConsoleFrame {
    # DESCRIPTION: Renders a fixed-height script execution viewport.
    # WHY THIS MATTERS: Child script output stays inside a bounded console-like frame instead of pushing the terminal down indefinitely.

    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptName,

        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[string]]$OutputBuffer,

        [Parameter(Mandatory = $false)]
        [int]$ScrollOffset = 0,

        [Parameter(Mandatory = $false)]
        [string]$Status = 'Running',

        [Parameter(Mandatory = $false)]
        [string]$FooterView = ''
    )

    if ($null -eq $OutputBuffer) {
        $OutputBuffer = [System.Collections.Generic.List[string]]::new()
    }

    Update-MOCResponsiveLayout
    $Width = Get-TerminalWidth
    $ScriptPaneBorder = $script:MOC_BorderPrimary
    $OutputPaneBorder = $script:MOC_BorderSecondary
    $LineStatusPaneBorder = $script:MOC_BorderSecondary
    $InputPaneBorder = $script:MOC_BorderInput
    $ResolvedFooterView = $FooterView
    if ([string]::IsNullOrWhiteSpace($ResolvedFooterView)) {
        if ($ScriptName -eq 'MOC Terminal') { $ResolvedFooterView = 'Terminal' }
        else { $ResolvedFooterView = 'RunConsole' }
    }

    $ViewportHeight = $script:MOC_RunViewportHeight
    if (-not [string]::IsNullOrWhiteSpace($ResolvedFooterView)) {
        # Reserve space for the bottom navigation footer on run/auth/review frames.
        # Without this, the footer can be rendered below the visible terminal area on shorter windows.
        $ViewportHeight = [Math]::Max(4, [int]$ViewportHeight - 4)
    }

    # Reserve space for the persistent MOC input pane. The pane is visible even when
    # a child script does not need input so the run-console layout stays stable.
    # Terminal paste editor mode may add a fixed-height preview, so reserve only
    # that bounded amount and keep the output pane from being pushed outside the frame.
    $InputPaneReservedRows = Get-MOCRunConsoleInputPaneReservedRows -Status $Status
    # Reserve one additional row because the Lines/Showing strip and the input
    # pane are now rendered as separate boxes with their own bottom/top borders.
    $LineStatusSeparateBoxExtraRow = 1
    $ViewportHeight = [Math]::Max(3, [int]$ViewportHeight - [int]$InputPaneReservedRows - [int]$LineStatusSeparateBoxExtraRow)
    $InnerWidth = [Math]::Max(1, $Width - 4)

    # Write-Header already clears and homes the console. Calling the clear routine
    # twice can leave a blank frame if the host drops an intermediate redraw.
    Write-Header
    Write-Breadcrumb

    # Render stacked panes as separate boxes instead of one shared multi-color box.
    # This keeps pane edges clean when the border color changes from the blue
    # script/activity pane to the light-blue/cyan output/input panes.
    Write-MOCBorderLine -Kind Top -Width $Width -Color $ScriptPaneBorder
    Write-PanelLine -BorderColor $ScriptPaneBorder -Text ("Running: {0}" -f $ScriptName) -Width $Width -Color "$($script:Ansi.Bold)$($script:Ansi.Green)"
    Write-MOCBorderLine -Kind Middle -Width $Width -Color $ScriptPaneBorder
    Write-RunConsoleProgressPanel -Width $Width -Status $Status -BorderColor $ScriptPaneBorder
    Write-MOCBorderLine -Kind Bottom -Width $Width -Color $ScriptPaneBorder

    Write-MOCBorderLine -Kind Top -Width $Width -Color $OutputPaneBorder

    $DisplayRows = [System.Collections.Generic.List[object]]::new()
    foreach ($RawLine in $OutputBuffer) {
        $OriginalLine = [string]$RawLine
        $LineColor = Get-RunConsoleLineColor -Line $OriginalLine
        $DisplayLine = Remove-MOCOutputLineLevelMarker -Line $OriginalLine
        $WrappedLines = Split-MOCRunConsoleOutputLine -Line $DisplayLine -Width $InnerWidth -MaxLines 4
        foreach ($WrappedLine in $WrappedLines) {
            $DisplayRows.Add([pscustomobject]@{
                Text  = [string]$WrappedLine
                Color = $LineColor
            })
        }
    }

    $Total = $DisplayRows.Count
    $MaxOffset = [Math]::Max(0, $Total - $ViewportHeight)
    if ($ScrollOffset -lt 0) { $ScrollOffset = 0 }
    if ($ScrollOffset -gt $MaxOffset) { $ScrollOffset = $MaxOffset }

    if ($Total -eq 0) {
        for ($i = 0; $i -lt $ViewportHeight; $i++) {
            if ($i -eq 0) {
                Write-PanelLine -BorderColor $OutputPaneBorder -Text 'Waiting for script output...' -Width $Width -Color $script:Ansi.Gray
            }
            else {
                Write-PanelLine -BorderColor $OutputPaneBorder -Text '' -Width $Width -Color $script:Ansi.Gray
            }
        }
    }
    else {
        $Start = $ScrollOffset
        $End = [Math]::Min($Total - 1, $Start + $ViewportHeight - 1)

        for ($i = $Start; $i -le $End; $i++) {
            $Row = $DisplayRows[$i]
            Write-PanelLine -BorderColor $OutputPaneBorder -Text ([string]$Row.Text) -Width $Width -Color ([string]$Row.Color)
        }

        $RowsShown = $End - $Start + 1
        for ($pad = $RowsShown; $pad -lt $ViewportHeight; $pad++) {
            Write-PanelLine -BorderColor $OutputPaneBorder -Text '' -Width $Width -Color $script:Ansi.Gray
        }
    }

    Write-MOCBorderLine -Kind Bottom -Width $Width -Color $OutputPaneBorder

    # Render the output line-status strip as its own complete mini-box.
    # Some long-running child scripts refresh the input pane many times while
    # waiting for technician choices. In those cases, a shared middle divider can
    # be visually swallowed by the next input-pane redraw in Windows Terminal.
    # Drawing an explicit bottom border for the Lines/Showing strip, followed by
    # a separate top border for the input pane, keeps both frames intact.
    Write-MOCBorderLine -Kind Top -Width $Width -Color $LineStatusPaneBorder
    Write-PanelLine -BorderColor $LineStatusPaneBorder -Text ("Lines: {0} | Showing: {1}-{2}" -f $Total, ([Math]::Min($Total, $ScrollOffset + 1)), ([Math]::Min($Total, $ScrollOffset + $ViewportHeight))) -Width $Width -Color $script:Ansi.Gray
    Write-MOCBorderLine -Kind Bottom -Width $Width -Color $LineStatusPaneBorder

    Write-MOCBorderLine -Kind Top -Width $Width -Color $InputPaneBorder
    Write-RunConsoleInputPanel -Width $Width -Status $Status -BorderColor $InputPaneBorder

    if ($Status -eq 'Completed') {
        Write-PanelLine -BorderColor $InputPaneBorder -Text 'Status: COMPLETED' -Width $Width -Color "$($script:Ansi.Bold)$($script:Ansi.Yellow)"
    }
    elseif ($Status -eq 'Failed') {
        Write-PanelLine -BorderColor $InputPaneBorder -Text 'Status: FAILED' -Width $Width -Color "$($script:Ansi.Bold)$($script:Ansi.Red)"
    }
    else {
        Write-PanelLine -BorderColor $InputPaneBorder -Text ("Status: {0}" -f $Status) -Width $Width -Color $script:Ansi.Gray
    }

    Write-MOCBorderLine -Kind Bottom -Width $Width -Color $InputPaneBorder

    if (-not [string]::IsNullOrWhiteSpace($ResolvedFooterView)) {
        $PriorFooterView = $script:MOC_View
        try {
            $script:MOC_View = $ResolvedFooterView
            Write-Footer -NoComplete
        }
        finally {
            $script:MOC_View = $PriorFooterView
        }
    }

    Complete-MOCFrameRender
}


function Split-MOCEmbeddedOutputLines {
    # DESCRIPTION: Normalizes a single captured output object/string into safe physical lines.
    # WHY THIS MATTERS: PowerShell parser errors and ScriptStackTrace values can contain embedded
    # CR/LF characters. If those reach Write-PanelLine as one string, the terminal host renders the
    # embedded newline outside the pane and the text can overwrite MOC frame borders.

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Value) {
        return @('')
    }

    $Text = [string]$Value

    # Normalize line endings first, then split every embedded newline into its own
    # run-console record. Use -1 to preserve intentional blank lines.
    $Text = $Text -replace "`r`n", "`n"
    $Text = $Text -replace "`r", "`n"

    $Parts = $Text.Split([string[]]@("`n"), [System.StringSplitOptions]::None)
    if ($Parts.Count -eq 0) {
        return @('')
    }

    $Rows = New-Object System.Collections.Generic.List[string]
    foreach ($Part in $Parts) {
        # Remove non-printing control characters except tab. This prevents pasted
        # command errors or host control characters from moving the cursor outside
        # the MOC frame while preserving normal text output.
        $SafePart = ([string]$Part) -replace '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]', ''
        $Rows.Add($SafePart)
    }

    return @($Rows)
}

function Add-RunConsoleLine {
    # DESCRIPTION: Adds a line to the bounded run output buffer.
    # WHY THIS MATTERS: Keeps script output reviewable without allowing unbounded terminal scrolling.

    param(
        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[string]]$OutputBuffer,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [string]$Line
    )

    if ($null -eq $OutputBuffer) {
        $OutputBuffer = [System.Collections.Generic.List[string]]::new()
    }

    $SafeLines = @(Split-MOCEmbeddedOutputLines -Value $Line)

    foreach ($SafeLine in $SafeLines) {
        if ($null -eq $SafeLine) {
            $SafeLine = ''
        }

        # Child scripts sometimes emit their own menu-return guidance. MOC now renders
        # those controls once in the footer, so suppress exact duplicate guidance lines.
        $NormalizedRunLine = ([string]$SafeLine).Trim()
        if ($script:MOC_RunConsole_IsActive -and $NormalizedRunLine -match '^(Completed\.|Script Completed\.?)\s*Press\s+Enter\s+to\s+return.*menu\.?$') {
            continue
        }
        if ($script:MOC_RunConsole_IsActive -and $NormalizedRunLine -match '^Press\s+ENTER\s+to\s+return\s+to\s+menu\s*\|\s*PgUp/PgDn\s+review\s+output\.?$') {
            continue
        }

        $OutputBuffer.Add([string]$SafeLine)

        if (-not [string]::IsNullOrWhiteSpace([string]$script:MOC_ActiveTranscriptPath)) {
            try {
                $TranscriptLine = Remove-MOCOutputLineLevelMarker -Line ([string]$SafeLine)
                Add-MOCTranscriptText -Path ([string]$script:MOC_ActiveTranscriptPath) -Text ([string]$TranscriptLine)
            }
            catch {
                # Transcript logging must never interfere with the live run console.
            }
        }

        while ($OutputBuffer.Count -gt $script:MOC_RunOutputBufferSize) {
            $OutputBuffer.RemoveAt(0)
        }
    }
}


function New-MOCTranscriptPath {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Script
    )

    if (-not (Test-Path $TranscriptLogDir)) {
        New-Item -ItemType Directory -Path $TranscriptLogDir -Force | Out-Null
    }

    $Stamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
    $BaseName = [System.IO.Path]::GetFileNameWithoutExtension([string]$Script.Name)
    $SafeName = $BaseName -replace '[^a-zA-Z0-9._-]', '_'
    return (Join-Path $TranscriptLogDir ("MOC-Transcript-{0}-{1}.txt" -f $SafeName, $Stamp))
}

function Get-MOCScriptReportsRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Script
    )

    $Category = [string]$Script.Folder
    if ([string]::IsNullOrWhiteSpace($Category)) { $Category = 'Uncategorized' }

    $SafeCategory = $Category -replace '[\/:*?"<>|]', '_'
    $Path = Join-Path $ReportsRootDir $SafeCategory

    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }

    return $Path
}


function Get-MOCGraphPermissionListFromText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [string]$ErrorText,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object[]]$FallbackScopes
    )

    $Scopes = [System.Collections.Generic.List[string]]::new()

    if (-not [string]::IsNullOrWhiteSpace($ErrorText)) {
        $Patterns = @(
            'required Microsoft Graph permission\(s\):\s*(?<scopes>.*?)\s+to call this API',
            'required Microsoft Graph permission\(s\):\s*(?<scopes>.*?)(?:\.|$)',
            'principal does not have required Microsoft Graph permission\(s\):\s*(?<scopes>.*?)(?:\.|$)'
        )

        foreach ($Pattern in $Patterns) {
            $Match = [regex]::Match($ErrorText, $Pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
            if ($Match.Success) {
                $RawScopes = [string]$Match.Groups['scopes'].Value
                foreach ($Scope in ($RawScopes -split '[,;\s]+')) {
                    $Clean = $Scope.Trim().Trim('.')
                    if ($Clean -match '^[A-Za-z0-9.]+$' -and $Clean -match '\.(Read|ReadWrite|Manage|Write|Send|Access|Grant|FullControl|All)(\.All)?$|\.All$') {
                        [void]$Scopes.Add($Clean)
                    }
                }
                break
            }
        }

        if ($Scopes.Count -eq 0) {
            foreach ($Match in [regex]::Matches($ErrorText, '\b[A-Za-z][A-Za-z0-9]+(?:\.[A-Za-z][A-Za-z0-9]+)+\.All\b')) {
                [void]$Scopes.Add([string]$Match.Value)
            }
        }
    }

    if ($Scopes.Count -eq 0 -and $FallbackScopes) {
        foreach ($Scope in @($FallbackScopes)) {
            $Clean = [string]$Scope
            if (-not [string]::IsNullOrWhiteSpace($Clean) -and $Clean -notmatch '^(None|N/A|NotRequired)$') {
                [void]$Scopes.Add($Clean.Trim())
            }
        }
    }

    return @($Scopes | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
}

function Get-MOCGraphPermissionGuidanceLines {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [string]$ErrorText,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [pscustomobject]$Script
    )

    $LooksLikeGraphPermissionError = $false
    if (-not [string]::IsNullOrWhiteSpace($ErrorText)) {
        if ($ErrorText -match 'Authentication_MSGraphPermissionMissing') { $LooksLikeGraphPermissionError = $true }
        elseif ($ErrorText -match 'does not have required Microsoft Graph permission') { $LooksLikeGraphPermissionError = $true }
        elseif ($ErrorText -match 'Authorization_RequestDenied' -and $ErrorText -match 'permission|privilege|consent') { $LooksLikeGraphPermissionError = $true }
        elseif ($ErrorText -match 'Insufficient privileges|InsufficientPermissions|Forbidden' -and $ErrorText -match 'Graph|permission|privilege') { $LooksLikeGraphPermissionError = $true }
    }

    if (-not $LooksLikeGraphPermissionError) { return @() }

    $FallbackScopes = @()
    if ($null -ne $Script -and $Script.PSObject.Properties.Name -contains 'RequiredGraphAppScopes') {
        $FallbackScopes = @($Script.RequiredGraphAppScopes)
    }

    $Scopes = @(Get-MOCGraphPermissionListFromText -ErrorText $ErrorText -FallbackScopes $FallbackScopes)
    if ($Scopes.Count -eq 0) { $Scopes = @('Review the child script .REQUIREDGRAPHAPPSCOPES metadata') }

    $Lines = [System.Collections.Generic.List[string]]::new()
    [void]$Lines.Add('')
    [void]$Lines.Add('Microsoft Graph permission missing.')
    [void]$Lines.Add('')
    [void]$Lines.Add('This MOC child script requires Microsoft Graph application permission(s):')
    foreach ($Scope in $Scopes) {
        [void]$Lines.Add(('  - {0}' -f $Scope))
    }
    [void]$Lines.Add('')
    [void]$Lines.Add('How to grant the permission:')
    [void]$Lines.Add('  1. Open the Microsoft Entra admin center.')
    [void]$Lines.Add('  2. Go to Identity > Applications > App registrations.')
    [void]$Lines.Add('  3. Open the app registration used by MOC Graph authentication.')
    [void]$Lines.Add('  4. Go to API permissions > Add a permission > Microsoft Graph > Application permissions.')
    foreach ($Scope in $Scopes) {
        if ($Scope -notmatch '^Review ') { [void]$Lines.Add(('  5. Add: {0}' -f $Scope)) }
    }
    [void]$Lines.Add('  6. Select Grant admin consent for the tenant.')
    [void]$Lines.Add('  7. Restart or reconnect MOC Graph authentication, then rerun this child script.')
    [void]$Lines.Add('')

    return @($Lines)
}


function Get-MOCModuleInstallGuidanceLines {
    [CmdletBinding()]
    param([AllowNull()][string]$ErrorText)

    if ([string]::IsNullOrWhiteSpace($ErrorText)) { return @() }
    if ($ErrorText -notmatch "Required PowerShell module '([^']+)' is not installed") { return @() }

    $ModuleName = $matches[1]
    $Lines = [System.Collections.Generic.List[string]]::new()
    [void]$Lines.Add('')
    [void]$Lines.Add('Required PowerShell module missing.')
    [void]$Lines.Add('')
    [void]$Lines.Add(('This child script requires PowerShell module: {0}' -f $ModuleName))
    [void]$Lines.Add('')
    [void]$Lines.Add('What to do:')
    [void]$Lines.Add(('  1. Open PowerShell 7 as the same user running MOC.'))
    [void]$Lines.Add(('  2. Run: Install-Module {0} -Scope CurrentUser' -f $ModuleName))
    [void]$Lines.Add('  3. Close and reopen PowerShell, then rerun MOC.')
    [void]$Lines.Add('')
    return @($Lines)
}

# Graph permission prompts are intentionally not shown before every run.
# Missing Graph permissions are handled in the run console when Microsoft Graph returns an authorization error.

function Invoke-ScriptInRunConsole {
    # DESCRIPTION: Executes a child script while capturing common host/progress output into a bounded run console.
    # WHY THIS MATTERS: This prevents long-running audit/report scripts from pushing the MOC menu off-screen.

    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Script
    )

    Set-MOCChildOutputRenderer `
    -OutputRenderer {
        param(
            [string]$Message,
            [string]$Level
        )

        Add-RunConsoleLine `
            -OutputBuffer $script:MOC_RunConsole_Buffer `
            -Line $Message

        Render-MOCRunConsoleIfDue
    } `
    -StatusRenderer {
        param(
            [string]$Message,
            [string]$Level
        )

        Add-RunConsoleLine `
            -OutputBuffer $script:MOC_RunConsole_Buffer `
            -Line $Message

        Render-MOCRunConsoleIfDue
    }

    $OutputBuffer = [System.Collections.Generic.List[string]]::new()
    $script:MOC_RunConsole_Buffer = $OutputBuffer
    $script:MOC_RunConsole_ScriptName = $Script.Name
    $script:MOC_RunConsole_LastRender = Get-Date
    $script:MOC_RunConsole_ProgressActivity = ''
    $script:MOC_RunConsole_ProgressStatus = 'Initializing'
    $script:MOC_RunConsole_ProgressPercent = 0
    $script:MOC_RunConsole_ProgressOperation = ''
    $script:MOC_RunConsole_ProgressCompleted = $false
    $script:MOC_RunConsole_InputRequired = $false
    $script:MOC_RunConsole_InputPrompt = ''
    $script:MOC_RunConsole_InputValue = ''
    $script:MOC_RunConsole_InputHelp = 'No input required.'
    $script:MOC_RunConsole_IsActive = $true
    $script:MOC_RunConsole_HadPermissionError = $false
    $script:MOC_RunConsole_UserScrollOffset = $null

    $ChildRunStartTime = Get-Date
    $ExitCode = 0
    $MenuTranscriptStarted = $false
    $MenuTranscriptPath = New-MOCTranscriptPath -Script $Script
    $script:MOC_ActiveTranscriptPath = $MenuTranscriptPath
    $script:MOC_FrameTranscriptMirrorEnabled = $false
    $script:MOC_CurrentScriptCategory = [string]$Script.Folder
    $script:MOC_CurrentScriptReportsRoot = Get-MOCScriptReportsRoot -Script $Script

    if (Initialize-MOCManualTranscript -Path $MenuTranscriptPath -ScriptName $Script.Name) {
        $MenuTranscriptStarted = $true
    }
    else {
        Add-RunConsoleLine -OutputBuffer $OutputBuffer -Line ("WARNING: Could not initialize parent MOC transcript: {0}" -f $MenuTranscriptPath)
    }

    Add-RunConsoleLine -OutputBuffer $OutputBuffer -Line ("Transcript log: {0}" -f $MenuTranscriptPath)
    if (-not [string]::IsNullOrWhiteSpace([string]$script:MOC_SessionIndexPath)) {
        Add-RunConsoleLine -OutputBuffer $OutputBuffer -Line ("Session index: {0}" -f $script:MOC_SessionIndexPath)
    }
    Add-RunConsoleLine -OutputBuffer $OutputBuffer -Line ("Report root: Reports\{0}\" -f [string]$Script.Folder)
    Write-RunConsoleFrame -ScriptName $Script.Name -OutputBuffer $OutputBuffer -Status 'Initializing'

    try {

        Initialize-MOCSharedSession

        if (Test-MOCScriptRequiresPurview -Script $Script) {
            Add-RunConsoleLine -OutputBuffer $OutputBuffer -Line 'This child script requires Microsoft Purview / Security & Compliance. Connecting that session now...'
            Write-RunConsoleFrame -ScriptName $Script.Name -OutputBuffer $OutputBuffer -ScrollOffset (Get-MOCRunConsoleScrollMaxOffset -OutputBuffer $OutputBuffer) -Status 'Running'
            Initialize-MOCLazyPurviewSession -OutputBuffer $OutputBuffer -ScriptName $Script.Name | Out-Null
        }

        Add-RunConsoleLine -OutputBuffer $OutputBuffer -Line 'Shared MOC session ready.'
        Write-RunConsoleFrame -ScriptName $Script.Name -OutputBuffer $OutputBuffer -Status 'Running'

        # Menu-owned child output API. Child scripts should prefer Write-MOCStatusLine
        # and Update-MOCProgress over Write-Host, Write-Output, Clear-Host, or Write-Progress.
        function Render-MOCRunConsoleIfDue {
            param([switch]$Force)

            $Now = Get-Date
            $ReviewKeyHandled = Invoke-MOCRunConsoleLiveReviewKeys -OutputBuffer $script:MOC_RunConsole_Buffer

            if ($Force -or $ReviewKeyHandled -or (($Now - $script:MOC_RunConsole_LastRender).TotalMilliseconds -ge 1000)) {
                $MaxOffset = Get-MOCRunConsoleScrollMaxOffset -OutputBuffer $script:MOC_RunConsole_Buffer
                if ($null -ne $script:MOC_RunConsole_UserScrollOffset) {
                    try { $Offset = [Math]::Min($MaxOffset, [Math]::Max(0, [int]$script:MOC_RunConsole_UserScrollOffset)) } catch { $Offset = $MaxOffset }
                }
                else {
                    $Offset = $MaxOffset
                }
                Write-RunConsoleFrame -ScriptName $script:MOC_RunConsole_ScriptName -OutputBuffer $script:MOC_RunConsole_Buffer -ScrollOffset $Offset -Status 'Running'
                $script:MOC_RunConsole_LastRender = $Now
            }
        }

        function global:Write-MOCStatusLine {
            param(
                [Parameter(Mandatory = $false, ValueFromPipeline = $true, ValueFromRemainingArguments = $true)]
                [AllowNull()]
                [AllowEmptyCollection()]
                [object[]]$Message,

                [ValidateSet('Info','Success','Warning','Error','Critical','Action','Prompt','Header','Muted')]
                [string]$Level = 'Info',

                [switch]$NoRender
            )

            process {
                $Parts = @($Message | ForEach-Object {
                    if ($null -eq $_) { '' } else { [string]$_ }
                })
                $Text = ($Parts -join ' ')

                # Do not let blank separator lines trigger stricter Message
                # validation in old function definitions that may still be loaded.
                if ([string]::IsNullOrWhiteSpace($Text)) {
                    return
                }

                $Lines = $Text -split "`r?`n"
                foreach ($Line in $Lines) {
                    if (-not [string]::IsNullOrWhiteSpace($Line)) {
                        Add-RunConsoleLine -OutputBuffer $script:MOC_RunConsole_Buffer -Line $Line
                    }
                }
                if (-not $NoRender) { Render-MOCRunConsoleIfDue }
            }
        }

        function Write-MOCTranscriptLine {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory = $false, ValueFromPipeline = $true, ValueFromRemainingArguments = $true)]
                [AllowNull()]
                [AllowEmptyCollection()]
                [object[]]$Message
            )

            process {
                $Parts = @($Message | ForEach-Object {
                    if ($null -eq $_) { '' } else { [string]$_ }
                })
                $Text = ($Parts -join ' ')
                if ([string]::IsNullOrWhiteSpace($Text)) { return }

                $Path = [string]$script:MOC_ActiveTranscriptPath
                if ([string]::IsNullOrWhiteSpace($Path)) { return }

                try {
                    Add-MOCTranscriptText -Path $Path -Text $Text
                }
                catch {
                    # Do not let transcript-helper failures interfere with child execution.
                }
            }
        }


        function global:Write-MOCOutputLine {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory = $false, ValueFromPipeline = $true, ValueFromRemainingArguments = $true)]
                [AllowNull()]
                [AllowEmptyCollection()]
                [object[]]$Message,

                [ValidateSet('Info','Success','Warning','Error','Critical','Action','Prompt','Header','Muted')]
                [string]$Level = 'Info',

                [switch]$NoRender
            )

            process {
                $Parts = @($Message | ForEach-Object {
                    if ($null -eq $_) { '' } else { [string]$_ }
                })
                $Text = ($Parts -join ' ')

                # Unlike Write-MOCStatusLine, this is the child-script output-pane
                # writer.  It intentionally preserves blank separator lines and
                # forces a repaint by default so prompts/menus appear before input is
                # read.  Child scripts should use this for multi-line menus and use
                # Update-MOCProgress only for compact progress/status text.
                $Lines = $Text -split "`r?`n", -1
                foreach ($Line in $Lines) {
                    $OutputLine = New-MOCOutputLineWithLevel -Line $Line -Level $Level
                    Add-RunConsoleLine -OutputBuffer $script:MOC_RunConsole_Buffer -Line $OutputLine
                }

                if (-not $NoRender) { Render-MOCRunConsoleIfDue -Force }
            }
        }

        function Add-MOCOutputLine {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory = $false, ValueFromPipeline = $true, ValueFromRemainingArguments = $true)]
                [AllowNull()]
                [AllowEmptyCollection()]
                [object[]]$Message,

                [ValidateSet('Info','Success','Warning','Error','Critical','Action','Prompt','Header','Muted')]
                [string]$Level = 'Info',

                [switch]$NoRender
            )

            process {
                Write-MOCOutputLine -Message $Message -Level $Level -NoRender:$NoRender
            }
        }

        function Read-MOCMenuChoice {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory = $true)][string]$Title,
                [Parameter(Mandatory = $true)][string[]]$Options,
                [Parameter(Mandatory = $false)][string]$Prompt = 'Select an option',
                [Parameter(Mandatory = $false)][string[]]$ValidChoices = @('1','2','3'),
                [Parameter(Mandatory = $false)][switch]$AllowExit
            )

            $priorActivity = $script:MOC_RunConsole_ProgressActivity
            $priorStatus = $script:MOC_RunConsole_ProgressStatus
            $priorOperation = $script:MOC_RunConsole_ProgressOperation
            $priorPercent = $script:MOC_RunConsole_ProgressPercent
            $priorInputRequired = $script:MOC_RunConsole_InputRequired
            $priorInputPrompt = $script:MOC_RunConsole_InputPrompt
            $priorInputValue = $script:MOC_RunConsole_InputValue
            $priorInputHelp = $script:MOC_RunConsole_InputHelp
            $priorUserScrollOffset = $script:MOC_RunConsole_UserScrollOffset

            # Normalize child-provided choices. Child scripts should pass only the base prompt
            # text and non-exit choices. The parent owns q/Esc display and handling.
            $NormalizedChoices = [System.Collections.Generic.List[string]]::new()
            foreach ($Choice in @($ValidChoices)) {
                $ChoiceText = ([string]$Choice).Trim()
                if ([string]::IsNullOrWhiteSpace($ChoiceText)) { continue }
                if ($AllowExit -and $ChoiceText -match '^(q|esc|escape)$') { continue }
                if (-not ($NormalizedChoices | Where-Object { [string]::Equals($_, $ChoiceText, [System.StringComparison]::OrdinalIgnoreCase) })) {
                    $NormalizedChoices.Add($ChoiceText)
                }
            }
            if ($NormalizedChoices.Count -eq 0) { $NormalizedChoices.Add('1') }
            $ValidChoices = [string[]]$NormalizedChoices.ToArray()

            $PromptBase = ([string]$Prompt).Trim()
            while ($PromptBase -match '\s*\([^\)]*(?:q|Q|Esc|ESC|escape|Escape)[^\)]*\)\s*$') {
                $PromptBase = ($PromptBase -replace '\s*\([^\)]*(?:q|Q|Esc|ESC|escape|Escape)[^\)]*\)\s*$', '').TrimEnd()
            }
            if ([string]::IsNullOrWhiteSpace($PromptBase)) { $PromptBase = 'Select an option' }

            $ChoiceHelp = if ($AllowExit) { (($ValidChoices + @('q', 'Esc')) -join '/') } else { ($ValidChoices -join '/') }

            try {
                $script:MOC_RunConsole_ProgressActivity = 'Waiting for input'
                $script:MOC_RunConsole_ProgressStatus = 'Waiting for user selection.'
                $script:MOC_RunConsole_ProgressOperation = ('Select {0}.' -f $ChoiceHelp)
                $script:MOC_RunConsole_ProgressPercent = 0
                $script:MOC_RunConsole_InputRequired = $true
                $script:MOC_RunConsole_InputPrompt = $PromptBase
                $script:MOC_RunConsole_InputValue = ''
                $script:MOC_RunConsole_InputHelp = ('Press {0}.' -f $ChoiceHelp)

                # Render the menu body exactly once. Review scrolling while input is
                # active must only move the parent-owned viewport/Area 6 range; it
                # must not append another copy of the prompt/options to Area 5.
                $MenuLines = [System.Collections.Generic.List[string]]::new()
                $MenuLines.Add('')
                $MenuLines.Add($Title)
                $MenuLines.Add(('-' * $Title.Length))
                # Normalize menu presentation so child scripts may provide either
                # numbered or unnumbered labels. Preserve an existing numeric prefix;
                # otherwise assign the option's 1-based position. Detect an exit label
                # semantically so the parent never appends a duplicate or hardcoded
                # "4. Exit" entry to menus containing more than three choices.
                $DisplayOptions = [System.Collections.Generic.List[string]]::new()
                $HasDisplayedExitOption = $false
                for ($OptionIndex = 0; $OptionIndex -lt @($Options).Count; $OptionIndex++) {
                    $OptionText = ([string]@($Options)[$OptionIndex]).Trim()
                    if ([string]::IsNullOrWhiteSpace($OptionText)) { continue }

                    if ($OptionText -match '^\s*\d+\.\s+') {
                        $DisplayText = $OptionText
                    }
                    else {
                        $DisplayText = ('{0}. {1}' -f ($OptionIndex + 1), $OptionText)
                    }

                    if ($OptionText -match '(?i)\bexit\b.*\b(return|back)\b.*\bMOC\b|\breturn\b.*\bMOC\b') {
                        $HasDisplayedExitOption = $true
                    }
                    $DisplayOptions.Add($DisplayText)
                }

                foreach ($DisplayOption in $DisplayOptions) { $MenuLines.Add($DisplayOption) }
                if ($AllowExit -and -not $HasDisplayedExitOption) {
                    $MenuLines.Add('Q/Esc. Exit and return to MOC menu')
                }
                $MenuLines.Add('')
                $MenuLines.Add(('{0} ({1})' -f $PromptBase, $ChoiceHelp))

                foreach ($Line in $MenuLines) {
                    Add-RunConsoleLine -OutputBuffer $script:MOC_RunConsole_Buffer -Line $Line
                }
                Render-MOCRunConsoleIfDue -Force
                Start-Sleep -Milliseconds 100

                while ($true) {
                    $KeyInfo = [System.Console]::ReadKey($true)
                    Hide-MOCCursor

                    if (Move-MOCRunConsoleScrollOffset -KeyInfo $KeyInfo -OutputBuffer $script:MOC_RunConsole_Buffer) {
                        Render-MOCRunConsoleIfDue -Force
                        continue
                    }

                    if ($AllowExit -and ($KeyInfo.Key -eq [System.ConsoleKey]::Escape -or ([int][char]$KeyInfo.KeyChar -eq 27))) {
                        Add-RunConsoleLine -OutputBuffer $script:MOC_RunConsole_Buffer -Line 'Selected option: Exit and return to MOC menu'
                        Clear-MOCRunConsoleInputState -Help 'Selection cancelled. Returning to script.'
                        Render-MOCRunConsoleIfDue -Force
                        return 'ExitToMenu'
                    }

                    $ChoiceText = ([string]$KeyInfo.KeyChar).Trim()
                    $ChoiceLower = $ChoiceText.ToLowerInvariant()

                    if ($AllowExit -and ($ChoiceLower -eq 'q')) {
                        Add-RunConsoleLine -OutputBuffer $script:MOC_RunConsole_Buffer -Line 'Selected option: Exit and return to MOC menu'
                        Render-MOCRunConsoleIfDue -Force
                        return 'ExitToMenu'
                    }

                    if ($AllowExit -and $ChoiceText -notin $ValidChoices -and $ChoiceText -eq '4') {
                        Add-RunConsoleLine -OutputBuffer $script:MOC_RunConsole_Buffer -Line 'Selected option: Exit and return to MOC menu'
                        Render-MOCRunConsoleIfDue -Force
                        return 'ExitToMenu'
                    }

                    if ($ChoiceText -in $ValidChoices) {
                        Add-RunConsoleLine -OutputBuffer $script:MOC_RunConsole_Buffer -Line ('Selected option: {0}' -f $ChoiceText)
                        Clear-MOCRunConsoleInputState -Help 'Selection accepted. Waiting for script output or completion.'
                        Render-MOCRunConsoleIfDue -Force
                        return $ChoiceText
                    }

                    $InvalidHelp = if ($AllowExit) { (($ValidChoices + @('q', 'Esc')) -join ', ') } else { ($ValidChoices -join ', ') }
                    Add-RunConsoleLine -OutputBuffer $script:MOC_RunConsole_Buffer -Line ('Invalid selection. Please enter {0}.' -f $InvalidHelp)
                    Render-MOCRunConsoleIfDue -Force
                    Start-Sleep -Milliseconds 500
                }
            }
            finally {
                $script:MOC_FrameTranscriptMirrorEnabled = $false
                $script:MOC_RunConsole_IsActive = $false
                $script:MOC_RunConsole_ProgressActivity = $priorActivity
                $script:MOC_RunConsole_ProgressStatus = $priorStatus
                $script:MOC_RunConsole_ProgressOperation = $priorOperation
                $script:MOC_RunConsole_ProgressPercent = $priorPercent
                if ($priorInputRequired) {
                    $script:MOC_RunConsole_InputRequired = $priorInputRequired
                    $script:MOC_RunConsole_InputPrompt = $priorInputPrompt
                    $script:MOC_RunConsole_InputValue = $priorInputValue
                    $script:MOC_RunConsole_InputHelp = $priorInputHelp
                }
                else {
                    Clear-MOCRunConsoleInputState -Help 'Waiting for script output or completion.'
                }
                $script:MOC_RunConsole_UserScrollOffset = $priorUserScrollOffset
                Render-MOCRunConsoleIfDue -Force
            }
        }


        function Read-MOCYesNoPrompt {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory = $true)]
                [string]$Prompt
            )

            $PromptText = $Prompt
            if ($PromptText -notmatch '\[Y/N\]\s*$') { $PromptText = "$PromptText [Y/N]" }

            $priorActivity = $script:MOC_RunConsole_ProgressActivity
            $priorStatus = $script:MOC_RunConsole_ProgressStatus
            $priorOperation = $script:MOC_RunConsole_ProgressOperation
            $priorPercent = $script:MOC_RunConsole_ProgressPercent
            $priorInputRequired = $script:MOC_RunConsole_InputRequired
            $priorInputPrompt = $script:MOC_RunConsole_InputPrompt
            $priorInputValue = $script:MOC_RunConsole_InputValue
            $priorInputHelp = $script:MOC_RunConsole_InputHelp

            try {
                $script:MOC_RunConsole_ProgressActivity = 'Waiting for input'
                $script:MOC_RunConsole_ProgressStatus = $PromptText
                $script:MOC_RunConsole_ProgressOperation = 'Press Y or N to continue.'
                $script:MOC_RunConsole_InputRequired = $true
                $script:MOC_RunConsole_InputPrompt = $PromptText
                $script:MOC_RunConsole_InputValue = ''
                $script:MOC_RunConsole_InputHelp = 'Press Y or N to continue.'
                Render-MOCRunConsoleIfDue -Force

                while ($true) {
                    $key = [System.Console]::ReadKey($true)
                    Hide-MOCCursor

                    if (Move-MOCRunConsoleScrollOffset -KeyInfo $key -OutputBuffer $script:MOC_RunConsole_Buffer) {
                        Render-MOCRunConsoleIfDue -Force
                        continue
                    }

                    $ch = [string]$key.KeyChar

                    if ($ch -match '^[Yy]$') {
                        $script:MOC_RunConsole_ProgressOperation = 'Selection: Y'
                        Clear-MOCRunConsoleInputState -Help 'Last response accepted. Waiting for script output or completion.'
                        Render-MOCRunConsoleIfDue -Force
                        return $true
                    }

                    if ($ch -match '^[Nn]$') {
                        $script:MOC_RunConsole_ProgressOperation = 'Selection: N'
                        Clear-MOCRunConsoleInputState -Help 'Last response accepted. Waiting for script output or completion.'
                        Render-MOCRunConsoleIfDue -Force
                        return $false
                    }

                    $script:MOC_RunConsole_ProgressOperation = 'Invalid key. Press Y or N to continue.'
                    Render-MOCRunConsoleIfDue -Force
                }
            }
            finally {
                $script:MOC_RunConsole_ProgressActivity = $priorActivity
                $script:MOC_RunConsole_ProgressStatus = $priorStatus
                $script:MOC_RunConsole_ProgressOperation = $priorOperation
                $script:MOC_RunConsole_ProgressPercent = $priorPercent

                if ($priorInputRequired) {
                    $script:MOC_RunConsole_InputRequired = $priorInputRequired
                    $script:MOC_RunConsole_InputPrompt = $priorInputPrompt
                    $script:MOC_RunConsole_InputValue = $priorInputValue
                    $script:MOC_RunConsole_InputHelp = $priorInputHelp
                }
                else {
                    Clear-MOCRunConsoleInputState -Help 'Waiting for script output or completion.'
                }

                $script:MOC_RunConsole_UserScrollOffset = $null
                Render-MOCRunConsoleIfDue -Force
            }
        }

        function Read-MOCTextPrompt {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory = $true)]
                [string]$Prompt,

                [switch]$AllowEmpty,

                [switch]$AsSecureString
            )

            $priorActivity = $script:MOC_RunConsole_ProgressActivity
            $priorStatus = $script:MOC_RunConsole_ProgressStatus
            $priorOperation = $script:MOC_RunConsole_ProgressOperation
            $priorPercent = $script:MOC_RunConsole_ProgressPercent
            $priorInputRequired = $script:MOC_RunConsole_InputRequired
            $priorInputPrompt = $script:MOC_RunConsole_InputPrompt
            $priorInputValue = $script:MOC_RunConsole_InputValue
            $priorInputHelp = $script:MOC_RunConsole_InputHelp
            $value = ''

            try {
                $script:MOC_RunConsole_ProgressActivity = 'Waiting for input'
                $script:MOC_RunConsole_ProgressStatus = 'Waiting for technician input.'
                $script:MOC_RunConsole_ProgressOperation = 'Use the Input pane below.'
                $script:MOC_RunConsole_ProgressPercent = 0
                $script:MOC_RunConsole_InputRequired = $true
                $script:MOC_RunConsole_InputPrompt = $Prompt
                $script:MOC_RunConsole_InputValue = ''
                $script:MOC_RunConsole_InputHelp = if ($AllowEmpty) { 'Type a value, then press Enter. Esc submits a blank value.' } else { 'Type a value, then press Enter. Backspace edits.' }
                Render-MOCRunConsoleIfDue -Force

                while ($true) {
                    $key = [System.Console]::ReadKey($true)
                    Hide-MOCCursor

                    if (Move-MOCRunConsoleScrollOffset -KeyInfo $key -OutputBuffer $script:MOC_RunConsole_Buffer) {
                        Render-MOCRunConsoleIfDue -Force
                        continue
                    }

                    switch ($key.Key) {
                        'Enter' {
                            if ($AllowEmpty -or -not [string]::IsNullOrWhiteSpace($value)) {
                                $script:MOC_RunConsole_InputHelp = 'Input accepted.'
                                Clear-MOCRunConsoleInputState -Help 'Last input accepted. Waiting for script output or completion.'
                                Render-MOCRunConsoleIfDue -Force
                                if ($AsSecureString) {
                                    return (ConvertTo-SecureString $value -AsPlainText -Force)
                                }
                                return $value.Trim()
                            }
                            $script:MOC_RunConsole_InputHelp = 'Value required. Type a value, then press Enter.'
                            Render-MOCRunConsoleIfDue -Force
                            continue
                        }
                        'Backspace' {
                            if ($value.Length -gt 0) { $value = $value.Substring(0, $value.Length - 1) }
                        }
                        'Escape' {
                            if ($AllowEmpty) {
                                $script:MOC_RunConsole_InputHelp = 'Blank input accepted.'
                                Clear-MOCRunConsoleInputState -Help 'Blank input accepted. Waiting for script output or completion.'
                                Render-MOCRunConsoleIfDue -Force
                                if ($AsSecureString) {
                                    return (ConvertTo-SecureString '' -AsPlainText -Force)
                                }
                                return ''
                            }
                        }
                        default {
                            $ch = [string]$key.KeyChar
                            if (-not [char]::IsControl($key.KeyChar)) { $value += $ch }
                        }
                    }

                    if ($AsSecureString) {
                        $script:MOC_RunConsole_InputValue = ('*' * $value.Length)
                    }
                    else {
                        $script:MOC_RunConsole_InputValue = $value
                    }
                    Render-MOCRunConsoleIfDue -Force
                }
            }
            finally {
                $script:MOC_RunConsole_ProgressActivity = $priorActivity
                $script:MOC_RunConsole_ProgressStatus = $priorStatus
                $script:MOC_RunConsole_ProgressOperation = $priorOperation
                $script:MOC_RunConsole_ProgressPercent = $priorPercent
                if ($priorInputRequired) {
                    $script:MOC_RunConsole_InputRequired = $priorInputRequired
                    $script:MOC_RunConsole_InputPrompt = $priorInputPrompt
                    $script:MOC_RunConsole_InputValue = $priorInputValue
                    $script:MOC_RunConsole_InputHelp = $priorInputHelp
                }
                else {
                    Clear-MOCRunConsoleInputState -Help 'Waiting for script output or completion.'
                }
                $script:MOC_RunConsole_UserScrollOffset = $null
                Render-MOCRunConsoleIfDue -Force
            }
        }

        function Update-MOCProgress {
            param(
                [int]$Id = 0,
                [int]$ParentId = -1,
                [string]$Activity,
                [string]$Status,
                [int]$PercentComplete = -1,
                [switch]$Completed,
                [int]$SecondsRemaining = -1,
                [string]$CurrentOperation
            )

            if ($Completed) {
                $script:MOC_RunConsole_ProgressCompleted = $true
                Render-MOCRunConsoleIfDue -Force
                return
            }

            if (-not [string]::IsNullOrWhiteSpace($Activity)) { $script:MOC_RunConsole_ProgressActivity = $Activity }
            if (-not [string]::IsNullOrWhiteSpace($Status)) { $script:MOC_RunConsole_ProgressStatus = $Status }
            if (-not [string]::IsNullOrWhiteSpace($CurrentOperation)) { $script:MOC_RunConsole_ProgressOperation = $CurrentOperation }
            elseif ($PSBoundParameters.ContainsKey('CurrentOperation')) { $script:MOC_RunConsole_ProgressOperation = '' }

            if ($PercentComplete -ge 0) {
                if ($PercentComplete -gt 100) { $PercentComplete = 100 }
                $script:MOC_RunConsole_ProgressPercent = $PercentComplete
            }
            $script:MOC_RunConsole_ProgressCompleted = $false
            Render-MOCRunConsoleIfDue
        }

        # Compatibility shims for older child scripts. Parameters are intentionally object-typed
        # so blank color values do not fail argument binding before the proxy can run.
        function Write-Host {
            param(
                [Parameter(ValueFromRemainingArguments = $true)]
                [object[]]$Object,
                [AllowNull()][object]$ForegroundColor,
                [AllowNull()][object]$BackgroundColor,
                [switch]$NoNewline,
                [string]$Separator = ' '
            )

            $Line = ($Object | ForEach-Object { [string]$_ }) -join $Separator
            Write-MOCStatusLine -Message $Line
        }

        function Write-Progress {
            param(
                [int]$Id = 0,
                [int]$ParentId = -1,
                [string]$Activity,
                [string]$Status,
                [int]$PercentComplete = -1,
                [switch]$Completed,
                [int]$SecondsRemaining = -1,
                [string]$CurrentOperation
            )
            Update-MOCProgress -Id $Id -ParentId $ParentId -Activity $Activity -Status $Status -PercentComplete $PercentComplete -Completed:$Completed -SecondsRemaining $SecondsRemaining -CurrentOperation $CurrentOperation
        }

        function Clear-Host {
            # Child scripts should not clear or redraw the MOC run console directly.
            # IMPORTANT: Do not call Render-MOCRunConsoleIfDue here. Write-RunConsoleFrame
            # uses the real Clear-Host, and rendering from this proxy can recurse into
            # Write-RunConsoleFrame until PowerShell hits call-depth overflow.
            return
        }

        function Read-Host {
            param(
                [Parameter(Position = 0)]
                [AllowNull()]
                [string]$Prompt,

                [switch]$AsSecureString
            )

            $PromptText = if ([string]::IsNullOrWhiteSpace($Prompt)) { 'Input' } else { [string]$Prompt }

            # Route child-script Read-Host calls through the MOC-managed input pane.
            # This keeps prompts inside the bounded terminal UI on Linux instead of
            # printing raw "Selection >" prompts below the MOC frame.
            return Read-MOCTextPrompt -Prompt $PromptText -AsSecureString:$AsSecureString
        }

        function Test-MOCRenderArtifactLine {
            param([AllowNull()][string]$Line)

            if ([string]::IsNullOrWhiteSpace($Line)) { return $false }

            # If a host/transcript captures our menu redraw output, do not add it
            # back into the child output buffer. This prevents frames from nesting
            # inside frames during live progress updates.
            $plain = $Line -replace "`e\[[0-9;?]*[ -/]*[@-~]", ''
            if ($plain -match 'M365 Operations Console') { return $true }
            if ($plain -match '^\s*Home\s*>') { return $true }
            if ($plain -match '^\s*Running:\s+.+\.ps1') { return $true }
            if ($plain -match '^\s*Status:\s+Running\s*\|') { return $true }
            if ($plain -match '^\s*Lines:\s+\d+\s*\|\s*Showing:') { return $true }
            if ($plain -match '^(Reading|Writing)\s+(web\s+)?(response|request)\s+stream') { return $true }
            if ($plain -match '\bDownloaded:\s*\d+\s+Bytes\b') { return $true }
            if ($plain -match '^[\s┌┐└┘├┤─│]+$') { return $true }
            return $false
        }

        # Suppress native PowerShell progress records during child-script execution.
        # WHY THIS MATTERS: cmdlets such as Invoke-WebRequest, Invoke-RestMethod,
        # and some Microsoft Graph/EXO internals can write host-level progress like
        # "Reading web response stream [Downloaded: ...]" directly to the console.
        # Those records bypass normal output capture and can overwrite MOC's
        # line-status and input panes. Child scripts that call Write-Progress still
        # update MOC because the menu provides a local Write-Progress proxy below.
        $MOC_PreviousProgressPreference = $ProgressPreference
        $MOC_PreviousGlobalProgressPreference = $global:ProgressPreference
        $ProgressPreference = 'SilentlyContinue'
        $global:ProgressPreference = 'SilentlyContinue'

        # Stream pipeline, warning, verbose, information, and error output as it is produced.
        # Do not assign the full child output to a variable; doing so prevents live redraws and
        # can leave the run console looking blank while the child script is still working.
        & {
            $ProgressPreference = 'SilentlyContinue'
            $global:ProgressPreference = 'SilentlyContinue'
            . $Script.Path
        } *>&1 | ForEach-Object {
            $Item = $_
            if ($Item -is [System.Management.Automation.ErrorRecord]) {
                $ErrorText = [string]$Item.ToString()
                $PermissionGuidance = @(Get-MOCGraphPermissionGuidanceLines -ErrorText $ErrorText -Script $Script)
                if ($PermissionGuidance.Count -gt 0) {
                    $ExitCode = 1
                    $script:MOC_RunConsole_HadPermissionError = $true
                    foreach ($GuidanceLine in $PermissionGuidance) {
                        Add-RunConsoleLine -OutputBuffer $OutputBuffer -Line $GuidanceLine
                    }
                }
                else {
                    $ModuleGuidance = @(Get-MOCModuleInstallGuidanceLines -ErrorText $ErrorText)
                    if ($ModuleGuidance.Count -gt 0) {
                        $ExitCode = 1
                        foreach ($GuidanceLine in $ModuleGuidance) {
                            Add-RunConsoleLine -OutputBuffer $OutputBuffer -Line $GuidanceLine
                        }
                    }
                    else {
                        Add-RunConsoleLine -OutputBuffer $OutputBuffer -Line ("ERROR: {0}" -f $ErrorText)
                    }
                }
            }
            else {
                $Text = [string]$Item
                foreach ($Line in ($Text -split "`r?`n")) {
                    if (-not (Test-MOCRenderArtifactLine -Line $Line)) {
                        Add-RunConsoleLine -OutputBuffer $OutputBuffer -Line $Line
                    }
                }
            }
            Render-MOCRunConsoleIfDue
        }
    }
    catch {
        $ExitCode = 1
        $CaughtErrorText = [string]$_.Exception.Message
        $PermissionGuidance = @(Get-MOCGraphPermissionGuidanceLines -ErrorText $CaughtErrorText -Script $Script)
        $ModuleGuidance = @()
        if ($PermissionGuidance.Count -gt 0) {
            $script:MOC_RunConsole_HadPermissionError = $true
            foreach ($GuidanceLine in $PermissionGuidance) {
                Add-RunConsoleLine -OutputBuffer $OutputBuffer -Line $GuidanceLine
            }
        }
        else {
            $ModuleGuidance = @(Get-MOCModuleInstallGuidanceLines -ErrorText $CaughtErrorText)
            if ($ModuleGuidance.Count -gt 0) {
                foreach ($GuidanceLine in $ModuleGuidance) {
                    Add-RunConsoleLine -OutputBuffer $OutputBuffer -Line $GuidanceLine
                }
            }
            else {
                Add-RunConsoleLine -OutputBuffer $OutputBuffer -Line ''
                Add-RunConsoleLine -OutputBuffer $OutputBuffer -Line ("ERROR: {0}" -f $CaughtErrorText)
            }
        }
        if (-not $script:MOC_RunConsole_HadPermissionError -and $ModuleGuidance.Count -eq 0 -and $_.ScriptStackTrace) {
            Add-RunConsoleLine -OutputBuffer $OutputBuffer -Line $_.ScriptStackTrace
        }
    }

    try {
        if ($null -ne $MOC_PreviousProgressPreference) { $ProgressPreference = $MOC_PreviousProgressPreference }
        if ($null -ne $MOC_PreviousGlobalProgressPreference) { $global:ProgressPreference = $MOC_PreviousGlobalProgressPreference }
    }
    catch { }

    $script:MOC_RunConsole_IsActive = $false
    $script:MOC_RunConsole_UserScrollOffset = $null
    $script:MOC_RunConsole_InputRequired = $false
    $script:MOC_RunConsole_InputPrompt = ''
    $script:MOC_RunConsole_InputValue = ''
    $script:MOC_RunConsole_InputHelp = 'Press Enter to return to the MOC menu.'
    $FinalStatus = if ($ExitCode -eq 0) { 'Completed' } else { 'Failed' }
    $script:MOC_RunConsole_ProgressActivity = if ($ExitCode -eq 0) { 'Script Completed' } else { 'Script Failed' }
    $script:MOC_RunConsole_ProgressStatus = ''
    $script:MOC_RunConsole_ProgressPercent = if ($ExitCode -eq 0) { 100 } else { [Math]::Max([int]$script:MOC_RunConsole_ProgressPercent, 0) }
    $script:MOC_RunConsole_ProgressOperation = ''
    Add-RunConsoleLine -OutputBuffer $OutputBuffer -Line ''
    Add-RunConsoleLine -OutputBuffer $OutputBuffer -Line ("Transcript log saved to: {0}" -f $MenuTranscriptPath)

    $ScrollOffset = Get-MOCRunConsoleScrollMaxOffset -OutputBuffer $OutputBuffer

    while ($true) {
        Write-RunConsoleFrame -ScriptName $Script.Name -OutputBuffer $OutputBuffer -ScrollOffset $ScrollOffset -Status $FinalStatus

        $Key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        Hide-MOCCursor

        if ($Key.VirtualKeyCode -eq 13 -or $Key.Character -match '[Qq]') {
            break
        }
        elseif ($Key.VirtualKeyCode -eq 33) {
            $ScrollOffset = [Math]::Max(0, $ScrollOffset - $script:MOC_RunViewportHeight)
        }
        elseif ($Key.VirtualKeyCode -eq 34) {
            $ScrollOffset = [Math]::Min((Get-MOCRunConsoleScrollMaxOffset -OutputBuffer $OutputBuffer), $ScrollOffset + $script:MOC_RunViewportHeight)
        }
        elseif ($Key.VirtualKeyCode -eq 38) {
            $ScrollOffset = [Math]::Max(0, $ScrollOffset - 1)
        }
        elseif ($Key.VirtualKeyCode -eq 40) {
            $ScrollOffset = [Math]::Min((Get-MOCRunConsoleScrollMaxOffset -OutputBuffer $OutputBuffer), $ScrollOffset + 1)
        }
        elseif ($Key.VirtualKeyCode -eq 36) {
            $ScrollOffset = 0
        }
        elseif ($Key.VirtualKeyCode -eq 35) {
            $ScrollOffset = (Get-MOCRunConsoleScrollMaxOffset -OutputBuffer $OutputBuffer)
        }
    }

    $script:MOC_FrameTranscriptMirrorEnabled = $false
    if ($MenuTranscriptStarted) {
        Complete-MOCManualTranscript -Path $MenuTranscriptPath
    }
    $script:MOC_ActiveTranscriptPath = $null
    $script:MOC_CurrentScriptCategory = $null
    $ChildRunEndTime = Get-Date
    Add-MOCSessionIndexEntry -Script $Script -Status $FinalStatus -StartTime $ChildRunStartTime -EndTime $ChildRunEndTime -ExitCode $ExitCode -TranscriptPath $MenuTranscriptPath -OutputBuffer $OutputBuffer

    $script:MOC_CurrentScriptReportsRoot = $null
    Clear-MOCChildOutputRenderer

    return $ExitCode
}




function Enable-MOCBracketedPasteMode {
    # DESCRIPTION: Requests bracketed-paste mode while MOC Terminal is active.
    # WHY THIS MATTERS: Supported terminal hosts wrap pasted text in paste markers so
    # MOC can buffer multiline script blocks as one command instead of executing each line.

    try {
        if (-not [bool]$script:MOC_BracketedPasteModeEnabled) {
            [Console]::Out.Write("$($script:Esc)[?2004h")
            [Console]::Out.Flush()
            $script:MOC_BracketedPasteModeEnabled = $true
        }
    }
    catch { }
}

function Disable-MOCBracketedPasteMode {
    try {
        if ([bool]$script:MOC_BracketedPasteModeEnabled) {
            [Console]::Out.Write("$($script:Esc)[?2004l")
            [Console]::Out.Flush()
        }
    }
    catch { }
    finally {
        $script:MOC_BracketedPasteModeEnabled = $false
    }
}

function Test-MOCKeyBatchStartsWithChars {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.Generic.List[System.ConsoleKeyInfo]]$KeyBatch,

        [Parameter(Mandatory = $true)]
        [int]$StartIndex,

        [Parameter(Mandatory = $true)]
        [string]$Chars
    )

    if ([string]::IsNullOrEmpty($Chars)) { return $false }
    if (($StartIndex + $Chars.Length) -gt $KeyBatch.Count) { return $false }

    for ($i = 0; $i -lt $Chars.Length; $i++) {
        if ([char]$KeyBatch[$StartIndex + $i].KeyChar -ne [char]$Chars[$i]) {
            return $false
        }
    }

    return $true
}

function Test-MOCTerminalCommandComplete {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [string]$CommandText
    )

    if ([string]::IsNullOrWhiteSpace($CommandText)) { return $true }

    try {
        $Tokens = $null
        $ParseErrors = $null
        [System.Management.Automation.Language.Parser]::ParseInput($CommandText, [ref]$Tokens, [ref]$ParseErrors) | Out-Null

        foreach ($ParseError in @($ParseErrors)) {
            $ErrorId = [string]$ParseError.ErrorId
            $Message = [string]$ParseError.Message

            if ($ErrorId -match '(?i)(Incomplete|Terminator|MissingEnd|EndCurly|EndParenthesis|EndSquare)' -or
                $Message -match '(?i)(incomplete|missing closing|terminator|missing end|unexpected end)') {
                return $false
            }
        }

        return $true
    }
    catch {
        # If the parser check itself fails, do not block execution. The command
        # execution path will surface the actual error inside the MOC output pane.
        return $true
    }
}


function Get-MOCTerminalParseIssues {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [string]$CommandText
    )

    $Issues = [System.Collections.Generic.List[object]]::new()
    if ([string]::IsNullOrWhiteSpace($CommandText)) { return @($Issues) }

    try {
        $Tokens = $null
        $ParseErrors = $null
        [System.Management.Automation.Language.Parser]::ParseInput($CommandText, [ref]$Tokens, [ref]$ParseErrors) | Out-Null

        foreach ($ParseError in @($ParseErrors)) {
            $LineNumber = 1
            $ColumnNumber = 1
            try { $LineNumber = [int]$ParseError.Extent.StartLineNumber } catch { }
            try { $ColumnNumber = [int]$ParseError.Extent.StartColumnNumber } catch { }
            $Issues.Add([pscustomobject]@{
                Line    = [Math]::Max(1, $LineNumber)
                Column  = [Math]::Max(1, $ColumnNumber)
                Message = [string]$ParseError.Message
                ErrorId = [string]$ParseError.ErrorId
            })
        }
    }
    catch {
        $Issues.Add([pscustomobject]@{
            Line    = 1
            Column  = 1
            Message = [string]$_.Exception.Message
            ErrorId = 'ParserInvocationFailed'
        })
    }

    return @($Issues)
}

function Get-MOCTerminalEditorTextFromLines {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$Lines
    )

    if ($null -eq $Lines) { return '' }
    return (@($Lines) -join [Environment]::NewLine)
}


function ConvertTo-MOCSyntaxHighlightedPowerShellLine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Line
    )

    if ($null -eq $Line) { return '' }
    $PlainLine = [string]$Line
    if ($PlainLine.Length -eq 0) { return '' }

    $Reset   = $script:Ansi.Reset
    $Cyan    = $script:Ansi.Cyan
    $Green   = $script:Ansi.Green
    $Yellow  = $script:Ansi.Yellow
    $Blue    = $script:Ansi.Blue
    $Magenta = $script:Ansi.Magenta
    $Gray    = $script:Ansi.DarkGray

    try {
        $Tokens = $null
        $ParseErrors = $null
        [System.Management.Automation.Language.Parser]::ParseInput($PlainLine, [ref]$Tokens, [ref]$ParseErrors) | Out-Null

        if ($null -eq $Tokens -or @($Tokens).Count -eq 0) {
            return $PlainLine
        }

        $Builder = [System.Text.StringBuilder]::new()
        $Cursor = 0

        foreach ($Token in @($Tokens | Sort-Object { $_.Extent.StartColumnNumber })) {
            $Start = [Math]::Max(0, [int]$Token.Extent.StartColumnNumber - 1)
            $End = [Math]::Max($Start, [int]$Token.Extent.EndColumnNumber - 1)
            if ($Start -gt $PlainLine.Length) { continue }
            if ($End -gt $PlainLine.Length) { $End = $PlainLine.Length }
            if ($Start -lt $Cursor) { continue }

            if ($Start -gt $Cursor) {
                [void]$Builder.Append($PlainLine.Substring($Cursor, $Start - $Cursor))
            }

            $TokenText = if ($End -gt $Start) { $PlainLine.Substring($Start, $End - $Start) } else { '' }
            $Kind = [string]$Token.Kind
            $Color = ''

            switch -Regex ($Kind) {
                '^(Function|Param|If|Else|ElseIf|For|Foreach|While|Do|Switch|Return|Break|Continue|Try|Catch|Finally|Begin|Process|End|Filter|Class|Enum|Using|Data|DynamicParam)$' { $Color = $Cyan; break }
                '^(Variable|SplattedVariable)$' { $Color = $Green; break }
                '^(StringExpandable|StringLiteral|HereStringExpandable|HereStringLiteral|ExpandableStringExpression)$' { $Color = $Yellow; break }
                '^(Number)$' { $Color = $Blue; break }
                '^(Parameter)$' { $Color = $Magenta; break }
                '^(Comment)$' { $Color = $Gray; break }
                default { $Color = '' }
            }

            if ([string]::IsNullOrEmpty($Color)) {
                [void]$Builder.Append($TokenText)
            }
            else {
                [void]$Builder.Append($Color)
                [void]$Builder.Append($TokenText)
                [void]$Builder.Append($Reset)
            }

            $Cursor = $End
        }

        if ($Cursor -lt $PlainLine.Length) {
            [void]$Builder.Append($PlainLine.Substring($Cursor))
        }

        return $Builder.ToString()
    }
    catch {
        return $PlainLine
    }
}

function Get-MOCTerminalPastePreviewLines {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$Lines,

        [Parameter(Mandatory = $false)]
        [int]$SelectedIndex = 0,

        [Parameter(Mandatory = $false)]
        [int]$ScrollOffset = 0,

        [Parameter(Mandatory = $false)]
        [int]$MaxPreviewLines = 10,

        [Parameter(Mandatory = $false)]
        [int]$MaxWidth = 100,

        [Parameter(Mandatory = $false)]
        [object[]]$ParseIssues = @()
    )

    $Rows = [System.Collections.Generic.List[string]]::new()
    $LineCount = [Math]::Max(1, @($Lines).Count)
    if ($SelectedIndex -lt 0) { $SelectedIndex = 0 }
    if ($SelectedIndex -ge $LineCount) { $SelectedIndex = $LineCount - 1 }
    if ($ScrollOffset -lt 0) { $ScrollOffset = 0 }
    $MaxScroll = [Math]::Max(0, $LineCount - $MaxPreviewLines)
    if ($ScrollOffset -gt $MaxScroll) { $ScrollOffset = $MaxScroll }

    $FirstIssue = @($ParseIssues | Select-Object -First 1)
    if ($FirstIssue.Count -gt 0) {
        $Issue = $FirstIssue[0]
        $IssueText = ('Parser: line {0}, col {1}: {2}' -f $Issue.Line, $Issue.Column, $Issue.Message)
        if ($IssueText.Length -gt $MaxWidth) { $IssueText = $IssueText.Substring(0, [Math]::Max(0, $MaxWidth - 3)) + '...' }
        $Rows.Add($IssueText)
    }

    $Rows.Add(('Lines: {0} | Selected: {1} | Scroll: {2}-{3}' -f $LineCount, ($SelectedIndex + 1), ($ScrollOffset + 1), ([Math]::Min($LineCount, $ScrollOffset + $MaxPreviewLines))))
    $Rows.Add('Preview:')

    $EndIndex = [Math]::Min($LineCount - 1, $ScrollOffset + $MaxPreviewLines - 1)
    for ($i = $ScrollOffset; $i -le $EndIndex; $i++) {
        $Marker = if ($i -eq $SelectedIndex) { '>' } else { ' ' }
        $LineText = if ($null -eq $Lines[$i]) { '' } else { [string]$Lines[$i] }
        $Available = [Math]::Max(10, $MaxWidth - 9)
        if ($LineText.Length -gt $Available) {
            $LineText = $LineText.Substring(0, [Math]::Max(0, $Available - 3)) + '...'
        }
        $RenderedLineText = ConvertTo-MOCSyntaxHighlightedPowerShellLine -Line $LineText
        $Rows.Add(('{0}{1,4}: {2}' -f $Marker, ($i + 1), $RenderedLineText))
    }

    if ($EndIndex -lt ($LineCount - 1)) {
        $Rows.Add(('  ... {0} more line(s) below ...' -f (($LineCount - 1) - $EndIndex)))
    }

    return @($Rows)
}

function Set-MOCTerminalPasteEditorDisplay {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$Lines,

        [Parameter(Mandatory = $false)]
        [int]$SelectedIndex = 0,

        [Parameter(Mandatory = $false)]
        [int]$ScrollOffset = 0,

        [Parameter(Mandatory = $false)]
        [object[]]$ParseIssues = @(),

        [Parameter(Mandatory = $false)]
        [string]$Prompt = 'MOC PS'
    )

    $InnerWidth = [Math]::Max(40, (Get-TerminalWidth) - 8)
    $LineCount = [Math]::Max(1, @($Lines).Count)
    $CharCount = ([string](Get-MOCTerminalEditorTextFromLines -Lines $Lines)).Length

    $script:MOC_RunConsole_InputRequired = $true
    $script:MOC_RunConsole_InputPrompt = $Prompt
    $script:MOC_RunConsole_InputValue = ('[Paste editor: {0} line(s), {1} char(s)]' -f $LineCount, $CharCount)
    $script:MOC_RunConsole_InputPreviewLines = @(Get-MOCTerminalPastePreviewLines -Lines $Lines -SelectedIndex $SelectedIndex -ScrollOffset $ScrollOffset -MaxPreviewLines 10 -MaxWidth $InnerWidth -ParseIssues $ParseIssues)
    $script:MOC_RunConsole_InputHelp = 'Up/Down line, PgUp/PgDn page, E edit, D delete, I insert below, Enter/F5 run, Esc cancel.'
    $script:MOC_RunConsole_ProgressActivity = 'MOC Terminal'
    $script:MOC_RunConsole_ProgressStatus = 'Paste editor active.'
    if (@($ParseIssues).Count -gt 0) {
        $script:MOC_RunConsole_ProgressOperation = 'Parser issue detected. Fix the selected line, then run again.'
    }
    else {
        $script:MOC_RunConsole_ProgressOperation = 'Review or edit the pasted block before running it.'
    }
    $script:MOC_RunConsole_ProgressPercent = 0
}

function Read-MOCTerminalInlineInput {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$ScriptName = 'MOC Terminal',

        [Parameter(Mandatory = $true)]
        [string]$Prompt,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [string]$InitialValue = '',

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$OutputBuffer = $null,

        [Parameter(Mandatory = $false)]
        [string]$Help = 'Type value, Enter saves, Esc cancels.'
    )

    if ($OutputBuffer -isnot [System.Collections.Generic.List[string]]) {
        $OutputBuffer = [System.Collections.Generic.List[string]]::new()
    }

    $Value = if ($null -eq $InitialValue) { '' } else { [string]$InitialValue }

    while ($true) {
        $script:MOC_RunConsole_InputRequired = $true
        $script:MOC_RunConsole_InputPrompt = $Prompt
        $script:MOC_RunConsole_InputValue = $Value
        $script:MOC_RunConsole_InputPreviewLines = @()
        $script:MOC_RunConsole_InputHelp = $Help
        $ScrollOffset = Get-MOCRunConsoleScrollMaxOffset -OutputBuffer $OutputBuffer
        Write-RunConsoleFrame -ScriptName $ScriptName -OutputBuffer $OutputBuffer -ScrollOffset $ScrollOffset -Status 'Running'

        $KeyInfo = [System.Console]::ReadKey($true)
        Hide-MOCCursor

        switch ($KeyInfo.Key) {
            'Enter' { return [pscustomobject]@{ Cancelled = $false; Value = $Value } }
            'Escape' { return [pscustomobject]@{ Cancelled = $true; Value = $InitialValue } }
            'Backspace' {
                if ($Value.Length -gt 0) { $Value = $Value.Substring(0, $Value.Length - 1) }
            }
            'Tab' { $Value += "`t" }
            default {
                if (-not [char]::IsControl($KeyInfo.KeyChar)) { $Value += [string]$KeyInfo.KeyChar }
            }
        }
    }
}

function Invoke-MOCTerminalPasteEditor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [string]$CommandText,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$OutputBuffer = $null,

        [Parameter(Mandatory = $false)]
        [string]$Prompt = 'MOC PS'
    )

    if ($OutputBuffer -isnot [System.Collections.Generic.List[string]]) {
        $OutputBuffer = [System.Collections.Generic.List[string]]::new()
    }

    $Normalized = if ($null -eq $CommandText) { '' } else { [string]$CommandText }
    $Normalized = $Normalized -replace "`r`n", "`n"
    $Normalized = $Normalized -replace "`r", "`n"
    $Lines = [System.Collections.Generic.List[string]]::new()
    foreach ($Line in $Normalized.Split([string[]]@("`n"), [System.StringSplitOptions]::None)) {
        $Lines.Add([string]$Line)
    }
    while ($Lines.Count -gt 1 -and [string]::IsNullOrWhiteSpace($Lines[$Lines.Count - 1])) {
        $Lines.RemoveAt($Lines.Count - 1)
    }
    if ($Lines.Count -eq 0) { $Lines.Add('') }

    $SelectedIndex = 0
    $ScrollOffset = 0
    $PreviewPageSize = 10
    $ParseIssues = @(Get-MOCTerminalParseIssues -CommandText (Get-MOCTerminalEditorTextFromLines -Lines ([string[]]@($Lines))))
    if ($ParseIssues.Count -gt 0) {
        $SelectedIndex = [Math]::Max(0, [Math]::Min($Lines.Count - 1, [int]$ParseIssues[0].Line - 1))
        $ScrollOffset = [Math]::Max(0, $SelectedIndex - 3)
    }

    while ($true) {
        if ($SelectedIndex -lt 0) { $SelectedIndex = 0 }
        if ($SelectedIndex -ge $Lines.Count) { $SelectedIndex = $Lines.Count - 1 }
        if ($ScrollOffset -gt $SelectedIndex) { $ScrollOffset = $SelectedIndex }
        if ($SelectedIndex -ge ($ScrollOffset + $PreviewPageSize)) { $ScrollOffset = $SelectedIndex - $PreviewPageSize + 1 }
        if ($ScrollOffset -lt 0) { $ScrollOffset = 0 }
        $MaxScroll = [Math]::Max(0, $Lines.Count - $PreviewPageSize)
        if ($ScrollOffset -gt $MaxScroll) { $ScrollOffset = $MaxScroll }

        Set-MOCTerminalPasteEditorDisplay -Lines ([string[]]@($Lines)) -SelectedIndex $SelectedIndex -ScrollOffset $ScrollOffset -ParseIssues $ParseIssues -Prompt $Prompt
        $FrameScroll = Get-MOCRunConsoleScrollMaxOffset -OutputBuffer $OutputBuffer
        Write-RunConsoleFrame -ScriptName 'MOC Terminal' -OutputBuffer $OutputBuffer -ScrollOffset $FrameScroll -Status 'Running'

        $KeyInfo = [System.Console]::ReadKey($true)
        Hide-MOCCursor

        switch ($KeyInfo.Key) {
            'UpArrow'   { $SelectedIndex-- }
            'DownArrow' { $SelectedIndex++ }
            'PageUp'    { $SelectedIndex -= $PreviewPageSize }
            'PageDown'  { $SelectedIndex += $PreviewPageSize }
            'Home'      { $SelectedIndex = 0 }
            'End'       { $SelectedIndex = $Lines.Count - 1 }
            'Escape' {
                $script:MOC_RunConsole_InputPreviewLines = @()
                return [pscustomobject]@{ Action = 'Cancel'; Text = '' }
            }
            'F5' {
                $Text = Get-MOCTerminalEditorTextFromLines -Lines ([string[]]@($Lines))
                $ParseIssues = @(Get-MOCTerminalParseIssues -CommandText $Text)
                if ($ParseIssues.Count -gt 0) {
                    $SelectedIndex = [Math]::Max(0, [Math]::Min($Lines.Count - 1, [int]$ParseIssues[0].Line - 1))
                    $ScrollOffset = [Math]::Max(0, $SelectedIndex - 3)
                    continue
                }
                $script:MOC_RunConsole_InputPreviewLines = @()
                return [pscustomobject]@{ Action = 'Run'; Text = $Text }
            }
            'Enter' {
                $Text = Get-MOCTerminalEditorTextFromLines -Lines ([string[]]@($Lines))
                $ParseIssues = @(Get-MOCTerminalParseIssues -CommandText $Text)
                if ($ParseIssues.Count -gt 0) {
                    $SelectedIndex = [Math]::Max(0, [Math]::Min($Lines.Count - 1, [int]$ParseIssues[0].Line - 1))
                    $ScrollOffset = [Math]::Max(0, $SelectedIndex - 3)
                    continue
                }
                $script:MOC_RunConsole_InputPreviewLines = @()
                return [pscustomobject]@{ Action = 'Run'; Text = $Text }
            }
            default {
                $KeyChar = [string]$KeyInfo.KeyChar
                if ($KeyChar -match '^[Ee]$') {
                    $EditResult = Read-MOCTerminalInlineInput -Prompt ('Edit line {0}' -f ($SelectedIndex + 1)) -InitialValue $Lines[$SelectedIndex] -OutputBuffer $OutputBuffer -Help 'Enter saves this line. Esc cancels edit.'
                    if (-not $EditResult.Cancelled) {
                        $Lines[$SelectedIndex] = [string]$EditResult.Value
                        $ParseIssues = @(Get-MOCTerminalParseIssues -CommandText (Get-MOCTerminalEditorTextFromLines -Lines ([string[]]@($Lines))))
                    }
                }
                elseif ($KeyChar -match '^[Dd]$') {
                    if ($Lines.Count -gt 1) {
                        $Lines.RemoveAt($SelectedIndex)
                        if ($SelectedIndex -ge $Lines.Count) { $SelectedIndex = $Lines.Count - 1 }
                        $ParseIssues = @(Get-MOCTerminalParseIssues -CommandText (Get-MOCTerminalEditorTextFromLines -Lines ([string[]]@($Lines))))
                    }
                }
                elseif ($KeyChar -match '^[Ii]$') {
                    $InsertResult = Read-MOCTerminalInlineInput -Prompt ('Insert after line {0}' -f ($SelectedIndex + 1)) -InitialValue '' -OutputBuffer $OutputBuffer -Help 'Enter inserts new line below selection. Esc cancels insert.'
                    if (-not $InsertResult.Cancelled) {
                        $Lines.Insert(($SelectedIndex + 1), [string]$InsertResult.Value)
                        $SelectedIndex++
                        $ParseIssues = @(Get-MOCTerminalParseIssues -CommandText (Get-MOCTerminalEditorTextFromLines -Lines ([string[]]@($Lines))))
                    }
                }
            }
        }
    }
}

function Set-MOCTerminalInputDisplay {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [string]$CommandText,

        [Parameter(Mandatory = $false)]
        [string]$Prompt = 'MOC PS',

        [Parameter(Mandatory = $false)]
        [string]$Help = 'Type a PowerShell command, then press Enter. Paste multiline blocks normally.'
    )

    $Text = if ($null -eq $CommandText) { '' } else { [string]$CommandText }
    $Lines = @($Text -split "`r?`n", -1)
    $LineCount = [Math]::Max(1, $Lines.Count)
    $LastLine = if ($Lines.Count -gt 0) { [string]$Lines[$Lines.Count - 1] } else { '' }

    $script:MOC_RunConsole_InputPreviewLines = @()

    if ($LineCount -gt 1) {
        $script:MOC_RunConsole_InputPrompt = $Prompt
        $script:MOC_RunConsole_InputValue = ('[Multiline command: {0} lines]' -f $LineCount)
        $script:MOC_RunConsole_InputHelp = 'Multiline input buffered. Paste editor opens for pasted blocks; Enter runs complete manual blocks.'
    }
    else {
        $script:MOC_RunConsole_InputPrompt = $Prompt
        $script:MOC_RunConsole_InputValue = $Text
        $script:MOC_RunConsole_InputHelp = $Help
    }
}

function Read-MOCTerminalCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$OutputBuffer = $null,

        [Parameter(Mandatory = $false)]
        [string]$Prompt = 'MOC PS'
    )

    if ($OutputBuffer -isnot [System.Collections.Generic.List[string]]) {
        $OutputBuffer = [System.Collections.Generic.List[string]]::new()
    }

    $Command = ''
    $script:MOC_RunConsole_InputRequired = $true
    $script:MOC_RunConsole_ProgressActivity = 'MOC Terminal'
    $script:MOC_RunConsole_ProgressStatus = 'Waiting for command.'
    $script:MOC_RunConsole_ProgressOperation = 'Command entry is contained inside the MOC Input pane.'
    $script:MOC_RunConsole_ProgressPercent = 0
    Set-MOCTerminalInputDisplay -CommandText $Command -Prompt $Prompt

    while ($true) {
        $MaxOffset = Get-MOCRunConsoleScrollMaxOffset -OutputBuffer $OutputBuffer
        if ($null -ne $script:MOC_RunConsole_UserScrollOffset) {
            try { $ScrollOffset = [Math]::Min($MaxOffset, [Math]::Max(0, [int]$script:MOC_RunConsole_UserScrollOffset)) } catch { $ScrollOffset = $MaxOffset }
        }
        else {
            $ScrollOffset = $MaxOffset
        }
        Write-RunConsoleFrame -ScriptName 'MOC Terminal' -OutputBuffer $OutputBuffer -ScrollOffset $ScrollOffset -Status 'Running'

        $FirstKeyInfo = [System.Console]::ReadKey($true)
        Hide-MOCCursor

        if (Move-MOCRunConsoleScrollOffset -KeyInfo $FirstKeyInfo -OutputBuffer $OutputBuffer) {
            continue
        }

        # Important: pasted multiline text arrives as a rapid sequence of key events.
        # Drain the pending queue, then process the whole batch before redrawing.
        # v1.13.29 also supports terminal bracketed paste markers ESC[200~ and
        # ESC[201~ so pasted script blocks are buffered as one command transaction.
        $KeyBatch = [System.Collections.Generic.List[System.ConsoleKeyInfo]]::new()
        [void]$KeyBatch.Add($FirstKeyInfo)

        $IdleSince = Get-Date
        while ($true) {
            $ReadAny = $false
            try {
                while ([System.Console]::KeyAvailable) {
                    [void]$KeyBatch.Add([System.Console]::ReadKey($true))
                    $ReadAny = $true
                    if ($KeyBatch.Count -ge 40000) { break }
                }
            }
            catch {
                break
            }

            if ($KeyBatch.Count -ge 40000) { break }

            if ($ReadAny) {
                $IdleSince = Get-Date
                continue
            }

            Start-Sleep -Milliseconds 15
            $IdleMilliseconds = ((Get-Date) - $IdleSince).TotalMilliseconds
            if ($IdleMilliseconds -ge 140) { break }
        }

        $BatchLookedLikePaste = ($KeyBatch.Count -gt 1)
        $InBracketedPaste = $false
        $SawBracketedPaste = $false

        for ($KeyIndex = 0; $KeyIndex -lt $KeyBatch.Count; $KeyIndex++) {
            $KeyInfo = $KeyBatch[$KeyIndex]
            $HasMoreBatchInput = ($KeyIndex -lt ($KeyBatch.Count - 1))

            # Bracketed paste start: ESC [ 2 0 0 ~
            if (($KeyInfo.Key -eq [System.ConsoleKey]::Escape -or [int][char]$KeyInfo.KeyChar -eq 27) -and
                (Test-MOCKeyBatchStartsWithChars -KeyBatch $KeyBatch -StartIndex ($KeyIndex + 1) -Chars '[200~')) {
                $InBracketedPaste = $true
                $SawBracketedPaste = $true
                $BatchLookedLikePaste = $true
                $KeyIndex += 5
                $script:MOC_RunConsole_ProgressStatus = 'Buffering pasted command.'
                $script:MOC_RunConsole_ProgressOperation = 'Bracketed paste is being collected before execution.'
                continue
            }

            # Bracketed paste end: ESC [ 2 0 1 ~
            if (($KeyInfo.Key -eq [System.ConsoleKey]::Escape -or [int][char]$KeyInfo.KeyChar -eq 27) -and
                (Test-MOCKeyBatchStartsWithChars -KeyBatch $KeyBatch -StartIndex ($KeyIndex + 1) -Chars '[201~')) {
                $InBracketedPaste = $false
                $KeyIndex += 5
                $script:MOC_RunConsole_ProgressStatus = 'Pasted command buffered.'
                $script:MOC_RunConsole_ProgressOperation = 'Review the pasted command, then press Enter to run it.'
                continue
            }

            if ($InBracketedPaste) {
                switch ($KeyInfo.Key) {
                    'Enter' { $Command += [Environment]::NewLine }
                    'Tab'   { $Command += "`t" }
                    default {
                        if (-not [char]::IsControl($KeyInfo.KeyChar)) {
                            $Command += [string]$KeyInfo.KeyChar
                        }
                    }
                }
                continue
            }

            switch ($KeyInfo.Key) {
                'Enter' {
                    $ForceNewLine = $false
                    if (($KeyInfo.Modifiers -band [System.ConsoleModifiers]::Shift) -or
                        ($KeyInfo.Modifiers -band [System.ConsoleModifiers]::Control)) {
                        $ForceNewLine = $true
                    }

                    $CommandIsComplete = Test-MOCTerminalCommandComplete -CommandText $Command

                    if ($HasMoreBatchInput -or $ForceNewLine -or -not $CommandIsComplete) {
                        $Command += [Environment]::NewLine
                        if (-not $CommandIsComplete) {
                            $script:MOC_RunConsole_ProgressStatus = 'Buffering multiline command.'
                            $script:MOC_RunConsole_ProgressOperation = 'Continue the command block, then press Enter when complete.'
                        }
                        elseif ($HasMoreBatchInput) {
                            $script:MOC_RunConsole_ProgressStatus = 'Buffering pasted command.'
                            $script:MOC_RunConsole_ProgressOperation = 'Pasted multiline input is being collected before execution.'
                        }
                    }
                    else {
                        $script:MOC_RunConsole_InputValue = ''
                        return $Command.TrimEnd()
                    }
                }
                'Backspace' {
                    if ($Command.Length -gt 0) {
                        $Command = $Command.Substring(0, $Command.Length - 1)
                    }
                }
                'Escape' {
                    $script:MOC_RunConsole_InputValue = ''
                    return 'exit'
                }
                'Tab' {
                    $Command += "`t"
                }
                default {
                    $Char = [string]$KeyInfo.KeyChar
                    if (-not [char]::IsControl($KeyInfo.KeyChar)) {
                        $Command += $Char
                    }
                }
            }
        }

        if ($SawBracketedPaste) {
            $script:MOC_RunConsole_ProgressStatus = 'Pasted command buffered.'
            $script:MOC_RunConsole_ProgressOperation = 'Press Enter to run the full pasted command, or continue editing.'
        }

        Set-MOCTerminalInputDisplay -CommandText $Command -Prompt $Prompt

        # Some hosts briefly echo pasted CR/LF text before the hidden ReadKey loop fully
        # drains it. A hard redraw after paste removes that residue and restores the
        # bounded MOC panes before the technician continues.
        if ($BatchLookedLikePaste) {
            Invoke-MOCHardClearHost

            if ($Command -match "`n") {
                $EditorResult = Invoke-MOCTerminalPasteEditor -CommandText $Command -OutputBuffer $OutputBuffer -Prompt $Prompt
                if ($EditorResult.Action -eq 'Run') {
                    $script:MOC_RunConsole_InputValue = ''
                    $script:MOC_RunConsole_InputPreviewLines = @()
                    return ([string]$EditorResult.Text).TrimEnd()
                }

                $Command = ''
                Set-MOCTerminalInputDisplay -CommandText $Command -Prompt $Prompt
                $script:MOC_RunConsole_ProgressStatus = 'Paste cancelled.'
                $script:MOC_RunConsole_ProgressOperation = 'Paste buffer cleared. Ready for next command.'
            }
        }
    }
}

function Invoke-MOCTerminal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$OutputBuffer = $null
    )

    $PriorView = $script:MOC_View
    $PriorFolder = $script:MOC_CurrentFolder
    $PriorActiveTranscript = $script:MOC_ActiveTranscriptPath

    # Some dispatcher paths can accidentally pass an empty string as the first
    # positional argument. Normalize that to a real buffer instead of letting
    # parameter binding or typed-list conversion stop Terminal mode from opening.
    if ($OutputBuffer -is [System.Collections.Generic.List[string]]) {
        $TerminalOutputBuffer = $OutputBuffer
    }
    else {
        $TerminalOutputBuffer = [System.Collections.Generic.List[string]]::new()
    }

    $script:MOC_View = 'Terminal'
    $script:MOC_RunConsole_Buffer = $TerminalOutputBuffer
    $script:MOC_RunConsole_ScriptName = 'MOC Terminal'
    $script:MOC_RunConsole_LastRender = Get-Date
    $script:MOC_RunConsole_ProgressActivity = 'MOC Terminal'
    $script:MOC_RunConsole_ProgressStatus = 'Ready'
    $script:MOC_RunConsole_ProgressPercent = 0
    $script:MOC_RunConsole_ProgressOperation = 'Run ad-hoc PowerShell commands in the active MOC session.'
    $script:MOC_RunConsole_ProgressCompleted = $false
    $script:MOC_RunConsole_InputRequired = $true
    $script:MOC_RunConsole_InputPrompt = 'MOC PS'
    $script:MOC_RunConsole_InputValue = ''
    $script:MOC_RunConsole_InputHelp = 'Type a PowerShell command, paste multiline blocks normally, then press Enter.'
    $script:MOC_RunConsole_InputPreviewLines = @()
    $script:MOC_RunConsole_IsActive = $true
    $script:MOC_RunConsole_UserScrollOffset = $null

    try {
        Enable-MOCBracketedPasteMode
        Add-RunConsoleLine -OutputBuffer $TerminalOutputBuffer -Line 'MOC Terminal'
        Add-RunConsoleLine -OutputBuffer $TerminalOutputBuffer -Line '------------'
        Add-RunConsoleLine -OutputBuffer $TerminalOutputBuffer -Line 'Run ad-hoc PowerShell commands inside this same MOC PowerShell session.'
        Add-RunConsoleLine -OutputBuffer $TerminalOutputBuffer -Line 'Example: Get-MgContext | Format-List *'
        Add-RunConsoleLine -OutputBuffer $TerminalOutputBuffer -Line ''

        while ($true) {
            $CommandText = Read-MOCTerminalCommand -OutputBuffer $TerminalOutputBuffer -Prompt 'MOC PS'

            if ([string]::IsNullOrWhiteSpace($CommandText)) {
                continue
            }

            if ($CommandText -match '(?i)^(exit|quit|back)$') {
                break
            }

            if ($CommandText -match '(?i)^(clear|cls)$') {
                $TerminalOutputBuffer.Clear()
                Add-RunConsoleLine -OutputBuffer $TerminalOutputBuffer -Line 'MOC Terminal'
                Add-RunConsoleLine -OutputBuffer $TerminalOutputBuffer -Line '------------'
                Add-RunConsoleLine -OutputBuffer $TerminalOutputBuffer -Line 'Output cleared.'
                Add-RunConsoleLine -OutputBuffer $TerminalOutputBuffer -Line ''
                $script:MOC_RunConsole_UserScrollOffset = $null
                $script:MOC_RunConsole_InputPreviewLines = @()
                continue
            }

            $CommandLineCount = @(([string]$CommandText) -split "`r?`n").Count
            if ($CommandLineCount -gt 1) {
                Add-RunConsoleLine -OutputBuffer $TerminalOutputBuffer -Line ("PS> [multiline command block: {0} lines]" -f $CommandLineCount)
            }
            else {
                Add-RunConsoleLine -OutputBuffer $TerminalOutputBuffer -Line ("PS> {0}" -f $CommandText)
            }
            $script:MOC_RunConsole_UserScrollOffset = $null
            $script:MOC_RunConsole_ProgressActivity = 'MOC Terminal'
            $script:MOC_RunConsole_ProgressStatus = 'Running command.'
            $script:MOC_RunConsole_ProgressOperation = if ($CommandLineCount -gt 1) { ('Executing multiline command block: {0} lines.' -f $CommandLineCount) } else { $CommandText }
            $script:MOC_RunConsole_ProgressPercent = 50
            $script:MOC_RunConsole_InputRequired = $false
            $script:MOC_RunConsole_InputPrompt = 'MOC PS'
            $script:MOC_RunConsole_InputValue = ''
            $script:MOC_RunConsole_InputHelp = 'Command is running.'
            $script:MOC_RunConsole_InputPreviewLines = @()
            $ScrollOffset = Get-MOCRunConsoleScrollMaxOffset -OutputBuffer $TerminalOutputBuffer
            $script:MOC_RunConsole_UserScrollOffset = $ScrollOffset
            Write-RunConsoleFrame -ScriptName 'MOC Terminal' -OutputBuffer $TerminalOutputBuffer -ScrollOffset $ScrollOffset -Status 'Running'

            try {
                $CommandScriptBlock = [scriptblock]::Create($CommandText)

                $PreviousInformationPreference = $InformationPreference
                $PreviousVerbosePreference = $VerbosePreference
                $PreviousWarningPreference = $WarningPreference
                $PreviousDebugPreference = $DebugPreference
                try {
                    $InformationPreference = 'Continue'
                    $VerbosePreference = 'Continue'
                    $WarningPreference = 'Continue'
                    $DebugPreference = 'Continue'

                    # Explicitly redirect all PowerShell streams to success output so
                    # Terminal mode captures Write-Host / Information, Verbose,
                    # Warning, Debug, Error, and pipeline output inside the MOC pane.
                    $CommandOutput = @(. $CommandScriptBlock 6>&1 5>&1 4>&1 3>&1 2>&1)
                }
                finally {
                    $InformationPreference = $PreviousInformationPreference
                    $VerbosePreference = $PreviousVerbosePreference
                    $WarningPreference = $PreviousWarningPreference
                    $DebugPreference = $PreviousDebugPreference
                }

                if ($CommandOutput.Count -eq 0) {
                    Add-RunConsoleLine -OutputBuffer $TerminalOutputBuffer -Line '(no pipeline or host output returned; function definitions and variable assignments can complete silently)'
                }
                else {
                    $Formatted = ($CommandOutput | Out-String -Width ([Math]::Max(80, (Get-TerminalWidth) - 6)))
                    foreach ($Line in ($Formatted -split "`r?`n")) {
                        if ($Line.Length -gt 0) {
                            Add-RunConsoleLine -OutputBuffer $TerminalOutputBuffer -Line $Line
                        }
                    }
                }

                $script:MOC_RunConsole_ProgressStatus = 'Command completed.'
                $script:MOC_RunConsole_ProgressPercent = 100
                $script:MOC_RunConsole_ProgressOperation = 'Ready for next command.'
            }
            catch {
                Add-RunConsoleLine -OutputBuffer $TerminalOutputBuffer -Line ('ERROR: {0}' -f [string]$_.Exception.Message)
                if ($_.ScriptStackTrace) {
                    Add-RunConsoleLine -OutputBuffer $TerminalOutputBuffer -Line $_.ScriptStackTrace
                }
                $script:MOC_RunConsole_ProgressStatus = 'Command failed.'
                $script:MOC_RunConsole_ProgressPercent = 100
                $script:MOC_RunConsole_ProgressOperation = 'Review error output.'
            }

            Add-RunConsoleLine -OutputBuffer $TerminalOutputBuffer -Line ''
            $script:MOC_RunConsole_UserScrollOffset = $null
            $script:MOC_RunConsole_InputRequired = $true
            $script:MOC_RunConsole_InputPrompt = 'MOC PS'
            $script:MOC_RunConsole_InputValue = ''
            $script:MOC_RunConsole_InputHelp = 'Type another command, paste multiline blocks normally, or use exit/back/quit.'
            $script:MOC_RunConsole_InputPreviewLines = @()
        }
    }
    finally {
        Disable-MOCBracketedPasteMode
        $script:MOC_RunConsole_IsActive = $false
        $script:MOC_RunConsole_UserScrollOffset = $null
        $script:MOC_RunConsole_InputRequired = $false
        $script:MOC_RunConsole_InputPrompt = ''
        $script:MOC_RunConsole_InputValue = ''
        $script:MOC_RunConsole_InputHelp = 'No input required.'
        $script:MOC_RunConsole_InputPreviewLines = @()
        $script:MOC_ActiveTranscriptPath = $PriorActiveTranscript
        $script:MOC_View = $PriorView
        $script:MOC_CurrentFolder = $PriorFolder
        $script:MOC_LastStatus = 'Returned from terminal'
    }
}

function Invoke-SelectedScript {
    param([pscustomobject]$Script)

    $start = Get-Date
    $ExitCode = 0
    Write-LauncherLog -Action 'START' -ScriptName $Script.Name

    $ExitCode = Invoke-ScriptInRunConsole -Script $Script

    $durationSeconds = ((Get-Date) - $start).TotalSeconds
    $durationFormatted = Format-Duration $durationSeconds
    $script:MOC_LastScript = $Script.Name
    $script:MOC_LastDuration = $durationFormatted

    if ($ExitCode -ne 0) {
        $script:MOC_LastStatus = 'Script error'
        Write-LauncherLog -Action 'FAIL' -ScriptName $Script.Name -ExitCode $ExitCode -Duration $durationFormatted
    }
    else {
        $script:MOC_LastStatus = 'Ready'
        Write-LauncherLog -Action 'END' -ScriptName $Script.Name -Duration $durationFormatted
    }
}

# ------------------------------------------------------------
# Main
# ------------------------------------------------------------
Initialize-ConsoleLayout


# ------------------------------------------------------------
# Module maintenance
# ------------------------------------------------------------
$script:MOC_ModuleInstallerNames = @(
    'Install-MOCPowerShellModules.ps1',
    'InstallPowerShellModules.ps1'
)

function Get-MOCModuleRequirementList {
    $Requirements = @(
        [pscustomobject]@{ Name = 'Az'; MinimumVersion = '15.4.0'; Purpose = 'Azure login and Azure Key Vault secret retrieval' }
        [pscustomobject]@{ Name = 'ExchangeOnlineManagement'; MinimumVersion = '3.9.2'; Purpose = 'Exchange Online and Purview/Security & Compliance connectivity' }
        [pscustomobject]@{ Name = 'Microsoft.Graph'; MinimumVersion = '2.36.1'; Purpose = 'Microsoft Graph SDK base modules' }
        [pscustomobject]@{ Name = 'Microsoft.Graph.Authentication'; MinimumVersion = '2.36.1'; Purpose = 'Microsoft Graph authentication and Invoke-MgGraphRequest' }
        [pscustomobject]@{ Name = 'Microsoft.Graph.Beta.Reports'; MinimumVersion = '2.36.1'; Purpose = 'Graph beta reports cmdlets used by legacy credential registration reports' }
        [pscustomobject]@{ Name = 'ImportExcel'; MinimumVersion = '7.8.10'; Purpose = 'XLSX workbook export and formatting' }
    )
    return $Requirements
}

function Get-MOCInstalledModuleVersionText {
    param([Parameter(Mandatory)][string]$Name)

    try {
        $Installed = @(Get-Module -ListAvailable -Name $Name -ErrorAction SilentlyContinue | Sort-Object Version -Descending)
        $Current = $Installed | Select-Object -First 1
        if ($Current) { return [string]$Current.Version }
    }
    catch { }

    return ''
}

function Get-MOCOnlineModuleVersionText {
    param([Parameter(Mandatory)][string]$Name)

    try {
        $Latest = Find-Module -Name $Name -Repository PSGallery -ErrorAction Stop
        if ($Latest -and $Latest.Version) { return [string]$Latest.Version }
    }
    catch {
        return 'Check failed'
    }

    return 'Unknown'
}

function Get-MOCModuleHealth {
    param([switch]$CheckOnline)

    $Rows = @()
    foreach ($Requirement in Get-MOCModuleRequirementList) {
        $InstalledVersion = Get-MOCInstalledModuleVersionText -Name $Requirement.Name
        $LatestVersion = if ($CheckOnline) { Get-MOCOnlineModuleVersionText -Name $Requirement.Name } else { 'Not checked' }

        $State = 'Missing'
        if (-not [string]::IsNullOrWhiteSpace($InstalledVersion)) {
            try {
                if ([version]$InstalledVersion -lt [version]$Requirement.MinimumVersion) {
                    $State = 'Below baseline'
                }
                elseif ($CheckOnline -and $LatestVersion -notin @('Check failed','Unknown','Not checked') -and [version]$InstalledVersion -lt [version]$LatestVersion) {
                    $State = 'Upgrade available'
                }
                else {
                    $State = 'OK'
                }
            }
            catch {
                $State = 'Installed'
            }
        }

        $Rows += [pscustomobject]@{
            Name = $Requirement.Name
            MinimumVersion = $Requirement.MinimumVersion
            InstalledVersion = $InstalledVersion
            LatestVersion = $LatestVersion
            State = $State
            Purpose = $Requirement.Purpose
        }
    }
    return $Rows
}

function Find-MOCModuleInstaller {
    foreach ($Name in $script:MOC_ModuleInstallerNames) {
        $Candidate = Join-Path $RootPath $Name
        if (Test-Path -LiteralPath $Candidate) { return $Candidate }
    }
    return $null
}

function Start-MOCModuleInstaller {
    param(
        [Parameter(Mandatory)][string]$Installer,
        [ValidateSet('InstallMissing','UpgradeAll')][string]$Mode,
        [ValidateSet('CurrentUser','AllUsers')][string]$Scope = 'CurrentUser'
    )

    $pwshCommand = Get-Command pwsh -ErrorAction SilentlyContinue
    if (-not $pwshCommand) {
        $pwshCommand = Get-Command powershell -ErrorAction Stop
    }

    $pwsh = $pwshCommand.Source
    $RunTitle = if ($Mode -eq 'UpgradeAll') { 'Module Maintenance - Upgrade Latest' } else { 'Module Maintenance - Install Missing' }
    $StatusText = if ($Mode -eq 'UpgradeAll') { 'Upgrading approved MOC modules...' } else { 'Installing missing or below-baseline MOC modules...' }

    # AllUsers on Windows requires UAC. A UAC-elevated process cannot be reliably captured
    # back into this terminal frame, so keep this as an intentional Windows-only path.
    if ($IsWindows -and $Scope -eq 'AllUsers') {
        $ArgumentList = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -Mode {1} -Scope {2} -NoPause' -f ($Installer -replace '"', '\"'), $Mode, $Scope
        Start-Process -FilePath $pwsh -ArgumentList $ArgumentList -Verb RunAs | Out-Null
        return [pscustomobject]@{
            ExitCode = 0
            LaunchedExternal = $true
        }
    }

    $OutputBuffer = [System.Collections.Generic.List[string]]::new()
    $script:MOC_RunConsole_Buffer = $OutputBuffer
    $script:MOC_RunConsole_ScriptName = $RunTitle
    $script:MOC_RunConsole_LastRender = Get-Date
    $script:MOC_RunConsole_ProgressActivity = 'Module Maintenance'
    $script:MOC_RunConsole_ProgressStatus = 'Initializing'
    $script:MOC_RunConsole_ProgressPercent = 0
    $script:MOC_RunConsole_ProgressOperation = 'Preparing module installer'
    $script:MOC_RunConsole_ProgressCompleted = $false
    $script:MOC_RunConsole_IsActive = $true

    $PriorActiveTranscript = $script:MOC_ActiveTranscriptPath
    $ModuleTranscriptPath = $null
    try {
        if (-not (Test-Path $TranscriptLogDir)) {
            New-Item -ItemType Directory -Path $TranscriptLogDir -Force | Out-Null
        }
        $ModuleTranscriptPath = Join-Path $TranscriptLogDir ("MOC-ModuleMaintenance-{0}.txt" -f (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'))
        $script:MOC_ActiveTranscriptPath = $ModuleTranscriptPath
        Add-MOCTranscriptText -Path $ModuleTranscriptPath -Text ("MOC Module Maintenance started: {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
    }
    catch {
        $ModuleTranscriptPath = $null
    }

    function Render-MOCModuleInstallerFrame {
        param(
            [string]$Status = 'Running',
            [switch]$Force
        )

        $Now = Get-Date
        if ($Force -or (($Now - $script:MOC_RunConsole_LastRender).TotalMilliseconds -ge 750)) {
            $Offset = [Math]::Max(0, $script:MOC_RunConsole_Buffer.Count - $script:MOC_RunViewportHeight)
            Write-RunConsoleFrame -ScriptName $script:MOC_RunConsole_ScriptName -OutputBuffer $script:MOC_RunConsole_Buffer -ScrollOffset $Offset -Status $Status
            $script:MOC_RunConsole_LastRender = $Now
        }
    }

    try {
        Add-RunConsoleLine -OutputBuffer $OutputBuffer -Line ("Installer: {0}" -f $Installer)
        Add-RunConsoleLine -OutputBuffer $OutputBuffer -Line ("PowerShell: {0}" -f $pwsh)
        Add-RunConsoleLine -OutputBuffer $OutputBuffer -Line ("Mode: {0}" -f $Mode)
        Add-RunConsoleLine -OutputBuffer $OutputBuffer -Line ("Scope: {0}" -f $Scope)
        if (-not [string]::IsNullOrWhiteSpace($ModuleTranscriptPath)) {
            Add-RunConsoleLine -OutputBuffer $OutputBuffer -Line ("MOC transcript: {0}" -f $ModuleTranscriptPath)
        }
        Add-RunConsoleLine -OutputBuffer $OutputBuffer -Line ''

        $script:MOC_RunConsole_ProgressPercent = 5
        $script:MOC_RunConsole_ProgressStatus = 'Starting'
        $script:MOC_RunConsole_ProgressOperation = $StatusText
        Render-MOCModuleInstallerFrame -Status 'Starting' -Force

        Add-RunConsoleLine -OutputBuffer $OutputBuffer -Line 'Module installer started. Output is being captured inside the MOC progress pane.'
        Add-RunConsoleLine -OutputBuffer $OutputBuffer -Line ''
        Render-MOCModuleInstallerFrame -Status 'Running' -Force

        # Linux fix: do not use System.Diagnostics async DataReceivedEventHandler callbacks here.
        # Those callbacks run on .NET thread-pool threads that do not have a PowerShell runspace,
        # which can terminate pwsh with: "There is no Runspace available to run scripts in this thread."
        # Start-Job + Receive-Job keeps all pane updates on the main MOC runspace.
        $InstallerJob = $null
        $ExitCode = 1
        try {
            $InstallerJobName = 'MOCModuleMaintenanceInstaller-{0}' -f ([guid]::NewGuid().ToString('N'))
            $InstallerJob = Start-Job -Name $InstallerJobName -ScriptBlock {
                param(
                    [Parameter(Mandatory)][string]$PwshPath,
                    [Parameter(Mandatory)][string]$InstallerPath,
                    [Parameter(Mandatory)][string]$InstallerMode,
                    [Parameter(Mandatory)][string]$InstallerScope
                )

                & $PwshPath -NoProfile -ExecutionPolicy Bypass -File $InstallerPath -Mode $InstallerMode -Scope $InstallerScope -NoPause 2>&1
                $Code = if ($null -ne $global:LASTEXITCODE) { [int]$global:LASTEXITCODE } else { 0 }
                [pscustomobject]@{
                    __MOCModuleInstallerExitCode = $Code
                }
            } -ArgumentList $pwsh, $Installer, $Mode, $Scope

            $script:MOC_RunConsole_ProgressPercent = 15
            $script:MOC_RunConsole_ProgressStatus = 'Running'
            $script:MOC_RunConsole_ProgressOperation = $StatusText

            while ($InstallerJob.State -eq 'Running') {
                $ReceivedItems = Receive-Job -Job $InstallerJob -ErrorAction SilentlyContinue
                $Dequeued = $false

                foreach ($Item in @($ReceivedItems)) {
                    if ($null -eq $Item) { continue }

                    $ExitProperty = $Item.PSObject.Properties['__MOCModuleInstallerExitCode']
                    if ($null -ne $ExitProperty) {
                        $ExitCode = [int]$ExitProperty.Value
                        continue
                    }

                    Add-RunConsoleLine -OutputBuffer $OutputBuffer -Line ([string]$Item)
                    $Dequeued = $true
                }

                if ($Dequeued) {
                    $script:MOC_RunConsole_ProgressPercent = [Math]::Min(95, [int]$script:MOC_RunConsole_ProgressPercent + 1)
                    Render-MOCModuleInstallerFrame -Status 'Running' -Force
                }
                else {
                    Render-MOCModuleInstallerFrame -Status 'Running'
                }

                Start-Sleep -Milliseconds 200
            }

            $ReceivedItems = Receive-Job -Job $InstallerJob -Wait -ErrorAction SilentlyContinue
            foreach ($Item in @($ReceivedItems)) {
                if ($null -eq $Item) { continue }

                $ExitProperty = $Item.PSObject.Properties['__MOCModuleInstallerExitCode']
                if ($null -ne $ExitProperty) {
                    $ExitCode = [int]$ExitProperty.Value
                    continue
                }

                Add-RunConsoleLine -OutputBuffer $OutputBuffer -Line ([string]$Item)
            }

            if ($InstallerJob.State -eq 'Failed') {
                $ExitCode = 1
                Add-RunConsoleLine -OutputBuffer $OutputBuffer -Line '[ERROR] Module installer job failed before completion.'
                foreach ($JobError in @($InstallerJob.ChildJobs[0].Error)) {
                    Add-RunConsoleLine -OutputBuffer $OutputBuffer -Line ('[ERROR] {0}' -f [string]$JobError)
                }
            }
        }
        finally {
            if ($null -ne $InstallerJob) {
                Remove-Job -Job $InstallerJob -Force -ErrorAction SilentlyContinue
            }
        }

        $CompletedStatus = if ($ExitCode -eq 0) { 'Completed' } else { 'Failed' }
        $script:MOC_RunConsole_ProgressPercent = 100
        $script:MOC_RunConsole_ProgressStatus = $CompletedStatus
        $script:MOC_RunConsole_ProgressOperation = ("Installer exit code: {0}" -f $ExitCode)
        $script:MOC_RunConsole_ProgressCompleted = $true
        Add-RunConsoleLine -OutputBuffer $OutputBuffer -Line ''
        Add-RunConsoleLine -OutputBuffer $OutputBuffer -Line ("Module installer finished with exit code: {0}" -f $ExitCode)
        if ($ExitCode -eq 0) {
            Add-RunConsoleLine -OutputBuffer $OutputBuffer -Line 'Close and reopen PowerShell before authenticating in MOC again if modules were installed or upgraded.'
        }
        Render-MOCModuleInstallerFrame -Status $CompletedStatus -Force

        $ScrollOffset = (Get-MOCRunConsoleScrollMaxOffset -OutputBuffer $OutputBuffer)
        while ($true) {
            Write-RunConsoleFrame -ScriptName $RunTitle -OutputBuffer $OutputBuffer -ScrollOffset $ScrollOffset -Status $CompletedStatus
            $Key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
            Hide-MOCCursor

            if ($Key.VirtualKeyCode -eq 13 -or $Key.VirtualKeyCode -eq 27 -or $Key.Character -match '[Qq]') {
                break
            }
            elseif ($Key.VirtualKeyCode -eq 33) {
                $ScrollOffset = [Math]::Max(0, $ScrollOffset - $script:MOC_RunViewportHeight)
            }
            elseif ($Key.VirtualKeyCode -eq 34) {
                $ScrollOffset = [Math]::Min((Get-MOCRunConsoleScrollMaxOffset -OutputBuffer $OutputBuffer), $ScrollOffset + $script:MOC_RunViewportHeight)
            }
            elseif ($Key.VirtualKeyCode -eq 38) {
                $ScrollOffset = [Math]::Max(0, $ScrollOffset - 1)
            }
            elseif ($Key.VirtualKeyCode -eq 40) {
                $ScrollOffset = [Math]::Min((Get-MOCRunConsoleScrollMaxOffset -OutputBuffer $OutputBuffer), $ScrollOffset + 1)
            }
            elseif ($Key.VirtualKeyCode -eq 36) {
                $ScrollOffset = 0
            }
            elseif ($Key.VirtualKeyCode -eq 35) {
                $ScrollOffset = (Get-MOCRunConsoleScrollMaxOffset -OutputBuffer $OutputBuffer)
            }
        }

        return [pscustomobject]@{
            ExitCode = $ExitCode
            LaunchedExternal = $false
        }
    }
    finally {
        $script:MOC_RunConsole_IsActive = $false
        $script:MOC_ActiveTranscriptPath = $PriorActiveTranscript
    }
}

function New-MOCModuleHealthRow {
    param(
        [Parameter(Mandatory)][pscustomobject]$Requirement,
        [Parameter(Mandatory = $false)][string]$InstalledVersion = '',
        [Parameter(Mandatory = $false)][string]$LatestVersion = 'Not checked'
    )

    $State = 'Missing'
    if (-not [string]::IsNullOrWhiteSpace($InstalledVersion)) {
        try {
            if ([version]$InstalledVersion -lt [version]$Requirement.MinimumVersion) {
                $State = 'Below baseline'
            }
            elseif ($LatestVersion -notin @('Check failed','Unknown','Not checked') -and [version]$InstalledVersion -lt [version]$LatestVersion) {
                $State = 'Upgrade available'
            }
            else {
                $State = 'OK'
            }
        }
        catch {
            $State = 'Installed'
        }
    }

    return [pscustomobject]@{
        Name = $Requirement.Name
        MinimumVersion = $Requirement.MinimumVersion
        InstalledVersion = $InstalledVersion
        LatestVersion = $LatestVersion
        State = $State
        Purpose = $Requirement.Purpose
    }
}

function Invoke-MOCModuleOnlineCheckWithProgress {
    # Module maintenance is a major screen transition. Force a hard clear before
    # the progress pane starts so it cannot layer under the previous folder/script
    # selection frame while PSGallery checks are running.
    Invoke-MOCHardClearHost

    $Requirements = @(Get-MOCModuleRequirementList)
    $Rows = @()
    $OutputBuffer = [System.Collections.Generic.List[string]]::new()
    $Total = [Math]::Max(1, $Requirements.Count)

    $script:MOC_RunConsole_ProgressActivity = 'Module Maintenance'
    $script:MOC_RunConsole_ProgressStatus = 'Checking PSGallery latest versions'
    $script:MOC_RunConsole_ProgressPercent = 0
    $script:MOC_RunConsole_ProgressOperation = 'Preparing module inventory'
    $script:MOC_RunConsole_ProgressCompleted = $false
    $script:MOC_RunConsole_IsActive = $true

    [void]$OutputBuffer.Add('Checking installed module versions and PSGallery latest versions...')
    [void]$OutputBuffer.Add('This may take a moment if PSGallery or the network is slow.')
    [void]$OutputBuffer.Add('')
    Write-RunConsoleFrame -ScriptName 'MOC Module Maintenance' -OutputBuffer $OutputBuffer -Status 'Running'

    for ($i = 0; $i -lt $Requirements.Count; $i++) {
        $Requirement = $Requirements[$i]
        $Name = [string]$Requirement.Name
        $PercentBefore = [int](($i / $Total) * 100)
        $script:MOC_RunConsole_ProgressPercent = $PercentBefore
        $script:MOC_RunConsole_ProgressStatus = 'Checking PSGallery latest versions'
        $script:MOC_RunConsole_ProgressOperation = ('Checking {0} ({1} of {2})' -f $Name, ($i + 1), $Requirements.Count)
        [void]$OutputBuffer.Add(('Checking {0}...' -f $Name))
        Write-RunConsoleFrame -ScriptName 'MOC Module Maintenance' -OutputBuffer $OutputBuffer -Status 'Running'

        $InstalledVersion = Get-MOCInstalledModuleVersionText -Name $Name
        $LatestVersion = Get-MOCOnlineModuleVersionText -Name $Name
        $Row = New-MOCModuleHealthRow -Requirement $Requirement -InstalledVersion $InstalledVersion -LatestVersion $LatestVersion
        $Rows += $Row

        $InstalledText = if ([string]::IsNullOrWhiteSpace($InstalledVersion)) { '-' } else { $InstalledVersion }
        [void]$OutputBuffer.Add(('  Installed: {0} | Latest: {1} | State: {2}' -f $InstalledText, $LatestVersion, $Row.State))

        $PercentAfter = [int]((($i + 1) / $Total) * 100)
        $script:MOC_RunConsole_ProgressPercent = $PercentAfter
        Write-RunConsoleFrame -ScriptName 'MOC Module Maintenance' -OutputBuffer $OutputBuffer -Status 'Running'
    }

    $script:MOC_RunConsole_ProgressPercent = 100
    $script:MOC_RunConsole_ProgressStatus = 'PSGallery check completed'
    $script:MOC_RunConsole_ProgressOperation = 'Displaying module maintenance results'
    $script:MOC_RunConsole_IsActive = $false
    [void]$OutputBuffer.Add('')
    [void]$OutputBuffer.Add('PSGallery check completed. Displaying module maintenance results...')
    Write-RunConsoleFrame -ScriptName 'MOC Module Maintenance' -OutputBuffer $OutputBuffer -Status 'Completed'
    Start-Sleep -Milliseconds 350

    return $Rows
}

function Format-MOCModuleTableCell {
    param(
        [Parameter(Mandatory = $false)][AllowNull()][object]$Value,
        [Parameter(Mandatory = $true)][int]$Width
    )

    if ($Width -le 0) { return '' }

    $Text = if ($null -eq $Value) { '' } else { [string]$Value }
    if ([string]::IsNullOrWhiteSpace($Text)) { $Text = '-' }

    if ($Text.Length -gt $Width) {
        if ($Width -le 3) {
            $Text = $Text.Substring(0, $Width)
        }
        else {
            $Text = $Text.Substring(0, ($Width - 3)) + '...'
        }
    }

    return $Text.PadRight($Width)
}

function Get-MOCModuleTableColumnWidths {
    param([Parameter(Mandatory = $true)][int]$ContentWidth)

    $SafeWidth = [Math]::Max(48, $ContentWidth)
    $NameWidth = [Math]::Min(38, [Math]::Max(20, [int][Math]::Floor($SafeWidth * 0.36)))
    $StateWidth = [Math]::Min(18, [Math]::Max(10, [int][Math]::Floor($SafeWidth * 0.18)))
    $Remaining = $SafeWidth - $NameWidth - $StateWidth - 3

    $InstalledWidth = [Math]::Max(10, [int][Math]::Floor($Remaining / 2))
    $LatestWidth = [Math]::Max(10, $Remaining - $InstalledWidth)

    $Total = $NameWidth + $StateWidth + $InstalledWidth + $LatestWidth + 3
    if ($Total -gt $SafeWidth) {
        $Overflow = $Total - $SafeWidth
        $NameWidth = [Math]::Max(16, $NameWidth - $Overflow)
    }

    return [pscustomobject]@{
        Name = $NameWidth
        State = $StateWidth
        Installed = $InstalledWidth
        Latest = $LatestWidth
    }
}

function Format-MOCModuleTableRow {
    param(
        [Parameter(Mandatory = $false)][object]$Name,
        [Parameter(Mandatory = $false)][object]$State,
        [Parameter(Mandatory = $false)][object]$Installed,
        [Parameter(Mandatory = $false)][object]$Latest,
        [Parameter(Mandatory = $true)][pscustomobject]$ColumnWidths
    )

    $Cells = @(
        (Format-MOCModuleTableCell -Value $Name -Width $ColumnWidths.Name),
        (Format-MOCModuleTableCell -Value $State -Width $ColumnWidths.State),
        (Format-MOCModuleTableCell -Value $Installed -Width $ColumnWidths.Installed),
        (Format-MOCModuleTableCell -Value $Latest -Width $ColumnWidths.Latest)
    )

    return ($Cells -join ' ')
}

function Write-MOCModuleMaintenanceScreen {
    param(
        [Parameter(Mandatory)][object[]]$ModuleRows,
        [Parameter(Mandatory = $false)][string]$Installer,
        [Parameter(Mandatory = $false)]$LastOnlineCheck = $null,
        [Parameter(Mandatory = $false)][string]$OnlineStatus = 'Not checked.'
    )

    Write-Header
    Write-Breadcrumb
    $Width = Get-TerminalWidth
    $ContentWidth = [Math]::Max(48, ($Width - 4))
    $ColumnWidths = Get-MOCModuleTableColumnWidths -ContentWidth $ContentWidth

    Write-MOCBorderLine -Kind Top -Width $Width -Color $script:MOC_BorderSecondary
    Write-PanelLine -Text 'MOC Module Maintenance' -Width $Width -Color "$($script:Ansi.Bold)$($script:Ansi.Cyan)"
    Write-MOCBorderLine -Kind Middle -Width $Width -Color $script:MOC_BorderSecondary
    Write-PanelLine -Text 'Child scripts validate required modules only. Install/update is handled here as an explicit maintenance action.' -Width $Width -Color $script:Ansi.White
    Write-PanelLine -Text 'This screen compares installed approved modules against the latest PSGallery versions checked this session.' -Width $Width -Color $script:Ansi.White
    Write-PanelLine -Text '' -Width $Width -Color $script:Ansi.White

    $InstallerText = if ($Installer) { $Installer } else { 'Not found in MOC root' }
    Write-PanelWrappedLabelValue -Label 'Installer: ' -Value $InstallerText -Width $Width -Color $(if ($Installer) { $script:Ansi.Gray } else { $script:Ansi.Yellow }) -MaxLines 4
    $LatestText = if ($LastOnlineCheck -is [datetime]) { $LastOnlineCheck.ToString('yyyy-MM-dd HH:mm:ss') } else { 'Not checked' }
    Write-PanelLine -Text ("Latest check: {0}" -f $LatestText) -Width $Width -Color $script:Ansi.Gray
    Write-PanelLine -Text ("Online status: {0}" -f $OnlineStatus) -Width $Width -Color $(if ($OnlineStatus -match 'failed|offline|unable|not checked') { $script:Ansi.Yellow } elseif ($OnlineStatus -match 'completed') { $script:Ansi.Green } else { $script:Ansi.Cyan })
    Write-PanelLine -Text '' -Width $Width -Color $script:Ansi.White

    $HeaderLine = Format-MOCModuleTableRow -Name 'Module' -State 'State' -Installed 'Installed' -Latest 'Latest' -ColumnWidths $ColumnWidths
    Write-PanelLine -Text $HeaderLine -Width $Width -Color "$($script:Ansi.Bold)$($script:Ansi.White)"
    Write-PanelLine -Text ('-' * [math]::Min($ContentWidth, ($HeaderLine.Length))) -Width $Width -Color $script:Ansi.Gray

    foreach ($Row in $ModuleRows) {
        $InstalledText = if ([string]::IsNullOrWhiteSpace($Row.InstalledVersion)) { '-' } else { $Row.InstalledVersion }
        $LatestText = if ([string]::IsNullOrWhiteSpace($Row.LatestVersion)) { '-' } else { $Row.LatestVersion }
        $Line = Format-MOCModuleTableRow -Name $Row.Name -State $Row.State -Installed $InstalledText -Latest $LatestText -ColumnWidths $ColumnWidths
        $Color = switch ($Row.State) {
            'OK' { $script:Ansi.Green }
            'Missing' { $script:Ansi.Yellow }
            'Below baseline' { $script:Ansi.Yellow }
            'Upgrade available' { $script:Ansi.Cyan }
            default { $script:Ansi.Gray }
        }
        Write-PanelLine -Text $Line -Width $Width -Color $Color
    }

    Write-PanelLine -Text '' -Width $Width -Color $script:Ansi.White
    if (-not $Installer) {
        Write-PanelLine -Text 'Place Install-MOCPowerShellModules.ps1 in the MOC root folder to enable install/upgrade actions.' -Width $Width -Color $script:Ansi.Yellow
    }
    Write-MOCBorderLine -Kind Bottom -Width $Width -Color $script:MOC_BorderSecondary
    Write-Footer
}


function Show-MOCModuleMaintenanceMessageScreen {
    param(
        [Parameter(Mandatory = $true)][string]$Title,
        [Parameter(Mandatory = $false)][string[]]$Lines = @(),
        [Parameter(Mandatory = $false)][string]$TitleColor = '',
        [Parameter(Mandatory = $false)][string]$DefaultLineColor = '',
        [Parameter(Mandatory = $false)][switch]$WaitForKey,
        [Parameter(Mandatory = $false)][string]$PromptText = 'Press Enter to return to module maintenance.'
    )

    if ([string]::IsNullOrWhiteSpace($TitleColor)) { $TitleColor = "$($script:Ansi.Bold)$($script:Ansi.Cyan)" }
    if ([string]::IsNullOrWhiteSpace($DefaultLineColor)) { $DefaultLineColor = $script:Ansi.White }

    Write-Header
    Write-Breadcrumb

    $Width = Get-TerminalWidth
    Write-MOCBorderLine -Kind Top -Width $Width -Color $script:MOC_BorderSecondary
    Write-PanelLine -Text $Title -Width $Width -Color $TitleColor
    Write-MOCBorderLine -Kind Middle -Width $Width -Color $script:MOC_BorderSecondary

    foreach ($Line in @($Lines)) {
        $Text = if ($null -eq $Line) { '' } else { [string]$Line }
        $Color = $DefaultLineColor

        if ([string]::IsNullOrWhiteSpace($Text)) {
            $Color = $script:Ansi.White
        }
        elseif ($Text -match 'failed|error|unable|not found') {
            $Color = $script:Ansi.Red
        }
        elseif ($Text -match 'After|restart|warning|change loaded module behavior|fully restart') {
            $Color = $script:Ansi.Yellow
        }
        elseif ($Text -match 'launched|completed|success') {
            $Color = $script:Ansi.Green
        }
        elseif ($Text -match '^Mode:|Press Y|Press Enter') {
            $Color = $script:Ansi.Cyan
        }

        Write-PanelLine -Text $Text -Width $Width -Color $Color
    }

    if ($WaitForKey) {
        Write-PanelLine -Text '' -Width $Width -Color $script:Ansi.White
        Write-PanelLine -Text $PromptText -Width $Width -Color $script:Ansi.Gray
    }

    Write-MOCBorderLine -Kind Bottom -Width $Width -Color $script:MOC_BorderSecondary
    Write-Footer

    if ($WaitForKey) {
        [void]$Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        Hide-MOCCursor
    }
}

function Invoke-MOCModuleMaintenance {
    $PreviousView = $script:MOC_View
    $PreviousFolder = $script:MOC_CurrentFolder
    $script:MOC_View = 'ModuleMaintenance'
    $script:MOC_CurrentFolder = $null

    $Installer = Find-MOCModuleInstaller
    $LastOnlineCheck = $null
    $OnlineStatus = 'Checking PSGallery latest versions...'
    $ModuleRows = @()

    try {
        $ModuleRows = @(Invoke-MOCModuleOnlineCheckWithProgress)
        $LastOnlineCheck = Get-Date
        $OnlineStatus = 'Completed.'
    }
    catch {
        $ModuleRows = @(Get-MOCModuleHealth)
        $LastOnlineCheck = Get-Date
        $OnlineStatus = 'Online check failed; showing installed/baseline status only.'
        $script:MOC_LastStatus = 'Module online check failed'
    }

    try {
        while ($true) {
            $Installer = Find-MOCModuleInstaller
            Write-MOCModuleMaintenanceScreen -ModuleRows $ModuleRows -Installer $Installer -LastOnlineCheck $LastOnlineCheck -OnlineStatus $OnlineStatus

            $Key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
            Hide-MOCCursor
            if ($Key.VirtualKeyCode -in @(8,27)) { break }

            if ($Key.Character -match '[Rr]') {
                try {
                    $OnlineStatus = 'Checking PSGallery latest versions...'
                    $ModuleRows = @(Invoke-MOCModuleOnlineCheckWithProgress)
                    $LastOnlineCheck = Get-Date
                    $OnlineStatus = 'Completed.'
                }
                catch {
                    $ModuleRows = @(Get-MOCModuleHealth)
                    $LastOnlineCheck = Get-Date
                    $OnlineStatus = 'Online check failed; showing installed/baseline status only.'
                    $script:MOC_LastStatus = 'Module online check failed'
                }
                continue
            }

            if ($Installer -and $Key.Character -match '[Ii]') {
                try {
                    $InstallResult = Start-MOCModuleInstaller -Installer $Installer -Mode 'InstallMissing' -Scope 'CurrentUser'
                    if ($InstallResult.ExitCode -eq 0) {
                        $script:MOC_LastStatus = 'Module installer completed'
                    }
                    else {
                        $script:MOC_LastStatus = 'Module installer failed'
                    }
                    $ModuleRows = @(Get-MOCModuleHealth)
                    $LastOnlineCheck = $null
                    $OnlineStatus = 'Install completed. Press R to recheck PSGallery, or restart PowerShell first if modules changed.'
                    continue
                }
                catch {
                    $script:MOC_LastStatus = 'Module installer launch failed'
                    Show-MOCModuleMaintenanceMessageScreen -Title 'MOC Module Maintenance' -TitleColor $script:Ansi.Red -Lines @(
                        "Failed to launch module installer: $($_.Exception.Message)"
                    ) -WaitForKey
                    continue
                }
            }

            if ($Installer -and $Key.Character -match '[Uu]') {
                Show-MOCModuleMaintenanceMessageScreen -Title 'Upgrade approved MOC modules?' -TitleColor $script:Ansi.Yellow -Lines @(
                    'Upgrade approved MOC modules to the latest PSGallery versions?',
                    '',
                    'This can change loaded module behavior. Close other PowerShell sessions first when possible.',
                    'After upgrade completes, fully restart PowerShell before authenticating in MOC again.',
                    '',
                    'Press Y to continue, or any other key to cancel.'
                )
                $Confirm = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
                Hide-MOCCursor
                if ($Confirm.Character -notmatch '[Yy]') { continue }

                try {
                    $UpgradeResult = Start-MOCModuleInstaller -Installer $Installer -Mode 'UpgradeAll' -Scope 'CurrentUser'
                    if ($UpgradeResult.ExitCode -eq 0) {
                        $script:MOC_LastStatus = 'Module upgrade completed'
                    }
                    else {
                        $script:MOC_LastStatus = 'Module upgrade failed'
                    }
                    $ModuleRows = @(Get-MOCModuleHealth)
                    $LastOnlineCheck = $null
                    $OnlineStatus = 'Upgrade completed. Press R to recheck PSGallery, or restart PowerShell first if modules changed.'
                    continue
                }
                catch {
                    $script:MOC_LastStatus = 'Module upgrade launch failed'
                    Show-MOCModuleMaintenanceMessageScreen -Title 'MOC Module Maintenance' -TitleColor $script:Ansi.Red -Lines @(
                        "Failed to launch module upgrade: $($_.Exception.Message)"
                    ) -WaitForKey
                    continue
                }
            }
        }
    }
    finally {
        $script:MOC_View = $PreviousView
        $script:MOC_CurrentFolder = $PreviousFolder
        Hide-MOCCursor
    }
}


Reset-MOCTerminalSessionState -BeforeLaunch

try {
Enter-MOCAlternateScreenBuffer

[void](Import-MOCLocalConfiguration)
Invoke-MOCFirstRunConfigurationIfNeeded
if ($script:MOC_ExitRequested) { return }

Remove-MOCUpdateStagingDirectory
$Scripts = @(Get-MOCScripts)
$Folders = @(Get-MOCFolders -Scripts $Scripts)

if ($Scripts.Count -eq 0) {
    Exit-MOCAlternateScreenBuffer
    Show-MOCCursor
    Write-Host ''
    Write-Host 'No child scripts were found for this MOC menu.' -ForegroundColor Yellow
    Write-Host ('MOC root: {0}' -f $RootPath) -ForegroundColor DarkGray
    if ($script:MOC_AllowedChildScriptNamePatterns -and @($script:MOC_AllowedChildScriptNamePatterns).Count -gt 0) {
        Write-Host ('Allowed script patterns: {0}' -f (@($script:MOC_AllowedChildScriptNamePatterns) -join ', ')) -ForegroundColor DarkGray
    }
    Write-Host 'Place approved .ps1 child scripts next to the menu or in child folders, then relaunch MOC.' -ForegroundColor DarkGray
    Write-Host ''
    exit
}

$HomeIndex = 0
$ScriptIndex = 0
$NumberBuffer = ''

while ($true) {
    Write-Header
    Write-Breadcrumb

    if ($script:MOC_View -eq 'Home') {
        if ($HomeIndex -ge $Folders.Count) { $HomeIndex = 0 }
        if ($HomeIndex -lt 0) { $HomeIndex = 0 }

        Write-HomeMenu -Folders $Folders -Index $HomeIndex -NumberBuffer $NumberBuffer
        Write-DetailsPane -Item $Folders[$HomeIndex]
    }
    else {
        $FolderScripts = @(Get-CurrentScripts)
        if ($ScriptIndex -ge $FolderScripts.Count) { $ScriptIndex = 0 }
        if ($ScriptIndex -lt 0) { $ScriptIndex = 0 }

        Write-ScriptMenu -FolderScripts $FolderScripts -Index $ScriptIndex -NumberBuffer $NumberBuffer
        if ($FolderScripts.Count -gt 0) {
            Write-DetailsPane -Item $FolderScripts[$ScriptIndex]
        }
    }

    Write-Footer
    $Key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        Hide-MOCCursor

    # Quit
    if ($Key.Character -match '[Qq]') {
        if (Show-MOCQuitConfirmation) {
            $script:MOC_ExitRequested = $true
            Write-LauncherLog -Action 'EXIT' -ScriptName 'Launcher'
            Write-DailyTotal
            Disconnect-MOCSharedSession
            $script:MOC_ExitCompleted = $true
            break
        }
        else {
            $script:MOC_LastStatus = 'Quit cancelled'
            continue
        }
    }

    # Authenticate now
    if ($Key.Character -match '[Aa]') {
        try {
            Initialize-MOCSharedSession -ForceRefresh
        }
        catch {
            $script:MOC_Authenticated = $false
            $script:MOC_OrganizationName = ''
            $script:MOC_LastStatus = 'Auth failed - press A to retry'
            # Initialize-MOCSharedSession renders authentication failures inside the MOC auth pane.
        }
        continue
    }


    # Module maintenance
    if ($Key.Character -match '[Mm]') {
        Invoke-MOCModuleMaintenance
        continue
    }

    # MOC terminal
    if ($Key.Character -match '[Tt]') {
        Invoke-MOCTerminal
        continue
    }




    # MOC configuration
    if ($Key.Character -match '[Cc]') {
        Invoke-MOCConfigurationMenu
        continue
    }

    # MOC self-update
    if ($Key.Character -match '[Uu]') {
        Invoke-MOCSelfUpdate
        if ([bool]$script:MOC_RestartRequested) {
            $script:MOC_ExitRequested = $true
            Write-LauncherLog -Action 'RESTART' -ScriptName 'Launcher'
            Write-DailyTotal
            Disconnect-MOCSharedSession
            $script:MOC_ExitCompleted = $true
            break
        }
        $Scripts = @(Get-MOCScripts)
        $Folders = @(Get-MOCFolders -Scripts $Scripts)
        if ($HomeIndex -ge $Folders.Count) { $HomeIndex = [Math]::Max(0, $Folders.Count - 1) }
        if ($ScriptIndex -ge @(Get-CurrentScripts).Count) { $ScriptIndex = 0 }
        continue
    }

    # Refresh inventory
    if ($Key.Character -match '[Rr]') {
        $Scripts = @(Get-MOCScripts)
        $Folders = @(Get-MOCFolders -Scripts $Scripts)
        $HomeIndex = 0
        $ScriptIndex = 0
        $script:MOC_View = 'Home'
        $script:MOC_CurrentFolder = $null
        $script:MOC_LastStatus = 'Script list refreshed'
        continue
    }

    # Back to Home
    if ($Key.VirtualKeyCode -eq 8 -and $NumberBuffer.Length -eq 0 -and $script:MOC_View -ne 'Home') {
        $script:MOC_View = 'Home'
        $script:MOC_CurrentFolder = $null
        $ScriptIndex = 0
        continue
    }

    # Numeric input
    if (($Key.VirtualKeyCode -ge 49 -and $Key.VirtualKeyCode -le 57) -or ($Key.VirtualKeyCode -ge 97 -and $Key.VirtualKeyCode -le 105)) {
        $digit = if ($Key.VirtualKeyCode -ge 97) { $Key.VirtualKeyCode - 96 } else { $Key.VirtualKeyCode - 48 }
        $NumberBuffer += $digit
        continue
    }

    if ($Key.VirtualKeyCode -eq 8 -and $NumberBuffer.Length -gt 0) {
        $NumberBuffer = $NumberBuffer.Substring(0, $NumberBuffer.Length - 1)
        continue
    }

    # Enter
    if ($Key.VirtualKeyCode -eq 13) {
        if ($NumberBuffer.Length -gt 0) {
            $target = [int]$NumberBuffer - 1
            if ($script:MOC_View -eq 'Home') {
                if ($target -ge 0 -and $target -lt $Folders.Count) { $HomeIndex = $target }
            }
            else {
                $FolderScripts = @(Get-CurrentScripts)
                if ($target -ge 0 -and $target -lt $FolderScripts.Count) { $ScriptIndex = $target }
            }
            $NumberBuffer = ''
            continue
        }

        if ($script:MOC_View -eq 'Home') {
            $script:MOC_CurrentFolder = $Folders[$HomeIndex].Name
            $script:MOC_View = 'Folder'
            $ScriptIndex = 0
            continue
        }
        else {
            $FolderScripts = @(Get-CurrentScripts)
            if ($FolderScripts.Count -gt 0) {
                Invoke-SelectedScript -Script $FolderScripts[$ScriptIndex]
            }
            continue
        }
    }

    # Navigation
    if ($script:MOC_View -eq 'Home') {
        if ($Key.VirtualKeyCode -eq 38 -and $HomeIndex -gt 0) { $HomeIndex-- }
        elseif ($Key.VirtualKeyCode -eq 40 -and $HomeIndex -lt $Folders.Count - 1) { $HomeIndex++ }
    }
    else {
        $FolderScripts = @(Get-CurrentScripts)
        if ($Key.VirtualKeyCode -eq 38 -and $ScriptIndex -gt 0) { $ScriptIndex-- }
        elseif ($Key.VirtualKeyCode -eq 40 -and $ScriptIndex -lt $FolderScripts.Count - 1) { $ScriptIndex++ }
        elseif ($Key.VirtualKeyCode -eq 33) { $ScriptIndex = [Math]::Max(0, $ScriptIndex - $script:MOC_PageSize) }
        elseif ($Key.VirtualKeyCode -eq 34) { $ScriptIndex = [Math]::Min($FolderScripts.Count - 1, $ScriptIndex + $script:MOC_PageSize) }
    }
}

}
finally {
    # Always restore terminal state, including after Ctrl+C/PipelineStoppedException.
    # This prevents the next MOC launch in the same terminal tab from inheriting a
    # stale alternate-screen or soft-redraw state that can hide the footer.
    Exit-MOCAlternateScreenBuffer
    Show-MOCCursor
    try { $Host.UI.RawUI.CursorSize = $OriginalCursorSize } catch {}

    # The alternate screen is discarded when MOC exits. Since MOC clears the normal
    # screen before launch, returning without new output appears as a blank terminal.
    # Render a persistent shutdown summary in the restored normal screen buffer.
    if ($script:MOC_ExitRequested) {
        try {
            [Console]::Out.Write("$($script:Esc)[0m$($script:Esc)[2J$($script:Esc)[H")
            [Console]::Out.Flush()
        }
        catch { }

        Write-Host ''
        if ($script:MOC_ExitCompleted) {
            Write-Host 'M365 Operations Console exited successfully.' -ForegroundColor Green
            Write-Host 'Parent-owned Microsoft 365 sessions were disconnected.' -ForegroundColor DarkGray
        }
        else {
            Write-Host 'M365 Operations Console stopped before shutdown completed.' -ForegroundColor Yellow
            Write-Host 'Review the preceding error or reopen MOC to verify session state.' -ForegroundColor DarkGray
        }
        Write-Host ("Exit time: {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')) -ForegroundColor DarkGray
        if ([bool]$script:MOC_RestartRequested) {
            Write-Host ''
            Write-Host 'Update to the MOC menu has been applied. A forced menu restart is required.' -ForegroundColor Yellow
            if (Start-MOCMenuRelaunchProcess -ScriptPath ([string]$script:MOC_RestartScriptPath)) {
                Write-Host 'The updated MOC menu is reopening automatically in a new PowerShell window.' -ForegroundColor Green
            }
            else {
                Write-Host 'Automatic relaunch did not complete. Reopen the updated menu manually from the path above.' -ForegroundColor Yellow
            }
        }
        Write-Host ''
    }
}
