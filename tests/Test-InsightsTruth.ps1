#Requires -Version 7.0
<#
.SYNOPSIS
    The 2026-10-19 Insights defects, proved offline against fixtures.

.DESCRIPTION
    Issue #339: an agent-run record whose local-runner run failed, or stopped
    for review, leaves `dispatched` (Sync-AgentRunFromRunnerOutcome), and a
    record the runner has not finished, or that already names a pull request,
    is left alone.

    Issue #340: runner runs are counted by how they ended
    (Get-RunnerRunOutcomeSummary). The 2026-10-19 shape, 5 runs with 4 failed,
    reads 80%, and a window where nothing finished reads $null, never 0%.

    Issue #342: the portfolio-index trend seed carries one entry per repository.
    Convert-PortfolioIndexReposToAssessments returns its list with `,@()`; an
    outer `@()` around the call made one entry holding them all. Proved on the
    converter's shape and by a tripwire over every caller in the source.

    Writes only under a temporary output root (REPO_MGMT_OUTPUT_ROOT), restored
    on exit.

.EXAMPLE
    pwsh ./tests/Test-InsightsTruth.ps1 -FailOnError
#>
[CmdletBinding()]
param(
    [Parameter()][string]$WorkspaceRoot = (Split-Path -Parent $PSScriptRoot),
    [Parameter()][switch]$FailOnError
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$WorkspaceRoot = (Resolve-Path -LiteralPath $WorkspaceRoot).Path
. (Join-Path $WorkspaceRoot 'backend/modules/agent-runs/AgentRuns.ps1')
. (Join-Path $WorkspaceRoot 'backend/modules/execution/Execution.Ledger.ps1')
. (Join-Path $WorkspaceRoot 'backend/modules/portfolio/Portfolio.Assessment.ps1')

$failures = [System.Collections.Generic.List[string]]::new()
$passed = 0
function Assert-That {
    param([bool]$Condition, [string]$Message)
    if ($Condition) { $script:passed++ } else { $script:failures.Add($Message) }
}

$fixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("insights-truth-{0}" -f [guid]::NewGuid().ToString('n'))
$outputRoot = Join-Path $fixtureRoot 'output'
$runsDir = Join-Path $outputRoot 'roadmap-task-history/runs'
$null = New-Item -ItemType Directory -Path $runsDir -Force
$previousOutputRoot = [System.Environment]::GetEnvironmentVariable('REPO_MGMT_OUTPUT_ROOT')
[System.Environment]::SetEnvironmentVariable('REPO_MGMT_OUTPUT_ROOT', $outputRoot)

function Write-RunnerSummary {
    param([string]$RunId, [hashtable]$Fields)
    $body = [ordered]@{ runId = $RunId }
    foreach ($k in $Fields.Keys) { $body[$k] = $Fields[$k] }
    $body | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $runsDir "$RunId.summary.json") -Encoding UTF8
}

try {
    $now = [datetime]'2026-10-19T12:00:00Z'
    $recent = $now.AddDays(-2).ToString('o')

    # -- #339: runner outcomes close agent-run records ------------------------
    Write-RunnerSummary 'run-failed' @{ status = 'failed'; error = 'verification failed: 2 tests'; startedAt = $recent; runnerCompletedAt = $now.AddDays(-2).AddMinutes(9).ToString('o'); branch = 'roadmap/run-failed' }
    Write-RunnerSummary 'run-review' @{ status = 'awaiting-review'; commitSha = 'b19eae4'; startedAt = $recent; runnerCompletedAt = $recent }
    Write-RunnerSummary 'run-running' @{ status = 'running'; startedAt = $recent }
    Write-RunnerSummary 'run-pr' @{ status = 'failed'; error = 'late failure'; startedAt = $recent }

    $failedRec  = New-AgentRunRecord -WorkspaceRoot $fixtureRoot -RepoName 'SystemDashboard' -DispatchRunId 'run-failed' -ProviderTool 'claude'
    $reviewRec  = New-AgentRunRecord -WorkspaceRoot $fixtureRoot -RepoName 'FreshStartFamily' -DispatchRunId 'run-review' -ProviderTool 'claude'
    $runningRec = New-AgentRunRecord -WorkspaceRoot $fixtureRoot -RepoName 'Busy' -DispatchRunId 'run-running' -ProviderTool 'claude'
    $prRec      = New-AgentRunRecord -WorkspaceRoot $fixtureRoot -RepoName 'HasPr' -DispatchRunId 'run-pr' -ProviderTool 'claude'
    $null = Update-AgentRunRecord -WorkspaceRoot $fixtureRoot -RunId $prRec.runId -Patch @{ prUrl = 'https://github.com/o/r/pull/1' }
    $orphanRec  = New-AgentRunRecord -WorkspaceRoot $fixtureRoot -RepoName 'NoSummary' -DispatchRunId 'run-missing' -ProviderTool 'claude'

    $sync = Sync-AgentRunFromRunnerOutcome -WorkspaceRoot $fixtureRoot
    Assert-That ($sync.advanced -eq 2) ("#339: two records advance (failed, awaiting-review); got {0}" -f $sync.advanced)
    Assert-That (@($sync.errors).Count -eq 0) ("#339: no sync errors; got {0}" -f (@($sync.errors) -join '; '))

    $f = (Get-AgentRunDetail -WorkspaceRoot $fixtureRoot -RunId $failedRec.runId).run
    Assert-That ($f.status -eq 'failed') "#339: a failed runner run closes its record as failed (got '$($f.status)')"
    Assert-That ($f.outcome -eq 'runner-failed') "#339: the outcome names the runner failure (got '$($f.outcome)')"
    Assert-That ($f.outcomeDetail -eq 'verification failed: 2 tests') '#339: the runner''s own reason is carried'
    Assert-That ($f.branch -eq 'roadmap/run-failed') '#339: a record with no branch takes the runner''s branch'
    Assert-That ($null -ne $f.metrics.agentCompletedAt) '#339: the completion time is recorded'
    $events = @((Get-AgentRunDetail -WorkspaceRoot $fixtureRoot -RunId $failedRec.runId).events | ForEach-Object { $_.eventType })
    Assert-That ($events -contains 'run.failed') ("#339: a run.failed event is emitted; got {0}" -f ($events -join ','))

    $r = (Get-AgentRunDetail -WorkspaceRoot $fixtureRoot -RunId $reviewRec.runId).run
    Assert-That ($r.status -eq 'blocked') "#339: a run awaiting review is blocked, not live (got '$($r.status)')"
    Assert-That ($r.outcome -eq 'awaiting-review-unpushed') '#339: awaiting-review names the unpushed state'
    Assert-That ($r.outcomeDetail -match 'b19eae4') '#339: the review detail names the commit'

    $u = (Get-AgentRunDetail -WorkspaceRoot $fixtureRoot -RunId $runningRec.runId).run
    Assert-That ($u.status -eq 'dispatched') '#339: a runner run still running leaves its record alone'
    $p = (Get-AgentRunDetail -WorkspaceRoot $fixtureRoot -RunId $prRec.runId).run
    Assert-That ($p.status -eq 'dispatched') '#339: a record that names a pull request belongs to the pull-request sweep'
    $o = (Get-AgentRunDetail -WorkspaceRoot $fixtureRoot -RunId $orphanRec.runId).run
    Assert-That ($o.status -eq 'dispatched') '#339: a missing runner summary is not evidence the run ended'

    $again = Sync-AgentRunFromRunnerOutcome -WorkspaceRoot $fixtureRoot
    Assert-That ($again.advanced -eq 0) ("#339: a second sync changes nothing; advanced {0}" -f $again.advanced)

    # A blocked review run that later fails is closed as failed.
    Write-RunnerSummary 'run-review' @{ status = 'failed'; error = 'push refused'; startedAt = $recent }
    $null = Sync-AgentRunFromRunnerOutcome -WorkspaceRoot $fixtureRoot
    $r2 = (Get-AgentRunDetail -WorkspaceRoot $fixtureRoot -RunId $reviewRec.runId).run
    Assert-That ($r2.status -eq 'failed') "#339: a blocked run whose runner run then fails becomes failed (got '$($r2.status)')"

    # An unreadable summary is reported, not swallowed.
    $badRec = New-AgentRunRecord -WorkspaceRoot $fixtureRoot -RepoName 'Bad' -DispatchRunId 'run-bad' -ProviderTool 'claude'
    Set-Content -LiteralPath (Join-Path $runsDir 'run-bad.summary.json') -Value '{ not json' -Encoding UTF8
    $bad = Sync-AgentRunFromRunnerOutcome -WorkspaceRoot $fixtureRoot
    Assert-That ($bad.failed -eq 1 -and @($bad.errors).Count -eq 1 -and $bad.errors[0] -match 'run-bad') '#339: an unreadable summary is counted and named'
    Assert-That ((Get-AgentRunDetail -WorkspaceRoot $fixtureRoot -RunId $badRec.runId).run.status -eq 'dispatched') '#339: an unreadable summary leaves its record alone'
    Remove-Item -LiteralPath (Join-Path $runsDir 'run-bad.summary.json')

    # -- #340: runner outcomes over a window -----------------------------------
    Get-ChildItem -LiteralPath $runsDir -File | Remove-Item
    $empty = Get-RunnerRunOutcomeSummary -WorkspaceRoot $fixtureRoot -Days 14 -Now $now
    Assert-That ($empty.total -eq 0 -and $null -eq $empty.errorRatePct) '#340: no runs reads no rate, never 0%'

    foreach ($i in 1..4) { Write-RunnerSummary "f$i" @{ status = 'failed'; startedAt = $now.AddDays(-1 * $i).ToString('o') } }
    Write-RunnerSummary 'review' @{ status = 'awaiting-review'; commitSha = 'b19eae4'; startedAt = $recent }
    Write-RunnerSummary 'inflight' @{ status = 'running'; startedAt = $now.AddHours(-1).ToString('o') }
    Write-RunnerSummary 'old' @{ status = 'failed'; startedAt = $now.AddDays(-20).ToString('o') }
    Write-RunnerSummary 'gone' @{ status = 'cancelled'; startedAt = $recent }

    $s = Get-RunnerRunOutcomeSummary -WorkspaceRoot $fixtureRoot -Days 14 -Now $now
    Assert-That ($s.total -eq 7) "#340: seven runs fall in the window (got $($s.total))"
    Assert-That ($s.failed -eq 4) "#340: four failed (got $($s.failed))"
    Assert-That ($s.finished -eq 5) "#340: five finished, excluding in-flight and cancelled (got $($s.finished))"
    Assert-That ($s.errorRatePct -eq 80) "#340: the 2026-10-19 shape reads 80% (got $($s.errorRatePct))"
    Assert-That ($s.inFlight -eq 1 -and $s.cancelled -eq 1) '#340: in-flight and cancelled are counted apart'
    Assert-That ($s.committed -eq 1) "#343: one run recorded a commit (got $($s.committed))"
    Assert-That (-not [string]::IsNullOrWhiteSpace($s.basis)) '#340: the figure names its basis'

    Set-Content -LiteralPath (Join-Path $runsDir 'broken.summary.json') -Value '{' -Encoding UTF8
    $withBad = Get-RunnerRunOutcomeSummary -WorkspaceRoot $fixtureRoot -Days 14 -Now $now
    Assert-That ($withBad.unreadable -eq 1 -and $withBad.total -eq 7) '#340: an unreadable summary is counted as unreadable, not dropped or guessed'

    # -- #342: the trend seed carries every repository -------------------------
    $indexRepos = @(1..62 | ForEach-Object { [pscustomobject]@{ repoId = "repo-$_"; curationState = 'none' } })
    $seedEntries = Convert-PortfolioIndexReposToAssessments -IndexRepos $indexRepos
    Assert-That (@($seedEntries).Count -eq 62) ("#342: 62 index repositories yield 62 seed entries (got {0})" -f @($seedEntries).Count)
    $wrapped = @(Convert-PortfolioIndexReposToAssessments -IndexRepos $indexRepos)
    Assert-That ($wrapped.Count -eq 1) '#342: (control) an outer @() collapses the list to one element, which is why callers must not add one'
    $noRepos = Convert-PortfolioIndexReposToAssessments -IndexRepos @()
    Assert-That ($null -ne $noRepos -and @($noRepos).Count -eq 0) '#342: an empty index yields an empty list, not $null'

    $wrapPattern = '@\(\s*Convert-PortfolioIndexReposToAssessments\b'
    $offenders = @(
        Get-ChildItem -Path (Join-Path $WorkspaceRoot 'backend'), (Join-Path $WorkspaceRoot 'scripts') -Recurse -File -Include '*.ps1', '*.psm1' |
            Select-String -Pattern $wrapPattern |
            ForEach-Object { '{0}:{1}' -f $_.Path.Substring($WorkspaceRoot.Length + 1), $_.LineNumber }
    )
    Assert-That ($offenders.Count -eq 0) ("#342: no caller wraps Convert-PortfolioIndexReposToAssessments in @(); found {0}" -f ($offenders -join ', '))
}
finally {
    [System.Environment]::SetEnvironmentVariable('REPO_MGMT_OUTPUT_ROOT', $previousOutputRoot)
    Remove-Item -LiteralPath $fixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ("Insights truth: {0} passed, {1} failed" -f $passed, $failures.Count)
foreach ($f in $failures) { Write-Host "  FAIL: $f" }
if ($failures.Count -gt 0 -and $FailOnError) { exit 1 }
