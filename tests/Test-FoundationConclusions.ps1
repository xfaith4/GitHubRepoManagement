#Requires -Version 7.0
<#
.SYNOPSIS
    Property checks over the foundation-conclusion model, selected by -Assert.

.DESCRIPTION
    One script, one assertion family per -Assert value, each a property the
    model must hold - never a distribution target over the cohort (steering
    section 6). The trial cohort (-Cohort) and the local index, where present,
    are assessed as real data; CI has neither and says so.

      lifecycle-consistency  (steering extension 3, Rung 1)
        lifecycleState and conclusion are two verdicts over the same signals
        and may not disagree without saying why. Asserts: every lifecycle
        state the assessment can emit is in lifecycleConsistency.allowed;
        every exception names states and conclusions from the vocabularies and
        carries a pattern that compiles; fixtures reach each agreement class
        (allowed, explained) and the validator goes red on a manufactured
        contradiction and on an unlisted lifecycle state; every record in the
        local index and every cohort repository holds.

      applicability          (3.7 M4b - not implemented yet; exits 1)
      action-routing         (3.7 M4c - not implemented yet; exits 1)

.EXAMPLE
    pwsh ./tests/Test-FoundationConclusions.ps1 -Cohort evidence/trials/release-3.7/cohort.json -Assert lifecycle-consistency -FailOnError
#>
[CmdletBinding()]
param(
    [Parameter()][string]$WorkspaceRoot = (Split-Path -Parent $PSScriptRoot),
    [Parameter()][string]$Cohort = '',
    [Parameter()][string]$IndexPath = '',
    [Parameter(Mandatory = $true)][ValidateSet('lifecycle-consistency', 'applicability', 'action-routing')][string]$Assert,
    [Parameter()][switch]$FailOnError
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($Assert -ne 'lifecycle-consistency') {
    Write-Host "  FAIL: -Assert $Assert is not implemented yet (3.7 M4b/M4c); nothing is proved" -ForegroundColor Red
    exit 1
}

$portfolioRoot = Join-Path $WorkspaceRoot 'backend\modules\portfolio'
. (Join-Path $portfolioRoot 'Portfolio.Conclusion.ps1')
$config = Get-FoundationDomainsConfig -ConfigPath (Join-Path $WorkspaceRoot 'backend\config\foundation-domains.json')
if ($null -eq $config) { throw 'foundation-domains.json did not load' }
$table = $config.lifecycleConsistency
if ($null -eq $table) { throw 'foundation-domains.json carries no lifecycleConsistency table' }

$failures = [System.Collections.Generic.List[string]]::new()
$notes = [System.Collections.Generic.List[string]]::new()

# --- The table covers the assessment's whole vocabulary -------------------
# The list the assessment reports by (Portfolio.Assessment.ps1 byLifecycle);
# read from the source so a new state cannot be added without a row here.
$assessmentSource = Get-Content -LiteralPath (Join-Path $portfolioRoot 'Portfolio.Assessment.ps1') -Raw -Encoding UTF8
$vocabMatch = [regex]::Match($assessmentSource, '(?s)\$byLifecycle\s*=\s*@\{\}\s*foreach\s*\(\$state in @\((.*?)\)\)')
if (-not $vocabMatch.Success) { throw 'could not read the lifecycle vocabulary from Portfolio.Assessment.ps1 ($byLifecycle list)' }
$lifecycleVocabulary = @([regex]::Matches($vocabMatch.Groups[1].Value, "'([a-z-]+)'") | ForEach-Object { $_.Groups[1].Value })
$conclusionVocabulary = @($config.conclusions.PSObject.Properties.Name)
$allowedStates = @($table.allowed.PSObject.Properties.Name)
foreach ($state in $lifecycleVocabulary) {
    if ($state -notin $allowedStates) { $failures.Add("lifecycle state '$state' (assessment vocabulary) has no lifecycleConsistency.allowed row") }
}
foreach ($state in $allowedStates) {
    if ($state -notin $lifecycleVocabulary) { $failures.Add("lifecycleConsistency.allowed lists '$state', which the assessment never emits") }
    foreach ($c in @($table.allowed.$state)) { if ([string]$c -notin $conclusionVocabulary) { $failures.Add("allowed['$state'] names conclusion '$c' outside the configured set") } }
}
foreach ($ex in @($table.exceptions)) {
    $st = [string]$ex.lifecycleState; $co = [string]$ex.conclusion
    if ($st -ne '*' -and $st -notin $lifecycleVocabulary) { $failures.Add("exception names lifecycle state '$st' outside the vocabulary") }
    if ($co -ne '*' -and $co -notin $conclusionVocabulary) { $failures.Add("exception names conclusion '$co' outside the configured set") }
    if ([string]::IsNullOrWhiteSpace([string]$ex.explanation)) { $failures.Add("exception ($st, $co) carries no explanation") }
    try { $null = [regex]::new([string]$ex.requires) } catch { $failures.Add("exception ($st, $co) pattern does not compile: $($ex.requires)") }
}

# --- Fixtures: each agreement class, then the validator proved red ----------
function ConvertTo-Entry([hashtable]$Overrides) {
    $base = @{ repoId = 'repo:x'; repoName = 'x'; sourceCoverage = 'local'; localPath = (Join-Path $WorkspaceRoot 'output\foundation-conclusions\x'); lastScanStatus = 'ok'
        lifecycleState = 'discovered'; curationState = 'none'; hasReadme = $true; readmeScore = 80; docFindingCount = 0; hasRoadmap = $true; roadmapState = 'pending'
        maturityLevel = 'L3-Contract-Ready'; pendingCount = 2; repoType = 'other'; structureFindings = @(); hasCiSignal = $false; hasTestSignal = $false
        latestWorkflowRunConclusion = $null; localCommitsLastMonth = 0; technologies = @(); kindSignals = $null }
    foreach ($k in $Overrides.Keys) { $base[$k] = $Overrides[$k] }
    $base['repoId'] = 'repo:' + [string]$base['repoName']
    return [pscustomobject]$base
}
$fixtures = @(
    # allowed
    (ConvertTo-Entry @{ repoName = 'archived-ok'; lifecycleState = 'archived' }),
    (ConvertTo-Entry @{ repoName = 'no-checklist'; lifecycleState = 'no-checklist'; roadmapState = 'no-checklist' }),
    (ConvertTo-Entry @{ repoName = 'needs-roadmap'; lifecycleState = 'needs-roadmap'; hasRoadmap = $false; roadmapState = 'missing'; maturityLevel = 'L0-Absent'; pendingCount = 0 }),
    (ConvertTo-Entry @{ repoName = 'completed-fine'; lifecycleState = 'completed'; roadmapState = 'complete'; pendingCount = 0 }),
    # explained: the lifecycle model does not read curation; the kind rule does
    (ConvertTo-Entry @{ repoName = 'curated-archive'; lifecycleState = 'needs-roadmap-repair'; curationState = 'archived-ignore'; maturityLevel = 'L0-Absent' }),
    # explained: no local checkout - the lifecycle reads the missing README, the conclusion names the need
    (ConvertTo-Entry @{ repoName = 'github-only'; lifecycleState = 'needs-readme'; sourceCoverage = 'github'; localPath = ''; hasReadme = $false; readmeScore = 0 })
)
$expectedAgreement = @{ 'archived-ok' = 'allowed'; 'no-checklist' = 'allowed'; 'needs-roadmap' = 'allowed'; 'completed-fine' = 'allowed'; 'curated-archive' = 'explained'; 'github-only' = 'explained' }
$payload = Get-PortfolioConclusionsPayload -Entries $fixtures -Config $config
if (-not $payload.contract.holds) { $failures.Add("fixture set violates the contract: $($payload.contract.violations -join '; ')") }
foreach ($item in @($payload.items)) {
    $name = [string]$item.repoName
    $c = $item.consistency
    if ($null -eq $c) { $failures.Add("${name} carries no consistency record"); continue }
    if ([string]$c.agreement -ne $expectedAgreement[$name]) { $failures.Add("${name}: agreement '$($c.agreement)' expected '$($expectedAgreement[$name])' (lifecycle=$($c.lifecycleState) conclusion=$($c.conclusion): $($c.explanation))") }
    if ([string]$c.agreement -eq 'explained' -and @($c.evidence).Count -eq 0) { $failures.Add("$name is explained but cites no evidence") }
    Write-Host ('  {0,-16} {1,-21} + {2,-25} -> {3}{4}' -f $name, $c.lifecycleState, $c.conclusion, $c.agreement, $(if (@($c.evidence).Count -gt 0) { " (evidence: $($c.evidence[0]))" } else { '' }))
}

# Red first: the validator must reject a contradiction and an unlisted state
# before its green verdict on real data means anything.
$contradiction = Get-RepositoryFoundationConclusion -Entry (ConvertTo-Entry @{ repoName = 'contradiction'; lifecycleState = 'needs-readme'; readmeScore = 95 }) -Config $config
$red = @(Test-FoundationConclusion -Conclusion $contradiction -Config $config)
if ([string]$contradiction.consistency.agreement -ne 'contradiction') { $failures.Add("the manufactured contradiction (needs-readme + $($contradiction.conclusion)) was classified '$($contradiction.consistency.agreement)'") }
if (@($red | Where-Object { $_ -match 'disagree and nothing in the basis explains it' }).Count -eq 0) { $failures.Add("validator did not go red on the contradiction (violations: $($red -join '; '))") }
$unlisted = Get-RepositoryFoundationConclusion -Entry (ConvertTo-Entry @{ repoName = 'unlisted'; lifecycleState = 'bogus-state' }) -Config $config
if (@(Test-FoundationConclusion -Conclusion $unlisted -Config $config | Where-Object { $_ -match 'not in lifecycleConsistency.allowed' }).Count -eq 0) { $failures.Add('validator did not go red on a lifecycle state the table does not list') }

# --- Real data: the local index and the cohort, where present ---------------
if ([string]::IsNullOrWhiteSpace($IndexPath)) { $IndexPath = Join-Path $WorkspaceRoot 'output\index\repos.index.json' }
$cohortNames = @()
if (-not [string]::IsNullOrWhiteSpace($Cohort)) {
    $cohortPath = if ([System.IO.Path]::IsPathRooted($Cohort)) { $Cohort } else { Join-Path $WorkspaceRoot $Cohort }
    if (-not (Test-Path -LiteralPath $cohortPath)) { $failures.Add("cohort file not found: $cohortPath") }
    else { $cohortNames = @((ConvertFrom-Json -InputObject (Get-Content -LiteralPath $cohortPath -Raw -Encoding UTF8)).records | Where-Object { [string]$_.selectionStatus -eq 'selected' } | ForEach-Object { [string]$_.repository }) }
}
if (Test-Path -LiteralPath $IndexPath) {
    $index = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $IndexPath -Raw -Encoding UTF8)
    $rows = @($index.repos)
    $live = Get-PortfolioConclusionsPayload -Entries $rows -Config $config
    $counts = $live.byConsistency
    $generated = $index.generatedAt
    if ($generated -is [datetime]) { $generated = $generated.ToUniversalTime().ToString('o') }
    $notes.Add(('local index {0}: {1} repositories - allowed {2}, explained {3}, contradiction {4}, unknown-lifecycle {5}' -f [string]$generated, $rows.Count, $counts.allowed, $counts.explained, $counts.contradiction, $counts.'unknown-lifecycle'))
    foreach ($item in @($live.items)) {
        $c = $item.consistency
        if ($null -eq $c -or -not $c.holds) { $failures.Add(("index: {0} ({1} + {2}): {3}" -f $item.repoName, $item.lifecycleState, $item.conclusion, $(if ($null -eq $c) { 'no consistency record' } else { $c.explanation }))) }
    }
    $seen = 0
    foreach ($name in $cohortNames) {
        $item = @($live.items | Where-Object { [string]$_.repoName -eq $name } | Select-Object -First 1)
        if ($item.Count -eq 0) { $notes.Add("cohort: $name is not in the local index"); continue }
        $seen++
        $c = $item[0].consistency
        Write-Host ('  cohort {0,-27} {1,-21} + {2,-25} -> {3}' -f $name, $c.lifecycleState, $c.conclusion, $c.agreement)
    }
    if ($cohortNames.Count -gt 0) { $notes.Add("cohort: $seen of $($cohortNames.Count) repositories assessed from the local index") }
} else {
    $notes.Add("no local index at $IndexPath - index and cohort passes skipped (CI has no portfolio; the fixtures and the vocabulary check ran)")
}

Write-Host 'Lifecycle/conclusion consistency (steering extension 3):'
foreach ($n in $notes) { Write-Host "  $n" }
if ($failures.Count -eq 0) {
    Write-Host ("  ok: {0} lifecycle states covered, {1} exceptions well-formed, {2} fixtures across allowed/explained, validator red on a contradiction and an unlisted state" -f $lifecycleVocabulary.Count, @($table.exceptions).Count, $fixtures.Count) -ForegroundColor Green
    exit 0
}
foreach ($f in $failures) { Write-Host "  FAIL: $f" -ForegroundColor Red }
if ($FailOnError) { exit 1 }
exit 0
