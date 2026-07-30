##############
# https://morgantechspace.com/2021/01/check-size-and-status-of-archive-mailbox-powershell.html
# Use the following Powershell script to get the archive status of all user mailboxes. 
# Finally, the script exports the archived mailbox details such as mailbox name, archive status, archive state, mailbox size, and more.
##############

#Sets the Script Directory to the location the .ps1 file is located
$ScriptDir = Split-Path $script:MyInvocation.MyCommand.Path

# Connects to Exchange Online PowerShell Module
write-host "Connecting to Exchange Online"
Connect-ExchangeOnline

$Result=@() 
#Get all user mailboxes
$mailboxes = Get-Mailbox -ResultSize Unlimited -RecipientTypeDetails UserMailbox
$totalmbx = $mailboxes.Count
$i = 0 
$mailboxes | ForEach-Object {
$i++
$mbx = $_
$size = $null
 
Write-Progress -activity "Processing $mbx" -status "$i out of $totalmbx completed"
 
if ($mbx.ArchiveStatus -eq "Active"){
#Get archive mailbox statistics
$mbs = Get-MailboxStatistics $mbx.UserPrincipalName -Archive
 
if ($mbs.TotalItemSize -ne $null){
$size = [math]::Round(($mbs.TotalItemSize.ToString().Split('(')[1].Split(' ')[0].Replace(',','')/1024MB),2)
}else{
$size = 0 }
}
 
$Result += New-Object -TypeName PSObject -Property $([ordered]@{ 
UserName = $mbx.DisplayName
UserPrincipalName = $mbx.UserPrincipalName
ArchiveStatus =$mbx.ArchiveStatus
ArchiveName =$mbx.ArchiveName
ArchiveState =$mbx.ArchiveState
ArchiveMailboxSizeInGB = $size
ArchiveWarningQuota=if ($mbx.ArchiveStatus -eq "Active") {$mbx.ArchiveWarningQuota} Else { $null} 
ArchiveQuota = if ($mbx.ArchiveStatus -eq "Active") {$mbx.ArchiveQuota} Else { $null} 
AutoExpandingArchiveEnabled=$mbx.AutoExpandingArchiveEnabled
})
}
$Result | Export-CSV "$ScriptDir\Reports\Archive-Mailbox-Report.csv" -NoTypeInformation -Encoding UTF8 