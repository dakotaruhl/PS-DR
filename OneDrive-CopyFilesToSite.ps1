#Requires -Modules PnP.PowerShell

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$excludeFiles,

    [Parameter(Mandatory = $false)]
    [string]$excludeFolders = "Apps, Desktop, Attachments, ERE (old), Forms"
)

#region Configuration

$TenantId = "0bdf0e1f-a359-4b5c-9b79-9357e35ff8c6"
$ClientId = "ea2ca49b-d0df-4774-b611-86cf9dc9629f"
$CertThumbprint = "C47B91EB62634CA61FA8146DDA83B8BF605C0962"

$SourceUserUPN = "NHosseini@erock.com"

$AdminSiteUrl = "https://enchantedrock-admin.sharepoint.com"
$DestinationSiteUrl = "https://enchantedrock.sharepoint.com/sites/erintranet"
$DestinationSiteRelativeFolder = "Engineering/Nasrollah's OneDrive"

# Use server-relative path for PnP copy target
$DestinationSiteFullUrl = $DestinationSiteUrl.TrimEnd("/") + "/" + $DestinationSiteRelativeFolder.TrimStart("/")

$outputDir = Join-Path -Path $PWD -ChildPath "output"
if (-not (Test-Path -Path $outputDir)) {
    New-Item -Path $outputDir -ItemType Directory | Out-Null
}
$ReportPath = Join-Path -Path $outputDir -ChildPath "OneDriveCopyResults.csv"

# Your common automation module
$CommonModulePath = "C:\Users\DakotaRuhl\Documents\PS-DR\M365 User Offboarding Runbooks\Erock.M365.Automation.Common\Erock.M365.Automation.Common.psd1"

#endregion

$ErrorActionPreference = "Stop"

#region Module Imports

if (-not (Test-Path -Path $CommonModulePath)) {
    throw "Common module not found at: $CommonModulePath"
}

Import-Module $CommonModulePath -Force -ErrorAction Stop

#endregion

#region Functions

function Write-MigrationLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet("Info", "Warning", "Error", "Success")]
        [string]$Level = "Info"
    )

    if (Get-Command Write-Log -CommandType Function -ErrorAction SilentlyContinue) {
        Write-Log -Message $Message -Level $Level
        return
    }

    switch ($Level) {
        "Info" {
            Write-Host "[INFO] $Message"
        }
        "Success" {
            Write-Host "[SUCCESS] $Message" -ForegroundColor Green
        }
        "Warning" {
            Write-Warning $Message
        }
        "Error" {
            Write-Host "[ERROR] $Message" -ForegroundColor Red
        }
    }
}

function Add-CopyResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[object]]$Results,

        [Parameter(Mandatory)]
        [string]$Type,

        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$Source,

        [Parameter(Mandatory)]
        [string]$Target,

        [Parameter(Mandatory)]
        [ValidateSet("Copied", "Failed", "Skipped")]
        [string]$Status,

        [string]$ErrorMessage
    )

    $Results.Add([pscustomobject]@{
        Type         = $Type
        Name         = $Name
        Source       = $Source
        Target       = $Target
        Status       = $Status
        ErrorMessage = $ErrorMessage
    }) | Out-Null
}

function Connect-PnPCertificate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Url
    )

    Connect-PnPOnline `
        -Url $Url `
        -Tenant $TenantId `
        -ClientId $ClientId `
        -Thumbprint $CertThumbprint `
        -ReturnConnection
}



#endregion

$results = New-Object System.Collections.Generic.List[object]

try {
    Write-MigrationLog -Message "Connecting to SharePoint admin site..." -Level Info
    $adminConnection = Connect-PnPCertificate -Url $AdminSiteUrl

    Write-MigrationLog -Message "Resolving OneDrive URL for $SourceUserUPN..." -Level Info
    $sourceOneDrive = Get-PnPUserProfileProperty `
        -Account $SourceUserUPN `
        -Connection $adminConnection `
        -ErrorAction Stop

    if (-not $sourceOneDrive.PersonalUrl) {
        throw "No PersonalUrl returned for $SourceUserUPN. The OneDrive may not exist, or the app cannot read user profile properties."
    }

    $sourceOneDriveUrl = ($sourceOneDrive.PersonalUrl.TrimEnd("/") -replace "/Documents$", "")

    Write-MigrationLog -Message "Source OneDrive: $sourceOneDriveUrl" -Level Info

    Write-MigrationLog -Message "Connecting to source OneDrive..." -Level Info
    $sourceConnection = Connect-PnPCertificate -Url $sourceOneDriveUrl

    Write-MigrationLog -Message "Connecting to destination site..." -Level Info
    $destinationConnection = Connect-PnPCertificate -Url $DestinationSiteUrl

    Write-MigrationLog -Message "Validating destination folder: $DestinationSiteFullUrl" -Level Info
    $null = Get-PnPFolder `
        -Url $DestinationSiteFullUrl `
        -Connection $destinationConnection `
        -ErrorAction Stop


    $folders = @(
        Get-PnPFolderItem `
            -FolderSiteRelativeUrl "Documents" `
            -ItemType Folder `
            -Connection $sourceConnection `
            -ErrorAction Stop
    )

    # Exclude specified folders
    $excludeFoldersArray = $excludeFolders -split ",\s*"
    $folders = $folders | Where-Object { $excludeFoldersArray -notcontains $_.Name }

    $files = @(
        Get-PnPFolderItem `
            -FolderSiteRelativeUrl "Documents" `
            -ItemType File `
            -Connection $sourceConnection `
            -ErrorAction Stop
    )
    
    # Exclude specified files
    $excludeFilesArray = $excludeFiles -split ",\s*"
    $files = $files | Where-Object { $excludeFilesArray -notcontains $_.Name }

    Write-MigrationLog -Message "Folders found: $($folders.Count)" -Level Info
    Write-MigrationLog -Message "Files found: $($files.Count)" -Level Info

    foreach ($folder in $folders) {
        $sourceFolder = "Documents/$($folder.Name)"

        Write-MigrationLog -Message "Copying folder: $($folder.Name)" -Level Info

        try {
            Copy-PnPFolder `
                -SourceUrl $sourceFolder `
                -TargetUrl $DestinationSiteFullUrl `
                -Overwrite `
                -Force `
                -Connection $sourceConnection `
                -ErrorAction Stop

            Add-CopyResult `
                -Results $results `
                -Type "Folder" `
                -Name $folder.Name `
                -Source $sourceFolder `
                -Target $DestinationSiteFullUrl `
                -Status "Copied"

            Write-MigrationLog -Message "Copied folder: $($folder.Name)" -Level Success
        }
        catch {
            $copyError = $_.Exception.Message

            Add-CopyResult `
                -Results $results `
                -Type "Folder" `
                -Name $folder.Name `
                -Source $sourceFolder `
                -Target $DestinationSiteFullUrl `
                -Status "Failed" `
                -ErrorMessage $copyError

            Write-MigrationLog -Message "Failed copying folder '$($folder.Name)': $copyError" -Level Warning
        }
    }

    foreach ($file in $files) {
        $sourceFile = "Documents/$($file.Name)"

        Write-MigrationLog -Message "Copying file: $($file.Name)" -Level Info

        try {
            Copy-PnPFile `
                -SourceUrl $sourceFile `
                -TargetUrl $DestinationSiteFullUrl `
                -Overwrite `
                -Force `
                -Connection $sourceConnection `
                -ErrorAction Stop

            Add-CopyResult `
                -Results $results `
                -Type "File" `
                -Name $file.Name `
                -Source $sourceFile `
                -Target $DestinationSiteFullUrl `
                -Status "Copied"

            Write-MigrationLog -Message "Copied file: $($file.Name)" -Level Success
        }
        catch {
            $copyError = $_.Exception.Message

            Add-CopyResult `
                -Results $results `
                -Type "File" `
                -Name $file.Name `
                -Source $sourceFile `
                -Target $DestinationSiteFullUrl `
                -Status "Failed" `
                -ErrorMessage $copyError

            Write-MigrationLog -Message "Failed copying file '$($file.Name)': $copyError" -Level Warning
        }
    }

    $results | Export-Csv -Path $ReportPath -NoTypeInformation -Encoding UTF8

    $successCount = @($results | Where-Object { $_.Status -eq "Copied" }).Count
    $failureCount = @($results | Where-Object { $_.Status -eq "Failed" }).Count

    Write-MigrationLog -Message "Migration completed." -Level Success
    Write-MigrationLog -Message "Successful items: $successCount" -Level Info
    Write-MigrationLog -Message "Failed items: $failureCount" -Level Info
    Write-MigrationLog -Message "Report path: $ReportPath" -Level Info
}
catch {
    Write-MigrationLog -Message "Migration failed. $($_.Exception.Message)" -Level Error
    throw
}
