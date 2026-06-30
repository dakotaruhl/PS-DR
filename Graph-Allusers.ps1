# -----------------------------
# Connect to Graph
# -----------------------------
$Thumbprint = "C47B91EB62634CA61FA8146DDA83B8BF605C0962"
$ClientID   = "ea2ca49b-d0df-4774-b611-86cf9dc9629f"
$TenantID   = "0bdf0e1f-a359-4b5c-9b79-9357e35ff8c6"
Connect-MgGraph -ClientId $ClientID -TenantId $TenantID -CertificateThumbprint $Thumbprint

$reportPath = "C:\Users\DakotaRuhl\Documents\Reports"

$users = Get-MgUser -All `
    -Filter "accountEnabled eq true and userType eq 'Member'" `
    -Property Id,DisplayName,UserPrincipalName

$users | Select-Object DisplayName, UserPrincipalName, Id |
Export-Csv "$($reportPath)\_AllUsers.csv" -NoTypeInformation