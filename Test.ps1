
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

$Thumbprint = "C47B91EB62634CA61FA8146DDA83B8BF605C0962"
$ClientID   = "ea2ca49b-d0df-4774-b611-86cf9dc9629f"
$Tenant = "enchantedrock.onmicrosoft.com"
$user = "tmcandrew@erock.com"
    
Connect-ExchangeOnline -CertificateThumbprint $Thumbprint -AppId $ClientID -Organization $Tenant
Get-Mailbox tmcandrew@erock.com | fl RetentionPolicy
Get-Mailbox $user | fl RetentionHoldEnabled
Get-RetentionPolicy "Move to Archive after 1 year" | fl RetentionPolicyTagLinks

Get-MailboxFolderStatistics $user `
    -FolderScope RecoverableItems |
    ft Name,FolderAndSubfolderSize

Get-EXOMailboxStatistics $user |
    fl TotalItemSize,TotalDeletedItemSize


Get-Mailbox $user | fl `
ArchiveStatus,
RetentionPolicy,
RetentionHoldEnabled,
LitigationHoldEnabled

Get-Mailbox $user |
    fl RetentionHoldEnabled,StartDateForRetentionHold,EndDateForRetentionHold

    Get-EXOMailboxStatistics $user -Archive |
    fl TotalItemSize,ItemCount

    Get-RetentionPolicy "Move to Archive after 1 year" |
    fl RetentionPolicyTagLinks



Get-RetentionPolicyTag "Move to Archive after 1 year" |
fl Name,Type,RetentionAction,AgeLimitForRetention

Get-Mailbox $user |
fl RetentionHoldEnabled,
   StartDateForRetentionHold,
   EndDateForRetentionHold
Get-Mailbox $user |
fl RetentionComment,
   RetentionUrl,
   RetentionHoldEnabled,
   LitigationHoldEnabled

   Get-Mailbox $user |
fl WhenChanged

Get-Mailbox $user |
fl ElcProcessingDisabled

$logs = Search-UnifiedAuditLog `
    -StartDate "8/11/2026" `
    -EndDate "8/13/2026" `
    -Operations Set-Mailbox `
    -ResultSize 5000 | Where-Object {$_.ObjectId -eq $user}

$logs | Where-Object {$_.Identity -match "018e1284-163e-45f9-9d8b-aa7de18e83fb"}

($logs | Where-Object {$_.ObjectId -match "018e1284-163e-45f9-9d8b-aa7de18e83fb"})[0].AuditData | ConvertFrom-Json

Set-Mailbox $user -RetentionHoldEnabled $false

Get-Mailbox $user | fl RetentionHoldEnabled

start-managedfolderassistant -identity $user

Get-Mailbox $user |
fl LitigationHoldEnabled,
   ComplianceTagHoldApplied,
   DelayHoldApplied,
   DelayReleaseHoldApplied,
   RetentionHoldEnabled

Get-MailboxStatistics $user |
fl *Time*

Get-MailboxStatistics $user |
fl LastProcessedTime
Get-EXOMailboxStatistics $user -Archive |
fl TotalItemSize,ItemCount

Get-MailboxFolderStatistics $user |
Sort FolderAndSubfolderSize -Descending |
Select -First 20 Name,FolderAndSubfolderSize

Export-MailboxDiagnosticLogs `
    -Identity $user `
    -ExtendedProperties |
    Select-String "ELC"


Get-Mailbox $user |
    Format-List RetentionHoldEnabled,ElcProcessingDisabled


Start-ManagedFolderAssistant -Identity $user -FullCrawl


$Log = Export-MailboxDiagnosticLogs `
    -Identity $user `
    -ExtendedProperties

$Xml = [xml]$Log.MailboxLog

$Xml.Properties.MailboxTable.Property |
    Where-Object {
        $_.Name -like "Elc*" -or
        $_.Name -eq "IsELCFullCrawlNeeded"
    } |
    Select-Object Name,Value |
    Format-Table -AutoSize

    Get-Mailbox $user |
    Format-List RetentionPolicy,RetentionHoldEnabled,
        ElcProcessingDisabled,ArchiveStatus

$Log = Export-MailboxDiagnosticLogs `
    -Identity $user `
    -ExtendedProperties

$Xml = [xml]$Log.MailboxLog

$FullCrawl = $Xml.Properties.MailboxTable.Property |
    Where-Object Name -eq "ELCJobAssistantFullCrawlExecutionDetails" |
    Select-Object -ExpandProperty Value |
    ConvertFrom-Json

$FullCrawl | Format-List *

$Names = @(
    "ElcAssistantLock"
    "ELCLastSuccessTimestamp"
    "IsELCFullCrawlNeeded"
    "ElcLastRunTaggedWithArchiveItemCount"
    "ElcLastRunArchivedFromRootItemCount"
    "ElcLastRunArchivedFromDumpsterItemCount"
    "ElcLastRunUpdatedItemCount"
    "ElcLastRunSkippedNoTagItemCount"
    "ElcLastRunSkippedWithTagItemCount"
    "ElcLastRunSkippedNotExcludedItemCount"
)

$Xml.Properties.MailboxTable.Property |
    Where-Object Name -in $Names |
    Select-Object Name,Value |
    Format-Table -AutoSize


Get-EXOMailboxStatistics $user -Archive |
    Format-List TotalItemSize,ItemCount

    Get-RetentionPolicyTag "Move to Archive after 1 year" |
    Format-List Name,
        Type,
        RetentionEnabled,
        RetentionAction,
        AgeLimitForRetention,
        MessageClass

Get-Mailbox $user |
    Format-List DisplayName,
        RecipientTypeDetails,
        AccountDisabled,
        LitigationHoldEnabled,
        RetentionHoldEnabled,
        ElcProcessingDisabled,
        RetentionPolicy,
        ArchiveStatus        

Get-MailboxFolderStatistics $user |
    Where-Object {
        $_.Name -in @("Inbox","Sent Items","Deleted Items")
    } |
    Format-List Name,
        FolderPath,
        ItemsInFolder,
        FolderAndSubfolderSize,
        OldestItemReceivedDate,
        NewestItemReceivedDate

Get-MailboxFolderStatistics $user |
    Where-Object {
        $_.Name -in @("Inbox","Sent Items","Deleted Items")
    } |
    Format-List Name,
        FolderPath,
        ArchivePolicy,
        DeletePolicy,
        CompliancePolicy,
        RetentionFlags

$Policy = Get-RetentionPolicy $user.RetentionPolicy

$Mailbox = Get-Mailbox $user
$Policy  = Get-RetentionPolicy $Mailbox.RetentionPolicy

$Policy.RetentionPolicyTagLinks |
    ForEach-Object {
        Get-RetentionPolicyTag $_
    } |
    Format-Table Name,
        Type,
        RetentionEnabled,
        RetentionAction,
        AgeLimitForRetention,
        MessageClass -AutoSize

$Mailbox = Get-Mailbox $user
$Tag = Get-RetentionPolicyTag "Move to Archive after 1 year"

[pscustomobject]@{
    RecipientTypeDetails  = $Mailbox.RecipientTypeDetails
    AccountDisabled       = $Mailbox.AccountDisabled
    ArchiveStatus         = $Mailbox.ArchiveStatus
    RetentionPolicy       = $Mailbox.RetentionPolicy
    RetentionHoldEnabled  = $Mailbox.RetentionHoldEnabled
    ElcProcessingDisabled = $Mailbox.ElcProcessingDisabled
    TagEnabled            = $Tag.RetentionEnabled
    TagType               = $Tag.Type
    TagAction             = $Tag.RetentionAction
    TagAge                 = $Tag.AgeLimitForRetention
    TagMessageClass        = $Tag.MessageClass
} | Format-List

Get-MailboxFolderStatistics $user -IncludeAnalysis |
    Where-Object {$_.Name -eq "Inbox"} |
    fl *

Get-MailboxFolderStatistics $user |
Where-Object {$_.ItemsInFolder -gt 1000} |
Select Name,
       ItemsInFolder,
       FolderAndSubfolderSize,
       NewestItemLastModifiedDate,
       OldestItemLastModifiedDate |
ft -Auto

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