Connect-MicrosoftTeams

get-csteamsmeetingpolicy -identity tag:transcriptions | FL

get-csteamsmeetingpolicy | Where-Object {$_.AutoRecording -eq "Enabled"} | select Identity, AutoRecording
get-csteamsmeetingpolicy | Where-Object {$_.AutoRecording -eq "Enabled"} | select Identity, AutoRecording, RecordingStorageMode