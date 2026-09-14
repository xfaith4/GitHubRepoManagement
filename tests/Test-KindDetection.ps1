#Requires -Version 7.0
<#
.SYNOPSIS
    Release 3.7 M4a check: repository kind resolves from manifests, entry points and the README purpose line.

.DESCRIPTION
    Builds one throwaway checkout per kind under output/kind-detection/, runs
    the scan-time signal scanner (Portfolio.KindSignals.ps1) and the config's
    kindDetection rules (Portfolio.Conclusion.ps1 + foundation-domains.json)
    over each, and asserts:

      - library, firmware, application, experiment and tooling each resolve
        from their own signals, not only `archived`;
      - every hint carries an evidence line a person can read;
      - the v1 field-equality rules still resolve `archived`;
      - a github-only entry (no checkout) stays `unknown`;
      - every conclusion record and the portfolio payload carry
        modelVersion = foundation-conclusions v2 beside the index identity.

    Exit 0 when every assertion holds. With -FailOnError, exit 1 on the first
    failing set; without it, the failures print and the exit code stays 0.

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
        kindSignals = (Get-RepoKindSignalProfile -LocalPath $LocalPath)
    }
    foreach ($k in $Overrides.Keys) { $entry[$k] = $Overrides[$k] }
    return [pscustomobject]$entry
}

$checkouts = [ordered]@{
    'ps-library'   = @{ 'README.md' = "# Contract Client`n`nA **contract-enforced, deterministic pagination** wrapper for a cloud API.`n"; 'src/ContractClient.psd1' = "@{`n    RootModule = 'ContractClient.psm1'`n    ModuleVersion = '1.0.0'`n}`n"; 'src/ContractClient.psm1' = "function Get-Thing { 1 }`n" }
    'led-firmware' = @{ 'README.md' = "# LED`n`nThis repository is organized around one job: generate board-specific sketches and serve them.`n"; 'package.json' = '{ "name": "led-web", "private": true, "dependencies": { "express": "^4", "react": "^18" } }'; 'sketches/strip/strip.ino' = "void setup() {}`nvoid loop() {}`n" }
    'family-app'   = @{ 'README.md' = "# Family Archive`n`n**A private, invite-only family history archive - searchable profiles, served as a fast static web app.** _(GitHub repo)_`n"; 'index.html' = '<!doctype html><title>x</title>'; 'package.json' = '{ "name": "family-archive", "private": true, "dependencies": { "firebase": "^10" } }' }
    'proto'        = @{ 'README.md' = "# Orchestration`n`n![badge](https://x/y.svg)`n`nA phase-0 prototype of a multi-agent runner; nothing here is a contract yet.`n"; 'package.json' = '{ "name": "proto", "private": true, "dependencies": { "express": "^4" } }' }
    'port-console' = @{ 'README.md' = "# DevPortConsole`n`nA self-contained PowerShell + WPF desktop utility for maintaining a local index of ports.`n"; 'DevPortConsole.ps1' = "'hi'`n"; 'DevPortConsole.Tests.ps1' = "Describe 'x' {}`n"; 'PSScriptAnalyzerSettings.psd1' = "@{ Severity = @('Error') }`n" }
    'node-lib'     = @{ 'README.md' = "# tiny-dates`n`n> Zero-dependency helpers for calendar math.`n"; 'package.json' = '{ "name": "tiny-dates", "version": "1.2.0", "main": "index.js", "exports": "./index.js" }'; 'index.js' = 'module.exports = {};' }
    'closed'       = @{ 'README.md' = "# Old Toolbox`n`nA toolbox of scripts, no longer maintained.`n"; 'BensToolbox.ps1' = "'x'`n" }
}
$paths = [ordered]@{}
foreach ($name in $checkouts.Keys) { $paths[$name] = Add-FixtureCheckout -Name $name -Files $checkouts[$name] }

$entries = @(
    (ConvertTo-IndexEntry -Name 'ps-library'   -LocalPath $paths['ps-library']   -Overrides @{ repoType = 'powershell' }),
    (ConvertTo-IndexEntry -Name 'led-firmware' -LocalPath $paths['led-firmware'] -Overrides @{ repoType = 'node' }),
    (ConvertTo-IndexEntry -Name 'family-app'   -LocalPath $paths['family-app']   -Overrides @{ repoType = 'node' }),
    (ConvertTo-IndexEntry -Name 'proto'        -LocalPath $paths['proto']        -Overrides @{ repoType = 'node' }),
    (ConvertTo-IndexEntry -Name 'port-console' -LocalPath $paths['port-console'] -Overrides @{ repoType = 'powershell' }),
    (ConvertTo-IndexEntry -Name 'node-lib'     -LocalPath $paths['node-lib']     -Overrides @{ repoType = 'node' }),
    (ConvertTo-IndexEntry -Name 'closed'       -LocalPath $paths['closed']       -Overrides @{ repoType = 'powershell'; lifecycleState = 'archived' }),
    (ConvertTo-IndexEntry -Name 'github-only'  -LocalPath ''                     -Overrides @{ sourceCoverage = 'github'; hasReadme = $false; readmeScore = 0 })
)

$expected = [ordered]@{
    'ps-library' = 'library'; 'led-firmware' = 'firmware'; 'family-app' = 'application'; 'proto' = 'experiment'
    'port-console' = 'tooling'; 'node-lib' = 'library'; 'closed' = 'archived'; 'github-only' = 'unknown'
}
$expectedHint = [ordered]@{
    'ps-library' = 'module-manifest'; 'led-firmware' = 'firmware-target'; 'family-app' = 'web-app'; 'proto' = 'experiment-wording'
    'port-console' = 'script-entry'; 'node-lib' = 'library-manifest'
}

$failures = [System.Collections.Generic.List[string]]::new()
$rows = [System.Collections.Generic.List[string]]::new()
foreach ($entry in $entries) {
    $name = [string]$entry.repoName
    $verdict = Resolve-RepositoryKind -Entry $entry -Config $config
    $hints = @($entry.kindSignals.hints)
    $rows.Add(('  {0,-13} -> {1,-12} [{2}] hints: {3}' -f $name, $verdict.kind, $verdict.basis, ($hints -join ', ')))
    if ([string]$verdict.kind -ne $expected[$name]) { $failures.Add("$name resolved '$($verdict.kind)', expected '$($expected[$name])' (hints: $($hints -join ', '))") }
    if ($expectedHint.Contains($name) -and $expectedHint[$name] -notin $hints) { $failures.Add("$name is missing the hint '$($expectedHint[$name])' (hints: $($hints -join ', '))") }
    if ($hints.Count -ne @($entry.kindSignals.evidence).Count) { $failures.Add("$name has $($hints.Count) hints but $(@($entry.kindSignals.evidence).Count) evidence lines") }
    if ($name -ne 'github-only' -and [string]::IsNullOrWhiteSpace([string]$entry.kindSignals.readmePurpose)) { $failures.Add("$name has no README purpose line") }
}

# The kinds the milestone names must each be reached by a rule, and the
# record must say which model drew the conclusion.
$kindIds = @($config.kinds | ForEach-Object { [string]$_.id })
foreach ($required in @('library', 'firmware', 'application', 'experiment', 'tooling')) {
    if ($required -notin $kindIds) { $failures.Add("foundation-domains.json does not define the kind '$required'") }
    if (@($config.kindDetection.rules | Where-Object { [string]$_.kind -eq $required }).Count -eq 0) { $failures.Add("no kindDetection rule resolves '$required'") }
}
if ([string]$config.modelVersion -ne 'foundation-conclusions v2') { $failures.Add("foundation-domains.json modelVersion is '$($config.modelVersion)', expected 'foundation-conclusions v2'") }
$payload = Get-PortfolioConclusionsPayload -Entries $entries -Config $config
if ([string]$payload.modelVersion -ne 'foundation-conclusions v2') { $failures.Add("conclusions payload modelVersion is '$($payload.modelVersion)'") }
foreach ($item in @($payload.items)) {
    if ([string]$item.modelVersion -ne 'foundation-conclusions v2') { $failures.Add("conclusion record for $($item.repoName) carries modelVersion '$($item.modelVersion)'") }
}
if (-not $payload.contract.holds) { $failures.Add("conclusion contract violated: $($payload.contract.violations -join '; ')") }
$unknownCount = @($payload.items | Where-Object { [string]$_.kind -eq 'unknown' }).Count
if ($unknownCount -ne 1) { $failures.Add("$unknownCount conclusions are 'unknown'; only the github-only entry should be") }

Write-Host 'Kind detection (foundation-conclusions v2):'
foreach ($row in $rows) { Write-Host $row }
if ($failures.Count -eq 0) {
    Write-Host ("  ok: {0} checkouts, {1} kinds reached, modelVersion on every record" -f $entries.Count, (@($payload.items | ForEach-Object { $_.kind } | Select-Object -Unique)).Count) -ForegroundColor Green
    exit 0
}
foreach ($f in $failures) { Write-Host "  FAIL: $f" -ForegroundColor Red }
if ($FailOnError) { exit 1 }
exit 0
