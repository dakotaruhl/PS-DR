param (
    [Parameter(Mandatory)]
    [ValidateLength(3, 100)]
    [string]$SecretPrefix
)

# Example:
# .\R-Azure\Search-KeyVault.ps1 -SecretPrefix "U0e"

$Results = [System.Collections.Generic.List[object]]::new()

$Subscriptions = Get-AzSubscription |
    Where-Object { $_.State -eq "Enabled" }

foreach ($Subscription in $Subscriptions) {

    Write-Host ""
    Write-Host "Subscription: $($Subscription.Name)" -ForegroundColor Cyan

    Set-AzContext -SubscriptionId $Subscription.Id | Out-Null

    try {
        $Vaults = Get-AzKeyVault -ErrorAction Stop
    }
    catch {
        Write-Warning "Could not enumerate Key Vaults in $($Subscription.Name)"
        continue
    }

    foreach ($Vault in $Vaults) {

        Write-Host "  Checking vault: $($Vault.VaultName)" -ForegroundColor DarkGray

        try {
            # This retrieves metadata first, not secret values.
            $Secrets = Get-AzKeyVaultSecret `
                -VaultName $Vault.VaultName `
                -ErrorAction Stop
        }
        catch {
            Write-Warning "  Cannot enumerate secrets in $($Vault.VaultName)"
            continue
        }

        foreach ($Secret in $Secrets) {

            try {
                # Retrieve the value only for comparison.
                $SecretValue = Get-AzKeyVaultSecret `
                    -VaultName $Vault.VaultName `
                    -Name $Secret.Name `
                    -AsPlainText `
                    -ErrorAction Stop

                if (
                    $null -ne $SecretValue -and
                    $SecretValue.StartsWith(
                        $SecretPrefix,
                        [System.StringComparison]::Ordinal
                    )
                ) {

                    Write-Host "    MATCH FOUND: $($Secret.Name)" -ForegroundColor Green

                    $Results.Add(
                        [PSCustomObject]@{
                            Subscription     = $Subscription.Name
                            SubscriptionId   = $Subscription.Id
                            ResourceGroup    = $Vault.ResourceGroupName
                            KeyVault         = $Vault.VaultName
                            SecretName       = $Secret.Name
                            SecretId         = $Secret.Id
                            Enabled          = $Secret.Enabled
                            Expires          = $Secret.Expires
                        }
                    )
                }

                # Don't retain the plaintext value longer than necessary.
                $SecretValue = $null
            }
            catch {
                Write-Host "    Unable to read: $($Secret.Name)" `
                    -ForegroundColor DarkYellow
            }
        }
    }
}

Write-Host ""
Write-Host "Search complete." -ForegroundColor Cyan

if ($Results.Count -gt 0) {

    Write-Host ""
    Write-Host "Matching secrets:" -ForegroundColor Green

    $Results |
        Format-Table `
            Subscription,
            ResourceGroup,
            KeyVault,
            SecretName,
            Enabled,
            Expires `
            -AutoSize
}
else {
    Write-Host "No matching secrets found." -ForegroundColor Yellow
}