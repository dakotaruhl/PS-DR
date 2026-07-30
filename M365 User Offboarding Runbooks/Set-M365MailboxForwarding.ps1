param(
    [Parameter(Mandatory)]
    [string]$UserPrincipalName,

    [Parameter(Mandatory)]
    [string]$ForwardingAddress,

    [bool]$WhatIfMode = $true,

    [Parameter(Mandatory)]
    [string]$CorrelationId,

    [Parameter(Mandatory)]
    [string]$LogSiteHostName,

    [Parameter(Mandatory)]
    [string]$LogSitePath,

    [Parameter(Mandatory)]
    [string]$LogLibraryName,

    [Parameter(Mandatory)]
    [string]$LogFolderPath
)
$ErrorActionPreference = "Stop"

Import-Module Erock.M365.Automation.Common -ErrorAction Stop

Connect-MgGraph -Identity -NoWelcome

Initialize-RunbookLog `
    -CorrelationId $CorrelationId `
    -RunbookName $MyInvocation.MyCommand.Name `
    -UserPrincipalName $UserPrincipalName

try {
    Connect-ExchangeOnline `
        -ManagedIdentity `
        -Organization "enchantedrock.onmicrosoft.com" `
        -ShowBanner:$false

    Write-Log -Level "INFO" -StepName "Connect" -Message "Connected to Exchange Online."

    if ($WhatIfMode) {
        Write-Log `
            -Level "WHATIF" `
            -StepName "SetForwarding" `
            -Target $UserPrincipalName `
            -Message "Would set forwarding to [$ForwardingAddress]."
    }
    else {
        Set-Mailbox `
            -Identity $UserPrincipalName `
            -DeliverToMailboxAndForward $true `
            -ForwardingSmtpAddress $ForwardingAddress `
            -ErrorAction Stop

        Write-Log `
            -Level "SUCCESS" `
            -StepName "SetForwarding" `
            -Target $UserPrincipalName `
            -Message "Set forwarding to [$ForwardingAddress]."
    }

    [PSCustomObject]@{
        UserPrincipalName = $UserPrincipalName
        Action            = "SetForwarding"
        ForwardingAddress = $ForwardingAddress
        Status            = if ($WhatIfMode) { "WhatIf" } else { "Success" }
        CorrelationId     = $CorrelationId
    }
}
catch {
    Write-Log `
        -Level "ERROR" `
        -StepName "SetForwarding" `
        -Target $UserPrincipalName `
        -Message "Failed to set forwarding." `
        -ErrorMessage $_.Exception.Message

    throw
}
finally {
    try {
        Publish-RunbookLogToSharePoint `
            -LogSiteHostName $LogSiteHostName `
            -LogSitePath $LogSitePath `
            -LogLibraryName $LogLibraryName `
            -LogFolderPath $LogFolderPath
    }
    catch {
        Write-Warning "Log upload failed. $($_.Exception.Message)"
    }

    try { Disconnect-ExchangeOnline -Confirm:$false } catch {}
    Disconnect-MgGraph | Out-Null
}