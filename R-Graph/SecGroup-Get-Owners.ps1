# Connect to Microsoft Graph using certificate-based authentication

Connect-MgGraph `
        -TenantId $env:AZURE_TENANT_ID `
        -ClientId $env:AZURE_CLIENT_ID `
        -CertificateThumbprint $env:AZURE_CLIENT_CERTIFICATE_THUMBPRINT `
        -NoWelcome

# Get all groups beginning with BC-ROLE
$Groups = Get-MgGroup `
    -Filter "startsWith(displayName,'BC-ROLE')" `
    -ConsistencyLevel eventual `
    -All `
    -Property Id, DisplayName, Mail, SecurityEnabled, GroupTypes

$Results = foreach ($Group in $Groups) {

    if ($Group.SecurityEnabled -ne $true) {
        continue
    }

    $Owners = @(
        Get-MgGroupOwner `
            -GroupId $Group.Id `
            -All
    )

    $OwnerNames = @(
        $Owners | ForEach-Object {
            $_.AdditionalProperties["displayName"]
        }
    )

    [PSCustomObject]@{
        DisplayName = $Group.DisplayName
        GroupId     = $Group.Id
        OwnerCount  = $Owners.Count
        Owners      = ($OwnerNames -join "; ")
        OwnerStatus = switch ($Owners.Count) {
            0       { "NO OWNER" }
            1       { "SINGLE OWNER" }
            default { "MULTIPLE OWNERS" }
        }
    }
}

$Results |
    Sort-Object OwnerCount, DisplayName |
    Format-Table DisplayName, OwnerCount, OwnerStatus, Owners -AutoSize


Export-Excel -InputObject $Results -Path ".\output\BCRoleGroups.xlsx" -AutoSize