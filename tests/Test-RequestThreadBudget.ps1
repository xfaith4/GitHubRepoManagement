[CmdletBinding()]
param(
    [string]$Route = '/api/portfolio/assessment',
    [int]$MaxMs = 2000,
    [switch]$FailOnError,
    [string]$HostPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'backend/api-host/Start-RepoManagementApiHost.ps1')
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($Route -ne '/api/portfolio/assessment') { throw "Unsupported route: $Route" }
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($HostPath, [ref]$null, [ref]$errors)
if ($errors.Count) { throw $errors[0] }
$functions = @{}
foreach ($fn in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) { $functions[$fn.Name] = $fn }
$switches = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.SwitchStatementAst] }, $true))
$routeBody = $null
foreach ($switch in $switches) {
    foreach ($clause in $switch.Clauses) {
        if ($clause.Item1.Extent.Text.Trim("'", '"') -eq "GET $Route") { $routeBody = $clause.Item2 }
    }
}
if ($null -eq $routeBody) { throw 'Assessment route not found; cannot prove a budget.' }
# Follow host helpers, so hiding a scan one function down still fails.
$forbidden = @('Get-GitHubReposViaApi','Get-StatusAdapterResult','Invoke-RoadmapScan','Invoke-DocAuditScan','Invoke-RoadmapAuditScan','Invoke-PortfolioAssessment','Invoke-BackgroundPortfolioAssessment','Save-PortfolioIndexArtifacts')
function Assert-ReadOnlyRoute($Node, $Seen) {
    foreach ($call in $Node.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)) {
        $name = $call.GetCommandName()
        if ($name -in $forbidden) { throw "Request thread invokes $name" }
        if ($name -and $functions.ContainsKey($name) -and -not $Seen.ContainsKey($name)) {
            $Seen[$name] = $true
            Assert-ReadOnlyRoute $functions[$name].Body $Seen
        }
    }
}
Assert-ReadOnlyRoute $routeBody @{}
if (-not $functions.ContainsKey('Get-PortfolioAssessmentReadPayload')) { throw 'Missing indexed read function.' }
. ([scriptblock]::Create($functions['Get-PortfolioAssessmentReadPayload'].Extent.Text))
# Isolated dependencies: no service, token, live index or ledger is touched.
$WorkspaceRoot = $PSScriptRoot
$script:index = $null
$script:starts = 0
$script:state = 'never-run'
function Get-HostSettings { return @{ inventory = @{ maxDepth = 3 } } }
function Get-PortfolioIndexPayload { return $script:index }
function Get-ObjectPropertyValue($InputObject, $PropertyName, $Default) {
    if ($InputObject.PSObject.Properties.Name -contains $PropertyName) { return $InputObject.$PropertyName }; return $Default
}
function Get-PortfolioAssessmentCacheTtlSeconds { return 120 }
function Parse-Bool($Value, $Default) { return [string]$Value -eq 'true' }
function Get-PortfolioScanState { return @{ state = $script:state; error = $(if ($script:state -eq 'failed') { 'fixture failure' } else { $null }) } }
function Get-ConfiguredLocalRootsOrWorkspace { return @('fixture') }
function Start-BackgroundStatusRefresh { param($LocalRoots, $MaxDepth, [switch]$ForceAssessment) $script:starts++; return $false }
function Convert-PortfolioIndexReposToAssessments($IndexRepos) { return $IndexRepos }
function Add-PortfolioCurationToAssessments($Assessments) { return $Assessments }
function Get-PortfolioAssessmentSummary($Assessments) { return @{ totalRepos = @($Assessments).Count } }
function New-PortfolioReadBudgetResult { return @{} }
foreach ($case in @('cold', 'fresh', 'stale-running', 'failed', 'republished', 'forced')) {
    $stamp = [datetime]::UtcNow
    if ($case -in @('stale-running', 'failed')) { $stamp = $stamp.AddMinutes(-10) }
    $script:state = if ($case -eq 'stale-running') { 'running' } elseif ($case -eq 'failed') { 'failed' } else { 'completed' }
    $script:index = if ($case -eq 'cold') { $null } else { [pscustomobject]@{
        staleness = [pscustomobject]@{ stale = $false }; generatedAt = $stamp.ToString('o'); signalSources = [pscustomobject]@{ github = 'api' }
        repos = @([pscustomobject]@{ repoName = $case; sourceCoverage = 'local' }, [pscustomobject]@{ repoName = 'remote'; sourceCoverage = 'github' })
    } }
    $before = $script:starts
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $result = Get-PortfolioAssessmentReadPayload -ForceRefresh:($case -eq 'forced')
    $sw.Stop()
    if ($sw.ElapsedMilliseconds -gt $MaxMs) { throw "$case exceeded ${MaxMs}ms: $($sw.ElapsedMilliseconds)ms" }
    if ($case -eq 'cold') {
        if ($result.available -or $null -ne $result.generatedAt -or $null -ne $result.summary) { throw 'Cold read invented assessment evidence.' }
    } elseif ($result.entries.Count -ne 1 -or $result.entries[0].repoName -ne $case) { throw 'Read did not use current index/local scope.' }
    if ($case -in @('cold','stale-running','failed','forced') -and $script:starts -ne ($before + 1)) { throw 'Refresh was not requested.' }
    if ($case -eq 'fresh' -and $script:starts -ne $before) { throw 'Fresh read launched unnecessary scan.' }
    if ($case -eq 'failed' -and $result.refresh.error -ne 'fixture failure') { throw 'Worker failure disappeared.' }
    Write-Host "PASS $case $($sw.ElapsedMilliseconds)ms"
}
$all = Get-PortfolioAssessmentReadPayload -Query @{ includeGithub = 'true'; includeCuration = 'true' }
if ($all.entries.Count -ne 2) { throw 'GitHub opt-in lost.' }
Write-Host 'PASS assessment request call graph and indexed read budget'

# Exercise the real publication function twice: replacement and full assessment
# preservation are essential once readers and the producer run concurrently.
$modulePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'backend/modules/portfolio/Portfolio.Assessment.ps1'
$moduleAst = [System.Management.Automation.Language.Parser]::ParseFile($modulePath, [ref]$null, [ref]$null)
$publisher = $moduleAst.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Save-PortfolioIndexArtifacts' }, $true)
. ([scriptblock]::Create($publisher.Extent.Text))
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('assessment-publication-' + [guid]::NewGuid().ToString('n'))
function Get-PortfolioIndexRoot { return $tempRoot }
function Get-PortfolioIndexLogicFingerprint { return 'fixture-logic' }
function New-PortfolioIndexPayload { return [pscustomobject]@{ repoCount = 1; repos = @() } }
try {
    foreach ($generation in @(1, 2)) {
        $entry = [pscustomobject]@{ repoName = 'fixture'; pendingItems = @('preserved'); generation = $generation }
        $published = Save-PortfolioIndexArtifacts -WorkspaceRoot $tempRoot -Assessments @($entry) -GeneratedAt ([datetime]::UtcNow.ToString('o'))
        $saved = Get-Content -LiteralPath $published.indexPath -Raw | ConvertFrom-Json
        if ($saved.assessmentEntries[0].generation -ne $generation -or $saved.assessmentEntries[0].pendingItems[0] -ne 'preserved') { throw 'Index publication lost the full assessment.' }
    }
    if (@(Get-ChildItem -LiteralPath $tempRoot -Filter '*.tmp*').Count) { throw 'Publication left temporary artifacts.' }
} finally {
    if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
}
Write-Host 'PASS atomic replacement preserves complete assessment generations'
