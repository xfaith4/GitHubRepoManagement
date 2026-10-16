#Requires -Version 7.0
<#
.SYNOPSIS
    The delivery loop's write path and its ledger (proof of value, 2026-10-16).

.DESCRIPTION
    Two defects stood between the console and its first real PR on another
    repository, and one gap stood between that PR and any measurement of it:

      1. The portal service runs as LocalSystem, which has no git identity, so
         every commit it attempted failed with "Author identity unknown".
      2. When the commit failed, the old submit path checked the start branch
         out with the rewritten roadmap still staged, leaving the operator's
         clone dirty and every later submit refused.
      3. Nothing recorded accept, reject, operator time or what became of a PR,
         so "one hour in must save more than one hour" was never computable.

    This gate proves, offline (local git only, GitHub calls injected):

      - Resolve-GitCommitIdentity: the checkout's git config wins; otherwise the
        token owner's noreply address; otherwise 'unresolved' with a reason.
      - New-RoadmapRepairCommit commits in a checkout with NO git identity when
        given one, authored as that identity, and returns to the start branch.
      - On a failed commit it restores the roadmap, leaves nothing staged,
        returns to the start branch and deletes its empty work branch.
      - Decision records refuse unexplainable input; the summary counts
        rejected proposals' time and reads null-with-reason, never 0.
      - CI verdicts: failure beats pending beats success; unreadable is
        'unavailable', never 'success'. Outcome refresh records state changes
        once and stops at a terminal state.

.EXAMPLE
    pwsh ./tests/Test-DeliveryLoop.ps1 -FailOnError
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
. (Join-Path $WorkspaceRoot 'backend\modules\git\Git.BaseFreshness.ps1')
. (Join-Path $WorkspaceRoot 'backend\modules\roadmap\Roadmap.PrSubmitter.ps1')
. (Join-Path $WorkspaceRoot 'backend\modules\delivery\Delivery.Ledger.ps1')

$failures = [System.Collections.Generic.List[string]]::new()
$passed = 0
function Assert-That {
    param([bool]$Condition, [string]$Message)
    if ($Condition) { $script:passed++ } else { $script:failures.Add($Message) }
}

$scratch = Join-Path ([System.IO.Path]::GetTempPath()) ("delivery-loop-{0}" -f [guid]::NewGuid().ToString('n'))
$null = New-Item -ItemType Directory -Path $scratch -Force
$emptyGitConfig = Join-Path $scratch 'empty.gitconfig'
Set-Content -LiteralPath $emptyGitConfig -Value '' -Encoding UTF8

# Every git call below runs as an account with no identity, the way the
# LocalSystem service does: no global config, no system config.
$savedEnv = @{
    GIT_CONFIG_GLOBAL     = $env:GIT_CONFIG_GLOBAL
    GIT_CONFIG_NOSYSTEM   = $env:GIT_CONFIG_NOSYSTEM
    REPO_MGMT_OUTPUT_ROOT = $env:REPO_MGMT_OUTPUT_ROOT
    GIT_AUTHOR_EMAIL      = $env:GIT_AUTHOR_EMAIL
    GIT_COMMITTER_EMAIL   = $env:GIT_COMMITTER_EMAIL
    EMAIL                 = $env:EMAIL
}
$env:GIT_CONFIG_GLOBAL = $emptyGitConfig
$env:GIT_CONFIG_NOSYSTEM = '1'
foreach ($name in 'GIT_AUTHOR_EMAIL', 'GIT_COMMITTER_EMAIL', 'EMAIL') { Remove-Item -LiteralPath ("Env:{0}" -f $name) -ErrorAction SilentlyContinue }

function Initialize-FixtureRepo {
    param([string]$Name)
    $path = Join-Path $scratch $Name
    $null = New-Item -ItemType Directory -Path $path -Force
    & git -C $path init -q -b main 2>&1 | Out-Null
    Set-Content -LiteralPath (Join-Path $path 'ROADMAP.md') -Value "# Roadmap`n`n- [ ] one`n" -Encoding UTF8 -NoNewline
    & git -C $path add ROADMAP.md 2>&1 | Out-Null
    # The fixture's own first commit needs an identity; the code under test does not get one.
    & git -C $path -c user.name=fixture -c user.email=fixture@example.invalid commit -q -m init 2>&1 | Out-Null
    return $path
}

function Get-Porcelain { param([string]$Path) ((& git -C $Path status --porcelain 2>&1) | Out-String).Trim() }

$noreplyLookup = { [pscustomobject]@{ login = 'octo-owner'; id = 4242; name = 'Octo Owner' } }

try {
    # -- 1. Identity resolution ------------------------------------------------
    $repoA = Initialize-FixtureRepo -Name 'identity'
    $none = Resolve-GitCommitIdentity -RepoPath $repoA -Token ''
    Assert-That ($none.source -eq 'unresolved' -and $none.reason -match 'no GitHub token') 'identity: no config and no token must be unresolved with a reason'

    $fromToken = Resolve-GitCommitIdentity -RepoPath $repoA -Token 'fixture-token' -GitHubUserLookup $noreplyLookup
    Assert-That ($fromToken.source -eq 'github-noreply') 'identity: the token owner must be used when git has none'
    Assert-That ($fromToken.email -eq '4242+octo-owner@users.noreply.github.com') "identity: noreply address must be <id>+<login>@users.noreply.github.com, got '$($fromToken.email)'"
    Assert-That ($fromToken.name -eq 'Octo Owner') 'identity: the display name must come from the GitHub profile'

    $lookupFails = Resolve-GitCommitIdentity -RepoPath $repoA -Token 'fixture-token' -GitHubUserLookup { throw '401 Unauthorized' }
    Assert-That ($lookupFails.source -eq 'unresolved' -and $lookupFails.reason -match '401') 'identity: a failed lookup must be unresolved and carry the failure'
    Assert-That ($lookupFails.reason -notmatch 'fixture-token') 'identity: a failure reason must never contain the token'

    & git -C $repoA config user.email 'owner@example.invalid' 2>&1 | Out-Null
    $configured = Resolve-GitCommitIdentity -RepoPath $repoA -Token 'fixture-token' -GitHubUserLookup { throw 'must not be called' }
    Assert-That ($configured.source -eq 'git-config' -and $configured.email -eq 'owner@example.invalid') 'identity: the checkout''s own user.email must win without a lookup'

    # -- 2. Commit succeeds in an identity-less checkout -----------------------
    $repoB = Initialize-FixtureRepo -Name 'commit-ok'
    $roadmapB = Join-Path $repoB 'ROADMAP.md'
    $before = Get-Content -LiteralPath $roadmapB -Raw
    $identity = Resolve-GitCommitIdentity -RepoPath $repoB -Token 'fixture-token' -GitHubUserLookup $noreplyLookup
    $ok = New-RoadmapRepairCommit -RepoPath $repoB -RoadmapPath $roadmapB -ProposedContent "# Roadmap`n`n## Phase 1`n`n- [ ] one`n" `
        -BranchName 'roadmap-repair/fixture-ok' -Message 'docs(roadmap): fixture repair' -Identity $identity
    Assert-That ($null -ne $ok -and $ok.authorEmail -eq '4242+octo-owner@users.noreply.github.com') "commit: must be authored as the resolved identity, got '$($ok.authorEmail)'"
    Assert-That ((Get-GitCurrentBranch -RepoPath $repoB) -eq 'main') 'commit: the checkout must be back on its start branch after success'
    Assert-That ([string]::IsNullOrEmpty((Get-Porcelain -Path $repoB))) 'commit: the working tree must be clean after success'
    Assert-That ((Get-Content -LiteralPath $roadmapB -Raw) -eq $before) 'commit: the start branch roadmap must be untouched'
    $branchLog = ((& git -C $repoB log --format=%s main..roadmap-repair/fixture-ok 2>&1) | Out-String).Trim()
    Assert-That ($branchLog -eq 'docs(roadmap): fixture repair') 'commit: the work branch must hold exactly the one repair commit'
    $branchFile = ((& git -C $repoB show roadmap-repair/fixture-ok:ROADMAP.md 2>&1) | Out-String)
    Assert-That ($branchFile -match '## Phase 1') 'commit: the work branch must carry the approved content'

    # -- 3. Commit fails: nothing staged, start branch, no stray branch -------
    $repoC = Initialize-FixtureRepo -Name 'commit-fails'
    $roadmapC = Join-Path $repoC 'ROADMAP.md'
    $beforeC = Get-Content -LiteralPath $roadmapC -Raw
    $unresolved = Resolve-GitCommitIdentity -RepoPath $repoC -Token ''
    $threw = $null
    try {
        $null = New-RoadmapRepairCommit -RepoPath $repoC -RoadmapPath $roadmapC -ProposedContent "# Changed`n" `
            -BranchName 'roadmap-repair/fixture-fail' -Message 'docs(roadmap): must fail' -Identity $unresolved
    }
    catch { $threw = $_.Exception.Message }
    Assert-That ($null -ne $threw) 'commit failure: an identity-less commit must throw (this is the service defect reproduced)'
    Assert-That ([string]$threw -match 'returned to' -and [string]$threw -match 'identity') "commit failure: the error must name the identity cause and the restore, got '$threw'"
    Assert-That ([string]::IsNullOrEmpty((Get-Porcelain -Path $repoC))) "commit failure: the clone must be left clean, got '$(Get-Porcelain -Path $repoC)'"
    Assert-That ((Get-GitCurrentBranch -RepoPath $repoC) -eq 'main') 'commit failure: the checkout must be back on its start branch'
    Assert-That ((Get-Content -LiteralPath $roadmapC -Raw) -eq $beforeC) 'commit failure: the roadmap must be byte-identical to before'
    & git -C $repoC rev-parse --verify --quiet refs/heads/roadmap-repair/fixture-fail 2>&1 | Out-Null
    Assert-That ($LASTEXITCODE -ne 0) 'commit failure: the empty work branch must be deleted'

    # A known-stale base is refused before anything is created.
    $staleReading = [pscustomobject]@{ state = 'behind'; isStale = $true; summary = '3 commit(s) behind origin/main' }
    $staleThrew = $null
    try {
        $null = New-RoadmapRepairCommit -RepoPath $repoC -RoadmapPath $roadmapC -ProposedContent "# Changed`n" `
            -BranchName 'roadmap-repair/fixture-stale' -Message 'docs: stale' -Identity $identity -BaseFreshness $staleReading
    }
    catch { $staleThrew = $_.Exception.Message }
    Assert-That ([string]$staleThrew -match 'stale base') 'commit: a stale base must be refused unless acknowledged'
    & git -C $repoC rev-parse --verify --quiet refs/heads/roadmap-repair/fixture-stale 2>&1 | Out-Null
    Assert-That ($LASTEXITCODE -ne 0) 'commit: a stale-base refusal must create no branch'
    # With no reading supplied the function probes for itself; a clone with no
    # remote reads unknown, which is not stale.
    $selfProbed = New-RoadmapRepairCommit -RepoPath $repoC -RoadmapPath $roadmapC -ProposedContent "# Probed`n" `
        -BranchName 'roadmap-repair/fixture-probed' -Message 'docs: probed' -Identity $identity
    Assert-That ($null -ne $selfProbed -and $selfProbed.commitSha) 'commit: with no reading, the function must probe the base itself and proceed when it is not stale'

    # A roadmap that did not exist before is removed, not left untracked.
    $newRoadmap = Join-Path $repoC 'docs-ROADMAP-new.md'
    try {
        $null = New-RoadmapRepairCommit -RepoPath $repoC -RoadmapPath $newRoadmap -ProposedContent "# New`n" `
            -BranchName 'roadmap-repair/fixture-new' -Message 'docs: new' -Identity $unresolved
    }
    catch { $null = $_ }
    Assert-That (-not (Test-Path -LiteralPath $newRoadmap)) 'commit failure: a newly created roadmap file must be removed'
    Assert-That ([string]::IsNullOrEmpty((Get-Porcelain -Path $repoC))) 'commit failure (new file): the clone must be left clean'

    # -- 4. Decision records refuse what cannot be explained ------------------
    $refusals = @(
        @{ name = 'unknown decision'; args = @{ RepoName = 'r'; Decision = 'maybe' } }
        @{ name = 'reject without reason'; args = @{ RepoName = 'r'; Decision = 'reject' } }
        @{ name = 'reject carrying a PR'; args = @{ RepoName = 'r'; Decision = 'reject'; Reason = 'x'; PrUrl = 'https://github.com/o/r/pull/1' } }
        @{ name = 'negative seconds'; args = @{ RepoName = 'r'; Decision = 'accept'; OperatorSeconds = -1; OperatorSecondsBasis = 'operator-entered' } }
        @{ name = 'seconds beyond a working day'; args = @{ RepoName = 'r'; Decision = 'accept'; OperatorSeconds = 99999; OperatorSecondsBasis = 'operator-entered' } }
        @{ name = 'seconds without a basis'; args = @{ RepoName = 'r'; Decision = 'accept'; OperatorSeconds = 30 } }
        @{ name = 'fractional seconds'; args = @{ RepoName = 'r'; Decision = 'accept'; OperatorSeconds = 'ten'; OperatorSecondsBasis = 'operator-entered' } }
    )
    foreach ($case in $refusals) {
        $refused = $false
        try { $argsCopy = $case.args; $null = New-DeliveryDecisionRecord @argsCopy } catch { $refused = $true }
        Assert-That $refused ("decision: '{0}' must be refused" -f $case.name)
    }
    $acceptRecord = New-DeliveryDecisionRecord -RepoName 'r' -Decision 'accept' -OperatorSeconds 90 -OperatorSecondsBasis 'measured-in-console' -PreviewId 'p1'
    Assert-That ($acceptRecord.kind -eq 'decision' -and $acceptRecord.operatorSeconds -eq 90 -and $acceptRecord.decisionId) 'decision: a valid accept must carry its id and seconds'
    $untimed = New-DeliveryDecisionRecord -RepoName 'r' -Decision 'accept'
    Assert-That ($null -eq $untimed.operatorSeconds -and $null -eq $untimed.operatorSecondsBasis) 'decision: no time recorded must stay null, never 0'

    # -- 5. Summary arithmetic -------------------------------------------------
    $asOf = '2026-10-16T12:00:00Z'
    $empty = Get-DeliverySummary -Record @() -AsOfUtc $asOf
    Assert-That ($null -eq $empty.metrics.operatorSeconds.value -and $empty.metrics.operatorSeconds.reason) 'summary: no decisions must read operator time as null with a reason'
    Assert-That ($null -eq $empty.metrics.operatorSecondsPerMergedImprovement.value) 'summary: no decisions must read per-improvement time as null'
    Assert-That (@($empty.prs).Count -eq 0) 'summary: no decisions must list no PRs (not one $null)'

    $d1 = New-DeliveryDecisionRecord -RepoName 'alpha' -Decision 'accept' -OperatorSeconds 300 -OperatorSecondsBasis 'measured-in-console' -PrUrl 'https://github.com/o/alpha/pull/1'
    $d2 = New-DeliveryDecisionRecord -RepoName 'beta' -Decision 'edit' -OperatorSeconds 600 -OperatorSecondsBasis 'measured-in-console' -PrUrl 'https://github.com/o/beta/pull/2'
    $d3 = New-DeliveryDecisionRecord -RepoName 'gamma' -Decision 'reject' -Reason 'proposal drops a release' -OperatorSeconds 240 -OperatorSecondsBasis 'measured-in-console'
    $o1 = New-DeliveryOutcomeRecord -PrUrl 'https://github.com/o/alpha/pull/1' -PrState 'merged' -MergedAt '2026-10-16T11:00:00Z' -CiConclusion 'success' -OperatorSeconds 60 -OperatorSecondsBasis 'operator-entered'
    $records = @($d1, $d2, $d3, $o1) | ForEach-Object { [pscustomobject]$_ }
    $sum = Get-DeliverySummary -Record $records -AsOfUtc $asOf
    Assert-That ($sum.metrics.proposalsDecided.value -eq 3) 'summary: three decisions'
    Assert-That ($sum.metrics.accepted.value -eq 2 -and $sum.metrics.rejected.value -eq 1) 'summary: accept and edit are accepted; reject is rejected'
    Assert-That ($sum.metrics.prsOpened.value -eq 2 -and $sum.metrics.prsMerged.value -eq 1) 'summary: two PRs opened, one merged'
    Assert-That ($sum.metrics.operatorSeconds.value -eq 1200) "summary: operator time must include the rejected proposal and the outcome review (1200s), got $($sum.metrics.operatorSeconds.value)"
    Assert-That ($sum.metrics.operatorSecondsPerMergedImprovement.value -eq 1200) "summary: 1200s over one merged improvement, got $($sum.metrics.operatorSecondsPerMergedImprovement.value)"
    $beta = @($sum.prs | Where-Object { $_.repoName -eq 'beta' })
    Assert-That ($beta.Count -eq 1 -and $beta[0].prState -eq 'open' -and -not $beta[0].stateKnown) 'summary: a PR with no outcome reads open and unknown, not merged'

    $d4 = New-DeliveryDecisionRecord -RepoName 'delta' -Decision 'accept' -PrUrl 'https://github.com/o/delta/pull/4'
    $partial = Get-DeliverySummary -Record (@($records) + [pscustomobject]$d4) -AsOfUtc $asOf
    Assert-That ($null -eq $partial.metrics.operatorSecondsPerMergedImprovement.value -and $partial.metrics.operatorSecondsPerMergedImprovement.reason -match 'carry no operator time') 'summary: an untimed decision must make per-improvement time null, not understated'
    Assert-That ($partial.metrics.operatorSeconds.confidence -eq 'partial') 'summary: operator time with an untimed decision must read partial coverage'

    # -- 6. Ledger round trip through the output root --------------------------
    $env:REPO_MGMT_OUTPUT_ROOT = Join-Path $scratch 'output'
    Add-DeliveryLedgerRecord -WorkspaceRoot $WorkspaceRoot -Record $d1
    Add-DeliveryLedgerRecord -WorkspaceRoot $WorkspaceRoot -Record $d3
    Add-Content -LiteralPath (Get-DeliveryLedgerPath -WorkspaceRoot $WorkspaceRoot) -Value '{not json' -Encoding UTF8
    $read = Get-DeliveryLedgerRecord -WorkspaceRoot $WorkspaceRoot
    Assert-That ($read.path.StartsWith($env:REPO_MGMT_OUTPUT_ROOT)) 'ledger: must live under the output root override, never the live output\'
    Assert-That (@($read.records).Count -eq 2 -and $read.skipped -eq 1) 'ledger: two records read back and the malformed line reported as skipped'

    # -- 7. CI verdict ---------------------------------------------------------
    Assert-That ((Resolve-DeliveryCiConclusion -CheckRun $null -CombinedStatus $null).conclusion -eq 'unavailable') 'ci: unreadable must be unavailable, never success'
    Assert-That ((Resolve-DeliveryCiConclusion -CheckRun @() -CombinedStatus ([pscustomobject]@{ state = 'pending'; total_count = 0 })).conclusion -eq 'none') 'ci: no checks and no statuses is none'
    $mixed = @([pscustomobject]@{ status = 'completed'; conclusion = 'success' }, [pscustomobject]@{ status = 'in_progress'; conclusion = $null })
    Assert-That ((Resolve-DeliveryCiConclusion -CheckRun $mixed -CombinedStatus $null).conclusion -eq 'pending') 'ci: a running check makes the head pending'
    $failed = @($mixed + [pscustomobject]@{ status = 'completed'; conclusion = 'failure' })
    Assert-That ((Resolve-DeliveryCiConclusion -CheckRun $failed -CombinedStatus $null).conclusion -eq 'failure') 'ci: any failure wins'
    $green = @([pscustomobject]@{ status = 'completed'; conclusion = 'success' }, [pscustomobject]@{ status = 'completed'; conclusion = 'skipped' })
    Assert-That ((Resolve-DeliveryCiConclusion -CheckRun $green -CombinedStatus $null).conclusion -eq 'success') 'ci: success and skipped is success'

    # -- 8. Outcome refresh with an injected GitHub ----------------------------
    $script:prMerged = $false
    $fakeGitHub = {
        param([string]$ApiPath)
        if ($ApiPath -match '/pulls/1$') { return [pscustomobject]@{ state = $(if ($script:prMerged) { 'closed' } else { 'open' }); merged = $script:prMerged; merged_at = $(if ($script:prMerged) { '2026-10-16T13:00:00Z' } else { $null }); head = [pscustomobject]@{ sha = 'abc' } } }
        if ($ApiPath -match '/check-runs$') { return [pscustomobject]@{ check_runs = @([pscustomobject]@{ status = 'completed'; conclusion = 'success' }) } }
        if ($ApiPath -match '/status$') { throw '403 Resource not accessible by personal access token' }
        throw "unexpected path $ApiPath"
    }
    $first = Update-DeliveryOutcome -WorkspaceRoot $WorkspaceRoot -GitHubGet $fakeGitHub
    Assert-That ($first.checked -eq 1 -and $first.appended -eq 1) "outcome: the first refresh must record the open PR once, got checked=$($first.checked) appended=$($first.appended)"
    $again = Update-DeliveryOutcome -WorkspaceRoot $WorkspaceRoot -GitHubGet $fakeGitHub
    Assert-That ($again.appended -eq 0) 'outcome: an unchanged PR must not append a duplicate record'
    $script:prMerged = $true
    $merge = Update-DeliveryOutcome -WorkspaceRoot $WorkspaceRoot -GitHubGet $fakeGitHub
    Assert-That ($merge.appended -eq 1) 'outcome: a merge must be recorded'
    $after = Update-DeliveryOutcome -WorkspaceRoot $WorkspaceRoot -GitHubGet { throw 'a terminal PR must not be fetched again' }
    Assert-That ($after.checked -eq 0 -and @($after.errors).Count -eq 0) 'outcome: a merged PR is terminal and is not fetched again'
    $final = Get-DeliverySummary -Record @((Get-DeliveryLedgerRecord -WorkspaceRoot $WorkspaceRoot).records) -AsOfUtc $asOf
    Assert-That ($final.metrics.prsMerged.value -eq 1) 'outcome: the summary must read the refreshed merge'
}
finally {
    foreach ($key in $savedEnv.Keys) {
        if ($null -eq $savedEnv[$key]) { Remove-Item -LiteralPath ("Env:{0}" -f $key) -ErrorAction SilentlyContinue }
        else { Set-Item -LiteralPath ("Env:{0}" -f $key) -Value $savedEnv[$key] }
    }
    Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ("Delivery loop: {0} assertion(s) passed, {1} failed." -f $passed, $failures.Count)
foreach ($f in $failures) { Write-Host ("  FAIL: {0}" -f $f) -ForegroundColor Red }
if ($failures.Count -gt 0 -and $FailOnError) { exit 1 }
if ($passed -eq 0) {
    Write-Host '  FAIL: zero assertions ran; the gate is vacuous.' -ForegroundColor Red
    if ($FailOnError) { exit 1 }
}
