# ============================================================
# Convert Display Name -> UPN
# Input: Excel with "Display Name" column
# Output: New sheet with UPNs
# ============================================================

# -----------------------------
# Config
# -----------------------------
$ExcelPath  = "C:\Users\DakotaRuhl\Downloads\Salesforce Profiles.xlsx"
$InputSheet = "ERock - Standard"
$OutputSheet = "$($InputSheet) UPN"

# -----------------------------
# Modules
# -----------------------------
Import-Module ImportExcel -ErrorAction Stop
Import-Module Microsoft.Graph.Users -ErrorAction Stop

# -----------------------------
# Connect to Graph
# -----------------------------
$Thumbprint = "C47B91EB62634CA61FA8146DDA83B8BF605C0962"
$ClientID   = "ea2ca49b-d0df-4774-b611-86cf9dc9629f"
$TenantID   = "0bdf0e1f-a359-4b5c-9b79-9357e35ff8c6"

Connect-MgGraph -ClientId $ClientID -TenantId $TenantID -CertificateThumbprint $Thumbprint

# -----------------------------
# Read Excel
# -----------------------------
$Rows = Import-Excel -Path $ExcelPath -WorksheetName $InputSheet

# -----------------------------
# Resolve Display Name -> UPN
# -----------------------------
function Resolve-UserUPN {
    param([string]$DisplayName)

    if ([string]::IsNullOrWhiteSpace($DisplayName)) {
        return [PSCustomObject]@{
            UPN    = $null
            Status = "Empty"
        }
    }

    try {
        $safe = $DisplayName.Replace("'", "''")

        $Users = Get-MgUser `
            -Filter "displayName eq '$safe'" `
            -ConsistencyLevel eventual `
            -CountVariable count `
            -All

        if ($Users.Count -eq 1) {
            return [PSCustomObject]@{
                UPN    = $Users.UserPrincipalName
                Status = "Found"
            }
        }
        elseif ($Users.Count -gt 1) {
            return [PSCustomObject]@{
                UPN    = ($Users | Select-Object -First 3 -ExpandProperty UserPrincipalName) -join ";"
                Status = "Multiple"
            }
        }
        else {
            return [PSCustomObject]@{
                UPN    = $null
                Status = "NotFound"
            }
        }
    }
    catch {
        return [PSCustomObject]@{
            UPN    = $null
            Status = "Error"
        }
    }
}

# -----------------------------
# Process
# -----------------------------
$Output = foreach ($Row in $Rows) {

    $result = Resolve-UserUPN $Row.'Display Name'

    [PSCustomObject]@{
        DisplayName = $Row.'Display Name'
        UPN         = $result.UPN
        Status      = $result.Status
    }
}

# -----------------------------
# Export
# -----------------------------
$TableName = "$($OutputSheet)_Results" -replace '[^a-zA-Z0-9_]', '_'

$Output | Export-Excel `
    -Path $ExcelPath `
    -WorksheetName $OutputSheet `
    -AutoSize `
    -TableName $TableName `
    -ClearSheet

Write-Host "Completed. Sheet '$OutputSheet' created." -ForegroundColor Green