Get-AzVM `
    -ResourceGroupName "VINE_RESOURCES" `
    -Name "azbusappsdb" `
    -Status |
    Select-Object -ExpandProperty Statuses |
    Select-Object Code, DisplayStatus


Get-AzVM `
    -ResourceGroupName "VINE_RESOURCES" `
    -Name "azbusappsdb" `
    -Status |
    Format-List *

az vm run-command list `
    --resource-group "VINE_RESOURCES" `
    --vm-name "azbusappsdb" `
    -o table

az vm run-command show `
    --resource-group "VINE_RESOURCES" `
    --vm-name "azbusappsdb" `
    --run-command-name "Enable-erockadmin" `
    --expand instanceView

## Check Extensions Status and Details
$vm = Get-AzVM `
    -ResourceGroupName "VINE_RESOURCES" `
    -Name "azbusappsdb" `
    -Status

$vm.VMAgent.Statuses | Format-List *

$vm.Extensions | ForEach-Object {
    Write-Host "`n===== $($_.Name) =====" -ForegroundColor Cyan
    $_ | Format-List *
}

$extensions = @(
    "AADLoginForWindows",
    "AdminCenter",
    "enablevmAccess",
    "SqlIaasExtension"
)

foreach ($extension in $extensions) {
    Write-Host "`n===== $extension =====" -ForegroundColor Cyan

    az vm extension show `
        --resource-group "VINE_RESOURCES" `
        --vm-name "azbusappsdb" `
        --name $extension `
        -o json
}

Get-AzVM `
    -ResourceGroupName "VINE_RESOURCES" `
    -Name "azbusappsdb" `
    -Status |
    Select-Object -ExpandProperty VMAgent |
    Format-List *

$commands = @(
    "Add-RemoteDesktopUsers",
    "Enable-erockadmin",
    "Get-RDPDiagnostics",
    "Get-RecentRDPFailure",
    "Test-EntraRDPPrereqs"
)

##Extensions - expand status object
$vm = Get-AzVM `
    -ResourceGroupName "VINE_RESOURCES" `
    -Name "azbusappsdb" `
    -Status

Write-Host "`n===== VM AGENT =====" -ForegroundColor Cyan
$vm.VMAgent.Statuses |
    Format-List Code, Level, DisplayStatus, Message, Time

foreach ($extension in $vm.Extensions) {

    Write-Host "`n===== $($extension.Name) =====" -ForegroundColor Cyan

    Write-Host "--- Status ---" -ForegroundColor Yellow
    $extension.Statuses |
        Format-List Code, Level, DisplayStatus, Message, Time

    Write-Host "--- Substatus ---" -ForegroundColor Yellow
    $extension.Substatuses |
        Format-List Code, Level, DisplayStatus, Message, Time
}

foreach ($command in $commands) {
    Write-Host "`n===== $command =====" -ForegroundColor Cyan

    az vm run-command show `
        --resource-group "VINE_RESOURCES" `
        --vm-name "azbusappsdb" `
        --run-command-name $command `
        --expand instanceView `
        -o json
}

(Get-CimInstance Win32_ComputerSystem).DNSHostName
(Get-CimInstance Win32_ComputerSystem).Domain

Resolve-DnsName 10.0.7.4 -Type PTR

Resolve-DnsName enchantedrock.com -Type SOA -Server 10.0.5.4

Resolve-DnsName enchantedrock.com -Type NS -Server 10.0.5.4

Get-AzNetworkInterface |
    ForEach-Object {
        $Nic = $_

        foreach ($IpConfig in $Nic.IpConfigurations) {
            if ($IpConfig.PrivateIpAddress -eq '10.0.5.4') {
                [PSCustomObject]@{
                    NetworkInterface = $Nic.Name
                    ResourceGroup    = $Nic.ResourceGroupName
                    PrivateIP        = $IpConfig.PrivateIpAddress
                    VM               = $Nic.VirtualMachine.Id
                }
            }
        }
    }

Get-AzVM `
    -ResourceGroupName "Vine_Resources" `
    -Name "azfgt01" |
    Select-Object Name,
        Location,
        @{N="Publisher";E={$_.StorageProfile.ImageReference.Publisher}},
        @{N="Offer";E={$_.StorageProfile.ImageReference.Offer}},
        @{N="SKU";E={$_.StorageProfile.ImageReference.Sku}}

Get-AzNetworkInterface |
    Where-Object {
        $_.VirtualMachine.Id -like "*/virtualMachines/azfgt01"
    } |
    ForEach-Object {

        $Nic = $_

        foreach ($IP in $Nic.IpConfigurations) {

            [PSCustomObject]@{
                NIC       = $Nic.Name
                PrivateIP = $IP.PrivateIpAddress
                Primary   = $IP.Primary
                Subnet    = ($IP.Subnet.Id -split "/")[-1]
            }
        }
    } |
    Format-Table -AutoSize