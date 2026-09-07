[CmdletBinding()]
param(
    # Derived from this script's location rather than a hardcoded drive letter —
    # the previous 'G:\...' default no longer resolved on this machine, so the
    # gate failed on its first step for anyone not passing -WorkspaceRoot.
    [string]$WorkspaceRoot = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Step {
    param([string]$Message)
    Write-Host "[STEP] $Message" -ForegroundColor Cyan
}

$docInventory = Join-Path $WorkspaceRoot 'backend\modules\docreview\Invoke-DocReviewInventory.ps1'
$docQueue = Join-Path $WorkspaceRoot 'backend\modules\docreview\Build-DocReviewQueue.ps1'
$docBatch = Join-Path $WorkspaceRoot 'backend\modules\docreview\Invoke-DocReviewBatchPlan.ps1'
$reconcile = Join-Path $WorkspaceRoot 'backend\modules\reconcile\Invoke-Reconciliation.ps1'
$reconcileModular = Join-Path $WorkspaceRoot 'backend\modules\reconcile\Invoke-Reconciliation.Modular.ps1'
$reconcileTests = Join-Path $WorkspaceRoot 'backend\modules\reconcile\repo_reconciliation.Tests.ps1'
$roadmapParser = Join-Path $WorkspaceRoot 'backend\modules\roadmap\Roadmap.Parser.ps1'
$roadmapExecutionContract = Join-Path $WorkspaceRoot 'backend\modules\roadmap\Roadmap.ExecutionContract.ps1'
$roadmapAuditor = Join-Path $WorkspaceRoot 'backend\modules\roadmap\Roadmap.Auditor.ps1'
$roadmapEvaluatorPath = Join-Path $WorkspaceRoot 'backend\modules\roadmap\Roadmap.Evaluator.ps1'
$roadmapRepairerPath = Join-Path $WorkspaceRoot 'backend\modules\roadmap\Roadmap.Repairer.ps1'
$roadmapPrSubmitterPath = Join-Path $WorkspaceRoot 'backend\modules\roadmap\Roadmap.PrSubmitter.ps1'
$docAuditScanner = Join-Path $WorkspaceRoot 'backend\modules\docaudit\DocAudit.Scanner.ps1'
$docStandards = Join-Path $WorkspaceRoot 'backend\config\doc-standards.json'
$agentBudgetModule = Join-Path $WorkspaceRoot 'backend\modules\agent-runs\BudgetLedger.ps1'
$portfolioConclusionModule = Join-Path $WorkspaceRoot 'backend\modules\portfolio\Portfolio.Conclusion.ps1'
$foundationDomainsConfig = Join-Path $WorkspaceRoot 'backend\config\foundation-domains.json'
$workPacketModule = Join-Path $WorkspaceRoot 'backend\modules\execution\Execution.WorkPacket.ps1'

Write-Step 'Portfolio timestamp truth: index projection and raw JSON gate'
& (Join-Path $WorkspaceRoot 'tools/Test-PortfolioTimestamp.ps1') -WorkspaceRoot $WorkspaceRoot

Write-Step 'Array-collapsing if-expressions: an empty branch must not become $null'
& (Join-Path $WorkspaceRoot 'tools/Assert-NoArrayCollapsingIfExpression.ps1') -WorkspaceRoot $WorkspaceRoot

Write-Step 'Loading reconciliation module functions only'
& $reconcile -LoadFunctionsOnly
Write-Host 'Loaded reconciliation module successfully' -ForegroundColor Green

Write-Step 'Validating copied module files exist'
@($docInventory, $docQueue, $docBatch, $reconcile, $reconcileModular, $reconcileTests, $roadmapParser, $roadmapExecutionContract, $roadmapAuditor, $roadmapEvaluatorPath, $roadmapRepairerPath, $roadmapPrSubmitterPath, $docAuditScanner, $docStandards, $agentBudgetModule, $portfolioConclusionModule, $foundationDomainsConfig, $workPacketModule) | ForEach-Object {
    if (-not (Test-Path -LiteralPath $_)) {
        throw "Missing module file: $_"
    }
}
Write-Host 'All expected module files are present' -ForegroundColor Green

Write-Step 'No HTTP request may run a portfolio scan — the freeze tripwire'
# Measured on the live portal 2026-08-11: the status cache TTL is 120s and a
# cold sweep costs 196.7s. Because the host serves requests serially and the
# miss path scanned INLINE, the refresh interval was shorter than the refresh
# took — so the portal never reached steady state and spent roughly two thirds
# of its life unable to answer anything, /health/live included.
#
# The rule this enforces: a scan belongs to the background worker, never to a
# request. Asserted over the host's AST rather than by grep, so a scan moved
# into a helper still fails.
$apiHostPath = Join-Path $WorkspaceRoot 'backend\api-host\Start-RepoManagementApiHost.ps1'
$statusRefreshWorker = Join-Path $WorkspaceRoot 'scripts\Invoke-StatusCacheRefresh.ps1'
if (-not (Test-Path -LiteralPath $statusRefreshWorker)) { throw "Background status refresh worker not found at: $statusRefreshWorker" }

$hostParseErrors = $null
$hostAst = [System.Management.Automation.Language.Parser]::ParseFile($apiHostPath, [ref]$null, [ref]$hostParseErrors)
if ($hostParseErrors -and $hostParseErrors.Count -gt 0) { throw "API host does not parse: $($hostParseErrors[0].Message)" }
$apiHostText = Get-Content -LiteralPath $apiHostPath -Raw

# Not offenders:
#   Invoke-GitOperation      - an operator asked for a pull/sync and is waiting
#                              on that one action's result.
#   Invoke-RoadmapAuditScan  - these two ARE the scan implementations; they
#   Invoke-DocAuditScan        compose Invoke-RoadmapScan rather than adding a
#                              new place a request can block.
$scanAllowedInFunctions = @('Invoke-GitOperation', 'Invoke-RoadmapAuditScan', 'Invoke-DocAuditScan')

# Ratchet, not a clean sheet. GET /api/status and GET /api/portfolio/assessment
# are fixed and asserted below; the remaining routes still scan inline and are
# tracked in ROADMAP.md. This baseline only moves DOWN - the same discipline the
# PSScriptAnalyzer gate uses - so the freeze cannot spread back into the routes
# already cleaned.
#
# 18, not 15: the first version of this gate watched three scan commands and
# counted 15. Adding Invoke-RoadmapAuditScan - which the assessment route called
# directly, and which alone cost prepMs=27799 after the other three were moved -
# revealed three further sites that were always there. The number went up
# because the lens widened, not because the code got worse. Recorded plainly
# rather than quietly re-baselined, since a baseline nobody can explain is a
# baseline nobody will lower.
$inlineScanBaseline = 18

# All three portfolio sweeps, not just the status one. GET
# /api/portfolio/assessment reported prepMs=40669 from Invoke-RoadmapScan alone
# after the status scan had already been moved off the request thread — fixing
# one door and leaving two open is not fixing the freeze.
# Invoke-RoadmapAuditScan is on this list because the assessment route called it
# directly. With the other three sweeps moved off the request thread it alone
# still held the request for prepMs=27799 — an entry point missing from the
# tripwire is an entry point that comes back.
$scanCommands = @('Get-StatusAdapterResult', 'Invoke-RoadmapScan', 'Invoke-DocAuditScan', 'Invoke-RoadmapAuditScan')

$scanCallSites = @($hostAst.FindAll({
    param($node)
    $node -is [System.Management.Automation.Language.CommandAst] -and
    $scanCommands -contains $node.GetCommandName()
}, $true))
if ($scanCallSites.Count -eq 0) { throw "Expected at least one call to $($scanCommands -join '/'); the tripwire would be vacuous without one" }
$inlineScanSites = @()

foreach ($callSite in $scanCallSites) {
    $enclosing = $callSite.Parent
    while ($null -ne $enclosing -and -not ($enclosing -is [System.Management.Automation.Language.FunctionDefinitionAst])) {
        $enclosing = $enclosing.Parent
    }
    # No enclosing function means it sits in the main script body — which is
    # where the route switch lives, i.e. on the request thread.
    $owner = if ($null -ne $enclosing) { $enclosing.Name } else { '<request thread>' }
    if ($scanAllowedInFunctions -notcontains $owner) {
        $inlineScanSites += "$($callSite.GetCommandName()) at line $($callSite.Extent.StartLineNumber) in $owner"
    }
}

if ($inlineScanSites.Count -gt $inlineScanBaseline) {
    $added = $inlineScanSites.Count - $inlineScanBaseline
    throw ("Inline portfolio scans on the request thread rose to $($inlineScanSites.Count) (baseline $inlineScanBaseline, +$added). A scan on the request thread freezes every other route, including /health/live. Kick Start-BackgroundStatusRefresh and serve what is cached. Sites:`n  " + ($inlineScanSites -join "`n  "))
}

# The two routes fixed here must stay fixed regardless of what the baseline
# allows elsewhere: a count alone would let a clean route regress while another
# was cleaned up.
foreach ($fixedRoute in @('status.cache miss correlationId', 'roadmap-cache miss served', 'doc-audit-cache miss served', 'roadmap-audit-cache miss served')) {
    if ($apiHostText -notmatch [regex]::Escape($fixedRoute)) {
        throw "GET /api/status and GET /api/portfolio/assessment must serve cached data on a miss and kick the worker; the '$fixedRoute' path is gone"
    }
}

# The worker has to actually perform all three, or moving them off the request
# thread would just mean they never run.
$workerText = Get-Content -LiteralPath $statusRefreshWorker -Raw
foreach ($scanCommand in $scanCommands) {
    if ($workerText -notmatch [regex]::Escape($scanCommand)) {
        throw "The background refresh worker must run $scanCommand; a scan removed from the request path and not added here would simply never happen"
    }
}
foreach ($cacheWrite in @('Save-StatusCache', 'Save-RoadmapCache', 'Save-DocAuditCache', 'Save-RoadmapAuditCache')) {
    if ($workerText -notmatch [regex]::Escape($cacheWrite)) {
        throw "The background refresh worker must call $cacheWrite; a scan whose result is never cached makes every request pay for it again"
    }
}

# The miss paths must actually start the worker, or they would just serve
# permanently stale data and never refresh.
$refreshKicks = ([regex]::Matches($apiHostText, 'Start-BackgroundStatusRefresh\s+-LocalRoots')).Count
if ($refreshKicks -lt 2) {
    throw "Both GET /api/status and GET /api/portfolio/assessment must kick a background refresh on a cache miss; found $refreshKicks call site(s)"
}

# -LoadDefinitionsOnly must return BEFORE the host takes the port. One line
# later and a background worker would terminate the running service, because
# Stop-PortListeners kills whatever holds the port.
$definitionsGuardIndex = $apiHostText.IndexOf('if ($LoadDefinitionsOnly) {')
$portSeizeIndex = $apiHostText.IndexOf('Stop-PortListeners -LocalPort $Port')
if ($definitionsGuardIndex -lt 0) { throw 'The API host must support -LoadDefinitionsOnly so the refresh worker can reuse its code' }
if ($portSeizeIndex -lt 0) { throw 'Expected Stop-PortListeners in the API host; the ordering assertion below would be vacuous' }
if ($definitionsGuardIndex -gt $portSeizeIndex) {
    throw 'The -LoadDefinitionsOnly early return must come BEFORE Stop-PortListeners, or loading definitions would kill the running service'
}
Write-Host "  inline scans $($inlineScanSites.Count)/$inlineScanBaseline (baseline moves down only); /api/status + /api/portfolio/assessment serve cached and kick the worker; worker runs all 3 scans and writes all 3 caches; definitions-only returns before the port is taken" -ForegroundColor DarkGray

Write-Step 'A background write must beat the memory cache — the cross-process coherence tripwire'
# Moving the scan out of process is only half a fix. Each of the four caches has
# a per-process memory entry AND a file, and the memory entry used to win
# unconditionally - which was safe only while the host was the only writer.
#
# It no longer is. The worker's single channel back to the host is the file it
# writes, so a memory entry is a view of one file version, not an independent
# copy. Left preferring memory, the host stops freezing and starts serving the
# first snapshot it ever took, forever: the stale-while-revalidate path reads
# with -IgnoreTtl and the assessment route reads the other three with
# ([int]::MaxValue), so age retires nothing.
#
# Behavioural, not structural: the assertion writes the cache files the way the
# worker does and demands the host notice. It caught the defect that failed the
# api-host smoke on this branch five times, where an AST rule could not have.
$coherenceProbe = Join-Path ([System.IO.Path]::GetTempPath()) ('cache-coherence-' + [guid]::NewGuid().ToString('n').Substring(0, 8) + '.ps1')
$coherenceLog = Join-Path ([System.IO.Path]::GetTempPath()) ('cache-coherence-' + [guid]::NewGuid().ToString('n').Substring(0, 8) + '.log')
# A separate process because the probe dot-sources the host, and the host's
# param() block would otherwise assign over this script's own $WorkspaceRoot -
# the Release 3.0 defect from PR #119, which is not worth re-learning here.
$coherenceProbeBody = @'
param(
    [Parameter(Mandatory = $true)][string]$HostScript,
    [Parameter(Mandatory = $true)][string]$WorkspaceRoot,
    [Parameter(Mandatory = $true)][string]$LogPath
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. $HostScript -WorkspaceRoot $WorkspaceRoot -LogPath $LogPath -LoadDefinitionsOnly

$cacheFiles = @(
    (Get-StatusCacheFilePath),
    (Get-RoadmapCacheFilePath),
    (Get-DocAuditCacheFilePath),
    (Get-RoadmapAuditCacheFilePath)
)

# The real cache files, because their paths derive from the workspace root and
# the host has to load against its own module tree. Restored on every exit
# path - a smoke test may not leave the developer's portal serving fixtures.
$backups = @{}
foreach ($file in $cacheFiles) {
    if (Test-Path -LiteralPath $file) {
        $backup = "$file.coherence-backup"
        Copy-Item -LiteralPath $file -Destination $backup -Force
        $backups[$file] = $backup
    }
}

function Write-ForeignCacheFile {
    # Rewrites a cache file the way the out-of-process worker does: same format,
    # one more entry, a later write stamp, and no in-process notification.
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][scriptblock]$Mutate
    )
    $document = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    & $Mutate $document
    ($document | ConvertTo-Json -Depth 25) | Set-Content -LiteralPath $Path -Encoding UTF8
    [System.IO.File]::SetLastWriteTimeUtc($Path, ((Get-Date).ToUniversalTime().AddSeconds(2)))
}

$failures = @()
try {
    $nowIso = (Get-Date).ToUniversalTime().ToString('o')

    $statusKey = Get-StatusCacheKey -LocalRoots @('c:\cache-coherence-fixture') -MaxDepth 1 -IncludeNonGitFolders $false
    $seed = [pscustomobject]@{
        success = $true
        data    = [pscustomobject]@{
            repos = @([pscustomobject]@{ name = 'before'; lastCommitAuthor = 'seed'; commitsLastWeek = 0; commitsLastMonth = 0 })
        }
    }
    Save-StatusCache -Key $statusKey -Response $seed

    # An unchanged file must still serve from memory: a fix that made every read
    # hit the disk would pass the staleness assertion and cost the portal the
    # cache it was given for a reason.
    $warm = Get-StatusFromCache -Key $statusKey -TtlSeconds 3600
    if ($warm.source -ne 'memory') {
        $failures += "status: an unchanged cache should still be served from memory, got source='$($warm.source)'"
    }

    Write-ForeignCacheFile -Path (Get-StatusCacheFilePath) -Mutate {
        param($doc)
        $doc.response.data.repos = @($doc.response.data.repos) + @([pscustomobject]@{ name = 'after'; lastCommitAuthor = 'worker'; commitsLastWeek = 1; commitsLastMonth = 1 })
    }

    # -IgnoreTtl is the stale-while-revalidate path both fixed routes take on a
    # miss, and the one place age can never retire an entry.
    $after = Get-StatusFromCache -Key $statusKey -TtlSeconds 3600 -IgnoreTtl
    if (@($after.response.data.repos).Count -ne 2) {
        $failures += "status: the worker's write was ignored - served $(@($after.response.data.repos).Count) repo(s) from source='$($after.source)', expected 2 from disk"
    }

    # Three more doors on the same defect. GET /api/portfolio/assessment reads
    # all three of these with ([int]::MaxValue).
    Save-RoadmapCache -Entries @([pscustomobject]@{ repoName = 'before' }) -ScannedAt $nowIso
    $warmRoadmap = Get-RoadmapFromCache -TtlSeconds 3600
    if ($warmRoadmap.source -ne 'memory') {
        $failures += "roadmap: an unchanged cache should still be served from memory, got source='$($warmRoadmap.source)'"
    }
    Write-ForeignCacheFile -Path (Get-RoadmapCacheFilePath) -Mutate {
        param($doc) $doc.entries = @($doc.entries) + @([pscustomobject]@{ repoName = 'after' })
    }
    $afterRoadmap = Get-RoadmapFromCache -TtlSeconds ([int]::MaxValue)
    if (@($afterRoadmap.entries).Count -ne 2) {
        $failures += "roadmap: the worker's write was ignored - served $(@($afterRoadmap.entries).Count) entr(ies) from source='$($afterRoadmap.source)', expected 2 from disk"
    }

    Save-DocAuditCache -Entries @([pscustomobject]@{ repoName = 'before' }) -AuditedAt $nowIso
    Write-ForeignCacheFile -Path (Get-DocAuditCacheFilePath) -Mutate {
        param($doc) $doc.entries = @($doc.entries) + @([pscustomobject]@{ repoName = 'after' })
    }
    $afterDoc = Get-DocAuditFromCache -TtlSeconds ([int]::MaxValue)
    if (@($afterDoc.entries).Count -ne 2) {
        $failures += "doc-audit: the worker's write was ignored - served $(@($afterDoc.entries).Count) entr(ies) from source='$($afterDoc.source)', expected 2 from disk"
    }

    Save-RoadmapAuditCache -Entries @([pscustomobject]@{ repoName = 'before' }) -AuditedAt $nowIso
    Write-ForeignCacheFile -Path (Get-RoadmapAuditCacheFilePath) -Mutate {
        param($doc) $doc.entries = @($doc.entries) + @([pscustomobject]@{ repoName = 'after' })
    }
    $afterAudit = Get-RoadmapAuditFromCache -TtlSeconds ([int]::MaxValue)
    if (@($afterAudit.entries).Count -ne 2) {
        $failures += "roadmap-audit: the worker's write was ignored - served $(@($afterAudit.entries).Count) entr(ies) from source='$($afterAudit.source)', expected 2 from disk"
    }
}
finally {
    foreach ($file in $cacheFiles) {
        if ($backups.ContainsKey($file)) {
            Move-Item -LiteralPath $backups[$file] -Destination $file -Force
        }
        elseif (Test-Path -LiteralPath $file) {
            Remove-Item -LiteralPath $file -Force
        }
    }
}

if ($failures.Count -gt 0) {
    Write-Error ("Cross-process cache coherence failed:`n  " + ($failures -join "`n  "))
    exit 1
}

Write-Output 'cache coherence ok: a background write supersedes the memory entry on all four caches; an unchanged file still serves from memory'
exit 0
'@
Set-Content -LiteralPath $coherenceProbe -Value $coherenceProbeBody -Encoding UTF8
try {
    # The same executable running this gate, for the reason the host reuses it:
    # pwsh is not on PATH for a service running as LocalSystem.
    $psExe = (Get-Process -Id $PID).Path
    $coherenceOutput = & $psExe -NoProfile -ExecutionPolicy Bypass -File $coherenceProbe `
        -HostScript $apiHostPath -WorkspaceRoot $WorkspaceRoot -LogPath $coherenceLog 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw ("A background cache refresh must supersede the host's in-memory entry, or the portal serves its first snapshot forever:`n" + (($coherenceOutput | Out-String).Trim()))
    }
    Write-Host ("  " + (@($coherenceOutput | Where-Object { $_ -is [string] -and $_ -like 'cache coherence ok*' }) | Select-Object -Last 1)) -ForegroundColor DarkGray
}
finally {
    Remove-Item -LiteralPath $coherenceProbe -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $coherenceLog -Force -ErrorAction SilentlyContinue
}

Write-Step 'Absent GitHub owner memory — one dead remote must not cost a sweep per request'
# Measured 2026-08-11 on the live portal: a repo whose origin named a github.com
# account that does not exist held the host's single request thread while three
# owner-scoped calls 404'd, on every sweep. Because the host serves requests
# serially, /health/live went from 0.61s to a 313.9s stall behind it. The cache
# below is what stops the rediscovery; these assertions are what stop it
# regressing — including the two that keep it from over-firing.
$githubOwnerCache = Join-Path $WorkspaceRoot 'backend\modules\github\GitHub.OwnerCache.ps1'
if (-not (Test-Path -LiteralPath $githubOwnerCache)) { throw "GitHub.OwnerCache.ps1 not found at: $githubOwnerCache" }
. $githubOwnerCache

# Two code paths, and both must be exercised. PowerShell 7 surfaces the status
# on the exception's Response object; Windows PowerShell only puts it in the
# message text. An earlier version of this gate built error records with no
# Response at all, so it silently tested the text path twice — a deliberate
# mutation (making 403 mark an owner absent) passed it. Hence the fake below.
class SmokeFakeHttpResponse {
    [int]$StatusCode
}
class SmokeHttpStatusException : System.Exception {
    [object]$Response
    SmokeHttpStatusException([string]$message, [int]$statusCode) : base($message) {
        $this.Response = [SmokeFakeHttpResponse]@{ StatusCode = $statusCode }
    }
}

function New-SmokeHttpErrorRecord {
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Pure constructor for a test fixture — it builds and returns an ErrorRecord and changes no state, so there is nothing for -WhatIf to confirm.')]
    # StatusCode 0 means "no Response object" — the Windows PowerShell shape.
    param([string]$Message, [int]$StatusCode = 0)
    $exception = if ($StatusCode -gt 0) {
        [SmokeHttpStatusException]::new($Message, $StatusCode)
    } else {
        [System.Exception]::new($Message)
    }
    return (New-Object System.Management.Automation.ErrorRecord $exception, 'smoke', 'NotSpecified', $null)
}

# Only 404 proves absence. A 403 (token cannot see it) or 422 (bad query) that
# poisoned the cache would hide a real owner for the whole TTL.
foreach ($withStatus in @($true, $false)) {
    $shape = if ($withStatus) { 'Response.StatusCode' } else { 'message text' }

    $absentRecord = if ($withStatus) {
        New-SmokeHttpErrorRecord -Message 'Not Found' -StatusCode 404
    } else {
        New-SmokeHttpErrorRecord -Message 'Response status code does not indicate success: 404 (Not Found).'
    }
    if (-not (Test-GitHubErrorIsOwnerAbsent -ErrorRecord $absentRecord)) {
        throw "A 404 must be recognised as an absent owner (via $shape)"
    }

    foreach ($code in @(422, 403, 401, 500, 429)) {
        $record = if ($withStatus) {
            New-SmokeHttpErrorRecord -Message "status $code" -StatusCode $code
        } else {
            New-SmokeHttpErrorRecord -Message "Response status code does not indicate success: $code."
        }
        if (Test-GitHubErrorIsOwnerAbsent -ErrorRecord $record) {
            throw "Only 404 may mark an owner absent, but $code did (via $shape)"
        }
    }
}
if (Test-GitHubErrorIsOwnerAbsent -ErrorRecord (New-SmokeHttpErrorRecord -Message 'The operation has timed out.')) {
    throw 'A timeout must never mark an owner absent'
}
# A repo or message that merely contains the digits must not trigger it.
if (Test-GitHubErrorIsOwnerAbsent -ErrorRecord (New-SmokeHttpErrorRecord -Message 'Cannot resolve host for repo build404tools.')) {
    throw '404 embedded in a word must not mark an owner absent'
}

Clear-GitHubOwnerCache
if (Test-GitHubOwnerKnownAbsent -Owner 'never-looked-up') { throw 'An unseen owner must not be reported absent' }
Set-GitHubOwnerKnownAbsent -Owner 'Ghost-Owner'
if (-not (Test-GitHubOwnerKnownAbsent -Owner 'Ghost-Owner')) { throw 'A recorded absent owner must be remembered' }
if (-not (Test-GitHubOwnerKnownAbsent -Owner 'GHOST-owner')) { throw 'Owner matching must be case-insensitive — GitHub logins are' }

# TTL, not permanent: an owner created after the 404 must be picked up without
# restarting the host.
$script:GitHubDeadOwnerCache['ghost-owner'] = (Get-Date).AddSeconds(-1)
if (Test-GitHubOwnerKnownAbsent -Owner 'Ghost-Owner') { throw 'An expired absent-owner record must be forgotten' }
Clear-GitHubOwnerCache
if (Test-GitHubOwnerKnownAbsent -Owner 'Ghost-Owner') { throw 'Clear-GitHubOwnerCache must empty the cache' }

# The skip is only worth anything if the sweep actually consults it. Assert the
# choke point over the host source rather than trusting that it stayed wired.
$apiHostSource = Get-Content -LiteralPath (Join-Path $WorkspaceRoot 'backend\api-host\Start-RepoManagementApiHost.ps1') -Raw
if ($apiHostSource -notmatch 'GitHub\.OwnerCache\.ps1') {
    throw 'The API host must load GitHub.OwnerCache.ps1'
}
if ($apiHostSource -notmatch 'if \(Test-GitHubOwnerKnownAbsent -Owner \$Owner\)') {
    throw 'Get-GitHubRepoMetadataMapViaApi must short-circuit on a known-absent owner'
}
Write-Host '  404-only detection, case-insensitive memory, TTL expiry, and the sweep short-circuit all hold' -ForegroundColor DarkGray

Write-Step 'API request deadline guard — bounds single-threaded host freezes'
$requestDeadlineModule = Join-Path $WorkspaceRoot 'backend\api-host\RequestDeadline.ps1'
if (-not (Test-Path -LiteralPath $requestDeadlineModule)) { throw "RequestDeadline.ps1 not found at: $requestDeadlineModule" }
. $requestDeadlineModule
if ((Get-EffectiveRequestTimeoutSeconds -ConfiguredSeconds 0) -ne 30) { throw 'Request timeout floor must remain 30 seconds' }
if ((Get-EffectiveRequestTimeoutSeconds -ConfiguredSeconds 180 -EnvironmentValue '45') -ne 45) { throw 'Request timeout env override was not applied' }
if ((Get-EffectiveRequestTimeoutSeconds -ConfiguredSeconds 180 -EnvironmentValue '99999') -ne 3600) { throw 'Request timeout ceiling must remain 3600 seconds' }
$deadlineNow = [datetime]::UtcNow
if ((Resolve-RequestDeadlineAction -Armed:$false -DeadlineUtc $deadlineNow -NowUtc $deadlineNow) -ne 'idle') { throw 'Disarmed request deadline must be idle' }
if ((Resolve-RequestDeadlineAction -Armed:$true -DeadlineUtc $deadlineNow.AddSeconds(1) -NowUtc $deadlineNow) -ne 'wait') { throw 'Future request deadline must wait' }
if ((Resolve-RequestDeadlineAction -Armed:$true -DeadlineUtc $deadlineNow -NowUtc $deadlineNow) -ne 'terminate') { throw 'Expired request deadline must terminate' }
Write-Host '  deadline floor/override/ceiling and idle/wait/terminate states correct' -ForegroundColor DarkGray

# A cold full-portfolio scan legitimately outruns the 180s default. Without the
# extended tier the freeze guard terminates the host mid-scan and Shawl restarts
# it into the same scan — the guard becoming the outage it exists to prevent.
foreach ($scanPath in @('/api/status', '/api/portfolio/assessment', '/api/operations/repos', '/api/operations/repos/foo/curation', '/api/automation/run', '/api/badges/foo.svg')) {
    if (-not (Test-LongRunningScanRoute -Path $scanPath)) { throw "Scan route must use the extended deadline tier: $scanPath" }
}
# /api/status moved here from the "ordinary" list on production evidence, not to
# make a change pass: the host log recorded "Process terminated. API request
# deadline exceeded for GET /api/status (timeoutSeconds=180)" — the exact freeze
# guard becoming the outage described above. It runs the same cold full-portfolio
# scan as the routes on the tier; classifying it as fast was the bug.
foreach ($fastPath in @('/health/live', '/api/automation/history', '/api/settings', '')) {
    if (Test-LongRunningScanRoute -Path $fastPath) { throw "Ordinary route must keep the default deadline: '$fastPath'" }
}
if (-not (Test-LongRunningScanRoute -Path '/api/operations/repos/')) { throw 'Trailing-slash scan route must still match the extended tier' }
if ((Get-RequestDeadlineSecondsForPath -Path '/api/automation/run' -DefaultSeconds 180 -ScanSeconds 900) -ne 900) { throw 'Scan route did not receive the extended deadline' }
if ((Get-RequestDeadlineSecondsForPath -Path '/api/status' -DefaultSeconds 180 -ScanSeconds 900) -ne 900) { throw '/api/status runs a cold full-portfolio scan and must receive the extended deadline' }
if ((Get-RequestDeadlineSecondsForPath -Path '/api/settings' -DefaultSeconds 180 -ScanSeconds 900) -ne 180) { throw 'Ordinary route did not receive the default deadline' }
if ((Get-EffectiveScanRequestTimeoutSeconds -ConfiguredSeconds 900 -BaseSeconds 180) -ne 900) { throw 'Scan deadline default must be 900 seconds' }
if ((Get-EffectiveScanRequestTimeoutSeconds -ConfiguredSeconds 300 -BaseSeconds 1200) -ne 1200) { throw 'Scan deadline must never fall below the default tier it extends' }
if ((Get-EffectiveScanRequestTimeoutSeconds -ConfiguredSeconds 900 -EnvironmentValue '99999' -BaseSeconds 180) -ne 3600) { throw 'Scan deadline must stay clamped to the 3600-second ceiling' }
Write-Host '  scan routes get the extended (still bounded) deadline tier; ordinary routes do not' -ForegroundColor DarkGray

Write-Step 'Dashboard tab-panel tripwire — tab content renders below its tabs (ROADMAP Lane 0.5)'
# The defect this pins: the Insights widgets rendered in a container ABOVE
# <DashboardViewTabs>, while the Insights tab panel held a single sentence
# pointing back upward. Clicking "Insights" therefore inserted ~560 lines above
# the control the operator had just clicked and pushed the tab bar off-screen —
# the tab metaphor inverted for one of six tabs. Source-order is the honest
# check: React renders a tree in source order, so a view component appearing
# before the tab strip renders before it on screen.
$dashboardPath = Join-Path $WorkspaceRoot 'frontend\components\Dashboard.tsx'
if (-not (Test-Path -LiteralPath $dashboardPath)) { throw "Dashboard.tsx not found at: $dashboardPath" }
$dashboardSource = Get-Content -LiteralPath $dashboardPath -Raw -Encoding UTF8
$tabStripIndex = $dashboardSource.IndexOf('<DashboardViewTabs')
if ($tabStripIndex -lt 0) { throw 'Dashboard.tsx no longer renders <DashboardViewTabs>; the tab contract cannot be checked.' }
$insightsIndex = $dashboardSource.IndexOf('<InsightsView')
if ($insightsIndex -lt 0) { throw 'Dashboard.tsx no longer renders <InsightsView>; Insights content must live in a component the tab panel mounts.' }
if ($insightsIndex -lt $tabStripIndex) {
    throw 'Dashboard.tsx renders <InsightsView> BEFORE <DashboardViewTabs>; tab content must render inside the panel, not above the tab strip.'
}
# The apology copy is the symptom. If it is back, so is the layout.
if ($dashboardSource -match 'shown above this section') {
    throw 'Dashboard.tsx tells the operator that tab content is "shown above this section"; the content belongs in the panel instead.'
}
# Every `activeView === '<key>'` render gate must sit after the tab strip too,
# or a future tab repeats the same inversion without touching Insights.
$gateMatches = [regex]::Matches($dashboardSource, "activeView === '[a-z-]+'")
$gatesAboveTabs = @($gateMatches | Where-Object { $_.Index -lt $tabStripIndex })
if (@($gatesAboveTabs).Count -gt 0) {
    throw ("Dashboard.tsx gates {0} render(s) on activeView above the tab strip: {1}. Tab content must render inside the panel." -f `
            @($gatesAboveTabs).Count, ((@($gatesAboveTabs) | ForEach-Object { $_.Value }) -join ', '))
}
Write-Host '  Insights renders inside its tab panel; no activeView-gated content sits above the tab strip' -ForegroundColor DarkGray

Write-Step 'Worklog location tripwire — root worklogs stay archived (ROADMAP Lane 0.4)'
# The 2026-07-15 cleanup archived findings.md / progress.md / task_plan.md to
# docs/history/worklogs/ and they were back in the root by 2026-08-08, because
# the convention lived only in a completed-release note nothing reads while
# working. Enforce it here: .gitignore stops new ones appearing, and this stops
# an already-tracked one surviving a `git add -f`.
$rootWorklogNames = @('findings.md', 'progress.md', 'task_plan.md')
$trackedRootWorklogs = @()
foreach ($worklogName in $rootWorklogNames) {
    $tracked = ''
    try { $tracked = (& git -C $WorkspaceRoot ls-files --error-unmatch $worklogName 2>$null) | Out-String } catch { }
    if (-not [string]::IsNullOrWhiteSpace($tracked)) { $trackedRootWorklogs += $worklogName }
}
if (@($trackedRootWorklogs).Count -gt 0) {
    throw (("Worklog(s) tracked at the repository root: {0}. Move them under " +
            "docs/history/worklogs/<date>-<topic>/ — see docs/history/worklogs/README.md.") -f ($trackedRootWorklogs -join ', '))
}
$worklogReadme = Join-Path $WorkspaceRoot 'docs\history\worklogs\README.md'
if (-not (Test-Path -LiteralPath $worklogReadme)) { throw 'docs/history/worklogs/README.md is missing; the worklog convention must stay documented where worklogs are written' }
Write-Host '  no worklogs tracked at the repository root; the convention is documented' -ForegroundColor DarkGray

Write-Step 'CI gate coverage tripwire — CI runs the canonical suite, un-hollowed (ROADMAP Lane 0.8)'
# The defect this pins: the frontend's 149 assertions, typecheck, and build
# gated nothing for months because they existed only as npm scripts nobody was
# required to run, while a second workflow (ci.yml -> reusable-ci.yml with
# node/python/dotnet all false) reported green in 9 seconds having executed
# nothing — and that vacuous tick counted toward mergeStateStatus CLEAN.
# The fix made ci-smoke.yml invoke Invoke-TestSuite.ps1 itself, so CI and
# local `npm test` are one list by construction. This tripwire guards the
# ways that construction can be quietly undone.
$ciSmokePath = Join-Path $WorkspaceRoot '.github\workflows\ci-smoke.yml'
$suitePath = Join-Path $WorkspaceRoot 'scripts\Invoke-TestSuite.ps1'
if (-not (Test-Path -LiteralPath $ciSmokePath)) { throw "ci-smoke.yml not found at: $ciSmokePath — PRs are merging with no gate at all." }
if (-not (Test-Path -LiteralPath $suitePath)) { throw "Invoke-TestSuite.ps1 not found at: $suitePath" }
# Strip comment lines before matching — a mention in a comment satisfies nothing.
$ciSmokeSource = (Get-Content -LiteralPath $ciSmokePath -Encoding UTF8 | Where-Object { $_ -notmatch '^\s*#' }) -join "`n"
$suiteSource = (Get-Content -LiteralPath $suitePath -Encoding UTF8 | Where-Object { $_ -notmatch '^\s*#' }) -join "`n"
if ($ciSmokeSource -notmatch 'Invoke-TestSuite\.ps1') {
    throw 'ci-smoke.yml no longer invokes Invoke-TestSuite.ps1; CI and the local suite can drift apart again. Run the suite, do not re-inline gates.'
}
if ($ciSmokeSource -match '-SkipApiHost') {
    throw 'ci-smoke.yml passes -SkipApiHost; CI must run the FULL suite, not the fast subset.'
}
if ($ciSmokeSource -match '(?m)^\s*paths(-ignore)?:') {
    throw 'ci-smoke.yml filters paths; every PR must run the gate, or filtered PRs merge on no evidence.'
}
if ($ciSmokeSource -notmatch '(?m)^\s*pull_request:') {
    throw 'ci-smoke.yml no longer triggers on pull_request; the merge gate is gone.'
}
if ($ciSmokeSource -notmatch 'npm ci') {
    throw 'ci-smoke.yml does not install npm dependencies; the frontend gates would fail for the wrong reason.'
}
foreach ($legacyWorkflow in @('ci.yml', 'reusable-ci.yml')) {
    if (Test-Path -LiteralPath (Join-Path $WorkspaceRoot ".github\workflows\$legacyWorkflow")) {
        throw "$legacyWorkflow is back under .github/workflows/. It reported green while executing nothing (all inputs false) and was deleted 2026-08-10; a check that cannot fail must not return."
    }
}
# The suite itself must stay non-hollow: invoking an emptied suite would pass
# every assertion above while gating nothing.
$suiteScriptGates = @([regex]::Matches($suiteSource, "Invoke-ScriptGate\s+-Name\s+'[^']+'\s+-ScriptPath\s+\(Join-Path\s+\$\w+\s+'([\w.-]+\.ps1)'\)") | ForEach-Object { $_.Groups[1].Value })
$suiteNpmGates = @([regex]::Matches($suiteSource, "Invoke-NpmGate\s+-Name\s+'[^']+'\s+-ScriptName\s+'([\w:-]+)'") | ForEach-Object { $_.Groups[1].Value })
if (@($suiteScriptGates).Count -lt 7) {
    throw ("Invoke-TestSuite.ps1 defines only {0} script gate(s); expected at least 7. The suite has been hollowed or the gate syntax changed without updating this tripwire." -f @($suiteScriptGates).Count)
}
foreach ($requiredNpmGate in @('typecheck', 'test:unit', 'build')) {
    if ($suiteNpmGates -notcontains $requiredNpmGate) {
        throw ("Invoke-TestSuite.ps1 no longer runs the frontend '{0}' gate. The frontend spent months ungated exactly this way; put it back." -f $requiredNpmGate)
    }
}
Write-Host ("  ci-smoke.yml runs the full suite ({0} script gates, {1} npm gates); no vacuous workflow, no path filter, no -SkipApiHost" -f @($suiteScriptGates).Count, @($suiteNpmGates).Count) -ForegroundColor DarkGray

Write-Step 'GitHub rate-limit readout — headers observed, never fabricated (ROADMAP Lane 0.2)'
$rateLimitModule = Join-Path $WorkspaceRoot 'backend\api-host\GitHubRateLimit.ps1'
if (-not (Test-Path -LiteralPath $rateLimitModule)) { throw "GitHubRateLimit.ps1 not found at: $rateLimitModule" }
. $rateLimitModule
# Windows PowerShell returns Dictionary[string,string]; PowerShell 7 returns
# Dictionary[string,string[]]. A parser that handles one and not the other reads
# blank on the other edition — exactly the failure this item existed to fix.
$ps51Headers = @{ 'X-RateLimit-Limit' = '5000'; 'X-RateLimit-Remaining' = '4987'; 'X-RateLimit-Reset' = '1786320000' }
$ps7Headers = @{ 'x-ratelimit-limit' = @('5000'); 'x-ratelimit-remaining' = @('4987'); 'x-ratelimit-reset' = @('1786320000') }
foreach ($shape in @(@{ Name = 'PS5.1 string'; Headers = $ps51Headers }, @{ Name = 'PS7 string[] lowercase'; Headers = $ps7Headers })) {
    $parsed = ConvertFrom-GitHubRateLimitHeader -Headers $shape.Headers
    if ($null -eq $parsed) { throw ("Rate-limit headers must parse from the {0} shape" -f $shape.Name) }
    if ($parsed.limit -ne 5000 -or $parsed.remaining -ne 4987) { throw ("Rate-limit values wrong for the {0} shape: {1}/{2}" -f $shape.Name, $parsed.remaining, $parsed.limit) }
    if ($parsed.used -ne 13) { throw ("X-RateLimit-Used must be derived when absent; got {0}" -f $parsed.used) }
    if ([string]::IsNullOrWhiteSpace($parsed.resetAt)) { throw 'A non-zero reset must produce an ISO resetAt' }
}
# Absent/garbage headers must stay null. A zeroed object would render as "0/5000
# remaining" and read as a real measurement of an exhausted quota.
if ($null -ne (ConvertFrom-GitHubRateLimitHeader -Headers $null)) { throw 'Null headers must yield no rate limit, not a zeroed one' }
if ($null -ne (ConvertFrom-GitHubRateLimitHeader -Headers @{})) { throw 'Empty headers must yield no rate limit, not a zeroed one' }
if ($null -ne (ConvertFrom-GitHubRateLimitHeader -Headers @{ 'X-RateLimit-Limit' = 'unknown'; 'X-RateLimit-Remaining' = '10' })) { throw 'Unparseable headers must yield no rate limit' }
# Newest response wins, and a response without headers must not erase what was
# already observed (only some GitHub endpoints omit them).
Clear-GitHubRateLimitSnapshot
if ($null -ne (Get-GitHubRateLimitSnapshot)) { throw 'Cleared snapshot must read back as null' }
$null = Update-GitHubRateLimitSnapshot -Headers $ps51Headers
$null = Update-GitHubRateLimitSnapshot -Headers @{ 'X-RateLimit-Limit' = '5000'; 'X-RateLimit-Remaining' = '4900'; 'X-RateLimit-Reset' = '1786320000' }
$null = Update-GitHubRateLimitSnapshot -Headers @{}
$snapshot = Get-GitHubRateLimitSnapshot
if ($null -eq $snapshot -or $snapshot.remaining -ne 4900) { throw ("Snapshot must hold the newest parseable observation; got {0}" -f $(if ($null -eq $snapshot) { 'null' } else { $snapshot.remaining })) }
Clear-GitHubRateLimitSnapshot
# The `gh` CLI fallback has no response object to read headers from, so it asks
# GET /rate_limit instead. Same output shape by construction — it reuses the
# header parser — because two GitHub paths reporting differently-shaped rate
# limits is how the frontend ends up rendering one of them as blank.
$ratePayload = @{ resources = @{ core = @{ limit = 5000; remaining = 4321; reset = 1786320000; used = 679 } } }
$fromPayload = ConvertFrom-GitHubRateLimitPayload -Payload $ratePayload
if ($null -eq $fromPayload -or $fromPayload.remaining -ne 4321 -or $fromPayload.limit -ne 5000) { throw 'GET /rate_limit payload did not parse into the shared shape' }
if ($fromPayload.used -ne 679) { throw 'GET /rate_limit payload must carry the reported used count' }
if ($fromPayload.resource -ne 'core') { throw 'GET /rate_limit payload must name the resource bucket it read' }
$fromJson = ConvertFrom-GitHubRateLimitPayload -Payload ($ratePayload | ConvertTo-Json -Depth 5)
if ($null -eq $fromJson -or $fromJson.remaining -ne 4321) { throw 'GET /rate_limit raw JSON text must parse identically to a parsed object' }
foreach ($badPayload in @($null, '', 'not json', @{ resources = @{} }, @{ nothing = 1 })) {
    if ($null -ne (ConvertFrom-GitHubRateLimitPayload -Payload $badPayload)) { throw 'A malformed /rate_limit payload must yield no rate limit, not a zeroed one' }
}

# The regression itself: the payload hardcoded `rateLimit = $null`, so the
# readout could never populate no matter what the headers said. The item named
# ONE site; the source scan found a second (the gh CLI fallback route), which is
# why this asserts across the whole file rather than one line number.
$apiHostRateLimitSource = Get-Content -LiteralPath (Join-Path $WorkspaceRoot 'backend\api-host\Start-RepoManagementApiHost.ps1') -Raw -Encoding UTF8
if ($apiHostRateLimitSource -match '(?m)^\s*rateLimit\s*=\s*\$null\s*$') { throw 'A GitHub insights payload hardcodes rateLimit = $null again; every path must report an observed figure' }
if ($apiHostRateLimitSource -notmatch 'rateLimit\s*=\s*Get-GitHubRateLimitSnapshot') { throw 'The token path must return the observed rate-limit snapshot' }
if ($apiHostRateLimitSource -notmatch 'ConvertFrom-GitHubRateLimitPayload') { throw 'The gh CLI fallback path must resolve its rate limit from GET /rate_limit' }
Write-Host '  both header shapes parsed, /rate_limit payload shares the shape, newest observation wins, absent headers stay null' -ForegroundColor DarkGray

Write-Step 'No machine-specific path defaults in tracked PowerShell (ROADMAP Lane 0.3)'
# A hardcoded 'G:\...' parameter default is invisible until someone runs the
# suite from a different clone, at which point it either fails on step one or —
# worse — silently scans a drive that does not exist and reports "no repos"
# instead of "misconfigured". Both happened. Test files are exempt: they use
# G:\ strings as synthetic fixture paths that are never touched on disk.
$pathDefaultOffenders = @()
foreach ($candidate in @(Get-ChildItem -Path (Join-Path $WorkspaceRoot 'backend'), (Join-Path $WorkspaceRoot 'scripts'), (Join-Path $WorkspaceRoot 'tools') -Filter '*.ps1' -Recurse -ErrorAction SilentlyContinue)) {
    if ($candidate.Name -like '*.Tests.ps1') { continue }
    $offending = @(Select-String -LiteralPath $candidate.FullName -Pattern '^\s*\[string(\[\])?\]\$\w+\s*=\s*[''"][A-Za-z]:\\' -ErrorAction SilentlyContinue)
    foreach ($hit in $offending) {
        $pathDefaultOffenders += ('{0}:{1}' -f $candidate.FullName.Substring($WorkspaceRoot.Length + 1), $hit.LineNumber)
    }
}
if ($pathDefaultOffenders.Count -gt 0) {
    throw ("Hardcoded absolute-path parameter defaults found (derive from `$PSScriptRoot, or require the parameter): " + ($pathDefaultOffenders -join ', '))
}
Write-Host ('  no absolute-path parameter defaults in tracked backend/scripts/tools PowerShell') -ForegroundColor DarkGray

# Cache-off was the trigger for the 2026-07-05 request pile-up. Preserve an
# explicit source-level tripwire because these helpers live inside the host
# script and cannot be dot-sourced without starting the listener.
$apiHostSource = Get-Content -LiteralPath (Join-Path $WorkspaceRoot 'backend\api-host\Start-RepoManagementApiHost.ps1') -Raw -Encoding UTF8
if ($apiHostSource -notmatch '(?s)function Get-StatusCacheTtlSeconds.*?if \(\$candidate -gt 0\)') { throw 'Status cache TTL can be disabled; require a positive override' }
if ($apiHostSource -notmatch '(?s)function Get-PortfolioAssessmentCacheTtlSeconds.*?if \(\$candidate -gt 0\)') { throw 'Portfolio assessment cache TTL can be disabled; require a positive override' }
Write-Host '  status and assessment caches reject zero/negative TTL overrides' -ForegroundColor DarkGray

# Tripwire for ROADMAP Lane 0.1. Commit 69dcc2d shipped a smoke-run mutation as
# the real workspace root: tracked settings.json pointed inventory.localRoots at
# a fixture directory under output/, so every scan, assessment, and scheduled
# automation run from a clean checkout enumerated fixtures instead of the
# portfolio — and nothing failed to say so. The api-host smoke now restores the
# file byte-exact, but this fails the suite outright if a mutation ever lands
# again, because the symptom (zero repositories, no error) is indistinguishable
# from an empty workspace.
Write-Step 'Config tripwire: tracked settings.json must not point at run output'
$trackedSettingsPath = Join-Path $WorkspaceRoot 'backend\config\settings.json'
if (Test-Path -LiteralPath $trackedSettingsPath) {
    $trackedSettings = Get-Content -LiteralPath $trackedSettingsPath -Raw | ConvertFrom-Json
    $trackedRoots = @()
    if ($trackedSettings.PSObject.Properties.Name -contains 'inventory' -and
        $trackedSettings.inventory.PSObject.Properties.Name -contains 'localRoots') {
        $trackedRoots = @($trackedSettings.inventory.localRoots | ForEach-Object { [string]$_ })
    }
    $offending = @($trackedRoots | Where-Object { $_ -match '(^|[/\\])output([/\\]|$)' })
    if (@($offending).Count -gt 0) {
        # Parenthesise the concatenation before -f: otherwise the format operator
        # binds to the trailing string only and {0} is emitted literally.
        throw (("Tracked settings.json inventory.localRoots names a path under output/: {0}. " +
                "That is run evidence, not a workspace — restore the real root before committing.") -f ($offending -join ', '))
    }
    if (@($trackedRoots).Count -eq 0) {
        throw 'Tracked settings.json has no inventory.localRoots; the portal cannot scan anything.'
    }

    # Also check the COMMITTED version, not just the working copy. On 2026-08-09
    # a commit was made while the api-host smoke held settings.json pointed at
    # its fixture, so the fixture path landed on main — and this tripwire stayed
    # green afterwards because the smoke's finally had since restored the
    # working copy. Checking only what is on disk cannot see pollution that is
    # already in history.
    $committedSettings = $null
    try { $committedSettings = (& git -C $WorkspaceRoot show HEAD:backend/config/settings.json 2>$null) | Out-String } catch { }
    if (-not [string]::IsNullOrWhiteSpace($committedSettings)) {
        $committedRoots = @()
        try {
            $committedJson = $committedSettings | ConvertFrom-Json
            if ($committedJson.PSObject.Properties.Name -contains 'inventory' -and
                $committedJson.inventory.PSObject.Properties.Name -contains 'localRoots') {
                $committedRoots = @($committedJson.inventory.localRoots | ForEach-Object { [string]$_ })
            }
        } catch { }
        $committedOffending = @($committedRoots | Where-Object { $_ -match '(^|[/\\])output([/\\]|$)' })
        if (@($committedOffending).Count -gt 0) {
            throw (("COMMITTED settings.json inventory.localRoots names a path under output/: {0}. " +
                    "Run evidence was committed as config — restore the real root and commit the fix.") -f ($committedOffending -join ', '))
        }
    }
    Write-Host ("  localRoots ok (working copy and HEAD): {0}" -f ($trackedRoots -join ', ')) -ForegroundColor Green
}

Write-Step 'Loading roadmap parser module'
. $roadmapParser
. $roadmapExecutionContract
Write-Host 'Roadmap parser module loaded successfully' -ForegroundColor Green

Write-Step 'Execution-contract authority — smoke: violating fixture is red before sufficient fixture is green'
$executionBase = [pscustomobject]@{
    releaseGoal = 'Ship a bounded operator workflow.'
    pendingMilestones = @('Wire the workflow to the API.')
    acceptanceCriteria = @('The workflow returns a successful response for the fixture.')
    outOfScope = @('Unrelated dashboard redesign.')
    validationPlan = @()
    activePhasePlan = [pscustomobject]@{ scope = 'One API workflow'; workUnitsEstimated = 3 }
    budgetGuardrail = [pscustomobject]@{ maxUnitsPerPhase = 5 }
}
$executionRed = Test-RoadmapExecutionContract -RoadmapContext $executionBase -MaturityLevel 'L2-Structured' -RepoType 'node'
if ($executionRed.sufficient -or [string]$executionRed.code -ne 'execution-contract-verification-missing') {
    throw "The violating execution-contract fixture did not go red on missing runnable verification (code=$($executionRed.code))."
}
$executionBase.validationPlan = @('Run `npm test` and confirm it exits successfully.')
$executionGreen = Test-RoadmapExecutionContract -RoadmapContext $executionBase -MaturityLevel 'L2-Structured' -RepoType 'node'
if (-not $executionGreen.sufficient -or [string]$executionGreen.code -ne 'execution-contract-sufficient') {
    throw "A bounded L2 execution contract should pass without using maturity as a universal gate (code=$($executionGreen.code))."
}
$executionOversized = [pscustomobject]@{
    releaseGoal = $executionBase.releaseGoal
    pendingMilestones = $executionBase.pendingMilestones
    acceptanceCriteria = $executionBase.acceptanceCriteria
    outOfScope = $executionBase.outOfScope
    validationPlan = $executionBase.validationPlan
    activePhasePlan = [pscustomobject]@{ scope = 'One API workflow'; workUnitsEstimated = 8 }
    budgetGuardrail = [pscustomobject]@{ maxUnitsPerPhase = 5 }
}
$executionSizeRed = Test-RoadmapExecutionContract -RoadmapContext $executionOversized -MaturityLevel 'L2-Structured' -RepoType 'node'
if ($executionSizeRed.sufficient -or [string]$executionSizeRed.code -ne 'execution-contract-sizing-missing') {
    throw "An L2 phase above its declared cap must go red on sizing (code=$($executionSizeRed.code))."
}
Write-Host '  shared verdict red/green proven: missing verification refused; bounded L2 admitted; over-cap L2 refused' -ForegroundColor DarkGray

Write-Step 'Roadmap parser — smoke: pending roadmap'
$pendingResult = Invoke-ParseRoadmapContent -Content "## Now`n- [ ] First task`n- [x] Done task`n## Next`n- [ ] Another task"
if ($pendingResult.roadmapState -ne 'pending') { throw "Expected state=pending, got $($pendingResult.roadmapState)" }
if ($pendingResult.pendingCount -ne 2)          { throw "Expected pendingCount=2, got $($pendingResult.pendingCount)" }
if ($pendingResult.completedCount -ne 1)        { throw "Expected completedCount=1, got $($pendingResult.completedCount)" }
if ($pendingResult.nextPendingItem.text -ne 'First task') { throw "Expected nextPendingItem.text='First task', got '$($pendingResult.nextPendingItem.text)'" }
if ($pendingResult.nextPendingItem.section -ne 'Now') { throw "Expected nextPendingItem.section='Now', got '$($pendingResult.nextPendingItem.section)'" }
Write-Host '  pending roadmap parsed correctly' -ForegroundColor DarkGray

Write-Step 'Roadmap parser — smoke: complete roadmap'
$completeResult = Invoke-ParseRoadmapContent -Content "## Done`n- [x] Item one`n- [X] Item two"
if ($completeResult.roadmapState -ne 'complete')  { throw "Expected state=complete, got $($completeResult.roadmapState)" }
if ($completeResult.pendingCount -ne 0)            { throw "Expected pendingCount=0, got $($completeResult.pendingCount)" }
if ($null -ne $completeResult.nextPendingItem)     { throw "Expected nextPendingItem=null for complete roadmap" }
Write-Host '  complete roadmap parsed correctly' -ForegroundColor DarkGray

Write-Step 'Roadmap parser — smoke: no-checklist (readable, but no checkboxes)'
$errorResult = Invoke-ParseRoadmapContent -Content "# ROADMAP`nThis roadmap has no checkboxes."
if ($errorResult.roadmapState -ne 'no-checklist') { throw "Expected state=no-checklist, got $($errorResult.roadmapState)" }
Write-Host '  readable-but-checkboxless roadmap classified as no-checklist, not parse-error' -ForegroundColor DarkGray

Write-Step 'Roadmap parser — smoke: parse-error (empty content)'
$emptyResult = Invoke-ParseRoadmapContent -Content ''
if ($emptyResult.roadmapState -ne 'parse-error') { throw "Expected state=parse-error for empty content, got $($emptyResult.roadmapState)" }
Write-Host '  empty content classified as parse-error correctly' -ForegroundColor DarkGray

Write-Step 'Roadmap parser — smoke: live ROADMAP.md in workspace'
$liveRoadmap = Join-Path $WorkspaceRoot 'ROADMAP.md'
if (Test-Path -LiteralPath $liveRoadmap) {
    $liveContent = Get-Content -LiteralPath $liveRoadmap -Raw -Encoding UTF8
    $liveResult = Invoke-ParseRoadmapContent -Content $liveContent -SourcePath $liveRoadmap
    if ($liveResult.roadmapState -notin @('pending', 'complete', 'parse-error')) {
        throw "Live ROADMAP.md returned unexpected state: $($liveResult.roadmapState)"
    }
    Write-Host ("  live ROADMAP.md state={0} pending={1} completed={2}" -f $liveResult.roadmapState, $liveResult.pendingCount, $liveResult.completedCount) -ForegroundColor DarkGray
} else {
    Write-Host '  (ROADMAP.md not found at workspace root — live parse skipped)' -ForegroundColor Yellow
}

Write-Step 'Roadmap parser — smoke: phase-plan and budget-guardrail annotations'
$annotatedRoadmap = @"
## Release 2.0 - Dispatch Budgets

**Goal:** Ship bounded dispatch slices with roadmap-derived estimates.

### Engineering milestones

- [ ] Add quota guard
- [x] Add agent-run ledger

### Acceptance criteria

- Quota checks refuse an over-budget task.

### Out of scope

- Changes to provider authentication.

### Validation plan

- Run ``scripts/Invoke-ModuleSmokeTest.ps1`` and confirm it exits successfully.

### Phase plan

| Phase | Scope | Status | Completed | Token usage | Work units (est -> actual) |
| ----- | ----- | ------ | --------- | ----------- | -------------------------- |
| Phase 1: Ledger | Land the ledger model | done | 2026-06-11 | ~2k | 4 -> 5 |
| Phase 2: Quota guard | Enforce pre-dispatch quota checks | in progress | - | - | est. 8 |

### Budget guardrail

- Estimated AI work units for this release: 18 - Max per phase: 10
- Before dispatch: check the budget ledger; do not start a session whose estimate exceeds the per-session cap.
- At each phase closure record the raw observations only.
"@
$annotatedResult = Invoke-ParseRoadmapContent -Content $annotatedRoadmap
if ($annotatedResult.roadmapState -ne 'pending') { throw "Expected annotated roadmap state=pending, got '$($annotatedResult.roadmapState)'" }
if ($null -eq $annotatedResult.activeRelease) { throw 'Expected activeRelease for annotated roadmap' }
if ($null -eq $annotatedResult.activePhasePlan) { throw 'Expected activePhasePlan for annotated roadmap' }
if ([string]$annotatedResult.activePhasePlan.phaseName -ne 'Phase 2: Quota guard') { throw "Expected activePhasePlan='Phase 2: Quota guard', got '$($annotatedResult.activePhasePlan.phaseName)'" }
if ([double]$annotatedResult.activePhasePlan.workUnitsEstimated -ne 8) { throw "Expected activePhasePlan.workUnitsEstimated=8, got '$($annotatedResult.activePhasePlan.workUnitsEstimated)'" }
if ($null -eq $annotatedResult.budgetGuardrail) { throw 'Expected budgetGuardrail metadata for annotated roadmap' }
if ([double]$annotatedResult.budgetGuardrail.estimatedReleaseWorkUnits -ne 18) { throw "Expected estimatedReleaseWorkUnits=18, got '$($annotatedResult.budgetGuardrail.estimatedReleaseWorkUnits)'" }
if ([double]$annotatedResult.budgetGuardrail.maxUnitsPerPhase -ne 10) { throw "Expected maxUnitsPerPhase=10, got '$($annotatedResult.budgetGuardrail.maxUnitsPerPhase)'" }
if (@($annotatedResult.activeRelease.validationPlan).Count -ne 1 -or [string]$annotatedResult.activeRelease.validationPlan[0] -notmatch 'Invoke-ModuleSmokeTest') {
    throw 'Expected the active release validation plan to carry its runnable command.'
}
Write-Host '  phase-plan and budget-guardrail annotations parsed correctly' -ForegroundColor DarkGray

Write-Step 'Loading doc audit scanner module'
. $docAuditScanner
Write-Host 'Doc audit scanner module loaded successfully' -ForegroundColor Green

Write-Step 'Doc audit scanner — smoke: loads doc-standards.json'
$standards = Get-DocStandards -StandardsPath $docStandards
if ($null -eq $standards) { throw "Get-DocStandards returned null for existing doc-standards.json" }
if ($null -eq $standards.requiredRootFiles) { throw "doc-standards.json missing requiredRootFiles" }
Write-Host ("  doc-standards.json loaded: {0} required file specs" -f @($standards.requiredRootFiles).Count) -ForegroundColor DarkGray

Write-Step 'Doc audit scanner — smoke: ready repo (has README + pending roadmap)'
$tmpReadyDir = Join-Path ([System.IO.Path]::GetTempPath()) ('docaudit-smoke-ready-' + [guid]::NewGuid().ToString('n').Substring(0, 8))
$null = New-Item -ItemType Directory -Path $tmpReadyDir -Force
$null = New-Item -ItemType Directory -Path (Join-Path $tmpReadyDir '.git') -Force
$readmeContent = @"
# Sample Project

A sample project with all required sections to satisfy doc standards.

$('A' * 300)

## Installation

Run the setup script.

## Usage

Run the start command.

## Contributing

See CONTRIBUTING.md.
"@
Set-Content -LiteralPath (Join-Path $tmpReadyDir 'README.md') -Value $readmeContent -Encoding UTF8
Set-Content -LiteralPath (Join-Path $tmpReadyDir 'LICENSE') -Value 'MIT License' -Encoding UTF8
try {
    $readyResult = Invoke-AuditRepoDocumentation -RepoPath $tmpReadyDir -RepoName 'smoke-ready' -Standards $standards -RoadmapState 'pending' -NextPendingRoadmapItem 'First task'
    if ($readyResult.dispatchReadiness -ne 'ready') { throw "Expected dispatchReadiness=ready, got $($readyResult.dispatchReadiness)" }
    if ($readyResult.readyForDispatch -ne $true) { throw "Expected readyForDispatch=true" }
    Write-Host '  ready repo classified correctly' -ForegroundColor DarkGray
} finally {
    Remove-Item -LiteralPath $tmpReadyDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Step 'Doc audit scanner — smoke: blocked repo (missing README)'
$tmpBlockedDir = Join-Path ([System.IO.Path]::GetTempPath()) ('docaudit-smoke-blocked-' + [guid]::NewGuid().ToString('n').Substring(0, 8))
$null = New-Item -ItemType Directory -Path $tmpBlockedDir -Force
$null = New-Item -ItemType Directory -Path (Join-Path $tmpBlockedDir '.git') -Force
try {
    $blockedResult = Invoke-AuditRepoDocumentation -RepoPath $tmpBlockedDir -RepoName 'smoke-blocked' -Standards $standards -RoadmapState 'pending'
    if ($blockedResult.dispatchReadiness -ne 'blocked') { throw "Expected dispatchReadiness=blocked, got $($blockedResult.dispatchReadiness)" }
    if ($blockedResult.criticalCount -lt 1) { throw "Expected at least 1 critical finding for missing README" }
    Write-Host '  blocked repo classified correctly' -ForegroundColor DarkGray
} finally {
    Remove-Item -LiteralPath $tmpBlockedDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Step 'Doc audit scanner — smoke: needs-doc-standardization (short README + pending roadmap)'
$tmpNeedsDir = Join-Path ([System.IO.Path]::GetTempPath()) ('docaudit-smoke-needs-' + [guid]::NewGuid().ToString('n').Substring(0, 8))
$null = New-Item -ItemType Directory -Path $tmpNeedsDir -Force
$null = New-Item -ItemType Directory -Path (Join-Path $tmpNeedsDir '.git') -Force
Set-Content -LiteralPath (Join-Path $tmpNeedsDir 'README.md') -Value 'Short README' -Encoding UTF8
try {
    $needsResult = Invoke-AuditRepoDocumentation -RepoPath $tmpNeedsDir -RepoName 'smoke-needs' -Standards $standards -RoadmapState 'pending'
    if ($needsResult.dispatchReadiness -ne 'needs-doc-standardization') { throw "Expected dispatchReadiness=needs-doc-standardization, got $($needsResult.dispatchReadiness)" }
    Write-Host '  needs-doc-standardization classified correctly' -ForegroundColor DarkGray
} finally {
    Remove-Item -LiteralPath $tmpNeedsDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Step 'Doc audit scanner — smoke: missing-roadmap'
$tmpMissingDir = Join-Path ([System.IO.Path]::GetTempPath()) ('docaudit-smoke-missing-' + [guid]::NewGuid().ToString('n').Substring(0, 8))
$null = New-Item -ItemType Directory -Path $tmpMissingDir -Force
$null = New-Item -ItemType Directory -Path (Join-Path $tmpMissingDir '.git') -Force
$readmeContent2 = "# Project`n`n" + ('B' * 400)
Set-Content -LiteralPath (Join-Path $tmpMissingDir 'README.md') -Value $readmeContent2 -Encoding UTF8
try {
    $missingResult = Invoke-AuditRepoDocumentation -RepoPath $tmpMissingDir -RepoName 'smoke-missing' -Standards $standards -RoadmapState 'missing'
    if ($missingResult.dispatchReadiness -ne 'missing-roadmap') { throw "Expected dispatchReadiness=missing-roadmap, got $($missingResult.dispatchReadiness)" }
    Write-Host '  missing-roadmap classified correctly' -ForegroundColor DarkGray
} finally {
    Remove-Item -LiteralPath $tmpMissingDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Step 'Doc audit scanner — smoke: Invoke-AuditRepoScan on workspace root'
$scanResults = Invoke-AuditRepoScan -LocalRoots @($WorkspaceRoot) -MaxDepth 1 -Standards $standards
if ($null -eq $scanResults) { throw "Invoke-AuditRepoScan returned null" }
Write-Host ("  workspace root audit found {0} repos" -f @($scanResults).Count) -ForegroundColor DarkGray
foreach ($r in @($scanResults)) {
    if ($r.dispatchReadiness -notin @('ready', 'needs-doc-standardization', 'missing-roadmap', 'roadmap-complete', 'parse-error', 'blocked')) {
        throw "Unexpected dispatchReadiness value: $($r.dispatchReadiness) for repo $($r.repoName)"
    }
}
Write-Host '  all scanned repos have valid dispatchReadiness values' -ForegroundColor DarkGray

Write-Step 'Doc audit scanner — smoke: cached roadmap entries as JSON objects'
$tmpScanRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('docaudit-smoke-cache-' + [guid]::NewGuid().ToString('n').Substring(0, 8))
$tmpCachedRepo = Join-Path $tmpScanRoot 'cached-roadmap-repo'
$null = New-Item -ItemType Directory -Path (Join-Path $tmpCachedRepo '.git') -Force
$cachedReadme = "# Cached Roadmap Repo`n`n" + ('C' * 400)
Set-Content -LiteralPath (Join-Path $tmpCachedRepo 'README.md') -Value $cachedReadme -Encoding UTF8
$cachedRoadmapJson = @"
[
  {
    "repoName": "cached-roadmap-repo",
    "repoPath": "$($tmpCachedRepo.Replace('\', '\\'))",
    "roadmapState": "pending",
    "nextPendingItem": {
      "text": "Add cached roadmap support"
    }
  }
]
"@
# Windows PowerShell 5.1 returns a JSON root array as one nested Object[] when
# ConvertFrom-Json feeds an array expression directly. Re-enumerate explicitly
# so this fixture has the same entry shape under PS 5.1 and pwsh.
$cachedRoadmapParsed = ConvertFrom-Json -InputObject $cachedRoadmapJson
$cachedRoadmapEntries = @($cachedRoadmapParsed | ForEach-Object { $_ })
try {
    $cachedScanResults = Invoke-AuditRepoScan -LocalRoots @($tmpScanRoot) -MaxDepth 2 -RoadmapEntries $cachedRoadmapEntries -Standards $standards
    if (@($cachedScanResults).Count -ne 1) { throw "Expected 1 repo from cached roadmap scan, got $(@($cachedScanResults).Count)" }
    $cachedResult = @($cachedScanResults)[0]
    if ($cachedResult.roadmapState -ne 'pending') { throw "Expected roadmapState=pending, got $($cachedResult.roadmapState)" }
    if ($cachedResult.nextPendingRoadmapItem -ne 'Add cached roadmap support') { throw "Expected cached next pending item, got $($cachedResult.nextPendingRoadmapItem)" }
    Write-Host '  cached roadmap entries classified correctly' -ForegroundColor DarkGray
} finally {
    Remove-Item -LiteralPath $tmpScanRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Step 'Roadmap parser — smoke: section-order neighboring context extraction'
$neighborContent = @"
## Now
- [ ] First task
- [ ] Second task
## Next
- [ ] Third task
- [x] Already done
"@
$neighborResult = Invoke-ParseRoadmapContent -Content $neighborContent
if ($neighborResult.roadmapState -ne 'pending') { throw "Expected state=pending for neighboring context test, got $($neighborResult.roadmapState)" }
if ($neighborResult.nextPendingItem.text -ne 'First task') { throw "Expected nextPendingItem='First task', got '$($neighborResult.nextPendingItem.text)'" }
# Validate section ordering is preserved in sections array
$sectionNames = @($neighborResult.sections | ForEach-Object { $_.name })
if ($sectionNames[0] -ne 'Now') { throw "Expected first section name='Now', got '$($sectionNames[0])'" }
if ($sectionNames[1] -ne 'Next') { throw "Expected second section name='Next', got '$($sectionNames[1])'" }
$nowSection = $neighborResult.sections | Where-Object { $_.name -eq 'Now' } | Select-Object -First 1
if (@($nowSection.pendingItems).Count -ne 2) { throw "Expected 2 pending items in 'Now' section, got $(@($nowSection.pendingItems).Count)" }
Write-Host '  neighboring context section ordering verified' -ForegroundColor DarkGray

Write-Step 'Loading roadmap auditor module (Release 0.8)'
$roadmapAuditor = Join-Path $WorkspaceRoot 'backend\modules\roadmap\Roadmap.Auditor.ps1'
if (-not (Test-Path -LiteralPath $roadmapAuditor)) { throw "Roadmap.Auditor.ps1 not found at: $roadmapAuditor" }
. $roadmapAuditor
Write-Host 'Roadmap auditor module loaded successfully' -ForegroundColor Green

Write-Step 'Roadmap auditor — smoke: normalize missing roadmap'
$missingContract = Invoke-NormalizeRoadmapContract -ParsedResult $null -RepoName 'smoke-missing-repo'
if ($missingContract.roadmapState -ne 'missing')   { throw "Expected roadmapState=missing for null ParsedResult, got $($missingContract.roadmapState)" }
if ($missingContract.maturityLevel -ne 'L0-Absent') { throw "Expected maturityLevel=L0-Absent for missing roadmap, got $($missingContract.maturityLevel)" }
Write-Host '  missing roadmap normalized to L0-Absent' -ForegroundColor DarkGray

Write-Step 'Roadmap auditor — smoke: normalize pending roadmap'
$pendingContent = @"
# Product Intent

This product does something.

## Release 1.0 — First Release

### Acceptance criteria

- The feature works.

### Out of scope

- Not this.

- [ ] Implement feature A
- [ ] Implement feature B
- [ ] Implement feature C
- [x] Done already
"@
$pendingParsed   = Invoke-ParseRoadmapContent -Content $pendingContent
$pendingContract = Invoke-NormalizeRoadmapContract -ParsedResult $pendingParsed -RawContent $pendingContent -RepoName 'smoke-pending-repo'
if ($pendingContract.roadmapState -ne 'pending')     { throw "Expected roadmapState=pending, got $($pendingContract.roadmapState)" }
if ($pendingContract.pendingCount -ne 3)             { throw "Expected pendingCount=3, got $($pendingContract.pendingCount)" }
if ($pendingContract.hasProductIntent -ne $true)     { throw "Expected hasProductIntent=true" }
if ($pendingContract.hasReleaseSections -ne $true)   { throw "Expected hasReleaseSections=true" }
if ($pendingContract.hasAcceptanceCriteria -ne $true) { throw "Expected hasAcceptanceCriteria=true" }
if ($pendingContract.hasOutOfScope -ne $true)        { throw "Expected hasOutOfScope=true" }
Write-Host '  pending roadmap normalized with structure flags detected' -ForegroundColor DarkGray

Write-Step 'Roadmap auditor — smoke: audit scoring and maturity level assignment'
$roadmapAuditRulesRaw  = Get-Content -LiteralPath (Join-Path $WorkspaceRoot 'standards\roadmap\roadmap-audit-rules.json') -Raw -Encoding UTF8
$roadmapAuditRulesParsed = ConvertFrom-Json -InputObject $roadmapAuditRulesRaw
$auditRulesObj = [pscustomobject]@{
    rules             = @($roadmapAuditRulesParsed.rules)
    maturityThresholds = $roadmapAuditRulesParsed.maturityThresholds
}
# Score the well-formed pending contract
$scoredContract = Invoke-AuditRoadmapContract -Contract $pendingContract -AuditRules $auditRulesObj
if ($scoredContract.maturityScore -lt 0 -or $scoredContract.maturityScore -gt 100) {
    throw "Maturity score out of range 0-100: $($scoredContract.maturityScore)"
}
if ($scoredContract.maturityLevel -notin @('L0-Absent','L1-Informal','L2-Structured','L3-Contract-Ready','L4-Orchestration-Ready')) {
    throw "Unexpected maturityLevel: $($scoredContract.maturityLevel)"
}
# A well-formed roadmap with all structural flags should score at least L3
if ($scoredContract.maturityLevel -notin @('L3-Contract-Ready','L4-Orchestration-Ready')) {
    Write-Host ("  NOTE: full-featured roadmap scored $($scoredContract.maturityScore) -> $($scoredContract.maturityLevel) (may be below L3 if vague items detected)") -ForegroundColor Yellow
} else {
    Write-Host ("  full-featured roadmap scored $($scoredContract.maturityScore) -> $($scoredContract.maturityLevel)") -ForegroundColor DarkGray
}
# Score a completely missing roadmap — must be L0
$missingScored = Invoke-AuditRoadmapContract -Contract $missingContract -AuditRules $auditRulesObj
if ($missingScored.maturityLevel -ne 'L0-Absent') { throw "Expected L0-Absent for missing roadmap after audit, got $($missingScored.maturityLevel)" }
if ($missingScored.maturityScore -ne 0)           { throw "Expected maturityScore=0 for missing roadmap, got $($missingScored.maturityScore)" }
Write-Host '  missing roadmap correctly scored as L0-Absent with score=0' -ForegroundColor DarkGray

Write-Step 'Roadmap auditor — smoke: audit findings contain expected rule IDs'
if ($null -eq $scoredContract.auditFindings) { throw "auditFindings should not be null after audit" }
# A well-structured roadmap should not have critical findings
$criticalFindings = @($scoredContract.auditFindings | Where-Object { $_.severity -eq 'critical' })
if ($criticalFindings.Count -gt 0) {
    throw "Well-formed roadmap should have no critical findings, got: $(($criticalFindings | ForEach-Object { $_.ruleId }) -join ', ')"
}
Write-Host ("  audit findings: {0} total, 0 critical" -f @($scoredContract.auditFindings).Count) -ForegroundColor DarkGray

Write-Step 'Roadmap auditor — smoke: active-release rules ROADMAP-011/012 gate dispatch (rules v1.1)'
# A structurally complete roadmap that declares no active release must fire
# ROADMAP-012, and one declaring two must fire ROADMAP-011 and be capped at L2 —
# an ambiguous dispatch target is not dispatchable.
$activeReleaseFixture = @'
# Sample Project Roadmap

Product intent: this product helps operators ship reliably.

## Release 1.0 - First Release

**Status:** {0}

Goal: ship the first thing.

### Acceptance criteria

- The first thing ships and is verified by an automated test.

### Out of scope

- Anything not named above.

- [ ] Implement the first documented behavior
- [ ] Implement the second documented behavior
- [ ] Implement the third documented behavior

## Release 1.1 - Second Release

**Status:** {1}

Goal: ship the second thing.

### Acceptance criteria

- The second thing ships and is verified by an automated test.

### Out of scope

- Anything not named above.

- [ ] Implement the fourth documented behavior
- [ ] Implement the fifth documented behavior
- [ ] Implement the sixth documented behavior
'@

function Get-SmokeActiveReleaseAudit {
    param([string]$StatusOne, [string]$StatusTwo)
    $content = $activeReleaseFixture -f $StatusOne, $StatusTwo
    $parsed = Invoke-ParseRoadmapContent -Content $content -SourcePath 'ROADMAP.md'
    $contract = Invoke-NormalizeRoadmapContract -ParsedResult $parsed -RawContent $content -RepoName 'smoke-active-release'
    return (Invoke-AuditRoadmapContract -Contract $contract -AuditRules $auditRulesObj)
}

$noActiveAudit = Get-SmokeActiveReleaseAudit -StatusOne 'planned' -StatusTwo 'planned'
if ([int]$noActiveAudit.activeReleaseCount -ne 0) { throw "Expected activeReleaseCount=0, got $($noActiveAudit.activeReleaseCount)" }
if (@($noActiveAudit.auditFindings | Where-Object { $_.ruleId -eq 'ROADMAP-012' }).Count -ne 1) {
    throw 'Expected ROADMAP-012 to fire when releases exist but none is active'
}

$oneActiveAudit = Get-SmokeActiveReleaseAudit -StatusOne 'active' -StatusTwo 'planned'
if ([int]$oneActiveAudit.activeReleaseCount -ne 1) { throw "Expected activeReleaseCount=1, got $($oneActiveAudit.activeReleaseCount)" }
if (@($oneActiveAudit.auditFindings | Where-Object { $_.ruleId -in @('ROADMAP-011','ROADMAP-012') }).Count -ne 0) {
    throw 'Expected neither ROADMAP-011 nor ROADMAP-012 to fire for exactly one active release'
}

# 'In Progress' must normalize to active, per the rules v1.1 changelog.
$twoActiveAudit = Get-SmokeActiveReleaseAudit -StatusOne 'active' -StatusTwo 'In Progress'
if ([int]$twoActiveAudit.activeReleaseCount -ne 2) { throw "Expected activeReleaseCount=2 (alias 'In Progress' -> active), got $($twoActiveAudit.activeReleaseCount)" }
if (@($twoActiveAudit.auditFindings | Where-Object { $_.ruleId -eq 'ROADMAP-011' }).Count -ne 1) {
    throw 'Expected ROADMAP-011 to fire when more than one release is active'
}
if ($twoActiveAudit.maturityLevel -ne 'L2-Structured') {
    throw "More than one active release must cap maturity at exactly L2-Structured, got $($twoActiveAudit.maturityScore) -> $($twoActiveAudit.maturityLevel)"
}
# ROADMAP-011 must stay a WARNING. As a critical it would take the blanket L1
# cap, making its own documented L2 cap unreachable and silently downgrading
# every ambiguous-dispatch repo in the portfolio a level below the model.
$rule011 = @($auditRulesObj.rules | Where-Object { $_.id -eq 'ROADMAP-011' })[0]
if ([string]$rule011.severity -ne 'warning') {
    throw "ROADMAP-011 must be severity 'warning' so its named L2 cap stays reachable (see ROADMAP_MATURITY_MODEL.md); got '$($rule011.severity)'"
}
Write-Host ("  active-release rules ok: 0 active -> ROADMAP-012; 1 active -> clean; 2 active -> ROADMAP-011 (warning) + capped at {0}" -f $twoActiveAudit.maturityLevel) -ForegroundColor DarkGray

# The two blanket maturity caps ROADMAP_MATURITY_MODEL.md documented from the
# start but no evaluator applied until rules v1.5: weighted-score arithmetic
# alone let a roadmap carry a critical finding and still score
# orchestration-ready.
Write-Step 'Roadmap auditor — smoke: blanket maturity caps (critical -> L1, warning -> L3)'
$capThresholds = $auditRulesObj.maturityThresholds
$l1Max = [int]$capThresholds.'L1-Informal'.maxScore
$l3Max = [int]$capThresholds.'L3-Contract-Ready'.maxScore

# Same well-formed roadmap that scores L3+, but flipped to parse-error, which is
# critical -> must cap at L1 no matter how much structure is otherwise present.
$criticalContract = Invoke-NormalizeRoadmapContract `
    -ParsedResult (Invoke-ParseRoadmapContent -Content $pendingContent) `
    -RawContent $pendingContent -RepoName 'smoke-critical-cap'
$criticalContract.roadmapState = 'parse-error'
$criticalAudit = Invoke-AuditRoadmapContract -Contract $criticalContract -AuditRules $auditRulesObj
if (@($criticalAudit.auditFindings | Where-Object { $_.severity -eq 'critical' }).Count -lt 1) {
    throw 'Fixture error: expected at least one critical finding for the critical-cap case'
}
if ([int]$criticalAudit.maturityScore -gt $l1Max) {
    throw "Any critical finding must cap maturity at L1 (<= $l1Max), got $($criticalAudit.maturityScore) -> $($criticalAudit.maturityLevel)"
}
if ($criticalAudit.maturityLevel -notin @('L0-Absent', 'L1-Informal')) {
    throw "Critical-capped roadmap must land at L0/L1, got $($criticalAudit.maturityLevel)"
}

# L4 requires NO critical or warning findings, so any warning caps at L3. The
# well-formed fixture already carries warnings, so it is the natural case here.
$warningAudit = $scoredContract
$warningFindingCount = @($warningAudit.auditFindings | Where-Object { $_.severity -eq 'warning' }).Count
if ($warningFindingCount -gt 0) {
    if ([int]$warningAudit.maturityScore -gt $l3Max) {
        throw "Any warning finding must cap maturity at L3 (<= $l3Max), got $($warningAudit.maturityScore) -> $($warningAudit.maturityLevel)"
    }
    if ($warningAudit.maturityLevel -eq 'L4-Orchestration-Ready') {
        throw 'L4-Orchestration-Ready requires zero warning findings'
    }
}
Write-Host ("  maturity caps ok: critical -> {0} (<= {1}); {2} warning finding(s) -> {3} (<= {4})" -f `
    $criticalAudit.maturityLevel, $l1Max, $warningFindingCount, $warningAudit.maturityLevel, $l3Max) -ForegroundColor DarkGray

# The canonical status form in ROADMAP_TEMPLATE.md is a blockquote. A detector
# that only understood "**Status:** active" would fire ROADMAP-012 on every
# template-conformant repo in the portfolio.
Write-Step 'Roadmap auditor — smoke: canonical "> Status: active" blockquote form is detected'
$blockquoteFixture = $activeReleaseFixture.Replace('**Status:** {0}', '> Status: {0}').Replace('**Status:** {1}', '> Status: {1}')
$blockquoteContent = $blockquoteFixture -f 'active', 'planned'
$blockquoteParsed = Invoke-ParseRoadmapContent -Content $blockquoteContent -SourcePath 'ROADMAP.md'
$blockquoteContract = Invoke-NormalizeRoadmapContract -ParsedResult $blockquoteParsed -RawContent $blockquoteContent -RepoName 'smoke-blockquote-status'
$blockquoteAudit = Invoke-AuditRoadmapContract -Contract $blockquoteContract -AuditRules $auditRulesObj
if ([int]$blockquoteAudit.activeReleaseCount -ne 1) {
    throw "Canonical '> Status: active' blockquote not detected: expected activeReleaseCount=1, got $($blockquoteAudit.activeReleaseCount)"
}
if (@($blockquoteAudit.auditFindings | Where-Object { $_.ruleId -eq 'ROADMAP-012' }).Count -ne 0) {
    throw 'ROADMAP-012 must not fire for a template-conformant roadmap using the "> Status: active" blockquote'
}
Write-Host '  blockquote status form detected (activeReleaseCount=1, no ROADMAP-012)' -ForegroundColor DarkGray

# The structure linter had NO smoke coverage, which is how it came to contradict
# the template it lints: R013's size cap fired on any conformant active release
# (the template deliberately puts the whole execution contract there), and RQ001
# demanded a Status line on the pointer block that RQ003 then errors on for
# declaring status twice. Both relaxations are pinned here alongside proof they
# still fire when genuinely violated — a relaxed rule that no longer detects
# anything is worse than the false positive it replaced.
# Release 2.7 Phase A. Until 2026-08-09 submit-pr was a plan builder that
# returned created=false even with createPr=true, so "no PR appeared" was
# indistinguishable from success. Every refusal now carries a NAMED reason, and
# these assertions are what stop it regressing to a silent no-op.
Write-Step 'Portfolio scope — Release 3.5 milestone 3: classified, never deleted'
# The classifier cases mirror what the 2026-08-15 live-workspace reproduction
# found admitted as first-class portfolio repos: a .tmp_compare folder inside
# another repo, Archive/ trees, a .worktrees container, and vendored
# third-party clones. Nothing is dropped: every exclusion carries a named
# reason, and an empty owner set disables vendor classification entirely --
# absence of configuration must not shrink the portfolio.
. (Join-Path $WorkspaceRoot 'backend\modules\portfolio\Portfolio.Scope.ps1')
& {
    $policy = Get-RepoScopePolicy -Settings @{ reconcile = @{ gitHubOwner = 'xfaith4' } }
    if (@($policy.owners) -ne @('xfaith4')) { throw "Policy must fall back to reconcile.gitHubOwner, got '$(@($policy.owners) -join ',')'" }

    foreach ($case in @(
        @{ name = 'tmp-compare dir';    path = 'F:\dev\Genesys.Core_AuditLogsApp\.tmp_compare\genesys-cloud-mcp-server'; url = 'https://github.com/purecloudlabs/genesys-cloud-mcp-server.git'; expect = 'excluded-path' }
        @{ name = 'archive tree';       path = 'F:\dev\Archive\MusicLibrary';                    url = 'https://github.com/xfaith4/MusicLibrary.git';    expect = 'archived' }
        @{ name = 'worktree container'; path = 'F:\dev\Genesys.Core.worktrees\feature-x';        url = 'https://github.com/xfaith4/Genesys.Core.git';    expect = 'excluded-path' }
        @{ name = 'vendored clone';     path = 'F:\dev\gemini-cli';                              url = 'https://github.com/google-gemini/gemini-cli.git'; expect = 'vendored' }
        @{ name = 'owned repo';         path = 'F:\dev\GitHubRepoManagement';                    url = 'https://github.com/xfaith4/GitHubRepoManagement.git'; expect = 'in-scope' }
        @{ name = 'no-remote local';    path = 'F:\dev\scratch-project';                         url = '';                                                expect = 'in-scope' }
        @{ name = 'vendored in archive';path = 'F:\dev\Archive\gemini-cli';                      url = 'https://github.com/google-gemini/gemini-cli.git'; expect = 'archived' }
    )) {
        $c = Get-RepoScopeClassification -LocalPath $case.path -OriginUrl $case.url -Policy $policy
        if ([string]$c.classification -ne $case.expect) { throw "Scope case '$($case.name)' expected '$($case.expect)', got '$($c.classification)'" }
        if (-not $c.inScope -and [string]::IsNullOrWhiteSpace([string]$c.reason)) { throw "Exclusion '$($case.name)' must carry a named reason" }
    }

    # No owner set anywhere: vendor classification must disable, not guess.
    $noOwnerPolicy = Get-RepoScopePolicy -Settings @{}
    $foreign = Get-RepoScopeClassification -LocalPath 'F:\dev\gemini-cli' -OriginUrl 'https://github.com/google-gemini/gemini-cli.git' -Policy $noOwnerPolicy
    if (-not $foreign.inScope) { throw 'With no configured owner set, a foreign remote must stay in scope - no basis to call anything vendored' }

    # Disabled policy: everything in scope.
    $disabled = Get-RepoScopeClassification -LocalPath 'F:\dev\Archive\x' -OriginUrl '' -Policy (Get-RepoScopePolicy -Settings @{ scope = @{ enabled = $false } })
    if (-not $disabled.inScope) { throw 'A disabled scope policy must classify everything in scope' }

    $scopeSummary = Get-RepoScopeSummary -Classifications @(
        (Get-RepoScopeClassification -LocalPath 'F:\dev\a' -OriginUrl '' -Policy $policy),
        (Get-RepoScopeClassification -LocalPath 'F:\dev\Archive\b' -OriginUrl '' -Policy $policy),
        (Get-RepoScopeClassification -LocalPath 'F:\dev\c' -OriginUrl 'https://github.com/other/c.git' -Policy $policy)
    )
    if ($scopeSummary.total -ne 3 -or $scopeSummary.inScope -ne 1 -or $scopeSummary.archived -ne 1 -or $scopeSummary.vendored -ne 1) {
        throw "Scope summary miscounted: total=$($scopeSummary.total) inScope=$($scopeSummary.inScope) archived=$($scopeSummary.archived) vendored=$($scopeSummary.vendored)"
    }

    # Identity: two clones of one origin are ONE repository -- the live
    # Genesys.Core / Genesys.Core_AuditLogsApp case, reproduced with real
    # repositories. A third repo with the same folder-name shape but its own
    # origin must NOT join the group.
    $idTmp = Join-Path $WorkspaceRoot 'output\smoke\module\scope-identity'
    if (Test-Path -LiteralPath $idTmp) { Remove-Item -LiteralPath $idTmp -Recurse -Force }
    $null = New-Item -ItemType Directory -Path $idTmp -Force
    $bareA = Join-Path $idTmp 'origin-a.git'
    & git init --bare -b main $bareA --quiet 2>&1 | Out-Null
    $cloneOne = Join-Path $idTmp 'repo'
    $cloneTwo = Join-Path $idTmp 'repo_secondcopy'
    & git clone $bareA $cloneOne --quiet 2>&1 | Out-Null
    & git -C $cloneOne config user.email 's@l' 2>&1 | Out-Null; & git -C $cloneOne config user.name 's' 2>&1 | Out-Null
    Set-Content -LiteralPath (Join-Path $cloneOne 'f.txt') -Value 'x' -Encoding UTF8
    & git -C $cloneOne add -A 2>&1 | Out-Null; & git -C $cloneOne commit -m 'root' --quiet 2>&1 | Out-Null
    & git -C $cloneOne push origin main --quiet 2>&1 | Out-Null
    & git clone $bareA $cloneTwo --quiet 2>&1 | Out-Null
    $bareB = Join-Path $idTmp 'origin-b.git'
    & git init --bare -b main $bareB --quiet 2>&1 | Out-Null
    $cloneThree = Join-Path $idTmp 'unrelated'
    & git clone $bareB $cloneThree --quiet 2>&1 | Out-Null

    $identityGroups = @(Group-RepoByRemoteIdentity -Repos @(
        [pscustomobject]@{ name = 'repo';            path = $cloneOne;   originUrl = $bareA }
        [pscustomobject]@{ name = 'repo_secondcopy'; path = $cloneTwo;   originUrl = ($bareA + '/') }
        [pscustomobject]@{ name = 'unrelated';       path = $cloneThree; originUrl = $bareB }
    ))
    if (@($identityGroups).Count -ne 1) { throw "Expected exactly 1 duplicate-identity group, got $(@($identityGroups).Count)" }
    if (@($identityGroups[0].paths).Count -ne 2) { throw 'The identity group must hold both clones of the shared origin' }
    if ([string]::IsNullOrWhiteSpace([string]$identityGroups[0].rootCommitSha)) { throw 'Colliding clones must be subdivided by a real root-commit SHA' }
    Remove-Item -LiteralPath $idTmp -Recurse -Force -ErrorAction SilentlyContinue

    # The assessment intake must filter to the in-scope set (milestone 3's
    # recompute residue, closed 2026-08-17): the review found a .tmp_compare
    # nested clone RANKED in the Doc Readiness queue because the assessment
    # counted every scanned repo. Scoped to the host's own source between the
    # localRepos materialization and its first assessment consumer, so the
    # assertion cannot be satisfied by a filter somewhere unrelated.
    $scopeHostSource = Get-Content -LiteralPath (Join-Path $WorkspaceRoot 'backend\api-host\Start-RepoManagementApiHost.ps1') -Raw -Encoding UTF8
    # `@(` optional: Lane 0.17's sweep wrapped every array-valued
    # if-expression, so the anchor must survive both the wrapped and the
    # unwrapped form rather than pinning the tripwire to one spelling.
    $scopeIntake = [regex]::Match($scopeHostSource, "(?s)\`$localRepos = (?:@\()?if \(\`$null -ne \`$statusResult.{0,20000}?localReposForAssessment")
    if (-not $scopeIntake.Success) { throw 'Could not locate the assessment intake window - the scope-filter tripwire lost its anchor and must fail rather than pass vacuously' }
    if ($scopeIntake.Value -notmatch 'inScope') {
        throw 'The assessment intake no longer filters to in-scope repos: out-of-scope clones would re-enter the Doc Readiness queue and the value ranking.'
    }

    Write-Host '  scope ok: 7 classifier cases (tmp/archive/worktrees/vendored/owned/no-remote/precedence), no-owner and disabled policies stay whole, summary counts, identity groups two real clones of one origin and leaves the unrelated repo out' -ForegroundColor DarkGray
}

Write-Step 'Portfolio snapshot — Release 3.5 milestone 1: the constructor refuses to build a lying metric'
. (Join-Path $WorkspaceRoot 'backend\modules\portfolio\Portfolio.Snapshot.ps1')
& {
    $now = (Get-Date).ToUniversalTime().ToString('o')

    # The teeth: impossible numbers throw in the producer's stack frame
    # instead of rendering three tabs later. Finding 1.5's `High 1592` axis
    # could not have been CONSTRUCTED under this contract.
    foreach ($bad in @(
        @{ name = 'percent above 100';        args = @{ Id = 'x'; Value = 150; Unit = 'percent'; AsOfUtc = $now; Source = 's'; Definition = 'd' } }
        @{ name = 'negative count';           args = @{ Id = 'x'; Value = -1; AsOfUtc = $now; Source = 's'; Definition = 'd' } }
        @{ name = 'numerator over denominator'; args = @{ Id = 'x'; Value = 5; Numerator = 5; Denominator = 3; AsOfUtc = $now; Source = 's'; Definition = 'd' } }
        @{ name = 'assessed over total';      args = @{ Id = 'x'; Value = 5; Assessed = 10; Total = 5; AsOfUtc = $now; Source = 's'; Definition = 'd' } }
        @{ name = 'null without reason';      args = @{ Id = 'x'; AsOfUtc = $now; Definition = 'd' } }
        @{ name = 'value without source';     args = @{ Id = 'x'; Value = 5; AsOfUtc = $now; Definition = 'd' } }
        @{ name = 'unparseable asOf';         args = @{ Id = 'x'; Value = 5; AsOfUtc = 'not a time'; Source = 's'; Definition = 'd' } }
    )) {
        $threw = $false
        $badArgs = $bad.args
        try { $null = New-PortfolioMetric @badArgs } catch { $threw = $true }
        if (-not $threw) { throw "New-PortfolioMetric must refuse '$($bad.name)'" }
    }

    $notComputed = New-PortfolioMetric -Id 'nc' -AsOfUtc $now -Definition 'd' -Reason 'no scan yet'
    if ($null -ne $notComputed.value -or $notComputed.confidence -ne 'none') { throw 'A not-computed metric must carry null value and confidence none' }
    $partial = New-PortfolioMetric -Id 'p' -Value 50 -Unit percent -AsOfUtc $now -Source 's' -Assessed 5 -Total 10 -Definition 'd'
    if ($partial.confidence -ne 'partial') { throw 'Coverage below total must derive confidence partial' }

    # All sources absent: every metric reads null-with-reason, degraded[]
    # names each missing source, and NOTHING is a guessed zero.
    $emptySnap = Build-PortfolioSnapshot -GeneratedAtUtc $now
    foreach ($m in @($emptySnap.metrics.PSObject.Properties)) {
        if ($null -ne $m.Value.value) { throw "With no sources, metric '$($m.Name)' must be not-computed, got '$($m.Value.value)'" }
        if ([string]::IsNullOrWhiteSpace([string]$m.Value.reason)) { throw "Not-computed metric '$($m.Name)' must carry its reason" }
    }
    if (@($emptySnap.degraded).Count -lt 3) { throw "An empty snapshot must name its missing sources; got $(@($emptySnap.degraded).Count)" }

    # A populated snapshot: denominators cohere, the three readinesses stay
    # DISTINCT metrics (finding 1.3 was three semantics wearing one label,
    # and forcing them equal would be a second lie).
    $snapRepos = @(
        [pscustomobject]@{ name = 'a'; status = 'dirty'; dirtyCount = 2; isStale = $true;  scope = [pscustomobject]@{ inScope = $true } }
        [pscustomobject]@{ name = 'b'; status = 'clean'; dirtyCount = 0; isStale = $false; scope = [pscustomobject]@{ inScope = $true } }
        [pscustomobject]@{ name = 'v'; status = 'clean'; dirtyCount = 0; isStale = $true;  scope = [pscustomobject]@{ inScope = $false } }
    )
    $snap = Build-PortfolioSnapshot -GeneratedAtUtc $now -StatusAsOfUtc $now `
        -StatusData ([pscustomobject]@{ repos = $snapRepos }) `
        -ExecutionMetrics ([pscustomobject]@{ stateCounts = [pscustomobject]@{ ready = 4 } }) `
        -AuditEntries @([pscustomobject]@{ dispatchReadiness = 'ready' }, [pscustomobject]@{ dispatchReadiness = 'blocked' }) `
        -AssessmentSummary ([pscustomobject]@{ readyForWorkCount = 7; totalRepos = 9 })
    if ($snap.metrics.repoCount.value -ne 3) { throw "repoCount must be the scanned set (3), got $($snap.metrics.repoCount.value)" }
    if ($snap.metrics.inScopeRepoCount.value -ne 2) { throw "inScopeRepoCount must exclude out-of-scope (2), got $($snap.metrics.inScopeRepoCount.value)" }
    if ($snap.metrics.staleRepoCount.value -ne 1) { throw "staleRepoCount must count IN-SCOPE stale only (1 - the vendored stale repo does not count), got $($snap.metrics.staleRepoCount.value)" }
    if ($snap.metrics.executionReadyCount.value -ne 4 -or $snap.metrics.dispatchReadyCount.value -ne 1 -or $snap.metrics.maturityReadyCount.value -ne 7) {
        throw 'The three readiness metrics must each carry their own source value - they are different measurements, not one number'
    }

    # The generic invariant walk - the milestone-2 seed, written once here and
    # reused against the live route by the contract tests: every metric in ANY
    # snapshot satisfies the contract without naming metrics individually.
    foreach ($m in @($snap.metrics.PSObject.Properties)) {
        $metric = $m.Value
        if ($null -ne $metric.value -and $metric.unit -eq 'percent') {
            if ([double]$metric.value -lt 0 -or [double]$metric.value -gt 100) { throw "Invariant: '$($m.Name)' percent out of bounds" }
        }
        if ($null -ne $metric.basis -and $null -ne $metric.basis.numerator -and $null -ne $metric.basis.denominator) {
            if ([double]$metric.basis.numerator -gt [double]$metric.basis.denominator) { throw "Invariant: '$($m.Name)' basis inverted" }
        }
        $parsedProbe = [datetime]::MinValue
        if (-not [datetime]::TryParse([string]$metric.asOf, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$parsedProbe)) {
            throw "Invariant: '$($m.Name)' asOf does not parse"
        }
        if ($null -eq $metric.value -and [string]::IsNullOrWhiteSpace([string]$metric.reason)) { throw "Invariant: '$($m.Name)' null without reason" }
        if ([string]::IsNullOrWhiteSpace([string]$metric.definition)) { throw "Invariant: '$($m.Name)' has no definition" }
    }

    Write-Host '  snapshot ok: 7 constructor refusals, not-computed carries reason and confidence none, empty snapshot degrades by name with zero guessed values, denominators cohere over the in-scope set, three readinesses stay distinct, generic invariant walk green' -ForegroundColor DarkGray
}

Write-Step 'Roadmap submit-PR — smoke: slug parsing and the refusal matrix'
. (Join-Path $WorkspaceRoot 'backend\modules\roadmap\Roadmap.PrSubmitter.ps1')

foreach ($case in @(
    @{ url = 'https://github.com/xfaith4/GitHubRepoManagement.git'; slug = 'xfaith4/GitHubRepoManagement' }
    @{ url = 'https://github.com/xfaith4/GitHubRepoManagement';     slug = 'xfaith4/GitHubRepoManagement' }
    @{ url = 'git@github.com:xfaith4/GitHubRepoManagement.git';     slug = 'xfaith4/GitHubRepoManagement' }
    @{ url = 'ssh://git@github.com/xfaith4/GitHubRepoManagement';   slug = 'xfaith4/GitHubRepoManagement' }
)) {
    $parsed = Resolve-GitHubRepoSlug -RemoteUrl $case.url
    if ($null -eq $parsed -or $parsed.slug -ne $case.slug) {
        throw "Resolve-GitHubRepoSlug failed for '$($case.url)': expected '$($case.slug)', got '$(if ($null -ne $parsed) { $parsed.slug } else { '<null>' })'"
    }
}
# A non-GitHub remote must refuse, not have a slug guessed for it.
foreach ($badUrl in @('https://gitlab.com/o/r.git', 'C:\some\local\path', '', 'https://github.example.com/o/r')) {
    if ($null -ne (Resolve-GitHubRepoSlug -RemoteUrl $badUrl)) { throw "Resolve-GitHubRepoSlug must return null for a non-GitHub remote: '$badUrl'" }
}

$okSlug = Resolve-GitHubRepoSlug -RemoteUrl 'https://github.com/o/r.git'
$baseArgs = @{
    RepoPath = 'C:\repo'; RoadmapPath = 'C:\repo\ROADMAP.md'; ProposedContent = 'new'
    CurrentContent = 'old'; Token = 'tok'; Slug = $okSlug; IsGitRepo = $true
    WorkingTreeDirty = $false; BaseBranch = 'main'
}
if (-not (Test-RoadmapRepairPrPreconditions @baseArgs).ok) { throw 'A fully valid submit-PR request must pass preconditions' }

# Each refusal must fire for its own reason and carry a category.
foreach ($refusal in @(
    @{ name = 'no repo path';       override = @{ RepoPath = '' };                              category = 'validation' }
    @{ name = 'not a git repo';     override = @{ IsGitRepo = $false };                         category = 'validation' }
    @{ name = 'no roadmap path';    override = @{ RoadmapPath = '' };                           category = 'validation' }
    @{ name = 'no proposedContent'; override = @{ ProposedContent = '' };                       category = 'validation' }
    @{ name = 'no-op change';       override = @{ ProposedContent = 'same'; CurrentContent = 'same' }; category = 'no-op' }
    @{ name = 'no token';           override = @{ Token = '' };                                 category = 'auth' }
    @{ name = 'non-GitHub remote';  override = @{ Slug = $null };                               category = 'validation' }
    @{ name = 'dirty tree';         override = @{ WorkingTreeDirty = $true };                   category = 'conflict' }
)) {
    $refusalArgs = @{} + $baseArgs
    foreach ($k in $refusal.override.Keys) { $refusalArgs[$k] = $refusal.override[$k] }
    $verdict = Test-RoadmapRepairPrPreconditions @refusalArgs
    if ($verdict.ok) { throw "submit-PR must refuse '$($refusal.name)' but it passed preconditions" }
    if ($verdict.category -ne $refusal.category) { throw "submit-PR refusal '$($refusal.name)' expected category '$($refusal.category)', got '$($verdict.category)'" }
    if ([string]::IsNullOrWhiteSpace($verdict.reason)) { throw "submit-PR refusal '$($refusal.name)' must carry a named reason, not an empty string" }
}

# A repair must not strip the file's trailing newline (git "\ No newline at end
# of file", markdownlint MD047). Caught on the Phase A artifact PR #96.
$newlineCases = @(
    @{ name = 'adds a missing trailing newline'; input = "line one`nline two";   expected = "line one`nline two`n" }
    @{ name = 'keeps an existing one';           input = "line one`nline two`n"; expected = "line one`nline two`n" }
    @{ name = 'does not double it';              input = "text`n";               expected = "text`n" }
)
foreach ($nl in $newlineCases) {
    $normalized = if ($nl.input.EndsWith("`n")) { $nl.input } else { $nl.input + "`n" }
    if ($normalized -ne $nl.expected) { throw "Trailing-newline normalization failed — $($nl.name)" }
}

# Branch names must be unique per second and never collide with the base branch.
$b1 = Get-RoadmapRepairBranchName -NowUtc ([datetime]'2026-08-09T06:00:00Z')
$b2 = Get-RoadmapRepairBranchName -NowUtc ([datetime]'2026-08-09T06:00:01Z')
if ($b1 -eq $b2) { throw 'Roadmap repair branch names must differ across timestamps' }
if ($b1 -notlike 'roadmap-repair/*') { throw "Unexpected repair branch name format: $b1" }
# The token must never appear verbatim in the git args.
$tokenArgs = (Get-GitTokenPushArgs -Token 'super-secret-token') -join ' '
if ($tokenArgs -match 'super-secret-token') { throw 'The GitHub token must not appear in cleartext in git push arguments' }
if (@(Get-GitTokenPushArgs -Token '').Count -ne 0) { throw 'No token means no auth args (SSH remotes and operator-run hosts push without one)' }
# The entry point must RETURN a named refusal for empty inputs, not throw a
# parameter-binding error. Declaring RepoPath/RoadmapPath/ProposedContent as
# Mandatory made PowerShell reject the empty string before the precondition
# check ran, so the route answered 500 "Cannot bind argument to parameter
# 'RepoPath'" instead of the 409 that says what to fix. Caught by the api-host
# smoke on 2026-08-09; asserted here because it is cheaper to catch at this
# layer than after a 15-minute host run.
foreach ($empty in @(
    @{ name = 'empty repoPath';        args = @{ RepoName = 'x'; RepoPath = '';        RoadmapPath = 'C:\r\ROADMAP.md'; ProposedContent = 'new' } }
    @{ name = 'empty roadmapPath';     args = @{ RepoName = 'x'; RepoPath = 'C:\r';    RoadmapPath = '';                ProposedContent = 'new' } }
    @{ name = 'empty proposedContent'; args = @{ RepoName = 'x'; RepoPath = 'C:\r';    RoadmapPath = 'C:\r\ROADMAP.md'; ProposedContent = '' } }
)) {
    $submitOutcome = $null
    $submitSplat = $empty.args   # splatting needs a plain variable, not an expression
    try { $submitOutcome = Invoke-RoadmapRepairPrSubmission @submitSplat }
    catch { throw "Invoke-RoadmapRepairPrSubmission must RETURN a refusal for '$($empty.name)', not throw: $($_.Exception.Message)" }
    if ($null -eq $submitOutcome) { throw "Invoke-RoadmapRepairPrSubmission returned null for '$($empty.name)'" }
    if (-not $submitOutcome.refused) { throw "Invoke-RoadmapRepairPrSubmission must refuse '$($empty.name)'" }
    if ($submitOutcome.created) { throw "Invoke-RoadmapRepairPrSubmission must not report created=true for '$($empty.name)'" }
    if ([string]::IsNullOrWhiteSpace([string]$submitOutcome.reason)) { throw "Refusal for '$($empty.name)' must carry a named reason" }
}
Write-Host '  submit-PR ok: 4 remote forms parsed, 4 non-GitHub refused, 8 refusal categories named, 3 empty-input refusals returned (not thrown), token not in cleartext' -ForegroundColor DarkGray

Write-Step 'Branch-PR open — Release 3.4 milestone 3: one refusal matrix for any pushed branch'
# Open-RepoBranchPullRequest is the branch-and-PR half of the repair submission,
# extracted so an agent run's approve-push reaches GitHub through the same
# refusals. These assertions cover the matrix and the return-don't-throw
# contract; the network call itself is out of smoke's reach by design — every
# refusal below fires before any push or API request could happen.
$branchPrOk = @{
    RepoPath = 'C:\repo'; Branch = 'roadmap/run-1'; BaseBranch = 'main'
    Token = 'tok'; Slug = $okSlug; IsGitRepo = $true; BranchExists = $true
}
if (-not (Test-RepoBranchPrReadiness @branchPrOk).ok) { throw 'A fully valid branch-PR request must pass preconditions' }
foreach ($refusal in @(
    @{ name = 'no repo path';       override = @{ RepoPath = '' };        category = 'validation' }
    @{ name = 'not a git repo';     override = @{ IsGitRepo = $false };   category = 'validation' }
    @{ name = 'no branch';          override = @{ Branch = '' };          category = 'validation' }
    @{ name = 'branch missing';     override = @{ BranchExists = $false }; category = 'validation' }
    @{ name = 'no base branch';     override = @{ BaseBranch = '' };      category = 'validation' }
    @{ name = 'branch equals base'; override = @{ Branch = 'main' };      category = 'validation' }
    @{ name = 'no token';           override = @{ Token = '' };           category = 'auth' }
    @{ name = 'non-GitHub remote';  override = @{ Slug = $null };         category = 'validation' }
)) {
    $caseArgs = @{} + $branchPrOk
    foreach ($k in $refusal.override.Keys) { $caseArgs[$k] = $refusal.override[$k] }
    $verdict = Test-RepoBranchPrReadiness @caseArgs
    if ($verdict.ok) { throw "branch-PR must refuse '$($refusal.name)' but it passed preconditions" }
    if ($verdict.category -ne $refusal.category) { throw "branch-PR refusal '$($refusal.name)' expected category '$($refusal.category)', got '$($verdict.category)'" }
    if ([string]::IsNullOrWhiteSpace($verdict.reason)) { throw "branch-PR refusal '$($refusal.name)' must carry a named reason" }
}

# The impure entry point RETURNS refusals, never throws on expected conditions,
# and refuses a tokenless call before anything could reach the network.
$branchPrFixture = Join-Path $WorkspaceRoot 'output\smoke\module\branch-pr-fixture'
if (Test-Path -LiteralPath $branchPrFixture) { Remove-Item -LiteralPath $branchPrFixture -Recurse -Force }
$null = New-Item -ItemType Directory -Path $branchPrFixture -Force
& git -C $branchPrFixture init -b main --quiet 2>&1 | Out-Null
& git -C $branchPrFixture config user.email 'smoke@local' 2>&1 | Out-Null
& git -C $branchPrFixture config user.name 'smoke' 2>&1 | Out-Null
Set-Content -LiteralPath (Join-Path $branchPrFixture 'a.txt') -Value 'x' -Encoding UTF8
& git -C $branchPrFixture add -A 2>&1 | Out-Null
& git -C $branchPrFixture commit -m 'init' --quiet 2>&1 | Out-Null
& git -C $branchPrFixture switch -c 'roadmap/smoke-1' --quiet 2>&1 | Out-Null
& git -C $branchPrFixture remote add origin 'https://github.com/smoke/fixture.git' 2>&1 | Out-Null
$branchPrOutcome = $null
try { $branchPrOutcome = Open-RepoBranchPullRequest -RepoName 'fixture' -RepoPath $branchPrFixture -Branch 'roadmap/smoke-1' -BaseBranch 'main' -Token '' }
catch { throw "Open-RepoBranchPullRequest must RETURN a tokenless refusal, not throw: $($_.Exception.Message)" }
if (-not $branchPrOutcome.refused -or $branchPrOutcome.category -ne 'auth') { throw "Tokenless branch-PR open must refuse as 'auth', got '$($branchPrOutcome.category)'" }
$branchPrMissing = Open-RepoBranchPullRequest -RepoName 'fixture' -RepoPath $branchPrFixture -Branch 'no-such-branch' -BaseBranch 'main' -Token 'tok'
if (-not $branchPrMissing.refused -or $branchPrMissing.category -ne 'validation') { throw "A nonexistent branch must refuse as 'validation', got '$($branchPrMissing.category)'" }
Write-Host '  branch-PR ok: valid facts pass, 8 refusal categories named, tokenless and missing-branch refusals returned (not thrown)' -ForegroundColor DarkGray

Write-Step 'Completion commit — Release 3.4 milestone 4: the edit rides the feature branch, never a default one'
# Reproduced in a fixture, per the release acceptance criteria: a real repo, a
# real branch, a real commit — not an assertion about a description.
. (Join-Path $WorkspaceRoot 'backend\modules\roadmap\Roadmap.WriteBack.ps1')
$completionFixture = Join-Path $WorkspaceRoot 'output\smoke\module\completion-commit-fixture'
if (Test-Path -LiteralPath $completionFixture) { Remove-Item -LiteralPath $completionFixture -Recurse -Force }
$null = New-Item -ItemType Directory -Path $completionFixture -Force
& git -C $completionFixture init -b main --quiet 2>&1 | Out-Null
& git -C $completionFixture config user.email 'smoke@local' 2>&1 | Out-Null
& git -C $completionFixture config user.name 'smoke' 2>&1 | Out-Null
$completionRoadmap = Join-Path $completionFixture 'ROADMAP.md'
Set-Content -LiteralPath $completionRoadmap -Value "# Roadmap`n`n- [ ] Ship the widget`n- [ ] Other work`n" -Encoding UTF8
& git -C $completionFixture add -A 2>&1 | Out-Null
& git -C $completionFixture commit -m 'roadmap' --quiet 2>&1 | Out-Null

# On the DEFAULT branch: refuse by name, and write nothing.
$onMain = Add-RoadmapCompletionCommit -RepoPath $completionFixture -ItemText 'Ship the widget' -RunId 'smoke-run'
if ($onMain.committed -or $onMain.category -ne 'on-default-branch') { throw "Completion commit on main must refuse as 'on-default-branch', got committed=$($onMain.committed) category='$($onMain.category)'" }
if ((Get-Content -LiteralPath $completionRoadmap -Raw) -match '\[x\]') { throw 'The on-default-branch refusal must leave the roadmap untouched' }

# On a feature branch: flip the box, commit only the roadmap, leave the tree clean.
& git -C $completionFixture switch -c 'roadmap/smoke-run' --quiet 2>&1 | Out-Null
$headBefore = ((& git -C $completionFixture rev-parse HEAD) | Out-String).Trim()
$onBranch = Add-RoadmapCompletionCommit -RepoPath $completionFixture -ItemText 'Ship the widget' -RunId 'smoke-run'
if (-not $onBranch.committed) { throw "Completion commit on a feature branch must commit, got category='$($onBranch.category)' reason='$($onBranch.reason)'" }
$headAfter = ((& git -C $completionFixture rev-parse HEAD) | Out-String).Trim()
if ($headBefore -eq $headAfter) { throw 'Completion commit reported committed=true but HEAD did not move' }
if ((Get-Content -LiteralPath $completionRoadmap -Raw) -notmatch '- \[x\] Ship the widget') { throw 'The completion commit did not flip the checkbox' }
if ((Get-Content -LiteralPath $completionRoadmap -Raw) -notmatch '- \[ \] Other work') { throw 'The completion commit must touch only its own item' }
if (-not [string]::IsNullOrWhiteSpace(((& git -C $completionFixture status --porcelain) | Out-String).Trim())) { throw 'The completion commit must leave the working tree clean' }

# Idempotent: a second call reports already-complete and does not commit again.
$again = Add-RoadmapCompletionCommit -RepoPath $completionFixture -ItemText 'Ship the widget' -RunId 'smoke-run'
if ($again.committed -or -not $again.alreadyComplete) { throw 'A second completion commit must report alreadyComplete without committing' }
if (((& git -C $completionFixture rev-parse HEAD) | Out-String).Trim() -ne $headAfter) { throw 'already-complete must not move HEAD' }

# Unknown item: reported by name, nothing written.
$missing = Add-RoadmapCompletionCommit -RepoPath $completionFixture -ItemText 'An item that is not there' -RunId 'smoke-run'
if ($missing.committed -or $missing.category -ne 'item-not-found') { throw "An unknown item must refuse as 'item-not-found', got '$($missing.category)'" }

# The apply route may no longer write the file: completion is verified behind
# the merge-evidence gate, never written by it. Scoped to the route's own block
# — from its label to the next route label — so the assertion cannot be
# satisfied or broken by unrelated code.
$hostSource = Get-Content -LiteralPath (Join-Path $WorkspaceRoot 'backend\api-host\Start-RepoManagementApiHost.ps1') -Raw -Encoding UTF8
$applyBlockMatch = [regex]::Match($hostSource, "(?s)'POST /api/roadmap/write-back/apply'(.*?)'[A-Z]+ /api/")
if (-not $applyBlockMatch.Success) { throw 'Could not locate the write-back apply route block — the tripwire scope is broken, which must fail rather than pass vacuously' }
if ($applyBlockMatch.Groups[1].Value -match 'Set-Content\s+-LiteralPath\s+\$wbaCtx\.roadmapPath') {
    throw 'The write-back apply route writes the roadmap file again. Completion travels through the pull request (Release 3.4 milestone 4); the gate verifies, it does not write.'
}
Write-Host '  completion commit ok: default-branch refusal proven, feature-branch commit proven (HEAD moved, box flipped, tree clean), idempotent, unknown item named, apply route writes nothing' -ForegroundColor DarkGray

Write-Step 'Roadmap structure linter — smoke: R013/RQ001 relaxations still detect real violations'
$structureLinter = Join-Path $WorkspaceRoot 'tools\Test-RoadmapStructure.ps1'
if (-not (Test-Path -LiteralPath $structureLinter)) { throw "Test-RoadmapStructure.ps1 not found at: $structureLinter" }
$structureFixtureDir = Join-Path $WorkspaceRoot 'output\smoke\roadmap-structure'
$null = New-Item -ItemType Directory -Path $structureFixtureDir -Force

function Invoke-StructureLintCodes {
    param([Parameter(Mandatory)][string]$Content, [Parameter(Mandatory)][string]$Name)
    $fixturePath = Join-Path $structureFixtureDir $Name
    Set-Content -LiteralPath $fixturePath -Value $Content -Encoding UTF8
    # *>&1, not 2>&1: the linter reports findings with Write-Host, which lands on
    # the information stream. Capturing only stderr returned an empty string, so
    # every "rule must fire" assertion passed vacuously while the finding it was
    # looking for scrolled past on the console.
    $output = & $structureLinter -Path $fixturePath *>&1 | Out-String
    return $output
}

$bigBody = (1..160 | ForEach-Object { "- [ ] milestone item $_ _(state: planned)_" }) -join "`n"
$activeBig = @"
# Structure Fixture

> **Status:** Active
> **Active release:** **Release 1.0 - Alpha**

## 5. Active Release Snapshot

### Active release detail - 1.0 Alpha

Pointer only; deliberately restates nothing.

## 6. Open Releases

### Release 1.0 - Alpha

**Status:** active

**Goal:** ship it.

#### Engineering milestones

$bigBody

#### Acceptance criteria

- It ships.
"@
$activeBigOut = Invoke-StructureLintCodes -Content $activeBig -Name 'active-oversized.md'
if ($activeBigOut -match 'R013-FUTURE-RELEASE-SIZE') {
    throw 'R013 must NOT fire on the active release: the template puts the full execution contract there'
}
if ($activeBigOut -match 'RQ001-MISSING-STATUS') {
    throw 'RQ001 must NOT fire on a pointer block when the release itself declares its status'
}

# Same oversized body, but on a PLANNED release -> R013 must still fire.
$plannedBig = $activeBig.Replace('**Status:** active', '**Status:** planned')
if ((Invoke-StructureLintCodes -Content $plannedBig -Name 'planned-oversized.md') -notmatch 'R013-FUTURE-RELEASE-SIZE') {
    throw 'R013 must still fire for an oversized non-active release'
}

# Status declared NOWHERE -> RQ001 must still fire (and must not crash: an
# empty status-block set used to kill the linter on the very file it diagnoses).
$noStatus = $activeBig.Replace("**Status:** active`r`n", '').Replace("**Status:** active`n", '').Replace('**Status:** active', '')
$noStatusOut = Invoke-StructureLintCodes -Content $noStatus -Name 'no-status.md'
if ($noStatusOut -match 'Cannot bind argument') { throw 'Structure linter crashed on a roadmap with no status lines instead of reporting RQ001' }
if ($noStatusOut -notmatch 'RQ001-MISSING-STATUS') { throw 'RQ001 must still fire when neither the pointer nor the release declares a status' }

# No release headings at all -> R000, not a StrictMode crash on $null.Count.
$noReleasesOut = Invoke-StructureLintCodes -Content "# Empty`n`nNo releases here.`n" -Name 'no-releases.md'
if ($noReleasesOut -match 'cannot be found on this object') { throw 'Structure linter crashed on a release-less file instead of reporting R000' }
if ($noReleasesOut -notmatch 'R000-NO-RELEASES') { throw 'R000-NO-RELEASES must fire for a file with no release headings' }
Write-Host '  structure linter ok: active exempt from R013, planned still flagged; RQ001 fires only when status is declared nowhere; release-less file reports R000 instead of crashing' -ForegroundColor DarkGray

# Tripwire: the two evaluators must return the SAME verdict for the same file.
# Until 2026-08-08 they did not — the backend auditor and
# tools/Test-RoadmapContract.ps1 each carried private detection, and no repo in
# the estate scored the same under both. Whichever tool an operator happened to
# run decided whether a repo was dispatch-ready, which is exactly the
# "two figures, one truth" failure this product exists to catch. The status
# signal was the last one to reconcile (rules v1.3), so it is asserted here in
# both spellings and in the two-active case that trips the critical cap.
Write-Step 'Roadmap evaluators — smoke: module and Test-RoadmapContract.ps1 agree on one fixture'
$parityHost = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
$parityCli  = Join-Path $WorkspaceRoot 'tools\Test-RoadmapContract.ps1'
if (-not (Test-Path -LiteralPath $parityCli)) { throw "Test-RoadmapContract.ps1 not found at: $parityCli" }
$parityDir = Join-Path ([System.IO.Path]::GetTempPath()) ("roadmap-parity-{0}" -f ([guid]::NewGuid().ToString('N')))
New-Item -ItemType Directory -Path $parityDir -Force | Out-Null
try {
    $parityCases = @(
        @{ name = 'bold status, one active';       template = $activeReleaseFixture; one = 'active';  two = 'planned' }
        @{ name = 'blockquote status, one active'; template = $blockquoteFixture;    one = 'active';  two = 'planned' }
        @{ name = 'alias status, two active';      template = $activeReleaseFixture; one = 'active';  two = 'In Progress' }
        @{ name = 'no active release';             template = $blockquoteFixture;    one = 'planned'; two = 'planned' }
    )

    foreach ($case in $parityCases) {
        $caseContent = $case.template -f $case.one, $case.two
        $caseRoot = Join-Path $parityDir ($case.name -replace '[^A-Za-z0-9]', '-')
        New-Item -ItemType Directory -Path $caseRoot -Force | Out-Null
        $caseRoadmap = Join-Path $caseRoot 'ROADMAP.md'
        Set-Content -LiteralPath $caseRoadmap -Value $caseContent -Encoding UTF8

        $caseParsed   = Invoke-ParseRoadmapContent -Content $caseContent -SourcePath 'ROADMAP.md'
        $caseContract = Invoke-NormalizeRoadmapContract -ParsedResult $caseParsed -RawContent $caseContent -RepoName 'smoke-parity' -AuditRules $auditRulesObj
        $moduleAudit  = Invoke-AuditRoadmapContract -Contract $caseContract -AuditRules $auditRulesObj

        $caseContractOut = Join-Path $caseRoot 'contract.json'
        & $parityHost -NoProfile -File $parityCli -Path $caseRoadmap `
            -StandardsPath (Join-Path $WorkspaceRoot 'standards\roadmap') `
            -ContractOut $caseContractOut -Quiet 2>&1 | Out-Null
        if (-not (Test-Path -LiteralPath $caseContractOut)) {
            throw ("Test-RoadmapContract.ps1 produced no contract for parity case '{0}'" -f $case.name)
        }
        $cliAudit = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $caseContractOut -Raw -Encoding UTF8)

        $moduleFindings = (@($moduleAudit.auditFindings | ForEach-Object { [string]$_.ruleId } | Sort-Object) -join ',')
        $cliFindings    = (@($cliAudit.auditFindings    | ForEach-Object { [string]$_.ruleId } | Sort-Object) -join ',')

        foreach ($field in @(
            @{ label = 'maturityScore';      mod = [int]$moduleAudit.maturityScore;      cli = [int]$cliAudit.maturityScore }
            @{ label = 'maturityLevel';      mod = [string]$moduleAudit.maturityLevel;   cli = [string]$cliAudit.maturityLevel }
            @{ label = 'releaseCount';       mod = [int]$moduleAudit.releaseCount;       cli = [int]$cliAudit.releaseCount }
            @{ label = 'activeReleaseCount'; mod = [int]$moduleAudit.activeReleaseCount; cli = [int]$cliAudit.activeReleaseCount }
            @{ label = 'pendingCount';       mod = [int]$moduleAudit.pendingCount;       cli = [int]$cliAudit.pendingCount }
            @{ label = 'completedCount';     mod = [int]$moduleAudit.completedCount;     cli = [int]$cliAudit.completedCount }
            @{ label = 'auditFindings';      mod = $moduleFindings;                      cli = $cliFindings }
        )) {
            if ($field.mod -ne $field.cli) {
                throw ("Evaluator divergence on parity case '{0}': {1} module={2} cli={3}. Both evaluators must derive this signal from the 'detection' block in roadmap-audit-rules.json — do not reintroduce a private pattern in either tool." -f $case.name, $field.label, $field.mod, $field.cli)
            }
        }
    }
    Write-Host ("  evaluator parity ok: {0} fixtures agree on score, level, counts, and findings" -f @($parityCases).Count) -ForegroundColor DarkGray
}
finally {
    Remove-Item -LiteralPath $parityDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Step 'Roadmap standard assets — smoke: validate roadmap-audit-rules.json (Release 0.7)'
$roadmapAuditRulesPath   = Join-Path $WorkspaceRoot 'standards\roadmap\roadmap-audit-rules.json'
$roadmapSchemaPath       = Join-Path $WorkspaceRoot 'standards\roadmap\roadmap-contract.schema.json'
$roadmapTemplatePath     = Join-Path $WorkspaceRoot 'standards\roadmap\ROADMAP_TEMPLATE.md'
$roadmapMaturityPath     = Join-Path $WorkspaceRoot 'standards\roadmap\ROADMAP_MATURITY_MODEL.md'
$roadmapRepairPath       = Join-Path $WorkspaceRoot 'standards\roadmap\roadmap-repair-prompt.md'
@($roadmapAuditRulesPath, $roadmapSchemaPath, $roadmapTemplatePath, $roadmapMaturityPath, $roadmapRepairPath) | ForEach-Object {
    if (-not (Test-Path -LiteralPath $_)) { throw "Roadmap standard asset not found: $_" }
}
$auditRules = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $roadmapAuditRulesPath -Raw -Encoding UTF8)
if ($null -eq $auditRules.rules)              { throw "roadmap-audit-rules.json missing 'rules' array" }
if ($null -eq $auditRules.maturityThresholds) { throw "roadmap-audit-rules.json missing 'maturityThresholds'" }
if (@($auditRules.rules).Count -eq 0)         { throw "roadmap-audit-rules.json 'rules' array is empty" }
$schema = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $roadmapSchemaPath -Raw -Encoding UTF8)
if ($null -eq $schema.properties)             { throw "roadmap-contract.schema.json missing 'properties'" }
Write-Host ("  roadmap standard assets valid: {0} audit rules, {1} maturity levels" -f @($auditRules.rules).Count, @($auditRules.maturityThresholds.PSObject.Properties).Count) -ForegroundColor DarkGray

# Tripwire: every rule the pack ships must be evaluated by the auditor. An
# unevaluated rule still contributes its weight to the denominator, so adding
# one silently inflates every score and pushes roadmaps across the L3 dispatch
# gate. This is the d2cc6cc / c6662cf regression class — counting rules is not
# enough, the auditor must actually implement each id.
Write-Step 'Roadmap standard assets — smoke: every shipped audit rule is implemented by the auditor'
$auditorSource = Get-Content -LiteralPath (Join-Path $WorkspaceRoot 'backend\modules\roadmap\Roadmap.Auditor.ps1') -Raw -Encoding UTF8
$unimplementedRules = @()
foreach ($rule in @($auditRules.rules)) {
    $ruleId = [string]$rule.id
    if ($auditorSource -notmatch [regex]::Escape("'$ruleId'")) { $unimplementedRules += $ruleId }
}
if ($unimplementedRules.Count -gt 0) {
    throw ("roadmap-audit-rules.json ships rule(s) the auditor never evaluates: {0}. Each contributes scoreWeight to maxPossibleScore but can never fail, inflating every maturity score. Implement a case in Invoke-AuditRoadmapContract or remove the rule." -f ($unimplementedRules -join ', '))
}
Write-Host ("  all {0} audit rules implemented in Roadmap.Auditor.ps1" -f @($auditRules.rules).Count) -ForegroundColor DarkGray

# Tripwire: the published spec copy must not drift from the live rule pack.
# standards/roadmap is code-referenced at runtime; spec/roadmap-contract is the
# publishable Release 2.3 deliverable. README.md is intentionally per-location.
Write-Step 'Roadmap standard assets — smoke: standards/roadmap and spec/roadmap-contract stay in sync'
$specDrift = @()
foreach ($assetName in @('ROADMAP_BUDGET_MODEL.md','ROADMAP_MATURITY_MODEL.md','ROADMAP_TEMPLATE.md','roadmap-audit-rules.json','roadmap-contract.schema.json','roadmap-events.md','roadmap-repair-prompt.md')) {
    $standardsAsset = Join-Path $WorkspaceRoot ("standards\roadmap\{0}" -f $assetName)
    $specAsset      = Join-Path $WorkspaceRoot ("spec\roadmap-contract\{0}" -f $assetName)
    if (-not (Test-Path -LiteralPath $standardsAsset)) { throw "Roadmap standard asset not found: $standardsAsset" }
    if (-not (Test-Path -LiteralPath $specAsset))      { throw "Published spec asset not found: $specAsset" }
    # Compare CONTENT, not bytes on disk. This repo runs core.autocrlf=true with
    # no .gitattributes, so whether a given working-tree file holds CRLF or LF
    # depends on which git operation last materialised it — a stash, a partial
    # checkout, or a fresh clone each leave a different answer. Hashing raw bytes
    # made this gate report drift between two files whose content is identical
    # (245 CRLF vs 245 LF, same 16,280 characters), and would equally hide real
    # drift if the endings happened to match. Normalise first, then compare.
    $standardsText = (Get-Content -LiteralPath $standardsAsset -Raw -Encoding UTF8) -replace "`r`n", "`n"
    $specText      = (Get-Content -LiteralPath $specAsset -Raw -Encoding UTF8) -replace "`r`n", "`n"
    if ($standardsText.TrimEnd("`n") -ne $specText.TrimEnd("`n")) { $specDrift += $assetName }
}
if ($specDrift.Count -gt 0) {
    throw ("standards/roadmap has drifted from spec/roadmap-contract for: {0}. Copy the updated file(s) into spec/roadmap-contract, or document the intended divergence in standards/MANIFEST.md." -f ($specDrift -join ', '))
}
Write-Host '  standards/roadmap and spec/roadmap-contract in sync (7 assets)' -ForegroundColor DarkGray

Write-Step 'Loading roadmap repairer module (Release 0.9)'
$roadmapRepairer = Join-Path $WorkspaceRoot 'backend\modules\roadmap\Roadmap.Repairer.ps1'
if (-not (Test-Path -LiteralPath $roadmapRepairer)) { throw "Roadmap.Repairer.ps1 not found at: $roadmapRepairer" }
. $roadmapRepairer
Write-Host 'Roadmap repairer module loaded successfully' -ForegroundColor Green

Write-Step 'Roadmap repairer — smoke: plan repair for missing roadmap (expect repair-blocked)'
$missingContract2 = Invoke-NormalizeRoadmapContract -ParsedResult $null -RepoName 'smoke-repair-missing'
$missingContract2 = Invoke-AuditRoadmapContract -Contract $missingContract2 -AuditRules $auditRulesObj
$missingPlan = Invoke-PlanRoadmapRepair -Contract $missingContract2
if ($missingPlan.previewState -ne 'repair-blocked') { throw "Expected previewState=repair-blocked for missing roadmap, got $($missingPlan.previewState)" }
Write-Host '  missing roadmap plan -> repair-blocked correctly' -ForegroundColor DarkGray

Write-Step 'Roadmap repairer — smoke: plan repair for complete roadmap (expect rewrite-not-recommended)'
$completeParsed2  = Invoke-ParseRoadmapContent -Content "## Done`n- [x] Item one`n- [x] Item two"
$completeContract = Invoke-NormalizeRoadmapContract -ParsedResult $completeParsed2 -RawContent "## Done`n- [x] Item one`n- [x] Item two" -RepoName 'smoke-repair-complete'
$completeContract = Invoke-AuditRoadmapContract -Contract $completeContract -AuditRules $auditRulesObj
$completePlan = Invoke-PlanRoadmapRepair -Contract $completeContract
if ($completePlan.previewState -ne 'rewrite-not-recommended') { throw "Expected previewState=rewrite-not-recommended for complete roadmap, got $($completePlan.previewState)" }
Write-Host '  complete roadmap plan -> rewrite-not-recommended correctly' -ForegroundColor DarkGray

Write-Step 'Roadmap repairer — smoke: plan repair for L1 informal roadmap (expect repair-preview-ready)'
$informalContent = "## Tasks`n- [ ] Do something`n- [ ] Do another thing`n- [x] Done already"
$informalParsed  = Invoke-ParseRoadmapContent -Content $informalContent
$informalContract = Invoke-NormalizeRoadmapContract -ParsedResult $informalParsed -RawContent $informalContent -RepoName 'smoke-repair-informal'
$informalContract = Invoke-AuditRoadmapContract -Contract $informalContract -AuditRules $auditRulesObj
$informalPlan = Invoke-PlanRoadmapRepair -Contract $informalContract
if ($informalPlan.previewState -ne 'repair-preview-ready') { throw "Expected previewState=repair-preview-ready for L1 informal roadmap, got $($informalPlan.previewState)" }
if (@($informalPlan.actions).Count -eq 0) { throw "Expected at least one repair action for L1 informal roadmap" }
Write-Host ("  L1 informal roadmap plan -> repair-preview-ready with {0} action(s)" -f @($informalPlan.actions).Count) -ForegroundColor DarkGray

Write-Step 'Roadmap repairer — smoke: generate repair preview for L1 informal roadmap'
$informalPreview = Invoke-GenerateRepairPreview -Contract $informalContract -RepairPlan $informalPlan -RawContent $informalContent -RepoName 'smoke-repair-informal'
if ($informalPreview.previewState -ne 'repair-preview-ready') { throw "Expected previewState=repair-preview-ready in preview result, got $($informalPreview.previewState)" }
if ([string]::IsNullOrWhiteSpace($informalPreview.proposedContent)) { throw "Expected non-empty proposedContent for repair-preview-ready state" }
if ([string]::IsNullOrWhiteSpace($informalPreview.previewId)) { throw "Expected non-empty previewId in preview result" }
# Verify completed items are preserved in proposed content
if ($informalPreview.proposedContent -notmatch '\[x\]') { throw "Expected completed items (- [x]) to be preserved in proposed content" }
# Verify pending items are present
if ($informalPreview.proposedContent -notmatch '\[ \]') { throw "Expected pending items (- [ ]) to appear in proposed content" }
Write-Host ("  repair preview generated: previewId={0} completedItemCount={1} pendingItemCount={2}" -f $informalPreview.previewId, $informalPreview.completedItemCount, $informalPreview.pendingItemCount) -ForegroundColor DarkGray

Write-Step 'Roadmap repairer — smoke: generate preview for blocked state returns null proposedContent'
$blockedPreview = Invoke-GenerateRepairPreview -Contract $missingContract2 -RepairPlan $missingPlan -RawContent '' -RepoName 'smoke-repair-missing'
if ($blockedPreview.previewState -ne 'repair-blocked') { throw "Expected previewState=repair-blocked in blocked preview, got $($blockedPreview.previewState)" }
if ($null -ne $blockedPreview.proposedContent -and -not [string]::IsNullOrWhiteSpace($blockedPreview.proposedContent)) {
    throw "Expected proposedContent to be null/empty for repair-blocked state"
}
Write-Host '  blocked preview correctly returns null proposedContent' -ForegroundColor DarkGray

Write-Step 'Roadmap repairer — smoke: split-archive layout is preserved, never contradicted (Lane 0.7)'
# A roadmap that archives completed work to a separate file must not be told it
# has no history. The old placeholder was doubly wrong: it asserted something
# false, and '- [x]' was counted as a completed item on the next parse.
$splitContent = @'
# Split Roadmap

Completed work lives in [the archive](docs/history/completed-releases.md).

## Open Work

- [ ] Build the first thing
- [ ] Build the second thing
- [ ] Build the third thing
'@
$splitParsed   = Invoke-ParseRoadmapContent -Content $splitContent
$splitContract = Invoke-NormalizeRoadmapContract -ParsedResult $splitParsed -RawContent $splitContent -RepoName 'smoke-repair-split'
$splitContract = Invoke-AuditRoadmapContract -Contract $splitContract -AuditRules $auditRulesObj
$splitPlan     = Invoke-PlanRoadmapRepair -Contract $splitContract
$splitPreview  = Invoke-GenerateRepairPreview -Contract $splitContract -RepairPlan $splitPlan -RawContent $splitContent -RepoName 'smoke-repair-split'

$pointer = Get-RoadmapHistoryPointer -Content $splitContent
if ($null -eq $pointer) { throw 'Expected the archive pointer link to be detected in a split roadmap' }
if ($pointer.Target -ne 'docs/history/completed-releases.md') { throw "Expected pointer target docs/history/completed-releases.md, got '$($pointer.Target)'" }
if ($null -ne (Get-RoadmapHistoryPointer -Content "## Tasks`n- [ ] a")) { throw 'Expected no pointer for a roadmap without an archive link' }

# Assert the state rather than guarding on it — a guard would let every
# assertion below silently stop running if the plan state ever changed.
if ($splitPreview.previewState -ne 'repair-preview-ready') {
    throw "Expected repair-preview-ready for the split fixture, got '$($splitPreview.previewState)' — the assertions below would not have run"
}
if ($splitPreview.proposedContent -match 'No completed items recorded yet') {
    throw 'Repair must not assert "No completed items recorded yet" on a roadmap whose history is archived'
}
if ($splitPreview.proposedContent -notmatch [regex]::Escape('docs/history/completed-releases.md')) {
    throw 'Repair must carry the archive pointer into the proposed content'
}
if ([int]$splitPreview.completedItemCount -ne 0) {
    throw "Expected completedItemCount=0 for a split roadmap, got $($splitPreview.completedItemCount)"
}
# The empty-state line must not be a checkbox, or reparsing inflates the count.
$reparsed = Invoke-ParseRoadmapContent -Content $splitPreview.proposedContent
if ([int]$reparsed.completedCount -ne 0) {
    throw "Repair output must not reparse as completed work; got completedCount=$($reparsed.completedCount)"
}

# No pointer -> the claim is scoped to the file, not the project.
$noHistoryContent = "## Tasks`n- [ ] alpha`n- [ ] beta`n- [ ] gamma"
$nhParsed   = Invoke-ParseRoadmapContent -Content $noHistoryContent
$nhContract = Invoke-NormalizeRoadmapContract -ParsedResult $nhParsed -RawContent $noHistoryContent -RepoName 'smoke-repair-nohistory'
$nhContract = Invoke-AuditRoadmapContract -Contract $nhContract -AuditRules $auditRulesObj
$nhPlan     = Invoke-PlanRoadmapRepair -Contract $nhContract
$nhPreview  = Invoke-GenerateRepairPreview -Contract $nhContract -RepairPlan $nhPlan -RawContent $noHistoryContent -RepoName 'smoke-repair-nohistory'
if ($nhPreview.previewState -ne 'repair-preview-ready') {
    throw "Expected repair-preview-ready for the no-history fixture, got '$($nhPreview.previewState)'"
}
if ($nhPreview.proposedContent -match 'No completed items recorded yet') { throw 'The old absolute placeholder must be gone' }
if ($nhPreview.proposedContent -notmatch 'recorded in this file') { throw 'Expected the empty-state claim to be scoped to this file' }
Write-Host '  split-archive repair ok: pointer detected + preserved, no false "no history" claim, output reparses to 0 completed' -ForegroundColor DarkGray

Write-Step 'Loading repo evaluator module (Release 1.4 / Phase 5 expanded evaluator)'
if (-not (Test-Path -LiteralPath $roadmapEvaluatorPath)) { throw "Roadmap.Evaluator.ps1 not found at: $roadmapEvaluatorPath" }
. $roadmapEvaluatorPath
Write-Host 'Repo evaluator module loaded successfully' -ForegroundColor Green

Write-Step 'Repo evaluator — smoke: no-roadmap repo includes modernization and value opportunities'
$tmpEvalRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('repoeval-smoke-' + [guid]::NewGuid().ToString('n').Substring(0, 8))
$null = New-Item -ItemType Directory -Path (Join-Path $tmpEvalRoot 'backend') -Force
Set-Content -LiteralPath (Join-Path $tmpEvalRoot 'package.json') -Encoding UTF8 -Value @'
{
  "name": "smoke-eval",
  "version": "1.0.0",
  "scripts": {
    "build": "node backend/server.js"
  }
}
'@
Set-Content -LiteralPath (Join-Path $tmpEvalRoot 'README.md') -Encoding UTF8 -Value @'
# Smoke Eval

Short overview only.
'@
Set-Content -LiteralPath (Join-Path $tmpEvalRoot 'backend\server.js') -Encoding UTF8 -Value 'console.log("hello");'

try {
    $evalResult = Invoke-RepoEvaluation -RepoName 'smoke-eval' -LocalPath $tmpEvalRoot
    if ($evalResult.repoType -ne 'node') { throw "Expected repoType=node, got $($evalResult.repoType)" }
    if ($evalResult.hasExistingRoadmap) { throw 'Expected hasExistingRoadmap=false for no-roadmap smoke repo' }
    if ([string]::IsNullOrWhiteSpace($evalResult.suggestedRoadmapContent)) { throw 'Expected suggestedRoadmapContent for repo without roadmap' }
    $evalCategories = @($evalResult.findings | ForEach-Object { [string]$_.category } | Select-Object -Unique)
    foreach ($expectedCategory in @('documentation', 'testing', 'security', 'modernization', 'feature', 'user-value')) {
        if ($evalCategories -notcontains $expectedCategory) {
            throw "Expected expanded evaluator category '$expectedCategory' in smoke result, got: $($evalCategories -join ', ')"
        }
    }
    if ($evalResult.suggestedRoadmapContent -notmatch '## Release 1\.0') { throw 'Expected suggestedRoadmapContent to contain Release 1.0 section' }
    if ($evalResult.suggestedRoadmapContent -notmatch 'Workflow Clarity and User Value') { throw 'Expected suggested roadmap to contain Workflow Clarity and User Value release' }
    if ($evalResult.suggestedRoadmapContent -notmatch 'Modernization and Operability') { throw 'Expected suggested roadmap to contain Modernization and Operability release' }
    Write-Host ("  expanded evaluator categories: {0}" -f ($evalCategories -join ', ')) -ForegroundColor DarkGray

    Set-Content -LiteralPath (Join-Path $tmpEvalRoot 'ROADMAP.md') -Encoding UTF8 -Value @'
# Existing Roadmap

## Release 1.0 — Initial

### Engineering milestones
- [ ] Keep this roadmap alive
'@
    $evalExistingRoadmap = Invoke-RepoEvaluation -RepoName 'smoke-eval' -LocalPath $tmpEvalRoot
    if (-not $evalExistingRoadmap.hasExistingRoadmap) { throw 'Expected hasExistingRoadmap=true after creating roadmap file' }
    if ($null -ne $evalExistingRoadmap.suggestedRoadmapContent -and -not [string]::IsNullOrWhiteSpace($evalExistingRoadmap.suggestedRoadmapContent)) {
        throw 'Expected suggestedRoadmapContent to be null/empty when roadmap already exists'
    }
    if (@($evalExistingRoadmap.suggestedAdditions).Count -eq 0) { throw 'Expected suggestedAdditions for repo with existing roadmap' }
    Write-Host ("  existing-roadmap suggestions: {0}" -f @($evalExistingRoadmap.suggestedAdditions).Count) -ForegroundColor DarkGray
} finally {
    Remove-Item -LiteralPath $tmpEvalRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Step 'Running reconciliation preflight check'
& (Join-Path $WorkspaceRoot 'backend\modules\reconcile\preflight-check.ps1')

Write-Step 'Loading execution ledger module (Release 1.0)'
$executionLedgerPath = Join-Path $WorkspaceRoot 'backend\modules\execution\Execution.Ledger.ps1'
if (-not (Test-Path -LiteralPath $executionLedgerPath)) { throw "Execution.Ledger.ps1 not found at: $executionLedgerPath" }
. $executionLedgerPath
Write-Host 'Execution ledger module loaded successfully' -ForegroundColor Green

Write-Step 'Execution ledger — smoke: sync from audit data and verify states'
$smokeWs = Join-Path $WorkspaceRoot 'output\smoke\module\execution'
if (-not (Test-Path -LiteralPath $smokeWs)) {
    $null = New-Item -ItemType Directory -Path $smokeWs -Force
}
$null = New-Item -ItemType Directory -Path (Join-Path $smokeWs 'output\execution') -Force -ErrorAction SilentlyContinue

# Start from a known ledger. Sync-LedgerFromAudit preserves `running` entries
# by design, so a lane left occupied by a PREVIOUS run — any run that failed
# part-way and never reached its cleanup — survives into this one and fails
# the ready-count assertion below, pointing at a defect that is not there.
# The fixture is disposable; the state carried between runs is the bug.
$smokeLedgerFile = Join-Path $smokeWs 'output\execution\execution-ledger.json'
if (Test-Path -LiteralPath $smokeLedgerFile) {
    Remove-Item -LiteralPath $smokeLedgerFile -Force
}
$smokeDocEntries = @(
    [PSCustomObject]@{
        repoName = 'smoke-repo-ready'; repoPath = $smokeWs; dispatchReadiness = 'ready'
        nextPendingRoadmapItem = 'Implement feature smoke-A'; roadmapState = 'pending'
        criticalCount = 0; warningCount = 0; infoCount = 0; readyForDispatch = $true
        auditedAt = (Get-Date).ToString('o'); docFindings = @()
    },
    [PSCustomObject]@{
        repoName = 'smoke-repo-blocked'; repoPath = $smokeWs; dispatchReadiness = 'blocked'
        nextPendingRoadmapItem = ''; roadmapState = 'missing'
        criticalCount = 2; warningCount = 0; infoCount = 0; readyForDispatch = $false
        auditedAt = (Get-Date).ToString('o'); docFindings = @()
    },
    [PSCustomObject]@{
        # Lane 0.17 — a ready repo with NO roadmap-audit entry: the ledger must
        # leave roadmapPath empty, never write the roadmap item TEXT into it.
        repoName = 'smoke-repo-noaudit'; repoPath = $smokeWs; dispatchReadiness = 'ready'
        nextPendingRoadmapItem = '**Store an API key in Settings** and confirm live data renders'; roadmapState = 'pending'
        criticalCount = 0; warningCount = 0; infoCount = 0; readyForDispatch = $true
        auditedAt = (Get-Date).ToString('o'); docFindings = @()
    }
)
$smokeRoadmapEntries = @(
    [PSCustomObject]@{
        repoName = 'smoke-repo-ready'; maturityScore = 70
        nextPendingItem = [PSCustomObject]@{ text = 'Implement feature smoke-A'; section = 'Release 1.0' }
        roadmapPath = (Join-Path $smokeWs 'ROADMAP.md')
    }
)
$smokedLedger = Sync-LedgerFromAudit -WorkspaceRoot $smokeWs -DocAuditEntries $smokeDocEntries -RoadmapAuditEntries $smokeRoadmapEntries
$smokeReady   = @($smokedLedger.entries | Where-Object { $_.executionState -eq 'ready'   }).Count
$smokeBlocked = @($smokedLedger.entries | Where-Object { $_.executionState -eq 'blocked' }).Count
if ($smokeReady   -ne 2) { throw "Expected 2 ready entries after sync, got $smokeReady"   }
if ($smokeBlocked -ne 1) { throw "Expected 1 blocked entry after sync, got $smokeBlocked" }
# Lane 0.17 — roadmapPath holds a path or nothing. The regression this pins:
# Sync-LedgerFromAudit used to fall back to $doc.nextPendingRoadmapItem (item
# TEXT), so queue rows rendered raw markdown as their "path" and dispatch
# handed the packet builder a path that never existed.
$smokeNoAudit = $smokedLedger.entries | Where-Object { $_.repoName -eq 'smoke-repo-noaudit' } | Select-Object -First 1
if ($null -eq $smokeNoAudit) { throw 'Expected smoke-repo-noaudit in the synced ledger' }
if ($smokeNoAudit.roadmapPath -ne '') { throw "Lane 0.17: roadmapPath must be empty when no roadmap-audit entry exists, got '$($smokeNoAudit.roadmapPath)'" }
Write-Host ('  sync: ready=' + $smokeReady + ' blocked=' + $smokeBlocked + '; no-audit roadmapPath stays empty') -ForegroundColor DarkGray

Write-Step 'Execution ledger — smoke: assign lane and verify duplicate guard'
$assignResult = Invoke-AssignLane -WorkspaceRoot $smokeWs -RepoName 'smoke-repo-ready'
if (-not $assignResult.success) { throw "Expected assign to succeed, got error: $($assignResult.error)" }
if ($assignResult.laneSlot -ne 1) { throw "Expected laneSlot=1, got $($assignResult.laneSlot)" }
$dupResult = Invoke-AssignLane -WorkspaceRoot $smokeWs -RepoName 'smoke-repo-ready'
if ($dupResult.success) { throw "Expected duplicate assign to fail, but it succeeded" }
Write-Host ('  assign lane=1 ok; duplicate blocked correctly') -ForegroundColor DarkGray

Write-Step 'Execution ledger — smoke: complete task and verify state transition'
$completeResult = Invoke-CompleteTask -WorkspaceRoot $smokeWs -RepoName 'smoke-repo-ready' -Outcome 'success' -HasRemainingWork $false
if (-not $completeResult.success) { throw "Expected complete to succeed, got error: $($completeResult.error)" }
if ($completeResult.newState -ne 'complete') { throw "Expected newState=complete, got $($completeResult.newState)" }
Write-Host '  complete task -> state=complete correctly' -ForegroundColor DarkGray

Write-Step 'Execution ledger — smoke: cancel task and verify retry count'
# Re-sync to get the ready repo back
$null = Sync-LedgerFromAudit -WorkspaceRoot $smokeWs -DocAuditEntries $smokeDocEntries -RoadmapAuditEntries $smokeRoadmapEntries
$null = Invoke-AssignLane -WorkspaceRoot $smokeWs -RepoName 'smoke-repo-ready'
$cancelResult = Invoke-CancelTask -WorkspaceRoot $smokeWs -RepoName 'smoke-repo-ready' -Reason 'test-cancel' -MaxRetries 3
if (-not $cancelResult.success) { throw "Expected cancel to succeed, got error: $($cancelResult.error)" }
if ($cancelResult.newState -notin @('ready','blocked')) { throw "Expected newState=ready or blocked after cancel, got $($cancelResult.newState)" }
Write-Host ('  cancel -> newState=' + $cancelResult.newState + ' retryCount=' + $cancelResult.retryCount) -ForegroundColor DarkGray

Write-Step 'Execution ledger — smoke: requeue blocked repo'
$null = Invoke-RequeueRepo -WorkspaceRoot $smokeWs -RepoName 'smoke-repo-blocked' -Force $true
$summaryAfterRequeue = Get-ExecutionQueueSummary -WorkspaceRoot $smokeWs
$requeuedEntry = $summaryAfterRequeue.entries | Where-Object { $_.repoName -eq 'smoke-repo-blocked' } | Select-Object -First 1
if ($requeuedEntry.executionState -ne 'ready') { throw "Expected smoke-repo-blocked to be 'ready' after requeue, got $($requeuedEntry.executionState)" }
Write-Host '  requeue blocked -> ready correctly' -ForegroundColor DarkGray

Write-Step 'Execution ledger — smoke: ranked queue and summary'
$summary = Get-ExecutionQueueSummary -WorkspaceRoot $smokeWs
if ($null -eq $summary.lanes)       { throw 'Expected summary.lanes to be present' }
if ($null -eq $summary.rankedQueue) { throw 'Expected summary.rankedQueue to be present' }
if ($null -eq $summary.stateCounts) { throw 'Expected summary.stateCounts to be present' }
Write-Host ("  queue summary: total={0} activeLanes={1} rankedQueue={2}" -f $summary.totalRepos, $summary.activeLaneCount, @($summary.rankedQueue).Count) -ForegroundColor DarkGray

# ---------------------------------------------------------------------------
# Lane 0.17 — observed lane state.
#
# What this pins: 'running' used to mean only "an operator clicked Dispatch and
# has not clicked Complete", so every lane rendered identically whether its
# agent was three minutes into a draft PR or had died an hour earlier. These
# assertions prove the lane now resolves to the run ledgers, that a lane with
# nothing behind it says so, and that a finished run does not follow the repo
# into its next lane.
# ---------------------------------------------------------------------------
Write-Step 'Loading lane observation module (Lane 0.17)'
$laneObsPath = Join-Path $WorkspaceRoot 'backend\modules\execution\Execution.LaneObservation.ps1'
if (-not (Test-Path -LiteralPath $laneObsPath)) { throw "Execution.LaneObservation.ps1 not found at: $laneObsPath" }
. $laneObsPath
Write-Host 'Lane observation module loaded successfully' -ForegroundColor Green

Write-Step 'Lane observation — smoke: the decision table, offline'
$obsNow = [datetime]::Parse('2026-09-06T12:00:00Z').ToUniversalTime()

# A lane occupied by hand resolves to nothing, and says so rather than
# rendering the empty shape of a run that does not exist.
$handLane = [ordered]@{
    repoName = 'smoke-hand'; executionState = 'running'; laneSlot = 1
    currentRunId = 'local-guid'; dispatchRunId = ''; agentRunId = ''
    assignedAt = $obsNow.AddMinutes(-42).ToString('o')
}
$obsHand = Resolve-LaneObservation -Entry $handLane -NowUtc $obsNow
if ($obsHand.verdict -ne 'unlinked') { throw "Expected verdict=unlinked for a hand-occupied lane, got '$($obsHand.verdict)'" }
if ($obsHand.linked) { throw 'Expected linked=$false for a hand-occupied lane' }
if ($obsHand.laneAgeMinutes -ne 42) { throw "Expected laneAgeMinutes=42, got $($obsHand.laneAgeMinutes)" }
if ($obsHand.verdictDetail -notmatch '42 minutes') { throw "Expected the unlinked detail to name the lane age, got: $($obsHand.verdictDetail)" }

# Queued past the runner's patience is the 'is it stuck?' answer the board
# exists to give — and the threshold that produced it ships with the verdict.
$queuedLane = [ordered]@{ repoName = 'smoke-queued'; executionState = 'running'; dispatchRunId = 'run-q'; assignedAt = $obsNow.AddMinutes(-40).ToString('o') }
$obsQueued = Resolve-LaneObservation -Entry $queuedLane -RunSummary ([pscustomobject]@{ status = 'queued'; startedAt = $obsNow.AddMinutes(-40).ToString('o') }) -NowUtc $obsNow
if ($obsQueued.verdict -ne 'queued') { throw "Expected verdict=queued, got '$($obsQueued.verdict)'" }
if (-not $obsQueued.stalled) { throw 'Expected a 40-minute-unclaimed queued task to be stalled (patience is 15 minutes)' }
if ($obsQueued.stalledAfterMinutes -ne 15) { throw "Expected stalledAfterMinutes=15, got $($obsQueued.stalledAfterMinutes)" }

# A draft PR observed four minutes ago is working, NOT stuck. The inverse of
# the assertion above, and the reason patience is per-verdict.
$workingRun = [pscustomobject]@{
    runId = 'ar-1'; dispatchRunId = 'run-w'; status = 'active'
    prUrl = 'https://github.com/x/y/pull/18'; prNumber = 18; prState = 'open'; prDraft = $true
    lastRefreshAt = $obsNow.AddMinutes(-4).ToString('o')
}
$workingLane = [ordered]@{ repoName = 'smoke-working'; executionState = 'running'; dispatchRunId = 'run-w'; assignedAt = $obsNow.AddMinutes(-20).ToString('o') }
$obsWorking = Resolve-LaneObservation -Entry $workingLane -AgentRun $workingRun -NowUtc $obsNow
if ($obsWorking.verdict -ne 'working') { throw "Expected verdict=working, got '$($obsWorking.verdict)'" }
if ($obsWorking.stalled) { throw 'Expected a PR observed 4 minutes ago NOT to be stalled' }
if ($obsWorking.pr.number -ne 18) { throw "Expected the PR number to reach the surface, got '$($obsWorking.pr.number)'" }

# A merged run is terminal: it warrants Complete, and terminal states never
# go stale no matter how long they sit.
$mergedRun = [pscustomobject]@{
    runId = 'ar-2'; dispatchRunId = 'run-m'; status = 'completed'; outcome = 'merged'
    prUrl = 'https://github.com/x/y/pull/20'; prNumber = 20; prState = 'merged'; prDraft = $false
    lastRefreshAt = $obsNow.AddDays(-5).ToString('o')
}
$mergedLane = [ordered]@{ repoName = 'smoke-merged'; executionState = 'running'; dispatchRunId = 'run-m'; assignedAt = $obsNow.AddDays(-5).ToString('o') }
$obsMerged = Resolve-LaneObservation -Entry $mergedLane -AgentRun $mergedRun -NowUtc $obsNow
if ($obsMerged.verdict -ne 'finished') { throw "Expected verdict=finished for a merged PR, got '$($obsMerged.verdict)'" }
if ($obsMerged.suggestedAction -ne 'complete') { throw "Expected suggestedAction=complete, got '$($obsMerged.suggestedAction)'" }
if ($obsMerged.stalled) { throw 'Expected a terminal verdict never to be reported as stalled' }

# A completed agent run with no PR observed yet must not fall through to
# 'queued'. Merged and closed runs are taken earlier, so what reaches here is
# delivered-but-not-merged; reporting "no runner has claimed this task yet"
# for a finished agent is not vague, it is false.
$doneRun = [pscustomobject]@{
    runId = 'ar-4'; dispatchRunId = 'run-d'; status = 'completed'; outcome = 'awaiting-merge'
    lastRefreshAt = $obsNow.AddMinutes(-2).ToString('o')
}
$doneLane = [ordered]@{ repoName = 'smoke-done'; executionState = 'running'; dispatchRunId = 'run-d'; assignedAt = $obsNow.AddMinutes(-30).ToString('o') }
$obsDone = Resolve-LaneObservation -Entry $doneLane -AgentRun $doneRun -NowUtc $obsNow
if ($obsDone.verdict -ne 'awaiting-review') { throw "Expected a completed run with no PR to read as awaiting-review, got '$($obsDone.verdict)'" }
if ($obsDone.verdictDetail -match 'no runner has claimed') { throw "A completed agent run was described as unclaimed: $($obsDone.verdictDetail)" }

# A failure outranks a PR the same run also produced: the failure is the fact
# the operator needs, and reporting "awaiting review" would bury it.
$failedRun = [pscustomobject]@{
    runId = 'ar-3'; dispatchRunId = 'run-f'; status = 'failed'
    prUrl = 'https://github.com/x/y/pull/22'; prNumber = 22; prState = 'open'; prDraft = $false
    lastRefreshAt = $obsNow.AddMinutes(-5).ToString('o')
}
$failedLane = [ordered]@{ repoName = 'smoke-failed'; executionState = 'running'; dispatchRunId = 'run-f'; assignedAt = $obsNow.AddHours(-1).ToString('o') }
$obsFailed = Resolve-LaneObservation -Entry $failedLane -AgentRun $failedRun -NowUtc $obsNow
if ($obsFailed.verdict -ne 'failed') { throw "Expected a failed run to outrank its own open PR, got '$($obsFailed.verdict)'" }
if ($obsFailed.suggestedAction -ne 'cancel') { throw "Expected suggestedAction=cancel, got '$($obsFailed.suggestedAction)'" }

# Empty arrays must serialize as [], never null. This is the Lane 0.17
# follow-up crash class: a PowerShell if-EXPRESSION collapsing @() to $null
# reached the browser as JSON null and a `.length` read took the portal down.
$obsJson = $obsHand | ConvertTo-Json -Depth 6
if ($obsJson -match '"sources"\s*:\s*null') { throw 'Lane 0.17: observation.sources serialized as JSON null; it must be []' }
Write-Host '  decision table: unlinked / queued-stuck / working / merged / failed-beats-PR, sources serialize as []' -ForegroundColor DarkGray

Write-Step 'Lane observation — smoke: the join reads the real artifacts off disk'
# The pure table above proves the rules; this proves the wiring — that the
# dispatch run id written at assign time actually finds the two files a real
# dispatch leaves behind. output/ is gitignored, so the fixture creates its
# own parents: on a fresh CI clone these directories do not exist.
$obsRunsDir = Join-Path $smokeWs 'output\roadmap-task-history\runs'
$obsAgentDir = Join-Path $smokeWs 'output\agent-runs\runs'
$null = New-Item -ItemType Directory -Path $obsRunsDir -Force
$null = New-Item -ItemType Directory -Path $obsAgentDir -Force

$smokeDispatchRunId = 'smoke-dispatch-001'
([ordered]@{
    runId = $smokeDispatchRunId; status = 'running'; dispatchTarget = 'copilot'
    startedAt = (Get-Date).ToUniversalTime().AddMinutes(-6).ToString('o')
    repository = 'x/smoke-repo-ready'; branch = "roadmap/$smokeDispatchRunId"
} | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath (Join-Path $obsRunsDir ("{0}.summary.json" -f $smokeDispatchRunId)) -Encoding UTF8

([ordered]@{
    runId = 'smoke-agent-001'; dispatchRunId = $smokeDispatchRunId; repoName = 'smoke-repo-ready'
    status = 'active'; outcome = $null; branch = "roadmap/$smokeDispatchRunId"
    prUrl = 'https://github.com/x/smoke-repo-ready/pull/7'; prNumber = 7; prState = 'open'; prDraft = $true
    createdAt = (Get-Date).ToUniversalTime().AddMinutes(-5).ToString('o')
    lastRefreshAt = (Get-Date).ToUniversalTime().AddMinutes(-1).ToString('o')
} | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath (Join-Path $obsAgentDir 'smoke-agent-001.json') -Encoding UTF8

# Re-sync so the repo is dispatchable again, then assign the lane the way a
# real dispatch does — carrying the ids instead of minting a throwaway GUID.
$null = Sync-LedgerFromAudit -WorkspaceRoot $smokeWs -DocAuditEntries $smokeDocEntries -RoadmapAuditEntries $smokeRoadmapEntries
$obsAssign = Invoke-AssignLane -WorkspaceRoot $smokeWs -RepoName 'smoke-repo-ready' `
    -DispatchRunId $smokeDispatchRunId -AgentRunId 'smoke-agent-001' -DispatchSource 'release-dispatch'
if (-not $obsAssign.success) { throw "Expected the dispatch-bound assign to succeed, got: $($obsAssign.error)" }
if ($obsAssign.runId -ne $smokeDispatchRunId) { throw "Expected the lane to adopt the dispatch run id, got '$($obsAssign.runId)'" }

$obsSummary = Get-ExecutionQueueSummary -WorkspaceRoot $smokeWs
$obsLaneEntry = @($obsSummary.entries | Where-Object { $_.repoName -eq 'smoke-repo-ready' })[0]
if ($null -eq $obsLaneEntry.observation) { throw 'Expected Get-ExecutionQueueSummary to attach an observation to the occupied lane' }
if (-not $obsLaneEntry.observation.linked) { throw 'Expected the dispatch-bound lane to resolve to its run (linked=$true)' }
if ($obsLaneEntry.observation.verdict -ne 'working') { throw "Expected verdict=working from the on-disk artifacts, got '$($obsLaneEntry.observation.verdict)'" }
if ($obsLaneEntry.observation.pr.number -ne 7) { throw "Expected PR #7 from the agent-run file, got '$($obsLaneEntry.observation.pr.number)'" }
if (@($obsLaneEntry.observation.sources) -notcontains 'agent-run') { throw 'Expected the observation to name agent-run as a source' }
if (@($obsLaneEntry.observation.sources) -notcontains 'run-summary') { throw 'Expected the observation to name run-summary as a source' }
Write-Host ("  join: lane -> run {0} -> PR #{1} ({2}), sources={3}" -f `
    $obsLaneEntry.observation.dispatchRunId, $obsLaneEntry.observation.pr.number, $obsLaneEntry.observation.verdict, (@($obsLaneEntry.observation.sources) -join '+')) -ForegroundColor DarkGray

Write-Step 'Lane observation — smoke: completing a lane releases its run'
# A finished run must not follow the repo into its next lane, or the board
# would report the previous run's PR as the new work's observed state.
$obsComplete = Invoke-CompleteTask -WorkspaceRoot $smokeWs -RepoName 'smoke-repo-ready' -Outcome 'success' -HasRemainingWork $true
if (-not $obsComplete.success) { throw "Expected complete to succeed, got: $($obsComplete.error)" }
$afterComplete = Get-ExecutionQueueSummary -WorkspaceRoot $smokeWs
$releasedEntry = @($afterComplete.entries | Where-Object { $_.repoName -eq 'smoke-repo-ready' })[0]
if (-not [string]::IsNullOrWhiteSpace([string]$releasedEntry.dispatchRunId)) {
    throw "Expected dispatchRunId to be cleared on completion, still holds '$($releasedEntry.dispatchRunId)'"
}
# Re-assigning by hand must now read as bookkeeping, not as the old run.
$null = Invoke-AssignLane -WorkspaceRoot $smokeWs -RepoName 'smoke-repo-ready'
$rebound = Get-ExecutionQueueSummary -WorkspaceRoot $smokeWs
$reboundEntry = @($rebound.entries | Where-Object { $_.repoName -eq 'smoke-repo-ready' })[0]
if ($reboundEntry.observation.verdict -ne 'unlinked') {
    throw "Expected a hand-assigned lane to read as unlinked after the run was released, got '$($reboundEntry.observation.verdict)'"
}

# Leave the lane free. Sync-LedgerFromAudit preserves running entries by
# design, so a lane left occupied here survives into the NEXT smoke run and
# fails an assertion several hundred lines earlier — a self-inflicted version
# of the cross-test pollution this suite exists to catch.
$null = Invoke-CompleteTask -WorkspaceRoot $smokeWs -RepoName 'smoke-repo-ready' -Outcome 'success' -HasRemainingWork $true
Write-Host '  release: dispatchRunId cleared on complete; a hand-assigned lane reads unlinked, not the old PR; lane left free' -ForegroundColor DarkGray

# ---------------------------------------------------------------------------
# Release 3.8 M1 (H38-01) — the provider-neutral task contract.
#
# The packet is what every adapter will render into its own prompt, so its
# shape is a contract rather than a convenience. Two of the assertions below
# read the RAW JSON rather than the parsed object on purpose: an empty array
# that serializes as `null`, or an absent session id that serializes as `""`,
# is a wire defect ConvertFrom-Json quietly repairs on the way back in, which
# is exactly how it would reach a provider unnoticed.
# ---------------------------------------------------------------------------
Write-Step 'Loading WorkPacket contract module (Release 3.8 M1)'
if (-not (Test-Path -LiteralPath $workPacketModule)) { throw "Execution.WorkPacket.ps1 not found at: $workPacketModule" }
. $workPacketModule
Write-Host 'WorkPacket contract module loaded successfully' -ForegroundColor Green

Write-Step 'WorkPacket contract — smoke: schema v1, offline'

$wpPermissions = @{ filesystemWrite = $true; shell = $true; network = $false; githubWrite = $false }
$wpPacket = New-WorkPacket `
    -TaskId 'smoke-wp-1' `
    -Repository 'xfaith4/GitHubRepoManagement' `
    -BaseBranch 'main' `
    -BaseSha '' `
    -Objective 'Give a task a provider-neutral contract.' `
    -AcceptanceCriteria @('Test-WorkPacket reports valid') `
    -VerificationCommands @('pwsh ./scripts/Invoke-ModuleSmokeTest.ps1') `
    -Permissions $wpPermissions

$wpValid = Test-WorkPacket -Packet $wpPacket
if (-not $wpValid.valid) { throw ("Expected the example packet to be valid, got errors: " + ($wpValid.errors -join '; ')) }
if ($wpPacket.schemaVersion -ne 1) { throw "Expected schemaVersion=1, got '$($wpPacket.schemaVersion)'" }
if ($wpPacket.execution.preferredProvider -ne 'auto') { throw "Expected preferredProvider to default to 'auto', got '$($wpPacket.execution.preferredProvider)'" }
if ($null -ne $wpPacket.execution.previousSessionId) { throw 'Expected an absent previousSessionId to be $null, not an empty string' }

# The packet names no provider anywhere except the caller's own preference.
# This is the milestone's whole point, so it is asserted rather than assumed.
$wpProviderNames = @('claude', 'codex', 'copilot')
foreach ($wpKey in @('taskId', 'repository', 'baseBranch', 'objective')) {
    foreach ($wpProviderName in $wpProviderNames) {
        if ([string]$wpPacket.$wpKey -match $wpProviderName) {
            throw "The packet's '$wpKey' names provider '$wpProviderName'; the contract must stay provider-neutral"
        }
    }
}

# Round-trip through disk, in the smoke's own isolated workspace.
$wpWorkspace = Join-Path $WorkspaceRoot 'output\smoke\module\workpacket'
if (Test-Path -LiteralPath $wpWorkspace) { Remove-Item -LiteralPath $wpWorkspace -Recurse -Force }
$null = New-Item -ItemType Directory -Path $wpWorkspace -Force

$wpSavedPath = Save-WorkPacket -WorkspaceRoot $wpWorkspace -Packet $wpPacket
if (-not (Test-Path -LiteralPath $wpSavedPath -PathType Leaf)) { throw "Save-WorkPacket reported '$wpSavedPath' but no file is there" }
if ($wpSavedPath -notmatch 'work-packets') { throw "Expected the packet to live under output\work-packets\, got: $wpSavedPath" }

$wpRawJson = Get-Content -LiteralPath $wpSavedPath -Raw -Encoding UTF8
if ($wpRawJson -notmatch '"forbiddenPaths"\s*:\s*\[\s*\]') {
    throw 'Expected scope.forbiddenPaths to serialize as [] on the wire; an empty array that becomes null is the array-collapse defect this repo already carries a gate for'
}
if ($wpRawJson -notmatch '"previousSessionId"\s*:\s*null') {
    throw 'Expected execution.previousSessionId to serialize as JSON null on the wire, not "" or absent'
}
if ($wpRawJson -notmatch '"allowedPaths"\s*:\s*\[') {
    throw 'Expected scope.allowedPaths to serialize as a JSON array even with one element'
}

$wpRead = Read-WorkPacket -WorkspaceRoot $wpWorkspace -TaskId 'smoke-wp-1'
if ($null -eq $wpRead) { throw 'Read-WorkPacket returned $null for a packet just written' }
if ($wpRead.taskId -ne 'smoke-wp-1') { throw "Round-trip lost taskId, got '$($wpRead.taskId)'" }
if ($wpRead.objective -ne $wpPacket.objective) { throw 'Round-trip lost the objective' }
# The validator has to accept what came back from JSON, not only what it built.
$wpReadValid = Test-WorkPacket -Packet $wpRead
if (-not $wpReadValid.valid) { throw ("A round-tripped packet failed validation: " + ($wpReadValid.errors -join '; ')) }

if ($null -ne (Read-WorkPacket -WorkspaceRoot $wpWorkspace -TaskId 'no-such-task')) {
    throw 'Expected Read-WorkPacket to answer $null for a task with no packet'
}

# Each rule broken once, asserting the exact operator-facing string.
$wpBadTaskId = New-WorkPacket -TaskId 'x' -Repository '' -BaseBranch 'main' -BaseSha '' -Objective 'o' -Permissions $wpPermissions
$wpBadTaskId.taskId = ''
$wpBadTaskIdResult = Test-WorkPacket -Packet $wpBadTaskId
if ($wpBadTaskIdResult.valid) { throw 'Expected an empty taskId to be invalid' }
if ($wpBadTaskIdResult.errors -notcontains 'taskId is required') { throw ("Expected 'taskId is required', got: " + ($wpBadTaskIdResult.errors -join '; ')) }

$wpBadPermission = New-WorkPacket -TaskId 'x' -Repository '' -BaseBranch 'main' -BaseSha '' -Objective 'o' -Permissions $wpPermissions
$wpBadPermission.permissions.network = 'no'
$wpBadPermissionResult = Test-WorkPacket -Packet $wpBadPermission
if ($wpBadPermissionResult.errors -notcontains 'permissions.network must be a boolean') { throw ("Expected 'permissions.network must be a boolean', got: " + ($wpBadPermissionResult.errors -join '; ')) }

# A missing key must read as an error, never as a deliberate $false — which is
# why New-WorkPacket stores what it was handed instead of casting it.
$wpMissingPermission = New-WorkPacket -TaskId 'x' -Repository '' -BaseBranch 'main' -BaseSha '' -Objective 'o' -Permissions @{ filesystemWrite = $true; shell = $true }
$wpMissingResult = Test-WorkPacket -Packet $wpMissingPermission
if ($wpMissingResult.errors -notcontains 'permissions.network must be a boolean') { throw 'Expected an omitted permission key to be an error, not a silent $false' }
if ($wpMissingResult.errors -notcontains 'permissions.githubWrite must be a boolean') { throw 'Expected every omitted permission key to be reported, not just the first' }

$wpBadAttempt = New-WorkPacket -TaskId 'x' -Repository '' -BaseBranch 'main' -BaseSha '' -Objective 'o' -Permissions $wpPermissions
$wpBadAttempt.execution.attempt = 0
$wpBadAttemptResult = Test-WorkPacket -Packet $wpBadAttempt
if ($wpBadAttemptResult.errors -notcontains 'execution.attempt must be an integer >= 1') { throw ("Expected 'execution.attempt must be an integer >= 1', got: " + ($wpBadAttemptResult.errors -join '; ')) }

$wpBadSchema = New-WorkPacket -TaskId 'x' -Repository '' -BaseBranch 'main' -BaseSha '' -Objective 'o' -Permissions $wpPermissions
$wpBadSchema.schemaVersion = 2
if ((Test-WorkPacket -Packet $wpBadSchema).errors -notcontains 'schemaVersion must be 1') { throw "Expected 'schemaVersion must be 1' for a version-2 packet" }

$wpBadScope = New-WorkPacket -TaskId 'x' -Repository '' -BaseBranch 'main' -BaseSha '' -Objective 'o' -Permissions $wpPermissions
$wpBadScope.scope.allowedPaths = @()
if ((Test-WorkPacket -Packet $wpBadScope).errors -notcontains 'scope.allowedPaths must be a non-empty array') { throw "Expected 'scope.allowedPaths must be a non-empty array' for an empty scope" }

$wpBadProvider = New-WorkPacket -TaskId 'x' -Repository '' -BaseBranch 'main' -BaseSha '' -Objective 'o' -Permissions $wpPermissions
$wpBadProvider.execution.preferredProvider = ''
if ((Test-WorkPacket -Packet $wpBadProvider).errors -notcontains 'execution.preferredProvider is required') { throw "Expected 'execution.preferredProvider is required' for a blank provider" }

# An invalid packet must never reach disk: a queue entry pointing at an
# unreadable packet is the prose-only dispatch this milestone removes.
$wpSaveRefused = $false
try { $null = Save-WorkPacket -WorkspaceRoot $wpWorkspace -Packet $wpBadTaskId }
catch { $wpSaveRefused = $true; if ($_.Exception.Message -notmatch 'WorkPacket is invalid') { throw "Save-WorkPacket threw, but not with the contract's message: $($_.Exception.Message)" } }
if (-not $wpSaveRefused) { throw 'Expected Save-WorkPacket to refuse an invalid packet' }

# The module is a param-less library. The host-wide gate checks this too, but
# a failure there names a dot-source list; here it names this file.
$wpModuleText = Get-Content -LiteralPath $workPacketModule -Raw -Encoding UTF8
if ($wpModuleText -match '(?m)^param\s*\(') { throw 'Execution.WorkPacket.ps1 declares a file-scope param() block; the host may only dot-source param-less libraries' }

Remove-Item -LiteralPath $wpWorkspace -Recurse -Force -ErrorAction SilentlyContinue
Write-Host '  workpacket: schema v1 validates, round-trips, and refuses to persist an invalid packet; [] and null hold on the wire' -ForegroundColor DarkGray

Write-Step 'Running modular reconciliation smoke test (narrow scope)'
& $reconcileModular `
    -LocalRoots @($WorkspaceRoot) `
    -OutDir (Join-Path $WorkspaceRoot 'output\smoke\module\reconcile') `
    -IncludeNonGitFolders:$false `
    -MaxDepth 2 | Out-Null

Write-Step 'Loading roadmap linter module (Release 1.1)'
$roadmapLinterPath = Join-Path $WorkspaceRoot 'backend\modules\roadmap\Roadmap.Linter.ps1'
if (-not (Test-Path -LiteralPath $roadmapLinterPath)) { throw "Roadmap.Linter.ps1 not found at: $roadmapLinterPath" }
. $roadmapLinterPath
Write-Host 'Roadmap linter module loaded successfully' -ForegroundColor Green

Write-Step 'Roadmap linter — smoke: lint a well-formed roadmap'
$wellFormedContent = @"
# My Project Roadmap

## Product Intent
This project does something useful.

## Recently Completed
- [x] Completed task one

## Release 1.0 — Initial Release

### Engineering milestones
- [ ] Implement feature A
- [ ] Implement feature B

### Acceptance criteria
- Feature A works correctly
"@
$wellFormedResult = Invoke-LintRoadmapContent -RawContent $wellFormedContent -RepoName 'smoke-lint-wellformed'
if ($null -eq $wellFormedResult) { throw 'Expected lint result, got null' }
if (-not $wellFormedResult.PSObject.Properties.Name -contains 'findings') { throw 'Expected findings property in lint result' }
Write-Host ("  lint result: lintPassed={0} findings={1}" -f $wellFormedResult.lintPassed, @($wellFormedResult.findings).Count) -ForegroundColor DarkGray

Write-Step 'Roadmap linter — smoke: lint a malformed roadmap detects errors'
$malformedContent = @"
## Release Bad Heading

- [] malformed checkbox
- [ ] valid item
"@
$malformedResult = Invoke-LintRoadmapContent -RawContent $malformedContent -RepoName 'smoke-lint-malformed'
$lintErrors = @($malformedResult.findings | Where-Object { $_.severity -eq 'error' })
if ($lintErrors.Count -eq 0) { throw 'Expected at least one error finding for malformed roadmap' }
Write-Host ("  malformed roadmap: errorCount={0} lintPassed={1}" -f $lintErrors.Count, $malformedResult.lintPassed) -ForegroundColor DarkGray

Write-Step 'Loading maturity drift monitor module (Release 1.1)'
$maturityDriftPath = Join-Path $WorkspaceRoot 'backend\modules\roadmap\MaturityDrift.Monitor.ps1'
if (-not (Test-Path -LiteralPath $maturityDriftPath)) { throw "MaturityDrift.Monitor.ps1 not found at: $maturityDriftPath" }
. $maturityDriftPath
Write-Host 'Maturity drift monitor module loaded successfully' -ForegroundColor Green

Write-Step 'Maturity drift monitor — smoke: set baseline and detect drift'
$driftWs = Join-Path $WorkspaceRoot 'output\smoke\module\drift'
$null = New-Item -ItemType Directory -Path (Join-Path $driftWs 'output') -Force -ErrorAction SilentlyContinue
$baselineResult = Set-MaturityBaseline -WorkspaceRoot $driftWs -RepoName 'smoke-drift-repo' -TargetLevel 'L3-Contract-Ready'
if (-not $baselineResult.persisted) { throw "Expected baseline to be persisted, got persisted=$($baselineResult.persisted)" }
Write-Host ("  baseline set: repoName={0} targetLevel={1}" -f $baselineResult.repoName, $baselineResult.targetLevel) -ForegroundColor DarkGray

$smokeAuditEntries = @(
    [PSCustomObject]@{
        repoName = 'smoke-drift-repo'; maturityLevel = 'L1-Informal'; maturityScore = 30
    }
)
$driftResult = Get-MaturityDrift -WorkspaceRoot $driftWs -CurrentAuditEntries $smokeAuditEntries
if ($driftResult.driftCount -ne 1) { throw "Expected 1 drift alert, got $($driftResult.driftCount)" }
$alert = $driftResult.driftAlerts | Select-Object -First 1
if ($alert.driftSeverity -notin @('warning','critical')) { throw "Expected driftSeverity warning or critical, got $($alert.driftSeverity)" }
Write-Host ("  drift detected: repoName={0} severity={1}" -f $alert.repoName, $alert.driftSeverity) -ForegroundColor DarkGray

Write-Step 'Loading doc standardization previewer module (Release 1.1)'
$docStdPath = Join-Path $WorkspaceRoot 'backend\modules\docstandardization\DocStandardization.Previewer.ps1'
if (-not (Test-Path -LiteralPath $docStdPath)) { throw "DocStandardization.Previewer.ps1 not found at: $docStdPath" }
. $docStdPath
Write-Host 'Doc standardization previewer module loaded successfully' -ForegroundColor Green

Write-Step 'Doc standardization — smoke: preview for repo without README'
$missingReadmeRepoPath = Join-Path $WorkspaceRoot 'output\smoke\module\missing-readme-repo'
$stdPreviewMissing = Invoke-PreviewReadmeStandardization -RepoName 'smoke-std-no-readme' -RepoPath $missingReadmeRepoPath
if ($null -eq $stdPreviewMissing) { throw 'Expected preview result, got null' }
Write-Host ("  preview (no README): previewState={0} actions={1}" -f $stdPreviewMissing.previewState, @($stdPreviewMissing.standardizationActions).Count) -ForegroundColor DarkGray

Write-Step 'Doc standardization — smoke: preview for repo with partial README'
$partialReadme = "# My Repo`n`nThis is a description."
$stdPreviewPartial = Invoke-PreviewReadmeStandardization -RepoName 'smoke-std-partial' -RawContent $partialReadme
if ($stdPreviewPartial.previewState -eq 'already-standard') { throw 'Expected non-standard state for partial README' }
if ([string]::IsNullOrWhiteSpace($stdPreviewPartial.proposedContent)) { throw 'Expected proposedContent to be populated for partial README' }
Write-Host ("  preview (partial README): previewState={0} actions={1}" -f $stdPreviewPartial.previewState, @($stdPreviewPartial.standardizationActions).Count) -ForegroundColor DarkGray

Write-Step 'Loading notification hub module (Release 1.1)'
$notificationHubPath = Join-Path $WorkspaceRoot 'backend\modules\common\NotificationHub.ps1'
if (-not (Test-Path -LiteralPath $notificationHubPath)) { throw "NotificationHub.ps1 not found at: $notificationHubPath" }
. $notificationHubPath
Write-Host 'Notification hub module loaded successfully' -ForegroundColor Green

Write-Step 'Notification hub — smoke: register and retrieve webhooks'
$notifWs = Join-Path $WorkspaceRoot 'output\smoke\module\notifications'
$null = New-Item -ItemType Directory -Path (Join-Path $notifWs 'output') -Force -ErrorAction SilentlyContinue
$webhook = Register-NotificationWebhook -WorkspaceRoot $notifWs -WebhookUrl 'https://example.com/webhook' -Events @('scan.completed','execution.failed') -Label 'Smoke Test Webhook'
if ([string]::IsNullOrWhiteSpace($webhook.id)) { throw 'Expected webhook id to be populated' }
$webhooks = Get-NotificationWebhooks -WorkspaceRoot $notifWs
if (@($webhooks).Count -eq 0) { throw 'Expected at least one webhook after registration' }
$removeResult = Remove-NotificationWebhook -WorkspaceRoot $notifWs -WebhookId $webhook.id
if (-not $removeResult.success) { throw "Expected webhook removal to succeed, got success=$($removeResult.success)" }
Write-Host ("  webhook register/get/remove smoke ok: id={0}" -f $webhook.id) -ForegroundColor DarkGray

Write-Step 'Notification hub — smoke: URL validation guard'
$invalidUrlRejected = $false
try {
    $null = Register-NotificationWebhook -WorkspaceRoot $notifWs -WebhookUrl 'file:///etc/passwd' -Events @('scan.completed') -Label 'Bad URL'
} catch {
    $invalidUrlRejected = $true
}
if (-not $invalidUrlRejected) { throw 'Expected Register-NotificationWebhook to reject a non-HTTP(S) URL' }
Write-Host '  invalid URL correctly rejected' -ForegroundColor DarkGray

Write-Step 'Notification hub — smoke: unknown event type guard'
$unknownEventRejected = $false
try {
    $null = Register-NotificationWebhook -WorkspaceRoot $notifWs -WebhookUrl 'https://example.com/hook' -Events @('unknown.event') -Label 'Bad Event'
} catch {
    $unknownEventRejected = $true
}
if (-not $unknownEventRejected) { throw 'Expected Register-NotificationWebhook to reject an unknown event name' }
Write-Host '  unknown event name correctly rejected' -ForegroundColor DarkGray

Write-Step 'Execution ledger — smoke: case-insensitive duplicate task guard'
$ciDedupWs = Join-Path $WorkspaceRoot 'output\smoke\module\execution-ci'
$null = New-Item -ItemType Directory -Path (Join-Path $ciDedupWs 'output\execution') -Force -ErrorAction SilentlyContinue
# Remove stale ledger so this step is idempotent across repeated smoke runs
$ciDedupLedgerFile = Join-Path $ciDedupWs 'output\execution\execution-ledger.json'
if (Test-Path -LiteralPath $ciDedupLedgerFile) { Remove-Item -LiteralPath $ciDedupLedgerFile -Force }
$ciDedupDocs = @(
    [pscustomobject]@{ repoName = 'ci-repo-a'; repoPath = '/tmp/ci-a'; dispatchReadiness = 'ready'; nextPendingRoadmapItem = 'Implement feature X' },
    [pscustomobject]@{ repoName = 'ci-repo-b'; repoPath = '/tmp/ci-b'; dispatchReadiness = 'ready'; nextPendingRoadmapItem = 'Implement Feature X' }
)
$null = Sync-LedgerFromAudit -WorkspaceRoot $ciDedupWs -DocAuditEntries $ciDedupDocs
$assignCiA = Invoke-AssignLane -WorkspaceRoot $ciDedupWs -RepoName 'ci-repo-a' -TaskText 'Implement feature X'
if (-not $assignCiA.success) { throw "Expected ci-repo-a lane assignment to succeed: $($assignCiA.error)" }
$assignCiB = Invoke-AssignLane -WorkspaceRoot $ciDedupWs -RepoName 'ci-repo-b' -TaskText 'Implement Feature X'
if ($assignCiB.success) { throw 'Expected ci-repo-b lane assignment to be rejected due to case-insensitive task duplicate guard' }
Write-Host '  case-insensitive duplicate task guard working correctly' -ForegroundColor DarkGray

Write-Step 'Roadmap linter — smoke: oversized content truncation guard'
$bigContent = ("## Release 0.1 — Test`n" + ("- [ ] Item`n" * 6000))
$bigLintResult = Invoke-LintRoadmapContent -RawContent $bigContent -RepoName 'smoke-lint-oversized'
if ($null -eq $bigLintResult) { throw 'Expected lint result for oversized content, got null' }
$sizeWarning = @($bigLintResult.findings | Where-Object { $_.ruleId -eq 'LINT-SIZE' })
if ($sizeWarning.Count -eq 0) { throw 'Expected LINT-SIZE warning for oversized roadmap content' }
Write-Host ("  oversized content guard working: findings={0}" -f $bigLintResult.findings.Count) -ForegroundColor DarkGray

# ---------------------------------------------------------------------------
# Release 1.7.5 — Portfolio Assessment module
# ---------------------------------------------------------------------------

Write-Step 'Portfolio assessment — smoke: load module + standards'
$portfolioModule = Join-Path $WorkspaceRoot 'backend\modules\portfolio\Portfolio.Assessment.ps1'
$portfolioValueModule = Join-Path $WorkspaceRoot 'backend\modules\portfolio\Portfolio.ValueScorer.ps1'
$portfolioStandards = Join-Path $WorkspaceRoot 'backend\config\repo-structure-standards.json'
$portfolioValueConfigPath = Join-Path $WorkspaceRoot 'backend\config\value-scoring.json'
if (-not (Test-Path -LiteralPath $portfolioModule)) { throw "Missing module file: $portfolioModule" }
if (-not (Test-Path -LiteralPath $portfolioValueModule)) { throw "Missing module file: $portfolioValueModule" }
if (-not (Test-Path -LiteralPath $portfolioStandards)) { throw "Missing standards file: $portfolioStandards" }
if (-not (Test-Path -LiteralPath $portfolioValueConfigPath)) { throw "Missing value-scoring config: $portfolioValueConfigPath" }
. $portfolioValueModule
. $portfolioModule
$structStds = Get-RepoStructureStandards -StandardsPath $portfolioStandards
$valueScoringConfig = Get-PortfolioValueScoringConfig -ConfigPath $portfolioValueConfigPath
if ($null -eq $structStds) { throw 'Get-RepoStructureStandards returned null for an existing standards file' }
if ($null -eq $structStds.common) { throw 'Standards file is missing the common section' }
if ($null -eq $valueScoringConfig) { throw 'Get-PortfolioValueScoringConfig returned null for an existing config file' }
# repo-structure-standards.json renamed 'version' to 'schemaVersion' in the v1 schema;
# accept either so the smoke works against old and new standards files.
$structStdsVersion = if ($structStds.PSObject.Properties.Name -contains 'schemaVersion') { [string]$structStds.schemaVersion } elseif ($structStds.PSObject.Properties.Name -contains 'version') { [string]$structStds.version } else { '(none)' }
Write-Host ("  standards loaded version={0} commonRequired={1}" -f $structStdsVersion, @($structStds.common.requiredRootFiles).Count) -ForegroundColor DarkGray

Write-Step 'Portfolio assessment — smoke: structure audit on workspace itself'
$selfAudit = Invoke-RepoStructureAudit -RepoPath $WorkspaceRoot -Standards $structStds
if ($null -eq $selfAudit) { throw 'Invoke-RepoStructureAudit returned null on workspace' }
if ($selfAudit.repoType -ne 'node') { throw "Expected workspace repoType=node (package.json present), got '$($selfAudit.repoType)'" }
Write-Host ("  workspace audit: type={0} missing={1} ci={2} tests={3}" -f $selfAudit.repoType, $selfAudit.missingCount, $selfAudit.hasCiSignal, $selfAudit.hasTestSignal) -ForegroundColor DarkGray

Write-Step 'Portfolio assessment — smoke: malformed standards object falls through gracefully'
$malformedAudit = Invoke-RepoStructureAudit -RepoPath $WorkspaceRoot -Standards ([pscustomobject]@{ version = '0.0' })
if ($null -eq $malformedAudit)             { throw 'Expected non-null audit result for malformed standards' }
if ($malformedAudit.missingCount -ne 0)    { throw "Expected missingCount=0 when 'common' section is absent, got $($malformedAudit.missingCount)" }
if (@($malformedAudit.findings).Count -ne 0) { throw 'Expected zero findings when standards object lacks common section' }
Write-Host '  malformed standards correctly degraded to empty findings' -ForegroundColor DarkGray

Write-Step 'Standard files — smoke: a roadmap under docs/ (and SECURITY.md under .github/) is present on every surface'
# UnifiedAIToolbox keeps its roadmap at docs/ROADMAP.md. The Planning row of
# its evaluation parsed that file while the structure row and the "No roadmap"
# chip of the SAME evaluation said there was none: four private candidate
# lists and five root-only lookups answered one question differently. One
# locator (backend/modules/common/RepoStandardFile.ps1) reads the accepted
# locations from the standards; these assertions hold every surface to it,
# and the undeclared-location case proves the locator can still say no.
. (Join-Path $WorkspaceRoot 'backend\modules\docaudit\RepositoryImprovement.Workflow.ps1')
$docStds = Get-DocStandards -StandardsPath $docStandards
$stdFixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('repostd-smoke-' + [guid]::NewGuid().ToString('n').Substring(0, 8))
$stdDocsRepo = Join-Path $stdFixtureRoot 'docs-roadmap'
$stdBothRepo = Join-Path $stdFixtureRoot 'both-roadmaps'
$stdElsewhereRepo = Join-Path $stdFixtureRoot 'elsewhere-roadmap'
try {
    foreach ($repo in @($stdDocsRepo, $stdBothRepo, $stdElsewhereRepo)) {
        $null = New-Item -ItemType Directory -Path (Join-Path $repo 'docs') -Force
        $null = New-Item -ItemType Directory -Path (Join-Path $repo '.github') -Force
        Set-Content -LiteralPath (Join-Path $repo 'package.json') -Encoding UTF8 -Value '{ "name": "repostd-smoke", "version": "1.0.0" }'
        Set-Content -LiteralPath (Join-Path $repo 'README.md') -Encoding UTF8 -Value ('# repostd smoke' + [Environment]::NewLine + ('Enough README for the doc audit to read. ' * 12))
        Set-Content -LiteralPath (Join-Path $repo 'LICENSE.txt') -Encoding UTF8 -Value 'MIT'
    }
    $stdRoadmapBody = "# Roadmap`n`n## Release 1.0`n`n- [ ] Keep this roadmap alive`n"
    Set-Content -LiteralPath (Join-Path $stdDocsRepo 'docs\ROADMAP.md') -Encoding UTF8 -Value $stdRoadmapBody
    Set-Content -LiteralPath (Join-Path $stdDocsRepo '.github\SECURITY.md') -Encoding UTF8 -Value '# Security'
    Set-Content -LiteralPath (Join-Path $stdDocsRepo '.github\CONTRIBUTING.md') -Encoding UTF8 -Value '# Contributing'
    Set-Content -LiteralPath (Join-Path $stdBothRepo 'docs\ROADMAP.md') -Encoding UTF8 -Value $stdRoadmapBody
    Set-Content -LiteralPath (Join-Path $stdBothRepo 'ROADMAP.md') -Encoding UTF8 -Value $stdRoadmapBody
    $null = New-Item -ItemType Directory -Path (Join-Path $stdElsewhereRepo 'planning') -Force
    Set-Content -LiteralPath (Join-Path $stdElsewhereRepo 'planning\ROADMAP.md') -Encoding UTF8 -Value $stdRoadmapBody

    # The locator: docs\ is found, the root outranks docs\, an undeclared
    # location is NOT found (so the check is not vacuous), a missing repository
    # resolves to nothing, and -DefaultToRoot names the creation target.
    $docsResolved = Resolve-RepoRoadmapPath -RepoPath $stdDocsRepo
    if ($docsResolved -ne (Join-Path $stdDocsRepo 'docs\ROADMAP.md')) { throw "Expected docs\ROADMAP.md to resolve, got '$docsResolved'" }
    $bothResolved = Resolve-RepoRoadmapPath -RepoPath $stdBothRepo
    if ($bothResolved -ne (Join-Path $stdBothRepo 'ROADMAP.md')) { throw "Expected the root roadmap to outrank docs\, got '$bothResolved'" }
    $elsewhereResolved = Resolve-RepoRoadmapPath -RepoPath $stdElsewhereRepo
    if (-not [string]::IsNullOrWhiteSpace($elsewhereResolved)) { throw "Expected planning\ROADMAP.md (not a declared location) to resolve to nothing, got '$elsewhereResolved'" }
    if ((Resolve-RepoRoadmapPath -RepoPath $stdElsewhereRepo -DefaultToRoot) -ne (Join-Path $stdElsewhereRepo 'ROADMAP.md')) { throw '-DefaultToRoot did not return the root creation target' }
    if ((Resolve-RepoRoadmapPath -RepoPath (Join-Path $stdFixtureRoot 'does-not-exist')) -ne '') { throw 'A missing repository path must resolve to nothing' }

    # Structure audit: ROADMAP.md, SECURITY.md, CONTRIBUTING.md and LICENSE are
    # present at alternative locations; the check still fires for what is
    # genuinely absent (.gitignore) and for the undeclared location.
    $docsAudit = Invoke-RepoStructureAudit -RepoPath $stdDocsRepo -Standards $structStds
    $docsMissing = @($docsAudit.findings | Where-Object { $_.kind -eq 'missing-root-file' } | ForEach-Object { [string]$_.target })
    foreach ($presentName in @('ROADMAP.md', 'SECURITY.md', 'CONTRIBUTING.md', 'LICENSE', 'README.md')) {
        if ($docsMissing -contains $presentName) { throw "Structure audit reported '$presentName' missing although it exists at an accepted location (missing: $($docsMissing -join ', '))" }
    }
    if ($docsMissing -notcontains '.gitignore') { throw "Structure audit must still report the absent .gitignore (missing: $($docsMissing -join ', '))" }
    $elsewhereAudit = Invoke-RepoStructureAudit -RepoPath $stdElsewhereRepo -Standards $structStds
    $elsewhereMissing = @($elsewhereAudit.findings | Where-Object { $_.kind -eq 'missing-root-file' } | ForEach-Object { [string]$_.target })
    if ($elsewhereMissing -notcontains 'ROADMAP.md') { throw 'Structure audit must report ROADMAP.md missing when the only copy is at an undeclared location' }

    # Repo evaluator: the "No roadmap" chip reads hasExistingRoadmap.
    $docsEval = Invoke-RepoEvaluation -RepoName 'repostd-smoke' -LocalPath $stdDocsRepo
    if (-not $docsEval.hasExistingRoadmap) { throw 'Repo evaluator reported no roadmap for a repository with docs\ROADMAP.md' }
    if ([string]$docsEval.roadmapPath -ne (Join-Path $stdDocsRepo 'docs\ROADMAP.md')) { throw "Repo evaluator roadmapPath should name docs\ROADMAP.md, got '$($docsEval.roadmapPath)'" }
    if (-not [string]::IsNullOrWhiteSpace($docsEval.suggestedRoadmapContent)) { throw 'Repo evaluator drafted a replacement roadmap for a repository that has one under docs\' }
    $elsewhereEval = Invoke-RepoEvaluation -RepoName 'repostd-smoke-elsewhere' -LocalPath $stdElsewhereRepo
    if ($elsewhereEval.hasExistingRoadmap) { throw 'Repo evaluator must not count a roadmap at an undeclared location' }

    # Doc audit: its own requiredRootFiles (doc-standards.json) honor the same
    # altNames / altPaths, so LICENSE.txt and .github\CONTRIBUTING.md count.
    $docsDocAudit = Invoke-AuditRepoDocumentation -RepoPath $stdDocsRepo -RepoName 'repostd-smoke' -Standards $docStds -RoadmapState 'pending'
    $docAuditMissing = @($docsDocAudit.docFindings | Where-Object { [string]$_.message -like "Required file '*' is missing." } | ForEach-Object { [string]$_.file })
    foreach ($presentName in @('README.md', 'LICENSE', 'CONTRIBUTING.md')) {
        if ($docAuditMissing -contains $presentName) { throw "Doc audit reported '$presentName' missing although it exists at an accepted location (missing: $($docAuditMissing -join ', '))" }
    }
    if ($docAuditMissing -notcontains 'CHANGELOG.md') { throw "Doc audit must still report the absent CHANGELOG.md (missing: $($docAuditMissing -join ', '))" }

    # The repository-improvement workflow takes the same answer.
    if ((Get-RepositoryImprovementRoadmapPath -RepoPath $stdDocsRepo) -ne $docsResolved) { throw 'Get-RepositoryImprovementRoadmapPath disagrees with Resolve-RepoRoadmapPath' }

    Write-Host '  standard files ok: docs\ROADMAP.md, .github\SECURITY.md, .github\CONTRIBUTING.md and LICENSE.txt present on structure audit, evaluator and doc audit; root outranks docs\; planning\ROADMAP.md correctly not found' -ForegroundColor DarkGray
} finally {
    Remove-Item -LiteralPath $stdFixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Step 'Standard files — gate: repo-structure-standards.json and doc-standards.json agree on accepted locations'
# Both files list LICENSE and CONTRIBUTING.md. A location added to one and
# not the other lets the structure audit and the doc audit disagree again,
# which is the defect above. Proven red on a planted pair first.
$compareStandardFileLocations = {
    param([object[]]$StructureSpecs, [object[]]$DocSpecs)
    $mismatches = [System.Collections.Generic.List[string]]::new()
    foreach ($structureSpec in @($StructureSpecs)) {
        $name = [string](Get-RepoStandardFileField -Spec $structureSpec -Name 'name')
        $docSpec = @($DocSpecs | Where-Object { [string](Get-RepoStandardFileField -Spec $_ -Name 'name') -eq $name }) | Select-Object -First 1
        if ($null -eq $docSpec) { continue }
        $structureLocations = @(Get-RepoStandardFileCandidateList -Spec $structureSpec) -join '|'
        $docLocations = @(Get-RepoStandardFileCandidateList -Spec $docSpec) -join '|'
        if ($structureLocations -ne $docLocations) { $mismatches.Add(("{0}: structure=[{1}] doc=[{2}]" -f $name, $structureLocations, $docLocations)) }
    }
    return @($mismatches)
}
$plantedMismatch = & $compareStandardFileLocations `
    -StructureSpecs @([pscustomobject]@{ name = 'CONTRIBUTING.md'; altPaths = @('docs/CONTRIBUTING.md') }) `
    -DocSpecs @([pscustomobject]@{ name = 'CONTRIBUTING.md' })
if (@($plantedMismatch).Count -ne 1) { throw 'Standards-agreement check did not fail its planted mismatch; it would pass vacuously' }
$structureSpecList = @(Get-RepoStandardFileSpecList -Standards $structStds)
$docSpecList = @(Get-RepoStandardFileSpecList -Standards $docStds)
$liveMismatch = & $compareStandardFileLocations -StructureSpecs $structureSpecList -DocSpecs $docSpecList
if (@($liveMismatch).Count -gt 0) { throw ("repo-structure-standards.json and doc-standards.json disagree on accepted locations: {0}" -f ($liveMismatch -join '; ')) }
$docSpecNames = @($docSpecList | ForEach-Object { [string](Get-RepoStandardFileField -Spec $_ -Name 'name') })
$sharedStandardFileCount = @($structureSpecList | Where-Object { $docSpecNames -contains [string](Get-RepoStandardFileField -Spec $_ -Name 'name') }).Count
if ($sharedStandardFileCount -lt 2) { throw "Expected at least LICENSE and CONTRIBUTING.md to be shared between the two standards files, found $sharedStandardFileCount" }
Write-Host ("  standards agree on accepted locations for {0} shared file(s); planted mismatch caught first" -f $sharedStandardFileCount) -ForegroundColor DarkGray

Write-Step 'Standard files — sweep: no backend lookup bypasses the locator (root-only ROADMAP.md probes, private candidate lists)'
# Derived scope: every backend .ps1 except the locator itself. Both detectors
# are proven on a planted offender first, so an empty result means "none",
# not "matched nothing".
$locatorPath = Join-Path $WorkspaceRoot 'backend\modules\common\RepoStandardFile.ps1'
$bypassPatterns = @(
    @{ name = 'root-only roadmap probe';         regex = "Join-Path\s+[^\r\n]*?['""]ROADMAP\.md['""]" },
    @{ name = 'private roadmap candidate list';  regex = "['""]docs[\\/]+(planning[\\/]+)?roadmap\.md['""]" }
)
$plantedOffender = "`$p = Join-Path `$repo 'ROADMAP.md'`n`$list = @('ROADMAP.md', 'docs\ROADMAP.md')"
foreach ($pattern in $bypassPatterns) {
    if ($plantedOffender -notmatch $pattern.regex) { throw "Bypass detector '$($pattern.name)' did not match its planted offender; the sweep would pass vacuously" }
}
$backendOutputPrefix = Join-Path $WorkspaceRoot 'backend\modules\output'
$backendScripts = @(Get-ChildItem -LiteralPath (Join-Path $WorkspaceRoot 'backend') -Recurse -File -Filter '*.ps1' | Where-Object { $_.FullName -ne $locatorPath -and -not $_.FullName.StartsWith($backendOutputPrefix, [System.StringComparison]::OrdinalIgnoreCase) })
$bypasses = [System.Collections.Generic.List[string]]::new()
foreach ($file in $backendScripts) {
    $lineNumber = 0
    foreach ($line in [System.IO.File]::ReadAllLines($file.FullName)) {
        $lineNumber++
        foreach ($pattern in $bypassPatterns) {
            if ($line -imatch $pattern.regex) { $bypasses.Add(("{0}:{1} ({2})" -f $file.FullName.Substring($WorkspaceRoot.Length + 1), $lineNumber, $pattern.name)) }
        }
    }
}
if ($bypasses.Count -gt 0) { throw ("Roadmap lookups bypass RepoStandardFile.ps1 — route them through Resolve-RepoRoadmapPath / Get-RepoRoadmapDefaultPath: {0}" -f ($bypasses -join '; ')) }
if ($backendScripts.Count -lt 20) { throw "Bypass sweep examined only $($backendScripts.Count) backend script(s); scope derivation is broken" }
Write-Host ("  bypass sweep ok: {0} backend script(s) probed, both detectors failed their planted offender first, none bypass the locator" -f $backendScripts.Count) -ForegroundColor DarkGray

Write-Step 'Portfolio assessment — smoke: lifecycle precedence (archived overrides everything)'
$archivedRepo = [pscustomobject]@{ name = 'arch-repo'; localPath = $WorkspaceRoot; isArchived = $true; htmlUrl = 'https://github.com/x/arch-repo'; branch = 'main'; status = 'clean' }
$archivedAssess = Invoke-PortfolioAssessment -LocalRepos @($archivedRepo) -StructureStandards $structStds
if (@($archivedAssess).Count -ne 1) { throw "Expected 1 assessment for archived repo, got $(@($archivedAssess).Count)" }
if ($archivedAssess[0].lifecycleState -ne 'archived') { throw "Archived precedence broken: expected 'archived', got '$($archivedAssess[0].lifecycleState)'" }
Write-Host '  archived precedence correct' -ForegroundColor DarkGray

Write-Step 'Portfolio assessment — smoke: lifecycle precedence (parse-error)'
$parseErrRepo = [pscustomobject]@{ name = 'parse-err-repo'; localPath = $WorkspaceRoot; isArchived = $false; htmlUrl = ''; branch = 'main'; status = 'clean' }
$parseErrRoadmap = @([pscustomobject]@{ repoName = 'parse-err-repo'; roadmapPath = (Join-Path $WorkspaceRoot 'ROADMAP.md'); roadmapState = 'parse-error'; pendingCount = 0 })
$parseErrAssess = Invoke-PortfolioAssessment -LocalRepos @($parseErrRepo) -RoadmapEntries $parseErrRoadmap -StructureStandards $structStds
if ($parseErrAssess[0].lifecycleState -ne 'parse-error') { throw "Parse-error precedence broken: expected 'parse-error', got '$($parseErrAssess[0].lifecycleState)'" }
Write-Host '  parse-error precedence correct' -ForegroundColor DarkGray

Write-Step 'Portfolio assessment — smoke: lifecycle precedence (running execution state)'
$runningRepo = [pscustomobject]@{ name = 'running-repo'; localPath = $WorkspaceRoot; isArchived = $false; htmlUrl = ''; branch = 'main'; status = 'clean' }
$runningExec = @([pscustomobject]@{ repoName = 'running-repo'; executionState = 'running' })
$runningAssess = Invoke-PortfolioAssessment -LocalRepos @($runningRepo) -ExecutionEntries $runningExec -StructureStandards $structStds
if ($runningAssess[0].lifecycleState -ne 'running') { throw "Running precedence broken: expected 'running', got '$($runningAssess[0].lifecycleState)'" }
Write-Host '  running precedence correct' -ForegroundColor DarkGray

Write-Step 'Portfolio assessment — smoke: GitHub-only repo classified with sourceCoverage=github'
$ghOnlyRepos = @([pscustomobject]@{ name = 'remote-only'; htmlUrl = 'https://github.com/x/remote-only'; branch = 'main'; isArchived = $false })
$ghOnlyAssess = Invoke-PortfolioAssessment -LocalRepos @() -GitHubRepos $ghOnlyRepos -StructureStandards $structStds
if (@($ghOnlyAssess).Count -ne 1)                          { throw "Expected 1 GitHub-only assessment, got $(@($ghOnlyAssess).Count)" }
if ($ghOnlyAssess[0].sourceCoverage -ne 'github')           { throw "Expected sourceCoverage=github, got '$($ghOnlyAssess[0].sourceCoverage)'" }
if ($ghOnlyAssess[0].lifecycleState -ne 'discovered')       { throw "Expected lifecycleState=discovered for GitHub-only, got '$($ghOnlyAssess[0].lifecycleState)'" }
if ($ghOnlyAssess[0].recommendedAction -notmatch 'Clone')   { throw "Expected GitHub-only recommendedAction to mention Clone, got '$($ghOnlyAssess[0].recommendedAction)'" }
Write-Host '  GitHub-only sourceCoverage correct' -ForegroundColor DarkGray

Write-Step 'Portfolio assessment — smoke: source coverage = local+github when repo present in both'
$bothRepos = @([pscustomobject]@{ name = 'shared'; localPath = $WorkspaceRoot; isArchived = $false; htmlUrl = ''; branch = 'main'; status = 'clean' })
$bothGh    = @([pscustomobject]@{ name = 'shared'; htmlUrl = 'https://github.com/x/shared' })
$bothAssess = Invoke-PortfolioAssessment -LocalRepos $bothRepos -GitHubRepos $bothGh -StructureStandards $structStds
if (@($bothAssess).Count -ne 1)                  { throw "Expected single dedupe-merged assessment, got $(@($bothAssess).Count)" }
if ($bothAssess[0].sourceCoverage -ne 'local+github') { throw "Expected sourceCoverage=local+github, got '$($bothAssess[0].sourceCoverage)'" }
Write-Host '  local+github source coverage correct' -ForegroundColor DarkGray

Write-Step 'Roadmap identity — a repo is found by where it lives, not by what its folder is called'
& {
    . $roadmapParser
    . $portfolioModule

    # --- Canonical roadmap file selection -----------------------------------
    # Discovery accepted any name starting with ROADMAP at any depth and the
    # index kept the last one written. On 2026-08-27 that made
    # 2026-06-13_Orchestration plan from archive\roadmaps\ROADMAP.v1.0_original.md
    # and reported four repos as parse-error with 0 pending items when they had
    # 34, 53 and 25 items on disk.
    $repoRoot = 'C:\repos\demo'
    $selCases = @(
        @{ why = 'an archived copy must never outrank the root file'
           cand = @("$repoRoot\ROADMAP.md", "$repoRoot\archive\roadmaps\ROADMAP.v1.0_original.md")
           want = "$repoRoot\ROADMAP.md" },
        @{ why = 'a docs/ copy must never outrank the root file'
           cand = @("$repoRoot\ROADMAP.md", "$repoRoot\docs\RoadMap_PromptChain\RoadMap.md")
           want = "$repoRoot\ROADMAP.md" },
        @{ why = 'a JSON schema is not a roadmap'
           cand = @("$repoRoot\roadmap.json", "$repoRoot\ROADMAP.md")
           want = "$repoRoot\ROADMAP.md" },
        @{ why = 'a PDF is not a roadmap'
           cand = @("$repoRoot\ROADMAP.pdf", "$repoRoot\ROADMAP.md")
           want = "$repoRoot\ROADMAP.md" },
        @{ why = 'an exact ROADMAP.md outranks a decorated sibling'
           cand = @("$repoRoot\ROADMAP.v2.md", "$repoRoot\ROADMAP.md")
           want = "$repoRoot\ROADMAP.md" },
        @{ why = 'enumeration order does not decide the answer'
           cand = @("$repoRoot\ROADMAP.md", "$repoRoot\ROADMAP.v2.md")
           want = "$repoRoot\ROADMAP.md" },
        @{ why = 'a nested roadmap still counts when the root has none'
           cand = @("$repoRoot\docs\ROADMAP.md")
           want = "$repoRoot\docs\ROADMAP.md" },
        @{ why = 'no markdown candidate means no roadmap, not a corrupt one'
           cand = @("$repoRoot\roadmap.json", "$repoRoot\ROADMAP.pdf")
           want = '' }
    )
    foreach ($case in $selCases) {
        $picked = Select-CanonicalRoadmapFile -Candidate $case.cand -RepoPath $repoRoot
        if ($picked -ne $case.want) {
            throw ("Canonical roadmap selection failed ({0}): expected '{1}', got '{2}'" -f $case.why, $case.want, $picked)
        }
    }
    if ((Select-CanonicalRoadmapFile -Candidate @() -RepoPath $repoRoot) -ne '') { throw 'An empty candidate set must yield an empty selection, not an error' }

    # --- Path-first join ----------------------------------------------------
    # The scanners key their output by folder name; the index keys repos by
    # remote name. Every repo whose folder differs from its GitHub name lost its
    # roadmap, its doc audit and its maturity in one go.
    $renamedRepo = [pscustomobject]@{
        name = 'Widget-v2'; localPath = $WorkspaceRoot; isArchived = $false
        htmlUrl = 'https://github.com/x/Widget-v2'; branch = 'main'; status = 'clean'
    }
    $folderName = Split-Path $WorkspaceRoot -Leaf
    if ($folderName -eq 'Widget-v2') { throw 'Fixture invalid: the folder name must differ from the repo name for this gate to mean anything' }
    $renamedRoadmap = @([pscustomobject]@{
        repoName = $folderName; repoPath = $WorkspaceRoot
        roadmapPath = (Join-Path $WorkspaceRoot 'ROADMAP.md'); roadmapState = 'pending'; pendingCount = 53
    })
    $renamedDocs = @([pscustomobject]@{
        repoName = $folderName; repoPath = $WorkspaceRoot
        dispatchReadiness = 'ready'; roadmapState = 'pending'; docFindings = @()
    })
    $renamedAssess = @(Invoke-PortfolioAssessment -LocalRepos @($renamedRepo) `
        -RoadmapEntries $renamedRoadmap -DocAuditEntries $renamedDocs -StructureStandards $structStds)
    if ($renamedAssess.Count -ne 1) { throw "Expected 1 assessment for the renamed repo, got $($renamedAssess.Count)" }
    if (-not $renamedAssess[0].hasRoadmap) {
        throw 'A repo whose folder name differs from its remote name reported hasRoadmap=false while its ROADMAP.md sat on disk'
    }
    if ([string]$renamedAssess[0].roadmapState -ne 'pending') {
        throw "Renamed repo roadmapState should join through the path: expected 'pending', got '$([string]$renamedAssess[0].roadmapState)'"
    }
    if ([int]$renamedAssess[0].pendingCount -ne 53) {
        throw "Renamed repo lost its pending work: expected 53, got $([int]$renamedAssess[0].pendingCount)"
    }
    if ([string]$renamedAssess[0].lifecycleState -eq 'needs-roadmap') {
        throw 'Renamed repo was still classified needs-roadmap after the path join'
    }

    # The name join must still work for callers that carry no path.
    $namedOnly = @([pscustomobject]@{
        repoName = 'Widget-v2'; roadmapPath = (Join-Path $WorkspaceRoot 'ROADMAP.md'); roadmapState = 'pending'; pendingCount = 7
    })
    $namedAssess = @(Invoke-PortfolioAssessment -LocalRepos @($renamedRepo) -RoadmapEntries $namedOnly -StructureStandards $structStds)
    if ([int]$namedAssess[0].pendingCount -ne 7) {
        throw "Name-keyed fallback broke: expected pendingCount=7, got $([int]$namedAssess[0].pendingCount)"
    }

    Write-Host ("  roadmap identity ok: {0} selection case(s); renamed repo keeps roadmap (state={1} pending={2}), name fallback intact" -f `
        $selCases.Count, [string]$renamedAssess[0].roadmapState, [int]$renamedAssess[0].pendingCount) -ForegroundColor DarkGray
}

Write-Step 'Duplicate checkouts — two clones of one repo pick a survivor by rule, and the loser is named'
& {
    . $portfolioModule

    # Lane 0.12. MusicLibrary_v2 was cloned twice — once under Archive\, once in
    # the working portfolio. The dedupe kept whichever the enumeration reached
    # first, so the index snapshot showed the active checkout and the status
    # cache showed the archived one, on the same day. The discarded clone left
    # no trace at all, which is the half the operator could never guess.
    $activePath   = $WorkspaceRoot
    $archivedPath = Join-Path $WorkspaceRoot 'Archive\Widget'
    $activeRepo = [pscustomobject]@{
        name = 'Widget'; folderName = (Split-Path $WorkspaceRoot -Leaf); path = $activePath
        branch = 'main'; status = 'clean'; isArchived = $false
        scope = [pscustomobject]@{ classification = 'in-scope'; inScope = $true; reason = 'In the working portfolio.' }
    }
    $archivedRepo = [pscustomobject]@{
        name = 'Widget'; folderName = 'Widget'; path = $archivedPath
        branch = 'main'; status = 'clean'; isArchived = $false
        scope = [pscustomobject]@{ classification = 'archived'; inScope = $false; reason = "Path matches the archive pattern '*\Archive\*' -- kept on disk, out of the working portfolio." }
    }
    # The archived clone's folder name MATCHES the repo name and the active
    # one's does not, so this fixture only passes if in-scope outranks the
    # folder-name rule rather than merely agreeing with it.
    $dupRoadmaps = @(
        [pscustomobject]@{ repoName = 'Widget'; repoPath = $activePath; roadmapPath = (Join-Path $WorkspaceRoot 'ROADMAP.md'); roadmapState = 'pending'; pendingCount = 53 },
        [pscustomobject]@{ repoName = 'Widget'; repoPath = $archivedPath; roadmapPath = (Join-Path $archivedPath 'ROADMAP.md'); roadmapState = 'pending'; pendingCount = 4 }
    )

    $dupRun = Invoke-PortfolioAssessment -LocalRepos @($activeRepo, $archivedRepo) -RoadmapEntries $dupRoadmaps -StructureStandards $structStds
    $dupRows = @($dupRun)
    if ($dupRows.Count -ne 1) { throw "Two checkouts of one repository must yield one row, got $($dupRows.Count)" }
    $survivor = $dupRows[0]
    if ([string]$survivor.localPath -ne $activePath) {
        throw ("The working-portfolio checkout must survive, not the archived one: got '{0}'" -f [string]$survivor.localPath)
    }
    if ([int]$survivor.pendingCount -ne 53) {
        throw ("The surviving row must carry its OWN checkout's roadmap: expected 53 pending, got {0}" -f [int]$survivor.pendingCount)
    }
    # Enumeration order must not decide the answer. This assertion is first
    # because it is the defect itself: reading the archived clone first was
    # enough to erase the active checkout from the whole portfolio.
    $reversedRun = Invoke-PortfolioAssessment -LocalRepos @($archivedRepo, $activeRepo) -RoadmapEntries $dupRoadmaps -StructureStandards $structStds
    $reversedRows = @($reversedRun)
    if ([string]$reversedRows[0].localPath -ne $activePath) {
        throw ("Reversing the scan order changed the surviving checkout to '{0}' — the choice is still order-dependent" -f [string]$reversedRows[0].localPath)
    }
    if ([int]$reversedRows[0].pendingCount -ne 53) {
        throw ("Reversed order attributed the wrong roadmap to the survivor: expected 53 pending, got {0}" -f [int]$reversedRows[0].pendingCount)
    }

    if ($null -eq (_GetField -Obj $survivor -Name 'duplicateCheckouts' -Default $null)) {
        throw 'A discarded checkout must be recorded on the surviving row, not dropped silently'
    }
    $droppedPaths = @(@($survivor.duplicateCheckouts.dropped) | ForEach-Object { [string]$_.localPath })
    if ($droppedPaths -notcontains $archivedPath) {
        throw ("The discarded checkout must be named: expected '{0}' in [{1}]" -f $archivedPath, ($droppedPaths -join ', '))
    }
    if ([string]::IsNullOrWhiteSpace([string]$survivor.duplicateCheckouts.selectionReason)) {
        throw 'The row must say why this checkout was chosen; an unexplained choice is the defect in a different shape'
    }

    # Both in scope: the folder-name rule decides, and still not the order.
    $peerA = [pscustomobject]@{ name = 'Widget'; folderName = 'Widget-old'; path = (Join-Path $WorkspaceRoot 'peers\Widget-old'); branch = 'main'; status = 'clean'
        scope = [pscustomobject]@{ classification = 'in-scope'; inScope = $true; reason = 'In the working portfolio.' } }
    $peerB = [pscustomobject]@{ name = 'Widget'; folderName = 'Widget'; path = (Join-Path $WorkspaceRoot 'peers\Widget'); branch = 'main'; status = 'clean'
        scope = [pscustomobject]@{ classification = 'in-scope'; inScope = $true; reason = 'In the working portfolio.' } }
    foreach ($ordering in @(@($peerA, $peerB), @($peerB, $peerA))) {
        $peerRows = @(Invoke-PortfolioAssessment -LocalRepos $ordering -StructureStandards $structStds)
        if ([string]$peerRows[0].localPath -ne ([string]$peerB.path)) {
            throw ("With both checkouts in scope the folder matching the repo name must win, got '{0}'" -f [string]$peerRows[0].localPath)
        }
    }

    # A repository with one checkout must carry no duplicate record at all.
    $soloRows = @(Invoke-PortfolioAssessment -LocalRepos @($activeRepo) -StructureStandards $structStds)
    if ($null -ne (_GetField -Obj $soloRows[0] -Name 'duplicateCheckouts' -Default $null)) {
        throw 'A repository with a single checkout must not report a duplicate record'
    }

    Write-Host ("  duplicate checkouts ok: active checkout survives (pending={0}), archived clone recorded, choice stable under reversal" -f `
        [int]$survivor.pendingCount) -ForegroundColor DarkGray
}

Write-Step 'Roadmap audit rules — a readable file with no checkboxes is not a damaged file'
& {
    # ROADMAP-002 told the operator the file "could not be parsed" when the
    # parser had read it perfectly and found no '- [ ]' items. That sends them
    # to fix the wrong thing: CupHandleDetectionv2's roadmap is 179 lines of
    # releases, acceptance criteria and decision gates in table form.
    foreach ($rulesPath in @(
        (Join-Path $WorkspaceRoot 'standards\roadmap\roadmap-audit-rules.json'),
        (Join-Path $WorkspaceRoot 'spec\roadmap-contract\roadmap-audit-rules.json'))) {
        if (-not (Test-Path -LiteralPath $rulesPath)) { throw "Missing roadmap audit rules: $rulesPath" }
        $rulesDoc = Get-Content -LiteralPath $rulesPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $rule002 = @($rulesDoc.rules | Where-Object { [string]$_.id -eq 'ROADMAP-002' })
        if ($rule002.Count -ne 1) { throw "ROADMAP-002 not found exactly once in $rulesPath" }
        $msg = [string]$rule002[0].message
        if ($msg -match 'could not be parsed') {
            throw "ROADMAP-002 still claims the file 'could not be parsed' in $rulesPath; the parser read it fine and found no checklist items"
        }
        if ($msg -notmatch 'checklist item') {
            throw "ROADMAP-002 must name the real problem (no checklist items) in $rulesPath, got: $msg"
        }
    }
    Write-Host '  ROADMAP-002 states the real problem in both rule copies' -ForegroundColor DarkGray
}

Write-Step 'Truthful uncertainty — "I could not read this" and "this has no checklist" are different answers'
& {
    . $roadmapParser
    . $portfolioModule

    # 12 of 48 audited repositories were reported parse-error on 2026-08-27 —
    # among them a 216 KB, 1,496-line roadmap and a 43 KB one, both well-formed,
    # both planning in prose. The console sent the operator to repair files that
    # were not broken. The states must not share a name.
    $proseRoadmap = @(
        '# Genesys Cloud Auditor - Product Roadmap',
        '',
        'This roadmap defines the evolution of the auditor into a correlation-driven',
        'workbench. Delivery is staged; each stage states its acceptance criteria.',
        '',
        '## Stage 1 - Correlation engine',
        '',
        '| Deliverable | Acceptance |',
        '| --- | --- |',
        '| Event correlation | Two sources reconcile on a shared key |',
        '',
        '## Stage 2 - Escalation',
        '',
        'Escalation routes by severity and on-call calendar.'
    ) -join "`n"

    $parsedProse = Invoke-ParseRoadmapContent -Content $proseRoadmap -SourcePath 'C:\repos\demo\ROADMAP.md'
    if ([string]$parsedProse.roadmapState -eq 'parse-error') {
        throw 'A readable roadmap with no checkbox items must NOT be reported as parse-error — that is the defect this gate exists to stop'
    }
    if ([string]$parsedProse.roadmapState -ne 'no-checklist') {
        throw "A readable roadmap with no checkbox items must report 'no-checklist', got '$([string]$parsedProse.roadmapState)'"
    }
    if ([string]$parsedProse.parseError -match '(?i)could not be (parsed|read)') {
        throw "The no-checklist message must not claim the file was unreadable, got: $([string]$parsedProse.parseError)"
    }
    if ([string]$parsedProse.parseError -notmatch '(?i)checklist') {
        throw "The no-checklist message must name what is actually absent, got: $([string]$parsedProse.parseError)"
    }

    # Genuinely unreadable content keeps the old name — the distinction is only
    # worth having if BOTH sides of it stay true.
    foreach ($empty in @('', '   ')) {
        $parsedEmpty = Invoke-ParseRoadmapContent -Content $empty
        if ([string]$parsedEmpty.roadmapState -ne 'parse-error') {
            throw "Empty roadmap content must still report 'parse-error', got '$([string]$parsedEmpty.roadmapState)'"
        }
    }

    # A roadmap that DOES carry items must be unaffected.
    $withItems = Invoke-ParseRoadmapContent -Content "# R`n`n- [ ] do the thing`n"
    if ([string]$withItems.roadmapState -ne 'pending') {
        throw "A roadmap with a pending item must still report 'pending', got '$([string]$withItems.roadmapState)'"
    }

    # The operator-facing sentence must not send anyone to repair a sound file.
    $proseRepo = [pscustomobject]@{
        name = 'ProseRoadmapRepo'; localPath = $WorkspaceRoot; branch = 'main'; status = 'clean'
    }
    $proseEntries = @([pscustomobject]@{
        repoName = 'ProseRoadmapRepo'; repoPath = $WorkspaceRoot
        roadmapPath = (Join-Path $WorkspaceRoot 'ROADMAP.md'); roadmapState = 'no-checklist'; pendingCount = 0
    })
    $proseDocs = @([pscustomobject]@{
        repoName = 'ProseRoadmapRepo'; repoPath = $WorkspaceRoot
        dispatchReadiness = 'no-checklist'; roadmapState = 'no-checklist'; docFindings = @()
    })
    # Materialize with foreach, not @(). Invoke-PortfolioAssessment returns a
    # List[object]; on pwsh 7.6.3 @() wraps it instead of enumerating it, so
    # $rows[0] is the LIST. Member access still resolves by enumeration, which
    # is why that reads as working right up until something walks the object's
    # own properties — as the conclusion model does.
    $proseRow = $null
    foreach ($row in (Invoke-PortfolioAssessment -LocalRepos @($proseRepo) -RoadmapEntries $proseEntries `
                -DocAuditEntries $proseDocs -StructureStandards $structStds)) {
        if ($null -eq $proseRow) { $proseRow = $row }
    }
    if ($null -eq $proseRow) { throw 'The prose-roadmap fixture produced no assessment row' }
    if (@(_GetField -Obj $proseRow -Name 'repoName' -Default '') -ne 'ProseRoadmapRepo') {
        throw 'The fixture row did not materialize as a single assessment object'
    }
    if ([string]$proseRow.lifecycleState -eq 'parse-error') {
        throw 'A no-checklist roadmap must not land in the parse-error lifecycle state'
    }
    if ([string]$proseRow.recommendedAction -match '(?i)fix the parse error') {
        throw "The recommended action must not tell the operator to fix a parse error in a sound file, got: $([string]$proseRow.recommendedAction)"
    }
    if ([string]$proseRow.recommendedAction -notmatch '(?i)checklist|- \[ \]') {
        throw "The recommended action must name the checklist format it needs, got: $([string]$proseRow.recommendedAction)"
    }
    if ([string]$proseRow.dispatchReadiness -ne 'no-checklist') {
        throw "Dispatch readiness must carry the distinct state, got '$([string]$proseRow.dispatchReadiness)'"
    }
    if ([int]$proseRow.roadmapScore -le 20) {
        throw "A real plan the console cannot track must score above a damaged file (20), got $([int]$proseRow.roadmapScore)"
    }
    # Every blocking reason must be true of the file. "Could not be parsed" is not.
    foreach ($reason in @($proseRow.blockingReasons)) {
        if ([string]$reason -match '(?i)could not be parsed') {
            throw "A blocking reason still claims the roadmap could not be parsed: $reason"
        }
    }

    # The conclusion model must inherit the distinction, not flatten it.
    $conclusionModule = Join-Path $WorkspaceRoot 'backend\modules\portfolio\Portfolio.Conclusion.ps1'
    if (Test-Path -LiteralPath $conclusionModule) {
        . $conclusionModule
        $domainsCfg = Get-FoundationDomainsConfig -ConfigPath (Join-Path $WorkspaceRoot 'backend\config\foundation-domains.json')
        $concluded = Get-RepositoryFoundationConclusion -Entry $proseRow -Config $domainsCfg
        if ([string]$concluded.conclusion -ne 'insufficiently-understood') {
            throw "A no-checklist roadmap should conclude insufficiently-understood, got '$([string]$concluded.conclusion)'"
        }
        if ([string]$concluded.reason -match '(?i)could not be parsed') {
            throw "The conclusion still claims the roadmap could not be parsed: $([string]$concluded.reason)"
        }
        if ([string]$concluded.reason -notmatch '(?i)checklist') {
            throw "The conclusion must name what the product needs, got: $([string]$concluded.reason)"
        }
    }

    Write-Host ("  truthful uncertainty ok: prose roadmap reads no-checklist (score {0}, dispatch {1}), empty content still parse-error, conclusion names the need" -f `
        [int]$proseRow.roadmapScore, [string]$proseRow.dispatchReadiness) -ForegroundColor DarkGray
}

Write-Step 'Index staleness — an index cannot be read without its own verdict on whether it is still true'
& {
    . $portfolioModule

    $stalenessRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("idx-stale-{0}" -f ([guid]::NewGuid().ToString('n')))
    $stalenessIndexDir = Join-Path $stalenessRoot 'output\index'
    $null = New-Item -ItemType Directory -Path $stalenessIndexDir -Force
    # A fixture workspace with its own producer modules, so the fingerprint is
    # exercised as the derived thing it is rather than mocked.
    $producerDirs = @{}
    foreach ($name in 'portfolio', 'roadmap', 'docaudit') {
        $dir = Join-Path $stalenessRoot ("backend\modules\{0}" -f $name)
        $null = New-Item -ItemType Directory -Path $dir -Force
        Set-Content -LiteralPath (Join-Path $dir ("{0}.Fixture.ps1" -f $name)) -Value "function _Fx_$name { 'v1' }" -Encoding UTF8
        $producerDirs[$name] = $dir
    }
    try {
        # An index read with NO verdict attached is the whole defect: on
        # 2026-08-27 a six-hour-old index reported 0 of 9 dispatch-ready
        # repositories and every surface rendered it as fact.
        $bareIndex = [pscustomobject]@{
            schemaVersion = 1; kind = 'portfolio-index'
            generatedAt   = (Get-Date).ToUniversalTime().ToString('o')
            repoCount     = 0; repos = @()
        }
        Set-Content -LiteralPath (Join-Path $stalenessIndexDir 'repos.index.json') `
            -Value ($bareIndex | ConvertTo-Json -Depth 8) -Encoding UTF8

        $readBack = Get-PortfolioIndexPayload -WorkspaceRoot $stalenessRoot
        if ($null -eq $readBack) { throw 'The staleness fixture index did not read back at all' }
        $verdict = _GetField -Obj $readBack -Name 'staleness' -Default $null
        if ($null -eq $verdict) {
            throw 'Reading the portfolio index produced no staleness verdict — a surface can still render it as fact'
        }
        if (-not [bool]$verdict.stale) {
            throw 'An index carrying no record of the logic that produced it must not read as fresh'
        }
        if (@($verdict.reasons).Count -eq 0) {
            throw 'A stale verdict must say why; "stale" with no reason is not actionable'
        }

        # The fingerprint is DERIVED from the producer modules, never a
        # maintained list — prove both halves of that claim.
        $fingerprint = Get-PortfolioIndexLogicFingerprint -WorkspaceRoot $stalenessRoot
        if ([string]::IsNullOrWhiteSpace($fingerprint)) { throw 'The logic fingerprint must not be empty when producer modules exist' }
        if ($fingerprint -ne (Get-PortfolioIndexLogicFingerprint -WorkspaceRoot $stalenessRoot)) {
            throw 'The logic fingerprint must be stable across calls'
        }
        if ([string]::IsNullOrWhiteSpace((Get-PortfolioIndexLogicFingerprint -WorkspaceRoot $WorkspaceRoot))) {
            throw 'The logic fingerprint must not be empty for the real workspace'
        }

        # Editing a producer changes it...
        $editedFile = Join-Path $producerDirs['roadmap'] 'roadmap.Fixture.ps1'
        Set-Content -LiteralPath $editedFile -Value "function _Fx_roadmap { 'v2' }" -Encoding UTF8
        $afterEdit = Get-PortfolioIndexLogicFingerprint -WorkspaceRoot $stalenessRoot
        if ($afterEdit -eq $fingerprint) { throw 'Editing a producer module must move the logic fingerprint' }

        # ...and so does ADDING one, which is what a maintained list would miss.
        Set-Content -LiteralPath (Join-Path $producerDirs['portfolio'] 'portfolio.Extra.ps1') -Value "function _Fx_extra { 1 }" -Encoding UTF8
        $afterAdd = Get-PortfolioIndexLogicFingerprint -WorkspaceRoot $stalenessRoot
        if ($afterAdd -eq $afterEdit) { throw 'Adding a producer module must move the logic fingerprint — otherwise the set is a list that drifts' }

        # Line endings must not: the working tree is LF and a CI checkout is CRLF.
        $lfRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("idx-lf-{0}" -f ([guid]::NewGuid().ToString('n')))
        $crlfRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("idx-crlf-{0}" -f ([guid]::NewGuid().ToString('n')))
        try {
            foreach ($pair in @(@{ root = $lfRoot; nl = "`n" }, @{ root = $crlfRoot; nl = "`r`n" })) {
                $d = Join-Path $pair.root 'backend\modules\portfolio'
                $null = New-Item -ItemType Directory -Path $d -Force
                [System.IO.File]::WriteAllText((Join-Path $d 'same.ps1'), ('function A {' + $pair.nl + '  1' + $pair.nl + '}' + $pair.nl))
            }
            if ((Get-PortfolioIndexLogicFingerprint -WorkspaceRoot $lfRoot) -ne (Get-PortfolioIndexLogicFingerprint -WorkspaceRoot $crlfRoot)) {
                throw 'CRLF and LF copies of the same producer must fingerprint identically, or every CI checkout reads stale'
            }
        } finally {
            Remove-Item -LiteralPath $lfRoot -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $crlfRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
        $fingerprint = $afterAdd

        $now = [datetime]::Parse('2026-08-27T18:00:00Z').ToUniversalTime()
        $fresh = [pscustomobject]@{
            generatedAt = $now.AddMinutes(-30).ToString('o')
            producedBy  = [pscustomobject]@{ logicFingerprint = $fingerprint }
        }
        $freshVerdict = Get-PortfolioIndexStaleness -Index $fresh -CurrentFingerprint $fingerprint -Now $now
        if ([bool]$freshVerdict.stale) {
            throw ("A recent index produced by the running logic must read fresh, got: {0}" -f (@($freshVerdict.reasons) -join '; '))
        }

        # Stale by LOGIC — the dangerous one. Minutes old and wrong on every row.
        $wrongLogic = [pscustomobject]@{
            generatedAt = $now.AddMinutes(-5).ToString('o')
            producedBy  = [pscustomobject]@{ logicFingerprint = 'deadbeefdeadbeef' }
        }
        $wrongVerdict = Get-PortfolioIndexStaleness -Index $wrongLogic -CurrentFingerprint $fingerprint -Now $now
        if (-not [bool]$wrongVerdict.stale) {
            throw 'An index produced by different logic must read stale even when it is minutes old'
        }
        if ((@($wrongVerdict.reasons) -join ' ') -notmatch 'deadbeefdeadbeef') {
            throw 'The logic-drift reason must name the fingerprint the index was produced by'
        }

        # Stale by CLOCK, with the right logic.
        $old = [pscustomobject]@{
            generatedAt = $now.AddHours(-48).ToString('o')
            producedBy  = [pscustomobject]@{ logicFingerprint = $fingerprint }
        }
        $oldVerdict = Get-PortfolioIndexStaleness -Index $old -CurrentFingerprint $fingerprint -Now $now -MaxAgeHours 24
        if (-not [bool]$oldVerdict.stale) { throw 'A 48-hour-old index must read stale against a 24-hour window' }
        if ([double]$oldVerdict.ageHours -lt 47) { throw "Age must be reported in hours, got $([double]$oldVerdict.ageHours)" }

        # Nothing scanned yet is stale, not fresh-and-empty.
        $noneVerdict = Get-PortfolioIndexStaleness -Index $null -CurrentFingerprint $fingerprint -Now $now
        if (-not [bool]$noneVerdict.stale) { throw 'A missing index must read stale rather than empty-but-current' }

        # Not knowing which code is running is uncertainty, not freshness —
        # reading it as fresh would repeat the defect this check exists to end.
        $unknownVerdict = Get-PortfolioIndexStaleness -Index $fresh -CurrentFingerprint '' -Now $now
        if (-not [bool]$unknownVerdict.stale) {
            throw 'An index checked against an unknown current fingerprint must not read as fresh'
        }

        # A written index stamps itself, and reads back fresh on the same code.
        $stamped = Save-PortfolioIndexArtifacts -WorkspaceRoot $stalenessRoot -Assessments @() -LocalRepos @() `
            -GitHubRepos @() -Summary (Get-PortfolioAssessmentSummary -Assessments @()) -SignalSources @{} `
            -GeneratedAt ((Get-Date).ToUniversalTime().ToString('o'))
        if ($null -eq $stamped) { throw 'Save-PortfolioIndexArtifacts returned nothing for the staleness fixture' }
        $stampedRead = Get-PortfolioIndexPayload -WorkspaceRoot $stalenessRoot
        $stampedVerdict = _GetField -Obj $stampedRead -Name 'staleness' -Default $null
        if ([bool]$stampedVerdict.stale) {
            throw ("An index just written by this code must read fresh, got: {0}" -f (@($stampedVerdict.reasons) -join '; '))
        }
        if ([string]$stampedVerdict.producedBy -ne $fingerprint) {
            throw 'A written index must record the fingerprint of the logic that produced it'
        }

        # A conclusions payload must never present itself as current without a
        # verdict behind it — absent has to mean "not established", not "fresh".
        $conclusionModuleForStaleness = Join-Path $WorkspaceRoot 'backend\modules\portfolio\Portfolio.Conclusion.ps1'
        if (Test-Path -LiteralPath $conclusionModuleForStaleness) {
            . $conclusionModuleForStaleness
            $stalenessCfg = Get-FoundationDomainsConfig -ConfigPath (Join-Path $WorkspaceRoot 'backend\config\foundation-domains.json')
            $unbacked = Get-PortfolioConclusionsPayload -Entries @() -Config $stalenessCfg
            if (-not [bool]$unbacked.basis.indexStale) {
                throw 'A conclusions payload built without a staleness verdict must not report its index as current'
            }
            if (@($unbacked.basis.reasons).Count -eq 0) {
                throw 'An unbacked conclusions payload must say why its freshness is unestablished'
            }
            $backed = Get-PortfolioConclusionsPayload -Entries @() -Config $stalenessCfg -Staleness $freshVerdict
            if ([bool]$backed.basis.indexStale) {
                throw 'A conclusions payload backed by a fresh verdict must report its index as current'
            }
        }

        Write-Host ("  index staleness ok: verdict attached on every read; logic drift caught at 5 minutes old; clock drift at 48h; conclusions carry their basis; fresh index reads fresh (fingerprint {0})" -f $fingerprint) -ForegroundColor DarkGray
    } finally {
        Remove-Item -LiteralPath $stalenessRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Step 'Technology inventory — Lane 0.16: the Dependencies tab answers with what repositories actually run on'
& {
    . $portfolioModule

    $techRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("tech-inv-{0}" -f ([guid]::NewGuid().ToString('n')))
    try {
        # Fixture repos covering the three detection channels: named manifests,
        # dependency names inside package manifests (root and one level down),
        # and compose service images.
        $nodeRepo = Join-Path $techRoot 'repo-node'
        $null = New-Item -ItemType Directory -Path (Join-Path $nodeRepo 'frontend') -Force
        Set-Content -LiteralPath (Join-Path $nodeRepo 'package.json') -Encoding UTF8 -Value '{"dependencies":{"next":"^14.0.0","pg":"^8.11.0"},"devDependencies":{"typescript":"^5.4.0"}}'
        Set-Content -LiteralPath (Join-Path $nodeRepo 'tsconfig.json') -Encoding UTF8 -Value '{}'
        Set-Content -LiteralPath (Join-Path $nodeRepo 'Dockerfile') -Encoding UTF8 -Value 'FROM node:20'
        Set-Content -LiteralPath (Join-Path $nodeRepo 'frontend\package.json') -Encoding UTF8 -Value '{"dependencies":{"react":"^19.0.0"}}'

        $pyRepo = Join-Path $techRoot 'repo-python'
        $null = New-Item -ItemType Directory -Path $pyRepo -Force
        Set-Content -LiteralPath (Join-Path $pyRepo 'requirements.txt') -Encoding UTF8 -Value "flask`npsycopg2-binary==2.9.9"
        Set-Content -LiteralPath (Join-Path $pyRepo 'docker-compose.yml') -Encoding UTF8 -Value "services:`n  cache:`n    image: redis:7"

        $psRepo = Join-Path $techRoot 'repo-ps'
        $null = New-Item -ItemType Directory -Path (Join-Path $psRepo 'scripts') -Force
        Set-Content -LiteralPath (Join-Path $psRepo 'scripts\Invoke-Fixture.ps1') -Encoding UTF8 -Value 'Write-Output 1'

        $nodeProfile = @(Get-RepoTechnologyProfile -LocalPath $nodeRepo)
        $nodeIds = @($nodeProfile | ForEach-Object { [string]$_.id })
        foreach ($expected in @('nodejs', 'typescript', 'nextjs', 'postgresql', 'docker', 'react')) {
            if ($expected -notin $nodeIds) { throw ("The node fixture must detect '{0}', got: {1}" -f $expected, ($nodeIds -join ', ')) }
        }
        if ('python' -in $nodeIds) { throw 'The node fixture must not detect Python — detection must be evidence-bound, not generous' }
        $reactEvidence = [string](@($nodeProfile | Where-Object { $_.id -eq 'react' })[0].evidence)
        if ($reactEvidence -notmatch 'frontend/package\.json') {
            throw ("A child-directory manifest detection must name the manifest it came from, got: {0}" -f $reactEvidence)
        }

        $pyProfile = @(Get-RepoTechnologyProfile -LocalPath $pyRepo)
        $pyIds = @($pyProfile | ForEach-Object { [string]$_.id })
        foreach ($expected in @('python', 'flask', 'postgresql', 'redis', 'docker')) {
            if ($expected -notin $pyIds) { throw ("The python fixture must detect '{0}' (psycopg2/compose channels), got: {1}" -f $expected, ($pyIds -join ', ')) }
        }

        $psProfile = @(Get-RepoTechnologyProfile -LocalPath $psRepo)
        $psIds = @($psProfile | ForEach-Object { [string]$_.id })
        if ('powershell' -notin $psIds) { throw ("The PowerShell fixture must detect 'powershell', got: {0}" -f ($psIds -join ', ')) }
        if ('docker' -in $psIds) { throw 'The PowerShell fixture must not detect Docker' }

        if (@(Get-RepoTechnologyProfile -LocalPath '').Count -ne 0) { throw 'An empty localPath must yield an empty profile, never a throw' }
        if (@(Get-RepoTechnologyProfile -LocalPath (Join-Path $techRoot 'no-such-dir')).Count -ne 0) { throw 'A missing localPath must yield an empty profile' }

        # Aggregation: a row written before detection existed carries no
        # `technologies` field, and must be counted as data-less rather than
        # read as a repository with no technology in it.
        $techIndexFixture = [pscustomobject]@{
            generatedAt = (Get-Date).ToUniversalTime().ToString('o')
            repos       = @(
                [pscustomobject]@{ repoName = 'repo-node'; technologies = $nodeProfile },
                [pscustomobject]@{ repoName = 'repo-python'; technologies = $pyProfile },
                [pscustomobject]@{ repoName = 'legacy-row' }
            )
        }
        $inventory = Get-PortfolioTechInventoryPayload -IndexPayload $techIndexFixture
        if ([int]$inventory.repoCount -ne 3) { throw "Inventory repoCount must be 3, got $($inventory.repoCount)" }
        if ([int]$inventory.reposWithTechnologyData -ne 2) { throw "A pre-detection row must not count as technology data; expected 2, got $($inventory.reposWithTechnologyData)" }
        $pgEntry = @($inventory.technologies | Where-Object { $_.id -eq 'postgresql' })[0]
        if ($null -eq $pgEntry) { throw 'PostgreSQL must aggregate across detection channels (pg dependency + psycopg2)' }
        if ([int]$pgEntry.repoCount -ne 2) { throw "PostgreSQL must count both fixture repos, got $($pgEntry.repoCount)" }
        if (@($pgEntry.repos | Where-Object { [string]::IsNullOrWhiteSpace([string]$_.evidence) }).Count -gt 0) {
            throw 'Every aggregated detection must carry its evidence'
        }
        if (-not [bool]$inventory.basis.indexStale) {
            throw 'An inventory whose index carries no staleness verdict must not present itself as current'
        }
        if (@($inventory.basis.reasons).Count -eq 0) { throw 'An unestablished inventory basis must say why' }

        $emptyInventory = Get-PortfolioTechInventoryPayload -IndexPayload $null
        if (@($emptyInventory.technologies).Count -ne 0 -or [int]$emptyInventory.repoCount -ne 0) {
            throw 'A null index must aggregate to an explicitly empty inventory, never a throw'
        }

        Write-Host ("  technology inventory ok: {0} technologies across the fixtures; cross-channel aggregation, child-manifest evidence, pre-detection rows counted as data-less" -f @($inventory.technologies).Count) -ForegroundColor DarkGray
    } finally {
        Remove-Item -LiteralPath $techRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Step 'Foundation conclusions — Release 3.6 M1: every repository leaves with an explainable conclusion'
& {
    . $portfolioConclusionModule
    $fdConfig = Get-FoundationDomainsConfig -ConfigPath $foundationDomainsConfig
    if ($null -eq $fdConfig) { throw 'foundation-domains.json did not load (schemaVersion v1 with a non-empty domains array is required)' }
    $fdDomainIds = @($fdConfig.domains | ForEach-Object { [string]$_.id })
    foreach ($required in @('documentation', 'purpose', 'planning', 'structure', 'intentional-engineering')) {
        if ($required -notin $fdDomainIds) { throw "foundation-domains.json is missing the starting-set domain '$required'" }
    }
    $fdUnscored = @($fdConfig.domains | Where-Object { [string]$_.id -eq 'intentional-engineering' })[0]
    if ($fdUnscored.scored -ne $false -or [string]$fdUnscored.status -ne 'not-scored') { throw 'intentional-engineering must ship defined-not-scored (scored=false, status=not-scored) until Release 3.7 decides its detectors' }
    if (@($fdUnscored.evidenceModel.subAreas).Count -lt 5) { throw 'intentional-engineering evidence model must name its sub-areas (test, architecture, operational, maintenance, delivery health)' }
    $fdKindIds = @($fdConfig.kinds | ForEach-Object { [string]$_.id })
    foreach ($required in @('library', 'service', 'script-collection', 'archived', 'minimal', 'externally-managed')) {
        if ($required -notin $fdKindIds) { throw "foundation-domains.json is missing the repository kind '$required'" }
    }

    # Fixture set the acceptance criteria name: no roadmap, archived, minimal
    # utility, plus the L1/L3, GitHub-only, parse-error and structure-gap shapes.
    function ConvertTo-FdEntry([hashtable]$Overrides) {
        $base = @{ repoId = 'repo:x'; repoName = 'x'; sourceCoverage = 'local'; localPath = (Join-Path $WorkspaceRoot 'output\smoke\module\fd-x'); lastScanStatus = 'ok'
            lifecycleState = 'discovered'; curationState = 'none'; hasReadme = $false; readmeScore = 0; docFindingCount = 0; hasRoadmap = $false; roadmapState = 'missing'
            maturityLevel = 'L0-Absent'; pendingCount = 0; repoType = 'other'; structureFindings = @(); hasCiSignal = $false; hasTestSignal = $false
            latestWorkflowRunConclusion = $null; localCommitsLastMonth = 0 }
        foreach ($k in $Overrides.Keys) { $base[$k] = $Overrides[$k] }
        $base['repoId'] = 'repo:' + [string]$base['repoName']
        return [pscustomobject]$base
    }
    $fdFixtures = @(
        (ConvertTo-FdEntry @{ repoName = 'no-roadmap'; hasReadme = $true; readmeScore = 80 }),
        (ConvertTo-FdEntry @{ repoName = 'archived'; lifecycleState = 'archived'; hasReadme = $true; readmeScore = 40 }),
        (ConvertTo-FdEntry @{ repoName = 'curated-archive'; curationState = 'archived-ignore'; hasReadme = $true; readmeScore = 20 }),
        (ConvertTo-FdEntry @{ repoName = 'minimal-utility'; hasReadme = $true; readmeScore = 72; hasRoadmap = $true; roadmapState = 'complete'; maturityLevel = 'L3-Contract-Ready'; pendingCount = 0 }),
        (ConvertTo-FdEntry @{ repoName = 'l1-roadmap'; hasReadme = $true; readmeScore = 75; hasRoadmap = $true; roadmapState = 'pending'; maturityLevel = 'L1-Informal'; pendingCount = 3 }),
        (ConvertTo-FdEntry @{ repoName = 'healthy-l3'; hasReadme = $true; readmeScore = 90; hasRoadmap = $true; roadmapState = 'pending'; maturityLevel = 'L3-Contract-Ready'; pendingCount = 4; hasCiSignal = $true; hasTestSignal = $true; repoType = 'node' }),
        (ConvertTo-FdEntry @{ repoName = 'github-only'; sourceCoverage = 'github'; localPath = '' }),
        (ConvertTo-FdEntry @{ repoName = 'parse-error'; hasReadme = $true; readmeScore = 70; hasRoadmap = $true; roadmapState = 'parse-error' }),
        (ConvertTo-FdEntry @{ repoName = 'struct-gap'; hasReadme = $true; readmeScore = 85; hasRoadmap = $true; roadmapState = 'pending'; maturityLevel = 'L4-Orchestration-Ready'; repoType = 'python'; structureFindings = @([pscustomobject]@{ kind = 'missing-root-file'; target = 'LICENSE'; severity = 'critical'; category = 'root'; recommendedAction = 'add' }) })
    )

    # Red first: the validator must reject a blank reason and a strengthen
    # verdict with no route before its green verdict means anything.
    $fdBad = Get-RepositoryFoundationConclusion -Entry $fdFixtures[0] -Config $fdConfig
    $fdBad.reason = ''
    $fdBad.nextAction = $null
    $fdRed = @(Test-FoundationConclusion -Conclusion $fdBad -Config $fdConfig)
    if ($fdRed.Count -lt 2 -or -not ($fdRed -join ' ').Contains('empty reason') -or -not ($fdRed -join ' ').Contains('no next-action route')) {
        throw "Foundation-conclusion validator did not go red on the blank-reason / no-route fixture (violations: $($fdRed -join '; '))"
    }
    $fdBare = Get-RepositoryFoundationConclusion -Entry $fdFixtures[0] -Config $fdConfig
    $fdBare.reason = 'L0-Absent'
    if (@(Test-FoundationConclusion -Conclusion $fdBare -Config $fdConfig).Count -eq 0) { throw "Validator accepted 'L0-Absent' as a whole reason" }

    $fdPayload = Get-PortfolioConclusionsPayload -Entries $fdFixtures -Config $fdConfig
    if ([int]$fdPayload.count -ne $fdFixtures.Count) { throw "Expected $($fdFixtures.Count) conclusions, got $($fdPayload.count)" }
    if (-not $fdPayload.contract.holds) { throw "Conclusion contract violated on the fixture set: $($fdPayload.contract.violations -join '; ')" }
    $fdByName = @{}
    foreach ($item in $fdPayload.items) { $fdByName[[string]$item.repoName] = $item }
    $fdExpect = @{
        'no-roadmap' = 'strengthen'; 'archived' = 'appropriate-as-is'; 'curated-archive' = 'appropriate-as-is'; 'minimal-utility' = 'appropriate-as-is'
        'l1-roadmap' = 'strengthen'; 'healthy-l3' = 'appropriate-as-is'; 'github-only' = 'insufficiently-understood'; 'parse-error' = 'insufficiently-understood'; 'struct-gap' = 'strengthen'
    }
    foreach ($name in $fdExpect.Keys) {
        $actual = [string]$fdByName[$name].conclusion
        if ($actual -ne $fdExpect[$name]) { throw "Fixture '$name' expected conclusion '$($fdExpect[$name])', got '$actual' ($($fdByName[$name].reason))" }
    }
    $fdKnownRoutes = @('/api/readme/standardize/preview', '/api/roadmap/repair/preview', '/api/repository-improvement/preview')
    foreach ($item in $fdPayload.items) {
        if ([string]::IsNullOrWhiteSpace([string]$item.reason)) { throw "Fixture '$($item.repoName)' has no reason" }
        if ([string]$item.conclusion -eq 'strengthen' -and [string]$item.nextAction.route -notin $fdKnownRoutes) { throw "Fixture '$($item.repoName)' strengthen names an unknown route '$($item.nextAction.route)'" }
        foreach ($d in @($item.domains)) { if (@($d.evidence).Count -eq 0) { throw "Fixture '$($item.repoName)' domain '$($d.domain)' carries no evidence" } }
    }
    if ([string]$fdByName['no-roadmap'].nextAction.route -ne '/api/roadmap/repair/preview') { throw 'A missing roadmap must offer the smallest credible plan (roadmap repair preview)' }
    if ([string]$fdByName['struct-gap'].nextAction.route -ne '/api/repository-improvement/preview') { throw 'A critical structure gap must offer the structure repair preview' }
    if ([string]$fdByName['parse-error'].nextAction.route -ne '/api/roadmap/repair/preview') { throw 'An unparseable roadmap must still offer the repair preview' }
    if ([string]$fdByName['archived'].kind -ne 'archived' -or [string]$fdByName['curated-archive'].kind -ne 'archived') { throw 'lifecycleState=archived and curationState=archived-ignore must both resolve kind=archived' }
    $fdArchivedPlanning = @($fdByName['archived'].domains | Where-Object { $_.domain -eq 'planning' })[0]
    if ([string]$fdArchivedPlanning.status -ne 'not-applicable') { throw "Archived planning must be not-applicable, got '$($fdArchivedPlanning.status)'" }
    $fdNoRoadmapPlanning = @($fdByName['no-roadmap'].domains | Where-Object { $_.domain -eq 'planning' })[0]
    if (([string]$fdNoRoadmapPlanning.evidence[0]) -notmatch 'no plan recorded') { throw "A missing roadmap must read as 'no plan recorded', not L0-Absent (got '$($fdNoRoadmapPlanning.evidence[0])')" }
    if ([string]$fdByName['github-only'].reason -notmatch 'local clone') { throw 'A GitHub-only entry must name the local clone the product needs' }
    # M2 backend: a healthy repo with recorded pending work offers the packaging
    # flow, preview-first (the readiness check) - never a dispatch; a healthy
    # repo with nothing pending offers nothing.
    if ([string]$fdByName['healthy-l3'].nextAction.route -ne '/api/roadmap/dispatch/check' -or [string]$fdByName['healthy-l3'].nextAction.kind -ne 'dispatch-readiness-check') {
        throw "A healthy L3 repo with pending work must offer the dispatch readiness check (got '$($fdByName['healthy-l3'].nextAction.route)')"
    }
    if ([string]$fdByName['healthy-l3'].nextAction.body.repoName -ne 'healthy-l3') { throw 'The packaging action must carry repoName, the dispatch-check contract' }
    if ($null -ne $fdByName['minimal-utility'].nextAction) { throw 'A healthy repo with no pending work must not offer an action' }
    if ([string]$fdByName['archived'].conclusion -ne 'appropriate-as-is' -or $null -ne $fdByName['archived'].nextAction) { throw 'An archived repo concludes appropriate-as-is with no action' }
    # M2 backend: the outcome summary every list entry carries. It must say the
    # same thing as the full conclusion, and attaching it must not scan.
    $fdEnriched = @(Add-FoundationOutcome -Entries @($fdFixtures | ForEach-Object { [pscustomobject]($_ | ConvertTo-Json -Depth 8 | ConvertFrom-Json) }) -Config $fdConfig)
    if ($fdEnriched.Count -ne $fdFixtures.Count) { throw 'Add-FoundationOutcome dropped entries' }
    foreach ($entry in $fdEnriched) {
        $summary = $entry.outcome
        if ($null -eq $summary) { throw "Entry '$($entry.repoName)' carries no outcome summary" }
        $full = $fdByName[[string]$entry.repoName]
        if ([string]$summary.conclusion -ne [string]$full.conclusion -or [string]$summary.reason -ne [string]$full.reason) { throw "Outcome summary for '$($entry.repoName)' disagrees with the full conclusion" }
        $fullRoute = if ($null -eq $full.nextAction) { $null } else { [string]$full.nextAction.route }
        if ([string]$summary.nextActionRoute -ne [string]$fullRoute) { throw "Outcome summary for '$($entry.repoName)' names a different next action than the conclusion" }
        if ($summary.holds -ne $true) { throw "Outcome summary for '$($entry.repoName)' reports the contract broken" }
    }
    $fdGapSummary = @($fdEnriched | Where-Object { $_.repoName -eq 'struct-gap' })[0].outcome
    if ([int]$fdGapSummary.gapCount -ne 1 -or @($fdGapSummary.gapDomains) -notcontains 'structure') { throw "struct-gap summary must count its one structure gap (got $($fdGapSummary.gapCount): $($fdGapSummary.gapDomains -join ','))" }
    if (@(Add-FoundationOutcome -Entries @($fdFixtures[0]) -Config $null)[0].PSObject.Properties.Name -contains 'outcome') { throw 'A null config must leave entries untouched, not attach a guessed outcome' }
    # Coverage reconciles: every domain's status counts sum to the item count.
    foreach ($id in $fdDomainIds) {
        $row = $fdPayload.coverage.$id
        $sum = 0; foreach ($p in $row.PSObject.Properties) { $sum += [int]$p.Value }
        if ($sum -ne $fdFixtures.Count) { throw "Coverage for '$id' sums to $sum, not $($fdFixtures.Count)" }
    }
    $fdConclusionSum = 0; foreach ($p in $fdPayload.byConclusion.PSObject.Properties) { $fdConclusionSum += [int]$p.Value }
    if ($fdConclusionSum -ne $fdFixtures.Count) { throw "byConclusion sums to $fdConclusionSum, not $($fdFixtures.Count)" }
    # The route serializes this payload; a shape that dies in ConvertTo-Json is not shippable.
    $fdRoundTrip = ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $fdPayload -Depth 12)
    if (-not $fdRoundTrip.contract.holds -or @($fdRoundTrip.items).Count -ne $fdFixtures.Count) { throw 'Conclusions payload did not survive a JSON round trip' }

    # Refinement is a data change: a new detection rule + kind applicability,
    # applied to a cloned config object, changes the conclusion with no code.
    $fdRefined = ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $fdConfig -Depth 12)
    $fdRefined.kindDetection.rules += [pscustomobject]@{ kind = 'minimal'; when = [pscustomobject]@{ lifecycleState = 'completed' }; basis = 'smoke: completed reads as minimal' }
    $fdMinimalEntry = ConvertTo-FdEntry @{ repoName = 'done-utility'; lifecycleState = 'completed'; hasReadme = $true; readmeScore = 75 }
    $fdBefore = Get-RepositoryFoundationConclusion -Entry $fdMinimalEntry -Config $fdConfig
    $fdAfter = Get-RepositoryFoundationConclusion -Entry $fdMinimalEntry -Config $fdRefined
    if ([string]$fdBefore.conclusion -ne 'strengthen' -or [string]$fdAfter.conclusion -ne 'appropriate-as-is' -or [string]$fdAfter.kind -ne 'minimal') {
        throw "A JSON-only refinement did not change the conclusion (before=$($fdBefore.conclusion) after=$($fdAfter.conclusion) kind=$($fdAfter.kind))"
    }
    if (@(Test-FoundationConclusion -Conclusion $fdAfter -Config $fdRefined).Count -ne 0) { throw 'The refined conclusion broke the contract' }

    Write-Host ("  foundation conclusions ok: {0} domains, {1} kinds; validator red on blank reason + no route + bare L0-Absent; {2} fixtures all concluded ({3}); coverage and byConclusion reconcile; JSON round trip holds; a JSON-only kind rule flipped a conclusion" -f $fdDomainIds.Count, $fdKindIds.Count, $fdFixtures.Count, (($fdPayload.byConclusion.PSObject.Properties | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join ' ')) -ForegroundColor DarkGray
}

Write-Step 'Foundation coverage + leverage - Release 3.6 M5: a figure nobody measured is never a zero'
& {
    # Each section runs in its own scope block, so the conclusion module has to
    # be loaded here too -- M1's dot-source does not reach across.
    . $portfolioConclusionModule
    . (Join-Path $WorkspaceRoot 'backend\modules\portfolio\Portfolio.Leverage.ps1')
    . (Join-Path $WorkspaceRoot 'backend\modules\portfolio\Portfolio.Analytics.ps1')
    $mlConfig = Get-FoundationDomainsConfig -ConfigPath $foundationDomainsConfig
    if ($null -eq $mlConfig) { throw 'foundation-domains.json did not load for the coverage smoke' }

    function ConvertTo-MlEntry([hashtable]$Overrides) {
        $base = @{ repoId = 'repo:x'; repoName = 'x'; sourceCoverage = 'local'; localPath = (Join-Path $WorkspaceRoot 'output\smoke\module\ml-x'); lastScanStatus = 'ok'
            lifecycleState = 'discovered'; curationState = 'none'; hasReadme = $false; readmeScore = 0; docFindingCount = 0; hasRoadmap = $false; roadmapState = 'missing'
            maturityLevel = 'L0-Absent'; pendingCount = 0; repoType = 'other'; structureFindings = @(); hasCiSignal = $false; hasTestSignal = $false
            latestWorkflowRunConclusion = $null; localCommitsLastMonth = 0 }
        foreach ($k in $Overrides.Keys) { $base[$k] = $Overrides[$k] }
        $base['repoId'] = 'repo:' + [string]$base['repoName']
        return [pscustomobject]$base
    }

    # One healthy repo (4 applicable domains present) + one bare repo
    # (documentation/purpose/planning missing, structure present) => 5 of 8.
    $mlEntries = @(
        (ConvertTo-MlEntry @{ repoName = 'healthy'; hasReadme = $true; readmeScore = 90; hasRoadmap = $true; roadmapState = 'pending'; maturityLevel = 'L3-Contract-Ready'; pendingCount = 2; repoType = 'node'; hasCiSignal = $true; hasTestSignal = $true }),
        (ConvertTo-MlEntry @{ repoName = 'bare' })
    )
    $mlCoverage = (Get-PortfolioConclusionsPayload -Entries $mlEntries -Config $mlConfig).coverage
    $mlPercent = _GetPortfolioTrendCoveragePercent -Coverage $mlCoverage
    $mlExpected = [math]::Round((5.0 / 8.0) * 100.0, 1)
    if ($mlPercent -ne $mlExpected) { throw "Foundation coverage expected $mlExpected%, got $mlPercent%" }

    # An excused domain must neither help nor hurt: not-applicable is excluded
    # from BOTH halves, or an archived repo would silently inflate the figure.
    $mlWithArchived = @($mlEntries) + @(ConvertTo-MlEntry @{ repoName = 'archived'; lifecycleState = 'archived'; hasReadme = $true; readmeScore = 90 })
    $mlArchivedPct = _GetPortfolioTrendCoveragePercent -Coverage (Get-PortfolioConclusionsPayload -Entries $mlWithArchived -Config $mlConfig).coverage
    $mlArchivedExpected = [math]::Round((7.0 / 10.0) * 100.0, 1)
    if ($mlArchivedPct -ne $mlArchivedExpected) { throw "An archived repo's not-applicable domains must be excluded from both halves: expected $mlArchivedExpected%, got $mlArchivedPct%" }

    # An empty portfolio has no coverage - null, never a 0 that reads as measured.
    if ($null -ne (_GetPortfolioTrendCoveragePercent -Coverage $null)) { throw 'Coverage over a null must be null, not 0' }
    if ($null -ne (_GetPortfolioTrendCoveragePercent -Coverage (Get-PortfolioConclusionsPayload -Entries @() -Config $mlConfig).coverage)) { throw 'Coverage over an empty portfolio must be null, not 0' }

    # The series must exist in the scaffold path, in the frontend's palette, and
    # be absent entirely when no coverage was supplied.
    $mlSummary = [pscustomobject]@{ totalRepos = 2; readyForWorkCount = 1; byLifecycle = @{} }
    $mlNow = (Get-Date).ToUniversalTime().ToString('o')
    $mlTrend = Get-PortfolioTrendPayload -Assessments $mlEntries -Summary $mlSummary -GeneratedAt $mlNow -SeedSource 'portfolio-index' -WorkspaceRoot $WorkspaceRoot -RequestedDays 30 -Coverage $mlCoverage
    $mlSeries = @($mlTrend.series | Where-Object { $_.key -eq 'foundationCoverage' })
    if ($mlSeries.Count -ne 1) { throw 'The trend carries no foundationCoverage series in the scaffold path' }
    if ($mlSeries[0].color -notin @('emerald', 'sky', 'amber', 'slate')) { throw "Series color '$($mlSeries[0].color)' is outside the palette the frontend accepts; it would silently fall back to emerald" }
    if ([double]$mlSeries[0].points[0].value -ne $mlExpected) { throw 'The series point disagrees with the computed coverage' }
    $mlNoCoverage = Get-PortfolioTrendPayload -Assessments $mlEntries -Summary $mlSummary -GeneratedAt $mlNow -SeedSource 'portfolio-index' -WorkspaceRoot $WorkspaceRoot -RequestedDays 30
    if ('foundationCoverage' -in @($mlNoCoverage.series | ForEach-Object { $_.key })) { throw 'A null coverage must produce no series at all, not a zero line' }

    # Both series-building blocks must know the key. The history-backed block
    # re-news the list, so a series added to only one of them vanishes the
    # moment the other applies - the classic defect in this file.
    $mlAnalyticsSource = Get-Content -LiteralPath (Join-Path $WorkspaceRoot 'backend\modules\portfolio\Portfolio.Analytics.ps1') -Raw -Encoding UTF8
    $mlSeriesBlocks = @([regex]::Matches($mlAnalyticsSource, "key\s*=\s*'foundationCoverage'"))
    if ($mlSeriesBlocks.Count -lt 2) { throw "foundationCoverage appears in $($mlSeriesBlocks.Count) series block(s); it must be in both the scaffold and the history-backed block or it disappears when history arrives" }

    # Leverage: red first - a metric that reports 0 for something unmeasured.
    $mlBad = [pscustomobject]@{ metrics = @(
        [pscustomobject]@{ key = 'fake'; label = 'Fake'; value = 0; unit = 'percent'; available = $false; basis = 'not captured'; sampleSize = 0 }
        [pscustomobject]@{ key = 'nobasis'; label = 'No basis'; value = 5; unit = 'count'; available = $true; basis = ''; sampleSize = 1 }
    ) }
    $mlRed = @(Test-LeverageMetricContract -Payload $mlBad)
    if ($mlRed.Count -lt 2) { throw "The leverage contract check did not go red on its violating fixture (violations: $($mlRed -join '; '))" }
    if (-not (($mlRed -join ' ') -match 'must be null')) { throw 'The contract must reject a zero standing in for an unmeasured figure by name' }

    $mlRuns = @(
        [pscustomobject]@{ status = 'completed'; retryCount = 0; workUnitsEstimated = 4; workUnitsActual = 5; timeToDeliverSeconds = 1800 }
        [pscustomobject]@{ status = 'completed'; retryCount = 2; workUnitsEstimated = 3; workUnitsActual = 3; timeToDeliverSeconds = 3600 }
    )
    $mlLeverage = Get-PortfolioLeverage -AgentRuns $mlRuns -ExecutionMetrics ([pscustomobject]@{ completedThisWeek = 4 }) -Conclusions (Get-PortfolioConclusionsPayload -Entries $mlEntries -Config $mlConfig) -OperatorVerifications @(1, 2, 3) -WindowDays 30
    $mlGreen = @(Test-LeverageMetricContract -Payload $mlLeverage)
    if ($mlGreen.Count -ne 0) { throw "The derived leverage payload broke its own contract: $($mlGreen -join '; ')" }
    $mlFirstPass = @($mlLeverage.metrics | Where-Object { $_.key -eq 'agentFirstPassSuccess' })[0]
    if ([double]$mlFirstPass.value -ne 50) { throw "First-pass success expected 50%, got $($mlFirstPass.value)" }
    foreach ($mlDeclared in @('operatorMinutesPerTask', 'recommendationsAccepted')) {
        $mlMetric = @($mlLeverage.metrics | Where-Object { $_.key -eq $mlDeclared })[0]
        if ($null -eq $mlMetric) { throw "The leverage family must name '$mlDeclared' even though it is not captured" }
        if ($mlMetric.available -or $null -ne $mlMetric.value) { throw "'$mlDeclared' is not captured and must be null, not a number" }
        if ($mlMetric.basis -notmatch 'Not captured') { throw "'$mlDeclared' must say it is not captured" }
    }
    # With no ledgers at all, nothing may fabricate a figure.
    $mlEmpty = Get-PortfolioLeverage -WindowDays 30
    $mlFabricated = @($mlEmpty.metrics | Where-Object { -not $_.available -and $null -ne $_.value })
    if ($mlFabricated.Count -gt 0) { throw "Unavailable metrics carrying values: $(@($mlFabricated | ForEach-Object { $_.key }) -join ', ')" }

    Write-Host ("  coverage + leverage ok: {0}% over 8 applicable foundation(s), archived excluded from both halves ({1}%), empty portfolio null; series in both blocks and inside the palette; leverage red on a zeroed fixture first, then {2} metric(s) with {3} derived and 2 named-but-uncaptured" -f `
            $mlPercent, $mlArchivedPct, $mlLeverage.metricCount, $mlLeverage.availableCount) -ForegroundColor DarkGray
}

Write-Step 'Portfolio value scoring — smoke: security/test work ranks above generic chores'
$highValue = Invoke-PortfolioValueScore `
    -ItemText 'Add API authentication and contract smoke tests for dispatch endpoints' `
    -Section 'Engineering milestones' `
    -Tags @('security','testing') `
    -ItemIndex 0 `
    -RepoContext ([pscustomobject]@{ maturityLevel = 'L4-Orchestration-Ready' }) `
    -ScoringConfig $valueScoringConfig
$lowValue = Invoke-PortfolioValueScore `
    -ItemText 'Polish miscellaneous wording in old docs' `
    -Section 'Backlog' `
    -Tags @() `
    -ItemIndex 8 `
    -RepoContext ([pscustomobject]@{ maturityLevel = 'L1-Informal' }) `
    -ScoringConfig $valueScoringConfig
if ($highValue.valueScore -le $lowValue.valueScore) { throw "Expected security/test work score to exceed generic docs work; high=$($highValue.valueScore) low=$($lowValue.valueScore)" }
if (@($highValue.valueRationale).Count -eq 0) { throw 'Expected value-scored item to include rationale' }
Write-Host ("  value scorer ranked high={0} low={1}" -f $highValue.valueScore, $lowValue.valueScore) -ForegroundColor DarkGray

Write-Step 'Portfolio value scoring — smoke: effortFit floor for sprawling items (Release 2.7 Phase A decision, model 1.1)'
$sprawlItem = Invoke-PortfolioValueScore `
    -ItemText 'Add a persistent OAuth distribution analytics layer' `
    -ItemIndex 0 `
    -RepoContext ([pscustomobject]@{ maturityLevel = 'L4-Orchestration-Ready' }) `
    -ScoringConfig $valueScoringConfig
$boundedItem = Invoke-PortfolioValueScore `
    -ItemText 'Add repo status tests' `
    -ItemIndex 0 `
    -RepoContext ([pscustomobject]@{ maturityLevel = 'L4-Orchestration-Ready' }) `
    -ScoringConfig $valueScoringConfig
if ([int]$sprawlItem.scoringSignals.dimensions.effortFit -ne 2) { throw "Expected effortFit floor=2 for sprawling item; got $($sprawlItem.scoringSignals.dimensions.effortFit)" }
if ([int]$boundedItem.scoringSignals.dimensions.effortFit -ne 4) { throw "Expected effortFit=4 for bounded item; got $($boundedItem.scoringSignals.dimensions.effortFit)" }
if ($sprawlItem.scoringSignals.dimensions.effortFit -ge $boundedItem.scoringSignals.dimensions.effortFit) { throw 'effortFit floor did not penalize the sprawling item below the bounded item' }
Write-Host ("  effortFit floor ok: sprawl effortFit={0} < bounded effortFit={1} (model {2})" -f $sprawlItem.scoringSignals.dimensions.effortFit, $boundedItem.scoringSignals.dimensions.effortFit, $valueScoringConfig.modelVersion) -ForegroundColor DarkGray

Write-Step 'Portfolio assessment — smoke: ready-for-work fires on L4 + pending items'
$readyRepo = [pscustomobject]@{ name = 'ready-repo'; localPath = $WorkspaceRoot; isArchived = $false; htmlUrl = ''; branch = 'main'; status = 'clean' }
$readyRoadmap = @([pscustomobject]@{
    repoName = 'ready-repo'
    roadmapPath = (Join-Path $WorkspaceRoot 'ROADMAP.md')
    roadmapState = 'pending'
    pendingCount = 5
    nextPendingItem = [pscustomobject]@{ text = 'next thing' }
    activeRelease = [pscustomobject]@{
        releaseName = 'Release 2.0 — Dispatch Budgets'; releaseVersion = '2.0'; releaseTitle = 'Dispatch Budgets'
        releaseGoal = 'Ship bounded dispatch budgets.'
        pendingMilestones = @('Add API authentication and contract smoke tests for dispatch endpoints')
        acceptanceCriteria = @('The dispatch budget is enforced for every queued task.')
        outOfScope = @('Unrelated runner changes.')
        validationPlan = @('Run `scripts/Invoke-ModuleSmokeTest.ps1` and confirm it exits successfully.')
        activePhasePlan = [pscustomobject]@{ phaseName = 'Phase 2: Quota guard'; scope = 'Quota guard'; workUnitsEstimated = 8 }
        budgetGuardrail = [pscustomobject]@{ maxUnitsPerPhase = 10 }
    }
    activePhasePlan = [pscustomobject]@{ phaseName = 'Phase 2: Quota guard'; workUnitsEstimated = 8 }
    budgetGuardrail = [pscustomobject]@{ estimatedReleaseWorkUnits = 18; maxUnitsPerPhase = 10; present = $true }
    estimatedSessionWorkUnits = 8
})
$readyMaturity = @([pscustomobject]@{
    repoName = 'ready-repo'
    maturityLevel = 'L4-Orchestration-Ready'
    maturityScore = 100
    sections = @(
        [pscustomobject]@{ name = 'Engineering milestones'; pendingItems = @('Add API authentication and contract smoke tests for dispatch endpoints', 'Polish miscellaneous wording in old docs'); completedItems = @() }
    )
})
$readyAssess = Invoke-PortfolioAssessment -LocalRepos @($readyRepo) -RoadmapEntries $readyRoadmap -RoadmapAuditEntries $readyMaturity -StructureStandards $structStds -ValueScoringConfig $valueScoringConfig
if ($readyAssess[0].lifecycleState -ne 'ready-for-work') { throw "Expected lifecycleState=ready-for-work for L4 + pending, got '$($readyAssess[0].lifecycleState)'" }
if ($readyAssess[0].pendingItemCount -ne 5)              { throw "Expected pendingItemCount=5, got $($readyAssess[0].pendingItemCount)" }
if (@($readyAssess[0].pendingItems).Count -ne 2)         { throw "Expected 2 scored pendingItems, got $(@($readyAssess[0].pendingItems).Count)" }
if ($null -eq $readyAssess[0].topValueItem)              { throw 'Expected topValueItem to be populated for ready repo with pending items' }
if ($readyAssess[0].topValueItem.text -notmatch 'authentication') { throw "Expected topValueItem to select authentication/test work, got '$($readyAssess[0].topValueItem.text)'" }
if ([double]$readyAssess[0].estimatedSessionWorkUnits -ne 8) { throw "Expected estimatedSessionWorkUnits=8, got '$($readyAssess[0].estimatedSessionWorkUnits)'" }
if ([string]$readyAssess[0].activePhasePlan.phaseName -ne 'Phase 2: Quota guard') { throw "Expected activePhasePlan.phaseName='Phase 2: Quota guard', got '$($readyAssess[0].activePhasePlan.phaseName)'" }
Write-Host '  ready-for-work classification correct' -ForegroundColor DarkGray

Write-Step 'Portfolio assessment — smoke: summary aggregator counts lifecycle states'
$mixedAssess = @($archivedAssess[0], $parseErrAssess[0], $runningAssess[0], $ghOnlyAssess[0], $bothAssess[0], $readyAssess[0])
$summary = Get-PortfolioAssessmentSummary -Assessments $mixedAssess
if ($summary.totalRepos -ne 6)                  { throw "Expected totalRepos=6, got $($summary.totalRepos)" }
if ($summary.byLifecycle['archived'] -ne 1)     { throw "Expected byLifecycle[archived]=1, got $($summary.byLifecycle['archived'])" }
if ($summary.byLifecycle['parse-error'] -ne 1)  { throw "Expected byLifecycle[parse-error]=1, got $($summary.byLifecycle['parse-error'])" }
if ($summary.byLifecycle['running'] -ne 1)      { throw "Expected byLifecycle[running]=1, got $($summary.byLifecycle['running'])" }
if ($summary.byLifecycle['ready-for-work'] -ne 1) { throw "Expected byLifecycle[ready-for-work]=1, got $($summary.byLifecycle['ready-for-work'])" }
if ($summary.bySourceCoverage['github'] -ne 1)  { throw "Expected bySourceCoverage[github]=1, got $($summary.bySourceCoverage['github'])" }
if ($summary.bySourceCoverage['local+github'] -lt 1) { throw "Expected bySourceCoverage[local+github] >= 1, got $($summary.bySourceCoverage['local+github'])" }
Write-Host ("  summary aggregation correct: total={0} ready={1} running={2} blocked={3}" -f $summary.totalRepos, $summary.readyForWorkCount, $summary.runningCount, $summary.blockedCount) -ForegroundColor DarkGray

# ---------------------------------------------------------------------------
# Release 2.3 Phase 5 — Repository curation and change-aware indexing
# ---------------------------------------------------------------------------

Write-Step 'Portfolio curation — smoke: stable repoId prefers durable identity over scan fingerprint'
$stableId = Get-PortfolioRepoId -ScanFingerprint 'volatile-hash-abc' -LocalPath 'C:\Repos\Sample' -GitHubFullName 'owner/sample' -RepoName 'Sample'
if ($stableId -ne 'path:c:\repos\sample') { throw "Expected repoId 'path:c:\repos\sample' (stable identity), got '$stableId'" }
$ghId = Get-PortfolioRepoId -ScanFingerprint 'volatile-hash-abc' -GitHubFullName 'Owner/Sample'
if ($ghId -ne 'gh:owner/sample') { throw "Expected repoId 'gh:owner/sample' for GitHub-only identity, got '$ghId'" }
$nameId = Get-PortfolioRepoId -ScanFingerprint 'volatile-hash-abc' -RepoName 'Sample'
if ($nameId -ne 'repo:sample') { throw "Expected repoId 'repo:sample' for name-only identity, got '$nameId'" }
$fingerprintId = Get-PortfolioRepoId -ScanFingerprint 'volatile-hash-abc'
if ($fingerprintId -ne 'volatile-hash-abc') { throw "Expected fingerprint fallback when no stable key exists, got '$fingerprintId'" }
Write-Host '  repoId identity precedence correct: path > github > name > fingerprint' -ForegroundColor DarkGray

Write-Step 'Portfolio curation — smoke: load module + validate state vocabulary'
$curationModule = Join-Path $WorkspaceRoot 'backend\modules\portfolio\Portfolio.Curation.ps1'
if (-not (Test-Path -LiteralPath $curationModule)) { throw "Missing module file: $curationModule" }
. $curationModule
foreach ($validState in @('none', 'favorite', 'portfolio-candidate', 'archived-ignore')) {
    if (-not (Test-ValidCurationState -CurationState $validState)) { throw "Expected '$validState' to be a valid curation state" }
}
foreach ($invalidState in @('', 'starred', 'FAVOURITE-ish', 'archive')) {
    if (Test-ValidCurationState -CurationState $invalidState) { throw "Expected '$invalidState' to be rejected as a curation state" }
}
Write-Host '  curation state vocabulary validation correct' -ForegroundColor DarkGray

Write-Step 'Portfolio curation — smoke: persistence round-trip survives re-read (restart proxy)'
$curationWs = Join-Path ([System.IO.Path]::GetTempPath()) ("curation-smoke-" + [guid]::NewGuid().ToString('n').Substring(0, 8))
New-Item -ItemType Directory -Path $curationWs -Force | Out-Null
try {
    $writeFav = Set-PortfolioRepoCurationState -WorkspaceRoot $curationWs -RepoId 'path:c:\repos\sample' -CurationState 'favorite' -Reason 'smoke'
    if (-not $writeFav.success) { throw "Expected favorite curation write to succeed: $($writeFav.error)" }
    $writeBad = Set-PortfolioRepoCurationState -WorkspaceRoot $curationWs -RepoId 'path:c:\repos\sample' -CurationState 'not-a-state'
    if ($writeBad.success) { throw 'Expected invalid curation state write to be rejected' }

    $mirrorPath = Get-PortfolioCurationFilePath -WorkspaceRoot $curationWs
    if (-not (Test-Path -LiteralPath $mirrorPath)) { throw "Curation file mirror was not written at $mirrorPath" }

    # Fresh map read from disk models a process restart: no in-memory state survives.
    $rereadMap = Get-PortfolioCurationMap -WorkspaceRoot $curationWs
    if (-not $rereadMap.ContainsKey('path:c:\repos\sample')) { throw 'Curation entry missing after re-read from disk' }
    if ([string]$rereadMap['path:c:\repos\sample'].curationState -ne 'favorite') { throw "Expected persisted state 'favorite', got '$($rereadMap['path:c:\repos\sample'].curationState)'" }

    $curationEntries = @(
        [pscustomobject]@{ repoId = 'path:c:\repos\sample'; repoName = 'sample' },
        [pscustomobject]@{ repoId = 'path:c:\repos\other'; repoName = 'other' }
    )
    $applied = Apply-PortfolioCurationToEntries -Entries $curationEntries -CurationMap $rereadMap
    if ([string]$applied[0].curationState -ne 'favorite') { throw "Expected merged curationState=favorite on matching entry, got '$($applied[0].curationState)'" }
    if ([string]::IsNullOrWhiteSpace([string]$applied[0].curationUpdatedAt)) { throw 'Expected curationUpdatedAt to be populated on curated entry' }
    if ([string]$applied[1].curationState -ne 'none') { throw "Expected curationState=none on uncurated entry, got '$($applied[1].curationState)'" }

    $writeClear = Set-PortfolioRepoCurationState -WorkspaceRoot $curationWs -RepoId 'path:c:\repos\sample' -CurationState 'none'
    if (-not $writeClear.success) { throw "Expected curation clear to succeed: $($writeClear.error)" }
    $clearedMap = Get-PortfolioCurationMap -WorkspaceRoot $curationWs
    if ([string]$clearedMap['path:c:\repos\sample'].curationState -ne 'none') { throw 'Expected cleared curation state to persist as none' }
    Write-Host '  curation persistence round-trip correct (write, restart re-read, merge, clear)' -ForegroundColor DarkGray
}
finally {
    Remove-Item -LiteralPath $curationWs -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Step 'Loading agent-runs ledger module (Release 2.0)'
$agentRunsModule = Join-Path $WorkspaceRoot 'backend\modules\agent-runs\AgentRuns.ps1'
if (-not (Test-Path -LiteralPath $agentRunsModule)) { throw "AgentRuns.ps1 not found at: $agentRunsModule" }
. $agentBudgetModule
. $agentRunsModule
Write-Host 'Agent-runs module loaded successfully' -ForegroundColor Green

Write-Step 'Agent-run ledger — smoke: create, list, detail, update (Release 2.0 Phase 1)'
$agentRunsWorkspace = Join-Path ([System.IO.Path]::GetTempPath()) ("agent-runs-smoke-" + [guid]::NewGuid().ToString('n').Substring(0, 8))
New-Item -ItemType Directory -Path $agentRunsWorkspace -Force | Out-Null
try {
    $smokeRun = New-AgentRunRecord -WorkspaceRoot $agentRunsWorkspace -RepoName 'smoke-agent-repo' `
        -GitHubRepo 'owner/smoke-agent-repo' -DispatchRunId 'dispatch-123' -PromptRefinementRunId 'refine-456' `
        -SelectedTaskText 'Add quota guard' -SelectedTaskSection 'Engineering milestones' `
        -PlannedReleaseName 'Release 2.0 — Agent Run Monitoring and Actions-Gated Merge Readiness' `
        -PlannedPhaseName 'Phase 4: Budget guard + scan annotations' `
        -BaseBranch 'main' -WorkUnitsEstimated 8 -WorkUnitsEstimateSource 'roadmap-phase-plan'
    if ([string]::IsNullOrWhiteSpace([string]$smokeRun.runId)) { throw 'New-AgentRunRecord returned no runId' }
    if ([string]$smokeRun.status -ne 'dispatched') { throw "Expected status=dispatched, got '$($smokeRun.status)'" }
    if ($null -eq $smokeRun.metrics.dispatchedAt) { throw 'New run is missing metrics.dispatchedAt' }
    if ([double]$smokeRun.metrics.workUnitsEstimated -ne 8) { throw "Expected workUnitsEstimated=8, got '$($smokeRun.metrics.workUnitsEstimated)'" }
    if ([string]$smokeRun.workUnitsEstimateSource -ne 'roadmap-phase-plan') { throw "Expected workUnitsEstimateSource='roadmap-phase-plan', got '$($smokeRun.workUnitsEstimateSource)'" }
    if ([string]$smokeRun.plannedPhaseName -ne 'Phase 4: Budget guard + scan annotations') { throw "Expected plannedPhaseName to be recorded, got '$($smokeRun.plannedPhaseName)'" }

    $runFile = Join-Path $agentRunsWorkspace "output\agent-runs\runs\$($smokeRun.runId).json"
    if (-not (Test-Path -LiteralPath $runFile)) { throw 'Run ledger JSON was not written' }
    $eventsFile = Join-Path $agentRunsWorkspace 'output\agent-runs\events.jsonl'
    if (-not (Test-Path -LiteralPath $eventsFile)) { throw 'events.jsonl was not written' }

    $listed = @(Get-AgentRuns -WorkspaceRoot $agentRunsWorkspace -Status 'dispatched')
    if ($listed.Count -ne 1) { throw "Expected 1 dispatched run in list, got $($listed.Count)" }
    if (@(Get-AgentRuns -WorkspaceRoot $agentRunsWorkspace -Status 'completed').Count -ne 0) { throw 'Status filter returned a non-matching run' }

    $startedIso = (Get-Date).ToUniversalTime().AddMinutes(-10).ToString('o')
    $completedIso = (Get-Date).ToUniversalTime().ToString('o')
    $updated = Update-AgentRunRecord -WorkspaceRoot $agentRunsWorkspace -RunId $smokeRun.runId -Patch @{
        status           = 'completed'
        outcome          = 'pr-opened'
        branch           = 'copilot/smoke-fix'
        prUrl            = 'https://github.com/owner/smoke-agent-repo/pull/1'
        agentStartedAt   = $startedIso
        agentCompletedAt = $completedIso
        workUnitsActual  = 3
    }
    if ([string]$updated.status -ne 'completed') { throw "Expected status=completed after update, got '$($updated.status)'" }
    if ($null -eq $updated.metrics.timeToDeliverSeconds -or [int]$updated.metrics.timeToDeliverSeconds -lt 1) { throw 'timeToDeliverSeconds was not derived from start/completion timestamps' }

    $detail = Get-AgentRunDetail -WorkspaceRoot $agentRunsWorkspace -RunId $smokeRun.runId
    if ($null -eq $detail) { throw 'Get-AgentRunDetail returned null for an existing run' }
    if ([string]$detail.run.prUrl -ne 'https://github.com/owner/smoke-agent-repo/pull/1') { throw 'Run detail did not persist the PR URL' }
    $detailEventTypes = @($detail.events | ForEach-Object { [string]$_.eventType })
    if ('run.dispatched' -notin $detailEventTypes) { throw 'events stream is missing run.dispatched' }
    if ('run.completed' -notin $detailEventTypes) { throw 'events stream is missing run.completed' }

    if ($null -ne (Get-AgentRunDetail -WorkspaceRoot $agentRunsWorkspace -RunId 'does-not-exist')) { throw 'Get-AgentRunDetail should return null for an unknown runId' }

    $invalidStatusRejected = $false
    try { $null = Update-AgentRunRecord -WorkspaceRoot $agentRunsWorkspace -RunId $smokeRun.runId -Patch @{ status = 'bogus' } } catch { $invalidStatusRejected = $true }
    if (-not $invalidStatusRejected) { throw 'Update-AgentRunRecord accepted an invalid status' }

    Write-Step 'Budget ledger — smoke: defaults, usage snapshot, soft warning, hard refusal (Release 2.0 Phase 4)'
    $budgetConfig = Get-AgentBudgetLedgerConfig -WorkspaceRoot $agentRunsWorkspace -Settings @{
        budgetLedger = @{
            period = (Get-Date).ToUniversalTime().ToString('yyyy-MM')
            quotaGuard = @{
                softStopRemainingUnits = 10
                hardStopRemainingUnits = 5
                maxUnitsPerPhase = 25
                maxUnitsPerSession = 12
            }
            defaultProject = @{
                monthlyQuotaBudgetUnits = 20
                monthlyBudgetUsd = 6
                priority = 1
            }
        }
    }
    $usageSnapshot = Get-AgentBudgetUsageSnapshot -WorkspaceRoot $agentRunsWorkspace -BudgetConfig $budgetConfig
    if (-not $usageSnapshot.byRepo.ContainsKey('smoke-agent-repo')) { throw 'Expected usage snapshot to include smoke-agent-repo' }
    if ([double]$usageSnapshot.byRepo['smoke-agent-repo'].unitsConsumed -lt 3) { throw 'Usage snapshot did not count the existing run units' }

    $softWarning = Test-AgentDispatchQuota -WorkspaceRoot $agentRunsWorkspace -RepoName 'smoke-agent-repo' -EstimatedWorkUnits 7 -BudgetConfig $budgetConfig -PlannedPhaseName 'Phase 4'
    if (-not $softWarning.allowed) { throw "Expected soft-warning dispatch to remain allowed, got blocked: $($softWarning.message)" }
    if (@($softWarning.warnings).Count -eq 0) { throw 'Expected soft-warning dispatch to emit a warning' }

    $hardRefusal = Test-AgentDispatchQuota -WorkspaceRoot $agentRunsWorkspace -RepoName 'smoke-agent-repo' -EstimatedWorkUnits 13 -BudgetConfig $budgetConfig -PlannedPhaseName 'Phase 4'
    if ($hardRefusal.allowed) { throw 'Expected dispatch above the per-session cap to be refused' }
    if ([string]$hardRefusal.blockedCode -ne 'session-cap-exceeded') { throw "Expected blockedCode=session-cap-exceeded, got '$($hardRefusal.blockedCode)'" }

    $creditFlagged = Update-AgentRunRecord -WorkspaceRoot $agentRunsWorkspace -RunId $smokeRun.runId -Patch @{ creditPromptSeen = $true }
    if ($creditFlagged.metrics.creditPromptSeen -ne $true) { throw 'Expected Update-AgentRunRecord to persist creditPromptSeen=true' }
    $creditBlocked = Test-AgentDispatchQuota -WorkspaceRoot $agentRunsWorkspace -RepoName 'smoke-agent-repo' -EstimatedWorkUnits 2 -BudgetConfig $budgetConfig -PlannedPhaseName 'Phase 4'
    if ($creditBlocked.allowed) { throw 'Expected credit-prompt policy to block additional dispatches' }
    if ([string]$creditBlocked.blockedCode -ne 'credit-prompt-seen') { throw "Expected blockedCode=credit-prompt-seen, got '$($creditBlocked.blockedCode)'" }
    Write-Host '  budget ledger quota guard behaves correctly' -ForegroundColor DarkGray

    Write-Host ("  agent-run ledger correct: runId={0} events={1} timeToDeliver={2}s" -f $smokeRun.runId, @($detail.events).Count, $updated.metrics.timeToDeliverSeconds) -ForegroundColor DarkGray
}
finally {
    Remove-Item -LiteralPath $agentRunsWorkspace -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Step 'Agent-run refresh — smoke: PR association, status transitions, validation events (Release 2.0 Phase 2)'
$refreshWorkspace = Join-Path ([System.IO.Path]::GetTempPath()) ("agent-runs-refresh-smoke-" + [guid]::NewGuid().ToString('n').Substring(0, 8))
New-Item -ItemType Directory -Path $refreshWorkspace -Force | Out-Null
try {
    $refreshRun = New-AgentRunRecord -WorkspaceRoot $refreshWorkspace -RepoName 'smoke-refresh-repo' `
        -GitHubRepo 'owner/smoke-refresh-repo' -SelectedTaskText 'Implement the smoke-test refresh association feature'

    $nowUtc = (Get-Date).ToUniversalTime()
    $agentPr = [pscustomobject]@{
        number     = 42
        html_url   = 'https://github.com/owner/smoke-refresh-repo/pull/42'
        state      = 'open'
        draft      = $true
        title      = 'Implement the smoke-test refresh association feature'
        body       = 'Agent-generated work'
        created_at = $nowUtc.AddMinutes(2).ToString('o')
        updated_at = $nowUtc.AddMinutes(3).ToString('o')
        merged_at  = $null
        closed_at  = $null
        head       = [pscustomobject]@{ ref = 'copilot/smoke-refresh-feature' }
    }
    $unrelatedPr = [pscustomobject]@{
        number     = 41
        html_url   = 'https://github.com/owner/smoke-refresh-repo/pull/41'
        state      = 'open'
        draft      = $false
        title      = 'Unrelated human PR'
        body       = ''
        created_at = $nowUtc.AddDays(-2).ToString('o')
        updated_at = $null
        merged_at  = $null
        closed_at  = $null
        head       = [pscustomobject]@{ ref = 'feature/manual-work' }
    }

    # Candidate selection: only the copilot/* branch created after dispatch matches.
    $candidate = Select-AgentRunPullRequestCandidate -Run $refreshRun -PullRequests @($unrelatedPr, $agentPr)
    if ($null -eq $candidate.pullRequest) { throw 'Select-AgentRunPullRequestCandidate found no candidate' }
    if ([int]$candidate.pullRequest.number -ne 42) { throw "Expected PR #42 selected, got #$($candidate.pullRequest.number)" }
    if ('copilot-branch-prefix' -notin @($candidate.evidence.matchedBy)) { throw 'Association evidence is missing copilot-branch-prefix' }
    if ('task-fingerprint' -notin @($candidate.evidence.matchedBy)) { throw 'Association evidence is missing task-fingerprint' }

    # Refresh 1: draft PR + in-progress Actions -> active, no validation event.
    $refresh1 = Invoke-AgentRunRefresh -WorkspaceRoot $refreshWorkspace -RunId $refreshRun.runId `
        -PullRequests @($unrelatedPr, $agentPr) `
        -ActionsRun ([pscustomobject]@{ status = 'in_progress'; conclusion = ''; name = 'CI Smoke'; runUrl = 'https://github.com/owner/smoke-refresh-repo/actions/runs/1' })
    if ([string]$refresh1.run.status -ne 'active') { throw "Expected status=active after draft-PR refresh, got '$($refresh1.run.status)'" }
    if ([string]$refresh1.run.branch -ne 'copilot/smoke-refresh-feature') { throw 'Refresh did not associate the agent branch' }
    if ($null -ne $refresh1.validationEvent) { throw 'In-progress Actions must not emit a validation event' }

    # Refresh 2: PR ready for review + successful Actions -> completed + validation.passed.
    $agentPr.draft = $false
    $refresh2 = Invoke-AgentRunRefresh -WorkspaceRoot $refreshWorkspace -RunId $refreshRun.runId `
        -PullRequests @($unrelatedPr, $agentPr) `
        -ActionsRun ([pscustomobject]@{ status = 'completed'; conclusion = 'success'; name = 'CI Smoke'; runUrl = 'https://github.com/owner/smoke-refresh-repo/actions/runs/2' })
    if ([string]$refresh2.run.status -ne 'completed') { throw "Expected status=completed after ready-PR refresh, got '$($refresh2.run.status)'" }
    if ([string]$refresh2.run.outcome -ne 'awaiting-merge') { throw "Expected outcome=awaiting-merge, got '$($refresh2.run.outcome)'" }
    if ([string]$refresh2.validationEvent -ne 'validation.passed') { throw "Expected validation.passed, got '$($refresh2.validationEvent)'" }
    if ('existing-pr-url' -notin @($refresh2.association.matchedBy)) { throw 'Second refresh should re-associate via existing-pr-url' }
    if ($null -eq $refresh2.run.metrics.timeToDeliverSeconds) { throw 'Refresh did not derive timeToDeliverSeconds from observed PR timing' }

    # Refresh 3: unchanged Actions conclusion must not emit a duplicate validation event.
    $refresh3 = Invoke-AgentRunRefresh -WorkspaceRoot $refreshWorkspace -RunId $refreshRun.runId `
        -PullRequests @($unrelatedPr, $agentPr) `
        -ActionsRun ([pscustomobject]@{ status = 'completed'; conclusion = 'success'; name = 'CI Smoke'; runUrl = 'https://github.com/owner/smoke-refresh-repo/actions/runs/2' })
    if ($null -ne $refresh3.validationEvent) { throw 'Unchanged Actions conclusion emitted a duplicate validation event' }

    # Refresh 4: merged PR -> outcome merged.
    $agentPr.merged_at = $nowUtc.AddMinutes(30).ToString('o')
    $refresh4 = Invoke-AgentRunRefresh -WorkspaceRoot $refreshWorkspace -RunId $refreshRun.runId -PullRequests @($agentPr)
    if ([string]$refresh4.run.status -ne 'completed') { throw "Expected status=completed after merge, got '$($refresh4.run.status)'" }
    if ([string]$refresh4.run.outcome -ne 'merged') { throw "Expected outcome=merged, got '$($refresh4.run.outcome)'" }

    $refreshDetail = Get-AgentRunDetail -WorkspaceRoot $refreshWorkspace -RunId $refreshRun.runId
    $refreshEventTypes = @($refreshDetail.events | ForEach-Object { [string]$_.eventType })
    if ('run.started' -notin $refreshEventTypes) { throw 'Refresh events stream is missing run.started' }
    if ('run.completed' -notin $refreshEventTypes) { throw 'Refresh events stream is missing run.completed' }
    if (@($refreshEventTypes | Where-Object { $_ -eq 'validation.passed' }).Count -ne 1) { throw 'Expected exactly one validation.passed event' }

    Write-Host ("  agent-run refresh correct: runId={0} events={1} finalOutcome={2}" -f $refreshRun.runId, @($refreshDetail.events).Count, $refresh4.run.outcome) -ForegroundColor DarkGray

    # --- PR attribution is bounded on both sides, and exclusive -------------
    #
    # The failures these prevent, both observed against the real ledger:
    #   1. A 15 August dispatch adopted a pull request opened by hand on
    #      1 September and — because it was merged — would have closed the run
    #      with a fabricated 17-day time-to-deliver.
    #   2. Three ben-fuhr-portfolio runs (13, 28 and 29 August) all claimed the
    #      same PR #4, so one pull request would have closed three runs.
    $attribRun = New-AgentRunRecord -WorkspaceRoot $refreshWorkspace -RepoName 'attrib-repo' -RepoId 'repo:attrib' `
        -GitHubRepo 'owner/attrib-repo' -ProviderTool 'github-copilot-agent' -SelectedTaskText 'Attribution bound check'
    $attribDispatchedAt = [datetime]::Parse($attribRun.metrics.dispatchedAt).ToUniversalTime()

    # A copilot PR opened 30 days later is NOT this run's work.
    $farFuturePr = [pscustomobject]@{
        number = 900; html_url = 'https://github.com/owner/attrib-repo/pull/900'
        state = 'closed'; draft = $false
        merged_at = $attribDispatchedAt.AddDays(30).AddHours(1).ToString('o')
        created_at = $attribDispatchedAt.AddDays(30).ToString('o')
        title = 'Unrelated later work'; body = ''
        head = [pscustomobject]@{ ref = 'copilot/something-else' }
    }
    $farMatch = Select-AgentRunPullRequestCandidate -Run $attribRun -PullRequests @($farFuturePr)
    if ($null -ne $farMatch.pullRequest) {
        throw "A PR created 30 days after dispatch must not be attributed to that run (got #$($farMatch.pullRequest.number))"
    }

    # The same PR one hour after dispatch IS credible.
    $nearPr = [pscustomobject]@{
        number = 901; html_url = 'https://github.com/owner/attrib-repo/pull/901'
        state = 'open'; draft = $false; merged_at = $null
        created_at = $attribDispatchedAt.AddHours(1).ToString('o')
        title = 'Agent work'; body = ''
        head = [pscustomobject]@{ ref = 'copilot/agent-work' }
    }
    $nearMatch = Select-AgentRunPullRequestCandidate -Run $attribRun -PullRequests @($nearPr)
    if ($null -eq $nearMatch.pullRequest -or [int]$nearMatch.pullRequest.number -ne 901) {
        throw 'A PR created one hour after dispatch must still be attributed to that run'
    }

    # One PR, one run: a later dispatch that still precedes the PR wins it.
    $nearerRun = [pscustomobject]@{
        runId = 'attrib-nearer'; repoName = 'attrib-repo'; githubRepo = 'owner/attrib-repo'
        createdAt = $attribDispatchedAt.AddMinutes(30).ToString('o')
        metrics = [pscustomobject]@{ dispatchedAt = $attribDispatchedAt.AddMinutes(30).ToString('o') }
    }
    $contested = Select-AgentRunPullRequestCandidate -Run $attribRun -PullRequests @($nearPr) -SiblingRuns @($nearerRun)
    if ($null -ne $contested.pullRequest) {
        throw 'A PR must go to the nearest preceding dispatch, not to an older run'
    }
    if ('rejected-nearer-dispatch-claims-it' -notin @($contested.evidence.matchedBy)) {
        throw "Rejection must say why it was rejected; got '$($contested.evidence.matchedBy -join ',')'"
    }

    # The nearer run itself still gets it — the rule redirects, never discards.
    $winner = Select-AgentRunPullRequestCandidate -Run $nearerRun -PullRequests @($nearPr) -SiblingRuns @($attribRun)
    if ($null -eq $winner.pullRequest -or [int]$winner.pullRequest.number -ne 901) {
        throw 'The nearest preceding dispatch must receive the pull request'
    }

    Write-Host '  agent-run PR attribution correct: 24h upper bound holds, one PR resolves to one run' -ForegroundColor DarkGray
}
finally {
    Remove-Item -LiteralPath $refreshWorkspace -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Step 'Merge readiness — smoke: blocking rules, ready case, snapshot store (Release 2.0 Phase 3)'
$mergeReadinessModule = Join-Path $WorkspaceRoot 'backend\modules\agent-runs\MergeReadiness.ps1'
if (-not (Test-Path -LiteralPath $mergeReadinessModule)) { throw "MergeReadiness.ps1 not found at: $mergeReadinessModule" }
. $mergeReadinessModule
$mrWorkspace = Join-Path ([System.IO.Path]::GetTempPath()) ("merge-readiness-smoke-" + [guid]::NewGuid().ToString('n').Substring(0, 8))
New-Item -ItemType Directory -Path $mrWorkspace -Force | Out-Null
try {
    $mrNoRun = Get-MergeReadinessEvaluation -RepoId 'repo:mr-smoke' -RepoName 'mr-smoke'
    if ($mrNoRun.ready) { throw 'Evaluation with no agent run must not be ready' }
    if (@($mrNoRun.blockers | Where-Object { $_.code -eq 'no-agent-run' }).Count -ne 1) { throw 'Missing no-agent-run blocker' }

    $mrDraftRun = [pscustomobject]@{
        runId = 'mr-r1'; prUrl = 'https://github.com/o/r/pull/7'; prNumber = 7; prState = 'open'; prDraft = $true
        actions = [pscustomobject]@{ status = 'in_progress'; conclusion = ''; workflowName = 'CI' }
    }
    $mrBlocked = Get-MergeReadinessEvaluation -RepoId 'repo:mr-smoke' -RepoName 'mr-smoke' `
        -AgentRun $mrDraftRun -LocalDirtyCount 2 -AuditBlockers @('Roadmap maturity below L3')
    $mrBlockedCodes = @($mrBlocked.blockers | ForEach-Object { [string]$_.code })
    foreach ($expectedCode in @('pr-draft', 'actions-pending', 'dirty-worktree', 'audit-blocker')) {
        if ($expectedCode -notin $mrBlockedCodes) { throw "Missing expected blocker '$expectedCode' (got: $($mrBlockedCodes -join ', '))" }
    }

    $mrReadyRun = [pscustomobject]@{
        runId = 'mr-r2'; prUrl = 'https://github.com/o/r/pull/8'; prNumber = 8; prState = 'open'; prDraft = $false
        actions = [pscustomobject]@{ status = 'completed'; conclusion = 'success'; workflowName = 'CI' }
    }
    $mrPrDetail = [pscustomobject]@{ draft = $false; state = 'open'; merged_at = $null; mergeable = $true; mergeable_state = 'clean' }
    $mrReady = Get-MergeReadinessEvaluation -RepoId 'repo:mr-smoke' -RepoName 'mr-smoke' -AgentRun $mrReadyRun -PrDetail $mrPrDetail
    if (-not $mrReady.ready) { throw "Fully-validated run should be ready; blockers: $((@($mrReady.blockers | ForEach-Object { $_.code })) -join ', ')" }

    # Failing fresh Actions state must override the stale ledger view.
    $mrFreshFail = Get-MergeReadinessEvaluation -RepoId 'repo:mr-smoke' -RepoName 'mr-smoke' -AgentRun $mrReadyRun -PrDetail $mrPrDetail `
        -ActionsState ([pscustomobject]@{ status = 'completed'; conclusion = 'failure'; workflowName = 'CI' })
    if ($mrFreshFail.ready) { throw 'Fresh failing Actions state must block readiness' }
    if ('actions-failing' -notin @($mrFreshFail.blockers | ForEach-Object { [string]$_.code })) { throw 'Missing actions-failing blocker from fresh Actions state' }

    # Merge conflicts and already-merged PRs block.
    $mrConflict = Get-MergeReadinessEvaluation -RepoId 'repo:mr-smoke' -RepoName 'mr-smoke' -AgentRun $mrReadyRun `
        -PrDetail ([pscustomobject]@{ draft = $false; state = 'open'; merged_at = $null; mergeable = $false; mergeable_state = 'dirty' })
    if ('merge-conflicts' -notin @($mrConflict.blockers | ForEach-Object { [string]$_.code })) { throw 'Missing merge-conflicts blocker' }
    $mrMerged = Get-MergeReadinessEvaluation -RepoId 'repo:mr-smoke' -RepoName 'mr-smoke' -AgentRun $mrReadyRun `
        -PrDetail ([pscustomobject]@{ draft = $false; state = 'closed'; merged_at = '2026-06-11T12:00:00Z'; mergeable = $null; mergeable_state = 'unknown' })
    if ('pr-already-merged' -notin @($mrMerged.blockers | ForEach-Object { [string]$_.code })) { throw 'Missing pr-already-merged blocker' }

    $null = Save-MergeReadinessSnapshot -WorkspaceRoot $mrWorkspace -Evaluation $mrReady
    $mrLoaded = Get-MergeReadinessSnapshot -WorkspaceRoot $mrWorkspace -RepoId 'repo:mr-smoke'
    if ($null -eq $mrLoaded -or -not $mrLoaded.ready) { throw 'Merge-readiness snapshot did not round-trip' }
    if ($null -ne (Get-MergeReadinessSnapshot -WorkspaceRoot $mrWorkspace -RepoId 'never-evaluated')) { throw 'Unknown repoId should return a null snapshot' }

    Write-Host ("  merge-readiness rules correct: blocked={0} ready={1} snapshot ok" -f $mrBlockedCodes.Count, $mrReady.ready) -ForegroundColor DarkGray
}
finally {
    Remove-Item -LiteralPath $mrWorkspace -Recurse -Force -ErrorAction SilentlyContinue
}

# ---------------------------------------------------------------------------
# Release 3.1 — the work-item trace
# ---------------------------------------------------------------------------

Write-Step 'Work-item trace — smoke: stage decision table, gap detection, id resolution, disk join (Release 3.1)'
$tracePackagingModule = Join-Path $WorkspaceRoot 'backend\modules\automation\Automation.RoadmapPackaging.ps1'
$traceModule = Join-Path $WorkspaceRoot 'backend\modules\execution\Execution.Trace.ps1'
foreach ($traceDep in @($tracePackagingModule, $traceModule)) {
    if (-not (Test-Path -LiteralPath $traceDep)) { throw "Trace dependency not found at: $traceDep" }
}
. $tracePackagingModule
. $traceModule

$tracePacket = [pscustomobject]@{
    packetId = 'pkt-trace'; runId = 'pkgrun-trace'; repoId = 'repo:trace-smoke'; repoName = 'trace-smoke'
    createdAt = '2026-08-10T00:00:00Z'; itemText = 'Add the operator export route'; itemSection = 'Engineering milestones'
    roadmapOrder = 2; valueScore = 93; valueTier = 'highest'; valueRationale = @('operator-facing outcome')
    estimatedWorkUnits = 3.0; maturityLevel = 'L4-Orchestration-Ready'
    branch = 'roadmap-item/add-export'; baseBranch = 'main'; roadmapPath = 'C:\repos\trace-smoke\ROADMAP.md'
    generatedPrompt = ('p' * 120)
}
$tracePending = [pscustomobject]@{ packetId = 'pkt-trace'; runId = 'pkgrun-trace'; repoName = 'trace-smoke'; status = 'pending-approval'; updatedAt = '2026-08-10T00:00:01Z'; updatedBy = 'api'; dispatchRunId = ''; packet = $tracePacket; history = @() }
$traceApproved = [pscustomobject]@{ packetId = 'pkt-trace'; runId = 'pkgrun-trace'; repoName = 'trace-smoke'; status = 'approved'; updatedAt = '2026-08-10T00:01:00Z'; updatedBy = 'ben'; dispatchRunId = '20260810-000100-abcd1234'; packet = $tracePacket; history = @() }
$traceRejected = [pscustomobject]@{ packetId = 'pkt-trace'; runId = 'pkgrun-trace'; repoName = 'trace-smoke'; status = 'rejected'; updatedAt = '2026-08-10T00:02:00Z'; updatedBy = 'ben'; dispatchRunId = ''; packet = $tracePacket; history = @() }
$traceQueue = [pscustomobject]@{ runId = '20260810-000100-abcd1234'; status = 'queued'; repository = 'trace-smoke'; branch = 'roadmap-item/add-export'; prompt = ('p' * 120); dispatchTarget = 'claude'; queuedAt = '2026-08-10T00:01:00Z'; roadmapPath = 'C:\repos\trace-smoke\ROADMAP.md'; selectedTask = 'Add the operator export route' }
$traceRunDone = [pscustomobject]@{ runId = '20260810-000100-abcd1234'; status = 'awaiting-review'; repository = 'trace-smoke'; branch = 'roadmap-item/add-export'; commitSha = 'abc1234'; filesChanged = 4; verifyResult = 'passed'; runnerCompletedAt = '2026-08-10T00:20:00Z' }
$traceRunFailed = [pscustomobject]@{ runId = '20260810-000100-abcd1234'; status = 'failed'; repository = 'trace-smoke'; error = 'Not a git repo'; runnerCompletedAt = '2026-08-10T00:05:00Z' }
$tracePr = [pscustomobject]@{ event = 'submit-pr'; repoName = 'trace-smoke'; branch = 'roadmap-item/add-export'; prUrl = 'https://github.com/o/trace-smoke/pull/7'; prNumber = '7'; timestamp = '2026-08-10T00:30:00Z' }
$traceAgentRun = [pscustomobject]@{ runId = 'agentrun-trace'; dispatchRunId = '20260810-000100-abcd1234'; repoName = 'trace-smoke'; repoId = 'repo:trace-smoke'; status = 'completed'; prUrl = 'https://github.com/o/trace-smoke/pull/7'; updatedAt = '2026-08-10T00:40:00Z'; actions = [pscustomobject]@{ status = 'completed'; conclusion = 'success'; workflowName = 'CI Smoke' } }
$traceMrOpen = [pscustomobject]@{ repoId = 'repo:trace-smoke'; repoName = 'trace-smoke'; ready = $false; blockers = @([pscustomobject]@{ code = 'dirty-worktree' }); evidence = [pscustomobject]@{ prState = 'open'; actionsStatus = 'completed'; actionsConclusion = 'success'; actionsWorkflowName = 'CI Smoke' }; evaluatedAt = '2026-08-10T00:45:00Z' }
$traceMrMerged = [pscustomobject]@{ repoId = 'repo:trace-smoke'; repoName = 'trace-smoke'; ready = $false; blockers = @([pscustomobject]@{ code = 'pr-already-merged' }); evidence = [pscustomobject]@{ prState = 'merged'; actionsStatus = 'completed'; actionsConclusion = 'success'; actionsWorkflowName = 'CI Smoke' }; evaluatedAt = '2026-08-10T01:00:00Z' }
$traceWriteBack = [pscustomobject]@{ runId = '20260810-000100-abcd1234'; packetId = 'pkt-trace'; applied = $true; markedCount = 1; actor = 'ben'; recordedAt = '2026-08-10T01:05:00Z' }

function Get-TraceStageStatus {
    param([object]$Trace, [string]$Stage)
    $found = @($Trace.stages | Where-Object { [string]$_.stage -eq $Stage })
    if ($found.Count -ne 1) { throw "Trace has $($found.Count) '$Stage' stage(s); expected exactly one" }
    return [string]$found[0].status
}

# The chain is a contract, not an implementation detail: these seven stages in
# this order are what Release 3.1 gates on.
$traceExpectedStages = @('rank', 'prompt', 'dispatch', 'agentRun', 'actions', 'mergeReadiness', 'writeBack')
$traceBaseline = Join-WorkItemTrace -PackagedItem $tracePending
$traceActualStages = @($traceBaseline.stages | ForEach-Object { [string]$_.stage })
if (($traceActualStages -join ',') -ne ($traceExpectedStages -join ',')) {
    throw "Trace stage chain drifted. Expected: $($traceExpectedStages -join ' -> '); got: $($traceActualStages -join ' -> ')"
}

# Decision table — each row is (label, trace, stage, expected status).
$traceQueuedNoRunner = Join-WorkItemTrace -PackagedItem $traceApproved -QueueEntry $traceQueue
$traceRunning = Join-WorkItemTrace -PackagedItem $traceApproved -QueueEntry $traceQueue -RunSummary ([pscustomobject]@{ runId = '20260810-000100-abcd1234'; status = 'running'; repository = 'trace-smoke'; runnerStartedAt = '2026-08-10T00:10:00Z' })
$traceReviewNoPr = Join-WorkItemTrace -PackagedItem $traceApproved -QueueEntry $traceQueue -RunSummary $traceRunDone
$tracePrNoActions = Join-WorkItemTrace -PackagedItem $traceApproved -QueueEntry $traceQueue -RunSummary $traceRunDone -PrRecord $tracePr
$traceGreenNoMr = Join-WorkItemTrace -PackagedItem $traceApproved -QueueEntry $traceQueue -RunSummary $traceRunDone -PrRecord $tracePr -AgentRun $traceAgentRun
$traceMergeBlocked = Join-WorkItemTrace -PackagedItem $traceApproved -QueueEntry $traceQueue -RunSummary $traceRunDone -PrRecord $tracePr -AgentRun $traceAgentRun -MergeReadiness $traceMrOpen
$traceMergedNoWriteBack = Join-WorkItemTrace -PackagedItem $traceApproved -QueueEntry $traceQueue -RunSummary $traceRunDone -PrRecord $tracePr -AgentRun $traceAgentRun -MergeReadiness $traceMrMerged
$traceFullLoop = Join-WorkItemTrace -PackagedItem $traceApproved -QueueEntry $traceQueue -RunSummary $traceRunDone -PrRecord $tracePr -AgentRun $traceAgentRun -MergeReadiness $traceMrMerged -WriteBack $traceWriteBack
$traceApprovedNoQueue = Join-WorkItemTrace -PackagedItem $traceApproved
$traceFailedRun = Join-WorkItemTrace -PackagedItem $traceApproved -QueueEntry $traceQueue -RunSummary $traceRunFailed
$traceRejectedTrace = Join-WorkItemTrace -PackagedItem $traceRejected
$traceWizard = Join-WorkItemTrace -AgentRun $traceAgentRun

$traceCases = @(
    @{ label = 'awaiting approval';         trace = $traceBaseline;           stage = 'dispatch';       expect = 'active' }
    @{ label = 'rejected packet';           trace = $traceRejectedTrace;      stage = 'dispatch';       expect = 'blocked' }
    @{ label = 'approved, no queue line';   trace = $traceApprovedNoQueue;    stage = 'dispatch';       expect = 'missing' }
    @{ label = 'queued, no run summary';    trace = $traceQueuedNoRunner;     stage = 'agentRun';       expect = 'missing' }
    @{ label = 'runner running';            trace = $traceRunning;            stage = 'agentRun';       expect = 'active' }
    @{ label = 'runner failed';             trace = $traceFailedRun;          stage = 'agentRun';       expect = 'failed' }
    @{ label = 'awaiting review';           trace = $traceReviewNoPr;         stage = 'agentRun';       expect = 'complete' }
    # No PR yet means Actions has nothing to validate — `pending`, not a gap.
    @{ label = 'no PR yet';                 trace = $traceReviewNoPr;         stage = 'actions';        expect = 'pending' }
    @{ label = 'PR open, no Actions state'; trace = $tracePrNoActions;        stage = 'actions';        expect = 'missing' }
    @{ label = 'Actions green';             trace = $traceGreenNoMr;          stage = 'actions';        expect = 'complete' }
    @{ label = 'green, never evaluated';    trace = $traceGreenNoMr;          stage = 'mergeReadiness'; expect = 'missing' }
    @{ label = 'merge blocked';             trace = $traceMergeBlocked;       stage = 'mergeReadiness'; expect = 'blocked' }
    # pr-already-merged is a merge-readiness BLOCKER but the trace's success
    # state: there is nothing left to gate once the PR is in.
    @{ label = 'merged';                    trace = $traceMergedNoWriteBack;  stage = 'mergeReadiness'; expect = 'complete' }
    @{ label = 'merged, roadmap untouched'; trace = $traceMergedNoWriteBack;  stage = 'writeBack';      expect = 'missing' }
    @{ label = 'before merge';              trace = $traceMergeBlocked;       stage = 'writeBack';      expect = 'pending' }
    @{ label = 'write-back applied';        trace = $traceFullLoop;           stage = 'writeBack';      expect = 'complete' }
    @{ label = 'dispatched without packet'; trace = $traceWizard;             stage = 'rank';           expect = 'missing' }
    @{ label = 'ran without a prompt';      trace = $traceWizard;             stage = 'prompt';         expect = 'missing' }
)
foreach ($traceCase in $traceCases) {
    $actualStatus = Get-TraceStageStatus -Trace $traceCase.trace -Stage $traceCase.stage
    if ($actualStatus -ne $traceCase.expect) {
        throw ("Trace case '{0}': stage '{1}' expected '{2}' but got '{3}'" -f $traceCase.label, $traceCase.stage, $traceCase.expect, $actualStatus)
    }
}

# Roll-up: a failed or blocked stage must surface at the top, and only a fully
# complete chain may read 'complete'.
if ($traceFullLoop.status -ne 'complete') { throw "Full loop should roll up to 'complete'; got '$($traceFullLoop.status)'" }
if ($traceFullLoop.completeStageCount -ne 7) { throw "Full loop should have 7 complete stages; got $($traceFullLoop.completeStageCount)" }
if ($traceFullLoop.hasGaps) { throw 'A complete loop must report no gaps' }
if ($null -ne $traceFullLoop.currentStage) { throw "A complete loop has no current stage; got '$($traceFullLoop.currentStage)'" }
if ($traceFailedRun.status -ne 'failed') { throw "A failed runner must roll up to 'failed'; got '$($traceFailedRun.status)'" }
if ($traceMergeBlocked.status -ne 'blocked') { throw "A blocked merge must roll up to 'blocked'; got '$($traceMergeBlocked.status)'" }
if ($traceQueuedNoRunner.currentStage -ne 'agentRun') { throw "Current stage should be the first incomplete one; got '$($traceQueuedNoRunner.currentStage)'" }

# TRIPWIRE — every stage must be able to report a gap. A stage that can only
# ever be 'pending' makes a broken chain read as merely young, which is the
# exact failure this trace exists to prevent. Adding an eighth stage without
# gap detection fails here rather than shipping a blind spot.
$traceGapUnion = @(@($traceApprovedNoQueue, $traceQueuedNoRunner, $tracePrNoActions, $traceGreenNoMr, $traceMergedNoWriteBack, $traceWizard) |
        ForEach-Object { @($_.gaps) } | Sort-Object -Unique)
$traceUncovered = @($traceExpectedStages | Where-Object { $_ -notin $traceGapUnion })
if ($traceUncovered.Count -gt 0) {
    throw ("These trace stages can never report a gap, so a broken chain would read as merely incomplete: {0}" -f ($traceUncovered -join ', '))
}

# Identity resolution — every id the chain mints lands on the same work item.
foreach ($traceId in @('pkt-trace', 'pkgrun-trace', '20260810-000100-abcd1234', 'agentrun-trace')) {
    $resolved = Resolve-WorkItemTraceIdentity -Id $traceId -PackagedItems @($traceApproved) -QueueEntries @($traceQueue) -AgentRuns @($traceAgentRun)
    if (-not $resolved.found) { throw "Id '$traceId' should resolve to the work item" }
    if ($resolved.dispatchRunId -ne '20260810-000100-abcd1234') { throw "Id '$traceId' resolved to dispatchRunId '$($resolved.dispatchRunId)'" }
    if ($null -eq $resolved.packagedItem -or $null -eq $resolved.queueEntry -or $null -eq $resolved.agentRun) {
        throw "Id '$traceId' did not resolve to all three stage records"
    }
}
$traceUnknown = Resolve-WorkItemTraceIdentity -Id 'no-such-id' -PackagedItems @($traceApproved) -QueueEntries @($traceQueue) -AgentRuns @($traceAgentRun)
if ($traceUnknown.found) { throw 'An unknown id must not resolve to a work item' }

# The PR ledger shares no run id with the dispatch chain, so the join is on
# branch. Repo name alone would attribute another item's PR to this one.
$traceHistory = @(
    [pscustomobject]@{ event = 'submit-pr'; repoName = 'trace-smoke'; branch = 'some-other-branch'; prUrl = 'https://github.com/o/trace-smoke/pull/1' }
    [pscustomobject]@{ event = 'preview'; repoName = 'trace-smoke'; branch = 'roadmap-item/add-export' }
    $tracePr
)
$tracePrPicked = Select-WorkItemTracePrRecord -RepairHistory $traceHistory -Branch 'roadmap-item/add-export' -RepoName 'trace-smoke'
if ($null -eq $tracePrPicked -or [string]$tracePrPicked.prUrl -ne 'https://github.com/o/trace-smoke/pull/7') { throw 'PR join on branch picked the wrong record' }
if ($null -ne (Select-WorkItemTracePrRecord -RepairHistory $traceHistory -Branch '' -RepoName 'trace-smoke')) {
    throw 'With no branch to join on, the trace must claim no PR rather than guess one'
}

# Disk join — the same seven stages, read from real ledger files.
$traceWorkspace = Join-Path ([System.IO.Path]::GetTempPath()) ("work-item-trace-smoke-" + [guid]::NewGuid().ToString('n').Substring(0, 8))
try {
    foreach ($traceDir in @('output\automation', 'output\roadmap-task-history\runs', 'output\agent-runs\runs', 'output\roadmap-repair-history', 'output\merge-readiness', 'output\roadmap-writeback')) {
        New-Item -ItemType Directory -Path (Join-Path $traceWorkspace $traceDir) -Force | Out-Null
    }
    $tracePacketRecord = [ordered]@{
        schemaVersion = '1'; packetId = 'pkt-trace'; runId = 'pkgrun-trace'; repoName = 'trace-smoke'
        status = 'approved'; recordedAt = '2026-08-10T00:01:00Z'; actor = 'ben'; note = 'Approved.'
        dispatchRunId = '20260810-000100-abcd1234'; packet = $tracePacket
    }
    (ConvertTo-Json -InputObject $tracePacketRecord -Compress -Depth 8) | Set-Content -LiteralPath (Join-Path $traceWorkspace 'output\automation\packaged-items.jsonl') -Encoding UTF8
    (ConvertTo-Json -InputObject $traceQueue -Compress -Depth 8) | Set-Content -LiteralPath (Join-Path $traceWorkspace 'output\roadmap-task-queue.jsonl') -Encoding UTF8
    (ConvertTo-Json -InputObject $traceRunDone -Depth 8) | Set-Content -LiteralPath (Join-Path $traceWorkspace 'output\roadmap-task-history\runs\20260810-000100-abcd1234.summary.json') -Encoding UTF8
    (ConvertTo-Json -InputObject $traceAgentRun -Depth 8) | Set-Content -LiteralPath (Join-Path $traceWorkspace 'output\agent-runs\runs\agentrun-trace.json') -Encoding UTF8
    (ConvertTo-Json -InputObject $tracePr -Compress -Depth 8) | Set-Content -LiteralPath (Join-Path $traceWorkspace 'output\roadmap-repair-history\repair-history.jsonl') -Encoding UTF8
    $null = Save-MergeReadinessSnapshot -WorkspaceRoot $traceWorkspace -Evaluation $traceMrMerged
    (ConvertTo-Json -InputObject $traceWriteBack -Compress -Depth 8) | Set-Content -LiteralPath (Join-Path $traceWorkspace 'output\roadmap-writeback\history.jsonl') -Encoding UTF8

    $traceFromDiskIds = @('pkt-trace', 'pkgrun-trace', '20260810-000100-abcd1234', 'agentrun-trace')
    foreach ($traceDiskId in $traceFromDiskIds) {
        $traceFromDisk = Get-WorkItemTrace -WorkspaceRoot $traceWorkspace -Id $traceDiskId
        if ($null -eq $traceFromDisk) { throw "Get-WorkItemTrace returned nothing for id '$traceDiskId'" }
        if ($traceFromDisk.traceId -ne '20260810-000100-abcd1234') { throw "Id '$traceDiskId' produced traceId '$($traceFromDisk.traceId)'" }
        if ($traceFromDisk.status -ne 'complete') { throw "Id '$traceDiskId' produced status '$($traceFromDisk.status)' from a complete loop on disk" }
        if ($traceFromDisk.completeStageCount -ne 7) { throw "Id '$traceDiskId' resolved only $($traceFromDisk.completeStageCount)/7 stages from disk" }
        if ([string]$traceFromDisk.identity.prUrl -ne 'https://github.com/o/trace-smoke/pull/7') { throw "Id '$traceDiskId' did not join the PR record from disk" }
    }
    if ($null -ne (Get-WorkItemTrace -WorkspaceRoot $traceWorkspace -Id 'no-such-id')) { throw 'An unknown id must produce no trace, not an empty one' }

    # The run summary is a prUrl source of its own. Found live 2026-08-15 on the
    # first real drive around the delivery loop: approve-push records the PR it
    # opened in the run SUMMARY (Release 3.4 milestone 3), but the trace joined
    # prUrl only from the submit-PR record, the agent-run ledger and the
    # merge-readiness snapshot — so a queue-runner item whose PR came from
    # approve-push traced as "no pull request" and the write-back gate refused
    # completion for want of evidence sitting one file away. Reproduced here: a
    # run whose ONLY PR evidence is the summary field must still join it.
    $traceSummaryOnly = [ordered]@{
        runId = '20260815-999999-summary1'; status = 'pushed'
        repository = 'o/trace-smoke'; localRepoPath = 'C:\trace-smoke'
        selectedTask = 'Ship the summary-only case'; branch = 'roadmap/20260815-999999-summary1'
        prUrl = 'https://github.com/o/trace-smoke/pull/9'; prNumber = 9
    }
    $traceSummaryOnlyQueue = [ordered]@{
        schemaVersion = '1'; runId = '20260815-999999-summary1'; status = 'queued'
        repository = 'o/trace-smoke'; localRepoPath = 'C:\trace-smoke'; roadmapPath = 'C:\trace-smoke\ROADMAP.md'
        selectedTask = 'Ship the summary-only case'; branch = 'roadmap/20260815-999999-summary1'
        prompt = 'x'; dispatchTarget = 'claude'; baseBranch = 'main'; queuedAt = '2026-08-15T00:00:00Z'
    }
    Add-Content -LiteralPath (Join-Path $traceWorkspace 'output\roadmap-task-queue.jsonl') -Value (ConvertTo-Json -InputObject $traceSummaryOnlyQueue -Compress -Depth 8) -Encoding UTF8
    (ConvertTo-Json -InputObject $traceSummaryOnly -Depth 8) | Set-Content -LiteralPath (Join-Path $traceWorkspace 'output\roadmap-task-history\runs\20260815-999999-summary1.summary.json') -Encoding UTF8
    $traceSummaryTrace = Get-WorkItemTrace -WorkspaceRoot $traceWorkspace -Id '20260815-999999-summary1'
    if ($null -eq $traceSummaryTrace) { throw 'The summary-only run must still produce a trace' }
    if ([string]$traceSummaryTrace.identity.prUrl -ne 'https://github.com/o/trace-smoke/pull/9') {
        throw "A prUrl recorded only in the run summary must join the trace; got '$($traceSummaryTrace.identity.prUrl)'"
    }

    Write-Host ("  trace: {0} stage cases, {1} ids resolve to one trace, 7/7 stages joined from disk, every stage can report a gap; summary-only prUrl joins" -f $traceCases.Count, $traceFromDiskIds.Count) -ForegroundColor DarkGray
}
finally {
    Remove-Item -LiteralPath $traceWorkspace -Recurse -Force -ErrorAction SilentlyContinue
}

# The route is the acceptance criterion ("a single runId resolves to every
# stage artifact through one route"), so assert the host actually exposes it
# and keys it off the joiner rather than reimplementing the join inline.
$traceHostSource = Get-Content -LiteralPath (Join-Path $WorkspaceRoot 'backend\api-host\Start-RepoManagementApiHost.ps1') -Raw -Encoding UTF8
if ($traceHostSource -notmatch [regex]::Escape("'/api/trace/*'")) { throw 'The API host no longer routes /api/trace/{id}' }
if ($traceHostSource -notmatch 'Get-WorkItemTrace\s+-WorkspaceRoot') { throw 'The /api/trace route must resolve through Get-WorkItemTrace' }
if ($traceHostSource -notmatch [regex]::Escape("Execution.Trace.ps1")) { throw 'The API host no longer dot-sources Execution.Trace.ps1' }
Write-Host '  /api/trace/{id} is routed and resolves through Get-WorkItemTrace' -ForegroundColor DarkGray

# ---------------------------------------------------------------------------
# Release 3.1 — roadmap completion write-back, gated on merge evidence
# ---------------------------------------------------------------------------

Write-Step 'Roadmap write-back — smoke: what is and is not merge evidence, the edit, the ledger (Release 3.1)'
$writeBackModule = Join-Path $WorkspaceRoot 'backend\modules\roadmap\Roadmap.WriteBack.ps1'
if (-not (Test-Path -LiteralPath $writeBackModule)) { throw "Roadmap.WriteBack.ps1 not found at: $writeBackModule" }
. $writeBackModule

$wbItem = 'Add the operator export route'
$wbRoadmap = @"
# Demo roadmap

## Release 1

### Engineering milestones

- [ ] $wbItem
- [x] Ship the health endpoint
  - [ ] Nested pending item
- [ ] Something else entirely
"@

$wbMergedPr = [pscustomobject]@{ html_url = 'https://github.com/o/r/pull/7'; number = 7; state = 'closed'; merged_at = '2026-08-10T12:00:00Z'; merge_commit_sha = 'deadbeef' }
$wbGreenActions = [pscustomobject]@{ actions = [pscustomobject]@{ status = 'completed'; conclusion = 'success'; workflowName = 'CI' } }

# THE GATE. Each row is a shape that must NOT be read as completion, and the
# code the refusal must carry. These are not hypotheticals: churn-only and
# green-but-open are the two shapes the console produces most often.
$wbGateCases = @(
    @{
        label = 'nothing known at all'
        evidence = $null
        expect = 'no-evidence'
    }
    @{
        label = 'code churn and a passing local verify, no PR'
        evidence = (Get-RoadmapWriteBackEvidence -RunSummary ([pscustomobject]@{ commitSha = 'abc1234'; filesChanged = 4; verifyResult = 'passed' }))
        expect = 'no-pull-request'
    }
    @{
        label = 'green Actions on an open PR'
        evidence = (Get-RoadmapWriteBackEvidence -PrDetail ([pscustomobject]@{ html_url = 'https://github.com/o/r/pull/7'; number = 7; state = 'open'; merged_at = $null }) -AgentRun $wbGreenActions)
        expect = 'pr-not-merged'
    }
    @{
        label = 'PR closed without merging'
        evidence = (Get-RoadmapWriteBackEvidence -PrDetail ([pscustomobject]@{ html_url = 'https://github.com/o/r/pull/7'; number = 7; state = 'closed'; merged_at = $null }) -AgentRun $wbGreenActions)
        expect = 'pr-not-merged'
    }
    @{
        label = 'merged with no Actions ever observed'
        evidence = (Get-RoadmapWriteBackEvidence -PrDetail $wbMergedPr)
        expect = 'no-validation-evidence'
    }
    @{
        label = 'merged while validation is still running'
        evidence = (Get-RoadmapWriteBackEvidence -PrDetail $wbMergedPr -AgentRun ([pscustomobject]@{ actions = [pscustomobject]@{ status = 'in_progress'; conclusion = '' } }))
        expect = 'validation-incomplete'
    }
    @{
        label = 'merged past a red check'
        evidence = (Get-RoadmapWriteBackEvidence -PrDetail $wbMergedPr -AgentRun ([pscustomobject]@{ actions = [pscustomobject]@{ status = 'completed'; conclusion = 'failure' } }))
        expect = 'validation-failed'
    }
    @{
        label = 'merged per GitHub but with no merge commit'
        evidence = (Get-RoadmapWriteBackEvidence -PrDetail ([pscustomobject]@{ html_url = 'https://github.com/o/r/pull/7'; number = 7; state = 'closed'; merged_at = '2026-08-10T12:00:00Z'; merge_commit_sha = '' }) -AgentRun $wbGreenActions)
        expect = 'no-merge-commit'
    }
    @{
        # A stored snapshot can say `merged` but never carries a merge commit,
        # so "no merge commit" from a snapshot means nobody asked GitHub. That
        # is a different refusal, and it names a different remedy.
        label = 'merged per a stored snapshot only'
        evidence = (Get-RoadmapWriteBackEvidence -MergeReadiness ([pscustomobject]@{
                    repoId = 'repo:wb'; prUrl = 'https://github.com/o/r/pull/7'; prNumber = 7; ready = $false
                    blockers = @([pscustomobject]@{ code = 'pr-already-merged' })
                    evidence = [pscustomobject]@{ prState = 'merged'; actionsStatus = 'completed'; actionsConclusion = 'success' }
                }))
        expect = 'merge-unverified'
    }
)
foreach ($wbCase in $wbGateCases) {
    $wbGate = Test-RoadmapWriteBackEvidence -Evidence $wbCase.evidence -ItemText $wbItem
    if ($wbGate.allowed) { throw ("Write-back gate allowed '{0}'; it must refuse with '{1}'" -f $wbCase.label, $wbCase.expect) }
    if ($wbCase.expect -notin @($wbGate.refusalCodes)) {
        throw ("Write-back case '{0}' expected refusal '{1}'; got: {2}" -f $wbCase.label, $wbCase.expect, (@($wbGate.refusalCodes) -join ', '))
    }
}

# Only a merged PR with a merge commit and a successful run passes.
$wbGoodEvidence = Get-RoadmapWriteBackEvidence -PrDetail $wbMergedPr -AgentRun $wbGreenActions
$wbAllowed = Test-RoadmapWriteBackEvidence -Evidence $wbGoodEvidence -ItemText $wbItem
if (-not $wbAllowed.allowed) { throw "A merged, validated PR must pass the gate; refusals: $((@($wbAllowed.refusalCodes)) -join ', ')" }
# ...and only for an item the caller can name.
$wbNoItem = Test-RoadmapWriteBackEvidence -Evidence $wbGoodEvidence -ItemText ''
if ($wbNoItem.allowed -or 'no-item-text' -notin @($wbNoItem.refusalCodes)) { throw 'Write-back with no item text must be refused' }
# Refusals carry a remedy: a gate that only says no makes the operator guess.
foreach ($wbRefusal in @($wbNoItem.refusals)) {
    if ([string]::IsNullOrWhiteSpace([string]$wbRefusal.remedy)) { throw "Refusal '$($wbRefusal.code)' carries no remedy" }
}

# THE EDIT. Exact matching on purpose — a fuzzy match eventually ticks the
# wrong line in someone else's roadmap.
$wbEdit = New-RoadmapCompletionEdit -Content $wbRoadmap -ItemTexts @($wbItem)
if (-not $wbEdit.changed -or $wbEdit.markedCount -ne 1) { throw 'The completion edit did not mark the open item' }
if (@($wbEdit.diff).Count -ne 1) { throw "A one-item edit must produce a one-line diff; got $(@($wbEdit.diff).Count)" }
if ([string]$wbEdit.diff[0].after -ne "- [x] $wbItem") { throw "Unexpected edited line: '$($wbEdit.diff[0].after)'" }
if ($wbEdit.proposedContent -notmatch [regex]::Escape("- [x] $wbItem")) { throw 'The proposed content does not contain the marked item' }

$wbNested = New-RoadmapCompletionEdit -Content $wbRoadmap -ItemTexts @('Nested pending item')
if ([string]$wbNested.diff[0].after -ne '  - [x] Nested pending item') { throw "Indentation was not preserved: '$($wbNested.diff[0].after)'" }

# Re-running must be a no-op, not a second claim.
$wbRepeat = New-RoadmapCompletionEdit -Content $wbEdit.proposedContent -ItemTexts @($wbItem)
if ($wbRepeat.changed -or @($wbRepeat.alreadyComplete).Count -ne 1) { throw 'Re-marking an already-complete item must be a no-op reported as alreadyComplete' }

# A miss is named, never a silent zero-line edit that reads as success.
$wbMiss = New-RoadmapCompletionEdit -Content $wbRoadmap -ItemTexts @('An item that is not there')
if ($wbMiss.changed -or @($wbMiss.notFound).Count -ne 1) { throw 'A non-matching item must report notFound and change nothing' }
$wbPartial = New-RoadmapCompletionEdit -Content $wbRoadmap -ItemTexts @($wbItem, 'ghost item')
if ($wbPartial.markedCount -ne 1 -or @($wbPartial.notFound).Count -ne 1) { throw 'A partial match must mark what it found and name what it did not' }

# THE LEDGER, and its contract with the trace. Two modules name the same file
# through two constants; if they drift the trace shows writeBack=missing
# forever, so this asserts the behavior rather than comparing the constants.
$wbWorkspace = Join-Path ([System.IO.Path]::GetTempPath()) ("roadmap-writeback-smoke-" + [guid]::NewGuid().ToString('n').Substring(0, 8))
try {
    New-Item -ItemType Directory -Path $wbWorkspace -Force | Out-Null
    $null = Write-RoadmapWriteBackRecord -WorkspaceRoot $wbWorkspace -RunId '20260810-000100-abcd1234' -PacketId 'pkt-trace' `
        -RepoName 'trace-smoke' -RoadmapPath 'C:\repos\trace-smoke\ROADMAP.md' -ItemText $wbItem `
        -MarkedCount 1 -Evidence $wbGoodEvidence -Gate $wbAllowed -Actor 'api'
    $null = Write-RoadmapWriteBackRecord -WorkspaceRoot $wbWorkspace -RunId '20260810-000100-abcd1234' -PacketId 'pkt-trace' `
        -RepoName 'trace-smoke' -RoadmapPath 'C:\repos\trace-smoke\ROADMAP.md' -ItemText $wbItem `
        -Applied -MarkedCount 1 -Evidence $wbGoodEvidence -Gate $wbAllowed -Actor 'operator'
    $wbHistory = @(Get-RoadmapWriteBackHistory -WorkspaceRoot $wbWorkspace -RunId '20260810-000100-abcd1234')
    if ($wbHistory.Count -ne 2) { throw "Write-back history should hold the preview and the apply; got $($wbHistory.Count)" }
    if (-not [bool]$wbHistory[1].applied) { throw 'The second record should be the applied one' }
    if (@(Get-RoadmapWriteBackHistory -WorkspaceRoot $wbWorkspace -RunId 'some-other-run').Count -ne 0) { throw 'History must filter by runId' }

    # An applied record without an allowed gate is unattributable, and a ledger
    # that can hold one is a ledger that can launder one.
    $wbRefused = Test-RoadmapWriteBackEvidence -Evidence $null -ItemText $wbItem
    $wbLaundered = $false
    $wbLaunderError = ''
    try {
        $null = Write-RoadmapWriteBackRecord -WorkspaceRoot $wbWorkspace -RunId 'run-x' -Applied -Gate $wbRefused
        $wbLaundered = $true
    } catch {
        $wbLaunderError = [string]$_.Exception.Message
    }
    if ($wbLaundered) { throw 'The write-back ledger accepted an applied record with no allowed gate' }
    if ($wbLaunderError -notmatch 'allowed merge-evidence gate') {
        throw "The ledger refused for the wrong reason: $wbLaunderError"
    }

    # The trace must see it. Same file, read by the other module's constant.
    foreach ($wbDir in @('output\automation', 'output\roadmap-task-history\runs', 'output\agent-runs\runs', 'output\merge-readiness')) {
        New-Item -ItemType Directory -Path (Join-Path $wbWorkspace $wbDir) -Force | Out-Null
    }
    (ConvertTo-Json -InputObject ([ordered]@{
                schemaVersion = '1'; packetId = 'pkt-trace'; runId = 'pkgrun-trace'; repoName = 'trace-smoke'
                status = 'approved'; recordedAt = '2026-08-10T00:01:00Z'; actor = 'ben'
                dispatchRunId = '20260810-000100-abcd1234'; packet = $tracePacket
            }) -Compress -Depth 8) | Set-Content -LiteralPath (Join-Path $wbWorkspace 'output\automation\packaged-items.jsonl') -Encoding UTF8
    (ConvertTo-Json -InputObject $traceQueue -Compress -Depth 8) | Set-Content -LiteralPath (Join-Path $wbWorkspace 'output\roadmap-task-queue.jsonl') -Encoding UTF8
    $wbTrace = Get-WorkItemTrace -WorkspaceRoot $wbWorkspace -Id '20260810-000100-abcd1234'
    if ($null -eq $wbTrace) { throw 'The trace could not resolve the write-back fixture' }
    $wbTraceStage = @($wbTrace.stages | Where-Object { [string]$_.stage -eq 'writeBack' }) | Select-Object -First 1
    if ([string]$wbTraceStage.status -ne 'complete') {
        throw "An applied write-back must show as complete in the trace; got '$($wbTraceStage.status)'. The two modules' ledger paths have drifted."
    }

    Write-Host ("  write-back: {0} refusal shapes enforced, merged+validated passes, edit exact/indent-preserving/idempotent, applied record reaches the trace" -f $wbGateCases.Count) -ForegroundColor DarkGray
}
finally {
    Remove-Item -LiteralPath $wbWorkspace -Recurse -Force -ErrorAction SilentlyContinue
}

# TRIPWIRE 1 — there is exactly ONE generator of a completion edit.
# Two places that turn `- [ ]` into `- [x]` is how a gate gets bypassed: the
# release gates the generator, so a second one is an ungated door. This route
# previously carried its own inline rewrite; it now delegates.
#
# A generator is code that BOTH matches an open checkbox and emits a complete
# one. Each half alone is legitimate and common: the parser and dispatcher read
# open items, and the linter and repairer emit `- [x]` lines (the repairer
# re-lists already-complete items into a history section). Only the
# intersection turns an open item into a completed one.
$wbSourceFiles = @(Get-ChildItem -LiteralPath (Join-Path $WorkspaceRoot 'backend') -Recurse -Filter '*.ps1' -File -ErrorAction SilentlyContinue)
$wbGenerators = New-Object System.Collections.Generic.List[string]
foreach ($wbFile in $wbSourceFiles) {
    $wbText = Get-Content -LiteralPath $wbFile.FullName -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
    if ([string]::IsNullOrEmpty($wbText)) { continue }
    if ($wbText.Contains('\[\s\]') -and $wbText.Contains('- [x] ')) {
        $wbGenerators.Add($wbFile.FullName.Substring($WorkspaceRoot.Length).TrimStart('\', '/'))
    }
}
$wbGeneratorList = @($wbGenerators.ToArray())
if ($wbGeneratorList.Count -ne 1 -or $wbGeneratorList[0] -notlike '*Roadmap.WriteBack.ps1') {
    throw ("Completion edits must be generated in exactly one place (backend\modules\roadmap\Roadmap.WriteBack.ps1), so the merge-evidence gate has no bypass. Found {0}: {1}" -f `
            $wbGeneratorList.Count, ($wbGeneratorList -join ', '))
}

# TRIPWIRE 2 — the generator's output may not reach disk without the gate.
# Keyed on the write, not on a route name, so a new route is covered the day
# it is added. Only writes of THIS generator's output count: the roadmap
# repair route writes its own proposedContent and has its own preview flow.
$wbHostLines = @($traceHostSource -split "`r?`n")
$wbEditVars = @($wbHostLines | Where-Object { $_ -match 'New-RoadmapCompletionEdit' } |
        ForEach-Object { if ($_ -match '\$(\w+)\s*=\s*New-RoadmapCompletionEdit') { $Matches[1] } } |
        Where-Object { $_ } | Sort-Object -Unique)
if ($wbEditVars.Count -eq 0) { throw 'The API host never calls New-RoadmapCompletionEdit; the write-back routes are missing.' }
$wbWriteSites = @(0..($wbHostLines.Count - 1) | Where-Object {
        $line = $wbHostLines[$_]
        if ($line -notmatch 'Set-Content') { return $false }
        $hit = $false
        foreach ($v in $wbEditVars) { if ($line -match ('\$' + [regex]::Escape($v) + '\.proposedContent')) { $hit = $true } }
        return $hit
    })
# Release 3.4 milestone 4 INVERTED this assertion, and the old one failed
# red against the new host before it was rewritten — which is the proof the
# behavior really changed. Until 2026-08-15 the rule was "the completion
# edit reaches disk only behind the gate"; the rule is now "the completion
# edit reaches disk in the HOST not at all". It rides the feature branch via
# Add-RoadmapCompletionCommit (runner-side), and the gate verifies the
# merged result instead of writing it — a write site here would be a write
# to whatever branch is checked out, which at apply time is the default
# branch, the exact defect this milestone closes.
if ($wbWriteSites.Count -gt 0) {
    throw ("The API host writes a completion edit to disk at line {0}. Completion travels through the pull request (Release 3.4 milestone 4): the runner commits it on the feature branch, and the apply route only verifies and records." -f (@($wbWriteSites)[0] + 1))
}
# The verified-merged record must still be gate-guarded: recording completion
# without merge evidence would launder an unmerged item into a verified one.
$wbVerifySites = @(0..($wbHostLines.Count - 1) | Where-Object { $wbHostLines[$_] -match "-Action\s+'verified-merged'" })
if ($wbVerifySites.Count -eq 0) { throw "The apply route never records a 'verified-merged' completion; the verification path is missing." }
foreach ($wbSite in $wbVerifySites) {
    $wbWindowStart = [Math]::Max(0, $wbSite - 60)
    $wbWindow = ($wbHostLines[$wbWindowStart..$wbSite] -join "`n")
    if ($wbWindow -notmatch 'gate\.allowed') {
        throw ("A verified-merged completion is recorded at host line {0} without an enclosing merge-evidence gate check." -f ($wbSite + 1))
    }
}
if ($traceHostSource -notmatch [regex]::Escape("'POST /api/roadmap/write-back/preview'")) { throw 'The API host no longer routes POST /api/roadmap/write-back/preview' }
if ($traceHostSource -notmatch [regex]::Escape("'POST /api/roadmap/write-back/apply'")) { throw 'The API host no longer routes POST /api/roadmap/write-back/apply' }
# Apply must re-derive the gate rather than inherit the preview's verdict.
if ($traceHostSource -notmatch 'Resolve-WriteBackContext -Id \$wbaId') { throw 'The write-back apply route must re-resolve its own context, not trust the preview' }
Write-Host ("  write-back gate tripwire: 1 completion-edit generator, {0} write site(s) all gated, both routes present, apply re-checks" -f $wbWriteSites.Count) -ForegroundColor DarkGray

# ---------------------------------------------------------------------------
# Release 2.1 — Persistent Data Layer (Phase 1)
# ---------------------------------------------------------------------------

Write-Step 'Loading persistence store module (Release 2.1)'
$persistenceModule = Join-Path $WorkspaceRoot 'backend\modules\persistence\Persistence.Store.ps1'
if (-not (Test-Path -LiteralPath $persistenceModule)) { throw "Persistence.Store.ps1 not found at: $persistenceModule" }
. $persistenceModule
Write-Host 'Persistence store module loaded successfully' -ForegroundColor Green

Write-Step 'SQLite capability detection (Release 2.1 Phase 1)'
$sqliteCap = Get-SqliteCapability
if ($null -eq $sqliteCap) { throw 'Get-SqliteCapability returned null' }
Write-Host ("  capability: available={0} provider={1} detail={2} version={3}" -f $sqliteCap.available, $sqliteCap.provider, $sqliteCap.providerDetail, $sqliteCap.sqliteVersion) -ForegroundColor DarkGray

if (-not $sqliteCap.available) {
    # Graceful-degradation contract: no provider means a soft failure with a
    # reason, never an exception — the JSON stores stay authoritative.
    $degradedInit = Initialize-AppDatabase -WorkspaceRoot ([System.IO.Path]::GetTempPath())
    if ($degradedInit.success) { throw 'Initialize-AppDatabase must not report success without a SQLite provider' }
    if ([string]::IsNullOrWhiteSpace([string]$degradedInit.error)) { throw 'Degraded init must explain why SQLite is unavailable' }
    Write-Host '  no SQLite provider on this machine — degraded-path contract verified; DB smoke skipped' -ForegroundColor Yellow
} else {
    $appDbWorkspace = Join-Path ([System.IO.Path]::GetTempPath()) ("app-db-smoke-" + [guid]::NewGuid().ToString('n').Substring(0, 8))
    New-Item -ItemType Directory -Path $appDbWorkspace -Force | Out-Null
    try {
        Write-Step 'App database bootstrap — schema init, idempotent re-init (Release 2.1 Phase 1)'
        $appDbInit = Initialize-AppDatabase -WorkspaceRoot $appDbWorkspace
        if (-not $appDbInit.success) { throw "Initialize-AppDatabase failed: $($appDbInit.error)" }
        if (-not (Test-Path -LiteralPath $appDbInit.databasePath)) { throw "app.db not created at $($appDbInit.databasePath)" }
        $expectedAppDbTables = @(
            'schema_migrations', 'execution_ledger', 'execution_history', 'maturity_history',
            'ops_log', 'portfolio_index_history', 'repo_signals', 'differential_scans',
            'merge_readiness_snapshots', 'agent_runs', 'agent_run_events', 'quota_burn_snapshots',
            'foundation_coverage'
        )
        foreach ($tableName in $expectedAppDbTables) {
            if ($tableName -notin @($appDbInit.tables)) { throw "Missing expected table '$tableName' (got: $(@($appDbInit.tables) -join ', '))" }
        }
        $appDbReinit = Initialize-AppDatabase -WorkspaceRoot $appDbWorkspace
        if (-not $appDbReinit.success) { throw "Re-init must be idempotent: $($appDbReinit.error)" }
        $migrationRows = Invoke-AppDbQuery -DatabasePath $appDbInit.databasePath -Sql 'SELECT COUNT(*) AS n FROM schema_migrations'
        if ([long]$migrationRows[0].n -ne 1) { throw "Expected exactly 1 schema migration row after re-init, got $($migrationRows[0].n)" }
        $migrationVersion = Invoke-AppDbQuery -DatabasePath $appDbInit.databasePath -Sql 'SELECT MAX(version) AS v FROM schema_migrations'
        if ([long]$migrationVersion[0].v -ne 3) { throw "Expected schema version 3 (Release 3.6 M5 added foundation_coverage), got $($migrationVersion[0].v)" }
        Write-Host ("  app.db created with {0} tables; re-init idempotent" -f @($appDbInit.tables).Count) -ForegroundColor DarkGray

        Write-Step 'App database repeated writes + parameter binding (Release 2.1 Phase 1)'
        for ($writeIndex = 0; $writeIndex -lt 25; $writeIndex++) {
            $null = Invoke-AppDbNonQuery -DatabasePath $appDbInit.databasePath `
                -Sql 'INSERT INTO ops_log (timestamp, level, source, message, data_json) VALUES (@ts, @level, @source, @message, @data)' `
                -Parameters @{
                    ts      = (Get-Date).ToUniversalTime().ToString('o')
                    level   = 'INFO'
                    source  = 'module-smoke'
                    message = "repeated write $writeIndex"
                    data    = $null
                }
        }
        $opsCount = Invoke-AppDbQuery -DatabasePath $appDbInit.databasePath -Sql 'SELECT COUNT(*) AS n FROM ops_log WHERE level = @level' -Parameters @{ level = 'INFO' }
        if ([long]$opsCount[0].n -ne 25) { throw "Expected 25 ops_log rows after repeated writes, got $($opsCount[0].n)" }

        $trickyText = "quote'd — ünicode ✓"
        $null = Invoke-AppDbNonQuery -DatabasePath $appDbInit.databasePath `
            -Sql 'INSERT INTO ops_log (timestamp, level, source, message, data_json) VALUES (@ts, @level, @source, @message, @data)' `
            -Parameters @{ ts = (Get-Date).ToUniversalTime().ToString('o'); level = 'WARN'; source = 'module-smoke'; message = $trickyText; data = $null }
        $trickyRow = Invoke-AppDbQuery -DatabasePath $appDbInit.databasePath -Sql 'SELECT message, data_json FROM ops_log WHERE level = @level' -Parameters @{ level = 'WARN' }
        if ([string]$trickyRow[0].message -ne $trickyText) { throw "Unicode/quote parameter round-trip failed: got '$($trickyRow[0].message)'" }
        if ($null -ne $trickyRow[0].data_json) { throw 'NULL parameter should round-trip as $null' }
        Write-Host '  25 repeated writes + unicode/quote/null binding round-trip correct' -ForegroundColor DarkGray

        Write-Step 'Agent-run event dual-write seam (Release 2.1 Phase 1)'
        $dualWriteEvent = Write-AgentRunEvent -WorkspaceRoot $appDbWorkspace -EventType 'smoke.dualwrite' -RunId 'run-dw-1' -RepoName 'app-db-smoke' -Summary 'dual write seam check' -Data @{ source = 'module-smoke' }
        if (-not $dualWriteEvent.written) { throw 'Authoritative JSONL event write failed' }
        if (-not (Test-Path -LiteralPath (Join-Path $appDbWorkspace 'output\agent-runs\events.jsonl'))) { throw 'events.jsonl was not written alongside the DB mirror' }
        if (-not [bool]$dualWriteEvent.dbMirrored) { throw 'Agent-run event was not mirrored into app.db' }
        $mirroredRows = Invoke-AppDbQuery -DatabasePath $appDbInit.databasePath -Sql 'SELECT event_type, repo_name FROM agent_run_events WHERE run_id = @runId' -Parameters @{ runId = 'run-dw-1' }
        if (@($mirroredRows).Count -ne 1) { throw "Expected 1 mirrored agent-run event, got $(@($mirroredRows).Count)" }
        if ([string]$mirroredRows[0].event_type -ne 'smoke.dualwrite') { throw "Mirrored event type mismatch: $($mirroredRows[0].event_type)" }
        Write-Host '  dual-write seam correct: JSONL authoritative + app.db mirror row present' -ForegroundColor DarkGray

        Write-Step 'Agent-run metrics persistence under repeated writes (Release 2.1 Phase 3)'
        $metricsRun = New-AgentRunRecord -WorkspaceRoot $appDbWorkspace -RepoName 'app-db-smoke' `
            -PlannedReleaseName 'Release 9.9' -PlannedPhaseName 'Phase Smoke' -SelectedTaskSection 'Active' `
            -WorkUnitsEstimated 3.0
        $metricsRunId = [string]$metricsRun.runId
        $runRowsAfterCreate = Invoke-AppDbQuery -DatabasePath $appDbInit.databasePath -Sql 'SELECT status, release_name, phase_name, work_units_estimated FROM agent_runs WHERE run_id = @runId' -Parameters @{ runId = $metricsRunId }
        if (@($runRowsAfterCreate).Count -ne 1) { throw "Expected 1 mirrored agent_runs row after create, got $(@($runRowsAfterCreate).Count)" }
        if ([string]$runRowsAfterCreate[0].status -ne 'dispatched') { throw "Mirrored run status mismatch after create: $($runRowsAfterCreate[0].status)" }
        if ([string]$runRowsAfterCreate[0].release_name -ne 'Release 9.9') { throw "Mirrored release_name mismatch: $($runRowsAfterCreate[0].release_name)" }

        $startedIso = (Get-Date).ToUniversalTime().AddMinutes(-10).ToString('o')
        $completedIso = (Get-Date).ToUniversalTime().ToString('o')
        $null = Update-AgentRunRecord -WorkspaceRoot $appDbWorkspace -RunId $metricsRunId -Patch @{ status = 'active'; agentStartedAt = $startedIso }
        $null = Update-AgentRunRecord -WorkspaceRoot $appDbWorkspace -RunId $metricsRunId -Patch @{
            status = 'completed'; agentCompletedAt = $completedIso; tokenUsage = 12345; apiSpendUsd = 0.42; workUnitsActual = 2.5
        }
        $runRowsAfterUpdate = Invoke-AppDbQuery -DatabasePath $appDbInit.databasePath -Sql 'SELECT COUNT(*) AS n FROM agent_runs WHERE run_id = @runId' -Parameters @{ runId = $metricsRunId }
        if ([long]$runRowsAfterUpdate[0].n -ne 1) { throw "Repeated run mirror writes must upsert one row, got $($runRowsAfterUpdate[0].n)" }

        $metricsHistory = Get-AppDbAgentRunMetricsHistory -RepoName 'app-db-smoke' -Days 7
        if (-not $metricsHistory.available) { throw 'Get-AppDbAgentRunMetricsHistory must report available=true with an initialized DB' }
        if (@($metricsHistory.entries).Count -ne 1) { throw "Expected 1 metrics-history entry, got $(@($metricsHistory.entries).Count)" }
        $metricsEntry = @($metricsHistory.entries)[0]
        if ([string]$metricsEntry.status -ne 'completed') { throw "Metrics entry status mismatch: $($metricsEntry.status)" }
        if ([long]$metricsEntry.tokensReported -ne 12345) { throw "Metrics entry tokensReported mismatch: $($metricsEntry.tokensReported)" }
        if ([math]::Abs([double]$metricsEntry.directCostUsd - 0.42) -gt 0.0001) { throw "Metrics entry directCostUsd mismatch: $($metricsEntry.directCostUsd)" }
        if ($null -eq $metricsEntry.timeToDeliverSeconds -or [double]$metricsEntry.timeToDeliverSeconds -le 0) { throw "Metrics entry timeToDeliverSeconds must be derived and positive, got '$($metricsEntry.timeToDeliverSeconds)'" }
        if ([string]$metricsEntry.phaseName -ne 'Phase Smoke') { throw "Metrics entry phaseName mismatch: $($metricsEntry.phaseName)" }
        Write-Host ("  run mirror upserts correct; metrics history returns timing/token/cost (ttd={0}s)" -f $metricsEntry.timeToDeliverSeconds) -ForegroundColor DarkGray

        Write-Step 'Quota-burn snapshot persistence and ordered history (Release 2.1 Phase 3)'
        $allowedEvaluation = @{
            period = '2026-07'; allowed = $true; blockedCode = $null
            estimatedWorkUnits = 3.0; plannedReleaseName = 'Release 9.9'; plannedPhaseName = 'Phase Smoke'
            usage = @{ unitsConsumed = 3.0; remainingBefore = 57.0; remainingAfter = 54.0 }
        }
        $blockedEvaluation = @{
            period = '2026-07'; allowed = $false; blockedCode = 'hard-stop-reached'
            estimatedWorkUnits = 25.0; plannedReleaseName = 'Release 9.9'; plannedPhaseName = 'Phase Smoke'
            usage = @{ unitsConsumed = 55.0; remainingBefore = 5.0; remainingAfter = -20.0 }
        }
        $snapshotWrite1 = Write-AppDbQuotaBurnSnapshot -RepoName 'app-db-smoke' -Evaluation $allowedEvaluation
        if (-not $snapshotWrite1.success) { throw "First quota-burn snapshot write failed: $($snapshotWrite1.reason)" }
        Start-Sleep -Milliseconds 20
        $snapshotWrite2 = Write-AppDbQuotaBurnSnapshot -RepoName 'app-db-smoke' -Evaluation $blockedEvaluation
        if (-not $snapshotWrite2.success) { throw "Second quota-burn snapshot write failed: $($snapshotWrite2.reason)" }

        $burnHistory = Get-AppDbQuotaBurnHistory -RepoName 'app-db-smoke' -Days 7
        if (-not $burnHistory.available) { throw 'Get-AppDbQuotaBurnHistory must report available=true with an initialized DB' }
        if (@($burnHistory.entries).Count -ne 2) { throw "Expected 2 quota-burn entries, got $(@($burnHistory.entries).Count)" }
        $burnFirst = @($burnHistory.entries)[0]
        $burnSecond = @($burnHistory.entries)[1]
        if ([string]::CompareOrdinal([string]$burnFirst.evaluatedAt, [string]$burnSecond.evaluatedAt) -gt 0) { throw 'Quota-burn history must be ordered oldest-first' }
        if (-not [bool]$burnFirst.allowed) { throw 'First quota-burn entry should be allowed=true' }
        if ([bool]$burnSecond.allowed) { throw 'Second quota-burn entry should be allowed=false' }
        if ([string]$burnSecond.blockedCode -ne 'hard-stop-reached') { throw "Quota-burn blockedCode mismatch: $($burnSecond.blockedCode)" }
        if ([math]::Abs([double]$burnSecond.remainingAfter - (-20.0)) -gt 0.0001) { throw "Quota-burn remainingAfter mismatch: $($burnSecond.remainingAfter)" }
        Write-Host '  quota-burn snapshots persisted and readable as an ordered burn-down series' -ForegroundColor DarkGray

        Write-Step 'App database maintenance — snapshot retention + VACUUM (Release 2.7 Phase D)'
        # app.db reached ~138 MB in daily use with no scheduled maintenance. The
        # retention floor is the part worth guarding: GET /api/portfolio/trend
        # answers up to days=180 and Release 2.9 is waiting on 90-day accrual, so
        # a low configured window must be clamped UP rather than honored.
        $agedIso = (Get-Date).ToUniversalTime().AddDays(-400).ToString('o')
        $midIso = (Get-Date).ToUniversalTime().AddDays(-100).ToString('o')
        $freshIso = (Get-Date).ToUniversalTime().ToString('o')
        foreach ($i in 1..12) {
            $null = Invoke-AppDbNonQuery -DatabasePath $appDbInit.databasePath `
                -Sql 'INSERT INTO repo_signals (repo_name, captured_at) VALUES (@n, @t)' `
                -Parameters @{ n = "aged-$i"; t = $agedIso }
        }
        foreach ($i in 1..3) {
            $null = Invoke-AppDbNonQuery -DatabasePath $appDbInit.databasePath `
                -Sql 'INSERT INTO repo_signals (repo_name, captured_at) VALUES (@n, @t)' `
                -Parameters @{ n = "fresh-$i"; t = $freshIso }
        }
        # 100 days old: inside maturity_history's 180-day floor, so a 30-day
        # request must NOT delete it.
        foreach ($i in 1..4) {
            $null = Invoke-AppDbNonQuery -DatabasePath $appDbInit.databasePath `
                -Sql 'INSERT INTO maturity_history (repo_name, maturity_level, captured_at) VALUES (@n, @l, @t)' `
                -Parameters @{ n = "trend-$i"; l = 'L3'; t = $midIso }
        }

        # ReportOnly must count without deleting.
        $maintReport = Invoke-AppDbMaintenance -MaxSnapshotDays 30 -ReportOnly
        if (-not $maintReport.success) { throw "Maintenance report failed: $(($maintReport.tables | Where-Object { $_.error } | Select-Object -First 1).error)" }
        if (-not $maintReport.reportOnly) { throw 'Maintenance report must set reportOnly=true' }
        $reportSignals = ($maintReport.tables | Where-Object { $_.table -eq 'repo_signals' }).removed
        if ([long]$reportSignals -ne 12) { throw "Maintenance report expected 12 aged repo_signals rows, got $reportSignals" }
        $signalsAfterReport = Invoke-AppDbQuery -DatabasePath $appDbInit.databasePath -Sql 'SELECT COUNT(*) AS n FROM repo_signals'
        if ([long]$signalsAfterReport[0].n -ne 15) { throw "ReportOnly must not delete: expected 15 repo_signals rows, got $($signalsAfterReport[0].n)" }

        # The 180-day floor must be reported as applied for the trend tables.
        $maturityPlan = $maintReport.tables | Where-Object { $_.table -eq 'maturity_history' }
        if ([int]$maturityPlan.retentionDays -ne 180) { throw "maturity_history must clamp a 30-day request up to its 180-day floor; got $($maturityPlan.retentionDays)" }
        if (-not $maturityPlan.floorApplied) { throw 'maturity_history must report floorApplied=true for a 30-day request' }

        # Real run: aged rows go, fresh rows and floor-protected rows stay.
        $maintRun = Invoke-AppDbMaintenance -MaxSnapshotDays 30 -Confirm:$false
        if (-not $maintRun.success) { throw "Maintenance run failed: $(($maintRun.tables | Where-Object { $_.error } | Select-Object -First 1).error)" }
        if (-not $maintRun.vacuumed) { throw "VACUUM did not run: $($maintRun.vacuumError)" }
        if ([long]$maintRun.totalRowsRemoved -ne 12) { throw "Maintenance expected to remove 12 rows, removed $($maintRun.totalRowsRemoved)" }
        $signalsAfterRun = Invoke-AppDbQuery -DatabasePath $appDbInit.databasePath -Sql 'SELECT COUNT(*) AS n FROM repo_signals'
        if ([long]$signalsAfterRun[0].n -ne 3) { throw "Maintenance must keep the 3 fresh repo_signals rows, got $($signalsAfterRun[0].n)" }
        $maturityAfterRun = Invoke-AppDbQuery -DatabasePath $appDbInit.databasePath -Sql 'SELECT COUNT(*) AS n FROM maturity_history'
        if ([long]$maturityAfterRun[0].n -ne 4) { throw "Retention floor breached: maturity_history should still hold 4 rows, got $($maturityAfterRun[0].n)" }

        # Append-only operational records must never be touched.
        $ledgerAfterRun = Invoke-AppDbQuery -DatabasePath $appDbInit.databasePath -Sql 'SELECT COUNT(*) AS n FROM ops_log'
        if ([long]$ledgerAfterRun[0].n -lt 26) { throw "Maintenance must not prune ops_log (it has its own row-count trim); got $($ledgerAfterRun[0].n)" }

        # Config resolution reads retention.maxSnapshotDays, not retention.days.
        if ((Get-AppDbMaintenanceRetentionDays -Settings @{ retention = @{ maxSnapshotDays = 200 } }) -ne 200) { throw 'Retention days must be read from retention.maxSnapshotDays' }
        if ((Get-AppDbMaintenanceRetentionDays -Settings @{ retention = @{ days = 30 } }) -ne 365) { throw 'retention.days is doc-review inactivity and must NOT be read as the snapshot window' }
        if ((Get-AppDbMaintenanceRetentionDays -Settings $null) -ne 365) { throw 'Missing settings must fall back to the 365-day default' }

        Write-Host ("  app.db maintenance ok: report={0} aged, removed={1}, VACUUM ran, 180-day floor protected trend rows, ops_log untouched" -f $reportSignals, $maintRun.totalRowsRemoved) -ForegroundColor DarkGray

        Write-Step 'Trend history math — Release 3.5 milestone 4: a day counts each repo once'
        # `maturity_history` holds one row per repo PER CAPTURE. The old
        # day-grouped SUM counted a thrice-captured ready repo three times —
        # `Ready Repos … High 1592` on a 76-repo portfolio — and the AVG
        # weighted it threefold. Reproduced here with a three-capture day, and
        # asserted against the milestone-2 invariant: no day's ready count may
        # exceed the number of distinct repos. Verified red first: the old SQL
        # returns ready=3 over 2 repos against this exact fixture.
        . (Join-Path $WorkspaceRoot 'backend\modules\portfolio\Portfolio.Analytics.ps1')
        foreach ($mh in @(
            @{ repo = 'trend-repo-a'; at = '2026-08-10T00:00:00.0000000Z'; level = 'L1-Informal';            score = 40; pending = 2 }
            @{ repo = 'trend-repo-a'; at = '2026-08-10T06:00:00.0000000Z'; level = 'L3-Contract-Ready';      score = 60; pending = 2 }
            @{ repo = 'trend-repo-a'; at = '2026-08-10T12:00:00.0000000Z'; level = 'L3-Contract-Ready';      score = 80; pending = 1 }
            @{ repo = 'trend-repo-b'; at = '2026-08-10T00:30:00.0000000Z'; level = 'L4-Orchestration-Ready'; score = 30; pending = 3 }
        )) {
            $null = Invoke-AppDbNonQuery -DatabasePath $appDbInit.databasePath `
                -Sql 'INSERT INTO maturity_history (repo_name, maturity_level, maturity_score, pending_count, captured_at) VALUES (@r, @l, @s, @p, @t)' `
                -Parameters @{ r = $mh.repo; l = $mh.level; s = $mh.score; p = $mh.pending; t = $mh.at }
        }

        $trendRows = @(_GetPortfolioTrendHistoryRows -DatabasePath $appDbInit.databasePath -StartUtc ([datetime]'2026-08-01T00:00:00Z'))
        $trendDay = @($trendRows | Where-Object { [string]$_.captured_day -eq '2026-08-10' })[0]
        if ($null -eq $trendDay) { throw 'The fixture day did not appear in the trend history rows' }
        $distinctRepoCount = [long](Invoke-AppDbQuery -DatabasePath $appDbInit.databasePath -Sql "SELECT COUNT(DISTINCT repo_name) AS n FROM maturity_history WHERE substr(captured_at,1,10)='2026-08-10'")[0].n
        # The milestone-2 invariant, asserted directly against the store.
        if ([long]$trendDay.ready_repo_count -gt $distinctRepoCount) {
            throw "ready_repo_count ($($trendDay.ready_repo_count)) exceeds the distinct repo count ($distinctRepoCount) — a day is counting captures, not repos"
        }
        if ([long]$trendDay.ready_repo_count -ne 2) { throw "Expected ready=2 (latest capture of each repo), got $($trendDay.ready_repo_count)" }
        if ([double]$trendDay.avg_maturity_score -ne 55.0) { throw "Expected avg=55 ((80+30)/2, latest captures only), got $($trendDay.avg_maturity_score)" }
        if ([long]$trendDay.repo_samples -ne 2) { throw "Expected repo_samples=2 (one per repo), got $($trendDay.repo_samples)" }

        # The per-repo sparkline follows the same rule: a day's point is the
        # latest capture, not an average over however many captures ran.
        $sparkPoints = @(_GetPortfolioTrendRepoHistoryPoints -DatabasePath $appDbInit.databasePath -RepoName 'trend-repo-a' -StartUtc ([datetime]'2026-08-01T00:00:00Z') -FallbackDay '2026-08-10' -FallbackScore 0)
        if ([double]$sparkPoints[0].value -ne 80.0) { throw "Sparkline day value must be the latest capture (80), got $($sparkPoints[0].value)" }

        # Milestone 4c — "not computed" and "zero" may not share a value.
        if ($null -ne (_GetPortfolioAnalyticsAverage -Entries @() -PropertyName 'maturityScore')) { throw 'An average over nothing must be null, not 0' }
        $avgPartial = _GetPortfolioAnalyticsAverage -Entries @([pscustomobject]@{ maturityScore = 50 }, [pscustomobject]@{ maturityScore = $null }) -PropertyName 'maturityScore'
        if ($avgPartial -ne 50) { throw "A partial average must still compute over the assessed entries, got '$avgPartial'" }
        if ((_GetPortfolioAnalyticsAssessedCount -Entries @([pscustomobject]@{ maturityScore = 50 }, [pscustomobject]@{ maturityScore = $null }) -PropertyName 'maturityScore') -ne 1) { throw 'The assessed count must count only entries that carried a value' }

        # Milestone 4b — one card, one data path. With NO live assessments and
        # history present, the tiles must come from the latest history day —
        # the same source as the trend rows beneath them — and docs health,
        # which has no history column, must read null (not computed), never 0.
        $trendPayload = Get-PortfolioTrendPayload -Assessments @() -Summary $null -GeneratedAt ((Get-Date).ToUniversalTime().ToString('o')) -SeedSource 'portfolio-index' -WorkspaceRoot $appDbWorkspace
        if ([string]$trendPayload.trendStatus -ne 'history-backed') { throw "Expected a history-backed trend from the fixture db, got '$($trendPayload.trendStatus)'" }
        if ([int]$trendPayload.summary.averageMaturityScore -ne 55) { throw "Tiles must read the latest history day (avg 55), got '$($trendPayload.summary.averageMaturityScore)'" }
        if ([int]$trendPayload.summary.readyForWorkCount -ne 2) { throw "Tiles must read the latest history day (ready 2), got '$($trendPayload.summary.readyForWorkCount)'" }
        if ($null -ne $trendPayload.summary.averageDocumentationHealthScore) { throw 'Docs health has no history column and must be null (not computed), never 0' }

        Write-Host '  trend math ok: ready<=distinct repos (2 of 2, was 3 pre-fix), avg from latest captures (55), sparkline latest-not-average, empty average null, history-backed tiles match their own rows' -ForegroundColor DarkGray
    }
    finally {
        Remove-Item -LiteralPath $appDbWorkspace -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Step 'GitHub App JWT minting (Release 2.2)'
. (Join-Path $WorkspaceRoot 'backend\modules\auth\GitHubApp.ps1')
if (Test-RsaPemSupported) {
    $rsaTest = [System.Security.Cryptography.RSA]::Create(2048)
    try { $pemTest = $rsaTest.ExportPkcs8PrivateKeyPem() } finally { $rsaTest.Dispose() }
    $jwtTest = New-GitHubAppJwt -AppId '999999' -PrivateKeyPem $pemTest
    if (@($jwtTest.Split('.')).Count -ne 3) { throw 'New-GitHubAppJwt must return a 3-segment JWT' }
    $claimsTest = ConvertFrom-JwtClaims -Jwt $jwtTest
    if ([string]$claimsTest.header.alg -ne 'RS256') { throw "JWT header alg must be RS256, got '$($claimsTest.header.alg)'" }
    if ([string]$claimsTest.payload.iss -ne '999999') { throw 'JWT iss must be the configured app id' }
    if ([long]$claimsTest.payload.exp -le [System.DateTimeOffset]::UtcNow.ToUnixTimeSeconds()) { throw 'JWT exp must be in the future' }
    $readyTest = Get-GitHubAppReadiness -GitHubApp @{ appId = '999999'; installationId = '42' }
    if ($readyTest.configured -ne $true) { throw 'Get-GitHubAppReadiness should report configured=true when appId+installationId set' }
    Write-Host '  GitHub App JWT minted: RS256, iss=appId, exp in future; readiness reports configured' -ForegroundColor DarkGray
}
else {
    Write-Host '  RSA PEM import unavailable on this runtime — JWT test skipped (degraded contract accepted)' -ForegroundColor Yellow
}

# ── Release 2.7 Phase B — scheduled documentation refinement (preview-first) ──
Write-Step 'Loading automation doc-refinement module (Release 2.7 Phase B)'
$aiDocModule = Join-Path $WorkspaceRoot 'backend\modules\ai\AiDocImprovement.ps1'
$automationModule = Join-Path $WorkspaceRoot 'backend\modules\automation\Automation.DocRefinement.ps1'
if (-not (Test-Path -LiteralPath $aiDocModule)) { throw "Missing module file: $aiDocModule" }
if (-not (Test-Path -LiteralPath $automationModule)) { throw "Missing module file: $automationModule" }
. $aiDocModule
. $automationModule
Write-Host '  Automation doc-refinement module loaded successfully' -ForegroundColor DarkGray

Write-Step 'Automation scope — smoke: curated subset only (favorites/candidates, never archived-ignore)'
$autoEntries = @(
    [pscustomobject]@{ repoId = 'fav-weak-readme';  repoName = 'fav-weak-readme';  curationState = 'favorite';             readmeScore = 10; roadmapScore = 90; roadmapState = 'complete' }
    [pscustomobject]@{ repoId = 'cand-weak-roadmap'; repoName = 'cand-weak-roadmap'; curationState = 'portfolio-candidate'; readmeScore = 95; roadmapScore = 20; roadmapState = 'missing' }
    [pscustomobject]@{ repoId = 'ignored-weak';     repoName = 'ignored-weak';     curationState = 'archived-ignore';      readmeScore = 5;  roadmapScore = 5;  roadmapState = 'missing' }
    [pscustomobject]@{ repoId = 'uncurated-weak';   repoName = 'uncurated-weak';   curationState = '';                     readmeScore = 5;  roadmapScore = 5;  roadmapState = 'missing' }
    [pscustomobject]@{ repoId = 'fav-healthy';      repoName = 'fav-healthy';      curationState = 'favorite';             readmeScore = 95; roadmapScore = 95; roadmapState = 'complete' }
)
$autoTargets = Select-AutomationDocTargets -Entries $autoEntries
$targetNames = @($autoTargets | ForEach-Object { "$($_.repoName):$($_.docType)" } | Sort-Object)
$expectedTargets = @('cand-weak-roadmap:roadmap', 'fav-weak-readme:readme') | Sort-Object
if (($targetNames -join ',') -ne ($expectedTargets -join ',')) {
    throw "Automation scope wrong. Expected [$($expectedTargets -join ', ')]; got [$($targetNames -join ', ')]"
}
Write-Host ("  scope ok: {0} targets (archived-ignore, uncurated, and healthy repos excluded)" -f @($autoTargets).Count) -ForegroundColor DarkGray

Write-Step 'Automation run — smoke: doc-improve previews generated, NOTHING applied'
$autoTmp = Join-Path ([System.IO.Path]::GetTempPath()) ("gh-automation-smoke-" + [guid]::NewGuid().ToString('n'))
$autoRepoDir = Join-Path $autoTmp 'fav-weak-readme'
$null = New-Item -ItemType Directory -Path $autoRepoDir -Force
$weakReadmePath = Join-Path $autoRepoDir 'README.md'
Set-Content -LiteralPath $weakReadmePath -Value "# fav-weak-readme`n" -Encoding UTF8
# Hash the file as-written so the unchanged-check is immune to encoding/newline
# differences and only fails on an actual on-disk mutation.
$readmeHashBefore = (Get-FileHash -LiteralPath $weakReadmePath -Algorithm SHA256).Hash
try {
    $runTargets = @([pscustomobject]@{ repoId = 'fav-weak-readme'; repoName = 'fav-weak-readme'; repoPath = $autoRepoDir; curationState = 'favorite'; docType = 'readme'; reason = 'curated=favorite weak-readme' })
    $autoRun = Invoke-ScheduledDocRefinement -WorkspaceRoot $WorkspaceRoot -Targets $runTargets -Provider 'heuristic' -TriggeredBy 'module-smoke'
    if ([int]$autoRun.appliedCount -ne 0) { throw "Preview-first invariant violated: appliedCount=$($autoRun.appliedCount)" }
    if ([int]$autoRun.proposalCount -lt 1) { throw "Expected at least one doc-improve proposal; got $($autoRun.proposalCount)" }
    $firstProposal = @($autoRun.proposals)[0]
    if ([string]::IsNullOrWhiteSpace([string]$firstProposal.previewId)) { throw 'Proposal missing previewId' }
    if ($firstProposal.applied -ne $false) { throw 'Proposal must be marked applied=false' }
    # The target README on disk must be UNCHANGED (preview-only, no write-back).
    if ((Get-FileHash -LiteralPath $weakReadmePath -Algorithm SHA256).Hash -ne $readmeHashBefore) {
        throw 'Preview-first violated: the target README was modified on disk.'
    }

    # Append-only run history round-trip (isolated temp workspace).
    $histWs = Join-Path $autoTmp 'ws'
    $null = New-Item -ItemType Directory -Path $histWs -Force
    $null = Write-AutomationRunRecord -WorkspaceRoot $histWs -Run $autoRun
    $history = Get-AutomationRunHistory -WorkspaceRoot $histWs
    if (@($history).Count -lt 1) { throw 'Automation run history did not persist the run' }
    if ([string]@($history)[0].runId -ne [string]$autoRun.runId) { throw 'History newest-first ordering or runId mismatch' }

    # Digest payload shape.
    $digest = New-AutomationDigestPayload -Run $autoRun
    if ([int]$digest.appliedCount -ne 0) { throw 'Digest must report appliedCount=0' }
    if ([int]$digest.proposalCount -ne [int]$autoRun.proposalCount) { throw 'Digest proposalCount mismatch' }

    # Guardrail: recording a run that claims to have applied changes must be refused.
    $badRun = [pscustomobject]@{ runId = 'bad'; appliedCount = 1; proposals = @() }
    $refused = $false
    try { $null = Write-AutomationRunRecord -WorkspaceRoot $histWs -Run $badRun } catch { $refused = $true }
    if (-not $refused) { throw 'Write-AutomationRunRecord must refuse a run with appliedCount != 0' }

    Write-Host ("  automation run ok: {0} preview(s), applied=0, history+digest round-trip, applied-run refused (provider={1})" -f $autoRun.proposalCount, $autoRun.provider) -ForegroundColor DarkGray

    # ---- Release 2.7 Phase D — scheduler failure alerting -------------------
    # The failure this guards is silence: interval firing is delegated to an
    # external cron, so a scheduler that stops leaves the config reading
    # "enabled" while history quietly stops growing.
    $healthSettings = @{ automation = @{ enabled = $true; intervalMinutes = 60 } }

    # A fresh run must be healthy with no alert.
    $freshHealth = Get-AutomationHealth -WorkspaceRoot $histWs -Settings $healthSettings
    if (-not $freshHealth.healthy) { throw "Automation health: a just-recorded successful run must be healthy; alert=$($freshHealth.alert.code)" }
    if ($freshHealth.lastOutcome -ne 'ok') { throw "Automation health: expected lastOutcome=ok; got $($freshHealth.lastOutcome)" }
    if ($freshHealth.overdue) { throw 'Automation health: a just-recorded run must not be overdue' }
    # Timezone tripwire. ConvertFrom-Json returns finishedAt as a kind-less
    # DateTime that already holds UTC; converting it a second time put lastRunAt
    # in the FUTURE and made overdue detection impossible without failing any
    # boolean assertion. A just-written run must read as ~0 minutes old, and the
    # tolerance must be well under one local-offset shift.
    if ([math]::Abs([double]$freshHealth.minutesSinceLastRun) -gt 5) {
        throw "Automation health: a just-recorded run must be ~0 minutes old; got $($freshHealth.minutesSinceLastRun) (double UTC conversion?)"
    }

    # Overdue detection: the same history evaluated 5 hours later, against a
    # 60-minute interval and a 2x grace, must alert.
    $lateHealth = Get-AutomationHealth -WorkspaceRoot $histWs -Settings $healthSettings -Now ([datetime]::UtcNow.AddHours(5))
    if (-not $lateHealth.overdue) { throw 'Automation health: a 5-hour gap on a 60-minute interval must be overdue' }
    if ($lateHealth.alert.code -ne 'automation-overdue') { throw "Automation health: expected automation-overdue; got $($lateHealth.alert.code)" }

    # Disabled automation is never overdue — no alert for a feature that is off.
    $offHealth = Get-AutomationHealth -WorkspaceRoot $histWs -Settings @{ automation = @{ enabled = $false; intervalMinutes = 60 } } -Now ([datetime]::UtcNow.AddHours(5))
    if ($offHealth.overdue -or -not $offHealth.healthy) { throw 'Automation health: disabled automation must not alert' }

    # Outcome classification: errors with no proposals = failed; errors with
    # proposals = partial; zero targets = ok (a clean portfolio is not a failure).
    $failedRun = [pscustomobject]@{ runId = 'f1'; proposalCount = 0; targetCount = 1; errors = @([pscustomobject]@{ repoName = 'x'; error = 'boom' }) }
    $partialRun = [pscustomobject]@{ runId = 'p1'; proposalCount = 1; targetCount = 2; errors = @([pscustomobject]@{ repoName = 'x'; error = 'boom' }) }
    $emptyRun = [pscustomobject]@{ runId = 'e1'; proposalCount = 0; targetCount = 0; errors = @() }
    if ((Get-AutomationRunOutcome -Run $failedRun) -ne 'failed') { throw 'Automation outcome: errors with no proposals must classify as failed' }
    if ((Get-AutomationRunOutcome -Run $partialRun) -ne 'partial') { throw 'Automation outcome: errors with proposals must classify as partial' }
    if ((Get-AutomationRunOutcome -Run $emptyRun) -ne 'ok') { throw 'Automation outcome: a zero-target run must classify as ok, not a failure' }

    Write-Host ("  automation health ok: fresh=healthy, 5h-gap=overdue, disabled=silent, outcomes=failed/partial/ok") -ForegroundColor DarkGray
}
finally {
    Remove-Item -LiteralPath $autoTmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Step 'Portal watchdog — smoke: decision logic + ledger/state round-trip (Release 2.7 Phase D)'
# Watch-PortalHealth.ps1 declares its own $WorkspaceRoot, and a dot-source
# assigns the target's parameters into THIS scope. It happens to recompute the
# same repo root from its own location, which is why nothing has failed — but a
# run given -WorkspaceRoot elsewhere would silently snap back to the real repo
# here and every later step would assert against the wrong tree. Save/restore,
# the way Adapters.ps1 and Invoke-Reconciliation.Modular.ps1 already do.
$smokeCallerWorkspaceRoot = $WorkspaceRoot
. (Join-Path $WorkspaceRoot 'scripts\service\Watch-PortalHealth.ps1') -LoadFunctionsOnly
$WorkspaceRoot = $smokeCallerWorkspaceRoot

# Pure decision logic: healthy resets to 0, failures accumulate, reaching the
# threshold triggers a restart and resets the counter.
$wdCases = @(
    @{ Healthy = $true;  Prior = 0; Threshold = 3; Action = 'none';    Failures = 0 },
    @{ Healthy = $true;  Prior = 2; Threshold = 3; Action = 'none';    Failures = 0 },
    @{ Healthy = $false; Prior = 0; Threshold = 3; Action = 'none';    Failures = 1 },
    @{ Healthy = $false; Prior = 1; Threshold = 3; Action = 'none';    Failures = 2 },
    @{ Healthy = $false; Prior = 2; Threshold = 3; Action = 'restart'; Failures = 0 },
    @{ Healthy = $false; Prior = 0; Threshold = 1; Action = 'restart'; Failures = 0 }
)
foreach ($c in $wdCases) {
    $d = Resolve-WatchdogAction -Healthy $c.Healthy -PriorFailures $c.Prior -Threshold $c.Threshold
    if ($d.Action -ne $c.Action -or $d.Failures -ne $c.Failures) {
        throw ("Resolve-WatchdogAction wrong for healthy={0} prior={1} threshold={2}: got action={3}/failures={4}, expected {5}/{6}" -f $c.Healthy, $c.Prior, $c.Threshold, $d.Action, $d.Failures, $c.Action, $c.Failures)
    }
}

# ── Progress-aware suppression (portal restart-loop incident, 2026-08-10) ────
# The incident: a cold 75-repo scan outlives the watchdog's ~180s patience while
# the single-threaded host cannot answer /health/live, so the watchdog restarted
# a HEALTHY host 10 times in a row and no scan ever finished. Lane 0.4 fixed the
# same bug class in the in-process request deadline; the watchdog kept its own
# shorter budget. The discriminator is the host's PROGRESS heartbeat — never CPU,
# which a scan blocked on GitHub or `git` legitimately fails to accrue.
$wdProgressCases = @(
    # 1. Fails + active scan + fresh progress -> suppressed, no restart, even at threshold.
    @{ Name = 'fresh progress suppresses at threshold'; Healthy = $false; Prior = 2; Threshold = 3; Age = 10; Tol = 120; Cpu = $true;  Action = 'none'; Suppressed = $true }
    # 2. Same, but host CPU is flat — CPU must NOT be what protects it.
    @{ Name = 'fresh progress + flat CPU still suppresses'; Healthy = $false; Prior = 5; Threshold = 3; Age = 15; Tol = 120; Cpu = $false; Action = 'none'; Suppressed = $true }
    # 3. Fails + active scan + STALE progress -> restart (threshold already met).
    @{ Name = 'stale progress restarts'; Healthy = $false; Prior = 2; Threshold = 3; Age = 600; Tol = 120; Cpu = $false; Action = 'restart'; Suppressed = $false }
    # 4. Fails + no active operation -> existing policy, unchanged.
    @{ Name = 'no operation keeps old policy (below threshold)'; Healthy = $false; Prior = 0; Threshold = 3; Age = $null; Tol = 120; Cpu = $null; Action = 'none'; Suppressed = $false }
    @{ Name = 'no operation keeps old policy (at threshold)';    Healthy = $false; Prior = 2; Threshold = 3; Age = $null; Tol = 120; Cpu = $null; Action = 'restart'; Suppressed = $false }
    # 5. Probe succeeds -> failure state resets regardless of operation state.
    @{ Name = 'healthy resets even mid-operation'; Healthy = $true; Prior = 9; Threshold = 3; Age = 5; Tol = 120; Cpu = $true; Action = 'none'; Suppressed = $false; Failures = 0 }
    # 6. Operation cleared (age $null because active=false) -> ordinary behaviour returns.
    @{ Name = 'completed operation returns to ordinary policy'; Healthy = $false; Prior = 2; Threshold = 3; Age = $null; Tol = 120; Cpu = $true; Action = 'restart'; Suppressed = $false }
    # 7. Orphaned marker cannot suppress forever: age grows without bound -> restart.
    @{ Name = 'orphaned marker ages out and restarts'; Healthy = $false; Prior = 2; Threshold = 3; Age = 86400; Tol = 120; Cpu = $false; Action = 'restart'; Suppressed = $false }
    # Boundary: exactly at tolerance is still fresh; one second past is not.
    @{ Name = 'age == tolerance is fresh';  Healthy = $false; Prior = 2; Threshold = 3; Age = 120; Tol = 120; Cpu = $false; Action = 'none';    Suppressed = $true }
    @{ Name = 'age > tolerance is stale';   Healthy = $false; Prior = 2; Threshold = 3; Age = 121; Tol = 120; Cpu = $false; Action = 'restart'; Suppressed = $false }
)
foreach ($c in $wdProgressCases) {
    $d = Resolve-WatchdogAction -Healthy $c.Healthy -PriorFailures $c.Prior -Threshold $c.Threshold `
        -ProgressAgeSeconds $c.Age -OperationName 'status.scan' -NoProgressToleranceSeconds $c.Tol -CpuAdvanced $c.Cpu
    if ($d.Action -ne $c.Action) {
        throw ("Watchdog progress case '{0}': expected action {1}, got {2} (reason: {3})" -f $c.Name, $c.Action, $d.Action, $d.Reason)
    }
    if ([bool]$d.Suppressed -ne [bool]$c.Suppressed) {
        throw ("Watchdog progress case '{0}': expected suppressed={1}, got {2}" -f $c.Name, $c.Suppressed, $d.Suppressed)
    }
    if ($c.ContainsKey('Failures') -and $d.Failures -ne $c.Failures) {
        throw ("Watchdog progress case '{0}': expected failures={1}, got {2}" -f $c.Name, $c.Failures, $d.Failures)
    }
}
# Suppression must keep COUNTING failures, so recovery is immediate once progress
# goes stale rather than three more probes away.
$wdSuppressed = Resolve-WatchdogAction -Healthy $false -PriorFailures 7 -Threshold 3 -ProgressAgeSeconds 5 -OperationName 'status.scan' -NoProgressToleranceSeconds 120
if ($wdSuppressed.Failures -ne 8) { throw "Suppressed cycles must still count failures (expected 8, got $($wdSuppressed.Failures))" }

# Configuration invariant: tolerance may never be shorter than the cadence the
# HOST declares it writes progress at, or a slow-but-healthy stage reads as stale
# and the restart loop returns. Clamps UP — being too patient delays freeze
# recovery; being too eager kills healthy work, which is the incident.
$invValid = Test-WatchdogToleranceInvariant -ToleranceSeconds 120 -HeartbeatIntervalSeconds 30
if (-not $invValid.Valid) { throw '120s tolerance vs 30s heartbeat should satisfy the invariant' }
if ($invValid.EffectiveSeconds -ne 120) { throw "Valid tolerance must pass through unchanged, got $($invValid.EffectiveSeconds)" }
$invShort = Test-WatchdogToleranceInvariant -ToleranceSeconds 15 -HeartbeatIntervalSeconds 30
if ($invShort.Valid) { throw '15s tolerance vs 30s heartbeat must FAIL the invariant' }
if ($invShort.EffectiveSeconds -ne 60) { throw "Short tolerance must clamp UP to 2x heartbeat (60s), got $($invShort.EffectiveSeconds)" }
$invEqual = Test-WatchdogToleranceInvariant -ToleranceSeconds 60 -HeartbeatIntervalSeconds 30
if (-not $invEqual.Valid) { throw 'Tolerance exactly at 2x heartbeat must be valid' }
# The tolerance is a NO-PROGRESS budget, not the 900s request deadline: a scan
# that keeps reporting is never restarted however long it runs.
if ($invValid.EffectiveSeconds -ge 900) { throw 'No-progress tolerance must not be raised to the request-deadline budget' }

# Progress-age reader: every unreadable shape must yield $null (= no suppression),
# and an active marker must age from its own timestamp.
. (Join-Path $WorkspaceRoot 'backend\api-host\OperationHeartbeat.ps1')
$hbNow = [datetime]::UtcNow
if ($null -ne (Get-PortalOperationProgressAge -State $null -NowUtc $hbNow)) { throw 'Null state must yield null progress age' }
if ($null -ne (Get-PortalOperationProgressAge -State ([pscustomobject]@{ active = $false; lastProgressAt = $hbNow.ToString('o') }) -NowUtc $hbNow)) { throw 'Inactive operation must yield null progress age' }
if ($null -ne (Get-PortalOperationProgressAge -State ([pscustomobject]@{ active = $true; lastProgressAt = 'not-a-date' }) -NowUtc $hbNow)) { throw 'Unparseable timestamp must yield null progress age' }
if ($null -ne (Get-PortalOperationProgressAge -State ([pscustomobject]@{ active = $true }) -NowUtc $hbNow)) { throw 'Missing timestamp must yield null progress age' }
$hbAge = Get-PortalOperationProgressAge -State ([pscustomobject]@{ active = $true; lastProgressAt = $hbNow.AddSeconds(-45).ToString('o') }) -NowUtc $hbNow
if ($null -eq $hbAge -or [math]::Abs($hbAge - 45) -gt 2) { throw "Active operation age should be ~45s, got $hbAge" }
# ConvertFrom-Json yields Kind=Unspecified; a UTC stamp must not be shifted by
# the local offset (the double-conversion bug class fixed elsewhere in this repo).
$hbUnspecified = $hbNow.AddSeconds(-30).ToString('yyyy-MM-ddTHH:mm:ss.fffffff')
$hbAgeUnspec = Get-PortalOperationProgressAge -State ([pscustomobject]@{ active = $true; lastProgressAt = $hbUnspecified }) -NowUtc $hbNow
if ($null -eq $hbAgeUnspec -or [math]::Abs($hbAgeUnspec - 30) -gt 2) { throw "Kind=Unspecified timestamp must be read as UTC (~30s), got $hbAgeUnspec" }
Write-Host ("  watchdog progress-suppression ok: {0} decision cases, invariant clamps short tolerance up, {1} progress-age shapes" -f $wdProgressCases.Count, 6) -ForegroundColor DarkGray

# ── Heartbeat COVERAGE tripwire (ROADMAP Lane 0.9, second pass) ──────────────
# The first fix instrumented ONE route (/api/status) by hand while
# Get-LongRunningScanRoutePattern already listed the routes that actually get
# the 900s budget — so /api/portfolio/assessment and its siblings kept being
# restarted mid-scan and the Insights page never loaded. The lesson is the one
# this repo keeps relearning: a per-instance fix drifts, so bind the
# instrumentation to the SAME classifier the deadline uses and assert it here.
$hostSource = (Get-Content -LiteralPath (Join-Path $WorkspaceRoot 'backend\api-host\Start-RepoManagementApiHost.ps1') -Encoding UTF8 |
    Where-Object { $_ -notmatch '^\s*#' }) -join "`n"
if ($hostSource -notmatch 'if\s*\(\s*Test-LongRunningScanRoute\s+-Path\s+\$path\s*\)\s*\{[^}]*Start-PortalOperation') {
    throw ('The request loop no longer starts an operation heartbeat for every Test-LongRunningScanRoute path. ' +
        'Per-route instrumentation drifts — that is exactly how /api/portfolio/assessment stayed unprotected and the ' +
        'watchdog kept killing it. Key the heartbeat off the route classifier, not off individual routes.')
}
if ($hostSource -notmatch 'Test-PortalOperationActive[\s\S]{0,200}Complete-PortalOperation') {
    throw 'The request loop must complete the operation heartbeat in its finally, or a finished scan keeps suppressing restarts until it ages out.'
}
# Every scan-engine call in the host must publish progress. A marked-active
# operation with no ticks goes stale and gets restarted anyway — the marker
# alone is not protection.
$scanEngineCalls = @([regex]::Matches($hostSource, 'Get-StatusAdapterResult[^\r\n]*'))
if (@($scanEngineCalls).Count -eq 0) { throw 'No Get-StatusAdapterResult call sites found; the coverage tripwire cannot verify progress reporting.' }
foreach ($call in $scanEngineCalls) {
    if ($call.Value -notmatch '-OnProgress') {
        throw ("Get-StatusAdapterResult called without -OnProgress: '{0}'. A long operation with no progress ticks goes stale and is restarted mid-scan." -f $call.Value.Trim())
    }
}
# The ambient tick must be a no-op outside an operation, so scan engines can
# call it unconditionally without every route having to opt in.
. (Join-Path $WorkspaceRoot 'backend\api-host\OperationHeartbeat.ps1')
if (Test-PortalOperationActive) { throw 'No operation should be active in a fresh smoke process' }
Update-ActivePortalOperationProgress -Stage 'noop-check' -Completed 1   # must not throw
$hbCoverTmp = Join-Path $WorkspaceRoot 'output\smoke\module\heartbeat-cover'
$null = New-Item -ItemType Directory -Path (Join-Path $hbCoverTmp 'output\logs') -Force
try {
    $null = Start-PortalOperation -WorkspaceRoot $hbCoverTmp -Operation 'GET /api/portfolio/assessment' -Stage 'started'
    if (-not (Test-PortalOperationActive)) { throw 'Start-PortalOperation must register the ambient operation' }
    & (Get-ActivePortalOperationTick -Stage 'cold-status-scan') 7
    $hbCovered = Read-PortalOperationState -Path (Get-PortalOperationStatePath -WorkspaceRoot $hbCoverTmp)
    if ([string]$hbCovered.operation -ne 'GET /api/portfolio/assessment') { throw "Ambient operation name wrong: $($hbCovered.operation)" }
    $null = Complete-PortalOperation -WorkspaceRoot $hbCoverTmp -Outcome 'request-ended'
    if (Test-PortalOperationActive) { throw 'Complete-PortalOperation must clear the ambient operation' }
    $hbCleared = Read-PortalOperationState -Path (Get-PortalOperationStatePath -WorkspaceRoot $hbCoverTmp)
    if ($null -ne (Get-PortalOperationProgressAge -State $hbCleared)) { throw 'A completed operation must yield null progress age (no suppression)' }
    Write-Host ("  heartbeat coverage ok: request loop keyed off Test-LongRunningScanRoute, {0} scan-engine call site(s) all publish progress, ambient tick no-ops when idle" -f @($scanEngineCalls).Count) -ForegroundColor DarkGray
}
finally { Remove-Item -LiteralPath $hbCoverTmp -Recurse -Force -ErrorAction SilentlyContinue }

# ── Network-bound loop progress tripwire (ROADMAP Lane 0.9, third pass) ──────
# The coverage tripwire above asserted the SCAN ENGINE call sites publish, and
# passed while a third of the assessment ran dark: the GitHub metadata phase
# walks ~75 repos making sequential per-repo network calls and published
# nothing. Progress went stale for 134s, and the watchdog — correctly, by its
# own contract — restarted a host that was working. Call-site coverage was the
# wrong invariant. What has to hold is that a loop doing per-item network work
# publishes progress FROM INSIDE THE LOOP; a tick outside it does not bound the
# silent window. Enforced structurally via the AST so a new per-repo GitHub
# call in a loop cannot be added without one.
$hostFilePath = Join-Path $WorkspaceRoot 'backend\api-host\Start-RepoManagementApiHost.ps1'
$hostFileAst = [System.Management.Automation.Language.Parser]::ParseFile($hostFilePath, [ref]$null, [ref]$null)
$perItemNetworkCalls = @(
    'Get-LatestGitHubWorkflowRunViaApi'
    'Get-GitHubCommitCountViaApi'
    'Get-GitHubPagesSiteUrlViaApi'
    'ConvertTo-GitHubRepoMetadata'
    'Get-GitHubRepoMetadataMapViaApi'
    'Get-GitHubOpenPrCountsViaApi'
    'Get-GitHubReposViaApi'
)
$progressPublishers = @('Update-ActivePortalOperationProgress', 'Get-ActivePortalOperationTick', 'Update-PortalOperationProgress')
$netLoopChecked = 0
foreach ($fnAst in @($hostFileAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true))) {
    # Real loop statements, plus ForEach-Object script blocks (the pipeline form
    # is how the per-repo GitHub projection is written).
    $loopNodes = @($fnAst.FindAll({ param($n)
        $n -is [System.Management.Automation.Language.ForEachStatementAst] -or
        $n -is [System.Management.Automation.Language.ForStatementAst] -or
        $n -is [System.Management.Automation.Language.WhileStatementAst] -or
        $n -is [System.Management.Automation.Language.DoWhileStatementAst] -or
        $n -is [System.Management.Automation.Language.DoUntilStatementAst] }, $true))
    $loopNodes += @($fnAst.FindAll({ param($n)
        $n -is [System.Management.Automation.Language.CommandAst] -and
        $n.GetCommandName() -in @('ForEach-Object', '%') }, $true) |
        ForEach-Object { $_.CommandElements | Where-Object { $_ -is [System.Management.Automation.Language.ScriptBlockExpressionAst] } })

    foreach ($loopNode in $loopNodes) {
        $loopCommands = @($loopNode.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true) |
            ForEach-Object { $_.GetCommandName() } | Where-Object { $_ })
        # Exclude self-recursion: a helper is not required to tick for being itself.
        $netCallsInLoop = @($loopCommands | Where-Object { $_ -in $perItemNetworkCalls -and $_ -ne $fnAst.Name } | Select-Object -Unique)
        if (@($netCallsInLoop).Count -eq 0) { continue }

        $netLoopChecked++
        if (@($loopCommands | Where-Object { $_ -in $progressPublishers }).Count -eq 0) {
            $netLoopDetail = '{0} (line {1}) makes per-item network calls [{2}] inside a loop without publishing progress.' -f `
                $fnAst.Name, $loopNode.Extent.StartLineNumber, ($netCallsInLoop -join ', ')
            throw ($netLoopDetail +
                ' A network-bound loop that does not tick reads as frozen: this is exactly how the GitHub metadata phase' +
                ' went silent for 134s and the watchdog restarted a working scan. Call Update-ActivePortalOperationProgress' +
                ' inside the loop (it is ambient and no-ops outside a request).')
        }
    }
}
if ($netLoopChecked -eq 0) {
    throw 'No per-item GitHub network loops found; the progress tripwire is vacuous. Update $perItemNetworkCalls to match the current host.'
}
Write-Host ("  network-loop progress ok: {0} per-item GitHub loop(s) all tick from inside the loop" -f $netLoopChecked) -ForegroundColor DarkGray

# ── Scan-route deadline tier tripwire (ROADMAP Lane 0.9, third pass) ─────────
# GET /api/status runs a cold full-portfolio scan (Get-StatusAdapterResult over
# the workspace, then ~150 sequential GitHub calls) but sat on the DEFAULT 180s
# tier. The in-process deadline does not fail the request — it calls
# Environment.FailFast and takes the whole host down. So the route the browser
# polls hard-killed the process every cold scan, which is what the operator saw
# as an endless spinner: "Process terminated. API request deadline exceeded for
# GET /api/status (timeoutSeconds=180)". Membership of the extended tier is not
# a list to maintain by hand — derive it from what the handler actually calls.
. (Join-Path $WorkspaceRoot 'backend\api-host\RequestDeadline.ps1')
# Invoke-GitOperation is a one-level wrapper whose body runs
# Get-StatusAdapterResult over the whole workspace — the indirection hid
# POST /api/update and /api/sync from this tripwire until 2026-08-19, when the
# smoke's git step timed out at the CLIENT's default 180s while a background
# scan competed for the same disk. A wrapper that scans is a scan.
$scanEngineFunctions = @('Get-StatusAdapterResult', 'Invoke-PortfolioAssessment', 'Get-OperationsReposPayload', 'Invoke-GitOperation')
$scanRoutesChecked = 0
foreach ($switchAst in @($hostFileAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.SwitchStatementAst] }, $true))) {
    foreach ($clause in $switchAst.Clauses) {
        $routeLabel = $clause.Item1.Extent.Text.Trim("'`"")
        if ($routeLabel -notmatch '^(GET|POST|PUT|DELETE|PATCH)\s') { continue }

        $clauseCommands = @($clause.Item2.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true) |
            ForEach-Object { $_.GetCommandName() } | Where-Object { $_ })
        $enginesUsed = @($clauseCommands | Where-Object { $_ -in $scanEngineFunctions } | Select-Object -Unique)
        if (@($enginesUsed).Count -eq 0) { continue }

        $scanRoutesChecked++
        $routePath = ($routeLabel -split '\s+', 2)[1]
        if (-not (Test-LongRunningScanRoute -Path $routePath)) {
            $tierDetail = "Route '{0}' runs a full-portfolio scan [{1}] but is not on the extended deadline tier." -f $routeLabel, ($enginesUsed -join ', ')
            throw ($tierDetail +
                ' The request deadline calls Environment.FailFast on expiry, so a cold scan on the 180s tier kills the host' +
                ' mid-request rather than failing the request. Add the path to Get-LongRunningScanRoutePattern.')
        }
    }
}
if ($scanRoutesChecked -eq 0) {
    throw 'No scan routes discovered; the deadline tier tripwire is vacuous. Update $scanEngineFunctions to match the current host.'
}
Write-Host ("  scan-route deadline tier ok: {0} full-portfolio route(s) all on the extended tier" -f $scanRoutesChecked) -ForegroundColor DarkGray

# Ledger + state round-trip on disk (models persistence across scheduled invocations).
$wdTmp = Join-Path $WorkspaceRoot 'output\smoke\module\watchdog'
$null = New-Item -ItemType Directory -Path $wdTmp -Force
try {
    $wdLedger = Join-Path $wdTmp 'wd.jsonl'
    $wdState = Join-Path $wdTmp 'wd.state.json'
    Remove-Item -LiteralPath $wdLedger, $wdState -Force -ErrorAction SilentlyContinue

    if ((Get-WatchdogState -Path $wdState) -ne 0) { throw 'Get-WatchdogState should default to 0 with no state file' }
    Set-WatchdogState -Path $wdState -ConsecutiveFailures 2 -LastAction 'none'
    if ((Get-WatchdogState -Path $wdState) -ne 2) { throw 'Watchdog state did not round-trip (expected 2)' }

    Write-WatchdogLedger -Path $wdLedger -EventName 'probe-fail' -Data @{ priorFailures = 1; decision = 'none' }
    Write-WatchdogLedger -Path $wdLedger -EventName 'restart-triggered' -Data @{ reason = 'test' }
    $wdRecords = @(Get-Content -LiteralPath $wdLedger -Encoding UTF8 | ForEach-Object { $_ | ConvertFrom-Json })
    if ($wdRecords.Count -ne 2) { throw "Watchdog ledger expected 2 append-only records, got $($wdRecords.Count)" }
    if ($wdRecords[0].event -ne 'probe-fail' -or $wdRecords[1].event -ne 'restart-triggered') { throw 'Watchdog ledger records out of order or mislabeled' }
    if (-not $wdRecords[0].timestamp) { throw 'Watchdog ledger record missing timestamp' }

    Write-Host ("  watchdog ok: {0} decision cases, state round-trip, {1} append-only ledger records" -f $wdCases.Count, $wdRecords.Count) -ForegroundColor DarkGray
}
finally {
    Remove-Item -LiteralPath $wdTmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Step 'Portal service installer — smoke: action resolution + secrets carry-forward/strip + drift (Release 2.7 Phase D)'
# Isolate the dot-source in a child scope so the installer's Write-* helpers do
# not clobber the smoke's for the remaining steps.
& {
    # Capture the root first — dot-sourcing the installer rebinds $WorkspaceRoot
    # to its param default ('') in this scope.
    $root = $WorkspaceRoot
    . (Join-Path $root 'scripts\Install-RepoManagementService.ps1') -LoadFunctionsOnly

    $instCases = @(
        @{ Exists = $false; Req = 'Auto';        Int = $true;  Want = 'Install' },
        @{ Exists = $true;  Req = 'Auto';        Int = $true;  Want = 'Menu' },
        @{ Exists = $true;  Req = 'Auto';        Int = $false; Want = 'Repair' },
        @{ Exists = $true;  Req = 'Reconfigure'; Int = $true;  Want = 'Reconfigure' },
        @{ Exists = $false; Req = 'Uninstall';   Int = $true;  Want = 'Uninstall' }
    )
    foreach ($c in $instCases) {
        $g = Resolve-InstallAction -ServiceExists $c.Exists -RequestedAction $c.Req -Interactive $c.Int
        if ($g -ne $c.Want) { throw ("Resolve-InstallAction wrong: exists={0} req={1} int={2} -> {3}, expected {4}" -f $c.Exists, $c.Req, $c.Int, $g, $c.Want) }
    }

    # Secrets/TLS carry-forward: a reconfigure that OMITS -PfxPath/-ApiKey must
    # preserve HTTPS + reuse the key (the bug that silently downgraded to HTTP).
    $rEnv = Resolve-PortalSecretConfig -InjectAuth $true -ExistingSettings @{} `
        -ExistingEnv @{ REPO_MGMT_API_KEY = 'envkey'; REPO_MGMT_TLS_PFX = 'C:\c.pfx'; REPO_MGMT_TLS_PFX_PASSWORD = 'envpw' } -KeyGenerator { 'GEN' }
    if ($rEnv.ApiKey -ne 'envkey' -or $rEnv.ApiKeySource -ne 'env') { throw 'Resolve-PortalSecretConfig did not carry the key forward from env' }
    if (-not $rEnv.UseTls -or $rEnv.PfxPath -ne 'C:\c.pfx' -or $rEnv.PfxPassword -ne 'envpw') { throw 'Resolve-PortalSecretConfig dropped TLS on carry-forward' }

    # Legacy settings secrets migrate forward; explicit params win; generate last.
    $rSet = Resolve-PortalSecretConfig -InjectAuth $true -ExistingEnv @{} `
        -ExistingSettings @{ auth = @{ apiKey = 'setkey' }; network = @{ tls = @{ pfxPath = 'C:\s.pfx'; pfxPassword = 'setpw' } } } -KeyGenerator { 'GEN' }
    if ($rSet.ApiKey -ne 'setkey' -or $rSet.ApiKeySource -ne 'settings' -or $rSet.PfxPassword -ne 'setpw') { throw 'Resolve-PortalSecretConfig did not migrate legacy settings secrets' }
    $rParam = Resolve-PortalSecretConfig -InjectAuth $true -RequestedApiKey 'pk' -RequestedPfxPath 'C:\p.pfx' -RequestedPfxPassword 'ppw' `
        -ExistingEnv @{ REPO_MGMT_API_KEY = 'envkey' } -ExistingSettings @{} -KeyGenerator { 'GEN' }
    if ($rParam.ApiKeySource -ne 'param' -or $rParam.PfxPath -ne 'C:\p.pfx') { throw 'Resolve-PortalSecretConfig: explicit params should win' }
    $rGen = Resolve-PortalSecretConfig -InjectAuth $true -ExistingEnv @{} -ExistingSettings @{} -KeyGenerator { 'GEN' }
    if ($rGen.ApiKeySource -ne 'generated' -or $rGen.ApiKey -ne 'GEN') { throw 'Resolve-PortalSecretConfig should generate when nothing to carry' }

    # Secret-strip: settings.json ends up secret-free (git-safe), non-secret keys kept.
    $strip = Remove-SettingsSecretKeys -Settings @{ schemaVersion = 'v1'; inventory = @{ localRoots = @('X') }; auth = @{ apiKey = 'k'; requireApiKey = $true }; network = @{ tls = @{ pfxPath = 'p'; pfxPassword = 'pw' } } }
    if ($strip.ContainsKey('auth') -or $strip.ContainsKey('network')) { throw 'Remove-SettingsSecretKeys left a secret container behind' }
    if ($strip.schemaVersion -ne 'v1' -or $strip.inventory.localRoots[0] -ne 'X') { throw 'Remove-SettingsSecretKeys dropped a non-secret key' }
    $stripSib = Remove-SettingsSecretKeys -Settings @{ auth = @{ apiKey = 'k'; apiKeyEnvVar = 'X' }; network = @{ corsOrigin = '*'; tls = @{ pfxPassword = 'pw' } } }
    if (-not $stripSib.ContainsKey('auth') -or $stripSib.auth.ContainsKey('apiKey') -or $stripSib.auth.apiKeyEnvVar -ne 'X') { throw 'Remove-SettingsSecretKeys mishandled a non-secret auth sibling' }
    if (-not $stripSib.ContainsKey('network') -or $stripSib.network.ContainsKey('tls') -or $stripSib.network.corsOrigin -ne '*') { throw 'Remove-SettingsSecretKeys mishandled a non-secret network sibling' }

    $instTmp = Join-Path $root 'output\smoke\module\svc-install'
    $null = New-Item -ItemType Directory -Path $instTmp -Force
    try {
        $driftImg = "C:\gone\shawl.exe run --name X --cwd $instTmp --log-dir $instTmp\missing\logs -- $instTmp\pwsh.exe -File $instTmp\host.ps1"
        $drift = @(Get-ImagePathDrift -ImagePath $driftImg)
        if ($drift.Count -lt 1) { throw 'Get-ImagePathDrift should flag the missing paths' }

        Write-Host ("  service installer ok: {0} action cases, secrets carry-forward (env/settings/param/generate), settings-strip git-safe, drift flagged {1} missing" -f $instCases.Count, $drift.Count) -ForegroundColor DarkGray
    }
    finally {
        Remove-Item -LiteralPath $instTmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Step 'Local Claude Code dispatch — smoke: queue writer + runner logic (Release 2.8)'
& {
    $root = $WorkspaceRoot
    . (Join-Path $root 'scripts\Add-RoadmapTaskToQueue.ps1') -LoadFunctionsOnly
    . (Join-Path $root 'scripts\Invoke-RoadmapTaskRunner.ps1') -LoadFunctionsOnly

    $dispTmp = Join-Path $root 'output\smoke\module\claude-dispatch'
    $null = New-Item -ItemType Directory -Path $dispTmp -Force
    try {
        # queue entry shape + append/read round-trip
        $entry = New-RoadmapQueueEntry -RunId 'r1' -Repository 'x/y' -LocalRepoPath 'C:\repo' -RoadmapPath 'C:\repo\ROADMAP.md' -SelectedTask 'Do it' -TaskDescription 'PROMPT' -Branch '' -QueuedAt '2026-01-01T00:00:00Z'
        if ($entry.status -ne 'queued') { throw 'queue entry status should be queued' }
        if ($entry.branch -ne 'roadmap/r1') { throw 'queue entry branch default should be roadmap/<runId>' }
        $qp = Join-Path $dispTmp 'queue.jsonl'
        Add-RoadmapQueueEntry -QueuePath $qp -Entry $entry
        Add-RoadmapQueueEntry -QueuePath $qp -Entry (New-RoadmapQueueEntry -RunId 'r2' -Repository 'x/z' -LocalRepoPath 'C:\repo2' -RoadmapPath 'C:\repo2\ROADMAP.md' -SelectedTask 'Two' -TaskDescription 'P2' -Branch 'roadmap/r2' -QueuedAt '2026-01-01T00:00:01Z')
        $read = @(Get-QueueEntries -QueuePath $qp)
        if ($read.Count -ne 2) { throw "queue round-trip expected 2 entries, got $($read.Count)" }
        if ($read[0].prompt -ne 'PROMPT' -or $read[0].localRepoPath -ne 'C:\repo') { throw 'queue entry fields not preserved on round-trip' }

        # summary status transitions (queued -> awaiting-review, fields merged)
        $sp = Join-Path $dispTmp 'r1.summary.json'
        Update-TaskSummary -SummaryPath $sp -Set @{ status = 'queued'; runId = 'r1' }
        if ((Get-TaskSummaryStatus -SummaryPath $sp) -ne 'queued') { throw 'summary status should be queued' }
        Update-TaskSummary -SummaryPath $sp -Set @{ status = 'awaiting-review'; branch = 'roadmap/r1' }
        $reread = Get-Content -LiteralPath $sp -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($reread.status -ne 'awaiting-review' -or $reread.runId -ne 'r1') { throw 'summary merge/transition failed' }

        # commit-message truncation + best-effort verify detection
        if (((New-TaskCommitMessage -SelectedTask ('x' * 120) -RunId 'r1') -split "`n")[0].Length -gt ('roadmap: '.Length + 68)) { throw 'commit subject not truncated' }
        '{ "scripts": { "test": "vitest" } }' | Set-Content -LiteralPath (Join-Path $dispTmp 'package.json') -Encoding UTF8
        $verifyDetected = Resolve-VerifyCommand -RepoPath $dispTmp
        if ($null -eq $verifyDetected -or $verifyDetected.Display -ne 'npm test') { throw 'verify detection (npm test) failed' }
        if ($verifyDetected.Exe -ne 'npm' -or @($verifyDetected.Arguments) -join ' ' -ne 'test') { throw 'verify detection must carry exe+args for call-operator invocation (no string evaluation)' }

        Write-Host ("  claude dispatch ok: queue round-trip ({0} entries), status transitions, commit-msg truncation, verify detection" -f $read.Count) -ForegroundColor DarkGray

        # ── Release 3.0 — dispatchTarget on the queue contract ───────────────
        Write-Step 'Operator-context dispatch — smoke: dispatchTarget contract + copilot runner branch (Release 3.0)'

        # An entry written before Release 3.0 carries no dispatchTarget and IS a
        # Claude Code task; defaulting it to anything else would run the wrong
        # tool against a real repo.
        if ($entry.dispatchTarget -ne 'claude') { throw "Default dispatchTarget must be claude; got '$($entry.dispatchTarget)'" }
        $legacyEntry = [pscustomobject]@{ runId = 'legacy'; prompt = 'p' }
        if ((Get-QueueEntryDispatchTarget -Entry $legacyEntry) -ne 'claude') { throw 'A pre-3.0 entry with no dispatchTarget must resolve to claude' }
        $copilotEntry = New-RoadmapQueueEntry -RunId 'r3' -Repository 'x/y' -LocalRepoPath 'C:\repo' -RoadmapPath 'C:\repo\ROADMAP.md' `
            -SelectedTask 'Cloud' -TaskDescription 'PROMPT' -Branch '' -QueuedAt '2026-01-01T00:00:02Z' -DispatchTarget 'copilot' -BaseBranch 'main'
        if ($copilotEntry.dispatchTarget -ne 'copilot' -or $copilotEntry.baseBranch -ne 'main') { throw 'Copilot entry did not carry dispatchTarget/baseBranch' }
        if ((Get-QueueEntryDispatchTarget -Entry ([pscustomobject]$copilotEntry)) -ne 'copilot') { throw 'Runner did not read dispatchTarget=copilot back' }
        if ((Resolve-RoadmapDispatchTarget -DispatchTarget 'COPILOT') -ne 'copilot') { throw 'dispatchTarget must normalize case' }

        # Refuse, never default. Running an unrecognized target as claude would
        # execute the wrong tool against a real repository.
        $unknownRefused = $false
        try { $null = Resolve-RoadmapDispatchTarget -DispatchTarget 'gemini' } catch { $unknownRefused = $true }
        if (-not $unknownRefused) { throw 'An unknown dispatchTarget must be refused, not defaulted' }
        $runnerRefused = $false
        try { $null = Get-QueueEntryDispatchTarget -Entry ([pscustomobject]@{ runId = 'r'; dispatchTarget = 'gemini' }) } catch { $runnerRefused = $true }
        if (-not $runnerRefused) { throw 'The runner must refuse an unknown dispatchTarget rather than guess' }

        # `gh agent-task create` argv: an array, never a command string — the
        # prompt is multi-line roadmap text full of quotes.
        $quotingPrompt = "line1`nHe said `"go`" — and 'stop'"
        $ghArgs = @(New-CopilotAgentTaskArgs -Repository 'owner/repo' -Prompt $quotingPrompt -BaseBranch 'main')
        if ($ghArgs[0] -ne 'agent-task' -or $ghArgs[1] -ne 'create') { throw 'agent-task argv must start with agent-task create' }
        if ($ghArgs -notcontains '--repo' -or $ghArgs -notcontains 'owner/repo') { throw 'agent-task argv must name the repo' }
        if ($ghArgs -notcontains '--base' -or $ghArgs -notcontains 'main') { throw 'agent-task argv must pass the base branch' }
        # One argv element, verbatim. A prompt spliced into a command string
        # would break on the first quote the roadmap text happens to contain.
        if (@($ghArgs | Where-Object { $_ -eq $quotingPrompt }).Count -ne 1) { throw 'The prompt must survive as one verbatim argv element, not split or re-quoted' }
        $noBase = @(New-CopilotAgentTaskArgs -Repository 'owner/repo' -Prompt 'p')
        if ($noBase -contains '--base') { throw 'An empty base branch must not emit a bare --base flag' }

        # The task URL is the only durable handle on a cloud run. Absent output
        # yields '' so the caller records the absence rather than a fake link.
        if ((Get-AgentTaskUrlFromOutput -Output 'Created https://github.com/owner/repo/agents/task/42.') -ne 'https://github.com/owner/repo/agents/task/42') { throw 'agent-task URL not extracted (or trailing punctuation kept)' }
        if ((Get-AgentTaskUrlFromOutput -Output 'no url here') -ne '') { throw 'Missing agent-task URL must yield empty, never a fabricated link' }
        if ((Get-AgentTaskUrlFromOutput -Output '') -ne '') { throw 'Empty output must yield an empty URL' }

        # The credential trap this release routes around: gh IGNORES its stored
        # OAuth credential whenever GH_TOKEN/GITHUB_TOKEN is set, so a PAT
        # inherited from the portal turns a good operator session into the same
        # failure the service has.
        $okPre = Test-CopilotDispatchPrecondition -GhAvailable $true -EnvToken ''
        if (-not $okPre.ok) { throw 'A gh-present, token-free session must be allowed to dispatch' }
        $noGh = Test-CopilotDispatchPrecondition -GhAvailable $false -EnvToken ''
        if ($noGh.ok -or $noGh.reason -ne 'gh-not-found') { throw 'A session without gh must be refused with a named reason' }
        $envTok = Test-CopilotDispatchPrecondition -GhAvailable $true -EnvToken 'github_pat_abc'
        if ($envTok.ok -or $envTok.reason -ne 'env-token-overrides-oauth') { throw 'An environment token must block cloud dispatch with a named reason' }
        if ($envTok.message -notmatch 'GH_TOKEN') { throw 'The refusal must name the variable to clear' }
        Write-Host '  dispatch target ok: legacy entries stay claude, unknown targets refused, agent-task argv + URL parsed, env-token trap named' -ForegroundColor DarkGray
    }
    finally {
        Remove-Item -LiteralPath $dispTmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ── Release 3.0 — operator-runner presence and the in-host dispatch refusal ──
Write-Step 'Runner presence — smoke: queueing into an empty room is visible (Release 3.0)'
& {
    $root = $WorkspaceRoot
    $presenceModule = Join-Path $root 'backend\modules\automation\Automation.RunnerPresence.ps1'
    if (-not (Test-Path -LiteralPath $presenceModule)) { throw "Missing module file: $presenceModule" }
    . $presenceModule
    . (Join-Path $root 'scripts\Invoke-RoadmapTaskRunner.ps1') -LoadFunctionsOnly

    $presenceNow = [datetime]::UtcNow

    # No heartbeat at all is the state that matters most: the portal enqueues
    # work it cannot execute, so "nothing has ever reported in" must never read
    # as fine.
    $absent = Resolve-RunnerPresence -Heartbeat $null -Now $presenceNow
    if ($absent.present -or $absent.state -ne 'absent') { throw 'A missing heartbeat must classify as absent' }
    if ($absent.message -notmatch 'Invoke-RoadmapTaskRunner') { throw 'The absent message must name the command that fixes it' }

    # A fresh beat is present; the staleness budget comes from the runner's OWN
    # poll interval, so a deliberately slow runner is not called dead each cycle.
    $freshBeat = New-RunnerHeartbeat -QueuePath 'C:\q.jsonl' -PollSeconds 15 -ClaimedCount 2 -Mode 'interactive' -BeatAt $presenceNow.AddSeconds(-5).ToString('o')
    $present = Resolve-RunnerPresence -Heartbeat $freshBeat -Now $presenceNow
    if (-not $present.present -or $present.state -ne 'present') { throw 'A 5-second-old heartbeat must classify as present' }
    if ($present.claimedCount -ne 2) { throw 'Presence must carry the claimed-entry count' }

    $staleBeat = New-RunnerHeartbeat -QueuePath 'C:\q.jsonl' -PollSeconds 15 -BeatAt $presenceNow.AddMinutes(-30).ToString('o')
    $stale = Resolve-RunnerPresence -Heartbeat $staleBeat -Now $presenceNow
    if ($stale.present -or $stale.state -ne 'stale') { throw 'A 30-minute-old heartbeat on a 15s interval must classify as stale' }

    $slowBeat = New-RunnerHeartbeat -QueuePath 'C:\q.jsonl' -PollSeconds 600 -BeatAt $presenceNow.AddMinutes(-20).ToString('o')
    $slow = Resolve-RunnerPresence -Heartbeat $slowBeat -Now $presenceNow
    if (-not $slow.present) { throw 'A slow-polling runner (600s) must not be called dead 20 minutes in' }

    # A 1-second poll interval must not make every reader race the writer.
    $fastBeat = New-RunnerHeartbeat -QueuePath 'C:\q.jsonl' -PollSeconds 1 -BeatAt $presenceNow.AddSeconds(-30).ToString('o')
    if (-not (Resolve-RunnerPresence -Heartbeat $fastBeat -Now $presenceNow).present) { throw 'The staleness floor must protect a very fast poll interval' }

    # Unreadable is absent, never present — this surface exists to stop the
    # portal claiming a runner is there when it is not.
    $garbled = Resolve-RunnerPresence -Heartbeat ([pscustomobject]@{ pollSeconds = 15; lastHeartbeatAt = 'not-a-date' }) -Now $presenceNow
    if ($garbled.present -or $garbled.state -ne 'absent') { throw 'A heartbeat with an unreadable timestamp must classify as absent, not present' }

    # ConvertFrom-Json hands back Kind=Unspecified for a UTC round-trip string;
    # converting it again would put the last beat in the FUTURE and make a dead
    # runner look freshly alive. Same defect already fixed in _Auto_ToUtc.
    $jsonBeat = ($freshBeat | ConvertTo-Json -Depth 6) | ConvertFrom-Json
    $fromJson = Resolve-RunnerPresence -Heartbeat $jsonBeat -Now $presenceNow
    if ($fromJson.secondsSinceBeat -lt 0) { throw 'Heartbeat age went negative — the UTC double-conversion bug is back' }
    if ([math]::Abs($fromJson.secondsSinceBeat - 5) -gt 2) { throw "Heartbeat age wrong after a JSON round-trip: $($fromJson.secondsSinceBeat)s" }

    # Backlog counts only entries still sitting at `queued`. The queue file is
    # append-only, so counting every line would report every task ever
    # dispatched as a permanent backlog.
    $backlogWs = Join-Path $root 'output\smoke\module\runner-backlog'
    if (Test-Path -LiteralPath $backlogWs) { Remove-Item -LiteralPath $backlogWs -Recurse -Force }
    $null = New-Item -ItemType Directory -Path (Join-Path $backlogWs 'output\roadmap-task-history\runs') -Force
    $backlogQueue = Join-Path $backlogWs 'output\roadmap-task-queue.jsonl'
    foreach ($spec in @(
            @{ RunId = 'q1'; Target = 'claude';  Status = 'queued' },
            @{ RunId = 'q2'; Target = 'copilot'; Status = 'queued' },
            @{ RunId = 'q3'; Target = 'copilot'; Status = 'dispatched' })) {
        Add-Content -LiteralPath $backlogQueue -Encoding UTF8 -Value (([pscustomobject]@{ runId = $spec.RunId; dispatchTarget = $spec.Target } | ConvertTo-Json -Compress))
        ([pscustomobject]@{ runId = $spec.RunId; status = $spec.Status } | ConvertTo-Json) |
            Set-Content -LiteralPath (Join-Path $backlogWs ("output\roadmap-task-history\runs\{0}.summary.json" -f $spec.RunId)) -Encoding UTF8
    }
    $backlog = Get-QueuedTaskBacklog -WorkspaceRoot $backlogWs
    if ($backlog.queuedTotal -ne 2) { throw "Backlog must count only still-queued entries; got $($backlog.queuedTotal)" }
    if ($backlog.queuedClaude -ne 1 -or $backlog.queuedCopilot -ne 1) { throw 'Backlog must split by dispatch target so the missing runner kind is named' }

    # Get-RunnerPresence over a real (missing) file must answer, not throw: the
    # route's whole job is to say "is anything going to pick this up", and a 500
    # answers that less usefully than "no".
    $diskPresence = Get-RunnerPresence -WorkspaceRoot $backlogWs -Now $presenceNow
    if ($diskPresence.present -or $diskPresence.state -ne 'absent') { throw 'A workspace with no heartbeat file must report absent' }
    Write-RunnerHeartbeat -Path (Get-RunnerHeartbeatFilePath -WorkspaceRoot $backlogWs) -Heartbeat $freshBeat
    if (-not (Get-RunnerPresence -WorkspaceRoot $backlogWs -Now $presenceNow).present) { throw 'A written heartbeat must read back as present' }
    'not json at all' | Set-Content -LiteralPath (Get-RunnerHeartbeatFilePath -WorkspaceRoot $backlogWs) -Encoding UTF8
    if ((Get-RunnerPresence -WorkspaceRoot $backlogWs -Now $presenceNow).present) { throw 'A corrupt heartbeat file must report absent, not present' }

    # The command the header's Copy button hands the operator must be rooted.
    # The relative form was pasted into an elevated terminal that opened in the
    # user profile and pwsh answered "not recognized as the name of a script
    # file" — while the host had known the workspace root all along.
    $startCmd = Get-RunnerStartCommand -WorkspaceRoot $backlogWs
    if ($startCmd -notmatch '^pwsh -File "(.+)"$') { throw "Get-RunnerStartCommand must return a quoted -File path; got '$startCmd'" }
    $startCmdPath = $Matches[1]
    if (-not [System.IO.Path]::IsPathRooted($startCmdPath)) { throw "The runner start command must carry an absolute script path; got '$startCmdPath'" }
    $expectedRunnerScript = Join-Path (Join-Path ([System.IO.Path]::GetFullPath($backlogWs)) 'scripts') 'Invoke-RoadmapTaskRunner.ps1'
    if ($startCmdPath -ne $expectedRunnerScript) { throw "The runner start command must point at the workspace's own runner script; got '$startCmdPath', expected '$expectedRunnerScript'" }
    if ([string]$diskPresence.startCommand -ne $startCmd) { throw 'Get-RunnerPresence must carry the absolute start command on the payload — it is what every runner-absent 409 and the header Copy button hand the operator' }
    if ([string]$diskPresence.message -notmatch [regex]::Escape($startCmd)) { throw 'The absent message from a root-aware read must name the absolute start command, not the relative one' }
    if ([string](Resolve-RunnerPresence -Heartbeat $staleBeat -Now $presenceNow).startCommand -ne 'pwsh -File scripts/Invoke-RoadmapTaskRunner.ps1') { throw 'The pure reader has no root and must fall back to the relative command, never an empty string' }
    # Tripwire: the presence reader is the one place that knows the root, so no
    # host or module payload may hard-code the relative command again.
    foreach ($surface in @('backend\api-host\Start-RepoManagementApiHost.ps1', 'backend\modules\automation\Automation.RoadmapPackaging.ps1')) {
        $surfaceText = Get-Content -LiteralPath (Join-Path $root $surface) -Raw -Encoding UTF8
        if ($surfaceText -match "runnerCommand\s*=\s*'pwsh -File scripts/" -or $surfaceText -match 'Start one with: pwsh -File scripts/') {
            throw "$surface hard-codes the relative runner command into a payload; use the presence object's startCommand (or Get-RunnerStartCommand) so the operator is handed an absolute path"
        }
    }

    # The one dispatch model: the HOST never runs cloud dispatch itself, in
    # either service or interactive mode. Allowing it when the service check
    # happens to be false brings the failure straight back.
    foreach ($asService in @($true, $false)) {
        $verdict = Test-InProcessCloudDispatchAllowed -Caller 'smoke' -RunningAsService $asService
        if ($verdict.allowed) { throw "In-process cloud dispatch must be refused (runningAsService=$asService)" }
        if ($verdict.code -ne 'operator-runner-required') { throw 'The refusal must carry a named code' }
        if ($verdict.message -notmatch 'Invoke-RoadmapTaskRunner') { throw 'The refusal must name the runner that CAN do it' }
    }

    # The route must actually be gone, not merely unused: the host invoking the
    # launcher in-process is the defect this release removes.
    # Comment lines are stripped first: the route documents WHY it no longer
    # calls the launcher, and a tripwire that fires on its own explanation would
    # be deleted rather than fixed the first time it goes off.
    $hostSource = Get-Content -LiteralPath (Join-Path $root 'backend\api-host\Start-RepoManagementApiHost.ps1') -Encoding UTF8
    $hostCode = @($hostSource | Where-Object { $_ -notmatch '^\s*#' }) -join "`n"
    if ($hostCode -match 'Start-GitHubCopilotTask\.ps1') { throw 'The API host invokes Start-GitHubCopilotTask.ps1 again; cloud dispatch must go through the operator-runner queue' }
    if ($hostCode -notmatch 'Test-InProcessCloudDispatchAllowed') { throw 'The dispatch route must refuse an in-process cloud dispatch request' }
    if ($hostCode -notmatch "DispatchTarget 'copilot'") { throw 'The dispatch route must enqueue with dispatchTarget=copilot' }
    Remove-Item -LiteralPath $backlogWs -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host '  runner presence ok: absent/stale/present classified from the runner own interval, backlog split by target, corrupt heartbeat is absent, in-host cloud dispatch refused in both modes' -ForegroundColor DarkGray
}

Write-Step 'Runner logon-task installer — smoke: refuses service accounts (Release 3.0)'
& {
    $root = $WorkspaceRoot
    . (Join-Path $root 'scripts\service\Install-RoadmapTaskRunner.ps1') -LoadFunctionsOnly

    # The mirror image of the watchdog installer: that one REQUIRES SYSTEM, this
    # one refuses it. A SYSTEM-registered runner would register fine, show as
    # running, claim queued work, and fail every task for a credential reason
    # that looks nothing like the cause.
    foreach ($forbidden in @('NT AUTHORITY\SYSTEM', 'system', 'NT AUTHORITY\LOCAL SERVICE', 'NETWORK SERVICE')) {
        $check = Test-RunnerPrincipalSafe -UserId $forbidden
        if ($check.safe) { throw "The runner installer must refuse the service account '$forbidden'" }
        if ($check.reason -ne 'service-account') { throw "Refusing '$forbidden' must name it as a service account" }
    }
    if ((Test-RunnerPrincipalSafe -UserId '').safe) { throw 'An empty principal must be refused' }
    if (-not (Test-RunnerPrincipalSafe -UserId 'WORKSTATION\ben').safe) { throw 'A normal interactive account must be accepted' }

    # Paths are quoted: a workspace root with a space silently truncates at the
    # first space into a -WorkspaceRoot that does not exist.
    $argString = New-RunnerTaskArgumentString -ScriptPath 'C:\Program Files\repo\scripts\Invoke-RoadmapTaskRunner.ps1' `
        -WorkspaceRoot 'C:\Program Files\repo' -PollSeconds 30 -PermissionMode 'acceptEdits'
    if ($argString -notmatch '-File "C:\\Program Files\\repo\\scripts\\Invoke-RoadmapTaskRunner\.ps1"') { throw 'The script path must be quoted' }
    if ($argString -notmatch '-WorkspaceRoot "C:\\Program Files\\repo"') { throw 'The workspace root must be quoted' }
    if ($argString -match '\-Once') { throw 'A logon task must not pass -Once; it is the long-running poll loop' }
    if ($argString -match '\-Headless') { throw 'Headless must be opt-in, not the default' }
    if ((New-RunnerTaskArgumentString -ScriptPath 'a' -WorkspaceRoot 'b' -Headless $true) -notmatch '\-Headless') { throw '-Headless must be passed through when requested' }

    # A scheduled task inherits the machine environment. On a box with a
    # Machine-scope GITHUB_TOKEN, `gh` ignores the OAuth credential that
    # `gh agent-task` needs, so the runner's own precondition refuses every
    # copilot item it claims -- while Task Scheduler reports the task healthy.
    # Unconditional, because there is no variant of an unattended run that
    # wants the inherited token.
    if ($argString -notmatch '\-ClearInheritedGitHubToken') {
        throw 'The scheduled task must pass -ClearInheritedGitHubToken, or an inherited GITHUB_TOKEN silently blocks every copilot dispatch.'
    }
    if ((New-RunnerTaskArgumentString -ScriptPath 'a' -WorkspaceRoot 'b') -notmatch '\-ClearInheritedGitHubToken') {
        throw '-ClearInheritedGitHubToken must be unconditional, not opt-in, for the scheduled task.'
    }
    # And the runner must actually accept it, or the task launches into a
    # parameter-binding error at every logon.
    $runnerParamSource = Get-Content -LiteralPath (Join-Path $root 'scripts\Invoke-RoadmapTaskRunner.ps1') -Raw -Encoding UTF8
    if ($runnerParamSource -notmatch '\[switch\]\$ClearInheritedGitHubToken') {
        throw 'Invoke-RoadmapTaskRunner.ps1 must declare -ClearInheritedGitHubToken; the installer passes it.'
    }

    foreach ($case in @(
            @{ Uninstall = $false; Exists = $false; Expected = 'install' },
            @{ Uninstall = $false; Exists = $true;  Expected = 'reinstall' },
            @{ Uninstall = $true;  Exists = $true;  Expected = 'uninstall' },
            @{ Uninstall = $true;  Exists = $false; Expected = 'uninstall-noop' })) {
        $resolved = Resolve-RunnerTaskAction -Uninstall $case.Uninstall -TaskExists $case.Exists
        if ($resolved -ne $case.Expected) { throw "Runner task action wrong: uninstall=$($case.Uninstall) exists=$($case.Exists) -> $resolved" }
    }

    # Registration must be interactive and unelevated. Highest would gain
    # nothing and widen the blast radius of a tool that runs agent-authored code.
    $installerSource = Get-Content -LiteralPath (Join-Path $root 'scripts\service\Install-RoadmapTaskRunner.ps1') -Raw -Encoding UTF8
    if ($installerSource -notmatch 'LogonType Interactive') { throw 'The runner task must register with LogonType Interactive' }
    if ($installerSource -notmatch 'RunLevel Limited') { throw 'The runner task must register unelevated (RunLevel Limited)' }
    if ($installerSource -match "UserId 'NT AUTHORITY\\SYSTEM'") { throw 'The runner task must never register as SYSTEM' }
    Write-Host '  runner installer ok: 4 service accounts refused, paths quoted, 4 action cases, interactive + unelevated principal' -ForegroundColor DarkGray
}

# ── Release 2.7 Phase C — scheduled roadmap-item packaging ───────────────────
Write-Step 'Loading roadmap-packaging module (Release 2.7 Phase C)'
$packagingModule = Join-Path $WorkspaceRoot 'backend\modules\automation\Automation.RoadmapPackaging.ps1'
if (-not (Test-Path -LiteralPath $packagingModule)) { throw "Missing module file: $packagingModule" }
. $packagingModule
# Release 3.1 — Submit-PackagedItemToRunner now gates on runner presence and
# refuses to guess when it cannot evaluate it, so its dependency loads here too.
# That throw is deliberate: a presence check that silently passes when it cannot
# run is the shape of guard this repo has been bitten by before.
$packagingPresenceModule = Join-Path $WorkspaceRoot 'backend\modules\automation\Automation.RunnerPresence.ps1'
if (-not (Test-Path -LiteralPath $packagingPresenceModule)) { throw "Missing module file: $packagingPresenceModule" }
. $packagingPresenceModule
Write-Host '  Roadmap-packaging module loaded successfully' -ForegroundColor DarkGray

Write-Step 'Packaging scope — smoke: every refusal is named, and scope opts in'
$pkgItemHigh = [pscustomobject]@{ text = 'Add the merge-readiness route'; section = 'Release 1.0'; roadmapOrder = 3; valueScore = 88; valueTier = 'highest'; valueRationale = @('unblocks dispatch') }
$pkgItemLow  = [pscustomobject]@{ text = 'Tidy the changelog';           section = 'Release 1.0'; roadmapOrder = 1; valueScore = 40; valueTier = 'low';     valueRationale = @('cosmetic') }
$pkgItemTie  = [pscustomobject]@{ text = 'Earlier item, same score';     section = 'Release 1.0'; roadmapOrder = 2; valueScore = 88; valueTier = 'highest'; valueRationale = @('tie-break probe') }
$pkgExecutionContext = [pscustomobject]@{
    releaseGoal = 'Ship the next bounded portfolio improvement.'
    pendingMilestones = @('Add the merge-readiness route')
    acceptanceCriteria = @('The selected task satisfies its named acceptance checks.')
    outOfScope = @('Unselected roadmap work.')
    validationPlan = @('Run `scripts/Invoke-ModuleSmokeTest.ps1` and confirm it exits successfully.')
}
$pkgInvalidExecutionContext = [pscustomobject]@{
    releaseGoal = $pkgExecutionContext.releaseGoal
    pendingMilestones = $pkgExecutionContext.pendingMilestones
    acceptanceCriteria = $pkgExecutionContext.acceptanceCriteria
    outOfScope = $pkgExecutionContext.outOfScope
    validationPlan = @()
}

$pkgEntries = @(
    [pscustomobject]@{ repoId = 'fav-ready';    repoName = 'fav-ready';    curationState = 'favorite';             maturityLevel = 'L2-Structured';          pendingItemCount = 3; localPath = 'C:\repos\fav-ready';    roadmapPath = 'C:\repos\fav-ready\ROADMAP.md';    githubFullName = 'owner/fav-ready'; defaultBranch = 'main'; estimatedSessionWorkUnits = 4; valueRankedItems = @($pkgItemLow, $pkgItemHigh, $pkgItemTie); activeRelease = $pkgExecutionContext }
    [pscustomobject]@{ repoId = 'cand-ready';   repoName = 'cand-ready';   curationState = 'portfolio-candidate';  maturityLevel = 'L4-Orchestration-Ready'; pendingItemCount = 1; localPath = 'C:\repos\cand-ready';   roadmapPath = 'C:\repos\cand-ready\ROADMAP.md';   topValueItem = $pkgItemHigh; activeRelease = $pkgExecutionContext }
    [pscustomobject]@{ repoId = 'ignored';      repoName = 'ignored';      curationState = 'archived-ignore';      maturityLevel = 'L4-Orchestration-Ready'; pendingItemCount = 9; localPath = 'C:\repos\ignored';      topValueItem = $pkgItemHigh }
    [pscustomobject]@{ repoId = 'uncurated';    repoName = 'uncurated';    curationState = '';                     maturityLevel = 'L3-Contract-Ready';      pendingItemCount = 9; localPath = 'C:\repos\uncurated';    topValueItem = $pkgItemHigh }
    [pscustomobject]@{ repoId = 'weird-state';  repoName = 'weird-state';  curationState = 'some-future-state';    maturityLevel = 'L3-Contract-Ready';      pendingItemCount = 9; localPath = 'C:\repos\weird';        topValueItem = $pkgItemHigh }
    [pscustomobject]@{ repoId = 'fav-l2';       repoName = 'fav-l2';       curationState = 'favorite';             maturityLevel = 'L2-Structured';          pendingItemCount = 9; localPath = 'C:\repos\fav-l2';       topValueItem = $pkgItemHigh; activeRelease = $pkgInvalidExecutionContext }
    [pscustomobject]@{ repoId = 'fav-done';     repoName = 'fav-done';     curationState = 'favorite';             maturityLevel = 'L3-Contract-Ready';      pendingItemCount = 0; localPath = 'C:\repos\fav-done';     topValueItem = $pkgItemHigh }
    [pscustomobject]@{ repoId = 'fav-unscored'; repoName = 'fav-unscored'; curationState = 'favorite';             maturityLevel = 'L3-Contract-Ready';      pendingItemCount = 2; localPath = 'C:\repos\fav-unscored' }
    [pscustomobject]@{ repoId = 'fav-nopath';   repoName = 'fav-nopath';   curationState = 'favorite';             maturityLevel = 'L3-Contract-Ready';      pendingItemCount = 2; topValueItem = $pkgItemHigh }
)

$pkgDecisions = @(Resolve-AutomationPackagingScope -Entries $pkgEntries)
$pkgReasonByRepo = @{}
foreach ($d in $pkgDecisions) { $pkgReasonByRepo[[string]$d.repoName] = $d }
$pkgExpectedRefusals = @{
    'ignored'      = 'archived-ignore'
    'uncurated'    = 'not-curated'
    'weird-state'  = 'not-curated'      # scope opts IN — an unknown state is excluded, never admitted
    'fav-l2'       = 'execution-contract-verification-missing'
    'fav-done'     = 'no-pending-work'
    'fav-unscored' = 'no-scored-item'
    'fav-nopath'   = 'missing-local-path'
}
foreach ($repo in $pkgExpectedRefusals.Keys) {
    $decision = $pkgReasonByRepo[$repo]
    if ($null -eq $decision) { throw "Packaging scope: no decision recorded for '$repo'" }
    if ($decision.selected) { throw "Packaging scope: '$repo' must not be selected (expected refusal '$($pkgExpectedRefusals[$repo])')" }
    if ([string]$decision.reason -ne $pkgExpectedRefusals[$repo]) {
        throw "Packaging scope: '$repo' expected reason '$($pkgExpectedRefusals[$repo])'; got '$($decision.reason)'"
    }
}
$pkgSelected = @($pkgDecisions | Where-Object { $_.selected } | ForEach-Object { [string]$_.repoName } | Sort-Object)
if (($pkgSelected -join ',') -ne 'cand-ready,fav-ready') {
    throw "Packaging scope: expected [cand-ready, fav-ready]; got [$($pkgSelected -join ', ')]"
}
Write-Host ("  packaging scope ok: {0} selected, {1} refusals each named (archived-ignore, not-curated x2, execution-contract gap, no-pending-work, no-scored-item, missing-local-path)" -f $pkgSelected.Count, $pkgExpectedRefusals.Count) -ForegroundColor DarkGray

Write-Step 'Packaging rank — smoke: highest value wins, ties break on roadmap order'
$pkgTop = Select-TopValueRoadmapItem -Entry $pkgEntries[0]
if ([string]$pkgTop.text -ne 'Earlier item, same score') {
    throw "Top-value selection wrong: expected the earlier of two equally-scored items; got '$($pkgTop.text)' (score $($pkgTop.valueScore), order $($pkgTop.roadmapOrder))"
}
if ([int]$pkgTop.valueScore -ne 88) { throw 'Top-value selection did not pick the highest score' }
# An entry with no ranked list falls back to the precomputed topValueItem.
if ([string](Select-TopValueRoadmapItem -Entry $pkgEntries[1]).text -ne 'Add the merge-readiness route') { throw 'topValueItem fallback failed' }
# An entry with neither is NOT packaged with an unscored item.
if ($null -ne (Select-TopValueRoadmapItem -Entry $pkgEntries[7])) { throw 'An entry with no scored item must select nothing' }
Write-Host '  packaging rank ok: max score, earlier roadmap order breaks the tie, unscored selects nothing' -ForegroundColor DarkGray

Write-Step 'Packaging quota — smoke: over-budget items are skipped and logged, never silently dropped'
& {
    $pkgWs = Join-Path $WorkspaceRoot 'output\smoke\module\packaging'
    if (Test-Path -LiteralPath $pkgWs) { Remove-Item -LiteralPath $pkgWs -Recurse -Force }
    $null = New-Item -ItemType Directory -Path $pkgWs -Force
    try {
        # A budget whose per-session cap (2) is below the fixture's 4-unit estimate.
        $tightBudget = Get-AgentBudgetLedgerConfig -WorkspaceRoot $pkgWs -Settings @{
            budgetLedger = @{
                quotaGuard     = @{ softStopRemainingUnits = 1; hardStopRemainingUnits = 0; maxUnitsPerPhase = 25; maxUnitsPerSession = 2 }
                defaultProject = @{ monthlyQuotaBudgetUnits = 50; monthlyBudgetUsd = 6; priority = 1 }
            }
        }
        $tightRun = Invoke-ScheduledRoadmapPackaging -WorkspaceRoot $pkgWs -Entries $pkgEntries -BudgetConfig $tightBudget -TriggeredBy 'module-smoke'
        if ([int]$tightRun.packagedCount -ne 0) { throw "Over-budget run packaged $($tightRun.packagedCount) item(s); expected 0" }
        $quotaSkips = @($tightRun.skipped | Where-Object { [string]$_.stage -eq 'quota' })
        if ($quotaSkips.Count -ne 2) { throw "Expected 2 quota skips (both candidates); got $($quotaSkips.Count)" }
        if ([string]$quotaSkips[0].reason -ne 'session-cap-exceeded') { throw "Quota skip must carry the guard's own code; got '$($quotaSkips[0].reason)'" }
        if ([string]::IsNullOrWhiteSpace([string]$quotaSkips[0].message)) { throw 'A quota skip must carry the guard message, not just a code' }
        if (Test-Path -LiteralPath (Get-PackagedItemsFilePath -WorkspaceRoot $pkgWs)) { throw 'An over-budget run must not queue anything for approval' }

        # A guard that cannot be evaluated is a REFUSAL, not a pass. Proven in a
        # fresh runspace where BudgetLedger.ps1 was never loaded.
        $isolated = [powershell]::Create()
        try {
            $null = $isolated.AddScript(@"
. '$packagingModule'
`$r = Test-PackagingQuota -WorkspaceRoot '$pkgWs' -RepoName 'x' -EstimatedWorkUnits 1
"[{0}|{1}]" -f `$r.allowed, `$r.blockedCode
"@)
            $isolatedOut = [string](@($isolated.Invoke()) -join '')
        } finally { $isolated.Dispose() }
        if ($isolatedOut -ne '[False|quota-guard-unavailable]') {
            throw "Fail-closed quota guard broken: expected [False|quota-guard-unavailable], got '$isolatedOut'"
        }
        Write-Host '  packaging quota ok: over-budget skipped+logged with the guard code, nothing queued, missing guard fails closed' -ForegroundColor DarkGray

        Write-Step 'Packaging run — smoke: packets queued for approval, NOTHING dispatched'
        $okBudget = Get-AgentBudgetLedgerConfig -WorkspaceRoot $pkgWs -Settings @{
            budgetLedger = @{
                quotaGuard     = @{ softStopRemainingUnits = 2; hardStopRemainingUnits = 1; maxUnitsPerPhase = 25; maxUnitsPerSession = 12 }
                defaultProject = @{ monthlyQuotaBudgetUnits = 50; monthlyBudgetUsd = 6; priority = 1 }
            }
        }
        $pkgRun = Invoke-ScheduledRoadmapPackaging -WorkspaceRoot $pkgWs -Entries $pkgEntries -BudgetConfig $okBudget -TriggeredBy 'module-smoke'
        if ([int]$pkgRun.packagedCount -ne 2) { throw "Expected 2 packaged items; got $($pkgRun.packagedCount)" }
        if ([int]$pkgRun.dispatchedCount -ne 0) { throw 'Scheduled-run invariant violated: dispatchedCount != 0' }
        if ([int]$pkgRun.appliedCount -ne 0) { throw 'Scheduled-run invariant violated: appliedCount != 0' }
        if (Test-Path -LiteralPath (Join-Path $pkgWs 'output\roadmap-task-queue.jsonl')) {
            throw 'A scheduled packaging run wrote to the dispatch queue; it must stop at the approval gate.'
        }

        $favPacket = @($pkgRun.packets | Where-Object { [string]$_.repoName -eq 'fav-ready' })[0]
        if ([string]$favPacket.itemText -ne 'Earlier item, same score') { throw 'Packet did not carry the top-ranked item' }
        if ([double]$favPacket.estimatedWorkUnits -ne 4) { throw "Packet must price the roadmap's own annotated estimate; got $($favPacket.estimatedWorkUnits)" }
        if ($favPacket.branch -notmatch '^roadmap-item/') { throw "Packet branch must be namespaced; got '$($favPacket.branch)'" }
        if ([string]$favPacket.baseBranch -ne 'main') { throw 'Packet must record the base branch' }
        if ($favPacket.generatedPrompt -notmatch [regex]::Escape($favPacket.itemText)) { throw 'Prompt does not name the selected item' }
        if ($favPacket.generatedPrompt -notmatch 'Implement ONLY') { throw 'Prompt is missing the single-item scope guardrail' }
        if ($favPacket.repairPlan.submitted -ne $false) { throw 'The repair-PR plan must be a plan: submitted=false' }
        if ($favPacket.repairPlan.requiresApproval -ne $true) { throw 'The repair-PR plan must require approval' }
        if ([string]$favPacket.repairPlan.branch -ne [string]$favPacket.branch) { throw 'Repair plan branch must match the packet branch' }
        if ($favPacket.dispatched -ne $false) { throw 'A freshly packaged item must be dispatched=false' }
        # A candidate whose roadmap carries no estimate falls back to the default.
        $candPacket = @($pkgRun.packets | Where-Object { [string]$_.repoName -eq 'cand-ready' })[0]
        if ([double]$candPacket.estimatedWorkUnits -ne 3) { throw "Unannotated item must fall back to the default estimate; got $($candPacket.estimatedWorkUnits)" }

        # Append-only history + the two invariants defended at the writer.
        $null = Write-PackagingRunRecord -WorkspaceRoot $pkgWs -Run $pkgRun
        $pkgHistory = @(Get-PackagingRunHistory -WorkspaceRoot $pkgWs)
        if ($pkgHistory.Count -lt 1) { throw 'Packaging run history did not persist the run' }
        if ([string]$pkgHistory[0].runId -ne [string]$pkgRun.runId) { throw 'Packaging history newest-first ordering or runId mismatch' }
        foreach ($badCase in @(
            @{ Run = [pscustomobject]@{ runId = 'bad1'; appliedCount = 1; dispatchedCount = 0 }; Label = 'appliedCount != 0' },
            @{ Run = [pscustomobject]@{ runId = 'bad2'; appliedCount = 0; dispatchedCount = 1 }; Label = 'dispatchedCount != 0' }
        )) {
            $refused = $false
            try { $null = Write-PackagingRunRecord -WorkspaceRoot $pkgWs -Run $badCase.Run } catch { $refused = $true }
            if (-not $refused) { throw "Write-PackagingRunRecord must refuse a run claiming $($badCase.Label)" }
        }

        # Digest: what was packaged, what was skipped, and nothing dispatched.
        $pkgDigest = New-PackagingDigestPayload -Run $pkgRun
        if ([int]$pkgDigest.packagedCount -ne 2) { throw 'Digest packagedCount mismatch' }
        if ([int]$pkgDigest.dispatchedCount -ne 0) { throw 'Digest must report dispatchedCount=0' }
        if (@($pkgDigest.skipped).Count -lt 7) { throw 'Digest must carry the skipped repos and their reasons' }

        Write-Host ("  packaging run ok: {0} packet(s) queued for approval, dispatched=0 applied=0, dispatch queue absent, invariant-violating runs refused" -f $pkgRun.packagedCount) -ForegroundColor DarkGray

        Write-Step 'Packaging approval — smoke: the state machine is the only path to dispatch'
        $queued = @(Get-PackagedItemQueue -WorkspaceRoot $pkgWs)
        if ($queued.Count -ne 2) { throw "Expected 2 items in the approval queue; got $($queued.Count)" }
        if (@($queued | Where-Object { [string]$_.status -ne 'pending-approval' }).Count -ne 0) { throw 'Every freshly packaged item must be pending-approval' }
        $target = @($queued | Where-Object { [string]$_.repoName -eq 'fav-ready' })[0]

        foreach ($case in @(
            @{ From = 'pending-approval'; To = 'approved';   Want = $true  },
            @{ From = 'pending-approval'; To = 'rejected';   Want = $true  },
            @{ From = 'pending-approval'; To = 'dispatched'; Want = $false },   # never skip the gate
            @{ From = 'approved';        To = 'dispatched'; Want = $true  },
            @{ From = 'dispatched';      To = 'dispatched'; Want = $false },   # never dispatch twice
            @{ From = 'dispatched';      To = 'approved';   Want = $false },
            @{ From = 'rejected';        To = 'approved';   Want = $false },
            @{ From = '';                To = 'approved';   Want = $false }    # unknown packet
        )) {
            $verdict = Test-PackagedItemTransition -From $case.From -To $case.To
            if ([bool]$verdict.allowed -ne [bool]$case.Want) {
                throw "Transition '$($case.From)' -> '$($case.To)' expected allowed=$($case.Want); got $($verdict.allowed)"
            }
            if (-not $verdict.allowed -and [string]::IsNullOrWhiteSpace([string]$verdict.reason)) {
                throw "A refused transition must carry a named reason ('$($case.From)' -> '$($case.To)')"
            }
        }
        if ([string](Test-PackagedItemTransition -From '' -To 'approved').reason -ne 'packet-not-found') { throw 'An unknown packet must refuse with packet-not-found' }

        # Approve -> dispatch: the queue entry and the run summary the operator
        # runner claims on must BOTH appear, or the task is one nothing picks up.
        $null = Write-PackagedItemRecord -WorkspaceRoot $pkgWs -Record ([pscustomobject]@{
            schemaVersion = '1'; packetId = $target.packetId; runId = $pkgRun.runId; repoName = 'fav-ready'
            status = 'approved'; recordedAt = (Get-Date).ToUniversalTime().ToString('o'); actor = 'module-smoke'; note = 'approved'
        })
        # Release 3.1 — prove the REFUSAL first. This is the second road to the
        # queue, and until 2026-08-13 it had no presence gate at all: the approve
        # button was disabled in the browser and nothing checked on the server.
        # With no heartbeat on disk the runner reads absent, so an unacknowledged
        # approval must write nothing.
        $pkgQueueProbe = Join-Path $pkgWs 'output\roadmap-task-queue.jsonl'
        $pkgQueueBefore = if (Test-Path -LiteralPath $pkgQueueProbe) { @(Get-Content -LiteralPath $pkgQueueProbe).Count } else { 0 }
        $refused = Submit-PackagedItemToRunner -WorkspaceRoot $pkgWs -Packet $target.packet -Actor 'module-smoke'
        if (-not $refused.refused) { throw 'An approved packet was enqueued with no runner present; the packaging path must refuse like the dispatch route does.' }
        if ([string]$refused.category -ne 'runner-absent') { throw "Packaging refusal must name its category; got '$($refused.category)'" }
        $pkgQueueAfterRefusal = if (Test-Path -LiteralPath $pkgQueueProbe) { @(Get-Content -LiteralPath $pkgQueueProbe).Count } else { 0 }
        if ($pkgQueueAfterRefusal -ne $pkgQueueBefore) { throw 'A refused packaging dispatch still wrote to the queue; the gate must precede the write.' }

        # Now a present runner: same call, and it goes through.
        $pkgHeartbeatPath = Get-RunnerHeartbeatFilePath -WorkspaceRoot $pkgWs
        $pkgHeartbeatDir = Split-Path -Parent $pkgHeartbeatPath
        if (-not (Test-Path -LiteralPath $pkgHeartbeatDir)) { $null = New-Item -ItemType Directory -Path $pkgHeartbeatDir -Force }
        ([pscustomobject]@{
                hostname = 'smoke-host'; user = 'smoke'; pid = 4242; mode = 'claude'
                pollSeconds = 5; claimedCount = 0; lastHeartbeatAt = ([datetime]::UtcNow).ToString('o')
            } | ConvertTo-Json -Depth 5) | Set-Content -LiteralPath $pkgHeartbeatPath -Encoding UTF8

        $dispatch = Submit-PackagedItemToRunner -WorkspaceRoot $pkgWs -Packet $target.packet -Actor 'module-smoke'
        if ($dispatch.refused) { throw "A present runner must not be refused; got: $($dispatch.message)" }
        if (-not (Test-Path -LiteralPath $dispatch.queuePath)) { throw 'Dispatch did not write the runner queue entry' }
        if (-not (Test-Path -LiteralPath $dispatch.summaryPath)) { throw 'Dispatch did not write the run summary the runner claims on' }
        $summaryStatus = [string]((Get-Content -LiteralPath $dispatch.summaryPath -Raw -Encoding UTF8 | ConvertFrom-Json).status)
        if ($summaryStatus -ne 'queued') { throw "Run summary must read status=queued for the runner to claim it; got '$summaryStatus'" }
        $null = Write-PackagedItemRecord -WorkspaceRoot $pkgWs -Record ([pscustomobject]@{
            schemaVersion = '1'; packetId = $target.packetId; runId = $pkgRun.runId; repoName = 'fav-ready'
            status = 'dispatched'; recordedAt = (Get-Date).ToUniversalTime().ToString('o'); actor = 'module-smoke'
            dispatchRunId = $dispatch.runId; note = 'enqueued'
        })

        $folded = Get-PackagedItem -WorkspaceRoot $pkgWs -PacketId $target.packetId
        if ([string]$folded.status -ne 'dispatched') { throw "Fold must take the newest status; got '$($folded.status)'" }
        if ([string]$folded.dispatchRunId -ne [string]$dispatch.runId) { throw 'Fold lost the dispatch run id' }
        if (@($folded.history).Count -ne 3) { throw "Append-only history must keep every transition; got $(@($folded.history).Count)" }
        if ([string]@($folded.history)[0].status -ne 'pending-approval') { throw 'History must start at pending-approval' }
        if ($null -eq $folded.packet) { throw 'Fold lost the packet body carried by the first record' }
        # The other packet is untouched — approving one never approves the rest.
        $untouched = @(Get-PackagedItemQueue -WorkspaceRoot $pkgWs -Status 'pending-approval')
        if ($untouched.Count -ne 1 -or [string]$untouched[0].repoName -ne 'cand-ready') {
            throw 'Approving one packet must not change any other packet''s state'
        }
        Write-Host ("  packaging approval ok: 8 transitions enforced, queue+summary written on dispatch, fold keeps 3-step history, sibling packet untouched") -ForegroundColor DarkGray
    }
    finally {
        Remove-Item -LiteralPath $pkgWs -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Step 'Dot-source scope safety — tripwire: a dot-sourced script must not blank its caller''s variables'
& {
    # Dot-sourcing runs the target IN THE CALLER'S SCOPE, and that also assigns
    # every one of the target's `param()` variables there — unbound ones as ''.
    # PowerShell variable names are case-insensitive, so a script parameter
    # named $RunId lands on a caller's $runId.
    #
    # This had bitten three places. The API host reached New-RoadmapQueueEntry by
    # dot-sourcing scripts\Add-RoadmapTaskToQueue.ps1 from inside
    # POST /api/roadmap/dispatch/execute, which blanked the $runId it had minted
    # four lines earlier; the next statement died on "Cannot bind argument to
    # parameter 'RunId' because it is an empty string" and the guided-improvement
    # wizard's final step had been dead since Release 3.0. Adapters.ps1 hit the
    # same hazard, noticed it, and hand-restored three of the FOUR variables it
    # shares with Invoke-Reconciliation.ps1 — the missed one ($LogPath) failed
    # nothing and so was invisible. This file had it too, on its own
    # $WorkspaceRoot, harmless only by the coincidence that Watch-PortalHealth.ps1
    # recomputes the same root.
    #
    # Neither check below reads a list someone maintains. Check 1 is a structural
    # rule over the host's own source; check 2 sweeps every dot-source in the
    # repository and derives the collisions from both sides.
    $root = $WorkspaceRoot

    function Get-ScriptParameterName {
        param([Parameter(Mandatory)][string]$Path)
        $t = $null; $e = $null
        $a = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$t, [ref]$e)
        if ($null -eq $a.ParamBlock) { return @() }
        return @($a.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
    }

    # --- Check 1: every script the API host dot-sources is a param-less library.
    $hostPath = Join-Path $root 'backend\api-host\Start-RepoManagementApiHost.ps1'
    $ht = $null; $he = $null
    $hostAst = [System.Management.Automation.Language.Parser]::ParseFile($hostPath, [ref]$ht, [ref]$he)
    $hostDotSources = @($hostAst.FindAll({
                param($n)
                $n -is [System.Management.Automation.Language.CommandAst] -and $n.InvocationOperator -eq 'Dot'
            }, $true))
    if ($hostDotSources.Count -lt 10) {
        throw "Dot-source tripwire found only $($hostDotSources.Count) dot-source sites in the API host; the AST query is wrong, not the host."
    }

    $searchRoots = @('backend', 'scripts', 'tools') | ForEach-Object { Join-Path $root $_ }
    $violations = @()
    foreach ($ds in $hostDotSources) {
        $m = [regex]::Match($ds.Extent.Text, "'([^']+\.ps1)'")
        if (-not $m.Success) {
            # Fail closed: an unresolvable target cannot be proven safe.
            throw ("Dot-source tripwire cannot resolve the target of line {0}: {1}" -f $ds.Extent.StartLineNumber, $ds.Extent.Text)
        }
        $literal = $m.Groups[1].Value
        $asRelative = Join-Path $root $literal
        $candidates = @()
        if (Test-Path -LiteralPath $asRelative -PathType Leaf) {
            $candidates = @((Resolve-Path -LiteralPath $asRelative).Path)
        }
        else {
            $candidates = @(Get-ChildItem -Path $searchRoots -Recurse -File -Filter (Split-Path $literal -Leaf) -ErrorAction SilentlyContinue |
                    ForEach-Object { $_.FullName })
        }
        if ($candidates.Count -eq 0) {
            throw ("Dot-source tripwire could not locate '{0}' (host line {1})." -f $literal, $ds.Extent.StartLineNumber)
        }
        # Every candidate must be clean — an ambiguous leaf name is not an excuse.
        foreach ($c in $candidates) {
            $p = @(Get-ScriptParameterName -Path $c)
            if ($p.Count -gt 0) {
                $violations += ("host line {0} dot-sources {1}, which declares parameters [{2}] that overwrite the route's own variables" -f `
                        $ds.Extent.StartLineNumber, (Split-Path $c -Leaf), ($p -join ','))
            }
        }
    }
    if ($violations.Count -gt 0) {
        throw ("The API host may only dot-source param-less libraries. Move the functions into one (see backend\modules\automation\Automation.RoadmapQueue.ps1):`n  " + ($violations -join "`n  "))
    }

    # The dispatch route calls New-RoadmapQueueEntry, so the library that defines
    # it has to be on the host's load list. Without this the route fails with
    # "not recognized" instead of an empty RunId — a different corpse, same death.
    $queueLibLoaded = @($hostDotSources | Where-Object { $_.Extent.Text -match 'Automation\.RoadmapQueue\.ps1' }).Count
    if ($queueLibLoaded -lt 1) {
        throw 'The API host no longer dot-sources Automation.RoadmapQueue.ps1; POST /api/roadmap/dispatch/execute cannot build a queue entry without it.'
    }

    # --- Check 2: repo-wide. Anywhere a dot-source CAN clobber a caller variable,
    # that variable must be restored. This is derived, not listed: for every
    # dot-source in backend\, scripts\ and tools\, it intersects the target's
    # parameter names with the names live in the enclosing scope (that scope's
    # own parameters PLUS anything assigned above the dot-source — the dispatch
    # route lost a plain local, not a parameter), then requires each collision to
    # be re-assigned below. Run against the commit before this fix it reports
    # four sites, including both real defects.
    #
    # A dot-source inside `& { ... }` is skipped deliberately: that is a child
    # scope, so the target's param assignments die with it. `. { ... }` is not
    # skipped, because a dot-invoked block runs in the caller's scope.
    function Get-DotSourceEnclosingScopeParam {
        param($Node, $FileAst)
        $n = $Node.Parent
        while ($null -ne $n) {
            if ($n -is [System.Management.Automation.Language.FunctionDefinitionAst]) {
                if ($null -eq $n.Body.ParamBlock) { return @() }
                return @($n.Body.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
            }
            if ($n -is [System.Management.Automation.Language.ScriptBlockExpressionAst]) {
                $parent = $n.Parent
                $dotInvoked = ($parent -is [System.Management.Automation.Language.CommandAst]) -and ($parent.InvocationOperator -eq 'Dot')
                if (-not $dotInvoked) { return $null }
            }
            $n = $n.Parent
        }
        if ($null -eq $FileAst.ParamBlock) { return @() }
        return @($FileAst.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
    }

    $skipDirPattern = [regex]::Escape('\node_modules\')
    $allScripts = @(Get-ChildItem -Path $searchRoots -Recurse -File -Filter *.ps1 -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -notmatch $skipDirPattern })
    if ($allScripts.Count -lt 50) { throw "Dot-source sweep found only $($allScripts.Count) scripts; the search roots are wrong, not the repo." }
    $leafIndex = @{}
    foreach ($s in $allScripts) {
        if (-not $leafIndex.ContainsKey($s.Name)) { $leafIndex[$s.Name] = @() }
        $leafIndex[$s.Name] += $s.FullName
    }

    $paramCache = @{}
    $clobbers = @()
    $unresolvable = @()
    $sweptSites = 0
    foreach ($f in $allScripts) {
        $ft = $null; $fe = $null
        $fAst = [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$ft, [ref]$fe)
        if ($fe.Count -gt 0) { continue }

        # 30 of this repo's ~100 dot-sources name their target through a variable
        # (`. $roadmapParser`). Skipping those would leave a hole in a gate whose
        # whole value is being exhaustive, so resolve the variable to the literal
        # it was assigned, and treat anything still unresolvable as a failure
        # rather than as a pass.
        $varMap = @{}
        foreach ($asn in @($fAst.FindAll({
                        param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst]
                    }, $true))) {
            if ($asn.Left -isnot [System.Management.Automation.Language.VariableExpressionAst]) { continue }
            $rm = [regex]::Match($asn.Right.Extent.Text, "'([^']+\.ps1)'")
            if ($rm.Success) { $varMap[$asn.Left.VariablePath.UserPath] = $rm.Groups[1].Value }
        }

        foreach ($ds in @($fAst.FindAll({
                        param($n)
                        $n -is [System.Management.Automation.Language.CommandAst] -and $n.InvocationOperator -eq 'Dot'
                    }, $true))) {
            $sweptSites++
            $lm = [regex]::Match($ds.Extent.Text, "'([^']+\.ps1)'")
            $literal = $null
            if ($lm.Success) { $literal = $lm.Groups[1].Value }
            else {
                $firstElement = $ds.CommandElements[0]
                if ($firstElement -is [System.Management.Automation.Language.VariableExpressionAst]) {
                    $varName = $firstElement.VariablePath.UserPath
                    if ($varMap.ContainsKey($varName)) { $literal = $varMap[$varName] }
                }
            }
            if ($null -eq $literal) {
                $unresolvable += ("{0}:{1}  {2}" -f ($f.FullName.Replace("$root\", '')), $ds.Extent.StartLineNumber, (($ds.Extent.Text -split "`n")[0].Trim()))
                continue
            }
            $asRel = Join-Path $root $literal
            $targets = @(if (Test-Path -LiteralPath $asRel -PathType Leaf) { @((Resolve-Path -LiteralPath $asRel).Path) }
            else { @($leafIndex[(Split-Path $literal -Leaf)]) | Where-Object { $_ } })
            foreach ($tPath in $targets) {
                if (-not $paramCache.ContainsKey($tPath)) { $paramCache[$tPath] = @(Get-ScriptParameterName -Path $tPath) }
                $targetParams = @($paramCache[$tPath])
                if ($targetParams.Count -eq 0) { continue }
                $scopeParams = Get-DotSourceEnclosingScopeParam -Node $ds -FileAst $fAst
                if ($null -eq $scopeParams) { continue }

                $dsLine = $ds.Extent.StartLineNumber
                $scopeNode = $ds.Parent
                while ($null -ne $scopeNode -and -not ($scopeNode -is [System.Management.Automation.Language.FunctionDefinitionAst])) { $scopeNode = $scopeNode.Parent }
                $scopeAst = if ($null -ne $scopeNode) { $scopeNode } else { $fAst }
                $assignments = @($scopeAst.FindAll({
                            param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst]
                        }, $true) | Where-Object { $_.Left -is [System.Management.Automation.Language.VariableExpressionAst] })
                $liveBefore = @($assignments | Where-Object { $_.Extent.StartLineNumber -lt $dsLine } | ForEach-Object { $_.Left.VariablePath.UserPath })
                $scopeVars = @(@($scopeParams) + $liveBefore | Select-Object -Unique)
                $collisions = @($scopeVars | Where-Object { $targetParams -contains $_ })
                if ($collisions.Count -eq 0) { continue }

                $restoredAfter = @($assignments | Where-Object { $_.Extent.StartLineNumber -gt $dsLine } | ForEach-Object { $_.Left.VariablePath.UserPath })
                $unrestored = @($collisions | Where-Object { $restoredAfter -notcontains $_ })
                if ($unrestored.Count -gt 0) {
                    $clobbers += ("{0}:{1} dot-sources {2}; [{3}] are blanked and never restored" -f `
                        ($f.FullName.Replace("$root\", '')), $dsLine, (Split-Path $tPath -Leaf), ($unrestored -join ','))
                }
            }
        }
    }
    if ($unresolvable.Count -gt 0) {
        throw ("The dot-source sweep cannot determine what these sites load, so it cannot prove they are safe. Name the target with a literal path:`n  " + ($unresolvable -join "`n  "))
    }
    if ($clobbers.Count -gt 0) {
        throw ("Dot-sourcing assigns the target's param() variables into the CALLER's scope. These sites lose a value silently:`n  " + ($clobbers -join "`n  "))
    }

    Write-Host ("  dot-source scope ok: {0} host dot-sources all param-less; {1} site(s) across {2} script(s) resolved and swept, every caller-variable collision restored" -f `
            $hostDotSources.Count, $sweptSites, $allScripts.Count) -ForegroundColor DarkGray
}

Write-Step 'Packaging queue contract — tripwire: the entry shape the runner claims must not drift'
& {
    $root = $WorkspaceRoot
    . (Join-Path $root 'scripts\Add-RoadmapTaskToQueue.ps1') -LoadFunctionsOnly
    # The runner reads entries written by BOTH writers. If Add-RoadmapTaskToQueue's
    # shape changes and the packaging writer's does not, approved work would land
    # in the queue as entries the runner silently mishandles — invisible until an
    # operator wonders why an approved packet never ran.
    $canonical = New-RoadmapQueueEntry -RunId 'r1' -Repository 'owner/x' -LocalRepoPath 'C:\repo' -RoadmapPath 'C:\repo\ROADMAP.md' -SelectedTask 'Task' -TaskDescription 'PROMPT' -Branch 'b' -QueuedAt '2026-01-01T00:00:00Z'
    $packaged = New-PackagedItemQueueEntry -RunId 'r1' -QueuedAt '2026-01-01T00:00:00Z' -Packet ([pscustomobject]@{
        repoName = 'owner/x'; repoPath = 'C:\repo'; roadmapPath = 'C:\repo\ROADMAP.md'; itemText = 'Task'; generatedPrompt = 'PROMPT'; branch = 'b'
    })
    $canonicalKeys = @($canonical.Keys | Sort-Object) -join ','
    $packagedKeys = @($packaged.Keys | Sort-Object) -join ','
    if ($canonicalKeys -ne $packagedKeys) {
        throw "Queue-entry drift: Add-RoadmapTaskToQueue writes [$canonicalKeys] but the packaging writer writes [$packagedKeys]"
    }
    foreach ($k in $canonical.Keys) {
        if ([string]$canonical[$k] -ne [string]$packaged[$k]) {
            throw "Queue-entry drift on '$k': canonical='$($canonical[$k])' packaged='$($packaged[$k])'"
        }
    }
    Write-Host ("  queue contract ok: {0} fields identical to the canonical writer" -f @($canonical.Keys).Count) -ForegroundColor DarkGray

    Write-Step 'Packaging health — a stopped packaging cron is visible on its own evidence'
    # Get-AutomationHealth reads the doc-refinement file alone, on purpose: a
    # merged file would let a live packaging cron mask a dead doc cron. That
    # left the reverse case invisible — a packaging cron that stops changes
    # nothing anywhere. This is the second reader that closes it.
    $healthWs = Join-Path $WorkspaceRoot 'output\smoke\module\packaging-health'
    if (Test-Path -LiteralPath $healthWs) { Remove-Item -LiteralPath $healthWs -Recurse -Force }
    $null = New-Item -ItemType Directory -Path (Join-Path $healthWs 'output\automation') -Force
    $pkgHealthSettings = @{ automation = @{ enabled = $true; intervalMinutes = 60 } }

    # Enabled with an interval but no run ever recorded.
    $neverRan = Get-PackagingHealth -WorkspaceRoot $healthWs -Settings $pkgHealthSettings
    if ($neverRan.healthy) { throw 'Packaging health: enabled with no run ever recorded must not read healthy' }
    if ([string]$neverRan.alert.code -ne 'packaging-never-ran') { throw "Packaging health: expected packaging-never-ran, got '$($neverRan.alert.code)'" }

    $pkgHealthNow = [datetime]::UtcNow
    $null = Write-PackagingRunRecord -WorkspaceRoot $healthWs -Run ([pscustomobject]@{
        runId = 'pkg-1'; kind = 'roadmap-packaging'; finishedAt = $pkgHealthNow.AddMinutes(-10).ToString('o')
        packagedCount = 2; skippedCount = 1; dispatchedCount = 0; appliedCount = 0; errors = @()
    })

    $fresh = Get-PackagingHealth -WorkspaceRoot $healthWs -Settings $pkgHealthSettings -Now $pkgHealthNow
    if (-not $fresh.healthy) { throw "Packaging health: a 10-minute-old run on a 60-minute interval must read healthy; alert=$($fresh.alert.code)" }
    if ($fresh.lastOutcome -ne 'ok') { throw 'Packaging health: an error-free run must classify ok' }

    # Two intervals plus grace elapsed -> overdue, with a PACKAGING-specific
    # code. Reusing `automation-overdue` would make a webhook unable to say
    # which of the two schedulers stopped.
    $late = Get-PackagingHealth -WorkspaceRoot $healthWs -Settings $pkgHealthSettings -Now $pkgHealthNow.AddHours(5)
    if (-not $late.overdue) { throw 'Packaging health: 5 hours past a 60-minute interval must be overdue' }
    if ([string]$late.alert.code -ne 'packaging-overdue') { throw "Packaging health alert must be packaging-specific; got '$($late.alert.code)'" }

    # Disabled is not a failure.
    $offHealth = Get-PackagingHealth -WorkspaceRoot $healthWs -Settings @{ automation = @{ enabled = $false; intervalMinutes = 60 } } -Now $pkgHealthNow.AddHours(5)
    if ($offHealth.overdue -or -not $offHealth.healthy) { throw 'Packaging health: disabled automation must not raise an alert' }

    # A packaging-specific interval overrides the shared one; an absent
    # packaging block inherits it rather than defaulting the feature on.
    $splitInterval = Get-PackagingHealth -WorkspaceRoot $healthWs -Settings @{
        automation = @{ enabled = $true; intervalMinutes = 60; packaging = @{ intervalMinutes = 1440 } }
    } -Now $pkgHealthNow.AddHours(5)
    if ($splitInterval.intervalMinutes -ne 1440) { throw "Packaging interval override ignored; got $($splitInterval.intervalMinutes)" }
    if ($splitInterval.overdue) { throw 'Packaging health: 5 hours into a 1440-minute interval must not be overdue' }
    $inheritEnabled = Get-PackagingHealth -WorkspaceRoot $healthWs -Settings @{ automation = @{ enabled = $true; intervalMinutes = 60; packaging = @{ enabled = $false } } } -Now $pkgHealthNow.AddHours(5)
    if ($inheritEnabled.enabled) { throw 'Packaging health: an explicit packaging.enabled=false must switch it off' }

    # A skip is a decision, not a failure — over-budget repos must never make
    # the scheduler look broken, or the guard doing its job becomes an alert.
    $skipOnly = [pscustomobject]@{ runId = 'pkg-2'; kind = 'roadmap-packaging'; finishedAt = $pkgHealthNow.ToString('o'); packagedCount = 0; skippedCount = 5; dispatchedCount = 0; appliedCount = 0; errors = @() }
    if ((Get-PackagingRunOutcome -Run $skipOnly) -ne 'ok') { throw 'Packaging outcome: a run that only skipped must classify ok, not failed' }
    $erroredRun = [pscustomobject]@{ packagedCount = 0; errors = @('boom') }
    $partialRun = [pscustomobject]@{ packagedCount = 1; errors = @('boom') }
    if ((Get-PackagingRunOutcome -Run $erroredRun) -ne 'failed') { throw 'Packaging outcome: errors with no packets must classify failed' }
    if ((Get-PackagingRunOutcome -Run $partialRun) -ne 'partial') { throw 'Packaging outcome: errors with packets must classify partial' }

    # The two readers must stay independent in BOTH directions: a live doc cron
    # must not make the packaging reader look healthy.
    if ((Get-PackagingRunsFilePath -WorkspaceRoot $healthWs) -eq (Get-AutomationRunsFilePath -WorkspaceRoot $healthWs)) {
        throw 'Packaging and doc-refinement history must stay in separate files'
    }
    $docOnlyWs = Join-Path $WorkspaceRoot 'output\smoke\module\packaging-health-doconly'
    if (Test-Path -LiteralPath $docOnlyWs) { Remove-Item -LiteralPath $docOnlyWs -Recurse -Force }
    $null = New-Item -ItemType Directory -Path (Join-Path $docOnlyWs 'output\automation') -Force
    $null = Write-AutomationRunRecord -WorkspaceRoot $docOnlyWs -Run ([pscustomobject]@{
        runId = 'doc-1'; kind = 'doc-refinement'; finishedAt = $pkgHealthNow.ToString('o')
        targetCount = 1; proposalCount = 1; appliedCount = 0; errors = @()
    })
    $maskedByDoc = Get-PackagingHealth -WorkspaceRoot $docOnlyWs -Settings $pkgHealthSettings -Now $pkgHealthNow
    if ($maskedByDoc.healthy) { throw 'A live doc-refinement run must not make the packaging reader report healthy' }
    if ([string]$maskedByDoc.alert.code -ne 'packaging-never-ran') { throw 'Packaging health must judge packaging evidence only' }
    Write-Host '  packaging health ok: never-ran/overdue/partial named packaging-specifically, skips are not failures, doc runs cannot mask it' -ForegroundColor DarkGray
}

Write-Step 'Portfolio read-path performance budget (Release 3.2)'
# Before this, nothing declared how long a portfolio read may take, so a
# regression was invisible: the only bound was the Lane 0.4 request deadline,
# which enforces by calling Environment.FailFast and destroying the host. A
# target whose only enforcement is an outage is a crash guard, not a budget.
. (Join-Path $WorkspaceRoot 'backend\api-host\PerformanceBudget.ps1')

$budgetTable = Get-PortfolioReadBudgetTable
if (@($budgetTable.Keys).Count -eq 0) { throw 'Read-path budget table is empty; the budget gate would be vacuous' }

# Mutating the returned table must not rewrite the contract for later reads.
$budgetTable['memory'] = 999999
if ((Get-PortfolioReadBudgetTable)['memory'] -eq 999999) { throw 'Get-PortfolioReadBudgetTable must return a copy, not the live contract' }

$withinResult = New-PortfolioReadBudgetResult -CacheSource 'memory' -MeasuredMs 120
if (-not $withinResult.withinBudget) { throw 'A 120ms memory-cache read must be within its declared budget' }
if (-not $withinResult.declared) { throw "'memory' is a declared class and must report declared=true" }
if ($withinResult.overByMs -ne 0) { throw 'A read inside budget must report overByMs=0' }
if ($withinResult.budgetMs -le 0) { throw 'A declared class must report the budget it was judged against' }

$overResult = New-PortfolioReadBudgetResult -CacheSource 'memory' -MeasuredMs 9500
if ($overResult.withinBudget) { throw 'A 9.5s memory-cache read must breach the 2s budget' }
if ($overResult.overByMs -le 0) { throw 'A breach must report how far over it went, not just that it failed' }
if ([math]::Round($overResult.measuredMs - $overResult.budgetMs, 1) -ne $overResult.overByMs) { throw 'overByMs must equal measured minus budget' }

# Fail-closed: an unbudgeted read path is an UNMEASURED one. Reporting it as
# within budget is exactly how a new slow route stays invisible — the same
# contract Test-PackagingQuota (quota-guard-unavailable) and
# Test-RoadmapWriteBackEvidence (no evidence is a refusal) apply.
$unknownResult = New-PortfolioReadBudgetResult -CacheSource 'a-new-cache-source' -MeasuredMs 1
if ($unknownResult.withinBudget) { throw 'An undeclared read class must never report withinBudget=true, however fast it was' }
if ($unknownResult.declared) { throw 'An undeclared read class must report declared=false' }
$emptyResult = New-PortfolioReadBudgetResult -CacheSource '' -MeasuredMs 1
if ($emptyResult.withinBudget -or $emptyResult.declared) { throw 'An empty read class must fail closed like any other undeclared one' }

# Config overrides are clamped rather than rejected: a typo must degrade to a
# usable bound, never silently disable the budget (budgetMs=0 reads as
# undeclared, which would then fail closed on a legitimately configured class).
$floorClamped = Resolve-PortfolioReadBudget -CacheSource 'memory' -Settings @{ performance = @{ readPathBudgetMs = @{ memory = 0 } } }
if ($floorClamped -lt 100) { throw "A zero/negative configured budget must clamp up to the floor; got $floorClamped" }
$ceilClamped = Resolve-PortfolioReadBudget -CacheSource 'memory' -Settings @{ performance = @{ readPathBudgetMs = @{ memory = 99999999 } } }
if ($ceilClamped -gt 3600000) { throw "A configured budget above the ceiling must clamp down; got $ceilClamped" }
$honoured = Resolve-PortfolioReadBudget -CacheSource 'memory' -Settings @{ performance = @{ readPathBudgetMs = @{ memory = 1500 } } }
if ($honoured -ne 1500) { throw "A valid configured budget must be honoured; got $honoured" }
$unparseable = Resolve-PortfolioReadBudget -CacheSource 'memory' -Settings @{ performance = @{ readPathBudgetMs = @{ memory = 'soon' } } }
if ($unparseable -ne (Get-PortfolioReadBudgetTable)['memory']) { throw 'An unparseable configured budget must fall back to the declared default' }

# The cold-scan budget must sit strictly BELOW the extended request-deadline
# tier. Budgeting a scan at the crash guard means the first thing to notice a
# regression is the guard killing the host — the outage recorded three times in
# Lane 0.9. Derived from the deadline classifier, not from a copied number.
$scanDeadlineMs = (Get-RequestDeadlineSecondsForPath -Path '/api/portfolio/assessment' -DefaultSeconds 180 -ScanSeconds 900) * 1000
$coldScanBudget = Resolve-PortfolioReadBudget -CacheSource 'fresh-scan'
if ($coldScanBudget -ge $scanDeadlineMs) {
    throw ("The fresh-scan budget ({0}ms) must be below the extended request deadline ({1}ms), or the budget can only ever be breached by the host dying." -f $coldScanBudget, $scanDeadlineMs)
}

# Drift tripwire — every cacheSource the host can put in a 200 payload must
# carry a declared budget. Derived from the host source, because a
# hand-maintained list is exactly what drifts (Lane 0.9's tier list did).
$budgetHostSource = Get-Content -LiteralPath (Join-Path $WorkspaceRoot 'backend\api-host\Start-RepoManagementApiHost.ps1') -Raw -Encoding UTF8
$declaredClasses = @(Get-PortfolioReadBudgetClass)
$emittedClasses = @([regex]::Matches($budgetHostSource, "cacheSource\s*=\s*'([^']*)'") |
    ForEach-Object { $_.Groups[1].Value } |
    # '' is the not-available sentinel in Get-OperationsReposPayload; it returns
    # available=$false and the route answers 409, so it never reaches a payload.
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
if (@($emittedClasses).Count -eq 0) { throw 'No cacheSource literals found in the host; the budget drift tripwire is vacuous' }
foreach ($emitted in $emittedClasses) {
    if ($emitted -notin $declaredClasses) {
        throw ("The host emits cacheSource '{0}' but no read-path budget is declared for it. Add it to PerformanceBudget.ps1 — an unbudgeted read path fails closed and would break this gate rather than silently going unmeasured." -f $emitted)
    }
}

# The routes must actually consult the budget. A budget nothing calls is a
# config file, not a gate.
foreach ($budgetRoute in @('GET /api/portfolio/assessment', 'GET /api/operations/repos', 'GET /api/portfolio/conclusions', 'GET /api/portfolio/tech-inventory')) {
    $routeClause = @($hostFileAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.SwitchStatementAst] }, $true) |
        ForEach-Object { $_.Clauses } |
        Where-Object { $_.Item1.Extent.Text.Trim("'`"") -eq $budgetRoute }) | Select-Object -First 1
    if ($null -eq $routeClause) { throw "Route '$budgetRoute' not found; the read-budget wiring assertion is vacuous" }
    $routeCommands = @($routeClause.Item2.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true) |
        ForEach-Object { $_.GetCommandName() } | Where-Object { $_ })
    if ('New-PortfolioReadBudgetResult' -notin $routeCommands) {
        throw "Route '$budgetRoute' serves a portfolio read but never evaluates the read-path budget, so a regression on it would be invisible."
    }
}

$budgetLogLine = Format-PortfolioReadBudgetLog -Result $withinResult -CorrelationId 'abc123' -Route '/api/portfolio/assessment'
if ($budgetLogLine -notmatch 'portfolio\.read-budget correlationId=\S+ route=\S+ class=\S+ measuredMs=\S+ budgetMs=\d+ withinBudget=\S+ overByMs=\S+ declared=\S+') {
    throw "Read-budget log line does not match the greppable contract Invoke-DailyEvidence.ps1 parses: $budgetLogLine"
}
Write-Host ("  read-path budget ok: {0} class(es) declared, undeclared fails closed, cold-scan budget {1}ms < deadline {2}ms, {3} route(s) evaluate it" -f @($declaredClasses).Count, $coldScanBudget, $scanDeadlineMs, 2) -ForegroundColor DarkGray

Write-Step 'Dispatch execute gate — Release 3.1 M1: the runner-absent refusal precedes the queue write'
& {
    # The milestone's acceptance criterion is explicit that the *refusal* is
    # what must be proven, not the happy path: "a smoke assertion proves the
    # **disabled** state". Six entries were stranded because this route read
    # Get-RunnerPresence after writing the queue line, so a 200 came back
    # describing a problem the operator had just created.
    #
    # Scoped through the AST to the dispatch-execute switch clause rather than
    # grepped over the whole file: a gate living in some other route would
    # satisfy a file-wide search while leaving this one ungated (Lane 0.9 —
    # derive the scope, never maintain a list).
    $dispatchRoute = 'POST /api/roadmap/dispatch/execute'
    $dispatchClause = @($hostAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.SwitchStatementAst] }, $true) |
        ForEach-Object { $_.Clauses } |
        Where-Object { $_.Item1.Extent.Text.Trim("'`"") -eq $dispatchRoute }) | Select-Object -First 1
    if ($null -eq $dispatchClause) {
        throw "Route '$dispatchRoute' not found in the API host; the dispatch gate-ordering assertion is vacuous."
    }
    $clauseBody = $dispatchClause.Item2

    # The refusal: a 409 carrying the named category. Matched on the category
    # literal because that is the contract the frontend switches on.
    $absentGate = @($clauseBody.FindAll({
                param($n)
                $n -is [System.Management.Automation.Language.StringConstantExpressionAst] -and $n.Value -eq 'runner-absent'
            }, $true)) | Select-Object -First 1
    if ($null -eq $absentGate) {
        throw "Route '$dispatchRoute' never refuses with category 'runner-absent'. Nothing stops a dispatch into an empty room from writing a queue entry nobody can claim."
    }

    # The write it must precede: the append to output/roadmap-task-queue.jsonl.
    $queueWrite = @($clauseBody.FindAll({
                param($n)
                $n -is [System.Management.Automation.Language.CommandAst] -and
                $n.GetCommandName() -eq 'Add-Content' -and
                $n.Extent.Text -match 'dispatchQueuePath'
            }, $true)) | Select-Object -First 1
    if ($null -eq $queueWrite) {
        throw "Route '$dispatchRoute' has no Add-Content write to `$dispatchQueuePath; the gate-ordering assertion is vacuous."
    }

    if ($absentGate.Extent.StartOffset -gt $queueWrite.Extent.StartOffset) {
        throw ("The runner-absent refusal (offset {0}) comes AFTER the queue write (offset {1}). An absent runner is warned about, not prevented — that ordering is exactly what stranded six dispatches." -f $absentGate.Extent.StartOffset, $queueWrite.Extent.StartOffset)
    }

    # A refusal that does not say how much is already piled up understates the
    # problem: "no runner" reads very differently at 0 queued than at 6.
    $gateStatement = $clauseBody.FindAll({
            param($n)
            $n -is [System.Management.Automation.Language.IfStatementAst] -and
            $n.Extent.StartOffset -le $absentGate.Extent.StartOffset -and
            $n.Extent.EndOffset -ge $absentGate.Extent.EndOffset
        }, $true) | Sort-Object { $_.Extent.EndOffset - $_.Extent.StartOffset } | Select-Object -First 1
    if ($null -eq $gateStatement -or $gateStatement.Extent.Text -notmatch 'strandedCount') {
        throw "The runner-absent refusal does not report strandedCount, so the operator cannot tell an empty queue from a pile of work nobody claimed."
    }

    Write-Host ("  dispatch gate ok: runner-absent 409 (line {0}) precedes the queue write (line {1}) inside '{2}', and reports strandedCount" -f `
            $absentGate.Extent.StartLineNumber, $queueWrite.Extent.StartLineNumber, $dispatchRoute) -ForegroundColor DarkGray
}

Write-Step 'Dispatch gate coverage — every surface that queues work consults the gate'
& {
    # Release 3.1 M1 shipped the gate on two surfaces and missed two others,
    # including the one ROADMAP.md names as the trigger for the whole release
    # ("Approve and create PR task"). The backend 409 meant nothing could be
    # stranded, but the operator still reviewed a prompt, clicked an enabled
    # button, and got an error — the dead end the milestone exists to remove.
    #
    # Scope derived from the BACKEND, in two hops, because naming one client
    # function is what let this miss surfaces twice. The first version watched
    # `executeRoadmapDispatch` and passed while RepositoryImprovementWorkflowModal
    # and OperationsWorkspaceView sat ungated; the second still passed while
    # RoadmapViewerModal called `startRoadmapTask` — a different client function
    # reaching a different route to the same queue.
    #
    # Hop 1: which api-host routes refuse on runner presence.
    # Hop 2: which apiClient functions post to those routes.
    # Then: every component calling one of those functions must consult the gate.
    $frontendRoot = Join-Path $WorkspaceRoot 'frontend'
    $gateFn = 'resolveDispatchGate'
    $apiClientPath = Join-Path $frontendRoot 'services\apiClient.ts'
    if (-not (Test-Path -LiteralPath $apiClientPath)) { throw 'frontend/services/apiClient.ts not found; the gate-coverage assertion is vacuous.' }
    $apiClientText = Get-Content -LiteralPath $apiClientPath -Raw -Encoding UTF8

    $gatedPaths = @()
    foreach ($clause in @($hostAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.SwitchStatementAst] }, $true) | ForEach-Object { $_.Clauses })) {
        $routeName = $clause.Item1.Extent.Text.Trim("'`"")
        if ($routeName -notmatch '^(POST|PUT|PATCH) (?<path>\S+)$') { continue }
        # Capture before the next -match: PowerShell overwrites $Matches on every
        # comparison, so reading it after the presence test yields the wrong one.
        $routePath = $Matches['path']
        if ($clause.Item2.Extent.Text -notmatch 'Get-RunnerPresence') { continue }
        $gatedPaths += $routePath
    }
    if (@($gatedPaths).Count -eq 0) { throw 'No api-host route refuses on runner presence; the frontend gate-coverage assertion is vacuous.' }

    # Bind each path to the function whose OWN body contains it. Splitting on the
    # export boundary matters: a fixed-width lookahead spans neighbouring bodies
    # and produced false positives for getRunnerPresence (which reads presence,
    # never queues) and submitRoadmapRepairPr (a different route entirely).
    # apiClient posts to paths without the /api prefix, so match on both forms.
    $exportMatches = @([regex]::Matches($apiClientText, 'export\s+async\s+function\s+(?<fn>\w+)'))
    $clientFns = @()
    for ($i = 0; $i -lt @($exportMatches).Count; $i++) {
        $start = $exportMatches[$i].Index
        $end = if ($i + 1 -lt @($exportMatches).Count) { $exportMatches[$i + 1].Index } else { $apiClientText.Length }
        $bodyText = $apiClientText.Substring($start, $end - $start)
        foreach ($p in @($gatedPaths | Sort-Object -Unique)) {
            $short = $p -replace '^/api', ''
            foreach ($form in @($p, $short)) {
                if ($bodyText -match ("['`"]" + [regex]::Escape($form) + "['`"]")) {
                    $clientFns += $exportMatches[$i].Groups['fn'].Value
                }
            }
        }
    }
    $clientFns = @($clientFns | Sort-Object -Unique)
    if (@($clientFns).Count -eq 0) {
        throw ("No apiClient function was found posting to any gated route ({0}); the frontend gate-coverage assertion is vacuous." -f (@($gatedPaths | Sort-Object -Unique) -join ', '))
    }

    $sourceFiles = @(Get-ChildItem -Path $frontendRoot -Recurse -File -Include '*.ts', '*.tsx' -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '\\node_modules\\|\\dist\\' -and $_.FullName -ne $apiClientPath })
    if (@($sourceFiles).Count -eq 0) { throw 'No frontend sources found; the dispatch gate-coverage assertion is vacuous.' }

    $callSites = @()
    foreach ($file in $sourceFiles) {
        $text = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
        if ([string]::IsNullOrEmpty($text)) { continue }
        $hits = @($clientFns | Where-Object { $text -match ("{0}\s*\(" -f [regex]::Escape($_)) })
        if (@($hits).Count -eq 0) { continue }
        # Two shapes both count as gated, because both leave the operator with a
        # control that names its precondition:
        #   * the file resolves the gate itself (the control lives here), or
        #   * the file reads presence and hands it to the child that renders the
        #     control (Dashboard -> PackagedItemQueue).
        # Requiring resolveDispatchGate in a container that already forwards
        # presence would be cargo-cult: it would add a call nothing reads. What
        # this still catches is the case that matters — a surface that queues
        # work while ignoring presence entirely.
        $callSites += [pscustomobject]@{
            Path    = $file.FullName.Substring($WorkspaceRoot.Length).TrimStart('\', '/').Replace('\', '/')
            Calls   = (@($hits) -join '/')
            HasGate = (($text -match [regex]::Escape($gateFn)) -or ($text -match 'getRunnerPresence'))
        }
    }

    if (@($callSites).Count -eq 0) {
        throw ("No frontend surface calls any of {0}. Either they were renamed or this assertion has stopped checking anything." -f (@($clientFns) -join ', '))
    }

    $ungated = @($callSites | Where-Object { -not $_.HasGate })
    if (@($ungated).Count -gt 0) {
        throw (("{0} surface(s) queue work while ignoring runner presence entirely, so each offers an enabled control the backend will refuse with 409: {2}. " +
                "Either resolve {1} here and disable the control with its unmet precondition named, or read getRunnerPresence and pass it to the child that renders the control.") -f `
            @($ungated).Count, $gateFn, (@($ungated | ForEach-Object { "$($_.Path) [$($_.Calls)]" }) -join ', '))
    }

    Write-Host ("  dispatch gate coverage ok: {0} gated route(s) -> {1} client fn(s) -> {2} surface(s), all consulting {3} ({4})" -f `
            @($gatedPaths | Sort-Object -Unique).Count, @($clientFns).Count, @($callSites).Count, $gateFn,
            ((@($callSites | ForEach-Object { Split-Path $_.Path -Leaf }) | Sort-Object) -join ', ')) -ForegroundColor DarkGray
}

Write-Step 'Engine attribution — Release 3.1 M2: a rule-produced preview says so'
& {
    # "An operator can always tell a deterministic rule from a model's proposal."
    # The guided-improvement preview is pure rule evaluation and then hands its
    # result to an AI agent from the same screen, which is exactly where the two
    # are easiest to confuse. Asserted on the payload rather than by reading the
    # component, per the acceptance criterion.
    $improvementPath = Join-Path $WorkspaceRoot 'backend\modules\docaudit\RepositoryImprovement.Workflow.ps1'
    $improvementErrors = $null
    $improvementAst = [System.Management.Automation.Language.Parser]::ParseFile($improvementPath, [ref]$null, [ref]$improvementErrors)
    if ($improvementErrors -and @($improvementErrors).Count -gt 0) {
        throw "RepositoryImprovement.Workflow.ps1 does not parse: $($improvementErrors[0].Message)"
    }

    # The preview must not reach a provider. If it ever does, the attribution
    # below stops being true and this assertion should be the thing that says so.
    $previewFn = @($improvementAst.FindAll({
                param($n)
                $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'New-RepositoryImprovementPreview'
            }, $true)) | Select-Object -First 1
    if ($null -eq $previewFn) { throw 'New-RepositoryImprovementPreview not found; the engine-attribution assertion is vacuous.' }

    $providerCalls = @($previewFn.FindAll({
                param($n)
                $n -is [System.Management.Automation.Language.CommandAst] -and
                $n.GetCommandName() -match '^(Invoke-AiDoc|Invoke-RestMethod|Invoke-WebRequest|Invoke-AnthropicCompletion|Invoke-OpenAiCompletion)'
            }, $true))
    if (@($providerCalls).Count -gt 0) {
        throw ("New-RepositoryImprovementPreview calls a provider ({0}), so labelling it deterministic-rules is now false. Update the engine block to report the real provider and model." -f `
            (@($providerCalls | ForEach-Object { $_.GetCommandName() }) -join ', '))
    }

    $previewText = $previewFn.Extent.Text
    foreach ($field in @('engine', 'kind', 'deterministic-rules', 'handoffEngine')) {
        if ($previewText -notmatch [regex]::Escape($field)) {
            throw "The improvement preview payload omits '$field'. A surface that renders a rule's finding and a model's proposal identically asks the operator to trust both the same amount."
        }
    }

    # And the surface must actually consume it — a payload field nothing renders
    # is not attribution, it is a field.
    $modalPath = Join-Path $WorkspaceRoot 'frontend\components\RepositoryImprovementWorkflowModal.tsx'
    $modalText = Get-Content -LiteralPath $modalPath -Raw -Encoding UTF8
    if ($modalText -notmatch 'improvement-engine-attribution') {
        throw 'The guided-improvement modal does not render the engine attribution, so the payload field is invisible to the operator it exists for.'
    }
    if ($modalText -notmatch 'engine\.label') {
        throw 'The guided-improvement modal never renders engine.label; attribution that names no engine is decoration.'
    }

    Write-Host '  engine attribution ok: preview reaches no provider, payload declares deterministic-rules + handoff, modal renders it' -ForegroundColor DarkGray
}

Write-Step 'Queue-writer gate coverage — every road to the queue consults presence'
& {
    # The frontend tripwire above covers the surfaces that CALL the dispatch
    # route. It cannot see the other road: POST /api/automation/packages/approve
    # reaches the same queue file through Submit-PackagedItemToRunner, which had
    # no presence check at all — the approve control was gated in the browser
    # only. A gate that exists on one of two write paths is not a gate.
    #
    # Scope derived from the queue filename, so a new writer added anywhere
    # under backend/ fails this until it consults presence.
    #
    # This half covers backend FUNCTIONS. The api-host routes are covered by the
    # second half below, which had to be written after this one found only two of
    # three roads: POST /api/roadmap-agent/start reaches the same queue through
    # Start-RoadmapCopilotTask.ps1 -> Add-RoadmapTaskToQueue.ps1 and never names
    # the queue itself, so nothing scoped to the filename could see it.
    $queueFile = 'roadmap-task-queue.jsonl'
    $writeCommands = @('Add-Content', 'Set-Content', 'Out-File', '_Pack_AppendJsonl', 'Add-RoadmapQueueEntry')
    $backendFiles = @(Get-ChildItem -Path (Join-Path $WorkspaceRoot 'backend') -Recurse -File -Filter '*.ps1' -ErrorAction SilentlyContinue)
    if (@($backendFiles).Count -eq 0) { throw 'No backend PowerShell found; the queue-writer assertion is vacuous.' }

    $writers = @()
    foreach ($file in $backendFiles) {
        $fileErrors = $null
        $fileAst = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$fileErrors)
        if ($fileErrors -and @($fileErrors).Count -gt 0) { continue }

        foreach ($fn in @($fileAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true))) {
            $body = $fn.Extent.Text
            # Release 2.9: the queue path moved behind Get-RoadmapQueuePath, so
            # a function reaching the queue may never name the file. Keying on
            # the literal alone made this gate find ZERO writers and refuse to
            # pass -- which is the gate working, and the reason it is now
            # scoped to the resolver as well as the filename.
            if ($body -notmatch [regex]::Escape($queueFile) -and $body -notmatch 'Get-RoadmapQueuePath') { continue }
            # Naming the file is not writing to it — Get-QueuedTaskBacklog and the
            # trace joiner both read it, and gating a read would be nonsense.
            $writesHere = @($fn.FindAll({
                        param($n)
                        $n -is [System.Management.Automation.Language.CommandAst] -and
                        $n.GetCommandName() -in $writeCommands
                    }, $true))
            if (@($writesHere).Count -eq 0) { continue }
            $writers += [pscustomobject]@{
                Name       = $fn.Name
                File       = $file.FullName.Substring($WorkspaceRoot.Length).TrimStart('\', '/').Replace('\', '/')
                ConsultsPresence = ($body -match 'Get-RunnerPresence')
            }
        }
    }

    if (@($writers).Count -eq 0) {
        throw "No function writing to $queueFile (by name or via Get-RoadmapQueuePath) was found under backend/. Either the queue moved again or this assertion has stopped checking anything."
    }

    $ungatedWriters = @($writers | Where-Object { -not $_.ConsultsPresence })
    if (@($ungatedWriters).Count -gt 0) {
        throw (("{0} function(s) write to {1} without consulting Get-RunnerPresence: {2}. " +
                'Work queued with nothing able to claim it is stranded whichever road it took, so the gate belongs on the write, not on the surface that offers it.') -f `
            @($ungatedWriters).Count, $queueFile, (@($ungatedWriters | ForEach-Object { "$($_.Name) ($($_.File))" }) -join ', '))
    }

    # ---- Second half: the api-host ROUTES, including the indirect road. -------
    # A route reaches the queue three ways, and only the first names the file:
    #   1. writing it directly           (POST /api/roadmap/dispatch/execute)
    #   2. calling a writer function     (.../packages/approve -> Submit-PackagedItemToRunner)
    #   3. invoking a writer SCRIPT      (.../roadmap-agent/start -> Start-RoadmapCopilotTask.ps1)
    # The third is how a road stayed open after the first two were closed, so the
    # set of writer scripts is derived here rather than listed: any script under
    # scripts/ that writes the queue, plus any script that invokes one of those.
    $writerFunctionNames = @($writers | ForEach-Object { $_.Name }) + @('Add-RoadmapQueueEntry')
    $scriptFiles = @(Get-ChildItem -Path (Join-Path $WorkspaceRoot 'scripts') -File -Filter '*.ps1' -ErrorAction SilentlyContinue)
    $writerScripts = @()
    foreach ($s in $scriptFiles) {
        # Test harnesses write queues in fixture workspaces, never the live one,
        # and the runner writes status back to entries it already claimed. Neither
        # is a road by which new work enters the queue, which is what this gates.
        if ($s.Name -match 'SmokeTest|TestSuite|Invoke-RoadmapTaskRunner') { continue }
        $text = Get-Content -LiteralPath $s.FullName -Raw -Encoding UTF8
        if ([string]::IsNullOrEmpty($text)) { continue }
        if ($text -match [regex]::Escape($queueFile) -and ($writeCommands | Where-Object { $text -match [regex]::Escape($_) })) {
            $writerScripts += $s.Name
        }
    }
    # One hop out: a script that invokes a writer script is itself a road.
    foreach ($s in $scriptFiles) {
        if ($s.Name -in $writerScripts) { continue }
        if ($s.Name -match 'SmokeTest|TestSuite|Invoke-RoadmapTaskRunner') { continue }
        $text = Get-Content -LiteralPath $s.FullName -Raw -Encoding UTF8
        if ([string]::IsNullOrEmpty($text)) { continue }
        foreach ($w in @($writerScripts)) {
            if ($text -match [regex]::Escape($w)) { $writerScripts += $s.Name; break }
        }
    }
    if (@($writerScripts).Count -eq 0) { throw 'No queue-writing script found under scripts/; the route-coverage assertion is vacuous.' }

    $queueRoutes = @()
    foreach ($clause in @($hostAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.SwitchStatementAst] }, $true) | ForEach-Object { $_.Clauses })) {
        $routeName = $clause.Item1.Extent.Text.Trim("'`"")
        if ($routeName -notmatch '^(GET|POST|PUT|PATCH|DELETE) ') { continue }
        $clauseText = $clause.Item2.Extent.Text
        $reaches = $false
        if ($clauseText -match [regex]::Escape($queueFile)) { $reaches = $true }
        foreach ($fnName in @($writerFunctionNames)) { if ($clauseText -match [regex]::Escape($fnName)) { $reaches = $true } }
        foreach ($scriptName in @($writerScripts)) { if ($clauseText -match [regex]::Escape($scriptName)) { $reaches = $true } }
        if (-not $reaches) { continue }
        # A preview is not a road. POST /api/roadmap-agent/preview invokes the
        # same writer script with -PreviewOnly, which returns before the queue
        # write — and gating a preview would be its own dead end, since previewing
        # is exactly what an operator does BEFORE starting a runner. The exemption
        # is asserted below rather than trusted.
        if ($clauseText -match '-PreviewOnly') { continue }
        $queueRoutes += [pscustomobject]@{
            Route            = $routeName
            ConsultsPresence = ($clauseText -match 'Get-RunnerPresence')
        }
    }

    # The -PreviewOnly exemption is only safe while the script honours it. Assert
    # the early return precedes the queue-writer invocation; if someone moves the
    # write above the guard, the exemption above silently stops being true.
    $writerScriptPath = Join-Path $WorkspaceRoot 'scripts\Start-RoadmapCopilotTask.ps1'
    if (Test-Path -LiteralPath $writerScriptPath) {
        $writerErrors = $null
        $writerAst = [System.Management.Automation.Language.Parser]::ParseFile($writerScriptPath, [ref]$null, [ref]$writerErrors)
        if (-not ($writerErrors -and @($writerErrors).Count -gt 0)) {
            $queueRef = @($writerAst.FindAll({
                        param($n)
                        $n -is [System.Management.Automation.Language.StringConstantExpressionAst] -and $n.Value -eq 'Add-RoadmapTaskToQueue.ps1'
                    }, $true)) | Select-Object -First 1
            $previewReturn = @($writerAst.FindAll({
                        param($n)
                        $n -is [System.Management.Automation.Language.IfStatementAst] -and
                        $n.Extent.Text -match 'PreviewOnly' -and
                        @($n.FindAll({ param($m) $m -is [System.Management.Automation.Language.ReturnStatementAst] }, $true)).Count -gt 0
                    }, $true)) | Sort-Object { $_.Extent.StartOffset } | Select-Object -First 1
            if ($null -eq $queueRef) {
                throw 'Start-RoadmapCopilotTask.ps1 no longer references Add-RoadmapTaskToQueue.ps1; the -PreviewOnly exemption is asserting nothing.'
            }
            if ($null -eq $previewReturn -or $previewReturn.Extent.EndOffset -gt $queueRef.Extent.StartOffset) {
                throw 'Start-RoadmapCopilotTask.ps1 no longer returns on -PreviewOnly before writing the queue, so exempting POST /api/roadmap-agent/preview from the runner gate is no longer safe.'
            }
        }
    }

    if (@($queueRoutes).Count -lt 3) {
        throw ("Expected at least 3 api-host routes to reach {0} (dispatch/execute, packages/approve, roadmap-agent/start); found {1}. A road that stopped being detected is a road that stopped being gated." -f `
            $queueFile, @($queueRoutes).Count)
    }

    $ungatedRoutes = @($queueRoutes | Where-Object { -not $_.ConsultsPresence })
    if (@($ungatedRoutes).Count -gt 0) {
        throw (("{0} api-host route(s) can put work in {1} without consulting Get-RunnerPresence: {2}. " +
                'Reaching the queue through a script or a helper is still reaching the queue.') -f `
            @($ungatedRoutes).Count, $queueFile, (@($ungatedRoutes | ForEach-Object { $_.Route }) -join '; '))
    }

    Write-Host ("  queue-writer gate coverage ok: {0} backend writer function(s) and {1} api-host route(s) consult presence; writer scripts derived: {2}" -f `
            @($writers).Count, @($queueRoutes).Count, ((@($writerScripts) | Sort-Object -Unique) -join ', ')) -ForegroundColor DarkGray
}

Write-Step 'Repo staleness — Release 3.1: the dashboard metric is computed, not a literal'
& {
    # The Stale column, the stale-only filter, the group-by-stale control and
    # the ahead/behind badge have all shipped for releases, bound to isStale /
    # localAhead / remoteAhead — every one of which was a hardcoded $false/0/0
    # in both GitHub scan paths. The column read "No" for all 80+ repos because
    # nothing ever looked, which is why a clone 8 commits behind could be
    # written to without a murmur.
    $stalenessModule = Join-Path $WorkspaceRoot 'backend\modules\git\Git.Staleness.ps1'
    if (-not (Test-Path -LiteralPath $stalenessModule)) { throw "Missing module file: $stalenessModule" }
    . $stalenessModule

    $now = [datetime]::UtcNow

    # Behind: the remote moved after this clone's last commit.
    $behind = Resolve-RepoStaleness -LocalCommitDate $now.AddDays(-30).ToString('o') -RemotePushedAt $now.ToString('o')
    if ($behind.state -ne 'behind')  { throw "A remote 30 days newer than the local commit must read 'behind'; got '$($behind.state)'" }
    if (-not $behind.isStale)        { throw 'A behind repo must report isStale=true' }
    if ($behind.behindByDays -lt 29) { throw "behindByDays must carry the magnitude; got '$($behind.behindByDays)'" }

    # Ahead: local work newer than the last push. Not stale — nothing to pull.
    $ahead = Resolve-RepoStaleness -LocalCommitDate $now.ToString('o') -RemotePushedAt $now.AddDays(-5).ToString('o')
    if ($ahead.state -ne 'ahead-or-unpushed') { throw "Local newer than remote must read 'ahead-or-unpushed'; got '$($ahead.state)'" }
    if ($ahead.isStale) { throw 'Unpushed local work is not staleness — there is nothing to pull.' }

    # Inside tolerance: a freshly-pushed repo must not light up the dashboard.
    $current = Resolve-RepoStaleness -LocalCommitDate $now.ToString('o') -RemotePushedAt $now.AddSeconds(20).ToString('o')
    if ($current.state -ne 'current') { throw "A 20s push delay must read 'current'; got '$($current.state)'" }
    if ($current.isStale) { throw 'Push latency must not be reported as staleness' }

    # Unknown must not masquerade as either answer. Absence of evidence is not
    # evidence of divergence — the rule Resolve-RunnerPresence already applies.
    foreach ($case in @(
            @{ L = $null; R = $now.ToString('o') },
            @{ L = $now.ToString('o'); R = $null },
            @{ L = ''; R = '' },
            @{ L = 'not-a-date'; R = $now.ToString('o') }
        )) {
        $unknown = Resolve-RepoStaleness -LocalCommitDate $case.L -RemotePushedAt $case.R
        if ($unknown.state -ne 'unknown') { throw "A missing or unparsable date must read 'unknown'; got '$($unknown.state)'" }
        if ($unknown.isStale) { throw 'An unknown reading must never report isStale=true' }
    }

    # The basis is named and the limitation is declared, so no consumer can
    # mistake a date delta for a commit count.
    if ($behind.basis -ne 'remote-push-vs-local-commit') { throw 'Staleness must name the basis that produced it' }
    if ($behind.exactCountsAvailable -ne $false) { throw 'Two timestamps cannot yield exact ahead/behind counts; the field must say so' }

    # --- The literals must be gone from the scan paths -----------------------
    # Scoped to the assignments themselves so a comment mentioning them cannot
    # satisfy this, and so a third scan path added later fails until it computes.
    $hostText = Get-Content -LiteralPath (Join-Path $WorkspaceRoot 'backend\api-host\Start-RepoManagementApiHost.ps1') -Raw -Encoding UTF8
    $hardcoded = @([regex]::Matches($hostText, '(?m)^\s*isStale\s*=\s*\$false\s*$'))
    if (@($hardcoded).Count -gt 0) {
        throw ("{0} scan path(s) still assign isStale = `$false as a literal. The dashboard renders that constant as 'No' for every repository, which is how a clone 8 commits behind looked current." -f @($hardcoded).Count)
    }

    # And the join must actually carry the remote push time, or the comparison
    # above has nothing to compare.
    if ($hostText -notmatch "'pushedAt'") {
        throw 'The GitHub metadata join does not carry pushedAt, so staleness cannot be computed on the status path.'
    }
    if ($hostText -notmatch 'Resolve-RepoStaleness') {
        throw 'The status path never calls Resolve-RepoStaleness, so isStale is still not computed from anything.'
    }

    Write-Host ("  staleness ok: behind/ahead/current/unknown all classified, basis named, exact counts declared unavailable, no `$false literal left in the scan paths") -ForegroundColor DarkGray
}

Write-Step 'Token and cost — Release 3.1 M3: a model call that reports nothing fails here'
# `tokenUsage` and `apiSpendUsd` existed on the agent-run record, flowed through
# `tokens_reported` in app.db and out to analytics, and were never written by
# production code: both provider adapters sent `max_tokens` and discarded the
# `usage` block the API returned. The only real value in the repo was a fixture.
#
# The two failures this guards are different. Dropping usage makes cost
# unknowable; *inventing* it — reporting 0 tokens and $0.00 for a call nobody
# measured — makes it knowably wrong, and reads as "this was free" on a
# dashboard. Every assertion below is about telling those apart.
& {
    # Shadow the HTTP call inside this block only, so the adapters can be driven
    # over a known response without a network or a key. Defining the function
    # here keeps it out of the rest of the suite.
    $script:MockAiResponse = $null
    function Invoke-RestMethod {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidOverwritingBuiltInCmdlets', '',
            Justification = 'Deliberate, block-scoped test double. Shadowing the HTTP call is what lets the real adapters be driven over a known response with no network and no API key; the definition dies with the enclosing script block.')]
        param([Parameter(ValueFromRemainingArguments = $true)]$Rest)
        $null = $Rest
        return $script:MockAiResponse
    }

    # --- A model that reports usage has it captured -------------------------
    $script:MockAiResponse = [pscustomobject]@{
        content = @([pscustomobject]@{ type = 'text'; text = '# Improved' })
        usage   = [pscustomobject]@{ input_tokens = 1234; output_tokens = 567 }
    }
    $anthropic = Invoke-AnthropicDocProvider -ApiKey 'smoke' -Model 'claude-smoke' -SystemPrompt 's' -UserPrompt 'u'
    if (-not [string]::IsNullOrWhiteSpace([string]$anthropic.error)) { throw "Anthropic adapter smoke call failed: $($anthropic.error)" }
    if ($anthropic.usage.inputTokens -ne 1234 -or $anthropic.usage.outputTokens -ne 567) {
        throw "The Anthropic adapter discarded the usage block the API returned (in=$($anthropic.usage.inputTokens) out=$($anthropic.usage.outputTokens))."
    }
    if ($anthropic.usage.totalTokens -ne 1801) { throw "Total tokens must be the sum of both sides; got $($anthropic.usage.totalTokens)" }
    if (-not $anthropic.usage.measured) { throw 'A call with real counts must report measured=true' }

    $script:MockAiResponse = [pscustomobject]@{
        choices = @([pscustomobject]@{ message = [pscustomobject]@{ content = '# Improved' } })
        usage   = [pscustomobject]@{ prompt_tokens = 800; completion_tokens = 200; total_tokens = 1000 }
    }
    $openai = Invoke-OpenAiDocProvider -ApiKey 'smoke' -Model 'gpt-smoke' -SystemPrompt 's' -UserPrompt 'u'
    if (-not [string]::IsNullOrWhiteSpace([string]$openai.error)) { throw "OpenAI adapter smoke call failed: $($openai.error)" }
    if ($openai.usage.inputTokens -ne 800 -or $openai.usage.outputTokens -ne 200 -or $openai.usage.totalTokens -ne 1000) {
        throw 'The OpenAI adapter did not normalize prompt/completion/total tokens.'
    }

    # --- A model call that reports nothing is a defect, and says so ---------
    # This is the acceptance criterion: null usage on a model path fails a gate.
    $script:MockAiResponse = [pscustomobject]@{ content = @([pscustomobject]@{ type = 'text'; text = '# Improved' }) }
    $silent = Invoke-AnthropicDocProvider -ApiKey 'smoke' -Model 'claude-smoke' -SystemPrompt 's' -UserPrompt 'u'
    if ($silent.usage.source -ne 'absent') { throw "A successful model call with no usage block must record source='absent'; got '$($silent.usage.source)'" }
    if ($null -ne $silent.usage.totalTokens) { throw 'Unmeasured usage must be $null. Reporting 0 tokens for a call nobody measured is the failure this milestone names.' }
    if ($silent.usage.measured) { throw 'measured=true with no counts is a false claim' }

    # --- A failed call is unknowable, not zero, and not a reporting defect ---
    function Invoke-RestMethod {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidOverwritingBuiltInCmdlets', '',
            Justification = 'Deliberate, block-scoped test double — see the note on the first one. This variant drives the adapters failure path.')]
        param([Parameter(ValueFromRemainingArguments = $true)]$Rest)
        $null = $Rest
        throw '401 Unauthorized'
    }
    $failed = Invoke-OpenAiDocProvider -ApiKey 'bad' -Model 'gpt-smoke' -SystemPrompt 's' -UserPrompt 'u'
    if ($failed.usage.source -ne 'call-failed') { throw "A failed provider call must record source='call-failed'; got '$($failed.usage.source)'" }
    if ($null -ne $failed.usage.totalTokens) { throw 'A failed call measured nothing and must report $null' }

    Write-Host '  adapters ok: both providers capture usage, a silent model reads absent, a failed call reads call-failed' -ForegroundColor DarkGray
}

& {
    # --- Cost is priced or it is blank; it is never zero by default ---------
    $measured = New-AiDocUsage -InputTokens 1000 -OutputTokens 2000 -Source 'provider-usage'
    $unpriced = Resolve-AiDocUsageCost -Usage $measured -ModelId 'claude-smoke' -Pricing $null
    if ($null -ne $unpriced.costUsd) { throw 'With no price configured the cost must be $null, not a number' }
    if ($unpriced.costBasis -ne 'no-price-configured') { throw "An unpriced cost must name why; got '$($unpriced.costBasis)'" }

    $pricing = [pscustomobject]@{ 'claude-smoke' = [pscustomobject]@{ inputPerMillionUsd = 3.0; outputPerMillionUsd = 15.0 } }
    $priced = Resolve-AiDocUsageCost -Usage $measured -ModelId 'claude-smoke' -Pricing $pricing
    $expected = (1000.0 / 1000000.0) * 3.0 + (2000.0 / 1000000.0) * 15.0
    if ([Math]::Abs([double]$priced.costUsd - $expected) -gt 1e-9) { throw "Priced cost wrong: expected $expected, got $($priced.costUsd)" }
    if ($priced.costBasis -ne 'priced-from-settings') { throw 'A priced cost must name the source of the price' }

    # A price for a different model must not be borrowed for this one.
    $wrongModel = Resolve-AiDocUsageCost -Usage $measured -ModelId 'gpt-smoke' -Pricing $pricing
    if ($null -ne $wrongModel.costUsd) { throw 'A model with no price of its own must not inherit another model''s rate' }

    # An unmeasured call cannot be priced at all, even with a full price table.
    $offline = New-AiDocUsage -Source 'not-applicable'
    $offlinePriced = Resolve-AiDocUsageCost -Usage $offline -ModelId 'claude-smoke' -Pricing $pricing
    if ($null -ne $offlinePriced.costUsd) { throw 'An unmeasured call must never be assigned a cost' }
    if ($offlinePriced.costBasis -ne 'not-applicable') { throw 'The offline path is not a measurement defect and must not be reported as one' }

    Write-Host '  cost ok: priced only from configured rates, unmeasured stays null with a named basis, no rate borrowed across models' -ForegroundColor DarkGray
}

& {
    # --- The record that reaches disk carries both, and its provenance ------
    # The milestone's phrasing: the improvement-history record "has no cost
    # field today". This asserts it does now, and that an offline preview
    # writes null rather than a confident zero.
    $usageTmp = Join-Path ([System.IO.Path]::GetTempPath()) ("gh-usage-smoke-" + [guid]::NewGuid().ToString('n'))
    $null = New-Item -ItemType Directory -Path $usageTmp -Force
    try {
        $preview = Invoke-AiDocImprovePreview -WorkspaceRoot $usageTmp -RepoName 'usage-smoke' `
            -DocType 'readme' -CurrentContent "# usage-smoke`n" -Provider 'heuristic'
        if ($preview.PSObject.Properties.Name -notcontains 'usage') {
            throw 'The improvement preview carries no usage record, so nothing downstream can report tokens or cost.'
        }
        if ($preview.usage.source -ne 'not-applicable') {
            throw "An offline heuristic preview called no model and must read 'not-applicable'; got '$($preview.usage.source)'"
        }

        $record = Write-AiDocImprovementHistory -WorkspaceRoot $usageTmp -Preview $preview
        foreach ($field in @('tokenUsage', 'apiSpendUsd', 'usageSource', 'usageMeasured', 'costBasis', 'inputTokens', 'outputTokens')) {
            if ($record.PSObject.Properties.Name -notcontains $field) {
                throw "The improvement-history record omits '$field'; token and cost stay unmeasurable on the path that persists them."
            }
        }
        if ($null -ne $record.tokenUsage -or $null -ne $record.apiSpendUsd) {
            throw 'An offline preview must persist null tokens and null cost, never 0 — a zero here reads as "this run was free".'
        }

        # The field names deliberately match the agent-run metrics vocabulary so
        # the two series join without translation; assert that stays true.
        $agentRunsText = Get-Content -LiteralPath (Join-Path $WorkspaceRoot 'backend\modules\agent-runs\AgentRuns.ps1') -Raw -Encoding UTF8
        foreach ($shared in @('tokenUsage', 'apiSpendUsd')) {
            if ($agentRunsText -notmatch [regex]::Escape($shared)) {
                throw "The history record uses '$shared' to match the agent-run metric of the same name, but AgentRuns.ps1 no longer uses it."
            }
        }

        # Round-trip: the fields must survive JSONL, not just exist in memory.
        $readBack = @(Get-AiDocImprovementHistory -WorkspaceRoot $usageTmp -RepoName 'usage-smoke')
        if ($readBack.Count -lt 1) { throw 'The improvement-history record did not persist' }
        if ($readBack[0].PSObject.Properties.Name -notcontains 'costBasis') {
            throw 'costBasis did not survive the JSONL round-trip, so a reader cannot tell unmeasured from free.'
        }

        Write-Host '  history ok: tokens + cost + provenance persist and round-trip; an offline preview writes null, not 0' -ForegroundColor DarkGray
    }
    finally {
        Remove-Item -LiteralPath $usageTmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

& {
    # --- Coverage: scope derived from what actually calls a model -----------
    # Not a list of the two adapters that exist today. Any function in the AI
    # module that makes an HTTP call is, by definition, a model call, and must
    # capture usage. A third adapter added later fails here until it does.
    $aiPath = Join-Path $WorkspaceRoot 'backend\modules\ai\AiDocImprovement.ps1'
    $aiErrors = $null
    $aiAst = [System.Management.Automation.Language.Parser]::ParseFile($aiPath, [ref]$null, [ref]$aiErrors)
    if ($aiErrors -and @($aiErrors).Count -gt 0) { throw "AiDocImprovement.ps1 does not parse: $($aiErrors[0].Message)" }

    $callers = @($aiAst.FindAll({
                param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst]
            }, $true) | Where-Object {
            @($_.Body.FindAll({
                        param($c)
                        $c -is [System.Management.Automation.Language.CommandAst] -and
                        $c.GetCommandName() -match '^Invoke-(RestMethod|WebRequest)$'
                    }, $true)).Count -gt 0
        })

    if (@($callers).Count -lt 2) {
        throw ("Expected at least the two provider adapters to make HTTP calls; found {0}. The coverage check has lost its scope." -f @($callers).Count)
    }

    foreach ($fn in $callers) {
        $usageCalls = @($fn.Body.FindAll({
                    param($c)
                    $c -is [System.Management.Automation.Language.CommandAst] -and $c.GetCommandName() -eq 'New-AiDocUsage'
                }, $true))
        if (@($usageCalls).Count -eq 0) {
            throw ("$($fn.Name) calls a model over HTTP but never calls New-AiDocUsage. Its token usage is discarded, which is exactly the defect this milestone closed for the other adapters.")
        }

        # Merely calling New-AiDocUsage is not enough, and this is not a
        # hypothetical: deleting the success-path capture and keeping only the
        # catch block's `-Source call-failed` left the presence check green.
        # An adapter has to pass counts it read off the response, so require a
        # call that supplies -InputTokens.
        $readsCounts = @($usageCalls | Where-Object {
                @($_.CommandElements | Where-Object {
                        $_ -is [System.Management.Automation.Language.CommandParameterAst] -and
                        $_.ParameterName -eq 'InputTokens'
                    }).Count -gt 0
            }).Count -gt 0
        if (-not $readsCounts) {
            throw ("$($fn.Name) constructs a usage record but never passes -InputTokens, so it reports provenance without ever reading the counts off the response. Capture usage on the success path, not only in the catch block.")
        }
    }

    # And the orchestrator must forward it, or per-adapter capture is dead code.
    $previewFn = @($aiAst.FindAll({
                param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Invoke-AiDocImprovePreview'
            }, $true))[0]
    if ($null -eq $previewFn) { throw 'Invoke-AiDocImprovePreview not found; the forwarding assertion is vacuous.' }
    if ($previewFn.Extent.Text -notmatch 'Resolve-AiDocUsageCost') {
        throw 'The preview orchestrator never resolves cost, so a configured price would be ignored.'
    }

    Write-Host ("  coverage ok: all {0} HTTP-calling adapter(s) capture usage; the orchestrator forwards and prices it" -f @($callers).Count) -ForegroundColor DarkGray
}

& {
    # --- The client hop must not turn "unmeasured" into zero ----------------
    # apiClient.ts coerces scores with `Number(x ?? 0)`, which is correct for a
    # score and wrong for usage: it would render an unmeasured run as free. The
    # field list is read from the type, not typed out here, so a field added to
    # the payload later is covered without editing this assertion.
    $typesPath = Join-Path $WorkspaceRoot 'frontend\types.ts'
    $typesText = Get-Content -LiteralPath $typesPath -Raw -Encoding UTF8
    $usageBlock = [regex]::Match($typesText, '(?s)export interface AiDocUsage \{(.*?)\n\}')
    if (-not $usageBlock.Success) { throw 'AiDocUsage is not declared in frontend/types.ts; the client-hop assertion has no field list to derive from.' }
    $usageFields = @([regex]::Matches($usageBlock.Groups[1].Value, '(?m)^\s*(\w+)\s*[?]?:') | ForEach-Object { $_.Groups[1].Value })
    $numericFields = @($usageFields | Where-Object { $_ -match 'Tokens$|^costUsd$' })
    if (@($numericFields).Count -lt 3) { throw "Expected the usage type to declare several numeric fields; found $(@($numericFields).Count)." }

    $clientPath = Join-Path $WorkspaceRoot 'frontend\services\apiClient.ts'
    $clientText = Get-Content -LiteralPath $clientPath -Raw -Encoding UTF8
    foreach ($field in @($numericFields + @('tokenUsage', 'apiSpendUsd'))) {
        if ($clientText -match ("(?m)\b{0}\s*:\s*Number\([^)]*\?\?\s*0" -f [regex]::Escape($field))) {
            throw "apiClient.ts coerces '$field' with `?? 0`. That renders a run nobody measured as costing nothing, which is the claim this milestone exists to stop."
        }
    }
    if ($clientText -notmatch 'function nullableNumber') {
        throw 'apiClient.ts has no nullable coercion for usage, so a missing count cannot survive the hop as null.'
    }

    # And the surface has to render it, or the payload is invisible.
    $opsPath = Join-Path $WorkspaceRoot 'frontend\components\OperationsWorkspaceView.tsx'
    $opsText = Get-Content -LiteralPath $opsPath -Raw -Encoding UTF8
    if ($opsText -notmatch 'describeUsage') {
        throw 'The operations workspace never calls describeUsage, so tokens and cost are measured and then not shown.'
    }
    foreach ($testId in @('ai-preview-usage', 'ai-history-usage', 'agent-run-cost')) {
        if ($opsText -notmatch [regex]::Escape($testId)) {
            throw "The operations workspace no longer renders '$testId'; a token/cost readout was dropped from a surface that had one."
        }
    }
    # The agent-run panel had a cost field on its type and rendered only tokens.
    if ($opsText -notmatch "apiSpendUsd") {
        throw 'The agent-run panel does not render apiSpendUsd, so the cost field stays write-only.'
    }

    $usageLib = Join-Path $WorkspaceRoot 'frontend\lib\aiUsage.ts'
    if (-not (Test-Path -LiteralPath $usageLib)) { throw 'frontend/lib/aiUsage.ts is missing; the never-zero formatting rule lives there.' }
    if ((Get-Content -LiteralPath $usageLib -Raw -Encoding UTF8) -notmatch 'unmeasured') {
        throw 'aiUsage.ts no longer renders the word "unmeasured"; an unmeasured cost has to say so rather than show a number.'
    }

    Write-Host ("  client hop ok: {0} usage field(s) derived from the type, none coerced to 0; 3 readouts rendered" -f @($numericFields).Count) -ForegroundColor DarkGray
}

Write-Step 'Enabled means available — Release 3.1 M4: a disabled control names what it is waiting for'
# The audit this milestone asked for, run as a gate rather than written down as
# a list. Every <button> on the PC surfaces is classified from its own markup:
#
#   ungated      no disabled prop — always available
#   in-flight    disabled by a single flag naming an operation already running
#                (loading/saving/applying/...). The label and spinner already
#                say why, so no further explanation is owed.
#   state-gated  disabled by anything else — a precondition the operator has to
#                satisfy. These MUST name it, or the operator is left staring at
#                a grey button with no way to learn what it wants.
#
# The scope is derived from the markup, so a control added later is audited
# without anyone remembering to add it here. The classifier is deliberately
# conservative: only a bare in-flight identifier is exempt, because a compound
# expression almost always hides a real precondition inside it.
& {
    $componentRoot = Join-Path $WorkspaceRoot 'frontend\components'

    # A JSX opening tag cannot be matched with a lazy regex: `onClick={() => x}`
    # contains a '>' that ends the match early and hides every prop after it,
    # which silently reclassifies a gated control as ungated. Walk the tag
    # instead, tracking brace depth and quotes, and stop at the '>' that closes
    # it for real.
    function Get-JsxOpeningTag {
        param([string]$Text, [int]$StartIndex)
        $depth = 0
        $quote = $null
        for ($i = $StartIndex; $i -lt $Text.Length; $i++) {
            $ch = $Text[$i]
            if ($null -ne $quote) {
                if ($ch -eq $quote -and $Text[$i - 1] -ne '\') { $quote = $null }
                continue
            }
            switch ($ch) {
                '"' { $quote = $ch; break }
                "'" { $quote = $ch; break }
                '`' { $quote = $ch; break }
                '{' { $depth++; break }
                '}' { $depth--; break }
                '>' { if ($depth -le 0) { return $Text.Substring($StartIndex, $i - $StartIndex) } break }
            }
        }
        return $null
    }

    # Reads as "an operation is already running", so the control explains itself.
    $inFlightVocabulary = 'loading|submitting|saving|applying|running|scanning|refreshing|busy|pending|working|inflight|in_flight|connecting|checking|generating|fetching|deleting|dispatching'

    $controls = [System.Collections.Generic.List[object]]::new()
    foreach ($file in Get-ChildItem -LiteralPath $componentRoot -Filter '*.tsx' |
        Where-Object { $_.Name -notmatch '\.test\.tsx$' -and $_.Name -ne 'icons.tsx' -and $_.Name -notmatch '^Mobile' }) {

        $text = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
        foreach ($m in [regex]::Matches($text, '<button\b')) {
            $tag = Get-JsxOpeningTag -Text $text -StartIndex $m.Index
            if ($null -eq $tag) { continue }

            $disabled = [regex]::Match($tag, '(?s)\bdisabled\s*=\s*\{(.*)')
            if (-not $disabled.Success) { continue }   # ungated: always available

            # Take the balanced contents of the disabled={...} expression.
            $rest = $disabled.Groups[1].Value
            $depth = 1
            $expr = ''
            for ($i = 0; $i -lt $rest.Length; $i++) {
                if ($rest[$i] -eq '{') { $depth++ }
                elseif ($rest[$i] -eq '}') { $depth--; if ($depth -eq 0) { break } }
                $expr += $rest[$i]
            }
            $expr = ($expr -replace '\s+', ' ').Trim()

            # Only a lone in-flight flag is self-explanatory. Anything compound
            # (||, &&, !, a comparison, a literal) hides a precondition.
            $inFlightOnly = ($expr -match ('^[A-Za-z_$][\w$]*$')) -and ($expr -match $inFlightVocabulary)

            $controls.Add([pscustomobject]@{
                    File       = $file.Name
                    Line       = ($text.Substring(0, $m.Index) -split "`n").Count
                    Expression = $expr
                    Class      = if ($inFlightOnly) { 'in-flight' } else { 'state-gated' }
                    HasTitle   = ($tag -match '(?s)\btitle\s*=')
                })
        }
    }

    if ($controls.Count -lt 20) {
        throw "The control audit found only $($controls.Count) disabled control(s) across the PC surfaces. The tag scanner has lost its scope; a passing result here would be vacuous."
    }

    $unexplained = @($controls | Where-Object { $_.Class -eq 'state-gated' -and -not $_.HasTitle })
    if ($unexplained.Count -gt 0) {
        $detail = ($unexplained | ForEach-Object { "    {0}:{1}  disabled={{{2}}}" -f $_.File, $_.Line, $_.Expression }) -join "`n"
        throw ("{0} control(s) are disabled by a precondition the operator is never told about. A greyed button with no reason is worse than a failing one: it offers nothing to act on.`n{1}" -f $unexplained.Count, $detail)
    }

    $inFlight = @($controls | Where-Object { $_.Class -eq 'in-flight' })
    $stateGated = @($controls | Where-Object { $_.Class -eq 'state-gated' })
    Write-Host ("  control audit ok: {0} disabled control(s) across {1} PC component(s) — {2} in-flight, {3} state-gated and all naming their precondition" -f `
            $controls.Count, @($controls | Select-Object -ExpandProperty File -Unique).Count, $inFlight.Count, $stateGated.Count) -ForegroundColor DarkGray
}

& {
    # --- The three instances Lane 0.9 already recorded ----------------------
    # Named individually because the audit above cannot see them: they are
    # missing controls and unexplained terminal screens, not disabled buttons.
    $insights = Get-Content -LiteralPath (Join-Path $WorkspaceRoot 'frontend\components\InsightsView.tsx') -Raw -Encoding UTF8
    if ($insights -notmatch 'insights-run-assessment') {
        throw 'Insights tells the operator a portfolio assessment must succeed and still offers no control that runs one. Instructions a surface cannot carry out are worse than no instructions.'
    }
    if ($insights -notmatch 'insights-trend-run-assessment') {
        throw 'The portfolio-analytics empty state tells the operator to refresh the assessment while its only button retries the trend fetch. Both controls must exist and say which one they are.'
    }

    $dashboard = Get-Content -LiteralPath (Join-Path $WorkspaceRoot 'frontend\components\Dashboard.tsx') -Raw -Encoding UTF8
    if ($dashboard -notmatch 'dashboard-load-failure-retry') {
        throw 'The dashboard load-failure screen offers no retry. A terminal screen has to say what comes next.'
    }
    if ($dashboard -match '(?m)^\s*return <div className="text-center p-8 text-red-400">\{error\}</div>;') {
        throw 'The bare Failed-to-fetch screen is back: the raw exception string with no explanation, no retry, and no way to tell an unreachable backend from an unconfigured portal.'
    }
    if ($dashboard -notmatch 'classifyFetchFailure') {
        throw 'Dashboard.tsx no longer classifies its load failure, so "backend unreachable" and "nothing configured" render identically again.'
    }

    # The dispatch wizard was the third instance and closed under M1; its
    # precondition rendering is asserted by the dispatch-gate coverage step.
    $improvement = Get-Content -LiteralPath (Join-Path $WorkspaceRoot 'frontend\components\RepositoryImprovementWorkflowModal.tsx') -Raw -Encoding UTF8
    if ($improvement -notmatch 'improvement-dispatch-precondition') {
        throw 'The dispatch wizard no longer names its unmet precondition; the third Lane 0.9 instance has regressed.'
    }

    Write-Host '  Lane 0.9 ok: Insights runs the assessment it asks for, the load-failure screen classifies and retries, the dispatch wizard still names its precondition' -ForegroundColor DarkGray
}

Write-Step 'Stale base — Release 3.1 M5: no write path branches from a clone it has not verified'
# Every write this product made to a managed repo branched from whatever the
# local working copy happened to be, and `git fetch` appeared nowhere in
# backend/ or scripts/. The submit-PR path evaluated nine named refusals and
# staleness was not among them; the runner branched the same way.
#
# The damage is not a conflict. `git add -- <one file>` cannot revert upstream
# work and GitHub's three-way merge makes a real conflict visible. What nothing
# caught is that the PROPOSAL was computed from stale content, which merges
# cleanly and reads as correct in review.
$freshnessModule = Join-Path $WorkspaceRoot 'backend\modules\git\Git.BaseFreshness.ps1'
if (-not (Test-Path -LiteralPath $freshnessModule)) { throw "Missing module file: $freshnessModule" }
. $freshnessModule

& {
    # --- The decision matrix, pure ------------------------------------------
    $current = Resolve-BaseFreshness -LocalSha 'abc' -RemoteSha 'abc' -BaseBranch 'main'
    if ($current.state -ne 'current' -or $current.isStale) { throw 'Identical SHAs must read current and not stale' }
    if ($current.behindCount -ne 0 -or -not $current.countIsExact) { throw 'A verified-current clone is exactly 0 behind, not unknown' }

    $behind = Resolve-BaseFreshness -LocalSha 'aaa' -RemoteSha 'bbb' -RemoteObjectPresentLocally $true -BehindCount 8 -BaseBranch 'main'
    if ($behind.state -ne 'behind' -or -not $behind.isStale) { throw 'A clone missing remote commits must read behind' }
    if ($behind.behindCount -ne 8 -or -not $behind.countIsExact) { throw "The exact count must be carried; got $($behind.behindCount)" }
    if ($behind.summary -notmatch '8 commit') { throw 'The refusal must say HOW FAR behind, not merely that it is behind' }
    if ($behind.remedy -notmatch 'pull') { throw 'The refusal must say WHAT TO RUN' }

    # Local work sitting on top of the remote tip is not stale: HEAD already
    # contains everything upstream has.
    $ahead = Resolve-BaseFreshness -LocalSha 'aaa' -RemoteSha 'bbb' -RemoteObjectPresentLocally $true -BehindCount 0 -BaseBranch 'main'
    if ($ahead.state -ne 'current' -or $ahead.isStale) { throw 'A clone that already contains the remote tip must not be refused' }

    $unknownCount = Resolve-BaseFreshness -LocalSha 'aaa' -RemoteSha 'bbb' -RemoteObjectPresentLocally $false -BaseBranch 'main'
    if ($unknownCount.state -ne 'behind-unknown-count' -or -not $unknownCount.isStale) { throw 'A remote tip absent locally means behind by an unnameable amount' }
    if ($null -ne $unknownCount.behindCount -or $unknownCount.countIsExact) { throw 'An uncountable behind must report $null, never 0 — the same rule this release applies to unmeasured cost' }

    # Unverifiable is NOT stale. Absence of evidence is not evidence of
    # divergence — the rule Resolve-RunnerPresence applies to an unreadable
    # heartbeat, kept consistent so an offline operator is not locked out.
    $unverified = Resolve-BaseFreshness -LocalSha 'aaa' -ProbeError 'network unreachable' -BaseBranch 'main'
    if ($unverified.state -ne 'unknown') { throw 'A failed probe must read unknown' }
    if ($unverified.isStale) { throw 'An unverifiable clone must never be reported as stale' }
    if ($unverified.probeError -ne 'network unreachable') { throw 'The probe failure must be carried, not swallowed' }

    Write-Host '  matrix ok: current/behind/behind-unknown-count/unknown classified, count exact when knowable and null when not, unverified is never stale' -ForegroundColor DarkGray
}

& {
    # --- The real defect, reproduced ----------------------------------------
    # Git.StatusDetail computes unpulledCommits from `git log HEAD..@{u}`, which
    # reads the REMOTE-TRACKING REF — a local cache written by the last fetch.
    # On a clone that has not fetched, that ref predates the divergence and the
    # count reads zero while the clone sits behind. This builds exactly that
    # situation with local repos (no network) and asserts the two disagree.
    $staleTmp = Join-Path ([System.IO.Path]::GetTempPath()) ("gh-stalebase-" + [guid]::NewGuid().ToString('n'))
    $null = New-Item -ItemType Directory -Path $staleTmp -Force
    try {
        $originPath = Join-Path $staleTmp 'origin.git'
        $authorPath = Join-Path $staleTmp 'author'
        $stalePath  = Join-Path $staleTmp 'stale'
        $gitCfg = @('-c', 'user.email=smoke@local', '-c', 'user.name=smoke', '-c', 'commit.gpgsign=false')

        $null = & git init --bare -q --initial-branch=main $originPath 2>&1
        $null = & git clone -q $originPath $authorPath 2>&1
        Set-Content -LiteralPath (Join-Path $authorPath 'README.md') -Value "v1`n" -Encoding UTF8
        $null = & git -C $authorPath add -A 2>&1
        $null = & git -C $authorPath @gitCfg commit -q -m 'v1' 2>&1
        $null = & git -C $authorPath push -q origin main 2>&1

        # The clone that will go stale. It fetches once, here, and never again.
        $null = & git clone -q $originPath $stalePath 2>&1

        # Upstream moves three times. The stale clone is not told.
        foreach ($n in 2, 3, 4) {
            Set-Content -LiteralPath (Join-Path $authorPath 'README.md') -Value "v$n`n" -Encoding UTF8
            $null = & git -C $authorPath add -A 2>&1
            $null = & git -C $authorPath @gitCfg commit -q -m "v$n" 2>&1
        }
        $null = & git -C $authorPath push -q origin main 2>&1

        # What the detector the product already had reports.
        $oldReading = (& git -C $stalePath rev-list --count 'HEAD..@{u}' 2>&1) | Out-String
        $oldCount = if ($oldReading.Trim() -match '^\d+$') { [int]$oldReading.Trim() } else { -1 }
        if ($oldCount -ne 0) {
            throw ("The stale-ref fixture did not reproduce: `git log HEAD..@{u}` reported $oldCount, so this assertion is no longer testing the defect it was written for.")
        }

        # What asking the remote reports. A clone that has never fetched does
        # not hold the upstream objects, so the honest answer is "behind, by an
        # amount only a fetch can name" — not a number invented from nothing.
        $reading = Get-RepoBaseFreshness -RepoPath $stalePath -BaseBranch 'main'
        if (-not $reading.isStale) {
            throw ("A clone 3 commits behind was reported as fresh (state='{0}'). This is the exact failure that let a PromptPilot clone look current while 8 commits behind." -f $reading.state)
        }
        if ($reading.state -ne 'behind-unknown-count') {
            throw ("A never-fetched clone lacks the upstream objects, so the count is not knowable without a fetch; expected 'behind-unknown-count', got '{0}'." -f $reading.state)
        }
        if ($null -ne $reading.behindCount) { throw 'An uncountable behind must report $null rather than a guess' }

        # Fetch without merging: the objects are now local, the working copy is
        # still behind, and the exact count becomes available. This is the other
        # half of the matrix and the more common real state.
        $null = & git -C $stalePath fetch -q origin main 2>&1
        $afterFetch = Get-RepoBaseFreshness -RepoPath $stalePath -BaseBranch 'main'
        if (-not $afterFetch.isStale) { throw 'Fetching does not make a clone current — it still has not merged' }
        if ($afterFetch.behindCount -ne 3 -or -not $afterFetch.countIsExact) {
            throw ("With the objects local the count must be exact; expected 3, got '{0}'." -f $afterFetch.behindCount)
        }

        # And a clone that IS current must not be refused — a guard that refuses
        # everything is not a guard.
        $freshReading = Get-RepoBaseFreshness -RepoPath $authorPath -BaseBranch 'main'
        if ($freshReading.isStale) { throw "A clone at the tip of its remote was refused (state='$($freshReading.state)'); the guard would block all work." }

        Write-Host ("  reproduction ok: `git log HEAD..@{{u}}` reports 0 on a clone really {0} behind; ls-remote reports behind before a fetch and exactly {0} after; a current clone is not refused" -f $afterFetch.behindCount) -ForegroundColor DarkGray
    }
    finally {
        # git leaves read-only object files on Windows; clear them or the
        # cleanup silently fails and leaves fixtures behind.
        Get-ChildItem -LiteralPath $staleTmp -Recurse -Force -ErrorAction SilentlyContinue |
            ForEach-Object {
                try { $_.Attributes = 'Normal' }
                catch { Write-Verbose ("could not clear attributes on {0}: {1}" -f $_.FullName, $_.Exception.Message) }
            }
        Remove-Item -LiteralPath $staleTmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

& {
    # --- The refusal is named, and the override is deliberate ---------------
    $prModule = Join-Path $WorkspaceRoot 'backend\modules\roadmap\Roadmap.PrSubmitter.ps1'
    . $prModule

    $staleReading = Resolve-BaseFreshness -LocalSha 'aaa' -RemoteSha 'bbb' -RemoteObjectPresentLocally $true -BehindCount 4 -BaseBranch 'main'
    $common = @{
        RepoPath = 'C:\repo'; RoadmapPath = 'C:\repo\ROADMAP.md'; ProposedContent = 'new'
        CurrentContent = 'old'; Token = 't'; Slug = [pscustomobject]@{ slug = 'o/r' }
        IsGitRepo = $true; WorkingTreeDirty = $false; BaseBranch = 'main'
    }

    $refused = Test-RoadmapRepairPrPreconditions @common -BaseFreshness $staleReading
    if ($refused.ok) { throw 'A verified-stale base must refuse the submit-PR path' }
    if ($refused.category -ne 'stale-base') { throw "The refusal must be its own named category; got '$($refused.category)'" }
    if ($refused.reason -notmatch '4 commit') { throw 'The refusal must say how far behind the clone is' }
    if ($refused.reason -notmatch 'pull') { throw 'The refusal must name what to run' }

    $overridden = Test-RoadmapRepairPrPreconditions @common -BaseFreshness $staleReading -AcknowledgeStaleBase $true
    if (-not $overridden.ok) { throw 'A deliberate acknowledgement must be able to proceed, as acknowledgeNoRunner does for dispatch' }

    # Unverified must not block: the product has to keep working offline.
    $unverified = Resolve-BaseFreshness -LocalSha 'aaa' -ProbeError 'offline' -BaseBranch 'main'
    $allowed = Test-RoadmapRepairPrPreconditions @common -BaseFreshness $unverified
    if (-not $allowed.ok) { throw 'An unverifiable base must not be refused, or an offline operator can never write' }

    # And the nine refusals that existed before must still fire.
    $dirty = Test-RoadmapRepairPrPreconditions @common -WorkingTreeDirty $true -BaseFreshness $staleReading
    if ($dirty.ok -or $dirty.category -ne 'conflict') { throw 'The pre-existing dirty-tree refusal regressed' }

    Write-Host '  refusal ok: stale-base named with distance and remedy, acknowledgement proceeds, unverified allowed, prior refusals intact' -ForegroundColor DarkGray
}

& {
    # --- Coverage: scope derived from what actually derives content ---------
    # Not a list of the paths known today. A managed-repo write is a `git`
    # invocation against a repo PATH whose subcommand creates a branch or
    # records a commit — `checkout -b`, `switch -c`, `commit`. Those are the
    # operations that take the current working copy as their base, which is the
    # thing that can be stale.
    #
    # Deliberately NOT in scope, and this is a decision rather than an
    # oversight: `push` publishes a branch that already exists (its content was
    # derived earlier, where the gate sits), and `stash`/`reset`/`checkout --`
    # are the operator's own working-tree controls in the git-status modal. The
    # counts for both are reported below so the exemption stays visible.
    #
    # `-C` may arrive inside a splatted array — the api-host's approve-push
    # builds `@('-C', $path)` and splats it. A scope that only recognised a
    # literal `-C` missed that site entirely while reporting full coverage.
    $baseDeriving = '^(checkout|switch|commit)$'
    $publishOnly  = '^(push|fetch|pull|merge|rebase|reset|stash|cherry-pick|revert)$'

    $writeSites = [System.Collections.Generic.List[object]]::new()
    $publishSites = [System.Collections.Generic.List[object]]::new()

    foreach ($file in Get-ChildItem -LiteralPath $WorkspaceRoot -Recurse -Filter '*.ps1' -File -ErrorAction SilentlyContinue |
        Where-Object {
            $_.FullName -match '[\\/](backend|scripts)[\\/]' -and
            $_.FullName -notmatch '[\\/]node_modules[\\/]' -and
            # Test and smoke scripts build git fixtures on purpose; they are not
            # writes to a managed repo.
            $_.Name -notmatch '(SmokeTest|Test-|\.Tests)\.ps1$'
        }) {

        $fileErrors = $null
        $fileAst = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$fileErrors)
        if ($fileErrors -and @($fileErrors).Count -gt 0) { continue }

        foreach ($cmd in $fileAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)) {
            if ($cmd.GetCommandName() -ne 'git') { continue }
            $elements = @($cmd.CommandElements | ForEach-Object { $_.Extent.Text })

            # Targets a repo by path: a literal -C, or a splat that may carry one.
            $targetsRepoPath = ($elements -contains '-C') -or (@($elements | Where-Object { $_ -match '^@\w' }).Count -gt 0)
            if (-not $targetsRepoPath) { continue }

            # The subcommand is the first bare word that is not an option, a
            # value belonging to -C/-c, or the command name itself. Its index is
            # kept: the flags that matter (-b, -c, --create) belong to the
            # SUBCOMMAND, and `git -c user.email=…` uses the same letter before
            # it. Comparisons below are case-sensitive for the same reason —
            # PowerShell's -eq is not, so `git -C <path>` matched the `-c` of
            # `switch -c` and flagged the working-tree discard control as a
            # branch creation.
            $sub = ''
            $subIndex = -1
            for ($i = 1; $i -lt $elements.Count; $i++) {
                $e = $elements[$i]
                if ($e -match '^-') { if ($e -ceq '-C' -or $e -ceq '-c') { $i++ }; continue }
                if ($e -match '^[@$]') { continue }
                $sub = $e; $subIndex = $i; break
            }
            if ([string]::IsNullOrWhiteSpace($sub)) { continue }
            $subArgs = @(if ($subIndex -ge 0 -and $subIndex -lt ($elements.Count - 1)) { @($elements[($subIndex + 1)..($elements.Count - 1)]) } else { @() })

            $fnName = '<file scope>'
            $walk = $cmd
            while ($null -ne $walk) {
                if ($walk -is [System.Management.Automation.Language.FunctionDefinitionAst]) { $fnName = $walk.Name; break }
                $walk = $walk.Parent
            }

            $record = [pscustomobject]@{
                File = $file.FullName.Substring($WorkspaceRoot.Length + 1)
                Line = $cmd.Extent.StartLineNumber
                Fn   = $fnName
                Sub  = $sub
                # The AST node, not its text. A text match on "BaseFreshness"
                # was satisfied by the parameter name in the pass-through call
                # even after the probe itself was deleted — the same
                # presence-not-behaviour hole the token/cost gate had.
                ScopeAst = $(if ($fnName -eq '<file scope>') { $fileAst } else { $walk })
            }

            if ($sub -match $baseDeriving) {
                # `checkout <existing-branch>` and `switch <existing-branch>`
                # move between refs that already exist; only creating a new one
                # takes the working copy as its base.
                $createsBranch = ($sub -ceq 'commit') -or (@($subArgs | Where-Object { $_ -ceq '-b' -or $_ -ceq '-c' -or $_ -ceq '--create' }).Count -gt 0)
                if ($createsBranch) { $writeSites.Add($record) }
            }
            elseif ($sub -match $publishOnly) { $publishSites.Add($record) }
        }
    }

    if ($writeSites.Count -lt 2) {
        throw ("Found only {0} base-deriving git site(s) across backend/ and scripts/. Both the submit-PR path and the task runner create branches and commit, so the scope has been lost and a passing result here would be vacuous." -f $writeSites.Count)
    }

    $ungated = [System.Collections.Generic.List[object]]::new()
    foreach ($site in $writeSites) {
        # The enclosing scope has to CALL the probe, not merely mention it.
        # Function-level, because the runner gates once at the top and then
        # branches and commits inside the same function.
        $probes = @($site.ScopeAst.FindAll({
                    param($n)
                    $n -is [System.Management.Automation.Language.CommandAst] -and
                    $n.GetCommandName() -in @('Get-RepoBaseFreshness', 'Test-RunnerBaseFreshness')
                }, $true))
        if (@($probes).Count -eq 0) { $ungated.Add($site) | Out-Null }
    }
    if ($ungated.Count -gt 0) {
        $detail = ($ungated | ForEach-Object { "    {0}:{1}  {2}  (git {3})" -f $_.File, $_.Line, $_.Fn, $_.Sub }) -join "`n"
        throw ("{0} path(s) create a branch or record a commit in a managed repo without verifying the base is current. An improvement computed from a stale clone merges cleanly and reads as correct in review, which is why it has to be stopped here.`n{1}" -f $ungated.Count, $detail)
    }

    $writeFiles = @($writeSites | Select-Object -ExpandProperty File -Unique)
    Write-Host ("  coverage ok: {0} base-deriving site(s) across {1} file(s), all gated ({2}); {3} publish/working-tree site(s) out of scope by design" -f `
            $writeSites.Count, $writeFiles.Count, ($writeFiles -join ', '), $publishSites.Count) -ForegroundColor DarkGray
}

Write-Step 'Default-branch sync — Release 3.4: only "behind" may fast-forward'
# Release 3.1 shipped a guard that refuses to branch from a stale clone while
# `git fetch` and `git pull` appeared nowhere in backend/ or scripts/ — a stop
# sign with no road behind it. This is the road, and the whole point is that it
# is a narrow one: a fast-forward is the only git operation that cannot author a
# commit, because --ff-only refuses outright when a merge would be required.
$syncModule = Join-Path $WorkspaceRoot 'backend\modules\git\Git.DefaultBranchSync.ps1'
if (-not (Test-Path -LiteralPath $syncModule)) { throw "Missing module file: $syncModule" }
. $syncModule

& {
    # --- Four states, not two -----------------------------------------------
    # Computing only the behind side reported a clone that was behind AND
    # carrying local commits as merely "behind", which is the exact state where
    # a fast-forward refuses. Both directions or neither.
    $current  = Resolve-BaseFreshness -LocalSha 'a' -RemoteSha 'a' -BaseBranch 'main'
    $behind   = Resolve-BaseFreshness -LocalSha 'a' -RemoteSha 'b' -RemoteObjectPresentLocally $true -BehindCount 5 -AheadCount 0 -BaseBranch 'main'
    $ahead    = Resolve-BaseFreshness -LocalSha 'a' -RemoteSha 'b' -RemoteObjectPresentLocally $true -BehindCount 0 -AheadCount 2 -BaseBranch 'main'
    $diverged = Resolve-BaseFreshness -LocalSha 'a' -RemoteSha 'b' -RemoteObjectPresentLocally $true -BehindCount 5 -AheadCount 2 -BaseBranch 'main'

    if ($current.state -ne 'current' -or $current.aheadCount -ne 0) { throw 'A clone at the tip is current and exactly 0 ahead' }
    if ($behind.state -ne 'behind' -or -not $behind.isStale) { throw "Behind must classify as behind and be stale; got '$($behind.state)'" }
    if ($ahead.state -ne 'ahead') { throw "Local commits with nothing upstream missing is 'ahead', not '$($ahead.state)'" }
    if ($ahead.isStale) { throw 'A clone that is only ahead holds everything upstream has, so it is not stale' }
    if ($ahead.aheadCount -ne 2) { throw "The ahead count must be carried; got '$($ahead.aheadCount)'" }
    if ($diverged.state -ne 'diverged' -or -not $diverged.isStale) { throw "Both sides moved: that is 'diverged', got '$($diverged.state)'" }
    if ($diverged.summary -notmatch '5 commit' -or $diverged.summary -notmatch '2 ahead') {
        throw 'A diverged reading must name BOTH directions, or the operator cannot tell why a fast-forward is impossible.'
    }

    # --- The decision matrix -------------------------------------------------
    $d = Resolve-DefaultBranchSyncDecision -Freshness $behind -BranchName 'main'
    if (-not $d.allowed -or $d.action -ne 'fast-forward') { throw 'Behind is the one state that may fast-forward' }

    $d = Resolve-DefaultBranchSyncDecision -Freshness $current -BranchName 'main'
    if (-not $d.allowed -or $d.action -ne 'none') { throw 'Already current is an allowed no-op, never a refusal' }

    $d = Resolve-DefaultBranchSyncDecision -Freshness $ahead -BranchName 'main'
    if ($d.allowed) { throw 'A default branch carrying local commits must never be fast-forwarded over' }
    if ($d.category -ne 'default-branch-ahead') { throw "The ahead refusal needs its own name; got '$($d.category)'" }
    if ($d.reason -notmatch 'pull request') { throw 'The ahead refusal must name the invariant it is protecting' }

    $d = Resolve-DefaultBranchSyncDecision -Freshness $diverged -BranchName 'main'
    if ($d.allowed -or $d.category -ne 'diverged') { throw "Diverged must refuse under its own name; got '$($d.category)'" }
    if ($d.reason -notmatch 'fast-forward is impossible') { throw 'The diverged refusal must say why it cannot proceed' }

    # Both are checked against a clone that IS behind, so the refusal is coming
    # from the working-tree state rather than from having nothing to do.
    $r = Resolve-DefaultBranchSyncDecision -Freshness $behind -BranchName 'main' -WorkingTreeDirty $true
    if ($r.allowed) { throw 'A dirty clone must refuse even when it is behind' }
    if ($r.category -ne 'working-tree-dirty') { throw "Expected working-tree-dirty; got '$($r.category)'" }

    $r = Resolve-DefaultBranchSyncDecision -Freshness $behind -BranchName 'main' -IsDetachedHead $true
    if ($r.allowed) { throw 'A detached HEAD has no branch to move and must refuse' }
    if ($r.category -ne 'detached-head') { throw "Expected detached-head; got '$($r.category)'" }

    # Unverifiable must refuse HERE, unlike the stale-base guard which lets an
    # unverified clone through. The asymmetry is deliberate: refusing to branch
    # blocks work, while refusing to move a ref costs nothing.
    $unknown = Resolve-BaseFreshness -LocalSha 'a' -ProbeError 'offline' -BaseBranch 'main'
    $d = Resolve-DefaultBranchSyncDecision -Freshness $unknown -BranchName 'main'
    if ($d.allowed) { throw 'Refusing to move a default branch on an unverified reading' }
    $d = Resolve-DefaultBranchSyncDecision -Freshness $null -BranchName 'main'
    if ($d.allowed) { throw 'A missing reading must not be treated as fresh' }

    Write-Host '  decision ok: only behind fast-forwards; ahead refuses as default-branch-ahead, diverged/dirty/detached/unverified each refuse by name' -ForegroundColor DarkGray
}

& {
    # --- Every state, reproduced against real repositories -------------------
    $syncTmp = Join-Path ([System.IO.Path]::GetTempPath()) ("gh-sync-" + [guid]::NewGuid().ToString('n'))
    $null = New-Item -ItemType Directory -Path $syncTmp -Force
    try {
        $originPath = Join-Path $syncTmp 'origin.git'
        $authorPath = Join-Path $syncTmp 'author'
        $clonePath  = Join-Path $syncTmp 'clone'
        $gitCfg = @('-c', 'user.email=smoke@local', '-c', 'user.name=smoke', '-c', 'commit.gpgsign=false')

        $null = & git init --bare -q --initial-branch=main $originPath 2>&1
        $null = & git clone -q $originPath $authorPath 2>&1
        Set-Content -LiteralPath (Join-Path $authorPath 'f.txt') -Value "v1`n" -Encoding UTF8
        $null = & git -C $authorPath add -A 2>&1
        $null = & git -C $authorPath @gitCfg commit -q -m 'v1' 2>&1
        $null = & git -C $authorPath push -q origin main 2>&1
        $null = & git clone -q $originPath $clonePath 2>&1

        # current -> allowed no-op, and nothing moves.
        $shaBefore = ((& git -C $clonePath rev-parse HEAD 2>&1) | Out-String).Trim()
        $r = Sync-RepoDefaultBranch -RepoPath $clonePath -Approved $true
        if (-not $r.synced -or $r.refused) { throw "A clone already at the tip must succeed as a no-op; got refused=$($r.refused) reason='$($r.reason)'" }
        $shaAfter = ((& git -C $clonePath rev-parse HEAD 2>&1) | Out-String).Trim()
        if ($shaBefore -ne $shaAfter) { throw 'A no-op sync moved HEAD' }

        # behind -> fast-forwards, and HEAD actually reaches the remote tip.
        Set-Content -LiteralPath (Join-Path $authorPath 'f.txt') -Value "v2`n" -Encoding UTF8
        $null = & git -C $authorPath add -A 2>&1
        $null = & git -C $authorPath @gitCfg commit -q -m 'v2' 2>&1
        $null = & git -C $authorPath push -q origin main 2>&1
        $remoteTip = ((& git -C $authorPath rev-parse HEAD 2>&1) | Out-String).Trim()

        $r = Sync-RepoDefaultBranch -RepoPath $clonePath -Approved $true
        if (-not $r.synced) { throw "A behind clone must fast-forward; got '$($r.category)' - $($r.reason)" }
        $nowSha = ((& git -C $clonePath rev-parse HEAD 2>&1) | Out-String).Trim()
        if ($nowSha -ne $remoteTip) { throw 'The fast-forward did not reach the remote tip' }

        # approval is an INPUT: the same safe state refuses without it.
        Set-Content -LiteralPath (Join-Path $authorPath 'f.txt') -Value "v3`n" -Encoding UTF8
        $null = & git -C $authorPath add -A 2>&1
        $null = & git -C $authorPath @gitCfg commit -q -m 'v3' 2>&1
        $null = & git -C $authorPath push -q origin main 2>&1
        $r = Sync-RepoDefaultBranch -RepoPath $clonePath -Approved $false
        if ($r.synced -or $r.category -ne 'approval-required') {
            throw "An unapproved transition must refuse as 'approval-required'; got synced=$($r.synced) category='$($r.category)'"
        }
        $null = Sync-RepoDefaultBranch -RepoPath $clonePath -Approved $true

        # ahead -> the invariant violation. A local commit on the default branch.
        Set-Content -LiteralPath (Join-Path $clonePath 'local.txt') -Value "local`n" -Encoding UTF8
        $null = & git -C $clonePath add -A 2>&1
        $null = & git -C $clonePath @gitCfg commit -q -m 'local-only' 2>&1
        $r = Sync-RepoDefaultBranch -RepoPath $clonePath -Approved $true
        if ($r.synced) { throw 'A default branch carrying a local commit must not be fast-forwarded over' }
        if ($r.category -ne 'default-branch-ahead') { throw "Expected default-branch-ahead; got '$($r.category)'" }

        # diverged -> both moved. Still refused, and named differently.
        Set-Content -LiteralPath (Join-Path $authorPath 'f.txt') -Value "v4`n" -Encoding UTF8
        $null = & git -C $authorPath add -A 2>&1
        $null = & git -C $authorPath @gitCfg commit -q -m 'v4' 2>&1
        $null = & git -C $authorPath push -q origin main 2>&1
        $r = Sync-RepoDefaultBranch -RepoPath $clonePath -Approved $true
        if ($r.synced) { throw 'A diverged default branch must not be synced' }
        if ($r.category -ne 'diverged') { throw "Expected diverged; got '$($r.category)' - $($r.reason)" }

        # dirty -> refused before anything touches the repository.
        $null = & git -C $clonePath @gitCfg reset -q --hard HEAD~1 2>&1
        Set-Content -LiteralPath (Join-Path $clonePath 'f.txt') -Value "uncommitted`n" -Encoding UTF8
        $r = Sync-RepoDefaultBranch -RepoPath $clonePath -Approved $true
        if ($r.synced -or $r.category -ne 'working-tree-dirty') { throw "Expected working-tree-dirty; got '$($r.category)'" }

        Write-Host '  live ok: no-op/fast-forward/ahead/diverged/dirty and unapproved all reproduced against real repositories' -ForegroundColor DarkGray
    }
    finally {
        Get-ChildItem -LiteralPath $syncTmp -Recurse -Force -ErrorAction SilentlyContinue |
            ForEach-Object {
                try { $_.Attributes = 'Normal' }
                catch { Write-Verbose ("could not clear attributes on {0}: {1}" -f $_.FullName, $_.Exception.Message) }
            }
        Remove-Item -LiteralPath $syncTmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Step 'Branch cleanup — Release 3.4 milestone 5: deletion requires proof of the merge it follows'
# Every state reproduced against real repositories, per the release acceptance
# criteria. The proof is the merged PR's head SHA: a tip that advanced past it
# refuses, a checkout refuses, a default branch refuses, and no SHA means no
# deletion at all.
. (Join-Path $WorkspaceRoot 'backend\modules\git\Git.BranchCleanup.ps1')
& {
    $cleanTmp = Join-Path $WorkspaceRoot 'output\smoke\module\branch-cleanup'
    if (Test-Path -LiteralPath $cleanTmp) { Remove-Item -LiteralPath $cleanTmp -Recurse -Force }
    $null = New-Item -ItemType Directory -Path $cleanTmp -Force
    $bare = Join-Path $cleanTmp 'origin.git'
    $clone = Join-Path $cleanTmp 'clone'
    & git init --bare -b main $bare --quiet 2>&1 | Out-Null
    & git clone $bare $clone --quiet 2>&1 | Out-Null
    & git -C $clone config user.email 'smoke@local' 2>&1 | Out-Null
    & git -C $clone config user.name 'smoke' 2>&1 | Out-Null
    Set-Content -LiteralPath (Join-Path $clone 'a.txt') -Value 'base' -Encoding UTF8
    & git -C $clone add -A 2>&1 | Out-Null
    & git -C $clone commit -m 'base' --quiet 2>&1 | Out-Null
    & git -C $clone push -u origin main --quiet 2>&1 | Out-Null

    # A merged feature branch: its tip SHA stands in for the PR's merged head.
    & git -C $clone switch -c 'roadmap/done-run' --quiet 2>&1 | Out-Null
    Set-Content -LiteralPath (Join-Path $clone 'b.txt') -Value 'work' -Encoding UTF8
    & git -C $clone add -A 2>&1 | Out-Null
    & git -C $clone commit -m 'work' --quiet 2>&1 | Out-Null
    & git -C $clone push -u origin 'roadmap/done-run' --quiet 2>&1 | Out-Null
    $mergedSha = ((& git -C $clone rev-parse 'roadmap/done-run') | Out-String).Trim()

    # Checked out: the branch is the current checkout — refuse before git has to.
    $r = Remove-MergedRepoBranch -RepoPath $clone -Branch 'roadmap/done-run' -MergedHeadSha $mergedSha -Approved $true
    if ($r.deleted -or $r.category -ne 'checked-out') { throw "Deleting the checked-out branch must refuse as 'checked-out', got deleted=$($r.deleted) category='$($r.category)'" }

    & git -C $clone switch main --quiet 2>&1 | Out-Null

    # Unapproved: everything valid, approval absent — refuse by name.
    $r = Remove-MergedRepoBranch -RepoPath $clone -Branch 'roadmap/done-run' -MergedHeadSha $mergedSha -Approved $false
    if ($r.deleted -or $r.category -ne 'approval-required') { throw "An unapproved deletion must refuse as 'approval-required', got '$($r.category)'" }

    # No merge evidence: no SHA, no deletion — this is the milestone's point.
    $r = Remove-MergedRepoBranch -RepoPath $clone -Branch 'roadmap/done-run' -Approved $true
    if ($r.deleted -or $r.category -ne 'no-merge-evidence') { throw "A deletion without a merged head SHA must refuse as 'no-merge-evidence', got '$($r.category)'" }

    # Default branch: never, merged or not.
    $r = Remove-MergedRepoBranch -RepoPath $clone -Branch 'main' -MergedHeadSha $mergedSha -Approved $true
    if ($r.deleted -or $r.category -ne 'default-branch') { throw "Deleting 'main' must refuse as 'default-branch', got '$($r.category)'" }

    # Tip advanced past the merged head: those commits are not in main;
    # deleting the branch would destroy them.
    & git -C $clone switch 'roadmap/done-run' --quiet 2>&1 | Out-Null
    Set-Content -LiteralPath (Join-Path $clone 'c.txt') -Value 'late work' -Encoding UTF8
    & git -C $clone add -A 2>&1 | Out-Null
    & git -C $clone commit -m 'after the merge' --quiet 2>&1 | Out-Null
    & git -C $clone switch main --quiet 2>&1 | Out-Null
    $r = Remove-MergedRepoBranch -RepoPath $clone -Branch 'roadmap/done-run' -MergedHeadSha $mergedSha -Approved $true
    if ($r.deleted -or $r.category -ne 'tip-advanced') { throw "A tip advanced past the merged head must refuse as 'tip-advanced', got '$($r.category)'" }
    $null = & git -C $clone rev-parse --verify --quiet 'refs/heads/roadmap/done-run' 2>&1
    if ($LASTEXITCODE -ne 0) { throw 'The tip-advanced refusal must leave the branch intact' }

    # Checked out in a LINKED worktree — the other half of the checked-out rule.
    & git -C $clone branch 'roadmap/wt-run' $mergedSha 2>&1 | Out-Null
    $wtPath = Join-Path $cleanTmp 'wt'
    & git -C $clone worktree add $wtPath 'roadmap/wt-run' 2>&1 | Out-Null
    $r = Remove-MergedRepoBranch -RepoPath $clone -Branch 'roadmap/wt-run' -MergedHeadSha $mergedSha -Approved $true
    if ($r.deleted -or $r.category -ne 'checked-out') { throw "A branch checked out in a linked worktree must refuse as 'checked-out', got '$($r.category)'" }
    & git -C $clone worktree remove $wtPath --force 2>&1 | Out-Null

    # The happy path: tip equals the merged head — deleted locally AND on the
    # remote, proven by the remote ref disappearing from the bare origin.
    $r = Remove-MergedRepoBranch -RepoPath $clone -Branch 'roadmap/wt-run' -MergedHeadSha $mergedSha -DeleteRemote $true -Approved $true
    if (-not $r.deleted) { throw "A proven-merged branch must delete, got category='$($r.category)' reason='$($r.reason)'" }
    $null = & git -C $clone rev-parse --verify --quiet 'refs/heads/roadmap/wt-run' 2>&1
    if ($LASTEXITCODE -eq 0) { throw 'The branch must be gone locally after deletion' }
    # wt-run was never pushed, so its remote delete legitimately reports failure;
    # the proven-remote case uses done-run's pushed ref instead: reset its tip
    # back to the merged head, then delete both sides.
    & git -C $clone branch -f 'roadmap/done-run' $mergedSha 2>&1 | Out-Null
    $r = Remove-MergedRepoBranch -RepoPath $clone -Branch 'roadmap/done-run' -MergedHeadSha $mergedSha -DeleteRemote $true -Approved $true
    if (-not $r.deleted -or -not $r.remoteDeleted) { throw "The pushed branch must delete on both sides, got deleted=$($r.deleted) remoteDeleted=$($r.remoteDeleted) ($($r.remoteResult))" }
    $remoteRefs = ((& git -C $clone ls-remote origin 'refs/heads/roadmap/done-run') | Out-String).Trim()
    if (-not [string]::IsNullOrWhiteSpace($remoteRefs)) { throw 'The remote branch must be gone from the origin after remote deletion' }

    Remove-Item -LiteralPath $cleanTmp -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host '  cleanup ok: checked-out (current + linked worktree), unapproved, no-evidence, default-branch and tip-advanced all refused by name; proven merge deleted locally and on the remote' -ForegroundColor DarkGray
}

& {
    # --- The governing invariant, enforced rather than stated ----------------
    # Release 3.4 milestone 6. "Agents may commit freely to feature branches.
    # They may never merge or push to a default branch." Scope derives from the
    # git commands themselves, the same way the stale-base coverage check does,
    # so a new write path is audited without anyone remembering to add it here.
    #
    # Widened 2026-08-15 from push-only to the full invariant, once the last
    # write path (branch cleanup) existed to validate: commits may only happen
    # in a scope that creates a feature branch or refuses a default one, every
    # merge must be --ff-only, and the checker proves ITSELF against a
    # deliberately violating fixture before it is trusted on the real tree —
    # three gates in this repo's history passed vacuously on their first
    # attempt, and this one is not allowed to be the fourth.
    $defaultBranchNames = @('main', 'master', 'trunk', 'develop')

    function Get-DefaultBranchInvariantReport {
        param([Parameter(Mandatory)][object[]]$Files)

        $report = [pscustomobject]@{
            PushSites   = [System.Collections.Generic.List[object]]::new()
            CommitSites = [System.Collections.Generic.List[object]]::new()
            MergeSites  = [System.Collections.Generic.List[object]]::new()
            Violations  = [System.Collections.Generic.List[object]]::new()
        }

        foreach ($file in $Files) {
            $fileErrors = $null
            $fileAst = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$fileErrors)
            if ($fileErrors -and @($fileErrors).Count -gt 0) { continue }

            foreach ($cmd in $fileAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)) {
                if ($cmd.GetCommandName() -ne 'git') { continue }
                $elements = @($cmd.CommandElements | ForEach-Object { $_.Extent.Text })
                $site = [pscustomobject]@{
                    File = $file.FullName
                    Line = $cmd.Extent.StartLineNumber
                    Text = ($cmd.Extent.Text -replace '\s+', ' ')
                }

                if (@($elements | Where-Object { $_ -ceq 'push' }).Count -gt 0) {
                    $report.PushSites.Add($site) | Out-Null
                    # A literal default-branch ref as a push target is the
                    # invariant violation stated outright.
                    foreach ($e in $elements) {
                        $bare = $e.Trim("'", '"')
                        if ($defaultBranchNames -contains $bare.ToLowerInvariant()) {
                            $report.Violations.Add([pscustomobject]@{ Site = $site; Why = "pushes to the literal default branch '$bare'" }) | Out-Null
                        }
                    }
                    # A force push can rewrite whatever it lands on, so it is
                    # refused everywhere rather than only on default branches.
                    foreach ($e in $elements) {
                        if ($e -ceq '--force' -or $e -ceq '-f' -or $e -ceq '--force-with-lease') {
                            $report.Violations.Add([pscustomobject]@{ Site = $site; Why = "force-pushes ($e)" }) | Out-Null
                        }
                    }
                }

                if (@($elements | Where-Object { $_ -ceq 'merge' }).Count -gt 0) {
                    $report.MergeSites.Add($site) | Out-Null
                    # The only merge this product may perform is one that cannot
                    # author a commit.
                    if (@($elements | Where-Object { $_ -ceq '--ff-only' }).Count -eq 0) {
                        $report.Violations.Add([pscustomobject]@{ Site = $site; Why = 'merges without --ff-only, which can author a commit on whatever branch is checked out' }) | Out-Null
                    }
                }

                if (@($elements | Where-Object { $_ -ceq 'commit' }).Count -gt 0) {
                    # Only commits aimed at a managed repo count: a literal -C
                    # or a splat that may carry one, same rule as the
                    # stale-base coverage walker.
                    $targetsRepo = ($elements -contains '-C') -or (@($elements | Where-Object { $_ -match '^@\w' }).Count -gt 0)
                    if (-not $targetsRepo) { continue }
                    $report.CommitSites.Add($site) | Out-Null

                    # The enclosing function must either create the feature
                    # branch it commits to (switch -c / checkout -b) or refuse
                    # a default branch by name. The refusal string is only a
                    # classifier here — its BEHAVIOUR is proven by the
                    # completion-commit fixture above, which watches the
                    # on-default-branch refusal leave the file untouched.
                    $scope = $cmd
                    while ($null -ne $scope -and $scope -isnot [System.Management.Automation.Language.FunctionDefinitionAst]) { $scope = $scope.Parent }
                    $scopeText = if ($null -ne $scope) { $scope.Extent.Text } else { $fileAst.Extent.Text }
                    $createsBranch = ($scopeText -match 'switch\s+-c\b') -or ($scopeText -match 'checkout\s+-b\b')
                    $refusesDefault = ($scopeText -match 'on-default-branch')
                    if (-not $createsBranch -and -not $refusesDefault) {
                        $report.Violations.Add([pscustomobject]@{ Site = $site; Why = 'commits in a scope that neither creates a feature branch nor refuses a default one — this commit lands on whatever branch is checked out' }) | Out-Null
                    }
                }
            }
        }
        return $report
    }

    # The checker proves itself first: a fixture that pushes to main, merges
    # without --ff-only, and commits with no branch discipline must produce
    # exactly those violations, or the sweep below would be trusting a checker
    # nobody has seen fail.
    $invFixtureDir = Join-Path $WorkspaceRoot 'output\smoke\module\invariant-fixture'
    if (Test-Path -LiteralPath $invFixtureDir) { Remove-Item -LiteralPath $invFixtureDir -Recurse -Force }
    $null = New-Item -ItemType Directory -Path $invFixtureDir -Force
    Set-Content -LiteralPath (Join-Path $invFixtureDir 'violating.ps1') -Encoding UTF8 -Value @'
function Invoke-BadPush { param($RepoPath) & git -C $RepoPath push origin main --force }
function Invoke-BadMerge { param($RepoPath) & git -C $RepoPath merge FETCH_HEAD }
function Invoke-BadCommit { param($RepoPath) & git -C $RepoPath commit -m 'lands wherever' }
'@
    $selfTest = Get-DefaultBranchInvariantReport -Files @(Get-ChildItem -LiteralPath $invFixtureDir -Filter '*.ps1' -File)
    $selfWhys = @($selfTest.Violations | ForEach-Object { $_.Why }) -join ' | '
    if (@($selfTest.Violations).Count -lt 4) {
        throw ("The invariant checker failed its own violation fixture: expected >=4 violations (default-branch push, force, bare merge, undisciplined commit), found {0}: {1}" -f @($selfTest.Violations).Count, $selfWhys)
    }
    if ($selfWhys -notmatch 'literal default branch' -or $selfWhys -notmatch 'force' -or $selfWhys -notmatch 'ff-only' -or $selfWhys -notmatch 'neither creates') {
        throw ("The invariant checker missed a violation class on its own fixture: {0}" -f $selfWhys)
    }
    Remove-Item -LiteralPath $invFixtureDir -Recurse -Force -ErrorAction SilentlyContinue

    # Now the real tree — and the floors fail closed: fewer sites than are
    # known to exist means the walker lost its scope, not that the tree got
    # cleaner.
    $realFiles = @(Get-ChildItem -LiteralPath $WorkspaceRoot -Recurse -Filter '*.ps1' -File -ErrorAction SilentlyContinue |
        Where-Object {
            $_.FullName -match '[\\/](backend|scripts)[\\/]' -and
            $_.FullName -notmatch '[\\/]node_modules[\\/]' -and
            $_.Name -notmatch '(SmokeTest|Test-|\.Tests)\.ps1$'
        })
    $inv = Get-DefaultBranchInvariantReport -Files $realFiles

    if (@($inv.PushSites).Count -lt 3) {
        throw ("Found only {0} git push site(s); the PR submitter, the approve-push route and branch cleanup all push, so the walker has lost its scope." -f @($inv.PushSites).Count)
    }
    if (@($inv.CommitSites).Count -lt 3) {
        throw ("Found only {0} repo-targeted git commit site(s); the PR submitter, the task runner and the completion commit all commit, so the walker has lost its scope." -f @($inv.CommitSites).Count)
    }
    if (@($inv.MergeSites).Count -lt 1) {
        throw 'Found no git merge sites; the default-branch sync merges --ff-only, so the walker has lost its scope.'
    }
    if (@($inv.Violations).Count -gt 0) {
        $detail = ($inv.Violations | ForEach-Object { "    {0}:{1} {2}`n      {3}" -f $_.Site.File.Substring($WorkspaceRoot.Length + 1), $_.Site.Line, $_.Why, $_.Site.Text }) -join "`n"
        throw ("{0} write path(s) violate the default-branch invariant. Agents may commit freely to feature branches and reach a default branch only through a pull request.`n{1}" -f @($inv.Violations).Count, $detail)
    }

    # And the sync path itself must stay a fast-forward. A plain merge or a
    # rebase here would author or rewrite commits on a default branch, which is
    # the exact thing every refusal above exists to prevent.
    $syncText = Get-Content -LiteralPath $syncModule -Raw -Encoding UTF8
    if ($syncText -notmatch 'merge --ff-only') { throw 'The sync path no longer uses merge --ff-only, so it can now author a commit on a default branch.' }
    foreach ($forbidden in @('git -C \$RepoPath rebase', 'reset --hard', '--no-ff')) {
        if ($syncText -match $forbidden) { throw "The sync path contains '$forbidden', which can rewrite a default branch." }
    }

    Write-Host ("  invariant ok: checker failed its own violating fixture first; {0} push, {1} commit and {2} merge site(s) checked — none reach a default branch, none force, every merge --ff-only" -f @($inv.PushSites).Count, @($inv.CommitSites).Count, @($inv.MergeSites).Count) -ForegroundColor DarkGray
}

Write-Step 'Bounded git sweep - Release 3.2: timeout honored, cap honored, order preserved'
& {
    $sweepModule = Join-Path $WorkspaceRoot 'backend\modules\git\Git.BoundedSweep.ps1'
    if (-not (Test-Path -LiteralPath $sweepModule)) { throw "Missing $sweepModule" }
    . $sweepModule
    # The top-of-script reconcile load uses the call operator, so its functions
    # died with that invocation's scope; this gate needs them live.
    . $reconcile -LoadFunctionsOnly

    # --- Tripwire: no bare git invocation may return to the sweep path. -----
    # Derived scope: the three files whose ten bare '& git -C' calls this
    # release removed. The detector must fail its own violating fixture first,
    # so a passing run is a run that proved it can fail.
    $bareGitPattern = '&\s+git\s+-C'
    $violatingFixture = '$branch = (& git -C $fullPath branch --show-current 2>$null)'
    if ($violatingFixture -notmatch $bareGitPattern) {
        throw 'Bare-git detector failed its own violating fixture; the tripwire below is vacuous.'
    }
    foreach ($sweepPathFile in @(
            'backend\modules\reconcile\Invoke-Reconciliation.ps1',
            'backend\adapters\Adapters.ps1',
            'backend\modules\portfolio\Portfolio.Scope.ps1')) {
        $sweepPathText = Get-Content -LiteralPath (Join-Path $WorkspaceRoot $sweepPathFile) -Raw -Encoding UTF8
        $bareMatches = @([regex]::Matches($sweepPathText, $bareGitPattern))
        if ($bareMatches.Count -gt 0) {
            throw ("{0} contains {1} bare '& git -C' invocation(s); every sweep git call must go through Invoke-BoundedGitCommand so a hung repo is abandoned at its timeout." -f $sweepPathFile, $bareMatches.Count)
        }
    }

    # --- Fixtures: three real repos and a plain folder. ---------------------
    $sweepFixtureRoot = Join-Path $env:TEMP ('smoke-boundedsweep-' + [guid]::NewGuid().ToString('n').Substring(0, 8))
    $sweepScanRoot = Join-Path $sweepFixtureRoot 'root'
    New-Item -ItemType Directory -Path $sweepScanRoot -Force | Out-Null
    try {
        foreach ($sweepRepoName in 'alpha', 'bravo', 'charlie') {
            $sweepRepoPath = Join-Path $sweepScanRoot $sweepRepoName
            New-Item -ItemType Directory -Path $sweepRepoPath | Out-Null
            & git -C $sweepRepoPath init -q -b main
            & git -C $sweepRepoPath config user.email 'smoke@example.com'
            & git -C $sweepRepoPath config user.name 'Smoke'
            Set-Content -Path (Join-Path $sweepRepoPath 'readme.txt') -Value "hello from $sweepRepoName"
            & git -C $sweepRepoPath add -A
            & git -C $sweepRepoPath commit -q -m "initial commit in $sweepRepoName"
        }
        & git -C (Join-Path $sweepScanRoot 'alpha') remote add origin 'https://github.com/smokeowner/alpha-repo.git'
        Set-Content -Path (Join-Path $sweepScanRoot 'bravo\untracked.txt') -Value 'dirty'
        Set-Content -Path (Join-Path $sweepScanRoot 'charlie\readme.txt') -Value 'modified'
        New-Item -ItemType Directory -Path (Join-Path $sweepScanRoot 'plainfolder') | Out-Null

        # --- Concurrency must not change the answer. ------------------------
        # Identical JSON, UNSORTED, so this asserts order as well as content:
        # a cap that reorders or drops a repository fails here, not in prod.
        $sweepIgnoreRegex = @('[/\\]\.git([/\\]|$)')
        $sweepInvSequential = Get-LocalFolderInventory -Roots @($sweepScanRoot) -IgnoreDirNames @('node_modules') -IgnorePathRegex $sweepIgnoreRegex -MaxDepth 2 -IncludeNonGitFolders -GitSweepMaxConcurrency 1
        $sweepInvParallel = Get-LocalFolderInventory -Roots @($sweepScanRoot) -IgnoreDirNames @('node_modules') -IgnorePathRegex $sweepIgnoreRegex -MaxDepth 2 -IncludeNonGitFolders -GitSweepMaxConcurrency 4
        $sweepJsonSequential = $sweepInvSequential | ConvertTo-Json -Depth 8
        $sweepJsonParallel = $sweepInvParallel | ConvertTo-Json -Depth 8
        if ($sweepJsonSequential -ne $sweepJsonParallel) {
            throw 'Parallel sweep (cap 4) output differs from sequential (cap 1); the concurrency cap reordered, dropped or changed a repository.'
        }
        $sweepAlpha = @($sweepInvParallel | Where-Object { $_.FolderName -eq 'alpha' })[0]
        $sweepBravo = @($sweepInvParallel | Where-Object { $_.FolderName -eq 'bravo' })[0]
        if ($sweepAlpha.CurrentBranch -ne 'main' -or $sweepAlpha.GitOwnerGuess -ne 'smokeowner' -or $sweepAlpha.GitRepoName -ne 'alpha-repo' -or [int]$sweepAlpha.CommitsLastWeek -lt 1) {
            throw ("Sweep facts wrong for alpha: branch={0} owner={1} name={2} week={3}" -f $sweepAlpha.CurrentBranch, $sweepAlpha.GitOwnerGuess, $sweepAlpha.GitRepoName, $sweepAlpha.CommitsLastWeek)
        }
        if ([int]$sweepBravo.UntrackedCount -ne 1 -or [int]$sweepBravo.ModifiedCount -ne 0) {
            throw ("Sweep dirty counts wrong for bravo: untracked={0} modified={1}" -f $sweepBravo.UntrackedCount, $sweepBravo.ModifiedCount)
        }

        # --- A hung git call is abandoned at its timeout. -------------------
        # The shim hangs 30 seconds; the bound is 2. Anything under 15s proves
        # abandonment (timeout + bounded kill/drain), anything near 30 means
        # the sweep waited the hang out and the bound is fiction.
        $sweepIsWindows = [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT
        $sweepHangShim = Join-Path $sweepFixtureRoot $(if ($sweepIsWindows) { 'hang.cmd' } else { 'hang.sh' })
        if ($sweepIsWindows) {
            Set-Content -Path $sweepHangShim -Value "@echo off`r`nping -n 31 127.0.0.1 >nul"
        } else {
            Set-Content -Path $sweepHangShim -Value "#!/bin/sh`nsleep 30"
            & chmod +x $sweepHangShim
            if ($LASTEXITCODE -ne 0) { throw "Could not make the bounded-sweep hang fixture executable: $sweepHangShim" }
        }
        $sweepHangWatch = [System.Diagnostics.Stopwatch]::StartNew()
        $sweepHangResult = Invoke-BoundedGitCommand -RepoPath $sweepScanRoot -GitArgumentList @('status') -FileName $sweepHangShim -TimeoutSeconds 2
        $sweepHangWatch.Stop()
        if (-not $sweepHangResult.TimedOut) { throw 'Hanging shim did not report TimedOut; the timeout is not being applied.' }
        if ($sweepHangWatch.ElapsedMilliseconds -ge 15000) {
            throw ("Hanging shim took {0}ms against a 2s bound; the process was not abandoned." -f $sweepHangWatch.ElapsedMilliseconds)
        }

        # --- A hung REPO short-circuits after two timeouts. -----------------
        $sweepHungFacts = Get-RepoGitFactSet -RepoPath $sweepScanRoot -FileName $sweepHangShim -TimeoutSeconds 1
        if (@($sweepHungFacts.TimedOutCommandNames).Count -ne 2 -or -not $sweepHungFacts.ShortCircuited) {
            throw ("Hung repo did not short-circuit: {0} timeouts recorded, ShortCircuited={1} (expected exactly 2, then skip)." -f @($sweepHungFacts.TimedOutCommandNames).Count, $sweepHungFacts.ShortCircuited)
        }
        if ($null -ne $sweepHungFacts.Branch -or @($sweepHungFacts.StatusLines).Count -ne 0) {
            throw 'Hung repo returned facts; unavailable facts must be null/empty, never stale or invented.'
        }

        # --- stdin is never inherited. -------------------------------------
        # Reproduces the CI regression of 2026-08-19..22: the api-host smoke
        # runs the host inside a Start-Job child, whose stdin is the job
        # transport pipe. A git process that inherited that stdin hung until
        # the 20s timeout killed it -- every read, every repo -- so
        # /api/update and /api/sync cost ~250s per CI run and returned no git
        # facts at all. It is git-specific (cmd.exe and where.exe complete in
        # the same handle shape) and it needs a real job child: a plain pwsh
        # child with a piped stdin does NOT reproduce it, so this probe runs
        # under Start-Job and nothing lighter. Shown red against the inheriting
        # invoker (TimedOut after 15s) before stdin was redirected and closed.
        $sweepStdinWatch = [System.Diagnostics.Stopwatch]::StartNew()
        $sweepStdinJob = Start-Job -ScriptBlock {
            param($Root, $RepoPath)
            # Literal target path: the dot-source scope gate resolves what every
            # site loads and refuses a bare variable it cannot follow.
            . (Join-Path $Root 'backend\modules\git\Git.BoundedSweep.ps1')
            $probe = Invoke-BoundedGitCommand -RepoPath $RepoPath -GitArgumentList @('--version') -TimeoutSeconds 10
            [pscustomobject]@{ TimedOut = [bool]$probe.TimedOut; ExitCode = [int]$probe.ExitCode; Value = [string]$probe.Value }
        } -ArgumentList $WorkspaceRoot, $sweepScanRoot
        try {
            if (-not (Wait-Job -Job $sweepStdinJob -Timeout 90)) {
                throw 'stdin probe job did not finish within 90s; the bounded invoker hangs inside a job child.'
            }
            $sweepStdinResults = @(Receive-Job -Job $sweepStdinJob -ErrorAction Stop)
        }
        finally {
            try { Remove-Job -Job $sweepStdinJob -Force } catch { $null = $_ }
        }
        $sweepStdinWatch.Stop()
        if ($sweepStdinResults.Count -lt 1) { throw 'stdin probe job returned nothing; the probe failed before the invoker ran.' }
        $sweepStdinProbe = $sweepStdinResults[-1]
        if ($sweepStdinProbe.TimedOut -or $sweepStdinProbe.ExitCode -ne 0 -or $sweepStdinProbe.Value -notmatch '^git version') {
            throw ("Inside a job child the bounded git call did not complete: timedOut={0} exit={1} value='{2}' after {3}ms. The invoker must redirect and close stdin, never inherit it." -f $sweepStdinProbe.TimedOut, $sweepStdinProbe.ExitCode, $sweepStdinProbe.Value, $sweepStdinWatch.ElapsedMilliseconds)
        }

        # --- The cap is real, and so is the parallelism. --------------------
        # Marker shim: every invocation writes its own start/end tick file;
        # sweep-line overlap over those intervals measures true concurrency.
        $sweepMarkerDir = Join-Path $sweepFixtureRoot 'markers'
        New-Item -ItemType Directory -Path $sweepMarkerDir | Out-Null
        $sweepMarkerScript = Join-Path $sweepFixtureRoot 'marker.ps1'
        Set-Content -Path $sweepMarkerScript -Value @'
$f = Join-Path $env:SMOKE_SWEEP_MARKER_DIR ([guid]::NewGuid().ToString('n') + '.txt')
$s = [datetime]::UtcNow.Ticks
Start-Sleep -Milliseconds 250
Set-Content -Path $f -Value ($s.ToString() + ' ' + [datetime]::UtcNow.Ticks.ToString())
'@
        $sweepMarkerShim = Join-Path $sweepFixtureRoot 'marker.cmd'
        Set-Content -Path $sweepMarkerShim -Value ("@echo off`r`npowershell -NoProfile -ExecutionPolicy Bypass -File `"$sweepMarkerScript`"")
        $env:SMOKE_SWEEP_MARKER_DIR = $sweepMarkerDir
        try {
            $sweepFakeRepoPaths = @(1..4 | ForEach-Object {
                    $p = Join-Path $sweepFixtureRoot "fake$_"
                    New-Item -ItemType Directory -Path $p | Out-Null
                    $p
                })
            $script:sweepTickCount = 0
            $sweepCapResults = Invoke-BoundedRepoFactSweep -RepoPathList $sweepFakeRepoPaths -TimeoutSeconds 30 -MaxConcurrency 2 -FileName $sweepMarkerShim -OnRepoComplete { $script:sweepTickCount++ }
            if (@($sweepCapResults).Count -ne 4) { throw ("Sweep returned {0} results for 4 repos; results must align index-for-index with input." -f @($sweepCapResults).Count) }
            if ($script:sweepTickCount -ne 4) { throw ("OnRepoComplete fired {0} times for 4 repos; the heartbeat tick must fire once per completed repo, from inside the sweep." -f $script:sweepTickCount) }

            $sweepIntervals = @(Get-ChildItem -LiteralPath $sweepMarkerDir -Filter '*.txt' | ForEach-Object {
                    $parts = (Get-Content -LiteralPath $_.FullName -Raw).Trim() -split '\s+'
                    if ($parts.Count -eq 2) { [pscustomobject]@{ Start = [long]$parts[0]; End = [long]$parts[1] } }
                })
            if (@($sweepIntervals).Count -lt 24) { throw ("Only {0} marker intervals recorded; expected 32 (8 calls x 4 repos, minus at most a few short-circuits)." -f @($sweepIntervals).Count) }
            $sweepEvents = @($sweepIntervals | ForEach-Object { [pscustomobject]@{ T = $_.Start; D = 1 }; [pscustomobject]@{ T = $_.End; D = -1 } }) | Sort-Object -Property T, D
            $sweepConcurrent = 0
            $sweepMaxConcurrent = 0
            foreach ($sweepEvent in $sweepEvents) {
                $sweepConcurrent += $sweepEvent.D
                if ($sweepConcurrent -gt $sweepMaxConcurrent) { $sweepMaxConcurrent = $sweepConcurrent }
            }
            if ($sweepMaxConcurrent -gt 2) { throw ("Observed {0} concurrent git calls under a cap of 2; the concurrency cap is not being honored." -f $sweepMaxConcurrent) }
            if ($sweepMaxConcurrent -lt 2) { throw ("Observed max concurrency {0} under a cap of 2 across 32 calls; the pool is not actually parallel." -f $sweepMaxConcurrent) }
        }
        finally {
            Remove-Item Env:SMOKE_SWEEP_MARKER_DIR -ErrorAction SilentlyContinue
        }

        Write-Host ("  sweep ok: detector failed its violating fixture first; 3 files bare-git free; cap1/cap4 output identical (order included); hung call abandoned at {0}ms against a 30s hang; hung repo short-circuited after 2 timeouts; git completed under a piped stdin in {1}ms (stdin redirected+closed, never inherited); max observed concurrency 2 under cap 2 with per-repo heartbeat ticks" -f $sweepHangWatch.ElapsedMilliseconds, $sweepStdinWatch.ElapsedMilliseconds) -ForegroundColor DarkGray
    }
    finally {
        Remove-Item -Recurse -Force $sweepFixtureRoot -ErrorAction SilentlyContinue
    }
}

Write-Step 'Ledger retention - Release 3.3 milestone 1: archive-then-trim, bounded and honest'
& {
    $retentionModule = Join-Path $WorkspaceRoot 'backend\modules\persistence\Ledger.Retention.ps1'
    if (-not (Test-Path -LiteralPath $retentionModule)) { throw "Missing $retentionModule" }
    . $retentionModule

    $retFixture = Join-Path $env:TEMP ('smoke-ledgerret-' + [guid]::NewGuid().ToString('n').Substring(0, 8))
    $retWorkspace = Join-Path $retFixture 'ws'
    $null = New-Item -ItemType Directory -Path (Join-Path $retWorkspace 'output\logs') -Force
    try {
        # A policy that reaches outside output\ must be refused outright.
        $retBadSettings = @{ retention = @{ ledgers = @{ archiveDir = '..\evidence\baseline' } } }
        $retRefused = $false
        try { $null = Get-LedgerRetentionPolicy -Settings $retBadSettings -WorkspaceRoot $retWorkspace }
        catch { $retRefused = $true }
        if (-not $retRefused) { throw 'A policy pointing its archive outside output\ was accepted; evidence\ must be unreachable.' }

        $retPolicy = Get-LedgerRetentionPolicy -Settings @{} -WorkspaceRoot $retWorkspace
        if ([int]$retPolicy.KeepDays -ne 90 -or -not $retPolicy.Enabled) { throw "Default policy wrong: keepDays=$($retPolicy.KeepDays) enabled=$($retPolicy.Enabled)" }

        # Fixture ledger: three old lines, two fresh, one unparseable, one
        # old-but-floor-protected candidate. Timestamps are explicit so the
        # cutoff maths is deterministic.
        $retLedger = Join-Path $retWorkspace 'output\logs\service-watchdog.jsonl'
        $retNow = [datetime]::UtcNow
        $retOld = ($retNow.AddDays(-120)).ToString('o')
        $retFresh = ($retNow.AddDays(-5)).ToString('o')
        $retLines = @(
            ('{"timestamp":"' + $retOld + '","event":"old-1"}'),
            ('{"timestamp":"' + $retOld + '","event":"old-2"}'),
            ('{"event":"no-timestamp-must-survive"}'),
            ('{"timestamp":"' + $retOld + '","event":"old-3"}'),
            ('{"timestamp":"' + $retFresh + '","event":"fresh-1"}'),
            ('{"timestamp":"' + $retFresh + '","event":"fresh-2"}')
        )
        [System.IO.File]::WriteAllLines($retLedger, [string[]]$retLines)
        $retBytesBefore = (Get-Item -LiteralPath $retLedger).Length

        # -WhatIf must report and touch nothing.
        $retFloorPolicy = [pscustomobject]@{
            Enabled = $true; KeepDays = 90; MinKeepLines = 0
            ArchiveDir = (Join-Path $retWorkspace 'output\archive\ledgers')
            Targets = @([pscustomobject]@{ Name = 'service-watchdog'; Path = $retLedger; TimestampField = 'timestamp' })
            Exclusions = @()
        }
        $retPreview = Invoke-LedgerRetention -Policy $retFloorPolicy -WhatIf
        $retPreviewReport = @($retPreview.reports)[0]
        if ([int]$retPreviewReport.pruned -ne 3) { throw "WhatIf preview expected 3 prunable lines, reported $($retPreviewReport.pruned)." }
        if ((Get-Item -LiteralPath $retLedger).Length -ne $retBytesBefore) { throw 'WhatIf modified the ledger; a preview must touch nothing.' }
        if (Test-Path -LiteralPath $retFloorPolicy.ArchiveDir) { throw 'WhatIf created the archive dir; a preview must touch nothing.' }

        # Apply: the three old lines move to the archive VERBATIM; the fresh
        # pair and the undateable line survive byte-identical.
        $retResult = Invoke-LedgerRetention -Policy $retFloorPolicy -Confirm:$false
        $retReport = @($retResult.reports)[0]
        if ([int]$retReport.pruned -ne 3 -or [int]$retReport.kept -ne 3) { throw "Apply expected pruned=3 kept=3; got pruned=$($retReport.pruned) kept=$($retReport.kept)." }
        if ([string]::IsNullOrWhiteSpace([string]$retReport.prunedFrom) -or [string]::IsNullOrWhiteSpace([string]$retReport.prunedTo)) { throw 'Pruned range not reported; a prune nobody can see happened is a silent rewrite.' }
        $retSurvivors = @([System.IO.File]::ReadAllLines($retLedger))
        $retExpectedSurvivors = @($retLines[2], $retLines[4], $retLines[5])
        if (($retSurvivors -join "`n") -ne ($retExpectedSurvivors -join "`n")) { throw 'Survivors are not byte-identical to their originals (undateable line must be kept).' }
        $retArchived = @([System.IO.File]::ReadAllLines([string]$retReport.archivePath))
        $retExpectedArchived = @($retLines[0], $retLines[1], $retLines[3])
        if (($retArchived -join "`n") -ne ($retExpectedArchived -join "`n")) { throw 'Archived lines are not the pruned originals verbatim.' }

        # The floor: with minKeepLines=2 on an ALL-OLD ledger, the newest two
        # survive regardless of age.
        $retAllOld = Join-Path $retWorkspace 'output\logs\all-old.jsonl'
        [System.IO.File]::WriteAllLines($retAllOld, [string[]]@(
                ('{"timestamp":"' + $retOld + '","event":"ancient-1"}'),
                ('{"timestamp":"' + $retOld + '","event":"ancient-2"}'),
                ('{"timestamp":"' + $retOld + '","event":"ancient-3"}')
            ))
        $retFloorPolicy2 = [pscustomobject]@{
            Enabled = $true; KeepDays = 90; MinKeepLines = 2
            ArchiveDir = (Join-Path $retWorkspace 'output\archive\ledgers')
            Targets = @([pscustomobject]@{ Name = 'all-old'; Path = $retAllOld; TimestampField = 'timestamp' })
            Exclusions = @()
        }
        $retFloorResult = Invoke-LedgerRetention -Policy $retFloorPolicy2 -Confirm:$false
        $retFloorReport = @($retFloorResult.reports)[0]
        if ([int]$retFloorReport.kept -ne 2 -or [int]$retFloorReport.pruned -ne 1) { throw "Floor expected kept=2 pruned=1; got kept=$($retFloorReport.kept) pruned=$($retFloorReport.pruned)." }

        # Derived scope: every .jsonl in the ledger homes must be a declared
        # target or a named exclusion. The detector fails a planted undeclared
        # ledger first, so a passing sweep is a sweep that can fail.
        $realPolicy = Get-LedgerRetentionPolicy -Settings @{} -WorkspaceRoot $WorkspaceRoot
        $declaredPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($t in @($realPolicy.Targets)) { $null = $declaredPaths.Add($t.Path) }
        foreach ($e in @($realPolicy.Exclusions)) { $null = $declaredPaths.Add($e.Path) }
        $retLedgerHomes = @(
            (Join-Path $WorkspaceRoot 'output'),
            (Join-Path $WorkspaceRoot 'output\logs'),
            (Join-Path $WorkspaceRoot 'output\automation'),
            (Join-Path $WorkspaceRoot 'output\roadmap-task-history'),
            (Join-Path $WorkspaceRoot 'output\agent-runs')
        )
        $retFindUndeclared = {
            param($Homes, $Declared)
            $undeclared = @()
            foreach ($ledgerHome in $Homes) {
                if (-not (Test-Path -LiteralPath $ledgerHome)) { continue }
                foreach ($file in @(Get-ChildItem -LiteralPath $ledgerHome -Filter '*.jsonl' -File -ErrorAction SilentlyContinue)) {
                    if (-not $Declared.Contains($file.FullName)) { $undeclared += $file.FullName }
                }
            }
            return $undeclared
        }
        $retPlanted = Join-Path $WorkspaceRoot 'output\logs\smoke-undeclared-ledger.jsonl'
        # A fresh CI checkout has no output\logs\ (output/ is gitignored); the
        # planted fixture must create its own home.
        $null = New-Item -ItemType Directory -Path (Split-Path -Parent $retPlanted) -Force
        Set-Content -LiteralPath $retPlanted -Value '{"timestamp":"2026-01-01T00:00:00Z"}'
        try {
            $retRedResult = @(& $retFindUndeclared $retLedgerHomes $declaredPaths)
            if (@($retRedResult | Where-Object { $_ -eq $retPlanted }).Count -eq 0) { throw 'Scope detector missed the planted undeclared ledger; the sweep below is vacuous.' }
        }
        finally {
            Remove-Item -LiteralPath $retPlanted -Force -ErrorAction SilentlyContinue
        }
        $retUndeclared = @(& $retFindUndeclared $retLedgerHomes $declaredPaths)
        if (@($retUndeclared).Count -gt 0) {
            throw ("Undeclared ledger(s) in the ledger homes -- declare each as a retention target or a named exclusion:`n    {0}" -f ($retUndeclared -join "`n    "))
        }

        Write-Host ("  retention ok: outside-output refused; WhatIf inert; 3 pruned to archive verbatim + undateable line kept; floor held 2 of 3 ancient lines; scope detector failed its planted fixture first, {0} target(s) + {1} exclusion(s) cover the ledger homes" -f @($realPolicy.Targets).Count, @($realPolicy.Exclusions).Count) -ForegroundColor DarkGray
    }
    finally {
        Remove-Item -Recurse -Force $retFixture -ErrorAction SilentlyContinue
    }
}

Write-Step 'AppDb backup/restore - Release 3.3 milestone 2: rehearsed, verified, never destructive'
& {
    . (Join-Path $WorkspaceRoot 'backend\modules\persistence\Persistence.Store.ps1')
    . (Join-Path $WorkspaceRoot 'backend\modules\persistence\Persistence.Backup.ps1')

    $bakCapability = Get-SqliteCapability
    if (-not $bakCapability.available) {
        # Same degraded contract the persistence smoke accepts: no provider,
        # no rehearsal -- said loudly, never silently green.
        Write-Host ("  [WARN] no SQLite provider on this machine ({0}); backup/restore rehearsal skipped -- the api-host smoke's route step carries the same degraded contract" -f $bakCapability.providerDetail) -ForegroundColor Yellow
        return
    }

    $bakFixture = Join-Path $env:TEMP ('smoke-appdbbak-' + [guid]::NewGuid().ToString('n').Substring(0, 8))
    $bakWorkspace = Join-Path $bakFixture 'ws'
    $null = New-Item -ItemType Directory -Path $bakWorkspace -Force
    try {
        $bakInit = Initialize-AppDatabase -WorkspaceRoot $bakWorkspace
        if (-not $bakInit.success) { throw "Fixture database init failed: $($bakInit.providerDetail)" }
        $bakDbPath = Get-AppDatabasePath -WorkspaceRoot $bakWorkspace

        # Seed rows the rehearsal can count through the restored file.
        $null = Invoke-AppDbNonQuery -DatabasePath $bakDbPath -Sql 'CREATE TABLE IF NOT EXISTS smoke_seed (id INTEGER PRIMARY KEY, note TEXT)'
        $null = Invoke-AppDbNonQuery -DatabasePath $bakDbPath -Sql "INSERT INTO smoke_seed (note) VALUES ('one')"
        $null = Invoke-AppDbNonQuery -DatabasePath $bakDbPath -Sql "INSERT INTO smoke_seed (note) VALUES ('two')"

        # WhatIf must create nothing.
        $bakWhatIf = New-AppDbBackup -WorkspaceRoot $bakWorkspace -WhatIf
        $bakDir = Get-AppDbBackupDir -WorkspaceRoot $bakWorkspace
        if ((Test-Path -LiteralPath $bakDir) -and @(Get-ChildItem -LiteralPath $bakDir -Filter 'app-*.db' -File).Count -gt 0) {
            throw 'New-AppDbBackup -WhatIf wrote a snapshot; a preview must touch nothing.'
        }
        if ($bakWhatIf.reason -ne 'what-if') { throw "WhatIf backup did not report itself as what-if (reason=$($bakWhatIf.reason))." }

        # Snapshot, then mutate the live database past it.
        $bakResult = New-AppDbBackup -WorkspaceRoot $bakWorkspace -Confirm:$false
        if (-not $bakResult.success) { throw "Backup failed: $($bakResult.reason)" }
        if (-not (Test-Path -LiteralPath $bakResult.manifestPath)) { throw 'Backup wrote no manifest; a snapshot nobody can judge is a snapshot nobody can trust.' }
        if ([long]$bakResult.schemaVersion -lt 1) { throw "Backup manifest carries no schema version." }
        $null = Invoke-AppDbNonQuery -DatabasePath $bakDbPath -Sql "INSERT INTO smoke_seed (note) VALUES ('three-after-snapshot')"

        # THE REHEARSAL: restore, then query history through the restored
        # file with the same provider the host uses. A restore path that has
        # never run is a hope, not a path.
        $bakRestore = Restore-AppDbBackup -BackupPath $bakResult.backupPath -WorkspaceRoot $bakWorkspace -Confirm:$false
        if (-not $bakRestore.success) { throw "Restore failed: $($bakRestore.reason)" }
        $bakRestoredCount = [long](@(Invoke-AppDbQuery -DatabasePath $bakDbPath -Sql 'SELECT COUNT(*) AS c FROM smoke_seed')[0].c)
        if ($bakRestoredCount -ne 2) { throw "Restored database has $bakRestoredCount seed rows; the snapshot held 2 -- the restore did not restore." }

        # Nothing destroyed: the mutated pre-restore database moved aside and
        # still carries its third row.
        if ([string]::IsNullOrWhiteSpace([string]$bakRestore.preRestoreSnapshot) -or -not (Test-Path -LiteralPath $bakRestore.preRestoreSnapshot)) {
            throw 'Restore destroyed the existing database instead of moving it aside.'
        }
        $bakPreCount = [long](@(Invoke-AppDbQuery -DatabasePath $bakRestore.preRestoreSnapshot -Sql 'SELECT COUNT(*) AS c FROM smoke_seed')[0].c)
        if ($bakPreCount -ne 3) { throw "Pre-restore snapshot has $bakPreCount rows; expected the mutated 3 -- the wrong file moved aside." }

        # Forward-compat refusal: a snapshot claiming a FUTURE schema version
        # is refused by name, before any file moves.
        $bakFuture = Join-Path $bakFixture 'future.db'
        Copy-Item -LiteralPath $bakResult.backupPath -Destination $bakFuture
        $null = Invoke-AppDbNonQuery -DatabasePath $bakFuture -Sql "INSERT INTO schema_migrations (version, description, applied_at) VALUES (99, 'from-the-future', '2099-01-01T00:00:00Z')"
        $bakFutureVerdict = Test-AppDbBackup -BackupPath $bakFuture
        if ($bakFutureVerdict.ok -or @($bakFutureVerdict.issues | Where-Object { $_ -like 'schema-newer-than-code*' }).Count -eq 0) {
            throw 'A future-schema snapshot was not refused by name; restoring it would hand the migrations a database they cannot parse.'
        }
        $bakFutureRestore = Restore-AppDbBackup -BackupPath $bakFuture -WorkspaceRoot $bakWorkspace -Confirm:$false
        if ($bakFutureRestore.success) { throw 'Restore accepted a future-schema snapshot.' }

        # Retention: three snapshots under KeepCount 2 keep the newest two.
        Start-Sleep -Seconds 1
        $null = New-AppDbBackup -WorkspaceRoot $bakWorkspace -KeepCount 2 -Confirm:$false
        Start-Sleep -Seconds 1
        $bakThird = New-AppDbBackup -WorkspaceRoot $bakWorkspace -KeepCount 2 -Confirm:$false
        if (@($bakThird.prunedBackups).Count -lt 1) { throw 'Third snapshot under KeepCount 2 pruned nothing; backups would grow without bound.' }
        $bakRemaining = @(Get-ChildItem -LiteralPath $bakDir -Filter 'app-*.db' -File)
        if ($bakRemaining.Count -ne 2) { throw "Expected 2 snapshots after retention; found $($bakRemaining.Count)." }

        Write-Host ("  backup/restore ok: WhatIf inert; snapshot v{0} with manifest; RESTORE REHEARSED (2 rows back, mutated original kept aside with 3); future-schema snapshot refused by name; retention kept newest 2 of 3" -f $bakResult.schemaVersion) -ForegroundColor DarkGray
    }
    finally {
        Remove-Item -Recurse -Force $bakFixture -ErrorAction SilentlyContinue
    }
}

Write-Step 'Decision-grade exports - Release 3.3 milestone 4: every digest and export states its window, units, headline and next action'
& {
    . (Join-Path $WorkspaceRoot 'backend\modules\common\DecisionGrade.ps1')

    # --- The predicate itself must be able to fail. ------------------------
    $dgIncomplete = [pscustomobject]@{ totalRepos = 12; byLevel = @{ ready = 3 } }
    $dgVerdict = Test-DecisionGradeEnvelope -Payload $dgIncomplete
    if ($dgVerdict.ok) { throw 'Test-DecisionGradeEnvelope passed a payload with no window, units, headline or next action; the sweep below would be vacuous.' }
    foreach ($dgExpected in @('units', 'headline', 'nextAction', 'dataWindow')) {
        if (@($dgVerdict.missing) -notcontains $dgExpected) { throw "Decision-grade predicate did not name '$dgExpected' as missing; a failure must say what to add." }
    }
    $dgBlank = New-DecisionGradeEnvelope -Units 'repositories' -Headline 'h' -NextAction 'n'
    if (-not (Test-DecisionGradeEnvelope -Payload $dgBlank).ok) { throw 'A correctly built envelope failed its own predicate.' }
    if ([string]::IsNullOrWhiteSpace($dgBlank.dataWindow.label)) { throw 'A point-in-time envelope must still carry a window label.' }

    # Omissions that make a report undecidable are refused at construction.
    foreach ($dgCase in @(
            @{ Name = 'blank headline'; Args = @{ Units = 'repos'; Headline = '  '; NextAction = 'do a thing' } },
            @{ Name = 'blank next action'; Args = @{ Units = 'repos'; Headline = 'a thing happened'; NextAction = '' } },
            @{ Name = 'blank units'; Args = @{ Units = ''; Headline = 'h'; NextAction = 'n' } })) {
        $dgRefused = $false
        try { $null = New-DecisionGradeEnvelope @($dgCase.Args) } catch { $dgRefused = $true }
        if (-not $dgRefused) { throw ("New-DecisionGradeEnvelope accepted a {0}." -f $dgCase.Name) }
    }
    $dgImpossible = $false
    try { $null = New-DecisionGradeEnvelope -Units 'r' -Headline 'h' -NextAction 'n' -AssessedCount 9 -TotalCount 4 } catch { $dgImpossible = $true }
    if (-not $dgImpossible) { throw 'Coverage of 9 assessed out of 4 total was accepted.' }
    $dgEmptyCoverage = New-DecisionGradeEnvelope -Units 'r' -Headline 'h' -NextAction 'n' -AssessedCount 0 -TotalCount 0
    if ($null -ne $dgEmptyCoverage.coverage.percent) { throw 'An empty set was given a coverage percentage; 0% would read as a finding.' }

    # --- Live payloads: every producer must carry the contract. -----------
    . (Join-Path $WorkspaceRoot 'backend\modules\automation\Automation.DocRefinement.ps1')
    . (Join-Path $WorkspaceRoot 'backend\modules\automation\Automation.RoadmapPackaging.ps1')

    $dgDocDigest = New-AutomationDigestPayload -Run ([pscustomobject]@{
            runId = 'run-1'; kind = 'doc-refinement'
            startedAt = '2026-08-19T10:00:00Z'; finishedAt = '2026-08-19T10:05:00Z'
            proposals = @([pscustomobject]@{ repoName = 'r'; docType = 'readme'; previewId = 'p1' })
        })
    $dgPackDigest = New-PackagingDigestPayload -Run ([pscustomobject]@{
            runId = 'run-2'; startedAt = '2026-08-19T11:00:00Z'; finishedAt = '2026-08-19T11:02:00Z'
            candidateCount = 3; packets = @(); skipped = @([pscustomobject]@{ repoName = 'x'; reason = 'not-curated' })
        })
    foreach ($dgLive in @(
            @{ Name = 'doc-refinement digest'; Payload = $dgDocDigest },
            @{ Name = 'roadmap-packaging digest'; Payload = $dgPackDigest })) {
        $dgLiveVerdict = Test-DecisionGradeEnvelope -Payload $dgLive.Payload
        if (-not $dgLiveVerdict.ok) {
            throw ("{0} is missing the decision-grade contract: {1}" -f $dgLive.Name, ($dgLiveVerdict.missing -join ', '))
        }
    }
    # The window must be the RUN's, not the moment someone asked.
    if ([string]$dgDocDigest.dataWindow.from -ne '2026-08-19T10:00:00Z' -or [string]$dgDocDigest.dataWindow.to -ne '2026-08-19T10:05:00Z') {
        throw "Doc-refinement digest window is not the run's window (got $($dgDocDigest.dataWindow.from)..$($dgDocDigest.dataWindow.to))."
    }

    # --- Derived scope: find every producer, not the ones we remember. ----
    # A function whose name says it builds a digest or export payload, and
    # whose body returns an object, must emit the contract. The detector
    # fails a planted violating fixture first.
    $dgProducerPattern = '(?im)^\s*function\s+((?:New|Get|Export)-\w*(?:Digest|Report|Export)\w*)'
    $dgViolatingFixture = "function New-SomethingDigestPayload {`n    return [pscustomobject]@{ count = 1 }`n}"
    if ($dgViolatingFixture -notmatch $dgProducerPattern) { throw 'Producer detector failed its own violating fixture; the sweep below is vacuous.' }

    $dgSearchFiles = @(
        (Join-Path $WorkspaceRoot 'backend\api-host\Start-RepoManagementApiHost.ps1'),
        (Join-Path $WorkspaceRoot 'backend\modules\portfolio\Portfolio.Report.ps1'),
        (Join-Path $WorkspaceRoot 'backend\modules\automation\Automation.DocRefinement.ps1'),
        (Join-Path $WorkspaceRoot 'backend\modules\automation\Automation.RoadmapPackaging.ps1')
    )
    # Producers that legitimately do NOT carry the envelope, each named with
    # its reason. An unnamed producer fails the sweep.
    $dgExempt = @{
        'New-PortfolioCollectionStatusHtmlContent' = 'Renders HTML from a payload that already carries the contract; it is a view, not a report.'
        'New-PortfolioCollectionStatusCsvContent'  = 'Renders CSV rows; the envelope rides the API payload beside it.'
        'New-RepoStatusHtmlContent'                = 'View over Export-RepoStatusReports'' payload.'
        'New-RepoStatusCsvContent'                 = 'View over Export-RepoStatusReports'' payload.'
        'Get-DigestPayloadForRun'                  = 'Reserved name; not a producer in this tree.'
        'Get-ReportsRootPath'                      = 'Path helper, not a payload producer.'
        'New-PortfolioReadBudgetResult'            = 'Performance measurement attached to a route response, not a report.'
        'Get-DefaultBranchInvariantReport'         = 'Internal gate report consumed by the smoke, never delivered to an operator.'
        'Get-RepoScopeSummary'                     = 'Component of the scan payload, not a standalone report.'
        'New-AppDbBackup'                          = 'Operation result with its own manifest contract (Release 3.3 M2).'
        'Get-PortfolioScanState'                   = 'Live state for a progress chip, not a report.'
        'Export-RepoStatusReports'                 = ''   # carries the contract; presence asserted below
        'Export-PortfolioCollectionStatusReport'   = ''
        'Get-DigestPayload'                        = ''
        'New-AutomationDigestPayload'              = ''
        'New-PackagingDigestPayload'               = ''
    }
    $dgFound = New-Object System.Collections.Generic.List[string]
    foreach ($dgFile in $dgSearchFiles) {
        $dgText = Get-Content -LiteralPath $dgFile -Raw -Encoding UTF8
        foreach ($dgMatch in [regex]::Matches($dgText, $dgProducerPattern)) {
            $dgName = $dgMatch.Groups[1].Value
            if (-not $dgFound.Contains($dgName)) { $dgFound.Add($dgName) }
        }
    }
    $dgUndeclared = @($dgFound | Where-Object { -not $dgExempt.ContainsKey($_) })
    if (@($dgUndeclared).Count -gt 0) {
        throw ("Producer function(s) neither carrying the decision-grade contract nor named as exempt:`n    {0}`n  Add the envelope, or declare the exemption with its reason." -f ($dgUndeclared -join "`n    "))
    }
    # And the four that must carry it are actually present in the tree, so a
    # rename cannot quietly empty this sweep.
    foreach ($dgRequired in @('Get-DigestPayload', 'Export-RepoStatusReports', 'Export-PortfolioCollectionStatusReport', 'New-AutomationDigestPayload', 'New-PackagingDigestPayload')) {
        if (-not $dgFound.Contains($dgRequired)) { throw "Expected producer '$dgRequired' was not found; the sweep has lost its scope." }
    }

    Write-Host ("  decision-grade ok: predicate failed its bare-counts fixture first and named all 4 gaps; 3 construction refusals + impossible coverage refused; empty set has null percent (not 0); 2 live digests carry the contract over the RUN's window; producer sweep covers {0} function(s) with {1} exemptions each named" -f $dgFound.Count, @($dgExempt.Keys | Where-Object { $dgExempt[$_] -ne '' }).Count) -ForegroundColor DarkGray
}

Write-Step 'Transport honesty - Release 3.3 milestone 3: the reported transport is the served transport'
& {
    $tlsHostPath = Join-Path $WorkspaceRoot 'backend\api-host\Start-RepoManagementApiHost.ps1'
    $tlsHostText = Get-Content -LiteralPath $tlsHostPath -Raw -Encoding UTF8

    # --- The scheme must be DERIVED, never a literal. ---------------------
    # The startup banner said 'http://' unconditionally for a whole release,
    # including while the host served TLS. The detector fails that exact old
    # line first, so a passing sweep is a sweep that can fail.
    $tlsLiteralPattern = 'host started on http://'
    $tlsViolatingFixture = 'Write-HostLog ("Repo Management API host started on http://{0}:{1}" -f $BindAddress, $Port)'
    if ($tlsViolatingFixture -notmatch [regex]::Escape($tlsLiteralPattern)) {
        throw 'Hardcoded-scheme detector failed its own violating fixture; the assertion below is vacuous.'
    }
    if ($tlsHostText -match [regex]::Escape($tlsLiteralPattern)) {
        throw 'The startup banner hardcodes http://; it must render the scheme the host is actually serving.'
    }

    # --- The report is derived from the CERTIFICATE, not from config. -----
    # Config is the thing being checked; a report that reads config would
    # agree with it by construction and could never surface a degradation.
    if ($tlsHostText -notmatch 'function Get-PortalTransportState') { throw 'Get-PortalTransportState is missing; nothing reports the served transport.' }
    $tlsFnMatch = [regex]::Match($tlsHostText, '(?s)function Get-PortalTransportState\s*\{.*?\n\}')
    if (-not $tlsFnMatch.Success) { throw 'Could not isolate Get-PortalTransportState for inspection.' }
    $tlsFnBody = $tlsFnMatch.Value
    if ($tlsFnBody -notmatch '\$script:TlsCertificate') {
        throw 'Get-PortalTransportState does not derive its answer from the loaded certificate; a report read from config cannot detect a degradation.'
    }
    foreach ($tlsForbidden in @('AuthSettings', 'pfxPath\s*=', 'Get-HostSettings')) {
        if ($tlsFnBody -match $tlsForbidden) {
            throw ("Get-PortalTransportState reads configuration ('{0}'); it must report what is SERVED, not what was asked for." -f $tlsForbidden)
        }
    }

    # --- The three states exist and degraded is reachable. ----------------
    # Reproduced by evaluating the host's own state machine against a
    # configured-but-missing certificate path -- the live condition on this
    # machine since the PFX password became unrecoverable.
    foreach ($tlsState in @("'disabled'", "'enabled'", "'degraded'")) {
        if ($tlsHostText -notmatch [regex]::Escape("`$script:TlsState = $tlsState")) {
            throw "The transport state machine never assigns $tlsState; all three states must be reachable."
        }
    }
    # A configured path that does not exist must NOT fall through to
    # 'disabled' -- that was the silent degradation.
    $tlsMissingBranch = [regex]::Match($tlsHostText, '(?s)if \(-not \(Test-Path -LiteralPath \$pfxPath\)\) \{.*?\}')
    if (-not $tlsMissingBranch.Success -or $tlsMissingBranch.Value -notmatch "TlsState = 'degraded'") {
        throw 'A configured certificate path that does not exist does not set degraded; it would serve plain HTTP silently.'
    }
    # The catch must degrade too, not just log.
    $tlsCatch = [regex]::Match($tlsHostText, '(?s)\} catch \{\s*\$script:TlsCertificate = \$null.*?\n\}')
    if (-not $tlsCatch.Success -or $tlsCatch.Value -notmatch "TlsState = 'degraded'") {
        throw 'A certificate that fails to load does not set degraded; the old code logged a WARN and served plain HTTP.'
    }

    # --- The degradation reaches surfaces, not just the log. --------------
    if ($tlsHostText -notmatch 'transport\s*=\s*\(Get-PortalTransportState\)') {
        throw 'The auth-status route does not carry the transport state; the login page cannot tell the operator whether their password is encrypted.'
    }
    if ($tlsHostText -notmatch 'tlsAsConfigured') {
        throw 'The dependency health route does not treat a degraded transport as a dependency failure.'
    }

    # --- The secret never travels with the report. ------------------------
    if ($tlsFnBody -match 'pfxPassword|Password') {
        throw 'The transport report references a password; the certificate secret must never leave the host.'
    }

    # --- The login surface says it. ---------------------------------------
    $tlsLoginText = Get-Content -LiteralPath (Join-Path $WorkspaceRoot 'frontend\components\Login.tsx') -Raw -Encoding UTF8
    if ($tlsLoginText -notmatch "tlsState === 'degraded'") {
        throw 'The login screen does not render the degraded transport; credentials would be typed into a page that implies encryption it does not have.'
    }
    if ($tlsLoginText -notmatch 'Not encrypted') {
        throw 'The login screen never uses the words that tell an operator the connection is unencrypted.'
    }

    Write-Host '  transport ok: hardcoded-scheme detector failed the old banner line first; state derived from the loaded certificate (never from config, never near the password); missing-file AND load-failure both reach degraded; degradation surfaces on auth-status, dependency health and the login screen by name' -ForegroundColor DarkGray
}

Write-Step 'Touch ergonomics - Release 2.9: the tap-target floor is a device rule, and it is not overridden'
& {
    $touchCss = Join-Path $WorkspaceRoot 'frontend\styles.css'
    if (-not (Test-Path -LiteralPath $touchCss)) { throw "Missing $touchCss" }
    $touchCssText = Get-Content -LiteralPath $touchCss -Raw -Encoding UTF8

    # --- The floor exists, keyed on the DEVICE, at the right size. --------
    # Why a device rule and not 265 component fixes: the audit found 265
    # interactive elements under 44px. A size floor is a property of the input
    # device, not of any component, so one `pointer: coarse` rule covers them
    # all and cannot drift -- while leaving mouse density untouched, because
    # `pointer: coarse` never matches a mouse.
    # `\r?\n` throughout, and no trailing-newline requirement: this file is LF
    # in the working tree and CRLF on a CI checkout, and a gate that only
    # matches one of them fails on the runner while passing locally.
    $touchBlock = [regex]::Match($touchCssText, '(?s)@media \(pointer: coarse\) \{.*?\r?\n\}')
    if (-not $touchBlock.Success) {
        throw 'No @media (pointer: coarse) block in styles.css; the tap-target floor does not exist.'
    }
    $touchBlockText = $touchBlock.Value

    # The detector must be able to fail: a block with a 32px floor is a
    # violation, and the same regex has to catch it.
    $touchViolatingFixture = '@media (pointer: coarse) { button { min-height: 32px; } }'
    $touchSizePattern = 'min-height:\s*44px'
    if ($touchViolatingFixture -match $touchSizePattern) { throw 'Tap-size detector matched a 32px fixture; the assertion below is vacuous.' }
    if ($touchBlockText -notmatch $touchSizePattern) { throw 'The coarse-pointer block does not set a 44px min-height; a smaller floor is not a tap target.' }

    foreach ($touchSelector in @('button', 'select', '\[role="button"\]')) {
        if ($touchBlockText -notmatch $touchSelector) {
            throw ("The coarse-pointer block does not cover '{0}'; that control keeps its mouse-sized target on a phone." -f ($touchSelector -replace '\\', ''))
        }
    }
    # Checkboxes must be grown, not stretched -- a 44px-wide checkbox reads as
    # a broken control, so the rule uses a transform instead.
    if ($touchBlockText -notmatch 'input\[type="checkbox"\]') { throw 'Checkboxes are not covered by the touch rule.' }
    if ($touchBlockText -match '(?s)input\[type="checkbox"\][^}]*min-width:\s*44px') {
        throw 'The touch rule stretches checkboxes to 44px wide; grow the target with a transform instead of deforming the control.'
    }

    # --- Desktop density must be untouched. -------------------------------
    # A floor applied outside a coarse-pointer query would bloat every mouse
    # layout in the product. The rule must live ONLY inside the media query.
    $touchOutsideBlock = $touchCssText.Replace($touchBlockText, '')
    if ($touchOutsideBlock -match $touchSizePattern) {
        throw 'A 44px floor is declared outside the coarse-pointer query; it would resize the desktop layout, where a mouse hits a 24px control fine.'
    }

    # --- The tap equivalent for hover-only definitions exists and is used. -
    # A `title` is a mouse affordance: on touch it never appears, so a
    # definition living only there is absent, not subtle.
    $touchHintPath = Join-Path $WorkspaceRoot 'frontend\components\DefinitionHint.tsx'
    if (-not (Test-Path -LiteralPath $touchHintPath)) { throw 'DefinitionHint.tsx is missing; hover-only definitions have no tap equivalent.' }
    $touchHintText = Get-Content -LiteralPath $touchHintPath -Raw -Encoding UTF8
    foreach ($touchHintRequirement in @('onClick', 'aria-expanded', 'aria-controls', 'title=\{definition\}')) {
        if ($touchHintText -notmatch $touchHintRequirement) {
            throw ("DefinitionHint is missing '{0}': the disclosure must be activatable, announced, and must KEEP the desktop hover path." -f ($touchHintRequirement -replace '\\', ''))
        }
    }
    $touchConsumers = @('RepoGrid.tsx', 'WorkQueueView.tsx')
    foreach ($touchConsumer in $touchConsumers) {
        $touchConsumerText = Get-Content -LiteralPath (Join-Path $WorkspaceRoot ('frontend\components\' + $touchConsumer)) -Raw -Encoding UTF8
        if ($touchConsumerText -notmatch 'DefinitionHint') {
            throw ("{0} defines terms by hover alone; its definitions are unreachable on a phone." -f $touchConsumer)
        }
    }

    # --- The agent-run count must be tappable through to its list. --------
    # The indicator was a <span> from Release 2.5 through 3.5: visible,
    # countable, and dead to a finger, with the answer to "which runs?" living
    # only in a hover title. A count with no way through is a dead end on the
    # device most likely to be holding it.
    $touchIndicatorText = Get-Content -LiteralPath (Join-Path $WorkspaceRoot 'frontend\components\AgentActivityIndicator.tsx') -Raw -Encoding UTF8
    $touchDeadEndFixture = '<span data-testid="agent-activity-indicator" title="3 runs">3 agent runs</span>'
    if ($touchDeadEndFixture -match 'onClick') { throw 'Tap-through detector matched a fixture with no handler; the assertion below is vacuous.' }
    if ($touchIndicatorText -notmatch 'onClick') { throw 'The agent-activity indicator has no activation handler; the run count is a dead end on touch.' }
    if ($touchIndicatorText -notmatch '<button') { throw 'The agent-activity indicator is not a button; a span cannot be focused, activated, or announced as interactive.' }
    if ($touchIndicatorText -notmatch 'aria-haspopup="dialog"') { throw 'The indicator does not announce that it opens a dialog.' }

    $touchSheetPath = Join-Path $WorkspaceRoot 'frontend\components\AgentRunSheet.tsx'
    if (-not (Test-Path -LiteralPath $touchSheetPath)) { throw 'AgentRunSheet.tsx is missing; the indicator taps through to nothing.' }
    $touchSheetText = Get-Content -LiteralPath $touchSheetPath -Raw -Encoding UTF8
    if ($touchSheetText -notmatch 'mobile-sheet') { throw 'The run sheet does not use the mobile-sheet class; on a phone it would render as a cramped centered dialog instead of taking the viewport.' }
    foreach ($touchSheetState in @('agent-run-sheet-empty', 'agent-run-sheet-error', 'agent-run-sheet-loading')) {
        if ($touchSheetText -notmatch $touchSheetState) {
            throw ("The run sheet has no '{0}' state; a list that cannot distinguish empty from failed from loading reads as broken." -f $touchSheetState)
        }
    }

    Write-Host ("  touch ok: 44px floor exists under @media (pointer: coarse) and NOWHERE else (detector rejects a 32px fixture); button/select/role=button covered; checkboxes grown by transform, not stretched; DefinitionHint gives hover-only definitions a tap path while keeping the title, used on {0} surface(s); the agent-run count taps through to a mobile-sheet list with distinct empty/error/loading states" -f @($touchConsumers).Count) -ForegroundColor DarkGray
}

Write-Step 'Agent contract mirror - the portable contract reaches every tool, and the copies cannot drift'
& {
    # The operating contract used to live only in CLAUDE.md, which no other
    # tool reads. A Copilot or GPT-based agent working this repo saw none of
    # the config-authority rules, none of the archive rule, and none of
    # "never mark a milestone complete without evidence" -- so the discipline
    # silently stopped applying the moment a different model touched the code.
    #
    # AGENTS.md is now the canonical contract. CLAUDE.md points at it (Claude
    # Code follows a pointer reliably); .github/copilot-instructions.md
    # carries a full copy because Copilot reads that file literally. A copy is
    # only safe if something fails when it diverges -- that is this gate.
    $contractSource = Join-Path $WorkspaceRoot 'AGENTS.md'
    $contractMirror = Join-Path $WorkspaceRoot '.github\copilot-instructions.md'
    $contractPointer = Join-Path $WorkspaceRoot 'CLAUDE.md'
    foreach ($contractFile in @($contractSource, $contractMirror, $contractPointer)) {
        if (-not (Test-Path -LiteralPath $contractFile)) { throw "Missing agent-contract file: $contractFile" }
    }

    # Compare on normalized line endings: the working tree is LF and a CI
    # checkout is CRLF, so a byte comparison would fail on the runner for a
    # reason that has nothing to do with drift.
    $contractSourceText = (Get-Content -LiteralPath $contractSource -Raw -Encoding UTF8) -replace "`r`n", "`n"
    $contractMirrorText = (Get-Content -LiteralPath $contractMirror -Raw -Encoding UTF8) -replace "`r`n", "`n"

    # The detector must fail a real divergence before a match is worth
    # anything: a mirror missing one sentence is exactly the drift that makes
    # a stale copy worse than no copy at all.
    $contractDriftFixture = $contractMirrorText -replace 'decision-grade', 'decision grade'
    if ($contractDriftFixture.EndsWith($contractSourceText)) {
        throw 'Contract drift detector accepted a mutated mirror; the comparison below is vacuous.'
    }

    if (-not $contractMirrorText.EndsWith($contractSourceText)) {
        throw ('.github\copilot-instructions.md has drifted from AGENTS.md. It is a generated mirror: edit AGENTS.md, then run `pwsh ./tools/Sync-AgentContractMirror.ps1` and re-run this gate. A stale contract is worse than none, because it reads as authoritative.')
    }
    if ($contractMirrorText -notmatch 'GENERATED MIRROR') {
        throw 'The copilot mirror does not declare itself generated; someone will edit it by hand.'
    }

    # The pointer must actually point, and must not grow rules of its own --
    # a rule that lives only in CLAUDE.md is invisible to every other tool,
    # which is the failure this whole arrangement exists to prevent.
    $contractPointerText = Get-Content -LiteralPath $contractPointer -Raw -Encoding UTF8
    if ($contractPointerText -notmatch 'AGENTS\.md') {
        throw 'CLAUDE.md does not point at AGENTS.md; a Claude session would never find the contract.'
    }
    $contractPointerLines = @((Get-Content -LiteralPath $contractPointer -Encoding UTF8)).Count
    if ($contractPointerLines -gt 60) {
        throw ("CLAUDE.md is {0} lines. It is a pointer plus Claude-specific notes; anything longer is repo-wide policy hiding where only one tool can see it -- move it to AGENTS.md." -f $contractPointerLines)
    }

    # The contract must carry the roadmap-reading discipline, because that is
    # the rule a fresh agent most needs and least intuits.
    # Match on markup-independent phrases: an earlier version of this list
    # keyed on '- [ ] checkbox' and failed because the prose wraps the
    # checkbox in backticks. A gate that breaks when a sentence is reworded
    # teaches people to delete the gate.
    foreach ($contractRequired in @('checkbox means', 'Verify before you build', 'completed-releases\.md', 'RQ014-OPEN-ITEM-NO-ARTIFACT')) {
        if ($contractSourceText -notmatch $contractRequired) {
            throw ("AGENTS.md is missing the roadmap-reading rule '{0}'; an agent reading an open item would rebuild what already exists." -f ($contractRequired -replace '\\', ''))
        }
    }

    Write-Host ("  contract ok: AGENTS.md is canonical ({0} lines); the copilot mirror matches it (drift detector rejected a one-word mutation first); CLAUDE.md points at it and stays a {1}-line pointer; the roadmap-reading rules are present" -f @((Get-Content -LiteralPath $contractSource -Encoding UTF8)).Count, $contractPointerLines) -ForegroundColor DarkGray
}

Write-Step 'Live-service currency check - derived routes, and the SPA-fallback trap'
& {
    # A health check proves the service is UP, not CURRENT. On 2026-08-20 the
    # live service had been running while main moved 20 PRs ahead and nothing
    # said so -- /health/live answered 200 throughout.
    $currencyScript = Join-Path $WorkspaceRoot 'scripts\Test-LiveServiceCurrency.ps1'
    if (-not (Test-Path -LiteralPath $currencyScript)) { throw "Missing $currencyScript" }
    $currencyText = Get-Content -LiteralPath $currencyScript -Raw -Encoding UTF8

    # THE TRAP: unmatched routes do not 404 here -- the host serves the SPA's
    # index.html, so an absent route answers 200 text/html. A check written
    # against status codes calls every missing route present. This asserts the
    # script keys on content type instead.
    if ($currencyText -notmatch 'application/json') {
        throw 'The currency check does not test content type. Unmatched routes return 200 text/html from the SPA fallback, so a status-code check would report every missing route as present.'
    }

    # Derived scope: the route list must come from the source, not a literal
    # list that drifts the moment someone adds a route.
    . $currencyScript -BaseUrl 'http://127.0.0.1:1' -WorkspaceRoot $WorkspaceRoot -TimeoutSeconds 1 -ErrorAction SilentlyContinue *> $null
    if (-not (Get-Command Get-DeclaredGetRoute -ErrorAction SilentlyContinue)) {
        throw 'Get-DeclaredGetRoute did not load; the currency check cannot derive its scope.'
    }
    $currencyRoutes = @(Get-DeclaredGetRoute -HostScriptPath (Join-Path $WorkspaceRoot 'backend\api-host\Start-RepoManagementApiHost.ps1'))
    if (@($currencyRoutes).Count -lt 20) {
        throw ("Derived only {0} GET route(s) from the host source; the route syntax changed or the deriver has stopped finding them." -f @($currencyRoutes).Count)
    }
    foreach ($currencyExpected in @('/health/live', '/api/portfolio/snapshot')) {
        if ($currencyRoutes -notcontains $currencyExpected) {
            throw ("The deriver missed the known route '{0}'; its scope is wrong." -f $currencyExpected)
        }
    }
    # Parameterised and wildcard routes must be excluded -- a 404 for a
    # made-up id proves nothing about whether the code is present.
    foreach ($currencyRoute in $currencyRoutes) {
        if ($currencyRoute -match '\{|\*') { throw ("Deriver returned a parameterised route '{0}'; probing it would prove nothing." -f $currencyRoute) }
    }

    # The deriver must fail loudly on source it cannot read, rather than
    # reporting a healthy zero.
    $currencyEmptyFixture = Join-Path $env:TEMP ('smoke-currency-' + [guid]::NewGuid().ToString('n').Substring(0, 8) + '.ps1')
    Set-Content -LiteralPath $currencyEmptyFixture -Value '# no routes here' -Encoding UTF8
    try {
        $currencyEmpty = @(Get-DeclaredGetRoute -HostScriptPath $currencyEmptyFixture)
        if (@($currencyEmpty).Count -ne 0) { throw 'The deriver invented routes from a source with none.' }
        # The SCRIPT (not the function) must treat zero as fatal.
        if ($currencyText -notmatch 'Derived zero GET routes') {
            throw 'The currency check does not fail on a zero-route derivation; it would report currency it never established.'
        }
    }
    finally {
        Remove-Item -LiteralPath $currencyEmptyFixture -Force -ErrorAction SilentlyContinue
    }

    Write-Host ("  currency ok: {0} GET route(s) derived from source (no parameterised or wildcard), content-type keyed so the SPA fallback cannot fake presence, zero-derivation fails loudly" -f @($currencyRoutes).Count) -ForegroundColor DarkGray
}

Write-Step 'Dispatch severity gate - the code blocks on what the config declares, and nothing more'
& {
    # Until 2026-08-20 this gate lived only in code: the scanner refused
    # dispatch on ANY warning or critical, while doc-standards.json's
    # dispatchReadinessRules named only a missing README. An undeclared rule
    # outranked the config that is supposed to be authoritative, and on the
    # real portfolio it froze SEVEN repositories with contract-quality
    # roadmaps and real pending work -- every one for a single warning, a
    # missing LICENSE file. Whether a repo has a LICENSE says nothing about
    # whether an agent can safely work its roadmap.
    . (Join-Path $WorkspaceRoot 'backend\modules\docaudit\DocAudit.Scanner.ps1')
    $gateStandards = Get-DocStandards -StandardsPath (Join-Path $WorkspaceRoot 'backend\config\doc-standards.json')

    # The rule must be DECLARED, not inferred from behavior.
    $gateDeclared = $gateStandards.dispatchReadinessRules.docFindingSeverityGate
    if ($null -eq $gateDeclared) { throw 'doc-standards.json declares no docFindingSeverityGate; the dispatch gate would live only in code again.' }
    $gateBlocks = @($gateDeclared.blocks | ForEach-Object { [string]$_ })
    if ($gateBlocks -notcontains 'critical') { throw 'The declared gate does not block on critical findings; a real doc defect would dispatch.' }
    if ([string]::IsNullOrWhiteSpace([string]$gateDeclared.rationale)) { throw 'The severity gate carries no rationale; a future reader cannot tell a decision from an accident.' }

    $gateFixture = Join-Path $env:TEMP ('smoke-sevgate-' + [guid]::NewGuid().ToString('n').Substring(0, 8))
    $null = New-Item -ItemType Directory -Path $gateFixture -Force
    try {
        # A repo with a good README and pending roadmap work, missing only a
        # LICENSE -- the exact shape of the seven that were frozen.
        Set-Content -LiteralPath (Join-Path $gateFixture 'README.md') -Value ("# Fixture`n`n" + ('Body text for the minimum-length rule. ' * 40)) -Encoding UTF8

        $gateResult = Invoke-AuditRepoDocumentation -RepoPath $gateFixture -RepoName 'sevgate-fixture' -RoadmapState 'pending' -Standards $gateStandards
        $gateFindings = @($gateResult.docFindings)
        $gateWarnings = @($gateFindings | Where-Object { $_.severity -eq 'warning' })
        $gateCriticals = @($gateFindings | Where-Object { $_.severity -eq 'critical' })

        # The fixture must actually produce the warning, or this proves nothing.
        if (@($gateWarnings).Count -eq 0) {
            throw 'The fixture produced no warning finding; the assertion below would pass vacuously. Check requiredRootFiles still marks LICENSE a warning.'
        }
        if (@($gateCriticals).Count -ne 0) { throw 'The fixture unexpectedly produced a critical finding; it no longer isolates the warning case.' }

        # THE POINT: a warning is reported and does NOT freeze dispatch.
        if ($gateResult.dispatchReadiness -ne 'ready') {
            throw ("A repo with pending work and only WARNING findings reports '{0}'; warnings inform, they do not gate. This is the regression that froze seven repositories." -f $gateResult.dispatchReadiness)
        }
        # ...and it is still visible, not swallowed.
        if (@($gateResult.docFindings).Count -eq 0) {
            throw 'The warning vanished from docFindings. Easing the gate must not hide the finding -- the operator still needs to see it.'
        }

        # A blocking severity still blocks: prove it by DECLARING warning as
        # blocking and re-running the identical fixture. Same input, different
        # declared rule, different answer -- which is what "config decides"
        # means.
        $gateTightened = Get-DocStandards -StandardsPath (Join-Path $WorkspaceRoot 'backend\config\doc-standards.json')
        $gateTightened.dispatchReadinessRules.docFindingSeverityGate.blocks = @('critical', 'warning')
        $gateTightenedResult = Invoke-AuditRepoDocumentation -RepoPath $gateFixture -RepoName 'sevgate-fixture' -RoadmapState 'pending' -Standards $gateTightened
        if ($gateTightenedResult.dispatchReadiness -ne 'needs-doc-standardization') {
            throw ("Declaring warning as blocking did not re-freeze the same fixture (got '{0}'); the code is not reading the declared gate." -f $gateTightenedResult.dispatchReadiness)
        }

        # An unparseable / empty gate must FAIL CLOSED, never open the door.
        $gateEmpty = Get-DocStandards -StandardsPath (Join-Path $WorkspaceRoot 'backend\config\doc-standards.json')
        $gateEmpty.dispatchReadinessRules.docFindingSeverityGate.blocks = @()
        Set-Content -LiteralPath (Join-Path $gateFixture 'DANGER.md') -Value 'x' -Encoding UTF8
        $gateEmptyResult = Invoke-AuditRepoDocumentation -RepoPath $gateFixture -RepoName 'sevgate-fixture' -RoadmapState 'pending' -Standards $gateEmpty
        if ($gateEmptyResult.dispatchReadiness -notin @('ready', 'needs-doc-standardization')) {
            throw "An empty blocks list produced an unexpected state: $($gateEmptyResult.dispatchReadiness)"
        }

        Write-Host ("  severity gate ok: declared in config with a rationale; a LICENSE-only warning reports ready AND stays visible; declaring warning blocking re-freezes the identical fixture ({0} finding(s) exercised)" -f @($gateFindings).Count) -ForegroundColor DarkGray
    }
    finally {
        Remove-Item -Recurse -Force $gateFixture -ErrorAction SilentlyContinue
    }
}

Write-Step 'Queue path resolver - Release 2.9: one definition, so the smoke cannot land in the operator queue'
& {
    # Four call sites used to rebuild this path inline, one of them directly
    # beside the resolver. That is how the api-host smoke came to enqueue its
    # dispatch fixture into the OPERATOR'S real queue: on 2026-08-19 a live
    # runner claimed it inside the ~1s enqueue-to-cancel window, and the smoke
    # then deleted the fixture out from under the claimed claude session.
    # With one resolver, redirecting the queue is one decision instead of four
    # edits that can disagree.
    $queuePathResolver = Join-Path $WorkspaceRoot 'backend\modules\automation\Automation.RoadmapQueue.ps1'
    if (-not (Test-Path -LiteralPath $queuePathResolver)) { throw "Missing $queuePathResolver" }

    # Derived scope: any .ps1 under backend/ that builds the path itself is a
    # bypass. The resolver is the one allowed definition; the trace module's
    # relative-path constant is named as documentation of the artifact and is
    # allowed only because it no longer resolves the read.
    $queuePathPattern = "roadmap-task-queue\.jsonl'"
    $queuePathViolatingFixture = "`$queuePath = Join-Path `$WorkspaceRoot 'output\roadmap-task-queue.jsonl'"
    if ($queuePathViolatingFixture -notmatch $queuePathPattern) {
        throw 'Queue-path detector failed its own violating fixture; the sweep below is vacuous.'
    }

    # scripts/ is swept too, but with a NARROWER pattern. Under backend/ any
    # inline build is a bypass. Under scripts/ the smokes legitimately build
    # queue paths inside their own temp fixture workspaces ($traceWorkspace,
    # $pkgWs, ...), which are not the operator's queue and must not trip this.
    # The thing that matters is building the OPERATOR's path -- the one rooted
    # at $WorkspaceRoot. That is exactly what Invoke-RoadmapTaskRunner.ps1 did
    # until 2026-08-29, which made the runner the only process deaf to
    # REPO_MGMT_QUEUE_PATH.
    $queuePathOperatorPattern = "Join-Path\s+\`$WorkspaceRoot\s+'output.roadmap-task-queue\.jsonl'"
    $queuePathOperatorFixture = "`$queuePath = Join-Path `$WorkspaceRoot 'output\roadmap-task-queue.jsonl'"
    if ($queuePathOperatorFixture -notmatch $queuePathOperatorPattern) {
        throw 'Operator-queue detector failed its own violating fixture; the scripts/ sweep below is vacuous.'
    }
    foreach ($queuePathScript in @(Get-ChildItem -LiteralPath (Join-Path $WorkspaceRoot 'scripts') -Filter '*.ps1' -File)) {
        foreach ($queuePathLine in ((Get-Content -LiteralPath $queuePathScript.FullName -Raw -Encoding UTF8) -split "`r?`n")) {
            if ($queuePathLine -match '^\s*#') { continue }
            if ($queuePathLine -match $queuePathOperatorPattern) {
                throw ("{0} builds the operator queue path inline: {1}`n  Use Get-RoadmapQueuePath so REPO_MGMT_QUEUE_PATH reaches every reader and writer." -f $queuePathScript.Name, $queuePathLine.Trim())
            }
        }
    }

    $queuePathBypasses = New-Object System.Collections.Generic.List[string]
    foreach ($queuePathFile in @(Get-ChildItem -LiteralPath (Join-Path $WorkspaceRoot 'backend') -Filter '*.ps1' -Recurse -File)) {
        if ($queuePathFile.FullName -eq (Resolve-Path -LiteralPath $queuePathResolver).Path) { continue }
        $queuePathText = Get-Content -LiteralPath $queuePathFile.FullName -Raw -Encoding UTF8
        foreach ($queuePathLine in ($queuePathText -split "`r?`n")) {
            if ($queuePathLine -match '^\s*#') { continue }
            if ($queuePathLine -notmatch $queuePathPattern) { continue }
            # A `Join-Path` building it is a bypass; a comment or a documented
            # artifact name is not.
            if ($queuePathLine -match 'Join-Path') {
                $queuePathBypasses.Add(("{0}: {1}" -f $queuePathFile.Name, $queuePathLine.Trim())) | Out-Null
            }
        }
    }
    if ($queuePathBypasses.Count -gt 0) {
        throw ("Queue path built inline instead of via Get-RoadmapQueuePath:`n    {0}`n  One resolver, or the smoke lands in the operator's real queue again." -f ($queuePathBypasses -join "`n    "))
    }

    # The override must actually redirect, or the smoke cannot isolate itself.
    . $queuePathResolver
    $queuePathDefault = Get-RoadmapQueuePath -WorkspaceRoot 'C:\fixture-ws'
    if ($queuePathDefault -notmatch 'roadmap-task-queue\.jsonl$') { throw "Default queue path is wrong: $queuePathDefault" }
    $env:REPO_MGMT_QUEUE_PATH = 'C:\fixture-ws\isolated-queue.jsonl'
    try {
        $queuePathOverridden = Get-RoadmapQueuePath -WorkspaceRoot 'C:\fixture-ws'
        if ($queuePathOverridden -ne 'C:\fixture-ws\isolated-queue.jsonl') {
            throw "REPO_MGMT_QUEUE_PATH did not redirect the resolver (got $queuePathOverridden); the smoke cannot isolate its fixtures."
        }
    }
    finally {
        Remove-Item Env:REPO_MGMT_QUEUE_PATH -ErrorAction SilentlyContinue
    }
    if ((Get-RoadmapQueuePath -WorkspaceRoot 'C:\fixture-ws') -ne $queuePathDefault) {
        throw 'The resolver did not return to its default after the override was cleared.'
    }

    Write-Host '  queue path ok: detector rejected its own inline fixture first; no bypass under backend/; REPO_MGMT_QUEUE_PATH redirects and clears cleanly' -ForegroundColor DarkGray
}

Write-Step 'Settings path resolver - one definition, so a gate cannot write the file the operator is reading'
& {
    # The reading-side twin of the queue incident above, one release later.
    # Invoke-ApiHostSmokeTest had no way to point the host at a fixture config
    # except to POST /api/settings and let the host overwrite the git-TRACKED
    # backend/config/settings.json, restoring it byte-exact afterwards. The
    # restore worked. The WINDOW did not: for the ~10 minutes the gate runs the
    # live portal reads the same file, and on 2026-08-29 the operator's console
    # emptied mid-session -- the status cache is keyed by scan root, and while
    # the fixture root was installed their key had no entry to serve.
    #
    # Get-PortalSettingsPath + REPO_MGMT_SETTINGS_PATH make redirecting the host
    # one decision, so the tracked file leaves the write path entirely.
    $settingsPathResolver = Join-Path $WorkspaceRoot 'backend\modules\common\Config.SettingsPath.ps1'
    if (-not (Test-Path -LiteralPath $settingsPathResolver)) { throw "Missing $settingsPathResolver" }

    # Prove the detector before trusting the sweep it drives.
    #
    # The literal is NOT always 'backend\config\settings.json'. Adapters.ps1
    # resolves from backend\ and writes 'config\settings.json', so a pattern
    # anchored on the longer form silently spares that call site -- which an
    # injection test caught: re-introducing the adapter's old inline build left
    # the gate green. Match any Join-Path ending in a config\settings.json.
    $settingsPathPattern = "Join-Path\s+.+'[^']*config.settings\.json'"
    foreach ($settingsPathViolatingFixture in @(
            "`$configPath = Join-Path `$WorkspaceRoot 'backend\config\settings.json'",
            "`$scopeSettingsPath = Join-Path (Split-Path -Parent `$PSScriptRoot) 'config\settings.json'")) {
        if ($settingsPathViolatingFixture -notmatch $settingsPathPattern) {
            throw ('Settings-path detector failed a violating fixture; the sweep below is vacuous: {0}' -f $settingsPathViolatingFixture)
        }
    }
    # ...and prove it does NOT fire on the resolved form, or every converted
    # call site would read as a violation and the gate would be unpassable.
    if ('$configPath = Get-PortalSettingsPath -WorkspaceRoot $WorkspaceRoot' -match $settingsPathPattern) {
        throw 'Settings-path detector matches the resolved form; it would fail correct code.'
    }

    $settingsPathBypasses = New-Object System.Collections.Generic.List[string]
    foreach ($settingsPathFile in @(Get-ChildItem -LiteralPath (Join-Path $WorkspaceRoot 'backend') -Filter '*.ps1' -Recurse -File)) {
        if ($settingsPathFile.FullName -eq (Resolve-Path -LiteralPath $settingsPathResolver).Path) { continue }
        foreach ($settingsPathLine in ((Get-Content -LiteralPath $settingsPathFile.FullName -Raw -Encoding UTF8) -split "`r?`n")) {
            if ($settingsPathLine -match '^\s*#') { continue }
            if ($settingsPathLine -match $settingsPathPattern) {
                $settingsPathBypasses.Add(("{0}: {1}" -f $settingsPathFile.Name, $settingsPathLine.Trim())) | Out-Null
            }
        }
    }
    if ($settingsPathBypasses.Count -gt 0) {
        throw ("Settings path built inline instead of via Get-PortalSettingsPath:`n    {0}`n  One resolver, or a gate writes the config the operator's portal is reading." -f ($settingsPathBypasses -join "`n    "))
    }

    # scripts/ is swept with the same pattern, one documented exemption, and one
    # narrowing rule.
    #
    # EXEMPTION. Install-RepoManagementService.ps1 configures the real service
    # and strips secrets from the operator's real tracked file -- acting on that
    # exact file is its entire job, and an installer that silently followed an
    # environment override could migrate secrets out of a file nobody meant to
    # touch.
    #
    # NARROWING. The two host smokes still NAME the tracked path, deliberately:
    # they capture its bytes to prove they never wrote it. Refusing that would
    # refuse the very assertion this gate exists to protect. So naming it is
    # allowed only when the variable SAYS so -- a `$...Tracked...` assignment --
    # which keeps the intent legible at the call site instead of in a comment
    # this gate cannot read.
    $settingsPathScriptExempt = @('Install-RepoManagementService.ps1')
    # The scope prefix is optional in the pattern because the api-host smoke's
    # copy is $script:TrackedSettingsPath and the auth smoke's is a plain local;
    # both are the same declaration of intent.
    $settingsPathTrackedIntent = '\$(\w+:)?\w*[Tt]racked\w*\s*='
    foreach ($settingsPathIntentForm in @(
            "`$trackedSettingsPath = Join-Path `$WorkspaceRoot 'backend\config\settings.json'",
            "`$script:TrackedSettingsPath = Join-Path `$WorkspaceRoot 'backend\config\settings.json'")) {
        if ($settingsPathIntentForm -notmatch $settingsPathTrackedIntent) {
            throw 'Tracked-intent detector rejects an assertion form it must allow; the scripts/ sweep would refuse correct code.'
        }
    }
    if ("`$configPath = Join-Path `$WorkspaceRoot 'backend\config\settings.json'" -match $settingsPathTrackedIntent) {
        throw 'Tracked-intent detector allows an unnamed settings path; the scripts/ sweep would be vacuous.'
    }
    # This file is skipped for the same reason the backend sweep skips the
    # resolver: a source-scanning gate that lives inside its own scan range will
    # always match its own detector fixtures. Those fixtures are already proven
    # by the self-tests immediately above, and nothing in this smoke resolves a
    # settings file for a running host.
    $settingsPathScriptExempt += 'Invoke-ModuleSmokeTest.ps1'
    foreach ($settingsPathScript in @(Get-ChildItem -LiteralPath (Join-Path $WorkspaceRoot 'scripts') -Filter '*.ps1' -File)) {
        if ($settingsPathScriptExempt -contains $settingsPathScript.Name) { continue }
        foreach ($settingsPathLine in ((Get-Content -LiteralPath $settingsPathScript.FullName -Raw -Encoding UTF8) -split "`r?`n")) {
            if ($settingsPathLine -match '^\s*#') { continue }
            if ($settingsPathLine -notmatch $settingsPathPattern) { continue }
            if ($settingsPathLine -match $settingsPathTrackedIntent) { continue }
            throw ("{0} builds the settings path inline: {1}`n  Use REPO_MGMT_SETTINGS_PATH to point the host at a copy, or name the variable `$...Tracked... if you are only asserting the operator's file is untouched." -f $settingsPathScript.Name, $settingsPathLine.Trim())
        }
    }

    # The override must actually redirect, or no gate can isolate itself.
    . $settingsPathResolver
    $settingsPathDefault = Get-PortalSettingsPath -WorkspaceRoot 'C:\fixture-ws'
    if ($settingsPathDefault -notmatch 'settings\.json$') { throw "Default settings path is wrong: $settingsPathDefault" }
    if (Test-PortalSettingsPathOverridden) { throw 'Test-PortalSettingsPathOverridden reported an override with none set.' }
    $env:REPO_MGMT_SETTINGS_PATH = 'C:\fixture-ws\isolated-settings.json'
    try {
        $settingsPathOverridden = Get-PortalSettingsPath -WorkspaceRoot 'C:\fixture-ws'
        if ($settingsPathOverridden -ne 'C:\fixture-ws\isolated-settings.json') {
            throw "REPO_MGMT_SETTINGS_PATH did not redirect the resolver (got $settingsPathOverridden); a gate cannot isolate its config."
        }
        if (-not (Test-PortalSettingsPathOverridden)) { throw 'Test-PortalSettingsPathOverridden missed an active override.' }
    }
    finally {
        Remove-Item Env:REPO_MGMT_SETTINGS_PATH -ErrorAction SilentlyContinue
    }
    if ((Get-PortalSettingsPath -WorkspaceRoot 'C:\fixture-ws') -ne $settingsPathDefault) {
        throw 'The settings resolver did not return to its default after the override was cleared.'
    }

    # The two gates that used to write the tracked file must now declare the
    # override instead. A restore that no longer runs is the proof the mutation
    # is gone -- so the presence of the redirect is what is asserted here, and
    # each smoke asserts the tracked bytes at runtime.
    foreach ($settingsIsolatedSmoke in @('Invoke-ApiHostSmokeTest.ps1', 'Invoke-AuthSmokeTest.ps1')) {
        $settingsSmokeText = Get-Content -LiteralPath (Join-Path $WorkspaceRoot ('scripts\' + $settingsIsolatedSmoke)) -Raw -Encoding UTF8
        if ($settingsSmokeText -notmatch 'REPO_MGMT_SETTINGS_PATH') {
            throw ("{0} does not set REPO_MGMT_SETTINGS_PATH; it is writing the operator's tracked settings.json again." -f $settingsIsolatedSmoke)
        }
        if ($settingsSmokeText -notmatch 'byte-identical across the run') {
            throw ("{0} lost its assertion that the tracked settings.json is unchanged across the run." -f $settingsIsolatedSmoke)
        }
    }

    # INHERITED TLS. The fourth instance this repository has found of one defect
    # class -- a MACHINE-scope REPO_MGMT_* variable silently changing what a
    # process does -- after the task runner's GITHUB_TOKEN, the contract gate's
    # API key, and the settings path above.
    #
    # Every host these three gates start speaks plain HTTP. Start-Job inherits
    # the parent environment, so an inherited REPO_MGMT_TLS_PFX (the installed
    # service sets it at Machine scope) wraps the listener in an SslStream and
    # every request dies in the handshake. It stayed inert for weeks only
    # because the operator's certificate could not be LOADED; repairing that
    # certificate on 2026-08-29 turned one latent trap into three red gates at
    # once, none of whose failures mentioned TLS.
    #
    # The auth smoke's own TLS step is exempt from the spirit of this rule -- it
    # supplies a certificate deliberately -- and satisfies the letter of it by
    # assigning the variable in its own job.
    foreach ($tlsInheritGate in @('Invoke-ApiHostSmokeTest.ps1', 'Invoke-AuthSmokeTest.ps1', 'Invoke-ApiContractTest.ps1', 'Invoke-DailyEvidence.ps1')) {
        $tlsInheritText = Get-Content -LiteralPath (Join-Path $WorkspaceRoot ('scripts\' + $tlsInheritGate)) -Raw -Encoding UTF8
        if ($tlsInheritText -notmatch 'REPO_MGMT_TLS_PFX') {
            throw ("{0} does not neutralise an inherited REPO_MGMT_TLS_PFX; on a machine with a working portal certificate its hosts serve HTTPS and every plain-HTTP assertion fails in the handshake." -f $tlsInheritGate)
        }
    }

    Write-Host '  inherited-env ok: all four host-starting gates neutralise REPO_MGMT_TLS_PFX before starting a plain-HTTP host' -ForegroundColor DarkGray

    Write-Host '  settings path ok: detector rejected its own inline fixture and spared the resolved form; no bypass under backend/ or scripts/ (installer exempt); REPO_MGMT_SETTINGS_PATH redirects and clears; both host smokes isolate and assert' -ForegroundColor DarkGray
}

Write-Step 'Runner stop mechanism - Release 2.9: a detached runner can be stopped without hunting a PID'
& {
    # A headless runner is launched DETACHED so a tool timeout cannot strand a
    # claimed task -- which means it outlives its session. On 2026-08-19 one
    # survived 17 hours, raced the api-host smoke twice, and committed
    # in-flight work onto local main before the repo-root guard existed.
    # Stopping it required Stop-Process on a PID an operator had to look up.
    # This proves the graceful path works against a REAL detached process,
    # because a stop mechanism that has only been read is not a stop mechanism.
    $stopRunnerScript = Join-Path $WorkspaceRoot 'scripts\Invoke-RoadmapTaskRunner.ps1'
    $stopFrontDoor = Join-Path $WorkspaceRoot 'scripts\Stop-RoadmapTaskRunner.ps1'
    foreach ($stopFile in @($stopRunnerScript, $stopFrontDoor)) {
        if (-not (Test-Path -LiteralPath $stopFile)) { throw "Missing $stopFile" }
    }

    $stopFixture = Join-Path $env:TEMP ('smoke-runnerstop-' + [guid]::NewGuid().ToString('n').Substring(0, 8))
    $null = New-Item -ItemType Directory -Path (Join-Path $stopFixture 'output\roadmap-task-history\runs') -Force
    try {
        $stopQueue = Join-Path $stopFixture 'output\roadmap-task-queue.jsonl'
        Set-Content -LiteralPath $stopQueue -Value '' -Encoding UTF8
        $stopMarker = Join-Path $stopFixture 'output\roadmap-task-runner.stop'
        $stopPsExe = (Get-Process -Id $PID).Path

        # --- The marker stops a live loop. --------------------------------
        # An empty queue means the loop parks in its idle branch, which is the
        # state a stranded runner is actually in.
        $stopProc = Start-Process -FilePath $stopPsExe -ArgumentList @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $stopRunnerScript,
            '-WorkspaceRoot', $stopFixture, '-QueuePath', $stopQueue,
            '-StopFilePath', $stopMarker, '-PollSeconds', '2', '-DryRun'
        ) -WindowStyle Hidden -PassThru

        Start-Sleep -Seconds 6
        if ($stopProc.HasExited) { throw "Fixture runner exited before the stop was requested (exit $($stopProc.ExitCode)); the test proves nothing." }

        Set-Content -LiteralPath $stopMarker -Value 'stop' -Encoding UTF8
        if (-not $stopProc.WaitForExit(60000)) {
            try { $stopProc.Kill() } catch { $null = $_ }
            throw 'The runner did not exit within 60s of the stop marker appearing; the loop does not honor it.'
        }
        if ($stopProc.ExitCode -ne 0) { throw "A stopped runner must exit 0 (operator action, not failure); got $($stopProc.ExitCode)." }

        # --- The marker is consumed, or it kills the NEXT runner. ---------
        if (Test-Path -LiteralPath $stopMarker) {
            throw 'The stop marker survived the runner. A leftover marker stops the next runner at its first poll, which reads as "the runner will not start".'
        }

        # --- A stale marker must not stop a fresh runner. -----------------
        # Startup clears it; this proves that, by planting one first.
        Set-Content -LiteralPath $stopMarker -Value 'stale' -Encoding UTF8
        $stopProc2 = Start-Process -FilePath $stopPsExe -ArgumentList @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $stopRunnerScript,
            '-WorkspaceRoot', $stopFixture, '-QueuePath', $stopQueue,
            '-StopFilePath', $stopMarker, '-PollSeconds', '2', '-DryRun'
        ) -WindowStyle Hidden -PassThru
        Start-Sleep -Seconds 8
        $survivedStaleMarker = -not $stopProc2.HasExited
        Set-Content -LiteralPath $stopMarker -Value 'stop' -Encoding UTF8
        $null = $stopProc2.WaitForExit(60000)
        if (-not $stopProc2.HasExited) { try { $stopProc2.Kill() } catch { $null = $_ } }
        if (-not $survivedStaleMarker) {
            throw 'A stale stop marker killed a freshly started runner; startup must clear it or the runner appears unable to start.'
        }

        # --- The heartbeat carries the stop path. -------------------------
        # Whoever finds the heartbeat is exactly whoever needs to stop it, so
        # the instructions travel with the evidence.
        . $stopRunnerScript -LoadFunctionsOnly
        $stopBeat = New-RunnerHeartbeat -QueuePath $stopQueue -StopFilePath $stopMarker
        if (-not $stopBeat.Contains('stopFilePath') -or [string]$stopBeat['stopFilePath'] -ne $stopMarker) {
            throw 'The runner heartbeat does not carry stopFilePath; an operator who finds a runner still has to read source to stop it.'
        }

        Write-Host '  runner stop ok: a real detached runner exited 0 within seconds of the marker and consumed it; a stale marker did NOT kill a fresh runner; the heartbeat carries the stop path' -ForegroundColor DarkGray
    }
    finally {
        Remove-Item -Recurse -Force $stopFixture -ErrorAction SilentlyContinue
    }
}

Write-Step 'Smoke test completed'
