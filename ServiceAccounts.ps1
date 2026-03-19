Connect-MgGraph -Scopes "AuditLog.Read.All", "Directory.Read.All"

#Interactive
$userUPN = "helpdesk@enchantedrock.com"
Get-MgAuditLogSignIn -Filter "userPrincipalName eq '$userUPN'" -Top 1 | Select-Object CreatedDateTime, UserPrincipalName, AppId, AppDisplayName, Status
Get-MgAuditLogSignIn -Filter "userPrincipalName eq 'druhl@enchantedrock.com'" -Top 1 | Select-Object CreatedDateTime, UserPrincipalName, AppId, AppDisplayName, Status

#Non-interactive

Disconnect-Graph
Import-Module Microsoft.Graph.Beta
# Connect-MgGraph again if the profile change requires re-authentication
Select-MgProfile -Name "beta"
$Filter = "(signInEventTypes/any(t: t ne 'interactiveUser'))"
Get-MgAuditLogSignIn -Filter $Filter -All
# Note: In the beta profile, the cmdlet might be named Get-MgBetaAuditLogSignIn
