Set-StrictMode -Version Latest

<#
    Proof of value, loop step 8 - the delivery report.

    The 2026-10-16 evaluation's figures (about eight merged PRs on other
    repositories, 45 of 80 real runner runs failed, one repository ready,
    operator minutes never recorded) were counted by hand once and never again,
    and nobody recorded how. Nothing said whether the next week moved them.

    This file computes them from the product's own records: the delivery
    ledger (decisions and outcomes), the runner's run summaries, the docs audit
    cache, and GitHub for what became of each PR the product opened. Every
    figure is a New-PortfolioMetric object plus the window it counts over; one
    the records cannot compute is null with its reason, never 0.

    A PR counts as initiated by the product only when a product record names
    it: a delivery-ledger decision, a run summary's prUrl or agentTaskUrl, or
    a run's own branch (roadmap/<runId>) found on GitHub. This is the
    "verified product-originated" basis of
    evidence/trials/proof-of-value-2026-11/README.md. PRs on the product's own
    repository are excluded; the question is delivery to OTHER repositories.

    New-DeliveryReport is pure over what it is given; tools/New-DeliveryReport.ps1
    gathers the inputs and writes the files.
#>

$script:DeliveryReportSchemaVersion = '1'

function Test-DeliverySmokeRepository {
    <#
    .SYNOPSIS
        True when a run's repository is a smoke-test fixture, not real work.
    .DESCRIPTION
        Fixtures are named for it: an owner of smoke-owner, or a repository
        name with "smoke" as a hyphen-separated word (smoke-repo,
        dispatch-success-smoke).
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([AllowEmptyString()][string]$Repository = '')
    if ([string]::IsNullOrWhiteSpace($Repository)) { return $false }
    $parts = $Repository.Split('/')
    if ($parts.Count -ge 2 -and $parts[0] -eq 'smoke-owner') { return $true }
    return ($parts[-1] -match '(^|-)smoke($|-)')
}

function Get-RunnerFailureCause {
    <#
    .SYNOPSIS
        Name the cause of one failed runner run from its recorded error.
    .DESCRIPTION
        Pure. The causes are the ones the 2026-10-16 evaluation named, plus
        'other' (the error is kept as the example) and 'unrecorded' (the run
        failed and recorded no error).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowEmptyString()][string]$ErrorText = '')
    if ([string]::IsNullOrWhiteSpace($ErrorText)) { return 'unrecorded' }
    switch -Regex ($ErrorText) {
        'gh agent-task' { return 'copilot-task-create' }
        'GitHub token not found|token conflict|Bad credentials' { return 'github-token' }
        "GitHub CLI 'gh' was not found" { return 'gh-cli-missing' }
        'No roadmap markdown file found' { return 'missing-roadmap' }
        "No unchecked roadmap tasks|SelectedTask' because it is an empty" { return 'no-actionable-item' }
        'runner pid .* is not this runner' { return 'runner-pid-mismatch' }
        '(claude|codex|copilot) execution failed' { return 'agent-exit' }
    }
    return 'other'
}

function Get-RunnerRunSummary {
    <#
    .SYNOPSIS
        Read every runner run summary (*.summary.json), oldest first.
    .DESCRIPTION
        An unreadable summary is counted in `skipped`, never dropped silently.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)][string]$RunsDirectory)
    $runs = [System.Collections.Generic.List[object]]::new()
    $skipped = 0
    if (Test-Path -LiteralPath $RunsDirectory) {
        foreach ($file in (Get-ChildItem -LiteralPath $RunsDirectory -Filter '*.summary.json' -File | Sort-Object Name)) {
            try { $j = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json }
            catch { $skipped++; continue }
            $runs.Add([pscustomobject]@{
                runId      = [string](_DeliveryField -Obj $j -Name 'runId' -Default ($file.Name -replace '\.summary\.json$', ''))
                status     = [string](_DeliveryField -Obj $j -Name 'status' -Default '')
                repository = [string](_DeliveryField -Obj $j -Name 'repository' -Default '')
                startedAt  = _DeliveryTimestamp (_DeliveryField -Obj $j -Name 'startedAt' -Default $null)
                error      = [string](_DeliveryField -Obj $j -Name 'error' -Default '')
                branch     = [string](_DeliveryField -Obj $j -Name 'branch' -Default '')
                prUrl      = [string](_DeliveryField -Obj $j -Name 'prUrl' -Default '')
                # A dispatched Copilot run names its PR here, not in prUrl.
                agentTaskUrl = [string](_DeliveryField -Obj $j -Name 'agentTaskUrl' -Default '')
            })
        }
    }
    return [pscustomobject]@{ path = $RunsDirectory; runs = $runs.ToArray(); skipped = $skipped }
}

function _DeliveryParseUtc {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [datetime]) { return $Value.ToUniversalTime() }
    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    $parsed = [datetime]::MinValue
    $styles = [Globalization.DateTimeStyles]::AdjustToUniversal -bor [Globalization.DateTimeStyles]::AssumeUniversal
    if ([datetime]::TryParse($text, [Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$parsed)) { return $parsed }
    return $null
}

function _DeliveryInWindow {
    # Start is inclusive and may be $null (since records began); end is exclusive.
    param([AllowNull()][object]$At, [AllowNull()][object]$Start, [Parameter(Mandatory)][datetime]$End)
    $t = _DeliveryParseUtc $At
    if ($null -eq $t) { return $false }
    if ($null -ne $Start -and $t -lt $Start) { return $false }
    return ($t -lt $End)
}

function _DeliveryRepoKey {
    # owner/repo, lower-cased; a bare name takes the product's owner.
    param([AllowEmptyString()][string]$Repository, [AllowEmptyString()][string]$DefaultOwner)
    if ([string]::IsNullOrWhiteSpace($Repository)) { return '' }
    $r = $Repository.Trim()
    if ($r -notmatch '/' -and $DefaultOwner) { $r = '{0}/{1}' -f $DefaultOwner, $r }
    return $r.ToLowerInvariant()
}

function Resolve-DeliveryProductPullRequest {
    <#
    .SYNOPSIS
        Every PR a product record names on another repository, as GitHub
        reports it now.
    .DESCRIPTION
        Candidates: delivery-ledger decisions with a prUrl, run summaries with
        a prUrl, and runs whose recorded branch is the runner's own
        (roadmap/<runId>) looked up on GitHub by head. Smoke fixtures and the
        product's own repository are excluded. Each PR found is read for its
        state, merge time, head and the CI verdict on that head. A read that
        fails lands in `errors` with its PR or branch, never silently.
    .PARAMETER GitHubGet
        Receives a GitHub API path and returns the parsed body, or throws.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()][AllowEmptyCollection()][object[]]$Record = @(),
        [Parameter()][AllowEmptyCollection()][object[]]$Run = @(),
        [Parameter(Mandatory)][string]$ProductRepository,
        [Parameter(Mandatory)][scriptblock]$GitHubGet
    )
    $product = $ProductRepository.ToLowerInvariant()
    $owner = ($ProductRepository -split '/')[0]
    $byUrl = [ordered]@{}
    $errors = [System.Collections.Generic.List[object]]::new()

    $addUrl = {
        param([string]$Url, [string]$Source)
        # An agent-task URL is the PR URL plus /agent-sessions/<id>.
        $m = [regex]::Match([string]$Url, '^https://github\.com/[^/]+/[^/]+/pull/\d+')
        if (-not $m.Success) { return }
        $Url = $m.Value
        $parts = ConvertFrom-PullRequestUrl -PrUrl $Url
        if ($null -eq $parts) { return }
        if (('{0}/{1}' -f $parts.owner, $parts.repo).ToLowerInvariant() -eq $product) { return }
        if (Test-DeliverySmokeRepository -Repository ('{0}/{1}' -f $parts.owner, $parts.repo)) { return }
        $key = $Url.TrimEnd('/')
        if ($byUrl.Contains($key)) { if ($byUrl[$key].sources -notcontains $Source) { $byUrl[$key].sources += $Source }; return }
        $byUrl[$key] = [pscustomobject]@{ url = $key; parts = $parts; sources = @($Source); pr = $null }
    }

    foreach ($d in @($Record)) {
        if ([string](_DeliveryField -Obj $d -Name 'kind' -Default '') -ne 'decision') { continue }
        $u = [string](_DeliveryField -Obj $d -Name 'prUrl' -Default '')
        if ($u) { & $addUrl $u 'delivery-ledger' }
    }
    foreach ($r in @($Run)) {
        if ($r.prUrl) { & $addUrl $r.prUrl 'runner-run' }
        if ($r.PSObject.Properties.Name -contains 'agentTaskUrl' -and $r.agentTaskUrl) { & $addUrl $r.agentTaskUrl 'runner-agent-task' }
    }
    # Runner branches with no recorded PR: ask GitHub whether one was opened.
    $branchesTried = @{}
    foreach ($r in @($Run)) {
        if ($r.prUrl -or -not $r.branch) { continue }
        if ($r.PSObject.Properties.Name -contains 'agentTaskUrl' -and $r.agentTaskUrl) { continue }
        if ($r.branch -notmatch '^roadmap(-item|-repair)?/') { continue }
        $repoKey = _DeliveryRepoKey -Repository $r.repository -DefaultOwner $owner
        if (-not $repoKey -or $repoKey -eq $product -or (Test-DeliverySmokeRepository -Repository $repoKey)) { continue }
        $tryKey = '{0}#{1}' -f $repoKey, $r.branch
        if ($branchesTried.ContainsKey($tryKey)) { continue }
        $branchesTried[$tryKey] = $true
        $repoOwner = ($repoKey -split '/')[0]
        try {
            $found = @(& $GitHubGet ('/repos/{0}/pulls?state=all&head={1}:{2}' -f $repoKey, $repoOwner, [uri]::EscapeDataString($r.branch)))
            foreach ($p in $found) {
                $u = [string](_DeliveryField -Obj $p -Name 'html_url' -Default '')
                if ($u) { & $addUrl $u 'runner-branch'; if ($byUrl.Contains($u)) { $byUrl[$u].pr = $p } }
            }
        }
        catch { $errors.Add([pscustomobject]@{ target = $tryKey; error = $_.Exception.Message }) }
    }

    $prs = [System.Collections.Generic.List[object]]::new()
    foreach ($c in $byUrl.Values) {
        try {
            $pr = if ($null -ne $c.pr) { $c.pr } else { & $GitHubGet ('/repos/{0}/{1}/pulls/{2}' -f $c.parts.owner, $c.parts.repo, $c.parts.number) }
            $merged = $null -ne (_DeliveryField -Obj $pr -Name 'merged_at' -Default $null)
            $state = if ($merged) { 'merged' } elseif ([string](_DeliveryField -Obj $pr -Name 'state' -Default '') -eq 'closed') { 'closed-unmerged' } else { 'open' }
            $head = [string](_DeliveryField -Obj (_DeliveryField -Obj $pr -Name 'head' -Default $null) -Name 'sha' -Default '')
            $runs = $null; $combined = $null
            if ($head) {
                try { $runs = @(_DeliveryField -Obj (& $GitHubGet ('/repos/{0}/{1}/commits/{2}/check-runs' -f $c.parts.owner, $c.parts.repo, $head)) -Name 'check_runs' -Default @()) } catch { $runs = $null }
                try { $combined = & $GitHubGet ('/repos/{0}/{1}/commits/{2}/status' -f $c.parts.owner, $c.parts.repo, $head) } catch { $combined = $null }
            }
            $ci = Resolve-DeliveryCiConclusion -CheckRun $runs -CombinedStatus $combined
            $prs.Add([pscustomobject]@{
                url          = $c.url
                repository   = ('{0}/{1}' -f $c.parts.owner, $c.parts.repo)
                sources      = $c.sources
                createdAt    = _DeliveryTimestamp (_DeliveryField -Obj $pr -Name 'created_at' -Default $null)
                state        = $state
                mergedAt     = _DeliveryTimestamp (_DeliveryField -Obj $pr -Name 'merged_at' -Default $null)
                headSha      = $(if ($head) { $head.ToLowerInvariant() } else { $null })
                ciConclusion = $ci.conclusion
                ciBasis      = $ci.basis
            })
        }
        catch { $errors.Add([pscustomobject]@{ target = $c.url; error = $_.Exception.Message }) }
    }
    return [pscustomobject]@{ prs = $prs.ToArray(); errors = $errors.ToArray(); candidates = $byUrl.Count }
}

function _DeliveryFigure {
    # A metric plus the window it counts over.
    param([Parameter(Mandatory)][object]$Metric, [AllowNull()][object]$Start, [Parameter(Mandatory)][datetime]$End)
    $Metric | Add-Member -NotePropertyName 'window' -NotePropertyValue ([pscustomobject]@{
            start = $(if ($null -ne $Start) { $Start.ToString('o', [Globalization.CultureInfo]::InvariantCulture) } else { $null })
            end   = $End.ToString('o', [Globalization.CultureInfo]::InvariantCulture)
        }) -Force
    return $Metric
}

function New-DeliveryReport {
    <#
    .SYNOPSIS
        Build the delivery report from already-gathered records.
    .DESCRIPTION
        Pure over its inputs. -PullRequest is $null when GitHub could not be
        read at all; every PR figure then reads null with that reason. -Previous
        is an earlier report; each figure says what moved since it, or why it
        cannot.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Pure constructor: returns a report and touches nothing. Same precedent as New-PortfolioMetric.')]
    param(
        [Parameter(Mandatory)][string]$GeneratedAtUtc,
        [Parameter()][AllowEmptyString()][string]$WindowStartUtc = '',
        [Parameter(Mandatory)][string]$WindowEndUtc,
        [Parameter()][AllowEmptyCollection()][object[]]$Record = @(),
        [Parameter()][AllowEmptyCollection()][object[]]$Run = @(),
        [Parameter()][AllowNull()][object[]]$PullRequest = $null,
        [Parameter()][AllowEmptyString()][string]$PullRequestReason = '',
        [Parameter()][AllowEmptyCollection()][object[]]$ReadError = @(),
        [Parameter()][AllowNull()][object]$AuditCache = $null,
        [Parameter()][AllowNull()][object]$Previous = $null
    )
    $start = if ([string]::IsNullOrWhiteSpace($WindowStartUtc)) { $null } else { _DeliveryParseUtc $WindowStartUtc }
    $end = _DeliveryParseUtc $WindowEndUtc
    if ($null -eq $end) { throw ("WindowEndUtc '{0}' is not a parseable timestamp." -f $WindowEndUtc) }
    if ($null -ne $start -and $start -ge $end) { throw 'The window must start before it ends.' }
    $asOf = $GeneratedAtUtc
    $windowText = if ($null -ne $start) { ('{0:yyyy-MM-dd} to {1:yyyy-MM-dd}' -f $start, $end.AddSeconds(-1)) } else { ('records through {0:yyyy-MM-dd}' -f $end.AddSeconds(-1)) }
    $figures = [ordered]@{}

    # -- PRs the product initiated on other repositories ------------------------
    $prSource = 'github (PRs named by the delivery ledger, run summaries and runner branches)'
    if ($null -eq $PullRequest) {
        $why = if ($PullRequestReason) { $PullRequestReason } else { 'GitHub was not read.' }
        foreach ($id in 'prsInitiated', 'prsPassedCi', 'prsMerged') {
            $figures[$id] = _DeliveryFigure -Start $start -End $end -Metric (New-PortfolioMetric -Id ('delivery.report.{0}' -f $id) -AsOfUtc $asOf -Definition 'PRs the product initiated on other repositories.' -Reason $why)
        }
    }
    else {
        $initiated = @($PullRequest | Where-Object { _DeliveryInWindow -At $_.createdAt -Start $start -End $end })
        $merged = @($PullRequest | Where-Object { _DeliveryInWindow -At $_.mergedAt -Start $start -End $end })
        $ciRead = @($initiated | Where-Object { @('success', 'failure', 'pending', 'none') -contains $_.ciConclusion })
        $ciPassed = @($initiated | Where-Object { $_.ciConclusion -eq 'success' })
        $figures.prsInitiated = _DeliveryFigure -Start $start -End $end -Metric (New-PortfolioMetric -Id 'delivery.report.prsInitiated' -Value $initiated.Count -AsOfUtc $asOf -Source $prSource `
                -Definition ('Pull requests opened in the window ({0}) on other repositories that a product record names.' -f $windowText))
        if ($initiated.Count -eq 0) {
            $figures.prsPassedCi = _DeliveryFigure -Start $start -End $end -Metric (New-PortfolioMetric -Id 'delivery.report.prsPassedCi' -AsOfUtc $asOf `
                    -Definition 'Initiated PRs whose head commit passed CI.' -Reason 'No PR was initiated in the window.')
        }
        elseif ($ciRead.Count -eq 0) {
            $figures.prsPassedCi = _DeliveryFigure -Start $start -End $end -Metric (New-PortfolioMetric -Id 'delivery.report.prsPassedCi' -AsOfUtc $asOf -Assessed 0 -Total $initiated.Count `
                    -Definition 'Initiated PRs whose head commit passed CI.' -Reason ('CI could not be read on any of the {0} initiated PR(s): {1}.' -f $initiated.Count, (@($initiated | ForEach-Object ciBasis | Select-Object -Unique) -join '; ')))
        }
        else {
            $figures.prsPassedCi = _DeliveryFigure -Start $start -End $end -Metric (New-PortfolioMetric -Id 'delivery.report.prsPassedCi' -Value $ciPassed.Count -Numerator $ciPassed.Count -Denominator $ciRead.Count `
                    -Assessed $ciRead.Count -Total $initiated.Count -AsOfUtc $asOf -Source $prSource `
                    -Definition 'Initiated PRs whose current head commit passed CI (check runs and commit statuses), out of those whose CI could be read; coverage counts them against every initiated PR. A PR whose CI was unreadable is never counted as failed.')
        }
        $figures.prsMerged = _DeliveryFigure -Start $start -End $end -Metric (New-PortfolioMetric -Id 'delivery.report.prsMerged' -Value $merged.Count -AsOfUtc $asOf -Source $prSource `
                -Definition ('Product-initiated PRs on other repositories that merged in the window ({0}).' -f $windowText))
    }

    # -- Proposals and operator time, from the delivery ledger -------------------
    $allDecisions = @($Record | Where-Object { [string](_DeliveryField -Obj $_ -Name 'kind' -Default '') -eq 'decision' })
    # Decisions made in the window, and every outcome read before it closed (an
    # outcome read later must not change what this window reports).
    $windowed = @($Record | Where-Object {
            $k = [string](_DeliveryField -Obj $_ -Name 'kind' -Default '')
            $at = _DeliveryField -Obj $_ -Name 'recordedAt' -Default $null
            ($k -eq 'outcome' -and (_DeliveryInWindow -At $at -Start $null -End $end)) -or ($k -eq 'decision' -and (_DeliveryInWindow -At $at -Start $start -End $end))
        })
    $summary = Get-DeliverySummary -Record $windowed -AsOfUtc $asOf
    # A ledger that held nothing by the window end was not yet recording: its
    # zero is "not measured", not "none happened".
    $allDecisions = @($allDecisions | Where-Object { _DeliveryInWindow -At (_DeliveryField -Obj $_ -Name 'recordedAt' -Default $null) -Start $null -End $end })
    $noTimeReason = if ($allDecisions.Count -eq 0) { 'The delivery ledger held no decision by the window end: operator time was not recorded.' }
    elseif ($summary.decisions -eq 0) { ('No decision was recorded in the window ({0}).' -f $windowText) }
    else { $null }
    if ($null -ne $noTimeReason) {
        foreach ($m in $summary.metrics.operatorSeconds, $summary.metrics.operatorSecondsPerMergedImprovement) { $m.reason = $noTimeReason }
    }
    if ($allDecisions.Count -eq 0) {
        $figures.proposalsRejected = _DeliveryFigure -Start $start -End $end -Metric (New-PortfolioMetric -Id 'delivery.report.proposalsRejected' -AsOfUtc $asOf `
                -Definition 'Proposals the operator rejected, each with a reason.' -Reason 'The delivery ledger held no decision by the window end: accepts and rejects were not recorded.')
    }
    else {
        $figures.proposalsRejected = _DeliveryFigure -Start $start -End $end -Metric (New-PortfolioMetric -Id 'delivery.report.proposalsRejected' -Value $summary.metrics.rejected.value `
                -Numerator $summary.metrics.rejected.value -Denominator $summary.decisions -AsOfUtc $asOf -Source 'delivery-ledger' `
                -Definition 'Proposals the operator rejected in the window, out of all decided in it.')
    }
    $figures.operatorSeconds = _DeliveryFigure -Start $start -End $end -Metric $summary.metrics.operatorSeconds
    $figures.operatorSecondsPerMergedImprovement = _DeliveryFigure -Start $start -End $end -Metric $summary.metrics.operatorSecondsPerMergedImprovement

    # -- Agent runs and their failures, from the runner's run summaries ---------
    $real = @($Run | Where-Object { -not (Test-DeliverySmokeRepository -Repository $_.repository) -and (_DeliveryInWindow -At $_.startedAt -Start $start -End $end) })
    $undated = @($Run | Where-Object { -not (Test-DeliverySmokeRepository -Repository $_.repository) -and $null -eq (_DeliveryParseUtc $_.startedAt) })
    # Did not deliver and was not called off: failed, blocked by a gate, or refused.
    $failed = @($real | Where-Object { @('failed', 'blocked', 'refused') -contains $_.status })
    $runsSource = 'runner run summaries (output\roadmap-task-history\runs)'
    $runDef = 'Runner runs in the window on real repositories (smoke fixtures excluded), every status.'
    if ($undated.Count -gt 0) { $runDef += (' {0} run(s) recorded no start time and are not counted.' -f $undated.Count) }
    if (@($Run).Count -eq 0) {
        $figures.agentRuns = _DeliveryFigure -Start $start -End $end -Metric (New-PortfolioMetric -Id 'delivery.report.agentRuns' -AsOfUtc $asOf -Definition $runDef -Reason 'No runner run summary was found.')
        $figures.agentRunsFailed = _DeliveryFigure -Start $start -End $end -Metric (New-PortfolioMetric -Id 'delivery.report.agentRunsFailed' -AsOfUtc $asOf -Definition 'Runner runs in the window that failed.' -Reason 'No runner run summary was found.')
    }
    else {
        $figures.agentRuns = _DeliveryFigure -Start $start -End $end -Metric (New-PortfolioMetric -Id 'delivery.report.agentRuns' -Value $real.Count -AsOfUtc $asOf -Source $runsSource -Definition $runDef)
        $figures.agentRunsFailed = _DeliveryFigure -Start $start -End $end -Metric (New-PortfolioMetric -Id 'delivery.report.agentRunsFailed' -Value $failed.Count -Numerator $failed.Count -Denominator $real.Count -AsOfUtc $asOf -Source $runsSource `
                -Definition 'Runner runs in the window that failed, were blocked by a gate, or were refused (cancelled runs are not counted); failureCauses names why.')
    }
    $causes = [System.Collections.Generic.List[object]]::new()
    foreach ($g in @($failed | Group-Object { Get-RunnerFailureCause -ErrorText $_.error } | Sort-Object @{ e = 'Count'; Descending = $true }, Name)) {
        $first = $g.Group | Select-Object -First 1
        $causes.Add([pscustomobject]@{ cause = $g.Name; count = $g.Count; exampleRunId = $first.runId; example = $(if ($first.error.Length -gt 160) { $first.error.Substring(0, 160) } else { $first.error }) })
    }

    # -- Repositories ready for automated work, from the docs audit cache -------
    $readyDef = 'Audited repositories whose dispatch readiness is ready: eligible to receive agent work.'
    $auditedAt = if ($null -ne $AuditCache) { _DeliveryParseUtc (_DeliveryField -Obj $AuditCache -Name 'auditedAt' -Default (_DeliveryField -Obj $AuditCache -Name 'createdAtUtc' -Default $null)) } else { $null }
    if ($null -eq $AuditCache) {
        $figures.reposReady = _DeliveryFigure -Start $start -End $end -Metric (New-PortfolioMetric -Id 'delivery.report.reposReady' -AsOfUtc $asOf -Definition $readyDef -Reason 'No docs audit cache was found; no docs audit has run.')
    }
    elseif ($null -ne $auditedAt -and $auditedAt -ge $end) {
        $figures.reposReady = _DeliveryFigure -Start $start -End $end -Metric (New-PortfolioMetric -Id 'delivery.report.reposReady' -AsOfUtc $asOf -Definition $readyDef `
                -Reason ('The docs audit cache keeps only its latest audit ({0:yyyy-MM-dd}), which is after the window ends; readiness at the window end was not recorded.' -f $auditedAt))
    }
    else {
        $entries = @(_DeliveryField -Obj $AuditCache -Name 'entries' -Default @())
        $ready = @($entries | Where-Object { [string](_DeliveryField -Obj $_ -Name 'dispatchReadiness' -Default '') -eq 'ready' })
        $figures.reposReady = _DeliveryFigure -Start $start -End $end -Metric (New-PortfolioMetric -Id 'delivery.report.reposReady' -Value $ready.Count -Numerator $ready.Count -Denominator $entries.Count `
                -AsOfUtc $(if ($null -ne $auditedAt) { $auditedAt.ToString('o') } else { $asOf }) -Source 'docs-audit-cache' `
                -Definition ('{0} The denominator is the repositories the latest audit covered.' -f $readyDef))
    }

    # -- What moved since the previous report ------------------------------------
    $changes = [ordered]@{}
    $prevFigures = if ($null -ne $Previous) { _DeliveryField -Obj $Previous -Name 'figures' -Default $null } else { $null }
    # Counts over different windows are not comparable: a cumulative figure
    # minus a weekly one is not what moved.
    $prevWindow = if ($null -ne $Previous) { _DeliveryField -Obj $Previous -Name 'window' -Default $null } else { $null }
    $prevStart = _DeliveryParseUtc (_DeliveryField -Obj $prevWindow -Name 'start' -Default $null)
    $prevEnd = _DeliveryParseUtc (_DeliveryField -Obj $prevWindow -Name 'end' -Default $null)
    $sameWindow = if ($null -eq $Previous) { $true }
    elseif ($null -eq $start) { $null -eq $prevStart }
    elseif ($null -eq $prevStart -or $null -eq $prevEnd) { $false }
    else { ($end - $start) -eq ($prevEnd - $prevStart) }
    foreach ($id in @($figures.Keys)) {
        $cur = $figures[$id].value
        $prevMetric = if ($null -ne $prevFigures) { _DeliveryField -Obj $prevFigures -Name $id -Default $null } else { $null }
        $prev = if ($null -ne $prevMetric) { _DeliveryField -Obj $prevMetric -Name 'value' -Default $null } else { $null }
        $reason = if ($null -eq $Previous) { 'No earlier report to compare with.' }
        elseif (-not $sameWindow) { 'The earlier report counted over a window of a different shape.' }
        elseif ($null -eq $prevMetric) { 'The earlier report did not carry this figure.' }
        elseif ($null -eq $prev) { 'Not measured in the earlier report.' }
        elseif ($null -eq $cur) { 'Not measured in this report.' }
        else { $null }
        $changes[$id] = [pscustomobject]@{
            previous = $prev
            current  = $cur
            delta    = $(if ($null -eq $reason) { [double]$cur - [double]$prev } else { $null })
            reason   = $reason
        }
    }

    return [pscustomobject]@{
        schemaVersion  = $script:DeliveryReportSchemaVersion
        kind           = 'delivery-report'
        generatedAt    = $asOf
        window         = [pscustomobject]@{ start = $(if ($null -ne $start) { $start.ToString('o') } else { $null }); end = $end.ToString('o'); text = $windowText }
        figures        = [pscustomobject]$figures
        failureCauses  = $causes.ToArray()
        pullRequests   = $(if ($null -ne $PullRequest) { @($PullRequest | Where-Object { (_DeliveryInWindow -At $_.createdAt -Start $start -End $end) -or (_DeliveryInWindow -At $_.mergedAt -Start $start -End $end) }) } else { $null })
        readErrors     = @($ReadError)
        previous       = $(if ($null -ne $Previous) { [pscustomobject]@{ generatedAt = _DeliveryField -Obj $Previous -Name 'generatedAt' -Default $null; window = _DeliveryField -Obj $Previous -Name 'window' -Default $null } } else { $null })
        changes        = [pscustomobject]$changes
    }
}

function ConvertTo-DeliveryReportMarkdown {
    <#
    .SYNOPSIS
        Render a delivery report as Markdown: one row per figure with its unit,
        basis, window, source and what moved.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][object]$Report, [Parameter()][AllowEmptyString()][string]$Title = 'Delivery report')
    $sb = [System.Text.StringBuilder]::new()
    $null = $sb.AppendLine("# $Title").AppendLine()
    $null = $sb.AppendLine(('Generated {0}. Window: {1}.' -f $Report.generatedAt, $Report.window.text)).AppendLine()
    $null = $sb.AppendLine('| Figure | Value | Unit | Basis | Source | Since last |').AppendLine('| --- | --- | --- | --- | --- | --- |')
    foreach ($p in $Report.figures.PSObject.Properties) {
        $m = $p.Value
        $value = if ($null -eq $m.value) { ('not measured: {0}' -f $m.reason) } else { [string]$m.value }
        $basis = if ($null -ne $m.basis) { ('{0} of {1}' -f $m.basis.numerator, $m.basis.denominator) } else { '' }
        $c = $Report.changes.($p.Name)
        $moved = if ($null -ne $c.delta) { ('{0:+0;-0;0} (was {1})' -f $c.delta, $c.previous) } else { [string]$c.reason }
        $source = if ($m.source) { [string]$m.source } else { '' }
        $null = $sb.AppendLine(('| {0} | {1} | {2} | {3} | {4} | {5} |' -f $p.Name, ($value -replace '\|', '/'), $m.unit, $basis, ($source -replace '\|', '/'), ($moved -replace '\|', '/')))
    }
    $null = $sb.AppendLine()
    if (@($Report.failureCauses).Count -gt 0) {
        $null = $sb.AppendLine('## Agent-run failures by cause').AppendLine()
        $null = $sb.AppendLine('| Cause | Runs | Example run |').AppendLine('| --- | --- | --- |')
        foreach ($c in $Report.failureCauses) { $null = $sb.AppendLine(('| {0} | {1} | {2} |' -f $c.cause, $c.count, $c.exampleRunId)) }
        $null = $sb.AppendLine()
    }
    $baseline = _DeliveryField -Obj $Report -Name 'baselineComparison' -Default $null
    if ($null -ne $baseline) {
        $null = $sb.AppendLine('## Against the 2026-10-16 evaluation').AppendLine()
        $null = $sb.AppendLine('| Figure | Evaluation | This report | Note |').AppendLine('| --- | --- | --- | --- |')
        foreach ($b in $baseline) { $null = $sb.AppendLine(('| {0} | {1} | {2} | {3} |' -f $b.figure, $b.evaluation, $b.report, ($b.note -replace '\|', '/'))) }
        $null = $sb.AppendLine()
    }
    if (@($Report.readErrors).Count -gt 0) {
        $null = $sb.AppendLine('## Reads that failed').AppendLine()
        # One line per error: a reader may append a raw response body, which would break the list.
        foreach ($e in $Report.readErrors) { $null = $sb.AppendLine(('- {0}: {1}' -f $e.target, @(([string]$e.error).Trim() -split '\r?\n')[0])) }
        $null = $sb.AppendLine()
    }
    return $sb.ToString()
}
