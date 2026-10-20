
$ManagedIdentityObjectId = "6e0f75bb-2aef-46ba-b80a-c9045d7ecd00"
$ManagedIdentityClientId = "7f2929c1-44c0-4aaf-8f1a-a4eed05fa3e3"
$ExchangeOnlineAppId = "00000002-0000-0ff1-ce00-000000000000"

Connect-MgGraph -TenantId $env:AZURE_TENANT_ID `
        -ClientId $env:AZURE_CLIENT_ID `
        -CertificateThumbprint $env:AZURE_CLIENT_CERTIFICATE_THUMBPRINT `
        -NoWelcome

#### Grant Exchange.ManageAsApp
$ExchangeServicePrincipal = Get-MgServicePrincipal `
    -Filter "appId eq '$ExchangeOnlineAppId'"

if (-not $ExchangeServicePrincipal) {
    throw "The Office 365 Exchange Online service principal was not found."
}

$ExchangeManageAsAppRole = $ExchangeServicePrincipal.AppRoles |
    Where-Object {
        $_.Value -eq "Exchange.ManageAsApp" -and
        $_.AllowedMemberTypes -contains "Application"
    }

if (-not $ExchangeManageAsAppRole) {
    throw "The Exchange.ManageAsApp application role was not found."
}

$ExistingAssignment = Get-MgServicePrincipalAppRoleAssignment `
    -ServicePrincipalId $ManagedIdentityObjectId `
    -All |
    Where-Object {
        $_.ResourceId -eq $ExchangeServicePrincipal.Id -and
        $_.AppRoleId -eq $ExchangeManageAsAppRole.Id
    }

if (-not $ExistingAssignment) {
    New-MgServicePrincipalAppRoleAssignment `
        -ServicePrincipalId $ManagedIdentityObjectId `
        -PrincipalId $ManagedIdentityObjectId `
        -ResourceId $ExchangeServicePrincipal.Id `
        -AppRoleId $ExchangeManageAsAppRole.Id

    Write-Host "Granted Exchange.ManageAsApp." -ForegroundColor Green
}
else {
    Write-Host "Exchange.ManageAsApp is already assigned." -ForegroundColor DarkGray
}

Disconnect-MgGraph

#### Create the Exchange service-principal reference
Connect-ExchangeOnline `
    -CertificateThumbprint $env:AZURE_CLIENT_CERTIFICATE_THUMBPRINT  `
    -AppId $env:AZURE_CLIENT_ID `
    -Organization $env:AZURE_TENANT_DOMAIN

$ExchangeServicePrincipalName = "AA-CustomAttribute1-Set-OfficeLocation"

$ExchangeServicePrincipal = Get-ServicePrincipal |
    Where-Object {
        $_.ObjectId -eq $ManagedIdentityObjectId -or
        $_.AppId -eq $ManagedIdentityClientId
    }

if (-not $ExchangeServicePrincipal) {
    $ExchangeServicePrincipal = New-ServicePrincipal `
        -AppId $ManagedIdentityClientId `
        -ObjectId $ManagedIdentityObjectId `
        -DisplayName $ExchangeServicePrincipalName

    Write-Host "Created Exchange service-principal reference." -ForegroundColor Green
}
else {
    Write-Host "Exchange service-principal reference already exists." -ForegroundColor DarkGray
}

#### Find the correct parent role in your tenant
Get-ManagementRole `
    -Cmdlet Set-Mailbox `
    -CmdletParameters Identity,ExtensionCustomAttribute1 |
    Format-Table Name, RoleType -AutoSize

Get-ManagementRoleEntry "Mail Recipients\Get-Mailbox" |
    Format-List Name, Parameters

Get-ManagementRoleEntry "Mail Recipients\Set-Mailbox" |
    Format-List Name, Parameters

#### Create the restricted management role
$ParentRoleName = "Mail Recipients"
$CustomRoleName = "Set-OfficeLocationExtensionAttribute"

#### Create the child role:
if (-not (Get-ManagementRole -Identity $CustomRoleName -ErrorAction SilentlyContinue)) {
    New-ManagementRole `
        -Name $CustomRoleName `
        -Parent $ParentRoleName

    Write-Host "Created custom management role." -ForegroundColor Green
}
else {
    Write-Host "Custom management role already exists." -ForegroundColor DarkGray
}

#### Remove every unnecessary cmdlet

$AllowedCmdlets = @(
    "Get-Mailbox"
    "Set-Mailbox"
)

$RoleEntriesToRemove = Get-ManagementRoleEntry "$CustomRoleName\*" |
    Where-Object {
        $_.Name -notin $AllowedCmdlets
    }

foreach ($RoleEntry in $RoleEntriesToRemove) {
    Remove-ManagementRoleEntry `
        -Identity "$CustomRoleName\$($RoleEntry.Name)" `
        -Confirm:$false
}

#### Restrict the allowed parameters
Set-ManagementRoleEntry `
    -Identity "$CustomRoleName\Get-Mailbox" `
    -Parameters Identity,ResultSize,RecipientTypeDetails
Set-ManagementRoleEntry `
    -Identity "$CustomRoleName\Set-Mailbox" `
    -Parameters Identity,ExtensionCustomAttribute1

#### Verify 
Get-ManagementRoleEntry "$CustomRoleName\*" |
    Select-Object Name, Parameters |
    Format-List

# Name       : Get-Mailbox
# Parameters : {Identity, ResultSize, RecipientTypeDetails}

# Name       : Set-Mailbox
# Parameters : {Identity, ExtensionCustomAttribute1}

#### Create role group 
$RoleGroupName = "RG-AA-Set-OfficeLocationExtensionAttribute"

if (-not (Get-RoleGroup -Identity $RoleGroupName -ErrorAction SilentlyContinue)) {
    New-RoleGroup `
        -Name $RoleGroupName `
        -Roles $CustomRoleName

    Write-Host "Created custom Exchange role group." -ForegroundColor Green
}
else {
    Write-Host "Exchange role group already exists." -ForegroundColor DarkGray
}

#### Add managed identity to the role group if not already a member
$RoleGroup = Get-RoleGroup -Identity $RoleGroupName

$ExistingMember = Get-RoleGroupMember `
    -Identity $RoleGroup.Identity `
    -ErrorAction SilentlyContinue |
    Where-Object {
        $_.ExternalDirectoryObjectId -eq $ManagedIdentityObjectId -or
        $_.Name -eq $ExchangeServicePrincipalName
    }

if (-not $ExistingMember) {
    Add-RoleGroupMember `
        -Identity $RoleGroup.Identity `
        -Member $ManagedIdentityObjectId

    Write-Host "Added managed identity to the role group." -ForegroundColor Green
}
else {
    Write-Host "Managed identity is already a member." -ForegroundColor DarkGray
}


## Clean up / remove 
## Inventory / Verify existing setup

$RoleGroupName       = "RG-AA-Set-OfficeLocationExtensionAttribute"
$CustomRoleName      = "Set-OfficeLocationExtensionAttribute"
$ServicePrincipalName = "AA-CustomAttribute1-Set-OfficeLocation"

Write-Host "=== Role Group ==="
Get-RoleGroup -Identity $RoleGroupName |
    Format-List Name,Roles,Members

Write-Host "`n=== Role Group Members ==="
Get-RoleGroupMember -Identity $RoleGroupName |
    Format-Table Name,RecipientType,PrimarySmtpAddress -AutoSize

Write-Host "`n=== Custom Role Assignments ==="
Get-ManagementRoleAssignment -Role $CustomRoleName |
    Format-Table Name,Role,RoleAssigneeName,RoleAssigneeType -AutoSize

Write-Host "`n=== Exchange Service Principal ==="
Get-ServicePrincipal -Identity $ServicePrincipalName |
    Format-List DisplayName,AppId,ObjectId,Identity

##Remove role group and custom role assignment
Write-Host "`n=== Removing Role Group ==="
Remove-RoleGroup `
    -Identity "RG-AA-Set-OfficeLocationExtensionAttribute" `
    -Confirm:$false

Get-RoleGroup `
    -Identity "RG-AA-Set-OfficeLocationExtensionAttribute" `
    -ErrorAction SilentlyContinue

Write-Host "`n=== Removing Custom Role Assignment ==="  
Remove-ManagementRoleAssignment `
    $CustomRoleName `
    -Confirm:$false

Get-ManagementRoleAssignment `
    -Role "Set-OfficeLocationExtensionAttribute" |
    Format-Table `
        Name,
        Role,
        RoleAssigneeName,
        RoleAssigneeType `
        -AutoSize

Remove-ManagementRole `
    -Identity "Set-OfficeLocationExtensionAttribute" `
    -Confirm:$false

Get-ManagementRole -Identity "Set-OfficeLocationExtensionAttribute" -ErrorAction SilentlyContinue

##Remove service principal
$ExchangeServicePrincipal = Get-ServicePrincipal `
    -Identity "AA-CustomAttribute1-Set-OfficeLocation"

$ExchangeServicePrincipal |
    Format-List DisplayName,AppId,ObjectId,Identity

Remove-ServicePrincipal `
    -Identity $ExchangeServicePrincipal.Identity `
    -Confirm:$false

Get-ServicePrincipal -Identity "AA-CustomAttribute1-Set-OfficeLocation" -ErrorAction SilentlyContinue

Write-Host "`n=== Finished Cleanup ==="

Get-ManagementRoleAssignment `
    -Role "Set-OfficeLocationExtensionAttribute" |
    Format-Table `
        Name,
        Role,
        RoleAssigneeName,
        RoleAssigneeType `
        -AutoSize

