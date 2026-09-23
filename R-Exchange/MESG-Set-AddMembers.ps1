param (
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$CsvPath
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

    $UPN       = $Row.UPN.Trim()
    $GroupName = $Row.'Group Name'.Trim()

    Write-Host "`nProcessing: $UPN" -ForegroundColor Cyan
    Write-Host "Group:      $GroupName" -ForegroundColor DarkGray

    # Skip rows already completed
    if ($Row.Added -eq 'TRUE') {
        Write-Host "Already marked as added. Skipping." -ForegroundColor DarkGray
        continue
    }

    # Default to FALSE
    $Row.Added = 'FALSE'

    # Verify the recipient exists in Exchange Online
    try {
        $Recipient = Get-Recipient -Identity $UPN -ErrorAction Stop
    }
    catch {
        Write-Warning "Unable to verify UPN: $UPN"

        $UnverifiedUsers.Add(
            [PSCustomObject]@{
                UPN        = $UPN
                GroupName  = $GroupName
            }
        )

        continue
    }

    # Add user to the mail-enabled security group
    try {
        Add-DistributionGroupMember `
            -Identity $GroupName `
            -Member $Recipient.PrimarySmtpAddress `
            -BypassSecurityGroupManagerCheck `
            -ErrorAction Stop

        $Row.Added = 'TRUE'

        Write-Host "Successfully added $UPN to $GroupName" -ForegroundColor Green

        # Save progress immediately
        $Users | Export-Csv -Path $CsvPath -NoTypeInformation
    }
    catch {

        # If they're already a member, determine whether we should
        # consider this row successfully satisfied.
        try {
            $ExistingMember = Get-DistributionGroupMember `
                -Identity $GroupName `
                -ResultSize Unlimited `
                -ErrorAction Stop |
                Where-Object {
                    $_.PrimarySmtpAddress -eq $Recipient.PrimarySmtpAddress
                }

            if ($ExistingMember) {
                $Row.Added = 'TRUE'

                Write-Host "$UPN is already a member of $GroupName" -ForegroundColor Yellow

                $Users | Export-Csv -Path $CsvPath -NoTypeInformation
            }
            else {
                Write-Warning "Failed to add $UPN to $GroupName"
                Write-Warning $_.Exception.Message
            }
        }
        catch {
            Write-Warning "Failed to add or verify membership for $UPN in $GroupName"
            Write-Warning $_.Exception.Message
        }
    }
}

# Final save
$Users | Export-Csv -Path $CsvPath -NoTypeInformation

Write-Host "`n============================================" -ForegroundColor Cyan
Write-Host "Processing complete" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan

if ($UnverifiedUsers.Count -gt 0) {

    Write-Host "`nUPNs that could not be verified:" -ForegroundColor Yellow

    $UnverifiedUsers |
        Format-Table UPN, GroupName -AutoSize
}
else {
    Write-Host "`nAll UPNs were successfully verified." -ForegroundColor Green
}

## .\MESG-Set-AddMembers.ps1 -CsvPath "C:\Users\DakotaRuhl\Documents\PS-DR\Input Data\FortiClient VPN Users.csv"