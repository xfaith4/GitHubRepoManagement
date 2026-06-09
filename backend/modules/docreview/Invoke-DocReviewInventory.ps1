### BEGIN FILE: Invoke-DocReviewInventory.ps1

[CmdletBinding()]
param(
    [Parameter()]
    [string]$OutDir = (Join-Path $PSScriptRoot '..\output\inventory'),

    [Parameter()]
    [string]$RootPath = 'G:\Development\20_Staging',

    [Parameter()]
    [int]$MaxDepth = 3
)

Set-StrictMode -Version Latest

$ErrorActionPreference = 'Stop'
### BEGIN: Debug Helpers
function Write-Step {
    param(
        [string]$Message,
        [string]$Color = 'DarkCyan'
    )
    Write-Host "[STEP] $Message" -ForegroundColor $Color
}

function Write-Value {
    param(
        [string]$Name,
        $Value,
        [string]$Color = 'DarkGray'
    )

    $display = if ($null -eq $Value) { '<null>' } else { [string]$Value }
    Write-Host ("[INFO] {0} = {1}" -f $Name, $display) -ForegroundColor $Color
}

function Get-SafeCount {
    param(
        $InputObject
    )
    return @($InputObject).Count
}
### END: Debug Helpers

function Resolve-FullPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    return (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path

}

function Get-RelativePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$BasePath,

        [Parameter(Mandatory = $true)]
        [string]$TargetPath
    )

    $resolvedBasePath = Resolve-FullPath -Path $BasePath
    $resolvedTargetPath = Resolve-FullPath -Path $TargetPath
    Write-Step "Resolving relative path"
    Write-Value -Name 'BasePath' -Value $resolvedBasePath
    Write-Value -Name 'TargetPath' -Value $resolvedTargetPath

    $baseUri = [System.Uri]($resolvedBasePath.TrimEnd('\') + '\')
    $targetUri = [System.Uri]$resolvedTargetPath
    $relative = $baseUri.MakeRelativeUri($targetUri).ToString()

    return [System.Uri]::UnescapeDataString($relative).Replace('/', '\')
}

function Test-IsGitRepo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    return (Test-Path -LiteralPath (Join-Path -Path $Path -ChildPath '.git'))
}

function Get-GitFreshness {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoPath
    )

    $result = @{
        LastCommitDate     = $null
        CurrentBranch      = $null
        UncommittedChanges = 0
    }

    try {
        $raw = & git -C $RepoPath log -1 --format='%ci' 2>$null
        if ($LASTEXITCODE -eq 0 -and $raw) {
            $result.LastCommitDate = $raw.Trim()
        }
    } catch { }

    try {
        $branch = & git -C $RepoPath branch --show-current 2>$null
        if ($LASTEXITCODE -eq 0) {
            $result.CurrentBranch = $branch.Trim()
        }
    } catch { }

    try {
        $statusLines = @(& git -C $RepoPath status --porcelain 2>$null)
        if ($LASTEXITCODE -eq 0) {
            $result.UncommittedChanges = $statusLines.Count
        }
    } catch { }

    return $result
}

function Get-DocQualityHints {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$RepoFacts,

        [Parameter(Mandatory = $true)]
        [string]$RepoPath,

        [Parameter(Mandatory = $true)]
        [string[]]$RelativeMdFiles
    )

    $hints = New-Object System.Collections.Generic.List[string]

    # No README
    if (-not $RepoFacts.hasReadme) {
        $hints.Add('no-readme')
    }

    # Very large README (> 500 lines)
    if ($RepoFacts.hasReadme) {
        $readmeRelPath = $RelativeMdFiles | Where-Object { $_ -match '(^|\\)README\.md$' } | Select-Object -First 1
        if ($readmeRelPath) {
            $readmeFullPath = Join-Path -Path $RepoPath -ChildPath $readmeRelPath
            if (Test-Path -LiteralPath $readmeFullPath) {
                $lineCount = (Get-Content -LiteralPath $readmeFullPath -ErrorAction SilentlyContinue | Measure-Object -Line).Lines
                if ($lineCount -gt 500) {
                    $hints.Add('large-readme')
                }
            }
        }
    }

    # No docs folder but many MD files
    if (-not $RepoFacts.hasDocsFolder -and $RepoFacts.markdownFileCount -gt 5) {
        $hints.Add('no-docs-folder-many-md')
    }

    # MD files with vague names
    $vaguePattern = '(^|\\)(notes?|draft|drafts?|temp|tmp|untitled|doc\d*|page\d*|new[_\-]?file|readme[\-_]old|copy[\-_]of)\.md$'
    $vagueFiles = @($RelativeMdFiles | Where-Object { $_ -imatch $vaguePattern })
    if ($vagueFiles.Count -gt 0) {
        $hints.Add('vague-md-names')
    }

    # MD filenames that are themselves TODO/TBD/WIP
    $wipNames = @($RelativeMdFiles | Where-Object { $_ -imatch '(^|\\)(todo|tbd|wip)[\._\-]' })
    if ($wipNames.Count -gt 0) {
        $hints.Add('wip-filenames')
    }

    # Content scan: risk markers — TODO, TBD, WIP, "coming soon"
    $riskPattern = '\b(TODO|TBD|WIP)\b|coming\s+soon'
    $foundRisk = $false
    foreach ($relPath in $RelativeMdFiles) {
        $fullPath = Join-Path -Path $RepoPath -ChildPath $relPath
        if (Test-Path -LiteralPath $fullPath) {
            if (Select-String -LiteralPath $fullPath -Pattern $riskPattern -Quiet -ErrorAction SilentlyContinue) {
                $foundRisk = $true
                break
            }
        }
    }
    if ($foundRisk) {
        $hints.Add('contains-risk-markers')
    }

    # Duplicate setup-oriented docs (3 or more setup-pattern files suggests overlap)
    $setupDocs = @($RelativeMdFiles | Where-Object { $_ -imatch 'setup|install|getting-started|get-started|quickstart' })
    if ($setupDocs.Count -ge 3) {
        $hints.Add('duplicate-setup-docs')
    }

    return @($hints)
}

function Get-DocCategory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RelativePath
    )

    $p = $RelativePath.ToLowerInvariant()

    if ($p -match '(^|\\)readme\.md$') { return 'readme' }
    if ($p -match '(^|\\)contributing\.md$') { return 'contributing' }
    if ($p -match '(^|\\)changelog\.md$') { return 'changelog' }
    if ($p -match '(^|\\)roadmap\.md$') { return 'roadmap' }
    if ($p -match 'runbook|playbook') { return 'runbook' }
    if ($p -match 'troubleshoot|troubleshooting|faq') { return 'troubleshooting' }
    if ($p -match 'setup|install|get-started|getting-started|quickstart') { return 'setup' }
    if ($p -match 'arch|architecture|design') { return 'architecture' }
    if ($p -match 'api|reference') { return 'reference' }
    if ($p -match '(^|\\)docs\\index\.md$') { return 'docs-index' }

    return 'general'
}

function Get-PriorityBand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [int]$Score
    )

    if ($Score -ge 40) { return 'High' }
    if ($Score -ge 20) { return 'Medium' }
    return 'Low'
}

function Get-RepoPriorityScore {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$RepoFacts
    )

    $score = 0

    if ($RepoFacts.hasReadme) { $score += 20 } else { $score -= 15 }
    if ($RepoFacts.hasDocsFolder) { $score += 15 }
    if ($RepoFacts.hasContributing) { $score += 10 }
    if ($RepoFacts.hasDocsIndex) { $score += 10 }

    foreach ($category in @('architecture', 'setup', 'troubleshooting', 'runbook', 'reference')) {
        if ($RepoFacts.activeCategories -contains $category) {
            $score += 10
        }
    }

    if ($RepoFacts.activeDocCount -ge 3 -and $RepoFacts.activeDocCount -le 20) {
        $score += 10
    }
    elseif ($RepoFacts.activeDocCount -gt 20) {
        $score += 5
    }

    return $score
}

function Get-ImmediateChildDirectories {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    Get-ChildItem -LiteralPath $Path -Directory -Force -ErrorAction Stop
}

function Get-RelativeDepth {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RelativePath
    )

    $normalized = $RelativePath.Trim('\')
    if ([string]::IsNullOrWhiteSpace($normalized)) {
        return 0
    }

    return ($normalized -split '[\\/]').Count - 1
}

function Test-IsIncludedMarkdownFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FullPath
    )

    $excludePattern = '\\(node_modules|bin|obj|dist|build|coverage|lib|vendor|third_party|\.venv|\.pytest_cache|\.git)(\\|$)'
    return ($FullPath -notmatch $excludePattern)
}

function Get-DocClass {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RelativePath
    )

    $p = $RelativePath.ToLowerInvariant()

    if ($p -match '(^|\\)(archive|_archive|deprecated|legacy|old[-_]docs?)(\\|$)') { return 'Archive' }
    if ($p -match '(^|\\)(examples?|samples?)(\\|$)') { return 'Generated' }
    if ($p -match 'runbook|playbook|incident|on[-_]?call') { return 'Operational' }
    if ($p -match '(^|\\)(api|reference)(\\|$)') { return 'Reference' }
    if ($p -match 'api[-_]reference|api[-_]docs?') { return 'Reference' }

    return 'Active'
}

function Get-ReviewMode {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$RepoFacts,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$DocQualityHints
    )

    if ($RepoFacts.activeDocCount -eq 0) {
        return 'README-only'
    }

    $archiveHeavy = $RepoFacts.archiveDocCount -gt $RepoFacts.activeDocCount
    $hasClutter   = ($DocQualityHints -contains 'vague-md-names') -or ($DocQualityHints -contains 'wip-filenames')

    if ($archiveHeavy -or ($hasClutter -and $RepoFacts.archiveDocCount -gt 3)) {
        return 'Archive cleanup first'
    }

    if (-not $RepoFacts.hasDocsFolder -and $RepoFacts.activeDocCount -gt 10) {
        return 'Needs taxonomy before rewrite'
    }

    if ($RepoFacts.activeDocCount -ge 20 -or ($RepoFacts.hasDocsFolder -and $RepoFacts.activeDocCount -ge 8)) {
        return 'Full-doc pass'
    }

    if ($RepoFacts.activeDocCount -ge 3) {
        return 'Core-docs batch'
    }

    return 'README-only'
}

$resolvedRootPath = Resolve-FullPath -Path $RootPath

if (-not (Test-Path -LiteralPath $resolvedRootPath -PathType Container)) {
    throw "RootPath is not a directory: $($resolvedRootPath)"
}

$null = New-Item -ItemType Directory -Path $OutDir -Force -ErrorAction Stop
$resolvedOutDir = Resolve-FullPath -Path $OutDir

$repoResults = New-Object System.Collections.Generic.List[object]

$candidateDirs = Get-ImmediateChildDirectories -Path $resolvedRootPath

foreach ($dir in $candidateDirs) {
    $repoPath = $dir.FullName
    $repoName = $dir.Name

    if (-not (Test-IsGitRepo -Path $repoPath)) {
        continue
    }

    Write-Host "Scanning repo: $($repoName)" -ForegroundColor Cyan
    $mdFiles = @()
    $mdFiles = @(Get-ChildItem -LiteralPath $repoPath -Recurse -File -Filter '*.md' -ErrorAction SilentlyContinue |
            Where-Object {
                Test-IsIncludedMarkdownFile -FullPath $_.FullName
            })

    if ($mdFiles.Count -eq 0) {
        continue
    }

    $relativeMdFiles = @(
        foreach ($file in $mdFiles) {
            $relativePath = Get-RelativePath -BasePath $repoPath -TargetPath $file.FullName
            $relativeDepth = Get-RelativeDepth -RelativePath $relativePath

            if ($relativeDepth -le $MaxDepth) {
                $relativePath
            }
        }
    )

    if ($relativeMdFiles.Count -eq 0) {
        continue
    }

    [object[]]$classifiedFiles = @(
        foreach ($relPath in $relativeMdFiles) {
            [pscustomobject]@{
                Path     = $relPath
                DocClass = Get-DocClass -RelativePath $relPath
            }
        }
    )

    $activeFiles    = @($classifiedFiles | Where-Object { $_.DocClass -eq 'Active' })
    $archiveFiles   = @($classifiedFiles | Where-Object { $_.DocClass -eq 'Archive' })
    $generatedFiles = @($classifiedFiles | Where-Object { $_.DocClass -eq 'Generated' })

    $categories = @(
        foreach ($relPath in $relativeMdFiles) {
            Get-DocCategory -RelativePath $relPath
        }
    )

    $uniqueCategories = @($categories | Sort-Object -Unique)

    $activeRelPaths = @($activeFiles | Select-Object -ExpandProperty Path)
    $activeCategories = @(
        if ($activeRelPaths.Count -gt 0) {
            foreach ($relPath in $activeRelPaths) {
                Get-DocCategory -RelativePath $relPath
            }
        }
    ) | Sort-Object -Unique

    $repoFacts = @{
        hasReadme         = (@($relativeMdFiles | Where-Object { $_ -match '(^|\\)README\.md$' })).Count -gt 0
        hasDocsFolder     = Test-Path -LiteralPath (Join-Path -Path $repoPath -ChildPath 'docs') -PathType Container
        hasContributing   = (@($relativeMdFiles | Where-Object { $_ -match '(^|\\)CONTRIBUTING\.md$' })).Count -gt 0
        hasDocsIndex      = (@($relativeMdFiles | Where-Object { $_ -match '(^|\\)docs\\index\.md$' })).Count -gt 0
        markdownFileCount = $relativeMdFiles.Count
        activeDocCount    = $activeFiles.Count
        archiveDocCount   = $archiveFiles.Count
        generatedDocCount = $generatedFiles.Count
        docCategories     = @($uniqueCategories)
        activeCategories  = @($activeCategories)
    }

    $priorityScore = Get-RepoPriorityScore -RepoFacts $repoFacts
    $priorityBand = Get-PriorityBand -Score $priorityScore

    $gitFreshness    = Get-GitFreshness -RepoPath $repoPath
    $docQualityHints = @(Get-DocQualityHints -RepoFacts $repoFacts -RepoPath $repoPath -RelativeMdFiles $relativeMdFiles)
    $reviewMode      = Get-ReviewMode -RepoFacts $repoFacts -DocQualityHints $docQualityHints

    $keyDocs = @(
        $classifiedFiles |
            Where-Object {
                $_.DocClass -notin @('Archive', 'Generated') -and (
                    $_.Path -match '(^|\\)README\.md$' -or
                    $_.Path -match '(^|\\)CONTRIBUTING\.md$' -or
                    $_.Path -match '(^|\\)docs\\index\.md$' -or
                    $_.Path -match 'architecture|design|setup|install|get-started|quickstart|troubleshoot|faq|runbook|playbook|api|reference'
                )
            } |
            Select-Object -ExpandProperty Path |
            Sort-Object -Unique
    )

    $repoResults.Add([pscustomobject]@{
            RepoName              = $repoName
            RepoPath              = $repoPath
            IsGitRepo             = $true
            MarkdownFiles         = @($relativeMdFiles | Sort-Object -Unique)
            MarkdownFileCount     = $relativeMdFiles.Count
            ActiveDocCount        = $repoFacts.activeDocCount
            ArchiveDocCount       = $repoFacts.archiveDocCount
            GeneratedDocCount     = $repoFacts.generatedDocCount
            HasReadme             = $repoFacts.hasReadme
            HasDocsFolder         = $repoFacts.hasDocsFolder
            HasContributing       = $repoFacts.hasContributing
            HasDocsIndex          = $repoFacts.hasDocsIndex
            DocCategories         = @($uniqueCategories)
            PriorityScore         = $priorityScore
            PriorityBand          = $priorityBand
            ReviewMode            = $reviewMode
            GitLastCommitDate     = $gitFreshness.LastCommitDate
            GitBranch             = $gitFreshness.CurrentBranch
            GitUncommittedChanges = $gitFreshness.UncommittedChanges
            DocQualityHints       = @($docQualityHints)
            KeyDocs               = @($keyDocs)
            ClassifiedFiles       = @($classifiedFiles | Sort-Object -Property Path)
        })
}

$sortedRepoResults = @(
    $repoResults |
        Sort-Object -Property `
        @{ Expression = 'PriorityScore'; Descending = $true }, `
        @{ Expression = 'MarkdownFileCount'; Descending = $true }, `
        @{ Expression = 'RepoName'; Descending = $false }
)

$jsonPath = Join-Path -Path $resolvedOutDir -ChildPath 'doc-review-manifest.json'
$csvPath = Join-Path -Path $resolvedOutDir -ChildPath 'doc-review-summary.csv'
$reportPath = Join-Path -Path $resolvedOutDir -ChildPath 'doc-review-report.md'

$sortedRepoResults |
    ConvertTo-Json -Depth 8 |
    Set-Content -LiteralPath $jsonPath -Encoding UTF8

$sortedRepoResults |
    Select-Object `
        RepoName,
    RepoPath,
    MarkdownFileCount,
    ActiveDocCount,
    ArchiveDocCount,
    GeneratedDocCount,
    HasReadme,
    HasDocsFolder,
    HasContributing,
    HasDocsIndex,
    PriorityScore,
    PriorityBand,
    ReviewMode,
    GitLastCommitDate,
    GitBranch,
    GitUncommittedChanges,
    @{ Name = 'DocQualityHints'; Expression = { ($_.DocQualityHints -join ', ') } },
    @{ Name = 'DocCategories'; Expression = { ($_.DocCategories -join ', ') } },
    @{ Name = 'KeyDocs'; Expression = { ($_.KeyDocs -join '; ') } } |
    Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8

$reportLines = New-Object System.Collections.Generic.List[string]
$reportLines.Add('# Documentation Review Inventory')
$reportLines.Add('')
$reportLines.Add("Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$reportLines.Add('')
$reportLines.Add('## Summary')
$reportLines.Add('')
$reportLines.Add("- Repos with Markdown docs: $($sortedRepoResults.Count)")
$reportLines.Add("- High priority: $(Get-SafeCount ($sortedRepoResults | Where-Object { $_.PriorityBand -eq 'High' }))")
$reportLines.Add("- Medium priority: $(Get-SafeCount ($sortedRepoResults | Where-Object { $_.PriorityBand -eq 'Medium' }))")
$reportLines.Add("- Low priority: $(Get-SafeCount ($sortedRepoResults | Where-Object { $_.PriorityBand -eq 'Low' }))")
$reportLines.Add('')
$reportLines.Add('### Review Modes')
$reportLines.Add('')
foreach ($mode in @('Full-doc pass', 'Core-docs batch', 'Needs taxonomy before rewrite', 'Archive cleanup first', 'README-only')) {
    $count = Get-SafeCount ($sortedRepoResults | Where-Object { $_.ReviewMode -eq $mode })
    if ($count -gt 0) {
        $reportLines.Add("- **${mode}:** $count")
    }
}
$reportLines.Add('')

foreach ($repo in $sortedRepoResults) {
    $reportLines.Add("## $($repo.RepoName)")
    $reportLines.Add('')
    $reportLines.Add("- **Path:** $($repo.RepoPath)")
    $reportLines.Add("- **Priority:** $($repo.PriorityBand) ($($repo.PriorityScore))")
    $reportLines.Add("- **Review mode:** $($repo.ReviewMode)")
    $reportLines.Add("- **Docs:** $($repo.ActiveDocCount) active / $($repo.ArchiveDocCount) archive / $($repo.GeneratedDocCount) generated (total $($repo.MarkdownFileCount))")
    $reportLines.Add("- **Categories:** $([string]::Join(', ', $repo.DocCategories))")
    $reportLines.Add("- **Has README:** $($repo.HasReadme)")
    $reportLines.Add("- **Has docs folder:** $($repo.HasDocsFolder)")
    $reportLines.Add("- **Has contributing guide:** $($repo.HasContributing)")
    $reportLines.Add("- **Has docs index:** $($repo.HasDocsIndex)")
    $reportLines.Add("- **Git branch:** $($repo.GitBranch)")
    $reportLines.Add("- **Last commit:** $($repo.GitLastCommitDate)")
    $reportLines.Add("- **Uncommitted changes:** $($repo.GitUncommittedChanges)")
    if (@($repo.DocQualityHints).Count -gt 0) {
        $reportLines.Add("- **Doc quality hints:** $([string]::Join(', ', $repo.DocQualityHints))")
    }
    $reportLines.Add('')

    if (@($repo.KeyDocs).Count -gt 0) {
        $reportLines.Add('### Key Docs')
        $reportLines.Add('')

        $classMap = @{}
        foreach ($cf in $repo.ClassifiedFiles) { $classMap[$cf.Path] = $cf.DocClass }

        foreach ($doc in $repo.KeyDocs) {
            $cls = if ($classMap.ContainsKey($doc)) { $classMap[$doc] } else { 'Active' }
            $reportLines.Add('- `' + $doc + '` _' + $cls + '_')
        }

        $reportLines.Add('')
    }
}

Set-Content -LiteralPath $reportPath -Value $reportLines -Encoding UTF8

Write-Host ''
Write-Host 'Done.' -ForegroundColor Green
Write-Host "JSON : $($jsonPath)"
Write-Host "CSV : $($csvPath)"
Write-Host "MD : $($reportPath)"
### END FILE: Invoke-DocReviewInventory.ps1
