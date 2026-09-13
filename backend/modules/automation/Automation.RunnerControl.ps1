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

function Get-RunnerControlRoot {
    <#
    .SYNOPSIS
        Directory holding the two files that govern whether runners may run.
    .DESCRIPTION
        Overridable with REPO_MGMT_RUNNER_CONTROL_ROOT, and the override names
        the ROOT rather than either file so the hold record and the stop marker
        always move together -- exactly the shape REPO_MGMT_INDEX_ROOT settled
        on, for the same reason.

        The isolation is not hypothetical. The api-host smoke starts its host
        with the OPERATOR'S real workspace root, so without this a gate that
        exercised the stop route would write a hold into their live output
        directory: their runner would stop mid-task and, because a hold is
        durable by design, would never come back. That is the same shape as the
        gate that twice emptied the operator's portfolio index.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory = $true)][string]$WorkspaceRoot)

    $override = [Environment]::GetEnvironmentVariable('REPO_MGMT_RUNNER_CONTROL_ROOT')
    if (-not [string]::IsNullOrWhiteSpace($override)) { return $override }
    return (Join-Path $WorkspaceRoot 'output')
}

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
            held     = $false
            since    = $null
            by       = $null
            reason   = $null
            readable = $true
            path     = $path
        }
    }

    $since = $null
    $by = $null
    $reason = $null
    $readable = $false
    try {
        $raw = Get-Content -LiteralPath $path -Raw -Encoding UTF8
        if (-not [string]::IsNullOrWhiteSpace($raw)) {
            $record = ConvertFrom-Json -InputObject $raw
            $names = @($record.PSObject.Properties.Name)
            if ($names -contains 'stoppedAt') { $since = [string]$record.stoppedAt }
            if ($names -contains 'stoppedBy') { $by = [string]$record.stoppedBy }
            if ($names -contains 'reason') { $reason = [string]$record.reason }
            $readable = $true
        }
    }
    catch { $readable = $false }

    return [pscustomobject]@{
        held     = $true
        since    = $since
        by       = $by
        reason   = $reason
        readable = $readable
        path     = $path
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

        Returns immediately rather than waiting for the runner to exit. A task
        already in flight finishes first, by design -- abandoning a live
        `claude` session would leave a claimed queue item with no owner and a
        half-written branch. The caller polls presence to watch it go.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)][string]$WorkspaceRoot,
        [Parameter()][AllowEmptyString()][string]$RequestedBy = '',
        [Parameter()][AllowEmptyString()][string]$Reason = '',
        [Parameter()][datetime]$Now = [datetime]::UtcNow
    )

    $holdPath = Get-RunnerHoldFilePath -WorkspaceRoot $WorkspaceRoot
    $stopPath = Get-RunnerStopMarkerPath -WorkspaceRoot $WorkspaceRoot
    if (-not $PSCmdlet.ShouldProcess($WorkspaceRoot, 'Hold the roadmap task runner')) {
        return [pscustomobject]@{ held = $false; holdPath = $holdPath; stopMarkerPath = $stopPath; stoppedAt = $null; reason = 'what-if' }
    }

    $outputDir = Split-Path -Parent $holdPath
    if ($outputDir -and -not (Test-Path -LiteralPath $outputDir)) { $null = New-Item -ItemType Directory -Path $outputDir -Force }

    $stoppedAt = $Now.ToUniversalTime().ToString('o')
    $record = [ordered]@{
        stoppedAt = $stoppedAt
        stoppedBy = $(if ([string]::IsNullOrWhiteSpace($RequestedBy)) { 'operator' } else { $RequestedBy.Trim() })
        reason    = $(if ([string]::IsNullOrWhiteSpace($Reason)) { 'Stopped from the console.' } else { $Reason.Trim() })
        # Named in the record itself so anyone who finds this file knows how to
        # undo it without reading this module.
        release   = 'Remove this file, or press Start in the console, to let runners come back.'
    }
    ([pscustomobject]$record | ConvertTo-Json -Depth 4) | Set-Content -LiteralPath $holdPath -Encoding UTF8
    Set-Content -LiteralPath $stopPath -Value $stoppedAt -Encoding UTF8

    return [pscustomobject]@{
        held           = $true
        holdPath       = $holdPath
        stopMarkerPath = $stopPath
        stoppedAt      = $stoppedAt
        stoppedBy      = $record.stoppedBy
        reason         = $record.reason
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

    $taskState = Get-RunnerTaskState -TaskName $TaskName
    if (-not $taskState.registered) {
        return [pscustomobject]@{
            requested     = $false
            holdReleased  = $holdReleased
            taskTriggered = $false
            taskName      = $TaskName
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
            error         = ("Task Scheduler refused to start '{0}': {1}" -f $TaskName, $_.Exception.Message)
        }
    }
}
