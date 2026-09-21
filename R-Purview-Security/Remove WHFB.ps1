Connect-MgGraph -Scopes "UserAuthenticationMethod.ReadWrite.All"
Select-MgProfile -Name "v1.0"

$userUpn = "admin-jo@enchantedrock.com"

$methods = Get-MgUserAuthenticationWindowsHelloForBusinessMethod -UserId $userUpn
$methods | Select-Object Id, DisplayName, CreatedDateTime


Get-MgUserAuthenticationWindowsHelloForBusinessMethod -UserId $userUpn |
ForEach-Object {
    Write-Host "Removing WHfB method Id=$($_.Id)" -ForegroundColor Yellow
    Remove-MgUserAuthenticationWindowsHelloForBusinessMethod `
        -UserId $userUpn `
        -WindowsHelloForBusinessAuthenticationMethodId $_.Id
}
