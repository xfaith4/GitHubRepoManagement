<#
.SYNOPSIS
    The daily evidence driver — one command that proves the gate and captures
    decision-grade evidence for the single-operator execution console.

.DESCRIPTION
    Runs the full test gate on a DEDICATED port (never 7071, so it cannot kill
    the operator's working portal), then boots its own host, runs one real
    portfolio scan against the live workspace (which also accrues the Release
    2.3 trend history that is time-gated), and captures the live signals the
    host already emits: the `scan-summary` (reused/reindexed/failed) and
    `scan-budget` TRACE lines, persistence status, and health probes.

    Everything is written to a dated snapshot under evidence/baseline/daily/
    with the git SHA, every gate's exit code, and the scan metrics — turning
    "smoke-tested today at SHA abc123, reused=68/68" into a fact you can cite
    rather than a memory. It also parses ROADMAP.md implementation states and
    writes the "verify next" queue (surfaces still at `smoke-tested`), so the
    daily beat of promoting one surface to `operator-verified` has a backlog.

    Why this exists: the CHANGELOG records three silent regressions that smoke
    passed VACUOUSLY. The gate proves `smoke-tested`; it cannot cross to
    `operator-verified`. This driver captures the durable evidence that makes
    that promotion honest, and pairs with Add-OperatorVerification.ps1 (the
    append-only verification log) and the api-host route-census assertion.

.PARAMETER WorkspaceRoot
    Repo root. Defaults to the parent of this script's directory.

.PARAMETER Port
    Port for the gate's API-host smoke and this driver's own scan host.
    Defaults to 7099 — deliberately NOT 7071 — so it never terminates a running
    portal or rewrites settings out from under a live session.

.PARAMETER SkipGate
    Skip the npm test / typecheck / vitest gate; capture live evidence only.

.PARAMETER SkipScan
    Skip the live host scan; run the gate only.

.PARAMETER SkipApiHost
    Pass -SkipApiHost through to the test suite for a quick hermetic gate
    (omits the ~4-minute live-workspace API-host smoke).

.PARAMETER RequestTimeoutSec
    Per-request timeout for the live scan calls. Cold assessment scans on a
    large workspace can take well over 30s, so the default is generous.

.EXAMPLE
    pwsh -File scripts/Invoke-DailyEvidence.ps1
    Full daily run: gate + live scan + evidence snapshot + verify queue.

.EXAMPLE
    pwsh -File scripts/Invoke-DailyEvidence.ps1 -SkipApiHost
    Fast gate (typecheck + vitest + module/adapter smoke) + live scan.
#>
[CmdletBinding()]
param(
    [string]$WorkspaceRoot,
    [int]$Port = 7099,
    [switch]$SkipGate,
    [switch]$SkipScan,
    [switch]$SkipApiHost,
    [int]$RequestTimeoutSec = 180
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Workspace + snapshot layout ──────────────────────────────────────────────
if ([string]::IsNullOrWhiteSpace($WorkspaceRoot)) {
    $WorkspaceRoot = Split-Path -Parent $PSScriptRoot
}
$WorkspaceRoot = (Resolve-Path -LiteralPath $WorkspaceRoot).Path

$stamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
$evidenceDir = Join-Path $WorkspaceRoot ("evidence\baseline\daily\{0}" -f $stamp)
$null = New-Item -ItemType Directory -Path $evidenceDir -Force
$gateLog = Join-Path $evidenceDir 'gate.log'
$hostLog = Join-Path $evidenceDir 'host.log'
$manifestPath = Join-Path $evidenceDir 'manifest.json'
$summaryPath = Join-Path $evidenceDir 'summary.md'
$queuePath = Join-Path $evidenceDir 'verify-queue.md'
$stateIndexPath = Join-Path $evidenceDir 'roadmap-state-index.json'

$settingsPath = Join-Path $WorkspaceRoot 'backend\config\settings.json'
$settingsBackup = $null
if (Test-Path -LiteralPath $settingsPath) {
    # ReadAllText/WriteAllText round-trips byte-exact (no BOM, no appended
    # newline) so restoring the file NEVER introduces a diff of its own. The
    # earlier Set-Content approach appended a newline each run, and because each
    # run re-read the grown file as its backup, trailing blank lines accumulated.
    $settingsBackup = [System.IO.File]::ReadAllText($settingsPath)
}

$pwshExe = Join-Path $PSHOME 'pwsh.exe'
if (-not (Test-Path -LiteralPath $pwshExe)) { $pwshExe = 'pwsh' }

$notes = [System.Collections.Generic.List[string]]::new()

function Write-Section {
    param([string]$Text)
    Write-Host ''
    Write-Host "===== $Text =====" -ForegroundColor Cyan
}

function Restore-Settings {
    # The API-host smoke (and first-run key generation on host boot) can rewrite
    # settings.json; a mid-run crash leaves it dirty. Restore byte-exact, and
    # only when the content actually differs, so the driver leaves settings.json
    # exactly as it found it — introducing no diff of its own.
    if ($null -eq $settingsBackup) { return }
    try {
        $current = if (Test-Path -LiteralPath $settingsPath) { [System.IO.File]::ReadAllText($settingsPath) } else { $null }
        if ($current -ne $settingsBackup) {
            [System.IO.File]::WriteAllText($settingsPath, $settingsBackup)
        }
    }
    catch { }
}

function Clear-ListenerPort {
    param([int]$PortNumber)
    try {
        $pids = Get-NetTCPConnection -LocalPort $PortNumber -State Listen -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty OwningProcess -Unique
        foreach ($procId in @($pids)) {
            if ($procId -and $procId -ne 0 -and $procId -ne $PID) {
                try { Stop-Process -Id $procId -Force -ErrorAction Stop } catch { }
            }
        }
        $deadline = (Get-Date).AddSeconds(10)
        while ((Get-Date) -lt $deadline) {
            if (-not (Get-NetTCPConnection -LocalPort $PortNumber -State Listen -ErrorAction SilentlyContinue)) { break }
            Start-Sleep -Milliseconds 300
        }
    }
    catch { }
}

function Invoke-Req {
    param([string]$Method, [string]$Uri, [string]$Body)
    try {
        # Not $args — that is an automatic variable.
        $reqArgs = @{ Uri = $Uri; Method = $Method; SkipHttpErrorCheck = $true; TimeoutSec = $RequestTimeoutSec }
        if ($PSBoundParameters.ContainsKey('Body')) {
            $reqArgs.Body = $Body
            $reqArgs.ContentType = 'application/json'
        }
        $response = Invoke-WebRequest @reqArgs
        $json = $null
        if (-not [string]::IsNullOrWhiteSpace($response.Content)) {
            $looksJson = $response.Content.TrimStart() -match '^[\{\[]'
            if ($looksJson) { try { $json = $response.Content | ConvertFrom-Json } catch { $json = $null } }
        }
        return [pscustomobject]@{ StatusCode = [int]$response.StatusCode; Json = $json; Ok = $true }
    }
    catch {
        return [pscustomobject]@{ StatusCode = 0; Json = $null; Ok = $false; Error = $_.Exception.Message }
    }
}

# ── Git context ──────────────────────────────────────────────────────────────
function Get-GitContext {
    $git = [ordered]@{ sha = $null; shortSha = $null; branch = $null; dirtyFiles = $null; dirty = $null }
    try {
        $git.sha = (& git -C $WorkspaceRoot rev-parse HEAD 2>$null).Trim()
        $git.shortSha = (& git -C $WorkspaceRoot rev-parse --short HEAD 2>$null).Trim()
        $git.branch = (& git -C $WorkspaceRoot rev-parse --abbrev-ref HEAD 2>$null).Trim()
        $porcelain = @(& git -C $WorkspaceRoot status --porcelain 2>$null)
        $git.dirtyFiles = $porcelain.Count
        $git.dirty = ($porcelain.Count -gt 0)
    }
    catch { }
    return [pscustomobject]$git
}

# ── ROADMAP implementation-state parsing (the verify-next queue) ──────────────
# The *(state: ...)* marker usually sits on a WRAPPED continuation line of a
# multi-line `- [ ]` item, not on the checkbox line itself, so we accumulate an
# item's text across continuation lines and attribute it to its section heading.
# Fenced code blocks are skipped so the vocabulary EXAMPLE in section 3 is not
# mistaken for a real milestone. This id derivation MUST stay identical to
# Add-OperatorVerification.ps1 or the verify queue and the log will not line up.
function Get-RoadmapSurfaces {
    param([string]$RoadmapPath)
    $surfaces = [System.Collections.Generic.List[object]]::new()
    if (-not (Test-Path -LiteralPath $RoadmapPath)) { return $surfaces.ToArray() }
    $sha1 = [System.Security.Cryptography.SHA1]::Create()
    $inFence = $false
    $release = '(preamble)'
    $pendingText = $null
    $pendingChecked = $false
    $pendingRelease = $release
    foreach ($line in (Get-Content -LiteralPath $RoadmapPath -Encoding UTF8)) {
        if ($line -match '^\s*```') { $inFence = -not $inFence; $pendingText = $null; continue }
        if ($inFence) { continue }
        $headMatch = [regex]::Match($line, '^(#{2,4})\s+(.+?)\s*$')
        if ($headMatch.Success) {
            # Only ## and ### define the release/section; #### subheadings
            # ("Engineering milestones", "Phase plan") sit WITHIN a release and
            # must not overwrite its context.
            if ($headMatch.Groups[1].Value.Length -le 3) {
                $h = $headMatch.Groups[2].Value.Trim()
                $rel = [regex]::Match($h, '^Release\s+(.+)$')
                $release = if ($rel.Success) { $rel.Groups[1].Value.Trim() } else { $h }
            }
            $pendingText = $null
            continue
        }
        $cb = [regex]::Match($line, '^\s*-\s*\[([ xX])\]\s*(.*)$')
        if ($cb.Success) {
            $pendingChecked = ($cb.Groups[1].Value -match '[xX]')
            $pendingRelease = $release
            $pendingText = $cb.Groups[2].Value
        }
        elseif ($null -ne $pendingText -and $line -match '^\s+\S') {
            $pendingText = ($pendingText + ' ' + $line.Trim())
        }
        else {
            $pendingText = $null
        }

        if ($null -ne $pendingText) {
            $sm = [regex]::Match($pendingText, '\*\(state:\s*([a-z][a-z-]*)')
            if ($sm.Success) {
                $state = $sm.Groups[1].Value
                $text = ($pendingText -replace '\s*\*\(state:.*$', '').Trim()
                if (-not [string]::IsNullOrWhiteSpace($text)) {
                    $norm = ($text.ToLowerInvariant() -replace '\s+', ' ')
                    $idBytes = $sha1.ComputeHash([System.Text.Encoding]::UTF8.GetBytes(("{0}||{1}" -f $pendingRelease, $norm)))
                    $id = -join ($idBytes[0..4] | ForEach-Object { $_.ToString('x2') })
                    $surfaces.Add([pscustomobject]@{ id = $id; release = $pendingRelease; state = $state; checked = $pendingChecked; text = $text })
                }
                $pendingText = $null
            }
        }
    }
    $sha1.Dispose()
    return $surfaces.ToArray()
}

# Sort key so the verify queue leads with the highest-value work: active/current
# sections (no version number — Current Status, Cross-Cutting) float to the top,
# then the newest releases descending, with historical completion-snapshot
# milestones (low versions) last.
function Get-ReleaseSortKey {
    param([string]$Release)
    $m = [regex]::Match($Release, '^(\d+)\.(\d+)(?:\.(\d+))?')
    if ($m.Success) {
        $pat = if ($m.Groups[3].Success) { [int]$m.Groups[3].Value } else { 0 }
        return ([int]$m.Groups[1].Value * 10000 + [int]$m.Groups[2].Value * 100 + $pat)
    }
    return 999999
}

function Get-RoadmapStates {
    $roadmapPath = Join-Path $WorkspaceRoot 'ROADMAP.md'
    $result = [ordered]@{
        totalSurfaces = 0
        byState = [ordered]@{}
        verifyNext = [System.Collections.Generic.List[object]]::new()
        surfaces = [System.Collections.Generic.List[object]]::new()
    }
    foreach ($surface in @(Get-RoadmapSurfaces -RoadmapPath $roadmapPath)) {
        $result.surfaces.Add($surface)
        $result.totalSurfaces++
        if (-not $result.byState.Contains($surface.state)) { $result.byState[$surface.state] = 0 }
        $result.byState[$surface.state]++
        if ($surface.state -eq 'smoke-tested') { $result.verifyNext.Add($surface) }
    }
    return $result
}

# ── Gate parsing ─────────────────────────────────────────────────────────────
function Get-SuiteSubGates {
    param([string]$LogPath)
    $gates = [System.Collections.Generic.List[object]]::new()
    if (-not (Test-Path -LiteralPath $LogPath)) { return $gates.ToArray() }
    foreach ($line in (Get-Content -LiteralPath $LogPath -Encoding UTF8)) {
        # Summary-block lines look like:  "  [PASS] Module smoke (12.3s)"
        # (run-time lines carry "(exit=0, 12.3s)" and are skipped by this regex).
        $m = [regex]::Match($line, '^\s*\[(PASS|FAIL)\]\s+(.+?)\s+\(([\d.]+)s\)\s*$')
        if ($m.Success) {
            $gates.Add([pscustomobject]@{
                name = $m.Groups[2].Value.Trim()
                ok = ($m.Groups[1].Value -eq 'PASS')
                seconds = [double]$m.Groups[3].Value
            })
        }
    }
    # Return an array (not the List) so callers never re-.ToArray() an unrolled
    # collection — the List unrolls on return and the method then vanishes.
    return $gates.ToArray()
}

# ═════════════════════════════════════════════════════════════════════════════
$gateResults = [System.Collections.Generic.List[object]]::new()
$scan = [ordered]@{ ran = $false; ok = $false; port = $Port }

try {
    Write-Host 'GitHub Repo Management — daily evidence driver' -ForegroundColor White
    Write-Host ("WorkspaceRoot: {0}" -f $WorkspaceRoot) -ForegroundColor DarkGray
    Write-Host ("Snapshot:      {0}" -f $evidenceDir) -ForegroundColor DarkGray
    Write-Host ("Port:          {0} (not 7071 — your portal is safe)" -f $Port) -ForegroundColor DarkGray

    $git = Get-GitContext
    Write-Host ("Git:           {0} @ {1}{2}" -f $git.branch, $git.shortSha, $(if ($git.dirty) { " (dirty: $($git.dirtyFiles) files)" } else { '' })) -ForegroundColor DarkGray

    # ── Gate ─────────────────────────────────────────────────────────────────
    if (-not $SkipGate) {
        Push-Location $WorkspaceRoot
        try {
            Write-Section 'Gate: frontend typecheck (tsc --noEmit)'
            & npm run --silent typecheck 2>&1 | Tee-Object -FilePath $gateLog | Out-Host
            $gateResults.Add([pscustomobject]@{ name = 'typecheck'; ok = ($LASTEXITCODE -eq 0); exitCode = $LASTEXITCODE })

            Write-Section 'Gate: frontend unit tests (vitest)'
            & npm run --silent test:unit 2>&1 | Tee-Object -FilePath $gateLog -Append | Out-Host
            $gateResults.Add([pscustomobject]@{ name = 'vitest'; ok = ($LASTEXITCODE -eq 0); exitCode = $LASTEXITCODE })
        }
        finally { Pop-Location }

        Write-Section ('Gate: test suite (Invoke-TestSuite.ps1 -Port {0}{1})' -f $Port, $(if ($SkipApiHost) { ' -SkipApiHost' } else { '' }))
        Clear-ListenerPort -PortNumber $Port
        $suite = Join-Path $WorkspaceRoot 'scripts\Invoke-TestSuite.ps1'
        $suiteArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $suite, '-WorkspaceRoot', $WorkspaceRoot, '-Port', $Port)
        if ($SkipApiHost) { $suiteArgs += '-SkipApiHost' }
        & $pwshExe $suiteArgs 2>&1 | Tee-Object -FilePath $gateLog -Append | Out-Host
        $suiteExit = $LASTEXITCODE
        $subGates = @(Get-SuiteSubGates -LogPath $gateLog)
        $gateResults.Add([pscustomobject]@{ name = 'test-suite'; ok = ($suiteExit -eq 0); exitCode = $suiteExit; subGates = $subGates })

        # The suite's API-host smoke rewrites settings.json; restore before the scan.
        Restore-Settings
    }
    else {
        Write-Section 'Gate skipped (-SkipGate)'
        $notes.Add('Gate skipped via -SkipGate.')
    }

    # ── Live scan (evidence + Release 2.3 history accrual) ────────────────────
    if (-not $SkipScan) {
        Write-Section 'Live scan: boot host + real portfolio assessment'
        Clear-ListenerPort -PortNumber $Port
        $scan.ran = $true
        $baseUrl = "http://127.0.0.1:$Port"
        $shutdownSignal = Join-Path $evidenceDir 'host-shutdown.signal'
        Remove-Item -LiteralPath $shutdownSignal -Force -ErrorAction SilentlyContinue
        $hostScript = Join-Path $WorkspaceRoot 'backend\api-host\Start-RepoManagementApiHost.ps1'

        $job = Start-Job -ScriptBlock {
            param($ScriptPath, $Root, $Log, $ListenPort, $SignalPath)
            & $ScriptPath -WorkspaceRoot $Root -BindAddress '127.0.0.1' -Port $ListenPort -LogPath $Log -ShutdownSignalPath $SignalPath
        } -ArgumentList $hostScript, $WorkspaceRoot, $hostLog, $Port, $shutdownSignal

        try {
            # Readiness poll
            $deadline = (Get-Date).AddSeconds(45)
            $ready = $false
            while ((Get-Date) -lt $deadline) {
                if ($job.State -in @('Failed', 'Stopped', 'Completed')) {
                    $out = Receive-Job -Job $job -Keep -ErrorAction SilentlyContinue | Out-String
                    throw ("Host job exited before readiness. State={0}. Output={1}" -f $job.State, $out.Trim())
                }
                $probe = Invoke-Req -Method Get -Uri "$baseUrl/health/live"
                if ($probe.Ok -and $probe.StatusCode -ge 200 -and $probe.StatusCode -lt 500) { $ready = $true; break }
                Start-Sleep -Milliseconds 500
            }
            if (-not $ready) { throw "Host did not become ready within 45s on port $Port." }

            $live = Invoke-Req -Method Get -Uri "$baseUrl/health/live"
            $readyResp = Invoke-Req -Method Get -Uri "$baseUrl/health/ready"
            $deps = Invoke-Req -Method Get -Uri "$baseUrl/health/dependencies"
            $persist = Invoke-Req -Method Get -Uri "$baseUrl/api/persistence/status"

            Write-Host '  running real portfolio assessment (differential — accrues trend history)...' -ForegroundColor DarkGray
            $assessment = Invoke-Req -Method Get -Uri "$baseUrl/api/portfolio/assessment?scanMode=differential&includeCuration=true"

            # Parse the authoritative scan-summary / scan-budget TRACE lines from
            # this run's fresh host log.
            $summaryLine = $null; $budgetLine = $null
            if (Test-Path -LiteralPath $hostLog) {
                foreach ($l in (Get-Content -LiteralPath $hostLog -Encoding UTF8)) {
                    if ($l -match 'scan-summary') { $summaryLine = $l }
                    if ($l -match 'scan-budget') { $budgetLine = $l }
                }
            }
            $scanMetrics = [ordered]@{ mode = $null; reused = $null; reindexed = $null; failed = $null; durationMs = $null; totalMs = $null; reposAssessed = $null }
            if ($summaryLine) {
                foreach ($k in @('mode', 'reused', 'reindexed', 'failed', 'durationMs')) {
                    $mm = [regex]::Match($summaryLine, ("{0}=([^\s]+)" -f $k))
                    if ($mm.Success) { $scanMetrics[$k] = $mm.Groups[1].Value }
                }
            }
            if ($budgetLine) {
                foreach ($k in @('totalMs', 'reposAssessed')) {
                    $mm = [regex]::Match($budgetLine, ("{0}=([^\s]+)" -f $k))
                    if ($mm.Success) { $scanMetrics[$k] = $mm.Groups[1].Value }
                }
            }

            $persistOk = ($persist.Ok -and $null -ne $persist.Json -and $persist.Json.success -eq $true)
            $scan.ok = ($assessment.Ok -and $assessment.StatusCode -eq 200)
            $scan.health = [ordered]@{
                live = $live.StatusCode; ready = $readyResp.StatusCode; dependencies = $deps.StatusCode
            }
            $scan.persistence = if ($persistOk) {
                [ordered]@{
                    available = $persist.Json.capability.available
                    enabled = $persist.Json.database.enabled
                    tables = @($persist.Json.tables).Count
                    agentRunEventCount = $persist.Json.agentRunEventCount
                }
            } else { [ordered]@{ available = $null; enabled = $null; tables = $null; agentRunEventCount = $null } }
            $scan.assessment = [ordered]@{ httpStatus = $assessment.StatusCode }
            foreach ($k in $scanMetrics.Keys) { $scan.assessment[$k] = $scanMetrics[$k] }

            # Release 2.7 Phase D — scheduled app.db maintenance. Driven through
            # the host's own route rather than the module directly: the host holds
            # the SQLite connections, so an out-of-process VACUUM would contend for
            # the write lock. Runs AFTER the assessment so the scan's fresh rows are
            # already written and the prune reflects this run.
            Write-Host '  running app.db maintenance (snapshot retention + VACUUM)...' -ForegroundColor DarkGray
            $maint = Invoke-Req -Method Post -Uri "$baseUrl/api/maintenance/database" -Body '{}'
            $maintOk = ($maint.Ok -and $maint.StatusCode -eq 200 -and $null -ne $maint.Json -and $maint.Json.success -eq $true)
            $scan.maintenance = if ($maintOk) {
                [ordered]@{
                    httpStatus     = $maint.StatusCode
                    rowsRemoved    = $maint.Json.data.totalRowsRemoved
                    vacuumed       = $maint.Json.data.vacuumed
                    reclaimedBytes = $maint.Json.data.reclaimedBytes
                    sizeAfterBytes = $maint.Json.data.sizeAfterBytes
                    durationMs     = $maint.Json.data.durationMs
                }
            } else {
                [ordered]@{ httpStatus = $maint.StatusCode; rowsRemoved = $null; vacuumed = $null; reclaimedBytes = $null; sizeAfterBytes = $null; durationMs = $null }
            }
            Write-Host ("  maintenance: rowsRemoved={0} vacuumed={1} reclaimedBytes={2} sizeAfter={3}" -f `
                    $scan.maintenance.rowsRemoved, $scan.maintenance.vacuumed, $scan.maintenance.reclaimedBytes, $scan.maintenance.sizeAfterBytes) -ForegroundColor DarkGray
            if (-not $maintOk) { $notes.Add(("app.db maintenance did not succeed (HTTP {0}) — see host.log" -f $maint.StatusCode)) }

            # Release 3.3 milestone 1 — scheduled ledger retention. Same shape
            # as the app.db pass: driven through the host's route, running
            # daily so the append-only ledgers stay bounded unattended. The
            # pruned lines are archived verbatim, never destroyed.
            Write-Host '  running ledger retention (archive-then-trim)...' -ForegroundColor DarkGray
            $ledgerMaint = Invoke-Req -Method Post -Uri "$baseUrl/api/maintenance/ledgers" -Body '{}'
            $ledgerOk = ($ledgerMaint.Ok -and $ledgerMaint.StatusCode -eq 200 -and $null -ne $ledgerMaint.Json -and $ledgerMaint.Json.success -eq $true)
            $scan.ledgerRetention = if ($ledgerOk) {
                $ledgerReports = @($ledgerMaint.Json.data.reports)
                [ordered]@{
                    httpStatus  = $ledgerMaint.StatusCode
                    prunedTotal = [int](@($ledgerReports | ForEach-Object { [int]$_.pruned } | Measure-Object -Sum).Sum)
                    ledgers     = @($ledgerReports | Where-Object { [int]$_.pruned -gt 0 } | ForEach-Object { "{0}:{1}" -f $_.name, $_.pruned })
                }
            } else {
                [ordered]@{ httpStatus = $ledgerMaint.StatusCode; prunedTotal = $null; ledgers = @() }
            }
            Write-Host ("  ledger retention: prunedTotal={0} ({1})" -f $scan.ledgerRetention.prunedTotal, ($scan.ledgerRetention.ledgers -join ', ')) -ForegroundColor DarkGray
            if (-not $ledgerOk) { $notes.Add(("ledger retention did not succeed (HTTP {0}) — see host.log" -f $ledgerMaint.StatusCode)) }

            Write-Host ("  health live/ready/deps: {0}/{1}/{2}" -f $live.StatusCode, $readyResp.StatusCode, $deps.StatusCode) -ForegroundColor DarkGray
            Write-Host ("  persistence: available={0} enabled={1} tables={2} agentRunEvents={3}" -f $scan.persistence.available, $scan.persistence.enabled, $scan.persistence.tables, $scan.persistence.agentRunEventCount) -ForegroundColor DarkGray
            Write-Host ("  scan: mode={0} reused={1} reindexed={2} failed={3} durationMs={4}" -f $scanMetrics.mode, $scanMetrics.reused, $scanMetrics.reindexed, $scanMetrics.failed, $scanMetrics.durationMs) -ForegroundColor DarkGray
            if ($scan.ok) { Write-Host '[PASS] live scan captured' -ForegroundColor Green }
            else { Write-Host ("[FAIL] live scan — assessment HTTP {0}" -f $assessment.StatusCode) -ForegroundColor Red }
        }
        finally {
            # Graceful shutdown via signal file, then force-kill the port, then Stop-Job.
            try { Set-Content -LiteralPath $shutdownSignal -Value 'shutdown' -Encoding ascii -Force; $null = Wait-Job -Job $job -Timeout 5 } catch { }
            Clear-ListenerPort -PortNumber $Port
            Stop-Job -Job $job -ErrorAction SilentlyContinue | Out-Null
            Remove-Job -Job $job -Force -ErrorAction SilentlyContinue | Out-Null
            Remove-Item -LiteralPath $shutdownSignal -Force -ErrorAction SilentlyContinue
        }
    }
    else {
        Write-Section 'Live scan skipped (-SkipScan)'
        $notes.Add('Live scan skipped via -SkipScan — no trend history accrued this run.')
    }

    # ── Verify-next queue (ROADMAP states) ───────────────────────────────────
    Write-Section 'Operator-verification queue (ROADMAP states)'
    $states = Get-RoadmapStates
    $verifyLogPath = Join-Path $WorkspaceRoot 'evidence\operator-verification-log.jsonl'
    $verifiedIds = @{}
    if (Test-Path -LiteralPath $verifyLogPath) {
        foreach ($l in (Get-Content -LiteralPath $verifyLogPath -Encoding UTF8)) {
            if ([string]::IsNullOrWhiteSpace($l)) { continue }
            try { $rec = $l | ConvertFrom-Json; if ($rec.surfaceId) { $verifiedIds[$rec.surfaceId] = $true } } catch { }
        }
    }
    $pendingVerify = @($states.verifyNext.ToArray() |
        Where-Object { -not $verifiedIds.ContainsKey($_.id) } |
        Sort-Object @{ Expression = { Get-ReleaseSortKey $_.release }; Descending = $true }, @{ Expression = 'release' })
    $stateSummary = ($states.byState.GetEnumerator() | ForEach-Object { "{0}={1}" -f $_.Key, $_.Value }) -join '  '
    Write-Host ("  {0} surfaces carry a state:  {1}" -f $states.totalSurfaces, $stateSummary) -ForegroundColor DarkGray
    Write-Host ("  {0} at smoke-tested and not yet in the verification log — top of the daily queue:" -f $pendingVerify.Count) -ForegroundColor DarkGray
    foreach ($s in ($pendingVerify | Select-Object -First 5)) {
        Write-Host ("    [{0}] {1} — {2}" -f $s.id, $s.release, $s.text) -ForegroundColor DarkGray
    }

    # ── Write artifacts ──────────────────────────────────────────────────────
    $gateOverall = if ($SkipGate) { $null } else { -not ($gateResults.ToArray() | Where-Object { -not $_.ok }) }
    $scanOverall = if ($SkipScan) { $null } else { [bool]$scan.ok }
    $verdict = if (($gateOverall -eq $false) -or ($scanOverall -eq $false)) { 'red' } else { 'green' }

    $manifest = [ordered]@{
        schemaVersion = '1'
        generatedAt = (Get-Date).ToString('o')
        stamp = $stamp
        workspaceRoot = $WorkspaceRoot
        verdict = $verdict
        git = $git
        gate = [ordered]@{ ran = (-not $SkipGate); passed = $gateOverall; results = $gateResults.ToArray(); logPath = $(if (Test-Path -LiteralPath $gateLog) { (Resolve-Path -LiteralPath $gateLog).Path } else { $null }) }
        scan = $scan
        verification = [ordered]@{
            totalSurfaces = $states.totalSurfaces
            byState = $states.byState
            verifyNextCount = $pendingVerify.Count
            verifyNextTop = @($pendingVerify | Select-Object -First 10 | ForEach-Object { [ordered]@{ id = $_.id; release = $_.release; text = $_.text } })
        }
        notes = $notes.ToArray()
    }
    $manifest | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
    $states.surfaces.ToArray() | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $stateIndexPath -Encoding UTF8

    # summary.md — the human one-pager
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine("# Daily evidence — $stamp")
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine("**Verdict:** $($verdict.ToUpper())")
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine("- **Git:** ``$($git.branch)`` @ ``$($git.shortSha)``" + $(if ($git.dirty) { " — dirty ($($git.dirtyFiles) files)" } else { ' — clean' }))
    [void]$sb.AppendLine("- **Generated:** $((Get-Date).ToString('u'))")
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('## Gate')
    [void]$sb.AppendLine('')
    if ($SkipGate) {
        [void]$sb.AppendLine('_Skipped (-SkipGate)._')
    }
    else {
        [void]$sb.AppendLine('| Gate | Result | Exit |')
        [void]$sb.AppendLine('| --- | --- | --- |')
        foreach ($g in $gateResults) {
            [void]$sb.AppendLine("| $($g.name) | $(if ($g.ok) { 'PASS' } else { 'FAIL' }) | $($g.exitCode) |")
        }
        $subs = @($gateResults.ToArray() | Where-Object { $_.name -eq 'test-suite' -and $_.PSObject.Properties.Name -contains 'subGates' } | Select-Object -ExpandProperty subGates)
        if ($subs.Count -gt 0) {
            [void]$sb.AppendLine('')
            [void]$sb.AppendLine('Test-suite gates:')
            [void]$sb.AppendLine('')
            foreach ($sg in $subs) { [void]$sb.AppendLine("- $(if ($sg.ok) { '✅' } else { '❌' }) $($sg.name) ($($sg.seconds)s)") }
        }
    }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('## Live scan')
    [void]$sb.AppendLine('')
    if ($SkipScan) {
        [void]$sb.AppendLine('_Skipped (-SkipScan)._')
    }
    else {
        [void]$sb.AppendLine("- **Assessment:** HTTP $($scan.assessment.httpStatus), mode=$($scan.assessment.mode), reused=$($scan.assessment.reused), reindexed=$($scan.assessment.reindexed), failed=$($scan.assessment.failed), durationMs=$($scan.assessment.durationMs)")
    [void]$sb.AppendLine("- **Health (live/ready/deps):** $($scan.health.live)/$($scan.health.ready)/$($scan.health.dependencies)")
        [void]$sb.AppendLine("- **Persistence:** available=$($scan.persistence.available), enabled=$($scan.persistence.enabled), tables=$($scan.persistence.tables), agentRunEvents=$($scan.persistence.agentRunEventCount)")
        if ($scan.Contains('maintenance')) {
            [void]$sb.AppendLine("- **app.db maintenance:** HTTP $($scan.maintenance.httpStatus), rowsRemoved=$($scan.maintenance.rowsRemoved), vacuumed=$($scan.maintenance.vacuumed), reclaimedBytes=$($scan.maintenance.reclaimedBytes), sizeAfterBytes=$($scan.maintenance.sizeAfterBytes)")
        }
    }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('## Verify-next queue')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine("Surfaces at ``smoke-tested`` not yet in the verification log ($($pendingVerify.Count) total). Promote one to ``operator-verified`` today with ``Add-OperatorVerification.ps1``.")
    [void]$sb.AppendLine('')
    $sb.ToString() | Set-Content -LiteralPath $summaryPath -Encoding UTF8

    # verify-queue.md — the standalone actionable list
    $qb = [System.Text.StringBuilder]::new()
    [void]$qb.AppendLine("# Verify-next queue — $stamp")
    [void]$qb.AppendLine('')
    [void]$qb.AppendLine("$($pendingVerify.Count) surfaces are at ``smoke-tested`` and not yet recorded as operator-verified.")
    [void]$qb.AppendLine('Pick one, drive it by hand against the live workspace, then record it:')
    [void]$qb.AppendLine('')
    [void]$qb.AppendLine('```powershell')
    [void]$qb.AppendLine('pwsh -File scripts/Add-OperatorVerification.ps1 -SurfaceId <id> -Evidence "<what you observed / artifact path>"')
    [void]$qb.AppendLine('```')
    [void]$qb.AppendLine('')
    [void]$qb.AppendLine('| Id | Release | Surface |')
    [void]$qb.AppendLine('| --- | --- | --- |')
    foreach ($s in $pendingVerify) {
        $safeText = $s.text -replace '\|', '\|'
        [void]$qb.AppendLine("| $($s.id) | $($s.release) | $safeText |")
    }
    $qb.ToString() | Set-Content -LiteralPath $queuePath -Encoding UTF8

    # ── Final verdict ────────────────────────────────────────────────────────
    Write-Section 'Daily evidence summary'
    Write-Host ("  Verdict:   {0}" -f $verdict.ToUpper()) -ForegroundColor $(if ($verdict -eq 'green') { 'Green' } else { 'Red' })
    Write-Host ("  Snapshot:  {0}" -f $evidenceDir) -ForegroundColor DarkGray
    Write-Host ("  Manifest:  {0}" -f $manifestPath) -ForegroundColor DarkGray
    Write-Host ("  Verify:    {0} surface(s) queued -> {1}" -f $pendingVerify.Count, $queuePath) -ForegroundColor DarkGray

    if ($verdict -eq 'red') { exit 1 }
    exit 0
}
finally {
    Restore-Settings
}
