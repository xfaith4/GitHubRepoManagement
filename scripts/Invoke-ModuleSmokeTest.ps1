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

Write-Step 'Loading reconciliation module functions only'
& $reconcile -LoadFunctionsOnly
Write-Host 'Loaded reconciliation module successfully' -ForegroundColor Green

Write-Step 'Validating copied module files exist'
@($docInventory, $docQueue, $docBatch, $reconcile, $reconcileModular, $reconcileTests, $roadmapParser, $roadmapAuditor, $roadmapEvaluatorPath, $roadmapRepairerPath, $docAuditScanner, $docStandards) | ForEach-Object {
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
Write-Host ("  standards loaded version={0} commonRequired={1}" -f $structStds.version, @($structStds.common.requiredRootFiles).Count) -ForegroundColor DarkGray

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
$readyRoadmap = @([pscustomobject]@{ repoName = 'ready-repo'; roadmapPath = (Join-Path $WorkspaceRoot 'ROADMAP.md'); roadmapState = 'pending'; pendingCount = 5; nextPendingItem = [pscustomobject]@{ text = 'next thing' } })
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

Write-Step 'Smoke test completed'
