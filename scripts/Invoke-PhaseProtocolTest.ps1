[CmdletBinding()]
param(
    # Derived from this script's location rather than a hardcoded drive letter,
    # so the suite runs unmodified from any clone location (ROADMAP Lane 0.3).
    [string]$WorkspaceRoot = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $WorkspaceRoot 'backend\modules\roadmap\Roadmap.Parser.ps1')
. (Join-Path $WorkspaceRoot 'backend\modules\roadmap\Roadmap.PhaseProtocol.ps1')

$script:Pass = 0
$script:Fail = 0
function Assert($cond, $name) {
    if ($cond) { $script:Pass++; Write-Host "  [PASS] $name" -ForegroundColor Green }
    else { $script:Fail++; Write-Host "  [FAIL] $name" -ForegroundColor Red }
}

# --- Canonical fixture: h3 release + h4 phase plan, full 6-col protocol table.
#     "Phase 1: Setup" appears in BOTH releases (ambiguity test).
$fixtureLines = @(
    '# Fixture Roadmap',
    '',
    '## 6. Future Releases',
    '',
    '### Release 9.1 — Test Alpha',
    '',
    '**Goal:** test alpha.',
    '',
    '- [ ] milestone one',
    '- [x] milestone two',
    '',
    '#### Phase plan (within this release)',
    '',
    '| Phase | Scope | Status | Completed | Token usage | Work units |',
    '| --- | --- | --- | --- | --- | --- |',
    '| Phase 1: Setup | bootstrap the thing | done | 2026-07-01 | 100000 | 3 |',
    '| Phase 2: Build | build the thing | in-progress | – | – | 5 |',
    '| Phase 3: Ship | ship the thing | planned | – | – | 2 |',
    '',
    '### Release 9.2 — Test Beta',
    '',
    '**Goal:** test beta.',
    '',
    '- [ ] beta milestone',
    '',
    '#### Phase plan (within this release)',
    '',
    '| Phase | Scope | Status | Completed | Token usage | Work units |',
    '| --- | --- | --- | --- | --- | --- |',
    '| Phase 1: Setup | beta setup | planned | – | – | 4 |',
    ''
)
$fixture = ($fixtureLines -join "`n")

Write-Host '[STEP] Parser tolerance (h3 release / h4 phase plan)' -ForegroundColor Cyan
$ctx = @(Get-RoadmapReleaseContexts -RoadmapContent $fixture)
Assert ($ctx.Count -eq 2) "fixture parses 2 releases (got $($ctx.Count))"
$r91 = @($ctx | Where-Object { $_.releaseVersion -eq '9.1' })[0]
Assert (@($r91.phasePlan).Count -eq 3) "release 9.1 has 3 phases"
Assert ($null -ne $r91.activePhasePlan -and $r91.activePhasePlan.phaseName -eq 'Phase 2: Build') "9.1 active phase = 'Phase 2: Build'"

Write-Host '[STEP] Write-back: mark active phase done' -ForegroundColor Cyan
$res = Set-RoadmapPhaseState -Content $fixture -ReleaseVersion '9.1' -PhaseName 'Phase 2: Build' `
    -Status 'done' -Completed '2026-07-08' -TokenUsage '250000'
Assert ($res.success -and $res.changed) "write-back succeeded + changed"
$ctx2 = @(Get-RoadmapReleaseContexts -RoadmapContent $res.content)
$r91b = @($ctx2 | Where-Object { $_.releaseVersion -eq '9.1' })[0]
$p2 = @($r91b.phasePlan | Where-Object { $_.phaseName -eq 'Phase 2: Build' })[0]
Assert ($p2.isComplete) "phase 2 now isComplete"
Assert ($p2.status -eq 'done' -and $p2.completed -eq '2026-07-08' -and $p2.tokenUsage -eq '250000') "phase 2 cells updated (status/completed/tokenUsage)"
Assert ($null -ne $r91b.activePhasePlan -and $r91b.activePhasePlan.phaseName -eq 'Phase 3: Ship') "active phase advanced to 'Phase 3: Ship'"

Write-Host '[STEP] Surgical: exactly one line changed, EOL preserved' -ForegroundColor Cyan
$before = $fixture -split "`n"
$after = $res.content -split "`n"
$diffCount = 0
for ($k = 0; $k -lt [Math]::Max($before.Count, $after.Count); $k++) {
    $a = if ($k -lt $before.Count) { $before[$k] } else { '<none>' }
    $b = if ($k -lt $after.Count) { $after[$k] } else { '<none>' }
    if ($a -ne $b) { $diffCount++ }
}
Assert ($diffCount -eq 1) "exactly 1 line differs (got $diffCount)"
Assert ($res.content -notmatch "`r`n") "LF preserved (no CRLF introduced)"

Write-Host '[STEP] CRLF content round-trips as CRLF' -ForegroundColor Cyan
$crlf = ($fixtureLines -join "`r`n")
$resCrlf = Set-RoadmapPhaseState -Content $crlf -ReleaseVersion '9.1' -PhaseName 'Phase 3: Ship' -Status 'done'
Assert ($resCrlf.success -and ($resCrlf.content -match "`r`n")) "CRLF preserved on write-back"

Write-Host '[STEP] Ambiguity + scoping ("Phase 1: Setup" in both releases)' -ForegroundColor Cyan
$amb = Set-RoadmapPhaseState -Content $fixture -PhaseName 'Phase 1: Setup' -Status 'done'
Assert (-not $amb.success -and $amb.reason -eq 'ambiguous-phase-specify-release') "ambiguous phase without release -> refused"
$scoped = Set-RoadmapPhaseState -Content $fixture -ReleaseVersion '9.2' -PhaseName 'Phase 1: Setup' -Status 'done' -Completed '2026-07-08'
Assert ($scoped.success -and $scoped.matchedRelease -eq '9.2') "scoping by release resolves the ambiguity"
# ensure only 9.2's row moved, 9.1's 'Phase 1: Setup' (already done) intact
$ctx3 = @(Get-RoadmapReleaseContexts -RoadmapContent $scoped.content)
$r92 = @($ctx3 | Where-Object { $_.releaseVersion -eq '9.2' })[0]
Assert (@($r92.phasePlan | Where-Object { $_.phaseName -eq 'Phase 1: Setup' })[0].isComplete) "9.2 Phase 1 now complete"

Write-Host '[STEP] Failure modes' -ForegroundColor Cyan
$nf = Set-RoadmapPhaseState -Content $fixture -ReleaseVersion '9.1' -PhaseName 'Phase 9: Nope' -Status 'done'
Assert (-not $nf.success -and $nf.reason -eq 'phase-not-found') "unknown phase -> phase-not-found"
# 3-column table (no Token usage column) should refuse a TokenUsage write
$threeCol = @('### Release 8.0 — Legacy', '', '#### Phase plan', '', '| Phase | Scope | Status |', '| --- | --- | --- |', '| Phase 1: X | do x | planned |', '') -join "`n"
$nc = Set-RoadmapPhaseState -Content $threeCol -PhaseName 'Phase 1: X' -TokenUsage '5'
Assert (-not $nc.success -and $nc.reason -eq 'no-tokenusage-column') "3-col table -> no-tokenusage-column"
# but a Status-only write on the 3-col table should succeed (status column exists)
$scOk = Set-RoadmapPhaseState -Content $threeCol -PhaseName 'Phase 1: X' -Status 'done'
Assert ($scOk.success -and $scOk.changed) "3-col table -> status-only write succeeds"

Write-Host '[STEP] Agent-readiness gate' -ForegroundColor Cyan
# scratch repo WITH a CI workflow (validation signal)
$scratchRepo = Join-Path $env:TEMP ('phaseproto-repo-' + [System.Guid]::NewGuid().ToString('N'))
$wfDir = Join-Path $scratchRepo '.github\workflows'
$null = New-Item -ItemType Directory -Path $wfDir -Force
Set-Content -LiteralPath (Join-Path $wfDir 'ci.yml') -Value "name: ci`non: [push]`njobs: {}" -Encoding UTF8
try {
    $gEligible = Test-RoadmapAgentReadiness -Content $fixture -RepoPath $scratchRepo -MaturityLevel 4
    Assert ($gEligible.eligible -and $gEligible.checks.hasProtocolColumns -and $gEligible.checks.hasValidationSignal) "canonical fixture @ L4 + CI -> ELIGIBLE"

    $gLowMaturity = Test-RoadmapAgentReadiness -Content $fixture -RepoPath $scratchRepo -MaturityLevel 2
    Assert ((-not $gLowMaturity.eligible) -and ($gLowMaturity.blockers -contains 'below-min-maturity')) "L2 -> blocked (below-min-maturity)"

    $gNoRepo = Test-RoadmapAgentReadiness -Content $fixture -MaturityLevel 4
    Assert ((-not $gNoRepo.eligible) -and ($gNoRepo.blockers -contains 'validation-signal-unknown')) "no repo path -> validation-signal-unknown"

    $gThreeCol = Test-RoadmapAgentReadiness -Content $threeCol -RepoPath $scratchRepo -MaturityLevel 4
    Assert ((-not $gThreeCol.eligible) -and ($gThreeCol.blockers -contains 'missing-protocol-columns')) "3-col table -> missing-protocol-columns"

    # The flagship repo's OWN roadmap: after the P0 column upgrade its phase-plan
    # tables carry the full protocol columns, so the format blocker is cleared (dogfood).
    $liveRoadmap = Get-Content (Join-Path $WorkspaceRoot 'ROADMAP.md') -Raw
    $gLive = Test-RoadmapAgentReadiness -Content $liveRoadmap -RepoPath $WorkspaceRoot -MaturityLevel 4
    Assert (-not ($gLive.blockers -contains 'missing-protocol-columns')) "live ROADMAP.md -> phase-plan tables carry protocol columns [dogfood]"
    Write-Host ("    live ROADMAP eligible=$($gLive.eligible) blockers: [" + ($gLive.blockers -join ', ') + ']') -ForegroundColor DarkGray
}
finally {
    Remove-Item -LiteralPath $scratchRepo -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host "==== PhaseProtocol: $script:Pass passed, $script:Fail failed ====" -ForegroundColor $(if ($script:Fail -eq 0) { 'Green' } else { 'Red' })
if ($script:Fail -gt 0) { exit 1 }
