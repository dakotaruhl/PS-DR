#Requires -Version 7.4
#Requires -Modules PnP.PowerShell, ImportExcel

[CmdletBinding()]
param(
    [string]$SiteUrl = 'https://enchantedrock.sharepoint.com/sites/safety',

    [string]$DeletedByName = 'Samuel Stell',

    [ValidateRange(1, 1000)]
    [int]$BatchSize = 200,

    [ValidateRange(0, 10)]
    [int]$MaxRetries = 5,

    [ValidateRange(0, 300)]
    [int]$DelayBetweenBatchesSeconds = 2,

    [ValidateRange(0, 300)]
    [int]$VerificationDelaySeconds = 5,

    [string]$OutputDirectory =
        'C:\Users\DakotaRuhl\Documents\Reports\RecycleBin'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region Functions

function Connect-SharePointPnP {
    [CmdletBinding()]
    param()

    Write-Host "Connecting to $SiteUrl..."

    Connect-PnPOnline `
        -Url $SiteUrl `
        -ClientId $env:AZURE_CLIENT_ID `
        -Tenant $env:AZURE_TENANT_ID `
        -Thumbprint $script:CertificateThumbprint `
        -ReturnConnection `
        -ErrorAction Stop
}

function Get-RemainingRecycleBinIds {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Ids,

        [Parameter(Mandatory)]
        [PnP.PowerShell.Commands.Base.PnPConnection]$Connection
    )

    if ($Ids.Count -eq 0) {
        return [string[]]@()
    }

    $targetIdLookup =
        [System.Collections.Generic.HashSet[string]]::new(
            $Ids,
            [System.StringComparer]::OrdinalIgnoreCase
        )

    $remainingIds =
        [System.Collections.Generic.HashSet[string]]::new(
            [System.StringComparer]::OrdinalIgnoreCase
        )

    $currentFirstStage = @(
        Get-PnPRecycleBinItem `
            -FirstStage `
            -Connection $Connection `
            -ErrorAction Stop
    )

    foreach ($item in $currentFirstStage) {
        $itemId = $item.Id.ToString()

        if ($targetIdLookup.Contains($itemId)) {
            $null = $remainingIds.Add($itemId)
        }
    }

    $currentSecondStage = @(
        Get-PnPRecycleBinItem `
            -SecondStage `
            -Connection $Connection `
            -ErrorAction Stop
    )

    foreach ($item in $currentSecondStage) {
        $itemId = $item.Id.ToString()

        if ($targetIdLookup.Contains($itemId)) {
            $null = $remainingIds.Add($itemId)
        }
    }

    return [string[]]@($remainingIds)
}

#endregion Functions

#region Initialization

$transcriptStarted = $false
$scriptSucceeded = $false

try {
    $requiredEnvironmentVariables = @(
        'AZURE_CLIENT_ID'
        'AZURE_TENANT_ID'
        'AZURE_CLIENT_CERTIFICATE_THUMBPRINT'
    )

    foreach ($variableName in $requiredEnvironmentVariables) {
        $variableValue = [Environment]::GetEnvironmentVariable($variableName)

        if ([string]::IsNullOrWhiteSpace($variableValue)) {
            throw "Required environment variable is missing or empty: $variableName"
        }
    }

    $script:CertificateThumbprint =
        $env:AZURE_CLIENT_CERTIFICATE_THUMBPRINT.Replace(' ', '').Trim()

    $certificate = Get-Item `
        -LiteralPath "Cert:\LocalMachine\My\$script:CertificateThumbprint" `
        -ErrorAction SilentlyContinue

    if ($null -eq $certificate) {
        throw "Certificate not found in Cert:\LocalMachine\My\$script:CertificateThumbprint"
    }

    if (-not $certificate.HasPrivateKey) {
        throw "Certificate $script:CertificateThumbprint does not have an accessible private key."
    }

    if ($certificate.NotAfter -le (Get-Date)) {
        throw "Certificate $script:CertificateThumbprint expired on $($certificate.NotAfter)."
    }

    if ($certificate.NotAfter -le (Get-Date).AddDays(14)) {
        Write-Warning "Certificate expires soon: $($certificate.NotAfter)"
    }

    if (-not (Test-Path -LiteralPath $OutputDirectory)) {
        $null = New-Item `
            -Path $OutputDirectory `
            -ItemType Directory `
            -Force
    }

    Import-Module PnP.PowerShell -ErrorAction Stop
    Import-Module ImportExcel -ErrorAction Stop

    $pnpModule = Get-Module PnP.PowerShell |
        Sort-Object Version -Descending |
        Select-Object -First 1

    if ($null -eq $pnpModule) {
        throw 'PnP.PowerShell was imported but is not visible in the current session.'
    }

    Write-Host "Using PnP.PowerShell $($pnpModule.Version)"
    Write-Host "Module path: $($pnpModule.Path)"

    $restoreCommand = Get-Command `
        -Name Restore-PnPRecycleBinItem `
        -Module PnP.PowerShell `
        -ErrorAction Stop

    if (-not $restoreCommand.Parameters.ContainsKey('IdList')) {
        throw (
            "Loaded PnP.PowerShell version $($pnpModule.Version) from " +
            "'$($pnpModule.Path)', but Restore-PnPRecycleBinItem does not " +
            'contain the required -IdList parameter.'
        )
    }

    Write-Host 'Confirmed: Restore-PnPRecycleBinItem supports -IdList.'

    $runStamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $safeDeletedByName = $DeletedByName -replace '[^\w.-]', '-'

    $reportPath = Join-Path `
        $OutputDirectory `
        "RecycleBinReport-$safeDeletedByName-$runStamp.xlsx"

    $checkpointPath = Join-Path `
        $OutputDirectory `
        "RestoreCheckpoint-$safeDeletedByName.csv"

    $failurePath = Join-Path `
        $OutputDirectory `
        "RestoreFailures-$safeDeletedByName-$runStamp.csv"

    $transcriptPath = Join-Path `
        $OutputDirectory `
        "RestoreTranscript-$safeDeletedByName-$runStamp.log"

    Start-Transcript -Path $transcriptPath -Force
    $transcriptStarted = $true

    #region Connection

    $connection = Connect-SharePointPnP

    $web = Get-PnPWeb `
        -Includes Title, Url `
        -Connection $connection `
        -ErrorAction Stop

    Write-Host "Connected to: $($web.Title)"
    Write-Host "Site URL: $($web.Url)"

    #endregion Connection

    #region Discovery and reporting

    Write-Host 'Retrieving first-stage recycle bin items...'
    $recycleBinItemsFirstStage = @(
        Get-PnPRecycleBinItem `
            -FirstStage `
            -Connection $connection `
            -ErrorAction Stop
    )

    Write-Host 'Retrieving second-stage recycle bin items...'
    $recycleBinItemsSecondStage = @(
        Get-PnPRecycleBinItem `
            -SecondStage `
            -Connection $connection `
            -ErrorAction Stop
    )

    $firstStageMatches = @(
        $recycleBinItemsFirstStage |
            Where-Object {
                $_.DeletedByName -eq $DeletedByName
            }
    )

    $secondStageMatches = @(
        $recycleBinItemsSecondStage |
            Where-Object {
                $_.DeletedByName -eq $DeletedByName
            }
    )

    $reportProperties = @(
        'Id'
        'LeafName'
        'Title'
        'DirName'
        'ItemType'
        'DeletedDate'
        'DeletedByName'
        'DeletedByEmail'
        'Size'
    )

    if ($firstStageMatches.Count -gt 0) {
        $firstStageMatches |
            Select-Object $reportProperties |
            Export-Excel `
                -Path $reportPath `
                -WorksheetName 'FirstStage' `
                -AutoSize `
                -FreezeTopRow `
                -AutoFilter
    }

    if ($secondStageMatches.Count -gt 0) {
        $secondStageExportParameters = @{
            Path          = $reportPath
            WorksheetName = 'SecondStage'
            AutoSize      = $true
            FreezeTopRow  = $true
            AutoFilter    = $true
        }

        if (Test-Path -LiteralPath $reportPath) {
            $secondStageExportParameters.Append = $true
        }

        $secondStageMatches |
            Select-Object $reportProperties |
            Export-Excel @secondStageExportParameters
    }

    $allMatches = @(
        @(
            $firstStageMatches |
                Select-Object *, @{ Name = 'Stage'; Expression = { 'FirstStage' } }
        )

        @(
            $secondStageMatches |
                Select-Object *, @{ Name = 'Stage'; Expression = { 'SecondStage' } }
        )
    )

    $allMatches = @(
        $allMatches |
            Group-Object { $_.Id.ToString() } |
            ForEach-Object {
                $_.Group | Select-Object -First 1
            }
    )

    Write-Host ''
    Write-Host "First-stage matches:  $($firstStageMatches.Count)"
    Write-Host "Second-stage matches: $($secondStageMatches.Count)"
    Write-Host "Unique total matches: $($allMatches.Count)"
    Write-Host "Report: $reportPath"
    Write-Host ''

    if ($allMatches.Count -eq 0) {
        throw "No recycle bin items were found for '$DeletedByName'."
    }

    #endregion Discovery and reporting

    #region Resume checkpoint and actionable target set

    $completedIdLookup =
        [System.Collections.Generic.HashSet[string]]::new(
            [System.StringComparer]::OrdinalIgnoreCase
        )

    if (Test-Path -LiteralPath $checkpointPath -PathType Leaf) {
        foreach ($checkpointRecord in @(Import-Csv -LiteralPath $checkpointPath)) {
            if (
                $null -ne $checkpointRecord.Id -and
                -not [string]::IsNullOrWhiteSpace($checkpointRecord.Id)
            ) {
                $null = $completedIdLookup.Add(
                    $checkpointRecord.Id.ToString()
                )
            }
        }

        Write-Host "Loaded $($completedIdLookup.Count) completed IDs from checkpoint."
    }

    $excludedFolderItems = @(
        $allMatches |
            Where-Object {
                $_.ItemType -eq 'Folder'
            }
    )

    $actionableItems = @(
        $allMatches |
            Where-Object {
                $_.ItemType -ne 'Folder'
            }
    )

    $pendingItems = @(
        $actionableItems |
            Where-Object {
                -not $completedIdLookup.Contains($_.Id.ToString())
            } |
            Sort-Object DeletedDate, DirName, LeafName
    )

    $totalMatchedRecords = $allMatches.Count
    $totalActionableItems = $actionableItems.Count
    $alreadyCompleted = $totalActionableItems - $pendingItems.Count
    $totalPending = $pendingItems.Count

    Write-Host "Matching recycle-bin records: $totalMatchedRecords"
    Write-Host "Folder records excluded:      $($excludedFolderItems.Count)"
    Write-Host "Actionable non-folder items: $totalActionableItems"
    Write-Host "Already completed:           $alreadyCompleted"
    Write-Host "Pending restore:             $totalPending"
    Write-Host ''

    if ($totalPending -eq 0) {
        Write-Host 'Nothing remains to restore.'
        $scriptSucceeded = $true
        return
    }

    #endregion Resume checkpoint and actionable target set

    #region Restore

    $totalBatches = [int][math]::Ceiling(
        $totalPending / [double]$BatchSize
    )

    $successfulItems = 0
    $failedItems = 0
    $processedPendingItems = 0
    $totalBatchSeconds = 0.0
    $overallStart = Get-Date

    for (
        $offset = 0;
        $offset -lt $totalPending;
        $offset += $BatchSize
    ) {
        $batchNumber = [int]($offset / $BatchSize) + 1

        $batchItems = @(
            $pendingItems |
                Select-Object -Skip $offset -First $BatchSize
        )

        [string[]]$batchIds = @(
            $batchItems |
                ForEach-Object {
                    $_.Id.ToString()
                }
        )

        $batchStart = Get-Date
        $lastErrorMessage = $null
        [string[]]$idsStillPending = $batchIds
        [string[]]$verifiedRestoredIds = @()

        for (
            $attempt = 1;
            $attempt -le ($MaxRetries + 1);
            $attempt++
        ) {
            try {
                Write-Host (
                    'Restoring batch {0}/{1}, attempt {2}, items remaining {3}...' -f
                    $batchNumber,
                    $totalBatches,
                    $attempt,
                    $idsStillPending.Count
                )

                Restore-PnPRecycleBinItem `
                    -IdList $idsStillPending `
                    -Connection $connection `
                    -ErrorAction Stop

                if ($VerificationDelaySeconds -gt 0) {
                    Start-Sleep -Seconds $VerificationDelaySeconds
                }

                [string[]]$remainingAfterRestore = @(
                    Get-RemainingRecycleBinIds `
                        -Ids $idsStillPending `
                        -Connection $connection
                )

                $remainingLookup =
                    [System.Collections.Generic.HashSet[string]]::new(
                        $remainingAfterRestore,
                        [System.StringComparer]::OrdinalIgnoreCase
                    )

                [string[]]$restoredThisAttempt = @(
                    $idsStillPending |
                        Where-Object {
                            -not $remainingLookup.Contains($_)
                        }
                )

                $verifiedRestoredIds = [string[]]@(
                    $verifiedRestoredIds
                    $restoredThisAttempt
                ) | Select-Object -Unique

                $idsStillPending = $remainingAfterRestore

                Write-Host (
                    'Verified restored this attempt: {0}; non-folder items still pending: {1}' -f
                    $restoredThisAttempt.Count,
                    $idsStillPending.Count
                )

                if ($idsStillPending.Count -eq 0) {
                    break
                }

                $lastErrorMessage =
                    "$($idsStillPending.Count) non-folder IDs remained in the recycle bin after attempt $attempt."

                Write-Warning $lastErrorMessage
            }
            catch {
                $lastErrorMessage = $_.Exception.Message

                Write-Warning (
                    'Batch {0}, attempt {1} failed: {2}' -f
                    $batchNumber,
                    $attempt,
                    $lastErrorMessage
                )
            }

            if ($attempt -gt $MaxRetries) {
                break
            }

            $retryDelaySeconds = [int][math]::Min(
                300,
                [math]::Pow(2, $attempt) * 5
            )

            Write-Host "Waiting $retryDelaySeconds seconds before retry..."
            Start-Sleep -Seconds $retryDelaySeconds

            try {
                $connection = Connect-SharePointPnP

                $null = Get-PnPWeb `
                    -Connection $connection `
                    -ErrorAction Stop

                Write-Host 'PnP connection refreshed.'
            }
            catch {
                Write-Warning (
                    'Reconnection attempt failed: {0}' -f
                    $_.Exception.Message
                )
            }
        }

        $restoredIdLookup =
            [System.Collections.Generic.HashSet[string]]::new(
                $verifiedRestoredIds,
                [System.StringComparer]::OrdinalIgnoreCase
            )

        $failedIdLookup =
            [System.Collections.Generic.HashSet[string]]::new(
                $idsStillPending,
                [System.StringComparer]::OrdinalIgnoreCase
            )

        $verifiedRestoredItems = @(
            $batchItems |
                Where-Object {
                    $restoredIdLookup.Contains($_.Id.ToString())
                }
        )

        $verifiedFailedItems = @(
            $batchItems |
                Where-Object {
                    $failedIdLookup.Contains($_.Id.ToString())
                }
        )

        $successfulItems += $verifiedRestoredItems.Count
        $failedItems += $verifiedFailedItems.Count

        if ($verifiedRestoredItems.Count -gt 0) {
            $checkpointRecords = foreach ($item in $verifiedRestoredItems) {
                [pscustomobject]@{
                    Id            = $item.Id.ToString()
                    Stage         = $item.Stage
                    LeafName      = $item.LeafName
                    DirName       = $item.DirName
                    ItemType      = $item.ItemType
                    DeletedDate   = $item.DeletedDate
                    DeletedByName = $item.DeletedByName
                    RestoredAt    = Get-Date
                    BatchNumber   = $batchNumber
                    Verified      = $true
                    Status        = 'VerifiedRestored'
                }
            }

            $checkpointRecords |
                Export-Csv `
                    -LiteralPath $checkpointPath `
                    -NoTypeInformation `
                    -Append

            foreach ($record in $checkpointRecords) {
                $null = $completedIdLookup.Add($record.Id)
            }
        }

        if ($verifiedFailedItems.Count -gt 0) {
            $failureRecords = foreach ($item in $verifiedFailedItems) {
                [pscustomobject]@{
                    Id            = $item.Id.ToString()
                    Stage         = $item.Stage
                    LeafName      = $item.LeafName
                    DirName       = $item.DirName
                    ItemType      = $item.ItemType
                    DeletedDate   = $item.DeletedDate
                    DeletedByName = $item.DeletedByName
                    BatchNumber   = $batchNumber
                    Attempts      = $MaxRetries + 1
                    Error         = $lastErrorMessage
                    FailedAt      = Get-Date
                }
            }

            $failureRecords |
                Export-Csv `
                    -LiteralPath $failurePath `
                    -NoTypeInformation `
                    -Append
        }

        $batchElapsed = (Get-Date) - $batchStart
        $totalBatchSeconds += $batchElapsed.TotalSeconds
        $processedPendingItems += $batchItems.Count

        $completedIncludingPrevious =
            $alreadyCompleted + $successfulItems

        $percentComplete = [math]::Round(
            ($processedPendingItems / [double]$totalPending) * 100,
            2
        )

        $processedBatchCount = $batchNumber
        $averageBatchSeconds =
            $totalBatchSeconds / [math]::Max($processedBatchCount, 1)

        $remainingBatches = $totalBatches - $processedBatchCount
        $estimatedSecondsRemaining =
            $averageBatchSeconds * $remainingBatches

        $eta = [TimeSpan]::FromSeconds(
            [math]::Max(0, $estimatedSecondsRemaining)
        )

        $elapsed = (Get-Date) - $overallStart

        $etaText = '{0:00}:{1:00}:{2:00}' -f
            [int]$eta.TotalHours,
            $eta.Minutes,
            $eta.Seconds

        $elapsedText = '{0:00}:{1:00}:{2:00}' -f
            [int]$elapsed.TotalHours,
            $elapsed.Minutes,
            $elapsed.Seconds

        Write-Progress `
            -Activity 'Restoring SharePoint recycle bin items' `
            -Status (
                'Batch {0}/{1} | Examined {2}/{3} pending | ' +
                'Verified this run: {4} | Failed this run: {5} | ' +
                'Completed overall: {6}/{7} actionable | Elapsed: {8} | ETA: {9}' -f
                $batchNumber,
                $totalBatches,
                $processedPendingItems,
                $totalPending,
                $successfulItems,
                $failedItems,
                $completedIncludingPrevious,
                $totalActionableItems,
                $elapsedText,
                $etaText
            ) `
            -PercentComplete $percentComplete `
            -Id 1

        if (
            $DelayBetweenBatchesSeconds -gt 0 -and
            $batchNumber -lt $totalBatches
        ) {
            Start-Sleep -Seconds $DelayBetweenBatchesSeconds
        }
    }

    Write-Progress -Completed -Id 1

    #endregion Restore

    #region Summary

    $overallElapsed = (Get-Date) - $overallStart

    Write-Host ''
    Write-Host 'Restore run completed.'
    Write-Host "Matching records:          $totalMatchedRecords"
    Write-Host "Folder records excluded:   $($excludedFolderItems.Count)"
    Write-Host "Actionable non-folders:    $totalActionableItems"
    Write-Host "Previously completed:      $alreadyCompleted"
    Write-Host "Verified restored this run: $successfulItems"
    Write-Host "Failed this run:           $failedItems"
    Write-Host "Elapsed:                   $overallElapsed"
    Write-Host "Checkpoint:                $checkpointPath"
    Write-Host "Failures:                  $failurePath"
    Write-Host "Transcript:                $transcriptPath"
    Write-Host "Discovery report:          $reportPath"

    if ($failedItems -gt 0) {
        throw "$failedItems non-folder items remain in failed batches. Review $failurePath and rerun the script."
    }

    $scriptSucceeded = $true

    #endregion Summary
}
finally {
    Write-Progress -Completed -Id 1 -ErrorAction SilentlyContinue

    if ($transcriptStarted) {
        try {
            Stop-Transcript | Out-Null
        }
        catch {
            Write-Warning "Unable to stop transcript cleanly: $($_.Exception.Message)"
        }
    }

    if (-not $scriptSucceeded) {
        Write-Warning 'The restore script did not complete successfully. Review the transcript and failure CSV before rerunning.'
    }
}
