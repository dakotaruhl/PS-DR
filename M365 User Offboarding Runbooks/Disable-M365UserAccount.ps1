param(
    [Parameter(Mandatory)]
    [string]$UserPrincipalName,

    [bool]$WhatIfMode = $true
)

$ErrorActionPreference = "Stop"

Import-Module Erock.M365.Automation.Common -ErrorAction Stop

Connect-MgGraph -Identity -NoWelcome

Initialize-RunbookLog `
    -CorrelationId $CorrelationId `
    -RunbookName $MyInvocation.MyCommand.Name `
    -UserPrincipalName $UserPrincipalName

$ErrorActionPreference = "Stop"

Connect-MgGraph -Identity -NoWelcome

if ($WhatIfMode) {
    [PSCustomObject]@{
        UserPrincipalName = $UserPrincipalName
        Action            = "DisableAccount"
        Status            = "WhatIf"
        Message           = "Would disable account and revoke sessions."
    }

    return
}

Update-MgUser `
    -UserId $UserPrincipalName `
    -AccountEnabled:$false

[PSCustomObject]@{
    UserPrincipalName = $UserPrincipalName
    Action            = "DisableAccount"
    Status            = "Success"
    Message           = "Account disabled."
}


$ModuleName = "Erock.M365.Automation.Common"
$SourceFolder = "C:\Users\DakotaRuhl\Documents\PS-DR\M365 User Offboarding Runbooks\$ModuleName"
$ZipPath = "C:\Users\DakotaRuhl\Documents\PS-DR\M365 User Offboarding Runbooks\Erock.M365.Automation.Common\$ModuleName.zip"

if (Test-Path $ZipPath) {
    Remove-Item $ZipPath -Force
}

Compress-Archive `
    -Path $SourceFolder `
    -DestinationPath $ZipPath `
    -Force

    Expand-Archive `
    -Path $ZipPath `
    -DestinationPath "C:\Temp\Validate-$ModuleName" `
    -Force

Get-ChildItem "C:\Temp\Validate-$ModuleName" -Recurse