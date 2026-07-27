## Configuration ##
$invitations = Import-Excel '.\Input Data\invitations.xlsx' -WorksheetName "invitations" |
    Where-Object {
        -not [string]::IsNullOrWhiteSpace($_.Email) -and
        -not [string]::IsNullOrWhiteSpace($_.Name)
    }
$sponsorEmail = $invitations.Sponsor | Select-Object -First 1 

## Azure AD App Registration Details ##
$Thumbprint = "C47B91EB62634CA61FA8146DDA83B8BF605C0962"
$ClientID   = "ea2ca49b-d0df-4774-b611-86cf9dc9629f"
$TenantID   = "0bdf0e1f-a359-4b5c-9b79-9357e35ff8c6"

# Connect to Microsoft Graph using the app registration credentials
Connect-MgGraph `
    -ClientId $ClientID `
    -TenantId $TenantID `
    -CertificateThumbprint $Thumbprint

$messageInfo = New-Object Microsoft.Graph.PowerShell.Models.MicrosoftGraphInvitedUserMessageInfo

$messageInfo.CustomizedMessageBody = @"
Hello,

This is the IT dept at ERock. Your guest account has been created for access to content in our organization, pending your activation.

Please click the "Accept Invitation" link below and follow the prompts to activate the guest account and set up multi-factor authentication. A corresponding file share link will be sent to you following this email.

If you have any questions, please feel free to send me an email at druhl@enchantedrock.com.
"@

$sponsor = Get-MgUser -UserId $sponsorEmail -ErrorAction Stop

$results = @()
$results = foreach ($row in $invitations) {
    try {
        if ([string]::IsNullOrWhiteSpace($row.Email)) {
            throw "Missing Email in CSV row."
        }

        if ([string]::IsNullOrWhiteSpace($row.Name)) {
            throw "Missing Name in CSV row for $($row.Email)."
        }

        $inviteEmail = $row.Email.Trim()
        $displayName = $row.Name.Trim()

        # Escape single quotes for OData filter safety
        $escapedInviteEmail = $inviteEmail.Replace("'", "''")

        # Check whether guest already exists
        # mail is usually populated for B2B guests, but not guaranteed in every edge case.
        $existingGuest = Get-MgUser `
            -Filter "userType eq 'Guest' and mail eq '$escapedInviteEmail'" `
            -Property Id,DisplayName,UserPrincipalName,Mail,UserType `
            -ErrorAction Stop

        if ($existingGuest) {
            Write-Warning "SKIPPED: $inviteEmail already exists as guest: $($existingGuest.DisplayName) / $($existingGuest.UserPrincipalName)"

            # Verify existing sponsors
            try {
                $assignedSponsors = Get-MgUserSponsor -UserId $existingGuest.Id -ErrorAction Stop

                $sponsorAlreadyAssigned = $assignedSponsors | Where-Object {
                    $_.Id -eq $sponsor.Id
                }

                if ($sponsorAlreadyAssigned) {
                    Write-Host "Sponsor already assigned for existing guest: $inviteEmail" -ForegroundColor Yellow
                }
                else {
                    Write-Warning "Guest exists, but sponsor is not assigned. Add sponsor manually or with New-MgUserSponsorByRef if needed."
                }
            }
            catch {
                Write-Warning "Could not verify sponsors for existing guest $inviteEmail - $($_.Exception.Message)"
            }

            [PSCustomObject]@{
                Email             = $inviteEmail
                DisplayName       = $displayName
                Status            = "Skipped"
                Reason            = "Guest already exists"
                GuestId           = $existingGuest.Id
                GuestUPN          = $existingGuest.UserPrincipalName
                Sponsor           = $sponsor.UserPrincipalName
            }

            continue
        }

        $params = @{
            InvitedUserEmailAddress = $inviteEmail
            InvitedUserDisplayName  = $displayName
            InviteRedirectUrl       = "https://myapplications.microsoft.com/?tenantid=$TenantID"
            InvitedUserMessageInfo  = $messageInfo
            SendInvitationMessage   = $true
            InvitedUserSponsors     = @($sponsor)
        }

        $invite = New-MgInvitation @params -ErrorAction Stop

        Write-Host "SUCCESS: $inviteEmail" -ForegroundColor Green
        Write-Host "Created Guest Id: $($invite.InvitedUser.Id)" -ForegroundColor Cyan

        $assignedSponsors = Get-MgUserSponsor -UserId $invite.InvitedUser.Id -ErrorAction Stop


        [PSCustomObject]@{
            Email             = $inviteEmail
            DisplayName       = $displayName
            Status            = "Invited"
            Reason            = "Invitation sent"
            GuestId           = $invite.InvitedUser.Id
            GuestUPN          = $invite.InvitedUser.UserPrincipalName
            Sponsor           = $sponsor.UserPrincipalName
        }
    }
    catch {
        Write-Warning "FAILED: $($row.Email) - $($_.Exception.Message)"

        [PSCustomObject]@{
            Email             = $row.Email
            DisplayName       = $row.Name
            Status            = "Failed"
            Reason            = $_.Exception.Message
            GuestId           = $null
            GuestUPN          = $null
            Sponsor           = $sponsor.UserPrincipalName
        }
    }
}

$results | Export-csv ".\Input Data\GuestInviteResults.csv" -NoTypeInformation 
$results | Format-Table -AutoSize  