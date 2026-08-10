<#
.SYNOPSIS
    PowerShell lint gate — PSScriptAnalyzer with a per-rule ratchet baseline.

.DESCRIPTION
    Runs PSScriptAnalyzer over the repository's PowerShell sources using
    PSScriptAnalyzerSettings.psd1 (policy exclusions) and compares per-rule
    finding counts against scripts/pssa-baseline.json (debt baseline).

    Fails when:
      - any Error-severity finding exists (the baseline holds zero; none may
        return), or
      - any rule's count EXCEEDS its baseline (new debt), or
      - a rule absent from the baseline appears (new debt category).

    Counts below baseline pass with a note — run -UpdateBaseline after real
    cleanup to lock the improvement in. The ratchet only tightens; loosening
    it is a reviewed edit to a committed JSON file, never something this
    script does on its own.

    First run on a machine without PSScriptAnalyzer installs it CurrentUser
    from PSGallery (the CI runner path; mirrors copilot-setup-steps.yml).

.PARAMETER UpdateBaseline
    Rewrite scripts/pssa-baseline.json from the current findings instead of
    gating. Use after intentional cleanup, and commit the shrunken file.
#>
[CmdletBinding()]
param(
    [string]$WorkspaceRoot = (Split-Path -Parent $PSScriptRoot),
    [switch]$UpdateBaseline
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$WorkspaceRoot = (Resolve-Path -LiteralPath $WorkspaceRoot).Path
$settingsPath = Join-Path $WorkspaceRoot 'PSScriptAnalyzerSettings.psd1'
$baselinePath = Join-Path $WorkspaceRoot 'scripts\pssa-baseline.json'

if (-not (Test-Path -LiteralPath $settingsPath)) { throw "PSScriptAnalyzerSettings.psd1 not found at $settingsPath" }

if (-not (Get-Module -ListAvailable PSScriptAnalyzer)) {
    Write-Host '[STEP] Installing PSScriptAnalyzer (CurrentUser, PSGallery)' -ForegroundColor Cyan
    Install-Module PSScriptAnalyzer -Scope CurrentUser -Force
}
Import-Module PSScriptAnalyzer

Write-Host "[STEP] PSScriptAnalyzer sweep (settings: PSScriptAnalyzerSettings.psd1)" -ForegroundColor Cyan
$findings = @(Invoke-ScriptAnalyzer -Path $WorkspaceRoot -Recurse -Settings $settingsPath |
    Where-Object { $_.ScriptPath -notmatch '\\node_modules\\|\\dist\\|\\output\\|\\evidence\\' })
Write-Host ("  {0} finding(s) after path filters" -f @($findings).Count) -ForegroundColor DarkGray

$currentCounts = @{}
foreach ($group in ($findings | Group-Object RuleName)) { $currentCounts[$group.Name] = $group.Count }

if ($UpdateBaseline) {
    $ordered = [ordered]@{}
    foreach ($key in ($currentCounts.Keys | Sort-Object)) { $ordered[$key] = $currentCounts[$key] }
    ($ordered | ConvertTo-Json) | Set-Content -LiteralPath $baselinePath -Encoding UTF8
    Write-Host ("[PASS] Baseline rewritten: {0} rule(s), {1} finding(s) total" -f $ordered.Count, @($findings).Count) -ForegroundColor Green
    exit 0
}

if (-not (Test-Path -LiteralPath $baselinePath)) { throw "Ratchet baseline not found at $baselinePath — run with -UpdateBaseline once to create it." }
$baselineRaw = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $baselinePath -Raw -Encoding UTF8)
$baseline = @{}
foreach ($property in $baselineRaw.PSObject.Properties) { $baseline[$property.Name] = [int]$property.Value }

$failures = [System.Collections.Generic.List[string]]::new()

# 1. Error severity is a hard zero — the one existing Error was fixed at
#    adoption and none may return.
$errorFindings = @($findings | Where-Object Severity -eq 'Error')
foreach ($errorFinding in $errorFindings) {
    $failures.Add(("ERROR severity: {0} at {1}:{2} — {3}" -f $errorFinding.RuleName, $errorFinding.ScriptPath, $errorFinding.Line, $errorFinding.Message))
}

# 2. No rule may exceed its baseline, and no new rule may appear.
foreach ($ruleName in ($currentCounts.Keys | Sort-Object)) {
    $allowed = if ($baseline.ContainsKey($ruleName)) { $baseline[$ruleName] } else { 0 }
    if ($currentCounts[$ruleName] -gt $allowed) {
        $delta = $currentCounts[$ruleName] - $allowed
        $offenders = @($findings | Where-Object RuleName -eq $ruleName | Select-Object -First 5 | ForEach-Object {
            ("    {0}:{1}" -f ($_.ScriptPath -replace [regex]::Escape($WorkspaceRoot + '\'), ''), $_.Line) })
        $failures.Add(("{0}: {1} finding(s), baseline allows {2} (+{3} new debt). First sites:`n{4}" -f $ruleName, $currentCounts[$ruleName], $allowed, $delta, ($offenders -join "`n")))
    }
}

$improved = @($baseline.Keys | Where-Object { $currentCounts[$_] -lt $baseline[$_] -or -not $currentCounts.ContainsKey($_) })
if (@($improved).Count -gt 0) {
    Write-Host ("  {0} rule(s) below baseline — run -UpdateBaseline to lock the improvement in: {1}" -f @($improved).Count, ($improved -join ', ')) -ForegroundColor Yellow
}

if ($failures.Count -gt 0) {
    Write-Host ''
    foreach ($failure in $failures) { Write-Host "[FAIL] $failure" -ForegroundColor Red }
    Write-Host ("`nLINT GATE FAILED — {0} problem(s). Fix the new findings; the baseline only moves down." -f $failures.Count) -ForegroundColor Red
    exit 1
}

Write-Host ("[PASS] PowerShell lint — 0 Error-severity findings; no rule above its ratchet baseline ({0} total, baseline {1})" -f @($findings).Count, (($baseline.Values | Measure-Object -Sum).Sum)) -ForegroundColor Green
exit 0
