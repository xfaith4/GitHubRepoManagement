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

.PARAMETER StopFilePath
    Release 2.9 — a way to stop a detached runner without hunting for its PID.
    A headless runner is launched detached so a tool timeout cannot strand a
    claim mid-run, which means it OUTLIVES the session that started it: one
    survived 17 hours on 2026-08-19, raced the api-host smoke twice, and
    committed in-flight work onto local `main` before the repo-root guard
    existed. Killing it needed `Stop-Process`, which an agent may not be
    permitted to call and an operator has to look up a PID for.

    Same shape as the api-host's `-ShutdownSignalPath`: create this file and
    the loop exits at its next poll boundary — between tasks, never mid-task,
    because abandoning a running `claude` session would leave a claimed item
    with no owner. Defaults to `output/roadmap-task-runner.stop`, is cleared
    at startup so a stale marker cannot kill a fresh runner, and is consumed
    when honored. `scripts/Stop-RoadmapTaskRunner.ps1` is the friendly front
    door.

.PARAMETER ClearInheritedGitHubToken
    Clear GH_TOKEN / GITHUB_TOKEN from this process before polling.

    For the SCHEDULED TASK, which inherits the machine environment. On a box
    where GITHUB_TOKEN is set at Machine scope, every copilot task the task
    runner claimed would be refused by its own dispatch precondition -- `gh`
    ignores its stored OAuth credential whenever an environment token is
    present, and `gh agent-task` needs OAuth. The task would sit there looking
    perfectly healthy in Task Scheduler and dispatch nothing, forever.

    Deliberately opt-IN and never the default: run interactively and the
    precondition still stops you with an explanation, which is the right
    behaviour for a human who can act on it. Only the unattended path, which
    has no one to tell, clears it -- and says so in its startup banner.

    Claude-target tasks are unaffected: git inside them authenticates through
    the credential helper, not this variable.

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
    [string]$StopFilePath,
    [switch]$ClearInheritedGitHubToken,
    [switch]$LoadFunctionsOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Unattended runs clear the inherited token before anything reads it, so the
# dispatch precondition sees the session it would have had if a human had run
# `$env:GITHUB_TOKEN=$null` first. Announced, never silent.
if ($ClearInheritedGitHubToken) {
    $clearedTokenNames = @('GH_TOKEN', 'GITHUB_TOKEN') |
        Where-Object { -not [string]::IsNullOrWhiteSpace([System.Environment]::GetEnvironmentVariable($_)) }
    foreach ($clearedTokenName in $clearedTokenNames) {
        [System.Environment]::SetEnvironmentVariable($clearedTokenName, $null, 'Process')
    }
    if (@($clearedTokenNames).Count -gt 0) {
        Write-Host ("  cleared inherited {0} for this process so gh uses its stored OAuth credential" -f ($clearedTokenNames -join ', ')) -ForegroundColor DarkYellow
    }
}

if ([string]::IsNullOrWhiteSpace($WorkspaceRoot)) { $WorkspaceRoot = Split-Path -Parent $PSScriptRoot }

# One resolver decides the queue path, here as everywhere else. Building it
# inline made the RUNNER the one process that ignored REPO_MGMT_QUEUE_PATH --
# so a smoke run could redirect every writer and still have the operator's
# real runner draining the operator's real queue underneath it. That is the
# same shape as the 2026-08-19 incident the resolver was introduced to end,
# only from the reading side instead of the writing side.
# Resolved from $PSScriptRoot, not $WorkspaceRoot: the runner is pointed at
# fixture workspaces that carry no backend/ tree, and dot-sourcing off
# $WorkspaceRoot made it exit at startup against every one of them.
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'backend\modules\automation\Automation.RoadmapQueue.ps1')
# Release 3.8 M1 (H38-03) - the execution contract. Resolved from $PSScriptRoot
# for the same reason as the queue module directly above: the runner is pointed
# at fixture workspaces that carry no backend/ tree of their own.
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'backend\modules\execution\Execution.WorkPacket.ps1')
# Release 3.8 M2 (H38-10) - the registry supplies the configured limitSignals
# and the capacity module records the cooldown a matched signal implies.
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'backend\modules\execution\Execution.ProviderRegistry.ps1')
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'backend\modules\execution\Execution.ProviderCapacity.ps1')
# H38-17: `auto` is resolved to a real provider here, at claim time.
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'backend\modules\execution\Execution.ProviderRouter.ps1')
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'backend\modules\agent-adapters\Adapter.Claude.ps1')
# H38-15: the copilot dispatch functions moved here from this file. Dot-sourced
# BEFORE any use, so every existing call site is unchanged by the move.
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'backend\modules\agent-adapters\Adapter.Copilot.ps1')
# H38-16: the codex branch below runs through this.
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'backend\modules\agent-adapters\Adapter.Codex.ps1')
if ([string]::IsNullOrWhiteSpace($QueuePath)) { $QueuePath = Get-RoadmapQueuePath -WorkspaceRoot $WorkspaceRoot }
if ([string]::IsNullOrWhiteSpace($StopFilePath)) { $StopFilePath = Join-Path $WorkspaceRoot 'output\roadmap-task-runner.stop' }
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

# Release 3.4 milestone 4 — completion travels through the pull request. The
# completion-edit builder and the feature-branch commit live in the write-back
# module so the runner and the apply route share one definition of "complete".
$script:WriteBackModule = Join-Path $WorkspaceRoot 'backend\modules\roadmap\Roadmap.WriteBack.ps1'
if (Test-Path -LiteralPath $script:WriteBackModule) { . $script:WriteBackModule }

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
    <# Best-effort detection of a per-repo check. Returns an executable plus
       argument list (invoked with the call operator — never string-evaluated)
       or $null. Non-blocking — a failing verify is recorded, not fatal. #>
    param([Parameter(Mandatory)][string]$RepoPath)
    $pkg = Join-Path $RepoPath 'package.json'
    if (Test-Path -LiteralPath $pkg) {
        try {
            $j = Get-Content -LiteralPath $pkg -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($j.PSObject.Properties.Name -contains 'scripts' -and $j.scripts.PSObject.Properties.Name -contains 'test') {
                return [pscustomobject]@{ Display = 'npm test'; Exe = 'npm'; Arguments = @('test') }
            }
        }
        catch { }
    }
    if (Test-Path -LiteralPath (Join-Path $RepoPath 'scripts\Invoke-TestSuite.ps1')) {
        return [pscustomobject]@{ Display = 'pwsh -NoProfile -File scripts/Invoke-TestSuite.ps1'; Exe = 'pwsh'; Arguments = @('-NoProfile', '-File', 'scripts/Invoke-TestSuite.ps1') }
    }
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
    # H38-14: one vocabulary. This used to repeat the queue module's list and
    # message, so adding a provider meant finding four copies and missing one.
    return (Resolve-RoadmapDispatchTarget -DispatchTarget $raw)
}

# New-CopilotAgentTaskArgs, Get-AgentTaskUrlFromOutput and
# Test-CopilotDispatchPrecondition MOVED to
# backend\modulesgent-adapters\Adapter.Copilot.ps1 in H38-15, verbatim.
# The adapter is dot-sourced above, so every call site here is unchanged; the
# module smoke asserts their output is identical to the pre-move behaviour.

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
        [AllowEmptyString()][string]$BeatAt = '',
        [AllowEmptyString()][string]$StopFilePath = '',
        [object]$ProviderCooldowns = $null,
        [nullable[int]]$LocalSlotsInUse = $null
    )

    if ([string]::IsNullOrWhiteSpace($BeatAt)) { $BeatAt = (Get-Date).ToUniversalTime().ToString('o') }
    $beat = [ordered]@{
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
        # How to stop this runner, carried WITH the evidence that it exists.
        # Whoever finds the heartbeat is exactly whoever needs to stop it.
        stopFilePath     = $StopFilePath
    }
    # Release 3.8 M2 (H38-11). Added ONLY when supplied, so a heartbeat written
    # without them is byte-identical to what every earlier reader expects --
    # the portal, the presence module and the api-host smoke all parse this.
    if ($null -ne $ProviderCooldowns) { $beat['providerCooldowns'] = $ProviderCooldowns }
    if ($null -ne $LocalSlotsInUse) { $beat['localSlotsInUse'] = [int]$LocalSlotsInUse }
    return $beat
}

function Get-RunnerHeartbeatPath {
    param([Parameter(Mandatory)][string]$WorkspaceRoot)
    return (Join-Path $WorkspaceRoot 'output\roadmap-task-runner.heartbeat.json')
}

function Get-RunnerStopFilePath {
    param([Parameter(Mandatory)][string]$WorkspaceRoot)
    return (Join-Path $WorkspaceRoot 'output\roadmap-task-runner.stop')
}

function Test-RunnerStopRequested {
    <#
    .SYNOPSIS
        Has an operator asked this runner to stop?
    .DESCRIPTION
        Checked at poll boundaries and between claims -- never mid-task. A
        stop that abandoned a running `claude` session would leave a claimed
        item with no owner and a half-written branch, which is the state this
        whole subsystem exists to avoid. Stopping between units of work costs
        at most one task's remaining time and leaves the queue coherent.
    #>
    param([Parameter(Mandatory)][string]$StopFilePath)
    if ([string]::IsNullOrWhiteSpace($StopFilePath)) { return $false }
    return (Test-Path -LiteralPath $StopFilePath)
}

function Clear-RunnerStopFile {
    <#
    .SYNOPSIS
        Consume the stop marker so it cannot kill the NEXT runner.
    .DESCRIPTION
        A marker left behind would stop a freshly started runner at its first
        poll, which reads as "the runner will not start" and sends the
        operator hunting for a fault that is a leftover file. Cleared both at
        startup and on honored stop.
    #>
    param([Parameter(Mandatory)][string]$StopFilePath)
    if ([string]::IsNullOrWhiteSpace($StopFilePath)) { return }
    if (-not (Test-Path -LiteralPath $StopFilePath)) { return }
    try { Remove-Item -LiteralPath $StopFilePath -Force -ErrorAction Stop }
    catch { Write-Warning ("Could not consume the runner stop file '{0}': {1}. Remove it by hand or the next runner will stop at its first poll." -f $StopFilePath, $_.Exception.Message) }
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

function Resolve-RunnerPrompt {
    <#
    .SYNOPSIS
        Pure - choose the prompt a run is given, and say where it came from.

    .DESCRIPTION
        Release 3.8 M1. From H38-02 the WorkPacket is the source of truth for
        what a task is, so the prompt should be DERIVED from it rather than
        carried alongside it and allowed to drift. But entries queued before
        3.8 carry no packet at all, and a runner that refused them would strip
        the queue of work it can still do perfectly well.

        So the packet wins when there is one and the prose stands in when there
        is not. The source is returned rather than inferred, because "which
        text did this run actually receive" is the first question when a result
        looks wrong, and reconstructing it afterwards is guesswork.
    .OUTPUTS
        [pscustomobject] prompt, source ('work-packet' | 'queue-entry')
    #>
    param(
        [Parameter()][object]$Entry = $null,
        [Parameter()][object]$Packet = $null
    )

    if ($null -ne $Packet -and (Get-Command -Name 'ConvertTo-ClaudePrompt' -ErrorAction SilentlyContinue)) {
        $rendered = ConvertTo-ClaudePrompt -Packet $Packet
        if (-not [string]::IsNullOrWhiteSpace($rendered)) {
            return [pscustomobject]@{ prompt = $rendered; source = 'work-packet' }
        }
    }

    $entryPrompt = ''
    if ($null -ne $Entry) {
        if ($Entry -is [System.Collections.IDictionary]) {
            if ($Entry.Contains('prompt')) { $entryPrompt = [string]$Entry['prompt'] }
        }
        elseif ($null -ne $Entry.PSObject -and ($Entry.PSObject.Properties.Name -contains 'prompt')) {
            $entryPrompt = [string]$Entry.prompt
        }
    }
    return [pscustomobject]@{ prompt = $entryPrompt; source = 'queue-entry' }
}

function Resolve-RunOutcomeFromResult {
    <#
    .SYNOPSIS
        Pure - decide a run's outcome from the agent's structured result.

    .DESCRIPTION
        Release 3.8 M1. Until this existed the runner read $LASTEXITCODE and
        nothing else, so an agent that printed an apology and exited 0 reached
        `awaiting-review` with no work behind it. The spec's rule is that
        free-form prose must not be the orchestration protocol, and the way to
        mean it is to make the ABSENCE of a structured result a named failure
        rather than a silent pass.

        ExitCode is recorded and decides nothing. That is deliberate, and it is
        not the same as ignoring a crash: a non-zero exit still throws earlier,
        at the launch site, before this is ever called. What this pins down is
        that once a result EXISTS, the result is the protocol -- an adapter
        reporting implementation_complete is believed even if the CLI's exit
        code disagrees, because the adapter knows what happened and the exit
        code only knows that a process ended.

        capacity_exhausted maps to `queued`, not `failed`. A provider limit
        means the work was never attempted; failing the task would blame the
        roadmap item for the subscription's state. H38-10 completes that path
        by preserving the branch, attempt and session; this only maps it.
    .OUTPUTS
        [pscustomobject] status, error, exitCode
    #>
    param(
        [Parameter()][object]$Result = $null,
        [Parameter()][int]$ExitCode = 0
    )

    $status = 'failed'
    $errorText = ''

    if ($null -eq $Result) {
        $errorText = 'no-structured-result: the agent produced no ExecutionResult; prose is not the protocol'
    }
    else {
        $validation = $null
        if (Get-Command -Name 'Test-ExecutionResult' -ErrorAction SilentlyContinue) {
            $validation = Test-ExecutionResult -Result $Result
        }
        if ($null -ne $validation -and -not $validation.valid) {
            $errorText = ('invalid-structured-result: {0}' -f ($validation.errors -join '; '))
        }
        else {
            $resultStatus = ''
            if ($Result -is [System.Collections.IDictionary]) {
                if ($Result.Contains('status')) { $resultStatus = [string]$Result['status'] }
            }
            elseif ($null -ne $Result.PSObject -and ($Result.PSObject.Properties.Name -contains 'status')) {
                $resultStatus = [string]$Result.status
            }

            $resultSummary = ''
            if ($Result -is [System.Collections.IDictionary]) {
                if ($Result.Contains('summary')) { $resultSummary = [string]$Result['summary'] }
            }
            elseif ($null -ne $Result.PSObject -and ($Result.PSObject.Properties.Name -contains 'summary')) {
                $resultSummary = [string]$Result.summary
            }

            switch ($resultStatus) {
                'capacity_exhausted' { $status = 'queued'; $errorText = '' }
                'implementation_failed' { $status = 'failed'; $errorText = $resultSummary }
                'cancelled' { $status = 'failed'; $errorText = 'cancelled' }
                'implementation_complete' { $status = 'awaiting-review'; $errorText = '' }
                default { $errorText = ('invalid-structured-result: status must be one of: implementation_complete, implementation_failed, capacity_exhausted, cancelled') }
            }
        }
    }

    return [pscustomobject]@{
        status   = $status
        error    = $errorText
        exitCode = [int]$ExitCode
    }
}

function Resolve-ClaimToken {
    <#
    .SYNOPSIS
        Pure - the provider token a claim decision is about, including `auto`.

    .DESCRIPTION
        Release 3.8 M2 (H38-11). Deliberately NOT Get-QueueEntryDispatchTarget,
        which throws on `auto`: that function decides which tool to RUN, and
        `auto` names no tool, so refusing it there is correct and stays correct.
        H38-14 widens that resolver to the full token list; until then the claim
        gate needs to recognise `auto` without borrowing the run-time contract.

        An unrecognised target is reported, never defaulted. Treating `gpt` as
        claude would run the wrong tool against a real repository, which is the
        exact failure Get-QueueEntryDispatchTarget exists to prevent.
    .OUTPUTS
        [pscustomobject] token, known, error
    #>
    param([Parameter(Mandatory)][object]$Entry)

    $raw = ''
    if ($null -ne $Entry.PSObject -and ($Entry.PSObject.Properties.Name -contains 'dispatchTarget') -and $Entry.dispatchTarget) {
        $raw = [string]$Entry.dispatchTarget
    }
    if ([string]::IsNullOrWhiteSpace($raw)) { return [pscustomobject]@{ token = 'claude'; known = $true; error = '' } }

    $normalized = $raw.Trim().ToLowerInvariant()
    if ($normalized -eq 'auto') { return [pscustomobject]@{ token = 'auto'; known = $true; error = '' } }

    try { return [pscustomobject]@{ token = (Get-QueueEntryDispatchTarget -Entry $Entry); known = $true; error = '' } }
    catch { return [pscustomobject]@{ token = $normalized; known = $false; error = $_.Exception.Message } }
}

function Test-RunnerClaimAllowed {
    <#
    .SYNOPSIS
        Pure - may this runner claim this entry right now?

    .DESCRIPTION
        Release 3.8 M2 (H38-11). Refusing to CLAIM is different from failing a
        task: the entry is left `queued` and untouched, so the next poll after a
        cooldown expires picks it up with nothing lost. The runner writes no
        summary at all on a refusal, which is what keeps this reversible.

        Every refusal names itself with a `code`, because a runner that quietly
        stops picking work up is indistinguishable from one that has died.

        An unenforced capacity verdict is ADVISORY: it is reported in the reason
        and the claim proceeds. While the per-task cost estimate is still a
        guess (D-011), refusing on it would block real work on an unmeasured
        number -- so it is visible without being binding.
    .OUTPUTS
        [pscustomobject] allowed, reason, code
    #>
    param(
        [Parameter(Mandatory)][object]$Entry,
        [Parameter()][AllowNull()][object]$CapacityRecord = $null,
        [Parameter()][AllowNull()][object]$Config = $null,
        [int]$ActiveLocalCount = 0,
        [datetime]$NowUtc = [datetime]::UtcNow
    )

    $resolved = Resolve-ClaimToken -Entry $Entry
    $token = [string]$resolved.token

    # An entry naming a tool this runner does not know is refused, not guessed
    # at. Leaving it queued is safe; running the wrong tool against a real
    # repository is not.
    if (-not $resolved.known) {
        return [pscustomobject]@{
            allowed = $false
            code    = 'unknown-dispatch-target'
            reason  = $resolved.error
        }
    }

    # `auto` has no provider yet, so there is nothing here to check. The router
    # (H38-17) evaluates cooldown, reserve and concurrency per candidate, at
    # claim time, in the session that can actually see authentication.
    if ($token -eq 'auto') {
        return [pscustomobject]@{
            allowed = $true
            code    = 'deferred-to-router'
            reason  = 'auto: cooldown, reserve and concurrency are checked per candidate by Resolve-ProviderSelection'
        }
    }

    $providerConfig = $null
    if ($null -ne $Config) {
        $providers = $null
        if ($Config -is [System.Collections.IDictionary]) {
            if ($Config.Contains('providers')) { $providers = $Config['providers'] }
        }
        elseif ($null -ne $Config.PSObject -and ($Config.PSObject.Properties.Name -contains 'providers')) {
            $providers = $Config.providers
        }
        if ($null -ne $providers -and $null -ne $providers.PSObject -and (@($providers.PSObject.Properties | ForEach-Object { $_.Name }) -contains $token)) {
            $providerConfig = $providers.$token
        }
    }

    # Cooldown first: it is the most specific answer and carries a time, so the
    # operator learns not just that nothing is moving but when it will.
    # Both shapes, deliberately: a record built in memory is an ordered
    # dictionary and one read from disk is a PSCustomObject, and reading only
    # one of them would silently skip the cooldown check for the other.
    $cooldownRaw = ''
    if ($CapacityRecord -is [System.Collections.IDictionary]) {
        if ($CapacityRecord.Contains('cooldownUntil')) { $cooldownRaw = [string]$CapacityRecord['cooldownUntil'] }
    }
    elseif ($null -ne $CapacityRecord -and $null -ne $CapacityRecord.PSObject -and ($CapacityRecord.PSObject.Properties.Name -contains 'cooldownUntil')) {
        $cooldownRaw = [string]$CapacityRecord.cooldownUntil
    }
    if (-not [string]::IsNullOrWhiteSpace($cooldownRaw)) {
        $cooldownAt = [datetime]::MinValue
        $parsed = [datetime]::TryParse(
            $cooldownRaw,
            [System.Globalization.CultureInfo]::InvariantCulture,
            [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal,
            [ref]$cooldownAt)
        if ($parsed -and $cooldownAt -gt $NowUtc) {
            return [pscustomobject]@{
                allowed = $false
                code    = 'provider-cooling-down'
                reason  = ('{0} is cooling down until {1}' -f $token, $cooldownRaw)
            }
        }
    }

    $executionMode = ''
    if ($null -ne $providerConfig -and $null -ne $providerConfig.PSObject -and ($providerConfig.PSObject.Properties.Name -contains 'executionMode')) {
        $executionMode = [string]$providerConfig.executionMode
    }

    # MVP concurrency is one local slot. A github-hosted run does not occupy it:
    # the work happens on GitHub's machines, not this one.
    if ($executionMode -eq 'local') {
        $slots = 1
        if ($null -ne $Config -and $null -ne $Config.PSObject -and ($Config.PSObject.Properties.Name -contains 'localExecutionSlots')) {
            $slots = [int]$Config.localExecutionSlots
        }
        if ($ActiveLocalCount -ge $slots) {
            return [pscustomobject]@{
                allowed = $false
                code    = 'local-slot-occupied'
                reason  = ('{0} local execution slot(s) in use; MVP concurrency is {1}' -f $ActiveLocalCount, $slots)
            }
        }
    }

    if ($null -ne $Config -and (Get-Command -Name 'Resolve-ProviderCapacityVerdict' -ErrorAction SilentlyContinue)) {
        $verdict = Resolve-ProviderCapacityVerdict -Record $CapacityRecord -Config $Config -NowUtc $NowUtc -Provider $token
        if (-not $verdict.eligible) {
            if ($verdict.enforced) {
                return [pscustomobject]@{
                    allowed = $false
                    code    = 'capacity-reserve'
                    reason  = ('{0}: {1}' -f $token, $verdict.reason)
                }
            }
            return [pscustomobject]@{
                allowed = $true
                code    = 'capacity-advisory'
                reason  = ('capacity verdict advisory: {0}' -f $verdict.reason)
            }
        }
    }

    return [pscustomobject]@{
        allowed = $true
        code    = 'allowed'
        reason  = ''
    }
}

<#
.SYNOPSIS
    H38-17 — gather the router's inputs from live runner state and choose a
    provider for one queued entry.

.DESCRIPTION
    The router itself is pure; this is the impure half that reads what is true
    right now: capacity records off disk, availability detected per installation
    (H38-15b), active execution counts derived from run summaries and the
    heartbeat, and recent run history.

    Availability comes from Get-AgentProviderAvailabilityMap and NOT from an
    inline Get-Command here. Duplicating the PATH probe is how availability came
    to be asserted in two places in the first place (A20), and a second copy
    would drift from the one Settings and the setup wizard show the operator.
#>
function Resolve-QueuedTaskProvider {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][object]$Entry,
        [Parameter(Mandatory)][AllowEmptyString()][string]$RunId
    )

    $empty = [pscustomobject]@{ selected = $null; reason = @('router unavailable'); candidates = @(); tie = $false }
    if (-not (Get-Command -Name 'Resolve-ProviderSelection' -ErrorAction SilentlyContinue)) { return $empty }

    $config = $null
    if (Get-Command -Name 'Get-AgentProviderConfig' -ErrorAction SilentlyContinue) {
        $config = Get-AgentProviderConfig -ConfigPath (Get-AgentProviderConfigPath -WorkspaceRoot $WorkspaceRoot)
    }
    if ($null -eq $config) {
        return [pscustomobject]@{ selected = $null; reason = @('no eligible provider', 'the provider config could not be loaded'); candidates = @(); tie = $false }
    }

    $registry = @(@(Get-AgentProviderToken -WorkspaceRoot $WorkspaceRoot) | Where-Object { $_ -ne 'auto' })

    $availability = @{}
    if (Get-Command -Name 'Get-AgentProviderAvailabilityMap' -ErrorAction SilentlyContinue) {
        $availability = Get-AgentProviderAvailabilityMap -WorkspaceRoot $WorkspaceRoot
    }

    $records = @{}
    $active = @{}
    foreach ($provider in $registry) {
        if (Get-Command -Name 'Read-ProviderCapacityRecord' -ErrorAction SilentlyContinue) {
            $records[$provider] = Read-ProviderCapacityRecord -WorkspaceRoot $WorkspaceRoot -Provider $provider
        }
        if (Get-Command -Name 'Get-ProviderActiveExecutionCount' -ErrorAction SilentlyContinue) {
            $active[$provider] = Get-ProviderActiveExecutionCount -RunsDir $runsDir -Provider $provider -HeartbeatPath $heartbeatPath
        }
    }

    # The last 50 run summaries, newest last, so the router's recent-failure
    # window reads the most recent attempts. Best effort: history is a ranking
    # input, and losing it must degrade the score rather than refuse the run.
    $history = @()
    try {
        if (Test-Path -LiteralPath $runsDir) {
            $summaryFiles = @(Get-ChildItem -LiteralPath $runsDir -Filter '*.json' -File -ErrorAction SilentlyContinue |
                    Sort-Object LastWriteTimeUtc | Select-Object -Last 50)
            foreach ($file in $summaryFiles) {
                try {
                    $summary = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
                    if ($null -eq $summary) { continue }
                    $history += [pscustomobject]@{
                        provider   = [string](_PRT_Field -Obj $summary -Name 'selectedProvider' -Default (_PRT_Field -Obj $summary -Name 'dispatchTarget' -Default ''))
                        repository = [string](_PRT_Field -Obj $summary -Name 'repoName' -Default '')
                        status     = [string](_PRT_Field -Obj $summary -Name 'status' -Default '')
                    }
                }
                catch { continue }
            }
        }
    }
    catch { $history = @() }

    $packet = [pscustomobject]@{
        taskId      = [string]$RunId
        repository  = [string](_PRT_Field -Obj $Entry -Name 'repoName' -Default '')
        execution   = [pscustomobject]@{
            preferredProvider = 'auto'
            previousProvider  = [string](_PRT_Field -Obj $Entry -Name 'previousProvider' -Default '')
        }
        permissions = [pscustomobject]@{
            githubWrite = [bool](_PRT_Field -Obj $Entry -Name 'githubWrite' -Default $false)
        }
    }

    return Resolve-ProviderSelection -Packet $packet -Registry $registry -CapacityRecords $records `
        -AuthStatus $availability -ActiveCounts $active -History @($history) -Config $config -NowUtc ([datetime]::UtcNow)
}

function Resolve-CapacityWaitUpdate {
    <#
    .SYNOPSIS
        Pure - the summary fields and cooldown target for a capacity wait.

    .DESCRIPTION
        Release 3.8 M2 (H38-10). A provider limit means the work was never
        attempted, so the task goes back to `queued` and everything needed to
        resume it must survive untouched: branch, attempt and the provider
        session id. This computes what to write; the caller writes it.

        Separated from the runner's IO so the rule can be asserted without
        launching an agent. That matters more than usual here, because the only
        way to produce a real usage limit is to exhaust a subscription -- which
        is exactly the cost this release exists to avoid spending.

        When the provider named no reset time, the wait is NowUtc + 60 minutes
        and `resetAssumed` is true (A17). The assumption is marked rather than
        hidden, so a board can show a guessed wait differently from a promised
        one and a later real reset time can replace it without ambiguity.
    .OUTPUTS
        [pscustomobject] set (hashtable of summary fields), cooldownUntil,
        resetAssumed
    #>
    param(
        [Parameter()][AllowEmptyString()][string]$Provider = 'claude',
        [Parameter()][AllowNull()][object]$LimitSignal = $null,
        [Parameter()][datetime]$NowUtc = [datetime]::UtcNow,
        [Parameter()][AllowEmptyString()][string]$Summary = ''
    )

    $resetAt = $null
    $pattern = $null
    if ($null -ne $LimitSignal) {
        if ($LimitSignal.PSObject.Properties.Name -contains 'resetAt') { $resetAt = $LimitSignal.resetAt }
        if ($LimitSignal.PSObject.Properties.Name -contains 'pattern') { $pattern = $LimitSignal.pattern }
    }

    $resetAssumed = $false
    $cooldownUntil = [string]$resetAt
    if ([string]::IsNullOrWhiteSpace($cooldownUntil)) {
        $cooldownUntil = $NowUtc.AddMinutes(60).ToString('yyyy-MM-ddTHH:mm:ssZ')
        $resetAssumed = $true
    }

    return [pscustomobject]@{
        set           = @{
            status            = 'queued'
            error             = ''
            capacityWait      = @{
                provider   = $Provider
                detectedAt = $NowUtc.ToString('yyyy-MM-ddTHH:mm:ssZ')
                resetAt    = $(if ([string]::IsNullOrWhiteSpace([string]$resetAt)) { $null } else { [string]$resetAt })
                pattern    = $pattern
                summary    = $Summary
            }
            runnerCompletedAt = (Get-Date).ToString('o')
        }
        cooldownUntil = $cooldownUntil
        resetAssumed  = $resetAssumed
    }
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

    Update-TaskSummary -SummaryPath $SummaryPath -Set @{ status = 'running'; dispatchTarget = 'copilot'; runnerStartedAt = (Get-Date).ToString('o'); runnerPid = $PID }
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
        # H38-15: a cloud dispatch now produces an ExecutionResult like every
        # other provider, so the result file is the one shape a reader handles
        # rather than "claude runs have one, copilot runs do not". The task URL
        # is the provider session id because it is the only durable handle a
        # dispatch produces today. Best-effort: failing to write the result must
        # not fail a dispatch that actually succeeded.
        try {
            if (Get-Command -Name 'Get-CopilotExecutionResult' -ErrorAction SilentlyContinue) {
                $copilotResult = Get-CopilotExecutionResult -TaskUrl $taskUrl -TaskId $RunId -ExecutionId $RunId
                $null = Save-ExecutionResult -WorkspaceRoot $WorkspaceRoot -Result $copilotResult
            }
        }
        catch { Write-Host ("  [warn] could not record the dispatch result: {0}" -f $_.Exception.Message) -ForegroundColor DarkYellow }

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
    $summaryPath = Join-Path $runsDir ("{0}.summary.json" -f $runId)

    # Release 3.8 M1 (H38-05) - the packet is the source of truth for what this
    # task is, so the prompt is rendered from it. Pre-3.8 entries carry no
    # packet and keep their prose; the chosen source is logged because "which
    # text did this run actually receive" is the first question when a result
    # looks wrong.
    $entryWorkPacketPath = ''
    if ($Entry.PSObject.Properties.Name -contains 'workPacketPath' -and $Entry.workPacketPath) {
        $entryWorkPacketPath = [string]$Entry.workPacketPath
    }
    $runWorkPacket = $null
    if (-not [string]::IsNullOrWhiteSpace($entryWorkPacketPath) -and (Test-Path -LiteralPath $entryWorkPacketPath -PathType Leaf)) {
        try { $runWorkPacket = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $entryWorkPacketPath -Raw -Encoding UTF8) }
        catch { $runWorkPacket = $null }
    }
    $promptChoice = Resolve-RunnerPrompt -Entry $Entry -Packet $runWorkPacket
    $prompt = [string]$promptChoice.prompt
    Write-Host ("  prompt source: {0}" -f $promptChoice.source) -ForegroundColor DarkGray

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

    # H38-17 -- resolve `auto` BEFORE any provider branch, at claim time.
    #
    # At claim time and not at enqueue time on purpose: capacity, cooldowns
    # and concurrency are all state that moves between the two, and a
    # provider chosen when the task was queued can be exhausted by the time
    # it runs. Choosing here means the decision is made against what is true
    # now, and the reason recorded alongside it is the reason that applied.
    if ($dispatchTarget -eq 'auto') {
        $routing = Resolve-QueuedTaskProvider -Entry $Entry -RunId $runId
        if ([string]::IsNullOrWhiteSpace($routing.selected)) {
            # No provider can take it. The entry stays QUEUED rather than
            # failing: nothing is wrong with the task, and marking it failed
            # would burn an attempt on the estate's condition.
            Write-Host '  [routing] no eligible provider; leaving the task queued' -ForegroundColor DarkYellow
            foreach ($routingLine in @($routing.reason)) { Write-Host ("             {0}" -f $routingLine) -ForegroundColor DarkGray }
            if (-not $DryRun) {
                Update-TaskSummary -SummaryPath $summaryPath -Set @{
                    status          = 'queued'
                    selectedProvider = $null
                    selectionReason = @($routing.reason)
                    capacityWaitReason = 'no eligible provider'
                }
            }
            return
        }
        $dispatchTarget = [string]$routing.selected
        Write-Host ("  [routing] auto -> {0}" -f $dispatchTarget) -ForegroundColor Cyan
        foreach ($routingLine in @($routing.reason)) { Write-Host ("             {0}" -f $routingLine) -ForegroundColor DarkGray }
        if (-not $DryRun) {
            Update-TaskSummary -SummaryPath $summaryPath -Set @{
                selectedProvider = $dispatchTarget
                selectionReason  = @($routing.reason)
            }
        }
    }

    if ($dispatchTarget -eq 'copilot') {
        Invoke-QueuedCopilotTask -Entry $Entry -RunId $runId -SummaryPath $summaryPath
        return
    }

    # H38-14 widened the VOCABULARY from claude|copilot to the full registry, so
    # a token can be valid without this runner being able to execute it. H38-16
    # added the `codex` branch, which leaves `auto` -- resolved to a real
    # provider by the router in H38-17. Everything below is the LOCAL execution
    # path, and it now runs one of two different CLIs, so without this guard an
    # unhandled token would silently run whichever one the code happens to
    # default to against a real repository. Refuse by name instead.
    $localProviders = @('claude', 'codex')
    if ($dispatchTarget -notin $localProviders) {
        $unrunnable = ("dispatchTarget '{0}' is a known token but this runner has no branch for it yet; refusing rather than running {1} in its place" -f $dispatchTarget, ($localProviders -join ' or '))
        Write-Host ("  refused: {0}" -f $unrunnable) -ForegroundColor Red
        if (-not $DryRun) {
            Update-TaskSummary -SummaryPath $summaryPath -Set @{ status = 'failed'; error = $unrunnable; runnerCompletedAt = (Get-Date).ToString('o') }
        }
        return
    }

    # From here down the provider is a VARIABLE, never a literal. Every 'claude'
    # left hardcoded below this line would be a codex run reported as a Claude
    # one -- in the result file, in the usage ledger, and in the cooldown that
    # decides which subscription is rested.
    $localProvider = [string]$dispatchTarget
    $localCommand = Get-AgentProviderCommandName -Provider $localProvider

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
        Write-Host "  [DRYRUN] would: claim -> git switch -c $branch -> launch $localCommand -> verify -> commit -> awaiting-review" -ForegroundColor Yellow
        if ($localProvider -eq 'codex') {
            Write-Host ("  [DRYRUN] {0} {1} (cwd={2})" -f $localCommand, "exec --json --sandbox workspace-write --output-schema <schema> <prompt>", $repo) -ForegroundColor Yellow
        }
        else {
            Write-Host ("  [DRYRUN] {0} {1} (cwd={2})" -f $localCommand, $(if ($Headless) { "-p <prompt> --permission-mode $PermissionMode" } else { "--permission-mode $PermissionMode <prompt>" }), $repo) -ForegroundColor Yellow
        }
        return
    }

    Update-TaskSummary -SummaryPath $summaryPath -Set @{ status = 'running'; runnerStartedAt = (Get-Date).ToString('o'); runnerPid = $PID }
    try {
        if (-not (Test-Path -LiteralPath (Join-Path $repo '.git'))) { throw "Not a git repo: $repo" }

        # Working branch (create, or switch if it already exists).
        & git -C $repo switch -c $branch 2>$null
        if ($LASTEXITCODE -ne 0) {
            & git -C $repo switch $branch 2>$null
            if ($LASTEXITCODE -ne 0) { throw "Failed to switch to branch '$branch' in repo '$repo'." }
        }

        # Launch the provider CLI in the repo.
        if (-not (Get-Command $localCommand -ErrorAction SilentlyContinue)) {
            throw ("'{0}' not found on PATH. Run this as the operator with the {1} CLI installed." -f $localCommand, $localProvider)
        }
        # Declared before the launch so the parse below can read it
        # unconditionally: Tee-Object -Variable writes into this scope, and an
        # interactive run never sets it at all.
        $claudeLines = @()
        Push-Location $repo
        try {
            if ($localProvider -eq 'codex') {
                # H38-16. Codex has one mode: structured, sandboxed, with the
                # ExecutionResult schema handed to it. There is no interactive
                # variant here because the runner is not a terminal the operator
                # is watching -- an unattended interactive session would block
                # on the first approval prompt forever.
                $codexArgv = New-CodexExecutionArgument -Prompt $prompt -SchemaPath (Get-CodexOutputSchemaPath -WorkspaceRoot $WorkspaceRoot)
                & $localCommand @codexArgv 2>&1 | Tee-Object -Variable claudeLines | Out-Null
            }
            elseif ($Headless) {
                # Release 3.8 M1 (H38-04) - structured output, captured.
                # Tee rather than redirect: the operator still sees the stream
                # live, and the same lines are kept for the adapter to parse.
                $claudeArgv = New-ClaudeExecutionArgument -Prompt $prompt -PermissionMode $PermissionMode
                & $localCommand @claudeArgv 2>&1 | Tee-Object -Variable claudeLines | Out-Null
            }
            else { & $localCommand --permission-mode $PermissionMode $prompt }
            if ($LASTEXITCODE -ne 0) { throw ("{0} execution failed with exit code {1}." -f $localProvider, $LASTEXITCODE) }
        }
        finally { Pop-Location }

        # The session can outlive the repo it was handed: the api-host smoke
        # cleans up its dispatch fixture while a racing claim is still inside
        # it (run 20260819-145958-7bc51ee2). Once `.git` is gone, every
        # `git -C $repo` below resolves upward to the nearest enclosing
        # repository, and the add/commit lands in the PARENT working tree on
        # whatever branch it happens to have checked out. Re-verify the root
        # before touching git; the throw records the run as 'failed'.
        $topLevel = & git -C $repo rev-parse --show-toplevel 2>$null
        $topLevelFull = if ($LASTEXITCODE -eq 0 -and $topLevel) { [System.IO.Path]::GetFullPath([string]$topLevel) } else { $null }
        $repoFull = [System.IO.Path]::GetFullPath($repo).TrimEnd('\')
        if (-not $topLevelFull -or -not [string]::Equals($topLevelFull.TrimEnd('\'), $repoFull, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Repo vanished mid-run: '$repo' is no longer the root of a git working tree (git resolved: '$topLevel')."
        }

        # Release 3.8 M1 (H38-03) - what did the agent actually say happened?
        #
        # Headless is where the question has teeth: nobody watched, so the only
        # evidence is what the adapter wrote. H38-04 is what writes it; until
        # then this reads $null and every headless run fails BY NAME, which is
        # the milestone's acceptance criterion rather than a regression.
        #
        # An interactive run has a human in the loop who saw the session, so it
        # records its own result instead of demanding one from an adapter that
        # was never involved. Every run leaves a result file either way.
        $runExitCode = if ($null -ne $LASTEXITCODE) { [int]$LASTEXITCODE } else { 0 }
        $executionResult = $null
        # Codex is always structured -- see the launch above -- so it takes the
        # transcript path regardless of -Headless, which is a Claude Code flag.
        if ($Headless -or $localProvider -eq 'codex') {
            # Release 3.8 M1 (H38-04) - the adapter turns the transcript into a
            # result. The provider-native payload is retained alongside it: the
            # spec asks for it for diagnosis, and it is also how a REAL
            # transcript reaches the fixture set without anyone spending quota
            # to record one.
            $claudeCaptured = @(@($claudeLines) | ForEach-Object { [string]$_ })
            if ($claudeCaptured.Count -gt 0) {
                $streamPath = Join-Path $runsDir ("{0}.{1}.stream.jsonl" -f $runId, $localProvider)
                try { Set-Content -LiteralPath $streamPath -Value $claudeCaptured -Encoding UTF8 }
                catch { Write-Host ("  [warn] could not retain the provider transcript: {0}" -f $_.Exception.Message) -ForegroundColor DarkYellow }

                $parsedStream = if ($localProvider -eq 'codex') { ConvertFrom-CodexJsonl -Lines $claudeCaptured } else { ConvertFrom-ClaudeStreamJson -Lines $claudeCaptured }
                if (@($parsedStream.parseErrors).Count -gt 0) {
                    Write-Host ("  [warn] {0} unparseable transcript line(s): {1}" -f @($parsedStream.parseErrors).Count, (@($parsedStream.parseErrors) -join ', ')) -ForegroundColor DarkYellow
                }
                $changedForResult = @(& git -C $repo status --porcelain | ForEach-Object { $_.Substring(3) })
                # The config carries the limitSignals that tell a provider limit
                # apart from an implementation failure. $null when it cannot be
                # loaded, and the adapter then reports the plain failure it can
                # actually see rather than guessing at limit wording.
                $providerConfigForResult = $null
                if (Get-Command -Name 'Get-AgentProviderConfig' -ErrorAction SilentlyContinue) {
                    $providerConfigForResult = Get-AgentProviderConfig -ConfigPath (Get-AgentProviderConfigPath -WorkspaceRoot (Split-Path -Parent $PSScriptRoot))
                }
                $adapterResult = if ($localProvider -eq 'codex') {
                    ConvertTo-CodexExecutionResult -Parsed $parsedStream -TaskId $runId -ExecutionId $runId -ChangedFiles $changedForResult -Config $providerConfigForResult
                }
                else {
                    ConvertTo-ClaudeExecutionResult -Parsed $parsedStream -TaskId $runId -ExecutionId $runId -ChangedFiles $changedForResult -Config $providerConfigForResult
                }
                if ($null -ne $adapterResult) {
                    $null = Save-ExecutionResult -WorkspaceRoot $WorkspaceRoot -Result $adapterResult

                    # H38-12. What the run actually consumed is rank-4 evidence
                    # toward replacing D-011's guessed per-task cost with a
                    # measured one. Best-effort: a capacity bookkeeping failure
                    # must never fail a run that succeeded.
                    try {
                        if (Get-Command -Name 'Add-ProviderUsageObservation' -ErrorAction SilentlyContinue) {
                            $null = Add-ProviderUsageObservation -WorkspaceRoot $WorkspaceRoot -Provider $localProvider -Result $adapterResult
                        }
                        # Codex answers $null here by construction: the spec
                        # forbids equating its token telemetry with remaining
                        # allowance, so the tokens above are consumption
                        # evidence and no window is derived from them.
                        $adapterWindow = if ($localProvider -eq 'codex') { Get-CodexAdapterCapacity -Parsed $parsedStream } else { Get-ClaudeAdapterCapacity -Parsed $parsedStream }
                        if ($null -ne $adapterWindow -and (Get-Command -Name 'Merge-ProviderCapacityWindow' -ErrorAction SilentlyContinue)) {
                            $capacityRecordNow = Read-ProviderCapacityRecord -WorkspaceRoot $WorkspaceRoot -Provider $localProvider
                            if ($null -ne $capacityRecordNow) {
                                $mergeOutcome = Merge-ProviderCapacityWindow -Record $capacityRecordNow -Window $adapterWindow
                                if ($mergeOutcome.merged) { $null = Save-ProviderCapacityRecord -WorkspaceRoot $WorkspaceRoot -Record $mergeOutcome.record }
                            }
                        }
                    }
                    catch { Write-Host ("  [warn] could not record capacity evidence: {0}" -f $_.Exception.Message) -ForegroundColor DarkYellow }
                }
            }
            $executionResult = Read-ExecutionResult -WorkspaceRoot $WorkspaceRoot -TaskId $runId
        }
        else {
            $executionResult = New-ExecutionResult `
                -TaskId $runId `
                -ExecutionId $runId `
                -Provider $localProvider `
                -Status 'implementation_complete' `
                -Summary 'interactive session; result recorded by the runner' `
                -Source 'interactive'
            $null = Save-ExecutionResult -WorkspaceRoot $WorkspaceRoot -Result $executionResult
        }

        $outcome = Resolve-RunOutcomeFromResult -Result $executionResult -ExitCode $runExitCode
        if ($outcome.status -eq 'failed') {
            # Return WITHOUT committing. Committing work whose result is missing
            # or malformed would put unreviewable changes on a branch and call
            # them ready, which is the exact failure this packet removes.
            Update-TaskSummary -SummaryPath $summaryPath -Set @{
                status            = $outcome.status
                error             = $outcome.error
                branch            = $branch
                resultPath        = (Get-ExecutionResultPath -WorkspaceRoot $WorkspaceRoot -TaskId $runId)
                runnerCompletedAt = (Get-Date).ToString('o')
            }
            Write-Host ("  [failed] {0}" -f $outcome.error) -ForegroundColor Red
            return
        }

        if ($outcome.status -eq 'queued') {
            # A provider limit is state, not a failure. Before H38-10 this fell
            # THROUGH to verify-commit-push, so an exhausted subscription would
            # have committed whatever happened to be on the branch and called it
            # ready for review. Return without committing, and leave branch,
            # attempt and providerSessionId exactly as they are so the task can
            # resume on the same session when the window reopens.
            $capacitySummary = ''
            $capacityProvider = $localProvider
            if ($null -ne $executionResult) {
                if ($executionResult -is [System.Collections.IDictionary]) {
                    if ($executionResult.Contains('summary')) { $capacitySummary = [string]$executionResult['summary'] }
                    if ($executionResult.Contains('provider')) { $capacityProvider = [string]$executionResult['provider'] }
                }
                else {
                    if ($executionResult.PSObject.Properties.Name -contains 'summary') { $capacitySummary = [string]$executionResult.summary }
                    if ($executionResult.PSObject.Properties.Name -contains 'provider') { $capacityProvider = [string]$executionResult.provider }
                }
            }

            $capacitySignal = $null
            if ((Get-Command -Name 'Test-ProviderLimitSignal' -ErrorAction SilentlyContinue) -and $null -ne $providerConfigForResult) {
                $capacitySignal = Test-ProviderLimitSignal -Provider $capacityProvider -Text $capacitySummary -Config $providerConfigForResult
            }

            $capacityWait = Resolve-CapacityWaitUpdate -Provider $capacityProvider -LimitSignal $capacitySignal -Summary $capacitySummary
            Update-TaskSummary -SummaryPath $summaryPath -Set $capacityWait.set

            if (Get-Command -Name 'Set-ProviderCooldown' -ErrorAction SilentlyContinue) {
                try {
                    $null = Set-ProviderCooldown -WorkspaceRoot $WorkspaceRoot -Provider $capacityProvider `
                        -Until $capacityWait.cooldownUntil -Source 'rate-limit-response' -ResetAssumed:$capacityWait.resetAssumed
                }
                catch { Write-Host ("  [warn] could not record the provider cooldown: {0}" -f $_.Exception.Message) -ForegroundColor DarkYellow }
            }

            # H38-33 wires the canonical execution.* events. Write-AgentRunEvent
            # is not loaded in the runner today, so this is a no-op until then
            # rather than a dot-source added for one call site.
            if (Get-Command -Name 'Write-AgentRunEvent' -ErrorAction SilentlyContinue) {
                try { Write-AgentRunEvent -WorkspaceRoot $WorkspaceRoot -RunId $runId -EventType 'execution.capacity.exhausted' }
                catch { Write-Host ("  [warn] could not record the capacity event: {0}" -f $_.Exception.Message) -ForegroundColor DarkYellow }
            }

            Write-Host ("  [capacity-wait] {0} until {1}{2}" -f $capacityProvider, $capacityWait.cooldownUntil, $(if ($capacityWait.resetAssumed) { ' (assumed)' } else { '' })) -ForegroundColor DarkYellow
            return
        }

        $resultSource = ''
        $resultSessionId = $null
        if ($null -ne $executionResult) {
            if ($executionResult -is [System.Collections.IDictionary]) {
                if ($executionResult.Contains('source')) { $resultSource = [string]$executionResult['source'] }
                if ($executionResult.Contains('providerSessionId')) { $resultSessionId = $executionResult['providerSessionId'] }
            }
            else {
                if ($executionResult.PSObject.Properties.Name -contains 'source') { $resultSource = [string]$executionResult.source }
                if ($executionResult.PSObject.Properties.Name -contains 'providerSessionId') { $resultSessionId = $executionResult.providerSessionId }
            }
        }

        # Best-effort verify.
        $verifyResult = 'skipped'
        $verifyCmd = Resolve-VerifyCommand -RepoPath $repo
        if ($verifyCmd) {
            Write-Host ("  verify: {0}" -f $verifyCmd.Display) -ForegroundColor DarkGray
            Push-Location $repo
            try { & $verifyCmd.Exe $verifyCmd.Arguments | Out-Null; $verifyResult = if ($LASTEXITCODE -eq 0) { 'passed' } else { 'failed' } }
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

        # Release 3.4 milestone 4 — the completion edit rides the feature
        # branch as its own commit, so the merge is what makes it
        # authoritative. Any refusal (item not found, default branch, git
        # failure) is RECORDED rather than fatal: the work is still good, and
        # the missing edit surfaces by name at the write-back gate instead of
        # silently at review.
        $completionStatus = 'skipped'
        $completionSha = $null
        $completionDetail = ''
        if ((Get-Command -Name 'Add-RoadmapCompletionCommit' -ErrorAction SilentlyContinue) -and -not [string]::IsNullOrWhiteSpace([string]$Entry.selectedTask)) {
            $entryRoadmapPath = if ($Entry.PSObject.Properties.Name -contains 'roadmapPath' -and $Entry.roadmapPath) { [string]$Entry.roadmapPath } else { '' }
            $completion = Add-RoadmapCompletionCommit -RepoPath $repo -RoadmapPath $entryRoadmapPath `
                -ItemText ([string]$Entry.selectedTask) -RunId $runId
            $completionDetail = [string]$completion.reason
            if ($completion.committed) {
                $completionStatus = 'committed'
                $completionSha = [string]$completion.commitSha
                Write-Host ("  [completion] {0}" -f $completion.reason) -ForegroundColor DarkGray
            }
            elseif ($completion.alreadyComplete) {
                $completionStatus = 'already-complete'
                Write-Host ("  [completion] {0}" -f $completion.reason) -ForegroundColor DarkGray
            }
            else {
                $completionStatus = [string]$completion.category
                Write-Host ("  [completion] not committed ({0}): {1}" -f $completion.category, $completion.reason) -ForegroundColor DarkYellow
            }
        }
        $commitSha = (& git -C $repo rev-parse --short HEAD 2>$null)

        Update-TaskSummary -SummaryPath $summaryPath -Set @{
            status          = $outcome.status
            branch          = $branch
            commitSha       = "$commitSha"
            filesChanged    = $filesChanged
            verifyResult    = $verifyResult
            completionEditStatus = $completionStatus
            completionCommitSha  = $completionSha
            completionEditDetail = $completionDetail
            resultPath        = (Get-ExecutionResultPath -WorkspaceRoot $WorkspaceRoot -TaskId $runId)
            resultSource      = $resultSource
            providerSessionId = $resultSessionId
            runnerCompletedAt = (Get-Date).ToString('o')
        }
        Write-Host ("  [{0}] branch={1} commit={2} files={3} verify={4} completion={5}" -f $outcome.status, $branch, $commitSha, $filesChanged, $verifyResult, $completionStatus) -ForegroundColor Green
        Write-Host "  Review the branch, then approve the push - the PR opens through the product." -ForegroundColor DarkGray
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
# A marker left by a previous run would stop this one at its first poll.
Clear-RunnerStopFile -StopFilePath $StopFilePath
Write-Host ("  stop with: New-Item -ItemType File '{0}'  (honored at the next poll boundary)" -f $StopFilePath) -ForegroundColor DarkGray

# Release 3.8 M2 (H38-11). The provider policy the claim gate reads, resolved
# once: a poll loop that re-read a config file every 15 seconds would turn an
# editor's half-saved file into a refusal to work.
$runnerProviderConfig = $null
if (Get-Command -Name 'Get-AgentProviderConfig' -ErrorAction SilentlyContinue) {
    $runnerProviderConfig = Get-AgentProviderConfig -ConfigPath (Get-AgentProviderConfigPath -WorkspaceRoot (Split-Path -Parent $PSScriptRoot))
}

# Orphan repair runs ONCE, here, before the first poll. A run left `running` by
# a runner that died is not just holding a slot -- it shows on the board as work
# in progress that will never finish. Naming it failed/orphaned is the only way
# anyone can tell it apart from a live run. Not per-poll: a live run's own pid
# equals this one's, so repeated passes would do nothing but re-read the disk.
if ((Get-Command -Name 'Repair-OrphanedRunSummary' -ErrorAction SilentlyContinue) -and $null -ne $runnerProviderConfig) {
    try {
        $orphaned = @(Repair-OrphanedRunSummary -RunsDir $runsDir -CurrentPid $PID -Config $runnerProviderConfig)
        foreach ($orphanId in $orphaned) {
            Write-Host ("  [orphaned] {0} was left running by a runner that is gone; marked failed" -f $orphanId) -ForegroundColor DarkYellow
        }
    }
    catch { Write-Host ("  [warn] orphan repair failed: {0}" -f $_.Exception.Message) -ForegroundColor DarkYellow }
}

do {
    if (Test-RunnerStopRequested -StopFilePath $StopFilePath) {
        Write-Host ("Stop requested ({0}); exiting before claiming anything." -f $StopFilePath) -ForegroundColor Yellow
        Clear-RunnerStopFile -StopFilePath $StopFilePath
        break
    }

    $claimable = @(Get-QueueEntries -QueuePath $QueuePath | Where-Object {
            (Get-TaskSummaryStatus -SummaryPath (Join-Path $runsDir ("{0}.summary.json" -f $_.runId))) -eq 'queued'
        })

    # Beat every cycle, including the idle ones. A runner that only announced
    # itself while working would look absent exactly when the portal most needs
    # to know it is there — before queueing anything.
    # Cooldowns and slot usage ride the heartbeat so the portal can explain a
    # runner that is alive and deliberately not claiming -- which otherwise
    # looks exactly like one that is stuck.
    $beatCooldowns = $null
    $beatLocalSlots = $null
    if ($null -ne $runnerProviderConfig -and (Get-Command -Name 'Read-ProviderCapacityRecord' -ErrorAction SilentlyContinue)) {
        $beatCooldowns = @{}
        foreach ($beatProvider in @($runnerProviderConfig.providers.PSObject.Properties | ForEach-Object { $_.Name })) {
            $beatRecord = Read-ProviderCapacityRecord -WorkspaceRoot $WorkspaceRoot -Provider $beatProvider
            $beatCooldowns[$beatProvider] = $(if ($null -eq $beatRecord) { $null } else { $beatRecord.cooldownUntil })
        }
        $beatLocalSlots = 0
        foreach ($beatProvider in @($runnerProviderConfig.providers.PSObject.Properties | ForEach-Object { $_.Name })) {
            if ([string]$runnerProviderConfig.providers.$beatProvider.executionMode -ne 'local') { continue }
            $beatLocalSlots += Get-ProviderActiveExecutionCount -RunsDir $runsDir -Provider $beatProvider -HeartbeatPath $heartbeatPath
        }
    }
    Write-RunnerHeartbeat -Path $heartbeatPath -Heartbeat (New-RunnerHeartbeat `
            -QueuePath $QueuePath -PollSeconds $PollSeconds -ClaimedCount $claimable.Count -Mode $runnerMode -StopFilePath $StopFilePath `
            -ProviderCooldowns $beatCooldowns -LocalSlotsInUse $beatLocalSlots)

    if ($claimable.Count -eq 0) {
        if ($Once) { Write-Host 'No queued tasks.' -ForegroundColor DarkGray; break }
        Start-Sleep -Seconds $PollSeconds
        continue
    }
    foreach ($entry in $claimable) {
        # Between tasks, never mid-task: abandoning a running claude session
        # would leave a claimed item with no owner and a half-written branch.
        if (Test-RunnerStopRequested -StopFilePath $StopFilePath) {
            Write-Host ("Stop requested ({0}); finishing between tasks with {1} still queued." -f $StopFilePath, @($claimable).Count) -ForegroundColor Yellow
            break
        }
        # The claim gate. A refusal writes NOTHING: the entry stays `queued` and
        # is picked up by a later poll once the cooldown expires or the slot
        # frees. That is why this runs before Invoke-QueuedTask rather than
        # inside it -- claiming is the irreversible step.
        if ($null -ne $runnerProviderConfig) {
            $entryToken = [string](Resolve-ClaimToken -Entry $entry).token

            if ($entryToken -eq 'auto' -and -not (Get-Command -Name 'Resolve-ProviderSelection' -ErrorAction SilentlyContinue)) {
                # A18 means nothing writes `auto` by default, so this is a
                # safety net rather than an expected path.
                Write-Host ("  [skip] {0}: routing not enabled; leaving the entry queued" -f $entry.runId) -ForegroundColor DarkGray
                continue
            }

            $entryRecord = $null
            if (Get-Command -Name 'Read-ProviderCapacityRecord' -ErrorAction SilentlyContinue) {
                $entryRecord = Read-ProviderCapacityRecord -WorkspaceRoot $WorkspaceRoot -Provider $entryToken
            }
            $activeLocal = 0
            if (Get-Command -Name 'Get-ProviderActiveExecutionCount' -ErrorAction SilentlyContinue) {
                $activeLocal = Get-ProviderActiveExecutionCount -RunsDir $runsDir -Provider $entryToken -HeartbeatPath $heartbeatPath
            }

            $claimCheck = Test-RunnerClaimAllowed -Entry $entry -CapacityRecord $entryRecord -Config $runnerProviderConfig -ActiveLocalCount $activeLocal
            if (-not $claimCheck.allowed) {
                Write-Host ("  [{0}] {1}: {2}" -f $claimCheck.code, $entry.runId, $claimCheck.reason) -ForegroundColor DarkYellow
                continue
            }
            if ($claimCheck.code -eq 'capacity-advisory') {
                Write-Host ("  [advisory] {0}: {1}" -f $entry.runId, $claimCheck.reason) -ForegroundColor DarkGray
            }
        }

        Invoke-QueuedTask -Entry $entry
    }
    if (Test-RunnerStopRequested -StopFilePath $StopFilePath) {
        Clear-RunnerStopFile -StopFilePath $StopFilePath
        break
    }
    if ($Once) { break }
    Start-Sleep -Seconds $PollSeconds
} while ($true)
