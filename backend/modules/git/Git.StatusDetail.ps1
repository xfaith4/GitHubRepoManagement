<#
.SYNOPSIS
    Git status detail functions for the GitHubRepoManagement API host.

.DESCRIPTION
    Provides per-file status inspection, stash, and discard operations
    for local git repositories.
#>

# ── Get-RepoGitStatusDetail ───────────────────────────────────────────────────

function Get-RepoGitStatusDetail {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$LocalPath,
        [Parameter(Mandatory)][string]$RepoName
    )

    if (-not (Test-Path -LiteralPath $LocalPath -PathType Container)) {
        throw "LocalPath not found: $LocalPath"
    }

    $gitDir = Join-Path $LocalPath '.git'
    if (-not (Test-Path -LiteralPath $gitDir)) {
        throw "Not a git repository: $LocalPath"
    }

    # ── Detect mid-rebase / mid-merge ─────────────────────────────────────────
    $isMidMerge  = Test-Path -LiteralPath (Join-Path $gitDir 'MERGE_HEAD')
    $isMidRebase = Test-Path -LiteralPath (Join-Path $gitDir 'rebase-merge')

    # ── Branch name ───────────────────────────────────────────────────────────
    $branchOutput = & git -C $LocalPath rev-parse --abbrev-ref HEAD 2>&1
    $branch = if ($LASTEXITCODE -eq 0) { ($branchOutput | Out-String).Trim() } else { 'HEAD' }

    # ── Upstream tracking branch ──────────────────────────────────────────────
    $upstreamOutput = & git -C $LocalPath rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>&1
    $upstream = if ($LASTEXITCODE -eq 0) { ($upstreamOutput | Out-String).Trim() } else { '' }
    $hasUpstream = -not [string]::IsNullOrWhiteSpace($upstream)

    # ── git status --porcelain=v1 ─────────────────────────────────────────────
    $porcelainOutput = & git -C $LocalPath status --porcelain=v1 2>&1
    $porcelainLines  = @(if ($LASTEXITCODE -eq 0) { @($porcelainOutput) } else { @() })

    $stagedFiles    = [System.Collections.Generic.List[object]]::new()
    $unstagedFiles  = [System.Collections.Generic.List[object]]::new()
    $untrackedFiles = [System.Collections.Generic.List[object]]::new()
    $conflictedFiles= [System.Collections.Generic.List[object]]::new()

    foreach ($line in $porcelainLines) {
        if ($line.Length -lt 3) { continue }
        $x    = $line[0]     # index (staged) status
        $y    = $line[1]     # worktree status
        $path = $line.Substring(3)

        # Rename: "R old -> new" or "R old\0new" in porcelain v1 with space separator
        $origPath = $null
        if ($x -eq 'R' -or $x -eq 'C') {
            if ($path -match '^(.+) -> (.+)$') {
                $origPath = $Matches[1]
                $path     = $Matches[2]
            }
        }

        $fileEntry = [pscustomobject]@{ status = [string]$x; path = $path; origPath = $origPath }

        if ($x -eq '?' -and $y -eq '?') {
            # Untracked
            $untrackedFiles.Add([pscustomobject]@{ status = '?'; path = $path; origPath = $null })
            continue
        }

        # Conflicted: both X and Y are non-space and represent conflict markers
        $conflictXY = @('U', 'A', 'D')
        $isConflict = ($conflictXY -contains [string]$x -and $conflictXY -contains [string]$y) -or
                      ($x -eq 'D' -and $y -eq 'D') -or ($x -eq 'A' -and $y -eq 'A') -or
                      ($x -eq 'U') -or ($y -eq 'U')
        if ($isConflict) {
            $conflictedFiles.Add($fileEntry)
            continue
        }

        # Staged: index status is set (not space)
        if ($x -ne ' ' -and $x -ne '?') {
            $stagedFiles.Add($fileEntry)
        }

        # Unstaged: worktree status is M or D and index is clean (space)
        if (($y -eq 'M' -or $y -eq 'D') -and $x -eq ' ') {
            $unstagedFiles.Add([pscustomobject]@{ status = [string]$y; path = $path; origPath = $null })
        }
    }

    # ── Commit logs ───────────────────────────────────────────────────────────
    $unpushedCommits = @()
    $unpulledCommits = @()

    if ($hasUpstream) {
        $pushedOut  = & git -C $LocalPath log "$upstream..HEAD" --oneline 2>&1
        if ($LASTEXITCODE -eq 0) {
            $unpushedCommits = @($pushedOut | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object {
                if ($_ -match '^([0-9a-f]+)\s+(.+)$') {
                    [pscustomobject]@{ hash = $Matches[1]; message = $Matches[2] }
                }
            } | Where-Object { $null -ne $_ })
        }

        $pulledOut  = & git -C $LocalPath log "HEAD..$upstream" --oneline 2>&1
        if ($LASTEXITCODE -eq 0) {
            $unpulledCommits = @($pulledOut | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object {
                if ($_ -match '^([0-9a-f]+)\s+(.+)$') {
                    [pscustomobject]@{ hash = $Matches[1]; message = $Matches[2] }
                }
            } | Where-Object { $null -ne $_ })
        }
    }

    # ── Stash count ───────────────────────────────────────────────────────────
    $stashOut  = & git -C $LocalPath stash list 2>&1
    $stashList = @($stashOut | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $stashCount= $stashList.Count

    return [pscustomobject]@{
        repoName        = $RepoName
        localPath       = $LocalPath
        branch          = $branch
        upstream        = if ($hasUpstream) { $upstream } else { '' }
        isMidMerge      = $isMidMerge
        isMidRebase     = $isMidRebase
        stagedFiles     = @($stagedFiles)
        unstagedFiles   = @($unstagedFiles)
        untrackedFiles  = @($untrackedFiles)
        conflictedFiles = @($conflictedFiles)
        stagedCount     = $stagedFiles.Count
        unstagedCount   = $unstagedFiles.Count
        untrackedCount  = $untrackedFiles.Count
        conflictedCount = $conflictedFiles.Count
        unpushedCommits = $unpushedCommits
        unpulledCommits = $unpulledCommits
        unpushedCount   = $unpushedCommits.Count
        unpulledCount   = $unpulledCommits.Count
        stashCount      = $stashCount
        scannedAt       = (Get-Date).ToUniversalTime().ToString('o')
    }
}

# ── Invoke-GitStash ───────────────────────────────────────────────────────────

function Invoke-GitStash {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$LocalPath
    )

    if (-not (Test-Path -LiteralPath $LocalPath -PathType Container)) {
        throw "LocalPath not found: $LocalPath"
    }

    $label = "Stashed by GitHubRepoManagement $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
    $stashOut = & git -C $LocalPath stash push --include-untracked -m $label 2>&1
    $exitCode = $LASTEXITCODE
    $outputText = ($stashOut | Out-String).Trim()

    if ($exitCode -ne 0) {
        return [pscustomobject]@{
            success  = $false
            output   = $outputText
            stashRef = $null
        }
    }

    # Extract stash ref from output (e.g. "Saved working directory and index state stash@{0}")
    $stashRef = $null
    if ($outputText -match 'stash@\{\d+\}') {
        $stashRef = $Matches[0]
    }

    return [pscustomobject]@{
        success  = $true
        output   = $outputText
        stashRef = $stashRef
    }
}

# ── Invoke-GitDiscard ─────────────────────────────────────────────────────────

function Invoke-GitDiscard {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$LocalPath,
        [bool]$IncludeUntracked = $false
    )

    if (-not (Test-Path -LiteralPath $LocalPath -PathType Container)) {
        throw "LocalPath not found: $LocalPath"
    }

    # Step 1: Unstage any staged changes so checkout can restore them
    $resetOut = & git -C $LocalPath reset HEAD -- . 2>&1
    $outputLines = @($resetOut)

    # Step 2: Restore tracked files (discards both staged-then-unstaged and unstaged changes)
    $checkoutOut  = & git -C $LocalPath checkout -- . 2>&1
    $checkoutExit = $LASTEXITCODE
    $outputLines += $checkoutOut

    # Count files restored from checkout output (lines like "Updated 3 paths...")
    $filesRestored = 0
    foreach ($line in $checkoutOut) {
        if ($line -match 'Updated (\d+) path') { $filesRestored += [int]$Matches[1] }
    }

    $filesRemoved = 0
    if ($IncludeUntracked) {
        $cleanOut  = & git -C $LocalPath clean -fd 2>&1
        $cleanExit = $LASTEXITCODE
        $outputLines += $cleanOut
        $filesRemoved = @($cleanOut | Where-Object { $_ -match '^Removing ' }).Count
        if ($cleanExit -ne 0) {
            return [pscustomobject]@{
                success       = $false
                output        = ($outputLines | Out-String).Trim()
                filesRestored = $filesRestored
                filesRemoved  = 0
            }
        }
    }

    if ($checkoutExit -ne 0) {
        return [pscustomobject]@{
            success       = $false
            output        = ($outputLines | Out-String).Trim()
            filesRestored = 0
            filesRemoved  = 0
        }
    }

    return [pscustomobject]@{
        success       = $true
        output        = ($outputLines | Out-String).Trim()
        filesRestored = $filesRestored
        filesRemoved  = $filesRemoved
    }
}
