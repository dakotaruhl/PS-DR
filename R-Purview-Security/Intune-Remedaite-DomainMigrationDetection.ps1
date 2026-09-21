$ScriptPath = "C:\ProgramData\ERockDomainMigration\DomainMigrationReminder.ps1"

if (Test-Path $ScriptPath) {
    Write-Output "Installed"
    exit 0
}

exit 1