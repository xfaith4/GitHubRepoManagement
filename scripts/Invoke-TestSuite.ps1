<#
.SYNOPSIS
    Canonical test suite — the exit-0/1 gate behind `npm test` AND behind CI.

.DESCRIPTION
    The single gate list. .github/workflows/ci-smoke.yml invokes THIS file, so
    CI and local verification run the same gates by construction — a gate added
    here runs on every PR; a gate that exists anywhere else gates nothing.
    Gates: module smoke, adapter smoke, frontend typecheck/unit tests/build,
    API-host smoke, API contract (Pester), auth smoke, repository-structure
    audit, config-integrity checks, and the roadmap structure linter
    (-FailOnError). A module-smoke tripwire (ROADMAP Lane 0.8) enforces that
    ci-smoke.yml keeps invoking this suite un-hollowed.

    Each script gate runs in its own `pwsh -File` child process so a gate's
    exit code is a real process exit code (0 = pass; an unhandled `throw`
    under $ErrorActionPreference='Stop' = 1) and no gate leaks module or
    strict-mode state into the next.

    The API-host smoke stands up a live server on $Port; a stale listener from
    a crashed prior run is the one reliably reproducible failure mode (observed
    as "connection forcibly closed by the remote host"), so the port is freed
    before that gate runs.

.PARAMETER SkipApiHost
    Omit the ~4-minute live-workspace API-host smoke. Used by `npm run
    test:fast` for a quick hermetic pass; CI and `npm test` run the full suite.
#>
[CmdletBinding()]
param(
    [string]$WorkspaceRoot,
    [switch]$SkipApiHost,
    # A DEDICATED port, never 7071: Clear-ListenerPort terminates whatever is
    # listening on $Port before the API-host gate binds it, so defaulting to the
    # live portal's port meant a bare `npm test` killed the operator's running
    # portal. Same convention as Invoke-DailyEvidence.ps1.
    [int]$Port = 7171
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($WorkspaceRoot)) {
    $WorkspaceRoot = Split-Path -Parent $PSScriptRoot
}
$WorkspaceRoot = (Resolve-Path -LiteralPath $WorkspaceRoot).Path

$pwshExe = Join-Path $PSHOME 'pwsh.exe'
if (-not (Test-Path -LiteralPath $pwshExe)) { $pwshExe = 'pwsh' }

$gateResults = [System.Collections.Generic.List[object]]::new()

function Clear-ListenerPort {
    param([int]$PortNumber)
    try {
        $pids = Get-NetTCPConnection -LocalPort $PortNumber -State Listen -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty OwningProcess -Unique
        foreach ($procId in @($pids)) {
            try {
                Stop-Process -Id $procId -Force -ErrorAction Stop
                Write-Host ("  freed port {0} (terminated stale PID {1})" -f $PortNumber, $procId) -ForegroundColor DarkGray
            } catch { }
        }
        # Wait for the port to actually release before the next gate binds it —
        # a lingering stale listener causes a "connection forcibly closed" flake.
        $deadline = (Get-Date).AddSeconds(10)
        while ((Get-Date) -lt $deadline) {
            if (-not (Get-NetTCPConnection -LocalPort $PortNumber -State Listen -ErrorAction SilentlyContinue)) { break }
            Start-Sleep -Milliseconds 300
        }
    } catch { }
}

function Invoke-ScriptGate {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$ScriptPath,
        [string[]]$ScriptArgs = @()
    )
    Write-Host ''
    Write-Host "===== $Name =====" -ForegroundColor Cyan
    if (-not (Test-Path -LiteralPath $ScriptPath)) {
        Write-Host "[FAIL] $Name — script not found: $ScriptPath" -ForegroundColor Red
        $gateResults.Add([pscustomobject]@{ Name = $Name; Ok = $false; Seconds = 0.0 })
        return
    }
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    & $pwshExe (@('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $ScriptPath) + $ScriptArgs)
    $code = $LASTEXITCODE
    $sw.Stop()
    $ok = ($code -eq 0)
    $seconds = [math]::Round($sw.Elapsed.TotalSeconds, 1)
    Write-Host ("[{0}] {1} (exit={2}, {3}s)" -f $(if ($ok) { 'PASS' } else { 'FAIL' }), $Name, $code, $seconds) -ForegroundColor $(if ($ok) { 'Green' } else { 'Red' })
    $gateResults.Add([pscustomobject]@{ Name = $Name; Ok = $ok; Seconds = $seconds })
}

function Invoke-NpmGate {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$ScriptName
    )
    Write-Host ''
    Write-Host "===== $Name =====" -ForegroundColor Cyan
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $ok = $false
    $npmCommand = Get-Command npm -ErrorAction SilentlyContinue
    if ($null -eq $npmCommand) {
        # Missing toolchain is a FAILING gate with a named cause, never a skip —
        # a suite that silently passes without Node is the vacuous-green
        # workflow this suite exists to replace.
        Write-Host '  npm not found on PATH — install Node.js; the frontend gates are required.' -ForegroundColor Red
    }
    elseif (-not (Test-Path -LiteralPath (Join-Path $WorkspaceRoot 'node_modules'))) {
        Write-Host '  node_modules missing — run `npm ci --include=optional` first.' -ForegroundColor Red
    }
    else {
        Push-Location $WorkspaceRoot
        try {
            & npm run --silent $ScriptName
            $ok = ($LASTEXITCODE -eq 0)
        }
        finally { Pop-Location }
    }
    $sw.Stop()
    $seconds = [math]::Round($sw.Elapsed.TotalSeconds, 1)
    Write-Host ("[{0}] {1} ({2}s)" -f $(if ($ok) { 'PASS' } else { 'FAIL' }), $Name, $seconds) -ForegroundColor $(if ($ok) { 'Green' } else { 'Red' })
    $gateResults.Add([pscustomobject]@{ Name = $Name; Ok = $ok; Seconds = $seconds })
}

function Invoke-InProcessGate {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$Action
    )
    Write-Host ''
    Write-Host "===== $Name =====" -ForegroundColor Cyan
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $ok = $true
    try { & $Action }
    catch { $ok = $false; Write-Host ("  {0}" -f $_.Exception.Message) -ForegroundColor Red }
    $sw.Stop()
    $seconds = [math]::Round($sw.Elapsed.TotalSeconds, 1)
    Write-Host ("[{0}] {1} ({2}s)" -f $(if ($ok) { 'PASS' } else { 'FAIL' }), $Name, $seconds) -ForegroundColor $(if ($ok) { 'Green' } else { 'Red' })
    $gateResults.Add([pscustomobject]@{ Name = $Name; Ok = $ok; Seconds = $seconds })
}

$scriptsDir = Join-Path $WorkspaceRoot 'scripts'
$toolsDir = Join-Path $WorkspaceRoot 'tools'
$rootArgs = @('-WorkspaceRoot', $WorkspaceRoot)

Write-Host "GitHub Repo Management — test suite" -ForegroundColor White
Write-Host ("WorkspaceRoot: {0}" -f $WorkspaceRoot) -ForegroundColor DarkGray
Write-Host ("SkipApiHost:   {0}" -f [bool]$SkipApiHost) -ForegroundColor DarkGray

Invoke-ScriptGate -Name 'Module smoke'      -ScriptPath (Join-Path $scriptsDir 'Invoke-ModuleSmokeTest.ps1')         -ScriptArgs $rootArgs
Invoke-ScriptGate -Name 'Adapter smoke'     -ScriptPath (Join-Path $scriptsDir 'Invoke-AdapterSmokeTest.ps1')        -ScriptArgs $rootArgs

# Frontend gates before the slow API-host smoke: cheap failures fail fast.
# These were dark until 2026-08-10 — 149 vitest assertions, the typecheck, and
# the production build ran only when someone typed them (ROADMAP Lane 0.8).
Invoke-NpmGate -Name 'Frontend typecheck'  -ScriptName 'typecheck'
Invoke-NpmGate -Name 'Frontend lint'       -ScriptName 'lint'
Invoke-NpmGate -Name 'Frontend unit tests' -ScriptName 'test:unit'
Invoke-NpmGate -Name 'Frontend build'      -ScriptName 'build'

# PowerShell lint: PSSA with a per-rule ratchet baseline — 0 Error-severity
# findings ever; warning counts may only shrink (ROADMAP Lane 0.8).
Invoke-ScriptGate -Name 'PowerShell lint'   -ScriptPath (Join-Path $scriptsDir 'Invoke-LintGate.ps1')             -ScriptArgs $rootArgs

if (-not $SkipApiHost) {
    Clear-ListenerPort -PortNumber $Port
    # Thread -Port/-BaseUrl into the smoke so a non-default port actually moves
    # the live host off 7071. Without this the suite freed $Port but the smoke
    # still bound its 7071 default — which, on a machine already running the
    # portal on 7071, made the host terminate the operator's running instance.
    $apiHostArgs = $rootArgs + @('-Port', $Port, '-BaseUrl', "http://127.0.0.1:$Port")
    Invoke-ScriptGate -Name 'API host smoke' -ScriptPath (Join-Path $scriptsDir 'Invoke-ApiHostSmokeTest.ps1')        -ScriptArgs $apiHostArgs
}
else {
    Write-Host ''
    Write-Host '===== API host smoke =====' -ForegroundColor Cyan
    Write-Host '[SKIP] API host smoke (-SkipApiHost)' -ForegroundColor Yellow
}

Invoke-ScriptGate -Name 'API contract'      -ScriptPath (Join-Path $scriptsDir 'Invoke-ApiContractTest.ps1')          -ScriptArgs $rootArgs
Invoke-ScriptGate -Name 'Auth smoke'        -ScriptPath (Join-Path $scriptsDir 'Invoke-AuthSmokeTest.ps1')            -ScriptArgs $rootArgs
Invoke-ScriptGate -Name 'Repo structure'    -ScriptPath (Join-Path $scriptsDir 'Invoke-RepositoryStructureAudit.ps1') -ScriptArgs $rootArgs

Invoke-InProcessGate -Name 'doc-standards.json integrity' -Action {
    $path = Join-Path $WorkspaceRoot 'backend/config/doc-standards.json'
    if (-not (Test-Path -LiteralPath $path)) { throw "doc-standards.json not found at $path" }
    $parsed = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $path -Raw -Encoding UTF8)
    if ($null -eq $parsed.requiredRootFiles) { throw 'doc-standards.json missing requiredRootFiles' }
    if ($null -eq $parsed.readmeStandards) { throw 'doc-standards.json missing readmeStandards' }
    Write-Host ("  doc-standards.json valid: {0} required file specs" -f @($parsed.requiredRootFiles).Count) -ForegroundColor DarkGray
}

Invoke-InProcessGate -Name 'roadmap standard assets integrity' -Action {
    $stdDir = Join-Path $WorkspaceRoot 'standards/roadmap'
    $assets = @(
        (Join-Path $stdDir 'roadmap-audit-rules.json'),
        (Join-Path $stdDir 'roadmap-contract.schema.json'),
        (Join-Path $stdDir 'ROADMAP_TEMPLATE.md'),
        (Join-Path $stdDir 'ROADMAP_MATURITY_MODEL.md'),
        (Join-Path $stdDir 'roadmap-repair-prompt.md')
    )
    foreach ($p in $assets) { if (-not (Test-Path -LiteralPath $p)) { throw "Roadmap standard asset not found: $p" } }
    $rules = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $assets[0] -Raw -Encoding UTF8)
    if ($null -eq $rules.rules) { throw "roadmap-audit-rules.json missing 'rules' array" }
    if ($null -eq $rules.maturityThresholds) { throw "roadmap-audit-rules.json missing 'maturityThresholds'" }
    if (@($rules.rules).Count -eq 0) { throw "roadmap-audit-rules.json 'rules' array is empty" }
    $schema = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $assets[1] -Raw -Encoding UTF8)
    if ($null -eq $schema.properties) { throw "roadmap-contract.schema.json missing 'properties'" }
    Write-Host ("  roadmap standard assets valid: {0} audit rules" -f @($rules.rules).Count) -ForegroundColor DarkGray
}

Invoke-InProcessGate -Name 'Agent API OpenAPI spec (Release 2.4)' -Action {
    $specPath = Join-Path $WorkspaceRoot 'docs/reference/agent-api.yaml'
    if (-not (Test-Path -LiteralPath $specPath)) { throw "agent-api.yaml not found at $specPath" }
    $raw = Get-Content -LiteralPath $specPath -Raw
    $requiredPaths = @('/api/v1/agent/readiness/{repoName}', '/api/v1/agent/claim/{repoName}', '/api/v1/agent/complete/{repoName}', '/api/v1/agent/queue')
    if (Get-Module -ListAvailable powershell-yaml) {
        Import-Module powershell-yaml -ErrorAction Stop
        $doc = ConvertFrom-Yaml $raw
        if ([string]$doc.openapi -notmatch '^3\.1') { throw "agent-api.yaml openapi must be 3.1.x, got '$($doc.openapi)'" }
        foreach ($p in $requiredPaths) { if (-not $doc.paths.ContainsKey($p)) { throw "agent-api.yaml missing path $p" } }
        if (-not $doc.paths.'/api/v1/agent/claim/{repoName}'.post.responses.ContainsKey('409')) { throw 'agent-api.yaml claim route must document a 409 response' }
        Write-Host ("  agent-api.yaml parsed as OpenAPI {0}, {1} paths, claim 409 present" -f $doc.openapi, @($doc.paths.Keys).Count) -ForegroundColor DarkGray
    }
    else {
        # Dependency-free structural fallback when powershell-yaml is absent.
        if ($raw -notmatch '(?m)^openapi:\s*3\.1') { throw "agent-api.yaml must declare openapi: 3.1.x" }
        foreach ($p in $requiredPaths) { if ($raw -notmatch [regex]::Escape($p)) { throw "agent-api.yaml missing path $p" } }
        if ($raw -notmatch '"409"') { throw 'agent-api.yaml must document a 409 response' }
        Write-Host '  agent-api.yaml structural check passed (powershell-yaml not installed)' -ForegroundColor DarkGray
    }
}

Invoke-InProcessGate -Name 'Roadmap contract spec directory (Release 2.3 Phase 4)' -Action {
    $specDir = Join-Path $WorkspaceRoot 'spec/roadmap-contract'
    if (-not (Test-Path -LiteralPath $specDir)) { throw "spec/roadmap-contract not found" }
    foreach ($f in @('README.md', 'ROADMAP_TEMPLATE.md', 'roadmap-contract.schema.json', 'roadmap-audit-rules.json', 'ROADMAP_MATURITY_MODEL.md')) {
        if (-not (Test-Path -LiteralPath (Join-Path $specDir $f))) { throw "spec/roadmap-contract missing $f (not self-contained)" }
    }
    $null = ConvertFrom-Json (Get-Content -LiteralPath (Join-Path $specDir 'roadmap-contract.schema.json') -Raw)
    $rules = ConvertFrom-Json (Get-Content -LiteralPath (Join-Path $specDir 'roadmap-audit-rules.json') -Raw)
    if ($null -eq $rules.rules) { throw "spec roadmap-audit-rules.json missing 'rules'" }
    Write-Host '  spec/roadmap-contract self-contained: template + schema + rules + maturity model present' -ForegroundColor DarkGray
}

Invoke-InProcessGate -Name 'roadmap-audit-action package (Release 2.3 Phase 3)' -Action {
    $actionDir = Join-Path $WorkspaceRoot '.github/actions/roadmap-audit-action'
    foreach ($f in @('action.yml', 'audit.ps1', 'README.md')) {
        if (-not (Test-Path -LiteralPath (Join-Path $actionDir $f))) { throw "roadmap-audit-action missing $f" }
    }
    if ((Get-Content -LiteralPath (Join-Path $actionDir 'action.yml') -Raw) -notmatch 'using:\s*"?composite') { throw 'action.yml must be a composite action' }
    # Run in a child process — audit.ps1 calls `exit`, which would otherwise end this suite.
    & $pwshExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $actionDir 'audit.ps1') -Path (Join-Path $WorkspaceRoot 'ROADMAP.md') -FailOnError | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "roadmap-audit-action audit failed against ROADMAP.md (exit $LASTEXITCODE)" }
    Write-Host '  roadmap-audit-action: composite action audits ROADMAP.md and passes' -ForegroundColor DarkGray
}

Invoke-ScriptGate -Name 'Roadmap structure lint' -ScriptPath (Join-Path $toolsDir 'Test-RoadmapStructure.ps1') -ScriptArgs @('-Path', (Join-Path $WorkspaceRoot 'ROADMAP.md'), '-FailOnError')

# Release 3.4, recorded 2026-08-15. PR #134 shipped a tested 306-line module and
# left all six of its release's milestones reading `planned`; the next agent to
# read the roadmap was one step from rebuilding it. This gate refuses a commit
# that claims a release, ships capability code, and does not advance a milestone.
# Verified non-vacuous by running it against 17dc1db, which it fails.
Invoke-ScriptGate -Name 'Roadmap capability record' -ScriptPath (Join-Path $toolsDir 'Test-RoadmapCapabilityRecord.ps1') -ScriptArgs @('-FailOnError')

# ── Summary ────────────────────────────────────────────────────────────────
Write-Host ''
Write-Host '===== Test suite summary =====' -ForegroundColor White
foreach ($g in $gateResults) {
    Write-Host ("  {0} {1} ({2}s)" -f $(if ($g.Ok) { '[PASS]' } else { '[FAIL]' }), $g.Name, $g.Seconds) -ForegroundColor $(if ($g.Ok) { 'Green' } else { 'Red' })
}
$failed = @($gateResults | Where-Object { -not $_.Ok })
if ($failed.Count -gt 0) {
    Write-Host ("`nTEST SUITE FAILED — {0} gate(s) failed." -f $failed.Count) -ForegroundColor Red
    exit 1
}
Write-Host "`nTEST SUITE PASSED — all $($gateResults.Count) gate(s) green." -ForegroundColor Green
exit 0
