<#
.SYNOPSIS
    Release 3.8 M3 — the Codex adapter. Turns a `codex exec --json` transcript
    into the same ExecutionResult the Claude adapter produces.

.DESCRIPTION
    Same posture as Adapter.Claude.ps1, and deliberately so: the runner should
    not be able to tell which provider produced a result by looking at its
    shape. This module builds argument vectors and parses output. It never
    launches a process — the runner is the operator session holding the
    credential and the working directory — which is what lets the whole thing
    be gated with no Codex installed, no network and no quota spent.

    **Two constants, both found by discovery rather than assumed.** Running the
    packet's discovery step over the fixture turned up two ambiguities that a
    loose match would have silently walked into:

      $script:CodexSessionIdProperty = 'thread_id', read at the TOP LEVEL only.
        The packet's `^(thread_id|session_id|id)$` also matches `item.id` one
        level down, four times — but those are item identifiers, not the
        thread. Resuming on an item id would resume nothing.

      $script:CodexResultTypeValue = 'turn.completed', matched EXACTLY.
        The packet's `final|result|completed` also matches `item.completed`,
        which appears four times before the real terminal object. A loose match
        picks the last `item.completed` and reports a finished turn that never
        finished. Exact match, last one wins.

    **The fixture is SYNTHETIC** — authored from the documented `codex exec
    --json` shape, not recorded, because no packet in this release may require
    spending subscription quota to produce a test input. So every field is read
    through a helper that tolerates absence: a transcript with no thread id, no
    usage, or an unfamiliar usage shape yields a VALID result with those parts
    null, never a throw and never a confidently wrong parse. Drop a real
    transcript in beside the synthetic one and the smoke asserts against both;
    any difference is a finding.

    **Sandbox is the only permission mapping here.** `--sandbox
    workspace-write` and nothing finer. Mapping the packet's permission
    envelope onto Codex's approval and sandbox policies waits on D-012 — the
    operator's ruling on what an agent may touch and whether it may edit
    workflow files. The envelope is rendered into the prompt, so the agent is
    told; it does not yet bind.

    **Capacity is not derived from token telemetry.** Get-CodexAdapterCapacity
    returns $null unconditionally, because the spec forbids equating Codex
    token counts with remaining subscription allowance. Tokens are rank-4
    consumption evidence, which is a different measurement; they travel on
    usage.native and Add-ProviderUsageObservation is what reads them.

.NOTES
    PowerShell 5.1 compatible. Param-less library: dot-source it, do not run it.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Found by discovery over tests\fixtures\providers\codex-exec-success.synthetic.jsonl.
# See the header for why each is matched the narrow way it is.
$script:CodexSessionIdProperty = 'thread_id'
$script:CodexResultTypeValue = 'turn.completed'

# NOT present in any fixture in this repository, and said so rather than
# implied: a failed turn is the documented sibling of turn.completed, so it is
# treated as terminal here, but nothing has proved that spelling. If a real
# transcript ever shows a different one, this is the line to correct.
$script:CodexFailureTypeValue = 'turn.failed'

function _Codex_Field {
    <#
        Read a field from a hashtable or a PSCustomObject, answering $Default
        when it is absent. Same shape as _Claude_Field; duplicated rather than
        shared so the adapter carries no load-order dependency on its sibling.
    #>
    param([object]$Obj, [string]$Name, [object]$Default = $null)
    if ($null -eq $Obj) { return $Default }
    if ($Obj -is [System.Collections.IDictionary]) {
        if ($Obj.Contains($Name) -and $null -ne $Obj[$Name]) { return $Obj[$Name] }
        return $Default
    }
    # The ForEach-Object rather than `.Properties.Name`: under
    # Set-StrictMode -Version Latest, member-access enumeration over an EMPTY
    # property collection throws "The property 'Name' cannot be found on this
    # object". An empty object is an ordinary input here -- a turn may report
    # no usage at all -- so this must answer "absent", not crash.
    if ($null -ne $Obj.PSObject -and (@($Obj.PSObject.Properties | ForEach-Object { $_.Name }) -contains $Name)) {
        $value = $Obj.$Name
        if ($null -ne $value) { return $value }
    }
    return $Default
}

<#
.SYNOPSIS
    The argument vector for a headless Codex run.

.DESCRIPTION
    Returns an ARRAY, never a command string, for the same reason the Claude
    adapter does: the prompt is multi-line roadmap text containing backticks,
    quotes and newlines, and flattening it for a shell to re-split is how one
    argument silently becomes several.

    The prompt goes LAST, after every flag, because `codex exec` takes it as a
    positional argument.
#>
function New-CodexExecutionArgument {
    [CmdletBinding()]
    [OutputType([string[]])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Pure: builds an argument array in memory and launches nothing. The runner is the only process that invokes.')]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Prompt,
        [Parameter(Mandatory)][string]$SchemaPath
    )
    return [string[]]@('exec', '--json', '--sandbox', 'workspace-write', '--output-schema', $SchemaPath, $Prompt)
}

<#
.SYNOPSIS
    Where the ExecutionResult JSON Schema lives, for --output-schema.
#>
function Get-CodexOutputSchemaPath {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter()][AllowEmptyString()][string]$WorkspaceRoot = '')
    $root = $WorkspaceRoot
    if ([string]::IsNullOrWhiteSpace($root)) { $root = (Get-Location).Path }
    return (Join-Path (Join-Path $root 'backend\config') 'execution-result.schema.json')
}

<#
.SYNOPSIS
    Parse a `codex exec --json` transcript. Records what it could not read
    instead of throwing on it.

.DESCRIPTION
    A single malformed line must not lose the whole transcript: the terminal
    turn object is the one thing worth recovering. Unparseable lines are
    counted by line number so a shape problem is diagnosable after the fact
    rather than invisible.
#>
function ConvertFrom-CodexJsonl {
    param([Parameter()][AllowEmptyCollection()][string[]]$Lines = @())

    $events = @()
    $parseErrors = @()
    $resultObject = $null
    $threadId = ''

    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $line = [string]$Lines[$i]
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $parsed = $null
        try { $parsed = ConvertFrom-Json -InputObject $line }
        catch { $parseErrors += ($i + 1); continue }
        if ($null -eq $parsed) { continue }
        $events += $parsed

        # Top level ONLY. `item.id` matches the same name one level down and is
        # an item identifier, not the thread -- see the header.
        if ([string]::IsNullOrWhiteSpace($threadId)) {
            $threadId = [string](_Codex_Field -Obj $parsed -Name $script:CodexSessionIdProperty -Default '')
        }

        # Exact match, not a pattern. `item.completed` would match a
        # `...completed` regex four times before the real terminal object.
        $type = [string](_Codex_Field -Obj $parsed -Name 'type' -Default '')
        if ($type -eq $script:CodexResultTypeValue -or $type -eq $script:CodexFailureTypeValue) {
            $resultObject = $parsed
        }
    }

    return [pscustomobject]@{
        result      = $resultObject
        threadId    = $threadId
        events      = @($events)
        parseErrors = @($parseErrors)
    }
}

<#
.SYNOPSIS
    Sum the token counts Codex reported, without inventing one.

.DESCRIPTION
    Adds every integer-valued property directly under `usage` whose name ends
    in `_tokens`. Returns $null rather than 0 when there are none: an unknown
    count and a count of zero are different claims.

    This is CONSUMPTION evidence, not allowance. Nothing here may be turned
    into a remaining-capacity ratio; see Get-CodexAdapterCapacity.
#>
function Get-CodexTokenTotal {
    param([Parameter()][object]$Usage = $null)

    if ($null -eq $Usage) { return $null }

    $names = @()
    if ($Usage -is [System.Collections.IDictionary]) { $names = @($Usage.Keys) }
    elseif ($null -ne $Usage.PSObject) { $names = @($Usage.PSObject.Properties | ForEach-Object { $_.Name }) }
    if ($names.Count -eq 0) { return $null }

    $total = 0
    $found = $false
    foreach ($name in $names) {
        if ([string]$name -notmatch '_tokens$') { continue }
        $value = _Codex_Field -Obj $Usage -Name ([string]$name) -Default $null
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
    The agent's closing message, unwrapped when it is structured.

.DESCRIPTION
    We invoke Codex with `--output-schema`, so a compliant run puts the
    ExecutionResult JSON in the final agent message rather than prose. Reading
    it raw would put a wall of JSON into the run summary an operator reads.

    So: if the last agent message parses as JSON carrying a `summary`, that is
    the summary. Otherwise the text itself is, because a model that ignored the
    schema still said something worth reading. Both paths are exercised by the
    smoke.
#>
function Get-CodexAgentMessage {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter()][AllowEmptyCollection()][object[]]$Events = @())

    $text = ''
    foreach ($evt in @($Events)) {
        $item = _Codex_Field -Obj $evt -Name 'item' -Default $null
        if ($null -eq $item) { continue }
        $itemType = [string](_Codex_Field -Obj $item -Name 'item_type' -Default '')
        if ($itemType -ne 'agent_message') { continue }
        $candidate = [string](_Codex_Field -Obj $item -Name 'text' -Default '')
        if (-not [string]::IsNullOrWhiteSpace($candidate)) { $text = $candidate }
    }

    if ([string]::IsNullOrWhiteSpace($text)) { return '' }

    $trimmed = $text.Trim()
    if ($trimmed.StartsWith('{')) {
        $structured = $null
        try { $structured = ConvertFrom-Json -InputObject $trimmed }
        catch { $structured = $null }
        if ($null -ne $structured) {
            $inner = [string](_Codex_Field -Obj $structured -Name 'summary' -Default '')
            if (-not [string]::IsNullOrWhiteSpace($inner)) { return $inner }
        }
    }

    return $text
}

<#
.SYNOPSIS
    Turn a parsed transcript into an ExecutionResult, or $null when there is no
    terminal turn to turn.

.DESCRIPTION
    $null is not an error here — it is H38-03's named failure path. A run whose
    transcript carries no terminal turn produced no structured answer, and
    Resolve-RunOutcomeFromResult is what says so.
#>
function ConvertTo-CodexExecutionResult {
    param(
        [Parameter(Mandatory)][object]$Parsed,
        [Parameter(Mandatory)][string]$TaskId,
        [Parameter(Mandatory)][string]$ExecutionId,
        [Parameter()][AllowEmptyCollection()][string[]]$ChangedFiles = @(),
        [Parameter()][object]$Config = $null
    )

    $resultObject = _Codex_Field -Obj $Parsed -Name 'result' -Default $null
    if ($null -eq $resultObject) { return $null }

    $type = [string](_Codex_Field -Obj $resultObject -Name 'type' -Default '')
    $isError = ($type -eq $script:CodexFailureTypeValue)
    $status = 'implementation_complete'
    if ($isError) { $status = 'implementation_failed' }

    $sessionId = [string](_Codex_Field -Obj $Parsed -Name 'threadId' -Default '')
    $usage = _Codex_Field -Obj $resultObject -Name 'usage' -Default $null

    $summary = Get-CodexAgentMessage -Events @(_Codex_Field -Obj $Parsed -Name 'events' -Default @())
    if ($isError) {
        # A failed turn carries its reason on the turn, not in an agent
        # message -- there may not be one at all.
        $errorObject = _Codex_Field -Obj $resultObject -Name 'error' -Default $null
        $errorText = [string](_Codex_Field -Obj $errorObject -Name 'message' -Default '')
        if ([string]::IsNullOrWhiteSpace($errorText)) { $errorText = [string](_Codex_Field -Obj $resultObject -Name 'message' -Default '') }
        if (-not [string]::IsNullOrWhiteSpace($errorText)) { $summary = $errorText }
    }
    if ($summary.Length -gt 500) { $summary = $summary.Substring(0, 500) }

    # A provider limit is STATE, not an execution failure (spec, and the §8
    # guardrail). Without this an exhausted subscription reads as
    # implementation_failed, which blames the roadmap item for the account's
    # condition and burns the attempt. Detection needs the configured
    # limitSignals, so it only runs when a caller supplied the config -- an
    # adapter that guessed at limit wording would be worse than one that
    # reports the plain failure it can actually see.
    $risks = @()
    if ($isError -and $null -ne $Config -and (Get-Command -Name 'Test-ProviderLimitSignal' -ErrorAction SilentlyContinue)) {
        $limit = Test-ProviderLimitSignal -Provider 'codex' -Text $summary -Config $Config
        if ($limit.matched) {
            $status = 'capacity_exhausted'
            $risks = @('provider-limit')
        }
    }

    return New-ExecutionResult `
        -Risks $risks `
        -TaskId $TaskId `
        -ExecutionId $ExecutionId `
        -Provider 'codex' `
        -ProviderSessionId $sessionId `
        -Status $status `
        -ChangedFiles @($ChangedFiles) `
        -UsageNative $usage `
        -TokensObserved (Get-CodexTokenTotal -Usage $usage) `
        -Summary $summary `
        -Source 'adapter'
}

<#
.SYNOPSIS
    Render a WorkPacket as the prompt Codex is given.

.DESCRIPTION
    The adapter is ALLOWED to reshape prompting for its provider but MUST NOT
    change the objective, scope, acceptance criteria or permission envelope —
    so it adds a heading and nothing else, exactly as the Claude adapter does.
#>
function ConvertTo-CodexPrompt {
    param([Parameter(Mandatory)][object]$Packet)
    $taskId = [string](_Codex_Field -Obj $Packet -Name 'taskId' -Default '')
    return ConvertTo-WorkPacketPrompt -Packet $Packet -Preamble ("# Task {0}" -f $taskId) -Postamble ''
}

# ---------------------------------------------------------------------------
# The A4 interface names — the same seven the Claude adapter carries, so the
# H38-15 conformance gate finds a complete set rather than a partial one.
# ---------------------------------------------------------------------------

function Get-CodexAdapterCapability {
    return [ordered]@{
        provider                 = 'codex'
        executionMode            = 'local'
        supportsResume           = $false
        supportsStructuredOutput = $true
    }
}

function Get-CodexAdapterCapacity {
    <#
    .SYNOPSIS
        Always $null. Codex reports tokens, and tokens are not allowance.

    .DESCRIPTION
        The spec is explicit: an adapter "MUST NOT equate Codex token telemetry
        with remaining subscription allowance". A turn reports input, cached and
        output token counts; none of them says how much of the subscription is
        left, and no ratio can be derived from them without inventing the
        denominator.

        So this refuses by construction rather than by omission. Unlike
        Get-ClaudeAdapterCapacity — which is a real reader that happens to find
        nothing in today's transcripts — there is no shape here worth looking
        for, and writing a speculative one would be an invitation to fill it in.

        $null means "not measured", which is honest. A fabricated ratio would be
        worse than no number at all: it is indistinguishable from a measured one
        at the moment the Governor decides whether to spend it.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '',
        Justification = 'Signature is fixed by the A4 adapter contract; the body must ignore its input, because deriving allowance from Codex token telemetry is forbidden by the spec.')]
    param([Parameter()][AllowNull()][object]$Parsed = $null)
    return $null
}

function Start-CodexExecution {
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
        [Parameter(Mandatory)][string]$SchemaPath
    )
    return New-CodexExecutionArgument -Prompt $Prompt -SchemaPath $SchemaPath
}

function Resume-CodexExecution {
    <#
        Refuses rather than guessing. `codex exec resume` takes a thread id, but
        the exact argv is not established by any transcript in this repository,
        and an adapter that guessed would produce a command that either fails
        loudly or -- far worse -- starts a NEW thread while reporting a resumed
        one. H38-29 supplies the fixture that settles it.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '',
        Justification = 'Signature is fixed by the A4 adapter contract so the H38-15 conformance gate finds a complete set; H38-29 supplies the body.')]
    param(
        [Parameter()][AllowEmptyString()][string]$SessionId = '',
        [Parameter()][AllowEmptyString()][string]$Prompt = '',
        [Parameter()][AllowEmptyString()][string]$SchemaPath = ''
    )
    throw 'Codex resume is fixture-gated (H38-29)'
}

function Stop-CodexExecution {
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Refuses unconditionally in 3.8; the Stop- verb is fixed by the A4 adapter contract. There is no state to confirm before changing.')]
    param()
    throw 'Not supported in 3.8: a local process is stopped by the runner'
}

function ConvertTo-CodexCanonicalEvent {
    <#
        H38-33 fills this with the spec's execution.* vocabulary. The parameter
        is named ProviderEvent rather than Event because $Event is a PowerShell
        automatic variable.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '',
        Justification = 'Signature is fixed by the A4 adapter contract so the H38-15 conformance gate finds a complete set; H38-33 supplies the body.')]
    param([Parameter()][object]$ProviderEvent = $null)
    return @()
}

function Get-CodexExecutionResult {
    param(
        [Parameter(Mandatory)][object]$Parsed,
        [Parameter(Mandatory)][string]$TaskId,
        [Parameter(Mandatory)][string]$ExecutionId,
        [Parameter()][AllowEmptyCollection()][string[]]$ChangedFiles = @()
    )
    return ConvertTo-CodexExecutionResult -Parsed $Parsed -TaskId $TaskId -ExecutionId $ExecutionId -ChangedFiles @($ChangedFiles)
}
