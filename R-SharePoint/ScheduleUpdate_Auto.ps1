<# 
This script will generate a report detailing what would happen if automatic versioning was enabled for a document library or site, given a Version Usage report.
#>

# save this file as ScheduleUpdate_Auto.ps1 

param (
  [Parameter(Mandatory=$true)][string]$ImportPath,
  [Parameter(Mandatory=$true)][string]$ExportPath
)

$Schedule = Import-Csv -Path $ImportPath 
$Schedule |
  ForEach-Object {
    $_.TargetExpirationDate = $_.AutomaticPolicyExpirationDate
  }
$Schedule |
  Export-Csv -Path $ExportPath -UseQuotes AsNeeded -NoTypeInformation

  <#
  $libraryName = "Building Management"
  $importPath = "C:\Users\DakotaRuhl\Documents\Reports\VersionStorage\Usage Reports\VersionStorageUsageReport_$libraryName.csv"
  $exportPath = "C:\Users\DakotaRuhl\Documents\Reports\VersionStorage\What if Reports\WhatIfAuto_$libraryName.csv"  

  To run this report, include mandatory parameters for ImportPath and ExportPath. Example:
    .\ScheduleUpdate_Auto.ps1 -ImportPath "C:\Path\To\VersionUsageReport.csv" -ExportPath "C:\Path\To\ScheduleUpdateReport.csv"

    .\ScheduleUpdate_Auto.ps1 -ImportPath $importPath -ExportPath $exportPath
  #>

