@{
    RootModule = 'MOCChildTools.psm1'
    ModuleVersion = '1.0.0'
    GUID = '3b13c423-cb92-458e-b232-f301d7f5dd07'
    Author = 'Long'
    CompanyName = 'Enchanted Rock'
    Copyright = '(c) Enchanted Rock. All rights reserved.'
    Description = 'Reusable MOC child-script helpers for metadata, MOC-safe output, prompts, run state, audit notes, and Excel workbook exports.'
    PowerShellVersion = '7.0'
    RequiredModules = @()
    FunctionsToExport = @(
        'Get-MOCChildState',
        'Get-MOCScriptMetadata',
        'Initialize-MOCChildRun',
        'Write-ChildOutputLine',
        'Write-ChildStatusLine',
        'Write-ChildTranscriptLine',
        'Update-ChildProgress',
        'Get-ReportDisplayPath',
        'Read-ChildText',
        'Read-ChildMenuChoice',
        'Get-MOCGraphConnectionMode',
        'Assert-MOCGraphPermission',
        'Add-AuditNote',
        'Set-MOCUtf8FileContent',
        'Export-AuditCsv',
        'ConvertTo-ExcelSafeText',
        'ConvertTo-ExcelSafeValue',
        'ConvertTo-ExcelSafeRows',
        'Get-SafeExcelWorksheetName',
        'Get-SafeExcelTableName',
        'Add-WorkbookWorksheet',
        'Assert-ImportExcelAvailable',
        'Get-WorkbookSummaryRows',
        'Set-MOCWorkbookStyle',
        'Export-MOCWorkbook',
        'Open-MOCOutputFile',
        'Invoke-ScriptStep',
        'Complete-MOCChildRun'
    )
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
    PrivateData = @{
        PSData = @{
            Tags = @('MOC','Reporting','Excel','Audit')
            ProjectUri = ''
            ReleaseNotes = 'Initial module extracted from MOC child-script skeleton. Preserves original function names, including unapproved verbs.'
        }
    }
}
