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