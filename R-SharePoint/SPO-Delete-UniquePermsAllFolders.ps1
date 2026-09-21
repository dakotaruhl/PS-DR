#Set Variables
$SiteURL = "https://enchantedrock.sharepoint.com/sites/Granite"
$FolderURL = "/Shared Documents" 
 
$TenantId   = "0bdf0e1f-a359-4b5c-9b79-9357e35ff8c6"
$ClientId   = "97d01716-c2a3-4311-9b73-09ac8579cbf1"
$Thumbprint = "94EF4B57723E2E90CD56F2F407EF6AFBEF275392"

#Connect to PnP Online
Connect-PnPOnline -URL $SiteURL -ClientId $ClientId -Tenant $TenantId -Thumbprint $Thumbprint
 
#Function to reset permissions of all Sub-Folders
Function Reset-SubFolderPermissions($FolderURL)
{
    #Get all sub-folders of the Folder - Exclude system folders
    $SubFolders = Get-PnPFolderItem -FolderSiteRelativeUrl $FolderURL -ItemType Folder | Where {$_.Name -ne "Forms" -and $_.Name -ne "Document"}
 
    #Loop through each sub-folder
    ForEach($SubFolder in $SubFolders)
    {
        $SubFolderURL = $FolderUrl+"/"+$SubFolder.Name
        Write-host -ForegroundColor Green "Processing Folder '$($SubFolder.Name)' at $SubFolderURL"
 
        #Get the Folder Object - with HasUniqueAssignments and ParentList properties
        $Folder = Get-PnPFolder -Url $SubFolderURL -Includes ListItemAllFields.HasUniqueRoleAssignments, ListItemAllFields.ParentList, ListItemAllFields.ID
 
        #Get the List Item of the Folder
        $FolderItem = $Folder.ListItemAllFields
 
        #Check if the Folder has unique permissions
        If($FolderItem.HasUniqueRoleAssignments)
        {
            #Reset permission inheritance
            Set-PnPListItemPermission -List $FolderItem.ParentList -Identity $FolderItem.ID -InheritPermissions
            Write-host "`tUnique Permissions are removed from the Folder!"
        }
 
        #Call the function recursively
        Reset-SubFolderPermissions $SubFolderURL
    }
}
   
#Call the function
Reset-SubFolderPermissions $FolderURL