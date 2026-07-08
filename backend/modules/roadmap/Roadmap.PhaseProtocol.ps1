<#
.SYNOPSIS
    Phase-plan protocol layer for the execution orchestrator (P0).
.DESCRIPTION
    The `### Phase plan` / `#### Phase plan` table is the machine-readable contract
    the worker and governor read (via Roadmap.Parser.ps1) and write. This module
    adds the two write/gate halves of that protocol:

      Set-RoadmapPhaseState     — surgically update a phase row's Status / Completed
                                  / Token usage cells, preserving the rest of the
                                  file (line- and EOL-preserving).
      Test-RoadmapAgentReadiness — decide whether a repo's roadmap is agent-eligible:
                                  parseable releases + a phase-plan table carrying the
                                  full protocol columns + maturity >= L3 + a real
                                  validation signal (CI workflows). Anything short is
                                  routed back to readiness/repair, never dispatched.

    Heading-level tolerant to match Roadmap.Parser.ps1 (releases at ##+, phase-plan
    headings at ###+). PowerShell 5.1 compatible.

.NOTES
    Dot-source alongside Roadmap.Parser.ps1 (Test-RoadmapAgentReadiness calls
    Get-RoadmapReleaseContexts):
        . (Join-Path $moduleRoot 'Roadmap.Parser.ps1')
        . (Join-Path $moduleRoot 'Roadmap.PhaseProtocol.ps1')
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function _PhaseProtocolDetectEol {
    param([string]$Content)
    if ($Content -match "`r`n") { return "`r`n" }
    return "`n"
}

function _PhaseProtocolNormalizeCell {
    param([string]$Value)
    return (([string]$Value).Trim().ToLowerInvariant() -replace '\s+', ' ')
}

function _PhaseProtocolTableCells {
    # Mirrors Roadmap.Parser's cell split: trim outer pipes, split on '|', trim each.
    param([string]$Line)
    $trimmed = ([string]$Line).Trim()
    if (-not $trimmed.StartsWith('|')) { return @() }
    $trimmed = $trimmed.Trim('|')
    return @(($trimmed -split '\|') | ForEach-Object { ([string]$_).Trim() })
}

function _PhaseProtocolColIndex {
    param([string[]]$NormHeaders, [string]$Pattern)
    for ($k = 0; $k -lt $NormHeaders.Count; $k++) {
        if ($NormHeaders[$k] -match $Pattern) { return $k }
    }
    return -1
}

function _PhaseProtocolFindPhasePlanTables {
    # Locate every phase-plan table with absolute line indices + a column map, and
    # the release version it sits under. Uses the same heading tolerance and column
    # detection as Roadmap.Parser so read and write agree on structure.
    param([string[]]$Lines)

    $tables = [System.Collections.Generic.List[object]]::new()
    $currentRelease = ''
    $i = 0
    while ($i -lt $Lines.Count) {
        $line = [string]$Lines[$i]

        $relMatch = [regex]::Match($line, '(?i)^#{2,}\s+Release\s+(\d+[\d\.]*)\s*[—–-]+\s*(.+?)\s*$')
        if ($relMatch.Success) {
            $currentRelease = $relMatch.Groups[1].Value.Trim()
            $i++
            continue
        }

        if ($line -match '^\s*#{3,}\s+Phase\s+plan\b') {
            $tableIdx = [System.Collections.Generic.List[int]]::new()
            $j = $i + 1
            while ($j -lt $Lines.Count) {
                $tl = ([string]$Lines[$j]).TrimEnd()
                if ([string]::IsNullOrWhiteSpace($tl)) {
                    if ($tableIdx.Count -gt 0) { break } else { $j++; continue }
                }
                if ($tl -match '^\s*#{1,6}\s+') { break }
                if ($tl -notmatch '^\s*\|') {
                    if ($tableIdx.Count -gt 0) { break } else { $j++; continue }
                }
                $tableIdx.Add($j) | Out-Null
                $j++
            }

            if ($tableIdx.Count -ge 3) {
                $sep = [string]$Lines[$tableIdx[1]]
                if ($sep -match '^\s*\|[\s:\-|]+\|\s*$') {
                    $headers = @(_PhaseProtocolTableCells -Line $Lines[$tableIdx[0]])
                    $norm = @($headers | ForEach-Object { _PhaseProtocolNormalizeCell $_ })
                    $colmap = @{
                        phase      = (_PhaseProtocolColIndex -NormHeaders $norm -Pattern '^phase\b')
                        scope      = (_PhaseProtocolColIndex -NormHeaders $norm -Pattern '^scope\b')
                        status     = (_PhaseProtocolColIndex -NormHeaders $norm -Pattern '^status\b')
                        completed  = (_PhaseProtocolColIndex -NormHeaders $norm -Pattern '^completed\b')
                        tokenUsage = (_PhaseProtocolColIndex -NormHeaders $norm -Pattern '^token usage\b')
                        workUnits  = (_PhaseProtocolColIndex -NormHeaders $norm -Pattern '^work units\b')
                    }
                    if ($colmap.phase -ge 0 -and $colmap.scope -ge 0 -and $colmap.status -ge 0) {
                        $tables.Add([pscustomobject]@{
                            releaseVersion = $currentRelease
                            headerIndex    = $tableIdx[0]
                            separatorIndex = $tableIdx[1]
                            rowIndices     = @($tableIdx | Select-Object -Skip 2)
                            headerCount    = $headers.Count
                            colmap         = $colmap
                        }) | Out-Null
                    }
                }
            }

            $i = $j
            continue
        }

        $i++
    }

    return @($tables)
}

function Set-RoadmapPhaseState {
    <#
    .SYNOPSIS
        Update one phase row's Status / Completed / Token usage cells in a roadmap.
    .DESCRIPTION
        Returns a result object; the original content is returned unchanged on any
        failure so the caller can decide what to do. The edited row is re-rendered
        with normalized single-space cell padding; all other bytes are preserved,
        including the file's line-ending style.
    .PARAMETER PhaseName
        Exact phase name to match (as returned by the parser's phasePlan rows).
    .PARAMETER ReleaseVersion
        Optional scope. Required only to disambiguate when the same phase name
        appears in more than one release's phase plan.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Content,
        [Parameter(Mandatory = $true)][string]$PhaseName,
        [string]$ReleaseVersion = '',
        [string]$Status,
        [string]$Completed,
        [string]$TokenUsage
    )

    function _Fail([string]$reason) {
        return [pscustomobject]@{
            success = $false; changed = $false; content = $Content
            matchedRelease = ''; matchedPhase = ''; reason = $reason
        }
    }

    $eol = _PhaseProtocolDetectEol -Content $Content
    $lines = [System.Collections.Generic.List[string]]::new()
    foreach ($l in ($Content -split '\r?\n')) { $lines.Add([string]$l) | Out-Null }

    $tables = @(_PhaseProtocolFindPhasePlanTables -Lines $lines.ToArray())
    if (-not [string]::IsNullOrWhiteSpace($ReleaseVersion)) {
        $tables = @($tables | Where-Object { $_.releaseVersion -eq $ReleaseVersion })
    }
    if ($tables.Count -eq 0) { return (_Fail 'no-phase-plan-table') }

    $wantPhase = _PhaseProtocolNormalizeCell -Value $PhaseName
    $matchTable = $null
    $matchRowIdx = -1
    $matchCount = 0
    foreach ($t in $tables) {
        foreach ($ri in $t.rowIndices) {
            $cells = @(_PhaseProtocolTableCells -Line $lines[$ri])
            if ($t.colmap.phase -ge $cells.Count) { continue }
            if ((_PhaseProtocolNormalizeCell -Value $cells[$t.colmap.phase]) -eq $wantPhase) {
                $matchCount++
                $matchTable = $t
                $matchRowIdx = $ri
            }
        }
    }
    if ($matchCount -eq 0) { return (_Fail 'phase-not-found') }
    if ($matchCount -gt 1) { return (_Fail 'ambiguous-phase-specify-release') }

    $updates = @{}
    if ($PSBoundParameters.ContainsKey('Status')) {
        if ($matchTable.colmap.status -lt 0) { return (_Fail 'no-status-column') }
        $updates[$matchTable.colmap.status] = $Status
    }
    if ($PSBoundParameters.ContainsKey('Completed')) {
        if ($matchTable.colmap.completed -lt 0) { return (_Fail 'no-completed-column') }
        $updates[$matchTable.colmap.completed] = $Completed
    }
    if ($PSBoundParameters.ContainsKey('TokenUsage')) {
        if ($matchTable.colmap.tokenUsage -lt 0) { return (_Fail 'no-tokenusage-column') }
        $updates[$matchTable.colmap.tokenUsage] = $TokenUsage
    }
    if ($updates.Count -eq 0) { return (_Fail 'no-updates-requested') }

    $cells = @(_PhaseProtocolTableCells -Line $lines[$matchRowIdx])
    $cellList = [System.Collections.Generic.List[string]]::new()
    foreach ($c in $cells) { $cellList.Add([string]$c) | Out-Null }
    while ($cellList.Count -lt $matchTable.headerCount) { $cellList.Add('') | Out-Null }
    foreach ($k in $updates.Keys) { $cellList[$k] = [string]$updates[$k] }

    $newRow = '| ' + (($cellList.ToArray()) -join ' | ') + ' |'
    $changed = ($newRow -ne [string]$lines[$matchRowIdx])
    $lines[$matchRowIdx] = $newRow

    return [pscustomobject]@{
        success        = $true
        changed        = $changed
        content        = ($lines.ToArray() -join $eol)
        matchedRelease = $matchTable.releaseVersion
        matchedPhase   = $PhaseName
        reason         = ''
    }
}

function Test-RoadmapAgentReadiness {
    <#
    .SYNOPSIS
        Decide whether a repo's roadmap is agent-eligible for execution dispatch.
    .DESCRIPTION
        Eligible only when ALL hold: parseable releases; a phase-plan table with the
        full protocol columns (Status + Completed + Token usage + Work units);
        maturity >= MinMaturityLevel (default L3); and a validation signal (CI
        workflow files under .github/workflows). Missing inputs (maturity/repo path)
        are treated as blockers — the orchestrator supplies them; the gate never
        assumes a repo is safe to auto-merge.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Content,
        [string]$RepoPath = '',
        [object]$MaturityLevel = $null,
        [int]$MinMaturityLevel = 3
    )

    $blockers = [System.Collections.Generic.List[string]]::new()

    $ctx = @(Get-RoadmapReleaseContexts -RoadmapContent $Content)
    if ($ctx.Count -eq 0) { $blockers.Add('no-releases') | Out-Null }

    $withPlan = @($ctx | Where-Object { @($_.phasePlan).Count -gt 0 })
    if ($withPlan.Count -eq 0) { $blockers.Add('no-phase-plan') | Out-Null }

    $lines = @($Content -split '\r?\n')
    $tables = @(_PhaseProtocolFindPhasePlanTables -Lines $lines)
    $conforming = @($tables | Where-Object {
            $_.colmap.status -ge 0 -and $_.colmap.completed -ge 0 -and
            $_.colmap.tokenUsage -ge 0 -and $_.colmap.workUnits -ge 0
        })
    if ($conforming.Count -eq 0) { $blockers.Add('missing-protocol-columns') | Out-Null }

    $maturityResolved = $null
    if ($null -eq $MaturityLevel) {
        $blockers.Add('maturity-unknown') | Out-Null
    }
    else {
        $maturityResolved = [int]$MaturityLevel
        if ($maturityResolved -lt $MinMaturityLevel) { $blockers.Add('below-min-maturity') | Out-Null }
    }

    $hasValidationSignal = $null
    if ([string]::IsNullOrWhiteSpace($RepoPath)) {
        $blockers.Add('validation-signal-unknown') | Out-Null
    }
    else {
        $hasValidationSignal = $false
        $workflowDir = Join-Path $RepoPath '.github/workflows'
        if (Test-Path -LiteralPath $workflowDir) {
            $wf = @(Get-ChildItem -LiteralPath $workflowDir -File -ErrorAction SilentlyContinue |
                    Where-Object { $_.Extension -in @('.yml', '.yaml') })
            $hasValidationSignal = ($wf.Count -gt 0)
        }
        if (-not $hasValidationSignal) { $blockers.Add('no-validation-signal') | Out-Null }
    }

    return [pscustomobject]@{
        eligible = ($blockers.Count -eq 0)
        blockers = @($blockers.ToArray())
        checks   = [pscustomobject]@{
            releaseCount         = $ctx.Count
            phasePlanReleaseCount = $withPlan.Count
            conformingTableCount = $conforming.Count
            hasProtocolColumns   = ($conforming.Count -gt 0)
            maturityLevel        = $maturityResolved
            minMaturityLevel     = $MinMaturityLevel
            hasValidationSignal  = $hasValidationSignal
        }
    }
}
