function Test-UserSharePointGroupRemoval {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$UserPrincipalName
    )

    Write-Host "Connecting to Microsoft Graph…" -ForegroundColor Cyan

    Connect-MgGraph -Scopes @(
        "Sites.Read.All",
        "Sites.Manage.All",
        "Directory.Read.All"
    ) -ErrorAction Stop

    Import-Module Microsoft.Graph.Beta -ErrorAction Stop

    # Retrieve user
    $user = Get-MgUser -UserId $UserPrincipalName -ErrorAction Stop

    Write-Host "Retrieving all SharePoint Online sites…" -ForegroundColor Cyan

    # Retrieve all sites
    $sites = Get-MgSite -Search "*" -ConsistencyLevel eventual -All
    $siteCount = $sites.Count
    $siteIndex = 0

    $results = @()

    foreach ($site in $sites) {
        $siteIndex++

        # MAIN PROGRESS BAR
        Write-Progress `
            -Id 1 `
            -Activity "Scanning SharePoint Sites" `
            -Status "Processing site ${siteIndex} of ${siteCount}: $($site.Name)" `
            -PercentComplete (($siteIndex / $siteCount) * 100)

        Write-Host "`nScanning Site: $($site.Name) [$($site.Id)]" -ForegroundColor Yellow

        try {
            # SharePoint group permissions require Beta endpoint
            $permissions = Get-MgBetaSitePermission -SiteId $site.Id -ErrorAction Stop
        }
        catch {
            Write-Host "  ⚠ Could not retrieve permissions for this site. Skipping." -ForegroundColor DarkYellow
            continue
        }

        # Sub-progress for group scanning
        $groupIndex = 0
        $groupCount = $permissions.Count

        foreach ($perm in $permissions) {
            $groupIndex++

            # GROUP PROGRESS BAR
            Write-Progress `
                -Id 2 `
                -ParentId 1 `
                -Activity "Scanning groups in site: $($site.Name)" `
                -Status "Checking group ${groupIndex} of ${groupCount}" `
                -PercentComplete (($groupIndex / $groupCount) * 100)

            # Groups appear as grantees with type "group"
            $groupGrantees = $perm.Grantees | Where-Object { $_.Type -eq "group" }

            foreach ($grantee in $groupGrantees) {
                try {
                    $members = Get-MgBetaGroupMember -GroupId $grantee.Id -All -ErrorAction Stop
                }
                catch {
                    Write-Host "    ⚠ Failed to retrieve members for group $($grantee.DisplayName)" -ForegroundColor DarkYellow
                    continue
                }

                if ($members.Id -contains $user.Id) {
                    $obj = [PSCustomObject]@{
                        SiteName   = $site.Name
                        SiteId     = $site.Id
                        GroupName  = $grantee.DisplayName
                        GroupId    = $grantee.Id
                    }

                    $results += $obj

                    Write-Host "    ➤ USER FOUND in group: $($grantee.DisplayName)" -ForegroundColor Green
                }
            }
        }

        # Clear group progress before moving to new site
        Write-Progress -Id 2 -Completed
    }

    # Clear overall progress
    Write-Progress -Id 1 -Completed

    Write-Host "`n========== TEST RESULTS ==========" -ForegroundColor Cyan

    if ($results.Count -eq 0) {
        Write-Host "User is not a member of ANY SharePoint group in ANY site." -ForegroundColor Green
    }
    else {
        $results | Format-Table -AutoSize
    }

    Write-Host "===================================" -ForegroundColor Cyan

    return $results
}


Test-UserSharePointGroupRemoval -UserPrincipalName "test.user@enchantedrock.com"