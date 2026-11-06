[Environment]::SetEnvironmentVariable(
    'DROPBOX_REFRESH_TOKEN',
    'YOUR_REFRESH_TOKEN',
    'User'
)

[Environment]::SetEnvironmentVariable(
    'DROPBOX_APP_KEY',
    'YOUR_APP_KEY',
    'User'
)

[Environment]::SetEnvironmentVariable(
    'DROPBOX_APP_SECRET',
    'YOUR_APP_SECRET',
    'User'
)

# ---------------------------------------------------------------------------
# Dropbox OAuth Bootstrap
#
# DROPBOX_APP_KEY and DROPBOX_APP_SECRET are expected to already exist as
# User-scoped environment variables.
#
# This authorization process only needs to be performed when creating or
# replacing the Dropbox refresh token.
# ---------------------------------------------------------------------------

$DropboxAppKey = [Environment]::GetEnvironmentVariable(
    'DROPBOX_APP_KEY',
    'User'
)

$DropboxAppSecret = [Environment]::GetEnvironmentVariable(
    'DROPBOX_APP_SECRET',
    'User'
)

if ([string]::IsNullOrWhiteSpace($DropboxAppKey)) {
    throw "User environment variable 'DROPBOX_APP_KEY' is not configured."
}

if ([string]::IsNullOrWhiteSpace($DropboxAppSecret)) {
    throw "User environment variable 'DROPBOX_APP_SECRET' is not configured."
}


# Generate Dropbox authorization URL requesting offline access.
$AuthorizeUrl = "https://www.dropbox.com/oauth2/authorize?client_id=$DropboxAppKey&response_type=code&token_access_type=offline"

Write-Host ""
Write-Host "Open the following URL and authorize the Dropbox application:"
Write-Host ""
Write-Host $AuthorizeUrl
Write-Host ""


# After authorization, Dropbox provides a one-time authorization code.
$AuthorizationCode = Read-Host "Enter the authorization code you received from Dropbox"

if ([string]::IsNullOrWhiteSpace($AuthorizationCode)) {
    throw 'Dropbox authorization code cannot be empty.'
}


# Create HTTP Basic authentication using the Dropbox app key and secret.
$BasicCredential = [Convert]::ToBase64String(
    [Text.Encoding]::ASCII.GetBytes(
        "${DropboxAppKey}:${DropboxAppSecret}"
    )
)


# Exchange the authorization code for an access token and refresh token.
$TokenResponse = Invoke-RestMethod `
    -Method Post `
    -Uri 'https://api.dropboxapi.com/oauth2/token' `
    -Headers @{
        Authorization = "Basic $BasicCredential"
    } `
    -ContentType 'application/x-www-form-urlencoded' `
    -Body @{
        code       = $AuthorizationCode
        grant_type = 'authorization_code'
    }


if ([string]::IsNullOrWhiteSpace($TokenResponse.refresh_token)) {
    throw 'Dropbox did not return a refresh token.'
}


# Persist the refresh token at User scope.
[Environment]::SetEnvironmentVariable(
    'DROPBOX_REFRESH_TOKEN',
    [string]$TokenResponse.refresh_token,
    'User'
)


# Also make it available immediately in the current PowerShell process.
$env:DROPBOX_REFRESH_TOKEN = [string]$TokenResponse.refresh_token


Write-Host ""
Write-Host "Dropbox authorization completed successfully." -ForegroundColor Green
Write-Host "DROPBOX_REFRESH_TOKEN has been saved as a User environment variable."
Remove-Item Env:DROPBOX_ACCESS_TOKEN `
    -ErrorAction SilentlyContinue