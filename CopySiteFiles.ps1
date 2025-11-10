# Connect to SharePoint Online
$TenantAdminURL = "https://enchantedrock-admin.sharepoint.com/"
Connect-PnPOnline -Url $TenantAdminURL -Interactive -ClientId 4ac6eede-e81e-4d22-abad-0d43c51486f2 

#Get files from Target Site and Folder
$targetSiteUrl = "https://enchantedrock.sharepoint.com/sites/erintranet"
$TargetFolder = "/EPC/ERE/00 ERE Projects"
$reportPath = "C:\Users\DakotaRuhl\Documents\Reports\ProjectManagement"
Connect-PnPOnline -Url $targetSiteUrl -Interactive -ClientId 4ac6eede-e81e-4d22-abad-0d43c51486f2
#$EREFilesList = Get-PnPFolderInFolder -FolderSiteRelativeUrl $TargetFolder | Get-PnPFileInFolder -Recurse -ExcludeSystemFolders | Where-Object {$_.Name -notlike "*.aspx" -and $_.Name -notlike "*.dotx" }

#Get sites collections to check files against
#$SearchTerm = "HEB"
#$SitesCollections = Get-PnPTenantSite | Where-Object {$_.Template -eq "GROUP#0" -and $_.Url -like "*$SearchTerm*"}
$SitesCollections = Get-PnPTenantSite | Where-Object {$_.URL -eq "https://enchantedrock.sharepoint.com/sites/GN1-HEB7-0798-TX"}

$siteCollectionsResults = @()

#Initialize collections to store found and missing files
$missingFilesCollection = @()
$foundFilesCollection = @()

foreach ($Site in $SitesCollections) 
{
    #Get batch number if it exists
    $SiteName = $Site.Url.Split("/")[-1]
    $split = $SiteName.Split("-")
    $batchNumber = $split[1]

    #Set target folder to check for files
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
        if ($batchNumber -match "\d$")  #Create in OnePlan Sites/BatchNumber/SiteName
        {
            $DestFolder = "EPC/ERE/00 ERE Projects/OnePlan Sites/$batchNumber/$SiteName"
            Write-Host -foregroundcolor Green "Found Batch Number: $batchNumber"
            $BatchName = $batchNumber
        }
        else 
        {
            $DestFolder = "EPC/ERE/00 ERE Projects/OnePlan Sites/Unknown Batch/$SiteName"
            Write-Host -foregroundcolor Yellow "No valid batch number found. Adding to unknown batch."
            $BatchName = "Unknown Batch"
        }
        $updatedReportPath = Join-Path -Path $reportPath -ChildPath $BatchName -AdditionalChildPath $SiteName
        # Check if folder exists
        if (-not (Test-Path -Path $updatedReportPath)) 
        {
            New-Item -Path $updatedReportPath -ItemType Directory
            Write-Host "Folder created at: $updatedReportPath"
        } 
        else 
        {
            Write-Host "Folder already exists at: $updatedReportPath"
        }
        $foundFilesCollection | Export-Csv -Path "$updatedReportPath\FilesFoundReport.csv" -NoTypeInformation
        $siteCollectionsResults += [PSCustomObject]@{
                    SiteCollection = $Site.Url
                    AllFilesFound  = "True"
                }
        
        continue
    }

    #loop didn't exit early, so we have missing files to copy. Report site as not all files found.
    $siteCollectionsResults += [PSCustomObject]@{
                SiteCollection = $Site.Url
                AllFilesFound  = "False"
            }
    #Check batch number ends with a number
    if ($batchNumber -match "\d$")  #Create in OnePlan Sites/BatchNumber/SiteName
    {
        $DestFolder = "EPC/ERE/00 ERE Projects/OnePlan Sites/$batchNumber"
        Write-Host -foregroundcolor Green "Found Batch Number: $batchNumber"
        #Update report path
        $updatedReportPath = Join-Path -Path $reportPath -ChildPath $batchNumber -AdditionalChildPath $SiteName
        #Check if folder exists
        $folderExists = Get-PnPFolder -Url $DestFolder -ErrorAction SilentlyContinue
        if ($null -ne $folderExists) 
        {
            #Found Folder
            Write-Host -ForegroundColor Green "`nFolder '$DestFolder' exists in Site Collection: $($Site.Url)."
            #Check if Site Name folder exists
            $siteFolderExists = Get-PnPFolder -Url "$DestFolder/$SiteName" -ErrorAction SilentlyContinue
            if ($null -ne $siteFolderExists) {
                Write-Host -ForegroundColor Green "`nSite Name '$SiteName' exists in Folder '$DestFolder'."
            }
            else {
                Write-Host -ForegroundColor Red "`nSite Name '$SiteName' does NOT exist in Folder '$DestFolder'. Creating folder."
                Add-PnPFolder -Name $SiteName -Folder $DestFolder
            }
            #Copy Files to target folder
            foreach ($MissingFile in $MissingFilesCollection) 
            {
                Write-Host -ForegroundColor Cyan "Copying File '$($MissingFile.FileName)' to ERE Library Folder '$DestFolder'."
                Copy-PnPFile -SourceUrl $MissingFile.FileURL -TargetUrl "$DestFolder/$SiteName"
            }
        }
        else 
        {
            Write-Host -ForegroundColor Red "`nFolder '$DestFolder' does NOT exist. Creating folder for found batch number."
            Add-PnPFolder -Name $batchNumber -Folder "EPC/ERE/00 ERE Projects/OnePlan Sites"
            Add-PnPFolder -Name $SiteName -Folder $DestFolder
            #Copy Files to target folder
            foreach ($MissingFile in $MissingFilesCollection) 
            {
                Write-Host -ForegroundColor Cyan "Copying File '$($MissingFile.FileName)' to ERE Library Folder '$DestFolder'. "
                Copy-PnPFile -SourceUrl $MissingFile.FileURL -TargetUrl "$DestFolder/$SiteName"
            }
        }
    }
    else #Create in OnePlan/SiteName if no valid batch number found
    {
        Write-Host -ForegroundColor Red "`nNo valid batch number found. Adding to unknown batch."
        $DestFolder = "EPC/ERE/00 ERE Projects/OnePlan Sites/Unknown Batch/"
        $folderExists = Get-PnPFolder -Url "$DestFolder/$SiteName" -ErrorAction SilentlyContinue
        $updatedReportPath = Join-Path -Path $reportPath -ChildPath "Unknown Batch" -AdditionalChildPath $SiteName
        if ($null -ne $folderExists) 
        {
            #Found Folder
            Write-Host -ForegroundColor Green "`nFolder '$DestFolder' exists."
            #Copy Files to target folder
            foreach ($MissingFile in $MissingFilesCollection) 
            {
                Write-Host -ForegroundColor Cyan "Copying File '$($MissingFile.FileName)' to ERE Library Folder '$DestFolder'."
                Copy-PnPFile -SourceUrl $MissingFile.FileURL -TargetUrl "$DestFolder/$SiteName"
            }
        }
        else 
        {
            Write-Host -ForegroundColor Red "`nFolder '$DestFolder' does NOT exist. Creating folder in OnePlan Sites."
            Add-PnPFolder -Name $SiteName -Folder $DestFolder
            #Copy Files to target folder
            foreach ($MissingFile in $MissingFilesCollection) 
            {
                Write-Host -ForegroundColor Cyan "Copying File '$($MissingFile.FileName)' to ERE Library Folder '$DestFolder'."
                Copy-PnPFile -SourceUrl $MissingFile.FileURL -TargetUrl "$DestFolder/$SiteName"
            }
        }
    }
#Export found and missing files to CSV


if (-not (Test-Path -Path $updatedReportPath)) 
{
    New-Item -Path $updatedReportPath -ItemType Directory
    Write-Host "Folder created at: $updatedReportPath"
} 
else 
{
    Write-Host "Folder already exists at: $updatedReportPath"
}

$foundFilesCollection | Export-Csv -Path "$updatedReportPath\FilesFoundReport.csv" -NoTypeInformation      
$missingFilesCollection | Export-Csv -Path "$updatedReportPath\FilesMissingReport.csv" -NoTypeInformation
$siteCollectionsResults | Export-Csv -Path "$updatedReportPath\SiteCollectionsFilesCheckReport.csv" -NoTypeInformation
Add-PnPFile -Path "$updatedReportPath\FilesMissingReport.csv" -Folder "$DestFolder/$SiteName"
Add-PnPFile -Path "$updatedReportPath\FilesFoundReport.csv" -Folder "$DestFolder/$SiteName"
}

