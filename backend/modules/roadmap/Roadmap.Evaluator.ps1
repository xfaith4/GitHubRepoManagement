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

function _HasAnyDirectory {
    param(
        [string]$LocalPath,
        [string[]]$RelativePaths
    )

    foreach ($relativePath in @($RelativePaths)) {
        if ([string]::IsNullOrWhiteSpace($relativePath)) { continue }
        if (Test-Path -LiteralPath (Join-Path $LocalPath $relativePath) -PathType Container) {
            return $true
        }
    }

    return $false
}

function _HasAnyFile {
    param(
        [string]$LocalPath,
        [string[]]$RelativePaths
    )

    foreach ($relativePath in @($RelativePaths)) {
        if ([string]::IsNullOrWhiteSpace($relativePath)) { continue }
        if (Test-Path -LiteralPath (Join-Path $LocalPath $relativePath) -PathType Leaf) {
            return $true
        }
    }

    return $false
}

function _ReadFileText {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return ''
    }

    try {
        return [string](Get-Content -LiteralPath $Path -Raw -Encoding UTF8 -ErrorAction Stop)
    } catch {
        return ''
    }
}

function _GetReadmeAnalysis {
    param([string]$LocalPath)

    $candidatePaths = @(
        (Join-Path $LocalPath 'README.md')
        (Join-Path $LocalPath 'readme.md')
    )

    $readmePath = $null
    foreach ($candidatePath in $candidatePaths) {
        if (Test-Path -LiteralPath $candidatePath -PathType Leaf) {
            $readmePath = $candidatePath
            break
        }
    }

    $content = if ($null -ne $readmePath) { _ReadFileText -Path $readmePath } else { '' }
    $headings = [System.Collections.Generic.List[string]]::new()
    if (-not [string]::IsNullOrWhiteSpace($content)) {
        foreach ($match in [regex]::Matches($content, '(?im)^#{1,6}\s+(.+?)\s*$')) {
            $null = $headings.Add($match.Groups[1].Value.ToLowerInvariant())
        }
    }

    $hasSetupSection = @($headings | Where-Object { $_ -match '\b(install|installation|setup|get started|quickstart|quick start|prerequisites)\b' }).Count -gt 0
    $hasUsageSection = @($headings | Where-Object { $_ -match '\b(usage|run|running|how to use|workflow|commands?)\b' }).Count -gt 0
    $hasArchitectureSection = @($headings | Where-Object { $_ -match '\b(architecture|design|system|components?|api|reference|structure)\b' }).Count -gt 0

    return [pscustomobject]@{
        hasReadme              = $null -ne $readmePath
        readmePath             = $readmePath
        content                = $content
        hasSetupSection        = $hasSetupSection
        hasUsageSection        = $hasUsageSection
        hasArchitectureSection = $hasArchitectureSection
    }
}

function _HasSecurityScanningWorkflow {
    param([string]$LocalPath)

    $workflowRoot = Join-Path $LocalPath '.github\workflows'
    if (-not (Test-Path -LiteralPath $workflowRoot -PathType Container)) {
        return $false
    }

    $workflowFiles = @(
        Get-ChildItem -LiteralPath $workflowRoot -Filter '*.yml' -ErrorAction SilentlyContinue
        Get-ChildItem -LiteralPath $workflowRoot -Filter '*.yaml' -ErrorAction SilentlyContinue
    )

    foreach ($workflowFile in @($workflowFiles)) {
        $name = $workflowFile.Name.ToLowerInvariant()
        if ($name -match 'codeql|semgrep|security|sast|gitleaks|dependency-review') {
            return $true
        }

        $raw = _ReadFileText -Path $workflowFile.FullName
        if ($raw -match '(?i)codeql|semgrep|gitleaks|dependency-review-action|security-events') {
            return $true
        }
    }

    return $false
}

function _GetPackageJsonObject {
    param([string]$LocalPath)

    $packageJsonPath = Join-Path $LocalPath 'package.json'
    if (-not (Test-Path -LiteralPath $packageJsonPath -PathType Leaf)) {
        return $null
    }

    try {
        return ConvertFrom-Json (_ReadFileText -Path $packageJsonPath)
    } catch {
        return $null
    }
}

function _GetRepoSignals {
    param(
        [string]$LocalPath,
        [string]$RepoType
    )

    $hasFrontend = _HasAnyDirectory -LocalPath $LocalPath -RelativePaths @('frontend', 'ui', 'web', 'client')
    $hasBackend = _HasAnyDirectory -LocalPath $LocalPath -RelativePaths @('backend', 'api', 'server', 'services')
    $hasCli = _HasAnyDirectory -LocalPath $LocalPath -RelativePaths @('cli', 'bin', 'cmd')
    $hasExamples = _HasAnyDirectory -LocalPath $LocalPath -RelativePaths @('examples', 'example', 'samples', 'sample', 'demo', 'demos')
    $hasDocsDir = _HasAnyDirectory -LocalPath $LocalPath -RelativePaths @('docs')
    $hasProductDocs = (
        (_HasAnyDirectory -LocalPath $LocalPath -RelativePaths @('docs\product', 'docs\reference', 'docs\architecture')) -or
        (_HasAnyFile -LocalPath $LocalPath -RelativePaths @('docs\index.md'))
    )
    $hasLaunchScript = _HasAnyFile -LocalPath $LocalPath -RelativePaths @('start.ps1', 'start.sh', 'start.bat', 'run.ps1', 'run.sh', 'run.bat')
    $hasDependabot = _HasAnyFile -LocalPath $LocalPath -RelativePaths @('.github\dependabot.yml', '.github\dependabot.yaml')
    $hasSecurityScanning = _HasSecurityScanningWorkflow -LocalPath $LocalPath
    $sourceFileCount = @(
        Get-ChildItem -LiteralPath $LocalPath -File -Recurse -Depth 4 -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -in @('.ps1', '.psm1', '.psd1', '.ts', '.tsx', '.js', '.jsx', '.py', '.cs', '.rs', '.go') }
    ).Count

    if (-not $hasBackend -and $RepoType -in @('powershell', 'python', 'dotnet')) {
        $hasBackend = $sourceFileCount -gt 0
    }

    return [pscustomobject]@{
        hasFrontend         = $hasFrontend
        hasBackend          = $hasBackend
        hasCli              = $hasCli
        hasExamples         = $hasExamples
        hasDocsDir          = $hasDocsDir
        hasProductDocs      = $hasProductDocs
        hasLaunchScript     = $hasLaunchScript
        hasDependabot       = $hasDependabot
        hasSecurityScanning = $hasSecurityScanning
        sourceFileCount     = $sourceFileCount
    }
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

function _GetFindingSeverityRank {
    param([string]$Severity)

    switch ($Severity) {
        'critical' { return 0 }
        'high'     { return 1 }
        'medium'   { return 2 }
        default    { return 3 }
    }
}

function _SortFindings {
    param([array]$Findings)

    if ($null -eq $Findings) { return @() }

    return @(
        $Findings |
            Sort-Object `
                @{ Expression = { _GetFindingSeverityRank -Severity ([string]$_.severity) } }, `
                @{ Expression = { [string]$_.category } }, `
                @{ Expression = { [string]$_.title } }
    )
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

    $sortedFindings = @(_SortFindings -Findings $Findings)
    $foundationalFindings = @($sortedFindings | Where-Object { $_.category -in @('hardening', 'ci', 'testing', 'security', 'compliance') })
    $experienceFindings = @($sortedFindings | Where-Object { $_.category -in @('documentation', 'feature', 'user-value') })
    $modernizationFindings = @($sortedFindings | Where-Object { $_.category -eq 'modernization' })

    $sections = [System.Collections.Generic.List[string]]::new()

    if ($foundationalFindings.Count -gt 0) {
        $null = $sections.Add(@"
## Release 1.0 — Foundational Hardening

**Goal:** Establish baseline quality, safety, and delivery practices so the repository is maintainable and safe to evolve.

### Product outcomes

- Core repo hygiene, testing, and security expectations are in place.
- Contributors can make changes without guessing about release discipline or safety checks.
- The project has a stable base for follow-on value delivery work.

### Engineering milestones

$(@($foundationalFindings | ForEach-Object { "- [ ] $($_.roadmapItem)" }) -join "`n")

### Acceptance criteria

- Foundational hardening items above are implemented and validated.
- CI, tests, and security expectations are documented or automated where applicable.
- The repo can be changed with lower regression and operational risk.

### Out of scope

- Larger user-facing workflow expansion.
- New product surfaces that depend on unresolved hardening work.
"@)
    }

    if ($experienceFindings.Count -gt 0) {
        $version = if ($foundationalFindings.Count -gt 0) { '1.1' } else { '1.0' }
        $null = $sections.Add(@"
## Release $version — Workflow Clarity and User Value

**Goal:** Turn the current codebase into a clearer operator or user experience with explicit workflows, value framing, and visible next-step opportunities.

### Product outcomes

- The repo explains what it does, how it is used, and why it matters.
- Missing roadmap work is not limited to hardening; it also captures value delivery and feature opportunities.
- New users can discover the primary workflow without reverse-engineering the source tree.

### Engineering milestones

$(@($experienceFindings | ForEach-Object { "- [ ] $($_.roadmapItem)" }) -join "`n")

### Acceptance criteria

- Documentation and user-facing workflow gaps are represented as concrete roadmap items.
- At least one item improves the repo's operator or user-visible value, not just internal hygiene.
- The roadmap reflects the highest-leverage experience improvements visible from the current repo state.

### Out of scope

- Broad redesign not grounded in the existing codebase.
- Feature ideas with no evidence in current repo capabilities.
"@)
    }

    if ($modernizationFindings.Count -gt 0) {
        $version = if ($foundationalFindings.Count -gt 0 -and $experienceFindings.Count -gt 0) {
            '1.2'
        } elseif ($foundationalFindings.Count -gt 0 -or $experienceFindings.Count -gt 0) {
            '1.1'
        } else {
            '1.0'
        }
        $null = $sections.Add(@"
## Release $version — Modernization and Operability

**Goal:** Reduce tooling drift and improve maintainability by modernizing repo-specific development and validation workflows.

### Product outcomes

- Core tooling expectations are explicit and repeatable across developer machines and CI.
- The repo is easier to maintain because the build or runtime stack is pinned and modernized where needed.
- Future roadmap work can build on more predictable development ergonomics.

### Engineering milestones

$(@($modernizationFindings | ForEach-Object { "- [ ] $($_.roadmapItem)" }) -join "`n")

### Acceptance criteria

- Modernization items are captured as concrete tasks rather than implied maintenance debt.
- Toolchain or packaging drift called out by the evaluator has a remediation path in the roadmap.
- The roadmap separates modernization work from feature delivery and baseline hardening.

### Out of scope

- Rewrites with no operational need.
- Framework churn that does not reduce real maintenance risk.
"@)
    }

    if ($sections.Count -eq 0) {
        $null = $sections.Add(@"
## Release 1.0 — Roadmap Establishment

**Goal:** Capture the next concrete work so the repo can be improved intentionally instead of ad hoc.

### Product outcomes

- The repository has an explicit roadmap.
- Future work can be prioritized and validated.

### Engineering milestones

- [ ] Review the current repository and capture the next concrete hardening or value-delivery tasks.

### Acceptance criteria

- ROADMAP.md exists and contains at least one actionable release with checklist items.

### Out of scope

- Work that is not yet grounded in the current repository state.
"@)
    }

    return @"
# $RepoName Roadmap

## Overview

This roadmap captures the planned hardening, modernization, and value-delivery work for **$RepoName** ($typeLabel project).

---

$($sections -join "`n`n---`n`n")
"@
}

function _BuildSuggestedAdditions {
    param([array]$Findings)
    if ($Findings.Count -eq 0) { return @() }
    return @(_SortFindings -Findings $Findings | ForEach-Object {
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
    $readmeAnalysis = _GetReadmeAnalysis -LocalPath $LocalPath
    $hasReadme = [bool]$readmeAnalysis.hasReadme
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

    if ($hasReadme -and (-not $readmeAnalysis.hasSetupSection -or -not $readmeAnalysis.hasUsageSection)) {
        $null = $findings.Add((_MakeFinding `
            -FindingId   'readme-missing-setup-or-usage' `
            -Category    'documentation' `
            -Severity    'medium' `
            -Title       'README is missing setup or usage guidance' `
            -Description 'A README was found, but it does not clearly expose both setup/install guidance and day-one usage or workflow guidance. Operators will have to infer the happy path from the source tree.' `
            -RoadmapItem 'Expand README with setup, usage, and primary workflow examples so a new operator can succeed without reading the source first'))
    }

    $repoSignals = _GetRepoSignals -LocalPath $LocalPath -RepoType $repoType

    if ($hasReadme -and -not $readmeAnalysis.hasArchitectureSection -and ($repoSignals.hasBackend -or $repoSignals.hasFrontend -or $repoSignals.sourceFileCount -ge 15)) {
        $null = $findings.Add((_MakeFinding `
            -FindingId   'missing-architecture-or-capability-map' `
            -Category    'documentation' `
            -Severity    'low' `
            -Title       'No architecture or capability map detected in docs' `
            -Description 'The repo appears substantial enough to need a lightweight architecture or capability overview, but the README headings do not expose one and no obvious reference docs were detected.' `
            -RoadmapItem 'Add architecture or capability-reference documentation that explains the main components and their operator-facing responsibilities'))
    }

    if (-not $repoSignals.hasDependabot) {
        $null = $findings.Add((_MakeFinding `
            -FindingId   'missing-dependabot' `
            -Category    'security' `
            -Severity    'medium' `
            -Title       'No dependency update automation detected' `
            -Description 'The repository does not appear to configure Dependabot. Dependency drift and vulnerability remediation will rely on manual checks instead of a repeatable update cadence.' `
            -RoadmapItem 'Add Dependabot configuration for the repo''s package ecosystems and review dependency updates on a regular cadence'))
    }

    if (-not $repoSignals.hasSecurityScanning) {
        $null = $findings.Add((_MakeFinding `
            -FindingId   'missing-security-scanning' `
            -Category    'security' `
            -Severity    'low' `
            -Title       'No security scanning workflow detected' `
            -Description 'No CodeQL, Semgrep, dependency-review, or similar security scanning workflow was detected under .github/workflows. Security posture depends on manual review only.' `
            -RoadmapItem 'Add a security scanning workflow (for example CodeQL or dependency review) and make it part of the normal PR signal set'))
    }

    # Type-specific checks
    switch ($repoType) {
        'node' {
            $pkg = _GetPackageJsonObject -LocalPath $LocalPath
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

            $hasLintScript = $null -ne $pkg -and $pkg.PSObject.Properties.Name -contains 'scripts' -and $pkg.scripts.PSObject.Properties.Name -contains 'lint'
            $hasTypecheckScript = $null -ne $pkg -and $pkg.PSObject.Properties.Name -contains 'scripts' -and $pkg.scripts.PSObject.Properties.Name -contains 'typecheck'
            if (-not $hasLintScript -or -not $hasTypecheckScript) {
                $missingScripts = [System.Collections.Generic.List[string]]::new()
                if (-not $hasLintScript) { $null = $missingScripts.Add('lint') }
                if (-not $hasTypecheckScript) { $null = $missingScripts.Add('typecheck') }
                $null = $findings.Add((_MakeFinding `
                    -FindingId   'node-missing-quality-scripts' `
                    -Category    'modernization' `
                    -Severity    'medium' `
                    -Title       ('package.json missing quality scripts: ' + ($missingScripts -join ', ')) `
                    -Description 'The Node.js toolchain is not exposing the usual quality-gate scripts for linting and/or type checking. This makes local validation and CI integration less predictable.' `
                    -RoadmapItem ('Add package.json scripts for ' + ($missingScripts -join ' and ') + ' and wire them into the standard local and CI validation flow')))
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
            if (-not (Test-Path -LiteralPath (Join-Path $LocalPath 'global.json') -PathType Leaf)) {
                $null = $findings.Add((_MakeFinding `
                    -FindingId   'dotnet-missing-global-json' `
                    -Category    'modernization' `
                    -Severity    'medium' `
                    -Title       'No global.json SDK pin detected' `
                    -Description 'Without global.json, local machines and CI may build the repo with different .NET SDK versions, producing subtle restore or analyzer drift.' `
                    -RoadmapItem 'Add global.json to pin the supported .NET SDK version for local development and CI'))
            }
        }
        'python' {
            if (-not (Test-Path -LiteralPath (Join-Path $LocalPath 'pyproject.toml') -PathType Leaf)) {
                $null = $findings.Add((_MakeFinding `
                    -FindingId   'python-missing-pyproject' `
                    -Category    'modernization' `
                    -Severity    'medium' `
                    -Title       'No pyproject.toml detected' `
                    -Description 'Python packaging and tooling configuration appear to rely on older scattered files only. A pyproject.toml consolidates build, lint, and test tool configuration into a standard entry point.' `
                    -RoadmapItem 'Add pyproject.toml and move Python build or tooling configuration toward the modern standard layout'))
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
            if (-not (_HasAnyFile -LocalPath $LocalPath -RelativePaths @('PSScriptAnalyzerSettings.psd1', '.config\PSScriptAnalyzerSettings.psd1'))) {
                $null = $findings.Add((_MakeFinding `
                    -FindingId   'powershell-missing-analyzer-settings' `
                    -Category    'modernization' `
                    -Severity    'medium' `
                    -Title       'No PSScriptAnalyzer settings detected' `
                    -Description 'The repo contains PowerShell code, but no explicit PSScriptAnalyzer settings file was detected. Linting and style enforcement are likely to drift between machines.' `
                    -RoadmapItem 'Add PSScriptAnalyzerSettings.psd1 and wire it into the PowerShell validation path'))
            }
        }
        'rust' {
            if (-not (_HasAnyFile -LocalPath $LocalPath -RelativePaths @('rust-toolchain.toml', 'rust-toolchain'))) {
                $null = $findings.Add((_MakeFinding `
                    -FindingId   'rust-missing-toolchain-pin' `
                    -Category    'modernization' `
                    -Severity    'medium' `
                    -Title       'No rust toolchain pin detected' `
                    -Description 'Without a rust-toolchain file, developers and CI may compile against different compiler versions, causing inconsistent warnings or feature support.' `
                    -RoadmapItem 'Add rust-toolchain.toml to pin the Rust compiler channel used by the project'))
            }
        }
    }

    if (-not $repoSignals.hasExamples -and -not $repoSignals.hasLaunchScript) {
        $null = $findings.Add((_MakeFinding `
            -FindingId   'missing-guided-demo-path' `
            -Category    'user-value' `
            -Severity    'medium' `
            -Title       'No first-run example or guided demo path detected' `
            -Description 'No examples, samples, demos, or obvious start script were detected. Even when the code is useful, a new user has no low-friction way to experience the primary workflow.' `
            -RoadmapItem 'Add a first-run example, demo, or one-command launch path that demonstrates the primary workflow end to end'))
    }

    if ($repoSignals.hasBackend -and -not $repoSignals.hasFrontend -and -not $repoSignals.hasCli) {
        $null = $findings.Add((_MakeFinding `
            -FindingId   'backend-without-operator-surface' `
            -Category    'feature' `
            -Severity    'low' `
            -Title       'Backend or service capability appears to lack an operator-facing surface' `
            -Description 'Backend or service-oriented directories were detected, but no obvious frontend or CLI surface was found. The repo may benefit from packaging its highest-value capability into a more accessible workflow.' `
            -RoadmapItem 'Add a thin operator-facing surface (CLI, report workflow, or small UI) for the highest-value backend capability already present in the repo'))
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

    $sortedFindings = @(_SortFindings -Findings @($findings))
    $criticalCount = @($sortedFindings | Where-Object { $_.severity -eq 'critical' }).Count
    $highCount     = @($sortedFindings | Where-Object { $_.severity -eq 'high' }).Count

    $result = [pscustomobject]@{
        evaluationId            = $evaluationId
        repoName                = $RepoName
        localPath               = $LocalPath
        repoType                = $repoType
        evaluatedAt             = $evaluatedAt
        hasExistingRoadmap      = $hasExistingRoadmap
        findings                = @($sortedFindings)
        findingCount            = $sortedFindings.Count
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
