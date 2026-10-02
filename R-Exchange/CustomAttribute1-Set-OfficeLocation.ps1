# Connect first if needed
# Connect-ExchangeOnline

# Locations allowed in ExtensionCustomAttribute1
$ValidLocations = @(
    "Vine"
    "Titan"
    "Hyperion"
    "Stockton"
    "Clifton"
    "Remote"
)

# Get user mailboxes that have an Office value
$Mailboxes = Get-Mailbox -ResultSize Unlimited -RecipientTypeDetails UserMailbox |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_.Office) }

$Results = foreach ($Mailbox in $Mailboxes) {

    # Split Office on "/" and clean up whitespace
    $OfficeLocations = @(
        $Mailbox.Office -split "/" |
            ForEach-Object { $_.Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )

    # Keep only our supported locations.
    # -contains is case-insensitive by default.
    $LocationsToSet = @(
        $OfficeLocations |
            Where-Object { $ValidLocations -contains $_ } |
            Select-Object -Unique
    )

    # Capture anything in Office that we don't recognize
    $UnknownLocations = @(
        $OfficeLocations |
            Where-Object { $ValidLocations -notcontains $_ }
    )

    if ($LocationsToSet.Count -eq 0) {
        Write-Warning "Skipping $($Mailbox.PrimarySmtpAddress): No recognized locations in '$($Mailbox.Office)'"

        [PSCustomObject]@{
            DisplayName      = $Mailbox.DisplayName
            PrimarySmtp      = $Mailbox.PrimarySmtpAddress
            Office           = $Mailbox.Office
            Locations        = $null
            UnknownLocations = $UnknownLocations -join ", "
            Status           = "Skipped"
        }

        continue
    }

    # Compare current ExtensionCustomAttribute1 with desired values
    $CurrentLocations = @($Mailbox.ExtensionCustomAttribute1)

    $CurrentSorted = @($CurrentLocations | Sort-Object)
    $DesiredSorted = @($LocationsToSet | Sort-Object)

    $IsAlreadyCorrect = (
        $CurrentSorted.Count -eq $DesiredSorted.Count -and
        (Compare-Object $CurrentSorted $DesiredSorted).Count -eq 0
    )

    if ($IsAlreadyCorrect) {
        Write-Host "Already correct: $($Mailbox.DisplayName)" -ForegroundColor DarkGray
        $Status = "No Change"
    }
    else {
        Write-Host "Updating $($Mailbox.DisplayName): $($LocationsToSet -join ', ')" -ForegroundColor Cyan

        Set-Mailbox `
            -Identity $Mailbox.Identity `
            -ExtensionCustomAttribute1 $LocationsToSet

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

$Results |
    Sort-Object DisplayName |
    Format-Table DisplayName, Office, Locations, UnknownLocations, Status -AutoSize

$Results | Export-Excel `
    -Path "C:\Users\DakotaRuhl\OneDrive - Enchanted Rock\Reports\Users\CustomAttribute1-Set-OfficeLocation.xlsx" `
    -WorksheetName "Results" `
    -AutoSize `
    -AutoFilter `
    -FreezeTopRow `
    -BoldTopRow