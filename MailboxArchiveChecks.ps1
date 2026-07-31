Connect-ExchangeOnline

$user = "alabra@enchantedrock.com"
$mailbox = Get-Mailbox -Identity $user
$mailboxStatistics = Get-MailboxFolderStatistics -Identity $user
$mailbox | Select-Object RetentionPolicy

#View all mailboxes with holds enabled
$LitigationHolds = Get-Mailbox -ResultSize unlimited | Where-Object {$_.LitigationHoldEnabled -eq 'True'}
$LitigationHolds.count 

#View specific user hold status
$mailbox | Format-List LitigationHoldEnabled,LitigationHoldDate,LitigationHoldOwner,InPlaceHolds
$mailbox | Format-List *hold*
#Check delay holds
$mailbox | FL *HoldApplied*

#If no holds, and mailbox is near full, enable the online archive.
Enable-Mailbox -Identity $user -Archive

#set retention policy to archive after 24 months. This will move items from the primary mailbox to the archive mailbox after 24 months.
Set-Mailbox -Identity $user -RetentionPolicy "Archive after 24 Months"
Get-Mailbox -Identity $user | Select-Object RetentionPolicy

##Retention policy won't apply to mailboxes on hold. 
##Once all holds, and delay holds are cleared, you can start the Managed Folder Assistant to apply the retention policy immediately. 
#Otherwise, it will run on its regular schedule (every 7 days by default).
##Start Managed Folder Assistant to apply retention policies or process removing holds
Start-ManagedFolderAssistant -Identity $user

#View mailbox sizes 
$mailboxStatistics $user | Select Name,ItemsInFolder,FolderSize,LastModifiedTime
$mailboxStatistics $user -FolderScope All | FL Name, FolderAndSubFolderSize, Itemsinfolderandsubfolders
$mailboxStatistics $user -FolderScope DeletedItems | FL Name, FolderAndSubFolderSize, Itemsinfolderandsubfolders
$mailboxStatistics $user -FolderScope Inbox | FL Name, FolderAndSubFolderSize, Itemsinfolderandsubfolders
$mailboxStatistics $user -FolderScope RecoverableItems | FL Name, FolderAndSubFolderSize, Itemsinfolderandsubfolders

#Get user's archive guid
$archiveGuid = Get-Mailbox -Identity $user | select -ExpandProperty ArchiveGuid

#View archive mailbox sizes 
#notice archive is a separate mailbox, so we use the archive guid to view the archive mailbox folder statistics.
Get-MailboxFolderStatistics $archiveGuid.Guid | Select Name,ItemsInFolder,FolderSize,LastModifiedTime
#there is also an archive switch against the primary user, which does the command above under the hood. 
Get-MailboxFolderStatistics $user -Archive | Select Name,ItemsInFolder,FolderSize,LastModifiedTime
