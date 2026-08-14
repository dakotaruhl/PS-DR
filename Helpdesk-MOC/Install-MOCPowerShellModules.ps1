<#
.SYNOPSIS
Installs and updates approved MOC PowerShell module prerequisites.

.DESCRIPTION
Maintenance script for the M365 Operations Console (MOC). This script installs or updates the approved PowerShell modules used by MOC parent authentication and MOC child scripts.

This build is OS-aware and supports Windows, Linux, and macOS behavior:
- Windows AllUsers installs can relaunch through UAC using Start-Process -Verb RunAs.
- Linux/macOS AllUsers installs require the script to already be running as root/sudo.
- CurrentUser installs are recommended for Linux/macOS and do not attempt self-elevation.

.VERSION
1.3.1

.AUTHOR
Long

.CATEGORY
MOC Maintenance

.OUTPUTFORMAT
Transcript

.REQUIREDGRAPHAPPSCOPES
None

.REQUIREDPOWERSHELLMODULES
PowerShellGet
PackageManagement

.CREATED
2026-06-12

.LASTMODIFIED
2026-06-29

.CHANGELOG
1.3.1 - Suppresses the deprecated module cleanup section when AzureADPreview, AzureAD, and MSOnline are not installed. Only displays cleanup output when deprecated modules are detected and removal is attempted.
1.3.0 - Adds Windows/Linux/macOS-aware elevation handling. Defaults to CurrentUser for cross-platform compatibility. Removes Windows-only -Verb RunAs usage on Linux/macOS. Adds OS/platform reporting and safer pause behavior.
1.2.1 - Reissued full canonical installer text with online PSGallery check/upgrade modes for MOC Module Maintenance.
1.2.0 - Adds -Mode InstallMissing/UpgradeAll so MOC can install missing approved modules or explicitly upgrade approved modules to the latest PSGallery versions.
1.1.0 - Adds Microsoft.Graph.Beta.Reports and ImportExcel to the MOC approved module set. Writes transcripts under MOC\Transcript Logs. Keeps installation separate from child-script execution.
1.0.0 - Baseline module installer with elevation, NuGet/PSGallery setup, deprecated module cleanup, and pinned Microsoft Graph install.
#>

[CmdletBinding()]
param(
    [ValidateSet('AllUsers','CurrentUser')]
    [string]$Scope = 'CurrentUser',

    [ValidateSet('InstallMissing','UpgradeAll')]
    [string]$Mode = 'InstallMissing',

    [switch]$SkipGraphReset,

    [switch]$NoPause
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Test-IsWindowsOS {
    if ($PSVersionTable.PSEdition -eq 'Desktop') { return $true }
    try {
        return [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Windows)
    }
    catch { return $false }
}

function Test-IsLinuxOS {
    try {
        return [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Linux)
    }
    catch { return $false }
}

function Test-IsMacOS {
    try {
        return [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::OSX)
    }
    catch { return $false }
}

function Get-MOCPlatformName {
    if (Test-IsWindowsOS) { return 'Windows' }
    if (Test-IsLinuxOS) { return 'Linux' }
    if (Test-IsMacOS) { return 'macOS' }
    return 'Unknown'
}

function Test-IsElevated {
    if (Test-IsWindowsOS) {
        try {
            $Identity = [Security.Principal.WindowsIdentity]::GetCurrent()
            $Principal = [Security.Principal.WindowsPrincipal]::new($Identity)
            return $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        }
        catch { return $false }
    }

    try {
        $IdCommand = Get-Command id -ErrorAction SilentlyContinue
        if ($null -eq $IdCommand) { return $false }
        $Uid = & id -u
        return ([int]$Uid -eq 0)
    }
    catch { return $false }
}

function Write-Section {
    param([Parameter(Mandatory)][string]$Text)

    Write-Host ''
    Write-Host ('=' * 72) -ForegroundColor Cyan
    Write-Host $Text -ForegroundColor Cyan
    Write-Host ('=' * 72) -ForegroundColor Cyan
}

function Write-Result {
    param(
        [Parameter(Mandatory)][ValidateSet('OK','WARN','ERROR','INFO')][string]$Level,
        [Parameter(Mandatory)][string]$Message
    )

    $Color = switch ($Level) {
        'OK'    { 'Green' }
        'WARN'  { 'Yellow' }
        'ERROR' { 'Red' }
        'INFO'  { 'Cyan' }
        default { 'White' }
    }

    Write-Host ("[{0}] {1}" -f $Level, $Message) -ForegroundColor $Color
}

function Get-CurrentPwshPath {
    try {
        $Pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
        if (-not [string]::IsNullOrWhiteSpace($Pwsh)) { return $Pwsh }
    }
    catch {}

    try {
        $WindowsPowerShell = (Get-Command powershell -ErrorAction SilentlyContinue).Source
        if (-not [string]::IsNullOrWhiteSpace($WindowsPowerShell)) { return $WindowsPowerShell }
    }
    catch {}

    return $null
}

function Invoke-WindowsSelfElevationIfNeeded {
    if ($Scope -ne 'AllUsers') { return $false }
    if (-not (Test-IsWindowsOS)) { return $false }
    if (Test-IsElevated) { return $false }

    Write-Host 'Restarting in elevated Administrator mode for AllUsers module installation...' -ForegroundColor Yellow

    $Pwsh = Get-CurrentPwshPath
    if ([string]::IsNullOrWhiteSpace($Pwsh)) {
        throw 'Could not locate pwsh or powershell for elevated relaunch.'
    }

    $ArgumentList = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', ('"{0}"' -f $PSCommandPath),
        '-Scope', 'AllUsers',
        '-Mode', $Mode
    )

    if ($SkipGraphReset) { $ArgumentList += '-SkipGraphReset' }
    if ($NoPause) { $ArgumentList += '-NoPause' }

    Start-Process -FilePath $Pwsh -ArgumentList $ArgumentList -Verb RunAs | Out-Null
    return $true
}

function Assert-InstallScopeAllowed {
    if ($Scope -ne 'AllUsers') { return }
    if (Test-IsElevated) { return }

    if (Test-IsWindowsOS) {
        return
    }

    Write-Result ERROR 'AllUsers module installation requires root/sudo on Linux/macOS.'
    Write-Result INFO 'Recommended current-user install:'
    Write-Result INFO ('  pwsh "{0}" -Scope CurrentUser -Mode {1}' -f $PSCommandPath, $Mode)
    Write-Result INFO 'System-wide install:'
    Write-Result INFO ('  sudo pwsh "{0}" -Scope AllUsers -Mode {1}' -f $PSCommandPath, $Mode)
    throw 'AllUsers scope requested without root/sudo.'
}

if (Invoke-WindowsSelfElevationIfNeeded) { exit }
Assert-InstallScopeAllowed

$ScriptDir = Split-Path -Parent $PSCommandPath
if ([string]::IsNullOrWhiteSpace($ScriptDir)) { $ScriptDir = (Get-Location).Path }

$TranscriptRoot = Join-Path $ScriptDir 'Transcript Logs'
if (-not (Test-Path -LiteralPath $TranscriptRoot)) {
    New-Item -ItemType Directory -Path $TranscriptRoot -Force | Out-Null
}

$TranscriptPath = Join-Path $TranscriptRoot ("MOC-ModuleMaintenance-{0}.txt" -f (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'))

try {
    Start-Transcript -Path $TranscriptPath -Force | Out-Null
}
catch {
    Write-Result WARN "Could not start transcript: $($_.Exception.Message)"
}

$script:HadError = $false

function Ensure-PowerShellGetAvailable {
    Write-Section 'PowerShellGet and PackageManagement setup'

    $RequiredBootstrapModules = @('PowerShellGet','PackageManagement')
    foreach ($ModuleName in $RequiredBootstrapModules) {
        try {
            $Module = Get-Module -ListAvailable -Name $ModuleName -ErrorAction SilentlyContinue |
                Sort-Object Version -Descending |
                Select-Object -First 1

            if ($Module) {
                Write-Result OK ("{0} {1} is available." -f $ModuleName, $Module.Version)
            }
            else {
                Write-Result WARN ("{0} was not detected. Install-Module operations may fail until PowerShellGet is installed." -f $ModuleName)
            }
        }
        catch {
            $script:HadError = $true
            Write-Result ERROR ("Could not validate {0}: {1}" -f $ModuleName, $_.Exception.Message)
        }
    }
}

function Ensure-NuGetAndGallery {
    Write-Section 'PowerShell Gallery setup'

    try {
        if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
            Write-Result INFO 'Installing NuGet package provider.'
            Install-PackageProvider -Name NuGet -Force -Scope $Scope | Out-Null
        }
        else {
            Write-Result OK 'NuGet package provider is available.'
        }
    }
    catch {
        $script:HadError = $true
        Write-Result ERROR "Could not ensure NuGet provider: $($_.Exception.Message)"
    }

    try {
        $Repo = Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue
        if ($Repo -and $Repo.InstallationPolicy -ne 'Trusted') {
            Write-Result INFO 'Setting PSGallery installation policy to Trusted.'
            Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
        }
        elseif ($Repo) {
            Write-Result OK 'PSGallery is available.'
        }
        else {
            $script:HadError = $true
            Write-Result ERROR 'PSGallery repository was not found.'
        }
    }
    catch {
        $script:HadError = $true
        Write-Result ERROR "Could not validate PSGallery: $($_.Exception.Message)"
    }
}

function Get-InstalledDeprecatedMOCModules {
    param(
        [string[]]$Names = @('AzureADPreview','AzureAD','MSOnline')
    )

    $Detected = New-Object System.Collections.Generic.List[string]

    foreach ($Name in $Names) {
        try {
            $Installed = @(Get-InstalledModule -Name $Name -ErrorAction SilentlyContinue)
            $ListAvailable = @(Get-Module -ListAvailable -Name $Name -ErrorAction SilentlyContinue)

            if (($Installed.Count -gt 0) -or ($ListAvailable.Count -gt 0)) {
                [void]$Detected.Add($Name)
            }
        }
        catch {
            # Detection should never stop module maintenance. If PowerShellGet cannot query the module,
            # leave removal to the explicit cleanup function only when the module is otherwise detected.
        }
    }

    return @($Detected)
}

function Remove-DeprecatedModule {
    param([Parameter(Mandatory)][string]$Name)

    try {
        $Installed = @(Get-InstalledModule -Name $Name -ErrorAction SilentlyContinue)
        $ListAvailable = @(Get-Module -ListAvailable -Name $Name -ErrorAction SilentlyContinue)

        if (($Installed.Count -eq 0) -and ($ListAvailable.Count -eq 0)) {
            return
        }

        Write-Result WARN "Removing deprecated module $Name."
        Get-Module $Name -All | Remove-Module -Force -ErrorAction SilentlyContinue
        Uninstall-Module -Name $Name -AllVersions -Force -ErrorAction SilentlyContinue

        $RemainingInstalled = @(Get-InstalledModule -Name $Name -ErrorAction SilentlyContinue)
        $RemainingAvailable = @(Get-Module -ListAvailable -Name $Name -ErrorAction SilentlyContinue)

        if (($RemainingInstalled.Count -eq 0) -and ($RemainingAvailable.Count -eq 0)) {
            Write-Result OK "$Name removed."
        }
        else {
            Write-Result WARN "$Name removal was attempted, but one or more copies may still be available on the module path."
        }
    }
    catch {
        Write-Result WARN "Could not fully remove $Name`: $($_.Exception.Message)"
    }
}

function Get-InstalledHighestVersion {
    param([Parameter(Mandatory)][string]$Name)

    try {
        return Get-Module -ListAvailable -Name $Name -ErrorAction SilentlyContinue |
            Sort-Object Version -Descending |
            Select-Object -First 1
    }
    catch { return $null }
}

function Ensure-ModuleMinimum {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][version]$MinimumVersion,
        [ValidateSet('AllUsers','CurrentUser')][string]$InstallScope = $Scope
    )

    $Current = Get-InstalledHighestVersion -Name $Name
    if ($Current -and [version]$Current.Version -ge $MinimumVersion) {
        Write-Result OK ("{0} {1} installed. Minimum required: {2}." -f $Name, $Current.Version, $MinimumVersion)
        return
    }

    if ($Current) {
        Write-Result INFO ("Updating {0}. Installed: {1}. Minimum required: {2}." -f $Name, $Current.Version, $MinimumVersion)
    }
    else {
        Write-Result INFO ("Installing {0}. Minimum required: {1}." -f $Name, $MinimumVersion)
    }

    try {
        Install-Module -Name $Name -MinimumVersion $MinimumVersion -Scope $InstallScope -Force -AllowClobber -ErrorAction Stop
        $New = Get-InstalledHighestVersion -Name $Name
        if ($New) {
            Write-Result OK ("{0} {1} installed." -f $Name, $New.Version)
        }
        else {
            $script:HadError = $true
            Write-Result ERROR "$Name install completed but the module was not detected."
        }
    }
    catch {
        $script:HadError = $true
        Write-Result ERROR "Failed installing $Name`: $($_.Exception.Message)"
    }
}

function Get-PSGalleryLatestVersion {
    param([Parameter(Mandatory)][string]$Name)

    try {
        $Latest = Find-Module -Name $Name -Repository PSGallery -ErrorAction Stop
        if ($Latest -and $Latest.Version) { return [version]$Latest.Version }
    }
    catch {
        Write-Result WARN "Could not check PSGallery latest version for $Name`: $($_.Exception.Message)"
    }

    return $null
}

function Ensure-ModuleLatest {
    param(
        [Parameter(Mandatory)][string]$Name,
        [ValidateSet('AllUsers','CurrentUser')][string]$InstallScope = $Scope
    )

    $LatestVersion = Get-PSGalleryLatestVersion -Name $Name
    if ($null -eq $LatestVersion) {
        $script:HadError = $true
        Write-Result ERROR "Could not determine latest PSGallery version for $Name."
        return
    }

    $Current = Get-InstalledHighestVersion -Name $Name
    if ($Current -and [version]$Current.Version -ge $LatestVersion) {
        Write-Result OK ("{0} {1} installed. Latest PSGallery version: {2}." -f $Name, $Current.Version, $LatestVersion)
        return
    }

    if ($Current) {
        Write-Result INFO ("Upgrading {0}. Installed: {1}. Latest PSGallery version: {2}." -f $Name, $Current.Version, $LatestVersion)
    }
    else {
        Write-Result INFO ("Installing {0}. Latest PSGallery version: {1}." -f $Name, $LatestVersion)
    }

    try {
        Install-Module -Name $Name -RequiredVersion $LatestVersion -Scope $InstallScope -Force -AllowClobber -ErrorAction Stop
        $New = Get-InstalledHighestVersion -Name $Name
        if ($New) {
            Write-Result OK ("{0} {1} installed." -f $Name, $New.Version)
        }
        else {
            $script:HadError = $true
            Write-Result ERROR "$Name install completed but the module was not detected."
        }
    }
    catch {
        $script:HadError = $true
        Write-Result ERROR "Failed upgrading $Name`: $($_.Exception.Message)"
    }
}

function Ensure-ModuleExact {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][version]$RequiredVersion,
        [ValidateSet('AllUsers','CurrentUser')][string]$InstallScope = $Scope
    )

    $Versions = @(Get-Module -ListAvailable -Name $Name -ErrorAction SilentlyContinue | Where-Object { [version]$_.Version -eq $RequiredVersion })
    if ($Versions.Count -gt 0) {
        Write-Result OK ("{0} {1} installed." -f $Name, $RequiredVersion)
        return
    }

    Write-Result INFO ("Installing {0} {1}." -f $Name, $RequiredVersion)

    try {
        Install-Module -Name $Name -RequiredVersion $RequiredVersion -Scope $InstallScope -Force -AllowClobber -ErrorAction Stop
        Write-Result OK ("{0} {1} installed." -f $Name, $RequiredVersion)
    }
    catch {
        $script:HadError = $true
        Write-Result ERROR "Failed installing $Name $RequiredVersion`: $($_.Exception.Message)"
    }
}

function Reset-MicrosoftGraphModules {
    param(
        [version]$GraphVersion = [version]'2.36.1',
        [ValidateSet('AllUsers','CurrentUser')][string]$InstallScope = $Scope
    )

    Write-Section 'Microsoft Graph module baseline'

    $LoadedGraphModules = @(Get-Module Microsoft.Graph* -ErrorAction SilentlyContinue)
    if ($LoadedGraphModules.Count -gt 0) {
        Write-Result WARN 'Microsoft Graph modules are loaded in this session. Removing loaded modules before install.'
        try { $LoadedGraphModules | Remove-Module -Force -ErrorAction SilentlyContinue } catch {}
    }

    if (-not $SkipGraphReset) {
        try {
            $InstalledMeta = @(Get-InstalledModule -Name Microsoft.Graph -ErrorAction SilentlyContinue)
            if ($InstalledMeta.Count -gt 0) {
                Write-Result INFO 'Removing installed Microsoft.Graph meta-module versions before reinstall.'
                Uninstall-Module -Name Microsoft.Graph -AllVersions -Force -ErrorAction SilentlyContinue
            }
        }
        catch {
            Write-Result WARN "Could not remove Microsoft.Graph meta-module cleanly: $($_.Exception.Message)"
        }
    }

    Ensure-ModuleExact -Name 'Microsoft.Graph' -RequiredVersion $GraphVersion -InstallScope $InstallScope
    Ensure-ModuleExact -Name 'Microsoft.Graph.Authentication' -RequiredVersion $GraphVersion -InstallScope $InstallScope
    Ensure-ModuleExact -Name 'Microsoft.Graph.Beta.Reports' -RequiredVersion $GraphVersion -InstallScope $InstallScope
}

function Write-SharePointCompatibilityNote {
    if (Test-IsWindowsOS) { return }

    Write-Result WARN 'Microsoft.Online.SharePoint.PowerShell can be less reliable outside Windows depending on module version and cmdlet usage.'
    Write-Result INFO 'If your MOC menu or child scripts do not use SharePoint Online cmdlets, this module can be optional on Linux/macOS.'
}

function Invoke-MOCPause {
    if ($NoPause) { return }

    Write-Host ''
    Write-Host 'Press Enter to exit...' -ForegroundColor DarkYellow
    try { [void](Read-Host) } catch {}
}

try {
    Write-Section 'MOC PowerShell module maintenance'
    Write-Result INFO ("Platform: {0}" -f (Get-MOCPlatformName))
    Write-Result INFO ("PowerShell: {0} {1}" -f $PSVersionTable.PSEdition, $PSVersionTable.PSVersion)
    Write-Result INFO "Scope: $Scope"
    Write-Result INFO "Mode: $Mode"
    Write-Result INFO 'Script build: Install-MOCPowerShellModules-1.3.1-CROSS-PLATFORM'
    Write-Result INFO "Transcript: $TranscriptPath"
    Write-Result INFO 'Normal MOC child scripts validate modules only. This maintenance script installs approved modules.'

    if ($Scope -eq 'CurrentUser') {
        Write-Result INFO 'CurrentUser scope is recommended for Linux/macOS and works without sudo/admin rights.'
    }

    Ensure-PowerShellGetAvailable
    Ensure-NuGetAndGallery
    Write-SharePointCompatibilityNote

    $DeprecatedMOCModules = @(Get-InstalledDeprecatedMOCModules)
    if ($DeprecatedMOCModules.Count -gt 0) {
        Write-Section 'Deprecated module cleanup'
        foreach ($DeprecatedMOCModule in $DeprecatedMOCModules) {
            Remove-DeprecatedModule -Name $DeprecatedMOCModule
        }
    }

    Write-Section 'Approved MOC module baseline'
    if ($Mode -eq 'UpgradeAll') {
        Write-Result WARN 'UpgradeAll installs the latest approved module versions available from PSGallery. Fully restart PowerShell after completion.'
        Ensure-ModuleLatest -Name 'Az' -InstallScope $Scope
        Ensure-ModuleLatest -Name 'ExchangeOnlineManagement' -InstallScope $Scope
        Ensure-ModuleLatest -Name 'Microsoft.Online.SharePoint.PowerShell' -InstallScope $Scope
        Ensure-ModuleLatest -Name 'ImportExcel' -InstallScope $Scope
        Ensure-ModuleLatest -Name 'Microsoft.Graph' -InstallScope $Scope
        Ensure-ModuleLatest -Name 'Microsoft.Graph.Authentication' -InstallScope $Scope
        Ensure-ModuleLatest -Name 'Microsoft.Graph.Beta.Reports' -InstallScope $Scope
    }
    else {
        Ensure-ModuleMinimum -Name 'Az' -MinimumVersion ([version]'15.4.0') -InstallScope $Scope
        Ensure-ModuleMinimum -Name 'ExchangeOnlineManagement' -MinimumVersion ([version]'3.9.2') -InstallScope $Scope
        Ensure-ModuleMinimum -Name 'Microsoft.Online.SharePoint.PowerShell' -MinimumVersion ([version]'16.0.27111.12000') -InstallScope $Scope
        Ensure-ModuleMinimum -Name 'ImportExcel' -MinimumVersion ([version]'7.8.10') -InstallScope $Scope
        Reset-MicrosoftGraphModules -GraphVersion ([version]'2.36.1') -InstallScope $Scope
    }

    Write-Section 'Final verification'
    $Verify = @(
        @{ Name = 'Az'; Minimum = [version]'15.4.0' }
        @{ Name = 'ExchangeOnlineManagement'; Minimum = [version]'3.9.2' }
        @{ Name = 'Microsoft.Online.SharePoint.PowerShell'; Minimum = [version]'16.0.27111.12000' }
        @{ Name = 'ImportExcel'; Minimum = [version]'7.8.10' }
        @{ Name = 'Microsoft.Graph'; Minimum = [version]'2.36.1' }
        @{ Name = 'Microsoft.Graph.Authentication'; Minimum = [version]'2.36.1' }
        @{ Name = 'Microsoft.Graph.Beta.Reports'; Minimum = [version]'2.36.1' }
    )

    foreach ($Item in $Verify) {
        $Module = Get-InstalledHighestVersion -Name $Item.Name
        if ($Module -and [version]$Module.Version -ge $Item.Minimum) {
            Write-Result OK ("{0} {1}" -f $Item.Name, $Module.Version)
        }
        else {
            $script:HadError = $true
            Write-Result ERROR ("{0} is missing or below required version {1}." -f $Item.Name, $Item.Minimum)
        }
    }

    Write-Host ''
    if ($script:HadError) {
        Write-Result WARN 'Module maintenance completed with one or more warnings/errors. Review the transcript.'
    }
    else {
        Write-Result OK 'Module maintenance completed successfully.'
    }

    Write-Result INFO 'Fully restart PowerShell/Windows Terminal/terminal shell before launching MOC and authenticating again.'
}
catch {
    $script:HadError = $true
    Write-Result ERROR $_.Exception.Message
    exit 1
}
finally {
    try { Stop-Transcript | Out-Null } catch {}
    Invoke-MOCPause
}