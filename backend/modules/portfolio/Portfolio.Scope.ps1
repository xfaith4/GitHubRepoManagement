<#
    Release 3.5 milestone 3 -- exclude what is not the portfolio, visibly.

    Until this module, the scan admitted everything under the configured roots
    at depth 3: temp comparison folders inside other repos, Archive/ trees,
    linked worktrees, and vendored third-party clones nobody will ever write a
    ROADMAP for. Every percentage in the product was computed over that
    contaminated set -- reproduced 2026-08-15 on the live workspace, where
    `.tmp_compare/genesys-cloud-mcp-server`, six Archive/ paths, and a
    `.worktrees` directory all counted as first-class portfolio repos.

    The rule: NOTHING IS DELETED. A repo outside the scope is classified and
    stays visible behind a toggle -- a scan that silently drops repositories is
    the same class of lie as a metric that silently drops them.

    Identity: two locals sharing one remote are one repository, not two.
    Reproduced live: `Genesys.Core_AuditLogsApp` and `Genesys.Core` carry the
    same origin URL AND the same root commit (d884af1) -- a second clone, which
    the folder-name duplicate detector could see only as two unrelated names.
    Grouping is by normalized remote URL first (free -- the scan already holds
    it), subdivided by root-commit SHA only within colliding groups, so the
    disambiguating git call is paid only by the repos that need it.
#>

Set-StrictMode -Version Latest

# Release 3.2: the root-commit identity call is bounded like every other sweep
# git call -- one unreadable clone must not stall duplicate grouping.
if (-not (Get-Command Invoke-BoundedGitCommand -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot '..\git\Git.BoundedSweep.ps1')
}

function Get-RepoScopePolicy {
    <#
    .SYNOPSIS
        Resolve the scope policy from settings, with shipped defaults.
    .DESCRIPTION
        Pure over its input. `scope.excludePathPatterns` are PowerShell -like
        wildcards matched against the repo's full local path. `scope.owners`
        names the remote owners considered first-party; when empty, it falls
        back to `reconcile.gitHubOwner`, and when THAT is empty too, vendor
        classification is disabled (no owner set means no basis to call
        anything foreign -- absence of configuration must not shrink the
        portfolio).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter()][AllowNull()][object]$Settings = $null)

    $get = {
        param([object]$Obj, [string]$Name)
        if ($null -eq $Obj) { return $null }
        if ($Obj -is [System.Collections.IDictionary]) { if ($Obj.Contains($Name)) { return $Obj[$Name] } return $null }
        if ($Obj.PSObject.Properties.Name -contains $Name) { return $Obj.$Name }
        return $null
    }

    $scope = & $get $Settings 'scope'
    $patterns = @(& $get $scope 'excludePathPatterns')
    if (@($patterns | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }).Count -eq 0) {
        $patterns = @(
            '*\.tmp*',        # temp comparison/scratch dirs (.tmp_compare, .tmpXYZ)
            '*\Archive\*',    # archived trees kept on disk but out of the working portfolio
            '*.worktrees*',   # linked-worktree containers beside their repo
            '*\node_modules\*'
        )
    }

    $owners = @(& $get $scope 'owners' | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { ([string]$_).ToLowerInvariant() })
    if (@($owners).Count -eq 0) {
        $reconcile = & $get $Settings 'reconcile'
        $fallbackOwner = [string](& $get $reconcile 'gitHubOwner')
        if (-not [string]::IsNullOrWhiteSpace($fallbackOwner)) { $owners = @($fallbackOwner.ToLowerInvariant()) }
    }

    $enabledRaw = & $get $scope 'enabled'
    $enabled = if ($null -eq $enabledRaw) { $true } else { [bool]$enabledRaw }

    return [pscustomobject]@{
        enabled             = $enabled
        excludePathPatterns = @($patterns)
        owners              = @($owners)
    }
}

function Get-RepoScopeClassification {
    <#
    .SYNOPSIS
        Pure -- classify one repo against the policy.
    .DESCRIPTION
        Returns classification (in-scope | excluded-path | archived | vendored),
        inScope, and the reason with the matched pattern or owner named --
        every exclusion must be explainable on the tile that states it.

        Precedence: path rules beat ownership. A vendored clone parked under
        Archive/ is 'archived' -- where it LIVES outranks where it came from,
        because the path rule is the operator's own filing decision.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()][AllowEmptyString()][string]$LocalPath = '',
        [Parameter()][AllowEmptyString()][string]$OriginUrl = '',
        [Parameter()][AllowNull()][object]$Policy = $null
    )

    if ($null -eq $Policy) { $Policy = Get-RepoScopePolicy }

    $verdict = {
        param([string]$Classification, [string]$Reason, [string]$Matched = '')
        [pscustomobject]@{
            classification = $Classification
            inScope        = ($Classification -eq 'in-scope')
            reason         = $Reason
            matched        = $Matched
        }
    }

    if (-not $Policy.enabled) {
        return & $verdict 'in-scope' 'Scope policy is disabled; everything scanned is treated as portfolio.'
    }

    $normalizedPath = ([string]$LocalPath) -replace '/', '\'
    foreach ($pattern in @($Policy.excludePathPatterns)) {
        if ([string]::IsNullOrWhiteSpace([string]$pattern)) { continue }
        if ($normalizedPath -like [string]$pattern) {
            # Archive/ gets its own class so the exclusion tile can say
            # "vendored/archived" truthfully rather than lumping a filing
            # decision in with a temp dir.
            if (([string]$pattern) -like '*Archive*') {
                return & $verdict 'archived' ("Path matches the archive pattern '{0}' -- kept on disk, out of the working portfolio." -f $pattern) ([string]$pattern)
            }
            return & $verdict 'excluded-path' ("Path matches the exclusion pattern '{0}'." -f $pattern) ([string]$pattern)
        }
    }

    if (@($Policy.owners).Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($OriginUrl)) {
        $ownerMatch = [regex]::Match([string]$OriginUrl, '(?i)github\.com[:/](?<owner>[^/]+)/')
        if ($ownerMatch.Success) {
            $owner = $ownerMatch.Groups['owner'].Value.ToLowerInvariant()
            if ($owner -notin @($Policy.owners)) {
                return & $verdict 'vendored' ("Remote owner '{0}' is outside the configured owner set ({1}) -- a third-party clone, not portfolio work." -f $owner, (@($Policy.owners) -join ', ')) $owner
            }
        }
    }

    return & $verdict 'in-scope' 'In the working portfolio.'
}

function Get-RepoScopeSummary {
    <#
    .SYNOPSIS
        Pure -- the counts a tile needs to state its scope.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter()][AllowEmptyCollection()][object[]]$Classifications = @())

    $list = @($Classifications)
    $inScope = @($list | Where-Object { $null -ne $_ -and $_.inScope }).Count
    $vendored = @($list | Where-Object { $null -ne $_ -and $_.classification -eq 'vendored' }).Count
    $archived = @($list | Where-Object { $null -ne $_ -and $_.classification -eq 'archived' }).Count
    $excludedPath = @($list | Where-Object { $null -ne $_ -and $_.classification -eq 'excluded-path' }).Count

    return [pscustomobject]@{
        total        = $list.Count
        inScope      = $inScope
        excluded     = ($list.Count - $inScope)
        vendored     = $vendored
        archived     = $archived
        excludedPath = $excludedPath
    }
}

function Get-LocalRepoRootCommitSha {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory = $true)][string]$RepoPath)

    $result = Invoke-BoundedGitCommand -RepoPath $RepoPath -GitArgumentList @('rev-list', '--max-parents=0', 'HEAD')
    if ($result.TimedOut -or $result.ExitCode -ne 0) { return '' }
    # A repo grafted from multiple roots reports several; the first is stable.
    $shas = @(@($result.Lines) | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($shas.Count -eq 0) { return '' }
    return $shas[0]
}

function Group-RepoByRemoteIdentity {
    <#
    .SYNOPSIS
        Find locals that are the same repository -- clones sharing one remote.
    .DESCRIPTION
        Groups by normalized remote URL (free; the scan already holds it), then
        subdivides colliding groups by root-commit SHA -- the git call is paid
        only inside groups that actually collide. Returns only groups with more
        than one member: singletons are not news.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param([Parameter()][AllowEmptyCollection()][object[]]$Repos = @())

    $byUrl = @{}
    foreach ($repo in @($Repos)) {
        if ($null -eq $repo) { continue }
        $url = [string]$repo.originUrl
        if ([string]::IsNullOrWhiteSpace($url)) { continue }
        $key = $url.Trim().TrimEnd('/').ToLowerInvariant()
        if ($key.EndsWith('.git')) { $key = $key.Substring(0, $key.Length - 4) }
        if (-not $byUrl.ContainsKey($key)) { $byUrl[$key] = [System.Collections.Generic.List[object]]::new() }
        $byUrl[$key].Add($repo) | Out-Null
    }

    $groups = [System.Collections.Generic.List[object]]::new()
    foreach ($key in $byUrl.Keys) {
        $members = @($byUrl[$key])
        if ($members.Count -lt 2) { continue }

        # Subdivide by root commit: same URL + same root = one repository with
        # several checkouts; different roots would be unrelated repos that
        # happen to share a URL string and must not be merged.
        $byRoot = @{}
        foreach ($member in $members) {
            $root = Get-LocalRepoRootCommitSha -RepoPath ([string]$member.path)
            $rootKey = if ([string]::IsNullOrWhiteSpace($root)) { '(unreadable)' } else { $root }
            if (-not $byRoot.ContainsKey($rootKey)) { $byRoot[$rootKey] = [System.Collections.Generic.List[object]]::new() }
            $byRoot[$rootKey].Add($member) | Out-Null
        }
        foreach ($rootKey in $byRoot.Keys) {
            $same = @($byRoot[$rootKey])
            if ($same.Count -lt 2) { continue }
            $groups.Add([pscustomobject]@{
                remoteUrl     = $key
                rootCommitSha = $(if ($rootKey -eq '(unreadable)') { $null } else { $rootKey })
                paths         = @($same | ForEach-Object { [string]$_.path })
                names         = @($same | ForEach-Object { [string]$_.name })
            }) | Out-Null
        }
    }
    return @($groups)
}
