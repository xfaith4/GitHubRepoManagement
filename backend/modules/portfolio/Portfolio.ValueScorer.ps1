<#
.SYNOPSIS
    Value scoring for pending roadmap work in portfolio assessment responses.

.DESCRIPTION
    Release 1.7.5 — Phase 2.

    The scorer is intentionally deterministic and config-driven. It assigns a
    0-100 value score to each pending roadmap item using weighted dimensions:
    impact, unblock potential, risk reduction, repo maturity, effort fit,
    dependency reduction, and roadmap-order recency.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-PortfolioValueScoringConfig {
    [CmdletBinding()]
    param([string]$ConfigPath = '')

    if (-not [string]::IsNullOrWhiteSpace($ConfigPath) -and (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
        try {
            $raw = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 -ErrorAction Stop
            $cfg = ConvertFrom-Json -InputObject $raw -ErrorAction Stop
            if ($null -ne $cfg -and ($cfg.PSObject.Properties.Name -contains 'dimensions')) {
                return $cfg
            }
        } catch {
            Write-Warning ("Value scoring config could not be loaded from '{0}': {1}" -f $ConfigPath, $_.Exception.Message)
        }
    }

    return [pscustomobject]@{
        modelVersion = 'fallback'
        maxScore = 100
        dimensions = [pscustomobject]@{
            impact = [pscustomobject]@{ weight = 25 }
            unblockPotential = [pscustomobject]@{ weight = 20 }
            riskReduction = [pscustomobject]@{ weight = 20 }
            repoMaturity = [pscustomobject]@{ weight = 15 }
            effortFit = [pscustomobject]@{ weight = 10 }
            dependencyReduction = [pscustomobject]@{ weight = 5 }
            recency = [pscustomobject]@{ weight = 5 }
        }
        keywordRules = [pscustomobject]@{}
    }
}

function _PV_GetField {
    param([object]$Obj, [string]$Name, [object]$Default = $null)

    if ($null -eq $Obj) { return $Default }
    if ($Obj -is [System.Collections.IDictionary]) {
        if ($Obj.Contains($Name)) { return $Obj[$Name] }
        return $Default
    }
    if ($Obj.PSObject.Properties.Name -contains $Name) { return $Obj.$Name }
    return $Default
}

function _PV_ClampScore {
    param([double]$Value, [double]$Min = 0, [double]$Max = 5)
    if ($Value -lt $Min) { return $Min }
    if ($Value -gt $Max) { return $Max }
    return $Value
}

function _PV_GetWeight {
    param([object]$Config, [string]$DimensionName)

    $dimensions = _PV_GetField -Obj $Config -Name 'dimensions' -Default $null
    $dimension = _PV_GetField -Obj $dimensions -Name $DimensionName -Default $null
    return [double](_PV_GetField -Obj $dimension -Name 'weight' -Default 0)
}

function _PV_EvaluateKeywordRules {
    param(
        [string]$Text,
        [object]$Config,
        [string]$DimensionName,
        [double]$DefaultScore,
        # Aggregation semantics settled by operator 2026-07-06 (Release 2.7 Phase A):
        # MAX within a dimension. When $FloorAtOrBelow > 0 (used only for effortFit),
        # a matched keyword scoring <= that cap floors the dimension to the LOWEST
        # matched score even if a higher (bounded-verb) keyword also matched — so a
        # sprawling item ("Add a persistent OAuth distribution layer") does not read
        # as bounded one-task work.
        [double]$FloorAtOrBelow = 0
    )

    $matchedScores = [System.Collections.Generic.List[double]]::new()
    $labels = [System.Collections.Generic.List[string]]::new()
    $keywordRules = _PV_GetField -Obj $Config -Name 'keywordRules' -Default $null
    $rules = @(_PV_GetField -Obj $keywordRules -Name $DimensionName -Default @())

    foreach ($rule in $rules) {
        if ($null -eq $rule) { continue }
        $pattern = [string](_PV_GetField -Obj $rule -Name 'pattern' -Default '')
        if ([string]::IsNullOrWhiteSpace($pattern)) { continue }
        if ($Text -match $pattern) {
            $score = [double](_PV_GetField -Obj $rule -Name 'score' -Default $DefaultScore)
            $matchedScores.Add($score) | Out-Null
            $label = [string](_PV_GetField -Obj $rule -Name 'label' -Default '')
            if (-not [string]::IsNullOrWhiteSpace($label)) { $labels.Add($label) | Out-Null }
        }
    }

    if ($matchedScores.Count -eq 0) {
        $result = [double]$DefaultScore
    }
    elseif ($FloorAtOrBelow -gt 0 -and (@($matchedScores | Where-Object { $_ -le $FloorAtOrBelow }).Count -gt 0)) {
        # Floor triggered: pull down to the lowest matched score (intentionally
        # allowed to fall below DefaultScore — a sprawling item scores < baseline).
        $result = ($matchedScores | Measure-Object -Minimum).Minimum
    }
    else {
        # MAX aggregation, never below the dimension's DefaultScore (unchanged).
        $result = [math]::Max([double]$DefaultScore, ($matchedScores | Measure-Object -Maximum).Maximum)
    }

    return [pscustomobject]@{
        score = (_PV_ClampScore -Value $result)
        labels = @($labels | Select-Object -Unique)
    }
}

function Get-RoadmapItemExecutor {
    <#
    .SYNOPSIS
        Pure — decide whether a pending roadmap item can be executed by an agent
        or requires a person, and say why.

    .DESCRIPTION
        Value and dispatchability are different questions. The impact dimension
        rewards operator-FACING outcomes, which is right, but nothing in the
        weighted model asked whether an agent could perform the item at all — so
        manual work floated to the top of a queue that exists to dispatch work
        the operator does not have to do.

        A declared tag wins over an inferred keyword: the roadmap author knows,
        the regex guesses. `default` is 'agent', because refusing to dispatch is
        the expensive mistake — a wrongly parked item is work nobody picks up.

    .OUTPUTS
        [pscustomobject] executor ('agent'|'operator'), source
        ('declared-tag'|'inferred'|'default'), label
    #>
    [CmdletBinding()]
    param(
        [Parameter()][AllowEmptyString()][string]$ItemText = '',
        [Parameter()][AllowEmptyString()][string]$Section = '',
        [Parameter()][AllowEmptyCollection()][string[]]$Tags = @(),
        [Parameter()][object]$ScoringConfig
    )

    $cfg = if ($null -ne $ScoringConfig) { $ScoringConfig } else { Get-PortfolioValueScoringConfig }
    $classification = _PV_GetField -Obj $cfg -Name 'executorClassification' -Default $null

    $result = [pscustomobject]@{ executor = 'agent'; source = 'default'; label = '' }
    if ($null -eq $classification) { return $result }
    if (-not [bool](_PV_GetField -Obj $classification -Name 'enabled' -Default $false)) { return $result }

    $defaultExecutor = [string](_PV_GetField -Obj $classification -Name 'default' -Default 'agent')
    if ($defaultExecutor -in @('agent', 'operator')) { $result.executor = $defaultExecutor }

    # A declared tag is authoritative, and an explicit agent tag is what an author
    # uses to overrule a keyword that reads as manual but is not.
    $normalizedTags = @(@($Tags) | ForEach-Object { ([string]$_).Trim().ToLowerInvariant() } | Where-Object { $_ })
    $operatorTags = @(@(_PV_GetField -Obj $classification -Name 'operatorTags' -Default @()) | ForEach-Object { ([string]$_).ToLowerInvariant() })
    $agentTags = @(@(_PV_GetField -Obj $classification -Name 'agentTags' -Default @()) | ForEach-Object { ([string]$_).ToLowerInvariant() })

    foreach ($tag in $normalizedTags) {
        if ($agentTags -contains $tag) {
            $result.executor = 'agent'
            $result.source = 'declared-tag'
            $result.label = ("declared agent-executable by the [{0}] tag" -f $tag)
            return $result
        }
    }
    foreach ($tag in $normalizedTags) {
        if ($operatorTags -contains $tag) {
            $result.executor = 'operator'
            $result.source = 'declared-tag'
            $result.label = ("declared operator-only by the [{0}] tag" -f $tag)
            return $result
        }
    }

    # The section heading is part of the match surface on purpose: a sub-bullet
    # like "Captains submit in the PWA" is only recognizable as manual from the
    # section it sits under ("One shadow Thursday").
    $combined = ((@($ItemText, $Section) + @($Tags)) -join ' ').ToLowerInvariant()
    foreach ($rule in @(_PV_GetField -Obj $classification -Name 'operatorRules' -Default @())) {
        if ($null -eq $rule) { continue }
        $pattern = [string](_PV_GetField -Obj $rule -Name 'pattern' -Default '')
        if ([string]::IsNullOrWhiteSpace($pattern)) { continue }
        if ($combined -match $pattern) {
            $result.executor = 'operator'
            $result.source = 'inferred'
            $result.label = [string](_PV_GetField -Obj $rule -Name 'label' -Default 'matches an operator-only pattern')
            return $result
        }
    }

    return $result
}

function _PV_GetMaturityScore {
    param([string]$MaturityLevel)

    switch ($MaturityLevel) {
        'L4-Orchestration-Ready' { return 5 }
        'L3-Contract-Ready'      { return 4 }
        'L2-Structured'          { return 3 }
        'L1-Informal'            { return 2 }
        default                  { return 1 }
    }
}

function _PV_GetRecencyScore {
    param([int]$ItemIndex)

    if ($ItemIndex -le 0) { return 5 }
    if ($ItemIndex -le 2) { return 4 }
    if ($ItemIndex -le 5) { return 3 }
    if ($ItemIndex -le 9) { return 2 }
    return 1
}

function _PV_GetTier {
    param([int]$Score)

    if ($Score -ge 85) { return 'highest' }
    if ($Score -ge 70) { return 'high' }
    if ($Score -ge 50) { return 'medium' }
    if ($Score -ge 30) { return 'low' }
    return 'deferred'
}

function Invoke-PortfolioValueScore {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ItemText,
        [Parameter()][string]$Section = '',
        [Parameter()][AllowEmptyCollection()][string[]]$Tags = @(),
        [Parameter()][int]$ItemIndex = 0,
        [Parameter()][object]$RepoContext,
        [Parameter()][object]$ScoringConfig
    )

    $cfg = if ($null -ne $ScoringConfig) { $ScoringConfig } else { Get-PortfolioValueScoringConfig }
    $combined = ((@($ItemText, $Section) + @($Tags)) -join ' ').ToLowerInvariant()

    # effortFit floor cap (config-driven; 0 = disabled). Applies only to effortFit
    # so the other dimensions keep pure MAX aggregation.
    $effortFloorCap = 0.0
    $agg = _PV_GetField -Obj $cfg -Name 'aggregation' -Default $null
    $effFloor = _PV_GetField -Obj $agg -Name 'effortFitFloor' -Default $null
    if ($null -ne $effFloor -and [bool](_PV_GetField -Obj $effFloor -Name 'enabled' -Default $false)) {
        $effortFloorCap = [double](_PV_GetField -Obj $effFloor -Name 'cap' -Default 2)
    }

    $impact = _PV_EvaluateKeywordRules -Text $combined -Config $cfg -DimensionName 'impact' -DefaultScore 2
    $unblock = _PV_EvaluateKeywordRules -Text $combined -Config $cfg -DimensionName 'unblockPotential' -DefaultScore 1
    $risk = _PV_EvaluateKeywordRules -Text $combined -Config $cfg -DimensionName 'riskReduction' -DefaultScore 1
    $dependency = _PV_EvaluateKeywordRules -Text $combined -Config $cfg -DimensionName 'dependencyReduction' -DefaultScore 1
    $effort = _PV_EvaluateKeywordRules -Text $combined -Config $cfg -DimensionName 'effortFit' -DefaultScore 3 -FloorAtOrBelow $effortFloorCap

    $maturityLevel = [string](_PV_GetField -Obj $RepoContext -Name 'maturityLevel' -Default 'L0-Absent')
    $maturityScore = [double](_PV_GetMaturityScore -MaturityLevel $maturityLevel)
    $recencyScore = [double](_PV_GetRecencyScore -ItemIndex $ItemIndex)

    $dimensionScores = [ordered]@{
        impact              = [double]$impact.score
        unblockPotential    = [double]$unblock.score
        riskReduction       = [double]$risk.score
        repoMaturity        = [double]$maturityScore
        effortFit           = [double]$effort.score
        dependencyReduction = [double]$dependency.score
        recency             = [double]$recencyScore
    }

    $weights = [ordered]@{}
    $weightedTotal = 0.0
    foreach ($name in $dimensionScores.Keys) {
        $weight = _PV_GetWeight -Config $cfg -DimensionName $name
        $weights[$name] = $weight
        $weightedTotal += ([double]$dimensionScores[$name] / 5.0) * $weight
    }

    $maxScore = [int](_PV_GetField -Obj $cfg -Name 'maxScore' -Default 100)
    $valueScore = [int][math]::Round([math]::Max(0, [math]::Min($maxScore, $weightedTotal)), 0)

    $rationale = [System.Collections.Generic.List[string]]::new()
    foreach ($label in @($impact.labels + $unblock.labels + $risk.labels + $dependency.labels + $effort.labels | Select-Object -Unique | Select-Object -First 4)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$label)) { $rationale.Add([string]$label) | Out-Null }
    }
    if ($maturityScore -ge 4) {
        $rationale.Add(("repo maturity is {0}, so the work is likely dispatchable" -f $maturityLevel)) | Out-Null
    } elseif ($maturityScore -le 2) {
        $rationale.Add(("repo maturity is {0}, so value is tempered by readiness risk" -f $maturityLevel)) | Out-Null
    }
    if ($ItemIndex -eq 0) {
        $rationale.Add('first pending roadmap item') | Out-Null
    }
    if ($rationale.Count -eq 0) {
        $rationale.Add('baseline roadmap value with no strong keyword signal') | Out-Null
    }

    # Classification is reported, never scored. An operator-only item keeps the
    # value it earned; it simply belongs in the verification lane rather than the
    # dispatch queue, and the rationale says so where the operator reads it.
    $executor = Get-RoadmapItemExecutor -ItemText $ItemText -Section $Section -Tags $Tags -ScoringConfig $cfg
    if ($executor.executor -eq 'operator') {
        $reason = if ([string]::IsNullOrWhiteSpace([string]$executor.label)) { 'operator-only work' } else { [string]$executor.label }
        # Inserted at the head, not appended: valueRationale is truncated to five
        # entries, and "nobody can dispatch this" outranks every keyword label.
        $rationale.Insert(0, ("operator-only: {0}" -f $reason))
    }

    return [pscustomobject]@{
        text           = $ItemText
        section        = $Section
        tags           = @($Tags)
        roadmapOrder   = $ItemIndex + 1
        valueScore     = $valueScore
        valueTier      = (_PV_GetTier -Score $valueScore)
        executor       = [string]$executor.executor
        executorSource = [string]$executor.source
        executorReason = [string]$executor.label
        valueRationale = @($rationale | Select-Object -Unique | Select-Object -First 5)
        scoringSignals = [pscustomobject]@{
            dimensions = [pscustomobject]$dimensionScores
            weights    = [pscustomobject]$weights
            modelVersion = [string](_PV_GetField -Obj $cfg -Name 'modelVersion' -Default ([string](_PV_GetField -Obj $cfg -Name 'version' -Default 'unknown')))
        }
    }
}

function Invoke-PortfolioValueScores {
    [CmdletBinding()]
    param(
        [Parameter()][AllowEmptyCollection()][object[]]$PendingItems = @(),
        [Parameter()][object]$RepoContext,
        [Parameter()][object]$ScoringConfig
    )

    $items = [System.Collections.Generic.List[object]]::new()
    $index = 0
    foreach ($item in @($PendingItems)) {
        if ($null -eq $item) { continue }
        $text = [string](_PV_GetField -Obj $item -Name 'text' -Default '')
        if ([string]::IsNullOrWhiteSpace($text)) { continue }
        $section = [string](_PV_GetField -Obj $item -Name 'section' -Default '')
        $tags = @(_PV_GetField -Obj $item -Name 'tags' -Default @() | ForEach-Object { [string]$_ })

        $items.Add((Invoke-PortfolioValueScore `
            -ItemText $text `
            -Section $section `
            -Tags $tags `
            -ItemIndex $index `
            -RepoContext $RepoContext `
            -ScoringConfig $ScoringConfig)) | Out-Null
        $index++
    }

    return $items.ToArray()
}
