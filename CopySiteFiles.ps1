Import-Module ImportExcel
$filePath = "C:\Users\DakotaRuhl\Documents\Reports\GroupsCreatedByApp\Plans with TeamsURL.xlsx"
$columnName = "ItemUrl"
$excelData = Import-Excel -Path $filePath
$columnValues = $excelData | Select-Object -ExpandProperty $columnName

# Connect to SharePoint Online
$TenantAdminURL = "https://enchantedrock-admin.sharepoint.com/"
Connect-PnPOnline -Url $TenantAdminURL -Interactive -ClientId 4ac6eede-e81e-4d22-abad-0d43c51486f2 

#Get files from Target Site and Folder
$targetSiteUrl = "https://enchantedrock.sharepoint.com/sites/erintranet"
$TargetFolder = "/EPC/ERE/00 ERE Projects"
Connect-PnPOnline -Url $targetSiteUrl -Interactive -ClientId 4ac6eede-e81e-4d22-abad-0d43c51486f2
$EREFilesList = Get-PnPFolderInFolder -FolderSiteRelativeUrl $TargetFolder | Get-PnPFileInFolder -Recurse -ExcludeSystemFolders | Where-Object {$_.Name -notlike "*.aspx" -and $_.Name -notlike "*.dotx" }

#Set base report path
$reportPath = "C:\Users\DakotaRuhl\Documents\Reports\ProjectManagement"

#Testing
#Get sites collections to check files against
#$SearchTerm = "HEB"
#$SitesCollections = Get-PnPTenantSite | Where-Object {$_.Template -eq "GROUP#0" -and $_.Url -like "*$SearchTerm*"}





$SitesCollections = @()
foreach ($item in $columnValues) 
{
    $startIndex = $item.IndexOf("groupId=") + 8
    $endIndex = $item.IndexOf("&tenantId")
    $length = $endIndex - $startIndex
    $groupdId = $item.Substring($startIndex, $length)

    try {
        $SitesCollections += Get-PnPTenantSite | Where-Object {$_.RelatedGroupID -eq $groupdId} -ErrorAction Stop
    }
    catch {
        Write-Host -ForegroundColor Red "Site for $groupdId not found. Skipping."
    }
}

$siteCollectionsResults = @()

#Initialize collections to store found and missing files
$missingFilesCollection = @()
$foundFilesCollection = @()

foreach ($Site in $SitesCollections) 
{
    ##Just getting names of folders here to create report paths
    #Get batch number if it exists
    $SiteName = $Site.Url.Split("/")[-1]
    $split = $SiteName.Split("-")
    $batchNumber = $split[1]

    if ($SiteName -contains "HEB")
    {
        $topFolder = "HEB"
    }
    elseif ($SiteName -contains "Wal" -and ($SiteName -notcontains "HEB" -or $SiteName -notcontains "Bucee"))
    {
        $topFolder = "Walmart"
    }
    else 
    {
        $topFolder = "Other"
    }

    #Is a number, Set destination to OnePlan Sites/TopFolder/BatchNumber/SiteName
    if ($batchNumber -match "\d$")  
    {
        $BatchName = $batchNumber
        $DestFolder = "EPC/ERE/00 ERE Projects/OnePlan Sites/$topFolder/$BatchName/$SiteName"
        Write-Host -foregroundcolor Green "$SiteName - Found Batch Number: $batchNumber, Destination Folder set to: $DestFolder"
            
    }
    #Is not a number, Set destination to OnePlan Sites/TopFolder/Unknown Batch/SiteName
    else         
    {
        $BatchName = "Unknown Batch"
        $DestFolder = "EPC/ERE/00 ERE Projects/OnePlan Sites/$topFolder/$BatchName/$SiteName"
        Write-Host -foregroundcolor Yellow "$SiteName - No valid batch number found. Destination Folder set to: $DestFolder"
    }    

    $updatedReportPath = Join-Path -Path $reportPath -ChildPath $topFolder -AdditionalChildPath $BatchName -AdditionalChildPath $SiteName
    $DestBatchFolder = "EPC/ERE/00 ERE Projects/OnePlan Sites/$topFolder/$BatchName"
    $DestTopFolder = "EPC/ERE/00 ERE Projects/OnePlan Sites/$topFolder"

    #Done checking paths and updating names

    #Set target folder to check for files in current site target
    $SiteLibrary = "/Shared Documents"
    Write-Host -ForegroundColor Yellow "`nProcessing Site Collection: $($Site.Url)"
    Connect-PnPOnline -Url $Site.Url -Interactive -ClientId 4ac6eede-e81e-4d22-abad-0d43c51486f2
    $FilesList = Get-PnPFolderInFolder -FolderSiteRelativeUrl $SiteLibrary | Get-PnPFileInFolder -Recurse -ExcludeSystemFolders | Where-Object {$_.Name -notlike "*.aspx" -and $_.Name -notlike "*.dotx" }
    foreach ($File in $FilesList) 
    {
        foreach ($EREFile in $EREFilesList) 
        {
            if ($File.Name -eq $EREFile.Name) 
            {
                Write-Host -ForegroundColor Green "File '$($EREFile.Name)' exists in both Site Collection '$($Site.Url)' and ERE Library."
                $foundFile = New-Object PSObject
                $foundFile | Add-Member NoteProperty FileName($EREFile.Name)
                $foundFile | Add-Member NoteProperty FileURL($EREFile.ServerRelativeUrl)
                $foundFile | Add-Member NoteProperty SiteCollection($EREFile.Url)
                $foundFilesCollection += $foundFile
                $found = $true
                break
            }
            else 
            {
                $found = $false
            }
        }
        if (-not $found) 
            {
                Write-Host -ForegroundColor Red "File '$($File.Name)' does NOT exist in ERE Library."
                $MissingFile = New-Object PSObject
                $MissingFile | Add-Member NoteProperty FileName($File.Name)
                $MissingFile | Add-Member NoteProperty FileURL($File.ServerRelativeUrl)
                $MissingFile | Add-Member NoteProperty SiteCollection($Site.Url)
                $missingFilesCollection += $MissingFile
                Write-Host -ForegroundColor Cyan "Added File '$($File.Name)' to copy list."
            }
    }

    #Connect back to Intranet site to copy files, and check if foleders exist
    Connect-PnPOnline -Url $targetSiteUrl -Interactive -ClientId 4ac6eede-e81e-4d22-abad-0d43c51486f2

    #Only copy if we have missing files 
    if ($missingFilesCollection.Count -eq 0) 
    {
        Write-Host -ForegroundColor Green "`nNo missing files to copy for Site Collection: $($Site.Url). Moving to next site."
        #Export found files to CSV
        $foundFilesCollection | Export-Csv -Path "$updatedReportPath\FilesFoundReport.csv" -NoTypeInformation
        $siteCollectionsResults += [PSCustomObject]@{
                    SiteCollection = $Site.Url
                    AllFilesFound  = "True"
                }
        
        continue
    }
    else #loop didn't exit early, so we have missing files to copy. Report site as not all files found.
    {
        $siteCollectionsResults += [PSCustomObject]@{
                    SiteCollection = $Site.Url
                    AllFilesFound  = "False"
                }
    }

    #Check what folder levels exist, create as needed
    $siteFolderExists = Get-PnPFolder -Url $DestFolder -ErrorAction SilentlyContinue
    $batchFolderExists = Get-PnPFolder -Url $DestBatchFolder -ErrorAction SilentlyContinue
    $topFolderExists = Get-PnPFolder -Url $DestTopFolder -ErrorAction SilentlyContinue

    #Full SiteName folder exists
    if ($null -ne $siteFolderExists) 
    {
        Write-Host -ForegroundColor Green "`nSite Name '$SiteName' exists in Folder '$DestBatchFolder'. Skipping copy, we must have already done this one."
    }
    #Top Folder/Batch folder exists, but not site name folder
    elseif ($null -ne $batchFolderExists)  
    {
        Write-Host -ForegroundColor Red "`nSite Name '$SiteName' does NOT exist in Folder '$DestBatchFolder', but batch folder does exist."
        Write-host -ForegroundColor Green "`nCreating Site Name folder '$SiteName' in '$DestBatchFolder'."
        Add-PnPFolder -Name $SiteName -Folder $DestBatchFolder

        #Copy Files to target folder
        foreach ($MissingFile in $MissingFilesCollection) 
        {
            Write-Host -ForegroundColor Cyan "Copying File '$($MissingFile.FileName)' to ERE Library Folder '$DestFolder'."
            Copy-PnPFile -SourceUrl $MissingFile.FileURL -TargetUrl "$DestFolder" -Force -IgnoreVersionHistory 
        }        
    }        
    #Only Top Folder exists
    elseif ($null -eq $topFolderExists)
    {
        Write-Host -ForegroundColor Red "`nFolder '$DestBatchFolder' does NOT exist in Folder '$DestTopFolder', but top folder does exist."
        Write-host -ForegroundColor Green "`nCreating Batch Folder '$batchName' in '$DestTopFolder'."
        Add-PnPFolder -Name $BatchName -Folder $DestTopFolder
        Write-host -ForegroundColor Green "`nCreating Site Name folder '$SiteName' in '$DestBatchFolder'."
        Add-PnPFolder -Name $SiteName -Folder $DestBatchFolder

        #Copy Files to target folder
        foreach ($MissingFile in $MissingFilesCollection) 
        {
            Write-Host -ForegroundColor Cyan "Copying File '$($MissingFile.FileName)' to ERE Library Folder '$DestFolder'. "
            Copy-PnPFile -SourceUrl $MissingFile.FileURL -TargetUrl "$DestFolder" -Force -IgnoreVersionHistory
        }
    }
    #No top folder exists, create all levels
    else 
    {
        Write-Host -ForegroundColor Red "`nTop Folder '$topFolder' does NOT exist."
        Write-host -ForegroundColor Green "`nCreating Top Folder '$topFolder' in 'EPC/ERE/00 ERE Projects/OnePlan Sites'."
        Add-PnPFolder -Name $topFolder -Folder "EPC/ERE/00 ERE Projects/OnePlan Sites"
        Write-host -ForegroundColor Green "`nCreating Batch Folder '$batchName' in '$DestTopFolder'."
        Add-PnPFolder -Name $BatchName -Folder $DestTopFolder
        Write-host -ForegroundColor Green "`nCreating Site Name folder '$SiteName' in '$DestBatchFolder'."
        Add-PnPFolder -Name $SiteName -Folder $DestBatchFolder

        #Copy Files to target folder
        foreach ($MissingFile in $MissingFilesCollection) 
        {
            Write-Host -ForegroundColor Cyan "Copying File '$($MissingFile.FileName)' to ERE Library Folder '$DestFolder'. "
            Copy-PnPFile -SourceUrl $MissingFile.FileURL -TargetUrl "$DestFolder" -Force -IgnoreVersionHistory
        }
    }

#Export found and missing files to CSV
if (-not (Test-Path -Path $updatedReportPath)) 
{
    New-Item -Path $updatedReportPath -ItemType Directory | Out-Null #Supress output
    Write-Host "Folder created at: $updatedReportPath"
} 
else 
{
    Write-Host "Folder already exists at: $updatedReportPath"
}

#Export found and missing files to CSV, then upload to destination folder
$foundFilesCollection | Export-Csv -Path "$updatedReportPath\FilesFoundReport.csv" -NoTypeInformation      
$missingFilesCollection | Export-Csv -Path "$updatedReportPath\FilesMissingReport.csv" -NoTypeInformation
Add-PnPFile -Path "$updatedReportPath\FilesMissingReport.csv" -Folder "$DestFolder"
Add-PnPFile -Path "$updatedReportPath\FilesFoundReport.csv" -Folder "$DestFolder"
}

#Overall report of site collections and if all files were found
$siteCollectionsResults | Export-Csv -Path "$updatedReportPath\SiteCollectionsFilesCheckReport.csv" -NoTypeInformation