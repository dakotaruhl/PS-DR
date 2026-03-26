# Revoke sessions for all user members of the Entra ID security group "M365Admins"
# Requires: Microsoft.Graph PowerShell SDK
# Permissions: Group.Read.All, User.Read.All, User.RevokeSessions.All (delegated) OR the equivalent app permissions

$GroupDisplayName = "M365Admins"
$LogPath = ".\RevokeSessions_M365Admins_$(Get-Date -Format yyyyMMdd_HHmmss).csv"

# Connect to Graph with the minimum scopes needed
$Scopes = @(
  "Group.Read.All",
  "User.Read.All",
  "User.RevokeSessions.All"
)

Connect-MgGraph -Scopes $Scopes -NoWelcome

# Resolve the group
$group = Get-MgGroup -Filter "displayName eq '$GroupDisplayName'" -ConsistencyLevel eventual -CountVariable cnt

if (-not $group) {
  throw "Group '$GroupDisplayName' was not found."
}
if ($group.Count -gt 1) {
  throw "Multiple groups found named '$GroupDisplayName'. Use ObjectId instead."
}

$groupId = $group.Id
Write-Host "Found group '$GroupDisplayName' ($groupId). Enumerating members..." -ForegroundColor Cyan

# Get all group members (handles paging)
$members = Get-MgGroupMember -GroupId $groupId -All

# Filter to user objects only
$userMembers = foreach ($m in $members) {
  if ($m.AdditionalProperties.'@odata.type' -eq '#microsoft.graph.user') {
    # Pull full user object to get UPN/displayName reliably
    Get-MgUser -UserId $m.Id -Property "id,displayName,userPrincipalName,accountEnabled"
  }
}

Write-Host ("User members found: {0}" -f ($userMembers | Measure-Object).Count) -ForegroundColor Cyan

$results = foreach ($u in $userMembers) {
  $status = "Unknown"
  $errorText = $null

  try {
    # Revokes refresh tokens / sign-in sessions (forces re-auth)
    Revoke-MgUserSignInSession -UserId $u.Id | Out-Null
    $status = "Revoked"
    Write-Host "Revoked sessions: $($u.UserPrincipalName)" -ForegroundColor Green
  }
  catch {
    $status = "Failed"
    $errorText = $_.Exception.Message
    Write-Host "FAILED: $($u.UserPrincipalName) - $errorText" -ForegroundColor Red
  }

  [pscustomobject]@{
    Timestamp         = (Get-Date).ToString("s")
    Group             = $GroupDisplayName
    DisplayName       = $u.DisplayName
    UserPrincipalName = $u.UserPrincipalName
    AccountEnabled    = $u.AccountEnabled
    Result            = $status
    Error             = $errorText
  }
}

$results | Export-Csv -Path $LogPath -NoTypeInformation
Write-Host "Done. Log written to $LogPath" -ForegroundColor Cyan