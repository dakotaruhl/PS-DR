param(
    [Parameter(Mandatory)]
    [string]$UserPrincipalName,

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
    Write-Log -Level "INFO" -StepName "Connect" -Message "Connected to Microsoft Graph."

    $User = Get-MgUser -UserId $UserPrincipalName -ErrorAction Stop

    if ($WhatIfMode) {
        Write-Log -Level "WHATIF" -StepName "RevokeSessions" -Target $UserPrincipalName -Message "Would revoke sign-in sessions."
    }
    else {
        Revoke-MgUserSignInSession -UserId $User.Id -ErrorAction Stop
        Write-Log -Level "SUCCESS" -StepName "RevokeSessions" -Target $UserPrincipalName -Message "Revoked sign-in sessions."
    }

    [PSCustomObject]@{
        UserPrincipalName = $UserPrincipalName
        Action            = "RevokeSessions"
        Status            = if ($WhatIfMode) { "WhatIf" } else { "Success" }
        CorrelationId     = $CorrelationId
    }
}
catch {
    Write-Log `
        -Level "ERROR" `
        -StepName "RevokeSessions" `
        -Target $UserPrincipalName `
        -Message "Failed to revoke sign-in sessions." `
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

    Disconnect-MgGraph | Out-Null
}