<#
.SYNOPSIS
    Release 3.8 M2 — where provider policy lives, and the rules it must obey.

.DESCRIPTION
    The execution governance spec is explicit that capacity reserves are
    "configuration, not hard-coded constants", and the roadmap milestone says
    reserves and ranking weights live in `backend/config/` rather than in code.
    This module is the loader and validator for that file.

    It is its own file rather than a section of `settings.json` for two
    reasons. Provider policy is application configuration, not operator
    settings, and `settings.json` is rewritten by the host on several paths
    while this is edited by hand and read. Keeping them apart also keeps
    reserve percentages away from `Remove-StoredSecretsFromSettings`, which has
    no business rewriting them.

    **Validation is loud where being wrong is expensive.** A reserve outside
    0..1 or an execution mode that names no real place to run are refused by
    name rather than defaulted, because a silently-corrected policy file is one
    nobody ever notices is not being obeyed. `dispatch.defaultTarget` may only
    be `auto` once `dispatch.autoEnabled` is true: writing a target the runner
    cannot yet claim would leave every dispatch queued forever, which is the
    deadlock this pairing exists to prevent.

    H38-14 added the registry half: this module is now the ONE token
    vocabulary. The list used to live in four places -- the queue module, the
    runner, and two ValidateSet attributes -- so adding a provider meant finding
    every copy, and missing one meant a valid provider was rejected somewhere
    nobody looked. The queue module and the runner delegate here; the two
    attributes cannot (a param() block binds before the body runs), so the
    module smoke checks them against this list and fails on drift.

.NOTES
    PowerShell 5.1 compatible. Param-less library: dot-source it, do not run it.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# The spec's list. A window's unit is the provider's OWN unit and is never
# converted: "unknown" is a legitimate answer for a subscription whose
# allowance is not exposed, and is far better than an invented ratio.
$script:AgentProviderWindowUnit = @('provider-allowance', 'tokens', 'ai-credits', 'premium-requests', 'currency', 'unknown')
$script:AgentProviderExecutionMode = @('local', 'github-hosted')
$script:AgentProviderTieBreak = @('nearest-reset-first', 'alphabetical')

function _APR_Field {
    <# Read a field from a hashtable or a PSCustomObject. Same shape as
       _PC_GetField in Portfolio.Conclusion.ps1, whose loader this follows. #>
    param([object]$Obj, [string]$Name, [object]$Default = $null)
    if ($null -eq $Obj) { return $Default }
    if ($Obj -is [System.Collections.IDictionary]) {
        if ($Obj.Contains($Name) -and $null -ne $Obj[$Name]) { return $Obj[$Name] }
        return $Default
    }
    # The ForEach-Object rather than `.Properties.Name`: under
    # Set-StrictMode -Version Latest, member-access enumeration over an EMPTY
    # property collection throws "The property 'Name' cannot be found on this
    # object". An empty object is an ordinary input here -- a fresh install has
    # no per-installation state, a provider may report no usage -- so this must
    # answer "absent", not crash.
    if ($null -ne $Obj.PSObject -and (@($Obj.PSObject.Properties | ForEach-Object { $_.Name }) -contains $Name)) {
        $value = $Obj.$Name
        if ($null -ne $value) { return $value }
    }
    return $Default
}

function _APR_Name {
    <# Property names of an object, whichever shape it arrived in. Returns a
       real array so an empty object does not collapse to $null on return.

       The ForEach-Object rather than `.Properties.Name`: under
       Set-StrictMode -Version Latest, member-access enumeration over an EMPTY
       property collection throws "The property 'Name' cannot be found on this
       object". An empty `"providers": {}` is exactly the malformed config this
       validator exists to reject, so it must not crash on the way. #>
    param([object]$Obj)
    if ($null -eq $Obj) { return @() }
    if ($Obj -is [System.Collections.IDictionary]) { return @($Obj.Keys) }
    if ($null -ne $Obj.PSObject) { return @($Obj.PSObject.Properties | ForEach-Object { $_.Name }) }
    return @()
}

function _APR_IsRatio {
    <# A ratio must be a number in 0..1. A string that happens to parse is
       accepted, because JSON round-trips are not always typed as expected;
       anything else is not. #>
    param([object]$Value)
    if ($null -eq $Value) { return $false }
    $parsed = 0.0
    if (-not [double]::TryParse([string]$Value, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$parsed)) { return $false }
    return ($parsed -ge 0.0 -and $parsed -le 1.0)
}

<#
.SYNOPSIS
    The one place the provider config path is decided.
#>
function Get-AgentProviderConfigPath {
    param([Parameter(Mandatory)][string]$WorkspaceRoot)
    return (Join-Path $WorkspaceRoot 'backend\config\agent-providers.json')
}

<#
.SYNOPSIS
    Load the provider config; $null when absent, unreadable, or not schema v1.

.DESCRIPTION
    Follows Get-FoundationDomainsConfig exactly: a caller that gets $null knows
    only that there is no usable config, and decides for itself whether that is
    fatal. The dispatch route treats it as fatal, because building a work
    packet with no scope policy would silently grant an agent everything.
#>
function Get-AgentProviderConfig {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ConfigPath)

    if (-not (Test-Path -LiteralPath $ConfigPath)) { return $null }
    try {
        $parsed = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8)
    }
    catch {
        return $null
    }
    if ($null -eq $parsed) { return $null }
    if ([string](_APR_Field -Obj $parsed -Name 'schemaVersion' -Default '') -ne 'v1') { return $null }
    if (@(_APR_Name -Obj (_APR_Field -Obj $parsed -Name 'providers' -Default $null)).Count -eq 0) { return $null }
    return $parsed
}

<#
.SYNOPSIS
    Every configured provider, keyed by name, in config order.

.DESCRIPTION
    H38-14. Includes providers whose `supported` is false. Whether a provider
    can currently run work is a ROUTING fact, decided per candidate; whether the
    name exists at all is a vocabulary fact, and this is the vocabulary. Hiding
    an unsupported provider here would make `codex` an unknown token rather than
    a known one that cannot yet be selected, and the two produce very different
    error messages for an operator.

    $null when the config cannot be read, so a caller can tell "no policy" from
    "a policy naming no providers" -- Get-AgentProviderConfig already refuses
    the latter.
#>
function Get-AgentProviderRegistry {
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param([Parameter(Mandatory)][string]$WorkspaceRoot)

    $config = Get-AgentProviderConfig -ConfigPath (Get-AgentProviderConfigPath -WorkspaceRoot $WorkspaceRoot)
    if ($null -eq $config) { return $null }

    $registry = [ordered]@{}
    $providers = _APR_Field -Obj $config -Name 'providers' -Default $null
    foreach ($name in @(_APR_Name -Obj $providers)) {
        $registry[$name] = (_APR_Field -Obj $providers -Name $name -Default $null)
    }
    return $registry
}

<#
.SYNOPSIS
    The one token vocabulary: every provider name, plus `auto`.

.DESCRIPTION
    Before this there were four copies -- the queue module, the runner, and two
    ValidateSet attributes -- each of which had to be found and edited to add a
    provider, and any one of which could be missed. `auto` is appended here
    rather than stored in config because it names no provider: it is the
    instruction to choose one.

    Falls back to the committed three when no config is loadable, so a caller in
    a fixture workspace still gets a usable vocabulary rather than an empty one.
#>
function Get-AgentProviderToken {
    [CmdletBinding()]
    [OutputType([object[]])]
    param([string]$WorkspaceRoot = '')

    $names = @()
    if (-not [string]::IsNullOrWhiteSpace($WorkspaceRoot)) {
        $registry = Get-AgentProviderRegistry -WorkspaceRoot $WorkspaceRoot
        if ($null -ne $registry) { $names = @($registry.Keys) }
    }
    if ($names.Count -eq 0) { $names = @('claude', 'codex', 'copilot') }
    return @(@($names) + @('auto'))
}

<#
.SYNOPSIS
    Is this a token the product knows, in any casing?
#>
function Test-AgentProviderToken {
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Token, [string]$WorkspaceRoot = '')

    if ([string]::IsNullOrWhiteSpace($Token)) { return $false }
    return (@(Get-AgentProviderToken -WorkspaceRoot $WorkspaceRoot) -contains $Token.Trim().ToLowerInvariant())
}

<#
.SYNOPSIS
    Normalize a token; empty means claude, unknown throws with the list named.

.DESCRIPTION
    Empty resolves to `claude` because entries written before Release 3.0 carry
    no target and must keep running as the Claude Code tasks they were queued
    as. An unrecognized value is refused rather than defaulted: silently running
    an unknown target as `claude` would execute the wrong tool against a real
    repository.

    The message shape is asserted by the module smoke and is what an operator
    reads, so it is a contract, not a string.
#>
function Resolve-AgentProviderToken {
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowEmptyString()][string]$Token = '', [string]$WorkspaceRoot = '')

    if ([string]::IsNullOrWhiteSpace($Token)) { return 'claude' }
    $normalized = $Token.Trim().ToLowerInvariant()
    $allowed = @(Get-AgentProviderToken -WorkspaceRoot $WorkspaceRoot)
    if ($allowed -notcontains $normalized) {
        throw ("Unknown dispatchTarget '{0}'. Allowed: {1}." -f $Token, ($allowed -join ', '))
    }
    return $normalized
}

<#
.SYNOPSIS
    The command a provider is invoked by, if it is installed at all.

.DESCRIPTION
    One place, so the availability probe and the router cannot drift apart about
    what to look for. `copilot` runs through the GitHub CLI, which is why its
    command is `gh` and not its own name.
#>
function Get-AgentProviderModel {
    <#
    .SYNOPSIS
        The model a provider runs by default, as configured.

    .DESCRIPTION
        Release 3.8 M5 (H38-28b). Provider and model are separate facts: a
        provider is which subscription and which CLI, a model is what actually
        answered. Collapsing them makes "one provider, one model" true by
        construction, which is wrong today and would be baked into H38-29's
        resume path.

        Returns the configured default, or an empty string for a provider the
        registry does not recognise -- never a guess. An unrecognised provider
        with an invented model would be indistinguishable from a real one at
        every call site downstream.
    .OUTPUTS
        [string]
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Provider,
        [Parameter()][string]$WorkspaceRoot = ''
    )

    $config = $null
    try { $config = Get-AgentProviderConfig -ConfigPath (Get-AgentProviderConfigPath -WorkspaceRoot $WorkspaceRoot) }
    catch {
        Write-Verbose ("provider registry: could not read the config for model lookup: {0}" -f $_.Exception.Message)
        return ''
    }
    if ($null -eq $config -or $null -eq $config.providers) { return '' }

    $normalized = ([string]$Provider).Trim().ToLowerInvariant()
    foreach ($name in @($config.providers.PSObject.Properties.Name)) {
        if ($name.ToLowerInvariant() -ne $normalized) { continue }
        return [string]$config.providers.$name.defaultModel
    }

    return ''
}

function Get-AgentProviderCommandName {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$Provider)

    switch ($Provider.ToLowerInvariant()) {
        'claude' { return 'claude' }
        'codex' { return 'codex' }
        'copilot' { return 'gh' }
        default { return $Provider.ToLowerInvariant() }
    }
}

<#
.SYNOPSIS
    Can this installation actually run work through this provider, and why not?

.DESCRIPTION
    Release 3.8 M3 (H38-15b), assumptions A20 and A21.

    Three different facts, deliberately kept apart:

      supported  a REPOSITORY fact -- a conforming adapter exists in this build.
                 Same for everyone, and CI can verify it.
      installed  a MACHINE fact -- the CLI is on this PATH. Different on every
                 installation, so it is detected here and never committed.
      optedOut   an OPERATOR fact -- switched off deliberately, stored in an
                 untracked per-installation file (A22).

    **Nothing here authenticates.** There is no probe of whether the account
    works, because the only way to prove that is to USE the account, and that
    spends the subscription quota this release exists to conserve (A21, R12).
    `authenticated` is therefore always the string `unknown`, and stays unknown
    until a real run reports otherwise -- an auth failure is a cheap and
    distinguishable outcome. An unknown that is labelled unknown is safe to
    route on; a guess is not. If this function ever starts a provider process,
    it has gone wrong.

    `detail` names the FIRST reason it is unavailable, because an operator
    fixing three problems wants the next one, not all of them at once.
#>
function Test-AgentProviderAvailability {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$Provider,
        [string]$WorkspaceRoot = '',
        [object]$InstallationState = $null
    )

    $supported = $false
    if (-not [string]::IsNullOrWhiteSpace($WorkspaceRoot)) {
        $registry = Get-AgentProviderRegistry -WorkspaceRoot $WorkspaceRoot
        if ($null -ne $registry -and $registry.Contains($Provider)) {
            $supported = [bool](_APR_Field -Obj $registry[$Provider] -Name 'supported' -Default $false)
        }
    }

    $commandName = Get-AgentProviderCommandName -Provider $Provider
    $installed = [bool](Get-Command -Name $commandName -ErrorAction SilentlyContinue)

    $optedOut = $false
    $state = $InstallationState
    if ($null -eq $state -and -not [string]::IsNullOrWhiteSpace($WorkspaceRoot) -and (Get-Command -Name 'Get-InstallationState' -ErrorAction SilentlyContinue)) {
        $state = Get-InstallationState -WorkspaceRoot $WorkspaceRoot
    }
    if ($null -ne $state) {
        $entry = _APR_Field -Obj (_APR_Field -Obj $state -Name 'providers' -Default $null) -Name $Provider -Default $null
        $optedOut = [bool](_APR_Field -Obj $entry -Name 'optOut' -Default $false)
    }

    $available = ($supported -and $installed -and -not $optedOut)

    $detail = 'available'
    if (-not $supported) { $detail = 'no adapter in this build' }
    elseif (-not $installed) { $detail = ("the {0} CLI was not found on PATH" -f $commandName) }
    elseif ($optedOut) { $detail = 'switched off in Settings' }

    return [pscustomobject]@{
        provider      = $Provider
        supported     = $supported
        installed     = $installed
        optedOut      = $optedOut
        authenticated = 'unknown'
        available     = $available
        detail        = $detail
    }
}

<#
.SYNOPSIS
    Availability per provider, as the router consumes it.

.DESCRIPTION
    H38-17 passes this as its eligibility input. It must call this rather than
    inlining `Get-Command`: an earlier draft of that packet did exactly that,
    which is how availability came to be duplicated between the router and the
    config in the first place (A20).
#>
function Get-AgentProviderAvailabilityMap {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([Parameter(Mandatory)][string]$WorkspaceRoot)

    $map = @{}
    $state = $null
    if (Get-Command -Name 'Get-InstallationState' -ErrorAction SilentlyContinue) {
        $state = Get-InstallationState -WorkspaceRoot $WorkspaceRoot
    }
    foreach ($token in @(Get-AgentProviderToken -WorkspaceRoot $WorkspaceRoot)) {
        # `auto` names no provider, so it has nothing to be available.
        if ($token -eq 'auto') { continue }
        $map[$token] = [bool](Test-AgentProviderAvailability -Provider $token -WorkspaceRoot $WorkspaceRoot -InstallationState $state).available
    }
    return $map
}

<#
.SYNOPSIS
    Where a provider's adapter file lives.
#>
function Get-AgentProviderAdapterPath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$WorkspaceRoot,
        [Parameter(Mandatory)][string]$Provider
    )
    $capitalized = $Provider.Substring(0, 1).ToUpperInvariant() + $Provider.Substring(1).ToLowerInvariant()
    return (Join-Path $WorkspaceRoot ('backend\modules\agent-adapters\Adapter.{0}.ps1' -f $capitalized))
}

<#
.SYNOPSIS
    Does this provider implement all seven IAgentExecutor functions?

.DESCRIPTION
    PowerShell has no interfaces, so the contract is a set of NAMES and the
    check is whether they resolve. That is the offline-testable equivalent: it
    needs no provider, no network and no quota, and it fails at gate time rather
    than at 2am when the router first selects a provider whose adapter is half
    written.

    Reports every missing name at once. A conformance check that stops at the
    first gap makes fixing a new adapter an exercise in re-running the gate.
#>
function Test-AgentProviderAdapter {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)][string]$Provider)

    $capitalized = $Provider.Substring(0, 1).ToUpperInvariant() + $Provider.Substring(1).ToLowerInvariant()
    $required = @(
        ('Get-{0}AdapterCapability' -f $capitalized),
        ('Get-{0}AdapterCapacity' -f $capitalized),
        ('Start-{0}Execution' -f $capitalized),
        ('Resume-{0}Execution' -f $capitalized),
        ('Stop-{0}Execution' -f $capitalized),
        ('ConvertTo-{0}CanonicalEvent' -f $capitalized),
        ('Get-{0}ExecutionResult' -f $capitalized)
    )

    $missing = @()
    foreach ($name in $required) {
        if (-not (Get-Command -Name $name -ErrorAction SilentlyContinue)) { $missing += , $name }
    }

    return [pscustomobject]@{
        provider = $Provider
        conforms = ($missing.Count -eq 0)
        missing  = @($missing)
    }
}

<#
.SYNOPSIS
    Validate a loaded provider config. Every error at once, each naming the
    exact key at fault.
#>
function Test-AgentProviderConfig {
    param([Parameter(Mandatory)][object]$Config)

    $errors = @()

    $providers = _APR_Field -Obj $Config -Name 'providers' -Default $null
    foreach ($providerName in @(_APR_Name -Obj $providers)) {
        $provider = _APR_Field -Obj $providers -Name $providerName -Default $null

        $executionMode = [string](_APR_Field -Obj $provider -Name 'executionMode' -Default '')
        if ($executionMode -notin $script:AgentProviderExecutionMode) {
            $errors += ('providers.{0}.executionMode must be local or github-hosted' -f $providerName)
        }

        # `supported` is a fact about THIS REPOSITORY -- whether a conforming
        # adapter exists here -- so CI can check it. It is deliberately not
        # `enabled`, which asserted something about one operator's machine that
        # no gate could ever verify and that this file has no business shipping
        # to every other installation. Whether a provider is installed and
        # funded is detected per installation, never committed.
        $supported = _APR_Field -Obj $provider -Name 'supported' -Default $null
        if ($supported -isnot [bool]) {
            $errors += ('providers.{0}.supported must be true or false' -f $providerName)
        }

        if ($null -ne (_APR_Field -Obj $provider -Name 'enabled' -Default $null)) {
            $errors += ('providers.{0}.enabled was removed -- use supported; whether a provider is installed is detected per installation, not configured' -f $providerName)
        }

        # Read inline: returning a collection from a function enumerates it, so
        # an empty windows array would come back as $null and be reported as
        # the wrong error.
        $windows = @()
        if ($provider -is [System.Collections.IDictionary]) {
            if ($provider.Contains('windows')) { $windows = @($provider['windows']) }
        }
        elseif ($null -ne $provider -and $null -ne $provider.PSObject -and ($provider.PSObject.Properties.Name -contains 'windows')) {
            $windows = @($provider.windows)
        }

        if ($windows.Count -eq 0) {
            $errors += ('providers.{0}.windows must be a non-empty array' -f $providerName)
        }
        else {
            for ($i = 0; $i -lt $windows.Count; $i++) {
                $unit = [string](_APR_Field -Obj $windows[$i] -Name 'unit' -Default '')
                if ($unit -notin $script:AgentProviderWindowUnit) {
                    $errors += ('providers.{0}.windows[{1}].unit must be one of: {2}' -f $providerName, $i, ($script:AgentProviderWindowUnit -join ', '))
                }
            }
        }
    }

    $reserves = _APR_Field -Obj $Config -Name 'reserves' -Default $null
    if (-not (_APR_IsRatio (_APR_Field -Obj $reserves -Name 'shortWindowRatio' -Default $null))) {
        $errors += 'reserves.shortWindowRatio must be between 0 and 1'
    }
    if (-not (_APR_IsRatio (_APR_Field -Obj $reserves -Name 'weeklyRatio' -Default $null))) {
        $errors += 'reserves.weeklyRatio must be between 0 and 1'
    }

    # MVP concurrency is one local slot (spec). Encoded as a validation rather
    # than a constant so relaxing it is a visible, reviewable edit.
    $slots = _APR_Field -Obj $Config -Name 'localExecutionSlots' -Default $null
    $parsedSlots = 0
    if ($null -eq $slots -or -not [int]::TryParse([string]$slots, [ref]$parsedSlots) -or $parsedSlots -ne 1) {
        $errors += 'localExecutionSlots must be 1'
    }

    $dispatch = _APR_Field -Obj $Config -Name 'dispatch' -Default $null
    $defaultTarget = [string](_APR_Field -Obj $dispatch -Name 'defaultTarget' -Default '')
    $autoEnabled = [bool](_APR_Field -Obj $dispatch -Name 'autoEnabled' -Default $false)
    $knownTargets = @(_APR_Name -Obj $providers) + @('auto')
    if ($defaultTarget -notin $knownTargets) {
        $errors += 'dispatch.defaultTarget must name a provider or auto'
    }
    elseif ($defaultTarget -eq 'auto' -and -not $autoEnabled) {
        # The deadlock guard: a target the runner cannot claim leaves every
        # dispatch queued forever.
        $errors += 'dispatch.defaultTarget is auto but dispatch.autoEnabled is false'
    }

    $ranking = _APR_Field -Obj $Config -Name 'ranking' -Default $null
    $tieBreak = [string](_APR_Field -Obj $ranking -Name 'tieBreak' -Default '')
    if ($tieBreak -notin $script:AgentProviderTieBreak) {
        $errors += 'ranking.tieBreak must be nearest-reset-first or alphabetical'
    }

    return [pscustomobject]@{
        valid  = ($errors.Count -eq 0)
        errors = @($errors)
    }
}
