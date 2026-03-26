$ErrorActionPreference = "Stop"

$EdgePolicyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
$BackupPath = "$env:ProgramData\EdgeExtPolicyBackup.json"
$ExtensionID = "diffhfjoepmlgklilllnlfpafmlgnpmk"   # your extension ID
$InstallPath = "C:\Program Files\EdgeExtensions\$ExtensionID"

# Ensure policy key exists
if (-not (Test-Path $EdgePolicyPath)) {
    New-Item -Path $EdgePolicyPath -Force | Out-Null
}

# Backup existing policy
$existing = Get-ItemProperty -Path $EdgePolicyPath -ErrorAction SilentlyContinue
$backup = @{
    ControlDefaultStateOfAllowExtensionFromOtherStoresSettingEnabled = $existing.ControlDefaultStateOfAllowExtensionFromOtherStoresSettingEnabled
}
$backup | ConvertTo-Json | Set-Content -Path $BackupPath -Encoding UTF8

# Temporarily allow external extensions
New-ItemProperty `
    -Path $EdgePolicyPath `
    -Name "ControlDefaultStateOfAllowExtensionFromOtherStoresSettingEnabled" `
    -PropertyType Dword `
    -Value "1" `
    -Force | Out-Null

# Install extension files
New-Item -ItemType Directory -Path $InstallPath -Force | Out-Null
Copy-Item ".\Extension\*" $InstallPath -Recurse -Force


# Restore original policy
$restore = Get-Content $BackupPath | ConvertFrom-Json

if ($null -eq $restore.ControlDefaultStateOfAllowExtensionFromOtherStoresSettingEnabled) {
    Remove-ItemProperty `
        -Path $EdgePolicyPath `
        -Name "ControlDefaultStateOfAllowExtensionFromOtherStoresSettingEnabled" `
        -ErrorAction SilentlyContinue
} else {
    Set-ItemProperty `
        -Path $EdgePolicyPath `
        -Name "ControlDefaultStateOfAllowExtensionFromOtherStoresSettingEnabled" `
        -Value $restore.ControlDefaultStateOfAllowExtensionFromOtherStoresSettingEnabled
}

# Refresh Edge policies
gpupdate /target:computer /force | Out-Null

param (
    [ValidateSet(0, 1)]
    [int]$Enable = 1
)



$ExtensionId = "makhkhkpghhmfcbjhoomjgbdiokgbkod"
$SourcePath = Join-Path $PSScriptRoot "Enchanted Rock Recruiting Assistant"
$DestPath = "C:\Program Files\EdgeExtensions\$ExtensionId"

if (-not (Test-Path $DestPath)) {
    New-Item -Path $DestPath -ItemType Directory -Force | Out-Null
}

Copy-Item -Path "$SourcePath\*" -Destination $DestPath -Recurse -Force
