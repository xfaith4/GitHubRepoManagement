<#
.SYNOPSIS
    Release 3.8 M4 (H38-24b) — when a run needs a second pair of eyes, and
    whose.

.DESCRIPTION
    The spec asks for independent review between CI_PASSED and
    READY_FOR_OPERATOR. "Independent" is the entire value: a provider reviewing
    its own work re-reads its own assumptions and agrees with them. So the
    eligible set is every provider EXCEPT the implementer, and `auto` is never
    in it -- `auto` is an instruction to choose, not something that can hold an
    opinion.

    Spending a review is not free, so the rule has to be worth its cost. Low
    risk never buys one; a rule that fired on everything would be a tax, and
    would train an operator to route around it. High risk always does. Medium
    is the interesting case, and it buys a review only where something
    specific says the change is not as small as it looks.

    The medium-risk diff threshold is PROVISIONAL. Nobody has measured the
    right number, and D-011's lesson is that an unmeasured number must not
    silently enforce -- so it lives in config, is marked provisional there, and
    the reason string names the value that fired, which is what makes it
    arguable rather than mysterious.

    This module decides. It does not dispatch: H38-30 owns redispatch, and a
    second dispatcher living here is the thing that would make the review stage
    impossible to reason about.
#>

Set-StrictMode -Version Latest

$script:ReviewPolicyDefaultDiffLines = 200

function Get-ReviewPolicyDiffThreshold {
    <#
    .SYNOPSIS
        The configured medium-risk diff threshold, or the documented default.
    .OUTPUTS
        [int]
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter()][string]$WorkspaceRoot = ''
    )

    if ([string]::IsNullOrWhiteSpace($WorkspaceRoot)) { return $script:ReviewPolicyDefaultDiffLines }

    $configPath = Join-Path $WorkspaceRoot 'backend\config\agent-providers.json'
    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) { return $script:ReviewPolicyDefaultDiffLines }

    try {
        $config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($null -ne $config.review -and $null -ne $config.review.mediumRiskDiffLines) {
            $configured = [int]$config.review.mediumRiskDiffLines
            if ($configured -gt 0) { return $configured }
        }
    }
    catch {
        # A half-saved config must not crash a policy decision -- fall through
        # to the documented default. Recorded rather than swallowed: a
        # threshold silently reverting to 200 is exactly the kind of change
        # nobody notices until it matters.
        Write-Verbose ("review policy: could not read '{0}', using the default threshold: {1}" -f $configPath, $_.Exception.Message)
    }

    return $script:ReviewPolicyDefaultDiffLines
}

function Resolve-ReviewImplementerToken {
    <#
    .SYNOPSIS
        Normalise whatever a caller has into a provider TOKEN.

    .DESCRIPTION
        The agent-run ledger records `providerTool` -- `claude-code`,
        `codex-cli`, `github-copilot-agent` -- which is not the token the
        registry speaks (`claude`, `codex`, `copilot`). Comparing the two
        directly never matches, so the implementer would silently stay in its
        own eligible-reviewer list and the independence this whole policy buys
        would be worth nothing. It would also fail SILENTLY: the refusal still
        appears, still names reviewers, and one of them is the author.

        Accepts either form and returns the token, or the input lower-cased
        when nothing matches -- never a guess dressed as a match.
    .OUTPUTS
        [string]
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()][string]$Value = '',
        [Parameter()][string]$WorkspaceRoot = ''
    )

    $normalized = ([string]$Value).Trim().ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($normalized)) { return '' }

    # Guarded BEFORE Join-Path: it throws on an empty root rather than
    # returning nothing, which would turn "no workspace given" into a crash.
    if ([string]::IsNullOrWhiteSpace($WorkspaceRoot)) { return $normalized }
    $configPath = Join-Path $WorkspaceRoot 'backend\config\agent-providers.json'
    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) { return $normalized }

    try {
        $config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($name in @($config.providers.PSObject.Properties.Name)) {
            if ($name.ToLowerInvariant() -eq $normalized) { return $name.ToLowerInvariant() }
            $tool = [string]$config.providers.$name.providerTool
            if (-not [string]::IsNullOrWhiteSpace($tool) -and $tool.ToLowerInvariant() -eq $normalized) {
                return $name.ToLowerInvariant()
            }
        }
    }
    catch {
        # Unreadable config means the token cannot be confirmed. Returning the
        # input unchanged is the safe answer: it will simply fail to match a
        # provider, which removes nobody from the reviewer set rather than
        # removing the wrong one.
        Write-Verbose ("review policy: could not resolve '{0}' to a provider token: {1}" -f $normalized, $_.Exception.Message)
    }

    return $normalized
}

function Resolve-ReviewRequirement {
    <#
    .SYNOPSIS
        Pure - does this run need an independent review, and who could give it?

    .DESCRIPTION
        Risk decides whether the question is even asked:

          low    - never. Whatever else is true.
          high   - always. Whatever else is true.
          medium - only on a named trigger: verification did not complete, the
                   diff is larger than the configured threshold, the
                   implementer's own confidence was LOW, or architecture
                   changed.

        Each medium trigger fires independently. That matters: a rule reading
        "all four" would almost never fire, and one reading "any" only works if
        each condition is genuinely sufficient on its own -- which is why the
        gate asserts them separately.

        The reason always says why, including for a "no". An operator who
        cannot see the cause cannot disagree with it, and a rule nobody can
        argue with is a rule nobody trusts.
    .OUTPUTS
        [pscustomobject] required, reason, eligibleReviewers
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()][string]$Risk = 'low',
        [Parameter()][string]$Implementer = '',
        [Parameter()][int]$DiffLines = 0,
        [Parameter()][bool]$VerificationComplete = $true,
        [Parameter()][string]$Confidence = '',
        [Parameter()][bool]$ArchitectureChanged = $false,
        [Parameter()][int]$MediumRiskDiffLines = 0,
        [Parameter()][string]$WorkspaceRoot = ''
    )

    $threshold = $MediumRiskDiffLines
    if ($threshold -le 0) { $threshold = Get-ReviewPolicyDiffThreshold -WorkspaceRoot $WorkspaceRoot }

    # Every provider except the implementer, and never `auto`. Computed even
    # when no review is required, so a caller can show who WOULD review without
    # asking a second question.
    $tokens = @('claude', 'codex', 'copilot')
    if (Get-Command -Name 'Get-AgentProviderToken' -ErrorAction SilentlyContinue) {
        $tokens = @(Get-AgentProviderToken -WorkspaceRoot $WorkspaceRoot)
    }
    # Normalised through the registry: the ledger says `claude-code` where the
    # registry says `claude`, and an unmatched implementer would quietly remain
    # eligible to review its own work.
    $normalizedImplementer = Resolve-ReviewImplementerToken -Value $Implementer -WorkspaceRoot $WorkspaceRoot
    $eligible = @($tokens | Where-Object {
        $_ -ne 'auto' -and $_.ToLowerInvariant() -ne $normalizedImplementer
    })

    $normalizedRisk = ([string]$Risk).Trim().ToLowerInvariant()
    $required = $false
    $reason = ''

    switch ($normalizedRisk) {
        'high' {
            $required = $true
            $reason = 'High-risk change: an independent review is always required before an operator is asked to approve.'
        }
        'medium' {
            $triggers = New-Object System.Collections.Generic.List[string]
            if (-not $VerificationComplete) { $triggers.Add('verification did not complete') }
            if ($DiffLines -gt $threshold) { $triggers.Add(("the diff is {0} lines, over the configured threshold of {1}" -f $DiffLines, $threshold)) }
            if (([string]$Confidence).Trim().ToUpperInvariant() -eq 'LOW') { $triggers.Add('the implementer reported LOW confidence') }
            if ($ArchitectureChanged) { $triggers.Add('architecture changed') }

            if ($triggers.Count -gt 0) {
                $required = $true
                $reason = ('Medium-risk change, and {0}.' -f ($triggers.ToArray() -join '; '))
            }
            else {
                $reason = ('Medium-risk change with no review trigger: verification completed, the diff is within {0} lines, confidence was not LOW, and architecture did not change.' -f $threshold)
            }
        }
        default {
            $reason = 'Low-risk change: review is not required regardless of diff size, confidence or verification state.'
        }
    }

    return [pscustomobject]@{
        required          = $required
        reason            = $reason
        eligibleReviewers = $eligible
    }
}
