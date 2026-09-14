#Requires -Version 7.0
<#
.SYNOPSIS
    A built or verified milestone's check is a step CI runs (validator R024).

.DESCRIPTION
    Ben, 2026-09-14, after 3.7 M4b was called built on `-Assert applicability`
    and the suite never ran it. The rule lives in
    tools/Test-RoadmapStructure.rules.ps1 and runs inside the roadmap validator;
    this check proves it over fixture repositories, each with its own suite:

      - a check the suite runs with every one of its arguments passes;
      - a gate with a different argument value, or without one of the check's
        arguments (-FailOnError included), fails and names what is missing;
      - a script CI never runs fails, and so does a gate that is commented out;
      - a planned milestone is exempt; a verified one is held to it;
      - a vitest check resolves through the npm gate that runs vitest, and a
        script an npm gate runs counts as a step;
      - a workflow `run:` line is a step;
      - a check whose script cannot be told fails;
      - a repository with no suite yields nothing.

    Then the live ROADMAP.md against the live suite: every built or verified
    check runs in CI, and there is at least one to hold (not vacuous).

.EXAMPLE
    pwsh ./tests/Test-RoadmapCheckRunsInCi.ps1 -FailOnError
#>
[CmdletBinding()]
param(
    [Parameter()][string]$WorkspaceRoot = (Split-Path -Parent $PSScriptRoot),
    [Parameter()][switch]$FailOnError
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $WorkspaceRoot 'tools\Test-RoadmapStructure.rules.ps1')
$failures = [System.Collections.Generic.List[string]]::new()
$fixtureRoots = [System.Collections.Generic.List[string]]::new()
$caseNames = [System.Collections.Generic.List[string]]::new()

function Build-FixtureRepository {
    param(
        [AllowEmptyCollection()][string[]]$SuiteLines = @(),
        [hashtable]$RootScripts = @{},
        [hashtable]$FrontendScripts = @{},
        [AllowEmptyCollection()][string[]]$WorkflowLines = @(),
        [switch]$NoSuite
    )
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ('r024-fixture-' + [guid]::NewGuid().ToString('n'))
    $null = New-Item -ItemType Directory -Path (Join-Path $root 'scripts') -Force
    $fixtureRoots.Add($root) | Out-Null
    if (-not $NoSuite) { Set-Content -LiteralPath (Join-Path $root 'scripts\Invoke-TestSuite.ps1') -Value $SuiteLines -Encoding UTF8 }
    if ($RootScripts.Count -gt 0) { Set-Content -LiteralPath (Join-Path $root 'package.json') -Value (@{ scripts = $RootScripts } | ConvertTo-Json) -Encoding UTF8 }
    if ($FrontendScripts.Count -gt 0) {
        $null = New-Item -ItemType Directory -Path (Join-Path $root 'frontend') -Force
        Set-Content -LiteralPath (Join-Path $root 'frontend\package.json') -Value (@{ scripts = $FrontendScripts } | ConvertTo-Json) -Encoding UTF8
    }
    if ($WorkflowLines.Count -gt 0) {
        $null = New-Item -ItemType Directory -Path (Join-Path $root '.github\workflows') -Force
        Set-Content -LiteralPath (Join-Path $root '.github\workflows\ci.yml') -Value $WorkflowLines -Encoding UTF8
    }
    return $root
}

function Get-FixtureRoadmap {
    param([string]$State, [string]$Check)
    return @(
        '## Current focus',
        '',
        "- [ ] **Fixture milestone.** Does one thing. _(state: $State)_",
        ('      `check: ' + $Check + '`'),
        ''
    )
}

function Assert-Case {
    param([string]$Name, [string]$Root, [string]$State, [string]$Check, [int]$Expect, [string]$MessageMatch = '')
    $caseNames.Add($Name) | Out-Null
    $found = @(Test-R024CheckRunsInCi -Lines (Get-FixtureRoadmap -State $State -Check $Check) -RepoRoot $Root)
    if ($found.Count -ne $Expect) {
        $failures.Add("${Name}: expected $Expect finding(s), got $($found.Count)$(if ($found.Count) { ' - ' + $found[0].Message })")
        return
    }
    if ($Expect -gt 0 -and $MessageMatch -and [string]$found[0].Message -notmatch $MessageMatch) {
        $failures.Add("${Name}: the finding does not name what is missing (expected /$MessageMatch/): $($found[0].Message)")
    }
    if ($Expect -gt 0 -and ([string]$found[0].Rule -ne 'R024-CHECK-RUNS-IN-CI' -or [string]$found[0].Severity -ne 'error')) {
        $failures.Add("${Name}: the finding must be R024-CHECK-RUNS-IN-CI at severity error")
    }
}

try {
    $gate = "Invoke-ScriptGate -Name 'Alpha' -ScriptPath (Join-Path `$WorkspaceRoot 'tests\Test-Alpha.ps1') -ScriptArgs @('-Cohort', 'evidence/trials/x/cohort.json', '-Assert', 'alpha', '-FailOnError')"
    $suite = Build-FixtureRepository -SuiteLines @($gate)
    $alpha = 'pwsh ./tests/Test-Alpha.ps1 -Cohort evidence/trials/x/cohort.json -Assert alpha -FailOnError'
    Assert-Case -Name 'runs with every argument' -Root $suite -State 'built' -Check $alpha -Expect 0
    Assert-Case -Name 'another assertion of the same script' -Root $suite -State 'built' -Check ($alpha -replace 'alpha -Fail', 'beta -Fail') -Expect 1 -MessageMatch 'never with beta'
    Assert-Case -Name 'never runs' -Root $suite -State 'built' -Check 'pwsh ./tests/Test-Omega.ps1 -FailOnError' -Expect 1 -MessageMatch 'never runs Test-Omega\.ps1'
    Assert-Case -Name 'planned is exempt' -Root $suite -State 'planned' -Check 'pwsh ./tests/Test-Omega.ps1 -FailOnError' -Expect 0
    Assert-Case -Name 'verified is held to it' -Root $suite -State 'verified' -Check 'pwsh ./tests/Test-Omega.ps1 -FailOnError' -Expect 1

    $noFail = Build-FixtureRepository -SuiteLines @($gate -replace ", '-FailOnError'", '')
    Assert-Case -Name 'gate without -FailOnError' -Root $noFail -State 'built' -Check $alpha -Expect 1 -MessageMatch 'never with -FailOnError'

    $commented = Build-FixtureRepository -SuiteLines @("# $gate")
    Assert-Case -Name 'commented-out gate' -Root $commented -State 'built' -Check $alpha -Expect 1 -MessageMatch 'never runs Test-Alpha\.ps1'

    $npm = Build-FixtureRepository -SuiteLines @(
        "Invoke-NpmGate -Name 'Frontend unit tests' -ScriptName 'test:unit'",
        "Invoke-NpmGate -Name 'UI debt ratchet'     -ScriptName 'ui:ratchet'"
    ) -RootScripts @{ 'test:unit' = 'npm run test:unit --workspace frontend'; 'ui:ratchet' = 'node tools/Measure-Fixture.mjs' } -FrontendScripts @{ 'test:unit' = 'vitest run' }
    Assert-Case -Name 'vitest through the npm gate' -Root $npm -State 'built' -Check 'npx vitest run frontend/lib/thing.test.ts' -Expect 0
    Assert-Case -Name 'script an npm gate runs' -Root $npm -State 'built' -Check 'node tools/Measure-Fixture.mjs' -Expect 0
    Assert-Case -Name 'npm script CI runs' -Root $npm -State 'built' -Check 'npm run ui:ratchet' -Expect 0
    Assert-Case -Name 'npm script CI does not run' -Root $npm -State 'built' -Check 'npm run e2e' -Expect 1 -MessageMatch "no npm script 'e2e'"
    $noVitest = Build-FixtureRepository -SuiteLines @("Invoke-NpmGate -Name 'UI debt ratchet' -ScriptName 'ui:ratchet'") -RootScripts @{ 'ui:ratchet' = 'node tools/Measure-Fixture.mjs' }
    Assert-Case -Name 'vitest with no vitest gate' -Root $noVitest -State 'built' -Check 'npx vitest run frontend' -Expect 1 -MessageMatch 'no vitest'

    $workflow = Build-FixtureRepository -SuiteLines @("Write-Host 'suite'") -WorkflowLines @('jobs:', '  test:', '    steps:', '      - run: pwsh ./tests/Test-Workflow.ps1 -FailOnError')
    Assert-Case -Name 'workflow run line' -Root $workflow -State 'built' -Check 'pwsh ./tests/Test-Workflow.ps1 -FailOnError' -Expect 0

    Assert-Case -Name 'untellable command' -Root $suite -State 'built' -Check 'make verify' -Expect 1 -MessageMatch 'cannot tell which script'

    $bare = Build-FixtureRepository -NoSuite
    Assert-Case -Name 'no suite' -Root $bare -State 'built' -Check 'make verify' -Expect 0
}
finally {
    foreach ($r in $fixtureRoots) { Remove-Item -LiteralPath $r -Recurse -Force -ErrorAction SilentlyContinue }
}

# --- The live roadmap against the live suite ------------------------------
$liveLines = [System.IO.File]::ReadAllLines((Join-Path $WorkspaceRoot 'ROADMAP.md'))
$held = 0
for ($i = 0; $i -lt $liveLines.Count; $i++) {
    if ($liveLines[$i] -notmatch '^\s*-\s\[( |x)\]') { continue }
    $end = $i
    while ($end + 1 -lt $liveLines.Count -and $liveLines[$end + 1] -match '^\s{2,}\S') { $end++ }
    $block = $liveLines[$i..$end] -join "`n"
    if ($block -match '\(state:\s*(built|verified)\b') { $held += [regex]::Matches($block, '`check:\s*[^`]+`').Count }
}
if ($held -eq 0) { $failures.Add('the live ROADMAP.md holds no built or verified check; the rule has nothing to hold') }
foreach ($f in @(Test-R024CheckRunsInCi -Lines $liveLines -RepoRoot $WorkspaceRoot)) {
    $failures.Add("ROADMAP.md line $($f.Line): $($f.Message)")
}

Write-Host 'A built or verified check is a step CI runs (validator R024):'
if ($failures.Count -gt 0) {
    foreach ($f in $failures) { Write-Host "  FAIL $f" }
    if ($FailOnError) { exit 1 }
}
else {
    Write-Host ("  ok: {0} fixture cases hold; the live ROADMAP.md's {1} built or verified check(s) all run in CI" -f $caseNames.Count, $held)
}
