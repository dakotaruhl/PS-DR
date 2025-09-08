# save this file as ScheduleUpdate_Count.ps1

param (
  [Parameter(Mandatory=$true)][string]$ImportPath,
  [Parameter(Mandatory=$true)][string]$ExportPath,
  [Parameter(Mandatory=$true)][int]$MajorVersionLimit
)

$Report = Import-Csv -Path $ImportPath 

$PreviousWebId = [Guid]::Empty
$PreviousDocId = [Guid]::Empty
$PreviousWebUrl = [string]::Empty
$PreviousFileUrl = [string]::Empty
$PreviousModifiedByUserId = [string]::Empty
$PreviousModifiedByDisplayName = [string]::Empty

$FileToVersions = @{}

foreach ($Version in $Report)
{  
  $WebId = [string]::IsNullOrEmpty($Version."WebId.Compact") ? $PreviousWebId : [Guid]::Parse($Version."WebId.Compact")
  $DocId = [string]::IsNullOrEmpty($Version."DocId.Compact") ? $PreviousDocId : [Guid]::Parse($Version."DocId.Compact")
  $WebUrl = [string]::IsNullOrEmpty($Version."WebUrl.Compact") ? $PreviousWebUrl : $Version."WebUrl.Compact"
  $FileUrl = [string]::IsNullOrEmpty($Version."FileUrl.Compact") ? $PreviousFileUrl : $Version."FileUrl.Compact"
  $ModifiedByUserId = [string]::IsNullOrEmpty($Version."ModifiedBy_UserId.Compact") ? $PreviousModifiedByUserId : $Version."ModifiedBy_UserId.Compact"
  $ModifiedByDisplayName = [string]::IsNullOrEmpty($Version."ModifiedBy_DisplayName.Compact") ? $PreviousModifiedByDisplayName : $Version."ModifiedBy_DisplayName.Compact"

  $PreviousWebId = $WebId
  $PreviousDocId = $DocId
  $PreviousWebUrl = $WebUrl
  $PreviousFileUrl = $FileUrl
  $PreviousModifiedByUserId = $ModifiedByUserId
  $PreviousModifiedByDisplayName = $ModifiedByDisplayName

  if (($PreviousWebId -eq [Guid]::Empty) -or ($WebId -eq [Guid]::Empty) -or 
    ($PreviousDocId -eq [Guid]::Empty) -or ($DocId -eq [Guid]::Empty))
  {
    throw "Compact column error."
  }

  $Version."WebId.Compact" = $WebId
  $Version."DocId.Compact" = $DocId
  $Version."WebUrl.Compact" = $WebUrl
  $Version."FileUrl.Compact" = $FileUrl
  $Version."ModifiedBy_UserId.Compact" = $ModifiedByUserId
  $Version."ModifiedBy_DisplayName.Compact" = $ModifiedByDisplayName
   
  if ($null -eq $FileToVersions[$DocId]) 
  {
    $FileToVersions[$DocId] = [System.Collections.Generic.PriorityQueue[Object, Int32]]::new()
  }

  $VersionsQueue = $FileToVersions[$DocId]

  $VersionNumber = [Int32]::Parse($Version.MajorVersion) * 512 + [Int32]::Parse($Version.MinorVersion)
  $VersionsQueue.Enqueue($Version, -$VersionNumber)
}

$Schedule = [System.Collections.Generic.List[Object]]::new()

foreach ($FilesAndVersions in $FileToVersions.GetEnumerator())
{
  $VersionsQueue = $FilesAndVersions.Value
  $NumMajorVersionsSeen = 0
  while ($VersionsQueue.Count -gt 0)
  {
    $Version = $VersionsQueue.Dequeue()
    if ($NumMajorVersionsSeen -ge $MajorVersionLimit) {
      $Version.TargetExpirationDate = [DateTime]::new(2000, 1, 1).ToString("yyyy-MM-ddTHH:mm:ssK")
    }
     
    if ([int]::Parse($Version.MinorVersion) -eq 0) { $NumMajorVersionsSeen++ }

    $Schedule.Add($Version)
  }
}

$Schedule | 
  Export-Csv -Path $ExportPath -UseQuotes AsNeeded -NoTypeInformation

# .\scheduleUpdate_Count.ps1 -importpath "C:\Users\DakotaRuhl\Documents\Reports\VersionStorageUsageReport_OMLibrary.csv" -ExportPath "C:\Users\DakotaRuhl\Documents\Reports\WhatIf200Count_O&M.csv" -MajorVersionLimit 200