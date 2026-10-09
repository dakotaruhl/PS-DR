<#
.SYNOPSIS
Copies the contents of a user's OneDrive Documents library to a specified SharePoint Online folder.

.DESCRIPTION
This script migrates the top-level contents of a user's OneDrive Documents library
to a specified destination folder in SharePoint Online.

The script performs the following actions:

- Connects to the SharePoint Online admin site using PnP.PowerShell and
  certificate-based app-only authentication.
- Resolves the source user's OneDrive URL from their user profile.
- Connects to the source OneDrive and destination SharePoint site.
- Validates that the destination folder exists.
- Retrieves top-level folders and files from the source OneDrive Documents library.
- Excludes configured folders and files from the copy operation.
- Copies folders and files to the destination SharePoint folder.
- Records the result of each copy operation.
- Exports a CSV report containing copied and failed items.

The script uses the Erock.M365.Automation.Common module for shared automation
functionality when available, including Write-Log.

.PARAMETER SourceUserUPN
The User Principal Name (UPN) of the user whose OneDrive contents will be copied.

Example:
kclothier@erock.com

.PARAMETER DestinationSiteUrl
The URL of the SharePoint Online site that will receive the copied OneDrive content.

Example:
https://enchantedrock.sharepoint.com/sites/Safety

.PARAMETER DestinationSiteRelativeFolder
The site-relative path of the destination folder within the SharePoint site.

Example:
Shared Documents/Archive/Kevin Clothier - OneDrive

.PARAMETER excludeFiles
Optional comma-separated list of top-level files that should not be copied.

Example:
desktop.ini,TemporaryFile.txt

.PARAMETER excludeFolders
Optional comma-separated list of top-level folders that should not be copied.

The default value is:
Forms

Example:
Forms,Archive,Temporary

.INPUTS
None.

This script does not accept pipeline input. Configuration is supplied through
script parameters and the configuration variables defined within the script.

.OUTPUTS
The script produces:

1. Console/log output showing:
   - Connection progress
   - Source OneDrive URL
   - Number of discovered folders and files
   - Copy progress
   - Copy failures
   - Final successful and failed item counts

2. A CSV migration report:

   .\output\OneDriveCopyResults.csv

   The report contains the following columns:

   Type
       Indicates whether the item is a File or Folder.

   Name
       Name of the source item.

   Source
       Source path within the user's OneDrive Documents library.

   Target
       Destination SharePoint folder.

   Status
       Result of the operation. Expected values are Copied, Failed, or Skipped.

   ErrorMessage
       Error returned by the copy operation when an item fails.

.NOTES
Requires:
- PnP.PowerShell
- Erock.M365.Automation.Common
- Access to the configured certificate
- An Entra ID application with the required SharePoint permissions
- Access to the SharePoint admin site, source OneDrive, and destination site

Authentication:
The script uses certificate-based PnP.PowerShell authentication with the configured
Tenant ID, Client ID, and certificate thumbprint.

Copy Scope:
Only files and folders directly within the root of the OneDrive Documents library
are enumerated. Copy-PnPFolder handles the contents of each selected folder.

Existing Content:
Copy operations use -Overwrite and -Force. Existing destination items with matching
paths or names may therefore be replaced.

Error Handling:
A failure copying an individual file or folder is recorded in the migration report
and processing continues with the remaining items. A failure during initialization,
connection, source discovery, or destination validation terminates the migration.

.EXAMPLE
.\Copy-OneDriveToSharePoint.ps1 `
    -SourceUserUPN "kclothier@erock.com" `
    -DestinationSiteUrl "https://enchantedrock.sharepoint.com/sites/Safety" `
    -DestinationSiteRelativeFolder "Shared Documents/Archive/Kevin Clothier - OneDrive"

Copies the user's OneDrive Documents content to the specified SharePoint archive folder.

.EXAMPLE
.\Copy-OneDriveToSharePoint.ps1 `
    -SourceUserUPN "kclothier@erock.com" `
    -DestinationSiteUrl "https://enchantedrock.sharepoint.com/sites/Safety" `
    -DestinationSiteRelativeFolder "Shared Documents/Archive/Kevin Clothier - OneDrive" `
    -excludeFolders "Forms,Temporary" `
    -excludeFiles "desktop.ini,test.txt"

Performs the migration while excluding the specified top-level files and folders.
#>

#Requires -Modules PnP.PowerShell


#Requires -Modules PnP.PowerShell

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$excludeFiles,

    [Parameter(Mandatory = $false)]
    [string]$excludeFolders = "Forms",

    [Parameter(Mandatory = $true)]
    [string]$SourceUserUPN,

    [Parameter(Mandatory = $true)]
    [string]$DestinationSiteUrl,

    [Parameter(Mandatory = $true)]
    [string]$DestinationSiteRelativeFolder
)

#region Configuration

$TenantId = $env:AZURE_TENANT_ID
$ClientId = $env:AZURE_CLIENT_ID
$CertThumbprint = $env:AZURE_CLIENT_CERTIFICATE_THUMBPRINT
$AdminSiteUrl = "https://enchantedrock-admin.sharepoint.com"

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
