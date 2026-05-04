# Requires ExchangeOnlineManagement module
Connect-ExchangeOnline

$target = "admin@erockhold.com"

$results = Get-EXORecipient -ResultSize Unlimited `
  -Properties DisplayName,RecipientTypeDetails,PrimarySmtpAddress,EmailAddresses |
Where-Object {
  ($_.PrimarySmtpAddress -ieq $target) -or
  ($_.EmailAddresses -match ("(?i)^smtp:" + [regex]::Escape($target) + "$"))
} |
Select-Object DisplayName,RecipientTypeDetails,PrimarySmtpAddress,
  @{n="MatchedProxy";e={($_.EmailAddresses | Where-Object { $_ -match ("(?i)^smtp:" + [regex]::Escape($target) + "$") }) -join ", "}}

$results | Format-Table -AutoSize

##### Slower but more comprehensive search for the target string in various objects #####

Connect-ExchangeOnline
$target = "admin@erockhold.com"
$hit = @()

# Recipients (proxy/primary)
$hit += Get-EXORecipient -ResultSize Unlimited -Properties EmailAddresses,PrimarySmtpAddress |
Where-Object {
  $_.PrimarySmtpAddress -ieq $target -or
  ($_.EmailAddresses -match ("(?i)^smtp:" + [regex]::Escape($target) + "$"))
} | Select-Object @{n="Type";e={"Recipient"}},DisplayName,RecipientTypeDetails,PrimarySmtpAddress

# Transport rules that contain the string anywhere in the rule object
$hit += Get-TransportRule | Where-Object { $_ | Out-String -Width 5000 | Select-String -Quiet -SimpleMatch $target } |
Select-Object @{n="Type";e={"TransportRule"}},Name,@{n="Details";e={"Contains $target"}}

# Inbound/Outbound connectors (basic scan)
$hit += Get-InboundConnector | Where-Object { $_ | Out-String -Width 5000 | Select-String -Quiet -SimpleMatch $target } |
Select-Object @{n="Type";e={"InboundConnector"}},Name,@{n="Details";e={"Contains $target"}}

$hit += Get-OutboundConnector | Where-Object { $_ | Out-String -Width 5000 | Select-String -Quiet -SimpleMatch $target } |
Select-Object @{n="Type";e={"OutboundConnector"}},Name,@{n="Details";e={"Contains $target"}}

$hit | Format-Table -AutoSize
