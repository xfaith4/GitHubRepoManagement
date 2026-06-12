<#
.SYNOPSIS
    Merge-readiness evaluator for Release 2.0 (Agent Run Monitoring and
    Actions-Gated Merge Readiness), Phase 3.

.DESCRIPTION
    Decides whether agent-produced work is safe to merge, with explicit
    operator-visible blockers. The evaluation itself is pure — it takes the
    latest agent-run ledger record, an optional GitHub PR detail (for
    mergeability), the local dirty count, and unresolved audit blockers —
    so the blocking rules are testable offline.

    Guardrail (ROADMAP section 8): merge readiness is never shown unless the
    app can identify the PR, the latest Actions result, validation evidence,
    and unresolved blockers. Anything unidentifiable is itself a blocker.

    Snapshots are stored one JSON per repo under output/merge-readiness/ so
    GET /api/merge-readiness/{repoId} can answer without re-querying GitHub.

.NOTES
    Dot-source after AgentRuns.ps1:
        . (Join-Path $agentRunsModuleRoot 'MergeReadiness.ps1')
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:MergeReadinessRelDir = 'output\merge-readiness'

function _MergeReadinessField {
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

function _MergeReadinessSnapshotPath {
    param([string]$WorkspaceRoot, [string]$RepoId)
    $dir = Join-Path $WorkspaceRoot $script:MergeReadinessRelDir
    $null = New-Item -ItemType Directory -Path $dir -Force -ErrorAction SilentlyContinue
    $safeRepoId = $RepoId -replace '[\\/:*?"<>|]', '_'
    return Join-Path $dir "$safeRepoId.json"
}

<#
.SYNOPSIS
    Evaluate merge readiness from observed state. Pure decision logic — no
    network, no disk writes.
.DESCRIPTION
    Blocking rules (any blocker => ready=false):
      no-agent-run            no ledger run exists for the repo
      no-pr                   the run has no associated pull request
      pr-draft                the PR is still a draft (agent not finished)
      pr-closed-without-merge the PR was closed unmerged
      pr-already-merged       the PR is already merged (nothing to gate)
      merge-conflicts         GitHub reports the PR is not mergeable
      missing-validation-evidence  no observed Actions state for the run
      actions-pending         the latest Actions run has not completed
      actions-failing         the latest Actions conclusion is not success
      dirty-worktree          the local worktree has uncommitted changes
      audit-blocker           unresolved assessment/audit blocking reasons
#>
function Get-MergeReadinessEvaluation {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)][string]$RepoId,
        [Parameter(Mandatory = $true)][string]$RepoName,
        [Parameter()][object]$AgentRun = $null,
        [Parameter()][object]$PrDetail = $null,
        # Freshly observed Actions state (status/conclusion/workflowName);
        # overrides the possibly-stale state on the ledger record.
        [Parameter()][object]$ActionsState = $null,
        [Parameter()][int]$LocalDirtyCount = 0,
        [Parameter()][string[]]$AuditBlockers = @()
    )

    $blockers = New-Object System.Collections.Generic.List[object]
    $addBlocker = {
        param([string]$Code, [string]$Message, [string]$Source)
        $blockers.Add([ordered]@{ code = $Code; message = $Message; source = $Source })
    }

    $runId = [string](_MergeReadinessField -Obj $AgentRun -Name 'runId' -Default '')
    $prUrl = [string](_MergeReadinessField -Obj $AgentRun -Name 'prUrl' -Default '')
    $prNumber = _MergeReadinessField -Obj $AgentRun -Name 'prNumber'
    $prState = [string](_MergeReadinessField -Obj $AgentRun -Name 'prState' -Default '')
    $prDraft = [bool](_MergeReadinessField -Obj $AgentRun -Name 'prDraft' -Default $false)
    $actions = if ($null -ne $ActionsState) { $ActionsState } else { _MergeReadinessField -Obj $AgentRun -Name 'actions' }

    # Fresh GitHub PR detail overrides the (possibly stale) ledger view.
    $mergeable = $null
    $mergeableState = ''
    if ($null -ne $PrDetail) {
        $prDraft = [bool](_MergeReadinessField -Obj $PrDetail -Name 'draft' -Default $prDraft)
        $detailMergedAt = _MergeReadinessField -Obj $PrDetail -Name 'merged_at'
        $detailState = [string](_MergeReadinessField -Obj $PrDetail -Name 'state' -Default '')
        if ($null -ne $detailMergedAt -and -not [string]::IsNullOrWhiteSpace([string]$detailMergedAt)) {
            $prState = 'merged'
        } elseif ($detailState -eq 'closed') {
            $prState = 'closed'
        } elseif (-not [string]::IsNullOrWhiteSpace($detailState)) {
            $prState = 'open'
        }
        $mergeable = _MergeReadinessField -Obj $PrDetail -Name 'mergeable'
        $mergeableState = [string](_MergeReadinessField -Obj $PrDetail -Name 'mergeable_state' -Default '')
    }

    if ($null -eq $AgentRun) {
        & $addBlocker 'no-agent-run' "No agent run is recorded for '$RepoName'; dispatch work before evaluating merge readiness." 'agent-run-ledger'
    } elseif ([string]::IsNullOrWhiteSpace($prUrl)) {
        & $addBlocker 'no-pr' 'The agent run has no associated pull request yet. Refresh the run from GitHub or wait for the agent to open its PR.' 'agent-run-ledger'
    } else {
        switch ($prState) {
            'merged' { & $addBlocker 'pr-already-merged' "PR $prUrl is already merged; there is nothing left to gate." 'github' }
            'closed' { & $addBlocker 'pr-closed-without-merge' "PR $prUrl was closed without merging; the agent work was discarded." 'github' }
            default {
                if ($prDraft) {
                    & $addBlocker 'pr-draft' "PR $prUrl is still a draft — the agent has not marked its work ready for review." 'github'
                }
                if ($mergeable -is [bool] -and -not $mergeable) {
                    & $addBlocker 'merge-conflicts' "GitHub reports PR $prUrl is not mergeable (state: $mergeableState)." 'github'
                }
            }
        }

        $actionsStatus = [string](_MergeReadinessField -Obj $actions -Name 'status' -Default '')
        $actionsConclusion = [string](_MergeReadinessField -Obj $actions -Name 'conclusion' -Default '')
        if ($null -eq $actions -or [string]::IsNullOrWhiteSpace($actionsStatus)) {
            & $addBlocker 'missing-validation-evidence' 'No GitHub Actions state has been observed for this run. Refresh the run from GitHub to capture validation evidence.' 'agent-run-ledger'
        } elseif ($actionsStatus -ne 'completed') {
            & $addBlocker 'actions-pending' "The latest Actions run is still '$actionsStatus'; validation has not finished." 'github'
        } elseif ($actionsConclusion -ne 'success') {
            & $addBlocker 'actions-failing' "The latest Actions conclusion is '$actionsConclusion'; merge requires a successful validation run." 'github'
        }
    }

    if ($LocalDirtyCount -gt 0) {
        & $addBlocker 'dirty-worktree' "The local worktree has $LocalDirtyCount uncommitted change(s)." 'local-git'
    }

    foreach ($reason in @($AuditBlockers | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
        & $addBlocker 'audit-blocker' $reason 'assessment'
    }

    return [pscustomobject]@{
        repoId      = $RepoId
        repoName    = $RepoName
        runId       = if ([string]::IsNullOrWhiteSpace($runId)) { $null } else { $runId }
        prUrl       = if ([string]::IsNullOrWhiteSpace($prUrl)) { $null } else { $prUrl }
        prNumber    = $prNumber
        ready       = ($blockers.Count -eq 0)
        blockers    = $blockers.ToArray()
        evidence    = [ordered]@{
            prState            = if ([string]::IsNullOrWhiteSpace($prState)) { $null } else { $prState }
            prDraft            = $prDraft
            mergeable          = $mergeable
            mergeableState     = if ([string]::IsNullOrWhiteSpace($mergeableState)) { $null } else { $mergeableState }
            actionsStatus      = [string](_MergeReadinessField -Obj $actions -Name 'status' -Default '')
            actionsConclusion  = [string](_MergeReadinessField -Obj $actions -Name 'conclusion' -Default '')
            actionsWorkflowName = [string](_MergeReadinessField -Obj $actions -Name 'workflowName' -Default '')
            localDirtyCount    = $LocalDirtyCount
            auditBlockerCount  = @($AuditBlockers | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count
        }
        evaluatedAt = (Get-Date).ToUniversalTime().ToString('o')
    }
}

<#
.SYNOPSIS
    Persist a merge-readiness evaluation as the repo's current snapshot.
#>
function Save-MergeReadinessSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$WorkspaceRoot,
        [Parameter(Mandatory = $true)][object]$Evaluation
    )

    $repoId = [string](_MergeReadinessField -Obj $Evaluation -Name 'repoId' -Default '')
    if ([string]::IsNullOrWhiteSpace($repoId)) { throw 'Evaluation has no repoId; cannot save snapshot.' }
    $path = _MergeReadinessSnapshotPath -WorkspaceRoot $WorkspaceRoot -RepoId $repoId
    ConvertTo-Json -InputObject $Evaluation -Depth 8 | Set-Content -LiteralPath $path -Encoding UTF8 -ErrorAction Stop
    return $path
}

<#
.SYNOPSIS
    Read the stored merge-readiness snapshot for a repo, or $null when the
    repo has never been evaluated.
#>
function Get-MergeReadinessSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$WorkspaceRoot,
        [Parameter(Mandatory = $true)][string]$RepoId
    )

    $path = _MergeReadinessSnapshotPath -WorkspaceRoot $WorkspaceRoot -RepoId $RepoId
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    try {
        return ConvertFrom-Json -InputObject (Get-Content -LiteralPath $path -Raw -Encoding UTF8)
    } catch {
        return $null
    }
}
