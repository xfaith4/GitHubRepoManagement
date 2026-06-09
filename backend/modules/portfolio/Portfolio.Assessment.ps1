<#
.SYNOPSIS
    Portfolio assessment — combines git, doc audit, roadmap state, roadmap maturity,
    structure audit, and execution state into one operator-facing record per repo.

.DESCRIPTION
    Release 1.7.5 — Portfolio Mission Alignment.

    This module exposes:

      Get-RepoStructureStandards
        Loads backend/config/repo-structure-standards.json.

      Invoke-RepoStructureAudit -RepoPath -Standards
        Runs a fast structural check against a single repo (Test-Path only,
        no subprocesses) and returns missing-element findings.

      Invoke-PortfolioAssessment -LocalRepos -RoadmapEntries -DocAuditEntries
                                 -RoadmapAuditEntries -ExecutionEntries
                                 -GitHubRepos -StructureStandards -ValueScoringConfig
        Produces a normalized assessment record per repo combining every input
        signal, plus a single lifecycleState per repo and a portfolio-level
        summary.

    The lifecycle state precedence is deterministic — see _ResolveLifecycleState.

.NOTES
    Dot-source from Start-RepoManagementApiHost.ps1.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Standards loader
# ---------------------------------------------------------------------------

function Get-RepoStructureStandards {
    [CmdletBinding()]
    param([string]$StandardsPath = '')

    if ([string]::IsNullOrWhiteSpace($StandardsPath) -or -not (Test-Path -LiteralPath $StandardsPath)) {
        return $null
    }
    try {
        $raw = Get-Content -LiteralPath $StandardsPath -Raw -Encoding UTF8 -ErrorAction Stop
        return ConvertFrom-Json -InputObject $raw
    } catch {
        return $null
    }
}

# ---------------------------------------------------------------------------
# Internal: detect repo type from on-disk manifests (mirrors Roadmap.Evaluator
# detection but kept local so this module has no roadmap-evaluator dependency).
# ---------------------------------------------------------------------------

function _DetectRepoTypeForStructure {
    param([string]$LocalPath)
    if ([string]::IsNullOrWhiteSpace($LocalPath) -or -not (Test-Path -LiteralPath $LocalPath -ErrorAction SilentlyContinue)) { return 'other' }

    if (Test-Path -LiteralPath (Join-Path $LocalPath 'package.json') -PathType Leaf) { return 'node' }
    if (Test-Path -LiteralPath (Join-Path $LocalPath 'go.mod')       -PathType Leaf) { return 'go' }
    if (Test-Path -LiteralPath (Join-Path $LocalPath 'Cargo.toml')   -PathType Leaf) { return 'rust' }
    if (Test-Path -LiteralPath (Join-Path $LocalPath 'pyproject.toml') -PathType Leaf) { return 'python' }
    if (Test-Path -LiteralPath (Join-Path $LocalPath 'setup.py')       -PathType Leaf) { return 'python' }
    if (Test-Path -LiteralPath (Join-Path $LocalPath 'requirements.txt') -PathType Leaf) { return 'python' }

    if (@(Get-ChildItem -LiteralPath $LocalPath -Filter '*.csproj' -Recurse -Depth 2 -File -ErrorAction SilentlyContinue).Count -gt 0) { return 'dotnet' }
    if (@(Get-ChildItem -LiteralPath $LocalPath -Filter '*.sln'    -Recurse -Depth 2 -File -ErrorAction SilentlyContinue).Count -gt 0) { return 'dotnet' }
    if (@(Get-ChildItem -LiteralPath $LocalPath -Filter '*.fsproj' -Recurse -Depth 2 -File -ErrorAction SilentlyContinue).Count -gt 0) { return 'dotnet' }

    if (@(Get-ChildItem -LiteralPath $LocalPath -Filter '*.psd1' -Recurse -Depth 2 -File -ErrorAction SilentlyContinue).Count -gt 0) { return 'powershell' }
    if (@(Get-ChildItem -LiteralPath $LocalPath -Filter '*.psm1' -Recurse -Depth 2 -File -ErrorAction SilentlyContinue).Count -gt 0) { return 'powershell' }
    if (@(Get-ChildItem -LiteralPath $LocalPath -Filter '*.ps1'  -Recurse -Depth 2 -File -ErrorAction SilentlyContinue).Count -gt 0) { return 'powershell' }

    return 'other'
}

function _HasTestSignal {
    # NOTE: patterns are hard-coded by repo type below. The JSON config exposes
    # repoTypes.<type>.testSignalGlobs as a forward-compatibility hook; it is
    # not consumed yet. A future enhancement can switch to data-driven globs
    # without changing this function's contract.
    param([string]$LocalPath, [string]$RepoType, [object]$Standards)

    if ([string]::IsNullOrWhiteSpace($LocalPath) -or -not (Test-Path -LiteralPath $LocalPath -ErrorAction SilentlyContinue)) { return $false }

    foreach ($d in @('test', 'tests', '__tests__', 'spec', 'specs')) {
        if (Test-Path -LiteralPath (Join-Path $LocalPath $d) -PathType Container) { return $true }
    }
    switch ($RepoType) {
        'node'       { return @(Get-ChildItem -LiteralPath $LocalPath -Filter '*.test.*'   -Recurse -Depth 4 -File -ErrorAction SilentlyContinue).Count -gt 0 }
        'dotnet'     { return @(Get-ChildItem -LiteralPath $LocalPath -Filter '*Tests*'    -Recurse -Depth 3 -File -ErrorAction SilentlyContinue).Count -gt 0 }
        'python'     { return @(Get-ChildItem -LiteralPath $LocalPath -Filter 'test_*.py'  -Recurse -Depth 4 -File -ErrorAction SilentlyContinue).Count -gt 0 }
        'powershell' { return @(Get-ChildItem -LiteralPath $LocalPath -Filter '*.Tests.ps1' -Recurse -Depth 4 -File -ErrorAction SilentlyContinue).Count -gt 0 }
        'go'         { return @(Get-ChildItem -LiteralPath $LocalPath -Filter '*_test.go'   -Recurse -Depth 4 -File -ErrorAction SilentlyContinue).Count -gt 0 }
        'rust'       { return Test-Path -LiteralPath (Join-Path $LocalPath 'tests') -PathType Container }
    }
    return $false
}

function _TestPathAny {
    param([string]$Base, [string[]]$Names)
    foreach ($n in @($Names)) {
        if ([string]::IsNullOrWhiteSpace($n)) { continue }
        if (Test-Path -LiteralPath (Join-Path $Base $n)) { return $true }
    }
    return $false
}

# ---------------------------------------------------------------------------
# Per-repo structure audit (Test-Path only — fast and side-effect free)
# ---------------------------------------------------------------------------

function Invoke-RepoStructureAudit {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RepoPath,
        [Parameter()][object]$Standards
    )

    $findings = [System.Collections.Generic.List[object]]::new()
    $repoType = _DetectRepoTypeForStructure -LocalPath $RepoPath

    # NOTE: parens around `-contains` are required — `-not` binds tighter than
    # `-contains`, so without them this guard becomes `(-not <array>) -contains 'common'`
    # which is always false and silently lets a malformed Standards object through.
    if ($null -eq $Standards -or -not ($Standards.PSObject.Properties.Name -contains 'common')) {
        return [pscustomobject]@{
            repoType   = $repoType
            findings   = @()
            missingCount = 0
            criticalMissingCount = 0
            warningMissingCount  = 0
            hasTestSignal = $false
            hasCiSignal   = $false
        }
    }

    $common = $Standards.common

    foreach ($spec in @($common.requiredRootFiles)) {
        if ($null -eq $spec) { continue }
        $names = @([string]$spec.name)
        if ($spec.PSObject.Properties.Name -contains 'altNames' -and $spec.altNames) {
            $names += @($spec.altNames | ForEach-Object { [string]$_ })
        }
        if (-not (_TestPathAny -Base $RepoPath -Names $names)) {
            $findings.Add([pscustomobject]@{
                kind              = 'missing-root-file'
                target            = [string]$spec.name
                category          = [string]$spec.category
                severity          = [string]$spec.severity
                recommendedAction = [string]$spec.recommendedAction
            })
        }
    }

    foreach ($spec in @($common.requiredRootFolders)) {
        if ($null -eq $spec) { continue }
        $names = @([string]$spec.name)
        if ($spec.PSObject.Properties.Name -contains 'altNames' -and $spec.altNames) {
            $names += @($spec.altNames | ForEach-Object { [string]$_ })
        }
        $found = $false
        foreach ($n in $names) {
            if ([string]::IsNullOrWhiteSpace($n)) { continue }
            if (Test-Path -LiteralPath (Join-Path $RepoPath $n) -PathType Container) { $found = $true; break }
        }
        if (-not $found) {
            $findings.Add([pscustomobject]@{
                kind              = 'missing-root-folder'
                target            = [string]$spec.name
                category          = [string]$spec.category
                severity          = [string]$spec.severity
                recommendedAction = [string]$spec.recommendedAction
            })
        }
    }

    $hasCiSignal = $false
    foreach ($spec in @($common.ciSignals)) {
        if ($null -eq $spec) { continue }
        $p = Join-Path $RepoPath ([string]$spec.path)
        $present = $false
        if (Test-Path -LiteralPath $p -PathType Container) {
            $present = @(Get-ChildItem -LiteralPath $p -File -ErrorAction SilentlyContinue).Count -gt 0
        } elseif (Test-Path -LiteralPath $p -PathType Leaf) {
            $present = $true
        }
        if ($present) {
            $hasCiSignal = $true
        } else {
            $findings.Add([pscustomobject]@{
                kind              = 'missing-ci-signal'
                target            = [string]$spec.path
                category          = [string]$spec.category
                severity          = [string]$spec.severity
                recommendedAction = [string]$spec.recommendedAction
            })
        }
    }

    $hasTestSignal = _HasTestSignal -LocalPath $RepoPath -RepoType $repoType -Standards $Standards
    if (-not $hasTestSignal -and $null -ne $common.testSignals) {
        $findings.Add([pscustomobject]@{
            kind              = 'missing-test-signal'
            target            = 'tests'
            category          = [string]$common.testSignals.category
            severity          = [string]$common.testSignals.severity
            recommendedAction = [string]$common.testSignals.recommendedAction
        })
    }

    $criticalMissing = @($findings | Where-Object { [string]$_.severity -eq 'critical' }).Count
    $warningMissing  = @($findings | Where-Object { [string]$_.severity -eq 'warning'  }).Count

    return [pscustomobject]@{
        repoType             = $repoType
        findings             = @($findings)
        missingCount         = @($findings).Count
        criticalMissingCount = $criticalMissing
        warningMissingCount  = $warningMissing
        hasTestSignal        = [bool]$hasTestSignal
        hasCiSignal          = [bool]$hasCiSignal
    }
}

# ---------------------------------------------------------------------------
# Lifecycle state resolution — single source of truth
# ---------------------------------------------------------------------------
#
# Precedence (first match wins):
#   archived            isArchived flag set
#   parse-error         roadmap state == parse-error
#   running             execution state == running
#   needs-readme        README missing (any structure finding kind=missing-root-file target=README.md)
#   needs-roadmap       no roadmap on disk
#   needs-roadmap-repair  roadmap maturity below L3
#   needs-structure     critical/warning structure findings remain (other than README which was caught above)
#   ready-for-work      dispatch readiness == ready  AND maturity >= L3  AND has pending items
#   completed           roadmap state == complete
#   monitored           none of the above (clean, stable, no pending work)
#   discovered          fallback when signals were missing
#
# `recommendedAction` is a short operator-facing next-step phrase.
#
# `blockingReasons` is a list of human-readable strings explaining why the repo
# is in this state (or why it's not yet ready) — used by the report and panel
# to make every state self-explanatory.
# ---------------------------------------------------------------------------

function _ResolveLifecycleState {
    param(
        [bool]$IsArchived,
        [string]$RoadmapState,
        [string]$DispatchReadiness,
        [string]$MaturityLevel,
        [string]$ExecutionState,
        [bool]$HasReadme,
        [bool]$HasRoadmap,
        [int]$PendingItemCount,
        [object[]]$StructureFindings = @()
    )

    $blocking = [System.Collections.Generic.List[string]]::new()
    $state = ''
    $action = ''

    $safeFindings = @()
    if ($null -ne $StructureFindings) {
        $safeFindings = @($StructureFindings | Where-Object { $null -ne $_ })
    }
    $criticalStruct = @($safeFindings | Where-Object {
        $sev = if ($_.PSObject.Properties.Name -contains 'severity') { [string]$_.severity } else { '' }
        $tgt = if ($_.PSObject.Properties.Name -contains 'target')   { [string]$_.target }   else { '' }
        $sev -eq 'critical' -and $tgt -ne 'README.md'
    })
    $warningStruct  = @($safeFindings | Where-Object {
        $sev = if ($_.PSObject.Properties.Name -contains 'severity') { [string]$_.severity } else { '' }
        $tgt = if ($_.PSObject.Properties.Name -contains 'target')   { [string]$_.target }   else { '' }
        $sev -eq 'warning' -and $tgt -ne 'README.md'
    })

    $maturityIsAtLeastL3 = $MaturityLevel -in @('L3-Contract-Ready', 'L4-Orchestration-Ready')

    if ($IsArchived) {
        $state = 'archived'
        $action = 'No action — repo is archived. Restore via settings if work resumes.'
        $blocking.Add('Repository is marked archived.') | Out-Null
        return @{ state = $state; recommendedAction = $action; blockingReasons = @($blocking) }
    }
    if ($RoadmapState -eq 'parse-error') {
        $state = 'parse-error'
        $action = 'Open the roadmap and fix the parse error before this repo can be assessed.'
        $blocking.Add('Roadmap could not be parsed.') | Out-Null
        return @{ state = $state; recommendedAction = $action; blockingReasons = @($blocking) }
    }
    if ($ExecutionState -eq 'running') {
        $state = 'running'
        $action = 'Wait for the active Copilot task to complete.'
        $blocking.Add('A Copilot task is already in flight.') | Out-Null
        return @{ state = $state; recommendedAction = $action; blockingReasons = @($blocking) }
    }
    if (-not $HasReadme) {
        $state = 'needs-readme'
        $action = "Generate a README first — use the Work Queue 'Generate README' action."
        $blocking.Add('README.md is missing.') | Out-Null
        return @{ state = $state; recommendedAction = $action; blockingReasons = @($blocking) }
    }
    if (-not $HasRoadmap) {
        $state = 'needs-roadmap'
        $action = 'Run repo evaluation to draft a roadmap from the current code and docs.'
        $blocking.Add('No ROADMAP.md found.') | Out-Null
        return @{ state = $state; recommendedAction = $action; blockingReasons = @($blocking) }
    }
    if (-not $maturityIsAtLeastL3 -and $RoadmapState -ne 'complete') {
        $state = 'needs-roadmap-repair'
        $action = "Open the Roadmap Repair preview — current maturity $MaturityLevel is below L3."
        $blocking.Add("Roadmap maturity is $MaturityLevel; L3-Contract-Ready or higher required for dispatch.") | Out-Null
        return @{ state = $state; recommendedAction = $action; blockingReasons = @($blocking) }
    }
    if ($criticalStruct.Count -gt 0 -or $warningStruct.Count -gt 0) {
        $state = 'needs-structure'
        $missing = @($criticalStruct + $warningStruct | ForEach-Object { [string]$_.target })
        $action = ('Add missing structural elements: {0}.' -f ($missing -join ', '))
        foreach ($f in $criticalStruct + $warningStruct) {
            $blocking.Add(("Missing {0} ({1})" -f $f.target, $f.severity)) | Out-Null
        }
        return @{ state = $state; recommendedAction = $action; blockingReasons = @($blocking) }
    }
    if ($DispatchReadiness -in @('needs-doc-standardization','blocked') -and $PendingItemCount -gt 0) {
        $state = 'needs-structure'
        $action = 'Resolve outstanding documentation findings before dispatching.'
        $blocking.Add(("Dispatch readiness is '{0}'." -f $DispatchReadiness)) | Out-Null
        return @{ state = $state; recommendedAction = $action; blockingReasons = @($blocking) }
    }
    if ($maturityIsAtLeastL3 -and $PendingItemCount -gt 0) {
        # Roadmap audit + pending items are authoritative for dispatchability.
        # dispatchReadiness from doc-audit is treated as a softer signal: if it
        # disagrees here it usually means the doc-audit cache is stale relative
        # to the roadmap audit, not that the repo is actually un-dispatchable.
        $state = 'ready-for-work'
        $action = 'Dispatch the next pending roadmap item to Copilot.'
        return @{ state = $state; recommendedAction = $action; blockingReasons = @() }
    }
    if ($RoadmapState -eq 'complete') {
        $state = 'completed'
        $action = 'No pending work — consider drafting a follow-up release or marking monitored.'
        return @{ state = $state; recommendedAction = $action; blockingReasons = @() }
    }
    if ($PendingItemCount -eq 0) {
        $state = 'monitored'
        $action = 'No pending work and no blockers — keep monitored.'
        return @{ state = $state; recommendedAction = $action; blockingReasons = @() }
    }

    # Fallback: signals were inconsistent or partial.
    return @{
        state             = 'discovered'
        recommendedAction = 'Re-run a portfolio scan to refresh roadmap, docs-audit, and maturity signals.'
        blockingReasons   = @('Assessment signals are incomplete; rescan recommended.')
    }
}

# ---------------------------------------------------------------------------
# Lookup helpers
# ---------------------------------------------------------------------------

function _NormalizeKey { param([string]$Value) return ([string]$Value).ToLowerInvariant() }

function _IndexByRepoName {
    param([object[]]$Items, [string]$NameField = 'repoName')
    $map = @{}
    foreach ($it in @($Items)) {
        if ($null -eq $it) { continue }
        $name = ''
        if ($it -is [System.Collections.IDictionary]) {
            if ($it.Contains($NameField)) { $name = [string]$it[$NameField] }
        } elseif ($it.PSObject.Properties.Name -contains $NameField) {
            $name = [string]$it.$NameField
        }
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        $map[(_NormalizeKey $name)] = $it
    }
    return $map
}

function _GetField {
    param([object]$Obj, [string]$Name, [object]$Default = $null)
    if ($null -eq $Obj) { return $Default }
    if ($Obj -is [System.Collections.IDictionary]) {
        if ($Obj.Contains($Name)) { return $Obj[$Name] }
        return $Default
    }
    if ($Obj.PSObject.Properties.Name -contains $Name) { return $Obj.$Name }
    return $Default
}

function _GetPendingRoadmapItems {
    param([object]$RoadmapEntry, [object]$MaturityEntry)

    $source = if ($null -ne $MaturityEntry) { $MaturityEntry } else { $RoadmapEntry }
    $items = [System.Collections.Generic.List[object]]::new()
    $nextPending = _GetField -Obj $source -Name 'nextPendingItem' -Default (_GetField -Obj $RoadmapEntry -Name 'nextPendingItem' -Default $null)
    $nextText = if ($null -ne $nextPending) { [string](_GetField -Obj $nextPending -Name 'text' -Default '') } else { '' }
    $nextTags = if ($null -ne $nextPending) { @(_GetField -Obj $nextPending -Name 'tags' -Default @() | ForEach-Object { [string]$_ }) } else { @() }

    foreach ($sec in @(_GetField -Obj $source -Name 'sections' -Default @())) {
        if ($null -eq $sec) { continue }
        $sectionName = [string](_GetField -Obj $sec -Name 'name' -Default '')
        foreach ($pending in @(_GetField -Obj $sec -Name 'pendingItems' -Default @())) {
            $text = [string]$pending
            if ([string]::IsNullOrWhiteSpace($text)) { continue }
            $tags = if (-not [string]::IsNullOrWhiteSpace($nextText) -and $text -eq $nextText) { $nextTags } else { @() }
            $items.Add([pscustomobject]@{
                text    = $text
                section = $sectionName
                tags    = @($tags)
            }) | Out-Null
        }
    }

    if ($items.Count -eq 0 -and -not [string]::IsNullOrWhiteSpace($nextText)) {
        $items.Add([pscustomobject]@{
            text    = $nextText
            section = [string](_GetField -Obj $nextPending -Name 'section' -Default '')
            tags    = @($nextTags)
        }) | Out-Null
    }

    return $items.ToArray()
}

function _ScorePendingRoadmapItems {
    param(
        [object[]]$PendingItems = @(),
        [object]$RepoContext,
        [object]$ValueScoringConfig
    )

    if (@($PendingItems).Count -eq 0) { return @() }
    if (Get-Command -Name Invoke-PortfolioValueScores -ErrorAction SilentlyContinue) {
        return @(Invoke-PortfolioValueScores -PendingItems $PendingItems -RepoContext $RepoContext -ScoringConfig $ValueScoringConfig)
    }

    $fallback = [System.Collections.Generic.List[object]]::new()
    $i = 0
    foreach ($item in @($PendingItems)) {
        $fallback.Add([pscustomobject]@{
            text           = [string](_GetField -Obj $item -Name 'text' -Default '')
            section        = [string](_GetField -Obj $item -Name 'section' -Default '')
            tags           = @(_GetField -Obj $item -Name 'tags' -Default @() | ForEach-Object { [string]$_ })
            roadmapOrder   = $i + 1
            valueScore     = 0
            valueTier      = 'unscored'
            valueRationale = @('value scorer module was not loaded')
            scoringSignals = [pscustomobject]@{}
        }) | Out-Null
        $i++
    }
    return $fallback.ToArray()
}

function _SelectTopValueItem {
    param([object[]]$ScoredItems = @())

    $validItems = [System.Collections.Generic.List[object]]::new()
    foreach ($scored in @($ScoredItems)) {
        if ($null -eq $scored) { continue }
        if ($scored -is [System.Array]) {
            foreach ($nested in @($scored)) {
                if ($null -ne $nested) { $validItems.Add($nested) | Out-Null }
            }
            continue
        }
        $validItems.Add($scored) | Out-Null
    }

    if ($validItems.Count -eq 0) { return $null }
    $selected = @($validItems.ToArray() | Sort-Object `
        @{ Expression = { [int](_GetField -Obj $_ -Name 'valueScore' -Default 0) }; Descending = $true },
        @{ Expression = { [int](_GetField -Obj $_ -Name 'roadmapOrder' -Default 999999) }; Ascending = $true } |
        Select-Object -First 1)
    if ($selected.Count -eq 0) { return $null }
    return $selected[0]
}

# ---------------------------------------------------------------------------
# Main orchestrator
# ---------------------------------------------------------------------------

function Invoke-PortfolioAssessment {
    [CmdletBinding()]
    param(
        [Parameter()][AllowEmptyCollection()][object[]]$LocalRepos = @(),
        [Parameter()][AllowEmptyCollection()][object[]]$RoadmapEntries      = @(),
        [Parameter()][AllowEmptyCollection()][object[]]$DocAuditEntries     = @(),
        [Parameter()][AllowEmptyCollection()][object[]]$RoadmapAuditEntries = @(),
        [Parameter()][AllowEmptyCollection()][object[]]$ExecutionEntries    = @(),
        [Parameter()][AllowEmptyCollection()][object[]]$GitHubRepos         = @(),
        [Parameter()][object]$StructureStandards,
        [Parameter()][object]$ValueScoringConfig
    )

    $roadmapMap     = _IndexByRepoName -Items $RoadmapEntries     -NameField 'repoName'
    $docAuditMap    = _IndexByRepoName -Items $DocAuditEntries    -NameField 'repoName'
    $maturityMap    = _IndexByRepoName -Items $RoadmapAuditEntries -NameField 'repoName'
    $executionMap   = _IndexByRepoName -Items $ExecutionEntries   -NameField 'repoName'
    $githubMap      = _IndexByRepoName -Items $GitHubRepos        -NameField 'name'

    $assessments = [System.Collections.Generic.List[object]]::new()
    $seenLocalKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($repo in @($LocalRepos)) {
        if ($null -eq $repo) { continue }
        $repoName = [string](_GetField -Obj $repo -Name 'name' -Default '')
        if ([string]::IsNullOrWhiteSpace($repoName)) { continue }
        $key = _NormalizeKey $repoName
        if (-not $seenLocalKeys.Add($key)) { continue }

        $localPath  = [string](_GetField -Obj $repo -Name 'localPath' -Default '')
        $isArchived = [bool](_GetField -Obj $repo -Name 'isArchived' -Default $false)
        $htmlUrl    = [string](_GetField -Obj $repo -Name 'htmlUrl' -Default '')
        $branch     = [string](_GetField -Obj $repo -Name 'branch' -Default '')
        $gitStatus  = [string](_GetField -Obj $repo -Name 'status' -Default 'unknown')

        # Roadmap state
        $roadmapEntry = if ($roadmapMap.ContainsKey($key)) { $roadmapMap[$key] } else { $null }
        $roadmapPath  = [string](_GetField -Obj $roadmapEntry -Name 'roadmapPath' -Default '')
        $roadmapState = [string](_GetField -Obj $roadmapEntry -Name 'roadmapState' -Default 'missing')
        $hasRoadmap   = -not [string]::IsNullOrWhiteSpace($roadmapPath) -and (Test-Path -LiteralPath $roadmapPath -ErrorAction SilentlyContinue)
        $pendingCount = [int](_GetField -Obj $roadmapEntry -Name 'pendingCount' -Default 0)
        $nextItemRaw  = _GetField -Obj $roadmapEntry -Name 'nextPendingItem' -Default $null
        $nextItemText = if ($null -ne $nextItemRaw) { [string](_GetField -Obj $nextItemRaw -Name 'text' -Default '') } else { '' }

        # Doc audit
        $docEntry = if ($docAuditMap.ContainsKey($key)) { $docAuditMap[$key] } else { $null }
        $dispatchReadiness = [string](_GetField -Obj $docEntry -Name 'dispatchReadiness' -Default 'missing-roadmap')
        $docFindings = @()
        $rawDocFindings = _GetField -Obj $docEntry -Name 'docFindings' -Default @()
        if ($null -ne $rawDocFindings) { $docFindings = @($rawDocFindings | Where-Object { $null -ne $_ }) }
        $hasReadme = $true
        if ($null -ne $docEntry) {
            $missingReadme = @($docFindings | Where-Object {
                ([string](_GetField -Obj $_ -Name 'file' -Default '')) -eq 'README.md' -and
                ([string](_GetField -Obj $_ -Name 'message' -Default '')) -match 'missing'
            })
            $hasReadme = $missingReadme.Count -eq 0
        } elseif (-not [string]::IsNullOrWhiteSpace($localPath)) {
            $hasReadme = Test-Path -LiteralPath (Join-Path $localPath 'README.md') -PathType Leaf
        }

        # Roadmap maturity
        $maturityEntry = if ($maturityMap.ContainsKey($key)) { $maturityMap[$key] } else { $null }
        $maturityLevel = [string](_GetField -Obj $maturityEntry -Name 'maturityLevel' -Default 'L0-Absent')
        $maturityScore = [int](_GetField -Obj $maturityEntry -Name 'maturityScore' -Default 0)

        # Execution
        $execEntry = if ($executionMap.ContainsKey($key)) { $executionMap[$key] } else { $null }
        $execState = [string](_GetField -Obj $execEntry -Name 'executionState' -Default 'idle')

        # Structure audit
        $structAudit = $null
        if (-not [string]::IsNullOrWhiteSpace($localPath) -and (Test-Path -LiteralPath $localPath -ErrorAction SilentlyContinue)) {
            $structAudit = Invoke-RepoStructureAudit -RepoPath $localPath -Standards $StructureStandards
        }
        $structFindings = if ($null -ne $structAudit) { @($structAudit.findings) } else { @() }
        $repoType = if ($null -ne $structAudit) { [string]$structAudit.repoType } else { 'other' }

        $githubRepo = if ($githubMap.ContainsKey($key)) { $githubMap[$key] } else { $null }

        # Source coverage
        $sourceCoverage = if ($githubMap.ContainsKey($key) -or -not [string]::IsNullOrWhiteSpace($htmlUrl)) {
            'local+github'
        } else {
            'local'
        }

        $lifecycle = _ResolveLifecycleState `
            -IsArchived $isArchived `
            -RoadmapState $roadmapState `
            -DispatchReadiness $dispatchReadiness `
            -MaturityLevel $maturityLevel `
            -ExecutionState $execState `
            -HasReadme $hasReadme `
            -HasRoadmap $hasRoadmap `
            -PendingItemCount $pendingCount `
            -StructureFindings $structFindings

        $pendingItemsRaw = @(_GetPendingRoadmapItems -RoadmapEntry $roadmapEntry -MaturityEntry $maturityEntry)
        $hasCiSignal = if ($null -ne $structAudit) { [bool]$structAudit.hasCiSignal } else { $false }
        $hasTestSignal = if ($null -ne $structAudit) { [bool]$structAudit.hasTestSignal } else { $false }
        $repoContext = [pscustomobject]@{
            repoName          = $repoName
            repoType          = $repoType
            lifecycleState    = $lifecycle.state
            maturityLevel     = $maturityLevel
            maturityScore     = $maturityScore
            dispatchReadiness = $dispatchReadiness
            hasCiSignal       = $hasCiSignal
            hasTestSignal     = $hasTestSignal
            sourceCoverage    = $sourceCoverage
            docFindingCount   = @($docFindings).Count
            pendingItemCount  = $pendingCount
        }
        $scoredPendingItems = @(_ScorePendingRoadmapItems -PendingItems $pendingItemsRaw -RepoContext $repoContext -ValueScoringConfig $ValueScoringConfig)
        $topValueItem = _SelectTopValueItem -ScoredItems $scoredPendingItems
        $readmeScore = _Get-ReadmeScore -HasReadme $hasReadme -DocFindingCount @($docFindings).Count
        $roadmapScore = _Get-RoadmapScore -HasRoadmap $hasRoadmap -RoadmapState $roadmapState -MaturityScore $maturityScore -PendingItemCount $pendingCount
        $documentationHealthScore = _Get-DocumentationHealthScore -ReadmeScore $readmeScore -RoadmapScore $roadmapScore -DocFindingCount @($docFindings).Count -HasCiSignal $hasCiSignal -HasTestSignal $hasTestSignal
        $dispatchReadinessExplanation = _Get-DispatchReadinessExplanation -DispatchReadiness $dispatchReadiness
        $openPrCount = [int](_GetField -Obj $githubRepo -Name 'openPrCount' -Default (_GetField -Obj $repo -Name 'openPrCount' -Default 0))
        $pendingReviewPrCount = [int](_GetField -Obj $githubRepo -Name 'pendingReviewPrCount' -Default (_GetField -Obj $repo -Name 'pendingReviewPrCount' -Default 0))

        $assessments.Add([pscustomobject]@{
            repoName            = $repoName
            localPath           = $localPath
            htmlUrl             = $htmlUrl
            branch              = $branch
            gitStatus           = $gitStatus
            isArchived          = $isArchived
            sourceCoverage      = $sourceCoverage
            hasPages            = [bool](_GetField -Obj $githubRepo -Name 'hasPages' -Default (_GetField -Obj $repo -Name 'hasPages' -Default $false))
            pagesUrl            = _GetField -Obj $githubRepo -Name 'pagesUrl' -Default (_GetField -Obj $repo -Name 'pagesUrl' -Default $null)
            createdAt           = _GetField -Obj $githubRepo -Name 'createdAt' -Default (_GetField -Obj $repo -Name 'createdAt' -Default $null)
            updatedAt           = _GetField -Obj $githubRepo -Name 'updatedAt' -Default (_GetField -Obj $repo -Name 'updatedAt' -Default $null)
            latestWorkflowRunStatus = _GetField -Obj $githubRepo -Name 'latestWorkflowRunStatus' -Default (_GetField -Obj $repo -Name 'latestWorkflowRunStatus' -Default $null)
            latestWorkflowRunConclusion = _GetField -Obj $githubRepo -Name 'latestWorkflowRunConclusion' -Default (_GetField -Obj $repo -Name 'latestWorkflowRunConclusion' -Default $null)
            latestWorkflowRunName = _GetField -Obj $githubRepo -Name 'latestWorkflowRunName' -Default (_GetField -Obj $repo -Name 'latestWorkflowRunName' -Default $null)
            latestWorkflowRunTimestamp = _GetField -Obj $githubRepo -Name 'latestWorkflowRunTimestamp' -Default (_GetField -Obj $repo -Name 'latestWorkflowRunTimestamp' -Default $null)
            openPrCount         = $openPrCount
            pendingReviewPrCount = $pendingReviewPrCount
            repoType            = $repoType
            lifecycleState      = $lifecycle.state
            recommendedAction   = $lifecycle.recommendedAction
            blockingReasons     = @($lifecycle.blockingReasons)
            roadmapState        = $roadmapState
            roadmapPath         = $roadmapPath
            hasRoadmap          = [bool]$hasRoadmap
            pendingItemCount    = $pendingCount
            nextPendingItemText = $nextItemText
            pendingItems        = @($scoredPendingItems)
            topValueItem        = $topValueItem
            maturityLevel       = $maturityLevel
            maturityScore       = $maturityScore
            dispatchReadiness   = $dispatchReadiness
            executionState      = $execState
            hasReadme           = [bool]$hasReadme
            readmeScore         = $readmeScore
            roadmapScore        = $roadmapScore
            documentationHealthScore = $documentationHealthScore
            hasCiSignal         = if ($null -ne $structAudit) { [bool]$structAudit.hasCiSignal } else { $false }
            hasTestSignal       = if ($null -ne $structAudit) { [bool]$structAudit.hasTestSignal } else { $false }
            structureFindings   = @($structFindings)
            docFindingCount     = @($docFindings).Count
            dispatchReadinessExplanation = $dispatchReadinessExplanation
        }) | Out-Null
    }

    # GitHub-only repos — those discovered on GitHub but not present locally.
    foreach ($gh in @($GitHubRepos)) {
        if ($null -eq $gh) { continue }
        $name = [string](_GetField -Obj $gh -Name 'name' -Default '')
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        $key = _NormalizeKey $name
        if ($seenLocalKeys.Contains($key)) { continue }

        $assessments.Add([pscustomobject]@{
            repoName            = $name
            localPath           = ''
            htmlUrl             = [string](_GetField -Obj $gh -Name 'htmlUrl' -Default '')
            branch              = [string](_GetField -Obj $gh -Name 'branch' -Default '')
            gitStatus           = 'unknown'
            isArchived          = [bool](_GetField -Obj $gh -Name 'isArchived' -Default $false)
            sourceCoverage      = 'github'
            hasPages            = [bool](_GetField -Obj $gh -Name 'hasPages' -Default $false)
            pagesUrl            = _GetField -Obj $gh -Name 'pagesUrl' -Default $null
            createdAt           = _GetField -Obj $gh -Name 'createdAt' -Default $null
            updatedAt           = _GetField -Obj $gh -Name 'updatedAt' -Default $null
            latestWorkflowRunStatus = _GetField -Obj $gh -Name 'latestWorkflowRunStatus' -Default $null
            latestWorkflowRunConclusion = _GetField -Obj $gh -Name 'latestWorkflowRunConclusion' -Default $null
            latestWorkflowRunName = _GetField -Obj $gh -Name 'latestWorkflowRunName' -Default $null
            latestWorkflowRunTimestamp = _GetField -Obj $gh -Name 'latestWorkflowRunTimestamp' -Default $null
            openPrCount         = [int](_GetField -Obj $gh -Name 'openPrCount' -Default 0)
            pendingReviewPrCount = [int](_GetField -Obj $gh -Name 'pendingReviewPrCount' -Default 0)
            repoType            = 'other'
            lifecycleState      = 'discovered'
            recommendedAction   = 'Clone the repo locally so it can participate in the work queue.'
            blockingReasons     = @('Repository exists on GitHub but is not present in any configured local root.')
            roadmapState        = 'missing'
            roadmapPath         = ''
            hasRoadmap          = $false
            pendingItemCount    = 0
            nextPendingItemText = ''
            pendingItems        = @()
            topValueItem        = $null
            maturityLevel       = 'L0-Absent'
            maturityScore       = 0
            dispatchReadiness   = 'missing-roadmap'
            executionState      = 'idle'
            hasReadme           = $false
            readmeScore         = 0
            roadmapScore        = 0
            documentationHealthScore = 0
            hasCiSignal         = $false
            hasTestSignal       = $false
            structureFindings   = @()
            docFindingCount     = 0
            dispatchReadinessExplanation = (_Get-DispatchReadinessExplanation -DispatchReadiness 'missing-roadmap')
        }) | Out-Null
    }

    return ,@($assessments)
}

# ---------------------------------------------------------------------------
# Portfolio summary aggregation — used by the dashboard mission panel.
# ---------------------------------------------------------------------------

function Get-PortfolioAssessmentSummary {
    [CmdletBinding()]
    param([Parameter()][AllowEmptyCollection()][object[]]$Assessments = @())

    $entries = @($Assessments)
    $total = $entries.Count

    $byLifecycle = @{}
    foreach ($state in @(
        'discovered','needs-readme','needs-roadmap','needs-roadmap-repair',
        'needs-structure','ready-for-work','running','completed','monitored',
        'archived','parse-error'
    )) { $byLifecycle[$state] = 0 }

    $byCoverage = @{ 'local' = 0; 'github' = 0; 'local+github' = 0 }
    $missingReadme = 0
    $missingRoadmap = 0
    $weakRoadmap = 0
    $readyForWork = 0
    $running = 0
    $blocked = 0

    foreach ($a in $entries) {
        $lc = [string](_GetField -Obj $a -Name 'lifecycleState' -Default 'discovered')
        if ($byLifecycle.ContainsKey($lc)) { $byLifecycle[$lc] = $byLifecycle[$lc] + 1 } else { $byLifecycle[$lc] = 1 }

        $cov = [string](_GetField -Obj $a -Name 'sourceCoverage' -Default 'local')
        if ($byCoverage.ContainsKey($cov)) { $byCoverage[$cov] = $byCoverage[$cov] + 1 } else { $byCoverage[$cov] = 1 }

        if (-not [bool](_GetField -Obj $a -Name 'hasReadme' -Default $true)) { $missingReadme++ }
        if (-not [bool](_GetField -Obj $a -Name 'hasRoadmap' -Default $true)) { $missingRoadmap++ }

        $ml = [string](_GetField -Obj $a -Name 'maturityLevel' -Default 'L0-Absent')
        if ($ml -in @('L0-Absent','L1-Informal','L2-Structured') -and [bool](_GetField -Obj $a -Name 'hasRoadmap' -Default $false)) {
            $weakRoadmap++
        }

        switch ($lc) {
            'ready-for-work' { $readyForWork++ }
            'running'        { $running++ }
            'needs-readme'    { $blocked++ }
            'needs-roadmap'   { $blocked++ }
            'needs-roadmap-repair' { $blocked++ }
            'needs-structure' { $blocked++ }
            'parse-error'     { $blocked++ }
        }
    }

    return [pscustomobject]@{
        totalRepos     = $total
        byLifecycle    = $byLifecycle
        bySourceCoverage = $byCoverage
        missingReadmeCount    = $missingReadme
        missingRoadmapCount   = $missingRoadmap
        weakRoadmapCount      = $weakRoadmap
        readyForWorkCount     = $readyForWork
        runningCount          = $running
        blockedCount          = $blocked
    }
}

function _ClampScore {
    param([int]$Value)

    if ($Value -lt 0) { return 0 }
    if ($Value -gt 100) { return 100 }
    return $Value
}

function _Get-DispatchReadinessExplanation {
    param([string]$DispatchReadiness)

    switch ([string]$DispatchReadiness) {
        'ready' {
            return 'Documentation and roadmap signals are strong enough for dispatch.'
        }
        'needs-doc-standardization' {
            return 'Core docs exist, but the repo still needs documentation cleanup before dispatch.'
        }
        'roadmap-complete' {
            return 'The roadmap has no pending work, so dispatch should move to a new release or maintenance task.'
        }
        'parse-error' {
            return 'The roadmap exists, but it could not be parsed into the standard contract format.'
        }
        'blocked' {
            return 'Blocking findings prevent reliable execution and should be resolved before dispatch.'
        }
        default {
            return 'A roadmap or supporting documentation is missing, so the repo is not yet dispatch-ready.'
        }
    }
}

function _Get-ReadmeScore {
    param(
        [bool]$HasReadme,
        [int]$DocFindingCount
    )

    if (-not $HasReadme) { return 0 }

    $penalty = [Math]::Min(25, ([Math]::Max(0, $DocFindingCount) * 5))
    return _ClampScore -Value (100 - $penalty)
}

function _Get-RoadmapScore {
    param(
        [bool]$HasRoadmap,
        [string]$RoadmapState,
        [int]$MaturityScore,
        [int]$PendingItemCount
    )

    if (-not $HasRoadmap) { return 0 }

    switch ([string]$RoadmapState) {
        'parse-error' {
            return 20
        }
        'complete' {
            return _ClampScore -Value ([Math]::Max(90, $MaturityScore))
        }
        'pending' {
            $base = [Math]::Max(55, $MaturityScore)
            if ($PendingItemCount -le 3) { $base += 10 }
            return _ClampScore -Value $base
        }
        default {
            return _ClampScore -Value ([Math]::Max(35, $MaturityScore))
        }
    }
}

function _Get-DocumentationHealthScore {
    param(
        [int]$ReadmeScore,
        [int]$RoadmapScore,
        [int]$DocFindingCount,
        [bool]$HasCiSignal,
        [bool]$HasTestSignal
    )

    $base = [Math]::Round((([double]$ReadmeScore) + ([double]$RoadmapScore)) / 2.0)
    $bonus = 0
    if ($HasCiSignal) { $bonus += 5 }
    if ($HasTestSignal) { $bonus += 5 }
    $penalty = [Math]::Min(15, ([Math]::Max(0, $DocFindingCount) * 2))
    return _ClampScore -Value ([int]($base + $bonus - $penalty))
}

function _Get-GitHubIdentityFromRemoteUrl {
    param([string]$RemoteUrl)

    if ([string]::IsNullOrWhiteSpace($RemoteUrl)) {
        return [pscustomobject]@{
            owner    = ''
            repo     = ''
            fullName = ''
        }
    }

    $trimmed = $RemoteUrl.Trim()
    $patterns = @(
        'github\.com[:/](?<owner>[^/]+)/(?<repo>[^/]+?)(?:\.git)?/?$',
        '^git@github\.com:(?<owner>[^/]+)/(?<repo>[^/]+?)(?:\.git)?/?$'
    )

    foreach ($pattern in $patterns) {
        $match = [regex]::Match($trimmed, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($match.Success) {
            $owner = $match.Groups['owner'].Value
            $repo = $match.Groups['repo'].Value
            return [pscustomobject]@{
                owner    = $owner
                repo     = $repo
                fullName = if ([string]::IsNullOrWhiteSpace($owner) -or [string]::IsNullOrWhiteSpace($repo)) { '' } else { '{0}/{1}' -f $owner, $repo }
            }
        }
    }

    return [pscustomobject]@{
        owner    = ''
        repo     = ''
        fullName = ''
    }
}

function _Get-FileLastWriteUtcIso {
    param([string]$FilePath)

    if ([string]::IsNullOrWhiteSpace($FilePath) -or -not (Test-Path -LiteralPath $FilePath -PathType Leaf -ErrorAction SilentlyContinue)) {
        return ''
    }

    try {
        return ([System.IO.File]::GetLastWriteTimeUtc($FilePath)).ToString('o')
    } catch {
        return ''
    }
}

function _Get-PortfolioStableHash {
    param([string]$InputText)

    if ([string]::IsNullOrEmpty($InputText)) { return '' }

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($InputText)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $digest = $sha.ComputeHash($bytes)
    } finally {
        $sha.Dispose()
    }
    return ([BitConverter]::ToString($digest)).Replace('-', '').ToLowerInvariant()
}

function Get-PortfolioScanFingerprintFromSignals {
    [CmdletBinding()]
    param(
        [Parameter()][object]$LocalRepo,
        [Parameter()][object]$GitHubRepo,
        [Parameter()][string]$LocalPath = '',
        [Parameter()][string]$SourceCoverage = 'local'
    )

    $effectiveLocalPath = if ([string]::IsNullOrWhiteSpace($LocalPath)) {
        [string](_GetField -Obj $LocalRepo -Name 'path' -Default '')
    } else {
        [string]$LocalPath
    }

    $readmePath = if ([string]::IsNullOrWhiteSpace($effectiveLocalPath)) { '' } else { Join-Path $effectiveLocalPath 'README.md' }
    $roadmapPath = if ([string]::IsNullOrWhiteSpace($effectiveLocalPath)) { '' } else { Join-Path $effectiveLocalPath 'ROADMAP.md' }

    $tokens = [ordered]@{
        sourceCoverage             = [string]$SourceCoverage
        localPath                  = $effectiveLocalPath
        localBranch                = [string](_GetField -Obj $LocalRepo -Name 'branch' -Default '')
        localStatus                = [string](_GetField -Obj $LocalRepo -Name 'status' -Default '')
        localOriginUrl             = [string](_GetField -Obj $LocalRepo -Name 'originUrl' -Default '')
        localLastCommitDate        = [string](_GetField -Obj $LocalRepo -Name 'lastCommitDate' -Default '')
        localCommitsLastWeek       = [int](_GetField -Obj $LocalRepo -Name 'commitsLastWeek' -Default 0)
        localCommitsLastMonth      = [int](_GetField -Obj $LocalRepo -Name 'commitsLastMonth' -Default 0)
        localModifiedCount         = [int](_GetField -Obj $LocalRepo -Name 'modifiedCount' -Default 0)
        localUntrackedCount        = [int](_GetField -Obj $LocalRepo -Name 'untrackedCount' -Default 0)
        localDirtyCount            = [int](_GetField -Obj $LocalRepo -Name 'dirtyCount' -Default 0)
        readmeLastWriteUtc         = (_Get-FileLastWriteUtcIso -FilePath $readmePath)
        roadmapLastWriteUtc        = (_Get-FileLastWriteUtcIso -FilePath $roadmapPath)
        githubUpdatedAt            = [string](_GetField -Obj $GitHubRepo -Name 'updatedAt' -Default '')
        githubOpenPrCount          = [int](_GetField -Obj $GitHubRepo -Name 'openPrCount' -Default 0)
        githubPendingReviewPrCount = [int](_GetField -Obj $GitHubRepo -Name 'pendingReviewPrCount' -Default 0)
        githubLatestRunStatus      = [string](_GetField -Obj $GitHubRepo -Name 'latestWorkflowRunStatus' -Default '')
        githubLatestRunConclusion  = [string](_GetField -Obj $GitHubRepo -Name 'latestWorkflowRunConclusion' -Default '')
        githubLatestRunName        = [string](_GetField -Obj $GitHubRepo -Name 'latestWorkflowRunName' -Default '')
        githubLatestRunTimestamp   = [string](_GetField -Obj $GitHubRepo -Name 'latestWorkflowRunTimestamp' -Default '')
        githubHasPages             = [string]([bool](_GetField -Obj $GitHubRepo -Name 'hasPages' -Default $false))
        githubPagesUrl             = [string](_GetField -Obj $GitHubRepo -Name 'pagesUrl' -Default '')
    }

    $parts = [System.Collections.Generic.List[string]]::new()
    foreach ($k in $tokens.Keys) {
        $parts.Add(('{0}={1}' -f $k, [string]$tokens[$k])) | Out-Null
    }
    return _Get-PortfolioStableHash -InputText ($parts -join '|')
}

function Get-PortfolioScanFingerprintFromIndexedRepo {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$IndexedRepo)

    $existing = [string](_GetField -Obj $IndexedRepo -Name 'scanFingerprint' -Default '')
    if (-not [string]::IsNullOrWhiteSpace($existing)) {
        return $existing
    }

    $tokens = [ordered]@{
        sourceCoverage             = [string](_GetField -Obj $IndexedRepo -Name 'sourceCoverage' -Default '')
        localPath                  = [string](_GetField -Obj $IndexedRepo -Name 'localPath' -Default '')
        localBranch                = [string](_GetField -Obj $IndexedRepo -Name 'currentBranch' -Default '')
        localStatus                = [string](_GetField -Obj $IndexedRepo -Name 'gitStatus' -Default '')
        localOriginUrl             = [string](_GetField -Obj $IndexedRepo -Name 'remoteUrl' -Default '')
        localLastCommitDate        = [string](_GetField -Obj $IndexedRepo -Name 'localLastCommitDate' -Default '')
        localCommitsLastWeek       = [int](_GetField -Obj $IndexedRepo -Name 'localCommitsLastWeek' -Default 0)
        localCommitsLastMonth      = [int](_GetField -Obj $IndexedRepo -Name 'localCommitsLastMonth' -Default 0)
        localModifiedCount         = [int](_GetField -Obj $IndexedRepo -Name 'localModifiedCount' -Default 0)
        localUntrackedCount        = [int](_GetField -Obj $IndexedRepo -Name 'localUntrackedCount' -Default 0)
        localDirtyCount            = [int](_GetField -Obj $IndexedRepo -Name 'localDirtyCount' -Default 0)
        readmeLastWriteUtc         = [string](_GetField -Obj $IndexedRepo -Name 'readmeLastWriteUtc' -Default '')
        roadmapLastWriteUtc        = [string](_GetField -Obj $IndexedRepo -Name 'roadmapLastWriteUtc' -Default '')
        githubUpdatedAt            = [string](_GetField -Obj $IndexedRepo -Name 'updatedAt' -Default '')
        githubOpenPrCount          = [int](_GetField -Obj $IndexedRepo -Name 'openPrCount' -Default 0)
        githubPendingReviewPrCount = [int](_GetField -Obj $IndexedRepo -Name 'pendingReviewPrCount' -Default 0)
        githubLatestRunStatus      = [string](_GetField -Obj $IndexedRepo -Name 'latestWorkflowRunStatus' -Default '')
        githubLatestRunConclusion  = [string](_GetField -Obj $IndexedRepo -Name 'latestWorkflowRunConclusion' -Default '')
        githubLatestRunName        = [string](_GetField -Obj $IndexedRepo -Name 'latestWorkflowRunName' -Default '')
        githubLatestRunTimestamp   = [string](_GetField -Obj $IndexedRepo -Name 'latestWorkflowRunTimestamp' -Default '')
        githubHasPages             = [string]([bool](_GetField -Obj $IndexedRepo -Name 'hasPages' -Default $false))
        githubPagesUrl             = [string](_GetField -Obj $IndexedRepo -Name 'pagesUrl' -Default '')
    }

    $parts = [System.Collections.Generic.List[string]]::new()
    foreach ($k in $tokens.Keys) {
        $parts.Add(('{0}={1}' -f $k, [string]$tokens[$k])) | Out-Null
    }
    return _Get-PortfolioStableHash -InputText ($parts -join '|')
}

function New-PortfolioIndexPayload {
    [CmdletBinding()]
    param(
        [Parameter()][AllowEmptyCollection()][object[]]$Assessments = @(),
        [Parameter()][AllowEmptyCollection()][object[]]$LocalRepos = @(),
        [Parameter()][AllowEmptyCollection()][object[]]$GitHubRepos = @(),
        [Parameter()][object]$Summary,
        [Parameter()][object]$SignalSources,
        [Parameter(Mandatory = $true)][string]$GeneratedAt
    )

    $localMap = _IndexByRepoName -Items $LocalRepos -NameField 'name'
    $githubMap = _IndexByRepoName -Items $GitHubRepos -NameField 'name'

    $ordered = @($Assessments | Sort-Object `
        @{ Expression = { [string](_GetField -Obj $_ -Name 'repoName' -Default '') }; Ascending = $true },
        @{ Expression = { [string](_GetField -Obj $_ -Name 'sourceCoverage' -Default '') }; Ascending = $true })

    $repos = [System.Collections.Generic.List[object]]::new()
    for ($i = 0; $i -lt $ordered.Count; $i++) {
        $assessment = $ordered[$i]
        if ($null -eq $assessment) { continue }

        $repoName = [string](_GetField -Obj $assessment -Name 'repoName' -Default '')
        if ([string]::IsNullOrWhiteSpace($repoName)) { continue }

        $key = _NormalizeKey $repoName
        $localRepo = if ($localMap.ContainsKey($key)) { $localMap[$key] } else { $null }
        $githubRepo = if ($githubMap.ContainsKey($key)) { $githubMap[$key] } else { $null }

        $localPath = [string](_GetField -Obj $assessment -Name 'localPath' -Default (_GetField -Obj $localRepo -Name 'path' -Default ''))
        $remoteUrl = [string](_GetField -Obj $localRepo -Name 'originUrl' -Default '')
        $remoteIdentity = _Get-GitHubIdentityFromRemoteUrl -RemoteUrl $remoteUrl

        $githubOwner = [string](_GetField -Obj $githubRepo -Name 'owner' -Default $remoteIdentity.owner)
        $githubRepoName = if ($null -ne $githubRepo) {
            [string](_GetField -Obj $githubRepo -Name 'name' -Default $remoteIdentity.repo)
        } else {
            $remoteIdentity.repo
        }
        $githubFullName = if (-not [string]::IsNullOrWhiteSpace($githubOwner) -and -not [string]::IsNullOrWhiteSpace($githubRepoName)) {
            '{0}/{1}' -f $githubOwner, $githubRepoName
        } else {
            [string](_GetField -Obj $githubRepo -Name 'fullName' -Default $remoteIdentity.fullName)
        }
        $currentBranch = [string](_GetField -Obj $assessment -Name 'branch' -Default (_GetField -Obj $localRepo -Name 'branch' -Default ''))
        $defaultBranch = [string](_GetField -Obj $githubRepo -Name 'branch' -Default $currentBranch)
        $htmlUrl = [string](_GetField -Obj $assessment -Name 'htmlUrl' -Default (_GetField -Obj $githubRepo -Name 'htmlUrl' -Default ''))
        $hasPages = [bool](_GetField -Obj $assessment -Name 'hasPages' -Default (_GetField -Obj $githubRepo -Name 'hasPages' -Default $false))
        $pagesUrl = [string](_GetField -Obj $assessment -Name 'pagesUrl' -Default (_GetField -Obj $githubRepo -Name 'pagesUrl' -Default ''))
        $createdAt = [string](_GetField -Obj $assessment -Name 'createdAt' -Default (_GetField -Obj $githubRepo -Name 'createdAt' -Default ''))
        $updatedAt = [string](_GetField -Obj $assessment -Name 'updatedAt' -Default (_GetField -Obj $githubRepo -Name 'updatedAt' -Default ''))
        $latestWorkflowRunStatus = [string](_GetField -Obj $assessment -Name 'latestWorkflowRunStatus' -Default (_GetField -Obj $githubRepo -Name 'latestWorkflowRunStatus' -Default ''))
        $latestWorkflowRunConclusion = [string](_GetField -Obj $assessment -Name 'latestWorkflowRunConclusion' -Default (_GetField -Obj $githubRepo -Name 'latestWorkflowRunConclusion' -Default ''))
        $latestWorkflowRunName = [string](_GetField -Obj $assessment -Name 'latestWorkflowRunName' -Default (_GetField -Obj $githubRepo -Name 'latestWorkflowRunName' -Default ''))
        $latestWorkflowRunTimestamp = [string](_GetField -Obj $assessment -Name 'latestWorkflowRunTimestamp' -Default (_GetField -Obj $githubRepo -Name 'latestWorkflowRunTimestamp' -Default ''))
        $openPrCount = [int](_GetField -Obj $assessment -Name 'openPrCount' -Default (_GetField -Obj $githubRepo -Name 'openPrCount' -Default 0))
        $pendingReviewPrCount = [int](_GetField -Obj $assessment -Name 'pendingReviewPrCount' -Default (_GetField -Obj $githubRepo -Name 'pendingReviewPrCount' -Default 0))
        $localLastCommitDate = [string](_GetField -Obj $localRepo -Name 'lastCommitDate' -Default '')
        $localCommitsLastWeek = [int](_GetField -Obj $localRepo -Name 'commitsLastWeek' -Default 0)
        $localCommitsLastMonth = [int](_GetField -Obj $localRepo -Name 'commitsLastMonth' -Default 0)
        $localModifiedCount = [int](_GetField -Obj $localRepo -Name 'modifiedCount' -Default 0)
        $localUntrackedCount = [int](_GetField -Obj $localRepo -Name 'untrackedCount' -Default 0)
        $localDirtyCount = [int](_GetField -Obj $localRepo -Name 'dirtyCount' -Default 0)
        $readmeLastWriteUtc = if ([string]::IsNullOrWhiteSpace($localPath)) { '' } else { _Get-FileLastWriteUtcIso -FilePath (Join-Path $localPath 'README.md') }
        $roadmapLastWriteUtc = if ([string]::IsNullOrWhiteSpace($localPath)) { '' } else { _Get-FileLastWriteUtcIso -FilePath (Join-Path $localPath 'ROADMAP.md') }
        $scanFingerprint = Get-PortfolioScanFingerprintFromSignals -LocalRepo $localRepo -GitHubRepo $githubRepo -LocalPath $localPath -SourceCoverage ([string](_GetField -Obj $assessment -Name 'sourceCoverage' -Default 'local'))

        $repos.Add([pscustomobject]@{
            ordinal             = $i + 1
            repoName            = $repoName
            sourceCoverage      = [string](_GetField -Obj $assessment -Name 'sourceCoverage' -Default 'local')
            localPath           = $localPath
            remoteUrl           = $remoteUrl
            githubOwner         = $githubOwner
            githubRepo          = $githubRepoName
            githubFullName      = $githubFullName
            htmlUrl             = $htmlUrl
            defaultBranch       = $defaultBranch
            currentBranch       = $currentBranch
            hasPages            = $hasPages
            pagesUrl            = if ([string]::IsNullOrWhiteSpace($pagesUrl)) { $null } else { $pagesUrl }
            createdAt           = if ([string]::IsNullOrWhiteSpace($createdAt)) { $null } else { $createdAt }
            updatedAt           = if ([string]::IsNullOrWhiteSpace($updatedAt)) { $null } else { $updatedAt }
            latestWorkflowRunStatus = if ([string]::IsNullOrWhiteSpace($latestWorkflowRunStatus)) { $null } else { $latestWorkflowRunStatus }
            latestWorkflowRunConclusion = if ([string]::IsNullOrWhiteSpace($latestWorkflowRunConclusion)) { $null } else { $latestWorkflowRunConclusion }
            latestWorkflowRunName = if ([string]::IsNullOrWhiteSpace($latestWorkflowRunName)) { $null } else { $latestWorkflowRunName }
            latestWorkflowRunTimestamp = if ([string]::IsNullOrWhiteSpace($latestWorkflowRunTimestamp)) { $null } else { $latestWorkflowRunTimestamp }
            openPrCount         = $openPrCount
            pendingReviewPrCount = $pendingReviewPrCount
            localLastCommitDate = if ([string]::IsNullOrWhiteSpace($localLastCommitDate)) { $null } else { $localLastCommitDate }
            localCommitsLastWeek = $localCommitsLastWeek
            localCommitsLastMonth = $localCommitsLastMonth
            localModifiedCount = $localModifiedCount
            localUntrackedCount = $localUntrackedCount
            localDirtyCount = $localDirtyCount
            readmeLastWriteUtc = if ([string]::IsNullOrWhiteSpace($readmeLastWriteUtc)) { $null } else { $readmeLastWriteUtc }
            roadmapLastWriteUtc = if ([string]::IsNullOrWhiteSpace($roadmapLastWriteUtc)) { $null } else { $roadmapLastWriteUtc }
            scanFingerprint     = $scanFingerprint
            repoType            = [string](_GetField -Obj $assessment -Name 'repoType' -Default 'other')
            lifecycleState      = [string](_GetField -Obj $assessment -Name 'lifecycleState' -Default 'discovered')
            recommendedAction   = [string](_GetField -Obj $assessment -Name 'recommendedAction' -Default '')
            blockingReasons     = @(_GetField -Obj $assessment -Name 'blockingReasons' -Default @())
            roadmapState        = [string](_GetField -Obj $assessment -Name 'roadmapState' -Default 'missing')
            roadmapPath         = [string](_GetField -Obj $assessment -Name 'roadmapPath' -Default '')
            hasRoadmap          = [bool](_GetField -Obj $assessment -Name 'hasRoadmap' -Default $false)
            hasReadme           = [bool](_GetField -Obj $assessment -Name 'hasReadme' -Default $false)
            readmeScore         = [int](_GetField -Obj $assessment -Name 'readmeScore' -Default 0)
            roadmapScore        = [int](_GetField -Obj $assessment -Name 'roadmapScore' -Default 0)
            documentationHealthScore = [int](_GetField -Obj $assessment -Name 'documentationHealthScore' -Default 0)
            pendingItemCount    = [int](_GetField -Obj $assessment -Name 'pendingItemCount' -Default 0)
            nextPendingItemText = [string](_GetField -Obj $assessment -Name 'nextPendingItemText' -Default '')
            topValueItem        = _GetField -Obj $assessment -Name 'topValueItem' -Default $null
            maturityLevel       = [string](_GetField -Obj $assessment -Name 'maturityLevel' -Default 'L0-Absent')
            maturityScore       = [int](_GetField -Obj $assessment -Name 'maturityScore' -Default 0)
            dispatchReadiness   = [string](_GetField -Obj $assessment -Name 'dispatchReadiness' -Default 'missing-roadmap')
            dispatchReadinessExplanation = [string](_GetField -Obj $assessment -Name 'dispatchReadinessExplanation' -Default '')
            executionState      = [string](_GetField -Obj $assessment -Name 'executionState' -Default 'idle')
            gitStatus           = [string](_GetField -Obj $assessment -Name 'gitStatus' -Default 'unknown')
            hasCiSignal         = [bool](_GetField -Obj $assessment -Name 'hasCiSignal' -Default $false)
            hasTestSignal       = [bool](_GetField -Obj $assessment -Name 'hasTestSignal' -Default $false)
            docFindingCount     = [int](_GetField -Obj $assessment -Name 'docFindingCount' -Default 0)
            structureFindings   = @(_GetField -Obj $assessment -Name 'structureFindings' -Default @())
        }) | Out-Null
    }

    return [pscustomobject]@{
        schemaVersion = 1
        kind          = 'portfolio-index'
        generatedAt   = $GeneratedAt
        repoCount     = $repos.Count
        signalSources = $SignalSources
        summary       = $Summary
        repos         = @($repos)
    }
}

function Save-PortfolioIndexArtifacts {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$WorkspaceRoot,
        [Parameter()][AllowEmptyCollection()][object[]]$Assessments = @(),
        [Parameter()][AllowEmptyCollection()][object[]]$LocalRepos = @(),
        [Parameter()][AllowEmptyCollection()][object[]]$GitHubRepos = @(),
        [Parameter()][object]$Summary,
        [Parameter()][object]$SignalSources,
        [Parameter(Mandatory = $true)][string]$GeneratedAt
    )

    $indexRoot = Join-Path $WorkspaceRoot 'output\index'
    $scansRoot = Join-Path $indexRoot 'scans'
    if (-not (Test-Path -LiteralPath $indexRoot)) {
        $null = New-Item -ItemType Directory -Path $indexRoot -Force
    }
    if (-not (Test-Path -LiteralPath $scansRoot)) {
        $null = New-Item -ItemType Directory -Path $scansRoot -Force
    }

    $payload = New-PortfolioIndexPayload `
        -Assessments $Assessments `
        -LocalRepos $LocalRepos `
        -GitHubRepos $GitHubRepos `
        -Summary $Summary `
        -SignalSources $SignalSources `
        -GeneratedAt $GeneratedAt

    $json = $payload | ConvertTo-Json -Depth 12
    $indexPath = Join-Path $indexRoot 'repos.index.json'
    Set-Content -LiteralPath $indexPath -Value $json -Encoding UTF8

    $artifactName = ('portfolio-scan-{0}.json' -f ((Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')))
    $artifactPath = Join-Path $scansRoot $artifactName
    Set-Content -LiteralPath $artifactPath -Value $json -Encoding UTF8

    return [pscustomobject]@{
        indexPath    = $indexPath
        artifactPath = $artifactPath
        repoCount    = [int]$payload.repoCount
        generatedAt  = $GeneratedAt
    }
}

function Get-PortfolioIndexPayload {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$WorkspaceRoot)

    $indexPath = Join-Path (Join-Path $WorkspaceRoot 'output\index') 'repos.index.json'
    if (-not (Test-Path -LiteralPath $indexPath -PathType Leaf -ErrorAction SilentlyContinue)) {
        return $null
    }

    try {
        $raw = Get-Content -LiteralPath $indexPath -Raw -Encoding UTF8 -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
        return ConvertFrom-Json -InputObject $raw
    } catch {
        return $null
    }
}

function Convert-PortfolioIndexReposToAssessments {
    [CmdletBinding()]
    param([Parameter()][AllowEmptyCollection()][object[]]$IndexRepos = @())

    $out = [System.Collections.Generic.List[object]]::new()
    foreach ($repo in @($IndexRepos)) {
        if ($null -eq $repo) { continue }

        $out.Add([pscustomobject]@{
            repoName            = [string](_GetField -Obj $repo -Name 'repoName' -Default '')
            localPath           = [string](_GetField -Obj $repo -Name 'localPath' -Default '')
            htmlUrl             = [string](_GetField -Obj $repo -Name 'htmlUrl' -Default '')
            branch              = [string](_GetField -Obj $repo -Name 'currentBranch' -Default '')
            gitStatus           = [string](_GetField -Obj $repo -Name 'gitStatus' -Default 'unknown')
            isArchived          = [bool](_GetField -Obj $repo -Name 'isArchived' -Default $false)
            sourceCoverage      = [string](_GetField -Obj $repo -Name 'sourceCoverage' -Default 'local')
            hasPages            = [bool](_GetField -Obj $repo -Name 'hasPages' -Default $false)
            pagesUrl            = _GetField -Obj $repo -Name 'pagesUrl' -Default $null
            createdAt           = _GetField -Obj $repo -Name 'createdAt' -Default $null
            updatedAt           = _GetField -Obj $repo -Name 'updatedAt' -Default $null
            latestWorkflowRunStatus = _GetField -Obj $repo -Name 'latestWorkflowRunStatus' -Default $null
            latestWorkflowRunConclusion = _GetField -Obj $repo -Name 'latestWorkflowRunConclusion' -Default $null
            latestWorkflowRunName = _GetField -Obj $repo -Name 'latestWorkflowRunName' -Default $null
            latestWorkflowRunTimestamp = _GetField -Obj $repo -Name 'latestWorkflowRunTimestamp' -Default $null
            openPrCount         = [int](_GetField -Obj $repo -Name 'openPrCount' -Default 0)
            pendingReviewPrCount = [int](_GetField -Obj $repo -Name 'pendingReviewPrCount' -Default 0)
            repoType            = [string](_GetField -Obj $repo -Name 'repoType' -Default 'other')
            lifecycleState      = [string](_GetField -Obj $repo -Name 'lifecycleState' -Default 'discovered')
            recommendedAction   = [string](_GetField -Obj $repo -Name 'recommendedAction' -Default '')
            blockingReasons     = @(_GetField -Obj $repo -Name 'blockingReasons' -Default @())
            roadmapState        = [string](_GetField -Obj $repo -Name 'roadmapState' -Default 'missing')
            roadmapPath         = [string](_GetField -Obj $repo -Name 'roadmapPath' -Default '')
            hasRoadmap          = [bool](_GetField -Obj $repo -Name 'hasRoadmap' -Default $false)
            pendingItemCount    = [int](_GetField -Obj $repo -Name 'pendingItemCount' -Default 0)
            nextPendingItemText = [string](_GetField -Obj $repo -Name 'nextPendingItemText' -Default '')
            pendingItems        = @()
            topValueItem        = _GetField -Obj $repo -Name 'topValueItem' -Default $null
            maturityLevel       = [string](_GetField -Obj $repo -Name 'maturityLevel' -Default 'L0-Absent')
            maturityScore       = [int](_GetField -Obj $repo -Name 'maturityScore' -Default 0)
            dispatchReadiness   = [string](_GetField -Obj $repo -Name 'dispatchReadiness' -Default 'missing-roadmap')
            executionState      = [string](_GetField -Obj $repo -Name 'executionState' -Default 'idle')
            hasReadme           = [bool](_GetField -Obj $repo -Name 'hasReadme' -Default $false)
            readmeScore         = [int](_GetField -Obj $repo -Name 'readmeScore' -Default 0)
            roadmapScore        = [int](_GetField -Obj $repo -Name 'roadmapScore' -Default 0)
            documentationHealthScore = [int](_GetField -Obj $repo -Name 'documentationHealthScore' -Default 0)
            hasCiSignal         = [bool](_GetField -Obj $repo -Name 'hasCiSignal' -Default $false)
            hasTestSignal       = [bool](_GetField -Obj $repo -Name 'hasTestSignal' -Default $false)
            structureFindings   = @(_GetField -Obj $repo -Name 'structureFindings' -Default @())
            docFindingCount     = [int](_GetField -Obj $repo -Name 'docFindingCount' -Default 0)
            dispatchReadinessExplanation = [string](_GetField -Obj $repo -Name 'dispatchReadinessExplanation' -Default '')
        }) | Out-Null
    }

    return ,@($out)
}
