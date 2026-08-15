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

function _PrSubmitterField {
    # Read a property off either a hashtable or a PSCustomObject without
    # tripping StrictMode on an absent name.
    param([object]$Obj, [string]$Name, [object]$Default = $null)
    if ($null -eq $Obj) { return $Default }
    if ($Obj -is [System.Collections.IDictionary]) {
        if ($Obj.Contains($Name) -and $null -ne $Obj[$Name]) { return $Obj[$Name] }
        return $Default
    }
    if ($null -ne $Obj.PSObject -and ($Obj.PSObject.Properties.Name -contains $Name)) {
        $v = $Obj.$Name
        if ($null -ne $v) { return $v }
    }
    return $Default
}

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
    # Declared rather than inferred: every branch returns a hashtable, and
    # saying so clears the analyzer findings this function has carried since it
    # was written instead of adding one more with the stale-base refusal.
    [OutputType([hashtable])]
    param(
        [AllowEmptyString()][string]$RepoPath = '',
        [AllowEmptyString()][string]$RoadmapPath = '',
        [AllowEmptyString()][string]$ProposedContent = '',
        [AllowEmptyString()][string]$CurrentContent = '',
        [AllowEmptyString()][string]$Token = '',
        [AllowNull()][object]$Slug = $null,
        [bool]$IsGitRepo = $false,
        [bool]$WorkingTreeDirty = $false,
        [AllowEmptyString()][string]$BaseBranch = 'main',
        # Release 3.1 — the tenth refusal. A reading from Get-RepoBaseFreshness;
        # $null means the caller did not check, which is treated as unverified
        # rather than as fresh.
        [AllowNull()][object]$BaseFreshness = $null,
        [bool]$AcknowledgeStaleBase = $false
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
    # A stale base is refused rather than merged: the danger is not a conflict
    # (git add stages one file, and GitHub's three-way merge makes a real
    # conflict visible) but that the PROPOSAL was computed from out-of-date
    # content — re-adding what upstream already fixed, or missing context added
    # since. That merges cleanly and reads as correct in review, which is why it
    # has to be stopped before the branch exists rather than caught after.
    if ($null -ne $BaseFreshness) {
        $freshnessState = [string](_PrSubmitterField -Obj $BaseFreshness -Name 'state' -Default 'unknown')
        if ([bool](_PrSubmitterField -Obj $BaseFreshness -Name 'isStale' -Default $false)) {
            if (-not $AcknowledgeStaleBase) {
                $count = _PrSubmitterField -Obj $BaseFreshness -Name 'behindCount' -Default $null
                $howFar = if ($null -ne $count) { "$count commit(s) behind" } else { 'behind by an amount only a fetch can name' }
                $remedy = [string](_PrSubmitterField -Obj $BaseFreshness -Name 'remedy' -Default '')
                $branch = [string](_PrSubmitterField -Obj $BaseFreshness -Name 'baseBranch' -Default $BaseBranch)
                $reason = "This clone is $howFar its remote $branch, so the proposed roadmap was generated from out-of-date content. Refusing to open a PR from a stale base."
                if (-not [string]::IsNullOrWhiteSpace($remedy)) { $reason += " Run: $remedy" }
                return @{ ok = $false; category = 'stale-base'; reason = $reason; freshnessState = $freshnessState }
            }
        }
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

function Test-RepoBranchPrReadiness {
    <#
        .SYNOPSIS
            Every reason opening a PR for an existing branch must refuse.
        .DESCRIPTION
            Release 3.4 milestone 3. The refusal matrix for opening a pull
            request from a branch that ALREADY carries its commits — the half of
            Invoke-RoadmapRepairPrSubmission that has nothing to do with writing
            a roadmap file. Pure, same contract as
            Test-RoadmapRepairPrPreconditions: facts in, named verdict out.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [AllowEmptyString()][string]$RepoPath = '',
        [AllowEmptyString()][string]$Branch = '',
        [AllowEmptyString()][string]$BaseBranch = '',
        [AllowEmptyString()][string]$Token = '',
        [AllowNull()][object]$Slug = $null,
        [bool]$IsGitRepo = $false,
        [bool]$BranchExists = $false
    )

    if ([string]::IsNullOrWhiteSpace($RepoPath)) {
        return @{ ok = $false; category = 'validation'; reason = 'No local repo path was provided, so there is no checkout to open a PR from.' }
    }
    if (-not $IsGitRepo) {
        return @{ ok = $false; category = 'validation'; reason = ("'{0}' is not a git working copy." -f $RepoPath) }
    }
    if ([string]::IsNullOrWhiteSpace($Branch)) {
        return @{ ok = $false; category = 'validation'; reason = 'No branch name was provided — there is nothing to open a PR for.' }
    }
    if (-not $BranchExists) {
        return @{ ok = $false; category = 'validation'; reason = ("Branch '{0}' does not exist in this checkout, so there is nothing to push or open." -f $Branch) }
    }
    if ([string]::IsNullOrWhiteSpace($BaseBranch)) {
        return @{ ok = $false; category = 'validation'; reason = 'No base branch resolved for the PR.' }
    }
    if ($Branch -eq $BaseBranch) {
        return @{ ok = $false; category = 'validation'; reason = ("Branch and base are both '{0}' — a PR from a branch onto itself is meaningless, and the invariant forbids treating the base branch as a work branch." -f $Branch) }
    }
    if ([string]::IsNullOrWhiteSpace($Token)) {
        return @{ ok = $false; category = 'auth'; reason = 'No GitHub token resolved. Set the configured token environment variable (Contents+PullRequests write access) — a PR cannot be opened without one.' }
    }
    if ($null -eq $Slug) {
        return @{ ok = $false; category = 'validation'; reason = "The repo's origin remote is not a recognizable GitHub URL, so there is no target to open a PR against." }
    }
    return @{ ok = $true; category = ''; reason = '' }
}

function Open-RepoBranchPullRequest {
    <#
        .SYNOPSIS
            Push (optionally) and open a pull request for an existing branch.
        .DESCRIPTION
            Release 3.4 milestone 3 — the branch-and-PR half of
            Invoke-RoadmapRepairPrSubmission, extracted so ANY caller with a
            committed branch reaches GitHub through one refusal matrix. Before
            this function, that logic was reachable from exactly one caller
            (the roadmap-repair submit), because it was entangled with writing
            the roadmap file — which is why an agent run ended at "Open the PR
            from GitHub when ready".

            Guarantees, same as the parent:
              - never force-pushes, never pushes the base branch
              - refuses with a NAMED reason rather than doing nothing silently
              - a PR that already exists for the branch is returned as
                `alreadyExisted = $true`, not surfaced as a raw 422 — approving
                twice must be idempotent, not an error.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$RepoName,
        [Parameter()][AllowEmptyString()][string]$RepoPath = '',
        [Parameter()][AllowEmptyString()][string]$Branch = '',
        [Parameter()][AllowEmptyString()][string]$BaseBranch = '',
        [Parameter()][AllowEmptyString()][string]$Title = '',
        [Parameter()][AllowEmptyString()][string]$Body = '',
        [Parameter()][AllowEmptyString()][string]$Token = '',
        [Parameter()][hashtable]$ApiHeaders = $null,
        # Push before opening. Off when the caller has already pushed (the
        # approve-push route proves its push by exit code before calling here).
        [Parameter()][switch]$PushFirst
    )

    $isGitRepo = (-not [string]::IsNullOrWhiteSpace($RepoPath)) -and (Test-Path -LiteralPath (Join-Path $RepoPath '.git'))
    $remoteUrl = if ($isGitRepo) { Get-GitRemoteUrl -RepoPath $RepoPath } else { '' }
    $slug      = Resolve-GitHubRepoSlug -RemoteUrl $remoteUrl

    $branchExists = $false
    if ($isGitRepo -and -not [string]::IsNullOrWhiteSpace($Branch)) {
        & git -C $RepoPath rev-parse --verify --quiet ("refs/heads/{0}" -f $Branch) 2>&1 | Out-Null
        $branchExists = ($LASTEXITCODE -eq 0)
    }

    $effectiveBase = if (-not [string]::IsNullOrWhiteSpace($BaseBranch)) { $BaseBranch } else { 'main' }

    $check = Test-RepoBranchPrReadiness -RepoPath $RepoPath -Branch $Branch -BaseBranch $effectiveBase `
        -Token $Token -Slug $slug -IsGitRepo $isGitRepo -BranchExists $branchExists
    if (-not $check.ok) {
        return [pscustomobject]@{
            created = $false; refused = $true; reason = $check.reason; category = $check.category
            branch = $Branch; baseBranch = $effectiveBase; prUrl = $null; prNumber = $null
            slug = $(if ($null -ne $slug) { $slug.slug } else { '' }); alreadyExisted = $false
        }
    }

    if (-not $PSCmdlet.ShouldProcess(("{0} ({1})" -f $RepoName, $slug.slug), ("open PR from branch '{0}' onto '{1}'" -f $Branch, $effectiveBase))) {
        return [pscustomobject]@{
            created = $false; refused = $true; category = 'whatif'
            reason = 'WhatIf: nothing pushed, no PR opened.'
            branch = $Branch; baseBranch = $effectiveBase; prUrl = $null; prNumber = $null
            slug = $slug.slug; alreadyExisted = $false
        }
    }

    if ($PushFirst) {
        $pushArgs = Get-GitTokenPushArgs -Token $Token
        # -u origin <branch>, never --force: an automated path must not be able
        # to overwrite a branch someone else is using.
        $push = (& git -C $RepoPath @pushArgs push -u origin $Branch 2>&1) | Out-String
        if ($LASTEXITCODE -ne 0) { throw ("git push failed for '{0}': {1}" -f $Branch, $push.Trim()) }
    }

    $headers = if ($null -ne $ApiHeaders) { $ApiHeaders } else { @{ Authorization = ("Bearer {0}" -f $Token); 'User-Agent' = 'GitHubRepoManagement'; Accept = 'application/vnd.github+json' } }
    $effectiveTitle = if (-not [string]::IsNullOrWhiteSpace($Title)) { $Title } else { ("{0}: {1}" -f $RepoName, $Branch) }
    $prPayload = @{ title = $effectiveTitle; head = $Branch; base = $effectiveBase; body = [string]$Body } | ConvertTo-Json -Depth 5
    $prUri = ("https://api.github.com/repos/{0}/{1}/pulls" -f $slug.owner, $slug.repo)

    try {
        $pr = Invoke-RestMethod -Uri $prUri -Headers $headers -Method Post -Body $prPayload -ContentType 'application/json'
        return [pscustomobject]@{
            created = $true; refused = $false; reason = ''; category = ''
            branch = $Branch; baseBranch = $effectiveBase; slug = $slug.slug
            prUrl = [string]$pr.html_url; prNumber = [int]$pr.number; alreadyExisted = $false
        }
    }
    catch {
        # GitHub answers 422 when a PR already exists for this head. That is a
        # success from the operator's point of view — the branch HAS its PR —
        # so look it up and return it rather than failing the approval.
        $statusCode = $null
        try { $statusCode = [int]$_.Exception.Response.StatusCode } catch { $statusCode = $null }
        if ($statusCode -eq 422) {
            $listUri = ("https://api.github.com/repos/{0}/{1}/pulls?head={2}:{3}&state=open" -f $slug.owner, $slug.repo, $slug.owner, $Branch)
            $existing = @(Invoke-RestMethod -Uri $listUri -Headers $headers -Method Get)
            if (@($existing).Count -gt 0) {
                $found = $existing[0]
                return [pscustomobject]@{
                    created = $false; refused = $false; reason = ("A pull request already exists for '{0}'." -f $Branch); category = ''
                    branch = $Branch; baseBranch = $effectiveBase; slug = $slug.slug
                    prUrl = [string]$found.html_url; prNumber = [int]$found.number; alreadyExisted = $true
                }
            }
        }
        throw
    }
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
        [Parameter()][hashtable]$ApiHeaders = $null,
        # Release 3.1 — the deliberate override, mirroring -AcknowledgeNoRunner
        # on the dispatch path. The capability is explained, not removed: an
        # operator who knows the base is stale and wants the PR anyway can say
        # so, and the acknowledgement is recorded on the result.
        [Parameter()][switch]$AcknowledgeStaleBase
    )

    $isGitRepo = (-not [string]::IsNullOrWhiteSpace($RepoPath)) -and (Test-Path -LiteralPath (Join-Path $RepoPath '.git'))
    $remoteUrl = if ($isGitRepo) { Get-GitRemoteUrl -RepoPath $RepoPath } else { '' }
    $slug      = Resolve-GitHubRepoSlug -RemoteUrl $remoteUrl
    $dirty     = if ($isGitRepo) { Test-GitWorkingTreeDirty -RepoPath $RepoPath } else { $false }
    $current   = if (Test-Path -LiteralPath $RoadmapPath) { Get-Content -LiteralPath $RoadmapPath -Raw -Encoding UTF8 } else { '' }
    $startBranch = if ($isGitRepo) { Get-GitCurrentBranch -RepoPath $RepoPath } else { '' }
    $effectiveBase = if (-not [string]::IsNullOrWhiteSpace($BaseBranch)) { $BaseBranch } elseif (-not [string]::IsNullOrWhiteSpace($startBranch)) { $startBranch } else { 'main' }

    # Ask the remote where the base actually is before anything branches from
    # it. One ls-remote round trip; never a fetch, and never fatal — an
    # unreachable remote reads 'unknown', which is not a refusal.
    $freshness = $null
    if ($isGitRepo -and (Get-Command -Name 'Get-RepoBaseFreshness' -ErrorAction SilentlyContinue)) {
        $freshness = Get-RepoBaseFreshness -RepoPath $RepoPath -BaseBranch $effectiveBase
    }

    $check = Test-RoadmapRepairPrPreconditions -RepoPath $RepoPath -RoadmapPath $RoadmapPath `
        -ProposedContent $ProposedContent -CurrentContent $current -Token $Token -Slug $slug `
        -IsGitRepo $isGitRepo -WorkingTreeDirty $dirty -BaseBranch $effectiveBase `
        -BaseFreshness $freshness -AcknowledgeStaleBase ([bool]$AcknowledgeStaleBase)
    if (-not $check.ok) {
        return [pscustomobject]@{
            created = $false; refused = $true; reason = $check.reason; category = $check.category
            branch = ''; prUrl = $null; prNumber = $null; slug = $(if ($null -ne $slug) { $slug.slug } else { '' })
            baseFreshness = $freshness
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

        # Release 3.4 milestone 3 — the push and PR-open now go through the
        # shared branch-PR path, so this caller and the agent-run approval
        # cannot drift apart. This function's own preconditions already passed,
        # so a refusal here would be a genuine surprise and is surfaced as one.
        $prResult = Open-RepoBranchPullRequest -RepoName $RepoName -RepoPath $RepoPath -Branch $branch `
            -BaseBranch $effectiveBase -Token $Token -ApiHeaders $ApiHeaders -PushFirst `
            -Title ("Roadmap repair: {0}" -f $RepoName) `
            -Body ("Automated roadmap repair for **{0}**.{1}`n`nGenerated by GitHubRepoManagement (Release 2.7 Phase A). Review the diff before merging — nothing here has been applied to {2}." -f `
                        $RepoName, $(if ($PreviewId) { " Based on repair preview ``$PreviewId``." } else { '' }), $effectiveBase)
        if ($prResult.refused) {
            throw ("PR could not be opened for '{0}' after the branch was committed: [{1}] {2}" -f $branch, $prResult.category, $prResult.reason)
        }

        return [pscustomobject]@{
            created = $true; refused = $false; reason = ''; category = ''
            branch = $branch; baseBranch = $effectiveBase; slug = $slug.slug
            prUrl = [string]$prResult.prUrl; prNumber = [int]$prResult.prNumber
            commitMessage = $message
            # The reading travels on success too, so a PR opened over a known
            # stale base is identifiable afterwards rather than only at the
            # moment someone clicked through the warning.
            baseFreshness = $freshness
            staleBaseAcknowledged = [bool]($AcknowledgeStaleBase -and $null -ne $freshness -and $freshness.isStale)
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
