<#
.SYNOPSIS
    Documentation audit scanner for local repositories.
.DESCRIPTION
    Scans a repository directory against the documentation standards defined in
    doc-standards.json and produces a normalized audit result including per-repo
    doc findings, README quality signals, and a computed DispatchReadiness state.

    DispatchReadiness states:
      ready                  — roadmap has pending work AND docs pass all critical checks
      needs-doc-standardization — roadmap has pending work but docs have critical/warning issues
      missing-roadmap        — no ROADMAP.md found for the repo
      roadmap-complete       — roadmap exists but all items are completed
      parse-error            — roadmap found but could not be parsed
      blocked                — README.md is missing (cannot dispatch without context)

    Exported function: Invoke-AuditRepoDocumentation, Invoke-AuditRepoScan

.NOTES
    Dot-source this file to load functions into the caller scope:
        . (Join-Path $moduleRoot 'DocAudit.Scanner.ps1')
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    Load documentation standards from doc-standards.json.
.PARAMETER StandardsPath
    Path to doc-standards.json. Falls back to the default config location.
#>
function Get-DocStandards {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$StandardsPath = ''
    )

    if ([string]::IsNullOrWhiteSpace($StandardsPath) -or -not (Test-Path -LiteralPath $StandardsPath)) {
        return $null
    }

    try {
        $raw = Get-Content -LiteralPath $StandardsPath -Raw -Encoding UTF8 -ErrorAction Stop
        return ConvertFrom-Json -InputObject $raw
    }
    catch {
        return $null
    }
}

function Get-DocAuditObjectValue {
    param(
        [Parameter()]
        [object]$InputObject,

        [Parameter(Mandatory = $true)]
        [string]$PropertyName,

        [Parameter()]
        [object]$Default = $null
    )

    if ($null -eq $InputObject) { return $Default }

    if ($InputObject -is [System.Collections.IDictionary]) {
        if ($InputObject.ContainsKey($PropertyName)) {
            $value = $InputObject[$PropertyName]
            if ($null -ne $value) { return $value }
        }
        return $Default
    }

    $property = $InputObject.PSObject.Properties[$PropertyName]
    if ($null -ne $property -and $null -ne $property.Value) {
        return $property.Value
    }

    return $Default
}

<#
.SYNOPSIS
    Audit a single repository directory against the documentation standards.
.PARAMETER RepoPath
    Full path to the repository root directory.
.PARAMETER RepoName
    Human-readable name for the repository.
.PARAMETER Standards
    Parsed documentation standards object from Get-DocStandards.
.PARAMETER RoadmapState
    Optional pre-computed roadmap state string (pending/complete/missing/parse-error).
.PARAMETER NextPendingRoadmapItem
    Optional next pending roadmap item text.
.OUTPUTS
    [pscustomobject] with:
      repoName                  string
      repoPath                  string
      dispatchReadiness         string   ready|needs-doc-standardization|missing-roadmap|roadmap-complete|parse-error|blocked
      docFindings               array of { file, message, severity, recommendedAction }
      roadmapState              string
      nextPendingRoadmapItem    string or $null
      auditedAt                 ISO 8601 string
      criticalCount             int
      warningCount              int
      infoCount                 int
      readyForDispatch          bool
#>
function Invoke-AuditRepoDocumentation {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoPath,

        [Parameter(Mandatory = $true)]
        [string]$RepoName,

        [Parameter()]
        [object]$Standards = $null,

        [Parameter()]
        [string]$RoadmapState = 'missing',

        [Parameter()]
        [string]$NextPendingRoadmapItem = ''
    )

    $findings = [System.Collections.Generic.List[pscustomobject]]::new()
    $auditedAt = (Get-Date).ToUniversalTime().ToString('o')

    # --- Required root file checks ---
    $hasReadme = $false
    $readmeLength = 0

    if ($null -ne $Standards -and $null -ne $Standards.requiredRootFiles) {
        foreach ($fileSpec in $Standards.requiredRootFiles) {
            $fileName = [string]$fileSpec.name
            $filePath = Join-Path $RepoPath $fileName

            # Also check common variants (LICENSE vs LICENSE.txt vs LICENSE.md)
            $found = Test-Path -LiteralPath $filePath
            if (-not $found -and $fileName -eq 'LICENSE') {
                $found = (Test-Path (Join-Path $RepoPath 'LICENSE.txt')) -or
                         (Test-Path (Join-Path $RepoPath 'LICENSE.md'))
            }

            if ($fileName -eq 'README.md') {
                $hasReadme = $found
                if ($found) {
                    try {
                        $readmeContent = Get-Content -LiteralPath $filePath -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
                        $readmeLength = if ($readmeContent) { $readmeContent.Length } else { 0 }
                    }
                    catch { $readmeLength = 0 }
                }
            }

            if (-not $found) {
                $findings.Add([pscustomobject]@{
                    file              = $fileName
                    message           = "Required file '$fileName' is missing."
                    severity          = [string]$fileSpec.severity
                    recommendedAction = [string]$fileSpec.recommendedAction
                })
            }
        }
    }
    else {
        # Minimal check without standards object
        $readmePath = Join-Path $RepoPath 'README.md'
        $hasReadme = Test-Path -LiteralPath $readmePath
        if ($hasReadme) {
            try {
                $rc = Get-Content -LiteralPath $readmePath -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
                $readmeLength = if ($rc) { $rc.Length } else { 0 }
            }
            catch { $readmeLength = 0 }
        }
        else {
            $findings.Add([pscustomobject]@{
                file              = 'README.md'
                message           = "README.md is missing."
                severity          = 'critical'
                recommendedAction = 'Create a README.md with project description, installation steps, and usage guide.'
            })
        }
    }

    # --- README quality checks ---
    if ($hasReadme -and $null -ne $Standards -and $null -ne $Standards.readmeStandards) {
        $rs = $Standards.readmeStandards
        $minLen = if ($rs.minLengthChars) { [int]$rs.minLengthChars } else { 300 }

        if ($readmeLength -lt $minLen) {
            $findings.Add([pscustomobject]@{
                file              = 'README.md'
                message           = "README.md is too short ($readmeLength chars; minimum $minLen recommended)."
                severity          = if ($rs.minLengthSeverity) { [string]$rs.minLengthSeverity } else { 'warning' }
                recommendedAction = if ($rs.minLengthRecommendedAction) { [string]$rs.minLengthRecommendedAction } else { 'Expand README.md with more project information.' }
            })
        }

        if ($null -ne $rs.recommendedSections -and $readmeLength -gt 0) {
            try {
                $readmePath = Join-Path $RepoPath 'README.md'
                $readmeContent = Get-Content -LiteralPath $readmePath -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
                if ($readmeContent) {
                    foreach ($section in $rs.recommendedSections) {
                        $heading = [string]$section.heading
                        # Match case-insensitively on the heading text after ##
                        $headingText = $heading -replace '^#+\s*', ''
                        if ($readmeContent -notmatch "(?im)^#{1,6}\s*$([regex]::Escape($headingText))") {
                            $findings.Add([pscustomobject]@{
                                file              = 'README.md'
                                message           = "README.md is missing recommended section: '$headingText'."
                                severity          = if ($section.severity) { [string]$section.severity } else { 'info' }
                                recommendedAction = if ($section.recommendedAction) { [string]$section.recommendedAction } else { "Add a '$headingText' section to README.md." }
                            })
                        }
                    }
                }
            }
            catch { }
        }
    }

    # --- Compute aggregate severity counts ---
    $criticalCount = @($findings | Where-Object { $_.severity -eq 'critical' }).Count
    $warningCount  = @($findings | Where-Object { $_.severity -eq 'warning'  }).Count
    $infoCount     = @($findings | Where-Object { $_.severity -eq 'info'     }).Count

    # --- Compute DispatchReadiness ---
    $readiness = switch ($RoadmapState) {
        'missing' {
            if (-not $hasReadme) { 'blocked' }
            else { 'missing-roadmap' }
        }
        'complete' {
            if (-not $hasReadme) { 'blocked' }
            else { 'roadmap-complete' }
        }
        'parse-error' {
            if (-not $hasReadme) { 'blocked' }
            else { 'parse-error' }
        }
        'pending' {
            if (-not $hasReadme) { 'blocked' }
            elseif ($criticalCount -gt 0 -or $warningCount -gt 0) { 'needs-doc-standardization' }
            else { 'ready' }
        }
        default {
            if (-not $hasReadme) { 'blocked' }
            else { 'missing-roadmap' }
        }
    }

    return [pscustomobject]@{
        repoName               = $RepoName
        repoPath               = $RepoPath
        dispatchReadiness      = $readiness
        docFindings            = @($findings)
        roadmapState           = $RoadmapState
        nextPendingRoadmapItem = if ([string]::IsNullOrWhiteSpace($NextPendingRoadmapItem)) { $null } else { $NextPendingRoadmapItem }
        auditedAt              = $auditedAt
        criticalCount          = $criticalCount
        warningCount           = $warningCount
        infoCount              = $infoCount
        readyForDispatch       = ($readiness -eq 'ready')
    }
}

<#
.SYNOPSIS
    Scan multiple local repository roots and return per-repo dispatch readiness audit results.
.PARAMETER LocalRoots
    Array of local directory paths to scan.
.PARAMETER MaxDepth
    Maximum recursion depth when scanning for repositories.
.PARAMETER RoadmapEntries
    Optional pre-computed roadmap index entries to avoid re-scanning.
.PARAMETER Standards
    Parsed documentation standards object. Loaded from config if not provided.
.PARAMETER StandardsPath
    Path to doc-standards.json file.
.OUTPUTS
    Array of audit result objects (one per discovered repository).
#>
function Invoke-AuditRepoScan {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$LocalRoots,

        [Parameter()]
        [int]$MaxDepth = 3,

        [Parameter()]
        [object[]]$RoadmapEntries = @(),

        [Parameter()]
        [object]$Standards = $null,

        [Parameter()]
        [string]$StandardsPath = ''
    )

    if ($null -eq $Standards) {
        $Standards = Get-DocStandards -StandardsPath $StandardsPath
    }

    # Build a map from repoPath (lowercased) to roadmap entry for quick lookup
    $roadmapMap = @{}
    foreach ($entry in @($RoadmapEntries)) {
        if ($null -eq $entry) { continue }
        $key = ([string](Get-DocAuditObjectValue -InputObject $entry -PropertyName 'repoPath' -Default '')).ToLowerInvariant()
        if (-not [string]::IsNullOrWhiteSpace($key)) {
            $roadmapMap[$key] = $entry
        }
        # Also index by repoName for fallback matching
        $nameKey = ([string](Get-DocAuditObjectValue -InputObject $entry -PropertyName 'repoName' -Default '')).ToLowerInvariant()
        if (-not [string]::IsNullOrWhiteSpace($nameKey) -and -not $roadmapMap.ContainsKey($nameKey)) {
            $roadmapMap[$nameKey] = $entry
        }
    }

    $results = [System.Collections.Generic.List[object]]::new()
    $seenPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($root in $LocalRoots) {
        if (-not (Test-Path -LiteralPath $root)) { continue }

        try {
            # Find all .git directories up to MaxDepth+1 to discover repo roots
            # Use -Force to include hidden directories (e.g., .git is hidden on Linux)
            $gitDirs = Get-ChildItem -Path $root -Recurse -Depth ($MaxDepth + 1) -Directory -Force -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -eq '.git' }
            foreach ($gitDir in $gitDirs) {
                $repoPath = $gitDir.Parent.FullName
                if ($seenPaths.Contains($repoPath)) { continue }
                [void]$seenPaths.Add($repoPath)

                $repoName = $gitDir.Parent.Name

                # Look up roadmap state
                $roadmapState = 'missing'
                $nextPendingItem = ''
                $pathKey = $repoPath.ToLowerInvariant()
                $nameKey = $repoName.ToLowerInvariant()
                $rm = if ($roadmapMap.ContainsKey($pathKey)) { $roadmapMap[$pathKey] }
                      elseif ($roadmapMap.ContainsKey($nameKey)) { $roadmapMap[$nameKey] }
                      else { $null }

                if ($null -ne $rm) {
                    $roadmapState = [string](Get-DocAuditObjectValue -InputObject $rm -PropertyName 'roadmapState' -Default 'missing')
                    $npi = Get-DocAuditObjectValue -InputObject $rm -PropertyName 'nextPendingItem' -Default $null
                    $nextPendingItem = [string](Get-DocAuditObjectValue -InputObject $npi -PropertyName 'text' -Default '')
                }

                $auditResult = Invoke-AuditRepoDocumentation `
                    -RepoPath $repoPath `
                    -RepoName $repoName `
                    -Standards $Standards `
                    -RoadmapState $roadmapState `
                    -NextPendingRoadmapItem $nextPendingItem

                $results.Add($auditResult)
            }
        }
        catch {
            # Non-fatal: log and continue scanning other roots
            Write-Verbose ("docaudit.scan root_error root={0} error={1}" -f $root, $_.Exception.Message)
        }
    }

    return @($results)
}
