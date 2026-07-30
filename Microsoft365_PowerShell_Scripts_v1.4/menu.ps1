# menu.ps1 - PowerShell TUI Script Launcher
# Stable baseline with numeric jump + enhanced Launcher-Reports logging
# PowerShell 7.6 compatible

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

if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir | Out-Null
}

$LogFile = Join-Path $LogDir ("Launcher-{0}.log" -f (Get-Date -Format 'yyyy-MM-dd'))
$CurrentUser = $env:USERNAME

# ------------------------------------------------------------
# Colors
# ------------------------------------------------------------
$C_Title    = 'Cyan'
$C_Folder   = 'Yellow'
$C_Selected = 'Green'
$C_Normal   = 'Gray'
$C_Help     = 'DarkYellow'

# ------------------------------------------------------------
# Logging helpers
# ------------------------------------------------------------
function Format-Duration {
    param([double]$Seconds)
    $ts = [TimeSpan]::FromSeconds([Math]::Round($Seconds))
    return ('{0:mm\:ss}' -f $ts)
}

function Write-LauncherLog {
    param(
        [string]$Action,
        [string]$ScriptName,
        [string]$Duration = '',
        [int]$ExitCode = 0
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

    if ($Action -eq 'FAIL') {
        "$timestamp | User=$CurrentUser | Action=FAIL | Script=$ScriptName | ExitCode=$ExitCode | Duration=$Duration" |
            Out-File -Append -Encoding utf8 $LogFile
    }
    elseif ($Action -eq 'END') {
        "$timestamp | User=$CurrentUser | Action=END | Script=$ScriptName | Duration=$Duration" |
            Out-File -Append -Encoding utf8 $LogFile
    }
    else {
        "$timestamp | User=$CurrentUser | Action=$Action | Script=$ScriptName" |
            Out-File -Append -Encoding utf8 $LogFile
    }
}

function Write-DailyTotal {
    if (-not (Test-Path $LogFile)) { return }

    $totalSeconds = 0
    foreach ($line in Get-Content $LogFile) {
        if ($line -match 'Duration=(\d+:\d+)') {
            $ts = [TimeSpan]::Parse($matches[1])
            $totalSeconds += $ts.TotalSeconds
        }
    }

    $totalFormatted = Format-Duration $totalSeconds
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

    "$timestamp | User=$CurrentUser | DAILY_TOTAL | Runtime=$totalFormatted" |
        Out-File -Append -Encoding utf8 $LogFile
}

# ------------------------------------------------------------
# Discover scripts (immutable list)
# ------------------------------------------------------------
$Scripts = @()

Get-ChildItem -Directory $RootPath |
Sort-Object @{ Expression = { $_.Name -ne $RunFirstFolder } }, Name |
ForEach-Object {
    $folder = $_.Name
    Get-ChildItem $_.FullName -Filter *.ps1 -File |
    Where-Object Name -ne 'menu.ps1' |
    ForEach-Object {
        $Scripts += [pscustomobject]@{
            Folder = $folder
            Name   = $_.Name
            Path   = $_.FullName
        }
    }
}

if ($Scripts.Count -eq 0) {
    Write-Host 'No scripts found.'
    exit
}

# ------------------------------------------------------------
# State
# ------------------------------------------------------------
$Index        = 0
$NumberBuffer = ''

# ------------------------------------------------------------
# Main loop
# ------------------------------------------------------------
while ($true) {
    Clear-Host

    if ($Index -ge $Scripts.Count) { $Index = 0 }

    Write-Host '  PowerShell Automation Launcher' -ForegroundColor $C_Title
    Write-Host '  --------------------------------' -ForegroundColor $C_Title

    $CurrentFolder = ''
    for ($i = 0; $i -lt $Scripts.Count; $i++) {
        if ($Scripts[$i].Folder -ne $CurrentFolder) {
            Write-Host ''
            Write-Host "  $($Scripts[$i].Folder)" -ForegroundColor $C_Folder
            $CurrentFolder = $Scripts[$i].Folder
        }

        $Color = if ($i -eq $Index) { $C_Selected } else { $C_Normal }
        Write-Host ("    [{0}] {1}" -f ($i + 1), $Scripts[$i].Name) -ForegroundColor $Color
    }

    Write-Host ''
    if ($NumberBuffer) {
        Write-Host "  Jump to #: $NumberBuffer  (Enter to confirm)" -ForegroundColor $C_Help
    }
    else {
        Write-Host '  Up/Down Move | Type Number + Enter = Jump | Enter = Run | Q = Quit' -ForegroundColor $C_Help
    }

    $Key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')

    # ---------------- Quit ----------------
    if ($Key.Character -match '[Qq]') {
        Write-LauncherLog -Action 'EXIT' -ScriptName 'Launcher'
        Write-DailyTotal
        break
    }

    # ---------------- Numeric input (PS 7 safe) ----------------
    if (
        ($Key.VirtualKeyCode -ge 49 -and $Key.VirtualKeyCode -le 57) -or
        ($Key.VirtualKeyCode -ge 97 -and $Key.VirtualKeyCode -le 105)
    ) {
        $digit = if ($Key.VirtualKeyCode -ge 97) {
            $Key.VirtualKeyCode - 96
        } else {
            $Key.VirtualKeyCode - 48
        }
        $NumberBuffer += $digit
        continue
    }

    if ($Key.VirtualKeyCode -eq 8 -and $NumberBuffer.Length -gt 0) {
        $NumberBuffer = $NumberBuffer.Substring(0, $NumberBuffer.Length - 1)
        continue
    }

    # ---------------- Enter ----------------
    if ($Key.VirtualKeyCode -eq 13) {

        if ($NumberBuffer.Length -gt 0) {
            $target = [int]$NumberBuffer - 1
            if ($target -ge 0 -and $target -lt $Scripts.Count) {
                $Index = $target
            }
            $NumberBuffer = ''
            continue
        }

        $script = $Scripts[$Index]

        Clear-Host
        Write-Host "Running $($script.Name)" -ForegroundColor $C_Selected

        $start = Get-Date
        Write-LauncherLog -Action 'START' -ScriptName $script.Name

        $proc = Start-Process pwsh `
            "-NoProfile -File `"$($script.Path)`"" `
            -Wait -PassThru

        $durationSeconds = ((Get-Date) - $start).TotalSeconds
        $durationFormatted = Format-Duration $durationSeconds

        if ($proc.ExitCode -ne 0) {
            Write-LauncherLog -Action 'FAIL' -ScriptName $script.Name -ExitCode $proc.ExitCode -Duration $durationFormatted
        }
        else {
            Write-LauncherLog -Action 'END' -ScriptName $script.Name -Duration $durationFormatted
        }

        Write-Host ''
        Write-Host "Completed in $durationFormatted. Press Enter to return." -ForegroundColor $C_Help
        [void]$Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    }

    # ---------------- Navigation ----------------
    if ($Key.VirtualKeyCode -eq 38 -and $Index -gt 0) {
        $Index--
    }
    elseif ($Key.VirtualKeyCode -eq 40 -and $Index -lt $Scripts.Count - 1) {
        $Index++
    }
}

# ------------------------------------------------------------
# Restore cursor
# ------------------------------------------------------------
try {
    $Host.UI.RawUI.CursorSize = $OriginalCursorSize
} catch {}