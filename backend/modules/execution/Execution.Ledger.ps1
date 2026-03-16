# Execution.Ledger.ps1
# Persistent two-lane execution state ledger for Release 1.0.
# Manages repo assignment, duplicate-dispatch prevention, execution states,
# and task outcomes for the portfolio execution console.
#
# Execution states:
#   idle      - repo is known but not queued for any work
#   ready     - repo has pending roadmap work and is eligible for dispatch
#   running   - a Copilot task is currently active for this repo
#   blocked   - repo cannot be dispatched (docs, parse error, etc.)
#   complete  - all roadmap work for this repo is done
#
# Two-lane model:
#   At most two repos may be in 'running' state simultaneously.
#   A repo cannot occupy both lanes at the same time.
#   The same roadmap item cannot be running in two repos simultaneously.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Schema version — increment when the ledger file format changes
# ---------------------------------------------------------------------------
$script:LedgerSchemaVersion = '1.0'

# ---------------------------------------------------------------------------
# Get-ExecutionLedgerPath
# Returns the canonical ledger file path under the workspace output directory.
# ---------------------------------------------------------------------------
function Get-ExecutionLedgerPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$WorkspaceRoot
    )

    $dir = Join-Path $WorkspaceRoot 'output\execution'
    if (-not (Test-Path -LiteralPath $dir)) {
        $null = New-Item -ItemType Directory -Path $dir -Force
    }
    return Join-Path $dir 'execution-ledger.json'
}

# ---------------------------------------------------------------------------
# Read-ExecutionLedger
# Reads and returns the current ledger. Returns a default empty ledger if
# the file does not exist or cannot be parsed.
# ---------------------------------------------------------------------------
function Read-ExecutionLedger {
    param(
        [Parameter(Mandatory = $true)]
        [string]$WorkspaceRoot
    )

    $path = Get-ExecutionLedgerPath -WorkspaceRoot $WorkspaceRoot
    $empty = @{
        schemaVersion = $script:LedgerSchemaVersion
        updatedAt     = (Get-Date).ToUniversalTime().ToString('o')
        entries       = @()
        history       = @()
    }

    if (-not (Test-Path -LiteralPath $path)) {
        return $empty
    }

    try {
        $raw = Get-Content -LiteralPath $path -Raw -Encoding UTF8
        $parsed = ConvertFrom-Json -InputObject $raw
        if ($null -eq $parsed -or $null -eq $parsed.entries) {
            return $empty
        }
        return @{
            schemaVersion = [string]($parsed.schemaVersion ?? $script:LedgerSchemaVersion)
            updatedAt     = [string]($parsed.updatedAt ?? (Get-Date).ToUniversalTime().ToString('o'))
            entries       = @($parsed.entries)
            history       = @($parsed.history ?? @())
        }
    } catch {
        return $empty
    }
}

# ---------------------------------------------------------------------------
# Write-ExecutionLedger
# Serialises and persists the ledger. Creates the output directory if needed.
# ---------------------------------------------------------------------------
function Write-ExecutionLedger {
    param(
        [Parameter(Mandatory = $true)]
        [string]$WorkspaceRoot,
        [Parameter(Mandatory = $true)]
        [hashtable]$Ledger
    )

    $path = Get-ExecutionLedgerPath -WorkspaceRoot $WorkspaceRoot
    $Ledger.updatedAt = (Get-Date).ToUniversalTime().ToString('o')
    $json = $Ledger | ConvertTo-Json -Depth 10
    Set-Content -LiteralPath $path -Value $json -Encoding UTF8
}

# ---------------------------------------------------------------------------
# New-LedgerEntry
# Constructs a fresh ledger entry for a repo.
# ---------------------------------------------------------------------------
function New-LedgerEntry {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoName,
        [Parameter()]
        [string]$RepoPath = '',
        [Parameter()]
        [string]$ExecutionState = 'idle',
        [Parameter()]
        [string]$RoadmapPath = '',
        [Parameter()]
        [string]$CurrentTaskText = '',
        [Parameter()]
        [string]$CurrentTaskSection = '',
        [Parameter()]
        [int]$PriorityScore = 0
    )

    return [ordered]@{
        repoName             = $RepoName
        repoPath             = $RepoPath
        executionState       = $ExecutionState
        roadmapPath          = $RoadmapPath
        currentTaskText      = $CurrentTaskText
        currentTaskSection   = $CurrentTaskSection
        currentRunId         = $null
        laneSlot             = $null
        priorityScore        = $PriorityScore
        assignedAt           = $null
        completedAt          = $null
        lastOutcome          = $null
        retryCount           = 0
        errorMessage         = $null
        updatedAt            = (Get-Date).ToUniversalTime().ToString('o')
    }
}

# ---------------------------------------------------------------------------
# New-HistoryRecord
# Constructs a ledger history record for completed/cancelled events.
# ---------------------------------------------------------------------------
function New-HistoryRecord {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoName,
        [Parameter(Mandatory = $true)]
        [string]$Event,
        [Parameter()]
        [string]$RunId = '',
        [Parameter()]
        [string]$TaskText = '',
        [Parameter()]
        [string]$Outcome = '',
        [Parameter()]
        [string]$ErrorMessage = ''
    )

    return [ordered]@{
        repoName     = $RepoName
        event        = $Event
        runId        = $RunId
        taskText     = $TaskText
        outcome      = $Outcome
        errorMessage = $ErrorMessage
        timestamp    = (Get-Date).ToUniversalTime().ToString('o')
    }
}

# ---------------------------------------------------------------------------
# Get-ActiveLaneCount
# Returns the number of repos currently in 'running' state (0, 1, or 2).
# ---------------------------------------------------------------------------
function Get-ActiveLaneCount {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Ledger
    )

    return @($Ledger.entries | Where-Object { $_.executionState -eq 'running' }).Count
}

# ---------------------------------------------------------------------------
# Get-LaneSummary
# Returns an array of the (up to) two active lane slot entries for the board.
# Slots are returned as [lane1, lane2] with $null for empty slots.
# ---------------------------------------------------------------------------
function Get-LaneSummary {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Ledger
    )

    $running = @($Ledger.entries | Where-Object { $_.executionState -eq 'running' } | Sort-Object laneSlot)
    $lane1 = $null
    $lane2 = $null
    foreach ($r in $running) {
        if ($null -eq $lane1) { $lane1 = $r }
        elseif ($null -eq $lane2) { $lane2 = $r }
    }
    return @($lane1, $lane2)
}

# ---------------------------------------------------------------------------
# Get-NextAvailableLaneSlot
# Returns 1 or 2 for the first available slot, or $null if both are occupied.
# ---------------------------------------------------------------------------
function Get-NextAvailableLaneSlot {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Ledger
    )

    $usedSlots = @($Ledger.entries | Where-Object { $_.executionState -eq 'running' } | ForEach-Object { [int]$_.laneSlot })
    if ($usedSlots -notcontains 1) { return 1 }
    if ($usedSlots -notcontains 2) { return 2 }
    return $null
}

# ---------------------------------------------------------------------------
# Sync-LedgerFromAudit
# Refreshes the ledger from fresh doc-audit + roadmap-audit data.
# Repos already 'running' are preserved. Repos that vanish from the audit
# are removed unless they are 'running'. New repos are added with 'idle' or
# 'ready' state based on readiness.
# Priority score = maturityScore (0-100) + readiness bonus:
#   ready                    +100
#   needs-doc-standardization +50
#   missing-roadmap            +0
#   roadmap-complete           +0
#   blocked                    -50
#   parse-error                -25
# ---------------------------------------------------------------------------
function Sync-LedgerFromAudit {
    param(
        [Parameter(Mandatory = $true)]
        [string]$WorkspaceRoot,
        [Parameter(Mandatory = $true)]
        [object[]]$DocAuditEntries,
        [Parameter()]
        [object[]]$RoadmapAuditEntries = @()
    )

    $ledger = Read-ExecutionLedger -WorkspaceRoot $WorkspaceRoot

    $readinessBonus = @{
        'ready'                     = 100
        'needs-doc-standardization' = 50
        'missing-roadmap'           = 0
        'roadmap-complete'          = 0
        'parse-error'               = -25
        'blocked'                   = -50
    }

    $roadmapByRepo = @{}
    foreach ($ra in $RoadmapAuditEntries) {
        $roadmapByRepo[$ra.repoName] = $ra
    }

    $existingByName = @{}
    foreach ($e in $ledger.entries) {
        $existingByName[$e.repoName] = $e
    }

    $newEntries = [System.Collections.Generic.List[object]]::new()

    foreach ($doc in $DocAuditEntries) {
        $name = $doc.repoName
        $existing = $existingByName[$name]

        # Preserve running entries unchanged
        if ($null -ne $existing -and $existing.executionState -eq 'running') {
            $newEntries.Add($existing)
            continue
        }

        # Determine target execution state
        $targetState = switch ($doc.dispatchReadiness) {
            'ready'                     { 'ready'   }
            'needs-doc-standardization' { 'ready'   }
            'roadmap-complete'          { 'complete' }
            'blocked'                   { 'blocked'  }
            'parse-error'               { 'blocked'  }
            'missing-roadmap'           { 'idle'     }
            default                     { 'idle'     }
        }

        # If previously completed and still complete — keep complete
        if ($null -ne $existing -and $existing.executionState -eq 'complete' -and $doc.dispatchReadiness -eq 'roadmap-complete') {
            $targetState = 'complete'
        }

        $ra = $roadmapByRepo[$name]
        $maturityScore = if ($null -ne $ra) { [int]($ra.maturityScore ?? 0) } else { 0 }
        $bonus = if ($readinessBonus.ContainsKey($doc.dispatchReadiness)) { $readinessBonus[$doc.dispatchReadiness] } else { 0 }
        $priorityScore = $maturityScore + $bonus

        $roadmapPath = if ($null -ne $ra) { [string]($ra.roadmapPath ?? '') } else { [string]($doc.nextPendingRoadmapItem ?? '') }
        $nextTaskText = if ($null -ne $ra -and $null -ne $ra.nextPendingItem) { [string]$ra.nextPendingItem.text } else { [string]($doc.nextPendingRoadmapItem ?? '') }
        $nextTaskSection = if ($null -ne $ra -and $null -ne $ra.nextPendingItem) { [string]$ra.nextPendingItem.section } else { '' }

        if ($null -ne $existing) {
            # Update existing entry, preserve identity fields
            $existing.executionState     = $targetState
            $existing.priorityScore      = $priorityScore
            $existing.roadmapPath        = $roadmapPath
            $existing.currentTaskText    = $nextTaskText
            $existing.currentTaskSection = $nextTaskSection
            $existing.updatedAt          = (Get-Date).ToUniversalTime().ToString('o')
            # Clear stale error if state improved
            if ($targetState -in @('ready', 'complete')) {
                $existing.errorMessage = $null
            }
            $newEntries.Add($existing)
        } else {
            $entry = New-LedgerEntry `
                -RepoName $name `
                -RepoPath ([string]($doc.repoPath ?? '')) `
                -ExecutionState $targetState `
                -RoadmapPath $roadmapPath `
                -CurrentTaskText $nextTaskText `
                -CurrentTaskSection $nextTaskSection `
                -PriorityScore $priorityScore
            $newEntries.Add($entry)
        }
    }

    $ledger.entries = @($newEntries)
    Write-ExecutionLedger -WorkspaceRoot $WorkspaceRoot -Ledger $ledger
    return $ledger
}

# ---------------------------------------------------------------------------
# Invoke-AssignLane
# Assigns a repo to the next available lane slot (changes state to 'running').
# Returns @{ success; laneSlot; error } where error is set on failure.
#
# Failure conditions:
#   - Repo not found in ledger
#   - Repo is not in 'ready' state
#   - Repo is already running
#   - Both lane slots are occupied
#   - The same roadmap item is already running in another lane
# ---------------------------------------------------------------------------
function Invoke-AssignLane {
    param(
        [Parameter(Mandatory = $true)]
        [string]$WorkspaceRoot,
        [Parameter(Mandatory = $true)]
        [string]$RepoName,
        [Parameter()]
        [string]$RunId = '',
        [Parameter()]
        [string]$TaskText = '',
        [Parameter()]
        [string]$TaskSection = ''
    )

    $ledger = Read-ExecutionLedger -WorkspaceRoot $WorkspaceRoot

    $entry = $ledger.entries | Where-Object { $_.repoName -eq $RepoName } | Select-Object -First 1
    if ($null -eq $entry) {
        return @{ success = $false; laneSlot = $null; error = "Repo '$RepoName' not found in execution ledger" }
    }

    if ($entry.executionState -eq 'running') {
        return @{ success = $false; laneSlot = $null; error = "Repo '$RepoName' is already running in lane $($entry.laneSlot)" }
    }

    if ($entry.executionState -notin @('ready', 'idle')) {
        return @{ success = $false; laneSlot = $null; error = "Repo '$RepoName' is not in a dispatchable state (current: $($entry.executionState))" }
    }

    $laneSlot = Get-NextAvailableLaneSlot -Ledger $ledger
    if ($null -eq $laneSlot) {
        return @{ success = $false; laneSlot = $null; error = 'Both execution lanes are occupied — wait for a running task to complete or cancel one' }
    }

    # Duplicate roadmap item guard: same task text cannot be active in both lanes
    $effectiveTask = if (-not [string]::IsNullOrWhiteSpace($TaskText)) { $TaskText } else { $entry.currentTaskText }
    if (-not [string]::IsNullOrWhiteSpace($effectiveTask)) {
        $duplicate = $ledger.entries | Where-Object {
            $_.executionState -eq 'running' -and
            -not [string]::IsNullOrWhiteSpace($_.currentTaskText) -and
            $_.currentTaskText -eq $effectiveTask
        }
        if ($null -ne $duplicate) {
            return @{ success = $false; laneSlot = $null; error = "Roadmap item '$effectiveTask' is already running in lane $($duplicate.laneSlot)" }
        }
    }

    $runId = if (-not [string]::IsNullOrWhiteSpace($RunId)) { $RunId } else { [System.Guid]::NewGuid().ToString('N') }

    $entry.executionState     = 'running'
    $entry.laneSlot           = $laneSlot
    $entry.currentRunId       = $runId
    $entry.assignedAt         = (Get-Date).ToUniversalTime().ToString('o')
    $entry.completedAt        = $null
    $entry.lastOutcome        = $null
    $entry.errorMessage       = $null
    $entry.updatedAt          = (Get-Date).ToUniversalTime().ToString('o')
    if (-not [string]::IsNullOrWhiteSpace($TaskText))    { $entry.currentTaskText    = $TaskText }
    if (-not [string]::IsNullOrWhiteSpace($TaskSection)) { $entry.currentTaskSection = $TaskSection }

    $hist = New-HistoryRecord -RepoName $RepoName -Event 'assigned' -RunId $runId -TaskText $entry.currentTaskText -Outcome 'running'
    $ledger.history = @($ledger.history) + @($hist)

    Write-ExecutionLedger -WorkspaceRoot $WorkspaceRoot -Ledger $ledger
    return @{ success = $true; laneSlot = $laneSlot; error = $null; runId = $runId; entry = $entry }
}

# ---------------------------------------------------------------------------
# Invoke-CompleteTask
# Marks a running repo task as complete.
# Transitions: running -> ready (if pending work remains) or complete (if done).
# ---------------------------------------------------------------------------
function Invoke-CompleteTask {
    param(
        [Parameter(Mandatory = $true)]
        [string]$WorkspaceRoot,
        [Parameter(Mandatory = $true)]
        [string]$RepoName,
        [Parameter()]
        [string]$Outcome = 'success',
        [Parameter()]
        [bool]$HasRemainingWork = $false
    )

    $ledger = Read-ExecutionLedger -WorkspaceRoot $WorkspaceRoot

    $entry = $ledger.entries | Where-Object { $_.repoName -eq $RepoName } | Select-Object -First 1
    if ($null -eq $entry) {
        return @{ success = $false; error = "Repo '$RepoName' not found in execution ledger" }
    }

    if ($entry.executionState -ne 'running') {
        return @{ success = $false; error = "Repo '$RepoName' is not currently running (state: $($entry.executionState))" }
    }

    $runId = $entry.currentRunId

    $entry.executionState = if ($HasRemainingWork) { 'ready' } else { 'complete' }
    $entry.laneSlot       = $null
    $entry.completedAt    = (Get-Date).ToUniversalTime().ToString('o')
    $entry.lastOutcome    = $Outcome
    $entry.updatedAt      = (Get-Date).ToUniversalTime().ToString('o')

    $hist = New-HistoryRecord -RepoName $RepoName -Event 'completed' -RunId $runId -TaskText $entry.currentTaskText -Outcome $Outcome
    $ledger.history = @($ledger.history) + @($hist)

    Write-ExecutionLedger -WorkspaceRoot $WorkspaceRoot -Ledger $ledger
    return @{ success = $true; newState = $entry.executionState; error = $null }
}

# ---------------------------------------------------------------------------
# Invoke-CancelTask
# Cancels or marks a running task as failed. Retries are tracked.
# Transitions: running -> ready (retry) or blocked (max retries exceeded).
# ---------------------------------------------------------------------------
function Invoke-CancelTask {
    param(
        [Parameter(Mandatory = $true)]
        [string]$WorkspaceRoot,
        [Parameter(Mandatory = $true)]
        [string]$RepoName,
        [Parameter()]
        [string]$Reason = 'cancelled',
        [Parameter()]
        [int]$MaxRetries = 3
    )

    $ledger = Read-ExecutionLedger -WorkspaceRoot $WorkspaceRoot

    $entry = $ledger.entries | Where-Object { $_.repoName -eq $RepoName } | Select-Object -First 1
    if ($null -eq $entry) {
        return @{ success = $false; error = "Repo '$RepoName' not found in execution ledger" }
    }

    if ($entry.executionState -ne 'running') {
        return @{ success = $false; error = "Repo '$RepoName' is not currently running (state: $($entry.executionState))" }
    }

    $runId = $entry.currentRunId
    $entry.retryCount  = [int]($entry.retryCount ?? 0) + 1
    $entry.laneSlot    = $null
    $entry.completedAt = (Get-Date).ToUniversalTime().ToString('o')
    $entry.lastOutcome = $Reason
    $entry.errorMessage = $Reason
    $entry.updatedAt   = (Get-Date).ToUniversalTime().ToString('o')

    if ($entry.retryCount -ge $MaxRetries) {
        $entry.executionState = 'blocked'
    } else {
        $entry.executionState = 'ready'
    }

    $hist = New-HistoryRecord -RepoName $RepoName -Event 'cancelled' -RunId $runId -TaskText $entry.currentTaskText -Outcome $Reason -ErrorMessage $Reason
    $ledger.history = @($ledger.history) + @($hist)

    Write-ExecutionLedger -WorkspaceRoot $WorkspaceRoot -Ledger $ledger
    return @{ success = $true; newState = $entry.executionState; retryCount = $entry.retryCount; error = $null }
}

# ---------------------------------------------------------------------------
# Invoke-RequeueRepo
# Resets a completed, blocked, or idle repo back to 'ready' state.
# Clears error state and resets retry count if forced.
# ---------------------------------------------------------------------------
function Invoke-RequeueRepo {
    param(
        [Parameter(Mandatory = $true)]
        [string]$WorkspaceRoot,
        [Parameter(Mandatory = $true)]
        [string]$RepoName,
        [Parameter()]
        [bool]$Force = $false
    )

    $ledger = Read-ExecutionLedger -WorkspaceRoot $WorkspaceRoot

    $entry = $ledger.entries | Where-Object { $_.repoName -eq $RepoName } | Select-Object -First 1
    if ($null -eq $entry) {
        return @{ success = $false; error = "Repo '$RepoName' not found in execution ledger" }
    }

    if ($entry.executionState -eq 'running') {
        return @{ success = $false; error = "Repo '$RepoName' is currently running — cancel it first" }
    }

    $entry.executionState = 'ready'
    $entry.laneSlot       = $null
    $entry.lastOutcome    = $null
    $entry.updatedAt      = (Get-Date).ToUniversalTime().ToString('o')
    if ($Force) {
        $entry.retryCount   = 0
        $entry.errorMessage = $null
    }

    $hist = New-HistoryRecord -RepoName $RepoName -Event 'requeued' -TaskText $entry.currentTaskText -Outcome 'ready'
    $ledger.history = @($ledger.history) + @($hist)

    Write-ExecutionLedger -WorkspaceRoot $WorkspaceRoot -Ledger $ledger
    return @{ success = $true; newState = 'ready'; error = $null }
}

# ---------------------------------------------------------------------------
# Get-RankedQueue
# Returns ready-state entries sorted by priorityScore descending.
# Used to surface the best next candidates for dispatch.
# ---------------------------------------------------------------------------
function Get-RankedQueue {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Ledger
    )

    return @($Ledger.entries | Where-Object { $_.executionState -eq 'ready' } | Sort-Object priorityScore -Descending)
}

# ---------------------------------------------------------------------------
# Get-ExecutionQueueSummary
# Returns the full queue summary used by GET /api/execution/queue.
# ---------------------------------------------------------------------------
function Get-ExecutionQueueSummary {
    param(
        [Parameter(Mandatory = $true)]
        [string]$WorkspaceRoot
    )

    $ledger = Read-ExecutionLedger -WorkspaceRoot $WorkspaceRoot
    $lanes = Get-LaneSummary -Ledger $ledger
    $ranked = Get-RankedQueue -Ledger $ledger

    $byState = @{}
    foreach ($state in @('idle','ready','running','blocked','complete')) {
        $byState[$state] = @($ledger.entries | Where-Object { $_.executionState -eq $state }).Count
    }

    return @{
        schemaVersion  = $ledger.schemaVersion
        updatedAt      = $ledger.updatedAt
        totalRepos     = @($ledger.entries).Count
        stateCounts    = $byState
        activeLaneCount = Get-ActiveLaneCount -Ledger $ledger
        lanes          = @{ lane1 = $lanes[0]; lane2 = $lanes[1] }
        rankedQueue    = $ranked
        entries        = $ledger.entries
        recentHistory  = @($ledger.history | Select-Object -Last 50)
    }
}
