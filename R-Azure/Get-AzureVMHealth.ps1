# Check all run commands
Get-AzVMRunCommand `
    -ResourceGroupName "VINE_RESOURCES" `
    -VMName "azappsdb" |
    Select-Object Name, ProvisioningState |
    Format-Table -AutoSize

# Check specific run command
$RC = Get-AzVMRunCommand `
    -ResourceGroupName "VINE_RESOURCES" `
    -VMName "azappsdb" `
    -RunCommandName "Check-WindowsVersion" `
    -Expand InstanceView
$RC.InstanceView |
    Select-Object ExecutionState, StartTime, EndTime, ExitCode |
    Format-List

# Remove run command
Remove-AzVMRunCommand `
    -ResourceGroupName "VINE_RESOURCES" `
    -VMName "azappsdb" `
    -RunCommandName "Check-WindowsVersion"

# Remove with asynchronous deletion 
Remove-AzVMRunCommand `
    -ResourceGroupName "VINE_RESOURCES" `
    -VMName "azappsdb" `
    -RunCommandName "Check-WindowsVersion" `
    -NoWait `
    -Confirm:$false

# Check extensions 
Get-AzVMExtension `
    -ResourceGroupName "VINE_RESOURCES" `
    -VMName "azappsdb" |
    Select Name, ExtensionType, TypeHandlerVersion, ProvisioningState |
    Format-Table -AutoSize

# Check Azure state 
Get-AzVMRunCommand `
    -ResourceGroupName "VINE_RESOURCES" `
    -VMName "azappsdb" |
    Select-Object Name, ProvisioningState |
    Format-Table -AutoSize

Get-AzVM `
    -ResourceGroupName "VINE_RESOURCES" `
    -Name "azappsdb" `
    -Status |
    Select-Object Name, ProvisioningState,
        @{N='PowerState';E={
            ($_.Statuses | Where-Object Code -like 'PowerState/*').DisplayStatus
        }}

# Check VM's top level state
$VM = Get-AzVM `
    -ResourceGroupName "VINE_RESOURCES" `
    -Name "azappsdb" `
    -Status

$VM.Statuses |
    Select-Object Code, DisplayStatus, Message |
    Format-Table -Wrap


# Check RDP service
Get-Service TermService, UmRdpService |
    Select-Object Name, Status, StartType

# Event Logs
$StartTime = (Get-Date).AddMinutes(-30)

$Logs = @(
    'Microsoft-Windows-TerminalServices-LocalSessionManager/Operational',
    'Microsoft-Windows-TerminalServices-RemoteConnectionManager/Operational',
    'Microsoft-Windows-RemoteDesktopServices-RdpCoreTS/Operational'
)

foreach ($Log in $Logs) {

    Write-Output ""
    Write-Output "================================================="
    Write-Output $Log
    Write-Output "================================================="

    Get-WinEvent `
        -FilterHashtable @{
            LogName   = $Log
            StartTime = $StartTime
        } `
        -ErrorAction SilentlyContinue |
        Select-Object TimeCreated, Id, LevelDisplayName, Message |
        Format-List
}

# System/Application errors
$StartTime = (Get-Date).AddMinutes(-30)

Get-WinEvent `
    -FilterHashtable @{
        LogName   = 'System'
        Level     = 1,2
        StartTime = $StartTime
    } `
    -ErrorAction SilentlyContinue |
    Select-Object TimeCreated, Id, ProviderName, Message |
    Format-List

Get-WinEvent `
    -FilterHashtable @{
        LogName   = 'Application'
        Level     = 1,2
        StartTime = $StartTime
    } `
    -ErrorAction SilentlyContinue |
    Select-Object TimeCreated, Id, ProviderName, Message |
    Format-List

# Full diagnostic script run command

$Script = @'
Write-Output "=== TIME ==="
Get-Date

Write-Output "`n=== RDP SERVICES ==="
Get-Service TermService, UmRdpService |
    Select-Object Name, Status, StartType |
    Format-Table -AutoSize

Write-Output "`n=== SESSIONS - QUSER ==="
quser 2>&1

Write-Output "`n=== SESSIONS - QWINSTA ==="
qwinsta 2>&1

Write-Output "`n=== RDP LISTENER ==="
Get-NetTCPConnection -LocalPort 3389 -ErrorAction SilentlyContinue |
    Select-Object LocalAddress, LocalPort, State, OwningProcess |
    Format-Table -AutoSize

Write-Output "`n=== TERMINAL SERVICES EVENTS ==="

$StartTime = (Get-Date).AddHours(-2)

$Logs = @(
    'Microsoft-Windows-TerminalServices-LocalSessionManager/Operational',
    'Microsoft-Windows-TerminalServices-RemoteConnectionManager/Operational',
    'Microsoft-Windows-RemoteDesktopServices-RdpCoreTS/Operational'
)

foreach ($Log in $Logs) {

    Write-Output "`n--- $Log ---"

    Get-WinEvent `
        -FilterHashtable @{
            LogName   = $Log
            StartTime = $StartTime
        } `
        -ErrorAction SilentlyContinue |
        Select-Object -First 100 TimeCreated, Id, LevelDisplayName, Message |
        Format-List
}

Write-Output "`n=== RECENT SYSTEM ERRORS ==="

Get-WinEvent `
    -FilterHashtable @{
        LogName   = 'System'
        Level     = 1,2
        StartTime = $StartTime
    } `
    -ErrorAction SilentlyContinue |
    Select-Object -First 100 TimeCreated, Id, ProviderName, Message |
    Format-List

Write-Output "`n=== RECENT APPLICATION ERRORS ==="

Get-WinEvent `
    -FilterHashtable @{
        LogName   = 'Application'
        Level     = 1,2
        StartTime = $StartTime
    } `
    -ErrorAction SilentlyContinue |
    Select-Object -First 100 TimeCreated, Id, ProviderName, Message |
    Format-List
'@

Set-AzVMRunCommand `
    -ResourceGroupName "VINE_RESOURCES" `
    -VMName "azappsdb" `
    -Location "centralus" `
    -RunCommandName "RDP-Diagnostics" `
    -SourceScript $Script

# AZ Rest Methods
# Review resource
$Path = "/subscriptions/03866bcc-752b-4fd1-b5bb-cdd66aed21fb/resourceGroups/VINE_RESOURCES/providers/Microsoft.Compute/virtualMachines/azappsdb/runCommands/Check-WindowsVersion?api-version=2026-04-01"

$Result = Invoke-AzRestMethod `
    -Method GET `
    -Path $Path

$Result.StatusCode
$Result.Content | ConvertFrom-Json | ConvertTo-Json -Depth 20


# ARM Get
$Path = "/subscriptions/03866bcc-752b-4fd1-b5bb-cdd66aed21fb/resourceGroups/VINE_RESOURCES/providers/Microsoft.Compute/virtualMachines/azappsdb/runCommands/Check-WindowsVersion?api-version=2026-04-01"

$Result = Invoke-AzRestMethod `
    -Method GET `
    -Path $Path

$Result.StatusCode

$Result.Content |
    ConvertFrom-Json |
    ConvertTo-Json -Depth 20

# Get command details
$RunCommandPath = "/subscriptions/03866bcc-752b-4fd1-b5bb-cdd66aed21fb/resourceGroups/VINE_RESOURCES/providers/Microsoft.Compute/virtualMachines/azappsdb/runCommands/Check-WindowsVersion?api-version=2026-04-01"

$Result = Invoke-AzRestMethod `
    -Method GET `
    -Path $RunCommandPath

$Result.StatusCode

$Json = $Result.Content | ConvertFrom-Json

$Json | ConvertTo-Json -Depth 20

# Get AADLogin extension detail
$AAD = Get-AzVMExtension `
    -ResourceGroupName "VINE_RESOURCES" `
    -VMName "azappsdb" `
    -Name "AADLogin" `
    -Status

$AAD |
    Select Name, ProvisioningState

$AAD.InstanceView.Statuses |
    Format-List *

# Reboot
Restart-AzVM `
    -ResourceGroupName "VINE_RESOURCES" `
    -Name "azappsdb" `
    -NoWait