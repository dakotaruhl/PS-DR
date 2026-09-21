# ==============================
# Parameters
# ==============================
$AdminCenterURL = "https://enchantedrock-admin.sharepoint.com"
$SiteCollectionAdmin = "admin-dr@enchantedrock.com"

$Thumbprint = "C47B91EB62634CA61FA8146DDA83B8BF605C0962"
$ClientID   = "ea2ca49b-d0df-4774-b611-86cf9dc9629f"
$TenantName = "enchantedrock.onmicrosoft.com"

# ==============================
# Import module
# ==============================
Import-Module PnP.PowerShell

# ==============================
# Connect to Admin Center
# ==============================
Connect-PnPOnline `
    -Url $AdminCenterURL `
    -ClientId $ClientID `
    -Tenant $TenantName `
    -Thumbprint $Thumbprint

# ==============================
# Get all OneDrive sites
# ==============================
$PSites = Get-PnPTenantSite `
    -IncludeOneDriveSites `
    -Filter "Url -like '-my.sharepoint.com/personal/'"

$count = 0
$disabledUsersFound = @()

foreach ($PSite in $PSites) {
    $count++
    Write-Host "Processing $count of $($PSites.Count): $($PSite.Url)" -ForegroundColor Cyan

    if ($PSite.LockState -ne "Unlock") {
        Write-Host "Site is locked. Skipping..." -ForegroundColor Yellow
        continue
    }

    try {
        # Connect to the personal site
        Connect-PnPOnline `
            -Url $PSite.Url `
            -ClientId $ClientID `
            -Tenant $TenantName `
            -Thumbprint $Thumbprint

        # Add site collection admin
        Add-PnPSiteCollectionAdmin -Owners $SiteCollectionAdmin

        # Get disabled users
        $disabledUsers = Get-PnPUser | Where-Object {
            $_.Title -like "*DIS on* " -or $_.Title -like "*DIS HOLD*"
        }

        foreach ($user in $disabledUsers) {
            $disabledUsersFound += [PSCustomObject]@{
                Name      = $user.Title
                LoginName = $user.LoginName
                Site      = $PSite.Url
            }

            Write-Host "Removing $($user.Title) from $($PSite.Url)" -ForegroundColor Red
            Remove-PnPUser -Identity $user.LoginName -Force
        }
    }
    catch {
        Write-Warning "Error processing $($PSite.Url): $($_.Exception.Message)"
    }
    finally {
        try {
            Remove-PnPSiteCollectionAdmin -Owners $SiteCollectionAdmin
        }
        catch {}
    }
}

# ==============================
# Export results
# ==============================
$disabledUsersFound |
    Sort-Object LoginName, Site -Unique |
    Export-Excel `
        -Path "C:\Users\DakotaRuhl\Documents\Reports\OneDrive DisabledUsers\DisabledUsersFound.xlsx" `
        -AutoSize