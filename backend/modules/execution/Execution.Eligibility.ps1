# ---------------------------------------------------------------------------
# Lane 0.22 - one dispatch-eligibility rule.
#
# The Dispatch Board read "Ready" for repositories Today holds for uncommitted
# changes, for a curated-out archived repository, for one whose own detail
# reads "blocked", and for folders not in the index. One rule answers
# `{ ok, reasons[] }` for a ledger entry, and every surface reads that answer.
#
# Pure: no I/O. Needs Portfolio.Ranking.ps1 (_PR_* helpers) loaded first.
# An unmeasured input is never a hold: a working tree nobody has read is not a
# dirty one. Only a recorded fact holds a repository.
# ---------------------------------------------------------------------------

function Find-EligibilityPortfolioEntry {
    [CmdletBinding()]
    param(
        [Parameter()][object]$LedgerEntry,
        [Parameter()][AllowEmptyCollection()][object[]]$PortfolioEntries = @()
    )

    $path = _PR_NormalizePath ([string](_PR_GetField -Obj $LedgerEntry -Name 'repoPath' -Default ''))
    $name = ([string](_PR_GetField -Obj $LedgerEntry -Name 'repoName' -Default '')).ToLowerInvariant()
    $byName = [System.Collections.Generic.List[object]]::new()
    foreach ($p in @($PortfolioEntries)) {
        if ($null -eq $p) { continue }
        if ($path -and (_PR_NormalizePath ([string](_PR_GetField -Obj $p -Name 'localPath' -Default ''))) -eq $path) { return $p }
        if ($name -and ([string](_PR_GetField -Obj $p -Name 'repoName' -Default '')).ToLowerInvariant() -eq $name) { $byName.Add($p) }
    }
    # A name shared by two indexed repositories identifies neither.
    if ($byName.Count -eq 1) { return $byName[0] }
    return $null
}

function Get-DispatchEligibility {
    <#
    .SYNOPSIS
        { ok, reasons[] } - may this repository be dispatched to right now?
    .DESCRIPTION
        reasons[] is a list of { code, label, detail }. Codes: not-in-index,
        archived, uncommitted-changes, blocked. ok is true only when none apply.
        $PortfolioEntry $null means the index does not hold the repository.
    #>
    [CmdletBinding()]
    param(
        [Parameter()][object]$LedgerEntry,
        [Parameter()][object]$PortfolioEntry
    )

    $reasons = [System.Collections.Generic.List[object]]::new()
    function _Reason([string]$Code, [string]$Label, [string]$Detail) {
        [pscustomobject]@{ code = $Code; label = $Label; detail = $Detail }
    }

    if ($null -eq $PortfolioEntry) {
        $reasons.Add((_Reason 'not-in-index' 'Not in the portfolio index' 'The index does not hold this folder, so nothing is known about it and it cannot be ranked or dispatched.'))
    } else {
        if ([string](_PR_GetField -Obj $PortfolioEntry -Name 'curationState' -Default 'none') -eq 'archived-ignore') {
            $reasons.Add((_Reason 'archived' 'Archived' 'You curated this repository out as archived-ignore.'))
        }
        $dirty = _PR_GetField -Obj $PortfolioEntry -Name 'localDirtyCount'
        if ((_PR_IsNumber $dirty) -and [double]$dirty -gt 0) {
            $n = [int]$dirty
            $reasons.Add((_Reason 'uncommitted-changes' 'Uncommitted changes' ("{0} uncommitted {1} in the working tree." -f $n, $(if ($n -eq 1) { 'file' } else { 'files' }))))
        }
    }

    if ([string](_PR_GetField -Obj $LedgerEntry -Name 'executionState' -Default '') -eq 'blocked') {
        $why = [string](_PR_GetField -Obj $LedgerEntry -Name 'errorMessage' -Default '')
        $reasons.Add((_Reason 'blocked' 'Blocked' $(if ($why) { $why } else { 'The execution ledger records this repository as blocked.' })))
    }

    return [pscustomobject]@{ ok = ($reasons.Count -eq 0); reasons = @($reasons.ToArray()) }
}

function Add-DispatchEligibility {
    <#
    .SYNOPSIS
        Attach `eligibility` to each ledger entry (derived on read, never
        persisted) and return the entries in the order given.
    #>
    [CmdletBinding()]
    [OutputType([System.Object[]])]
    param(
        [Parameter()][AllowEmptyCollection()][object[]]$QueueEntries = @(),
        [Parameter()][AllowEmptyCollection()][object[]]$PortfolioEntries = @()
    )

    foreach ($entry in @($QueueEntries)) {
        if ($null -eq $entry) { continue }
        $match = Find-EligibilityPortfolioEntry -LedgerEntry $entry -PortfolioEntries $PortfolioEntries
        _PR_SetField -Obj $entry -Name 'eligibility' -Value (Get-DispatchEligibility -LedgerEntry $entry -PortfolioEntry $match)
    }
    return @($QueueEntries | Where-Object { $null -ne $_ })
}

function Get-HeldSummary {
    <#
    .SYNOPSIS
        "N held (why)": ineligible entries collapsed by reason code.
    #>
    [CmdletBinding()]
    param([Parameter()][AllowEmptyCollection()][object[]]$Entries = @())

    $held = @(@($Entries) | Where-Object { $null -ne $_ -and -not (_PR_GetField -Obj (_PR_GetField -Obj $_ -Name 'eligibility') -Name 'ok' -Default $true) })
    $byReason = [ordered]@{}
    foreach ($e in $held) {
        foreach ($r in @((_PR_GetField -Obj $e -Name 'eligibility').reasons)) {
            if (-not $byReason.Contains($r.code)) { $byReason[$r.code] = [System.Collections.Generic.List[string]]::new() }
            $byReason[$r.code].Add([string](_PR_GetField -Obj $e -Name 'repoName' -Default ''))
        }
    }
    $summary = @(foreach ($code in $byReason.Keys) { [pscustomobject]@{ code = $code; count = $byReason[$code].Count; repos = @($byReason[$code].ToArray()) } })
    return [pscustomobject]@{ heldCount = $held.Count; byReason = $summary }
}
