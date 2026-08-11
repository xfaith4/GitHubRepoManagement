# Portfolio read-path performance budget (Release 3.2).
#
# Why this file exists: before it, nothing in the repo declared how long a
# portfolio read is ALLOWED to take, so a performance regression was invisible.
# The only number bounding a read was the Lane 0.4 request deadline (180s
# default / 900s scan tier), and that is a RELIABILITY ceiling, not a budget:
# it fires by calling Environment.FailFast and destroying every in-flight
# request. A target whose only enforcement is killing the host is a crash
# guard. It cannot tell you that a 400ms cache read became 4 seconds, which is
# exactly the regression an operator feels first.
#
# Dot-sourced rather than defined inside the host script, for the reason
# RequestDeadline.ps1, GitHubRateLimit.ps1 and OperationHeartbeat.ps1 are: a
# helper reachable only by starting the listener is a helper nothing can test.
#
# Design properties, each load-bearing:
#
#  - The budget is keyed off the SAME `cacheSource` string the routes already
#    put in their response payloads. The budget table and the served figure
#    therefore cannot disagree about which path ran — there is no second
#    classifier to drift out of step with the first (this repo's recurring
#    "two figures, one truth" failure).
#  - An UNKNOWN class is a breach, never a pass. A read path added without a
#    declared budget must fail loudly rather than silently score as within
#    budget; `declared=$false` forces `withinBudget=$false`, and a module-smoke
#    tripwire fails the gate when the host emits a cacheSource this table does
#    not know. Fail-closed is the same contract Test-PackagingQuota and
#    Test-RoadmapWriteBackEvidence use.
#  - The cold-scan budget is deliberately far BELOW the 900s scan-tier deadline.
#    Budgeting a cold scan at the crash guard would mean the first thing to
#    notice a regression is the guard killing the host — the outage this
#    product's own roadmap records three times. 300s sits above the measured
#    235s cold scan (Lane 0.9, live 2026-08-10) and well below 900s, so drift
#    toward the guard is reported while it is still only slow.

# Declared budgets, in milliseconds, per read class. `cacheSource` values are
# the literals the portfolio routes emit; see Get-PortfolioReadBudgetTable's
# tripwire in Invoke-ModuleSmokeTest.ps1, which fails if the host grows a class
# that is missing here.
#
#  memory            in-process assessment cache hit: no disk, no scan
#  portfolio-index   output/index/repos.index.json: one disk read + JSON parse
#  assessment-cache  index absent, rebuilt from the in-process cache payload
#  fresh-scan        a full cold rebuild of every signal
$script:PortfolioReadBudgetDefaults = @{
    'memory'           = 2000
    'portfolio-index'  = 3000
    'assessment-cache' = 3000
    'fresh-scan'       = 300000
}

# A budget below this cannot be met by any real read (JSON serialization of a
# 75-repo payload alone costs more), so a misconfigured 0/negative value would
# report a permanent false breach. A budget above the ceiling is meaningless:
# the request deadline terminates the host first.
$script:PortfolioReadBudgetFloorMs   = 100
$script:PortfolioReadBudgetCeilingMs = 3600000

function Get-PortfolioReadBudgetTable {
    <# The declared budget table. Pure; returns a copy so a caller cannot mutate
       the contract for every subsequent request. #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()
    $copy = @{}
    foreach ($key in $script:PortfolioReadBudgetDefaults.Keys) {
        $copy[$key] = [int]$script:PortfolioReadBudgetDefaults[$key]
    }
    return $copy
}

function Get-PortfolioReadBudgetClass {
    <# The read classes carrying a declared budget, for the drift tripwire.
       Singular noun per PowerShell convention (Get-ChildItem, Get-Process):
       the verb-noun names the item kind, not the cardinality of the result. #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param()
    return [string[]]@($script:PortfolioReadBudgetDefaults.Keys | Sort-Object)
}

function Resolve-PortfolioReadBudget {
    <# Resolve the budget for one read class. Returns 0 when the class is not
       declared — the caller must treat that as a breach, not as "no limit".

       A `performance.readPathBudgetMs` map in settings.json overrides per
       class; values are clamped into [floor, ceiling] rather than rejected, so
       a typo degrades to a usable bound instead of disabling the budget. #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$CacheSource,
        [Parameter()][object]$Settings = $null
    )

    $key = if ($null -eq $CacheSource) { '' } else { $CacheSource.Trim().ToLowerInvariant() }
    if (-not $script:PortfolioReadBudgetDefaults.ContainsKey($key)) { return 0 }

    $budget = [int]$script:PortfolioReadBudgetDefaults[$key]

    $override = $null
    if ($null -ne $Settings -and $Settings -is [System.Collections.IDictionary] -and $Settings.Contains('performance')) {
        $perf = $Settings['performance']
        if ($null -ne $perf -and $perf -is [System.Collections.IDictionary] -and $perf.Contains('readPathBudgetMs')) {
            $map = $perf['readPathBudgetMs']
            if ($null -ne $map -and $map -is [System.Collections.IDictionary] -and $map.Contains($key)) {
                $override = $map[$key]
            }
        }
    }

    if ($null -ne $override) {
        $parsed = 0
        if ([int]::TryParse([string]$override, [ref]$parsed)) { $budget = $parsed }
    }

    if ($budget -lt $script:PortfolioReadBudgetFloorMs) { $budget = $script:PortfolioReadBudgetFloorMs }
    if ($budget -gt $script:PortfolioReadBudgetCeilingMs) { $budget = $script:PortfolioReadBudgetCeilingMs }
    return $budget
}

function New-PortfolioReadBudgetResult {
    <# Pure evaluator: the measured figure reported NEXT TO the budget it was
       judged against, so a reader never has to go and find the target in a
       config file to know whether the number they are looking at is good.

       `declared=$false` (an unrecognized class) yields `withinBudget=$false`.
       An unbudgeted read path is not a fast one — it is an unmeasured one, and
       reporting it as passing is how a regression stays invisible. #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Pure evaluator: builds a verdict object from its inputs and mutates nothing. -WhatIf plumbing here would suggest the function changes state, which is the opposite of its contract.')]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$CacheSource,
        [Parameter(Mandatory)][double]$MeasuredMs,
        [Parameter()][object]$Settings = $null
    )

    $key = if ($null -eq $CacheSource) { '' } else { $CacheSource.Trim().ToLowerInvariant() }
    $budgetMs = Resolve-PortfolioReadBudget -CacheSource $key -Settings $Settings
    $declared = ($budgetMs -gt 0)
    $measured = [math]::Round([math]::Max(0, $MeasuredMs), 1)

    $withinBudget = $declared -and ($measured -le $budgetMs)
    $overByMs = if ($declared -and -not $withinBudget) { [math]::Round($measured - $budgetMs, 1) } else { 0 }

    return [pscustomobject]@{
        readClass    = $key
        declared     = $declared
        budgetMs     = $budgetMs
        measuredMs   = $measured
        withinBudget = $withinBudget
        overByMs     = $overByMs
    }
}

function Format-PortfolioReadBudgetLog {
    <# One greppable line per portfolio read, in the shape the existing
       scan-budget / scan-summary TRACE lines use, so Invoke-DailyEvidence.ps1
       can parse read performance the same way it already parses scan phases. #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][pscustomobject]$Result,
        [Parameter(Mandatory)][AllowEmptyString()][string]$CorrelationId,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Route
    )
    return ('[TRACE] portfolio.read-budget correlationId={0} route={1} class={2} measuredMs={3} budgetMs={4} withinBudget={5} overByMs={6} declared={7}' -f `
            $CorrelationId, $Route, $Result.readClass, $Result.measuredMs, $Result.budgetMs, $Result.withinBudget, $Result.overByMs, $Result.declared)
}
