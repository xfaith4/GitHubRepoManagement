#Requires -Version 5.1
<#
.SYNOPSIS
    Fail a commit that ships a capability while leaving the roadmap describing it
    as planned.

.DESCRIPTION
    Release 3.4, recorded 2026-08-15. PR #134 shipped Git.DefaultBranchSync.ps1 --
    306 lines, wired into the task runner, covered by module smoke against real
    fixture clones -- and updated no milestone state. Every one of Release 3.4's
    six milestones still read `(state: planned)` afterwards, and the next agent
    to read ROADMAP.md was one step away from rebuilding a module that already
    existed and already passed its tests.

    The drift is only visible at the COMMIT boundary. A working-tree gate cannot
    see it: after the fact, a roadmap that says `planned` and a module that
    exists are both perfectly valid files. What is invalid is the transition
    between them landing without the record moving too.

    The rule this enforces:

        A commit whose message claims a release (`feat(release-N.M):` and
        friends) AND whose diff touches backend/ or scripts/ MUST advance a
        milestone in ROADMAP.md -- either checking a box `[x]` or writing a
        `(state: ...)` that is not `planned`.

    THE FIRST VERSION OF THIS CHECK PASSED ON PR #134.

    It required only that ROADMAP.md appear in the diff, and #134 touched
    ROADMAP.md -- it added the entire Release 3.4 section, 141 lines, with all six
    milestones reading `(state: planned)` while shipping the code for two of them.
    A rule satisfied by a filename is not a rule about whether the record moved.

    Hence the stronger predicate: shipping capability code must coincide with at
    least one milestone ADVANCING. Adding new `planned` milestones is not
    advancement, which is precisely the hole #134 fell through.

    It still does not try to prove the RIGHT milestone moved -- that needs intent,
    and any proxy for it is gameable. It proves the record was moved forward at
    all, which is the thing that was actually missing.

    Docs-only commits, refactors, fixes, chores and revert commits are all out of
    scope, because none of them claim a milestone.

.PARAMETER Range
    Git revision range to inspect, e.g. 'origin/main..HEAD'. Defaults to 'auto',
    which resolves to origin/main..HEAD when that is available -- the commits this
    branch is proposing -- and falls back to HEAD~1..HEAD otherwise.

    'auto' resolving to an EMPTY range (on main, nothing ahead) is a legitimate
    pass: there are no proposed commits to check. Being unable to resolve any
    range at all is not -- it exits non-zero, because "could not verify" must
    never read as "verified".

.PARAMETER FailOnError
    Exit non-zero when a violation is found. CI passes this; a local advisory run
    can omit it and still see the report.

.EXAMPLE
    pwsh ./tools/Test-RoadmapCapabilityRecord.ps1 -Range 'origin/main..HEAD' -FailOnError
#>
[CmdletBinding()]
param(
    [Parameter()][string]$Range = 'auto',
    [Parameter()][switch]$FailOnError,
    [Parameter()][string]$WorkspaceRoot = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# A commit "claims a release" when its subject carries a conventional-commit
# scope naming one. Both `feat(release-3.4):` and `feat(phase4):` are in this
# repo's history, so both count -- the point is a message asserting that release
# work landed.
$script:ReleaseClaimPattern = '^\s*\w+\((?:release|phase)[-\s]?[0-9]'

# Paths whose change constitutes shipping a capability. Tests and docs are
# excluded: a test-only commit is not a capability claim, and this check must not
# punish someone adding coverage to work already recorded.
function Test-IsCapabilityPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $normalized = $Path -replace '\\', '/'
    if ($normalized -notmatch '^(backend|scripts)/') { return $false }
    if ($normalized -match '\.Tests\.ps1$') { return $false }
    if ($normalized -match '(^|/)Invoke-.*(SmokeTest|TestSuite)\.ps1$') { return $false }
    return $true
}

# Did this commit move a milestone FORWARD in ROADMAP.md? Adding milestones that
# read `planned` is recording intent, not shipping -- #134 did exactly that and
# the first version of this check waved it through.
function Test-RoadmapAdvanced {
    param([Parameter(Mandatory = $true)][string]$Sha)

    # The `--` goes AFTER the rev. With it before, git reads $Sha as a pathspec
    # and diffs HEAD instead -- which made this function report on the working
    # commit rather than the one under test, and it passed everything.
    $diff = (& git -C $WorkspaceRoot show --format='' --unified=0 $Sha -- 'ROADMAP.md' 2>&1) | Out-String
    if ($LASTEXITCODE -ne 0) { return $false }

    foreach ($line in ($diff -split "`n")) {
        if ($line -notmatch '^\+') { continue }
        if ($line -match '^\+\+\+') { continue }

        # A checked box is unambiguous advancement.
        if ($line -match '^\+\s*-\s*\[x\]') { return $true }

        # So is any state past `planned`. The vocabulary is section 3's.
        if ($line -match '\(state:\s*([a-z\-]+)') {
            if ($Matches[1] -ne 'planned') { return $true }
        }
    }

    return $false
}

function Get-CommitsInRange {
    param([Parameter(Mandatory = $true)][string]$Range)

    $raw = (& git -C $WorkspaceRoot rev-list --no-merges $Range 2>&1) | Out-String
    if ($LASTEXITCODE -ne 0) {
        throw ("Could not resolve range '{0}': {1}" -f $Range, $raw.Trim())
    }
    return @($raw -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

function Resolve-AutoRange {
    # origin/main..HEAD is the honest question on a feature branch: what is this
    # branch proposing? A shallow CI checkout has no origin/main, so the caller
    # is told rather than silently downgraded to a one-commit window.
    $null = (& git -C $WorkspaceRoot rev-parse --verify --quiet 'origin/main') 2>&1
    if ($LASTEXITCODE -eq 0) { return 'origin/main..HEAD' }

    $null = (& git -C $WorkspaceRoot rev-parse --verify --quiet 'HEAD~1') 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host '  origin/main is unavailable (shallow clone?); falling back to HEAD~1..HEAD.' -ForegroundColor Yellow
        return 'HEAD~1..HEAD'
    }

    throw 'Cannot resolve a commit range: neither origin/main nor HEAD~1 exists. Fetch history (actions/checkout fetch-depth: 0) -- an unverifiable check must not report success.'
}

if ($Range -eq 'auto') { $Range = Resolve-AutoRange }

$violations = [System.Collections.Generic.List[object]]::new()
$examined = 0

foreach ($sha in Get-CommitsInRange -Range $Range) {
    $subject = ((& git -C $WorkspaceRoot log -1 --format='%s' $sha) | Out-String).Trim()
    if ($subject -notmatch $script:ReleaseClaimPattern) { continue }

    $examined++
    $files = @(((& git -C $WorkspaceRoot show --name-only --format='' $sha) | Out-String) -split "`n" |
        ForEach-Object { $_.Trim() } | Where-Object { $_ })

    $capabilityFiles = @($files | Where-Object { Test-IsCapabilityPath -Path $_ })
    if (@($capabilityFiles).Count -eq 0) { continue }

    $touchedRoadmap = @($files | Where-Object { ($_ -replace '\\', '/') -eq 'ROADMAP.md' }).Count -gt 0
    if ($touchedRoadmap -and (Test-RoadmapAdvanced -Sha $sha)) { continue }

    $violations.Add([pscustomobject]@{
        Sha             = $sha.Substring(0, [Math]::Min(8, $sha.Length))
        Subject         = $subject
        CapabilityFiles = @($capabilityFiles)
        Reason          = if ($touchedRoadmap) {
            'ROADMAP.md changed, but no milestone advanced -- every added state line still reads `planned`.'
        } else {
            'ROADMAP.md was not touched at all.'
        }
    }) | Out-Null
}

Write-Host ''
Write-Host '== Roadmap capability-record check ==' -ForegroundColor Cyan
Write-Host ("  Range:              {0}" -f $Range)
Write-Host ("  Release claims:     {0}" -f $examined)
Write-Host ("  Violations:         {0}" -f $violations.Count)

foreach ($v in $violations) {
    Write-Host ''
    Write-Host ("[FAIL] {0} {1}" -f $v.Sha, $v.Subject) -ForegroundColor Red
    Write-Host ("       {0}" -f $v.Reason) -ForegroundColor Red
    Write-Host  '       Capability files shipped in this commit:' -ForegroundColor Red
    foreach ($f in @($v.CapabilityFiles | Select-Object -First 10)) {
        Write-Host ("         - {0}" -f $f) -ForegroundColor DarkRed
    }
    if (@($v.CapabilityFiles).Count -gt 10) {
        Write-Host ("         ... and {0} more" -f (@($v.CapabilityFiles).Count - 10)) -ForegroundColor DarkRed
    }
    Write-Host  '       Move the milestone state in this same commit. A merge must not be' -ForegroundColor Yellow
    Write-Host  '       able to claim a milestone shipped while the roadmap still says planned.' -ForegroundColor Yellow
}

if ($violations.Count -gt 0) {
    Write-Host ''
    if ($FailOnError) { exit 1 }
    exit 0
}

Write-Host '  [PASS] every release-claiming commit moved the record with the code.' -ForegroundColor Green
Write-Host ''
exit 0
