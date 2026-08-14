<#
.SYNOPSIS
Export Example Report

.DESCRIPTION
Example MOC child script skeleton using the shared MOCChildTools module.

.VERSION
1.0.0

.AUTHOR
Long

.CATEGORY
Reporting

.OUTPUTFORMAT
XLSX

.REQUIREDPOWERSHELLMODULES
Microsoft.Graph.Authentication
ImportExcel

.CREATED
2026-08-14

.LASTMODIFIED
2026-08-14

.REQUIREDGRAPHAPPSCOPES
User.Read.All
Group.Read.All

.CHANGELOG
v1.0.0
- Initial version.

.NOTES
CUSTOMIZATION CHECKLIST

1. Update metadata.
2. Update $RunFolderPrefix.
3. Update $TotalSteps.
4. Add parameters.
5. Replace sample Invoke-ScriptStep blocks.
6. Add worksheets using Add-WorkbookWorksheet.
7. Export workbook using Export-MOCWorkbook.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$UseExistingSession,

    [Parameter(Mandatory = $false)]
    [switch]$SkipConnect,

    [Parameter(Mandatory = $false)]
    [switch]$DoNotOpenOutput,

    [Parameter(Mandatory = $false)]
    [string]$ReportsRoot
)

############################################################################
# Load MOCChildTools
############################################################################

$ModulePath = Join-Path $script:MOC_RootPath 'Modules\MOCChildTools\MOCChildTools.psd1'

if (-not (Test-Path $ModulePath)) {
    throw "MOCChildTools module not found: $ModulePath"
}

Import-Module $ModulePath -Force -DisableNameChecking

############################################################################
# Script Configuration
############################################################################

$RunFolderPrefix = 'Example-Report'
$TotalSteps = 4

$Run = Initialize-MOCChildRun `
    -ScriptPath $PSCommandPath `
    -ScriptRoot $PSScriptRoot `
    -ReportsRoot $ReportsRoot `
    -RunFolderPrefix $RunFolderPrefix `
    -TotalSteps $TotalSteps `
    -UseExistingSession:$UseExistingSession `
    -DoNotOpenOutput:$DoNotOpenOutput

############################################################################
# Main
############################################################################

try {

    Invoke-ScriptStep `
        -StepNumber 1 `
        -Name 'Validate Session' `
        -ScriptBlock {

            if ($script:MOC_Authenticated -eq $true -or $UseExistingSession) {
                Write-ChildStatusLine 'Parent session detected.'
            }
            elseif (-not $SkipConnect) {
                throw 'Authenticate from the MOC menu first.'
            }

            Assert-MOCGraphPermission
        }

    Invoke-ScriptStep `
        -StepNumber 2 `
        -Name 'Collect Data' `
        -ScriptBlock {

            $Rows = @(
                [pscustomobject]@{
                    Name   = 'Example'
                    Status = 'OK'
                }
            )

            Add-WorkbookWorksheet `
                -Name 'Results' `
                -Rows $Rows `
                -ColumnOrder @(
                    'Name',
                    'Status'
                ) `
                -Description 'Example output.'
        }

    Invoke-ScriptStep `
        -StepNumber 3 `
        -Name 'Generate Workbook' `
        -ScriptBlock {

            Export-MOCWorkbook `
                -Path $Run.WorkbookPath `
                -OpenAfterExport
        }

    Invoke-ScriptStep `
        -StepNumber 4 `
        -Name 'Finalize Outputs' `
        -ScriptBlock {

            Complete-MOCChildRun `
                -ExportAuditNotes
        }

    Update-ChildProgress `
        -Activity $Run.ScriptName `
        -Percent 100 `
        -Status 'Completed successfully.'
}
catch {

    Update-ChildProgress `
        -Activity $Run.ScriptName `
        -Percent 100 `
        -Status 'Failed.'

    Write-ChildOutputLine `
        -Level Error `
        -Message $_.Exception.Message

    throw
}
finally {
    # Parent MOC owns transcripts, service disconnects, and terminal rendering.
}