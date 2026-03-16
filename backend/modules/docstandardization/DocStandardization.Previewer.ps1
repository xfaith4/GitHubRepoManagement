<#
.SYNOPSIS
    README standardization previewer and applier for Release 1.1.
.DESCRIPTION
    Provides two exported functions:

      Invoke-PreviewReadmeStandardization
        Analyses an existing README.md (or raw content) for missing required
        sections, minimum length, and title presence. Returns a preview object
        with the proposed standardized content and a list of standardization
        actions — without touching the file system.

      Invoke-ApplyReadmeStandardization
        Backs up the current README.md, writes the proposed content, and
        appends a history entry to the JSONL log.

.NOTES
    Dot-source this file to load both functions:
        . (Join-Path $moduleRoot 'DocStandardization.Previewer.ps1')
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

$script:RequiredSections = @('## Installation', '## Usage', '## Contributing', '## License')
$script:MinReadmeLength  = 300
$script:HistoryDir       = 'output/readme-standardization-history'
$script:BackupDir        = 'output/readme-standardization-history/backups'
$script:HistoryLog       = 'output/readme-standardization-history/standardization-history.jsonl'

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

function _EnsureOutputDirs {
    param([string]$WorkspaceRoot)
    $dirs = @(
        (Join-Path $WorkspaceRoot $script:HistoryDir),
        (Join-Path $WorkspaceRoot $script:BackupDir)
    )
    foreach ($dir in $dirs) {
        New-Item -ItemType Directory -Path $dir -Force -ErrorAction SilentlyContinue | Out-Null
    }
}

function _BuildAction {
    param([string]$ActionId, [string]$Description, [string]$Severity)
    return [pscustomobject]@{
        actionId    = $ActionId
        description = $Description
        severity    = $Severity
    }
}

function _HasSection {
    param([string]$Content, [string]$Heading)
    # Match heading at start of line, case-insensitive, ignoring extra whitespace
    $escaped = [regex]::Escape($Heading.TrimStart('#').Trim())
    return ($Content -imatch "(?m)^#{1,6}\s+$escaped\s*$")
}

function _GenerateTemplateReadme {
    param([string]$RepoName)
    return @"
# $RepoName

## Overview

> Describe what this repository does and why it exists.

## Installation

```bash
# Add installation instructions here
```

## Usage

```bash
# Add usage examples here
```

## Contributing

Contributions are welcome. Please open an issue or pull request.

## License

See [LICENSE](LICENSE) for details.
"@
}

function _AppendMissingSections {
    param([string]$Content, [string[]]$MissingSections, [string]$RepoName)
    $result = $Content.TrimEnd()
    foreach ($section in $MissingSections) {
        $sectionTitle = $section.TrimStart('#').Trim()
        $fence       = '```'
        $placeholder  = switch ($sectionTitle) {
            'Installation'  { "${fence}bash`n# Add installation instructions here`n${fence}" }
            'Usage'         { "${fence}bash`n# Add usage examples here`n${fence}" }
            'Contributing'  { 'Contributions are welcome. Please open an issue or pull request.' }
            'License'       { 'See [LICENSE](LICENSE) for details.' }
            default         { "_TODO: Add $sectionTitle content._" }
        }
        $result += "`n`n$section`n`n$placeholder"
    }
    return $result
}

# ---------------------------------------------------------------------------
# Invoke-PreviewReadmeStandardization
# ---------------------------------------------------------------------------

<#
.SYNOPSIS
    Preview what standardization changes would be made to a README.md.
.PARAMETER RepoName
    Name of the repository.
.PARAMETER RepoPath
    Filesystem path to the repository root. Used to read README.md when
    RawContent is not supplied.
.PARAMETER RawContent
    Optional raw README content. If provided, RepoPath is not read.
.OUTPUTS
    [pscustomobject] with previewId, repoName, previewState, blockReason,
    currentContent, proposedContent, standardizationActions, generatedAt.
#>
function Invoke-PreviewReadmeStandardization {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoName,

        [Parameter()]
        [string]$RepoPath,

        [Parameter()]
        [AllowEmptyString()]
        [string]$RawContent
    )

    $previewId = [guid]::NewGuid().ToString('n')
    $actions   = [System.Collections.Generic.List[pscustomobject]]::new()
    $now       = (Get-Date).ToUniversalTime().ToString('o')

    # ---- Resolve content ----
    $currentContent = ''
    $readmeFound    = $false

    if ($PSBoundParameters.ContainsKey('RawContent') -and -not [string]::IsNullOrEmpty($RawContent)) {
        $currentContent = $RawContent
        $readmeFound    = $true
    } elseif ($PSBoundParameters.ContainsKey('RepoPath') -and -not [string]::IsNullOrWhiteSpace($RepoPath)) {
        $readmePath = Join-Path $RepoPath 'README.md'
        if (Test-Path -LiteralPath $readmePath) {
            try {
                $currentContent = Get-Content -LiteralPath $readmePath -Raw -Encoding UTF8
                $readmeFound    = $true
            } catch {
                return [pscustomobject]@{
                    previewId              = $previewId
                    repoName               = $RepoName
                    previewState           = 'standardization-blocked'
                    blockReason            = "Failed to read README.md: $_"
                    currentContent         = ''
                    proposedContent        = ''
                    standardizationActions = @()
                    generatedAt            = $now
                }
            }
        }
    }

    # ---- Build action list ----

    # Missing title check
    $hasTitleLine = $false
    if ($readmeFound -and -not [string]::IsNullOrWhiteSpace($currentContent)) {
        $firstLine = ($currentContent -split "`n")[0].Trim()
        $hasTitleLine = $firstLine -match '^#\s+\S+'
        if (-not $hasTitleLine) {
            $actions.Add((_BuildAction 'ACT-TITLE' "First line should be a top-level heading '# Title'" 'warning'))
        }
    }

    # Missing required sections
    $missingSections = [System.Collections.Generic.List[string]]::new()
    foreach ($section in $script:RequiredSections) {
        if (-not $readmeFound -or -not (_HasSection -Content $currentContent -Heading $section)) {
            $missingSections.Add($section)
            $sectionTitle = $section.TrimStart('#').Trim()
            $actions.Add((_BuildAction "ACT-SECTION-$($sectionTitle.ToUpper() -replace ' ','-')" `
                "Missing required section: $section" 'warning'))
        }
    }

    # Minimum length check
    if ($readmeFound -and $currentContent.Length -lt $script:MinReadmeLength) {
        $actions.Add((_BuildAction 'ACT-LENGTH' `
            "README is only $($currentContent.Length) characters (minimum $($script:MinReadmeLength))." 'info'))
    }

    # ---- Determine proposed content ----
    $proposedContent = ''
    if (-not $readmeFound -or [string]::IsNullOrWhiteSpace($currentContent)) {
        $proposedContent = _GenerateTemplateReadme -RepoName $RepoName
        $actions.Add((_BuildAction 'ACT-CREATE' 'README.md is missing; a full template will be generated.' 'error'))
    } elseif ($missingSections.Count -gt 0 -or -not $hasTitleLine) {
        $proposedContent = _AppendMissingSections `
            -Content $currentContent `
            -MissingSections $missingSections.ToArray() `
            -RepoName $RepoName
    } else {
        $proposedContent = $currentContent
    }

    # ---- Determine preview state ----
    $previewState = if ($actions.Count -eq 0) {
        'already-standard'
    } elseif ($actions | Where-Object { $_.severity -eq 'error' }) {
        'standardization-preview-ready'
    } else {
        'standardization-preview-ready'
    }

    return [pscustomobject]@{
        previewId              = $previewId
        repoName               = $RepoName
        previewState           = $previewState
        blockReason            = $null
        currentContent         = $currentContent
        proposedContent        = $proposedContent
        standardizationActions = $actions.ToArray()
        generatedAt            = $now
    }
}

# ---------------------------------------------------------------------------
# Invoke-ApplyReadmeStandardization
# ---------------------------------------------------------------------------

<#
.SYNOPSIS
    Apply a previously previewed README standardization to disk.
.PARAMETER RepoName
    Name of the repository.
.PARAMETER PreviewId
    The previewId returned by Invoke-PreviewReadmeStandardization.
.PARAMETER ProposedContent
    The proposedContent returned by Invoke-PreviewReadmeStandardization.
.PARAMETER RepoPath
    Filesystem path to the repository root where README.md will be written.
.OUTPUTS
    [pscustomobject] with success, repoName, appliedAt.
#>
function Invoke-ApplyReadmeStandardization {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoName,

        [Parameter(Mandatory = $true)]
        [string]$PreviewId,

        [Parameter(Mandatory = $true)]
        [string]$ProposedContent,

        [Parameter(Mandatory = $true)]
        [string]$RepoPath
    )

    $now        = (Get-Date).ToUniversalTime().ToString('o')
    $readmePath = Join-Path $RepoPath 'README.md'

    # Determine workspace root (two levels up from repo path is not reliable; use output relative to RepoPath)
    # The history dirs are written relative to the workspace root passed as RepoPath's parent — but since
    # the spec says output/ lives at workspace root, we treat RepoPath as workspace root for output.
    _EnsureOutputDirs -WorkspaceRoot $RepoPath

    # ---- Backup existing README ----
    $backedUpPath = $null
    if (Test-Path -LiteralPath $readmePath) {
        try {
            $timestamp    = (Get-Date).ToUniversalTime().ToString('yyyyMMddHHmmss')
            $backupName   = "README.$RepoName.$timestamp.md"
            $backupDest   = Join-Path $RepoPath $script:BackupDir $backupName
            Copy-Item -LiteralPath $readmePath -Destination $backupDest -Force
            $backedUpPath = $backupDest
        } catch {
            # Non-fatal — continue with write
        }
    }

    # ---- Write proposed content ----
    try {
        Set-Content -LiteralPath $readmePath -Value $ProposedContent -Encoding UTF8 -NoNewline
    } catch {
        return [pscustomobject]@{
            success   = $false
            repoName  = $RepoName
            appliedAt = $now
            error     = "Failed to write README.md: $_"
        }
    }

    # ---- Append history entry ----
    try {
        $historyPath = Join-Path $RepoPath $script:HistoryLog
        $entry = [pscustomobject]@{
            previewId   = $PreviewId
            repoName    = $RepoName
            appliedAt   = $now
            backedUpTo  = $backedUpPath
        }
        $json = $entry | ConvertTo-Json -Depth 10 -Compress
        Add-Content -LiteralPath $historyPath -Value $json -Encoding UTF8
    } catch {
        # Non-fatal — history logging failure should not fail the apply
    }

    return [pscustomobject]@{
        success   = $true
        repoName  = $RepoName
        appliedAt = $now
    }
}

