Connect-ExchangeOnline


Connect-MgGraph -Scopes "Group.ReadWrite.All","Calendars.ReadWrite"

$GroupId = "2775d79c-5894-4306-89ce-b033b32a78b2"

$MeetingIds = @(
    "<MEETING-ID-1>",
    "<MEETING-ID-2>"
)

foreach ($id in $MeetingIds) {
    Update-MgGroupCalendarEvent `
        -GroupId $GroupId `
        -EventId "24162895129546" `
        -BodyParameter @{
            body = @{
                contentType = "HTML"
                content = " "   # harmless nudge
            }
        }
}


##WORKS
$Event = Get-MgGroupCalendarEvent -GroupId $GroupId | Where-Object Subject -eq "Reoccurring Meeting test"

update-mggroupcalendarevent -GroupId $GroupId -EventId $Event.Id -BodyParameter @{
    body = @{
        contentType = "HTML"
        content = " "   # harmless nudge
    }
}
