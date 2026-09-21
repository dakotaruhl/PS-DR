Import-Module Microsoft.Graph.Authentication 
Import-Module ImportExcel

Connect-ExchangeOnline
Connect-Graph -Scopes "User.Read.All"

$DisabledUsers = Get-MgUser -Filter "accountEnabled eq false" | Select-Object DisplayName, UserPrincipalName, Mail
$ForwardingReport = @()

Foreach ($user in $DisabledUsers) {
    $mailboxexists = Get-Mailbox -Identity $user.UserPrincipalName -ErrorAction SilentlyContinue
    if (-not $mailboxexists) {
        continue
    }
    $deliverAndForwardEnabled = get-mailbox $user.userprincipalname | Select-Object UserPrincipalName, DeliverToMailboxAndForward, ForwardingSmtpAddress, ForwardingAddress
    if ($deliverAndForwardEnabled) {
        $ReportEntry = [PSCustomObject]@{
            UserPrincipalName         = $user.UserPrincipalName
            DisplayName               = $user.DisplayName
            DeliverToMailboxAndForward = $deliverAndForwardEnabled.DeliverToMailboxAndForward
            ForwardingSmtpAddress     = $deliverAndForwardEnabled.ForwardingSmtpAddress
            ForwardingAddress         = $deliverAndForwardEnabled.ForwardingAddress
        }
        $ForwardingReport += $ReportEntry
    }
}
$ReportFile = "C:\Users\DakotaRuhl\Documents\Reports\DisabledUsersForwarding\DisabledUsersForwardingReport.xlsx"
$ForwardingReport | Export-Excel -Path $ReportFile -WorkSheetname 'DisabledUsersForwarding'

