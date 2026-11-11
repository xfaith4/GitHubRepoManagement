#Requires -Version 7.0
<#
.SYNOPSIS
    A baseline now, then a weekly delivery report (loop step 8).

.DESCRIPTION
    The 2026-10-16 evaluation's figures were counted by hand once, and nothing
    said whether a week moved them. This gate proves, offline (GitHub calls
    injected, records under a temporary root):

      - Run summaries are read with every status; an unreadable one is
        counted, never dropped; smoke fixtures are not real work.
      - A failed run names its cause from its recorded error.
      - A PR counts as product-initiated only when a product record names it
        (ledger prUrl, run prUrl or agentTaskUrl, a runner branch found on
        GitHub), never on the product's own repository; a GitHub read that
        fails is listed, never silently dropped.
      - Every figure carries unit, basis, window and source. One the records
        cannot compute is null with its reason, never 0: no ledger decision,
        GitHub unread, readiness only known after the window.
      - Each report says what moved since the previous one, and refuses to
        subtract counts taken over windows of a different shape.
      - tools/New-DeliveryReport.ps1 writes JSON and Markdown in one command,
        the baseline beside the evaluation's figures; -WhatIf writes nothing.

.EXAMPLE
    pwsh ./tests/Test-DeliveryReport.ps1 -FailOnError
#>
[CmdletBinding()]
param(
    [Parameter()][string]$WorkspaceRoot = (Split-Path -Parent $PSScriptRoot),
    [Parameter()][switch]$FailOnError
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$WorkspaceRoot = (Resolve-Path -LiteralPath $WorkspaceRoot).Path
. (Join-Path $WorkspaceRoot 'backend\modules\common\Config.OutputRoot.ps1')
. (Join-Path $WorkspaceRoot 'backend\modules\portfolio\Portfolio.Snapshot.ps1')
. (Join-Path $WorkspaceRoot 'backend\modules\delivery\Delivery.Ledger.ps1')
. (Join-Path $WorkspaceRoot 'backend\modules\delivery\Delivery.Report.ps1')

$failures = [System.Collections.Generic.List[string]]::new()
$passed = 0
function Assert-That {
    param([bool]$Condition, [string]$Message)
    if ($Condition) { $script:passed++ } else { $script:failures.Add($Message) }
}

$scratch = Join-Path ([System.IO.Path]::GetTempPath()) ("delivery-report-{0}" -f [guid]::NewGuid().ToString('n'))
$null = New-Item -ItemType Directory -Path $scratch -Force
$savedOutputRoot = $env:REPO_MGMT_OUTPUT_ROOT
$savedCacheRoot = $env:REPO_MGMT_CACHE_ROOT

try {
    # -- 1. Smoke fixtures and failure causes ----------------------------------
    Assert-That (Test-DeliverySmokeRepository -Repository 'smoke-owner/smoke-repo') 'smoke-owner/* is a fixture'
    Assert-That (Test-DeliverySmokeRepository -Repository 'xfaith4/dispatch-success-smoke') 'a *-smoke repository is a fixture'
    Assert-That (-not (Test-DeliverySmokeRepository -Repository 'xfaith4/SystemDashboard')) 'a real repository is not a fixture'
    Assert-That (-not (Test-DeliverySmokeRepository -Repository 'xfaith4/smokehouse')) 'smoke must be a whole hyphenated word'
    $causeCases = @{
        'gh agent-task create failed with exit code 1'                = 'copilot-task-create'
        'GitHub token not found. Set either GitHub_Token'             = 'github-token'
        'No roadmap markdown file found in repository'                = 'missing-roadmap'
        'No unchecked roadmap tasks were found'                       = 'no-actionable-item'
        'runner pid 4242 is not this runner (8080); run abandoned'    = 'runner-pid-mismatch'
        'claude execution failed with exit code 3'                    = 'agent-exit'
        'something nobody anticipated'                                = 'other'
        ''                                                            = 'unrecorded'
    }
    foreach ($k in $causeCases.Keys) {
        $got = Get-RunnerFailureCause -ErrorText $k
        Assert-That ($got -eq $causeCases[$k]) ("cause of '{0}' should be {1}, got {2}" -f $k, $causeCases[$k], $got)
    }

    # -- 2. Run summaries: every status, unreadable counted ---------------------
    $runsDir = Join-Path $scratch 'data\output\roadmap-task-history\runs'
    $null = New-Item -ItemType Directory -Path $runsDir -Force
    $runFixtures = @(
        @{ runId = 'r1'; status = 'failed'; repository = 'xfaith4/alpha'; startedAt = '2026-10-01T10:00:00Z'; error = 'gh agent-task create failed'; branch = 'roadmap/20261001-100000-aaaaaaaa' }
        @{ runId = 'r2'; status = 'blocked'; repository = 'xfaith4/alpha'; startedAt = '2026-10-02T10:00:00Z'; error = 'No roadmap markdown file found' }
        @{ runId = 'r3'; status = 'cancelled'; repository = 'xfaith4/beta'; startedAt = '2026-10-03T10:00:00Z' }
        @{ runId = 'r4'; status = 'dispatched'; repository = 'xfaith4/beta'; startedAt = '2026-10-04T10:00:00Z'; agentTaskUrl = 'https://github.com/xfaith4/beta/pull/4/agent-sessions/0f0f' }
        @{ runId = 'r5'; status = 'awaiting-review'; repository = 'gamma'; startedAt = '2026-10-05T10:00:00Z'; prUrl = 'https://github.com/xfaith4/gamma/pull/7' }
        @{ runId = 'r6'; status = 'failed'; repository = 'smoke-owner/smoke-repo'; startedAt = '2026-10-06T10:00:00Z'; error = 'x' }
        @{ runId = 'r7'; status = 'refused'; repository = 'xfaith4/alpha'; startedAt = '2026-10-20T10:00:00Z'; error = 'runner pid 1 is not this runner' }
        @{ runId = 'r8'; status = 'pushed'; repository = 'xfaith4/GitHubRepoManagement'; startedAt = '2026-10-07T10:00:00Z'; prUrl = 'https://github.com/xfaith4/GitHubRepoManagement/pull/140' }
    )
    foreach ($r in $runFixtures) { Set-Content -LiteralPath (Join-Path $runsDir ('{0}.summary.json' -f $r.runId)) -Value ($r | ConvertTo-Json) -Encoding utf8NoBOM }
    Set-Content -LiteralPath (Join-Path $runsDir 'broken.summary.json') -Value '{ not json' -Encoding utf8NoBOM
    $read = Get-RunnerRunSummary -RunsDirectory $runsDir
    Assert-That (@($read.runs).Count -eq 8) ("8 readable runs expected, got {0}" -f @($read.runs).Count)
    Assert-That ($read.skipped -eq 1) 'the unreadable summary is counted as skipped'
    Assert-That ((@($read.runs | Where-Object runId -eq 'r4')[0].agentTaskUrl) -like '*agent-sessions*') 'agentTaskUrl is read'
    Assert-That (@(Get-RunnerRunSummary -RunsDirectory (Join-Path $scratch 'nope')).Count -eq 1) 'a missing runs directory returns one empty result, not an error'

    # -- 3. Product PRs: only what a record names, read from GitHub ------------
    $sha = 'd' * 40
    $decision = [pscustomobject]@{ kind = 'decision'; decision = 'accept'; recordedAt = '2026-10-08T10:00:00Z'; repoName = 'delta'; prUrl = 'https://github.com/xfaith4/delta/pull/2'; operatorSeconds = 300 }
    $reject = [pscustomobject]@{ kind = 'decision'; decision = 'reject'; recordedAt = '2026-10-09T10:00:00Z'; repoName = 'delta'; prUrl = ''; operatorSeconds = 120; reason = 'not useful' }
    $calls = [System.Collections.Generic.List[string]]::new()
    $fake = {
        param([string]$Path)
        $calls.Add($Path)
        switch -Regex ($Path) {
            '/pulls\?state=all&head=xfaith4:roadmap%2F20261001' { return @([pscustomobject]@{ html_url = 'https://github.com/xfaith4/alpha/pull/9'; state = 'closed'; merged_at = '2026-10-02T00:00:00Z'; created_at = '2026-10-01T11:00:00Z'; head = [pscustomobject]@{ sha = ('a' * 40) } }) }
            '/repos/xfaith4/beta/pulls/4$' { return [pscustomobject]@{ html_url = 'https://github.com/xfaith4/beta/pull/4'; state = 'open'; merged_at = $null; created_at = '2026-10-04T11:00:00Z'; head = [pscustomobject]@{ sha = ('b' * 40) } } }
            '/repos/xfaith4/gamma/pulls/7$' { throw 'HTTP 404' }
            '/repos/xfaith4/delta/pulls/2$' { return [pscustomobject]@{ html_url = 'https://github.com/xfaith4/delta/pull/2'; state = 'closed'; merged_at = '2026-10-10T00:00:00Z'; created_at = '2026-10-08T10:00:00Z'; head = [pscustomobject]@{ sha = $sha } } }
            '/commits/a+/check-runs' { return [pscustomobject]@{ check_runs = @([pscustomobject]@{ status = 'completed'; conclusion = 'failure' }) } }
            '/commits/d+/check-runs' { return [pscustomobject]@{ check_runs = @([pscustomobject]@{ status = 'completed'; conclusion = 'success' }) } }
            '/check-runs' { return [pscustomobject]@{ check_runs = @() } }
            '/status$' { return [pscustomobject]@{ state = 'pending'; total_count = 0 } }
        }
        throw "unexpected GitHub path $Path"
    }.GetNewClosure()
    $resolved = Resolve-DeliveryProductPullRequest -Record @($decision, $reject) -Run $read.runs -ProductRepository 'xfaith4/GitHubRepoManagement' -GitHubGet $fake
    $byUrl = @{}; foreach ($p in $resolved.prs) { $byUrl[$p.url] = $p }
    Assert-That ($byUrl.ContainsKey('https://github.com/xfaith4/delta/pull/2')) 'a ledger decision PR is product-initiated'
    Assert-That ($byUrl.ContainsKey('https://github.com/xfaith4/beta/pull/4')) 'an agentTaskUrl names its PR'
    Assert-That ($byUrl.ContainsKey('https://github.com/xfaith4/alpha/pull/9')) 'a runner branch found on GitHub is product-initiated'
    Assert-That (-not ($resolved.prs.url -match 'GitHubRepoManagement')) "the product's own repository is excluded"
    Assert-That (@($resolved.errors | Where-Object { $_.target -like '*gamma/pull/7' }).Count -eq 1) 'a PR GitHub could not read is listed as an error'
    Assert-That ($byUrl['https://github.com/xfaith4/alpha/pull/9'].state -eq 'merged') 'merged_at makes a PR merged'
    Assert-That ($byUrl['https://github.com/xfaith4/alpha/pull/9'].ciConclusion -eq 'failure') 'CI is read on the head commit'
    Assert-That ($byUrl['https://github.com/xfaith4/beta/pull/4'].ciConclusion -eq 'none') 'a head with no CI reads none, not success'
    Assert-That ($byUrl['https://github.com/xfaith4/delta/pull/2'].ciConclusion -eq 'success') 'a passing head reads success'
    Assert-That (-not ($calls -match 'smoke')) 'smoke fixtures are never looked up'

    # -- 4. The report: every figure with unit, basis, window and source -------
    $asOf = '2026-11-11T12:00:00Z'
    $audit = [pscustomobject]@{ auditedAt = '2026-10-15T00:00:00Z'; entries = @(
            [pscustomobject]@{ dispatchReadiness = 'ready' }, [pscustomobject]@{ dispatchReadiness = 'missing-roadmap' }, [pscustomobject]@{ dispatchReadiness = 'missing-roadmap' }) }
    $report = New-DeliveryReport -GeneratedAtUtc $asOf -WindowEndUtc '2026-10-17T00:00:00Z' -Record @($decision, $reject) -Run $read.runs -PullRequest $resolved.prs -AuditCache $audit
    $f = $report.figures
    foreach ($id in 'prsInitiated', 'prsPassedCi', 'prsMerged', 'proposalsRejected', 'operatorSeconds', 'operatorSecondsPerMergedImprovement', 'agentRuns', 'agentRunsFailed', 'reposReady') {
        $m = $f.$id
        Assert-That ($null -ne $m) "figure $id is present"
        if ($null -eq $m) { continue }
        Assert-That ($m.PSObject.Properties.Name -contains 'window' -and $m.window.end -like '2026-10-17*') "figure $id carries its window"
        Assert-That ($null -ne $m.unit) "figure $id carries its unit"
        Assert-That (($null -ne $m.value -and $m.source) -or ($null -eq $m.value -and $m.reason)) "figure $id has a source, or is null with a reason"
    }
    Assert-That ($f.prsInitiated.value -eq 3) ("3 PRs initiated before the window end, got {0}" -f $f.prsInitiated.value)
    Assert-That ($f.prsMerged.value -eq 2) ("2 merged before the window end, got {0}" -f $f.prsMerged.value)
    Assert-That ($f.prsPassedCi.value -eq 1 -and $f.prsPassedCi.basis.denominator -eq 3) 'passed CI is 1 of 3 read'
    Assert-That ($f.agentRuns.value -eq 6) ("6 non-smoke runs started before the window end (every status), got {0}" -f $f.agentRuns.value)
    Assert-That ($f.agentRunsFailed.value -eq 2) ("failed and blocked count, cancelled does not, the refused run is after the window: got {0}" -f $f.agentRunsFailed.value)
    Assert-That (@($report.failureCauses | Where-Object cause -eq 'missing-roadmap').Count -eq 1) 'failure causes are named'
    Assert-That ($f.proposalsRejected.value -eq 1 -and $f.proposalsRejected.basis.denominator -eq 2) 'proposals rejected is 1 of 2 decided'
    Assert-That ($f.operatorSeconds.value -eq 420) 'operator seconds count every decision, rejected included'
    Assert-That ($f.reposReady.value -eq 1 -and $f.reposReady.basis.denominator -eq 3) 'ready is 1 of the 3 audited'

    # Not measured is null with its reason, never 0.
    $bare = New-DeliveryReport -GeneratedAtUtc $asOf -WindowEndUtc '2026-10-17T00:00:00Z' -Record @() -Run @() -PullRequest $null -PullRequestReason 'No GitHub token is configured.' `
        -AuditCache ([pscustomobject]@{ auditedAt = '2026-11-01T00:00:00Z'; entries = @() })
    foreach ($id in 'prsInitiated', 'prsPassedCi', 'prsMerged', 'proposalsRejected', 'operatorSeconds', 'operatorSecondsPerMergedImprovement', 'agentRuns', 'agentRunsFailed', 'reposReady') {
        Assert-That ($null -eq $bare.figures.$id.value -and $bare.figures.$id.reason) "with no records, $id is null with a reason, never 0"
    }
    Assert-That ($bare.figures.prsMerged.reason -eq 'No GitHub token is configured.') 'the GitHub reason is carried'
    Assert-That ($bare.figures.operatorSeconds.reason -like '*not recorded*') 'no ledger decision says operator time was not recorded'
    # A ledger that began after the window ends was not recording in it.
    $late = [pscustomobject]@{ kind = 'decision'; decision = 'reject'; recordedAt = '2026-10-20T10:00:00Z'; repoName = 'delta'; prUrl = ''; operatorSeconds = 60; reason = 'x' }
    $early = New-DeliveryReport -GeneratedAtUtc $asOf -WindowEndUtc '2026-10-17T00:00:00Z' -Record @($late) -Run @()
    Assert-That ($null -eq $early.figures.proposalsRejected.value -and $early.figures.proposalsRejected.reason -like '*by the window end*') 'a ledger that began after the window reads not measured, never 0 of 0'
    # Unreadable CI on every PR is not measured, never 0 passed.
    $blind = @($resolved.prs | ForEach-Object { $c = $_.PSObject.Copy(); $c.ciConclusion = 'unavailable'; $c.ciBasis = 'check runs were not readable'; $c })
    $blindReport = New-DeliveryReport -GeneratedAtUtc $asOf -WindowEndUtc '2026-10-17T00:00:00Z' -Record @() -Run @() -PullRequest $blind
    Assert-That ($null -eq $blindReport.figures.prsPassedCi.value -and $blindReport.figures.prsPassedCi.reason -like '*could not be read*') 'CI unreadable on every PR is not measured'
    # Unreadable CI on some PRs leaves them out of the denominator: never counted as failed.
    $partial = @($resolved.prs | ForEach-Object { $c = $_.PSObject.Copy(); if ($c.ciConclusion -ne 'success') { $c.ciConclusion = 'unavailable' }; $c })
    $partialCi = (New-DeliveryReport -GeneratedAtUtc $asOf -WindowEndUtc '2026-10-17T00:00:00Z' -Record @() -Run @() -PullRequest $partial).figures.prsPassedCi
    Assert-That ($partialCi.value -eq 1 -and $partialCi.basis.denominator -eq 1 -and $partialCi.coverage.assessed -eq 1 -and $partialCi.coverage.total -eq 3) ("unreadable CI is out of the denominator: got {0} of {1}, coverage {2} of {3}" -f $partialCi.value, $partialCi.basis.denominator, $partialCi.coverage.assessed, $partialCi.coverage.total)
    $ciUnknown = Resolve-DeliveryCiConclusion -CheckRun $null -CombinedStatus ([pscustomobject]@{ state = 'pending'; total_count = 0 })
    Assert-That ($ciUnknown.conclusion -eq 'unavailable') ("unreadable check runs and no commit status is unavailable, not none: got {0}" -f $ciUnknown.conclusion)
    Assert-That ($bare.figures.reposReady.reason -like '*after the window ends*') 'readiness audited after the window is not measured'
    $noCache = New-DeliveryReport -GeneratedAtUtc $asOf -WindowEndUtc $asOf -Record @() -Run @()
    Assert-That ($noCache.figures.reposReady.reason -like '*No docs audit cache*') 'no audit cache is not measured'

    # -- 5. What moved since the previous report --------------------------------
    $json = $report | ConvertTo-Json -Depth 12 | ConvertFrom-Json -DateKind String
    $later = New-DeliveryReport -GeneratedAtUtc $asOf -WindowEndUtc '2026-10-21T00:00:00Z' -Record @($decision, $reject) -Run $read.runs -PullRequest $resolved.prs -AuditCache $audit -Previous $json
    Assert-That ($later.changes.agentRunsFailed.delta -eq 1 -and $later.changes.agentRunsFailed.previous -eq 2) 'the refused run moved failures from 2 to 3'
    Assert-That ($later.changes.prsMerged.delta -eq 0) 'an unmoved figure reads delta 0'
    Assert-That ($report.changes.prsMerged.reason -like 'No earlier report*') 'the first report says there is nothing to compare with'
    $weekly = New-DeliveryReport -GeneratedAtUtc $asOf -WindowStartUtc '2026-10-14T00:00:00Z' -WindowEndUtc '2026-10-21T00:00:00Z' -Record @() -Run $read.runs -Previous $json
    Assert-That ($null -eq $weekly.changes.agentRuns.delta -and $weekly.changes.agentRuns.reason -like '*different shape*') 'a weekly count is never subtracted from a cumulative one'
    $nullThen = New-DeliveryReport -GeneratedAtUtc $asOf -WindowEndUtc '2026-10-21T00:00:00Z' -Record @($decision) -Run @() -Previous ($bare | ConvertTo-Json -Depth 12 | ConvertFrom-Json -DateKind String)
    Assert-That ($nullThen.changes.operatorSeconds.reason -like 'Not measured in the earlier*') 'a figure first measured now says it was not measured before'
    $md = ConvertTo-DeliveryReportMarkdown -Report $bare
    Assert-That ($md -match 'not measured: No GitHub token') 'Markdown shows not measured with its reason'
    Assert-That ($md -match '\| --- \| --- \|') 'Markdown tables use spaced delimiter rows'
    $errReport = New-DeliveryReport -GeneratedAtUtc $asOf -WindowEndUtc '2026-10-17T00:00:00Z' -Record @() -Run @() -ReadError @([pscustomobject]@{ target = 'o/r#1'; error = "gh: Not Found (HTTP 404)`r`n{`"message`":`"Not Found`"}" })
    $errMd = ConvertTo-DeliveryReportMarkdown -Report $errReport
    Assert-That ($errMd -match '- o/r#1: gh: Not Found \(HTTP 404\)\r?\n' -and $errMd -notmatch '"message"') 'a read error renders on one line without the raw response body'

    # -- 6. One command writes the report ---------------------------------------
    $dataRoot = Join-Path $scratch 'data'
    $destRoot = Join-Path $scratch 'dest'
    $null = New-Item -ItemType Directory -Path $destRoot -Force
    $env:REPO_MGMT_OUTPUT_ROOT = ''
    $env:REPO_MGMT_CACHE_ROOT = Join-Path $scratch 'cache'
    $null = New-Item -ItemType Directory -Path $env:REPO_MGMT_CACHE_ROOT -Force
    $audit | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $env:REPO_MGMT_CACHE_ROOT 'docs-audit-cache.json') -Encoding utf8NoBOM
    $tool = Join-Path $WorkspaceRoot 'tools\New-DeliveryReport.ps1'
    $common = @{ WorkspaceRoot = $WorkspaceRoot; DataRoot = $dataRoot; DestinationRoot = $destRoot; ProductRepository = 'xfaith4/GitHubRepoManagement'; Offline = $true }
    $null = & $tool @common -Baseline -WhatIf
    Assert-That (-not (Test-Path -LiteralPath (Join-Path $destRoot 'evidence'))) '-WhatIf writes nothing'
    $out = & $tool @common -Baseline -AsOfUtc $asOf
    Assert-That (Test-Path -LiteralPath $out.json) 'the baseline JSON is written'
    Assert-That ($out.json -like '*evidence*baseline*2026-10-16*') 'the baseline lands under evidence/baseline/2026-10-16'
    $written = Get-Content -LiteralPath $out.json -Raw | ConvertFrom-Json -DateKind String
    Assert-That (@($written.baselineComparison).Count -eq 9) 'the baseline sits beside every evaluation figure'
    Assert-That ((@($written.baselineComparison | Where-Object figure -eq 'agentRuns')[0].note) -like 'Differs*') 'a figure that differs from the evaluation says so'
    Assert-That ((Get-Content -LiteralPath $out.markdown -Raw) -match 'Against the 2026-10-16 evaluation') 'the Markdown carries the comparison'
    $weeklyOut = & $tool @common -AsOfUtc '2026-11-11T12:00:00Z'
    Assert-That ($weeklyOut.json -like '*delivery*reports*2026-11-11.json') 'a weekly report lands under delivery/reports/<date>.json'
    $weeklyJson = Get-Content -LiteralPath $weeklyOut.json -Raw | ConvertFrom-Json -DateKind String
    Assert-That ($null -ne $weeklyJson.previous -and $weeklyJson.previous.window.end -like '2026-10-17*') 'the first weekly report compares against the baseline'
    Assert-That ($weeklyJson.changes.agentRunsFailed.delta -eq 1) 'the weekly report says what moved since the baseline'

    # -- 7. Wired into the suite -------------------------------------------------
    $suite = Get-Content -LiteralPath (Join-Path $WorkspaceRoot 'scripts\Invoke-TestSuite.ps1') -Raw
    Assert-That ($suite -match "Test-DeliveryReport\.ps1") 'the suite runs this gate'
}
finally {
    $env:REPO_MGMT_OUTPUT_ROOT = $savedOutputRoot
    $env:REPO_MGMT_CACHE_ROOT = $savedCacheRoot
    Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction Ignore
}

foreach ($m in $failures) { Write-Information ("FAIL: {0}" -f $m) -InformationAction Continue }
Write-Information ("Delivery report: {0} passed, {1} failed" -f $passed, $failures.Count) -InformationAction Continue
if ($FailOnError -and $failures.Count -gt 0) { exit 1 }
