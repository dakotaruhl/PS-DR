# =====================================================
# Connect
# =====================================================  

$Thumbprint = "C47B91EB62634CA61FA8146DDA83B8BF605C0962"
$ClientID   = "ea2ca49b-d0df-4774-b611-86cf9dc9629f"
$TenantId = "0bdf0e1f-a359-4b5c-9b79-9357e35ff8c6"

Connect-MgGraph `
        -TenantId $TenantId `
        -ClientId $ClientID `
        -CertificateThumbprint $Thumbprint `
        -NoWelcome

# =====================================================
# Configuration
# =====================================================          

$displayName = "Board Meeting Prep"
$accessType = "Private"
$primarySmtpAddress = "$($displayName.Trim())@erock.com"


#-SubscriptionEnabled -AutoSubscribeNewMembers