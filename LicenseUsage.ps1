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

#Find all users for a specific license (e.g. Visio Plan 2)  
$skuFriendlyName = "Visio Plan 2"
$skuId = "c5928f49-12ba-48f7-ada3-0d743a3601d5" # Visio Plan 2
$licensedUsers = Get-MgUser -All -Property UserPrincipalName, DisplayName, AssignedLicenses 
    | Where-Object { $_.AssignedLicenses.skuId -contains $skuId } 
    | Select-Object UserPrincipalName, DisplayName
$licensedUsers.Count
#create report for licensed users
$licensedUsers | Export-Excel -Path "$env:USERPROFILE\Documents\Reports\License Usage\$($skuFriendlyName)LicensedUsers.xlsx" -WorkSheetname 'LicensedUsers' -AutoSize

# Consent once as an admin; Reports.Read.All is required
Connect-MgGraph -Scopes "Reports.Read.All"

# Download the CSV to a local path
$path = "$env:TEMP\o365_active_users_D90.csv"
Get-MgReportOffice365ActiveUserDetail -Period D90 -OutFile $path

# Load the CSV for analysis
$data = Import-Csv $path
# Example: show last activity columns per user
$data | Select-Object UserPrincipalName, LastActivityDate, ExchangeActive, OneDriveActive, SharePointActive, TeamsActive | Format-Table -Auto


