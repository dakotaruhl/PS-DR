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

Import-Module Erock.M365.Automation.Common -ErrorAction Stop

Connect-MgGraph -Identity -NoWelcome

Initialize-RunbookLog `
    -CorrelationId $CorrelationId `
    -RunbookName $MyInvocation.MyCommand.Name `
    -UserPrincipalName $UserPrincipalName

$ErrorActionPreference = "Stop"

try {
    Write-Log -Level "INFO" -StepName "Connect" -Message "Connected to Microsoft Graph."

    $User = Get-MgUser `
        -UserId $UserPrincipalName `
        -Property "id,userPrincipalName,assignedLicenses" `
        -ErrorAction Stop

    $SkuIds = @($User.AssignedLicenses | ForEach-Object { $_.SkuId }) | Where-Object { $_ }

    if ($SkuIds.Count -eq 0) {
        Write-Log -Level "INFO" -StepName "RemoveLicenses" -Target $UserPrincipalName -Message "No assigned licenses found."
    }
    elseif ($WhatIfMode) {
        Write-Log -Level "WHATIF" -StepName "RemoveLicenses" -Target $UserPrincipalName -Message "Would remove $($SkuIds.Count) license assignment(s)."
    }
    else {
        Set-MgUserLicense `
            -UserId $User.Id `
            -AddLicenses @() `
            -RemoveLicenses $SkuIds `
            -ErrorAction Stop

        Write-Log -Level "SUCCESS" -StepName "RemoveLicenses" -Target $UserPrincipalName -Message "Removed $($SkuIds.Count) license assignment(s)."
    }

    [PSCustomObject]@{
        UserPrincipalName = $UserPrincipalName
        Action            = "RemoveLicenses"
        Status            = if ($WhatIfMode) { "WhatIf" } else { "Success" }
        LicenseCount      = $SkuIds.Count
        CorrelationId     = $CorrelationId
    }
}
catch {
    Write-Log `
        -Level "ERROR" `
        -StepName "RemoveLicenses" `
        -Target $UserPrincipalName `
        -Message "Failed to remove licenses." `
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


$MI_ID = (Get-MgServicePrincipal -Filter "displayName eq 'OffboardingAutomation' and servicePrincipalType eq 'ManagedIdentity'").Id

$AppRoleID = "dc50a0fb-09a3-484d-be87-e023b12c6440"

$ResourceID = (Get-MgServicePrincipal -Filter "AppId eq '00000002-0000-0ff1-ce00-000000000000'").Id

New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $MI_ID -PrincipalId $MI_ID -AppRoleId $AppRoleID -ResourceId $ResourceID