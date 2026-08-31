[CmdletBinding()]
param(
    # Derived from this script's location rather than a hardcoded drive letter —
    # the previous 'G:\...' default no longer resolves on this machine (same fix
    # as Invoke-ModuleSmokeTest.ps1; ROADMAP Lane 0.3).
    [string]$WorkspaceRoot = (Split-Path -Parent $PSScriptRoot),
    # 127.0.0.1, NOT localhost: the host binds IPv4 loopback only, and on this
    # machine the firewall silently drops (rather than refuses) connections to
    # [::1]:7071, so every 'localhost' request burned ~2s in a dual-stack
    # fallback and left each connect at the mercy of firewall timing. Direct
    # IPv4 makes each request ~2ms and removes that fragility entirely.
    # 7171, NOT 7071. 7071 is the port the INSTALLED PORTAL SERVICE listens on,
    # and the api-host's startup terminates whatever already holds the port it
    # is told to bind -- by design, so a restart-in-place is not blocked by its
    # own stale process. Defaulting this gate to 7071 pointed that mechanism at
    # the operator's live service: run the smoke directly, with no -Port, and it
    # tries to kill the portal. Observed 2026-08-29:
    #   "Port 7071 is already in use by pwsh (PID 35160). Terminating it before startup."
    # It survived only because an unelevated smoke cannot kill a LocalSystem
    # service -- luck, not design. Invoke-TestSuite.ps1 always passed 7171
    # explicitly, so the suite was never exposed and the default went unnoticed.
    [string]$BaseUrl = 'http://127.0.0.1:7171',
    [int]$Port = 7171,
    # Per-request timeout. Cold cache routes that scan a full workspace
    # (e.g. /api/portfolio/assessment) can legitimately take well over 30s on a
    # large real workspace, so the default is generous enough to let them finish
    # rather than tripping a false "hang" before later steps run.
    [int]$RequestTimeoutSec = 180,
    # Cold full-portfolio scans on the real 75-repo workspace outrun 180s, which
    # is why this smoke previously needed -RequestTimeoutSec 900 to pass locally.
    # Raising the client timeout for exactly the routes the host already puts on
    # its extended deadline tier removes the workaround without blunting the
    # false-hang detection on ordinary routes.
    [int]$ScanRequestTimeoutSec = 900
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Same route classification the host uses for its request deadline, so the
# client timeout and the server deadline can never drift apart.
. (Join-Path $WorkspaceRoot 'backend\api-host\RequestDeadline.ps1')

# -Port alone used to boot the host on the requested port while BaseUrl stayed
# pinned to :7071 — so the run silently exercised whatever host was ALREADY
# listening there (typically the operator's live portal) and reported its
# behavior as the result. Every assertion still "ran"; none of them tested the
# host under test. Derive the URL from the port unless the caller set both.
if (-not $PSBoundParameters.ContainsKey('BaseUrl') -and $PSBoundParameters.ContainsKey('Port')) {
    $BaseUrl = "http://127.0.0.1:$Port"
}
$BaseUrl = $BaseUrl.TrimEnd('/')
Write-Host ("[INFO] api-host smoke targeting {0} (host boots on port {1})" -f $BaseUrl, $Port) -ForegroundColor DarkGray

# Declared BEFORE the try so the finally block can always read them. Under
# StrictMode an early failure would otherwise make the finally throw
# "variable ... has not been set" and replace the actual error with a bogus one.
#
# This smoke NO LONGER WRITES the git-tracked settings file. The host is pointed
# at a private copy through REPO_MGMT_SETTINGS_PATH (see the isolation block
# below), so the tracked bytes are captured here only to PROVE the file was
# never touched. That assertion is worth more than the restore it replaces: a
# restore still leaves a ~10-minute window in which the live portal reads the
# fixture path, and on 2026-08-29 that emptied the operator's console
# mid-session with nothing on screen connecting it to a test run.
$script:TrackedSettingsPath = Join-Path $WorkspaceRoot 'backend\config\settings.json'
$script:TrackedSettingsAtStart = if (Test-Path -LiteralPath $script:TrackedSettingsPath) {
    Get-Content -LiteralPath $script:TrackedSettingsPath -Raw -Encoding UTF8
} else { $null }
# The copy the HOST reads and writes for the whole run; assigned once $smokeRoot
# exists, beside the queue isolation.
$script:HostSettingsPath = $null

$hostScript = Join-Path $WorkspaceRoot 'backend\api-host\Start-RepoManagementApiHost.ps1'
$smokeRoot = Join-Path $WorkspaceRoot 'output\smoke\api-host'
$null = New-Item -ItemType Directory -Path $smokeRoot -Force
$logPath = Join-Path $smokeRoot 'api-host-smoke.log'

function Invoke-ApiRequest {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Method,
        [Parameter(Mandatory = $true)]
        [string]$Uri,
        [Parameter()]
        [object]$Body
    )

    # Scan routes get the same extended budget the host's deadline gives them;
    # everything else keeps the tighter timeout so a real hang still surfaces.
    $requestPath = try { ([uri]$Uri).AbsolutePath } catch { $Uri }
    $effectiveTimeoutSec = Get-RequestDeadlineSecondsForPath -Path $requestPath `
        -DefaultSeconds $RequestTimeoutSec `
        -ScanSeconds ([Math]::Max($RequestTimeoutSec, $ScanRequestTimeoutSec))

    $invokeSplat = @{
        Uri = $Uri
        Method = $Method
        SkipHttpErrorCheck = $true
        # On pwsh 7.4+ TimeoutSec is an alias of ConnectionTimeoutSeconds and
        # sets HttpClient.Timeout, so this bounds the whole request including
        # the connect phase — a stalled connect cannot hang the harness.
        TimeoutSec = $effectiveTimeoutSec
    }

    if ($null -ne $Body) {
        $invokeSplat.ContentType = 'application/json'
        $invokeSplat.Body = ($Body | ConvertTo-Json -Depth 8)
    }

    # The booted host inherits this environment: when a machine-level
    # REPO_MGMT_API_KEY is set (Release 2.2 auth), the host enforces it, so the
    # smoke must send it. Unset (CI) means auth is off and no header is sent.
    $smokeApiKey = [Environment]::GetEnvironmentVariable('REPO_MGMT_API_KEY')
    if (-not [string]::IsNullOrWhiteSpace($smokeApiKey)) {
        $invokeSplat.Headers = @{ 'X-Api-Key' = $smokeApiKey }
    }

    $response = Invoke-WebRequest @invokeSplat
    $json = $null
    if (-not [string]::IsNullOrWhiteSpace($response.Content)) {
        $contentType = [string]$response.Headers['Content-Type']
        $looksLikeJson = $response.Content.TrimStart() -match '^[\{\[]'
        if ($contentType -like 'application/json*' -or $looksLikeJson) {
            try { $json = $response.Content | ConvertFrom-Json } catch { $json = $null }
        }
    }

    return [pscustomobject]@{
        StatusCode = [int]$response.StatusCode
        ContentType = [string]$response.Headers['Content-Type']
        Content = [string]$response.Content
        Json = $json
    }
}

function Assert-Not503 {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [object]$Response
    )

    if ([int]$Response.StatusCode -eq 503) {
        throw "$Name returned HTTP 503"
    }
}

function Wait-ForPortfolioIndex {
    <#
    .SYNOPSIS
        Waits until the background refresh has indexed the portfolio.
    .DESCRIPTION
        No route scans on the request thread any more. A cache miss - including
        ?refresh=true - answers immediately with what is on disk and kicks an
        out-of-process worker, because scanning inline froze every other route
        for the length of the sweep (measured: /health/live at 313.9s).

        Steps that write fixtures to disk and then assert they are indexed must
        therefore wait for that worker. This is not papering over flakiness: an
        empty or stale answer is the CORRECT response to the first request, and
        a real client has to wait for the refresh too. What would be wrong is
        asserting against a cache nothing has filled yet.

        Fails loudly on timeout, naming the log line to look for, so a worker
        that never starts is a failure rather than a hang.
    .PARAMETER RequiredRepoNames
        Repos that must appear in the index. Empty means "any non-zero index".
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$BaseUrl,
        [Parameter()]
        [string[]]$RequiredRepoNames = @(),
        [Parameter()]
        [int]$TimeoutSeconds = 300,
        # The worker reports through Write-HostLog, which writes to the host's
        # log FILE and never to the console. Without this the CI transcript
        # shows only "it did not warm" and every diagnosis is a guess.
        [Parameter()]
        [string]$HostLogPath = '',
        # Wait for the repos to be AUDITED, not merely indexed. `roadmapState`
        # comes from the roadmap cache while `maturityLevel` comes from the
        # roadmap-AUDIT cache, and the background worker fills those in
        # sequence -- so a repo can be present, parsed, and still carry the
        # L0-Absent default because its audit entry does not exist yet.
        # Callers that go on to require a maturity level must wait for the
        # cache that produces one. (Diagnosed 2026-08-19 from a CI-only
        # failure whose message read `L0-Absent roadmapState=pending`: parsed
        # fine, audited not yet.)
        [switch]$RequireAuditedMaturity
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $missing = @($RequiredRepoNames)
    $unaudited = @()
    $entryCount = 0

    while ((Get-Date) -lt $deadline) {
        # Two calls, and the order matters. /api/operations/repos serves from the
        # repos index, and that index is written by the ASSESSMENT route's
        # index-write step - not by the background worker, which only fills the
        # scan caches. Polling operations/repos alone would therefore wait
        # forever: the worker would warm the caches and nothing would ever
        # rebuild the index from them.
        #
        # ?refresh=true, not the plain route: the assessment has its own 180s
        # cache, so the plain call kept replaying a stale one-repo result and
        # never rewrote the index. refresh=true skips those cache lookups and
        # rebuilds from the freshest scan caches - which no longer means
        # scanning inline, only reading what the worker last wrote.
        $null = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/portfolio/assessment?refresh=true"

        $probe = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/operations/repos"
        $entries = @()
        if ($null -ne $probe.Json -and $null -ne $probe.Json.data) {
            $entries = @($probe.Json.data.entries)
        }
        $entryCount = @($entries).Count

        if (@($RequiredRepoNames).Count -eq 0) {
            if ($entryCount -ge 1) { return $entryCount }
        }
        else {
            $present = @($entries | ForEach-Object { [string]$_.repoName })
            $missing = @($RequiredRepoNames | Where-Object { $present -notcontains $_ })
            $unaudited = @()
            if (@($missing).Count -eq 0 -and $RequireAuditedMaturity) {
                # An explicit loop, not nested Where-Object: the inner pipeline
                # rebinds $_ to the entry, so the outer repo name has to be
                # held in a variable of its own to be comparable at all.
                foreach ($waitName in @($RequiredRepoNames)) {
                    $waitEntry = @($entries | Where-Object { [string]$_.repoName -eq $waitName }) | Select-Object -First 1
                    $waitLevel = if ($null -ne $waitEntry) { [string]$waitEntry.maturityLevel } else { '' }
                    if ([string]::IsNullOrWhiteSpace($waitLevel) -or $waitLevel -eq 'L0-Absent') {
                        $unaudited += $waitName
                    }
                }
            }
            if (@($missing).Count -eq 0 -and @($unaudited).Count -eq 0) { return $entryCount }
        }

        Start-Sleep -Seconds 5
    }

    $detail = if (@($missing).Count -gt 0) { "still missing: $($missing -join ', ')" }
        elseif (@($unaudited).Count -gt 0) { "indexed but not yet audited (maturity still L0-Absent): $($unaudited -join ', ')" }
        else { "index still empty" }

    # Carry the evidence into the failure rather than telling a reader where to
    # go looking - on a CI runner the log file is gone by the time anyone asks.
    $evidence = 'no host log path supplied'
    if (-not [string]::IsNullOrWhiteSpace($HostLogPath)) {
        if (Test-Path -LiteralPath $HostLogPath) {
            $refreshLines = @(Get-Content -LiteralPath $HostLogPath -ErrorAction SilentlyContinue |
                Where-Object { $_ -match 'status\.refresh' } | Select-Object -Last 15)
            $evidence = if (@($refreshLines).Count -gt 0) {
                "host log 'status.refresh' lines:`n    " + ($refreshLines -join "`n    ")
            } else {
                "host log has NO 'status.refresh' lines at all - the kick never happened, so look at why the miss path did not call Start-BackgroundStatusRefresh"
            }
        }
        else {
            $evidence = "host log not found at $HostLogPath"
        }
    }

    throw "Portfolio index did not warm within ${TimeoutSeconds}s ($detail; $entryCount entr(ies) present).`n  $evidence"
}

function Wait-ApiHostReady {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Uri,
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.Job]$Job,
        [Parameter()]
        [int]$TimeoutSeconds = 30
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if ($Job.State -in @('Failed', 'Stopped', 'Completed')) {
            $jobOutput = Receive-Job -Job $Job -Keep -ErrorAction SilentlyContinue | Out-String
            throw ("API host job exited before readiness check completed. State={0}. Output={1}" -f $Job.State, $jobOutput.Trim())
        }

        try {
            $response = Invoke-WebRequest -Uri $Uri -Method Get -SkipHttpErrorCheck -TimeoutSec 5
            if ($response.StatusCode -ge 200 -and $response.StatusCode -lt 500) {
                return
            }
        }
        catch {
            Start-Sleep -Milliseconds 500
            continue
        }

        Start-Sleep -Milliseconds 500
    }

    throw "API host did not become ready within $TimeoutSeconds seconds."
}

# Shutdown contract: with -ShutdownSignalPath the host polls Pending() between
# requests instead of parking forever inside a blocking AcceptTcpClient() call,
# and exits its accept loop cleanly when this file appears. That gives teardown
# a graceful path that does not depend on Stop-Job being able to interrupt a
# job pipeline that is blocked in native code.
$shutdownSignalPath = Join-Path $smokeRoot 'api-host-shutdown.signal'
Remove-Item -LiteralPath $shutdownSignalPath -Force -ErrorAction SilentlyContinue

# This smoke's dispatch section enqueues into the operator's REAL task queue
# and cancels ~1s later. A live headless runner polling that queue can claim
# the fixture inside that window and then have the fixture deleted out from
# under its claude session -- proven 2026-08-19 (run 20260819-145958-7bc51ee2),
# where only the runner's repo-root guard kept the orphaned session's commit
# out of the real working tree. Warn loudly; CI has no runner and stays quiet.
$runnerHeartbeatPath = Join-Path $WorkspaceRoot 'output\roadmap-task-runner.heartbeat.json'
if (Test-Path -LiteralPath $runnerHeartbeatPath) {
    try {
        $runnerHeartbeat = Get-Content -LiteralPath $runnerHeartbeatPath -Raw | ConvertFrom-Json
        $runnerHeartbeatPid = [int]$runnerHeartbeat.processId
        if ($runnerHeartbeatPid -gt 0 -and $null -ne (Get-Process -Id $runnerHeartbeatPid -ErrorAction Ignore)) {
            Write-Host ("[WARN] A live task runner (pid {0}) is polling the real queue this smoke enqueues into. It can claim the dispatch fixture mid-test. Stop the runner before running this smoke on an operator machine." -f $runnerHeartbeatPid) -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host ("[WARN] Runner heartbeat at {0} is unreadable; if a runner is alive it can race this smoke's dispatch fixture." -f $runnerHeartbeatPath) -ForegroundColor Yellow
    }
}

# Release 2.9 -- this smoke enqueues dispatch fixtures and cancels them ~1s
# later. Until now it wrote into the OPERATOR'S real queue, and on 2026-08-19 a
# live runner claimed a fixture inside that window before the smoke deleted it
# out from under the claimed session. The host resolves the queue through
# Get-RoadmapQueuePath, which honors REPO_MGMT_QUEUE_PATH, so the fixtures now
# land somewhere only this test looks. Set on the job, not the parent, so a
# crashed smoke cannot leave the operator's environment redirected.
$smokeQueuePath = Join-Path $smokeRoot 'roadmap-task-queue.jsonl'
Remove-Item -LiteralPath $smokeQueuePath -Force -ErrorAction SilentlyContinue
Write-Host ("  queue isolated to {0} (the operator's real queue is untouched)" -f $smokeQueuePath) -ForegroundColor DarkGray

# The settings twin of the queue isolation above -- the same lesson, learned on
# the reading side. This smoke has to point the host at a fixture workspace, and
# its only way to do that was to POST /api/settings and let the host overwrite
# the git-TRACKED file, restoring it afterwards. The restore worked; the window
# did not. The host now resolves settings through Get-PortalSettingsPath, which
# honours REPO_MGMT_SETTINGS_PATH, so the fixture config lands somewhere only
# this test looks and the operator's portal keeps serving the portfolio.
#
# Seeded from the tracked file's bytes so the run starts from the operator's
# real configuration -- the point is to stop WRITING that file, not to test
# against a different one.
# Refuse to start on a port something else already holds, rather than letting
# the host's restart-in-place mechanism terminate it. The default above is now
# 7171, but an explicit -Port can still name the portal's, and "the gate killed
# the service" must not be reachable by a typo. Reported, never silently worked
# around: the operator picks the port, this only declines to take one.
$occupant = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
if ($null -ne $occupant) {
    $occupantName = (Get-Process -Id $occupant.OwningProcess -ErrorAction SilentlyContinue).ProcessName
    throw ("Port {0} is already held by PID {1} ({2}). This smoke will not evict it -- the api-host terminates whatever holds the port it binds, and on {0} that is usually the installed portal service. Re-run with -Port on a free port." -f $Port, $occupant.OwningProcess, ($occupantName ?? 'unknown'))
}

$script:HostSettingsPath = Join-Path $smokeRoot 'settings.smoke.json'
Set-Content -LiteralPath $script:HostSettingsPath `
    -Value $(if ($null -ne $script:TrackedSettingsAtStart) { $script:TrackedSettingsAtStart } else { '{}' }) `
    -Encoding UTF8 -NoNewline
Write-Host ("  settings isolated to {0} (the operator's tracked settings.json is never written)" -f $script:HostSettingsPath) -ForegroundColor DarkGray

$job = Start-Job -ScriptBlock {
    param($ScriptPath, $Root, $Log, $ListenPort, $SignalPath, $QueuePath, $SettingsPath)
    # Both overrides are set on the JOB, never on the parent, so a crashed smoke
    # cannot leave the operator's environment redirected.
    $env:REPO_MGMT_QUEUE_PATH = $QueuePath
    $env:REPO_MGMT_SETTINGS_PATH = $SettingsPath
    # Start-Job inherits the parent environment. Every assertion below speaks
    # plain HTTP to this host, so an inherited REPO_MGMT_TLS_PFX -- which the
    # installed service sets at MACHINE scope -- would wrap the listener in an
    # SslStream and every request would die in the handshake, 30 seconds from a
    # readiness timeout that names nothing about TLS. Observed 2026-08-29 the
    # hour the operator's certificate was repaired: it had been inert only
    # because the certificate could not be loaded. The auth smoke's TLS step
    # supplies its own certificate; this gate wants none.
    $env:REPO_MGMT_TLS_PFX = ''
    $env:REPO_MGMT_TLS_PFX_PASSWORD = ''
    & $ScriptPath -WorkspaceRoot $Root -BindAddress '127.0.0.1' -Port $ListenPort -LogPath $Log -ShutdownSignalPath $SignalPath -QueuePath $QueuePath
} -ArgumentList $hostScript, $WorkspaceRoot, $logPath, $Port, $shutdownSignalPath, $smokeQueuePath, $script:HostSettingsPath

try {
    Wait-ApiHostReady -Uri "$BaseUrl/health/live" -Job $job

    Write-Host '[STEP] Health checks' -ForegroundColor Cyan
    $liveResponse = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/health/live"
    $readyResponse = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/health/ready"
    $depsResponse = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/health/dependencies"
    Assert-Not503 -Name '/health/live' -Response $liveResponse
    Assert-Not503 -Name '/health/ready' -Response $readyResponse
    Assert-Not503 -Name '/health/dependencies' -Response $depsResponse
    $live = $liveResponse.Json
    $ready = $readyResponse.Json
    $deps = $depsResponse.Json

    Write-Host '[STEP] Background scan: observable progress + cancel honored mid-scan (Release 3.2 M1)' -ForegroundColor Cyan
    $scanKnownStates = @('running', 'completed', 'failed', 'cancelled', 'aborted', 'never-run')

    # Route contract first: status always answers with a legal state.
    $scanStatusResponse = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/portfolio/scan/status"
    if ($scanStatusResponse.StatusCode -ne 200 -or $scanStatusResponse.Json.success -ne $true) {
        throw "GET /api/portfolio/scan/status failed: HTTP $($scanStatusResponse.StatusCode). Body=$($scanStatusResponse.Content)"
    }
    $scanInitialState = [string]$scanStatusResponse.Json.data.state
    if ($scanInitialState -notin $scanKnownStates) {
        throw "scan/status returned unknown state '$scanInitialState'; the UI can only render the declared vocabulary."
    }

    # If some earlier request already kicked a refresh, let it settle so the
    # start/cancel choreography below owns the single-flight lock.
    $scanSettleDeadline = (Get-Date).AddSeconds(240)
    while ($scanInitialState -eq 'running') {
        if ((Get-Date) -gt $scanSettleDeadline) { throw 'A pre-existing background scan did not settle within 240s.' }
        Start-Sleep -Seconds 3
        $scanInitialState = [string](Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/portfolio/scan/status").Json.data.state
    }

    # Start through the route, then cancel through the route. The cancel lands
    # at the worker's next phase boundary, so the terminal state must be
    # 'cancelled' with fewer than all phases done -- a cancel that reports
    # success while the scan runs to completion would be a false-affordance.
    $scanStartResponse = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/portfolio/scan" -Body @{}
    if ($scanStartResponse.StatusCode -ne 200 -or $scanStartResponse.Json.success -ne $true) {
        throw "POST /api/portfolio/scan failed: HTTP $($scanStartResponse.StatusCode). Body=$($scanStartResponse.Content)"
    }
    if (-not [bool]$scanStartResponse.Json.data.started) {
        throw "POST /api/portfolio/scan reported started=false on a settled host. Body=$($scanStartResponse.Content)"
    }

    # The host must stay answerable while its scan runs out of process --
    # the Lane 0.9 closure this architecture exists for.
    $scanLiveDuring = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/health/live"
    if ($scanLiveDuring.StatusCode -ne 200) {
        throw "/health/live answered HTTP $($scanLiveDuring.StatusCode) while a background scan was starting; liveness must not depend on scan state."
    }

    $scanCancelResponse = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/portfolio/scan/cancel" -Body @{}
    if ($scanCancelResponse.StatusCode -ne 200 -or -not [bool]$scanCancelResponse.Json.data.cancelRequested) {
        throw "POST /api/portfolio/scan/cancel on a running scan failed: HTTP $($scanCancelResponse.StatusCode). Body=$($scanCancelResponse.Content)"
    }

    # The cancel is honored at the NEXT phase gate, so it waits out the phase
    # it lands in -- on the real workspace that is the bounded (M2) inventory.
    $scanTerminalDeadline = (Get-Date).AddSeconds(360)
    $scanFinal = $null
    while ($true) {
        $scanFinal = (Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/portfolio/scan/status").Json.data
        if ([string]$scanFinal.state -ne 'running') { break }
        if ((Get-Date) -gt $scanTerminalDeadline) { throw 'Cancelled scan did not reach a terminal state within 360s.' }
        Start-Sleep -Seconds 3
    }
    if ([string]$scanFinal.state -ne 'cancelled') {
        throw "Cancelled scan ended '$($scanFinal.state)' (phases $($scanFinal.phasesDone)/$($scanFinal.phaseTotal)); expected 'cancelled'."
    }
    if ([int]$scanFinal.phasesDone -ge [int]$scanFinal.phaseTotal) {
        throw "Cancel reported success but all $($scanFinal.phaseTotal) phases completed; the cancel changed nothing."
    }

    # With nothing running, cancel must be a NAMED refusal, not a polite 200.
    $scanCancelIdle = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/portfolio/scan/cancel" -Body @{}
    if ($scanCancelIdle.StatusCode -ne 409 -or [string]$scanCancelIdle.Json.error.code -ne 'no-scan-running') {
        throw "Cancel with no scan running must refuse 409/no-scan-running; got HTTP $($scanCancelIdle.StatusCode). Body=$($scanCancelIdle.Content)"
    }
    Write-Host ("  scan route ok: started via route, /health/live 200 during scan, cancelled at phase boundary ({0}/{1} phases kept), idle cancel refused by name" -f $scanFinal.phasesDone, $scanFinal.phaseTotal) -ForegroundColor DarkGray

    # Worker-level determinism: the same worker script the host launches,
    # driven directly with a stretched phase delay so the mid-scan cancel is
    # race-free, plus a control run proving the delay alone changes nothing.
    $scanWorkerScript = Join-Path $WorkspaceRoot 'scripts\Invoke-StatusCacheRefresh.ps1'
    $scanFixtureDir = Join-Path $smokeRoot 'scan-cancel-fixture'
    $scanFixtureRepo = Join-Path $scanFixtureDir 'probe-repo'
    if (-not (Test-Path -LiteralPath $scanFixtureRepo)) {
        $null = New-Item -ItemType Directory -Path $scanFixtureRepo -Force
        & git init -q -b main "$scanFixtureRepo" 2>$null
        Set-Content -LiteralPath (Join-Path $scanFixtureRepo 'README.md') -Value '# scan cancel fixture'
    }
    $scanWorkerLock = Join-Path $scanFixtureDir 'worker.lock'
    $scanWorkerProgress = Join-Path $scanFixtureDir 'worker-progress.json'
    $scanWorkerCancel = Join-Path $scanFixtureDir 'worker-cancel.marker'
    $scanPsExe = (Get-Process -Id $PID).Path

    $scanControl = Start-Process -FilePath $scanPsExe -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $scanWorkerScript,
        '-WorkspaceRoot', $WorkspaceRoot, '-LocalRoots', $scanFixtureDir, '-MaxDepth', '2',
        '-LockPath', $scanWorkerLock, '-ProgressPath', $scanWorkerProgress, '-CancelPath', $scanWorkerCancel,
        '-PhaseDelayMs', '300', '-LogPath', $logPath
    ) -WindowStyle Hidden -PassThru
    if (-not $scanControl.WaitForExit(180000)) { throw 'Control worker run did not finish within 180s.' }
    $scanControlFinal = Get-Content -LiteralPath $scanWorkerProgress -Raw | ConvertFrom-Json
    if ($scanControl.ExitCode -ne 0 -or [string]$scanControlFinal.state -ne 'completed' -or [int]$scanControlFinal.phasesDone -ne 4) {
        throw "Control worker run: exit=$($scanControl.ExitCode) state=$($scanControlFinal.state) phases=$($scanControlFinal.phasesDone); expected exit 0, completed, 4/4."
    }

    $scanCancelRun = Start-Process -FilePath $scanPsExe -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $scanWorkerScript,
        '-WorkspaceRoot', $WorkspaceRoot, '-LocalRoots', $scanFixtureDir, '-MaxDepth', '2',
        '-LockPath', $scanWorkerLock, '-ProgressPath', $scanWorkerProgress, '-CancelPath', $scanWorkerCancel,
        '-PhaseDelayMs', '4000', '-LogPath', $logPath
    ) -WindowStyle Hidden -PassThru
    Start-Sleep -Seconds 6
    Set-Content -LiteralPath $scanWorkerCancel -Value 'cancel'
    if (-not $scanCancelRun.WaitForExit(180000)) { throw 'Cancel worker run did not finish within 180s.' }
    $scanCancelFinal = Get-Content -LiteralPath $scanWorkerProgress -Raw | ConvertFrom-Json
    if ($scanCancelRun.ExitCode -ne 0) { throw "Cancelled worker must exit 0 (operator action, not failure); got $($scanCancelRun.ExitCode)." }
    if ([string]$scanCancelFinal.state -ne 'cancelled' -or [int]$scanCancelFinal.phasesDone -ge 4) {
        throw "Cancel worker run: state=$($scanCancelFinal.state) phases=$($scanCancelFinal.phasesDone); expected cancelled with fewer than 4 phases."
    }
    if (Test-Path -LiteralPath $scanWorkerCancel) { throw 'Cancel marker survived the worker; a leftover marker would cancel the next scan at its first gate.' }
    if (Test-Path -LiteralPath $scanWorkerLock) { throw 'Worker lock survived the run; a leftover lock suppresses every future refresh.' }
    Write-Host ("  scan worker ok: control completed 4/4; delayed run cancelled at {0}/4 with exit 0, marker consumed, lock removed" -f $scanCancelFinal.phasesDone) -ForegroundColor DarkGray

    Write-Host '[STEP] Persistence status route (Release 2.1 Phase 1)' -ForegroundColor Cyan
    $persistenceStatusResponse = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/persistence/status"
    Assert-Not503 -Name '/api/persistence/status' -Response $persistenceStatusResponse
    $persistenceStatus = $persistenceStatusResponse.Json
    if ($null -eq $persistenceStatus -or $persistenceStatus.success -ne $true) {
        throw "/api/persistence/status did not return success=true. HTTP $($persistenceStatusResponse.StatusCode). Body=$($persistenceStatusResponse.Content)"
    }
    foreach ($persistenceField in @('capability', 'database', 'tables', 'agentRunEventCount')) {
        if (-not ($persistenceStatus.PSObject.Properties.Name -contains $persistenceField)) {
            throw "/api/persistence/status response missing '$persistenceField'. Body=$($persistenceStatusResponse.Content)"
        }
    }
    if (-not ($persistenceStatus.capability.PSObject.Properties.Name -contains 'available')) {
        throw "/api/persistence/status capability missing 'available' field"
    }
    if ($persistenceStatus.capability.available -eq $true) {
        if ($persistenceStatus.database.enabled -ne $true) {
            throw "/api/persistence/status: SQLite capability is available but the app database is not enabled"
        }
        $persistenceTables = @($persistenceStatus.tables)
        foreach ($expectedTable in @('schema_migrations', 'execution_ledger', 'execution_history', 'maturity_history', 'ops_log', 'portfolio_index_history', 'repo_signals', 'differential_scans', 'merge_readiness_snapshots', 'agent_runs', 'agent_run_events', 'quota_burn_snapshots')) {
            if ($expectedTable -notin $persistenceTables) {
                throw "/api/persistence/status missing expected table '$expectedTable' (got: $($persistenceTables -join ', '))"
            }
        }
        if ($null -eq $persistenceStatus.agentRunEventCount -or [long]$persistenceStatus.agentRunEventCount -lt 0) {
            throw "/api/persistence/status agentRunEventCount must be a non-negative count when the database is enabled"
        }
        Write-Host ("  persistence: provider={0} db enabled, {1} tables, agentRunEventCount={2}" -f $persistenceStatus.capability.providerDetail, @($persistenceTables).Count, $persistenceStatus.agentRunEventCount) -ForegroundColor DarkGray
    } else {
        Write-Host '  persistence: no SQLite provider on this machine — degraded contract accepted' -ForegroundColor Yellow
    }

    Write-Host '[STEP] Auth + setup routes (Release 2.2)' -ForegroundColor Cyan
    $authStatusResponse = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/auth/status"
    Assert-Not503 -Name '/api/auth/status' -Response $authStatusResponse
    $authStatus = $authStatusResponse.Json
    if ($null -eq $authStatus -or $authStatus.success -ne $true) { throw "/api/auth/status did not return success=true. Body=$($authStatusResponse.Content)" }
    foreach ($f in @('authRequired', 'authEnforced', 'authenticated', 'bindAddress', 'isLoopbackBind')) {
        if (-not ($authStatus.data.PSObject.Properties.Name -contains $f)) { throw "/api/auth/status missing data.$f" }
    }
    # Mirror the host's own rule (Test-ApiAuthRequired + a non-empty key):
    # enforcement is governed by the requireApiKey SWITCH, not by whether a key
    # happens to exist in the environment. The earlier version keyed only off
    # REPO_MGMT_API_KEY, so any workstation that exports a key expected
    # enforcement the host correctly does not apply — it passed only while the
    # tracked settings.json carried leftover smoke pollution (an `auth` block).
    # Cleaning that up (ROADMAP Lane 0.1) exposed the wrong premise.
    $requireToggle = [Environment]::GetEnvironmentVariable('REPO_MGMT_REQUIRE_API_KEY')
    $requireFromEnv = (-not [string]::IsNullOrWhiteSpace($requireToggle)) -and ($requireToggle.Trim() -match '^(?i)(1|true|yes|on)$')
    $requireFromSettings = $false
    # The file the HOST resolved, not the tracked one: this predicts the host's
    # own behaviour, so it has to read the settings the host is actually using.
    if (Test-Path -LiteralPath $script:HostSettingsPath) {
        try {
            $trackedAuth = (Get-Content -LiteralPath $script:HostSettingsPath -Raw | ConvertFrom-Json).auth
            if ($null -ne $trackedAuth -and ($trackedAuth.PSObject.Properties.Name -contains 'requireApiKey')) {
                $requireFromSettings = [bool]$trackedAuth.requireApiKey
            }
        } catch { $requireFromSettings = $false }
    }
    $hasKey = -not [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable('REPO_MGMT_API_KEY'))
    $expectAuthEnforced = ($requireFromEnv -or $requireFromSettings) -and $hasKey
    if ($authStatus.data.authEnforced -ne $expectAuthEnforced) {
        throw ("/api/auth/status expected authEnforced={0} (requireApiKey env={1} settings={2}, key present={3}), got {4}" -f `
                $expectAuthEnforced, $requireFromEnv, $requireFromSettings, $hasKey, $authStatus.data.authEnforced)
    }
    if ($authStatus.data.isLoopbackBind -ne $true) { throw "/api/auth/status expected isLoopbackBind=true for a 127.0.0.1 bind" }

    $setupStatusResponse = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/setup/status"
    Assert-Not503 -Name '/setup/status' -Response $setupStatusResponse
    $setupStatus = $setupStatusResponse.Json
    if ($null -eq $setupStatus -or $setupStatus.success -ne $true) { throw "/setup/status did not return success=true. Body=$($setupStatusResponse.Content)" }
    foreach ($f in @('needsSetup', 'settingsExists', 'hasLocalRoots', 'localRootCount', 'firstScanComplete')) {
        if (-not ($setupStatus.data.PSObject.Properties.Name -contains $f)) { throw "/setup/status missing data.$f" }
    }
    if ($setupStatus.data.settingsExists -ne $true) { throw "/setup/status expected settingsExists=true in this workspace" }

    $prereqResponse = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/setup/prerequisites"
    Assert-Not503 -Name '/setup/prerequisites' -Response $prereqResponse
    $prereq = $prereqResponse.Json
    if ($null -eq $prereq -or $prereq.success -ne $true) { throw "/setup/prerequisites did not return success=true. Body=$($prereqResponse.Content)" }
    if (-not ($prereq.data.PSObject.Properties.Name -contains 'prerequisitesMet')) { throw "/setup/prerequisites missing data.prerequisitesMet" }
    if (@($prereq.data.checks).Count -lt 1) { throw "/setup/prerequisites returned no checks" }

    $setupConfigBad = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/setup/config" -Body @{ localRoots = @() }
    if ([int]$setupConfigBad.StatusCode -ne 400) { throw "/setup/config with empty localRoots expected HTTP 400, got $($setupConfigBad.StatusCode)" }
    Write-Host ("  auth/setup routes ok: authEnforced={0} needsSetup={1} prerequisitesMet={2} setup/config(empty)->400" -f $authStatus.data.authEnforced, $setupStatus.data.needsSetup, $prereq.data.prerequisitesMet) -ForegroundColor DarkGray

    Write-Host '[STEP] Agent integration protocol (Release 2.4)' -ForegroundColor Cyan
    $agentReadiness1 = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/v1/agent/readiness/$([uri]::EscapeDataString('github-repo-management'))"
    Assert-Not503 -Name '/api/v1/agent/readiness' -Response $agentReadiness1
    if ($null -eq $agentReadiness1.Json -or $agentReadiness1.Json.success -ne $true) { throw "/api/v1/agent/readiness did not return success=true. Body=$($agentReadiness1.Content)" }
    foreach ($f in @('schemaVersion', 'repoName', 'found', 'lifecycleState', 'dispatchReadiness', 'roadmapState', 'readyForWork', 'blockingReasons', 'claim', 'generatedAt')) {
        if (-not ($agentReadiness1.Json.data.PSObject.Properties.Name -contains $f)) { throw "/api/v1/agent/readiness missing data.$f" }
    }
    $agentReadiness2 = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/v1/agent/readiness/$([uri]::EscapeDataString('github-repo-management'))"
    $shape1 = (($agentReadiness1.Json.data.PSObject.Properties.Name) | Sort-Object) -join ','
    $shape2 = (($agentReadiness2.Json.data.PSObject.Properties.Name) | Sort-Object) -join ','
    if ($shape1 -ne $shape2) { throw "/api/v1/agent/readiness shape changed between calls: '$shape1' vs '$shape2'" }
    $agentClaimRepo = 'smoke-agent-claim-repo'
    $claim1 = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/v1/agent/claim/$agentClaimRepo" -Body @{ agentId = 'smoke-a' }
    if ([int]$claim1.StatusCode -ne 200) { throw "first agent claim expected 200, got $($claim1.StatusCode). Body=$($claim1.Content)" }
    $claim2 = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/v1/agent/claim/$agentClaimRepo" -Body @{ agentId = 'smoke-b' }
    if ([int]$claim2.StatusCode -ne 409) { throw "second concurrent agent claim expected 409, got $($claim2.StatusCode). Body=$($claim2.Content)" }
    $complete1 = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/v1/agent/complete/$agentClaimRepo"
    if ([int]$complete1.StatusCode -ne 200) { throw "agent complete expected 200, got $($complete1.StatusCode)" }
    $claim3 = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/v1/agent/claim/$agentClaimRepo" -Body @{ agentId = 'smoke-c' }
    if ([int]$claim3.StatusCode -ne 200) { throw "re-claim after complete expected 200, got $($claim3.StatusCode)" }
    $null = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/v1/agent/complete/$agentClaimRepo"
    $agentQueue = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/v1/agent/queue"
    if ($null -eq $agentQueue.Json -or $agentQueue.Json.success -ne $true) { throw "/api/v1/agent/queue did not return success=true" }
    Write-Host '  agent protocol ok: readiness stable shape, concurrent-claim -> 409, complete + reclaim, queue ok' -ForegroundColor DarkGray

    Write-Host '[STEP] Distribution: SVG badges + digest (Release 2.3 Phase 3)' -ForegroundColor Cyan
    $portfolioBadge = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/badges/portfolio.svg"
    if ([int]$portfolioBadge.StatusCode -ne 200) { throw "/api/badges/portfolio.svg expected 200, got $($portfolioBadge.StatusCode)" }
    if ($portfolioBadge.ContentType -notlike 'image/svg+xml*') { throw "/api/badges/portfolio.svg expected image/svg+xml, got '$($portfolioBadge.ContentType)'" }
    if ($portfolioBadge.Content -notmatch '<svg') { throw "/api/badges/portfolio.svg did not return SVG markup" }
    $digestSend = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/digest/send" -Body @{}
    if ([int]$digestSend.StatusCode -ne 200) { throw "/api/digest/send expected 200, got $($digestSend.StatusCode). Body=$($digestSend.Content)" }
    if ($null -eq $digestSend.Json -or $digestSend.Json.success -ne $true) { throw "/api/digest/send did not return success=true" }
    foreach ($f in @('totalRepos', 'byLevel', 'improvedThisWeek', 'topCandidates')) {
        if (-not ($digestSend.Json.data.payload.PSObject.Properties.Name -contains $f)) { throw "/api/digest/send payload missing '$f'" }
    }
    if ($digestSend.Json.data.delivered -ne $false) { throw "/api/digest/send with no webhook should report delivered=false" }
    Write-Host '  distribution ok: portfolio.svg is SVG, digest payload has totalRepos/byLevel/improvedThisWeek/topCandidates (dry-run)' -ForegroundColor DarkGray

    Write-Host '[STEP] Automation: scheduled doc-refinement (Release 2.7 Phase B, preview-first)' -ForegroundColor Cyan
    # Automation now depends on an available portfolio payload; prime it first.
    $automationPortfolioWarm = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/portfolio/assessment"
    Assert-Not503 -Name '/api/portfolio/assessment (warm for automation)' -Response $automationPortfolioWarm
    if ([int]$automationPortfolioWarm.StatusCode -ne 200) {
        throw "/api/portfolio/assessment warm-up for automation expected 200, got $($automationPortfolioWarm.StatusCode). Body=$($automationPortfolioWarm.Content)"
    }
    if ($null -eq $automationPortfolioWarm.Json -or $automationPortfolioWarm.Json.success -ne $true) {
        throw "/api/portfolio/assessment warm-up for automation did not return success=true. Body=$($automationPortfolioWarm.Content)"
    }
    # POST /api/automation/run — runs the curated-subset doc-refinement. It must
    # never apply anything (appliedCount=0) and must write to the run history.
    $autoRun = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/automation/run" -Body @{}
    if ([int]$autoRun.StatusCode -ne 200) { throw "/api/automation/run expected 200, got $($autoRun.StatusCode). Body=$($autoRun.Content)" }
    if ($null -eq $autoRun.Json -or $autoRun.Json.success -ne $true) { throw "/api/automation/run did not return success=true. Body=$($autoRun.Content)" }
    $autoData = $autoRun.Json.data
    if ($null -eq $autoData.run) { throw "/api/automation/run missing data.run" }
    if ([int]$autoData.run.appliedCount -ne 0) { throw "/api/automation/run must never apply (appliedCount=$($autoData.run.appliedCount))" }
    if ($autoData.delivered -ne $false) { throw "/api/automation/run with no webhook should report delivered=false" }
    if ($null -eq $autoData.digest -or [int]$autoData.digest.appliedCount -ne 0) { throw "/api/automation/run digest must report appliedCount=0" }
    $autoRunId = [string]$autoData.run.runId
    # GET /api/automation/history — the run just made must be present, newest-first.
    $autoHist = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/automation/history?limit=10"
    if ([int]$autoHist.StatusCode -ne 200) { throw "/api/automation/history expected 200, got $($autoHist.StatusCode)" }
    if ($null -eq $autoHist.Json -or $autoHist.Json.success -ne $true) { throw "/api/automation/history did not return success=true" }
    $histRuns = @($autoHist.Json.data.runs)
    if (@($histRuns).Count -lt 1) { throw "/api/automation/history returned no runs after a run" }
    if ([string]$histRuns[0].runId -ne $autoRunId) { throw "/api/automation/history newest run should match the run just created" }
    # /api/scan/schedule now surfaces the automation config block.
    $schedAuto = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/scan/schedule"
    if ($null -eq $schedAuto.Json.data.automation) { throw "/api/scan/schedule missing automation config block" }
    if ($schedAuto.Json.data.automation.previewOnly -ne $true) { throw "/api/scan/schedule automation.previewOnly should be true" }
    Write-Host ("  automation ok: run appliedCount=0, {0} proposal(s), history round-trip, scan/schedule exposes automation block (previewOnly)" -f $autoData.run.proposalCount) -ForegroundColor DarkGray

    Write-Host '[STEP] Cost/burn analytics (Release 2.3 Phase 4)' -ForegroundColor Cyan
    $costResponse = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/analytics/cost?days=90"
    Assert-Not503 -Name '/api/analytics/cost' -Response $costResponse
    if ($null -eq $costResponse.Json -or $costResponse.Json.success -ne $true) { throw "/api/analytics/cost did not return success=true. Body=$($costResponse.Content)" }
    foreach ($f in @('totalCostUsd', 'runCount', 'starvationCount', 'byRepo', 'byPhase', 'derivedOnly')) {
        if (-not ($costResponse.Json.data.PSObject.Properties.Name -contains $f)) { throw "/api/analytics/cost missing data.$f" }
    }
    if ($costResponse.Json.data.derivedOnly -ne $true) { throw "/api/analytics/cost must report derivedOnly=true" }
    Write-Host ("  cost analytics ok: runCount={0} totalCostUsd={1} starvation={2} (derived-only)" -f $costResponse.Json.data.runCount, $costResponse.Json.data.totalCostUsd, $costResponse.Json.data.starvationCount) -ForegroundColor DarkGray

    Write-Host '[STEP] Stale-cache diagnostics (cross-cutting)' -ForegroundColor Cyan
    $cacheDiag = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/cache/diagnostics"
    Assert-Not503 -Name '/api/cache/diagnostics' -Response $cacheDiag
    if ($null -eq $cacheDiag.Json -or $cacheDiag.Json.success -ne $true) { throw "/api/cache/diagnostics did not return success=true. Body=$($cacheDiag.Content)" }
    foreach ($c in @('status', 'roadmap', 'roadmapAudit', 'docAudit', 'portfolioIndex')) {
        if (-not ($cacheDiag.Json.data.caches.PSObject.Properties.Name -contains $c)) { throw "/api/cache/diagnostics missing cache '$c'" }
        foreach ($f in @('present', 'ttlSeconds', 'stale')) {
            if (-not ($cacheDiag.Json.data.caches.$c.PSObject.Properties.Name -contains $f)) { throw "/api/cache/diagnostics cache '$c' missing field '$f'" }
        }
    }
    if (-not ($cacheDiag.Json.data.PSObject.Properties.Name -contains 'staleCount')) { throw "/api/cache/diagnostics missing staleCount" }
    Write-Host ("  cache diagnostics ok: 5 caches reported, staleCount={0}" -f $cacheDiag.Json.data.staleCount) -ForegroundColor DarkGray

    Write-Host '[STEP] Status route' -ForegroundColor Cyan
    $statusResponse = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/status?localRoots=$([uri]::EscapeDataString($WorkspaceRoot))&maxDepth=2&includeNonGitFolders=false"
    Assert-Not503 -Name '/api/status' -Response $statusResponse
    $status = $statusResponse.Json
    if ($null -eq $status) {
        throw "/api/status did not return JSON. HTTP $($statusResponse.StatusCode). Content-Type=$($statusResponse.ContentType). Body=$($statusResponse.Content)"
    }
    if (-not ($status.PSObject.Properties.Name -contains 'success')) {
        throw "/api/status response missing 'success'. Body=$($statusResponse.Content)"
    }
    if ($status.success -ne $true) {
        $err = if ($status.PSObject.Properties.Name -contains 'error') { $status.error } else { $statusResponse.Content }
        throw "/api/status returned success=false. HTTP $($statusResponse.StatusCode). Error=$err"
    }
    if (-not ($status.PSObject.Properties.Name -contains 'data') -or $null -eq $status.data) {
        throw "/api/status returned success=true but missing 'data'. Body=$($statusResponse.Content)"
    }
    if (-not ($status.data.PSObject.Properties.Name -contains 'repos')) {
        throw "/api/status returned success=true but data.repos is missing. Body=$($statusResponse.Content)"
    }
    $statusRepos = @($status.data.repos)
    if ($statusRepos.Count -gt 0) {
        $firstStatusRepo = $statusRepos[0]
        foreach ($field in @('lastCommitAuthor', 'commitsLastWeek', 'commitsLastMonth')) {
            if (-not ($firstStatusRepo.PSObject.Properties.Name -contains $field)) {
                throw "/api/status repo entry missing '$field' field"
            }
        }
    } else {
        Write-Host '  /api/status returned no repos for contract field validation; activity field check skipped' -ForegroundColor Yellow
    }

    Write-Host '[STEP] Status cache routes' -ForegroundColor Cyan
    $statusCache = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/status/cache"
    $statusCacheClear = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/status/cache/clear" -Body @{}
    Assert-Not503 -Name '/api/status/cache' -Response $statusCache
    Assert-Not503 -Name '/api/status/cache/clear' -Response $statusCacheClear

    # The host read every request through an ASCII StreamReader until 2026-08-09,
    # so any non-ASCII character in a JSON body was replaced with '?' before a
    # route saw it — an em-dash (3 UTF-8 bytes) arrived as '???'. It surfaced
    # only when the Phase A live submit-PR opened a real PR that mangled every
    # '—' in ROADMAP.md. Echo a known non-ASCII payload back through a route and
    # compare it byte-for-byte, so this cannot regress silently again.
    Write-Host '[STEP] Request body encoding — non-ASCII must survive the round trip' -ForegroundColor Cyan
    $unicodeProbe = 'em-dash:— arrow:→ accent:é quote:" cjk:日本語 emoji-free-ascii:ok'
    $echoResponse = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/roadmap/repair/submit-pr" -Body @{
        repoName = $unicodeProbe
    }
    if ([int]$echoResponse.StatusCode -ne 200) {
        throw "encoding probe: submit-pr dry-run expected 200, got $($echoResponse.StatusCode). Body=$($echoResponse.Content)"
    }
    $echoedName = [string]$echoResponse.Json.data.plan.repoName
    if ($echoedName -ne $unicodeProbe) {
        throw ("Request body encoding is lossy. Sent '{0}' but the host parsed '{1}'. " -f $unicodeProbe, $echoedName) +
              'The request StreamReader must preserve bytes (Latin-1) and decode the body as UTF-8.'
    }
    if ($echoedName -match '\?\?\?') {
        throw 'Request body encoding replaced a multi-byte character with "???" — the ASCII-reader regression is back.'
    }
    Write-Host '  request body encoding ok: em-dash / arrow / accent / CJK all survived the round trip' -ForegroundColor DarkGray

    Write-Host '[STEP] Settings routes' -ForegroundColor Cyan
    $settingsGet = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/settings"
    Assert-Not503 -Name '/api/settings (GET)' -Response $settingsGet
    $settingsJson = $settingsGet.Json
    if ($null -eq $settingsJson) {
        throw "/api/settings did not return JSON. HTTP $($settingsGet.StatusCode). Content-Type=$($settingsGet.ContentType). Body=$($settingsGet.Content)"
    }
    if (-not ($settingsJson.PSObject.Properties.Name -contains 'success')) {
        throw "/api/settings response missing 'success'. Body=$($settingsGet.Content)"
    }
    if ($settingsJson.success -ne $true) {
        $err = if ($settingsJson.PSObject.Properties.Name -contains 'error') { $settingsJson.error } else { $settingsGet.Content }
        throw "/api/settings returned success=false. HTTP $($settingsGet.StatusCode). Error=$err"
    }
    if (-not ($settingsJson.PSObject.Properties.Name -contains 'data') -or $null -eq $settingsJson.data) {
        throw "/api/settings returned success=true but missing 'data'. Body=$($settingsGet.Content)"
    }
    $settingsPostBody = @{
        basePath = [string]($settingsJson.data.inventory.localRoots[0] ?? $WorkspaceRoot)
        scanDepth = [int]($settingsJson.data.inventory.maxDepth ?? 3)
        daysInactive = [int]($settingsJson.data.retention.days ?? 30)
        githubUser = [string]($settingsJson.data.reconcile.gitHubOwner ?? '')
    }
    # No backup is taken here any more. Every POST below round-trips through the
    # host, which now writes $script:HostSettingsPath -- the tracked file is not
    # in the write path at all, so there is nothing to put back. The finally
    # block asserts that, rather than restoring it (ROADMAP Lane 0.1, Lane 0.8).
    $settingsPost = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/settings" -Body $settingsPostBody
    Assert-Not503 -Name '/api/settings (POST)' -Response $settingsPost

    # A workspace path that is not on disk must be refused here, not accepted and
    # then silently scanned to zero repositories. '/setup/config' has always
    # rejected a missing root; this route used to accept one, which is how a
    # mistyped path presented as "the tool found nothing" instead of "that folder
    # is not there".
    Write-Host '[STEP] Workspace path validation — a missing basePath is refused and not persisted' -ForegroundColor Cyan
    $bogusRoot = Join-Path $WorkspaceRoot ('does-not-exist-' + [guid]::NewGuid().ToString('n').Substring(0, 8))
    $badBasePath = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/settings" -Body @{ basePath = $bogusRoot }
    if ([int]$badBasePath.StatusCode -ne 400) {
        throw ("/api/settings must reject a basePath that is not on disk with HTTP 400; got {0}. Body={1}" -f $badBasePath.StatusCode, $badBasePath.Content)
    }
    $settingsAfterBadPath = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/settings"
    $rootsAfterBadPath = @($settingsAfterBadPath.Json.data.inventory.localRoots)
    if ($rootsAfterBadPath -contains $bogusRoot) {
        throw ("/api/settings persisted a non-existent basePath. localRoots={0}" -f ($rootsAfterBadPath -join ', '))
    }
    $script:WorkspaceValidationOk = $true
    Write-Host ("  rejected {0} with HTTP 400 and left localRoots untouched" -f $bogusRoot) -ForegroundColor DarkGray

    # And when a bad root is already saved (or a drive goes away), the scan must
    # say so rather than reporting an ordinary empty result.
    $missingRootStatus = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/status?localRoots=$([uri]::EscapeDataString($bogusRoot))&maxDepth=2&includeNonGitFolders=false"
    Assert-Not503 -Name '/api/status (missing root)' -Response $missingRootStatus
    if ([int]$missingRootStatus.StatusCode -ne 200) {
        throw ("/api/status over a missing root should still succeed; got {0}" -f $missingRootStatus.StatusCode)
    }
    $missingRootsReported = @($missingRootStatus.Json.meta.missingRoots)
    if ($missingRootsReported.Count -eq 0) {
        throw ("/api/status must report meta.missingRoots for a root that is not on disk. Body={0}" -f $missingRootStatus.Content)
    }
    $script:MissingRootsReportedOk = $true
    Write-Host ("  /api/status reported meta.missingRoots = {0}" -f ($missingRootsReported -join ', ')) -ForegroundColor DarkGray

    # GitHub auth is env-var-name indirection only. These guard the three ways a
    # secret could re-enter the app: stored in tracked settings, posted from the
    # browser, or pasted into the name field. All must be refused, not ignored —
    # a silent ignore reads as success while auth quietly degrades to anonymous.
    Write-Host '[STEP] GitHub auth — env-var-name indirection (no stored/transmitted tokens)' -ForegroundColor Cyan
    $storedTokenReject = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/settings" -Body @{ githubToken = 'ghp_smoketestvalue' }
    if ($storedTokenReject.StatusCode -ne 400) {
        throw ("/api/settings must reject a literal githubToken with HTTP 400; got {0}. Body={1}" -f $storedTokenReject.StatusCode, $storedTokenReject.Content)
    }
    $badNameReject = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/settings" -Body @{ gitHubTokenEnvVar = 'not a valid name' }
    if ($badNameReject.StatusCode -ne 400) {
        throw ("/api/settings must reject an invalid env var name with HTTP 400; got {0}. Body={1}" -f $badNameReject.StatusCode, $badNameReject.Content)
    }
    $tokenAsNameReject = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/settings" -Body @{ gitHubTokenEnvVar = 'github_pat_11ABCDEF' }
    if ($tokenAsNameReject.StatusCode -ne 400) {
        throw ("/api/settings must reject a token pasted into the env-var-name field with HTTP 400; got {0}. Body={1}" -f $tokenAsNameReject.StatusCode, $tokenAsNameReject.Content)
    }
    $wireTokenReject = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/github/status" -Body @{ githubUser = 'smoke-test'; apiKey = 'ghp_smoketestvalue' }
    if ($wireTokenReject.StatusCode -ne 400) {
        throw ("/api/github/status must reject a body token with HTTP 400; got {0}. Body={1}" -f $wireTokenReject.StatusCode, $wireTokenReject.Content)
    }
    # Confirm the tracked config never gained the key any of the above tried to set.
    $settingsAfterReject = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/settings"
    $secretsAfter = $settingsAfterReject.Json.data.secrets
    if ($null -ne $secretsAfter -and ($secretsAfter.PSObject.Properties.Name -contains 'githubToken')) {
        throw '/api/settings persisted a githubToken key; settings.json must stay secret-free.'
    }
    # The resolve probe must name the variable and report how it resolved, so an
    # operator can tell "not set" from "set in a scope this process cannot read".
    $ghAuth = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/auth/github/status"
    Assert-Not503 -Name '/api/auth/github/status' -Response $ghAuth
    $ghAuthData = $ghAuth.Json.data
    foreach ($field in @('tokenEnvVar', 'tokenSource', 'tokenEnvScope', 'runningAsService', 'hint')) {
        if (-not ($ghAuthData.PSObject.Properties.Name -contains $field)) {
            throw ("/api/auth/github/status missing resolve-probe field '{0}'. Body={1}" -f $field, $ghAuth.Content)
        }
    }
    if ($ghAuthData.tokenSource -notin @('env', 'gh-cli', 'none')) {
        throw ("/api/auth/github/status returned unexpected tokenSource '{0}'." -f $ghAuthData.tokenSource)
    }
    $githubAuthProbeOk = $true
    Write-Host ("  github auth ok: envVar={0} source={1} scope='{2}' service={3}; stored/wire/pasted tokens all rejected 400" -f `
        $ghAuthData.tokenEnvVar, $ghAuthData.tokenSource, $ghAuthData.tokenEnvScope, $ghAuthData.runningAsService) -ForegroundColor DarkGray

    Write-Host '[STEP] Placeholder and git operation routes' -ForegroundColor Cyan
    $initResponse = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/init" -Body @{ githubUser = 'smoke-test'; cloneOwned = $false }
    $updateResponse = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/update" -Body @{ repoNames = @('__smoke_test_missing_repo__') }
    $syncResponse = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/sync" -Body @{ repoNames = @('__smoke_test_missing_repo__') }
    $archiveResponse = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/archive" -Body @{}
    Assert-Not503 -Name '/api/init' -Response $initResponse
    Assert-Not503 -Name '/api/update' -Response $updateResponse
    Assert-Not503 -Name '/api/sync' -Response $syncResponse
    Assert-Not503 -Name '/api/archive' -Response $archiveResponse

    Write-Host '[STEP] Reconcile route' -ForegroundColor Cyan
    $reconcileBody = @{
        localRoots = @($WorkspaceRoot)
        maxDepth = 2
        includeNonGitFolders = $false
        outDir = (Join-Path $smokeRoot 'reconcile')
    }
    $reconcileResponse = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/reconcile" -Body $reconcileBody
    Assert-Not503 -Name '/api/reconcile' -Response $reconcileResponse
    $reconcile = $reconcileResponse.Json
    # The unmatched-route 404 envelope has no 'success' property; these checks
    # keep this step from passing vacuously if the route is ever removed again
    # (it silently vanished in bfb3724 and nothing failed).
    if ([int]$reconcileResponse.StatusCode -eq 404) { throw 'POST /api/reconcile returned 404 - route missing from API host' }
    if ($null -eq $reconcile -or -not ($reconcile.PSObject.Properties.Name -contains 'success')) { throw 'POST /api/reconcile response missing success envelope' }

    Write-Host '[STEP] DocReview route' -ForegroundColor Cyan
    $docBody = @{
        rootPath = $WorkspaceRoot
        maxDepth = 2
        outDir = (Join-Path $smokeRoot 'docreview')
        generateQueue = $false
        generateBatchPlan = $false
    }
    $docResponse = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/docreview/run" -Body $docBody
    Assert-Not503 -Name '/api/docreview/run' -Response $docResponse
    $doc = $docResponse.Json

    Write-Host '[STEP] Report and artifact routes' -ForegroundColor Cyan
    $artifactsResponse = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/report/artifacts"
    Assert-Not503 -Name '/api/report/artifacts' -Response $artifactsResponse
    $artifacts = $artifactsResponse.Json
    Write-Host '  /api/report/artifacts complete' -ForegroundColor DarkGray
    $artifactByRepoResponse = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/artifacts/$([uri]::EscapeDataString((Split-Path $WorkspaceRoot -Leaf)))"
    Assert-Not503 -Name '/api/artifacts/:repoName' -Response $artifactByRepoResponse
    Write-Host '  /api/artifacts/:repoName complete' -ForegroundColor DarkGray

    $exportBody = @{
        portfolioEntries = @(
            @{
                repoName = 'smoke-export'
                localPath = $WorkspaceRoot
                htmlUrl = 'https://example.invalid/smoke-export'
                branch = 'main'
                sourceCoverage = 'local+github'
                gitStatus = 'clean'
                isArchived = $false
                repoType = 'powershell'
                lifecycleState = 'ready-for-work'
                recommendedAction = 'Dispatch the top-ranked roadmap item.'
                blockingReasons = @()
                roadmapState = 'pending'
                roadmapPath = (Join-Path $WorkspaceRoot 'ROADMAP.md')
                hasRoadmap = $true
                readmeScore = 92
                roadmapScore = 88
                documentationHealthScore = 90
                pendingItemCount = 3
                nextPendingItemText = 'Ship the collection status report.'
                pendingItems = @()
                topValueItem = @{
                    text = 'Ship the collection status report.'
                    section = 'Release 1.7.5'
                    tags = @('reporting')
                    roadmapOrder = 1
                    valueScore = 96
                    valueTier = 'highest'
                    valueRationale = @('Unblocks operator-visible progress reporting.')
                    scoringSignals = @{
                        dimensions = @{ impact = 10 }
                        weights = @{ impact = 1 }
                        modelVersion = 'smoke'
                    }
                }
                maturityLevel = 'L4-Orchestration-Ready'
                maturityScore = 92
                dispatchReadiness = 'ready'
                executionState = 'idle'
                hasReadme = $true
                hasCiSignal = $true
                hasTestSignal = $true
                structureFindings = @()
                docFindingCount = 0
            }
        )
        sourceLabel = 'Smoke Test'
    }
    $exportResponse = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/export" -Body $exportBody
    Assert-Not503 -Name '/api/export' -Response $exportResponse
    $export = if ($null -ne $exportResponse.Json) { $exportResponse.Json } elseif (-not [string]::IsNullOrWhiteSpace($exportResponse.Content)) { $exportResponse.Content | ConvertFrom-Json } else { $null }
    Write-Host '  /api/export complete' -ForegroundColor DarkGray
    if ($null -eq $export -or -not ($export.PSObject.Properties.Name -contains 'data') -or [string]::IsNullOrWhiteSpace([string]$export.data.reportUrl)) {
        throw '/api/export did not return reportUrl in the response payload'
    }
    $reportOpenResponse = Invoke-ApiRequest -Method Get -Uri "$BaseUrl$($export.data.reportUrl)"
    Assert-Not503 -Name '/api/reports/:reportName' -Response $reportOpenResponse
    if ([string]$reportOpenResponse.Content -notmatch 'Collection Status Report') {
        throw '/api/reports/:reportName did not return the collection status report content'
    }
    Write-Host '  /api/reports/:reportName complete' -ForegroundColor DarkGray

    Write-Host '[STEP] Metrics route' -ForegroundColor Cyan
    $metricsResponse = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/metrics"
    Assert-Not503 -Name '/metrics' -Response $metricsResponse
    $metrics = $metricsResponse.Json

    Write-Host '[STEP] Roadmap index route' -ForegroundColor Cyan
    $roadmapIndexResponse = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/roadmap/index?localRoots=$([uri]::EscapeDataString($WorkspaceRoot))&maxDepth=3"
    Assert-Not503 -Name '/api/roadmap/index' -Response $roadmapIndexResponse
    $roadmapIndex = $roadmapIndexResponse.Json
    if (-not $roadmapIndex.success) { throw 'roadmap/index returned success=false' }

    Write-Host '[STEP] Roadmap scan route' -ForegroundColor Cyan
    $roadmapScanBody = @{
        localRoots = @($WorkspaceRoot)
        maxDepth = 3
    }
    $roadmapScanResponse = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/roadmap/scan" -Body $roadmapScanBody
    Assert-Not503 -Name '/api/roadmap/scan' -Response $roadmapScanResponse
    $roadmapScan = $roadmapScanResponse.Json
    if ($null -eq $roadmapScan) {
        throw "/api/roadmap/scan did not return JSON. HTTP $($roadmapScanResponse.StatusCode). Content-Type=$($roadmapScanResponse.ContentType). Body=$($roadmapScanResponse.Content)"
    }
    if (-not ($roadmapScan.PSObject.Properties.Name -contains 'success')) {
        throw "/api/roadmap/scan response missing 'success'. Body=$($roadmapScanResponse.Content)"
    }
    if (-not $roadmapScan.success) {
        $err = if ($roadmapScan.PSObject.Properties.Name -contains 'error') { $roadmapScan.error } else { $roadmapScanResponse.Content }
        throw "/api/roadmap/scan returned success=false. HTTP $($roadmapScanResponse.StatusCode). Error=$err"
    }
    if (-not ($roadmapScan.PSObject.Properties.Name -contains 'data') -or $null -eq $roadmapScan.data) {
        throw "/api/roadmap/scan returned success=true but missing 'data'. Body=$($roadmapScanResponse.Content)"
    }
    if (-not ($roadmapScan.data.PSObject.Properties.Name -contains 'entries')) {
        throw "/api/roadmap/scan returned success=true but missing 'data.entries'. Body=$($roadmapScanResponse.Content)"
    }

    Write-Host '[STEP] Roadmap scan entry state fields' -ForegroundColor Cyan
    $roadmapStateFieldsOk = $true
    $entries = @($roadmapScan.data.entries)
    $firstEntry = if ($entries.Count -gt 0) { $entries[0] } else { $null }
    if ($firstEntry) {
        $validStates = @('pending', 'complete', 'parse-error')
        if (-not ($firstEntry.PSObject.Properties.Name -contains 'roadmapState')) {
            throw "roadmap/scan entry missing 'roadmapState' field"
        }
        if ([string]$firstEntry.roadmapState -notin $validStates) {
            throw ("roadmap/scan entry has unexpected roadmapState: '{0}'" -f $firstEntry.roadmapState)
        }
        if (-not ($firstEntry.PSObject.Properties.Name -contains 'pendingCount')) {
            throw "roadmap/scan entry missing 'pendingCount' field"
        }
        if (-not ($firstEntry.PSObject.Properties.Name -contains 'completedCount')) {
            throw "roadmap/scan entry missing 'completedCount' field"
        }
        Write-Host ("  entry state={0} pendingCount={1} completedCount={2}" -f $firstEntry.roadmapState, $firstEntry.pendingCount, $firstEntry.completedCount) -ForegroundColor DarkGray
    } else {
        Write-Host '  (no roadmap entries found — state field check skipped)' -ForegroundColor Yellow
    }

    Write-Host '[STEP] Roadmap scan annotation fields (Release 2.0 Phase 4)' -ForegroundColor Cyan
    $annotatedRoadmapRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("roadmap-scan-annotations-" + [guid]::NewGuid().ToString('n').Substring(0, 8))
    $annotatedRoadmapRepo = Join-Path $annotatedRoadmapRoot 'quota-annotation-smoke'
    $null = New-Item -ItemType Directory -Path (Join-Path $annotatedRoadmapRepo '.git') -Force
    $annotatedRoadmapPath = Join-Path $annotatedRoadmapRepo 'ROADMAP.md'
    $annotatedRoadmapContent = @"
## Release 2.0 - Dispatch Budgets

**Goal:** Ship bounded dispatch slices with roadmap-derived estimates.

### Engineering milestones

- [ ] Add quota guard
- [x] Add agent-run ledger

### Phase plan

| Phase | Scope | Status | Completed | Token usage | Work units (est -> actual) |
| ----- | ----- | ------ | --------- | ----------- | -------------------------- |
| Phase 1: Ledger | Land the ledger model | done | 2026-06-11 | ~2k | 4 -> 5 |
| Phase 2: Quota guard | Enforce pre-dispatch quota checks | in progress | - | - | est. 8 |

### Budget guardrail

- Estimated AI work units for this release: 18 - Max per phase: 10
- Before dispatch: check the budget ledger; do not start a session whose estimate exceeds the per-session cap.
"@
    Set-Content -LiteralPath $annotatedRoadmapPath -Value $annotatedRoadmapContent -Encoding UTF8
    try {
        $annotatedScanResponse = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/roadmap/scan" -Body @{
            localRoots = @($annotatedRoadmapRoot)
            maxDepth = 2
        }
        Assert-Not503 -Name '/api/roadmap/scan (annotation fixture)' -Response $annotatedScanResponse
        $annotatedScanJson = $annotatedScanResponse.Json
        if (-not $annotatedScanJson.success) { throw '/api/roadmap/scan (annotation fixture) returned success=false' }
        $annotatedEntry = @($annotatedScanJson.data.entries | Where-Object { [string]$_.repoName -eq 'quota-annotation-smoke' } | Select-Object -First 1)
        if (@($annotatedEntry).Count -eq 0) { throw 'Annotated roadmap scan did not return the fixture repo.' }
        $annotatedEntry = $annotatedEntry[0]
        if ([string]$annotatedEntry.activeRelease.releaseName -notmatch '^Release 2\.0\b.*Dispatch Budgets$') { throw "Expected activeRelease.releaseName to include 'Release 2.0' and 'Dispatch Budgets', got '$($annotatedEntry.activeRelease.releaseName)'" }
        if ([string]$annotatedEntry.activePhasePlan.phaseName -ne 'Phase 2: Quota guard') { throw "Expected activePhasePlan.phaseName='Phase 2: Quota guard', got '$($annotatedEntry.activePhasePlan.phaseName)'" }
        if ([double]$annotatedEntry.estimatedSessionWorkUnits -ne 8) { throw "Expected estimatedSessionWorkUnits=8, got '$($annotatedEntry.estimatedSessionWorkUnits)'" }
        if ([double]$annotatedEntry.budgetGuardrail.maxUnitsPerPhase -ne 10) { throw "Expected budgetGuardrail.maxUnitsPerPhase=10, got '$($annotatedEntry.budgetGuardrail.maxUnitsPerPhase)'" }
        Write-Host ("  annotated roadmap entry -> phase='{0}' est={1} maxPhase={2}" -f $annotatedEntry.activePhasePlan.phaseName, $annotatedEntry.estimatedSessionWorkUnits, $annotatedEntry.budgetGuardrail.maxUnitsPerPhase) -ForegroundColor DarkGray
    }
    finally {
        Remove-Item -LiteralPath $annotatedRoadmapRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    Write-Host '[STEP] Roadmap scan — repo-scoped branch (Lane 0.4)' -ForegroundColor Cyan
    # The global-scope path is asserted above; the scoped branch (the RepoGrid
    # per-row action) was ui-connected only. Its load-bearing property is that a
    # single-repo scan must NOT overwrite the portfolio-wide roadmap cache —
    # `useDefaultScope` is false for a scoped request, so Save-RoadmapCache is
    # skipped. A regression there would let one row action silently shrink the
    # cached portfolio to one repo.
    $scopedScanOk = $false
    $scopedRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("roadmap-scoped-" + [guid]::NewGuid().ToString('n').Substring(0, 8))
    try {
        foreach ($fixtureName in @('scoped-target-repo', 'scoped-other-repo')) {
            $fixtureRepo = Join-Path $scopedRoot $fixtureName
            $null = New-Item -ItemType Directory -Path (Join-Path $fixtureRepo '.git') -Force
            Set-Content -LiteralPath (Join-Path $fixtureRepo 'ROADMAP.md') -Encoding UTF8 -Value @"
## Release 1.0 - $fixtureName

### Engineering milestones

- [ ] Pending item for $fixtureName
- [x] Completed item for $fixtureName
"@
        }

        # Cache state before the scoped call, so clobbering is detectable.
        $cacheBefore = (Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/roadmap/cache").Json

        $scopedResponse = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/roadmap/scan" -Body @{
            localRoots = @($scopedRoot)
            maxDepth   = 2
            repoName   = 'scoped-target-repo'
        }
        Assert-Not503 -Name '/api/roadmap/scan (scoped)' -Response $scopedResponse
        $scopedJson = $scopedResponse.Json
        if ($null -eq $scopedJson) { throw "/api/roadmap/scan (scoped) did not return JSON. HTTP $($scopedResponse.StatusCode) Content-Type=$($scopedResponse.ContentType)" }
        if (-not $scopedJson.success) { throw "/api/roadmap/scan (scoped) returned success=false. Body=$($scopedResponse.Content)" }

        # The response must declare its own scope, so a consumer can tell a
        # one-repo result from a portfolio that happens to hold one repo.
        if ([string]$scopedJson.data.scopedRepo -ne 'scoped-target-repo') {
            throw "Scoped scan must echo scopedRepo='scoped-target-repo'; got '$($scopedJson.data.scopedRepo)'"
        }
        $scopedEntries = @($scopedJson.data.entries)
        if ($scopedEntries.Count -ne 1) {
            throw ("Scoped scan must return exactly the target repo; got {0} entries: {1}" -f $scopedEntries.Count, (($scopedEntries | ForEach-Object { $_.repoName }) -join ', '))
        }
        if ([string]$scopedEntries[0].repoName -ne 'scoped-target-repo') {
            throw "Scoped scan returned the wrong repo: '$($scopedEntries[0].repoName)'"
        }

        # The global scan over the same root must see BOTH repos — proving the
        # single result above came from scoping, not from an empty fixture.
        $unscopedResponse = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/roadmap/scan" -Body @{
            localRoots = @($scopedRoot)
            maxDepth   = 2
        }
        $unscopedCount = @($unscopedResponse.Json.data.entries).Count
        if ($unscopedCount -lt 2) {
            throw "Fixture check failed: an unscoped scan of the same root should see 2 repos, saw $unscopedCount — the scoped assertion above would be vacuous."
        }
        if ($null -ne $unscopedResponse.Json.data.scopedRepo) {
            throw "An unscoped scan must report scopedRepo=null; got '$($unscopedResponse.Json.data.scopedRepo)'"
        }

        # Neither call used the default scope, so the portfolio-wide cache must
        # be untouched by both.
        $cacheAfter = (Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/roadmap/cache").Json
        $beforeCount = if ($null -ne $cacheBefore -and $null -ne $cacheBefore.disk) { [int]$cacheBefore.disk.entryCount } else { -1 }
        $afterCount = if ($null -ne $cacheAfter -and $null -ne $cacheAfter.disk) { [int]$cacheAfter.disk.entryCount } else { -1 }
        if ($beforeCount -ge 0 -and $afterCount -ne $beforeCount) {
            throw "A scoped/custom-root roadmap scan must not rewrite the portfolio roadmap cache (entryCount $beforeCount -> $afterCount)."
        }

        $scopedScanOk = $true
        Write-Host ("  scoped scan ok: 1 entry (target), unscoped saw {0}, cache count unchanged at {1}" -f $unscopedCount, $afterCount) -ForegroundColor DarkGray
    }
    finally {
        Remove-Item -LiteralPath $scopedRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    Write-Host '[STEP] Repository-improvement preview route (Lane 0.4)' -ForegroundColor Cyan
    # The Guided Repository Improvement Workflow shipped 2026-08-01 as the only
    # API route added since 2026-07-05 with no smoke coverage — which also left
    # it outside the route-census tripwire (that census is GET-only).
    $improvementPreviewOk = $false
    $improvementRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("repo-improvement-" + [guid]::NewGuid().ToString('n').Substring(0, 8))
    $improvementRepo = Join-Path $improvementRoot 'improvement-smoke-repo'
    try {
        $null = New-Item -ItemType Directory -Path (Join-Path $improvementRepo '.git') -Force
        # A deliberately thin repo: a one-line README and no ROADMAP, so the
        # preview has real findings to report rather than an empty happy path.
        Set-Content -LiteralPath (Join-Path $improvementRepo 'README.md') -Encoding UTF8 -Value "# improvement-smoke-repo`n"

        $improvementResponse = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/repository-improvement/preview" -Body @{
            repoName = 'improvement-smoke-repo'
            repoPath = $improvementRepo
        }
        Assert-Not503 -Name '/api/repository-improvement/preview' -Response $improvementResponse
        if ([string]$improvementResponse.ContentType -notlike 'application/json*') {
            throw "/api/repository-improvement/preview did not return JSON (HTTP $($improvementResponse.StatusCode), $($improvementResponse.ContentType)) — deleted route shadowed by the SPA fallback?"
        }
        $improvementJson = $improvementResponse.Json
        if ($null -eq $improvementJson -or -not $improvementJson.success) {
            throw "/api/repository-improvement/preview returned success=false for a valid repo. HTTP $($improvementResponse.StatusCode). Body=$($improvementResponse.Content)"
        }
        if ($null -eq $improvementJson.data) {
            throw "/api/repository-improvement/preview returned success=true with no data. Body=$($improvementResponse.Content)"
        }
        if (-not ($improvementJson.data.PSObject.Properties.Name -contains 'findingCount')) {
            throw "/api/repository-improvement/preview data missing 'findingCount'. Body=$($improvementResponse.Content)"
        }
        # A repo with a one-line README and no ROADMAP must produce findings; a
        # zero here would mean the preview ran but evaluated nothing.
        if ([int]$improvementJson.data.findingCount -lt 1) {
            throw "Expected at least one finding for a thin repo with no ROADMAP; got findingCount=$($improvementJson.data.findingCount)"
        }

        # Required-input validation must refuse rather than guess a path.
        $improvementBad = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/repository-improvement/preview" -Body @{ repoName = 'improvement-smoke-repo' }
        if ($improvementBad.StatusCode -eq 200 -and $null -ne $improvementBad.Json -and $improvementBad.Json.success -eq $true) {
            throw '/api/repository-improvement/preview must refuse a request with no repoPath, not infer one.'
        }

        $improvementPreviewOk = $true
        Write-Host ("  repository-improvement/preview ok: findingCount={0}, missing-repoPath refused with HTTP {1}" -f $improvementJson.data.findingCount, $improvementBad.StatusCode) -ForegroundColor DarkGray
    }
    finally {
        Remove-Item -LiteralPath $improvementRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    Write-Host '[STEP] Roadmap content route' -ForegroundColor Cyan
    $roadmapContentOk = $false
    if ($firstEntry) {
        $encodedRepo = [uri]::EscapeDataString($firstEntry.repoName)
        $contentResponse = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/roadmap/content?repo=$encodedRepo"
        Assert-Not503 -Name '/api/roadmap/content?repo=' -Response $contentResponse
        $roadmapContentOk = ($contentResponse.StatusCode -eq 200)
    } else {
        Write-Host '  (no roadmap entries found — content route skipped)' -ForegroundColor Yellow
        $roadmapContentOk = $true
    }

    $largeRoadmapPath = Join-Path $smokeRoot 'full-roadmap-test.md'
    $largeRoadmapDir = Split-Path $largeRoadmapPath -Parent
    $null = New-Item -ItemType Directory -Path $largeRoadmapDir -Force
    $largeRoadmapContent = ('# LARGE ROADMAP' + "`n") + ('0123456789abcdef' * 40000)
    Set-Content -LiteralPath $largeRoadmapPath -Value $largeRoadmapContent -Encoding UTF8
    $expectedLargeRoadmapContent = Get-Content -LiteralPath $largeRoadmapPath -Raw -Encoding UTF8
    $encodedPath = [uri]::EscapeDataString($largeRoadmapPath)
    $fullRoadmapResponse = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/roadmap/content?path=$encodedPath"
    Assert-Not503 -Name '/api/roadmap/content?path=' -Response $fullRoadmapResponse
    $fullRoadmapJson = $fullRoadmapResponse.Json
    $fullRoadmapReturnedAll = ($fullRoadmapJson.success -and [string]$fullRoadmapJson.data.content -eq $expectedLargeRoadmapContent)

    Write-Host '[STEP] Roadmap cache routes' -ForegroundColor Cyan
    $roadmapCache = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/roadmap/cache"
    $roadmapCacheClear = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/roadmap/cache/clear" -Body @{}
    Assert-Not503 -Name '/api/roadmap/cache' -Response $roadmapCache
    Assert-Not503 -Name '/api/roadmap/cache/clear' -Response $roadmapCacheClear

    Write-Host '[STEP] Roadmap standard assets route (Release 0.7)' -ForegroundColor Cyan
    $roadmapStandardResponse = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/roadmap/standard"
    Assert-Not503 -Name '/api/roadmap/standard' -Response $roadmapStandardResponse
    $roadmapStandardJson = $roadmapStandardResponse.Json
    if ($roadmapStandardJson -and $roadmapStandardJson.success -eq $true) {
        $std = $roadmapStandardJson.data
        if ($null -eq $std.rules -or @($std.rules).Count -eq 0) { throw '/api/roadmap/standard returned no rules' }
        if ($null -eq $std.maturityThresholds)                   { throw '/api/roadmap/standard missing maturityThresholds' }
        Write-Host ("  /api/roadmap/standard -> ruleCount={0} maturityLevels={1}" -f $std.ruleCount, (@($std.maturityLevels) -join ',')) -ForegroundColor DarkGray
    } elseif ($roadmapStandardResponse.StatusCode -eq 404) {
        Write-Host '  /api/roadmap/standard -> 404 (standards/roadmap/roadmap-audit-rules.json not found — acceptable in non-workspace CI)' -ForegroundColor Yellow
    } else {
        throw ('/api/roadmap/standard returned unexpected status {0}' -f $roadmapStandardResponse.StatusCode)
    }

    Write-Host '[STEP] Docs audit routes' -ForegroundColor Cyan
    $docsAuditGet = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/docs-audit"
    $docsAuditScan = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/docs-audit/scan" -Body @{}
    Assert-Not503 -Name '/api/docs-audit' -Response $docsAuditGet
    Assert-Not503 -Name '/api/docs-audit/scan' -Response $docsAuditScan
    $docsAuditData = $docsAuditGet.Json
    $docsAuditScanData = $docsAuditScan.Json
    if (-not $docsAuditData.success) { throw '/api/docs-audit returned success=false' }
    if (-not $docsAuditScanData.success) { throw '/api/docs-audit/scan returned success=false' }
    Write-Host ("  docs-audit: {0} repos audited" -f $docsAuditData.data.count) -ForegroundColor DarkGray

    Write-Host '[STEP] GitHub and roadmap-agent routes' -ForegroundColor Cyan
    $githubStatusResponse = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/github/status" -Body @{}
    $roadmapPreviewResponse = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/roadmap-agent/preview" -Body @{}
    $roadmapStartResponse = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/roadmap-agent/start" -Body @{}
    $roadmapHistoryResponse = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/roadmap-agent/history?limit=5"
    Assert-Not503 -Name '/api/github/status' -Response $githubStatusResponse
    Assert-Not503 -Name '/api/roadmap-agent/preview' -Response $roadmapPreviewResponse
    Assert-Not503 -Name '/api/roadmap-agent/start' -Response $roadmapStartResponse
    Assert-Not503 -Name '/api/roadmap-agent/history' -Response $roadmapHistoryResponse

    # Use a deterministic fixture roadmap (with a pending task) rather than the
    # live workspace ROADMAP.md — the preview endpoint previews the next pending
    # task, so the assertion must not depend on the workspace roadmap's current
    # completion state (which is legitimately 100% complete).
    $workspaceRoadmapPath = Join-Path $smokeRoot 'roadmap-agent-preview-fixture.md'
    @'
# Fixture Roadmap

## Release 1 — Fixture Release

- [x] A completed fixture item.
- [ ] A pending fixture item to preview.
'@ | Set-Content -LiteralPath $workspaceRoadmapPath -Encoding UTF8
    if (Test-Path -LiteralPath $workspaceRoadmapPath -PathType Leaf) {
        $roadmapPreviewLocalResponse = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/roadmap-agent/preview" -Body @{
            repository = 'smoke-owner/smoke-repo'
            roadmapPath = $workspaceRoadmapPath
        }
        Assert-Not503 -Name '/api/roadmap-agent/preview (local roadmap path)' -Response $roadmapPreviewLocalResponse
        $roadmapPreviewLocalJson = $roadmapPreviewLocalResponse.Json
        if ($null -eq $roadmapPreviewLocalJson -or -not $roadmapPreviewLocalJson.success) {
            throw '/api/roadmap-agent/preview with local roadmapPath did not return success=true'
        }
        if (-not ($roadmapPreviewLocalJson.data.PSObject.Properties.Name -contains 'roadmapPath') -or [string]::IsNullOrWhiteSpace([string]$roadmapPreviewLocalJson.data.roadmapPath)) {
            throw '/api/roadmap-agent/preview with local roadmapPath did not return a resolved roadmapPath'
        }
        Write-Host ("  /api/roadmap-agent/preview (local roadmap path) -> {0}" -f [string]$roadmapPreviewLocalJson.data.roadmapPath) -ForegroundColor DarkGray
    } else {
        Write-Host '  workspace ROADMAP.md not found — local-roadmap preview check skipped' -ForegroundColor Yellow
    }

    Write-Host '[STEP] Roadmap-agent dispatch: start route enqueues + approve-push contract (Release 2.8)' -ForegroundColor Cyan
    $dispatchFixtureRoot = Join-Path $smokeRoot 'roadmap-dispatch-fixture'
    $dispatchRepoPath = Join-Path $dispatchFixtureRoot 'smoke-dispatch-repo'
    if (Test-Path -LiteralPath $dispatchFixtureRoot) { Remove-Item -LiteralPath $dispatchFixtureRoot -Recurse -Force }
    $null = New-Item -ItemType Directory -Path $dispatchRepoPath -Force
    & git init "$dispatchRepoPath" *>&1 | Out-Null
    $dispatchRoadmapPath = Join-Path $dispatchRepoPath 'ROADMAP.md'
    Set-Content -LiteralPath $dispatchRoadmapPath `
        -Value "# Smoke Dispatch Roadmap`n`n## Release 1`n`n- [ ] Pending dispatch fixture item`n" -Encoding UTF8

    $dispatchQueuePath = $smokeQueuePath  # Release 2.9: the isolated queue, not the operator's
    $queueLinesBefore = if (Test-Path -LiteralPath $dispatchQueuePath) { @(Get-Content -LiteralPath $dispatchQueuePath -Encoding UTF8 | Where-Object { $_ -and $_.Trim() }).Count } else { 0 }

    # Release 3.1 — this route is the third road to the queue, reaching it
    # indirectly through Start-RoadmapCopilotTask.ps1 -> Add-RoadmapTaskToQueue.ps1.
    # Prove the refusal before the happy path: with no heartbeat it must 409 and
    # add no queue line, or it is a road by which work still strands.
    # This is the operator's real heartbeat file — the same one the dispatch
    # section further down is careful to put back exactly as found. Back it up
    # before removing it, or a smoke run on a machine with a live runner would
    # silently disrupt that runner.
    $agentHeartbeatPath = Join-Path $WorkspaceRoot 'output\roadmap-task-runner.heartbeat.json'
    $agentHeartbeatBackup = if (Test-Path -LiteralPath $agentHeartbeatPath) { Get-Content -LiteralPath $agentHeartbeatPath -Raw -Encoding UTF8 } else { $null }
    if (Test-Path -LiteralPath $agentHeartbeatPath) { Remove-Item -LiteralPath $agentHeartbeatPath -Force }
    $dispatchNoRunner = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/roadmap-agent/start" -Body @{
        repository = 'smoke-owner/smoke-dispatch-repo'
        roadmapPath = $dispatchRoadmapPath
    }
    if ([int]$dispatchNoRunner.StatusCode -ne 409) {
        throw ("/api/roadmap-agent/start with no runner expected 409, got {0}. Body={1}" -f $dispatchNoRunner.StatusCode, $dispatchNoRunner.Content)
    }
    if ([string]$dispatchNoRunner.Json.category -ne 'runner-absent') {
        throw ("/api/roadmap-agent/start refusal expected category runner-absent; got '{0}'" -f $dispatchNoRunner.Json.category)
    }
    $queueLinesAfterRefusal = if (Test-Path -LiteralPath $dispatchQueuePath) { @(Get-Content -LiteralPath $dispatchQueuePath -Encoding UTF8 | Where-Object { $_ -and $_.Trim() }).Count } else { 0 }
    if ($queueLinesAfterRefusal -ne $queueLinesBefore) {
        throw 'A refused /api/roadmap-agent/start still wrote a queue line; the gate must precede the write.'
    }

    # A present runner lets the same call through.
    $agentHeartbeatDir = Split-Path -Parent $agentHeartbeatPath
    if (-not (Test-Path -LiteralPath $agentHeartbeatDir)) { $null = New-Item -ItemType Directory -Path $agentHeartbeatDir -Force }
    ([pscustomobject]@{
            hostname = 'api-host-smoke'; user = 'smoke'; pid = 4242; mode = 'claude'
            pollSeconds = 5; claimedCount = 0; lastHeartbeatAt = ([datetime]::UtcNow).ToString('o')
        } | ConvertTo-Json -Depth 5) | Set-Content -LiteralPath $agentHeartbeatPath -Encoding UTF8

    $dispatchStartResponse = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/roadmap-agent/start" -Body @{
        repository = 'smoke-owner/smoke-dispatch-repo'
        roadmapPath = $dispatchRoadmapPath
    }
    if ($dispatchStartResponse.StatusCode -ne 200) {
        throw ("/api/roadmap-agent/start (fixture) failed: HTTP {0}. Body={1}" -f $dispatchStartResponse.StatusCode, $dispatchStartResponse.Content)
    }
    if (-not $dispatchStartResponse.Json.success) { throw '/api/roadmap-agent/start (fixture) returned success=false' }
    $dispatchLatest = $dispatchStartResponse.Json.data.latestHistory
    if ($null -eq $dispatchLatest -or [string]$dispatchLatest.status -ne 'queued') {
        throw ("/api/roadmap-agent/start did not surface a 'queued' latestHistory (got '{0}')" -f $(if ($null -ne $dispatchLatest) { [string]$dispatchLatest.status } else { 'null' }))
    }
    $dispatchRunId = [string]$dispatchLatest.runId

    # Deterministic enqueue evidence: the queue ledger gained a line whose runId
    # matches the started run, and that run's summary is status='queued'.
    $dispatchOutput = [string]$dispatchStartResponse.Json.data.output
    if ($dispatchOutput -notmatch [regex]::Escape($dispatchQueuePath)) {
        throw ("/api/roadmap-agent/start did not pass the isolated queue to its nested writer. Output={0}" -f $dispatchOutput)
    }
    $dispatchQueueLines = @(Get-Content -LiteralPath $dispatchQueuePath -Encoding UTF8 | Where-Object { $_ -and $_.Trim() })
    if ($dispatchQueueLines.Count -le $queueLinesBefore) { throw 'roadmap-task-queue.jsonl did not gain an entry after /api/roadmap-agent/start' }
    $dispatchQueueEntry = $dispatchQueueLines[-1] | ConvertFrom-Json
    if ([string]$dispatchQueueEntry.runId -ne $dispatchRunId) { throw ("queue tail runId '{0}' does not match started run '{1}'" -f $dispatchQueueEntry.runId, $dispatchRunId) }
    $dispatchSummaryPath = Join-Path $WorkspaceRoot ("output\roadmap-task-history\runs\{0}.summary.json" -f $dispatchRunId)
    $dispatchSummary = Get-Content -LiteralPath $dispatchSummaryPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$dispatchSummary.status -ne 'queued') { throw ("run summary status expected 'queued', got '{0}'" -f $dispatchSummary.status) }
    # Put the operator's heartbeat back exactly as found, before anything else
    # in this suite reads it. The dispatch section below does its own backup and
    # restore, and it must capture the real file rather than this fixture.
    if ($null -ne $agentHeartbeatBackup) {
        Set-Content -LiteralPath $agentHeartbeatPath -Value $agentHeartbeatBackup -Encoding UTF8 -NoNewline
    }
    elseif (Test-Path -LiteralPath $agentHeartbeatPath) {
        Remove-Item -LiteralPath $agentHeartbeatPath -Force
    }
    Write-Host ("  start route enqueued run {0} (queue line + summary proven, refusal proven first)" -f $dispatchRunId) -ForegroundColor DarkGray

    # approve-push contract gates: 400 (no runId), 404 (unknown run), 409 (wrong
    # state — a 'queued' run must not be pushable).
    $approveMissing = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/roadmap-agent/approve-push" -Body @{}
    if ($approveMissing.StatusCode -ne 400) { throw ("approve-push without runId expected 400, got {0}" -f $approveMissing.StatusCode) }
    $approveUnknown = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/roadmap-agent/approve-push" -Body @{ runId = 'smoke-no-such-run' }
    if ($approveUnknown.StatusCode -ne 404) { throw ("approve-push with unknown runId expected 404, got {0}" -f $approveUnknown.StatusCode) }
    $approveWrongState = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/roadmap-agent/approve-push" -Body @{ runId = $dispatchRunId }
    if ($approveWrongState.StatusCode -ne 409) { throw ("approve-push on a 'queued' run expected 409, got {0}" -f $approveWrongState.StatusCode) }

    # approve-push happy path: a real push proven against a local bare remote
    # (no network, deterministic). Lift the smoke run to awaiting-review with
    # branch + localRepoPath exactly as the runner would have left it.
    $bareRemotePath = Join-Path $dispatchFixtureRoot 'bare-remote.git'
    & git init --bare "$bareRemotePath" *>&1 | Out-Null
    & git -C $dispatchRepoPath -c user.email=smoke@local -c user.name=smoke commit -q --allow-empty -m 'smoke: dispatch fixture base' *>&1 | Out-Null
    & git -C $dispatchRepoPath remote add origin "$bareRemotePath" *>&1 | Out-Null
    $approveBranchName = "roadmap/$dispatchRunId"
    & git -C $dispatchRepoPath switch -c $approveBranchName *>&1 | Out-Null
    & git -C $dispatchRepoPath -c user.email=smoke@local -c user.name=smoke commit -q --allow-empty -m 'smoke: reviewed work' *>&1 | Out-Null
    $dispatchSummaryHash = @{}
    foreach ($prop in $dispatchSummary.PSObject.Properties) { $dispatchSummaryHash[$prop.Name] = $prop.Value }
    $dispatchSummaryHash['status'] = 'awaiting-review'
    $dispatchSummaryHash['branch'] = $approveBranchName
    $dispatchSummaryHash['localRepoPath'] = $dispatchRepoPath
    ($dispatchSummaryHash | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $dispatchSummaryPath -Encoding UTF8

    $approveOk = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/roadmap-agent/approve-push" -Body @{ runId = $dispatchRunId }
    if ($approveOk.StatusCode -ne 200) {
        throw ("approve-push on awaiting-review run expected 200, got HTTP {0}. Body={1}" -f $approveOk.StatusCode, $approveOk.Content)
    }
    if (-not $approveOk.Json.success -or -not $approveOk.Json.data.pushed) { throw 'approve-push did not return success=true/pushed=true' }
    & git -C $bareRemotePath rev-parse --verify ("refs/heads/{0}" -f $approveBranchName) *>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw ("bare remote does not contain pushed branch {0} — push was not real" -f $approveBranchName) }
    $dispatchSummaryAfter = Get-Content -LiteralPath $dispatchSummaryPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$dispatchSummaryAfter.status -ne 'pushed') { throw ("summary status after approve-push expected 'pushed', got '{0}'" -f $dispatchSummaryAfter.status) }
    $approveAgain = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/roadmap-agent/approve-push" -Body @{ runId = $dispatchRunId }
    if ($approveAgain.StatusCode -ne 409) { throw ("approve-push on a 'pushed' run expected 409 (terminal state), got {0}" -f $approveAgain.StatusCode) }
    Write-Host '  approve-push ok: 400/404/409 gates, real push to local bare remote, terminal pushed state' -ForegroundColor DarkGray

    # Park the smoke run so it reads as fixture data in history (the queue
    # ledger stays append-only; the runner only ever claims status='queued').
    $dispatchSummaryFinal = Get-Content -LiteralPath $dispatchSummaryPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $dispatchFinalHash = @{}
    foreach ($prop in $dispatchSummaryFinal.PSObject.Properties) { $dispatchFinalHash[$prop.Name] = $prop.Value }
    $dispatchFinalHash['status'] = 'smoke-cancelled'
    ($dispatchFinalHash | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $dispatchSummaryPath -Encoding UTF8
    Remove-Item -LiteralPath $dispatchFixtureRoot -Recurse -Force -ErrorAction SilentlyContinue

    Write-Host '[STEP] Copilot task packet routes (Release 0.6)' -ForegroundColor Cyan
    # Preview with a missing repoName should return non-503 (400/500 is acceptable)
    $copilotPreviewMissingBody = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/copilot-task/preview" -Body @{}
    Assert-Not503 -Name '/api/copilot-task/preview (no repoName)' -Response $copilotPreviewMissingBody
    Write-Host ("  /api/copilot-task/preview (no repoName) -> HTTP {0}" -f $copilotPreviewMissingBody.StatusCode) -ForegroundColor DarkGray

    # Warm portfolio assessment first so the prompt-context packet can include live value and lifecycle context.
    $copilotPreviewPortfolioWarm = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/portfolio/assessment"
    Assert-Not503 -Name '/api/portfolio/assessment (warm for copilot packet)' -Response $copilotPreviewPortfolioWarm

    # Preview with workspace repo name — may succeed if roadmap index is warm, or fail gracefully
    $workspaceRepoName = Split-Path $WorkspaceRoot -Leaf
    $copilotPreviewResponse = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/copilot-task/preview" -Body @{ repoName = $workspaceRepoName }
    Assert-Not503 -Name '/api/copilot-task/preview' -Response $copilotPreviewResponse
    $copilotPreviewJson = $copilotPreviewResponse.Json
    $copilotPreviewPacketOk = $false
    if ($copilotPreviewJson -and $copilotPreviewJson.success -eq $true) {
        $packet = $copilotPreviewJson.data
        $copilotPacketFieldsPresent = $packet -and
            $packet.packetVersion -and
            $packet.runId -and
            ($packet.PSObject.Properties.Name -contains 'repoContext') -and
            ($packet.PSObject.Properties.Name -contains 'readmeContext') -and
            ($packet.PSObject.Properties.Name -contains 'roadmapContext') -and
            ($packet.PSObject.Properties.Name -contains 'selectedRoadmapItem') -and
            ($packet.PSObject.Properties.Name -contains 'valueContext') -and
            ($packet.PSObject.Properties.Name -contains 'constraints') -and
            $packet.generatedPrompt
        if ($copilotPacketFieldsPresent) {
            $copilotPreviewPacketOk = $true
            Write-Host ("  /api/copilot-task/preview -> packet runId={0} section='{1}' selection='{2}'" -f $packet.runId, $packet.selectedRoadmapItem.section, $packet.selectedRoadmapItem.selectionSource) -ForegroundColor DarkGray
        } else {
            Write-Host '  /api/copilot-task/preview returned success=true but packet fields missing' -ForegroundColor Yellow
        }
    } else {
        Write-Host ("  /api/copilot-task/preview -> HTTP {0} (non-ready repo or missing roadmap index — acceptable)" -f $copilotPreviewResponse.StatusCode) -ForegroundColor DarkGray
        $copilotPreviewPacketOk = $true  # graceful error is OK in smoke context
    }

    # Lane 0.17 — the packet-build EXCEPTION path must return JSON naming the
    # problem, via the route's own catch. Before it existed, the throw reached
    # the accept-loop catch, which wrote the 500 to the raw TCP stream — fatal
    # under TLS (the browser saw only "Failed to fetch"). A repo no cache has
    # ever heard of forces that throw deterministically.
    $copilotPreviewGhostResponse = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/copilot-task/preview" -Body @{ repoName = 'lane017-ghost-repo-that-no-cache-holds' }
    Assert-Not503 -Name '/api/copilot-task/preview (unknown repo)' -Response $copilotPreviewGhostResponse
    $copilotGhostJson = $copilotPreviewGhostResponse.Json
    if (-not $copilotGhostJson) {
        throw '/api/copilot-task/preview (unknown repo) did not return parseable JSON — the packet-build failure is not reaching the client as a structured error'
    }
    if ($copilotGhostJson.success -ne $false) {
        throw "/api/copilot-task/preview (unknown repo) returned success=$($copilotGhostJson.success); expected a structured failure"
    }
    $copilotGhostMessage = if ($copilotGhostJson.error -and $copilotGhostJson.error.message) { [string]$copilotGhostJson.error.message } else { [string]$copilotGhostJson.error }
    if ([string]::IsNullOrWhiteSpace($copilotGhostMessage)) {
        throw '/api/copilot-task/preview (unknown repo) returned a failure with no error message — the operator would see nothing actionable'
    }
    # The operation name proves the ROUTE's catch answered, not the accept-loop
    # catch (which writes to the raw TCP stream and dies under TLS).
    if ([string]$copilotGhostJson.operation -ne 'copilot-task.preview') {
        throw "/api/copilot-task/preview (unknown repo) was answered by operation '$($copilotGhostJson.operation)' — expected the route-level catch 'copilot-task.preview'"
    }
    Write-Host ("  /api/copilot-task/preview (unknown repo) -> HTTP {0} JSON error from route catch: {1}" -f $copilotPreviewGhostResponse.StatusCode, $copilotGhostMessage) -ForegroundColor DarkGray

    $opsPromptRefineMissingBody = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/operations/prompt/refine" -Body @{}
    Assert-Not503 -Name '/api/operations/prompt/refine (no repoName)' -Response $opsPromptRefineMissingBody
    Write-Host ("  /api/operations/prompt/refine (no repoName) -> HTTP {0}" -f $opsPromptRefineMissingBody.StatusCode) -ForegroundColor DarkGray

    $opsPromptRefineResponse = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/operations/prompt/refine" -Body @{
        repoName = $workspaceRepoName
        selectedTaskText = ''
        selectedTaskSection = ''
        additionalConstraints = @('Prefer small focused commits')
        emphasisAreas = @('tests', 'documentation')
        operatorInstructions = 'Keep behavior backwards compatible.'
    }
    Assert-Not503 -Name '/api/operations/prompt/refine' -Response $opsPromptRefineResponse
    $opsPromptRefineJson = $opsPromptRefineResponse.Json
    $opsPromptRefineOk = $false
    $opsPromptHistoryDispatchFile = $null
    $opsPromptHistoryDispatchBackup = $null
    $opsPromptHistorySyntheticRunId = ''
    $opsPromptHistoryLinkedRefineRunId = ''
    if ($opsPromptRefineJson -and $opsPromptRefineJson.success -eq $true) {
        $opsPromptRefineData = $opsPromptRefineJson.data
        $opsPromptRefineFieldsOk = $null -ne $opsPromptRefineData -and
            ($opsPromptRefineData.PSObject.Properties.Name -contains 'runId') -and
            ($opsPromptRefineData.PSObject.Properties.Name -contains 'packet') -and
            ($opsPromptRefineData.PSObject.Properties.Name -contains 'refinedPrompt') -and
            ($opsPromptRefineData.PSObject.Properties.Name -contains 'warnings') -and
            ($opsPromptRefineData.PSObject.Properties.Name -contains 'applied')
        if ($opsPromptRefineFieldsOk) {
            $opsPromptRefineOk = $true
            $opsPromptHistoryLinkedRefineRunId = [string]$opsPromptRefineData.runId
            Write-Host ("  /api/operations/prompt/refine -> warnings={0} selected='{1}'" -f @($opsPromptRefineData.warnings).Count, [string]$opsPromptRefineData.applied.selectedTaskText) -ForegroundColor DarkGray

            if (-not [string]::IsNullOrWhiteSpace($opsPromptHistoryLinkedRefineRunId)) {
                $safeRepoName = $workspaceRepoName -replace '[\\/:*?"<>|]', '_'
                $opsPromptHistoryDispatchFile = Join-Path $WorkspaceRoot "output\roadmap-task-history\prompt-refinements\$safeRepoName.dispatches.jsonl"
                if (Test-Path -LiteralPath $opsPromptHistoryDispatchFile) {
                    $opsPromptHistoryDispatchBackup = Get-Content -LiteralPath $opsPromptHistoryDispatchFile -Raw -Encoding UTF8
                }

                $opsPromptHistorySyntheticRunId = "smoke-dispatch-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
                $syntheticTimestamp = (Get-Date).ToUniversalTime().ToString('o')
                $syntheticDispatchRecord = [ordered]@{
                    promptRefinementRunId = $opsPromptHistoryLinkedRefineRunId
                    dispatchRunId         = $opsPromptHistorySyntheticRunId
                    repoName              = $workspaceRepoName
                    githubRepo            = 'smoke-owner/smoke-repo'
                    status                = 'started'
                    startedAt             = $syntheticTimestamp
                    recordedAt            = $syntheticTimestamp
                    localPath             = $WorkspaceRoot
                    baseBranch            = 'main'
                }
                $null = New-Item -ItemType Directory -Path (Split-Path -Path $opsPromptHistoryDispatchFile -Parent) -Force -ErrorAction SilentlyContinue
                Add-Content -LiteralPath $opsPromptHistoryDispatchFile -Value ($syntheticDispatchRecord | ConvertTo-Json -Compress -Depth 5) -Encoding UTF8
            }
        } else {
            Write-Host '  /api/operations/prompt/refine returned success=true but expected fields were missing' -ForegroundColor Yellow
        }
    } else {
        Write-Host ("  /api/operations/prompt/refine -> HTTP {0} (missing roadmap/index for selected repo is acceptable in smoke context)" -f $opsPromptRefineResponse.StatusCode) -ForegroundColor DarkGray
        $opsPromptRefineOk = $true
    }

    try {
        $opsPromptHistoryResponse = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/operations/prompt/history?repoName=$([uri]::EscapeDataString($workspaceRepoName))&limit=5"
        Assert-Not503 -Name '/api/operations/prompt/history' -Response $opsPromptHistoryResponse
        $opsPromptHistoryJson = $opsPromptHistoryResponse.Json
        $opsPromptHistoryOk = $false
        if ($opsPromptHistoryJson -and $opsPromptHistoryJson.success -eq $true) {
            $opsPromptHistoryData = $opsPromptHistoryJson.data
            $opsPromptHistoryOk = $null -ne $opsPromptHistoryData -and ($opsPromptHistoryData.PSObject.Properties.Name -contains 'items')
            if ($opsPromptHistoryOk) {
                if (-not [string]::IsNullOrWhiteSpace($opsPromptHistoryLinkedRefineRunId) -and -not [string]::IsNullOrWhiteSpace($opsPromptHistorySyntheticRunId)) {
                    $matchingPromptHistory = @($opsPromptHistoryData.items | Where-Object { [string]$_.runId -eq $opsPromptHistoryLinkedRefineRunId } | Select-Object -First 1)
                    if (@($matchingPromptHistory).Count -eq 0) {
                        throw '/api/operations/prompt/history did not return the newly created refinement run.'
                    }

                    $historyDispatchCount = [int]($matchingPromptHistory[0].dispatchCount)
                    $historyDispatchRecords = @($matchingPromptHistory[0].dispatchRecords)
                    $historySyntheticMatch = @($historyDispatchRecords | Where-Object { [string]$_.dispatchRunId -eq $opsPromptHistorySyntheticRunId })
                    if ($historyDispatchCount -lt 1 -or @($historySyntheticMatch).Count -eq 0) {
                        throw '/api/operations/prompt/history did not surface linked dispatch records for the refinement run.'
                    }
                }
                Write-Host ("  /api/operations/prompt/history -> {0} item(s)" -f @($opsPromptHistoryData.items).Count) -ForegroundColor DarkGray
            }
        }
        if (-not $opsPromptHistoryOk) {
            throw '/api/operations/prompt/history returned an unexpected payload shape'
        }
    }
    finally {
        if ($opsPromptHistoryDispatchFile) {
            if ($null -eq $opsPromptHistoryDispatchBackup) {
                Remove-Item -LiteralPath $opsPromptHistoryDispatchFile -Force -ErrorAction SilentlyContinue
            } else {
                Set-Content -LiteralPath $opsPromptHistoryDispatchFile -Value $opsPromptHistoryDispatchBackup -Encoding UTF8
            }
        }
    }

    Write-Host '[STEP] AI documentation improvement preview (Release 1.9)' -ForegroundColor Cyan
    # Missing repoName -> validation failure path (must not 503).
    $aiImproveMissingBody = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/ai/docs/improve/preview" -Body @{}
    Assert-Not503 -Name '/api/ai/docs/improve/preview (no repoName)' -Response $aiImproveMissingBody
    Write-Host ("  /api/ai/docs/improve/preview (no repoName) -> HTTP {0}" -f $aiImproveMissingBody.StatusCode) -ForegroundColor DarkGray

    # Inline content + heuristic provider keeps the smoke offline, deterministic, and free.
    $aiImproveSampleReadme = "# Sample`n`nA short description without the standard sections."
    $aiImproveResponse = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/ai/docs/improve/preview" -Body @{
        repoName       = $workspaceRepoName
        docType        = 'readme'
        templateId     = 'readme-product'
        provider       = 'heuristic'
        currentContent = $aiImproveSampleReadme
        customPrompt   = 'Keep it concise.'
    }
    Assert-Not503 -Name '/api/ai/docs/improve/preview' -Response $aiImproveResponse
    $aiImproveJson = $aiImproveResponse.Json
    if (-not $aiImproveJson.success) { throw '/api/ai/docs/improve/preview returned success=false' }
    $aiImproveData = $aiImproveJson.data
    $aiImproveFieldsOk = $null -ne $aiImproveData -and
        ($aiImproveData.PSObject.Properties.Name -contains 'previewId') -and
        ($aiImproveData.PSObject.Properties.Name -contains 'providerId') -and
        ($aiImproveData.PSObject.Properties.Name -contains 'currentContent') -and
        ($aiImproveData.PSObject.Properties.Name -contains 'proposedContent') -and
        ($aiImproveData.PSObject.Properties.Name -contains 'changeSummary') -and
        ($aiImproveData.PSObject.Properties.Name -contains 'estimatedScore') -and
        ($aiImproveData.PSObject.Properties.Name -contains 'warnings')
    if (-not $aiImproveFieldsOk) { throw '/api/ai/docs/improve/preview returned an unexpected payload shape' }
    if ([string]$aiImproveData.providerId -ne 'heuristic') { throw "/api/ai/docs/improve/preview expected heuristic provider, got '$($aiImproveData.providerId)'" }
    if ([string]::IsNullOrWhiteSpace([string]$aiImproveData.proposedContent)) { throw '/api/ai/docs/improve/preview returned empty proposedContent' }
    Write-Host ("  /api/ai/docs/improve/preview -> provider={0} scoreDelta={1} changes={2}" -f $aiImproveData.providerId, $aiImproveData.estimatedScore.delta, @($aiImproveData.changeSummary).Count) -ForegroundColor DarkGray

    # Templates route serves the data-driven built-in improvement templates.
    $aiTemplatesResponse = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/ai/docs/templates"
    Assert-Not503 -Name '/api/ai/docs/templates' -Response $aiTemplatesResponse
    $aiTemplatesJson = $aiTemplatesResponse.Json
    if (-not $aiTemplatesJson.success) { throw '/api/ai/docs/templates returned success=false' }
    $aiReadmeTemplateCount = @($aiTemplatesJson.data.readmeTemplates).Count
    $aiRoadmapTemplateCount = @($aiTemplatesJson.data.roadmapTemplates).Count
    if ($aiReadmeTemplateCount -lt 1 -or $aiRoadmapTemplateCount -lt 1) { throw '/api/ai/docs/templates returned empty template lists' }
    Write-Host ("  /api/ai/docs/templates -> readme={0} roadmap={1}" -f $aiReadmeTemplateCount, $aiRoadmapTemplateCount) -ForegroundColor DarkGray

    # History route: missing repoName -> 400; the earlier preview must have written a history record.
    $aiHistoryMissing = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/ai/docs/improve/history"
    Assert-Not503 -Name '/api/ai/docs/improve/history (no repoName)' -Response $aiHistoryMissing
    Write-Host ("  /api/ai/docs/improve/history (no repoName) -> HTTP {0}" -f $aiHistoryMissing.StatusCode) -ForegroundColor DarkGray

    $aiHistoryResponse = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/ai/docs/improve/history?repoName=$([uri]::EscapeDataString($workspaceRepoName))&limit=5"
    Assert-Not503 -Name '/api/ai/docs/improve/history' -Response $aiHistoryResponse
    $aiHistoryJson = $aiHistoryResponse.Json
    if (-not $aiHistoryJson.success) { throw '/api/ai/docs/improve/history returned success=false' }
    $aiHistoryItems = @($aiHistoryJson.data.items)
    if ($aiHistoryItems.Count -lt 1) { throw '/api/ai/docs/improve/history did not return the record persisted by the preview call' }
    $aiHistoryMatch = @($aiHistoryItems | Where-Object { [string]$_.previewId -eq [string]$aiImproveData.previewId })
    if (@($aiHistoryMatch).Count -eq 0) { throw '/api/ai/docs/improve/history did not include the previewId from the preview call' }
    Write-Host ("  /api/ai/docs/improve/history -> {0} item(s), latest previewId matched" -f $aiHistoryItems.Count) -ForegroundColor DarkGray

    Write-Host '[STEP] AI documentation improvement apply (Release 1.9 Phase 3)' -ForegroundColor Cyan
    # Missing proposedContent -> validation failure path (must not 503).
    $aiApplyMissingBody = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/ai/docs/improve/apply" -Body @{ repoName = 'smoke-ai-apply' }
    Assert-Not503 -Name '/api/ai/docs/improve/apply (no proposedContent)' -Response $aiApplyMissingBody
    if ([int]$aiApplyMissingBody.StatusCode -ne 400) { throw "/api/ai/docs/improve/apply without proposedContent expected HTTP 400, got $($aiApplyMissingBody.StatusCode)" }
    Write-Host ("  /api/ai/docs/improve/apply (no proposedContent) -> HTTP {0}" -f $aiApplyMissingBody.StatusCode) -ForegroundColor DarkGray

    # Real apply against an isolated temp target so the smoke never mutates a real repo document.
    $aiApplyRepoName = 'smoke-ai-apply'
    $aiApplyDir = Join-Path ([System.IO.Path]::GetTempPath()) ("ai-apply-smoke-" + [guid]::NewGuid().ToString('n').Substring(0, 8))
    $aiApplyBackupDir = Join-Path $WorkspaceRoot "output\ai-doc-improvements\backups\$aiApplyRepoName"
    $aiApplyHistoryFile = Join-Path $WorkspaceRoot "output\ai-doc-improvements\$aiApplyRepoName.improvements.jsonl"
    try {
        New-Item -ItemType Directory -Path $aiApplyDir -Force | Out-Null
        $aiApplyTarget = Join-Path $aiApplyDir 'README.md'
        Set-Content -LiteralPath $aiApplyTarget -Value "# Smoke Apply`n`nOriginal content." -Encoding UTF8 -NoNewline

        $aiApplyResponse = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/ai/docs/improve/apply" -Body @{
            repoName        = $aiApplyRepoName
            docType         = 'readme'
            path            = $aiApplyTarget
            proposedContent = "# Smoke Apply`n`nImproved content."
            previewId       = 'smoke-apply-preview'
        }
        Assert-Not503 -Name '/api/ai/docs/improve/apply' -Response $aiApplyResponse
        $aiApplyJson = $aiApplyResponse.Json
        if (-not $aiApplyJson.success) { throw '/api/ai/docs/improve/apply returned success=false' }
        $aiApplyData = $aiApplyJson.data
        if ([string]::IsNullOrWhiteSpace([string]$aiApplyData.applyId)) { throw '/api/ai/docs/improve/apply returned no applyId' }
        if (-not [bool]$aiApplyData.originalExisted) { throw '/api/ai/docs/improve/apply did not report the pre-existing original file' }

        $aiAppliedContent = Get-Content -LiteralPath $aiApplyTarget -Raw -Encoding UTF8
        if ($aiAppliedContent -notmatch 'Improved content\.') { throw '/api/ai/docs/improve/apply did not write the proposed content to the target file' }

        $aiBackupPath = [string]$aiApplyData.backupPath
        if ([string]::IsNullOrWhiteSpace($aiBackupPath) -or -not (Test-Path -LiteralPath $aiBackupPath)) { throw '/api/ai/docs/improve/apply did not create a backup file' }
        $aiBackupContent = Get-Content -LiteralPath $aiBackupPath -Raw -Encoding UTF8
        if ($aiBackupContent -notmatch 'Original content\.') { throw '/api/ai/docs/improve/apply backup does not contain the original content' }

        $aiRestorePath = [string]$aiApplyData.restoreMetadataPath
        if ([string]::IsNullOrWhiteSpace($aiRestorePath) -or -not (Test-Path -LiteralPath $aiRestorePath)) { throw '/api/ai/docs/improve/apply did not write restore metadata' }
        $aiRestoreMeta = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $aiRestorePath -Raw -Encoding UTF8)
        if ([string]$aiRestoreMeta.applyId -ne [string]$aiApplyData.applyId) { throw 'restore metadata applyId does not match the apply response' }
        if ([string]::IsNullOrWhiteSpace([string]$aiRestoreMeta.restoreCommand)) { throw 'restore metadata is missing the restoreCommand' }

        # The apply must append an append-only history record marked applied=true.
        $aiApplyHistoryResponse = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/ai/docs/improve/history?repoName=$([uri]::EscapeDataString($aiApplyRepoName))&limit=5"
        Assert-Not503 -Name '/api/ai/docs/improve/history (apply record)' -Response $aiApplyHistoryResponse
        $aiApplyHistoryJson = $aiApplyHistoryResponse.Json
        if (-not $aiApplyHistoryJson.success) { throw '/api/ai/docs/improve/history (apply record) returned success=false' }
        $aiApplyHistoryMatch = @(@($aiApplyHistoryJson.data.items) | Where-Object { [string]$_.recordType -eq 'apply' -and [bool]$_.applied })
        if (@($aiApplyHistoryMatch).Count -eq 0) { throw '/api/ai/docs/improve/history did not return the applied=true record written by the apply' }

        Write-Host ("  /api/ai/docs/improve/apply -> applyId={0} backup+restore metadata verified, history applied record present" -f $aiApplyData.applyId) -ForegroundColor DarkGray
    }
    finally {
        Remove-Item -LiteralPath $aiApplyDir -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $aiApplyBackupDir -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $aiApplyHistoryFile -Force -ErrorAction SilentlyContinue
    }

    Write-Host '[STEP] Agent-run ledger routes (Release 2.0 Phase 1)' -ForegroundColor Cyan
    $agentRunsResponse = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/agent-runs?limit=10"
    Assert-Not503 -Name '/api/agent-runs' -Response $agentRunsResponse
    $agentRunsJson = $agentRunsResponse.Json
    if (-not $agentRunsJson.success) { throw '/api/agent-runs returned success=false' }
    $agentRunsShapeOk = ($null -ne $agentRunsJson.data) -and
        ($agentRunsJson.data.PSObject.Properties.Name -contains 'items') -and
        ($agentRunsJson.data.PSObject.Properties.Name -contains 'count') -and
        ($agentRunsJson.data.PSObject.Properties.Name -contains 'byStatus')
    if (-not $agentRunsShapeOk) { throw '/api/agent-runs returned an unexpected payload shape' }
    Write-Host ("  /api/agent-runs -> {0} run(s)" -f @($agentRunsJson.data.items).Count) -ForegroundColor DarkGray

    $agentRunMissing = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/agent-runs/does-not-exist"
    Assert-Not503 -Name '/api/agent-runs/{runId} (unknown)' -Response $agentRunMissing
    if ([int]$agentRunMissing.StatusCode -ne 404) { throw "/api/agent-runs/{runId} for unknown runId expected HTTP 404, got $($agentRunMissing.StatusCode)" }
    Write-Host ("  /api/agent-runs/does-not-exist -> HTTP {0}" -f $agentRunMissing.StatusCode) -ForegroundColor DarkGray

    # Release 2.0 Phase 2: refresh route contract. Unknown runs must 404
    # before any GitHub lookup happens, so this stays offline-safe.
    $agentRunRefreshMissing = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/agent-runs/does-not-exist/refresh" -Body @{}
    Assert-Not503 -Name '/api/agent-runs/{runId}/refresh (unknown)' -Response $agentRunRefreshMissing
    if ([int]$agentRunRefreshMissing.StatusCode -ne 404) { throw "/api/agent-runs/{runId}/refresh for unknown runId expected HTTP 404, got $($agentRunRefreshMissing.StatusCode)" }
    Write-Host ("  /api/agent-runs/does-not-exist/refresh -> HTTP {0}" -f $agentRunRefreshMissing.StatusCode) -ForegroundColor DarkGray

    # The two assertions this suite already made about /api/roadmap/dispatch/execute
    # were both REFUSALS (quota 409, in-process 409), and both return before the
    # route reaches the code that actually enqueues. So the path the guided-
    # improvement wizard uses — the successful one — had no gate at all, and had
    # been broken since Release 3.0: the route dot-sourced a parameterised script
    # mid-request, which blanked the $runId it had just minted, and the wizard
    # died at its final step on "Cannot bind argument to parameter 'RunId'".
    # A contract proven only by its refusals is not proven.
    Write-Host '[STEP] Dispatch success path — the route the wizard uses must actually enqueue' -ForegroundColor Cyan
    $okSettingsPath = $script:HostSettingsPath
    $okSettingsBackup = if (Test-Path -LiteralPath $okSettingsPath) { Get-Content -LiteralPath $okSettingsPath -Raw -Encoding UTF8 } else { $null }
    $okRepoRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("dispatch-success-smoke-" + [guid]::NewGuid().ToString('n').Substring(0, 8))
    $okRepoPath = Join-Path $okRepoRoot 'dispatch-success-smoke'
    $okRunId = ''
    # Release 3.1 — the route now refuses to queue into an empty room, so the
    # success path has to supply the room. This is the operator's real heartbeat
    # file (its path derives from the workspace root), hence the backup.
    $heartbeatPath = Join-Path $WorkspaceRoot 'output\roadmap-task-runner.heartbeat.json'
    $heartbeatBackup = if (Test-Path -LiteralPath $heartbeatPath) { Get-Content -LiteralPath $heartbeatPath -Raw -Encoding UTF8 } else { $null }
    # Assigned before the try so the finally can always restore, including when
    # the step throws on its first line.
    $okQueuePath = $smokeQueuePath  # Release 2.9: the isolated queue, not the operator's
    $okQueueBefore = if (Test-Path -LiteralPath $okQueuePath) { @(Get-Content -LiteralPath $okQueuePath -Encoding UTF8 | Where-Object { $_ -and $_.Trim() }).Count } else { 0 }
    try {
        $null = New-Item -ItemType Directory -Path (Split-Path -Parent $heartbeatPath) -Force -ErrorAction SilentlyContinue
        Set-Content -LiteralPath $heartbeatPath -Encoding UTF8 -Value (([ordered]@{
            schemaVersion   = '1'
            hostname        = 'smoke-host'
            user            = 'smoke-operator'
            pid             = $PID
            mode            = 'interactive'
            pollSeconds     = 15
            claimedCount    = 0
            lastHeartbeatAt = (Get-Date).ToUniversalTime().ToString('o')
        }) | ConvertTo-Json -Depth 5)

        $null = New-Item -ItemType Directory -Path $okRepoPath -Force
        & git init "$okRepoPath" *>&1 | Out-Null
        Set-Content -LiteralPath (Join-Path $okRepoPath 'ROADMAP.md') -Encoding UTF8 `
            -Value "# Smoke`n`n## Release 1`n`n- [ ] A pending item the dispatch route can plan against`n"

        # Quota is forced generous so this step proves the ENQUEUE, not the guard —
        # the refusal case is asserted separately below.
        $okSettingsObject = if ($null -ne $okSettingsBackup -and -not [string]::IsNullOrWhiteSpace($okSettingsBackup)) {
            $okSettingsBackup | ConvertFrom-Json -Depth 20
        } else { [pscustomobject]@{} }
        $okSettingsObject | Add-Member -NotePropertyName budgetLedger -NotePropertyValue ([pscustomobject]@{}) -Force
        $okSettingsObject.budgetLedger = [pscustomobject]@{
            period         = (Get-Date).ToUniversalTime().ToString('yyyy-MM')
            quotaGuard     = [pscustomobject]@{
                softStopRemainingUnits = 0
                hardStopRemainingUnits = 0
                maxUnitsPerPhase       = 10000
                maxUnitsPerSession     = 10000
            }
            defaultProject = [pscustomobject]@{
                monthlyQuotaBudgetUnits = 100000
                monthlyBudgetUsd        = 1000
                priority                = 1
            }
        }
        Set-Content -LiteralPath $okSettingsPath -Value ($okSettingsObject | ConvertTo-Json -Depth 20) -Encoding UTF8

        $okResponse = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/roadmap/dispatch/execute" -Body @{
            repoName   = 'dispatch-success-smoke'
            localPath  = $okRepoPath
            prompt     = 'Smoke-test the successful enqueue path of the dispatch route.'
            baseBranch = 'smoke-base'
        }
        Assert-Not503 -Name '/api/roadmap/dispatch/execute (success)' -Response $okResponse
        if ([int]$okResponse.StatusCode -ne 200) {
            throw "/api/roadmap/dispatch/execute success path expected HTTP 200, got $($okResponse.StatusCode). Body=$($okResponse.Content)"
        }
        $okJson = $okResponse.Json
        if ($okJson.success -ne $true) { throw "/api/roadmap/dispatch/execute success path returned success=false. Body=$($okResponse.Content)" }
        $okRunId = [string]$okJson.data.runId
        if ([string]::IsNullOrWhiteSpace($okRunId)) {
            throw '/api/roadmap/dispatch/execute returned an empty runId; the caller has nothing to track the queued task by.'
        }
        if ([string]$okJson.data.status -ne 'queued') { throw "Expected status='queued', got '$($okJson.data.status)'" }
        if ([string]$okJson.data.branch -ne "roadmap/$okRunId") {
            throw ("Expected branch 'roadmap/{0}', got '{1}'" -f $okRunId, $okJson.data.branch)
        }

        # The queue line is the artifact the runner claims on. Its runId must be
        # the one the caller was told, and its baseBranch must be the one the
        # caller asked for — $baseBranch was clobbered by the same dot-source,
        # silently, which no status code would have revealed.
        $okQueueLines = @(Get-Content -LiteralPath $okQueuePath -Encoding UTF8 | Where-Object { $_ -and $_.Trim() })
        if ($okQueueLines.Count -le $okQueueBefore) { throw 'roadmap-task-queue.jsonl gained no entry after a successful dispatch' }
        $okEntry = $okQueueLines[-1] | ConvertFrom-Json
        if ([string]$okEntry.runId -ne $okRunId) { throw ("queue tail runId '{0}' does not match the returned runId '{1}'" -f $okEntry.runId, $okRunId) }
        if ([string]$okEntry.baseBranch -ne 'smoke-base') { throw ("queue entry lost the requested baseBranch: got '{0}'" -f $okEntry.baseBranch) }
        if ([string]$okEntry.dispatchTarget -ne 'copilot') { throw ("queue entry dispatchTarget expected 'copilot', got '{0}'" -f $okEntry.dispatchTarget) }
        if ([string]$okEntry.prompt -notmatch 'Smoke-test the successful enqueue') { throw 'queue entry did not carry the approved prompt' }

        $okSummaryPath = Join-Path $WorkspaceRoot ("output\roadmap-task-history\runs\{0}.summary.json" -f $okRunId)
        if (-not (Test-Path -LiteralPath $okSummaryPath -PathType Leaf)) {
            throw "No run summary at $okSummaryPath; a queue line with no summary is a task the runner never claims."
        }
        $okSummary = Get-Content -LiteralPath $okSummaryPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ([string]$okSummary.status -ne 'queued') { throw ("run summary status expected 'queued', got '{0}'" -f $okSummary.status) }

        # The response has to agree with the heartbeat it was authorised
        # against. `queuedWithoutRunner` true here would mean the route queued
        # into an empty room and called it a success.
        if ($okJson.data.runner.present -ne $true) {
            throw ("dispatch success path reported runner.present={0} with a fresh heartbeat on disk" -f $okJson.data.runner.present)
        }
        if ([bool]$okJson.data.queuedWithoutRunner) { throw 'dispatch success path reported queuedWithoutRunner=true with a live runner' }
        Write-Host ("  dispatch success path ok: runId={0} branch={1} baseBranch={2} queue+summary written, runner present" -f `
                $okRunId, $okJson.data.branch, $okEntry.baseBranch) -ForegroundColor DarkGray

        # ── The refused state, which is the one that matters here ───────────
        # Release 3.1 acceptance criterion: prove the DISABLED state, not the
        # happy path. Six entries reached `queued` with nothing able to claim
        # them because this route answered 200 and explained the problem
        # afterwards.
        Remove-Item -LiteralPath $heartbeatPath -Force -ErrorAction SilentlyContinue
        $strandedBefore = @(Get-Content -LiteralPath $okQueuePath -Encoding UTF8 | Where-Object { $_ -and $_.Trim() }).Count

        $refusedResponse = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/roadmap/dispatch/execute" -Body @{
            repoName   = 'dispatch-success-smoke'
            localPath  = $okRepoPath
            prompt     = 'Smoke-test the refusal when no runner can claim the work.'
            baseBranch = 'smoke-base'
        }
        Assert-Not503 -Name '/api/roadmap/dispatch/execute (runner absent)' -Response $refusedResponse
        if ([int]$refusedResponse.StatusCode -ne 409) {
            throw "/api/roadmap/dispatch/execute with no runner expected HTTP 409, got $($refusedResponse.StatusCode). Body=$($refusedResponse.Content)"
        }
        $refusedJson = $refusedResponse.Json
        if ([string]$refusedJson.category -ne 'runner-absent') {
            throw ("Expected category='runner-absent', got '{0}'" -f $refusedJson.category)
        }
        # The refusal must name the unmet precondition and how to meet it. A
        # 409 that says only "conflict" is the greyed button with no reason.
        if ([string]$refusedJson.error -notmatch 'Invoke-RoadmapTaskRunner') {
            throw ("The runner-absent refusal must name the command that meets the precondition. Got: {0}" -f $refusedJson.error)
        }
        if ([string]$refusedJson.data.overrideField -ne 'acknowledgeNoRunner') {
            throw ("The refusal must name its override field so capability is explained, not removed. Got: '{0}'" -f $refusedJson.data.overrideField)
        }
        # Nothing written is the whole point: a refusal that still queued would
        # be the original defect with a different status code.
        $strandedAfter = @(Get-Content -LiteralPath $okQueuePath -Encoding UTF8 | Where-Object { $_ -and $_.Trim() }).Count
        if ($strandedAfter -ne $strandedBefore) {
            throw ("A refused dispatch wrote {0} queue line(s); a 409 must write nothing." -f ($strandedAfter - $strandedBefore))
        }

        # ── The deliberate override ─────────────────────────────────────────
        # Capability explained, not removed: an operator who intends to start a
        # runner next can still queue, and is told what they just did.
        $forcedResponse = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/roadmap/dispatch/execute" -Body @{
            repoName            = 'dispatch-success-smoke'
            localPath           = $okRepoPath
            prompt              = 'Smoke-test the acknowledged queue-into-empty-room path.'
            baseBranch          = 'smoke-base'
            acknowledgeNoRunner = $true
        }
        Assert-Not503 -Name '/api/roadmap/dispatch/execute (acknowledged)' -Response $forcedResponse
        if ([int]$forcedResponse.StatusCode -ne 200) {
            throw "/api/roadmap/dispatch/execute with acknowledgeNoRunner expected HTTP 200, got $($forcedResponse.StatusCode). Body=$($forcedResponse.Content)"
        }
        $forcedJson = $forcedResponse.Json
        $forcedRunId = [string]$forcedJson.data.runId
        if (-not [bool]$forcedJson.data.queuedWithoutRunner) {
            throw 'An acknowledged dispatch into an empty room must report queuedWithoutRunner=true, or the operator cannot tell it is stranded.'
        }
        if ([int]$forcedJson.data.strandedCount -lt 1) {
            throw ("An acknowledged dispatch must count itself as stranded; got strandedCount={0}" -f $forcedJson.data.strandedCount)
        }
        if (-not [string]::IsNullOrWhiteSpace($forcedRunId)) {
            Remove-Item -LiteralPath (Join-Path $WorkspaceRoot ("output\roadmap-task-history\runs\{0}.summary.json" -f $forcedRunId)) -Force -ErrorAction SilentlyContinue
        }
        Write-Host ("  dispatch presence gate ok: 409 runner-absent wrote nothing and named the precondition; acknowledged override queued with stranded={0}" -f `
                $forcedJson.data.strandedCount) -ForegroundColor DarkGray
    }
    finally {
        if ($null -eq $okSettingsBackup) {
            Remove-Item -LiteralPath $okSettingsPath -Force -ErrorAction SilentlyContinue
        } else {
            Set-Content -LiteralPath $okSettingsPath -Value $okSettingsBackup -Encoding UTF8
        }
        # The operator's own heartbeat, put back exactly as found — this smoke
        # borrows the live file rather than a fixture path.
        if ($null -eq $heartbeatBackup) {
            Remove-Item -LiteralPath $heartbeatPath -Force -ErrorAction SilentlyContinue
        } else {
            Set-Content -LiteralPath $heartbeatPath -Value $heartbeatBackup -Encoding UTF8 -NoNewline
        }
        if (-not [string]::IsNullOrWhiteSpace($okRunId)) {
            Remove-Item -LiteralPath (Join-Path $WorkspaceRoot ("output\roadmap-task-history\runs\{0}.summary.json" -f $okRunId)) -Force -ErrorAction SilentlyContinue
        }
        # Fixture dispatches used to be left in the operator's real queue file
        # forever — this smoke's own entries, indistinguishable from work an
        # operator asked for. Trim back to what was there before the step.
        if (Test-Path -LiteralPath $okQueuePath) {
            $tailLines = @(Get-Content -LiteralPath $okQueuePath -Encoding UTF8)
            if ($tailLines.Count -gt $okQueueBefore) {
                if ($okQueueBefore -eq 0) {
                    Remove-Item -LiteralPath $okQueuePath -Force -ErrorAction SilentlyContinue
                } else {
                    Set-Content -LiteralPath $okQueuePath -Value ($tailLines | Select-Object -First $okQueueBefore) -Encoding UTF8
                }
            }
        }
        Remove-Item -LiteralPath $okRepoRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    Write-Host '[STEP] Dispatch quota guard contract (Release 2.0 Phase 4)' -ForegroundColor Cyan
    $settingsPath = $script:HostSettingsPath
    $settingsBackup = if (Test-Path -LiteralPath $settingsPath) { Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8 } else { $null }
    $agentEventsPath = Join-Path $WorkspaceRoot 'output\agent-runs\events.jsonl'
    $agentEventsBackup = if (Test-Path -LiteralPath $agentEventsPath) { Get-Content -LiteralPath $agentEventsPath -Raw -Encoding UTF8 } else { $null }
    $quotaRepoRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("dispatch-quota-smoke-" + [guid]::NewGuid().ToString('n').Substring(0, 8))
    $quotaRepoPath = Join-Path $quotaRepoRoot 'quota-dispatch-smoke'
    # A live heartbeat, so this step still tests the QUOTA guard. Without it the
    # Release 3.1 presence gate answers first and the assertion below would be
    # asserting the wrong refusal.
    $quotaHeartbeatPath = Join-Path $WorkspaceRoot 'output\roadmap-task-runner.heartbeat.json'
    $quotaHeartbeatBackup = if (Test-Path -LiteralPath $quotaHeartbeatPath) { Get-Content -LiteralPath $quotaHeartbeatPath -Raw -Encoding UTF8 } else { $null }
    try {
        Set-Content -LiteralPath $quotaHeartbeatPath -Encoding UTF8 -Value (([ordered]@{
            schemaVersion   = '1'
            hostname        = 'smoke-host'
            user            = 'smoke-operator'
            pid             = $PID
            mode            = 'interactive'
            pollSeconds     = 15
            claimedCount    = 0
            lastHeartbeatAt = (Get-Date).ToUniversalTime().ToString('o')
        }) | ConvertTo-Json -Depth 5)

        $null = New-Item -ItemType Directory -Path (Join-Path $quotaRepoPath '.git') -Force
        Set-Content -LiteralPath (Join-Path $quotaRepoPath 'ROADMAP.md') -Encoding UTF8 -Value @"
## Release 2.0 - Dispatch Budgets

**Goal:** Refuse over-budget dispatches before any GitHub dependency is required.

### Engineering milestones

- [ ] Add quota guard

### Phase plan

| Phase | Scope | Status | Completed | Token usage | Work units (est -> actual) |
| ----- | ----- | ------ | --------- | ----------- | -------------------------- |
| Phase 1: Quota guard | Enforce the pre-dispatch guard | in progress | - | - | est. 8 |
"@

        $settingsObject = if ($null -ne $settingsBackup -and -not [string]::IsNullOrWhiteSpace($settingsBackup)) {
            $settingsBackup | ConvertFrom-Json -Depth 20
        } else {
            [pscustomobject]@{}
        }
        $settingsObject | Add-Member -NotePropertyName budgetLedger -NotePropertyValue ([pscustomobject]@{}) -Force
        $settingsObject.budgetLedger = [pscustomobject]@{
            period = (Get-Date).ToUniversalTime().ToString('yyyy-MM')
            quotaGuard = [pscustomobject]@{
                softStopRemainingUnits = 10
                hardStopRemainingUnits = 5
                maxUnitsPerPhase = 1
                maxUnitsPerSession = 1
            }
            defaultProject = [pscustomobject]@{
                monthlyQuotaBudgetUnits = 20
                monthlyBudgetUsd = 6
                priority = 1
            }
        }
        $null = New-Item -ItemType Directory -Path (Split-Path -Path $settingsPath -Parent) -Force -ErrorAction SilentlyContinue
        Set-Content -LiteralPath $settingsPath -Value ($settingsObject | ConvertTo-Json -Depth 20) -Encoding UTF8

        $dispatchQuotaResponse = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/roadmap/dispatch/execute" -Body @{
            repoName = 'quota-dispatch-smoke'
            localPath = $quotaRepoPath
            prompt = 'Smoke-test quota refusal before GitHub dispatch.'
        }
        Assert-Not503 -Name '/api/roadmap/dispatch/execute (quota refusal)' -Response $dispatchQuotaResponse
        if ([int]$dispatchQuotaResponse.StatusCode -ne 409) { throw "/api/roadmap/dispatch/execute quota refusal expected HTTP 409, got $($dispatchQuotaResponse.StatusCode)" }
        $dispatchQuotaJson = $dispatchQuotaResponse.Json
        if ($dispatchQuotaJson.success -ne $false) { throw '/api/roadmap/dispatch/execute quota refusal expected success=false' }
        if ([string]$dispatchQuotaJson.error.code -ne 'quota-exhausted') { throw "Expected error.code='quota-exhausted', got '$($dispatchQuotaJson.error.code)'" }
        if ([string]$dispatchQuotaJson.error.data.reasonCode -ne 'session-cap-exceeded') { throw "Expected reasonCode='session-cap-exceeded', got '$($dispatchQuotaJson.error.data.reasonCode)'" }
        if ([double]$dispatchQuotaJson.error.data.estimatedWorkUnits -lt 1) { throw 'Expected quota refusal to report an estimatedWorkUnits value.' }
        Write-Host ("  /api/roadmap/dispatch/execute quota refusal -> reason={0} est={1}" -f $dispatchQuotaJson.error.data.reasonCode, $dispatchQuotaJson.error.data.estimatedWorkUnits) -ForegroundColor DarkGray
    }
    finally {
        if ($null -eq $settingsBackup) {
            Remove-Item -LiteralPath $settingsPath -Force -ErrorAction SilentlyContinue
        } else {
            Set-Content -LiteralPath $settingsPath -Value $settingsBackup -Encoding UTF8
        }

        if ($null -eq $agentEventsBackup) {
            Remove-Item -LiteralPath $agentEventsPath -Force -ErrorAction SilentlyContinue
        } else {
            Set-Content -LiteralPath $agentEventsPath -Value $agentEventsBackup -Encoding UTF8
        }

        if ($null -eq $quotaHeartbeatBackup) {
            Remove-Item -LiteralPath $quotaHeartbeatPath -Force -ErrorAction SilentlyContinue
        } else {
            Set-Content -LiteralPath $quotaHeartbeatPath -Value $quotaHeartbeatBackup -Encoding UTF8 -NoNewline
        }

        Remove-Item -LiteralPath $quotaRepoRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    # Release 2.0 Phase 3: merge-readiness route contracts (offline-safe).
    $mergeReadinessMissing = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/merge-readiness/does-not-exist"
    Assert-Not503 -Name '/api/merge-readiness/{repoId} (unknown)' -Response $mergeReadinessMissing
    if ([int]$mergeReadinessMissing.StatusCode -ne 404) { throw "/api/merge-readiness/{repoId} for unevaluated repoId expected HTTP 404, got $($mergeReadinessMissing.StatusCode)" }
    Write-Host ("  /api/merge-readiness/does-not-exist -> HTTP {0}" -f $mergeReadinessMissing.StatusCode) -ForegroundColor DarkGray

    # Evaluate for an unknown repo: 404 when the portfolio index exists, 409
    # when it has not been built yet — both prove the route is wired without
    # requiring GitHub access.
    $mergeEvaluateMissing = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/merge-readiness/does-not-exist/evaluate" -Body @{}
    Assert-Not503 -Name '/api/merge-readiness/{repoId}/evaluate (unknown)' -Response $mergeEvaluateMissing
    if ([int]$mergeEvaluateMissing.StatusCode -notin @(404, 409)) { throw "/api/merge-readiness/{repoId}/evaluate for unknown repoId expected HTTP 404 or 409, got $($mergeEvaluateMissing.StatusCode)" }
    Write-Host ("  /api/merge-readiness/does-not-exist/evaluate -> HTTP {0}" -f $mergeEvaluateMissing.StatusCode) -ForegroundColor DarkGray

    $mergeActionMissing = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/merge-readiness/does-not-exist/merge" -Body @{}
    Assert-Not503 -Name '/api/merge-readiness/{repoId}/merge (unknown)' -Response $mergeActionMissing
    if ([int]$mergeActionMissing.StatusCode -notin @(404, 409)) { throw "/api/merge-readiness/{repoId}/merge for unknown repoId expected HTTP 404 or 409, got $($mergeActionMissing.StatusCode)" }
    Write-Host ("  /api/merge-readiness/does-not-exist/merge -> HTTP {0}" -f $mergeActionMissing.StatusCode) -ForegroundColor DarkGray

    $copilotHistoryResponse = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/copilot-task/history?limit=5"
    Assert-Not503 -Name '/api/copilot-task/history' -Response $copilotHistoryResponse
    $copilotHistoryJson = $copilotHistoryResponse.Json
    if (-not $copilotHistoryJson.success) { throw '/api/copilot-task/history returned success=false' }
    $copilotHistoryItemsOk = ($copilotHistoryJson.data -and $copilotHistoryJson.data.PSObject.Properties.Name -contains 'items')
    Write-Host ("  /api/copilot-task/history -> {0} item(s)" -f @($copilotHistoryJson.data.items).Count) -ForegroundColor DarkGray

    Write-Host '[STEP] Roadmap audit routes (Release 0.8)' -ForegroundColor Cyan
    $roadmapAuditGetResponse  = Invoke-ApiRequest -Method Get  -Uri "$BaseUrl/api/roadmap/audit"
    $roadmapAuditScanResponse = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/roadmap/audit/scan" -Body @{}
    Assert-Not503 -Name '/api/roadmap/audit'      -Response $roadmapAuditGetResponse
    Assert-Not503 -Name '/api/roadmap/audit/scan' -Response $roadmapAuditScanResponse
    $roadmapAuditData     = $roadmapAuditGetResponse.Json
    $roadmapAuditScanData = $roadmapAuditScanResponse.Json
    if (-not $roadmapAuditData.success)     { throw '/api/roadmap/audit returned success=false' }
    if (-not $roadmapAuditScanData.success) { throw '/api/roadmap/audit/scan returned success=false' }
    Write-Host ("  /api/roadmap/audit -> {0} repos audited" -f $roadmapAuditData.data.count) -ForegroundColor DarkGray

    # Validate contract fields on the first entry (if any returned)
    $roadmapAuditFieldsOk = $true
    if ($roadmapAuditData.data.entries -and @($roadmapAuditData.data.entries).Count -gt 0) {
        $firstEntry = @($roadmapAuditData.data.entries)[0]
        $requiredFields = @('repoName','roadmapState','maturityLevel','maturityScore','pendingCount','completedCount','parsedAt')
        foreach ($field in $requiredFields) {
            if ($null -eq $firstEntry.$field -and $field -ne 'auditFindings') {
                Write-Host ("  WARNING: /api/roadmap/audit entry missing field '{0}'" -f $field) -ForegroundColor Yellow
                $roadmapAuditFieldsOk = $false
            }
        }
        $validLevels = @('L0-Absent','L1-Informal','L2-Structured','L3-Contract-Ready','L4-Orchestration-Ready')
        if ($firstEntry.maturityLevel -notin $validLevels) {
            Write-Host ("  WARNING: unexpected maturityLevel '{0}'" -f $firstEntry.maturityLevel) -ForegroundColor Yellow
            $roadmapAuditFieldsOk = $false
        }
        if ($roadmapAuditFieldsOk) {
            Write-Host ("  /api/roadmap/audit first entry: repo={0} maturityLevel={1} score={2}" -f $firstEntry.repoName, $firstEntry.maturityLevel, $firstEntry.maturityScore) -ForegroundColor DarkGray
        }
    }

    Write-Host '[STEP] Roadmap repair routes (Release 0.9)' -ForegroundColor Cyan
    # Pick a repo to use for repair preview (use first audit entry if available, else fallback to a dummy name)
    $repairTestRepoName = ''
    if ($roadmapAuditData.data.entries -and @($roadmapAuditData.data.entries).Count -gt 0) {
        $repairTestRepoName = [string](@($roadmapAuditData.data.entries)[0].repoName)
    }
    if (-not [string]::IsNullOrWhiteSpace($repairTestRepoName)) {
        $repairPreviewResponse = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/roadmap/repair/preview" -Body @{ repoName = $repairTestRepoName }
        Assert-Not503 -Name '/api/roadmap/repair/preview' -Response $repairPreviewResponse
        $repairPreviewJson = $repairPreviewResponse.Json
        if (-not $repairPreviewJson.success) { throw '/api/roadmap/repair/preview returned success=false' }
        $repairPreviewData = $repairPreviewJson.data
        $repairPreviewFieldsOk = $true
        $requiredRepairFields = @('previewId', 'previewState', 'repoName', 'completedItemCount', 'pendingItemCount', 'generatedAt')
        foreach ($field in $requiredRepairFields) {
            if ($null -eq $repairPreviewData.$field) {
                Write-Host ("  WARNING: /api/roadmap/repair/preview response missing field '{0}'" -f $field) -ForegroundColor Yellow
                $repairPreviewFieldsOk = $false
            }
        }
        $validRepairStates = @('repair-preview-ready', 'repair-blocked', 'rewrite-not-recommended')
        if ($repairPreviewData.previewState -notin $validRepairStates) {
            Write-Host ("  WARNING: unexpected previewState '{0}'" -f $repairPreviewData.previewState) -ForegroundColor Yellow
            $repairPreviewFieldsOk = $false
        }
        if ($repairPreviewFieldsOk) {
            Write-Host ("  /api/roadmap/repair/preview -> repo={0} previewState={1} actions={2}" -f $repairPreviewData.repoName, $repairPreviewData.previewState, @($repairPreviewData.repairActions).Count) -ForegroundColor DarkGray
        }

        $dispatchCheckResponse = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/roadmap/dispatch/check" -Body @{ repoName = $repairTestRepoName }
        Assert-Not503 -Name '/api/roadmap/dispatch/check' -Response $dispatchCheckResponse
        if ([int]$dispatchCheckResponse.StatusCode -ne 200 -or -not $dispatchCheckResponse.Json.success) {
            throw "/api/roadmap/dispatch/check failed for '$repairTestRepoName'. HTTP=$($dispatchCheckResponse.StatusCode) Body=$($dispatchCheckResponse.Content)"
        }
        $dispatchCheck = $dispatchCheckResponse.Json.data
        if ($null -eq $dispatchCheck.executionContract) { throw '/api/roadmap/dispatch/check missing shared executionContract verdict' }
        foreach ($field in @('model','sufficient','code','explanation','checks')) {
            if (-not ($dispatchCheck.executionContract.PSObject.Properties.Name -contains $field)) {
                throw "/api/roadmap/dispatch/check executionContract missing '$field'"
            }
        }
        if ([bool]$dispatchCheck.dispatchReady -ne [bool]$dispatchCheck.executionContract.sufficient) {
            throw '/api/roadmap/dispatch/check dispatchReady disagrees with the visible executionContract verdict'
        }
        if (-not $dispatchCheck.dispatchReady -and $null -eq $dispatchCheck.repairPreview) {
            throw '/api/roadmap/dispatch/check refused the contract without returning preview-first repair'
        }
        if ($dispatchCheck.dispatchReady -and ($null -eq $dispatchCheck.releasePacket -or -not $dispatchCheck.releasePacket.executionContract.sufficient)) {
            throw '/api/roadmap/dispatch/check admitted work without carrying the sufficient verdict into its release packet'
        }
        Write-Host ("  /api/roadmap/dispatch/check -> ready={0} verdict={1}" -f $dispatchCheck.dispatchReady, $dispatchCheck.executionContract.code) -ForegroundColor DarkGray
    } else {
        Write-Host '  /api/roadmap/repair/preview skipped (no audited repos available)' -ForegroundColor Yellow
        $repairPreviewFieldsOk = $true
    }

    $repairHistoryResponse = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/roadmap/repair/history?limit=5"
    Assert-Not503 -Name '/api/roadmap/repair/history' -Response $repairHistoryResponse
    $repairHistoryJson = $repairHistoryResponse.Json
    if (-not $repairHistoryJson.success) { throw '/api/roadmap/repair/history returned success=false' }
    $repairHistoryItemsOk = ($repairHistoryJson.data -and $repairHistoryJson.data.PSObject.Properties.Name -contains 'items')
    Write-Host ("  /api/roadmap/repair/history -> {0} item(s)" -f @($repairHistoryJson.data.items).Count) -ForegroundColor DarkGray

    Write-Host '[STEP] Roadmap repair submit-PR (Release 2.4, dry-run)' -ForegroundColor Cyan
    $submitPrBad = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/roadmap/repair/submit-pr" -Body @{}
    if ([int]$submitPrBad.StatusCode -ne 400) { throw "/api/roadmap/repair/submit-pr without repoName expected 400, got $($submitPrBad.StatusCode)" }
    $submitPr = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/roadmap/repair/submit-pr" -Body @{ repoName = 'github-repo-management'; previewId = 'smoke-preview' }
    if ([int]$submitPr.StatusCode -ne 200) { throw "/api/roadmap/repair/submit-pr expected 200, got $($submitPr.StatusCode). Body=$($submitPr.Content)" }
    if ($submitPr.Json.success -ne $true) { throw '/api/roadmap/repair/submit-pr returned success=false' }
    if ($submitPr.Json.data.dryRun -ne $true) { throw '/api/roadmap/repair/submit-pr default should be dryRun=true' }
    foreach ($f in @('branch', 'baseBranch', 'title', 'body')) {
        if (-not ($submitPr.Json.data.plan.PSObject.Properties.Name -contains $f)) { throw "/api/roadmap/repair/submit-pr plan missing '$f'" }
    }
    if ($submitPr.Json.data.created -ne $false) { throw '/api/roadmap/repair/submit-pr dry-run must report created=false' }

    # Release 2.7 Phase A — the live branch must be REACHABLE and must refuse
    # loudly. Before 2026-08-09 createPr=true returned 200 with created=false,
    # so a caller could not tell "refused" from "opened a PR". The refusal is
    # now 409 with a named reason; asserting it here exercises the live code
    # path without opening a PR, because the precondition check runs before any
    # git or GitHub call.
    $submitPrLive = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/roadmap/repair/submit-pr" -Body @{
        repoName = 'github-repo-management'; previewId = 'smoke-preview'; createPr = $true
    }
    if ([int]$submitPrLive.StatusCode -ne 409) {
        throw "/api/roadmap/repair/submit-pr with createPr=true and no proposedContent must refuse with 409, got $($submitPrLive.StatusCode). Body=$($submitPrLive.Content)"
    }
    if ($submitPrLive.Json.success -ne $false) { throw 'A submit-pr refusal must report success=false, never success=true with created=false' }
    if ([string]::IsNullOrWhiteSpace([string]$submitPrLive.Json.error)) { throw 'A submit-pr refusal must name its reason' }
    if ([string]$submitPrLive.Json.category -ne 'validation') {
        throw "submit-pr refusal for missing proposedContent expected category 'validation', got '$($submitPrLive.Json.category)'"
    }
    Write-Host ("  submit-pr ok: dry-run plan (branch={0}) created=false, no-repoName -> 400, live-without-content -> 409 '{1}'" -f $submitPr.Json.data.plan.branch, $submitPrLive.Json.category) -ForegroundColor DarkGray

    Write-Host '[STEP] Log tail route' -ForegroundColor Cyan
    $sinceIso = (Get-Date).ToUniversalTime().AddHours(-6).ToString('o')
    $encodedSinceIso = [uri]::EscapeDataString($sinceIso)
    $logTailResponse = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/log/tail?lines=20&since=$encodedSinceIso&level=INFO"
    Assert-Not503 -Name '/api/log/tail' -Response $logTailResponse
    $logTail = $logTailResponse.Json
    if (-not $logTail.success) { throw 'api/log/tail returned success=false' }
    if (-not ($logTail.PSObject.Properties.Name -contains 'source')) {
        throw '/api/log/tail response missing source field'
    }
    if ([string]$logTail.source -notin @('sqlite', 'jsonl')) {
        throw "/api/log/tail returned unexpected source '$($logTail.source)'"
    }
    foreach ($entry in @($logTail.entries)) {
        if ($null -eq $entry) { continue }
        $lvl = [string]$entry.level
        if (-not [string]::IsNullOrWhiteSpace($lvl) -and $lvl -ne 'INFO') {
            throw "/api/log/tail level filter failed; saw level '$lvl' while requesting INFO"
        }
    }
    Write-Host ("  /api/log/tail -> source={0} count={1}" -f [string]$logTail.source, @($logTail.entries).Count) -ForegroundColor DarkGray

    Write-Host '[STEP] Roadmap maturity history route (Release 2.1)' -ForegroundColor Cyan
    $maturityHistoryResponse = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/roadmap/maturity-history?days=30"
    Assert-Not503 -Name '/api/roadmap/maturity-history?days=30' -Response $maturityHistoryResponse
    $maturityHistory = $maturityHistoryResponse.Json
    if ($null -eq $maturityHistory -or -not $maturityHistory.success) {
        throw '/api/roadmap/maturity-history returned invalid success payload'
    }
    if (-not ($maturityHistory.PSObject.Properties.Name -contains 'data') -or -not ($maturityHistory.PSObject.Properties.Name -contains 'source')) {
        throw '/api/roadmap/maturity-history response missing expected fields (data, source)'
    }
    if ([string]$maturityHistory.source -notin @('sqlite', 'roadmap-audit-cache', 'none')) {
        throw "/api/roadmap/maturity-history returned unexpected source '$($maturityHistory.source)'"
    }
    foreach ($row in @($maturityHistory.data)) {
        if ($null -eq $row) { continue }
        foreach ($field in @('repoName', 'maturityLevel', 'maturityScore', 'capturedAt')) {
            if (-not ($row.PSObject.Properties.Name -contains $field)) {
                throw "/api/roadmap/maturity-history entry missing '$field'"
            }
        }
    }
    Write-Host ("  /api/roadmap/maturity-history -> source={0} count={1}" -f [string]$maturityHistory.source, @($maturityHistory.data).Count) -ForegroundColor DarkGray

    Write-Host '[STEP] Agent-run metrics history route (Release 2.1 Phase 3)' -ForegroundColor Cyan
    $runMetricsResponse = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/agent-runs/metrics-history?days=30"
    Assert-Not503 -Name '/api/agent-runs/metrics-history?days=30' -Response $runMetricsResponse
    $runMetrics = $runMetricsResponse.Json
    if ($null -eq $runMetrics -or -not $runMetrics.success) {
        throw '/api/agent-runs/metrics-history returned invalid success payload'
    }
    foreach ($metricsField in @('data', 'count', 'source')) {
        if (-not ($runMetrics.PSObject.Properties.Name -contains $metricsField)) {
            throw "/api/agent-runs/metrics-history response missing '$metricsField'"
        }
    }
    if ([string]$runMetrics.source -notin @('sqlite', 'agent-runs-json')) {
        throw "/api/agent-runs/metrics-history returned unexpected source '$($runMetrics.source)'"
    }
    foreach ($row in @($runMetrics.data)) {
        if ($null -eq $row) { continue }
        foreach ($field in @('runId', 'repoName', 'status', 'dispatchedAt', 'timeToDeliverSeconds', 'tokensReported', 'directCostUsd', 'workUnitsEstimated', 'phaseName')) {
            if (-not ($row.PSObject.Properties.Name -contains $field)) {
                throw "/api/agent-runs/metrics-history entry missing '$field'"
            }
        }
    }
    Write-Host ("  /api/agent-runs/metrics-history -> source={0} count={1}" -f [string]$runMetrics.source, @($runMetrics.data).Count) -ForegroundColor DarkGray

    Write-Host '[STEP] Quota burn-down history route (Release 2.1 Phase 3)' -ForegroundColor Cyan
    $quotaBurnResponse = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/agent-runs/quota-burn-history?days=30"
    Assert-Not503 -Name '/api/agent-runs/quota-burn-history?days=30' -Response $quotaBurnResponse
    $quotaBurn = $quotaBurnResponse.Json
    if ($null -eq $quotaBurn -or -not $quotaBurn.success) {
        throw '/api/agent-runs/quota-burn-history returned invalid success payload'
    }
    foreach ($quotaField in @('data', 'count', 'source')) {
        if (-not ($quotaBurn.PSObject.Properties.Name -contains $quotaField)) {
            throw "/api/agent-runs/quota-burn-history response missing '$quotaField'"
        }
    }
    if ([string]$quotaBurn.source -notin @('sqlite', 'none')) {
        throw "/api/agent-runs/quota-burn-history returned unexpected source '$($quotaBurn.source)'"
    }
    foreach ($row in @($quotaBurn.data)) {
        if ($null -eq $row) { continue }
        foreach ($field in @('repoName', 'budgetPeriod', 'evaluatedAt', 'unitsConsumed', 'remainingAfter', 'allowed')) {
            if (-not ($row.PSObject.Properties.Name -contains $field)) {
                throw "/api/agent-runs/quota-burn-history entry missing '$field'"
            }
        }
    }
    Write-Host ("  /api/agent-runs/quota-burn-history -> source={0} count={1}" -f [string]$quotaBurn.source, @($quotaBurn.data).Count) -ForegroundColor DarkGray

    Write-Host '[STEP] Execution queue routes (Release 1.0)' -ForegroundColor Cyan
    $execQueueResponse = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/execution/queue"
    Assert-Not503 -Name '/api/execution/queue' -Response $execQueueResponse
    $execQueueJson = $execQueueResponse.Json
    if (-not $execQueueJson.success) { throw '/api/execution/queue returned success=false' }
    $execQueueData = $execQueueJson.data
    $execQueueFieldsOk = $null -ne $execQueueData -and
        ($execQueueData.PSObject.Properties.Name -contains 'lanes') -and
        ($execQueueData.PSObject.Properties.Name -contains 'rankedQueue') -and
        ($execQueueData.PSObject.Properties.Name -contains 'stateCounts')
    if (-not $execQueueFieldsOk) { throw '/api/execution/queue response missing expected fields (lanes, rankedQueue, stateCounts)' }
    Write-Host ("  /api/execution/queue -> totalRepos={0} activeLanes={1}" -f $execQueueData.totalRepos, $execQueueData.activeLaneCount) -ForegroundColor DarkGray

    $execSyncResponse = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/execution/sync" -Body @{}
    Assert-Not503 -Name '/api/execution/sync' -Response $execSyncResponse
    $execSyncJson = $execSyncResponse.Json
    if (-not $execSyncJson.success) { throw '/api/execution/sync returned success=false' }
    Write-Host ("  /api/execution/sync -> totalRepos={0}" -f $execSyncJson.data.totalRepos) -ForegroundColor DarkGray

    # Test assign with no repoName — should return 400
    $execAssignMissingBody = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/execution/assign" -Body @{}
    if ($execAssignMissingBody.StatusCode -notin @(400, 409, 500)) {
        throw ("/api/execution/assign (no repoName) expected 4xx, got {0}" -f $execAssignMissingBody.StatusCode)
    }
    Write-Host ("  /api/execution/assign (no repoName) -> HTTP {0} correctly rejected" -f $execAssignMissingBody.StatusCode) -ForegroundColor DarkGray

    # Test assign with unknown repo — should return 409
    $execAssignUnknown = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/execution/assign" -Body @{ repoName = '__smoke-unknown-repo__' }
    if ($execAssignUnknown.StatusCode -notin @(400, 409, 500)) {
        throw ("/api/execution/assign (unknown repo) expected 4xx, got {0}" -f $execAssignUnknown.StatusCode)
    }
    Write-Host ("  /api/execution/assign (unknown repo) -> HTTP {0} correctly rejected" -f $execAssignUnknown.StatusCode) -ForegroundColor DarkGray

    # Test cancel with no repoName — should return 400
    $execCancelMissing = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/execution/cancel" -Body @{}
    if ($execCancelMissing.StatusCode -notin @(400, 409, 500)) {
        throw ("/api/execution/cancel (no repoName) expected 4xx, got {0}" -f $execCancelMissing.StatusCode)
    }
    Write-Host ("  /api/execution/cancel (no repoName) -> HTTP {0} correctly rejected" -f $execCancelMissing.StatusCode) -ForegroundColor DarkGray

    Write-Host '[STEP] Roadmap lint routes (Release 1.1)' -ForegroundColor Cyan
    # GET /api/roadmap/lint without repoName — should return 400
    $lintNoRepo = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/roadmap/lint"
    if ($lintNoRepo.StatusCode -notin @(400, 500)) {
        throw ("/api/roadmap/lint (no repoName) expected 4xx, got {0}" -f $lintNoRepo.StatusCode)
    }
    Write-Host ("  /api/roadmap/lint (no repoName) -> HTTP {0} correctly rejected" -f $lintNoRepo.StatusCode) -ForegroundColor DarkGray

    $lintScanResponse = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/roadmap/lint/scan" -Body @{}
    Assert-Not503 -Name '/api/roadmap/lint/scan' -Response $lintScanResponse
    $lintScanJson = $lintScanResponse.Json
    if (-not $lintScanJson.success) { throw '/api/roadmap/lint/scan returned success=false' }
    Write-Host ("  /api/roadmap/lint/scan -> count={0}" -f $lintScanJson.data.count) -ForegroundColor DarkGray

    Write-Host '[STEP] README standardization routes (Release 1.1)' -ForegroundColor Cyan
    # POST /api/readme/standardize/preview without repoName — should return 4xx
    $stdPreviewNoRepo = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/readme/standardize/preview" -Body @{}
    if ($stdPreviewNoRepo.StatusCode -notin @(400, 500)) {
        throw ("/api/readme/standardize/preview (no repoName) expected 4xx, got {0}" -f $stdPreviewNoRepo.StatusCode)
    }
    Write-Host ("  /api/readme/standardize/preview (no repoName) -> HTTP {0} correctly rejected" -f $stdPreviewNoRepo.StatusCode) -ForegroundColor DarkGray

    $stdHistoryResponse = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/readme/standardize/history?limit=5"
    Assert-Not503 -Name '/api/readme/standardize/history' -Response $stdHistoryResponse
    $stdHistoryJson = $stdHistoryResponse.Json
    if (-not $stdHistoryJson.success) { throw '/api/readme/standardize/history returned success=false' }
    Write-Host ("  /api/readme/standardize/history -> items={0}" -f @($stdHistoryJson.data.items).Count) -ForegroundColor DarkGray

    Write-Host '[STEP] Contract drift routes (Release 1.1)' -ForegroundColor Cyan
    $driftResponse = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/roadmap/drift"
    Assert-Not503 -Name '/api/roadmap/drift' -Response $driftResponse
    $driftJson = $driftResponse.Json
    if (-not $driftJson.success) { throw '/api/roadmap/drift returned success=false' }
    $driftFieldsOk = $null -ne $driftJson.data -and
        ($driftJson.data.PSObject.Properties.Name -contains 'driftAlerts') -and
        ($driftJson.data.PSObject.Properties.Name -contains 'driftCount')
    if (-not $driftFieldsOk) { throw '/api/roadmap/drift response missing expected fields (driftAlerts, driftCount)' }
    Write-Host ("  /api/roadmap/drift -> driftCount={0} baselineCount={1}" -f $driftJson.data.driftCount, $driftJson.data.baselineCount) -ForegroundColor DarkGray

    Write-Host '[STEP] Notification webhook routes (Release 1.1)' -ForegroundColor Cyan
    $webhooksResponse = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/notifications/webhooks"
    Assert-Not503 -Name '/api/notifications/webhooks' -Response $webhooksResponse
    $webhooksJson = $webhooksResponse.Json
    if (-not $webhooksJson.success) { throw '/api/notifications/webhooks returned success=false' }
    Write-Host ("  /api/notifications/webhooks -> count={0}" -f $webhooksJson.data.count) -ForegroundColor DarkGray

    # POST without url — should return 400
    $webhookRegNoUrl = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/notifications/webhooks" -Body @{}
    if ($webhookRegNoUrl.StatusCode -notin @(400, 500)) {
        throw ("/api/notifications/webhooks (no url) expected 4xx, got {0}" -f $webhookRegNoUrl.StatusCode)
    }
    Write-Host ("  /api/notifications/webhooks (no url) -> HTTP {0} correctly rejected" -f $webhookRegNoUrl.StatusCode) -ForegroundColor DarkGray

    Write-Host '[STEP] Roadmap completion preview route (Release 1.1)' -ForegroundColor Cyan
    # POST /api/roadmap/completion-preview without repoName — should return 400
    $completionPreviewNoRepo = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/roadmap/completion-preview" -Body @{}
    if ($completionPreviewNoRepo.StatusCode -notin @(400, 500)) {
        throw ("/api/roadmap/completion-preview (no repoName) expected 4xx, got {0}" -f $completionPreviewNoRepo.StatusCode)
    }
    Write-Host ("  /api/roadmap/completion-preview (no repoName) -> HTTP {0} correctly rejected" -f $completionPreviewNoRepo.StatusCode) -ForegroundColor DarkGray

    Write-Host '[STEP] Execution metrics route (Release 1.2)' -ForegroundColor Cyan
    $execMetricsResponse = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/execution/metrics"
    Assert-Not503 -Name '/api/execution/metrics' -Response $execMetricsResponse
    $execMetricsJson = $execMetricsResponse.Json
    if ($null -eq $execMetricsJson) {
        throw "/api/execution/metrics did not return JSON. HTTP $($execMetricsResponse.StatusCode). Content-Type=$($execMetricsResponse.ContentType). Body=$($execMetricsResponse.Content)"
    }
    if (-not ($execMetricsJson.PSObject.Properties.Name -contains 'success')) {
        throw "/api/execution/metrics response missing 'success'. Body=$($execMetricsResponse.Content)"
    }
    if (-not $execMetricsJson.success) {
        $err = if ($execMetricsJson.PSObject.Properties.Name -contains 'error') { $execMetricsJson.error } else { $execMetricsResponse.Content }
        throw "/api/execution/metrics returned success=false. HTTP $($execMetricsResponse.StatusCode). Error=$err"
    }
    if (-not ($execMetricsJson.PSObject.Properties.Name -contains 'data') -or $null -eq $execMetricsJson.data) {
        throw "/api/execution/metrics returned success=true but missing 'data'. Body=$($execMetricsResponse.Content)"
    }
    $execMetricsData = $execMetricsJson.data
    $execMetricsFieldsOk = $null -ne $execMetricsData -and
        ($execMetricsData.PSObject.Properties.Name -contains 'completedToday') -and
        ($execMetricsData.PSObject.Properties.Name -contains 'completedThisWeek') -and
        ($execMetricsData.PSObject.Properties.Name -contains 'errorRatePct') -and
        ($execMetricsData.PSObject.Properties.Name -contains 'stateCounts')
    if (-not $execMetricsFieldsOk) { throw '/api/execution/metrics response missing expected fields' }
    Write-Host ("  /api/execution/metrics -> completedToday={0} completedThisWeek={1} errorRatePct={2}" -f $execMetricsData.completedToday, $execMetricsData.completedThisWeek, $execMetricsData.errorRatePct) -ForegroundColor DarkGray

    Write-Host '[STEP] Auto-scan schedule route (Release 1.2)' -ForegroundColor Cyan
    $scanScheduleResponse = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/scan/schedule"
    Assert-Not503 -Name '/api/scan/schedule' -Response $scanScheduleResponse
    $scanScheduleJson = $scanScheduleResponse.Json
    if ($null -eq $scanScheduleJson) {
        throw "/api/scan/schedule did not return JSON. HTTP $($scanScheduleResponse.StatusCode). Content-Type=$($scanScheduleResponse.ContentType). Body=$($scanScheduleResponse.Content)"
    }
    if (-not ($scanScheduleJson.PSObject.Properties.Name -contains 'success')) {
        throw "/api/scan/schedule response missing 'success'. Body=$($scanScheduleResponse.Content)"
    }
    if (-not $scanScheduleJson.success) {
        $err = if ($scanScheduleJson.PSObject.Properties.Name -contains 'error') { $scanScheduleJson.error } else { $scanScheduleResponse.Content }
        throw "/api/scan/schedule returned success=false. HTTP $($scanScheduleResponse.StatusCode). Error=$err"
    }
    if (-not ($scanScheduleJson.PSObject.Properties.Name -contains 'data') -or $null -eq $scanScheduleJson.data) {
        throw "/api/scan/schedule returned success=true but missing 'data'. Body=$($scanScheduleResponse.Content)"
    }
    $scanScheduleData = $scanScheduleJson.data
    $scanScheduleFieldsOk = $null -ne $scanScheduleData -and
        ($scanScheduleData.PSObject.Properties.Name -contains 'enabled') -and
        ($scanScheduleData.PSObject.Properties.Name -contains 'intervalMinutes')
    if (-not $scanScheduleFieldsOk) { throw '/api/scan/schedule response missing expected fields (enabled, intervalMinutes)' }
    Write-Host ("  /api/scan/schedule -> enabled={0} intervalMinutes={1}" -f $scanScheduleData.enabled, $scanScheduleData.intervalMinutes) -ForegroundColor DarkGray

    Write-Host '[STEP] Roadmap dependency graph route (Release 1.2)' -ForegroundColor Cyan
    $depGraphResponse = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/roadmap/dependencies"
    Assert-Not503 -Name '/api/roadmap/dependencies' -Response $depGraphResponse
    $depGraphJson = $depGraphResponse.Json
    if ($null -eq $depGraphJson) {
        throw "/api/roadmap/dependencies did not return JSON. HTTP $($depGraphResponse.StatusCode). Content-Type=$($depGraphResponse.ContentType). Body=$($depGraphResponse.Content)"
    }
    if (-not ($depGraphJson.PSObject.Properties.Name -contains 'success')) {
        throw "/api/roadmap/dependencies response missing 'success'. Body=$($depGraphResponse.Content)"
    }
    if (-not $depGraphJson.success) {
        $err = if ($depGraphJson.PSObject.Properties.Name -contains 'error') { $depGraphJson.error } else { $depGraphResponse.Content }
        throw "/api/roadmap/dependencies returned success=false. HTTP $($depGraphResponse.StatusCode). Error=$err"
    }
    if (-not ($depGraphJson.PSObject.Properties.Name -contains 'data') -or $null -eq $depGraphJson.data) {
        throw "/api/roadmap/dependencies returned success=true but missing 'data'. Body=$($depGraphResponse.Content)"
    }
    $depGraphData = $depGraphJson.data
    $depGraphFieldsOk = $null -ne $depGraphData -and
        ($depGraphData.PSObject.Properties.Name -contains 'totalEdges') -and
        ($depGraphData.PSObject.Properties.Name -contains 'summary') -and
        ($depGraphData.PSObject.Properties.Name -contains 'scannedAt')
    if (-not $depGraphFieldsOk) { throw '/api/roadmap/dependencies response missing expected fields (totalEdges, summary, scannedAt)' }
    Write-Host ("  /api/roadmap/dependencies -> totalEdges={0} summaryCount={1}" -f $depGraphData.totalEdges, @($depGraphData.summary).Count) -ForegroundColor DarkGray

    # ------------------------------------------------------------------
    # Portfolio fixture setup — required for Phase 5 proofs
    # ------------------------------------------------------------------
    # In CI the WorkspaceRoot is the management tool itself; there are no
    # sub-git-repos so Get-LocalFolderInventory returns 0 items and the
    # portfolio is always empty.  Create a minimal fixture repo directory
    # and point the API host at it before the Release 1.7.5 tests run.
    Write-Host '[STEP] Portfolio fixture: seed managed-repo for assessment proofs' -ForegroundColor Cyan
    $portfolioFixtureRoot = Join-Path $smokeRoot 'portfolio-fixture-repos'
    $fixtureRepoPath      = Join-Path $portfolioFixtureRoot 'smoke-managed-repo'
    $null = New-Item -ItemType Directory -Path $portfolioFixtureRoot -Force
    & git init "$fixtureRepoPath" *>&1 | Out-Null
    if (Test-Path (Join-Path $fixtureRepoPath '.git')) {
        Set-Content -LiteralPath (Join-Path $fixtureRepoPath 'README.md') `
            -Value "# Smoke Fixture Repo`nFixture for portfolio assessment proofs." -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $fixtureRepoPath 'ROADMAP.md') `
            -Value "# Smoke Fixture Roadmap`n`n## Release 1`n`n- [x] Completed item`n- [ ] Pending item`n" -Encoding UTF8
        Write-Host ("  fixture repo initialised -> {0}" -f $fixtureRepoPath) -ForegroundColor DarkGray
    } else {
        Write-Host '  WARNING: git init did not create .git — portfolio proofs may fail with count=0' -ForegroundColor Yellow
    }
    # This POST persists into the git-TRACKED backend/config/settings.json. Left
    # unrestored, it is how commit 69dcc2d shipped a WSL fixture path as the real
    # workspace root (ROADMAP Lane 0.1) — every scan from a clean checkout then
    # enumerated fixtures instead of the portfolio. The byte-exact backup was
    # taken at the first settings write above and is restored in the finally.
    $fixtureSettingsResponse = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/settings" `
        -Body @{ basePath = $portfolioFixtureRoot }
    if ($fixtureSettingsResponse.StatusCode -ne 200) {
        throw ("Fixture settings update failed: HTTP {0}. Body={1}" -f $fixtureSettingsResponse.StatusCode, $fixtureSettingsResponse.Content)
    }
    # Force a full portfolio rescan with the new root so both the in-memory
    # cache and the on-disk index reflect the fixture repo before the
    # Release 1.7.5 tests run.  Without this, the cache would still hold
    # the zero-entry result from the early warm call at line ~657.
    # ?refresh=true kicks the background worker and returns; it no longer scans
    # on the request thread. Wait for the fixture to reach the index, or every
    # Release 1.7.5 assertion below runs against the zero-entry result this call
    # was meant to replace.
    $null = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/portfolio/assessment?refresh=true"
    $null = Wait-ForPortfolioIndex -BaseUrl $BaseUrl -HostLogPath $logPath
    Write-Host '  portfolio scan root updated and index seeded with fixture repo' -ForegroundColor DarkGray

    # ------------------------------------------------------------------
    # Release 1.7.5 — Portfolio Mission Alignment
    # ------------------------------------------------------------------
    Write-Host '[STEP] Portfolio assessment route (Release 1.7.5)' -ForegroundColor Cyan
    $portfolioResponse = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/portfolio/assessment"
    Assert-Not503 -Name '/api/portfolio/assessment' -Response $portfolioResponse
    $portfolioJson = $portfolioResponse.Json
    if ($null -eq $portfolioJson) {
        throw "/api/portfolio/assessment did not return JSON. HTTP $($portfolioResponse.StatusCode). Content-Type=$($portfolioResponse.ContentType). Body=$($portfolioResponse.Content)"
    }
    if (-not ($portfolioJson.PSObject.Properties.Name -contains 'success')) {
        throw "/api/portfolio/assessment response missing 'success'. Body=$($portfolioResponse.Content)"
    }
    if (-not $portfolioJson.success) {
        $err = if ($portfolioJson.PSObject.Properties.Name -contains 'error') { $portfolioJson.error } else { $portfolioResponse.Content }
        throw "/api/portfolio/assessment returned success=false. HTTP $($portfolioResponse.StatusCode). Error=$err"
    }
    if (-not ($portfolioJson.PSObject.Properties.Name -contains 'data') -or $null -eq $portfolioJson.data) {
        throw "/api/portfolio/assessment returned success=true but missing 'data'. Body=$($portfolioResponse.Content)"
    }
    $portfolioData = $portfolioJson.data
    $portfolioFieldsOk = $null -ne $portfolioData -and
        ($portfolioData.PSObject.Properties.Name -contains 'entries') -and
        ($portfolioData.PSObject.Properties.Name -contains 'summary') -and
        ($portfolioData.PSObject.Properties.Name -contains 'signalSources') -and
        ($portfolioData.PSObject.Properties.Name -contains 'generatedAt')
    if (-not $portfolioFieldsOk) { throw '/api/portfolio/assessment response missing expected fields (entries, summary, signalSources, generatedAt)' }

    Write-Host '[STEP] Scan performance budget log (cross-cutting)' -ForegroundColor Cyan
    $null = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/portfolio/assessment?refresh=true"
    $hostLogContent = if (Test-Path -LiteralPath $logPath) { Get-Content -LiteralPath $logPath -Raw -ErrorAction SilentlyContinue } else { '' }
    if ($hostLogContent -notmatch 'scan-budget correlationId=\S+ prepMs=\d+ assessMs=\d+ indexWriteMs=\d+ totalMs=\d+') {
        throw 'scan performance budget log line (scan-budget prepMs/assessMs/indexWriteMs/totalMs) not found in host log after a scan'
    }
    Write-Host '  scan-budget log ok: per-phase timing (prep=discovery/git/GitHub, assess=audit, indexWrite) emitted' -ForegroundColor DarkGray

    # Release 3.2 — the portfolio read path has a DECLARED budget, and the
    # measured figure is served next to it. Enforcement is here: a warm read
    # that breaches its budget, or a read class with no declared budget at all
    # (which fails closed to withinBudget=false), fails this gate.
    Write-Host '[STEP] Portfolio read-path performance budget (Release 3.2)' -ForegroundColor Cyan
    $warmReadResponse = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/portfolio/assessment"
    Assert-Not503 -Name '/api/portfolio/assessment (warm)' -Response $warmReadResponse
    $warmReadData = if ($null -ne $warmReadResponse.Json) { $warmReadResponse.Json.data } else { $null }
    if ($null -eq $warmReadData) { throw '/api/portfolio/assessment (warm) returned no data payload for the read-budget check' }
    if (-not ($warmReadData.PSObject.Properties.Name -contains 'performance')) {
        throw '/api/portfolio/assessment does not report its performance budget. The measured figure must be served next to the budget it was judged against, not left in a log the operator has to go and find.'
    }
    $warmBudget = $warmReadData.performance
    foreach ($budgetField in @('readClass', 'declared', 'budgetMs', 'measuredMs', 'withinBudget', 'overByMs')) {
        if (-not ($warmBudget.PSObject.Properties.Name -contains $budgetField)) {
            throw "/api/portfolio/assessment performance block missing '$budgetField'"
        }
    }
    # The class judged and the class served must be the same string. Two
    # classifiers would be this repo's recurring "two figures, one truth" drift.
    if ([string]$warmBudget.readClass -ne [string]$warmReadData.cacheSource) {
        throw ("Read-budget class '{0}' does not match the served cacheSource '{1}'; the budget is judging a different path from the one that ran." -f $warmBudget.readClass, $warmReadData.cacheSource)
    }
    if (-not $warmBudget.declared) {
        throw ("Read class '{0}' has no declared budget, so it is unmeasured rather than fast. Declare it in backend/api-host/PerformanceBudget.ps1." -f $warmBudget.readClass)
    }
    if ([int]$warmBudget.budgetMs -le 0) { throw 'A declared read budget must be a positive number of milliseconds' }
    if (-not $warmBudget.withinBudget) {
        throw ("Portfolio read-path budget BREACHED: class={0} measuredMs={1} budgetMs={2} overByMs={3}" -f $warmBudget.readClass, $warmBudget.measuredMs, $warmBudget.budgetMs, $warmBudget.overByMs)
    }
    if ($hostLogContent -notmatch 'portfolio\.read-budget correlationId=\S+ route=\S+ class=\S+ measuredMs=\S+ budgetMs=\d+ withinBudget=\S+') {
        $hostLogContent = if (Test-Path -LiteralPath $logPath) { Get-Content -LiteralPath $logPath -Raw -ErrorAction SilentlyContinue } else { '' }
        if ($hostLogContent -notmatch 'portfolio\.read-budget correlationId=\S+ route=\S+ class=\S+ measuredMs=\S+ budgetMs=\d+ withinBudget=\S+') {
            throw 'read-budget TRACE line not found in host log after a portfolio read'
        }
    }
    Write-Host ("  read-path budget ok: class={0} measuredMs={1} budgetMs={2} withinBudget=True" -f $warmBudget.readClass, $warmBudget.measuredMs, $warmBudget.budgetMs) -ForegroundColor DarkGray

    $portfolioSummaryFieldsOk = $null -ne $portfolioData.summary -and
        ($portfolioData.summary.PSObject.Properties.Name -contains 'totalRepos') -and
        ($portfolioData.summary.PSObject.Properties.Name -contains 'byLifecycle') -and
        ($portfolioData.summary.PSObject.Properties.Name -contains 'bySourceCoverage') -and
        ($portfolioData.summary.PSObject.Properties.Name -contains 'readyForWorkCount') -and
        ($portfolioData.summary.PSObject.Properties.Name -contains 'blockedCount')
    if (-not $portfolioSummaryFieldsOk) { throw '/api/portfolio/assessment summary missing expected fields (totalRepos, byLifecycle, bySourceCoverage, readyForWorkCount, blockedCount)' }

    $portfolioEntryFieldsOk = $true
    if (@($portfolioData.entries).Count -gt 0) {
        $first = @($portfolioData.entries)[0]
        $portfolioEntryFieldsOk = $null -ne $first -and
            ($first.PSObject.Properties.Name -contains 'lifecycleState') -and
            ($first.PSObject.Properties.Name -contains 'sourceCoverage') -and
            ($first.PSObject.Properties.Name -contains 'recommendedAction') -and
            ($first.PSObject.Properties.Name -contains 'blockingReasons') -and
            ($first.PSObject.Properties.Name -contains 'pendingCount') -and
            ($first.PSObject.Properties.Name -contains 'nextPendingItem') -and
            ($first.PSObject.Properties.Name -contains 'executionContract') -and
            ($first.PSObject.Properties.Name -contains 'pendingItems') -and
            ($first.PSObject.Properties.Name -contains 'topValueItem')
        if (-not $portfolioEntryFieldsOk) { throw '/api/portfolio/assessment first entry missing canonical readiness fields' }
        if ([int]$first.pendingCount -ne [int]$first.pendingItemCount) {
            throw "/api/portfolio/assessment naming aliases disagree: pendingCount=$($first.pendingCount), pendingItemCount=$($first.pendingItemCount)"
        }
        if ($null -ne $first.nextPendingItem -and [string]$first.nextPendingItem.text -ne [string]$first.nextPendingItemText) {
            throw '/api/portfolio/assessment naming aliases disagree: nextPendingItem.text differs from nextPendingItemText'
        }
    }

    Write-Host ("  /api/portfolio/assessment -> count={0} ready={1} blocked={2} cacheSource={3}" -f $portfolioData.count, $portfolioData.summary.readyForWorkCount, $portfolioData.summary.blockedCount, $portfolioData.cacheSource) -ForegroundColor DarkGray

    Write-Host '[STEP] Portfolio trend route (Release 2.3 scaffold)' -ForegroundColor Cyan
    $portfolioTrendResponse = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/portfolio/trend?days=30"
    if ($null -eq $portfolioTrendResponse.Json -and [string]$portfolioTrendResponse.ContentType -like 'text/html*') {
        # Retry once: occasional path-shape mismatches used to fall through to
        # the SPA catch-all before route normalization.
        Start-Sleep -Milliseconds 200
        $portfolioTrendResponse = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/portfolio/trend?days=30"
    }
    Assert-Not503 -Name '/api/portfolio/trend?days=30' -Response $portfolioTrendResponse
    $portfolioTrendJson = $portfolioTrendResponse.Json
    if ($null -eq $portfolioTrendJson) {
        throw "/api/portfolio/trend did not return JSON. HTTP $($portfolioTrendResponse.StatusCode). Content-Type=$($portfolioTrendResponse.ContentType). Body=$($portfolioTrendResponse.Content)"
    }
    if (-not ($portfolioTrendJson.PSObject.Properties.Name -contains 'success')) {
        throw "/api/portfolio/trend response missing 'success'. Body=$($portfolioTrendResponse.Content)"
    }
    if (-not $portfolioTrendJson.success) {
        $err = if ($portfolioTrendJson.PSObject.Properties.Name -contains 'error') { $portfolioTrendJson.error } else { $portfolioTrendResponse.Content }
        throw "/api/portfolio/trend returned success=false. HTTP $($portfolioTrendResponse.StatusCode). Error=$err"
    }
    if (-not ($portfolioTrendJson.PSObject.Properties.Name -contains 'data') -or $null -eq $portfolioTrendJson.data) {
        throw "/api/portfolio/trend returned success=true but missing 'data'. Body=$($portfolioTrendResponse.Content)"
    }
    $portfolioTrendData = $portfolioTrendJson.data
    $portfolioTrendFieldsOk = $null -ne $portfolioTrendData -and
        ($portfolioTrendData.PSObject.Properties.Name -contains 'trendStatus') -and
        ($portfolioTrendData.PSObject.Properties.Name -contains 'seedSource') -and
        ($portfolioTrendData.PSObject.Properties.Name -contains 'summary') -and
        ($portfolioTrendData.PSObject.Properties.Name -contains 'series') -and
        ($portfolioTrendData.PSObject.Properties.Name -contains 'repoSparklines') -and
        ($portfolioTrendData.PSObject.Properties.Name -contains 'topCandidates') -and
        ($portfolioTrendData.PSObject.Properties.Name -contains 'availableDays') -and
        ($portfolioTrendData.PSObject.Properties.Name -contains 'generatedAt')
    if (-not $portfolioTrendFieldsOk) { throw '/api/portfolio/trend response missing expected fields (trendStatus, seedSource, summary, series, repoSparklines, topCandidates, availableDays, generatedAt)' }

    $portfolioTrendSummaryFieldsOk = $null -ne $portfolioTrendData.summary -and
        ($portfolioTrendData.summary.PSObject.Properties.Name -contains 'totalRepos') -and
        ($portfolioTrendData.summary.PSObject.Properties.Name -contains 'averageMaturityScore') -and
        ($portfolioTrendData.summary.PSObject.Properties.Name -contains 'averageDocumentationHealthScore')
    if (-not $portfolioTrendSummaryFieldsOk) { throw '/api/portfolio/trend summary missing expected fields (totalRepos, averageMaturityScore, averageDocumentationHealthScore)' }

    if ([string]$portfolioTrendData.trendStatus -notin @('history-backed', 'current-snapshot-only')) {
        throw '/api/portfolio/trend returned an unexpected trendStatus value'
    }
    if ([string]$portfolioTrendData.seedSource -notin @('portfolio-index', 'assessment-cache')) {
        throw '/api/portfolio/trend returned an unexpected seedSource value'
    }
    if (@($portfolioTrendData.series).Count -lt 1) {
        throw '/api/portfolio/trend returned no series entries'
    }

    Write-Host ("  /api/portfolio/trend -> status={0} availableDays={1} seed={2}" -f [string]$portfolioTrendData.trendStatus, [int]$portfolioTrendData.availableDays, [string]$portfolioTrendData.seedSource) -ForegroundColor DarkGray

    # Release 3.6 M5 - the trend carries foundation coverage and the leverage
    # family. Both are derived from ledgers; the assertion that matters is that
    # nothing fabricates a figure nobody measured.
    Write-Host '[STEP] Trend: foundation coverage + leverage (Release 3.6 M5)' -ForegroundColor Cyan
    $m5Trend = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/portfolio/trend?days=30"
    Assert-Not503 -Name '/api/portfolio/trend (M5)' -Response $m5Trend
    if ([string]$m5Trend.ContentType -notlike 'application/json*') { throw "/api/portfolio/trend did not return JSON (Content-Type=$($m5Trend.ContentType))" }
    $m5Data = $m5Trend.Json.data
    if ($null -eq $m5Data) { throw "/api/portfolio/trend returned no data. Body=$($m5Trend.Content)" }
    $m5Keys = @($m5Data.series | ForEach-Object { [string]$_.key })
    if ('foundationCoverage' -notin $m5Keys) { throw "/api/portfolio/trend carries no foundationCoverage series (got: $($m5Keys -join ', '))" }
    $m5Coverage = @($m5Data.series | Where-Object { [string]$_.key -eq 'foundationCoverage' })[0]
    if ([string]$m5Coverage.color -notin @('emerald', 'sky', 'amber', 'slate')) { throw "The coverage series color '$($m5Coverage.color)' is outside the palette the frontend accepts" }
    if (@($m5Coverage.points).Count -lt 1) { throw 'The coverage series carries no points' }
    foreach ($m5Point in @($m5Coverage.points)) {
        $m5Value = [double]$m5Point.value
        if ($m5Value -lt 0 -or $m5Value -gt 100) { throw "Coverage point $m5Value is outside 0-100; it is a percentage" }
    }
    if (-not ($m5Data.PSObject.Properties.Name -contains 'leverage') -or $null -eq $m5Data.leverage) { throw '/api/portfolio/trend carries no leverage payload' }
    $m5Leverage = $m5Data.leverage
    if (@($m5Leverage.metrics).Count -lt 5) { throw "The leverage family reported $(@($m5Leverage.metrics).Count) metric(s); the family names more than that" }
    foreach ($m5Metric in @($m5Leverage.metrics)) {
        if ([string]::IsNullOrWhiteSpace([string]$m5Metric.basis)) { throw "Leverage metric '$($m5Metric.key)' states no basis" }
        if (-not $m5Metric.available -and $null -ne $m5Metric.value) { throw "Leverage metric '$($m5Metric.key)' is unavailable but carries the value '$($m5Metric.value)'; an unmeasured figure must be null, never a 0" }
        if ($m5Metric.available -and $null -eq $m5Metric.value) { throw "Leverage metric '$($m5Metric.key)' claims to be available with no value" }
    }
    # The two the roadmap names but the product does not capture must be present
    # and honest - omitting them would let a reader mistake absence for zero.
    foreach ($m5Declared in @('operatorMinutesPerTask', 'recommendationsAccepted')) {
        $m5Named = @($m5Leverage.metrics | Where-Object { [string]$_.key -eq $m5Declared })
        if ($m5Named.Count -ne 1) { throw "The leverage family must name '$m5Declared' even though it is not captured" }
        if ($m5Named[0].available -ne $false) { throw "'$m5Declared' is not captured yet and must report available=false" }
    }
    Write-Host ("  trend M5 ok: foundationCoverage {0}% over {1} point(s) (color={2}); leverage {3} metric(s), {4} derived, uncaptured ones named and null" -f `
            $m5Coverage.points[-1].value, @($m5Coverage.points).Count, $m5Coverage.color, @($m5Leverage.metrics).Count, [int]$m5Leverage.availableCount) -ForegroundColor DarkGray

    Write-Host '[STEP] Operations repo index route (Release 1.8)' -ForegroundColor Cyan
    $operationsReposResponse = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/operations/repos"
    Assert-Not503 -Name '/api/operations/repos' -Response $operationsReposResponse
    $operationsReposJson = $operationsReposResponse.Json
    if ($null -eq $operationsReposJson) {
        throw "/api/operations/repos did not return JSON. HTTP $($operationsReposResponse.StatusCode). Content-Type=$($operationsReposResponse.ContentType). Body=$($operationsReposResponse.Content)"
    }
    if (-not ($operationsReposJson.PSObject.Properties.Name -contains 'success')) {
        throw "/api/operations/repos response missing 'success'. Body=$($operationsReposResponse.Content)"
    }
    if (-not $operationsReposJson.success) {
        $err = if ($operationsReposJson.PSObject.Properties.Name -contains 'error') { $operationsReposJson.error } else { $operationsReposResponse.Content }
        throw "/api/operations/repos returned success=false. HTTP $($operationsReposResponse.StatusCode). Error=$err"
    }
    if (-not ($operationsReposJson.PSObject.Properties.Name -contains 'data') -or $null -eq $operationsReposJson.data) {
        throw "/api/operations/repos returned success=true but missing 'data'. Body=$($operationsReposResponse.Content)"
    }
    $operationsReposData = $operationsReposJson.data
    $operationsRepoFieldsOk = $null -ne $operationsReposData -and
        ($operationsReposData.PSObject.Properties.Name -contains 'entries') -and
        ($operationsReposData.PSObject.Properties.Name -contains 'generatedAt') -and
        ($operationsReposData.PSObject.Properties.Name -contains 'count') -and
        ($operationsReposData.PSObject.Properties.Name -contains 'cacheSource')
    if (-not $operationsRepoFieldsOk) { throw '/api/operations/repos response missing expected fields (entries, generatedAt, count, cacheSource)' }
    if ([int]$operationsReposData.count -ne @($operationsReposData.entries).Count) {
        throw '/api/operations/repos count did not match the number of entries returned'
    }
    if ([string]$operationsReposData.cacheSource -notin @('portfolio-index', 'assessment-cache')) {
        throw '/api/operations/repos returned an unexpected cacheSource value'
    }
    # Release 3.2 — the other half of the portfolio read path carries the same
    # budget contract, judged against the class it actually served from.
    if (-not ($operationsReposData.PSObject.Properties.Name -contains 'performance')) {
        throw '/api/operations/repos does not report its performance budget alongside the data it served'
    }
    $operationsBudget = $operationsReposData.performance
    if ([string]$operationsBudget.readClass -ne [string]$operationsReposData.cacheSource) {
        throw ("Read-budget class '{0}' does not match the served cacheSource '{1}' on /api/operations/repos" -f $operationsBudget.readClass, $operationsReposData.cacheSource)
    }
    if (-not $operationsBudget.declared) {
        throw ("/api/operations/repos read class '{0}' has no declared budget; declare it in backend/api-host/PerformanceBudget.ps1" -f $operationsBudget.readClass)
    }
    if (-not $operationsBudget.withinBudget) {
        throw ("/api/operations/repos read-path budget BREACHED: class={0} measuredMs={1} budgetMs={2} overByMs={3}" -f $operationsBudget.readClass, $operationsBudget.measuredMs, $operationsBudget.budgetMs, $operationsBudget.overByMs)
    }
    Write-Host ("  /api/operations/repos read-budget ok: class={0} measuredMs={1} budgetMs={2}" -f $operationsBudget.readClass, $operationsBudget.measuredMs, $operationsBudget.budgetMs) -ForegroundColor DarkGray
    if (@($portfolioData.entries).Count -ne @($operationsReposData.entries).Count) {
        throw '/api/operations/repos count did not align with /api/portfolio/assessment for the default workspace scope'
    }

    if (@($operationsReposData.entries).Count -gt 0) {
        $firstOperationsRepo = @($operationsReposData.entries)[0]
        $operationsEntryFieldsOk = $null -ne $firstOperationsRepo -and
            ($firstOperationsRepo.PSObject.Properties.Name -contains 'repoId') -and
            ($firstOperationsRepo.PSObject.Properties.Name -contains 'repoName') -and
            ($firstOperationsRepo.PSObject.Properties.Name -contains 'localPath') -and
            ($firstOperationsRepo.PSObject.Properties.Name -contains 'defaultBranch') -and
            ($firstOperationsRepo.PSObject.Properties.Name -contains 'currentBranch') -and
            ($firstOperationsRepo.PSObject.Properties.Name -contains 'lifecycleState') -and
            ($firstOperationsRepo.PSObject.Properties.Name -contains 'recommendedAction')
        if (-not $operationsEntryFieldsOk) { throw '/api/operations/repos first entry missing expected fields (repoId, repoName, localPath, defaultBranch, currentBranch, lifecycleState, recommendedAction)' }

        $encodedOperationsRepoId = [uri]::EscapeDataString([string]$firstOperationsRepo.repoId)
        $operationsRepoDetailResponse = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/operations/repos/$encodedOperationsRepoId"
        Assert-Not503 -Name '/api/operations/repos/{repoId}' -Response $operationsRepoDetailResponse
        if ($operationsRepoDetailResponse.StatusCode -ne 200) {
            throw "/api/operations/repos/{repoId} expected HTTP 200, got $($operationsRepoDetailResponse.StatusCode)"
        }
        $operationsRepoDetailJson = $operationsRepoDetailResponse.Json
        if ($null -eq $operationsRepoDetailJson -or -not $operationsRepoDetailJson.success) {
            throw '/api/operations/repos/{repoId} returned invalid success payload'
        }
        if (-not ($operationsRepoDetailJson.PSObject.Properties.Name -contains 'data') -or $null -eq $operationsRepoDetailJson.data) {
            throw '/api/operations/repos/{repoId} response missing data payload'
        }
        $operationsRepoDetailData = $operationsRepoDetailJson.data
        $operationsRepoDetailFieldsOk = $null -ne $operationsRepoDetailData -and
            ($operationsRepoDetailData.PSObject.Properties.Name -contains 'repoId') -and
            ($operationsRepoDetailData.PSObject.Properties.Name -contains 'repo') -and
            ($operationsRepoDetailData.PSObject.Properties.Name -contains 'documentationContext') -and
            ($operationsRepoDetailData.PSObject.Properties.Name -contains 'docAudit') -and
            ($operationsRepoDetailData.PSObject.Properties.Name -contains 'roadmapAudit') -and
            ($operationsRepoDetailData.PSObject.Properties.Name -contains 'dispatchContext')
        if (-not $operationsRepoDetailFieldsOk) { throw '/api/operations/repos/{repoId} response missing expected fields (repoId, repo, documentationContext, docAudit, roadmapAudit, dispatchContext)' }
        if ([string]$operationsRepoDetailData.repoId -ne [string]$firstOperationsRepo.repoId) {
            throw '/api/operations/repos/{repoId} returned a mismatched repoId'
        }
        # Release 3.6 M2 (backend) — the outcome card reads from the payloads the
        # workspace already loads: an `outcome` summary on every list entry and
        # the full `conclusion` (+ contract) on the detail. Both must agree.
        if (-not ($firstOperationsRepo.PSObject.Properties.Name -contains 'outcome') -or $null -eq $firstOperationsRepo.outcome) { throw '/api/operations/repos entries carry no outcome summary' }
        $entryOutcome = $firstOperationsRepo.outcome
        if ([string]$entryOutcome.conclusion -notin @('strengthen', 'appropriate-as-is', 'insufficiently-understood')) { throw "entry outcome conclusion '$($entryOutcome.conclusion)' is outside the set" }
        if ([string]::IsNullOrWhiteSpace([string]$entryOutcome.reason)) { throw 'entry outcome carries an empty reason' }
        if ($entryOutcome.holds -ne $true) { throw "entry outcome for '$($firstOperationsRepo.repoName)' reports the conclusion contract broken" }
        if (-not ($operationsRepoDetailData.PSObject.Properties.Name -contains 'conclusion') -or $null -eq $operationsRepoDetailData.conclusion) { throw '/api/operations/repos/{repoId} carries no conclusion' }
        if ($operationsRepoDetailData.conclusionContract.holds -ne $true) { throw "/api/operations/repos/{repoId} conclusion contract violated: $(@($operationsRepoDetailData.conclusionContract.violations) -join '; ')" }
        if ([string]$operationsRepoDetailData.conclusion.conclusion -ne [string]$entryOutcome.conclusion -or [string]$operationsRepoDetailData.conclusion.reason -ne [string]$entryOutcome.reason) {
            throw 'The detail conclusion and the list-entry outcome summary disagree for the same repo'
        }
        if (@($operationsRepoDetailData.conclusion.domains).Count -lt 5) { throw 'The detail conclusion carries fewer than the five starting-set domains' }
        Write-Host ("  outcome on entries + conclusion on detail: {0} — {1}" -f $entryOutcome.conclusion, ([string]$entryOutcome.reason).Substring(0, [Math]::Min(90, ([string]$entryOutcome.reason).Length))) -ForegroundColor DarkGray
        Write-Host ("  /api/operations/repos/{repoId} -> repo=$($operationsRepoDetailData.repo.repoName) docFindings=$(@($operationsRepoDetailData.docAudit.findings).Count)") -ForegroundColor DarkGray
    }
    Write-Host ("  /api/operations/repos -> count={0} source={1}" -f $operationsReposData.count, [string]$operationsReposData.cacheSource) -ForegroundColor DarkGray

    # Release 3.6 milestone 1 — every indexed repository leaves with an
    # explainable conclusion. Content type is asserted first: the SPA fallback
    # answers 200 text/html for a route that does not exist.
    Write-Host '[STEP] Portfolio conclusions route (Release 3.6 M1) — every indexed repo leaves with a conclusion' -ForegroundColor Cyan
    $conclusionsResponse = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/portfolio/conclusions"
    Assert-Not503 -Name '/api/portfolio/conclusions' -Response $conclusionsResponse
    if ([string]$conclusionsResponse.ContentType -notlike 'application/json*') {
        throw "/api/portfolio/conclusions did not return JSON (HTTP $($conclusionsResponse.StatusCode), Content-Type=$($conclusionsResponse.ContentType)) — the SPA fallback is shadowing it"
    }
    if ($conclusionsResponse.StatusCode -ne 200) { throw "/api/portfolio/conclusions expected HTTP 200, got $($conclusionsResponse.StatusCode). Body=$($conclusionsResponse.Content)" }
    $conclusionsJson = $conclusionsResponse.Json
    if ($null -eq $conclusionsJson -or $conclusionsJson.success -ne $true -or $null -eq $conclusionsJson.data) { throw "/api/portfolio/conclusions did not return success=true with data. Body=$($conclusionsResponse.Content)" }
    $conclusionsData = $conclusionsJson.data
    foreach ($field in @('schemaVersion', 'model', 'generatedAt', 'count', 'totalCount', 'byConclusion', 'byKind', 'coverage', 'contract', 'items', 'cacheSource', 'performance')) {
        if (-not ($conclusionsData.PSObject.Properties.Name -contains $field)) { throw "/api/portfolio/conclusions response missing '$field'" }
    }
    if ([string]$conclusionsData.schemaVersion -ne 'v1') { throw "/api/portfolio/conclusions schemaVersion expected v1, got '$($conclusionsData.schemaVersion)'" }
    if ([int]$conclusionsData.totalCount -ne @($operationsReposData.entries).Count) {
        throw "/api/portfolio/conclusions covered $($conclusionsData.totalCount) repositories but the index holds $(@($operationsReposData.entries).Count) — a repository left without a conclusion"
    }
    if ([int]$conclusionsData.count -ne @($conclusionsData.items).Count) { throw '/api/portfolio/conclusions count did not match the number of items returned' }
    if ($conclusionsData.contract.holds -ne $true) {
        throw "/api/portfolio/conclusions contract violated on the live index: $(@($conclusionsData.contract.violations) -join '; ')"
    }
    $conclusionSet = @('strengthen', 'appropriate-as-is', 'insufficiently-understood')
    foreach ($item in @($conclusionsData.items)) {
        if ([string]::IsNullOrWhiteSpace([string]$item.reason)) { throw "Conclusion for '$($item.repoName)' has an empty reason" }
        if ([string]$item.conclusion -notin $conclusionSet) { throw "Conclusion for '$($item.repoName)' is '$($item.conclusion)', outside the set" }
        if (@($item.domains).Count -lt 5) { throw "Conclusion for '$($item.repoName)' carries $(@($item.domains).Count) domain records; the starting set is five" }
        if ([string]$item.conclusion -eq 'strengthen' -and [string]::IsNullOrWhiteSpace([string]$item.nextAction.route)) { throw "Conclusion for '$($item.repoName)' is strengthen but names no next action" }
    }
    # Release 3.2 read budget, judged against the class the index was served from.
    $conclusionsBudget = $conclusionsData.performance
    if ([string]$conclusionsBudget.readClass -ne [string]$conclusionsData.cacheSource) { throw ("Read-budget class '{0}' does not match the served cacheSource '{1}' on /api/portfolio/conclusions" -f $conclusionsBudget.readClass, $conclusionsData.cacheSource) }
    if (-not $conclusionsBudget.declared) { throw ("/api/portfolio/conclusions read class '{0}' has no declared budget" -f $conclusionsBudget.readClass) }
    if (-not $conclusionsBudget.withinBudget) { throw ("/api/portfolio/conclusions read-path budget BREACHED: class={0} measuredMs={1} budgetMs={2}" -f $conclusionsBudget.readClass, $conclusionsBudget.measuredMs, $conclusionsBudget.budgetMs) }

    $fixtureConclusion = @($conclusionsData.items | Where-Object { [string]$_.repoName -eq 'smoke-managed-repo' } | Select-Object -First 1)
    if ($fixtureConclusion.Count -eq 0) { throw "The seeded fixture 'smoke-managed-repo' has no conclusion" }
    $fixtureConclusion = $fixtureConclusion[0]

    # One repository, by the same four-way id the operations detail route accepts.
    $encodedConclusionRepoId = [uri]::EscapeDataString([string]$fixtureConclusion.repoId)
    $conclusionDetail = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/portfolio/conclusions/$encodedConclusionRepoId"
    if ([string]$conclusionDetail.ContentType -notlike 'application/json*' -or $conclusionDetail.StatusCode -ne 200) { throw "/api/portfolio/conclusions/{repoId} expected 200 JSON, got HTTP $($conclusionDetail.StatusCode) $($conclusionDetail.ContentType)" }
    if ($conclusionDetail.Json.success -ne $true -or [string]$conclusionDetail.Json.data.conclusion.repoId -ne [string]$fixtureConclusion.repoId) { throw '/api/portfolio/conclusions/{repoId} returned a mismatched or unsuccessful payload' }
    if ($conclusionDetail.Json.data.contract.holds -ne $true) { throw "/api/portfolio/conclusions/{repoId} contract violated: $(@($conclusionDetail.Json.data.contract.violations) -join '; ')" }
    $conclusionMissing = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/portfolio/conclusions/does-not-exist-$([guid]::NewGuid().ToString('n').Substring(0,8))"
    if ($conclusionMissing.StatusCode -ne 404 -or [string]$conclusionMissing.ContentType -notlike 'application/json*') { throw "/api/portfolio/conclusions/{unknown} expected 404 JSON, got HTTP $($conclusionMissing.StatusCode) $($conclusionMissing.ContentType)" }

    # The filter is a first-class view: appropriate-as-is must be as filterable as strengthen.
    $conclusionFiltered = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/portfolio/conclusions?conclusion=$([uri]::EscapeDataString([string]$fixtureConclusion.conclusion))"
    if ($conclusionFiltered.StatusCode -ne 200 -or $null -eq $conclusionFiltered.Json) { throw '/api/portfolio/conclusions?conclusion= did not return 200 JSON' }
    if (@($conclusionFiltered.Json.data.items | Where-Object { [string]$_.conclusion -ne [string]$fixtureConclusion.conclusion }).Count -ne 0) { throw '/api/portfolio/conclusions?conclusion= returned items outside the filter' }
    if ([int]$conclusionFiltered.Json.data.count -lt 1 -or [int]$conclusionFiltered.Json.data.totalCount -ne [int]$conclusionsData.totalCount) { throw '/api/portfolio/conclusions?conclusion= count/totalCount did not reconcile' }

    # Acceptance: a strengthen conclusion's next action is a route the console
    # can actually run — it must answer JSON 200 for the fixture repo.
    if ([string]$fixtureConclusion.conclusion -eq 'strengthen') {
        $fixtureAction = $fixtureConclusion.nextAction
        $fixtureActionBody = @{}
        foreach ($p in $fixtureAction.body.PSObject.Properties) { $fixtureActionBody[[string]$p.Name] = [string]$p.Value }
        $fixtureActionResponse = Invoke-ApiRequest -Method ([string]$fixtureAction.method) -Uri "$BaseUrl$($fixtureAction.route)" -Body $fixtureActionBody
        if ([string]$fixtureActionResponse.ContentType -notlike 'application/json*' -or $fixtureActionResponse.StatusCode -ne 200) {
            throw ("The fixture's next action {0} {1} answered HTTP {2} {3}; a strengthen conclusion must name an action the console can run. Body={4}" -f $fixtureAction.method, $fixtureAction.route, $fixtureActionResponse.StatusCode, $fixtureActionResponse.ContentType, $fixtureActionResponse.Content)
        }
        Write-Host ("  fixture next action {0} {1} -> HTTP 200 JSON" -f $fixtureAction.method, $fixtureAction.route) -ForegroundColor DarkGray
    }
    Write-Host ("  /api/portfolio/conclusions -> total={0} {1}; fixture '{2}' -> {3} (kind={4}); detail 200, unknown 404 JSON, filter reconciles; read-budget class={5} measuredMs={6}" -f `
            $conclusionsData.totalCount, (($conclusionsData.byConclusion.PSObject.Properties | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join ' '), `
            $fixtureConclusion.repoName, $fixtureConclusion.conclusion, $fixtureConclusion.kind, $conclusionsBudget.readClass, $conclusionsBudget.measuredMs) -ForegroundColor DarkGray

    Write-Host '[STEP] README content route (Release 1.8)' -ForegroundColor Cyan
    $readmeContentOk = $true
    if (@($operationsReposData.entries).Count -gt 0) {
        $firstOperationsRepo = @($operationsReposData.entries)[0]
        $encodedOperationsRepo = [uri]::EscapeDataString([string]$firstOperationsRepo.repoName)
        $readmeContentResponse = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/readme/content?repo=$encodedOperationsRepo"
        Assert-Not503 -Name '/api/readme/content?repo=' -Response $readmeContentResponse
        if ($firstOperationsRepo.hasReadme) {
            $readmeContentOk = ($readmeContentResponse.StatusCode -eq 200)
        } else {
            $readmeContentOk = ($readmeContentResponse.StatusCode -eq 404)
        }
    } else {
        Write-Host '  (no operations entries found — README content route skipped)' -ForegroundColor Yellow
    }

    Write-Host '[STEP] Portfolio assessment differential mode (Release 1.7.5 Phase 7A)' -ForegroundColor Cyan
    $portfolioDiffResponse = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/portfolio/assessment?scanMode=differential"
    Assert-Not503 -Name '/api/portfolio/assessment?scanMode=differential' -Response $portfolioDiffResponse
    $portfolioDiffJson = $portfolioDiffResponse.Json
    if ($null -eq $portfolioDiffJson -or -not $portfolioDiffJson.success) {
        throw '/api/portfolio/assessment?scanMode=differential returned invalid success payload'
    }
    if (-not ($portfolioDiffJson.PSObject.Properties.Name -contains 'data') -or $null -eq $portfolioDiffJson.data) {
        throw '/api/portfolio/assessment?scanMode=differential response missing data payload'
    }
    $portfolioDiffData = $portfolioDiffJson.data
    $portfolioDiffFieldsOk = $null -ne $portfolioDiffData -and
        ($portfolioDiffData.PSObject.Properties.Name -contains 'entries') -and
        ($portfolioDiffData.PSObject.Properties.Name -contains 'summary') -and
        ($portfolioDiffData.PSObject.Properties.Name -contains 'signalSources') -and
        ($portfolioDiffData.PSObject.Properties.Name -contains 'generatedAt')
    if (-not $portfolioDiffFieldsOk) { throw '/api/portfolio/assessment?scanMode=differential response missing expected fields (entries, summary, signalSources, generatedAt)' }

    $portfolioDiffSignalSources = $portfolioDiffData.signalSources
    $portfolioDiffModeObserved = $false
    if ($null -ne $portfolioDiffSignalSources -and ($portfolioDiffSignalSources.PSObject.Properties.Name -contains 'scanMode')) {
        $mode = [string]$portfolioDiffSignalSources.scanMode
        $portfolioDiffModeObserved = ($mode -in @('differential', 'differential-fallback-full'))
    }
    if (-not $portfolioDiffModeObserved) {
        throw '/api/portfolio/assessment?scanMode=differential did not report differential scan mode in signalSources.scanMode'
    }
    Write-Host ("  /api/portfolio/assessment?scanMode=differential -> count={0} mode={1}" -f $portfolioDiffData.count, [string]$portfolioDiffSignalSources.scanMode) -ForegroundColor DarkGray

    # ------------------------------------------------------------------
    # Release 2.3 Phase 5 — Repository curation and change-aware indexing
    # ------------------------------------------------------------------
    Write-Host '[STEP] Repository curation write round-trip (Release 2.3 Phase 5A/5C)' -ForegroundColor Cyan
    # Curate a repo with a local path: GitHub-only rows survive differential
    # merges via the persisted index but are legitimately absent from a forced
    # full reassessment (refresh-all does not enumerate GitHub-only repos), so
    # the refresh-all curation-survival assertion needs a local repo.
    $curationRepoId = ''
    $curationTargetRepo = @($operationsReposData.entries) |
        Where-Object { ($_.PSObject.Properties.Name -contains 'localPath') -and -not [string]::IsNullOrWhiteSpace([string]$_.localPath) } |
        Select-Object -First 1
    if ($null -ne $curationTargetRepo) {
        $curationRepoId = [string]$curationTargetRepo.repoId
        $encodedCurationRepoId = [uri]::EscapeDataString($curationRepoId)

        $curationInvalidResponse = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/operations/repos/$encodedCurationRepoId/curation" -Body @{ curationState = 'not-a-state' }
        if ($curationInvalidResponse.StatusCode -ne 400) {
            throw "POST curation with invalid state expected HTTP 400, got $($curationInvalidResponse.StatusCode)"
        }

        $curationWriteResponse = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/operations/repos/$encodedCurationRepoId/curation" -Body @{ curationState = 'favorite'; reason = 'api-host smoke' }
        if ($curationWriteResponse.StatusCode -ne 200) {
            throw "POST curation favorite expected HTTP 200, got $($curationWriteResponse.StatusCode). Body=$($curationWriteResponse.Content)"
        }
        $curationWriteJson = $curationWriteResponse.Json
        if ($null -eq $curationWriteJson -or -not $curationWriteJson.success) { throw 'POST curation favorite returned invalid success payload' }
        if ([string]$curationWriteJson.data.curationState -ne 'favorite') { throw "POST curation expected persisted state 'favorite', got '$($curationWriteJson.data.curationState)'" }
        if ([string]::IsNullOrWhiteSpace([string]$curationWriteJson.data.updatedAt)) { throw 'POST curation response missing updatedAt' }

        $curationReadBackResponse = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/operations/repos"
        $curationReadBackEntry = @($curationReadBackResponse.Json.data.entries) | Where-Object { [string]$_.repoId -eq $curationRepoId } | Select-Object -First 1
        if ($null -eq $curationReadBackEntry) { throw 'Curated repo missing from /api/operations/repos read-back' }
        if ([string]$curationReadBackEntry.curationState -ne 'favorite') { throw "/api/operations/repos read-back expected curationState=favorite, got '$($curationReadBackEntry.curationState)'" }
        Write-Host ("  curation persisted and read back -> repoId={0} state=favorite" -f $curationRepoId) -ForegroundColor DarkGray
    } else {
        Write-Host '  (no operations entries with a local path found — curation round-trip skipped)' -ForegroundColor Yellow
    }

    Write-Host '[STEP] Differential reuse proof: warm unchanged startup must not reindex (Release 2.3 Phase 5B/5F)' -ForegroundColor Cyan
    # This proof needs a WARM index; the scan that fills it is now the
    # background worker's job, not the request's.
    $warmEntryCount = Wait-ForPortfolioIndex -BaseUrl $BaseUrl -HostLogPath $logPath
    Write-Host ("  portfolio index warmed by the background worker -> {0} entr(ies)" -f $warmEntryCount) -ForegroundColor DarkGray

    $reuseProofResponse = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/portfolio/assessment?scanMode=differential&includeCuration=true"
    Assert-Not503 -Name '/api/portfolio/assessment?scanMode=differential&includeCuration=true' -Response $reuseProofResponse
    $reuseProofJson = $reuseProofResponse.Json
    if ($null -eq $reuseProofJson -or -not $reuseProofJson.success) { throw 'Differential reuse-proof call returned invalid success payload' }
    $reuseProofData = $reuseProofJson.data
    if (-not ($reuseProofData.PSObject.Properties.Name -contains 'scanSummary') -or $null -eq $reuseProofData.scanSummary) {
        throw 'Differential reuse-proof response missing scanSummary'
    }
    $reuseSummary = $reuseProofData.scanSummary
    foreach ($scanSummaryField in @('reused', 'reindexed', 'failed', 'durationMs')) {
        if (-not ($reuseSummary.PSObject.Properties.Name -contains $scanSummaryField)) { throw "scanSummary missing field '$scanSummaryField'" }
    }
    if ([int]$reuseProofData.count -lt 1) { throw 'Differential reuse-proof returned zero entries; cannot prove reuse' }
    # The core Phase 5 guarantee: with a warm index, ordinary startup reuses
    # every row whose signals did not change. GitHub metadata (Actions
    # timestamps, updatedAt) is fetched live per request, so a handful of
    # repos may legitimately drift between back-to-back calls — those must
    # carry a detected-change reason. What must never happen is wholesale
    # reindexing or reindexing without a stated change (cache-miss /
    # cache-invalid would mean the reuse machinery itself broke).
    if (([int]$reuseSummary.reused + [int]$reuseSummary.reindexed) -ne [int]$reuseProofData.count) {
        throw "scanSummary does not reconcile: reused=$($reuseSummary.reused) + reindexed=$($reuseSummary.reindexed) != count=$($reuseProofData.count)"
    }
    $reuseViolations = @($reuseProofData.entries | Where-Object {
        [string]$_.scanDecisionReason -notin @('reused-cache', 'new-commit', 'metadata-changed')
    } | ForEach-Object { "$($_.repoName)=$($_.scanDecisionReason)" })
    if ($reuseViolations.Count -gt 0) {
        throw "Differential startup reindexed repos without a detected change: $($reuseViolations -join ', ')"
    }
    $minimumReused = [int][math]::Ceiling([int]$reuseProofData.count * 0.9)
    if ([int]$reuseSummary.reused -lt $minimumReused) {
        $reindexedNames = @($reuseProofData.entries | Where-Object { [string]$_.scanDecisionReason -ne 'reused-cache' } | ForEach-Object { "$($_.repoName)=$($_.scanDecisionReason)" })
        throw "Expected at least $minimumReused of $($reuseProofData.count) repos reused on warm differential startup, got $($reuseSummary.reused). Non-reused: $($reindexedNames -join ', ')"
    }
    if ([int]$reuseSummary.reindexed -gt 0) {
        $driftNames = @($reuseProofData.entries | Where-Object { [string]$_.scanDecisionReason -ne 'reused-cache' } | ForEach-Object { "$($_.repoName)=$($_.scanDecisionReason)" })
        Write-Host ("  (live-signal drift tolerated: {0})" -f ($driftNames -join ', ')) -ForegroundColor Yellow
    }
    $entriesMissingDecision = @($reuseProofData.entries | Where-Object {
        -not ($_.PSObject.Properties.Name -contains 'scanDecisionReason') -or [string]::IsNullOrWhiteSpace([string]$_.scanDecisionReason)
    })
    if ($entriesMissingDecision.Count -gt 0) { throw "Differential entries missing scanDecisionReason: $($entriesMissingDecision.Count)" }
    $entriesMissingCuration = @($reuseProofData.entries | Where-Object { -not ($_.PSObject.Properties.Name -contains 'curationState') })
    if ($entriesMissingCuration.Count -gt 0) { throw "includeCuration=true entries missing curationState: $($entriesMissingCuration.Count)" }
    if (-not [string]::IsNullOrWhiteSpace($curationRepoId)) {
        $reuseCuratedEntry = @($reuseProofData.entries) | Where-Object { [string]$_.repoId -eq $curationRepoId } | Select-Object -First 1
        if ($null -eq $reuseCuratedEntry) { throw 'Curated repo missing from differential assessment entries' }
        if ([string]$reuseCuratedEntry.curationState -ne 'favorite') { throw "Differential entry expected curationState=favorite, got '$($reuseCuratedEntry.curationState)'" }
    }
    Write-Host ("  reuse proof -> count={0} reused={1} reindexed={2} durationMs={3}" -f $reuseProofData.count, $reuseSummary.reused, $reuseSummary.reindexed, $reuseSummary.durationMs) -ForegroundColor DarkGray

    Write-Host '[STEP] Refresh All forced full reassessment (Release 2.3 Phase 5E)' -ForegroundColor Cyan
    $refreshAllResponse = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/portfolio/assessment/refresh-all" -Body @{ reason = 'api-host smoke' }
    Assert-Not503 -Name '/api/portfolio/assessment/refresh-all' -Response $refreshAllResponse
    if ($refreshAllResponse.StatusCode -ne 200) {
        throw "POST /api/portfolio/assessment/refresh-all expected HTTP 200, got $($refreshAllResponse.StatusCode). Body=$($refreshAllResponse.Content)"
    }
    $refreshAllJson = $refreshAllResponse.Json
    if ($null -eq $refreshAllJson -or -not $refreshAllJson.success) { throw '/api/portfolio/assessment/refresh-all returned invalid success payload' }
    $refreshAllData = $refreshAllJson.data
    if (-not ($refreshAllData.PSObject.Properties.Name -contains 'generatedAt') -or [string]::IsNullOrWhiteSpace([string]$refreshAllData.generatedAt)) {
        throw '/api/portfolio/assessment/refresh-all response missing generatedAt'
    }
    if (-not ($refreshAllData.PSObject.Properties.Name -contains 'scanSummary') -or $null -eq $refreshAllData.scanSummary) {
        throw '/api/portfolio/assessment/refresh-all response missing scanSummary'
    }
    if ([int]$refreshAllData.scanSummary.reused -ne 0) { throw "Refresh All expected reused=0, got $($refreshAllData.scanSummary.reused)" }
    if ([int]$refreshAllData.scanSummary.reindexed -lt 1) { throw "Refresh All expected reindexed >= 1, got $($refreshAllData.scanSummary.reindexed)" }
    $nonForcedEntries = @($refreshAllData.entries | Where-Object { [string]$_.scanDecisionReason -ne 'forced-refresh' })
    if ($nonForcedEntries.Count -gt 0) {
        $nonForcedNames = @($nonForcedEntries | Select-Object -First 5 | ForEach-Object { "$($_.repoName)=$($_.scanDecisionReason)" })
        throw "Refresh All expected every entry to report scanDecisionReason=forced-refresh; violations: $($nonForcedNames -join ', ')"
    }
    if (-not [string]::IsNullOrWhiteSpace($curationRepoId)) {
        $refreshAllCuratedEntry = @($refreshAllData.entries) | Where-Object { [string]$_.repoId -eq $curationRepoId } | Select-Object -First 1
        if ($null -eq $refreshAllCuratedEntry) { throw 'Curated repo missing from refresh-all entries' }
        if ([string]$refreshAllCuratedEntry.curationState -ne 'favorite') {
            throw "Curation must survive a forced full refresh; expected favorite, got '$($refreshAllCuratedEntry.curationState)'"
        }
    }
    Write-Host ("  refresh-all -> reindexed={0} forced-refresh on all {1} entries" -f $refreshAllData.scanSummary.reindexed, @($refreshAllData.entries).Count) -ForegroundColor DarkGray

    if (-not [string]::IsNullOrWhiteSpace($curationRepoId)) {
        # Leave no operator-visible curation state behind in the live workspace.
        $curationResetResponse = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/operations/repos/$([uri]::EscapeDataString($curationRepoId))/curation" -Body @{ curationState = 'none'; reason = 'api-host smoke cleanup' }
        if ($curationResetResponse.StatusCode -ne 200) { throw "Curation cleanup expected HTTP 200, got $($curationResetResponse.StatusCode)" }
        Write-Host '  curation state reset to none (cleanup)' -ForegroundColor DarkGray
    }

    # ------------------------------------------------------------------
    # Release 1.3 — Production static frontend bundle
    # ------------------------------------------------------------------
    Write-Host '[STEP] Static frontend bundle (Release 1.3)' -ForegroundColor Cyan
    $distIndexHtmlPath = Join-Path $WorkspaceRoot 'frontend\dist\index.html'
    $staticIndexOk   = $false
    $staticAssetsOk  = $false
    $staticSkipped   = $false

    if (-not (Test-Path -LiteralPath $distIndexHtmlPath -PathType Leaf)) {
        Write-Host '  frontend/dist/index.html not found — static-bundle tests SKIPPED (run Start-App.ps1 -Rebuild first)' -ForegroundColor Yellow
        $staticSkipped = $true
        $staticIndexOk = $true   # not a failure
        $staticAssetsOk = $true
    } else {
        # Test 1: GET / returns 200 text/html (SPA index)
        $staticRootResponse = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/"
        if ($staticRootResponse.StatusCode -ne 200) {
            throw ("GET / expected HTTP 200, got {0}" -f $staticRootResponse.StatusCode)
        }
        $rootContentType = [string]$staticRootResponse.ContentType
        if ($rootContentType -notlike '*text/html*') {
            throw ("GET / expected text/html Content-Type, got '{0}'" -f $rootContentType)
        }
        $staticIndexOk = $true
        Write-Host ("  GET / -> HTTP 200 {0}" -f $rootContentType) -ForegroundColor DarkGray

        # Test 2: GET /assets/<hashed>.js returns correct MIME + Cache-Control immutable
        $assetsDir = Join-Path $WorkspaceRoot 'frontend\dist\assets'
        $jsFile = Get-ChildItem -LiteralPath $assetsDir -Filter '*.js' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -eq $jsFile) {
            Write-Host '  No .js file found in frontend/dist/assets — asset MIME test skipped' -ForegroundColor Yellow
            $staticAssetsOk = $true
        } else {
            $assetRelPath = '/assets/' + $jsFile.Name
            $assetResponse = Invoke-ApiRequest -Method Get -Uri "$BaseUrl$assetRelPath"
            if ($assetResponse.StatusCode -ne 200) {
                throw ("GET $assetRelPath expected HTTP 200, got {0}" -f $assetResponse.StatusCode)
            }
            $assetContentType = [string]$assetResponse.ContentType
            if ($assetContentType -notlike '*javascript*' -and $assetContentType -notlike '*application/js*') {
                throw ("GET $assetRelPath expected javascript Content-Type, got '{0}'" -f $assetContentType)
            }
            # Verify Cache-Control: immutable is set
            $assetRaw = Invoke-WebRequest -Uri "$BaseUrl$assetRelPath" -Method Get -UseBasicParsing -TimeoutSec 10 -SkipHttpErrorCheck
            $cacheControl = [string]$assetRaw.Headers['Cache-Control']
            if ($cacheControl -notlike '*immutable*') {
                throw ("GET $assetRelPath expected Cache-Control immutable, got '{0}'" -f $cacheControl)
            }
            $staticAssetsOk = $true
            Write-Host ("  GET {0} -> HTTP 200 {1} | Cache-Control: {2}" -f $assetRelPath, $assetContentType, $cacheControl) -ForegroundColor DarkGray
        }
    }

    # ── Route census (silent-deletion tripwire) ──────────────────────────────
    # Generalizes the reconcile-route regression: a route deleted in a "refactor"
    # (d2cc6cc/bfb3724) used to vanish silently because nothing asserted it still
    # existed. The naive check — "status must not be 404" — is ITSELF vacuous
    # here: this host serves the SPA index.html for any unmatched GET path, so a
    # silently-deleted API route returns HTTP 200 text/html, not 404. The real
    # discriminator is the content type: every live API route (including /metrics
    # and /health) returns application/json, whereas the SPA fallback returns
    # text/html. So a census route that stops returning JSON has been deleted and
    # is now being shadowed by the SPA catch-all. Heavy scan routes are exercised
    # by their own steps above; this census stays to instant/cached JSON routes.
    Write-Host '[STEP] app.db maintenance route (Release 2.7 Phase D)' -ForegroundColor Cyan
    # GET previews without mutating; POST prunes + VACUUMs. The property worth
    # asserting is that the trend-window floor survives the round trip — a
    # retention window configured below 180 days must be clamped up, not
    # honored, or the Release 2.9 trend accrual would be deleted by its own
    # maintenance job.
    $dbMaintenanceOk = $false
    $maintGet = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/maintenance/database"
    Assert-Not503 -Name '/api/maintenance/database (GET)' -Response $maintGet
    if ($null -eq $maintGet.Json -or -not $maintGet.Json.success) {
        throw "GET /api/maintenance/database returned success=false. HTTP $($maintGet.StatusCode). Body=$($maintGet.Content)"
    }
    if (-not [bool]$maintGet.Json.data.preview.reportOnly) {
        throw 'GET /api/maintenance/database must be report-only (preview.reportOnly=true) and never mutate.'
    }

    $maintPost = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/maintenance/database" -Body @{ maxSnapshotDays = 30 }
    Assert-Not503 -Name '/api/maintenance/database (POST)' -Response $maintPost
    if ($null -eq $maintPost.Json -or -not $maintPost.Json.success) {
        throw "POST /api/maintenance/database returned success=false. HTTP $($maintPost.StatusCode). Body=$($maintPost.Content)"
    }
    $maturityTable = @($maintPost.Json.data.tables | Where-Object { [string]$_.table -eq 'maturity_history' })
    if ($maturityTable.Count -ne 1) { throw 'Maintenance result missing the maturity_history table entry.' }
    if ([int]$maturityTable[0].retentionDays -lt 180) {
        throw "Retention floor breached over HTTP: a 30-day request must clamp maturity_history up to 180 days; got $($maturityTable[0].retentionDays)."
    }
    if (-not [bool]$maintPost.Json.data.vacuumed) {
        throw "POST /api/maintenance/database did not VACUUM: $($maintPost.Json.data.vacuumError)"
    }
    # The last-run result must now be visible, so an operator can tell a
    # maintenance job that is running from one that is merely configured.
    $maintGet2 = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/maintenance/database"
    if ($null -eq $maintGet2.Json.data.lastRun) {
        throw 'GET /api/maintenance/database must report lastRun after a POST.'
    }
    $dbMaintenanceOk = $true
    Write-Host ("  maintenance ok: report-only GET, POST removed={0} vacuumed={1} floor={2}d, lastRun surfaced" -f `
            $maintPost.Json.data.totalRowsRemoved, $maintPost.Json.data.vacuumed, $maturityTable[0].retentionDays) -ForegroundColor DarkGray

    Write-Host '[STEP] Ledger retention routes (Release 3.3 M1)' -ForegroundColor Cyan
    # The prune behavior itself is proven in the module smoke against
    # fixtures; this step proves the operator surface: a report-only GET that
    # states the policy and its named exclusions, a POST that applies it, and
    # a lastRun the next GET can see.
    $ledgerGet = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/maintenance/ledgers"
    Assert-Not503 -Name '/api/maintenance/ledgers (GET)' -Response $ledgerGet
    if ($null -eq $ledgerGet.Json -or -not $ledgerGet.Json.success) {
        throw "GET /api/maintenance/ledgers returned success=false. HTTP $($ledgerGet.StatusCode). Body=$($ledgerGet.Content)"
    }
    if ([int]$ledgerGet.Json.data.policy.keepDays -le 0) { throw 'Ledger retention policy must state keepDays.' }
    if (@($ledgerGet.Json.data.policy.exclusions).Count -lt 1) { throw 'Ledger retention policy must name its exclusions; an empty exclusion list means the scope tripwire is not covering anything.' }
    if (@($ledgerGet.Json.data.preview.reports).Count -lt 1) { throw 'Ledger retention preview must report per-target, even when targets are absent on this workspace.' }

    $ledgerPost = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/maintenance/ledgers" -Body @{}
    Assert-Not503 -Name '/api/maintenance/ledgers (POST)' -Response $ledgerPost
    if ($null -eq $ledgerPost.Json -or -not $ledgerPost.Json.success) {
        throw "POST /api/maintenance/ledgers returned success=false. HTTP $($ledgerPost.StatusCode). Body=$($ledgerPost.Content)"
    }
    $ledgerGet2 = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/maintenance/ledgers"
    if ($null -eq $ledgerGet2.Json.data.lastRun) {
        throw 'GET /api/maintenance/ledgers must report lastRun after a POST.'
    }
    Write-Host ("  ledger retention ok: policy keepDays={0} with {1} named exclusion(s), preview reports {2} target(s), POST applied, lastRun surfaced" -f `
            $ledgerGet.Json.data.policy.keepDays, @($ledgerGet.Json.data.policy.exclusions).Count, @($ledgerGet.Json.data.preview.reports).Count) -ForegroundColor DarkGray

    Write-Host '[STEP] AppDb backup routes (Release 3.3 M2)' -ForegroundColor Cyan
    # The rehearsed restore lives in the module smoke; this step proves the
    # operator surface: a POST that snapshots the live database, and a GET
    # that lists judgeable snapshots (manifest included). Restore is
    # deliberately not a route -- the host holds the database it would
    # overwrite -- so the GET carries the documented operator path instead.
    $bakPost = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/maintenance/backup" -Body @{}
    Assert-Not503 -Name '/api/maintenance/backup (POST)' -Response $bakPost
    if ($bakPost.StatusCode -eq 200 -and $bakPost.Json.success) {
        if ([string]::IsNullOrWhiteSpace([string]$bakPost.Json.data.backupPath)) { throw 'Backup succeeded without a backupPath.' }
        $bakGet = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/maintenance/backups"
        if ($null -eq $bakGet.Json -or -not $bakGet.Json.success) { throw "GET /api/maintenance/backups failed. Body=$($bakGet.Content)" }
        if ([int]$bakGet.Json.data.count -lt 1) { throw 'Backup list is empty right after a successful POST.' }
        if ([string]::IsNullOrWhiteSpace([string]$bakGet.Json.data.restoreNote)) { throw 'Backup list must carry the documented restore path.' }
        Write-Host ("  appdb backup ok: snapshot {0} ({1} bytes, schema v{2}); list shows {3} with manifests and the restore note" -f `
                (Split-Path -Leaf ([string]$bakPost.Json.data.backupPath)), $bakPost.Json.data.sizeBytes, $bakPost.Json.data.schemaVersion, $bakGet.Json.data.count) -ForegroundColor DarkGray
    }
    elseif ([string]$bakPost.Json.data.reason -eq 'source-missing') {
        # No app.db on this workspace (no SQLite provider): the same degraded
        # contract the persistence step accepts, said loudly.
        Write-Host '  appdb backup: no app.db on this workspace (degraded contract accepted; the module smoke rehearses backup/restore where a provider exists)' -ForegroundColor Yellow
    }
    else {
        throw "POST /api/maintenance/backup failed unexpectedly: HTTP $($bakPost.StatusCode). Body=$($bakPost.Content)"
    }

    Write-Host '[STEP] Automation status route (Release 2.7 Phase D)' -ForegroundColor Cyan
    $automationStatusOk = $false
    $autoStatus = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/automation/status"
    Assert-Not503 -Name '/api/automation/status' -Response $autoStatus
    if ($null -eq $autoStatus.Json -or -not $autoStatus.Json.success) {
        throw "GET /api/automation/status returned success=false. HTTP $($autoStatus.StatusCode). Body=$($autoStatus.Content)"
    }
    foreach ($autoField in @('enabled', 'intervalMinutes', 'overdue', 'healthy', 'lastOutcome', 'consecutiveFailures')) {
        if (-not ($autoStatus.Json.data.PSObject.Properties.Name -contains $autoField)) {
            throw "GET /api/automation/status missing '$autoField'. Body=$($autoStatus.Content)"
        }
    }
    # Automation is disabled by default in this repo's settings, and disabled
    # automation must never report itself overdue — a switched-off feature is
    # not a failure, and alerting on it would train the operator to ignore it.
    if (-not [bool]$autoStatus.Json.data.enabled -and [bool]$autoStatus.Json.data.overdue) {
        throw 'Disabled automation must not report overdue=true.'
    }
    # Phase C's packaging cron reports separately, on its own history file. A
    # single merged verdict would let a live doc cron mask a dead packaging one
    # (and vice versa), which is why the two readers exist at all — assert the
    # route actually carries both rather than the doc one twice.
    if (-not ($autoStatus.Json.data.PSObject.Properties.Name -contains 'packaging')) {
        throw "GET /api/automation/status missing the packaging health block. Body=$($autoStatus.Content)"
    }
    $pkgHealthBlock = $autoStatus.Json.data.packaging
    foreach ($pkgField in @('kind', 'enabled', 'intervalMinutes', 'overdue', 'healthy', 'lastOutcome', 'consecutiveFailures')) {
        if (-not ($pkgHealthBlock.PSObject.Properties.Name -contains $pkgField)) {
            throw "Packaging health block missing '$pkgField'. Body=$($autoStatus.Content)"
        }
    }
    if ([string]$pkgHealthBlock.kind -ne 'roadmap-packaging') {
        throw "Packaging health block must identify itself as roadmap-packaging; got '$($pkgHealthBlock.kind)'"
    }
    if ([string]$autoStatus.Json.data.kind -ne 'doc-refinement') {
        throw "The top-level health block must identify itself as doc-refinement; got '$($autoStatus.Json.data.kind)'"
    }
    if (-not [bool]$pkgHealthBlock.enabled -and [bool]$pkgHealthBlock.overdue) {
        throw 'Disabled packaging automation must not report overdue=true.'
    }
    $automationStatusOk = $true
    Write-Host ("  automation status ok: enabled={0} overdue={1} healthy={2} lastOutcome={3}; packaging reported separately (kind={4} healthy={5})" -f `
            $autoStatus.Json.data.enabled, $autoStatus.Json.data.overdue, $autoStatus.Json.data.healthy, $autoStatus.Json.data.lastOutcome, `
            $pkgHealthBlock.kind, $pkgHealthBlock.healthy) -ForegroundColor DarkGray

    # ------------------------------------------------------------------
    # Release 2.7 Phase C — scheduled roadmap-item packaging
    # ------------------------------------------------------------------
    # Proves the whole route path: rank the curated subset, package the
    # top-value item, refuse an over-budget one, and dispatch ONLY on an
    # explicit approval. Two fixture repos are used because the single
    # pre-existing fixture's roadmap is deliberately below L3.
    Write-Host '[STEP] Automation: scheduled roadmap-item packaging (Release 2.7 Phase C)' -ForegroundColor Cyan
    $packagingOk = $false
    $packagingRepoName = 'smoke-packaging-repo'
    $packagingOverName = 'smoke-packaging-overbudget'
    $packagingQueuePath = $smokeQueuePath  # Release 2.9: the isolated queue, not the operator's
    $packagingQueueBackup = if (Test-Path -LiteralPath $packagingQueuePath) { Get-Content -LiteralPath $packagingQueuePath -Raw -Encoding UTF8 } else { $null }
    $packagingCuratedIds = [System.Collections.Generic.List[string]]::new()
    $packagingDispatchRunId = ''
    try {
        # A contract-ready (L3+) fixture roadmap whose top-value item is
        # deliberately NOT its first pending item, so "packaged the top-ranked
        # item" cannot pass by accidentally taking the first one.
        $packagingRoadmapBody = @'
# {NAME} — Product & Engineering Roadmap

> Project status: Active
>
> Product direction: A fixture repository used by the api-host smoke to prove scheduled roadmap-item packaging end to end.

## 1. Product Intent

This repository exists only as a smoke fixture. It carries a contract-ready roadmap so the Release 2.7 Phase C packaging run has a real L3 target to rank, package, and queue for approval.

---

## 2. Product Principles

- **Deterministic** — the pending items are worded so value ranking is stable across runs.
- **Contract-ready** — the roadmap satisfies the L3 contract, so dispatch readiness is not the thing under test.

---

## 3. Current State Summary

The fixture ships a README and this roadmap. One release is active with two pending milestones, deliberately ordered so the highest-value item is not the first one.

---

## 4. Release Index

| Release | Status | Purpose | Dispatch readiness |
| --- | --- | --- | --- |
| 1.0 | active | Prove packaging against a contract-ready roadmap | ready |
| 1.1 | planned | Reserved for future fixture needs | planned |

---

## 5. Release Roadmap

## Release 1.0 — Packaging Fixture

> Status: active

**Goal:** give the scheduled packaging run a contract-ready roadmap whose top-value item is provably not its first pending item.

### Product outcomes

- The packaging run selects a top-value item rather than the first pending item.
- The selected item carries a value score and a rationale.

### Engineering milestones

- [x] Seed the fixture repository with a README *(completed: 2026-08-09)*
- [ ] Document the changelog format for the fixture
- [ ] Add the operator dashboard export route with smoke test coverage

### Acceptance criteria

- The packaging run packages exactly one item for this repository.
- The packaged item is the highest-value pending item.

### Out of scope

- Any real product behavior; this repository is a fixture.

### Validation plan

- Run `pwsh -File scripts/Invoke-ApiHostSmokeTest.ps1` and confirm it exits successfully.

### Risks and blockers

- None currently known.

### Dependencies

- None.

### Known issues

- None currently known.
{PHASEPLAN}
### Traceability

- Release 2.7 Phase C — scripts/Invoke-ApiHostSmokeTest.ps1.

---

## Release 1.1 — Reserved

> Status: planned

**Goal:** hold space for future fixture needs.

### Product outcomes

- None yet.

### Engineering milestones

- [ ] Reserved

### Acceptance criteria

- Not applicable.

### Out of scope

- Everything.

---

## 6. Recently Completed

- [x] Fixture repository created *(completed: 2026-08-09, from Release 1.0)*

---

## 7. Cross-Cutting Engineering Work

- [ ] Keep the fixture roadmap contract-ready.

---

## 8. Risks and Design Guardrails

### Risks

- The fixture could drift below L3 and silently stop exercising packaging.

### Guardrails

- Only one release may carry `Status: active` at a time.
- This smoke asserts the fixture audits to L3 or higher.
- The validation plan must name a runnable command in a code span; the execution-contract gate refuses prose-only verification.

---

## 9. Definition of Done for Release Execution

A release should not be marked `done` unless:

- All checklist items are implemented, moved, or explicitly blocked.
- Acceptance criteria are verifiably satisfied.
- Validation commands have been run.
'@
        # The over-budget twin differs only by a phase-plan estimate above the
        # quota guard's per-session cap, so the refusal is caused by the budget
        # and nothing else.
        $packagingOverPhasePlan = @'

### Phase plan

| Phase | Scope | Status | Completed | Work units |
| --- | --- | --- | --- | --- |
| Phase 1: Oversized | Deliberately larger than the per-session cap | planned | — | 99 |

'@
        foreach ($fixture in @(
            @{ Name = $packagingRepoName; PhasePlan = "`n" },
            @{ Name = $packagingOverName; PhasePlan = $packagingOverPhasePlan }
        )) {
            $fixtureDir = Join-Path $portfolioFixtureRoot $fixture.Name
            $null = New-Item -ItemType Directory -Path $fixtureDir -Force
            & git init "$fixtureDir" *>&1 | Out-Null
            Set-Content -LiteralPath (Join-Path $fixtureDir 'README.md') -Value ("# {0}`n`nFixture for Release 2.7 Phase C packaging proofs." -f $fixture.Name) -Encoding UTF8
            $fixtureRoadmap = $packagingRoadmapBody.Replace('{NAME}', $fixture.Name).Replace('{PHASEPLAN}', $fixture.PhasePlan)
            Set-Content -LiteralPath (Join-Path $fixtureDir 'ROADMAP.md') -Value $fixtureRoadmap -Encoding UTF8
        }
        # ?refresh=true no longer scans on the request thread — it kicks the
        # background worker and returns. Wait for the fixtures to actually land
        # in the index instead of assuming one round trip did it.
        $null = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/portfolio/assessment?refresh=true"
        # -RequireAuditedMaturity: the assertion below needs L3+, which only
        # exists once the roadmap-audit cache has an entry. Waiting only for
        # the name made this step race the worker.
        $null = Wait-ForPortfolioIndex -BaseUrl $BaseUrl -RequiredRepoNames @($packagingRepoName, $packagingOverName) -HostLogPath $logPath -RequireAuditedMaturity

        $packagingOpsResponse = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/operations/repos"
        $packagingEntries = @($packagingOpsResponse.Json.data.entries)
        foreach ($name in @($packagingRepoName, $packagingOverName)) {
            $entry = @($packagingEntries) | Where-Object { [string]$_.repoName -eq $name } | Select-Object -First 1
            if ($null -eq $entry) { throw "Packaging fixture '$name' was not indexed by /api/operations/repos" }
            if ([string]$entry.maturityLevel -notin @('L3-Contract-Ready', 'L4-Orchestration-Ready')) {
                # A fixture auditing to L0-Absent means the per-repo audit threw
                # (parse-error catch) or never saw the roadmap. Name the cause
                # from the host log before failing -- CI keeps no host-log
                # artifact, so this excerpt is the only diagnostic that leaves
                # the runner (first seen: PR #155, L0-Absent in CI only).
                if (Test-Path -LiteralPath $logPath) {
                    $auditTrail = @(Select-String -LiteralPath $logPath -Pattern 'audit-rule-failure|roadmap\.audit\.scan' -ErrorAction SilentlyContinue | Select-Object -Last 12)
                    if (@($auditTrail).Count -gt 0) {
                        Write-Host '  host-log audit trail (last 12 matching lines):' -ForegroundColor Yellow
                        foreach ($auditTrailLine in $auditTrail) { Write-Host ("    {0}" -f $auditTrailLine.Line) -ForegroundColor Yellow }
                    }
                }
                $entryStateDetail = ''
                try { $entryStateDetail = " roadmapState=$($entry.roadmapState)" } catch { $entryStateDetail = '' }
                throw "Packaging fixture '$name' audits to $($entry.maturityLevel)$entryStateDetail; the packaging gate needs L3+. Fix the fixture roadmap, not the gate."
            }
            $curateResponse = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/operations/repos/$([uri]::EscapeDataString([string]$entry.repoId))/curation" -Body @{ curationState = 'favorite'; reason = 'api-host smoke (Phase C)' }
            if ($curateResponse.StatusCode -ne 200) { throw "Curating '$name' failed: HTTP $($curateResponse.StatusCode)" }
            $packagingCuratedIds.Add([string]$entry.repoId)
        }
        $packagedEntry = @($packagingEntries) | Where-Object { [string]$_.repoName -eq $packagingRepoName } | Select-Object -First 1
        if ($null -eq $packagedEntry.topValueItem) { throw "Packaging fixture '$packagingRepoName' carries no topValueItem; the value scorer did not run over it" }

        # POST /api/automation/package-run — ranks, prices, packages, queues.
        $packageRun = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/automation/package-run" -Body @{}
        if ([int]$packageRun.StatusCode -ne 200) { throw "/api/automation/package-run expected 200, got $($packageRun.StatusCode). Body=$($packageRun.Content)" }
        if ($null -eq $packageRun.Json -or $packageRun.Json.success -ne $true) { throw "/api/automation/package-run did not return success=true. Body=$($packageRun.Content)" }
        $packageRunData = $packageRun.Json.data
        if ([int]$packageRunData.run.dispatchedCount -ne 0) { throw "A scheduled packaging run must never dispatch (dispatchedCount=$($packageRunData.run.dispatchedCount))" }
        if ([int]$packageRunData.run.appliedCount -ne 0) { throw "A scheduled packaging run must never apply (appliedCount=$($packageRunData.run.appliedCount))" }
        if ($packageRunData.delivered -ne $false) { throw '/api/automation/package-run with no webhook should report delivered=false' }

        $packagedPacket = @($packageRunData.run.packets) | Where-Object { [string]$_.repoName -eq $packagingRepoName } | Select-Object -First 1
        if ($null -eq $packagedPacket) { throw "The packaging run did not package the curated L3 fixture '$packagingRepoName'. Skipped=$(($packageRunData.run.skipped | ConvertTo-Json -Compress -Depth 4))" }
        # It must have packaged the TOP-VALUE item, not merely the first pending
        # one — the whole point of ranking.
        if ([int]$packagedPacket.roadmapOrder -le 1) { throw "Packaged item is the first pending item (roadmapOrder=$($packagedPacket.roadmapOrder)); ranking was not applied" }
        if ([string]$packagedPacket.itemText -eq [string]$packagedEntry.nextPendingItemText) { throw 'Packaged item equals the next pending item; ranking was not applied' }
        if ([string]$packagedPacket.itemText -ne [string]$packagedEntry.topValueItem.text) { throw "Packaged item '$($packagedPacket.itemText)' is not the entry's top-value item '$($packagedEntry.topValueItem.text)'" }
        if ([int]$packagedPacket.valueScore -le 0) { throw 'Packaged item carries no value score' }
        if ([string]::IsNullOrWhiteSpace([string]$packagedPacket.generatedPrompt)) { throw 'Packet carries no generated prompt' }
        if ($packagedPacket.repairPlan.submitted -ne $false) { throw 'The repair-PR plan must be a plan (submitted=false)' }
        if ($packagedPacket.dispatched -ne $false) { throw 'A freshly packaged item must be dispatched=false' }

        # The over-budget twin must be SKIPPED AND LOGGED, with the quota
        # guard's own code — not silently absent.
        if (@($packageRunData.run.packets | Where-Object { [string]$_.repoName -eq $packagingOverName }).Count -ne 0) {
            throw "The over-budget fixture '$packagingOverName' was packaged; the quota guard did not refuse it"
        }
        $overSkip = @($packageRunData.run.skipped) | Where-Object { [string]$_.repoName -eq $packagingOverName } | Select-Object -First 1
        if ($null -eq $overSkip) { throw "The over-budget fixture was dropped without a skip record" }
        if ([string]$overSkip.stage -ne 'quota') { throw "Expected the over-budget fixture to be skipped at stage=quota; got '$($overSkip.stage)'" }
        if ([string]$overSkip.reason -ne 'session-cap-exceeded') { throw "Expected blockedCode session-cap-exceeded; got '$($overSkip.reason)'" }

        # GET /api/automation/packages — the packet is queued for approval.
        $packagesList = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/automation/packages?status=pending-approval"
        if ([string]$packagesList.ContentType -notlike 'application/json*') { throw '/api/automation/packages did not return JSON' }
        if ($packagesList.Json.success -ne $true) { throw '/api/automation/packages did not return success=true' }
        $queuedPacket = @($packagesList.Json.data.items) | Where-Object { [string]$_.packetId -eq [string]$packagedPacket.packetId } | Select-Object -First 1
        if ($null -eq $queuedPacket) { throw 'The packaged item is not in the pending-approval queue' }
        if ([string]$queuedPacket.status -ne 'pending-approval') { throw "Queued packet status expected pending-approval; got '$($queuedPacket.status)'" }

        # Nothing may have been dispatched by the run itself.
        $queueAfterRun = if (Test-Path -LiteralPath $packagingQueuePath) { Get-Content -LiteralPath $packagingQueuePath -Raw -Encoding UTF8 } else { '' }
        if ([string]$queueAfterRun -match [regex]::Escape([string]$packagedPacket.branch)) {
            throw 'The packaging run enqueued work for the runner; it must stop at the approval gate.'
        }

        # An unknown packet is a 404 with a named category, not a 200.
        $approveUnknown = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/automation/packages/approve" -Body @{ packetId = 'no-such-packet' }
        if ([int]$approveUnknown.StatusCode -ne 404) { throw "Approving an unknown packet expected 404, got $($approveUnknown.StatusCode)" }
        if ([string]$approveUnknown.Json.category -ne 'packet-not-found') { throw "Expected category packet-not-found; got '$($approveUnknown.Json.category)'" }

        # Release 3.1 — approving into an empty room is refused, and the refusal
        # must leave NO trace. Prove that before the happy path: with no runner
        # heartbeat the packet must stay pending-approval, because `approved` may
        # only become `dispatched` or `dispatch-failed` — an approval recorded
        # here and then refused would strand the packet permanently.
        $approveHeartbeatPath = Join-Path $WorkspaceRoot 'output\roadmap-task-runner.heartbeat.json'
        $approveHeartbeatBackup = if (Test-Path -LiteralPath $approveHeartbeatPath) { Get-Content -LiteralPath $approveHeartbeatPath -Raw -Encoding UTF8 } else { $null }
        if (Test-Path -LiteralPath $approveHeartbeatPath) { Remove-Item -LiteralPath $approveHeartbeatPath -Force }
        $queueBeforeRefusal = if (Test-Path -LiteralPath $packagingQueuePath) { Get-Content -LiteralPath $packagingQueuePath -Raw -Encoding UTF8 } else { '' }
        $approveNoRunner = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/automation/packages/approve" -Body @{ packetId = [string]$packagedPacket.packetId; actor = 'api-host-smoke' }
        if ([int]$approveNoRunner.StatusCode -ne 409) { throw "Approving with no runner expected 409, got $($approveNoRunner.StatusCode). Body=$($approveNoRunner.Content)" }
        if ([string]$approveNoRunner.Json.category -ne 'runner-absent') { throw "Expected category runner-absent; got '$($approveNoRunner.Json.category)'" }
        if ([string]$approveNoRunner.Json.data.status -ne 'pending-approval') { throw "A refused approval must leave the packet pending-approval so it can be approved again; got '$($approveNoRunner.Json.data.status)'" }
        $queueAfterRefusal = if (Test-Path -LiteralPath $packagingQueuePath) { Get-Content -LiteralPath $packagingQueuePath -Raw -Encoding UTF8 } else { '' }
        if ([string]$queueAfterRefusal -ne [string]$queueBeforeRefusal) { throw 'A refused approval wrote to the runner queue; the gate must precede every write.' }

        # A present runner: the same call now goes through, which also proves the
        # refusal above was the gate and not a broken route.
        ([pscustomobject]@{
                hostname = 'api-host-smoke'; user = 'smoke'; pid = 4242; mode = 'copilot'
                pollSeconds = 5; claimedCount = 0; lastHeartbeatAt = ([datetime]::UtcNow).ToString('o')
            } | ConvertTo-Json -Depth 5) | Set-Content -LiteralPath $approveHeartbeatPath -Encoding UTF8

        # The explicit approval action — the only path to dispatch.
        $approve = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/automation/packages/approve" -Body @{ packetId = [string]$packagedPacket.packetId; actor = 'api-host-smoke' }
        if ([int]$approve.StatusCode -ne 200) { throw "Approving the packet expected 200, got $($approve.StatusCode). Body=$($approve.Content)" }
        if ([string]$approve.Json.data.status -ne 'dispatched') { throw "Approval expected status=dispatched; got '$($approve.Json.data.status)'" }
        $packagingDispatchRunId = [string]$approve.Json.data.dispatchRunId
        if ([string]::IsNullOrWhiteSpace($packagingDispatchRunId)) { throw 'Approval did not return a dispatch run id' }
        $queueAfterApprove = if (Test-Path -LiteralPath $packagingQueuePath) { Get-Content -LiteralPath $packagingQueuePath -Raw -Encoding UTF8 } else { '' }
        if ([string]$queueAfterApprove -notmatch [regex]::Escape($packagingDispatchRunId)) { throw 'Approval did not enqueue the task for the operator runner' }
        $packagingSummaryPath = Join-Path $WorkspaceRoot ("output\roadmap-task-history\runs\{0}.summary.json" -f $packagingDispatchRunId)
        if (-not (Test-Path -LiteralPath $packagingSummaryPath)) { throw 'Approval did not write the run summary the operator runner claims on' }
        if ([string]((Get-Content -LiteralPath $packagingSummaryPath -Raw -Encoding UTF8 | ConvertFrom-Json).status) -ne 'queued') {
            throw 'The dispatched run summary must read status=queued for the runner to claim it'
        }

        # The operator's heartbeat, put back exactly as found.
        if ($null -ne $approveHeartbeatBackup) {
            Set-Content -LiteralPath $approveHeartbeatPath -Value $approveHeartbeatBackup -Encoding UTF8 -NoNewline
        }
        elseif (Test-Path -LiteralPath $approveHeartbeatPath) {
            Remove-Item -LiteralPath $approveHeartbeatPath -Force
        }

        # A dispatched packet is terminal: re-approving is a 409, never a second dispatch.
        $reapprove = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/automation/packages/approve" -Body @{ packetId = [string]$packagedPacket.packetId; actor = 'api-host-smoke' }
        if ([int]$reapprove.StatusCode -ne 409) { throw "Re-approving a dispatched packet expected 409, got $($reapprove.StatusCode)" }
        if ([string]$reapprove.Json.category -notlike 'invalid-transition*') { throw "Expected an invalid-transition category; got '$($reapprove.Json.category)'" }

        # The packaging run is visible in the shared automation history.
        $packagingHistory = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/automation/history?kind=roadmap-packaging&limit=10"
        if ($packagingHistory.Json.success -ne $true) { throw '/api/automation/history?kind=roadmap-packaging did not return success=true' }
        if (@($packagingHistory.Json.data.runs | Where-Object { [string]$_.runId -eq [string]$packageRunData.run.runId }).Count -eq 0) {
            throw 'The packaging run is missing from /api/automation/history'
        }

        # Release 3.1 — the work-item trace, on the item this run just packaged
        # and dispatched. This is the release's acceptance criterion ("a single
        # runId resolves to every stage artifact through one route") checked
        # against real ledgers rather than fixtures.
        $traceByRun = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/trace/$([uri]::EscapeDataString($packagingDispatchRunId))"
        Assert-Not503 -Name '/api/trace/{dispatchRunId}' -Response $traceByRun
        if ([int]$traceByRun.StatusCode -ne 200) { throw "/api/trace/{dispatchRunId} expected 200, got $($traceByRun.StatusCode). Body=$($traceByRun.Content)" }
        if ([string]$traceByRun.ContentType -notlike 'application/json*') { throw '/api/trace/{id} did not return JSON' }
        if ($traceByRun.Json.success -ne $true) { throw '/api/trace/{dispatchRunId} returned success=false' }
        $traceData = $traceByRun.Json.data
        if (@($traceData.stages).Count -ne 7) { throw "/api/trace/{id} returned $(@($traceData.stages).Count) stages; the chain is seven" }
        if ([string]$traceData.identity.dispatchRunId -ne $packagingDispatchRunId) { throw '/api/trace/{id} did not resolve the dispatch run id' }
        $traceDispatchStage = @($traceData.stages | Where-Object { [string]$_.stage -eq 'dispatch' }) | Select-Object -First 1
        if ([string]$traceDispatchStage.status -ne 'complete') {
            throw "An approved-and-enqueued item must trace dispatch=complete; got '$($traceDispatchStage.status)'"
        }

        # The same item, asked for by the packaging-side id: an operator holding
        # any id the chain minted must land on the same trace.
        $traceByPacket = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/trace/$([uri]::EscapeDataString([string]$packagedPacket.packetId))"
        if ([int]$traceByPacket.StatusCode -ne 200) { throw "/api/trace/{packetId} expected 200, got $($traceByPacket.StatusCode)" }
        if ([string]$traceByPacket.Json.data.traceId -ne [string]$traceData.traceId) {
            throw "packetId and dispatchRunId resolved to different traces ('$($traceByPacket.Json.data.traceId)' vs '$($traceData.traceId)')"
        }

        # An unknown id must 404 as JSON. Status alone is not enough: an
        # unmatched GET falls through to the SPA shell, which answers 200 with
        # text/html — a deleted route would pass a status-only check.
        $traceUnknown = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/trace/no-such-work-item"
        Assert-Not503 -Name '/api/trace/{id} (unknown)' -Response $traceUnknown
        if ([int]$traceUnknown.StatusCode -ne 404) { throw "/api/trace/{id} for an unknown id expected 404, got $($traceUnknown.StatusCode)" }
        if ([string]$traceUnknown.ContentType -notlike 'application/json*') { throw '/api/trace/{id} 404 must be JSON, not the SPA shell' }

        # Release 3.1 — the write-back gate, on an item that has NOT merged.
        # This is the release's central claim checked over HTTP: a real,
        # ranked, approved, dispatched work item still cannot be marked
        # complete, because nothing has merged. Both routes must refuse
        # independently — apply re-runs the gate rather than trusting a
        # preview — and both must refuse with 409, never a 200 carrying
        # changed=false that a caller could read as success.
        foreach ($wbRoute in @('preview', 'apply')) {
            $wbResp = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/roadmap/write-back/$wbRoute" -Body @{ id = $packagingDispatchRunId }
            Assert-Not503 -Name "/api/roadmap/write-back/$wbRoute" -Response $wbResp
            if ([string]$wbResp.ContentType -notlike 'application/json*') { throw "/api/roadmap/write-back/$wbRoute did not return JSON" }
            if ([int]$wbResp.StatusCode -ne 409) {
                throw "/api/roadmap/write-back/$wbRoute for an unmerged item expected 409, got $($wbResp.StatusCode). Body=$($wbResp.Content)"
            }
            if ($wbResp.Json.success -ne $false) { throw "/api/roadmap/write-back/$wbRoute refusal must carry success=false" }
            # The refusal has to say which rule stopped it, or the operator is
            # left guessing which of six preconditions is missing.
            $wbCategory = [string]$wbResp.Json.category
            if ($wbCategory -notin @('write-back-refused', 'roadmap-not-found')) {
                throw "/api/roadmap/write-back/$wbRoute refused with an unexpected category '$wbCategory'. Body=$($wbResp.Content)"
            }
            if ($wbCategory -eq 'write-back-refused') {
                $wbCodes = @(@($wbResp.Json.data.refusals) | ForEach-Object { [string]$_.code })
                if ($wbCodes.Count -eq 0) { throw "/api/roadmap/write-back/$wbRoute refused without naming a refusal code" }
                foreach ($wbRefusal in @($wbResp.Json.data.refusals)) {
                    if ([string]::IsNullOrWhiteSpace([string]$wbRefusal.remedy)) { throw "Refusal '$($wbRefusal.code)' carries no remedy" }
                }
            }
            $wbRefusalCategory = $wbCategory
        }

        # The managed repo's roadmap must be untouched by a refused write-back.
        $wbFixtureRoadmap = Join-Path $portfolioFixtureRoot (Join-Path $packagingRepoName 'ROADMAP.md')
        if (Test-Path -LiteralPath $wbFixtureRoadmap) {
            $wbRoadmapAfter = Get-Content -LiteralPath $wbFixtureRoadmap -Raw -Encoding UTF8
            if ($wbRoadmapAfter -match [regex]::Escape("- [x] $([string]$packagedPacket.itemText)")) {
                throw 'A refused write-back marked the roadmap item complete anyway.'
            }
        }

        $wbUnknown = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/roadmap/write-back/preview" -Body @{ id = 'no-such-work-item' }
        Assert-Not503 -Name '/api/roadmap/write-back/preview (unknown id)' -Response $wbUnknown
        if ([int]$wbUnknown.StatusCode -ne 404) { throw "/api/roadmap/write-back/preview for an unknown id expected 404, got $($wbUnknown.StatusCode)" }
        if ([string]$wbUnknown.ContentType -notlike 'application/json*') { throw '/api/roadmap/write-back/preview 404 must be JSON, not the SPA shell' }

        $packagingOk = $true
        Write-Host ("  packaging ok: packaged '{0}' (score {1}, order {2}) not the first item, over-budget twin skipped at stage=quota, dispatch only on approval (run {3}), re-approval 409" -f `
                $packagedPacket.itemText, $packagedPacket.valueScore, $packagedPacket.roadmapOrder, $packagingDispatchRunId) -ForegroundColor DarkGray
        Write-Host ("  write-back ok: preview AND apply both refuse the unmerged item 409 ({0}), roadmap untouched, unknown id 404s as JSON" -f $wbRefusalCategory) -ForegroundColor DarkGray
        Write-Host ("  trace ok: {0}/7 stages joined for run {1}, packetId resolves to the same trace, unknown id 404s as JSON" -f `
                $traceData.completeStageCount, $packagingDispatchRunId) -ForegroundColor DarkGray
    }
    finally {
        # Leave nothing runnable behind: an approved packet enqueues real work
        # for the operator's runner, and the fixture repo is about to be deleted.
        if ($null -ne $packagingQueueBackup) {
            Set-Content -LiteralPath $packagingQueuePath -Value $packagingQueueBackup -Encoding UTF8 -NoNewline
        } elseif (Test-Path -LiteralPath $packagingQueuePath) {
            Remove-Item -LiteralPath $packagingQueuePath -Force -ErrorAction SilentlyContinue
        }
        if (-not [string]::IsNullOrWhiteSpace($packagingDispatchRunId)) {
            Remove-Item -LiteralPath (Join-Path $WorkspaceRoot ("output\roadmap-task-history\runs\{0}.summary.json" -f $packagingDispatchRunId)) -Force -ErrorAction SilentlyContinue
        }
        foreach ($curatedId in $packagingCuratedIds) {
            $null = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/operations/repos/$([uri]::EscapeDataString($curatedId))/curation" -Body @{ curationState = 'none'; reason = 'api-host smoke cleanup' }
        }
        foreach ($name in @($packagingRepoName, $packagingOverName)) {
            Remove-Item -LiteralPath (Join-Path $portfolioFixtureRoot $name) -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Write-Host '[STEP] Operator-runner presence + in-host cloud-dispatch refusal (Release 3.0)' -ForegroundColor Cyan
    $runnerRouteOk = $false
    $runnerResp = Invoke-ApiRequest -Method Get -Uri "$BaseUrl/api/roadmap/runner"
    Assert-Not503 -Name '/api/roadmap/runner' -Response $runnerResp
    if ($null -eq $runnerResp.Json -or -not $runnerResp.Json.success) {
        throw "GET /api/roadmap/runner returned success=false. HTTP $($runnerResp.StatusCode). Body=$($runnerResp.Content)"
    }
    foreach ($runnerField in @('state', 'present', 'message', 'queuedTotal', 'queuedClaude', 'queuedCopilot', 'strandedCount', 'startCommand')) {
        if (-not ($runnerResp.Json.data.PSObject.Properties.Name -contains $runnerField)) {
            throw "GET /api/roadmap/runner missing '$runnerField'. Body=$($runnerResp.Content)"
        }
    }
    # The header's Copy button hands startCommand to the operator verbatim; a
    # relative path fails from any terminal that did not open inside the repo.
    $runnerStartCmd = [string]$runnerResp.Json.data.startCommand
    if ($runnerStartCmd -notmatch '^pwsh -File "(.+)"$' -or -not [System.IO.Path]::IsPathRooted($Matches[1])) {
        throw "GET /api/roadmap/runner startCommand must be a quoted, absolute -File path; got '$runnerStartCmd'"
    }
    if ([string]$runnerResp.Json.data.state -notin @('present', 'stale', 'absent')) {
        throw "Runner state must be present/stale/absent; got '$($runnerResp.Json.data.state)'"
    }
    # Presence and `present` must agree. Two fields disagreeing about liveness is
    # exactly the "two figures, one truth" divergence this product exists to catch.
    if ([bool]$runnerResp.Json.data.present -ne ([string]$runnerResp.Json.data.state -eq 'present')) {
        throw "Runner present flag disagrees with state: present=$($runnerResp.Json.data.present) state=$($runnerResp.Json.data.state)"
    }
    # No runner in a smoke run, so nothing may be reported as about to run.
    if ([bool]$runnerResp.Json.data.present) {
        throw 'The smoke host has no operator runner; reporting one present would be the false-green this route exists to prevent.'
    }

    # The route-level refusal: asking the host to run cloud dispatch itself must
    # be a 409 that names the runner, not a 200 that fails at the last step.
    $inProcessResp = Invoke-ApiRequest -Method Post -Uri "$BaseUrl/api/roadmap/dispatch/execute" -Body @{
        repoName = 'smoke-in-process-refusal'; prompt = 'noop'; inProcess = $true
    }
    if ($inProcessResp.StatusCode -ne 409) {
        throw "In-process cloud dispatch must be refused with 409; got HTTP $($inProcessResp.StatusCode). Body=$($inProcessResp.Content)"
    }
    if ([string]$inProcessResp.Json.category -ne 'operator-runner-required') {
        throw "The 409 must carry category=operator-runner-required; got '$($inProcessResp.Json.category)'"
    }
    if ([string]$inProcessResp.Json.error -notmatch 'Invoke-RoadmapTaskRunner') {
        throw "The refusal must name the runner that can do it. Body=$($inProcessResp.Content)"
    }
    $runnerRouteOk = $true
    Write-Host ("  runner presence ok: state={0} present={1} queued={2} stranded={3}; in-process cloud dispatch refused 409 ({4})" -f `
            $runnerResp.Json.data.state, $runnerResp.Json.data.present, $runnerResp.Json.data.queuedTotal, `
            $runnerResp.Json.data.strandedCount, $inProcessResp.Json.category) -ForegroundColor DarkGray

    Write-Host '[STEP] Route census — critical API routes must return JSON (not the SPA fallback)' -ForegroundColor Cyan
    $censusRoutes = @(
        '/health/live', '/health/ready', '/health/dependencies', '/metrics',
        '/api/persistence/status', '/api/auth/status', '/api/auth/github/status',
        '/api/automation/history', '/api/automation/status', '/api/automation/packages',
        '/api/roadmap/runner',
        '/api/settings', '/api/roadmap/index',
        '/api/maintenance/database',
        '/api/cache/diagnostics', '/api/scan/schedule', '/api/execution/metrics',
        '/api/execution/queue', '/api/notifications/webhooks', '/api/roadmap/drift',
        '/api/analytics/cost', '/api/roadmap/maturity-history', '/api/agent-runs',
        '/api/report/artifacts', '/api/status/cache', '/api/log/tail',
        # Release 3.6 M1 — every repository's conclusion; a deleted route would
        # answer 200 text/html here and the whole product outcome would vanish.
        '/api/portfolio/conclusions',
        # Lane 0.16 — the Dependencies tab's technology inventory. With no index
        # in the fixture workspace it answers 409 JSON, which still proves the
        # route exists; the SPA fallback would answer 200 text/html.
        '/api/portfolio/tech-inventory',
        # Release 3.1. The census asserts content-type, not status, so an
        # id that matches nothing still proves the route exists: its 404 is
        # JSON, whereas a deleted route would answer 200 text/html.
        '/api/trace/no-such-work-item'
    )
    $censusMissing = [System.Collections.Generic.List[string]]::new()
    foreach ($route in $censusRoutes) {
        $censusResponse = Invoke-ApiRequest -Method Get -Uri "$BaseUrl$route"
        $censusCt = [string]$censusResponse.ContentType
        if ($censusCt -notlike 'application/json*') {
            $observed = if ([string]::IsNullOrWhiteSpace($censusCt)) { "HTTP $($censusResponse.StatusCode), no content-type" } else { "HTTP $($censusResponse.StatusCode), $censusCt" }
            $censusMissing.Add(("{0} ({1})" -f $route, $observed))
            Write-Host ("  [MISSING] GET {0} -> {1} (not JSON — deleted route now shadowed by the SPA fallback)" -f $route, $observed) -ForegroundColor Red
        }
    }
    if ($censusMissing.Count -gt 0) {
        throw ("Route census failed — {0} critical API route(s) no longer return JSON (silently deleted?): {1}" -f $censusMissing.Count, ($censusMissing.ToArray() -join '; '))
    }
    Write-Host ("  {0}/{1} critical API routes return JSON (no silent deletions)" -f $censusRoutes.Count, $censusRoutes.Count) -ForegroundColor DarkGray

    Write-Host '[PASS] API host smoke completed' -ForegroundColor Green
    $statusCacheSuccess = if ($null -ne $statusCache.Json -and ($statusCache.Json.PSObject.Properties.Name -contains 'success')) { $statusCache.Json.success } else { $null }
    $settingsGetSuccess = if ($null -ne $settingsGet.Json -and ($settingsGet.Json.PSObject.Properties.Name -contains 'success')) { $settingsGet.Json.success } else { $null }
    $settingsPostSuccess = if ($null -ne $settingsPost.Json -and ($settingsPost.Json.PSObject.Properties.Name -contains 'success')) { $settingsPost.Json.success } else { $null }
    # Each summary entry is evaluated independently so one missing property
    # degrades to a labelled "(unavailable: ...)" value instead of discarding
    # the whole projection (StrictMode throws on absent properties).
    $summarySpec = [ordered]@{
        liveStatus = { $live.status }
        readyStatus = { $ready.status }
        dependenciesStatus = { $deps.status }
        dependenciesHttpCode = { [int]$depsResponse.StatusCode }
        statusSuccess = { $status.success }
        statusCacheSuccess = { $statusCacheSuccess }
        settingsGetSuccess = { $settingsGetSuccess }
        settingsPostSuccess = { $settingsPostSuccess }
        initStatusCode = { $initResponse.StatusCode }
        updateStatusCode = { $updateResponse.StatusCode }
        syncStatusCode = { $syncResponse.StatusCode }
        archiveStatusCode = { $archiveResponse.StatusCode }
        reconcileSuccess = { $reconcile.success }
        docreviewSuccess = { $doc.success }
        artifactsCount = { @($artifacts.artifacts).Count }
        exportSuccess = { $export.success }
        reportOpenStatusCode = { $reportOpenResponse.StatusCode }
        metricsGeneratedAt = { $metrics.generatedAt }
        roadmapIndexCount = { $roadmapIndex.data.count }
        roadmapScanCount = { $roadmapScan.data.count }
        roadmapStateFieldsOk = { $roadmapStateFieldsOk }
        roadmapContentOk = { $roadmapContentOk }
        readmeContentOk = { $readmeContentOk }
        roadmapFullContentOk = { $fullRoadmapReturnedAll }
        roadmapCacheStatusCode = { $roadmapCache.StatusCode }
        githubStatusCode = { $githubStatusResponse.StatusCode }
        roadmapPreviewStatusCode = { $roadmapPreviewResponse.StatusCode }
        roadmapStartStatusCode = { $roadmapStartResponse.StatusCode }
        roadmapHistoryStatusCode = { $roadmapHistoryResponse.StatusCode }
        logTailEntryCount = { $logTail.count }
        logTailSource = { $logTail.source }
        maturityHistorySource = { $maturityHistory.source }
        maturityHistoryCount = { @($maturityHistory.data).Count }
        docsAuditGetSuccess = { $docsAuditData.success }
        docsAuditScanSuccess = { $docsAuditScanData.success }
        docsAuditRepoCount = { $docsAuditData.data.count }
        copilotPreviewStatusCode = { $copilotPreviewResponse.StatusCode }
        copilotPreviewPacketOk = { $copilotPreviewPacketOk }
        opsPromptRefineStatusCode = { $opsPromptRefineResponse.StatusCode }
        opsPromptRefineOk = { $opsPromptRefineOk }
        copilotHistorySuccess = { $copilotHistoryJson.success }
        copilotHistoryItemsOk = { $copilotHistoryItemsOk }
        roadmapAuditGetSuccess = { $roadmapAuditData.success }
        roadmapAuditScanSuccess = { $roadmapAuditScanData.success }
        roadmapAuditRepoCount = { $roadmapAuditData.data.count }
        roadmapAuditFieldsOk = { $roadmapAuditFieldsOk }
        repairPreviewFieldsOk = { $repairPreviewFieldsOk }
        repairHistoryItemsOk = { $repairHistoryItemsOk }
        execQueueFieldsOk = { $execQueueFieldsOk }
        lintScanSuccess = { $lintScanJson.success }
        stdHistorySuccess = { $stdHistoryJson.success }
        driftFieldsOk = { $driftFieldsOk }
        webhooksGetSuccess = { $webhooksJson.success }
        execMetricsFieldsOk = { $execMetricsFieldsOk }
        scanScheduleFieldsOk = { $scanScheduleFieldsOk }
        depGraphFieldsOk = { $depGraphFieldsOk }
        depGraphTotalEdges = { $depGraphData.totalEdges }
        portfolioFieldsOk = { $portfolioFieldsOk }
        portfolioSummaryFieldsOk = { $portfolioSummaryFieldsOk }
        portfolioEntryFieldsOk = { $portfolioEntryFieldsOk }
        portfolioRepoCount = { [int]$portfolioData.count }
        portfolioDiffFieldsOk = { $portfolioDiffFieldsOk }
        portfolioDiffModeObserved = { $portfolioDiffModeObserved }
        staticIndexOk = { $staticIndexOk }
        staticAssetsOk = { $staticAssetsOk }
        staticSkipped = { $staticSkipped }
        routeCensusChecked = { $censusRoutes.Count }
        routeCensusMissing = { $censusMissing.Count }
        scopedRoadmapScanOk = { $scopedScanOk }
        improvementPreviewOk = { $improvementPreviewOk }
        dbMaintenanceOk = { $dbMaintenanceOk }
        automationStatusOk = { $automationStatusOk }
        packagingOk = { $packagingOk }
        runnerRouteOk = { $runnerRouteOk }
        githubAuthProbeOk = { $githubAuthProbeOk }
        githubTokenSource = { $ghAuthData.tokenSource }
        workspaceValidationOk = { $script:WorkspaceValidationOk }
        missingRootsReportedOk = { $script:MissingRootsReportedOk }
    }
    $summary = [ordered]@{}
    foreach ($entryName in $summarySpec.Keys) {
        try { $summary[$entryName] = & $summarySpec[$entryName] }
        catch { $summary[$entryName] = "(unavailable: $($_.Exception.Message))" }
    }
    [pscustomobject]$summary | Format-List
}
finally {
    # PROVE the tracked config was never written, rather than putting it back.
    # This is the assertion that replaced the old byte-exact restore: with the
    # host resolving settings through REPO_MGMT_SETTINGS_PATH there is no write
    # path to the tracked file, so any difference here is a real regression --
    # a call site that went round the resolver — and it must fail the gate
    # loudly instead of being silently repaired.
    if ($null -ne $script:TrackedSettingsAtStart) {
        try {
            $current = if (Test-Path -LiteralPath $script:TrackedSettingsPath) {
                Get-Content -LiteralPath $script:TrackedSettingsPath -Raw -Encoding UTF8
            } else { $null }
            if ($current -ne $script:TrackedSettingsAtStart) {
                # Put it back first -- the operator's file matters more than the
                # tidiness of the failure -- then fail so the leak is not missed.
                Set-Content -LiteralPath $script:TrackedSettingsPath -Value $script:TrackedSettingsAtStart -Encoding UTF8 -NoNewline
                Write-Host '  FAIL: tracked settings.json was written during this run and has been restored.' -ForegroundColor Red
                Write-Host '        A call site is resolving the settings path inline instead of through Get-PortalSettingsPath.' -ForegroundColor Red
                throw 'api-host smoke mutated the git-tracked backend/config/settings.json'
            }
            Write-Host '  verified: tracked settings.json byte-identical across the run' -ForegroundColor DarkGray
        }
        catch [System.Management.Automation.RuntimeException] { throw }
        catch {
            Write-Host ("  WARNING: could not verify settings.json — check it before committing. {0}" -f $_.Exception.Message) -ForegroundColor Yellow
        }
    }

    # Teardown order matters. Stop-Job against a job whose pipeline is wedged
    # inside a native call can block forever — that is exactly how the harness
    # used to hang after its last visible step and leave an orphaned host
    # holding port 7071. So: (1) ask the host to exit via its shutdown-signal
    # file and give it a bounded window, (2) force-kill anything still
    # listening on the port, and only then (3) run Stop-Job/Remove-Job, which
    # are trivial once the host process is gone.
    try {
        Set-Content -LiteralPath $shutdownSignalPath -Value 'shutdown' -Encoding ascii -Force
        $null = Wait-Job -Job $job -Timeout 5
    }
    catch {
        # Best-effort graceful shutdown only.
    }

    try {
        $lingering = @(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty OwningProcess -Unique)
        foreach ($lingeringPid in $lingering) {
            if ($lingeringPid -and $lingeringPid -ne 0 -and $lingeringPid -ne $PID) {
                Stop-Process -Id $lingeringPid -Force -ErrorAction SilentlyContinue
            }
        }
    }
    catch {
        # Best-effort cleanup only; never let teardown mask the smoke result.
    }

    Stop-Job -Job $job -ErrorAction SilentlyContinue | Out-Null
    Remove-Job -Job $job -Force -ErrorAction SilentlyContinue | Out-Null
    Remove-Item -LiteralPath $shutdownSignalPath -Force -ErrorAction SilentlyContinue
}
