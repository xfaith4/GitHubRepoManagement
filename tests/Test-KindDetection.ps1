#Requires -Version 7.0
<#
.SYNOPSIS
    Release 3.7 M4a check: repository kind resolves from manifests, entry points and the README purpose line.

.DESCRIPTION
    Builds one throwaway checkout per kind under output/kind-detection/, runs
    the scan-time signal scanner (Portfolio.KindSignals.ps1 over
    backend/config/kind-signals.json) and the config's kindDetection rules
    (Portfolio.Conclusion.ps1 + foundation-domains.json) over each, and asserts:

      - library, firmware, application, experiment and tooling each resolve
        from their own signals, not only `archived`;
      - every hint carries an evidence line a person can read;
      - the v1 field-equality rules still resolve `archived`;
      - a github-only entry (no checkout) stays `unknown`;
      - an `unknown` with hints names them, so the next rule is a data change
        (steering Rung 1);
      - every matching rule is a ranked candidate and the first is the kind;
      - a manifest-vs-README disagreement is an observation with
        canonicalEffect none and its provenance, and changes no verdict
        (steering extension 2);
      - the opinions live in config: kind-signals.json loads, every group and
        wording rule carries observedOn, every whenAny rule carries observedOn,
        and each index entry is stamped with the signal model (contract 6);
      - every conclusion record and the portfolio payload carry
        modelVersion = foundation-conclusions v2.1 beside the index identity;
      - the canonical kind is the first matching rule in config order, and the
        candidates are that walk's distinct kinds - no score participates;
      - replaying the current rules over the recorded v2 signals for the nine
        cohort repositories (evidence/trials/release-3.7/kind-baseline-v2.json)
        yields zero kind deltas; where the checkouts exist at the recorded
        commits, the current scanner reproduces the recorded hints and the
        SHA-256 of each README purpose line. The baseline carries no README
        text (public repository), and the check fails if it ever does.

    Exit 0 when every assertion holds. With -FailOnError, exit 1 on any
    failure; without it, the failures print and the exit code stays 0.

.EXAMPLE
    pwsh ./tests/Test-KindDetection.ps1 -FailOnError
#>
[CmdletBinding()]
param(
    [Parameter()][string]$WorkspaceRoot = (Split-Path -Parent $PSScriptRoot),
    [Parameter()][switch]$FailOnError
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$portfolioRoot = Join-Path $WorkspaceRoot 'backend\modules\portfolio'
. (Join-Path $portfolioRoot 'Portfolio.KindSignals.ps1')
. (Join-Path $portfolioRoot 'Portfolio.Conclusion.ps1')
$configPath = Join-Path $WorkspaceRoot 'backend\config\foundation-domains.json'
$config = Get-FoundationDomainsConfig -ConfigPath $configPath
if ($null -eq $config) { throw "foundation-domains.json did not load from $configPath" }
$signalConfigPath = Join-Path $WorkspaceRoot 'backend\config\kind-signals.json'
$signalConfig = Get-KindSignalConfig -ConfigPath $signalConfigPath
$expectedModel = 'foundation-conclusions v2.1'
$expectedSignalModel = 'kind-signals v1'

$fixtureRoot = Join-Path $WorkspaceRoot 'output\kind-detection'
if (Test-Path -LiteralPath $fixtureRoot) { Remove-Item -LiteralPath $fixtureRoot -Recurse -Force }
New-Item -ItemType Directory -Path $fixtureRoot -Force | Out-Null

function Add-FixtureCheckout {
    param([string]$Name, [hashtable]$Files)
    $dir = Join-Path $fixtureRoot $Name
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    foreach ($rel in $Files.Keys) {
        $path = Join-Path $dir $rel
        $parent = Split-Path -Parent $path
        if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        [System.IO.File]::WriteAllText($path, [string]$Files[$rel], [System.Text.UTF8Encoding]::new($false))
    }
    return $dir
}

function ConvertTo-IndexEntry {
    param([string]$Name, [string]$LocalPath, [hashtable]$Overrides = @{})
    $entry = [ordered]@{
        repoId = "repo:$Name"; repoName = $Name; sourceCoverage = 'local'; localPath = $LocalPath; lastScanStatus = 'ok'
        lifecycleState = 'discovered'; curationState = 'none'; hasReadme = $true; readmeScore = 70; docFindingCount = 0
        hasRoadmap = $false; roadmapState = 'missing'; maturityLevel = 'L0-Absent'; pendingCount = 0; repoType = 'other'
        structureFindings = @(); hasCiSignal = $false; hasTestSignal = $false; latestWorkflowRunConclusion = $null; localCommitsLastMonth = 0
        technologies = @()
        kindSignals = (Get-RepoKindSignalProfile -LocalPath $LocalPath -Config $signalConfig)
    }
    foreach ($k in $Overrides.Keys) { $entry[$k] = $Overrides[$k] }
    return [pscustomobject]$entry
}

$checkouts = [ordered]@{
    'ps-library'     = @{ 'README.md' = "# Paged Client`n`nA retrying pagination **wrapper** for a generic REST API.`n"; 'src/PagedClient.psd1' = "@{`n    RootModule = 'PagedClient.psm1'`n    ModuleVersion = '1.0.0'`n}`n"; 'src/PagedClient.psm1' = "function Get-Thing { 1 }`n" }
    'led-firmware'   = @{ 'README.md' = "# Strip Lights`n`nGenerates sketches for a light strip and serves them to a browser.`n"; 'package.json' = '{ "name": "led-web", "private": true, "dependencies": { "express": "^4", "react": "^18" } }'; 'sketches/strip/strip.ino' = "void setup() {}`nvoid loop() {}`n" }
    'family-app'     = @{ 'README.md' = "# Photo Wall`n`n**A photo gallery served as a static web app.** _(demo)_`n"; 'index.html' = '<!doctype html><title>x</title>'; 'package.json' = '{ "name": "photo-wall", "private": true, "dependencies": { "firebase": "^10" } }' }
    'proto'          = @{ 'README.md' = "# Job Runner`n`n![badge](https://x/y.svg)`n`nA phase-0 prototype of a job runner; nothing here is stable yet.`n"; 'package.json' = '{ "name": "proto", "private": true, "dependencies": { "express": "^4" } }' }
    'port-console'   = @{ 'README.md' = "# Port List`n`nA desktop utility that lists which local ports are in use.`n"; 'PortList.ps1' = "'hi'`n"; 'PortList.Tests.ps1' = "Describe 'x' {}`n"; 'PSScriptAnalyzerSettings.psd1' = "@{ Severity = @('Error') }`n" }
    'node-lib'       = @{ 'README.md' = "# tiny-dates`n`n> Zero-dependency helpers for calendar math.`n"; 'package.json' = '{ "name": "tiny-dates", "version": "1.2.0", "main": "index.js", "exports": "./index.js" }'; 'index.js' = 'module.exports = {};' }
    'closed'         = @{ 'README.md' = "# Old Toolbox`n`nA toolbox of scripts, no longer maintained.`n"; 'OldToolbox.ps1' = "'x'`n" }
    # A workspace root: a manifest that says nothing about what the packages are, and a purpose line that names them.
    'workspace-root' = @{ 'README.md' = "# Workspace`n`nThe root of a monorepo holding three workspaces: web, worker, common.`n"; 'package.json' = '{ "name": "workspace", "private": true, "workspaces": ["packages/*"] }' }
    # A served page beside a helper module, with a README that reads as a quick-start line: the manifests and the words disagree.
    'score-app'      = @{ 'README.md' = "# Scores`n`nUse the bound script and the sheet to record scores.`n"; 'Scores.psd1' = "@{`n    RootModule = 'Scores.psm1'`n    ModuleVersion = '2.0.0'`n}`n"; 'Scores.psm1' = "function Get-Score { 1 }`n"; 'public/index.html' = '<!doctype html><title>s</title>' }
}
$paths = [ordered]@{}
foreach ($name in $checkouts.Keys) { $paths[$name] = Add-FixtureCheckout -Name $name -Files $checkouts[$name] }

$entries = @(
    (ConvertTo-IndexEntry -Name 'ps-library'     -LocalPath $paths['ps-library']     -Overrides @{ repoType = 'powershell' }),
    (ConvertTo-IndexEntry -Name 'led-firmware'   -LocalPath $paths['led-firmware']   -Overrides @{ repoType = 'node' }),
    (ConvertTo-IndexEntry -Name 'family-app'     -LocalPath $paths['family-app']     -Overrides @{ repoType = 'node' }),
    (ConvertTo-IndexEntry -Name 'proto'          -LocalPath $paths['proto']          -Overrides @{ repoType = 'node' }),
    (ConvertTo-IndexEntry -Name 'port-console'   -LocalPath $paths['port-console']   -Overrides @{ repoType = 'powershell' }),
    (ConvertTo-IndexEntry -Name 'node-lib'       -LocalPath $paths['node-lib']       -Overrides @{ repoType = 'node' }),
    (ConvertTo-IndexEntry -Name 'closed'         -LocalPath $paths['closed']         -Overrides @{ repoType = 'powershell'; lifecycleState = 'archived' }),
    (ConvertTo-IndexEntry -Name 'workspace-root' -LocalPath $paths['workspace-root'] -Overrides @{ repoType = 'node' }),
    (ConvertTo-IndexEntry -Name 'score-app'      -LocalPath $paths['score-app']      -Overrides @{ repoType = 'powershell' }),
    (ConvertTo-IndexEntry -Name 'github-only'    -LocalPath ''                       -Overrides @{ sourceCoverage = 'github'; hasReadme = $false; readmeScore = 0 })
)

$expected = [ordered]@{
    'ps-library' = 'library'; 'led-firmware' = 'firmware'; 'family-app' = 'application'; 'proto' = 'experiment'
    'port-console' = 'tooling'; 'node-lib' = 'library'; 'closed' = 'archived'; 'workspace-root' = 'unknown'
    'score-app' = 'application'; 'github-only' = 'unknown'
}
$expectedHint = [ordered]@{
    'ps-library' = 'module-manifest'; 'led-firmware' = 'firmware-target'; 'family-app' = 'web-app'; 'proto' = 'experiment-wording'
    'port-console' = 'script-entry'; 'node-lib' = 'library-manifest'; 'workspace-root' = 'monorepo'; 'score-app' = 'module-manifest'
}

$failures = [System.Collections.Generic.List[string]]::new()
$rows = [System.Collections.Generic.List[string]]::new()
$verdicts = @{}
foreach ($entry in $entries) {
    $name = [string]$entry.repoName
    $verdict = Resolve-RepositoryKind -Entry $entry -Config $config
    $verdicts[$name] = $verdict
    $hints = @($entry.kindSignals.hints)
    $ranked = @($verdict.candidates | ForEach-Object { [string]$_.kind })
    $rows.Add(('  {0,-14} -> {1,-12} [{2}] ranked: {3}; hints: {4}' -f $name, $verdict.kind, $verdict.basis, ($ranked -join ' > '), ($hints -join ', ')))
    if ([string]$verdict.kind -ne $expected[$name]) { $failures.Add("$name resolved '$($verdict.kind)', expected '$($expected[$name])' (hints: $($hints -join ', '))") }
    if ($expectedHint.Contains($name) -and $expectedHint[$name] -notin $hints) { $failures.Add("$name is missing the hint '$($expectedHint[$name])' (hints: $($hints -join ', '))") }
    if ($hints.Count -ne @($entry.kindSignals.evidence).Count) { $failures.Add("$name has $($hints.Count) hints but $(@($entry.kindSignals.evidence).Count) evidence lines") }
    if ($name -ne 'github-only' -and [string]::IsNullOrWhiteSpace([string]$entry.kindSignals.readmePurpose)) { $failures.Add("$name has no README purpose line") }
    if ([string]$entry.kindSignals.signalModel -ne $expectedSignalModel) { $failures.Add("$name kindSignals.signalModel is '$($entry.kindSignals.signalModel)', expected '$expectedSignalModel'") }
    if ($ranked.Count -gt 0 -and $ranked[0] -ne [string]$verdict.kind) { $failures.Add("$name kind '$($verdict.kind)' is not its first ranked candidate ($($ranked -join ' > '))") }
    if (@($verdict.hints).Count -ne $hints.Count) { $failures.Add("$name verdict carries $(@($verdict.hints).Count) hints but the entry has $($hints.Count)") }
    foreach ($c in @($verdict.candidates)) {
        if (@($c.matchedOn).Count -eq 0) { $failures.Add("$name candidate '$($c.kind)' says nothing about what it matched on") }
    }
}

# Ranked candidates keep honest ambiguity visible: firmware beside the web app that serves it.
$ledRanked = @($verdicts['led-firmware'].candidates | ForEach-Object { [string]$_.kind })
if ('application' -notin $ledRanked) { $failures.Add("led-firmware ranks only ($($ledRanked -join ' > ')); the served web app should be a second candidate") }

# An unknown with hints names them; an unknown with none says so.
$wsBasis = [string]$verdicts['workspace-root'].basis
if ($wsBasis -notmatch 'monorepo') { $failures.Add("workspace-root is unknown but its basis does not name the hint it saw: '$wsBasis'") }
$ghBasis = [string]$verdicts['github-only'].basis
if ($ghBasis -ne 'no kind signal in the index; every scored domain applies') { $failures.Add("github-only unknown basis changed to '$ghBasis'") }

# The kinds the milestone names must each be reached by a rule; every whenAny
# rule names where it was observed; the config says which kind a hint speaks for.
$kindIds = @($config.kinds | ForEach-Object { [string]$_.id })
foreach ($required in @('library', 'firmware', 'application', 'experiment', 'tooling')) {
    if ($required -notin $kindIds) { $failures.Add("foundation-domains.json does not define the kind '$required'") }
    if (@($config.kindDetection.rules | Where-Object { [string]$_.kind -eq $required }).Count -eq 0) { $failures.Add("no kindDetection rule resolves '$required'") }
}
foreach ($rule in @($config.kindDetection.rules)) {
    if ($null -eq $rule.PSObject.Properties['whenAny']) { continue }
    if ($null -eq $rule.PSObject.Properties['observedOn']) { $failures.Add("kindDetection rule for '$($rule.kind)' carries no observedOn") }
}
if ($null -eq $config.kindDetection.PSObject.Properties['hintKinds']) { $failures.Add('foundation-domains.json kindDetection has no hintKinds map') }
if ([string]$config.modelVersion -ne $expectedModel) { $failures.Add("foundation-domains.json modelVersion is '$($config.modelVersion)', expected '$expectedModel'") }

# kind-signals.json: opinions in config, each with the repositories it was observed on.
if ([string]$signalConfig.modelVersion -ne $expectedSignalModel) { $failures.Add("kind-signals.json modelVersion is '$($signalConfig.modelVersion)', expected '$expectedSignalModel'") }
foreach ($group in @('firmware', 'powershell', 'servedPage', 'node', 'dotnet', 'python')) {
    $g = $signalConfig.$group
    if ($null -eq $g.PSObject.Properties['observedOn']) { $failures.Add("kind-signals.json group '$group' carries no observedOn") }
}
foreach ($w in @($signalConfig.wording)) {
    if ([string]::IsNullOrWhiteSpace([string]$w.hint) -or [string]::IsNullOrWhiteSpace([string]$w.pattern)) { $failures.Add('kind-signals.json wording rule missing hint or pattern') }
    if ($null -eq $w.PSObject.Properties['observedOn']) { $failures.Add("kind-signals.json wording rule '$($w.hint)' carries no observedOn") }
    if ($null -eq $config.kindDetection.hintKinds.PSObject.Properties[[string]$w.hint]) { $failures.Add("hintKinds does not say which kind '$($w.hint)' speaks for") }
}

# Conclusion records: modelVersion, ranked candidates, hints and observations on every one.
$payload = Get-PortfolioConclusionsPayload -Entries $entries -Config $config
if ([string]$payload.modelVersion -ne $expectedModel) { $failures.Add("conclusions payload modelVersion is '$($payload.modelVersion)'") }
$byName = @{}
foreach ($item in @($payload.items)) {
    $byName[[string]$item.repoName] = $item
    if ([string]$item.modelVersion -ne $expectedModel) { $failures.Add("conclusion record for $($item.repoName) carries modelVersion '$($item.modelVersion)'") }
    foreach ($field in @('kindCandidates', 'kindHints', 'observations')) {
        if ($null -eq $item.PSObject.Properties[$field]) { $failures.Add("conclusion record for $($item.repoName) has no '$field'") }
    }
    foreach ($o in @($item.observations)) {
        if ([string]$o.canonicalEffect -ne 'none') { $failures.Add("$($item.repoName) observation '$($o.id)' has canonicalEffect '$($o.canonicalEffect)'") }
        if ($null -eq $o.provenance -or [string]::IsNullOrWhiteSpace([string]$o.provenance.source)) { $failures.Add("$($item.repoName) observation '$($o.id)' carries no provenance") }
    }
}
if (-not $payload.contract.holds) { $failures.Add("conclusion contract violated: $($payload.contract.violations -join '; ')") }
$unknownCount = @($payload.items | Where-Object { [string]$_.kind -eq 'unknown' }).Count
if ($unknownCount -ne 2) { $failures.Add("$unknownCount conclusions are 'unknown'; only github-only and workspace-root should be") }

# The coherence observation: manifests say library/application, the README says tooling - observed, and the verdict unchanged.
$scoreObs = @($byName['score-app'].observations | Where-Object { [string]$_.id -eq 'kind-coherence' })
if ($scoreObs.Count -ne 1) { $failures.Add("score-app should carry exactly one kind-coherence observation, has $($scoreObs.Count)") }
elseif ([string]$scoreObs[0].statement -notmatch 'tooling' -or [string]$scoreObs[0].statement -notmatch 'library') { $failures.Add("score-app coherence statement does not name both sides: '$($scoreObs[0].statement)'") }
if ([string]$byName['score-app'].kind -ne 'application') { $failures.Add("the observation changed score-app's verdict to '$($byName['score-app'].kind)'") }
foreach ($agreeing in @('ps-library', 'family-app', 'port-console')) {
    if (@($byName[$agreeing].observations | Where-Object { [string]$_.id -eq 'kind-coherence' }).Count -ne 0) { $failures.Add("$agreeing manifests and README agree but a coherence observation was emitted") }
}

# The canonical kind is the first matching rule in config order and nothing
# else: re-derive the pick here without the engine, and require the engine's
# candidates to be that walk's distinct kinds in the same order. No score
# participates - a future one would break this assertion.
function Test-RuleMatch {
    param([object]$Rule, [object]$Entry)
    $when = $Rule.PSObject.Properties['when']; $whenAny = $Rule.PSObject.Properties['whenAny']
    if ($null -eq $when -and $null -eq $whenAny) { return $false }
    $matchedAnything = $false
    if ($null -ne $when) {
        foreach ($prop in $Rule.when.PSObject.Properties) {
            $actual = if ($null -ne $Entry.PSObject.Properties[$prop.Name]) { [string]$Entry.($prop.Name) } else { '' }
            if ($actual -ne [string]$prop.Value) { return $false }
            $matchedAnything = $true
        }
    }
    if ($null -ne $whenAny) {
        foreach ($prop in $Rule.whenAny.PSObject.Properties) {
            if ($prop.Name -ne 'kindSignals.hints') { throw "Test-RuleMatch only understands kindSignals.hints paths; extend it for '$($prop.Name)'" }
            $present = @($Entry.kindSignals.hints)
            $hit = @($present | Where-Object { $_ -in @($prop.Value) })
            if ($hit.Count -eq 0) { return $false }
            $matchedAnything = $true
        }
    }
    return $matchedAnything
}
foreach ($entry in $entries) {
    $name = [string]$entry.repoName
    $walk = [System.Collections.Generic.List[string]]::new()
    foreach ($rule in @($config.kindDetection.rules)) {
        if ((Test-RuleMatch -Rule $rule -Entry $entry) -and -not $walk.Contains([string]$rule.kind)) { $walk.Add([string]$rule.kind) | Out-Null }
    }
    $engineOrder = @($verdicts[$name].candidates | ForEach-Object { [string]$_.kind })
    if (($walk -join '>') -ne ($engineOrder -join '>')) { $failures.Add("$name candidates ($($engineOrder -join ' > ')) are not the config-order walk ($($walk -join ' > '))") }
    $expectedPick = if ($walk.Count -gt 0) { $walk[0] } else { 'unknown' }
    if ([string]$verdicts[$name].kind -ne $expectedPick) { $failures.Add("$name kind '$($verdicts[$name].kind)' is not the first matching rule in config order ('$expectedPick')") }
}

# Zero kind deltas against the recorded v2 baseline (steering contract 11):
# the current rules replayed over the v2 signals for the nine cohort
# repositories must resolve the kinds v2 recorded. A later model version that
# changes an answer says so with a new baseline, never silently. Locally,
# where the checkouts exist at the recorded commits, the current scanner must
# also reproduce the recorded hints; CI has no checkouts and says so.
$baselinePath = Join-Path $WorkspaceRoot 'evidence\trials\release-3.7\kind-baseline-v2.json'
$baselineSummary = 'baseline replay: not run'
if (-not (Test-Path -LiteralPath $baselinePath)) { $failures.Add("kind baseline not found at $baselinePath") }
else {
    $baseline = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $baselinePath -Raw -Encoding UTF8)
    $cohortPath = Join-Path $WorkspaceRoot 'evidence\trials\release-3.7\cohort.json'
    $cohortPaths = @{}
    if (Test-Path -LiteralPath $cohortPath) {
        foreach ($rec in @((ConvertFrom-Json -InputObject (Get-Content -LiteralPath $cohortPath -Raw -Encoding UTF8)).records)) { $cohortPaths[[string]$rec.repository] = [string]$rec.localPath }
    }
    $replayed = 0; $rescanned = 0; $skipped = 0; $moved = 0
    # The baseline lives in a public repository: hints and a hash, never text.
    foreach ($rec in @($baseline.records)) {
        foreach ($textField in @('readmePurpose', 'evidence', 'entryPoints')) {
            if ($null -ne $rec.kindSignals.PSObject.Properties[$textField]) { $failures.Add("kind baseline record $($rec.repository) carries '$textField' - README or repository text must not be recorded, only hints and readmePurposeSha256") }
        }
    }
    foreach ($rec in @($baseline.records)) {
        $replayEntry = [pscustomobject]@{ repoName = [string]$rec.repository; lifecycleState = [string]$rec.lifecycleState; curationState = [string]$rec.curationState; kindSignals = $rec.kindSignals }
        $v = Resolve-RepositoryKind -Entry $replayEntry -Config $config
        $replayed++
        if ([string]$v.kind -ne [string]$rec.kind) { $failures.Add("kind delta on $($rec.repository): $($baseline.modelVersion) recorded '$($rec.kind)', $expectedModel resolves '$($v.kind)' over the same signals (hints: $(@($rec.kindSignals.hints) -join ', '))") }
        $local = if ($cohortPaths.ContainsKey([string]$rec.repository)) { $cohortPaths[[string]$rec.repository] } else { '' }
        if ([string]::IsNullOrWhiteSpace($local) -or -not (Test-Path -LiteralPath $local -PathType Container)) { $skipped++; continue }
        $head = ((& git -C $local rev-parse HEAD 2>$null) | Out-String).Trim()
        if ($head -ne [string]$rec.checkoutCommit) { $moved++; continue }
        $now = Get-RepoKindSignalProfile -LocalPath $local -Config $signalConfig
        $rescanned++
        $nowPurposeHash = if ([string]::IsNullOrEmpty([string]$now.readmePurpose)) { $null } else { [System.Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::UTF8.GetBytes([string]$now.readmePurpose))).ToLowerInvariant() }
        if ([string]$nowPurposeHash -ne [string]$rec.kindSignals.readmePurposeSha256) { $failures.Add("purpose-line hash delta on $($rec.repository) at $($head.Substring(0, 8)): the README purpose line the scanner reads has changed since the baseline") }
        if ((@($now.hints) -join ',') -ne (@($rec.kindSignals.hints) -join ',')) { $failures.Add("hint delta on $($rec.repository) at $($head.Substring(0, 8)): baseline [$(@($rec.kindSignals.hints) -join ', ')] vs $expectedSignalModel [$(@($now.hints) -join ', ')]") }
    }
    $baselineSummary = 'baseline replay ({0}): {1} records, kinds unchanged; {2} rescanned with equal hints and purpose-line hashes, {3} skipped (no checkout here), {4} skipped (checkout moved past the recorded commit)' -f $baseline.modelVersion, $replayed, $rescanned, $skipped, $moved
}

Write-Host "Kind detection ($expectedModel over $expectedSignalModel):"
foreach ($row in $rows) { Write-Host $row }
if ($failures.Count -eq 0) {
    Write-Host ("  ok: {0} checkouts, {1} kinds reached, ranked candidates + hints + observations on every record, opinions in config with observedOn, pick = first rule in config order" -f $entries.Count, (@($payload.items | ForEach-Object { $_.kind } | Select-Object -Unique)).Count) -ForegroundColor Green
    Write-Host "  $baselineSummary" -ForegroundColor Green
    exit 0
}
Write-Host "  $baselineSummary"
foreach ($f in $failures) { Write-Host "  FAIL: $f" -ForegroundColor Red }
if ($FailOnError) { exit 1 }
exit 0
