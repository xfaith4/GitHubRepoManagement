<#
    Release 3.5 milestone 1 -- one snapshot, one clock, one provenance.

    The adversarial review found nine cross-tab contradictions with one root
    cause: four producers (live scan, portfolio index, execution ledger,
    app.db) each rendered by whichever component owned them, with no
    reconciliation layer and no shared "as of" instant. One screen reported
    76, 75, 52 and 27 repositories, and every number was right about its own
    source and wrong about the portfolio.

    This module is the reconciliation layer. Two rules, enforced in the
    constructor rather than stated in a comment:

    1. EVERY METRIC IS AN OBJECT, NEVER A BARE NUMBER -- value, unit, basis,
       asOf, source, coverage, confidence, definition. A tile that cannot
       state what it counted, over which set, as of when, from which source,
       has no business rendering.

    2. THE CONSTRUCTOR REFUSES TO BUILD A LYING METRIC. A percent outside
       0-100, a basis whose numerator exceeds its denominator, a value with no
       source -- these throw at construction, in the producer's stack frame,
       instead of rendering as a plausible number three tabs later. And an
       UNCOMPUTABLE metric is null with a reason, never 0: "not computed" and
       "zero" may not share a value (the milestone-4c rule, promoted to the
       contract).

    "Ready" is deliberately THREE metrics here, not one forced number. The
    five endpoints that disagreed (21 / 0 / 0) were measuring different
    things wearing one name: execution-lane readiness, dispatch readiness,
    and maturity readiness. The invariant the suite enforces is same-source
    equality -- each endpoint must equal ITS snapshot metric -- and the
    naming pass (milestone 7) gives the three their own labels in the UI.
#>

Set-StrictMode -Version Latest

$script:PortfolioSnapshotSchemaVersion = '1'

function New-PortfolioMetric {
    <#
    .SYNOPSIS
        Construct one snapshot metric -- or throw rather than build a lie.
    .DESCRIPTION
        Pure. `-Value $null` is legal and means NOT COMPUTED: it requires a
        -Reason and renders as an em dash at the boundary. A numeric value
        requires a -Source. Percent values must sit in 0-100; a basis must
        satisfy numerator <= denominator; coverage must satisfy
        assessed <= total. Confidence derives from coverage rather than being
        declared: full when assessed == total, partial otherwise, none when
        the value is null.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Pure constructor: it returns a metric object and never touches disk or process state. -WhatIf on a function that changes nothing would suggest it does. Same precedent as New-RoadmapCompletionEdit.')]
    param(
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter()][AllowNull()][object]$Value = $null,
        [Parameter()][ValidateSet('count', 'percent', 'seconds')][string]$Unit = 'count',
        [Parameter()][AllowNull()][object]$Numerator = $null,
        [Parameter()][AllowNull()][object]$Denominator = $null,
        [Parameter(Mandatory = $true)][string]$AsOfUtc,
        [Parameter()][AllowEmptyString()][string]$Source = '',
        [Parameter()][AllowNull()][object]$Assessed = $null,
        [Parameter()][AllowNull()][object]$Total = $null,
        [Parameter(Mandatory = $true)][string]$Definition,
        [Parameter()][AllowEmptyString()][string]$Reason = ''
    )

    # One clock: asOf must be parseable and is stored UTC ISO-8601. The render
    # boundary formats it exactly once, in the viewer's locale.
    $parsedAsOf = [datetime]::MinValue
    $styles = [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal
    if (-not [datetime]::TryParse($AsOfUtc, [System.Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$parsedAsOf)) {
        throw ("Metric '{0}': asOf '{1}' is not a parseable timestamp." -f $Id, $AsOfUtc)
    }
    $asOfIso = $parsedAsOf.ToUniversalTime().ToString('o')

    if ($null -eq $Value) {
        if ([string]::IsNullOrWhiteSpace($Reason)) {
            throw ("Metric '{0}': a null value means NOT COMPUTED and requires a reason the tile can render." -f $Id)
        }
    }
    else {
        if ([string]::IsNullOrWhiteSpace($Source)) {
            throw ("Metric '{0}': a computed value must name its source." -f $Id)
        }
        $numeric = [double]$Value
        if ($Unit -eq 'percent' -and ($numeric -lt 0 -or $numeric -gt 100)) {
            throw ("Metric '{0}': percent value {1} is outside 0-100. Fix the producer's arithmetic; the snapshot does not render impossible numbers." -f $Id, $numeric)
        }
        if ($Unit -eq 'count' -and $numeric -lt 0) {
            throw ("Metric '{0}': a count cannot be negative ({1})." -f $Id, $numeric)
        }
    }

    if ($null -ne $Numerator -and $null -ne $Denominator) {
        if ([double]$Numerator -gt [double]$Denominator) {
            throw ("Metric '{0}': basis {1}/{2} has a numerator above its denominator." -f $Id, $Numerator, $Denominator)
        }
    }
    if ($null -ne $Assessed -and $null -ne $Total) {
        if ([int]$Assessed -gt [int]$Total) {
            throw ("Metric '{0}': coverage {1}/{2} claims more assessed than exist." -f $Id, $Assessed, $Total)
        }
    }

    $confidence = if ($null -eq $Value) { 'none' }
    elseif ($null -ne $Assessed -and $null -ne $Total -and [int]$Assessed -lt [int]$Total) { 'partial' }
    else { 'full' }

    return [pscustomobject]@{
        id         = $Id
        value      = $Value
        unit       = $Unit
        basis      = $(if ($null -ne $Numerator -or $null -ne $Denominator) { [pscustomobject]@{ numerator = $Numerator; denominator = $Denominator } } else { $null })
        asOf       = $asOfIso
        source     = $(if ([string]::IsNullOrWhiteSpace($Source)) { $null } else { $Source })
        coverage   = $(if ($null -ne $Assessed -or $null -ne $Total) { [pscustomobject]@{ assessed = $Assessed; total = $Total } } else { $null })
        confidence = $confidence
        definition = $Definition
        reason     = $(if ([string]::IsNullOrWhiteSpace($Reason)) { $null } else { $Reason })
    }
}

function Build-PortfolioSnapshot {
    <#
    .SYNOPSIS
        Assemble the snapshot from already-gathered sources.
    .DESCRIPTION
        Pure over its inputs: the ROUTE gathers the sources (scan cache,
        roadmap cache, execution ledger, audit cache) and this function only
        judges them, so the whole contract is testable without a host. A
        source that is absent lands in `degraded[]` by name, and every metric
        that needed it reads null-with-reason -- never a guessed 0.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()][AllowNull()][object]$StatusData = $null,
        [Parameter()][AllowNull()][object]$ExecutionMetrics = $null,
        [Parameter()][AllowNull()][object]$AuditEntries = $null,
        [Parameter()][AllowNull()][object]$AssessmentSummary = $null,
        [Parameter()][AllowEmptyString()][string]$StatusAsOfUtc = '',
        [Parameter()][AllowEmptyString()][string]$GeneratedAtUtc = ''
    )

    $get = {
        param([object]$Obj, [string]$Name)
        if ($null -eq $Obj) { return $null }
        if ($Obj -is [System.Collections.IDictionary]) { if ($Obj.Contains($Name)) { return $Obj[$Name] } return $null }
        if ($Obj.PSObject.Properties.Name -contains $Name) { return $Obj.$Name }
        return $null
    }

    if ([string]::IsNullOrWhiteSpace($GeneratedAtUtc)) { $GeneratedAtUtc = (Get-Date).ToUniversalTime().ToString('o') }
    $degraded = [System.Collections.Generic.List[object]]::new()
    $metrics = [ordered]@{}

    # ---- The canonical denominator ---------------------------------------
    $repos = @(& $get $StatusData 'repos')
    $scanAsOf = if (-not [string]::IsNullOrWhiteSpace($StatusAsOfUtc)) { $StatusAsOfUtc } else { $GeneratedAtUtc }

    if ($null -eq $StatusData -or @($repos).Count -eq 0 -and $null -eq (& $get $StatusData 'repos')) {
        $degraded.Add([pscustomobject]@{ source = 'status-scan'; reason = 'No scan payload was available; every scan-derived metric reads not-computed.' }) | Out-Null
        $metrics['repoCount'] = New-PortfolioMetric -Id 'repoCount' -AsOfUtc $GeneratedAtUtc `
            -Definition 'Distinct repositories found by the workspace scan (scanned set, before scope).' `
            -Reason 'No scan has run.'
        $metrics['inScopeRepoCount'] = New-PortfolioMetric -Id 'inScopeRepoCount' -AsOfUtc $GeneratedAtUtc `
            -Definition 'Scanned repositories inside the scope policy: the denominator every portfolio percentage uses.' `
            -Reason 'No scan has run.'
        $metrics['staleRepoCount'] = New-PortfolioMetric -Id 'staleRepoCount' -AsOfUtc $GeneratedAtUtc `
            -Definition 'In-scope repositories whose local default branch is behind its remote (drift, not age).' `
            -Reason 'No scan has run.'
        $metrics['dirtyRepoCount'] = New-PortfolioMetric -Id 'dirtyRepoCount' -AsOfUtc $GeneratedAtUtc `
            -Definition 'In-scope repositories with uncommitted working-tree changes.' `
            -Reason 'No scan has run.'
    }
    else {
        $inScope = @($repos | Where-Object {
            $scope = & $get $_ 'scope'
            $null -eq $scope -or [bool](& $get $scope 'inScope')
        })
        $scannedCount = @($repos).Count
        $inScopeCount = @($inScope).Count

        $metrics['repoCount'] = New-PortfolioMetric -Id 'repoCount' -Value $scannedCount -AsOfUtc $scanAsOf -Source 'status-scan' `
            -Definition 'Distinct repositories found by the workspace scan (scanned set, before scope).'
        $metrics['inScopeRepoCount'] = New-PortfolioMetric -Id 'inScopeRepoCount' -Value $inScopeCount -AsOfUtc $scanAsOf -Source 'status-scan' `
            -Numerator $inScopeCount -Denominator $scannedCount `
            -Definition 'Scanned repositories inside the scope policy: the denominator every portfolio percentage uses.'

        $staleCount = @($inScope | Where-Object { [bool](& $get $_ 'isStale') }).Count
        $metrics['staleRepoCount'] = New-PortfolioMetric -Id 'staleRepoCount' -Value $staleCount -AsOfUtc $scanAsOf -Source 'status-scan' `
            -Numerator $staleCount -Denominator $inScopeCount `
            -Definition 'In-scope repositories whose local default branch is behind its remote (drift, not age).'

        $dirtyCount = @($inScope | Where-Object { [int](& $get $_ 'dirtyCount') -gt 0 -or [string](& $get $_ 'status') -eq 'dirty' }).Count
        $metrics['dirtyRepoCount'] = New-PortfolioMetric -Id 'dirtyRepoCount' -Value $dirtyCount -AsOfUtc $scanAsOf -Source 'status-scan' `
            -Numerator $dirtyCount -Denominator $inScopeCount `
            -Definition 'In-scope repositories with uncommitted working-tree changes.'
    }

    # ---- The three readinesses, named apart ------------------------------
    # The review's finding 1.3 (21 / 0 / 0) was three semantics wearing one
    # label. They stay three metrics; the vocabulary pass gives the UI their
    # names. Each endpoint must equal ITS metric -- that is the invariant.
    if ($null -ne $ExecutionMetrics) {
        $stateCounts = & $get $ExecutionMetrics 'stateCounts'
        $readyLanes = & $get $stateCounts 'ready'
        if ($null -ne $readyLanes) {
            $metrics['executionReadyCount'] = New-PortfolioMetric -Id 'executionReadyCount' -Value ([int]$readyLanes) -AsOfUtc $GeneratedAtUtc -Source 'execution-ledger' `
                -Definition 'Execution-lane entries in the ready state: work assigned and claimable right now.'
        }
        else {
            $metrics['executionReadyCount'] = New-PortfolioMetric -Id 'executionReadyCount' -AsOfUtc $GeneratedAtUtc `
                -Definition 'Execution-lane entries in the ready state: work assigned and claimable right now.' `
                -Reason 'The execution ledger reported no state counts.'
        }
    }
    else {
        $degraded.Add([pscustomobject]@{ source = 'execution-ledger'; reason = 'The execution ledger was not readable.' }) | Out-Null
        $metrics['executionReadyCount'] = New-PortfolioMetric -Id 'executionReadyCount' -AsOfUtc $GeneratedAtUtc `
            -Definition 'Execution-lane entries in the ready state: work assigned and claimable right now.' `
            -Reason 'The execution ledger was not readable.'
    }

    if ($null -ne $AuditEntries) {
        $dispatchReady = @(@($AuditEntries) | Where-Object { [string](& $get $_ 'dispatchReadiness') -eq 'ready' }).Count
        $metrics['dispatchReadyCount'] = New-PortfolioMetric -Id 'dispatchReadyCount' -Value $dispatchReady -AsOfUtc $GeneratedAtUtc -Source 'docs-audit-cache' `
            -Numerator $dispatchReady -Denominator (@($AuditEntries).Count) `
            -Assessed (@($AuditEntries).Count) -Total (@($AuditEntries).Count) `
            -Definition 'Audited repositories whose dispatch readiness is ready: eligible to receive agent work.'
    }
    else {
        $degraded.Add([pscustomobject]@{ source = 'docs-audit-cache'; reason = 'No docs audit has run; dispatch readiness is not computed.' }) | Out-Null
        $metrics['dispatchReadyCount'] = New-PortfolioMetric -Id 'dispatchReadyCount' -AsOfUtc $GeneratedAtUtc `
            -Definition 'Audited repositories whose dispatch readiness is ready: eligible to receive agent work.' `
            -Reason 'No docs audit has run.'
    }

    if ($null -ne $AssessmentSummary) {
        $maturityReady = & $get $AssessmentSummary 'readyForWorkCount'
        $assessedTotal = & $get $AssessmentSummary 'totalRepos'
        if ($null -ne $maturityReady) {
            $metrics['maturityReadyCount'] = New-PortfolioMetric -Id 'maturityReadyCount' -Value ([int]$maturityReady) -AsOfUtc $GeneratedAtUtc -Source 'portfolio-assessment' `
                -Assessed $assessedTotal -Total $assessedTotal `
                -Definition 'Assessed repositories at L3+ roadmap maturity with pending items: ready for value-ranked work.'
        }
        else {
            $metrics['maturityReadyCount'] = New-PortfolioMetric -Id 'maturityReadyCount' -AsOfUtc $GeneratedAtUtc `
                -Definition 'Assessed repositories at L3+ roadmap maturity with pending items: ready for value-ranked work.' `
                -Reason 'The assessment summary carried no ready count.'
        }
    }
    else {
        $degraded.Add([pscustomobject]@{ source = 'portfolio-assessment'; reason = 'No portfolio assessment has run; maturity readiness is not computed.' }) | Out-Null
        $metrics['maturityReadyCount'] = New-PortfolioMetric -Id 'maturityReadyCount' -AsOfUtc $GeneratedAtUtc `
            -Definition 'Assessed repositories at L3+ roadmap maturity with pending items: ready for value-ranked work.' `
            -Reason 'No portfolio assessment has run.'
    }

    return [pscustomobject]@{
        schemaVersion = $script:PortfolioSnapshotSchemaVersion
        generatedAt   = $GeneratedAtUtc
        degraded      = @($degraded)
        metrics       = [pscustomobject]$metrics
    }
}
