<#
.SYNOPSIS
    Release 3.8 M6/M7a — canonical execution event vocabulary and delivery state
    mapping. H38-34 + H38-35.

.DESCRIPTION
    H38-34: Provider output converts to the canonical execution.* event vocabulary,
    and the delivery state machine states are exposed as a mapped dimension — the
    sixth status dimension the Dispatch Board can display alongside the five from
    Release 3.5.

    H38-35: The execution.completed event carries cost/duration/first-pass telemetry
    so historical performance data is available for adaptive routing and accounting.

    Vocabulary boundary (one namespace per concern, no overlap):
    - execution.* events  : per-agent-run step events (this module)
    - roadmap-events.jsonl: roadmap phase-level lifecycle events (roadmap-events.md)

    An execution.completed event is not a roadmap lifecycle event; they live in
    different ledgers and are consumed by different audiences.

.NOTES
    PowerShell 5.1 compatible. Param-less library: dot-source it, do not run it.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Canonical event type vocabulary (H38-34)
# ---------------------------------------------------------------------------

# Minimum vocabulary every provider adapter MUST use. Consumers MUST tolerate
# unknown types so new events can be added without a schema break.
$script:ExecutionEventTypes = @(
    'execution.queued',
    'execution.started',
    'execution.progress',
    'execution.command.started',
    'execution.command.completed',
    'execution.files.changed',
    'execution.verification.started',
    'execution.verification.completed',
    'execution.usage',
    'execution.capacity.warning',
    'execution.capacity.exhausted',
    'execution.completed',
    'execution.failed',
    'execution.cancelled'
)

# ---------------------------------------------------------------------------
# Delivery state machine (H38-34 — sixth status dimension)
# ---------------------------------------------------------------------------

# States ordered along the happy-path progression from Agent-Execution-Governance.md.
$script:DeliveryStates = @(
    'DISCOVERED', 'FORMING', 'QUALIFIED', 'QUEUED',
    'CAPACITY_EVALUATING', 'CAPACITY_WAIT',
    'PROVIDER_SELECTED', 'WORKSPACE_PREPARING',
    'AGENT_RUNNING', 'LOCAL_VERIFYING',
    'IMPLEMENTATION_COMPLETE',
    'PUSHING', 'PR_OPEN',
    'CI_PENDING', 'CI_FAILED', 'CI_PASSED',
    'READY_FOR_OPERATOR', 'OPERATOR_APPROVED',
    'MERGING', 'MERGED',
    'POST_MERGE_VERIFYING', 'POST_MERGE_REMEDIATION',
    'COMPLETE',
    'REMEDIATION'
)

# Run-summary / lane-verdict status strings → delivery state.
# Keys are lowercase/kebab-case values from run summaries, agent-run ledger
# entries, and lane observation verdicts. Values are the canonical ALL_CAPS
# delivery states from Agent-Execution-Governance.md.
# Callers MUST tolerate $null from Get-DeliveryState for unrecognised inputs.
$script:_StatusToDeliveryState = [ordered]@{
    'discovered'              = 'DISCOVERED'
    'forming'                 = 'FORMING'
    'qualified'               = 'QUALIFIED'
    'queued'                  = 'QUEUED'
    'capacity_evaluating'     = 'CAPACITY_EVALUATING'
    'capacity_wait'           = 'CAPACITY_WAIT'
    'dispatched'              = 'PROVIDER_SELECTED'
    'provider_selected'       = 'PROVIDER_SELECTED'
    'workspace_preparing'     = 'WORKSPACE_PREPARING'
    'active'                  = 'AGENT_RUNNING'
    'running'                 = 'AGENT_RUNNING'
    'local-verifying'         = 'LOCAL_VERIFYING'
    'local_verifying'         = 'LOCAL_VERIFYING'
    'implementation_complete' = 'IMPLEMENTATION_COMPLETE'
    'completed'               = 'IMPLEMENTATION_COMPLETE'
    'implementation_failed'   = 'REMEDIATION'
    'capacity_exhausted'      = 'CAPACITY_WAIT'
    'cancelled'               = 'REMEDIATION'
    'pushing'                 = 'PUSHING'
    'awaiting-review'         = 'PR_OPEN'
    'pr-open'                 = 'PR_OPEN'
    'ci-pending'              = 'CI_PENDING'
    'ci_pending'              = 'CI_PENDING'
    'ci-failed'               = 'CI_FAILED'
    'ci_failed'               = 'CI_FAILED'
    'ci-passed'               = 'CI_PASSED'
    'ci_passed'               = 'CI_PASSED'
    'ready-for-operator'      = 'READY_FOR_OPERATOR'
    'ready_for_operator'      = 'READY_FOR_OPERATOR'
    'merging'                 = 'MERGING'
    'merged'                  = 'MERGED'
    'post_merge_verifying'    = 'POST_MERGE_VERIFYING'
    'post_merge_remediation'  = 'POST_MERGE_REMEDIATION'
    'finished'                = 'COMPLETE'
    'complete'                = 'COMPLETE'
    'remediation'             = 'REMEDIATION'
}

# ---------------------------------------------------------------------------
# New-ExecutionEvent — H38-34
# ---------------------------------------------------------------------------

<#
.SYNOPSIS
    Create a normalized execution.* event with all required envelope fields.

.DESCRIPTION
    Returns an [ordered] hashtable. The caller is responsible for generating a
    unique EventId (e.g. a GUID) and a UTC timestamp string. Payload is any
    provider-specific or type-specific data; it is attached as-is so callers
    control the shape without this constructor having to enumerate every type.

    Unknown Type values are rejected so that a typo never silently produces an
    event Mission Control cannot classify. Consumers reading the event stream
    MUST still tolerate unknown types (new additions are not breaking), but a
    producer that spells a type wrong is a producer bug, not a consumer concern.
#>
function New-ExecutionEvent {
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Pure constructor: builds an event object in memory and writes nothing.')]
    param(
        [Parameter(Mandatory)][string]$EventId,
        [Parameter(Mandatory)][string]$TaskId,
        [Parameter(Mandatory)][string]$ExecutionId,
        [Parameter(Mandatory)][string]$Provider,
        [AllowEmptyString()][string]$ProviderSessionId = '',
        [Parameter(Mandatory)][string]$Timestamp,
        [Parameter(Mandatory)][string]$Type,
        [object]$Payload = $null
    )

    if ($Type -notin $script:ExecutionEventTypes) {
        throw ("Unknown execution event type '{0}'. Valid types: {1}" -f $Type, ($script:ExecutionEventTypes -join ', '))
    }

    $sessionId = $null
    if (-not [string]::IsNullOrWhiteSpace($ProviderSessionId)) { $sessionId = [string]$ProviderSessionId }

    $evObj = [ordered]@{
        eventId           = [string]$EventId
        taskId            = [string]$TaskId
        executionId       = [string]$ExecutionId
        provider          = [string]$Provider
        providerSessionId = $sessionId
        timestamp         = [string]$Timestamp
        type              = [string]$Type
    }

    if ($null -ne $Payload) { $evObj['payload'] = $Payload }

    return $evObj
}

# ---------------------------------------------------------------------------
# Get-DeliveryState — H38-34 (sixth status dimension)
# ---------------------------------------------------------------------------

<#
.SYNOPSIS
    Map a run-summary status or lane-verdict string to the canonical delivery
    state dimension value defined in Agent-Execution-Governance.md.

.DESCRIPTION
    Returns the ALL_CAPS delivery state string, or $null when the input does not
    map to a known state. Callers MUST handle $null: an unrecognised status is
    not an error — it means the input predates this vocabulary or carries a value
    this version was not built to map.

    Case-insensitive: 'QUEUED', 'queued', and 'Queued' all map to 'QUEUED'.
#>
function Get-DeliveryState {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter()][AllowEmptyString()][AllowNull()][string]$Status = $null)

    if ([string]::IsNullOrWhiteSpace($Status)) { return $null }

    $key = $Status.ToLowerInvariant()
    if ($script:_StatusToDeliveryState.Contains($key)) {
        return [string]$script:_StatusToDeliveryState[$key]
    }
    return $null
}

# ---------------------------------------------------------------------------
# New-ExecutionCompletedPayload — H38-35 (cost/duration/first-pass telemetry)
# ---------------------------------------------------------------------------

<#
.SYNOPSIS
    Build the telemetry payload for an execution.completed event.

.DESCRIPTION
    H38-35: adds cost/duration/first-pass telemetry to the execution.completed
    event so historical performance data is available for adaptive routing and
    accounting without a secondary lookup.

    Duration is computed from StartTime and CompletionTime when both are
    supplied; it is not required because a provider may not always record timing.
    Cost is nullable: a subscription allowance has no unit-cost, and the spec
    forbids inventing one (same posture as Get-ClaudeTokenTotal).

    FirstPassSuccess is $true when AttemptCount is 1 and the execution status
    is implementation_complete; the caller passes it explicitly so this function
    carries no knowledge of how attempts are counted.
#>
function New-ExecutionCompletedPayload {
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Pure constructor: returns a payload hashtable and writes nothing.')]
    param(
        [AllowEmptyString()][AllowNull()][string]$StartTime = $null,
        [AllowEmptyString()][AllowNull()][string]$CompletionTime = $null,
        [AllowNull()][nullable[double]]$EstimatedCost = $null,
        [AllowEmptyString()][AllowNull()][string]$CostUnit = 'usd',
        [AllowNull()][nullable[bool]]$FirstPassSuccess = $null,
        [AllowNull()][nullable[int]]$InputTokens = $null,
        [AllowNull()][nullable[int]]$OutputTokens = $null,
        [AllowNull()][nullable[int]]$AttemptCount = $null
    )

    $duration = $null
    if (-not [string]::IsNullOrWhiteSpace($StartTime) -and -not [string]::IsNullOrWhiteSpace($CompletionTime)) {
        try {
            $start = [datetime]::Parse($StartTime)
            $end = [datetime]::Parse($CompletionTime)
            $duration = [math]::Round(($end - $start).TotalSeconds, 3)
        } catch { $duration = $null }
    }

    $cost = $null
    if ($null -ne $EstimatedCost) {
        $cost = [ordered]@{
            estimated = $EstimatedCost
            unit      = $(if ([string]::IsNullOrWhiteSpace($CostUnit)) { 'usd' } else { $CostUnit })
        }
    }

    return [ordered]@{
        startTime        = $(if ([string]::IsNullOrWhiteSpace($StartTime)) { $null } else { [string]$StartTime })
        completionTime   = $(if ([string]::IsNullOrWhiteSpace($CompletionTime)) { $null } else { [string]$CompletionTime })
        durationSeconds  = $duration
        cost             = $cost
        firstPassSuccess = $FirstPassSuccess
        inputTokens      = $InputTokens
        outputTokens     = $OutputTokens
        attemptCount     = $AttemptCount
    }
}

# ---------------------------------------------------------------------------
# Test-ExecutionEvent — validation (mirrors Test-WorkPacket / Test-ExecutionResult)
# ---------------------------------------------------------------------------

<#
.SYNOPSIS
    Validate an execution event object. Returns all errors at once.
#>
function Test-ExecutionEvent {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$ExecutionEvent)

    $errors = @()

    foreach ($field in @('eventId', 'taskId', 'executionId', 'provider', 'timestamp', 'type')) {
        $val = $null
        if ($ExecutionEvent -is [System.Collections.IDictionary]) { $val = $ExecutionEvent[$field] }
        elseif ($null -ne $ExecutionEvent.PSObject -and ($ExecutionEvent.PSObject.Properties.Name -contains $field)) { $val = $ExecutionEvent.$field }
        if ([string]::IsNullOrWhiteSpace([string]$val)) { $errors += ("'{0}' is required" -f $field) }
    }

    $typeVal = $null
    if ($ExecutionEvent -is [System.Collections.IDictionary]) { $typeVal = [string]$ExecutionEvent['type'] }
    elseif ($null -ne $ExecutionEvent.PSObject -and ($ExecutionEvent.PSObject.Properties.Name -contains 'type')) { $typeVal = [string]$ExecutionEvent.type }
    if (-not [string]::IsNullOrWhiteSpace($typeVal) -and $typeVal -notin $script:ExecutionEventTypes) {
        $errors += ("type '{0}' is not in the canonical vocabulary" -f $typeVal)
    }

    return [pscustomobject]@{
        ok     = ($errors.Count -eq 0)
        errors = @($errors)
    }
}
