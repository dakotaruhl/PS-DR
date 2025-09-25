Connect-PnPOnline -URL "https://enchantedrock.sharepoint.com/" -Interactive -ClientId 4ac6eede-e81e-4d22-abad-0d43c51486f2

$SourceUrl = "sites/erintranet/Sales  Marketing/Sales Kit & Published Content/Photos, Videos, Illustrations & Site Photos/Content Development Assets/Viewpoint Raw Footage/Viewpoint Raw Footage July 2024" 
$TargetUrl = "sites/MarketingTeam/Sales Kit Collaboration/Sales Kit & Published Content/Photos, Videos, Illustrations & Site Photos/Content Development Assets/Viewpoint Raw Footage"

$job = Copy-PnPFolder -SourceUrl $SourceUrl -TargetUrl $TargetUrl -NoWait
$jobStatus = Receive-PnPCopyMoveJobStatus -Job $job
if($jobStatus.JobState -eq 0)
{
  Write-Host "Job finished"
}