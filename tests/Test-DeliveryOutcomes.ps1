#Requires -Version 7.0
<#
.SYNOPSIS
    Every decision carries its outcome, read from GitHub (loop step 7).

.DESCRIPTION
    The delivery ledger recorded accept and reject, and a refresh could read
    what became of a PR, but no decision said what became of IT: a rejected
    proposal, an accept that never produced a PR and a PR nobody had read back
    all looked alike, the CI verdict named no head, and a new push with the
    same verdict was never recorded. This gate proves, offline (GitHub calls
    injected, ledger under a temporary output root):

      - A decision that opened a PR carries the PR's head SHA as GitHub
        returned it; a malformed SHA, or one on a reject, is refused.
      - Every decision resolves to exactly one outcome: rejected before any PR
        existed, accepted with no PR recorded, PR opened (nothing read back
        yet), PR open, merged, or closed unmerged. One with no outcome yet
        says so and is counted as awaiting, never as a failure.
      - An outcome names the head its CI verdict was read on, and a refresh
        records a moved head even when the verdict did not change.
      - Operator seconds per merged improvement is one computation over every
        decision, rejected ones included.
      - The summary states when outcomes were last read from GitHub, or that
        they never were; -WhatIf reads nothing into the ledger or that state.
      - Outcomes are never typed in: only Update-DeliveryOutcome builds an
        outcome record, and the decision route takes no head SHA from a body.

.EXAMPLE
    pwsh ./tests/Test-DeliveryOutcomes.ps1 -FailOnError
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
. (Join-Path $WorkspaceRoot 'backend\modules\roadmap\Roadmap.PrSubmitter.ps1')
. (Join-Path $WorkspaceRoot 'backend\modules\delivery\Delivery.Ledger.ps1')

$failures = [System.Collections.Generic.List[string]]::new()
$passed = 0
function Assert-That {
    param([bool]$Condition, [string]$Message)
    if ($Condition) { $script:passed++ } else { $script:failures.Add($Message) }
}
function Test-Refused {
    param([scriptblock]$Action)
    try { $null = & $Action; return $false } catch { return $true }
}

$shaA = 'a' * 40
$shaB = 'b' * 40
$shaC = 'c' * 40
$urlOne = 'https://github.com/o/alpha/pull/1'
$urlTwo = 'https://github.com/o/beta/pull/2'
$asOf = '2026-11-10T12:00:00Z'

$scratch = Join-Path ([System.IO.Path]::GetTempPath()) ("delivery-outcomes-{0}" -f [guid]::NewGuid().ToString('n'))
$null = New-Item -ItemType Directory -Path $scratch -Force
$savedOutputRoot = $env:REPO_MGMT_OUTPUT_ROOT

try {
    # -- 1. The head SHA travels with the PR, read from GitHub ------------------
    $opened = New-DeliveryDecisionRecord -RepoName 'alpha' -Decision 'accept' -PrUrl $urlOne -PrHeadSha $shaA
    Assert-That ($opened.prHeadSha -eq $shaA) 'decision: a PR-opening accept must carry the PR head SHA'
    $plain = New-DeliveryDecisionRecord -RepoName 'alpha' -Decision 'accept'
    Assert-That ($plain.Contains('prHeadSha') -and $null -eq $plain.prHeadSha) 'decision: prHeadSha is always present and null when no PR exists'
    Assert-That (Test-Refused { New-DeliveryDecisionRecord -RepoName 'r' -Decision 'accept' -PrUrl $urlOne -PrHeadSha 'not-a-sha' }) 'decision: a malformed head SHA must be refused'
    Assert-That (Test-Refused { New-DeliveryDecisionRecord -RepoName 'r' -Decision 'accept' -PrHeadSha $shaA }) 'decision: a head SHA with no PR must be refused'
    Assert-That (Test-Refused { New-DeliveryDecisionRecord -RepoName 'r' -Decision 'reject' -Reason 'x' -PrHeadSha $shaA }) 'decision: a reject cannot carry a head SHA'

    $outcome = New-DeliveryOutcomeRecord -PrUrl $urlOne -PrState 'open' -HeadSha $shaA -CiConclusion 'success' -CiBasis '1 check run(s), 0 commit status(es)'
    Assert-That ($outcome.headSha -eq $shaA -and $outcome.source -eq 'github') 'outcome: must name the head its CI was read on and its source'
    Assert-That (Test-Refused { New-DeliveryOutcomeRecord -PrUrl $urlOne -PrState 'open' -HeadSha 'xyz' }) 'outcome: a malformed head SHA must be refused'

    $missingHead = [pscustomobject]@{ number = 3; html_url = 'https://github.com/o/r/pull/3' }
    Assert-That ((Get-PullRequestHeadSha -PullRequest $missingHead) -eq '') 'pr head: a response with no head reads empty, never throws'
    Assert-That ((Get-PullRequestHeadSha -PullRequest ([pscustomobject]@{ head = [pscustomobject]@{ sha = $shaB } })) -eq $shaB) 'pr head: reads head.sha from the GitHub response'
    Assert-That ((Get-PullRequestHeadSha -PullRequest $null) -eq '') 'pr head: a null response reads empty'

    # -- 2. Every decision resolves to exactly one outcome ---------------------
    $dReject = [pscustomobject](New-DeliveryDecisionRecord -RepoName 'gamma' -Decision 'reject' -Reason 'drops a release' -OperatorSeconds 240 -OperatorSecondsBasis 'measured-in-console')
    $dNoPr = [pscustomobject](New-DeliveryDecisionRecord -RepoName 'delta' -Decision 'accept' -OperatorSeconds 60 -OperatorSecondsBasis 'measured-in-console')
    $dOpened = [pscustomobject](New-DeliveryDecisionRecord -RepoName 'epsilon' -Decision 'edit' -PrUrl 'https://github.com/o/epsilon/pull/5' -PrHeadSha $shaC -OperatorSeconds 120 -OperatorSecondsBasis 'measured-in-console')
    $dOne = [pscustomobject](New-DeliveryDecisionRecord -RepoName 'alpha' -Decision 'accept' -PrUrl $urlOne -PrHeadSha $shaA -OperatorSeconds 300 -OperatorSecondsBasis 'measured-in-console')
    $dTwo = [pscustomobject](New-DeliveryDecisionRecord -RepoName 'beta' -Decision 'accept' -PrUrl $urlTwo -PrHeadSha $shaB -OperatorSeconds 180 -OperatorSecondsBasis 'measured-in-console')
    $oOne = [pscustomobject](New-DeliveryOutcomeRecord -PrUrl $urlOne -PrState 'merged' -MergedAt '2026-11-09T10:00:00Z' -HeadSha $shaC -CiConclusion 'success' -DecisionId $dOne.decisionId)
    $oTwo = [pscustomobject](New-DeliveryOutcomeRecord -PrUrl $urlTwo -PrState 'closed-unmerged' -HeadSha $shaB -CiConclusion 'failure' -DecisionId $dTwo.decisionId)
    $records = @($dReject, $dNoPr, $dOpened, $dOne, $dTwo, $oOne, $oTwo)

    $outcomes = @(Get-DeliveryDecisionOutcome -Record $records)
    Assert-That ($outcomes.Count -eq 5) "outcomes: one per decision (5), got $($outcomes.Count)"
    $byRepo = @{}
    foreach ($o in $outcomes) { $byRepo[$o.repoName] = $o }

    $r = $byRepo['gamma']
    Assert-That ($r.outcome -eq 'rejected-before-pr' -and $r.terminal -and -not $r.awaiting -and $null -eq $r.prUrl) 'outcomes: a reject reads rejected before any PR existed, terminal'
    $r = $byRepo['delta']
    Assert-That ($r.outcome -eq 'no-pr-recorded' -and $r.awaiting -and -not $r.terminal -and $r.reason) 'outcomes: an accept with no PR says so and awaits, with a reason'
    $r = $byRepo['epsilon']
    Assert-That ($r.outcome -eq 'pr-opened' -and $r.awaiting -and -not $r.outcomeRead -and $r.headSha -eq $shaC -and $r.ciConclusion -eq 'not-read' -and $r.reason) 'outcomes: a PR nothing has read back reads opened, at its opening head, CI not read'
    $r = $byRepo['alpha']
    Assert-That ($r.outcome -eq 'merged' -and $r.terminal -and $r.outcomeRead -and $r.headSha -eq $shaC -and $r.mergedAt) 'outcomes: a merged PR names the head GitHub reported last, not the opening head'
    $r = $byRepo['beta']
    Assert-That ($r.outcome -eq 'closed-unmerged' -and $r.terminal -and $r.ciConclusion -eq 'failure') 'outcomes: a PR closed unmerged reads closed-unmerged with its CI'

    # -- 3. Summary: awaiting is not failure; one cost computation -------------
    $sum = Get-DeliverySummary -Record $records -AsOfUtc $asOf
    Assert-That (@($sum.decisionOutcomes).Count -eq 5) 'summary: carries one outcome per decision'
    Assert-That ($sum.metrics.awaitingOutcome.value -eq 2) "summary: two decisions await an outcome, got $($sum.metrics.awaitingOutcome.value)"
    Assert-That ($sum.metrics.closedUnmerged.value -eq 1) "summary: only the closed PR counts as closed unmerged, got $($sum.metrics.closedUnmerged.value)"
    Assert-That ($sum.metrics.prsMerged.value -eq 1) 'summary: one merged improvement'
    Assert-That ($sum.metrics.operatorSecondsPerMergedImprovement.value -eq 900) "summary: 900 operator seconds (rejected and unmerged included) over one merge, got $($sum.metrics.operatorSecondsPerMergedImprovement.value)"
    $empty = Get-DeliverySummary -Record @() -AsOfUtc $asOf
    Assert-That ($null -ne $empty.decisionOutcomes -and @($empty.decisionOutcomes).Count -eq 0) 'summary: no decisions is an empty outcome list, not $null'
    Assert-That ($null -eq $empty.metrics.awaitingOutcome.value -and $empty.metrics.awaitingOutcome.reason) 'summary: awaiting with no decisions is null with a reason, never 0'
    Assert-That ($null -eq $empty.outcomeFreshness.lastReadAt -and $empty.outcomeFreshness.reason) 'summary: outcomes never read must say so'

    # -- 4. Refresh against GitHub (injected) ----------------------------------
    $env:REPO_MGMT_OUTPUT_ROOT = Join-Path $scratch 'output'
    $state = Get-DeliveryOutcomeRefreshState -WorkspaceRoot $WorkspaceRoot
    Assert-That ($null -eq $state.lastReadAt -and $state.reason) 'refresh state: before any refresh it reads never, with a reason'

    $live = @{
        1 = @{ state = 'open'; merged = $false; merged_at = $null; head = $shaA; checks = @(@{ status = 'completed'; conclusion = 'success' }) }
        2 = @{ state = 'open'; merged = $false; merged_at = $null; head = $shaB; checks = @(@{ status = 'in_progress'; conclusion = $null }) }
    }
    $fake = {
        param([string]$ApiPath)
        $m = [regex]::Match($ApiPath, '/pulls/(\d+)$')
        if ($m.Success) {
            $p = $live[[int]$m.Groups[1].Value]
            return [pscustomobject]@{ state = $p.state; merged = $p.merged; merged_at = $p.merged_at; head = [pscustomobject]@{ sha = $p.head } }
        }
        $c = [regex]::Match($ApiPath, '/commits/([0-9a-f]{40})/(check-runs|status)$')
        if ($c.Success) {
            $owner = @($live.Values | Where-Object { $_.head -eq $c.Groups[1].Value })[0]
            if ($c.Groups[2].Value -eq 'status') { return [pscustomobject]@{ state = 'pending'; total_count = 0 } }
            return [pscustomobject]@{ check_runs = @($owner.checks | ForEach-Object { [pscustomobject]$_ }) }
        }
        throw "unexpected path $ApiPath"
    }.GetNewClosure()

    Add-DeliveryLedgerRecord -WorkspaceRoot $WorkspaceRoot -Record (New-DeliveryDecisionRecord -RepoName 'alpha' -Decision 'accept' -PrUrl $urlOne -PrHeadSha $shaA)
    Add-DeliveryLedgerRecord -WorkspaceRoot $WorkspaceRoot -Record (New-DeliveryDecisionRecord -RepoName 'beta' -Decision 'accept' -PrUrl $urlTwo -PrHeadSha $shaB)
    Add-DeliveryLedgerRecord -WorkspaceRoot $WorkspaceRoot -Record (New-DeliveryDecisionRecord -RepoName 'gamma' -Decision 'reject' -Reason 'no')

    $dry = Update-DeliveryOutcome -WorkspaceRoot $WorkspaceRoot -GitHubGet $fake -WhatIf
    $null = $dry
    Assert-That (@((Get-DeliveryLedgerRecord -WorkspaceRoot $WorkspaceRoot).records | Where-Object { $_.kind -eq 'outcome' }).Count -eq 0) 'refresh -WhatIf: must append no outcome'
    Assert-That ($null -eq (Get-DeliveryOutcomeRefreshState -WorkspaceRoot $WorkspaceRoot).lastReadAt) 'refresh -WhatIf: must not claim outcomes were read'

    $first = Update-DeliveryOutcome -WorkspaceRoot $WorkspaceRoot -GitHubGet $fake
    Assert-That ($first.checked -eq 2 -and $first.appended -eq 2 -and @($first.errors).Count -eq 0) "refresh: two PRs read, two outcomes recorded (checked=$($first.checked) appended=$($first.appended))"
    $read = @((Get-DeliveryLedgerRecord -WorkspaceRoot $WorkspaceRoot).records | Where-Object { $_.kind -eq 'outcome' })
    Assert-That (@($read | Where-Object { $_.prUrl -eq $urlOne -and $_.headSha -eq $shaA -and $_.ciConclusion -eq 'success' -and $_.source -eq 'github' }).Count -eq 1) 'refresh: the outcome names its head and CI verdict, from GitHub'
    Assert-That (@($read | Where-Object { $_.prUrl -eq $urlTwo -and $_.ciConclusion -eq 'pending' }).Count -eq 1) 'refresh: a running check reads pending on its head'
    $state = Get-DeliveryOutcomeRefreshState -WorkspaceRoot $WorkspaceRoot
    Assert-That ($state.lastReadAt -and $state.checked -eq 2 -and $state.errorCount -eq 0) 'refresh state: a refresh records when outcomes were read'

    $again = Update-DeliveryOutcome -WorkspaceRoot $WorkspaceRoot -GitHubGet $fake
    Assert-That ($again.appended -eq 0) 'refresh: nothing changed, nothing appended'

    $live[1].head = $shaC
    $live[1].checks = @(@{ status = 'completed'; conclusion = 'success' })
    $moved = Update-DeliveryOutcome -WorkspaceRoot $WorkspaceRoot -GitHubGet $fake
    $latestOne = @((Get-DeliveryLedgerRecord -WorkspaceRoot $WorkspaceRoot).records | Where-Object { $_.kind -eq 'outcome' -and $_.prUrl -eq $urlOne })[-1]
    Assert-That ($moved.appended -eq 1 -and $latestOne.headSha -eq $shaC) 'refresh: a moved head is recorded even when the CI verdict is unchanged'

    $live[1].state = 'closed'; $live[1].merged = $true; $live[1].merged_at = '2026-11-10T09:00:00Z'
    $live[2].state = 'closed'
    $null = Update-DeliveryOutcome -WorkspaceRoot $WorkspaceRoot -GitHubGet $fake
    $final = @(Get-DeliveryDecisionOutcome -Record @((Get-DeliveryLedgerRecord -WorkspaceRoot $WorkspaceRoot).records))
    Assert-That (@($final | Where-Object { $_.repoName -eq 'alpha' -and $_.outcome -eq 'merged' -and $_.headSha -eq $shaC }).Count -eq 1) 'refresh: merge recorded at the head that merged'
    Assert-That (@($final | Where-Object { $_.repoName -eq 'beta' -and $_.outcome -eq 'closed-unmerged' }).Count -eq 1) 'refresh: closed without merging recorded'
    Assert-That (@($final | Where-Object { $_.repoName -eq 'gamma' -and $_.outcome -eq 'rejected-before-pr' }).Count -eq 1) 'refresh: the reject keeps its outcome with no GitHub call'
    $terminal = Update-DeliveryOutcome -WorkspaceRoot $WorkspaceRoot -GitHubGet { throw 'a terminal PR must not be fetched again' }
    Assert-That ($terminal.checked -eq 0 -and @($terminal.errors).Count -eq 0) 'refresh: terminal PRs are never fetched again'

    # -- 5. Outcomes are never typed in (source tripwires) ---------------------
    $callSites = [System.Collections.Generic.List[string]]::new()
    $scanRoots = @('backend', 'scripts', 'tools') | ForEach-Object { Join-Path $WorkspaceRoot $_ } | Where-Object { Test-Path -LiteralPath $_ }
    $scanned = 0
    foreach ($file in (Get-ChildItem -LiteralPath $scanRoots -Recurse -File -Include '*.ps1', '*.psm1')) {
        $scanned++
        $tokens = $null; $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors)
        $calls = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'New-DeliveryOutcomeRecord' }, $true)
        foreach ($call in $calls) {
            $parent = $call.Parent
            while ($null -ne $parent -and -not ($parent -is [System.Management.Automation.Language.FunctionDefinitionAst])) { $parent = $parent.Parent }
            $owner = if ($null -ne $parent) { $parent.Name } else { '<script>' }
            if ($owner -ne 'Update-DeliveryOutcome') { $callSites.Add(('{0}:{1} in {2}' -f $file.Name, $call.Extent.StartLineNumber, $owner)) }
        }
    }
    Assert-That ($scanned -gt 0) 'tripwire: must scan at least one source file'
    Assert-That ($callSites.Count -eq 0) ("tripwire: only Update-DeliveryOutcome may build an outcome record; found {0}" -f ($callSites -join '; '))

    $hostSource = Get-Content -LiteralPath (Join-Path $WorkspaceRoot 'backend\api-host\Start-RepoManagementApiHost.ps1') -Raw
    $decisionRoute = [regex]::Match($hostSource, "(?s)'POST /api/delivery/decision' \{.*?\r?\n                \}\r?\n")
    Assert-That $decisionRoute.Success 'tripwire: the decision route must be found'
    Assert-That ($decisionRoute.Success -and $decisionRoute.Value -notmatch 'HeadSha') 'tripwire: the decision route must not take a head SHA from a request body'
    Assert-That ($hostSource -match "\`$submitDecision\['prHeadSha'\]\s*=\s*ConvertTo-DeliveryHeadSha -Sha \(\[string\]\(Get-ObjectPropertyValue -InputObject \`$submitResult -PropertyName 'prHeadSha'") 'tripwire: submit-pr must record the head SHA GitHub returned on its decision'
    $summaryRoute = [regex]::Match($hostSource, "(?s)'GET /api/delivery/summary' \{.*?\r?\n                \}\r?\n")
    Assert-That ($summaryRoute.Success -and $summaryRoute.Value -match 'Get-DeliveryOutcomeRefreshState') 'tripwire: the summary route must state when outcomes were last read'

    $prSource = Get-Content -LiteralPath (Join-Path $WorkspaceRoot 'backend\modules\roadmap\Roadmap.PrSubmitter.ps1') -Raw
    $openBody = [regex]::Match($prSource, '(?s)function Open-RepoBranchPullRequest \{.*?\r?\n\}\r?\n')
    Assert-That ($openBody.Success -and ([regex]::Matches($openBody.Value, 'headSha\s*=\s*\(Get-PullRequestHeadSha')).Count -ge 2) 'tripwire: Open-RepoBranchPullRequest must return the head SHA on both the created and the already-open path'
    Assert-That ($prSource -match 'prHeadSha\s*=\s*\[string\]\$prResult\.headSha') 'tripwire: Invoke-RoadmapRepairPrSubmission must pass the head SHA on'
}
finally {
    $env:REPO_MGMT_OUTPUT_ROOT = $savedOutputRoot
    Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Information ("Delivery outcomes: {0} passed, {1} failed" -f $passed, $failures.Count) -InformationAction Continue
foreach ($f in $failures) { Write-Information ("  FAIL: {0}" -f $f) -InformationAction Continue }
if ($FailOnError -and $failures.Count -gt 0) { exit 1 }
exit 0
