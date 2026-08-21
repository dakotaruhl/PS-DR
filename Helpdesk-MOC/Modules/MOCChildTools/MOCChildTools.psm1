Set-StrictMode -Version Latest

$script:MOCChildState = [ordered]@{
    ScriptName = 'MOC Child Script'
    Version = 'Unknown'
    ScriptCategory = 'Uncategorized'
    RunFolderPrefix = 'Custom-Report'
    TotalSteps = 1
    MOCRootPath = ''
    ReportsRoot = ''
    ReportsDir = ''
    SummaryPath = ''
    AuditNotesPath = ''
    WorkbookPath = ''
    DoNotOpenOutput = $false
    AuditNotes = [System.Collections.ArrayList]::new()
    WorkbookSheets = [System.Collections.ArrayList]::new()
    Summary = [ordered]@{}
    ScriptMetadata = $null
}

$script:MOCChildOutputRenderer = $null
$script:MOCChildStatusRenderer = $null

function Set-MOCChildOutputRenderer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [scriptblock]$OutputRenderer,

        [Parameter(Mandatory = $false)]
        [scriptblock]$StatusRenderer
    )

    $script:MOCChildOutputRenderer = $OutputRenderer
    $script:MOCChildStatusRenderer = $StatusRenderer
}

function Clear-MOCChildOutputRenderer {
    [CmdletBinding()]
    param()

    $script:MOCChildOutputRenderer = $null
    $script:MOCChildStatusRenderer = $null
}

function Get-MOCChildState {
    [CmdletBinding()]
    param()

    return [pscustomobject]$script:MOCChildState
}

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
        OutputFormat = ''
        RequiredPowerShellModules = @()
    }

    try {
        if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
            return [pscustomobject]$Metadata
        }

        $Raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
        $Header = $Raw
        if ($Raw -match '(?s)^\s*<#(?<header>.*?)#>') { $Header = $matches.header }

        foreach ($Name in @('SYNOPSIS','DESCRIPTION','VERSION','AUTHOR','CATEGORY','OUTPUTFORMAT','REQUIREDPOWERSHELLMODULES','CREATED','LASTMODIFIED','CHANGELOG','REQUIREDGRAPHAPPSCOPES')) {
            $Pattern = "(?ims)^\s*\.$Name\s*(?<value>.*?)(?=^\s*\.[A-Z][A-Z0-9]*\s*|\z)"
            if ($Header -match $Pattern) {
                $Value = $matches.value.Trim()
                switch ($Name) {
                    'SYNOPSIS' { $Metadata.Synopsis = $Value }
                    'DESCRIPTION' { $Metadata.Description = $Value }
                    'VERSION' { $Metadata.Version = ($Value -split '\r?\n')[0].Trim() }
                    'AUTHOR' { $Metadata.Author = $Value }
                    'CATEGORY' { $Metadata.Category = $Value }
                    'OUTPUTFORMAT' { $Metadata.OutputFormat = ($Value -split '\r?\n')[0].Trim() }
                    'REQUIREDPOWERSHELLMODULES' {
                        $Metadata.RequiredPowerShellModules = @(
                            ($Value -split '\r?\n') |
                            ForEach-Object { $_.Trim() } |
                            Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and $_ -notmatch '^(None|N/A|NotRequired)$' }
                        )
                    }
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

function Initialize-MOCChildRun {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)][string]$ScriptPath,
        [Parameter(Mandatory = $false)][string]$ScriptRoot,
        [Parameter(Mandatory = $false)][string]$ReportsRoot,
        [Parameter(Mandatory = $false)][string]$RunFolderPrefix = 'Custom-Report',
        [Parameter(Mandatory = $false)][int]$TotalSteps = 1,
        [Parameter(Mandatory = $false)][switch]$UseExistingSession,
        [Parameter(Mandatory = $false)][switch]$DoNotOpenOutput
    )

    $Metadata = Get-MOCScriptMetadata -Path $ScriptPath
    $ScriptName = if (-not [string]::IsNullOrWhiteSpace($Metadata.Synopsis)) { $Metadata.Synopsis } else { 'MOC Child Script' }
    $Version = $Metadata.Version
    $ScriptCategory = if (-not [string]::IsNullOrWhiteSpace($Metadata.Category)) { $Metadata.Category } else { 'Uncategorized' }

    if ([string]::IsNullOrWhiteSpace($ScriptRoot)) {
        if (-not [string]::IsNullOrWhiteSpace($ScriptPath)) { $ScriptRoot = Split-Path -Parent $ScriptPath }
        else { $ScriptRoot = (Get-Location).Path }
    }

    $MOCRootVar = Get-Variable -Name MOC_RootPath -Scope Script -ErrorAction SilentlyContinue
    if ($MOCRootVar -and -not [string]::IsNullOrWhiteSpace([string]$MOCRootVar.Value)) {
        $MOCRootPath = [string]$MOCRootVar.Value
    }
    else {
        $ParentOfScriptRoot = Split-Path -Parent $ScriptRoot
        if (-not [string]::IsNullOrWhiteSpace($ParentOfScriptRoot)) { $MOCRootPath = $ParentOfScriptRoot }
        else { $MOCRootPath = $ScriptRoot }
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

    $script:MOCChildState.ScriptName = $ScriptName
    $script:MOCChildState.Version = $Version
    $script:MOCChildState.ScriptCategory = $ScriptCategory
    $script:MOCChildState.RunFolderPrefix = $RunFolderPrefix
    $script:MOCChildState.TotalSteps = $TotalSteps
    $script:MOCChildState.MOCRootPath = $MOCRootPath
    $script:MOCChildState.ReportsRoot = $ReportsRoot
    $script:MOCChildState.ReportsDir = $ReportsDir
    $script:MOCChildState.SummaryPath = Join-Path $ReportsDir ("{0}-Summary-{1}.json" -f $RunFolderPrefix, $RunStamp)
    $script:MOCChildState.AuditNotesPath = Join-Path $ReportsDir ("{0}-Audit-Notes-{1}.csv" -f $RunFolderPrefix, $RunStamp)
    $script:MOCChildState.WorkbookPath = Join-Path $ReportsDir ("{0}-{1}.xlsx" -f $RunFolderPrefix, $RunStamp)
    $script:MOCChildState.DoNotOpenOutput = [bool]$DoNotOpenOutput
    $script:MOCChildState.AuditNotes = [System.Collections.ArrayList]::new()
    $script:MOCChildState.WorkbookSheets = [System.Collections.ArrayList]::new()
    $script:MOCChildState.ScriptMetadata = $Metadata
    $script:MOCChildState.Summary = [ordered]@{
        ScriptName = $ScriptName
        Version = $Version
        RunDateTime = (Get-Date).ToString('o')
        OutputFolder = $ReportsDir
        UseExistingSession = [bool]$UseExistingSession
        Counts = [ordered]@{}
        Files = [ordered]@{}
        Warnings = [System.Collections.ArrayList]::new()
    }

    if (-not (Test-Path -LiteralPath $ReportsDir)) {
        New-Item -ItemType Directory -Path $ReportsDir -Force | Out-Null
    }

    return Get-MOCChildState
}

function Write-ChildOutputLine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false, ValueFromPipeline = $true, ValueFromRemainingArguments = $true)]
        [AllowNull()]
        [object[]]$Message,

        [ValidateSet('Info','Success','Warning','Error','Critical','Action','Prompt','Header','Muted')]
        [string]$Level = 'Info'
    )

    process {
        $Text = (@($Message) | ForEach-Object {
            if ($null -eq $_) { '' } else { [string]$_ }
        }) -join ' '

        if ([string]::IsNullOrWhiteSpace($Text)) {
            return
        }

        if ($script:MOCChildOutputRenderer) {
            try {
                & $script:MOCChildOutputRenderer -Message $Text -Level $Level
                return
            }
            catch {
                throw "MOC child output renderer failed. $($_.Exception.Message)"
            }
        }

        if ($script:MOCChildStatusRenderer) {
            try {
                & $script:MOCChildStatusRenderer -Message $Text -Level $Level
                return
            }
            catch {
                throw "MOC child status renderer failed. $($_.Exception.Message)"
            }
        }

        if (Get-Command Write-MOCOutputLine -ErrorAction SilentlyContinue) {
            Write-MOCOutputLine -Message $Text -Level $Level
            return
        }

        if (Get-Command Write-MOCStatusLine -ErrorAction SilentlyContinue) {
            Write-MOCStatusLine -Message $Text -Level $Level
            return
        }

        throw 'No MOC-safe output renderer is available.'
}
}

function Write-ChildStatusLine {
    [CmdletBinding()]
    param([Parameter(Mandatory = $false, ValueFromPipeline = $true, ValueFromRemainingArguments = $true)][AllowNull()][object[]]$Message)

    process {
        $Text = (@($Message) | ForEach-Object { if ($null -eq $_) { '' } else { [string]$_ } }) -join ' '
        if ([string]::IsNullOrWhiteSpace($Text)) { return }

        if (Get-Command -Name Write-MOCStatusLine -ErrorAction SilentlyContinue) {
            try {
                $null = Write-MOCStatusLine `
                    -Message $Text `
                    -Level Info
                return
            }
            catch { }
            try {
                $null = Write-MOCStatusLine `
                    -Message $Text `
                    -Level Info
                return
            }
            catch { }
        }

        Write-ChildOutputLine `
            -Message $Text
    }
}

function Write-ChildTranscriptLine {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Message)

    if (Get-Command Write-MOCTranscriptLine -ErrorAction SilentlyContinue) {
        try { Write-MOCTranscriptLine $Message; return } catch { }
    }

    return
}

function Update-ChildProgress {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Activity,
        [Parameter(Mandatory = $true)][double]$Percent,
        [Parameter(Mandatory = $false)][string]$Status = '',
        [Parameter(Mandatory = $false)][string]$CurrentOperation = ''
    )

    $SafePercent = [Math]::Max(0, [Math]::Min(100, [int][Math]::Round($Percent, 0)))

    if (Get-Command -Name Update-MOCProgress -ErrorAction SilentlyContinue) {
        $Params = @{ Activity = $Activity; PercentComplete = $SafePercent; Status = $Status }
        if ($PSBoundParameters.ContainsKey('CurrentOperation') -and -not [string]::IsNullOrWhiteSpace($CurrentOperation)) {
            $Params.CurrentOperation = $CurrentOperation
        }
        try { $null = Update-MOCProgress @Params; return } catch { }
    }

    return
}

function Get-ReportDisplayPath {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    $Leaf = Split-Path -Leaf $Path
    $Category = Split-Path -Leaf $script:MOCChildState.ReportsRoot
    if ([string]::IsNullOrWhiteSpace($Category)) { $Category = 'Reports' }
    return ("Reports\{0}\{1}" -f $Category, $Leaf)
}

function Read-ChildText {
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

function Read-ChildMenuChoice {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Title,
        [Parameter(Mandatory = $true)][string[]]$Options,
        [Parameter(Mandatory = $false)][string]$Prompt = 'Select an option',
        [Parameter(Mandatory = $false)][string[]]$ValidChoices = @('1','2','3'),
        [Parameter(Mandatory = $false)][switch]$AllowExit,
        [Parameter(Mandatory = $false)][string]$DefaultChoice
    )

    Write-ChildOutputLine -Level Header -Message $Title
    Write-ChildOutputLine -Level Muted -Message ('-' * $Title.Length)
    foreach ($Option in $Options) { Write-ChildOutputLine -Message $Option }
    if ($AllowExit) { Write-ChildOutputLine -Level Muted -Message '4. Exit and return to MOC menu' }

    $ChoiceHelp = if ($AllowExit) { (($ValidChoices + @('4','q','Esc')) -join '/') } else { ($ValidChoices -join '/') }
    if (-not [string]::IsNullOrWhiteSpace($DefaultChoice)) {
        Write-ChildOutputLine -Level Prompt -Message ("{0} ({1}; default {2})" -f $Prompt, $ChoiceHelp, $DefaultChoice)
    }
    else {
        Write-ChildOutputLine -Level Prompt -Message ("{0} ({1})" -f $Prompt, $ChoiceHelp) 
    }

    while ($true) {
        $RawChoice = Read-ChildText -Prompt $Prompt -AllowEmpty
        $Choice = ([string]$RawChoice).Trim()

        if ([string]::IsNullOrWhiteSpace($Choice) -and -not [string]::IsNullOrWhiteSpace($DefaultChoice)) {
            $Choice = $DefaultChoice
        }

        $ChoiceLower = $Choice.ToLowerInvariant()
        if ($AllowExit -and ($ChoiceLower -in @('4','q','esc'))) {
            Write-ChildOutputLine -Message 'Selected option: Exit and return to MOC menu'
            return 'ExitToMenu'
        }

        if ($Choice -in $ValidChoices) {
            Write-ChildOutputLine -Message ("Selected option: {0}" -f $Choice)
            return $Choice
        }

        $Help = if ($AllowExit) { (($ValidChoices + @('4','q','Esc')) -join ', ') } else { ($ValidChoices -join ', ') }
        if (-not [string]::IsNullOrWhiteSpace($DefaultChoice)) {
            Write-ChildOutputLine -Level Warning -Message ("Invalid selection. Please enter {0}, or press Enter for {1}." -f $Help, $DefaultChoice) 
        }
        else {
            Write-ChildOutputLine -Level Warning -Message ("Invalid selection. Please enter {0}." -f $Help) 
        }
    }
}

function Get-MOCGraphConnectionMode {
    [CmdletBinding()]
    param()

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
    param([Parameter(Mandatory = $false)][string[]]$RequiredScopes)

    if ($null -eq $RequiredScopes) {
        $RequiredScopes = @($script:MOCChildState.ScriptMetadata.RequiredGraphAppScopes)
    }

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
        throw 'Microsoft Graph connection state is unknown. Authenticate from the MOC menu and try again.'
    }

    return $true
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
    [void]$script:MOCChildState.AuditNotes.Add($Row)
    if ($Severity -match 'Warning|Error') { [void]$script:MOCChildState.Summary.Warnings.Add("[$Severity] $Area - $Message") }
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

    if (-not (Test-Path -LiteralPath $script:MOCChildState.ReportsDir)) { New-Item -ItemType Directory -Path $script:MOCChildState.ReportsDir -Force | Out-Null }

    $CsvPath = Join-Path $script:MOCChildState.ReportsDir $FileName
    $ArrayRows = @($Rows)
    $ArrayRows | Export-Csv -Path $CsvPath -NoTypeInformation -Encoding UTF8

    $RowCount = @($ArrayRows).Count
    Write-ChildOutputLine -Level Success -Message ("Exported {0} row(s) -> {1}" -f $RowCount, (Get-ReportDisplayPath -Path $CsvPath))
    Write-ChildTranscriptLine ("Exported {0} row(s) to {1}" -f $RowCount, $CsvPath)

    if (-not [string]::IsNullOrWhiteSpace($SummaryKey)) {
        $script:MOCChildState.Summary.Counts[$SummaryKey] = $RowCount
        $script:MOCChildState.Summary.Files[$SummaryKey] = $CsvPath
    }

    return $CsvPath
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
    [void]$script:MOCChildState.WorkbookSheets.Add([pscustomobject][ordered]@{
        Name = $Name
        Rows = $SafeRows
        ColumnOrder = $ColumnOrder
        Description = $Description
    })

    $script:MOCChildState.Summary.Counts[$Name] = $SafeRows.Count
    Write-ChildStatusLine ("Staged {0} row(s) for workbook worksheet '{1}'." -f $SafeRows.Count, $Name)
}

function Assert-ImportExcelAvailable {
    [CmdletBinding()]
    param()

    if (-not (Get-Command Export-Excel -ErrorAction SilentlyContinue)) {
        try { Import-Module ImportExcel -ErrorAction Stop }
        catch { throw "The ImportExcel PowerShell module is required for XLSX output. Install ImportExcel or add it to the MOC module load path. Details: $($_.Exception.Message)" }
    }

    return $true
}

function Get-WorkbookSummaryRows {
    [CmdletBinding()]
    param()

    $Rows = [System.Collections.ArrayList]::new()
    [void]$Rows.Add([pscustomobject][ordered]@{ Section = 'Run'; Name = 'Script'; Count = ''; Worksheet = ''; Description = $script:MOCChildState.ScriptName; Value = $script:MOCChildState.ScriptName })
    [void]$Rows.Add([pscustomobject][ordered]@{ Section = 'Run'; Name = 'Version'; Count = ''; Worksheet = ''; Description = 'Script version executed.'; Value = $script:MOCChildState.Version })
    [void]$Rows.Add([pscustomobject][ordered]@{ Section = 'Run'; Name = 'Generated'; Count = ''; Worksheet = ''; Description = 'Report generation timestamp.'; Value = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') })
    [void]$Rows.Add([pscustomobject][ordered]@{ Section = 'Run'; Name = 'OutputFolder'; Count = ''; Worksheet = ''; Description = 'Folder where all output files were written.'; Value = $script:MOCChildState.ReportsDir })

    foreach ($Sheet in @($script:MOCChildState.WorkbookSheets)) {
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

            $LongColumnNames = @('SettingValue','PolicyAValue','PolicyBValue','AssignmentSummary','ReviewReason','RawValueJson','Error','ErrorMessage','Exception','Uri','Description','Notes')
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

function Export-MOCWorkbook {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)][string]$Path,
        [Parameter(Mandatory = $false)][switch]$OpenAfterExport
    )

    [void](Assert-ImportExcelAvailable)
    if ([string]::IsNullOrWhiteSpace($Path)) { $Path = $script:MOCChildState.WorkbookPath }

    $WorkbookDirectory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $WorkbookDirectory)) { New-Item -ItemType Directory -Path $WorkbookDirectory -Force | Out-Null }
    if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue }

    Write-ChildStatusLine "Creating Excel workbook: $Path"
    $SummaryRows = @(ConvertTo-ExcelSafeRows -Rows @(Get-WorkbookSummaryRows) -ColumnOrder @('Section','Name','Count','Worksheet','Description','Value'))
    $SummaryRows | Export-Excel -Path $Path -WorksheetName 'Summary' -TableName 'Summary' -TableStyle Light9 -AutoSize -FreezeTopRow -BoldTopRow -ClearSheet

    $UsedTables = @{ Summary = $true }
    $UsedWorksheets = @{ Summary = $true }

    foreach ($Sheet in @($script:MOCChildState.WorkbookSheets)) {
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
        $Rows | Export-Excel -Path $Path -WorksheetName $WorksheetName -TableName $TableName -TableStyle Light9 -AutoSize -FreezeTopRow -BoldTopRow -Append
    }

    Set-MOCWorkbookStyle -Path $Path

    if (-not (Test-Path -LiteralPath $Path)) { throw "Workbook writer completed without error, but file was not found: $Path" }
    $WorkbookItem = Get-Item -LiteralPath $Path -ErrorAction Stop
    if ($WorkbookItem.Length -le 0) { throw "Workbook file was created but its size is 0 bytes: $Path" }

    $script:MOCChildState.Summary.Files['Workbook'] = $Path
    Write-ChildStatusLine ("Excel workbook written -> {0}" -f (Get-ReportDisplayPath -Path $Path))
    Write-ChildStatusLine ("Workbook size: {0:N0} bytes" -f $WorkbookItem.Length)

    if ($OpenAfterExport) { Open-MOCOutputFile -Path $Path -Description 'Excel workbook' }
    return $Path
}

function Open-MOCOutputFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $false)][string]$Description = 'output file'
    )

    if ($script:MOCChildState.DoNotOpenOutput) {
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

function Invoke-ScriptStep {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][int]$StepNumber,
        [Parameter(Mandatory = $false)][int]$TotalSteps = $script:MOCChildState.TotalSteps,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$ScriptBlock
    )

    $Percent = (($StepNumber - 1) / [Math]::Max($TotalSteps, 1)) * 100
    Update-ChildProgress -Activity $script:MOCChildState.ScriptName -Percent $Percent -Status ("Step {0} of {1} - {2}" -f $StepNumber, $TotalSteps, $Name) -CurrentOperation ''

    Write-ChildOutputLine -Message ''

    Write-ChildOutputLine `
        -Level Header `
        -Message '========================================================================'
        

    Write-ChildOutputLine `
        -Level Header `
        -Message ("[Step {0} of {1}] {2}" -f $StepNumber, $TotalSteps, $Name) 
        

    Write-ChildOutputLine `
        -Level Header `
        -Message '========================================================================' `
        


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
    Update-ChildProgress -Activity $script:MOCChildState.ScriptName -Percent $Percent -Status ("Completed Step {0} of {1} - {2}" -f $StepNumber, $TotalSteps, $Name) -CurrentOperation ''
}

function Complete-MOCChildRun {
    [CmdletBinding()]
    param([Parameter(Mandatory = $false)][switch]$ExportAuditNotes)

    if ($ExportAuditNotes -and $script:MOCChildState.AuditNotes.Count -gt 0) {
        Export-AuditCsv -Rows $script:MOCChildState.AuditNotes -FileName (Split-Path -Leaf $script:MOCChildState.AuditNotesPath) -SummaryKey 'AuditNotes' | Out-Null
    }

    $script:MOCChildState.Summary.CompletedDateTime = (Get-Date).ToString('o')
    Set-MOCUtf8FileContent -Path $script:MOCChildState.SummaryPath -Content ($script:MOCChildState.Summary | ConvertTo-Json -Depth 8)
    Write-ChildStatusLine ("Summary saved -> {0}" -f (Get-ReportDisplayPath -Path $script:MOCChildState.SummaryPath))

    return Get-MOCChildState
}

Export-ModuleMember -Function @(
    'Get-MOCChildState',
    'Get-MOCScriptMetadata',
    'Initialize-MOCChildRun',
    'Write-ChildOutputLine',
    'Write-ChildStatusLine',
    'Write-ChildTranscriptLine',
    'Update-ChildProgress',
    'Get-ReportDisplayPath',
    'Read-ChildText',
    'Read-ChildMenuChoice',
    'Get-MOCGraphConnectionMode',
    'Assert-MOCGraphPermission',
    'Add-AuditNote',
    'Set-MOCUtf8FileContent',
    'Export-AuditCsv',
    'ConvertTo-ExcelSafeText',
    'ConvertTo-ExcelSafeValue',
    'ConvertTo-ExcelSafeRows',
    'Get-SafeExcelWorksheetName',
    'Get-SafeExcelTableName',
    'Add-WorkbookWorksheet',
    'Assert-ImportExcelAvailable',
    'Get-WorkbookSummaryRows',
    'Set-MOCWorkbookStyle',
    'Export-MOCWorkbook',
    'Open-MOCOutputFile',
    'Invoke-ScriptStep',
    'Complete-MOCChildRun',
    'Set-MOCChildOutputRenderer',
    'Clear-MOCChildOutputRenderer'
)
