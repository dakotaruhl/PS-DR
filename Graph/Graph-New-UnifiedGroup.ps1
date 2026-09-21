# =====================================================
# Connect
# =====================================================  

$Thumbprint = "C47B91EB62634CA61FA8146DDA83B8BF605C0962"
$ClientID   = "ea2ca49b-d0df-4774-b611-86cf9dc9629f"
$TenantId = "0bdf0e1f-a359-4b5c-9b79-9357e35ff8c6"
$Tenant = "enchantedrock.onmicrosoft.com"

Connect-MgGraph `
        -TenantId $TenantId `
        -ClientId $ClientID `
        -CertificateThumbprint $Thumbprint `
        -NoWelcome

# =====================================================
# Configuration
# =====================================================          

$HideFromAddressLists = $true
$visibility = "Private"
$displayName = "Board Meeting Prep"
$mailNickname = $displayName -replace '\s',''
$description = "Board Meeting Preparation Group"
$primarySmtpAddress = "$($mailNickname)@erock.com"
$members = @(
    "JCarrington@erock.com",
    "SGhubril@erock.com",
    "DZapffe@erock.com",
    "IBlakely@erock.com",
    "CAmthor@erock.com",
    "TDurbin@erock.com",
    "MButler@erock.com",
    "dyamamoto@erock.com",
    "ANew@erock.com",
    "PFroutan@erock.com",
    "ASchurr@erock.com",
    "TPrice@erock.com",
    "AMiddleton@erock.com"
)
$owner = "arohan@erock.com"


$OwnerId = ("https://graph.microsoft.com/v1.0/users/{0}" -f (Get-MgUser -UserId $owner).Id ) 
$NewGroupSettings = @{ 
    "displayName" = $displayName
    "mailNickname"= $mailNickname 
    "description" = $description 
    "owners@odata.bind" = @($OwnerId) 
    "groupTypes" = @("Unified") 
    "mailEnabled" = "true" 
    "securityEnabled" = "false" 
    "ResourceBehaviorOptions" = @("WelcomeEmailDisabled") 
}  

# =====================================================
# Create Group
# ===================================================== 

$NewGroup = New-MgGroup -BodyParameter $NewGroupSettings

# Update group settings
$params = @{
    description = $description
    visibility  = $visibility
    SecurityEnabled = $true
}

# Add members
foreach ($member in $members) {

    $user = Get-MgUser -UserId $member

    New-MgGroupMemberByRef `
        -GroupId $NewGroup.Id `
        -BodyParameter @{
            '@odata.id' = "https://graph.microsoft.com/v1.0/directoryObjects/$($user.Id)"
        }
}

Update-MgGroup `
    -GroupId $NewGroup.Id `
    -BodyParameter $params 

# Set Exchange Properties
Connect-ExchangeOnline -CertificateThumbprint $Thumbprint -AppId $ClientID -Organization $Tenant

Set-UnifiedGroup `
    -Identity $NewGroup.Id `
    -primarySmtpAddress $primarySmtpAddress `
    -HiddenFromAddressListsEnabled:$HideFromAddressLists `
    -autoSubscribeNewMembers:$true `
    -SubscriptionEnabled:$true
    