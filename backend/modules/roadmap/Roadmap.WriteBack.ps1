<#
.SYNOPSIS
    Release 3.1 — roadmap completion write-back, gated on merge evidence.

.DESCRIPTION
    The last unbuilt step of the north-star workflow: once a work item's pull
    request is merged, the managed repo's own roadmap should say so. Nothing
    marked an item complete before this module, and the roadmap's section 8
    guardrail against doing it from the wrong signal had no enforcement.

    Two ideas, kept apart on purpose:

      1. Test-RoadmapWriteBackEvidence decides whether completion may be
         claimed at all. It is pure and it fails closed.
      2. New-RoadmapCompletionEdit produces the edit. It never consults the
         gate, so it cannot be talked into skipping it — the caller must pass
         the gate first, and both routes do.

    WHAT IS NOT EVIDENCE, and why each one is refused rather than merely
    unimplemented:

      * Code churn. Files changed and a commit sha say work happened, not that
        it was accepted. A branch full of commits that never merged is the
        commonest shape of abandoned work in this portfolio.
      * A green validation run on an unmerged PR. Actions passing means the
        change is safe to merge, which is the opposite of merged.
      * A local verify result. `verifyResult=passed` is the runner's own
        opinion, recorded before review, on a machine the change never left.
      * A merged PR with no successful validation run. Merging past a red or
        absent check is possible; recording it as completed work is how a
        roadmap starts lying.

    Only a merged pull request, identified by url or number, with a merge
    commit and a successful Actions conclusion, is completion.

    The write-back ledger (output/roadmap-writeback/history.jsonl) is
    append-only and is the same file the Release 3.1 work-item trace reads for
    its final stage, so a write-back is visible in the trace that gated it.

.NOTES
    PowerShell 5.1 compatible. Pure functions do no I/O.
    Dot-source after Roadmap.Parser.ps1.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:RoadmapWriteBackSchemaVersion = '1'
$script:RoadmapWriteBackRelPath = 'output\roadmap-writeback\history.jsonl'

function _WriteBack_GetField {
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

function _WriteBack_Str {
    param([object]$Obj, [string]$Name, [string]$Default = '')
    return [string](_WriteBack_GetField -Obj $Obj -Name $Name -Default $Default)
}

function _WriteBack_HasText {
    param([object]$Value)
    return (-not [string]::IsNullOrWhiteSpace([string]$Value))
}

<#
.SYNOPSIS
    Pure — normalize what is known about a work item's pull request into one
    evidence record.
.DESCRIPTION
    Reads from whichever sources exist. A fresh GitHub PR detail wins over the
    stored merge-readiness snapshot, because the snapshot is a photograph and
    the PR is the subject: an item merged five minutes ago still has a snapshot
    that says `open`.
#>
function Get-RoadmapWriteBackEvidence {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        # GitHub's pull-request object (html_url, number, merged_at, merge_commit_sha, state).
        [Parameter()][object]$PrDetail = $null,
        # A stored merge-readiness snapshot for the repo.
        [Parameter()][object]$MergeReadiness = $null,
        # The agent-run ledger record, for its observed Actions state.
        [Parameter()][object]$AgentRun = $null,
        # The runner's run summary — carried so its LOCAL signals can be named
        # in a refusal rather than silently ignored.
        [Parameter()][object]$RunSummary = $null
    )

    $mrEvidence = _WriteBack_GetField -Obj $MergeReadiness -Name 'evidence' -Default $null

    $prUrl = _WriteBack_Str -Obj $PrDetail -Name 'html_url'
    if (-not (_WriteBack_HasText $prUrl)) { $prUrl = _WriteBack_Str -Obj $MergeReadiness -Name 'prUrl' }
    if (-not (_WriteBack_HasText $prUrl)) { $prUrl = _WriteBack_Str -Obj $AgentRun -Name 'prUrl' }

    $prNumber = _WriteBack_GetField -Obj $PrDetail -Name 'number' -Default $null
    if ($null -eq $prNumber) { $prNumber = _WriteBack_GetField -Obj $MergeReadiness -Name 'prNumber' -Default $null }

    $mergedAt = _WriteBack_Str -Obj $PrDetail -Name 'merged_at'
    $mergeCommitSha = _WriteBack_Str -Obj $PrDetail -Name 'merge_commit_sha'
    $prState = ''
    if ($null -ne $PrDetail) {
        $detailState = _WriteBack_Str -Obj $PrDetail -Name 'state'
        if (_WriteBack_HasText $mergedAt) { $prState = 'merged' }
        elseif ($detailState -eq 'closed') { $prState = 'closed' }
        elseif (_WriteBack_HasText $detailState) { $prState = 'open' }
    }
    if (-not (_WriteBack_HasText $prState)) { $prState = _WriteBack_Str -Obj $mrEvidence -Name 'prState' }

    $actions = _WriteBack_GetField -Obj $AgentRun -Name 'actions' -Default $null
    $actionsStatus = _WriteBack_Str -Obj $actions -Name 'status'
    $actionsConclusion = _WriteBack_Str -Obj $actions -Name 'conclusion'
    if (-not (_WriteBack_HasText $actionsStatus)) {
        $actionsStatus = _WriteBack_Str -Obj $mrEvidence -Name 'actionsStatus'
        $actionsConclusion = _WriteBack_Str -Obj $mrEvidence -Name 'actionsConclusion'
    }

    # Where the merge claim came from. A stored snapshot can say `merged` but
    # never carries a merge commit, so "no merge commit" from a snapshot means
    # "nobody asked GitHub" — a different refusal from "GitHub had none".
    $evidenceSource = if ($null -ne $PrDetail) { 'github-pr' }
    elseif ($null -ne $MergeReadiness) { 'merge-readiness-snapshot' }
    elseif ($null -ne $AgentRun) { 'agent-run-ledger' }
    else { 'none' }

    return [pscustomobject]@{
        evidenceSource    = $evidenceSource
        prUrl             = if (_WriteBack_HasText $prUrl) { $prUrl } else { $null }
        prNumber          = $prNumber
        prState           = if (_WriteBack_HasText $prState) { $prState } else { $null }
        merged            = ($prState -eq 'merged')
        mergedAt          = if (_WriteBack_HasText $mergedAt) { $mergedAt } else { $null }
        mergeCommitSha    = if (_WriteBack_HasText $mergeCommitSha) { $mergeCommitSha } else { $null }
        actionsStatus     = if (_WriteBack_HasText $actionsStatus) { $actionsStatus } else { $null }
        actionsConclusion = if (_WriteBack_HasText $actionsConclusion) { $actionsConclusion } else { $null }
        # Local signals, recorded so a refusal can name what the caller was
        # probably looking at. They are never evidence of completion.
        localCommitSha    = _WriteBack_Str -Obj $RunSummary -Name 'commitSha'
        localFilesChanged = _WriteBack_GetField -Obj $RunSummary -Name 'filesChanged' -Default $null
        localVerifyResult = _WriteBack_Str -Obj $RunSummary -Name 'verifyResult'
        observedAt        = (Get-Date).ToUniversalTime().ToString('o')
    }
}

<#
.SYNOPSIS
    Pure — decide whether a roadmap item may be marked complete.
.DESCRIPTION
    Fails closed: no evidence object at all is a refusal, not a pass. Every
    refusal carries a code, a human sentence, and what would satisfy it.

    Refusal codes:
      no-evidence            nothing is known about this item's pull request
      no-pull-request        no PR is linked to the work item
      pr-not-merged          the PR is open, or closed without merging
      no-merge-commit        merged, but GitHub reported no merge commit
      merge-unverified       merged per a stored snapshot only; GitHub unread
      no-validation-evidence no Actions run was ever observed for the PR
      validation-incomplete  the latest Actions run has not finished
      validation-failed      the latest Actions conclusion is not success
      no-item-text           nothing says which roadmap item this completes
#>
function Test-RoadmapWriteBackEvidence {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()][object]$Evidence = $null,
        [Parameter()][AllowEmptyString()][string]$ItemText = ''
    )

    $refusals = New-Object System.Collections.Generic.List[object]
    $addRefusal = {
        param([string]$Code, [string]$Message, [string]$Remedy)
        $refusals.Add([ordered]@{ code = $Code; message = $Message; remedy = $Remedy })
    }

    if ($null -eq $Evidence) {
        & $addRefusal 'no-evidence' `
            'Nothing is known about this work item''s pull request, so completion cannot be claimed.' `
            'Refresh the agent run from GitHub, or evaluate merge readiness for the repo, then try again.'
    }
    else {
        $prUrl = _WriteBack_Str -Obj $Evidence -Name 'prUrl'
        $prState = _WriteBack_Str -Obj $Evidence -Name 'prState'
        $merged = [bool](_WriteBack_GetField -Obj $Evidence -Name 'merged' -Default $false)
        $actionsStatus = _WriteBack_Str -Obj $Evidence -Name 'actionsStatus'
        $actionsConclusion = _WriteBack_Str -Obj $Evidence -Name 'actionsConclusion'
        $filesChanged = _WriteBack_GetField -Obj $Evidence -Name 'localFilesChanged' -Default $null
        $verifyResult = _WriteBack_Str -Obj $Evidence -Name 'localVerifyResult'

        if (-not (_WriteBack_HasText $prUrl)) {
            # Name the local signals explicitly. A caller staring at "4 files
            # changed, verify passed" needs to be told those are not the thing,
            # not merely that something is missing.
            $churn = @()
            if ($null -ne $filesChanged -and [int]$filesChanged -gt 0) { $churn += ("{0} changed file(s)" -f $filesChanged) }
            if ($verifyResult -eq 'passed') { $churn += 'a passing local verify' }
            $churnNote = if ($churn.Count -gt 0) { (" This item has {0}, which is work done, not work accepted." -f ($churn -join ' and ')) } else { '' }
            & $addRefusal 'no-pull-request' `
                ("No pull request is linked to this work item.{0}" -f $churnNote) `
                'Open a pull request for the branch (POST /api/roadmap/repair/submit-pr), then re-check.'
        }
        elseif (-not $merged) {
            $stateNote = if ($prState -eq 'closed') { 'was closed without merging' } else { 'is still open' }
            $greenNote = if ($actionsConclusion -eq 'success') { ' A green validation run means the change is safe to merge, which is not the same as merged.' } else { '' }
            & $addRefusal 'pr-not-merged' `
                ("Pull request {0} {1}.{2}" -f $prUrl, $stateNote, $greenNote) `
                'Merge the pull request (merge stays an explicit operator action), then re-check.'
        }
        else {
            if (-not (_WriteBack_HasText (_WriteBack_Str -Obj $Evidence -Name 'mergeCommitSha'))) {
                if ((_WriteBack_Str -Obj $Evidence -Name 'evidenceSource') -eq 'github-pr') {
                    & $addRefusal 'no-merge-commit' `
                        ("Pull request {0} reports as merged but GitHub returned no merge commit, so the merge is unverifiable." -f $prUrl) `
                        'Re-read the pull request from GitHub; if the merge commit is genuinely absent, do not record completion.'
                }
                else {
                    & $addRefusal 'merge-unverified' `
                        ("The merge of {0} is known only from a stored snapshot, which never records a merge commit — nobody has asked GitHub." -f $prUrl) `
                        'Configure a GitHub token so the pull request can be re-read live, then re-check.'
                }
            }
            if (-not (_WriteBack_HasText $actionsStatus)) {
                & $addRefusal 'no-validation-evidence' `
                    ("No GitHub Actions run was ever observed for pull request {0}, so this merge carries no validation evidence." -f $prUrl) `
                    'Refresh the agent run from GitHub to capture the Actions result.'
            }
            elseif ($actionsStatus -ne 'completed') {
                & $addRefusal 'validation-incomplete' `
                    ("The latest Actions run for {0} is '{1}'; validation has not finished." -f $prUrl, $actionsStatus) `
                    'Wait for the validation run to complete, then re-check.'
            }
            elseif ($actionsConclusion -ne 'success') {
                & $addRefusal 'validation-failed' `
                    ("The latest Actions conclusion for {0} is '{1}'. A merge past a failing check is not completed work." -f $prUrl, $actionsConclusion) `
                    'Fix the failing validation and land a passing run before recording completion.'
            }
        }
    }

    if (-not (_WriteBack_HasText $ItemText)) {
        & $addRefusal 'no-item-text' `
            'No roadmap item text is recorded for this work item, so there is nothing to mark complete.' `
            'Trace the item to find the packet that names it, or pass itemText explicitly.'
    }

    return [pscustomobject]@{
        allowed     = ($refusals.Count -eq 0)
        refusals    = @($refusals.ToArray())
        refusalCodes = @(@($refusals.ToArray()) | ForEach-Object { [string]$_.code })
        checkedAt   = (Get-Date).ToUniversalTime().ToString('o')
    }
}

<#
.SYNOPSIS
    Pure — produce the completion edit for one or more roadmap items.
.DESCRIPTION
    Marks `- [ ] <item>` as `- [x] <item>`, preserving indentation. Returns the
    proposed content plus a line-level diff so the operator reviews an edit
    rather than approving a promise.

    Deliberately conservative:
      * Only an exact (trimmed) item-text match is edited. Fuzzy matching would
        eventually tick the wrong line in someone else's roadmap.
      * An item already `- [x]` is reported as `alreadyComplete`, not matched
        again, so a re-run is a no-op instead of a second claim.
      * No match at all is `changed = $false` with the item named — never a
        silent zero-line edit that reads as success.
#>
function New-RoadmapCompletionEdit {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Pure builder: it returns the proposed content and never touches disk. -WhatIf on a function that changes nothing would suggest it does. The write that DOES change state is in the apply route, behind the merge-evidence gate.')]
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Content,
        [Parameter(Mandatory = $true)][string[]]$ItemTexts
    )

    $proposed = [string]$Content
    $matched = New-Object System.Collections.Generic.List[object]
    $alreadyComplete = New-Object System.Collections.Generic.List[string]
    $notFound = New-Object System.Collections.Generic.List[string]

    foreach ($rawItem in @($ItemTexts)) {
        $item = ([string]$rawItem).Trim()
        if ([string]::IsNullOrWhiteSpace($item)) { continue }
        $escaped = [regex]::Escape($item)

        $openPattern = "(?m)^(\s*)-\s+\[\s\]\s+$escaped\s*$"
        $donePattern = "(?m)^(\s*)-\s+\[[xX]\]\s+$escaped\s*$"

        if ($proposed -match $openPattern) {
            $proposed = [regex]::Replace($proposed, $openPattern, { param($m) ("{0}- [x] {1}" -f $m.Groups[1].Value, $item) })
            $matched.Add([ordered]@{ itemText = $item })
        }
        elseif ($proposed -match $donePattern) {
            $alreadyComplete.Add($item)
        }
        else {
            $notFound.Add($item)
        }
    }

    # Line-level diff. The roadmap files this edits are large, so a whole-file
    # dump is not a review surface — only changed lines, with their numbers.
    $before = [string]$Content -split "`r?`n"
    $after = $proposed -split "`r?`n"
    $diff = New-Object System.Collections.Generic.List[object]
    $lineCount = [Math]::Max($before.Count, $after.Count)
    for ($i = 0; $i -lt $lineCount; $i++) {
        $b = if ($i -lt $before.Count) { $before[$i] } else { $null }
        $a = if ($i -lt $after.Count) { $after[$i] } else { $null }
        if ($b -ne $a) {
            $diff.Add([ordered]@{ line = ($i + 1); before = $b; after = $a })
        }
    }

    return [pscustomobject]@{
        proposedContent = $proposed
        changed         = ($matched.Count -gt 0)
        markedCount     = $matched.Count
        markedItems     = @(@($matched.ToArray()) | ForEach-Object { [string]$_.itemText })
        alreadyComplete = @($alreadyComplete.ToArray())
        notFound        = @($notFound.ToArray())
        diff            = @($diff.ToArray())
        generatedAt     = (Get-Date).ToUniversalTime().ToString('o')
    }
}

function Add-RoadmapCompletionCommit {
    <#
        .SYNOPSIS
            Commit the completion edit for one roadmap item onto the CURRENT
            feature branch, so the merge makes it authoritative.
        .DESCRIPTION
            Release 3.4 milestone 4. Until this function, the completion edit
            was written by POST /api/roadmap/write-back/apply AFTER the merge,
            as a bare Set-Content on whatever branch was checked out — main at
            that point in the loop. Completion now travels through the pull
            request: the runner calls this after the work commit, and the
            merge-evidence gate downstream verifies rather than writes.

            Refuses BY NAME on a default branch. That is the acceptance
            criterion made executable: no path writes a completion edit to a
            default branch, this one included.

            Never throws for an expected condition — the caller is a runner in
            the middle of a task; a completion edit it cannot make is a
            recorded outcome, not a crashed run.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)][string]$RepoPath,
        [Parameter()][AllowEmptyString()][string]$RoadmapPath = '',
        [Parameter(Mandatory = $true)][string]$ItemText,
        [Parameter()][AllowEmptyString()][string]$RunId = ''
    )

    $result = [ordered]@{
        committed = $false; category = ''; reason = ''
        alreadyComplete = $false; itemFound = $true
        branch = ''; commitSha = $null; roadmapPath = $RoadmapPath
    }

    if (-not (Test-Path -LiteralPath (Join-Path $RepoPath '.git'))) {
        $result.category = 'not-a-git-repo'
        $result.reason = ("'{0}' is not a git working copy." -f $RepoPath)
        return [pscustomobject]$result
    }

    if ([string]::IsNullOrWhiteSpace($RoadmapPath)) { $RoadmapPath = Join-Path $RepoPath 'ROADMAP.md' }
    $result.roadmapPath = $RoadmapPath
    if (-not (Test-Path -LiteralPath $RoadmapPath -PathType Leaf)) {
        $result.category = 'roadmap-not-found'
        $result.reason = ("No roadmap file at '{0}', so there is no checkbox to mark." -f $RoadmapPath)
        return [pscustomobject]$result
    }

    $branchOut = (& git -C $RepoPath rev-parse --abbrev-ref HEAD 2>&1) | Out-String
    if ($LASTEXITCODE -ne 0) {
        $result.category = 'branch-unreadable'
        $result.reason = 'Could not read the current branch (detached HEAD?). A completion commit needs a named feature branch.'
        return [pscustomobject]$result
    }
    $branch = $branchOut.Trim()
    $result.branch = $branch

    # The default branch may not receive a completion edit from any path. The
    # remote's HEAD names it when known; 'main'/'master' cover a clone whose
    # origin/HEAD was never set. Refusal, not silence — the caller records it.
    $defaultNames = @('main', 'master')
    $originDefaultName = ''
    $originHead = (& git -C $RepoPath symbolic-ref --quiet --short 'refs/remotes/origin/HEAD' 2>&1) | Out-String
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($originHead)) {
        $originDefaultName = ($originHead.Trim() -replace '^origin/', '')
        $defaultNames += $originDefaultName
    }
    if ($branch -in $defaultNames) {
        $result.category = 'on-default-branch'
        $result.reason = ("Refusing to commit a completion edit on '{0}': completion travels through a pull request, never directly onto a default branch." -f $branch)
        return [pscustomobject]$result
    }

    # The base state travels ON the record rather than gating it. The runner
    # already refused a stale base before the branch existed (Release 3.1), and
    # after that the pull request's own merge is the arbiter — refusing here
    # would strand finished work over drift the PR will surface anyway. What the
    # 2026-08-11 stranded-queue triage actually lacked was EVIDENCE of the base
    # state at each step, so this reading is recorded, reported when stale, and
    # never a refusal.
    $result.baseFreshness = $null
    $result.baseStaleAtCompletion = $false
    if (Get-Command -Name 'Get-RepoBaseFreshness' -ErrorAction SilentlyContinue) {
        $baseName = if (-not [string]::IsNullOrWhiteSpace($originDefaultName)) { $originDefaultName } else { 'main' }
        $freshness = Get-RepoBaseFreshness -RepoPath $RepoPath -BaseBranch $baseName
        $result.baseFreshness = $freshness
        $result.baseStaleAtCompletion = ($null -ne $freshness -and [bool](_WriteBack_GetField -Obj $freshness -Name 'isStale' -Default $false))
    }

    $content = Get-Content -LiteralPath $RoadmapPath -Raw -Encoding UTF8
    if ($null -eq $content) { $content = '' }
    $edit = New-RoadmapCompletionEdit -Content $content -ItemTexts @($ItemText)

    if (@($edit.alreadyComplete).Count -gt 0) {
        # The agent may have flipped the box itself during the run. That is the
        # desired end state, already reached — success, nothing to commit.
        $result.alreadyComplete = $true
        $result.reason = ("'{0}' is already marked complete on this branch." -f $ItemText)
        return [pscustomobject]$result
    }
    if (-not $edit.changed) {
        $result.itemFound = $false
        $result.category = 'item-not-found'
        $result.reason = ("No open checkbox matching '{0}' exists in {1} — the completion edit cannot be generated." -f $ItemText, $RoadmapPath)
        return [pscustomobject]$result
    }

    if (-not $PSCmdlet.ShouldProcess($RoadmapPath, ("commit completion edit for '{0}' on branch '{1}'" -f $ItemText, $branch))) {
        $result.category = 'whatif'
        $result.reason = 'WhatIf: nothing written, nothing committed.'
        return [pscustomobject]$result
    }

    # Preserve the trailing newline, same rule as the PR submitter: only ADD
    # one, never strip or double it.
    $toWrite = [string]$edit.proposedContent
    if (-not $toWrite.EndsWith("`n")) { $toWrite += "`n" }
    Set-Content -LiteralPath $RoadmapPath -Value $toWrite -Encoding UTF8 -NoNewline

    $add = (& git -C $RepoPath add -- $RoadmapPath 2>&1) | Out-String
    if ($LASTEXITCODE -ne 0) {
        $result.category = 'git-add-failed'
        $result.reason = ("git add failed: {0}" -f $add.Trim())
        return [pscustomobject]$result
    }
    $message = if ([string]::IsNullOrWhiteSpace($RunId)) {
        ("docs(roadmap): record completion — {0}" -f $ItemText)
    } else {
        ("docs(roadmap): record completion — {0} (run {1})" -f $ItemText, $RunId)
    }
    $commit = (& git -C $RepoPath commit -m $message -- $RoadmapPath 2>&1) | Out-String
    if ($LASTEXITCODE -ne 0) {
        $result.category = 'git-commit-failed'
        $result.reason = ("git commit failed: {0}" -f $commit.Trim())
        return [pscustomobject]$result
    }

    $sha = ((& git -C $RepoPath rev-parse --short HEAD 2>&1) | Out-String).Trim()
    $result.committed = $true
    $result.commitSha = $sha
    $result.reason = ("Completion edit committed on '{0}' ({1})." -f $branch, $sha)
    return [pscustomobject]$result
}

function Get-RoadmapWriteBackHistoryPath {
    param([Parameter(Mandatory = $true)][string]$WorkspaceRoot)
    return (Join-Path $WorkspaceRoot $script:RoadmapWriteBackRelPath)
}

<#
.SYNOPSIS
    Append one write-back record. The file is append-only: an apply is a NEW
    line after its preview, never an edit of it.
.DESCRIPTION
    Refuses to record an applied write-back that carries no allowed gate
    result. The gate is the point; a ledger that can hold an unattributable
    "applied" is a ledger that can launder one.
#>
function Write-RoadmapWriteBackRecord {
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)][string]$WorkspaceRoot,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$RunId,
        [Parameter()][AllowEmptyString()][string]$PacketId = '',
        [Parameter()][AllowEmptyString()][string]$RepoName = '',
        [Parameter()][AllowEmptyString()][string]$RoadmapPath = '',
        [Parameter()][AllowEmptyString()][string]$ItemText = '',
        [Parameter()][switch]$Applied,
        [Parameter()][int]$MarkedCount = 0,
        [Parameter()][object]$Evidence = $null,
        [Parameter()][object]$Gate = $null,
        [Parameter()][AllowEmptyString()][string]$Actor = '',
        [Parameter()][AllowEmptyString()][string]$PreviewId = '',
        # Release 3.4 milestone 4 — what the applied record MEANS. 'applied-edit'
        # is the legacy shape (the route wrote the checkbox itself);
        # 'verified-merged' records that the merge already carried the edit and
        # the gate verified it. The default keeps old records' meaning intact.
        [Parameter()][ValidateSet('applied-edit', 'verified-merged')][string]$Action = 'applied-edit'
    )

    if ($Applied.IsPresent) {
        $gateAllowed = [bool](_WriteBack_GetField -Obj $Gate -Name 'allowed' -Default $false)
        if (-not $gateAllowed) {
            throw 'Refusing to record an applied write-back without an allowed merge-evidence gate result.'
        }
    }

    $record = [ordered]@{
        schemaVersion = $script:RoadmapWriteBackSchemaVersion
        recordId      = [guid]::NewGuid().ToString('n')
        previewId     = if (_WriteBack_HasText $PreviewId) { $PreviewId } else { $null }
        runId         = if (_WriteBack_HasText $RunId) { $RunId } else { $null }
        packetId      = if (_WriteBack_HasText $PacketId) { $PacketId } else { $null }
        repoName      = $RepoName
        roadmapPath   = $RoadmapPath
        itemText      = $ItemText
        applied       = [bool]$Applied.IsPresent
        action        = $Action
        markedCount   = $MarkedCount
        actor         = $Actor
        evidence      = $Evidence
        gate          = $Gate
        recordedAt    = (Get-Date).ToUniversalTime().ToString('o')
    }

    $path = Get-RoadmapWriteBackHistoryPath -WorkspaceRoot $WorkspaceRoot
    if ($PSCmdlet.ShouldProcess($path, 'Append roadmap write-back record')) {
        $dir = Split-Path -Parent $path
        if (-not (Test-Path -LiteralPath $dir)) { $null = New-Item -ItemType Directory -Path $dir -Force }
        Add-Content -LiteralPath $path -Value (ConvertTo-Json -InputObject $record -Compress -Depth 8) -Encoding UTF8
    }
    return [pscustomobject]$record
}

<#
.SYNOPSIS
    Read write-back records, newest last (append order), optionally for one run.
#>
function Get-RoadmapWriteBackHistory {
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory = $true)][string]$WorkspaceRoot,
        [Parameter()][AllowEmptyString()][string]$RunId = '',
        [Parameter()][int]$Limit = 50
    )

    $path = Get-RoadmapWriteBackHistoryPath -WorkspaceRoot $WorkspaceRoot
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return @() }

    $records = New-Object System.Collections.Generic.List[object]
    foreach ($line in @(Get-Content -LiteralPath $path -Encoding UTF8 -ErrorAction SilentlyContinue)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try { $records.Add((ConvertFrom-Json -InputObject $line)) } catch { continue }
    }

    $items = @($records.ToArray())
    if (_WriteBack_HasText $RunId) {
        $items = @($items | Where-Object { (_WriteBack_Str -Obj $_ -Name 'runId') -eq $RunId })
    }
    if ($Limit -gt 0 -and $items.Count -gt $Limit) {
        $items = @($items[($items.Count - $Limit)..($items.Count - 1)])
    }
    return $items
}
