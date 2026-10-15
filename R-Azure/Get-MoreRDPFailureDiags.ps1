<# 
$Result = Get-AzVMRunCommand `
    -ResourceGroupName $ResourceGroupName `
    -VMName $VMName `
    -RunCommandName $RunCommandName `
    -Expand InstanceView

$Result.InstanceView.Output
$Result.InstanceView.Error 
#>

$SubscriptionId    = (Get-AzContext).Subscription.Id
$ResourceGroupName = "VINE_RESOURCES"
$VMName            = "azappsdb"
$Location          = "centralus"
$RunCommandName    = "Get-RecentRDPFailure"

$Script = @'
$Start = (Get-Date).AddMinutes(-30)

Write-Output "========================================"
Write-Output "RDP FAILURE DIAGNOSTICS"
Write-Output "========================================"
Write-Output "Computer: $env:COMPUTERNAME"
Write-Output "Since:    $Start"
Write-Output "Current:  $(Get-Date)"
Write-Output ""

$Logs = @(
    'Microsoft-Windows-TerminalServices-LocalSessionManager/Operational',
    'Microsoft-Windows-TerminalServices-RemoteConnectionManager/Operational',
    'Microsoft-Windows-RemoteDesktopServices-RdpCoreTS/Operational',
    'Microsoft-Windows-User Profiles Service/Operational'
)

foreach ($Log in $Logs) {

    Write-Output ""
    Write-Output "============================================================"
    Write-Output $Log
    Write-Output "============================================================"

    try {
        $Events = Get-WinEvent -FilterHashtable @{
            LogName   = $Log
            StartTime = $Start
        } -ErrorAction Stop | Sort-Object TimeCreated

        if ($Events) {
            foreach ($Event in $Events) {
                Write-Output "Time     : $($Event.TimeCreated)"
                Write-Output "ID       : $($Event.Id)"
                Write-Output "Level    : $($Event.LevelDisplayName)"
                Write-Output "Provider : $($Event.ProviderName)"
                Write-Output "Message:"
                Write-Output $Event.Message
                Write-Output "----------------------------------------"
            }
        }
        else {
            Write-Output "No events found."
        }
    }
    catch {
        Write-Output "Unable to read log: $($_.Exception.Message)"
    }
}

Write-Output ""
Write-Output "============================================================"
Write-Output "SYSTEM EVENTS"
Write-Output "============================================================"

$SystemEvents = Get-WinEvent -FilterHashtable @{
    LogName   = 'System'
    StartTime = $Start
} -ErrorAction SilentlyContinue |
Where-Object {
    $_.ProviderName -match 'TermService|RemoteDesktop|Schannel|LSA|Kerberos'
} |
Sort-Object TimeCreated

if ($SystemEvents) {
    foreach ($Event in $SystemEvents) {
        Write-Output "Time     : $($Event.TimeCreated)"
        Write-Output "Provider : $($Event.ProviderName)"
        Write-Output "ID       : $($Event.Id)"
        Write-Output "Level    : $($Event.LevelDisplayName)"
        Write-Output "Message:"
        Write-Output $Event.Message
        Write-Output "----------------------------------------"
    }
}
else {
    Write-Output "No matching System events found."
}

Write-Output ""
Write-Output "============================================================"
Write-Output "APPLICATION EVENTS"
Write-Output "============================================================"

$ApplicationEvents = Get-WinEvent -FilterHashtable @{
    LogName   = 'Application'
    StartTime = $Start
} -ErrorAction SilentlyContinue |
Where-Object {
    $_.ProviderName -match 'User Profile|Winlogon'
} |
Sort-Object TimeCreated

if ($ApplicationEvents) {
    foreach ($Event in $ApplicationEvents) {
        Write-Output "Time     : $($Event.TimeCreated)"
        Write-Output "Provider : $($Event.ProviderName)"
        Write-Output "ID       : $($Event.Id)"
        Write-Output "Level    : $($Event.LevelDisplayName)"
        Write-Output "Message:"
        Write-Output $Event.Message
        Write-Output "----------------------------------------"
    }
}
else {
    Write-Output "No matching Application events found."
}

Write-Output ""
Write-Output "============================================================"
Write-Output "CURRENT RDP SESSIONS"
Write-Output "============================================================"

Write-Output ""
Write-Output "--- QUSER ---"
quser 2>&1

Write-Output ""
Write-Output "--- QWINSTA ---"
qwinsta 2>&1

Write-Output ""
Write-Output "========================================"
Write-Output "Diagnostics complete."
Write-Output "========================================"
'@

Set-AzVMRunCommand `
    -SubscriptionId $SubscriptionId `
    -ResourceGroupName $ResourceGroupName `
    -VMName $VMName `
    -Location $Location `
    -RunCommandName $RunCommandName `
    -SourceScript $Script


$ResourceGroupName = "VINE_RESOURCES"
$VMName            = "azappsdb"
$RunCommandName    = "Get-RecentRDPFailure"

<# Get-AzVMRunCommand `
    -ResourceGroupName $ResourceGroupName `
    -VMName $VMName `
    -RunCommandName $RunCommandName `
    -Expand InstanceView |
Select-Object `
    Name,
    ProvisioningState,
    InstanceViewExecutionState,
    InstanceViewStartTime,
    InstanceViewEndTime,
    InstanceViewExitCode,
    InstanceViewExecutionMessage

Get-AzVM `
    -ResourceGroupName "VINE_RESOURCES" `
    -Name "azappsdb" `
    -Status |
Select-Object -ExpandProperty VMAgent

Get-AzVM `
    -ResourceGroupName "VINE_RESOURCES" `
    -Name "azappsdb" `
    -Status |
Format-List *

$VM = Get-AzVM `
    -ResourceGroupName "VINE_RESOURCES" `
    -Name "azappsdb" `
    -Status

$VM.VMAgent.Statuses | Format-List *
$VM.Statuses | Format-Table Code, DisplayStatus, Message -AutoSize

Get-AzVMExtension `
    -ResourceGroupName "VINE_RESOURCES" `
    -VMName "azappsdb" |
Select-Object Name, Publisher, ExtensionType, ProvisioningState |
Format-Table -AutoSize

Get-AzVMRunCommand `
    -ResourceGroupName "VINE_RESOURCES" `
    -VMName "azappsdb"

$SqlExt = Get-AzVMExtension `
    -ResourceGroupName "VINE_RESOURCES" `
    -VMName "azappsdb" `
    -Name "SqlIaasExtension" `
    -Status

$SqlExt | Format-List *

$SqlExt.SubStatuses | Format-List *

Get-AzVMRunCommand `
    -ResourceGroupName "VINE_RESOURCES" `
    -VMName "azappsdb" `
    -RunCommandName "Get-RecentRDPFailure" `
    -Expand InstanceView |
Format-List * #>