<#
.SYNOPSIS
    Budget-ledger configuration and quota-guard helpers for agent dispatch.
.DESCRIPTION
    Reads the host-side budget ledger configuration from `settings.json`,
    summarizes own-ledger work-unit usage from `output/agent-runs/runs/*.json`,
    and evaluates whether a proposed dispatch should proceed, warn, or stop.

    This module deliberately stores and returns raw observations and derived
    counts only. It does not write telemetry; the API host records `quota.*`
    events after acting on the returned evaluation.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function _BudgetField {
    param(
        [object]$Obj,
        [string[]]$Names,
        [object]$Default = $null
    )

    foreach ($name in @($Names)) {
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        if ($null -eq $Obj) { continue }

        if ($Obj -is [System.Collections.IDictionary]) {
            if ($Obj.Contains($name) -and $null -ne $Obj[$name]) {
                return $Obj[$name]
            }
            continue
        }

        if ($null -ne $Obj.PSObject -and ($Obj.PSObject.Properties.Name -contains $name)) {
            $value = $Obj.$name
            if ($null -ne $value) {
                return $value
            }
        }
    }

    return $Default
}

function _BudgetAsDouble {
    param([object]$Value, [object]$Default = $null)

    if ($null -eq $Value) { return $Default }
    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) { return $Default }

    $number = 0.0
    if ([double]::TryParse($text, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$number)) {
        return [double]$number
    }

    return $Default
}

function _BudgetAsBool {
    param([object]$Value, [bool]$Default = $false)

    if ($null -eq $Value) { return $Default }
    if ($Value -is [bool]) { return [bool]$Value }

    $text = ([string]$Value).Trim().ToLowerInvariant()
    switch ($text) {
        'true' { return $true }
        '1' { return $true }
        'yes' { return $true }
        'y' { return $true }
        'false' { return $false }
        '0' { return $false }
        'no' { return $false }
        'n' { return $false }
    }

    return $Default
}

function _BudgetNormalizeProjectMap {
    param(
        [object]$Projects,
        [hashtable]$DefaultProject
    )

    $normalized = @{}
    if ($null -eq $Projects) {
        return $normalized
    }

    $projectNames = @()
    if ($Projects -is [System.Collections.IDictionary]) {
        $projectNames = @($Projects.Keys)
    } elseif ($null -ne $Projects.PSObject) {
        $projectNames = @($Projects.PSObject.Properties.Name)
    }

    foreach ($projectName in @($projectNames)) {
        $projectValue = _BudgetField -Obj $Projects -Names @([string]$projectName) -Default $null
        if ($null -eq $projectValue) { continue }

        $normalized[$projectName.ToLowerInvariant()] = @{
            monthlyBudgetUsd        = _BudgetAsDouble (_BudgetField -Obj $projectValue -Names @('monthlyBudgetUsd', 'monthly_budget_usd') -Default $DefaultProject.monthlyBudgetUsd) $DefaultProject.monthlyBudgetUsd
            monthlyQuotaBudgetUnits = _BudgetAsDouble (_BudgetField -Obj $projectValue -Names @('monthlyQuotaBudgetUnits', 'monthly_quota_budget_units') -Default $DefaultProject.monthlyQuotaBudgetUnits) $DefaultProject.monthlyQuotaBudgetUnits
            priority                = [int](_BudgetField -Obj $projectValue -Names @('priority') -Default $DefaultProject.priority)
        }
    }

    return $normalized
}

function Get-AgentBudgetLedgerConfig {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)][string]$WorkspaceRoot,
        [Parameter()][hashtable]$Settings
    )

    if ($null -eq $Settings) {
        $Settings = @{}
    }

    $rawConfig = _BudgetField -Obj $Settings -Names @('budgetLedger', 'budget_ledger', 'agentBudget', 'agent_budget') -Default @{}
    $period = [string](_BudgetField -Obj $rawConfig -Names @('period') -Default '')
    if ([string]::IsNullOrWhiteSpace($period)) {
        $period = (Get-Date).ToUniversalTime().ToString('yyyy-MM')
    }

    $quotaGuardSection = _BudgetField -Obj $rawConfig -Names @('quotaGuard', 'quota_guard', 'globalQuotaGuard', 'global_quota_guard') -Default @{}
    $creditPolicySection = _BudgetField -Obj $rawConfig -Names @('creditPolicy', 'credit_policy') -Default @{}
    $unitWeightsSection = _BudgetField -Obj $rawConfig -Names @('unitWeights', 'unit_weights') -Default @{}
    $valuationSection = _BudgetField -Obj $rawConfig -Names @('valuation') -Default @{}
    $defaultProjectSection = _BudgetField -Obj $rawConfig -Names @('defaultProject', 'default_project', 'projectDefaults', 'project_defaults') -Default @{}

    $defaultProject = @{
        monthlyBudgetUsd        = _BudgetAsDouble (_BudgetField -Obj $defaultProjectSection -Names @('monthlyBudgetUsd', 'monthly_budget_usd') -Default 6.0) 6.0
        monthlyQuotaBudgetUnits = _BudgetAsDouble (_BudgetField -Obj $defaultProjectSection -Names @('monthlyQuotaBudgetUnits', 'monthly_quota_budget_units') -Default 60.0) 60.0
        priority                = [int](_BudgetField -Obj $defaultProjectSection -Names @('priority') -Default 1)
    }

    return @{
        period = $period
        currency = [string](_BudgetField -Obj $rawConfig -Names @('currency') -Default 'USD')
        subscription = @{
            planName = [string](_BudgetField -Obj (_BudgetField -Obj $rawConfig -Names @('subscription') -Default @{}) -Names @('planName', 'plan_name') -Default '')
            monthlyCostUsd = _BudgetAsDouble (_BudgetField -Obj (_BudgetField -Obj $rawConfig -Names @('subscription') -Default @{}) -Names @('monthlyCostUsd', 'monthly_cost_usd') -Default 20.0) 20.0
        }
        creditPolicy = @{
            allowPaidCredits = _BudgetAsBool (_BudgetField -Obj $creditPolicySection -Names @('allowPaidCredits', 'allow_paid_credits') -Default $false) $false
            requireManualApprovalBeforeCredits = _BudgetAsBool (_BudgetField -Obj $creditPolicySection -Names @('requireManualApprovalBeforeCredits', 'require_manual_approval_before_credits') -Default $true) $true
            stopWorkWhenCreditPromptSeen = _BudgetAsBool (_BudgetField -Obj $creditPolicySection -Names @('stopWorkWhenCreditPromptSeen', 'stop_work_when_credit_prompt_seen') -Default $true) $true
        }
        quotaGuard = @{
            softStopRemainingUnits = _BudgetAsDouble (_BudgetField -Obj $quotaGuardSection -Names @('softStopRemainingUnits', 'soft_stop_remaining_units') -Default 10.0) 10.0
            hardStopRemainingUnits = _BudgetAsDouble (_BudgetField -Obj $quotaGuardSection -Names @('hardStopRemainingUnits', 'hard_stop_remaining_units') -Default 5.0) 5.0
            maxUnitsPerPhase = _BudgetAsDouble (_BudgetField -Obj $quotaGuardSection -Names @('maxUnitsPerPhase', 'max_units_per_phase') -Default 25.0) 25.0
            maxUnitsPerSession = _BudgetAsDouble (_BudgetField -Obj $quotaGuardSection -Names @('maxUnitsPerSession', 'max_units_per_session') -Default 12.0) 12.0
        }
        unitWeights = @{
            planningPrompt = _BudgetAsDouble (_BudgetField -Obj $unitWeightsSection -Names @('planningPrompt', 'planning_prompt') -Default 0.5) 0.5
            implementationPrompt = _BudgetAsDouble (_BudgetField -Obj $unitWeightsSection -Names @('implementationPrompt', 'implementation_prompt') -Default 1.0) 1.0
            agentRun = _BudgetAsDouble (_BudgetField -Obj $unitWeightsSection -Names @('agentRun', 'agent_run') -Default 3.0) 3.0
            failedAgentRetry = _BudgetAsDouble (_BudgetField -Obj $unitWeightsSection -Names @('failedAgentRetry', 'failed_agent_retry') -Default 2.0) 2.0
            roadmapReconciliation = _BudgetAsDouble (_BudgetField -Obj $unitWeightsSection -Names @('roadmapReconciliation', 'roadmap_reconciliation') -Default 1.0) 1.0
            deepResearch = _BudgetAsDouble (_BudgetField -Obj $unitWeightsSection -Names @('deepResearch', 'deep_research') -Default 5.0) 5.0
        }
        valuation = @{
            humanTimeRateUsdPerHour = _BudgetAsDouble (_BudgetField -Obj $valuationSection -Names @('humanTimeRateUsdPerHour', 'human_time_rate_usd_per_hour') -Default 60.0) 60.0
            allocationOption = [string](_BudgetField -Obj $valuationSection -Names @('allocationOption', 'allocation_option') -Default 'B')
        }
        defaultProject = $defaultProject
        projects = _BudgetNormalizeProjectMap -Projects (_BudgetField -Obj $rawConfig -Names @('projects') -Default @{}) -DefaultProject $defaultProject
    }
}

function Get-AgentBudgetProjectConfig {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)][hashtable]$BudgetConfig,
        [Parameter(Mandatory = $true)][string]$RepoName
    )

    $normalizedKey = $RepoName.Trim().ToLowerInvariant()
    if (-not [string]::IsNullOrWhiteSpace($normalizedKey) -and $BudgetConfig.projects.ContainsKey($normalizedKey)) {
        return $BudgetConfig.projects[$normalizedKey]
    }

    return $BudgetConfig.defaultProject
}

function _BudgetUsageUnitsForRun {
    param(
        [object]$RunRecord,
        [double]$DefaultAgentRunUnits
    )

    $metrics = _BudgetField -Obj $RunRecord -Names @('metrics') -Default $null
    $actual = _BudgetAsDouble (_BudgetField -Obj $metrics -Names @('workUnitsActual', 'work_units_actual') -Default $null) $null
    if ($null -ne $actual) {
        return [double]$actual
    }

    $estimated = _BudgetAsDouble (_BudgetField -Obj $metrics -Names @('workUnitsEstimated', 'work_units_estimated') -Default $null) $null
    if ($null -ne $estimated) {
        return [double]$estimated
    }

    return [double]$DefaultAgentRunUnits
}

function _BudgetUsagePeriodForRun {
    param([object]$RunRecord)

    $metrics = _BudgetField -Obj $RunRecord -Names @('metrics') -Default $null
    $timestamp = [string](_BudgetField -Obj $metrics -Names @('dispatchedAt', 'dispatched_at') -Default (_BudgetField -Obj $RunRecord -Names @('createdAt', 'created_at') -Default ''))
    if ([string]::IsNullOrWhiteSpace($timestamp)) {
        return ''
    }

    try {
        return ([datetime]$timestamp).ToUniversalTime().ToString('yyyy-MM')
    } catch {
        return ''
    }
}

function Get-AgentBudgetUsageSnapshot {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)][string]$WorkspaceRoot,
        [Parameter(Mandatory = $true)][hashtable]$BudgetConfig
    )

    $runsDir = Join-Path $WorkspaceRoot 'output\agent-runs\runs'
    $defaultAgentRunUnits = [double]$BudgetConfig.unitWeights.agentRun
    $byRepo = @{}
    $totalUnitsConsumed = 0.0
    $creditPromptRepos = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $creditPromptRunIds = [System.Collections.Generic.List[string]]::new()

    if (Test-Path -LiteralPath $runsDir -PathType Container) {
        $runFiles = @(Get-ChildItem -LiteralPath $runsDir -Filter '*.json' -File -ErrorAction SilentlyContinue)
        foreach ($runFile in @($runFiles)) {
            $run = $null
            try {
                $run = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $runFile.FullName -Raw -Encoding UTF8)
            } catch {
                continue
            }

            if ((_BudgetUsagePeriodForRun -RunRecord $run) -ne $BudgetConfig.period) {
                continue
            }

            $repoName = [string](_BudgetField -Obj $run -Names @('repoName', 'repo_name') -Default '')
            if ([string]::IsNullOrWhiteSpace($repoName)) {
                continue
            }

            $unitsConsumed = _BudgetUsageUnitsForRun -RunRecord $run -DefaultAgentRunUnits $defaultAgentRunUnits
            if (-not $byRepo.ContainsKey($repoName.ToLowerInvariant())) {
                $byRepo[$repoName.ToLowerInvariant()] = @{
                    repoName = $repoName
                    unitsConsumed = 0.0
                }
            }
            $byRepo[$repoName.ToLowerInvariant()].unitsConsumed += [double]$unitsConsumed
            $totalUnitsConsumed += [double]$unitsConsumed

            $metrics = _BudgetField -Obj $run -Names @('metrics') -Default $null
            if (_BudgetAsBool (_BudgetField -Obj $metrics -Names @('creditPromptSeen', 'credit_prompt_seen') -Default $false) $false) {
                $null = $creditPromptRepos.Add($repoName)
                $creditPromptRunIds.Add([string](_BudgetField -Obj $run -Names @('runId', 'run_id') -Default '')) | Out-Null
            }
        }
    }

    return @{
        period = $BudgetConfig.period
        byRepo = $byRepo
        totalUnitsConsumed = [math]::Round([double]$totalUnitsConsumed, 3)
        creditPromptSeen = ($creditPromptRepos.Count -gt 0)
        creditPromptRepos = @($creditPromptRepos | Sort-Object)
        creditPromptRunIds = @($creditPromptRunIds | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)
    }
}

function Test-AgentDispatchQuota {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)][string]$WorkspaceRoot,
        [Parameter(Mandatory = $true)][string]$RepoName,
        [Parameter(Mandatory = $true)][double]$EstimatedWorkUnits,
        [Parameter(Mandatory = $true)][hashtable]$BudgetConfig,
        [Parameter()][string]$PlannedReleaseName = '',
        [Parameter()][string]$PlannedPhaseName = ''
    )

    $projectConfig = Get-AgentBudgetProjectConfig -BudgetConfig $BudgetConfig -RepoName $RepoName
    $usageSnapshot = Get-AgentBudgetUsageSnapshot -WorkspaceRoot $WorkspaceRoot -BudgetConfig $BudgetConfig
    $repoUsageKey = $RepoName.Trim().ToLowerInvariant()
    $unitsConsumed = if ($usageSnapshot.byRepo.ContainsKey($repoUsageKey)) {
        [double]$usageSnapshot.byRepo[$repoUsageKey].unitsConsumed
    } else {
        0.0
    }

    $projectBudgetUnits = [double]$projectConfig.monthlyQuotaBudgetUnits
    $remainingBefore = $projectBudgetUnits - $unitsConsumed
    $remainingAfter = $remainingBefore - $EstimatedWorkUnits
    $softStop = [double]$BudgetConfig.quotaGuard.softStopRemainingUnits
    $hardStop = [double]$BudgetConfig.quotaGuard.hardStopRemainingUnits
    $maxUnitsPerPhase = [double]$BudgetConfig.quotaGuard.maxUnitsPerPhase
    $maxUnitsPerSession = [double]$BudgetConfig.quotaGuard.maxUnitsPerSession
    $warnings = [System.Collections.Generic.List[string]]::new()
    $blockedCode = ''
    $blockedMessage = ''

    if ($BudgetConfig.creditPolicy.stopWorkWhenCreditPromptSeen -and $usageSnapshot.creditPromptSeen) {
        $blockedCode = 'credit-prompt-seen'
        $blockedMessage = 'Dispatch stopped because a prior run in the current budget period recorded a credit-prompt warning. Clear or approve credits before starting more agent work.'
    } elseif ($EstimatedWorkUnits -gt $maxUnitsPerSession) {
        $blockedCode = 'session-cap-exceeded'
        $blockedMessage = ("Dispatch stopped: estimated session work ({0} units) exceeds the configured per-session cap ({1}). Split the work before dispatch." -f $EstimatedWorkUnits, $maxUnitsPerSession)
    } elseif ($EstimatedWorkUnits -gt $maxUnitsPerPhase) {
        $blockedCode = 'phase-cap-exceeded'
        $blockedMessage = ("Dispatch stopped: estimated work ({0} units) exceeds the configured per-phase cap ({1}). Split the roadmap phase before dispatch." -f $EstimatedWorkUnits, $maxUnitsPerPhase)
    } elseif ($EstimatedWorkUnits -gt $projectBudgetUnits) {
        $blockedCode = 'project-budget-exceeded'
        $blockedMessage = ("Dispatch stopped: estimated work ({0} units) is larger than the repo's monthly quota budget ({1})." -f $EstimatedWorkUnits, $projectBudgetUnits)
    } elseif ($remainingBefore -le $hardStop) {
        $blockedCode = 'hard-stop-reached'
        $blockedMessage = ("Dispatch stopped: repo '{0}' has only {1} work units remaining in period {2}, which is at or below the hard-stop threshold ({3})." -f $RepoName, [math]::Round($remainingBefore, 3), $BudgetConfig.period, $hardStop)
    } elseif ($remainingAfter -lt 0) {
        $blockedCode = 'monthly-budget-exhausted'
        $blockedMessage = ("Dispatch stopped: repo '{0}' would exceed its monthly quota budget by {1} work units (remaining before dispatch: {2})." -f $RepoName, [math]::Round([math]::Abs($remainingAfter), 3), [math]::Round($remainingBefore, 3))
    } elseif ($remainingAfter -le $hardStop) {
        $blockedCode = 'hard-stop-after-dispatch'
        $blockedMessage = ("Dispatch stopped: repo '{0}' would fall to {1} remaining work units after this dispatch, below the hard-stop threshold ({2})." -f $RepoName, [math]::Round($remainingAfter, 3), $hardStop)
    } elseif ($remainingAfter -le $softStop) {
        $warnings.Add(("Repo '{0}' would have only {1} work units remaining after this dispatch, at or below the soft-stop threshold ({2})." -f $RepoName, [math]::Round($remainingAfter, 3), $softStop)) | Out-Null
    }

    if (-not [string]::IsNullOrWhiteSpace($PlannedPhaseName) -and $EstimatedWorkUnits -gt 0 -and $EstimatedWorkUnits -lt 1) {
        $warnings.Add(("Planned phase '{0}' estimates less than one work unit. Check the roadmap annotation for underestimation." -f $PlannedPhaseName)) | Out-Null
    }

    return @{
        allowed = [string]::IsNullOrWhiteSpace($blockedCode)
        blockedCode = if ([string]::IsNullOrWhiteSpace($blockedCode)) { $null } else { $blockedCode }
        message = if (-not [string]::IsNullOrWhiteSpace($blockedMessage)) { $blockedMessage } elseif ($warnings.Count -gt 0) { $warnings[0] } else { '' }
        warnings = @($warnings)
        period = $BudgetConfig.period
        plannedReleaseName = if ([string]::IsNullOrWhiteSpace($PlannedReleaseName)) { $null } else { $PlannedReleaseName }
        plannedPhaseName = if ([string]::IsNullOrWhiteSpace($PlannedPhaseName)) { $null } else { $PlannedPhaseName }
        estimatedWorkUnits = [double]$EstimatedWorkUnits
        project = @{
            monthlyBudgetUsd = [double]$projectConfig.monthlyBudgetUsd
            monthlyQuotaBudgetUnits = [double]$projectBudgetUnits
            priority = [int]$projectConfig.priority
        }
        usage = @{
            unitsConsumed = [math]::Round([double]$unitsConsumed, 3)
            remainingBefore = [math]::Round([double]$remainingBefore, 3)
            remainingAfter = [math]::Round([double]$remainingAfter, 3)
            totalUnitsConsumed = [double]$usageSnapshot.totalUnitsConsumed
            creditPromptSeen = [bool]$usageSnapshot.creditPromptSeen
            creditPromptRepos = @($usageSnapshot.creditPromptRepos)
            creditPromptRunIds = @($usageSnapshot.creditPromptRunIds)
        }
    }
}
