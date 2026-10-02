<#
.SYNOPSIS
    Synchronizes Exchange ExtensionCustomAttribute1 with Office locations.

.DESCRIPTION
    Reads the Office attribute from Exchange Online user mailboxes.

    Supported Office locations:
        Vine
        Titan
        Hyperion
        Stockton
        Clifton
        Remote

    Office values can contain multiple locations separated by "/".
    Example:

        Office = Titan/Hyperion/Vine

    Becomes:

        ExtensionCustomAttribute1 = Titan, Hyperion, Vine

    The runbook only updates mailboxes when the existing
    ExtensionCustomAttribute1 values differ from the desired values.

.NOTES
    Designed for Azure Automation using a system-assigned managed identity.
#>

$ErrorActionPreference = "Stop"

# =========================
# Configuration
# =========================

$Organization = "erock.com"

$ValidLocations = @(
    "Vine"
    "Titan"
    "Hyperion"
    "Stockton"
    "Clifton"
    "Remote"
)

# =========================
# Connect to Exchange Online
# =========================

try {
    Write-Output "Connecting to Exchange Online using managed identity..."

    Connect-ExchangeOnline `
        -ManagedIdentity `
        -Organization $Organization `
        -ShowBanner:$false

    Write-Output "Connected to Exchange Online."
}
catch {
    Write-Error "Failed to connect to Exchange Online: $($_.Exception.Message)"
    throw
}

# =========================
# Get mailboxes
# =========================

try {
    Write-Output "Retrieving user mailboxes..."

    $Mailboxes = @(
        Get-Mailbox `
            -ResultSize Unlimited `
            -RecipientTypeDetails UserMailbox
    )

    Write-Output "Retrieved $($Mailboxes.Count) user mailboxes."
}
catch {
    Write-Error "Failed to retrieve mailboxes: $($_.Exception.Message)"
    throw
}

# =========================
# Counters
# =========================

$UpdatedCount  = 0
$NoChangeCount = 0
$SkippedCount  = 0
$FailedCount   = 0

$Results = foreach ($Mailbox in $Mailboxes) {

    try {

        # Skip mailboxes without an Office value
        if ([string]::IsNullOrWhiteSpace($Mailbox.Office)) {

            Write-Output "SKIPPED: $($Mailbox.PrimarySmtpAddress) - Office is empty."

            $SkippedCount++

            [PSCustomObject]@{
                DisplayName      = $Mailbox.DisplayName
                PrimarySmtp      = $Mailbox.PrimarySmtpAddress
                Office           = $null
                Locations        = $null
                UnknownLocations = $null
                Status           = "Skipped - Empty Office"
            }

            continue
        }

        # Split Office into individual locations
        $OfficeLocations = @(
            $Mailbox.Office -split "/" |
                ForEach-Object { $_.Trim() } |
                Where-Object {
                    -not [string]::IsNullOrWhiteSpace($_)
                }
        )

        # Only retain approved locations
        $LocationsToSet = @(
            $OfficeLocations |
                Where-Object {
                    $ValidLocations -contains $_
                } |
                Select-Object -Unique
        )

        # Identify unexpected Office values
        $UnknownLocations = @(
            $OfficeLocations |
                Where-Object {
                    $ValidLocations -notcontains $_
                }
        )

        # No approved locations found
        if ($LocationsToSet.Count -eq 0) {

            Write-Warning "SKIPPED: $($Mailbox.PrimarySmtpAddress) - No recognized locations in '$($Mailbox.Office)'"

            $SkippedCount++

            [PSCustomObject]@{
                DisplayName      = $Mailbox.DisplayName
                PrimarySmtp      = $Mailbox.PrimarySmtpAddress
                Office           = $Mailbox.Office
                Locations        = $null
                UnknownLocations = $UnknownLocations -join ", "
                Status           = "Skipped - No Valid Locations"
            }

            continue
        }

        # Current attribute values
        $CurrentLocations = @(
            $Mailbox.ExtensionCustomAttribute1 |
                Where-Object {
                    -not :IsNullOrWhiteSpace($_)
                }
        )

        # Normalize order for comparison
        $CurrentSorted = @(
            $CurrentLocations |
                Sort-Object
        )

        $DesiredSorted = @(
            $LocationsToSet |
                Sort-Object
        )

        # Determine whether anything actually changed
        $Differences = @(
            Compare-Object `
                -ReferenceObject $CurrentSorted `
                -DifferenceObject $DesiredSorted
        )

        $IsAlreadyCorrect = (
            $CurrentSorted.Count -eq $DesiredSorted.Count -and
            $Differences.Count -eq 0
        )

        if ($IsAlreadyCorrect) {

            Write-Output "NO CHANGE: $($Mailbox.PrimarySmtpAddress) - $($LocationsToSet -join ', ')"

            $NoChangeCount++
            $Status = "No Change"
        }
        else {

            Write-Output "UPDATING: $($Mailbox.PrimarySmtpAddress)"
            Write-Output "    Office:  $($Mailbox.Office)"
            Write-Output "    Current: $($CurrentLocations -join ', ')"
            Write-Output "    New:     $($LocationsToSet -join ', ')"

            Set-Mailbox `
                -Identity $Mailbox.Identity `
                -ExtensionCustomAttribute1 $LocationsToSet `
                -ErrorAction Stop

            $UpdatedCount++
            $Status = "Updated"
        }

        [PSCustomObject]@{
            DisplayName      = $Mailbox.DisplayName
            PrimarySmtp      = $Mailbox.PrimarySmtpAddress
            Office           = $Mailbox.Office
            Locations        = $LocationsToSet -join ", "
            UnknownLocations = $UnknownLocations -join ", "
            Status           = $Status
        }
    }
    catch {

        $FailedCount++

        Write-Error "FAILED: $($Mailbox.PrimarySmtpAddress) - $($_.Exception.Message)"

        [PSCustomObject]@{
            DisplayName      = $Mailbox.DisplayName
            PrimarySmtp      = $Mailbox.PrimarySmtpAddress
            Office           = $Mailbox.Office
            Locations        = $null
            UnknownLocations = $null
            Status           = "Failed: $($_.Exception.Message)"
        }
    }
}

# =========================
# Summary
# =========================

Write-Output ""
Write-Output "========================================="
Write-Output "Office Location Synchronization Complete"
Write-Output "========================================="
Write-Output "Mailboxes processed : $($Mailboxes.Count)"
Write-Output "Updated             : $UpdatedCount"
Write-Output "No change           : $NoChangeCount"
Write-Output "Skipped             : $SkippedCount"
Write-Output "Failed              : $FailedCount"
Write-Output ""

if ($FailedCount -gt 0) {
    Write-Warning "$FailedCount mailbox(es) failed processing."
}

$Results |
    Sort-Object DisplayName |
    Format-Table `
        DisplayName,
        Office,
        Locations,
        UnknownLocations,
        Status `
        -AutoSize

# =========================
# Disconnect
# =========================

Disconnect-ExchangeOnline -Confirm:$false