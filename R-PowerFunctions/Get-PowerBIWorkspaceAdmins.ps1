#requires -Version 7.2
<#
.SYNOPSIS
    Audits Power BI workspace Admin assignments across the tenant.

.DESCRIPTION
    Uses the Power BI Admin APIs to enumerate tenant workspaces and retrieve
    workspace role assignments. By default, only Admin assignments are exported.
    Use -UserPrincipalName to return only direct Admin assignments for one user.

    Important: Direct assignments are evaluated. If the user receives Admin through
    an Entra security group or Microsoft 365 group, the result shows the group, not
    the user's transitive membership.

.PREREQUISITES
    - MicrosoftPowerBIMgmt module 1.3.84 or later
    - Fabric Administrator or Power BI Administrator role
    - Power BI service administrator APIs enabled for the tenant

.EXAMPLE
    .\R-PowerFunctions\Get-PowerBIWorkspaceAdmins.ps1 `
        -UserPrincipalName "ratkinson@erock.com" `
        -OutputPath "C:\Reports\User-PowerBI-Admin-Roles.csv"
#>

[CmdletBinding()]
param(
    [Parameter()]
    [ValidatePattern('^[^@\s]+@[^@\s]+\.[^@\s]+$')]
    [string]$UserPrincipalName,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$OutputPath = (Join-Path $PWD 'PowerBI-Workspace-Admins.csv'),

    [Parameter()]
    [ValidateSet('Active', 'Deleted', 'Removing', 'All')]
    [string]$WorkspaceState = 'Active',

    [Parameter()]
    [ValidateRange(1, 200)]
    [int]$MaxRequestsPerHour = 190,

    [Parameter()]
    [switch]$IncludeAllWorkspaceRoles
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-PowerBIAdminRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RelativeUrl
    )

    $maximumAttempts = 5

    for ($attempt = 1; $attempt -le $maximumAttempts; $attempt++) {
        try {
            $json = Invoke-PowerBIRestMethod -Url $RelativeUrl -Method Get
            if ([string]::IsNullOrWhiteSpace($json)) {
                return @()
            }

            $response = $json | ConvertFrom-Json -Depth 20
            if ($null -eq $response.value) {
                return @($response)
            }

            return @($response.value)
        }
        catch {
            $statusCode = $null
            if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
                $statusCode = [int]$_.Exception.Response.StatusCode
            }

            $isRetryable = $statusCode -in 429, 500, 502, 503, 504
            if (-not $isRetryable -or $attempt -eq $maximumAttempts) {
                throw
            }

            $delaySeconds = [math]::Min(60, [math]::Pow(2, $attempt) + (Get-Random -Minimum 1 -Maximum 4))
            Write-Warning "Power BI API request failed with HTTP $statusCode. Retrying in $delaySeconds seconds."
            Start-Sleep -Seconds $delaySeconds
        }
    }
}

if (-not (Get-Module -ListAvailable -Name MicrosoftPowerBIMgmt.Profile)) {
    throw 'MicrosoftPowerBIMgmt is not installed. Run: Install-Module MicrosoftPowerBIMgmt -Scope CurrentUser'
}

$installedVersion = Get-Module -ListAvailable -Name MicrosoftPowerBIMgmt.Profile |
    Sort-Object Version -Descending |
    Select-Object -First 1 -ExpandProperty Version

if ($installedVersion -lt [version]'1.3.84') {
    throw "MicrosoftPowerBIMgmt $installedVersion is installed. Upgrade to 1.3.84 or later."
}

$minimumDelaySeconds = [math]::Ceiling(3600 / $MaxRequestsPerHour)
$connected = $false

try {
    # MicrosoftPowerBIMgmt/MSAL can emit harmless authority-type warnings during
    # interactive authentication. Suppress warnings only for the connection call.
    Connect-PowerBIServiceAccount -WarningAction SilentlyContinue | Out-Null
    $connected = $true

    Write-Host 'Retrieving tenant workspaces...'
    $workspaces = @(
        Get-PowerBIWorkspace -Scope Organization -All |
            Where-Object {
                # Exclude personal "My workspace" workspaces
                $_.Type -ne 'PersonalGroup'
            }
    )

    if ($WorkspaceState -ne 'All') {
        $workspaces = @(
            $workspaces |
                Where-Object State -eq $WorkspaceState
        )
    }

    Write-Host "Auditing $($workspaces.Count) workspace(s)."
    Write-Host "Admin API pacing is set to no more than $MaxRequestsPerHour requests per hour."

    $results = [System.Collections.Generic.List[object]]::new()

    for ($index = 0; $index -lt $workspaces.Count; $index++) {
        $workspace = $workspaces[$index]
        $progressPercent = if ($workspaces.Count -gt 0) {
            [math]::Round((($index + 1) / $workspaces.Count) * 100)
        }
        else { 100 }

        Write-Progress `
            -Activity 'Auditing Power BI workspace administrators' `
            -Status "$($index + 1) of $($workspaces.Count): $($workspace.Name)" `
            -PercentComplete $progressPercent

        try {
            $encodedWorkspaceId = [uri]::EscapeDataString([string]$workspace.Id)
            $assignments = @(Invoke-PowerBIAdminRequest -RelativeUrl "admin/groups/$encodedWorkspaceId/users")

            foreach ($assignment in $assignments) {
                if (-not $IncludeAllWorkspaceRoles -and $assignment.groupUserAccessRight -ne 'Admin') {
                    continue
                }

                if ($UserPrincipalName) {
                    $candidateIdentifiers = @(
                        [string]$assignment.emailAddress
                        [string]$assignment.identifier
                    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

                    $isMatch = $candidateIdentifiers | Where-Object {
                        $_.Equals($UserPrincipalName, [System.StringComparison]::OrdinalIgnoreCase)
                    }

                    if (-not $isMatch) {
                        continue
                    }
                }

                $results.Add([pscustomobject]@{
                    WorkspaceName    = $workspace.Name
                    WorkspaceId      = $workspace.Id
                    WorkspaceState   = $workspace.State
                    WorkspaceType    = $workspace.Type
                    IsOnDedicatedCapacity = $workspace.IsOnDedicatedCapacity
                    CapacityId       = $workspace.CapacityId
                    DisplayName      = $assignment.displayName
                    EmailAddress     = $assignment.emailAddress
                    Identifier       = $assignment.identifier
                    GraphId          = $assignment.graphId
                    PrincipalType    = $assignment.principalType
                    AccessLevel      = $assignment.groupUserAccessRight
                    AssignmentScope  = 'Direct workspace role assignment'
                })
            }
        }
        catch {
            Write-Warning "Could not audit workspace '$($workspace.Name)' [$($workspace.Id)]: $($_.Exception.Message)"

            $results.Add([pscustomobject]@{
                WorkspaceName    = $workspace.Name
                WorkspaceId      = $workspace.Id
                WorkspaceState   = $workspace.State
                WorkspaceType    = $workspace.Type
                IsOnDedicatedCapacity = $workspace.IsOnDedicatedCapacity
                CapacityId       = $workspace.CapacityId
                DisplayName      = $null
                EmailAddress     = $null
                Identifier       = $null
                GraphId          = $null
                PrincipalType    = $null
                AccessLevel      = 'AuditError'
                AssignmentScope  = $_.Exception.Message
            })
        }

        if ($index -lt ($workspaces.Count - 1)) {
            Start-Sleep -Seconds $minimumDelaySeconds
        }
    }

    Write-Progress -Activity 'Auditing Power BI workspace administrators' -Completed

    $sortedResults = @($results | Sort-Object WorkspaceName, AccessLevel, DisplayName)
    $outputDirectory = Split-Path -Parent $OutputPath

    if ($outputDirectory -and -not (Test-Path -LiteralPath $outputDirectory)) {
        New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
    }

    $sortedResults | Export-Csv -LiteralPath $OutputPath -NoTypeInformation -Encoding utf8BOM

    if ($UserPrincipalName) {
        Write-Host "Found $($sortedResults.Count) direct matching workspace assignment(s) for $UserPrincipalName."
    }
    else {
        Write-Host "Found $($sortedResults.Count) matching workspace assignment(s)."
    }

    Write-Host "Export: $OutputPath"
    $sortedResults
}
finally {
    if ($connected) {
        Disconnect-PowerBIServiceAccount | Out-Null
    }
}
