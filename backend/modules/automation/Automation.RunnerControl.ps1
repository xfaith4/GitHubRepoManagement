Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
    Lane 0.20 -- the console acts instead of dictating a command.

    Automation.RunnerPresence.ps1 answers "is a runner alive". This answers the
    two questions that follow, which until now the operator answered themselves
    with a terminal: start one, and stop one.

    THE IDENTITY CONSTRAINT, AND WHY THE ANSWER IS TASK SCHEDULER.
    The portal is a LocalSystem service. The runner launches the operator's
    authenticated Claude Code, so it must run as the operator. A process this
    host spawned would come up as SYSTEM in session 0, hold neither the OAuth
    credential nor the Claude Code login, claim packets and fail every one --
    strictly worse than refusing, and precisely the hole Release 3.0 exists to
    climb out of. So the host never spawns a runner. It asks Task Scheduler to
    run the task Install-RoadmapTaskRunner.ps1 already registered under the
    operator's own account with LogonType=Interactive, and the scheduler does
    the cross-identity hop it is the only component privileged to do.

    WHAT "STARTED" IS ALLOWED TO MEAN. An Interactive task only runs when that
    operator is logged on. Logged out, Start-ScheduledTask still succeeds and
    the task simply waits. So nothing here ever reports that a runner is up:
    it reports that a start was REQUESTED, and presence -- the heartbeat, which
    only a live runner writes -- remains the sole evidence that one exists.

    WHY STOPPING NEEDS A FILE THAT OUTLIVES THE RUNNER. The stop marker the
    runner already watches cannot hold it down: the runner consumes the marker
    as it exits, and the logon task's repetition revives it within minutes. So
    "stop" would have meant "stop for about five minutes". The hold record is
    the durable half. It is NOT test scaffolding -- a mechanism built to
    reproduce a down runner was rejected on 2026-09-13 and stays rejected. This
    exists so the operator can halt real work they can see happening, which is
    what makes unattended execution acceptable in the first place.
#>

# Get-RunnerControlRoot lives in Automation.RunnerPresence.ps1, which every
# caller of this module loads first. It resolves REPO_MGMT_RUNNER_CONTROL_ROOT
# for the heartbeat as well as the two files below, so a test that isolates one
# runner-state file isolates all three. Without that override, a gate exercising
# the stop route would write a DURABLE hold into the operator's live output
# directory: their runner would stop mid-task and never come back.

function Get-RunnerHoldFilePath {
    <#
    .SYNOPSIS
        Where the operator's durable "stay stopped" record lives.
    .DESCRIPTION
        Deliberately a different file from the stop marker
        (`roadmap-task-runner.stop`). The marker is consumed by the runner that
        honors it; this one is not, because its whole job is to still be there
        when the scheduled task tries again.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory = $true)][string]$WorkspaceRoot)
    return (Join-Path (Get-RunnerControlRoot -WorkspaceRoot $WorkspaceRoot) 'roadmap-task-runner.hold.json')
}

function Get-RunnerStopMarkerPath {
    <#
    .SYNOPSIS
        The marker a live runner watches, honored at its next poll boundary.
    .DESCRIPTION
        Same path Invoke-RoadmapTaskRunner.ps1 and Stop-RoadmapTaskRunner.ps1
        already use. Named here so the host does not hand-build it a fourth
        time, and routed through the control root so a test that stops runners
        cannot reach the operator's live one.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory = $true)][string]$WorkspaceRoot)
    return (Join-Path (Get-RunnerControlRoot -WorkspaceRoot $WorkspaceRoot) 'roadmap-task-runner.stop')
}

function Get-RunnerInterruptMarkerPath {
    <#
    .SYNOPSIS
        The "stop mid-run" request a live runner watches while an agent runs.
    .DESCRIPTION
        Agent Ops "All work stop" (2026-09-27). The stop marker is honored
        BETWEEN tasks; this one is honored DURING one. The runner polls it while
        its provider child runs, kills the child's process tree, records the
        run as `stopped` (keeping branch, attempt and session id) and consumes
        the marker. Resume deletes it too, so a stale request cannot interrupt
        the first run after a restart. Routed through the control root like the
        other two, and the runner script mirrors this path -- the module smoke
        fails when they disagree.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory = $true)][string]$WorkspaceRoot)
    return (Join-Path (Get-RunnerControlRoot -WorkspaceRoot $WorkspaceRoot) 'roadmap-task-runner.interrupt.json')
}

function _RunnerControl_ReadJson {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    try {
        $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
        return (ConvertFrom-Json -InputObject $raw)
    }
    catch { return $null }
}

function _RunnerControl_Field {
    param([Parameter()][AllowNull()][object]$Obj, [Parameter(Mandatory = $true)][string]$Name, [Parameter()][AllowNull()][object]$Default = $null)
    if ($null -eq $Obj) { return $Default }
    if ($Obj -is [System.Collections.IDictionary]) { if ($Obj.Contains($Name)) { return $Obj[$Name] } else { return $Default } }
    if ($null -ne $Obj.PSObject -and ($Obj.PSObject.Properties.Name -contains $Name)) { return $Obj.$Name }
    return $Default
}

function Update-RoadmapRunSummary {
    <#
    .SYNOPSIS
        Merge fields into one `<runId>.summary.json`; every other key survives.
    .DESCRIPTION
        The same merge the runner's Update-TaskSummary does, so a host-side
        write (marking a remote run stopped, requeuing a local one on resume)
        preserves branch, attempt and providerSessionId exactly as the runner
        would. Missing file: nothing is written and $false is returned, because
        inventing a summary for a run the runner never recorded is how a ghost
        task appears on the board.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)][string]$SummaryPath,
        [Parameter(Mandatory = $true)][hashtable]$Set
    )
    if (-not (Test-Path -LiteralPath $SummaryPath -PathType Leaf)) { return $false }
    if (-not $PSCmdlet.ShouldProcess($SummaryPath, 'Update run summary')) { return $false }
    $obj = @{}
    try {
        $parsed = Get-Content -LiteralPath $SummaryPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($null -ne $parsed -and $null -ne $parsed.PSObject) {
            foreach ($p in $parsed.PSObject.Properties) { $obj[$p.Name] = $p.Value }
        }
    } catch { $obj = @{} }
    foreach ($k in $Set.Keys) { $obj[$k] = $Set[$k] }
    ($obj | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $SummaryPath -Encoding UTF8
    return $true
}

function Get-ActiveRunnerExecution {
    <#
    .SYNOPSIS
        Every run an "All work stop" would interrupt, and how.
    .DESCRIPTION
        Two kinds, told apart because they need different words on screen:

          * local  -- a summary at `running` whose `runnerPid` is a process that
                      is alive right now. The runner owns the provider child, so
                      the host SIGNALS it (the interrupt marker) rather than
                      killing anything itself. A `running` summary whose pid is
                      gone is an orphan, not an active run; the runner's own
                      orphan repair names it failed at its next start.
          * remote -- a copilot task at `dispatched`: the agent runs on GitHub
                      and nothing local can stop it. It is marked stopped so the
                      console stops presenting it as in flight, and labelled as
                      remote so nobody reads "stopped" as "killed".

        Liveness is the pid, not the heartbeat's age: the runner beats between
        tasks and a long agent session outlives the staleness budget, so the
        beat is stale precisely when there IS something to interrupt.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param([Parameter(Mandatory = $true)][string]$WorkspaceRoot)

    $runsDir = Get-RoadmapRunsDirectory -WorkspaceRoot $WorkspaceRoot
    $found = [System.Collections.Generic.List[object]]::new()
    if (-not (Test-Path -LiteralPath $runsDir -PathType Container)) { return $found.ToArray() }

    $runnerAlive = ($runnerPid -gt 0) -and ($null -ne (Get-Process -Id $runnerPid -ErrorAction SilentlyContinue))
    # The host does not load the execution events module at startup; the state
    # vocabulary is one function in it, so it is loaded here on first need
    # (the same seam Add-AgentRunDeliveryState uses).
    if (-not (Get-Command -Name 'Get-DeliveryState' -ErrorAction SilentlyContinue)) {
        $eventsModule = Join-Path (Split-Path -Parent $PSScriptRoot) 'execution\Execution.Events.ps1'
        if (Test-Path -LiteralPath $eventsModule -PathType Leaf) { . $eventsModule }
    }
    $deliveryStateAvailable = [bool](Get-Command -Name 'Get-DeliveryState' -ErrorAction SilentlyContinue)
    foreach ($file in @(Get-ChildItem -LiteralPath $runsDir -Filter '*.summary.json' -File -ErrorAction SilentlyContinue)) {
        $summary = _RunnerControl_ReadJson -Path $file.FullName
        if ($null -eq $summary) { continue }
        $status = ([string](_RunnerControl_Field -Obj $summary -Name 'status' -Default '')).ToLowerInvariant()
        $target = ([string](_RunnerControl_Field -Obj $summary -Name 'dispatchTarget' -Default 'claude')).ToLowerInvariant()
        if ([string]::IsNullOrWhiteSpace($target)) { $target = 'claude' }

        $remote = $false
        if ($status -eq 'running') {
            $summaryPid = _RunnerControl_Field -Obj $summary -Name 'runnerPid' -Default $null
            if (-not $runnerAlive -or $null -eq $summaryPid -or ([string]$summaryPid -ne [string]$runnerPid)) { continue }
        }
        elseif ($status -eq 'dispatched' -and $target -eq 'copilot') {
            $remote = $true
        }
        else { continue }

        $runId = [string](_RunnerControl_Field -Obj $summary -Name 'runId' -Default '')
        if ([string]::IsNullOrWhiteSpace($runId)) { $runId = $file.Name -replace '\.summary\.json$', '' }
        $repoName = ''
        foreach ($nameField in @('repoName', 'repository', 'repo')) {
            $candidate = [string](_RunnerControl_Field -Obj $summary -Name $nameField -Default '')
            if (-not [string]::IsNullOrWhiteSpace($candidate)) { $repoName = $candidate; break }
        }
        if ([string]::IsNullOrWhiteSpace($repoName)) {
            $localPath = [string](_RunnerControl_Field -Obj $summary -Name 'localRepoPath' -Default '')
            if (-not [string]::IsNullOrWhiteSpace($localPath)) { $repoName = Split-Path -Leaf $localPath }
        }
        $fromState = $null
        if ($deliveryStateAvailable) { $fromState = Get-DeliveryState -Status $status }

        $found.Add([pscustomobject]@{
            runId       = $runId
            repoName    = $repoName
            provider    = $target
            status      = $status
            fromState   = $fromState
            remote      = $remote
            summaryPath = $file.FullName
        })
    }
    return $found.ToArray()
}

function Read-RunnerHoldRecord {
    <#
    .SYNOPSIS
        Read the hold record. Present-but-unparseable still counts as held.
    .DESCRIPTION
        Fails CLOSED, unlike every other reader in this subsystem. Presence
        defaults an unreadable heartbeat to `absent` because claiming a runner
        exists when it may not is the dangerous direction. Here the dangerous
        direction is the opposite: an operator pressed stop, and a corrupt byte
        must not quietly resume the work they halted. So the file EXISTING is
        the hold; its contents only supply the attribution.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory = $true)][string]$WorkspaceRoot)

    $path = Get-RunnerHoldFilePath -WorkspaceRoot $WorkspaceRoot
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return [pscustomobject]@{
            held             = $false
            since            = $null
            by               = $null
            reason           = $null
            interruptedCount = 0
            readable         = $true
            path             = $path
        }
    }

    $since = $null
    $by = $null
    $reason = $null
    $interruptedCount = 0
    $readable = $false
    try {
        $raw = Get-Content -LiteralPath $path -Raw -Encoding UTF8
        if (-not [string]::IsNullOrWhiteSpace($raw)) {
            $record = ConvertFrom-Json -InputObject $raw
            $names = @($record.PSObject.Properties.Name)
            if ($names -contains 'stoppedAt') { $since = [string]$record.stoppedAt }
            if ($names -contains 'stoppedBy') { $by = [string]$record.stoppedBy }
            if ($names -contains 'reason') { $reason = [string]$record.reason }
            # Agent Ops: how many runs this hold interrupted, so the held banner
            # can say so after a page reload without re-deriving it.
            if ($names -contains 'interrupted' -and $null -ne $record.interrupted) { $interruptedCount = @($record.interrupted).Count }
            $readable = $true
        }
    }
    catch { $readable = $false }

    return [pscustomobject]@{
        held             = $true
        since            = $since
        by               = $by
        reason           = $reason
        interruptedCount = $interruptedCount
        readable         = $readable
        path             = $path
    }
}

function Get-RunnerTaskState {
    <#
    .SYNOPSIS
        Is the scheduled task that starts the runner registered, and enabled?
    .DESCRIPTION
        Answered separately from presence because the two failures need
        different words. "No runner and no task" means the installer was never
        run and a Start button would fail every time; "no runner but the task
        is there" is the ordinary case a start request fixes.

        Never throws: Task Scheduler is unavailable in some hosts (a container,
        a fixture workspace), and this route answering "unknown" is far more
        useful than a 500.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter()][string]$TaskName = 'RepoMgmtRoadmapTaskRunner')

    if (-not (Get-Command -Name 'Get-ScheduledTask' -ErrorAction SilentlyContinue)) {
        return [pscustomobject]@{ taskName = $TaskName; registered = $false; enabled = $null; available = $false }
    }
    try {
        $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction Stop
        return [pscustomobject]@{
            taskName   = $TaskName
            registered = $true
            enabled    = ([string]$task.State -ne 'Disabled')
            available  = $true
        }
    }
    catch {
        return [pscustomobject]@{ taskName = $TaskName; registered = $false; enabled = $null; available = $true }
    }
}

function Suspend-OperatorRunner {
    <#
    .SYNOPSIS
        The kill switch. Halt runners now, and keep them halted.
    .DESCRIPTION
        Two writes, and both are needed:

          * the hold record, so the logon task's repetition does not revive a
            runner minutes later -- without this, "stop" lasts one interval;
          * the stop marker, so a runner that is alive RIGHT NOW winds down at
            its next poll boundary.

        Returns immediately rather than waiting for the runner to exit. Without
        -Interrupt a task already in flight finishes first -- abandoning a live
        `claude` session would leave a claimed queue item with no owner and a
        half-written branch. The caller polls presence to watch it go.

        With -Interrupt (Agent Ops "All work stop", 2026-09-27) the hold is
        taken AND every active run is signalled: the interrupt marker names the
        local runs, and the runner that owns their provider child kills its
        process tree and records each as `stopped`, keeping workspace, branch,
        attempt and session id so resume can requeue it. A copilot task already
        on GitHub cannot be killed from here; it is marked stopped and flagged
        remote. Nothing is pushed or merged by a stop.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)][string]$WorkspaceRoot,
        [Parameter()][AllowEmptyString()][string]$RequestedBy = '',
        [Parameter()][AllowEmptyString()][string]$Reason = '',
        [Parameter()][switch]$Interrupt,
        [Parameter()][datetime]$Now = [datetime]::UtcNow
    )

    $holdPath = Get-RunnerHoldFilePath -WorkspaceRoot $WorkspaceRoot
    $stopPath = Get-RunnerStopMarkerPath -WorkspaceRoot $WorkspaceRoot
    $interruptPath = Get-RunnerInterruptMarkerPath -WorkspaceRoot $WorkspaceRoot
    if (-not $PSCmdlet.ShouldProcess($WorkspaceRoot, 'Hold the roadmap task runner')) {
        return [pscustomobject]@{ held = $false; holdPath = $holdPath; stopMarkerPath = $stopPath; stoppedAt = $null; reason = 'what-if'; interrupted = @() }
    }

    $outputDir = Split-Path -Parent $holdPath
    if ($outputDir -and -not (Test-Path -LiteralPath $outputDir)) { $null = New-Item -ItemType Directory -Path $outputDir -Force }

    $stoppedAt = $Now.ToUniversalTime().ToString('o')
    $stoppedBy = $(if ([string]::IsNullOrWhiteSpace($RequestedBy)) { 'operator' } else { $RequestedBy.Trim() })
    $stopReason = $(if ([string]::IsNullOrWhiteSpace($Reason)) { 'Stopped from the console.' } else { $Reason.Trim() })

    # Enumerated BEFORE the hold is written: the hold is what the runner reads
    # first, and a runner that exits on it between now and the marker write is
    # not "interrupted", it is stopped between tasks like any other.
    $interrupted = [System.Collections.Generic.List[object]]::new()
    if ($Interrupt) {
        foreach ($active in @(Get-ActiveRunnerExecution -WorkspaceRoot $WorkspaceRoot)) {
            $interrupted.Add([pscustomobject]@{
                runId     = [string]$active.runId
                repoName  = [string]$active.repoName
                provider  = [string]$active.provider
                fromState = $active.fromState
                remote    = [bool]$active.remote
            })
            if ($active.remote) {
                # The host owns this write: no local process will ever reach it.
                $null = Update-RoadmapRunSummary -SummaryPath $active.summaryPath -Set @{
                    status        = 'stopped'
                    stoppedFrom   = [string]$active.status
                    stoppedAt     = $stoppedAt
                    stoppedBy     = $stoppedBy
                    stopReason    = $stopReason
                    stoppedRemote = $true
                    interrupted   = $true
                } -Confirm:$false
            }
        }
        $localRunIds = @($interrupted | Where-Object { -not $_.remote } | ForEach-Object { $_.runId })
        $interruptRecord = [ordered]@{
            requestedAt = $stoppedAt
            requestedBy = $stoppedBy
            reason      = $stopReason
            # The runner interrupts only a run named here, so a marker written
            # for one session cannot kill the next one it happens to be running.
            runIds      = @($localRunIds)
        }
        ([pscustomobject]$interruptRecord | ConvertTo-Json -Depth 4) | Set-Content -LiteralPath $interruptPath -Encoding UTF8
    }

    $record = [ordered]@{
        stoppedAt = $stoppedAt
        stoppedBy = $stoppedBy
        reason    = $stopReason
        # Named in the record itself so anyone who finds this file knows how to
        # undo it without reading this module.
        release   = 'Remove this file, or press Start in the console, to let runners come back.'
    }
    if ($Interrupt) { $record['interrupted'] = @($interrupted | ForEach-Object { $_.runId }) }
    ([pscustomobject]$record | ConvertTo-Json -Depth 4) | Set-Content -LiteralPath $holdPath -Encoding UTF8
    Set-Content -LiteralPath $stopPath -Value $stoppedAt -Encoding UTF8

    return [pscustomobject]@{
        held           = $true
        holdPath       = $holdPath
        stopMarkerPath = $stopPath
        stoppedAt      = $stoppedAt
        stoppedBy      = $record.stoppedBy
        reason         = $record.reason
        interrupted    = $interrupted.ToArray()
    }
}

function Resume-OperatorRunner {
    <#
    .SYNOPSIS
        Release the hold and ask Task Scheduler to run the runner now.
    .DESCRIPTION
        There is deliberately no separate "start" path. Starting a runner that
        was never held and resuming one the operator stopped differ only in
        whether a hold file has to be deleted first, and a second entry point
        would be a second place for the two to drift apart.

        Clearing the hold alone would be enough eventually -- the logon task
        repeats -- but "eventually" is up to five minutes of an operator
        watching nothing happen, so the task is also triggered directly.

        Reports REQUESTED, never STARTED. See the identity note at the top of
        this file: logged out, this succeeds and no runner appears, and saying
        otherwise would rebuild the false-green the presence route removed.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)][string]$WorkspaceRoot,
        [Parameter()][string]$TaskName = 'RepoMgmtRoadmapTaskRunner'
    )

    $holdPath = Get-RunnerHoldFilePath -WorkspaceRoot $WorkspaceRoot
    $stopPath = Get-RunnerStopMarkerPath -WorkspaceRoot $WorkspaceRoot
    if (-not $PSCmdlet.ShouldProcess($WorkspaceRoot, 'Release the runner hold and trigger the runner task')) {
        return [pscustomobject]@{ requested = $false; holdReleased = $false; taskTriggered = $false; error = 'what-if' }
    }

    $holdReleased = $false
    if (Test-Path -LiteralPath $holdPath) {
        Remove-Item -LiteralPath $holdPath -Force -ErrorAction SilentlyContinue
        $holdReleased = -not (Test-Path -LiteralPath $holdPath)
    }
    # A leftover marker would stop the runner we are about to start at its very
    # first poll, which reads as "the console cannot start the runner".
    if (Test-Path -LiteralPath $stopPath) { Remove-Item -LiteralPath $stopPath -Force -ErrorAction SilentlyContinue }
    # Same for a leftover interrupt: it would kill the first agent the runner
    # we are about to start launches.
    $interruptPath = Get-RunnerInterruptMarkerPath -WorkspaceRoot $WorkspaceRoot
    if (Test-Path -LiteralPath $interruptPath) { Remove-Item -LiteralPath $interruptPath -Force -ErrorAction SilentlyContinue }

    # Agent Ops "All work stop": a run the stop interrupted goes back to the
    # queue with its branch, attempt and session id untouched, exactly as a
    # CAPACITY_WAIT does -- the runner picks it up again once it is back. A
    # remote (copilot) run stays stopped: GitHub is still running it and no
    # local requeue would change that.
    $requeued = [System.Collections.Generic.List[string]]::new()
    $runsDir = Get-RoadmapRunsDirectory -WorkspaceRoot $WorkspaceRoot
    if (Test-Path -LiteralPath $runsDir -PathType Container) {
        foreach ($file in @(Get-ChildItem -LiteralPath $runsDir -Filter '*.summary.json' -File -ErrorAction SilentlyContinue)) {
            $summary = _RunnerControl_ReadJson -Path $file.FullName
            if ($null -eq $summary) { continue }
            if (([string](_RunnerControl_Field -Obj $summary -Name 'status' -Default '')).ToLowerInvariant() -ne 'stopped') { continue }
            if ([bool](_RunnerControl_Field -Obj $summary -Name 'stoppedRemote' -Default $false)) { continue }
            $written = Update-RoadmapRunSummary -SummaryPath $file.FullName -Set @{
                status     = 'queued'
                error      = ''
                requeuedAt = [datetime]::UtcNow.ToString('o')
                requeuedBy = 'resume'
            } -Confirm:$false
            if ($written) {
                $runId = [string](_RunnerControl_Field -Obj $summary -Name 'runId' -Default '')
                if ([string]::IsNullOrWhiteSpace($runId)) { $runId = $file.Name -replace '\.summary\.json$', '' }
                $requeued.Add($runId)
            }
        }
    }

    $taskState = Get-RunnerTaskState -TaskName $TaskName
    if (-not $taskState.registered) {
        return [pscustomobject]@{
            requested     = $false
            holdReleased  = $holdReleased
            taskTriggered = $false
            taskName      = $TaskName
            requeued      = $requeued.ToArray()
            error         = ("Scheduled task '{0}' is not registered, so there is nothing to start. Register it once, unelevated, with: pwsh -File scripts/service/Install-RoadmapTaskRunner.ps1" -f $TaskName)
        }
    }

    try {
        Start-ScheduledTask -TaskName $TaskName -ErrorAction Stop
        return [pscustomobject]@{
            requested     = $true
            holdReleased  = $holdReleased
            taskTriggered = $true
            taskName      = $TaskName
            requeued      = $requeued.ToArray()
            error         = $null
        }
    }
    catch {
        # The error the attempt actually produced, verbatim. A start that fails
        # for an access reason and a start that fails because the operator is
        # logged out are different problems, and paraphrasing them into one
        # message is how the console stops being useful.
        return [pscustomobject]@{
            requested     = $false
            holdReleased  = $holdReleased
            taskTriggered = $false
            taskName      = $TaskName
            requeued      = $requeued.ToArray()
            error         = ("Task Scheduler refused to start '{0}': {1}" -f $TaskName, $_.Exception.Message)
        }
    }
}
