#Requires -Version 7.0
<#
.SYNOPSIS
    Local runner: execute queued roadmap tasks with Claude Code on the LOCAL repo.

.DESCRIPTION
    Run this AS YOURSELF (your Claude Code auth + your `claude` on PATH) — never as
    the portal service. It watches output/roadmap-task-queue.jsonl for tasks the
    portal enqueued (status='queued' in their run summary) and, for each:

      claim (status='running') -> create branch roadmap/<runId> -> launch `claude`
      in the target repo with the task prompt -> best-effort verify -> commit any
      changes on the branch -> status='awaiting-review'.

    It STOPS there. Nothing is pushed to GitHub — you review the branch and push /
    open a PR yourself. Status flows back to the portal via the existing run
    summary (Get-RoadmapTaskHistory), so the ROADMAP modal reflects progress.

.PARAMETER Once
    Process the currently-queued tasks and exit (default is a poll loop).

.PARAMETER Headless
    Run `claude -p "<prompt>"` non-interactively instead of an interactive session.
    Tasks that run commands may need -PermissionMode bypassPermissions to avoid
    stalling on a prompt that headless mode cannot answer.

.PARAMETER PermissionMode
    Claude Code permission mode. Default 'acceptEdits' (auto-accept file edits).

.PARAMETER DryRun
    Show what would happen for each queued task without claiming, branching,
    launching claude, or committing. Safe to demo.

.PARAMETER AcknowledgeStaleBase
    Proceed even when the target clone is verified behind its remote base.
    Off by default: an agent that reads a stale working copy produces a
    proposal computed from out-of-date content, which merges cleanly and reads
    as correct in review. Use this only when you know the base is stale and
    want the task run against it anyway.

.PARAMETER SyncMain
    Release 3.4, step 2 of the delivery loop: fast-forward the repository's
    default branch to its remote tip before branching from it. Off by default,
    because moving a ref in someone's working copy is an action, not a read.
    Only a clone that is strictly BEHIND is moved; a default branch carrying
    local commits refuses as `default-branch-ahead`, and a diverged one refuses
    outright. Never a merge, never a rebase, never a force.

.PARAMETER LoadFunctionsOnly
    Dot-source the pure functions without running (used by the module smoke).

.EXAMPLE
    pwsh -File scripts/Invoke-RoadmapTaskRunner.ps1 -Once
.EXAMPLE
    pwsh -File scripts/Invoke-RoadmapTaskRunner.ps1 -Headless -PermissionMode bypassPermissions
#>
[CmdletBinding()]
param(
    [string]$WorkspaceRoot,
    [string]$QueuePath,
    [switch]$Once,
    [switch]$Headless,
    [string]$PermissionMode = 'acceptEdits',
    [int]$PollSeconds = 15,
    [switch]$DryRun,
    [switch]$AcknowledgeStaleBase,
    [switch]$SyncMain,
    [switch]$LoadFunctionsOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($WorkspaceRoot)) { $WorkspaceRoot = Split-Path -Parent $PSScriptRoot }
if ([string]::IsNullOrWhiteSpace($QueuePath)) { $QueuePath = Join-Path $WorkspaceRoot 'output\roadmap-task-queue.jsonl' }
$runsDir = Join-Path $WorkspaceRoot 'output\roadmap-task-history\runs'

# Hoisted to an explicit script-scoped value: Invoke-QueuedTask reads it from
# inside a function, which PowerShell resolves dynamically but leaves invisible
# to both the analyzer and the next reader.
$script:AcknowledgeStaleBase = [bool]$AcknowledgeStaleBase
$script:SyncMain = [bool]$SyncMain

# Release 3.1 — the base-freshness probe lives in the git module so the submit-PR
# path and this runner share one definition of "stale" rather than each growing
# its own.
$script:BaseFreshnessModule = Join-Path $WorkspaceRoot 'backend\modules\git\Git.BaseFreshness.ps1'
if (Test-Path -LiteralPath $script:BaseFreshnessModule) { . $script:BaseFreshnessModule }

$script:DefaultBranchSyncModule = Join-Path $WorkspaceRoot 'backend\modules\git\Git.DefaultBranchSync.ps1'
if (Test-Path -LiteralPath $script:DefaultBranchSyncModule) { . $script:DefaultBranchSyncModule }

function Test-RunnerBaseFreshness {
    <#
        .SYNOPSIS
            Ask the shared probe whether this clone is current with its remote.
        .DESCRIPTION
            Returns $null when the probe is unavailable, which callers treat as
            "not checked" rather than "fresh". Never throws: the guard must not
            be the thing that breaks the runner.
    #>
    param([Parameter()][AllowEmptyString()][string]$RepoPath = '')
    if (-not (Get-Command -Name 'Get-RepoBaseFreshness' -ErrorAction SilentlyContinue)) { return $null }
    try { return Get-RepoBaseFreshness -RepoPath $RepoPath }
    catch { return $null }
}

# ── Pure / testable helpers (module smoke covers these; no git, no claude) ────
function Get-QueueEntries {
    param([Parameter(Mandatory)][string]$QueuePath)
    $entries = [System.Collections.Generic.List[object]]::new()
    if (-not (Test-Path -LiteralPath $QueuePath)) { return $entries.ToArray() }
    foreach ($line in (Get-Content -LiteralPath $QueuePath -Encoding UTF8)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try { $entries.Add(($line | ConvertFrom-Json)) } catch { }
    }
    return $entries.ToArray()
}

function New-TaskCommitMessage {
    param([Parameter(Mandatory)][string]$SelectedTask, [Parameter(Mandatory)][string]$RunId)
    $t = $SelectedTask.Trim()
    if ($t.Length -gt 68) { $t = $t.Substring(0, 68) }
    return "roadmap: $t`n`nRun: $RunId (queued via portal, executed by the local runner)."
}

function Resolve-VerifyCommand {
    <# Best-effort detection of a per-repo check. Returns a scriptblock-friendly
       command string or $null. Non-blocking — a failing verify is recorded, not
       fatal. #>
    param([Parameter(Mandatory)][string]$RepoPath)
    $pkg = Join-Path $RepoPath 'package.json'
    if (Test-Path -LiteralPath $pkg) {
        try {
            $j = Get-Content -LiteralPath $pkg -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($j.PSObject.Properties.Name -contains 'scripts' -and $j.scripts.PSObject.Properties.Name -contains 'test') {
                return 'npm test'
            }
        }
        catch { }
    }
    if (Test-Path -LiteralPath (Join-Path $RepoPath 'scripts\Invoke-TestSuite.ps1')) { return 'pwsh -NoProfile -File scripts/Invoke-TestSuite.ps1' }
    return $null
}

function Get-TaskSummaryStatus {
    param([Parameter(Mandatory)][string]$SummaryPath)
    if (-not (Test-Path -LiteralPath $SummaryPath)) { return $null }
    try { return [string]((Get-Content -LiteralPath $SummaryPath -Raw -Encoding UTF8 | ConvertFrom-Json).status) } catch { return $null }
}

# ── Release 3.0: cloud (Copilot) dispatch, executed in the operator session ───

function Get-QueueEntryDispatchTarget {
    <#
    .SYNOPSIS
        Pure — which tool a queue entry names, defaulting only for old entries.
    .DESCRIPTION
        An entry written before Release 3.0 has no `dispatchTarget` and is a
        Claude Code task, so an absent value resolves to 'claude'. An entry
        naming something ELSE is refused rather than defaulted: running an
        unrecognized target as Claude Code would execute the wrong tool against
        a real repository, which is worse than refusing to claim it.
    #>
    param([Parameter(Mandatory)][object]$Entry)

    $raw = ''
    if ($Entry.PSObject.Properties.Name -contains 'dispatchTarget' -and $Entry.dispatchTarget) {
        $raw = [string]$Entry.dispatchTarget
    }
    if ([string]::IsNullOrWhiteSpace($raw)) { return 'claude' }
    $normalized = $raw.Trim().ToLowerInvariant()
    if ($normalized -notin @('claude', 'copilot')) {
        throw ("Unknown dispatchTarget '{0}'; refusing to guess which tool to run. Allowed: claude, copilot." -f $raw)
    }
    return $normalized
}

function New-CopilotAgentTaskArgs {
    <#
    .SYNOPSIS
        Pure — the `gh agent-task create` argv for a queued copilot entry.
    .DESCRIPTION
        Built as an array, never a command string: the prompt is multi-line
        roadmap text and interpolating it into a shell line would break on the
        first quote it contains.
    #>
    param(
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][string]$Prompt,
        [AllowEmptyString()][string]$BaseBranch = ''
    )

    if ([string]::IsNullOrWhiteSpace($Repository)) { throw 'A copilot entry needs repository (owner/repo).' }
    if ([string]::IsNullOrWhiteSpace($Prompt)) { throw 'A copilot entry needs a prompt.' }

    # Not $args — that is an automatic variable, and shadowing it inside an
    # advanced function is a debugging trap for whoever reads this next.
    $ghArgv = [System.Collections.Generic.List[string]]::new()
    $ghArgv.Add('agent-task'); $ghArgv.Add('create'); $ghArgv.Add($Prompt)
    $ghArgv.Add('--repo'); $ghArgv.Add($Repository)
    if (-not [string]::IsNullOrWhiteSpace($BaseBranch)) { $ghArgv.Add('--base'); $ghArgv.Add($BaseBranch) }
    return $ghArgv.ToArray()
}

function Get-AgentTaskUrlFromOutput {
    <#
    .SYNOPSIS
        Pure — pull the agent-task URL out of `gh agent-task create` output.
    .DESCRIPTION
        The URL is the only durable handle on a cloud run; without it the run
        summary records "dispatched" and the operator has no way to find what
        was dispatched. Returns '' when the output carries none, so the caller
        records the absence rather than a fabricated link.
    #>
    param([AllowEmptyString()][string]$Output = '')

    if ([string]::IsNullOrWhiteSpace($Output)) { return '' }
    $match = [regex]::Match($Output, 'https://github\.com/\S+')
    if (-not $match.Success) { return '' }
    return $match.Value.TrimEnd('.', ',', ')', ']', '"', "'")
}

function Test-CopilotDispatchPrecondition {
    <#
    .SYNOPSIS
        Pure — can this session run `gh agent-task create`? Named reason if not.
    .DESCRIPTION
        Two things break cloud dispatch, and both are silent until the call
        fails: `gh` is absent, or the process carries GH_TOKEN/GITHUB_TOKEN.
        The second is the trap Release 3.0 exists to route around — gh IGNORES
        its stored OAuth credential whenever an environment token is set, so a
        PAT inherited from the portal's environment turns a working operator
        session into the same failure the service has.
    #>
    param(
        [bool]$GhAvailable,
        [AllowEmptyString()][string]$EnvToken = ''
    )

    if (-not $GhAvailable) {
        return [pscustomobject]@{
            ok     = $false
            reason = 'gh-not-found'
            message = "'gh' was not found on PATH. Cloud dispatch runs the GitHub CLI in your session; install it or set GH_CLI_PATH."
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($EnvToken)) {
        return [pscustomobject]@{
            ok     = $false
            reason = 'env-token-overrides-oauth'
            message = ('This session carries a GitHub token in the environment, and gh ignores its stored OAuth credential whenever one is set. ' +
                       'agent-task needs OAuth, so clear GH_TOKEN/GITHUB_TOKEN in this shell and re-run: $env:GH_TOKEN=$null; $env:GITHUB_TOKEN=$null')
        }
    }
    return [pscustomobject]@{ ok = $true; reason = ''; message = '' }
}

# ── Release 3.0: runner presence ─────────────────────────────────────────────

function New-RunnerHeartbeat {
    <#
    .SYNOPSIS
        Pure — the heartbeat record the portal reads to know a runner exists.
    .DESCRIPTION
        The portal enqueues work it cannot execute. Without this, queueing into
        an empty room looks identical to queueing into a running one, and the
        operator finds out only when nothing ever moves off `queued`.
    #>
    param(
        [Parameter(Mandatory)][string]$QueuePath,
        [int]$PollSeconds = 15,
        [int]$ClaimedCount = 0,
        [AllowEmptyString()][string]$Mode = 'interactive',
        [AllowEmptyString()][string]$BeatAt = ''
    )

    if ([string]::IsNullOrWhiteSpace($BeatAt)) { $BeatAt = (Get-Date).ToUniversalTime().ToString('o') }
    return [ordered]@{
        schemaVersion    = '1'
        hostname         = [string]$env:COMPUTERNAME
        # The account matters: a runner must be an interactive operator session,
        # never the LocalSystem the portal runs as.
        user             = [string]$env:USERNAME
        pid              = $PID
        mode             = $Mode
        pollSeconds      = $PollSeconds
        claimedCount     = $ClaimedCount
        queuePath        = $QueuePath
        lastHeartbeatAt  = $BeatAt
    }
}

function Get-RunnerHeartbeatPath {
    param([Parameter(Mandatory)][string]$WorkspaceRoot)
    return (Join-Path $WorkspaceRoot 'output\roadmap-task-runner.heartbeat.json')
}

function Write-RunnerHeartbeat {
    <# Best-effort: a heartbeat write must never take down a runner that is
       otherwise doing real work. #>
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][System.Collections.IDictionary]$Heartbeat)
    try {
        $dir = Split-Path -Parent $Path
        if ($dir -and -not (Test-Path -LiteralPath $dir)) { $null = New-Item -ItemType Directory -Path $dir -Force }
        ([pscustomobject]$Heartbeat | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $Path -Encoding UTF8
    }
    catch { Write-Verbose ("heartbeat write failed: {0}" -f $_.Exception.Message) }
}

function Update-TaskSummary {
    param([Parameter(Mandatory)][string]$SummaryPath, [Parameter(Mandatory)][hashtable]$Set)
    $obj = @{}
    if (Test-Path -LiteralPath $SummaryPath) {
        try { $obj = Get-Content -LiteralPath $SummaryPath -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable } catch { $obj = @{} }
    }
    foreach ($k in $Set.Keys) { $obj[$k] = $Set[$k] }
    ($obj | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $SummaryPath -Encoding UTF8
}

if ($LoadFunctionsOnly) { return }

# ── Execution ─────────────────────────────────────────────────────────────────
function Invoke-QueuedCopilotTask {
    <#
    .SYNOPSIS
        Run one queued cloud-dispatch entry as `gh agent-task create`.
    .DESCRIPTION
        Release 3.0. The portal used to invoke Start-GitHubCopilotTask.ps1
        in-process, which could never work: `gh agent-task` requires an OAuth
        credential, and the LocalSystem service has neither a stored one nor an
        interactive login to obtain one. The portal now enqueues and this runs
        in the operator's session, where the credential already exists.

        Unlike the Claude path this creates no branch and commits nothing — the
        cloud agent owns the working copy. What comes back is a task URL, and
        recording it is the whole point: without it "dispatched" is a claim with
        nothing behind it.
    #>
    param(
        [Parameter(Mandatory)][object]$Entry,
        [Parameter(Mandatory)][string]$RunId,
        [Parameter(Mandatory)][string]$SummaryPath
    )

    $repository = [string]$Entry.repository
    $prompt = [string]$Entry.prompt
    $baseBranch = if ($Entry.PSObject.Properties.Name -contains 'baseBranch' -and $Entry.baseBranch) { [string]$Entry.baseBranch } else { '' }

    $ghCommand = Get-Command gh -ErrorAction SilentlyContinue
    $envToken = if (-not [string]::IsNullOrWhiteSpace($env:GH_TOKEN)) { $env:GH_TOKEN } else { [string]$env:GITHUB_TOKEN }
    $precondition = Test-CopilotDispatchPrecondition -GhAvailable ([bool]$ghCommand) -EnvToken $envToken

    if ($DryRun) {
        $preview = if ($precondition.ok) { 'ok' } else { "BLOCKED ($($precondition.reason)): $($precondition.message)" }
        Write-Host ("  [DRYRUN] would: claim -> gh agent-task create --repo {0}{1} -> record task URL" -f `
                $repository, $(if ($baseBranch) { " --base $baseBranch" } else { '' })) -ForegroundColor Yellow
        Write-Host ("  [DRYRUN] precondition: {0}" -f $preview) -ForegroundColor Yellow
        return
    }

    if (-not $precondition.ok) {
        # Refuse without claiming: the task stays queued so it can run once the
        # session is fixed, instead of being burned on a session that cannot.
        Write-Host ("  [blocked] {0}" -f $precondition.message) -ForegroundColor Red
        Update-TaskSummary -SummaryPath $SummaryPath -Set @{
            status         = 'blocked'
            dispatchTarget = 'copilot'
            error          = [string]$precondition.message
            blockedCode    = [string]$precondition.reason
            runnerBlockedAt = (Get-Date).ToString('o')
        }
        return
    }

    Update-TaskSummary -SummaryPath $SummaryPath -Set @{ status = 'running'; dispatchTarget = 'copilot'; runnerStartedAt = (Get-Date).ToString('o') }
    try {
        $ghArgs = New-CopilotAgentTaskArgs -Repository $repository -Prompt $prompt -BaseBranch $baseBranch
        $output = ((& $ghCommand.Source @ghArgs 2>&1) | Out-String).Trim()
        if ($LASTEXITCODE -ne 0) { throw ("gh agent-task create failed with exit code {0}: {1}" -f $LASTEXITCODE, $output) }

        $taskUrl = Get-AgentTaskUrlFromOutput -Output $output
        Update-TaskSummary -SummaryPath $SummaryPath -Set @{
            status            = 'dispatched'
            dispatchTarget    = 'copilot'
            repository        = $repository
            baseBranch        = $baseBranch
            agentTaskUrl      = $taskUrl
            runnerCompletedAt = (Get-Date).ToString('o')
        }
        Write-Host ("  [dispatched] repo={0} url={1}" -f $repository, $(if ($taskUrl) { $taskUrl } else { '(none reported)' })) -ForegroundColor Green
        if (-not $taskUrl) {
            Write-Host "  gh reported no task URL; check 'gh agent-task list' for the run." -ForegroundColor DarkYellow
        }
    }
    catch {
        Update-TaskSummary -SummaryPath $SummaryPath -Set @{ status = 'failed'; dispatchTarget = 'copilot'; error = $_.Exception.Message; runnerCompletedAt = (Get-Date).ToString('o') }
        Write-Host ("  [failed] {0}" -f $_.Exception.Message) -ForegroundColor Red
    }
}

function Invoke-QueuedTask {
    param([object]$Entry)
    $runId = [string]$Entry.runId
    $repo = [string]$Entry.localRepoPath
    $branch = if ($Entry.PSObject.Properties.Name -contains 'branch' -and $Entry.branch) { [string]$Entry.branch } else { "roadmap/$runId" }
    $prompt = [string]$Entry.prompt
    $summaryPath = Join-Path $runsDir ("{0}.summary.json" -f $runId)

    # Refuse an unrecognized target before claiming it — a claimed task that
    # cannot run is worse than one left queued, because it looks handled.
    $dispatchTarget = 'claude'
    try { $dispatchTarget = Get-QueueEntryDispatchTarget -Entry $Entry }
    catch {
        Write-Host ("`n[task] runId={0} refused: {1}" -f $runId, $_.Exception.Message) -ForegroundColor Red
        if (-not $DryRun) {
            Update-TaskSummary -SummaryPath $summaryPath -Set @{ status = 'failed'; error = $_.Exception.Message; runnerCompletedAt = (Get-Date).ToString('o') }
        }
        return
    }

    Write-Host ("`n[task] runId={0} repo={1} target={2}" -f $runId, $repo, $dispatchTarget) -ForegroundColor Cyan

    if ($dispatchTarget -eq 'copilot') {
        Invoke-QueuedCopilotTask -Entry $Entry -RunId $runId -SummaryPath $summaryPath
        return
    }

    # Release 3.1 — verify the base BEFORE branching from it, and before the
    # dry-run shortcut, so a dry run reports the refusal it would hit. The
    # runner hands the repo to an agent that reads its files and proposes
    # changes; on a stale clone that proposal is computed against out-of-date
    # content and still merges cleanly. Refusing before the claim leaves the
    # task queued and visible rather than marked running against an unchecked
    # base.
    # Release 3.4 step 2 — bring the default branch to the remote tip BEFORE the
    # freshness gate reads it, so an operator who asked for a sync is not
    # refused for a staleness the sync would have fixed. Opt-in, approved by
    # the presence of the switch: approval is an input here, not a prompt.
    if ($script:SyncMain -and (Get-Command -Name 'Sync-RepoDefaultBranch' -ErrorAction SilentlyContinue)) {
        $sync = Sync-RepoDefaultBranch -RepoPath $repo -Approved $true
        if ($sync.synced) {
            Write-Host ("  [task] {0}" -f $sync.reason) -ForegroundColor DarkGray
        }
        else {
            # Not fatal: the staleness gate below decides whether the run may
            # proceed. A failed sync that still leaves a current clone is not a
            # reason to refuse work.
            Write-Host ("  [task] sync refused ({0}): {1}" -f $sync.category, $sync.reason) -ForegroundColor DarkYellow
            if ($sync.remedy) { Write-Host ("         {0}" -f $sync.remedy) -ForegroundColor DarkGray }
        }
    }

    $freshness = Test-RunnerBaseFreshness -RepoPath $repo
    if ($null -ne $freshness -and $freshness.isStale -and -not $script:AcknowledgeStaleBase) {
        $msg = ("Refusing to branch from a stale base. {0}{1}" -f $freshness.summary, $(if ($freshness.remedy) { " Run: $($freshness.remedy)" } else { '' }))
        Write-Host ("  [task] runId={0} refused (stale-base): {1}" -f $runId, $msg) -ForegroundColor Red
        Write-Host "         Re-run with -AcknowledgeStaleBase to proceed anyway." -ForegroundColor DarkGray
        if (-not $DryRun) {
            Update-TaskSummary -SummaryPath $summaryPath -Set @{
                status = 'refused'; refusalCategory = 'stale-base'; error = $msg
                baseFreshnessState = [string]$freshness.state
                runnerCompletedAt = (Get-Date).ToString('o')
            }
        }
        return
    }
    if ($null -ne $freshness -and $freshness.state -eq 'unknown') {
        # Not a refusal — absence of evidence is not evidence of divergence —
        # but it is said out loud rather than passed over in silence.
        Write-Host ("  [task] base freshness unverified: {0}" -f $freshness.summary) -ForegroundColor DarkYellow
    }

    if ($DryRun) {
        Write-Host "  [DRYRUN] would: claim -> git switch -c $branch -> launch claude -> verify -> commit -> awaiting-review" -ForegroundColor Yellow
        Write-Host ("  [DRYRUN] claude {0} (cwd={1})" -f $(if ($Headless) { "-p <prompt> --permission-mode $PermissionMode" } else { "--permission-mode $PermissionMode <prompt>" }), $repo) -ForegroundColor Yellow
        return
    }

    Update-TaskSummary -SummaryPath $summaryPath -Set @{ status = 'running'; runnerStartedAt = (Get-Date).ToString('o') }
    try {
        if (-not (Test-Path -LiteralPath (Join-Path $repo '.git'))) { throw "Not a git repo: $repo" }

        # Working branch (create, or switch if it already exists).
        & git -C $repo switch -c $branch 2>$null
        if ($LASTEXITCODE -ne 0) {
            & git -C $repo switch $branch 2>$null
            if ($LASTEXITCODE -ne 0) { throw "Failed to switch to branch '$branch' in repo '$repo'." }
        }

        # Launch Claude Code in the repo.
        if (-not (Get-Command claude -ErrorAction SilentlyContinue)) { throw "'claude' not found on PATH. Run this as the operator with Claude Code installed." }
        Push-Location $repo
        try {
            if ($Headless) { & claude -p $prompt --permission-mode $PermissionMode }
            else { & claude --permission-mode $PermissionMode $prompt }
            if ($LASTEXITCODE -ne 0) { throw "Claude Code execution failed with exit code $LASTEXITCODE." }
        }
        finally { Pop-Location }

        # Best-effort verify.
        $verifyResult = 'skipped'
        $verifyCmd = Resolve-VerifyCommand -RepoPath $repo
        if ($verifyCmd) {
            Write-Host ("  verify: {0}" -f $verifyCmd) -ForegroundColor DarkGray
            Push-Location $repo
            try { Invoke-Expression $verifyCmd | Out-Null; $verifyResult = if ($LASTEXITCODE -eq 0) { 'passed' } else { 'failed' } }
            catch { $verifyResult = 'error' }
            finally { Pop-Location }
        }

        # Commit any changes on the branch (operator may have already committed inside the session).
        $dirty = @(& git -C $repo status --porcelain)
        $filesChanged = $dirty.Count
        if ($filesChanged -gt 0) {
            & git -C $repo add -A
            & git -C $repo commit -m (New-TaskCommitMessage -SelectedTask ([string]$Entry.selectedTask) -RunId $runId) | Out-Null
        }
        $commitSha = (& git -C $repo rev-parse --short HEAD 2>$null)

        Update-TaskSummary -SummaryPath $summaryPath -Set @{
            status          = 'awaiting-review'
            branch          = $branch
            commitSha       = "$commitSha"
            filesChanged    = $filesChanged
            verifyResult    = $verifyResult
            runnerCompletedAt = (Get-Date).ToString('o')
        }
        Write-Host ("  [awaiting-review] branch={0} commit={1} files={2} verify={3}" -f $branch, $commitSha, $filesChanged, $verifyResult) -ForegroundColor Green
        Write-Host "  Review the branch, then push / open a PR yourself." -ForegroundColor DarkGray
    }
    catch {
        Update-TaskSummary -SummaryPath $summaryPath -Set @{ status = 'failed'; error = $_.Exception.Message; runnerCompletedAt = (Get-Date).ToString('o') }
        Write-Host ("  [failed] {0}" -f $_.Exception.Message) -ForegroundColor Red
    }
}

$runnerMode = if ($Headless) { 'headless' } else { 'interactive' }
$heartbeatPath = Get-RunnerHeartbeatPath -WorkspaceRoot $WorkspaceRoot

Write-Host ("Roadmap task runner — queue: {0}" -f $QueuePath) -ForegroundColor White
Write-Host ("  mode: {0}{1}  permission: {2}" -f $runnerMode, $(if ($DryRun) { ' (dry-run)' } else { '' }), $PermissionMode) -ForegroundColor DarkGray
Write-Host ("  heartbeat: {0}" -f $heartbeatPath) -ForegroundColor DarkGray

do {
    $claimable = @(Get-QueueEntries -QueuePath $QueuePath | Where-Object {
            (Get-TaskSummaryStatus -SummaryPath (Join-Path $runsDir ("{0}.summary.json" -f $_.runId))) -eq 'queued'
        })

    # Beat every cycle, including the idle ones. A runner that only announced
    # itself while working would look absent exactly when the portal most needs
    # to know it is there — before queueing anything.
    Write-RunnerHeartbeat -Path $heartbeatPath -Heartbeat (New-RunnerHeartbeat `
            -QueuePath $QueuePath -PollSeconds $PollSeconds -ClaimedCount $claimable.Count -Mode $runnerMode)

    if ($claimable.Count -eq 0) {
        if ($Once) { Write-Host 'No queued tasks.' -ForegroundColor DarkGray; break }
        Start-Sleep -Seconds $PollSeconds
        continue
    }
    foreach ($entry in $claimable) { Invoke-QueuedTask -Entry $entry }
    if ($Once) { break }
    Start-Sleep -Seconds $PollSeconds
} while ($true)
