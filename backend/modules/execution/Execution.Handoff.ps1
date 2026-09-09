<#
.SYNOPSIS
    Release 3.8 M5 — remediation and handoff. What happens after CI says no.

.DESCRIPTION
    H38-27 gave a run a durable attempt count. This module is what that count
    is for: turning a CI failure back into work, and deciding who does it.

    Three things live here, in the order the runner needs them.

    `New-RemediationPacket` turns evidence into a task. The failing checks
    become acceptance criteria in the agent's own contract language, so the
    next attempt is judged against "this check must pass" rather than against a
    paragraph describing a build log. The original criteria travel with it
    verbatim: a remediation that satisfied the CI check but abandoned the
    original objective is not a fix.

    `Resolve-RemediationRoute` decides between resuming the original session
    and handing the work to someone else. It is pure and it is deliberately
    conservative: anything it cannot establish becomes a handoff, never a
    resume. A resume against a session that is gone, or a provider whose
    adapter cannot resume, fails at launch after the capacity has already been
    spent; a handoff that was not strictly necessary merely costs a fresh
    context.

    `New-HandoffPacket` is the part the spec is most specific about, and the
    reason is worth keeping in view: **no provider may depend on another
    provider's conversation.** A transcript is not portable evidence. It is one
    model's reasoning in one model's format, and passing it to a second model
    invites it to adopt the first one's wrong turns as established fact. So the
    handoff carries durable artifacts only — the diff's file list, the CI
    failures, the structured result — and `Test-HandoffPacket` refuses a packet
    that smuggles a transcript through anyway.

.NOTES
    PowerShell 5.1 compatible. Param-less library: dot-source it, do not run it.
    Dot-source after Execution.ProviderRouter.ps1:
        . (Join-Path $executionModuleRoot 'Execution.Handoff.ps1')

    Depends on New-WorkPacket from Execution.WorkPacket.ps1 and, for routing,
    Resolve-ProviderCapacityVerdict from Execution.ProviderCapacity.ps1.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# The transcript rule's two halves. A key whose NAME says transcript, and a
# value long enough that nothing else it could plausibly be would reach it.
# 4,000 characters is far above any summary or risk line the ExecutionResult
# contract produces and far below a real transcript.
$script:HandoffTranscriptKeys = @('events', 'stream', 'lines', 'messages')
$script:HandoffMaxStringLength = 4000

# The spec's field list, in the spec's order. Kept as data because
# Test-HandoffPacket reports every missing key at once and the smoke asserts
# the count.
$script:HandoffPacketKeys = @(
    'taskId', 'attempt', 'previousProvider', 'objective', 'baseSha', 'headSha',
    'changedFiles', 'priorResult', 'ciFailures', 'acceptanceCriteria', 'remainingScope'
)

<#
.SYNOPSIS
    Read a field from a hashtable or a PSCustomObject, or return the default.
.DESCRIPTION
    Same shape and the same reason as _WP_Field in Execution.WorkPacket.ps1:
    every input here arrives either freshly built as an [ordered] hashtable or
    read back through ConvertFrom-Json as a PSCustomObject, and under
    Set-StrictMode member-access enumeration over an empty property collection
    throws rather than answering "absent".
#>
function _HO_Field {
    param([object]$Obj, [string]$Name, [object]$Default = $null)
    if ($null -eq $Obj) { return $Default }
    if ($Obj -is [System.Collections.IDictionary]) {
        if ($Obj.Contains($Name) -and $null -ne $Obj[$Name]) { return $Obj[$Name] }
        return $Default
    }
    if ($null -ne $Obj.PSObject -and (@($Obj.PSObject.Properties | ForEach-Object { $_.Name }) -contains $Name)) {
        $value = $Obj.$Name
        if ($null -ne $value) { return $value }
    }
    return $Default
}

<#
.SYNOPSIS
    Convert a permissions object back into the hashtable New-WorkPacket wants.
.DESCRIPTION
    The original packet's permission envelope is carried across unchanged. It
    is deliberately NOT widened for the remediation: a task that could not
    write to the filesystem on its first attempt has no better claim to it on
    its second, and a remediation is exactly the moment an agent is most
    tempted to reach for something it was not granted.
#>
function _HO_PermissionMap {
    param([object]$Permissions)
    $map = @{}
    foreach ($key in @('filesystemWrite', 'shell', 'network', 'githubWrite')) {
        $map[$key] = [bool](_HO_Field -Obj $Permissions -Name $key -Default $false)
    }
    return $map
}

<#
.SYNOPSIS
    Build a WorkPacket that asks for a CI failure to be fixed.

.DESCRIPTION
    Release 3.8 M5 (H38-28). The failing checks become acceptance criteria
    because that is the only form the rest of the system already knows how to
    carry: the prompt renderer prints them verbatim, the router reads the
    packet, and a later attempt is judged against them without anything
    needing to understand what a check run is.

    The original criteria are a SUPERSET, never a replacement. A remediation
    that turned the check green by deleting the test would satisfy the new
    criterion and fail the old ones, and the packet has to be able to say so.

    Two keys the WorkPacket schema does not name are added on purpose:
    `remediation`, which carries the evidence, and `execution.previousProvider`,
    which is what Resolve-RemediationRoute reads. Test-WorkPacket already
    ignores top-level keys it does not know, so this needs no schema change --
    verified against the H38-01 validator rather than assumed.

.OUTPUTS
    [System.Collections.Specialized.OrderedDictionary] a valid WorkPacket.
#>
function New-RemediationPacket {
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Pure constructor: builds and returns a packet in memory and touches nothing. Save-WorkPacket is the only writer, and the New- verb matches the M1 task contract.')]
    param(
        [Parameter(Mandatory)][object]$WorkPacket,
        [Parameter(Mandatory)][object]$AgentRun,
        [Parameter(Mandatory)][object]$Summary,
        [Parameter()][AllowEmptyCollection()][object[]]$CiFailures = @(),
        [Parameter()][AllowEmptyString()][string]$TaskId = ''
    )

    $branch = [string](_HO_Field -Obj $AgentRun -Name 'branch' -Default '')
    if ([string]::IsNullOrWhiteSpace($branch)) { $branch = '(unknown branch)' }

    $originalObjective = [string](_HO_Field -Obj $WorkPacket -Name 'objective' -Default '')
    $originalCriteria = @(_HO_Field -Obj $WorkPacket -Name 'acceptanceCriteria' -Default @())

    # Normalized first so the packet, the prompt and the smoke all read the
    # same three fields whatever the caller had available. With H-10 absent
    # there is one coarse entry per run; with it there is one per check, and
    # nothing downstream changes shape.
    $failures = [System.Collections.Generic.List[object]]::new()
    $appendedCriteria = [System.Collections.Generic.List[string]]::new()
    foreach ($failure in @($CiFailures)) {
        $name = [string](_HO_Field -Obj $failure -Name 'name' -Default '')
        $conclusion = [string](_HO_Field -Obj $failure -Name 'conclusion' -Default '')
        $url = [string](_HO_Field -Obj $failure -Name 'url' -Default '')
        if ([string]::IsNullOrWhiteSpace($name)) { $name = '(unnamed check)' }
        if ([string]::IsNullOrWhiteSpace($conclusion)) { $conclusion = 'unknown' }
        $failures.Add([ordered]@{ name = $name; conclusion = $conclusion; url = $url }) | Out-Null
        $appendedCriteria.Add(("CI check '{0}' must pass (was: {1})" -f $name, $conclusion)) | Out-Null
    }

    $scope = _HO_Field -Obj $WorkPacket -Name 'scope' -Default $null
    $verification = _HO_Field -Obj $WorkPacket -Name 'verification' -Default $null
    $execution = _HO_Field -Obj $WorkPacket -Name 'execution' -Default $null

    $attempt = [int](_HO_Field -Obj $Summary -Name 'attempt' -Default 1)
    $previousSessionId = [string](_HO_Field -Obj $Summary -Name 'providerSessionId' -Default '')

    # dispatchTarget is the fallback because a run dispatched before routing was
    # turned on recorded the target it was given and never a selection.
    $previousProvider = [string](_HO_Field -Obj $Summary -Name 'selectedProvider' -Default '')
    if ([string]::IsNullOrWhiteSpace($previousProvider)) {
        $previousProvider = [string](_HO_Field -Obj $Summary -Name 'dispatchTarget' -Default '')
    }

    $effectiveTaskId = $TaskId
    if ([string]::IsNullOrWhiteSpace($effectiveTaskId)) {
        $effectiveTaskId = [string](_HO_Field -Obj $WorkPacket -Name 'taskId' -Default '')
    }

    $packet = New-WorkPacket `
        -TaskId $effectiveTaskId `
        -Repository ([string](_HO_Field -Obj $WorkPacket -Name 'repository' -Default '')) `
        -BaseBranch ([string](_HO_Field -Obj $WorkPacket -Name 'baseBranch' -Default '')) `
        -BaseSha ([string](_HO_Field -Obj $WorkPacket -Name 'baseSha' -Default '')) `
        -Objective ('Remediate CI failure on {0}: {1}' -f $branch, $originalObjective) `
        -AllowedPaths @(_HO_Field -Obj $scope -Name 'allowedPaths' -Default @('**')) `
        -ForbiddenPaths @(_HO_Field -Obj $scope -Name 'forbiddenPaths' -Default @()) `
        -AcceptanceCriteria (@($originalCriteria) + @($appendedCriteria.ToArray())) `
        -VerificationCommands @(_HO_Field -Obj $verification -Name 'commands' -Default @()) `
        -Permissions (_HO_PermissionMap -Permissions (_HO_Field -Obj $WorkPacket -Name 'permissions' -Default $null)) `
        -Attempt ($attempt + 1) `
        -PreferredProvider ([string](_HO_Field -Obj $execution -Name 'preferredProvider' -Default 'auto')) `
        -PreviousSessionId $previousSessionId

    $packet['execution']['previousProvider'] = $previousProvider
    $packet['remediation'] = [ordered]@{
        ciFailures       = @($failures.ToArray())
        headSha          = [string](_HO_Field -Obj $AgentRun -Name 'prHeadSha' -Default '')
        remediationCount = [int](_HO_Field -Obj $Summary -Name 'remediationCount' -Default 0)
    }

    return $packet
}

<#
.SYNOPSIS
    Decide whether a remediation resumes its original session or is handed on.

.DESCRIPTION
    Release 3.8 M5 (H38-29). Pure: it reads records and answers, and the
    runner is what acts on the answer.

    Every uncertainty resolves to `handoff`. A missing adapter, an unreadable
    capability, an absent session id and an exhausted provider all mean the
    same thing here, which is "do not spend the original provider's capacity
    on a resume that may not work". `blocked` is reserved for the one case
    where there is genuinely nowhere for the work to go: no enabled provider
    at all.

    The reason is always populated, including on the resume path, because
    H38-17 established that a routing decision that cannot say why it was made
    is not reviewable.

.OUTPUTS
    [pscustomobject] mode ('resume'|'handoff'|'blocked'), provider, reason
#>
function Resolve-RemediationRoute {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][object]$Packet,
        [Parameter()][AllowEmptyCollection()][string[]]$Registry = @(),
        [Parameter()][AllowNull()][object]$CapacityRecords = $null,
        [Parameter()][AllowNull()][object]$Config = $null,
        [Parameter()][datetime]$NowUtc = [datetime]::UtcNow
    )

    $providersConfig = _HO_Field -Obj $Config -Name 'providers' -Default $null

    $enabled = [System.Collections.Generic.List[string]]::new()
    foreach ($candidate in @($Registry)) {
        $name = [string]$candidate
        if ([string]::IsNullOrWhiteSpace($name) -or $name -eq 'auto') { continue }
        $entry = _HO_Field -Obj $providersConfig -Name $name -Default $null
        if ([bool](_HO_Field -Obj $entry -Name 'supported' -Default $false)) { $enabled.Add($name) | Out-Null }
    }

    if ($enabled.Count -eq 0) {
        return [pscustomobject]@{ mode = 'blocked'; provider = ''; reason = 'no enabled provider' }
    }

    $execution = _HO_Field -Obj $Packet -Name 'execution' -Default $null
    $previousProvider = [string](_HO_Field -Obj $execution -Name 'previousProvider' -Default '')
    $previousSessionId = [string](_HO_Field -Obj $execution -Name 'previousSessionId' -Default '')

    if ([string]::IsNullOrWhiteSpace($previousProvider) -or -not $enabled.Contains($previousProvider)) {
        return [pscustomobject]@{ mode = 'handoff'; provider = ''; reason = 'previous provider is not enabled' }
    }

    if ([string]::IsNullOrWhiteSpace($previousSessionId)) {
        return [pscustomobject]@{ mode = 'handoff'; provider = ''; reason = 'no previous session' }
    }

    # An adapter that is not loaded is not a resumable one. Failing closed here
    # is the difference between a handoff and a launch that dies holding
    # capacity it already consumed.
    $supportsResume = $false
    $capabilityCommand = ('Get-{0}{1}AdapterCapability' -f $previousProvider.Substring(0, 1).ToUpperInvariant(), $previousProvider.Substring(1))
    $resolved = Get-Command -Name $capabilityCommand -ErrorAction SilentlyContinue
    if ($null -ne $resolved) {
        try { $supportsResume = [bool](_HO_Field -Obj (& $capabilityCommand) -Name 'supportsResume' -Default $false) }
        catch { $supportsResume = $false }
    }

    if (-not $supportsResume) {
        return [pscustomobject]@{ mode = 'handoff'; provider = ''; reason = 'provider does not support resume' }
    }

    # TaskClass remediation is what lets this draw on the weekly reserve
    # (D-011). A remediation blocked by a reserve set aside for remediation
    # would be the reserve defeating its own purpose.
    $record = _HO_Field -Obj $CapacityRecords -Name $previousProvider -Default $null
    $verdict = Resolve-ProviderCapacityVerdict `
        -Record $record `
        -Config $Config `
        -TaskClass 'remediation' `
        -NowUtc $NowUtc `
        -Provider $previousProvider

    if (-not [bool]$verdict.eligible) {
        return [pscustomobject]@{
            mode     = 'handoff'
            provider = ''
            reason   = ('capacity: {0}' -f [string]$verdict.reason)
        }
    }

    return [pscustomobject]@{
        mode     = 'resume'
        provider = $previousProvider
        reason   = ('resuming session on {0}' -f $previousProvider)
    }
}

<#
.SYNOPSIS
    Build the durable-evidence packet that crosses a provider boundary.

.DESCRIPTION
    Release 3.8 M5 (H38-30). The spec's eleven fields, and nothing else.

    `remainingScope` is every acceptance criterion. Release 3.8's
    ExecutionResult has no per-criterion satisfaction field, so there is no
    honest way to narrow it -- and narrowing it dishonestly would tell the next
    provider that work was finished when nothing checked. Lane 0.18's
    acceptance-check work is what would refine this; until then the wider
    answer is the true one.

.OUTPUTS
    [System.Collections.Specialized.OrderedDictionary] a HandoffPacket.
#>
function New-HandoffPacket {
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Pure constructor: builds and returns a packet in memory and touches nothing.')]
    param(
        [Parameter(Mandatory)][object]$RemediationPacket,
        [Parameter(Mandatory)][AllowNull()][object]$PriorResult,
        [Parameter()][AllowNull()][object]$Summary = $null
    )

    $execution = _HO_Field -Obj $RemediationPacket -Name 'execution' -Default $null
    $remediation = _HO_Field -Obj $RemediationPacket -Name 'remediation' -Default $null

    $previousProvider = [string](_HO_Field -Obj $execution -Name 'previousProvider' -Default '')
    if ([string]::IsNullOrWhiteSpace($previousProvider) -and $null -ne $Summary) {
        $previousProvider = [string](_HO_Field -Obj $Summary -Name 'selectedProvider' -Default '')
    }

    $criteria = @(_HO_Field -Obj $RemediationPacket -Name 'acceptanceCriteria' -Default @())

    return [ordered]@{
        taskId             = [string](_HO_Field -Obj $RemediationPacket -Name 'taskId' -Default '')
        attempt            = [int](_HO_Field -Obj $execution -Name 'attempt' -Default 1)
        previousProvider   = $previousProvider
        objective          = [string](_HO_Field -Obj $RemediationPacket -Name 'objective' -Default '')
        baseSha            = [string](_HO_Field -Obj $RemediationPacket -Name 'baseSha' -Default '')
        headSha            = [string](_HO_Field -Obj $remediation -Name 'headSha' -Default '')
        changedFiles       = @(_HO_Field -Obj $PriorResult -Name 'changedFiles' -Default @())
        priorResult        = $PriorResult
        ciFailures         = @(_HO_Field -Obj $remediation -Name 'ciFailures' -Default @())
        acceptanceCriteria = @($criteria)
        remainingScope     = @($criteria)
    }
}

<#
.SYNOPSIS
    Validate a HandoffPacket, including the rule that keeps transcripts out.

.DESCRIPTION
    Release 3.8 M5 (H38-30). Reports every error at once, same posture as
    Test-WorkPacket.

    The transcript rule is the one with teeth. A caller that attached a stream
    of provider events to `priorResult` would produce a packet that still
    validates against every field name in the spec while breaking the
    invariant the spec exists to protect. So the check is on shape rather than
    on intent: a key named like a transcript, or a string long enough that
    nothing in the ExecutionResult contract could legitimately be that long.

.OUTPUTS
    [pscustomobject] valid, errors
#>
function Test-HandoffPacket {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)][object]$Packet)

    $errors = [System.Collections.Generic.List[string]]::new()

    foreach ($key in $script:HandoffPacketKeys) {
        $value = _HO_Field -Obj $Packet -Name $key -Default $null
        if ($null -eq $value) { $errors.Add(('{0} is required' -f $key)) | Out-Null }
    }

    if ([string]::IsNullOrWhiteSpace([string](_HO_Field -Obj $Packet -Name 'taskId' -Default ''))) {
        $errors.Add('taskId must not be empty') | Out-Null
    }

    $priorResult = _HO_Field -Obj $Packet -Name 'priorResult' -Default $null
    if ($null -ne $priorResult) {
        $offending = [System.Collections.Generic.List[string]]::new()

        $names = @()
        if ($priorResult -is [System.Collections.IDictionary]) { $names = @($priorResult.Keys) }
        elseif ($null -ne $priorResult.PSObject) { $names = @($priorResult.PSObject.Properties | ForEach-Object { $_.Name }) }

        foreach ($name in $names) {
            if ($script:HandoffTranscriptKeys -contains [string]$name) { $offending.Add([string]$name) | Out-Null }
            $value = _HO_Field -Obj $priorResult -Name ([string]$name) -Default $null
            if ($value -is [string] -and $value.Length -gt $script:HandoffMaxStringLength) {
                $offending.Add([string]$name) | Out-Null
            }
        }

        if ($offending.Count -gt 0) {
            $errors.Add(('priorResult must not contain a transcript (offending: {0})' -f (($offending.ToArray() | Sort-Object -Unique) -join ', '))) | Out-Null
        }
    }

    return [pscustomobject]@{
        valid  = ($errors.Count -eq 0)
        errors = @($errors.ToArray())
    }
}

<#
.SYNOPSIS
    Render a HandoffPacket as the prompt a fresh provider session receives.

.DESCRIPTION
    Release 3.8 M5 (H38-30). The H38-05 rendering, plus one section describing
    what the previous attempt actually did.

    `-Packet` is optional and is the remediation WorkPacket the handoff was
    built from. When it is supplied the prompt is H38-05's rendering verbatim
    with the prior attempt appended as a postamble, so scope, verification and
    permissions reach the new provider unchanged. When it is absent the
    HandoffPacket alone carries only objective and criteria, and the prompt
    says so rather than inventing a scope.

.OUTPUTS
    [string] the prompt.
#>
function ConvertTo-HandoffPrompt {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][object]$HandoffPacket,
        [Parameter()][AllowNull()][object]$Packet = $null
    )

    $previousProvider = [string](_HO_Field -Obj $HandoffPacket -Name 'previousProvider' -Default '')
    if ([string]::IsNullOrWhiteSpace($previousProvider)) { $previousProvider = 'unknown provider' }

    $priorLines = [System.Collections.Generic.List[string]]::new()
    $priorLines.Add(('## Prior attempt ({0})' -f $previousProvider)) | Out-Null
    $priorLines.Add('') | Out-Null
    $priorLines.Add('A previous attempt on this task did not pass CI. Its conversation is deliberately not included; treat the facts below as the only record of it.') | Out-Null
    $priorLines.Add('') | Out-Null

    $priorLines.Add('Files it changed:') | Out-Null
    $changedFiles = @(_HO_Field -Obj $HandoffPacket -Name 'changedFiles' -Default @())
    if ($changedFiles.Count -eq 0) { $priorLines.Add('- (none recorded)') | Out-Null }
    else { foreach ($file in $changedFiles) { $priorLines.Add(('- {0}' -f [string]$file)) | Out-Null } }
    $priorLines.Add('') | Out-Null

    $priorLines.Add('CI failures:') | Out-Null
    $ciFailures = @(_HO_Field -Obj $HandoffPacket -Name 'ciFailures' -Default @())
    if ($ciFailures.Count -eq 0) { $priorLines.Add('- (none recorded)') | Out-Null }
    else {
        foreach ($failure in $ciFailures) {
            $priorLines.Add(('- {0}: {1}' -f
                [string](_HO_Field -Obj $failure -Name 'name' -Default '(unnamed check)'),
                [string](_HO_Field -Obj $failure -Name 'conclusion' -Default 'unknown'))) | Out-Null
        }
    }
    $priorLines.Add('') | Out-Null

    $priorSummary = [string](_HO_Field -Obj (_HO_Field -Obj $HandoffPacket -Name 'priorResult' -Default $null) -Name 'summary' -Default '')
    $priorLines.Add('What it reported:') | Out-Null
    $priorLines.Add($(if ([string]::IsNullOrWhiteSpace($priorSummary)) { '- (no summary recorded)' } else { ('- {0}' -f $priorSummary) })) | Out-Null

    $postamble = ($priorLines.ToArray() -join "`n")

    if ($null -ne $Packet) {
        return ConvertTo-WorkPacketPrompt -Packet $Packet -Postamble $postamble
    }

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('## Objective') | Out-Null
    $lines.Add('') | Out-Null
    $lines.Add([string](_HO_Field -Obj $HandoffPacket -Name 'objective' -Default '')) | Out-Null
    $lines.Add('') | Out-Null
    $lines.Add('## Acceptance Criteria') | Out-Null
    $lines.Add('') | Out-Null
    $criteria = @(_HO_Field -Obj $HandoffPacket -Name 'acceptanceCriteria' -Default @())
    if ($criteria.Count -eq 0) { $lines.Add('- (none declared)') | Out-Null }
    else { foreach ($criterion in $criteria) { $lines.Add(('- {0}' -f [string]$criterion)) | Out-Null } }
    $lines.Add('') | Out-Null
    $lines.Add($postamble) | Out-Null

    return ($lines.ToArray() -join "`n")
}

<#
.SYNOPSIS
    Is this packet a remediation of an earlier attempt?
.DESCRIPTION
    One definition, because the runner, the reconcile tick and the smoke all
    have to agree on it. The `remediation` key is what New-RemediationPacket
    adds and what nothing else produces.
.OUTPUTS
    [bool]
#>
function Test-WorkPacketIsRemediation {
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter()][AllowNull()][object]$Packet = $null)
    return ($null -ne (_HO_Field -Obj $Packet -Name 'remediation' -Default $null))
}

<#
.SYNOPSIS
    What the runner does next with a remediation, in the order it must decide it.

.DESCRIPTION
    Release 3.8 M5 (H38-29). Pure, and the ORDER is the point.

    The cap is evaluated FIRST and beats everything, including a route that
    would otherwise resume happily. That ordering is the whole difference
    between a bounded remediation loop and an unbounded one: a runner that
    resolved the route first would build an argument vector, launch a provider
    and consume capacity before discovering the attempt was never allowed.

    Because it is pure, the smoke can assert that ordering directly rather than
    inferring it from a live run -- hand it a cap-reached verdict together with
    a resume-eligible route and the answer must still be halt, with no provider
    named to launch.

.OUTPUTS
    [pscustomobject] action ('halt'|'resume'|'handoff'|'blocked'), provider, sessionId, reason
#>
function Resolve-RemediationLaunch {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][object]$Packet,
        [Parameter()][AllowNull()][object]$CapVerdict = $null,
        [Parameter()][AllowNull()][object]$Route = $null
    )

    # 1. The cap, before anything that could spend capacity.
    if ($null -ne $CapVerdict -and [bool](_HO_Field -Obj $CapVerdict -Name 'reached' -Default $false)) {
        return [pscustomobject]@{
            action    = 'halt'
            provider  = ''
            sessionId = ''
            reason    = 'remediation-cap-reached'
        }
    }

    $mode = [string](_HO_Field -Obj $Route -Name 'mode' -Default '')
    $reason = [string](_HO_Field -Obj $Route -Name 'reason' -Default '')

    if ($mode -eq 'resume') {
        $execution = _HO_Field -Obj $Packet -Name 'execution' -Default $null
        return [pscustomobject]@{
            action    = 'resume'
            provider  = [string](_HO_Field -Obj $Route -Name 'provider' -Default '')
            sessionId = [string](_HO_Field -Obj $execution -Name 'previousSessionId' -Default '')
            reason    = $reason
        }
    }

    if ($mode -eq 'handoff') {
        return [pscustomobject]@{ action = 'handoff'; provider = ''; sessionId = ''; reason = $reason }
    }

    # An unrecognized mode is treated as blocked rather than as permission to
    # run: a route this function does not understand is not a route.
    return [pscustomobject]@{
        action    = 'blocked'
        provider  = ''
        sessionId = ''
        reason    = $(if ([string]::IsNullOrWhiteSpace($reason)) { 'no route resolved' } else { $reason })
    }
}
