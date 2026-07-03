<#
.SYNOPSIS
    Portfolio analytics scaffold for Release 2.3.

.DESCRIPTION
    Produces a forward-compatible portfolio trend payload from the current
    portfolio assessment snapshot and, when available, SQLite maturity
    history. The scaffold is intentionally truthful:

      - If history exists in `maturity_history`, the route returns
        `trendStatus = history-backed` with daily average maturity and
        ready-repo trend series plus per-repo sparkline data.
      - If history has not been captured yet, the route still returns a
        useful `current-snapshot-only` analytics payload so the dashboard
        can render the Phase 1 scaffold without inventing fake history.

.NOTES
    Dot-source from Start-RepoManagementApiHost.ps1.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function _GetPortfolioAnalyticsField {
    param(
        [Parameter()][object]$InputObject,
        [Parameter(Mandatory = $true)][string]$PropertyName,
        [Parameter()][object]$Default = $null
    )

    if ($null -eq $InputObject -or [string]::IsNullOrWhiteSpace($PropertyName)) {
        return $Default
    }

    if ($InputObject -is [System.Collections.IDictionary]) {
        if ($InputObject.Contains($PropertyName)) {
            $value = $InputObject[$PropertyName]
            if ($null -ne $value) { return $value }
        }
        return $Default
    }

    if ($InputObject.PSObject.Properties.Name -contains $PropertyName) {
        $value = $InputObject.$PropertyName
        if ($null -ne $value) { return $value }
    }

    return $Default
}

function _GetPortfolioAnalyticsAverage {
    param(
        [Parameter()][AllowEmptyCollection()][object[]]$Entries = @(),
        [Parameter(Mandatory = $true)][string]$PropertyName
    )

    $values = [System.Collections.Generic.List[double]]::new()
    foreach ($entry in @($Entries)) {
        if ($null -eq $entry) { continue }
        $raw = _GetPortfolioAnalyticsField -InputObject $entry -PropertyName $PropertyName -Default $null
        if ($null -eq $raw) { continue }
        $number = 0.0
        if ([double]::TryParse([string]$raw, [ref]$number)) {
            $values.Add($number) | Out-Null
        }
    }

    if ($values.Count -eq 0) {
        return 0
    }

    return [int][math]::Round(($values | Measure-Object -Average).Average, 0)
}

function _NewPortfolioTrendPoint {
    param(
        [Parameter(Mandatory = $true)][string]$Date,
        [Parameter()][double]$Value = 0
    )

    return [pscustomobject]@{
        date  = $Date
        value = [math]::Round($Value, 1)
    }
}

function _GetPortfolioTrendTopCandidates {
    param(
        [Parameter()][AllowEmptyCollection()][object[]]$Assessments = @(),
        [Parameter()][int]$Limit = 5
    )

    $ranked = @($Assessments | Where-Object {
        $candidate = _GetPortfolioAnalyticsField -InputObject $_ -PropertyName 'topValueItem' -Default $null
        $candidateText = [string](_GetPortfolioAnalyticsField -InputObject $candidate -PropertyName 'text' -Default '')
        -not [string]::IsNullOrWhiteSpace($candidateText)
    } | Sort-Object `
        @{ Expression = {
            $candidate = _GetPortfolioAnalyticsField -InputObject $_ -PropertyName 'topValueItem' -Default $null
            [int](_GetPortfolioAnalyticsField -InputObject $candidate -PropertyName 'valueScore' -Default -1)
        }; Descending = $true }, `
        @{ Expression = { [int](_GetPortfolioAnalyticsField -InputObject $_ -PropertyName 'pendingItemCount' -Default 0) }; Descending = $true }, `
        @{ Expression = { [int](_GetPortfolioAnalyticsField -InputObject $_ -PropertyName 'maturityScore' -Default 0) }; Descending = $true }, `
        @{ Expression = { [string](_GetPortfolioAnalyticsField -InputObject $_ -PropertyName 'repoName' -Default '') }; Ascending = $true })

    if ($Limit -lt 1) { $Limit = 1 }
    return @($ranked | Select-Object -First $Limit)
}

function _GetPortfolioTrendHistoryRows {
    param(
        [Parameter(Mandatory = $true)][string]$DatabasePath,
        [Parameter(Mandatory = $true)][datetime]$StartUtc
    )

    return @(Invoke-AppDbQuery -DatabasePath $DatabasePath -Sql @'
SELECT
  substr(captured_at, 1, 10) AS captured_day,
  ROUND(AVG(COALESCE(maturity_score, 0)), 1) AS avg_maturity_score,
  SUM(CASE WHEN maturity_level IN ('L3-Contract-Ready', 'L4-Orchestration-Ready') AND COALESCE(pending_count, 0) > 0 THEN 1 ELSE 0 END) AS ready_repo_count,
  COUNT(*) AS repo_samples
FROM maturity_history
WHERE captured_at >= @start_utc
GROUP BY substr(captured_at, 1, 10)
ORDER BY captured_day
'@ -Parameters @{
        '@start_utc' = $StartUtc.ToString('o')
    })
}

function _GetPortfolioTrendRepoHistoryPoints {
    param(
        [Parameter(Mandatory = $true)][string]$DatabasePath,
        [Parameter(Mandatory = $true)][string]$RepoName,
        [Parameter(Mandatory = $true)][datetime]$StartUtc,
        [Parameter(Mandatory = $true)][string]$FallbackDay,
        [Parameter()][int]$FallbackScore = 0
    )

    $rows = @(Invoke-AppDbQuery -DatabasePath $DatabasePath -Sql @'
SELECT
  substr(captured_at, 1, 10) AS captured_day,
  ROUND(AVG(COALESCE(maturity_score, 0)), 1) AS maturity_score
FROM maturity_history
WHERE repo_name = @repo_name
  AND captured_at >= @start_utc
GROUP BY substr(captured_at, 1, 10)
ORDER BY captured_day
'@ -Parameters @{
        '@repo_name' = $RepoName
        '@start_utc' = $StartUtc.ToString('o')
    })

    if (@($rows).Count -eq 0) {
        return @(_NewPortfolioTrendPoint -Date $FallbackDay -Value $FallbackScore)
    }

    $points = [System.Collections.Generic.List[object]]::new()
    foreach ($row in @($rows)) {
        $points.Add((_NewPortfolioTrendPoint -Date ([string]$row.captured_day) -Value ([double]$row.maturity_score))) | Out-Null
    }

    return @($points)
}

function _GetPortfolioTrendImprovedThisWeek {
    param(
        [Parameter(Mandatory = $true)][string]$DatabasePath,
        [Parameter(Mandatory = $true)][datetime]$WeekStartUtc
    )

    $rows = @(Invoke-AppDbQuery -DatabasePath $DatabasePath -Sql @'
SELECT repo_name, maturity_score, captured_at
FROM maturity_history
WHERE captured_at >= @week_start_utc
ORDER BY repo_name, captured_at
'@ -Parameters @{
        '@week_start_utc' = $WeekStartUtc.ToString('o')
    })

    if (@($rows).Count -eq 0) {
        return 0
    }

    $groups = @{}
    foreach ($row in @($rows)) {
        $repoName = [string]$row.repo_name
        if ([string]::IsNullOrWhiteSpace($repoName)) { continue }
        if (-not $groups.ContainsKey($repoName)) {
            $groups[$repoName] = [System.Collections.Generic.List[object]]::new()
        }
        $groups[$repoName].Add($row) | Out-Null
    }

    $improved = 0
    foreach ($repoName in $groups.Keys) {
        $repoRows = @($groups[$repoName])
        if ($repoRows.Count -lt 2) { continue }

        $firstScore = [double](_GetPortfolioAnalyticsField -InputObject $repoRows[0] -PropertyName 'maturity_score' -Default 0)
        $lastScore = [double](_GetPortfolioAnalyticsField -InputObject $repoRows[$repoRows.Count - 1] -PropertyName 'maturity_score' -Default 0)
        if ($lastScore -gt $firstScore) {
            $improved++
        }
    }

    return $improved
}

function Get-PortfolioTrendPayload {
    [CmdletBinding()]
    param(
        [Parameter()][AllowEmptyCollection()][object[]]$Assessments = @(),
        [Parameter()][object]$Summary = $null,
        [Parameter(Mandatory = $true)][string]$GeneratedAt,
        [Parameter(Mandatory = $true)][ValidateSet('portfolio-index', 'assessment-cache')][string]$SeedSource,
        [Parameter(Mandatory = $true)][string]$WorkspaceRoot,
        [Parameter()][int]$RequestedDays = 90
    )

    if ($RequestedDays -lt 7) { $RequestedDays = 7 }
    if ($RequestedDays -gt 180) { $RequestedDays = 180 }

    $entryList = @($Assessments)
    $nowUtc = (Get-Date).ToUniversalTime()
    $today = $nowUtc.ToString('yyyy-MM-dd')
    $startUtc = $nowUtc.Date.AddDays(-1 * ($RequestedDays - 1))

    $byLifecycle = _GetPortfolioAnalyticsField -InputObject $Summary -PropertyName 'byLifecycle' -Default @{}
    $completedCount = [int](_GetPortfolioAnalyticsField -InputObject $byLifecycle -PropertyName 'completed' -Default 0)
    $averageMaturityScore = _GetPortfolioAnalyticsAverage -Entries $entryList -PropertyName 'maturityScore'
    $averageDocumentationHealthScore = _GetPortfolioAnalyticsAverage -Entries $entryList -PropertyName 'documentationHealthScore'

    $summaryPayload = [pscustomobject]@{
        totalRepos                       = [int](_GetPortfolioAnalyticsField -InputObject $Summary -PropertyName 'totalRepos' -Default $entryList.Count)
        readyForWorkCount                = [int](_GetPortfolioAnalyticsField -InputObject $Summary -PropertyName 'readyForWorkCount' -Default 0)
        runningCount                     = [int](_GetPortfolioAnalyticsField -InputObject $Summary -PropertyName 'runningCount' -Default 0)
        blockedCount                     = [int](_GetPortfolioAnalyticsField -InputObject $Summary -PropertyName 'blockedCount' -Default 0)
        completedCount                   = $completedCount
        averageMaturityScore             = $averageMaturityScore
        averageDocumentationHealthScore  = $averageDocumentationHealthScore
        improvedThisWeek                 = 0
    }

    $series = [System.Collections.Generic.List[object]]::new()
    $series.Add([pscustomobject]@{
        key    = 'avgMaturityScore'
        label  = 'Avg Maturity'
        color  = 'emerald'
        points = @(_NewPortfolioTrendPoint -Date $today -Value $summaryPayload.averageMaturityScore)
    }) | Out-Null
    $series.Add([pscustomobject]@{
        key    = 'readyRepos'
        label  = 'Ready Repos'
        color  = 'sky'
        points = @(_NewPortfolioTrendPoint -Date $today -Value $summaryPayload.readyForWorkCount)
    }) | Out-Null

    $topAssessments = @(_GetPortfolioTrendTopCandidates -Assessments $entryList -Limit 5)
    $topCandidates = [System.Collections.Generic.List[object]]::new()
    $repoSparklines = [System.Collections.Generic.List[object]]::new()

    foreach ($assessment in @($topAssessments)) {
        $topValueItem = _GetPortfolioAnalyticsField -InputObject $assessment -PropertyName 'topValueItem' -Default $null
        $repoName = [string](_GetPortfolioAnalyticsField -InputObject $assessment -PropertyName 'repoName' -Default '')
        $lifecycleState = [string](_GetPortfolioAnalyticsField -InputObject $assessment -PropertyName 'lifecycleState' -Default 'discovered')
        $maturityLevel = [string](_GetPortfolioAnalyticsField -InputObject $assessment -PropertyName 'maturityLevel' -Default 'L0-Absent')
        $maturityScore = [int](_GetPortfolioAnalyticsField -InputObject $assessment -PropertyName 'maturityScore' -Default 0)
        $docHealthScore = [int](_GetPortfolioAnalyticsField -InputObject $assessment -PropertyName 'documentationHealthScore' -Default 0)
        $pendingItemCount = [int](_GetPortfolioAnalyticsField -InputObject $assessment -PropertyName 'pendingItemCount' -Default 0)
        $topValueItemText = [string](_GetPortfolioAnalyticsField -InputObject $topValueItem -PropertyName 'text' -Default '')
        $valueScore = [int](_GetPortfolioAnalyticsField -InputObject $topValueItem -PropertyName 'valueScore' -Default 0)
        $recommendedAction = [string](_GetPortfolioAnalyticsField -InputObject $assessment -PropertyName 'recommendedAction' -Default '')

        $topCandidates.Add([pscustomobject]@{
            repoName                  = $repoName
            lifecycleState            = $lifecycleState
            maturityLevel             = $maturityLevel
            maturityScore             = $maturityScore
            documentationHealthScore  = $docHealthScore
            pendingItemCount          = $pendingItemCount
            topValueItemText          = $topValueItemText
            valueScore                = $valueScore
            recommendedAction         = $recommendedAction
        }) | Out-Null

        $repoSparklines.Add([pscustomobject]@{
            repoName          = $repoName
            lifecycleState    = $lifecycleState
            maturityLevel     = $maturityLevel
            currentScore      = $maturityScore
            points            = @(_NewPortfolioTrendPoint -Date $today -Value $maturityScore)
            topValueItemText  = $topValueItemText
            recommendedAction = $recommendedAction
        }) | Out-Null
    }

    $trendStatus = 'current-snapshot-only'
    $availableDays = 1
    $note = 'History snapshots are not populated yet; showing the current portfolio assessment scaffold until Release 2.1 history capture lands.'

    $appDbState = $null
    try {
        $appDbState = Get-AppDatabaseState
    } catch {
        $appDbState = $null
    }

    $dbPath = [string](_GetPortfolioAnalyticsField -InputObject $appDbState -PropertyName 'databasePath' -Default '')
    $dbEnabled = [bool](_GetPortfolioAnalyticsField -InputObject $appDbState -PropertyName 'enabled' -Default $false)

    if ($dbEnabled -and -not [string]::IsNullOrWhiteSpace($dbPath) -and (Test-Path -LiteralPath $dbPath -PathType Leaf)) {
        $historyRows = @(_GetPortfolioTrendHistoryRows -DatabasePath $dbPath -StartUtc $startUtc)
        if (@($historyRows).Count -gt 0) {
            $trendStatus = 'history-backed'
            $availableDays = @($historyRows | Select-Object -ExpandProperty captured_day -Unique).Count
            $series = [System.Collections.Generic.List[object]]::new()
            $series.Add([pscustomobject]@{
                key    = 'avgMaturityScore'
                label  = 'Avg Maturity'
                color  = 'emerald'
                points = @($historyRows | ForEach-Object {
                    _NewPortfolioTrendPoint -Date ([string]$_.captured_day) -Value ([double]$_.avg_maturity_score)
                })
            }) | Out-Null
            $series.Add([pscustomobject]@{
                key    = 'readyRepos'
                label  = 'Ready Repos'
                color  = 'sky'
                points = @($historyRows | ForEach-Object {
                    _NewPortfolioTrendPoint -Date ([string]$_.captured_day) -Value ([double]$_.ready_repo_count)
                })
            }) | Out-Null

            $summaryPayload.improvedThisWeek = _GetPortfolioTrendImprovedThisWeek -DatabasePath $dbPath -WeekStartUtc ($nowUtc.Date.AddDays(-6))

            $repoSparklines = [System.Collections.Generic.List[object]]::new()
            foreach ($candidate in @($topCandidates)) {
                $repoName = [string](_GetPortfolioAnalyticsField -InputObject $candidate -PropertyName 'repoName' -Default '')
                $currentScore = [int](_GetPortfolioAnalyticsField -InputObject $candidate -PropertyName 'maturityScore' -Default 0)
                $repoSparklines.Add([pscustomobject]@{
                    repoName          = $repoName
                    lifecycleState    = [string](_GetPortfolioAnalyticsField -InputObject $candidate -PropertyName 'lifecycleState' -Default 'discovered')
                    maturityLevel     = [string](_GetPortfolioAnalyticsField -InputObject $candidate -PropertyName 'maturityLevel' -Default 'L0-Absent')
                    currentScore      = $currentScore
                    points            = @(_GetPortfolioTrendRepoHistoryPoints -DatabasePath $dbPath -RepoName $repoName -StartUtc $startUtc -FallbackDay $today -FallbackScore $currentScore)
                    topValueItemText  = [string](_GetPortfolioAnalyticsField -InputObject $candidate -PropertyName 'topValueItemText' -Default '')
                    recommendedAction = [string](_GetPortfolioAnalyticsField -InputObject $candidate -PropertyName 'recommendedAction' -Default '')
                }) | Out-Null
            }

            $note = if ($availableDays -lt $RequestedDays) {
                "SQLite maturity history is available for $availableDays day(s); the scaffold will widen automatically as Release 2.1 history capture fills in."
            } else {
                'Trend analytics are backed by SQLite maturity history; broader digest/distribution work remains planned in Release 2.3.'
            }
        }
    }

    return [pscustomobject]@{
        trendStatus    = $trendStatus
        seedSource     = $SeedSource
        requestedDays  = $RequestedDays
        availableDays  = $availableDays
        generatedAt    = $GeneratedAt
        note           = $note
        summary        = $summaryPayload
        series         = @($series)
        topCandidates  = @($topCandidates)
        repoSparklines = @($repoSparklines)
    }
}
