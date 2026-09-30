<#
.SYNOPSIS
    Recognises records that test gates wrote into the operator's live ledgers
    before those gates were isolated, so no operational view counts them.

.DESCRIPTION
    Lane 0.22, 2026-09-16. Until `REPO_MGMT_OUTPUT_ROOT` existed, the api-host
    smoke wrote its fixtures into the operator's own `output\`. On 2026-09-15,
    175 of 192 agent-run records were `dispatch-success-smoke`. They were most
    of the console's "100 agent runs" badge, and `smoke-packaging-repo` led the
    packaged work queue.

    THE WRITES ARE FIXED ELSEWHERE; THIS HIDES WHAT THEY LEFT. Every gate that
    starts a host now writes under an isolated output root, and
    `tests/Test-FixtureIsolation.ps1` fails the suite if one stops. The records
    already written stay on disk and are skipped when read, never deleted: the
    ledgers are append-only evidence, and a cleanup is the operator's call.

    A CLOSED LIST, BY NAME. These are the fixture repository names found in the
    operator's ledgers on 2026-09-16. No new name can reach those ledgers, so
    the list does not grow. Matching on name alone is deliberate: a path rule
    such as "under %TEMP%" would also hide fixtures that module-smoke tests
    create on purpose in temporary workspaces.

    ONLY THE OPERATOR'S ROOT IS FILTERED. With `REPO_MGMT_OUTPUT_ROOT` set, the
    root holds exactly what its own gate wrote, and that gate must be able to
    read its fixtures back. So the filter applies only when the output root is
    not overridden.
#>

Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'Config.OutputRoot.ps1')

$script:LiveLedgerFixtureRepoNames = @(
    'dispatch-success-smoke'   # api-host smoke: dispatch enqueue path
    'quota-dispatch-smoke'     # api-host smoke: quota refusal event
    'smoke-approve-bind'       # api-host smoke: approval binds to a SHA
    'verify-approve-bind'      # a manual check of the same route
    'smoke-packaging-repo'     # api-host smoke: packaging queue
)

function Get-LiveLedgerFixtureRepoName {
    <#
    .SYNOPSIS
        The fixture repository names hidden from the operator's ledgers.
        Enumerated; collect with @().
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    foreach ($name in $script:LiveLedgerFixtureRepoNames) { [string]$name }
}

function Test-FixtureRecordFilterActive {
    <#
    .SYNOPSIS
        True when reads come from the operator's own output root, which is the
        only place historical fixture records exist.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    -not (Test-OutputRootOverridden)
}

function Test-FixtureRecord {
    <#
    .SYNOPSIS
        True when a ledger record belongs to a test fixture and the filter is
        active.
    .PARAMETER Record
        An agent run, an agent-run event, a packaged item or a metrics row:
        anything with `repoName`, `repo_name` or `githubRepo`.
    .PARAMETER Force
        Test the name even when the output root is overridden (for the gate
        that proves the filter).
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter()][AllowNull()][object]$Record,
        [Parameter()][switch]$Force
    )

    if ($null -eq $Record) { return $false }
    if (-not $Force -and -not (Test-FixtureRecordFilterActive)) { return $false }

    $candidates = [System.Collections.Generic.List[string]]::new()
    foreach ($field in @('repoName', 'repo_name', 'githubRepo')) {
        $value = $null
        if ($Record -is [System.Collections.IDictionary]) {
            if ($Record.Contains($field)) { $value = $Record[$field] }
        }
        elseif ($null -ne $Record.PSObject.Properties[$field]) {
            $value = $Record.$field
        }
        if ($null -eq $value) { continue }
        $text = [string]$value
        if ([string]::IsNullOrWhiteSpace($text)) { continue }
        # githubRepo is owner/name; the name is what the list holds.
        $candidates.Add(($text -split '/')[-1])
    }

    foreach ($candidate in $candidates) {
        if ($script:LiveLedgerFixtureRepoNames -contains $candidate) { return $true }
    }
    return $false
}
