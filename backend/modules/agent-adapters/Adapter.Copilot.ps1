<#
.SYNOPSIS
    Release 3.8 M3 — the GitHub Copilot adapter, conforming to IAgentExecutor.

.DESCRIPTION
    Copilot is the one provider that does NOT run on this machine. `gh
    agent-task create` hands the work to GitHub, which runs it on its own
    infrastructure, so this adapter dispatches and then has nothing further to
    do: there is no local process to stop, no session to resume, and no
    transcript to parse. Every one of those is a refusal below rather than a
    silent no-op, because a stub that quietly returns nothing is
    indistinguishable from one that worked.

    **The first three functions are MOVED, not rewritten.** `New-CopilotAgentTaskArgs`,
    `Get-AgentTaskUrlFromOutput` and `Test-CopilotDispatchPrecondition` came out
    of `Invoke-RoadmapTaskRunner.ps1` with the same bodies and the same
    signatures. The runner dot-sources this file, so every existing call keeps
    working, and the module smoke asserts their output is byte-identical to the
    pre-move behaviour. A move that quietly changed something would be the worst
    kind of refactor: invisible in review and visible only in production.

.NOTES
    PowerShell 5.1 compatible. Param-less library: dot-source it, do not run it.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function New-CopilotAgentTaskArgs {
    <#
    .SYNOPSIS
        Pure — the `gh agent-task create` argv for a queued copilot entry.
    .DESCRIPTION
        Built as an array, never a command string: the prompt is multi-line
        roadmap text and interpolating it into a shell line would break on the
        first quote it contains.
    #>
    param(
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][string]$Prompt,
        [AllowEmptyString()][string]$BaseBranch = ''
    )

    if ([string]::IsNullOrWhiteSpace($Repository)) { throw 'A copilot entry needs repository (owner/repo).' }
    if ([string]::IsNullOrWhiteSpace($Prompt)) { throw 'A copilot entry needs a prompt.' }

    # Not $args — that is an automatic variable, and shadowing it inside an
    # advanced function is a debugging trap for whoever reads this next.
    $ghArgv = [System.Collections.Generic.List[string]]::new()
    $ghArgv.Add('agent-task'); $ghArgv.Add('create'); $ghArgv.Add($Prompt)
    $ghArgv.Add('--repo'); $ghArgv.Add($Repository)
    if (-not [string]::IsNullOrWhiteSpace($BaseBranch)) { $ghArgv.Add('--base'); $ghArgv.Add($BaseBranch) }
    return $ghArgv.ToArray()
}

function Get-AgentTaskUrlFromOutput {
    <#
    .SYNOPSIS
        Pure — pull the agent-task URL out of `gh agent-task create` output.
    .DESCRIPTION
        The URL is the only durable handle on a cloud run; without it the run
        summary records "dispatched" and the operator has no way to find what
        was dispatched. Returns '' when the output carries none, so the caller
        records the absence rather than a fabricated link.
    #>
    param([AllowEmptyString()][string]$Output = '')

    if ([string]::IsNullOrWhiteSpace($Output)) { return '' }
    $match = [regex]::Match($Output, 'https://github\.com/\S+')
    if (-not $match.Success) { return '' }
    return $match.Value.TrimEnd('.', ',', ')', ']', '"', "'")
}

function Test-CopilotDispatchPrecondition {
    <#
    .SYNOPSIS
        Pure — can this session run `gh agent-task create`? Named reason if not.
    .DESCRIPTION
        Two things break cloud dispatch, and both are silent until the call
        fails: `gh` is absent, or the process carries GH_TOKEN/GITHUB_TOKEN.
        The second is the trap Release 3.0 exists to route around — gh IGNORES
        its stored OAuth credential whenever an environment token is set, so a
        PAT inherited from the portal's environment turns a working operator
        session into the same failure the service has.
    #>
    param(
        [bool]$GhAvailable,
        [AllowEmptyString()][string]$EnvToken = ''
    )

    if (-not $GhAvailable) {
        return [pscustomobject]@{
            ok     = $false
            reason = 'gh-not-found'
            message = "'gh' was not found on PATH. Cloud dispatch runs the GitHub CLI in your session; install it or set GH_CLI_PATH."
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($EnvToken)) {
        return [pscustomobject]@{
            ok     = $false
            reason = 'env-token-overrides-oauth'
            message = ('This session carries a GitHub token in the environment, and gh ignores its stored OAuth credential whenever one is set. ' +
                       'agent-task needs OAuth, so clear GH_TOKEN/GITHUB_TOKEN in this shell and re-run: $env:GH_TOKEN=$null; $env:GITHUB_TOKEN=$null')
        }
    }
    return [pscustomobject]@{ ok = $true; reason = ''; message = '' }
}

# ── The seven A4 names ───────────────────────────────────────────────────────

function Get-CopilotAdapterCapability {
    return [ordered]@{
        provider                 = 'copilot'
        executionMode            = 'github-hosted'
        # No resume: a GitHub-hosted run is not a session this machine holds.
        # Remediation is a new task, which is what H38-30's handoff builds.
        supportsResume           = $false
        supportsStructuredOutput = $false
    }
}

function Get-CopilotAdapterCapacity {
    <#
        One window, deliberately unmeasured. Billing mode is a property of
        whichever GitHub account is signed in -- AI credits or the legacy
        premium-request allowance -- so there is no single answer this
        repository could record on every installation's behalf. That was asked
        as D-014 and WITHDRAWN on 2026-09-07 as the wrong kind of question
        (A20): per-account state is observed, never decided.

        `unknown` with `remainingRatio = $null` is therefore the honest answer,
        and the verdict reads it as "capacity unmeasured" -- eligible, not
        exhausted. An invented ratio would be indistinguishable from a measured
        one at the moment the governor decides whether to spend it.
    #>
    return [ordered]@{
        name           = 'billing'
        unit           = 'unknown'
        remainingRatio = $null
        source         = 'historical-estimate'
    }
}

function Start-CopilotExecution {
    <#
        Returns the argument vector; it does NOT launch. Same contract as the
        Claude adapter: the runner is the process holding the credential.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Returns an argument vector and starts nothing; the Start- verb is fixed by the A4 adapter contract.')]
    param(
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][string]$Prompt,
        [AllowEmptyString()][string]$BaseBranch = ''
    )
    return (New-CopilotAgentTaskArgs -Repository $Repository -Prompt $Prompt -BaseBranch $BaseBranch)
}

function Resume-CopilotExecution {
    throw 'Not supported: Copilot runs are GitHub-hosted; remediation is a new task'
}

function Stop-CopilotExecution {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Throws unconditionally; the Stop- verb is fixed by the A4 adapter contract.')]
    param()
    throw 'Not supported in 3.8'
}

function ConvertTo-CopilotCanonicalEvent {
    <# H38-33 fills this. A GitHub-hosted run emits nothing this machine sees,
       so today the only honest answer is no events -- not a fabricated one. #>
    param([Parameter()][AllowNull()][object]$Parsed = $null)
    return @()
}

function Get-CopilotExecutionResult {
    <#
        The task URL is the only durable handle a dispatch produces today, so it
        serves as the provider session id: it is what makes "dispatched"
        checkable rather than a claim with nothing behind it. H38-22 reconciles
        the pull request state that eventually replaces this.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$TaskUrl,
        [Parameter(Mandatory)][string]$TaskId,
        [Parameter(Mandatory)][string]$ExecutionId
    )

    return New-ExecutionResult `
        -TaskId $TaskId `
        -ExecutionId $ExecutionId `
        -Provider 'copilot' `
        -ProviderSessionId $TaskUrl `
        -Status 'implementation_complete' `
        -Summary ("dispatched: {0}" -f $TaskUrl) `
        -Source 'adapter'
}
