<#
.SYNOPSIS
    Release 3.1 — the per-work-item trace that joins the north-star loop.

.DESCRIPTION
    Every stage of the loop already writes its own evidence, and nothing joined
    them: answering "what happened to this item?" meant opening four ledgers by
    hand and matching ids across them. This module is that join.

      rank / prompt      output/automation/packaged-items.jsonl  (the packet)
      dispatch           output/roadmap-task-queue.jsonl +
                         output/roadmap-task-history/runs/<runId>.summary.json
      agent run          output/agent-runs/runs/<runId>.json
      actions            the same run record's observed Actions state
      merge readiness    output/merge-readiness/<repoId>.json
      write-back         output/roadmap-writeback.jsonl

    Two ideas carry the design:

    1. **One key, any key.** An operator holds whichever id the surface they
       came from showed them — a packet id, the packaging run id, the dispatch
       run id, or the agent run id. All four resolve to the same trace, because
       a trace view you can only open if you already know the right id is not a
       trace view.

    2. **Absence is a finding.** A stage that never ran is reported as
       `present=false` with the reason it is missing and the action that would
       advance it, never omitted. A trace that silently drops its empty stages
       reads as "the loop finished" when the loop actually stalled.

    Join-WorkItemTrace is pure — it takes the already-read artifacts and
    returns the trace — so every stage combination is testable offline without
    a workspace. Get-WorkItemTrace is the one impure entry point.

.NOTES
    Dot-source after Automation.RoadmapPackaging.ps1, AgentRuns.ps1 and
    MergeReadiness.ps1:
        . (Join-Path $executionModuleRoot 'Execution.Trace.ps1')
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:WorkItemTraceVersion       = '1.0'
$script:WorkItemTraceWriteBackPath = 'output/roadmap-writeback.jsonl'

# The loop, in order. The trace always reports all seven; what varies is which
# ones are present.
$script:WorkItemTraceStageOrder = @(
    'rank'
    'prompt'
    'dispatch'
    'agent-run'
    'actions'
    'merge-readiness'
    'write-back'
)

function _Trace_Field {
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
    param([object]$Obj, [string]$Name)
    return [string](_Trace_Field -Obj $Obj -Name $Name -Default '')
}

function _Trace_ReadJsonl {
    param([string]$Path)
    $records = [System.Collections.Generic.List[object]]::new()
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $records.ToArray() }
    foreach ($line in @(Get-Content -LiteralPath $Path -Encoding UTF8 -ErrorAction SilentlyContinue)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        # A torn final line (append-only files are written under a live process)
        # skips rather than failing the whole read: one unparseable line must not
        # cost an operator the rest of the trace.
        try { $records.Add((ConvertFrom-Json -InputObject $line)) | Out-Null }
        catch { Write-Verbose ("Skipping unparseable JSONL line in '{0}': {1}" -f $Path, $_.Exception.Message) }
    }
    return $records.ToArray()
}

function _Trace_ReadJson {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    try { return (ConvertFrom-Json -InputObject (Get-Content -LiteralPath $Path -Raw -Encoding UTF8)) } catch { return $null }
}

function Get-WorkItemWriteBackLedgerPath {
    <#
    .SYNOPSIS
        The append-only write-back ledger path. One file, workspace-relative.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory = $true)][string]$WorkspaceRoot)
    return (Join-Path $WorkspaceRoot ($script:WorkItemTraceWriteBackPath -replace '/', [System.IO.Path]::DirectorySeparatorChar))
}

function Write-WorkItemWriteBackRecord {
    <#
    .SYNOPSIS
        Append one write-back decision — proposed, applied, or refused.
    .DESCRIPTION
        A refusal is recorded as deliberately as an application. The whole point
        of the evidence gate is that "we declined to mark this complete, and
        here is why" survives; a ledger that only kept successes would make the
        guardrail invisible the moment it worked.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)][string]$WorkspaceRoot,
        [Parameter(Mandatory = $true)][object]$Record
    )

    $decision = _Trace_Str -Obj $Record -Name 'decision'
    if ([string]::IsNullOrWhiteSpace($decision)) {
        throw 'Write-back record is missing decision; refusing to append an unattributable record.'
    }
    if ($decision -notin @('proposed', 'applied', 'refused')) {
        throw ("Write-back record carries unknown decision '{0}'; expected proposed, applied, or refused." -f $decision)
    }

    $path = Get-WorkItemWriteBackLedgerPath -WorkspaceRoot $WorkspaceRoot
    $dir = Split-Path -Path $path -Parent
    if (-not (Test-Path -LiteralPath $dir)) { $null = New-Item -ItemType Directory -Path $dir -Force }
    Add-Content -LiteralPath $path -Value ($Record | ConvertTo-Json -Depth 10 -Compress) -Encoding UTF8
    return $path
}

function Get-WorkItemWriteBackRecord {
    <#
    .SYNOPSIS
        Read write-back ledger records, optionally for one trace key.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory = $true)][string]$WorkspaceRoot,
        [Parameter()][AllowEmptyString()][string]$RunId = '',
        [Parameter()][AllowEmptyString()][string]$PacketId = ''
    )

    $all = @(_Trace_ReadJsonl -Path (Get-WorkItemWriteBackLedgerPath -WorkspaceRoot $WorkspaceRoot))
    if ([string]::IsNullOrWhiteSpace($RunId) -and [string]::IsNullOrWhiteSpace($PacketId)) { return $all }

    return @($all | Where-Object {
        (-not [string]::IsNullOrWhiteSpace($RunId) -and (
            (_Trace_Str -Obj $_ -Name 'runId') -eq $RunId -or
            (_Trace_Str -Obj $_ -Name 'dispatchRunId') -eq $RunId -or
            (_Trace_Str -Obj $_ -Name 'agentRunId') -eq $RunId)) -or
        (-not [string]::IsNullOrWhiteSpace($PacketId) -and (_Trace_Str -Obj $_ -Name 'packetId') -eq $PacketId)
    })
}

function Test-WorkItemTraceKeyMatch {
    <#
    .SYNOPSIS
        Pure — does this artifact carry the supplied trace key under any of its
        id fields?
    .DESCRIPTION
        Deliberately matches on ALL of a record's identity fields rather than
        guessing the key's kind from its shape. The dispatch run id and the
        agent run id have different formats today; a resolver that pattern-matched
        on format would silently stop resolving the day either format changed,
        and the failure would look like "that item has no trace" rather than
        "the resolver is broken".
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter()][object]$Record,
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter()][string[]]$Fields = @('packetId', 'runId', 'dispatchRunId', 'agentRunId')
    )

    if ($null -eq $Record -or [string]::IsNullOrWhiteSpace($Key)) { return $false }
    foreach ($field in $Fields) {
        if ((_Trace_Str -Obj $Record -Name $field) -eq $Key) { return $true }
    }
    return $false
}

function New-WorkItemTraceStage {
    <#
    .SYNOPSIS
        Pure — one stage row of a trace.
    .DESCRIPTION
        `nextAction` exists because a trace whose empty stage says only "not
        present" tells an operator what they already knew. Every absent stage
        names the thing that would advance it.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Pure object builder — it constructs a trace row and changes no state, so -WhatIf plumbing would describe an action that does not exist.')]
    param(
        [Parameter(Mandatory = $true)][string]$Stage,
        [Parameter()][bool]$Present = $false,
        [Parameter()][AllowEmptyString()][string]$At = '',
        [Parameter()][string[]]$Artifacts = @(),
        [Parameter()][AllowEmptyString()][string]$Summary = '',
        [Parameter()][AllowEmptyString()][string]$NextAction = '',
        [Parameter()][object]$Detail = $null
    )

    return [pscustomobject]@{
        stage      = $Stage
        present    = $Present
        at         = if ([string]::IsNullOrWhiteSpace($At)) { $null } else { $At }
        artifacts  = @($Artifacts)
        summary    = $Summary
        nextAction = $NextAction
        detail     = $Detail
    }
}

function Join-WorkItemTrace {
    <#
    .SYNOPSIS
        Pure — join the already-read stage artifacts into one ordered trace.
    .DESCRIPTION
        Takes what each stage wrote and returns the seven-stage trace plus the
        resolved identity keys. No disk, no network: every stage combination
        (including "nothing exists for this key") is testable offline.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)][string]$TraceKey,
        [Parameter()][object]$PackagedItem = $null,
        [Parameter()][object]$QueueEntry = $null,
        [Parameter()][object]$RunSummary = $null,
        [Parameter()][object]$AgentRun = $null,
        [Parameter()][object]$MergeReadiness = $null,
        [Parameter()][object[]]$WriteBackRecords = @()
    )

    $packet = _Trace_Field -Obj $PackagedItem -Name 'packet' -Default $null

    $packetId       = _Trace_Str -Obj $PackagedItem -Name 'packetId'
    $packagingRunId = _Trace_Str -Obj $PackagedItem -Name 'runId'
    $dispatchRunId  = _Trace_Str -Obj $PackagedItem -Name 'dispatchRunId'
    if ([string]::IsNullOrWhiteSpace($dispatchRunId)) { $dispatchRunId = _Trace_Str -Obj $QueueEntry -Name 'runId' }
    if ([string]::IsNullOrWhiteSpace($dispatchRunId)) { $dispatchRunId = _Trace_Str -Obj $RunSummary -Name 'runId' }
    if ([string]::IsNullOrWhiteSpace($dispatchRunId)) { $dispatchRunId = _Trace_Str -Obj $AgentRun -Name 'dispatchRunId' }

    $agentRunId = _Trace_Str -Obj $AgentRun -Name 'runId'

    $repoName = _Trace_Str -Obj $PackagedItem -Name 'repoName'
    if ([string]::IsNullOrWhiteSpace($repoName)) { $repoName = _Trace_Str -Obj $QueueEntry -Name 'repository' }
    if ([string]::IsNullOrWhiteSpace($repoName)) { $repoName = _Trace_Str -Obj $RunSummary -Name 'repository' }
    if ([string]::IsNullOrWhiteSpace($repoName)) { $repoName = _Trace_Str -Obj $AgentRun -Name 'repoName' }
    if ([string]::IsNullOrWhiteSpace($repoName)) { $repoName = _Trace_Str -Obj $MergeReadiness -Name 'repoName' }

    $repoId = _Trace_Str -Obj $AgentRun -Name 'repoId'
    if ([string]::IsNullOrWhiteSpace($repoId)) { $repoId = _Trace_Str -Obj $MergeReadiness -Name 'repoId' }
    if ([string]::IsNullOrWhiteSpace($repoId)) { $repoId = _Trace_Str -Obj $packet -Name 'repoId' }

    $itemText = _Trace_Str -Obj $PackagedItem -Name 'itemText'
    if ([string]::IsNullOrWhiteSpace($itemText)) { $itemText = _Trace_Str -Obj $packet -Name 'itemText' }
    if ([string]::IsNullOrWhiteSpace($itemText)) { $itemText = _Trace_Str -Obj $QueueEntry -Name 'selectedTask' }
    if ([string]::IsNullOrWhiteSpace($itemText)) { $itemText = _Trace_Str -Obj $RunSummary -Name 'selectedTask' }
    if ([string]::IsNullOrWhiteSpace($itemText)) { $itemText = _Trace_Str -Obj $AgentRun -Name 'selectedTaskText' }

    $stages = [System.Collections.Generic.List[object]]::new()

    # ── rank ────────────────────────────────────────────────────────────────
    if ($null -ne $packet) {
        $valueScore = [int](_Trace_Field -Obj $packet -Name 'valueScore' -Default 0)
        $valueTier  = _Trace_Str -Obj $packet -Name 'valueTier'
        $stages.Add((New-WorkItemTraceStage -Stage 'rank' -Present $true `
            -At (_Trace_Str -Obj $packet -Name 'createdAt') `
            -Artifacts @('output/automation/packaged-items.jsonl') `
            -Summary ("Ranked highest-value pending item for {0}: score {1} ({2})." -f $repoName, $valueScore, $valueTier) `
            -Detail ([pscustomobject]@{
                valueScore     = $valueScore
                valueTier      = $valueTier
                valueRationale = @(_Trace_Field -Obj $packet -Name 'valueRationale' -Default @())
                roadmapOrder   = [int](_Trace_Field -Obj $packet -Name 'roadmapOrder' -Default 0)
                itemSection    = _Trace_Str -Obj $packet -Name 'itemSection'
                itemText       = $itemText
            })))
    } else {
        $stages.Add((New-WorkItemTraceStage -Stage 'rank' -Present $false `
            -Summary 'No packaged item carries this key; the item was never ranked and packaged.' `
            -NextAction 'Run scheduled packaging (POST /api/automation/package-run) so the item is ranked into a packet.'))
    }

    # ── prompt ──────────────────────────────────────────────────────────────
    $prompt = _Trace_Str -Obj $packet -Name 'generatedPrompt'
    if (-not [string]::IsNullOrWhiteSpace($prompt)) {
        $stages.Add((New-WorkItemTraceStage -Stage 'prompt' -Present $true `
            -At (_Trace_Str -Obj $packet -Name 'createdAt') `
            -Artifacts @('output/automation/packaged-items.jsonl') `
            -Summary ("Task packet {0} carries a {1}-character prompt and a repair-PR plan on branch {2}." -f $packetId, $prompt.Length, (_Trace_Str -Obj $packet -Name 'branch')) `
            -Detail ([pscustomobject]@{
                packetId     = $packetId
                branch       = _Trace_Str -Obj $packet -Name 'branch'
                baseBranch   = _Trace_Str -Obj $packet -Name 'baseBranch'
                promptLength = $prompt.Length
                repairPlan   = _Trace_Field -Obj $packet -Name 'repairPlan' -Default $null
                status       = _Trace_Str -Obj $PackagedItem -Name 'status'
                history      = @(_Trace_Field -Obj $PackagedItem -Name 'history' -Default @())
            })))
    } else {
        $stages.Add((New-WorkItemTraceStage -Stage 'prompt' -Present $false `
            -Summary 'No generated prompt is recorded for this key.' `
            -NextAction 'Packaging generates the prompt with the packet; re-run packaging for this repo.'))
    }

    # ── dispatch ────────────────────────────────────────────────────────────
    if ($null -ne $QueueEntry -or $null -ne $RunSummary) {
        $runnerStatus = _Trace_Str -Obj $RunSummary -Name 'status'
        if ([string]::IsNullOrWhiteSpace($runnerStatus)) { $runnerStatus = _Trace_Str -Obj $QueueEntry -Name 'status' }
        $queuedAt = _Trace_Str -Obj $QueueEntry -Name 'queuedAt'
        if ([string]::IsNullOrWhiteSpace($queuedAt)) { $queuedAt = _Trace_Str -Obj $RunSummary -Name 'startedAt' }
        $stages.Add((New-WorkItemTraceStage -Stage 'dispatch' -Present $true `
            -At $queuedAt `
            -Artifacts @('output/roadmap-task-queue.jsonl', ("output/roadmap-task-history/runs/{0}.summary.json" -f $dispatchRunId)) `
            -Summary ("Dispatched to the operator runner as {0}; runner status '{1}'." -f $dispatchRunId, $runnerStatus) `
            -Detail ([pscustomobject]@{
                dispatchRunId  = $dispatchRunId
                dispatchTarget = _Trace_Str -Obj $QueueEntry -Name 'dispatchTarget'
                branch         = _Trace_Str -Obj $RunSummary -Name 'branch'
                runnerStatus   = $runnerStatus
                approvedBy     = _Trace_Str -Obj $RunSummary -Name 'approvedBy'
                commitSha      = _Trace_Str -Obj $RunSummary -Name 'commitSha'
                filesChanged   = _Trace_Field -Obj $RunSummary -Name 'filesChanged' -Default $null
                verifyResult   = _Trace_Str -Obj $RunSummary -Name 'verifyResult'
                runnerError    = _Trace_Str -Obj $RunSummary -Name 'error'
            })))
    } else {
        $packetStatus = _Trace_Str -Obj $PackagedItem -Name 'status'
        $dispatchNext = if ($packetStatus -eq 'pending-approval') {
            'Approve the packet (POST /api/automation/packages/approve) — dispatch happens only on an explicit approval.'
        } elseif ($packetStatus -eq 'rejected') {
            'This packet was rejected; nothing will dispatch. Package a different item.'
        } else {
            'Enqueue the approved packet for the operator runner.'
        }
        $stages.Add((New-WorkItemTraceStage -Stage 'dispatch' -Present $false `
            -Summary 'No queue entry or runner summary exists for this key; the item was never dispatched.' `
            -NextAction $dispatchNext))
    }

    # ── agent run ───────────────────────────────────────────────────────────
    if ($null -ne $AgentRun) {
        $stages.Add((New-WorkItemTraceStage -Stage 'agent-run' -Present $true `
            -At (_Trace_Str -Obj $AgentRun -Name 'createdAt') `
            -Artifacts @(("output/agent-runs/runs/{0}.json" -f $agentRunId), 'output/agent-runs/events.jsonl') `
            -Summary ("Agent run {0} via {1}: status '{2}'." -f $agentRunId, (_Trace_Str -Obj $AgentRun -Name 'providerTool'), (_Trace_Str -Obj $AgentRun -Name 'status')) `
            -Detail ([pscustomobject]@{
                agentRunId   = $agentRunId
                providerTool = _Trace_Str -Obj $AgentRun -Name 'providerTool'
                status       = _Trace_Str -Obj $AgentRun -Name 'status'
                outcome      = _Trace_Str -Obj $AgentRun -Name 'outcome'
                branch       = _Trace_Str -Obj $AgentRun -Name 'branch'
                baseBranch   = _Trace_Str -Obj $AgentRun -Name 'baseBranch'
                prUrl        = _Trace_Str -Obj $AgentRun -Name 'prUrl'
                prNumber     = _Trace_Field -Obj $AgentRun -Name 'prNumber' -Default $null
                prState      = _Trace_Str -Obj $AgentRun -Name 'prState'
                prMergedAt   = _Trace_Str -Obj $AgentRun -Name 'prMergedAt'
                prMergeCommitSha = _Trace_Str -Obj $AgentRun -Name 'prMergeCommitSha'
                updatedAt    = _Trace_Str -Obj $AgentRun -Name 'updatedAt'
            })))
    } else {
        $stages.Add((New-WorkItemTraceStage -Stage 'agent-run' -Present $false `
            -Summary 'No agent-run ledger record references this dispatch.' `
            -NextAction 'Start the operator runner (Invoke-RoadmapTaskRunner.ps1) so the queued task is claimed and executed.'))
    }

    # ── actions ─────────────────────────────────────────────────────────────
    $actions = _Trace_Field -Obj $AgentRun -Name 'actions' -Default $null
    $actionsStatus = _Trace_Str -Obj $actions -Name 'status'
    if (-not [string]::IsNullOrWhiteSpace($actionsStatus)) {
        $actionsConclusion = _Trace_Str -Obj $actions -Name 'conclusion'
        $stages.Add((New-WorkItemTraceStage -Stage 'actions' -Present $true `
            -At (_Trace_Str -Obj $AgentRun -Name 'updatedAt') `
            -Artifacts @(("output/agent-runs/runs/{0}.json" -f $agentRunId)) `
            -Summary ("Actions '{0}': status {1}, conclusion {2}." -f (_Trace_Str -Obj $actions -Name 'workflowName'), $actionsStatus, $(if ($actionsConclusion) { $actionsConclusion } else { 'none yet' })) `
            -Detail ([pscustomobject]@{
                status       = $actionsStatus
                conclusion   = $actionsConclusion
                workflowName = _Trace_Str -Obj $actions -Name 'workflowName'
                url          = _Trace_Str -Obj $actions -Name 'url'
            })))
    } else {
        $stages.Add((New-WorkItemTraceStage -Stage 'actions' -Present $false `
            -Summary 'No GitHub Actions state has been observed for this run.' `
            -NextAction 'Refresh the agent run from GitHub (POST /api/agent-runs/{runId}/refresh) to capture validation evidence.'))
    }

    # ── merge readiness ─────────────────────────────────────────────────────
    if ($null -ne $MergeReadiness) {
        $ready = [bool](_Trace_Field -Obj $MergeReadiness -Name 'ready' -Default $false)
        $blockers = @(_Trace_Field -Obj $MergeReadiness -Name 'blockers' -Default @())
        $stages.Add((New-WorkItemTraceStage -Stage 'merge-readiness' -Present $true `
            -At (_Trace_Str -Obj $MergeReadiness -Name 'evaluatedAt') `
            -Artifacts @(("output/merge-readiness/{0}.json" -f $repoId)) `
            -Summary $(if ($ready) { 'Merge readiness passes: every gate is green.' } else { ("Merge readiness blocked by {0} blocker(s): {1}." -f $blockers.Count, ((@($blockers | ForEach-Object { _Trace_Str -Obj $_ -Name 'code' })) -join ', ')) }) `
            -NextAction $(if ($ready) { 'Merge is an explicit operator action — merge the PR, then propose the roadmap write-back.' } else { 'Clear the named blockers, then re-evaluate merge readiness.' }) `
            -Detail ([pscustomobject]@{
                ready    = $ready
                blockers = $blockers
                evidence = _Trace_Field -Obj $MergeReadiness -Name 'evidence' -Default $null
                prUrl    = _Trace_Str -Obj $MergeReadiness -Name 'prUrl'
                prNumber = _Trace_Field -Obj $MergeReadiness -Name 'prNumber' -Default $null
            })))
    } else {
        $stages.Add((New-WorkItemTraceStage -Stage 'merge-readiness' -Present $false `
            -Summary 'This repo has no merge-readiness snapshot.' `
            -NextAction 'Evaluate merge readiness (POST /api/merge-readiness/{repoId}/evaluate).'))
    }

    # ── write-back ──────────────────────────────────────────────────────────
    $wb = @($WriteBackRecords)
    if ($wb.Count -gt 0) {
        $latest = $wb[-1]
        $decision = _Trace_Str -Obj $latest -Name 'decision'
        $stages.Add((New-WorkItemTraceStage -Stage 'write-back' -Present $true `
            -At (_Trace_Str -Obj $latest -Name 'recordedAt') `
            -Artifacts @($script:WorkItemTraceWriteBackPath) `
            -Summary ("Latest write-back decision: {0}{1}." -f $decision, $(if ((_Trace_Str -Obj $latest -Name 'reason')) { (" ({0})" -f (_Trace_Str -Obj $latest -Name 'reason')) } else { '' })) `
            -NextAction $(switch ($decision) {
                'proposed' { 'Review the proposed completion diff and apply it through the repair submit-PR route.' }
                'refused'  { 'The evidence gate refused this write-back; supply merge evidence or leave the item open.' }
                default    { '' }
            }) `
            -Detail ([pscustomobject]@{
                decision = $decision
                reason   = _Trace_Str -Obj $latest -Name 'reason'
                actor    = _Trace_Str -Obj $latest -Name 'actor'
                itemText = _Trace_Str -Obj $latest -Name 'itemText'
                prUrl    = _Trace_Str -Obj $latest -Name 'prUrl'
                mergedAt = _Trace_Str -Obj $latest -Name 'mergedAt'
                history  = $wb
            })))
    } else {
        $stages.Add((New-WorkItemTraceStage -Stage 'write-back' -Present $false `
            -Summary 'No roadmap write-back has been proposed, applied, or refused for this item.' `
            -NextAction 'Propose the completion edit (POST /api/roadmap/write-back/preview) once the PR is merged.'))
    }

    $stageArray = @($stages.ToArray())
    $presentStages = @($stageArray | Where-Object { $_.present })

    # The furthest stage reached, and the first gap after it. "Current stage" is
    # the last PRESENT one rather than the last non-empty index, so a trace with
    # a hole in the middle (merge readiness evaluated before Actions was ever
    # observed, say) still reports the gap instead of hiding it behind a later
    # success.
    $currentStage = if ($presentStages.Count -gt 0) { [string]$presentStages[-1].stage } else { '' }
    $firstGap = @($stageArray | Where-Object { -not $_.present } | Select-Object -First 1)
    $nextAction = if ($firstGap.Count -gt 0) { [string]$firstGap[0].nextAction } else { 'The loop is complete for this item.' }

    return [pscustomobject]@{
        traceVersion   = $script:WorkItemTraceVersion
        traceKey       = $TraceKey
        resolved       = ($presentStages.Count -gt 0)
        repoId         = if ([string]::IsNullOrWhiteSpace($repoId)) { $null } else { $repoId }
        repoName       = if ([string]::IsNullOrWhiteSpace($repoName)) { $null } else { $repoName }
        itemText       = if ([string]::IsNullOrWhiteSpace($itemText)) { $null } else { $itemText }
        keys           = [pscustomobject]@{
            packetId       = if ([string]::IsNullOrWhiteSpace($packetId)) { $null } else { $packetId }
            packagingRunId = if ([string]::IsNullOrWhiteSpace($packagingRunId)) { $null } else { $packagingRunId }
            dispatchRunId  = if ([string]::IsNullOrWhiteSpace($dispatchRunId)) { $null } else { $dispatchRunId }
            agentRunId     = if ([string]::IsNullOrWhiteSpace($agentRunId)) { $null } else { $agentRunId }
        }
        stageOrder     = @($script:WorkItemTraceStageOrder)
        stages         = $stageArray
        stageCount     = $stageArray.Count
        presentCount   = $presentStages.Count
        currentStage   = if ([string]::IsNullOrWhiteSpace($currentStage)) { $null } else { $currentStage }
        firstGapStage  = if ($firstGap.Count -gt 0) { [string]$firstGap[0].stage } else { $null }
        nextAction     = $nextAction
        evaluatedAt    = (Get-Date).ToUniversalTime().ToString('o')
    }
}

function Get-WorkItemTrace {
    <#
    .SYNOPSIS
        The one impure entry point — read every stage's artifact for a key and
        join them.
    .DESCRIPTION
        Accepts a packet id, a packaging run id, a dispatch run id, or an agent
        run id and resolves the same trace from any of them. Resolution walks
        both directions: an agent run id finds its dispatch (via the run
        record's dispatchRunId), and a packet id finds its agent run (via the
        packet's dispatchRunId).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)][string]$WorkspaceRoot,
        [Parameter(Mandatory = $true)][string]$Key
    )

    $key = $Key.Trim()

    # 1. The packet — by packetId, packaging runId, or dispatchRunId.
    $packagedItem = $null
    if (Get-Command -Name 'Get-PackagedItemQueue' -ErrorAction SilentlyContinue) {
        $packagedItem = @(Get-PackagedItemQueue -WorkspaceRoot $WorkspaceRoot -Limit 0 |
            Where-Object { Test-WorkItemTraceKeyMatch -Record $_ -Key $key }) | Select-Object -First 1
    }

    $dispatchRunId = if ($null -ne $packagedItem) { _Trace_Str -Obj $packagedItem -Name 'dispatchRunId' } else { '' }

    # 2. The agent run — by its own runId, or by the dispatch it belongs to.
    $agentRun = $null
    $agentRunsDir = Join-Path $WorkspaceRoot 'output\agent-runs\runs'
    if (Test-Path -LiteralPath $agentRunsDir -PathType Container) {
        $direct = Join-Path $agentRunsDir ("{0}.json" -f ($key -replace '[\\/:*?"<>|]', '_'))
        $agentRun = _Trace_ReadJson -Path $direct
        if ($null -eq $agentRun) {
            $wanted = if (-not [string]::IsNullOrWhiteSpace($dispatchRunId)) { $dispatchRunId } else { $key }
            foreach ($file in @(Get-ChildItem -LiteralPath $agentRunsDir -Filter '*.json' -File -ErrorAction SilentlyContinue)) {
                $candidate = _Trace_ReadJson -Path $file.FullName
                if ($null -eq $candidate) { continue }
                if ((_Trace_Str -Obj $candidate -Name 'dispatchRunId') -eq $wanted) { $agentRun = $candidate; break }
            }
        }
    }

    # An agent run reached by its own id still knows which dispatch produced it.
    if ([string]::IsNullOrWhiteSpace($dispatchRunId) -and $null -ne $agentRun) {
        $dispatchRunId = _Trace_Str -Obj $agentRun -Name 'dispatchRunId'
    }
    if ([string]::IsNullOrWhiteSpace($dispatchRunId)) { $dispatchRunId = $key }

    # A dispatch id reached first (no packet found by key) still finds its packet.
    if ($null -eq $packagedItem -and (Get-Command -Name 'Get-PackagedItemQueue' -ErrorAction SilentlyContinue)) {
        $packagedItem = @(Get-PackagedItemQueue -WorkspaceRoot $WorkspaceRoot -Limit 0 |
            Where-Object { (_Trace_Str -Obj $_ -Name 'dispatchRunId') -eq $dispatchRunId }) | Select-Object -First 1
    }

    # 3. Dispatch artifacts.
    $queueEntry = @(_Trace_ReadJsonl -Path (Join-Path $WorkspaceRoot 'output\roadmap-task-queue.jsonl') |
        Where-Object { (_Trace_Str -Obj $_ -Name 'runId') -eq $dispatchRunId }) | Select-Object -First 1
    $runSummary = _Trace_ReadJson -Path (Join-Path $WorkspaceRoot ("output\roadmap-task-history\runs\{0}.summary.json" -f ($dispatchRunId -replace '[\\/:*?"<>|]', '_')))

    # 4. Merge readiness, by the repo the run names.
    $mergeReadiness = $null
    $repoId = if ($null -ne $agentRun) { _Trace_Str -Obj $agentRun -Name 'repoId' } else { '' }
    if ([string]::IsNullOrWhiteSpace($repoId) -and $null -ne $packagedItem) {
        $repoId = _Trace_Str -Obj (_Trace_Field -Obj $packagedItem -Name 'packet' -Default $null) -Name 'repoId'
    }
    if (-not [string]::IsNullOrWhiteSpace($repoId) -and (Get-Command -Name 'Get-MergeReadinessSnapshot' -ErrorAction SilentlyContinue)) {
        $mergeReadiness = Get-MergeReadinessSnapshot -WorkspaceRoot $WorkspaceRoot -RepoId $repoId
    }

    # 5. Write-back decisions for any of this trace's ids.
    $packetId = if ($null -ne $packagedItem) { _Trace_Str -Obj $packagedItem -Name 'packetId' } else { '' }
    $writeBack = @(_Trace_ReadJsonl -Path (Get-WorkItemWriteBackLedgerPath -WorkspaceRoot $WorkspaceRoot) |
        Where-Object {
            (Test-WorkItemTraceKeyMatch -Record $_ -Key $dispatchRunId) -or
            (Test-WorkItemTraceKeyMatch -Record $_ -Key $key) -or
            (-not [string]::IsNullOrWhiteSpace($packetId) -and (_Trace_Str -Obj $_ -Name 'packetId') -eq $packetId)
        })

    return (Join-WorkItemTrace -TraceKey $key `
        -PackagedItem $packagedItem `
        -QueueEntry $queueEntry `
        -RunSummary $runSummary `
        -AgentRun $agentRun `
        -MergeReadiness $mergeReadiness `
        -WriteBackRecords $writeBack)
}
