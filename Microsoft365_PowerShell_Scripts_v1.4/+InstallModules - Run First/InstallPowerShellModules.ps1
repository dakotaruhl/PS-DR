# 04/08/2026 - Full rewrite: reliable elevation, transcript logging, safe Graph reset/install, pinned versions.
# 04/07/2026 - Added the new PowerShell Module "Az" which allows you to Authenticate to Azure & Azure Key Vault.
# 12/18/2025 - Updated minimum Microsoft.Graph -RequiredVersion 2.33.0
# 10/21/2025 - Updated minimum PowerShell modules (SharePoint & Microsoft Graph) to the latest as of this date.
# 08/28/2025 - Added lines to check if AzureAD and MSOnline modules are installed, and remove as Microsoft has deprecated them.
# 08/28/2025 - Update Microsoft.Graph modules to the latest supported v2.30.0.
# 08/28/2025 - Updated minimum Powershell modules to the latest as of this date.
# 04/02/2025 - Updated minimum PowerShell module version for ExchangeOnlineManagement to 3.7.2.
# 02/25/2025 - Updated minimum PowerShell module versions.

# Purpose of this script: Check if PowerShell modules exist, and if not, install them.

# ----------------------------
# Self-elevate (Admin required for -Scope AllUsers installs/uninstalls)
# ----------------------------
$IsAdmin = $false
try {
    $IsAdmin = (New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
} catch {}

if (-not $IsAdmin) {
    Write-Host "Restarting in elevated (Administrator) mode..." -ForegroundColor Yellow
    Start-Process pwsh "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

# ----------------------------
# Setup paths + transcript
# ----------------------------
$ScriptDir  = Split-Path -Parent $PSCommandPath
$ReportsDir = Join-Path $ScriptDir "Reports"
if (-not (Test-Path $ReportsDir)) { New-Item -ItemType Directory -Path $ReportsDir | Out-Null }

$TranscriptPath = Join-Path $ReportsDir ("InstallPowerShellModules-{0}.txt" -f (Get-Date -Format "yyyy-MM-dd_HH-mm-ss"))
Start-Transcript -Path $TranscriptPath -Append | Out-Null

# Speed up module operations a bit (optional)
$ProgressPreference = 'SilentlyContinue'

try {
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host " Install PowerShell Modules (Admin) - $(Get-Date)" -ForegroundColor Cyan
    Write-Host " Transcript: $TranscriptPath" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""

    # ----------------------------
    # Prereqs: NuGet + PSGallery
    # ----------------------------
    Write-Host "Ensuring NuGet provider and PSGallery trust..." -ForegroundColor Yellow
    try {
        if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
            Install-PackageProvider -Name NuGet -Force | Out-Null
        }
    } catch {
        Write-Host "WARNING: Could not ensure NuGet provider. $_" -ForegroundColor Yellow
    }

    try {
        $psg = Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue
        if ($psg -and $psg.InstallationPolicy -ne 'Trusted') {
            Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
        }
    } catch {
        Write-Host "WARNING: Could not set PSGallery to Trusted. $_" -ForegroundColor Yellow
    }

    # ----------------------------
    # Helper functions
    # ----------------------------
    function Write-Section($text) {
        Write-Host ""
        Write-Host "---- $text ----" -ForegroundColor Cyan
    }

    function Ensure-ModuleMinimum {
        param(
            [Parameter(Mandatory=$true)][string]$Name,
            [Parameter(Mandatory=$true)][version]$MinimumVersion,
            [ValidateSet('AllUsers','CurrentUser')][string]$Scope = 'AllUsers'
        )

        Write-Host "Checking $Name (min $MinimumVersion)..." -ForegroundColor Yellow

        $installed = $null
        try { $installed = Get-InstalledModule -Name $Name -ErrorAction SilentlyContinue } catch {}

        if ($installed -and ([version]$installed.Version -ge $MinimumVersion)) {
            Write-Host "OK: $Name $($installed.Version) installed." -ForegroundColor Green
            return
        }

        Write-Host "Installing/Updating $Name to meet minimum version..." -ForegroundColor Yellow
        try {
            Install-Module -Name $Name -MinimumVersion $MinimumVersion -Scope $Scope -Force -AllowClobber
            $new = Get-InstalledModule -Name $Name -ErrorAction SilentlyContinue
            if ($new) {
                Write-Host "OK: $Name $($new.Version) installed." -ForegroundColor Green
            } else {
                Write-Host "WARNING: $Name install completed but module not detected." -ForegroundColor Yellow
            }
        } catch {
            Write-Host "ERROR: Failed installing $Name. $_" -ForegroundColor Red
        }
    }

    function Ensure-ModuleExact {
        param(
            [Parameter(Mandatory=$true)][string]$Name,
            [Parameter(Mandatory=$true)][version]$RequiredVersion,
            [ValidateSet('AllUsers','CurrentUser')][string]$Scope = 'AllUsers'
        )

        Write-Host "Checking $Name (required $RequiredVersion)..." -ForegroundColor Yellow

        $installed = $null
        try { $installed = Get-InstalledModule -Name $Name -ErrorAction SilentlyContinue } catch {}

        if ($installed -and ([version]$installed.Version -eq $RequiredVersion)) {
            Write-Host "OK: $Name $($installed.Version) installed." -ForegroundColor Green
            return
        }

        Write-Host "Installing $Name $RequiredVersion..." -ForegroundColor Yellow
        try {
            Install-Module -Name $Name -RequiredVersion $RequiredVersion -Scope $Scope -Force -AllowClobber
            $new = Get-InstalledModule -Name $Name -ErrorAction SilentlyContinue
            if ($new) {
                Write-Host "OK: $Name $($new.Version) installed." -ForegroundColor Green
            } else {
                Write-Host "WARNING: $Name install completed but module not detected." -ForegroundColor Yellow
            }
        } catch {
            Write-Host "ERROR: Failed installing $Name $RequiredVersion. $_" -ForegroundColor Red
        }
    }

    function Remove-DeprecatedModule {
        param([Parameter(Mandatory=$true)][string]$Name)

        Write-Host "Checking for deprecated module: $Name" -ForegroundColor Yellow
        $installed = $null
        try { $installed = Get-InstalledModule -Name $Name -ErrorAction SilentlyContinue } catch {}

        if (-not $installed) {
            Write-Host "OK: $Name not found." -ForegroundColor Green
            return
        }

        Write-Host "Removing deprecated module: $Name ($($installed.Version))" -ForegroundColor Yellow
        try {
            Get-Module $Name -All | Remove-Module -Force -ErrorAction SilentlyContinue
            Uninstall-Module -Name $Name -AllVersions -Force -ErrorAction SilentlyContinue
            Write-Host "OK: $Name removed." -ForegroundColor Green
        } catch {
            Write-Host "WARNING: Could not fully remove $Name. $_" -ForegroundColor Yellow
        }
    }

    function Reset-MicrosoftGraph {
        param(
            [version]$RequiredVersion = [version]'2.36.1',
            [ValidateSet('AllUsers','CurrentUser')][string]$Scope = 'AllUsers'
        )

        Write-Section "Microsoft Graph Module Reset/Install"

        # Disconnect only if cmdlet exists + context exists (avoid noise)
        if (Get-Command Get-MgContext -ErrorAction SilentlyContinue) {
            try {
                $ctx = Get-MgContext
                if ($ctx) { Disconnect-MgGraph -ErrorAction SilentlyContinue }
            } catch {}
        }

        # If Graph.Authentication is loaded in THIS session, skip uninstall to avoid file-lock warnings.
        $graphAuthLoaded = $false
        try { $graphAuthLoaded = [bool](Get-Module Microsoft.Graph.Authentication -ErrorAction SilentlyContinue) } catch {}

        if ($graphAuthLoaded) {
            Write-Host "WARNING: Microsoft.Graph.Authentication is currently loaded in this session." -ForegroundColor Yellow
            Write-Host "Skipping Graph uninstall/reset to avoid file-lock issues." -ForegroundColor Yellow
            Write-Host "Close other PowerShell/Terminal/VS Code sessions using Graph to fully reset later." -ForegroundColor Yellow

            # Still ensure required version is installed (side-by-side installs are OK)
            Ensure-ModuleExact -Name Microsoft.Graph -RequiredVersion $RequiredVersion -Scope $Scope
            return
        }

        # Remove loaded Graph modules from THIS session to avoid locks
        Get-Module Microsoft.Graph* | Remove-Module -Force -ErrorAction SilentlyContinue

        # Attempt uninstall in correct dependency order:
        # 1) meta-module Microsoft.Graph
        # 2) submodules Microsoft.Graph.*
        # If locked by OTHER processes, catch and continue.

        $uninstallBlocked = $false

        try {
            if (Get-InstalledModule -Name Microsoft.Graph -ErrorAction SilentlyContinue) {
                Uninstall-Module -Name Microsoft.Graph -AllVersions -Force -ErrorAction Stop
            }
        } catch {
            $uninstallBlocked = $true
            Write-Host "WARNING: Could not uninstall Microsoft.Graph (likely in use by another process)." -ForegroundColor Yellow
            Write-Host "         $_" -ForegroundColor DarkYellow
        }

        if (-not $uninstallBlocked) {
            try {
                Get-InstalledModule Microsoft.Graph.* -ErrorAction SilentlyContinue |
                    ForEach-Object {
                        try {
                            Uninstall-Module -Name $_.Name -AllVersions -Force -ErrorAction Stop
                        } catch {
                            Write-Host "WARNING: Could not uninstall $($_.Name) (may be locked)." -ForegroundColor Yellow
                        }
                    }
            } catch {
                Write-Host "WARNING: Issue enumerating Graph submodules. $_" -ForegroundColor Yellow
            }
        }
        else {
            Write-Host "NOTE: Skipping submodule uninstall because the Graph meta-module uninstall was blocked." -ForegroundColor Yellow
        }

        # Ensure pinned version is present regardless of uninstall success
        Ensure-ModuleExact -Name Microsoft.Graph -RequiredVersion $RequiredVersion -Scope $Scope
    }

    # ----------------------------
    # Remove deprecated modules
    # ----------------------------
    Write-Section "Remove Deprecated Modules"
    Remove-DeprecatedModule -Name "AzureADPreview"
    Remove-DeprecatedModule -Name "MSOnline"

    # ----------------------------
    # Install/Update required modules
    # ----------------------------
    Write-Section "Ensure Required Modules"

    # Az (for Key Vault auth/workflows)
    Ensure-ModuleMinimum -Name "Az" -MinimumVersion ([version]'15.4.0') -Scope AllUsers

    # Exchange Online
    Ensure-ModuleMinimum -Name "ExchangeOnlineManagement" -MinimumVersion ([version]'3.9.2') -Scope AllUsers

    # SharePoint Online
    Ensure-ModuleMinimum -Name "Microsoft.Online.SharePoint.PowerShell" -MinimumVersion ([version]'16.0.27111.12000') -Scope AllUsers

    # Microsoft Graph pinned install (safe reset)
    Reset-MicrosoftGraph -RequiredVersion ([version]'2.36.1') -Scope AllUsers

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host " Module verification complete." -ForegroundColor Green
    Write-Host " If you see any RED text above, capture the transcript and escalate." -ForegroundColor Green
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host ""
}
finally {
    try { Stop-Transcript | Out-Null } catch {}
    Write-Host "Press any key to exit..." -ForegroundColor DarkYellow
    try { [void]$Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown') } catch {}
}
