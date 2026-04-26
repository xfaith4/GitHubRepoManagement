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
                                 -GitHubRepos -StructureStandards
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
        [Parameter()][object]$StructureStandards
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

        $assessments.Add([pscustomobject]@{
            repoName            = $repoName
            localPath           = $localPath
            htmlUrl             = $htmlUrl
            branch              = $branch
            gitStatus           = $gitStatus
            isArchived          = $isArchived
            sourceCoverage      = $sourceCoverage
            repoType            = $repoType
            lifecycleState      = $lifecycle.state
            recommendedAction   = $lifecycle.recommendedAction
            blockingReasons     = @($lifecycle.blockingReasons)
            roadmapState        = $roadmapState
            roadmapPath         = $roadmapPath
            hasRoadmap          = [bool]$hasRoadmap
            pendingItemCount    = $pendingCount
            nextPendingItemText = $nextItemText
            maturityLevel       = $maturityLevel
            maturityScore       = $maturityScore
            dispatchReadiness   = $dispatchReadiness
            executionState      = $execState
            hasReadme           = [bool]$hasReadme
            hasCiSignal         = if ($null -ne $structAudit) { [bool]$structAudit.hasCiSignal } else { $false }
            hasTestSignal       = if ($null -ne $structAudit) { [bool]$structAudit.hasTestSignal } else { $false }
            structureFindings   = @($structFindings)
            docFindingCount     = @($docFindings).Count
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
            repoType            = 'other'
            lifecycleState      = 'discovered'
            recommendedAction   = 'Clone the repo locally so it can participate in the work queue.'
            blockingReasons     = @('Repository exists on GitHub but is not present in any configured local root.')
            roadmapState        = 'missing'
            roadmapPath         = ''
            hasRoadmap          = $false
            pendingItemCount    = 0
            nextPendingItemText = ''
            maturityLevel       = 'L0-Absent'
            maturityScore       = 0
            dispatchReadiness   = 'missing-roadmap'
            executionState      = 'idle'
            hasReadme           = $false
            hasCiSignal         = $false
            hasTestSignal       = $false
            structureFindings   = @()
            docFindingCount     = 0
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
