# =====================================================
# Key Vault Authentication App
# =====================================================

$TenantId           = "0bdf0e1f-a359-4b5c-9b79-9357e35ff8c6"
$KeyVaultAppId      = "2c26c598-5c72-40eb-a4c0-2d3dd4cb361c"
#$KeyVaultAppSecret  = Get From Bitwarden
$VaultName          = "kv-azureaps"

# =====================================================
# Authenticate to Azure using Client ID / Secret
# =====================================================

$SecureSecret = ConvertTo-SecureString $KeyVaultAppSecret -AsPlainText -Force

$Credential = New-Object System.Management.Automation.PSCredential(
    $KeyVaultAppId,
    $SecureSecret
)

Connect-AzAccount `
    -ServicePrincipal `
    -Tenant $TenantId `
    -Credential $Credential | Out-Null

# =====================================================
# Retrieve secrets from Key Vault
# =====================================================

$GraphClientId = Get-AzKeyVaultSecret `
    -VaultName $VaultName `
    -Name "OAuth-SMTP-ClientId" `
    -AsPlainText

$GraphClientSecret = Get-AzKeyVaultSecret `
    -VaultName $VaultName `
    -Name "OAuth-SMTP-Secret" `
    -AsPlainText

# Optional if stored in Key Vault
# $GraphTenantId = Get-AzKeyVaultSecret `
#     -VaultName $VaultName `
#     -Name "OAuth-SMTP-TenantId" `
#     -AsPlainText

# =====================================================
# Create an access token for Microsoft Graph API
# =====================================================

$TokenBody = @{
    grant_type    = "client_credentials"
    client_id     = $GraphClientId
    client_secret = $GraphClientSecret
    scope         = "https://graph.microsoft.com/.default"
}

$TokenResponse = Invoke-RestMethod `
    -Method Post `
    -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" `
    -Body $TokenBody

$AccessToken = $TokenResponse.access_token

# =====================================================
# Send Mail
# =====================================================

# Reusable function optional parameters for From, To, Subject, Body, TenantId, ClientId, ClientSecret
function Send-GraphMail {
    param(
        [string]$From,
        [string]$To,
        [string]$Subject,
        [string]$Body,
        [string]$TenantId,
        [string]$ClientId,
        [string]$ClientSecret
    )

    $Token = Invoke-RestMethod `
        -Method POST `
        -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" `
        -Body @{
            client_id     = $ClientId
            client_secret = $ClientSecret
            grant_type    = "client_credentials"
            scope         = "https://graph.microsoft.com/.default"
        }

    $Payload = @{
        message = @{
            subject = $Subject
            body = @{
                contentType = "HTML"
                content = $Body
            }
            toRecipients = @(
                @{
                    emailAddress = @{
                        address = $To
                    }
                }
            )
        }
        saveToSentItems = $true
    } | ConvertTo-Json -Depth 10

    Invoke-RestMethod `
        -Method POST `
        -Uri "https://graph.microsoft.com/v1.0/users/$From/sendMail" `
        -Headers @{
            Authorization = "Bearer $($Token.access_token)"
            "Content-Type" = "application/json"
        } `
        -Body $Payload
}


# Send a test email without using function  
$From = "SSRSreport@enchantedrock.com"
$To   = "druhl@erock.com"

$MailBody = @{
    message = @{
        subject = "Graph Mail Test"

        body = @{
            contentType = "HTML"
            content     = "<p>This was sent using Microsoft Graph.</p>"
        }

        toRecipients = @(
            @{
                emailAddress = @{
                    address = $To
                }
            }
        )
    }

    saveToSentItems = $true
} | ConvertTo-Json -Depth 10

$Headers = @{
    Authorization = "Bearer $AccessToken"
    "Content-Type" = "application/json"
}

Invoke-RestMethod `
    -Method POST `
    -Uri "https://graph.microsoft.com/v1.0/users/$From/sendMail" `
    -Headers $Headers `
    -Body $MailBody