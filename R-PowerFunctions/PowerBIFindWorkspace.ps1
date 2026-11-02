Connect-PowerBIServiceAccount

# Use the reportId from the URL/email
$reportId = "ec7e3af7-d9e1-4dbe-8650-2721528e0fd6"

# Optional: shut up the MSAL warnings for this session
$WarningPreference = "SilentlyContinue"

# Query tenant-wide reports, filter to the exact report ID
$json = Invoke-PowerBIRestMethod -Url "admin/reports?`$filter=id eq '$reportId'" -Method Get
$result = $json | ConvertFrom-Json

$result.value | Select-Object id, name, workspaceId, webUrl

$workspaceId = $result.value[0].workspaceId
Get-PowerBIWorkspace -Scope Organization -Id $workspaceId | Select-Object Id, Name, State

Add-PowerBIWorkspaceUser -Id $workspaceId -UserPrincipalName "admin-dr@erock.com" -AccessRight Admin

