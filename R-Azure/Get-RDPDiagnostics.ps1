<# 
$Result = Get-AzVMRunCommand `
    -ResourceGroupName $ResourceGroupName `
    -VMName $VMName `
    -RunCommandName $RunCommandName `
    -Expand InstanceView

$Result.InstanceView |
    Select-Object ExecutionState, ExitCode, StartTime, EndTime, Output, Error |
    Format-List 

$Result = Get-AzVMRunCommand `
    -ResourceGroupName $ResourceGroupName `
    -VMName $VMName `
    -RunCommandName $RunCommandName `
    -Expand InstanceView

$Result.InstanceView.Output
#>

$SubscriptionId    = (Get-AzContext).Subscription.Id
$ResourceGroupName = "VINE_RESOURCES"
$VMName            = "azbusappsdb"
$Location          = "centralus"
$RunCommandName    = "Get-RecentRDPFailure"

$Script = @'
$StartTime = (Get-Date).AddMinutes(-15)

Write-Output "========================================"
Write-Output " RECENT RDP FAILURE DIAGNOSTICS"
Write-Output "========================================"
Write-Output "Computer: $env:COMPUTERNAME"
Write-Output "Since:    $StartTime"
Write-Output "Current:  $(Get-Date)"
Write-Output ""

$Logs = @(
    "Microsoft-Windows-TerminalServices-RemoteConnectionManager/Operational",
    "Microsoft-Windows-TerminalServices-LocalSessionManager/Operational"
)

foreach ($Log in $Logs) {

    Write-Output ""
    Write-Output "========================================"
    Write-Output $Log
    Write-Output "========================================"

    try {

        $Events = Get-WinEvent -FilterHashtable @{
            LogName   = $Log
            StartTime = $StartTime
        } -ErrorAction Stop |
        Sort-Object TimeCreated -Descending |
        Select-Object -First 15

        if ($Events) {

            foreach ($Event in $Events) {

                Write-Output ""
                Write-Output "Time   : $($Event.TimeCreated)"
                Write-Output "ID     : $($Event.Id)"
                Write-Output "Level  : $($Event.LevelDisplayName)"
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
        Write-Output "No events found or log unavailable."
        Write-Output $_.Exception.Message
    }
}

Write-Output ""
Write-Output "========================================"
Write-Output " SECURITY 4625 EVENTS"
Write-Output "========================================"

try {

    $Events = Get-WinEvent -FilterHashtable @{
        LogName   = "Security"
        Id        = 4625
        StartTime = $StartTime
    } -ErrorAction Stop |
    Sort-Object TimeCreated -Descending |
    Select-Object -First 10

    if ($Events) {

        foreach ($Event in $Events) {

            Write-Output ""
            Write-Output "Time   : $($Event.TimeCreated)"
            Write-Output "Message:"
            Write-Output $Event.Message
            Write-Output "----------------------------------------"
        }
    }
    else {
        Write-Output "No recent 4625 events found."
    }
}
catch {
    Write-Output "No recent 4625 events found."
}

Write-Output ""
Write-Output "Diagnostics complete."
'@

Set-AzVMRunCommand `
    -SubscriptionId $SubscriptionId `
    -ResourceGroupName $ResourceGroupName `
    -VMName $VMName `
    -Location $Location `
    -RunCommandName $RunCommandName `
    -SourceScript $Script