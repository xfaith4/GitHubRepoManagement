<#
.SYNOPSIS
    Lane 0.18 (H-13b) — dependency-aware next-item selection.

.DESCRIPTION
    One pure function: given a roadmap's parsed items and the set of completed
    ids, which item may be worked on next, or why may none be?

    D-001 (2026-09-06) settled the shape: dependencies are optional, within one
    repository, acyclic, keyed on stable item ids, and they gate dispatch
    eligibility. H-13a made the notation readable; this decides with it.

    THREE VERDICTS, and the difference between two of them is the point:

      ready     an item is eligible now. `item` carries it.
      complete  nothing is pending. There is no next item because the work is
                done, which is not a problem.
      blocked   work remains and none of it can start. This is a DEAD END and
                it is reported as one, because the alternative -- picking an
                item whose prerequisites are unmet -- dispatches an agent into
                work it cannot finish, and does so silently.

    Ordering is deliberate and matches the reference implementation this packet
    names (RoadmapOrchestrator's Get-NextPhase): completeness first, then
    structural faults, then eligibility, then the dead end. Structural faults
    outrank eligibility because an unresolved id or a cycle means the roadmap's
    own ordering cannot be trusted -- returning "here is your next item" from a
    graph that contradicts itself would be a confident answer computed from a
    broken input.

    A roadmap with no dependency notation returns exactly what first-pending
    logic returned before this existed. That is asserted, not assumed: every
    item is eligible immediately, so the first pending item wins.

.NOTES
    PowerShell 5.1 compatible. Param-less library: dot-source it, do not run it.
    Pure -- reads no file, writes nothing, and takes its completed set as input.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function _RoadmapDeps_Field {
    param([object]$Obj, [string]$Name, [object]$Default = $null)
    if ($null -eq $Obj) { return $Default }
    if ($Obj -is [System.Collections.IDictionary]) {
        if ($Obj.Contains($Name) -and $null -ne $Obj[$Name]) { return $Obj[$Name] }
        return $Default
    }
    # ForEach-Object rather than `.Properties.Name`: under StrictMode,
    # member-access enumeration over an EMPTY property collection throws, and an
    # item carrying neither id nor dependsOn is the ordinary case here.
    if ($null -ne $Obj.PSObject -and (@($Obj.PSObject.Properties | ForEach-Object { $_.Name }) -contains $Name)) {
        $value = $Obj.$Name
        if ($null -ne $value) { return $value }
    }
    return $Default
}

function _RoadmapDeps_Dependencies {
    <#
        The declared dependencies of one item, with nothing empty in the list.

        The Where-Object is load-bearing: @($null) is a ONE-element array
        holding $null, not an empty one, so an item with no dependsOn would
        otherwise read as depending on the empty string -- which no item
        declares, so every such item would report as blocked.
    #>
    param([object]$Item)
    return @(@(_RoadmapDeps_Field -Obj $Item -Name 'dependsOn' -Default @()) |
        Where-Object { $null -ne $_ -and -not [string]::IsNullOrWhiteSpace([string]$_) } |
        ForEach-Object { [string]$_ })
}

<#
.SYNOPSIS
    The next roadmap item that may be worked on, or why none may.

.PARAMETER Items
    Parsed items from Invoke-ParseRoadmapContent's `items` array. Each may carry
    `id` and `dependsOn`; items carrying neither are eligible immediately.

.PARAMETER CompletedIds
    Ids already finished. When omitted, it is derived from the items themselves:
    within one roadmap, a dependency is satisfied when the item declaring that
    id is checked. Passing it explicitly lets a caller model completion that
    lives outside the file.

.OUTPUTS
    [pscustomobject] verdict ('ready' | 'complete' | 'blocked'), item, reason,
    blockedIds, unresolvedIds, cycles.
#>
function Get-NextEligibleRoadmapItem {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()][AllowEmptyCollection()][object[]]$Items = @(),
        [Parameter()][AllowNull()][AllowEmptyCollection()][string[]]$CompletedIds
    )

    $all = @(@($Items) | Where-Object { $null -ne $_ })

    # Derive the completed set when the caller did not supply one. $null and an
    # explicitly empty array are DIFFERENT inputs: an explicit @() means "treat
    # nothing as done", which is exactly what a caller testing a fresh roadmap
    # wants, and silently re-deriving it would ignore them.
    $done = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    if ($null -eq $CompletedIds) {
        foreach ($item in $all) {
            if (-not [bool](_RoadmapDeps_Field -Obj $item -Name 'checked' -Default $false)) { continue }
            $id = [string](_RoadmapDeps_Field -Obj $item -Name 'id' -Default '')
            if (-not [string]::IsNullOrWhiteSpace($id)) { $null = $done.Add($id) }
        }
    }
    else {
        foreach ($id in @($CompletedIds)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$id)) { $null = $done.Add([string]$id) }
        }
    }

    $declared = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($item in $all) {
        $id = [string](_RoadmapDeps_Field -Obj $item -Name 'id' -Default '')
        if (-not [string]::IsNullOrWhiteSpace($id)) { $null = $declared.Add($id) }
    }

    $pending = @($all | Where-Object { -not [bool](_RoadmapDeps_Field -Obj $_ -Name 'checked' -Default $false) })

    if ($pending.Count -eq 0) {
        return [pscustomobject]@{
            verdict       = 'complete'
            item          = $null
            reason        = 'No pending items remain.'
            blockedIds    = @()
            unresolvedIds = @()
            cycles        = @()
        }
    }

    # Structural faults outrank eligibility. A roadmap whose graph contradicts
    # itself cannot be trusted to say what comes next, so it is refused BY NAME
    # rather than answered from a broken input.
    $report = [pscustomobject]@{ unknownIds = @(); cycles = @() }
    if (Get-Command -Name 'Get-RoadmapDependencyReport' -ErrorAction SilentlyContinue) {
        $report = Get-RoadmapDependencyReport -Items $all
    }
    $unresolved = @($report.unknownIds)
    $cycles = @($report.cycles)

    if ($unresolved.Count -gt 0 -or $cycles.Count -gt 0) {
        $why = @()
        if ($unresolved.Count -gt 0) { $why += ("unresolved dependency id(s): {0}" -f ($unresolved -join '; ')) }
        if ($cycles.Count -gt 0) { $why += ("dependency cycle(s): {0}" -f ($cycles -join '; ')) }
        return [pscustomobject]@{
            verdict       = 'blocked'
            item          = $null
            reason        = ("The dependency graph cannot be trusted to order this work — {0}." -f ($why -join ', and '))
            blockedIds    = @()
            unresolvedIds = $unresolved
            cycles        = $cycles
        }
    }

    # First eligible in DOCUMENT ORDER, so selection is deterministic for a
    # given completed set. Items are already in document order.
    foreach ($item in $pending) {
        $deps = _RoadmapDeps_Dependencies -Item $item
        $ready = $true
        foreach ($dep in $deps) {
            if (-not $done.Contains($dep)) { $ready = $false; break }
        }
        if ($ready) {
            return [pscustomobject]@{
                verdict       = 'ready'
                item          = $item
                reason        = ''
                blockedIds    = @()
                unresolvedIds = @()
                cycles        = @()
            }
        }
    }

    # The dead end: work remains and nothing can start.
    #
    # UNREACHABLE when the graph is sound, and that is worth stating rather than
    # implying: an acyclic graph whose ids all resolve always has a source node
    # with no dependencies, and a source is eligible by definition. So this
    # branch is reached only when the structural check above could not run --
    # Roadmap.Dependencies.ps1 dot-sourced without Roadmap.Parser.ps1, which
    # leaves Get-RoadmapDependencyReport undefined and lets a cycle through.
    #
    # It is kept, and kept correct, because the alternative on that path is
    # returning an item from a graph nothing verified. A safety net that is
    # never used is not the same as one that is wrong.
    $blocked = [System.Collections.Generic.List[string]]::new()
    foreach ($item in $pending) {
        $deps = _RoadmapDeps_Dependencies -Item $item
        $unmet = @($deps | Where-Object { -not $done.Contains($_) })
        if ($unmet.Count -eq 0) { continue }
        $label = [string](_RoadmapDeps_Field -Obj $item -Name 'id' -Default '')
        if ([string]::IsNullOrWhiteSpace($label)) { $label = [string](_RoadmapDeps_Field -Obj $item -Name 'text' -Default '(untitled item)') }
        $blocked.Add(("{0} waits on {1}" -f $label, ($unmet -join ', '))) | Out-Null
    }

    return [pscustomobject]@{
        verdict       = 'blocked'
        item          = $null
        reason        = ("dependencies unresolved — {0} pending item(s) remain and none is eligible: {1}." -f $pending.Count, (@($blocked) -join '; '))
        blockedIds    = @($blocked)
        unresolvedIds = @()
        cycles        = @()
    }
}
