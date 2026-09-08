using namespace System.Net

param($Request, $TriggerMetadata)

Write-Information 'SendMail function triggered.'

# ---------------------------------------------------------------------------
# 1. Read and validate input
# ---------------------------------------------------------------------------
$To      = $Request.Body.To
$Subject = $Request.Body.Subject
$Body    = $Request.Body.Body
$Cc      = $Request.Body.Cc
$From    = if ($Request.Body.From) { $Request.Body.From } else { $env:MailFromAddress }

if (-not $To -or -not $Subject -or -not $Body) {
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::BadRequest
        Body       = @{ error = "Request body must include 'To', 'Subject', and 'Body'." } | ConvertTo-Json
    })
    return
}

if (-not $From) {
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::InternalServerError
        Body       = @{ error = "No sender configured. Set the 'MailFromAddress' app setting, or pass 'From' in the request body." } | ConvertTo-Json
    })
    return
}

function ConvertTo-RecipientArray {
    param([Parameter(Mandatory)] $Addresses)
    $list = if ($Addresses -is [array]) { $Addresses } else { $Addresses -split '[;,]' }
    $recipients = @($list | ForEach-Object { @{ emailAddress = @{ address = $_.Trim() } } })
    # Unary comma forces PowerShell to return the array as a single object,
    # preventing it from being unrolled to a bare hashtable when Count -eq 1.
    return ,$recipients
}

# Helper: Invoke-RestMethod throws away the response body on non-2xx status
# codes unless you dig it out of the exception yourself. Wrap it once here
# so every caller gets the real error text instead of just "400 Bad Request".
function Invoke-RestMethodWithBody {
    param(
        [Parameter(Mandatory)] [string] $Method,
        [Parameter(Mandatory)] [string] $Uri,
        $Headers,
        $Body,
        $ContentType
    )
    try {
        $params = @{ Method = $Method; Uri = $Uri }
        if ($Headers)     { $params.Headers     = $Headers }
        if ($Body)        { $params.Body        = $Body }
        if ($ContentType) { $params.ContentType = $ContentType }
        return Invoke-RestMethod @params
    }
    catch {
        $responseBody = $null
        if ($_.ErrorDetails.Message) {
            # PowerShell 7+: already captured for you
            $responseBody = $_.ErrorDetails.Message
        }
        elseif ($_.Exception.Response) {
            # Windows PowerShell 5.1 fallback: read the stream manually
            try {
                $stream = $_.Exception.Response.GetResponseStream()
                $reader = New-Object System.IO.StreamReader($stream)
                $responseBody = $reader.ReadToEnd()
            } catch { }
        }
        $detail = if ($responseBody) { " Response body: $responseBody" } else { '' }
        throw "$($_.Exception.Message).$detail"
    }
}

try {
    # -----------------------------------------------------------------------
    # 2. Pull config from App Settings (populated via Key Vault references)
    # -----------------------------------------------------------------------
    $TenantId     = $env:GraphTenantId
    $ClientId     = $env:GraphClientId
    $ClientSecret = $env:GraphClientSecret

    if (-not $TenantId -or -not $ClientId -or -not $ClientSecret) {
        throw "Missing one or more required app settings: GraphTenantId, GraphClientId, GraphClientSecret."
    }

    # -----------------------------------------------------------------------
    # 3. Get an app-only Graph token (client credentials flow)
    # -----------------------------------------------------------------------
    $TokenBody = @{
        grant_type    = 'client_credentials'
        client_id     = $ClientId
        client_secret = $ClientSecret
        scope         = 'https://graph.microsoft.com/.default'
    }

    $TokenResponse = Invoke-RestMethodWithBody -Method Post `
        -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" `
        -Body $TokenBody -ContentType 'application/x-www-form-urlencoded'

    $AccessToken = $TokenResponse.access_token

    # -----------------------------------------------------------------------
    # 4. Build and send the message
    # -----------------------------------------------------------------------
    $Message = @{
        subject      = $Subject
        body         = @{ contentType = 'HTML'; content = $Body }
        toRecipients = ConvertTo-RecipientArray -Addresses $To
    }
    if ($Cc) {
        $Message['ccRecipients'] = ConvertTo-RecipientArray -Addresses $Cc
    }

    $MailPayload = @{
        message         = $Message
        saveToSentItems = $true
    } | ConvertTo-Json -Depth 10

    $Headers = @{
        Authorization  = "Bearer $AccessToken"
        'Content-Type' = 'application/json'
    }

    Invoke-RestMethodWithBody -Method Post `
        -Uri "https://graph.microsoft.com/v1.0/users/$From/sendMail" `
        -Headers $Headers -Body $MailPayload

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = @{ status = 'sent'; from = $From; to = $To } | ConvertTo-Json
    })
}
catch {
    Write-Error "SendMail failed: $($_.Exception.Message)"
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::InternalServerError
        Body       = @{ error = $_.Exception.Message } | ConvertTo-Json
    })
}
