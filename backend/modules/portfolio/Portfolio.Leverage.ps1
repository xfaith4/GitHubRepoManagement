<#
.SYNOPSIS
    Release 3.6 M5 - does this product return more time than it takes?
.DESCRIPTION
    The leverage family, derived from ledgers the product already keeps: agent
    runs, the execution ledger, the conclusion model, and the operator
    verification log. Nothing here starts a new capture except where the
    roadmap says one is needed, and where a figure cannot be derived it is
    returned as null WITH ITS REASON - never a 0 that reads as measured.

    That rule is the whole point. A leverage dashboard that shows 0% where it
    means "not captured" would argue the product is worthless using a number
    nobody measured.

    Param-less: the API host dot-sources this file.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function _PL_GetField {
    param([object]$Obj, [string]$Name, [object]$Default = $null)
    if ($null -eq $Obj) { return $Default }
    if ($Obj -is [System.Collections.IDictionary]) {
        if ($Obj.Contains($Name)) { return $Obj[$Name] }
        return $Default
    }
    if ($null -eq $Obj.PSObject) { return $Default }
    foreach ($prop in $Obj.PSObject.Properties) { if ($prop.Name -eq $Name) { return $prop.Value } }
    return $Default
}

function _PL_NewMetric {
    <#
    .SYNOPSIS
        One leverage figure, or an honest absence.
    .DESCRIPTION
        `available = $false` with a `basis` naming what is missing is a valid,
        expected result. Callers render the basis; they never substitute 0.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter()][object]$Value = $null,
        [Parameter()][string]$Unit = 'count',
        [Parameter(Mandatory = $true)][string]$Basis,
        [Parameter()][int]$SampleSize = 0
    )

    $available = ($null -ne $Value)
    return [pscustomobject]@{
        key        = $Key
        label      = $Label
        value      = $Value
        unit       = $Unit
        available  = $available
        basis      = $Basis
        sampleSize = $SampleSize
    }
}

function Get-PortfolioLeverage {
    <#
    .SYNOPSIS
        The leverage family for a window, each metric carrying its own basis.
    .PARAMETER AgentRuns
        Rows from the agent-run metrics history (or the JSON ledger fallback).
    .PARAMETER ExecutionMetrics
        The execution-metrics payload.
    .PARAMETER Conclusions
        The conclusions payload, for outcome-shaped leverage.
    .PARAMETER OperatorVerifications
        Parsed lines of evidence/operator-verification-log.jsonl.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()][AllowEmptyCollection()][object[]]$AgentRuns = @(),
        [Parameter()][object]$ExecutionMetrics = $null,
        [Parameter()][object]$Conclusions = $null,
        [Parameter()][AllowEmptyCollection()][object[]]$OperatorVerifications = @(),
        [Parameter()][int]$WindowDays = 30
    )

    $metrics = [System.Collections.Generic.List[object]]::new()
    $runs = @($AgentRuns | Where-Object { $null -ne $_ })

    # ---- Agent first-pass success -------------------------------------------
    # A run that completed without a retry did what was asked the first time.
    $completed = @($runs | Where-Object {
        [string](_PL_GetField -Obj $_ -Name 'status' -Default '') -in @('completed', 'merged', 'succeeded', 'success')
    })
    if ($completed.Count -gt 0) {
        $firstPass = @($completed | Where-Object { [int](_PL_GetField -Obj $_ -Name 'retryCount' -Default 0) -le 0 })
        $metrics.Add((_PL_NewMetric -Key 'agentFirstPassSuccess' -Label 'Agent first-pass success' `
            -Value ([math]::Round(($firstPass.Count / [double]$completed.Count) * 100.0, 1)) -Unit 'percent' `
            -Basis ("{0} of {1} completed agent run(s) in the last {2} days needed no retry." -f $firstPass.Count, $completed.Count, $WindowDays) `
            -SampleSize $completed.Count)) | Out-Null
    }
    else {
        $metrics.Add((_PL_NewMetric -Key 'agentFirstPassSuccess' -Label 'Agent first-pass success' `
            -Unit 'percent' -Basis ("No agent run completed in the last {0} days, so first-pass success has no sample." -f $WindowDays))) | Out-Null
    }

    # ---- Estimate accuracy ---------------------------------------------------
    # Work-unit estimates are what the product asks operators to plan against;
    # this says whether they hold. Only runs carrying BOTH figures count.
    $estimated = @($runs | Where-Object {
        $e = _PL_GetField -Obj $_ -Name 'workUnitsEstimated' -Default $null
        $a = _PL_GetField -Obj $_ -Name 'workUnitsActual' -Default $null
        ($null -ne $e) -and ($null -ne $a) -and ([double]$e -gt 0)
    })
    if ($estimated.Count -gt 0) {
        $ratios = @($estimated | ForEach-Object {
            [double](_PL_GetField -Obj $_ -Name 'workUnitsActual' -Default 0) / [double](_PL_GetField -Obj $_ -Name 'workUnitsEstimated' -Default 1)
        })
        $metrics.Add((_PL_NewMetric -Key 'estimateAccuracy' -Label 'Actual vs estimated work' `
            -Value ([math]::Round((($ratios | Measure-Object -Average).Average) * 100.0, 1)) -Unit 'percent' `
            -Basis ("Mean actual-over-estimated work units across {0} run(s) that recorded both. 100% means estimates held." -f $estimated.Count) `
            -SampleSize $estimated.Count)) | Out-Null
    }
    else {
        $metrics.Add((_PL_NewMetric -Key 'estimateAccuracy' -Label 'Actual vs estimated work' `
            -Unit 'percent' -Basis 'No agent run recorded both an estimate and an actual, so estimate accuracy cannot be derived.')) | Out-Null
    }

    # ---- Delivery time -------------------------------------------------------
    $delivered = @($runs | Where-Object {
        $s = _PL_GetField -Obj $_ -Name 'timeToDeliverSeconds' -Default $null
        ($null -ne $s) -and ([double]$s -gt 0)
    })
    if ($delivered.Count -gt 0) {
        $avgSeconds = ($delivered | ForEach-Object { [double](_PL_GetField -Obj $_ -Name 'timeToDeliverSeconds' -Default 0) } | Measure-Object -Average).Average
        $metrics.Add((_PL_NewMetric -Key 'agentTimeToDeliver' -Label 'Agent time to deliver' `
            -Value ([math]::Round($avgSeconds / 60.0, 1)) -Unit 'minutes' `
            -Basis ("Mean elapsed time from dispatch to delivery across {0} run(s). This is agent time, not operator time." -f $delivered.Count) `
            -SampleSize $delivered.Count)) | Out-Null
    }
    else {
        $metrics.Add((_PL_NewMetric -Key 'agentTimeToDeliver' -Label 'Agent time to deliver' `
            -Unit 'minutes' -Basis 'No agent run recorded a delivery time.')) | Out-Null
    }

    # ---- Work completed ------------------------------------------------------
    if ($null -ne $ExecutionMetrics) {
        $completedThisWeek = _PL_GetField -Obj $ExecutionMetrics -Name 'completedThisWeek' -Default $null
        if ($null -ne $completedThisWeek) {
            $metrics.Add((_PL_NewMetric -Key 'tasksCompletedThisWeek' -Label 'Tasks completed this week' `
                -Value ([int]$completedThisWeek) -Unit 'count' `
                -Basis 'Execution ledger entries that reached the complete state in the last 7 days.')) | Out-Null
        }
    }
    else {
        $metrics.Add((_PL_NewMetric -Key 'tasksCompletedThisWeek' -Label 'Tasks completed this week' `
            -Unit 'count' -Basis 'The execution ledger was not readable.')) | Out-Null
    }

    # ---- Outcome-shaped leverage --------------------------------------------
    # A repository concluded appropriate-as-is is work the operator does NOT
    # have to do. That is leverage: the product's most valuable answer is often
    # "nothing here needs you".
    if ($null -ne $Conclusions) {
        $byConclusion = _PL_GetField -Obj $Conclusions -Name 'byConclusion' -Default $null
        $total = [int](_PL_GetField -Obj $Conclusions -Name 'count' -Default 0)
        $healthy = [int](_PL_GetField -Obj $byConclusion -Name 'appropriate-as-is' -Default 0)
        $strengthen = [int](_PL_GetField -Obj $byConclusion -Name 'strengthen' -Default 0)
        if ($total -gt 0) {
            $metrics.Add((_PL_NewMetric -Key 'repositoriesNeedingNothing' -Label 'Repositories needing nothing' `
                -Value $healthy -Unit 'count' `
                -Basis ("{0} of {1} repositories concluded appropriate as-is - work the operator does not have to do." -f $healthy, $total) `
                -SampleSize $total)) | Out-Null
            $metrics.Add((_PL_NewMetric -Key 'repositoriesWithANextStep' -Label 'Repositories with a next step' `
                -Value $strengthen -Unit 'count' `
                -Basis ("{0} of {1} repositories carry a specific, previewable next action." -f $strengthen, $total) `
                -SampleSize $total)) | Out-Null
        }
    }
    else {
        $metrics.Add((_PL_NewMetric -Key 'repositoriesNeedingNothing' -Label 'Repositories needing nothing' `
            -Unit 'count' -Basis 'No conclusions payload was supplied.')) | Out-Null
    }

    # ---- Operator proofs -----------------------------------------------------
    $verifications = @($OperatorVerifications | Where-Object { $null -ne $_ })
    $metrics.Add((_PL_NewMetric -Key 'operatorVerifiedSurfaces' -Label 'Operator-verified surfaces' `
        -Value $verifications.Count -Unit 'count' `
        -Basis ("Entries in evidence/operator-verification-log.jsonl. An unrecorded proof is indistinguishable from one that never happened." ) `
        -SampleSize $verifications.Count)) | Out-Null

    # ---- Declared-not-derived ------------------------------------------------
    # The roadmap names these; the product does not capture them yet. They ship
    # unavailable-with-a-reason rather than silently absent, so the gap is
    # visible on the surface that would otherwise imply it was measured.
    $metrics.Add((_PL_NewMetric -Key 'operatorMinutesPerTask' -Label 'Operator minutes per task' `
        -Unit 'minutes' -Basis 'Not captured: the product records agent elapsed time, never the operator''s own minutes. Capturing it needs an operator-side timer this product does not have.')) | Out-Null
    $metrics.Add((_PL_NewMetric -Key 'recommendationsAccepted' -Label 'Recommendations accepted vs rejected' `
        -Unit 'percent' -Basis 'Not captured: approving or rejecting a packaged item leaves no accept/reject ledger. This is the one new capture Release 3.6 names, and it is not built.')) | Out-Null

    $available = @($metrics | Where-Object { $_.available })
    return [pscustomobject]@{
        schemaVersion  = 'v1'
        model          = 'portfolio-leverage'
        windowDays     = $WindowDays
        metricCount    = $metrics.Count
        availableCount = $available.Count
        metrics        = @($metrics)
    }
}

function Test-LeverageMetricContract {
    <#
    .SYNOPSIS
        Return the ways a leverage payload breaks its contract; empty means it holds.
    .DESCRIPTION
        Every metric must carry a basis; an unavailable metric must have a null
        value (never a 0 standing in for "not measured"); an available metric
        must have a value. This is the decision-grade rule the product already
        applies to its exports, enforced here before anything renders.
    #>
    [CmdletBinding()]
    [OutputType([System.Object[]])]
    param([Parameter(Mandatory = $true)][object]$Payload)

    $violations = [System.Collections.Generic.List[string]]::new()
    $metrics = @(_PL_GetField -Obj $Payload -Name 'metrics' -Default @())
    if ($metrics.Count -eq 0) { $violations.Add('the leverage payload carries no metrics') | Out-Null }

    foreach ($metric in $metrics) {
        $key = [string](_PL_GetField -Obj $metric -Name 'key' -Default '?')
        $basis = [string](_PL_GetField -Obj $metric -Name 'basis' -Default '')
        $value = _PL_GetField -Obj $metric -Name 'value' -Default $null
        $available = [bool](_PL_GetField -Obj $metric -Name 'available' -Default $false)
        if ([string]::IsNullOrWhiteSpace($basis)) { $violations.Add("$key states no basis") | Out-Null }
        if ($available -and $null -eq $value) { $violations.Add("$key claims to be available but carries no value") | Out-Null }
        if (-not $available -and $null -ne $value) { $violations.Add("$key is unavailable but carries the value '$value' - an unmeasured figure must be null") | Out-Null }
        if ([string]::IsNullOrWhiteSpace([string](_PL_GetField -Obj $metric -Name 'label' -Default ''))) { $violations.Add("$key has no label") | Out-Null }
    }
    return @($violations)
}
