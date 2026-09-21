Get-Mailbox ConfRoom-101 | Select AuditEnabled

Connect-ExchangeOnline

# Get calendar folder ID
$mbx = "badlands@enchantedrock.com"
$cal = Get-MailboxFolderStatistics $mbx |
  Where-Object {$_.FolderType -eq "Calendar"}

# Pull recent meeting items
Search-Mailbox -Identity $mbx `
  -SearchQuery 'kind:meetings' `
  -TargetMailbox $mbx `
  -TargetFolder "CalendarAuditTemp" `
  -LogOnly `
  -LogLevel Full

  #set start date to 4:00pm today to avoid pulling in old meetings
Search-UnifiedAuditLog `
  -StartDate (Get-Date).Date.AddHours(16) `
  -EndDate (Get-Date) `
  -RecordType ExchangeItem `
  -Operations Update `
  -ResultSize 5000 |
Where-Object {
  $_.AuditData -like "*Calendar*"
}



$Subject = "Paul Froutan"

Search-UnifiedAuditLog `
  -StartDate (Get-Date).Date.AddHours(16) `
  -EndDate (Get-Date) `
  -RecordType ExchangeItem `
  -Operations Update `
  -ResultSize 5000 `
  -FreeText "\Calendar" |
ForEach-Object {
  $data = $_.AuditData | ConvertFrom-Json

  if (
    $data.Item.ParentFolder.Path -eq "\Calendar" -and
    $data.Item.Subject -eq $Subject -and
    -not $data.Item.OccurrenceId -and
    -not (
      $data.ModifiedProperties.Count -eq 1 -and
      $data.ModifiedProperties[0] -eq "AttachmentCollection"
    )
  ) {
    [PSCustomObject]@{
      LocalTime = ([datetime]$data.CreationTime).ToLocalTime()
      Subject   = $data.Item.Subject
      Actor     = $data.ActorInfoString
      UserId    = $data.UserId
      Props     = ($data.ModifiedProperties -join ", ")
    }
  }
} | Sort-Object LocalTime -Descending


Get-CalendarDiagnosticObjects `
  -Identity badlands@enchantedrock.com `
  -Subject "Paul Froutan" `
  -ExactMatch $true `
  -ShouldBindToItem $true |
Where-Object {
  [datetime]::Parse($_.EndTime.ToString()) -gt (Get-Date) -and
  $_.IsRecurring -eq $true -and
  $_.CalendarItemType -eq "RecurringMaster"
} |
Select `
  Subject,
  Organizer,
  @{n="StartTime";e={[datetime]::Parse($_.StartTime.ToString())}},
  @{n="EndTime";e={[datetime]::Parse($_.EndTime.ToString())}},
  @{n="LastModifiedTime";e={[datetime]::Parse($_.LastModifiedTime.ToString())}} |
Sort-Object LastModifiedTime -Descending
