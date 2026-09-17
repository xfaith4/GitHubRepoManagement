#Requires -Version 7.0
<#
.SYNOPSIS
    Test fixtures never reach the operator's live state (Lane 0.22).

.DESCRIPTION
    On 2026-09-15, 175 of the operator's 192 agent-run records were the
    api-host smoke's `dispatch-success-smoke`. They were most of the console's
    "100 agent runs" badge, and `smoke-packaging-repo` led the packaged work
    queue. The smoke isolated the index, queue and settings, but every other
    ledger under `output\` was built inline as
    `Join-Path $WorkspaceRoot 'output\...'`.

    Four checks, each run against a violating case first where one applies:

      1. resolver - no code under backend\ or scripts\ builds an `output\`
         path without Get-OutputRoot or Resolve-OutputPath. Named exemptions
         carry their reasons. The detector must flag its own violating
         fixtures and pass the resolved forms before its sweep counts.
      2. redirect - with REPO_MGMT_OUTPUT_ROOT set, the agent-run ledger,
         packaged items, work packets, app.db, write-back history, index,
         queue, runner state and operation heartbeat all resolve under it,
         and writing a run and a packaged item leaves the workspace's own
         `output\` absent. Clearing the override restores every default.
      3. gates - every file that starts an API host sets
         REPO_MGMT_OUTPUT_ROOT. The list is derived: a file that names the
         host script and passes -BindAddress starts one.
      4. records already written - in the operator's root, each listed fixture
         is hidden from the agent-run list and the packaged queue, and a real
         repository is not. Under an override nothing is hidden, because a
         gate must be able to read its own fixtures back.

.EXAMPLE
    pwsh ./tests/Test-FixtureIsolation.ps1 -FailOnError
#>
[CmdletBinding()]
param(
    [Parameter()][string]$WorkspaceRoot = (Split-Path -Parent $PSScriptRoot),
    [Parameter()][switch]$FailOnError
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$WorkspaceRoot = (Resolve-Path -LiteralPath $WorkspaceRoot).Path
$failures = [System.Collections.Generic.List[string]]::new()
$notes = [System.Collections.Generic.List[string]]::new()

# ---------------------------------------------------------------------------
# 1. resolver
# ---------------------------------------------------------------------------

# A Join-Path (or -ChildPath) whose argument is an output\ literal, unless the
# literal is what -RelativePath hands to the resolver.
$literalPattern = '(?i)(?:Join-Path\b[^#\r\n]*?|-ChildPath\s+)(?<!-RelativePath\s*\(?\s*)\(?\s*[''"]output(?:[''"]|[\\/])'

function Get-OutputConstantName {
    # $script: constants assigned an output\ literal in one file.
    param([string]$Text)
    @([regex]::Matches($Text, '(?im)^\s*\$script:(?<name>\w+)\s*=\s*[''"]output(?:[''"]|[\\/])') | ForEach-Object { $_.Groups['name'].Value })
}

function Find-UnresolvedOutputPath {
    param([string]$Text)
    $constants = @(Get-OutputConstantName -Text $Text)
    $hits = [System.Collections.Generic.List[object]]::new()
    $lineNumber = 0
    foreach ($line in ($Text -split "`r?`n")) {
        $lineNumber++
        if ($line -match '^\s*#') { continue }
        $flag = $line -match $literalPattern
        if (-not $flag) {
            foreach ($name in $constants) {
                if ($line -match ('(?i)Join-Path\s+\S+\s+\$script:{0}\b' -f [regex]::Escape($name))) { $flag = $true; break }
            }
        }
        if ($flag) { $hits.Add([pscustomobject]@{ Line = $lineNumber; Text = $line.Trim() }) }
    }
    # Enumerated, not wrapped: every caller collects with @().
    return $hits.ToArray()
}

$violating = @(
    "`$dir = Join-Path `$WorkspaceRoot 'output\agent-runs\runs'"
    "`$p = Join-Path `$WorkspaceRoot (""output\roadmap-task-history\runs\{0}.summary.json"" -f `$id)"
    "`$root = Join-Path `$WorkspaceRoot 'output'"
    "`$out = Join-Path -Path `$workspaceRoot -ChildPath 'output/reconciliation'"
    "`$x = Join-Path (Join-Path `$WorkspaceRoot 'output\auth') 'api-key'"
)
foreach ($fixture in $violating) {
    if (@(Find-UnresolvedOutputPath -Text $fixture).Count -ne 1) {
        $failures.Add("resolver detector missed a violating fixture, so its sweep proves nothing: $fixture")
    }
}
$constantFixture = "`$script:LedgerRelDir = 'output\ledger'`nfunction f { Join-Path `$WorkspaceRoot `$script:LedgerRelDir }"
if (@(Find-UnresolvedOutputPath -Text $constantFixture).Count -ne 1) {
    $failures.Add('resolver detector missed a Join-Path over an output\ constant')
}
$resolved = @(
    "`$dir = Resolve-OutputPath -WorkspaceRoot `$WorkspaceRoot -RelativePath 'output\agent-runs\runs'"
    "`$p = Join-Path (Resolve-OutputPath -WorkspaceRoot `$WorkspaceRoot -RelativePath 'output\roadmap-task-history\runs') ('{0}.json' -f `$id)"
    "`$p = Resolve-OutputPath -WorkspaceRoot `$WorkspaceRoot -RelativePath (""output\runs\{0}.json"" -f `$id)"
    "`$root = Get-OutputRoot -WorkspaceRoot `$WorkspaceRoot"
    "`$here = Join-Path `$PSScriptRoot '..\output\queue'"
    "`$script:LedgerRelDir = 'output\ledger'`nfunction f { Resolve-OutputPath -WorkspaceRoot `$WorkspaceRoot -RelativePath `$script:LedgerRelDir }"
)
foreach ($fixture in $resolved) {
    if (@(Find-UnresolvedOutputPath -Text $fixture).Count -ne 0) {
        $failures.Add("resolver detector flags a resolved form, so it would fail correct code: $fixture")
    }
}

# Named exemptions. A file exemption covers the whole file; a line exemption
# covers only lines containing its text.
$fileExemptions = @{
    'backend\modules\common\Config.OutputRoot.ps1'              = 'the resolver itself'
    'backend\modules\reconcile\Invoke-Reconciliation.Modular.ps1' = 'resolves under backend\ (its $workspaceRoot is two levels up from the module), not the workspace output'
    'scripts\Invoke-ModuleSmokeTest.ps1'                         = 'builds temporary workspaces and holds its own detector fixtures'
    'backend\api-host\ApiHost.Contract.Tests.ps1'                = 'a gate; its own scratch root is output\contract-tests'
}
$lineExemptions = @(
    @{ Text = 'output\auth'; Reason = 'the host API key is a credential and stays the operator''s' }
    @{ Text = 'output\smoke\'; Reason = 'a gate''s own scratch root' }
    @{ Text = 'output\roadmap-task-runner.'; Reason = 'the api-host smoke reads the operator''s live runner files only to prove it never touched them' }
    @{ Text = 'Join-Path $smokeRoot'; Reason = 'a host smoke building its isolated output root inside its own scratch root' }
)

$sweepFiles = @(
    Get-ChildItem -LiteralPath (Join-Path $WorkspaceRoot 'backend') -Filter '*.ps1' -Recurse -File
    Get-ChildItem -LiteralPath (Join-Path $WorkspaceRoot 'scripts') -Filter '*.ps1' -Recurse -File
) | Where-Object { $_.FullName -notmatch '\\node_modules\\' }
$bypasses = [System.Collections.Generic.List[string]]::new()
foreach ($file in $sweepFiles) {
    $relative = $file.FullName.Substring($WorkspaceRoot.Length).TrimStart('\', '/')
    if ($fileExemptions.ContainsKey($relative)) { continue }
    foreach ($hit in @(Find-UnresolvedOutputPath -Text (Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8))) {
        $normalized = $hit.Text -replace '/', '\'
        if (@($lineExemptions | Where-Object { $normalized.IndexOf($_.Text, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 }).Count -gt 0) { continue }
        $bypasses.Add(('{0}:{1}: {2}' -f $relative, $hit.Line, $hit.Text))
    }
}
if ($sweepFiles.Count -lt 50) {
    $failures.Add("the resolver sweep read only $($sweepFiles.Count) file(s); it is not looking where the code is")
}
foreach ($bypass in $bypasses) {
    $failures.Add("output\ path built without the resolver: $bypass")
}
$notes.Add(("resolver: detector flagged {0} violating fixtures and passed {1} resolved forms; {2} file(s) swept, {3} bypass(es), {4} file and {5} line exemption(s)" -f ($violating.Count + 1), $resolved.Count, $sweepFiles.Count, $bypasses.Count, $fileExemptions.Count, $lineExemptions.Count))

# The opposite mistake: the resolver handed a constant that is not under
# output\. It throws at run time, and a caller that collects per-item errors
# turns that into an empty result. The conversion that introduced this
# resolver did exactly that to the AI template path (config, not output), and
# the only symptom was "0 proposals".
function Find-MisresolvedConstant {
    param([string]$Text)
    $outputConstants = @(Get-OutputConstantName -Text $Text)
    @([regex]::Matches($Text, 'Resolve-OutputPath\b[^\r\n#]*-RelativePath\s+\$script:(?<name>\w+)') |
        Where-Object { $outputConstants -notcontains $_.Groups['name'].Value } |
        ForEach-Object { $_.Groups['name'].Value })
}
$misresolvedFixture = "`$script:TemplatesRelPath = 'backend\config\ai-doc-templates.json'`n`$p = Resolve-OutputPath -WorkspaceRoot `$WorkspaceRoot -RelativePath `$script:TemplatesRelPath"
if (@(Find-MisresolvedConstant -Text $misresolvedFixture).Count -ne 1) {
    $failures.Add('the misresolved-constant detector missed its fixture, so its sweep proves nothing')
}
$wellResolvedFixture = "`$script:LedgerRelDir = 'output\ledger'`n`$p = Resolve-OutputPath -WorkspaceRoot `$WorkspaceRoot -RelativePath `$script:LedgerRelDir"
if (@(Find-MisresolvedConstant -Text $wellResolvedFixture).Count -ne 0) {
    $failures.Add('the misresolved-constant detector flags an output\ constant')
}
$misresolvedCount = 0
foreach ($file in $sweepFiles) {
    $relative = $file.FullName.Substring($WorkspaceRoot.Length).TrimStart('\', '/')
    foreach ($name in @(Find-MisresolvedConstant -Text (Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8))) {
        $misresolvedCount++
        $failures.Add("$relative passes `$script:$name to Resolve-OutputPath, but that constant is not an output\ path (declared elsewhere or pointing outside output\)")
    }
}
$notes.Add(("resolver input: every `$script: constant given to Resolve-OutputPath is an output\ path ({0} misresolved)" -f $misresolvedCount))

# ---------------------------------------------------------------------------
# 2. redirect
# ---------------------------------------------------------------------------

$modules = @(
    'backend\modules\common\Config.OutputRoot.ps1'
    'backend\modules\common\Config.IndexPath.ps1'
    'backend\modules\common\Fixture.Records.ps1'
    'backend\modules\automation\Automation.RoadmapQueue.ps1'
    'backend\modules\automation\Automation.RunnerPresence.ps1'
    'backend\modules\automation\Automation.RoadmapPackaging.ps1'
    'backend\modules\agent-runs\AgentRuns.ps1'
    'backend\modules\execution\Execution.WorkPacket.ps1'
    'backend\modules\persistence\Persistence.Store.ps1'
    'backend\modules\roadmap\Roadmap.WriteBack.ps1'
    'backend\api-host\OperationHeartbeat.ps1'
)
foreach ($module in $modules) { . (Join-Path $WorkspaceRoot $module) }

$scratch = Join-Path ([System.IO.Path]::GetTempPath()) ('fixture-isolation-' + [guid]::NewGuid().ToString('n').Substring(0, 8))
$fakeWorkspace = Join-Path $scratch 'workspace'
$isolatedRoot = Join-Path $scratch 'isolated-output'
$null = New-Item -ItemType Directory -Path $fakeWorkspace -Force
$priorOverride = [Environment]::GetEnvironmentVariable('REPO_MGMT_OUTPUT_ROOT')
$priorOthers = @{}
foreach ($name in 'REPO_MGMT_INDEX_ROOT', 'REPO_MGMT_QUEUE_PATH', 'REPO_MGMT_RUNNER_CONTROL_ROOT') {
    $priorOthers[$name] = [Environment]::GetEnvironmentVariable($name)
    [Environment]::SetEnvironmentVariable($name, $null)
}

$resolvers = [ordered]@{
    'agent-run ledger'    = { _AgentRunsRunsDir -WorkspaceRoot $fakeWorkspace }
    'agent-run events'    = { _AgentRunEventsPath -WorkspaceRoot $fakeWorkspace }
    'packaged items'      = { Get-PackagedItemsFilePath -WorkspaceRoot $fakeWorkspace }
    'work packet'         = { Get-WorkPacketPath -WorkspaceRoot $fakeWorkspace -TaskId 'probe' }
    'app database'        = { Get-AppDatabasePath -WorkspaceRoot $fakeWorkspace }
    'write-back history'  = { Get-RoadmapWriteBackHistoryPath -WorkspaceRoot $fakeWorkspace }
    'portfolio index'     = { Get-PortfolioIndexRoot -WorkspaceRoot $fakeWorkspace }
    'task queue'          = { Get-RoadmapQueuePath -WorkspaceRoot $fakeWorkspace }
    'runner state'        = { Get-RunnerControlRoot -WorkspaceRoot $fakeWorkspace }
    'operation heartbeat' = { Get-PortalOperationStatePath -WorkspaceRoot $fakeWorkspace }
}

try {
    [Environment]::SetEnvironmentVariable('REPO_MGMT_OUTPUT_ROOT', $isolatedRoot)
    foreach ($label in $resolvers.Keys) {
        $path = [string](& $resolvers[$label])
        if (-not $path.StartsWith($isolatedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            $failures.Add("with REPO_MGMT_OUTPUT_ROOT set, the $label still resolves to $path")
        }
    }

    $run = New-AgentRunRecord -WorkspaceRoot $fakeWorkspace -RepoName 'isolation-probe' -SelectedTaskText 'Fixture isolation probe'
    $null = Write-PackagedItemRecord -WorkspaceRoot $fakeWorkspace -Record @{ packetId = 'pkt-isolation-probe'; status = 'pending-approval'; repoName = 'isolation-probe'; recordedAt = (Get-Date).ToUniversalTime().ToString('o') }
    if (-not (Test-Path -LiteralPath (Join-Path $isolatedRoot ("agent-runs\runs\{0}.json" -f $run.runId)))) {
        $failures.Add('New-AgentRunRecord did not write under the isolated output root')
    }
    if (-not (Test-Path -LiteralPath (Join-Path $isolatedRoot 'automation\packaged-items.jsonl'))) {
        $failures.Add('Write-PackagedItemRecord did not write under the isolated output root')
    }
    if (Test-Path -LiteralPath (Join-Path $fakeWorkspace 'output')) {
        $failures.Add(("writes under an override still created the workspace's own output\: {0}" -f ((Get-ChildItem -LiteralPath (Join-Path $fakeWorkspace 'output') -Recurse -File | ForEach-Object { $_.FullName }) -join ', ')))
    }
}
finally {
    [Environment]::SetEnvironmentVariable('REPO_MGMT_OUTPUT_ROOT', $null)
}

$defaultRoot = Join-Path $fakeWorkspace 'output'
foreach ($label in $resolvers.Keys) {
    $path = [string](& $resolvers[$label])
    if (-not $path.StartsWith($defaultRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        $failures.Add("with the override cleared, the $label resolves to $path instead of the workspace's output\")
    }
}
$notes.Add(("redirect: {0} resolvers follow REPO_MGMT_OUTPUT_ROOT and return to output\ when it clears; a run and a packaged item written under the override left the workspace output\ absent" -f $resolvers.Count))

# ---------------------------------------------------------------------------
# 3. gates
# ---------------------------------------------------------------------------

$hostStartExemptions = @{
    'scripts\Install-RepoManagementService.ps1' = 'installs the operator''s own service, which must write the real output\'
    'scripts\Invoke-DailyEvidence.ps1'          = 'captures the operator''s real portfolio by design'
}
$hostStarters = [System.Collections.Generic.List[string]]::new()
foreach ($root in 'scripts', 'tests', 'backend', 'tools') {
    $dir = Join-Path $WorkspaceRoot $root
    if (-not (Test-Path -LiteralPath $dir)) { continue }
    foreach ($file in @(Get-ChildItem -LiteralPath $dir -Include '*.ps1', '*.psm1' -Recurse -File)) {
        $relative = $file.FullName.Substring($WorkspaceRoot.Length).TrimStart('\', '/')
        if ($relative -eq 'backend\api-host\Start-RepoManagementApiHost.ps1') { continue }
        $text = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
        if ($text -notmatch 'Start-RepoManagementApiHost\.ps1' -or $text -notmatch '-BindAddress') { continue }
        $hostStarters.Add($relative)
        if ($hostStartExemptions.ContainsKey($relative)) { continue }
        if ($text -notmatch 'REPO_MGMT_OUTPUT_ROOT') {
            $failures.Add("$relative starts an API host without setting REPO_MGMT_OUTPUT_ROOT; its agent runs, packaged items and app.db would land in the operator's output\")
        }
    }
}
if ($hostStarters.Count -lt 4) {
    $failures.Add(("found only {0} host-starting file(s) ({1}); the derivation is not seeing the gates" -f $hostStarters.Count, ($hostStarters -join ', ')))
}
$notes.Add(("gates: {0} file(s) start a host, {1} exempt by name, the rest set REPO_MGMT_OUTPUT_ROOT" -f $hostStarters.Count, $hostStartExemptions.Count))

# ---------------------------------------------------------------------------
# 4. records already written
# ---------------------------------------------------------------------------

$fixtureNames = @(Get-LiveLedgerFixtureRepoName)
if ($fixtureNames.Count -lt 1) { $failures.Add('the fixture list is empty; nothing would be hidden') }
foreach ($name in $fixtureNames) {
    $null = New-AgentRunRecord -WorkspaceRoot $fakeWorkspace -RepoName $name -GitHubRepo "smoke-owner/$name"
    $null = Write-PackagedItemRecord -WorkspaceRoot $fakeWorkspace -Record @{ packetId = "pkt-$name"; status = 'pending-approval'; repoName = $name; recordedAt = (Get-Date).ToUniversalTime().ToString('o') }
}
$realRun = New-AgentRunRecord -WorkspaceRoot $fakeWorkspace -RepoName 'RealRepository' -GitHubRepo 'owner/RealRepository'
$null = Write-PackagedItemRecord -WorkspaceRoot $fakeWorkspace -Record @{ packetId = 'pkt-real'; status = 'pending-approval'; repoName = 'RealRepository'; recordedAt = (Get-Date).ToUniversalTime().ToString('o') }

$listed = @(Get-AgentRuns -WorkspaceRoot $fakeWorkspace -Limit 500)
$listedNames = @($listed | ForEach-Object { [string]$_.repoName })
foreach ($name in $fixtureNames) {
    if ($listedNames -contains $name) { $failures.Add("the agent-run list shows fixture '$name' from the operator's root") }
}
if ($listedNames -notcontains 'RealRepository') { $failures.Add('the agent-run list hides a real repository') }
$queued = @(Get-PackagedItemQueue -WorkspaceRoot $fakeWorkspace -Limit 500)
$queuedNames = @($queued | ForEach-Object { [string]$_.repoName })
foreach ($name in $fixtureNames) {
    if ($queuedNames -contains $name) { $failures.Add("the packaged queue shows fixture '$name' from the operator's root") }
}
if ($queuedNames -notcontains 'RealRepository') { $failures.Add('the packaged queue hides a real repository') }
if (-not (Test-FixtureRecord -Record @{ githubRepo = "someone/$($fixtureNames[0])" })) {
    $failures.Add('an owner/name githubRepo naming a fixture is not recognised')
}
if (Test-FixtureRecord -Record @{ repo_name = 'RealRepository' }) {
    $failures.Add('a real repository name is recognised as a fixture')
}

try {
    [Environment]::SetEnvironmentVariable('REPO_MGMT_OUTPUT_ROOT', $isolatedRoot)
    $null = New-AgentRunRecord -WorkspaceRoot $fakeWorkspace -RepoName $fixtureNames[0]
    $ownFixtures = @(Get-AgentRuns -WorkspaceRoot $fakeWorkspace -Limit 500 | Where-Object { [string]$_.repoName -eq $fixtureNames[0] })
    if ($ownFixtures.Count -ne 1) {
        $failures.Add("under an override a gate must read its own fixture back; Get-AgentRuns returned $($ownFixtures.Count)")
    }
}
finally {
    [Environment]::SetEnvironmentVariable('REPO_MGMT_OUTPUT_ROOT', $priorOverride)
    foreach ($name in $priorOthers.Keys) { [Environment]::SetEnvironmentVariable($name, $priorOthers[$name]) }
}
$null = $realRun
$notes.Add(("records: {0} listed fixture name(s) hidden from the agent-run list and the packaged queue in the operator's root; a real repository shown; under an override a gate reads its own fixture back" -f $fixtureNames.Count))

Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue

Write-Host 'Fixture isolation (Lane 0.22):' -ForegroundColor Cyan
foreach ($note in $notes) { Write-Host "  $note" -ForegroundColor DarkGray }
if ($failures.Count -gt 0) {
    Write-Host ("Fixture isolation: FAIL - {0} problem(s)." -f $failures.Count) -ForegroundColor Red
    foreach ($failure in $failures) { Write-Host "  - $failure" -ForegroundColor Red }
    if ($FailOnError) { exit 1 }
    exit 0
}
Write-Host 'Fixture isolation: PASS' -ForegroundColor Green
exit 0
