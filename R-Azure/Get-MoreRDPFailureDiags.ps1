<# 
Get-AzVMRunCommand `
    -ResourceGroupName "VINE_RESOURCES" `
    -VMName "azappsdb" `
    -RunCommandName "AzAppsDb-AuthDiagnostics" `
    -Expand InstanceView |
    Select-Object -ExpandProperty InstanceView |
    Select-Object ExecutionState, ExitCode, Output, Error |
    Format-List 
#>

$Script = @'
Write-Output "=== DSREGCMD ==="
dsregcmd /status

Write-Output "`n=== RDP CONFIG ==="
Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server" |
    Select-Object fDenyTSConnections

Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" |
    Select-Object UserAuthentication, SecurityLayer, PortNumber

Write-Output "`n=== AAD LOGIN SERVICES ==="
Get-Service -ErrorAction SilentlyContinue |
    Where-Object {
        $_.Name -like "*AAD*" -or
        $_.DisplayName -like "*Azure AD*" -or
        $_.DisplayName -like "*Entra*"
    } |
    Select-Object Name, DisplayName, Status, StartType

Write-Output "`n=== COMPUTER NAME ==="
hostname
[System.Net.Dns]::GetHostEntry($env:COMPUTERNAME)

Write-Output "`n=== RDP USERS ==="
Get-LocalGroupMember -Group "Remote Desktop Users" -ErrorAction SilentlyContinue

Write-Output "`n=== ADMINISTRATORS ==="
Get-LocalGroupMember -Group "Administrators" -ErrorAction SilentlyContinue
'@

Set-AzVMRunCommand `
    -ResourceGroupName "VINE_RESOURCES" `
    -VMName "azappsdb" `
    -Location "centralus" `
    -RunCommandName "AzAppsDb-AuthDiagnostics" `
    -SourceScript $Script