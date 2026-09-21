# Connect to Microsoft Graph
$TenantAdminURL = "https://enchantedrock-admin.sharepoint.com/"
$Thumbprint = "C47B91EB62634CA61FA8146DDA83B8BF605C0962"
$ClientID = "ea2ca49b-d0df-4774-b611-86cf9dc9629f"
$TenantID = "0bdf0e1f-a359-4b5c-9b79-9357e35ff8c6"
Connect-MgGraph -ClientId $ClientID -TenantId $TenantID -CertificateThumbprint $Thumbprint 
# Cache all users, groups, and service principals for name resolution
Write-Host "Caching directory objects..."

$Users  = Get-MgUser -All -Property Id,DisplayName,UserPrincipalName | Group-Object Id -AsHashTable
$Groups = Get-MgGroup -All -Property Id,DisplayName | Group-Object Id -AsHashTable
$SPs    = Get-MgServicePrincipal -All -Property Id,DisplayName,AppRoles

# Build lookup table for service principals
$SPTable = $SPs | Group-Object Id -AsHashTable

$Results = @()

foreach ($sp in $SPs) {

    Write-Host "Processing $($sp.DisplayName)"

    # Get assignments to the Enterprise App
    $assignments = Get-MgServicePrincipalAppRoleAssignedTo `
        -ServicePrincipalId $sp.Id `
        -All `
        -ErrorAction SilentlyContinue

    foreach ($a in $assignments) {

        # Resolve assignee type and name
        switch ($a.PrincipalType) {
            "User" {
                $Name = $Users[$a.PrincipalId]?.DisplayName
                $UPN  = $Users[$a.PrincipalId]?.UserPrincipalName
            }
            "Group" {
                $Name = $Groups[$a.PrincipalId]?.DisplayName
                $UPN  = $null
            }
            "ServicePrincipal" {
                $Name = $SPTable[$a.PrincipalId]?.DisplayName
                $UPN  = $null
            }
            default {
                $Name = "Unknown"
                $UPN  = $null
            }
        }

        # Resolve App Role name
        $RoleName = $sp.AppRoles |
            Where-Object { $_.Id -eq $a.AppRoleId } |
            Select-Object -ExpandProperty DisplayName -First 1

        if (-not $RoleName) {
            $RoleName = "Default access"
        }

        $Results += [pscustomobject]@{
            EnterpriseApp      = $sp.DisplayName
            EnterpriseAppId    = $sp.Id
            AssignedObjectType = $a.PrincipalType
            AssignedObjectName = $Name
            AssignedUPN        = $UPN
            AppRole            = $RoleName
        }
    }
}

# Export
$Results | Sort-Object EnterpriseApp,AssignedObjectType |
    Export-Csv "C:\Users\DakotaRuhl\Documents\Reports\EnterpriseAppAssignments.csv" -NoTypeInformation -Encoding UTF8

Write-Host "Done. Output: C:\Users\DakotaRuhl\Documents\Reports\EnterpriseAppAssignments.csv"