# ---------------------------------------------------------------------------
# Current focus - "At least ten repositories legitimately ready for automated
# work": one readiness rule, and every hold on a repository named.
#
# Ready means what the roadmap item says it means: the dispatch-eligibility
# rule passes (Lane 0.22) and the repository carries an actionable item with
# acceptance criteria and a runnable check. Concretely, every one of these is
# a recorded fact on the portfolio index entry:
#
#   - the lifecycle resolver reads ready-for-work (README, roadmap, a
#     sufficient execution contract - goal, pending work, out of scope,
#     acceptance criteria, a runnable check, sizing - and no structure hold);
#   - Get-DispatchEligibility answers ok (indexed, not curated out, a clean
#     working tree, not blocked in the execution ledger);
#   - the assessment selected a top dispatchable item: an actionable line an
#     agent, not the operator, can perform;
#   - the repository has a GitHub remote, because the delivery loop ends in a
#     pull request and a local-only folder cannot receive one.
#
# The lifecycle resolver stops at the first hold. This rule does not: it
# lists every hold independently, so the census can say which repositories
# are one fix from ready and which need four. It loosens nothing - a
# repository is ready only when the lifecycle resolver also says so.
#
# Pure: no I/O. Needs Portfolio.Ranking.ps1 (_PR_* helpers) and
# Execution.Eligibility.ps1 loaded first.
# ---------------------------------------------------------------------------

$script:RepositoryReadinessModelVersion = '1.0'

function _RR_Hold {
    param([string]$Code, [string]$Label, [string]$Detail)
    [pscustomobject]@{ code = $Code; label = $Label; detail = $Detail }
}

function Get-RepositoryReadiness {
    <#
    .SYNOPSIS
        { ready, holds[] } for one portfolio index entry.
    .DESCRIPTION
        holds[] is a list of { code, label, detail }, every hold that applies,
        in a fixed order. ready is true only when holds[] is empty. Codes:
        archived, no-readme, no-roadmap, no-checklist, parse-error, running,
        contract-gap, no-pending-work, structure, doc-readiness,
        uncommitted-changes, blocked, item-quality-unmeasured,
        no-actionable-item, no-github-remote, lifecycle. $LedgerEntry is the repository's execution-ledger entry
        when one exists; without it the ledger cannot hold the repository.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$PortfolioEntry,
        [Parameter()][object]$LedgerEntry = $null
    )

    $e = $PortfolioEntry
    $holds = [System.Collections.Generic.List[object]]::new()
    $lifecycle = [string](_PR_GetField -Obj $e -Name 'lifecycleState' -Default '')
    $roadmapState = [string](_PR_GetField -Obj $e -Name 'roadmapState' -Default '')
    $hasRoadmap = [bool](_PR_GetField -Obj $e -Name 'hasRoadmap' -Default $false)
    $pending = _PR_GetField -Obj $e -Name 'pendingItemCount' -Default 0
    $pendingCount = if (_PR_IsNumber $pending) { [int]$pending } else { 0 }

    if ([string](_PR_GetField -Obj $e -Name 'curationState' -Default 'none') -eq 'archived-ignore' -or [bool](_PR_GetField -Obj $e -Name 'isArchived' -Default $false)) {
        $holds.Add((_RR_Hold -Code 'archived' -Label 'Archived or curated out' -Detail 'The owner curated this repository out, or it is archived; nothing is dispatched to it.'))
    }
    if (-not [bool](_PR_GetField -Obj $e -Name 'hasReadme' -Default $false)) {
        $holds.Add((_RR_Hold -Code 'no-readme' -Label 'No README' -Detail 'README.md is missing.'))
    }
    if (-not $hasRoadmap) {
        $holds.Add((_RR_Hold -Code 'no-roadmap' -Label 'No roadmap' -Detail 'No ROADMAP.md was found, so there is no planned work to take.'))
    }
    elseif ($roadmapState -eq 'no-checklist') {
        $holds.Add((_RR_Hold -Code 'no-checklist' -Label 'Prose roadmap' -Detail 'The roadmap records no "- [ ]" checklist items, so there is no unit of work to take.'))
    }
    elseif ($roadmapState -eq 'parse-error') {
        $holds.Add((_RR_Hold -Code 'parse-error' -Label 'Roadmap does not parse' -Detail 'The roadmap could not be parsed.'))
    }
    if ([string](_PR_GetField -Obj $e -Name 'executionState' -Default '') -eq 'running') {
        $holds.Add((_RR_Hold -Code 'running' -Label 'Run in flight' -Detail 'An agent run is already recorded as running here.'))
    }

    if ($hasRoadmap -and $roadmapState -notin @('no-checklist', 'parse-error')) {
        $contract = _PR_GetField -Obj $e -Name 'executionContract' -Default $null
        if (-not [bool](_PR_GetField -Obj $contract -Name 'sufficient' -Default $false) -and $roadmapState -ne 'complete') {
            $failed = @(@(_PR_GetField -Obj $contract -Name 'checks' -Default @()) | Where-Object { $null -ne $_ -and -not [bool](_PR_GetField -Obj $_ -Name 'passed' -Default $false) } |
                    ForEach-Object { [string](_PR_GetField -Obj $_ -Name 'explanation' -Default '') } | Where-Object { $_ })
            $detail = if ($failed.Count -gt 0) { $failed -join ' ' } else { [string](_PR_GetField -Obj $contract -Name 'explanation' -Default 'Execution-contract sufficiency could not be established.') }
            $holds.Add((_RR_Hold -Code 'contract-gap' -Label 'Execution contract incomplete' -Detail $detail))
        }
        if ($pendingCount -le 0) {
            $holds.Add((_RR_Hold -Code 'no-pending-work' -Label 'No pending work' -Detail 'The roadmap has no pending item.'))
        }
    }

    # Same selection as _ResolveLifecycleState: critical or warning, README aside.
    $struct = @(@(_PR_GetField -Obj $e -Name 'structureFindings' -Default @()) | Where-Object {
            $null -ne $_ -and [string](_PR_GetField -Obj $_ -Name 'severity' -Default '') -in @('critical', 'warning') -and [string](_PR_GetField -Obj $_ -Name 'target' -Default '') -ne 'README.md'
        })
    if ($struct.Count -gt 0) {
        $holds.Add((_RR_Hold -Code 'structure' -Label 'Structure findings' -Detail ('Missing {0}.' -f (@($struct | ForEach-Object { '{0} ({1})' -f $_.target, $_.severity }) -join ', '))))
    }
    $docReadiness = [string](_PR_GetField -Obj $e -Name 'dispatchReadiness' -Default '')
    if ($docReadiness -in @('needs-doc-standardization', 'blocked') -and $pendingCount -gt 0) {
        $why = [string](_PR_GetField -Obj $e -Name 'dispatchReadinessExplanation' -Default '')
        $holds.Add((_RR_Hold -Code 'doc-readiness' -Label 'Documentation readiness' -Detail $(if ($why) { "Dispatch readiness is '$docReadiness': $why" } else { "Dispatch readiness is '$docReadiness'." })))
    }

    # Lane 0.22: the one dispatch-eligibility rule. Its archived reason is
    # already listed above; the rest are its own.
    $ledger = if ($null -ne $LedgerEntry) { $LedgerEntry } else { [pscustomobject]@{ repoName = (_PR_GetField -Obj $e -Name 'repoName' -Default ''); executionState = '' } }
    $eligibility = Get-DispatchEligibility -LedgerEntry $ledger -PortfolioEntry $e
    foreach ($r in @($eligibility.reasons)) {
        if ($r.code -eq 'archived') { continue }
        $holds.Add((_RR_Hold -Code $r.code -Label $r.label -Detail $r.detail))
    }

    # Ready needs positive evidence of an actionable item. An entry assessed
    # before the actionable-line classifier (Lane 0.22 loop step 1) carries no
    # itemQualityModelVersion: its missing top item was never measured, so it
    # is held as unmeasured, not reported as a roadmap with nothing to do.
    if ($pendingCount -gt 0 -and $null -eq (_PR_GetField -Obj $e -Name 'topDispatchableItem' -Default $null)) {
        if (-not [string](_PR_GetField -Obj $e -Name 'itemQualityModelVersion' -Default '')) {
            $holds.Add((_RR_Hold -Code 'item-quality-unmeasured' -Label 'Actionable items not measured' -Detail 'This entry was assessed before the actionable-line classifier, so whether any pending item is actionable is unknown. Rescan the portfolio with the current service to measure it.'))
        } else {
            $excluded = _PR_GetField -Obj $e -Name 'excludedItemCount' -Default $null
            $holds.Add((_RR_Hold -Code 'no-actionable-item' -Label 'No actionable item' -Detail ('None of the {0} pending items is an actionable line an agent can take{1}.' -f $pendingCount, $(if (_PR_IsNumber $excluded) { " ($([int]$excluded) excluded as unclear, truncated, or not a task; any others are operator-only)" } else { '' }))))
        }
    }
    if (-not [string](_PR_GetField -Obj $e -Name 'githubFullName' -Default '')) {
        $holds.Add((_RR_Hold -Code 'no-github-remote' -Label 'No GitHub remote' -Detail 'The repository has no GitHub remote, so a run here cannot end in a pull request.'))
    }

    # Never call ready what the lifecycle resolver does not.
    if ($holds.Count -eq 0 -and $lifecycle -ne 'ready-for-work') {
        $holds.Add((_RR_Hold -Code 'lifecycle' -Label 'Lifecycle not ready' -Detail ("The lifecycle resolver reads '{0}', not ready-for-work." -f $(if ($lifecycle) { $lifecycle } else { 'unknown' }))))
    }

    return [pscustomobject]@{
        repoName = [string](_PR_GetField -Obj $e -Name 'repoName' -Default '')
        ready    = ($holds.Count -eq 0)
        holds    = @($holds.ToArray())
    }
}

function Get-ReadinessCensus {
    <#
    .SYNOPSIS
        Every indexed repository's readiness, the ready count, the holds by
        code, and the repositories one hold away from ready.
    .DESCRIPTION
        $LedgerEntries are matched to index entries the way the Dispatch Board
        matches them (Find-EligibilityPortfolioEntry), so a repository the
        ledger blocks is held here too.
    #>
    [CmdletBinding()]
    param(
        [Parameter()][AllowEmptyCollection()][object[]]$PortfolioEntries = @(),
        [Parameter()][AllowEmptyCollection()][object[]]$LedgerEntries = @(),
        [Parameter()][string]$IndexGeneratedAt = ''
    )

    $entries = @(@($PortfolioEntries) | Where-Object { $null -ne $_ })
    $ledgerFor = @{}
    foreach ($l in @($LedgerEntries)) {
        if ($null -eq $l) { continue }
        $match = Find-EligibilityPortfolioEntry -LedgerEntry $l -PortfolioEntries $entries
        if ($null -ne $match) { $ledgerFor[[System.Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($match)] = $l }
    }

    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($p in $entries) {
        $key = [System.Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($p)
        $l = if ($ledgerFor.ContainsKey($key)) { $ledgerFor[$key] } else { $null }
        $rows.Add((Get-RepositoryReadiness -PortfolioEntry $p -LedgerEntry $l))
    }
    $all = @($rows.ToArray())

    $byCode = [ordered]@{}
    foreach ($row in $all) {
        foreach ($h in @($row.holds)) {
            if (-not $byCode.Contains($h.code)) { $byCode[$h.code] = [System.Collections.Generic.List[string]]::new() }
            $byCode[$h.code].Add($row.repoName)
        }
    }
    $holdSummary = @(foreach ($code in $byCode.Keys) { [pscustomobject]@{ code = $code; count = $byCode[$code].Count; repos = @($byCode[$code].ToArray()) } } )
    $holdSummary = @($holdSummary | Sort-Object @{ e = 'count'; Descending = $true }, code)

    return [pscustomobject]@{
        schemaVersion    = 'v1'
        kind             = 'readiness-census'
        modelVersion     = $script:RepositoryReadinessModelVersion
        indexGeneratedAt = $IndexGeneratedAt
        repoCount        = $all.Count
        readyCount       = @($all | Where-Object { $_.ready }).Count
        ready            = @($all | Where-Object { $_.ready } | ForEach-Object { $_.repoName })
        oneHoldAway      = @($all | Where-Object { @($_.holds).Count -eq 1 } | ForEach-Object { [pscustomobject]@{ repoName = $_.repoName; hold = $_.holds[0] } })
        holdsByCode      = $holdSummary
        repositories     = $all
    }
}
