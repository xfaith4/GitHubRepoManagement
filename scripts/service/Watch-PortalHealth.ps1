<#
.SYNOPSIS
    External liveness watchdog for the always-on RepoMgmtPortal service.

.DESCRIPTION
    The portal host (a shawl-wrapped pwsh process, LocalSystem) can *freeze* —
    process alive, port 7071 still Listen, but not responding (flat CPU, stuck
    CloseWait). shawl restarts only on process EXIT, so a hung-but-alive host is
    never recovered and squats the port. This watchdog runs on an interval (as a
    Scheduled Task in SYSTEM context — see Install-PortalWatchdog.ps1), probes
    GET /health/live, and after N consecutive failures force-kills the frozen
    host and restarts the service.

    Design for testability: the decision is a pure function (Resolve-WatchdogAction)
    that the module smoke exercises without any elevation; only the actual
    kill + Restart-Service (Invoke-PortalRestart) needs SYSTEM, and it is skipped
    under -DryRun. Consecutive-failure count persists in a state file so the
    threshold spans separate scheduled invocations. Every decision is appended to
    an append-only JSONL ledger, and a restart fires the execution.failed webhook
    so a freeze is visible, not silent.

    PowerShell 5.1-compatible (uses try/catch around Invoke-WebRequest rather than
    -SkipHttpErrorCheck), so it runs under Windows PowerShell or pwsh 7.

.PARAMETER LoadFunctionsOnly
    Dot-source the functions without running the watchdog body (used by the smoke).

.PARAMETER DryRun
    Decide and log, but never kill or restart — for safe verification.

.EXAMPLE
    pwsh -File scripts/service/Watch-PortalHealth.ps1 -DryRun
    One probe/decision cycle against the live host; logs, changes nothing.
#>
[CmdletBinding()]
param(
    [string]$WorkspaceRoot,
    [string]$BaseUrl = 'http://127.0.0.1:7071',
    [string]$HealthPath = '/health/live',
    [int]$TimeoutSec = 5,
    [int]$FailureThreshold = 3,
    [int]$Port = 7071,
    [string]$ServiceName = 'RepoMgmtPortal',
    [string]$StatePath,
    [string]$LedgerPath,
    [string]$WebhookUrl,
    [switch]$DryRun,
    [switch]$LoadFunctionsOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($WorkspaceRoot)) {
    $WorkspaceRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}

# ── Pure decision logic (unit-tested by the module smoke — no elevation) ──────
function Resolve-WatchdogAction {
    <#
      Given the current probe result and the prior consecutive-failure count,
      decide whether to restart. Restart fires when failures reach the threshold;
      the counter resets on success OR after a restart is triggered.
    #>
    param(
        [Parameter(Mandatory)][bool]$Healthy,
        [Parameter(Mandatory)][int]$PriorFailures,
        [Parameter(Mandatory)][int]$Threshold
    )
    if ($Healthy) {
        return [pscustomobject]@{ Action = 'none'; Failures = 0; Reason = 'healthy' }
    }
    $next = $PriorFailures + 1
    if ($next -ge $Threshold) {
        return [pscustomobject]@{ Action = 'restart'; Failures = 0; Reason = "unhealthy x$next >= threshold $Threshold" }
    }
    return [pscustomobject]@{ Action = 'none'; Failures = $next; Reason = "unhealthy x$next < threshold $Threshold" }
}

function Get-WatchdogState {
    param([string]$Path)
    if ($Path -and (Test-Path -LiteralPath $Path)) {
        try {
            $s = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
            $val = [int]$s.consecutiveFailures
            return $val
        }
        catch { return 0 }
    }
    return 0
}

function Set-WatchdogState {
    param([string]$Path, [int]$ConsecutiveFailures, [string]$LastAction)
    if (-not $Path) { return }
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { $null = New-Item -ItemType Directory -Path $dir -Force }
    $obj = [ordered]@{
        consecutiveFailures = $ConsecutiveFailures
        lastAction          = $LastAction
        updatedAt           = (Get-Date).ToString('o')
    }
    ($obj | ConvertTo-Json -Depth 4) | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Write-WatchdogLedger {
    param([string]$Path, [string]$Event, [hashtable]$Data)
    if (-not $Path) { return }
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { $null = New-Item -ItemType Directory -Path $dir -Force }
    $record = [ordered]@{ timestamp = (Get-Date).ToString('o'); event = $Event }
    if ($Data) { foreach ($k in $Data.Keys) { $record[$k] = $Data[$k] } }
    $line = ($record | ConvertTo-Json -Depth 6 -Compress)
    Add-Content -LiteralPath $Path -Value $line -Encoding UTF8
}

function Test-PortalHealth {
    <# HTTP probe. 5.1-safe: a non-2xx or a timeout (frozen host that never
       responds) both throw and are caught as unhealthy. #>
    param([string]$Uri, [int]$TimeoutSec)
    try {
        $resp = Invoke-WebRequest -Uri $Uri -TimeoutSec $TimeoutSec -UseBasicParsing
        $ok = ([int]$resp.StatusCode -ge 200 -and [int]$resp.StatusCode -lt 300)
        return [pscustomobject]@{ Healthy = $ok; StatusCode = [int]$resp.StatusCode; Detail = "HTTP $($resp.StatusCode)" }
    }
    catch {
        return [pscustomobject]@{ Healthy = $false; StatusCode = 0; Detail = $_.Exception.Message }
    }
}

function Invoke-PortalRestart {
    <# The elevated action: force-kill whatever pwsh host is Listen-ing on the
       port (SYSTEM can kill the frozen host), then restart the service. Returns
       a result object; never throws so the watchdog run always completes. #>
    param([int]$Port, [string]$ServiceName)
    $result = [ordered]@{ killedPids = @(); serviceRestarted = $false; errors = @() }
    try {
        $pids = @(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty OwningProcess -Unique)
        foreach ($procId in $pids) {
            if ($procId -and $procId -ne 0 -and $procId -ne $PID) {
                try { Stop-Process -Id $procId -Force -ErrorAction Stop; $result.killedPids += $procId }
                catch { $result.errors += "kill $procId : $($_.Exception.Message)" }
            }
        }
    }
    catch { $result.errors += "enumerate port $Port : $($_.Exception.Message)" }
    try {
        Restart-Service -Name $ServiceName -Force -ErrorAction Stop
        $result.serviceRestarted = $true
    }
    catch { $result.errors += "restart $ServiceName : $($_.Exception.Message)" }
    return [pscustomobject]$result
}

function Send-WatchdogAlert {
    param([string]$WebhookUrl, [hashtable]$Payload)
    if ([string]::IsNullOrWhiteSpace($WebhookUrl)) { return }
    try {
        $body = ($Payload | ConvertTo-Json -Depth 6)
        $null = Invoke-WebRequest -Uri $WebhookUrl -Method Post -Body $body -ContentType 'application/json' -TimeoutSec 10 -UseBasicParsing
    }
    catch { }
}

if ($LoadFunctionsOnly) { return }

# ── Watchdog cycle ───────────────────────────────────────────────────────────
if (-not $StatePath) { $StatePath = Join-Path $WorkspaceRoot 'output\logs\service-watchdog.state.json' }
if (-not $LedgerPath) { $LedgerPath = Join-Path $WorkspaceRoot 'output\logs\service-watchdog.jsonl' }

$prior = Get-WatchdogState -Path $StatePath
$probe = Test-PortalHealth -Uri "$BaseUrl$HealthPath" -TimeoutSec $TimeoutSec
$decision = Resolve-WatchdogAction -Healthy $probe.Healthy -PriorFailures $prior -Threshold $FailureThreshold

Write-WatchdogLedger -Path $LedgerPath -Event $(if ($probe.Healthy) { 'probe-ok' } else { 'probe-fail' }) -Data @{
    statusCode = $probe.StatusCode; detail = $probe.Detail; priorFailures = $prior; decision = $decision.Action; reason = $decision.Reason; dryRun = [bool]$DryRun
}

if ($decision.Action -eq 'restart') {
    Write-WatchdogLedger -Path $LedgerPath -Event 'restart-triggered' -Data @{ reason = $decision.Reason; dryRun = [bool]$DryRun }
    if ($DryRun) {
        Write-Host ("[DRYRUN] would force-kill port {0} and Restart-Service {1} ({2})" -f $Port, $ServiceName, $decision.Reason) -ForegroundColor Yellow
    }
    else {
        $restart = Invoke-PortalRestart -Port $Port -ServiceName $ServiceName
        Write-WatchdogLedger -Path $LedgerPath -Event $(if ($restart.serviceRestarted) { 'restart-done' } else { 'restart-failed' }) -Data @{
            killedPids = $restart.killedPids; serviceRestarted = $restart.serviceRestarted; errors = $restart.errors
        }
        Send-WatchdogAlert -WebhookUrl $WebhookUrl -Payload @{
            event = 'execution.failed'; source = 'portal-watchdog'; service = $ServiceName
            reason = $decision.Reason; killedPids = $restart.killedPids; serviceRestarted = $restart.serviceRestarted
            timestamp = (Get-Date).ToString('o')
        }
    }
}

Set-WatchdogState -Path $StatePath -ConsecutiveFailures $decision.Failures -LastAction $decision.Action

Write-Host ("[watchdog] healthy={0} priorFailures={1} -> action={2} ({3})" -f $probe.Healthy, $prior, $decision.Action, $decision.Reason) -ForegroundColor $(if ($probe.Healthy) { 'Green' } elseif ($decision.Action -eq 'restart') { 'Red' } else { 'Yellow' })
exit 0
