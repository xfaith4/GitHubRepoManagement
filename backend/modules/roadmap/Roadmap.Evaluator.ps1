<#
.SYNOPSIS
    Repo structure evaluator — produces hardening and feature suggestions.
.DESCRIPTION
    Provides two exported functions:

      Invoke-RepoEvaluation
        Inspects a local repository's file structure, detects missing
        best-practice files, and returns a structured list of findings
        with suggested roadmap items.

        When no ROADMAP.md exists the function also generates a complete
        draft ROADMAP.md from the findings.  When one exists, it generates
        a targeted list of suggested additions.

      Get-RepoEvaluationHistory
        Returns past evaluation records from the history directory,
        newest first.

.NOTES
    Dot-source this file from Start-RepoManagementApiHost.ps1 before use:
        . (Join-Path $roadmapModuleRoot 'Roadmap.Evaluator.ps1')
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

function _DetectRepoType {
    param([string]$LocalPath)
    if (Test-Path -LiteralPath (Join-Path $LocalPath 'package.json')   -PathType Leaf) { return 'node' }
    if (@(Get-ChildItem -LiteralPath $LocalPath -Filter '*.csproj' -Recurse -Depth 2 -ErrorAction SilentlyContinue).Count -gt 0) { return 'dotnet' }
    if (@(Get-ChildItem -LiteralPath $LocalPath -Filter '*.sln'    -Recurse -Depth 2 -ErrorAction SilentlyContinue).Count -gt 0) { return 'dotnet' }
    if (Test-Path -LiteralPath (Join-Path $LocalPath 'requirements.txt') -PathType Leaf) { return 'python' }
    if (Test-Path -LiteralPath (Join-Path $LocalPath 'setup.py')         -PathType Leaf) { return 'python' }
    if (Test-Path -LiteralPath (Join-Path $LocalPath 'Cargo.toml')       -PathType Leaf) { return 'rust' }
    if (@(Get-ChildItem -LiteralPath $LocalPath -Filter '*.ps1' -Recurse -Depth 2 -ErrorAction SilentlyContinue).Count -gt 0) { return 'powershell' }
    return 'other'
}

function _HasTestFiles {
    param([string]$LocalPath, [string]$RepoType)
    $testDirs = @('test', 'tests', '__tests__', 'spec', 'specs', 'test-suite')
    foreach ($d in $testDirs) {
        if (Test-Path -LiteralPath (Join-Path $LocalPath $d) -PathType Container) { return $true }
    }
    switch ($RepoType) {
        'node'       { return @(Get-ChildItem -LiteralPath $LocalPath -Filter '*.test.*'  -Recurse -Depth 4 -ErrorAction SilentlyContinue).Count -gt 0 }
        'dotnet'     { return @(Get-ChildItem -LiteralPath $LocalPath -Filter '*Tests*'   -Recurse -Depth 3 -ErrorAction SilentlyContinue).Count -gt 0 }
        'python'     { return @(Get-ChildItem -LiteralPath $LocalPath -Filter 'test_*.py' -Recurse -Depth 4 -ErrorAction SilentlyContinue).Count -gt 0 }
        'powershell' { return @(Get-ChildItem -LiteralPath $LocalPath -Filter '*.Tests.ps1' -Recurse -Depth 4 -ErrorAction SilentlyContinue).Count -gt 0 }
    }
    return $false
}

function _HasCiWorkflows {
    param([string]$LocalPath)
    $githubWorkflows = Join-Path $LocalPath '.github\workflows'
    if (Test-Path -LiteralPath $githubWorkflows -PathType Container) {
        return @(Get-ChildItem -LiteralPath $githubWorkflows -Filter '*.yml' -ErrorAction SilentlyContinue).Count -gt 0
    }
    # GitLab CI
    if (Test-Path -LiteralPath (Join-Path $LocalPath '.gitlab-ci.yml') -PathType Leaf) { return $true }
    # Azure DevOps
    if (Test-Path -LiteralPath (Join-Path $LocalPath 'azure-pipelines.yml') -PathType Leaf) { return $true }
    return $false
}

function _MakeFinding {
    param(
        [string]$FindingId,
        [string]$Category,
        [string]$Severity,
        [string]$Title,
        [string]$Description,
        [string]$RoadmapItem
    )
    return [pscustomobject]@{
        findingId    = $FindingId
        category     = $Category
        severity     = $Severity
        title        = $Title
        description  = $Description
        roadmapItem  = $RoadmapItem
    }
}

function _BuildSuggestedRoadmap {
    param(
        [string]$RepoName,
        [string]$RepoType,
        [array]$Findings
    )

    $typeLabel = switch ($RepoType) {
        'node'       { 'Node.js' }
        'dotnet'     { '.NET' }
        'python'     { 'Python' }
        'rust'       { 'Rust' }
        'powershell' { 'PowerShell' }
        default      { 'software' }
    }

    $milestones = @($Findings | ForEach-Object { "- [ ] $($_.roadmapItem)" }) -join "`n"

    return @"
# $RepoName Roadmap

## Overview

This roadmap captures the planned hardening and improvement work for **$RepoName** ($typeLabel project).

---

## Release 1.0 — Foundational Hardening

**Goal:** Establish baseline quality practices so the repository is maintainable, testable, and safe to collaborate on.

### Product outcomes

- Consistent project structure with all expected best-practice files in place.
- Automated CI pipeline runs on every pull request.
- Contributors can onboard from the README alone.

### Engineering milestones

$milestones

### Acceptance criteria

- All checklist items above are marked complete.
- CI pipeline passes on the main branch.
- README describes how to build, test, and run the project.

### Out of scope

- Feature development (tracked in future releases).
- Performance optimisation.

---
"@
}

function _BuildSuggestedAdditions {
    param([array]$Findings)
    if ($Findings.Count -eq 0) { return @() }
    return @($Findings | ForEach-Object {
        [pscustomobject]@{
            severity    = $_.severity
            category    = $_.category
            title       = $_.title
            roadmapItem = $_.roadmapItem
        }
    })
}

# ---------------------------------------------------------------------------
# Invoke-RepoEvaluation
# ---------------------------------------------------------------------------

<#
.SYNOPSIS
    Inspect a local repository and return a structured evaluation result.
.PARAMETER RepoName
    Display name of the repository (used in generated content).
.PARAMETER LocalPath
    Absolute path to the repository root on disk.
.PARAMETER HistoryRoot
    Directory where evaluation history JSON files are saved.
.OUTPUTS
    [pscustomobject] with:
      evaluationId        string
      repoName            string
      localPath           string
      repoType            string  'node' | 'dotnet' | 'python' | 'rust' | 'powershell' | 'other'
      evaluatedAt         string  ISO-8601 UTC
      hasExistingRoadmap  bool
      findings            array of finding objects
      findingCount        int
      criticalCount       int
      highCount           int
      suggestedRoadmapContent  string or $null  (populated when no roadmap exists)
      suggestedAdditions  array  (populated when roadmap exists)
#>
function Invoke-RepoEvaluation {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoName,

        [Parameter(Mandatory = $true)]
        [string]$LocalPath,

        [Parameter(Mandatory = $false)]
        [string]$HistoryRoot = ''
    )

    if (-not (Test-Path -LiteralPath $LocalPath -PathType Container)) {
        throw "Repository path not found: $LocalPath"
    }

    $evaluationId = [System.Guid]::NewGuid().ToString('n').Substring(0, 12)
    $evaluatedAt  = (Get-Date).ToUniversalTime().ToString('o')
    $repoType     = _DetectRepoType -LocalPath $LocalPath
    $findings     = [System.Collections.Generic.List[pscustomobject]]::new()

    # ------------------------------------------------------------------
    # Structural checks
    # ------------------------------------------------------------------

    # .gitignore
    if (-not (Test-Path -LiteralPath (Join-Path $LocalPath '.gitignore') -PathType Leaf)) {
        $null = $findings.Add((_MakeFinding `
            -FindingId   'missing-gitignore' `
            -Category    'hardening' `
            -Severity    'high' `
            -Title       'No .gitignore file' `
            -Description 'Without .gitignore, build artifacts, secrets, and OS-specific files risk being committed accidentally.' `
            -RoadmapItem 'Add .gitignore with patterns for build artifacts, IDE files, and secrets'))
    }

    # README.md
    $hasReadme = (Test-Path -LiteralPath (Join-Path $LocalPath 'README.md') -PathType Leaf) -or
                 (Test-Path -LiteralPath (Join-Path $LocalPath 'readme.md') -PathType Leaf)
    if (-not $hasReadme) {
        $null = $findings.Add((_MakeFinding `
            -FindingId   'missing-readme' `
            -Category    'documentation' `
            -Severity    'medium' `
            -Title       'No README.md file' `
            -Description 'A README is the first thing contributors and users see. Without one, the project purpose and setup steps are undiscoverable.' `
            -RoadmapItem 'Add README.md with project overview, prerequisites, setup steps, and usage examples'))
    }

    # LICENSE
    $hasLicense = (Test-Path -LiteralPath (Join-Path $LocalPath 'LICENSE')    -PathType Leaf) -or
                  (Test-Path -LiteralPath (Join-Path $LocalPath 'LICENSE.md') -PathType Leaf) -or
                  (Test-Path -LiteralPath (Join-Path $LocalPath 'LICENSE.txt') -PathType Leaf)
    if (-not $hasLicense) {
        $null = $findings.Add((_MakeFinding `
            -FindingId   'missing-license' `
            -Category    'compliance' `
            -Severity    'medium' `
            -Title       'No LICENSE file' `
            -Description 'Without an explicit licence, the code is legally "all rights reserved" and cannot be used, modified, or distributed by third parties.' `
            -RoadmapItem 'Add a LICENSE file (MIT, Apache-2.0, or appropriate licence for this project)'))
    }

    # CI/CD workflows
    if (-not (_HasCiWorkflows -LocalPath $LocalPath)) {
        $null = $findings.Add((_MakeFinding `
            -FindingId   'missing-ci' `
            -Category    'ci' `
            -Severity    'high' `
            -Title       'No CI/CD pipeline found' `
            -Description 'Without automated CI, regressions can go undetected. Pull requests and merges have no automated quality gate.' `
            -RoadmapItem 'Add a CI workflow (GitHub Actions / GitLab CI) that lints and tests on every pull request'))
    }

    # Tests
    if (-not (_HasTestFiles -LocalPath $LocalPath -RepoType $repoType)) {
        $null = $findings.Add((_MakeFinding `
            -FindingId   'missing-tests' `
            -Category    'testing' `
            -Severity    'high' `
            -Title       'No test files detected' `
            -Description 'No test directory or test files were found. Without tests, refactoring and new features carry unquantified regression risk.' `
            -RoadmapItem 'Add a test suite covering core functionality; target at least one test per public function or API endpoint'))
    }

    # CHANGELOG / release notes
    $hasChangelog = (Test-Path -LiteralPath (Join-Path $LocalPath 'CHANGELOG.md') -PathType Leaf) -or
                    (Test-Path -LiteralPath (Join-Path $LocalPath 'CHANGELOG')     -PathType Leaf)
    if (-not $hasChangelog) {
        $null = $findings.Add((_MakeFinding `
            -FindingId   'missing-changelog' `
            -Category    'documentation' `
            -Severity    'low' `
            -Title       'No CHANGELOG.md' `
            -Description 'A changelog lets users understand what changed between releases without reading every commit.' `
            -RoadmapItem 'Add CHANGELOG.md and keep it updated with every release using Keep a Changelog format'))
    }

    # Security policy
    $hasSecurityPolicy = (Test-Path -LiteralPath (Join-Path $LocalPath 'SECURITY.md') -PathType Leaf) -or
                         (Test-Path -LiteralPath (Join-Path $LocalPath '.github\SECURITY.md') -PathType Leaf)
    if (-not $hasSecurityPolicy) {
        $null = $findings.Add((_MakeFinding `
            -FindingId   'missing-security-policy' `
            -Category    'security' `
            -Severity    'medium' `
            -Title       'No SECURITY.md policy' `
            -Description 'Without a security policy, vulnerability reporters have no defined contact point or disclosure process.' `
            -RoadmapItem 'Add SECURITY.md describing how to report vulnerabilities and the expected response SLA'))
    }

    # Contributing guide
    $hasContributing = (Test-Path -LiteralPath (Join-Path $LocalPath 'CONTRIBUTING.md') -PathType Leaf) -or
                       (Test-Path -LiteralPath (Join-Path $LocalPath '.github\CONTRIBUTING.md') -PathType Leaf)
    if (-not $hasContributing) {
        $null = $findings.Add((_MakeFinding `
            -FindingId   'missing-contributing' `
            -Category    'documentation' `
            -Severity    'low' `
            -Title       'No CONTRIBUTING.md guide' `
            -Description 'A contributing guide reduces onboarding friction and sets expectations for PRs, code style, and commit messages.' `
            -RoadmapItem 'Add CONTRIBUTING.md covering branch naming, PR process, and coding standards'))
    }

    # Type-specific checks
    switch ($repoType) {
        'node' {
            $pkg = $null
            try {
                $pkgPath = Join-Path $LocalPath 'package.json'
                $pkg = ConvertFrom-Json (Get-Content -LiteralPath $pkgPath -Raw -ErrorAction Stop)
            } catch { }
            if ($null -ne $pkg -and -not ($pkg.PSObject.Properties.Name -contains 'scripts' -and $pkg.scripts.PSObject.Properties.Name -contains 'test')) {
                $null = $findings.Add((_MakeFinding `
                    -FindingId   'node-missing-test-script' `
                    -Category    'testing' `
                    -Severity    'medium' `
                    -Title       'package.json has no "test" script' `
                    -Description 'Without a standard test script, CI pipelines cannot run tests with npm test.' `
                    -RoadmapItem 'Add a "test" script to package.json and wire it to the test runner'))
            }
            if (-not (Test-Path -LiteralPath (Join-Path $LocalPath '.nvmrc') -PathType Leaf) -and
                -not (Test-Path -LiteralPath (Join-Path $LocalPath '.node-version') -PathType Leaf)) {
                $null = $findings.Add((_MakeFinding `
                    -FindingId   'node-no-engine-pin' `
                    -Category    'hardening' `
                    -Severity    'low' `
                    -Title       'Node.js version not pinned' `
                    -Description 'Without a .nvmrc or .node-version file, different developers and CI runners may use different Node.js versions, causing subtle incompatibilities.' `
                    -RoadmapItem 'Add .nvmrc (or .node-version) to pin the required Node.js version'))
            }
        }
        'dotnet' {
            if (-not (Test-Path -LiteralPath (Join-Path $LocalPath '.editorconfig') -PathType Leaf)) {
                $null = $findings.Add((_MakeFinding `
                    -FindingId   'dotnet-no-editorconfig' `
                    -Category    'hardening' `
                    -Severity    'low' `
                    -Title       'No .editorconfig file' `
                    -Description '.editorconfig enforces consistent indentation and encoding across editors and OS, preventing noisy diffs.' `
                    -RoadmapItem 'Add .editorconfig with consistent indent_style, end_of_line, and charset settings'))
            }
        }
        'powershell' {
            $strictModeFiles = @(Get-ChildItem -LiteralPath $LocalPath -Filter '*.ps1' -Recurse -Depth 4 -ErrorAction SilentlyContinue |
                Where-Object { (Get-Content -LiteralPath $_.FullName -Raw -ErrorAction SilentlyContinue) -notmatch 'Set-StrictMode' })
            if ($strictModeFiles.Count -gt 0) {
                $null = $findings.Add((_MakeFinding `
                    -FindingId   'ps-missing-strict-mode' `
                    -Category    'hardening' `
                    -Severity    'medium' `
                    -Title       "$($strictModeFiles.Count) PowerShell file(s) missing Set-StrictMode" `
                    -Description 'Set-StrictMode -Version Latest catches undefined variables and other common PowerShell errors that are otherwise silently ignored.' `
                    -RoadmapItem 'Add Set-StrictMode -Version Latest to all PowerShell scripts that are missing it'))
            }
        }
    }

    # ------------------------------------------------------------------
    # Roadmap presence
    # ------------------------------------------------------------------
    $roadmapPath = Join-Path $LocalPath 'ROADMAP.md'
    $hasExistingRoadmap = Test-Path -LiteralPath $roadmapPath -PathType Leaf

    $suggestedRoadmapContent = $null
    $suggestedAdditions = @()

    if (-not $hasExistingRoadmap) {
        $suggestedRoadmapContent = _BuildSuggestedRoadmap -RepoName $RepoName -RepoType $repoType -Findings @($findings)
    } else {
        $suggestedAdditions = @(_BuildSuggestedAdditions -Findings @($findings))
    }

    $criticalCount = @($findings | Where-Object { $_.severity -eq 'critical' }).Count
    $highCount     = @($findings | Where-Object { $_.severity -eq 'high' }).Count

    $result = [pscustomobject]@{
        evaluationId            = $evaluationId
        repoName                = $RepoName
        localPath               = $LocalPath
        repoType                = $repoType
        evaluatedAt             = $evaluatedAt
        hasExistingRoadmap      = $hasExistingRoadmap
        findings                = @($findings)
        findingCount            = $findings.Count
        criticalCount           = $criticalCount
        highCount               = $highCount
        suggestedRoadmapContent = $suggestedRoadmapContent
        suggestedAdditions      = $suggestedAdditions
    }

    # Persist history
    if (-not [string]::IsNullOrWhiteSpace($HistoryRoot)) {
        try {
            if (-not (Test-Path -LiteralPath $HistoryRoot)) {
                $null = New-Item -ItemType Directory -Path $HistoryRoot -Force
            }
            $safeRepo = $RepoName -replace '[^\w\-]', '_'
            $ts       = (Get-Date).ToString('yyyyMMdd-HHmmss')
            $histFile = Join-Path $HistoryRoot "$safeRepo-$ts-$evaluationId.json"
            $result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $histFile -Encoding UTF8
        } catch { }
    }

    return $result
}

# ---------------------------------------------------------------------------
# Get-RepoEvaluationHistory
# ---------------------------------------------------------------------------

<#
.SYNOPSIS
    Return past evaluation records from the history directory.
.PARAMETER HistoryRoot
    Directory containing evaluation JSON files.
.PARAMETER Limit
    Maximum number of records to return (newest first). Default 25.
.PARAMETER RepoName
    Optional filter: only return evaluations for this repo name.
#>
function Get-RepoEvaluationHistory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$HistoryRoot,

        [Parameter()]
        [int]$Limit = 25,

        [Parameter()]
        [string]$RepoName = ''
    )

    if (-not (Test-Path -LiteralPath $HistoryRoot -PathType Container)) {
        return @()
    }

    $files = @(Get-ChildItem -LiteralPath $HistoryRoot -Filter '*.json' -ErrorAction SilentlyContinue |
               Sort-Object LastWriteTime -Descending)

    $items = [System.Collections.Generic.List[pscustomobject]]::new()
    foreach ($f in $files) {
        if ($items.Count -ge $Limit) { break }
        try {
            $obj = ConvertFrom-Json (Get-Content -LiteralPath $f.FullName -Raw -ErrorAction Stop)
            if (-not [string]::IsNullOrWhiteSpace($RepoName) -and [string]$obj.repoName -ne $RepoName) { continue }
            $null = $items.Add($obj)
        } catch { }
    }

    return @($items)
}
