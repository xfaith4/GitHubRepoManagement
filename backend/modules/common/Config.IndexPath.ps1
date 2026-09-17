<#
.SYNOPSIS
    The one place the portfolio index location is decided.

.DESCRIPTION
    Third time for this shape of defect, and the first two are already written
    down a few files away. Release 2.9 gave the task queue
    `Get-RoadmapQueuePath` plus `REPO_MGMT_QUEUE_PATH`, because four call sites
    rebuilding the same path inline is how the api-host smoke came to enqueue
    its dispatch fixture into the OPERATOR'S real queue. `Config.SettingsPath.ps1`
    did the same for `settings.json` after the smoke emptied the operator's
    console mid-session. `output\index\` was built inline at both of its call
    sites and never got the same fix.

    THE INCIDENT THIS EXISTS FOR (2026-09-13). The api-host smoke scans a
    fixture root. Its scan wrote straight through to the operator's own
    `output\index\repos.index.json`, replacing 59 real repositories with the
    gate's three fixtures -- and on a second run, with none at all. It happened
    twice in two days. The second time landed four minutes before the operator
    ticked "rebuild the index" on their own checklist, so a verification step
    recorded work that a test run had just undone, and nothing on screen
    connected an empty portfolio to a gate.

    Every portal surface reads this index. A gate that can overwrite it can
    empty the product the operator is looking at, silently, while telling them
    nothing -- exactly the failure the other two resolvers exist to prevent.

    ROOT, NOT FILE. The index is a directory: `repos.index.json`,
    `repo-curation.json`, and a `scans\` history beside them. Overriding only
    the index file would leave a gate's scan snapshots landing in the operator's
    history, so the override names the ROOT and everything under it moves
    together.

    NOT A SCAN-SCOPE MECHANISM. This decides WHERE the index is written, never
    WHAT is scanned. Scan scope is `inventory.localRoots` in settings, and a
    gate that wants a fixture portfolio overrides both: the settings file to
    choose the roots, and this to choose where the answer lands.
#>

Set-StrictMode -Version Latest

# The default derives from the output root (Lane 0.22), so a gate that moves
# all of output\ moves the index with it.
. (Join-Path $PSScriptRoot 'Config.OutputRoot.ps1')

function Get-PortfolioIndexRoot {
    <#
    .SYNOPSIS
        Resolve the portfolio index directory, honouring REPO_MGMT_INDEX_ROOT.
    .PARAMETER WorkspaceRoot
        The repository root. Used only for the default; an override ignores it,
        which is what lets a gate write its index outside the repo entirely.
    .OUTPUTS
        [string] path to the directory holding repos.index.json. The directory
        need not exist; callers create it when they write.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$WorkspaceRoot)

    $override = [System.Environment]::GetEnvironmentVariable('REPO_MGMT_INDEX_ROOT')
    if (-not [string]::IsNullOrWhiteSpace($override)) { return $override }

    Resolve-OutputPath -WorkspaceRoot $WorkspaceRoot -RelativePath 'output\index'
}

function Get-PortfolioIndexPath {
    <#
    .SYNOPSIS
        Resolve repos.index.json itself.
    .PARAMETER WorkspaceRoot
        The repository root, passed through to Get-PortfolioIndexRoot.
    .OUTPUTS
        [string] path to repos.index.json.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$WorkspaceRoot)

    Join-Path (Get-PortfolioIndexRoot -WorkspaceRoot $WorkspaceRoot) 'repos.index.json'
}

function Test-PortfolioIndexRootOverridden {
    <#
    .SYNOPSIS
        True when REPO_MGMT_INDEX_ROOT is steering writes away from the
        operator's index.
    .DESCRIPTION
        For surfaces that must SAY they are reading a redirected index rather
        than let the operator assume otherwise -- the same rule the rest of this
        console follows about naming the basis of what it shows.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    -not [string]::IsNullOrWhiteSpace([System.Environment]::GetEnvironmentVariable('REPO_MGMT_INDEX_ROOT'))
}
