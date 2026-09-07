<#
.SYNOPSIS
    The one place per-installation state is decided — and it is never tracked.

.DESCRIPTION
    Release 3.8 M3 (H38-15b), assumption A22.

    Some facts belong to ONE machine and one account: which agent CLIs are
    installed, and which providers this operator has deliberately switched off.
    Those must not be written into a file that ships to every installation,
    because a committed answer is wrong for everyone else and wrong for this
    operator as soon as they install a tool or change a plan.

    THE PRECEDENT THIS EXISTS BECAUSE OF. `backend\config\settings.json` is
    git-TRACKED. Its `.gitignore` entry does nothing, because a file that is
    already tracked stays tracked no matter what the ignore file says. Putting a
    provider opt-out there would therefore commit one operator's choice into
    everyone's repository -- the exact defect Ben named on 2026-09-07 about
    `enabled: false` in agent-providers.json, reintroduced one layer down.

    So this file is NEW, is ignored from the start (which does work), and the
    module smoke asserts `git ls-files` does not know it. An ignore rule alone
    is a hope; the assertion is the guarantee.

    NOT A SECRETS MECHANISM, and not portal settings. This holds operator
    preferences that are meaningless on another machine. Secrets still belong in
    the `REPO_MGMT_*` environment variables.

.NOTES
    PowerShell 5.1 compatible. Param-less library: dot-source it, do not run it.
#>

Set-StrictMode -Version Latest

function Get-InstallationStatePath {
    <#
    .SYNOPSIS
        Resolve the per-installation state file, honouring the env override.
    .PARAMETER WorkspaceRoot
        The repository root. Used only for the default; an override ignores it,
        which is what lets a gate point at a fixture instead of writing the file
        the operator is actually using.
    .OUTPUTS
        [string] path to an installation.local.json. The file need not exist:
        "no file" is the ordinary state until an operator changes something.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$WorkspaceRoot)

    $override = [System.Environment]::GetEnvironmentVariable('REPO_MGMT_INSTALLATION_STATE_PATH')
    if (-not [string]::IsNullOrWhiteSpace($override)) { return $override }

    return (Join-Path $WorkspaceRoot 'backend\config\installation.local.json')
}

function Get-InstallationState {
    <#
    .SYNOPSIS
        Read the per-installation state; an empty object when absent or broken.
    .DESCRIPTION
        Absent and unparseable answer the same way, and neither throws. A
        missing file is the ordinary state on every fresh install, and a corrupt
        one must not stop the runner from claiming work -- the worst it should
        cost is a forgotten preference.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$WorkspaceRoot)

    $path = Get-InstallationStatePath -WorkspaceRoot $WorkspaceRoot
    if (-not (Test-Path -LiteralPath $path)) { return ([pscustomobject]@{}) }
    try {
        $parsed = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $path -Raw -Encoding UTF8)
    }
    catch {
        return ([pscustomobject]@{})
    }
    if ($null -eq $parsed) { return ([pscustomobject]@{}) }
    return $parsed
}
