<#
.SYNOPSIS
  Builds and applies device name: <MODEL3><SERIAL7>-<UserTag4>
  Example: INS4567895-DRuh

.NOTES
  Run in SYSTEM context (Win32 app during ESP recommended).
  For UserTag4 we try:
    1) Autopilot artifact -> UPN
    2) Graph lookup UPN -> displayName
    3) fallback: derive from UPN if displayName unavailable
#>

#region ====== CONFIG (Graph App) ======
$TenantId     = "<YOUR_TENANT_ID>"
$ClientId     = "<YOUR_CLIENT_ID>"

# Prefer certificate auth. If using a secret instead, set $ClientSecret and switch token function.
$CertThumbprint = "<CERT_THUMBPRINT_IN_LOCALMACHINE_MY>"
# $ClientSecret = "<CLIENT_SECRET>"  # (Not recommended)
#endregion =================================

#region ====== Helpers ======
function Get-DeviceModelPrefix {
    $model = (Get-CimInstance -ClassName Win32_ComputerSystem).Model
    if (-not $model) { $model = "UNK" }

    # Keep letters only, then take first 3
    $letters = ($model -replace '[^A-Za-z]', '')
    if ($letters.Length -lt 3) { $letters = ($letters + "XXX").Substring(0,3) }

    return $letters.Substring(0,3).ToUpperInvariant()
}

function Get-SerialSuffix {
    $serial = (Get-CimInstance -ClassName Win32_BIOS).SerialNumber
    if (-not $serial) { $serial = "0000000" }

    # Keep alphanumerics, use last 7
    $clean = ($serial -replace '[^A-Za-z0-9]', '')
    if ($clean.Length -lt 7) { $clean = ("0000000" + $clean) }
    return $clean.Substring($clean.Length - 7, 7).ToUpperInvariant()
}

function Get-AutopilotUpn {
    $paths = @(
        "C:\ProgramData\Microsoft\Provisioning\Autopilot\AutopilotDDSZTDFile.json",
        "C:\Windows\Provisioning\Autopilot\AutopilotDDSZTDFile.json"
    )

    foreach ($p in $paths) {
        if (Test-Path $p) {
            try {
                $raw = Get-Content -Path $p -Raw -ErrorAction Stop
                $json = $raw | ConvertFrom-Json -ErrorAction Stop

                # Common key names (varies by scenario/build)
                $candidateKeys = @(
                    "CloudAssignedUserPrincipalName",
                    "CloudAssignedUserUpn",
                    "AssignedUserPrincipalName",
                    "UserPrincipalName",
                    "UPN"
                )

                foreach ($k in $candidateKeys) {
                    if ($json.PSObject.Properties.Name -contains $k) {
                        $val = $json.$k
                        if ($val -match '^[^@\s]+@[^@\s]+\.[^@\s]+$') { return $val }
                    }
                }

                # Fallback: scan the JSON text for an email-like string
                $m = [regex]::Match($raw, '([A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,})')
                if ($m.Success) { return $m.Groups[1].Value }
            } catch {
                # ignore and keep trying
            }
        }
    }

    return $null
}

function Get-GraphTokenWithCert {
    param(
        [Parameter(Mandatory)] [string] $TenantId,
        [Parameter(Mandatory)] [string] $ClientId,
        [Parameter(Mandatory)] [string] $Thumbprint
    )

    $cert = Get-Item "Cert:\LocalMachine\My\$Thumbprint" -ErrorAction Stop

    # Build client assertion JWT (minimal implementation)
    $now = [DateTimeOffset]::UtcNow
    $aud = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"

    $header = @{
        alg = "RS256"
        typ = "JWT"
        x5t = [System.Convert]::ToBase64String($cert.GetCertHash()) -replace '\+','-' -replace '/','_' -replace '='
    } | ConvertTo-Json -Compress

    $payload = @{
        aud = $aud
        exp = [int]$now.AddMinutes(10).ToUnixTimeSeconds()
        iss = $ClientId
        jti = [guid]::NewGuid().ToString()
        nbf = [int]$now.AddMinutes(-1).ToUnixTimeSeconds()
        sub = $ClientId
    } | ConvertTo-Json -Compress

    function To-Base64Url([string]$s) {
        [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($s)) -replace '\+','-' -replace '/','_' -replace '='
    }

    $unsigned = (To-Base64Url $header) + "." + (To-Base64Url $payload)

    $rsa = $cert.GetRSAPrivateKey()
    $sigBytes = $rsa.SignData([Text.Encoding]::UTF8.GetBytes($unsigned), [Security.Cryptography.HashAlgorithmName]::SHA256, [Security.Cryptography.RSASignaturePadding]::Pkcs1)
    $sig = ([Convert]::ToBase64String($sigBytes) -replace '\+','-' -replace '/','_' -replace '=')

    $clientAssertion = "$unsigned.$sig"

    $body = @{
        client_id             = $ClientId
        scope                 = "https://graph.microsoft.com/.default"
        grant_type            = "client_credentials"
        client_assertion_type = "urn:ietf:params:oauth:client-assertion-type:jwt-bearer"
        client_assertion      = $clientAssertion
    }

    $tokenResponse = Invoke-RestMethod -Method Post -Uri $aud -Body $body -ContentType "application/x-www-form-urlencoded"
    return $tokenResponse.access_token
}

function Get-UserDisplayNameFromGraph {
    param(
        [Parameter(Mandatory)] [string] $Upn,
        [Parameter(Mandatory)] [string] $AccessToken
    )

    $uri = "https://graph.microsoft.com/v1.0/users/$Upn`?\$select=displayName"
    $headers = @{ Authorization = "Bearer $AccessToken" }

    try {
        $resp = Invoke-RestMethod -Method Get -Uri $uri -Headers $headers
        return $resp.displayName
    } catch {
        return $null
    }
}

function Get-UserTagFromDisplayName {
    param([Parameter(Mandatory)] [string] $DisplayName)

    # Split on spaces; first token = first name, last token = last name
    $parts = $DisplayName.Trim() -split '\s+' | Where-Object { $_ }
    if ($parts.Count -lt 2) { return $null }

    $first = $parts[0]
    $last  = $parts[$parts.Count - 1]

    $fi = $first.Substring(0,1).ToUpperInvariant()

    # last name: 1st upper + next 2 lower
    $lastClean = ($last -replace '[^A-Za-z]', '')
    if ($lastClean.Length -lt 3) { $lastClean = ($lastClean + "xxx").Substring(0,3) }

    $tag = $fi +
           $lastClean.Substring(0,1).ToUpperInvariant() +
           $lastClean.Substring(1,2).ToLowerInvariant()

    return $tag
}

function Get-UserTagFallbackFromUpn {
    param([Parameter(Mandatory)] [string] $Upn)

    # If we only have UPN, do best-effort:
    # first initial = first char of alias
    # last portion after dot becomes last name candidate
    $alias = $Upn.Split('@')[0]
    $chunks = $alias -split '\.'
    if ($chunks.Count -ge 2) {
        $first = $chunks[0]
        $last  = $chunks[$chunks.Count - 1]
        $dn = "$first $last"
        return Get-UserTagFromDisplayName -DisplayName $dn
    }

    return $null
}

function Test-NameValid {
    param([Parameter(Mandatory)] [string] $Name)

    if ($Name.Length -gt 15) { return $false }
    if ($Name -notmatch '^[A-Za-z][A-Za-z0-9-]{0,14}$') { return $false }
    if ($Name -match '^[0-9]+$') { return $false }
    return $true
}
#endregion =================================

#region ====== Build Name ======
$model3  = Get-DeviceModelPrefix
$serial7 = Get-SerialSuffix

$upn = Get-AutopilotUpn

$userTag = $null
if ($upn) {
    try {
        $token = Get-GraphTokenWithCert -TenantId $TenantId -ClientId $ClientId -Thumbprint $CertThumbprint
        if ($token) {
            $dn = Get-UserDisplayNameFromGraph -Upn $upn -AccessToken $token
            if ($dn) { $userTag = Get-UserTagFromDisplayName -DisplayName $dn }
        }
    } catch {}

    if (-not $userTag) {
        $userTag = Get-UserTagFallbackFromUpn -Upn $upn
    }
}

if (-not $userTag) { $userTag = "UNKn" }  # final fallback (still 4 chars)

$newName = "$model3$serial7-$userTag"
#endregion =================================

#region ====== Apply Rename ======
Write-Output "Model prefix : $model3"
Write-Output "Serial suffix: $serial7"
Write-Output "UPN found    : $upn"
Write-Output "User tag     : $userTag"
Write-Output "New name     : $newName"

if (-not (Test-NameValid -Name $newName)) {
    Write-Error "Generated name is invalid for NetBIOS/computer naming: $newName"
    exit 1
}

$current = $env:COMPUTERNAME
if ($current -ieq $newName) {
    Write-Output "Computer name already set. No action."
    exit 0
}

Rename-Computer -NewName $newName -Force

# Mark completion for Win32 detection
New-Item -Path "HKLM:\SOFTWARE\EnchantedRock" -Force | Out-Null
New-ItemProperty -Path "HKLM:\SOFTWARE\EnchantedRock" -Name "AutopilotRename" -Value $newName -PropertyType String -Force | Out-Null

# Request reboot (IME/Win32 can treat 3010 as soft reboot)
Write-Output "Rename applied. Reboot required."
exit 3010
#endregion =================================


#Win32 Package Notes
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Rename-AutopilotDevice.ps1