<# Monitor
Get-AzVMRunCommand `
    -ResourceGroupName $ResourceGroupName `
    -VMName $VMName `
    -RunCommandName $RunCommandName `
    -Expand InstanceView

$Result = Get-AzVMRunCommand `
    -ResourceGroupName $ResourceGroupName `
    -VMName $VMName `
    -RunCommandName $RunCommandName `
    -Expand InstanceView

$Result.InstanceView 
#>
$SubscriptionId    = (Get-AzContext).Subscription.Id
$ResourceGroupName = "VINE_RESOURCES"
$VMName            = "azbusappsdb"
$Location          = "centralus"
$RunCommandName    = "Enable-erockadmin"

$Script = @'
$ErrorActionPreference = "Stop"
$UserName = "erockadmin"

Write-Output "========================================"
Write-Output " LOCAL ADMIN ACCOUNT CONFIGURATION"
Write-Output "========================================"
Write-Output "Computer: $env:COMPUTERNAME"
Write-Output "Target local account: $UserName"
Write-Output ""

# Verify the local account exists
$User = Get-LocalUser -Name $UserName -ErrorAction Stop

Write-Output "Found local account: $UserName"
Write-Output "Currently enabled: $($User.Enabled)"

# Enable the account if necessary
if (-not $User.Enabled) {
    Enable-LocalUser -Name $UserName -ErrorAction Stop
    Write-Output "Enabled local account: $UserName"
}
else {
    Write-Output "$UserName is already enabled."
}

Write-Output ""
Write-Output "--- ADMINISTRATORS MEMBERSHIP ---"

# Avoid Get-LocalGroupMember because unresolved S-1-12-1
# principals in the Administrators group can cause it to fail.
#
# Run net.exe through cmd.exe so PowerShell doesn't convert
# stderr output from an already-member result into a terminating error.

$AdminResult = cmd.exe /c "net localgroup Administrators `"$UserName`" /add 2>&1"
$AdminExitCode = $LASTEXITCODE

switch ($AdminExitCode) {

    0 {
        Write-Output "Added $UserName to local Administrators."
    }

    2 {
        # NET HELPMSG 1378 maps the underlying Windows error
        # indicating the account is already a group member.
        if ($AdminResult -match "1378|already a member") {
            Write-Output "$UserName is already a local Administrator."
        }
        else {
            Write-Error "Failed to add $UserName to Administrators. Exit code: $AdminExitCode. Output: $($AdminResult -join ' ')"
        }
    }

    default {
        if ($AdminResult -match "1378|already a member") {
            Write-Output "$UserName is already a local Administrator."
        }
        else {
            Write-Error "Failed to add $UserName to Administrators. Exit code: $AdminExitCode. Output: $($AdminResult -join ' ')"
        }
    }
}

Write-Output ""
Write-Output "--- FINAL ACCOUNT STATUS ---"

$FinalUser = Get-LocalUser -Name $UserName -ErrorAction Stop

$FinalUser |
    Select-Object Name, Enabled, SID, LastLogon, PasswordExpires |
    Format-List

if (-not $FinalUser.Enabled) {
    Write-Error "$UserName is still disabled."
}

Write-Output "VALIDATION RESULTS"
Write-Output "------------------"
Write-Output "Account exists     : True"
Write-Output "Account enabled    : $($FinalUser.Enabled)"

if ($AdminResult -match "1378|already a member") {
    Write-Output "Local Administrator: True"
}
elseif ($AdminExitCode -eq 0) {
    Write-Output "Local Administrator: True"
}
else {
    Write-Output "Local Administrator: Unknown"
}

Write-Output ""
Write-Output "Configuration completed successfully."
'@

Set-AzVMRunCommand `
    -SubscriptionId $SubscriptionId `
    -ResourceGroupName $ResourceGroupName `
    -VMName $VMName `
    -Location $Location `
    -RunCommandName $RunCommandName `
    -SourceScript $Script

    