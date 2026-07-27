<#
.SYNOPSIS
    Creates Entra ID security groups from an Excel workbook and assigns an owner.

.DESCRIPTION
    Reads two sheets from a single .xlsx file and creates a security group for each row:
      - 'Role Descriptions' : group name from "User Role",  description from "Description"
      - 'Companies'         : group name from "Group Name", description from "Description"

    If -OwnerUPN is supplied, that user is set as owner on every group the script
    touches. Owner assignment is idempotent: for groups that already exist, the script
    adds the owner only if they are not already an owner. This means you can re-run the
    script purely to backfill owners on groups that were created by an earlier run.
    Supports -WhatIf.

.PARAMETER Path
    Full path to the source .xlsx workbook.

.PARAMETER TenantId
    Entra tenant ID to connect to.

.PARAMETER OwnerUPN
    UPN of the user to set as owner on each group (e.g. jdoe@enchantedrock.com).
    Optional. If omitted, no owner is assigned.

.EXAMPLE
    .\New-SecurityGroupsFromExcel.ps1 -OwnerUPN jdoe@enchantedrock.com -WhatIf

.NOTES
    Requires modules: ImportExcel, Microsoft.Graph.Groups, Microsoft.Graph.Users, Microsoft.Graph.Authentication
    Required Graph app permissions: Group.ReadWrite.All, User.Read.All (admin consent)
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $false)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$Path = 'C:\Users\DakotaRuhl\Documents\PS-DR\Input Data\BCGroups.xlsx',

    [Parameter(Mandatory = $false)]
    [string]$TenantId = "0bdf0e1f-a359-4b5c-9b79-9357e35ff8c6",

    [Parameter(Mandatory = $false)]
    [bool]$mailEnabled = $false,

    [Parameter(Mandatory = $false)]
    [string]$OwnerUPN = "ballen@erock.com"
)

## Azure AD App Registration Details ##
$Thumbprint = "C47B91EB62634CA61FA8146DDA83B8BF605C0962"
$ClientID   = "ea2ca49b-d0df-4774-b611-86cf9dc9629f"

# Connect to Microsoft Graph using the app registration credentials
Connect-MgGraph `
    -ClientId $ClientID `
    -TenantId $TenantId `
    -CertificateThumbprint $Thumbprint

# --- Config: sheet name -> column that holds the group name -----------------
$SheetMap = @(
    [pscustomobject]@{ Sheet = 'Role Descriptions'; NameColumn = 'User Role'  ; DescColumn = 'Description' }
    [pscustomobject]@{ Sheet = 'Companies'        ; NameColumn = 'Group Name' ; DescColumn = 'Description' }
)

# --- Dependency check -------------------------------------------------------
foreach ($module in 'ImportExcel', 'Microsoft.Graph.Groups', 'Microsoft.Graph.Users') {
    if (-not (Get-Module -ListAvailable -Name $module)) {
        throw "Required module '$module' is not installed. Run: Install-Module $module -Scope CurrentUser"
    }
}

# --- Helpers ----------------------------------------------------------------
function New-MailNickname {
    # Mail nickname must be unique and contain no spaces or reserved characters.
    param([string]$DisplayName)
    $clean = ($DisplayName -replace '[^a-zA-Z0-9]', '').Trim()
    if ([string]::IsNullOrWhiteSpace($clean)) { $clean = 'group' }
    return ('{0}-{1}' -f $clean, ([guid]::NewGuid().ToString('N').Substring(0, 6)))
}

function Set-GroupOwner {
    # Adds $OwnerId as an owner of $GroupId only if not already present. Idempotent.
    param(
        [Parameter(Mandatory)][string]$GroupId,
        [Parameter(Mandatory)][string]$OwnerId
    )
    $current = Get-MgGroupOwner -GroupId $GroupId -All -ErrorAction Stop
    if ($current.Id -contains $OwnerId) {
        return 'Owner already set'
    }
    $ref = @{ '@odata.id' = "https://graph.microsoft.com/v1.0/directoryObjects/$OwnerId" }
    New-MgGroupOwnerByRef -GroupId $GroupId -BodyParameter $ref -ErrorAction Stop
    return 'Owner added'
}

# --- Resolve owner UPN to object ID (once) ----------------------------------
$OwnerId = $null
if ($OwnerUPN) {
    try {
        $OwnerId = (Get-MgUser -UserId $OwnerUPN -Property 'id' -ErrorAction Stop).Id
        Write-Host "Owner resolved: $OwnerUPN -> $OwnerId" -ForegroundColor Cyan
    }
    catch {
        throw "Could not resolve OwnerUPN '$OwnerUPN': $($_.Exception.Message)"
    }
}

# Cache existing groups once (name -> id) to avoid a lookup per row.
Write-Host 'Loading existing groups for duplicate check...' -ForegroundColor Cyan
$existing = @{}
Get-MgGroup -All -Property 'id', 'displayName' |
    ForEach-Object { $existing[$_.DisplayName.Trim().ToLower()] = $_.Id }

# --- Process each sheet -----------------------------------------------------
$results = [System.Collections.Generic.List[object]]::new()

foreach ($map in $SheetMap) {

    Write-Host "`nProcessing sheet '$($map.Sheet)'..." -ForegroundColor Cyan

    try {
        $rows = Import-Excel -Path $Path -WorksheetName $map.Sheet -ErrorAction Stop
    }
    catch {
        Write-Warning "Could not read sheet '$($map.Sheet)': $($_.Exception.Message)"
        continue
    }

    foreach ($row in $rows) {

        $name = ($row.$($map.NameColumn) | Out-String).Trim()
        $desc = ($row.$($map.DescColumn) | Out-String).Trim()

        # Skip blank / empty rows.
        if ([string]::IsNullOrWhiteSpace($name)) { continue }

        $key = $name.ToLower()

        # --- Group already exists: do not recreate, but backfill owner if asked.
        if ($existing.ContainsKey($key)) {
            if ($OwnerId) {
                if ($PSCmdlet.ShouldProcess($name, "Ensure owner '$OwnerUPN'")) {
                    try {
                        $ownerStatus = Set-GroupOwner -GroupId $existing[$key] -OwnerId $OwnerId
                        Write-Host "  EXISTS '$name' -> $ownerStatus" -ForegroundColor Yellow
                        $results.Add([pscustomobject]@{ Sheet = $map.Sheet; Group = $name; Status = "Exists ($ownerStatus)" })
                    }
                    catch {
                        Write-Warning "  FAIL owner on existing '$name': $($_.Exception.Message)"
                        $results.Add([pscustomobject]@{ Sheet = $map.Sheet; Group = $name; Status = "Exists (owner failed: $($_.Exception.Message))" })
                    }
                }
            }
            else {
                Write-Host "  SKIP  '$name' (already exists)" -ForegroundColor Yellow
                $results.Add([pscustomobject]@{ Sheet = $map.Sheet; Group = $name; Status = 'Skipped (exists)' })
            }
            continue
        }

        # --- New group.
        if ($PSCmdlet.ShouldProcess($name, 'Create security group')) {
            try {
                $params = @{
                    DisplayName     = $name
                    Description     = if ($desc) { $desc } else { $null }
                    MailEnabled     = $mailEnabled
                    MailNickname    = (New-MailNickname -DisplayName $name)
                    SecurityEnabled = $true
                }

                $newGroup = New-MgGroup @params -ErrorAction Stop
                $existing[$key] = $newGroup.Id   # prevent same-name dupes across sheets

                $status = 'Created'
                if ($OwnerId) {
                    $ownerStatus = Set-GroupOwner -GroupId $newGroup.Id -OwnerId $OwnerId
                    $status = "Created ($ownerStatus)"
                }

                Write-Host "  OK    '$name' -> $status" -ForegroundColor Green
                $results.Add([pscustomobject]@{ Sheet = $map.Sheet; Group = $name; Status = $status })
            }
            catch {
                Write-Warning "  FAIL  '$name': $($_.Exception.Message)"
                $results.Add([pscustomobject]@{ Sheet = $map.Sheet; Group = $name; Status = "Failed: $($_.Exception.Message)" })
            }
        }
        else {
            $results.Add([pscustomobject]@{ Sheet = $map.Sheet; Group = $name; Status = 'WhatIf' })
        }
    }
}

# --- Summary ----------------------------------------------------------------
Write-Host "`n===== Summary =====" -ForegroundColor Cyan
$results | Format-Table -AutoSize
Disconnect-MgGraph | Out-Null
