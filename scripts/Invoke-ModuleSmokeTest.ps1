[CmdletBinding()]
param(
    # Derived from this script's location rather than a hardcoded drive letter —
    # the previous 'G:\...' default no longer resolved on this machine, so the
    # gate failed on its first step for anyone not passing -WorkspaceRoot.
    [string]$WorkspaceRoot = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Step {
    param([string]$Message)
    Write-Host "[STEP] $Message" -ForegroundColor Cyan
}

$docInventory = Join-Path $WorkspaceRoot 'backend\modules\docreview\Invoke-DocReviewInventory.ps1'
$docQueue = Join-Path $WorkspaceRoot 'backend\modules\docreview\Build-DocReviewQueue.ps1'
$docBatch = Join-Path $WorkspaceRoot 'backend\modules\docreview\Invoke-DocReviewBatchPlan.ps1'
$reconcile = Join-Path $WorkspaceRoot 'backend\modules\reconcile\Invoke-Reconciliation.ps1'
$reconcileModular = Join-Path $WorkspaceRoot 'backend\modules\reconcile\Invoke-Reconciliation.Modular.ps1'
$reconcileTests = Join-Path $WorkspaceRoot 'backend\modules\reconcile\repo_reconciliation.Tests.ps1'
$roadmapParser = Join-Path $WorkspaceRoot 'backend\modules\roadmap\Roadmap.Parser.ps1'
$roadmapAuditor = Join-Path $WorkspaceRoot 'backend\modules\roadmap\Roadmap.Auditor.ps1'
$roadmapEvaluatorPath = Join-Path $WorkspaceRoot 'backend\modules\roadmap\Roadmap.Evaluator.ps1'
$roadmapRepairerPath = Join-Path $WorkspaceRoot 'backend\modules\roadmap\Roadmap.Repairer.ps1'
$roadmapPrSubmitterPath = Join-Path $WorkspaceRoot 'backend\modules\roadmap\Roadmap.PrSubmitter.ps1'
$docAuditScanner = Join-Path $WorkspaceRoot 'backend\modules\docaudit\DocAudit.Scanner.ps1'
$docStandards = Join-Path $WorkspaceRoot 'backend\config\doc-standards.json'
$agentBudgetModule = Join-Path $WorkspaceRoot 'backend\modules\agent-runs\BudgetLedger.ps1'

Write-Step 'Loading reconciliation module functions only'
& $reconcile -LoadFunctionsOnly
Write-Host 'Loaded reconciliation module successfully' -ForegroundColor Green

Write-Step 'Validating copied module files exist'
@($docInventory, $docQueue, $docBatch, $reconcile, $reconcileModular, $reconcileTests, $roadmapParser, $roadmapAuditor, $roadmapEvaluatorPath, $roadmapRepairerPath, $roadmapPrSubmitterPath, $docAuditScanner, $docStandards, $agentBudgetModule) | ForEach-Object {
    if (-not (Test-Path -LiteralPath $_)) {
        throw "Missing module file: $_"
    }
}
Write-Host 'All expected module files are present' -ForegroundColor Green

Write-Step 'API request deadline guard — bounds single-threaded host freezes'
$requestDeadlineModule = Join-Path $WorkspaceRoot 'backend\api-host\RequestDeadline.ps1'
if (-not (Test-Path -LiteralPath $requestDeadlineModule)) { throw "RequestDeadline.ps1 not found at: $requestDeadlineModule" }
. $requestDeadlineModule
if ((Get-EffectiveRequestTimeoutSeconds -ConfiguredSeconds 0) -ne 30) { throw 'Request timeout floor must remain 30 seconds' }
if ((Get-EffectiveRequestTimeoutSeconds -ConfiguredSeconds 180 -EnvironmentValue '45') -ne 45) { throw 'Request timeout env override was not applied' }
if ((Get-EffectiveRequestTimeoutSeconds -ConfiguredSeconds 180 -EnvironmentValue '99999') -ne 3600) { throw 'Request timeout ceiling must remain 3600 seconds' }
$deadlineNow = [datetime]::UtcNow
if ((Resolve-RequestDeadlineAction -Armed:$false -DeadlineUtc $deadlineNow -NowUtc $deadlineNow) -ne 'idle') { throw 'Disarmed request deadline must be idle' }
if ((Resolve-RequestDeadlineAction -Armed:$true -DeadlineUtc $deadlineNow.AddSeconds(1) -NowUtc $deadlineNow) -ne 'wait') { throw 'Future request deadline must wait' }
if ((Resolve-RequestDeadlineAction -Armed:$true -DeadlineUtc $deadlineNow -NowUtc $deadlineNow) -ne 'terminate') { throw 'Expired request deadline must terminate' }
Write-Host '  deadline floor/override/ceiling and idle/wait/terminate states correct' -ForegroundColor DarkGray

# A cold full-portfolio scan legitimately outruns the 180s default. Without the
# extended tier the freeze guard terminates the host mid-scan and Shawl restarts
# it into the same scan — the guard becoming the outage it exists to prevent.
foreach ($scanPath in @('/api/portfolio/assessment', '/api/operations/repos', '/api/operations/repos/foo/curation', '/api/automation/run', '/api/badges/foo.svg')) {
    if (-not (Test-LongRunningScanRoute -Path $scanPath)) { throw "Scan route must use the extended deadline tier: $scanPath" }
}
foreach ($fastPath in @('/api/status', '/health/live', '/api/automation/history', '/api/settings', '')) {
    if (Test-LongRunningScanRoute -Path $fastPath) { throw "Ordinary route must keep the default deadline: '$fastPath'" }
}
if (-not (Test-LongRunningScanRoute -Path '/api/operations/repos/')) { throw 'Trailing-slash scan route must still match the extended tier' }
if ((Get-RequestDeadlineSecondsForPath -Path '/api/automation/run' -DefaultSeconds 180 -ScanSeconds 900) -ne 900) { throw 'Scan route did not receive the extended deadline' }
if ((Get-RequestDeadlineSecondsForPath -Path '/api/status' -DefaultSeconds 180 -ScanSeconds 900) -ne 180) { throw 'Ordinary route did not receive the default deadline' }
if ((Get-EffectiveScanRequestTimeoutSeconds -ConfiguredSeconds 900 -BaseSeconds 180) -ne 900) { throw 'Scan deadline default must be 900 seconds' }
if ((Get-EffectiveScanRequestTimeoutSeconds -ConfiguredSeconds 300 -BaseSeconds 1200) -ne 1200) { throw 'Scan deadline must never fall below the default tier it extends' }
if ((Get-EffectiveScanRequestTimeoutSeconds -ConfiguredSeconds 900 -EnvironmentValue '99999' -BaseSeconds 180) -ne 3600) { throw 'Scan deadline must stay clamped to the 3600-second ceiling' }
Write-Host '  scan routes get the extended (still bounded) deadline tier; ordinary routes do not' -ForegroundColor DarkGray

Write-Step 'No machine-specific path defaults in tracked PowerShell (ROADMAP Lane 0.3)'
# A hardcoded 'G:\...' parameter default is invisible until someone runs the
# suite from a different clone, at which point it either fails on step one or —
# worse — silently scans a drive that does not exist and reports "no repos"
# instead of "misconfigured". Both happened. Test files are exempt: they use
# G:\ strings as synthetic fixture paths that are never touched on disk.
$pathDefaultOffenders = @()
foreach ($candidate in @(Get-ChildItem -Path (Join-Path $WorkspaceRoot 'backend'), (Join-Path $WorkspaceRoot 'scripts'), (Join-Path $WorkspaceRoot 'tools') -Filter '*.ps1' -Recurse -ErrorAction SilentlyContinue)) {
    if ($candidate.Name -like '*.Tests.ps1') { continue }
    $offending = @(Select-String -LiteralPath $candidate.FullName -Pattern '^\s*\[string(\[\])?\]\$\w+\s*=\s*[''"][A-Za-z]:\\' -ErrorAction SilentlyContinue)
    foreach ($hit in $offending) {
        $pathDefaultOffenders += ('{0}:{1}' -f $candidate.FullName.Substring($WorkspaceRoot.Length + 1), $hit.LineNumber)
    }
}
if ($pathDefaultOffenders.Count -gt 0) {
    throw ("Hardcoded absolute-path parameter defaults found (derive from `$PSScriptRoot, or require the parameter): " + ($pathDefaultOffenders -join ', '))
}
Write-Host ('  no absolute-path parameter defaults in tracked backend/scripts/tools PowerShell') -ForegroundColor DarkGray

# Cache-off was the trigger for the 2026-07-05 request pile-up. Preserve an
# explicit source-level tripwire because these helpers live inside the host
# script and cannot be dot-sourced without starting the listener.
$apiHostSource = Get-Content -LiteralPath (Join-Path $WorkspaceRoot 'backend\api-host\Start-RepoManagementApiHost.ps1') -Raw -Encoding UTF8
if ($apiHostSource -notmatch '(?s)function Get-StatusCacheTtlSeconds.*?if \(\$candidate -gt 0\)') { throw 'Status cache TTL can be disabled; require a positive override' }
if ($apiHostSource -notmatch '(?s)function Get-PortfolioAssessmentCacheTtlSeconds.*?if \(\$candidate -gt 0\)') { throw 'Portfolio assessment cache TTL can be disabled; require a positive override' }
Write-Host '  status and assessment caches reject zero/negative TTL overrides' -ForegroundColor DarkGray

# Tripwire for ROADMAP Lane 0.1. Commit 69dcc2d shipped a smoke-run mutation as
# the real workspace root: tracked settings.json pointed inventory.localRoots at
# a fixture directory under output/, so every scan, assessment, and scheduled
# automation run from a clean checkout enumerated fixtures instead of the
# portfolio — and nothing failed to say so. The api-host smoke now restores the
# file byte-exact, but this fails the suite outright if a mutation ever lands
# again, because the symptom (zero repositories, no error) is indistinguishable
# from an empty workspace.
Write-Step 'Config tripwire: tracked settings.json must not point at run output'
$trackedSettingsPath = Join-Path $WorkspaceRoot 'backend\config\settings.json'
if (Test-Path -LiteralPath $trackedSettingsPath) {
    $trackedSettings = Get-Content -LiteralPath $trackedSettingsPath -Raw | ConvertFrom-Json
    $trackedRoots = @()
    if ($trackedSettings.PSObject.Properties.Name -contains 'inventory' -and
        $trackedSettings.inventory.PSObject.Properties.Name -contains 'localRoots') {
        $trackedRoots = @($trackedSettings.inventory.localRoots | ForEach-Object { [string]$_ })
    }
    $offending = @($trackedRoots | Where-Object { $_ -match '(^|[/\\])output([/\\]|$)' })
    if (@($offending).Count -gt 0) {
        # Parenthesise the concatenation before -f: otherwise the format operator
        # binds to the trailing string only and {0} is emitted literally.
        throw (("Tracked settings.json inventory.localRoots names a path under output/: {0}. " +
                "That is run evidence, not a workspace — restore the real root before committing.") -f ($offending -join ', '))
    }
    if (@($trackedRoots).Count -eq 0) {
        throw 'Tracked settings.json has no inventory.localRoots; the portal cannot scan anything.'
    }

    # Also check the COMMITTED version, not just the working copy. On 2026-08-09
    # a commit was made while the api-host smoke held settings.json pointed at
    # its fixture, so the fixture path landed on main — and this tripwire stayed
    # green afterwards because the smoke's finally had since restored the
    # working copy. Checking only what is on disk cannot see pollution that is
    # already in history.
    $committedSettings = $null
    try { $committedSettings = (& git -C $WorkspaceRoot show HEAD:backend/config/settings.json 2>$null) | Out-String } catch { }
    if (-not [string]::IsNullOrWhiteSpace($committedSettings)) {
        $committedRoots = @()
        try {
            $committedJson = $committedSettings | ConvertFrom-Json
            if ($committedJson.PSObject.Properties.Name -contains 'inventory' -and
                $committedJson.inventory.PSObject.Properties.Name -contains 'localRoots') {
                $committedRoots = @($committedJson.inventory.localRoots | ForEach-Object { [string]$_ })
            }
        } catch { }
        $committedOffending = @($committedRoots | Where-Object { $_ -match '(^|[/\\])output([/\\]|$)' })
        if (@($committedOffending).Count -gt 0) {
            throw (("COMMITTED settings.json inventory.localRoots names a path under output/: {0}. " +
                    "Run evidence was committed as config — restore the real root and commit the fix.") -f ($committedOffending -join ', '))
        }
    }
    Write-Host ("  localRoots ok (working copy and HEAD): {0}" -f ($trackedRoots -join ', ')) -ForegroundColor Green
}

Write-Step 'Loading roadmap parser module'
. $roadmapParser
Write-Host 'Roadmap parser module loaded successfully' -ForegroundColor Green

Write-Step 'Roadmap parser — smoke: pending roadmap'
$pendingResult = Invoke-ParseRoadmapContent -Content "## Now`n- [ ] First task`n- [x] Done task`n## Next`n- [ ] Another task"
if ($pendingResult.roadmapState -ne 'pending') { throw "Expected state=pending, got $($pendingResult.roadmapState)" }
if ($pendingResult.pendingCount -ne 2)          { throw "Expected pendingCount=2, got $($pendingResult.pendingCount)" }
if ($pendingResult.completedCount -ne 1)        { throw "Expected completedCount=1, got $($pendingResult.completedCount)" }
if ($pendingResult.nextPendingItem.text -ne 'First task') { throw "Expected nextPendingItem.text='First task', got '$($pendingResult.nextPendingItem.text)'" }
if ($pendingResult.nextPendingItem.section -ne 'Now') { throw "Expected nextPendingItem.section='Now', got '$($pendingResult.nextPendingItem.section)'" }
Write-Host '  pending roadmap parsed correctly' -ForegroundColor DarkGray

Write-Step 'Roadmap parser — smoke: complete roadmap'
$completeResult = Invoke-ParseRoadmapContent -Content "## Done`n- [x] Item one`n- [X] Item two"
if ($completeResult.roadmapState -ne 'complete')  { throw "Expected state=complete, got $($completeResult.roadmapState)" }
if ($completeResult.pendingCount -ne 0)            { throw "Expected pendingCount=0, got $($completeResult.pendingCount)" }
if ($completeResult.nextPendingItem -ne $null)     { throw "Expected nextPendingItem=null for complete roadmap" }
Write-Host '  complete roadmap parsed correctly' -ForegroundColor DarkGray

Write-Step 'Roadmap parser — smoke: parse-error (no checkboxes)'
$errorResult = Invoke-ParseRoadmapContent -Content "# ROADMAP`nThis roadmap has no checkboxes."
if ($errorResult.roadmapState -ne 'parse-error') { throw "Expected state=parse-error, got $($errorResult.roadmapState)" }
Write-Host '  parse-error roadmap classified correctly' -ForegroundColor DarkGray

Write-Step 'Roadmap parser — smoke: parse-error (empty content)'
$emptyResult = Invoke-ParseRoadmapContent -Content ''
if ($emptyResult.roadmapState -ne 'parse-error') { throw "Expected state=parse-error for empty content, got $($emptyResult.roadmapState)" }
Write-Host '  empty content classified as parse-error correctly' -ForegroundColor DarkGray

Write-Step 'Roadmap parser — smoke: live ROADMAP.md in workspace'
$liveRoadmap = Join-Path $WorkspaceRoot 'ROADMAP.md'
if (Test-Path -LiteralPath $liveRoadmap) {
    $liveContent = Get-Content -LiteralPath $liveRoadmap -Raw -Encoding UTF8
    $liveResult = Invoke-ParseRoadmapContent -Content $liveContent -SourcePath $liveRoadmap
    if ($liveResult.roadmapState -notin @('pending', 'complete', 'parse-error')) {
        throw "Live ROADMAP.md returned unexpected state: $($liveResult.roadmapState)"
    }
    Write-Host ("  live ROADMAP.md state={0} pending={1} completed={2}" -f $liveResult.roadmapState, $liveResult.pendingCount, $liveResult.completedCount) -ForegroundColor DarkGray
} else {
    Write-Host '  (ROADMAP.md not found at workspace root — live parse skipped)' -ForegroundColor Yellow
}

Write-Step 'Roadmap parser — smoke: phase-plan and budget-guardrail annotations'
$annotatedRoadmap = @"
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
- At each phase closure record the raw observations only.
"@
$annotatedResult = Invoke-ParseRoadmapContent -Content $annotatedRoadmap
if ($annotatedResult.roadmapState -ne 'pending') { throw "Expected annotated roadmap state=pending, got '$($annotatedResult.roadmapState)'" }
if ($null -eq $annotatedResult.activeRelease) { throw 'Expected activeRelease for annotated roadmap' }
if ($null -eq $annotatedResult.activePhasePlan) { throw 'Expected activePhasePlan for annotated roadmap' }
if ([string]$annotatedResult.activePhasePlan.phaseName -ne 'Phase 2: Quota guard') { throw "Expected activePhasePlan='Phase 2: Quota guard', got '$($annotatedResult.activePhasePlan.phaseName)'" }
if ([double]$annotatedResult.activePhasePlan.workUnitsEstimated -ne 8) { throw "Expected activePhasePlan.workUnitsEstimated=8, got '$($annotatedResult.activePhasePlan.workUnitsEstimated)'" }
if ($null -eq $annotatedResult.budgetGuardrail) { throw 'Expected budgetGuardrail metadata for annotated roadmap' }
if ([double]$annotatedResult.budgetGuardrail.estimatedReleaseWorkUnits -ne 18) { throw "Expected estimatedReleaseWorkUnits=18, got '$($annotatedResult.budgetGuardrail.estimatedReleaseWorkUnits)'" }
if ([double]$annotatedResult.budgetGuardrail.maxUnitsPerPhase -ne 10) { throw "Expected maxUnitsPerPhase=10, got '$($annotatedResult.budgetGuardrail.maxUnitsPerPhase)'" }
Write-Host '  phase-plan and budget-guardrail annotations parsed correctly' -ForegroundColor DarkGray

Write-Step 'Loading doc audit scanner module'
. $docAuditScanner
Write-Host 'Doc audit scanner module loaded successfully' -ForegroundColor Green

Write-Step 'Doc audit scanner — smoke: loads doc-standards.json'
$standards = Get-DocStandards -StandardsPath $docStandards
if ($null -eq $standards) { throw "Get-DocStandards returned null for existing doc-standards.json" }
if ($null -eq $standards.requiredRootFiles) { throw "doc-standards.json missing requiredRootFiles" }
Write-Host ("  doc-standards.json loaded: {0} required file specs" -f @($standards.requiredRootFiles).Count) -ForegroundColor DarkGray

Write-Step 'Doc audit scanner — smoke: ready repo (has README + pending roadmap)'
$tmpReadyDir = Join-Path ([System.IO.Path]::GetTempPath()) ('docaudit-smoke-ready-' + [guid]::NewGuid().ToString('n').Substring(0, 8))
$null = New-Item -ItemType Directory -Path $tmpReadyDir -Force
$null = New-Item -ItemType Directory -Path (Join-Path $tmpReadyDir '.git') -Force
$readmeContent = @"
# Sample Project

A sample project with all required sections to satisfy doc standards.

$('A' * 300)

## Installation

Run the setup script.

## Usage

Run the start command.

## Contributing

See CONTRIBUTING.md.
"@
Set-Content -LiteralPath (Join-Path $tmpReadyDir 'README.md') -Value $readmeContent -Encoding UTF8
Set-Content -LiteralPath (Join-Path $tmpReadyDir 'LICENSE') -Value 'MIT License' -Encoding UTF8
try {
    $readyResult = Invoke-AuditRepoDocumentation -RepoPath $tmpReadyDir -RepoName 'smoke-ready' -Standards $standards -RoadmapState 'pending' -NextPendingRoadmapItem 'First task'
    if ($readyResult.dispatchReadiness -ne 'ready') { throw "Expected dispatchReadiness=ready, got $($readyResult.dispatchReadiness)" }
    if ($readyResult.readyForDispatch -ne $true) { throw "Expected readyForDispatch=true" }
    Write-Host '  ready repo classified correctly' -ForegroundColor DarkGray
} finally {
    Remove-Item -LiteralPath $tmpReadyDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Step 'Doc audit scanner — smoke: blocked repo (missing README)'
$tmpBlockedDir = Join-Path ([System.IO.Path]::GetTempPath()) ('docaudit-smoke-blocked-' + [guid]::NewGuid().ToString('n').Substring(0, 8))
$null = New-Item -ItemType Directory -Path $tmpBlockedDir -Force
$null = New-Item -ItemType Directory -Path (Join-Path $tmpBlockedDir '.git') -Force
try {
    $blockedResult = Invoke-AuditRepoDocumentation -RepoPath $tmpBlockedDir -RepoName 'smoke-blocked' -Standards $standards -RoadmapState 'pending'
    if ($blockedResult.dispatchReadiness -ne 'blocked') { throw "Expected dispatchReadiness=blocked, got $($blockedResult.dispatchReadiness)" }
    if ($blockedResult.criticalCount -lt 1) { throw "Expected at least 1 critical finding for missing README" }
    Write-Host '  blocked repo classified correctly' -ForegroundColor DarkGray
} finally {
    Remove-Item -LiteralPath $tmpBlockedDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Step 'Doc audit scanner — smoke: needs-doc-standardization (short README + pending roadmap)'
$tmpNeedsDir = Join-Path ([System.IO.Path]::GetTempPath()) ('docaudit-smoke-needs-' + [guid]::NewGuid().ToString('n').Substring(0, 8))
$null = New-Item -ItemType Directory -Path $tmpNeedsDir -Force
$null = New-Item -ItemType Directory -Path (Join-Path $tmpNeedsDir '.git') -Force
Set-Content -LiteralPath (Join-Path $tmpNeedsDir 'README.md') -Value 'Short README' -Encoding UTF8
try {
    $needsResult = Invoke-AuditRepoDocumentation -RepoPath $tmpNeedsDir -RepoName 'smoke-needs' -Standards $standards -RoadmapState 'pending'
    if ($needsResult.dispatchReadiness -ne 'needs-doc-standardization') { throw "Expected dispatchReadiness=needs-doc-standardization, got $($needsResult.dispatchReadiness)" }
    Write-Host '  needs-doc-standardization classified correctly' -ForegroundColor DarkGray
} finally {
    Remove-Item -LiteralPath $tmpNeedsDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Step 'Doc audit scanner — smoke: missing-roadmap'
$tmpMissingDir = Join-Path ([System.IO.Path]::GetTempPath()) ('docaudit-smoke-missing-' + [guid]::NewGuid().ToString('n').Substring(0, 8))
$null = New-Item -ItemType Directory -Path $tmpMissingDir -Force
$null = New-Item -ItemType Directory -Path (Join-Path $tmpMissingDir '.git') -Force
$readmeContent2 = "# Project`n`n" + ('B' * 400)
Set-Content -LiteralPath (Join-Path $tmpMissingDir 'README.md') -Value $readmeContent2 -Encoding UTF8
try {
    $missingResult = Invoke-AuditRepoDocumentation -RepoPath $tmpMissingDir -RepoName 'smoke-missing' -Standards $standards -RoadmapState 'missing'
    if ($missingResult.dispatchReadiness -ne 'missing-roadmap') { throw "Expected dispatchReadiness=missing-roadmap, got $($missingResult.dispatchReadiness)" }
    Write-Host '  missing-roadmap classified correctly' -ForegroundColor DarkGray
} finally {
    Remove-Item -LiteralPath $tmpMissingDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Step 'Doc audit scanner — smoke: Invoke-AuditRepoScan on workspace root'
$scanResults = Invoke-AuditRepoScan -LocalRoots @($WorkspaceRoot) -MaxDepth 1 -Standards $standards
if ($null -eq $scanResults) { throw "Invoke-AuditRepoScan returned null" }
Write-Host ("  workspace root audit found {0} repos" -f @($scanResults).Count) -ForegroundColor DarkGray
foreach ($r in @($scanResults)) {
    if ($r.dispatchReadiness -notin @('ready', 'needs-doc-standardization', 'missing-roadmap', 'roadmap-complete', 'parse-error', 'blocked')) {
        throw "Unexpected dispatchReadiness value: $($r.dispatchReadiness) for repo $($r.repoName)"
    }
}
Write-Host '  all scanned repos have valid dispatchReadiness values' -ForegroundColor DarkGray

Write-Step 'Doc audit scanner — smoke: cached roadmap entries as JSON objects'
$tmpScanRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('docaudit-smoke-cache-' + [guid]::NewGuid().ToString('n').Substring(0, 8))
$tmpCachedRepo = Join-Path $tmpScanRoot 'cached-roadmap-repo'
$null = New-Item -ItemType Directory -Path (Join-Path $tmpCachedRepo '.git') -Force
$cachedReadme = "# Cached Roadmap Repo`n`n" + ('C' * 400)
Set-Content -LiteralPath (Join-Path $tmpCachedRepo 'README.md') -Value $cachedReadme -Encoding UTF8
$cachedRoadmapJson = @"
[
  {
    "repoName": "cached-roadmap-repo",
    "repoPath": "$($tmpCachedRepo.Replace('\', '\\'))",
    "roadmapState": "pending",
    "nextPendingItem": {
      "text": "Add cached roadmap support"
    }
  }
]
"@
$cachedRoadmapEntries = @($cachedRoadmapJson | ConvertFrom-Json)
try {
    $cachedScanResults = Invoke-AuditRepoScan -LocalRoots @($tmpScanRoot) -MaxDepth 2 -RoadmapEntries $cachedRoadmapEntries -Standards $standards
    if (@($cachedScanResults).Count -ne 1) { throw "Expected 1 repo from cached roadmap scan, got $(@($cachedScanResults).Count)" }
    $cachedResult = @($cachedScanResults)[0]
    if ($cachedResult.roadmapState -ne 'pending') { throw "Expected roadmapState=pending, got $($cachedResult.roadmapState)" }
    if ($cachedResult.nextPendingRoadmapItem -ne 'Add cached roadmap support') { throw "Expected cached next pending item, got $($cachedResult.nextPendingRoadmapItem)" }
    Write-Host '  cached roadmap entries classified correctly' -ForegroundColor DarkGray
} finally {
    Remove-Item -LiteralPath $tmpScanRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Step 'Roadmap parser — smoke: section-order neighboring context extraction'
$neighborContent = @"
## Now
- [ ] First task
- [ ] Second task
## Next
- [ ] Third task
- [x] Already done
"@
$neighborResult = Invoke-ParseRoadmapContent -Content $neighborContent
if ($neighborResult.roadmapState -ne 'pending') { throw "Expected state=pending for neighboring context test, got $($neighborResult.roadmapState)" }
if ($neighborResult.nextPendingItem.text -ne 'First task') { throw "Expected nextPendingItem='First task', got '$($neighborResult.nextPendingItem.text)'" }
# Validate section ordering is preserved in sections array
$sectionNames = @($neighborResult.sections | ForEach-Object { $_.name })
if ($sectionNames[0] -ne 'Now') { throw "Expected first section name='Now', got '$($sectionNames[0])'" }
if ($sectionNames[1] -ne 'Next') { throw "Expected second section name='Next', got '$($sectionNames[1])'" }
$nowSection = $neighborResult.sections | Where-Object { $_.name -eq 'Now' } | Select-Object -First 1
if (@($nowSection.pendingItems).Count -ne 2) { throw "Expected 2 pending items in 'Now' section, got $(@($nowSection.pendingItems).Count)" }
Write-Host '  neighboring context section ordering verified' -ForegroundColor DarkGray

Write-Step 'Loading roadmap auditor module (Release 0.8)'
$roadmapAuditor = Join-Path $WorkspaceRoot 'backend\modules\roadmap\Roadmap.Auditor.ps1'
if (-not (Test-Path -LiteralPath $roadmapAuditor)) { throw "Roadmap.Auditor.ps1 not found at: $roadmapAuditor" }
. $roadmapAuditor
Write-Host 'Roadmap auditor module loaded successfully' -ForegroundColor Green

Write-Step 'Roadmap auditor — smoke: normalize missing roadmap'
$missingContract = Invoke-NormalizeRoadmapContract -ParsedResult $null -RepoName 'smoke-missing-repo'
if ($missingContract.roadmapState -ne 'missing')   { throw "Expected roadmapState=missing for null ParsedResult, got $($missingContract.roadmapState)" }
if ($missingContract.maturityLevel -ne 'L0-Absent') { throw "Expected maturityLevel=L0-Absent for missing roadmap, got $($missingContract.maturityLevel)" }
Write-Host '  missing roadmap normalized to L0-Absent' -ForegroundColor DarkGray

Write-Step 'Roadmap auditor — smoke: normalize pending roadmap'
$pendingContent = @"
# Product Intent

This product does something.

## Release 1.0 — First Release

### Acceptance criteria

- The feature works.

### Out of scope

- Not this.

- [ ] Implement feature A
- [ ] Implement feature B
- [ ] Implement feature C
- [x] Done already
"@
$pendingParsed   = Invoke-ParseRoadmapContent -Content $pendingContent
$pendingContract = Invoke-NormalizeRoadmapContract -ParsedResult $pendingParsed -RawContent $pendingContent -RepoName 'smoke-pending-repo'
if ($pendingContract.roadmapState -ne 'pending')     { throw "Expected roadmapState=pending, got $($pendingContract.roadmapState)" }
if ($pendingContract.pendingCount -ne 3)             { throw "Expected pendingCount=3, got $($pendingContract.pendingCount)" }
if ($pendingContract.hasProductIntent -ne $true)     { throw "Expected hasProductIntent=true" }
if ($pendingContract.hasReleaseSections -ne $true)   { throw "Expected hasReleaseSections=true" }
if ($pendingContract.hasAcceptanceCriteria -ne $true) { throw "Expected hasAcceptanceCriteria=true" }
if ($pendingContract.hasOutOfScope -ne $true)        { throw "Expected hasOutOfScope=true" }
Write-Host '  pending roadmap normalized with structure flags detected' -ForegroundColor DarkGray

Write-Step 'Roadmap auditor — smoke: audit scoring and maturity level assignment'
$roadmapAuditRulesRaw  = Get-Content -LiteralPath (Join-Path $WorkspaceRoot 'standards\roadmap\roadmap-audit-rules.json') -Raw -Encoding UTF8
$roadmapAuditRulesParsed = ConvertFrom-Json -InputObject $roadmapAuditRulesRaw
$auditRulesObj = [pscustomobject]@{
    rules             = @($roadmapAuditRulesParsed.rules)
    maturityThresholds = $roadmapAuditRulesParsed.maturityThresholds
}
# Score the well-formed pending contract
$scoredContract = Invoke-AuditRoadmapContract -Contract $pendingContract -AuditRules $auditRulesObj
if ($scoredContract.maturityScore -lt 0 -or $scoredContract.maturityScore -gt 100) {
    throw "Maturity score out of range 0-100: $($scoredContract.maturityScore)"
}
if ($scoredContract.maturityLevel -notin @('L0-Absent','L1-Informal','L2-Structured','L3-Contract-Ready','L4-Orchestration-Ready')) {
    throw "Unexpected maturityLevel: $($scoredContract.maturityLevel)"
}
# A well-formed roadmap with all structural flags should score at least L3
if ($scoredContract.maturityLevel -notin @('L3-Contract-Ready','L4-Orchestration-Ready')) {
    Write-Host ("  NOTE: full-featured roadmap scored $($scoredContract.maturityScore) -> $($scoredContract.maturityLevel) (may be below L3 if vague items detected)") -ForegroundColor Yellow
} else {
    Write-Host ("  full-featured roadmap scored $($scoredContract.maturityScore) -> $($scoredContract.maturityLevel)") -ForegroundColor DarkGray
}
# Score a completely missing roadmap — must be L0
$missingScored = Invoke-AuditRoadmapContract -Contract $missingContract -AuditRules $auditRulesObj
if ($missingScored.maturityLevel -ne 'L0-Absent') { throw "Expected L0-Absent for missing roadmap after audit, got $($missingScored.maturityLevel)" }
if ($missingScored.maturityScore -ne 0)           { throw "Expected maturityScore=0 for missing roadmap, got $($missingScored.maturityScore)" }
Write-Host '  missing roadmap correctly scored as L0-Absent with score=0' -ForegroundColor DarkGray

Write-Step 'Roadmap auditor — smoke: audit findings contain expected rule IDs'
if ($null -eq $scoredContract.auditFindings) { throw "auditFindings should not be null after audit" }
# A well-structured roadmap should not have critical findings
$criticalFindings = @($scoredContract.auditFindings | Where-Object { $_.severity -eq 'critical' })
if ($criticalFindings.Count -gt 0) {
    throw "Well-formed roadmap should have no critical findings, got: $(($criticalFindings | ForEach-Object { $_.ruleId }) -join ', ')"
}
Write-Host ("  audit findings: {0} total, 0 critical" -f @($scoredContract.auditFindings).Count) -ForegroundColor DarkGray

Write-Step 'Roadmap auditor — smoke: active-release rules ROADMAP-011/012 gate dispatch (rules v1.1)'
# A structurally complete roadmap that declares no active release must fire
# ROADMAP-012, and one declaring two must fire ROADMAP-011 and be capped at L2 —
# an ambiguous dispatch target is not dispatchable.
$activeReleaseFixture = @'
# Sample Project Roadmap

Product intent: this product helps operators ship reliably.

## Release 1.0 - First Release

**Status:** {0}

Goal: ship the first thing.

### Acceptance criteria

- The first thing ships and is verified by an automated test.

### Out of scope

- Anything not named above.

- [ ] Implement the first documented behavior
- [ ] Implement the second documented behavior
- [ ] Implement the third documented behavior

## Release 1.1 - Second Release

**Status:** {1}

Goal: ship the second thing.

### Acceptance criteria

- The second thing ships and is verified by an automated test.

### Out of scope

- Anything not named above.

- [ ] Implement the fourth documented behavior
- [ ] Implement the fifth documented behavior
- [ ] Implement the sixth documented behavior
'@

function Get-SmokeActiveReleaseAudit {
    param([string]$StatusOne, [string]$StatusTwo)
    $content = $activeReleaseFixture -f $StatusOne, $StatusTwo
    $parsed = Invoke-ParseRoadmapContent -Content $content -SourcePath 'ROADMAP.md'
    $contract = Invoke-NormalizeRoadmapContract -ParsedResult $parsed -RawContent $content -RepoName 'smoke-active-release'
    return (Invoke-AuditRoadmapContract -Contract $contract -AuditRules $auditRulesObj)
}

$noActiveAudit = Get-SmokeActiveReleaseAudit -StatusOne 'planned' -StatusTwo 'planned'
if ([int]$noActiveAudit.activeReleaseCount -ne 0) { throw "Expected activeReleaseCount=0, got $($noActiveAudit.activeReleaseCount)" }
if (@($noActiveAudit.auditFindings | Where-Object { $_.ruleId -eq 'ROADMAP-012' }).Count -ne 1) {
    throw 'Expected ROADMAP-012 to fire when releases exist but none is active'
}

$oneActiveAudit = Get-SmokeActiveReleaseAudit -StatusOne 'active' -StatusTwo 'planned'
if ([int]$oneActiveAudit.activeReleaseCount -ne 1) { throw "Expected activeReleaseCount=1, got $($oneActiveAudit.activeReleaseCount)" }
if (@($oneActiveAudit.auditFindings | Where-Object { $_.ruleId -in @('ROADMAP-011','ROADMAP-012') }).Count -ne 0) {
    throw 'Expected neither ROADMAP-011 nor ROADMAP-012 to fire for exactly one active release'
}

# 'In Progress' must normalize to active, per the rules v1.1 changelog.
$twoActiveAudit = Get-SmokeActiveReleaseAudit -StatusOne 'active' -StatusTwo 'In Progress'
if ([int]$twoActiveAudit.activeReleaseCount -ne 2) { throw "Expected activeReleaseCount=2 (alias 'In Progress' -> active), got $($twoActiveAudit.activeReleaseCount)" }
if (@($twoActiveAudit.auditFindings | Where-Object { $_.ruleId -eq 'ROADMAP-011' }).Count -ne 1) {
    throw 'Expected ROADMAP-011 to fire when more than one release is active'
}
if ($twoActiveAudit.maturityLevel -ne 'L2-Structured') {
    throw "More than one active release must cap maturity at exactly L2-Structured, got $($twoActiveAudit.maturityScore) -> $($twoActiveAudit.maturityLevel)"
}
# ROADMAP-011 must stay a WARNING. As a critical it would take the blanket L1
# cap, making its own documented L2 cap unreachable and silently downgrading
# every ambiguous-dispatch repo in the portfolio a level below the model.
$rule011 = @($auditRulesObj.rules | Where-Object { $_.id -eq 'ROADMAP-011' })[0]
if ([string]$rule011.severity -ne 'warning') {
    throw "ROADMAP-011 must be severity 'warning' so its named L2 cap stays reachable (see ROADMAP_MATURITY_MODEL.md); got '$($rule011.severity)'"
}
Write-Host ("  active-release rules ok: 0 active -> ROADMAP-012; 1 active -> clean; 2 active -> ROADMAP-011 (warning) + capped at {0}" -f $twoActiveAudit.maturityLevel) -ForegroundColor DarkGray

# The two blanket maturity caps ROADMAP_MATURITY_MODEL.md documented from the
# start but no evaluator applied until rules v1.5: weighted-score arithmetic
# alone let a roadmap carry a critical finding and still score
# orchestration-ready.
Write-Step 'Roadmap auditor — smoke: blanket maturity caps (critical -> L1, warning -> L3)'
$capThresholds = $auditRulesObj.maturityThresholds
$l1Max = [int]$capThresholds.'L1-Informal'.maxScore
$l3Max = [int]$capThresholds.'L3-Contract-Ready'.maxScore

# Same well-formed roadmap that scores L3+, but flipped to parse-error, which is
# critical -> must cap at L1 no matter how much structure is otherwise present.
$criticalContract = Invoke-NormalizeRoadmapContract `
    -ParsedResult (Invoke-ParseRoadmapContent -Content $pendingContent) `
    -RawContent $pendingContent -RepoName 'smoke-critical-cap'
$criticalContract.roadmapState = 'parse-error'
$criticalAudit = Invoke-AuditRoadmapContract -Contract $criticalContract -AuditRules $auditRulesObj
if (@($criticalAudit.auditFindings | Where-Object { $_.severity -eq 'critical' }).Count -lt 1) {
    throw 'Fixture error: expected at least one critical finding for the critical-cap case'
}
if ([int]$criticalAudit.maturityScore -gt $l1Max) {
    throw "Any critical finding must cap maturity at L1 (<= $l1Max), got $($criticalAudit.maturityScore) -> $($criticalAudit.maturityLevel)"
}
if ($criticalAudit.maturityLevel -notin @('L0-Absent', 'L1-Informal')) {
    throw "Critical-capped roadmap must land at L0/L1, got $($criticalAudit.maturityLevel)"
}

# L4 requires NO critical or warning findings, so any warning caps at L3. The
# well-formed fixture already carries warnings, so it is the natural case here.
$warningAudit = $scoredContract
$warningFindingCount = @($warningAudit.auditFindings | Where-Object { $_.severity -eq 'warning' }).Count
if ($warningFindingCount -gt 0) {
    if ([int]$warningAudit.maturityScore -gt $l3Max) {
        throw "Any warning finding must cap maturity at L3 (<= $l3Max), got $($warningAudit.maturityScore) -> $($warningAudit.maturityLevel)"
    }
    if ($warningAudit.maturityLevel -eq 'L4-Orchestration-Ready') {
        throw 'L4-Orchestration-Ready requires zero warning findings'
    }
}
Write-Host ("  maturity caps ok: critical -> {0} (<= {1}); {2} warning finding(s) -> {3} (<= {4})" -f `
    $criticalAudit.maturityLevel, $l1Max, $warningFindingCount, $warningAudit.maturityLevel, $l3Max) -ForegroundColor DarkGray

# The canonical status form in ROADMAP_TEMPLATE.md is a blockquote. A detector
# that only understood "**Status:** active" would fire ROADMAP-012 on every
# template-conformant repo in the portfolio.
Write-Step 'Roadmap auditor — smoke: canonical "> Status: active" blockquote form is detected'
$blockquoteFixture = $activeReleaseFixture.Replace('**Status:** {0}', '> Status: {0}').Replace('**Status:** {1}', '> Status: {1}')
$blockquoteContent = $blockquoteFixture -f 'active', 'planned'
$blockquoteParsed = Invoke-ParseRoadmapContent -Content $blockquoteContent -SourcePath 'ROADMAP.md'
$blockquoteContract = Invoke-NormalizeRoadmapContract -ParsedResult $blockquoteParsed -RawContent $blockquoteContent -RepoName 'smoke-blockquote-status'
$blockquoteAudit = Invoke-AuditRoadmapContract -Contract $blockquoteContract -AuditRules $auditRulesObj
if ([int]$blockquoteAudit.activeReleaseCount -ne 1) {
    throw "Canonical '> Status: active' blockquote not detected: expected activeReleaseCount=1, got $($blockquoteAudit.activeReleaseCount)"
}
if (@($blockquoteAudit.auditFindings | Where-Object { $_.ruleId -eq 'ROADMAP-012' }).Count -ne 0) {
    throw 'ROADMAP-012 must not fire for a template-conformant roadmap using the "> Status: active" blockquote'
}
Write-Host '  blockquote status form detected (activeReleaseCount=1, no ROADMAP-012)' -ForegroundColor DarkGray

# The structure linter had NO smoke coverage, which is how it came to contradict
# the template it lints: R013's size cap fired on any conformant active release
# (the template deliberately puts the whole execution contract there), and RQ001
# demanded a Status line on the pointer block that RQ003 then errors on for
# declaring status twice. Both relaxations are pinned here alongside proof they
# still fire when genuinely violated — a relaxed rule that no longer detects
# anything is worse than the false positive it replaced.
# Release 2.7 Phase A. Until 2026-08-09 submit-pr was a plan builder that
# returned created=false even with createPr=true, so "no PR appeared" was
# indistinguishable from success. Every refusal now carries a NAMED reason, and
# these assertions are what stop it regressing to a silent no-op.
Write-Step 'Roadmap submit-PR — smoke: slug parsing and the refusal matrix'
. (Join-Path $WorkspaceRoot 'backend\modules\roadmap\Roadmap.PrSubmitter.ps1')

foreach ($case in @(
    @{ url = 'https://github.com/xfaith4/GitHubRepoManagement.git'; slug = 'xfaith4/GitHubRepoManagement' }
    @{ url = 'https://github.com/xfaith4/GitHubRepoManagement';     slug = 'xfaith4/GitHubRepoManagement' }
    @{ url = 'git@github.com:xfaith4/GitHubRepoManagement.git';     slug = 'xfaith4/GitHubRepoManagement' }
    @{ url = 'ssh://git@github.com/xfaith4/GitHubRepoManagement';   slug = 'xfaith4/GitHubRepoManagement' }
)) {
    $parsed = Resolve-GitHubRepoSlug -RemoteUrl $case.url
    if ($null -eq $parsed -or $parsed.slug -ne $case.slug) {
        throw "Resolve-GitHubRepoSlug failed for '$($case.url)': expected '$($case.slug)', got '$(if ($null -ne $parsed) { $parsed.slug } else { '<null>' })'"
    }
}
# A non-GitHub remote must refuse, not have a slug guessed for it.
foreach ($badUrl in @('https://gitlab.com/o/r.git', 'C:\some\local\path', '', 'https://github.example.com/o/r')) {
    if ($null -ne (Resolve-GitHubRepoSlug -RemoteUrl $badUrl)) { throw "Resolve-GitHubRepoSlug must return null for a non-GitHub remote: '$badUrl'" }
}

$okSlug = Resolve-GitHubRepoSlug -RemoteUrl 'https://github.com/o/r.git'
$baseArgs = @{
    RepoPath = 'C:\repo'; RoadmapPath = 'C:\repo\ROADMAP.md'; ProposedContent = 'new'
    CurrentContent = 'old'; Token = 'tok'; Slug = $okSlug; IsGitRepo = $true
    WorkingTreeDirty = $false; BaseBranch = 'main'
}
if (-not (Test-RoadmapRepairPrPreconditions @baseArgs).ok) { throw 'A fully valid submit-PR request must pass preconditions' }

# Each refusal must fire for its own reason and carry a category.
foreach ($refusal in @(
    @{ name = 'no repo path';       override = @{ RepoPath = '' };                              category = 'validation' }
    @{ name = 'not a git repo';     override = @{ IsGitRepo = $false };                         category = 'validation' }
    @{ name = 'no roadmap path';    override = @{ RoadmapPath = '' };                           category = 'validation' }
    @{ name = 'no proposedContent'; override = @{ ProposedContent = '' };                       category = 'validation' }
    @{ name = 'no-op change';       override = @{ ProposedContent = 'same'; CurrentContent = 'same' }; category = 'no-op' }
    @{ name = 'no token';           override = @{ Token = '' };                                 category = 'auth' }
    @{ name = 'non-GitHub remote';  override = @{ Slug = $null };                               category = 'validation' }
    @{ name = 'dirty tree';         override = @{ WorkingTreeDirty = $true };                   category = 'conflict' }
)) {
    $args = @{} + $baseArgs
    foreach ($k in $refusal.override.Keys) { $args[$k] = $refusal.override[$k] }
    $verdict = Test-RoadmapRepairPrPreconditions @args
    if ($verdict.ok) { throw "submit-PR must refuse '$($refusal.name)' but it passed preconditions" }
    if ($verdict.category -ne $refusal.category) { throw "submit-PR refusal '$($refusal.name)' expected category '$($refusal.category)', got '$($verdict.category)'" }
    if ([string]::IsNullOrWhiteSpace($verdict.reason)) { throw "submit-PR refusal '$($refusal.name)' must carry a named reason, not an empty string" }
}

# A repair must not strip the file's trailing newline (git "\ No newline at end
# of file", markdownlint MD047). Caught on the Phase A artifact PR #96.
$newlineCases = @(
    @{ name = 'adds a missing trailing newline'; input = "line one`nline two";   expected = "line one`nline two`n" }
    @{ name = 'keeps an existing one';           input = "line one`nline two`n"; expected = "line one`nline two`n" }
    @{ name = 'does not double it';              input = "text`n";               expected = "text`n" }
)
foreach ($nl in $newlineCases) {
    $normalized = if ($nl.input.EndsWith("`n")) { $nl.input } else { $nl.input + "`n" }
    if ($normalized -ne $nl.expected) { throw "Trailing-newline normalization failed — $($nl.name)" }
}

# Branch names must be unique per second and never collide with the base branch.
$b1 = Get-RoadmapRepairBranchName -NowUtc ([datetime]'2026-08-09T06:00:00Z')
$b2 = Get-RoadmapRepairBranchName -NowUtc ([datetime]'2026-08-09T06:00:01Z')
if ($b1 -eq $b2) { throw 'Roadmap repair branch names must differ across timestamps' }
if ($b1 -notlike 'roadmap-repair/*') { throw "Unexpected repair branch name format: $b1" }
# The token must never appear verbatim in the git args.
$tokenArgs = (Get-GitTokenPushArgs -Token 'super-secret-token') -join ' '
if ($tokenArgs -match 'super-secret-token') { throw 'The GitHub token must not appear in cleartext in git push arguments' }
if (@(Get-GitTokenPushArgs -Token '').Count -ne 0) { throw 'No token means no auth args (SSH remotes and operator-run hosts push without one)' }
# The entry point must RETURN a named refusal for empty inputs, not throw a
# parameter-binding error. Declaring RepoPath/RoadmapPath/ProposedContent as
# Mandatory made PowerShell reject the empty string before the precondition
# check ran, so the route answered 500 "Cannot bind argument to parameter
# 'RepoPath'" instead of the 409 that says what to fix. Caught by the api-host
# smoke on 2026-08-09; asserted here because it is cheaper to catch at this
# layer than after a 15-minute host run.
foreach ($empty in @(
    @{ name = 'empty repoPath';        args = @{ RepoName = 'x'; RepoPath = '';        RoadmapPath = 'C:\r\ROADMAP.md'; ProposedContent = 'new' } }
    @{ name = 'empty roadmapPath';     args = @{ RepoName = 'x'; RepoPath = 'C:\r';    RoadmapPath = '';                ProposedContent = 'new' } }
    @{ name = 'empty proposedContent'; args = @{ RepoName = 'x'; RepoPath = 'C:\r';    RoadmapPath = 'C:\r\ROADMAP.md'; ProposedContent = '' } }
)) {
    $submitOutcome = $null
    $submitSplat = $empty.args   # splatting needs a plain variable, not an expression
    try { $submitOutcome = Invoke-RoadmapRepairPrSubmission @submitSplat }
    catch { throw "Invoke-RoadmapRepairPrSubmission must RETURN a refusal for '$($empty.name)', not throw: $($_.Exception.Message)" }
    if ($null -eq $submitOutcome) { throw "Invoke-RoadmapRepairPrSubmission returned null for '$($empty.name)'" }
    if (-not $submitOutcome.refused) { throw "Invoke-RoadmapRepairPrSubmission must refuse '$($empty.name)'" }
    if ($submitOutcome.created) { throw "Invoke-RoadmapRepairPrSubmission must not report created=true for '$($empty.name)'" }
    if ([string]::IsNullOrWhiteSpace([string]$submitOutcome.reason)) { throw "Refusal for '$($empty.name)' must carry a named reason" }
}
Write-Host '  submit-PR ok: 4 remote forms parsed, 4 non-GitHub refused, 8 refusal categories named, 3 empty-input refusals returned (not thrown), token not in cleartext' -ForegroundColor DarkGray

Write-Step 'Roadmap structure linter — smoke: R013/RQ001 relaxations still detect real violations'
$structureLinter = Join-Path $WorkspaceRoot 'tools\Test-RoadmapStructure.ps1'
if (-not (Test-Path -LiteralPath $structureLinter)) { throw "Test-RoadmapStructure.ps1 not found at: $structureLinter" }
$structureFixtureDir = Join-Path $WorkspaceRoot 'output\smoke\roadmap-structure'
$null = New-Item -ItemType Directory -Path $structureFixtureDir -Force

function Invoke-StructureLintCodes {
    param([Parameter(Mandatory)][string]$Content, [Parameter(Mandatory)][string]$Name)
    $fixturePath = Join-Path $structureFixtureDir $Name
    Set-Content -LiteralPath $fixturePath -Value $Content -Encoding UTF8
    # *>&1, not 2>&1: the linter reports findings with Write-Host, which lands on
    # the information stream. Capturing only stderr returned an empty string, so
    # every "rule must fire" assertion passed vacuously while the finding it was
    # looking for scrolled past on the console.
    $output = & $structureLinter -Path $fixturePath *>&1 | Out-String
    return $output
}

$bigBody = (1..160 | ForEach-Object { "- [ ] milestone item $_ _(state: planned)_" }) -join "`n"
$activeBig = @"
# Structure Fixture

> **Status:** Active
> **Active release:** **Release 1.0 - Alpha**

## 5. Active Release Snapshot

### Active release detail - 1.0 Alpha

Pointer only; deliberately restates nothing.

## 6. Open Releases

### Release 1.0 - Alpha

**Status:** active

**Goal:** ship it.

#### Engineering milestones

$bigBody

#### Acceptance criteria

- It ships.
"@
$activeBigOut = Invoke-StructureLintCodes -Content $activeBig -Name 'active-oversized.md'
if ($activeBigOut -match 'R013-FUTURE-RELEASE-SIZE') {
    throw 'R013 must NOT fire on the active release: the template puts the full execution contract there'
}
if ($activeBigOut -match 'RQ001-MISSING-STATUS') {
    throw 'RQ001 must NOT fire on a pointer block when the release itself declares its status'
}

# Same oversized body, but on a PLANNED release -> R013 must still fire.
$plannedBig = $activeBig.Replace('**Status:** active', '**Status:** planned')
if ((Invoke-StructureLintCodes -Content $plannedBig -Name 'planned-oversized.md') -notmatch 'R013-FUTURE-RELEASE-SIZE') {
    throw 'R013 must still fire for an oversized non-active release'
}

# Status declared NOWHERE -> RQ001 must still fire (and must not crash: an
# empty status-block set used to kill the linter on the very file it diagnoses).
$noStatus = $activeBig.Replace("**Status:** active`r`n", '').Replace("**Status:** active`n", '').Replace('**Status:** active', '')
$noStatusOut = Invoke-StructureLintCodes -Content $noStatus -Name 'no-status.md'
if ($noStatusOut -match 'Cannot bind argument') { throw 'Structure linter crashed on a roadmap with no status lines instead of reporting RQ001' }
if ($noStatusOut -notmatch 'RQ001-MISSING-STATUS') { throw 'RQ001 must still fire when neither the pointer nor the release declares a status' }

# No release headings at all -> R000, not a StrictMode crash on $null.Count.
$noReleasesOut = Invoke-StructureLintCodes -Content "# Empty`n`nNo releases here.`n" -Name 'no-releases.md'
if ($noReleasesOut -match 'cannot be found on this object') { throw 'Structure linter crashed on a release-less file instead of reporting R000' }
if ($noReleasesOut -notmatch 'R000-NO-RELEASES') { throw 'R000-NO-RELEASES must fire for a file with no release headings' }
Write-Host '  structure linter ok: active exempt from R013, planned still flagged; RQ001 fires only when status is declared nowhere; release-less file reports R000 instead of crashing' -ForegroundColor DarkGray

# Tripwire: the two evaluators must return the SAME verdict for the same file.
# Until 2026-08-08 they did not — the backend auditor and
# tools/Test-RoadmapContract.ps1 each carried private detection, and no repo in
# the estate scored the same under both. Whichever tool an operator happened to
# run decided whether a repo was dispatch-ready, which is exactly the
# "two figures, one truth" failure this product exists to catch. The status
# signal was the last one to reconcile (rules v1.3), so it is asserted here in
# both spellings and in the two-active case that trips the critical cap.
Write-Step 'Roadmap evaluators — smoke: module and Test-RoadmapContract.ps1 agree on one fixture'
$parityHost = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
$parityCli  = Join-Path $WorkspaceRoot 'tools\Test-RoadmapContract.ps1'
if (-not (Test-Path -LiteralPath $parityCli)) { throw "Test-RoadmapContract.ps1 not found at: $parityCli" }
$parityDir = Join-Path ([System.IO.Path]::GetTempPath()) ("roadmap-parity-{0}" -f ([guid]::NewGuid().ToString('N')))
New-Item -ItemType Directory -Path $parityDir -Force | Out-Null
try {
    $parityCases = @(
        @{ name = 'bold status, one active';       template = $activeReleaseFixture; one = 'active';  two = 'planned' }
        @{ name = 'blockquote status, one active'; template = $blockquoteFixture;    one = 'active';  two = 'planned' }
        @{ name = 'alias status, two active';      template = $activeReleaseFixture; one = 'active';  two = 'In Progress' }
        @{ name = 'no active release';             template = $blockquoteFixture;    one = 'planned'; two = 'planned' }
    )

    foreach ($case in $parityCases) {
        $caseContent = $case.template -f $case.one, $case.two
        $caseRoot = Join-Path $parityDir ($case.name -replace '[^A-Za-z0-9]', '-')
        New-Item -ItemType Directory -Path $caseRoot -Force | Out-Null
        $caseRoadmap = Join-Path $caseRoot 'ROADMAP.md'
        Set-Content -LiteralPath $caseRoadmap -Value $caseContent -Encoding UTF8

        $caseParsed   = Invoke-ParseRoadmapContent -Content $caseContent -SourcePath 'ROADMAP.md'
        $caseContract = Invoke-NormalizeRoadmapContract -ParsedResult $caseParsed -RawContent $caseContent -RepoName 'smoke-parity' -AuditRules $auditRulesObj
        $moduleAudit  = Invoke-AuditRoadmapContract -Contract $caseContract -AuditRules $auditRulesObj

        $caseContractOut = Join-Path $caseRoot 'contract.json'
        & $parityHost -NoProfile -File $parityCli -Path $caseRoadmap `
            -StandardsPath (Join-Path $WorkspaceRoot 'standards\roadmap') `
            -ContractOut $caseContractOut -Quiet 2>&1 | Out-Null
        if (-not (Test-Path -LiteralPath $caseContractOut)) {
            throw ("Test-RoadmapContract.ps1 produced no contract for parity case '{0}'" -f $case.name)
        }
        $cliAudit = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $caseContractOut -Raw -Encoding UTF8)

        $moduleFindings = (@($moduleAudit.auditFindings | ForEach-Object { [string]$_.ruleId } | Sort-Object) -join ',')
        $cliFindings    = (@($cliAudit.auditFindings    | ForEach-Object { [string]$_.ruleId } | Sort-Object) -join ',')

        foreach ($field in @(
            @{ label = 'maturityScore';      mod = [int]$moduleAudit.maturityScore;      cli = [int]$cliAudit.maturityScore }
            @{ label = 'maturityLevel';      mod = [string]$moduleAudit.maturityLevel;   cli = [string]$cliAudit.maturityLevel }
            @{ label = 'releaseCount';       mod = [int]$moduleAudit.releaseCount;       cli = [int]$cliAudit.releaseCount }
            @{ label = 'activeReleaseCount'; mod = [int]$moduleAudit.activeReleaseCount; cli = [int]$cliAudit.activeReleaseCount }
            @{ label = 'pendingCount';       mod = [int]$moduleAudit.pendingCount;       cli = [int]$cliAudit.pendingCount }
            @{ label = 'completedCount';     mod = [int]$moduleAudit.completedCount;     cli = [int]$cliAudit.completedCount }
            @{ label = 'auditFindings';      mod = $moduleFindings;                      cli = $cliFindings }
        )) {
            if ($field.mod -ne $field.cli) {
                throw ("Evaluator divergence on parity case '{0}': {1} module={2} cli={3}. Both evaluators must derive this signal from the 'detection' block in roadmap-audit-rules.json — do not reintroduce a private pattern in either tool." -f $case.name, $field.label, $field.mod, $field.cli)
            }
        }
    }
    Write-Host ("  evaluator parity ok: {0} fixtures agree on score, level, counts, and findings" -f @($parityCases).Count) -ForegroundColor DarkGray
}
finally {
    Remove-Item -LiteralPath $parityDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Step 'Roadmap standard assets — smoke: validate roadmap-audit-rules.json (Release 0.7)'
$roadmapAuditRulesPath   = Join-Path $WorkspaceRoot 'standards\roadmap\roadmap-audit-rules.json'
$roadmapSchemaPath       = Join-Path $WorkspaceRoot 'standards\roadmap\roadmap-contract.schema.json'
$roadmapTemplatePath     = Join-Path $WorkspaceRoot 'standards\roadmap\ROADMAP_TEMPLATE.md'
$roadmapMaturityPath     = Join-Path $WorkspaceRoot 'standards\roadmap\ROADMAP_MATURITY_MODEL.md'
$roadmapRepairPath       = Join-Path $WorkspaceRoot 'standards\roadmap\roadmap-repair-prompt.md'
@($roadmapAuditRulesPath, $roadmapSchemaPath, $roadmapTemplatePath, $roadmapMaturityPath, $roadmapRepairPath) | ForEach-Object {
    if (-not (Test-Path -LiteralPath $_)) { throw "Roadmap standard asset not found: $_" }
}
$auditRules = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $roadmapAuditRulesPath -Raw -Encoding UTF8)
if ($null -eq $auditRules.rules)              { throw "roadmap-audit-rules.json missing 'rules' array" }
if ($null -eq $auditRules.maturityThresholds) { throw "roadmap-audit-rules.json missing 'maturityThresholds'" }
if (@($auditRules.rules).Count -eq 0)         { throw "roadmap-audit-rules.json 'rules' array is empty" }
$schema = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $roadmapSchemaPath -Raw -Encoding UTF8)
if ($null -eq $schema.properties)             { throw "roadmap-contract.schema.json missing 'properties'" }
Write-Host ("  roadmap standard assets valid: {0} audit rules, {1} maturity levels" -f @($auditRules.rules).Count, @($auditRules.maturityThresholds.PSObject.Properties).Count) -ForegroundColor DarkGray

# Tripwire: every rule the pack ships must be evaluated by the auditor. An
# unevaluated rule still contributes its weight to the denominator, so adding
# one silently inflates every score and pushes roadmaps across the L3 dispatch
# gate. This is the d2cc6cc / c6662cf regression class — counting rules is not
# enough, the auditor must actually implement each id.
Write-Step 'Roadmap standard assets — smoke: every shipped audit rule is implemented by the auditor'
$auditorSource = Get-Content -LiteralPath (Join-Path $WorkspaceRoot 'backend\modules\roadmap\Roadmap.Auditor.ps1') -Raw -Encoding UTF8
$unimplementedRules = @()
foreach ($rule in @($auditRules.rules)) {
    $ruleId = [string]$rule.id
    if ($auditorSource -notmatch [regex]::Escape("'$ruleId'")) { $unimplementedRules += $ruleId }
}
if ($unimplementedRules.Count -gt 0) {
    throw ("roadmap-audit-rules.json ships rule(s) the auditor never evaluates: {0}. Each contributes scoreWeight to maxPossibleScore but can never fail, inflating every maturity score. Implement a case in Invoke-AuditRoadmapContract or remove the rule." -f ($unimplementedRules -join ', '))
}
Write-Host ("  all {0} audit rules implemented in Roadmap.Auditor.ps1" -f @($auditRules.rules).Count) -ForegroundColor DarkGray

# Tripwire: the published spec copy must not drift from the live rule pack.
# standards/roadmap is code-referenced at runtime; spec/roadmap-contract is the
# publishable Release 2.3 deliverable. README.md is intentionally per-location.
Write-Step 'Roadmap standard assets — smoke: standards/roadmap and spec/roadmap-contract stay in sync'
$specDrift = @()
foreach ($assetName in @('ROADMAP_BUDGET_MODEL.md','ROADMAP_MATURITY_MODEL.md','ROADMAP_TEMPLATE.md','roadmap-audit-rules.json','roadmap-contract.schema.json','roadmap-events.md','roadmap-repair-prompt.md')) {
    $standardsAsset = Join-Path $WorkspaceRoot ("standards\roadmap\{0}" -f $assetName)
    $specAsset      = Join-Path $WorkspaceRoot ("spec\roadmap-contract\{0}" -f $assetName)
    if (-not (Test-Path -LiteralPath $standardsAsset)) { throw "Roadmap standard asset not found: $standardsAsset" }
    if (-not (Test-Path -LiteralPath $specAsset))      { throw "Published spec asset not found: $specAsset" }
    $standardsHash = (Get-FileHash -LiteralPath $standardsAsset -Algorithm SHA256).Hash
    $specHash      = (Get-FileHash -LiteralPath $specAsset -Algorithm SHA256).Hash
    if ($standardsHash -ne $specHash) { $specDrift += $assetName }
}
if ($specDrift.Count -gt 0) {
    throw ("standards/roadmap has drifted from spec/roadmap-contract for: {0}. Copy the updated file(s) into spec/roadmap-contract, or document the intended divergence in standards/MANIFEST.md." -f ($specDrift -join ', '))
}
Write-Host '  standards/roadmap and spec/roadmap-contract in sync (7 assets)' -ForegroundColor DarkGray

Write-Step 'Loading roadmap repairer module (Release 0.9)'
$roadmapRepairer = Join-Path $WorkspaceRoot 'backend\modules\roadmap\Roadmap.Repairer.ps1'
if (-not (Test-Path -LiteralPath $roadmapRepairer)) { throw "Roadmap.Repairer.ps1 not found at: $roadmapRepairer" }
. $roadmapRepairer
Write-Host 'Roadmap repairer module loaded successfully' -ForegroundColor Green

Write-Step 'Roadmap repairer — smoke: plan repair for missing roadmap (expect repair-blocked)'
$missingContract2 = Invoke-NormalizeRoadmapContract -ParsedResult $null -RepoName 'smoke-repair-missing'
$missingContract2 = Invoke-AuditRoadmapContract -Contract $missingContract2 -AuditRules $auditRulesObj
$missingPlan = Invoke-PlanRoadmapRepair -Contract $missingContract2
if ($missingPlan.previewState -ne 'repair-blocked') { throw "Expected previewState=repair-blocked for missing roadmap, got $($missingPlan.previewState)" }
Write-Host '  missing roadmap plan -> repair-blocked correctly' -ForegroundColor DarkGray

Write-Step 'Roadmap repairer — smoke: plan repair for complete roadmap (expect rewrite-not-recommended)'
$completeParsed2  = Invoke-ParseRoadmapContent -Content "## Done`n- [x] Item one`n- [x] Item two"
$completeContract = Invoke-NormalizeRoadmapContract -ParsedResult $completeParsed2 -RawContent "## Done`n- [x] Item one`n- [x] Item two" -RepoName 'smoke-repair-complete'
$completeContract = Invoke-AuditRoadmapContract -Contract $completeContract -AuditRules $auditRulesObj
$completePlan = Invoke-PlanRoadmapRepair -Contract $completeContract
if ($completePlan.previewState -ne 'rewrite-not-recommended') { throw "Expected previewState=rewrite-not-recommended for complete roadmap, got $($completePlan.previewState)" }
Write-Host '  complete roadmap plan -> rewrite-not-recommended correctly' -ForegroundColor DarkGray

Write-Step 'Roadmap repairer — smoke: plan repair for L1 informal roadmap (expect repair-preview-ready)'
$informalContent = "## Tasks`n- [ ] Do something`n- [ ] Do another thing`n- [x] Done already"
$informalParsed  = Invoke-ParseRoadmapContent -Content $informalContent
$informalContract = Invoke-NormalizeRoadmapContract -ParsedResult $informalParsed -RawContent $informalContent -RepoName 'smoke-repair-informal'
$informalContract = Invoke-AuditRoadmapContract -Contract $informalContract -AuditRules $auditRulesObj
$informalPlan = Invoke-PlanRoadmapRepair -Contract $informalContract
if ($informalPlan.previewState -ne 'repair-preview-ready') { throw "Expected previewState=repair-preview-ready for L1 informal roadmap, got $($informalPlan.previewState)" }
if (@($informalPlan.actions).Count -eq 0) { throw "Expected at least one repair action for L1 informal roadmap" }
Write-Host ("  L1 informal roadmap plan -> repair-preview-ready with {0} action(s)" -f @($informalPlan.actions).Count) -ForegroundColor DarkGray

Write-Step 'Roadmap repairer — smoke: generate repair preview for L1 informal roadmap'
$informalPreview = Invoke-GenerateRepairPreview -Contract $informalContract -RepairPlan $informalPlan -RawContent $informalContent -RepoName 'smoke-repair-informal'
if ($informalPreview.previewState -ne 'repair-preview-ready') { throw "Expected previewState=repair-preview-ready in preview result, got $($informalPreview.previewState)" }
if ([string]::IsNullOrWhiteSpace($informalPreview.proposedContent)) { throw "Expected non-empty proposedContent for repair-preview-ready state" }
if ([string]::IsNullOrWhiteSpace($informalPreview.previewId)) { throw "Expected non-empty previewId in preview result" }
# Verify completed items are preserved in proposed content
if ($informalPreview.proposedContent -notmatch '\[x\]') { throw "Expected completed items (- [x]) to be preserved in proposed content" }
# Verify pending items are present
if ($informalPreview.proposedContent -notmatch '\[ \]') { throw "Expected pending items (- [ ]) to appear in proposed content" }
Write-Host ("  repair preview generated: previewId={0} completedItemCount={1} pendingItemCount={2}" -f $informalPreview.previewId, $informalPreview.completedItemCount, $informalPreview.pendingItemCount) -ForegroundColor DarkGray

Write-Step 'Roadmap repairer — smoke: generate preview for blocked state returns null proposedContent'
$blockedPreview = Invoke-GenerateRepairPreview -Contract $missingContract2 -RepairPlan $missingPlan -RawContent '' -RepoName 'smoke-repair-missing'
if ($blockedPreview.previewState -ne 'repair-blocked') { throw "Expected previewState=repair-blocked in blocked preview, got $($blockedPreview.previewState)" }
if ($null -ne $blockedPreview.proposedContent -and -not [string]::IsNullOrWhiteSpace($blockedPreview.proposedContent)) {
    throw "Expected proposedContent to be null/empty for repair-blocked state"
}
Write-Host '  blocked preview correctly returns null proposedContent' -ForegroundColor DarkGray

Write-Step 'Roadmap repairer — smoke: split-archive layout is preserved, never contradicted (Lane 0.7)'
# A roadmap that archives completed work to a separate file must not be told it
# has no history. The old placeholder was doubly wrong: it asserted something
# false, and '- [x]' was counted as a completed item on the next parse.
$splitContent = @'
# Split Roadmap

Completed work lives in [the archive](docs/history/completed-releases.md).

## Open Work

- [ ] Build the first thing
- [ ] Build the second thing
- [ ] Build the third thing
'@
$splitParsed   = Invoke-ParseRoadmapContent -Content $splitContent
$splitContract = Invoke-NormalizeRoadmapContract -ParsedResult $splitParsed -RawContent $splitContent -RepoName 'smoke-repair-split'
$splitContract = Invoke-AuditRoadmapContract -Contract $splitContract -AuditRules $auditRulesObj
$splitPlan     = Invoke-PlanRoadmapRepair -Contract $splitContract
$splitPreview  = Invoke-GenerateRepairPreview -Contract $splitContract -RepairPlan $splitPlan -RawContent $splitContent -RepoName 'smoke-repair-split'

$pointer = Get-RoadmapHistoryPointer -Content $splitContent
if ($null -eq $pointer) { throw 'Expected the archive pointer link to be detected in a split roadmap' }
if ($pointer.Target -ne 'docs/history/completed-releases.md') { throw "Expected pointer target docs/history/completed-releases.md, got '$($pointer.Target)'" }
if ($null -ne (Get-RoadmapHistoryPointer -Content "## Tasks`n- [ ] a")) { throw 'Expected no pointer for a roadmap without an archive link' }

# Assert the state rather than guarding on it — a guard would let every
# assertion below silently stop running if the plan state ever changed.
if ($splitPreview.previewState -ne 'repair-preview-ready') {
    throw "Expected repair-preview-ready for the split fixture, got '$($splitPreview.previewState)' — the assertions below would not have run"
}
if ($splitPreview.proposedContent -match 'No completed items recorded yet') {
    throw 'Repair must not assert "No completed items recorded yet" on a roadmap whose history is archived'
}
if ($splitPreview.proposedContent -notmatch [regex]::Escape('docs/history/completed-releases.md')) {
    throw 'Repair must carry the archive pointer into the proposed content'
}
if ([int]$splitPreview.completedItemCount -ne 0) {
    throw "Expected completedItemCount=0 for a split roadmap, got $($splitPreview.completedItemCount)"
}
# The empty-state line must not be a checkbox, or reparsing inflates the count.
$reparsed = Invoke-ParseRoadmapContent -Content $splitPreview.proposedContent
if ([int]$reparsed.completedCount -ne 0) {
    throw "Repair output must not reparse as completed work; got completedCount=$($reparsed.completedCount)"
}

# No pointer -> the claim is scoped to the file, not the project.
$noHistoryContent = "## Tasks`n- [ ] alpha`n- [ ] beta`n- [ ] gamma"
$nhParsed   = Invoke-ParseRoadmapContent -Content $noHistoryContent
$nhContract = Invoke-NormalizeRoadmapContract -ParsedResult $nhParsed -RawContent $noHistoryContent -RepoName 'smoke-repair-nohistory'
$nhContract = Invoke-AuditRoadmapContract -Contract $nhContract -AuditRules $auditRulesObj
$nhPlan     = Invoke-PlanRoadmapRepair -Contract $nhContract
$nhPreview  = Invoke-GenerateRepairPreview -Contract $nhContract -RepairPlan $nhPlan -RawContent $noHistoryContent -RepoName 'smoke-repair-nohistory'
if ($nhPreview.previewState -ne 'repair-preview-ready') {
    throw "Expected repair-preview-ready for the no-history fixture, got '$($nhPreview.previewState)'"
}
if ($nhPreview.proposedContent -match 'No completed items recorded yet') { throw 'The old absolute placeholder must be gone' }
if ($nhPreview.proposedContent -notmatch 'recorded in this file') { throw 'Expected the empty-state claim to be scoped to this file' }
Write-Host '  split-archive repair ok: pointer detected + preserved, no false "no history" claim, output reparses to 0 completed' -ForegroundColor DarkGray

Write-Step 'Loading repo evaluator module (Release 1.4 / Phase 5 expanded evaluator)'
if (-not (Test-Path -LiteralPath $roadmapEvaluatorPath)) { throw "Roadmap.Evaluator.ps1 not found at: $roadmapEvaluatorPath" }
. $roadmapEvaluatorPath
Write-Host 'Repo evaluator module loaded successfully' -ForegroundColor Green

Write-Step 'Repo evaluator — smoke: no-roadmap repo includes modernization and value opportunities'
$tmpEvalRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('repoeval-smoke-' + [guid]::NewGuid().ToString('n').Substring(0, 8))
$null = New-Item -ItemType Directory -Path (Join-Path $tmpEvalRoot 'backend') -Force
Set-Content -LiteralPath (Join-Path $tmpEvalRoot 'package.json') -Encoding UTF8 -Value @'
{
  "name": "smoke-eval",
  "version": "1.0.0",
  "scripts": {
    "build": "node backend/server.js"
  }
}
'@
Set-Content -LiteralPath (Join-Path $tmpEvalRoot 'README.md') -Encoding UTF8 -Value @'
# Smoke Eval

Short overview only.
'@
Set-Content -LiteralPath (Join-Path $tmpEvalRoot 'backend\server.js') -Encoding UTF8 -Value 'console.log("hello");'

try {
    $evalResult = Invoke-RepoEvaluation -RepoName 'smoke-eval' -LocalPath $tmpEvalRoot
    if ($evalResult.repoType -ne 'node') { throw "Expected repoType=node, got $($evalResult.repoType)" }
    if ($evalResult.hasExistingRoadmap) { throw 'Expected hasExistingRoadmap=false for no-roadmap smoke repo' }
    if ([string]::IsNullOrWhiteSpace($evalResult.suggestedRoadmapContent)) { throw 'Expected suggestedRoadmapContent for repo without roadmap' }
    $evalCategories = @($evalResult.findings | ForEach-Object { [string]$_.category } | Select-Object -Unique)
    foreach ($expectedCategory in @('documentation', 'testing', 'security', 'modernization', 'feature', 'user-value')) {
        if ($evalCategories -notcontains $expectedCategory) {
            throw "Expected expanded evaluator category '$expectedCategory' in smoke result, got: $($evalCategories -join ', ')"
        }
    }
    if ($evalResult.suggestedRoadmapContent -notmatch '## Release 1\.0') { throw 'Expected suggestedRoadmapContent to contain Release 1.0 section' }
    if ($evalResult.suggestedRoadmapContent -notmatch 'Workflow Clarity and User Value') { throw 'Expected suggested roadmap to contain Workflow Clarity and User Value release' }
    if ($evalResult.suggestedRoadmapContent -notmatch 'Modernization and Operability') { throw 'Expected suggested roadmap to contain Modernization and Operability release' }
    Write-Host ("  expanded evaluator categories: {0}" -f ($evalCategories -join ', ')) -ForegroundColor DarkGray

    Set-Content -LiteralPath (Join-Path $tmpEvalRoot 'ROADMAP.md') -Encoding UTF8 -Value @'
# Existing Roadmap

## Release 1.0 — Initial

### Engineering milestones
- [ ] Keep this roadmap alive
'@
    $evalExistingRoadmap = Invoke-RepoEvaluation -RepoName 'smoke-eval' -LocalPath $tmpEvalRoot
    if (-not $evalExistingRoadmap.hasExistingRoadmap) { throw 'Expected hasExistingRoadmap=true after creating roadmap file' }
    if ($null -ne $evalExistingRoadmap.suggestedRoadmapContent -and -not [string]::IsNullOrWhiteSpace($evalExistingRoadmap.suggestedRoadmapContent)) {
        throw 'Expected suggestedRoadmapContent to be null/empty when roadmap already exists'
    }
    if (@($evalExistingRoadmap.suggestedAdditions).Count -eq 0) { throw 'Expected suggestedAdditions for repo with existing roadmap' }
    Write-Host ("  existing-roadmap suggestions: {0}" -f @($evalExistingRoadmap.suggestedAdditions).Count) -ForegroundColor DarkGray
} finally {
    Remove-Item -LiteralPath $tmpEvalRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Step 'Running reconciliation preflight check'
& (Join-Path $WorkspaceRoot 'backend\modules\reconcile\preflight-check.ps1')

Write-Step 'Loading execution ledger module (Release 1.0)'
$executionLedgerPath = Join-Path $WorkspaceRoot 'backend\modules\execution\Execution.Ledger.ps1'
if (-not (Test-Path -LiteralPath $executionLedgerPath)) { throw "Execution.Ledger.ps1 not found at: $executionLedgerPath" }
. $executionLedgerPath
Write-Host 'Execution ledger module loaded successfully' -ForegroundColor Green

Write-Step 'Execution ledger — smoke: sync from audit data and verify states'
$smokeWs = Join-Path $WorkspaceRoot 'output\smoke\module\execution'
if (-not (Test-Path -LiteralPath $smokeWs)) {
    $null = New-Item -ItemType Directory -Path $smokeWs -Force
}
$null = New-Item -ItemType Directory -Path (Join-Path $smokeWs 'output\execution') -Force -ErrorAction SilentlyContinue
$smokeDocEntries = @(
    [PSCustomObject]@{
        repoName = 'smoke-repo-ready'; repoPath = $smokeWs; dispatchReadiness = 'ready'
        nextPendingRoadmapItem = 'Implement feature smoke-A'; roadmapState = 'pending'
        criticalCount = 0; warningCount = 0; infoCount = 0; readyForDispatch = $true
        auditedAt = (Get-Date).ToString('o'); docFindings = @()
    },
    [PSCustomObject]@{
        repoName = 'smoke-repo-blocked'; repoPath = $smokeWs; dispatchReadiness = 'blocked'
        nextPendingRoadmapItem = ''; roadmapState = 'missing'
        criticalCount = 2; warningCount = 0; infoCount = 0; readyForDispatch = $false
        auditedAt = (Get-Date).ToString('o'); docFindings = @()
    }
)
$smokeRoadmapEntries = @(
    [PSCustomObject]@{
        repoName = 'smoke-repo-ready'; maturityScore = 70
        nextPendingItem = [PSCustomObject]@{ text = 'Implement feature smoke-A'; section = 'Release 1.0' }
        roadmapPath = (Join-Path $smokeWs 'ROADMAP.md')
    }
)
$smokedLedger = Sync-LedgerFromAudit -WorkspaceRoot $smokeWs -DocAuditEntries $smokeDocEntries -RoadmapAuditEntries $smokeRoadmapEntries
$smokeReady   = @($smokedLedger.entries | Where-Object { $_.executionState -eq 'ready'   }).Count
$smokeBlocked = @($smokedLedger.entries | Where-Object { $_.executionState -eq 'blocked' }).Count
if ($smokeReady   -ne 1) { throw "Expected 1 ready entry after sync, got $smokeReady"   }
if ($smokeBlocked -ne 1) { throw "Expected 1 blocked entry after sync, got $smokeBlocked" }
Write-Host ('  sync: ready=' + $smokeReady + ' blocked=' + $smokeBlocked) -ForegroundColor DarkGray

Write-Step 'Execution ledger — smoke: assign lane and verify duplicate guard'
$assignResult = Invoke-AssignLane -WorkspaceRoot $smokeWs -RepoName 'smoke-repo-ready'
if (-not $assignResult.success) { throw "Expected assign to succeed, got error: $($assignResult.error)" }
if ($assignResult.laneSlot -ne 1) { throw "Expected laneSlot=1, got $($assignResult.laneSlot)" }
$dupResult = Invoke-AssignLane -WorkspaceRoot $smokeWs -RepoName 'smoke-repo-ready'
if ($dupResult.success) { throw "Expected duplicate assign to fail, but it succeeded" }
Write-Host ('  assign lane=1 ok; duplicate blocked correctly') -ForegroundColor DarkGray

Write-Step 'Execution ledger — smoke: complete task and verify state transition'
$completeResult = Invoke-CompleteTask -WorkspaceRoot $smokeWs -RepoName 'smoke-repo-ready' -Outcome 'success' -HasRemainingWork $false
if (-not $completeResult.success) { throw "Expected complete to succeed, got error: $($completeResult.error)" }
if ($completeResult.newState -ne 'complete') { throw "Expected newState=complete, got $($completeResult.newState)" }
Write-Host '  complete task -> state=complete correctly' -ForegroundColor DarkGray

Write-Step 'Execution ledger — smoke: cancel task and verify retry count'
# Re-sync to get the ready repo back
$smokedLedger2 = Sync-LedgerFromAudit -WorkspaceRoot $smokeWs -DocAuditEntries $smokeDocEntries -RoadmapAuditEntries $smokeRoadmapEntries
$null = Invoke-AssignLane -WorkspaceRoot $smokeWs -RepoName 'smoke-repo-ready'
$cancelResult = Invoke-CancelTask -WorkspaceRoot $smokeWs -RepoName 'smoke-repo-ready' -Reason 'test-cancel' -MaxRetries 3
if (-not $cancelResult.success) { throw "Expected cancel to succeed, got error: $($cancelResult.error)" }
if ($cancelResult.newState -notin @('ready','blocked')) { throw "Expected newState=ready or blocked after cancel, got $($cancelResult.newState)" }
Write-Host ('  cancel -> newState=' + $cancelResult.newState + ' retryCount=' + $cancelResult.retryCount) -ForegroundColor DarkGray

Write-Step 'Execution ledger — smoke: requeue blocked repo'
$null = Invoke-RequeueRepo -WorkspaceRoot $smokeWs -RepoName 'smoke-repo-blocked' -Force $true
$summaryAfterRequeue = Get-ExecutionQueueSummary -WorkspaceRoot $smokeWs
$requeuedEntry = $summaryAfterRequeue.entries | Where-Object { $_.repoName -eq 'smoke-repo-blocked' } | Select-Object -First 1
if ($requeuedEntry.executionState -ne 'ready') { throw "Expected smoke-repo-blocked to be 'ready' after requeue, got $($requeuedEntry.executionState)" }
Write-Host '  requeue blocked -> ready correctly' -ForegroundColor DarkGray

Write-Step 'Execution ledger — smoke: ranked queue and summary'
$summary = Get-ExecutionQueueSummary -WorkspaceRoot $smokeWs
if ($null -eq $summary.lanes)       { throw 'Expected summary.lanes to be present' }
if ($null -eq $summary.rankedQueue) { throw 'Expected summary.rankedQueue to be present' }
if ($null -eq $summary.stateCounts) { throw 'Expected summary.stateCounts to be present' }
Write-Host ("  queue summary: total={0} activeLanes={1} rankedQueue={2}" -f $summary.totalRepos, $summary.activeLaneCount, @($summary.rankedQueue).Count) -ForegroundColor DarkGray

Write-Step 'Running modular reconciliation smoke test (narrow scope)'
& $reconcileModular `
    -LocalRoots @($WorkspaceRoot) `
    -OutDir (Join-Path $WorkspaceRoot 'output\smoke\module\reconcile') `
    -IncludeNonGitFolders:$false `
    -MaxDepth 2 | Out-Null

Write-Step 'Loading roadmap linter module (Release 1.1)'
$roadmapLinterPath = Join-Path $WorkspaceRoot 'backend\modules\roadmap\Roadmap.Linter.ps1'
if (-not (Test-Path -LiteralPath $roadmapLinterPath)) { throw "Roadmap.Linter.ps1 not found at: $roadmapLinterPath" }
. $roadmapLinterPath
Write-Host 'Roadmap linter module loaded successfully' -ForegroundColor Green

Write-Step 'Roadmap linter — smoke: lint a well-formed roadmap'
$wellFormedContent = @"
# My Project Roadmap

## Product Intent
This project does something useful.

## Recently Completed
- [x] Completed task one

## Release 1.0 — Initial Release

### Engineering milestones
- [ ] Implement feature A
- [ ] Implement feature B

### Acceptance criteria
- Feature A works correctly
"@
$wellFormedResult = Invoke-LintRoadmapContent -RawContent $wellFormedContent -RepoName 'smoke-lint-wellformed'
if ($null -eq $wellFormedResult) { throw 'Expected lint result, got null' }
if (-not $wellFormedResult.PSObject.Properties.Name -contains 'findings') { throw 'Expected findings property in lint result' }
Write-Host ("  lint result: lintPassed={0} findings={1}" -f $wellFormedResult.lintPassed, @($wellFormedResult.findings).Count) -ForegroundColor DarkGray

Write-Step 'Roadmap linter — smoke: lint a malformed roadmap detects errors'
$malformedContent = @"
## Release Bad Heading

- [] malformed checkbox
- [ ] valid item
"@
$malformedResult = Invoke-LintRoadmapContent -RawContent $malformedContent -RepoName 'smoke-lint-malformed'
$lintErrors = @($malformedResult.findings | Where-Object { $_.severity -eq 'error' })
if ($lintErrors.Count -eq 0) { throw 'Expected at least one error finding for malformed roadmap' }
Write-Host ("  malformed roadmap: errorCount={0} lintPassed={1}" -f $lintErrors.Count, $malformedResult.lintPassed) -ForegroundColor DarkGray

Write-Step 'Loading maturity drift monitor module (Release 1.1)'
$maturityDriftPath = Join-Path $WorkspaceRoot 'backend\modules\roadmap\MaturityDrift.Monitor.ps1'
if (-not (Test-Path -LiteralPath $maturityDriftPath)) { throw "MaturityDrift.Monitor.ps1 not found at: $maturityDriftPath" }
. $maturityDriftPath
Write-Host 'Maturity drift monitor module loaded successfully' -ForegroundColor Green

Write-Step 'Maturity drift monitor — smoke: set baseline and detect drift'
$driftWs = Join-Path $WorkspaceRoot 'output\smoke\module\drift'
$null = New-Item -ItemType Directory -Path (Join-Path $driftWs 'output') -Force -ErrorAction SilentlyContinue
$baselineResult = Set-MaturityBaseline -WorkspaceRoot $driftWs -RepoName 'smoke-drift-repo' -TargetLevel 'L3-Contract-Ready'
if (-not $baselineResult.persisted) { throw "Expected baseline to be persisted, got persisted=$($baselineResult.persisted)" }
Write-Host ("  baseline set: repoName={0} targetLevel={1}" -f $baselineResult.repoName, $baselineResult.targetLevel) -ForegroundColor DarkGray

$smokeAuditEntries = @(
    [PSCustomObject]@{
        repoName = 'smoke-drift-repo'; maturityLevel = 'L1-Informal'; maturityScore = 30
    }
)
$driftResult = Get-MaturityDrift -WorkspaceRoot $driftWs -CurrentAuditEntries $smokeAuditEntries
if ($driftResult.driftCount -ne 1) { throw "Expected 1 drift alert, got $($driftResult.driftCount)" }
$alert = $driftResult.driftAlerts | Select-Object -First 1
if ($alert.driftSeverity -notin @('warning','critical')) { throw "Expected driftSeverity warning or critical, got $($alert.driftSeverity)" }
Write-Host ("  drift detected: repoName={0} severity={1}" -f $alert.repoName, $alert.driftSeverity) -ForegroundColor DarkGray

Write-Step 'Loading doc standardization previewer module (Release 1.1)'
$docStdPath = Join-Path $WorkspaceRoot 'backend\modules\docstandardization\DocStandardization.Previewer.ps1'
if (-not (Test-Path -LiteralPath $docStdPath)) { throw "DocStandardization.Previewer.ps1 not found at: $docStdPath" }
. $docStdPath
Write-Host 'Doc standardization previewer module loaded successfully' -ForegroundColor Green

Write-Step 'Doc standardization — smoke: preview for repo without README'
$missingReadmeRepoPath = Join-Path $WorkspaceRoot 'output\smoke\module\missing-readme-repo'
$stdPreviewMissing = Invoke-PreviewReadmeStandardization -RepoName 'smoke-std-no-readme' -RepoPath $missingReadmeRepoPath
if ($null -eq $stdPreviewMissing) { throw 'Expected preview result, got null' }
Write-Host ("  preview (no README): previewState={0} actions={1}" -f $stdPreviewMissing.previewState, @($stdPreviewMissing.standardizationActions).Count) -ForegroundColor DarkGray

Write-Step 'Doc standardization — smoke: preview for repo with partial README'
$partialReadme = "# My Repo`n`nThis is a description."
$stdPreviewPartial = Invoke-PreviewReadmeStandardization -RepoName 'smoke-std-partial' -RawContent $partialReadme
if ($stdPreviewPartial.previewState -eq 'already-standard') { throw 'Expected non-standard state for partial README' }
if ([string]::IsNullOrWhiteSpace($stdPreviewPartial.proposedContent)) { throw 'Expected proposedContent to be populated for partial README' }
Write-Host ("  preview (partial README): previewState={0} actions={1}" -f $stdPreviewPartial.previewState, @($stdPreviewPartial.standardizationActions).Count) -ForegroundColor DarkGray

Write-Step 'Loading notification hub module (Release 1.1)'
$notificationHubPath = Join-Path $WorkspaceRoot 'backend\modules\common\NotificationHub.ps1'
if (-not (Test-Path -LiteralPath $notificationHubPath)) { throw "NotificationHub.ps1 not found at: $notificationHubPath" }
. $notificationHubPath
Write-Host 'Notification hub module loaded successfully' -ForegroundColor Green

Write-Step 'Notification hub — smoke: register and retrieve webhooks'
$notifWs = Join-Path $WorkspaceRoot 'output\smoke\module\notifications'
$null = New-Item -ItemType Directory -Path (Join-Path $notifWs 'output') -Force -ErrorAction SilentlyContinue
$webhook = Register-NotificationWebhook -WorkspaceRoot $notifWs -WebhookUrl 'https://example.com/webhook' -Events @('scan.completed','execution.failed') -Label 'Smoke Test Webhook'
if ([string]::IsNullOrWhiteSpace($webhook.id)) { throw 'Expected webhook id to be populated' }
$webhooks = Get-NotificationWebhooks -WorkspaceRoot $notifWs
if (@($webhooks).Count -eq 0) { throw 'Expected at least one webhook after registration' }
$removeResult = Remove-NotificationWebhook -WorkspaceRoot $notifWs -WebhookId $webhook.id
if (-not $removeResult.success) { throw "Expected webhook removal to succeed, got success=$($removeResult.success)" }
Write-Host ("  webhook register/get/remove smoke ok: id={0}" -f $webhook.id) -ForegroundColor DarkGray

Write-Step 'Notification hub — smoke: URL validation guard'
$invalidUrlRejected = $false
try {
    $null = Register-NotificationWebhook -WorkspaceRoot $notifWs -WebhookUrl 'file:///etc/passwd' -Events @('scan.completed') -Label 'Bad URL'
} catch {
    $invalidUrlRejected = $true
}
if (-not $invalidUrlRejected) { throw 'Expected Register-NotificationWebhook to reject a non-HTTP(S) URL' }
Write-Host '  invalid URL correctly rejected' -ForegroundColor DarkGray

Write-Step 'Notification hub — smoke: unknown event type guard'
$unknownEventRejected = $false
try {
    $null = Register-NotificationWebhook -WorkspaceRoot $notifWs -WebhookUrl 'https://example.com/hook' -Events @('unknown.event') -Label 'Bad Event'
} catch {
    $unknownEventRejected = $true
}
if (-not $unknownEventRejected) { throw 'Expected Register-NotificationWebhook to reject an unknown event name' }
Write-Host '  unknown event name correctly rejected' -ForegroundColor DarkGray

Write-Step 'Execution ledger — smoke: case-insensitive duplicate task guard'
$ciDedupWs = Join-Path $WorkspaceRoot 'output\smoke\module\execution-ci'
$null = New-Item -ItemType Directory -Path (Join-Path $ciDedupWs 'output\execution') -Force -ErrorAction SilentlyContinue
# Remove stale ledger so this step is idempotent across repeated smoke runs
$ciDedupLedgerFile = Join-Path $ciDedupWs 'output\execution\execution-ledger.json'
if (Test-Path -LiteralPath $ciDedupLedgerFile) { Remove-Item -LiteralPath $ciDedupLedgerFile -Force }
$ciDedupDocs = @(
    [pscustomobject]@{ repoName = 'ci-repo-a'; repoPath = '/tmp/ci-a'; dispatchReadiness = 'ready'; nextPendingRoadmapItem = 'Implement feature X' },
    [pscustomobject]@{ repoName = 'ci-repo-b'; repoPath = '/tmp/ci-b'; dispatchReadiness = 'ready'; nextPendingRoadmapItem = 'Implement Feature X' }
)
$ciDedupLedger = Sync-LedgerFromAudit -WorkspaceRoot $ciDedupWs -DocAuditEntries $ciDedupDocs
$assignCiA = Invoke-AssignLane -WorkspaceRoot $ciDedupWs -RepoName 'ci-repo-a' -TaskText 'Implement feature X'
if (-not $assignCiA.success) { throw "Expected ci-repo-a lane assignment to succeed: $($assignCiA.error)" }
$assignCiB = Invoke-AssignLane -WorkspaceRoot $ciDedupWs -RepoName 'ci-repo-b' -TaskText 'Implement Feature X'
if ($assignCiB.success) { throw 'Expected ci-repo-b lane assignment to be rejected due to case-insensitive task duplicate guard' }
Write-Host '  case-insensitive duplicate task guard working correctly' -ForegroundColor DarkGray

Write-Step 'Roadmap linter — smoke: oversized content truncation guard'
$bigContent = ("## Release 0.1 — Test`n" + ("- [ ] Item`n" * 6000))
$bigLintResult = Invoke-LintRoadmapContent -RawContent $bigContent -RepoName 'smoke-lint-oversized'
if ($null -eq $bigLintResult) { throw 'Expected lint result for oversized content, got null' }
$sizeWarning = @($bigLintResult.findings | Where-Object { $_.ruleId -eq 'LINT-SIZE' })
if ($sizeWarning.Count -eq 0) { throw 'Expected LINT-SIZE warning for oversized roadmap content' }
Write-Host ("  oversized content guard working: findings={0}" -f $bigLintResult.findings.Count) -ForegroundColor DarkGray

# ---------------------------------------------------------------------------
# Release 1.7.5 — Portfolio Assessment module
# ---------------------------------------------------------------------------

Write-Step 'Portfolio assessment — smoke: load module + standards'
$portfolioModule = Join-Path $WorkspaceRoot 'backend\modules\portfolio\Portfolio.Assessment.ps1'
$portfolioValueModule = Join-Path $WorkspaceRoot 'backend\modules\portfolio\Portfolio.ValueScorer.ps1'
$portfolioStandards = Join-Path $WorkspaceRoot 'backend\config\repo-structure-standards.json'
$portfolioValueConfigPath = Join-Path $WorkspaceRoot 'backend\config\value-scoring.json'
if (-not (Test-Path -LiteralPath $portfolioModule)) { throw "Missing module file: $portfolioModule" }
if (-not (Test-Path -LiteralPath $portfolioValueModule)) { throw "Missing module file: $portfolioValueModule" }
if (-not (Test-Path -LiteralPath $portfolioStandards)) { throw "Missing standards file: $portfolioStandards" }
if (-not (Test-Path -LiteralPath $portfolioValueConfigPath)) { throw "Missing value-scoring config: $portfolioValueConfigPath" }
. $portfolioValueModule
. $portfolioModule
$structStds = Get-RepoStructureStandards -StandardsPath $portfolioStandards
$valueScoringConfig = Get-PortfolioValueScoringConfig -ConfigPath $portfolioValueConfigPath
if ($null -eq $structStds) { throw 'Get-RepoStructureStandards returned null for an existing standards file' }
if ($null -eq $structStds.common) { throw 'Standards file is missing the common section' }
if ($null -eq $valueScoringConfig) { throw 'Get-PortfolioValueScoringConfig returned null for an existing config file' }
# repo-structure-standards.json renamed 'version' to 'schemaVersion' in the v1 schema;
# accept either so the smoke works against old and new standards files.
$structStdsVersion = if ($structStds.PSObject.Properties.Name -contains 'schemaVersion') { [string]$structStds.schemaVersion } elseif ($structStds.PSObject.Properties.Name -contains 'version') { [string]$structStds.version } else { '(none)' }
Write-Host ("  standards loaded version={0} commonRequired={1}" -f $structStdsVersion, @($structStds.common.requiredRootFiles).Count) -ForegroundColor DarkGray

Write-Step 'Portfolio assessment — smoke: structure audit on workspace itself'
$selfAudit = Invoke-RepoStructureAudit -RepoPath $WorkspaceRoot -Standards $structStds
if ($null -eq $selfAudit) { throw 'Invoke-RepoStructureAudit returned null on workspace' }
if ($selfAudit.repoType -ne 'node') { throw "Expected workspace repoType=node (package.json present), got '$($selfAudit.repoType)'" }
Write-Host ("  workspace audit: type={0} missing={1} ci={2} tests={3}" -f $selfAudit.repoType, $selfAudit.missingCount, $selfAudit.hasCiSignal, $selfAudit.hasTestSignal) -ForegroundColor DarkGray

Write-Step 'Portfolio assessment — smoke: malformed standards object falls through gracefully'
$malformedAudit = Invoke-RepoStructureAudit -RepoPath $WorkspaceRoot -Standards ([pscustomobject]@{ version = '0.0' })
if ($null -eq $malformedAudit)             { throw 'Expected non-null audit result for malformed standards' }
if ($malformedAudit.missingCount -ne 0)    { throw "Expected missingCount=0 when 'common' section is absent, got $($malformedAudit.missingCount)" }
if (@($malformedAudit.findings).Count -ne 0) { throw 'Expected zero findings when standards object lacks common section' }
Write-Host '  malformed standards correctly degraded to empty findings' -ForegroundColor DarkGray

Write-Step 'Portfolio assessment — smoke: lifecycle precedence (archived overrides everything)'
$archivedRepo = [pscustomobject]@{ name = 'arch-repo'; localPath = $WorkspaceRoot; isArchived = $true; htmlUrl = 'https://github.com/x/arch-repo'; branch = 'main'; status = 'clean' }
$archivedAssess = Invoke-PortfolioAssessment -LocalRepos @($archivedRepo) -StructureStandards $structStds
if (@($archivedAssess).Count -ne 1) { throw "Expected 1 assessment for archived repo, got $(@($archivedAssess).Count)" }
if ($archivedAssess[0].lifecycleState -ne 'archived') { throw "Archived precedence broken: expected 'archived', got '$($archivedAssess[0].lifecycleState)'" }
Write-Host '  archived precedence correct' -ForegroundColor DarkGray

Write-Step 'Portfolio assessment — smoke: lifecycle precedence (parse-error)'
$parseErrRepo = [pscustomobject]@{ name = 'parse-err-repo'; localPath = $WorkspaceRoot; isArchived = $false; htmlUrl = ''; branch = 'main'; status = 'clean' }
$parseErrRoadmap = @([pscustomobject]@{ repoName = 'parse-err-repo'; roadmapPath = (Join-Path $WorkspaceRoot 'ROADMAP.md'); roadmapState = 'parse-error'; pendingCount = 0 })
$parseErrAssess = Invoke-PortfolioAssessment -LocalRepos @($parseErrRepo) -RoadmapEntries $parseErrRoadmap -StructureStandards $structStds
if ($parseErrAssess[0].lifecycleState -ne 'parse-error') { throw "Parse-error precedence broken: expected 'parse-error', got '$($parseErrAssess[0].lifecycleState)'" }
Write-Host '  parse-error precedence correct' -ForegroundColor DarkGray

Write-Step 'Portfolio assessment — smoke: lifecycle precedence (running execution state)'
$runningRepo = [pscustomobject]@{ name = 'running-repo'; localPath = $WorkspaceRoot; isArchived = $false; htmlUrl = ''; branch = 'main'; status = 'clean' }
$runningExec = @([pscustomobject]@{ repoName = 'running-repo'; executionState = 'running' })
$runningAssess = Invoke-PortfolioAssessment -LocalRepos @($runningRepo) -ExecutionEntries $runningExec -StructureStandards $structStds
if ($runningAssess[0].lifecycleState -ne 'running') { throw "Running precedence broken: expected 'running', got '$($runningAssess[0].lifecycleState)'" }
Write-Host '  running precedence correct' -ForegroundColor DarkGray

Write-Step 'Portfolio assessment — smoke: GitHub-only repo classified with sourceCoverage=github'
$ghOnlyRepos = @([pscustomobject]@{ name = 'remote-only'; htmlUrl = 'https://github.com/x/remote-only'; branch = 'main'; isArchived = $false })
$ghOnlyAssess = Invoke-PortfolioAssessment -LocalRepos @() -GitHubRepos $ghOnlyRepos -StructureStandards $structStds
if (@($ghOnlyAssess).Count -ne 1)                          { throw "Expected 1 GitHub-only assessment, got $(@($ghOnlyAssess).Count)" }
if ($ghOnlyAssess[0].sourceCoverage -ne 'github')           { throw "Expected sourceCoverage=github, got '$($ghOnlyAssess[0].sourceCoverage)'" }
if ($ghOnlyAssess[0].lifecycleState -ne 'discovered')       { throw "Expected lifecycleState=discovered for GitHub-only, got '$($ghOnlyAssess[0].lifecycleState)'" }
if ($ghOnlyAssess[0].recommendedAction -notmatch 'Clone')   { throw "Expected GitHub-only recommendedAction to mention Clone, got '$($ghOnlyAssess[0].recommendedAction)'" }
Write-Host '  GitHub-only sourceCoverage correct' -ForegroundColor DarkGray

Write-Step 'Portfolio assessment — smoke: source coverage = local+github when repo present in both'
$bothRepos = @([pscustomobject]@{ name = 'shared'; localPath = $WorkspaceRoot; isArchived = $false; htmlUrl = ''; branch = 'main'; status = 'clean' })
$bothGh    = @([pscustomobject]@{ name = 'shared'; htmlUrl = 'https://github.com/x/shared' })
$bothAssess = Invoke-PortfolioAssessment -LocalRepos $bothRepos -GitHubRepos $bothGh -StructureStandards $structStds
if (@($bothAssess).Count -ne 1)                  { throw "Expected single dedupe-merged assessment, got $(@($bothAssess).Count)" }
if ($bothAssess[0].sourceCoverage -ne 'local+github') { throw "Expected sourceCoverage=local+github, got '$($bothAssess[0].sourceCoverage)'" }
Write-Host '  local+github source coverage correct' -ForegroundColor DarkGray

Write-Step 'Portfolio value scoring — smoke: security/test work ranks above generic chores'
$highValue = Invoke-PortfolioValueScore `
    -ItemText 'Add API authentication and contract smoke tests for dispatch endpoints' `
    -Section 'Engineering milestones' `
    -Tags @('security','testing') `
    -ItemIndex 0 `
    -RepoContext ([pscustomobject]@{ maturityLevel = 'L4-Orchestration-Ready' }) `
    -ScoringConfig $valueScoringConfig
$lowValue = Invoke-PortfolioValueScore `
    -ItemText 'Polish miscellaneous wording in old docs' `
    -Section 'Backlog' `
    -Tags @() `
    -ItemIndex 8 `
    -RepoContext ([pscustomobject]@{ maturityLevel = 'L1-Informal' }) `
    -ScoringConfig $valueScoringConfig
if ($highValue.valueScore -le $lowValue.valueScore) { throw "Expected security/test work score to exceed generic docs work; high=$($highValue.valueScore) low=$($lowValue.valueScore)" }
if (@($highValue.valueRationale).Count -eq 0) { throw 'Expected value-scored item to include rationale' }
Write-Host ("  value scorer ranked high={0} low={1}" -f $highValue.valueScore, $lowValue.valueScore) -ForegroundColor DarkGray

Write-Step 'Portfolio value scoring — smoke: effortFit floor for sprawling items (Release 2.7 Phase A decision, model 1.1)'
$sprawlItem = Invoke-PortfolioValueScore `
    -ItemText 'Add a persistent OAuth distribution analytics layer' `
    -ItemIndex 0 `
    -RepoContext ([pscustomobject]@{ maturityLevel = 'L4-Orchestration-Ready' }) `
    -ScoringConfig $valueScoringConfig
$boundedItem = Invoke-PortfolioValueScore `
    -ItemText 'Add repo status tests' `
    -ItemIndex 0 `
    -RepoContext ([pscustomobject]@{ maturityLevel = 'L4-Orchestration-Ready' }) `
    -ScoringConfig $valueScoringConfig
if ([int]$sprawlItem.scoringSignals.dimensions.effortFit -ne 2) { throw "Expected effortFit floor=2 for sprawling item; got $($sprawlItem.scoringSignals.dimensions.effortFit)" }
if ([int]$boundedItem.scoringSignals.dimensions.effortFit -ne 4) { throw "Expected effortFit=4 for bounded item; got $($boundedItem.scoringSignals.dimensions.effortFit)" }
if ($sprawlItem.scoringSignals.dimensions.effortFit -ge $boundedItem.scoringSignals.dimensions.effortFit) { throw 'effortFit floor did not penalize the sprawling item below the bounded item' }
Write-Host ("  effortFit floor ok: sprawl effortFit={0} < bounded effortFit={1} (model {2})" -f $sprawlItem.scoringSignals.dimensions.effortFit, $boundedItem.scoringSignals.dimensions.effortFit, $valueScoringConfig.modelVersion) -ForegroundColor DarkGray

Write-Step 'Portfolio assessment — smoke: ready-for-work fires on L4 + pending items'
$readyRepo = [pscustomobject]@{ name = 'ready-repo'; localPath = $WorkspaceRoot; isArchived = $false; htmlUrl = ''; branch = 'main'; status = 'clean' }
$readyRoadmap = @([pscustomobject]@{
    repoName = 'ready-repo'
    roadmapPath = (Join-Path $WorkspaceRoot 'ROADMAP.md')
    roadmapState = 'pending'
    pendingCount = 5
    nextPendingItem = [pscustomobject]@{ text = 'next thing' }
    activeRelease = [pscustomobject]@{ releaseName = 'Release 2.0 — Dispatch Budgets'; releaseVersion = '2.0'; releaseTitle = 'Dispatch Budgets' }
    activePhasePlan = [pscustomobject]@{ phaseName = 'Phase 2: Quota guard'; workUnitsEstimated = 8 }
    budgetGuardrail = [pscustomobject]@{ estimatedReleaseWorkUnits = 18; maxUnitsPerPhase = 10; present = $true }
    estimatedSessionWorkUnits = 8
})
$readyMaturity = @([pscustomobject]@{
    repoName = 'ready-repo'
    maturityLevel = 'L4-Orchestration-Ready'
    maturityScore = 100
    sections = @(
        [pscustomobject]@{ name = 'Engineering milestones'; pendingItems = @('Add API authentication and contract smoke tests for dispatch endpoints', 'Polish miscellaneous wording in old docs'); completedItems = @() }
    )
})
$readyAssess = Invoke-PortfolioAssessment -LocalRepos @($readyRepo) -RoadmapEntries $readyRoadmap -RoadmapAuditEntries $readyMaturity -StructureStandards $structStds -ValueScoringConfig $valueScoringConfig
if ($readyAssess[0].lifecycleState -ne 'ready-for-work') { throw "Expected lifecycleState=ready-for-work for L4 + pending, got '$($readyAssess[0].lifecycleState)'" }
if ($readyAssess[0].pendingItemCount -ne 5)              { throw "Expected pendingItemCount=5, got $($readyAssess[0].pendingItemCount)" }
if (@($readyAssess[0].pendingItems).Count -ne 2)         { throw "Expected 2 scored pendingItems, got $(@($readyAssess[0].pendingItems).Count)" }
if ($null -eq $readyAssess[0].topValueItem)              { throw 'Expected topValueItem to be populated for ready repo with pending items' }
if ($readyAssess[0].topValueItem.text -notmatch 'authentication') { throw "Expected topValueItem to select authentication/test work, got '$($readyAssess[0].topValueItem.text)'" }
if ([double]$readyAssess[0].estimatedSessionWorkUnits -ne 8) { throw "Expected estimatedSessionWorkUnits=8, got '$($readyAssess[0].estimatedSessionWorkUnits)'" }
if ([string]$readyAssess[0].activePhasePlan.phaseName -ne 'Phase 2: Quota guard') { throw "Expected activePhasePlan.phaseName='Phase 2: Quota guard', got '$($readyAssess[0].activePhasePlan.phaseName)'" }
Write-Host '  ready-for-work classification correct' -ForegroundColor DarkGray

Write-Step 'Portfolio assessment — smoke: summary aggregator counts lifecycle states'
$mixedAssess = @($archivedAssess[0], $parseErrAssess[0], $runningAssess[0], $ghOnlyAssess[0], $bothAssess[0], $readyAssess[0])
$summary = Get-PortfolioAssessmentSummary -Assessments $mixedAssess
if ($summary.totalRepos -ne 6)                  { throw "Expected totalRepos=6, got $($summary.totalRepos)" }
if ($summary.byLifecycle['archived'] -ne 1)     { throw "Expected byLifecycle[archived]=1, got $($summary.byLifecycle['archived'])" }
if ($summary.byLifecycle['parse-error'] -ne 1)  { throw "Expected byLifecycle[parse-error]=1, got $($summary.byLifecycle['parse-error'])" }
if ($summary.byLifecycle['running'] -ne 1)      { throw "Expected byLifecycle[running]=1, got $($summary.byLifecycle['running'])" }
if ($summary.byLifecycle['ready-for-work'] -ne 1) { throw "Expected byLifecycle[ready-for-work]=1, got $($summary.byLifecycle['ready-for-work'])" }
if ($summary.bySourceCoverage['github'] -ne 1)  { throw "Expected bySourceCoverage[github]=1, got $($summary.bySourceCoverage['github'])" }
if ($summary.bySourceCoverage['local+github'] -lt 1) { throw "Expected bySourceCoverage[local+github] >= 1, got $($summary.bySourceCoverage['local+github'])" }
Write-Host ("  summary aggregation correct: total={0} ready={1} running={2} blocked={3}" -f $summary.totalRepos, $summary.readyForWorkCount, $summary.runningCount, $summary.blockedCount) -ForegroundColor DarkGray

# ---------------------------------------------------------------------------
# Release 2.3 Phase 5 — Repository curation and change-aware indexing
# ---------------------------------------------------------------------------

Write-Step 'Portfolio curation — smoke: stable repoId prefers durable identity over scan fingerprint'
$stableId = Get-PortfolioRepoId -ScanFingerprint 'volatile-hash-abc' -LocalPath 'C:\Repos\Sample' -GitHubFullName 'owner/sample' -RepoName 'Sample'
if ($stableId -ne 'path:c:\repos\sample') { throw "Expected repoId 'path:c:\repos\sample' (stable identity), got '$stableId'" }
$ghId = Get-PortfolioRepoId -ScanFingerprint 'volatile-hash-abc' -GitHubFullName 'Owner/Sample'
if ($ghId -ne 'gh:owner/sample') { throw "Expected repoId 'gh:owner/sample' for GitHub-only identity, got '$ghId'" }
$nameId = Get-PortfolioRepoId -ScanFingerprint 'volatile-hash-abc' -RepoName 'Sample'
if ($nameId -ne 'repo:sample') { throw "Expected repoId 'repo:sample' for name-only identity, got '$nameId'" }
$fingerprintId = Get-PortfolioRepoId -ScanFingerprint 'volatile-hash-abc'
if ($fingerprintId -ne 'volatile-hash-abc') { throw "Expected fingerprint fallback when no stable key exists, got '$fingerprintId'" }
Write-Host '  repoId identity precedence correct: path > github > name > fingerprint' -ForegroundColor DarkGray

Write-Step 'Portfolio curation — smoke: load module + validate state vocabulary'
$curationModule = Join-Path $WorkspaceRoot 'backend\modules\portfolio\Portfolio.Curation.ps1'
if (-not (Test-Path -LiteralPath $curationModule)) { throw "Missing module file: $curationModule" }
. $curationModule
foreach ($validState in @('none', 'favorite', 'portfolio-candidate', 'archived-ignore')) {
    if (-not (Test-ValidCurationState -CurationState $validState)) { throw "Expected '$validState' to be a valid curation state" }
}
foreach ($invalidState in @('', 'starred', 'FAVOURITE-ish', 'archive')) {
    if (Test-ValidCurationState -CurationState $invalidState) { throw "Expected '$invalidState' to be rejected as a curation state" }
}
Write-Host '  curation state vocabulary validation correct' -ForegroundColor DarkGray

Write-Step 'Portfolio curation — smoke: persistence round-trip survives re-read (restart proxy)'
$curationWs = Join-Path ([System.IO.Path]::GetTempPath()) ("curation-smoke-" + [guid]::NewGuid().ToString('n').Substring(0, 8))
New-Item -ItemType Directory -Path $curationWs -Force | Out-Null
try {
    $writeFav = Set-PortfolioRepoCurationState -WorkspaceRoot $curationWs -RepoId 'path:c:\repos\sample' -CurationState 'favorite' -Reason 'smoke'
    if (-not $writeFav.success) { throw "Expected favorite curation write to succeed: $($writeFav.error)" }
    $writeBad = Set-PortfolioRepoCurationState -WorkspaceRoot $curationWs -RepoId 'path:c:\repos\sample' -CurationState 'not-a-state'
    if ($writeBad.success) { throw 'Expected invalid curation state write to be rejected' }

    $mirrorPath = Get-PortfolioCurationFilePath -WorkspaceRoot $curationWs
    if (-not (Test-Path -LiteralPath $mirrorPath)) { throw "Curation file mirror was not written at $mirrorPath" }

    # Fresh map read from disk models a process restart: no in-memory state survives.
    $rereadMap = Get-PortfolioCurationMap -WorkspaceRoot $curationWs
    if (-not $rereadMap.ContainsKey('path:c:\repos\sample')) { throw 'Curation entry missing after re-read from disk' }
    if ([string]$rereadMap['path:c:\repos\sample'].curationState -ne 'favorite') { throw "Expected persisted state 'favorite', got '$($rereadMap['path:c:\repos\sample'].curationState)'" }

    $curationEntries = @(
        [pscustomobject]@{ repoId = 'path:c:\repos\sample'; repoName = 'sample' },
        [pscustomobject]@{ repoId = 'path:c:\repos\other'; repoName = 'other' }
    )
    $applied = Apply-PortfolioCurationToEntries -Entries $curationEntries -CurationMap $rereadMap
    if ([string]$applied[0].curationState -ne 'favorite') { throw "Expected merged curationState=favorite on matching entry, got '$($applied[0].curationState)'" }
    if ([string]::IsNullOrWhiteSpace([string]$applied[0].curationUpdatedAt)) { throw 'Expected curationUpdatedAt to be populated on curated entry' }
    if ([string]$applied[1].curationState -ne 'none') { throw "Expected curationState=none on uncurated entry, got '$($applied[1].curationState)'" }

    $writeClear = Set-PortfolioRepoCurationState -WorkspaceRoot $curationWs -RepoId 'path:c:\repos\sample' -CurationState 'none'
    if (-not $writeClear.success) { throw "Expected curation clear to succeed: $($writeClear.error)" }
    $clearedMap = Get-PortfolioCurationMap -WorkspaceRoot $curationWs
    if ([string]$clearedMap['path:c:\repos\sample'].curationState -ne 'none') { throw 'Expected cleared curation state to persist as none' }
    Write-Host '  curation persistence round-trip correct (write, restart re-read, merge, clear)' -ForegroundColor DarkGray
}
finally {
    Remove-Item -LiteralPath $curationWs -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Step 'Loading agent-runs ledger module (Release 2.0)'
$agentRunsModule = Join-Path $WorkspaceRoot 'backend\modules\agent-runs\AgentRuns.ps1'
if (-not (Test-Path -LiteralPath $agentRunsModule)) { throw "AgentRuns.ps1 not found at: $agentRunsModule" }
. $agentBudgetModule
. $agentRunsModule
Write-Host 'Agent-runs module loaded successfully' -ForegroundColor Green

Write-Step 'Agent-run ledger — smoke: create, list, detail, update (Release 2.0 Phase 1)'
$agentRunsWorkspace = Join-Path ([System.IO.Path]::GetTempPath()) ("agent-runs-smoke-" + [guid]::NewGuid().ToString('n').Substring(0, 8))
New-Item -ItemType Directory -Path $agentRunsWorkspace -Force | Out-Null
try {
    $smokeRun = New-AgentRunRecord -WorkspaceRoot $agentRunsWorkspace -RepoName 'smoke-agent-repo' `
        -GitHubRepo 'owner/smoke-agent-repo' -DispatchRunId 'dispatch-123' -PromptRefinementRunId 'refine-456' `
        -SelectedTaskText 'Add quota guard' -SelectedTaskSection 'Engineering milestones' `
        -PlannedReleaseName 'Release 2.0 — Agent Run Monitoring and Actions-Gated Merge Readiness' `
        -PlannedPhaseName 'Phase 4: Budget guard + scan annotations' `
        -BaseBranch 'main' -WorkUnitsEstimated 8 -WorkUnitsEstimateSource 'roadmap-phase-plan'
    if ([string]::IsNullOrWhiteSpace([string]$smokeRun.runId)) { throw 'New-AgentRunRecord returned no runId' }
    if ([string]$smokeRun.status -ne 'dispatched') { throw "Expected status=dispatched, got '$($smokeRun.status)'" }
    if ($null -eq $smokeRun.metrics.dispatchedAt) { throw 'New run is missing metrics.dispatchedAt' }
    if ([double]$smokeRun.metrics.workUnitsEstimated -ne 8) { throw "Expected workUnitsEstimated=8, got '$($smokeRun.metrics.workUnitsEstimated)'" }
    if ([string]$smokeRun.workUnitsEstimateSource -ne 'roadmap-phase-plan') { throw "Expected workUnitsEstimateSource='roadmap-phase-plan', got '$($smokeRun.workUnitsEstimateSource)'" }
    if ([string]$smokeRun.plannedPhaseName -ne 'Phase 4: Budget guard + scan annotations') { throw "Expected plannedPhaseName to be recorded, got '$($smokeRun.plannedPhaseName)'" }

    $runFile = Join-Path $agentRunsWorkspace "output\agent-runs\runs\$($smokeRun.runId).json"
    if (-not (Test-Path -LiteralPath $runFile)) { throw 'Run ledger JSON was not written' }
    $eventsFile = Join-Path $agentRunsWorkspace 'output\agent-runs\events.jsonl'
    if (-not (Test-Path -LiteralPath $eventsFile)) { throw 'events.jsonl was not written' }

    $listed = @(Get-AgentRuns -WorkspaceRoot $agentRunsWorkspace -Status 'dispatched')
    if ($listed.Count -ne 1) { throw "Expected 1 dispatched run in list, got $($listed.Count)" }
    if (@(Get-AgentRuns -WorkspaceRoot $agentRunsWorkspace -Status 'completed').Count -ne 0) { throw 'Status filter returned a non-matching run' }

    $startedIso = (Get-Date).ToUniversalTime().AddMinutes(-10).ToString('o')
    $completedIso = (Get-Date).ToUniversalTime().ToString('o')
    $updated = Update-AgentRunRecord -WorkspaceRoot $agentRunsWorkspace -RunId $smokeRun.runId -Patch @{
        status           = 'completed'
        outcome          = 'pr-opened'
        branch           = 'copilot/smoke-fix'
        prUrl            = 'https://github.com/owner/smoke-agent-repo/pull/1'
        agentStartedAt   = $startedIso
        agentCompletedAt = $completedIso
        workUnitsActual  = 3
    }
    if ([string]$updated.status -ne 'completed') { throw "Expected status=completed after update, got '$($updated.status)'" }
    if ($null -eq $updated.metrics.timeToDeliverSeconds -or [int]$updated.metrics.timeToDeliverSeconds -lt 1) { throw 'timeToDeliverSeconds was not derived from start/completion timestamps' }

    $detail = Get-AgentRunDetail -WorkspaceRoot $agentRunsWorkspace -RunId $smokeRun.runId
    if ($null -eq $detail) { throw 'Get-AgentRunDetail returned null for an existing run' }
    if ([string]$detail.run.prUrl -ne 'https://github.com/owner/smoke-agent-repo/pull/1') { throw 'Run detail did not persist the PR URL' }
    $detailEventTypes = @($detail.events | ForEach-Object { [string]$_.eventType })
    if ('run.dispatched' -notin $detailEventTypes) { throw 'events stream is missing run.dispatched' }
    if ('run.completed' -notin $detailEventTypes) { throw 'events stream is missing run.completed' }

    if ($null -ne (Get-AgentRunDetail -WorkspaceRoot $agentRunsWorkspace -RunId 'does-not-exist')) { throw 'Get-AgentRunDetail should return null for an unknown runId' }

    $invalidStatusRejected = $false
    try { $null = Update-AgentRunRecord -WorkspaceRoot $agentRunsWorkspace -RunId $smokeRun.runId -Patch @{ status = 'bogus' } } catch { $invalidStatusRejected = $true }
    if (-not $invalidStatusRejected) { throw 'Update-AgentRunRecord accepted an invalid status' }

    Write-Step 'Budget ledger — smoke: defaults, usage snapshot, soft warning, hard refusal (Release 2.0 Phase 4)'
    $budgetConfig = Get-AgentBudgetLedgerConfig -WorkspaceRoot $agentRunsWorkspace -Settings @{
        budgetLedger = @{
            period = (Get-Date).ToUniversalTime().ToString('yyyy-MM')
            quotaGuard = @{
                softStopRemainingUnits = 10
                hardStopRemainingUnits = 5
                maxUnitsPerPhase = 25
                maxUnitsPerSession = 12
            }
            defaultProject = @{
                monthlyQuotaBudgetUnits = 20
                monthlyBudgetUsd = 6
                priority = 1
            }
        }
    }
    $usageSnapshot = Get-AgentBudgetUsageSnapshot -WorkspaceRoot $agentRunsWorkspace -BudgetConfig $budgetConfig
    if (-not $usageSnapshot.byRepo.ContainsKey('smoke-agent-repo')) { throw 'Expected usage snapshot to include smoke-agent-repo' }
    if ([double]$usageSnapshot.byRepo['smoke-agent-repo'].unitsConsumed -lt 3) { throw 'Usage snapshot did not count the existing run units' }

    $softWarning = Test-AgentDispatchQuota -WorkspaceRoot $agentRunsWorkspace -RepoName 'smoke-agent-repo' -EstimatedWorkUnits 7 -BudgetConfig $budgetConfig -PlannedPhaseName 'Phase 4'
    if (-not $softWarning.allowed) { throw "Expected soft-warning dispatch to remain allowed, got blocked: $($softWarning.message)" }
    if (@($softWarning.warnings).Count -eq 0) { throw 'Expected soft-warning dispatch to emit a warning' }

    $hardRefusal = Test-AgentDispatchQuota -WorkspaceRoot $agentRunsWorkspace -RepoName 'smoke-agent-repo' -EstimatedWorkUnits 13 -BudgetConfig $budgetConfig -PlannedPhaseName 'Phase 4'
    if ($hardRefusal.allowed) { throw 'Expected dispatch above the per-session cap to be refused' }
    if ([string]$hardRefusal.blockedCode -ne 'session-cap-exceeded') { throw "Expected blockedCode=session-cap-exceeded, got '$($hardRefusal.blockedCode)'" }

    $creditFlagged = Update-AgentRunRecord -WorkspaceRoot $agentRunsWorkspace -RunId $smokeRun.runId -Patch @{ creditPromptSeen = $true }
    if ($creditFlagged.metrics.creditPromptSeen -ne $true) { throw 'Expected Update-AgentRunRecord to persist creditPromptSeen=true' }
    $creditBlocked = Test-AgentDispatchQuota -WorkspaceRoot $agentRunsWorkspace -RepoName 'smoke-agent-repo' -EstimatedWorkUnits 2 -BudgetConfig $budgetConfig -PlannedPhaseName 'Phase 4'
    if ($creditBlocked.allowed) { throw 'Expected credit-prompt policy to block additional dispatches' }
    if ([string]$creditBlocked.blockedCode -ne 'credit-prompt-seen') { throw "Expected blockedCode=credit-prompt-seen, got '$($creditBlocked.blockedCode)'" }
    Write-Host '  budget ledger quota guard behaves correctly' -ForegroundColor DarkGray

    Write-Host ("  agent-run ledger correct: runId={0} events={1} timeToDeliver={2}s" -f $smokeRun.runId, @($detail.events).Count, $updated.metrics.timeToDeliverSeconds) -ForegroundColor DarkGray
}
finally {
    Remove-Item -LiteralPath $agentRunsWorkspace -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Step 'Agent-run refresh — smoke: PR association, status transitions, validation events (Release 2.0 Phase 2)'
$refreshWorkspace = Join-Path ([System.IO.Path]::GetTempPath()) ("agent-runs-refresh-smoke-" + [guid]::NewGuid().ToString('n').Substring(0, 8))
New-Item -ItemType Directory -Path $refreshWorkspace -Force | Out-Null
try {
    $refreshRun = New-AgentRunRecord -WorkspaceRoot $refreshWorkspace -RepoName 'smoke-refresh-repo' `
        -GitHubRepo 'owner/smoke-refresh-repo' -SelectedTaskText 'Implement the smoke-test refresh association feature'

    $nowUtc = (Get-Date).ToUniversalTime()
    $agentPr = [pscustomobject]@{
        number     = 42
        html_url   = 'https://github.com/owner/smoke-refresh-repo/pull/42'
        state      = 'open'
        draft      = $true
        title      = 'Implement the smoke-test refresh association feature'
        body       = 'Agent-generated work'
        created_at = $nowUtc.AddMinutes(2).ToString('o')
        updated_at = $nowUtc.AddMinutes(3).ToString('o')
        merged_at  = $null
        closed_at  = $null
        head       = [pscustomobject]@{ ref = 'copilot/smoke-refresh-feature' }
    }
    $unrelatedPr = [pscustomobject]@{
        number     = 41
        html_url   = 'https://github.com/owner/smoke-refresh-repo/pull/41'
        state      = 'open'
        draft      = $false
        title      = 'Unrelated human PR'
        body       = ''
        created_at = $nowUtc.AddDays(-2).ToString('o')
        updated_at = $null
        merged_at  = $null
        closed_at  = $null
        head       = [pscustomobject]@{ ref = 'feature/manual-work' }
    }

    # Candidate selection: only the copilot/* branch created after dispatch matches.
    $candidate = Select-AgentRunPullRequestCandidate -Run $refreshRun -PullRequests @($unrelatedPr, $agentPr)
    if ($null -eq $candidate.pullRequest) { throw 'Select-AgentRunPullRequestCandidate found no candidate' }
    if ([int]$candidate.pullRequest.number -ne 42) { throw "Expected PR #42 selected, got #$($candidate.pullRequest.number)" }
    if ('copilot-branch-prefix' -notin @($candidate.evidence.matchedBy)) { throw 'Association evidence is missing copilot-branch-prefix' }
    if ('task-fingerprint' -notin @($candidate.evidence.matchedBy)) { throw 'Association evidence is missing task-fingerprint' }

    # Refresh 1: draft PR + in-progress Actions -> active, no validation event.
    $refresh1 = Invoke-AgentRunRefresh -WorkspaceRoot $refreshWorkspace -RunId $refreshRun.runId `
        -PullRequests @($unrelatedPr, $agentPr) `
        -ActionsRun ([pscustomobject]@{ status = 'in_progress'; conclusion = ''; name = 'CI Smoke'; runUrl = 'https://github.com/owner/smoke-refresh-repo/actions/runs/1' })
    if ([string]$refresh1.run.status -ne 'active') { throw "Expected status=active after draft-PR refresh, got '$($refresh1.run.status)'" }
    if ([string]$refresh1.run.branch -ne 'copilot/smoke-refresh-feature') { throw 'Refresh did not associate the agent branch' }
    if ($null -ne $refresh1.validationEvent) { throw 'In-progress Actions must not emit a validation event' }

    # Refresh 2: PR ready for review + successful Actions -> completed + validation.passed.
    $agentPr.draft = $false
    $refresh2 = Invoke-AgentRunRefresh -WorkspaceRoot $refreshWorkspace -RunId $refreshRun.runId `
        -PullRequests @($unrelatedPr, $agentPr) `
        -ActionsRun ([pscustomobject]@{ status = 'completed'; conclusion = 'success'; name = 'CI Smoke'; runUrl = 'https://github.com/owner/smoke-refresh-repo/actions/runs/2' })
    if ([string]$refresh2.run.status -ne 'completed') { throw "Expected status=completed after ready-PR refresh, got '$($refresh2.run.status)'" }
    if ([string]$refresh2.run.outcome -ne 'awaiting-merge') { throw "Expected outcome=awaiting-merge, got '$($refresh2.run.outcome)'" }
    if ([string]$refresh2.validationEvent -ne 'validation.passed') { throw "Expected validation.passed, got '$($refresh2.validationEvent)'" }
    if ('existing-pr-url' -notin @($refresh2.association.matchedBy)) { throw 'Second refresh should re-associate via existing-pr-url' }
    if ($null -eq $refresh2.run.metrics.timeToDeliverSeconds) { throw 'Refresh did not derive timeToDeliverSeconds from observed PR timing' }

    # Refresh 3: unchanged Actions conclusion must not emit a duplicate validation event.
    $refresh3 = Invoke-AgentRunRefresh -WorkspaceRoot $refreshWorkspace -RunId $refreshRun.runId `
        -PullRequests @($unrelatedPr, $agentPr) `
        -ActionsRun ([pscustomobject]@{ status = 'completed'; conclusion = 'success'; name = 'CI Smoke'; runUrl = 'https://github.com/owner/smoke-refresh-repo/actions/runs/2' })
    if ($null -ne $refresh3.validationEvent) { throw 'Unchanged Actions conclusion emitted a duplicate validation event' }

    # Refresh 4: merged PR -> outcome merged.
    $agentPr.merged_at = $nowUtc.AddMinutes(30).ToString('o')
    $refresh4 = Invoke-AgentRunRefresh -WorkspaceRoot $refreshWorkspace -RunId $refreshRun.runId -PullRequests @($agentPr)
    if ([string]$refresh4.run.status -ne 'completed') { throw "Expected status=completed after merge, got '$($refresh4.run.status)'" }
    if ([string]$refresh4.run.outcome -ne 'merged') { throw "Expected outcome=merged, got '$($refresh4.run.outcome)'" }

    $refreshDetail = Get-AgentRunDetail -WorkspaceRoot $refreshWorkspace -RunId $refreshRun.runId
    $refreshEventTypes = @($refreshDetail.events | ForEach-Object { [string]$_.eventType })
    if ('run.started' -notin $refreshEventTypes) { throw 'Refresh events stream is missing run.started' }
    if ('run.completed' -notin $refreshEventTypes) { throw 'Refresh events stream is missing run.completed' }
    if (@($refreshEventTypes | Where-Object { $_ -eq 'validation.passed' }).Count -ne 1) { throw 'Expected exactly one validation.passed event' }

    Write-Host ("  agent-run refresh correct: runId={0} events={1} finalOutcome={2}" -f $refreshRun.runId, @($refreshDetail.events).Count, $refresh4.run.outcome) -ForegroundColor DarkGray
}
finally {
    Remove-Item -LiteralPath $refreshWorkspace -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Step 'Merge readiness — smoke: blocking rules, ready case, snapshot store (Release 2.0 Phase 3)'
$mergeReadinessModule = Join-Path $WorkspaceRoot 'backend\modules\agent-runs\MergeReadiness.ps1'
if (-not (Test-Path -LiteralPath $mergeReadinessModule)) { throw "MergeReadiness.ps1 not found at: $mergeReadinessModule" }
. $mergeReadinessModule
$mrWorkspace = Join-Path ([System.IO.Path]::GetTempPath()) ("merge-readiness-smoke-" + [guid]::NewGuid().ToString('n').Substring(0, 8))
New-Item -ItemType Directory -Path $mrWorkspace -Force | Out-Null
try {
    $mrNoRun = Get-MergeReadinessEvaluation -RepoId 'repo:mr-smoke' -RepoName 'mr-smoke'
    if ($mrNoRun.ready) { throw 'Evaluation with no agent run must not be ready' }
    if (@($mrNoRun.blockers | Where-Object { $_.code -eq 'no-agent-run' }).Count -ne 1) { throw 'Missing no-agent-run blocker' }

    $mrDraftRun = [pscustomobject]@{
        runId = 'mr-r1'; prUrl = 'https://github.com/o/r/pull/7'; prNumber = 7; prState = 'open'; prDraft = $true
        actions = [pscustomobject]@{ status = 'in_progress'; conclusion = ''; workflowName = 'CI' }
    }
    $mrBlocked = Get-MergeReadinessEvaluation -RepoId 'repo:mr-smoke' -RepoName 'mr-smoke' `
        -AgentRun $mrDraftRun -LocalDirtyCount 2 -AuditBlockers @('Roadmap maturity below L3')
    $mrBlockedCodes = @($mrBlocked.blockers | ForEach-Object { [string]$_.code })
    foreach ($expectedCode in @('pr-draft', 'actions-pending', 'dirty-worktree', 'audit-blocker')) {
        if ($expectedCode -notin $mrBlockedCodes) { throw "Missing expected blocker '$expectedCode' (got: $($mrBlockedCodes -join ', '))" }
    }

    $mrReadyRun = [pscustomobject]@{
        runId = 'mr-r2'; prUrl = 'https://github.com/o/r/pull/8'; prNumber = 8; prState = 'open'; prDraft = $false
        actions = [pscustomobject]@{ status = 'completed'; conclusion = 'success'; workflowName = 'CI' }
    }
    $mrPrDetail = [pscustomobject]@{ draft = $false; state = 'open'; merged_at = $null; mergeable = $true; mergeable_state = 'clean' }
    $mrReady = Get-MergeReadinessEvaluation -RepoId 'repo:mr-smoke' -RepoName 'mr-smoke' -AgentRun $mrReadyRun -PrDetail $mrPrDetail
    if (-not $mrReady.ready) { throw "Fully-validated run should be ready; blockers: $((@($mrReady.blockers | ForEach-Object { $_.code })) -join ', ')" }

    # Failing fresh Actions state must override the stale ledger view.
    $mrFreshFail = Get-MergeReadinessEvaluation -RepoId 'repo:mr-smoke' -RepoName 'mr-smoke' -AgentRun $mrReadyRun -PrDetail $mrPrDetail `
        -ActionsState ([pscustomobject]@{ status = 'completed'; conclusion = 'failure'; workflowName = 'CI' })
    if ($mrFreshFail.ready) { throw 'Fresh failing Actions state must block readiness' }
    if ('actions-failing' -notin @($mrFreshFail.blockers | ForEach-Object { [string]$_.code })) { throw 'Missing actions-failing blocker from fresh Actions state' }

    # Merge conflicts and already-merged PRs block.
    $mrConflict = Get-MergeReadinessEvaluation -RepoId 'repo:mr-smoke' -RepoName 'mr-smoke' -AgentRun $mrReadyRun `
        -PrDetail ([pscustomobject]@{ draft = $false; state = 'open'; merged_at = $null; mergeable = $false; mergeable_state = 'dirty' })
    if ('merge-conflicts' -notin @($mrConflict.blockers | ForEach-Object { [string]$_.code })) { throw 'Missing merge-conflicts blocker' }
    $mrMerged = Get-MergeReadinessEvaluation -RepoId 'repo:mr-smoke' -RepoName 'mr-smoke' -AgentRun $mrReadyRun `
        -PrDetail ([pscustomobject]@{ draft = $false; state = 'closed'; merged_at = '2026-06-11T12:00:00Z'; mergeable = $null; mergeable_state = 'unknown' })
    if ('pr-already-merged' -notin @($mrMerged.blockers | ForEach-Object { [string]$_.code })) { throw 'Missing pr-already-merged blocker' }

    $null = Save-MergeReadinessSnapshot -WorkspaceRoot $mrWorkspace -Evaluation $mrReady
    $mrLoaded = Get-MergeReadinessSnapshot -WorkspaceRoot $mrWorkspace -RepoId 'repo:mr-smoke'
    if ($null -eq $mrLoaded -or -not $mrLoaded.ready) { throw 'Merge-readiness snapshot did not round-trip' }
    if ($null -ne (Get-MergeReadinessSnapshot -WorkspaceRoot $mrWorkspace -RepoId 'never-evaluated')) { throw 'Unknown repoId should return a null snapshot' }

    Write-Host ("  merge-readiness rules correct: blocked={0} ready={1} snapshot ok" -f $mrBlockedCodes.Count, $mrReady.ready) -ForegroundColor DarkGray
}
finally {
    Remove-Item -LiteralPath $mrWorkspace -Recurse -Force -ErrorAction SilentlyContinue
}

# ---------------------------------------------------------------------------
# Release 2.1 — Persistent Data Layer (Phase 1)
# ---------------------------------------------------------------------------

Write-Step 'Loading persistence store module (Release 2.1)'
$persistenceModule = Join-Path $WorkspaceRoot 'backend\modules\persistence\Persistence.Store.ps1'
if (-not (Test-Path -LiteralPath $persistenceModule)) { throw "Persistence.Store.ps1 not found at: $persistenceModule" }
. $persistenceModule
Write-Host 'Persistence store module loaded successfully' -ForegroundColor Green

Write-Step 'SQLite capability detection (Release 2.1 Phase 1)'
$sqliteCap = Get-SqliteCapability
if ($null -eq $sqliteCap) { throw 'Get-SqliteCapability returned null' }
Write-Host ("  capability: available={0} provider={1} detail={2} version={3}" -f $sqliteCap.available, $sqliteCap.provider, $sqliteCap.providerDetail, $sqliteCap.sqliteVersion) -ForegroundColor DarkGray

if (-not $sqliteCap.available) {
    # Graceful-degradation contract: no provider means a soft failure with a
    # reason, never an exception — the JSON stores stay authoritative.
    $degradedInit = Initialize-AppDatabase -WorkspaceRoot ([System.IO.Path]::GetTempPath())
    if ($degradedInit.success) { throw 'Initialize-AppDatabase must not report success without a SQLite provider' }
    if ([string]::IsNullOrWhiteSpace([string]$degradedInit.error)) { throw 'Degraded init must explain why SQLite is unavailable' }
    Write-Host '  no SQLite provider on this machine — degraded-path contract verified; DB smoke skipped' -ForegroundColor Yellow
} else {
    $appDbWorkspace = Join-Path ([System.IO.Path]::GetTempPath()) ("app-db-smoke-" + [guid]::NewGuid().ToString('n').Substring(0, 8))
    New-Item -ItemType Directory -Path $appDbWorkspace -Force | Out-Null
    try {
        Write-Step 'App database bootstrap — schema init, idempotent re-init (Release 2.1 Phase 1)'
        $appDbInit = Initialize-AppDatabase -WorkspaceRoot $appDbWorkspace
        if (-not $appDbInit.success) { throw "Initialize-AppDatabase failed: $($appDbInit.error)" }
        if (-not (Test-Path -LiteralPath $appDbInit.databasePath)) { throw "app.db not created at $($appDbInit.databasePath)" }
        $expectedAppDbTables = @(
            'schema_migrations', 'execution_ledger', 'execution_history', 'maturity_history',
            'ops_log', 'portfolio_index_history', 'repo_signals', 'differential_scans',
            'merge_readiness_snapshots', 'agent_runs', 'agent_run_events', 'quota_burn_snapshots'
        )
        foreach ($tableName in $expectedAppDbTables) {
            if ($tableName -notin @($appDbInit.tables)) { throw "Missing expected table '$tableName' (got: $(@($appDbInit.tables) -join ', '))" }
        }
        $appDbReinit = Initialize-AppDatabase -WorkspaceRoot $appDbWorkspace
        if (-not $appDbReinit.success) { throw "Re-init must be idempotent: $($appDbReinit.error)" }
        $migrationRows = Invoke-AppDbQuery -DatabasePath $appDbInit.databasePath -Sql 'SELECT COUNT(*) AS n FROM schema_migrations'
        if ([long]$migrationRows[0].n -ne 1) { throw "Expected exactly 1 schema migration row after re-init, got $($migrationRows[0].n)" }
        $migrationVersion = Invoke-AppDbQuery -DatabasePath $appDbInit.databasePath -Sql 'SELECT MAX(version) AS v FROM schema_migrations'
        if ([long]$migrationVersion[0].v -ne 2) { throw "Expected schema version 2 (Phase 3), got $($migrationVersion[0].v)" }
        Write-Host ("  app.db created with {0} tables; re-init idempotent" -f @($appDbInit.tables).Count) -ForegroundColor DarkGray

        Write-Step 'App database repeated writes + parameter binding (Release 2.1 Phase 1)'
        for ($writeIndex = 0; $writeIndex -lt 25; $writeIndex++) {
            $null = Invoke-AppDbNonQuery -DatabasePath $appDbInit.databasePath `
                -Sql 'INSERT INTO ops_log (timestamp, level, source, message, data_json) VALUES (@ts, @level, @source, @message, @data)' `
                -Parameters @{
                    ts      = (Get-Date).ToUniversalTime().ToString('o')
                    level   = 'INFO'
                    source  = 'module-smoke'
                    message = "repeated write $writeIndex"
                    data    = $null
                }
        }
        $opsCount = Invoke-AppDbQuery -DatabasePath $appDbInit.databasePath -Sql 'SELECT COUNT(*) AS n FROM ops_log WHERE level = @level' -Parameters @{ level = 'INFO' }
        if ([long]$opsCount[0].n -ne 25) { throw "Expected 25 ops_log rows after repeated writes, got $($opsCount[0].n)" }

        $trickyText = "quote'd — ünicode ✓"
        $null = Invoke-AppDbNonQuery -DatabasePath $appDbInit.databasePath `
            -Sql 'INSERT INTO ops_log (timestamp, level, source, message, data_json) VALUES (@ts, @level, @source, @message, @data)' `
            -Parameters @{ ts = (Get-Date).ToUniversalTime().ToString('o'); level = 'WARN'; source = 'module-smoke'; message = $trickyText; data = $null }
        $trickyRow = Invoke-AppDbQuery -DatabasePath $appDbInit.databasePath -Sql 'SELECT message, data_json FROM ops_log WHERE level = @level' -Parameters @{ level = 'WARN' }
        if ([string]$trickyRow[0].message -ne $trickyText) { throw "Unicode/quote parameter round-trip failed: got '$($trickyRow[0].message)'" }
        if ($null -ne $trickyRow[0].data_json) { throw 'NULL parameter should round-trip as $null' }
        Write-Host '  25 repeated writes + unicode/quote/null binding round-trip correct' -ForegroundColor DarkGray

        Write-Step 'Agent-run event dual-write seam (Release 2.1 Phase 1)'
        $dualWriteEvent = Write-AgentRunEvent -WorkspaceRoot $appDbWorkspace -EventType 'smoke.dualwrite' -RunId 'run-dw-1' -RepoName 'app-db-smoke' -Summary 'dual write seam check' -Data @{ source = 'module-smoke' }
        if (-not $dualWriteEvent.written) { throw 'Authoritative JSONL event write failed' }
        if (-not (Test-Path -LiteralPath (Join-Path $appDbWorkspace 'output\agent-runs\events.jsonl'))) { throw 'events.jsonl was not written alongside the DB mirror' }
        if (-not [bool]$dualWriteEvent.dbMirrored) { throw 'Agent-run event was not mirrored into app.db' }
        $mirroredRows = Invoke-AppDbQuery -DatabasePath $appDbInit.databasePath -Sql 'SELECT event_type, repo_name FROM agent_run_events WHERE run_id = @runId' -Parameters @{ runId = 'run-dw-1' }
        if (@($mirroredRows).Count -ne 1) { throw "Expected 1 mirrored agent-run event, got $(@($mirroredRows).Count)" }
        if ([string]$mirroredRows[0].event_type -ne 'smoke.dualwrite') { throw "Mirrored event type mismatch: $($mirroredRows[0].event_type)" }
        Write-Host '  dual-write seam correct: JSONL authoritative + app.db mirror row present' -ForegroundColor DarkGray

        Write-Step 'Agent-run metrics persistence under repeated writes (Release 2.1 Phase 3)'
        $metricsRun = New-AgentRunRecord -WorkspaceRoot $appDbWorkspace -RepoName 'app-db-smoke' `
            -PlannedReleaseName 'Release 9.9' -PlannedPhaseName 'Phase Smoke' -SelectedTaskSection 'Active' `
            -WorkUnitsEstimated 3.0
        $metricsRunId = [string]$metricsRun.runId
        $runRowsAfterCreate = Invoke-AppDbQuery -DatabasePath $appDbInit.databasePath -Sql 'SELECT status, release_name, phase_name, work_units_estimated FROM agent_runs WHERE run_id = @runId' -Parameters @{ runId = $metricsRunId }
        if (@($runRowsAfterCreate).Count -ne 1) { throw "Expected 1 mirrored agent_runs row after create, got $(@($runRowsAfterCreate).Count)" }
        if ([string]$runRowsAfterCreate[0].status -ne 'dispatched') { throw "Mirrored run status mismatch after create: $($runRowsAfterCreate[0].status)" }
        if ([string]$runRowsAfterCreate[0].release_name -ne 'Release 9.9') { throw "Mirrored release_name mismatch: $($runRowsAfterCreate[0].release_name)" }

        $startedIso = (Get-Date).ToUniversalTime().AddMinutes(-10).ToString('o')
        $completedIso = (Get-Date).ToUniversalTime().ToString('o')
        $null = Update-AgentRunRecord -WorkspaceRoot $appDbWorkspace -RunId $metricsRunId -Patch @{ status = 'active'; agentStartedAt = $startedIso }
        $null = Update-AgentRunRecord -WorkspaceRoot $appDbWorkspace -RunId $metricsRunId -Patch @{
            status = 'completed'; agentCompletedAt = $completedIso; tokenUsage = 12345; apiSpendUsd = 0.42; workUnitsActual = 2.5
        }
        $runRowsAfterUpdate = Invoke-AppDbQuery -DatabasePath $appDbInit.databasePath -Sql 'SELECT COUNT(*) AS n FROM agent_runs WHERE run_id = @runId' -Parameters @{ runId = $metricsRunId }
        if ([long]$runRowsAfterUpdate[0].n -ne 1) { throw "Repeated run mirror writes must upsert one row, got $($runRowsAfterUpdate[0].n)" }

        $metricsHistory = Get-AppDbAgentRunMetricsHistory -RepoName 'app-db-smoke' -Days 7
        if (-not $metricsHistory.available) { throw 'Get-AppDbAgentRunMetricsHistory must report available=true with an initialized DB' }
        if (@($metricsHistory.entries).Count -ne 1) { throw "Expected 1 metrics-history entry, got $(@($metricsHistory.entries).Count)" }
        $metricsEntry = @($metricsHistory.entries)[0]
        if ([string]$metricsEntry.status -ne 'completed') { throw "Metrics entry status mismatch: $($metricsEntry.status)" }
        if ([long]$metricsEntry.tokensReported -ne 12345) { throw "Metrics entry tokensReported mismatch: $($metricsEntry.tokensReported)" }
        if ([math]::Abs([double]$metricsEntry.directCostUsd - 0.42) -gt 0.0001) { throw "Metrics entry directCostUsd mismatch: $($metricsEntry.directCostUsd)" }
        if ($null -eq $metricsEntry.timeToDeliverSeconds -or [double]$metricsEntry.timeToDeliverSeconds -le 0) { throw "Metrics entry timeToDeliverSeconds must be derived and positive, got '$($metricsEntry.timeToDeliverSeconds)'" }
        if ([string]$metricsEntry.phaseName -ne 'Phase Smoke') { throw "Metrics entry phaseName mismatch: $($metricsEntry.phaseName)" }
        Write-Host ("  run mirror upserts correct; metrics history returns timing/token/cost (ttd={0}s)" -f $metricsEntry.timeToDeliverSeconds) -ForegroundColor DarkGray

        Write-Step 'Quota-burn snapshot persistence and ordered history (Release 2.1 Phase 3)'
        $allowedEvaluation = @{
            period = '2026-07'; allowed = $true; blockedCode = $null
            estimatedWorkUnits = 3.0; plannedReleaseName = 'Release 9.9'; plannedPhaseName = 'Phase Smoke'
            usage = @{ unitsConsumed = 3.0; remainingBefore = 57.0; remainingAfter = 54.0 }
        }
        $blockedEvaluation = @{
            period = '2026-07'; allowed = $false; blockedCode = 'hard-stop-reached'
            estimatedWorkUnits = 25.0; plannedReleaseName = 'Release 9.9'; plannedPhaseName = 'Phase Smoke'
            usage = @{ unitsConsumed = 55.0; remainingBefore = 5.0; remainingAfter = -20.0 }
        }
        $snapshotWrite1 = Write-AppDbQuotaBurnSnapshot -RepoName 'app-db-smoke' -Evaluation $allowedEvaluation
        if (-not $snapshotWrite1.success) { throw "First quota-burn snapshot write failed: $($snapshotWrite1.reason)" }
        Start-Sleep -Milliseconds 20
        $snapshotWrite2 = Write-AppDbQuotaBurnSnapshot -RepoName 'app-db-smoke' -Evaluation $blockedEvaluation
        if (-not $snapshotWrite2.success) { throw "Second quota-burn snapshot write failed: $($snapshotWrite2.reason)" }

        $burnHistory = Get-AppDbQuotaBurnHistory -RepoName 'app-db-smoke' -Days 7
        if (-not $burnHistory.available) { throw 'Get-AppDbQuotaBurnHistory must report available=true with an initialized DB' }
        if (@($burnHistory.entries).Count -ne 2) { throw "Expected 2 quota-burn entries, got $(@($burnHistory.entries).Count)" }
        $burnFirst = @($burnHistory.entries)[0]
        $burnSecond = @($burnHistory.entries)[1]
        if ([string]::CompareOrdinal([string]$burnFirst.evaluatedAt, [string]$burnSecond.evaluatedAt) -gt 0) { throw 'Quota-burn history must be ordered oldest-first' }
        if (-not [bool]$burnFirst.allowed) { throw 'First quota-burn entry should be allowed=true' }
        if ([bool]$burnSecond.allowed) { throw 'Second quota-burn entry should be allowed=false' }
        if ([string]$burnSecond.blockedCode -ne 'hard-stop-reached') { throw "Quota-burn blockedCode mismatch: $($burnSecond.blockedCode)" }
        if ([math]::Abs([double]$burnSecond.remainingAfter - (-20.0)) -gt 0.0001) { throw "Quota-burn remainingAfter mismatch: $($burnSecond.remainingAfter)" }
        Write-Host '  quota-burn snapshots persisted and readable as an ordered burn-down series' -ForegroundColor DarkGray

        Write-Step 'App database maintenance — snapshot retention + VACUUM (Release 2.7 Phase D)'
        # app.db reached ~138 MB in daily use with no scheduled maintenance. The
        # retention floor is the part worth guarding: GET /api/portfolio/trend
        # answers up to days=180 and Release 2.9 is waiting on 90-day accrual, so
        # a low configured window must be clamped UP rather than honored.
        $agedIso = (Get-Date).ToUniversalTime().AddDays(-400).ToString('o')
        $midIso = (Get-Date).ToUniversalTime().AddDays(-100).ToString('o')
        $freshIso = (Get-Date).ToUniversalTime().ToString('o')
        foreach ($i in 1..12) {
            $null = Invoke-AppDbNonQuery -DatabasePath $appDbInit.databasePath `
                -Sql 'INSERT INTO repo_signals (repo_name, captured_at) VALUES (@n, @t)' `
                -Parameters @{ n = "aged-$i"; t = $agedIso }
        }
        foreach ($i in 1..3) {
            $null = Invoke-AppDbNonQuery -DatabasePath $appDbInit.databasePath `
                -Sql 'INSERT INTO repo_signals (repo_name, captured_at) VALUES (@n, @t)' `
                -Parameters @{ n = "fresh-$i"; t = $freshIso }
        }
        # 100 days old: inside maturity_history's 180-day floor, so a 30-day
        # request must NOT delete it.
        foreach ($i in 1..4) {
            $null = Invoke-AppDbNonQuery -DatabasePath $appDbInit.databasePath `
                -Sql 'INSERT INTO maturity_history (repo_name, maturity_level, captured_at) VALUES (@n, @l, @t)' `
                -Parameters @{ n = "trend-$i"; l = 'L3'; t = $midIso }
        }

        # ReportOnly must count without deleting.
        $maintReport = Invoke-AppDbMaintenance -MaxSnapshotDays 30 -ReportOnly
        if (-not $maintReport.success) { throw "Maintenance report failed: $(($maintReport.tables | Where-Object { $_.error } | Select-Object -First 1).error)" }
        if (-not $maintReport.reportOnly) { throw 'Maintenance report must set reportOnly=true' }
        $reportSignals = ($maintReport.tables | Where-Object { $_.table -eq 'repo_signals' }).removed
        if ([long]$reportSignals -ne 12) { throw "Maintenance report expected 12 aged repo_signals rows, got $reportSignals" }
        $signalsAfterReport = Invoke-AppDbQuery -DatabasePath $appDbInit.databasePath -Sql 'SELECT COUNT(*) AS n FROM repo_signals'
        if ([long]$signalsAfterReport[0].n -ne 15) { throw "ReportOnly must not delete: expected 15 repo_signals rows, got $($signalsAfterReport[0].n)" }

        # The 180-day floor must be reported as applied for the trend tables.
        $maturityPlan = $maintReport.tables | Where-Object { $_.table -eq 'maturity_history' }
        if ([int]$maturityPlan.retentionDays -ne 180) { throw "maturity_history must clamp a 30-day request up to its 180-day floor; got $($maturityPlan.retentionDays)" }
        if (-not $maturityPlan.floorApplied) { throw 'maturity_history must report floorApplied=true for a 30-day request' }

        # Real run: aged rows go, fresh rows and floor-protected rows stay.
        $maintRun = Invoke-AppDbMaintenance -MaxSnapshotDays 30 -Confirm:$false
        if (-not $maintRun.success) { throw "Maintenance run failed: $(($maintRun.tables | Where-Object { $_.error } | Select-Object -First 1).error)" }
        if (-not $maintRun.vacuumed) { throw "VACUUM did not run: $($maintRun.vacuumError)" }
        if ([long]$maintRun.totalRowsRemoved -ne 12) { throw "Maintenance expected to remove 12 rows, removed $($maintRun.totalRowsRemoved)" }
        $signalsAfterRun = Invoke-AppDbQuery -DatabasePath $appDbInit.databasePath -Sql 'SELECT COUNT(*) AS n FROM repo_signals'
        if ([long]$signalsAfterRun[0].n -ne 3) { throw "Maintenance must keep the 3 fresh repo_signals rows, got $($signalsAfterRun[0].n)" }
        $maturityAfterRun = Invoke-AppDbQuery -DatabasePath $appDbInit.databasePath -Sql 'SELECT COUNT(*) AS n FROM maturity_history'
        if ([long]$maturityAfterRun[0].n -ne 4) { throw "Retention floor breached: maturity_history should still hold 4 rows, got $($maturityAfterRun[0].n)" }

        # Append-only operational records must never be touched.
        $ledgerAfterRun = Invoke-AppDbQuery -DatabasePath $appDbInit.databasePath -Sql 'SELECT COUNT(*) AS n FROM ops_log'
        if ([long]$ledgerAfterRun[0].n -lt 26) { throw "Maintenance must not prune ops_log (it has its own row-count trim); got $($ledgerAfterRun[0].n)" }

        # Config resolution reads retention.maxSnapshotDays, not retention.days.
        if ((Get-AppDbMaintenanceRetentionDays -Settings @{ retention = @{ maxSnapshotDays = 200 } }) -ne 200) { throw 'Retention days must be read from retention.maxSnapshotDays' }
        if ((Get-AppDbMaintenanceRetentionDays -Settings @{ retention = @{ days = 30 } }) -ne 365) { throw 'retention.days is doc-review inactivity and must NOT be read as the snapshot window' }
        if ((Get-AppDbMaintenanceRetentionDays -Settings $null) -ne 365) { throw 'Missing settings must fall back to the 365-day default' }

        Write-Host ("  app.db maintenance ok: report={0} aged, removed={1}, VACUUM ran, 180-day floor protected trend rows, ops_log untouched" -f $reportSignals, $maintRun.totalRowsRemoved) -ForegroundColor DarkGray
    }
    finally {
        Remove-Item -LiteralPath $appDbWorkspace -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Step 'GitHub App JWT minting (Release 2.2)'
. (Join-Path $WorkspaceRoot 'backend\modules\auth\GitHubApp.ps1')
if (Test-RsaPemSupported) {
    $rsaTest = [System.Security.Cryptography.RSA]::Create(2048)
    try { $pemTest = $rsaTest.ExportPkcs8PrivateKeyPem() } finally { $rsaTest.Dispose() }
    $jwtTest = New-GitHubAppJwt -AppId '999999' -PrivateKeyPem $pemTest
    if (@($jwtTest.Split('.')).Count -ne 3) { throw 'New-GitHubAppJwt must return a 3-segment JWT' }
    $claimsTest = ConvertFrom-JwtClaims -Jwt $jwtTest
    if ([string]$claimsTest.header.alg -ne 'RS256') { throw "JWT header alg must be RS256, got '$($claimsTest.header.alg)'" }
    if ([string]$claimsTest.payload.iss -ne '999999') { throw 'JWT iss must be the configured app id' }
    if ([long]$claimsTest.payload.exp -le [System.DateTimeOffset]::UtcNow.ToUnixTimeSeconds()) { throw 'JWT exp must be in the future' }
    $readyTest = Get-GitHubAppReadiness -GitHubApp @{ appId = '999999'; installationId = '42' }
    if ($readyTest.configured -ne $true) { throw 'Get-GitHubAppReadiness should report configured=true when appId+installationId set' }
    Write-Host '  GitHub App JWT minted: RS256, iss=appId, exp in future; readiness reports configured' -ForegroundColor DarkGray
}
else {
    Write-Host '  RSA PEM import unavailable on this runtime — JWT test skipped (degraded contract accepted)' -ForegroundColor Yellow
}

# ── Release 2.7 Phase B — scheduled documentation refinement (preview-first) ──
Write-Step 'Loading automation doc-refinement module (Release 2.7 Phase B)'
$aiDocModule = Join-Path $WorkspaceRoot 'backend\modules\ai\AiDocImprovement.ps1'
$automationModule = Join-Path $WorkspaceRoot 'backend\modules\automation\Automation.DocRefinement.ps1'
if (-not (Test-Path -LiteralPath $aiDocModule)) { throw "Missing module file: $aiDocModule" }
if (-not (Test-Path -LiteralPath $automationModule)) { throw "Missing module file: $automationModule" }
. $aiDocModule
. $automationModule
Write-Host '  Automation doc-refinement module loaded successfully' -ForegroundColor DarkGray

Write-Step 'Automation scope — smoke: curated subset only (favorites/candidates, never archived-ignore)'
$autoEntries = @(
    [pscustomobject]@{ repoId = 'fav-weak-readme';  repoName = 'fav-weak-readme';  curationState = 'favorite';             readmeScore = 10; roadmapScore = 90; roadmapState = 'complete' }
    [pscustomobject]@{ repoId = 'cand-weak-roadmap'; repoName = 'cand-weak-roadmap'; curationState = 'portfolio-candidate'; readmeScore = 95; roadmapScore = 20; roadmapState = 'missing' }
    [pscustomobject]@{ repoId = 'ignored-weak';     repoName = 'ignored-weak';     curationState = 'archived-ignore';      readmeScore = 5;  roadmapScore = 5;  roadmapState = 'missing' }
    [pscustomobject]@{ repoId = 'uncurated-weak';   repoName = 'uncurated-weak';   curationState = '';                     readmeScore = 5;  roadmapScore = 5;  roadmapState = 'missing' }
    [pscustomobject]@{ repoId = 'fav-healthy';      repoName = 'fav-healthy';      curationState = 'favorite';             readmeScore = 95; roadmapScore = 95; roadmapState = 'complete' }
)
$autoTargets = Select-AutomationDocTargets -Entries $autoEntries
$targetNames = @($autoTargets | ForEach-Object { "$($_.repoName):$($_.docType)" } | Sort-Object)
$expectedTargets = @('cand-weak-roadmap:roadmap', 'fav-weak-readme:readme') | Sort-Object
if (($targetNames -join ',') -ne ($expectedTargets -join ',')) {
    throw "Automation scope wrong. Expected [$($expectedTargets -join ', ')]; got [$($targetNames -join ', ')]"
}
Write-Host ("  scope ok: {0} targets (archived-ignore, uncurated, and healthy repos excluded)" -f @($autoTargets).Count) -ForegroundColor DarkGray

Write-Step 'Automation run — smoke: doc-improve previews generated, NOTHING applied'
$autoTmp = Join-Path ([System.IO.Path]::GetTempPath()) ("gh-automation-smoke-" + [guid]::NewGuid().ToString('n'))
$autoRepoDir = Join-Path $autoTmp 'fav-weak-readme'
$null = New-Item -ItemType Directory -Path $autoRepoDir -Force
$weakReadmePath = Join-Path $autoRepoDir 'README.md'
Set-Content -LiteralPath $weakReadmePath -Value "# fav-weak-readme`n" -Encoding UTF8
# Hash the file as-written so the unchanged-check is immune to encoding/newline
# differences and only fails on an actual on-disk mutation.
$readmeHashBefore = (Get-FileHash -LiteralPath $weakReadmePath -Algorithm SHA256).Hash
try {
    $runTargets = @([pscustomobject]@{ repoId = 'fav-weak-readme'; repoName = 'fav-weak-readme'; repoPath = $autoRepoDir; curationState = 'favorite'; docType = 'readme'; reason = 'curated=favorite weak-readme' })
    $autoRun = Invoke-ScheduledDocRefinement -WorkspaceRoot $WorkspaceRoot -Targets $runTargets -Provider 'heuristic' -TriggeredBy 'module-smoke'
    if ([int]$autoRun.appliedCount -ne 0) { throw "Preview-first invariant violated: appliedCount=$($autoRun.appliedCount)" }
    if ([int]$autoRun.proposalCount -lt 1) { throw "Expected at least one doc-improve proposal; got $($autoRun.proposalCount)" }
    $firstProposal = @($autoRun.proposals)[0]
    if ([string]::IsNullOrWhiteSpace([string]$firstProposal.previewId)) { throw 'Proposal missing previewId' }
    if ($firstProposal.applied -ne $false) { throw 'Proposal must be marked applied=false' }
    # The target README on disk must be UNCHANGED (preview-only, no write-back).
    if ((Get-FileHash -LiteralPath $weakReadmePath -Algorithm SHA256).Hash -ne $readmeHashBefore) {
        throw 'Preview-first violated: the target README was modified on disk.'
    }

    # Append-only run history round-trip (isolated temp workspace).
    $histWs = Join-Path $autoTmp 'ws'
    $null = New-Item -ItemType Directory -Path $histWs -Force
    $null = Write-AutomationRunRecord -WorkspaceRoot $histWs -Run $autoRun
    $history = Get-AutomationRunHistory -WorkspaceRoot $histWs
    if (@($history).Count -lt 1) { throw 'Automation run history did not persist the run' }
    if ([string]@($history)[0].runId -ne [string]$autoRun.runId) { throw 'History newest-first ordering or runId mismatch' }

    # Digest payload shape.
    $digest = New-AutomationDigestPayload -Run $autoRun
    if ([int]$digest.appliedCount -ne 0) { throw 'Digest must report appliedCount=0' }
    if ([int]$digest.proposalCount -ne [int]$autoRun.proposalCount) { throw 'Digest proposalCount mismatch' }

    # Guardrail: recording a run that claims to have applied changes must be refused.
    $badRun = [pscustomobject]@{ runId = 'bad'; appliedCount = 1; proposals = @() }
    $refused = $false
    try { $null = Write-AutomationRunRecord -WorkspaceRoot $histWs -Run $badRun } catch { $refused = $true }
    if (-not $refused) { throw 'Write-AutomationRunRecord must refuse a run with appliedCount != 0' }

    Write-Host ("  automation run ok: {0} preview(s), applied=0, history+digest round-trip, applied-run refused (provider={1})" -f $autoRun.proposalCount, $autoRun.provider) -ForegroundColor DarkGray

    # ---- Release 2.7 Phase D — scheduler failure alerting -------------------
    # The failure this guards is silence: interval firing is delegated to an
    # external cron, so a scheduler that stops leaves the config reading
    # "enabled" while history quietly stops growing.
    $healthSettings = @{ automation = @{ enabled = $true; intervalMinutes = 60 } }

    # A fresh run must be healthy with no alert.
    $freshHealth = Get-AutomationHealth -WorkspaceRoot $histWs -Settings $healthSettings
    if (-not $freshHealth.healthy) { throw "Automation health: a just-recorded successful run must be healthy; alert=$($freshHealth.alert.code)" }
    if ($freshHealth.lastOutcome -ne 'ok') { throw "Automation health: expected lastOutcome=ok; got $($freshHealth.lastOutcome)" }
    if ($freshHealth.overdue) { throw 'Automation health: a just-recorded run must not be overdue' }
    # Timezone tripwire. ConvertFrom-Json returns finishedAt as a kind-less
    # DateTime that already holds UTC; converting it a second time put lastRunAt
    # in the FUTURE and made overdue detection impossible without failing any
    # boolean assertion. A just-written run must read as ~0 minutes old, and the
    # tolerance must be well under one local-offset shift.
    if ([math]::Abs([double]$freshHealth.minutesSinceLastRun) -gt 5) {
        throw "Automation health: a just-recorded run must be ~0 minutes old; got $($freshHealth.minutesSinceLastRun) (double UTC conversion?)"
    }

    # Overdue detection: the same history evaluated 5 hours later, against a
    # 60-minute interval and a 2x grace, must alert.
    $lateHealth = Get-AutomationHealth -WorkspaceRoot $histWs -Settings $healthSettings -Now ([datetime]::UtcNow.AddHours(5))
    if (-not $lateHealth.overdue) { throw 'Automation health: a 5-hour gap on a 60-minute interval must be overdue' }
    if ($lateHealth.alert.code -ne 'automation-overdue') { throw "Automation health: expected automation-overdue; got $($lateHealth.alert.code)" }

    # Disabled automation is never overdue — no alert for a feature that is off.
    $offHealth = Get-AutomationHealth -WorkspaceRoot $histWs -Settings @{ automation = @{ enabled = $false; intervalMinutes = 60 } } -Now ([datetime]::UtcNow.AddHours(5))
    if ($offHealth.overdue -or -not $offHealth.healthy) { throw 'Automation health: disabled automation must not alert' }

    # Outcome classification: errors with no proposals = failed; errors with
    # proposals = partial; zero targets = ok (a clean portfolio is not a failure).
    $failedRun = [pscustomobject]@{ runId = 'f1'; proposalCount = 0; targetCount = 1; errors = @([pscustomobject]@{ repoName = 'x'; error = 'boom' }) }
    $partialRun = [pscustomobject]@{ runId = 'p1'; proposalCount = 1; targetCount = 2; errors = @([pscustomobject]@{ repoName = 'x'; error = 'boom' }) }
    $emptyRun = [pscustomobject]@{ runId = 'e1'; proposalCount = 0; targetCount = 0; errors = @() }
    if ((Get-AutomationRunOutcome -Run $failedRun) -ne 'failed') { throw 'Automation outcome: errors with no proposals must classify as failed' }
    if ((Get-AutomationRunOutcome -Run $partialRun) -ne 'partial') { throw 'Automation outcome: errors with proposals must classify as partial' }
    if ((Get-AutomationRunOutcome -Run $emptyRun) -ne 'ok') { throw 'Automation outcome: a zero-target run must classify as ok, not a failure' }

    Write-Host ("  automation health ok: fresh=healthy, 5h-gap=overdue, disabled=silent, outcomes=failed/partial/ok") -ForegroundColor DarkGray
}
finally {
    Remove-Item -LiteralPath $autoTmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Step 'Portal watchdog — smoke: decision logic + ledger/state round-trip (Release 2.7 Phase D)'
. (Join-Path $WorkspaceRoot 'scripts\service\Watch-PortalHealth.ps1') -LoadFunctionsOnly

# Pure decision logic: healthy resets to 0, failures accumulate, reaching the
# threshold triggers a restart and resets the counter.
$wdCases = @(
    @{ Healthy = $true;  Prior = 0; Threshold = 3; Action = 'none';    Failures = 0 },
    @{ Healthy = $true;  Prior = 2; Threshold = 3; Action = 'none';    Failures = 0 },
    @{ Healthy = $false; Prior = 0; Threshold = 3; Action = 'none';    Failures = 1 },
    @{ Healthy = $false; Prior = 1; Threshold = 3; Action = 'none';    Failures = 2 },
    @{ Healthy = $false; Prior = 2; Threshold = 3; Action = 'restart'; Failures = 0 },
    @{ Healthy = $false; Prior = 0; Threshold = 1; Action = 'restart'; Failures = 0 }
)
foreach ($c in $wdCases) {
    $d = Resolve-WatchdogAction -Healthy $c.Healthy -PriorFailures $c.Prior -Threshold $c.Threshold
    if ($d.Action -ne $c.Action -or $d.Failures -ne $c.Failures) {
        throw ("Resolve-WatchdogAction wrong for healthy={0} prior={1} threshold={2}: got action={3}/failures={4}, expected {5}/{6}" -f $c.Healthy, $c.Prior, $c.Threshold, $d.Action, $d.Failures, $c.Action, $c.Failures)
    }
}

# Ledger + state round-trip on disk (models persistence across scheduled invocations).
$wdTmp = Join-Path $WorkspaceRoot 'output\smoke\module\watchdog'
$null = New-Item -ItemType Directory -Path $wdTmp -Force
try {
    $wdLedger = Join-Path $wdTmp 'wd.jsonl'
    $wdState = Join-Path $wdTmp 'wd.state.json'
    Remove-Item -LiteralPath $wdLedger, $wdState -Force -ErrorAction SilentlyContinue

    if ((Get-WatchdogState -Path $wdState) -ne 0) { throw 'Get-WatchdogState should default to 0 with no state file' }
    Set-WatchdogState -Path $wdState -ConsecutiveFailures 2 -LastAction 'none'
    if ((Get-WatchdogState -Path $wdState) -ne 2) { throw 'Watchdog state did not round-trip (expected 2)' }

    Write-WatchdogLedger -Path $wdLedger -Event 'probe-fail' -Data @{ priorFailures = 1; decision = 'none' }
    Write-WatchdogLedger -Path $wdLedger -Event 'restart-triggered' -Data @{ reason = 'test' }
    $wdRecords = @(Get-Content -LiteralPath $wdLedger -Encoding UTF8 | ForEach-Object { $_ | ConvertFrom-Json })
    if ($wdRecords.Count -ne 2) { throw "Watchdog ledger expected 2 append-only records, got $($wdRecords.Count)" }
    if ($wdRecords[0].event -ne 'probe-fail' -or $wdRecords[1].event -ne 'restart-triggered') { throw 'Watchdog ledger records out of order or mislabeled' }
    if (-not $wdRecords[0].timestamp) { throw 'Watchdog ledger record missing timestamp' }

    Write-Host ("  watchdog ok: {0} decision cases, state round-trip, {1} append-only ledger records" -f $wdCases.Count, $wdRecords.Count) -ForegroundColor DarkGray
}
finally {
    Remove-Item -LiteralPath $wdTmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Step 'Portal service installer — smoke: action resolution + secrets carry-forward/strip + drift (Release 2.7 Phase D)'
# Isolate the dot-source in a child scope so the installer's Write-* helpers do
# not clobber the smoke's for the remaining steps.
& {
    # Capture the root first — dot-sourcing the installer rebinds $WorkspaceRoot
    # to its param default ('') in this scope.
    $root = $WorkspaceRoot
    . (Join-Path $root 'scripts\Install-RepoManagementService.ps1') -LoadFunctionsOnly

    $instCases = @(
        @{ Exists = $false; Req = 'Auto';        Int = $true;  Want = 'Install' },
        @{ Exists = $true;  Req = 'Auto';        Int = $true;  Want = 'Menu' },
        @{ Exists = $true;  Req = 'Auto';        Int = $false; Want = 'Repair' },
        @{ Exists = $true;  Req = 'Reconfigure'; Int = $true;  Want = 'Reconfigure' },
        @{ Exists = $false; Req = 'Uninstall';   Int = $true;  Want = 'Uninstall' }
    )
    foreach ($c in $instCases) {
        $g = Resolve-InstallAction -ServiceExists $c.Exists -RequestedAction $c.Req -Interactive $c.Int
        if ($g -ne $c.Want) { throw ("Resolve-InstallAction wrong: exists={0} req={1} int={2} -> {3}, expected {4}" -f $c.Exists, $c.Req, $c.Int, $g, $c.Want) }
    }

    # Secrets/TLS carry-forward: a reconfigure that OMITS -PfxPath/-ApiKey must
    # preserve HTTPS + reuse the key (the bug that silently downgraded to HTTP).
    $rEnv = Resolve-PortalSecretConfig -InjectAuth $true -ExistingSettings @{} `
        -ExistingEnv @{ REPO_MGMT_API_KEY = 'envkey'; REPO_MGMT_TLS_PFX = 'C:\c.pfx'; REPO_MGMT_TLS_PFX_PASSWORD = 'envpw' } -KeyGenerator { 'GEN' }
    if ($rEnv.ApiKey -ne 'envkey' -or $rEnv.ApiKeySource -ne 'env') { throw 'Resolve-PortalSecretConfig did not carry the key forward from env' }
    if (-not $rEnv.UseTls -or $rEnv.PfxPath -ne 'C:\c.pfx' -or $rEnv.PfxPassword -ne 'envpw') { throw 'Resolve-PortalSecretConfig dropped TLS on carry-forward' }

    # Legacy settings secrets migrate forward; explicit params win; generate last.
    $rSet = Resolve-PortalSecretConfig -InjectAuth $true -ExistingEnv @{} `
        -ExistingSettings @{ auth = @{ apiKey = 'setkey' }; network = @{ tls = @{ pfxPath = 'C:\s.pfx'; pfxPassword = 'setpw' } } } -KeyGenerator { 'GEN' }
    if ($rSet.ApiKey -ne 'setkey' -or $rSet.ApiKeySource -ne 'settings' -or $rSet.PfxPassword -ne 'setpw') { throw 'Resolve-PortalSecretConfig did not migrate legacy settings secrets' }
    $rParam = Resolve-PortalSecretConfig -InjectAuth $true -RequestedApiKey 'pk' -RequestedPfxPath 'C:\p.pfx' -RequestedPfxPassword 'ppw' `
        -ExistingEnv @{ REPO_MGMT_API_KEY = 'envkey' } -ExistingSettings @{} -KeyGenerator { 'GEN' }
    if ($rParam.ApiKeySource -ne 'param' -or $rParam.PfxPath -ne 'C:\p.pfx') { throw 'Resolve-PortalSecretConfig: explicit params should win' }
    $rGen = Resolve-PortalSecretConfig -InjectAuth $true -ExistingEnv @{} -ExistingSettings @{} -KeyGenerator { 'GEN' }
    if ($rGen.ApiKeySource -ne 'generated' -or $rGen.ApiKey -ne 'GEN') { throw 'Resolve-PortalSecretConfig should generate when nothing to carry' }

    # Secret-strip: settings.json ends up secret-free (git-safe), non-secret keys kept.
    $strip = Remove-SettingsSecretKeys -Settings @{ schemaVersion = 'v1'; inventory = @{ localRoots = @('X') }; auth = @{ apiKey = 'k'; requireApiKey = $true }; network = @{ tls = @{ pfxPath = 'p'; pfxPassword = 'pw' } } }
    if ($strip.ContainsKey('auth') -or $strip.ContainsKey('network')) { throw 'Remove-SettingsSecretKeys left a secret container behind' }
    if ($strip.schemaVersion -ne 'v1' -or $strip.inventory.localRoots[0] -ne 'X') { throw 'Remove-SettingsSecretKeys dropped a non-secret key' }
    $stripSib = Remove-SettingsSecretKeys -Settings @{ auth = @{ apiKey = 'k'; apiKeyEnvVar = 'X' }; network = @{ corsOrigin = '*'; tls = @{ pfxPassword = 'pw' } } }
    if (-not $stripSib.ContainsKey('auth') -or $stripSib.auth.ContainsKey('apiKey') -or $stripSib.auth.apiKeyEnvVar -ne 'X') { throw 'Remove-SettingsSecretKeys mishandled a non-secret auth sibling' }
    if (-not $stripSib.ContainsKey('network') -or $stripSib.network.ContainsKey('tls') -or $stripSib.network.corsOrigin -ne '*') { throw 'Remove-SettingsSecretKeys mishandled a non-secret network sibling' }

    $instTmp = Join-Path $root 'output\smoke\module\svc-install'
    $null = New-Item -ItemType Directory -Path $instTmp -Force
    try {
        $driftImg = "C:\gone\shawl.exe run --name X --cwd $instTmp --log-dir $instTmp\missing\logs -- $instTmp\pwsh.exe -File $instTmp\host.ps1"
        $drift = @(Get-ImagePathDrift -ImagePath $driftImg)
        if ($drift.Count -lt 1) { throw 'Get-ImagePathDrift should flag the missing paths' }

        Write-Host ("  service installer ok: {0} action cases, secrets carry-forward (env/settings/param/generate), settings-strip git-safe, drift flagged {1} missing" -f $instCases.Count, $drift.Count) -ForegroundColor DarkGray
    }
    finally {
        Remove-Item -LiteralPath $instTmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Step 'Local Claude Code dispatch — smoke: queue writer + runner logic (Release 2.8)'
& {
    $root = $WorkspaceRoot
    . (Join-Path $root 'scripts\Add-RoadmapTaskToQueue.ps1') -LoadFunctionsOnly
    . (Join-Path $root 'scripts\Invoke-RoadmapTaskRunner.ps1') -LoadFunctionsOnly

    $dispTmp = Join-Path $root 'output\smoke\module\claude-dispatch'
    $null = New-Item -ItemType Directory -Path $dispTmp -Force
    try {
        # queue entry shape + append/read round-trip
        $entry = New-RoadmapQueueEntry -RunId 'r1' -Repository 'x/y' -LocalRepoPath 'C:\repo' -RoadmapPath 'C:\repo\ROADMAP.md' -SelectedTask 'Do it' -TaskDescription 'PROMPT' -Branch '' -QueuedAt '2026-01-01T00:00:00Z'
        if ($entry.status -ne 'queued') { throw 'queue entry status should be queued' }
        if ($entry.branch -ne 'roadmap/r1') { throw 'queue entry branch default should be roadmap/<runId>' }
        $qp = Join-Path $dispTmp 'queue.jsonl'
        Add-RoadmapQueueEntry -QueuePath $qp -Entry $entry
        Add-RoadmapQueueEntry -QueuePath $qp -Entry (New-RoadmapQueueEntry -RunId 'r2' -Repository 'x/z' -LocalRepoPath 'C:\repo2' -RoadmapPath 'C:\repo2\ROADMAP.md' -SelectedTask 'Two' -TaskDescription 'P2' -Branch 'roadmap/r2' -QueuedAt '2026-01-01T00:00:01Z')
        $read = @(Get-QueueEntries -QueuePath $qp)
        if ($read.Count -ne 2) { throw "queue round-trip expected 2 entries, got $($read.Count)" }
        if ($read[0].prompt -ne 'PROMPT' -or $read[0].localRepoPath -ne 'C:\repo') { throw 'queue entry fields not preserved on round-trip' }

        # summary status transitions (queued -> awaiting-review, fields merged)
        $sp = Join-Path $dispTmp 'r1.summary.json'
        Update-TaskSummary -SummaryPath $sp -Set @{ status = 'queued'; runId = 'r1' }
        if ((Get-TaskSummaryStatus -SummaryPath $sp) -ne 'queued') { throw 'summary status should be queued' }
        Update-TaskSummary -SummaryPath $sp -Set @{ status = 'awaiting-review'; branch = 'roadmap/r1' }
        $reread = Get-Content -LiteralPath $sp -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($reread.status -ne 'awaiting-review' -or $reread.runId -ne 'r1') { throw 'summary merge/transition failed' }

        # commit-message truncation + best-effort verify detection
        if (((New-TaskCommitMessage -SelectedTask ('x' * 120) -RunId 'r1') -split "`n")[0].Length -gt ('roadmap: '.Length + 68)) { throw 'commit subject not truncated' }
        '{ "scripts": { "test": "vitest" } }' | Set-Content -LiteralPath (Join-Path $dispTmp 'package.json') -Encoding UTF8
        if ((Resolve-VerifyCommand -RepoPath $dispTmp) -ne 'npm test') { throw 'verify detection (npm test) failed' }

        Write-Host ("  claude dispatch ok: queue round-trip ({0} entries), status transitions, commit-msg truncation, verify detection" -f $read.Count) -ForegroundColor DarkGray
    }
    finally {
        Remove-Item -LiteralPath $dispTmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ── Release 2.7 Phase C — scheduled roadmap-item packaging ───────────────────
Write-Step 'Loading roadmap-packaging module (Release 2.7 Phase C)'
$packagingModule = Join-Path $WorkspaceRoot 'backend\modules\automation\Automation.RoadmapPackaging.ps1'
if (-not (Test-Path -LiteralPath $packagingModule)) { throw "Missing module file: $packagingModule" }
. $packagingModule
Write-Host '  Roadmap-packaging module loaded successfully' -ForegroundColor DarkGray

Write-Step 'Packaging scope — smoke: every refusal is named, and scope opts in'
$pkgItemHigh = [pscustomobject]@{ text = 'Add the merge-readiness route'; section = 'Release 1.0'; roadmapOrder = 3; valueScore = 88; valueTier = 'highest'; valueRationale = @('unblocks dispatch') }
$pkgItemLow  = [pscustomobject]@{ text = 'Tidy the changelog';           section = 'Release 1.0'; roadmapOrder = 1; valueScore = 40; valueTier = 'low';     valueRationale = @('cosmetic') }
$pkgItemTie  = [pscustomobject]@{ text = 'Earlier item, same score';     section = 'Release 1.0'; roadmapOrder = 2; valueScore = 88; valueTier = 'highest'; valueRationale = @('tie-break probe') }

$pkgEntries = @(
    [pscustomobject]@{ repoId = 'fav-ready';    repoName = 'fav-ready';    curationState = 'favorite';             maturityLevel = 'L3-Contract-Ready';      pendingItemCount = 3; localPath = 'C:\repos\fav-ready';    roadmapPath = 'C:\repos\fav-ready\ROADMAP.md';    githubFullName = 'owner/fav-ready'; defaultBranch = 'main'; estimatedSessionWorkUnits = 4; valueRankedItems = @($pkgItemLow, $pkgItemHigh, $pkgItemTie) }
    [pscustomobject]@{ repoId = 'cand-ready';   repoName = 'cand-ready';   curationState = 'portfolio-candidate';  maturityLevel = 'L4-Orchestration-Ready'; pendingItemCount = 1; localPath = 'C:\repos\cand-ready';   roadmapPath = 'C:\repos\cand-ready\ROADMAP.md';   topValueItem = $pkgItemHigh }
    [pscustomobject]@{ repoId = 'ignored';      repoName = 'ignored';      curationState = 'archived-ignore';      maturityLevel = 'L4-Orchestration-Ready'; pendingItemCount = 9; localPath = 'C:\repos\ignored';      topValueItem = $pkgItemHigh }
    [pscustomobject]@{ repoId = 'uncurated';    repoName = 'uncurated';    curationState = '';                     maturityLevel = 'L3-Contract-Ready';      pendingItemCount = 9; localPath = 'C:\repos\uncurated';    topValueItem = $pkgItemHigh }
    [pscustomobject]@{ repoId = 'weird-state';  repoName = 'weird-state';  curationState = 'some-future-state';    maturityLevel = 'L3-Contract-Ready';      pendingItemCount = 9; localPath = 'C:\repos\weird';        topValueItem = $pkgItemHigh }
    [pscustomobject]@{ repoId = 'fav-l2';       repoName = 'fav-l2';       curationState = 'favorite';             maturityLevel = 'L2-Structured';          pendingItemCount = 9; localPath = 'C:\repos\fav-l2';       topValueItem = $pkgItemHigh }
    [pscustomobject]@{ repoId = 'fav-done';     repoName = 'fav-done';     curationState = 'favorite';             maturityLevel = 'L3-Contract-Ready';      pendingItemCount = 0; localPath = 'C:\repos\fav-done';     topValueItem = $pkgItemHigh }
    [pscustomobject]@{ repoId = 'fav-unscored'; repoName = 'fav-unscored'; curationState = 'favorite';             maturityLevel = 'L3-Contract-Ready';      pendingItemCount = 2; localPath = 'C:\repos\fav-unscored' }
    [pscustomobject]@{ repoId = 'fav-nopath';   repoName = 'fav-nopath';   curationState = 'favorite';             maturityLevel = 'L3-Contract-Ready';      pendingItemCount = 2; topValueItem = $pkgItemHigh }
)

$pkgDecisions = @(Resolve-AutomationPackagingScope -Entries $pkgEntries)
$pkgReasonByRepo = @{}
foreach ($d in $pkgDecisions) { $pkgReasonByRepo[[string]$d.repoName] = $d }
$pkgExpectedRefusals = @{
    'ignored'      = 'archived-ignore'
    'uncurated'    = 'not-curated'
    'weird-state'  = 'not-curated'      # scope opts IN — an unknown state is excluded, never admitted
    'fav-l2'       = 'roadmap-not-ready'
    'fav-done'     = 'no-pending-work'
    'fav-unscored' = 'no-scored-item'
    'fav-nopath'   = 'missing-local-path'
}
foreach ($repo in $pkgExpectedRefusals.Keys) {
    $decision = $pkgReasonByRepo[$repo]
    if ($null -eq $decision) { throw "Packaging scope: no decision recorded for '$repo'" }
    if ($decision.selected) { throw "Packaging scope: '$repo' must not be selected (expected refusal '$($pkgExpectedRefusals[$repo])')" }
    if ([string]$decision.reason -ne $pkgExpectedRefusals[$repo]) {
        throw "Packaging scope: '$repo' expected reason '$($pkgExpectedRefusals[$repo])'; got '$($decision.reason)'"
    }
}
$pkgSelected = @($pkgDecisions | Where-Object { $_.selected } | ForEach-Object { [string]$_.repoName } | Sort-Object)
if (($pkgSelected -join ',') -ne 'cand-ready,fav-ready') {
    throw "Packaging scope: expected [cand-ready, fav-ready]; got [$($pkgSelected -join ', ')]"
}
Write-Host ("  packaging scope ok: {0} selected, {1} refusals each named (archived-ignore, not-curated x2, roadmap-not-ready, no-pending-work, no-scored-item, missing-local-path)" -f $pkgSelected.Count, $pkgExpectedRefusals.Count) -ForegroundColor DarkGray

Write-Step 'Packaging rank — smoke: highest value wins, ties break on roadmap order'
$pkgTop = Select-TopValueRoadmapItem -Entry $pkgEntries[0]
if ([string]$pkgTop.text -ne 'Earlier item, same score') {
    throw "Top-value selection wrong: expected the earlier of two equally-scored items; got '$($pkgTop.text)' (score $($pkgTop.valueScore), order $($pkgTop.roadmapOrder))"
}
if ([int]$pkgTop.valueScore -ne 88) { throw 'Top-value selection did not pick the highest score' }
# An entry with no ranked list falls back to the precomputed topValueItem.
if ([string](Select-TopValueRoadmapItem -Entry $pkgEntries[1]).text -ne 'Add the merge-readiness route') { throw 'topValueItem fallback failed' }
# An entry with neither is NOT packaged with an unscored item.
if ($null -ne (Select-TopValueRoadmapItem -Entry $pkgEntries[7])) { throw 'An entry with no scored item must select nothing' }
Write-Host '  packaging rank ok: max score, earlier roadmap order breaks the tie, unscored selects nothing' -ForegroundColor DarkGray

Write-Step 'Packaging quota — smoke: over-budget items are skipped and logged, never silently dropped'
& {
    $pkgWs = Join-Path $WorkspaceRoot 'output\smoke\module\packaging'
    if (Test-Path -LiteralPath $pkgWs) { Remove-Item -LiteralPath $pkgWs -Recurse -Force }
    $null = New-Item -ItemType Directory -Path $pkgWs -Force
    try {
        # A budget whose per-session cap (2) is below the fixture's 4-unit estimate.
        $tightBudget = Get-AgentBudgetLedgerConfig -WorkspaceRoot $pkgWs -Settings @{
            budgetLedger = @{
                quotaGuard     = @{ softStopRemainingUnits = 1; hardStopRemainingUnits = 0; maxUnitsPerPhase = 25; maxUnitsPerSession = 2 }
                defaultProject = @{ monthlyQuotaBudgetUnits = 50; monthlyBudgetUsd = 6; priority = 1 }
            }
        }
        $tightRun = Invoke-ScheduledRoadmapPackaging -WorkspaceRoot $pkgWs -Entries $pkgEntries -BudgetConfig $tightBudget -TriggeredBy 'module-smoke'
        if ([int]$tightRun.packagedCount -ne 0) { throw "Over-budget run packaged $($tightRun.packagedCount) item(s); expected 0" }
        $quotaSkips = @($tightRun.skipped | Where-Object { [string]$_.stage -eq 'quota' })
        if ($quotaSkips.Count -ne 2) { throw "Expected 2 quota skips (both candidates); got $($quotaSkips.Count)" }
        if ([string]$quotaSkips[0].reason -ne 'session-cap-exceeded') { throw "Quota skip must carry the guard's own code; got '$($quotaSkips[0].reason)'" }
        if ([string]::IsNullOrWhiteSpace([string]$quotaSkips[0].message)) { throw 'A quota skip must carry the guard message, not just a code' }
        if (Test-Path -LiteralPath (Get-PackagedItemsFilePath -WorkspaceRoot $pkgWs)) { throw 'An over-budget run must not queue anything for approval' }

        # A guard that cannot be evaluated is a REFUSAL, not a pass. Proven in a
        # fresh runspace where BudgetLedger.ps1 was never loaded.
        $isolated = [powershell]::Create()
        try {
            $null = $isolated.AddScript(@"
. '$packagingModule'
`$r = Test-PackagingQuota -WorkspaceRoot '$pkgWs' -RepoName 'x' -EstimatedWorkUnits 1
"[{0}|{1}]" -f `$r.allowed, `$r.blockedCode
"@)
            $isolatedOut = [string](@($isolated.Invoke()) -join '')
        } finally { $isolated.Dispose() }
        if ($isolatedOut -ne '[False|quota-guard-unavailable]') {
            throw "Fail-closed quota guard broken: expected [False|quota-guard-unavailable], got '$isolatedOut'"
        }
        Write-Host '  packaging quota ok: over-budget skipped+logged with the guard code, nothing queued, missing guard fails closed' -ForegroundColor DarkGray

        Write-Step 'Packaging run — smoke: packets queued for approval, NOTHING dispatched'
        $okBudget = Get-AgentBudgetLedgerConfig -WorkspaceRoot $pkgWs -Settings @{
            budgetLedger = @{
                quotaGuard     = @{ softStopRemainingUnits = 2; hardStopRemainingUnits = 1; maxUnitsPerPhase = 25; maxUnitsPerSession = 12 }
                defaultProject = @{ monthlyQuotaBudgetUnits = 50; monthlyBudgetUsd = 6; priority = 1 }
            }
        }
        $pkgRun = Invoke-ScheduledRoadmapPackaging -WorkspaceRoot $pkgWs -Entries $pkgEntries -BudgetConfig $okBudget -TriggeredBy 'module-smoke'
        if ([int]$pkgRun.packagedCount -ne 2) { throw "Expected 2 packaged items; got $($pkgRun.packagedCount)" }
        if ([int]$pkgRun.dispatchedCount -ne 0) { throw 'Scheduled-run invariant violated: dispatchedCount != 0' }
        if ([int]$pkgRun.appliedCount -ne 0) { throw 'Scheduled-run invariant violated: appliedCount != 0' }
        if (Test-Path -LiteralPath (Join-Path $pkgWs 'output\roadmap-task-queue.jsonl')) {
            throw 'A scheduled packaging run wrote to the dispatch queue; it must stop at the approval gate.'
        }

        $favPacket = @($pkgRun.packets | Where-Object { [string]$_.repoName -eq 'fav-ready' })[0]
        if ([string]$favPacket.itemText -ne 'Earlier item, same score') { throw 'Packet did not carry the top-ranked item' }
        if ([double]$favPacket.estimatedWorkUnits -ne 4) { throw "Packet must price the roadmap's own annotated estimate; got $($favPacket.estimatedWorkUnits)" }
        if ($favPacket.branch -notmatch '^roadmap-item/') { throw "Packet branch must be namespaced; got '$($favPacket.branch)'" }
        if ([string]$favPacket.baseBranch -ne 'main') { throw 'Packet must record the base branch' }
        if ($favPacket.generatedPrompt -notmatch [regex]::Escape($favPacket.itemText)) { throw 'Prompt does not name the selected item' }
        if ($favPacket.generatedPrompt -notmatch 'Implement ONLY') { throw 'Prompt is missing the single-item scope guardrail' }
        if ($favPacket.repairPlan.submitted -ne $false) { throw 'The repair-PR plan must be a plan: submitted=false' }
        if ($favPacket.repairPlan.requiresApproval -ne $true) { throw 'The repair-PR plan must require approval' }
        if ([string]$favPacket.repairPlan.branch -ne [string]$favPacket.branch) { throw 'Repair plan branch must match the packet branch' }
        if ($favPacket.dispatched -ne $false) { throw 'A freshly packaged item must be dispatched=false' }
        # A candidate whose roadmap carries no estimate falls back to the default.
        $candPacket = @($pkgRun.packets | Where-Object { [string]$_.repoName -eq 'cand-ready' })[0]
        if ([double]$candPacket.estimatedWorkUnits -ne 3) { throw "Unannotated item must fall back to the default estimate; got $($candPacket.estimatedWorkUnits)" }

        # Append-only history + the two invariants defended at the writer.
        $null = Write-PackagingRunRecord -WorkspaceRoot $pkgWs -Run $pkgRun
        $pkgHistory = @(Get-PackagingRunHistory -WorkspaceRoot $pkgWs)
        if ($pkgHistory.Count -lt 1) { throw 'Packaging run history did not persist the run' }
        if ([string]$pkgHistory[0].runId -ne [string]$pkgRun.runId) { throw 'Packaging history newest-first ordering or runId mismatch' }
        foreach ($badCase in @(
            @{ Run = [pscustomobject]@{ runId = 'bad1'; appliedCount = 1; dispatchedCount = 0 }; Label = 'appliedCount != 0' },
            @{ Run = [pscustomobject]@{ runId = 'bad2'; appliedCount = 0; dispatchedCount = 1 }; Label = 'dispatchedCount != 0' }
        )) {
            $refused = $false
            try { $null = Write-PackagingRunRecord -WorkspaceRoot $pkgWs -Run $badCase.Run } catch { $refused = $true }
            if (-not $refused) { throw "Write-PackagingRunRecord must refuse a run claiming $($badCase.Label)" }
        }

        # Digest: what was packaged, what was skipped, and nothing dispatched.
        $pkgDigest = New-PackagingDigestPayload -Run $pkgRun
        if ([int]$pkgDigest.packagedCount -ne 2) { throw 'Digest packagedCount mismatch' }
        if ([int]$pkgDigest.dispatchedCount -ne 0) { throw 'Digest must report dispatchedCount=0' }
        if (@($pkgDigest.skipped).Count -lt 7) { throw 'Digest must carry the skipped repos and their reasons' }

        Write-Host ("  packaging run ok: {0} packet(s) queued for approval, dispatched=0 applied=0, dispatch queue absent, invariant-violating runs refused" -f $pkgRun.packagedCount) -ForegroundColor DarkGray

        Write-Step 'Packaging approval — smoke: the state machine is the only path to dispatch'
        $queued = @(Get-PackagedItemQueue -WorkspaceRoot $pkgWs)
        if ($queued.Count -ne 2) { throw "Expected 2 items in the approval queue; got $($queued.Count)" }
        if (@($queued | Where-Object { [string]$_.status -ne 'pending-approval' }).Count -ne 0) { throw 'Every freshly packaged item must be pending-approval' }
        $target = @($queued | Where-Object { [string]$_.repoName -eq 'fav-ready' })[0]

        foreach ($case in @(
            @{ From = 'pending-approval'; To = 'approved';   Want = $true  },
            @{ From = 'pending-approval'; To = 'rejected';   Want = $true  },
            @{ From = 'pending-approval'; To = 'dispatched'; Want = $false },   # never skip the gate
            @{ From = 'approved';        To = 'dispatched'; Want = $true  },
            @{ From = 'dispatched';      To = 'dispatched'; Want = $false },   # never dispatch twice
            @{ From = 'dispatched';      To = 'approved';   Want = $false },
            @{ From = 'rejected';        To = 'approved';   Want = $false },
            @{ From = '';                To = 'approved';   Want = $false }    # unknown packet
        )) {
            $verdict = Test-PackagedItemTransition -From $case.From -To $case.To
            if ([bool]$verdict.allowed -ne [bool]$case.Want) {
                throw "Transition '$($case.From)' -> '$($case.To)' expected allowed=$($case.Want); got $($verdict.allowed)"
            }
            if (-not $verdict.allowed -and [string]::IsNullOrWhiteSpace([string]$verdict.reason)) {
                throw "A refused transition must carry a named reason ('$($case.From)' -> '$($case.To)')"
            }
        }
        if ([string](Test-PackagedItemTransition -From '' -To 'approved').reason -ne 'packet-not-found') { throw 'An unknown packet must refuse with packet-not-found' }

        # Approve -> dispatch: the queue entry and the run summary the operator
        # runner claims on must BOTH appear, or the task is one nothing picks up.
        $null = Write-PackagedItemRecord -WorkspaceRoot $pkgWs -Record ([pscustomobject]@{
            schemaVersion = '1'; packetId = $target.packetId; runId = $pkgRun.runId; repoName = 'fav-ready'
            status = 'approved'; recordedAt = (Get-Date).ToUniversalTime().ToString('o'); actor = 'module-smoke'; note = 'approved'
        })
        $dispatch = Submit-PackagedItemToRunner -WorkspaceRoot $pkgWs -Packet $target.packet -Actor 'module-smoke'
        if (-not (Test-Path -LiteralPath $dispatch.queuePath)) { throw 'Dispatch did not write the runner queue entry' }
        if (-not (Test-Path -LiteralPath $dispatch.summaryPath)) { throw 'Dispatch did not write the run summary the runner claims on' }
        $summaryStatus = [string]((Get-Content -LiteralPath $dispatch.summaryPath -Raw -Encoding UTF8 | ConvertFrom-Json).status)
        if ($summaryStatus -ne 'queued') { throw "Run summary must read status=queued for the runner to claim it; got '$summaryStatus'" }
        $null = Write-PackagedItemRecord -WorkspaceRoot $pkgWs -Record ([pscustomobject]@{
            schemaVersion = '1'; packetId = $target.packetId; runId = $pkgRun.runId; repoName = 'fav-ready'
            status = 'dispatched'; recordedAt = (Get-Date).ToUniversalTime().ToString('o'); actor = 'module-smoke'
            dispatchRunId = $dispatch.runId; note = 'enqueued'
        })

        $folded = Get-PackagedItem -WorkspaceRoot $pkgWs -PacketId $target.packetId
        if ([string]$folded.status -ne 'dispatched') { throw "Fold must take the newest status; got '$($folded.status)'" }
        if ([string]$folded.dispatchRunId -ne [string]$dispatch.runId) { throw 'Fold lost the dispatch run id' }
        if (@($folded.history).Count -ne 3) { throw "Append-only history must keep every transition; got $(@($folded.history).Count)" }
        if ([string]@($folded.history)[0].status -ne 'pending-approval') { throw 'History must start at pending-approval' }
        if ($null -eq $folded.packet) { throw 'Fold lost the packet body carried by the first record' }
        # The other packet is untouched — approving one never approves the rest.
        $untouched = @(Get-PackagedItemQueue -WorkspaceRoot $pkgWs -Status 'pending-approval')
        if ($untouched.Count -ne 1 -or [string]$untouched[0].repoName -ne 'cand-ready') {
            throw 'Approving one packet must not change any other packet''s state'
        }
        Write-Host ("  packaging approval ok: 8 transitions enforced, queue+summary written on dispatch, fold keeps 3-step history, sibling packet untouched") -ForegroundColor DarkGray
    }
    finally {
        Remove-Item -LiteralPath $pkgWs -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Step 'Packaging queue contract — tripwire: the entry shape the runner claims must not drift'
& {
    $root = $WorkspaceRoot
    . (Join-Path $root 'scripts\Add-RoadmapTaskToQueue.ps1') -LoadFunctionsOnly
    # The runner reads entries written by BOTH writers. If Add-RoadmapTaskToQueue's
    # shape changes and the packaging writer's does not, approved work would land
    # in the queue as entries the runner silently mishandles — invisible until an
    # operator wonders why an approved packet never ran.
    $canonical = New-RoadmapQueueEntry -RunId 'r1' -Repository 'owner/x' -LocalRepoPath 'C:\repo' -RoadmapPath 'C:\repo\ROADMAP.md' -SelectedTask 'Task' -TaskDescription 'PROMPT' -Branch 'b' -QueuedAt '2026-01-01T00:00:00Z'
    $packaged = New-PackagedItemQueueEntry -RunId 'r1' -QueuedAt '2026-01-01T00:00:00Z' -Packet ([pscustomobject]@{
        repoName = 'owner/x'; repoPath = 'C:\repo'; roadmapPath = 'C:\repo\ROADMAP.md'; itemText = 'Task'; generatedPrompt = 'PROMPT'; branch = 'b'
    })
    $canonicalKeys = @($canonical.Keys | Sort-Object) -join ','
    $packagedKeys = @($packaged.Keys | Sort-Object) -join ','
    if ($canonicalKeys -ne $packagedKeys) {
        throw "Queue-entry drift: Add-RoadmapTaskToQueue writes [$canonicalKeys] but the packaging writer writes [$packagedKeys]"
    }
    foreach ($k in $canonical.Keys) {
        if ([string]$canonical[$k] -ne [string]$packaged[$k]) {
            throw "Queue-entry drift on '$k': canonical='$($canonical[$k])' packaged='$($packaged[$k])'"
        }
    }
    Write-Host ("  queue contract ok: {0} fields identical to the canonical writer" -f @($canonical.Keys).Count) -ForegroundColor DarkGray
}

Write-Step 'Smoke test completed'
