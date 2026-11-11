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
    [int]$Port = 7171,
    # CI runs the suite as three parallel jobs, one per shard (ci-smoke.yml), so
    # the wall clock is the slowest shard, not the sum of every gate. 'all', the
    # default, runs every gate in order, as `npm test` always has. Every gate
    # names its shard with -In; the frontend build sits in 'host' because the
    # API-host smoke tests the built bundle in frontend/dist.
    [ValidateSet('all', 'module', 'host', 'static')]
    [string]$Shard = 'all'
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
            # Best-effort: a stale listener that exited between the query and the kill is already gone, which is the outcome wanted.
            } catch { $null = $_ }
        }
        # Wait for the port to actually release before the next gate binds it —
        # a lingering stale listener causes a "connection forcibly closed" flake.
        $deadline = (Get-Date).AddSeconds(10)
        while ((Get-Date) -lt $deadline) {
            if (-not (Get-NetTCPConnection -LocalPort $PortNumber -State Listen -ErrorAction SilentlyContinue)) { break }
            Start-Sleep -Milliseconds 300
        }
    # Best-effort: port cleanup is best-effort; a port still busy surfaces as the host failing to bind, with its own message.
    } catch { $null = $_ }
}

# A gate runs when the suite runs every shard or the gate's own one. A gate that
# names no shard stops the suite: it would otherwise run in no CI job at all.
function Test-GateInShard {
    param([string]$Name, [string]$In)
    if ($In -notin @('module', 'host', 'static')) {
        throw "Gate '$Name' names no shard. Pass -In module, host or static so a CI job runs it."
    }
    return ($Shard -eq 'all' -or $Shard -eq $In)
}

function Invoke-ScriptGate {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$ScriptPath,
        [string[]]$ScriptArgs = @(),
        [string]$In
    )
    if (-not (Test-GateInShard -Name $Name -In $In)) { return }
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
        [Parameter(Mandatory)][string]$ScriptName,
        [string]$In
    )
    if (-not (Test-GateInShard -Name $Name -In $In)) { return }
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
        [Parameter(Mandatory)][scriptblock]$Action,
        [string]$In
    )
    if (-not (Test-GateInShard -Name $Name -In $In)) { return }
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
Write-Host ("SkipApiHost:   {0}`nShard:         {1}" -f [bool]$SkipApiHost, $Shard) -ForegroundColor DarkGray

Invoke-ScriptGate -Name 'Module smoke'      -ScriptPath (Join-Path $scriptsDir 'Invoke-ModuleSmokeTest.ps1')         -ScriptArgs $rootArgs -In module
Invoke-ScriptGate -Name 'Adapter smoke'     -ScriptPath (Join-Path $scriptsDir 'Invoke-AdapterSmokeTest.ps1')        -ScriptArgs $rootArgs -In module

# Frontend gates before the slow API-host smoke: cheap failures fail fast.
# These were dark until 2026-08-10 — 149 vitest assertions, the typecheck, and
# the production build ran only when someone typed them (ROADMAP Lane 0.8).
# Ratchets against a committed baseline, so it fails only on NEW unrestored
# `outline-none`. The old tiny-text rule is retired (see tools/Measure-UiRatchet.mjs)
# because the product's density ladder is now intentional design, not debt.
Invoke-NpmGate -Name 'UI debt ratchet'     -ScriptName 'ui:ratchet' -In static
Invoke-NpmGate -Name 'Frontend typecheck'  -ScriptName 'typecheck' -In static
Invoke-NpmGate -Name 'Frontend lint'       -ScriptName 'lint' -In static
Invoke-NpmGate -Name 'Frontend unit tests' -ScriptName 'test:unit' -In static
Invoke-NpmGate -Name 'Frontend build'      -ScriptName 'build' -In host

# PowerShell lint: PSSA with a per-rule ratchet baseline — 0 Error-severity
# findings ever; warning counts may only shrink (ROADMAP Lane 0.8).
Invoke-ScriptGate -Name 'PowerShell lint'   -ScriptPath (Join-Path $scriptsDir 'Invoke-LintGate.ps1')             -ScriptArgs $rootArgs -In static

if (-not $SkipApiHost) {
    if ($Shard -in @('all', 'host')) { Clear-ListenerPort -PortNumber $Port }
    # Thread -Port/-BaseUrl into the smoke so a non-default port actually moves
    # the live host off 7071. Without this the suite freed $Port but the smoke
    # still bound its 7071 default — which, on a machine already running the
    # portal on 7071, made the host terminate the operator's running instance.
    $apiHostArgs = $rootArgs + @('-Port', $Port, '-BaseUrl', "http://127.0.0.1:$Port")
    Invoke-ScriptGate -Name 'API host smoke' -ScriptPath (Join-Path $scriptsDir 'Invoke-ApiHostSmokeTest.ps1')        -ScriptArgs $apiHostArgs -In host

    # Lane 0.21, 2026-09-15: the assessment route answers from the worker's
    # last result while the worker scans. Boots its own host on a free port with
    # every written root isolated, so it never touches $Port or the portal.
    Invoke-ScriptGate -Name 'Request thread budget' -ScriptPath (Join-Path $WorkspaceRoot 'tests\Test-RequestThreadBudget.ps1') -ScriptArgs @('-Route', '/api/portfolio/assessment', '-MaxMs', '2000', '-FailOnError') -In host
}
else {
    Write-Host ''
    Write-Host '===== API host smoke =====' -ForegroundColor Cyan
    Write-Host '[SKIP] API host smoke (-SkipApiHost)' -ForegroundColor Yellow
    Write-Host '[SKIP] Request thread budget (-SkipApiHost; it boots a host)' -ForegroundColor Yellow
}

Invoke-ScriptGate -Name 'API contract'      -ScriptPath (Join-Path $scriptsDir 'Invoke-ApiContractTest.ps1')          -ScriptArgs $rootArgs -In host
Invoke-ScriptGate -Name 'Auth smoke'        -ScriptPath (Join-Path $scriptsDir 'Invoke-AuthSmokeTest.ps1')            -ScriptArgs $rootArgs -In host
Invoke-ScriptGate -Name 'Repo structure'    -ScriptPath (Join-Path $scriptsDir 'Invoke-RepositoryStructureAudit.ps1') -ScriptArgs $rootArgs -In static

Invoke-InProcessGate -Name 'doc-standards.json integrity' -In static -Action {
    $path = Join-Path $WorkspaceRoot 'backend/config/doc-standards.json'
    if (-not (Test-Path -LiteralPath $path)) { throw "doc-standards.json not found at $path" }
    $parsed = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $path -Raw -Encoding UTF8)
    if ($null -eq $parsed.requiredRootFiles) { throw 'doc-standards.json missing requiredRootFiles' }
    if ($null -eq $parsed.readmeStandards) { throw 'doc-standards.json missing readmeStandards' }
    Write-Host ("  doc-standards.json valid: {0} required file specs" -f @($parsed.requiredRootFiles).Count) -ForegroundColor DarkGray
}

Invoke-InProcessGate -Name 'roadmap standard assets integrity' -In static -Action {
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

# Release 3.6 milestone 1 -- the foundation domains are data. Adding a domain
# or a per-kind applicability rule is a JSON-only change, so this gate is what
# keeps that JSON honest: versioned, complete, and never scoring what the
# roadmap says is defined-only.
Invoke-InProcessGate -Name 'foundation-domains.json integrity (Release 3.6)' -In static -Action {
    $path = Join-Path $WorkspaceRoot 'backend/config/foundation-domains.json'
    if (-not (Test-Path -LiteralPath $path)) { throw "foundation-domains.json not found at $path" }
    $parsed = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $path -Raw -Encoding UTF8)
    if ([string]$parsed.schemaVersion -ne 'v1') { throw "foundation-domains.json schemaVersion must be 'v1', got '$($parsed.schemaVersion)'" }
    foreach ($key in @('principle', 'refinementRule', 'conclusions', 'domainStatuses', 'domains', 'kinds', 'kindDetection')) {
        if ($null -eq $parsed.$key) { throw "foundation-domains.json missing '$key'" }
    }
    foreach ($c in @('strengthen', 'appropriate-as-is', 'insufficiently-understood')) {
        if ($null -eq $parsed.conclusions.$c) { throw "foundation-domains.json conclusions missing '$c'" }
    }
    foreach ($s in @('present', 'weak', 'missing', 'not-applicable')) {
        if ($s -notin @($parsed.domainStatuses)) { throw "foundation-domains.json domainStatuses missing '$s'" }
    }
    if (@($parsed.domains).Count -lt 5) { throw "foundation-domains.json must carry the five starting-set domains, found $(@($parsed.domains).Count)" }
    foreach ($d in @($parsed.domains)) {
        foreach ($key in @('id', 'title', 'question')) {
            if ([string]::IsNullOrWhiteSpace([string]$d.$key)) { throw "foundation-domains.json domain missing '$key'" }
        }
        $isScored = if ($null -eq $d.PSObject.Properties['scored']) { $true } else { [bool]$d.scored }
        if ($isScored) {
            if ($null -eq $d.nextAction -or [string]::IsNullOrWhiteSpace([string]$d.nextAction.route)) { throw "scored domain '$($d.id)' names no next-action route; a strengthen verdict could not offer one" }
            # 3.7 M4c: a domain that routes by case names a kind and a route for every case.
            if ($null -ne $d.PSObject.Properties['actionsByCase']) {
                foreach ($c in @($d.actionsByCase.PSObject.Properties | Where-Object { $_.Name -ne 'note' })) {
                    if ([string]::IsNullOrWhiteSpace([string]$c.Value.kind) -or [string]::IsNullOrWhiteSpace([string]$c.Value.route)) { throw "domain '$($d.id)' actionsByCase '$($c.Name)' names no kind or no route" }
                }
            }
        } else {
            if ([string]$d.status -ne 'not-scored') { throw "unscored domain '$($d.id)' must declare status 'not-scored'" }
            if ($null -eq $d.evidenceModel -or @($d.evidenceModel.subAreas).Count -eq 0) { throw "unscored domain '$($d.id)' must define its evidence model (subAreas)" }
        }
    }
    $domainIds = @($parsed.domains | ForEach-Object { [string]$_.id })
    if (@($parsed.kinds).Count -lt 6) { throw "foundation-domains.json must carry the six repository kinds, found $(@($parsed.kinds).Count)" }
    foreach ($k in @($parsed.kinds)) {
        if ([string]::IsNullOrWhiteSpace([string]$k.id)) { throw 'foundation-domains.json kind missing id' }
        if ($null -eq $k.applicability) { throw "kind '$($k.id)' missing applicability (use {} when every domain applies)" }
        foreach ($p in $k.applicability.PSObject.Properties) {
            if ($p.Name -notin $domainIds) { throw "kind '$($k.id)' marks unknown domain '$($p.Name)' not-applicable" }
            if ([string]::IsNullOrWhiteSpace([string]$p.Value)) { throw "kind '$($k.id)' marks '$($p.Name)' not-applicable without a stated reason" }
        }
    }
    foreach ($r in @($parsed.kindDetection.rules)) {
        if ([string]$r.kind -notin @($parsed.kinds | ForEach-Object { [string]$_.id })) { throw "kindDetection rule names unknown kind '$($r.kind)'" }
        # foundation-conclusions v2 (3.7 M4a): a rule matches on `when` (field
        # equality), `whenAny` (a dotted path holds one of the listed values), or both.
        $hasWhen = $null -ne $r.PSObject.Properties['when'] -and $null -ne $r.when
        $hasWhenAny = $null -ne $r.PSObject.Properties['whenAny'] -and $null -ne $r.whenAny
        if (-not $hasWhen -and -not $hasWhenAny) { throw "kindDetection rule for '$($r.kind)' has neither 'when' nor 'whenAny'" }
    }
    Write-Host ("  foundation-domains.json valid: {0} domains ({1} scored), {2} kinds, {3} detection rule(s)" -f @($parsed.domains).Count, @($parsed.domains | Where-Object { $null -eq $_.PSObject.Properties['scored'] -or $_.scored }).Count, @($parsed.kinds).Count, @($parsed.kindDetection.rules).Count) -ForegroundColor DarkGray
}

Invoke-InProcessGate -Name 'Agent API OpenAPI spec (Release 2.4)' -In static -Action {
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

Invoke-InProcessGate -Name 'Roadmap contract spec directory (Release 2.3 Phase 4)' -In static -Action {
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

Invoke-InProcessGate -Name 'roadmap-audit-action package (Release 2.3 Phase 3)' -In static -Action {
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

# Release 3.7 M4a — the milestone's own check line, run where the roadmap says
# it runs: kind resolves from manifests, entry points and the README purpose line.
Invoke-ScriptGate -Name 'Kind detection' -ScriptPath (Join-Path $WorkspaceRoot 'tests\Test-KindDetection.ps1') -ScriptArgs @('-FailOnError') -In static
# Steering extension 3 — lifecycleState and conclusion may not disagree
# unexplained; the milestone's own check line, run where the roadmap says it runs.
Invoke-ScriptGate -Name 'Lifecycle consistency' -ScriptPath (Join-Path $WorkspaceRoot 'tests\Test-FoundationConclusions.ps1') -ScriptArgs @('-Cohort', 'evidence/trials/release-3.7/cohort.json', '-Assert', 'lifecycle-consistency', '-FailOnError') -In static
# 3.7 M4b - the milestone's own check line, run where the roadmap says it runs.
Invoke-ScriptGate -Name 'Applicability' -ScriptPath (Join-Path $WorkspaceRoot 'tests\Test-FoundationConclusions.ps1') -ScriptArgs @('-Cohort', 'evidence/trials/release-3.7/cohort.json', '-Assert', 'applicability', '-FailOnError') -In static
# 3.7 M4c - the milestone's own check line.
Invoke-ScriptGate -Name 'Action routing' -ScriptPath (Join-Path $WorkspaceRoot 'tests\Test-FoundationConclusions.ps1') -ScriptArgs @('-Cohort', 'evidence/trials/release-3.7/cohort.json', '-Assert', 'action-routing', '-FailOnError') -In static

# Lane 0.22, 2026-09-16 - the milestone's own check line. Every output\ path goes
# through the output root, every host-starting gate isolates it, and the smoke
# fixtures already in the operator's ledgers stay out of the operational views.
Invoke-ScriptGate -Name 'Fixture isolation' -ScriptPath (Join-Path $WorkspaceRoot 'tests\Test-FixtureIsolation.ps1') -ScriptArgs @('-FailOnError') -In static

# Release 4.0 phase A - the milestone's own check line. Today and the Dispatch
# Board read one server-side ranking, and the frontend they import sorts on none
# of its inputs.
Invoke-ScriptGate -Name 'One ranking' -ScriptPath (Join-Path $WorkspaceRoot 'tests\Test-OneRanking.ps1') -ScriptArgs @('-FailOnError') -In static

# Proof of value, 2026-10-16 - the delivery loop's write path and its ledger.
# The service can commit (identity), a failed commit leaves the clone clean, and
# decisions, PR outcomes and operator time are recorded and summed honestly.
Invoke-ScriptGate -Name 'Delivery loop' -ScriptPath (Join-Path $WorkspaceRoot 'tests\Test-DeliveryLoop.ps1') -ScriptArgs @('-FailOnError') -In module

# Loop step 7 - every decision carries its outcome, read from GitHub: the PR's
# head SHA at opening, the CI verdict per head, merged or closed unmerged, and
# when outcomes were last read. Only the refresh writes an outcome.
Invoke-ScriptGate -Name 'Delivery outcomes' -ScriptPath (Join-Path $WorkspaceRoot 'tests\Test-DeliveryOutcomes.ps1') -ScriptArgs @('-FailOnError') -In static

# Loop step 8: the delivery report. Every figure carries unit, basis, window
# and source; not measured is null with a reason, never 0; each report says
# what moved since the last, and the baseline sits beside the evaluation.
Invoke-ScriptGate -Name 'Delivery report' -ScriptPath (Join-Path $WorkspaceRoot 'tests\Test-DeliveryReport.ps1') -ScriptArgs @('-FailOnError')

# Loop steps 3 to 5: a finished run, once approved, pushes its branch and
# records the PR it opened (or the named reason it could not); a run whose
# runner pid no longer matches the heartbeat and whose process is gone is
# closed as abandoned with its reason instead of staying `running`.
Invoke-ScriptGate -Name 'Dispatch to PR' -ScriptPath (Join-Path $WorkspaceRoot 'tests\Test-DispatchToPr.ps1') -ScriptArgs @('-FailOnError')

# Lane 0.22 - one server-side dispatch-eligibility rule.
Invoke-ScriptGate -Name 'Dispatch eligibility' -ScriptPath (Join-Path $WorkspaceRoot 'tests\Test-DispatchEligibility.ps1') -ScriptArgs @('-FailOnError') -In static

# Lane 0.22, loop step 1 - only actionable roadmap lines are ranked, queued or
# dispatched; each exclusion carries its reason; an item is not launched twice
# inside the cooldown unless the operator overrides.
Invoke-ScriptGate -Name 'Work item quality' -ScriptPath (Join-Path $WorkspaceRoot 'tests\Test-WorkItemQuality.ps1') -ScriptArgs @('-FailOnError')

# Release 4.1, 2026-10-19 - the session briefing and the handoff issue. The
# briefing's parsers read this repository's own ROADMAP.md and operator queue,
# so a format change that would blind a fresh session fails here instead.
Invoke-ScriptGate -Name 'Session briefing' -ScriptPath (Join-Path $WorkspaceRoot 'tests\Test-SessionBriefing.ps1') -ScriptArgs @('-FailOnError') -In module

# Issues #339, #340, #342 (2026-10-19) - runner outcomes close agent runs and
# reach the metrics, and the trend seed carries every indexed repository.
Invoke-ScriptGate -Name 'Insights truth' -ScriptPath (Join-Path $WorkspaceRoot 'tests\Test-InsightsTruth.ps1') -ScriptArgs @('-FailOnError') -In static

# D-012 - a run whose branch touches a forbidden path (.github/workflows/** at
# least) fails by name in the runner and is never pushed.
Invoke-ScriptGate -Name 'Permission envelope' -ScriptPath (Join-Path $WorkspaceRoot 'tests\Test-PermissionEnvelope.ps1') -ScriptArgs @('-FailOnError') -In static

# D-012, the rest - a cloud agent's pull request is held to the same envelope
# before the host records it as delivered, a proposed workflow is reported as
# waiting for the owner, and network access needs an owner-approved allowlist.
Invoke-ScriptGate -Name 'Envelope cloud and network' -ScriptPath (Join-Path $WorkspaceRoot 'tests\Test-EnvelopeCloudAndNetwork.ps1') -ScriptArgs @('-FailOnError') -In static

# Validator R024 - a built or verified milestone's check is a step CI runs; the
# milestone's own check line. The rule itself also runs inside the lint below.
Invoke-ScriptGate -Name 'Check runs in CI' -ScriptPath (Join-Path $WorkspaceRoot 'tests\Test-RoadmapCheckRunsInCi.ps1') -ScriptArgs @('-FailOnError') -In static

Invoke-ScriptGate -Name 'Roadmap structure lint' -ScriptPath (Join-Path $toolsDir 'Test-RoadmapStructure.ps1') -ScriptArgs @('-Path', (Join-Path $WorkspaceRoot 'ROADMAP.md'), '-FailOnError') -In static

# Release 3.4, recorded 2026-08-15. PR #134 shipped a tested 306-line module and
# left all six of its release's milestones reading `planned`; the next agent to
# read the roadmap was one step from rebuilding it. This gate refuses a commit
# that claims a release, ships capability code, and does not advance a milestone.
# Verified non-vacuous by running it against 17dc1db, which it fails.
Invoke-ScriptGate -Name 'Roadmap capability record' -ScriptPath (Join-Path $toolsDir 'Test-RoadmapCapabilityRecord.ps1') -ScriptArgs @('-FailOnError') -In static

# ── Summary ────────────────────────────────────────────────────────────────
Write-Host ''
Write-Host '===== Test suite summary =====' -ForegroundColor White
foreach ($g in $gateResults) {
    Write-Host ("  {0} {1} ({2}s)" -f $(if ($g.Ok) { '[PASS]' } else { '[FAIL]' }), $g.Name, $g.Seconds) -ForegroundColor $(if ($g.Ok) { 'Green' } else { 'Red' })
}
$failed = @($gateResults | Where-Object { -not $_.Ok })
# A shard that ran no gates fails too: a CI job that runs nothing must not pass.
if ($failed.Count -gt 0 -or $gateResults.Count -eq 0) {
    Write-Host ("`nTEST SUITE FAILED — {0} gate(s) failed, {1} ran (shard: {2})." -f $failed.Count, $gateResults.Count, $Shard) -ForegroundColor Red
    exit 1
}
Write-Host "`nTEST SUITE PASSED — all $($gateResults.Count) gate(s) green (shard: $Shard)." -ForegroundColor Green
exit 0
