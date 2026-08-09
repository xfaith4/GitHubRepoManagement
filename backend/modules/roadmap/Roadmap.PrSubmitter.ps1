Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
    Release 2.7 Phase A — live submit-PR for a roadmap repair.

    Until 2026-08-09 `POST /api/roadmap/repair/submit-pr` was a plan builder:
    even with createPr=true it returned created=false / prUrl=null and a note
    saying no branch was pushed. The roadmap recorded this as "only the live
    round trip is missing", which read as a credentials gate — but the write
    path itself had never been implemented.

    The pure helpers here (branch naming, remote-slug parsing, precondition
    checks) are separated from the single impure entry point so the refusal
    rules can be unit-tested without a git checkout or a GitHub token. Every
    refusal is a NAMED reason: a submit that silently does nothing is the
    failure mode this whole feature exists to remove.
#>

function Get-RoadmapRepairBranchName {
    [CmdletBinding()]
    param(
        [Parameter()][datetime]$NowUtc = ([datetime]::UtcNow),
        [Parameter()][string]$Prefix = 'roadmap-repair'
    )
    return ('{0}/{1}' -f $Prefix, $NowUtc.ToString('yyyyMMdd-HHmmss'))
}

function Resolve-GitHubRepoSlug {
    <#
        .SYNOPSIS
            Parse "owner/repo" out of a git remote URL.
        .DESCRIPTION
            Handles the three forms a portfolio repo actually carries:
            https://github.com/o/r(.git), git@github.com:o/r(.git), and
            ssh://git@github.com/o/r(.git). Returns $null for anything that is
            not a GitHub remote — a non-GitHub origin must refuse loudly rather
            than have a slug guessed for it.
    #>
    [CmdletBinding()]
    param([AllowEmptyString()][string]$RemoteUrl = '')

    if ([string]::IsNullOrWhiteSpace($RemoteUrl)) { return $null }
    $url = $RemoteUrl.Trim()

    $patterns = @(
        '^https?://(?:[^@/]+@)?github\.com/(?<owner>[^/]+)/(?<repo>[^/]+?)(?:\.git)?/?$'
        '^git@github\.com:(?<owner>[^/]+)/(?<repo>[^/]+?)(?:\.git)?/?$'
        '^ssh://git@github\.com/(?<owner>[^/]+)/(?<repo>[^/]+?)(?:\.git)?/?$'
    )
    foreach ($pattern in $patterns) {
        $m = [regex]::Match($url, $pattern)
        if ($m.Success) {
            return [pscustomobject]@{
                owner = $m.Groups['owner'].Value
                repo  = $m.Groups['repo'].Value
                slug  = ('{0}/{1}' -f $m.Groups['owner'].Value, $m.Groups['repo'].Value)
            }
        }
    }
    return $null
}

function Test-RoadmapRepairPrPreconditions {
    <#
        .SYNOPSIS
            Every reason a live submit-PR must refuse, evaluated as data.
        .DESCRIPTION
            Returns @{ ok = [bool]; reason = [string]; category = [string] }.
            Pure: takes already-gathered facts rather than probing the disk, so
            the refusal matrix is unit-testable. The caller gathers the facts.
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyString()][string]$RepoPath = '',
        [AllowEmptyString()][string]$RoadmapPath = '',
        [AllowEmptyString()][string]$ProposedContent = '',
        [AllowEmptyString()][string]$CurrentContent = '',
        [AllowEmptyString()][string]$Token = '',
        [AllowNull()][object]$Slug = $null,
        [bool]$IsGitRepo = $false,
        [bool]$WorkingTreeDirty = $false,
        [AllowEmptyString()][string]$BaseBranch = 'main'
    )

    if ([string]::IsNullOrWhiteSpace($RepoPath)) {
        return @{ ok = $false; category = 'validation'; reason = 'No local repo path is known for this repo. Run a scan so the roadmap index resolves its repoPath.' }
    }
    if (-not $IsGitRepo) {
        return @{ ok = $false; category = 'validation'; reason = ("'{0}' is not a git working copy, so there is nothing to branch from." -f $RepoPath) }
    }
    if ([string]::IsNullOrWhiteSpace($RoadmapPath)) {
        return @{ ok = $false; category = 'validation'; reason = 'No roadmap path is known for this repo, so there is no file to commit.' }
    }
    if ([string]::IsNullOrWhiteSpace($ProposedContent)) {
        return @{ ok = $false; category = 'validation'; reason = 'proposedContent is required for a live PR — refusing to open a PR with no change.' }
    }
    if ($ProposedContent -eq $CurrentContent) {
        return @{ ok = $false; category = 'no-op'; reason = 'The proposed roadmap is byte-identical to the current one. Refusing to open an empty PR.' }
    }
    if ([string]::IsNullOrWhiteSpace($Token)) {
        return @{ ok = $false; category = 'auth'; reason = 'No GitHub token resolved. Set the configured token environment variable (Machine scope for the service) with Contents+PullRequests write access.' }
    }
    if ($null -eq $Slug) {
        return @{ ok = $false; category = 'validation'; reason = "The repo's origin remote is not a recognizable GitHub URL, so there is no target to open a PR against." }
    }
    # A dirty tree is refused rather than stashed: committing alongside unrelated
    # operator edits would put work nobody reviewed into an automated PR.
    if ($WorkingTreeDirty) {
        return @{ ok = $false; category = 'conflict'; reason = 'The working tree has uncommitted changes. Commit or stash them first — refusing to sweep unrelated edits into an automated PR.' }
    }
    if ([string]::IsNullOrWhiteSpace($BaseBranch)) {
        return @{ ok = $false; category = 'validation'; reason = 'No base branch resolved for the PR.' }
    }
    return @{ ok = $true; category = ''; reason = '' }
}

function Get-GitRemoteUrl {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RepoPath, [string]$Remote = 'origin')
    $out = (& git -C $RepoPath remote get-url $Remote 2>&1) | Out-String
    if ($LASTEXITCODE -ne 0) { return '' }
    return $out.Trim()
}

function Test-GitWorkingTreeDirty {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RepoPath)
    $out = (& git -C $RepoPath status --porcelain 2>&1) | Out-String
    if ($LASTEXITCODE -ne 0) { return $true }
    return -not [string]::IsNullOrWhiteSpace($out.Trim())
}

function Get-GitCurrentBranch {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RepoPath)
    $out = (& git -C $RepoPath rev-parse --abbrev-ref HEAD 2>&1) | Out-String
    if ($LASTEXITCODE -ne 0) { return '' }
    return $out.Trim()
}

function Get-GitTokenPushArgs {
    <#
        .SYNOPSIS
            Auth args for a push by a service account with no credential manager.
        .DESCRIPTION
            Same http.extraheader approach the agent-run approve-push path uses.
            The token never reaches the command line as a plain argument; it is
            base64'd into a header value, so it does not appear in `ps` output
            in cleartext. It IS still sensitive — never log the result.
    #>
    [CmdletBinding()]
    param([AllowEmptyString()][string]$Token = '')

    if ([string]::IsNullOrWhiteSpace($Token)) { return @() }
    $basic = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("x-access-token:{0}" -f $Token)))
    return @('-c', ("http.extraheader=AUTHORIZATION: basic {0}" -f $basic))
}

function Invoke-RoadmapRepairPrSubmission {
    <#
        .SYNOPSIS
            Branch, commit the repaired roadmap, push, and open the PR.
        .DESCRIPTION
            The one impure entry point. Returns a result object; throws only on
            genuinely unexpected failures. Guarantees:
              - never force-pushes, and never commits onto the base branch
              - always returns to the branch it started on
              - refuses (with a named reason) rather than opening an empty PR
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$RepoName,
        # AllowEmptyString, NOT Mandatory: an unresolved repoPath / roadmapPath
        # (the repo is not in the roadmap index yet) and a missing
        # proposedContent are the most common real refusals, and each has a
        # named reason in Test-RoadmapRepairPrPreconditions below. Declaring
        # them Mandatory made PowerShell throw a parameter-binding error first —
        # so the caller got an opaque 500 "Cannot bind argument to parameter
        # 'RepoPath'" instead of the 409 explaining what to fix. Same shape as
        # the linter crashes fixed earlier today: the guard must not die before
        # the diagnostic it exists to produce.
        [Parameter()][AllowEmptyString()][string]$RepoPath = '',
        [Parameter()][AllowEmptyString()][string]$RoadmapPath = '',
        [Parameter()][AllowEmptyString()][string]$ProposedContent = '',
        [Parameter()][AllowEmptyString()][string]$PreviewId = '',
        [Parameter()][AllowEmptyString()][string]$Token = '',
        [Parameter()][AllowEmptyString()][string]$BaseBranch = '',
        [Parameter()][AllowEmptyString()][string]$BranchName = '',
        [Parameter()][hashtable]$ApiHeaders = $null
    )

    $isGitRepo = (-not [string]::IsNullOrWhiteSpace($RepoPath)) -and (Test-Path -LiteralPath (Join-Path $RepoPath '.git'))
    $remoteUrl = if ($isGitRepo) { Get-GitRemoteUrl -RepoPath $RepoPath } else { '' }
    $slug      = Resolve-GitHubRepoSlug -RemoteUrl $remoteUrl
    $dirty     = if ($isGitRepo) { Test-GitWorkingTreeDirty -RepoPath $RepoPath } else { $false }
    $current   = if (Test-Path -LiteralPath $RoadmapPath) { Get-Content -LiteralPath $RoadmapPath -Raw -Encoding UTF8 } else { '' }
    $startBranch = if ($isGitRepo) { Get-GitCurrentBranch -RepoPath $RepoPath } else { '' }
    $effectiveBase = if (-not [string]::IsNullOrWhiteSpace($BaseBranch)) { $BaseBranch } elseif (-not [string]::IsNullOrWhiteSpace($startBranch)) { $startBranch } else { 'main' }

    $check = Test-RoadmapRepairPrPreconditions -RepoPath $RepoPath -RoadmapPath $RoadmapPath `
        -ProposedContent $ProposedContent -CurrentContent $current -Token $Token -Slug $slug `
        -IsGitRepo $isGitRepo -WorkingTreeDirty $dirty -BaseBranch $effectiveBase
    if (-not $check.ok) {
        return [pscustomobject]@{
            created = $false; refused = $true; reason = $check.reason; category = $check.category
            branch = ''; prUrl = $null; prNumber = $null; slug = $(if ($null -ne $slug) { $slug.slug } else { '' })
        }
    }

    $branch = if (-not [string]::IsNullOrWhiteSpace($BranchName)) { $BranchName } else { Get-RoadmapRepairBranchName }
    if ($branch -eq $effectiveBase) {
        return [pscustomobject]@{
            created = $false; refused = $true; category = 'validation'
            reason = ("Refusing to commit directly onto the base branch '{0}'." -f $effectiveBase)
            branch = $branch; prUrl = $null; prNumber = $null; slug = $slug.slug
        }
    }

    if (-not $PSCmdlet.ShouldProcess(("{0} ({1})" -f $RepoName, $slug.slug), ("open roadmap-repair PR from branch '{0}'" -f $branch))) {
        return [pscustomobject]@{
            created = $false; refused = $true; category = 'whatif'
            reason = 'WhatIf: no branch created, nothing pushed, no PR opened.'
            branch = $branch; prUrl = $null; prNumber = $null; slug = $slug.slug
        }
    }

    $pushArgs = Get-GitTokenPushArgs -Token $Token
    $restoreBranch = $startBranch
    try {
        $co = (& git -C $RepoPath checkout -b $branch 2>&1) | Out-String
        if ($LASTEXITCODE -ne 0) { throw ("git checkout -b '{0}' failed: {1}" -f $branch, $co.Trim()) }

        # Preserve the file's trailing newline. Writing the caller's content
        # verbatim let a proposal that happened to end at the last character
        # strip it, which git reports as "\ No newline at end of file" and
        # markdownlint fails as MD047 — a repair tool quietly damaging the file
        # it was asked to improve. Only ADD one; never strip or double it.
        $contentToWrite = if ($ProposedContent.EndsWith("`n")) { $ProposedContent } else { $ProposedContent + "`n" }
        Set-Content -LiteralPath $RoadmapPath -Value $contentToWrite -Encoding UTF8 -NoNewline

        $add = (& git -C $RepoPath add -- $RoadmapPath 2>&1) | Out-String
        if ($LASTEXITCODE -ne 0) { throw ("git add failed: {0}" -f $add.Trim()) }

        $message = if ([string]::IsNullOrWhiteSpace($PreviewId)) {
            ("docs(roadmap): automated roadmap repair for {0}" -f $RepoName)
        } else {
            ("docs(roadmap): automated roadmap repair for {0} (preview {1})" -f $RepoName, $PreviewId)
        }
        $commit = (& git -C $RepoPath commit -m $message 2>&1) | Out-String
        if ($LASTEXITCODE -ne 0) { throw ("git commit failed: {0}" -f $commit.Trim()) }

        # -u origin <branch>, never --force: an automated path must not be able
        # to overwrite a branch someone else is using.
        $push = (& git -C $RepoPath @pushArgs push -u origin $branch 2>&1) | Out-String
        if ($LASTEXITCODE -ne 0) { throw ("git push failed for '{0}': {1}" -f $branch, $push.Trim()) }

        $headers = if ($null -ne $ApiHeaders) { $ApiHeaders } else { @{ Authorization = ("Bearer {0}" -f $Token); 'User-Agent' = 'GitHubRepoManagement'; Accept = 'application/vnd.github+json' } }
        $prBody = @{
            title = ("Roadmap repair: {0}" -f $RepoName)
            head  = $branch
            base  = $effectiveBase
            body  = ("Automated roadmap repair for **{0}**.{1}`n`nGenerated by GitHubRepoManagement (Release 2.7 Phase A). Review the diff before merging — nothing here has been applied to {2}." -f `
                        $RepoName, $(if ($PreviewId) { " Based on repair preview ``$PreviewId``." } else { '' }), $effectiveBase)
        } | ConvertTo-Json -Depth 5

        $prUri = ("https://api.github.com/repos/{0}/{1}/pulls" -f $slug.owner, $slug.repo)
        $pr = Invoke-RestMethod -Uri $prUri -Headers $headers -Method Post -Body $prBody -ContentType 'application/json'

        return [pscustomobject]@{
            created = $true; refused = $false; reason = ''; category = ''
            branch = $branch; baseBranch = $effectiveBase; slug = $slug.slug
            prUrl = [string]$pr.html_url; prNumber = [int]$pr.number
            commitMessage = $message
        }
    }
    finally {
        # Always land the operator back where they started, even on failure —
        # a half-finished submit must not leave the checkout on a stray branch.
        if (-not [string]::IsNullOrWhiteSpace($restoreBranch) -and $restoreBranch -ne $branch) {
            & git -C $RepoPath checkout $restoreBranch 2>&1 | Out-Null
        }
    }
}
