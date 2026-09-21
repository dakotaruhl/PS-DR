# ============================================================
# Convert Display Names to UPNs using Microsoft Graph
# Reads columns: Apply Hold, Remove Hold, Keep Hold Active
# Writes new sheet with UPN values
# ============================================================

# -----------------------------
# Config
# -----------------------------
$ExcelPath = "C:\Users\DakotaRuhl\Downloads\Salesforce Profiles.xlsx"
$InputSheet = "Power Users"
$OutputSheet = "Power Users UPNs"

# -----------------------------
# Modules
# -----------------------------
Import-Module ImportExcel -ErrorAction Stop
Import-Module Microsoft.Graph.Users -ErrorAction Stop

# -----------------------------
# Connect to Graph
# -----------------------------
$Thumbprint = "C47B91EB62634CA61FA8146DDA83B8BF605C0962"
$ClientID = "ea2ca49b-d0df-4774-b611-86cf9dc9629f"
$TenantID = "0bdf0e1f-a359-4b5c-9b79-9357e35ff8c6"
Connect-MgGraph -ClientId $ClientID -TenantId $TenantID -CertificateThumbprint $Thumbprint

# -----------------------------
# Read Excel
# -----------------------------
$Rows = Import-Excel -Path $ExcelPath -WorksheetName $InputSheet

# -----------------------------
# Helper: Resolve Display Name
# -----------------------------
function Resolve-UserUPN {
    param([string]$DisplayName)

    if ([string]::IsNullOrWhiteSpace($DisplayName)) {
        return $null
    }

    try {
        # exact match first (fast filter)
        $Users = Get-MgUser -Filter "displayName eq '$($DisplayName.Replace("'","''"))'" -ConsistencyLevel eventual -CountVariable count -All

        if ($Users.Count -eq 1) {
            return [PSCustomObject]@{
                UPN    = $Users.UserPrincipalName
                Status = "Found"
                Note   = ""
            }
        }
        elseif ($Users.Count -gt 1) {
            # fallback: contains match for visibility
            $AltUsers = Get-MgUser -Search "displayName:$DisplayName" -ConsistencyLevel eventual -All

            return [PSCustomObject]@{
                UPN    = ($AltUsers | Select-Object -First 3 | ForEach-Object {$_.UserPrincipalName}) -join ";"
                Status = "MultipleMatches"
                Note   = "$($Users.Count) exact matches"
            }
        }
        else {
            return [PSCustomObject]@{
                UPN    = $null
                Status = "NotFound"
                Note   = ""
            }
        }
    }
    catch {
        return [PSCustomObject]@{
            UPN    = $null
            Status = "Error"
            Note   = $_.Exception.Message
        }
    }
}

# -----------------------------
# Process rows
# -----------------------------
$Output = foreach ($Row in $Rows) {

    $Apply   = Resolve-UserUPN $Row.'Apply Hold'
    $Remove  = Resolve-UserUPN $Row.'Remove Hold'
    $Keep    = Resolve-UserUPN $Row.'Keep Hold Active'

    [PSCustomObject]@{
        # Original values (optional but useful)
        ApplyHold_DisplayName        = $Row.'Apply Hold'
        RemoveHold_DisplayName       = $Row.'Remove Hold'
        KeepHoldActive_DisplayName   = $Row.'Keep Hold Active'

        # Resolved UPNs
        ApplyHold_UPN                = $Apply.UPN
        RemoveHold_UPN               = $Remove.UPN
        KeepHoldActive_UPN           = $Keep.UPN

        # Status columns
        Apply_Status                 = $Apply.Status
        Remove_Status                = $Remove.Status
        Keep_Status                  = $Keep.Status

        # Notes (for troubleshooting duplicates/errors)
        Apply_Note                   = $Apply.Note
        Remove_Note                  = $Remove.Note
        Keep_Note                    = $Keep.Note
    }
}

# -----------------------------
# Export to new sheet
# -----------------------------
$Output | Export-Excel `
    -Path $ExcelPath `
    -WorksheetName $OutputSheet `
    -AutoSize `
    -TableName "ResolvedUPNs" `
    -ClearSheet

Write-Host ""
Write-Host "Completed. New sheet '$OutputSheet' created with UPN mappings." -ForegroundColor Green