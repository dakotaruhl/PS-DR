## Tests
Set-AzVMExtension `
    -ResourceGroupName "VINE_RESOURCES" `
    -VMName "azappsdb" `
    -Location "centralus" `
    -Name "AADLogin" `
    -Publisher "Microsoft.Azure.ActiveDirectory" `
    -ExtensionType "AADLoginForWindows" `
    -TypeHandlerVersion "1.0" `
    -DisableAutoUpgradeMinorVersion `
    -EnableAutomaticUpgrade $false

$AAD = Get-AzVMExtension `
    -ResourceGroupName "VINE_RESOURCES" `
    -VMName "azappsdb" `
    -Name "AADLogin" `
    -Status

$AAD |
    Select-Object Name, TypeHandlerVersion, ProvisioningState |
    Format-List

$AAD.InstanceView |
    Select-Object Name, Type, TypeHandlerVersion |
    Format-List

$AAD.InstanceView.Statuses |
    Format-List *