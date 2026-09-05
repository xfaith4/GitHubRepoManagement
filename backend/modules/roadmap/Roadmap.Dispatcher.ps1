<#
.SYNOPSIS
    Release-level roadmap dispatch helpers for GitHub Copilot agent tasks.
.DESCRIPTION
    Provides three exported functions:

      Get-NextPendingRelease
        Parses raw ROADMAP.md content and returns the first release section
        (## Release X.Y — Title) that contains at least one unchecked milestone.

      Build-ReleaseDispatchPacket
        Assembles a structured dispatch packet for the next pending release,
        including a fully-formatted Copilot task prompt.

      Resolve-GitHubRepoIdentity
        Resolves the "owner/repo" GitHub slug for a local git clone by reading
        the 'origin' remote URL. Supports both HTTPS and SSH remote formats.

.NOTES
    Dot-source this file after Roadmap.Parser.ps1, Roadmap.Auditor.ps1, and
    Roadmap.Repairer.ps1:
        . (Join-Path $moduleRoot 'Roadmap.Parser.ps1')
        . (Join-Path $moduleRoot 'Roadmap.Auditor.ps1')
        . (Join-Path $moduleRoot 'Roadmap.Repairer.ps1')
        . (Join-Path $moduleRoot 'Roadmap.Dispatcher.ps1')
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

function _ExtractSubsectionLines {
    <#
    .SYNOPSIS
        Extract bullet lines from a named subsection within a markdown block.
        Stops at the next ### heading or end of content.
    #>
    param(
        [string[]]$Lines,
        [string]$HeadingPattern  # regex to match the ### heading line
    )

    $results = [System.Collections.Generic.List[string]]::new()
    $inSection = $false
    $headingDepth = 0

    foreach ($line in $Lines) {
        if ($line -match "^\s*(#{3,6})\s+$HeadingPattern") {
            $inSection = $true
            $headingDepth = $matches[1].Length
            continue
        }

        if ($inSection) {
            if ($line -match '^\s*(#{1,6})\s+') {
                if ($matches[1].Length -le $headingDepth) { break }
                continue
            }
            # Collect non-empty bullet lines
            if ($line -match '^\s*-\s+(.+)$') {
                $text = $matches[1].Trim()
                # Strip leading [ ] or [x] checkbox markers if present
                $text = $text -replace '^\[[ xX]\]\s+', ''
                if (-not [string]::IsNullOrWhiteSpace($text)) {
                    $results.Add($text)
                }
            }
        }
    }

    return @($results)
}

function _ExtractGoal {
    param([string[]]$Lines)

    foreach ($line in $Lines) {
        if ($line -match '\*\*Goal:\*\*\s*(.+)') {
            return $matches[1].Trim()
        }
    }
    return ''
}

# ---------------------------------------------------------------------------
# Get-NextPendingRelease
# ---------------------------------------------------------------------------

<#
.SYNOPSIS
    Find the first release section in ROADMAP.md content that has pending items.
.PARAMETER RoadmapContent
    Raw string content of a ROADMAP.md file.
.OUTPUTS
    [pscustomobject] with:
      found               bool
      releaseName         string  e.g. "Release 1.6 — API Authentication"
      releaseVersion      string  e.g. "1.6"
      releaseTitle        string  e.g. "API Authentication"
      goal                string
      pendingMilestones   string[]  items without [x]
      completedMilestones string[]  items with [x]
      acceptanceCriteria  string[]
      outOfScope          string[]
      milestoneCount      int
      pendingCount        int
      completedCount      int
      notFound            string or $null  reason if found=$false
#>
function Get-NextPendingRelease {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$RoadmapContent
    )

    if ([string]::IsNullOrWhiteSpace($RoadmapContent)) {
        return [pscustomobject]@{
            found    = $false
            notFound = 'Roadmap content is empty.'
        }
    }

    # Releases may be nested under a parent such as "Open Releases".
    $releaseHeadingRx = [regex]'(?im)^#{2,6}\s+Release (\d+[\d\.]*)\s*[—–-]+\s*(.+?)$'
    $headingMatches = $releaseHeadingRx.Matches($RoadmapContent)

    if ($headingMatches.Count -eq 0) {
        return [pscustomobject]@{
            found    = $false
            notFound = 'No release sections (## Release X.Y) found in roadmap.'
        }
    }

    # Build list of blocks: { version, title, startIndex }
    $blocks = [System.Collections.Generic.List[hashtable]]::new()
    foreach ($m in $headingMatches) {
        $blocks.Add(@{
            version    = $m.Groups[1].Value.Trim()
            title      = $m.Groups[2].Value.Trim()
            startIndex = $m.Index
        })
    }

    for ($i = 0; $i -lt $blocks.Count; $i++) {
        $block = $blocks[$i]
        $blockStart = $block.startIndex
        $blockEnd   = if ($i + 1 -lt $blocks.Count) { $blocks[$i + 1].startIndex } else { $RoadmapContent.Length }
        $blockText  = $RoadmapContent.Substring($blockStart, $blockEnd - $blockStart)
        $blockLines = $blockText -split "`r?`n"

        # Count pending and completed milestone items
        $pendingMilestones   = [System.Collections.Generic.List[string]]::new()
        $completedMilestones = [System.Collections.Generic.List[string]]::new()

        foreach ($line in $blockLines) {
            if ($line -match '^\s*-\s*\[\s\]\s+(.+)$') {
                $pendingMilestones.Add($matches[1].Trim())
            }
            elseif ($line -match '^\s*-\s*\[x\]\s+(.+)$') {
                $completedMilestones.Add($matches[1].Trim())
            }
        }

        if ($pendingMilestones.Count -eq 0) {
            continue  # This release is fully complete — skip
        }

        # Found the first release with pending work
        $goal              = _ExtractGoal -Lines $blockLines
        $acceptanceCriteria = _ExtractSubsectionLines -Lines $blockLines -HeadingPattern 'Acceptance\s+criteria'
        $outOfScope        = _ExtractSubsectionLines -Lines $blockLines -HeadingPattern 'Out\s+of\s+scope'
        $validationPlan    = @(if ($null -ne (Get-Command -Name '_RoadmapParserExtractValidationLines' -ErrorAction SilentlyContinue)) {
            @(_RoadmapParserExtractValidationLines -Lines $blockLines)
        } else {
            @(_ExtractSubsectionLines -Lines $blockLines -HeadingPattern '(?:Validation|Test)\s+plan')
        })

        $releaseName = "Release $($block.version) — $($block.title)"

        return [pscustomobject]@{
            found               = $true
            releaseName         = $releaseName
            releaseVersion      = $block.version
            releaseTitle        = $block.title
            goal                = $goal
            pendingMilestones   = @($pendingMilestones)
            completedMilestones = @($completedMilestones)
            acceptanceCriteria  = @($acceptanceCriteria)
            outOfScope          = @($outOfScope)
            validationPlan      = @($validationPlan)
            milestoneCount      = $pendingMilestones.Count + $completedMilestones.Count
            pendingCount        = $pendingMilestones.Count
            completedCount      = $completedMilestones.Count
            notFound            = $null
        }
    }

    return [pscustomobject]@{
        found    = $false
        notFound = 'All release sections are fully complete — no pending milestones found.'
    }
}

# ---------------------------------------------------------------------------
# Build-ReleaseDispatchPacket
# ---------------------------------------------------------------------------

<#
.SYNOPSIS
    Build a structured dispatch packet for the next pending release.
.PARAMETER RepoName
    Short repository name (e.g. "GitHubRepoManagement").
.PARAMETER RoadmapContent
    Raw ROADMAP.md content string.
.PARAMETER RoadmapPath
    File path to the ROADMAP.md on disk (for metadata only).
.PARAMETER GitHubRepo
    GitHub "owner/repo" slug. Pass empty string at check-time; populated at execute-time.
.PARAMETER AuditContract
    Optional: the already-audited contract object (pscustomobject). Used to embed
    maturityLevel and maturityScore into the packet.
.OUTPUTS
    [pscustomobject] with:
      packetVersion, packetId, createdAt, repoName, githubRepo, roadmapPath,
      releaseName, releaseVersion, releaseGoal,
      pendingMilestones[], acceptanceCriteria[], outOfScope[],
      generatedPrompt, maturityLevel, maturityScore
#>
function Build-ReleaseDispatchPacket {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoName,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$RoadmapContent,

        [Parameter(Mandatory = $true)]
        [string]$RoadmapPath,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$GitHubRepo,

        [Parameter()]
        [AllowNull()]
        [pscustomobject]$AuditContract = $null,

        [Parameter()]
        [AllowNull()]
        [pscustomobject]$ExecutionContract = $null
    )

    $release = Get-NextPendingRelease -RoadmapContent $RoadmapContent
    if (-not $release.found) {
        throw "Cannot build dispatch packet: $($release.notFound)"
    }

    $packetId  = "{0}-{1}" -f (Get-Date -Format 'yyyyMMdd-HHmmss'), ([guid]::NewGuid().ToString('N').Substring(0, 8))
    $createdAt = (Get-Date).ToUniversalTime().ToString('o')

    $maturityLevel = if ($null -ne $AuditContract -and $AuditContract.PSObject.Properties['maturityLevel']) { [string]$AuditContract.maturityLevel } else { 'unknown' }
    $maturityScore = if ($null -ne $AuditContract -and $AuditContract.PSObject.Properties['maturityScore']) { [int]$AuditContract.maturityScore } else { 0 }

    $generatedPrompt = _BuildDispatchPrompt `
        -RepoName      $RepoName `
        -GitHubRepo    $GitHubRepo `
        -RoadmapPath   $RoadmapPath `
        -Release       $release

    return [pscustomobject]@{
        packetVersion      = '2.0'
        packetId           = $packetId
        createdAt          = $createdAt
        repoName           = $RepoName
        githubRepo         = $GitHubRepo
        roadmapPath        = $RoadmapPath
        releaseName        = $release.releaseName
        releaseVersion     = $release.releaseVersion
        releaseGoal        = $release.goal
        pendingMilestones  = @($release.pendingMilestones)
        acceptanceCriteria = @($release.acceptanceCriteria)
        outOfScope         = @($release.outOfScope)
        validationPlan     = @($release.validationPlan)
        executionContract  = $ExecutionContract
        generatedPrompt    = $generatedPrompt
        maturityLevel      = $maturityLevel
        maturityScore      = $maturityScore
    }
}

function _BuildDispatchPrompt {
    param(
        [string]$RepoName,
        [string]$GitHubRepo,
        [string]$RoadmapPath,
        [pscustomobject]$Release
    )

    $lines = [System.Collections.Generic.List[string]]::new()

    $lines.Add("# Copilot Task: Implement $($Release.releaseName) for $RepoName")
    $lines.Add('')
    $lines.Add('## Repository Context')
    $lines.Add('')

    if (-not [string]::IsNullOrWhiteSpace($GitHubRepo)) {
        $lines.Add("Repository: $GitHubRepo")
    } else {
        $lines.Add("Repository: $RepoName")
    }

    if (-not [string]::IsNullOrWhiteSpace($RoadmapPath)) {
        $lines.Add("Roadmap:    $RoadmapPath")
    }

    $lines.Add("Release:    $($Release.releaseName)")

    if (-not [string]::IsNullOrWhiteSpace($Release.goal)) {
        $lines.Add("Goal:       $($Release.goal)")
    }

    $lines.Add('')
    $lines.Add('## Engineering Milestones to Implement')
    $lines.Add('')
    $lines.Add('Implement ALL of the following milestones in this task:')
    $lines.Add('')

    $idx = 1
    foreach ($m in $Release.pendingMilestones) {
        $lines.Add("$idx. [ ] $m")
        $idx++
    }

    if ($Release.acceptanceCriteria.Count -gt 0) {
        $lines.Add('')
        $lines.Add('## Acceptance Criteria')
        $lines.Add('')
        $lines.Add('All of the following must be true before marking this release complete:')
        $lines.Add('')
        foreach ($c in $Release.acceptanceCriteria) {
            $lines.Add("- $c")
        }
    }

    if ($Release.outOfScope.Count -gt 0) {
        $lines.Add('')
        $lines.Add('## Guardrails (Out of Scope — Do NOT implement)')
        $lines.Add('')
        foreach ($o in $Release.outOfScope) {
            $lines.Add("- $o")
        }
    }

    if ($Release.validationPlan.Count -gt 0) {
        $lines.Add('')
        $lines.Add('## Required Verification')
        $lines.Add('')
        foreach ($verification in $Release.validationPlan) {
            $lines.Add("- $verification")
        }
    }

    $lines.Add('')
    $lines.Add('## Execution Requirements')
    $lines.Add('')
    $lines.Add('1. Verify the most recently completed roadmap items are truly complete in code, tests, and docs.')
    $lines.Add('2. Implement ALL Engineering Milestones end-to-end with production-safe changes.')
    $lines.Add('3. Mark each completed milestone `[x]` in ROADMAP.md.')
    $lines.Add('4. Run existing tests and quality gates before finalizing.')
    $lines.Add("5. Create a PR titled `"$($Release.releaseName) — implementation`".")

    return ($lines -join "`n")
}

# ---------------------------------------------------------------------------
# Resolve-GitHubRepoIdentity
# ---------------------------------------------------------------------------

<#
.SYNOPSIS
    Resolve the GitHub "owner/repo" slug from a local git clone's origin remote.
.PARAMETER LocalPath
    Absolute path to the local repository directory.
.PARAMETER FallbackOwner
    Optional: GitHub owner name to use if git remote resolution fails.
.PARAMETER FallbackRepoName
    Optional: Repository name to use with FallbackOwner if resolution fails.
.OUTPUTS
    [string] "owner/repo"
#>
function Resolve-GitHubRepoIdentity {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$LocalPath,

        [Parameter()]
        [AllowEmptyString()]
        [string]$FallbackOwner = '',

        [Parameter()]
        [AllowEmptyString()]
        [string]$FallbackRepoName = ''
    )

    if ([string]::IsNullOrWhiteSpace($LocalPath)) {
        throw 'LocalPath is required for Resolve-GitHubRepoIdentity.'
    }

    if (-not (Test-Path -LiteralPath $LocalPath -PathType Container)) {
        throw "Local path '$LocalPath' does not exist or is not a directory."
    }

    # Try to find git on PATH
    $gitCmd = Get-Command -Name 'git' -ErrorAction SilentlyContinue
    if ($null -eq $gitCmd) {
        if (-not [string]::IsNullOrWhiteSpace($FallbackOwner) -and -not [string]::IsNullOrWhiteSpace($FallbackRepoName)) {
            Write-Warning "git not found on PATH. Using fallback identity: $FallbackOwner/$FallbackRepoName"
            return "$FallbackOwner/$FallbackRepoName"
        }
        throw "git was not found on PATH and no fallback owner/repo was provided."
    }

    # Run: git -C <path> remote get-url origin
    $gitOutput = & $gitCmd.Source -C $LocalPath remote get-url origin 2>&1
    $exitCode  = $LASTEXITCODE

    if ($exitCode -ne 0 -or [string]::IsNullOrWhiteSpace($gitOutput)) {
        if (-not [string]::IsNullOrWhiteSpace($FallbackOwner) -and -not [string]::IsNullOrWhiteSpace($FallbackRepoName)) {
            Write-Warning "git remote get-url origin failed for '$LocalPath'. Using fallback: $FallbackOwner/$FallbackRepoName"
            return "$FallbackOwner/$FallbackRepoName"
        }
        throw "git remote get-url origin failed for '$LocalPath'. Ensure the repository has a remote named 'origin'. git output: $gitOutput"
    }

    $remoteUrl = ([string]$gitOutput).Trim()

    # Match both HTTPS and SSH GitHub remote formats:
    #   https://github.com/owner/repo.git
    #   git@github.com:owner/repo.git
    $m = [regex]::Match($remoteUrl, 'github\.com[/:]([^/]+)/([^/.]+)')
    if (-not $m.Success) {
        if (-not [string]::IsNullOrWhiteSpace($FallbackOwner) -and -not [string]::IsNullOrWhiteSpace($FallbackRepoName)) {
            Write-Warning "Remote URL '$remoteUrl' does not appear to be a GitHub repository. Using fallback: $FallbackOwner/$FallbackRepoName"
            return "$FallbackOwner/$FallbackRepoName"
        }
        throw "Remote URL '$remoteUrl' for '$LocalPath' does not appear to be a GitHub repository (github.com not found)."
    }

    $owner = $m.Groups[1].Value.Trim()
    $repo  = $m.Groups[2].Value.Trim() -replace '\.git$', ''

    if ([string]::IsNullOrWhiteSpace($owner) -or [string]::IsNullOrWhiteSpace($repo)) {
        throw "Could not parse owner/repo from remote URL '$remoteUrl'."
    }

    return "$owner/$repo"
}
