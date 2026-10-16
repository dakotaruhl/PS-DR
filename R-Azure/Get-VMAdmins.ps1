$Result = Invoke-AzVMRunCommand `
    -ResourceGroupName "VINE_RESOURCES" `
    -VMName "azappsdb" `
    -CommandId "RunPowerShellScript" `
    -ScriptString @'
$Group = [ADSI]"WinNT://./Administrators,group"

$Group.Invoke("Members") | ForEach-Object {
    $Member = $_

    [PSCustomObject]@{
        Name  = $Member.GetType().InvokeMember(
            "Name",
            "GetProperty",
            $null,
            $Member,
            $null
        )
        Class = $Member.GetType().InvokeMember(
            "Class",
            "GetProperty",
            $null,
            $Member,
            $null
        )
        Path  = $Member.GetType().InvokeMember(
            "ADsPath",
            "GetProperty",
            $null,
            $Member,
            $null
        )
    }
} | Format-Table -AutoSize
'@

$Result.Value |
    Select-Object Code, DisplayStatus, Message |
    Format-List