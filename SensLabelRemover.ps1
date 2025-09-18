#Requires -Modules Microsoft.Graph.Files
#Requires -Modules Microsoft.Graph.Applications
#Requires -Modules Microsoft.Graph.Identity.DirectoryManagement
#Requires -Modules Microsoft.Graph.Beta.Security
#Requires -Modules Microsoft.Graph.Authentication
#Requires -Modules Microsoft.Graph.Users
#Requires -Modules Microsoft.Graph.Security
#Requires -Modules Microsoft.Graph.Sites

# Report-SPOFilesDocumentLibrary.PS1
# Updated: Iterate all drives automatically and only include files with valid Sensitivity labels (excluding "No label" and "General")

Param (
    [Parameter(Mandatory = $true)]
    [string]$SiteName # Name of the SharePoint Online site to process
)

function Get-DriveItems {
    [CmdletBinding()]
    param (
        [Parameter()] $Drive,
        [Parameter()] $FolderId
    )

    # Get data for a folder and its children
    [array]$Data = Get-MgDriveItemChild -DriveId $Drive -DriveItemId $FolderId -All

    # Split the data into files and folders
    [array]$Folders = $Data | Where-Object { $_.folder.childcount -gt 0 } | Sort-Object Name
    $Global:TotalFolders = $TotalFolders + $Folders.Count
    [array]$Files = $Data | Where-Object { $null -ne $_.file.mimetype }

    # Process the files
    foreach ($File in $Files) {
        $SensitivityLabelName = $null
        $RetentionLabelName = $null

        if ($SensitivityLabelsAvailable -eq $true) {
            $FileType = $File.Name.Split(".")[1]
            if ($FileType -in $ValidFileTypes) {
                $Uri = ("https://graph.microsoft.com/beta/sites/{0}/drive/items/{1}/extractSensitivityLabels" -f $Site.Id, $File.id)
                try {
                    [array]$SensitivityLabelInfo = Invoke-MgGraphRequest -Uri $Uri -Method POST
                    if ($SensitivityLabelInfo.labels.sensitivityLabelId) {
                        [array]$LabelName = $SensitivityLabelsHash[$SensitivityLabelInfo.labels.sensitivityLabelId]
                    }
                }
                catch {
                    Write-Host ("Error reading sensitivity label data from file {0}" -f $File.Name)
                    [array]$LabelName = "Error"
                }
            }
        }

        # Resolve sensitivity label
        if ([string]::IsNullOrEmpty($LabelName)) {
            $SensitivityLabelName = "No label"
        }
        else {
            [string]$SensitivityLabelName = $LabelName[0].Trim()
        }

        # Skip excluded labels early
        if ($SensitivityLabelName -eq "No label" -or $SensitivityLabelName -eq "General") {
            continue
        }

        # Get retention label information
        if ($RetentionLabelsAvailable -eq $true) {
            try {
                $Uri = ("https://graph.microsoft.com/v1.0/drives/{0}/items/{1}/retentionLabel" -f $Drive, $File.Id)
                [array]$RetentionLabelInfo = Invoke-MgGraphRequest -Uri $Uri -Method Get
                $RetentionLabelName = $RetentionLabelInfo.name
            }
            catch {
                Write-Host ("Error reading retention label data from file {0}" -f $File.Name)
            }
        }

        if ([string]::IsNullOrEmpty($RetentionLabelName)) {
            $RetentionLabelName = "No label"
        }
        else {
            $RetentionLabelName = $RetentionLabelName.Trim()
        }

        if ($File.LastModifiedDateTime) {
            $LastModifiedDateTime = Get-Date $File.LastModifiedDateTime -format 'dd-MMM-yyyy HH:mm'
        }
        else {
            $LastModifiedDateTime = $null
        }

        if ($File.CreatedDateTime) {
            $FileCreatedDateTime = Get-Date $File.CreatedDateTime -format 'dd-MMM-yyyy HH:mm'
        }

        # Build report line
        $ReportLine = [PSCustomObject]@{
            FileName         = $File.Name
            Folder           = $File.parentreference.name
            Size             = (FormatFileSize $File.Size)
            Created          = $FileCreatedDateTime
            Author           = $File.CreatedBy.User.DisplayName
            LastModified     = $LastModifiedDateTime
            'Last modified by' = $File.LastModifiedBy.User.DisplayName
            'Sensitivity label' = $SensitivityLabelName
            'Retention label'   = $RetentionLabelName
            WebURL           = $File.WebUrl
            DriveID          = $Drive
            FileID           = $File.Id
        }

        $ReportData.Add($ReportLine)
    }

    # Process the folders recursively
    foreach ($Folder in $Folders) {
        Write-Host ("Processing folder {0} ({1} files/size {2})" -f $Folder.Name, $Folder.folder.childcount, (FormatFileSize $Folder.Size))
        Get-DriveItems -Drive $Drive -FolderId $Folder.Id
    }
}

function FormatFileSize {
    param ([parameter(Mandatory = $true)] $InFileSize)
    if ($InFileSize -lt 1KB) {
        $FileSize = $InFileSize.ToString() + " B"
    }
    elseif ($InFileSize -lt 1MB) {
        $FileSize = $InFileSize / 1KB
        $FileSize = ("{0:n2}" -f $FileSize) + " KB"
    }
    elseif ($InFileSize -lt 1GB) {
        $FileSize = $InFileSize / 1MB
        $FileSize = ("{0:n2}" -f $FileSize) + " MB"
    }
    elseif ($InFileSize -ge 1GB) {
        $FileSize = $InFileSize / 1GB
        $FileSize = ("{0:n2}" -f $FileSize) + " GB"
    }
    return $FileSize
}

# Disconnect from any previous Graph SDK session
Disconnect-MgGraph

# Connect to the Microsoft Graph
Connect-MgGraph -Scopes "Sites.Read.All", "InformationProtectionPolicy.Read", "RecordsManagement.Read.All" -NoWelcome

Write-Host "Setting up for the SharePoint Online site files report..."

# Discover if the tenant uses sensitivity labels
$Account = (Get-MgContext).Account
[array]$SensitivityLabels = Get-MgBetaUserSecurityInformationProtectionSensitivityLabel -UserId $Account
if ($SensitivityLabels) {
    $Global:SensitivityLabelsAvailable = $true
    [array]$Global:ValidfileTypes = "docx", "pptx", "xlsx", "pdf"
    $Global:SensitivityLabelsHash = @{}
    foreach ($Label in $SensitivityLabels) {
        $SensitivityLabelsHash.Add($Label.Id, $Label.Name)
    }
}
else {
    $Global:SensitivityLabelsAvailable = $false
}

# Discover if the tenant uses retention labels
[array]$RetentionLabels = Get-MgSecurityLabelRetentionLabel
if ($RetentionLabels) {
    $Global:RetentionLabelsAvailable = $true
}
else {
    $Global:RetentionLabelsAvailable = $false
}

Import-Module Microsoft.Graph.Authentication
Import-Module Microsoft.Graph.Groups

# Find the site
Write-Host "Looking for matching sites..."
[array]$Sites = Get-MgSite -Search ($SiteName)
if (!($Sites)) {
    Write-Host "No matching sites found - exiting"
    break
}
if ($Sites.Count -eq 1) {
    $Global:Site = $Sites[0]
    $SiteName = $Site.DisplayName
    Write-Host "Found site to process:" $SiteName
}
elseif ($Sites.Count -gt 1) {
    Clear-Host
    [int]$i = 1
    Write-Host "More than one matching site was found. We need you to select a site to report."
    foreach ($SiteOption in $Sites) {
        Write-Host ("{0}: {1} ({2})" -f $i, $SiteOption.DisplayName, $SiteOption.Name)
        $i++
    }
    [Int]$Answer = Read-Host "Enter the number of the site to use"
    if (($Answer -gt 0) -and ($Answer -le $i)) {
        [int]$Si = ($Answer-1)
        $SiteName = $Sites[$Si].DisplayName
        Write-Host ("OK. Selected site is {0}" -f $Sites[$Si].DisplayName)
        $Global:Site = $Sites[$Si]
    }
}

if (!($Site)) {
    Write-Host ("Can't find the {0} site - script exiting" -f $Uri)
    break
}

# Find ALL document libraries (drives) in the site
[array]$Drives = Get-MgSiteDrive -SiteId $Site.Id
if (!($Drives)) {
    Write-Host "No document libraries found in the site" -ForegroundColor Red
    Break
}

[datetime]$StartProcessing = Get-Date
$Global:TotalFolders = 1
$Global:ReportData = [System.Collections.Generic.List[Object]]::new()

<# Process ALL drives for a given site
Write-Host "Processing all drives in site $SiteName..."
foreach ($Drive in $Drives) {
    $DriveName = $Drive.Name
    Write-Host "Fetching file information from drive:" $DriveName
    Get-DriveItems -Drive $Drive.Id -FolderId "root"
}
#>

# Only process a single drive as selected by the user instead of all drives
Write-Host "Select a document library to process:"
[int]$i = 1
foreach ($DriveOption in $Drives) {
    Write-Host ("{0}: {1}" -f $i, $DriveOption.Name)
    $i++
}
[Int]$Answer = Read-Host "Enter the number of the document library to use"
if (($Answer -gt 0) -and ($Answer -le $i)) {
    [int]$Si = ($Answer-1)
    $DriveName = $Drives[$Si].Name
    Write-Host ("OK. Selected document library is {0}" -f $Drives[$Si].Name)
    $DriveId = $Drives[$Si].Id
    Write-Host "Fetching file information from drive:" $DriveName
    #Get-DriveItems -Drive $DriveId -FolderId "root"
}
else {
    Write-Host "Invalid selection - exiting"
    Break
}

[datetime]$EndProcessing = Get-Date
$ElapsedTime = ($EndProcessing - $StartProcessing)
$FilesPerMinute = [math]::Round(($ReportData.Count / ($ElapsedTime.TotalSeconds / 60)), 2)

Write-Host ""
Write-Host ("Processed {0} files in {1} folders in {2}:{3} minutes ({4} files/minute)" -f $ReportData.Count, $TotalFolders, $ElapsedTime.Minutes, $ElapsedTime.Seconds, $FilesPerMinute)
Write-Host ""

Write-Host "Retention Labels in Use"
$ReportData | Group-Object 'Retention label' -NoElement | Sort-Object Count -Descending | Format-Table Name, Count
Write-Host ""

Write-Host "Sensitivity Labels in Use"
$ReportData | Group-Object 'Sensitivity label' -NoElement | Sort-Object Count -Descending | Format-Table Name, Count

# Save CSV report
$CSVOutputFile = ((New-Object -ComObject Shell.Application).Namespace('shell:Downloads').Self.Path) + ("\Files {0} site report.csv" -f $Site.displayName)
$ReportData | Export-Csv -Path $CSVOutputFile -NoTypeInformation -Encoding UTF8
Write-Host ("Report data saved to {0}" -f $CSVOutputFile)

Write-Host "Done."