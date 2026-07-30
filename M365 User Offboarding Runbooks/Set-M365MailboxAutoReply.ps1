param(
    [Parameter(Mandatory)]
    [string]$UserPrincipalName,

    [string]$AutoReplyMessage = "This mailbox is no longer being monitored. Your email has been forwarded if applicable.",

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
            -StepName "SetAutoReply" `
            -Target $UserPrincipalName `
            -Message "Would enable mailbox auto reply."
    }
    else {
        Set-MailboxAutoReplyConfiguration `
            -Identity $UserPrincipalName `
            -AutoReplyState Enabled `
            -InternalMessage $AutoReplyMessage `
            -ExternalMessage $AutoReplyMessage `
            -ExternalAudience All `
            -ErrorAction Stop

        Write-Log `
            -Level "SUCCESS" `
            -StepName "SetAutoReply" `
            -Target $UserPrincipalName `
            -Message "Enabled mailbox auto reply."
    }

    [PSCustomObject]@{
        UserPrincipalName = $UserPrincipalName
        Action            = "SetAutoReply"
        Status            = if ($WhatIfMode) { "WhatIf" } else { "Success" }
        CorrelationId     = $CorrelationId
    }
}
catch {
    Write-Log `
        -Level "ERROR" `
        -StepName "SetAutoReply" `
        -Target $UserPrincipalName `
        -Message "Failed to set mailbox auto reply." `
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