if (-not (Get-Variable -Scope Script -Name MetricsStore -ErrorAction SilentlyContinue)) {
    $script:MetricsStore = [ordered]@{
        counters = @{}
        gauges = @{}
        histograms = @{}
    }
}

function Reset-MetricsStore {
    [CmdletBinding()]
    param()

    $script:MetricsStore = [ordered]@{
        counters = @{}
        gauges = @{}
        histograms = @{}
    }
}

function Add-MetricCounter {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter()]
        [double]$Value = 1
    )

    if (-not $script:MetricsStore.counters.ContainsKey($Name)) {
        $script:MetricsStore.counters[$Name] = 0.0
    }
    $script:MetricsStore.counters[$Name] = [double]$script:MetricsStore.counters[$Name] + $Value
}

function Set-MetricGauge {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [double]$Value
    )

    $script:MetricsStore.gauges[$Name] = $Value
}

function Add-MetricHistogramValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [double]$Value
    )

    if (-not $script:MetricsStore.histograms.ContainsKey($Name)) {
        $script:MetricsStore.histograms[$Name] = @()
    }

    $current = @($script:MetricsStore.histograms[$Name])
    $script:MetricsStore.histograms[$Name] = @($current + $Value)
}

function Get-MetricsSnapshot {
    [CmdletBinding()]
    param()

    $histogramSummary = @{}
    foreach ($name in $script:MetricsStore.histograms.Keys) {
        $values = @($script:MetricsStore.histograms[$name])
        $count = $values.Count
        $sum = ($values | Measure-Object -Sum).Sum
        $avg = if ($count -gt 0) { [double]$sum / $count } else { 0.0 }
        $min = if ($count -gt 0) { ($values | Measure-Object -Minimum).Minimum } else { 0.0 }
        $max = if ($count -gt 0) { ($values | Measure-Object -Maximum).Maximum } else { 0.0 }

        $histogramSummary[$name] = [ordered]@{
            count = $count
            sum = [double]$sum
            avg = [double]$avg
            min = [double]$min
            max = [double]$max
        }
    }

    return [ordered]@{
        counters = [ordered]@{} + $script:MetricsStore.counters
        gauges = [ordered]@{} + $script:MetricsStore.gauges
        histograms = $histogramSummary
        generatedAt = (Get-Date).ToString('o')
    }
}
