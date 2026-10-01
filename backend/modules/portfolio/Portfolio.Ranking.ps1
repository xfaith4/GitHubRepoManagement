<#
.SYNOPSIS
    Release 4.0 phase A - one ranking for Today and the Dispatch Board.
.DESCRIPTION
    Today ranked the operations index in the browser
    (frontend/lib/todayRanking.ts) while the Dispatch Board sorted the
    execution ledger by `priorityScore` (roadmap maturity plus a readiness
    bonus). The two scales had nothing in common, and one repository read #1 on
    Today and #8 on the board.

    This file is now the only ranking. `Get-OperationsReposPayload` attaches a
    `ranking` object to every entry, and `Get-ExecutionQueueSummary` orders the
    board by the same rank, so the number beside a repository is the same
    number on both screens. The frontend renders the rank; it computes none.

    The keys, in order: what the product concluded, what the operator curated,
    whether a next action is offered, readiness for unattended work (measured
    beats unmeasured), foundation gaps, cheaper effort, then the name. No key
    ranks by business value: every repository in this portfolio is useful, so
    nothing here may order them by worth (operator correction, 2026-09-01).

    Pure: no clock, no randomness, no I/O. The same entries always give the
    same order. Param-less on purpose: the API host dot-sources this file, and
    a param() block here would overwrite the route's own variables.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function _PR_GetField {
    param([object]$Obj, [string]$Name, [object]$Default = $null)
    if ($null -eq $Obj) { return $Default }
    if ($Obj -is [System.Collections.IDictionary]) {
        if ($Obj.Contains($Name)) { return $Obj[$Name] }
        return $Default
    }
    if ($null -eq $Obj.PSObject) { return $Default }
    foreach ($prop in $Obj.PSObject.Properties) { if ($prop.Name -eq $Name) { return $prop.Value } }
    return $Default
}

function _PR_SetField {
    param([object]$Obj, [string]$Name, [object]$Value)
    if ($Obj -is [System.Collections.IDictionary]) { $Obj[$Name] = $Value; return }
    $Obj | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
}

function _PR_IsNumber {
    param([object]$Value)
    if ($null -eq $Value -or $Value -is [bool] -or $Value -is [string]) { return $false }
    try { $d = [double]$Value } catch { return $false }
    return -not ([double]::IsNaN($d) -or [double]::IsInfinity($d))
}

# Conclusion precedence. `strengthen` is actionable now; `insufficiently
# understood` is a gap in the product's own knowledge; `appropriate as-is` sinks
# but is never hidden.
#
# Functions rather than $script: tables, so the file behaves the same whether
# the host dot-sources it at script level or a smoke loads it inside a function.
function _PR_ConclusionRank {
    param([string]$Conclusion)
    switch ($Conclusion) {
        'strengthen' { return 0 }
        'insufficiently-understood' { return 1 }
        'appropriate-as-is' { return 2 }
        default { return 3 }
    }
}

# Curated repositories lead: the operator already said these matter.
function _PR_CurationRank {
    param([string]$Curation)
    switch ($Curation) {
        'favorite' { return 0 }
        'portfolio-candidate' { return 1 }
        'archived-ignore' { return 3 }
        default { return 2 }
    }
}

function _PR_CurationPhrase {
    param([string]$Curation)
    switch ($Curation) {
        'favorite' { return 'you marked it a favorite' }
        'portfolio-candidate' { return 'you marked it a portfolio candidate' }
        default { return "its curation is $Curation" }
    }
}

# Kept out of the source as literals so the file stays ASCII: Windows
# PowerShell 5.1 reads a BOM-less file as ANSI and would garble them.
function _PR_MiddleDot { return [string][char]0x00B7 }
function _PR_EmDash { return [string][char]0x2014 }

# ---------------------------------------------------------------------------
# Readiness for unattended work - four named checks, never a weighted score.
# An absent input is `unmeasured`, never a failure: a missing CI signal means
# nobody looked, not that CI is absent.
# ---------------------------------------------------------------------------

function _PR_Factor {
    param([string]$Key, [string]$Label, [string]$State, [string]$Detail)
    return [pscustomobject]@{ key = $Key; label = $Label; state = $State; detail = $Detail }
}

function Get-UnattendedReadiness {
    <#
    .SYNOPSIS
        Four checks, in the order an agent hits them: understand the repo,
        select the work, get a clean tree, prove the result.
    #>
    [CmdletBinding()]
    param([Parameter()][object]$Entry)

    $hasReadme = _PR_GetField -Obj $Entry -Name 'hasReadme'
    $hasRoadmap = _PR_GetField -Obj $Entry -Name 'hasRoadmap'
    $docs = if ($hasReadme -isnot [bool] -or $hasRoadmap -isnot [bool]) {
        _PR_Factor -Key 'docs' -Label 'Docs present' -State 'unmeasured' -Detail 'Nobody has checked whether a README and a ROADMAP exist here.'
    } elseif ($hasReadme -and $hasRoadmap) {
        _PR_Factor -Key 'docs' -Label 'Docs present' -State 'ready' -Detail 'A README states the purpose and a ROADMAP states the plan.'
    } else {
        $missing = @(@($(if (-not $hasReadme) { 'README.md' }), $(if (-not $hasRoadmap) { 'ROADMAP.md' })) | Where-Object { $_ }) -join ' and '
        _PR_Factor -Key 'docs' -Label 'Docs present' -State 'not-ready' -Detail "$missing is missing, so an agent has to ask what this repository is for."
    }

    $roadmapState = [string](_PR_GetField -Obj $Entry -Name 'roadmapState' -Default '')
    $roadmap = if ([string]::IsNullOrWhiteSpace($roadmapState)) {
        _PR_Factor -Key 'roadmap-machine-readable' -Label 'Roadmap machine-readable' -State 'unmeasured' -Detail 'The roadmap has not been parsed, so nobody knows whether work can be selected from it.'
    } elseif ($roadmapState -in @('pending', 'complete')) {
        _PR_Factor -Key 'roadmap-machine-readable' -Label 'Roadmap machine-readable' -State 'ready' -Detail 'Items can be selected and dispatched without a human reading the file.'
    } else {
        # 'no-checklist' is a SOUND document with no `- [ ]` items. It must never
        # be described as damaged - that wording sent operators to repair working files.
        $detail = switch ($roadmapState) {
            'no-checklist' { 'The roadmap is sound but records no "- [ ]" items, so there is nothing in it to dispatch.' }
            'missing' { 'There is no ROADMAP.md, so there is no plan to select work from.' }
            default { 'ROADMAP.md could not be parsed, so no item in it can be ranked or dispatched.' }
        }
        _PR_Factor -Key 'roadmap-machine-readable' -Label 'Roadmap machine-readable' -State 'not-ready' -Detail $detail
    }

    $dirty = _PR_GetField -Obj $Entry -Name 'localDirtyCount'
    $tree = if (-not (_PR_IsNumber $dirty)) {
        _PR_Factor -Key 'clean-tree' -Label 'Clean working tree' -State 'unmeasured' -Detail 'The working tree has not been read, so it cannot be called clean.'
    } elseif ([double]$dirty -eq 0) {
        _PR_Factor -Key 'clean-tree' -Label 'Clean working tree' -State 'ready' -Detail 'Nothing uncommitted stands between an agent and a dispatch.'
    } else {
        $n = [int]$dirty
        _PR_Factor -Key 'clean-tree' -Label 'Clean working tree' -State 'not-ready' -Detail ("{0} uncommitted {1} block dispatch." -f $n, $(if ($n -eq 1) { 'file' } else { 'files' }))
    }

    $hasCi = _PR_GetField -Obj $Entry -Name 'hasCiSignal'
    $ci = if ($hasCi -isnot [bool]) {
        _PR_Factor -Key 'ci' -Label 'CI present' -State 'unmeasured' -Detail 'Nobody has looked for a CI signal, so its absence is not established.'
    } elseif ($hasCi) {
        _PR_Factor -Key 'ci' -Label 'CI present' -State 'ready' -Detail 'A run can be judged green or red without a human looking at it.'
    } else {
        _PR_Factor -Key 'ci' -Label 'CI present' -State 'not-ready' -Detail 'No CI signal, so an unattended run has nothing to prove itself against.'
    }

    $factors = @($docs, $roadmap, $tree, $ci)
    $ready = @($factors | Where-Object { $_.state -eq 'ready' }).Count
    $unmeasured = @($factors | Where-Object { $_.state -eq 'unmeasured' })
    $measured = $factors.Count - $unmeasured.Count

    # The denominator is what was MEASURED, never the full four - "2 of 4" when
    # one check never ran reports an absence as a failure.
    $summary = "$ready of $measured ready"
    if ($unmeasured.Count -gt 0) {
        $summary += (' {0} ' -f (_PR_MiddleDot)) + (@($unmeasured | ForEach-Object { $_.label.ToLowerInvariant() }) -join ', ') + ' unmeasured'
    }
    if ($measured -eq 0) { $summary = 'unmeasured {0} no check has run for this repository' -f (_PR_EmDash) }

    return [pscustomobject]@{
        factors  = $factors
        ready    = $ready
        measured = $measured
        total    = $factors.Count
        summary  = $summary
    }
}

function Get-RankingEffort {
    <#
    .SYNOPSIS
        The human effort estimate, or "not estimated" - never a guessed one.
        Cheap work first is a tiebreak, not a ranking principle.
    #>
    [CmdletBinding()]
    param([Parameter()][object]$WorkUnits)

    if (-not (_PR_IsNumber $WorkUnits) -or [double]$WorkUnits -le 0) {
        return [pscustomobject]@{ workUnits = $null; label = 'Effort not estimated'; band = 'unknown' }
    }
    $units = [math]::Round([double]$WorkUnits * 10, [System.MidpointRounding]::AwayFromZero) / 10
    $text = $units.ToString([System.Globalization.CultureInfo]::InvariantCulture)
    $band = if ($units -le 3) { 'small' } elseif ($units -le 8) { 'medium' } else { 'large' }
    $label = if ($units -eq 1) { "$text work unit" } else { "$text work units" }
    return [pscustomobject]@{ workUnits = $units; label = $label; band = $band }
}

# ---------------------------------------------------------------------------
# The sort keys. One function per key so the comparison, the rank basis and
# the pin explanation all read the same value.
# ---------------------------------------------------------------------------

function _PR_Outcome { param([object]$Entry) return (_PR_GetField -Obj $Entry -Name 'outcome') }

function _PR_ConclusionOf {
    param([object]$Entry)
    $c = [string](_PR_GetField -Obj (_PR_Outcome $Entry) -Name 'conclusion' -Default '')
    if ($c -in @('strengthen', 'insufficiently-understood', 'appropriate-as-is')) { return $c }
    return 'unknown'
}

function _PR_CurationOf {
    param([object]$Entry)
    $c = [string](_PR_GetField -Obj $Entry -Name 'curationState' -Default 'none')
    if ([string]::IsNullOrWhiteSpace($c)) { return 'none' }
    return $c
}

function _PR_ActionRoute {
    param([object]$Entry)
    return ([string](_PR_GetField -Obj (_PR_Outcome $Entry) -Name 'nextActionRoute' -Default '')).Trim()
}

function _PR_Keys {
    param([object]$Entry)
    $readiness = Get-UnattendedReadiness -Entry $Entry
    $effort = Get-RankingEffort -WorkUnits (_PR_GetField -Obj $Entry -Name 'estimatedSessionWorkUnits')
    $gapCount = _PR_GetField -Obj (_PR_Outcome $Entry) -Name 'gapCount' -Default 0
    $curation = _PR_CurationOf $Entry
    $conclusion = _PR_ConclusionOf $Entry
    return [pscustomobject]@{
        conclusion     = $conclusion
        conclusionRank = _PR_ConclusionRank -Conclusion $conclusion
        curation       = $curation
        curationRank   = _PR_CurationRank -Curation $curation
        actionRank     = $(if (_PR_ActionRoute $Entry) { 0 } else { 1 })
        # Unmeasured sorts LAST among ties and is not zero: "we looked and an
        # agent cannot work here" is a stronger statement than "nobody looked".
        readinessRank  = $(if ($readiness.measured -eq 0) { -1 } else { $readiness.ready })
        gaps           = $(if (_PR_IsNumber $gapCount) { [int]$gapCount } else { 0 })
        effortUnits    = $(if ($null -eq $effort.workUnits) { [double]::MaxValue } else { [double]$effort.workUnits })
        name           = [string](_PR_GetField -Obj $Entry -Name 'repoName' -Default '')
        id             = [string](_PR_GetField -Obj $Entry -Name 'repoId' -Default '')
        readiness      = $readiness
        effort         = $effort
    }
}

function _PR_Compare {
    param([object]$A, [object]$B)
    if ($A.conclusionRank -ne $B.conclusionRank) { return $A.conclusionRank.CompareTo($B.conclusionRank) }
    if ($A.curationRank -ne $B.curationRank) { return $A.curationRank.CompareTo($B.curationRank) }
    if ($A.actionRank -ne $B.actionRank) { return $A.actionRank.CompareTo($B.actionRank) }
    if ($A.readinessRank -ne $B.readinessRank) { return $B.readinessRank.CompareTo($A.readinessRank) }
    if ($A.gaps -ne $B.gaps) { return $B.gaps.CompareTo($A.gaps) }
    if ($A.effortUnits -ne $B.effortUnits) { return $A.effortUnits.CompareTo($B.effortUnits) }
    # Ordinal, so the order is the same on every machine and culture.
    $byName = [System.StringComparer]::OrdinalIgnoreCase.Compare($A.name, $B.name)
    if ($byName -ne 0) { return $byName }
    return [System.StringComparer]::Ordinal.Compare($A.id, $B.id)
}

function _PR_RankBasis {
    param([object]$Entry, [object]$Keys)
    $basis = [System.Collections.Generic.List[string]]::new()
    $basis.Add("conclusion=$($Keys.conclusion)")
    if ($Keys.curation -ne 'none') { $basis.Add("curation=$($Keys.curation)") }
    if ($Keys.gaps -gt 0) {
        $domains = @(_PR_GetField -Obj (_PR_Outcome $Entry) -Name 'gapDomains' -Default @()) | ForEach-Object { [string]$_ }
        $basis.Add(('{0} foundation gap(s): {1}' -f $Keys.gaps, ($domains -join ', ')))
    }
    # Says what it measures in its own label: how many of the four
    # unattended-work checks pass, not a score out of anything.
    if ($Keys.readiness.measured -eq 0) {
        $basis.Add('unattendedReadiness=unmeasured')
    } else {
        $basis.Add(('unattendedReadiness={0}/{1} checks ready' -f $Keys.readiness.ready, $Keys.readiness.measured))
    }
    if ($null -ne $Keys.effort.workUnits) {
        $basis.Add('effort=' + ([double]$Keys.effort.workUnits).ToString([System.Globalization.CultureInfo]::InvariantCulture))
    }
    if (-not (_PR_ActionRoute $Entry)) { $basis.Add('no next action offered') }
    return $basis.ToArray()
}

function _PR_WhyNow {
    param([object]$Entry, [object]$Keys)
    $outcome = _PR_Outcome $Entry
    $reason = ([string](_PR_GetField -Obj $outcome -Name 'reason' -Default '')).Trim()
    if ($Keys.conclusion -eq 'unknown' -or -not $reason) {
        return 'Not yet concluded: this repository has no recorded outcome, so the product cannot say whether it needs work.'
    }
    $parts = @($reason)
    $value = _PR_GetField -Obj $Entry -Name 'topValueItem'
    $score = _PR_GetField -Obj $value -Name 'valueScore'
    if ($Keys.conclusion -eq 'strengthen' -and (_PR_IsNumber $score) -and [double]$score -gt 0) {
        $parts += ('Highest-value pending work scores {0} ({1}).' -f `
                ([double]$score).ToString([System.Globalization.CultureInfo]::InvariantCulture),
            [string](_PR_GetField -Obj $value -Name 'valueTier' -Default ''))
    }
    return ($parts -join ' ')
}

# Why `Pinned` sits above `Outranked`, which is readier for unattended work.
# Walks the same keys as _PR_Compare, in the same order, and reports the first
# one that decided it - so the explanation cannot drift from the ordering.
function _PR_ExplainPin {
    param([object]$Pinned, [object]$Outranked)
    if ($Pinned.conclusionRank -ne $Outranked.conclusionRank) {
        if ($Pinned.conclusion -eq 'strengthen') {
            return 'Ranked above a repository that is readier for unattended work because this one has a specific next step and that one does not.'
        }
        return ('Ranked above a repository that is readier for unattended work because its conclusion is "{0}".' -f $Pinned.conclusion)
    }
    if ($Pinned.curationRank -ne $Outranked.curationRank) {
        $phrase = _PR_CurationPhrase -Curation $Pinned.curation
        return "Ranked above a repository that is readier for unattended work because $phrase."
    }
    if ($Pinned.actionRank -ne $Outranked.actionRank) {
        return 'Ranked above a repository that is readier for unattended work because it offers an action to take and that one does not.'
    }
    return $null
}

function Add-PortfolioRanking {
    <#
    .SYNOPSIS
        Rank the portfolio once, attach a `ranking` object to every entry, and
        return the entries in rank order.
    .DESCRIPTION
        `ranking` carries rank (1-based), scale ('portfolio' - one scale for
        every screen), basis (the ordered signals behind the rank, most
        significant first), whyNow, pinReason (set only when the row sits above
        a repository that is readier for unattended work), readiness and
        effort. Pure and in-memory.
    #>
    [CmdletBinding()]
    [OutputType([System.Object[]])]
    param([Parameter()][AllowEmptyCollection()][object[]]$Entries = @())

    $keyed = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in @($Entries)) {
        if ($null -eq $entry) { continue }
        if ([string]::IsNullOrWhiteSpace([string](_PR_GetField -Obj $entry -Name 'repoId' -Default ''))) { continue }
        $keyed.Add([pscustomobject]@{ entry = $entry; keys = (_PR_Keys $entry) })
    }
    $keyed.Sort([System.Comparison[object]] { param($a, $b) _PR_Compare -A $a.keys -B $b.keys })

    $ordered = $keyed.ToArray()
    for ($i = 0; $i -lt $ordered.Count; $i++) {
        $item = $ordered[$i]
        $pinReason = $null
        # The first row below this one that is READIER is the row this position
        # has to justify itself against. Unmeasured never triggers one.
        for ($j = $i + 1; $j -lt $ordered.Count; $j++) {
            if ($ordered[$j].keys.readinessRank -gt $item.keys.readinessRank) {
                $pinReason = _PR_ExplainPin -Pinned $item.keys -Outranked $ordered[$j].keys
                break
            }
        }
        _PR_SetField -Obj $item.entry -Name 'ranking' -Value ([pscustomobject]@{
                rank      = $i + 1
                scale     = 'portfolio'
                basis     = @(_PR_RankBasis -Entry $item.entry -Keys $item.keys)
                whyNow    = _PR_WhyNow -Entry $item.entry -Keys $item.keys
                pinReason = $pinReason
                readiness = $item.keys.readiness
                effort    = $item.keys.effort
            })
    }
    return @($ordered | ForEach-Object { $_.entry })
}

function _PR_NormalizePath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
    return ($Path.Trim() -replace '/', '\').TrimEnd('\').ToLowerInvariant()
}

function Add-QueueRanking {
    <#
    .SYNOPSIS
        Put the portfolio rank on execution-ledger entries and return them in
        that order, so the Dispatch Board reads the same #n as Today.
    .DESCRIPTION
        Matches a ledger entry to a ranked portfolio entry by local path first,
        then by repository name when exactly one indexed repository carries
        it. An entry with no match has `portfolioRank` $null and a `rankNote`
        saying why, and sorts after every ranked entry, by name. The ranking is
        derived on read and never written to the ledger.
    #>
    [CmdletBinding()]
    [OutputType([System.Object[]])]
    param(
        [Parameter()][AllowEmptyCollection()][object[]]$QueueEntries = @(),
        [Parameter()][AllowEmptyCollection()][object[]]$RankedEntries = @()
    )

    $byPath = @{}
    $byName = @{}
    foreach ($ranked in @($RankedEntries)) {
        $ranking = _PR_GetField -Obj $ranked -Name 'ranking'
        if ($null -eq $ranking) { continue }
        $path = _PR_NormalizePath ([string](_PR_GetField -Obj $ranked -Name 'localPath' -Default ''))
        if ($path) { $byPath[$path] = $ranking }
        $name = ([string](_PR_GetField -Obj $ranked -Name 'repoName' -Default '')).ToLowerInvariant()
        if ($name) {
            if ($byName.ContainsKey($name)) { $byName[$name] = 'ambiguous' } else { $byName[$name] = $ranking }
        }
    }

    $rankedRows = [System.Collections.Generic.List[object]]::new()
    $unrankedRows = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in @($QueueEntries)) {
        if ($null -eq $entry) { continue }
        $path = _PR_NormalizePath ([string](_PR_GetField -Obj $entry -Name 'repoPath' -Default ''))
        $name = ([string](_PR_GetField -Obj $entry -Name 'repoName' -Default '')).ToLowerInvariant()
        $ranking = $null
        $note = $null
        if ($path -and $byPath.ContainsKey($path)) {
            $ranking = $byPath[$path]
        } elseif ($name -and $byName.ContainsKey($name)) {
            if ($byName[$name] -is [string]) {
                $note = 'Two indexed repositories share this name and the ledger records no path that tells them apart, so it has no rank.'
            } else {
                $ranking = $byName[$name]
            }
        } else {
            $note = 'Not in the portfolio index, so it has no rank on Today or here.'
        }

        if ($null -ne $ranking) {
            _PR_SetField -Obj $entry -Name 'portfolioRank' -Value ([int]$ranking.rank)
            _PR_SetField -Obj $entry -Name 'rankBasis' -Value @($ranking.basis)
            _PR_SetField -Obj $entry -Name 'rankNote' -Value $null
            $rankedRows.Add($entry)
        } else {
            _PR_SetField -Obj $entry -Name 'portfolioRank' -Value $null
            _PR_SetField -Obj $entry -Name 'rankBasis' -Value @()
            _PR_SetField -Obj $entry -Name 'rankNote' -Value $note
            $unrankedRows.Add($entry)
        }
    }

    $rankedRows.Sort([System.Comparison[object]] {
            param($a, $b)
            ([int](_PR_GetField -Obj $a -Name 'portfolioRank')).CompareTo([int](_PR_GetField -Obj $b -Name 'portfolioRank'))
        })
    $unrankedRows.Sort([System.Comparison[object]] {
            param($a, $b)
            [System.StringComparer]::OrdinalIgnoreCase.Compare([string](_PR_GetField -Obj $a -Name 'repoName' -Default ''), [string](_PR_GetField -Obj $b -Name 'repoName' -Default ''))
        })
    return @($rankedRows.ToArray()) + @($unrankedRows.ToArray())
}
