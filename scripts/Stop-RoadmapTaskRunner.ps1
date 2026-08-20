<#
.SYNOPSIS
    Ask the local roadmap task runner to stop, and confirm that it did.

.DESCRIPTION
    Release 2.9. A headless runner is launched DETACHED on purpose -- a tool
    timeout must not strand a claimed task mid-run -- which means it outlives
    the session that started it. On 2026-08-19 one survived 17 hours, raced
    the api-host smoke twice, and committed the operator's in-flight work onto
    local `main` before the repo-root guard existed. Stopping it meant finding
    a PID and calling `Stop-Process`: a step an agent may not be permitted to
    take, and one an operator has to look up.

    This is the front door. It writes the stop marker the runner already
    watches, then waits for the runner to actually go away -- because a request
    that is never confirmed is indistinguishable from one that was ignored.

    The stop is honored at a POLL BOUNDARY, between tasks. If a `claude`
    session is running right now, the runner finishes that task first; that is
    deliberate, since abandoning it would leave a claimed item with no owner
    and a half-written branch. Expect the wait to take up to one task's
    remaining time, not one poll interval.

    If the runner is already gone, this reports that and removes any marker it
    wrote, so a leftover file cannot stop the NEXT runner at its first poll.

.PARAMETER WorkspaceRoot
    Repository whose runner should stop. Defaults to this repo.

.PARAMETER TimeoutSeconds
    How long to wait for the runner to exit before reporting that it is still
    running. Default 900 (15 minutes) -- long enough for a task in flight.

.PARAMETER Force
    Also stop the process if it is still alive when the timeout expires. Off
    by default: the graceful path leaves the queue coherent, and a kill does
    not.

.EXAMPLE
    pwsh -File scripts/Stop-RoadmapTaskRunner.ps1
.EXAMPLE
    pwsh -File scripts/Stop-RoadmapTaskRunner.ps1 -TimeoutSeconds 60 -Force
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter()][string]$WorkspaceRoot = (Split-Path -Parent $PSScriptRoot),
    [Parameter()][ValidateRange(5, 3600)][int]$TimeoutSeconds = 900,
    [Parameter()][switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$heartbeatPath = Join-Path $WorkspaceRoot 'output\roadmap-task-runner.heartbeat.json'
$stopFilePath = Join-Path $WorkspaceRoot 'output\roadmap-task-runner.stop'

function Get-RunnerProcessId {
    param([Parameter(Mandatory)][string]$HeartbeatPath)
    if (-not (Test-Path -LiteralPath $HeartbeatPath)) { return 0 }
    try {
        $beat = Get-Content -LiteralPath $HeartbeatPath -Raw -Encoding UTF8 | ConvertFrom-Json
        return [int]$beat.pid
    }
    catch { return 0 }
}

$runnerPid = Get-RunnerProcessId -HeartbeatPath $heartbeatPath
$alive = ($runnerPid -gt 0) -and ($null -ne (Get-Process -Id $runnerPid -ErrorAction Ignore))

if (-not $alive) {
    # No runner. Clear any marker so it cannot stop the next one.
    if (Test-Path -LiteralPath $stopFilePath) {
        Remove-Item -LiteralPath $stopFilePath -Force -ErrorAction SilentlyContinue
        Write-Host 'No runner is alive; removed a leftover stop marker so the next runner starts cleanly.' -ForegroundColor Yellow
    }
    else {
        Write-Host ("No runner is alive (heartbeat {0})." -f $(if ($runnerPid -gt 0) { "names pid $runnerPid, which is gone" } else { 'absent or unreadable' })) -ForegroundColor DarkGray
    }
    return [pscustomobject]@{ stopped = $true; wasRunning = $false; processId = $runnerPid; forced = $false }
}

if (-not $PSCmdlet.ShouldProcess("runner pid $runnerPid", 'Request stop at the next poll boundary')) {
    return [pscustomobject]@{ stopped = $false; wasRunning = $true; processId = $runnerPid; forced = $false; reason = 'what-if' }
}

$null = New-Item -ItemType Directory -Path (Split-Path -Parent $stopFilePath) -Force
Set-Content -LiteralPath $stopFilePath -Value ((Get-Date).ToUniversalTime().ToString('o')) -Encoding UTF8
Write-Host ("Stop requested for runner pid {0}. It exits at its next poll boundary; a task already running finishes first." -f $runnerPid) -ForegroundColor Cyan

$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
while ((Get-Date) -lt $deadline) {
    if ($null -eq (Get-Process -Id $runnerPid -ErrorAction Ignore)) {
        Write-Host ("Runner pid {0} has exited." -f $runnerPid) -ForegroundColor Green
        # The runner consumes the marker itself; clear it if it could not.
        if (Test-Path -LiteralPath $stopFilePath) { Remove-Item -LiteralPath $stopFilePath -Force -ErrorAction SilentlyContinue }
        return [pscustomobject]@{ stopped = $true; wasRunning = $true; processId = $runnerPid; forced = $false }
    }
    Start-Sleep -Seconds 3
}

if ($Force) {
    Write-Host ("Runner pid {0} did not exit within {1}s; stopping it. A task in flight loses its session -- check the run summary for a claimed item with no owner." -f $runnerPid, $TimeoutSeconds) -ForegroundColor Yellow
    Stop-Process -Id $runnerPid -Force -Confirm:$false
    if (Test-Path -LiteralPath $stopFilePath) { Remove-Item -LiteralPath $stopFilePath -Force -ErrorAction SilentlyContinue }
    return [pscustomobject]@{ stopped = $true; wasRunning = $true; processId = $runnerPid; forced = $true }
}

# Not stopped, and said so. The marker stays: the runner will honor it when
# its current task ends, so leaving it is the useful outcome.
Write-Host ("Runner pid {0} is still running after {1}s. The stop marker remains, so it will exit when its current task finishes. Re-run with -Force to stop it now." -f $runnerPid, $TimeoutSeconds) -ForegroundColor Yellow
return [pscustomobject]@{ stopped = $false; wasRunning = $true; processId = $runnerPid; forced = $false; reason = 'timeout-still-running' }
