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
        # Release 3.5 milestone 4c -- "not computed" and "zero" may not share a
        # value. Returning 0 here is what let a portfolio with no assessed
        # repos render `0% Avg Maturity` as though it had been measured; null
        # renders as an em dash at the boundary instead.
        return $null
    }

    return [int][math]::Round(($values | Measure-Object -Average).Average, 0)
}

function _GetPortfolioAnalyticsAssessedCount {
    # Release 3.5 milestone 4c -- the average's denominator, carried beside it.
    # The null-skipping average is legitimate arithmetic; what made it a lie
    # was presenting a partial sample as the portfolio headline. The assessed
    # count is what lets the UI say "of N assessed" instead.
    param(
        [Parameter()][AllowEmptyCollection()][object[]]$Entries = @(),
        [Parameter(Mandatory = $true)][string]$PropertyName
    )

    $count = 0
    foreach ($entry in @($Entries)) {
        if ($null -eq $entry) { continue }
        $raw = _GetPortfolioAnalyticsField -InputObject $entry -PropertyName $PropertyName -Default $null
        if ($null -eq $raw) { continue }
        $number = 0.0
        if ([double]::TryParse([string]$raw, [ref]$number)) { $count++ }
    }
    return $count
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

function _GetPortfolioTrendCoveragePercent {
    <#
        Release 3.6 M5 -- one number for "how much of the portfolio's
        foundations are in place": present as a share of the foundations that
        actually APPLY. `not-applicable` and `not-scored` are excluded from
        both halves, so a repository excused from a domain neither helps nor
        hurts the figure, and the defined-but-unscored domain cannot dilute it.

        Returns $null when nothing applies -- an honest absence, not a 0.
    #>
    param([object]$Coverage)

    if ($null -eq $Coverage) { return $null }
    $domainNames = if ($Coverage -is [System.Collections.IDictionary]) {
        @($Coverage.Keys | ForEach-Object { [string]$_ })
    } else {
        @($Coverage.PSObject.Properties | ForEach-Object { [string]$_.Name })
    }

    $present = 0.0
    $applicable = 0.0
    foreach ($domainId in $domainNames) {
        $row = if ($Coverage -is [System.Collections.IDictionary]) { $Coverage[$domainId] } else { $Coverage.$domainId }
        if ($null -eq $row) { continue }
        foreach ($status in @('present', 'weak', 'missing')) {
            $value = if ($row -is [System.Collections.IDictionary]) {
                if ($row.Contains($status)) { $row[$status] } else { 0 }
            } elseif ($null -ne $row.PSObject -and ($row.PSObject.Properties.Name -contains $status)) {
                $row.$status
            } else { 0 }
            if ($null -eq $value) { $value = 0 }
            $applicable += [double]$value
            if ($status -eq 'present') { $present += [double]$value }
        }
    }

    if ($applicable -le 0) { return $null }
    return [math]::Round(($present / $applicable) * 100.0, 1)
}

function _GetPortfolioTrendCoverageRows {
    <#
        Daily coverage percentage from the foundation_coverage table. Returns
        an empty array when the reader is unavailable, so the caller falls back
        to the single-point scaffold rather than failing the whole trend.
    #>
    param([int]$Days = 30)

    if ($null -eq (Get-Command -Name 'Get-AppDbFoundationCoverageHistory' -ErrorAction SilentlyContinue)) { return @() }
    $history = Get-AppDbFoundationCoverageHistory -Days $Days
    if ($null -eq $history -or -not $history.available) { return @() }

    $byDay = [ordered]@{}
    foreach ($row in @($history.entries)) {
        $day = [string]$row.captured_day
        if ([string]::IsNullOrWhiteSpace($day)) { continue }
        if (-not $byDay.Contains($day)) { $byDay[$day] = @{ present = 0.0; applicable = 0.0 } }
        $present = [double]$(if ($null -ne $row.present_count) { $row.present_count } else { 0 })
        $weak = [double]$(if ($null -ne $row.weak_count) { $row.weak_count } else { 0 })
        $missing = [double]$(if ($null -ne $row.missing_count) { $row.missing_count } else { 0 })
        $byDay[$day].present += $present
        $byDay[$day].applicable += ($present + $weak + $missing)
    }

    $result = [System.Collections.Generic.List[object]]::new()
    foreach ($day in $byDay.Keys) {
        $bucket = $byDay[$day]
        if ($bucket.applicable -le 0) { continue }
        $result.Add([pscustomobject]@{
            captured_day = [string]$day
            coverage_pct = [math]::Round(($bucket.present / $bucket.applicable) * 100.0, 1)
        }) | Out-Null
    }
    return @($result)
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

    # Release 3.5 milestone 4a. `maturity_history` holds one row per repo PER
    # CAPTURE, and the old query aggregated over every capture in a day: a day
    # with three captures counted each ready repo three times (`Ready Repos ...
    # High 1592` on a 76-repo portfolio) and weighted a thrice-captured repo
    # threefold in the average -- the AVG merely hid the same defect the SUM
    # displayed. Each day now contributes each repo exactly once, at its
    # latest capture that day, so no day's ready count can exceed the number
    # of distinct repos.
    return @(Invoke-AppDbQuery -DatabasePath $DatabasePath -Sql @'
SELECT
  latest.captured_day AS captured_day,
  ROUND(AVG(COALESCE(m.maturity_score, 0)), 1) AS avg_maturity_score,
  SUM(CASE WHEN m.maturity_level IN ('L3-Contract-Ready', 'L4-Orchestration-Ready') AND COALESCE(m.pending_count, 0) > 0 THEN 1 ELSE 0 END) AS ready_repo_count,
  COUNT(*) AS repo_samples
FROM maturity_history m
JOIN (
  SELECT substr(captured_at, 1, 10) AS captured_day, repo_name, MAX(captured_at) AS latest_capture
  FROM maturity_history
  WHERE captured_at >= @start_utc
  GROUP BY substr(captured_at, 1, 10), repo_name
) latest
  ON m.repo_name = latest.repo_name AND m.captured_at = latest.latest_capture
GROUP BY latest.captured_day
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

    # Same latest-capture-per-day rule as the portfolio series (milestone 4a):
    # a day's point is the repo's latest capture that day, not an average over
    # however many captures happened to run.
    $rows = @(Invoke-AppDbQuery -DatabasePath $DatabasePath -Sql @'
SELECT
  substr(captured_at, 1, 10) AS captured_day,
  ROUND(COALESCE(maturity_score, 0), 1) AS maturity_score
FROM maturity_history m
WHERE repo_name = @repo_name
  AND captured_at >= @start_utc
  AND captured_at = (
    SELECT MAX(captured_at) FROM maturity_history
    WHERE repo_name = m.repo_name
      AND substr(captured_at, 1, 10) = substr(m.captured_at, 1, 10)
  )
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
        [Parameter()][int]$RequestedDays = 90,
        # Release 3.6 M5 -- per-domain coverage for TODAY, computed by the caller
        # (Portfolio.Conclusion owns the model; this module owns the chart).
        [Parameter()][object]$Coverage = $null
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
        # Nullable, deliberately (milestone 4c): null means "not computed",
        # and the render boundary shows an em dash. The assessed counts are
        # the denominators that let a partial sample say so.
        averageMaturityScore             = $averageMaturityScore
        averageDocumentationHealthScore  = $averageDocumentationHealthScore
        maturityAssessedCount            = (_GetPortfolioAnalyticsAssessedCount -Entries $entryList -PropertyName 'maturityScore')
        docsHealthAssessedCount          = (_GetPortfolioAnalyticsAssessedCount -Entries $entryList -PropertyName 'documentationHealthScore')
        improvedThisWeek                 = 0
    }

    $series = [System.Collections.Generic.List[object]]::new()
    $series.Add([pscustomobject]@{
        key    = 'avgMaturityScore'
        label  = 'Avg Maturity'
        color  = 'emerald'
        # The scaffold point needs a number; the TILE stays honest via the
        # nullable summary above. A 0-point in a 1-day scaffold series is
        # chart filler, not a headline. (No null-coalescing operator: this
        # module keeps the repo's PowerShell 5.1 contract.)
        points = @(_NewPortfolioTrendPoint -Date $today -Value ([double]$(if ($null -ne $summaryPayload.averageMaturityScore) { $summaryPayload.averageMaturityScore } else { 0 })))
    }) | Out-Null
    $series.Add([pscustomobject]@{
        key    = 'readyRepos'
        label  = 'Work-ready (L3+)'
        color  = 'sky'
        points = @(_NewPortfolioTrendPoint -Date $today -Value $summaryPayload.readyForWorkCount)
    }) | Out-Null
    # Release 3.6 M5 -- foundation coverage. Added in BOTH this scaffold block
    # and the history-backed block below: the history block re-news $series, so
    # a series added to only one of them vanishes the moment the other applies.
    $coveragePercentToday = _GetPortfolioTrendCoveragePercent -Coverage $Coverage
    if ($null -ne $coveragePercentToday) {
        $series.Add([pscustomobject]@{
            key    = 'foundationCoverage'
            label  = 'Foundations in place'
            color  = 'amber'
            points = @(_NewPortfolioTrendPoint -Date $today -Value ([double]$coveragePercentToday))
        }) | Out-Null
    }

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

            # Release 3.5 milestone 4b -- one card, one data path. The tiles
            # were built from the passed-in assessments while the series below
            # is rebuilt from history, so an index-only read rendered
            # `0% Avg Maturity / 0 Ready Now` above trend rows reading 20% and
            # 22 -- in the same card. When no live assessments were supplied,
            # the tiles now take the latest history day, the same source the
            # rows come from. (Docs health has no history column; it stays
            # null and renders as "not computed" rather than 0%.)
            if ($entryList.Count -eq 0) {
                $latestHistoryRow = @($historyRows)[-1]
                $summaryPayload.averageMaturityScore = [int][math]::Round([double]$latestHistoryRow.avg_maturity_score, 0)
                $summaryPayload.readyForWorkCount = [int]$latestHistoryRow.ready_repo_count
                $summaryPayload.maturityAssessedCount = [int]$latestHistoryRow.repo_samples
                if ([int]$summaryPayload.totalRepos -eq 0) {
                    $summaryPayload.totalRepos = [int]$latestHistoryRow.repo_samples
                }
            }

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
                label  = 'Work-ready (L3+)'
                color  = 'sky'
                points = @($historyRows | ForEach-Object {
                    _NewPortfolioTrendPoint -Date ([string]$_.captured_day) -Value ([double]$_.ready_repo_count)
                })
            }) | Out-Null
            # Release 3.6 M5 -- the history-backed twin of the coverage series
            # added to the scaffold above. Coverage has its own capture table,
            # so it accrues on its own clock: it falls back to today's single
            # point when nothing has been recorded yet.
            $coverageRows = @(_GetPortfolioTrendCoverageRows -Days $RequestedDays)
            if ($coverageRows.Count -gt 0) {
                $series.Add([pscustomobject]@{
                    key    = 'foundationCoverage'
                    label  = 'Foundations in place'
                    color  = 'amber'
                    points = @($coverageRows | ForEach-Object {
                        _NewPortfolioTrendPoint -Date ([string]$_.captured_day) -Value ([double]$_.coverage_pct)
                    })
                }) | Out-Null
            }
            elseif ($null -ne $coveragePercentToday) {
                $series.Add([pscustomobject]@{
                    key    = 'foundationCoverage'
                    label  = 'Foundations in place'
                    color  = 'amber'
                    points = @(_NewPortfolioTrendPoint -Date $today -Value ([double]$coveragePercentToday))
                }) | Out-Null
            }

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
