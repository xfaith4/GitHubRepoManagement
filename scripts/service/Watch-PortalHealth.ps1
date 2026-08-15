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
    [string]$BaseUrl = 'https://127.0.0.1:7071',
    [string]$HealthPath = '/health/live',
    [int]$TimeoutSec = 5,
    [int]$FailureThreshold = 3,
    [int]$Port = 7071,
    [string]$ServiceName = 'RepoMgmtPortal',
    [string]$StatePath,
    [string]$LedgerPath,
    # Path to the host's operation heartbeat. A failed probe while THIS file
    # shows fresh progress means the host is busy, not frozen.
    [string]$OperationStatePath,
    # How stale the host's last progress record may be before a failing probe is
    # treated as a freeze. This is a NO-PROGRESS budget, deliberately NOT the
    # 900s request deadline: a scan that keeps reporting progress is never
    # restarted however long it runs, while a host that stops moving is caught in
    # ~2 minutes. Clamped up if it is below the host's declared heartbeat cadence
    # (see Test-WatchdogToleranceInvariant).
    [int]$NoProgressToleranceSeconds = 120,
    # Fallback cadence when no heartbeat file exists to declare one.
    [int]$DefaultHeartbeatIntervalSeconds = 30,
    [string]$WebhookUrl,
    [switch]$DryRun,
    [switch]$LoadFunctionsOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($WorkspaceRoot)) {
    $WorkspaceRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}

# Reuse the host's own heartbeat reader rather than reimplementing the parse —
# a second copy of the shape is how the two sides drift apart.
. (Join-Path $WorkspaceRoot 'backend\api-host\OperationHeartbeat.ps1')

# ── Pure decision logic (unit-tested by the module smoke — no elevation) ──────
function Test-WatchdogToleranceInvariant {
    <#
      Configuration invariant: the no-progress tolerance must be at least the
      producer's own heartbeat interval, or a legitimately slow stage reads as
      stale and the restart loop returns through the back door.

      The interval is taken from the heartbeat file itself — the host declares
      the cadence it actually promises — so the two sides cannot drift apart by
      someone editing a number in one file. Returns the verdict plus the minimum
      the caller must use; the caller clamps UP, never down, because being too
      patient delays freeze recovery while being too eager kills healthy work.
    #>
    param(
        [Parameter(Mandatory)][int]$ToleranceSeconds,
        [Parameter(Mandatory)][int]$HeartbeatIntervalSeconds,
        # Two missed heartbeats before calling it stale: one missed write is a
        # slow disk or a GC pause, not a freeze.
        [int]$SafetyFactor = 2
    )
    $required = [int]($HeartbeatIntervalSeconds * $SafetyFactor)
    $valid = ($ToleranceSeconds -ge $required)
    return [pscustomobject]@{
        Valid                    = $valid
        RequiredSeconds          = $required
        EffectiveSeconds         = [math]::Max($ToleranceSeconds, $required)
        HeartbeatIntervalSeconds = $HeartbeatIntervalSeconds
        Reason                   = if ($valid) { "tolerance ${ToleranceSeconds}s >= required ${required}s" } else { "tolerance ${ToleranceSeconds}s < required ${required}s (heartbeat ${HeartbeatIntervalSeconds}s x$SafetyFactor); clamped up" }
    }
}

function Resolve-WatchdogAction {
    <#
      Given the current probe result, the prior consecutive-failure count, and
      the host's declared operation progress, decide whether to restart.

      A failed probe is NOT evidence of a freeze on this host: it is
      single-threaded, so any long scan makes /health/live unanswerable. The
      discriminator is PROGRESS — the host publishes what it is doing and when it
      last moved, and a restart is suppressed only while that statement is fresh.

      Progress, not CPU, is the contract. A healthy scan can block for minutes on
      GitHub, `git`/`gh` child processes, or filesystem I/O while accruing almost
      no CPU, and a runaway loop can burn CPU while achieving nothing — so
      CpuAdvanced is carried for the ledger as corroboration and is never on its
      own a reason to skip a restart.

      Suppression cannot become permanent: it is gated on the AGE of the last
      progress record, so an orphaned marker (host killed mid-scan) goes stale by
      itself and ordinary policy resumes with no cleanup step. Failures keep
      counting while suppressed, so the moment progress does go stale the
      threshold is already satisfied and recovery is immediate rather than
      three probes away.

      ProgressAgeSeconds is $null whenever there is no active, readable operation
      — missing file, unparseable JSON, inactive marker. Absence of proof is
      never suppression.
    #>
    param(
        [Parameter(Mandatory)][bool]$Healthy,
        [Parameter(Mandatory)][int]$PriorFailures,
        [Parameter(Mandatory)][int]$Threshold,
        [object]$ProgressAgeSeconds = $null,
        [string]$OperationName = '',
        [int]$NoProgressToleranceSeconds = 0,
        [object]$CpuAdvanced = $null
    )
    if ($Healthy) {
        return [pscustomobject]@{ Action = 'none'; Failures = 0; Reason = 'healthy'; Suppressed = $false; OperationName = $OperationName; ProgressAgeSeconds = $ProgressAgeSeconds; CpuAdvanced = $CpuAdvanced }
    }

    $next = $PriorFailures + 1
    $hasProgress = ($null -ne $ProgressAgeSeconds)
    $progressFresh = $hasProgress -and ([double]$ProgressAgeSeconds -le $NoProgressToleranceSeconds)

    if ($progressFresh) {
        # Working, not frozen. Keep counting so a later staleness restarts at once.
        return [pscustomobject]@{
            Action = 'none'; Failures = $next; Suppressed = $true
            Reason = ("unhealthy x{0} but operation '{1}' progressed {2:N0}s ago (<= {3}s tolerance) — busy, not frozen" -f $next, $OperationName, [double]$ProgressAgeSeconds, $NoProgressToleranceSeconds)
            OperationName = $OperationName; ProgressAgeSeconds = $ProgressAgeSeconds; CpuAdvanced = $CpuAdvanced
        }
    }

    if ($next -ge $Threshold) {
        $why = if ($hasProgress) {
            ("operation '{0}' has not progressed for {1:N0}s (> {2}s tolerance)" -f $OperationName, [double]$ProgressAgeSeconds, $NoProgressToleranceSeconds)
        } else { 'no active operation' }
        return [pscustomobject]@{
            Action = 'restart'; Failures = 0; Suppressed = $false
            Reason = "unhealthy x$next >= threshold $Threshold; $why"
            OperationName = $OperationName; ProgressAgeSeconds = $ProgressAgeSeconds; CpuAdvanced = $CpuAdvanced
        }
    }
    return [pscustomobject]@{
        Action = 'none'; Failures = $next; Suppressed = $false
        Reason = "unhealthy x$next < threshold $Threshold"
        OperationName = $OperationName; ProgressAgeSeconds = $ProgressAgeSeconds; CpuAdvanced = $CpuAdvanced
    }
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
    param([string]$Path, [int]$ConsecutiveFailures, [string]$LastAction, [object]$LastCpuSeconds = $null)
    if (-not $Path) { return }
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { $null = New-Item -ItemType Directory -Path $dir -Force }
    $obj = [ordered]@{
        consecutiveFailures = $ConsecutiveFailures
        lastAction          = $LastAction
        updatedAt           = (Get-Date).ToString('o')
        # Diagnostic only — the next cycle diffs this for the ledger's
        # cpuAdvanced field. Never an input to the restart decision.
        lastCpuSeconds      = $LastCpuSeconds
    }
    ($obj | ConvertTo-Json -Depth 4) | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Write-WatchdogLedger {
    param([string]$Path, [string]$EventName, [hashtable]$Data)
    if (-not $Path) { return }
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { $null = New-Item -ItemType Directory -Path $dir -Force }
    $record = [ordered]@{ timestamp = (Get-Date).ToString('o'); event = $EventName }
    if ($Data) { foreach ($k in $Data.Keys) { $record[$k] = $Data[$k] } }
    $line = ($record | ConvertTo-Json -Depth 6 -Compress)
    Add-Content -LiteralPath $Path -Value $line -Encoding UTF8
}

function Test-PortalHealth {
    <# Health probe. The portal serves HTTPS whenever a TLS cert is loaded
       (REPO_MGMT_TLS_PFX / network.tls.pfxPath) — as the RepoMgmtPortal service
       does — so an https URI MUST skip cert validation: the portal cert is
       self-signed and this is a loopback liveness check, not a security
       boundary. Probing http against that TLS listener fails the handshake and
       would falsely mark a healthy host unhealthy (the original bug). 5.1-safe:
       a non-2xx, a TLS handshake failure, or a timeout (frozen host) all throw
       and are caught as unhealthy; cert-skip uses -SkipCertificateCheck on
       pwsh 6+ and the ServicePointManager callback on Windows PowerShell 5.1. #>
    param([string]$Uri, [int]$TimeoutSec)
    $splat = @{ Uri = $Uri; TimeoutSec = $TimeoutSec; UseBasicParsing = $true }
    $isHttps = ($Uri -match '^(?i)https:')
    $touchedCallback = $false
    $prevCallback = $null
    try {
        if ($isHttps) {
            if ($PSVersionTable.PSVersion.Major -ge 6) {
                $splat['SkipCertificateCheck'] = $true
            }
            else {
                $prevCallback = [System.Net.ServicePointManager]::ServerCertificateValidationCallback
                [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
                $touchedCallback = $true
            }
        }
        $resp = Invoke-WebRequest @splat
        $ok = ([int]$resp.StatusCode -ge 200 -and [int]$resp.StatusCode -lt 300)
        return [pscustomobject]@{ Healthy = $ok; StatusCode = [int]$resp.StatusCode; Detail = "HTTP $($resp.StatusCode)" }
    }
    catch {
        return [pscustomobject]@{ Healthy = $false; StatusCode = 0; Detail = $_.Exception.Message }
    }
    finally {
        if ($touchedCallback) { [System.Net.ServicePointManager]::ServerCertificateValidationCallback = $prevCallback }
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

if (-not $OperationStatePath) { $OperationStatePath = Join-Path $WorkspaceRoot 'output\logs\portal-operation.json' }

$prior = Get-WatchdogState -Path $StatePath
$probe = Test-PortalHealth -Uri "$BaseUrl$HealthPath" -TimeoutSec $TimeoutSec

# Operation progress — the discriminator between "busy" and "frozen". Every
# failure mode here ($null) falls through to ordinary restart policy.
$operationState = Read-PortalOperationState -Path $OperationStatePath
$progressAge = Get-PortalOperationProgressAge -State $operationState
$operationName = ''
$declaredHeartbeat = $DefaultHeartbeatIntervalSeconds
if ($null -ne $operationState) {
    if (Test-PortalStateHasProperty -State $operationState -Name 'operation') {
        $operationName = [string]$operationState.operation
    }
    if (Test-PortalStateHasProperty -State $operationState -Name 'heartbeatIntervalSeconds') {
        $declared = 0
        if ([int]::TryParse([string]$operationState.heartbeatIntervalSeconds, [ref]$declared) -and $declared -gt 0) {
            $declaredHeartbeat = $declared
        }
    }
}

# Enforce the tolerance invariant against the cadence the HOST declares, and
# clamp up if it is short — never silently run a tolerance that would make a
# healthy slow stage look stale.
$invariant = Test-WatchdogToleranceInvariant -ToleranceSeconds $NoProgressToleranceSeconds -HeartbeatIntervalSeconds $declaredHeartbeat
$effectiveTolerance = $invariant.EffectiveSeconds
if (-not $invariant.Valid) {
    Write-WatchdogLedger -Path $LedgerPath -EventName 'config-invalid' -Data @{
        reason = $invariant.Reason; configuredTolerance = $NoProgressToleranceSeconds; effectiveTolerance = $effectiveTolerance
    }
}

# CPU delta: recorded as corroboration only. Never consulted by the decision —
# a scan blocked on GitHub or git accrues no CPU while perfectly healthy.
$cpuAdvanced = $null
$cpuSampleError = ''
try {
    $listenerPid = (Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty OwningProcess)
    if ($listenerPid) {
        $cpuNow = (Get-Process -Id $listenerPid -ErrorAction SilentlyContinue).CPU
        $cpuPrior = $null
        $priorState = Read-PortalOperationState -Path $StatePath
        if ($null -ne $priorState -and (Test-PortalStateHasProperty -State $priorState -Name 'lastCpuSeconds')) {
            $cpuPrior = $priorState.lastCpuSeconds
        }
        if ($null -ne $cpuNow -and $null -ne $cpuPrior) { $cpuAdvanced = ([double]$cpuNow -gt [double]$cpuPrior) }
        $script:LastCpuSeconds = $cpuNow
    }
}
catch {
    # Diagnostic-only sample: never blocks the decision, but the reason is
    # carried to the ledger rather than dropped into an empty catch.
    $cpuSampleError = $_.Exception.Message
}

$decision = Resolve-WatchdogAction -Healthy $probe.Healthy -PriorFailures $prior -Threshold $FailureThreshold `
    -ProgressAgeSeconds $progressAge -OperationName $operationName `
    -NoProgressToleranceSeconds $effectiveTolerance -CpuAdvanced $cpuAdvanced

Write-WatchdogLedger -Path $LedgerPath -EventName $(if ($probe.Healthy) { 'probe-ok' } else { 'probe-fail' }) -Data @{
    statusCode = $probe.StatusCode; detail = $probe.Detail; priorFailures = $prior; decision = $decision.Action; reason = $decision.Reason; dryRun = [bool]$DryRun
    operation = $operationName; progressAgeSeconds = $progressAge; suppressed = [bool]$decision.Suppressed
    noProgressToleranceSeconds = $effectiveTolerance; cpuAdvanced = $cpuAdvanced; cpuSampleError = $cpuSampleError
}

if ($decision.Action -eq 'restart') {
    Write-WatchdogLedger -Path $LedgerPath -EventName 'restart-triggered' -Data @{ reason = $decision.Reason; dryRun = [bool]$DryRun }
    if ($DryRun) {
        Write-Host ("[DRYRUN] would force-kill port {0} and Restart-Service {1} ({2})" -f $Port, $ServiceName, $decision.Reason) -ForegroundColor Yellow
    }
    else {
        $restart = Invoke-PortalRestart -Port $Port -ServiceName $ServiceName
        Write-WatchdogLedger -Path $LedgerPath -EventName $(if ($restart.serviceRestarted) { 'restart-done' } else { 'restart-failed' }) -Data @{
            killedPids = $restart.killedPids; serviceRestarted = $restart.serviceRestarted; errors = $restart.errors
        }
        Send-WatchdogAlert -WebhookUrl $WebhookUrl -Payload @{
            event = 'execution.failed'; source = 'portal-watchdog'; service = $ServiceName
            reason = $decision.Reason; killedPids = $restart.killedPids; serviceRestarted = $restart.serviceRestarted
            timestamp = (Get-Date).ToString('o')
        }
    }
}

Set-WatchdogState -Path $StatePath -ConsecutiveFailures $decision.Failures -LastAction $decision.Action -LastCpuSeconds $script:LastCpuSeconds

Write-Host ("[watchdog] healthy={0} priorFailures={1} -> action={2} ({3})" -f $probe.Healthy, $prior, $decision.Action, $decision.Reason) -ForegroundColor $(if ($probe.Healthy) { 'Green' } elseif ($decision.Action -eq 'restart') { 'Red' } else { 'Yellow' })
exit 0
