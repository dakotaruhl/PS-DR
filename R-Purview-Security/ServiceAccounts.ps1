Connect-MgGraph -Scopes "AuditLog.Read.All", "Directory.Read.All"

## ## ## 
# ==============================
# CONFIGURATION
# ==============================
$InputFile  = "C:\Users\DakotaRuhl\Documents\Reports\Service Accounts\Service accts.xlsx"
$OutputFile = "C:\Users\DakotaRuhl\Documents\Reports\Service Accounts\ServiceAccounts_Annotated.xlsx"
$DaysBack   = 180

# ==============================
# LOAD DATA
# ==============================
$accounts = Import-Excel $InputFile -sheet "Updated March 19"
$acct = $accounts[2]
$sinceDate = (Get-Date).AddDays(-$DaysBack)

$results = foreach ($acct in $accounts) {

    if (-not $acct.UserPrincipalName) { continue }

    Write-Host "Processing $($acct.UserPrincipalName)" -ForegroundColor Cyan

    try {
        $signins = Get-MgAuditLogSignIn `
            -Filter "userPrincipalName eq '$($acct.UserPrincipalName)' and createdDateTime ge $($sinceDate.ToString('yyyy-MM-ddTHH:mm:ssZ'))" `
            -All
    }
    catch {
        Write-Warning "Failed to query $($acct.UserPrincipalName)"
        continue
    }

    if (-not $signins) {
        [PSCustomObject]@{
            UserPrincipalName     = $acct.UserPrincipalName
            DisplayName           = $acct.DisplayName
            LastSignInDateTime    = $null
            SignInTypeSeen        = "None"
            MostUsedApp           = "None"
            AppSignInCount        = 0
            Classification        = "🗑 Candidate (No Activity)"
            AnnotatedOn           = Get-Date
        }
        continue
    }

    $appUsage = $signins |
        Where-Object { $_.AppDisplayName } |
        Group-Object AppDisplayName |
        Sort-Object Count -Descending

    $topApp = $appUsage | Select-Object -First 1

    $nonInteractive = $signins |
        Where-Object { $_.SignInEventTypes -contains "nonInteractiveUser" }

    $classification = if ($nonInteractive.Count -gt 0) {
        "✅ Keep (Non-Interactive Use)"
    }
    elseif ($signins.Count -gt 0) {
        "⚠ Investigate (Interactive Only)"
    }
    else {
        "🗑 Candidate"
    }

    [PSCustomObject]@{
        UserPrincipalName     = $acct.UserPrincipalName
        DisplayName           = $acct.DisplayName
        LastSignInDateTime    = ($signins | Sort-Object CreatedDateTime -Descending | Select-Object -First 1).CreatedDateTime
        SignInTypeSeen        = ($signins.SignInEventTypes | Sort-Object -Unique) -join ", "
        MostUsedApp           = $topApp.Name
        AppSignInCount        = $topApp.Count
        Classification        = $classification
        AnnotatedOn           = Get-Date
    }
}

# ==============================
# EXPORT
# ==============================
$results | Export-Excel `
    -Path $OutputFile `
    -WorksheetName "Annotated" `
    -AutoSize `
    -BoldTopRow `
    -FreezeTopRow

Write-Host "✅ Annotation complete: $OutputFile" -ForegroundColor Green

# ==============================
# Exchange Activity Check (Optional)
# ==============================
Connect-ExchangeOnline
$DaysBack   = 180
$sinceDate = (Get-Date).AddDays(-$DaysBack)
$InputFile = "C:\Users\DakotaRuhl\Documents\Reports\Service Accounts\ServiceAccounts_Details.xlsx"
$accountsExchange = Import-Excel $InputFile -sheet "All Data" -StartRow 3 -EndColumn 1 | Select-Object UserPrincipalName | Where-Object { $_.UserPrincipalName -ne $null -and $_.UserPrincipalName -ne "" }
#$acct = $accountsExchange[0]
#$acct = $null
$exchangeResults = @()
foreach ($acct in $accountsExchange) {
    Write-Host "Checking Exchange activity for $($acct.UserPrincipalName)" -ForegroundColor Cyan

    try {
        $mailbox = Get-ExoRecipient -Identity $acct.UserPrincipalName -ErrorAction Stop
        if ($mailbox) {
            Write-Host "📧 Mailbox exists for $($acct.UserPrincipalName)" -ForegroundColor Green
            # Optionally, check for recent email activity here using Get-ExoRecipientStatistics or similar cmdlets
            $mailboxStats = Get-MailboxStatistics -Identity $acct.UserPrincipalName
            try {
                $owner = Get-Mailbox $mailboxStats.OwnerADGuid | FL
            }
            catch {
                Write-Warning "Failed to get owner details for $($acct.UserPrincipalName)"
                $owner = $null
            }
            
            #$recipientTypeDetails = $mailboxStats.RecipientTypeDetails
            $exchangeResults += [PSCustomObject]@{
                UserPrincipalName = $acct.UserPrincipalName
                DisplayName = $mailbox.DisplayName
                RecipientType = $mailbox.RecipientTypeDetails
                ResourceUsageMin = $mailboxStats.ResourceUsageMinDateTime
                ResourceUsageMax = $mailboxStats.ResourceUsageMaxDateTime
                ResourceUsageLastInteractive = $mailboxStats.ResourceUsageLastInteractiveClientTime
                OwnerGuid = $mailboxStats.OwnerADGuid
                OwnerDisplayName = $owner.DisplayName
                OwnerUPN = $owner.WindowsEmailAddress
                OwnerOffice = $owner.Office
                ForwardingAddress = $mailbox.ForwardingAddress
            }
        }
    }
    catch {
        Write-Warning "No mailbox found for $($acct.UserPrincipalName)"
    }
}

$cal = @()
$cal += Get-Mailbox -RecipientTypeDetails SchedulingMailbox | ForEach-Object {
    Get-MailboxFolderStatistics $_.Identity -FolderScope Calendar | ForEach-Object {
        [PSCustomObject]@{
            Mailbox = $_.Identity
            CalendarItems = ($_ | Measure-Object ItemsInFolder -Sum).Sum
            LastModified = ($_ | Sort LastModifiedTime -Descending | Select -First 1).LastModifiedTime
        }
    }
}

Get-MailboxFolderPermission -Identity "Chat with Enchanted Rock Expert:\Calendar" | FL
Get-MailboxFolderStatistics -Identity "Chat with Enchanted Rock Expert" -FolderScope Calendar | FL

Get-MailboxFolderPermission -Identity "Conversation with Enchanted Rock:\Calendar" | FL
Get-MailboxFolderStatistics -Identity "Conversation with Enchanted Rock" -FolderScope Calendar | FL

Get-MailboxFolderPermission -Identity "Enchanted Rock:\Calendar" | FL
Get-MailboxFolderStatistics -Identity "Enchanted Rock_626f35c5a7" -FolderScope Calendar | FL

$exchangeResults | Export-Excel `
    -Path "C:\Users\DakotaRuhl\Documents\Reports\Service Accounts\ServiceAccounts_ExchangeActivity.xlsx" `
    -WorksheetName "ExchangeActivity"

get-mailbox -identity enchantedrock@enchantedrock.com