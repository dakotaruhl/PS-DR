##############
# https://morgantechspace.com/2018/04/export-office-365-distribution-group-members-csv-powershell.html
# The following script exports all the distribution lists and their memberships to CSV file.
##############

#Sets the Script Directory to the location the .ps1 file is located
$ScriptDir = Split-Path $script:MyInvocation.MyCommand.Path

$Result=@()
$groups = Get-DistributionGroup -ResultSize Unlimited
$totalmbx = $groups.Count
$i = 1 
$groups | ForEach-Object {
Write-Progress -activity "Processing $_.DisplayName" -status "$i out of $totalmbx completed"
$group = $_
Get-DistributionGroupMember -Identity $group.Name -ResultSize Unlimited | ForEach-Object {
$member = $_
$Result += New-Object PSObject -property @{ 
GroupName = $group.DisplayName
Member = $member.Name
EmailAddress = $member.PrimarySMTPAddress
RecipientType= $member.RecipientType
}}
$i++
}
$Result | Export-CSV "$ScriptDir\Reports\All-Distribution-Group-Members.csv" -NoTypeInformation -Encoding UTF8
