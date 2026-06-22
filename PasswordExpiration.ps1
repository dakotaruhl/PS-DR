$params = @{
    passwordPolicies = "DisablePasswordExpiration"
}

Update-MgUser -UserId svc_fat_ipads@enchantedrock.com -BodyParameter $params


Update-MgUser -UserId svc_fat_ipads@enchantedrock.com -BodyParameter @{
    passwordPolicies = "None"
}


Update-MgUser -UserId svc_fat_ipads@enchantedrock.com -BodyParameter @{
    passwordPolicies = "DisablePasswordExpiration"
}


Get-MgUser -UserId svc_fat_ipads@enchantedrock.com | Select PasswordPolicies



$user = "svc_fat_ipads@enchantedrock.com"

# Step 1: explicitly set None
Update-MgUser -UserId $user -PasswordPolicies "None"

# Step 2: set DisablePasswordExpiration
Update-MgUser -UserId $user -PasswordPolicies "DisablePasswordExpiration"

# Step 3: verify FULL object (not Select)
Get-MgUser -UserId $user | fl PasswordPolicies