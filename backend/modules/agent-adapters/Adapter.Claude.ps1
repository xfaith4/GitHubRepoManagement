<#
.SYNOPSIS
    Release 3.8 M1 — the Claude Code adapter. Turns what the CLI actually
    emitted into the ExecutionResult the runner decides on.

.DESCRIPTION
    The runner used to read `$LASTEXITCODE` and nothing else. Running Claude
    Code with `--output-format stream-json` gives a machine-readable transcript
    instead, and this module is the only place that knows its shape.

    Everything here is pure. The adapter builds argument vectors and parses
    output; it never launches a process, because the runner is the operator
    session that holds the credential and the working directory. That split is
    what lets the whole thing be gated offline.

    **Defensive by requirement, not by habit.** The fixture this is developed
    against is SYNTHETIC — authored from the documented stream-json shape
    rather than recorded from a real run, because no packet in this release may
    require spending subscription quota to produce a test input. A synthetic
    fixture encodes an assumption, so every field is read through a helper that
    tolerates absence: a transcript missing `session_id`, missing `usage`, or
    carrying an unfamiliar `usage` shape yields a VALID result with those parts
    null, never a throw and never a confidently wrong parse. A real transcript,
    which appears for free at `<runId>.claude.stream.jsonl` after any headless
    run, can be dropped in beside the synthetic one; the smoke then asserts
    against both and any difference is a finding.

    Permission-envelope ENFORCEMENT is deliberately not here. Mapping the
    packet's envelope onto `--allowedTools` / `--disallowedTools` waits on
    D-012, which is the operator's ruling on what an agent may touch and
    whether it may edit workflow files. The envelope travels on every packet
    today; it does not yet bind.

.NOTES
    PowerShell 5.1 compatible. Param-less library: dot-source it, do not run it.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function _Claude_Field {
    <#
        Read a field from a hashtable or a PSCustomObject, answering $Default
        when it is absent. Same shape as _WP_Field; duplicated rather than
        shared so the adapter carries no load-order dependency on the
        execution module.
    #>
    param([object]$Obj, [string]$Name, [object]$Default = $null)
    if ($null -eq $Obj) { return $Default }
    if ($Obj -is [System.Collections.IDictionary]) {
        if ($Obj.Contains($Name) -and $null -ne $Obj[$Name]) { return $Obj[$Name] }
        return $Default
    }
    if ($null -ne $Obj.PSObject -and ($Obj.PSObject.Properties.Name -contains $Name)) {
        $value = $Obj.$Name
        if ($null -ne $value) { return $value }
    }
    return $Default
}

<#
.SYNOPSIS
    The argument vector for a headless Claude Code run.

.DESCRIPTION
    Returns an ARRAY, never a command string. The prompt is multi-line roadmap
    text containing backticks, quotes and newlines; flattening it into a string
    for a shell to re-split is how a prompt silently becomes several arguments.
#>
function New-ClaudeExecutionArgument {
    [CmdletBinding()]
    [OutputType([string[]])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Pure: builds an argument array in memory and launches nothing. The runner is the only process that invokes.')]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Prompt,
        [Parameter(Mandatory)][string]$PermissionMode
    )
    return [string[]]@('-p', $Prompt, '--output-format', 'stream-json', '--verbose', '--permission-mode', $PermissionMode)
}

<#
.SYNOPSIS
    The argument vector for resuming a previous session.
#>
function Resume-ClaudeExecution {
    param(
        [Parameter(Mandatory)][string]$SessionId,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Prompt,
        [Parameter(Mandatory)][string]$PermissionMode
    )
    return [string[]]@('-p', $Prompt, '--resume', $SessionId, '--output-format', 'stream-json', '--verbose', '--permission-mode', $PermissionMode)
}

<#
.SYNOPSIS
    Parse a stream-json transcript. Records what it could not read instead of
    throwing on it.

.DESCRIPTION
    A single malformed line must not lose the whole transcript: the terminal
    `result` object is the one thing worth recovering, and it is usually the
    last line. Unparseable lines are counted by line number so a shape problem
    is diagnosable after the fact rather than invisible.
#>
function ConvertFrom-ClaudeStreamJson {
    param([Parameter()][AllowEmptyCollection()][string[]]$Lines = @())

    $events = @()
    $parseErrors = @()
    $resultObject = $null

    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $line = [string]$Lines[$i]
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $parsed = $null
        try { $parsed = ConvertFrom-Json -InputObject $line }
        catch { $parseErrors += ($i + 1); continue }
        if ($null -eq $parsed) { continue }
        $events += $parsed
        # Last one wins: a transcript should carry exactly one terminal result,
        # and if a future format carries more the final one is the outcome.
        if ([string](_Claude_Field -Obj $parsed -Name 'type' -Default '') -eq 'result') {
            $resultObject = $parsed
        }
    }

    return [pscustomobject]@{
        result      = $resultObject
        events      = @($events)
        parseErrors = @($parseErrors)
    }
}

<#
.SYNOPSIS
    Sum the token counts a provider reported, without inventing one.

.DESCRIPTION
    Adds every integer-valued property directly under `usage` whose name ends
    in `_tokens`. Returns $null rather than 0 when there are none: an unknown
    count and a count of zero are different claims, and the spec forbids
    inventing a conversion for a subscription allowance.
#>
function Get-ClaudeTokenTotal {
    param([Parameter()][object]$Usage = $null)

    if ($null -eq $Usage) { return $null }

    # ForEach-Object rather than `.Properties.Name`: under
    # Set-StrictMode -Version Latest, member-access enumeration over an EMPTY
    # property collection throws. A provider that reports `"usage": {}` is
    # exactly the shape this function must answer $null for, not crash on.
    $names = @()
    if ($Usage -is [System.Collections.IDictionary]) { $names = @($Usage.Keys) }
    elseif ($null -ne $Usage.PSObject) { $names = @($Usage.PSObject.Properties | ForEach-Object { $_.Name }) }
    if ($names.Count -eq 0) { return $null }

    $total = 0
    $found = $false
    foreach ($name in $names) {
        if ([string]$name -notmatch '_tokens$') { continue }
        $value = _Claude_Field -Obj $Usage -Name ([string]$name) -Default $null
        if ($null -eq $value) { continue }
        $parsed = 0
        if ([int]::TryParse([string]$value, [ref]$parsed)) {
            $total += $parsed
            $found = $true
        }
    }

    if (-not $found) { return $null }
    return $total
}

<#
.SYNOPSIS
    Turn a parsed transcript into an ExecutionResult, or $null when there is
    no terminal result to turn.

.DESCRIPTION
    $null is not an error here — it is H38-03's named failure path. A run whose
    transcript carries no result object produced no structured answer, and
    Resolve-RunOutcomeFromResult is what says so.
#>
function ConvertTo-ClaudeExecutionResult {
    param(
        [Parameter(Mandatory)][object]$Parsed,
        [Parameter(Mandatory)][string]$TaskId,
        [Parameter(Mandatory)][string]$ExecutionId,
        [Parameter()][AllowEmptyCollection()][string[]]$ChangedFiles = @(),
        [Parameter()][object]$Config = $null
    )

    $resultObject = _Claude_Field -Obj $Parsed -Name 'result' -Default $null
    if ($null -eq $resultObject) { return $null }

    $isError = _Claude_Field -Obj $resultObject -Name 'is_error' -Default $false
    $status = 'implementation_complete'
    if ([bool]$isError) { $status = 'implementation_failed' }

    $sessionId = [string](_Claude_Field -Obj $resultObject -Name 'session_id' -Default '')
    $usage = _Claude_Field -Obj $resultObject -Name 'usage' -Default $null

    # `result` is the CLI's own summary text. Bounded because it lands in a run
    # summary an operator reads, not in a log.
    $summary = [string](_Claude_Field -Obj $resultObject -Name 'result' -Default '')
    if ($summary.Length -gt 500) { $summary = $summary.Substring(0, 500) }

    # A provider limit is STATE, not an execution failure (spec, and the §8
    # guardrail). Without this an exhausted subscription reads as
    # implementation_failed, which blames the roadmap item for the account's
    # condition and burns the attempt. Detection needs the configured
    # limitSignals, so it only runs when a caller supplied the config -- an
    # adapter that silently guessed at limit wording would be worse than one
    # that reports the plain failure it can actually see.
    $risks = @()
    if ([bool]$isError -and $null -ne $Config -and (Get-Command -Name 'Test-ProviderLimitSignal' -ErrorAction SilentlyContinue)) {
        $limit = Test-ProviderLimitSignal -Provider 'claude' -Text $summary -Config $Config
        if ($limit.matched) {
            $status = 'capacity_exhausted'
            $risks = @('provider-limit')
        }
    }

    return New-ExecutionResult `
        -Risks $risks `
        -TaskId $TaskId `
        -ExecutionId $ExecutionId `
        -Provider 'claude' `
        -ProviderSessionId $sessionId `
        -Status $status `
        -ChangedFiles @($ChangedFiles) `
        -UsageNative $usage `
        -TokensObserved (Get-ClaudeTokenTotal -Usage $usage) `
        -Summary $summary `
        -Source 'adapter'
}

<#
.SYNOPSIS
    Render a WorkPacket as the prompt Claude Code is given.

.DESCRIPTION
    Claude Code takes plain markdown, so the provider-neutral rendering needs
    no translation beyond a title. The adapter is ALLOWED to reshape prompting
    for its provider but MUST NOT change the objective, scope, acceptance
    criteria or permission envelope — so it adds a heading and nothing else.

    Note what this does not do: it does not map the packet's permission
    envelope onto --allowedTools / --disallowedTools. That enforcement waits on
    D-012, the operator's ruling on what an agent may touch and whether it may
    edit workflow files. The envelope is rendered into the prompt, so the agent
    is told; it is not yet enforced by the CLI.
#>
function ConvertTo-ClaudePrompt {
    param([Parameter(Mandatory)][object]$Packet)
    $taskId = [string](_Claude_Field -Obj $Packet -Name 'taskId' -Default '')
    return ConvertTo-WorkPacketPrompt -Packet $Packet -Preamble ("# Task {0}" -f $taskId) -Postamble ''
}

# ---------------------------------------------------------------------------
# The A4 interface names. Declared here so H38-15's conformance gate finds a
# complete set for `claude` rather than a partial one it has to special-case.
# ---------------------------------------------------------------------------

function Get-ClaudeAdapterCapability {
    return [ordered]@{
        provider                = 'claude'
        executionMode           = 'local'
        supportsResume          = $true
        supportsStructuredOutput = $true
    }
}

function Get-ClaudeAdapterCapacity {
    <#
    .SYNOPSIS
        A capacity window from a parsed stream-json transcript, or $null.

    .DESCRIPTION
        H38-12. Rank 3 on the spec's ladder -- "provider-reported warning or
        remaining percentage" -- read from whatever the CLI volunteered.

        **No transcript we have carries one.** The success and usage-limit
        fixtures expose only `usage` token counts, which are rank 4 evidence and
        a different measurement entirely (see Add-ProviderUsageObservation). So
        today this returns $null on every transcript in the repository, and the
        module smoke asserts exactly that rather than pretending otherwise.

        It is still written as a real reader rather than a hardcoded $null,
        because the shape it looks for is cheap to check and costs nothing when
        absent: if a future transcript does carry a remaining percentage, this
        starts working without anyone having to notice it could.

        $null means "not measured", which is honest. A fabricated ratio would be
        worse than no number at all -- it is indistinguishable from a measured
        one at the moment the Governor decides whether to spend it.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param([Parameter()][AllowNull()][object]$Parsed = $null)

    if ($null -eq $Parsed) { return $null }

    $candidates = @()
    if ($null -ne $Parsed.PSObject -and ($Parsed.PSObject.Properties.Name -contains 'events')) { $candidates += @($Parsed.events) }
    if ($null -ne $Parsed.PSObject -and ($Parsed.PSObject.Properties.Name -contains 'result')) { $candidates += @($Parsed.result) }

    foreach ($candidate in $candidates) {
        if ($null -eq $candidate -or $null -eq $candidate.PSObject) { continue }
        foreach ($property in @($candidate.PSObject.Properties | ForEach-Object { $_ })) {
            if ($property.Name -notmatch '(?i)remaining|limit|quota') { continue }

            $value = $property.Value
            # Only a bare number is usable. A string like "usage limit reached"
            # matches the name pattern and carries no ratio at all, which is
            # precisely the confusion this guard prevents.
            if ($value -isnot [double] -and $value -isnot [int] -and $value -isnot [long] -and $value -isnot [decimal]) { continue }

            $numeric = [double]$value
            if ($numeric -lt 0) { continue }
            # 0..1 is a ratio; 1..100 is a percentage. Above 100 is neither, and
            # is far more likely to be a token count that happened to be named
            # "limit" -- guessing at it would invent the number this refuses.
            if ($numeric -gt 100) { continue }
            $ratio = $(if ($numeric -gt 1) { $numeric / 100.0 } else { $numeric })

            return [ordered]@{
                name           = 'short-term'
                unit           = 'provider-allowance'
                remainingRatio = $ratio
                source         = 'provider-warning'
            }
        }
    }

    return $null
}

function Start-ClaudeExecution {
    <#
        Returns the argument vector; it does NOT launch. The runner is the
        process holding the credential and the working directory, and keeping
        the launch there is what allows this module to be gated with no
        provider, no network and no quota.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Returns an argument vector and starts nothing; the Start- verb is fixed by the A4 adapter contract.')]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Prompt,
        [Parameter(Mandatory)][string]$PermissionMode
    )
    return New-ClaudeExecutionArgument -Prompt $Prompt -PermissionMode $PermissionMode
}

function Stop-ClaudeExecution {
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Refuses unconditionally in 3.8; the Stop- verb is fixed by the A4 adapter contract. There is no state to confirm before changing.')]
    param()
    throw 'Not supported in 3.8: a local process is stopped by the runner'
}

function ConvertTo-ClaudeCanonicalEvent {
    <#
        H38-33 fills this with the spec's execution.* vocabulary. The parameter
        is named ProviderEvent rather than Event because $Event is a PowerShell
        automatic variable, and shadowing it inside an adapter that will later
        run within an eventing loop is a trap worth not setting.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '',
        Justification = 'Signature is fixed by the A4 adapter contract so the H38-15 conformance gate finds a complete set; H38-33 supplies the body.')]
    param([Parameter()][object]$ProviderEvent = $null)
    return @()
}

function Get-ClaudeExecutionResult {
    param(
        [Parameter(Mandatory)][object]$Parsed,
        [Parameter(Mandatory)][string]$TaskId,
        [Parameter(Mandatory)][string]$ExecutionId,
        [Parameter()][AllowEmptyCollection()][string[]]$ChangedFiles = @()
    )
    return ConvertTo-ClaudeExecutionResult -Parsed $Parsed -TaskId $TaskId -ExecutionId $ExecutionId -ChangedFiles @($ChangedFiles)
}
