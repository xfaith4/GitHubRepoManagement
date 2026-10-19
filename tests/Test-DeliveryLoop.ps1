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
. (Join-Path $WorkspaceRoot 'backend\modules\execution\Execution.WorkPacket.ps1')
. (Join-Path $WorkspaceRoot 'backend\modules\agent-adapters\Adapter.Claude.ps1')
. (Join-Path $WorkspaceRoot 'backend\modules\execution\Execution.Ledger.ps1')

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

    # -- 9. The approved task text reaches the agent (2026-10-17) -------------
    # Run 20261016-031015-cc34298c: a 30-line operator-reviewed prompt reached
    # Claude as its first line, with "(none declared)" under criteria.
    $approved = "Make ROADMAP.md ready.`n`n1. MOVE the open items; do not copy them.`n2. Diff must be additions only.`n`nCommit and stop."
    $permissionsAll = @{ filesystemWrite = $true; shell = $true; network = $false; githubWrite = $false }
    $withText = New-WorkPacket -TaskId 'dl-1' -Repository 'o/r' -BaseBranch 'main' -BaseSha '' -Objective 'Make ROADMAP.md ready.' `
        -ForbiddenPaths @('.github/workflows/**') -Permissions $permissionsAll -Instructions $approved
    $rendered = ConvertTo-ClaudePrompt -Packet $withText
    Assert-That ($rendered.Contains($approved)) 'instructions: the approved text must reach the agent verbatim'
    Assert-That ($rendered.IndexOf('## Instructions') -gt $rendered.IndexOf('## Objective') -and $rendered.IndexOf('## Instructions') -lt $rendered.IndexOf('## Scope')) 'instructions: rendered between Objective and Scope'
    $oneLine = New-WorkPacket -TaskId 'dl-2' -Repository '' -BaseBranch 'main' -BaseSha '' -Objective 'Fix it.' -Permissions $permissionsAll -Instructions 'Fix it.'
    Assert-That ($null -eq $oneLine.instructions -and -not (ConvertTo-ClaudePrompt -Packet $oneLine).Contains('## Instructions')) 'instructions: text identical to the objective is not repeated'
    $roundTrip = ConvertTo-Json -InputObject $withText -Depth 8 | ConvertFrom-Json
    Assert-That ((ConvertTo-ClaudePrompt -Packet $roundTrip).Contains($approved)) 'instructions: survive the packet''s JSON round trip, which is how the runner reads it'
    $dispatchRoute = Get-Content -LiteralPath (Join-Path $WorkspaceRoot 'backend\api-host\Start-RepoManagementApiHost.ps1') -Raw
    Assert-That ($dispatchRoute -match '-Instructions \(\[string\]\$prompt\)') 'instructions: the dispatch route passes the operator prompt into the packet'
    $packaging = Get-Content -LiteralPath (Join-Path $WorkspaceRoot 'backend\modules\automation\Automation.RoadmapPackaging.ps1') -Raw
    Assert-That ($packaging -match "-Instructions \(\[string\]\(_Pack_GetField -Obj \`$Packet -Name 'generatedPrompt'") 'instructions: the packaged-item road passes the approved generated prompt into the packet'

    # -- 10. The permission envelope binds (2026-10-17) -----------------------
    $setting = ConvertTo-ClaudePermissionSetting -Packet $withText
    $allowList = @($setting.permissions.allow)
    $denyList = @($setting.permissions.deny)
    foreach ($readTool in 'Read', 'Glob', 'Grep') { Assert-That ($allowList -contains $readTool) "envelope: reading ($readTool) is never a prompt" }
    Assert-That ($allowList -contains 'Bash') 'envelope: shell true allows Bash'
    # The first real dispatch (FreshStartFamily, 2026-10-17) stalled on a
    # PowerShell call the Bash-only envelope did not cover.
    Assert-That ($allowList -contains 'PowerShell') 'envelope: shell true allows PowerShell too - Windows agents reach for it first'
    Assert-That ($denyList -contains 'Bash(git push:*)' -and $denyList -contains 'Bash(gh:*)') 'envelope: githubWrite false denies push and gh'
    Assert-That ($denyList -contains 'PowerShell(git push:*)' -and $denyList -contains 'PowerShell(gh:*)') 'envelope: githubWrite false denies push and gh from PowerShell as well'
    Assert-That ($denyList -contains 'PowerShell(Invoke-WebRequest:*)' -and $denyList -contains 'PowerShell(git reset --hard:*)') 'envelope: network and destructive denials cover PowerShell'
    Assert-That ($denyList -contains 'WebFetch' -and $denyList -contains 'WebSearch') 'envelope: network false denies web tools'
    Assert-That ($denyList -contains 'Edit(.github/workflows/**)') 'envelope: a forbidden path denies edits on it (D-012)'
    Assert-That (@($denyList | Where-Object { $_ -like 'Write(*' }).Count -eq 0) 'envelope: no Write(path) rules; the CLI ignores them and Edit(path) covers every editing tool'
    Assert-That ($denyList -contains 'Bash(git reset --hard:*)') 'envelope: destructive local git is denied'
    $noShell = ConvertTo-ClaudePermissionSetting -Packet (New-WorkPacket -TaskId 'dl-3' -Repository '' -BaseBranch 'main' -BaseSha '' -Objective 'o' -Permissions @{ filesystemWrite = $false; shell = $false; network = $true; githubWrite = $true })
    Assert-That (@($noShell.permissions.deny) -contains 'Bash' -and @($noShell.permissions.allow) -notcontains 'Bash') 'envelope: shell false denies Bash'
    Assert-That (@($noShell.permissions.deny) -contains 'PowerShell' -and @($noShell.permissions.allow) -notcontains 'PowerShell') 'envelope: shell false denies PowerShell'
    Assert-That (@($noShell.permissions.deny) -contains 'Edit') 'envelope: filesystemWrite false denies editing'
    Assert-That (@($noShell.permissions.deny) -notcontains 'WebFetch' -and @($noShell.permissions.deny) -notcontains 'Bash(git push:*)') 'envelope: granted network and githubWrite are not denied'
    $noPacket = ConvertTo-ClaudePermissionSetting -Packet $null
    Assert-That (@($noPacket.permissions.deny) -contains 'Bash' -and @($noPacket.permissions.allow) -contains 'Read') 'envelope: no packet means reads only - an absent grant is not a grant'
    $argvWith = New-ClaudeExecutionArgument -Prompt 'p' -PermissionMode 'acceptEdits' -SettingsPath 'C:\s.json'
    Assert-That (($argvWith -join ' ').EndsWith('--settings C:\s.json') -and $argvWith[1] -eq 'p') 'envelope: the settings file travels as one --settings argument after the prompt flag pair'
    Assert-That (@(New-ClaudeExecutionArgument -Prompt 'p' -PermissionMode 'acceptEdits').Count -eq 7) 'envelope: no settings path leaves the argv unchanged'
    $runnerSource = Get-Content -LiteralPath (Join-Path $WorkspaceRoot 'scripts\Invoke-RoadmapTaskRunner.ps1') -Raw
    Assert-That ($runnerSource -match '--settings \$claudeSettingsPath \$prompt') 'envelope: the interactive launch passes the settings file too'

    # -- 8. A closed run releases its lane (2026-10-17) -------------------------
    # The runner closes a run in its own summary; the ledger only ever heard
    # about completion through /api/execution/complete. FowlingScorecard read
    # "running" for two days on a run abandoned in forty minutes.
    $ledgerOutput = Join-Path $scratch 'ledger-output'
    $null = New-Item -ItemType Directory -Path (Join-Path $ledgerOutput 'execution') -Force
    $ledgerRuns = Join-Path $ledgerOutput 'roadmap-task-history\runs'
    $null = New-Item -ItemType Directory -Path $ledgerRuns -Force
    $env:REPO_MGMT_OUTPUT_ROOT = $ledgerOutput
    $ledgerFixture = @{
        schemaVersion = '1'
        updatedAt     = '2026-10-15T01:47:44Z'
        history       = @()
        entries       = @(
            @{ repoName = 'orphaned-repo';   executionState = 'running'; currentRunId = 'run-orphaned';  laneSlot = 1; retryCount = 0; currentTaskText = 'do the thing'; dispatchRunId = 'run-orphaned'; agentRunId = 'agent-1'; dispatchSource = 'console'; lastOutcome = $null; errorMessage = $null; completedAt = $null; updatedAt = '2026-10-15T01:47:44Z' }
            @{ repoName = 'live-repo';       executionState = 'running'; currentRunId = 'run-live';      laneSlot = 2; retryCount = 0; currentTaskText = 'still going'; dispatchRunId = 'run-live'; agentRunId = 'agent-2'; dispatchSource = 'console'; lastOutcome = $null; errorMessage = $null; completedAt = $null; updatedAt = '2026-10-15T01:47:44Z' }
            @{ repoName = 'no-summary-repo'; executionState = 'running'; currentRunId = 'run-missing';   laneSlot = $null; retryCount = 0; currentTaskText = 'unknown'; dispatchRunId = 'run-missing'; agentRunId = $null; dispatchSource = 'console'; lastOutcome = $null; errorMessage = $null; completedAt = $null; updatedAt = '2026-10-15T01:47:44Z' }
            @{ repoName = 'capped-repo';     executionState = 'running'; currentRunId = 'run-capped';    laneSlot = $null; retryCount = 2; currentTaskText = 'third strike'; dispatchRunId = 'run-capped'; agentRunId = $null; dispatchSource = 'console'; lastOutcome = $null; errorMessage = $null; completedAt = $null; updatedAt = '2026-10-15T01:47:44Z' }
            @{ repoName = 'idle-repo';       executionState = 'ready';   currentRunId = $null;           laneSlot = $null; retryCount = 0; currentTaskText = 'waiting'; dispatchRunId = $null; agentRunId = $null; dispatchSource = $null; lastOutcome = $null; errorMessage = $null; completedAt = $null; updatedAt = '2026-10-15T01:47:44Z' }
        )
    }
    ($ledgerFixture | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath (Join-Path $ledgerOutput 'execution\execution-ledger.json') -Encoding UTF8
    (@{ runId = 'run-orphaned'; status = 'failed'; failureCategory = 'orphaned'; error = 'runner pid 1 is not this runner (2); run abandoned' } | ConvertTo-Json) | Set-Content -LiteralPath (Join-Path $ledgerRuns 'run-orphaned.summary.json') -Encoding UTF8
    (@{ runId = 'run-live'; status = 'running' } | ConvertTo-Json) | Set-Content -LiteralPath (Join-Path $ledgerRuns 'run-live.summary.json') -Encoding UTF8
    (@{ runId = 'run-capped'; status = 'refused'; refusalCategory = 'stale-base'; error = 'Refusing to branch from a stale base.' } | ConvertTo-Json) | Set-Content -LiteralPath (Join-Path $ledgerRuns 'run-capped.summary.json') -Encoding UTF8

    $sync = Sync-LedgerFromRunHistory -WorkspaceRoot $WorkspaceRoot
    Assert-That ($sync.checked -eq 4) "ledger release: all four running entries are checked, got $($sync.checked)"
    Assert-That (@($sync.released).Count -eq 2) "ledger release: exactly the two closed runs release their lanes, got $(@($sync.released).Count)"
    $after = Read-ExecutionLedger -WorkspaceRoot $WorkspaceRoot
    $orphaned = @($after.entries) | Where-Object { $_.repoName -eq 'orphaned-repo' } | Select-Object -First 1
    Assert-That ($orphaned.executionState -eq 'ready' -and $null -eq $orphaned.laneSlot -and [int]$orphaned.retryCount -eq 1) 'ledger release: an orphaned run frees its lane, counts a retry and returns to ready'
    Assert-That ($orphaned.lastOutcome -eq 'orphaned' -and $orphaned.errorMessage -match 'abandoned') 'ledger release: the entry carries the run''s own failure category and error'
    Assert-That ($null -eq $orphaned.dispatchRunId -and $null -eq $orphaned.agentRunId) 'ledger release: the join keys are cleared so the next run does not inherit this one''s PR'
    $live = @($after.entries) | Where-Object { $_.repoName -eq 'live-repo' } | Select-Object -First 1
    Assert-That ($live.executionState -eq 'running' -and [int]$live.laneSlot -eq 2) 'ledger release: a run the runner still reports running keeps its lane'
    $missing = @($after.entries) | Where-Object { $_.repoName -eq 'no-summary-repo' } | Select-Object -First 1
    Assert-That ($missing.executionState -eq 'running') 'ledger release: a run with no summary is left alone - absence is not evidence'
    $capped = @($after.entries) | Where-Object { $_.repoName -eq 'capped-repo' } | Select-Object -First 1
    Assert-That ($capped.executionState -eq 'blocked' -and $capped.lastOutcome -eq 'stale-base') 'ledger release: the third failure blocks the repo, the same cap cancel applies'
    $releasedHistory = @($after.history) | Where-Object { $_.event -eq 'released' }
    Assert-That (@($releasedHistory).Count -eq 2 -and (@($releasedHistory | ForEach-Object { $_.runId }) -contains 'run-orphaned')) 'ledger release: each freed lane leaves one history record naming its run'
    $again = Sync-LedgerFromRunHistory -WorkspaceRoot $WorkspaceRoot
    Assert-That (@($again.released).Count -eq 0 -and $again.checked -eq 2) 'ledger release: a second pass changes nothing'
    $hostSource = Get-Content -LiteralPath (Join-Path $WorkspaceRoot 'backend\api-host\Start-RepoManagementApiHost.ps1') -Raw
    Assert-That ($hostSource -match 'Sync-LedgerFromRunHistory -WorkspaceRoot \$WorkspaceRoot') 'ledger release: the execution sync route runs the release pass'

    # -- 9. The clone goes back to the branch the operator left it on ----------
    # The runner switched clones onto roadmap/<runId> and never back; the
    # operator's next commit in 300PixelLED_2812B landed on a product branch.
    . (Join-Path $WorkspaceRoot 'scripts\Invoke-RoadmapTaskRunner.ps1') -LoadFunctionsOnly
    # Readiness repairs have an objective but deliberately select no roadmap checkbox.
    $repairEntry = [pscustomobject]@{ selectedTask = ''; runId = 'repair-fixture' }
    $repairObjective = 'Improve README and ROADMAP readiness.'
    $repairMessage = New-TaskCommitMessage -SelectedTask $repairEntry.selectedTask -RunId $repairEntry.runId -Objective $repairObjective
    Assert-That (($repairMessage -split "`n")[0] -eq "roadmap: $repairObjective") 'commit: an empty selected task uses the packet objective'
    Assert-That ($repairEntry.selectedTask -eq '') 'commit: a repair must not fabricate a selected roadmap checkbox'
    foreach ($emptyTask in @('', '  ', $null)) {
        $fallbackMessage = New-TaskCommitMessage -SelectedTask $emptyTask -RunId 'legacy-fixture'
        Assert-That (($fallbackMessage -split "`n")[0] -eq 'roadmap: Queued task legacy-fixture') 'commit: empty legacy labels have a nonempty run-linked fallback'
    }
    $selectedMessage = New-TaskCommitMessage -SelectedTask '  Selected checkbox  ' -RunId 'selected-fixture' -Objective 'Other objective'
    Assert-That (($selectedMessage -split "`n")[0] -eq 'roadmap: Selected checkbox') 'commit: the selected task retains precedence'
    $longMessage = New-TaskCommitMessage -SelectedTask '' -RunId 'long-fixture' -Objective ('x' * 120)
    Assert-That (($longMessage -split "`n")[0].Length -eq ('roadmap: '.Length + 68)) 'commit: fallback objectives use the existing subject length limit'
    Assert-That ($repairMessage.Contains('Run: repair-fixture')) 'commit: repair commit retains run provenance'
    $repairRepo = Initialize-FixtureRepo -Name 'repair-commit'
    & git -C $repairRepo switch -q -c 'roadmap/repair-fixture'
    Set-Content -LiteralPath (Join-Path $repairRepo 'README.md') -Value 'Repaired documentation' -Encoding UTF8
    & git -C $repairRepo add README.md
    & git -C $repairRepo -c user.name=fixture -c user.email=fixture@example.invalid commit -q -m $repairMessage
    Assert-That ($LASTEXITCODE -eq 0 -and (Get-Porcelain -Path $repairRepo) -eq '') 'commit: a readiness repair with no selected checkbox commits successfully'
    Assert-That ((& git -C $repairRepo log -1 --format=%s) -eq "roadmap: $repairObjective") 'commit: the actual repair commit uses the objective'

    $repoR = Initialize-FixtureRepo -Name 'restore'
    & git -C $repoR switch -q -c 'roadmap/fixture-run' 2>&1 | Out-Null
    Set-Content -LiteralPath (Join-Path $repoR 'work.txt') -Value 'agent output' -Encoding UTF8
    & git -C $repoR add work.txt 2>&1 | Out-Null
    & git -C $repoR -c user.name=fixture -c user.email=fixture@example.invalid commit -q -m 'agent work' 2>&1 | Out-Null
    $restored = Restore-RunnerStartBranch -RepoPath $repoR -StartBranch 'main' -WorkBranch 'roadmap/fixture-run'
    Assert-That ([bool]$restored.restored -and ((& git -C $repoR branch --show-current) | Out-String).Trim() -eq 'main') "restore: a clean clone returns to its start branch, got '$($restored.reason)'"
    $workCommits = ((& git -C $repoR rev-list --count 'roadmap/fixture-run') | Out-String).Trim()
    Assert-That ($workCommits -eq '2' -and -not (Test-Path -LiteralPath (Join-Path $repoR 'work.txt'))) 'restore: the work branch keeps its commit and the start branch does not carry it'
    $second = Restore-RunnerStartBranch -RepoPath $repoR -StartBranch 'main' -WorkBranch 'roadmap/fixture-run'
    Assert-That ([bool]$second.restored -and $second.reason -match 'already') 'restore: already on the start branch is a no-op that still reads restored'
    & git -C $repoR switch -q 'roadmap/fixture-run' 2>&1 | Out-Null
    Set-Content -LiteralPath (Join-Path $repoR 'leftover.txt') -Value 'uncommitted' -Encoding UTF8
    $dirtyRestore = Restore-RunnerStartBranch -RepoPath $repoR -StartBranch 'main' -WorkBranch 'roadmap/fixture-run'
    Assert-That (-not [bool]$dirtyRestore.restored -and $dirtyRestore.reason -match 'uncommitted' -and ((& git -C $repoR branch --show-current) | Out-String).Trim() -eq 'roadmap/fixture-run') 'restore: a dirty tree is never switched, and the refusal says why'
    $unknownRestore = Restore-RunnerStartBranch -RepoPath $repoR -StartBranch '' -WorkBranch 'roadmap/fixture-run'
    Assert-That (-not [bool]$unknownRestore.restored -and $unknownRestore.reason -match 'unknown') 'restore: an unrecorded start branch leaves the checkout alone with a reason'
    Assert-That ($runnerSource -match 'finally \{[\s\S]*Restore-RunnerStartBranch -RepoPath \$cloneRoot -StartBranch \$startBranch') 'restore: Invoke-QueuedTask restores the clone''s start branch in a finally, whatever the outcome'
    Assert-That ($runnerSource -match 'Update-TaskSummary -SummaryPath \$summaryPath -Set @\{ startBranch = \$startBranch \}') 'restore: the start branch is recorded in the run summary before the switch'

    # -- 10. The agent works in a run-owned worktree, never in the clone ------
    # Decision of 2026-10-17: the product must not switch branches in working
    # directories the owner also develops in. Workspaces live under the output
    # root (REPO_MGMT_OUTPUT_ROOT is still the scratch ledger root here).
    $runnerSource = Get-Content -LiteralPath (Join-Path $WorkspaceRoot 'scripts\Invoke-RoadmapTaskRunner.ps1') -Raw
    $repoW = Initialize-FixtureRepo -Name 'workspace-clone'
    $ws = New-RunWorkspace -CloneRoot $repoW -Branch 'roadmap/ws-run' -RunId 'ws-run' -WorkspaceRoot $WorkspaceRoot
    Assert-That ([bool]$ws.created -and (Test-Path -LiteralPath $ws.path)) "workspace: a worktree is created for the run, got '$($ws.reason)'"
    Assert-That ($ws.path.StartsWith((Join-Path $ledgerOutput 'agent-workspaces'), [System.StringComparison]::OrdinalIgnoreCase)) "workspace: it lives under the output root, not in the clone, got '$($ws.path)'"
    Assert-That (((& git -C $ws.path branch --show-current) | Out-String).Trim() -eq 'roadmap/ws-run') 'workspace: the worktree is on the run branch'
    Assert-That (((& git -C $repoW branch --show-current) | Out-String).Trim() -eq 'main') 'workspace: the clone stays on the branch the owner left it on'
    Set-Content -LiteralPath (Join-Path $ws.path 'agent.txt') -Value 'agent output' -Encoding UTF8
    & git -C $ws.path add agent.txt 2>&1 | Out-Null
    & git -C $ws.path -c user.name=fixture -c user.email=fixture@example.invalid commit -q -m 'agent work' 2>&1 | Out-Null
    Assert-That (-not (Test-Path -LiteralPath (Join-Path $repoW 'agent.txt'))) 'workspace: the agent''s edits never appear in the clone''s working tree'
    & git -C $repoW rev-parse --verify --quiet 'refs/heads/roadmap/ws-run' 2>&1 | Out-Null
    Assert-That ($LASTEXITCODE -eq 0) 'workspace: the run branch is visible from the clone, so approve-push can push it by name'
    $removed = Remove-RunWorkspace -CloneRoot $repoW -WorkspacePath $ws.path
    Assert-That ([bool]$removed.removed -and -not (Test-Path -LiteralPath $ws.path)) "workspace: a clean worktree is removed when the run ends, got '$($removed.reason)'"
    Assert-That (((& git -C $repoW rev-list --count 'roadmap/ws-run') | Out-String).Trim() -eq '2') 'workspace: removing the worktree keeps the branch and its commit'
    $wsDirty = New-RunWorkspace -CloneRoot $repoW -Branch 'roadmap/ws-dirty' -RunId 'ws-dirty' -WorkspaceRoot $WorkspaceRoot
    Set-Content -LiteralPath (Join-Path $wsDirty.path 'half-done.txt') -Value 'uncommitted' -Encoding UTF8
    $kept = Remove-RunWorkspace -CloneRoot $repoW -WorkspacePath $wsDirty.path
    Assert-That (-not [bool]$kept.removed -and $kept.reason -match 'uncommitted' -and (Test-Path -LiteralPath (Join-Path $wsDirty.path 'half-done.txt'))) 'workspace: uncommitted work is kept, recoverable at the recorded path'
    $reused = New-RunWorkspace -CloneRoot $repoW -Branch 'roadmap/ws-dirty' -RunId 'ws-dirty' -WorkspaceRoot $WorkspaceRoot
    Assert-That ([bool]$reused.created -and $reused.reason -match 'reused') 'workspace: a resumed run finds its own worktree again'
    $collided = $null
    try { New-RunWorkspace -CloneRoot $repoW -Branch 'roadmap/other' -RunId 'ws-dirty' -WorkspaceRoot $WorkspaceRoot | Out-Null } catch { $collided = $_.Exception.Message }
    Assert-That ($collided -match 'refusing to reuse') 'workspace: a path already holding another branch is refused, never overwritten'
    & git -C $repoW worktree remove --force $wsDirty.path 2>&1 | Out-Null
    $remapped = Convert-RunPathToWorkspace -Text ("Roadmap: {0}\ROADMAP.md and {0}x\other" -f $repoW) -CloneRoot $repoW -WorkspacePath 'Q:\ws\run'
    Assert-That ($remapped -eq ("Roadmap: Q:\ws\run\ROADMAP.md and {0}x\other" -f $repoW)) "remap: clone paths point into the workspace, and a longer sibling name is left alone, got '$remapped'"
    Assert-That ((Convert-RunPathToWorkspace -Text 'no paths here' -CloneRoot $repoW -WorkspacePath 'Q:\ws') -eq 'no paths here' -and (Convert-RunPathToWorkspace -Text '' -CloneRoot $repoW -WorkspacePath 'Q:\ws') -eq '') 'remap: text without the clone path, or empty text, is unchanged'
    Assert-That ($runnerSource -match 'New-RunWorkspace -CloneRoot \$cloneRoot -Branch \$branch' -and $runnerSource -notmatch 'git -C \$repo switch -c \$branch') 'workspace: Invoke-QueuedTask creates a worktree and no longer switches the clone'
    Assert-That ($runnerSource -match 'finally \{[\s\S]*Remove-RunWorkspace -CloneRoot \$cloneRoot') 'workspace: the worktree is cleaned up in the finally, whatever the outcome'

    # -- 11. The agent never inherits a GitHub write credential ------------------
    $savedGh = $env:GH_TOKEN
    $savedGithub = $env:GITHUB_TOKEN
    try {
        Remove-Item -LiteralPath 'Env:GH_TOKEN' -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath 'Env:GITHUB_TOKEN' -ErrorAction SilentlyContinue
        $clean = Test-RunnerCredentialIsolation
        Assert-That ([bool]$clean.isolated -and @($clean.present).Count -eq 0) 'isolation: no token in the process reads isolated'
        $env:GH_TOKEN = 'fixture-secret-value'
        $leaky = Test-RunnerCredentialIsolation
        Assert-That (-not [bool]$leaky.isolated -and @($leaky.present) -contains 'GH_TOKEN') 'isolation: a token in the process is named'
        Assert-That ($leaky.summary -notmatch 'fixture-secret-value') 'isolation: the summary names the variable, never its value'
    }
    finally {
        if ($null -eq $savedGh) { Remove-Item -LiteralPath 'Env:GH_TOKEN' -ErrorAction SilentlyContinue } else { $env:GH_TOKEN = $savedGh }
        if ($null -eq $savedGithub) { Remove-Item -LiteralPath 'Env:GITHUB_TOKEN' -ErrorAction SilentlyContinue } else { $env:GITHUB_TOKEN = $savedGithub }
    }
    Assert-That ($runnerSource -match 'Test-RunnerCredentialIsolation[\s\S]*Refusing to launch the agent') 'isolation: the runner refuses to launch an agent while a token is in its environment'
    Assert-That ($runnerSource -match '-TokenIsolation \(') 'isolation: the heartbeat carries the isolation verdict for the host to show'
    $providerConfig = Get-Content -LiteralPath (Join-Path $WorkspaceRoot 'backend\config\agent-providers.json') -Raw | ConvertFrom-Json
    Assert-That (-not [bool]$providerConfig.providers.claude.autoPush -and -not [bool]$providerConfig.providers.codex.autoPush) 'publication: no local provider pushes on its own; the push and the PR stay behind approve-push'

    # -- 12. The PR base comes from repository policy, validated, or is refused --
    $repoP = Initialize-FixtureRepo -Name 'base-policy'
    $bareP = Join-Path $scratch 'base-policy-remote.git'
    & git init --bare -q -b main $bareP 2>&1 | Out-Null
    & git -C $repoP remote add origin $bareP 2>&1 | Out-Null
    & git -C $repoP push -q origin main 2>&1 | Out-Null
    & git -C $repoP branch staging 2>&1 | Out-Null
    & git -C $repoP push -q origin staging 2>&1 | Out-Null
    & git -C $repoP remote set-head origin main 2>&1 | Out-Null
    $policyPath = Join-Path $scratch 'repo-policies.json'
    (@{ schemaVersion = '1'; repositories = @{ 'base-policy' = @{ prBase = 'staging'; reason = 'fixture flow' }; ghost = @{ prBase = 'nope' } } } | ConvertTo-Json -Depth 5) | Set-Content -LiteralPath $policyPath -Encoding UTF8
    $fromPolicy = Resolve-RepoPullRequestBase -WorkspaceRoot $WorkspaceRoot -RepoName 'base-policy' -RepoPath $repoP -PolicyPath $policyPath
    Assert-That ([bool]$fromPolicy.ok -and $fromPolicy.base -eq 'staging' -and $fromPolicy.source -match 'policy') "base: explicit policy names the base, got '$($fromPolicy.reason)'"
    $overRequest = Resolve-RepoPullRequestBase -WorkspaceRoot $WorkspaceRoot -RepoName 'base-policy' -RepoPath $repoP -RequestedBase 'main' -PolicyPath $policyPath
    Assert-That ([bool]$overRequest.ok -and $overRequest.base -eq 'staging' -and $overRequest.reason -match 'policy wins') 'base: a dispatch that asked for main is overruled by policy, and the reason says so'
    $fromRemote = Resolve-RepoPullRequestBase -WorkspaceRoot $WorkspaceRoot -RepoName 'unlisted' -RepoPath $repoP -PolicyPath $policyPath
    Assert-That ([bool]$fromRemote.ok -and $fromRemote.base -eq 'main' -and $fromRemote.source -match 'origin/HEAD') "base: without policy the remote's default branch is used, got '$($fromRemote.reason)'"
    & git -C $repoP remote set-head origin --delete 2>&1 | Out-Null
    $noHead = Resolve-RepoPullRequestBase -WorkspaceRoot $WorkspaceRoot -RepoName 'unlisted' -RepoPath $repoP -PolicyPath $policyPath
    Assert-That ([bool]$noHead.ok -and $noHead.base -eq 'main' -and $noHead.source -match 'origin/HEAD unset') "base: a clone with no origin/HEAD uses origin/main only because it exists on origin, got '$($noHead.reason)'"
    & git -C $repoP remote set-head origin main 2>&1 | Out-Null
    $ghost = Resolve-RepoPullRequestBase -WorkspaceRoot $WorkspaceRoot -RepoName 'ghost' -RepoPath $repoP -PolicyPath $policyPath
    Assert-That (-not [bool]$ghost.ok -and $ghost.reason -match 'does not exist on origin') 'base: a policy branch missing from origin refuses publication by name'
    $repoN = Initialize-FixtureRepo -Name 'no-remote'
    $unresolved = Resolve-RepoPullRequestBase -WorkspaceRoot $WorkspaceRoot -RepoName 'no-remote' -RepoPath $repoN -PolicyPath $policyPath
    Assert-That (-not [bool]$unresolved.ok -and $unresolved.reason -match 'No pull-request base resolved') 'base: no policy and no origin/HEAD refuses rather than guessing main'
    $shipped = Resolve-RepoPullRequestBase -WorkspaceRoot $WorkspaceRoot -RepoName 'FreshStartFamily' -RepoPath ''
    Assert-That ([bool]$shipped.ok -and $shipped.base -eq 'staging') 'base: the shipped policy sends FreshStartFamily pull requests to staging'
    $hostSource = Get-Content -LiteralPath (Join-Path $WorkspaceRoot 'backend\api-host\Start-RepoManagementApiHost.ps1') -Raw
    Assert-That (([regex]::Matches($hostSource, 'Resolve-RepoPullRequestBase -WorkspaceRoot')).Count -ge 2 -and ([regex]::Matches($hostSource, '-BaseBranch \(\[string\]\$\w+Base\.base\)')).Count -ge 2) 'base: both PR-opening paths (approve-push and the reconcile tick) resolve the base and pass it'

    # -- 13. A live runner keeps its run; only a dead runner's run is orphaned --
    $runsO = Join-Path $scratch 'orphan-runs'
    $null = New-Item -ItemType Directory -Path $runsO -Force
    foreach ($pair in @(@('run-alive', 4242), @('run-dead', 4243), @('run-self', $PID))) {
        (@{ runId = $pair[0]; status = 'running'; runnerPid = $pair[1]; dispatchTarget = 'claude'; branch = ('roadmap/{0}' -f $pair[0]) } | ConvertTo-Json) | Set-Content -LiteralPath (Join-Path $runsO ("{0}.summary.json" -f $pair[0])) -Encoding UTF8
    }
    $pcFixture = [pscustomobject]@{ providers = [pscustomobject]@{ claude = [pscustomobject]@{ executionMode = 'local' } } }
    $orphaned = @(Repair-OrphanedRunSummary -RunsDir $runsO -CurrentPid 1 -Config $pcFixture -IsProcessAlive { param([int]$ProcessId) $ProcessId -eq 4242 })
    Assert-That ($orphaned -contains 'run-dead' -and $orphaned -notcontains 'run-alive') "orphan: a run whose runner process is alive is owned, not abandoned, got: $($orphaned -join ', ')"
    $aliveSummary = Get-Content -LiteralPath (Join-Path $runsO 'run-alive.summary.json') -Raw | ConvertFrom-Json
    Assert-That ($aliveSummary.status -eq 'running') 'orphan: the live runner''s summary is untouched'
    $runsSelf = Join-Path $scratch 'orphan-runs-self'
    $null = New-Item -ItemType Directory -Path $runsSelf -Force
    (@{ runId = 'run-self'; status = 'running'; runnerPid = $PID; dispatchTarget = 'claude'; branch = 'roadmap/run-self' } | ConvertTo-Json) | Set-Content -LiteralPath (Join-Path $runsSelf 'run-self.summary.json') -Encoding UTF8
    $selfSweep = @(Repair-OrphanedRunSummary -RunsDir $runsSelf -CurrentPid 1 -Config $pcFixture)
    Assert-That ($selfSweep -notcontains 'run-self' -and (Get-Content -LiteralPath (Join-Path $runsSelf 'run-self.summary.json') -Raw | ConvertFrom-Json).status -eq 'running') 'orphan: the default liveness check finds this very process alive and leaves its run running'
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
