
Import-Module Microsoft.Graph.Authentication
Import-Module Microsoft.Graph.Groups


$SiteName = "https://enchantedrock.sharepoint.com/sites/erintranet" # Name of the SharePoint Online site to process

# Connect to the Microsoft Graph
Connect-MgGraph -Scopes "Sites.Read.All", "InformationProtectionPolicy.Read", "RecordsManagement.Read.All" -NoWelcome

Write-Host "Setting up for the SharePoint Online site files report..."

# Find the site
Write-Host "Looking for matching sites..."
[array]$Sites = Get-MgSite -Search ($SiteName)
if (!($Sites)) {
    Write-Host "No matching sites found - exiting"
    break
}
if ($Sites.Count -eq 1) {
    $Global:Site = $Sites[0]
    $SiteName = $Site.DisplayName
    Write-Host "Found site to process:" $SiteName
}
elseif ($Sites.Count -gt 1) {
    Clear-Host
    [int]$i = 1
    Write-Host "More than one matching site was found. We need you to select a site to report."
    foreach ($SiteOption in $Sites) {
        Write-Host ("{0}: {1} ({2})" -f $i, $SiteOption.DisplayName, $SiteOption.Name)
        $i++
    }
    [Int]$Answer = Read-Host "Enter the number of the site to use"
    if (($Answer -gt 0) -and ($Answer -le $i)) {
        [int]$Si = ($Answer-1)
        $SiteName = $Sites[$Si].DisplayName
        Write-Host ("OK. Selected site is {0}" -f $Sites[$Si].DisplayName)
        $Global:Site = $Sites[$Si]
    }
}

if (!($Site)) {
    Write-Host ("Can't find the {0} site - script exiting" -f $Uri)
    break
}

# Find ALL document libraries (drives) in the site
[array]$Drives = Get-MgSiteDrive -SiteId $Site.Id
if (!($Drives)) {
    Write-Host "No document libraries found in the site" -ForegroundColor Red
    Break
}


# Request which drive to use instead of all drives
Write-Host "Select a document library to process:"
[int]$i = 1
foreach ($DriveOption in $Drives) {
    Write-Host ("{0}: {1}" -f $i, $DriveOption.Name)
    $i++
}
[Int]$Answer = Read-Host "Enter the number of the document library to use"
if (($Answer -gt 0) -and ($Answer -le $i)) {
    [int]$Si = ($Answer-1)
    $DriveName = $Drives[$Si].Name
    Write-Host ("OK. Selected document library is {0}" -f $Drives[$Si].Name)
    $DriveId = $Drives[$Si].Id
    Write-Host "Fetching file information from drive:" $DriveName
    #Get-DriveItems -Drive $DriveId -FolderId "root"
}
else {
    Write-Host "Invalid selection - exiting"
    Break
}

Install-AllUsersModule microsoft.online.sharepoint.powershell
import-module microsoft.online.sharepoint.powershell 
update-module microsoft.online.sharepoint.powershell 
Get-SPOTenant | Select RestrictedAccessControl


$TenantId   = "0bdf0e1f-a359-4b5c-9b79-9357e35ff8c6"
$ClientId   = "97d01716-c2a3-4311-9b73-09ac8579cbf1"
$Thumbprint = "94EF4B57723E2E90CD56F2F407EF6AFBEF275392"
$AdminUrl   = "https://enchantedrock-admin.sharepoint.com"

$cert = Get-Item "Cert:\LocalMachine\My\$Thumbprint"

try {
    Connect-SPOService `
        -Url $AdminUrl `
        -ClientId $ClientId `
        -TenantId $TenantId `
        -Certificate $cert `
        -Verbose `
        -ErrorAction Stop
}
catch {
    Write-Host "TOP LEVEL ERROR:" -ForegroundColor Red
    $_ | Format-List * -Force

    Write-Host "EXCEPTION:" -ForegroundColor Red
    $_.Exception | Format-List * -Force

    Write-Host "INNER EXCEPTION:" -ForegroundColor Red
    $_.Exception.InnerException | Format-List * -Force

    Write-Host "INNER INNER EXCEPTION:" -ForegroundColor Red
    $_.Exception.InnerException.InnerException | Format-List * -Force
}

[Environment]::GetFolderPath("MyDocuments")


$User = Get-MgUser -UserId "svc_itnotifications@enchantedrock.com"
$ExpirationDate = $User.LastPasswordChangeDateTime.AddDays($ValidityPeriod)
$ExpirationDate

$User | Select-Object -ExpandProperty PasswordPolicies DisablePasswordExpiration

[PSCustomObject]@{
    DisplayName          = $User.DisplayName
    LastPasswordChanged  = $User.LastPasswordChangeDateTime
    MustChangeNextLogon  = $User.PasswordProfile.ForceChangePasswordNextSignIn
    Expiration          = $User.PasswordPolicies
}

Update-MgUser -UserId "svc_itnotifications@enchantedrock.com" -PasswordPolicies DisablePasswordExpiration
$User | FL *Password*

$user = Get-MgUser -UserId "svc_itnotifications@enchantedrock.com" -Property UserPrincipalName, PasswordPolicies
$user.PasswordPolicies
$user.PasswordPolicies



Connect-MgGraph -Scopes "User.ReadWrite.All" 

Update-MgUser -UserId "7af10937-97d8-41ec-8de8-bd7af754d85e" -PasswordPolicies DisablePasswordExpiration  
Get-mguser -UserId "7af10937-97d8-41ec-8de8-bd7af754d85e" | Select-Object -ExpandProperty PasswordPolicies

Update-MgUser -UserId "7af10937-97d8-41ec-8de8-bd7af754d85e" -PasswordProfile @{ForceChangePasswordNextSignIn = $false}
get-mguser -UserId "7af10937-97d8-41ec-8de8-bd7af754d85e" | Select-Object -ExpandProperty PasswordProfile

@(
    Get-Content C:\Users\DakotaRuhl\Downloads\BLOBS\BLOBS\blob.crt -Raw
    Get-Content C:\Users\DakotaRuhl\Downloads\BLOBS\BLOBS\blob.key -Raw
) | Set-Content C:\Users\DakotaRuhl\Downloads\BLOBS\BLOBS\blob.pem -NoNewline

(RecipientTypeDetails -eq 'UserMailbox') -and
(AccountDisabled -eq $false) -and
(Title -like '*Contractor*') -and
(WindowsLiveID -like '*-sc*')

Get-Recipient -RecipientPreviewFilter "
(RecipientTypeDetails -eq 'UserMailbox') -and
(AccountDisabled -eq `$false) -and
(Title -like '*Contractor') -and
(WindowsLiveID -like '*-sc*')
" | FL *displayname*

New-DynamicDistributionGroup `
    -Name "Contractors-DL" `
    -Alias "Contractors-DL" `
    -PrimarySmtpAddress "Contractors-DL@erock.com" `
    -RecipientFilter "
        (RecipientTypeDetails -eq 'UserMailbox') -and
        (AccountDisabled -eq `$false) -and
        (Title -like '*Contractor') -and
        (WindowsLiveID -like '*-sc@erock.com')
    "
get-inboxrule -mailbox 46d4f931-4b88-4716-aa9b-ce4307ed3cde -IncludeHidden | select name, identity, description, enabled, priority, ruleidentity, ruleid, ruleversion, ruleversionid, ruleversionnumber