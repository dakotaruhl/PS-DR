$Thumbprint = "C47B91EB62634CA61FA8146DDA83B8BF605C0962"
$ClientID   = "ea2ca49b-d0df-4774-b611-86cf9dc9629f"
$TenantId = "0bdf0e1f-a359-4b5c-9b79-9357e35ff8c6"

# Connect to Microsoft Graph using the app registration credentials, if not already connected. For password expiration. 
$graphConnection = Get-MgContext -ErrorAction SilentlyContinue
if (-not $graphConnection) {
    Connect-MgGraph `
        -ClientId $ClientID `
        -TenantId $TenantId `
        -CertificateThumbprint $Thumbprint
}
else {
    Write-Host "Already connected to Microsoft Graph." -ForegroundColor Green
}

$userList = @()
$userList = Import-Excel -Path ".\Input Data\ContractorList.xlsx"
#$manager = "bbarr@erock.com"
#$managerUser = Get-MgUser -UserId $manager
$user = $userList[0]

ForEach ($user in $userList) {
    $displayName = $user.displayName.Trim()
    $UPN = $user.UPN.Trim()
    $mailnickname = $user.mailnickname.Trim()
    #$givenName = $user.givenName.Trim()
    #$surname = $user.surname.Trim()
    #$department = $user.department.Trim()
    #$hireDate = $user.hireDate
    $employeeType = $user.employeeType.Trim()
    $companyName = $user.companyName.Trim()
    $usageLocation = $user.usageLocation.Trim()
    $jobTitle = $user.jobTitle.Trim()
    $employeeId = $user.employeeId.Trim()
    $UserPassword = $user.Password
    $passwordProfile = @{
        Password = $UserPassword
        ForceChangePasswordNextSignIn = $false
    }

    if($user.created -eq "No") {
        Write-Host "Preparing to create contractor user: $displayName ($UPN)" -ForegroundColor Yellow

        New-MgUser -DisplayName $displayName `
                -MailNickname $mailnickname `
                -UserPrincipalName $UPN `
                -EmployeeType $employeeType `
                -CompanyName $companyName `
                -UsageLocation $usageLocation `
                -JobTitle $jobTitle `
                -EmployeeId $employeeId `
                -AccountEnabled:$true `
                -PasswordPolicies "DisablePasswordExpiration" `
                -PasswordProfile $passwordProfile | Out-Null

            #-GivenName $givenName `
            #-Surname $surname `
            #-Department $department `

        Write-Host "Created contractor user: $displayName ($UPN)"
    }
    else {
        Write-Host "Contractor user: $displayName ($UPN) already exists. Skipping creation." -ForegroundColor Yellow
    }
    
    #if ($HireDate) {
    #    Write-Host "Waiting 5 seconds" -ForegroundColor Yellow
    #    Start-Sleep -Seconds 5

    #    Write-Host "Attempting to update user" -ForegroundColor Yellow
    #    Update-MgUser `
    #        -UserId $UPN `
    #        -EmployeeHireDate $HireDate

    #    Set-MgUserManagerByRef `
    #        -UserId $UPN `
    #        -OdataId "https://graph.microsoft.com/v1.0/users/$($managerUser.Id)"
    #}    
}


New-ServicePrincipal `
    -AppId "96b011fd-9d27-4d9d-b813-078a17c8a35f" `
    -ObjectId "05f5c700-bbc6-4b75-b07f-3df9bcf105d3"

Add-MailboxPermission `
    -Identity "SSRSreport@enchantedrock.com" `
    -User "05f5c700-bbc6-4b75-b07f-3df9bcf105d3" `
    -AccessRights FullAccess `
    -InheritanceType All

    