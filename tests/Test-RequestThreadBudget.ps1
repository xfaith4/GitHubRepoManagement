#Requires -Version 7.0
<#
.SYNOPSIS
    A route answers within its request-thread budget while the background scan
    it asked for runs (Lane 0.21).

.DESCRIPTION
    The operator's timed reload, 2026-09-15: the shell painted in 0.7 s and the
    host barely answered for 3 m 33 s. The host serves one connection at a
    time, and each GET /api/portfolio/assessment?scanMode=differential held it
    for 60-72 s running the GitHub pass, the changed-root scans, the assessment
    and the index write inline. /health/live peaked at 48 s behind it.

    This boots a real host on a free port against two fixture repositories,
    with every root it writes isolated (settings, index, scan caches, queue,
    runner state, installation state), and measures from the client side:

      1. cold  - the route with scanMode=differential, nothing on disk yet;
      2. while the worker scans - /health/live and the plain route, sampled
         until the scan settles, with at least one sample taken while the scan
         is running (a scan too fast to overlap proves nothing, and fails);
      3. the worker's result reaches the route (both fixtures are served);
      4. warm - refresh=true, then scanMode=differential while that runs
         (single flight: it must not start a second scan), sampled again.

    Every request must answer within -MaxMs. GitHub stays offline (no owner
    configured) so the measurement is the host's, not the network's.

.PARAMETER Route
    The route under budget. Only /api/portfolio/assessment is wired today.

.PARAMETER MaxMs
    The per-request budget, client-measured.

.EXAMPLE
    pwsh ./tests/Test-RequestThreadBudget.ps1 -Route /api/portfolio/assessment -MaxMs 2000 -FailOnError
#>
[CmdletBinding()]
param(
    [Parameter()][ValidateSet('/api/portfolio/assessment')][string]$Route = '/api/portfolio/assessment',
    [Parameter()][ValidateRange(100, 60000)][int]$MaxMs = 2000,
    [Parameter()][string]$WorkspaceRoot = (Split-Path -Parent $PSScriptRoot),
    [Parameter()][int]$Port = 0,
    [Parameter()][int]$ScanTimeoutSeconds = 300,
    [Parameter()][switch]$FailOnError
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$WorkspaceRoot = (Resolve-Path -LiteralPath $WorkspaceRoot).Path
$hostScript = Join-Path $WorkspaceRoot 'backend\api-host\Start-RepoManagementApiHost.ps1'
if (-not (Test-Path -LiteralPath $hostScript)) { throw "API host not found at $hostScript" }

if ($Port -le 0) {
    $probe = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    $probe.Start()
    $Port = ([System.Net.IPEndPoint]$probe.LocalEndpoint).Port
    $probe.Stop()
}
# 127.0.0.1, never localhost: on this machine localhost resolves to ::1 first
# and pays a firewall penalty that would be measured as host latency.
$baseUrl = "http://127.0.0.1:$Port"

$runRoot = Join-Path $WorkspaceRoot ('output\smoke\request-thread-budget\' + [guid]::NewGuid().ToString('n').Substring(0, 8))
$fixtureRoot = Join-Path $runRoot 'repos'
$logPath = Join-Path $runRoot 'host.log'
$signalPath = Join-Path $runRoot 'host.shutdown.signal'
$null = New-Item -ItemType Directory -Path $fixtureRoot -Force

foreach ($name in @('budget-fixture-alpha', 'budget-fixture-beta')) {
    $repo = Join-Path $fixtureRoot $name
    $null = New-Item -ItemType Directory -Path $repo -Force
    Set-Content -LiteralPath (Join-Path $repo 'README.md') -Value "# $name`n`nFixture for the request-thread budget test." -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $repo 'ROADMAP.md') -Value "# $name roadmap`n`n## Release 1`n`n- [x] Done item`n- [ ] Pending item`n" -Encoding UTF8
    $null = & git -C $repo init -q -b main 2>&1
    $null = & git -C $repo -c user.name=fixture -c user.email=fixture@example.invalid -c commit.gpgsign=false add -A 2>&1
    $null = & git -C $repo -c user.name=fixture -c user.email=fixture@example.invalid -c commit.gpgsign=false commit -q -m 'fixture' 2>&1
    if ($LASTEXITCODE -ne 0) { throw "git could not commit the fixture repository at $repo" }
}

# The tracked settings, with the scan scope pointed at the fixtures and GitHub
# offline. Written to the run root; the tracked file is never touched.
$trackedSettingsPath = Join-Path $WorkspaceRoot 'backend\config\settings.json'
$settings = if (Test-Path -LiteralPath $trackedSettingsPath) { Get-Content -LiteralPath $trackedSettingsPath -Raw | ConvertFrom-Json -AsHashtable } else { @{ schemaVersion = 'v1' } }
if (-not $settings.ContainsKey('inventory') -or $settings.inventory -isnot [System.Collections.IDictionary]) { $settings.inventory = @{} }
$settings.inventory.localRoots = @($fixtureRoot)
$settings.inventory.maxDepth = 2
if (-not $settings.ContainsKey('reconcile') -or $settings.reconcile -isnot [System.Collections.IDictionary]) { $settings.reconcile = @{} }
$settings.reconcile.gitHubOwner = ''
$settingsPath = Join-Path $runRoot 'settings.json'
Set-Content -LiteralPath $settingsPath -Value ($settings | ConvertTo-Json -Depth 20) -Encoding UTF8

$apiKey = [Environment]::GetEnvironmentVariable('REPO_MGMT_API_KEY')
$headers = @{}
if (-not [string]::IsNullOrWhiteSpace($apiKey)) { $headers['X-Api-Key'] = $apiKey }

$samples = [System.Collections.Generic.List[object]]::new()
$failures = [System.Collections.Generic.List[string]]::new()

function Invoke-TimedRequest {
    param(
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)][string]$PathAndQuery,
        [Parameter()][string]$Phase = ''
    )
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $response = $null
    $errorText = $null
    try {
        $response = Invoke-WebRequest -Uri ($baseUrl + $PathAndQuery) -Method Get -Headers $headers -SkipHttpErrorCheck -TimeoutSec 120
    }
    catch { $errorText = $_.Exception.Message }
    $sw.Stop()
    $json = $null
    if ($null -ne $response -and -not [string]::IsNullOrWhiteSpace([string]$response.Content)) {
        try { $json = $response.Content | ConvertFrom-Json } catch { $json = $null }
    }
    $sample = [pscustomobject]@{
        Label  = $Label
        Phase  = $Phase
        Ms     = [math]::Round($sw.Elapsed.TotalMilliseconds, 1)
        Status = $(if ($null -ne $response) { [int]$response.StatusCode } else { 0 })
        Error  = $errorText
        Json   = $json
    }
    $samples.Add($sample)
    if ($sample.Status -ne 200) {
        $failures.Add(("{0} ({1}) answered HTTP {2}{3}" -f $Label, $PathAndQuery, $sample.Status, $(if ($errorText) { ": $errorText" } else { '' })))
    }
    elseif ($sample.Ms -gt $MaxMs) {
        $failures.Add(("{0} ({1}) took {2} ms, over the {3} ms request-thread budget{4}" -f $Label, $PathAndQuery, $sample.Ms, $MaxMs, $(if ($Phase) { " while $Phase" } else { '' })))
    }
    return $sample
}

function Get-ScanState {
    $response = Invoke-WebRequest -Uri "$baseUrl/api/portfolio/scan/status" -Method Get -Headers $headers -SkipHttpErrorCheck -TimeoutSec 60
    return ($response.Content | ConvertFrom-Json).data
}

function Measure-WhileScanning {
    # Samples the two routes an operator's page hits during a scan until the
    # worker settles. Returns how many samples overlapped a running scan.
    param(
        [Parameter(Mandatory = $true)][string]$Phase,
        [Parameter(Mandatory = $true)][int]$TimeoutSeconds
    )
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $overlapping = 0
    while ((Get-Date) -lt $deadline) {
        $state = Get-ScanState
        if ([string]$state.state -in @('failed', 'aborted')) {
            $failures.Add(("the background scan ended '{0}' during {1}: {2}" -f $state.state, $Phase, $state.error))
            return $overlapping
        }
        $live = Invoke-TimedRequest -Label '/health/live' -PathAndQuery '/health/live' -Phase $Phase
        $read = Invoke-TimedRequest -Label 'plain read' -PathAndQuery $Route -Phase $Phase
        $running = ([string]$state.state -eq 'running')
        if ($running) { $overlapping++ }
        $refreshing = $false
        if ($null -ne $read.Json -and $null -ne $read.Json.data) { $refreshing = [bool]$read.Json.data.refreshing }
        if (-not $running -and -not $refreshing) { return $overlapping }
        $null = $live
        Start-Sleep -Milliseconds 400
    }
    $failures.Add(("the background scan did not settle within {0}s during {1}; see {2}" -f $TimeoutSeconds, $Phase, $logPath))
    return $overlapping
}

# $using: rather than param(): each parameter a Start-Job scriptblock reads is
# one more PSUseUsingScopeModifierInNewRunspaces finding, and that ratchet only
# moves down.
$job = Start-Job -ScriptBlock {
    $jobRunRoot = $using:runRoot
    # Every root the host or its worker writes, isolated to this run. Set on
    # the job, so a crashed test cannot leave the operator's shell redirected.
    $env:REPO_MGMT_SETTINGS_PATH = (Join-Path $jobRunRoot 'settings.json')
    $env:REPO_MGMT_INDEX_ROOT = (Join-Path $jobRunRoot 'index')
    $env:REPO_MGMT_CACHE_ROOT = (Join-Path $jobRunRoot 'cache')
    $env:REPO_MGMT_QUEUE_PATH = (Join-Path $jobRunRoot 'queue.jsonl')
    $env:REPO_MGMT_RUNNER_CONTROL_ROOT = (Join-Path $jobRunRoot 'runner-control')
    $env:REPO_MGMT_INSTALLATION_STATE_PATH = (Join-Path $jobRunRoot 'installation.local.json')
    # Plain HTTP: an inherited machine-scope certificate would wrap the
    # listener in TLS and every request here would fail the handshake.
    $env:REPO_MGMT_TLS_PFX = ''
    $env:REPO_MGMT_TLS_PFX_PASSWORD = ''
    & $using:hostScript -WorkspaceRoot $using:WorkspaceRoot -BindAddress '127.0.0.1' -Port $using:Port -LogPath $using:logPath -ShutdownSignalPath $using:signalPath -QueuePath (Join-Path $jobRunRoot 'queue.jsonl')
}

try {
    $readyDeadline = (Get-Date).AddSeconds(90)
    $ready = $false
    while ((Get-Date) -lt $readyDeadline) {
        if ($job.State -in @('Failed', 'Stopped', 'Completed')) {
            throw ("The host exited before it answered: {0}" -f ((Receive-Job -Job $job -Keep -ErrorAction SilentlyContinue | Out-String).Trim()))
        }
        try {
            $r = Invoke-WebRequest -Uri "$baseUrl/health/live" -Method Get -SkipHttpErrorCheck -TimeoutSec 5
            if ($r.StatusCode -eq 200) { $ready = $true; break }
        }
        catch { $null = $_ }
        Start-Sleep -Milliseconds 500
    }
    if (-not $ready) { throw "The host did not answer /health/live within 90s on $baseUrl; see $logPath" }
    Write-Host ("Request-thread budget: {0} within {1} ms on {2} (host log {3})" -f $Route, $MaxMs, $baseUrl, $logPath) -ForegroundColor Cyan

    # 1. Cold: nothing on disk. The route must answer at once and start a scan.
    $cold = Invoke-TimedRequest -Label 'cold differential load' -PathAndQuery "$($Route)?scanMode=differential&includeCuration=true" -Phase 'nothing was on disk'
    if ($null -ne $cold.Json) {
        if ([string]$cold.Json.data.cacheSource -ne 'awaiting-first-scan') { $failures.Add(("a cold host served cacheSource '{0}'; expected awaiting-first-scan" -f $cold.Json.data.cacheSource)) }
        if (-not [bool]$cold.Json.data.scanRequested.started) { $failures.Add('the cold differential load did not start a background scan') }
        if ([bool]$cold.Json.data.refreshing -ne $true) { $failures.Add('the cold differential load did not report refreshing=true') }
    }

    # 2. While the worker scans.
    $overlapCold = Measure-WhileScanning -Phase 'the first scan ran' -TimeoutSeconds $ScanTimeoutSeconds

    # 3. The worker's result reaches the route.
    $served = Invoke-TimedRequest -Label 'read after the first scan' -PathAndQuery $Route -Phase 'the first scan had settled'
    $servedNames = @()
    if ($null -ne $served.Json -and $null -ne $served.Json.data) {
        # Shape before names: member enumeration reads repoName straight through
        # a nested array, so [[a, b]] would pass a names-only check. It did, once.
        $servedEntries = @($served.Json.data.entries)
        $nestedEntries = @($servedEntries | Where-Object { $_ -is [System.Array] -or $null -eq $_.PSObject.Properties['repoName'] })
        if ($nestedEntries.Count -gt 0 -or $servedEntries.Count -ne 2) {
            $failures.Add(("the served entries are not two repository objects: {0} element(s), {1} of them not an object with repoName" -f $servedEntries.Count, $nestedEntries.Count))
        }
        $servedNames = @($servedEntries | ForEach-Object { [string]$_.repoName })
        if ([string]$served.Json.data.cacheSource -notin @('memory', 'disk')) { $failures.Add(("after the first scan the route served cacheSource '{0}'; expected the worker's result (memory or disk)" -f $served.Json.data.cacheSource)) }
    }
    foreach ($expected in @('budget-fixture-alpha', 'budget-fixture-beta')) {
        if ($servedNames -notcontains $expected) { $failures.Add(("the worker's result does not include fixture '{0}'; served: {1}" -f $expected, ($servedNames -join ', '))) }
    }

    # 4. Warm: a forced refresh, then a differential load while it runs.
    $forced = Invoke-TimedRequest -Label 'forced refresh' -PathAndQuery "$($Route)?refresh=true&includeCuration=true" -Phase 'a result was on disk'
    if ($null -ne $forced.Json -and -not ([bool]$forced.Json.data.scanRequested.started -or [bool]$forced.Json.data.scanRequested.queued)) {
        $failures.Add('refresh=true neither started nor queued a background scan')
    }
    $second = Invoke-TimedRequest -Label 'differential load during a scan' -PathAndQuery "$($Route)?scanMode=differential&includeCuration=true" -Phase 'a forced refresh ran'
    if ($null -ne $second.Json -and (Get-ScanState).state -eq 'running' -and [bool]$second.Json.data.scanRequested.started) {
        $failures.Add('a differential load started a second scan while one was running; the worker is single-flight')
    }
    $overlapWarm = Measure-WhileScanning -Phase 'the forced refresh ran' -TimeoutSeconds $ScanTimeoutSeconds

    if (($overlapCold + $overlapWarm) -eq 0) {
        $failures.Add('no sample overlapped a running scan, so nothing was measured under load; the budget is unproven')
    }

    Write-Host ''
    $samples | Group-Object Label | ForEach-Object {
        $ms = @($_.Group | ForEach-Object { $_.Ms })
        [pscustomobject]@{
            Request = $_.Name
            Count   = $ms.Count
            MaxMs   = ($ms | Measure-Object -Maximum).Maximum
            MedianMs = ($ms | Sort-Object)[[int][math]::Floor($ms.Count / 2)]
        }
    } | Format-Table -AutoSize | Out-String | Write-Host
    Write-Host ("Samples taken while a scan was running: {0} (first scan), {1} (forced refresh)" -f $overlapCold, $overlapWarm)
}
catch {
    $failures.Add(("the budget test could not run: {0}" -f $_.Exception.Message))
}
finally {
    # Graceful signal, then anything still holding the port, then the job;
    # Stop-Job against a wedged native call can block forever.
    try {
        Set-Content -LiteralPath $signalPath -Value 'shutdown' -Encoding ascii -Force
        $null = Wait-Job -Job $job -Timeout 5
    }
    catch { $null = $_ }
    try {
        foreach ($holder in @(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue | Select-Object -ExpandProperty OwningProcess -Unique)) {
            if ($holder -and $holder -ne 0 -and $holder -ne $PID) { Stop-Process -Id $holder -Force -ErrorAction SilentlyContinue }
        }
    }
    catch { $null = $_ }
    # A worker this run started must not outlive it.
    $lockPath = Join-Path $runRoot 'cache\status-refresh.lock'
    if (Test-Path -LiteralPath $lockPath) {
        try {
            $workerPid = [int]((Get-Content -LiteralPath $lockPath -Raw | ConvertFrom-Json).processId)
            if ($workerPid -gt 0) { Stop-Process -Id $workerPid -Force -ErrorAction SilentlyContinue }
        }
        catch { $null = $_ }
    }
    Stop-Job -Job $job -ErrorAction SilentlyContinue | Out-Null
    Remove-Job -Job $job -Force -ErrorAction SilentlyContinue | Out-Null
}

if ($failures.Count -gt 0) {
    Write-Host ("Request-thread budget: FAIL - {0} problem(s)." -f $failures.Count) -ForegroundColor Red
    foreach ($failure in $failures) { Write-Host ("  - {0}" -f $failure) -ForegroundColor Red }
    if (Test-Path -LiteralPath $logPath) {
        Write-Host '  host log, last scan lines:' -ForegroundColor Yellow
        Get-Content -LiteralPath $logPath | Where-Object { $_ -match 'status\.refresh|portfolio\.assessment|ERROR|WARN' } | Select-Object -Last 20 | ForEach-Object { Write-Host ("    {0}" -f $_) }
    }
    if ($FailOnError) { exit 1 }
    exit 0
}
Write-Host ("Request-thread budget: PASS - every request to {0} and /health/live answered within {1} ms, including {2} sample(s) taken while the worker scanned." -f $Route, $MaxMs, ($overlapCold + $overlapWarm)) -ForegroundColor Green
Remove-Item -LiteralPath $runRoot -Recurse -Force -ErrorAction SilentlyContinue
exit 0
