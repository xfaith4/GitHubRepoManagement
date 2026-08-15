<#
    Release 3.4 milestone 5 -- a merged branch is cleaned up, and cleanup proves
    it is the branch that merged.

    Until this module, no deletion of any kind existed anywhere in backend/ or
    scripts/, so every completed item left two branches behind -- one local, one
    on the remote. The delivery loop was an arc that accumulated debris.

    The rule is deliberately stricter than `git branch -d`:

        Deletion requires BOTH a confirmed merged pull request AND the branch
        tip still equalling that pull request's merged head SHA.

    `-d` proves "merged into the upstream"; it does not prove *which* merge, and
    it says yes to a branch whose tip commit happens to be reachable some other
    way. Requiring the caller to present the merged PR's head SHA -- a fact only
    the merge evidence can supply -- means a tip that advanced after the merge
    refuses BY NAME: those commits are not in the default branch, and deleting
    the branch would destroy them. A branch checked out in any worktree refuses
    the same way, before git has to.

    Approval is an INPUT, exactly as on Sync-RepoDefaultBranch: every transition
    takes it, none defaults it, and an omitted approval is a named refusal.
#>

Set-StrictMode -Version Latest

function Resolve-BranchCleanupDecision {
    <#
    .SYNOPSIS
        Pure -- decide whether a branch may be deleted, from gathered facts.
    .DESCRIPTION
        No git, no network, no disk: the whole refusal matrix is unit-testable,
        in the same shape as Resolve-DefaultBranchSyncDecision. The caller
        gathers the facts; this function only judges them.
    .OUTPUTS
        [pscustomobject] allowed, category, reason, remedy.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()][AllowEmptyString()][string]$Branch = '',
        [Parameter()][AllowEmptyString()][string]$MergedHeadSha = '',
        [Parameter()][AllowEmptyString()][string]$BranchTipSha = '',
        [Parameter()][AllowEmptyCollection()][string[]]$DefaultBranchNames = @('main', 'master'),
        [Parameter()][bool]$BranchExists = $false,
        [Parameter()][AllowEmptyString()][string]$CheckedOutAt = '',
        [Parameter()][bool]$Approved = $false
    )

    $verdict = {
        param([bool]$Allowed, [string]$Category, [string]$Reason, [string]$Remedy = '')
        [pscustomobject]@{ allowed = $Allowed; category = $Category; reason = $Reason; remedy = $Remedy }
    }

    if ([string]::IsNullOrWhiteSpace($Branch)) {
        return & $verdict $false 'validation' 'No branch name was provided -- there is nothing to delete.'
    }
    if ($Branch -in $DefaultBranchNames) {
        return & $verdict $false 'default-branch' ("'{0}' is a default branch and is never deleted by this product, merged or not." -f $Branch)
    }
    if (-not $BranchExists) {
        return & $verdict $false 'branch-not-found' ("Branch '{0}' does not exist in this checkout." -f $Branch) 'Nothing local to delete; use remote-only cleanup if the remote branch remains.'
    }
    if (-not [string]::IsNullOrWhiteSpace($CheckedOutAt)) {
        return & $verdict $false 'checked-out' ("Branch '{0}' is checked out at '{1}'. Deleting a checked-out branch would strand that working tree." -f $Branch, $CheckedOutAt) 'Switch that worktree to another branch first.'
    }
    if ([string]::IsNullOrWhiteSpace($MergedHeadSha)) {
        # No merged-head SHA means no proven merge. This is the milestone's
        # whole point: deletion is not a tidiness action, it is the last step
        # of a PROVEN merge, and the proof travels as the SHA.
        return & $verdict $false 'no-merge-evidence' 'No merged pull-request head SHA was provided, so there is no proof this branch merged.' 'Confirm the PR merged and pass its merged head SHA.'
    }
    if ([string]::IsNullOrWhiteSpace($BranchTipSha)) {
        return & $verdict $false 'tip-unreadable' ("Could not read the tip of '{0}', so it cannot be compared to the merged head." -f $Branch)
    }
    if ($BranchTipSha -ne $MergedHeadSha) {
        return & $verdict $false 'tip-advanced' ("The tip of '{0}' ({1}) is not the merged head ({2}). Commits landed on this branch after the merge; they are not in the default branch, and deleting the branch would destroy them." -f $Branch, $BranchTipSha.Substring(0, [Math]::Min(8, $BranchTipSha.Length)), $MergedHeadSha.Substring(0, [Math]::Min(8, $MergedHeadSha.Length))) 'Review the extra commits: merge them through a new PR, or delete manually once they are accounted for.'
    }
    if (-not $Approved) {
        return & $verdict $false 'approval-required' 'This deletion has not been approved.' 'Approve the cleanup, or mark this transition trusted.'
    }
    return & $verdict $true '' ''
}

function Remove-MergedRepoBranch {
    <#
    .SYNOPSIS
        Impure -- delete a branch that has been PROVEN merged, locally and
        (optionally) on the remote.
    .DESCRIPTION
        Gathers the facts, asks Resolve-BranchCleanupDecision, and acts only on
        an allowed verdict. Returns a result object; never throws for an
        expected condition -- a refusal is information, and the operation that
        tidies up after a merge must not be the thing that breaks the loop.

        The local deletion uses `git branch -D` deliberately: `-d`'s own merged
        check is WEAKER than the proof already demanded (tip equals the merged
        PR head), and letting git second-guess a stronger proof with a weaker
        one would refuse legitimate cleanups of squash-merged branches -- whose
        commits are never reachable from the default branch by ancestry.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter()][AllowEmptyString()][string]$RepoPath = '',
        [Parameter()][AllowEmptyString()][string]$Branch = '',
        [Parameter()][AllowEmptyString()][string]$MergedHeadSha = '',
        [Parameter()][AllowEmptyString()][string]$Remote = 'origin',
        [Parameter()][bool]$DeleteRemote = $false,
        [Parameter()][AllowEmptyString()][string]$Token = '',
        [Parameter()][bool]$Approved = $false
    )

    $fail = {
        param([string]$Category, [string]$Reason, [string]$Remedy = '')
        [pscustomobject]@{
            deleted = $false; refused = $true; category = $Category; reason = $Reason; remedy = $Remedy
            branch = $Branch; tipSha = $null; remoteDeleted = $false; remoteResult = ''
        }
    }

    if ([string]::IsNullOrWhiteSpace($RepoPath) -or -not (Test-Path -LiteralPath (Join-Path $RepoPath '.git'))) {
        return & $fail 'not-a-git-repo' ("'{0}' is not a git working copy." -f $RepoPath) 'Point at a cloned repository.'
    }
    if ([string]::IsNullOrWhiteSpace($Remote)) { $Remote = 'origin' }

    # Default-branch names: the remote's HEAD when it is known, plus the two
    # conventional names for a clone whose origin/HEAD was never set.
    $defaultNames = @('main', 'master')
    $originHead = (& git -C $RepoPath symbolic-ref --quiet --short ("refs/remotes/{0}/HEAD" -f $Remote) 2>&1) | Out-String
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($originHead)) {
        $defaultNames += ($originHead.Trim() -replace ("^{0}/" -f [regex]::Escape($Remote)), '')
    }

    $branchExists = $false
    $tipSha = ''
    if (-not [string]::IsNullOrWhiteSpace($Branch)) {
        $tipOut = (& git -C $RepoPath rev-parse --verify --quiet ("refs/heads/{0}" -f $Branch) 2>&1) | Out-String
        if ($LASTEXITCODE -eq 0) { $branchExists = $true; $tipSha = $tipOut.Trim() }
    }

    # A branch checked out in ANY worktree -- this one or a linked one -- refuses
    # before git has to. `worktree list --porcelain` names each checkout's
    # branch ref; the main working tree is listed too, so the current checkout
    # needs no separate case.
    $checkedOutAt = ''
    $wtOut = (& git -C $RepoPath worktree list --porcelain 2>&1) | Out-String
    if ($LASTEXITCODE -eq 0) {
        $wtPath = ''
        foreach ($line in ($wtOut -split "`n")) {
            $trimmed = $line.Trim()
            if ($trimmed -like 'worktree *') { $wtPath = $trimmed.Substring(9) }
            elseif ($trimmed -eq ("branch refs/heads/{0}" -f $Branch)) { $checkedOutAt = $wtPath }
        }
    }

    $decision = Resolve-BranchCleanupDecision -Branch $Branch -MergedHeadSha $MergedHeadSha `
        -BranchTipSha $tipSha -DefaultBranchNames $defaultNames -BranchExists $branchExists `
        -CheckedOutAt $checkedOutAt -Approved $Approved
    if (-not $decision.allowed) {
        $refusal = & $fail $decision.category $decision.reason $decision.remedy
        $refusal.tipSha = $(if ($tipSha) { $tipSha } else { $null })
        return $refusal
    }

    if (-not $PSCmdlet.ShouldProcess(("{0} ({1})" -f $RepoPath, $Branch), 'delete merged branch')) {
        return & $fail 'whatif' 'WhatIf: nothing deleted.'
    }

    $del = (& git -C $RepoPath branch -D $Branch 2>&1) | Out-String
    if ($LASTEXITCODE -ne 0) {
        return & $fail 'delete-failed' ("git branch -D '{0}' failed: {1}" -f $Branch, ($del.Trim() -split "`n" | Select-Object -First 1))
    }

    $remoteDeleted = $false
    $remoteResult = ''
    if ($DeleteRemote) {
        # Same auth mechanics as every push in this product; never a force.
        # A remote failure does NOT undo the proven local deletion -- it is
        # reported as its own outcome so the operator finishes the half git
        # could not.
        $pushArgs = @()
        if ((Get-Command -Name 'Get-GitTokenPushArgs' -ErrorAction SilentlyContinue) -and -not [string]::IsNullOrWhiteSpace($Token)) {
            $pushArgs = Get-GitTokenPushArgs -Token $Token
        }
        $rdel = (& git -C $RepoPath @pushArgs push $Remote --delete $Branch 2>&1) | Out-String
        if ($LASTEXITCODE -eq 0) { $remoteDeleted = $true; $remoteResult = 'deleted' }
        else { $remoteResult = ("remote deletion failed: {0}" -f ($rdel.Trim() -split "`n" | Select-Object -First 1)) }
    }

    return [pscustomobject]@{
        deleted = $true; refused = $false; category = ''; remedy = ''
        reason = ("Branch '{0}' deleted at its merged head {1}." -f $Branch, $MergedHeadSha.Substring(0, [Math]::Min(8, $MergedHeadSha.Length)))
        branch = $Branch; tipSha = $tipSha
        remoteDeleted = $remoteDeleted; remoteResult = $remoteResult
    }
}
