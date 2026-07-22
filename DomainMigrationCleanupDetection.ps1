# ===========================================================
# ERock Domain Migration Reminder - Detection
#
# Purpose:
# Detects whether any artifacts from the ERock Domain
# Migration Reminder deployment still exist.
#
# Exit 1 = Remediation required
# Exit 0 = Compliant
# ===========================================================

$TaskNames = @(
    "ERock Domain Migration Reminder",
    "ERock Domain Migration Reminder - Logon",
    "ERock Domain Migration Reminder - Unlock"
)

$Folder = "$env:ProgramData\ERockDomainMigration"
$RegPath = "HKCU:\Software\ERock\DomainMigration"

$ArtifactsFound = @()

# Check scheduled tasks
foreach ($TaskName in $TaskNames)
{
    $Task = Get-ScheduledTask `
        -TaskName $TaskName `
        -ErrorAction SilentlyContinue

    if ($Task)
    {
        $ArtifactsFound += "Scheduled Task: $TaskName"
    }
}

# Check folder
if (Test-Path $Folder)
{
    $ArtifactsFound += "Folder: $Folder"
}

# Check current-user registry key
if (Test-Path $RegPath)
{
    $ArtifactsFound += "Registry Key: $RegPath"
}

# Determine compliance
if ($ArtifactsFound.Count -gt 0)
{
    Write-Output @"
ERock Domain Migration Reminder artifacts detected.

$($ArtifactsFound -join [System.Environment]::NewLine)
"@

    exit 1
}

Write-Output "ERock Domain Migration Reminder cleanup verified. No artifacts found."
exit 0