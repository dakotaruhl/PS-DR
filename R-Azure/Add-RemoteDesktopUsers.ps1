<# 
$Result = Get-AzVMRunCommand `
    -ResourceGroupName $ResourceGroupName `
    -VMName $VMName `
    -RunCommandName $RunCommandName `
    -Expand InstanceView

$Result.InstanceView |
    Select-Object ExecutionState, ExitCode, StartTime, EndTime, Output, Error |
    Format-List 
#>

$SubscriptionId    = (Get-AzContext).Subscription.Id
$ResourceGroupName = "VINE_RESOURCES"
$VMName            = "azbusappsdb"
$Location          = "centralus"
$RunCommandName    = "Add-RemoteDesktopUsers"

$Script = @'
$User = "AzureAD\admin-sl@erock.com"

Write-Output "========================================"
Write-Output " REMOTE DESKTOP USERS CONFIGURATION"
Write-Output "========================================"
Write-Output "Computer: $env:COMPUTERNAME"
Write-Output "User:     $User"
Write-Output ""

# Use net.exe directly rather than Get-LocalGroupMember because
# unresolved Entra SIDs can cause Get-LocalGroupMember enumeration failures.

$Result = cmd.exe /c "net localgroup `"Remote Desktop Users`" /add `"$User`" 2>&1"
$ExitCode = $LASTEXITCODE

Write-Output "Command output:"
Write-Output $Result
Write-Output ""

if ($ExitCode -eq 0) {
    Write-Output "SUCCESS: $User was added to Remote Desktop Users."
}
elseif ($Result -match "1378|already a member") {
    Write-Output "SUCCESS: $User is already a member of Remote Desktop Users."
}
else {
    Write-Error "Failed to add $User to Remote Desktop Users. Exit code: $ExitCode"
}

Write-Output ""
Write-Output "Configuration complete."
'@

Set-AzVMRunCommand `
    -SubscriptionId $SubscriptionId `
    -ResourceGroupName $ResourceGroupName `
    -VMName $VMName `
    -Location $Location `
    -RunCommandName $RunCommandName `
    -SourceScript $Script