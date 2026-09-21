#Requires -Modules ImportExcel, Microsoft.Graph.Groups, Microsoft.Graph.Users

# Connect to Graph with the needed scopes
$Thumbprint = "C47B91EB62634CA61FA8146DDA83B8BF605C0962"
$ClientID = "ea2ca49b-d0df-4774-b611-86cf9dc9629f"
$TenantID = "0bdf0e1f-a359-4b5c-9b79-9357e35ff8c6"

# --- Connect ---
Connect-MgGraph  -ClientId $ClientID -TenantId $TenantID -CertificateThumbprint $Thumbprint

# --- Config ---
$excelPath  = "C:\Users\DakotaRuhl\OneDrive - Enchanted Rock\Reports\SitePermissionsGroups\EOPUsers.xlsx"  # Update this path
$sheetName  = "Sheet2"
$groupName  = "EOPUsers"

# --- Import Excel ---
# The file has no true header row, so we import raw and grab column 1 (display names)
$rawData = Import-Excel -Path $excelPath -WorksheetName $sheetName -NoHeader
$userNames = $rawData | ForEach-Object { $_.P1 } | Where-Object { $_ -and $_.Trim() -ne "" }

Write-Host "Found $($userNames.Count) users in Excel." -ForegroundColor Cyan

# --- Resolve the target group ---
$group = Get-MgGroup -Filter "displayName eq '$groupName'" -ErrorAction Stop
if (-not $group) {
    Write-Error "Group '$groupName' not found in Entra ID. Exiting."
    return
}
Write-Host "Target group: $($group.DisplayName) ($($group.Id))" -ForegroundColor Cyan

# --- Get current group members to skip duplicates ---
$existingMembers = Get-MgGroupMember -GroupId $group.Id -All | Select-Object -ExpandProperty Id

# --- Process each user ---
$results = foreach ($name in $userNames) {
    $trimmedName = $name.Trim()

    # Look up user by DisplayName
    $user = Get-MgUser -Filter "displayName eq '$trimmedName'" -ErrorAction SilentlyContinue |
            Select-Object -First 1

    if (-not $user) {
        Write-Warning "User not found: $trimmedName"
        [PSCustomObject]@{ User = $trimmedName; Status = "NotFound" }
        continue
    }

    # Check if already a member
    if ($existingMembers -contains $user.Id) {
        Write-Host "  Already a member: $trimmedName" -ForegroundColor Yellow
        [PSCustomObject]@{ User = $trimmedName; Status = "AlreadyMember" }
        continue
    }

    # Add to group
    try {
        New-MgGroupMember -GroupId $group.Id -DirectoryObjectId $user.Id -ErrorAction Stop
        Write-Host "  Added: $trimmedName" -ForegroundColor Green
        [PSCustomObject]@{ User = $trimmedName; Status = "Added" }
    }
    catch {
        Write-Warning "  Failed to add $trimmedName : $_"
        [PSCustomObject]@{ User = $trimmedName; Status = "Error: $_" }
    }
}

# --- Summary ---
Write-Host "`n--- Summary ---" -ForegroundColor Cyan
$results | Format-Table -AutoSize

Disconnect-MgGraph