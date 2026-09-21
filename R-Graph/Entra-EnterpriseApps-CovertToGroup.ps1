#Requires -Modules Microsoft.Graph.Authentication
#Requires -Modules Microsoft.Graph.Applications
#Requires -Modules Microsoft.Graph.Groups
#Requires -Modules Microsoft.Graph.Users

param(
    [string]$EnterpriseAppName = "Adobe Identity Management (OIDC)",
    [string]$GroupDisplayName = "Adobe-Provisioning-Users",
    [string]$OutputFolder = "C:\Users\DakotaRuhl\Documents\PS-DR\output"
)

# ---------------------------------------------------------------------
# Connect Graph
# ---------------------------------------------------------------------

$script:ErockGraph = @{
    TenantId              = "0bdf0e1f-a359-4b5c-9b79-9357e35ff8c6"
    ClientId              = "ea2ca49b-d0df-4774-b611-86cf9dc9629f"
    CertificateThumbprint = "C47B91EB62634CA61FA8146DDA83B8BF605C0962"
}

function Connect-ErockGraph
{
    [CmdletBinding()]
    param()

    $context = Get-MgContext -ErrorAction SilentlyContinue

    if ($context -and
        $context.TenantId -eq $script:ErockGraph.TenantId -and
        $context.ClientId -eq $script:ErockGraph.ClientId)
    {
        try
        {
            $null = Get-MgOrganization -ErrorAction Stop
            Write-Verbose "Existing Graph connection is valid."
            return
        }
        catch
        {
            Write-Verbose "Context exists but token invalid. Reconnecting."
            Disconnect-MgGraph -ErrorAction SilentlyContinue
        }
    }

    Write-Verbose "Connecting to Microsoft Graph..."
    Connect-MgGraph @script:ErockGraph -NoWelcome

    $context = Get-MgContext
    if (-not $context -or
        $context.TenantId -ne $script:ErockGraph.TenantId -or
        $context.ClientId -ne $script:ErockGraph.ClientId)
    {
        throw "Failed to establish the expected Microsoft Graph connection."
    }

    Write-Verbose "Connected to tenant $($context.TenantId)."
}

Connect-ErockGraph

# ---------------------------------------------------------------------
# Create output folder
# ---------------------------------------------------------------------

$null = New-Item -Path $OutputFolder -ItemType Directory -Force

# ---------------------------------------------------------------------
# Find Enterprise Application
# ---------------------------------------------------------------------

$servicePrincipal = Get-MgServicePrincipal `
    -Filter "displayName eq '$EnterpriseAppName'"

if (-not $servicePrincipal)
{
    throw "Enterprise application '$EnterpriseAppName' not found."
}

Write-Host "Found Enterprise Application: $($servicePrincipal.DisplayName)"
Write-Host "Service Principal Id: $($servicePrincipal.Id)"

# ---------------------------------------------------------------------
# Get all app assignments
# ---------------------------------------------------------------------

$assignments = Get-MgServicePrincipalAppRoleAssignedTo `
    -ServicePrincipalId $servicePrincipal.Id `
    -All 

$userAssignments = @($assignments |
    Where-Object {$_.PrincipalType -eq "User"} |
    Sort-Object PrincipalId -Unique)    

Write-Host "User assignments found: $($userAssignments.Count)"

# ---------------------------------------------------------------------
# Export direct assignments
# ---------------------------------------------------------------------

$exportUsers = @(foreach ($assignment in $userAssignments)
{
    try
    {
        $user = Get-MgUser `
            -UserId $assignment.PrincipalId `
            -Property Id,DisplayName,UserPrincipalName,AccountEnabled

        [pscustomobject]@{
            DisplayName       = $user.DisplayName
            UserPrincipalName = $user.UserPrincipalName
            UserId            = $user.Id
            AccountEnabled    = $user.AccountEnabled
        }
    }
    catch
    {
        Write-Warning "Unable to resolve user $($assignment.PrincipalId)"
    }
})

$userReportPath = Join-Path $OutputFolder "AdobeAssignedUsers.csv"

$exportUsers |
    Sort-Object UserPrincipalName |
    Export-Csv $userReportPath -NoTypeInformation

Write-Host "Exported user list:"
Write-Host $userReportPath

# ---------------------------------------------------------------------
# Create security group if needed
# ---------------------------------------------------------------------

$mailNickname = (
    $GroupDisplayName `
        -replace '[^a-zA-Z0-9]', ''
).ToLower()

$group = Get-MgGroup `
    -Filter "displayName eq '$GroupDisplayName'"

if (-not $group)
{
    Write-Host "Creating group $GroupDisplayName"

    $group = New-MgGroup `
        -DisplayName $GroupDisplayName `
        -Description "Adobe Enterprise Application Access" `
        -MailEnabled:$false `
        -SecurityEnabled:$true `
        -MailNickname $mailNickname

    # Wait for replication before writing members
        # Wait until the members endpoint is queryable, not just the group object
    $ready = $false
    $attempts = 0
    do
    {
        Start-Sleep -Seconds 3
        $attempts++
        try
        {
            $null = Get-MgGroupMember -GroupId $group.Id -Top 1 -ErrorAction Stop
            $ready = $true
        }
        catch
        {
            Write-Verbose "Group members endpoint not ready (attempt $attempts)."
        }
    }
    until ($ready -or $attempts -ge 10)

    if (-not $ready)
    {
        throw "Group $($group.Id) members endpoint did not become available."
    }
}
else
{
    Write-Host "Group already exists."
}

Write-Host "Group Id: $($group.Id)"

# ---------------------------------------------------------------------
# Add users to group
# ---------------------------------------------------------------------
function Add-GroupMemberWithRetry
{
    param(
        [string]$GroupId,
        [string]$UserId,
        [int]$MaxAttempts = 5
    )

    for ($i = 1; $i -le $MaxAttempts; $i++)
    {
        try
        {
            New-MgGroupMemberByRef -GroupId $GroupId -BodyParameter @{
                "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$($UserId)"
            }
            return $true
        }
        catch
        {
            $status = $_.Exception.Response.StatusCode.value__

            if ($status -in 404,429,503 -and $i -lt $MaxAttempts)
            {
                $wait = [math]::Pow(2, $i)
                Write-Verbose "Attempt $i failed ($status). Retrying in $wait s."
                Start-Sleep -Seconds $wait
                continue
            }
            throw
        }
    }
}

function Get-GroupMembersWithRetry
{
    param(
        [string]$GroupId,
        [int]$MaxAttempts = 5
    )

    for ($i = 1; $i -le $MaxAttempts; $i++)
    {
        try
        {
            return Get-MgGroupMember -GroupId $GroupId -All -ErrorAction Stop
        }
        catch
        {
            $status = $_.Exception.Response.StatusCode.value__
            if ($status -in 404,429,503 -and $i -lt $MaxAttempts)
            {
                $wait = [math]::Pow(2, $i)
                Write-Verbose "Get-MgGroupMember attempt $i failed ($status). Retrying in $wait s."
                Start-Sleep -Seconds $wait
                continue
            }
            throw
        }
    }
}

$addedUsers = @()
$failedUsers = @()

$currentMembers = Get-GroupMembersWithRetry -GroupId $group.Id |
    Select-Object -ExpandProperty Id

foreach ($user in $exportUsers)
{
    try
    {
        if ($user.UserId -in $currentMembers)
        {
            Write-Host "Already member: $($user.UserPrincipalName)"

            $addedUsers += [pscustomobject]@{
                UserPrincipalName = $user.UserPrincipalName
                Status = "AlreadyMember"
            }

            continue
        }

        $dirObj = Get-MgDirectoryObject -DirectoryObjectId $user.UserId -ErrorAction SilentlyContinue
        if (-not $dirObj)
        {
            Write-Warning "Skipping unresolved object: $($user.UserPrincipalName) [$($user.UserId)]"
            continue
        }
        Add-GroupMemberWithRetry -GroupId $group.Id -UserId $user.UserId

        Write-Host "Added: $($user.UserPrincipalName)"

        $addedUsers += [pscustomobject]@{
            UserPrincipalName = $user.UserPrincipalName
            Status = "Added"
        }
    }
    catch
    {
        Write-Warning "Failed to add $($user.UserPrincipalName)"

        $failedUsers += [pscustomobject]@{
            UserPrincipalName = $user.UserPrincipalName
            Error = $_.Exception.Message
        }
    }
}

# ---------------------------------------------------------------------
# Export results
# ---------------------------------------------------------------------

$addedUsers |
    Export-Csv `
        (Join-Path $OutputFolder "GroupMembershipResults.csv") `
        -NoTypeInformation

$failedUsers |
    Export-Csv `
        (Join-Path $OutputFolder "GroupMembershipFailures.csv") `
        -NoTypeInformation

$finalCount = (Get-GroupMembersWithRetry -GroupId $group.Id).Count

# ---------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------

Write-Host ""
Write-Host "=================================="
Write-Host "Migration Preparation Complete"
Write-Host "=================================="
Write-Host "Enterprise App : $EnterpriseAppName"
Write-Host "Group          : $($group.DisplayName)"
Write-Host "Users Exported : $($exportUsers.Count)"
Write-Host "Failures       : $($failedUsers.Count)"
Write-Host "Output Folder  : $OutputFolder"
Write-Host "Group Members  : $finalCount"