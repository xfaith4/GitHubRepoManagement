<#
.SYNOPSIS
    Record that an operator has verified a smoke-tested surface end-to-end.

.DESCRIPTION
    Appends one record to the append-only evidence/operator-verification-log.jsonl.
    This is the durable, decision-grade trail the CLAUDE.md rule wants — "never
    mark a phase complete without an evidence note naming the test or artifact
    that proves it." The daily driver (Invoke-DailyEvidence.ps1) reads this log
    to shrink its verify-next queue.

    The SurfaceId is the short id shown in the driver's verify-queue.md (a stable
    hash of release + surface text). This script recomputes ROADMAP ids to
    resolve the surface and REFUSES an unknown id, so a typo can't silently log
    a verification against nothing.

.PARAMETER SurfaceId
    The surface id from verify-queue.md (e.g. "a1b2c3d4e5").

.PARAMETER Evidence
    What you actually observed or the artifact that proves it (route + response,
    screenshot path, log line, evidence snapshot path). Required — a verification
    without evidence is exactly the vacuous pass this whole system exists to stop.

.PARAMETER State
    The state you are promoting the surface to. Default 'operator-verified'.

.PARAMETER VerifiedBy
    Who verified it. Defaults to the current user.

.PARAMETER List
    Print the current smoke-tested surfaces (id + release + text) and exit,
    without recording anything.

.EXAMPLE
    pwsh -File scripts/Add-OperatorVerification.ps1 -List

.EXAMPLE
    pwsh -File scripts/Add-OperatorVerification.ps1 -SurfaceId a1b2c3d4e5 `
      -Evidence "Drove Refresh All in the grid; POST /api/portfolio/assessment/refresh-all returned reused=0 reindexed=68; curation survived. host.log 14:22."
#>
[CmdletBinding(DefaultParameterSetName = 'Record')]
param(
    [string]$WorkspaceRoot,

    [Parameter(ParameterSetName = 'Record', Mandatory = $true)]
    [string]$SurfaceId,

    [Parameter(ParameterSetName = 'Record', Mandatory = $true)]
    [string]$Evidence,

    [Parameter(ParameterSetName = 'Record')]
    [string]$State = 'operator-verified',

    [Parameter(ParameterSetName = 'Record')]
    [string]$VerifiedBy = $env:USERNAME,

    [Parameter(ParameterSetName = 'List', Mandatory = $true)]
    [switch]$List
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($WorkspaceRoot)) {
    $WorkspaceRoot = Split-Path -Parent $PSScriptRoot
}
$WorkspaceRoot = (Resolve-Path -LiteralPath $WorkspaceRoot).Path

function Get-RoadmapSurfaces {
    # Must mirror Invoke-DailyEvidence.ps1's Get-RoadmapSurfaces id derivation
    # EXACTLY, or ids will not match the verify queue. The *(state: ...)* marker
    # usually sits on a wrapped continuation line, so item text is accumulated
    # across continuation lines; fenced code blocks are skipped so the section-3
    # vocabulary example is not treated as a real milestone.
    param([string]$RoadmapPath)
    $surfaces = [System.Collections.Generic.List[object]]::new()
    if (-not (Test-Path -LiteralPath $RoadmapPath)) { return $surfaces.ToArray() }
    $sha1 = [System.Security.Cryptography.SHA1]::Create()
    $inFence = $false
    $release = '(preamble)'
    $pendingText = $null
    $pendingChecked = $false
    $pendingRelease = $release
    foreach ($line in (Get-Content -LiteralPath $RoadmapPath -Encoding UTF8)) {
        if ($line -match '^\s*```') { $inFence = -not $inFence; $pendingText = $null; continue }
        if ($inFence) { continue }
        $headMatch = [regex]::Match($line, '^(#{2,4})\s+(.+?)\s*$')
        if ($headMatch.Success) {
            # Only ## and ### define the release/section; #### subheadings
            # ("Engineering milestones", "Phase plan") sit WITHIN a release and
            # must not overwrite its context.
            if ($headMatch.Groups[1].Value.Length -le 3) {
                $h = $headMatch.Groups[2].Value.Trim()
                $rel = [regex]::Match($h, '^Release\s+(.+)$')
                $release = if ($rel.Success) { $rel.Groups[1].Value.Trim() } else { $h }
            }
            $pendingText = $null
            continue
        }
        $cb = [regex]::Match($line, '^\s*-\s*\[([ xX])\]\s*(.*)$')
        if ($cb.Success) {
            $pendingChecked = ($cb.Groups[1].Value -match '[xX]')
            $pendingRelease = $release
            $pendingText = $cb.Groups[2].Value
        }
        elseif ($null -ne $pendingText -and $line -match '^\s+\S') {
            $pendingText = ($pendingText + ' ' + $line.Trim())
        }
        else {
            $pendingText = $null
        }

        if ($null -ne $pendingText) {
            $sm = [regex]::Match($pendingText, '\*\(state:\s*([a-z][a-z-]*)')
            if ($sm.Success) {
                $state = $sm.Groups[1].Value
                $text = ($pendingText -replace '\s*\*\(state:.*$', '').Trim()
                if (-not [string]::IsNullOrWhiteSpace($text)) {
                    $norm = ($text.ToLowerInvariant() -replace '\s+', ' ')
                    $idBytes = $sha1.ComputeHash([System.Text.Encoding]::UTF8.GetBytes(("{0}||{1}" -f $pendingRelease, $norm)))
                    $id = -join ($idBytes[0..4] | ForEach-Object { $_.ToString('x2') })
                    $surfaces.Add([pscustomobject]@{ id = $id; release = $pendingRelease; state = $state; checked = $pendingChecked; text = $text })
                }
                $pendingText = $null
            }
        }
    }
    $sha1.Dispose()
    return $surfaces.ToArray()
}

$roadmapPath = Join-Path $WorkspaceRoot 'ROADMAP.md'
$surfaces = @(Get-RoadmapSurfaces -RoadmapPath $roadmapPath)

if ($List) {
    $smoke = @($surfaces | Where-Object { $_.state -eq 'smoke-tested' })
    Write-Host ("{0} surface(s) at smoke-tested:" -f $smoke.Count) -ForegroundColor Cyan
    foreach ($s in $smoke) {
        Write-Host ("  [{0}] {1} — {2}" -f $s.id, $s.release, $s.text) -ForegroundColor Gray
    }
    exit 0
}

$match = $surfaces | Where-Object { $_.id -eq $SurfaceId } | Select-Object -First 1
if (-not $match) {
    Write-Host ("[FAIL] Surface id '{0}' not found in ROADMAP.md. Run with -List to see valid ids." -f $SurfaceId) -ForegroundColor Red
    exit 1
}

$logPath = Join-Path $WorkspaceRoot 'evidence\operator-verification-log.jsonl'
$null = New-Item -ItemType Directory -Path (Split-Path -Parent $logPath) -Force

$sha = $null
try { $sha = (& git -C $WorkspaceRoot rev-parse --short HEAD 2>$null).Trim() } catch { }

$record = [ordered]@{
    timestamp = (Get-Date).ToString('o')
    surfaceId = $match.id
    release = $match.release
    surface = $match.text
    roadmapState = $match.state
    promotedTo = $State
    evidence = $Evidence
    verifiedBy = $VerifiedBy
    gitSha = $sha
}
$json = $record | ConvertTo-Json -Depth 5 -Compress
Add-Content -LiteralPath $logPath -Value $json -Encoding UTF8

Write-Host '[PASS] Verification recorded' -ForegroundColor Green
Write-Host ("  {0} — {1}" -f $match.release, $match.text) -ForegroundColor DarkGray
Write-Host ("  {0} -> {1} by {2}" -f $match.state, $State, $VerifiedBy) -ForegroundColor DarkGray
Write-Host ("  logged to {0}" -f $logPath) -ForegroundColor DarkGray
if ($match.state -ne 'smoke-tested') {
    Write-Host ("  note: ROADMAP still shows this at '{0}'. Update its inline *(state: ...)* to '{1}' to keep the roadmap and the log in sync." -f $match.state, $State) -ForegroundColor Yellow
}
exit 0
