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
$script:AiDocDefaultAnthropicModel = 'claude-opus-4-8'
$script:AiDocDefaultOpenAiModel    = 'gpt-4o'
$script:AiDocDefaultMaxTokens      = 8000
$script:AiDocHttpTimeoutSec        = 60

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
    } catch {
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

    $list = if ($DocType -eq 'roadmap') {
        @(_AiGetField -Obj $TemplatesConfig -Name 'roadmapTemplates' -Default @())
    } else {
        @(_AiGetField -Obj $TemplatesConfig -Name 'readmeTemplates' -Default @())
    }
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
    $openai    = _AiGetField -Obj $ai -Name 'openai' -Default $null

    return [pscustomobject]@{
        configuredProvider   = [string](_AiGetField -Obj $ai -Name 'provider' -Default 'auto')
        anthropicKeyEnvVar   = [string](_AiGetField -Obj $anthropic -Name 'apiKeyEnvVar' -Default 'ANTHROPIC_API_KEY')
        anthropicModel       = [string](_AiGetField -Obj $anthropic -Name 'model' -Default $script:AiDocDefaultAnthropicModel)
        anthropicMaxTokens   = [int](_AiGetField -Obj $anthropic -Name 'maxTokens' -Default $script:AiDocDefaultMaxTokens)
        openAiKeyEnvVar      = [string](_AiGetField -Obj $openai -Name 'apiKeyEnvVar' -Default 'OPENAI_API_KEY')
        openAiModel          = [string](_AiGetField -Obj $openai -Name 'model' -Default $script:AiDocDefaultOpenAiModel)
        openAiMaxTokens      = [int](_AiGetField -Obj $openai -Name 'maxTokens' -Default $script:AiDocDefaultMaxTokens)
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
    }
}

# ---------------------------------------------------------------------------
# Prompt construction for network providers
# ---------------------------------------------------------------------------

function _AiBuildSystemPrompt {
    param([string]$DocType)
    $docLabel = if ($DocType -eq 'roadmap') { 'ROADMAP.md' } else { 'README.md' }
    return @"
You are a documentation specialist improving a project's $docLabel file.
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
    if (-not [string]::IsNullOrWhiteSpace($Guidance)) {
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("Improvement intent:")
        [void]$sb.AppendLine($Guidance)
    }
    if (@($RequiredSections).Count -gt 0) {
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("The improved document should converge toward these sections where they make sense:")
        foreach ($s in @($RequiredSections)) { [void]$sb.AppendLine("- $s") }
    }
    if (-not [string]::IsNullOrWhiteSpace($CustomPrompt)) {
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("Additional operator instruction:")
        [void]$sb.AppendLine($CustomPrompt)
    }
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("Current document content:")
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

        return [pscustomobject]@{
            providerId      = 'anthropic'
            modelId         = $Model
            proposedContent = $text.Trim()
            changeSummary   = @("Document rewritten by Anthropic ($Model).")
            warnings        = @()
            error           = $null
        }
    } catch {
        return [pscustomobject]@{
            providerId      = 'anthropic'
            modelId         = $Model
            proposedContent = ''
            changeSummary   = @()
            warnings        = @()
            error           = "Anthropic provider call failed: $($_.Exception.Message)"
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

        return [pscustomobject]@{
            providerId      = 'openai'
            modelId         = $Model
            proposedContent = $text.Trim()
            changeSummary   = @("Document rewritten by OpenAI ($Model).")
            warnings        = @()
            error           = $null
        }
    } catch {
        return [pscustomobject]@{
            providerId      = 'openai'
            modelId         = $Model
            proposedContent = ''
            changeSummary   = @()
            warnings        = @()
            error           = "OpenAI provider call failed: $($_.Exception.Message)"
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
    } elseif ($requested -eq 'anthropic') {
        if ($availability.anthropic) { $selected = 'anthropic' }
        else { $warnings.Add('Anthropic provider requested but no API key is configured; falling back to the offline heuristic provider.') }
    } elseif ($requested -eq 'openai') {
        if ($availability.openai) { $selected = 'openai' }
        else { $warnings.Add('OpenAI provider requested but no API key is configured; falling back to the offline heuristic provider.') }
    } else {
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
        } else {
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

    # ---- Estimated score movement ----
    $scoreBefore = _AiSectionScore -Content $currentContent -RequiredSections $requiredSections
    $scoreAfter = _AiSectionScore -Content $proposedContent -RequiredSections $requiredSections

    return [pscustomobject]@{
        previewId        = $previewId
        repoName         = $RepoName
        docType          = $docType
        providerId       = [string]$result.providerId
        modelId          = $result.modelId
        templateId       = $effectiveTemplateId
        currentContent   = $currentContent
        proposedContent  = $proposedContent
        changeSummary    = @($result.changeSummary)
        estimatedScore   = [pscustomobject]@{
            before = $scoreBefore
            after  = $scoreAfter
            delta  = ($scoreAfter - $scoreBefore)
        }
        warnings         = @($warnings)
        generatedAt      = $now
    }
}
