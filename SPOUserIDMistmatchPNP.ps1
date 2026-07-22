#Requires -Modules PnP.PowerShell

# =========================
# Parameters
# =========================

$AdminCenterURL = "https://enchantedrock-admin.sharepoint.com"

# User with the ID mismatch
$UserLoginID = "i:0#.f|membership|kparekh@enchantedrock.com"

# SharePoint admin account to temporarily add as site collection admin
$SiteCollectionAdmin = "admin-dr@enchantedrock.com"

# App-only auth
$Thumbprint = "C47B91EB62634CA61FA8146DDA83B8BF605C0962"
$ClientID   = "ea2ca49b-d0df-4774-b611-86cf9dc9629f"
$TenantID   = "0bdf0e1f-a359-4b5c-9b79-9357e35ff8c6"

# Set to $true only after you validate the report
$RemoveUser = $false

# Export path
$ReportPath = "C:\Users\DakotaRuhl\Documents\Reports\OneDrive DisabledUsers\OneDrive_UserLookup.xlsx"

# =========================
# Connect to SharePoint Admin Center
# =========================

Import-Module PnP.PowerShell

Connect-PnPOnline `
    -Url $AdminCenterURL `
    -ClientId $ClientID `
    -Tenant $TenantID `
    -Thumbprint $Thumbprint

# =========================
# Get OneDrive personal sites
# =========================
## test
# $OneDriveSites = Get-PnPTenantSite `
# -IncludeOneDriveSites `
# -Filter "Url -like '-my.sharepoint.com/personal/kparekh'" |
# Select-Object Url, LockState
# $Site = $OneDriveSites | Where-Object { $_.Url -like '-my.sharepoint.com/personal/kparekh' }
##

$OneDriveSites = Get-PnPTenantSite `
    -IncludeOneDriveSites `
    -Filter "Url -like '-my.sharepoint.com/personal/'" |
    Select-Object Url, LockState

Write-Host "Found $($OneDriveSites.Count) OneDrive sites." -ForegroundColor Cyan

# =========================
# Process sites
# =========================

$Results = @()
$count = 0

foreach ($Site in $OneDriveSites) {

    $count++

    Write-Host "Processing $count of $($OneDriveSites.Count): $($Site.Url)" -ForegroundColor Cyan

    if ($Site.LockState -ne "Unlock") {
        Write-Host "Site is locked. Skipping: $($Site.Url)" -ForegroundColor Yellow

        $Results += [PSCustomObject]@{
            SiteUrl       = $Site.Url
            LockState     = $Site.LockState
            UserFound     = $false
            Removed       = $false
            LoginName     = $UserLoginID
            DisplayName   = $null
            Error         = "Skipped because site is locked"
        }

        continue
    }

    $adminAdded = $false

    try {
        # Temporarily add admin as site collection admin
        Add-PnPSiteCollectionAdmin `
            -Owners $SiteCollectionAdmin `
            -Connection (Get-PnPConnection) `
            -ErrorAction Stop

        $adminAdded = $true

        # Connect directly to the OneDrive site
        Connect-PnPOnline `
            -Url $Site.Url `
            -ClientId $ClientID `
            -Tenant $TenantID `
            -Thumbprint $Thumbprint

        # Check if target user exists in the site's user list
        $MatchedUser = Get-PnPUser -ErrorAction Stop |
            Where-Object { $_.LoginName -eq $UserLoginID -and $_.Title -like "*DIS -*" }

        if ($MatchedUser) {

            Write-Host "Found user in site: $($Site.Url) with display name $($MatchedUser.Title)" -ForegroundColor Green

            $removed = $false

            if ($RemoveUser) {
                Write-Host "Removing $UserLoginID from $($Site.Url)" -ForegroundColor Red

                Remove-PnPUser `
                    -Identity $UserLoginID `
                    -Force `
                    -ErrorAction Stop

                $removed = $true
            }

            $Results += [PSCustomObject]@{
                SiteUrl       = $Site.Url
                LockState     = $Site.LockState
                UserFound     = $true
                Removed       = $removed
                LoginName     = $MatchedUser.LoginName
                DisplayName   = $MatchedUser.Title
                Error         = $null
            }
        }
        else {
            $Results += [PSCustomObject]@{
                SiteUrl       = $Site.Url
                LockState     = $Site.LockState
                UserFound     = $false
                Removed       = $false
                LoginName     = $UserLoginID
                DisplayName   = $null
                Error         = $null
            }
        }
    }
    catch {
        Write-Warning "Error processing $($Site.Url): $($_.Exception.Message)"

        $Results += [PSCustomObject]@{
            SiteUrl       = $Site.Url
            LockState     = $Site.LockState
            UserFound     = $false
            Removed       = $false
            LoginName     = $UserLoginID
            DisplayName   = $null
            Error         = $_.Exception.Message
        }
    }
    finally {
        try {
            # Reconnect to the admin center to remove site collection admin
            Connect-PnPOnline `
                -Url $AdminCenterURL `
                -ClientId $ClientID `
                -Tenant $TenantID `
                -Thumbprint $Thumbprint

            if ($adminAdded) {
                Remove-PnPSiteCollectionAdmin `
                    -Owners $SiteCollectionAdmin `
                    -Connection (Get-PnPConnection) `
                    -ErrorAction SilentlyContinue
            }
        }
        catch {
            Write-Warning "Could not remove temporary site collection admin from $($Site.Url): $($_.Exception.Message)"
        }
    }
}

# =========================
# Export results
# =========================

$ReportFolder = Split-Path $ReportPath -Parent

if (!(Test-Path $ReportFolder)) {
    New-Item -Path $ReportFolder -ItemType Directory -Force | Out-Null
}

if (Get-Module -ListAvailable -Name ImportExcel) {
    $Results |
        Sort-Object @{Expression='UserFound';Descending=$true}, SiteUrl |
        Export-Excel `
            -Path $ReportPath `
            -AutoSize `
            -FreezeTopRow `
            -BoldTopRow
}
else {
    $CsvPath = $ReportPath -replace '\.xlsx$', '.csv'

    $Results |
        Sort-Object @{Expression='UserFound';Descending=$true}, SiteUrl |
        Export-Csv `
            -Path $CsvPath `
            -NoTypeInformation

    Write-Warning "ImportExcel module was not found. Exported CSV instead: $CsvPath"
}

Write-Host "Complete." -ForegroundColor Green
Write-Host "Matches found: $(($Results | Where-Object UserFound).Count)" -ForegroundColor Green


<# Single Site Check 
$UserLoginID = "i:0#.f|membership|test.user@enchantedrock.com"

# SharePoint admin account to temporarily add as site collection admin
$SiteCollectionAdmin = "admin-dr@enchantedrock.com"

# App-only auth
$Thumbprint = "C47B91EB62634CA61FA8146DDA83B8BF605C0962"
$ClientID   = "ea2ca49b-d0df-4774-b611-86cf9dc9629f"
$TenantID   = "0bdf0e1f-a359-4b5c-9b79-9357e35ff8c6"

$Site = Connect-PnPOnline -Url "https://enchantedrock-my.sharepoint.com/personal/druhl_enchantedrock_com" `
    -ClientId $ClientID `
    -Tenant $TenantID `
    -Thumbprint $Thumbprint

 Add-PnPSiteCollectionAdmin `
            -Owners $SiteCollectionAdmin `
            -Connection (Get-PnPConnection) `
            -ErrorAction Stop

$adminAdded = $true

# Check if target user exists in the site's user list
$MatchedUser = Get-PnPUser -ErrorAction Stop |
    Where-Object { $_.LoginName -eq $UserLoginID }

$MatchedUser = Get-PnPUser -ErrorAction Stop |
    Where-Object { $_.LoginName -like "*test.user*" }

if ($MatchedUser) {

    Write-Host "Found user in site: $($Site.Url)" -ForegroundColor Green

    $removed = $false

    if ($RemoveUser) {
        Write-Host "Removing $UserLoginID from $($Site.Url)" -ForegroundColor Red

        Remove-PnPUser `
            -Identity $UserLoginID `
            -Force `
            -ErrorAction Stop

        $removed = $true
    }
Connect-PnPOnline `
            -Url "https://enchantedrock-my.sharepoint.com/personal/asenko_enchantedrock_com" `
            -ClientId $ClientID `
            -Tenant $TenantID `
            -Thumbprint $Thumbprint

$MatchedUser = Get-PnPUser -ErrorAction Stop |
            Where-Object { $_.LoginName -eq $UserLoginID -and $_.Title -like "*DIS -*" }

#>