# Windows Server Administrative Account Audit
# SOX Evidence Collection
#
# Scope:
#   Members of the local Windows Administrators group only.
#
# Read-only script. No configuration changes are made.

$TimeStamp = Get-Date -Format "yyyyMMdd_HHmmss"
$DesktopPath = :GetFolderPath("Desktop")
$TranscriptPath = Join-Path $DesktopPath "Windows_AdminAccount_Audit_$TimeStamp.txt"

Start-Transcript -Path $TranscriptPath

try {

    Clear-Host

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host " WINDOWS SERVER ADMINISTRATIVE ACCOUNT AUDIT" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""

    $CurrentIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    $OS = Get-CimInstance -ClassName Win32_OperatingSystem

    Write-Host "Audit Scope      : Local Administrators group members only"
    Write-Host "Audit Date/Time  : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')"
    Write-Host "Computer Name    : $env:COMPUTERNAME"
    Write-Host "Executed By      : $CurrentIdentity"
    Write-Host "Operating System : $($OS.Caption)"
    Write-Host "OS Version       : $($OS.Version)"

    # ------------------------------------------------------------
    # Local password policy
    # ------------------------------------------------------------

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Yellow
    Write-Host " LOCAL WINDOWS PASSWORD AND LOCKOUT POLICY" -ForegroundColor Yellow
    Write-Host "============================================================" -ForegroundColor Yellow
    Write-Host ""

    $NetAccountsOutput = net accounts 2>&1 |
        Where-Object {
            $_ -notmatch "^The command completed successfully\.$"
        }

    $NetAccountsOutput | ForEach-Object {
        Write-Host $_
    }

    # ------------------------------------------------------------
    # Administrators group
    # ------------------------------------------------------------

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Yellow
    Write-Host " LOCAL ADMINISTRATORS GROUP - FULL SCOPE" -ForegroundColor Yellow
    Write-Host "============================================================" -ForegroundColor Yellow
    Write-Host ""

    Write-Host "The following is the raw Windows Administrators group membership:"
    Write-Host ""

    $AdminGroupOutput = net localgroup Administrators 2>&1 |
        Where-Object {
            $_ -notmatch "^The command completed successfully\.$"
        }

    $AdminGroupOutput | ForEach-Object {
        Write-Host $_
    }

    # ------------------------------------------------------------
    # Parse Administrators membership
    # ------------------------------------------------------------

    $AdminMembers = @()
    $SeparatorFound = $false

    foreach ($Line in $AdminGroupOutput) {

        $TrimmedLine = $Line.Trim()

        if ($TrimmedLine -match "^-{3,}$") {
            $SeparatorFound = $true
            continue
        }

        if (
            $SeparatorFound -and
            $TrimmedLine -and
            $TrimmedLine -notmatch "^The command completed successfully"
        ) {
            $AdminMembers += $TrimmedLine
        }
    }

    # ------------------------------------------------------------
    # Local Windows admin accounts
    # ------------------------------------------------------------

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Yellow
    Write-Host " LOCAL WINDOWS ADMINISTRATOR ACCOUNTS" -ForegroundColor Yellow
    Write-Host "============================================================" -ForegroundColor Yellow
    Write-Host ""

    $LocalAccounts = Get-CimInstance `
        -ClassName Win32_UserAccount `
        -Filter "LocalAccount=True"

    $LocalAdminResults = @()

    foreach ($Account in $LocalAccounts) {

        $ShortName = $Account.Name
        $ComputerName = "$env:COMPUTERNAME\$ShortName"
        $DotName = ".\$ShortName"

        $IsAdmin = (
            $AdminMembers -contains $ShortName -or
            $AdminMembers -contains $ComputerName -or
            $AdminMembers -contains $DotName
        )

        if ($IsAdmin) {

            $LocalAdminResults += [PSCustomObject]@{
                Identity           = "$env:COMPUTERNAME\$($Account.Name)"
                AccountType        = "Local Windows"
                Enabled            = -not $Account.Disabled
                PasswordRequired   = $Account.PasswordRequired
                PasswordExpires    = $Account.PasswordExpires
                PasswordChangeable = $Account.PasswordChangeable
                LockedOut          = $Account.Lockout
                SID                = $Account.SID
            }
        }
    }

    if ($LocalAdminResults.Count -gt 0) {

        $LocalAdminResults |
            Sort-Object Identity |
            Format-Table `
                Identity,
                Enabled,
                PasswordRequired,
                PasswordExpires,
                PasswordChangeable,
                LockedOut `
                -AutoSize
    }
    else {
        Write-Host "No local Windows user accounts were identified as members of the Administrators group."
    }

    # ------------------------------------------------------------
    # Microsoft Entra / AzureAD administrator identities
    # ------------------------------------------------------------

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Yellow
    Write-Host " MICROSOFT ENTRA / AZUREAD ADMINISTRATOR IDENTITIES" -ForegroundColor Yellow
    Write-Host "============================================================" -ForegroundColor Yellow
    Write-Host ""

    $AzureADAdmins = @(
        $AdminMembers |
            Where-Object { $_ -match "^AzureAD\\" } |
            Sort-Object -Unique
    )

    if ($AzureADAdmins.Count -gt 0) {

        $AzureADResults = foreach ($AzureADAdmin in $AzureADAdmins) {

            [PSCustomObject]@{
                Identity               = $AzureADAdmin
                AdministratorAccess    = $true
                AuthenticationSource   = "Microsoft Entra ID"
                LocalPasswordPolicy    = "Not Applicable"
                PasswordPolicySource   = "Microsoft Entra ID"
            }
        }

        $AzureADResults |
            Format-Table `
                Identity,
                AdministratorAccess,
                AuthenticationSource,
                LocalPasswordPolicy,
                PasswordPolicySource `
                -AutoSize
    }
    else {

        Write-Host "No direct AzureAD identities were returned in the Administrators group."
    }

    # ------------------------------------------------------------
    # Other administrator principals
    # ------------------------------------------------------------

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Yellow
    Write-Host " OTHER ADMINISTRATOR PRINCIPALS" -ForegroundColor Yellow
    Write-Host "============================================================" -ForegroundColor Yellow
    Write-Host ""

    $KnownLocalMembers = @()

    foreach ($Result in $LocalAdminResults) {

        $ShortName = ($Result.Identity -split "\\")[-1]

        $KnownLocalMembers += $ShortName
        $KnownLocalMembers += "$env:COMPUTERNAME\$ShortName"
        $KnownLocalMembers += ".\$ShortName"
    }

    $OtherAdmins = @(
        $AdminMembers |
            Where-Object {
                $_ -notmatch "^AzureAD\\" -and
                $_ -notin $KnownLocalMembers
            } |
            Sort-Object -Unique
    )

    if ($OtherAdmins.Count -gt 0) {

        foreach ($OtherAdmin in $OtherAdmins) {
            Write-Host $OtherAdmin
        }
    }
    else {
        Write-Host "None."
    }

    # ------------------------------------------------------------
    # Current session
    # ------------------------------------------------------------

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Yellow
    Write-Host " CURRENT WINDOWS SESSION" -ForegroundColor Yellow
    Write-Host "============================================================" -ForegroundColor Yellow
    Write-Host ""

    Write-Host "Current Windows Identity: $CurrentIdentity"

    # ------------------------------------------------------------
    # Audit summary
    # ------------------------------------------------------------

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host " AUDIT SCOPE SUMMARY" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""

    Write-Host "Scope: Members of the local Windows Administrators group."
    Write-Host ""
    Write-Host "Local Windows accounts are documented with their Windows"
    Write-Host "password-related account properties."
    Write-Host ""
    Write-Host "AzureAD identities are documented separately because they"
    Write-Host "are not local Windows user accounts."
    Write-Host ""

    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host " END OF AUDIT" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""

    Write-Host "Transcript: $TranscriptPath"
}
finally {

    Stop-Transcript
}