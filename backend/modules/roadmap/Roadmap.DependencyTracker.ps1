<#
.SYNOPSIS
    Cross-repo dependency tracker for ROADMAP.md files.
.DESCRIPTION
    Scans roadmap content across all indexed repos and identifies references from
    one repo's roadmap items to other known repos in the portfolio.

    Detection patterns (case-insensitive):
      - GitHub URLs:           https://github.com/{owner}/{repoName}
      - Repo-hash refs:        {repoName}#{number}  (e.g. OtherRepo#42)
      - Explicit keywords:     "depends on {repoName}", "requires {repoName}",
                               "blocked by {repoName}", "after {repoName}"

    Exported function: Invoke-ScanRoadmapDependencies

.NOTES
    Dot-source this file to load Invoke-ScanRoadmapDependencies into the caller scope:
        . (Join-Path $moduleRoot 'Roadmap.DependencyTracker.ps1')
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    Extract cross-repo dependency references from a single roadmap's text.
.PARAMETER Content
    Raw roadmap markdown content.
.PARAMETER SourceRepoName
    Name of the repo whose roadmap is being scanned (used to exclude self-references).
.PARAMETER KnownRepoNames
    Array of all known repo names in the portfolio for targeted matching.
.PARAMETER GitHubOwner
    GitHub org/user for URL pattern matching (optional).
.OUTPUTS
    Array of dependency objects: { targetRepo, context, lineNumber, pattern }
#>
function Get-RoadmapDependencyReferences {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content,

        [Parameter(Mandatory = $true)]
        [string]$SourceRepoName,

        [Parameter(Mandatory = $true)]
        [string[]]$KnownRepoNames,

        [Parameter()]
        [string]$GitHubOwner = ''
    )

    $deps    = [System.Collections.Generic.List[pscustomobject]]::new()
    $seen    = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $lines   = $Content -split '\r?\n'
    $lineNum = 0

    # Build a lookup set of known repos (excluding self) for fast O(1) checks
    $repoSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($r in $KnownRepoNames) {
        if ($r -ne $SourceRepoName) { $null = $repoSet.Add($r) }
    }

    foreach ($line in $lines) {
        $lineNum++

        # Pattern 1: GitHub URL  https://github.com/{owner}/{repo}
        if (-not [string]::IsNullOrWhiteSpace($GitHubOwner)) {
            $urlPattern = [regex]::new(
                "https://github\.com/$([regex]::Escape($GitHubOwner))/([A-Za-z0-9_.\-]+)",
                [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
            )
            foreach ($m in $urlPattern.Matches($line)) {
                $target = $m.Groups[1].Value
                if ($repoSet.Contains($target) -and $seen.Add("$target|url")) {
                    $deps.Add([pscustomobject]@{
                        targetRepo = $target
                        context    = $line.Trim()
                        lineNumber = $lineNum
                        pattern    = 'github-url'
                    })
                }
            }
        }

        # Pattern 2: RepoName#number  (e.g. MyOtherRepo#42)
        foreach ($m in [regex]::Matches($line, '([A-Za-z][A-Za-z0-9_.\-]*)#\d+')) {
            $target = $m.Groups[1].Value
            if ($repoSet.Contains($target) -and $seen.Add("$target|hash-ref")) {
                $deps.Add([pscustomobject]@{
                    targetRepo = $target
                    context    = $line.Trim()
                    lineNumber = $lineNum
                    pattern    = 'hash-ref'
                })
            }
        }

        # Pattern 3: Explicit dependency keywords followed by a known repo name
        $keywordPattern = [regex]::new(
            '\b(?:depends?\s+on|requires?|blocked\s+by|after|needs?)\s+([A-Za-z][A-Za-z0-9_.\-]*)',
            [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
        )
        foreach ($m in $keywordPattern.Matches($line)) {
            $target = $m.Groups[1].Value
            if ($repoSet.Contains($target) -and $seen.Add("$target|keyword")) {
                $deps.Add([pscustomobject]@{
                    targetRepo = $target
                    context    = $line.Trim()
                    lineNumber = $lineNum
                    pattern    = 'keyword'
                })
            }
        }
    }

    return @($deps)
}

<#
.SYNOPSIS
    Scan all roadmap entries and build a portfolio-wide cross-repo dependency graph.
.PARAMETER RoadmapEntries
    Array of roadmap index entries. Each must have: repoName, content (or filePath).
.PARAMETER GitHubOwner
    GitHub org/user for URL pattern matching (optional).
.OUTPUTS
    [pscustomobject] with:
      graph         hashtable keyed by repoName → array of dependency objects
      summary       array of { sourceRepo, dependsOn: string[], dependedOnBy: string[] }
      totalEdges    int
      scannedAt     string (ISO-8601)
#>
function Invoke-ScanRoadmapDependencies {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$RoadmapEntries,

        [Parameter()]
        [string]$GitHubOwner = ''
    )

    $knownRepos = @($RoadmapEntries | Where-Object { $_.repoName } | ForEach-Object { $_.repoName })

    $graph      = @{}
    $totalEdges = 0

    foreach ($entry in $RoadmapEntries) {
        $repoName = $entry.repoName
        if ([string]::IsNullOrWhiteSpace($repoName)) { continue }

        $content = ''
        if ($entry.PSObject.Properties['content'] -and -not [string]::IsNullOrWhiteSpace($entry.content)) {
            $content = $entry.content
        } elseif ($entry.PSObject.Properties['filePath'] -and (Test-Path -LiteralPath $entry.filePath)) {
            try { $content = Get-Content -LiteralPath $entry.filePath -Raw -ErrorAction Stop } catch { continue }
        }

        if ([string]::IsNullOrWhiteSpace($content)) {
            $graph[$repoName] = @()
            continue
        }

        $refs = Get-RoadmapDependencyReferences `
            -Content       $content `
            -SourceRepoName $repoName `
            -KnownRepoNames $knownRepos `
            -GitHubOwner   $GitHubOwner

        $graph[$repoName] = @($refs)
        $totalEdges += $refs.Count
    }

    # Build reverse index for "depended-on-by" view
    $dependedOnBy = @{}
    foreach ($src in $graph.Keys) {
        foreach ($dep in $graph[$src]) {
            $tgt = $dep.targetRepo
            if (-not $dependedOnBy.ContainsKey($tgt)) { $dependedOnBy[$tgt] = @() }
            $dependedOnBy[$tgt] += $src
        }
    }

    $summary = @($knownRepos | ForEach-Object {
        $src      = $_
        $depNames = @($graph[$src] | ForEach-Object { $_.targetRepo } | Sort-Object -Unique)
        $revNames = @(if ($dependedOnBy.ContainsKey($src)) { $dependedOnBy[$src] | Sort-Object -Unique } else { @() })
        [pscustomobject]@{
            repoName    = $src
            dependsOn   = $depNames
            dependedOnBy = $revNames
        }
    } | Where-Object { $_.dependsOn.Count -gt 0 -or $_.dependedOnBy.Count -gt 0 })

    return [pscustomobject]@{
        graph      = $graph
        summary    = @($summary)
        totalEdges = $totalEdges
        scannedAt  = (Get-Date).ToUniversalTime().ToString('o')
    }
}
