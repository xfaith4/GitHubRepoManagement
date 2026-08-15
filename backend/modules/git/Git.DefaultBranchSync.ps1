<#
.SYNOPSIS
    Return a clone's default branch to the remote tip — and refuse, by name,
    every state in which that is not the safe thing to do.

.DESCRIPTION
    Release 3.4 — Release 3.1 shipped a guard that detects a stale base and
    refuses to branch from it, but `git fetch` and `git pull` appeared nowhere
    in `backend/` or `scripts/`, so the guard was a stop sign with no road
    behind it: a correct diagnosis and no action. This module is the road.

    THE GOVERNING INVARIANT, WHICH THIS MODULE DOES NOT RELAX. Agents may commit
    freely to feature branches. They may never merge or push to a default
    branch. Changes reach `main` only through a passing pull request.

    A fast-forward is the only operation here, and it is the one git operation
    that cannot violate that rule: `--ff-only` refuses outright when a merge
    would be required, so it moves a ref pointer and can never author a commit.
    There is no merge, no rebase, no force, and no `git pull` — the fetch and
    the fast-forward are separate, explicit steps, so a repository-local
    `pull.rebase` setting cannot silently turn this into a history rewrite.

    ONLY `behind` MAY FAST-FORWARD. The four states are not shades of the same
    thing and each gets its own answer:

      current   nothing to do; a no-op is a success, not a refusal
      behind    fast-forward — the only state that moves anything
      ahead     REFUSED as `default-branch-ahead`. Local commits sitting on a
                default branch are precisely the invariant violation this
                release exists to prevent. Fast-forwarding would silently carry
                them along; reporting them is the point.
      diverged  REFUSED. A fast-forward is impossible, and the alternatives
                (merge, rebase) are both history changes on a default branch.

    Dirty tree, missing upstream and detached HEAD refuse with their own named
    reasons, because "it didn't work" is not a diagnosis.
#>

Set-StrictMode -Version Latest

$script:DefaultBranchSyncFetchTimeoutSeconds = 60

function Resolve-DefaultBranchSyncDecision {
    <#
    .SYNOPSIS
        Pure — decide whether a sync may proceed, from already-gathered facts.
    .DESCRIPTION
        Takes a freshness reading plus working-tree facts and returns the
        decision. No git, no network, no disk: the whole refusal matrix is
        unit-testable, in the same shape as Test-RoadmapRepairPrPreconditions
        and Resolve-BaseFreshness.
    .OUTPUTS
        [pscustomobject] action (fast-forward | none), allowed, category,
        reason, remedy, state.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()][AllowNull()][object]$Freshness = $null,
        [Parameter()][bool]$WorkingTreeDirty = $false,
        [Parameter()][bool]$IsDetachedHead = $false,
        [Parameter()][AllowEmptyString()][string]$BranchName = ''
    )

    $decide = {
        param([string]$Action, [bool]$Allowed, [string]$Category, [string]$Reason, [string]$Remedy, [string]$State)
        [pscustomobject]@{
            action   = $Action
            allowed  = $Allowed
            category = $Category
            reason   = $Reason
            remedy   = if ([string]::IsNullOrWhiteSpace($Remedy)) { $null } else { $Remedy }
            state    = $State
        }
    }

    $label = if ([string]::IsNullOrWhiteSpace($BranchName)) { 'the default branch' } else { "'$BranchName'" }

    if ($IsDetachedHead) {
        return & $decide 'none' $false 'detached-head' `
            "HEAD is detached, so there is no branch to fast-forward." `
            "Check out the default branch first." 'unknown'
    }

    # A dirty tree is refused before anything else touches the repository: a
    # fast-forward over uncommitted work can fail partway and leave the operator
    # with a mess they did not create.
    if ($WorkingTreeDirty) {
        return & $decide 'none' $false 'working-tree-dirty' `
            "The working tree has uncommitted changes, so $label cannot be moved safely." `
            "Commit the work to a feature branch, or stash it, then sync again." 'unknown'
    }

    if ($null -eq $Freshness) {
        return & $decide 'none' $false 'freshness-unknown' `
            "The clone's position relative to its remote was never determined, so there is nothing to act on." `
            "Re-run the freshness probe." 'unknown'
    }

    $state = [string]$Freshness.state
    $remedy = if ($Freshness.PSObject.Properties.Name -contains 'remedy') { [string]$Freshness.remedy } else { '' }

    switch ($state) {
        'current' {
            # Already there. This is a success with nothing to do, and callers
            # must not treat it as a failure.
            return & $decide 'none' $true '' "$label is already at the remote tip." '' 'current'
        }
        'behind' {
            $count = $Freshness.behindCount
            $howFar = if ($null -ne $count) { "$count commit(s)" } else { 'an unknown number of commits' }
            return & $decide 'fast-forward' $true '' `
                "$label is $howFar behind its remote and can be fast-forwarded." '' 'behind'
        }
        'behind-unknown-count' {
            # Certainly behind; the count needs a fetch, which the sync does
            # anyway. Allowed — the fetch resolves the ambiguity before the
            # fast-forward is attempted, and --ff-only refuses if it turns out
            # not to be a fast-forward after all.
            return & $decide 'fast-forward' $true '' `
                "$label is behind its remote by an amount only a fetch can name." '' 'behind-unknown-count'
        }
        'ahead' {
            $count = $Freshness.aheadCount
            $howFar = if ($null -ne $count) { "$count commit(s)" } else { 'commits' }
            return & $decide 'none' $false 'default-branch-ahead' `
                ("$label carries $howFar that its remote does not. Commits on a default branch are exactly what must never happen: everything reaches it through a pull request.") `
                ("Move the local commit(s) to a feature branch and open a pull request, then sync again.") 'ahead'
        }
        'diverged' {
            $behind = $Freshness.behindCount
            $ahead = $Freshness.aheadCount
            return & $decide 'none' $false 'diverged' `
                ("$label is {0} behind its remote and {1} ahead of it, so a fast-forward is impossible. Merging or rebasing would rewrite a default branch, which this product does not do." -f `
                    $(if ($null -ne $behind) { "$behind commit(s)" } else { 'an unknown number of commits' }), `
                    $(if ($null -ne $ahead) { "$ahead commit(s)" } else { 'an unknown number' })) `
                $(if ([string]::IsNullOrWhiteSpace($remedy)) { "Move the local commit(s) to a feature branch, reset $label to its remote, and open a pull request." } else { $remedy }) 'diverged'
        }
        default {
            $why = if ($Freshness.PSObject.Properties.Name -contains 'probeError' -and $Freshness.probeError) { [string]$Freshness.probeError } else { 'the remote could not be reached' }
            return & $decide 'none' $false 'freshness-unknown' `
                "The clone's position relative to its remote is unknown: $why. Refusing to move $label on a guess." `
                "Check the remote and network, then sync again." 'unknown'
        }
    }
}

function Sync-RepoDefaultBranch {
    <#
    .SYNOPSIS
        Impure — fetch, then fast-forward the default branch if that is safe.
    .DESCRIPTION
        Fetch and fast-forward are separate commands on purpose (see the module
        note). Returns a result object; never throws, because the operation that
        keeps a clone current must not be the thing that breaks a run.
    .PARAMETER Approved
        Release 3.4 — approval is an INPUT, not a hard-coded prompt. Every
        transition takes it, so a later release can mark a transition trusted
        and skip the prompt without reopening the transition itself.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter()][AllowEmptyString()][string]$RepoPath = '',
        [Parameter()][AllowEmptyString()][string]$BranchName = '',
        [Parameter()][AllowEmptyString()][string]$Remote = 'origin',
        [Parameter()][bool]$Approved = $false,
        [Parameter()][int]$FetchTimeoutSeconds = $script:DefaultBranchSyncFetchTimeoutSeconds
    )

    $fail = {
        param([string]$Category, [string]$Reason, [string]$Remedy)
        [pscustomobject]@{
            synced = $false; refused = $true; category = $Category; reason = $Reason
            remedy = $Remedy; state = 'unknown'; branch = $BranchName; remote = $Remote
            fromSha = $null; toSha = $null; freshness = $null
        }
    }

    if ([string]::IsNullOrWhiteSpace($RepoPath) -or -not (Test-Path -LiteralPath (Join-Path $RepoPath '.git'))) {
        return & $fail 'not-a-git-repo' "'$RepoPath' is not a git working copy." 'Point at a cloned repository.'
    }
    if ([string]::IsNullOrWhiteSpace($Remote)) { $Remote = 'origin' }

    # Resolve the branch before anything else — a detached HEAD has no branch to
    # move, and saying so is more useful than a git error.
    $detached = $false
    $branch = $BranchName
    $headRef = (& git -C $RepoPath symbolic-ref --quiet --short HEAD 2>&1) | Out-String
    if ($LASTEXITCODE -ne 0) { $detached = $true }
    elseif ([string]::IsNullOrWhiteSpace($branch)) { $branch = $headRef.Trim() }

    $dirty = $false
    $statusOut = (& git -C $RepoPath status --porcelain 2>&1) | Out-String
    if ($LASTEXITCODE -ne 0) { $dirty = $true } else { $dirty = -not [string]::IsNullOrWhiteSpace($statusOut.Trim()) }

    $freshness = $null
    if (-not $detached -and (Get-Command -Name 'Get-RepoBaseFreshness' -ErrorAction SilentlyContinue)) {
        $freshness = Get-RepoBaseFreshness -RepoPath $RepoPath -BaseBranch $branch -Remote $Remote
    }

    $decision = Resolve-DefaultBranchSyncDecision -Freshness $freshness -WorkingTreeDirty $dirty `
        -IsDetachedHead $detached -BranchName $branch

    $fromSha = ''
    $rev = (& git -C $RepoPath rev-parse HEAD 2>&1) | Out-String
    if ($LASTEXITCODE -eq 0) { $fromSha = $rev.Trim() }

    $base = [ordered]@{
        synced = $false; refused = $false; category = $decision.category; reason = $decision.reason
        remedy = $decision.remedy; state = $decision.state; branch = $branch; remote = $Remote
        fromSha = $(if ($fromSha) { $fromSha } else { $null }); toSha = $null; freshness = $freshness
    }

    if (-not $decision.allowed) {
        $base.refused = $true
        return [pscustomobject]$base
    }

    if ($decision.action -eq 'none') {
        # 'current' — allowed, nothing to do. Not a refusal.
        $base.synced = $true
        $base.toSha = $base.fromSha
        return [pscustomobject]$base
    }

    if (-not $Approved) {
        $base.refused = $true
        $base.category = 'approval-required'
        $base.reason = "$($decision.reason) This transition has not been approved."
        $base.remedy = 'Approve the sync, or mark this transition trusted.'
        return [pscustomobject]$base
    }

    if (-not $PSCmdlet.ShouldProcess(("{0} ({1})" -f $RepoPath, $branch), ("fast-forward to {0}/{1}" -f $Remote, $branch))) {
        $base.refused = $true
        $base.category = 'whatif'
        $base.reason = 'WhatIf: nothing fetched, nothing moved.'
        return [pscustomobject]$base
    }

    try {
        $fetchOut = (& git -C $RepoPath -c ('http.lowSpeedLimit=1') -c ("http.lowSpeedTime={0}" -f $FetchTimeoutSeconds) `
                fetch $Remote $branch 2>&1) | Out-String
        if ($LASTEXITCODE -ne 0) {
            $base.refused = $true
            $base.category = 'fetch-failed'
            $base.reason = ("Could not fetch {0}/{1}: {2}" -f $Remote, $branch, ($fetchOut.Trim() -split "`n" | Select-Object -First 1))
            $base.remedy = 'Check the remote and network, then sync again.'
            return [pscustomobject]$base
        }

        # Re-evaluate now that the objects are local. Before the fetch a clone
        # that has never fetched cannot see the remote commits at all, so its
        # reading is `behind-unknown-count` — which is allowed through on the
        # grounds that the fetch resolves it. It does: afterwards the counts are
        # exact, and a clone that turns out to be diverged gets that refusal by
        # name instead of falling through to git's own error text.
        $postFetch = $null
        if (Get-Command -Name 'Get-RepoBaseFreshness' -ErrorAction SilentlyContinue) {
            $postFetch = Get-RepoBaseFreshness -RepoPath $RepoPath -BaseBranch $branch -Remote $Remote
        }
        if ($null -ne $postFetch) {
            $base.freshness = $postFetch
            $postDecision = Resolve-DefaultBranchSyncDecision -Freshness $postFetch -WorkingTreeDirty $dirty `
                -IsDetachedHead $detached -BranchName $branch
            $base.state = $postDecision.state
            if (-not $postDecision.allowed) {
                $base.refused = $true
                $base.category = $postDecision.category
                $base.reason = $postDecision.reason
                $base.remedy = $postDecision.remedy
                return [pscustomobject]$base
            }
            if ($postDecision.action -eq 'none') {
                $base.synced = $true
                $base.toSha = $base.fromSha
                $base.reason = $postDecision.reason
                return [pscustomobject]$base
            }
        }

        # --ff-only, never a plain merge or pull: this is what makes the
        # operation incapable of authoring a commit on a default branch.
        $mergeOut = (& git -C $RepoPath merge --ff-only FETCH_HEAD 2>&1) | Out-String
        if ($LASTEXITCODE -ne 0) {
            $base.refused = $true
            $base.category = 'not-fast-forwardable'
            $base.reason = ("A fast-forward was refused by git: {0}" -f ($mergeOut.Trim() -split "`n" | Select-Object -First 1))
            $base.remedy = "Move any local commits to a feature branch, then sync again."
            return [pscustomobject]$base
        }

        $after = (& git -C $RepoPath rev-parse HEAD 2>&1) | Out-String
        $base.synced = $true
        $base.toSha = if ($LASTEXITCODE -eq 0) { $after.Trim() } else { $null }
        $base.reason = ("{0} fast-forwarded to {1}/{0}." -f $branch, $Remote)
        return [pscustomobject]$base
    }
    catch {
        $base.refused = $true
        $base.category = 'sync-failed'
        $base.reason = ("The sync failed: {0}" -f $_.Exception.Message)
        return [pscustomobject]$base
    }
}
