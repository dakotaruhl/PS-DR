#Connect-ExchangeOnline

$excelData = Import-Excel -path ".\Input Data\MailEnabledSG-ImportGroupMembersTemplate.xlsx"
$group = get-distributiongroup -Identity $excelData[0].groupEmail -ErrorAction SilentlyContinue

foreach ($row in $excelData) {

    #Check if they are member of group
    try {
        $member = get-distributiongroupmember -Identity $group.PrimarySmtpAddress -ResultSize Unlimited | Where-Object {$_.PrimarySmtpAddress -eq $row.UPN}
    }
    catch {
        Write-Host "Error checking membership for $($row.UPN) in $($group.DisplayName). Error: $_" -ForegroundColor Red
        continue
    }


    if ($member) {
        Write-Host "$($row.UPN) is already a member of $($group.DisplayName). Skipping." -ForegroundColor Yellow
        continue
    }
    else {
        Try {
            Add-DistributionGroupMember -Identity $group.PrimarySmtpAddress -Member $row.UPN
            Write-Host "Added $($row.UPN) to $($group.DisplayName)" -ForegroundColor Green
        }
        Catch {
            Write-Host "Failed to add $($row.UPN) to $($group.DisplayName). Error: $_" -ForegroundColor Red
        }
    }
}
