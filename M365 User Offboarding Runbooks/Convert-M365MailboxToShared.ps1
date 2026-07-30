param(
    [Parameter(Mandatory)]
    [string]$UserPrincipalName,

    [bool]$WhatIfMode = $true
)
$ErrorActionPreference = "Stop"

$ErrorActionPreference = "Stop"

Import-Module Erock.M365.Automation.Common -ErrorAction Stop

Connect-MgGraph -Identity -NoWelcome

Initialize-RunbookLog `
    -CorrelationId $CorrelationId `
    -RunbookName $MyInvocation.MyCommand.Name `
    -UserPrincipalName $UserPrincipalName

Connect-ExchangeOnline `
    -ManagedIdentity `
    -Organization "enchantedrock.onmicrosoft.com" `
    -ShowBanner:$false

try {
    if ($WhatIfMode) {
        [PSCustomObject]@{
            UserPrincipalName = $UserPrincipalName
            Action            = "ConvertMailbox"
            Status            = "WhatIf"
            Message           = "Would convert mailbox to shared."
        }

        return
    }

    Set-Mailbox `
        -Identity $UserPrincipalName `
        -Type Shared

    [PSCustomObject]@{
        UserPrincipalName = $UserPrincipalName
        Action            = "ConvertMailbox"
        Status            = "Success"
        Message           = "Mailbox converted to shared."
    }
}
finally {
    Disconnect-ExchangeOnline -Confirm:$false
}