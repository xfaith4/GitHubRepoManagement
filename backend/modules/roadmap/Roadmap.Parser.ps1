<#
.SYNOPSIS
    Structured roadmap parser for ROADMAP.md files.
.DESCRIPTION
    Parses markdown roadmap content to extract checkbox task items, group them by
    section, classify roadmap state, and surface the next actionable pending item.

    Exported function: Invoke-ParseRoadmapContent

    Roadmap states returned:
      pending    — one or more unchecked items found
      complete   — checkboxes present but none are unchecked
      parse-error — content is empty, null, or contains no checkbox items

.NOTES
    Dot-source this file to load Invoke-ParseRoadmapContent into the caller scope:
        . (Join-Path $moduleRoot 'Roadmap.Parser.ps1')
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    Parse markdown roadmap content and return a normalized state object.
.PARAMETER Content
    Raw text content of a ROADMAP.md file.
.PARAMETER SourcePath
    Optional file path for diagnostic messages.
.OUTPUTS
    [pscustomobject] with:
      roadmapState      string   pending | complete | parse-error
      pendingCount      int
      completedCount    int
      totalCount        int
      nextPendingItem   pscustomobject { text, section, tags } or $null
      sections          array of { name, pendingItems[], completedItems[] }
      allTags           string[]  unique tags found across all items
      parseError        string or $null

    Tags are bracketed tokens in item text, e.g. `[security]`, `[infra]`, `[breaking]`.
    They are stripped from the display text stored in pendingItems/completedItems.
#>
function Invoke-ParseRoadmapContent {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Content,

        [Parameter()]
        [string]$SourcePath = ''
    )

    # Empty / null content → parse-error
    if ([string]::IsNullOrWhiteSpace($Content)) {
        return [pscustomobject]@{
            roadmapState    = 'parse-error'
            pendingCount    = 0
            completedCount  = 0
            totalCount      = 0
            nextPendingItem = $null
            sections        = @()
            allTags         = @()
            parseError      = 'Roadmap content is empty.'
        }
    }

    $lines = $Content -split '\r?\n'

    # Guard against pathologically large roadmaps — cap at 5 000 lines to keep
    # parsing predictable; the linter enforces the same limit.
    $script:MaxParserLines = 5000
    if ($lines.Count -gt $script:MaxParserLines) {
        $lines = $lines[0..($script:MaxParserLines - 1)]
    }

    $currentSection  = 'General'
    $sections        = [System.Collections.Generic.List[pscustomobject]]::new()
    $sectionMap      = @{}   # section name → index in $sections
    $allTagsSet      = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    $pendingCount    = 0
    $completedCount  = 0
    $nextPendingItem = $null

    # Extract bracketed tags from an item string, e.g. "[security] [infra]".
    # Returns a hashtable: { text = cleaned text; tags = string[] }
    function Get-ItemTagsAndText {
        param([string]$Raw)
        $tags = @([regex]::Matches($Raw, '\[([a-zA-Z0-9_-]+)\]') | ForEach-Object { $_.Groups[1].Value.ToLowerInvariant() })
        $cleaned = ([regex]::Replace($Raw, '\s*\[[a-zA-Z0-9_-]+\]', '')).Trim()
        return @{ text = $cleaned; tags = $tags }
    }

    foreach ($line in $lines) {
        # Detect section headings (## or ###)
        if ($line -match '^#{1,6}\s+(.+)$') {
            $currentSection = $Matches[1].Trim()
            if (-not $sectionMap.ContainsKey($currentSection)) {
                $sec = [pscustomobject]@{
                    name           = $currentSection
                    pendingItems   = [System.Collections.Generic.List[string]]::new()
                    completedItems = [System.Collections.Generic.List[string]]::new()
                }
                $sections.Add($sec)
                $sectionMap[$currentSection] = $sections.Count - 1
            }
            continue
        }

        # Ensure a default section bucket exists
        if (-not $sectionMap.ContainsKey($currentSection)) {
            $sec = [pscustomobject]@{
                name           = $currentSection
                pendingItems   = [System.Collections.Generic.List[string]]::new()
                completedItems = [System.Collections.Generic.List[string]]::new()
            }
            $sections.Add($sec)
            $sectionMap[$currentSection] = $sections.Count - 1
        }

        $sec = $sections[$sectionMap[$currentSection]]

        # Pending item:  - [ ] text  (space inside brackets)
        if ($line -match '^\s*-\s+\[\s\]\s+(.+)$') {
            $parsed   = Get-ItemTagsAndText -Raw $Matches[1].Trim()
            $itemText = $parsed.text
            $itemTags = $parsed.tags
            foreach ($t in $itemTags) { $null = $allTagsSet.Add($t) }
            $sec.pendingItems.Add($itemText)
            $pendingCount++
            if ($null -eq $nextPendingItem) {
                $nextPendingItem = [pscustomobject]@{
                    text    = $itemText
                    section = $currentSection
                    tags    = $itemTags
                }
            }
            continue
        }

        # Completed item: - [x] or - [X] text
        if ($line -match '^\s*-\s+\[[xX]\]\s+(.+)$') {
            $parsed   = Get-ItemTagsAndText -Raw $Matches[1].Trim()
            $itemText = $parsed.text
            $itemTags = $parsed.tags
            foreach ($t in $itemTags) { $null = $allTagsSet.Add($t) }
            $sec.completedItems.Add($itemText)
            $completedCount++
            continue
        }
    }

    $totalCount = $pendingCount + $completedCount

    # Classify state
    if ($totalCount -eq 0) {
        $state    = 'parse-error'
        $errorMsg = if ([string]::IsNullOrWhiteSpace($SourcePath)) {
            'No checkbox items found in roadmap content.'
        } else {
            "No checkbox items found in roadmap file: $SourcePath"
        }
    } elseif ($pendingCount -gt 0) {
        $state    = 'pending'
        $errorMsg = $null
    } else {
        $state    = 'complete'
        $errorMsg = $null
    }

    return [pscustomobject]@{
        roadmapState    = $state
        pendingCount    = $pendingCount
        completedCount  = $completedCount
        totalCount      = $totalCount
        nextPendingItem = $nextPendingItem
        sections        = @($sections)
        allTags         = @($allTagsSet | Sort-Object)
        parseError      = $errorMsg
    }
}
