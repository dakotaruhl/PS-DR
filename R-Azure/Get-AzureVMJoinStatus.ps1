<# $RC = Get-AzVMRunCommand `
    -ResourceGroupName "VINE_RESOURCES" `
    -VMName "azappsdb" `
    -RunCommandName "Check-AADLogin" `
    -Expand InstanceView

$RC.InstanceView | Format-List * #>

$Script = @'
Write-Output "=== HOSTNAME ==="
hostname

Write-Output "`n=== DSREGCMD ==="
dsregcmd /status

Write-Output "`n=== AAD LOGIN PACKAGE ==="
Get-AppxPackage Microsoft.AAD.BrokerPlugin -AllUsers |
    Select-Object Name, PackageFullName

Write-Output "`n=== RDP SERVICE ==="
Get-Service TermService |
    Select-Object Name, Status, StartType
'@

Set-AzVMRunCommand `
    -ResourceGroupName "VINE_RESOURCES" `
    -VMName "azappsdb" `
    -Location "centralus" `
    -RunCommandName "Check-AADLogin" `
    -SourceScript $Script