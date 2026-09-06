<#
.SYNOPSIS
    Lane 0.17 — what is ACTUALLY happening in a dispatch lane, read from the
    run ledgers rather than inferred from a button click.

.DESCRIPTION
    Until this module existed, a lane's `running` state meant exactly one
    thing: an operator clicked Dispatch and had not yet clicked Complete. The
    board could not tell a Copilot agent three minutes into a draft PR from one
    that died an hour ago, because nothing joined the lane to the run.

    The join key is the dispatch run id. `/api/roadmap/dispatch/execute` mints
    it, writes it into `output/roadmap-task-history/runs/<id>.summary.json`, and
    registers an agent-run record carrying the same id in `dispatchRunId`. A
    lane assigned from a real dispatch stores it; a lane occupied by hand does
    not, and that difference is reported rather than hidden — `unlinked` is a
    verdict, not a blank.

    Two orthogonal facts come out, because they answer different questions:

      verdict  — WHERE the work is:  unlinked | queued | working
                                     | awaiting-review | finished | failed
      stalled  — whether it is STUCK there: a non-terminal verdict with nothing
                 observed for longer than that verdict's own patience.

    One threshold for both would be wrong in both directions. A queued task a
    runner has not claimed in 15 minutes is already a problem; a PR awaiting
    human review for 15 minutes is not. So each non-terminal verdict carries
    its own patience, and the applied threshold ships in the result so a
    surface can say why it called something stuck.

    Resolve-LaneObservation is pure — it takes the already-read ledger records
    and a clock, so every rule below is testable with no disk and no network.
    Get-LaneObservationMap is the thin I/O wrapper that reads the artifacts
    once for a whole ledger and calls it per lane.

.NOTES
    PowerShell 5.1 compatible.
    Dot-source after Execution.Ledger.ps1:
        . (Join-Path $executionModuleRoot 'Execution.LaneObservation.ps1')
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:LaneObservationRunsRelDir = 'output\roadmap-task-history\runs'
$script:LaneObservationAgentRunsRelDir = 'output\agent-runs\runs'

# How long each non-terminal verdict is willing to wait before it is called
# stuck. Terminal verdicts (finished, failed) are never stalled — they have
# arrived, and an arrival does not go stale.
$script:LaneObservationDefaultPatienceMinutes = @{
    queued          = 15
    working         = 90
    'awaiting-review' = 1440
}

function _LaneObs_Field {
    param([object]$Obj, [string]$Name, [object]$Default = $null)
    if ($null -eq $Obj) { return $Default }
    if ($Obj -is [System.Collections.IDictionary]) {
        if ($Obj.Contains($Name) -and $null -ne $Obj[$Name]) { return $Obj[$Name] }
        return $Default
    }
    if ($null -ne $Obj.PSObject -and ($Obj.PSObject.Properties.Name -contains $Name)) {
        $value = $Obj.$Name
        if ($null -ne $value) { return $value }
    }
    return $Default
}

function _LaneObs_Str {
    param([object]$Obj, [string]$Name, [string]$Default = '')
    return [string](_LaneObs_Field -Obj $Obj -Name $Name -Default $Default)
}

function _LaneObs_HasText {
    param([object]$Value)
    return (-not [string]::IsNullOrWhiteSpace([string]$Value))
}

<#
.SYNOPSIS
    Parse an ISO timestamp to UTC, returning $null rather than throwing.
#>
function _LaneObs_AsUtc {
    param([object]$Value)
    if (-not (_LaneObs_HasText $Value)) { return $null }
    [datetime]$parsed = [datetime]::MinValue
    $styles = [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal
    if ([datetime]::TryParse([string]$Value, [System.Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$parsed)) {
        return $parsed
    }
    return $null
}

<#
.SYNOPSIS
    Whole minutes between two instants, or $null when either is unknown.
#>
function _LaneObs_MinutesBetween {
    param([datetime]$From, [datetime]$To)
    $span = $To - $From
    $minutes = [int][math]::Floor($span.TotalMinutes)
    if ($minutes -lt 0) { return 0 }
    return $minutes
}

<#
.SYNOPSIS
    Read a JSON file, returning $null on any failure.
#>
function _LaneObs_ReadJson {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    try { return (ConvertFrom-Json -InputObject (Get-Content -LiteralPath $Path -Raw -Encoding UTF8)) } catch { return $null }
}

<#
.SYNOPSIS
    Pure — join one lane entry to its run records and say what is happening.

.DESCRIPTION
    Takes the already-read records so the whole decision table runs offline.

    Precedence, and why:

      1. Nothing to join on          -> unlinked. The lane is bookkeeping; say
                                        so rather than rendering an empty run.
      2. Terminal failure            -> failed. A refused, blocked or failed
                                        run, or a PR closed without merging.
      3. Merged                      -> finished.
      4. PR open and out of draft    -> awaiting-review. The agent delivered;
                                        what remains is a human or a merge.
      5. Claimed and producing       -> working.
      6. Written but unclaimed       -> queued.

    Failure is checked before success because a run can carry both a PR and a
    failure, and the failure is the fact the operator needs.

.PARAMETER Entry
    The ledger entry for the occupied lane.

.PARAMETER RunSummary
    The dispatch run summary (roadmap-task-history/runs/<dispatchRunId>.summary.json),
    or $null when none exists.

.PARAMETER AgentRun
    The agent-run ledger record whose dispatchRunId matches, or $null.

.PARAMETER NowUtc
    The clock. Defaults to now; passed explicitly by tests.

.PARAMETER PatienceMinutes
    Per-verdict staleness thresholds. Defaults to queued=15, working=90,
    awaiting-review=1440.
#>
function Resolve-LaneObservation {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Entry,
        [Parameter()]
        [object]$RunSummary = $null,
        [Parameter()]
        [object]$AgentRun = $null,
        [Parameter()]
        [datetime]$NowUtc = [datetime]::UtcNow,
        [Parameter()]
        [hashtable]$PatienceMinutes = $null
    )

    $patience = @{}
    foreach ($key in $script:LaneObservationDefaultPatienceMinutes.Keys) {
        $patience[$key] = [int]$script:LaneObservationDefaultPatienceMinutes[$key]
    }
    if ($null -ne $PatienceMinutes) {
        foreach ($key in $PatienceMinutes.Keys) { $patience[[string]$key] = [int]$PatienceMinutes[$key] }
    }

    $repoName      = _LaneObs_Str -Obj $Entry -Name 'repoName'
    $dispatchRunId = _LaneObs_Str -Obj $Entry -Name 'dispatchRunId'
    $agentRunId    = _LaneObs_Str -Obj $Entry -Name 'agentRunId'
    $assignedAtUtc = _LaneObs_AsUtc (_LaneObs_Str -Obj $Entry -Name 'assignedAt')

    $laneAgeMinutes = $null
    if ($null -ne $assignedAtUtc) { $laneAgeMinutes = _LaneObs_MinutesBetween -From $assignedAtUtc -To $NowUtc }

    # An agent run's own id is authoritative over whatever the lane recorded at
    # assign time: the ledger write is best-effort and can lose to a race, the
    # run record cannot.
    if (_LaneObs_HasText (_LaneObs_Str -Obj $AgentRun -Name 'runId')) {
        $agentRunId = _LaneObs_Str -Obj $AgentRun -Name 'runId'
    }

    $sources = [System.Collections.Generic.List[string]]::new()
    if ($null -ne $RunSummary) { $null = $sources.Add('run-summary') }
    if ($null -ne $AgentRun)   { $null = $sources.Add('agent-run') }

    $unlinked = [pscustomobject]@{
        linked             = $false
        dispatchRunId      = $(if (_LaneObs_HasText $dispatchRunId) { $dispatchRunId } else { $null })
        agentRunId         = $(if (_LaneObs_HasText $agentRunId) { $agentRunId } else { $null })
        repoName           = $repoName
        runStatus          = $null
        outcome            = $null
        branch             = $null
        pr                 = $null
        actions            = $null
        lastObservedAt     = $null
        observedAgeMinutes = $null
        laneAgeMinutes     = $laneAgeMinutes
        verdict            = 'unlinked'
        verdictLabel       = 'Bookkeeping'
        verdictDetail      = $(if ($null -eq $laneAgeMinutes) {
                'No agent run is linked to this lane — it was occupied by hand, so Running means "an operator claimed it", not "an agent is working".'
            } else {
                'No agent run is linked to this lane — it was occupied by hand {0} ago, so Running means "an operator claimed it", not "an agent is working".' -f (Format-LaneObservationAge -Minutes $laneAgeMinutes)
            })
        stalled            = $false
        stalledAfterMinutes = $null
        suggestedAction    = 'none'
        sources            = @($sources.ToArray())
    }

    # Nothing resolved: the lane holds no dispatch id, or held one that matches
    # no record. Either way there is no observed fact to report, and inventing
    # one would be worse than the blank this replaces.
    if ($null -eq $RunSummary -and $null -eq $AgentRun) { return $unlinked }

    $runSummaryStatus = (_LaneObs_Str -Obj $RunSummary -Name 'status').Trim().ToLowerInvariant()
    $agentStatus      = (_LaneObs_Str -Obj $AgentRun -Name 'status').Trim().ToLowerInvariant()
    $agentOutcome     = (_LaneObs_Str -Obj $AgentRun -Name 'outcome').Trim().ToLowerInvariant()
    $prState          = (_LaneObs_Str -Obj $AgentRun -Name 'prState').Trim().ToLowerInvariant()
    $prDraft          = [bool](_LaneObs_Field -Obj $AgentRun -Name 'prDraft' -Default $false)
    $prUrl            = _LaneObs_Str -Obj $AgentRun -Name 'prUrl'
    $prNumber         = _LaneObs_Field -Obj $AgentRun -Name 'prNumber' -Default $null
    $runError         = _LaneObs_Str -Obj $RunSummary -Name 'error'

    $branch = _LaneObs_Str -Obj $AgentRun -Name 'branch'
    if (-not (_LaneObs_HasText $branch)) { $branch = _LaneObs_Str -Obj $RunSummary -Name 'branch' }

    $pr = $null
    if (_LaneObs_HasText $prUrl) {
        $pr = [pscustomobject]@{
            number = $(if ($null -eq $prNumber) { $null } else { [int]$prNumber })
            url    = $prUrl
            state  = $(if (_LaneObs_HasText $prState) { $prState } else { 'open' })
            draft  = $prDraft
        }
    }

    $actions = $null
    $actionsRecord = _LaneObs_Field -Obj $AgentRun -Name 'actions' -Default $null
    if ($null -ne $actionsRecord) {
        $actions = [pscustomobject]@{
            status       = _LaneObs_Str -Obj $actionsRecord -Name 'status'
            conclusion   = $(if (_LaneObs_HasText (_LaneObs_Str -Obj $actionsRecord -Name 'conclusion')) { _LaneObs_Str -Obj $actionsRecord -Name 'conclusion' } else { $null })
            workflowName = _LaneObs_Str -Obj $actionsRecord -Name 'workflowName'
            runUrl       = $(if (_LaneObs_HasText (_LaneObs_Str -Obj $actionsRecord -Name 'runUrl')) { _LaneObs_Str -Obj $actionsRecord -Name 'runUrl' } else { $null })
        }
    }

    # The newest thing anyone actually observed about this run. Staleness is
    # measured from here, never from the lane's assign time: a lane assigned
    # this morning whose run was refreshed a minute ago is not stuck.
    $observedCandidates = [System.Collections.Generic.List[datetime]]::new()
    foreach ($field in @('lastRefreshAt', 'updatedAt', 'createdAt')) {
        $parsed = _LaneObs_AsUtc (_LaneObs_Str -Obj $AgentRun -Name $field)
        if ($null -ne $parsed) { $null = $observedCandidates.Add($parsed) }
    }
    foreach ($field in @('runnerCompletedAt', 'completedAt', 'runnerStartedAt', 'startedAt')) {
        $parsed = _LaneObs_AsUtc (_LaneObs_Str -Obj $RunSummary -Name $field)
        if ($null -ne $parsed) { $null = $observedCandidates.Add($parsed) }
    }

    $lastObservedUtc = $null
    foreach ($candidate in @($observedCandidates.ToArray())) {
        if ($null -eq $lastObservedUtc -or $candidate -gt $lastObservedUtc) { $lastObservedUtc = $candidate }
    }
    $observedAgeMinutes = $null
    if ($null -ne $lastObservedUtc) { $observedAgeMinutes = _LaneObs_MinutesBetween -From $lastObservedUtc -To $NowUtc }

    # ---- the decision table ------------------------------------------------
    $verdict = 'queued'
    $detail = ''
    $suggestedAction = 'wait'

    $prLabel = 'the PR'
    if ($null -ne $pr -and $null -ne $pr.number) { $prLabel = 'PR #{0}' -f $pr.number }

    if ($runSummaryStatus -in @('failed', 'refused', 'blocked') -or $agentStatus -eq 'failed' -or $agentOutcome -eq 'pr-closed-without-merge') {
        $verdict = 'failed'
        $suggestedAction = 'cancel'
        $detail = if ($agentOutcome -eq 'pr-closed-without-merge') {
            '{0} was closed without merging.' -f $prLabel
        } elseif (_LaneObs_HasText $runError) {
            'The run failed: {0}' -f $runError
        } elseif ($runSummaryStatus -eq 'refused') {
            'The runner refused this task before starting it.'
        } elseif ($runSummaryStatus -eq 'blocked') {
            'The runner blocked this task before starting it.'
        } else {
            'The agent run failed.'
        }
    }
    elseif ($agentOutcome -eq 'merged' -or $prState -eq 'merged') {
        $verdict = 'finished'
        $suggestedAction = 'complete'
        $detail = '{0} is merged.' -f $prLabel
    }
    elseif ($null -ne $pr -and $prState -eq 'closed') {
        $verdict = 'failed'
        $suggestedAction = 'cancel'
        $detail = '{0} was closed without merging.' -f $prLabel
    }
    elseif (($null -ne $pr -and -not $prDraft) -or $agentStatus -eq 'completed') {
        # `completed` on its own also lands here. The agent-run ledger marks a
        # run completed when the work is delivered — merged runs were already
        # taken above, so what is left is delivered-but-not-merged, whether or
        # not a PR has been observed yet. Falling through to the branches below
        # would have reported a finished agent as "queued, no runner has
        # claimed this yet", which is not merely vague but false.
        $verdict = 'awaiting-review'
        $suggestedAction = 'wait'
        $detail = if ($null -eq $pr) {
            'The agent run completed; no pull request has been observed for it yet.'
        } elseif ($prDraft) {
            'The agent run completed, but {0} is still a draft.' -f $prLabel
        } else {
            '{0} is open and out of draft — the agent has delivered; the merge is the remaining step.' -f $prLabel
        }
    }
    elseif ($agentStatus -in @('active', 'dispatched') -or $runSummaryStatus -in @('running', 'dispatched', 'awaiting-review')) {
        $verdict = 'working'
        $suggestedAction = 'wait'
        $detail = if ($null -ne $pr) {
            'The agent is working on draft {0}.' -f $prLabel
        } elseif ($runSummaryStatus -eq 'awaiting-review') {
            'The runner finished and pushed a branch; no pull request has been observed yet.'
        } else {
            'The runner has claimed this task and the agent is working; no pull request has been observed yet.'
        }
    }
    else {
        $verdict = 'queued'
        $suggestedAction = 'wait'
        $detail = 'Queued — no runner has claimed this task yet.'
    }

    # ---- stuck? ------------------------------------------------------------
    # Only a non-terminal verdict can stall, and only against its own patience.
    $stalled = $false
    $stalledAfter = $null
    if ($patience.ContainsKey($verdict)) {
        $stalledAfter = [int]$patience[$verdict]
        $ageForStaleness = $observedAgeMinutes
        if ($null -eq $ageForStaleness) { $ageForStaleness = $laneAgeMinutes }
        if ($null -ne $ageForStaleness -and $ageForStaleness -ge $stalledAfter) {
            $stalled = $true
            $detail = '{0} Nothing has moved for {1} — past the {2} this state waits before it is called stuck.' -f `
                $detail, (Format-LaneObservationAge -Minutes $ageForStaleness), (Format-LaneObservationAge -Minutes $stalledAfter)
        }
    }

    $label = switch ($verdict) {
        'failed'          { 'Failed' }
        'finished'        { 'Merged' }
        'awaiting-review' { 'Awaiting review' }
        'working'         { 'Working' }
        default           { 'Queued' }
    }
    if ($stalled) { $label = 'Stuck' }

    $runStatus = $agentStatus
    if (-not (_LaneObs_HasText $runStatus)) { $runStatus = $runSummaryStatus }

    return [pscustomobject]@{
        linked              = $true
        dispatchRunId       = $(if (_LaneObs_HasText $dispatchRunId) { $dispatchRunId } else { $null })
        agentRunId          = $(if (_LaneObs_HasText $agentRunId) { $agentRunId } else { $null })
        repoName            = $repoName
        runStatus           = $(if (_LaneObs_HasText $runStatus) { $runStatus } else { $null })
        outcome             = $(if (_LaneObs_HasText $agentOutcome) { $agentOutcome } else { $null })
        branch              = $(if (_LaneObs_HasText $branch) { $branch } else { $null })
        pr                  = $pr
        actions             = $actions
        lastObservedAt      = $(if ($null -eq $lastObservedUtc) { $null } else { $lastObservedUtc.ToString('o') })
        observedAgeMinutes  = $observedAgeMinutes
        laneAgeMinutes      = $laneAgeMinutes
        verdict             = $verdict
        verdictLabel        = $label
        verdictDetail       = $detail
        stalled             = $stalled
        stalledAfterMinutes = $stalledAfter
        suggestedAction     = $suggestedAction
        sources             = @($sources.ToArray())
    }
}

<#
.SYNOPSIS
    Pure — render a minute count the way an operator reads a clock.
#>
function Format-LaneObservationAge {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [int]$Minutes
    )

    if ($Minutes -lt 1)    { return 'less than a minute' }
    if ($Minutes -eq 1)    { return '1 minute' }
    if ($Minutes -lt 60)   { return '{0} minutes' -f $Minutes }

    $hours = [int][math]::Floor($Minutes / 60)
    if ($hours -lt 24) {
        if ($hours -eq 1) { return '1 hour' }
        return '{0} hours' -f $hours
    }

    $days = [int][math]::Floor($hours / 24)
    if ($days -eq 1) { return '1 day' }
    return '{0} days' -f $days
}

<#
.SYNOPSIS
    Read the run ledgers once and return an observation per occupied lane.

.DESCRIPTION
    Thin I/O wrapper. The agent-run directory is read a single time for the
    whole ledger rather than once per lane — there are at most two lanes today,
    but the read is the expensive part and a per-lane read would make the cost
    grow with a number this module does not control.

    Returns a hashtable keyed by repoName. A ledger with no running entries
    reads nothing from disk and returns an empty map.
#>
function Get-LaneObservationMap {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$WorkspaceRoot,
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Entries,
        [Parameter()]
        [datetime]$NowUtc = [datetime]::UtcNow
    )

    $map = @{}
    $running = @(@($Entries) | Where-Object { (_LaneObs_Str -Obj $_ -Name 'executionState') -eq 'running' })
    if ($running.Count -eq 0) { return $map }

    # Only lanes that recorded a dispatch id can join. A hand-occupied lane
    # skips the disk entirely and still gets its honest `unlinked` verdict.
    $dispatchIds = @(@($running | ForEach-Object { _LaneObs_Str -Obj $_ -Name 'dispatchRunId' }) | Where-Object { _LaneObs_HasText $_ })

    $agentRunsByDispatchId = @{}
    if ($dispatchIds.Count -gt 0) {
        $agentRunsDir = Join-Path $WorkspaceRoot $script:LaneObservationAgentRunsRelDir
        foreach ($file in @(Get-ChildItem -LiteralPath $agentRunsDir -Filter '*.json' -File -ErrorAction SilentlyContinue)) {
            $record = _LaneObs_ReadJson -Path $file.FullName
            if ($null -eq $record) { continue }
            $recordDispatchId = _LaneObs_Str -Obj $record -Name 'dispatchRunId'
            if (-not (_LaneObs_HasText $recordDispatchId)) { continue }
            if ($dispatchIds -notcontains $recordDispatchId) { continue }
            # Newest wins: a redispatch of the same item writes a second record,
            # and the lane is looking at the current one.
            $existing = $null
            if ($agentRunsByDispatchId.ContainsKey($recordDispatchId)) { $existing = $agentRunsByDispatchId[$recordDispatchId] }
            if ($null -eq $existing) {
                $agentRunsByDispatchId[$recordDispatchId] = $record
            } else {
                $existingAt = _LaneObs_AsUtc (_LaneObs_Str -Obj $existing -Name 'createdAt')
                $recordAt = _LaneObs_AsUtc (_LaneObs_Str -Obj $record -Name 'createdAt')
                if ($null -ne $recordAt -and ($null -eq $existingAt -or $recordAt -gt $existingAt)) {
                    $agentRunsByDispatchId[$recordDispatchId] = $record
                }
            }
        }
    }

    $runsDir = Join-Path $WorkspaceRoot $script:LaneObservationRunsRelDir
    foreach ($entry in $running) {
        $repoName = _LaneObs_Str -Obj $entry -Name 'repoName'
        if (-not (_LaneObs_HasText $repoName)) { continue }

        $dispatchRunId = _LaneObs_Str -Obj $entry -Name 'dispatchRunId'
        $runSummary = $null
        $agentRun = $null
        if (_LaneObs_HasText $dispatchRunId) {
            $runSummary = _LaneObs_ReadJson -Path (Join-Path $runsDir ('{0}.summary.json' -f $dispatchRunId))
            if ($agentRunsByDispatchId.ContainsKey($dispatchRunId)) { $agentRun = $agentRunsByDispatchId[$dispatchRunId] }
        }

        $map[$repoName] = Resolve-LaneObservation -Entry $entry -RunSummary $runSummary -AgentRun $agentRun -NowUtc $NowUtc
    }

    return $map
}
