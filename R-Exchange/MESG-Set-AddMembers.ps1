param (
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$CsvPath,

    [Parameter(Mandatory)]
    [string]$GroupEmailAddress
)

# Requires ExchangeOnlineManagement
Connect-ExchangeOnline `
    -AppId $env:AZURE_CLIENT_ID `
    -CertificateThumbprint $env:AZURE_CLIENT_CERTIFICATE_THUMBPRINT `
    -Organization $env:AZURE_TENANT_DOMAIN `
    -ShowBanner:$false

$CsvPath = (Resolve-Path $CsvPath).Path
$Users = @(Import-Csv -Path $CsvPath)
$UnverifiedUsers = [System.Collections.Generic.List[object]]::new()

foreach ($Row in $Users) {

    # Add the tracking column if the source CSV does not already contain it.
    if (-not $Row.PSObject.Properties['Added']) {
        $Row | Add-Member `
            -MemberType NoteProperty `
            -Name 'Added' `
            -Value 'FALSE'
    }

    # Skip rows already completed.
    if ($Row.Added -eq 'TRUE') {
        Write-Host "`nAlready marked as added. Skipping: $($Row.userPrincipalName)" -ForegroundColor DarkGray
        continue
    }

    # Default the current row to FALSE until membership is confirmed.
    $Row.Added = 'FALSE'

    $UPN = if ($null -ne $Row.userPrincipalName) {
        $Row.userPrincipalName.Trim()
    }
    else {
        ''
    }

    Write-Host "`nProcessing: $UPN" -ForegroundColor Cyan
    Write-Host "Group:      $GroupEmailAddress" -ForegroundColor DarkGray

    # Skip malformed rows that do not contain a userPrincipalName.
    if ([string]::IsNullOrWhiteSpace($UPN)) {
        Write-Warning "Row does not contain a userPrincipalName."
        continue
    }

    # Verify the recipient exists in Exchange Online.
    try {
        $Recipient = Get-Recipient `
            -Identity $UPN `
            -ErrorAction Stop
    }
    catch {
        Write-Warning "Unable to verify UPN: $UPN"

        $UnverifiedUsers.Add(
            [PSCustomObject]@{
                UPN = $UPN
            }
        )

        continue
    }

    # Add the recipient to the mail-enabled security group.
    try {
        Add-DistributionGroupMember `
            -Identity $GroupEmailAddress `
            -Member $Recipient.PrimarySmtpAddress `
            -BypassSecurityGroupManagerCheck `
            -ErrorAction Stop

        $Row.Added = 'TRUE'

        Write-Host "Successfully added $UPN to $GroupEmailAddress" -ForegroundColor Green

        # Save progress immediately so the script is safely rerunnable.
        $Users | Export-Csv `
            -Path $CsvPath `
            -NoTypeInformation
    }
    catch {
        # If the recipient is already a member, consider the row complete.
        try {
            $ExistingMember = Get-DistributionGroupMember `
                -Identity $GroupEmailAddress `
                -ResultSize Unlimited `
                -ErrorAction Stop |
                Where-Object {
                    $_.PrimarySmtpAddress -eq $Recipient.PrimarySmtpAddress
                }

            if ($ExistingMember) {
                $Row.Added = 'TRUE'

                Write-Host "$UPN is already a member of $GroupEmailAddress" -ForegroundColor Yellow

                $Users | Export-Csv `
                    -Path $CsvPath `
                    -NoTypeInformation
            }
            else {
                Write-Warning "Failed to add $UPN to $GroupEmailAddress"
                Write-Warning $_.Exception.Message
            }
        }
        catch {
            Write-Warning "Failed to add or verify membership for $UPN in $GroupEmailAddress"
            Write-Warning $_.Exception.Message
        }
    }
}

# Final save.
$Users | Export-Csv `
    -Path $CsvPath `
    -NoTypeInformation

Write-Host "`n============================================" -ForegroundColor Cyan
Write-Host "Processing complete" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan

if ($UnverifiedUsers.Count -gt 0) {
    Write-Host "`nUPNs that could not be verified:" -ForegroundColor Yellow

    $UnverifiedUsers |
        Format-Table UPN -AutoSize
}
else {
    Write-Host "`nAll UPNs were successfully verified." -ForegroundColor Green
}

<# Example:
 .\R-Exchange\MESG-Set-AddMembers.ps1 `
     -CsvPath "C:\Users\DakotaRuhl\Downloads\OnePlanUsers (1).csv" `
     -GroupEmailAddress "oneplanusers@erock.com"
#>