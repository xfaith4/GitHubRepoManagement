<#
.SYNOPSIS
    Release 3.1 — the per-work-item trace that joins one roadmap item's whole
    life into a single record.

.DESCRIPTION
    Every stage of the north-star loop already writes its own ledger, and until
    now nothing joined them: answering "what happened to this item?" meant
    reconstructing the story from four append-only files whose only shared
    identifier was implicit. This module makes the join explicit and keyed, so
    one id resolves to every stage artifact.

    The seven canonical stages are exactly the chain Release 3.1 gates on:

        rank -> prompt -> dispatch -> agentRun -> actions -> mergeReadiness
             -> writeBack

    Each stage carries its own status, timestamp, evidence and the artifact it
    was read from. A stage that legitimately has not started yet is `pending`;
    a stage that SHOULD have an artifact because a later-or-equal stage already
    happened, but has none, is `missing` — that distinction is the point. A
    silent blank reads as "not there yet"; a `missing` stage names a broken
    link in the chain and is surfaced through `gaps`.

    Join-WorkItemTrace is pure — it takes the already-read stage inputs and
    returns the trace — so the whole decision table is testable offline with no
    disk, no network and no host. Get-WorkItemTrace is the thin I/O wrapper
    that reads each ledger and calls it.

    Join keys, in the order the chain mints them:

      packetId        minted by packaging      (packaged-items.jsonl)
      packagingRunId  minted by the scheduled run
      dispatchRunId   minted at approval       (roadmap-task-queue.jsonl,
                                                roadmap-task-history/runs/*)
      agentRunId      minted by the agent-run ledger, which stores the
                      dispatchRunId it came from
      branch          the only identifier the submit-PR history shares with
                      the packet, so the PR stage joins on it

.NOTES
    PowerShell 5.1 compatible.
    Dot-source after Automation.RoadmapPackaging.ps1 and MergeReadiness.ps1:
        . (Join-Path $executionModuleRoot 'Execution.Trace.ps1')
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:WorkItemTraceSchemaVersion = '1'
$script:WorkItemTraceWriteBackRelPath = 'output\roadmap-writeback\history.jsonl'
$script:WorkItemTraceQueueRelPath = 'output\roadmap-task-queue.jsonl'
$script:WorkItemTraceRunsRelDir = 'output\roadmap-task-history\runs'
$script:WorkItemTraceAgentRunsRelDir = 'output\agent-runs\runs'
$script:WorkItemTraceRepairHistoryRelPath = 'output\roadmap-repair-history\repair-history.jsonl'

# The canonical stage order. Section 8's guardrail is that a trace must show
# where the chain actually stands, so this list is the contract: a stage may
# change how it is derived, but the chain itself is fixed and ordered.
$script:WorkItemTraceStageOrder = @('rank', 'prompt', 'dispatch', 'agentRun', 'actions', 'mergeReadiness', 'writeBack')

$script:WorkItemTraceStageLabels = @{
    rank           = 'Rank'
    prompt         = 'Prompt'
    dispatch       = 'Dispatch'
    agentRun       = 'Agent run'
    actions        = 'Actions result'
    mergeReadiness = 'Merge readiness'
    writeBack      = 'Roadmap write-back'
}

function _Trace_GetField {
    param([object]$Obj, [string]$Name, [object]$Default = $null)
    if ($null -eq $Obj) { return $Default }
    if ($Obj -is [System.Collections.IDictionary]) {
        if ($Obj.Contains($Name) -and $null -ne $Obj[$Name]) { return $Obj[$Name] }
        return $Default
    }
    if ($null -ne $Obj.PSObject -and ($Obj.PSObject.Properties.Name -contains $Name)) {
        $v = $Obj.$Name
        if ($null -ne $v) { return $v }
    }
    return $Default
}

function _Trace_Str {
    param([object]$Obj, [string]$Name, [string]$Default = '')
    return [string](_Trace_GetField -Obj $Obj -Name $Name -Default $Default)
}

function _Trace_HasText {
    param([object]$Value)
    return (-not [string]::IsNullOrWhiteSpace([string]$Value))
}

function _Trace_ReadJsonl {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @() }
    $records = New-Object System.Collections.Generic.List[object]
    foreach ($line in @(Get-Content -LiteralPath $Path -Encoding UTF8 -ErrorAction SilentlyContinue)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try { $records.Add((ConvertFrom-Json -InputObject $line)) } catch { continue }
    }
    return @($records.ToArray())
}

function _Trace_ReadJson {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    try { return (ConvertFrom-Json -InputObject (Get-Content -LiteralPath $Path -Raw -Encoding UTF8)) } catch { return $null }
}

<#
.SYNOPSIS
    Pure — build one stage descriptor.
#>
function _Trace_NewStage {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)][ValidateSet('rank', 'prompt', 'dispatch', 'agentRun', 'actions', 'mergeReadiness', 'writeBack')][string]$Key,
        [Parameter(Mandatory = $true)][ValidateSet('complete', 'active', 'failed', 'blocked', 'pending', 'missing')][string]$Status,
        [Parameter()][AllowEmptyString()][string]$At = '',
        [Parameter()][AllowEmptyString()][string]$Detail = '',
        [Parameter()][AllowEmptyString()][string]$Artifact = '',
        [Parameter()][object]$Evidence = $null
    )

    return [pscustomobject]@{
        stage    = $Key
        label    = [string]$script:WorkItemTraceStageLabels[$Key]
        order    = ([array]::IndexOf($script:WorkItemTraceStageOrder, $Key) + 1)
        status   = $Status
        at       = if (_Trace_HasText $At) { $At } else { $null }
        detail   = $Detail
        artifact = if (_Trace_HasText $Artifact) { $Artifact } else { $null }
        evidence = if ($null -ne $Evidence) { $Evidence } else { [ordered]@{} }
    }
}

<#
.SYNOPSIS
    Pure — join one work item's stage records into a single ordered trace.
.DESCRIPTION
    Takes the already-read inputs and returns the trace. No disk, no network,
    no clock beyond the join timestamp, so every rule below is testable offline.

    `pending` vs `missing` is the load-bearing distinction: `pending` means the
    chain has not reached this stage, `missing` means it demonstrably has and
    the artifact that should exist does not. Only `missing` stages become gaps.
#>
function Join-WorkItemTrace {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        # Folded packaged-item record (Get-PackagedItemQueue shape): packetId,
        # status, history, dispatchRunId, packet.
        [Parameter()][object]$PackagedItem = $null,
        # roadmap-task-queue.jsonl line for the dispatch run.
        [Parameter()][object]$QueueEntry = $null,
        # roadmap-task-history/runs/<dispatchRunId>.summary.json
        [Parameter()][object]$RunSummary = $null,
        # agent-runs ledger record whose dispatchRunId matches, when the work
        # went through the cloud-agent path.
        [Parameter()][object]$AgentRun = $null,
        # repair-history 'submit-pr' record matched on branch.
        [Parameter()][object]$PrRecord = $null,
        # merge-readiness snapshot for the repo.
        [Parameter()][object]$MergeReadiness = $null,
        # roadmap write-back record (Release 3.1 milestone 2).
        [Parameter()][object]$WriteBack = $null,
        [Parameter()][AllowEmptyString()][string]$RequestedId = '',
        [Parameter()][AllowEmptyString()][string]$JoinedAt = ''
    )

    $packet = _Trace_GetField -Obj $PackagedItem -Name 'packet' -Default $null

    # ---- identity -------------------------------------------------------
    $packetId = _Trace_Str -Obj $PackagedItem -Name 'packetId'
    if (-not (_Trace_HasText $packetId)) { $packetId = _Trace_Str -Obj $packet -Name 'packetId' }
    $packagingRunId = _Trace_Str -Obj $PackagedItem -Name 'runId'
    if (-not (_Trace_HasText $packagingRunId)) { $packagingRunId = _Trace_Str -Obj $packet -Name 'runId' }

    $dispatchRunId = _Trace_Str -Obj $PackagedItem -Name 'dispatchRunId'
    if (-not (_Trace_HasText $dispatchRunId)) { $dispatchRunId = _Trace_Str -Obj $QueueEntry -Name 'runId' }
    if (-not (_Trace_HasText $dispatchRunId)) { $dispatchRunId = _Trace_Str -Obj $RunSummary -Name 'runId' }
    if (-not (_Trace_HasText $dispatchRunId)) { $dispatchRunId = _Trace_Str -Obj $AgentRun -Name 'dispatchRunId' }

    $agentRunId = _Trace_Str -Obj $AgentRun -Name 'runId'

    $repoName = _Trace_Str -Obj $packet -Name 'repoName'
    if (-not (_Trace_HasText $repoName)) { $repoName = _Trace_Str -Obj $PackagedItem -Name 'repoName' }
    if (-not (_Trace_HasText $repoName)) { $repoName = _Trace_Str -Obj $RunSummary -Name 'repository' }
    if (-not (_Trace_HasText $repoName)) { $repoName = _Trace_Str -Obj $QueueEntry -Name 'repository' }
    if (-not (_Trace_HasText $repoName)) { $repoName = _Trace_Str -Obj $AgentRun -Name 'repoName' }
    if (-not (_Trace_HasText $repoName)) { $repoName = _Trace_Str -Obj $MergeReadiness -Name 'repoName' }

    $repoId = _Trace_Str -Obj $packet -Name 'repoId'
    if (-not (_Trace_HasText $repoId)) { $repoId = _Trace_Str -Obj $AgentRun -Name 'repoId' }
    if (-not (_Trace_HasText $repoId)) { $repoId = _Trace_Str -Obj $MergeReadiness -Name 'repoId' }

    $itemText = _Trace_Str -Obj $packet -Name 'itemText'
    if (-not (_Trace_HasText $itemText)) { $itemText = _Trace_Str -Obj $QueueEntry -Name 'selectedTask' }
    if (-not (_Trace_HasText $itemText)) { $itemText = _Trace_Str -Obj $RunSummary -Name 'selectedTask' }
    if (-not (_Trace_HasText $itemText)) { $itemText = _Trace_Str -Obj $AgentRun -Name 'selectedTaskText' }

    $branch = _Trace_Str -Obj $RunSummary -Name 'branch'
    if (-not (_Trace_HasText $branch)) { $branch = _Trace_Str -Obj $QueueEntry -Name 'branch' }
    if (-not (_Trace_HasText $branch)) { $branch = _Trace_Str -Obj $packet -Name 'branch' }
    if (-not (_Trace_HasText $branch)) { $branch = _Trace_Str -Obj $AgentRun -Name 'branch' }

    $roadmapPath = _Trace_Str -Obj $packet -Name 'roadmapPath'
    if (-not (_Trace_HasText $roadmapPath)) { $roadmapPath = _Trace_Str -Obj $RunSummary -Name 'roadmapPath' }
    if (-not (_Trace_HasText $roadmapPath)) { $roadmapPath = _Trace_Str -Obj $QueueEntry -Name 'roadmapPath' }

    $traceId = @($dispatchRunId, $packetId, $agentRunId, $packagingRunId, $RequestedId) |
        Where-Object { _Trace_HasText $_ } | Select-Object -First 1
    if ($null -eq $traceId) { $traceId = '' }

    $stages = New-Object System.Collections.Generic.List[object]

    # ---- 1. rank --------------------------------------------------------
    $valueScore = _Trace_GetField -Obj $packet -Name 'valueScore' -Default $null
    if ($null -ne $packet -and $null -ne $valueScore) {
        $rationale = @(_Trace_GetField -Obj $packet -Name 'valueRationale' -Default @())
        $stages.Add((_Trace_NewStage -Key 'rank' -Status 'complete' `
                    -At (_Trace_Str -Obj $packet -Name 'createdAt') `
                    -Detail ("Ranked {0} ({1}) out of the repo's pending roadmap work." -f $valueScore, (_Trace_Str -Obj $packet -Name 'valueTier' -Default 'unscored')) `
                    -Artifact 'output/automation/packaged-items.jsonl' `
                    -Evidence ([ordered]@{
                        valueScore         = $valueScore
                        valueTier          = _Trace_Str -Obj $packet -Name 'valueTier'
                        valueRationale     = $rationale
                        roadmapOrder       = _Trace_GetField -Obj $packet -Name 'roadmapOrder' -Default $null
                        itemSection        = _Trace_Str -Obj $packet -Name 'itemSection'
                        estimatedWorkUnits = _Trace_GetField -Obj $packet -Name 'estimatedWorkUnits' -Default $null
                        maturityLevel      = _Trace_Str -Obj $packet -Name 'maturityLevel'
                    })))
    } elseif ($null -ne $QueueEntry -or $null -ne $RunSummary -or $null -ne $AgentRun) {
        # Work reached the chain without a packet — the wizard path dispatches
        # directly. The ranking that chose it was never recorded, and saying so
        # is the whole reason this stage exists.
        $stages.Add((_Trace_NewStage -Key 'rank' -Status 'missing' `
                    -Detail 'This item was dispatched without a packaging record, so the ranking that selected it was never written down.' `
                    -Artifact 'output/automation/packaged-items.jsonl'))
    } else {
        $stages.Add((_Trace_NewStage -Key 'rank' -Status 'pending' `
                    -Detail 'No packaging run has ranked this item yet.' `
                    -Artifact 'output/automation/packaged-items.jsonl'))
    }

    # ---- 2. prompt ------------------------------------------------------
    $prompt = _Trace_Str -Obj $packet -Name 'generatedPrompt'
    if (-not (_Trace_HasText $prompt)) { $prompt = _Trace_Str -Obj $QueueEntry -Name 'prompt' }
    if (_Trace_HasText $prompt) {
        $stages.Add((_Trace_NewStage -Key 'prompt' -Status 'complete' `
                    -At (_Trace_Str -Obj $packet -Name 'createdAt') `
                    -Detail ("Task prompt generated ({0} characters)." -f $prompt.Length) `
                    -Artifact 'output/automation/packaged-items.jsonl' `
                    -Evidence ([ordered]@{
                        promptLength          = $prompt.Length
                        branch                = $branch
                        baseBranch            = _Trace_Str -Obj $packet -Name 'baseBranch'
                        promptRefinementRunId = _Trace_Str -Obj $AgentRun -Name 'promptRefinementRunId'
                    })))
    } elseif ($null -ne $QueueEntry -or $null -ne $RunSummary -or $null -ne $AgentRun) {
        $stages.Add((_Trace_NewStage -Key 'prompt' -Status 'missing' `
                    -Detail 'Work ran for this item but the prompt it ran on was never recorded, so the instruction cannot be reviewed after the fact.' `
                    -Artifact 'output/automation/packaged-items.jsonl'))
    } else {
        $stages.Add((_Trace_NewStage -Key 'prompt' -Status 'pending' `
                    -Detail 'No prompt has been generated for this item yet.' `
                    -Artifact 'output/automation/packaged-items.jsonl'))
    }

    # ---- 3. dispatch ----------------------------------------------------
    # Approval is what causes dispatch, so the operator decision is evidence on
    # this stage rather than a stage of its own.
    $packetStatus = _Trace_Str -Obj $PackagedItem -Name 'status'
    $dispatchEvidence = [ordered]@{
        approvalStatus = if (_Trace_HasText $packetStatus) { $packetStatus } else { $null }
        approvedBy     = _Trace_Str -Obj $PackagedItem -Name 'updatedBy'
        approvedAt     = _Trace_Str -Obj $PackagedItem -Name 'updatedAt'
        dispatchRunId  = if (_Trace_HasText $dispatchRunId) { $dispatchRunId } else { $null }
        dispatchTarget = _Trace_Str -Obj $QueueEntry -Name 'dispatchTarget'
        queued         = ($null -ne $QueueEntry)
    }
    if ($null -ne $QueueEntry) {
        $stages.Add((_Trace_NewStage -Key 'dispatch' -Status 'complete' `
                    -At (_Trace_Str -Obj $QueueEntry -Name 'queuedAt') `
                    -Detail ("Approved and enqueued for the operator runner as run {0}." -f $dispatchRunId) `
                    -Artifact 'output/roadmap-task-queue.jsonl' -Evidence $dispatchEvidence))
    } elseif ($packetStatus -eq 'rejected') {
        $stages.Add((_Trace_NewStage -Key 'dispatch' -Status 'blocked' `
                    -At (_Trace_Str -Obj $PackagedItem -Name 'updatedAt') `
                    -Detail 'The operator rejected this packet, so it was never dispatched.' `
                    -Artifact 'output/automation/packaged-items.jsonl' -Evidence $dispatchEvidence))
    } elseif ($packetStatus -eq 'approved' -or $packetStatus -eq 'dispatched' -or (_Trace_HasText $dispatchRunId)) {
        $dispatchGapDetail = if (_Trace_HasText $packetStatus) {
            "The packet is '{0}' but no queue entry exists for run {1}; nothing will pick this work up." -f $packetStatus, $dispatchRunId
        } else {
            "Run {0} has no queue entry, so how this work was dispatched is unrecorded." -f $dispatchRunId
        }
        $stages.Add((_Trace_NewStage -Key 'dispatch' -Status 'missing' `
                    -Detail $dispatchGapDetail `
                    -Artifact 'output/roadmap-task-queue.jsonl' -Evidence $dispatchEvidence))
    } elseif ($packetStatus -eq 'pending-approval') {
        $stages.Add((_Trace_NewStage -Key 'dispatch' -Status 'active' `
                    -At (_Trace_Str -Obj $PackagedItem -Name 'updatedAt') `
                    -Detail 'Waiting at the approval gate. Dispatch happens only on an explicit operator approval.' `
                    -Artifact 'output/automation/packaged-items.jsonl' -Evidence $dispatchEvidence))
    } else {
        $stages.Add((_Trace_NewStage -Key 'dispatch' -Status 'pending' `
                    -Detail 'Not dispatched.' -Artifact 'output/roadmap-task-queue.jsonl' -Evidence $dispatchEvidence))
    }
    $dispatchComplete = ([string]$stages[$stages.Count - 1].status -eq 'complete')

    # ---- 4. agent run ---------------------------------------------------
    $runStatus = _Trace_Str -Obj $RunSummary -Name 'status'
    $agentStatus = _Trace_Str -Obj $AgentRun -Name 'status'
    $prUrl = _Trace_Str -Obj $PrRecord -Name 'prUrl'
    if (-not (_Trace_HasText $prUrl)) { $prUrl = _Trace_Str -Obj $AgentRun -Name 'prUrl' }
    if (-not (_Trace_HasText $prUrl)) { $prUrl = _Trace_Str -Obj $MergeReadiness -Name 'prUrl' }

    $agentEvidence = [ordered]@{
        runnerStatus  = if (_Trace_HasText $runStatus) { $runStatus } else { $null }
        agentRunId    = if (_Trace_HasText $agentRunId) { $agentRunId } else { $null }
        agentStatus   = if (_Trace_HasText $agentStatus) { $agentStatus } else { $null }
        branch        = if (_Trace_HasText $branch) { $branch } else { $null }
        commitSha     = _Trace_Str -Obj $RunSummary -Name 'commitSha'
        filesChanged  = _Trace_GetField -Obj $RunSummary -Name 'filesChanged' -Default $null
        verifyResult  = _Trace_Str -Obj $RunSummary -Name 'verifyResult'
        agentTaskUrl  = _Trace_Str -Obj $RunSummary -Name 'agentTaskUrl'
        prUrl         = if (_Trace_HasText $prUrl) { $prUrl } else { $null }
        error         = _Trace_Str -Obj $RunSummary -Name 'error'
    }
    $agentArtifact = if (_Trace_HasText $dispatchRunId) { "output/roadmap-task-history/runs/$dispatchRunId.summary.json" } else { 'output/roadmap-task-history/runs' }
    $effectiveRunStatus = if (_Trace_HasText $runStatus) { $runStatus } else { $agentStatus }

    switch ($effectiveRunStatus) {
        'awaiting-review' {
            $stages.Add((_Trace_NewStage -Key 'agentRun' -Status 'complete' `
                        -At (_Trace_Str -Obj $RunSummary -Name 'runnerCompletedAt') `
                        -Detail ("The runner finished on branch '{0}'; the work is committed and awaiting review." -f $branch) `
                        -Artifact $agentArtifact -Evidence $agentEvidence))
        }
        'dispatched' {
            $stages.Add((_Trace_NewStage -Key 'agentRun' -Status 'active' `
                        -At (_Trace_Str -Obj $RunSummary -Name 'runnerCompletedAt') `
                        -Detail 'Handed to the cloud coding agent; the agent has not reported back yet.' `
                        -Artifact $agentArtifact -Evidence $agentEvidence))
        }
        'completed' {
            $stages.Add((_Trace_NewStage -Key 'agentRun' -Status 'complete' `
                        -At (_Trace_Str -Obj $AgentRun -Name 'updatedAt') `
                        -Detail 'The agent run completed.' -Artifact $agentArtifact -Evidence $agentEvidence))
        }
        'running' {
            $stages.Add((_Trace_NewStage -Key 'agentRun' -Status 'active' `
                        -At (_Trace_Str -Obj $RunSummary -Name 'runnerStartedAt') `
                        -Detail 'The operator runner claimed this task and is executing it.' `
                        -Artifact $agentArtifact -Evidence $agentEvidence))
        }
        'active' {
            $stages.Add((_Trace_NewStage -Key 'agentRun' -Status 'active' `
                        -At (_Trace_Str -Obj $AgentRun -Name 'updatedAt') `
                        -Detail 'The agent run is active.' -Artifact $agentArtifact -Evidence $agentEvidence))
        }
        'queued' {
            $stages.Add((_Trace_NewStage -Key 'agentRun' -Status 'pending' `
                        -Detail 'Queued. No runner has claimed this task yet — check that the operator runner is present.' `
                        -Artifact $agentArtifact -Evidence $agentEvidence))
        }
        'failed' {
            $stages.Add((_Trace_NewStage -Key 'agentRun' -Status 'failed' `
                        -At (_Trace_Str -Obj $RunSummary -Name 'runnerCompletedAt') `
                        -Detail ("The run failed: {0}" -f (_Trace_Str -Obj $RunSummary -Name 'error' -Default 'no error text was recorded')) `
                        -Artifact $agentArtifact -Evidence $agentEvidence))
        }
        'blocked' {
            $stages.Add((_Trace_NewStage -Key 'agentRun' -Status 'blocked' `
                        -At (_Trace_Str -Obj $RunSummary -Name 'runnerBlockedAt') `
                        -Detail ("The runner refused this task without claiming it: {0}" -f (_Trace_Str -Obj $RunSummary -Name 'error' -Default 'no reason was recorded')) `
                        -Artifact $agentArtifact -Evidence $agentEvidence))
        }
        default {
            if ($dispatchComplete) {
                $stages.Add((_Trace_NewStage -Key 'agentRun' -Status 'missing' `
                            -Detail 'The item was dispatched but no run summary exists, so nothing can report on it.' `
                            -Artifact $agentArtifact -Evidence $agentEvidence))
            } else {
                $stages.Add((_Trace_NewStage -Key 'agentRun' -Status 'pending' `
                            -Detail 'No agent run yet.' -Artifact $agentArtifact -Evidence $agentEvidence))
            }
        }
    }
    $agentRunComplete = ([string]$stages[$stages.Count - 1].status -eq 'complete')

    # ---- 5. Actions result ----------------------------------------------
    # Actions only exist once a PR exists, so a missing Actions state before the
    # PR is `pending`, and only after it is a gap.
    $actions = _Trace_GetField -Obj $AgentRun -Name 'actions' -Default $null
    if ($null -eq $actions) {
        $mrEvidence = _Trace_GetField -Obj $MergeReadiness -Name 'evidence' -Default $null
        if ($null -ne $mrEvidence -and (_Trace_HasText (_Trace_Str -Obj $mrEvidence -Name 'actionsStatus'))) {
            $actions = [pscustomobject]@{
                status       = _Trace_Str -Obj $mrEvidence -Name 'actionsStatus'
                conclusion   = _Trace_Str -Obj $mrEvidence -Name 'actionsConclusion'
                workflowName = _Trace_Str -Obj $mrEvidence -Name 'actionsWorkflowName'
            }
        }
    }
    $actionsStatus = _Trace_Str -Obj $actions -Name 'status'
    $actionsConclusion = _Trace_Str -Obj $actions -Name 'conclusion'
    $actionsEvidence = [ordered]@{
        status       = if (_Trace_HasText $actionsStatus) { $actionsStatus } else { $null }
        conclusion   = if (_Trace_HasText $actionsConclusion) { $actionsConclusion } else { $null }
        workflowName = _Trace_Str -Obj $actions -Name 'workflowName'
        prUrl        = if (_Trace_HasText $prUrl) { $prUrl } else { $null }
        prNumber     = _Trace_GetField -Obj $PrRecord -Name 'prNumber' -Default (_Trace_GetField -Obj $MergeReadiness -Name 'prNumber' -Default $null)
    }
    $actionsArtifact = if (_Trace_HasText $agentRunId) { "output/agent-runs/runs/$agentRunId.json" } else { 'output/agent-runs/runs' }

    if (-not (_Trace_HasText $actionsStatus)) {
        if (_Trace_HasText $prUrl) {
            $stages.Add((_Trace_NewStage -Key 'actions' -Status 'missing' `
                        -Detail ("PR {0} exists but no Actions state has been observed for it; refresh the run from GitHub to capture validation evidence." -f $prUrl) `
                        -Artifact $actionsArtifact -Evidence $actionsEvidence))
        } elseif ($agentRunComplete) {
            $stages.Add((_Trace_NewStage -Key 'actions' -Status 'pending' `
                        -Detail 'The branch is ready but no pull request has been opened, so there is nothing for Actions to validate yet.' `
                        -Artifact $actionsArtifact -Evidence $actionsEvidence))
        } else {
            $stages.Add((_Trace_NewStage -Key 'actions' -Status 'pending' `
                        -Detail 'No validation run yet.' -Artifact $actionsArtifact -Evidence $actionsEvidence))
        }
    } elseif ($actionsStatus -ne 'completed') {
        $stages.Add((_Trace_NewStage -Key 'actions' -Status 'active' `
                    -Detail ("The latest Actions run is '{0}'; validation has not finished." -f $actionsStatus) `
                    -Artifact $actionsArtifact -Evidence $actionsEvidence))
    } elseif ($actionsConclusion -ne 'success') {
        $stages.Add((_Trace_NewStage -Key 'actions' -Status 'failed' `
                    -Detail ("The latest Actions conclusion is '{0}'; this work cannot merge." -f $actionsConclusion) `
                    -Artifact $actionsArtifact -Evidence $actionsEvidence))
    } else {
        $stages.Add((_Trace_NewStage -Key 'actions' -Status 'complete' `
                    -Detail ("Validation succeeded on {0}." -f $(if (_Trace_HasText (_Trace_Str -Obj $actions -Name 'workflowName')) { _Trace_Str -Obj $actions -Name 'workflowName' } else { 'the latest workflow run' })) `
                    -Artifact $actionsArtifact -Evidence $actionsEvidence))
    }
    $actionsComplete = ([string]$stages[$stages.Count - 1].status -eq 'complete')

    # ---- 6. merge readiness ---------------------------------------------
    $mrArtifact = if (_Trace_HasText $repoId) { "output/merge-readiness/$repoId.json" } else { 'output/merge-readiness' }
    if ($null -ne $MergeReadiness) {
        $blockers = @(_Trace_GetField -Obj $MergeReadiness -Name 'blockers' -Default @())
        $blockerCodes = @($blockers | ForEach-Object { _Trace_Str -Obj $_ -Name 'code' } | Where-Object { _Trace_HasText $_ })
        $mrEvid = _Trace_GetField -Obj $MergeReadiness -Name 'evidence' -Default $null
        $prState = _Trace_Str -Obj $mrEvid -Name 'prState'
        $mrEvidence2 = [ordered]@{
            ready        = [bool](_Trace_GetField -Obj $MergeReadiness -Name 'ready' -Default $false)
            blockerCodes = $blockerCodes
            prState      = if (_Trace_HasText $prState) { $prState } else { $null }
            prUrl        = if (_Trace_HasText $prUrl) { $prUrl } else { $null }
            evaluatedAt  = _Trace_Str -Obj $MergeReadiness -Name 'evaluatedAt'
        }
        if ([bool](_Trace_GetField -Obj $MergeReadiness -Name 'ready' -Default $false)) {
            $stages.Add((_Trace_NewStage -Key 'mergeReadiness' -Status 'complete' `
                        -At (_Trace_Str -Obj $MergeReadiness -Name 'evaluatedAt') `
                        -Detail 'Merge readiness passed with no blockers. Merging stays an explicit operator action.' `
                        -Artifact $mrArtifact -Evidence $mrEvidence2))
        } elseif ($prState -eq 'merged') {
            # `pr-already-merged` is a merge-readiness blocker precisely because
            # there is nothing left to gate — for the trace that is the success
            # state, not a failure.
            $stages.Add((_Trace_NewStage -Key 'mergeReadiness' -Status 'complete' `
                        -At (_Trace_Str -Obj $MergeReadiness -Name 'evaluatedAt') `
                        -Detail 'The pull request is merged; merge readiness has nothing left to gate.' `
                        -Artifact $mrArtifact -Evidence $mrEvidence2))
        } else {
            $stages.Add((_Trace_NewStage -Key 'mergeReadiness' -Status 'blocked' `
                        -At (_Trace_Str -Obj $MergeReadiness -Name 'evaluatedAt') `
                        -Detail ("Merge is blocked by {0} check(s): {1}." -f $blockerCodes.Count, ($blockerCodes -join ', ')) `
                        -Artifact $mrArtifact -Evidence $mrEvidence2))
        }
    } elseif ($actionsComplete) {
        $stages.Add((_Trace_NewStage -Key 'mergeReadiness' -Status 'missing' `
                    -Detail 'Validation passed but merge readiness has never been evaluated for this repo. Run POST /api/merge-readiness/{repoId}/evaluate.' `
                    -Artifact $mrArtifact))
    } else {
        $stages.Add((_Trace_NewStage -Key 'mergeReadiness' -Status 'pending' `
                    -Detail 'Merge readiness has not been evaluated.' -Artifact $mrArtifact))
    }

    # ---- 7. roadmap write-back -------------------------------------------
    $mergedState = ''
    if ($null -ne $MergeReadiness) {
        $mergedState = _Trace_Str -Obj (_Trace_GetField -Obj $MergeReadiness -Name 'evidence' -Default $null) -Name 'prState'
    }
    $writeBackEvidence = [ordered]@{
        applied     = [bool](_Trace_GetField -Obj $WriteBack -Name 'applied' -Default $false)
        roadmapPath = if (_Trace_HasText $roadmapPath) { $roadmapPath } else { $null }
        itemText    = if (_Trace_HasText $itemText) { $itemText } else { $null }
        markedCount = _Trace_GetField -Obj $WriteBack -Name 'markedCount' -Default $null
        appliedBy   = _Trace_Str -Obj $WriteBack -Name 'actor'
    }
    if ($null -ne $WriteBack -and [bool](_Trace_GetField -Obj $WriteBack -Name 'applied' -Default $false)) {
        $stages.Add((_Trace_NewStage -Key 'writeBack' -Status 'complete' `
                    -At (_Trace_Str -Obj $WriteBack -Name 'recordedAt') `
                    -Detail ("The managed repo's roadmap was updated to mark this item complete ({0} line(s))." -f (_Trace_GetField -Obj $WriteBack -Name 'markedCount' -Default 0)) `
                    -Artifact 'output/roadmap-writeback/history.jsonl' -Evidence $writeBackEvidence))
    } elseif ($null -ne $WriteBack) {
        $stages.Add((_Trace_NewStage -Key 'writeBack' -Status 'active' `
                    -At (_Trace_Str -Obj $WriteBack -Name 'recordedAt') `
                    -Detail 'A completion edit has been previewed and is waiting for the operator to apply it.' `
                    -Artifact 'output/roadmap-writeback/history.jsonl' -Evidence $writeBackEvidence))
    } elseif ($mergedState -eq 'merged') {
        $stages.Add((_Trace_NewStage -Key 'writeBack' -Status 'missing' `
                    -Detail 'The pull request is merged but the managed repo''s roadmap still shows this item as open.' `
                    -Artifact 'output/roadmap-writeback/history.jsonl' -Evidence $writeBackEvidence))
    } else {
        $stages.Add((_Trace_NewStage -Key 'writeBack' -Status 'pending' `
                    -Detail 'Write-back needs merge evidence; nothing is marked complete before the pull request merges.' `
                    -Artifact 'output/roadmap-writeback/history.jsonl' -Evidence $writeBackEvidence))
    }

    # ---- roll-up ---------------------------------------------------------
    $stageArray = @($stages.ToArray())
    $gaps = @($stageArray | Where-Object { [string]$_.status -eq 'missing' } | ForEach-Object { [string]$_.stage })
    $failed = @($stageArray | Where-Object { [string]$_.status -eq 'failed' })
    $blocked = @($stageArray | Where-Object { [string]$_.status -eq 'blocked' })
    $completeCount = @($stageArray | Where-Object { [string]$_.status -eq 'complete' }).Count
    $current = @($stageArray | Where-Object { [string]$_.status -ne 'complete' } | Select-Object -First 1)

    $overall = if ($failed.Count -gt 0) { 'failed' }
    elseif ($blocked.Count -gt 0) { 'blocked' }
    elseif ($completeCount -eq $stageArray.Count) { 'complete' }
    else { 'active' }

    if ([string]::IsNullOrWhiteSpace($JoinedAt)) { $JoinedAt = (Get-Date).ToUniversalTime().ToString('o') }

    return [pscustomobject]@{
        schemaVersion      = $script:WorkItemTraceSchemaVersion
        traceId            = $traceId
        requestedId        = if (_Trace_HasText $RequestedId) { $RequestedId } else { $null }
        status             = $overall
        currentStage       = if ($current.Count -gt 0) { [string]$current[0].stage } else { $null }
        completeStageCount = $completeCount
        stageCount         = $stageArray.Count
        hasGaps            = ($gaps.Count -gt 0)
        gaps               = $gaps
        identity           = [ordered]@{
            packetId       = if (_Trace_HasText $packetId) { $packetId } else { $null }
            packagingRunId = if (_Trace_HasText $packagingRunId) { $packagingRunId } else { $null }
            dispatchRunId  = if (_Trace_HasText $dispatchRunId) { $dispatchRunId } else { $null }
            agentRunId     = if (_Trace_HasText $agentRunId) { $agentRunId } else { $null }
            repoName       = if (_Trace_HasText $repoName) { $repoName } else { $null }
            repoId         = if (_Trace_HasText $repoId) { $repoId } else { $null }
            itemText       = if (_Trace_HasText $itemText) { $itemText } else { $null }
            branch         = if (_Trace_HasText $branch) { $branch } else { $null }
            roadmapPath    = if (_Trace_HasText $roadmapPath) { $roadmapPath } else { $null }
            prUrl          = if (_Trace_HasText $prUrl) { $prUrl } else { $null }
        }
        stages             = $stageArray
        joinedAt           = $JoinedAt
    }
}

<#
.SYNOPSIS
    Resolve any of the chain's identifiers to the one work item it belongs to.
.DESCRIPTION
    The chain mints a new id at nearly every stage, and an operator holding one
    of them should not have to know which. This accepts a packetId, a packaging
    runId, a dispatch runId or an agent-run id and returns the same identity
    either way — that is what makes "a single runId resolves to every stage
    artifact through one route" true rather than aspirational.
#>
function Resolve-WorkItemTraceIdentity {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter()][object[]]$PackagedItems = @(),
        [Parameter()][object[]]$QueueEntries = @(),
        [Parameter()][object[]]$AgentRuns = @()
    )

    $packagedItem = $null
    $queueEntry = $null
    $agentRun = $null

    foreach ($item in @($PackagedItems)) {
        if ((_Trace_Str -Obj $item -Name 'packetId') -eq $Id -or
            (_Trace_Str -Obj $item -Name 'dispatchRunId') -eq $Id -or
            (_Trace_Str -Obj $item -Name 'runId') -eq $Id) {
            $packagedItem = $item
            break
        }
    }

    # An agent-run id resolves through its dispatchRunId, so a caller holding
    # only the agent's own id still lands on the same work item.
    foreach ($run in @($AgentRuns)) {
        if ((_Trace_Str -Obj $run -Name 'runId') -eq $Id) { $agentRun = $run; break }
    }
    $dispatchRunId = if ($null -ne $packagedItem) { _Trace_Str -Obj $packagedItem -Name 'dispatchRunId' } else { '' }
    if (-not (_Trace_HasText $dispatchRunId) -and $null -ne $agentRun) {
        $dispatchRunId = _Trace_Str -Obj $agentRun -Name 'dispatchRunId'
    }
    if (-not (_Trace_HasText $dispatchRunId)) { $dispatchRunId = $Id }

    foreach ($entry in @($QueueEntries)) {
        if ((_Trace_Str -Obj $entry -Name 'runId') -eq $dispatchRunId) { $queueEntry = $entry }
    }

    # Fall back the other way: a dispatch runId with no packet of its own still
    # finds its packet if one recorded the same dispatch.
    if ($null -eq $packagedItem) {
        foreach ($item in @($PackagedItems)) {
            if ((_Trace_Str -Obj $item -Name 'dispatchRunId') -eq $dispatchRunId) { $packagedItem = $item; break }
        }
    }
    if ($null -eq $agentRun) {
        foreach ($run in @($AgentRuns)) {
            if ((_Trace_Str -Obj $run -Name 'dispatchRunId') -eq $dispatchRunId) { $agentRun = $run; break }
        }
    }

    return [pscustomobject]@{
        found         = ($null -ne $packagedItem -or $null -ne $queueEntry -or $null -ne $agentRun)
        requestedId   = $Id
        dispatchRunId = $dispatchRunId
        packagedItem  = $packagedItem
        queueEntry    = $queueEntry
        agentRun      = $agentRun
    }
}

<#
.SYNOPSIS
    Select the submit-PR history record that belongs to this work item.
.DESCRIPTION
    Pure. The repair history is the only ledger that records the PR, and it
    shares no run id with the dispatch chain — branch is the one identifier
    both carry, so that is the join. Repo name alone is not enough: a repo with
    several repairs would attribute another item's PR to this one.
#>
function Select-WorkItemTracePrRecord {
    [CmdletBinding()]
    param(
        [Parameter()][object[]]$RepairHistory = @(),
        [Parameter()][AllowEmptyString()][string]$Branch = '',
        [Parameter()][AllowEmptyString()][string]$RepoName = ''
    )

    if (-not (_Trace_HasText $Branch)) { return $null }
    $candidates = @(@($RepairHistory) | Where-Object {
            (_Trace_Str -Obj $_ -Name 'event') -eq 'submit-pr' -and
            (_Trace_Str -Obj $_ -Name 'branch') -eq $Branch -and
            (_Trace_HasText (_Trace_Str -Obj $_ -Name 'prUrl'))
        })
    if ($candidates.Count -eq 0) { return $null }
    if (_Trace_HasText $RepoName) {
        $sameRepo = @($candidates | Where-Object { (_Trace_Str -Obj $_ -Name 'repoName') -eq $RepoName })
        if ($sameRepo.Count -gt 0) { $candidates = $sameRepo }
    }
    return $candidates[$candidates.Count - 1]
}

<#
.SYNOPSIS
    Read every ledger and return the joined trace for one work item.
.DESCRIPTION
    Thin I/O wrapper — all the decision logic lives in Join-WorkItemTrace.
    Returns $null when the id matches nothing anywhere in the chain.
#>
function Get-WorkItemTrace {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)][string]$WorkspaceRoot,
        [Parameter(Mandatory = $true)][string]$Id
    )

    if ([string]::IsNullOrWhiteSpace($Id)) { return $null }

    $packagedItems = @()
    if (Get-Command -Name 'Get-PackagedItemQueue' -ErrorAction SilentlyContinue) {
        try { $packagedItems = @(Get-PackagedItemQueue -WorkspaceRoot $WorkspaceRoot -Limit 0) } catch { $packagedItems = @() }
    }

    $queueEntries = @(_Trace_ReadJsonl -Path (Join-Path $WorkspaceRoot $script:WorkItemTraceQueueRelPath))

    $agentRunsDir = Join-Path $WorkspaceRoot $script:WorkItemTraceAgentRunsRelDir
    $agentRuns = @(
        @(Get-ChildItem -LiteralPath $agentRunsDir -Filter '*.json' -File -ErrorAction SilentlyContinue) |
            ForEach-Object { _Trace_ReadJson -Path $_.FullName } | Where-Object { $null -ne $_ }
    )

    $identity = Resolve-WorkItemTraceIdentity -Id $Id -PackagedItems $packagedItems -QueueEntries $queueEntries -AgentRuns $agentRuns
    if (-not $identity.found) { return $null }

    $runSummary = $null
    if (_Trace_HasText $identity.dispatchRunId) {
        $runSummary = _Trace_ReadJson -Path (Join-Path (Join-Path $WorkspaceRoot $script:WorkItemTraceRunsRelDir) ("{0}.summary.json" -f $identity.dispatchRunId))
    }

    $packet = _Trace_GetField -Obj $identity.packagedItem -Name 'packet' -Default $null
    $branch = _Trace_Str -Obj $runSummary -Name 'branch'
    if (-not (_Trace_HasText $branch)) { $branch = _Trace_Str -Obj $identity.queueEntry -Name 'branch' }
    if (-not (_Trace_HasText $branch)) { $branch = _Trace_Str -Obj $packet -Name 'branch' }
    if (-not (_Trace_HasText $branch)) { $branch = _Trace_Str -Obj $identity.agentRun -Name 'branch' }

    $repoName = _Trace_Str -Obj $packet -Name 'repoName'
    if (-not (_Trace_HasText $repoName)) { $repoName = _Trace_Str -Obj $identity.packagedItem -Name 'repoName' }
    if (-not (_Trace_HasText $repoName)) { $repoName = _Trace_Str -Obj $runSummary -Name 'repository' }

    $prRecord = Select-WorkItemTracePrRecord `
        -RepairHistory (_Trace_ReadJsonl -Path (Join-Path $WorkspaceRoot $script:WorkItemTraceRepairHistoryRelPath)) `
        -Branch $branch -RepoName $repoName

    $repoId = _Trace_Str -Obj $packet -Name 'repoId'
    if (-not (_Trace_HasText $repoId)) { $repoId = _Trace_Str -Obj $identity.agentRun -Name 'repoId' }
    $mergeReadiness = $null
    if ((_Trace_HasText $repoId) -and (Get-Command -Name 'Get-MergeReadinessSnapshot' -ErrorAction SilentlyContinue)) {
        try { $mergeReadiness = Get-MergeReadinessSnapshot -WorkspaceRoot $WorkspaceRoot -RepoId $repoId } catch { $mergeReadiness = $null }
    }

    $writeBack = $null
    $writeBackRecords = @(_Trace_ReadJsonl -Path (Join-Path $WorkspaceRoot $script:WorkItemTraceWriteBackRelPath))
    if ($writeBackRecords.Count -gt 0) {
        $keys = @(@($identity.dispatchRunId, (_Trace_Str -Obj $identity.packagedItem -Name 'packetId')) | Where-Object { _Trace_HasText $_ })
        $writeBackMatches = @($writeBackRecords | Where-Object {
                $recordRunId = _Trace_Str -Obj $_ -Name 'runId'
                $recordPacketId = _Trace_Str -Obj $_ -Name 'packetId'
                ($keys -contains $recordRunId) -or ($keys -contains $recordPacketId)
            })
        # Applied beats previewed regardless of order: a later preview must not
        # make an already-applied write-back read as still pending.
        $applied = @($writeBackMatches | Where-Object { [bool](_Trace_GetField -Obj $_ -Name 'applied' -Default $false) })
        if ($applied.Count -gt 0) { $writeBack = $applied[$applied.Count - 1] }
        elseif ($writeBackMatches.Count -gt 0) { $writeBack = $writeBackMatches[$writeBackMatches.Count - 1] }
    }

    return (Join-WorkItemTrace -PackagedItem $identity.packagedItem -QueueEntry $identity.queueEntry `
            -RunSummary $runSummary -AgentRun $identity.agentRun -PrRecord $prRecord `
            -MergeReadiness $mergeReadiness -WriteBack $writeBack -RequestedId $Id)
}
