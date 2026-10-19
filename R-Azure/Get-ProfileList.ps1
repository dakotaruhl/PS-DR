$Result = Invoke-AzVMRunCommand `
    -ResourceGroupName "VINE_RESOURCES" `
    -VMName "azappsdb" `
    -CommandId "RunPowerShellScript" `
    -ScriptString @'
Write-Output "=== DSREGCMD STATUS ==="
dsregcmd /status

Write-Output "`n=== AAD LOGIN COMPONENTS ==="

Get-Service |
    Where-Object {
        $_.Name -match 'AAD|Azure' -or
        $_.DisplayName -match 'Azure AD|Microsoft Entra'
    } |
    Select-Object Name, DisplayName, Status, StartType |
    Format-Table -AutoSize

Write-Output "`n=== PROFILE LIST ==="

Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\*' |
    Select-Object PSChildName, ProfileImagePath |
    Format-Table -AutoSize
'@

$Result.Value |
    Select-Object Code, DisplayStatus, Message |
    Format-List

