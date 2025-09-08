# save this file as ScheduleUpdate_ExpireAfter.ps1

param (
  [Parameter(Mandatory=$false)][string]$ImportPath,
  [Parameter(Mandatory=$false)][string]$ExportPath,
  [Parameter(Mandatory=$false)][double]$ExpireAfter
)

function StringToDateTime($Value) { return [string]::IsNullOrEmpty($Value) ? $null : [DateTime]::ParseExact($Value, "yyyy-MM-ddTHH:mm:ssK", $null) }
function DateTimeToString($Value) { return $null -eq $Value ? "" : $Value.ToString("yyyy-MM-ddTHH:mm:ssK") }  

$Schedule = Import-Csv -Path $ImportPath 
$Schedule | 
  ForEach-Object { 
    $SnapshotDate = StringToDateTime -Value $_.SnapshotDate
    $TargetExpirationDate = $SnapshotDate.AddDays($ExpireAfter)
    $_.TargetExpirationDate = DateTimeToString -Value $TargetExpirationDate
  } 
$Schedule | 
  Export-Csv -Path $ExportPath -UseQuotes AsNeeded -NoTypeInformation