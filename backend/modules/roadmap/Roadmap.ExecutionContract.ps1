<#
.SYNOPSIS
    Shared execution-contract sufficiency model for roadmap dispatch.
.DESCRIPTION
    Interactive dispatch, scheduled packaging, and visible portfolio readiness
    must consult this verdict instead of maintaining private maturity gates.
    Maturity remains useful evidence: L3+ is the default sizing signal, while a
    lower-maturity roadmap may qualify only when the actual task is explicitly
    bounded to one selected item or to an estimated active phase.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function _ExecutionContractGetField {
    param([object]$InputObject, [string]$Name, [object]$Default = $null)

    if ($null -eq $InputObject) { return $Default }
    if ($InputObject -is [System.Collections.IDictionary]) {
        if ($InputObject.Contains($Name)) { return $InputObject[$Name] }
        return $Default
    }
    if ($null -ne $InputObject.PSObject -and ($InputObject.PSObject.Properties.Name -contains $Name)) {
        return $InputObject.$Name
    }
    return $Default
}

function _ExecutionContractMeaningfulStrings {
    param([object[]]$Values)

    return @($Values | ForEach-Object { [string]$_ } | Where-Object {
        -not [string]::IsNullOrWhiteSpace($_) -and $_ -notmatch '(?i)^\s*(?:tbd|todo|none|n/?a|not yet)\s*[.!]?\s*$'
    })
}

function Test-RoadmapRunnableVerification {
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter()][AllowEmptyCollection()][string[]]$Text = @())

    $combined = (_ExecutionContractMeaningfulStrings -Values @($Text)) -join "`n"
    if ([string]::IsNullOrWhiteSpace($combined)) { return $false }

    # A runnable proof names either an executable command/script in code spans
    # or an HTTP method + route. Generic prose such as "run tests" is useful
    # intent, but it is not something an agent can execute without guessing.
    $commandPattern = '(?i)(?:`\s*(?:npm|pnpm|yarn|npx|node|dotnet|pytest|python3?|pwsh|powershell|go|cargo|mvn|gradle|make|bash|sh|git)\b[^`]*`|`[^`]*(?:\.ps1|\.psm1|\.sh|\.cmd|\.bat|\.py|\.js|\.ts|\.cjs)\b[^`]*`|\b(?:GET|POST|PUT|PATCH|DELETE)\s+/[A-Za-z0-9_./{}:-]+)'
    return [regex]::IsMatch($combined, $commandPattern)
}

function Test-RoadmapExecutionContract {
    <#
    .SYNOPSIS
        Return one explainable sufficiency verdict for a roadmap work target.
    .PARAMETER RoadmapContext
        A parsed active-release context or a compatible assessment entry.
    .PARAMETER SelectedTask
        When supplied, the caller is packaging exactly one task rather than an
        entire release. This is an explicit task-size boundary.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$RoadmapContext,
        [Parameter()][string]$MaturityLevel = 'L0-Absent',
        [Parameter()][string]$RepoType = 'other',
        [Parameter()][AllowEmptyString()][string]$SelectedTask = ''
    )

    $goal = [string](_ExecutionContractGetField -InputObject $RoadmapContext -Name 'releaseGoal' -Default `
        (_ExecutionContractGetField -InputObject $RoadmapContext -Name 'goal' -Default ''))
    $pending = @(_ExecutionContractGetField -InputObject $RoadmapContext -Name 'pendingMilestones' -Default @())
    if ($pending.Count -eq 0) {
        $next = _ExecutionContractGetField -InputObject $RoadmapContext -Name 'nextPendingItem' -Default $null
        if ($null -ne $next) {
            $nextText = [string](_ExecutionContractGetField -InputObject $next -Name 'text' -Default $next)
            if (-not [string]::IsNullOrWhiteSpace($nextText)) { $pending = @($nextText) }
        }
    }
    $acceptance = @(_ExecutionContractGetField -InputObject $RoadmapContext -Name 'acceptanceCriteria' -Default @())
    $outOfScope = @(_ExecutionContractGetField -InputObject $RoadmapContext -Name 'outOfScope' -Default @())
    $validation = @(_ExecutionContractGetField -InputObject $RoadmapContext -Name 'validationPlan' -Default @())
    $phase = _ExecutionContractGetField -InputObject $RoadmapContext -Name 'activePhasePlan' -Default $null
    $budget = _ExecutionContractGetField -InputObject $RoadmapContext -Name 'budgetGuardrail' -Default $null

    $goalOk = @(_ExecutionContractMeaningfulStrings -Values @($goal)).Count -gt 0
    $pendingOk = @(_ExecutionContractMeaningfulStrings -Values @($pending)).Count -gt 0
    $boundaryOk = @(_ExecutionContractMeaningfulStrings -Values @($outOfScope)).Count -gt 0
    $scopeOk = $goalOk -and $pendingOk -and $boundaryOk
    $acceptanceOk = @(_ExecutionContractMeaningfulStrings -Values @($acceptance)).Count -gt 0
    $verificationOk = Test-RoadmapRunnableVerification -Text @($validation + $acceptance)

    $maturitySized = $MaturityLevel -in @('L3-Contract-Ready', 'L4-Orchestration-Ready')
    $singleItemSized = -not [string]::IsNullOrWhiteSpace($SelectedTask)
    $phaseScope = [string](_ExecutionContractGetField -InputObject $phase -Name 'scope' -Default '')
    $phaseEstimateRaw = _ExecutionContractGetField -InputObject $phase -Name 'workUnitsEstimated' -Default $null
    $phaseEstimate = 0.0
    $hasPhaseEstimate = ($null -ne $phaseEstimateRaw -and [double]::TryParse([string]$phaseEstimateRaw, [ref]$phaseEstimate) -and $phaseEstimate -gt 0)
    $phaseCapRaw = _ExecutionContractGetField -InputObject $budget -Name 'maxUnitsPerPhase' -Default $null
    $phaseCap = 0.0
    $hasPhaseCap = ($null -ne $phaseCapRaw -and [double]::TryParse([string]$phaseCapRaw, [ref]$phaseCap) -and $phaseCap -gt 0)
    $withinPhaseCap = (-not $hasPhaseCap) -or ($phaseEstimate -le $phaseCap)
    $explicitPhaseSized = (-not [string]::IsNullOrWhiteSpace($phaseScope)) -and $hasPhaseEstimate -and $withinPhaseCap
    $sizingOk = $maturitySized -or $singleItemSized -or $explicitPhaseSized

    $checks = @(
        [pscustomobject]@{
            name = 'scope'; passed = [bool]$scopeOk; code = 'execution-contract-scope-missing'
            explanation = if ($scopeOk) { 'Release goal, pending work, and out-of-scope boundary are present.' } else { 'Add a release goal, pending milestone, and out-of-scope boundary.' }
        }
        [pscustomobject]@{
            name = 'acceptance'; passed = [bool]$acceptanceOk; code = 'execution-contract-acceptance-missing'
            explanation = if ($acceptanceOk) { 'Observable acceptance criteria are present.' } else { 'Add observable acceptance criteria to the active release.' }
        }
        [pscustomobject]@{
            name = 'verification'; passed = [bool]$verificationOk; code = 'execution-contract-verification-missing'
            explanation = if ($verificationOk) { 'A runnable command, script, or API verification is named.' } else { 'Name an exact command, script, or API request in the validation plan.' }
        }
        [pscustomobject]@{
            name = 'sizing'; passed = [bool]$sizingOk; code = 'execution-contract-sizing-missing'
            explanation = if ($maturitySized) {
                "Roadmap maturity $MaturityLevel supplies the default sizing signal for repo type $RepoType."
            } elseif ($singleItemSized) {
                "Dispatch is bounded to one selected task for repo type $RepoType."
            } elseif ($explicitPhaseSized) {
                "Active phase is scoped and estimated at $phaseEstimate work units for repo type $RepoType."
            } else {
                "For repo type $RepoType, add a scoped phase with a positive work-unit estimate within its phase cap, or raise the roadmap to L3."
            }
        }
    )

    $failed = @($checks | Where-Object { -not $_.passed })
    $sufficient = ($failed.Count -eq 0)
    $code = if ($sufficient) { 'execution-contract-sufficient' } else { [string]$failed[0].code }
    $explanation = if ($sufficient) {
        'Execution contract is sufficient for dispatch.'
    } else {
        [string]$failed[0].explanation
    }

    return [pscustomobject]@{
        schemaVersion = '1.0'
        model = 'execution-contract-sufficiency'
        sufficient = [bool]$sufficient
        code = $code
        explanation = $explanation
        maturityLevel = $MaturityLevel
        repoType = $RepoType
        selectedTask = if ([string]::IsNullOrWhiteSpace($SelectedTask)) { $null } else { $SelectedTask }
        checks = @($checks)
    }
}
