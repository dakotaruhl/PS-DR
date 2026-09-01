Connect-azaccount
Connect-MgGraph

$user = "8f3a1a79-b25b-4833-8fb8-bba83b84aac1"
$userEmail = "jhull@graniteproject.dev"
$user2 = "ad9470af-5cdd-4efe-bbdb-960e34011ea4"
$user2Email = "admin-jh@graniteproject.dev"

# Entra roles
Get-MgUserMemberOf -UserId $user
Get-MgUserMemberOf -UserId $user2

# Azure RBAC
Get-AzRoleAssignment -SignInName $userEmail | Select-Object -Property RoleDefinitionName, Scope, SignInName
Get-AzRoleAssignment -SignInName $user2Email | Select-Object -Property RoleDefinitionName, Scope, SignInName

# PIM
Get-AzureADMSPrivilegedRoleAssignment $user

# App ownership
Get-MgUserOwnedObject -UserId $user 

# Group membership
Get-MgUserMemberOf -UserId $user

# Shared mailbox permissions
Get-MailboxPermission
Get-RecipientPermission


$params = @{
    UserPrincipalName    = 'jhull@graniteproject.dev'
    TenantId             = 'a76bf141-b9f9-4f32-ad2a-060b5991730f'
    ClientId             = 'ddbd94ea-ad86-46f0-84af-24998ed86d2d'
    CertificateThumbprint = 'A1D8B302230D51274ED54FB6E1C182B890D560BC'
    ExchangeOrganization = 'enchantedrock.onmicrosoft.com'
    OutputPath           = 'C:\Users\DakotaRuhl\Documents\Reports\Elevated User Offboarding'
}

.\Get-AzureEntraOffboardingReport.ps1 @params