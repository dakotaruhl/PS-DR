<# 
$RC = Get-AzVMRunCommand `
    -ResourceGroupName "VINE_RESOURCES" `
    -VMName "azappsdb" `
    -RunCommandName "Check-WindowsVersion" `
    -Expand InstanceView

$RC.InstanceView.Output 

$RC = Get-AzVMRunCommand `
    -ResourceGroupName "VINE_RESOURCES" `
    -VMName "azappsdb" `
    -RunCommandName "Check-WindowsVersion" `
    -Expand InstanceView

$RC.InstanceView |
    Select ExecutionState, StartTime, EndTime, ExitCode |
    Format-List



#>

$Script = @'
Get-ComputerInfo |
    Select-Object WindowsProductName, WindowsVersion, OsBuildNumber, OsArchitecture |
    Format-List

Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' |
    Select-Object ProductName, DisplayVersion, CurrentBuild, UBR |
    Format-List
'@

Set-AzVMRunCommand `
    -ResourceGroupName "VINE_RESOURCES" `
    -VMName "azappsdb" `
    -Location "centralus" `
    -RunCommandName "Check-WindowsVersion" `
    -SourceScript $Script