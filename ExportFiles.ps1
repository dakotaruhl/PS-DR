$SiteURL="https://enchantedrock.sharepoint.com/sites/erintranet"
$ReportFile="C:\Users\DakotaRuhl\Documents\PnP\"
#Folder Site Relative URL (e.g. for 'https://contoso.sharepoint.com/sites/test/Shared Documents/General', it is '/Shared Documents/General')
$FolderSiteRelativeURL = "/Tech Wiki"  
    
#Connect to the Site collection

#May need to connect Admin Site first? 
#Connect-PnPOnline -URL "https://enchantedrock-admin.sharepoint.com" -Interactive -ClientId 4ac6eede-e81e-4d22-abad-0d43c51486f2
Connect-PnPOnline -URL $SiteURL -Interactive -ClientId 4ac6eede-e81e-4d22-abad-0d43c51486f2    
   
#Get the Folder and all Subfolders from URL  
$FolderURL = Get-PnPFolder -Url $FolderSiteRelativeURL

$ReportFile += $FolderURL.Name + ".csv"
#Delete the file, If already exist!  
If (Test-Path $ReportFile) { Remove-Item $ReportFile } 

$SubFolders = Get-PnPFolderItem -FolderSiteRelativeUrl $FolderSiteRelativeURL -ItemType Folder -Recursive


$SingleFolderFilesCollection = @()
$SingleFolderFolderCollection = @()

$CurrentFolderFileContents = get-pnpfileinfolder $FolderURL

$SingleFolderFilesCollection += $FolderURL
$SingleFolderFilesCollection += ">>>>"
Foreach($file in $CurrentFolderFileContents)
{  
    $SingleFolderFilesCollection += $file
}

Foreach($Folder in $SubFolders)
{  
    $SingleFolderFolderCollection += $Folder
    $CurrentFolderFileContents = get-PnpFileInFolder $Folder
    $SingleFolderFilesCollection += $Folder
    $SingleFolderFilesCollection += ">>" 
    Foreach($file in $CurrentFolderFileContents)
    {  
        $SingleFolderFilesCollection += $file
    }
}

$SingleFolderFilesCollection | Export-CSV $ReportFile -NoTypeInformation -Append