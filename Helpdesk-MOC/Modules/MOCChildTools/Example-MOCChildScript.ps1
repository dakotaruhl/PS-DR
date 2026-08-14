<#
.SYNOPSIS
Example MOC child script using MOCChildTools.

.DESCRIPTION
Shows the minimum pattern for using the shared helper module from a child script.

.VERSION
1.0.0

.AUTHOR
Long

.CATEGORY
Template

.OUTPUTFORMAT
XLSX

.REQUIREDPOWERSHELLMODULES
Microsoft.Graph.Authentication
ImportExcel

.REQUIREDGRAPHAPPSCOPES
None
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)][switch]$UseExistingSession,
    [Parameter(Mandatory = $false)][switch]$SkipConnect,
    [Parameter(Mandatory = $false)][switch]$DoNotOpenOutput,
    [Parameter(Mandatory = $false)][string]$ReportsRoot
)

$ModulePath = Join-Path $script:MOC_RootPath 'Modules\MOCChildTools\MOCChildTools.psd1'
Import-Module $ModulePath -Force -DisableNameChecking 

$Run = Initialize-MOCChildRun `
    -ScriptPath $PSCommandPath `
    -ScriptRoot $PSScriptRoot `
    -ReportsRoot $ReportsRoot `
    -RunFolderPrefix 'Custom-Report' `
    -TotalSteps 4 `
    -UseExistingSession:$UseExistingSession `
    -DoNotOpenOutput:$DoNotOpenOutput

$script:RunSucceeded = $false

try {
    $Choice = Read-ChildMenuChoice `
        -Title 'Example Export Options' `
        -Options @('1. Export all rows','2. Export filtered rows','3. Export summary only') `
        -Prompt 'Select export option' `
        -ValidChoices @('1','2','3') `
        -DefaultChoice '1' `
        -AllowExit

    if ($Choice -eq 'ExitToMenu') {
        Write-ChildStatusLine 'User selected exit. Returning to MOC menu without creating a report.'
        return
    }

    Update-ChildProgress -Activity $Run.ScriptName -Percent 0 -Status 'Starting' -CurrentOperation ''
    Write-ChildOutputLine 'ERock M365 Operations Console (MOC)' -Level Header
    Write-ChildOutputLine $Run.ScriptName -Level Header
    Write-ChildOutputLine ('Run started:   {0}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
    Write-ChildOutputLine ('Output folder: {0}' -f (Get-ReportDisplayPath -Path $Run.ReportsDir))
    Write-ChildTranscriptLine ('Full output folder: {0}' -f $Run.ReportsDir)

    Invoke-ScriptStep -StepNumber 1 -Name 'Initialize script' -ScriptBlock {
        Write-ChildStatusLine 'Initialization completed.'
    }

    Invoke-ScriptStep -StepNumber 2 -Name 'Validate parent session' -ScriptBlock {
        if ($script:MOC_Authenticated -eq $true -or $UseExistingSession) {
            Write-ChildStatusLine 'Reusing parent MOC authentication session.'
        }
        elseif ($SkipConnect) {
            Write-ChildStatusLine 'Connection validation skipped by parameter.'
        }
        else {
            throw 'Parent MOC authentication session was not detected. Authenticate from the MOC menu and try again.'
        }
    }

    Invoke-ScriptStep -StepNumber 3 -Name 'Collect evidence' -ScriptBlock {
        $Rows = @(
            [pscustomobject][ordered]@{ Name = 'Example Item 1'; Status = 'Review'; Notes = 'Replace this sample data with real audit output.' },
            [pscustomobject][ordered]@{ Name = 'Example Item 2'; Status = 'OK'; Notes = 'Second sample row.' }
        )

        Add-WorkbookWorksheet -Name 'Example Report' -Rows $Rows -ColumnOrder @('Name','Status','Notes') -Description 'Example worksheet showing how to stage rows for the final workbook.'
        Update-ChildProgress -Activity $Run.ScriptName -Percent 75 -Status 'Step 3 of 4 - Collect evidence' -CurrentOperation 'Processed example rows.'
    }

    Invoke-ScriptStep -StepNumber 4 -Name 'Finalize outputs' -ScriptBlock {
        Export-MOCWorkbook -OpenAfterExport | Out-Null
        Complete-MOCChildRun -ExportAuditNotes | Out-Null
    }

    $script:RunSucceeded = $true
    Update-ChildProgress -Activity $Run.ScriptName -Percent 100 -Status 'Completed successfully. Press Enter to return to the menu.' -CurrentOperation ''

    $FinalRun = Get-MOCChildState
    Write-ChildOutputLine ''
    Write-ChildOutputLine 'Run Summary' -Level Header
    Write-ChildOutputLine '===========' -Level Header
    Write-ChildOutputLine ("Workbook: {0}" -f $FinalRun.WorkbookPath)
    Write-ChildOutputLine ("Output folder: {0}" -f $FinalRun.ReportsDir)
}
catch {
    Update-ChildProgress -Activity $Run.ScriptName -Percent 100 -Status 'Failed. Press Enter to return to the menu.' -CurrentOperation ''
    Write-ChildOutputLine ''
    Write-ChildOutputLine ("ERROR: {0}" -f $_.Exception.Message) -Level Error
    Write-ChildTranscriptLine ($_.ScriptStackTrace | Out-String)
    throw
}
finally {
    # Parent MOC owns transcripts, service disconnects, and terminal rendering.
}
