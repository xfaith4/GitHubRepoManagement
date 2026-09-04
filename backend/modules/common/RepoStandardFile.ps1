<#
.SYNOPSIS
    Locates a repository's standard files (ROADMAP.md, SECURITY.md, ...) at
    every location the standards accept.

.DESCRIPTION
    backend/config/repo-structure-standards.json declares, per required root
    file, the accepted alternative NAMES (same directory: LICENSE.txt for
    LICENSE) and PATHS (repo-relative: docs/ROADMAP.md, .github/SECURITY.md).
    This module is the one place that turns such a spec into an ordered
    candidate list and probes disk, so a repository that keeps its roadmap
    under docs/ reads as having one on every surface: the structure audit, the
    repo evaluator, the doc audit, roadmap write-back and the api-host's
    roadmap resolvers.

    Before this module, four copies of a candidate list and five root-only
    Join-Path lookups answered the same question differently: the Planning
    row of an evaluation found docs/ROADMAP.md while the structure row and the
    "No roadmap" chip of the same evaluation said there was none. The module
    smoke sweeps backend/ for lookups that bypass this module.

    The roadmap index (Invoke-RoadmapScan) still discovers a roadmap anywhere
    under a repository by recursive walk. The standards name the locations a
    repository is EXPECTED to use; a roadmap elsewhere is indexed but reported
    as out of place.

.NOTES
    Dot-source from every module that needs it (idempotent):
        . (Join-Path $PSScriptRoot '..\common\RepoStandardFile.ps1')
    PowerShell 5.1 compatible.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:RepoStandardFileStandardsCache = $null

function Get-RepoStandardFileField {
    <#
    .SYNOPSIS
        Reads one property from a spec that may be a PSCustomObject (JSON) or a hashtable.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter()][object]$Spec,
        [Parameter(Mandatory = $true)][string]$Name
    )
    if ($null -eq $Spec) { return $null }
    if ($Spec -is [System.Collections.IDictionary]) {
        if ($Spec.Contains($Name)) { return $Spec[$Name] }
        return $null
    }
    $prop = $Spec.PSObject.Properties[$Name]
    if ($null -eq $prop) { return $null }
    return $prop.Value
}

function Get-RepoStandardFileSpecList {
    <#
    .SYNOPSIS
        The requiredRootFiles specs, from a supplied standards object or from
        backend/config/repo-structure-standards.json (read once, cached).
    .DESCRIPTION
        Accepts both shapes in use: repo-structure-standards.json nests the
        list under `common`; doc-standards.json carries it at the top level.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param([Parameter()][object]$Standards = $null)

    $source = $Standards
    if ($null -eq $source) {
        if ($null -eq $script:RepoStandardFileStandardsCache) {
            $configPath = Join-Path $PSScriptRoot '..\..\config\repo-structure-standards.json'
            if (Test-Path -LiteralPath $configPath -PathType Leaf) {
                $raw = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8
                $script:RepoStandardFileStandardsCache = ConvertFrom-Json -InputObject $raw
            }
            else {
                # The standards file is part of the repository; its absence is
                # a broken checkout. Degrade to "root only" rather than throw so
                # a read-only surface still answers, and say so on the stream.
                Write-Warning ("repo-structure-standards.json not found at '{0}'; standard files resolve at the repository root only." -f $configPath)
                $script:RepoStandardFileStandardsCache = [pscustomobject]@{ common = [pscustomobject]@{ requiredRootFiles = @() } }
            }
        }
        $source = $script:RepoStandardFileStandardsCache
    }

    $common = Get-RepoStandardFileField -Spec $source -Name 'common'
    if ($null -ne $common) { $source = $common }
    $list = Get-RepoStandardFileField -Spec $source -Name 'requiredRootFiles'
    if ($null -eq $list) { return @() }
    return @($list | Where-Object { $null -ne $_ })
}

function Get-RepoStandardFileSpec {
    <#
    .SYNOPSIS
        The spec for one standard file by name, or a name-only spec when the
        standards do not declare it (so the caller still gets a root probe).
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter()][object]$Standards = $null
    )
    foreach ($spec in @(Get-RepoStandardFileSpecList -Standards $Standards)) {
        if ([string](Get-RepoStandardFileField -Spec $spec -Name 'name') -eq $Name) { return $spec }
    }
    return [pscustomobject]@{ name = $Name }
}

function Get-RepoStandardFileCandidateList {
    <#
    .SYNOPSIS
        Ordered repo-relative candidates for a spec: the name, then altNames
        (same directory), then altPaths (repo-relative). First match wins, so
        a root file outranks a docs/ copy.
    .DESCRIPTION
        Separators are normalized to the platform's, so the JSON can use '/'
        and a Linux runner does not look for a file with a backslash in it.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param([Parameter(Mandatory = $true)][object]$Spec)

    $sep = [System.IO.Path]::DirectorySeparatorChar
    $list = [System.Collections.Generic.List[string]]::new()
    $name = [string](Get-RepoStandardFileField -Spec $Spec -Name 'name')
    if (-not [string]::IsNullOrWhiteSpace($name)) { $list.Add($name) }
    foreach ($alt in @(Get-RepoStandardFileField -Spec $Spec -Name 'altNames')) {
        if (-not [string]::IsNullOrWhiteSpace([string]$alt)) { $list.Add([string]$alt) }
    }
    foreach ($alt in @(Get-RepoStandardFileField -Spec $Spec -Name 'altPaths')) {
        if ([string]::IsNullOrWhiteSpace([string]$alt)) { continue }
        # The replacement side of -replace is literal text, so the separator
        # goes in as-is (escaping it would write two backslashes).
        $normalized = ([string]$alt) -replace '[\\/]+', ([string]$sep)
        $list.Add($normalized)
    }
    return [string[]]@($list | Select-Object -Unique)
}

function Resolve-RepoStandardFilePath {
    <#
    .SYNOPSIS
        The first existing candidate for a spec under a repository, or '' when
        none exists (or the repository path itself does not).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$RepoPath,
        [Parameter(Mandatory = $true)][object]$Spec
    )
    if ([string]::IsNullOrWhiteSpace($RepoPath) -or -not (Test-Path -LiteralPath $RepoPath -PathType Container)) { return '' }
    foreach ($relative in @(Get-RepoStandardFileCandidateList -Spec $Spec)) {
        $candidate = Join-Path $RepoPath $relative
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }
    return ''
}

function Get-RoadmapFileCandidateList {
    <#
    .SYNOPSIS
        Ordered repo-relative roadmap locations, from the ROADMAP.md spec.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param([Parameter()][object]$Standards = $null)
    return [string[]]@(Get-RepoStandardFileCandidateList -Spec (Get-RepoStandardFileSpec -Name 'ROADMAP.md' -Standards $Standards))
}

function Get-RepoRoadmapDefaultPath {
    <#
    .SYNOPSIS
        Where a NEW roadmap is created: the repository root. The one legitimate
        root-only roadmap path in the backend; every lookup goes through
        Resolve-RepoRoadmapPath instead.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory = $true)][string]$RepoPath)
    return (Join-Path $RepoPath 'ROADMAP.md')
}

function Resolve-RepoRoadmapPath {
    <#
    .SYNOPSIS
        The repository's roadmap file at any accepted location, or '' when it
        has none. -DefaultToRoot returns the creation target instead of '' for
        callers that need a path to report or to write.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$RepoPath,
        [Parameter()][object]$Standards = $null,
        [Parameter()][switch]$DefaultToRoot
    )
    $spec = Get-RepoStandardFileSpec -Name 'ROADMAP.md' -Standards $Standards
    $found = Resolve-RepoStandardFilePath -RepoPath $RepoPath -Spec $spec
    if (-not [string]::IsNullOrWhiteSpace($found)) { return $found }
    if ($DefaultToRoot -and -not [string]::IsNullOrWhiteSpace($RepoPath)) { return (Get-RepoRoadmapDefaultPath -RepoPath $RepoPath) }
    return ''
}
