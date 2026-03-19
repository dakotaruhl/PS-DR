$ErrorActionPreference = "Stop"

try {
    # Registry path for Edge policy
    $regPath = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"

    # Create the registry path if it doesn't exist
    if (-not (Test-Path $regPath)) {
        New-Item -Path $regPath -Force | Out-Null
    }

    # Set the policy value
    Set-ItemProperty -Path $regPath -Name "ControlDefaultStateOfAllowExtensionFromOtherStoresSettingEnabled" -Value 1 -Type DWord

    Write-Host "'Allow extensions from other stores' has been set to 1 (1=Enabled, 0=Disabled)." -ForegroundColor Green
    Write-Host "Restart Microsoft Edge for the change to take effect."
}
catch {
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
} 