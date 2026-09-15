#Requires -Version 7.0
<#
.SYNOPSIS
    The merge tripwire holds what only the owner may approve and fails what no
    approval clears (D-023).

.DESCRIPTION
    Ben, 2026-09-15: the review-by-file-class rule of D-019 is replaced by a
    gate, so the gate is proved here over fixture repositories, each a real git
    repository with a main branch and a case branch:

      - an ordinary source change passes;
      - a gate removed from the suite, -FailOnError dropped from a gate, a
        check file deleted, a protected path touched, a workflow edited, or
        the contracts section of steering.md changed is HELD and names it;
      - a change elsewhere in steering.md passes; a renamed check file passes;
      - the operator-approved label on the pull request turns HELD into PASS;
      - a secret on an added line FAILS even with the label; a placeholder
        value is not a secret;
      - the permission envelope floor loosened FAILS;
      - a versioned config changed without a modelVersion bump FAILS, and
        passes with one;
      - the eslint cap raised, a PSScriptAnalyzer baseline count raised or a
        rule added to it, or a UI ratchet count raised FAILS; a cap lowered
        passes;
      - head equal to base passes with nothing to evaluate.

    Then the live repository: the tripwire runs, and its outcome is PASS or
    HELD - never FAIL - so a hard finding on the branch fails this proof too.

.EXAMPLE
    pwsh ./tests/Test-MergeTripwire.ps1 -FailOnError
#>
[CmdletBinding()]
param(
    [Parameter()][string]$WorkspaceRoot = (Split-Path -Parent $PSScriptRoot),
    [Parameter()][switch]$FailOnError
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$toolPath = Join-Path $WorkspaceRoot 'tools\Test-MergeTripwire.ps1'
if (-not (Test-Path -LiteralPath $toolPath)) { throw "Tripwire not found at $toolPath" }

$failures = [System.Collections.Generic.List[string]]::new()
$fixtureRoots = [System.Collections.Generic.List[string]]::new()
$caseCount = 0

function Write-FixtureFile {
    param([string]$Root, [string]$Path, [string]$Content)
    $full = Join-Path $Root ($Path -replace '/', '\')
    $parent = Split-Path -Parent $full
    if (-not (Test-Path -LiteralPath $parent)) { $null = New-Item -ItemType Directory -Path $parent -Force }
    [System.IO.File]::WriteAllText($full, $Content, [System.Text.UTF8Encoding]::new($false))
}

function Invoke-FixtureGit {
    param([string]$Root, [string[]]$Argument)
    $out = (& git -C $Root -c user.name=fixture -c user.email=fixture@example.invalid -c commit.gpgsign=false @Argument 2>&1) | Out-String
    if ($LASTEXITCODE -ne 0) { throw ("git {0} failed in {1}: {2}" -f ($Argument -join ' '), $Root, $out.Trim()) }
    return $out.Trim()
}

function Build-FixtureRepository {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ('tripwire-fixture-' + [guid]::NewGuid().ToString('n'))
    $null = New-Item -ItemType Directory -Path $root -Force
    $fixtureRoots.Add($root) | Out-Null
    $hooks = Join-Path $root '.nohooks'
    $null = New-Item -ItemType Directory -Path $hooks -Force

    Write-FixtureFile -Root $root -Path 'scripts/Invoke-TestSuite.ps1' -Content (@(
        "Invoke-ScriptGate -Name 'Kind detection' -ScriptPath 'tests\Test-Something.ps1' -ScriptArgs @('-FailOnError')",
        "Invoke-ScriptGate -Name 'Roadmap structure lint' -ScriptPath 'tools\Test-Roadmap.ps1' -ScriptArgs @('-Path', 'ROADMAP.md', '-FailOnError')",
        "Invoke-NpmGate -Name 'Frontend lint' -ScriptName 'lint'",
        ''
    ) -join "`n")
    Write-FixtureFile -Root $root -Path 'tests/Test-Something.ps1' -Content "exit 0`n"
    Write-FixtureFile -Root $root -Path 'tools/Test-MergeTripwire.ps1' -Content "# stand-in for the tripwire`n"
    Write-FixtureFile -Root $root -Path 'src/app.ps1' -Content "Write-Output 'hello'`n"
    Write-FixtureFile -Root $root -Path 'backend/config/agent-providers.json' -Content (@{
            defaultScope       = @{ allowedPaths = @('**'); forbiddenPaths = @('.github/workflows/**') }
            defaultPermissions = @{ filesystemWrite = $true; shell = $true; network = $false; githubWrite = $false }
        } | ConvertTo-Json -Depth 5)
    Write-FixtureFile -Root $root -Path 'backend/config/kind-signals.json' -Content (@{ modelVersion = '2.0'; rules = @(@{ kind = 'library'; hint = 'psd1' }) } | ConvertTo-Json -Depth 5)
    Write-FixtureFile -Root $root -Path 'frontend/package.json' -Content (@{ scripts = @{ lint = 'eslint . --max-warnings 10' } } | ConvertTo-Json -Depth 5)
    Write-FixtureFile -Root $root -Path 'scripts/pssa-baseline.json' -Content (@{ PSUseSingularNouns = 3 } | ConvertTo-Json)
    Write-FixtureFile -Root $root -Path 'tools/ui-ratchet-baseline.json' -Content (@{ counts = @{ outlineNone = 4 }; byFile = @{} } | ConvertTo-Json -Depth 5)
    Write-FixtureFile -Root $root -Path 'docs/governance/steering.md' -Content (@(
        '# Steering', '',
        '## 2. The contracts', '',
        '1. Every figure is an object, never a bare number.', '',
        '## 5. Working rules', '',
        '- Next action is the first item in Current focus.', ''
    ) -join "`n")
    Write-FixtureFile -Root $root -Path 'docs/governance/merge-policy.md' -Content "# Merge policy`n"
    Write-FixtureFile -Root $root -Path '.github/workflows/ci.yml' -Content "name: CI`n"

    $null = Invoke-FixtureGit -Root $root -Argument @('init', '-q', '-b', 'main')
    $null = Invoke-FixtureGit -Root $root -Argument @('config', 'core.autocrlf', 'false')
    $null = Invoke-FixtureGit -Root $root -Argument @('config', 'core.hooksPath', $hooks)
    $null = Invoke-FixtureGit -Root $root -Argument @('add', '-A')
    $null = Invoke-FixtureGit -Root $root -Argument @('commit', '-q', '-m', 'base')
    return $root
}

function Invoke-Case {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][scriptblock]$Mutate,
        [Parameter(Mandatory = $true)][ValidateSet('PASS', 'HELD', 'FAIL')][string]$Expect,
        [Parameter()][string[]]$Mentions = @(),
        [Parameter()][string[]]$Labels = @(),
        [Parameter()][string]$BaseRef = 'auto',
        [Parameter()][switch]$NoCommit
    )
    $script:caseCount++
    $branch = 'case-{0}' -f $script:caseCount
    $mainSha = Invoke-FixtureGit -Root $Root -Argument @('rev-parse', 'main')
    $null = Invoke-FixtureGit -Root $Root -Argument @('checkout', '-q', '-b', $branch, 'main')
    try {
        & $Mutate $Root
        if (-not $NoCommit) {
            $null = Invoke-FixtureGit -Root $Root -Argument @('add', '-A')
            $null = Invoke-FixtureGit -Root $Root -Argument @('commit', '-q', '--allow-empty', '-m', $Name)
        }
        $eventPath = Join-Path $Root ('event-{0}.json' -f $script:caseCount)
        $payload = @{ pull_request = @{ base = @{ sha = $mainSha }; labels = @($Labels | ForEach-Object { @{ name = $_ } }) } }
        [System.IO.File]::WriteAllText($eventPath, ($payload | ConvertTo-Json -Depth 6), [System.Text.UTF8Encoding]::new($false))

        $output = (& pwsh -NoProfile -ExecutionPolicy Bypass -File $toolPath -WorkspaceRoot $Root -BaseRef $BaseRef -EventPath $eventPath -FailOnError 2>&1) | Out-String
        $code = $LASTEXITCODE
        $outcome = 'NONE'
        if ($output -match 'Merge tripwire: (PASS|HELD|FAIL)') { $outcome = $Matches[1] }

        $problems = [System.Collections.Generic.List[string]]::new()
        if ($outcome -ne $Expect) { $problems.Add(('expected {0}, got {1}' -f $Expect, $outcome)) }
        $expectedCode = if ($Expect -eq 'PASS') { 0 } else { 1 }
        if ($code -ne $expectedCode) { $problems.Add(('expected exit {0}, got {1}' -f $expectedCode, $code)) }
        foreach ($mention in $Mentions) {
            if ($output -notlike ('*' + $mention + '*')) { $problems.Add(('output does not mention "{0}"' -f $mention)) }
        }
        if ($problems.Count -gt 0) {
            $failures.Add(('{0}: {1}' -f $Name, ($problems -join '; ')))
            Write-Host ("  [FAIL] {0}" -f $Name) -ForegroundColor Red
            Write-Host ($output -replace '(?m)^', '         ')
        }
        else { Write-Host ("  [ok]   {0} -> {1}" -f $Name, $outcome) -ForegroundColor Green }
    }
    finally {
        $null = Invoke-FixtureGit -Root $Root -Argument @('checkout', '-q', '-f', 'main')
        Get-ChildItem -LiteralPath $Root -Filter 'event-*.json' -File | Remove-Item -Force -ErrorAction Ignore
    }
}

try {
    Write-Host '== Merge tripwire cases ==' -ForegroundColor Cyan
    $root = Build-FixtureRepository
    # Every secret-shaped fixture is assembled from fragments, so this file's
    # own source never matches the shapes it proves the tripwire catches; the
    # live-tree run below scans this file too, and CI saw it do so.
    $fakeToken = 'ghp_' + ('A' * 36)

    Invoke-Case -Name 'ordinary source change passes' -Root $root -Expect PASS -Mutate {
        param($r) Write-FixtureFile -Root $r -Path 'src/app.ps1' -Content "Write-Output 'changed'`n" }

    Invoke-Case -Name 'head equal to base passes with nothing to evaluate' -Root $root -Expect PASS -NoCommit -Mentions 'nothing to evaluate' -Mutate { param($r) $null = $r }

    Invoke-Case -Name 'gate removed from the suite is held' -Root $root -Expect HELD -Mentions 'gate removed from the suite: Kind detection' -Mutate {
        param($r) Write-FixtureFile -Root $r -Path 'scripts/Invoke-TestSuite.ps1' -Content (@(
            "Invoke-ScriptGate -Name 'Roadmap structure lint' -ScriptPath 'tools\Test-Roadmap.ps1' -ScriptArgs @('-Path', 'ROADMAP.md', '-FailOnError')",
            "Invoke-NpmGate -Name 'Frontend lint' -ScriptName 'lint'", '') -join "`n") }

    Invoke-Case -Name 'gate commented out is held as removed' -Root $root -Expect HELD -Mentions 'gate removed from the suite: Frontend lint' -Mutate {
        param($r) Write-FixtureFile -Root $r -Path 'scripts/Invoke-TestSuite.ps1' -Content (@(
            "Invoke-ScriptGate -Name 'Kind detection' -ScriptPath 'tests\Test-Something.ps1' -ScriptArgs @('-FailOnError')",
            "Invoke-ScriptGate -Name 'Roadmap structure lint' -ScriptPath 'tools\Test-Roadmap.ps1' -ScriptArgs @('-Path', 'ROADMAP.md', '-FailOnError')",
            "# Invoke-NpmGate -Name 'Frontend lint' -ScriptName 'lint'", '') -join "`n") }

    Invoke-Case -Name '-FailOnError dropped from a gate is held' -Root $root -Expect HELD -Mentions '-FailOnError dropped from gate: Roadmap structure lint' -Mutate {
        param($r) Write-FixtureFile -Root $r -Path 'scripts/Invoke-TestSuite.ps1' -Content (@(
            "Invoke-ScriptGate -Name 'Kind detection' -ScriptPath 'tests\Test-Something.ps1' -ScriptArgs @('-FailOnError')",
            "Invoke-ScriptGate -Name 'Roadmap structure lint' -ScriptPath 'tools\Test-Roadmap.ps1' -ScriptArgs @('-Path', 'ROADMAP.md')",
            "Invoke-NpmGate -Name 'Frontend lint' -ScriptName 'lint'", '') -join "`n") }

    Invoke-Case -Name 'a new gate added passes' -Root $root -Expect PASS -Mutate {
        param($r) Write-FixtureFile -Root $r -Path 'scripts/Invoke-TestSuite.ps1' -Content (@(
            "Invoke-ScriptGate -Name 'Kind detection' -ScriptPath 'tests\Test-Something.ps1' -ScriptArgs @('-FailOnError')",
            "Invoke-ScriptGate -Name 'Roadmap structure lint' -ScriptPath 'tools\Test-Roadmap.ps1' -ScriptArgs @('-Path', 'ROADMAP.md', '-FailOnError')",
            "Invoke-NpmGate -Name 'Frontend lint' -ScriptName 'lint'",
            "Invoke-ScriptGate -Name 'New proof' -ScriptPath 'tests\Test-New.ps1' -ScriptArgs @('-FailOnError')", '') -join "`n") }

    Invoke-Case -Name 'check file deleted is held' -Root $root -Expect HELD -Mentions 'check file deleted: tests/Test-Something.ps1' -Mutate {
        param($r) Remove-Item -LiteralPath (Join-Path $r 'tests\Test-Something.ps1') -Force }

    Invoke-Case -Name 'check file renamed passes' -Root $root -Expect PASS -Mutate {
        param($r) $null = Invoke-FixtureGit -Root $r -Argument @('mv', 'tests/Test-Something.ps1', 'tests/Test-Other.ps1') }

    Invoke-Case -Name 'the tripwire itself edited is held' -Root $root -Expect HELD -Mentions 'protected path changed: tools/Test-MergeTripwire.ps1' -Mutate {
        param($r) Write-FixtureFile -Root $r -Path 'tools/Test-MergeTripwire.ps1' -Content "# relaxed`n" }

    Invoke-Case -Name 'a workflow edited is held' -Root $root -Expect HELD -Mentions 'protected path changed: .github/workflows/ci.yml' -Mutate {
        param($r) Write-FixtureFile -Root $r -Path '.github/workflows/ci.yml' -Content "name: CI`non: push`n" }

    Invoke-Case -Name 'the merge policy edited is held' -Root $root -Expect HELD -Mentions 'protected path changed: docs/governance/merge-policy.md' -Mutate {
        param($r) Write-FixtureFile -Root $r -Path 'docs/governance/merge-policy.md' -Content "# Merge policy`n`nRelaxed.`n" }

    Invoke-Case -Name 'steering section 2 changed is held' -Root $root -Expect HELD -Mentions 'section 2' -Mutate {
        param($r) Write-FixtureFile -Root $r -Path 'docs/governance/steering.md' -Content (@(
            '# Steering', '', '## 2. The contracts', '', '1. Every figure is a bare number.', '',
            '## 5. Working rules', '', '- Next action is the first item in Current focus.', '') -join "`n") }

    Invoke-Case -Name 'steering section 5 changed passes' -Root $root -Expect PASS -Mutate {
        param($r) Write-FixtureFile -Root $r -Path 'docs/governance/steering.md' -Content (@(
            '# Steering', '', '## 2. The contracts', '', '1. Every figure is an object, never a bare number.', '',
            '## 5. Working rules', '', '- Next action is the first item in Current focus.', '- Run its check.', '') -join "`n") }

    Invoke-Case -Name 'the operator-approved label clears a held finding' -Root $root -Expect PASS -Labels 'operator-approved' -Mentions 'approved by the' -Mutate {
        param($r) Remove-Item -LiteralPath (Join-Path $r 'tests\Test-Something.ps1') -Force }

    Invoke-Case -Name 'an explicit -BaseRef resolves the base' -Root $root -Expect HELD -BaseRef 'main' -Mentions @('(main)', 'check file deleted') -Mutate {
        param($r) Remove-Item -LiteralPath (Join-Path $r 'tests\Test-Something.ps1') -Force }

    Invoke-Case -Name 'a secret on an added line fails even with the label' -Root $root -Expect FAIL -Labels 'operator-approved' -Mentions 'src/app.ps1:2 looks like a GitHub token' -Mutate {
        param($r) Write-FixtureFile -Root $r -Path 'src/app.ps1' -Content ("Write-Output 'hello'`n`$token = '{0}'`n" -f $fakeToken) }

    Invoke-Case -Name 'a private key block fails' -Root $root -Expect FAIL -Mentions 'private key block' -Mutate {
        param($r) Write-FixtureFile -Root $r -Path 'src/key.pem' -Content ("-----BEGIN RSA " + "PRIVATE KEY-----`nabc`n") }

    Invoke-Case -Name 'a placeholder credential is not a secret' -Root $root -Expect PASS -Mutate {
        param($r) Write-FixtureFile -Root $r -Path 'src/app.ps1' -Content "`$apiKey = 'REPO_MGMT_SMOKE_AI_PLACEHOLDER_KEY'`n`$password = `"`${SECRET_FROM_ENV}`"`n" }

    Invoke-Case -Name 'a credential assigned in the clear fails' -Root $root -Expect FAIL -Mentions 'credential assignment' -Mutate {
        param($r) Write-FixtureFile -Root $r -Path 'src/app.ps1' -Content ("`$pass" + "word = '" + ('hunter2' * 3) + "'`n") }

    Invoke-Case -Name 'envelope network true fails' -Root $root -Expect FAIL -Mentions 'defaultPermissions.network is true' -Mutate {
        param($r) Write-FixtureFile -Root $r -Path 'backend/config/agent-providers.json' -Content (@{
                defaultScope       = @{ allowedPaths = @('**'); forbiddenPaths = @('.github/workflows/**') }
                defaultPermissions = @{ filesystemWrite = $true; shell = $true; network = $true; githubWrite = $false }
            } | ConvertTo-Json -Depth 5) }

    Invoke-Case -Name 'workflows no longer forbidden fails' -Root $root -Expect FAIL -Mentions 'no longer a forbidden path' -Mutate {
        param($r) Write-FixtureFile -Root $r -Path 'backend/config/agent-providers.json' -Content (@{
                defaultScope       = @{ allowedPaths = @('**'); forbiddenPaths = @() }
                defaultPermissions = @{ filesystemWrite = $true; shell = $true; network = $false; githubWrite = $false }
            } | ConvertTo-Json -Depth 5) }

    Invoke-Case -Name 'versioned config without a modelVersion bump fails' -Root $root -Expect FAIL -Mentions 'kind-signals.json changed without a modelVersion bump' -Mutate {
        param($r) Write-FixtureFile -Root $r -Path 'backend/config/kind-signals.json' -Content (@{ modelVersion = '2.0'; rules = @(@{ kind = 'library'; hint = 'psd1' }, @{ kind = 'firmware'; hint = 'ino' }) } | ConvertTo-Json -Depth 5) }

    Invoke-Case -Name 'versioned config with a modelVersion bump passes' -Root $root -Expect PASS -Mutate {
        param($r) Write-FixtureFile -Root $r -Path 'backend/config/kind-signals.json' -Content (@{ modelVersion = '2.1'; rules = @(@{ kind = 'library'; hint = 'psd1' }, @{ kind = 'firmware'; hint = 'ino' }) } | ConvertTo-Json -Depth 5) }

    Invoke-Case -Name 'eslint cap raised fails' -Root $root -Expect FAIL -Mentions '--max-warnings raised 10 -> 20' -Mutate {
        param($r) Write-FixtureFile -Root $r -Path 'frontend/package.json' -Content (@{ scripts = @{ lint = 'eslint . --max-warnings 20' } } | ConvertTo-Json -Depth 5) }

    Invoke-Case -Name 'eslint cap lowered passes' -Root $root -Expect PASS -Mutate {
        param($r) Write-FixtureFile -Root $r -Path 'frontend/package.json' -Content (@{ scripts = @{ lint = 'eslint . --max-warnings 5' } } | ConvertTo-Json -Depth 5) }

    Invoke-Case -Name 'PSScriptAnalyzer baseline raised or widened fails' -Root $root -Expect FAIL -Mentions @('PSUseSingularNouns raised 3 -> 4', 'new debt category PSAvoidUsingWriteHost = 2') -Mutate {
        param($r) Write-FixtureFile -Root $r -Path 'scripts/pssa-baseline.json' -Content (@{ PSUseSingularNouns = 4; PSAvoidUsingWriteHost = 2 } | ConvertTo-Json) }

    Invoke-Case -Name 'PSScriptAnalyzer baseline lowered passes' -Root $root -Expect PASS -Mutate {
        param($r) Write-FixtureFile -Root $r -Path 'scripts/pssa-baseline.json' -Content (@{ PSUseSingularNouns = 2 } | ConvertTo-Json) }

    Invoke-Case -Name 'UI ratchet count raised fails' -Root $root -Expect FAIL -Mentions 'outlineNone raised 4 -> 5' -Mutate {
        param($r) Write-FixtureFile -Root $r -Path 'tools/ui-ratchet-baseline.json' -Content (@{ counts = @{ outlineNone = 5 }; byFile = @{} } | ConvertTo-Json -Depth 5) }

    Write-Host ''
    Write-Host '== Live repository ==' -ForegroundColor Cyan
    $liveOutput = (& pwsh -NoProfile -ExecutionPolicy Bypass -File $toolPath -WorkspaceRoot $WorkspaceRoot -FailOnError 2>&1) | Out-String
    $liveOutcome = 'NONE'
    if ($liveOutput -match 'Merge tripwire: (PASS|HELD|FAIL)') { $liveOutcome = $Matches[1] }
    if ($liveOutcome -eq 'FAIL' -or $liveOutcome -eq 'NONE') {
        $failures.Add(('live repository: tripwire outcome {0}' -f $liveOutcome))
        Write-Host ($liveOutput -replace '(?m)^', '         ')
    }
    else { Write-Host ("  [ok]   live repository -> {0} (a hard finding would fail this proof)" -f $liveOutcome) -ForegroundColor Green }
}
finally {
    foreach ($fixture in $fixtureRoots) { Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction Ignore }
}

Write-Host ''
if ($failures.Count -gt 0) {
    Write-Host ("Merge tripwire proof: {0} of {1} case(s) failed." -f $failures.Count, $caseCount) -ForegroundColor Red
    foreach ($failure in $failures) { Write-Host ("  - {0}" -f $failure) -ForegroundColor Red }
    if ($FailOnError) { exit 1 }
    exit 0
}
Write-Host ("Merge tripwire proof: ok - {0} cases and the live repository hold." -f $caseCount) -ForegroundColor Green
exit 0
