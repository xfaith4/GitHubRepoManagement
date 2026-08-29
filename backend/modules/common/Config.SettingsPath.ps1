<#
.SYNOPSIS
    The one place the portal settings file is decided.

.DESCRIPTION
    Release 2.9 gave the task queue `Get-RoadmapQueuePath` plus a
    `REPO_MGMT_QUEUE_PATH` override, because four call sites rebuilding the same
    path inline is how the api-host smoke came to enqueue its dispatch fixture
    into the OPERATOR'S real queue. `backend\config\settings.json` had the same
    problem in the other direction and never got the same fix.

    THE INCIDENT THIS EXISTS FOR (2026-08-29). The api-host smoke needs the host
    pointed at a fixture workspace. With no override, its only way to do that was
    to `POST /api/settings` and let the host overwrite the git-TRACKED settings
    file, then restore it byte-exact in a `finally`. The restore is careful and
    it works -- but for the ~10 minutes the gate runs, the LIVE PORTAL reads the
    same file. The operator's console emptied mid-session: the status cache is
    keyed by scan root, and while the fixture root was installed the operator's
    key (`f:\development\20_staging|depth:3|nonGit:False`) had no entry to serve.
    Nothing on screen connected a vanished portfolio to a test run.

    A gate must not be able to reach into the state the operator is looking at.
    With this resolver the smoke redirects the whole host to a temp copy in one
    decision, and the tracked file is never opened for writing at all -- which is
    a stronger guarantee than restoring it afterwards, because it removes the
    window rather than shortening it.

    READ AND WRITE, DELIBERATELY. The smoke does not write settings itself; it
    POSTs `/api/settings` and the HOST writes. So an override honoured only on
    the read path would leave the fixture POST landing on the tracked file
    anyway. Every site that resolves this path -- reads, writes, and existence
    probes -- goes through here, and the module smoke refuses new inline
    constructions under `backend\`.

    NOT A SECRETS MECHANISM. This decides WHICH settings file is in play, never
    what may be stored in one. Secrets still belong in the `REPO_MGMT_*`
    environment variables; the host's secret-strip pass runs against whichever
    file this resolves, so pointing the host at a fixture does not relax it.
#>

Set-StrictMode -Version Latest

function Get-PortalSettingsPath {
    <#
    .SYNOPSIS
        Resolve the portal settings file, honouring REPO_MGMT_SETTINGS_PATH.
    .PARAMETER WorkspaceRoot
        The repository root. Used only for the default; an override ignores it,
        which is what lets a gate point the host at a file outside the repo.
    .OUTPUTS
        [string] absolute or caller-relative path to a settings.json.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$WorkspaceRoot)

    $override = [System.Environment]::GetEnvironmentVariable('REPO_MGMT_SETTINGS_PATH')
    if (-not [string]::IsNullOrWhiteSpace($override)) { return $override }

    Join-Path $WorkspaceRoot 'backend\config\settings.json'
}

function Test-PortalSettingsPathOverridden {
    <#
    .SYNOPSIS
        True when REPO_MGMT_SETTINGS_PATH is steering the host away from the
        tracked file.
    .DESCRIPTION
        For surfaces that must SAY they are running against a redirected config
        rather than let the operator assume otherwise -- the same rule the rest
        of this console follows about naming the basis of what it shows.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    -not [string]::IsNullOrWhiteSpace([System.Environment]::GetEnvironmentVariable('REPO_MGMT_SETTINGS_PATH'))
}
