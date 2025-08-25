#Function to Get Permissions Applied on a particular Folder  
Function Get-PnPFolderPermission([Microsoft.SharePoint.Client.Folder]$Folder)  
{  
    Try {  

        #load folder collection
        $folder.RefreshLoad()

        #Get permissions assigned to the Folder  
        #Get-PnPProperty -ClientObject $Folder.ListItemAllFields -Property HasUniqueRoleAssignments, RoleAssignments
        Get-PnPProperty -ClientObject $Folder.ListItemAllFields -Property RoleAssignments
        Get-PnPProperty -ClientObject $Folder.ListItemAllFields.RoleAssignments -Property RoleDefinitionBindings, Member
    
        #Check if Folder has unique permissions  
        $HasUniquePermissions = $Folder.ListItemAllFields.HasUniqueRoleAssignments  
       
        #Loop through each permission assigned and extract details  
        $PermissionCollection = @()  
        Foreach($RoleAssignment in $Folder.ListItemAllFields.RoleAssignments)  
        {  
            #Get the Permission Levels assigned and Member  
            Get-PnPProperty -ClientObject $RoleAssignment -Property RoleDefinitionBindings, Member  
   
            #Leave the Hidden Permissions  
            If($RoleAssignment.Member.IsHiddenInUI -eq $False)  
            {     
                #Get the Principal Type: User, SP Group, AD Group  
                $PermissionType = $RoleAssignment.Member.PrincipalType  
                $PermissionLevels = $RoleAssignment.RoleDefinitionBindings | Select-Object -ExpandProperty Name  
    
                #Remove Limited Access  
                $PermissionLevels = ($PermissionLevels | Where-Object { $_ -ne "Limited Access"}) -join ","  
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
    Catch {  
    write-host -f Red "Error Generating Folder Permission Report!" $_.Exception.Message  
    }  
}  
      
# Parameters  
$SiteURL="https://enchantedrock.sharepoint.com/sites/erintranet"
$ReportFile="C:\Users\DakotaRuhl\Documents\PnP\SingleSitePerms.csv"  
$FolderSiteRelativeURL = "IT Corporate/ERP Selection"  #Folder Site Relative URL (e.g. for 'https://contoso.sharepoint.com/sites/test/Shared Documents/General', it is '/Shared Documents/General')
    
#Connect to the Site collection

#May need to connect Admin Site first? 
#Connect-PnPOnline -URL "https://enchantedrock-admin.sharepoint.com" -Interactive -ClientId 4ac6eede-e81e-4d22-abad-0d43c51486f2
Connect-PnPOnline -URL $SiteURL -Interactive -ClientId 4ac6eede-e81e-4d22-abad-0d43c51486f2
   
#Delete the file, If already exist!  
If (Test-Path $ReportFile) { Remove-Item $ReportFile }  
   
#Get the Folder and all Subfolders from URL  
$Folder = Get-PnPFolder -Url $FolderSiteRelativeURL
$SubFolders = Get-PnPFolderItem -FolderSiteRelativeUrl $FolderSiteRelativeURL -ItemType Folder -Recursive

#Call the function to generate folder permission report  
Get-PnPFolderPermission $Folder
$SubFolders | ForEach-Object { Get-PnPFolderPermission $_ }