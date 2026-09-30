<#
.SYNOPSIS
    The one place the run-evidence directory (`output\`) is decided.

.DESCRIPTION
    Lane 0.22, 2026-09-16. The fourth resolver of this shape, after the queue
    (`REPO_MGMT_QUEUE_PATH`), settings (`REPO_MGMT_SETTINGS_PATH`) and the
    portfolio index (`REPO_MGMT_INDEX_ROOT`). Each of those was added after a
    test host wrote into the operator's live state through a path built
    inline. This one covers the rest of `output\` at once instead of one
    ledger per incident.

    THE INCIDENT THIS EXISTS FOR (2026-09-15). 175 of 192 agent-run records in
    the operator's `output\agent-runs` were the api-host smoke's
    `dispatch-success-smoke`. They were most of the console's "100 agent runs"
    badge, and a smoke fixture led the packaged work queue. The smoke isolated
    the index, the queue and the settings, but agent runs, packaged items,
    work packets, run summaries, the execution ledger and `app.db` were still
    built as `Join-Path $WorkspaceRoot 'output\...'`.

    ROOT, NOT FILE. Every ledger under `output\` moves together, so a gate sets
    one variable and cannot miss a store that is added later.
    `tests/Test-FixtureIsolation.ps1` fails any `Join-Path` that builds an
    `output\` path without going through here.

    MORE SPECIFIC OVERRIDES STILL WIN. `REPO_MGMT_INDEX_ROOT` and
    `REPO_MGMT_QUEUE_PATH` keep their meaning. Their defaults now derive from
    this root, so setting only `REPO_MGMT_OUTPUT_ROOT` moves them too.
#>

Set-StrictMode -Version Latest

function Get-OutputRoot {
    <#
    .SYNOPSIS
        Resolve the run-evidence directory, honouring REPO_MGMT_OUTPUT_ROOT.
    .PARAMETER WorkspaceRoot
        The repository root. Used only for the default; an override ignores it.
    .OUTPUTS
        [string] the directory that stands in for `<WorkspaceRoot>\output`. It
        need not exist; callers create what they write.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$WorkspaceRoot)

    $override = [System.Environment]::GetEnvironmentVariable('REPO_MGMT_OUTPUT_ROOT')
    if (-not [string]::IsNullOrWhiteSpace($override)) { return $override }

    Join-Path $WorkspaceRoot 'output'
}

function Resolve-OutputPath {
    <#
    .SYNOPSIS
        Resolve a workspace-relative `output\...` path against the output root.
    .DESCRIPTION
        Modules declare their ledger homes as `output\agent-runs` or
        `output/automation/packaged-items.jsonl`, and those constants double as
        the artifact labels the trace shows. This keeps the constants and moves
        only the resolution: the leading `output` segment becomes the output
        root. A path that does not start with `output` is a caller bug and
        throws, rather than landing somewhere unexpected.
    .PARAMETER WorkspaceRoot
        The repository root, passed through to Get-OutputRoot.
    .PARAMETER RelativePath
        `output\...` or `output/...`; `output` alone names the root itself.
    .OUTPUTS
        [string] the resolved path.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$WorkspaceRoot,
        [Parameter(Mandatory)][string]$RelativePath
    )

    $root = Get-OutputRoot -WorkspaceRoot $WorkspaceRoot
    if ($RelativePath -match '^output[\\/]*$') { return $root }
    if ($RelativePath -notmatch '^output[\\/](?<rest>.+)$') {
        throw ("Resolve-OutputPath expects a path under output\, got '{0}'." -f $RelativePath)
    }
    Join-Path $root ($Matches['rest'] -replace '/', '\')
}

function Test-OutputRootOverridden {
    <#
    .SYNOPSIS
        True when REPO_MGMT_OUTPUT_ROOT is steering writes away from the
        operator's run evidence.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    -not [string]::IsNullOrWhiteSpace([System.Environment]::GetEnvironmentVariable('REPO_MGMT_OUTPUT_ROOT'))
}
