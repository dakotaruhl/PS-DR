# -----------------------------
# Connect to Graph
# -----------------------------
$Thumbprint = "C47B91EB62634CA61FA8146DDA83B8BF605C0962"
$ClientID   = "ea2ca49b-d0df-4774-b611-86cf9dc9629f"
$TenantID   = "0bdf0e1f-a359-4b5c-9b79-9357e35ff8c6"
Connect-MgGraph -ClientId $ClientID -TenantId $TenantID -CertificateThumbprint $Thumbprint

# -----------------------------
# Configuration
# -----------------------------
$objectID = "6f781269-ff56-408c-a8a3-bb24dc476756"
$reportPath = "C:\Users\DakotaRuhl\Documents\Reports"

# -----------------------------
# Create user objects for export 
# -----------------------------
$sp = Get-MgServicePrincipal -ServicePrincipalId $objectID
$appName = $sp.AppDisplayName
$assignments = Get-MgServicePrincipalAppRoleAssignedTo -ServicePrincipalId $sp.Id -All


$result = foreach ($a in $assignments) {
    if ($a.PrincipalType -eq "User") {
        $user = Get-MgUser -UserId $a.PrincipalId
        [PSCustomObject]@{
            DisplayName = $user.DisplayName
            UserPrincipalName = $user.UserPrincipalName
            Email = $user.Mail
            ObjectId = $user.Id
            RoleId = $a.AppRoleId
        }
    }
}

# -----------------------------
# Export users
# -----------------------------
$result | Export-Csv "$($reportPath)\$($appName)_UserList.csv" -NoTypeInformation

