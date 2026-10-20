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
        Field

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

$Organization = "EnchantedRock.onmicrosoft.com"

$ValidLocations = @(
    "Vine"
    "Titan"
    "Hyperion"
    "Atlas"
    "Stockton"
    "Clifton"
    "Clinton"
    "Remote"
    "Field"
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
                    -not [string]::IsNullOrWhiteSpace($_)
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

            $MaxAttempts = 3
            $Attempt = 0
            $UpdateSucceeded = $false

            while (-not $UpdateSucceeded -and $Attempt -lt $MaxAttempts) {

                $Attempt++

                try {

                    Set-Mailbox `
                        -Identity $Mailbox.Identity `
                        -ExtensionCustomAttribute1 $LocationsToSet `
                        -ErrorAction Stop

                    $UpdateSucceeded = $true
                }
                catch {

                    $SetMailboxError = $_

                    if ($Attempt -ge $MaxAttempts) {
                        throw
                    }

                    $DelaySeconds = 5 * $Attempt

                    Write-Warning (
                        "Set-Mailbox attempt {0}/{1} failed for {2}: {3}. Retrying after {4} seconds." -f `
                        $Attempt,
                        $MaxAttempts,
                        $Mailbox.PrimarySmtpAddress,
                        $SetMailboxError.Exception.Message,
                        $DelaySeconds
                    )

                    Start-Sleep -Seconds $DelaySeconds
                }
            }

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

        $ErrorMessage = $_.Exception.Message

        Write-Warning "FAILED: $($Mailbox.PrimarySmtpAddress) - $ErrorMessage"

        [PSCustomObject]@{
            DisplayName      = $Mailbox.DisplayName
            PrimarySmtp      = $Mailbox.PrimarySmtpAddress
            Office           = $Mailbox.Office
            Locations        = $null
            UnknownLocations = $null
            Status           = "Failed: $ErrorMessage"
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
    Select-Object `
        DisplayName,
        PrimarySmtp,
        Office,
        Locations,
        UnknownLocations,
        Status

# =========================
# Disconnect
# =========================

Disconnect-ExchangeOnline -Confirm:$false



$ManagedIdentityObjectId = "6e0f75bb-2aef-46ba-b80a-c9045d7ecd00"

$RoleDefinition = Get-MgRoleManagementDirectoryRoleDefinition `
    -Filter "displayName eq 'Exchange Recipient Administrator'"

if ($null -eq $RoleDefinition) {
    throw "Exchange Recipient Administrator role definition was not found."
}

$RoleDefinition |
    Select-Object Id, DisplayName |
    Format-List

#Assign 
$RoleAssignment = New-MgRoleManagementDirectoryRoleAssignment `
    -PrincipalId $ManagedIdentityObjectId `
    -RoleDefinitionId $RoleDefinition.Id `
    -DirectoryScopeId "/"

$RoleAssignment |
    Select-Object `
        Id,
        PrincipalId,
        RoleDefinitionId,
        DirectoryScopeId |
    Format-List

$RoleAssignmentId = $RoleAssignment.Id



$Assignments = Get-MgRoleManagementDirectoryRoleAssignment `
    -Filter "principalId eq '$ManagedIdentityObjectId'" `
    -All

 $Assignments | ForEach-Object {
    $Assignment = $_
    $Definition = Get-MgRoleManagementDirectoryRoleDefinition `
        -UnifiedRoleDefinitionId $Assignment.RoleDefinitionId

    [PSCustomObject]@{
        RoleName     = $Definition.DisplayName
        AssignmentId = $Assignment.Id
        Scope        = $Assignment.DirectoryScopeId
    }
} | Format-Table -AutoSize