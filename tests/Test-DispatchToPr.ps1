#Requires -Version 7.0
<#
.SYNOPSIS
    A dispatched agent run ends in a pull request on another repository, and a
    run whose runner died is closed as abandoned (loop steps 3 to 5).

.DESCRIPTION
    The 2026-10-16 evaluation found no agent run outside the smoke tests since
    2026-09-01 and 45 of 80 real runner runs failed, one class of them a runner
    pid that no longer matched the heartbeat, leaving the run `running` for
    good. This gate drives the real code offline:

      Dispatch to PR. A finished run's structured result decides its outcome
      (Resolve-RunOutcomeFromResult, read from the runner by AST). With the
      shipped provider config the runner does not push (autoPush off: approval
      stays on publication), so the run waits at awaiting-review. Approving it
      runs Invoke-RunApprovePush, the body of POST
      /api/roadmap-agent/approve-push: a real `git push` to a local bare
      remote, then a pull request opened through the GitHub API, which is the
      only thing stubbed. The run summary records the PR URL. A base that
      cannot resolve still pushes, and the run records the named refusal.

      Abandoned run. Repair-OrphanedRunSummary -HeartbeatPath, the host's
      sweep, closes a local run whose runner pid no longer matches a fresh
      heartbeat and whose process is gone: failed, category `orphaned`, with
      its reason. A run owned by the heartbeat's runner, a run whose process is
      still alive, and a github-hosted run are left alone. With no fresh
      heartbeat only process liveness protects a run.

      Wiring. The approve-push route calls Invoke-RunApprovePush and pushes
      nothing itself; the history route sweeps before it lists runs.

    Nothing touches a live root: every path is under a temp scratch directory.

.EXAMPLE
    pwsh ./tests/Test-DispatchToPr.ps1 -FailOnError
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
. (Join-Path $WorkspaceRoot 'backend\modules\git\Git.BaseFreshness.ps1')
. (Join-Path $WorkspaceRoot 'backend\modules\roadmap\Roadmap.PrSubmitter.ps1')
. (Join-Path $WorkspaceRoot 'backend\modules\execution\Execution.WorkPacket.ps1')
. (Join-Path $WorkspaceRoot 'backend\modules\execution\Execution.ProviderRegistry.ps1')
. (Join-Path $WorkspaceRoot 'backend\modules\execution\Execution.ProviderCapacity.ps1')

$failures = [System.Collections.Generic.List[string]]::new()
$passed = 0
function Assert-That {
    param([bool]$Condition, [string]$Message)
    if ($Condition) { $script:passed++ } else { $script:failures.Add($Message) }
}

# The GitHub API, and only the GitHub API, is injected. Every call is recorded
# so the gate can say what was asked of GitHub, not merely that it answered.
$script:GitHubCalls = [System.Collections.Generic.List[object]]::new()
$script:NextPrNumber = 101
function Invoke-RestMethod {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidOverwritingBuiltInCmdlets', '', Justification = 'The GitHub API is the one thing this gate stubs; the modules call the cmdlet by name.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'ContentType', Justification = 'Matches the call signature Open-RepoBranchPullRequest uses.')]
    param([string]$Uri, [hashtable]$Headers, [string]$Method = 'Get', [string]$Body = '', [string]$ContentType = '')
    $payload = if ([string]::IsNullOrWhiteSpace($Body)) { $null } else { $Body | ConvertFrom-Json }
    $script:GitHubCalls.Add([pscustomobject]@{ uri = $Uri; method = $Method; payload = $payload; auth = [string]$Headers['Authorization'] })
    if ($Method -eq 'Post' -and $Uri -match '^https://api\.github\.com/repos/([^/]+)/([^/]+)/pulls$') {
        $number = $script:NextPrNumber
        $script:NextPrNumber++
        return [pscustomobject]@{
            number   = $number
            html_url = ("https://github.com/{0}/{1}/pull/{2}" -f $Matches[1], $Matches[2], $number)
            head     = [pscustomobject]@{ sha = ('{0:x40}' -f $number) }
        }
    }
    throw ("Unexpected GitHub call in the fixture: {0} {1}" -f $Method, $Uri)
}

$scratch = Join-Path ([System.IO.Path]::GetTempPath()) ("dispatch-to-pr-{0}" -f [guid]::NewGuid().ToString('n'))
$null = New-Item -ItemType Directory -Path $scratch -Force
$emptyGitConfig = Join-Path $scratch 'empty.gitconfig'
Set-Content -LiteralPath $emptyGitConfig -Value '' -Encoding UTF8
$savedEnv = @{ GIT_CONFIG_GLOBAL = $env:GIT_CONFIG_GLOBAL; GIT_CONFIG_NOSYSTEM = $env:GIT_CONFIG_NOSYSTEM }
$env:GIT_CONFIG_GLOBAL = $emptyGitConfig
$env:GIT_CONFIG_NOSYSTEM = '1'

function Invoke-FixtureGit {
    param([string]$Path, [string[]]$GitArgs)
    $out = (& git -C $Path -c user.name=fixture -c user.email=fixture@example.invalid @GitArgs 2>&1) | Out-String
    if ($LASTEXITCODE -ne 0) { throw ("fixture git {0} failed: {1}" -f ($GitArgs -join ' '), $out.Trim()) }
    return $out.Trim()
}

function Initialize-FixtureClone {
    <# A clone whose fetch URL is a GitHub URL (so the slug resolves) and whose
       push URL is a local bare repository (so the push is real). #>
    param([string]$Name, [switch]$NoRemoteTracking)
    $bare = Join-Path $scratch ("{0}.git" -f $Name)
    $null = New-Item -ItemType Directory -Path $bare -Force
    & git init -q --bare -b main $bare 2>&1 | Out-Null
    $clone = Join-Path $scratch $Name
    $null = New-Item -ItemType Directory -Path $clone -Force
    & git -C $clone init -q -b main 2>&1 | Out-Null
    Set-Content -LiteralPath (Join-Path $clone 'ROADMAP.md') -Value "# Roadmap`n`n- [ ] Add retry with backoff to the uploader`n" -Encoding UTF8 -NoNewline
    $null = Invoke-FixtureGit -Path $clone -GitArgs @('add', 'ROADMAP.md')
    $null = Invoke-FixtureGit -Path $clone -GitArgs @('commit', '-q', '-m', 'init')
    $null = Invoke-FixtureGit -Path $clone -GitArgs @('remote', 'add', 'origin', ("https://github.com/fixture-owner/{0}.git" -f $Name))
    $null = Invoke-FixtureGit -Path $clone -GitArgs @('remote', 'set-url', '--push', 'origin', $bare)
    $null = Invoke-FixtureGit -Path $clone -GitArgs @('push', '-q', 'origin', 'main')
    if ($NoRemoteTracking) {
        # The push above recorded origin/main; a clone that never fetched has none.
        $null = Invoke-FixtureGit -Path $clone -GitArgs @('update-ref', '-d', 'refs/remotes/origin/main')
    }
    else {
        # What a fetch would have recorded; the fetch URL is not reachable offline.
        $null = Invoke-FixtureGit -Path $clone -GitArgs @('update-ref', 'refs/remotes/origin/main', 'main')
        $null = Invoke-FixtureGit -Path $clone -GitArgs @('symbolic-ref', 'refs/remotes/origin/HEAD', 'refs/remotes/origin/main')
    }
    return [pscustomobject]@{ clone = $clone; bare = $bare }
}

function Initialize-FinishedRun {
    <# The state the runner leaves for a completed local run: a committed work
       branch in the clone and a summary at awaiting-review. #>
    param([string]$Clone, [string]$RunsDir, [string]$RunId)
    $branch = "roadmap-task/$RunId"
    $null = Invoke-FixtureGit -Path $Clone -GitArgs @('checkout', '-q', '-b', $branch)
    Set-Content -LiteralPath (Join-Path $Clone 'uploader.ps1') -Value "# retry with backoff`n" -Encoding UTF8 -NoNewline
    $null = Invoke-FixtureGit -Path $Clone -GitArgs @('add', 'uploader.ps1')
    $null = Invoke-FixtureGit -Path $Clone -GitArgs @('commit', '-q', '-m', 'feat: retry with backoff')
    $sha = Invoke-FixtureGit -Path $Clone -GitArgs @('rev-parse', 'HEAD')
    $null = Invoke-FixtureGit -Path $Clone -GitArgs @('checkout', '-q', 'main')
    $summary = [ordered]@{
        runId = $RunId; status = 'awaiting-review'; repository = (Split-Path -Leaf $Clone); localRepoPath = $Clone
        branch = $branch; baseBranch = 'main'; selectedTask = 'Add retry with backoff to the uploader'
        selectedProvider = 'claude'; runnerPid = 4242; runnerStartedAt = '2026-11-11T10:00:00Z'
    }
    ([pscustomobject]$summary | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath (Join-Path $RunsDir "$RunId.summary.json") -Encoding UTF8
    return [pscustomobject]@{ branch = $branch; sha = $sha; summaryPath = (Join-Path $RunsDir "$RunId.summary.json") }
}

try {
    # ---------------------------------------------------------------- runner half
    $runnerPath = Join-Path $WorkspaceRoot 'scripts/Invoke-RoadmapTaskRunner.ps1'
    $runnerAst = [System.Management.Automation.Language.Parser]::ParseFile($runnerPath, [ref]$null, [ref]$null)
    foreach ($name in 'Resolve-RunOutcomeFromResult', 'Resolve-PostImplementationTransition') {
        $fn = $runnerAst.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }.GetNewClosure(), $true)
        Assert-That ($null -ne $fn) "the runner defines $name"
        if ($null -ne $fn) { . ([scriptblock]::Create($fn.Extent.Text)) }
    }

    $result = [pscustomobject]@{ taskId = 't-1'; executionId = 'run-ok'; provider = 'claude'; status = 'implementation_complete'; changedFiles = @('uploader.ps1') }
    $outcome = Resolve-RunOutcomeFromResult -Result $result -ExitCode 0
    Assert-That ($outcome.status -eq 'awaiting-review') "runner: a valid implementation_complete result reaches awaiting-review, got '$($outcome.status)'"

    $providerConfig = Get-AgentProviderConfig -ConfigPath (Get-AgentProviderConfigPath -WorkspaceRoot $WorkspaceRoot)
    $transition = Resolve-PostImplementationTransition -Outcome $outcome.status -ProviderConfig $providerConfig.providers.claude -VerifyResult 'passed'
    Assert-That (-not $transition.push -and $transition.nextStatus -eq 'awaiting-review') 'runner: with the shipped config the claude run does not push on its own; it waits for approval'

    # ------------------------------------------------------------- dispatch to PR
    $runsDir = Join-Path $scratch 'runs'
    $null = New-Item -ItemType Directory -Path $runsDir -Force
    $fx = Initialize-FixtureClone -Name 'widget'
    $run = Initialize-FinishedRun -Clone $fx.clone -RunsDir $runsDir -RunId 'run-ok'

    $approve = Invoke-RunApprovePush -WorkspaceRoot $WorkspaceRoot -RunsDir $runsDir -RunId 'run-ok' -Token 'fixture-token-not-real'
    Assert-That ($approve.ok -and $approve.statusCode -eq 200) "approve: an awaiting-review run is approved, got $($approve.statusCode) '$($approve.error)'"

    $remoteSha = ((& git -C $fx.bare rev-parse --verify --quiet ("refs/heads/{0}" -f $run.branch) 2>&1) | Out-String).Trim()
    Assert-That ($remoteSha -eq $run.sha) "push: the bare remote holds the run branch at the run's commit ($($run.sha)), got '$remoteSha'"
    $remoteMain = ((& git -C $fx.bare rev-parse main 2>&1) | Out-String).Trim()
    $cloneMain = ((& git -C $fx.clone rev-parse main 2>&1) | Out-String).Trim()
    Assert-That ($remoteMain -eq $cloneMain) 'push: the remote default branch is untouched'

    $posts = @($script:GitHubCalls | Where-Object { $_.method -eq 'Post' })
    Assert-That ($posts.Count -eq 1) "github: exactly one pull request is requested, got $($posts.Count)"
    if ($posts.Count -ge 1) {
        Assert-That ($posts[0].uri -eq 'https://api.github.com/repos/fixture-owner/widget/pulls') "github: the PR is opened on the run's repository, got '$($posts[0].uri)'"
        Assert-That ($posts[0].payload.head -eq $run.branch -and $posts[0].payload.base -eq 'main') 'github: the PR goes from the run branch onto the resolved base'
        Assert-That ($posts[0].payload.title -eq 'Add retry with backoff to the uploader') 'github: the PR title is the roadmap item'
        Assert-That ([string]$posts[0].payload.body -match 'run-ok') 'github: the PR body names the run'
    }

    $recorded = Get-Content -LiteralPath $run.summaryPath -Raw | ConvertFrom-Json
    Assert-That ($recorded.status -eq 'pushed') "record: the run reads pushed, got '$($recorded.status)'"
    Assert-That ($recorded.prState -eq 'open') "record: the run reads prState open, got '$($recorded.prState)'"
    Assert-That ($recorded.prUrl -eq 'https://github.com/fixture-owner/widget/pull/101') "record: the run records the PR URL, got '$($recorded.prUrl)'"
    Assert-That ($recorded.prNumber -eq 101 -and -not [string]::IsNullOrWhiteSpace([string]$recorded.prOpenedAt)) 'record: the run records the PR number and when it opened'
    Assert-That ($approve.data.prUrl -eq $recorded.prUrl) 'record: the route answer and the run record name the same PR'
    $rawSummary = Get-Content -LiteralPath $run.summaryPath -Raw
    Assert-That ($rawSummary -notmatch 'fixture-token-not-real' -and ([string]$approve.data.output) -notmatch 'fixture-token-not-real') 'record: the token never reaches the run record or the answer'

    $again = Invoke-RunApprovePush -WorkspaceRoot $WorkspaceRoot -RunsDir $runsDir -RunId 'run-ok' -Token 'fixture-token-not-real'
    Assert-That (-not $again.ok -and $again.statusCode -eq 409) 'approve: a run already pushed cannot be approved again (409)'
    Assert-That (@($script:GitHubCalls | Where-Object { $_.method -eq 'Post' }).Count -eq 1) 'approve: a refused second approval asks GitHub for nothing'

    $badId = Invoke-RunApprovePush -WorkspaceRoot $WorkspaceRoot -RunsDir $runsDir -RunId '../escape'
    Assert-That (-not $badId.ok -and $badId.statusCode -eq 400 -and $badId.category -eq 'validation') 'approve: a runId outside [A-Za-z0-9._-] is refused (400)'
    $missing = Invoke-RunApprovePush -WorkspaceRoot $WorkspaceRoot -RunsDir $runsDir -RunId 'run-none'
    Assert-That (-not $missing.ok -and $missing.statusCode -eq 404) 'approve: an unknown run is 404'

    # A base that cannot resolve: the push still happens and the run says why
    # no PR exists, instead of reading pushed with nothing behind it.
    $fxNoBase = Initialize-FixtureClone -Name 'gadget' -NoRemoteTracking
    $runNoBase = Initialize-FinishedRun -Clone $fxNoBase.clone -RunsDir $runsDir -RunId 'run-nobase'
    $noBase = Invoke-RunApprovePush -WorkspaceRoot $WorkspaceRoot -RunsDir $runsDir -RunId 'run-nobase' -Token 'fixture-token-not-real'
    Assert-That ($noBase.ok -and $null -eq $noBase.data.prUrl -and $noBase.data.prRefusal.category -eq 'pr-base-policy') 'refusal: an unresolvable base pushes and answers with the named refusal'
    $remoteNoBase = ((& git -C $fxNoBase.bare rev-parse --verify --quiet ("refs/heads/{0}" -f $runNoBase.branch) 2>&1) | Out-String).Trim()
    Assert-That ($remoteNoBase -eq $runNoBase.sha) 'refusal: the branch is still pushed'
    $recNoBase = Get-Content -LiteralPath $runNoBase.summaryPath -Raw | ConvertFrom-Json
    Assert-That ($recNoBase.status -eq 'pushed' -and $recNoBase.prState -eq 'open-refused') "refusal: the run reads pushed / open-refused, got '$($recNoBase.status)' / '$($recNoBase.prState)'"
    Assert-That ($recNoBase.prRefusal.category -eq 'pr-base-policy' -and -not [string]::IsNullOrWhiteSpace([string]$recNoBase.prRefusal.reason)) 'refusal: the run records the refusal category and reason'
    Assert-That (-not ($recNoBase.PSObject.Properties.Name -contains 'prUrl')) 'refusal: no PR URL is invented'
    Assert-That (@($script:GitHubCalls | Where-Object { $_.method -eq 'Post' }).Count -eq 1) 'refusal: GitHub is not asked to open a PR against an unresolved base'

    # ------------------------------------------------------------ abandoned runs
    $abRuns = Join-Path $scratch 'abandoned-runs'
    $null = New-Item -ItemType Directory -Path $abRuns -Force
    $now = [datetime]::new(2026, 11, 11, 12, 0, 0, [DateTimeKind]::Utc)
    function Write-RunningSummary {
        param([string]$RunId, [object]$RunnerPid, [string]$Provider = 'claude')
        $s = [ordered]@{ runId = $RunId; status = 'running'; selectedProvider = $Provider; branch = "roadmap-task/$RunId"; attempt = 1 }
        if ($null -ne $RunnerPid) { $s['runnerPid'] = $RunnerPid }
        ([pscustomobject]$s | ConvertTo-Json) | Set-Content -LiteralPath (Join-Path $abRuns "$RunId.summary.json") -Encoding UTF8
    }
    function Read-Run { param([string]$RunId) Get-Content -LiteralPath (Join-Path $abRuns "$RunId.summary.json") -Raw | ConvertFrom-Json }
    $heartbeat = Join-Path $scratch 'roadmap-task-runner.heartbeat.json'
    ([pscustomobject]@{ pid = 7002; lastHeartbeatAt = $now.AddMinutes(-1).ToString('o') } | ConvertTo-Json) | Set-Content -LiteralPath $heartbeat -Encoding UTF8

    Write-RunningSummary -RunId 'dead-runner' -RunnerPid 7001
    Write-RunningSummary -RunId 'live-runner' -RunnerPid 7002
    Write-RunningSummary -RunId 'second-runner' -RunnerPid 7003
    Write-RunningSummary -RunId 'cloud-run' -RunnerPid 7001 -Provider 'copilot'
    $alive = { param([int]$ProcessId) $ProcessId -in 7002, 7003 }

    $closed = @(Repair-OrphanedRunSummary -RunsDir $abRuns -HeartbeatPath $heartbeat -NowUtc $now -Config $providerConfig -IsProcessAlive $alive)
    Assert-That ($closed.Count -eq 1 -and $closed[0] -eq 'dead-runner') "abandoned: only the dead runner's run is closed, got '$($closed -join ', ')'"
    $dead = Read-Run 'dead-runner'
    Assert-That ($dead.status -eq 'failed' -and $dead.failureCategory -eq 'orphaned') 'abandoned: the run is closed failed / orphaned, never left running'
    Assert-That ([string]$dead.error -match 'runner pid 7001 no longer matches the heartbeat \(live runner pid: 7002\)' -and [string]$dead.error -match 'abandoned') "abandoned: the reason names the pid, the heartbeat and the abandonment, got '$($dead.error)'"
    Assert-That (-not [string]::IsNullOrWhiteSpace([string]$dead.orphanedAt) -and $dead.branch -eq 'roadmap-task/dead-runner' -and $dead.attempt -eq 1) 'abandoned: when, and everything needed to retry, are kept'
    Assert-That ((Read-Run 'live-runner').status -eq 'running') "abandoned: the heartbeat runner's own run stays running"
    Assert-That ((Read-Run 'second-runner').status -eq 'running') 'abandoned: a run whose runner process is alive is owned, not abandoned'
    Assert-That ((Read-Run 'cloud-run').status -eq 'running') 'abandoned: a github-hosted run continues off this machine and is left alone'

    $again = @(Repair-OrphanedRunSummary -RunsDir $abRuns -HeartbeatPath $heartbeat -NowUtc $now -Config $providerConfig -IsProcessAlive $alive)
    Assert-That ($again.Count -eq 0) 'abandoned: a second sweep changes nothing'

    # A stale heartbeat names no live runner: its own pid no longer protects a
    # run whose process is gone, and a missing heartbeat reads "none".
    ([pscustomobject]@{ pid = 7002; lastHeartbeatAt = $now.AddMinutes(-45).ToString('o') } | ConvertTo-Json) | Set-Content -LiteralPath $heartbeat -Encoding UTF8
    $stale = @(Repair-OrphanedRunSummary -RunsDir $abRuns -HeartbeatPath $heartbeat -NowUtc $now -Config $providerConfig -IsProcessAlive { param([int]$ProcessId) $ProcessId -eq 7003 })
    Assert-That ($stale.Count -eq 1 -and $stale[0] -eq 'live-runner') "stale heartbeat: the dead runner's run is closed even though its pid is the heartbeat's, got '$($stale -join ', ')'"
    Assert-That ([string](Read-Run 'live-runner').error -match 'live runner pid: none') 'stale heartbeat: the reason says no runner is live'
    Assert-That ((Read-Run 'second-runner').status -eq 'running') 'stale heartbeat: a live process still protects its run'

    Write-RunningSummary -RunId 'no-heartbeat' -RunnerPid 7009
    $none = @(Repair-OrphanedRunSummary -RunsDir $abRuns -HeartbeatPath (Join-Path $scratch 'absent.heartbeat.json') -NowUtc $now -Config $providerConfig -IsProcessAlive { $false } -WhatIf)
    Assert-That ($none.Count -eq 0 -and (Read-Run 'no-heartbeat').status -eq 'running') 'abandoned: -WhatIf writes nothing'

    # -------------------------------------------------------------------- wiring
    $hostText = Get-Content -LiteralPath (Join-Path $WorkspaceRoot 'backend/api-host/Start-RepoManagementApiHost.ps1') -Raw
    $approveRoute = [regex]::Match($hostText, "(?s)'POST /api/roadmap-agent/approve-push' \{.*?\r?\n                \}\r?\n")
    Assert-That $approveRoute.Success 'wiring: the approve-push route exists'
    if ($approveRoute.Success) {
        Assert-That ($approveRoute.Value -match 'Invoke-RunApprovePush') 'wiring: the approve-push route calls Invoke-RunApprovePush'
        Assert-That ($approveRoute.Value -notmatch 'push -u origin' -and $approveRoute.Value -notmatch 'Open-RepoBranchPullRequest') 'wiring: the approve-push route pushes nothing and opens nothing itself'
    }
    $historyRoute = [regex]::Match($hostText, "(?s)'GET /api/roadmap-agent/history' \{.*?Get-RoadmapTaskHistory")
    Assert-That ($historyRoute.Success -and $historyRoute.Value -match 'Repair-OrphanedRunSummary\s[^\r\n]*-HeartbeatPath') 'wiring: the history route closes abandoned runs by heartbeat before it lists them'
}
finally {
    foreach ($key in $savedEnv.Keys) {
        if ($null -eq $savedEnv[$key]) { Remove-Item -LiteralPath ("Env:{0}" -f $key) -ErrorAction SilentlyContinue }
        else { Set-Item -LiteralPath ("Env:{0}" -f $key) -Value $savedEnv[$key] }
    }
    Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ("Test-DispatchToPr: {0} passed, {1} failed" -f $passed, $failures.Count)
foreach ($f in $failures) { Write-Host ("  FAIL: {0}" -f $f) }
if ($failures.Count -gt 0 -and $FailOnError) { exit 1 }
