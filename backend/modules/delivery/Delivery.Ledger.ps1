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
        [Parameter(Mandatory)][string]$AsOfUtc
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

    return [pscustomobject]@{
        asOf      = $AsOfUtc
        decisions = $decidedCount
        metrics   = [pscustomobject]$metrics
        prs       = $prs
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
            if ($state -eq $priorState -and $ci.conclusion -eq $priorCi) { continue }
            $mergedAt = [string](_DeliveryField -Obj $pr -Name 'merged_at' -Default '')
            $record = New-DeliveryOutcomeRecord -PrUrl $url -PrState $state -DecisionId ([string](_DeliveryField -Obj $d -Name 'decisionId' -Default '')) `
                -MergedAt $mergedAt -CiConclusion $ci.conclusion -CiBasis $ci.basis
            if ($PSCmdlet.ShouldProcess($url, 'record PR outcome')) {
                Add-DeliveryLedgerRecord -WorkspaceRoot $WorkspaceRoot -Record $record
                $appended++
            }
        }
        catch {
            $errors.Add([pscustomobject]@{ prUrl = $url; error = $_.Exception.Message })
        }
    }
    return [pscustomobject]@{ checked = $checked; appended = $appended; errors = $errors.ToArray() }
}
