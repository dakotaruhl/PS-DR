<#
This script copies files from various OnePlan SharePoint Site Collections ($SitesCollections) into a central ERE Projects SharePoint Library.
It checks for missing files in the target library and copies them over, organizing them into folders based on site names and batch numbers.
It also generates reports on found and missing files for each site collection processed. Once all files are copied, it then locks the site collection to Read-Only access.
#>

Start-Transcript -Path "C:\Users\DakotaRuhl\Documents\ProjectManagement\CopySiteFiles_Transcript_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt" -Append 

# Set up Excel module and read in file 
# Import-Module ImportExcel
# $filePath = "C:\Users\DakotaRuhl\Documents\Reports\GroupsCreatedByApp\Plans with TeamsURL.xlsx"
# $Worksheet = "Sheet2"
# $columnName = "UniqueGroupsWithExclusions"
# $excelData = Import-Excel -Path $filePath -WorksheetName $Worksheet
# $columnValues = $excelData | Select-Object -ExpandProperty $columnName

# Connect to SharePoint Online
$TenantAdminURL = "https://enchantedrock-admin.sharepoint.com/"
Connect-PnPOnline -Url $TenantAdminURL -Interactive -ClientId 4ac6eede-e81e-4d22-abad-0d43c51486f2 

#Get files from Target Site and Folder
$targetSiteUrl = "https://enchantedrock.sharepoint.com/sites/erintranet"
#$TargetFolder = "/EPC/ERE/00 ERE Projects"
Connect-PnPOnline -Url $targetSiteUrl -Interactive -ClientId 4ac6eede-e81e-4d22-abad-0d43c51486f2
#Write-Host -ForegroundColor Yellow "`nConnected to Target Site: $targetSiteUrl`nGetting all files from Target Folder: $TargetFolder"
#$EREFilesList = Get-PnPFolderInFolder -FolderSiteRelativeUrl $TargetFolder | Get-PnPFileInFolder -Recurse -ExcludeSystemFolders | Where-Object {$_.Name -notlike "*.aspx" -and $_.Name -notlike "*.dotx" }

#Set base report path
$reportPath = "C:\Users\DakotaRuhl\Documents\ProjectManagement"

#Testing
#Get sites collections to check files against
#$SearchTerm = "HEB"
#$SitesCollections = Get-PnPTenantSite | Where-Object {$_.Template -eq "GROUP#0" -and $_.Url -like "*$SearchTerm*"}

# $testCollections = @()
# $testSite = $SitesCollections[34]
# $testCollections += $testSite

# $j = 0
# while ($j -lt 4) 
# {
#     Write-Output -ForegroundColor Yellow "Adding test site collection number $j" 
#     $testSite = $SitesCollections[$j]
#     $testCollections += $testSite
#     $j++
# } 
 
# $SitesCollections = @()
# foreach ($item in $columnValues) 
# {
#     try 
#     {
#         $CurrentSite = Get-PnPTenantSite | Where-Object {$_.RelatedGroupID -eq $item} -ErrorAction Stop
#         $SitesCollections += $CurrentSite
#         Write-Host -ForegroundColor Green "Added Site Collection for GroupID: $item, and Site URL: $($CurrentSite.Url)"
#     }
#     catch 
#     {
#         Write-Host -ForegroundColor Red "Site for $item not found. Skipping."
#     }
# }

#Initialize collections to store found and missing files, and overall report
$siteCollectionsResults = @()
$s = 0
foreach ($Site in $SitesCollections) 
{
    $s++
    Write-Host -foregroundcolor Magenta "`nProcessing Site Collection number $s of $($SitesCollections.Count)"
    $missingFilesCollection = @()
    $foundFilesCollection = @()
    
    ##Just getting names of folders here to create report paths
    #Get batch number if it exists
    $SiteName = $Site.Url.Split("/")[-1]
    $split = $SiteName.Split("-")
    $batchNumber = $split[1] #Second element should be batch number "ABC-HEB7-EFGHIJ.."

    if ($SiteName -like "*HEB*")
    {
        $topFolder = "HEB"
        #Is a number, Set destination to OnePlan Sites/TopFolder/BatchNumber/SiteName
        if ($batchNumber -match "\d$") #Ends with a digit 0-9 "HEB7"
        {
            $BatchName = $batchNumber
            $DestFolder = "EPC/ERE/00 ERE Projects/OnePlan Sites/$topFolder/$BatchName/$SiteName"
            Write-Host -foregroundcolor Yellow "$SiteName - HEB Site - FOUND Batch Number: $batchNumber, Destination Folder set to: $DestFolder"
        }
        else 
        {
            $BatchName = "Unknown Batch"
            $DestFolder = "EPC/ERE/00 ERE Projects/OnePlan Sites/$topFolder/$BatchName/$SiteName"
            Write-Host -foregroundcolor Yellow "$SiteName - HEB Site - UNKNOWN Batch Number, Destination Folder set to: $DestFolder"
        }
        $DestBatchFolder = "EPC/ERE/00 ERE Projects/OnePlan Sites/$topFolder/$BatchName"
        $updatedReportPath = Join-Path -Path $reportPath -ChildPath $topFolder -AdditionalChildPath "$BatchName/$SiteName"
    }
    elseif ($SiteName -like "*Wal*" -and ($SiteName -notlike "*HEB*" -or $SiteName -notlike "*Bucee*"))
    {
        $topFolder = "Walmart"
        $DestFolder = "EPC/ERE/00 ERE Projects/OnePlan Sites/$topFolder/$SiteName"
        Write-Host -foregroundcolor Yellow "$SiteName - WALMART Site - Destination Folder set to: $DestFolder"
        $updatedReportPath = Join-Path -Path $reportPath -ChildPath $topFolder -AdditionalChildPath $SiteName
    }
    else 
    {
        $topFolder = "Other"
        $DestFolder = "EPC/ERE/00 ERE Projects/OnePlan Sites/$topFolder/$SiteName"
        Write-Host -foregroundcolor Yellow "$SiteName - OTHER Site - Destination Folder set to: $DestFolder"
        $updatedReportPath = Join-Path -Path $reportPath -ChildPath $topFolder -AdditionalChildPath $SiteName
    }
    $DestTopFolder = "EPC/ERE/00 ERE Projects/OnePlan Sites/$topFolder"

    #Done checking paths and updating names

    #Set target folder to check for files in current site target
    $SiteLibrary = "/Shared Documents"
    Connect-PnPOnline -Url $Site.Url -Interactive -ClientId 4ac6eede-e81e-4d22-abad-0d43c51486f2
    $FilesList = Get-PnPFolderInFolder -FolderSiteRelativeUrl $SiteLibrary | Get-PnPFileInFolder -Recurse -ExcludeSystemFolders | Where-Object {$_.Name -notlike "*.aspx" -and $_.Name -notlike "*.dotx" }
    $i = 0
    foreach ($File in $FilesList) 
    {
        $i++

        Write-Host -ForegroundColor Cyan "`nChecking File number $i of $($FilesList.Count)"
        foreach ($EREFile in $EREFilesList) 
        {   
            if ($File.Name -eq $EREFile.Name) 
            {
                Write-Host -ForegroundColor Green "File '$($EREFile.Name)' exists in both Site Collection '$($Site.Url)' and ERE Library."
                $foundFile = New-Object PSObject
                $foundFile | Add-Member NoteProperty FileName($EREFile.Name)
                $foundFile | Add-Member NoteProperty FileURL($EREFile.ServerRelativeUrl)
                $foundFile | Add-Member NoteProperty Created($EREFile.TimeCreated)
                $foundFile | Add-Member NoteProperty Modified($EREFile.TimeLastModified)
                $foundFile | Add-Member NoteProperty SourceFilePath($Site.Url + $File.ServerRelativeUrl)
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
                $MissingFile | Add-Member NoteProperty Created($File.TimeCreated)
                $MissingFile | Add-Member NoteProperty Modified($File.TimeLastModified)
                $missingFilesCollection += $MissingFile
            }
    }

    #Connect back to Intranet site to copy files, and check if folders exist
    Connect-PnPOnline -Url $targetSiteUrl -Interactive -ClientId 4ac6eede-e81e-4d22-abad-0d43c51486f2

    #Update sitecollectionresults based on found/missing files 
    if ($missingFilesCollection.Count -eq 0 -and $foundFilesCollection.count -gt 0) 
    {
        Write-Host -ForegroundColor Yellow "`nAll Files in Site Collection: $($Site.Url) exist in ERE Library"
        #Export found files to CSV
        $siteCollectionsResults += [PSCustomObject]@{
                    SiteCollection = $Site.Url
                    AllFilesFound  = "True"
                }
    }
    #If no files found in either collection, lock site and skip to next site
    elseif($missingFilesCollection.count -eq 0 -and $foundFilesCollection.count -eq 0) 
    {
        Write-Host -ForegroundColor Yellow "`nNo files found in Site Collection: $($Site.Url). Skipping to next site."
        #Set-PnPTenantSite -Url $Site.Url -LockState "ReadOnly"
        #Write-Host -ForegroundColor Yellow "`nSite Collection '$($Site.Url)' has been locked to Read-Only access after file copy completed."
        $siteCollectionsResults += [PSCustomObject]@{
                    SiteCollection = $Site.Url
                    AllFilesFound  = "Empty Site"
                }

        continue
    }
    else #We have missing files to copy. Report site as not all files found.
    {
        $siteCollectionsResults += [PSCustomObject]@{
                    SiteCollection = $Site.Url
                    AllFilesFound  = "False"
                }
    }

    
    
<#
    #Check what folder levels exist, create as needed
    $siteFolderExists = Get-PnPFolder -Url $DestFolder -ErrorAction SilentlyContinue
    if ($SiteName -like "*HEB*")
    {
        $batchFolderExists = Get-PnPFolder -Url $DestBatchFolder -ErrorAction SilentlyContinue
    }
    else 
    {
        $batchFolderExists = $null
    }
    $topFolderExists = Get-PnPFolder -Url $DestTopFolder -ErrorAction SilentlyContinue

    #Full SiteName folder exists
    if ($null -ne $siteFolderExists) 
    {
        Write-Host -ForegroundColor Green "`nSite Name '$SiteName' folder already exists at $DestFolder. We must have already done this one."
    }
    #Top Folder/Batch folder exists, but not site name folder - only HEB sites will have possibility for non-null value here
    if ($null -ne $batchFolderExists -and ($null -eq $siteFolderExists))  
    {
        Write-Host -ForegroundColor Red "`nSite Name '$SiteName' folder does NOT exist in '$DestBatchFolder', but batch folder does exist."
        Write-host -ForegroundColor Green "Creating Site Name folder '$SiteName' in '$DestBatchFolder'."
        Add-PnPFolder -Name $SiteName -Folder $DestBatchFolder | Out-Null #Supress output
    }        
    #Only Top Folder exists, need seperate cases for HEB and non-HEB sites
    if (($SiteName -like "*HEB*") -and (($null -ne $topFolderExists) -and ($null -eq $batchFolderExists))) 
    {
        Write-Host -ForegroundColor Red "`nFolder '$DestBatchFolder' does NOT exist in Folder '$DestTopFolder', but top folder does exist."
        Write-host -ForegroundColor Green "Creating Batch Folder '$batchName' in '$DestTopFolder'."
        Add-PnPFolder -Name $BatchName -Folder $DestTopFolder | Out-Null #Supress output
        Write-host -ForegroundColor Green "Creating Site Name folder '$SiteName' in '$DestBatchFolder'."
        Add-PnPFolder -Name $SiteName -Folder $DestBatchFolder | Out-Null #Supress output
    }
    elseif (($SiteName -notlike "*HEB*") -and (($null -ne $topFolderExists) -and ($null -eq $siteFolderExists)))
    {
        Write-Host -ForegroundColor Red "`nSite Name '$SiteName' folder does NOT exist in '$DestTopFolder', but top folder does exist."
        Write-host -ForegroundColor Green "Creating Site Name folder '$SiteName' in '$DestTopFolder'."
        Add-PnPFolder -Name $SiteName -Folder $DestTopFolder | Out-Null #Supress output 
    }

     #No top folder exists, create all levels
    elseif ($null -eq $topFolderExists) 
    {
        Write-Host -ForegroundColor Red "`nTop Folder '$topFolder' does NOT exist."
        Write-host -ForegroundColor Green "Creating Top Folder '$topFolder' in 'EPC/ERE/00 ERE Projects/OnePlan Sites'."
        Add-PnPFolder -Name $topFolder -Folder "EPC/ERE/00 ERE Projects/OnePlan Sites" | Out-Null #Supress output
        #Create batch and site folders as needed
        if ($SiteName -like "*HEB*" -and $null -eq $batchFolderExists)
        {
            Write-host -ForegroundColor Green "Creating Batch Folder '$batchName' in '$DestTopFolder'."
            Add-PnPFolder -Name $BatchName -Folder $DestTopFolder | Out-Null #Supress output
            Write-host -ForegroundColor Green "Creating Site Name folder '$SiteName' in '$DestBatchFolder'."
            Add-PnPFolder -Name $SiteName -Folder $DestBatchFolder | Out-Null #Supress output
        }
        else
        {
            Write-host -ForegroundColor Green "Creating Site Name folder '$SiteName' in '$DestTopFolder'."
            Add-PnPFolder -Name $SiteName -Folder $DestTopFolder | Out-Null #Supress output
        } 
        
    }

    #Create duplicates folder if we have found files to copy there
    if ($foundFilesCollection.Count -gt 0) 
    {
        $duplicatesFolderExists = Get-PnPFolder -Url "$DestFolder\duplicates" -ErrorAction SilentlyContinue
        if ($null -eq $duplicatesFolderExists)
        {
            Write-Host -ForegroundColor Green "Creating 'duplicates' folder in '$DestFolder'. `n"
            Add-PnPFolder -Name "duplicates" -Folder $DestFolder | Out-Null #Supress output
        }
    }

    #Copy Files to target folder
    foreach ($MissingFile in $MissingFilesCollection) 
    {
        Write-Host -ForegroundColor Cyan "Copying Missing File '$($MissingFile.FileName)' to ERE Library Folder '$DestFolder'."
        Copy-PnPFile -SourceUrl $MissingFile.FileURL -TargetUrl "$DestFolder" -Force -IgnoreVersionHistory -Overwrite
    }      
    foreach ($foundFile in $foundFilesCollection) 
    {
        Write-Host -ForegroundColor Cyan "Copying Found File '$($foundFile.FileName)' to ERE Library Folder '$DestFolder/duplicates'."
        Write-Host -ForegroundColor Cyan "Source File Path: $($foundFile.SourceFilePath)"
        Copy-PnPFile -SourceUrl $foundFile.FileURL -TargetUrl "$DestFolder/duplicates" -Force -IgnoreVersionHistory -Overwrite
    }

    #Export found and missing files to CSV
    if (-not (Test-Path -Path $updatedReportPath)) 
    {
        New-Item -Path $updatedReportPath -ItemType Directory | Out-Null #Supress output
        Write-Host -ForegroundColor Green "`nFolder created at: $updatedReportPath"
    } 
    else 
    {
        Write-Host -ForegroundColor Yellow "`nFolder already exists at: $updatedReportPath"
    }

    #Export found and missing files to CSV, then upload to destination folder
    $foundFilesCollection | Export-Csv -Path "$updatedReportPath\FilesFoundReport.csv" -NoTypeInformation      
    $missingFilesCollection | Export-Csv -Path "$updatedReportPath\FilesMissingReport.csv" -NoTypeInformation

    $reportsFolderExists = Get-PnPFolder -Url "$DestFolder/Reports" -ErrorAction SilentlyContinue
    if ($null -eq $reportsFolderExists)
    {
        Write-Host -ForegroundColor Green "Reports folder missing. Creating 'Reports' folder in '$DestFolder'."
        Add-PnPFolder -Name "Reports" -Folder $DestFolder | Out-Null #Supress output
    }

    Add-PnPFile -Path "$updatedReportPath\FilesMissingReport.csv" -Folder "$DestFolder/Reports" | Out-Null #Supress output
    Add-PnPFile -Path "$updatedReportPath\FilesFoundReport.csv" -Folder "$DestFolder/Reports" | Out-Null #Supress output
#>
    #Lock site access after files have been copied
#    Set-PnPTenantSite -Url $Site.Url -LockState "ReadOnly"
#    Write-Host -ForegroundColor Yellow "`nSite Collection '$($Site.Url)' has been locked to Read-Only access after file copy completed."
}

#Overall report of site collections and if all files were found
$siteCollectionsResults | Export-Csv -Path "$reportPath\SiteCollectionsFilesCheckReport.csv" -NoTypeInformation
Stop-Transcript
#$SitesCollections | Export-Csv -Path "$reportPath\AllSitesReport.csv" -NoTypeInformation 



#debug and unlock
# for ($i = 15; $i -lt 20; $i++) {
#     write-host "Site collection url: $($sitescollections[$i].Url)"
#     set-pnptenantsite $sitescollections[20] -lockstate "unlock"
# }

#set-pnptenantsite "https://enchantedrock.sharepoint.com/sites/HEBFreshPlantPhaseI" -lockstate "readonly"

set-pnptenantsite "https://enchantedrock.sharepoint.com/sites/CPS-SAWSMaintenanceAgreement" -lockstate "unlock"
#get-pnptenantsite $sitescollections[113].Url | Select-Object lockstate



#remove element at index 1 
#$SitesCollections = $SitesCollections | Where-Object { $_ -ne $SitesCollections[1] }

#remove files where path includes GN1-HEB7-0801Alliance
#$EREFilesList = $EREFilesList | Where-Object { $_.ServerRelativeUrl -notlike "*OnePlan Sites/HEB/HEB7/GN1-HEB7-0801Alliance*" }

#$contSiteCollections = $contSiteCollections[4..($contSiteCollections.Count - 1)]


$siteCollectionsResults = @()
$i = 0
foreach ($site in $SitesCollections) {
    write-host -foregroundcolor Green "Processing site number $i" 
    write-host $site.url
    $siteCollectionsResults += [PSCustomObject]@{
                    SiteName = $Site.Url.Split("/")[-1]
                    LockState  = (Get-PnPTenantSite -Url $Site.Url).LockState
                    RelatedGroup = (Get-PnPTenantSite -Url $Site.Url).RelatedGroupID
                    SiteTemplate = (Get-PnPTenantSite -Url $Site.Url).Template
                    StorageUsed = (Get-PnPTenantSite -Url $Site.Url).StorageUsageCurrent
                }
    $i++
}

$siteCollectionsResults | Export-Excel -Path "$reportPath\SiteCollectionsLockStateReport.xlsx"
