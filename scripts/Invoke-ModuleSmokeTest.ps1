[CmdletBinding()]
param(
    [string]$WorkspaceRoot = 'G:\Development\GitHubRepoManagement'
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
$docAuditScanner = Join-Path $WorkspaceRoot 'backend\modules\docaudit\DocAudit.Scanner.ps1'
$docStandards = Join-Path $WorkspaceRoot 'backend\config\doc-standards.json'
$agentBudgetModule = Join-Path $WorkspaceRoot 'backend\modules\agent-runs\BudgetLedger.ps1'

Write-Step 'Loading reconciliation module functions only'
& $reconcile -LoadFunctionsOnly
Write-Host 'Loaded reconciliation module successfully' -ForegroundColor Green

Write-Step 'Validating copied module files exist'
@($docInventory, $docQueue, $docBatch, $reconcile, $reconcileModular, $reconcileTests, $roadmapParser, $roadmapAuditor, $roadmapEvaluatorPath, $roadmapRepairerPath, $docAuditScanner, $docStandards, $agentBudgetModule) | ForEach-Object {
    if (-not (Test-Path -LiteralPath $_)) {
        throw "Missing module file: $_"
    }
}
Write-Host 'All expected module files are present' -ForegroundColor Green

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
            'merge_readiness_snapshots', 'agent_runs', 'agent_run_events'
        )
        foreach ($tableName in $expectedAppDbTables) {
            if ($tableName -notin @($appDbInit.tables)) { throw "Missing expected table '$tableName' (got: $(@($appDbInit.tables) -join ', '))" }
        }
        $appDbReinit = Initialize-AppDatabase -WorkspaceRoot $appDbWorkspace
        if (-not $appDbReinit.success) { throw "Re-init must be idempotent: $($appDbReinit.error)" }
        $migrationRows = Invoke-AppDbQuery -DatabasePath $appDbInit.databasePath -Sql 'SELECT COUNT(*) AS n FROM schema_migrations'
        if ([long]$migrationRows[0].n -ne 1) { throw "Expected exactly 1 schema migration row after re-init, got $($migrationRows[0].n)" }
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
    }
    finally {
        Remove-Item -LiteralPath $appDbWorkspace -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Step 'Smoke test completed'
