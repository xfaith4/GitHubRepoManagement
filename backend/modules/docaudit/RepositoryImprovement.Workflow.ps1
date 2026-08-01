<#
.SYNOPSIS
    Builds a repository-scoped README/ROADMAP improvement task preview.
.DESCRIPTION
    Reuses the documentation scanner and roadmap parser/auditor to produce one
    reviewable task. This module is intentionally read-only; execution remains
    behind the existing guarded Copilot dispatch endpoint.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-RepositoryImprovementRoadmapPath {
    param([Parameter(Mandatory = $true)][string]$RepoPath)

    foreach ($candidate in @('ROADMAP.md', 'Roadmap.md', 'docs\planning\roadmap.md', 'docs\ROADMAP.md', 'roadmap.md')) {
        $path = Join-Path $RepoPath $candidate
        if (Test-Path -LiteralPath $path -PathType Leaf) { return $path }
    }
    return ''
}

function New-RepositoryImprovementPrompt {
    param(
        [Parameter(Mandatory = $true)][string]$RepoName,
        [Parameter(Mandatory = $true)][array]$Findings,
        [Parameter(Mandatory = $true)][array]$AcceptanceCriteria
    )

    $findingLines = @($Findings | ForEach-Object {
        "- [$([string]$_.severity)] $([string]$_.message) Recommended: $([string]$_.recommendedAction)"
    })
    $criteriaLines = @($AcceptanceCriteria | ForEach-Object { "- $_" })

    return (@(
        "Improve README and ROADMAP readiness for repository '$RepoName'."
        ''
        'Work only on README.md and the repository roadmap. Preserve accurate project-specific content and do not invent commands, features, dates, or completion claims.'
        ''
        'Findings to address:'
        $findingLines
        ''
        'Acceptance criteria:'
        $criteriaLines
        ''
        'Before finishing, inspect the diff, run the narrowest relevant documentation or repository checks available, and open a pull request that explains the findings addressed and any finding intentionally left unresolved.'
    ) -join [Environment]::NewLine)
}

function New-RepositoryImprovementPreview {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)][string]$RepoName,
        [Parameter(Mandatory = $true)][string]$RepoPath,
        [Parameter()][AllowNull()][object]$DocStandards = $null,
        [Parameter()][AllowNull()][object]$RoadmapAuditRules = $null
    )

    if (-not (Test-Path -LiteralPath $RepoPath -PathType Container)) {
        throw "Repository path '$RepoPath' was not found."
    }
    if (-not (Test-Path -LiteralPath (Join-Path $RepoPath '.git'))) {
        throw "Repository path '$RepoPath' is not a Git repository root."
    }

    $roadmapPath = Get-RepositoryImprovementRoadmapPath -RepoPath $RepoPath
    $roadmapRaw = ''
    $parsedRoadmap = $null
    if (-not [string]::IsNullOrWhiteSpace($roadmapPath)) {
        $roadmapRaw = Get-Content -LiteralPath $roadmapPath -Raw -Encoding UTF8 -ErrorAction Stop
        $parsedRoadmap = Invoke-ParseRoadmapContent -Content $roadmapRaw -SourcePath $roadmapPath
    }

    $roadmapContract = Invoke-NormalizeRoadmapContract `
        -ParsedResult $parsedRoadmap `
        -RawContent $roadmapRaw `
        -RepoName $RepoName `
        -RepoPath $RepoPath `
        -RoadmapPath $roadmapPath
    $roadmapContract = Invoke-AuditRoadmapContract -Contract $roadmapContract -AuditRules $RoadmapAuditRules

    $nextPendingItem = if ($null -ne $roadmapContract.nextPendingItem) { [string]$roadmapContract.nextPendingItem.text } else { '' }
    $docAudit = Invoke-AuditRepoDocumentation `
        -RepoPath $RepoPath `
        -RepoName $RepoName `
        -Standards $DocStandards `
        -RoadmapState ([string]$roadmapContract.roadmapState) `
        -NextPendingRoadmapItem $nextPendingItem

    $readmeFindings = @($docAudit.docFindings | Where-Object { [string]$_.file -eq 'README.md' } | ForEach-Object {
        [pscustomobject]@{
            source = 'readme'; file = 'README.md'; ruleId = $null
            severity = [string]$_.severity; message = [string]$_.message
            recommendedAction = [string]$_.recommendedAction
        }
    })
    $roadmapFindings = @($roadmapContract.auditFindings | ForEach-Object {
        [pscustomobject]@{
            source = 'roadmap'; file = 'ROADMAP.md'; ruleId = [string]$_.ruleId
            severity = [string]$_.severity; message = [string]$_.message
            recommendedAction = [string]$_.recommendedAction
        }
    })
    $allFindings = @($readmeFindings) + @($roadmapFindings)

    $acceptanceCriteria = [System.Collections.Generic.List[string]]::new()
    if (@($readmeFindings).Count -gt 0) {
        $acceptanceCriteria.Add('README.md addresses every listed README finding with accurate setup, usage, and project context where applicable.')
    }
    if (@($roadmapFindings).Count -gt 0) {
        $acceptanceCriteria.Add('The roadmap addresses every listed roadmap finding and clearly distinguishes pending work from completed work.')
    }
    if (@($allFindings).Count -gt 0) {
        $acceptanceCriteria.Add('Only README.md and the repository roadmap are changed unless a directly related validation fix is required.')
        $acceptanceCriteria.Add('The pull request describes the documentation changes, validation performed, and any intentionally deferred finding.')
    }

    $task = $null
    if (@($allFindings).Count -gt 0) {
        $criteria = @($acceptanceCriteria)
        $task = [pscustomobject]@{
            taskId = [guid]::NewGuid().ToString('n')
            title = "Improve README and ROADMAP readiness for $RepoName"
            summary = "$(@($allFindings).Count) README/ROADMAP finding(s) require review."
            acceptanceCriteria = $criteria
            generatedPrompt = New-RepositoryImprovementPrompt -RepoName $RepoName -Findings $allFindings -AcceptanceCriteria $criteria
        }
    }

    return [pscustomobject]@{
        repoName = $RepoName
        repoPath = $RepoPath
        scannedAt = (Get-Date).ToUniversalTime().ToString('o')
        needsImprovement = (@($allFindings).Count -gt 0)
        findingCount = @($allFindings).Count
        findings = @($allFindings)
        readme = [pscustomobject]@{
            exists = (Test-Path -LiteralPath (Join-Path $RepoPath 'README.md') -PathType Leaf)
            path = Join-Path $RepoPath 'README.md'
            findingCount = @($readmeFindings).Count
            findings = @($readmeFindings)
        }
        roadmap = [pscustomobject]@{
            exists = (-not [string]::IsNullOrWhiteSpace($roadmapPath))
            path = if ([string]::IsNullOrWhiteSpace($roadmapPath)) { $null } else { $roadmapPath }
            state = [string]$roadmapContract.roadmapState
            maturityLevel = [string]$roadmapContract.maturityLevel
            maturityScore = [int]$roadmapContract.maturityScore
            pendingCount = [int]$roadmapContract.pendingCount
            findingCount = @($roadmapFindings).Count
            findings = @($roadmapFindings)
        }
        task = $task
    }
}
