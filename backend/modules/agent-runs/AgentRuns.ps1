<#
.SYNOPSIS
    Agent-run ledger and append-only run-event telemetry for Release 2.0
    (Agent Run Monitoring and Actions-Gated Merge Readiness), Phase 1.

.DESCRIPTION
    Storage model (per standards/roadmap/ROADMAP_BUDGET_MODEL.md and the
    "Markdown for intent, structured state editable, JSONL append-only for
    history" telemetry architecture):

      output/agent-runs/runs/<runId>.json   Editable current state — one JSON
                                            document per run, updated in place
                                            as the run progresses.
      output/agent-runs/events.jsonl        Append-only, schema-versioned
                                            lifecycle event stream. Events are
                                            never rewritten; derived values
                                            are never stored in them.

    Tier-1 metric fields (automatic, required) live on the run record:
    dispatch/start/completion timestamps, derived time-to-deliver, prompt
    count, retries, reported token usage, direct API spend, and normalized
    AI work units. Tier-2 operator observations attach without blocking.
    Tier-3 valuations (USD allocation, overage risk) are never stored here —
    they are computed at report time.

.NOTES
    Dot-source this file to load the public functions:
        . (Join-Path $agentRunsModuleRoot 'AgentRuns.ps1')
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

$script:AgentRunsRelDir       = 'output\agent-runs'
$script:AgentRunsRunsRelDir   = 'output\agent-runs\runs'
$script:AgentRunEventsFile    = 'events.jsonl'
$script:AgentRunEventSchema   = '1.0'

# Default normalized work-unit weight for one coding-agent run. The budget
# model (standards/roadmap/ROADMAP_BUDGET_MODEL.md) defines the starting
# weights; Phase 4 moves these into the budget ledger config.
$script:AgentRunDefaultWorkUnits = 3

$script:AgentRunStatuses = @('dispatched', 'active', 'completed', 'failed', 'blocked')

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

function _AgentRunsField {
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

function _AgentRunsRunsDir {
    param([string]$WorkspaceRoot)
    $dir = Join-Path $WorkspaceRoot $script:AgentRunsRunsRelDir
    $null = New-Item -ItemType Directory -Path $dir -Force -ErrorAction SilentlyContinue
    return $dir
}

function _AgentRunFilePath {
    param([string]$WorkspaceRoot, [string]$RunId)
    $safeRunId = $RunId -replace '[\\/:*?"<>|]', '_'
    return Join-Path (_AgentRunsRunsDir -WorkspaceRoot $WorkspaceRoot) "$safeRunId.json"
}

function _AgentRunEventsPath {
    param([string]$WorkspaceRoot)
    $dir = Join-Path $WorkspaceRoot $script:AgentRunsRelDir
    $null = New-Item -ItemType Directory -Path $dir -Force -ErrorAction SilentlyContinue
    return Join-Path $dir $script:AgentRunEventsFile
}

# ---------------------------------------------------------------------------
# Event stream (append-only)
# ---------------------------------------------------------------------------

<#
.SYNOPSIS
    Append one schema-versioned lifecycle event to output/agent-runs/events.jsonl.
.DESCRIPTION
    Append-only by contract: events are never rewritten or deleted, and only
    raw observations belong in them. Failures are non-fatal — telemetry must
    never break the run it describes — but the failure is surfaced in the
    return value so callers can log it.
#>
function Write-AgentRunEvent {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)][string]$WorkspaceRoot,
        [Parameter(Mandatory = $true)][string]$EventType,
        # Pre-dispatch telemetry (e.g. 'quota.exhausted' / 'quota.warning') is emitted
        # before any run exists, so RunId is optional and defaults to empty. A mandatory
        # binding here rejected the empty string and turned the quota-refusal route's
        # intended HTTP 409 into a caught 500.
        [Parameter()][string]$RunId = '',
        [Parameter()][string]$RepoName = '',
        [Parameter()][string]$Actor = 'system',
        [Parameter()][string]$Summary = '',
        [Parameter()][object]$Data = $null
    )

    $record = [ordered]@{
        schemaVersion = $script:AgentRunEventSchema
        eventId       = 'evt_' + [guid]::NewGuid().ToString('n').Substring(0, 12)
        timestamp     = (Get-Date).ToUniversalTime().ToString('o')
        eventType     = $EventType
        runId         = $RunId
        repoName      = $RepoName
        actor         = $Actor
        summary       = $Summary
        data          = $Data
    }

    try {
        $json = ConvertTo-Json -InputObject $record -Compress -Depth 6
        Add-Content -LiteralPath (_AgentRunEventsPath -WorkspaceRoot $WorkspaceRoot) -Value $json -Encoding UTF8 -ErrorAction Stop
        $record['written'] = $true
    } catch {
        $record['written'] = $false
        $record['writeError'] = $_.Exception.Message
    }

    # Release 2.1 Phase 1 persistence seam: best-effort mirror into the SQLite
    # agent_run_events table when the persistence module is loaded and the app
    # database is initialized. The JSONL stream above remains authoritative
    # during rollout; a mirror failure must never break the run it describes.
    if (Get-Command -Name 'Write-AppDbAgentRunEvent' -ErrorAction SilentlyContinue) {
        try {
            $mirror = Write-AppDbAgentRunEvent -EventRecord $record
            $record['dbMirrored'] = [bool]$mirror.success
        } catch {
            $record['dbMirrored'] = $false
        }
    }

    return [pscustomobject]$record
}

# ---------------------------------------------------------------------------
# Ledger (editable current state, one JSON per run)
# ---------------------------------------------------------------------------

<#
.SYNOPSIS
    Create a new agent-run ledger record at dispatch time and append the
    run.dispatched event.
#>
function New-AgentRunRecord {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)][string]$WorkspaceRoot,
        [Parameter(Mandatory = $true)][string]$RepoName,
        [Parameter()][string]$RepoId = '',
        [Parameter()][string]$GitHubRepo = '',
        [Parameter()][string]$LocalPath = '',
        [Parameter()][string]$DispatchRunId = '',
        [Parameter()][string]$PromptRefinementRunId = '',
        [Parameter()][string]$SelectedTaskText = '',
        [Parameter()][string]$SelectedTaskSection = '',
        [Parameter()][string]$PlannedReleaseName = '',
        [Parameter()][string]$PlannedPhaseName = '',
        [Parameter()][string]$BaseBranch = '',
        [Parameter()][string]$ProviderTool = 'github-copilot-agent',
        [Parameter()][int]$PromptCount = 1,
        [Parameter()][double]$WorkUnitsEstimated = $script:AgentRunDefaultWorkUnits,
        [Parameter()][string]$WorkUnitsEstimateSource = ''
    )

    $runId = [guid]::NewGuid().ToString('n')
    $nowIso = (Get-Date).ToUniversalTime().ToString('o')

    $record = [ordered]@{
        runId                 = $runId
        repoName              = $RepoName
        repoId                = if ([string]::IsNullOrWhiteSpace($RepoId)) { $null } else { $RepoId }
        githubRepo            = if ([string]::IsNullOrWhiteSpace($GitHubRepo)) { $null } else { $GitHubRepo }
        localPath             = if ([string]::IsNullOrWhiteSpace($LocalPath)) { $null } else { $LocalPath }
        dispatchRunId         = if ([string]::IsNullOrWhiteSpace($DispatchRunId)) { $null } else { $DispatchRunId }
        promptRefinementRunId = if ([string]::IsNullOrWhiteSpace($PromptRefinementRunId)) { $null } else { $PromptRefinementRunId }
        selectedTaskText      = if ([string]::IsNullOrWhiteSpace($SelectedTaskText)) { $null } else { $SelectedTaskText }
        selectedTaskSection   = if ([string]::IsNullOrWhiteSpace($SelectedTaskSection)) { $null } else { $SelectedTaskSection }
        plannedReleaseName    = if ([string]::IsNullOrWhiteSpace($PlannedReleaseName)) { $null } else { $PlannedReleaseName }
        plannedPhaseName      = if ([string]::IsNullOrWhiteSpace($PlannedPhaseName)) { $null } else { $PlannedPhaseName }
        workUnitsEstimateSource = if ([string]::IsNullOrWhiteSpace($WorkUnitsEstimateSource)) { $null } else { $WorkUnitsEstimateSource }
        providerTool          = $ProviderTool
        branch                = $null
        baseBranch            = if ([string]::IsNullOrWhiteSpace($BaseBranch)) { $null } else { $BaseBranch }
        prUrl                 = $null
        status                = 'dispatched'
        outcome               = $null
        createdAt             = $nowIso
        updatedAt             = $nowIso
        metrics               = [ordered]@{
            # Tier 1 — automatic observations
            dispatchedAt         = $nowIso
            agentStartedAt       = $null
            agentCompletedAt     = $null
            timeToDeliverSeconds = $null
            promptCount          = $PromptCount
            retries              = 0
            tokenUsage           = $null
            apiSpendUsd          = $null
            workUnitsEstimated   = if ($WorkUnitsEstimated -gt 0) { [double]$WorkUnitsEstimated } else { [double]$script:AgentRunDefaultWorkUnits }
            workUnitsActual      = $null
            # Tier 2 — optional operator observations (never blocking)
            unitsRemainingObserved = $null
            creditPromptSeen     = $null
            humanReviewMinutes   = $null
        }
    }

    $path = _AgentRunFilePath -WorkspaceRoot $WorkspaceRoot -RunId $runId
    ConvertTo-Json -InputObject $record -Depth 6 | Set-Content -LiteralPath $path -Encoding UTF8 -ErrorAction Stop

    $null = Write-AgentRunEvent -WorkspaceRoot $WorkspaceRoot -EventType 'run.dispatched' -RunId $runId -RepoName $RepoName `
        -Summary "Agent run dispatched for $RepoName via $ProviderTool." `
        -Data ([ordered]@{
            githubRepo            = $record['githubRepo']
            dispatchRunId         = $record['dispatchRunId']
            promptRefinementRunId = $record['promptRefinementRunId']
            selectedTaskText      = $record['selectedTaskText']
            selectedTaskSection   = $record['selectedTaskSection']
            plannedReleaseName    = $record['plannedReleaseName']
            plannedPhaseName      = $record['plannedPhaseName']
            workUnitsEstimated    = $record['metrics']['workUnitsEstimated']
            workUnitsEstimateSource = $record['workUnitsEstimateSource']
        })

    return [pscustomobject]$record
}

<#
.SYNOPSIS
    Read all agent-run ledger records, optionally filtered by status, newest
    (by updatedAt) first.
#>
function Get-AgentRuns {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$WorkspaceRoot,
        [Parameter()][string]$Status = '',
        [Parameter()][string]$RepoName = '',
        [Parameter()][int]$Limit = 50
    )

    $dir = _AgentRunsRunsDir -WorkspaceRoot $WorkspaceRoot
    $files = @(Get-ChildItem -LiteralPath $dir -Filter '*.json' -File -ErrorAction SilentlyContinue)
    if ($files.Count -eq 0) { return @() }

    $runs = @(
        $files | ForEach-Object {
            try { ConvertFrom-Json -InputObject (Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8) } catch { $null }
        } | Where-Object { $null -ne $_ }
    )

    if (-not [string]::IsNullOrWhiteSpace($Status)) {
        $wanted = $Status.ToLowerInvariant()
        $runs = @($runs | Where-Object { ([string](_AgentRunsField -Obj $_ -Name 'status' -Default '')).ToLowerInvariant() -eq $wanted })
    }
    if (-not [string]::IsNullOrWhiteSpace($RepoName)) {
        $runs = @($runs | Where-Object { [string](_AgentRunsField -Obj $_ -Name 'repoName' -Default '') -eq $RepoName })
    }

    return @(
        $runs |
            Sort-Object { _AgentRunsField -Obj $_ -Name 'updatedAt' -Default ([datetime]::MinValue) } -Descending |
            Select-Object -First $Limit
    )
}

<#
.SYNOPSIS
    Read one run's full detail: the ledger record plus its lifecycle events
    from the append-only stream.
#>
function Get-AgentRunDetail {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$WorkspaceRoot,
        [Parameter(Mandatory = $true)][string]$RunId
    )

    $path = _AgentRunFilePath -WorkspaceRoot $WorkspaceRoot -RunId $RunId
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }

    $run = $null
    try {
        $run = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $path -Raw -Encoding UTF8)
    } catch {
        return $null
    }

    $events = @()
    $eventsPath = _AgentRunEventsPath -WorkspaceRoot $WorkspaceRoot
    if (Test-Path -LiteralPath $eventsPath -PathType Leaf) {
        try {
            $events = @(
                Get-Content -LiteralPath $eventsPath -Encoding UTF8 -ErrorAction Stop |
                    Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                    ForEach-Object { try { ConvertFrom-Json -InputObject $_ } catch { $null } } |
                    Where-Object { $null -ne $_ -and [string](_AgentRunsField -Obj $_ -Name 'runId' -Default '') -eq $RunId }
            )
        } catch {
            $events = @()
        }
    }

    return [pscustomobject]@{
        run    = $run
        events = $events
    }
}

<#
.SYNOPSIS
    Patch an agent-run ledger record (status, branch/PR association, metric
    observations), bump updatedAt, and append the matching lifecycle event.
.DESCRIPTION
    Status transitions emit run.completed / run.failed / run.blocked /
    run.started events; other patches emit run.updated. When a patch sets
    agentCompletedAt and agentStartedAt is known, timeToDeliverSeconds is
    derived onto the ledger record (the event keeps only the raw timestamps).
#>
function Update-AgentRunRecord {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)][string]$WorkspaceRoot,
        [Parameter(Mandatory = $true)][string]$RunId,
        [Parameter(Mandatory = $true)][hashtable]$Patch,
        [Parameter()][string]$Actor = 'system',
        [Parameter()][string]$Summary = ''
    )

    $path = _AgentRunFilePath -WorkspaceRoot $WorkspaceRoot -RunId $RunId
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Agent run '$RunId' was not found."
    }

    $run = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $path -Raw -Encoding UTF8) -AsHashtable
    $previousStatus = [string](_AgentRunsField -Obj $run -Name 'status' -Default '')

    $metricKeys = @('agentStartedAt', 'agentCompletedAt', 'promptCount', 'retries', 'tokenUsage', 'apiSpendUsd',
                    'workUnitsEstimated', 'workUnitsActual', 'unitsRemainingObserved', 'creditPromptSeen', 'humanReviewMinutes')

    foreach ($key in $Patch.Keys) {
        if ($key -in $metricKeys) {
            if ($null -eq $run['metrics']) { $run['metrics'] = @{} }
            $run['metrics'][$key] = $Patch[$key]
        } elseif ($key -eq 'status') {
            $newStatus = ([string]$Patch[$key]).ToLowerInvariant()
            if ($newStatus -notin $script:AgentRunStatuses) {
                throw "Invalid agent-run status '$newStatus'. Expected one of: $($script:AgentRunStatuses -join ', ')."
            }
            $run['status'] = $newStatus
        } else {
            $run[$key] = $Patch[$key]
        }
    }

    # Derive time-to-deliver onto the ledger when both timestamps are known.
    # Normalize both sides to UTC: values may be ISO strings (fresh patches)
    # or [datetime] objects (records re-read via ConvertFrom-Json).
    $startedUtc = _AgentRunsAsUtc -Value (_AgentRunsField -Obj $run['metrics'] -Name 'agentStartedAt' -Default $null)
    $completedUtc = _AgentRunsAsUtc -Value (_AgentRunsField -Obj $run['metrics'] -Name 'agentCompletedAt' -Default $null)
    if ($null -ne $startedUtc -and $null -ne $completedUtc) {
        $run['metrics']['timeToDeliverSeconds'] = [int]($completedUtc - $startedUtc).TotalSeconds
    }

    $run['updatedAt'] = (Get-Date).ToUniversalTime().ToString('o')
    ConvertTo-Json -InputObject $run -Depth 6 | Set-Content -LiteralPath $path -Encoding UTF8 -ErrorAction Stop

    $newStatusValue = [string](_AgentRunsField -Obj $run -Name 'status' -Default '')
    $eventType = if ($newStatusValue -ne $previousStatus) {
        switch ($newStatusValue) {
            'active'    { 'run.started' }
            'completed' { 'run.completed' }
            'failed'    { 'run.failed' }
            'blocked'   { 'run.blocked' }
            default     { 'run.updated' }
        }
    } else {
        'run.updated'
    }
    $eventSummary = if (-not [string]::IsNullOrWhiteSpace($Summary)) {
        $Summary
    } elseif ($eventType -ne 'run.updated') {
        "Agent run status changed: $previousStatus -> $newStatusValue."
    } else {
        'Agent run record updated.'
    }

    $null = Write-AgentRunEvent -WorkspaceRoot $WorkspaceRoot -EventType $eventType -RunId $RunId `
        -RepoName ([string](_AgentRunsField -Obj $run -Name 'repoName' -Default '')) -Actor $Actor `
        -Summary $eventSummary -Data ([ordered]@{ patchedFields = @($Patch.Keys) })

    return [pscustomobject]$run
}

# ---------------------------------------------------------------------------
# Phase 2 — branch/PR association and GitHub-state refresh
# ---------------------------------------------------------------------------

# Branch-name prefix the GitHub Copilot coding agent uses for the head branch
# of the pull requests it opens.
$script:AgentRunCopilotBranchPrefix = 'copilot/'

# Clock-skew allowance when comparing PR creation time against dispatch time.
$script:AgentRunDispatchSkewMinutes = 10

<#
.SYNOPSIS
    Normalize a timestamp to a UTC [datetime], or $null when unusable.
.DESCRIPTION
    Timestamps arrive either as ISO 8601 strings (ledger files, GitHub API
    JSON) or as [datetime] objects (ConvertFrom-Json / Invoke-RestMethod
    eagerly convert ISO strings). Casting a [datetime] to [string] and
    re-parsing double-applies the timezone offset, so this helper handles
    both shapes explicitly.
#>
function _AgentRunsAsUtc {
    param([object]$Value)

    if ($null -eq $Value) { return $null }
    if ($Value -is [datetime]) {
        switch ($Value.Kind) {
            ([System.DateTimeKind]::Utc)   { return $Value }
            ([System.DateTimeKind]::Local) { return $Value.ToUniversalTime() }
            # Unspecified: the ledger and GitHub only ever serialize UTC.
            default { return [datetime]::SpecifyKind($Value, [System.DateTimeKind]::Utc) }
        }
    }

    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    try {
        return ([System.DateTimeOffset]::Parse($text, [System.Globalization.CultureInfo]::InvariantCulture)).UtcDateTime
    } catch {
        return $null
    }
}

# ISO 8601 UTC string for ledger storage, or $null when unusable.
function _AgentRunsIsoString {
    param([object]$Value)
    $utc = _AgentRunsAsUtc -Value $Value
    if ($null -eq $utc) { return $null }
    return $utc.ToString('o')
}

<#
.SYNOPSIS
    Pick the pull request that belongs to an agent run from a list of the
    repo's pull requests, with operator-visible association evidence.
.DESCRIPTION
    Pure selection logic (no network, no ledger writes) so association
    heuristics are testable offline. Pull-request objects use the GitHub REST
    shape: number, html_url, state, draft, title, body, created_at,
    updated_at, merged_at, closed_at, head.ref.

    Match order:
      1. existing-pr-url      — the run already stores this PR's html_url
      2. recorded-branch-name — the run already stores the PR's head branch
      3. heuristic            — copilot/* head branch created at/after the
                                run's dispatch time (minus a small clock-skew
                                allowance); a selectedTaskText fingerprint in
                                the PR title or body breaks ties, then the
                                earliest-created candidate wins.
#>
function Select-AgentRunPullRequestCandidate {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)][object]$Run,
        [Parameter()][object[]]$PullRequests = @()
    )

    $prs = @($PullRequests | Where-Object { $null -ne $_ })
    $evidence = [ordered]@{
        matchedBy      = @()
        candidateCount = 0
        evaluatedAt    = (Get-Date).ToUniversalTime().ToString('o')
    }

    if ($prs.Count -eq 0) {
        return [pscustomobject]@{ pullRequest = $null; evidence = [pscustomobject]$evidence }
    }

    $getHeadRef = {
        param($pr)
        $head = _AgentRunsField -Obj $pr -Name 'head'
        return [string](_AgentRunsField -Obj $head -Name 'ref' -Default '')
    }

    # 1. The run already knows its PR URL.
    $existingPrUrl = [string](_AgentRunsField -Obj $Run -Name 'prUrl' -Default '')
    if (-not [string]::IsNullOrWhiteSpace($existingPrUrl)) {
        $match = $prs | Where-Object { [string](_AgentRunsField -Obj $_ -Name 'html_url' -Default '') -eq $existingPrUrl } | Select-Object -First 1
        if ($null -ne $match) {
            $evidence['matchedBy'] = @('existing-pr-url')
            $evidence['candidateCount'] = 1
            return [pscustomobject]@{ pullRequest = $match; evidence = [pscustomobject]$evidence }
        }
    }

    # 2. The run already knows its head branch.
    $existingBranch = [string](_AgentRunsField -Obj $Run -Name 'branch' -Default '')
    if (-not [string]::IsNullOrWhiteSpace($existingBranch)) {
        $match = $prs | Where-Object { (& $getHeadRef $_) -eq $existingBranch } | Select-Object -First 1
        if ($null -ne $match) {
            $evidence['matchedBy'] = @('recorded-branch-name')
            $evidence['candidateCount'] = 1
            return [pscustomobject]@{ pullRequest = $match; evidence = [pscustomobject]$evidence }
        }
    }

    # 3. Heuristic association: copilot/* branches created after dispatch.
    $metrics = _AgentRunsField -Obj $Run -Name 'metrics'
    $dispatchedAt = _AgentRunsAsUtc -Value (_AgentRunsField -Obj $metrics -Name 'dispatchedAt')
    if ($null -eq $dispatchedAt) {
        $dispatchedAt = _AgentRunsAsUtc -Value (_AgentRunsField -Obj $Run -Name 'createdAt')
    }

    $candidates = @(
        $prs | Where-Object {
            $headRef = & $getHeadRef $_
            if (-not $headRef.StartsWith($script:AgentRunCopilotBranchPrefix, [System.StringComparison]::OrdinalIgnoreCase)) { return $false }
            if ($null -eq $dispatchedAt) { return $true }
            $created = _AgentRunsAsUtc -Value (_AgentRunsField -Obj $_ -Name 'created_at')
            if ($null -eq $created) { return $false }
            return $created -ge $dispatchedAt.AddMinutes(-1 * $script:AgentRunDispatchSkewMinutes)
        }
    )
    $evidence['candidateCount'] = $candidates.Count
    if ($candidates.Count -eq 0) {
        return [pscustomobject]@{ pullRequest = $null; evidence = [pscustomobject]$evidence }
    }

    $matchedBy = @('copilot-branch-prefix')
    if ($null -ne $dispatchedAt) { $matchedBy += 'created-after-dispatch' }

    # Task fingerprint: a normalized leading slice of the selected roadmap
    # task appearing in the PR title or body.
    $fingerprintMatches = @()
    $taskText = [string](_AgentRunsField -Obj $Run -Name 'selectedTaskText' -Default '')
    $fingerprint = ($taskText -replace '\s+', ' ').Trim()
    if ($fingerprint.Length -gt 60) { $fingerprint = $fingerprint.Substring(0, 60) }
    if ($fingerprint.Length -ge 12) {
        $fingerprintMatches = @(
            $candidates | Where-Object {
                $title = ([string](_AgentRunsField -Obj $_ -Name 'title' -Default '') -replace '\s+', ' ')
                $body  = ([string](_AgentRunsField -Obj $_ -Name 'body'  -Default '') -replace '\s+', ' ')
                ($title.IndexOf($fingerprint, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) -or
                ($body.IndexOf($fingerprint, [System.StringComparison]::OrdinalIgnoreCase) -ge 0)
            }
        )
    }
    if ($fingerprintMatches.Count -gt 0) {
        $candidates = $fingerprintMatches
        $matchedBy += 'task-fingerprint'
    }

    $selected = @(
        $candidates | Sort-Object {
            $created = _AgentRunsAsUtc -Value (_AgentRunsField -Obj $_ -Name 'created_at')
            if ($null -eq $created) { [datetime]::MaxValue } else { $created }
        }
    )[0]

    $evidence['matchedBy'] = $matchedBy
    return [pscustomobject]@{ pullRequest = $selected; evidence = [pscustomobject]$evidence }
}

<#
.SYNOPSIS
    Refresh one agent run from observed GitHub state: associate its branch
    and PR, record Actions status, advance the run status, and append the
    matching lifecycle / validation events.
.DESCRIPTION
    Takes pre-fetched GitHub state (the repo's pull requests and the latest
    Actions run for the associated branch) so the decision logic stays
    network-free and testable offline. Status transitions observed from PR
    state:

      draft PR found            dispatched -> active
      PR ready for review       active     -> completed (outcome awaiting-merge)
      PR merged                 *          -> completed (outcome merged)
      PR closed without merge   *          -> failed    (outcome pr-closed-without-merge)

    A validation.passed / validation.failed event is appended when the
    observed Actions conclusion changed since the previous refresh; derived
    values are never written into events.
#>
function Invoke-AgentRunRefresh {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)][string]$WorkspaceRoot,
        [Parameter(Mandatory = $true)][string]$RunId,
        [Parameter()][object[]]$PullRequests = @(),
        [Parameter()][object]$ActionsRun = $null,
        [Parameter()][string]$Actor = 'operator'
    )

    $path = _AgentRunFilePath -WorkspaceRoot $WorkspaceRoot -RunId $RunId
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Agent run '$RunId' was not found."
    }
    $run = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $path -Raw -Encoding UTF8)

    $nowIso = (Get-Date).ToUniversalTime().ToString('o')
    $candidate = Select-AgentRunPullRequestCandidate -Run $run -PullRequests $PullRequests
    $currentStatus = [string](_AgentRunsField -Obj $run -Name 'status' -Default '')
    $metrics = _AgentRunsField -Obj $run -Name 'metrics'

    $patch = @{ lastRefreshAt = $nowIso }
    $summaryParts = @()

    if ($null -ne $candidate.pullRequest) {
        $pr = $candidate.pullRequest
        $head = _AgentRunsField -Obj $pr -Name 'head'
        $headRef = [string](_AgentRunsField -Obj $head -Name 'ref' -Default '')
        $prDraft = [bool](_AgentRunsField -Obj $pr -Name 'draft' -Default $false)
        $mergedAt = _AgentRunsIsoString -Value (_AgentRunsField -Obj $pr -Name 'merged_at')
        $closedAt = _AgentRunsIsoString -Value (_AgentRunsField -Obj $pr -Name 'closed_at')
        $prState = if ($null -ne $mergedAt) {
            'merged'
        } elseif ([string](_AgentRunsField -Obj $pr -Name 'state' -Default '') -eq 'closed') {
            'closed'
        } else {
            'open'
        }

        if (-not [string]::IsNullOrWhiteSpace($headRef)) { $patch['branch'] = $headRef }
        $prUrl = [string](_AgentRunsField -Obj $pr -Name 'html_url' -Default '')
        if (-not [string]::IsNullOrWhiteSpace($prUrl)) { $patch['prUrl'] = $prUrl }
        $patch['prNumber'] = _AgentRunsField -Obj $pr -Name 'number'
        $patch['prState'] = $prState
        $patch['prDraft'] = $prDraft

        $existingAssociation = _AgentRunsField -Obj $run -Name 'association'
        $associatedAt = [string](_AgentRunsField -Obj $existingAssociation -Name 'associatedAt' -Default $nowIso)
        $patch['association'] = [ordered]@{
            matchedBy      = @($candidate.evidence.matchedBy)
            candidateCount = [int]$candidate.evidence.candidateCount
            associatedAt   = $associatedAt
        }

        # Observed tier-1 timing: PR creation is the closest observable proxy
        # for when the agent started producing work.
        if ($null -eq (_AgentRunsField -Obj $metrics -Name 'agentStartedAt')) {
            $prCreatedAt = _AgentRunsIsoString -Value (_AgentRunsField -Obj $pr -Name 'created_at')
            if ($null -ne $prCreatedAt) { $patch['agentStartedAt'] = $prCreatedAt }
        }

        $agentCompletedAt = _AgentRunsField -Obj $metrics -Name 'agentCompletedAt'
        switch ($prState) {
            'merged' {
                $patch['status'] = 'completed'
                $patch['outcome'] = 'merged'
                if ($null -eq $agentCompletedAt) { $patch['agentCompletedAt'] = $mergedAt }
                $summaryParts += "PR #$($patch['prNumber']) merged"
            }
            'closed' {
                $patch['status'] = 'failed'
                $patch['outcome'] = 'pr-closed-without-merge'
                if ($null -eq $agentCompletedAt -and $null -ne $closedAt) { $patch['agentCompletedAt'] = $closedAt }
                $summaryParts += "PR #$($patch['prNumber']) closed without merge"
            }
            default {
                if (-not $prDraft -and $currentStatus -in @('dispatched', 'active')) {
                    $patch['status'] = 'completed'
                    $patch['outcome'] = 'awaiting-merge'
                    if ($null -eq $agentCompletedAt) {
                        $prUpdatedAt = _AgentRunsIsoString -Value (_AgentRunsField -Obj $pr -Name 'updated_at')
                        $patch['agentCompletedAt'] = if ($null -eq $prUpdatedAt) { $nowIso } else { $prUpdatedAt }
                    }
                    $summaryParts += "PR #$($patch['prNumber']) ready for review"
                } elseif ($prDraft -and $currentStatus -eq 'dispatched') {
                    $patch['status'] = 'active'
                    $summaryParts += "agent working on draft PR #$($patch['prNumber'])"
                } else {
                    $summaryParts += "PR #$($patch['prNumber']) $prState"
                }
            }
        }
    } else {
        $summaryParts += 'no matching agent pull request found yet'
    }

    # Actions state for the associated branch, plus validation events when
    # the observed conclusion changed since the previous refresh.
    $validationEventType = $null
    if ($null -ne $ActionsRun) {
        $actionsStatus = [string](_AgentRunsField -Obj $ActionsRun -Name 'status' -Default '')
        $actionsConclusion = [string](_AgentRunsField -Obj $ActionsRun -Name 'conclusion' -Default '')
        $actionsName = [string](_AgentRunsField -Obj $ActionsRun -Name 'name' -Default '')
        $actionsUrl = [string](_AgentRunsField -Obj $ActionsRun -Name 'runUrl' -Default '')
        $patch['actions'] = [ordered]@{
            status       = $actionsStatus
            conclusion   = if ([string]::IsNullOrWhiteSpace($actionsConclusion)) { $null } else { $actionsConclusion }
            workflowName = $actionsName
            runUrl       = if ([string]::IsNullOrWhiteSpace($actionsUrl)) { $null } else { $actionsUrl }
            observedAt   = $nowIso
        }
        $summaryParts += "Actions $actionsStatus$(if ($actionsConclusion) { "/$actionsConclusion" })"

        $previousActions = _AgentRunsField -Obj $run -Name 'actions'
        $previousConclusion = [string](_AgentRunsField -Obj $previousActions -Name 'conclusion' -Default '')
        if (-not [string]::IsNullOrWhiteSpace($actionsConclusion) -and $actionsConclusion -ne $previousConclusion) {
            $validationEventType = if ($actionsConclusion -eq 'success') { 'validation.passed' } else { 'validation.failed' }
        }
    }

    $summary = 'Refreshed from GitHub: ' + ($summaryParts -join '; ') + '.'
    $updated = Update-AgentRunRecord -WorkspaceRoot $WorkspaceRoot -RunId $RunId -Patch $patch -Actor $Actor -Summary $summary

    if ($null -ne $validationEventType) {
        $null = Write-AgentRunEvent -WorkspaceRoot $WorkspaceRoot -EventType $validationEventType -RunId $RunId `
            -RepoName ([string](_AgentRunsField -Obj $updated -Name 'repoName' -Default '')) -Actor $Actor `
            -Summary ("GitHub Actions conclusion observed: {0}." -f [string](_AgentRunsField -Obj $ActionsRun -Name 'conclusion' -Default '')) `
            -Data ([ordered]@{
                status       = [string](_AgentRunsField -Obj $ActionsRun -Name 'status' -Default '')
                conclusion   = [string](_AgentRunsField -Obj $ActionsRun -Name 'conclusion' -Default '')
                workflowName = [string](_AgentRunsField -Obj $ActionsRun -Name 'name' -Default '')
                runUrl       = [string](_AgentRunsField -Obj $ActionsRun -Name 'runUrl' -Default '')
            })
    }

    return [pscustomobject]@{
        run             = $updated
        association     = $candidate.evidence
        pullRequestFound = ($null -ne $candidate.pullRequest)
        validationEvent = $validationEventType
        refreshedAt     = $nowIso
    }
}
