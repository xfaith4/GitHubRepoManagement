<#
.SYNOPSIS
    Verify that a clone is current with its remote base branch BEFORE anything
    branches from it or commits to it.

.DESCRIPTION
    Release 3.1 — every write this product makes to a managed repo branched
    from whatever the local working copy happened to be, and `git fetch`
    appeared nowhere in `backend/` or `scripts/`. The submit-PR path evaluated
    nine named refusals — not a git repo, dirty tree, no token, unrecognizable
    remote, byte-identical no-op, and five more — and staleness was not among
    them. The task runner branched the same way.

    THE DAMAGE IS NOT THE OBVIOUS ONE. `git add -- <one file>` cannot revert
    unrelated upstream work, and GitHub's three-way merge turns a genuinely
    conflicting edit into a visible DIRTY state. What nothing catches is that
    the **proposal itself was computed from stale content** — an improvement
    generated against an outdated document, re-adding what upstream already
    fixed or missing context added since. That merges cleanly and reads as
    correct in review.

    THE DETECTOR THE PRODUCT ALREADY HAD WAS AS STALE AS THE THING IT DETECTED.
    Git.StatusDetail.ps1 computes `unpulledCommits` from `git log HEAD..@{u}`,
    which reads the *remote-tracking ref* — a local cache written by the last
    fetch. On a clone that last fetched 195 days ago it reports **zero** while
    the clone sits far behind, which is exactly what a PromptPilot clone did
    while 8 commits behind. Measured 2026-08-14 across 60 local clones: 49 had
    upstreams, 11 reported behind, and those same clones last fetched 93, 195,
    285, 93, 26, 0, 63, 104, 53, 120 and 16 days ago — one had never fetched.
    Every one of those counts was measured against a ref that was itself stale,
    so the true figures could only be larger.

    This module asks the remote directly with `git ls-remote`: one round trip,
    no object download, no working-tree mutation. A fetch would also work and
    would be more expensive; a write path runs rarely enough that one round
    trip is not a budget concern the way the 80-repo portfolio scan is.

    WHAT IT REFUSES, AND WHAT IT DELIBERATELY DOES NOT. A clone **verified**
    behind is refused with a named `stale-base` category that says how far and
    what to run. A clone whose freshness could **not be determined** — no
    remote, no network, detached HEAD — is reported as `unknown` and allowed
    through, because absence of evidence is not evidence of divergence. That is
    the same rule Resolve-RunnerPresence applies to an unreadable heartbeat and
    Resolve-RepoStaleness applies to a missing timestamp, and it keeps an
    offline operator working. The state travels on the result either way, so a
    caller that wants to be stricter can be, and the surface can say which of
    the two it is.
#>

Set-StrictMode -Version Latest

# `ls-remote` talks to the network. A write path must not hang on it forever;
# an unreachable remote degrades to 'unknown', which is not a refusal.
$script:BaseFreshnessTimeoutSeconds = 20

function Resolve-BaseFreshness {
    <#
    .SYNOPSIS
        Pure — classify a clone against its remote base from already-gathered facts.
    .DESCRIPTION
        Takes SHAs and counts rather than probing, so the whole decision matrix
        is unit-testable with no clone, no remote and no network — the same
        shape as Test-RoadmapRepairPrPreconditions.
    .PARAMETER RemoteObjectPresentLocally
        Whether the remote tip commit already exists in the local object store.
        $true means exact counts could be computed; $false means the clone
        genuinely lacks upstream commits; $null means it was not checked.
    .PARAMETER AheadCount
        Commits the clone has that the remote does not. Release 3.4 — computing
        only the behind side reported a clone that was 5 behind AND carrying
        local commits as merely "behind 5", which is the exact state where a
        fast-forward refuses. Both directions or neither.
    .OUTPUTS
        state:    current | behind | ahead | diverged | behind-unknown-count | unknown
        isStale is true when the remote holds commits this clone does not:
        behind, diverged, and behind-unknown-count. 'ahead' is NOT stale — the
        clone already contains everything upstream has — though it is still a
        refusal for the sync path, which is a different question. 'unknown' is
        never stale; see the module note on absence of evidence.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()][AllowNull()][AllowEmptyString()][string]$LocalSha = '',
        [Parameter()][AllowNull()][AllowEmptyString()][string]$RemoteSha = '',
        [Parameter()][AllowNull()][object]$RemoteObjectPresentLocally = $null,
        [Parameter()][AllowNull()][object]$BehindCount = $null,
        [Parameter()][AllowNull()][object]$AheadCount = $null,
        [Parameter()][AllowEmptyString()][string]$BaseBranch = '',
        [Parameter()][AllowEmptyString()][string]$Remote = 'origin',
        [Parameter()][AllowEmptyString()][string]$ProbeError = ''
    )

    $branchLabel = if ([string]::IsNullOrWhiteSpace($BaseBranch)) { 'the base branch' } else { "$Remote/$BaseBranch" }

    $result = [ordered]@{
        state          = 'unknown'
        isStale        = $false
        # Named so no consumer has to infer what produced this. Distinct from
        # Resolve-RepoStaleness's 'remote-push-vs-local-commit', which compares
        # timestamps and cannot yield a commit count.
        basis          = 'ls-remote-vs-local-head'
        baseBranch     = $BaseBranch
        remote         = $Remote
        localSha       = if ([string]::IsNullOrWhiteSpace($LocalSha)) { $null } else { $LocalSha }
        remoteSha      = if ([string]::IsNullOrWhiteSpace($RemoteSha)) { $null } else { $RemoteSha }
        behindCount    = $null
        aheadCount     = $null
        countIsExact   = $false
        remedy         = $null
        probeError     = if ([string]::IsNullOrWhiteSpace($ProbeError)) { $null } else { $ProbeError }
        summary        = ''
    }

    if ([string]::IsNullOrWhiteSpace($LocalSha) -or [string]::IsNullOrWhiteSpace($RemoteSha)) {
        $why = if (-not [string]::IsNullOrWhiteSpace($ProbeError)) { $ProbeError }
               elseif ([string]::IsNullOrWhiteSpace($RemoteSha)) { "could not read $branchLabel from the remote" }
               else { 'could not resolve the local HEAD commit' }
        $result.summary = "Base freshness unknown: $why. Proceeding without verification."
        return [pscustomobject]$result
    }

    if ($LocalSha -eq $RemoteSha) {
        $result.state        = 'current'
        $result.behindCount  = 0
        $result.aheadCount   = 0
        $result.countIsExact = $true
        $result.summary      = "This clone is at the tip of $branchLabel."
        return [pscustomobject]$result
    }

    # The remote tip is already in the local object store, so exact counts are
    # available in both directions without fetching anything.
    if ($RemoteObjectPresentLocally -eq $true) {
        $behind = $null
        $ahead = $null
        if ($null -ne $BehindCount) { try { $behind = [int]$BehindCount } catch { $behind = $null } }
        if ($null -ne $AheadCount) { try { $ahead = [int]$AheadCount } catch { $ahead = $null } }

        if ($null -ne $behind) {
            # Ahead is only reported when it was actually measured. A caller
            # that supplied no ahead-count gets $null rather than an implied 0.
            $result.behindCount  = $behind
            $result.aheadCount   = $ahead
            $result.countIsExact = $true

            if ($behind -le 0 -and ($null -eq $ahead -or $ahead -le 0)) {
                $result.state   = 'current'
                $result.summary = "This clone already contains the tip of $branchLabel."
                return [pscustomobject]$result
            }

            if ($behind -le 0) {
                # Nothing upstream is missing here, so this is not stale — but
                # on a default branch it is still an invariant violation, and
                # the sync layer refuses it as `default-branch-ahead`.
                $result.state   = 'ahead'
                $result.remedy  = "Move these commits to a feature branch and open a pull request; nothing reaches $branchLabel except through one."
                $result.summary = "This clone has $ahead commit(s) that $branchLabel does not."
                return [pscustomobject]$result
            }

            if ($null -ne $ahead -and $ahead -gt 0) {
                # Both sides moved. A fast-forward is impossible from here, so
                # this is called out separately rather than reported as behind.
                $result.state   = 'diverged'
                $result.isStale = $true
                $result.remedy  = "git -C <repo> fetch $Remote, then move the $ahead local commit(s) to a feature branch — $branchLabel cannot fast-forward while it carries them."
                $result.summary = "This clone is $behind commit(s) behind $branchLabel and $ahead ahead of it. The histories have diverged."
                return [pscustomobject]$result
            }

            $result.state   = 'behind'
            $result.isStale = $true
            $result.remedy  = "git -C <repo> pull --ff-only $Remote $BaseBranch"
            $result.summary = "This clone is $behind commit(s) behind $branchLabel. Anything generated from it was computed against out-of-date content."
            return [pscustomobject]$result
        }
    }

    # The SHAs differ and the remote tip is absent locally (or the count could
    # not be taken): the clone is behind by an amount only a fetch can name.
    $result.state        = 'behind-unknown-count'
    $result.isStale      = $true
    $result.behindCount  = $null
    $result.countIsExact = $false
    $result.remedy       = "git -C <repo> fetch $Remote && git -C <repo> pull --ff-only $Remote $BaseBranch"
    $result.summary      = "$branchLabel has commits this clone does not have. The exact count needs a fetch; what is certain is that it is not zero."
    return [pscustomobject]$result
}

function Get-RepoBaseFreshness {
    <#
    .SYNOPSIS
        Impure — ask the remote where its base branch is, and compare.
    .DESCRIPTION
        One `git ls-remote` round trip. Never fetches, never mutates the working
        tree, and never throws: every failure degrades to an 'unknown' reading
        carrying the reason, because a write path must not die inside the guard
        that exists to protect it.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()][AllowEmptyString()][string]$RepoPath = '',
        [Parameter()][AllowEmptyString()][string]$BaseBranch = '',
        [Parameter()][AllowEmptyString()][string]$Remote = 'origin',
        [Parameter()][int]$TimeoutSeconds = $script:BaseFreshnessTimeoutSeconds
    )

    if ([string]::IsNullOrWhiteSpace($RepoPath) -or -not (Test-Path -LiteralPath (Join-Path $RepoPath '.git'))) {
        return Resolve-BaseFreshness -BaseBranch $BaseBranch -Remote $Remote -ProbeError 'the path is not a git working copy'
    }

    if ([string]::IsNullOrWhiteSpace($Remote)) { $Remote = 'origin' }

    # Resolve the base branch if the caller did not name one.
    $branch = $BaseBranch
    if ([string]::IsNullOrWhiteSpace($branch)) {
        $headRef = (& git -C $RepoPath symbolic-ref --quiet --short HEAD 2>&1) | Out-String
        if ($LASTEXITCODE -eq 0) { $branch = $headRef.Trim() }
    }
    if ([string]::IsNullOrWhiteSpace($branch)) {
        return Resolve-BaseFreshness -Remote $Remote -ProbeError 'HEAD is detached, so there is no base branch to compare against'
    }

    $localSha = ''
    $rev = (& git -C $RepoPath rev-parse HEAD 2>&1) | Out-String
    if ($LASTEXITCODE -eq 0) { $localSha = $rev.Trim() }
    if ([string]::IsNullOrWhiteSpace($localSha)) {
        return Resolve-BaseFreshness -BaseBranch $branch -Remote $Remote -ProbeError 'the clone has no commits'
    }

    # The network call. `ls-remote` returns "<sha>\t<ref>" and downloads no
    # objects, which is what makes this affordable on a write path.
    $remoteSha = ''
    $probeError = ''
    try {
        $lsOutput = (& git -C $RepoPath -c ("http.lowSpeedLimit=1") -c ("http.lowSpeedTime={0}" -f $TimeoutSeconds) `
                ls-remote --heads $Remote $branch 2>&1) | Out-String
        if ($LASTEXITCODE -ne 0) {
            $probeError = ("could not reach remote '{0}' ({1})" -f $Remote, ($lsOutput.Trim() -split "`n" | Select-Object -First 1))
        }
        else {
            $line = @($lsOutput -split "`n" | Where-Object { $_ -match '\S' }) | Select-Object -First 1
            if ($null -ne $line -and $line -match '^([0-9a-f]{40})\s') { $remoteSha = $Matches[1] }
            else { $probeError = ("remote '{0}' has no branch '{1}'" -f $Remote, $branch) }
        }
    }
    catch {
        $probeError = ("the remote probe failed: {0}" -f $_.Exception.Message)
    }

    if ([string]::IsNullOrWhiteSpace($remoteSha)) {
        return Resolve-BaseFreshness -LocalSha $localSha -BaseBranch $branch -Remote $Remote -ProbeError $probeError
    }

    # Is the remote tip already in the local object store? If so exact counts are
    # available with no network and no fetch.
    $present = $false
    $behind = $null
    $ahead = $null
    $null = (& git -C $RepoPath cat-file -e ("{0}^{{commit}}" -f $remoteSha) 2>&1)
    if ($LASTEXITCODE -eq 0) {
        $present = $true
        # `--left-right --count A...B` reports both sides from one walk: left is
        # what HEAD has and the remote does not (ahead), right is the reverse
        # (behind). Two separate rev-list calls would answer the same question
        # twice and could disagree if a ref moved between them.
        $countOut = (& git -C $RepoPath rev-list --left-right --count ("HEAD...{0}" -f $remoteSha) 2>&1) | Out-String
        if ($LASTEXITCODE -eq 0 -and $countOut.Trim() -match '^(\d+)\s+(\d+)$') {
            $ahead = [int]$Matches[1]
            $behind = [int]$Matches[2]
        }
    }

    return Resolve-BaseFreshness -LocalSha $localSha -RemoteSha $remoteSha `
        -RemoteObjectPresentLocally $present -BehindCount $behind -AheadCount $ahead `
        -BaseBranch $branch -Remote $Remote
}
