<#
.SYNOPSIS
    AI documentation improvement provider adapters and preview orchestrator
    for Release 1.9 (AI Documentation Improvement Cycles), Phase 1.

.DESCRIPTION
    Provides a provider-agnostic contract for generating improved README.md and
    ROADMAP.md content from current content plus a built-in improvement template.

    Three adapters implement the same contract:

      Invoke-HeuristicDocProvider   Deterministic, offline, always available.
                                     Scaffolds missing required sections and
                                     normalizes the title. This is the
                                     no-hard-roadblock fallback: a preview can
                                     always be produced even with no AI key.
      Invoke-OpenAiDocProvider      Raw HTTP to the OpenAI Chat Completions API,
                                     used only when an API key is configured.
      Invoke-AnthropicDocProvider   Raw HTTP to the Anthropic Messages API,
                                     used only when an API key is configured.

    Invoke-AiDocImprovePreview ties these together: it resolves a template,
    selects an available provider (with graceful fallback to the heuristic
    provider), and returns a preview-only record. NOTHING is written to disk —
    apply is a later Release 1.9 phase.

    TOKEN USAGE AND COST (Release 3.1)

    Every provider result carries a `usage` record, and every count in it is
    nullable: $null means unmeasured and 0 means measured-as-zero. `source`
    distinguishes the cases that look alike from the outside — a model that
    reported nothing (`absent`, a defect) from a call that failed
    (`call-failed`) from the offline provider that called no model at all
    (`not-applicable`).

    Cost is derived only from operator-supplied rates. Add them to settings as:

        "ai": {
          "pricing": {
            "claude-opus-4-8": { "inputPerMillionUsd": 5, "outputPerMillionUsd": 25 }
          }
        }

    This repo ships no rates on purpose. Published prices change, and a stale
    rate produces a confidently wrong number — worse than an honest blank. With
    no rate configured `costUsd` stays $null, `costBasis` says
    'no-price-configured', and the UI renders "unmeasured" rather than $0.00.

.NOTES
    Dot-source this file to load the public functions:
        . (Join-Path $aiModuleRoot 'AiDocImprovement.ps1')
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

$script:AiDocTemplatesRelPath = 'backend\config\ai-doc-templates.json'
$script:AiDocHistoryRelDir = 'output\ai-doc-improvements'
$script:AiDocBackupRelDir = 'output\ai-doc-improvements\backups'
$script:AiDocDefaultAnthropicModel = 'claude-opus-4-8'
$script:AiDocDefaultOpenAiModel = 'gpt-4o'
$script:AiDocDefaultMaxTokens = 8000
$script:AiDocHttpTimeoutSec = 60

# Usage provenance. Every provider result carries one of these, so a consumer
# can tell "no model was called" apart from "a model was called and told us
# nothing" — the second is a defect, the first is not.
$script:AiDocUsageSourceProvider      = 'provider-usage'   # real counts from the API response
$script:AiDocUsageSourceAbsent        = 'absent'           # call succeeded, response carried no usage block
$script:AiDocUsageSourceCallFailed    = 'call-failed'      # call errored; usage is unknowable
$script:AiDocUsageSourceNotApplicable = 'not-applicable'   # no model was called (offline heuristic)

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

function _AiGetField {
    param([object]$Obj, [string]$Name, [object]$Default = $null)
    if ($null -eq $Obj) { return $Default }
    if ($Obj -is [System.Collections.IDictionary]) {
        if ($Obj.Contains($Name) -and $null -ne $Obj[$Name]) { return $Obj[$Name] }
        return $Default
    }
    if ($null -ne $Obj.PSObject -and ($Obj.PSObject.Properties.Name -contains $Name)) {
        $v = $Obj.$Name
        if ($null -ne $v) { return $v }
    }
    return $Default
}

function _AiHasHeading {
    param([string]$Content, [string]$Heading)
    if ([string]::IsNullOrWhiteSpace($Content)) { return $false }
    $escaped = [regex]::Escape($Heading.TrimStart('#').Trim())
    return ($Content -imatch "(?m)^#{1,6}\s+$escaped\s*$")
}

function _AiResolveApiKey {
    param([string]$EnvVarName)
    if ([string]::IsNullOrWhiteSpace($EnvVarName)) { return '' }
    $val = [Environment]::GetEnvironmentVariable($EnvVarName)
    if ([string]::IsNullOrWhiteSpace($val)) { return '' }
    return $val
}

# ---------------------------------------------------------------------------
# Templates
# ---------------------------------------------------------------------------

<#
.SYNOPSIS
    Load the built-in AI documentation improvement templates config.
#>
function Get-AiDocTemplates {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$WorkspaceRoot)

    $path = Join-Path $WorkspaceRoot $script:AiDocTemplatesRelPath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return [pscustomobject]@{ readmeTemplates = @(); roadmapTemplates = @() }
    }
    try {
        return ConvertFrom-Json -InputObject (Get-Content -LiteralPath $path -Raw -Encoding UTF8)
    }
    catch {
        return [pscustomobject]@{ readmeTemplates = @(); roadmapTemplates = @() }
    }
}

<#
.SYNOPSIS
    Resolve a template for a doc type. Returns $null when no template matches,
    so the orchestrator can still run with a custom-prompt-only improvement.
#>
function Resolve-AiDocTemplate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$DocType,
        [Parameter()][string]$TemplateId = '',
        [Parameter()][object]$TemplatesConfig = $null
    )

    if ($null -eq $TemplatesConfig) { return $null }

    $list = @(if ($DocType -eq 'roadmap') {
        @(_AiGetField -Obj $TemplatesConfig -Name 'roadmapTemplates' -Default @())
    }
    else {
        @(_AiGetField -Obj $TemplatesConfig -Name 'readmeTemplates' -Default @())
    })
    if (@($list).Count -eq 0) { return $null }

    if (-not [string]::IsNullOrWhiteSpace($TemplateId)) {
        $match = @($list | Where-Object { [string](_AiGetField -Obj $_ -Name 'id' -Default '') -eq $TemplateId } | Select-Object -First 1)
        if (@($match).Count -gt 0) { return $match[0] }
        return $null
    }

    # Default to the first template for the doc type.
    return @($list)[0]
}

# ---------------------------------------------------------------------------
# Provider resolution
# ---------------------------------------------------------------------------

<#
.SYNOPSIS
    Read AI provider settings from the host settings object, applying defaults.
.OUTPUTS
    [pscustomobject] with configuredProvider, and per-provider model/key/maxTokens.
#>
function Get-AiDocProviderSettings {
    [CmdletBinding()]
    param([Parameter()][object]$Settings = $null)

    $ai = _AiGetField -Obj $Settings -Name 'ai' -Default $null
    $anthropic = _AiGetField -Obj $ai -Name 'anthropic' -Default $null
    $openai = _AiGetField -Obj $ai -Name 'openai' -Default $null

    return [pscustomobject]@{
        configuredProvider = [string](_AiGetField -Obj $ai -Name 'provider' -Default 'auto')
        anthropicKeyEnvVar = [string](_AiGetField -Obj $anthropic -Name 'apiKeyEnvVar' -Default 'ANTHROPIC_API_KEY')
        anthropicModel     = [string](_AiGetField -Obj $anthropic -Name 'model' -Default $script:AiDocDefaultAnthropicModel)
        anthropicMaxTokens = [int](_AiGetField -Obj $anthropic -Name 'maxTokens' -Default $script:AiDocDefaultMaxTokens)
        openAiKeyEnvVar    = [string](_AiGetField -Obj $openai -Name 'apiKeyEnvVar' -Default 'OPENAI_API_KEY')
        openAiModel        = [string](_AiGetField -Obj $openai -Name 'model' -Default $script:AiDocDefaultOpenAiModel)
        openAiMaxTokens    = [int](_AiGetField -Obj $openai -Name 'maxTokens' -Default $script:AiDocDefaultMaxTokens)
        # Optional, operator-supplied, and empty by default — see Resolve-AiDocUsageCost.
        pricing            = _AiGetField -Obj $ai -Name 'pricing' -Default $null
    }
}

<#
.SYNOPSIS
    Determine which providers are usable right now (key present in environment).
#>
function Get-AiDocProviderAvailability {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$ProviderSettings)

    return [pscustomobject]@{
        heuristic = $true
        anthropic = -not [string]::IsNullOrWhiteSpace((_AiResolveApiKey -EnvVarName $ProviderSettings.anthropicKeyEnvVar))
        openai    = -not [string]::IsNullOrWhiteSpace((_AiResolveApiKey -EnvVarName $ProviderSettings.openAiKeyEnvVar))
    }
}

# ---------------------------------------------------------------------------
# Scoring (estimated movement based on required-section coverage)
# ---------------------------------------------------------------------------

function _AiSectionScore {
    param([string]$Content, [string[]]$RequiredSections)

    $sections = @($RequiredSections)
    if ($sections.Count -eq 0) {
        # No template sections to measure against: fall back to a coarse length signal.
        $len = if ([string]::IsNullOrWhiteSpace($Content)) { 0 } else { $Content.Length }
        if ($len -ge 1200) { return 100 }
        if ($len -le 0) { return 0 }
        return [int][Math]::Round(100.0 * [Math]::Min(1.0, $len / 1200.0))
    }

    $present = 0
    foreach ($s in $sections) {
        if (_AiHasHeading -Content $Content -Heading $s) { $present++ }
    }
    $hasTitle = $false
    if (-not [string]::IsNullOrWhiteSpace($Content)) {
        $firstLine = ($Content -split "`n")[0].Trim()
        $hasTitle = $firstLine -match '^#\s+\S+'
    }
    # 90% section coverage + 10% title presence.
    $sectionScore = 90.0 * ($present / [double]$sections.Count)
    $titleScore = if ($hasTitle) { 10.0 } else { 0.0 }
    return [int][Math]::Round($sectionScore + $titleScore)
}

# ---------------------------------------------------------------------------
# Token usage and cost
#
# The rule this section exists to enforce: a number that was never measured is
# reported as $null with a named reason, never as 0. Zero tokens and zero
# dollars are real values that mean "this cost nothing" — claiming them for an
# unmeasured call is the failure mode this milestone was written against.
# ---------------------------------------------------------------------------

function _AiUsageInt {
    param([object]$Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [string] -and [string]::IsNullOrWhiteSpace($Value)) { return $null }
    try {
        $n = [int]$Value
        if ($n -lt 0) { return $null }
        return $n
    }
    catch {
        return $null
    }
}

<#
.SYNOPSIS
    Build the canonical token-usage record carried by every provider result.
.DESCRIPTION
    Normalizes whatever the provider reported into one shape. Counts are $null
    when unknown — never 0. `measured` is true only when a model actually
    reported counts, so a consumer never has to infer trust from the numbers.

    `source` is the provenance and is the field a gate should assert on:
      provider-usage   real counts from the API response
      absent           the call succeeded and reported nothing (a defect)
      call-failed      the call errored; usage cannot be known
      not-applicable   no model was called at all (offline heuristic)
.OUTPUTS
    [pscustomobject] with inputTokens, outputTokens, totalTokens, measured,
    source, costUsd, costBasis.
#>
function New-AiDocUsage {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Pure constructor: normalizes reported counts into a record and mutates nothing. -WhatIf plumbing would imply it changes state, which is the opposite of its contract.')]
    param(
        [Parameter()][AllowNull()][object]$InputTokens = $null,
        [Parameter()][AllowNull()][object]$OutputTokens = $null,
        [Parameter()][AllowNull()][object]$TotalTokens = $null,
        [Parameter()][ValidateSet('provider-usage', 'absent', 'call-failed', 'not-applicable')]
        [string]$Source = 'absent'
    )

    $inTok  = _AiUsageInt -Value $InputTokens
    $outTok = _AiUsageInt -Value $OutputTokens
    $total  = _AiUsageInt -Value $TotalTokens

    # Derive a total only from counts that were actually reported. If exactly one
    # side is present the total is that side plus an unknown, which is not a
    # total — leave it null rather than understate it.
    if ($null -eq $total -and $null -ne $inTok -and $null -ne $outTok) {
        $total = $inTok + $outTok
    }

    $measured = ($Source -eq $script:AiDocUsageSourceProvider -and $null -ne $total)
    $effectiveSource = if ($Source -eq $script:AiDocUsageSourceProvider -and -not $measured) {
        # The adapter asked for a provider reading and got nothing usable. Say so.
        $script:AiDocUsageSourceAbsent
    }
    else { $Source }

    $costBasis = switch ($effectiveSource) {
        $script:AiDocUsageSourceNotApplicable { 'not-applicable' }
        $script:AiDocUsageSourceCallFailed    { 'call-failed' }
        $script:AiDocUsageSourceAbsent        { 'usage-absent' }
        default                               { 'no-price-configured' }
    }

    return [pscustomobject]@{
        inputTokens  = $inTok
        outputTokens = $outTok
        totalTokens  = $total
        measured     = $measured
        source       = $effectiveSource
        costUsd      = $null
        costBasis    = $costBasis
    }
}

<#
.SYNOPSIS
    Attach a USD cost to a usage record when — and only when — a price is known.
.DESCRIPTION
    Prices are operator-supplied under `ai.pricing.<modelId>` as
    `{ inputPerMillionUsd, outputPerMillionUsd }`. This repo ships no prices:
    published rates change, and a stale rate produces a confidently wrong
    number, which is worse than an honest blank. With no price configured the
    cost stays $null and `costBasis` says why, which is what the UI renders as
    "unmeasured".
.OUTPUTS
    [pscustomobject] usage record with costUsd/costBasis resolved.
#>
function Resolve-AiDocUsageCost {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)][object]$Usage,
        [Parameter()][AllowNull()][AllowEmptyString()][string]$ModelId = '',
        [Parameter()][AllowNull()][object]$Pricing = $null
    )

    $result = [pscustomobject]@{
        inputTokens  = _AiGetField -Obj $Usage -Name 'inputTokens'  -Default $null
        outputTokens = _AiGetField -Obj $Usage -Name 'outputTokens' -Default $null
        totalTokens  = _AiGetField -Obj $Usage -Name 'totalTokens'  -Default $null
        measured     = [bool](_AiGetField -Obj $Usage -Name 'measured' -Default $false)
        source       = [string](_AiGetField -Obj $Usage -Name 'source' -Default $script:AiDocUsageSourceAbsent)
        costUsd      = $null
        costBasis    = [string](_AiGetField -Obj $Usage -Name 'costBasis' -Default 'no-price-configured')
    }

    # Nothing measured means nothing to price. The basis already names the reason.
    if (-not $result.measured) { return $result }

    if ([string]::IsNullOrWhiteSpace($ModelId)) {
        $result.costBasis = 'no-model-id'
        return $result
    }

    $modelPrice = _AiGetField -Obj $Pricing -Name $ModelId -Default $null
    if ($null -eq $modelPrice) {
        $result.costBasis = 'no-price-configured'
        return $result
    }

    $inPrice  = _AiGetField -Obj $modelPrice -Name 'inputPerMillionUsd'  -Default $null
    $outPrice = _AiGetField -Obj $modelPrice -Name 'outputPerMillionUsd' -Default $null
    if ($null -eq $inPrice -or $null -eq $outPrice) {
        $result.costBasis = 'price-incomplete'
        return $result
    }

    # Both sides are needed: a total alone cannot be split across two rates.
    if ($null -eq $result.inputTokens -or $null -eq $result.outputTokens) {
        $result.costBasis = 'token-detail-insufficient'
        return $result
    }

    try {
        $cost = ([double]$result.inputTokens / 1000000.0) * [double]$inPrice +
                ([double]$result.outputTokens / 1000000.0) * [double]$outPrice
        $result.costUsd = [Math]::Round($cost, 6)
        $result.costBasis = 'priced-from-settings'
    }
    catch {
        $result.costBasis = 'price-invalid'
    }

    return $result
}

# ---------------------------------------------------------------------------
# Heuristic provider (offline, deterministic, always available)
# ---------------------------------------------------------------------------

<#
.SYNOPSIS
    Produce an improved document offline by normalizing the title and scaffolding
    any required sections that the template expects but the current content lacks.
.OUTPUTS
    Normalized provider result (see Invoke-AiDocImprovePreview return shape).
#>
function Invoke-HeuristicDocProvider {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$DocType,
        [Parameter(Mandatory = $true)][string]$RepoName,
        [Parameter()][AllowEmptyString()][string]$CurrentContent = '',
        [Parameter()][string[]]$RequiredSections = @(),
        [Parameter()][string]$CustomPrompt = ''
    )

    $changes = [System.Collections.Generic.List[string]]::new()
    $content = if ($null -eq $CurrentContent) { '' } else { $CurrentContent }
    $proposed = $content.TrimEnd()

    # 1. Ensure a top-level title.
    $firstLine = if ([string]::IsNullOrWhiteSpace($proposed)) { '' } else { ($proposed -split "`n")[0].Trim() }
    if ($firstLine -notmatch '^#\s+\S+') {
        $titleWord = if ($DocType -eq 'roadmap') { "$RepoName Roadmap" } else { $RepoName }
        $proposed = "# $titleWord`n`n" + $proposed.TrimStart()
        $changes.Add("Added a top-level title heading.")
    }

    # 2. Scaffold missing required sections.
    foreach ($section in @($RequiredSections)) {
        $heading = "## $section"
        if (-not (_AiHasHeading -Content $proposed -Heading $section)) {
            $placeholder = "_TODO: Add $section content._"
            $proposed = $proposed.TrimEnd() + "`n`n$heading`n`n$placeholder"
            $changes.Add("Scaffolded missing section: $heading")
        }
    }

    # 3. Record custom-prompt intent so the operator sees it reflected.
    if (-not [string]::IsNullOrWhiteSpace($CustomPrompt)) {
        $changes.Add("Noted custom improvement instruction (offline heuristic cannot apply free-form rewrites): $CustomPrompt")
    }

    if ($changes.Count -eq 0) {
        $changes.Add("No structural changes needed; document already covers the expected sections.")
    }

    return [pscustomobject]@{
        providerId      = 'heuristic'
        modelId         = $null
        proposedContent = $proposed
        changeSummary   = @($changes)
        warnings        = @()
        error           = $null
        # No model was called, so there is nothing to measure — which is not the
        # same as measuring zero.
        usage           = New-AiDocUsage -Source $script:AiDocUsageSourceNotApplicable
    }
}

# ---------------------------------------------------------------------------
# Prompt construction for network providers
# ---------------------------------------------------------------------------

function _AiBuildSystemPrompt {
    param([string]$DocType)
    $docLabel = if ($DocType -eq 'roadmap') { 'ROADMAP.md' } else { 'README.md' }
    $docSpecificRule = if ($DocType -eq 'roadmap') {
        'For pending roadmap work, use compact action-first milestone text with explicit scope and verification signals.'
    }
    else {
        'For README content, keep outcome, setup, and usage sections compact, executable, and easy to scan.'
    }
    return @"
You are a documentation specialist improving a project's $docLabel file.
Use semantic compression: maximize information density; minimize filler, repetition, throat-clearing, and generic transitions.
Prefer short headings, parallel bullets, and compact tables only when they are clearer than prose.
$docSpecificRule
Return only the improved Markdown document — no preamble, no commentary, no code fences around the whole document.
Preserve accurate existing facts, links, badges, and genuine completion history. Do not invent features or fabricate completed work.
"@
}

function _AiBuildUserPrompt {
    param(
        [string]$RepoName,
        [string]$DocType,
        [string]$CurrentContent,
        [string]$Guidance,
        [string[]]$RequiredSections,
        [string]$CustomPrompt
    )
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine("Repository: $RepoName")
    [void]$sb.AppendLine("Document type: $DocType")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("Compression contract:")
    [void]$sb.AppendLine("- High information density; no filler or throat-clearing.")
    [void]$sb.AppendLine("- Merge redundant statements; keep bullets parallel.")
    [void]$sb.AppendLine("- Use the shortest wording that preserves operator/agent utility.")
    if ($DocType -eq 'roadmap') {
        [void]$sb.AppendLine("- ROADMAP pending items: action-first, independently selectable, verification-ready.")
    }
    else {
        [void]$sb.AppendLine("- README sections: outcome-first, setup/usage executable, repeated explanation collapsed.")
    }
    if (-not [string]::IsNullOrWhiteSpace($Guidance)) {
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("Template intent:")
        [void]$sb.AppendLine($Guidance)
    }
    if (@($RequiredSections).Count -gt 0) {
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("Target sections:")
        foreach ($s in @($RequiredSections)) { [void]$sb.AppendLine("- $s") }
    }
    if (-not [string]::IsNullOrWhiteSpace($CustomPrompt)) {
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("Operator delta:")
        [void]$sb.AppendLine($CustomPrompt)
    }
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("Current document:")
    [void]$sb.AppendLine("-----BEGIN CURRENT DOCUMENT-----")
    [void]$sb.AppendLine($CurrentContent)
    [void]$sb.AppendLine("-----END CURRENT DOCUMENT-----")
    return $sb.ToString()
}

# ---------------------------------------------------------------------------
# Anthropic provider (raw HTTP — Messages API)
# ---------------------------------------------------------------------------

<#
.SYNOPSIS
    Generate improved content via the Anthropic Messages API.
.DESCRIPTION
    Uses raw HTTP because PowerShell has no official Anthropic SDK. Sends no
    temperature/top_p (removed on current Opus models). On any failure, returns
    a result with `error` set so the orchestrator can surface it and fall back.
#>
function Invoke-AnthropicDocProvider {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ApiKey,
        [Parameter(Mandatory = $true)][string]$Model,
        [Parameter(Mandatory = $true)][string]$SystemPrompt,
        [Parameter(Mandatory = $true)][string]$UserPrompt,
        [Parameter()][int]$MaxTokens = 8000
    )

    try {
        $headers = @{
            'x-api-key'         = $ApiKey
            'anthropic-version' = '2023-06-01'
            'content-type'      = 'application/json'
        }
        $payload = @{
            model      = $Model
            max_tokens = $MaxTokens
            system     = $SystemPrompt
            messages   = @(@{ role = 'user'; content = $UserPrompt })
        } | ConvertTo-Json -Depth 8

        $resp = Invoke-RestMethod -Method Post -Uri 'https://api.anthropic.com/v1/messages' `
            -Headers $headers -Body $payload -TimeoutSec $script:AiDocHttpTimeoutSec

        $text = ''
        foreach ($block in @($resp.content)) {
            if ([string](_AiGetField -Obj $block -Name 'type' -Default '') -eq 'text') {
                $text += [string](_AiGetField -Obj $block -Name 'text' -Default '')
            }
        }
        if ([string]::IsNullOrWhiteSpace($text)) {
            throw 'Anthropic response contained no text content.'
        }

        # The Messages API returns usage alongside the content. Read it here or
        # it is gone: the response object does not outlive this scope.
        $rawUsage = _AiGetField -Obj $resp -Name 'usage' -Default $null

        return [pscustomobject]@{
            providerId      = 'anthropic'
            modelId         = $Model
            proposedContent = $text.Trim()
            changeSummary   = @("Document rewritten by Anthropic ($Model).")
            warnings        = @()
            error           = $null
            usage           = New-AiDocUsage `
                -InputTokens  (_AiGetField -Obj $rawUsage -Name 'input_tokens'  -Default $null) `
                -OutputTokens (_AiGetField -Obj $rawUsage -Name 'output_tokens' -Default $null) `
                -Source       $script:AiDocUsageSourceProvider
        }
    }
    catch {
        return [pscustomobject]@{
            providerId      = 'anthropic'
            modelId         = $Model
            proposedContent = ''
            changeSummary   = @()
            warnings        = @()
            error           = "Anthropic provider call failed: $($_.Exception.Message)"
            usage           = New-AiDocUsage -Source $script:AiDocUsageSourceCallFailed
        }
    }
}

# ---------------------------------------------------------------------------
# OpenAI provider (raw HTTP — Chat Completions API)
# ---------------------------------------------------------------------------

<#
.SYNOPSIS
    Generate improved content via the OpenAI Chat Completions API (raw HTTP).
#>
function Invoke-OpenAiDocProvider {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ApiKey,
        [Parameter(Mandatory = $true)][string]$Model,
        [Parameter(Mandatory = $true)][string]$SystemPrompt,
        [Parameter(Mandatory = $true)][string]$UserPrompt,
        [Parameter()][int]$MaxTokens = 8000
    )

    try {
        $headers = @{
            'Authorization' = "Bearer $ApiKey"
            'content-type'  = 'application/json'
        }
        $payload = @{
            model      = $Model
            max_tokens = $MaxTokens
            messages   = @(
                @{ role = 'system'; content = $SystemPrompt },
                @{ role = 'user'; content = $UserPrompt }
            )
        } | ConvertTo-Json -Depth 8

        $resp = Invoke-RestMethod -Method Post -Uri 'https://api.openai.com/v1/chat/completions' `
            -Headers $headers -Body $payload -TimeoutSec $script:AiDocHttpTimeoutSec

        $text = [string](_AiGetField -Obj (@($resp.choices)[0].message) -Name 'content' -Default '')
        if ([string]::IsNullOrWhiteSpace($text)) {
            throw 'OpenAI response contained no message content.'
        }

        # Chat Completions reports usage with different field names than the
        # Messages API; both normalize into the same record.
        $rawUsage = _AiGetField -Obj $resp -Name 'usage' -Default $null

        return [pscustomobject]@{
            providerId      = 'openai'
            modelId         = $Model
            proposedContent = $text.Trim()
            changeSummary   = @("Document rewritten by OpenAI ($Model).")
            warnings        = @()
            error           = $null
            usage           = New-AiDocUsage `
                -InputTokens  (_AiGetField -Obj $rawUsage -Name 'prompt_tokens'     -Default $null) `
                -OutputTokens (_AiGetField -Obj $rawUsage -Name 'completion_tokens' -Default $null) `
                -TotalTokens  (_AiGetField -Obj $rawUsage -Name 'total_tokens'      -Default $null) `
                -Source       $script:AiDocUsageSourceProvider
        }
    }
    catch {
        return [pscustomobject]@{
            providerId      = 'openai'
            modelId         = $Model
            proposedContent = ''
            changeSummary   = @()
            warnings        = @()
            error           = "OpenAI provider call failed: $($_.Exception.Message)"
            usage           = New-AiDocUsage -Source $script:AiDocUsageSourceCallFailed
        }
    }
}

# ---------------------------------------------------------------------------
# Orchestrator
# ---------------------------------------------------------------------------

<#
.SYNOPSIS
    Build a preview-only AI documentation improvement record.
.DESCRIPTION
    Resolves a template, selects an available provider (honoring an explicit
    request, then settings, then falling back to the always-available heuristic
    provider), and returns current vs proposed content, a change summary,
    estimated score movement, and warnings. No file is written.
.PARAMETER DocType
    'readme' (default) or 'roadmap'.
.PARAMETER Provider
    Optional explicit provider: 'auto', 'heuristic', 'openai', or 'anthropic'.
    Empty uses the configured provider from settings (default 'auto').
.OUTPUTS
    [pscustomobject] preview record.
#>
function Invoke-AiDocImprovePreview {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)][string]$WorkspaceRoot,
        [Parameter(Mandatory = $true)][string]$RepoName,
        [Parameter()][string]$DocType = 'readme',
        [Parameter()][AllowEmptyString()][string]$CurrentContent = '',
        [Parameter()][string]$TemplateId = '',
        [Parameter()][string]$CustomPrompt = '',
        [Parameter()][string]$Provider = '',
        [Parameter()][object]$Settings = $null
    )

    $previewId = [guid]::NewGuid().ToString('n')
    $now = (Get-Date).ToUniversalTime().ToString('o')
    $docType = if ($DocType -eq 'roadmap') { 'roadmap' } else { 'readme' }
    $currentContent = if ($null -eq $CurrentContent) { '' } else { $CurrentContent }
    $warnings = [System.Collections.Generic.List[string]]::new()

    # ---- Resolve template ----
    $templates = Get-AiDocTemplates -WorkspaceRoot $WorkspaceRoot
    $template = Resolve-AiDocTemplate -DocType $docType -TemplateId $TemplateId -TemplatesConfig $templates
    if ($null -eq $template -and -not [string]::IsNullOrWhiteSpace($TemplateId)) {
        $warnings.Add("Template '$TemplateId' was not found for doc type '$docType'; using a generic improvement.")
    }
    $effectiveTemplateId = [string](_AiGetField -Obj $template -Name 'id' -Default '')
    $guidance = [string](_AiGetField -Obj $template -Name 'guidance' -Default '')
    $requiredSections = @(_AiGetField -Obj $template -Name 'requiredSections' -Default @() | ForEach-Object { [string]$_ })

    if ([string]::IsNullOrWhiteSpace($currentContent)) {
        $warnings.Add("Current $docType content is empty; the improvement starts from a scaffold.")
    }

    # ---- Resolve provider ----
    $providerSettings = Get-AiDocProviderSettings -Settings $Settings
    $availability = Get-AiDocProviderAvailability -ProviderSettings $providerSettings

    $requested = if (-not [string]::IsNullOrWhiteSpace($Provider)) { $Provider.ToLowerInvariant() } else { $providerSettings.configuredProvider.ToLowerInvariant() }
    if ([string]::IsNullOrWhiteSpace($requested)) { $requested = 'auto' }

    $selected = 'heuristic'
    if ($requested -eq 'heuristic') {
        $selected = 'heuristic'
    }
    elseif ($requested -eq 'anthropic') {
        if ($availability.anthropic) { $selected = 'anthropic' }
        else { $warnings.Add('Anthropic provider requested but no API key is configured; falling back to the offline heuristic provider.') }
    }
    elseif ($requested -eq 'openai') {
        if ($availability.openai) { $selected = 'openai' }
        else { $warnings.Add('OpenAI provider requested but no API key is configured; falling back to the offline heuristic provider.') }
    }
    else {
        # auto
        if ($availability.anthropic) { $selected = 'anthropic' }
        elseif ($availability.openai) { $selected = 'openai' }
        else {
            $selected = 'heuristic'
            $warnings.Add('No AI provider key configured; using the offline heuristic provider. Set an Anthropic or OpenAI API key to enable AI rewrites.')
        }
    }

    # ---- Invoke provider ----
    $result = $null
    if ($selected -eq 'anthropic' -or $selected -eq 'openai') {
        $systemPrompt = _AiBuildSystemPrompt -DocType $docType
        $userPrompt = _AiBuildUserPrompt -RepoName $RepoName -DocType $docType -CurrentContent $currentContent `
            -Guidance $guidance -RequiredSections $requiredSections -CustomPrompt $CustomPrompt

        if ($selected -eq 'anthropic') {
            $result = Invoke-AnthropicDocProvider -ApiKey (_AiResolveApiKey -EnvVarName $providerSettings.anthropicKeyEnvVar) `
                -Model $providerSettings.anthropicModel -SystemPrompt $systemPrompt -UserPrompt $userPrompt -MaxTokens $providerSettings.anthropicMaxTokens
        }
        else {
            $result = Invoke-OpenAiDocProvider -ApiKey (_AiResolveApiKey -EnvVarName $providerSettings.openAiKeyEnvVar) `
                -Model $providerSettings.openAiModel -SystemPrompt $systemPrompt -UserPrompt $userPrompt -MaxTokens $providerSettings.openAiMaxTokens
        }

        if ($null -ne $result -and -not [string]::IsNullOrWhiteSpace([string]$result.error)) {
            $warnings.Add([string]$result.error)
            $warnings.Add('Falling back to the offline heuristic provider so a preview is still available.')
            $result = $null
        }
    }

    if ($null -eq $result) {
        $selected = 'heuristic'
        $result = Invoke-HeuristicDocProvider -DocType $docType -RepoName $RepoName -CurrentContent $currentContent `
            -RequiredSections $requiredSections -CustomPrompt $CustomPrompt
    }

    foreach ($w in @($result.warnings)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$w)) { $warnings.Add([string]$w) }
    }

    $proposedContent = [string]$result.proposedContent

    # ---- Token usage and cost ----
    # An adapter that predates this contract returns no usage at all; treat that
    # as absent rather than inventing zeros, so the gate sees it.
    $rawUsage = _AiGetField -Obj $result -Name 'usage' -Default $null
    $usage = if ($null -eq $rawUsage) { New-AiDocUsage -Source $script:AiDocUsageSourceAbsent } else { $rawUsage }
    $usage = Resolve-AiDocUsageCost -Usage $usage -ModelId ([string]$result.modelId) -Pricing $providerSettings.pricing

    if ($usage.source -eq $script:AiDocUsageSourceAbsent -and $selected -ne 'heuristic') {
        $warnings.Add("The $selected provider returned no token usage; cost for this preview is unmeasured.")
    }

    # ---- Estimated score movement ----
    $scoreBefore = _AiSectionScore -Content $currentContent -RequiredSections $requiredSections
    $scoreAfter = _AiSectionScore -Content $proposedContent -RequiredSections $requiredSections

    return [pscustomobject]@{
        previewId       = $previewId
        repoName        = $RepoName
        docType         = $docType
        providerId      = [string]$result.providerId
        modelId         = $result.modelId
        templateId      = $effectiveTemplateId
        customPrompt    = if (-not [string]::IsNullOrWhiteSpace($CustomPrompt)) { $CustomPrompt } else { $null }
        currentContent  = $currentContent
        proposedContent = $proposedContent
        changeSummary   = @($result.changeSummary)
        estimatedScore  = [pscustomobject]@{
            before = $scoreBefore
            after  = $scoreAfter
            delta  = ($scoreAfter - $scoreBefore)
        }
        usage           = $usage
        warnings        = @($warnings)
        generatedAt     = $now
    }
}

# ---------------------------------------------------------------------------
# Improvement cycle history (per repo, JSONL — compact metadata, no full docs)
# ---------------------------------------------------------------------------

function _AiHistoryFilePath {
    param([string]$WorkspaceRoot, [string]$RepoName)
    $safeRepoName = $RepoName -replace '[\\/:*?"<>|]', '_'
    $historyRoot = Join-Path $WorkspaceRoot $script:AiDocHistoryRelDir
    $null = New-Item -ItemType Directory -Path $historyRoot -Force -ErrorAction SilentlyContinue
    return Join-Path $historyRoot "$safeRepoName.improvements.jsonl"
}

<#
.SYNOPSIS
    Append a compact improvement-cycle history record for a generated preview.
.DESCRIPTION
    Stores metadata only (scores, provider, template, change summary) — not the
    full current/proposed document bodies, which can be regenerated and would
    bloat the per-repo JSONL. Failures are non-fatal: history must never block
    a preview.
#>
function Write-AiDocImprovementHistory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$WorkspaceRoot,
        [Parameter(Mandatory = $true)][object]$Preview
    )

    $repoName = [string](_AiGetField -Obj $Preview -Name 'repoName' -Default '')
    if ([string]::IsNullOrWhiteSpace($repoName)) { return $null }

    $score = _AiGetField -Obj $Preview -Name 'estimatedScore' -Default $null
    $usage = _AiGetField -Obj $Preview -Name 'usage' -Default $null
    if ($null -eq $usage) { $usage = New-AiDocUsage -Source $script:AiDocUsageSourceAbsent }

    $record = [ordered]@{
        previewId     = [string](_AiGetField -Obj $Preview -Name 'previewId' -Default '')
        createdAt     = [string](_AiGetField -Obj $Preview -Name 'generatedAt' -Default ((Get-Date).ToUniversalTime().ToString('o')))
        repoName      = $repoName
        docType       = [string](_AiGetField -Obj $Preview -Name 'docType' -Default 'readme')
        providerId    = [string](_AiGetField -Obj $Preview -Name 'providerId' -Default '')
        modelId       = _AiGetField -Obj $Preview -Name 'modelId' -Default $null
        templateId    = [string](_AiGetField -Obj $Preview -Name 'templateId' -Default '')
        customPrompt  = _AiGetField -Obj $Preview -Name 'customPrompt' -Default $null
        scoreBefore   = [int](_AiGetField -Obj $score -Name 'before' -Default 0)
        scoreAfter    = [int](_AiGetField -Obj $score -Name 'after' -Default 0)
        scoreDelta    = [int](_AiGetField -Obj $score -Name 'delta' -Default 0)
        changeSummary = @(_AiGetField -Obj $Preview -Name 'changeSummary' -Default @() | ForEach-Object { [string]$_ })
        warningCount  = @(_AiGetField -Obj $Preview -Name 'warnings' -Default @()).Count
        # Token and cost, named to match the agent-run metrics vocabulary
        # (tokenUsage / apiSpendUsd) so the two series join without translation.
        # Null here means unmeasured; usageSource and costBasis say which kind.
        inputTokens   = _AiGetField -Obj $usage -Name 'inputTokens'  -Default $null
        outputTokens  = _AiGetField -Obj $usage -Name 'outputTokens' -Default $null
        tokenUsage    = _AiGetField -Obj $usage -Name 'totalTokens'  -Default $null
        usageMeasured = [bool](_AiGetField -Obj $usage -Name 'measured' -Default $false)
        usageSource   = [string](_AiGetField -Obj $usage -Name 'source' -Default $script:AiDocUsageSourceAbsent)
        apiSpendUsd   = _AiGetField -Obj $usage -Name 'costUsd'   -Default $null
        costBasis     = [string](_AiGetField -Obj $usage -Name 'costBasis' -Default 'usage-absent')
        applied       = $false
    }

    try {
        $json = ConvertTo-Json -InputObject $record -Compress -Depth 5
        Add-Content -LiteralPath (_AiHistoryFilePath -WorkspaceRoot $WorkspaceRoot -RepoName $repoName) -Value $json -Encoding UTF8 -ErrorAction Stop
    }
    catch {
        # Non-fatal — preview must succeed even when history cannot be written.
    }

    return [pscustomobject]$record
}

<#
.SYNOPSIS
    Read per-repo improvement-cycle history, newest first.
#>
function Get-AiDocImprovementHistory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$WorkspaceRoot,
        [Parameter(Mandatory = $true)][string]$RepoName,
        [Parameter()][string]$DocType = '',
        [Parameter()][int]$Limit = 20
    )

    $file = _AiHistoryFilePath -WorkspaceRoot $WorkspaceRoot -RepoName $RepoName
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { return @() }

    try {
        $items = @(
            Get-Content -LiteralPath $file -Encoding UTF8 -ErrorAction Stop |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                ForEach-Object {
                    try { ConvertFrom-Json -InputObject $_ } catch { $null }
                } |
                Where-Object { $null -ne $_ }
        )

        if (-not [string]::IsNullOrWhiteSpace($DocType)) {
            $wanted = $DocType.ToLowerInvariant()
            $items = @($items | Where-Object { [string](_AiGetField -Obj $_ -Name 'docType' -Default '') -eq $wanted })
        }

        # Sort on the raw value: ConvertFrom-Json (PS7) parses ISO timestamps into
        # [datetime], and casting those to [string] loses sub-second precision —
        # same-second records would tie and keep file (oldest-first) order.
        return @(
            $items |
                Sort-Object { _AiGetField -Obj $_ -Name 'createdAt' -Default ([datetime]::MinValue) } -Descending |
                Select-Object -First $Limit
        )
    }
    catch {
        return @()
    }
}

# ---------------------------------------------------------------------------
# Apply (explicit operator approval — Release 1.9 Phase 3)
# ---------------------------------------------------------------------------

function _AiSha256Hex {
    param([AllowEmptyString()][string]$Text)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes([string]$Text))
        return ([BitConverter]::ToString($bytes)).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

<#
.SYNOPSIS
    Write operator-approved proposed content to a README.md or ROADMAP.md,
    creating a backup of the current file and restore metadata first.
.DESCRIPTION
    This is the only function in this module that mutates a managed document,
    and it must only ever be invoked from the explicit apply route after
    operator approval. Before writing it:

      1. Refuses targets whose file name does not match the doc type
         (README.md / ROADMAP.md), so the apply surface cannot write
         arbitrary files.
      2. Copies the current content (when the file exists) to a timestamped
         backup under output/ai-doc-improvements/backups/<repo>/.
      3. Writes a restore-metadata JSON beside the backup with content
         hashes and a ready-to-run restore command.
      4. Appends an `apply` record to the same per-repo improvement-history
         JSONL the preview path uses (append-only; prior records are never
         rewritten).
.OUTPUTS
    [pscustomobject] apply receipt with backup and restore metadata paths.
#>
function Invoke-AiDocImproveApply {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)][string]$WorkspaceRoot,
        [Parameter(Mandatory = $true)][string]$RepoName,
        [Parameter(Mandatory = $true)][string]$TargetPath,
        [Parameter(Mandatory = $true)][string]$ProposedContent,
        [Parameter()][string]$DocType = 'readme',
        [Parameter()][string]$PreviewId = ''
    )

    $docType = if ($DocType -eq 'roadmap') { 'roadmap' } else { 'readme' }
    $expectedLeaf = if ($docType -eq 'roadmap') { 'ROADMAP.md' } else { 'README.md' }

    if ([string]::IsNullOrWhiteSpace($ProposedContent)) {
        throw 'proposedContent is empty; refusing to overwrite the target document with nothing.'
    }
    $leaf = Split-Path -Path $TargetPath -Leaf
    if (-not [string]::Equals($leaf, $expectedLeaf, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Apply target file name '$leaf' does not match the expected $docType file name '$expectedLeaf'."
    }
    $targetDir = Split-Path -Path $TargetPath -Parent
    if ([string]::IsNullOrWhiteSpace($targetDir) -or -not (Test-Path -LiteralPath $targetDir -PathType Container)) {
        throw "Apply target directory does not exist: $targetDir"
    }

    $applyId = [guid]::NewGuid().ToString('n')
    $now = (Get-Date).ToUniversalTime()
    $nowIso = $now.ToString('o')
    $stamp = $now.ToString('yyyyMMddTHHmmssfff') + 'Z'

    $safeRepoName = $RepoName -replace '[\\/:*?"<>|]', '_'
    $backupDir = Join-Path (Join-Path $WorkspaceRoot $script:AiDocBackupRelDir) $safeRepoName
    $null = New-Item -ItemType Directory -Path $backupDir -Force

    $originalExisted = Test-Path -LiteralPath $TargetPath -PathType Leaf
    $originalContent = ''
    $originalSha256 = $null
    $backupPath = $null

    if ($originalExisted) {
        $originalContent = Get-Content -LiteralPath $TargetPath -Raw -Encoding UTF8 -ErrorAction Stop
        $originalSha256 = _AiSha256Hex -Text $originalContent
        $backupPath = Join-Path $backupDir ("{0}.{1}.{2}.bak.md" -f $docType, $stamp, $applyId.Substring(0, 8))
        Set-Content -LiteralPath $backupPath -Value $originalContent -Encoding UTF8 -NoNewline -ErrorAction Stop
    }

    $appliedSha256 = _AiSha256Hex -Text $ProposedContent
    Set-Content -LiteralPath $TargetPath -Value $ProposedContent -Encoding UTF8 -NoNewline -ErrorAction Stop

    # Restore metadata: everything needed to undo this apply without the app.
    $restoreMetadataPath = Join-Path $backupDir ("{0}.{1}.{2}.restore.json" -f $docType, $stamp, $applyId.Substring(0, 8))
    $restoreMetadata = [ordered]@{
        applyId         = $applyId
        appliedAt       = $nowIso
        repoName        = $RepoName
        docType         = $docType
        targetPath      = [string]$TargetPath
        backupPath      = $backupPath
        originalExisted = [bool]$originalExisted
        originalSha256  = $originalSha256
        appliedSha256   = $appliedSha256
        previewId       = if ([string]::IsNullOrWhiteSpace($PreviewId)) { $null } else { $PreviewId }
        restoreCommand  = if ($null -ne $backupPath) {
            "Copy-Item -LiteralPath '$backupPath' -Destination '$TargetPath' -Force"
        }
        else {
            "Remove-Item -LiteralPath '$TargetPath' -Force  # file did not exist before this apply"
        }
    }
    try {
        ConvertTo-Json -InputObject $restoreMetadata -Depth 4 |
            Set-Content -LiteralPath $restoreMetadataPath -Encoding UTF8 -ErrorAction Stop
    }
    catch {
        $restoreMetadataPath = $null
    }

    # Append-only history record; never rewrite earlier preview records.
    $historyRecord = [ordered]@{
        previewId     = if ([string]::IsNullOrWhiteSpace($PreviewId)) { '' } else { $PreviewId }
        applyId       = $applyId
        recordType    = 'apply'
        createdAt     = $nowIso
        repoName      = $RepoName
        docType       = $docType
        providerId    = 'operator'
        modelId       = $null
        templateId    = ''
        customPrompt  = $null
        scoreBefore   = 0
        scoreAfter    = 0
        scoreDelta    = 0
        changeSummary = @(
            "Applied proposed $expectedLeaf to $TargetPath after explicit operator approval.",
            $(if ($null -ne $backupPath) { "Backup created at $backupPath" } else { "No backup created — target file did not exist before apply." })
        )
        warningCount  = 0
        applied       = $true
        backupPath    = $backupPath
        targetPath    = [string]$TargetPath
    }
    try {
        $json = ConvertTo-Json -InputObject $historyRecord -Compress -Depth 5
        Add-Content -LiteralPath (_AiHistoryFilePath -WorkspaceRoot $WorkspaceRoot -RepoName $RepoName) -Value $json -Encoding UTF8 -ErrorAction Stop
    }
    catch {
        # Non-fatal — the apply itself succeeded; history must not undo that fact.
    }

    return [pscustomobject]@{
        applyId             = $applyId
        repoName            = $RepoName
        docType             = $docType
        targetPath          = [string]$TargetPath
        backupPath          = $backupPath
        restoreMetadataPath = $restoreMetadataPath
        originalExisted     = [bool]$originalExisted
        originalSha256      = $originalSha256
        appliedSha256       = $appliedSha256
        previewId           = if ([string]::IsNullOrWhiteSpace($PreviewId)) { $null } else { $PreviewId }
        appliedAt           = $nowIso
    }
}
