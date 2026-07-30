function Initialize-RunbookLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CorrelationId,

        [Parameter(Mandatory)]
        [string]$RunbookName,

        [Parameter(Mandatory)]
        [string]$UserPrincipalName
    )

    $script:RunbookLog = [System.Collections.Generic.List[object]]::new()
    $script:RunbookName = $RunbookName
    $script:CorrelationId = $CorrelationId
    $script:LogUserPrincipalName = $UserPrincipalName
}

function Write-RunbookLog {
    [CmdletBinding()]
    param(
        [ValidateSet("INFO", "SUCCESS", "WARNING", "ERROR", "WHATIF")]
        [string]$Level = "INFO",

        [Parameter(Mandatory)]
        [string]$Message,

        [string]$StepName,

        [string]$Target,

        [string]$ErrorMessage
    )

    if (-not $script:RunbookLog) {
        $script:RunbookLog = [System.Collections.Generic.List[object]]::new()
    }

    $Entry = [PSCustomObject]@{
        Timestamp         = (Get-Date).ToString("o")
        CorrelationId     = $script:CorrelationId
        RunbookName       = $script:RunbookName
        UserPrincipalName = $script:LogUserPrincipalName
        StepName          = $StepName
        Level             = $Level
        Target            = $Target
        Message           = $Message
        ErrorMessage      = $ErrorMessage
    }

    $script:RunbookLog.Add($Entry)

    $Text = "[{0}] [{1}] [{2}] {3}" -f $Entry.Timestamp, $Level, $StepName, $Message

    switch ($Level) {
        "ERROR"   { Write-Error $Text -ErrorAction Continue }
        "WARNING" { Write-Warning $Text }
        default   { Write-Output $Text }
    }
}

function Get-RunbookLog {
    [CmdletBinding()]
    param()

    if (-not $script:RunbookLog) {
        return @()
    }

    return $script:RunbookLog
}

function Get-GraphSafePathSegment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Value
    )

    return ($Value -replace '[\\/:*?"<>|#%{}~&]', '_')
}

function Publish-RunbookLogToSharePoint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$LogSiteHostName,

        [Parameter(Mandatory)]
        [string]$LogSitePath,

        [Parameter(Mandatory)]
        [string]$LogLibraryName,

        [Parameter(Mandatory)]
        [string]$LogFolderPath
    )

    if (-not $script:RunbookLog -or $script:RunbookLog.Count -eq 0) {
        Write-Output "No log entries to publish."
        return
    }

    try {
        $SafeUser = Get-GraphSafePathSegment -Value $script:LogUserPrincipalName
        $SafeRunbook = Get-GraphSafePathSegment -Value $script:RunbookName
        $Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"

        $BaseFileName = "{0}_{1}_{2}_{3}" -f $Timestamp, $SafeUser, $SafeRunbook, $script:CorrelationId

        $JsonPath = Join-Path $env:TEMP "$BaseFileName.json"
        $CsvPath  = Join-Path $env:TEMP "$BaseFileName.csv"

        $script:RunbookLog |
            ConvertTo-Json -Depth 10 |
            Set-Content -Path $JsonPath -Encoding UTF8

        $script:RunbookLog |
            Export-Csv -Path $CsvPath -NoTypeInformation -Encoding UTF8

        $SiteLookupId = "{0}:{1}" -f $LogSiteHostName, $LogSitePath
        $Site = Get-MgSite `
            -SiteId $SiteLookupId

        $Drives = Get-MgSiteDrive -SiteId $Site.Id -ErrorAction Stop
        $Drive = $Drives | Where-Object { $_.Name -eq $LogLibraryName } | Select-Object -First 1

        if (-not $Drive) {
            throw "Could not find document library [$LogLibraryName] on site [$LogSiteHostName$LogSitePath]."
        }

        foreach ($FilePath in @($JsonPath, $CsvPath)) {
            $FileName = Split-Path $FilePath -Leaf
            $UploadPath = "$LogFolderPath/$FileName"
            $Bytes = [System.IO.File]::ReadAllBytes($FilePath)

            Invoke-MgGraphRequest `
                -Method PUT `
                -Uri "https://graph.microsoft.com/v1.0/drives/$($Drive.Id)/root:/$($UploadPath):/content" `
                -Body $Bytes `
                -ContentType "application/octet-stream" `
                -ErrorAction Stop

            Write-Output "Uploaded log file [$UploadPath] to SharePoint."
        }
    }
    catch {
        Write-Warning "Failed to upload runbook log to SharePoint. $($_.Exception.Message)"
        throw
    }
}

function Assert-OffboardingTargetIsAllowed {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$UserPrincipalName,

        [string[]]$BlockedPatterns = @(
            "breakglass",
            "admin",
            "svc",
            "service"
        )
    )

    foreach ($Pattern in $BlockedPatterns) {
        if ($UserPrincipalName -match $Pattern) {
            throw "Blocked offboarding target [$UserPrincipalName]. Matched protected pattern [$Pattern]."
        }
    }
}

Export-ModuleMember `
    -Function Initialize-RunbookLog,
              Write-RunbookLog,
              Get-RunbookLog,
              Publish-RunbookLogToSharePoint,
              Get-GraphSafePathSegment,
              Assert-OffboardingTargetIsAllowed