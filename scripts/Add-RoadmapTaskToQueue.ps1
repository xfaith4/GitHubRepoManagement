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

function New-RoadmapQueueEntry {
    <# Pure: build the queue entry object. `status='queued'` is the runner's cue
       to claim it. `prompt` is the full task text handed to `claude`. #>
    param(
        [Parameter(Mandatory)][string]$RunId,
        [string]$Repository,
        [Parameter(Mandatory)][string]$LocalRepoPath,
        [string]$RoadmapPath,
        [string]$SelectedTask,
        [Parameter(Mandatory)][string]$TaskDescription,
        [string]$Branch,
        [Parameter(Mandatory)][string]$QueuedAt
    )
    if ([string]::IsNullOrWhiteSpace($Branch)) { $Branch = "roadmap/$RunId" }
    return [ordered]@{
        schemaVersion = '1'
        runId         = $RunId
        status        = 'queued'
        repository    = $Repository
        localRepoPath = $LocalRepoPath
        roadmapPath   = $RoadmapPath
        selectedTask  = $SelectedTask
        branch        = $Branch
        prompt        = $TaskDescription
        queuedAt      = $QueuedAt
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

$entry = New-RoadmapQueueEntry -RunId $RunId -Repository $Repository -LocalRepoPath $LocalRepoPath `
    -RoadmapPath $RoadmapPath -SelectedTask $SelectedTask -TaskDescription $TaskDescription `
    -Branch $Branch -QueuedAt ((Get-Date).ToString('o'))

$queuePath = Get-RoadmapQueuePath -WorkspaceRoot $WorkspaceRoot
Add-RoadmapQueueEntry -QueuePath $queuePath -Entry $entry

Write-Host ("[queued] runId={0} repo={1} branch={2}" -f $entry.runId, $entry.repository, $entry.branch) -ForegroundColor Green
Write-Host ("  local repo: {0}" -f $entry.localRepoPath) -ForegroundColor DarkGray
Write-Host ("  queue     : {0}" -f $queuePath) -ForegroundColor DarkGray
Write-Host '  Run the local runner (as yourself) to execute it:' -ForegroundColor DarkGray
Write-Host '    pwsh -File scripts/Invoke-RoadmapTaskRunner.ps1 -Once' -ForegroundColor DarkGray
