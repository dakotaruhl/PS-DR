<# 
$Result = Get-AzVMRunCommand `
    -ResourceGroupName $ResourceGroupName `
    -VMName $VMName `
    -RunCommandName $RunCommandName `
    -Expand InstanceView

$Result.InstanceView |
    Select-Object `
        ExecutionState,
        ExecutionMessage,
        ExitCode,
        StartTime,
        EndTime,
        Output,
        Error |
    Format-List 
#>

$SubscriptionId    = (Get-AzContext).Subscription.Id
$ResourceGroupName = "VINE_RESOURCES"
$VMName            = "azbusappsdb"
$Location          = "centralus"
$RunCommandName    = "Test-EntraRDPPrereqs"

$Script = @'
$targets = @(
    "login.microsoftonline.com",
    "enterpriseregistration.windows.net",
    "pas.windows.net"
)

Write-Output "========================================"
Write-Output " ENTRA / RDP CONNECTIVITY DIAGNOSTICS"
Write-Output "========================================"
Write-Output "Computer: $env:COMPUTERNAME"
Write-Output "Time:     $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss K')"
Write-Output ""

Write-Output "--- ENTRA ENDPOINT CONNECTIVITY ---"

foreach ($target in $targets) {

    $dns = Resolve-DnsName $target -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress } |
        Select-Object -First 1

    $test = Test-NetConnection `
        -ComputerName $target `
        -Port 443 `
        -WarningAction SilentlyContinue

    [PSCustomObject]@{
        Target        = $target
        ResolvedIP    = $dns.IPAddress
        TCP443        = $test.TcpTestSucceeded
        RemoteAddress = $test.RemoteAddress
    } | Format-List

    Write-Output ""
}

Write-Output "--- RDP SERVICE ---"

Get-Service TermService |
    Select-Object Status, StartType |
    Format-List

Write-Output "--- RDP LISTENER ---"

$RdpListener = Get-NetTCPConnection `
    -LocalPort 3389 `
    -State Listen `
    -ErrorAction SilentlyContinue

if ($RdpListener) {

    $RdpListener |
        Select-Object LocalAddress, LocalPort, State |
        Format-List
}
else {
    Write-Warning "No TCP 3389 listening socket was found."
}

Write-Output "--- ENTRA JOIN ---"

$DsregStatus = dsregcmd /status

$DsregStatus |
    Select-String "AzureAdJoined|DeviceId|TenantId" |
    ForEach-Object {
        Write-Output $_.Line.Trim()
    }

Write-Output ""
Write-Output "--- SUMMARY ---"

$TermService = Get-Service TermService

Write-Output "TermService Running : $($TermService.Status -eq 'Running')"
Write-Output "RDP 3389 Listening  : $([bool]$RdpListener)"

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

