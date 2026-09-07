<#
.SYNOPSIS
    Release 3.8 M1 — the provider-neutral task contract. What an agent is asked
    to do, expressed the same way whatever engine ends up doing it.

.DESCRIPTION
    Until this module existed, the only agent-facing artifact a dispatch
    produced was `generatedPrompt`, a string built by `Build-ReleaseDispatchPacket`
    in `backend\modules\roadmap\Roadmap.Dispatcher.ps1`. Prose is a fine thing
    to send a model and a terrible thing to orchestrate on: nothing can read a
    scope boundary out of a paragraph, compare two attempts, or hand the same
    task to a different provider without rewriting it.

    A `WorkPacket` is that task as data. It names the objective, the paths the
    agent may and may not touch, the criteria that decide whether the work is
    done, the commands that verify it, and the permission envelope it runs
    under. It names **no provider**. Which engine executes it is the scheduler's
    decision, made later and recorded separately, which is the core invariant
    the execution governance spec exists to protect.

    Persistence is deliberate and deliberately placed. The packet is written
    under `output\work-packets\`, which is gitignored — the spec requires the
    packet to live outside files eligible for commit, so that an agent editing
    its own repository can never accidentally commit, and therefore never
    accidentally rewrite, the instructions it was given.

    Validation is separate from construction on purpose. `New-WorkPacket`
    records what it was handed rather than coercing it, so a caller that omits
    a permission gets an error from `Test-WorkPacket` instead of a silent
    `$false` that reads as a deliberate denial.

.NOTES
    PowerShell 5.1 compatible. Param-less library: dot-source it, do not run it.
    Dot-source after Execution.LaneObservation.ps1:
        . (Join-Path $executionModuleRoot 'Execution.WorkPacket.ps1')
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Bump only for a breaking shape change, and only alongside a reader that can
# still open version 1 — a packet on disk outlives the process that wrote it.
$script:WorkPacketSchemaVersion = 1

<#
.SYNOPSIS
    Read a named field from either a hashtable or a PSCustomObject.

.DESCRIPTION
    A packet arrives as an [ordered] hashtable when it was just built and as a
    PSCustomObject when it came back through ConvertFrom-Json. Every reader
    here has to accept both, so none of them may use a bare property access.
    Same shape as _LaneObs_Field in Execution.LaneObservation.ps1.
#>
function _WP_Field {
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
    Build a WorkPacket. Provider-neutral by construction — nothing here names
    an engine except the caller's own preference, which the scheduler may
    override.

.DESCRIPTION
    Permission values are stored exactly as supplied rather than cast to
    [bool]. A missing key must reach Test-WorkPacket as an error; casting it
    would turn "the caller forgot" into "the caller denied it", which is the
    same value with a completely different meaning.

.PARAMETER Repository
    `owner/repo`, or '' for work with no GitHub counterpart. An empty value is
    also what makes a packet ineligible for a GitHub-hosted provider later.

.PARAMETER PreviousSessionId
    The session this attempt resumes. Stored as $null when absent, never '',
    so a consumer can distinguish "no previous session" from "a session whose
    id we failed to record".
#>
function New-WorkPacket {
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Pure constructor: builds and returns a packet in memory and touches nothing. Save-WorkPacket is the only writer, and the New- verb is fixed by the M1 task contract.')]
    param(
        [Parameter(Mandatory)][string]$TaskId,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Repository,
        # Empty is legitimate and is not the same as missing: the queue entry
        # has always allowed it, and a local task with no declared base branches
        # from whatever is checked out. H38-01 shipped this mandatory and
        # non-empty; H38-02's packaging caller is the real case that showed the
        # constraint was wrong. Inventing 'main' here would branch some repository
        # off the wrong base one day, silently.
        [Parameter(Mandatory)][AllowEmptyString()][string]$BaseBranch,
        [Parameter(Mandatory)][AllowEmptyString()][string]$BaseSha,
        [Parameter(Mandatory)][string]$Objective,
        [string[]]$AllowedPaths = @('**'),
        [string[]]$ForbiddenPaths = @(),
        [string[]]$AcceptanceCriteria = @(),
        [string[]]$VerificationCommands = @(),
        [Parameter(Mandatory)][hashtable]$Permissions,
        [int]$Attempt = 1,
        [string]$PreferredProvider = 'auto',
        [AllowEmptyString()][string]$PreviousSessionId = ''
    )

    $sessionId = $null
    if (-not [string]::IsNullOrWhiteSpace($PreviousSessionId)) {
        $sessionId = [string]$PreviousSessionId
    }

    return [ordered]@{
        schemaVersion      = $script:WorkPacketSchemaVersion
        taskId             = [string]$TaskId
        repository         = [string]$Repository
        baseBranch         = [string]$BaseBranch
        baseSha            = [string]$BaseSha
        objective          = [string]$Objective
        scope              = [ordered]@{
            allowedPaths   = @($AllowedPaths)
            forbiddenPaths = @($ForbiddenPaths)
        }
        acceptanceCriteria = @($AcceptanceCriteria)
        verification       = [ordered]@{
            commands = @($VerificationCommands)
        }
        permissions        = [ordered]@{
            filesystemWrite = (_WP_Field -Obj $Permissions -Name 'filesystemWrite' -Default $null)
            shell           = (_WP_Field -Obj $Permissions -Name 'shell' -Default $null)
            network         = (_WP_Field -Obj $Permissions -Name 'network' -Default $null)
            githubWrite     = (_WP_Field -Obj $Permissions -Name 'githubWrite' -Default $null)
        }
        execution          = [ordered]@{
            attempt           = [int]$Attempt
            preferredProvider = [string]$PreferredProvider
            previousSessionId = $sessionId
        }
    }
}

<#
.SYNOPSIS
    Validate a WorkPacket. Returns every error at once rather than the first.

.DESCRIPTION
    Reports all failures in one pass because the caller is usually a dispatch
    route with one chance to tell an operator what is wrong. Accepts a freshly
    built [ordered] hashtable or one read back from JSON.
#>
function Test-WorkPacket {
    param([Parameter(Mandatory)][object]$Packet)

    $errors = @()

    $schemaVersion = _WP_Field -Obj $Packet -Name 'schemaVersion' -Default $null
    $schemaOk = $false
    if ($null -ne $schemaVersion) {
        $parsedSchema = 0
        if ([int]::TryParse([string]$schemaVersion, [ref]$parsedSchema)) {
            if ($parsedSchema -eq $script:WorkPacketSchemaVersion) { $schemaOk = $true }
        }
    }
    if (-not $schemaOk) { $errors += 'schemaVersion must be 1' }

    if ([string]::IsNullOrWhiteSpace([string](_WP_Field -Obj $Packet -Name 'taskId' -Default ''))) {
        $errors += 'taskId is required'
    }

    if ([string]::IsNullOrWhiteSpace([string](_WP_Field -Obj $Packet -Name 'objective' -Default ''))) {
        $errors += 'objective is required'
    }

    $scope = _WP_Field -Obj $Packet -Name 'scope' -Default $null
    $allowedPaths = @(_WP_Field -Obj $scope -Name 'allowedPaths' -Default @())
    if ($allowedPaths.Count -eq 0) { $errors += 'scope.allowedPaths must be a non-empty array' }

    # One error per key, so a caller that omitted two of them is told about
    # both instead of fixing one and being refused again.
    $permissions = _WP_Field -Obj $Packet -Name 'permissions' -Default $null
    foreach ($permissionKey in @('filesystemWrite', 'shell', 'network', 'githubWrite')) {
        $permissionValue = _WP_Field -Obj $permissions -Name $permissionKey -Default $null
        if ($permissionValue -isnot [bool]) {
            $errors += ('permissions.{0} must be a boolean' -f $permissionKey)
        }
    }

    $execution = _WP_Field -Obj $Packet -Name 'execution' -Default $null

    $attempt = _WP_Field -Obj $execution -Name 'attempt' -Default $null
    $attemptOk = $false
    if ($null -ne $attempt) {
        $parsedAttempt = 0
        if ([int]::TryParse([string]$attempt, [ref]$parsedAttempt)) {
            if ($parsedAttempt -ge 1) { $attemptOk = $true }
        }
    }
    if (-not $attemptOk) { $errors += 'execution.attempt must be an integer >= 1' }

    if ([string]::IsNullOrWhiteSpace([string](_WP_Field -Obj $execution -Name 'preferredProvider' -Default ''))) {
        $errors += 'execution.preferredProvider is required'
    }

    return [pscustomobject]@{
        valid  = ($errors.Count -eq 0)
        errors = @($errors)
    }
}

<#
.SYNOPSIS
    Where a task's packet lives. Under output\, which is gitignored — the spec
    requires the packet to sit outside files eligible for commit.
#>
function Get-WorkPacketPath {
    param(
        [Parameter(Mandatory)][string]$WorkspaceRoot,
        [Parameter(Mandatory)][string]$TaskId
    )
    return (Join-Path $WorkspaceRoot ('output\work-packets\{0}.workpacket.json' -f $TaskId))
}

<#
.SYNOPSIS
    Persist a packet, refusing to write an invalid one.

.DESCRIPTION
    Validation precedes the write so a malformed packet never reaches disk.
    A queue entry pointing at a packet that cannot be read is the prose-only
    dispatch this milestone removes, arrived at by a different route.
#>
function Save-WorkPacket {
    param(
        [Parameter(Mandatory)][string]$WorkspaceRoot,
        [Parameter(Mandatory)][object]$Packet
    )

    $validation = Test-WorkPacket -Packet $Packet
    if (-not $validation.valid) {
        throw ('WorkPacket is invalid: {0}' -f ($validation.errors -join '; '))
    }

    $taskId = [string](_WP_Field -Obj $Packet -Name 'taskId' -Default '')
    $path = Get-WorkPacketPath -WorkspaceRoot $WorkspaceRoot -TaskId $taskId
    $directory = Split-Path -Parent $path
    if (-not (Test-Path -LiteralPath $directory)) {
        $null = New-Item -ItemType Directory -Path $directory -Force
    }

    Set-Content -LiteralPath $path -Value ($Packet | ConvertTo-Json -Depth 8) -Encoding UTF8
    return $path
}

<#
.SYNOPSIS
    Read a packet back, or $null when there is nothing readable to return.

.DESCRIPTION
    Absent and unparseable both answer $null on purpose. A caller's next move
    is the same either way — it has no packet — and a throw here would take
    down a reconciliation pass over many runs for one corrupt file.
#>
function Read-WorkPacket {
    param(
        [Parameter(Mandatory)][string]$WorkspaceRoot,
        [Parameter(Mandatory)][string]$TaskId
    )

    $path = Get-WorkPacketPath -WorkspaceRoot $WorkspaceRoot -TaskId $TaskId
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    try {
        return (ConvertFrom-Json -InputObject (Get-Content -LiteralPath $path -Raw -Encoding UTF8))
    }
    catch {
        return $null
    }
}

# ---------------------------------------------------------------------------
# The other half of the contract: what came back.
#
# A WorkPacket says what to do. An ExecutionResult says what happened, and it
# exists because the runner has never had an answer to that question. It reads
# the CLI's exit code, so an agent that printed an apology and exited 0 reached
# `awaiting-review` with nothing behind it. The spec puts it plainly: free-form
# prose must not be the orchestration protocol.
# ---------------------------------------------------------------------------

$script:ExecutionResultSchemaVersion = 1

function Get-ExecutionResultStatus {
    <#
    .SYNOPSIS
        The four ways an execution can end. One list, so the validator and the
        constructor cannot disagree about it.
    #>
    return @('implementation_complete', 'implementation_failed', 'capacity_exhausted', 'cancelled')
}

<#
.SYNOPSIS
    Build an ExecutionResult: the structured answer an adapter owes the runner.

.DESCRIPTION
    `capacity_exhausted` is a first-class status rather than a kind of failure.
    A provider limit means the work was never attempted, so recording it as
    failed would blame the task for the subscription's state and burn an
    attempt that never happened. H38-10 completes that path; this defines it.

.PARAMETER VerificationPassed
    Tri-state on purpose: $true, $false, or $null for "no verification ran".
    Collapsing the third into $false would report an unverified run as a failed
    one, which is a different and much louder claim.

.PARAMETER UsageNative
    Whatever the provider actually reported, in the provider's own units, kept
    unconverted. The spec forbids inventing a token conversion for a
    subscription allowance, so this stays opaque and TokensObserved carries a
    count only when the provider genuinely gave one.
#>
function New-ExecutionResult {
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Pure constructor: builds and returns a result in memory and touches nothing. Save-ExecutionResult is the only writer, and the New- verb is fixed by the M1 task contract.')]
    param(
        [Parameter(Mandatory)][string]$TaskId,
        [Parameter(Mandatory)][string]$ExecutionId,
        [Parameter(Mandatory)][string]$Provider,
        [AllowEmptyString()][string]$ProviderSessionId = '',
        [Parameter(Mandatory)][ValidateSet('implementation_complete', 'implementation_failed', 'capacity_exhausted', 'cancelled')][string]$Status,
        [string[]]$ChangedFiles = @(),
        [nullable[bool]]$VerificationPassed = $null,
        [string[]]$VerificationCommands = @(),
        [object]$UsageNative = $null,
        [nullable[int]]$TokensObserved = $null,
        [string[]]$Risks = @(),
        [bool]$OperatorAttentionRequired = $false,
        [AllowEmptyString()][string]$Summary = '',
        [ValidateSet('adapter', 'interactive')][string]$Source = 'adapter'
    )

    $sessionId = $null
    if (-not [string]::IsNullOrWhiteSpace($ProviderSessionId)) {
        $sessionId = [string]$ProviderSessionId
    }

    return [ordered]@{
        schemaVersion             = $script:ExecutionResultSchemaVersion
        taskId                    = [string]$TaskId
        executionId               = [string]$ExecutionId
        provider                  = [string]$Provider
        providerSessionId         = $sessionId
        status                    = [string]$Status
        changedFiles              = @($ChangedFiles)
        verification              = [ordered]@{
            passed   = $VerificationPassed
            commands = @($VerificationCommands)
        }
        usage                     = [ordered]@{
            native         = $UsageNative
            tokensObserved = $TokensObserved
        }
        risks                     = @($Risks)
        operatorAttentionRequired = [bool]$OperatorAttentionRequired
        summary                   = [string]$Summary
        source                    = [string]$Source
    }
}

<#
.SYNOPSIS
    Validate an ExecutionResult. Same posture as Test-WorkPacket: every error
    at once, and both a fresh hashtable and a JSON round-trip accepted.
#>
function Test-ExecutionResult {
    param([Parameter(Mandatory)][object]$Result)

    $errors = @()

    if ([string]::IsNullOrWhiteSpace([string](_WP_Field -Obj $Result -Name 'taskId' -Default ''))) {
        $errors += 'taskId is required'
    }
    if ([string]::IsNullOrWhiteSpace([string](_WP_Field -Obj $Result -Name 'executionId' -Default ''))) {
        $errors += 'executionId is required'
    }
    if ([string]::IsNullOrWhiteSpace([string](_WP_Field -Obj $Result -Name 'provider' -Default ''))) {
        $errors += 'provider is required'
    }

    $status = [string](_WP_Field -Obj $Result -Name 'status' -Default '')
    if ($status -notin (Get-ExecutionResultStatus)) {
        $errors += ('status must be one of: {0}' -f ((Get-ExecutionResultStatus) -join ', '))
    }

    # Read inline rather than through _WP_Field. Returning a value from a
    # PowerShell function ENUMERATES it, so an empty array comes back as $null
    # and a correctly-formed result would be reported as having no array at
    # all. Indexing into the object directly does not enumerate. This is the
    # same hazard tools\Assert-NoArrayCollapsingIfExpression.ps1 gates for in
    # its if-expression form.
    #
    # A STRING here is a provider that answered the wrong question, and a
    # caller counting files would silently read its character length.
    $hasChangedFiles = $false
    $changedFiles = $null
    if ($Result -is [System.Collections.IDictionary]) {
        if ($Result.Contains('changedFiles')) {
            $hasChangedFiles = $true
            $changedFiles = $Result['changedFiles']
        }
    }
    elseif ($null -ne $Result.PSObject -and ($Result.PSObject.Properties.Name -contains 'changedFiles')) {
        $hasChangedFiles = $true
        $changedFiles = $Result.changedFiles
    }
    if (-not $hasChangedFiles -or $changedFiles -is [string] -or $changedFiles -isnot [System.Collections.IEnumerable]) {
        $errors += 'changedFiles must be an array'
    }

    return [pscustomobject]@{
        valid  = ($errors.Count -eq 0)
        errors = @($errors)
    }
}

<#
.SYNOPSIS
    Where a run's result lives: beside the run summary that already describes it.
#>
function Get-ExecutionResultPath {
    param(
        [Parameter(Mandatory)][string]$WorkspaceRoot,
        [Parameter(Mandatory)][string]$TaskId
    )
    return (Join-Path $WorkspaceRoot ('output\roadmap-task-history\runs\{0}.result.json' -f $TaskId))
}

<#
.SYNOPSIS
    Persist a result, refusing to write an invalid one.
#>
function Save-ExecutionResult {
    param(
        [Parameter(Mandatory)][string]$WorkspaceRoot,
        [Parameter(Mandatory)][object]$Result
    )

    $validation = Test-ExecutionResult -Result $Result
    if (-not $validation.valid) {
        throw ('ExecutionResult is invalid: {0}' -f ($validation.errors -join '; '))
    }

    $taskId = [string](_WP_Field -Obj $Result -Name 'taskId' -Default '')
    $path = Get-ExecutionResultPath -WorkspaceRoot $WorkspaceRoot -TaskId $taskId
    $directory = Split-Path -Parent $path
    if (-not (Test-Path -LiteralPath $directory)) {
        $null = New-Item -ItemType Directory -Path $directory -Force
    }

    Set-Content -LiteralPath $path -Value ($Result | ConvertTo-Json -Depth 8) -Encoding UTF8
    return $path
}

<#
.SYNOPSIS
    Read a result back, or $null when there is nothing readable.

.DESCRIPTION
    $null is the ordinary case, not an error: until an adapter writes one, no
    run has a result. Resolve-RunOutcomeFromResult in the runner is what turns
    that absence into a named failure.
#>
function Read-ExecutionResult {
    param(
        [Parameter(Mandatory)][string]$WorkspaceRoot,
        [Parameter(Mandatory)][string]$TaskId
    )

    $path = Get-ExecutionResultPath -WorkspaceRoot $WorkspaceRoot -TaskId $TaskId
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    try {
        return (ConvertFrom-Json -InputObject (Get-Content -LiteralPath $path -Raw -Encoding UTF8))
    }
    catch {
        return $null
    }
}
