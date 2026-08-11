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

# The queue contract lives in a param-less library, deliberately. Callers that
# only want these functions dot-source something — and dot-sourcing runs the
# target in the CALLER'S scope, assigning its `param()` variables there too.
# When those functions lived in this file, the API host's dispatch route
# dot-sourced it beside its own `$runId` and got the empty string back from this
# script's `$RunId` parameter, killing the guided-improvement wizard's last step.
# Resolved from this script's own location, not from -WorkspaceRoot: that
# parameter names the SCAN TARGET, which need not be this repo.
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'backend\modules\automation\Automation.RoadmapQueue.ps1')

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
