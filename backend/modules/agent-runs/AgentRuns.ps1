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
        [Parameter(Mandatory = $true)][string]$RunId,
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
        [Parameter()][string]$BaseBranch = '',
        [Parameter()][string]$ProviderTool = 'github-copilot-agent',
        [Parameter()][int]$PromptCount = 1
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
            workUnitsEstimated   = $script:AgentRunDefaultWorkUnits
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
            workUnitsEstimated    = $script:AgentRunDefaultWorkUnits
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
    $startedAt = _AgentRunsField -Obj $run['metrics'] -Name 'agentStartedAt' -Default $null
    $completedAt = _AgentRunsField -Obj $run['metrics'] -Name 'agentCompletedAt' -Default $null
    if ($null -ne $startedAt -and $null -ne $completedAt) {
        try {
            $run['metrics']['timeToDeliverSeconds'] = [int]([datetime]$completedAt - [datetime]$startedAt).TotalSeconds
        } catch {
            # Leave timeToDeliverSeconds untouched when timestamps cannot parse.
        }
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
