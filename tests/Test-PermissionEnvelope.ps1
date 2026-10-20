#Requires -Version 7.0
<#
.SYNOPSIS
    D-012 - a run whose branch touches a forbidden path fails by name and is
    never pushed.

.DESCRIPTION
    Three layers, proved offline:

      - The matcher (Test-PathGlobMatch, Find-ForbiddenPathChange) and the
        effective list (Get-EffectiveForbiddenPath): `.github/workflows/**` is
        forbidden even when a packet omits it, and `.github/workflows-proposed/`
        is not.
      - The runner's check (Test-RunPermissionEnvelope) against real git
        repositories: a workflow edit the agent committed itself, one left
        uncommitted, and a rename out of the directory all fail; a change the
        base made after the branch point is not blamed on the run; a missing or
        unknown base fails closed.
      - The wiring: inside Invoke-QueuedTask the check runs before the push
        decision and the push, and its refusal returns.

    Writes only under a temporary directory, removed on exit.

.EXAMPLE
    pwsh ./tests/Test-PermissionEnvelope.ps1 -FailOnError
#>
[CmdletBinding()]
param(
    [Parameter()][string]$WorkspaceRoot = (Split-Path -Parent $PSScriptRoot),
    [Parameter()][switch]$FailOnError
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$WorkspaceRoot = (Resolve-Path -LiteralPath $WorkspaceRoot).Path
$runnerPath = Join-Path $WorkspaceRoot 'scripts/Invoke-RoadmapTaskRunner.ps1'
. $runnerPath -LoadFunctionsOnly

$failures = [System.Collections.Generic.List[string]]::new()
$passed = 0
function Assert-That {
    param([bool]$Condition, [string]$Message)
    if ($Condition) { $script:passed++ } else { $script:failures.Add($Message) }
}

# --- The matcher ---
$globCases = @(
    @{ path = '.github/workflows/ci.yml'; pattern = '.github/workflows/**'; expected = $true }
    @{ path = '.github/workflows/nested/x.yml'; pattern = '.github/workflows/**'; expected = $true }
    @{ path = '.github\workflows\ci.yml'; pattern = '.github/workflows/**'; expected = $true }
    @{ path = '.GitHub/Workflows/CI.yml'; pattern = '.github/workflows/**'; expected = $true }
    @{ path = './.github/workflows/ci.yml'; pattern = '.github/workflows/**'; expected = $true }
    @{ path = '.github/workflows-proposed/ci.yml'; pattern = '.github/workflows/**'; expected = $false }
    @{ path = '.github/dependabot.yml'; pattern = '.github/workflows/**'; expected = $false }
    @{ path = 'docs/.github/workflows/ci.yml'; pattern = '.github/workflows/**'; expected = $false }
    @{ path = 'secrets/prod/key.pem'; pattern = 'secrets/'; expected = $true }
    @{ path = 'secrets'; pattern = 'secrets'; expected = $true }
    @{ path = 'secrets/a.txt'; pattern = 'secrets'; expected = $true }
    @{ path = 'secretsfile.txt'; pattern = 'secrets'; expected = $false }
    @{ path = 'src/app.ps1'; pattern = 'src/*.ps1'; expected = $true }
    @{ path = 'src/lib/app.ps1'; pattern = 'src/*.ps1'; expected = $false }
    @{ path = 'src/lib/app.ps1'; pattern = 'src/**/*.ps1'; expected = $true }
    @{ path = 'src/app.ps1'; pattern = 'src/**/*.ps1'; expected = $true }
    @{ path = 'a.env'; pattern = '?.env'; expected = $true }
    @{ path = 'ab.env'; pattern = '?.env'; expected = $false }
    @{ path = 'config/app+1.json'; pattern = 'config/app+1.json'; expected = $true }
    @{ path = ''; pattern = '.github/workflows/**'; expected = $false }
    @{ path = 'src/app.ps1'; pattern = ''; expected = $false }
)
foreach ($case in $globCases) {
    $actual = Test-PathGlobMatch -Path $case.path -Pattern $case.pattern
    Assert-That ($actual -eq $case.expected) ("glob: '{0}' vs '{1}' should be {2}, got {3}" -f $case.path, $case.pattern, $case.expected, $actual)
}

# These return their arrays whole (`return , $list`), so an empty answer is
# never $null; wrapping a call in @() would nest it, so none is wrapped.
$noPacket = Get-EffectiveForbiddenPath -Packet $null
Assert-That ($noPacket -is [array] -and $noPacket.Count -eq 1 -and [string]$noPacket[0] -eq '.github/workflows/**') ("a run with no packet is still held to .github/workflows/** (got '{0}')" -f ($noPacket -join ', '))
$emptyScope = Get-EffectiveForbiddenPath -Packet ([pscustomobject]@{ scope = [pscustomobject]@{ allowedPaths = @('src/**'); forbiddenPaths = @() } })
Assert-That ($emptyScope.Count -eq 1 -and [string]$emptyScope[0] -eq '.github/workflows/**') 'a packet with an empty forbiddenPaths list still forbids .github/workflows/**'
$withSecrets = Get-EffectiveForbiddenPath -Packet ([ordered]@{ scope = [ordered]@{ forbiddenPaths = @('secrets/**', '.GITHUB/workflows/**') } })
Assert-That ($withSecrets.Count -eq 2 -and $withSecrets[0] -eq 'secrets/**') ("a packet's own entries come first and a case-variant duplicate of the floor is dropped (got '{0}')" -f ($withSecrets -join ', '))

$none = Find-ForbiddenPathChange -ChangedPath @() -ForbiddenPath @('.github/workflows/**')
Assert-That ($null -ne $none -and @($none).Count -eq 0) 'no changes yield an empty array, not $null'
$found = Find-ForbiddenPathChange -ChangedPath @('src/a.ps1', '.github/workflows/ci.yml', 'secrets/k') -ForbiddenPath @('secrets/**', '.github/workflows/**')
Assert-That ($found.Count -eq 2) ("two of three changes are forbidden (got {0})" -f $found.Count)
Assert-That (@($found | Where-Object { $_.path -eq '.github/workflows/ci.yml' -and $_.pattern -eq '.github/workflows/**' }).Count -eq 1) 'a violation names the path and the pattern it broke'

# --- The runner's check, against real repositories ---
$fixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("permission-envelope-{0}" -f [guid]::NewGuid().ToString('n'))
$null = New-Item -ItemType Directory -Path $fixtureRoot -Force

function Invoke-FixtureGit {
    param([Parameter(Mandatory)][string]$Repo, [Parameter(Mandatory)][string[]]$GitArgs)
    $out = & git -C $Repo -c user.name=fixture -c user.email=fixture@example.invalid -c commit.gpgsign=false @GitArgs 2>&1
    if ($LASTEXITCODE -ne 0) { throw ("git {0} failed: {1}" -f ($GitArgs -join ' '), ($out -join ' ')) }
    return $out
}
function Initialize-FixtureRepo {
    param([string]$Name)
    $repo = Join-Path $fixtureRoot $Name
    $null = New-Item -ItemType Directory -Path (Join-Path $repo '.github/workflows') -Force
    Set-Content -LiteralPath (Join-Path $repo 'README.md') -Value 'fixture' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $repo '.github/workflows/ci.yml') -Value 'name: ci' -Encoding UTF8
    $null = Invoke-FixtureGit -Repo $repo -GitArgs @('init', '--quiet', '--initial-branch=main')
    $null = Invoke-FixtureGit -Repo $repo -GitArgs @('add', '-A')
    $null = Invoke-FixtureGit -Repo $repo -GitArgs @('commit', '--quiet', '-m', 'base')
    $base = ((Invoke-FixtureGit -Repo $repo -GitArgs @('rev-parse', 'HEAD')) | Out-String).Trim()
    $null = Invoke-FixtureGit -Repo $repo -GitArgs @('switch', '--quiet', '-c', 'roadmap/run')
    return [pscustomobject]@{ path = $repo; base = $base }
}

try {
    # In scope: a source change and a proposed workflow pass.
    $clean = Initialize-FixtureRepo 'clean'
    $null = New-Item -ItemType Directory -Path (Join-Path $clean.path 'src') -Force
    Set-Content -LiteralPath (Join-Path $clean.path 'src/app.ps1') -Value 'x' -Encoding UTF8
    $null = New-Item -ItemType Directory -Path (Join-Path $clean.path '.github/workflows-proposed') -Force
    Set-Content -LiteralPath (Join-Path $clean.path '.github/workflows-proposed/ci.yml') -Value 'name: proposed' -Encoding UTF8
    $null = Invoke-FixtureGit -Repo $clean.path -GitArgs @('add', '-A')
    $null = Invoke-FixtureGit -Repo $clean.path -GitArgs @('commit', '--quiet', '-m', 'work')
    $ok = Test-RunPermissionEnvelope -RepoPath $clean.path -BaseCommit $clean.base -Packet $null
    Assert-That ($ok.ok) ("a source change plus a proposed workflow passes (error: {0})" -f $ok.error)
    Assert-That ($ok.changedCount -eq 2) ("the check read both changed paths (got {0})" -f $ok.changedCount)
    Assert-That ($ok.summary -match '^passed: 2 changed') ("the pass is recorded with its count (got '{0}')" -f $ok.summary)

    # Committed by the agent itself: a provider deny rule never saw it.
    $committed = Initialize-FixtureRepo 'committed'
    Add-Content -LiteralPath (Join-Path $committed.path '.github/workflows/ci.yml') -Value 'on: push' -Encoding UTF8
    $null = Invoke-FixtureGit -Repo $committed.path -GitArgs @('commit', '--quiet', '-am', 'agent edits ci')
    $c = Test-RunPermissionEnvelope -RepoPath $committed.path -BaseCommit $committed.base -Packet $null
    Assert-That (-not $c.ok) 'a workflow edit the agent committed fails the run'
    Assert-That ($c.error -match [regex]::Escape('.github/workflows/ci.yml (.github/workflows/**)')) ("the failure names the path and the rule (got '{0}')" -f $c.error)
    Assert-That ($c.error -match 'Not pushed' -and $c.error -match 'workflows-proposed') 'the failure says it was not pushed and where a workflow goes instead'

    # Left uncommitted.
    $dirty = Initialize-FixtureRepo 'dirty'
    Set-Content -LiteralPath (Join-Path $dirty.path '.github/workflows/new.yml') -Value 'name: new' -Encoding UTF8
    $d = Test-RunPermissionEnvelope -RepoPath $dirty.path -BaseCommit $dirty.base -Packet $null
    Assert-That (-not $d.ok -and @($d.violations | Where-Object { $_.path -eq '.github/workflows/new.yml' }).Count -eq 1) 'an uncommitted workflow file fails the run'

    # A non-ASCII name: git C-quotes it unless told not to (PR #352 review).
    $accent = [string][char]0x00E9
    $unicode = Initialize-FixtureRepo 'unicode'
    Set-Content -LiteralPath (Join-Path $unicode.path ".github/workflows/d$accent.yml") -Value 'name: sneaky' -Encoding UTF8
    $null = Invoke-FixtureGit -Repo $unicode.path -GitArgs @('add', '-A')
    $null = Invoke-FixtureGit -Repo $unicode.path -GitArgs @('commit', '--quiet', '-m', 'agent adds a workflow with a non-ASCII name')
    $u = Test-RunPermissionEnvelope -RepoPath $unicode.path -BaseCommit $unicode.base -Packet $null
    Assert-That (-not $u.ok) 'a committed workflow with a non-ASCII name fails the run'
    Assert-That (@($u.violations | Where-Object { $_.path -eq ".github/workflows/d$accent.yml" }).Count -eq 1) ("the violation names the file unquoted (got '{0}')" -f (@($u.violations | ForEach-Object { $_.path }) -join ', '))
    Set-Content -LiteralPath (Join-Path $unicode.path ".github/workflows/n$accent.yml") -Value 'name: dirty' -Encoding UTF8
    $u2 = Test-RunPermissionEnvelope -RepoPath $unicode.path -BaseCommit $unicode.base -Packet $null
    Assert-That (@($u2.violations | Where-Object { $_.path -eq ".github/workflows/n$accent.yml" }).Count -eq 1) 'an uncommitted workflow with a non-ASCII name is named unquoted'
    $cafe = Initialize-FixtureRepo 'cafe'
    $null = New-Item -ItemType Directory -Path (Join-Path $cafe.path 'docs') -Force
    Set-Content -LiteralPath (Join-Path $cafe.path "docs/caf$accent.md") -Value 'x' -Encoding UTF8
    $null = Invoke-FixtureGit -Repo $cafe.path -GitArgs @('add', '-A')
    $null = Invoke-FixtureGit -Repo $cafe.path -GitArgs @('commit', '--quiet', '-m', 'touch cafe')
    $cafePacket = [pscustomobject]@{ scope = [pscustomobject]@{ forbiddenPaths = @("docs/caf$accent.md") } }
    $cf = Test-RunPermissionEnvelope -RepoPath $cafe.path -BaseCommit $cafe.base -Packet $cafePacket
    Assert-That (-not $cf.ok) 'a packet entry naming a non-ASCII file exactly binds'

    # A rename out of the directory removes a workflow: both sides count.
    $renamed = Initialize-FixtureRepo 'renamed'
    $null = Invoke-FixtureGit -Repo $renamed.path -GitArgs @('mv', '.github/workflows/ci.yml', 'ci.yml.bak')
    $null = Invoke-FixtureGit -Repo $renamed.path -GitArgs @('commit', '--quiet', '-m', 'move ci away')
    $r = Test-RunPermissionEnvelope -RepoPath $renamed.path -BaseCommit $renamed.base -Packet $null
    Assert-That (-not $r.ok) 'renaming a workflow out of the directory fails the run'

    # The packet's own list binds too.
    $secret = Initialize-FixtureRepo 'secret'
    $null = New-Item -ItemType Directory -Path (Join-Path $secret.path 'secrets') -Force
    Set-Content -LiteralPath (Join-Path $secret.path 'secrets/key.txt') -Value 'k' -Encoding UTF8
    $null = Invoke-FixtureGit -Repo $secret.path -GitArgs @('add', '-A')
    $null = Invoke-FixtureGit -Repo $secret.path -GitArgs @('commit', '--quiet', '-m', 'touch secrets')
    $packet = [pscustomobject]@{ scope = [pscustomobject]@{ allowedPaths = @('**'); forbiddenPaths = @('secrets/**') } }
    $s = Test-RunPermissionEnvelope -RepoPath $secret.path -BaseCommit $secret.base -Packet $packet
    Assert-That (-not $s.ok -and $s.error -match [regex]::Escape('secrets/key.txt (secrets/**)')) ("a packet's forbiddenPaths entry binds (got '{0}')" -f $s.error)
    $sNoPacket = Test-RunPermissionEnvelope -RepoPath $secret.path -BaseCommit $secret.base -Packet $null
    Assert-That ($sNoPacket.ok) '(control) without that packet entry the same change passes'

    # The base moved on after the branch point: its workflow change is not the run's.
    $moved = Initialize-FixtureRepo 'moved'
    $null = Invoke-FixtureGit -Repo $moved.path -GitArgs @('switch', '--quiet', 'main')
    Add-Content -LiteralPath (Join-Path $moved.path '.github/workflows/ci.yml') -Value 'on: pull_request' -Encoding UTF8
    $null = Invoke-FixtureGit -Repo $moved.path -GitArgs @('commit', '--quiet', '-am', 'owner edits ci on main')
    $movedBase = ((Invoke-FixtureGit -Repo $moved.path -GitArgs @('rev-parse', 'HEAD')) | Out-String).Trim()
    $null = Invoke-FixtureGit -Repo $moved.path -GitArgs @('switch', '--quiet', 'roadmap/run')
    Set-Content -LiteralPath (Join-Path $moved.path 'notes.md') -Value 'run work' -Encoding UTF8
    $null = Invoke-FixtureGit -Repo $moved.path -GitArgs @('add', '-A')
    $null = Invoke-FixtureGit -Repo $moved.path -GitArgs @('commit', '--quiet', '-m', 'run work')
    $m = Test-RunPermissionEnvelope -RepoPath $moved.path -BaseCommit $movedBase -Packet $null
    Assert-That ($m.ok) ("a workflow change the base made after the branch point is not blamed on the run (error: {0})" -f $m.error)

    # Fails closed.
    $noBase = Test-RunPermissionEnvelope -RepoPath $clean.path -BaseCommit '' -Packet $null
    Assert-That (-not $noBase.ok -and $noBase.error -match 'unprovable') 'no recorded base commit fails closed, by name'
    $badBase = Test-RunPermissionEnvelope -RepoPath $clean.path -BaseCommit 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeef' -Packet $null
    Assert-That (-not $badBase.ok -and $badBase.error -match 'git diff') ("an unknown base commit fails closed and names git (got '{0}')" -f $badBase.error)
}
finally {
    Remove-Item -LiteralPath $fixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
}

# --- The wiring ---
$tokens = $null; $parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($runnerPath, [ref]$tokens, [ref]$parseErrors)
Assert-That (@($parseErrors).Count -eq 0) ("the runner parses ({0} error(s))" -f @($parseErrors).Count)
$queued = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Invoke-QueuedTask' }, $true)
Assert-That ($null -ne $queued) 'Invoke-QueuedTask exists'
if ($null -ne $queued) {
    $firstCall = {
        param([string]$Name)
        $calls = @($queued.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq $Name }, $true))
        if ($calls.Count -eq 0) { return $null }
        return ($calls | Sort-Object { $_.Extent.StartOffset } | Select-Object -First 1)
    }
    $check = & $firstCall 'Test-RunPermissionEnvelope'
    $transition = & $firstCall 'Resolve-PostImplementationTransition'
    $push = & $firstCall 'Invoke-RunnerBranchPush'
    Assert-That ($null -ne $check) 'Invoke-QueuedTask calls Test-RunPermissionEnvelope'
    if ($null -ne $check -and $null -ne $transition -and $null -ne $push) {
        Assert-That ($check.Extent.StartOffset -lt $transition.Extent.StartOffset) 'the envelope check runs before the push decision'
        Assert-That ($check.Extent.StartOffset -lt $push.Extent.StartOffset) 'the envelope check runs before the push'
    }
    $refusal = $queued.Find({
            param($n)
            $n -is [System.Management.Automation.Language.IfStatementAst] -and
            $n.Clauses[0].Item1.Extent.Text -match '-not\s+\$envelope\.ok'
        }, $true)
    Assert-That ($null -ne $refusal) 'the runner branches on a failed envelope'
    if ($null -ne $refusal) {
        $body = $refusal.Clauses[0].Item2
        Assert-That ($null -ne $body.Find({ param($n) $n -is [System.Management.Automation.Language.ReturnStatementAst] }, $true)) 'a failed envelope returns before the push'
        Assert-That ($body.Extent.Text -match "status\s*=\s*'failed'") "a failed envelope records status 'failed', which Approve & push refuses"
    }
}

Write-Host ("Permission envelope: {0} passed, {1} failed" -f $passed, $failures.Count)
foreach ($f in $failures) { Write-Host "  FAIL: $f" }
if ($failures.Count -gt 0 -and $FailOnError) { exit 1 }
