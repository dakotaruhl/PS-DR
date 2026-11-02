# Existing static Hyperion DL
$HyperionFilter = "(ExtensionCustomAttribute1 -eq 'Hyperion') -and (RecipientTypeDetails -eq 'UserMailbox') -and (HiddenFromAddressListsEnabled -eq `$false)"
$CurrentMembers = Get-DistributionGroupMember `
    -Identity "hyperion@erock.com" `
    -ResultSize Unlimited

# Recipients currently matching the proposed dynamic filter
$DynamicMembers = Get-Recipient `
    -Filter $HyperionFilter `
    -ResultSize Unlimited

$DynamicIds = @(
    $DynamicMembers |
        Where-Object { $_.ExternalDirectoryObjectId } |
        ForEach-Object { $_.ExternalDirectoryObjectId }
)

# Existing DL members that do NOT currently match the dynamic filter
$MissingMembers = @(
    $CurrentMembers |
        Where-Object {
            $_.ExternalDirectoryObjectId -and
            $_.ExternalDirectoryObjectId -notin $DynamicIds
        }
)

Write-Host "Current static DL members : $($CurrentMembers.Count)"
Write-Host "Current dynamic matches   : $($DynamicMembers.Count)"
Write-Host "Members requiring updates : $($MissingMembers.Count)"
Write-Host ""

foreach ($Member in $MissingMembers) {

    try {
        $Recipient = Get-Recipient `
            -Identity $Member.ExternalDirectoryObjectId `
            -ErrorAction Stop

        # Only process mailboxes
        if ($Recipient.RecipientTypeDetails -notin @(
            "UserMailbox",
            "SharedMailbox"
        )) {
            Write-Warning "Skipping $($Recipient.PrimarySmtpAddress): RecipientTypeDetails is $($Recipient.RecipientTypeDetails)"
            continue
        }

        $CurrentOffice = [string]$Recipient.Office
        $CurrentExtensionValues = @($Recipient.ExtensionCustomAttribute1)

        # Determine new Office value
        if ([string]::IsNullOrWhiteSpace($CurrentOffice)) {
            $NewOffice = "Hyperion"
        }
        elseif ($CurrentOffice -notmatch "(?i)(^|/)Hyperion($|/)") {
            $NewOffice = "$CurrentOffice/Hyperion"
        }
        else {
            $NewOffice = $CurrentOffice
        }

        $OfficeNeedsUpdate = $NewOffice -ne $CurrentOffice

        $ExtensionNeedsUpdate = (
            "Hyperion" -notin $CurrentExtensionValues
        )

        Write-Host "Processing: $($Recipient.DisplayName)"
        Write-Host "  SMTP:      $($Recipient.PrimarySmtpAddress)"
        Write-Host "  Office:    '$CurrentOffice' -> '$NewOffice'"
        Write-Host "  Add Ext:   $ExtensionNeedsUpdate"

        if ($OfficeNeedsUpdate) {
            Set-Mailbox `
                -Identity $Recipient.ExternalDirectoryObjectId `
                -Office $NewOffice
        }

        if ($ExtensionNeedsUpdate) {
            Set-Mailbox `
                -Identity $Recipient.ExternalDirectoryObjectId `
                -ExtensionCustomAttribute1 @{ Add = "Hyperion" }
        }

        if (-not $OfficeNeedsUpdate -and -not $ExtensionNeedsUpdate) {
            Write-Host "  No changes required."
        }

        Write-Host ""
    }
    catch {
        Write-Warning "Failed to process $($Member.PrimarySmtpAddress): $($_.Exception.Message)"
    }
}