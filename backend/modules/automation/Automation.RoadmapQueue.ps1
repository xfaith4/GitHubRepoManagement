<#
.SYNOPSIS
    Pure roadmap-task-queue contract: the shape of a queue entry and the rules
    for what may go in one.

.DESCRIPTION
    These functions used to live inside `scripts/Add-RoadmapTaskToQueue.ps1`,
    which is an ENTRY-POINT SCRIPT with a `param()` block. Dot-sourcing a script
    runs it in the CALLER'S scope, and that also assigns every one of its
    parameters there - unbound ones as ''. So the API host, which dot-sourced
    that script from inside `POST /api/roadmap/dispatch/execute` to reach
    `New-RoadmapQueueEntry`, silently had its own `$runId` and `$baseBranch`
    blanked by the script's `$RunId` and `$BaseBranch` parameters (PowerShell
    variable names are case-insensitive, so `$runId` and `$RunId` are one
    variable). The very next statement then failed with

        Cannot bind argument to parameter 'RunId' because it is an empty string.

    which is where the guided-improvement wizard died at its final step.

    The fix is structural, not a rename: a function library carries no `param()`
    block, so dot-sourcing it cannot touch a caller's variables. The API host
    loads THIS file with its other libraries at startup and never dot-sources a
    parameterised script mid-request. `Invoke-ModuleSmokeTest.ps1` asserts that
    property over the host's own source, so the trap cannot be re-armed by a
    future route that wants one of these functions.

    `Add-RoadmapTaskToQueue.ps1` still owns the command-line surface and still
    exposes these functions via `-LoadFunctionsOnly`; it now dot-sources them
    from here so there is exactly one definition of the queue contract.
#>

# NOTE: these five functions are moved here VERBATIM from
# scripts\Add-RoadmapTaskToQueue.ps1 - same signatures, same bodies, no added
# [CmdletBinding()]/[OutputType()]. The move is the fix; changing the functions
# at the same time would have made a behaviour regression indistinguishable from
# the relocation, and the two long-standing PSScriptAnalyzer findings they carry
# (plural noun, ShouldProcess) would have moved from "existing debt" to "new".

function Get-RoadmapQueuePath {
    <#
    .SYNOPSIS
        The one place the task-queue path is decided.
    .DESCRIPTION
        Release 2.9. Four call sites used to rebuild this path inline beside
        this resolver, which is how the api-host smoke came to enqueue its
        dispatch fixture into the OPERATOR'S real queue: a live runner claimed
        it in the ~1s enqueue-to-cancel window on 2026-08-19, then the smoke
        deleted the fixture out from under the claimed session. With one
        resolver, redirecting the queue is a single decision instead of four
        edits that can disagree.

        REPO_MGMT_QUEUE_PATH overrides it, matching the REPO_MGMT_* convention
        the timeout and TLS settings already use. The smoke sets it so its
        fixtures never touch the operator's queue; nothing in production does.
    #>
    param([Parameter(Mandatory)][string]$WorkspaceRoot)

    $override = [System.Environment]::GetEnvironmentVariable('REPO_MGMT_QUEUE_PATH')
    if (-not [string]::IsNullOrWhiteSpace($override)) { return $override }

    Join-Path $WorkspaceRoot 'output\roadmap-task-queue.jsonl'
}

function Get-RoadmapDispatchTargets {
    <# Release 3.0 - the only two execution contexts a queue entry may name.
       `claude` runs Claude Code in the operator's session; `copilot` runs
       `gh agent-task create`, which needs the OAuth credential only an operator
       session holds. Both execute as the operator; neither runs in the service. #>
    return @('claude', 'copilot')
}

function Resolve-RoadmapDispatchTarget {
    <#
    .SYNOPSIS
        Pure - normalize a dispatch target, or throw with the allowed set named.
    .DESCRIPTION
        Empty resolves to `claude` for backward compatibility: entries written
        before Release 3.0 carry no dispatchTarget and must keep running as the
        Claude Code tasks they were queued as. An UNRECOGNIZED value is refused
        rather than defaulted - silently running an unknown target as `claude`
        would execute the wrong tool against a real repository.
    #>
    param([AllowEmptyString()][string]$DispatchTarget = '')

    if ([string]::IsNullOrWhiteSpace($DispatchTarget)) { return 'claude' }
    $normalized = $DispatchTarget.Trim().ToLowerInvariant()
    if ($normalized -notin (Get-RoadmapDispatchTargets)) {
        throw ("Unknown dispatchTarget '{0}'. Allowed: {1}." -f $DispatchTarget, ((Get-RoadmapDispatchTargets) -join ', '))
    }
    return $normalized
}

function New-RoadmapQueueEntry {
    <# Pure: build the queue entry object. `status='queued'` is the runner's cue
       to claim it. `prompt` is the full task text handed to the target tool.

       `dispatchTarget` (Release 3.0) names WHICH tool: the portal enqueues from
       a LocalSystem service that can hold neither an OAuth credential nor a
       Claude Code login, so the entry records the intent and the operator-session
       runner supplies the identity. `baseBranch` is carried because
       `gh agent-task create --base` needs it and the runner has no other source. #>
    param(
        [Parameter(Mandatory)][string]$RunId,
        [string]$Repository,
        [Parameter(Mandatory)][string]$LocalRepoPath,
        [string]$RoadmapPath,
        [string]$SelectedTask,
        [Parameter(Mandatory)][string]$TaskDescription,
        [string]$Branch,
        [Parameter(Mandatory)][string]$QueuedAt,
        [AllowEmptyString()][string]$DispatchTarget = 'claude',
        [AllowEmptyString()][string]$BaseBranch = ''
    )
    if ([string]::IsNullOrWhiteSpace($Branch)) { $Branch = "roadmap/$RunId" }
    return [ordered]@{
        schemaVersion  = '1'
        runId          = $RunId
        status         = 'queued'
        repository     = $Repository
        localRepoPath  = $LocalRepoPath
        roadmapPath    = $RoadmapPath
        selectedTask   = $SelectedTask
        branch         = $Branch
        prompt         = $TaskDescription
        dispatchTarget = (Resolve-RoadmapDispatchTarget -DispatchTarget $DispatchTarget)
        baseBranch     = $BaseBranch
        queuedAt       = $QueuedAt
    }
}

function Add-RoadmapQueueEntry {
    param([Parameter(Mandatory)][string]$QueuePath, [Parameter(Mandatory)][System.Collections.IDictionary]$Entry)
    $dir = Split-Path -Parent $QueuePath
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { $null = New-Item -ItemType Directory -Path $dir -Force }
    $line = ([pscustomobject]$Entry | ConvertTo-Json -Depth 8 -Compress)
    Add-Content -LiteralPath $QueuePath -Value $line -Encoding UTF8
}
