Connect-PowerBIServiceAccount

# Use the reportId from the URL/email
$reportId = "dd0cd391-6fa0-4759-9c3a-7a092a268d9a"

# Optional: shut up the MSAL warnings for this session
$WarningPreference = "SilentlyContinue"

# Query tenant-wide reports, filter to the exact report ID
$json = Invoke-PowerBIRestMethod -Url "admin/reports?`$filter=id eq '$reportId'" -Method Get
$result = $json | ConvertFrom-Json

$result.value | Select-Object id, name, workspaceId, webUrl

$workspaceId = $result.value[0].workspaceId
Get-PowerBIWorkspace -Scope Organization -Id $workspaceId | Select-Object Id, Name, State

Add-PowerBIWorkspaceUser -Id $workspaceId -UserPrincipalName "admin-dr@enchantedrock.com" -AccessRight Admin
