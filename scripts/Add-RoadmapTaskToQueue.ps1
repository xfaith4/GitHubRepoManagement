<#
.SYNOPSIS
    Append a roadmap task to the local Claude Code task queue.

.DESCRIPTION
    The portal (a LocalSystem service) cannot run the operator's authenticated
    Claude Code, so instead of dispatching to GitHub Copilot it ENQUEUES the task
    here. A separate operator-run runner (Invoke-RoadmapTaskRunner.ps1) watches
    output/roadmap-task-queue.jsonl and launches `claude` in the target local repo.

    This writer only appends one append-only JSONL line (it never runs anything).
    The run summary (status='queued') is written by the caller
    (Start-RoadmapCopilotTask.ps1) so summary handling stays in one place and the
    existing Get-RoadmapTaskHistory / UI keep working.

.PARAMETER LoadFunctionsOnly
    Dot-source the pure functions without appending (used by the module smoke).
#>
[CmdletBinding()]
param(
    [string]$WorkspaceRoot,
    [string]$RunId,
    [string]$Repository,
    [string]$LocalRepoPath,
    [string]$RoadmapPath,
    [string]$SelectedTask,
    [string]$TaskDescription,
    [string]$Branch,
    [ValidateSet('claude', 'copilot')]
    [string]$DispatchTarget = 'claude',
    [string]$BaseBranch,
    [switch]$LoadFunctionsOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($WorkspaceRoot)) {
    $WorkspaceRoot = Split-Path -Parent $PSScriptRoot
}

function Get-RoadmapQueuePath {
    param([Parameter(Mandatory)][string]$WorkspaceRoot)
    Join-Path $WorkspaceRoot 'output\roadmap-task-queue.jsonl'
}

function Get-RoadmapDispatchTargets {
    <# Release 3.0 — the only two execution contexts a queue entry may name.
       `claude` runs Claude Code in the operator's session; `copilot` runs
       `gh agent-task create`, which needs the OAuth credential only an operator
       session holds. Both execute as the operator; neither runs in the service. #>
    return @('claude', 'copilot')
}

function Resolve-RoadmapDispatchTarget {
    <#
    .SYNOPSIS
        Pure — normalize a dispatch target, or throw with the allowed set named.
    .DESCRIPTION
        Empty resolves to `claude` for backward compatibility: entries written
        before Release 3.0 carry no dispatchTarget and must keep running as the
        Claude Code tasks they were queued as. An UNRECOGNIZED value is refused
        rather than defaulted — silently running an unknown target as `claude`
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

if ($LoadFunctionsOnly) { return }

if ([string]::IsNullOrWhiteSpace($RunId)) { throw 'RunId is required.' }
if ([string]::IsNullOrWhiteSpace($LocalRepoPath)) { throw 'LocalRepoPath is required.' }
if ([string]::IsNullOrWhiteSpace($TaskDescription)) { throw 'TaskDescription is required.' }

# A copilot entry names a GitHub repo, not a local path — `gh agent-task create`
# has nothing to run against without one. Refuse at enqueue time rather than
# letting the runner claim a task it can only fail.
if ($DispatchTarget -eq 'copilot' -and [string]::IsNullOrWhiteSpace($Repository)) {
    throw 'Repository (owner/repo) is required when DispatchTarget is copilot; gh agent-task create needs it.'
}

$entry = New-RoadmapQueueEntry -RunId $RunId -Repository $Repository -LocalRepoPath $LocalRepoPath `
    -RoadmapPath $RoadmapPath -SelectedTask $SelectedTask -TaskDescription $TaskDescription `
    -Branch $Branch -QueuedAt ((Get-Date).ToString('o')) -DispatchTarget $DispatchTarget -BaseBranch $BaseBranch

$queuePath = Get-RoadmapQueuePath -WorkspaceRoot $WorkspaceRoot
Add-RoadmapQueueEntry -QueuePath $queuePath -Entry $entry

Write-Host ("[queued] runId={0} repo={1} branch={2} target={3}" -f $entry.runId, $entry.repository, $entry.branch, $entry.dispatchTarget) -ForegroundColor Green
Write-Host ("  local repo: {0}" -f $entry.localRepoPath) -ForegroundColor DarkGray
Write-Host ("  queue     : {0}" -f $queuePath) -ForegroundColor DarkGray
Write-Host '  Run the local runner (as yourself) to execute it:' -ForegroundColor DarkGray
Write-Host '    pwsh -File scripts/Invoke-RoadmapTaskRunner.ps1 -Once' -ForegroundColor DarkGray
