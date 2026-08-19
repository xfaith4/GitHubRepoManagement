<#
.SYNOPSIS
    The decision-grade envelope every export and digest must carry: data
    window, units, headline finding, recommended next action.

.DESCRIPTION
    Release 3.3 milestone 4. The repo's own operating contract says a report
    or export must show what happened, why it matters, and what to do next.
    The payloads shipped counts and lists; the framing was left to whoever
    read them. A digest that says `byLevel: {ready: 3, blocked: 12}` makes a
    reader do the work of deciding whether that is good, over what period,
    and what to do about it -- and different readers decide differently.

    New-DecisionGradeEnvelope is the single place that shape is defined:

      dataWindow  - what period the numbers cover, stated as from/to/label.
                    A snapshot is a window too ('as of <t>'), and saying so
                    is the difference between "12 blocked" and "12 blocked
                    right now, which may be 3 after the next scan".
      units       - what the numbers ARE (repositories, findings, packets).
                    A bare 12 is not a measurement.
      headline    - the one sentence a reader who stops here should leave
                    with.
      nextAction  - what to DO. Not "review the results" -- a specific move.
      coverage    - optional: assessed vs total, so a percentage over a
                    partial set cannot read as a percentage over all of it.

    Test-DecisionGradeEnvelope is the predicate the smoke gates use, so
    "carries the contract" has exactly one definition rather than four
    hand-written assertions that can drift apart.
#>

Set-StrictMode -Version Latest

function New-DecisionGradeEnvelope {
    <#
    .SYNOPSIS
        Build the decision-grade envelope. Throws on the omissions that would
        make a report undecidable.
    #>
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Pure builder: constructs and validates an in-memory object, changes no system state, and is called from request handlers where no operator is present to answer a -WhatIf prompt.')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)][string]$Units,
        [Parameter(Mandatory = $true)][string]$Headline,
        [Parameter(Mandatory = $true)][string]$NextAction,
        # A point-in-time report passes From = To; that is a window one
        # instant wide, and stating it is the point.
        [Parameter()][string]$WindowFrom = '',
        [Parameter()][string]$WindowTo = '',
        [Parameter()][string]$WindowLabel = '',
        [Parameter()][AllowNull()][object]$AssessedCount = $null,
        [Parameter()][AllowNull()][object]$TotalCount = $null
    )

    foreach ($required in @(
            @{ Name = 'Units'; Value = $Units },
            @{ Name = 'Headline'; Value = $Headline },
            @{ Name = 'NextAction'; Value = $NextAction })) {
        if ([string]::IsNullOrWhiteSpace([string]$required.Value)) {
            throw ("Decision-grade envelope requires {0}: a report without it makes the reader guess." -f $required.Name)
        }
    }

    $nowUtc = (Get-Date).ToUniversalTime().ToString('o')
    $from = if ([string]::IsNullOrWhiteSpace($WindowFrom)) { $nowUtc } else { $WindowFrom }
    $to = if ([string]::IsNullOrWhiteSpace($WindowTo)) { $nowUtc } else { $WindowTo }
    $label = if ([string]::IsNullOrWhiteSpace($WindowLabel)) {
        if ($from -eq $to) { "point-in-time snapshot as of $to" } else { "$from to $to" }
    }
    else { $WindowLabel }

    $coverage = $null
    if ($null -ne $AssessedCount -and $null -ne $TotalCount) {
        $assessed = [int]$AssessedCount
        $total = [int]$TotalCount
        if ($assessed -gt $total) {
            throw ("Coverage is impossible: {0} assessed of {1} total." -f $assessed, $total)
        }
        $coverage = [pscustomobject]@{
            assessed = $assessed
            total    = $total
            # Null, not 0, when there is nothing to divide: an empty set has
            # no percentage, and 0% would read as a finding.
            percent  = $(if ($total -gt 0) { [math]::Round(($assessed / [double]$total) * 100, 1) } else { $null })
        }
    }

    return [pscustomobject]@{
        dataWindow = [pscustomobject]@{ from = $from; to = $to; label = $label }
        units      = $Units
        headline   = $Headline
        nextAction = $NextAction
        coverage   = $coverage
    }
}

function Test-DecisionGradeEnvelope {
    <#
    .SYNOPSIS
        Does this payload carry the decision-grade contract? One definition,
        used by every gate.
    .OUTPUTS
        [pscustomobject] ok, missing[] -- the field names that are absent or
        blank, so a failure names what to add.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter()][AllowNull()][object]$Payload)

    $missing = New-Object System.Collections.Generic.List[string]

    if ($null -eq $Payload) {
        $missing.Add('payload')
        return [pscustomobject]@{ ok = $false; missing = $missing.ToArray() }
    }

    $hasProperty = {
        param($Obj, $Name)
        if ($Obj -is [System.Collections.IDictionary]) { return $Obj.Contains($Name) }
        return ($null -ne $Obj.PSObject.Properties[$Name])
    }
    $valueOf = {
        param($Obj, $Name)
        if ($Obj -is [System.Collections.IDictionary]) { return $Obj[$Name] }
        return $Obj.$Name
    }

    foreach ($field in @('units', 'headline', 'nextAction')) {
        if (-not (& $hasProperty $Payload $field) -or [string]::IsNullOrWhiteSpace([string](& $valueOf $Payload $field))) {
            $missing.Add($field)
        }
    }

    if (-not (& $hasProperty $Payload 'dataWindow')) {
        $missing.Add('dataWindow')
    }
    else {
        $window = & $valueOf $Payload 'dataWindow'
        if ($null -eq $window) {
            $missing.Add('dataWindow')
        }
        else {
            foreach ($windowField in @('from', 'to', 'label')) {
                if (-not (& $hasProperty $window $windowField) -or [string]::IsNullOrWhiteSpace([string](& $valueOf $window $windowField))) {
                    $missing.Add("dataWindow.$windowField")
                }
            }
        }
    }

    return [pscustomobject]@{ ok = ($missing.Count -eq 0); missing = $missing.ToArray() }
}
