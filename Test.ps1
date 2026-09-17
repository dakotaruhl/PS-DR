
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

    
Get-TransportConfig | Format-List SmtpClientAuthenticationDisabled






    get-inboxrule -mailbox 46d4f931-4b88-4716-aa9b-ce4307ed3cde -IncludeHidden | select name, identity, description, enabled, priority, ruleidentity, ruleid, ruleversion, ruleversionid, ruleversionnumber


New-ApplicationAccessPolicy -AccessRight RestrictAccess -AppId 4a1b9aed-6040-4f15-88ba-2c34d2635957 -PolicyScopeGroupId it_mail_app_access@erock.com -Description "Restrict app to specific mailboxes used in IT environment"
Test-ApplicationAccessPolicy -Identity svc_ITNotifications@enchantedrock.com -AppId 4a1b9aed-6040-4f15-88ba-2c34d2635957
Add-DistributionGroupMember -Identity "offboarding@erock.com" -Member "soc@erock.com"

Get-AzRoleDefinition | Where-Object {
    $_.Name -like "*Communication*"
} | Select-Object Name

Get-AzRoleDefinition "Communication and Email Service Owner" |
Select-Object -ExpandProperty Permissions |
Format-List

az role assignment list --assignee 38d1b123-3eaf-47ae-a416-796297c2742d --scope "/subscriptions/03866bcc-752b-4fd1-b5bb-cdd66aed21fb/resourceGroups/fieldpoint-communications-prod/providers/Microsoft.Communication/communicationServices/fieldpoint-communications-sms-prod"

func azure functionapp publish graph-mail-sendAs
az functionapp function keys list -g M365-Infrastructure -n graph-mail-sendAs --function-name SendMail

$code = "<paste-the-default-key>"
Invoke-RestMethod -Method Post -Uri "https://graph-mail-sendAs.azurewebsites.net/api/SendMail?code=$code" `
    -ContentType 'application/json' -Body (@{
        To      = "druhl@erock.com"
        Subject = "Prod test"
        Body    = "<p>Sent from the deployed Function App.</p>"
    } | ConvertTo-Json)

cd C:\Users\DakotaRuhl\Documents\PS-DR\GraphMailFunction

$rg      = "M365-Infrastructure"
$appName = "graph-mail-sendAs"
$zipPath = "C:\Users\DakotaRuhl\Documents\PS-DR\GraphMailFunction.zip"

# Zip the CONTENTS of the folder, not the folder itself
Compress-Archive -Path ".\*" -DestinationPath $zipPath -Force

Publish-AzWebApp -ResourceGroupName $rg -Name $appName -ArchivePath $zipPath -Force



Invoke-RestMethod -Method Post -Uri "https://graph-mail-sendas-guh9b5c3h8e5azas.centralus-01.azurewebsites.net/api/sendmail?code=$code" -ContentType 'application/json' -Body (@{
    To      = "druhl@erock.com"
    Subject = "Prod test"
    Body    = "<p>Sent from the Function App.</p>"
} | ConvertTo-Json)

$secureKey = ConvertTo-SecureString -String $code -AsPlainText -Force
Set-AzKeyVaultSecret -VaultName "kv-summittrail" -Name "GraphMailSendAs-FunctionKey" -SecretValue $secureKey


$Thumbprint = "C47B91EB62634CA61FA8146DDA83B8BF605C0962"
$ClientId   = "ea2ca49b-d0df-4774-b611-86cf9dc9629f"
$TenantId   = "0bdf0e1f-a359-4b5c-9b79-9357e35ff8c6"


function Get-TrimmedValue {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Value) {
        return ""
    }

    return $Value.ToString().Trim()
}

function ConvertTo-EmployeeHireDate {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace($Value.ToString())) {
        return [datetime]::MinValue
    }

    if ($Value -is [datetime]) {
        return [datetime]$Value
    }

    # Handle an Excel serial date if ImportExcel returns a numeric value.
    $excelSerial = 0.0
    if ([double]::
            $Value.ToString(),
            [System.Globalization.NumberStyles]::Any,
            [System.Globalization.CultureInfo]::InvariantCulture,
            [ref]$excelSerial
        )) {
        return [datetime]::FromOADate($excelSerial)
    }

    $parsedDate = [datetime]::MinValue

    if ([datetime]::TryParselue.ToString(),
            [System.Globalization.CultureInfo]::GetCultureInfo("en-US"),
            [System.Globalization.DateTimeStyles]::AssumeLocal,
            [ref]$parsedDate
        )) {
        return $parsedDate
    }

    throw "Hire date '$Value' is not a recognized date."
}

# Validate the input file.
if (-not (Test-Path -LiteralPath $InputPath)) {
    throw "Input file was not found: $InputPath"
}

# Validate and establish the intended Graph connection.
$graphContext = Get-MgContext -ErrorAction SilentlyContinue

$connectionMatches = (
    $null -ne $graphContext -and
    $graphContext.TenantId -eq $TenantId -and
    $graphContext.ClientId -eq $ClientId -and
    $graphContext.AuthType -eq "AppOnly"
)

if (-not $connectionMatches) {
    if ($graphContext) {
        Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
    }

    Connect-MgGraph `
        -ClientId $ClientId `
        -TenantId $TenantId `
        -CertificateThumbprint $Thumbprint `
        -NoWelcome
}

$graphContext = Get-MgContext

if (
    $graphContext.TenantId -ne $TenantId -or
    $graphContext.ClientId -ne $ClientId -or
    $graphContext.AuthType -ne "AppOnly"
) {
    throw "Microsoft Graph connected with an unexpected tenant, client, or authentication type."
}

Write-Host "Connected to Microsoft Graph using application authentication." `
    -ForegroundColor Green

$userList = @(Import-Excel -Path $InputPath)

if ($userList.Count -eq 0) {
    throw "The input workbook contains no user rows."
}

$results = [System.Collections.Generic.List[object]]::new()

$rowNumber = 1

foreach ($user in $userList) {
    $rowNumber++

    $displayName   = Get-TrimmedValue $user.displayName
    $upn           = Get-TrimmedValue $user.UPN
    $mailNickname  = Get-TrimmedValue $user.mailnickname
    $givenName     = Get-TrimmedValue $user.givenName
    $surname       = Get-TrimmedValue $user.surname
    $department    = Get-TrimmedValue $user.department
    $employeeType  = Get-TrimmedValue $user.employeeType
    $companyName   = Get-TrimmedValue $user.companyName
    $usageLocation = (Get-TrimmedValue $user.usageLocation).ToUpperInvariant()
    $jobTitle      = Get-TrimmedValue $user.jobTitle
    $employeeId    = Get-TrimmedValue $user.employeeId
    $userPassword  = Get-TrimmedValue $user.Password

    $result = [ordered]@{
        RowNumber      = $rowNumber
        DisplayName    = $displayName
        UPN            = $upn
        EmployeeId     = $employeeId
        Action         = ""
        Status         = ""
        UserId         = ""
        EmployeeHireDate = ""
        Error          = ""
        ProcessedAt    = Get-Date
    }

    try {
        # Validate required spreadsheet values.
        $missingFields = [System.Collections.Generic.List[string]]::new()

        if ([string]:: {
            $missingFields.Add("displayName")
        }

        if ([string]:: {
            $missingFields.Add("UPN")
        }

        if ([string]:: {
            $missingFields.Add("mailnickname")
        }

        if ([string]:: {
            $missingFields.Add("givenName")
        }

        if ([string]:: {
            $missingFields.Add("surname")
        }

        if ([string]:: {
            $missingFields.Add("usageLocation")
        }

        if ([string]::IsNullOrWhiteSpace($userPasswordd("Password")
        }

        if ($missingFields.Count -gt 0) {
            throw "Missing required field(s): $($missingFields -join ', ')."
        }

        if ($upn -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') {
            throw "UPN is not in a valid email-style format: $upn"
        }

        if ($usageLocation -notmatch '^[A-Z]{2}$') {
            throw "UsageLocation must be a two-letter country code, such as US."
        }

        $employeeHireDate = ConvertTo-EmployeeHireDate $user.hireDate

        if ($employeeHireDate) {
            $result.EmployeeHireDate = $employeeHireDate.ToString("yyyy-MM-dd")
        }

        # Query the user while distinguishing a real 404 from other Graph errors.
        $existingUser = $null

        try {
            $existingUser = Get-MgUser `
                -UserId $upn `
                -Property Id,DisplayName,UserPrincipalName,EmployeeHireDate `
                -ErrorAction Stop
        }
        catch {
            $statusCode = $null

            if ($_.Exception.ResponseStatusCode) {
                $statusCode = [int]$_.Exception.ResponseStatusCode
            }
            elseif ($_.Exception.Response.StatusCode) {
                $statusCode = [int]$_.Exception.Response.StatusCode
            }

            if ($statusCode -ne 404) {
                throw
            }
        }

        if ($existingUser) {
            $result.Action = "Skipped"
            $result.Status = "Already exists"
            $result.UserId = $existingUser.Id

            Write-Host "User already exists: $displayName ($upn). Skipping creation." `
                -ForegroundColor Yellow

            # Intentionally do not update existing users from this creation script.
            $results.Add([pscustomobject]$result)
            continue
        }

        $passwordProfile = @{
            Password                      = $userPassword
            ForceChangePasswordNextSignIn = $true
        }

        $newUserParameters = @{
            DisplayName       = $displayName
            MailNickname      = $mailNickname
            UserPrincipalName = $upn
            AccountEnabled    = $true
            GivenName         = $givenName
            Surname           = $surname
            UsageLocation     = $usageLocation
            PasswordProfile   = $passwordProfile
        }

        # Only send optional properties when values are present.
        if ($department) {
            $newUserParameters.Department = $department
        }

        if ($employeeType) {
            $newUserParameters.EmployeeType = $employeeType
        }

        if ($companyName) {
            $newUserParameters.CompanyName = $companyName
        }

        if ($jobTitle) {
            $newUserParameters.JobTitle = $jobTitle
        }

        if ($employeeId) {
            $newUserParameters.EmployeeId = $employeeId
        }

        if ($employeeHireDate) {
            $newUserParameters.EmployeeHireDate = $employeeHireDate
        }

        Write-Host "Creating user: $displayName ($upn)" -ForegroundColor Cyan

        $createdUser = New-MgUser @newUserParameters -ErrorAction Stop

        $result.Action = "Created"
        $result.Status = "Success"
        $result.UserId = $createdUser.Id

        Write-Host "Created user: $displayName ($upn)" -ForegroundColor Green
    }
    catch {
        $result.Action = if ($result.Action) {
            $result.Action
        }
        else {
            "Create"
        }

        $result.Status = "Failed"
        $result.Error  = $_.Exception.Message

        Write-Host "Failed to process $displayName ($upn): $($_.Exception.Message)" `
            -ForegroundColor Red
    }

    $results.Add([pscustomobject]$result)
}

$results |
    Export-Excel `
        -Path $ReportPath `
        -WorksheetName "Results" `
        -AutoSize `
        -AutoFilter `
        -FreezeTopRow `
        -BoldTopRow

$createdCount = @($results | Where-Object Status -eq "Success").Count
$skippedCount = @($results | Where-Object Status -eq "Already exists").Count
$failedCount  = @($results | Where-Object Status -eq "Failed").Count

Write-Host ""
Write-Host "Processing complete." -ForegroundColor Green
Write-Host "Created: $createdCount"
Write-Host "Skipped: $skippedCount"
Write-Host "Failed: $failedCount"
Write-Host "Report: $ReportPath"