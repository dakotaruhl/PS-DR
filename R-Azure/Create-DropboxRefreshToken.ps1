# $env:DROPBOX_ACCESS_TOKEN = 'PASTE-NEW-TOKEN-HERE'
# $env:DROPBOX_APP_KEY = 'PASTE-KEY-HERE'
# $env:DROPBOX_APP_SECRET = 'PASTE-SECRET-HERE'

#Generate Dropbox authorization URL for offline token
$AuthorizeUrl = "https://www.dropbox.com/oauth2/authorize?client_id=$($env:DROPBOX_APP_KEY)&response_type=code&token_access_type=offline"
$AuthorizeUrl

# After visiting the URL and authorizing, you will receive a code. Exchange it for an access token.
$AuthorizationCode = Read-Host "Enter the authorization code you received from Dropbox"
$BasicCredential = [Convert]::ToBase64String(
    [Text.Encoding]::ASCII.GetBytes(
        "$($env:DROPBOX_APP_KEY):$($env:DROPBOX_APP_SECRET)"
    )
)

$TokenResponse = Invoke-RestMethod `
    -Method Post `
    -Uri "https://api.dropboxapi.com/oauth2/token" `
    -Headers @{
        Authorization = "Basic $BasicCredential"
    } `
    -ContentType "application/x-www-form-urlencoded" `
    -Body @{
        code       = $AuthorizationCode
        grant_type = "authorization_code"
    }

$env:DROPBOX_REFRESH_TOKEN = $TokenResponse.refresh_token
Remove-Item Env:DROPBOX_ACCESS_TOKEN `
    -ErrorAction SilentlyContinue