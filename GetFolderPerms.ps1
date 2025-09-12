#Function to Get Permissions Applied on a particular Folder
Function Get-PnPFolderPermission([Microsoft.SharePoint.Client.Folder]$Folder)
{
    Try 
    {
        # Load ListItemAllFields first
        $ctx = Get-PnPContext
        $ctx.Load($folder.ListItemAllFields)
        $ctx.ExecuteQuery()

        # Then load HasUniqueRoleAssignments and RoleAssignments
        $LoadHasUnique = Get-PnPProperty -ClientObject $Folder.ListItemAllFields -Property HasUniqueRoleAssignments
        $LoadRoleAssignments = Get-PnPProperty -ClientObject $Folder.ListItemAllFields -Property RoleAssignments


        $RAList = $Folder.ListItemAllFields.RoleAssignments

        #Check if Folder has unique permissions
        $HasUniquePermissions = $Folder.ListItemAllFields.HasUniqueRoleAssignments
     
        #Loop through each permission assigned and extract details
        $PermissionCollection = @()
        Foreach($RoleAssignment in $RAList)
        {
            #Get the Permission Levels assigned and Member
            $loadPermissionLevel = Get-PnPProperty -ClientObject $RoleAssignment -Property RoleDefinitionBindings, Member
 
            #Leave the Hidden Permissions
            If($RoleAssignment.Member.IsHiddenInUI -eq $False)
            {    
                #Get the Principal Type: User, SP Group, AD Group
                $PermissionType = $RoleAssignment.Member.PrincipalType
                $PermissionLevels = $RoleAssignment.RoleDefinitionBindings | Select -ExpandProperty Name
  
                #Remove Limited Access
                $PermissionLevels = ($PermissionLevels | Where { $_ -ne "Limited Access"}) -join ","
                If($PermissionLevels.Length -eq 0) {Continue}
  
                #Get SharePoint group members
                If($PermissionType -eq "SharePointGroup")
                {
                    #Get Group Members
                    $GroupName = $RoleAssignment.Member.LoginName
                    $GroupMembers = Get-PnPGroupMember -Identity $GroupName
                  
                    #Leave Empty Groups
                    If($GroupMembers.count -eq 0){Continue}
                    If($GroupName -notlike "*System Account*" -and $GroupName -notlike "*SharingLinks*" -and $GroupName -notlike "*tenant*" -and $GroupName -notlike `
                        "Excel Services Viewers" -and $GroupName -notlike "Restricted Readers" -and  $GroupName -notlike "Records Center Web Service Submitters for records")
                    { 
                        ForEach($User in $GroupMembers)
                        {
                            #Add the Data to Folder
                            $Permissions = New-Object PSObject
                            $Permissions | Add-Member NoteProperty FolderName($Folder.Name)
                            $Permissions | Add-Member NoteProperty FolderURL($Folder.ServerRelativeUrl)
                            $Permissions | Add-Member NoteProperty User($User.Title)
                            $Permissions | Add-Member NoteProperty Type($PermissionType)
                            $Permissions | Add-Member NoteProperty Permissions($PermissionLevels)
                            $Permissions | Add-Member NoteProperty GrantedThrough("SharePoint Group: $($RoleAssignment.Member.LoginName)")
                            $PermissionCollection += $Permissions
                        }
                    }
                }
                Else
                {
                    #Add the Data to Folder
                    $Permissions = New-Object PSObject
                    $Permissions | Add-Member NoteProperty FolderName($Folder.Name)
                    $Permissions | Add-Member NoteProperty FolderURL($Folder.ServerRelativeUrl)
                    $Permissions | Add-Member NoteProperty User($RoleAssignment.Member.Title)
                    $Permissions | Add-Member NoteProperty Type($PermissionType)
                    $Permissions | Add-Member NoteProperty Permissions($PermissionLevels)
                    $Permissions | Add-Member NoteProperty GrantedThrough("Direct Permissions")
                    $PermissionCollection += $Permissions
                }
            }
        }
        #Export Permissions to CSV File
        $PermissionCollection | Export-CSV $ReportFile -NoTypeInformation -Append
        Write-host -f Green "`n*** Permissions of Folder '$($Folder.Name)' at '$($Folder.ServerRelativeUrl)' Exported Successfully!***"
    }   
        Catch 
        {
        write-host -f Red "Error Generating Folder Permission Report!" $_.Exception.Message
        }
}

function Merge-CsvFiles 
{
    param 
    (
        [string]$csvFolderPath,
        [string]$outputFilePath
    )
    #Delete the file, If already exist!
    If (Test-Path $outputFilePath) { Remove-Item $outputFilePath }

    # Get all CSV files in the specified folder
    $csvFiles = Get-ChildItem -Path $csvFolderPath -Filter "*.csv"

    # Initialize an empty array to store the combined data
    $combinedData = @()

    # Loop through each CSV file
    foreach ($file in $csvFiles) {
        # Import the content of each CSV file
        $data = Import-Csv -Path $file.FullName

        # Add the imported data to the combined data array
        $combinedData += $data
    }

    # Export the combined data to a new CSV file
    # -NoTypeInformation prevents the addition of a "#TYPE System.Management.Automation.PSCustomObject" line
    $combinedData | Export-Csv -Path $outputFilePath -NoTypeInformation
}      
##Parameters
##  install-module sharepointpnpPowerShellOnline -scope currentuser -allowclobber (maybe required old version?)
#Site URL and document library (Change the value for relativeURL to the targeted Doc Library)
$SiteURL="https://enchantedrock.sharepoint.com/sites/erintranet/"
$FolderSiteRelativeURL = "/IT Corporate" 

#Connect to the Site collection
Connect-PnPOnline -URL $SiteURL -Interactive -ClientId 4ac6eede-e81e-4d22-abad-0d43c51486f2

#Initialize collection of library. Removed -recursive to get top level folders only
$Folder = Get-PnPFolder -Url $FolderSiteRelativeURL
$SubFolders = Get-PnPFolderItem -FolderSiteRelativeUrl $FolderSiteRelativeURL -ItemType Folder
$TargetLib = $Folder.Name 

#Set initial report path to Doc Library name (make sure to create this folder first, probably?)
$ReportLibrary = $Folder.Name -replace " ", "_"
$ReportFileSubString ="C:\Users\DakotaRuhl\Documents\Reports\Permission Reports\$ReportLibrary\PnPFolderPermissionRpt_"

#Run permission report function for each top level folder
foreach ($SubFolder in $SubFolders) {
    $FolderSiteRelativeURL = "$TargetLib/" + $SubFolder.Name
    $ReportFile = $ReportFileSubString + ($SubFolder.Name -replace " ", "_") + ".csv"
    write-host -f Yellow "`nGenerating Permission Report for Folder '$($SubFolder.Name)' at '$($FolderSiteRelativeURL)'"

    #Delete the file, If already exist!
    If (Test-Path $ReportFile) { Remove-Item $ReportFile }

    #Get the Folder and all Subfolders from URL
    $Folder = Get-PnPFolder -Url $FolderSiteRelativeURL
    $SubFoldersRecursive = Get-PnPFolderItem -FolderSiteRelativeUrl $FolderSiteRelativeURL -ItemType Folder -Recursive
 
    #Call the function to generate folder permission report
    if ($subfolder.Name -ne "Forms" -or $Folder.Name -ne "Forms") 
    {
        Get-PnPFolderPermission $Folder
        $SubFoldersRecursive | ForEach-Object { Get-PnPFolderPermission $_ }
    }
    elseif ($Folder.Name -eq "Forms" -or $subfolder.Name -eq "Forms") 
    {
        write-host -f Red "`nSkipping Folder at '$($FolderSiteRelativeURL)' as it is a forms folder"
    } 
    elseif ($SubFoldersRecursive.Count -eq 0) 
    {
        write-host -f Red "`nNo remaining folders found at '$($FolderSiteRelativeURL)'"
    }
}

#Merge all CSV files into one
# Define the path to the folder containing your CSV files
$csvFolderPath = "C:\Users\DakotaRuhl\Documents\Reports\Permission Reports\$ReportLibrary"

# Define the path and name for the merged output file
$outputFilePath = "C:\Users\DakotaRuhl\Documents\Reports\Permission Reports\$ReportLibrary\MergedPermissionsFile.csv"

try 
{
    Merge-CsvFiles -csvFolderPath $csvFolderPath -outputFilePath $outputFilePath
    Write-Host -ForegroundColor Yellow "`nMerged CSV File Created Successfully at '$outputFilePath'"
}
catch 
{
    Write-Host -ForegroundColor Red "`nError Merging CSV Files: $_.Exception.Message"
}
