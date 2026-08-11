<#
.SYNOPSIS
    Release 3.1 — roadmap completion write-back: the evidence gate, and the
    preview-first completion edit it guards.

.DESCRIPTION
    The last unbuilt step of the north-star loop. Two guardrails from ROADMAP
    section 8 meet here, and both are enforced rather than described:

      "Do not silently mark roadmap items complete based only on code churn."
      "Prefer preview-first workflows before write-back or autonomous mutation."

    So this module does exactly two things:

    1. **Test-RoadmapWriteBackEvidence** decides whether the evidence justifies
       marking an item complete. Merged-PR evidence is the only thing that
       qualifies. Files changed, a commit sha, a green Actions run, or a
       finished agent run are each refused with their own named code — a green
       run on an unmerged branch is a *proposal*, not a completion, and churn
       is not even that. A claim that a PR merged, with no `mergedAt` and no
       merge commit, is refused too: an unverifiable claim is not evidence.

    2. **New-RoadmapCompletionEdit** produces the proposed content and its diff.
       It never writes. The operator applies it through the existing repair
       submit-PR path, which is where review and the PR already live.

    Both are pure. The edit is deliberately conservative:
      * exactly one `- [ ]` line may match the item text; ambiguity refuses
        rather than guessing which one the operator meant
      * an already-`[x]` item is a no-op, not a second edit
      * the ONLY changes are the flipped checkbox and one inserted evidence
        line — asserted by diffing, so a generator bug that rewrites the file
        is caught by the generator's own output rather than at review time
      * the evidence line names the PR and the validation run, because this
        repo's own contract is that no item is marked complete without an
        evidence note naming the artifact that proves it

.NOTES
    Dot-source after Roadmap.Parser.ps1:
        . (Join-Path $roadmapModuleRoot 'Roadmap.WriteBack.ps1')
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:RoadmapWriteBackVersion = '1.0'

function _WriteBack_Field {
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
    param([object]$Obj, [string]$Name)
    return ([string](_WriteBack_Field -Obj $Obj -Name $Name -Default '')).Trim()
}

function _WriteBack_CleanItemText {
    # Mirrors the parser's item-text extraction so the text a packet carries
    # matches the line it came from: strip the checkbox marker, strip [tag]
    # markers, collapse whitespace.
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    $t = [string]$Text
    $t = $t -replace '^\s*-\s+\[[ xX]\]\s+', ''
    $t = [regex]::Replace($t, '\s*\[[a-zA-Z0-9_-]+\]', '')
    $t = $t -replace '\s+', ' '
    return $t.Trim()
}

function _WriteBack_NormalizeForMatch {
    param([string]$Text)
    $t = _WriteBack_CleanItemText -Text $Text
    if ([string]::IsNullOrWhiteSpace($t)) { return '' }
    $t = $t -replace '[‐‑‒–—―−]', '-'
    return $t.ToLowerInvariant()
}

function Test-RoadmapWriteBackEvidence {
    <#
    .SYNOPSIS
        Pure — may this item be marked complete on the evidence supplied?
    .DESCRIPTION
        The single definition of "proven complete". Callers turn a refusal into
        a 409 carrying the named code; nothing may reach the edit generator by
        deciding for itself that some evidence looks good enough.

        Refusal codes, most-specific first:
          no-evidence          nothing was supplied at all
          churn-only           files/commits changed but no pull request exists
          no-pr                no pull request is associated with the work
          pr-not-merged        the PR exists but has not merged (green != done)
          merge-unverified     merge is claimed with no mergedAt and no merge sha
          actions-missing      no Actions state was ever observed
          actions-incomplete   the validation run has not finished
          actions-failing      the validation run did not succeed
    .OUTPUTS
        [pscustomobject] allowed / reason / message / evidence
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()][object]$Evidence = $null,
        # A merged PR whose Actions state was never observed is still a merge.
        # Off by default: the loop this gates always observes Actions, and an
        # unobserved validation run is exactly the gap the guardrail cares about.
        [Parameter()][switch]$AllowMissingActions
    )

    $refuse = {
        param([string]$Code, [string]$Message)
        [pscustomobject]@{ allowed = $false; reason = $Code; message = $Message; evidence = $null }
    }

    if ($null -eq $Evidence) {
        return (& $refuse 'no-evidence' 'No merge evidence was supplied. A roadmap item is never marked complete without evidence that its work merged.')
    }

    $prUrl    = _WriteBack_Str -Obj $Evidence -Name 'prUrl'
    $prNumber = _WriteBack_Field -Obj $Evidence -Name 'prNumber' -Default $null
    $prState  = (_WriteBack_Str -Obj $Evidence -Name 'prState').ToLowerInvariant()
    $mergedAt = _WriteBack_Str -Obj $Evidence -Name 'mergedAt'
    $mergeSha = _WriteBack_Str -Obj $Evidence -Name 'mergeCommitSha'
    $merged   = [bool](_WriteBack_Field -Obj $Evidence -Name 'merged' -Default $false)
    $actionsStatus     = (_WriteBack_Str -Obj $Evidence -Name 'actionsStatus').ToLowerInvariant()
    $actionsConclusion = (_WriteBack_Str -Obj $Evidence -Name 'actionsConclusion').ToLowerInvariant()
    $filesChanged = [int](_WriteBack_Field -Obj $Evidence -Name 'filesChanged' -Default 0)
    $commitSha    = _WriteBack_Str -Obj $Evidence -Name 'commitSha'

    $hasPr = (-not [string]::IsNullOrWhiteSpace($prUrl)) -or ($null -ne $prNumber -and [string]$prNumber -ne '' -and [int]$prNumber -gt 0)

    if (-not $hasPr) {
        if ($filesChanged -gt 0 -or -not [string]::IsNullOrWhiteSpace($commitSha)) {
            return (& $refuse 'churn-only' ("Refusing to mark this item complete from code churn alone ({0} file(s) changed{1}). Churn is not completion — open a pull request and merge it." -f $filesChanged, $(if ($commitSha) { ", commit $commitSha" } else { '' })))
        }
        return (& $refuse 'no-pr' 'No pull request is associated with this work, so there is nothing to prove it landed.')
    }

    $prLabel = if ($prUrl) { $prUrl } else { "PR #$prNumber" }

    if (-not $merged -and $prState -ne 'merged') {
        $stateLabel = if ($prState) { $prState } else { 'unknown' }
        $greenNote = if ($actionsConclusion -eq 'success') { ' A successful validation run on an unmerged branch is a proposal, not a completion.' } else { '' }
        return (& $refuse 'pr-not-merged' ("{0} has not merged (state: {1}); the roadmap item stays open until it does.{2}" -f $prLabel, $stateLabel, $greenNote))
    }

    if ([string]::IsNullOrWhiteSpace($mergedAt) -and [string]::IsNullOrWhiteSpace($mergeSha)) {
        return (& $refuse 'merge-unverified' ("{0} is reported merged but carries neither a merge timestamp nor a merge commit. An unverifiable claim is not evidence." -f $prLabel))
    }

    if ([string]::IsNullOrWhiteSpace($actionsStatus)) {
        if (-not $AllowMissingActions) {
            return (& $refuse 'actions-missing' ("No GitHub Actions state was observed for {0}. Refresh the run from GitHub so validation evidence exists before claiming completion." -f $prLabel))
        }
    } elseif ($actionsStatus -ne 'completed') {
        return (& $refuse 'actions-incomplete' ("The validation run for {0} is still '{1}'; it has not finished." -f $prLabel, $actionsStatus))
    } elseif ($actionsConclusion -ne 'success') {
        return (& $refuse 'actions-failing' ("The validation run for {0} concluded '{1}', not success." -f $prLabel, $actionsConclusion))
    }

    return [pscustomobject]@{
        allowed  = $true
        reason   = ''
        message  = ("{0} merged{1}; validation {2}." -f $prLabel, $(if ($mergedAt) { " at $mergedAt" } else { " as $mergeSha" }), $(if ($actionsStatus) { "$actionsStatus/$actionsConclusion" } else { 'not observed (explicitly allowed)' }))
        evidence = [pscustomobject]@{
            prUrl             = if ($prUrl) { $prUrl } else { $null }
            prNumber          = $prNumber
            mergedAt          = if ($mergedAt) { $mergedAt } else { $null }
            mergeCommitSha    = if ($mergeSha) { $mergeSha } else { $null }
            actionsStatus     = if ($actionsStatus) { $actionsStatus } else { $null }
            actionsConclusion = if ($actionsConclusion) { $actionsConclusion } else { $null }
            workflowName      = _WriteBack_Str -Obj $Evidence -Name 'workflowName'
        }
    }
}

function Get-RoadmapWriteBackEvidenceFromTrace {
    <#
    .SYNOPSIS
        Pure — collect the evidence fields the gate reads from a work-item trace.
    .DESCRIPTION
        Reads the trace's own stages rather than re-querying GitHub, so the
        evidence the gate judges is exactly the evidence the trace displays.
        Nothing is inferred: a field the trace does not carry stays empty and
        the gate refuses on it.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory = $true)][object]$Trace)

    $stageByName = @{}
    foreach ($stage in @(_WriteBack_Field -Obj $Trace -Name 'stages' -Default @())) {
        $stageByName[[string](_WriteBack_Field -Obj $stage -Name 'stage' -Default '')] = $stage
    }

    $agentDetail = if ($stageByName.ContainsKey('agent-run')) { _WriteBack_Field -Obj $stageByName['agent-run'] -Name 'detail' -Default $null } else { $null }
    $actionsDetail = if ($stageByName.ContainsKey('actions')) { _WriteBack_Field -Obj $stageByName['actions'] -Name 'detail' -Default $null } else { $null }
    $mrDetail = if ($stageByName.ContainsKey('merge-readiness')) { _WriteBack_Field -Obj $stageByName['merge-readiness'] -Name 'detail' -Default $null } else { $null }
    $dispatchDetail = if ($stageByName.ContainsKey('dispatch')) { _WriteBack_Field -Obj $stageByName['dispatch'] -Name 'detail' -Default $null } else { $null }
    $mrEvidence = _WriteBack_Field -Obj $mrDetail -Name 'evidence' -Default $null

    $prUrl = _WriteBack_Str -Obj $agentDetail -Name 'prUrl'
    if ([string]::IsNullOrWhiteSpace($prUrl)) { $prUrl = _WriteBack_Str -Obj $mrDetail -Name 'prUrl' }
    $prNumber = _WriteBack_Field -Obj $agentDetail -Name 'prNumber' -Default (_WriteBack_Field -Obj $mrDetail -Name 'prNumber' -Default $null)
    # The agent-run record is the authority on merge: Invoke-AgentRunRefresh sets
    # prState/prMergedAt from GitHub's own merged_at. The merge-readiness snapshot
    # is the fallback because it can be older than the run it describes.
    $prState = _WriteBack_Str -Obj $agentDetail -Name 'prState'
    if ([string]::IsNullOrWhiteSpace($prState)) { $prState = _WriteBack_Str -Obj $mrEvidence -Name 'prState' }

    return [pscustomobject]@{
        prUrl             = $prUrl
        prNumber          = $prNumber
        prState           = $prState
        merged            = ($prState.ToLowerInvariant() -eq 'merged')
        mergedAt          = _WriteBack_Str -Obj $agentDetail -Name 'prMergedAt'
        mergeCommitSha    = _WriteBack_Str -Obj $agentDetail -Name 'prMergeCommitSha'
        actionsStatus     = _WriteBack_Str -Obj $actionsDetail -Name 'status'
        actionsConclusion = _WriteBack_Str -Obj $actionsDetail -Name 'conclusion'
        workflowName      = _WriteBack_Str -Obj $actionsDetail -Name 'workflowName'
        filesChanged      = [int](_WriteBack_Field -Obj $dispatchDetail -Name 'filesChanged' -Default 0)
        commitSha         = _WriteBack_Str -Obj $dispatchDetail -Name 'commitSha'
    }
}

function Find-RoadmapCompletionItemLine {
    <#
    .SYNOPSIS
        Pure — locate the single pending checkbox line an item text refers to.
    .DESCRIPTION
        Matching is exact on the parser's own cleaned form first, then on a
        case/dash-normalized form. More than one match in either tier is a
        refusal: marking the wrong item is a silent corruption of the very
        history this loop exists to keep honest.
    .OUTPUTS
        [pscustomobject] found / reason / message / lineIndex / indent / alreadyComplete
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        # AllowEmptyString as well as AllowEmptyCollection: roadmap files are full
        # of blank lines, and a mandatory [string[]] rejects empty ELEMENTS, not
        # just an empty array.
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][AllowEmptyString()][string[]]$Lines,
        [Parameter(Mandatory = $true)][string]$ItemText
    )

    $wantedExact = _WriteBack_CleanItemText -Text $ItemText
    $wantedNorm  = _WriteBack_NormalizeForMatch -Text $ItemText

    if ([string]::IsNullOrWhiteSpace($wantedExact)) {
        return [pscustomobject]@{ found = $false; reason = 'empty-item-text'; message = 'No item text was supplied to locate.'; lineIndex = -1; indent = ''; alreadyComplete = $false }
    }

    $pendingExact = [System.Collections.Generic.List[int]]::new()
    $pendingNorm  = [System.Collections.Generic.List[int]]::new()
    $completeNorm = [System.Collections.Generic.List[int]]::new()

    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $line = [string]$Lines[$i]
        if ($line -match '^(\s*)-\s+\[(\s|x|X)\]\s+(.+)$') {
            $mark = $Matches[2]
            $body = $Matches[3]
            $cleaned = _WriteBack_CleanItemText -Text $body
            $normalized = _WriteBack_NormalizeForMatch -Text $body
            if ($mark -eq ' ') {
                if ($cleaned -ceq $wantedExact) { $pendingExact.Add($i) | Out-Null }
                elseif ($normalized -eq $wantedNorm) { $pendingNorm.Add($i) | Out-Null }
            } elseif ($normalized -eq $wantedNorm) {
                $completeNorm.Add($i) | Out-Null
            }
        }
    }

    # @(...) around .ToArray(): assigning a List from an `if` expression unrolls
    # it, so an empty list would arrive as $null and .Count would throw under
    # StrictMode — the "no match" case failing louder than the failure it reports.
    $matches_ = @(if ($pendingExact.Count -gt 0) { $pendingExact.ToArray() } else { $pendingNorm.ToArray() })

    if ($matches_.Count -gt 1) {
        return [pscustomobject]@{
            found = $false; reason = 'ambiguous-item'
            message = ("{0} pending roadmap items match this text (lines {1}); refusing to guess which one completed." -f $matches_.Count, ((@($matches_ | ForEach-Object { $_ + 1 })) -join ', '))
            lineIndex = -1; indent = ''; alreadyComplete = $false
        }
    }

    if ($matches_.Count -eq 0) {
        if ($completeNorm.Count -gt 0) {
            return [pscustomobject]@{
                found = $false; reason = 'already-complete'
                message = ("The item is already marked complete on line {0}; nothing to write back." -f ($completeNorm[0] + 1))
                lineIndex = $completeNorm[0]; indent = ''; alreadyComplete = $true
            }
        }
        return [pscustomobject]@{
            found = $false; reason = 'item-not-found'
            message = 'No pending checkbox item in this roadmap matches the supplied text.'
            lineIndex = -1; indent = ''; alreadyComplete = $false
        }
    }

    $idx = $matches_[0]
    $indent = ''
    if ([string]$Lines[$idx] -match '^(\s*)-\s+\[') { $indent = $Matches[1] }

    return [pscustomobject]@{
        found = $true; reason = ''; message = ''
        lineIndex = $idx; indent = $indent; alreadyComplete = $false
    }
}

function Get-RoadmapItemBlockEnd {
    <#
    .SYNOPSIS
        Pure — the index of the last line belonging to the list item that starts
        at StartIndex.
    .DESCRIPTION
        A roadmap item is rarely one line: this repo's own items carry indented
        continuation prose and an evidence note. The evidence line has to be
        appended AFTER that body, not spliced into the middle of a sentence.
        Continuation = a more-indented non-blank line; a blank line ends the
        block unless an indented line follows it.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        # AllowEmptyString as well as AllowEmptyCollection: roadmap files are full
        # of blank lines, and a mandatory [string[]] rejects empty ELEMENTS, not
        # just an empty array.
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][AllowEmptyString()][string[]]$Lines,
        [Parameter(Mandatory = $true)][int]$StartIndex
    )

    if ($StartIndex -lt 0 -or $StartIndex -ge $Lines.Count) { return $StartIndex }

    $markerIndent = 0
    if ([string]$Lines[$StartIndex] -match '^(\s*)-\s+\[') { $markerIndent = $Matches[1].Length }

    $end = $StartIndex
    $i = $StartIndex + 1
    while ($i -lt $Lines.Count) {
        $line = [string]$Lines[$i]
        if ([string]::IsNullOrWhiteSpace($line)) {
            # Look ahead: an indented line after a blank continues the item.
            $j = $i + 1
            while ($j -lt $Lines.Count -and [string]::IsNullOrWhiteSpace([string]$Lines[$j])) { $j++ }
            if ($j -ge $Lines.Count) { break }
            $nextLine = [string]$Lines[$j]
            if ($nextLine -match '^(\s*)\S' -and $Matches[1].Length -gt $markerIndent -and $nextLine -notmatch '^\s*-\s+\[') {
                $end = $j; $i = $j + 1; continue
            }
            break
        }
        if ($line -match '^\s*-\s+\[') { break }
        if ($line -match '^(\s*)\S' -and $Matches[1].Length -gt $markerIndent) { $end = $i; $i++; continue }
        break
    }

    return $end
}

function New-RoadmapCompletionEvidenceNote {
    <#
    .SYNOPSIS
        Pure — the evidence line appended under a completed item.
    .DESCRIPTION
        Names the PR and the validation run. This repo's contract is that no
        item is marked complete without an evidence note naming the artifact
        that proves it; a write-back that flipped the box and said nothing would
        produce exactly the unfalsifiable "[x]" the guardrail exists to stop.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Pure string builder — it returns a line of text and changes no state, so -WhatIf would describe an action that does not exist.')]
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Indent,
        [Parameter(Mandatory = $true)][object]$Evidence,
        [Parameter()][AllowEmptyString()][string]$TraceKey = ''
    )

    $prUrl = _WriteBack_Str -Obj $Evidence -Name 'prUrl'
    $prNumber = _WriteBack_Field -Obj $Evidence -Name 'prNumber' -Default $null
    $prLabel = if ($prUrl) { $prUrl } elseif ($null -ne $prNumber) { "PR #$prNumber" } else { 'the merged pull request' }
    $mergedAt = _WriteBack_Str -Obj $Evidence -Name 'mergedAt'
    $mergeSha = _WriteBack_Str -Obj $Evidence -Name 'mergeCommitSha'
    $workflow = _WriteBack_Str -Obj $Evidence -Name 'workflowName'
    $conclusion = _WriteBack_Str -Obj $Evidence -Name 'actionsConclusion'

    $mergePart = if ($mergedAt) { ("merged {0}" -f $mergedAt) } elseif ($mergeSha) { ("merged as {0}" -f $mergeSha) } else { 'merged' }
    $validationPart = if ($conclusion) {
        ("validation {0}{1}" -f $(if ($workflow) { "$workflow " } else { '' }), $conclusion)
    } else {
        'validation not observed'
    }
    $tracePart = if ($TraceKey) { ("; trace ``{0}``" -f $TraceKey) } else { '' }

    # Continuation indent: the marker's indent plus the width of "- [x] ", which
    # is what the surrounding items use.
    $contIndent = $Indent + (' ' * 6)
    return ("{0}**Evidence:** {1} in {2}; {3}{4}." -f $contIndent, $mergePart, $prLabel, $validationPart, $tracePart)
}

function New-RoadmapCompletionEdit {
    <#
    .SYNOPSIS
        Pure — propose the completion edit for one roadmap item. Writes nothing.
    .DESCRIPTION
        Returns the proposed content, the located line, the inserted evidence
        note, and a unified diff of the changed region. The generator verifies
        its own output: if the proposal differs from the original anywhere other
        than the flipped checkbox line and the one inserted evidence line, it
        refuses with `unexpected-edit` rather than handing a reviewer a diff
        that quietly rewrote the file.
    .OUTPUTS
        [pscustomobject] ok / reason / message / proposedContent / diff / ...
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Pure generator — it returns proposed content and never writes it. The whole point of this release is that applying is a separate, explicit operator action.')]
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$RoadmapContent,
        [Parameter(Mandatory = $true)][string]$ItemText,
        [Parameter(Mandatory = $true)][object]$Evidence,
        [Parameter()][AllowEmptyString()][string]$TraceKey = '',
        [Parameter()][int]$DiffContextLines = 3
    )

    $refuse = {
        param([string]$Code, [string]$Message)
        [pscustomobject]@{
            ok = $false; reason = $Code; message = $Message
            proposedContent = ''; currentContent = $RoadmapContent
            lineNumber = 0; matchedLine = ''; evidenceNote = ''; diff = ''
            changedLineCount = 0
        }
    }

    if ([string]::IsNullOrWhiteSpace($RoadmapContent)) {
        return (& $refuse 'empty-roadmap' 'The roadmap content is empty; there is nothing to mark complete.')
    }

    $newline = if ($RoadmapContent -match "`r`n") { "`r`n" } else { "`n" }
    $lines = @($RoadmapContent -split "`r?`n")

    $located = Find-RoadmapCompletionItemLine -Lines $lines -ItemText $ItemText
    if (-not $located.found) {
        return (& $refuse ([string]$located.reason) ([string]$located.message))
    }

    $idx = [int]$located.lineIndex
    $matchedLine = [string]$lines[$idx]
    $flipped = $matchedLine -replace '^(\s*-\s+)\[\s\](\s+)', '$1[x]$2'
    if ($flipped -ceq $matchedLine) {
        return (& $refuse 'checkbox-not-flipped' 'The matched line could not be rewritten to a completed checkbox.')
    }

    $blockEnd = Get-RoadmapItemBlockEnd -Lines $lines -StartIndex $idx
    $note = New-RoadmapCompletionEvidenceNote -Indent ([string]$located.indent) -Evidence $Evidence -TraceKey $TraceKey

    $out = [System.Collections.Generic.List[string]]::new()
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($i -eq $idx) { $out.Add($flipped) | Out-Null } else { $out.Add([string]$lines[$i]) | Out-Null }
        if ($i -eq $blockEnd) { $out.Add($note) | Out-Null }
    }
    $proposed = ($out.ToArray() -join $newline)

    # Self-check: exactly one line rewritten and exactly one inserted.
    $proposedLines = @($proposed -split "`r?`n")
    if ($proposedLines.Count -ne ($lines.Count + 1)) {
        return (& $refuse 'unexpected-edit' ("The proposal changed the line count by {0}; expected exactly one inserted evidence line." -f ($proposedLines.Count - $lines.Count)))
    }
    $changed = 0
    $offset = 0
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($i -eq ($blockEnd + 1)) { $offset = 1 }
        if ([string]$proposedLines[$i + $offset] -cne [string]$lines[$i]) { $changed++ }
    }
    if ($changed -ne 1) {
        return (& $refuse 'unexpected-edit' ("The proposal rewrote {0} existing line(s); only the checkbox line may change." -f $changed))
    }

    # Unified diff of the changed region only.
    $from = [math]::Max(0, $idx - $DiffContextLines)
    $to = [math]::Min($lines.Count - 1, $blockEnd + $DiffContextLines)
    $diff = [System.Collections.Generic.List[string]]::new()
    $diff.Add(("@@ -{0},{1} +{0},{2} @@" -f ($from + 1), ($to - $from + 1), ($to - $from + 2))) | Out-Null
    for ($i = $from; $i -le $to; $i++) {
        if ($i -eq $idx) {
            $diff.Add('-' + $matchedLine) | Out-Null
            $diff.Add('+' + $flipped) | Out-Null
        } else {
            $diff.Add(' ' + [string]$lines[$i]) | Out-Null
        }
        if ($i -eq $blockEnd) { $diff.Add('+' + $note) | Out-Null }
    }

    return [pscustomobject]@{
        ok               = $true
        reason           = ''
        message          = ("Proposed marking line {0} complete with an evidence note." -f ($idx + 1))
        editVersion      = $script:RoadmapWriteBackVersion
        currentContent   = $RoadmapContent
        proposedContent  = $proposed
        lineNumber       = $idx + 1
        blockEndLine     = $blockEnd + 1
        matchedLine      = $matchedLine
        proposedLine     = $flipped
        evidenceNote     = $note
        changedLineCount = 1
        insertedLineCount = 1
        diff             = ($diff.ToArray() -join "`n")
    }
}

function New-RoadmapWriteBackPreview {
    <#
    .SYNOPSIS
        Pure — the gate and the generator in the order they must run.
    .DESCRIPTION
        The single composition point, so no caller can reach the generator
        without the gate. A refusal carries the gate's own code and produces no
        proposed content at all — there is nothing for a UI to "just apply".
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Pure composition of the gate and the generator — it returns a preview and writes nothing.')]
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$RoadmapContent,
        [Parameter(Mandatory = $true)][string]$ItemText,
        [Parameter()][object]$Evidence = $null,
        [Parameter()][AllowEmptyString()][string]$TraceKey = '',
        [Parameter()][AllowEmptyString()][string]$RepoName = '',
        [Parameter()][switch]$AllowMissingActions
    )

    $gate = Test-RoadmapWriteBackEvidence -Evidence $Evidence -AllowMissingActions:$AllowMissingActions
    if (-not $gate.allowed) {
        return [pscustomobject]@{
            allowed         = $false
            decision        = 'refused'
            reason          = [string]$gate.reason
            message         = [string]$gate.message
            repoName        = $RepoName
            itemText        = $ItemText
            traceKey        = $TraceKey
            previewId       = $null
            proposedContent = ''
            diff            = ''
            evidence        = $null
            generatedAt     = (Get-Date).ToUniversalTime().ToString('o')
        }
    }

    $edit = New-RoadmapCompletionEdit -RoadmapContent $RoadmapContent -ItemText $ItemText -Evidence $gate.evidence -TraceKey $TraceKey
    if (-not $edit.ok) {
        return [pscustomobject]@{
            allowed         = $false
            decision        = 'refused'
            reason          = [string]$edit.reason
            message         = [string]$edit.message
            repoName        = $RepoName
            itemText        = $ItemText
            traceKey        = $TraceKey
            previewId       = $null
            proposedContent = ''
            diff            = ''
            evidence        = $gate.evidence
            generatedAt     = (Get-Date).ToUniversalTime().ToString('o')
        }
    }

    return [pscustomobject]@{
        allowed          = $true
        decision         = 'proposed'
        reason           = ''
        message          = [string]$edit.message
        repoName         = $RepoName
        itemText         = $ItemText
        traceKey         = $TraceKey
        previewId        = ('wb_' + [guid]::NewGuid().ToString('n').Substring(0, 12))
        currentContent   = [string]$edit.currentContent
        proposedContent  = [string]$edit.proposedContent
        diff             = [string]$edit.diff
        lineNumber       = [int]$edit.lineNumber
        matchedLine      = [string]$edit.matchedLine
        proposedLine     = [string]$edit.proposedLine
        evidenceNote     = [string]$edit.evidenceNote
        changedLineCount = [int]$edit.changedLineCount
        evidence         = $gate.evidence
        evidenceSummary  = [string]$gate.message
        applyRoute       = 'POST /api/roadmap/repair/submit-pr (createPr=true) — write-back is preview-first; nothing is applied here.'
        generatedAt      = (Get-Date).ToUniversalTime().ToString('o')
    }
}
