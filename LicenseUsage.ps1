# Requires Microsoft.Graph module
# This example fetches the Office 365 Active User Detail CSV for the last 90 days.
# NOTE: Microsoft’s generic "Active User Detail" report covers core workloads
# (Exchange, OneDrive, SharePoint, Teams, etc.) but NOT Visio/Project specifically.
# Get license names https://learn.microsoft.com/en-us/entra/identity/users/licensing-service-plan-reference

Install-Module Microsoft.Graph -Scope CurrentUser
Import-Module Microsoft.Graph.Reports
Import-Module ImportExcel

#Connect to graph with permission to read licenses 
Connect-MgGraph -Scopes "User.Read.All", "Directory.Read.All"

#Exchange for recipient details
Connect-ExchangeOnline

#Find all users for a specific license (e.g. Visio Plan 2)  
$skuFriendlyName = "Microsoft 365 Business Basic "
$skuId = "3b555118-da6a-4418-894f-7df1e2096870"
$licensedUsers = Get-MgUser -All -Property UserPrincipalName, DisplayName, AssignedLicenses 
    | Where-Object { $_.AssignedLicenses.skuId -contains $skuId } 
    | Select-Object UserPrincipalName, DisplayName
$licensedUsers.Count
#create report for licensed users
$licensedUsers | Export-Excel -Path "$env:USERPROFILE\Documents\Reports\License Usage\$($skuFriendlyName) LicensedUsers.xlsx" -WorkSheetname 'LicensedUsers' -AutoSize

#get recipient type details for $licensedusers
$licensedUserDetails = foreach ($user in $licensedUsers) {
    $recipient = Get-MgUser -UserId $user.UserPrincipalName -Property UserPrincipalName, DisplayName, AssignedLicenses
    $recipientdetails = Get-Recipient -Identity $user.UserPrincipalName | Select-Object RecipientType
    [PSCustomObject]@{
        UserPrincipalName = $recipient.UserPrincipalName
        DisplayName = $recipient.DisplayName
        RecipientType = $recipientdetails.RecipientType
    }
}

$licensedUserDetails | Export-Excel -Path "$env:USERPROFILE\Documents\Reports\License Usage\$($skuFriendlyName) LicensedUsers_Details.xlsx" -WorkSheetname 'LicensedUsersDetails' -AutoSize


#Check a user's license details
$userPrincipalName = "ratkinson@enchantedrock.com"
$user = Get-MgUser -UserId $userPrincipalName -Property AssignedLicenses
$user.AssignedLicenses | ForEach-Object {
    $skuId = $_.skuId
    $licenseDetails = Get-MgSubscribedSku | Where-Object { $_.SkuId -eq $skuId }
    [PSCustomObject]@{
        SkuId = $skuId
        SkuPartNumber = $licenseDetails.SkuPartNumber
        AssignedDateTime = $_.assignedDateTime
    }
} | Format-Table -AutoSize

# Consent once as an admin; Reports.Read.All is required
Connect-MgGraph -Scopes "Reports.Read.All"

# Download the CSV to a local path
$path = "$env:TEMP\o365_active_users_D90.csv"
Get-MgReportOffice365ActiveUserDetail -Period D90 -OutFile $path

# Load the CSV for analysis
$data = Import-Csv $path
# Example: show last activity columns per user
$data | Select-Object UserPrincipalName, LastActivityDate, ExchangeActive, OneDriveActive, SharePointActive, TeamsActive | Format-Table -Auto


