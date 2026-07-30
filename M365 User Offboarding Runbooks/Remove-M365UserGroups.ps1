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

$RemovedCount = 0
$FailedCount = 0
$SkippedCount = 0

try {
    Write-Log -Level "INFO" -StepName "Connect" -Message "Connected to Microsoft Graph."

    $User = Get-MgUser -UserId $UserPrincipalName -ErrorAction Stop

    $MemberObjects = Get-MgUserMemberOf -UserId $User.Id -All -ErrorAction Stop
    $Groups = @($MemberObjects | Where-Object { $_.AdditionalProperties.'@odata.type' -eq '#microsoft.graph.group' })

    Write-Log `
        -Level "INFO" `
        -StepName "DiscoverGroups" `
        -Target $UserPrincipalName `
        -Message "Found $($Groups.Count) group membership object(s)."

    foreach ($GroupObject in $Groups) {
        $GroupId = $GroupObject.Id

        try {
            $Group = Get-MgGroup `
                -GroupId $GroupId `
                -Property "id,displayName,groupTypes,onPremisesSyncEnabled,isAssignableToRole,securityEnabled,mailEnabled" `
                -ErrorAction Stop

            $GroupTypes = @($Group.GroupTypes)

            if ($GroupTypes -contains "DynamicMembership") {
                $SkippedCount++

                Write-Log `
                    -Level "WARNING" `
                    -StepName "RemoveGroupMembership" `
                    -Target $Group.DisplayName `
                    -Message "Skipped dynamic group membership. Dynamic memberships are controlled by the group rule."
                continue
            }

            if ($Group.OnPremisesSyncEnabled -eq $true) {
                $SkippedCount++

                Write-Log `
                    -Level "WARNING" `
                    -StepName "RemoveGroupMembership" `
                    -Target $Group.DisplayName `
                    -Message "Skipped synced group. Membership is controlled outside cloud-only Graph removal."
                continue
            }

            if ($WhatIfMode) {
                Write-Log `
                    -Level "WHATIF" `
                    -StepName "RemoveGroupMembership" `
                    -Target $Group.DisplayName `
                    -Message "Would remove user from group [$($Group.DisplayName)] [$($Group.Id)]."
                continue
            }

            Remove-MgGroupMemberByRef `
                -GroupId $Group.Id `
                -DirectoryObjectId $User.Id `
                -ErrorAction Stop

            $RemovedCount++

            Write-Log `
                -Level "SUCCESS" `
                -StepName "RemoveGroupMembership" `
                -Target $Group.DisplayName `
                -Message "Removed user from group [$($Group.DisplayName)] [$($Group.Id)]."
        }
        catch {
            $FailedCount++

            Write-Log `
                -Level "ERROR" `
                -StepName "RemoveGroupMembership" `
                -Target $GroupId `
                -Message "Failed to remove group membership." `
                -ErrorMessage $_.Exception.Message
        }
    }

    [PSCustomObject]@{
        UserPrincipalName = $UserPrincipalName
        Action            = "RemoveGroups"
        Status            = if ($FailedCount -gt 0) { "CompletedWithErrors" } elseif ($WhatIfMode) { "WhatIf" } else { "Success" }
        RemovedCount      = $RemovedCount
        FailedCount       = $FailedCount
        SkippedCount      = $SkippedCount
        CorrelationId     = $CorrelationId
    }
}
catch {
    Write-Log `
        -Level "ERROR" `
        -StepName "RemoveGroups" `
        -Target $UserPrincipalName `
        -Message "Failed during group removal workflow." `
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
    # Clean up temporary log files
    Remove-Item -Path "$env:TEMP\*$($script:CorrelationId)*.json" -ErrorAction SilentlyContinue
    Remove-Item -Path "$env:TEMP\*$($script:CorrelationId)*.csv" -ErrorAction SilentlyContinue
    Disconnect-MgGraph | Out-Null
}