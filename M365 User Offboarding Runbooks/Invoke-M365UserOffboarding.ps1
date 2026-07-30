param(
    [Parameter(Mandatory)]
    [string]$UserPrincipalName,

    [string]$ForwardingAddress,

    [ValidateSet("60Days", "365Days", "Hold")]
    [string]$DisableDuration = "60Days",

    [string[]]$Actions = @(
    "DisableAccount",
    "RevokeSessions",
    "ConvertMailbox",
    "HideFromGAL",
    "SetAutoReply",
    "RemoveLicenses",
    "RemoveGroups"
    ),

    [bool]$WhatIfMode = $true
)

Import-Module Erock.M365.Automation.Common -ErrorAction Stop

Assert-OffboardingTargetIsAllowed -UserPrincipalName $UserPrincipalName

$ErrorActionPreference = "Stop"

$ResourceGroupName = "M365-Infrastructure"
$AutomationAccountName = "OffboardingAutomation"

$LogSiteHostName = "enchantedrock.sharepoint.com"
$LogSitePath     = "/sites/ITDepartment"
$LogLibraryName  = "Shared Documents"
$LogFolderPath   = "AutomationLogs/M365 Offboarding"

$CorrelationId = [guid]::NewGuid()

Disable-AzContextAutosave -Scope Process | Out-Null

$AzureContext = (Connect-AzAccount -Identity).Context
$AzureContext = Set-AzContext `
    -SubscriptionId $AzureContext.Subscription.Id `
    -DefaultProfile $AzureContext

Connect-MgGraph -Identity -NoWelcome

$CorrelationId = [guid]::NewGuid()

Initialize-RunbookLog `
    -CorrelationId $CorrelationId `
    -RunbookName "Invoke-M365UserOffboarding" `
    -UserPrincipalName $UserPrincipalName

Write-RunbookLog `
    -Level "INFO" `
    -StepName "Start" `
    -Message "Starting parent offboarding runbook."

$Results = [System.Collections.Generic.List[object]]::new()

$CommonParams = @{
    UserPrincipalName = $UserPrincipalName
    WhatIfMode        = $WhatIfMode
    CorrelationId     = $CorrelationId
    LogSiteHostName   = $LogSiteHostName
    LogSitePath       = $LogSitePath
    LogLibraryName    = $LogLibraryName
    LogFolderPath     = $LogFolderPath
}


function Add-ParentResult {
    param(
        [string]$StepName,
        [string]$Status,
        [string]$JobId,
        [string]$Message
    )

    $Result = [PSCustomObject]@{
        Timestamp          = (Get-Date).ToString("o")
        CorrelationId      = $CorrelationId
        UserPrincipalName  = $UserPrincipalName
        StepName           = $StepName
        Status             = $Status
        JobId              = $JobId
        Message            = $Message
    }

    $Results.Add($Result)

    Write-Log `
        -Level "INFO" `
        -StepName $StepName `
        -Target $JobId `
        -Message "$Status - $Message"
}
function Wait-AutomationJob {
    param(
        [Parameter(Mandatory)]
        [guid]$JobId,

        [int]$PollSeconds = 10
    )

    $TerminalStates = @(
        "Completed",
        "Failed",
        "Stopped",
        "Suspended"
    )

    while ($true) {
        $Job = Get-AzAutomationJob `
            -ResourceGroupName $ResourceGroupName `
            -AutomationAccountName $AutomationAccountName `
            -Id $JobId `
            -DefaultProfile $AzureContext

        if ($TerminalStates -contains $Job.Status) {
            return $Job
        }

        Start-Sleep -Seconds $PollSeconds
    }
}
function Invoke-ChildRunbook {
    param(
        [Parameter(Mandatory)]
        [string]$StepName,

        [Parameter(Mandatory)]
        [string]$RunbookName,

        [Parameter(Mandatory)]
        [hashtable]$Parameters,

        [bool]$StopParentOnFailure = $true
    )

    Write-Log `
        -Level "INFO" `
        -StepName $StepName `
        -Message "Starting child runbook [$RunbookName]."

    $Job = Start-AzAutomationRunbook `
        -AutomationAccountName $AutomationAccountName `
        -ResourceGroupName $ResourceGroupName `
        -Name $RunbookName `
        -Parameters $Parameters `
        -DefaultProfile $AzureContext

    Add-ParentResult `
        -StepName $StepName `
        -Status "Started" `
        -JobId $Job.JobId `
        -Message "Child runbook started."

    $CompletedJob = Wait-AutomationJob -JobId $Job.JobId

    Add-ParentResult `
        -StepName $StepName `
        -Status $CompletedJob.Status `
        -JobId $Job.JobId `
        -Message "Child runbook finished with status [$($CompletedJob.Status)]."

    if (($CompletedJob.Status -ne "Completed") -and $StopParentOnFailure) {
        Write-Log `
            -Level "ERROR" `
            -StepName $StepName `
            -Target $Job.JobId `
            -Message "Child runbook failed." `
            -ErrorMessage "Status: $($CompletedJob.Status)"

        throw "Step [$StepName] failed. Child runbook [$RunbookName] ended with status [$($CompletedJob.Status)]. JobId: $($Job.JobId)"
    }

    return $CompletedJob
}


# Main execution block for the parent offboarding runbook
try {
    if ($Actions -contains "DisableAccount") {
        Invoke-ChildRunbook `
            -StepName "DisableAccount" `
            -RunbookName "Disable-M365UserAccount" `
            -Parameters $CommonParams
    }

    if ($Actions -contains "RevokeSessions") {
        Invoke-ChildRunbook `
            -StepName "RevokeSessions" `
            -RunbookName "Revoke-M365UserSessions" `
            -Parameters $CommonParams
    }

    if ($Actions -contains "ConvertMailbox") {
        Invoke-ChildRunbook `
            -StepName "ConvertMailbox" `
            -RunbookName "Convert-M365MailboxToShared" `
            -Parameters $CommonParams
    }

    if ($Actions -contains "HideFromGAL") {
        Invoke-ChildRunbook `
            -StepName "HideFromGAL" `
            -RunbookName "Hide-M365MailboxFromGAL" `
            -Parameters $CommonParams
    }

    if (($Actions -contains "SetForwarding") -and $ForwardingAddress) {
        $ForwardingParams = $CommonParams.Clone()
        $ForwardingParams["ForwardingAddress"] = $ForwardingAddress

        Invoke-ChildRunbook `
            -StepName "SetForwarding" `
            -RunbookName "Set-M365MailboxForwarding" `
            -Parameters $ForwardingParams
    }

    if ($Actions -contains "SetAutoReply") {
        Invoke-ChildRunbook `
            -StepName "SetAutoReply" `
            -RunbookName "Set-M365MailboxAutoReply" `
            -Parameters $CommonParams
    }

    if ($Actions -contains "RemoveLicenses") {
        Invoke-ChildRunbook `
            -StepName "RemoveLicenses" `
            -RunbookName "Remove-M365UserLicenses" `
            -Parameters $CommonParams
    }

    if ($Actions -contains "RemoveGroups") {
        Invoke-ChildRunbook `
            -StepName "RemoveGroups" `
            -RunbookName "Remove-M365UserGroups" `
            -Parameters $CommonParams `
            -StopParentOnFailure $false
    }

    Write-Log -Level "SUCCESS" -StepName "Complete" -Message "Parent offboarding runbook completed."
}
catch {
    Write-Log `
        -Level "ERROR" `
        -StepName "ParentFailure" `
        -Message "Parent runbook failed." `
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
        Write-Warning "Parent log upload failed. $($_.Exception.Message)"
    }
}

$Results