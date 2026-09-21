NDe#l$0IB4*4!NCRD5z7

$oneDriveExe = "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDrive.exe"
$runKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"

# Ensure OneDrive auto-starts
if (Test-Path $oneDriveExe) {
    Set-ItemProperty -Path $runKey -Name "OneDrive" -Value "`"$oneDriveExe`" /background"
}

# Start OneDrive if not running
if (-not (Get-Process OneDrive -ErrorAction SilentlyContinue)) {
    Start-Process $oneDriveExe -ArgumentList "/background"
}

## Task at logon and every 10 mins ##
Get-Process OneDrive -ErrorAction SilentlyContinue | Out-Null
if (-not $?) {
    Start-Process "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDrive.exe" -ArgumentList "/background"
}



$watchPath = "C:\TestDrops\Outbound"
$fsw = New-Object System.IO.FileSystemWatcher $watchPath, "*.*"
$fsw.IncludeSubdirectories = $false
$fsw.EnableRaisingEvents = $true

Register-ObjectEvent $fsw Created -Action {
    $path = $Event.SourceEventArgs.FullPath

    # wait for file to be released (stable size)
    $stable = $false
    $lastSize = -1
    for ($i=0; $i -lt 60 -and -not $stable; $i++) {
        Start-Sleep -Seconds 1
        try {
            $size = (Get-Item $path -ErrorAction Stop).Length
            if ($size -eq $lastSize -and $size -gt 0) { $stable = $true }
            $lastSize = $size
        } catch { }
    }

    if ($stable) {
        # enqueue upload (in production: write to a queue file or concurrent queue)
        # Upload-FileToSharePoint -Path $path
    }
}

## Watcher Idea ## 
<# 
  App has Application permission: Sites.Selected
  Admin consent granted
  App granted Write to site erintranet (Sites.Selected assignment)
  Certificate added to the app (public key) 


  The matching certificate (private key) installed in LocalMachine\My
  PowerShell 5.1+ (works in Windows PowerShell; also fine in PS7) 
#>

## Upload Script ## 
<#
.SYNOPSIS
  Upload files to SharePoint library folder using Microsoft Graph (app-only + certificate),
  using resumable upload sessions, then archive locally. Optional real-time watch mode.

.DESCRIPTION
  Target:
    Site:  https://enchantedrock.sharepoint.com/sites/erintranet
    Drive: Titan
    Folder: Test/Final FAT

  Auth:
    App-only (client credentials) using certificate thumbprint from LocalMachine\My

.NOTES
  - Requires Sites.Selected + site write grant for the app on /sites/erintranet
  - Upload session URLs are pre-authenticated; no Authorization header needed for chunk PUTs
#>

[CmdletBinding()]
param(
  # Entra ID tenant ID (GUID)
  [Parameter(Mandatory)]
  [string]$TenantId,

  # App (client) ID (GUID)
  [Parameter(Mandatory)]
  [string]$ClientId,

  # Thumbprint of cert with private key in LocalMachine\My
  [Parameter(Mandatory)]
  [string]$CertThumbprint,

  # SharePoint host + site path
  [string]$SiteHostname = "enchantedrock.sharepoint.com",
  [string]$SitePath     = "/sites/erintranet",

  # Drive (document library) name
  [string]$DriveName    = "Titan",

  # Folder path inside the drive (no leading slash)
  [string]$TargetFolder = "Test/Final FAT",

  # Local paths
  [string]$OutboundPath = "C:\TitanFAT2\Outbound",
  [string]$UploadingPath= "C:\TitanFAT2\Uploading",
  [string]$ArchivedPath = "C:\TitanFAT2\Archived",
  [string]$FailedPath   = "C:\TitanFAT2\Failed",
  [string]$LogPath      = "C:\TitanFAT2\Logs\uploader.log",

  # Chunk size in MB for upload sessions (5-10MB is typical)
  [ValidateRange(1,60)]
  [int]$ChunkSizeMB = 10,

  # If set, watch OutboundPath and upload in real time
  [switch]$Watch
)

# ---------------------------
# Helpers
# ---------------------------

function Write-Log {
  param([string]$Message, [string]$Level = "INFO")
  $ts = (Get-Date).ToString("s")
  $line = "[$ts][$Level] $Message"
  Write-Host $line
  New-Item -ItemType Directory -Force -Path (Split-Path $LogPath) | Out-Null
  Add-Content -Path $LogPath -Value $line
}

function Ensure-Folders {
  foreach ($p in @($OutboundPath,$UploadingPath,$ArchivedPath,$FailedPath,(Split-Path $LogPath))) {
    New-Item -ItemType Directory -Force -Path $p | Out-Null
  }
}

function Get-Certificate {
  param([string]$Thumbprint)
  $tp = $Thumbprint -replace '\s',''
  $cert = Get-Item "Cert:\LocalMachine\My\$tp" -ErrorAction SilentlyContinue
  if (-not $cert) { throw "Certificate with thumbprint $tp not found in Cert:\LocalMachine\My" }
  if (-not $cert.HasPrivateKey) { throw "Certificate $tp does not have a private key." }
  return $cert
}

function New-ClientAssertionJwt {
  <#
    Creates a client assertion JWT signed by certificate for OAuth2 client_credentials.
    This avoids requiring external modules.
  #>
  param(
    [Parameter(Mandatory)][System.Security.Cryptography.X509Certificates.X509Certificate2]$Cert,
    [Parameter(Mandatory)][string]$TenantId,
    [Parameter(Mandatory)][string]$ClientId
  )

  # JWT parts are base64url-encoded JSON.
  function To-Base64Url([byte[]]$bytes) {
    [Convert]::ToBase64String($bytes).TrimEnd('=') -replace '\+','-' -replace '/','_'
  }

  $now = [DateTimeOffset]::UtcNow
  $nbf = [int]$now.ToUnixTimeSeconds()
  $exp = [int]$now.AddMinutes(10).ToUnixTimeSeconds()
  $jti = [guid]::NewGuid().ToString()

  # x5t = base64url(SHA1(derCert))
  $sha1 = [System.Security.Cryptography.SHA1]::Create()
  $x5t = To-Base64Url($sha1.ComputeHash($Cert.RawData))

  $header = @{
    alg = "RS256"
    typ = "JWT"
    x5t = $x5t
  } | ConvertTo-Json -Compress

  $aud = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"

  $payload = @{
    aud = $aud
    iss = $ClientId
    sub = $ClientId
    jti = $jti
    nbf = $nbf
    exp = $exp
  } | ConvertTo-Json -Compress

  $headerB64  = To-Base64Url([Text.Encoding]::UTF8.GetBytes($header))
  $payloadB64 = To-Base64Url([Text.Encoding]::UTF8.GetBytes($payload))
  $toSign = "$headerB64.$payloadB64"

  $rsa = $Cert.GetRSAPrivateKey()
  $sig = $rsa.SignData([Text.Encoding]::UTF8.GetBytes($toSign),
                       [System.Security.Cryptography.HashAlgorithmName]::SHA256,
                       [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)

  $sigB64 = To-Base64Url($sig)
  return "$toSign.$sigB64"
}

function Get-GraphToken {
  param(
    [Parameter(Mandatory)][string]$TenantId,
    [Parameter(Mandatory)][string]$ClientId,
    [Parameter(Mandatory)][System.Security.Cryptography.X509Certificates.X509Certificate2]$Cert
  )

  $assertion = New-ClientAssertionJwt -Cert $Cert -TenantId $TenantId -ClientId $ClientId

  $body = @{
    client_id             = $ClientId
    scope                 = "https://graph.microsoft.com/.default"
    grant_type            = "client_credentials"
    client_assertion_type = "urn:ietf:params:oauth:client-assertion-type:jwt-bearer"
    client_assertion      = $assertion
  }

  $tokenUri = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"
  $resp = Invoke-RestMethod -Method POST -Uri $tokenUri -Body $body -ContentType "application/x-www-form-urlencoded"
  return $resp.access_token
}

function Invoke-Graph {
  param(
    [Parameter(Mandatory)][string]$Method,
    [Parameter(Mandatory)][string]$Uri,
    [Parameter(Mandatory)][string]$Token,
    $Body = $null,
    [hashtable]$Headers = $null
  )

  $h = @{ Authorization = "Bearer $Token" }
  if ($Headers) { $Headers.Keys | ForEach-Object { $h[$_] = $Headers[$_] } }

  if ($null -ne $Body) {
    $json = ($Body | ConvertTo-Json -Depth 10 -Compress)
    return Invoke-RestMethod -Method $Method -Uri $Uri -Headers $h -Body $json -ContentType "application/json"
  } else {
    return Invoke-RestMethod -Method $Method -Uri $Uri -Headers $h
  }
}

function Encode-GraphPath {
  # Encode each segment but keep slashes
  param([Parameter(Mandatory)][string]$Path)
  ($Path -split "/") | ForEach-Object { [System.Uri]::EscapeDataString($_) } | Join-String -Separator "/"
}

function Wait-FileStable {
  param(
    [Parameter(Mandatory)][string]$Path,
    [int]$MaxSeconds = 60
  )
  $last = -1
  for ($i=0; $i -lt $MaxSeconds; $i++) {
    Start-Sleep -Seconds 1
    try {
      $size = (Get-Item $Path -ErrorAction Stop).Length
      if ($size -gt 0 -and $size -eq $last) { return $true }
      $last = $size
    } catch {
      # File might still be moving/locked; keep waiting
    }
  }
  return $false
}

# ---------------------------
# Graph resolution
# ---------------------------

function Resolve-SiteId {
  param([string]$Token)

  $uri = "https://graph.microsoft.com/v1.0/sites/$SiteHostname:`$SitePath"
  $site = Invoke-Graph -Method GET -Uri $uri -Token $Token
  return $site.id
}

function Resolve-DriveId {
  param([string]$Token, [string]$SiteId)

  $uri = "https://graph.microsoft.com/v1.0/sites/$SiteId/drives"
  $drives = Invoke-Graph -Method GET -Uri $uri -Token $Token
  $drive = $drives.value | Where-Object { $_.name -eq $DriveName } | Select-Object -First 1
  if (-not $drive) { throw "Drive/library '$DriveName' not found on site." }
  return $drive.id
}

# ---------------------------
# Upload (resumable session)
# ---------------------------

function New-UploadSession {
  param(
    [Parameter(Mandatory)][string]$Token,
    [Parameter(Mandatory)][string]$DriveId,
    [Parameter(Mandatory)][string]$RemotePathEncoded
  )

  $uri = "https://graph.microsoft.com/v1.0/drives/$DriveId/root:/$RemotePathEncoded:/createUploadSession"
  $body = @{
    item = @{
      "@microsoft.graph.conflictBehavior" = "rename"
    }
  }

  $session = Invoke-Graph -Method POST -Uri $uri -Token $Token -Body $body
  if (-not $session.uploadUrl) { throw "Upload session did not return uploadUrl." }
  return $session.uploadUrl
}

function Send-UploadChunks {
  param(
    [Parameter(Mandatory)][string]$UploadUrl,
    [Parameter(Mandatory)][string]$FilePath,
    [Parameter(Mandatory)][int]$ChunkSizeBytes
  )

  $fileInfo = Get-Item $FilePath -ErrorAction Stop
  $fileSize = [int64]$fileInfo.Length

  $fs = [System.IO.File]::Open($FilePath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
  try {
    $buffer = New-Object byte[] $ChunkSizeBytes
    $position = 0

    while ($position -lt $fileSize) {
      $remaining = $fileSize - $position
      $readSize = [int][Math]::Min($ChunkSizeBytes, $remaining)

      $bytesRead = $fs.Read($buffer, 0, $readSize)
      if ($bytesRead -le 0) { break }

      $start = $position
      $end   = $position + $bytesRead - 1

      $headers = @{
        "Content-Length" = "$bytesRead"
        "Content-Range"  = "bytes $start-$end/$fileSize"
      }

      # Important: Use Invoke-WebRequest for uploadUrl (absolute URL). No auth header needed.
      $chunk = if ($bytesRead -eq $buffer.Length) { $buffer } else { $buffer[0..($bytesRead-1)] }

      $resp = Invoke-WebRequest -Method PUT -Uri $UploadUrl -Headers $headers -Body $chunk -ErrorAction Stop

      # 202 = still uploading, 201/200 = complete
      if ($resp.StatusCode -in 200,201) {
        return $true
      }

      $position += $bytesRead
    }
  }
  finally {
    $fs.Close()
  }

  # If we got here, upload didn't complete cleanly
  return $false
}

function Upload-ToSharePoint {
  param(
    [Parameter(Mandatory)][string]$Token,
    [Parameter(Mandatory)][string]$DriveId,
    [Parameter(Mandatory)][string]$FilePath
  )

  $fileName = [System.IO.Path]::GetFileName($FilePath)

  # Remote path: TargetFolder + filename
  $remotePath = "$TargetFolder/$fileName"
  $remotePathEncoded = Encode-GraphPath -Path $remotePath

  Write-Log "Creating upload session for '$remotePath'..."
  $uploadUrl = New-UploadSession -Token $Token -DriveId $DriveId -RemotePathEncoded $remotePathEncoded

  $chunkBytes = $ChunkSizeMB * 1MB
  Write-Log "Uploading '$fileName' in $ChunkSizeMB MB chunks..."
  $ok = Send-UploadChunks -UploadUrl $uploadUrl -FilePath $FilePath -ChunkSizeBytes $chunkBytes

  if (-not $ok) { throw "Upload did not complete successfully for $fileName." }

  Write-Log "Upload complete: $fileName"
}

# ---------------------------
# Main processing
# ---------------------------

function Process-OutboundOnce {
  param(
    [Parameter(Mandatory)][string]$Token,
    [Parameter(Mandatory)][string]$DriveId
  )

  $files = Get-ChildItem -Path $OutboundPath -File -ErrorAction SilentlyContinue
  foreach ($f in $files) {
    $src = $f.FullName
    $name = $f.Name

    Write-Log "Detected file: $name"

    if (-not (Wait-FileStable -Path $src -MaxSeconds 120)) {
      Write-Log "File not stable after waiting; skipping for now: $name" "WARN"
      continue
    }

    $moveTo = Join-Path $UploadingPath $name
    try {
      Move-Item -Path $src -Destination $moveTo -Force
      Upload-ToSharePoint -Token $Token -DriveId $DriveId -FilePath $moveTo

      $archiveTo = Join-Path $ArchivedPath $name
      Move-Item -Path $moveTo -Destination $archiveTo -Force
      Write-Log "Archived locally: $archiveTo"
    }
    catch {
      Write-Log "FAILED upload for $name : $($_.Exception.Message)" "ERROR"
      try {
        $failTo = Join-Path $FailedPath $name
        Move-Item -Path $moveTo -Destination $failTo -Force -ErrorAction SilentlyContinue
      } catch {}
    }
  }
}

# ---------------------------
# Run
# ---------------------------

Ensure-Folders

Write-Log "Starting Titan FAT2 uploader..."
$cert = Get-Certificate -Thumbprint $CertThumbprint
$token = Get-GraphToken -TenantId $TenantId -ClientId $ClientId -Cert $cert

Write-Log "Resolving site and drive..."
$siteId  = Resolve-SiteId -Token $token
$driveId = Resolve-DriveId -Token $token -SiteId $siteId
Write-Log "Resolved: siteId=$siteId, driveId=$driveId"

# Initial pass (catch anything already in Outbound)
Process-OutboundOnce -Token $token -DriveId $driveId

if ($Watch) {
  Write-Log "Watch mode enabled. Monitoring: $OutboundPath"

  $fsw = New-Object System.IO.FileSystemWatcher $OutboundPath
  $fsw.IncludeSubdirectories = $false
  $fsw.EnableRaisingEvents = $true

  Register-ObjectEvent $fsw Created -SourceIdentifier TitanFAT2Created -Action {
    # Re-acquire token if needed (simple approach: just reuse; for long runs you can refresh periodically)
    try {
      Process-OutboundOnce -Token $using:token -DriveId $using:driveId
    } catch {
      Write-Log "Watcher processing error: $($_.Exception.Message)" "ERROR"
    }
  } | Out-Null

  # Keep script alive
  while ($true) { Start-Sleep -Seconds 5 }
}

Write-Log "Done."

## Sample Graph queries for testing auth and permissions (interactive vs non-interactive) ##

$watchPath = "C:\TitanFAT2\Outbound"
$uploading = "C:\TitanFAT2\Uploading"
$archived  = "C:\TitanFAT2\Archived"

$fsw = New-Object System.IO.FileSystemWatcher $watchPath
$fsw.EnableRaisingEvents = $true
$fsw.IncludeSubdirectories = $false

Register-ObjectEvent $fsw Created -Action {
    $src = $Event.SourceEventArgs.FullPath
    $name = [System.IO.Path]::GetFileName($src)

    # Wait for file to be stable
    $last = -1
    do {
        Start-Sleep 1
        try { $size = (Get-Item $src).Length } catch { return }
    } while ($size -ne $last -and ($last = $size))

    $dest = Join-Path $uploading $name
    Move-Item $src $dest -Force

    try {
        Upload-ToSharePoint -FilePath $dest
        Move-Item $dest (Join-Path $archived $name)
    }
    catch {
        Write-Error $_
    }
}

<# 
powershell.exe -ExecutionPolicy Bypass -File "C:\Program Files\TitanFAT2\TitanFAT2-Uploader.ps1" -TenantId ... -ClientId ... -CertThumbprint ... -Watch 
#>