Set-StrictMode -Version Latest

<#
    Proof of value, 2026-10-16 - the delivery ledger.

    Ben's decision of 2026-10-16 made one question primary until 2026-11-15:
    does the product deliver merged improvements to OTHER repositories for
    less operator time than doing them by hand? Before this file nothing could
    answer it. Operator minutes were null on every trial record, accept and
    reject were never captured, and a PR opened by the product was a line in a
    repair history nobody read back.

    One append-only JSONL stream, two record kinds:

      decision - the operator's response to one proposal: accept, edit
                 (accepted after changing the text) or reject (a reason is
                 required). Carries the seconds the operator spent reviewing it
                 and how that figure was obtained.
      outcome  - what became of an opened PR: open, merged or closed without
                 merging, the CI conclusion on its head, and any further
                 operator seconds (review on GitHub) the operator reports.

    The summary is the admission-rule arithmetic: total operator seconds,
    including the time spent on rejected proposals, divided by merged
    improvements. With nothing merged it is null with a reason, never 0.

    Minutes are never inferred from timestamps. A figure is either measured in
    the console while the proposal was on screen ('measured-in-console') or
    entered by the operator ('operator-entered'), and the basis travels with it.
#>

$script:DeliveryLedgerSchemaVersion = '1'
$script:DeliveryLedgerRelativePath = 'output\delivery\delivery-ledger.jsonl'
$script:DeliveryRefreshStateRelativePath = 'output\delivery\outcome-refresh.json'
$script:DeliveryDecisions = @('accept', 'edit', 'reject')
$script:DeliverySecondsBases = @('measured-in-console', 'operator-entered')
$script:DeliveryPrStates = @('open', 'merged', 'closed-unmerged')
$script:DeliveryCiConclusions = @('success', 'failure', 'pending', 'none', 'unavailable')
# A review longer than a working day is a stopwatch left running, not a review.
$script:DeliveryMaxOperatorSeconds = 28800

function Get-DeliveryLedgerPath {
    <#
    .SYNOPSIS
        Where the delivery ledger lives, honouring REPO_MGMT_OUTPUT_ROOT.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$WorkspaceRoot)
    return (Resolve-OutputPath -WorkspaceRoot $WorkspaceRoot -RelativePath $script:DeliveryLedgerRelativePath)
}

function ConvertTo-DeliveryOperatorSecond {
    # Validates one operator-seconds reading; returns the int or $null.
    [CmdletBinding()]
    [OutputType([int])]
    param([AllowNull()][object]$Seconds, [AllowEmptyString()][string]$Basis = '', [string]$Context = 'record')
    if ($null -eq $Seconds -or ([string]$Seconds) -eq '') { return $null }
    $parsed = 0
    if (-not [int]::TryParse([string]$Seconds, [ref]$parsed)) {
        throw ("{0}: operatorSeconds '{1}' is not a whole number of seconds." -f $Context, $Seconds)
    }
    if ($parsed -lt 0 -or $parsed -gt $script:DeliveryMaxOperatorSeconds) {
        throw ("{0}: operatorSeconds {1} is outside 0-{2}." -f $Context, $parsed, $script:DeliveryMaxOperatorSeconds)
    }
    if ($script:DeliverySecondsBases -notcontains $Basis) {
        throw ("{0}: operatorSeconds needs a basis, one of {1}; got '{2}'." -f $Context, ($script:DeliverySecondsBases -join ', '), $Basis)
    }
    return $parsed
}

function ConvertTo-DeliveryHeadSha {
    <#
    .SYNOPSIS
        Validate one commit SHA read from GitHub; returns it lower-cased, or
        $null when none was given. Throws on anything that is not a full SHA.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowNull()][AllowEmptyString()][string]$Sha = '', [string]$Context = 'record')
    if ([string]::IsNullOrWhiteSpace($Sha)) { return $null }
    $normalized = $Sha.Trim().ToLowerInvariant()
    if ($normalized -notmatch '^[0-9a-f]{40}$') {
        throw ("{0}: head SHA '{1}' is not a full 40-character commit SHA." -f $Context, $Sha)
    }
    return $normalized
}

function New-DeliveryDecisionRecord {
    <#
    .SYNOPSIS
        Build one decision record, or throw rather than record an
        unexplainable one.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Pure constructor: returns a record and touches nothing. Same precedent as New-PortfolioMetric.')]
    param(
        [Parameter(Mandatory)][string]$RepoName,
        [Parameter(Mandatory)][string]$Decision,
        [Parameter()][AllowEmptyString()][string]$PreviewId = '',
        [Parameter()][AllowEmptyString()][string]$ActionKind = 'roadmap-repair',
        [Parameter()][AllowEmptyString()][string]$Reason = '',
        [Parameter()][AllowNull()][object]$OperatorSeconds = $null,
        [Parameter()][AllowEmptyString()][string]$OperatorSecondsBasis = '',
        [Parameter()][AllowEmptyString()][string]$PrUrl = '',
        [Parameter()][AllowNull()][object]$PrNumber = $null,
        [Parameter()][AllowEmptyString()][string]$PrHeadSha = '',
        [Parameter()][AllowNull()][object]$Proposal = $null,
        [Parameter()][AllowEmptyString()][string]$RecordedAtUtc = ''
    )

    if ([string]::IsNullOrWhiteSpace($RepoName)) { throw 'A decision needs the repository it answers.' }
    if ($script:DeliveryDecisions -notcontains $Decision) {
        throw ("decision must be one of {0}; got '{1}'." -f ($script:DeliveryDecisions -join ', '), $Decision)
    }
    if ($Decision -eq 'reject' -and [string]::IsNullOrWhiteSpace($Reason)) {
        throw 'A rejection must say why: an unexplained reject teaches the model nothing.'
    }
    if ($Decision -eq 'reject' -and -not [string]::IsNullOrWhiteSpace($PrUrl)) {
        throw 'A rejected proposal cannot carry a PR it did not open.'
    }
    if (-not [string]::IsNullOrWhiteSpace($PrHeadSha)) {
        if ($Decision -eq 'reject') { throw 'A rejected proposal cannot carry the head of a PR it did not open.' }
        if ([string]::IsNullOrWhiteSpace($PrUrl)) { throw 'A head SHA needs the PR it belongs to.' }
    }
    $headSha = ConvertTo-DeliveryHeadSha -Sha $PrHeadSha -Context ("decision on {0}" -f $RepoName)
    $seconds = ConvertTo-DeliveryOperatorSecond -Seconds $OperatorSeconds -Basis $OperatorSecondsBasis -Context ("decision on {0}" -f $RepoName)

    $at = if ([string]::IsNullOrWhiteSpace($RecordedAtUtc)) { [datetime]::UtcNow.ToString('o') } else { ([datetime]::Parse($RecordedAtUtc, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal)).ToString('o') }
    $record = [ordered]@{
        schemaVersion        = $script:DeliveryLedgerSchemaVersion
        kind                 = 'decision'
        decisionId           = [guid]::NewGuid().ToString('n')
        recordedAt           = $at
        repoName             = $RepoName
        previewId            = $(if ($PreviewId) { $PreviewId } else { $null })
        actionKind           = $(if ($ActionKind) { $ActionKind } else { 'roadmap-repair' })
        decision             = $Decision
        reason               = $(if ($Reason) { $Reason } else { $null })
        operatorSeconds      = $seconds
        operatorSecondsBasis = $(if ($null -ne $seconds) { $OperatorSecondsBasis } else { $null })
        prUrl                = $(if ($PrUrl) { $PrUrl } else { $null })
        prNumber             = $(if ($null -ne $PrNumber -and [string]$PrNumber -ne '') { [int]$PrNumber } else { $null })
        # The head GitHub reported when the PR was opened. Always present;
        # null when no PR exists.
        prHeadSha            = $headSha
        proposal             = $Proposal
    }
    return $record
}

function New-DeliveryOutcomeRecord {
    <#
    .SYNOPSIS
        Build one outcome record for an opened PR.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Pure constructor: returns a record and touches nothing.')]
    param(
        [Parameter(Mandatory)][string]$PrUrl,
        [Parameter(Mandatory)][string]$PrState,
        [Parameter()][AllowEmptyString()][string]$DecisionId = '',
        [Parameter()][AllowEmptyString()][string]$MergedAt = '',
        [Parameter()][AllowEmptyString()][string]$HeadSha = '',
        [Parameter()][AllowEmptyString()][string]$CiConclusion = 'unavailable',
        [Parameter()][AllowEmptyString()][string]$CiBasis = '',
        [Parameter()][AllowNull()][object]$OperatorSeconds = $null,
        [Parameter()][AllowEmptyString()][string]$OperatorSecondsBasis = '',
        [Parameter()][AllowEmptyString()][string]$Note = '',
        [Parameter()][AllowEmptyString()][string]$RecordedAtUtc = ''
    )
    if ($script:DeliveryPrStates -notcontains $PrState) {
        throw ("prState must be one of {0}; got '{1}'." -f ($script:DeliveryPrStates -join ', '), $PrState)
    }
    if ($script:DeliveryCiConclusions -notcontains $CiConclusion) {
        throw ("ciConclusion must be one of {0}; got '{1}'." -f ($script:DeliveryCiConclusions -join ', '), $CiConclusion)
    }
    if ($PrState -eq 'merged' -and [string]::IsNullOrWhiteSpace($MergedAt)) {
        throw 'A merged outcome must say when it merged.'
    }
    $head = ConvertTo-DeliveryHeadSha -Sha $HeadSha -Context ("outcome for {0}" -f $PrUrl)
    $seconds = ConvertTo-DeliveryOperatorSecond -Seconds $OperatorSeconds -Basis $OperatorSecondsBasis -Context ("outcome for {0}" -f $PrUrl)
    $at = if ([string]::IsNullOrWhiteSpace($RecordedAtUtc)) { [datetime]::UtcNow.ToString('o') } else { ([datetime]::Parse($RecordedAtUtc, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal)).ToString('o') }
    return [ordered]@{
        schemaVersion        = $script:DeliveryLedgerSchemaVersion
        kind                 = 'outcome'
        recordedAt           = $at
        decisionId           = $(if ($DecisionId) { $DecisionId } else { $null })
        prUrl                = $PrUrl
        prState              = $PrState
        mergedAt             = $(if ($MergedAt) { $MergedAt } else { $null })
        # The head the CI verdict was read on, and where the reading came
        # from: outcomes are read from GitHub, never typed in.
        headSha              = $head
        source               = 'github'
        ciConclusion         = $CiConclusion
        ciBasis              = $(if ($CiBasis) { $CiBasis } else { $null })
        operatorSeconds      = $seconds
        operatorSecondsBasis = $(if ($null -ne $seconds) { $OperatorSecondsBasis } else { $null })
        note                 = $(if ($Note) { $Note } else { $null })
    }
}

function Add-DeliveryLedgerRecord {
    <#
    .SYNOPSIS
        Append one record to the delivery ledger.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)][string]$WorkspaceRoot,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Record
    )
    $path = Get-DeliveryLedgerPath -WorkspaceRoot $WorkspaceRoot
    $dir = Split-Path -Parent $path
    if (-not $PSCmdlet.ShouldProcess($path, 'append delivery ledger record')) { return }
    if (-not (Test-Path -LiteralPath $dir)) { $null = New-Item -ItemType Directory -Path $dir -Force }
    $line = ConvertTo-Json -InputObject $Record -Compress -Depth 8
    Add-Content -LiteralPath $path -Value $line -Encoding UTF8
}

function Get-DeliveryLedgerRecord {
    <#
    .SYNOPSIS
        Read every delivery ledger record, oldest first.
    .DESCRIPTION
        A malformed line is reported in `skipped`, never silently dropped.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)][string]$WorkspaceRoot)
    $path = Get-DeliveryLedgerPath -WorkspaceRoot $WorkspaceRoot
    $records = [System.Collections.Generic.List[object]]::new()
    $skipped = 0
    if (Test-Path -LiteralPath $path) {
        foreach ($line in (Get-Content -LiteralPath $path -Encoding UTF8)) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try { $records.Add(($line | ConvertFrom-Json)) } catch { $skipped++ }
        }
    }
    return [pscustomobject]@{ path = $path; records = $records.ToArray(); skipped = $skipped }
}

function _DeliveryField {
    param([object]$Obj, [string]$Name, [object]$Default = $null)
    if ($null -eq $Obj) { return $Default }
    if ($Obj -is [System.Collections.IDictionary]) {
        if ($Obj.Contains($Name) -and $null -ne $Obj[$Name]) { return $Obj[$Name] }
        return $Default
    }
    if ($Obj.PSObject.Properties.Name -contains $Name -and $null -ne $Obj.$Name) { return $Obj.$Name }
    return $Default
}

function _DeliveryTimestamp {
    # ConvertFrom-Json turns ISO strings into DateTime; give them back as
    # invariant round-trip UTC strings so the wire never carries a
    # culture-formatted date.
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [datetime]) { return $Value.ToUniversalTime().ToString('o', [Globalization.CultureInfo]::InvariantCulture) }
    if ($Value -is [datetimeoffset]) { return $Value.UtcDateTime.ToString('o', [Globalization.CultureInfo]::InvariantCulture) }
    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    return $text
}

function Get-DeliveryDecisionOutcome {
    <#
    .SYNOPSIS
        Exactly one outcome per decision, oldest decision first (loop step 7).
    .DESCRIPTION
        Pure over the ledger records. The outcome of a decision is one of:

          rejected-before-pr  the operator rejected it; no PR ever existed.
          no-pr-recorded      accepted, but the ledger names no PR for it.
          pr-opened           a PR was opened; nothing has been read back
                              from GitHub yet, so CI reads 'not-read' and
                              the head is the one GitHub reported at opening.
          pr-open             GitHub last reported the PR open.
          merged              GitHub reported it merged.
          closed-unmerged     GitHub reported it closed without merging.

        The last three come only from outcome records, which only an outcome
        refresh against GitHub writes. A decision with no outcome yet is
        `awaiting` and carries a reason; it is never a failure.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter()][AllowEmptyCollection()][object[]]$Record = @())

    $latestByPr = @{}
    foreach ($r in @($Record)) {
        if ([string](_DeliveryField -Obj $r -Name 'kind' -Default '') -ne 'outcome') { continue }
        $url = [string](_DeliveryField -Obj $r -Name 'prUrl' -Default '')
        if (-not [string]::IsNullOrWhiteSpace($url)) { $latestByPr[$url] = $r }
    }

    $list = [System.Collections.Generic.List[object]]::new()
    foreach ($d in @($Record)) {
        if ([string](_DeliveryField -Obj $d -Name 'kind' -Default '') -ne 'decision') { continue }
        $decision = [string](_DeliveryField -Obj $d -Name 'decision' -Default '')
        $url = [string](_DeliveryField -Obj $d -Name 'prUrl' -Default '')
        $openingHead = _DeliveryField -Obj $d -Name 'prHeadSha' -Default $null
        $latest = if ($url -and $latestByPr.ContainsKey($url)) { $latestByPr[$url] } else { $null }

        $outcome = ''; $reason = $null; $prState = $null; $headSha = $null; $ci = $null; $mergedAt = $null; $readAt = $null
        if ($decision -eq 'reject') {
            $outcome = 'rejected-before-pr'
        }
        elseif ([string]::IsNullOrWhiteSpace($url)) {
            $outcome = 'no-pr-recorded'
            $reason = 'Accepted, but no pull request is recorded for this decision.'
        }
        elseif ($null -eq $latest) {
            $outcome = 'pr-opened'
            $headSha = $openingHead
            $ci = 'not-read'
            $reason = 'No outcome has been read from GitHub for this PR yet.'
        }
        else {
            $prState = [string](_DeliveryField -Obj $latest -Name 'prState' -Default 'open')
            $outcome = switch ($prState) { 'merged' { 'merged' } 'closed-unmerged' { 'closed-unmerged' } default { 'pr-open' } }
            $headSha = _DeliveryField -Obj $latest -Name 'headSha' -Default $openingHead
            $ci = [string](_DeliveryField -Obj $latest -Name 'ciConclusion' -Default 'unavailable')
            $mergedAt = _DeliveryTimestamp (_DeliveryField -Obj $latest -Name 'mergedAt' -Default $null)
            $readAt = _DeliveryTimestamp (_DeliveryField -Obj $latest -Name 'recordedAt' -Default $null)
            if ($outcome -eq 'pr-open') { $reason = 'The PR is still open on GitHub.' }
        }
        $terminal = @('rejected-before-pr', 'merged', 'closed-unmerged') -contains $outcome
        $prNumber = _DeliveryField -Obj $d -Name 'prNumber' -Default $null
        $list.Add([pscustomobject]@{
            decisionId        = _DeliveryField -Obj $d -Name 'decisionId' -Default $null
            repoName          = [string](_DeliveryField -Obj $d -Name 'repoName' -Default '')
            decision          = $decision
            decidedAt         = _DeliveryTimestamp (_DeliveryField -Obj $d -Name 'recordedAt' -Default $null)
            operatorSeconds   = _DeliveryField -Obj $d -Name 'operatorSeconds' -Default $null
            prUrl             = $(if ($url) { $url } else { $null })
            prNumber          = $(if ($null -ne $prNumber) { [int]$prNumber } else { $null })
            outcome           = $outcome
            terminal          = $terminal
            awaiting          = (-not $terminal)
            outcomeRead       = ($null -ne $latest)
            prState           = $prState
            headSha           = $headSha
            ciConclusion      = $ci
            mergedAt          = $mergedAt
            outcomeRecordedAt = $readAt
            reason            = $reason
        })
    }
    # Unrolled: callers wrap the call in @() (an empty ledger yields @()).
    return $list.ToArray()
}

function Get-DeliveryOutcomeRefreshState {
    <#
    .SYNOPSIS
        When outcomes were last read from GitHub, or that they never were.
    .DESCRIPTION
        Update-DeliveryOutcome writes output\delivery\outcome-refresh.json
        after every refresh it actually performs (never under -WhatIf), so
        freshness is established from that record, never assumed.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)][string]$WorkspaceRoot)
    $path = Resolve-OutputPath -WorkspaceRoot $WorkspaceRoot -RelativePath $script:DeliveryRefreshStateRelativePath
    $never = 'Outcomes have never been read from GitHub; POST /api/delivery/outcomes/refresh reads them.'
    if (-not (Test-Path -LiteralPath $path)) {
        return [pscustomobject]@{ lastReadAt = $null; checked = $null; appended = $null; errorCount = $null; reason = $never }
    }
    try { $raw = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json }
    catch {
        return [pscustomobject]@{ lastReadAt = $null; checked = $null; appended = $null; errorCount = $null; reason = ('The outcome refresh record at {0} is unreadable: {1}' -f $path, $_.Exception.Message) }
    }
    $at = _DeliveryTimestamp (_DeliveryField -Obj $raw -Name 'refreshedAt' -Default $null)
    $errorCount = [int](_DeliveryField -Obj $raw -Name 'errorCount' -Default 0)
    return [pscustomobject]@{
        lastReadAt = $at
        checked    = [int](_DeliveryField -Obj $raw -Name 'checked' -Default 0)
        appended   = [int](_DeliveryField -Obj $raw -Name 'appended' -Default 0)
        errorCount = $errorCount
        reason     = $(if ($null -eq $at) { $never } elseif ($errorCount -gt 0) { ('{0} PR(s) could not be read at the last refresh.' -f $errorCount) } else { $null })
    }
}

function Get-DeliverySummary {
    <#
    .SYNOPSIS
        The admission-rule arithmetic over the ledger, as contract metrics.
    .DESCRIPTION
        Pure over its records. Every figure is a New-PortfolioMetric object.
        Operator time counts EVERY decision, rejected ones included, plus any
        outcome-time the operator reported: automation that moves effort into
        review has not saved it.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()][AllowEmptyCollection()][object[]]$Record = @(),
        [Parameter(Mandatory)][string]$AsOfUtc,
        # Get-DeliveryOutcomeRefreshState's reading; when omitted, freshness
        # is null with a reason, never assumed.
        [Parameter()][AllowNull()][object]$LastRefresh = $null
    )
    $source = 'delivery-ledger'
    $decisions = @($Record | Where-Object { [string](_DeliveryField -Obj $_ -Name 'kind' -Default '') -eq 'decision' })
    $outcomes = @($Record | Where-Object { [string](_DeliveryField -Obj $_ -Name 'kind' -Default '') -eq 'outcome' })

    $accepted = @($decisions | Where-Object { @('accept', 'edit') -contains [string](_DeliveryField -Obj $_ -Name 'decision' -Default '') })
    $rejected = @($decisions | Where-Object { [string](_DeliveryField -Obj $_ -Name 'decision' -Default '') -eq 'reject' })
    $opened = @($decisions | Where-Object { -not [string]::IsNullOrWhiteSpace([string](_DeliveryField -Obj $_ -Name 'prUrl' -Default '')) })

    # Latest outcome per PR decides its state.
    $latestByPr = @{}
    foreach ($o in $outcomes) {
        $url = [string](_DeliveryField -Obj $o -Name 'prUrl' -Default '')
        if ([string]::IsNullOrWhiteSpace($url)) { continue }
        $latestByPr[$url] = $o
    }
    # A List, not `$prs = foreach`: an empty foreach assigns $null, and @($null)
    # is a one-element array that would count as one PR.
    $prList = [System.Collections.Generic.List[object]]::new()
    foreach ($d in $opened) {
        $url = [string](_DeliveryField -Obj $d -Name 'prUrl' -Default '')
        $latest = if ($latestByPr.ContainsKey($url)) { $latestByPr[$url] } else { $null }
        $prList.Add([pscustomobject]@{
            repoName     = [string](_DeliveryField -Obj $d -Name 'repoName' -Default '')
            prUrl        = $url
            decision     = [string](_DeliveryField -Obj $d -Name 'decision' -Default '')
            decidedAt    = [string](_DeliveryField -Obj $d -Name 'recordedAt' -Default '')
            prState      = $(if ($null -ne $latest) { [string](_DeliveryField -Obj $latest -Name 'prState' -Default 'open') } else { 'open' })
            stateKnown   = ($null -ne $latest)
            mergedAt     = $(if ($null -ne $latest) { _DeliveryField -Obj $latest -Name 'mergedAt' -Default $null } else { $null })
            ciConclusion = $(if ($null -ne $latest) { [string](_DeliveryField -Obj $latest -Name 'ciConclusion' -Default 'unavailable') } else { 'unavailable' })
            headSha      = $(if ($null -ne $latest) { _DeliveryField -Obj $latest -Name 'headSha' -Default (_DeliveryField -Obj $d -Name 'prHeadSha' -Default $null) } else { _DeliveryField -Obj $d -Name 'prHeadSha' -Default $null })
        })
    }
    $prs = $prList.ToArray()
    $merged = @($prs | Where-Object { $_.prState -eq 'merged' })

    $timed = @($decisions | Where-Object { $null -ne (_DeliveryField -Obj $_ -Name 'operatorSeconds' -Default $null) })
    $totalSeconds = 0
    foreach ($r in @($decisions) + @($outcomes)) {
        $s = _DeliveryField -Obj $r -Name 'operatorSeconds' -Default $null
        if ($null -ne $s) { $totalSeconds += [int]$s }
    }

    $decidedCount = $decisions.Count
    $metrics = [ordered]@{}
    $metrics.proposalsDecided = New-PortfolioMetric -Id 'delivery.proposalsDecided' -Value $decidedCount -AsOfUtc $AsOfUtc -Source $source `
        -Definition 'Proposals the operator accepted, accepted with edits, or rejected in the console.'
    $metrics.accepted = New-PortfolioMetric -Id 'delivery.accepted' -Value $accepted.Count -Numerator $accepted.Count -Denominator $decidedCount -AsOfUtc $AsOfUtc -Source $source `
        -Definition 'Decisions that accepted the proposal, with or without edits.'
    $metrics.rejected = New-PortfolioMetric -Id 'delivery.rejected' -Value $rejected.Count -Numerator $rejected.Count -Denominator $decidedCount -AsOfUtc $AsOfUtc -Source $source `
        -Definition 'Decisions that rejected the proposal, each with a reason.'
    $metrics.prsOpened = New-PortfolioMetric -Id 'delivery.prsOpened' -Value $opened.Count -AsOfUtc $AsOfUtc -Source $source `
        -Definition 'Pull requests the product opened on a repository after the operator accepted the proposal.'
    $metrics.prsMerged = New-PortfolioMetric -Id 'delivery.prsMerged' -Value $merged.Count -Numerator $merged.Count -Denominator $opened.Count -AsOfUtc $AsOfUtc -Source $source `
        -Definition 'Opened pull requests whose latest recorded outcome is merged. An outcome is recorded only by an outcome refresh against GitHub.'

    if ($decidedCount -eq 0) {
        $metrics.operatorSeconds = New-PortfolioMetric -Id 'delivery.operatorSeconds' -Value $null -Unit 'seconds' -AsOfUtc $AsOfUtc `
            -Definition 'Operator seconds across every decision and reported outcome review.' -Reason 'No decision has been recorded yet.'
    }
    else {
        $metrics.operatorSeconds = New-PortfolioMetric -Id 'delivery.operatorSeconds' -Value $totalSeconds -Unit 'seconds' -AsOfUtc $AsOfUtc -Source $source `
            -Assessed $timed.Count -Total $decidedCount `
            -Definition 'Operator seconds across every decision (rejected ones included) and reported outcome review. Coverage counts decisions that carry a time.'
    }

    $perMergedReason = if ($decidedCount -eq 0) { 'No decision has been recorded yet.' }
    elseif ($merged.Count -eq 0) { ('No merged improvement yet; {0} operator second(s) recorded across {1} decision(s).' -f $totalSeconds, $decidedCount) }
    elseif ($timed.Count -lt $decidedCount) { ('{0} of {1} decision(s) carry no operator time, so a per-improvement figure would understate the cost.' -f ($decidedCount - $timed.Count), $decidedCount) }
    else { '' }
    if ($perMergedReason) {
        $metrics.operatorSecondsPerMergedImprovement = New-PortfolioMetric -Id 'delivery.operatorSecondsPerMergedImprovement' -Value $null -Unit 'seconds' -AsOfUtc $AsOfUtc `
            -Definition 'Total operator seconds divided by merged improvements.' -Reason $perMergedReason
    }
    else {
        $metrics.operatorSecondsPerMergedImprovement = New-PortfolioMetric -Id 'delivery.operatorSecondsPerMergedImprovement' `
            -Value ([math]::Round($totalSeconds / $merged.Count)) -Unit 'seconds' -AsOfUtc $AsOfUtc -Source $source `
            -Definition 'Total operator seconds (rejected proposals and outcome review included) divided by merged improvements.'
    }

    # Loop step 7: one outcome per decision. Awaiting is not failure.
    $decisionOutcomes = @(Get-DeliveryDecisionOutcome -Record $Record)
    $awaiting = @($decisionOutcomes | Where-Object { $_.awaiting })
    $closedUnmerged = @($decisionOutcomes | Where-Object { $_.outcome -eq 'closed-unmerged' })
    if ($decidedCount -eq 0) {
        $metrics.awaitingOutcome = New-PortfolioMetric -Id 'delivery.awaitingOutcome' -Value $null -AsOfUtc $AsOfUtc `
            -Definition 'Decisions with no final outcome yet: an accept with no PR recorded, or a PR not yet merged or closed.' -Reason 'No decision has been recorded yet.'
    }
    else {
        $metrics.awaitingOutcome = New-PortfolioMetric -Id 'delivery.awaitingOutcome' -Value $awaiting.Count -Numerator $awaiting.Count -Denominator $decidedCount -AsOfUtc $AsOfUtc -Source $source `
            -Definition 'Decisions with no final outcome yet: an accept with no PR recorded, or a PR not yet merged or closed. Awaiting is not a failure.'
    }
    $metrics.closedUnmerged = New-PortfolioMetric -Id 'delivery.closedUnmerged' -Value $closedUnmerged.Count -Numerator $closedUnmerged.Count -Denominator $opened.Count -AsOfUtc $AsOfUtc -Source $source `
        -Definition 'Opened pull requests GitHub reported closed without merging.'

    $freshAt = if ($null -ne $LastRefresh) { _DeliveryField -Obj $LastRefresh -Name 'lastReadAt' -Default $null } else { $null }
    $freshReason = if ($null -eq $LastRefresh) { 'No outcome refresh has been recorded.' } else { _DeliveryField -Obj $LastRefresh -Name 'reason' -Default $null }
    if ($null -eq $freshAt -and [string]::IsNullOrWhiteSpace([string]$freshReason)) { $freshReason = 'No outcome refresh has been recorded.' }
    $outcomeFreshness = [pscustomobject]@{
        lastReadAt = $freshAt
        source     = 'github'
        errorCount = $(if ($null -ne $LastRefresh) { _DeliveryField -Obj $LastRefresh -Name 'errorCount' -Default $null } else { $null })
        reason     = $freshReason
    }

    return [pscustomobject]@{
        asOf             = $AsOfUtc
        decisions        = $decidedCount
        metrics          = [pscustomobject]$metrics
        prs              = $prs
        decisionOutcomes = $decisionOutcomes
        outcomeFreshness = $outcomeFreshness
    }
}

function ConvertFrom-PullRequestUrl {
    <#
    .SYNOPSIS
        Split https://github.com/<owner>/<repo>/pull/<n> into parts, or $null.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([AllowEmptyString()][string]$PrUrl = '')
    $m = [regex]::Match([string]$PrUrl, '^https://github\.com/(?<owner>[^/]+)/(?<repo>[^/]+)/pull/(?<n>\d+)/?$')
    if (-not $m.Success) { return $null }
    return [pscustomobject]@{ owner = $m.Groups['owner'].Value; repo = $m.Groups['repo'].Value; number = [int]$m.Groups['n'].Value }
}

function Resolve-DeliveryCiConclusion {
    <#
    .SYNOPSIS
        One CI verdict from check runs plus the combined commit status.
    .DESCRIPTION
        Pure. Either source may be $null (unreadable); both null is
        'unavailable', never 'success'. Any failure wins, then anything still
        running, then success. Neutral and skipped checks do not fail a head.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [AllowNull()][object[]]$CheckRun = $null,
        [AllowNull()][object]$CombinedStatus = $null
    )
    if ($null -eq $CheckRun -and $null -eq $CombinedStatus) {
        return [pscustomobject]@{ conclusion = 'unavailable'; basis = 'neither check runs nor commit statuses were readable with the configured token' }
    }
    $signals = [System.Collections.Generic.List[string]]::new()
    foreach ($run in @($CheckRun | Where-Object { $null -ne $_ })) {
        $status = [string](_DeliveryField -Obj $run -Name 'status' -Default '')
        $conclusion = [string](_DeliveryField -Obj $run -Name 'conclusion' -Default '')
        if ($status -ne 'completed') { $signals.Add('pending') }
        elseif (@('failure', 'timed_out', 'cancelled', 'action_required', 'startup_failure') -contains $conclusion) { $signals.Add('failure') }
        else { $signals.Add('success') }
    }
    $statusCount = [int](_DeliveryField -Obj $CombinedStatus -Name 'total_count' -Default 0)
    if ($null -ne $CombinedStatus -and $statusCount -gt 0) {
        switch ([string](_DeliveryField -Obj $CombinedStatus -Name 'state' -Default '')) {
            'failure' { $signals.Add('failure') }
            'error' { $signals.Add('failure') }
            'pending' { $signals.Add('pending') }
            'success' { $signals.Add('success') }
        }
    }
    $basis = ('{0} check run(s), {1} commit status(es)' -f @($CheckRun | Where-Object { $null -ne $_ }).Count, $statusCount)
    # Unreadable check runs plus no commit status is not "no CI": most CI
    # reports through check runs, so nothing is known about the head.
    if ($null -eq $CheckRun -and $statusCount -eq 0) {
        return [pscustomobject]@{ conclusion = 'unavailable'; basis = 'check runs were not readable with the configured token and the head has no commit status' }
    }
    if ($signals.Count -eq 0) { return [pscustomobject]@{ conclusion = 'none'; basis = "no CI reported on the head commit ($basis)" } }
    if ($signals -contains 'failure') { return [pscustomobject]@{ conclusion = 'failure'; basis = $basis } }
    if ($signals -contains 'pending') { return [pscustomobject]@{ conclusion = 'pending'; basis = $basis } }
    return [pscustomobject]@{ conclusion = 'success'; basis = $basis }
}

function Update-DeliveryOutcome {
    <#
    .SYNOPSIS
        Ask GitHub what became of every opened PR not yet merged or closed,
        and append an outcome record wherever the state or CI changed.
    .PARAMETER GitHubGet
        Injectable for tests: receives a GitHub API path ('/repos/o/r/pulls/1')
        and returns the parsed body, or throws.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$WorkspaceRoot,
        [Parameter()][AllowEmptyString()][string]$Token = '',
        [Parameter()][AllowNull()][scriptblock]$GitHubGet = $null
    )
    $get = $GitHubGet
    if ($null -eq $get) {
        if ([string]::IsNullOrWhiteSpace($Token)) { throw 'No GitHub token is configured, so PR outcomes cannot be read.' }
        $get = {
            param([string]$ApiPath)
            Invoke-RestMethod -Uri ('https://api.github.com{0}' -f $ApiPath) -Method Get -TimeoutSec 20 -Headers @{
                Authorization = ('Bearer {0}' -f $Token); 'User-Agent' = 'GitHubRepoManagement'; Accept = 'application/vnd.github+json'
            }
        }.GetNewClosure()
    }

    $ledger = Get-DeliveryLedgerRecord -WorkspaceRoot $WorkspaceRoot
    $latest = @{}
    foreach ($r in $ledger.records) {
        if ([string](_DeliveryField -Obj $r -Name 'kind' -Default '') -eq 'outcome') { $latest[[string](_DeliveryField -Obj $r -Name 'prUrl' -Default '')] = $r }
    }
    $checked = 0; $appended = 0
    $errors = [System.Collections.Generic.List[object]]::new()
    $seen = @{}
    foreach ($d in $ledger.records) {
        if ([string](_DeliveryField -Obj $d -Name 'kind' -Default '') -ne 'decision') { continue }
        $url = [string](_DeliveryField -Obj $d -Name 'prUrl' -Default '')
        if ([string]::IsNullOrWhiteSpace($url) -or $seen.ContainsKey($url)) { continue }
        $seen[$url] = $true
        $prior = if ($latest.ContainsKey($url)) { $latest[$url] } else { $null }
        if ($null -ne $prior -and @('merged', 'closed-unmerged') -contains [string](_DeliveryField -Obj $prior -Name 'prState' -Default '')) { continue }
        $parts = ConvertFrom-PullRequestUrl -PrUrl $url
        if ($null -eq $parts) { $errors.Add([pscustomobject]@{ prUrl = $url; error = 'not a GitHub pull request URL' }); continue }
        $checked++
        try {
            $pr = & $get ('/repos/{0}/{1}/pulls/{2}' -f $parts.owner, $parts.repo, $parts.number)
            $state = if ([bool](_DeliveryField -Obj $pr -Name 'merged' -Default $false)) { 'merged' } elseif ([string](_DeliveryField -Obj $pr -Name 'state' -Default '') -eq 'closed') { 'closed-unmerged' } else { 'open' }
            $headSha = [string](_DeliveryField -Obj (_DeliveryField -Obj $pr -Name 'head' -Default $null) -Name 'sha' -Default '')
            $runs = $null; $combined = $null
            if ($headSha) {
                try { $runs = @(_DeliveryField -Obj (& $get ('/repos/{0}/{1}/commits/{2}/check-runs' -f $parts.owner, $parts.repo, $headSha)) -Name 'check_runs' -Default @()) } catch { $runs = $null }
                try { $combined = & $get ('/repos/{0}/{1}/commits/{2}/status' -f $parts.owner, $parts.repo, $headSha) } catch { $combined = $null }
            }
            $ci = Resolve-DeliveryCiConclusion -CheckRun $runs -CombinedStatus $combined
            $priorState = if ($null -ne $prior) { [string](_DeliveryField -Obj $prior -Name 'prState' -Default '') } else { '' }
            $priorCi = if ($null -ne $prior) { [string](_DeliveryField -Obj $prior -Name 'ciConclusion' -Default '') } else { '' }
            $priorHead = if ($null -ne $prior) { [string](_DeliveryField -Obj $prior -Name 'headSha' -Default '') } else { '' }
            # A new push is a new head: its verdict is a new reading even when
            # it matches the old one.
            if ($state -eq $priorState -and $ci.conclusion -eq $priorCi -and $headSha.ToLowerInvariant() -eq $priorHead) { continue }
            $mergedAt = _DeliveryTimestamp (_DeliveryField -Obj $pr -Name 'merged_at' -Default $null)
            $record = New-DeliveryOutcomeRecord -PrUrl $url -PrState $state -DecisionId ([string](_DeliveryField -Obj $d -Name 'decisionId' -Default '')) `
                -MergedAt ([string]$mergedAt) -HeadSha $headSha -CiConclusion $ci.conclusion -CiBasis $ci.basis
            if ($PSCmdlet.ShouldProcess($url, 'record PR outcome')) {
                Add-DeliveryLedgerRecord -WorkspaceRoot $WorkspaceRoot -Record $record
                $appended++
            }
        }
        catch {
            $errors.Add([pscustomobject]@{ prUrl = $url; error = $_.Exception.Message })
        }
    }

    # Freshness is established, never assumed: record when GitHub was read.
    $refreshedAt = $null
    $statePath = Resolve-OutputPath -WorkspaceRoot $WorkspaceRoot -RelativePath $script:DeliveryRefreshStateRelativePath
    if ($PSCmdlet.ShouldProcess($statePath, 'record when PR outcomes were read')) {
        $refreshedAt = [datetime]::UtcNow.ToString('o', [Globalization.CultureInfo]::InvariantCulture)
        $stateDir = Split-Path -Parent $statePath
        if (-not (Test-Path -LiteralPath $stateDir)) { $null = New-Item -ItemType Directory -Path $stateDir -Force }
        $stateJson = ConvertTo-Json -InputObject ([ordered]@{ refreshedAt = $refreshedAt; checked = $checked; appended = $appended; errorCount = $errors.Count }) -Depth 3
        Set-Content -LiteralPath $statePath -Value $stateJson -Encoding UTF8
    }
    return [pscustomobject]@{ checked = $checked; appended = $appended; errors = $errors.ToArray(); refreshedAt = $refreshedAt }
}
