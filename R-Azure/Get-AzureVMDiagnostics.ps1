<# 
$rc.InstanceView |
    Select-Object ExecutionState,
                    ExitCode,
                    StartTime,
                    EndTime,
                    ExecutionMessage,
                    Error |
    Format-List

$rc.InstanceView.Output 

//Check on the command 
Get-AzVMRunCommand `
    -ResourceGroupName "VINE_RESOURCES" `
    -VMName "azappsdb" `
    -RunCommandName "AzAppsDb-Diagnostics" `
    -Expand InstanceView |
    Select-Object -ExpandProperty InstanceView |
    Format-List *


#>

$ResourceGroupName = "VINE_RESOURCES"
$VMName = "azappsdb"
$Location = "centralus"
$RunCommandName = "AzAppsDb-Diagnostics"

$Script = @'
Write-Output "=== COMPUTER ==="
hostname

Write-Output "`n=== TIME ==="
Get-Date

Write-Output "`n=== WINDOWS ==="
Get-CimInstance Win32_OperatingSystem |
    Select-Object Caption, Version, LastBootUpTime

Write-Output "`n=== RDP SERVICES ==="
Get-Service TermService, SessionEnv, UmRdpService -ErrorAction SilentlyContinue |
    Select-Object Name, Status, StartType

Write-Output "`n=== RDP PORT ==="
Get-NetTCPConnection -LocalPort 3389 -State Listen -ErrorAction SilentlyContinue |
    Select-Object LocalAddress, LocalPort, State, OwningProcess

Write-Output "`n=== AZURE AGENT SERVICES ==="
Get-Service WindowsAzureGuestAgent, RdAgent -ErrorAction SilentlyContinue |
    Select-Object Name, Status, StartType

Write-Output "`n=== SQL SERVICES ==="
Get-Service |
    Where-Object { $_.Name -like "MSSQL*" -or $_.Name -like "SQL*" } |
    Select-Object Name, DisplayName, Status, StartType

Write-Output "`n=== REBOOT PENDING ==="
$Paths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending",
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired"
)

foreach ($Path in $Paths) {
    [PSCustomObject]@{
        Path   = $Path
        Exists = Test-Path $Path
    }
}

Write-Output "`n=== DISK SPACE ==="
Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" |
    Select-Object DeviceID,
        @{N="SizeGB";E={[math]::Round($_.Size / 1GB,2)}},
        @{N="FreeGB";E={[math]::Round($_.FreeSpace / 1GB,2)}}

Write-Output "`n=== RECENT SERVICE CONTROL EVENTS ==="
Get-WinEvent -FilterHashtable @{
    LogName   = "System"
    Id        = 7000,7001,7009,7011,7022,7023,7024,7031,7034
    StartTime = (Get-Date).AddHours(-12)
} -ErrorAction SilentlyContinue |
    Select-Object -First 30 TimeCreated, Id, LevelDisplayName, Message
'@

Set-AzVMRunCommand `
    -ResourceGroupName $ResourceGroupName `
    -VMName $VMName `
    -Location $Location `
    -RunCommandName $RunCommandName `
    -SourceScript $Script