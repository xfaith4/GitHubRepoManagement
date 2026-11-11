#Requires -Version 7.0
<#
.SYNOPSIS
    D-012, the rest - a cloud agent's pull request is held to the same
    envelope as a local run, a proposed workflow is reported as waiting for
    the owner, and `network true` grants nothing without an approved
    allowlist.

.DESCRIPTION
    Proved offline, in five layers:

      - The shared verdict (Test-ChangedPathEnvelope): passed, failed, and
        unproven when the paths could not be read; proposed workflows listed.
      - The host's road (Invoke-AgentRunRefresh): a Copilot pull request that
        touches a forbidden path fails the run and is never recorded as
        delivered, merged or not; one whose files were not read is not
        recorded as delivered either; green CI never verifies a head whose
        envelope did not pass. Plus the host wiring that feeds it, read from
        the AST.
      - The runner's road (Test-RunPermissionEnvelope) names proposed
        workflows in its result, and both run summaries carry them.
      - The network allowlist: packet validation, the resolver's states, the
        fingerprint that makes a changed list stale, and the Claude settings
        each state produces.
      - The owner's approval command (tools/Approve-WorkPacketNetwork.ps1).

    Writes only under temporary directories, removed on exit.

.EXAMPLE
    pwsh ./tests/Test-EnvelopeCloudAndNetwork.ps1 -FailOnError
#>
[CmdletBinding()]
param(
    [Parameter()][string]$WorkspaceRoot = (Split-Path -Parent $PSScriptRoot),
    [Parameter()][switch]$FailOnError
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$WorkspaceRoot = (Resolve-Path -LiteralPath $WorkspaceRoot).Path
$runnerPath = Join-Path $WorkspaceRoot 'scripts/Invoke-RoadmapTaskRunner.ps1'
$hostPath = Join-Path $WorkspaceRoot 'backend/api-host/Start-RepoManagementApiHost.ps1'
$approvePath = Join-Path $WorkspaceRoot 'tools/Approve-WorkPacketNetwork.ps1'

. (Join-Path $WorkspaceRoot 'backend/modules/common/Config.OutputRoot.ps1')
. (Join-Path $WorkspaceRoot 'backend/modules/execution/Execution.WorkPacket.ps1')
. (Join-Path $WorkspaceRoot 'backend/modules/agent-adapters/Adapter.Claude.ps1')
. (Join-Path $WorkspaceRoot 'backend/modules/agent-runs/AgentRuns.ps1')
. $runnerPath -LoadFunctionsOnly

$failures = [System.Collections.Generic.List[string]]::new()
$passed = 0
function Assert-That {
    param([bool]$Condition, [string]$Message)
    if ($Condition) { $script:passed++ } else { $script:failures.Add($Message) }
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("envelope-cloud-network-{0}" -f [guid]::NewGuid().ToString('n'))
$null = New-Item -ItemType Directory -Path $tempRoot -Force
$savedOutputRoot = $env:REPO_MGMT_OUTPUT_ROOT
$env:REPO_MGMT_OUTPUT_ROOT = Join-Path $tempRoot 'output'

try {
    # --- The shared verdict ---
    $clean = Test-ChangedPathEnvelope -ChangedPath @('src/a.ps1', 'README.md') -Packet $null
    Assert-That ($clean.state -eq 'passed' -and $clean.ok -and $clean.changedCount -eq 2) ("clean paths pass (got {0})" -f $clean.state)
    $bad = Test-ChangedPathEnvelope -ChangedPath @('src/a.ps1', '.github/workflows/ci.yml') -Packet $null
    Assert-That ($bad.state -eq 'failed' -and -not $bad.ok) 'a workflow edit fails the envelope'
    Assert-That ($bad.summary -match [regex]::Escape('.github/workflows/ci.yml (.github/workflows/**)')) ("the failure names the path and the rule (got '{0}')" -f $bad.summary)
    $unproven = Test-ChangedPathEnvelope -ChangedPath $null -Packet $null
    Assert-That ($unproven.state -eq 'unproven' -and -not $unproven.ok) 'unread paths are unproven, never passed'
    $empty = Test-ChangedPathEnvelope -ChangedPath @() -Packet $null
    Assert-That ($empty.state -eq 'passed' -and $empty.changedCount -eq 0) 'an empty change list was read and passes; it is not unproven'
    $proposal = Test-ChangedPathEnvelope -ChangedPath @('src/a.ps1', '.github/workflows-proposed/ci.yml') -Packet $null
    Assert-That ($proposal.state -eq 'passed' -and @($proposal.proposedWorkflows).Count -eq 1) 'a proposed workflow passes and is listed'
    Assert-That (@($proposal.proposedWorkflows)[0].state -eq 'waiting-for-owner' -and $proposal.summary -match 'waiting for the owner') ("the proposal is named as waiting for the owner (got '{0}')" -f $proposal.summary)
    $packetForbids = [pscustomobject]@{ scope = [pscustomobject]@{ forbiddenPaths = @('secrets/**') } }
    $secret = Test-ChangedPathEnvelope -ChangedPath @('secrets/key.txt') -Packet $packetForbids
    Assert-That ($secret.state -eq 'failed') "the packet's own forbidden paths bind on the cloud road too"
    $noProposals = Find-ProposedWorkflowChange -ChangedPath @('src/a.ps1')
    Assert-That ($null -ne $noProposals -and $noProposals.Count -eq 0) 'no proposals yields an empty array, not $null'

    # --- The host's road: Invoke-AgentRunRefresh ---
    $ws = Join-Path $tempRoot 'ws'
    $null = New-Item -ItemType Directory -Path $ws -Force
    $now = (Get-Date).ToUniversalTime()
    $newPr = {
        param([int]$Number, [string]$Sha, [string]$Title)
        [pscustomobject]@{
            number = $Number; html_url = "https://github.com/owner/envelope/pull/$Number"
            state = 'open'; draft = $false; title = $Title; body = ''
            created_at = $now.AddMinutes(2).ToString('o'); updated_at = $now.AddMinutes(3).ToString('o')
            merged_at = $null; closed_at = $null
            head = [pscustomobject]@{ ref = "copilot/envelope-$Number"; sha = $Sha }
        }
    }
    $green = { param([string]$Sha) [pscustomobject]@{ status = 'completed'; conclusion = 'success'; name = 'CI'; runUrl = 'https://x/1'; headSha = $Sha } }
    $newRun = { param([string]$Name, [string]$Task) New-AgentRunRecord -WorkspaceRoot $ws -RepoName $Name -GitHubRepo "owner/$Name" -SelectedTaskText $Task }

    # Clean files: delivered and verified exactly as before D-012.
    $okRun = & $newRun 'envelope-ok' 'Clean cloud change envelope check'
    $okPr = & $newPr 101 'aaa' 'Clean cloud change envelope check'
    $ok = Invoke-AgentRunRefresh -WorkspaceRoot $ws -RunId $okRun.runId -PullRequests @($okPr) -ActionsRun (& $green 'aaa') -PullRequestFiles @{ 101 = @('src/a.ps1') }
    Assert-That ($ok.run.status -eq 'completed' -and $ok.run.outcome -eq 'awaiting-merge') ("a clean PR is recorded as delivered (got {0}/{1})" -f $ok.run.status, $ok.run.outcome)
    Assert-That ($ok.envelopeState -eq 'passed' -and $ok.run.permissionEnvelope.state -eq 'passed') 'the clean verdict is on the record'
    Assert-That ([string]$ok.run.verifiedHeadSha -eq 'aaa') 'a clean PR with green CI on its head is verified'

    # Same head, no files this time: the decided verdict is reused, not re-fetched.
    $okAgain = Invoke-AgentRunRefresh -WorkspaceRoot $ws -RunId $okRun.runId -PullRequests @($okPr) -ActionsRun (& $green 'aaa')
    Assert-That ($okAgain.envelopeState -eq 'passed' -and [string]$okAgain.run.verifiedHeadSha -eq 'aaa') 'a verdict for the same head is reused when no files are passed'
    # A new head with no files is unproven again: a head is what was checked.
    $okPr.head = [pscustomobject]@{ ref = 'copilot/envelope-101'; sha = 'bbb' }
    $okMoved = Invoke-AgentRunRefresh -WorkspaceRoot $ws -RunId $okRun.runId -PullRequests @($okPr) -ActionsRun (& $green 'bbb')
    Assert-That ($okMoved.envelopeState -eq 'unproven' -and $null -eq $okMoved.run.verifiedHeadSha) 'a moved head with unread files is unproven and not verified, even with green CI on it'

    # A forbidden file: failed, not delivered, not verified, one event.
    $badRun = & $newRun 'envelope-bad' 'Cloud agent edits the CI workflow'
    $badPr = & $newPr 102 'ccc' 'Cloud agent edits the CI workflow'
    $badFiles = @{ 102 = @('src/a.ps1', '.github/workflows/ci.yml') }
    $b1 = Invoke-AgentRunRefresh -WorkspaceRoot $ws -RunId $badRun.runId -PullRequests @($badPr) -ActionsRun (& $green 'ccc') -PullRequestFiles $badFiles
    Assert-That ($b1.run.status -eq 'failed' -and $b1.run.outcome -eq 'envelope-violation') ("a forbidden path fails the run (got {0}/{1})" -f $b1.run.status, $b1.run.outcome)
    Assert-That ($null -eq $b1.run.verifiedHeadSha -and $null -eq $b1.run.readyForOperatorAt) 'green CI never verifies a head that breaks the envelope'
    Assert-That (@($b1.run.permissionEnvelope.violations).Count -eq 1 -and [string]@($b1.run.permissionEnvelope.violations)[0].path -eq '.github/workflows/ci.yml') 'the record names the forbidden path'
    $b2 = Invoke-AgentRunRefresh -WorkspaceRoot $ws -RunId $badRun.runId -PullRequests @($badPr) -ActionsRun (& $green 'ccc') -PullRequestFiles $badFiles
    $badPr.merged_at = $now.AddMinutes(30).ToString('o')
    $b3 = Invoke-AgentRunRefresh -WorkspaceRoot $ws -RunId $badRun.runId -PullRequests @($badPr)
    Assert-That ($b3.run.status -eq 'failed' -and $b3.run.outcome -eq 'envelope-violation') ("a merged PR that broke the envelope is still not recorded as delivered (got {0}/{1})" -f $b3.run.status, $b3.run.outcome)
    Assert-That ($b3.run.prState -eq 'merged') 'the merge itself is still recorded'
    $badEvents = @((Get-AgentRunDetail -WorkspaceRoot $ws -RunId $badRun.runId).events | Where-Object { [string]$_.eventType -eq 'run.envelope-violation' })
    Assert-That ($badEvents.Count -eq 1) ("one violation is one event, not one per refresh (got {0})" -f $badEvents.Count)
    if ($badEvents.Count -ge 1) {
        Assert-That ([string]$badEvents[0].data.headSha -eq 'ccc') 'the event names the head that broke the envelope'
    }
    $null = $b2

    # Files not read: an open, ready PR is not recorded as delivered.
    $unRun = & $newRun 'envelope-unread' 'Cloud change whose files were not read'
    $unPr = & $newPr 103 'ddd' 'Cloud change whose files were not read'
    $u1 = Invoke-AgentRunRefresh -WorkspaceRoot $ws -RunId $unRun.runId -PullRequests @($unPr) -ActionsRun (& $green 'ddd')
    Assert-That ($u1.envelopeState -eq 'unproven') 'no files means unproven'
    Assert-That ($u1.run.status -ne 'completed') ("an unproven ready PR is not completed (got {0})" -f $u1.run.status)
    Assert-That ($null -eq $u1.run.verifiedHeadSha) 'an unproven head is not verified'
    $unPr.merged_at = $now.AddMinutes(30).ToString('o')
    $u2 = Invoke-AgentRunRefresh -WorkspaceRoot $ws -RunId $unRun.runId -PullRequests @($unPr)
    Assert-That ($u2.run.status -ne 'completed' -and $u2.run.outcome -ne 'merged') ("a merged but unproven PR is not recorded as merged work (got {0}/{1})" -f $u2.run.status, $u2.run.outcome)
    # The next refresh that can read the files decides it.
    $u3 = Invoke-AgentRunRefresh -WorkspaceRoot $ws -RunId $unRun.runId -PullRequests @($unPr) -PullRequestFiles @{ '103' = @('docs/x.md') }
    Assert-That ($u3.run.status -eq 'completed' -and $u3.run.outcome -eq 'merged') ("a string PR-number key is found, and reading the files decides it (got {0}/{1})" -f $u3.run.status, $u3.run.outcome)

    # A proposed workflow: delivered, and the proposal is named on the record.
    $propRun = & $newRun 'envelope-proposal' 'Cloud change proposing a workflow'
    $propPr = & $newPr 104 'eee' 'Cloud change proposing a workflow'
    $p1 = Invoke-AgentRunRefresh -WorkspaceRoot $ws -RunId $propRun.runId -PullRequests @($propPr) -PullRequestFiles @{ 104 = @('.github/workflows-proposed/ci.yml', 'src/a.ps1') }
    Assert-That ($p1.run.status -eq 'completed' -and @($p1.run.permissionEnvelope.proposedWorkflows).Count -eq 1) 'a proposed workflow does not block delivery and is on the record'
    $propEvents = @((Get-AgentRunDetail -WorkspaceRoot $ws -RunId $propRun.runId).events | Where-Object { [string]$_.summary -match 'workflow proposal\(s\) waiting for the owner' })
    Assert-That ($propEvents.Count -ge 1) 'the refresh summary says a workflow proposal is waiting for the owner'

    # The packet's own forbidden path binds on this road.
    $pkRun = & $newRun 'envelope-packet' 'Cloud change touching packet secrets'
    $pkPr = & $newPr 105 'fff' 'Cloud change touching packet secrets'
    $pk = Invoke-AgentRunRefresh -WorkspaceRoot $ws -RunId $pkRun.runId -PullRequests @($pkPr) -PullRequestFiles @{ 105 = @('secrets/key.txt') } -Packet $packetForbids
    Assert-That ($pk.run.status -eq 'failed' -and $pk.run.outcome -eq 'envelope-violation') "the run's packet forbidden paths fail a cloud PR"

    # --- Host wiring, from the AST ---
    $tokens = $null; $parseErrors = $null
    $hostAst = [System.Management.Automation.Language.Parser]::ParseFile($hostPath, [ref]$tokens, [ref]$parseErrors)
    Assert-That (@($parseErrors).Count -eq 0) ("the host parses ({0} error(s))" -f @($parseErrors).Count)
    $refreshCalls = @($hostAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Invoke-AgentRunRefresh' }, $true))
    Assert-That ($refreshCalls.Count -ge 2) ("the host refreshes agent runs on both roads (found {0})" -f $refreshCalls.Count)
    foreach ($call in $refreshCalls) {
        $params = @($call.CommandElements | Where-Object { $_ -is [System.Management.Automation.Language.CommandParameterAst] } | ForEach-Object { $_.ParameterName })
        Assert-That ($params -contains 'PullRequestFiles' -and $params -contains 'Packet') ("host line {0}: Invoke-AgentRunRefresh passes -PullRequestFiles and -Packet" -f $call.Extent.StartLineNumber)
    }
    $fetchFn = $hostAst.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-PullRequestChangedPathViaApi' }, $true)
    Assert-That ($null -ne $fetchFn) 'the host can fetch a pull request''s changed paths'
    if ($null -ne $fetchFn) {
        $fetchText = $fetchFn.Extent.Text
        Assert-That ($fetchText -match 'previous_filename') 'a rename counts its old path, so moving a workflow away is seen'
        Assert-That ($fetchText -match 'return \$null') 'a failed or capped fetch returns $null (unproven), not an empty pass'
    }
    $inputFn = $hostAst.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-AgentRunEnvelopeInput' }, $true)
    Assert-That ($null -ne $inputFn -and $inputFn.Extent.Text -match 'Read-WorkPacket') 'the host reads the run''s WorkPacket for its forbidden paths'

    # --- The runner's road ---
    $fixtureRoot = Join-Path $tempRoot 'git'
    $null = New-Item -ItemType Directory -Path (Join-Path $fixtureRoot '.github/workflows') -Force
    $gitIn = {
        param([string[]]$GitArgs)
        $out = & git -C $fixtureRoot -c user.name=fixture -c user.email=fixture@example.invalid -c commit.gpgsign=false @GitArgs 2>&1
        if ($LASTEXITCODE -ne 0) { throw ("git {0} failed: {1}" -f ($GitArgs -join ' '), ($out -join ' ')) }
        return $out
    }
    Set-Content -LiteralPath (Join-Path $fixtureRoot 'README.md') -Value 'fixture' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $fixtureRoot '.github/workflows/ci.yml') -Value 'name: ci' -Encoding UTF8
    $null = & $gitIn @('init', '--quiet', '--initial-branch=main')
    $null = & $gitIn @('add', '-A')
    $null = & $gitIn @('commit', '--quiet', '-m', 'base')
    $base = ((& $gitIn @('rev-parse', 'HEAD')) | Out-String).Trim()
    $null = & $gitIn @('switch', '--quiet', '-c', 'roadmap/run')
    $null = New-Item -ItemType Directory -Path (Join-Path $fixtureRoot '.github/workflows-proposed') -Force
    Set-Content -LiteralPath (Join-Path $fixtureRoot '.github/workflows-proposed/ci.yml') -Value 'name: proposed' -Encoding UTF8
    $null = & $gitIn @('add', '-A')
    $null = & $gitIn @('commit', '--quiet', '-m', 'propose a workflow')
    $local = Test-RunPermissionEnvelope -RepoPath $fixtureRoot -BaseCommit $base -Packet $null
    Assert-That ($local.ok -and @($local.proposedWorkflows).Count -eq 1) ("the runner passes a proposal and lists it (ok={0}, error={1})" -f $local.ok, $local.error)
    Assert-That ($local.summary -match 'waiting for the owner') ("the runner's summary names the waiting proposal (got '{0}')" -f $local.summary)

    $runnerAst = [System.Management.Automation.Language.Parser]::ParseFile($runnerPath, [ref]$tokens, [ref]$parseErrors)
    $queued = $runnerAst.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Invoke-QueuedTask' }, $true)
    $summaryKeys = @()
    if ($null -ne $queued) {
        $summaryKeys = @($queued.FindAll({
                    param($n)
                    $n -is [System.Management.Automation.Language.HashtableAst] -and
                    @($n.KeyValuePairs | Where-Object { $_.Item1.Extent.Text -eq 'proposedWorkflows' }).Count -gt 0
                }, $true))
    }
    Assert-That ($summaryKeys.Count -ge 2) ("both runner summaries (failed and finished) carry proposedWorkflows (found {0})" -f $summaryKeys.Count)

    # --- The network allowlist ---
    $perm = { param([hashtable]$P) New-WorkPacket -TaskId 'net-1' -Repository 'owner/r' -BaseBranch 'main' -BaseSha '' -Objective 'o' -Permissions $P }
    $base4 = @{ filesystemWrite = $true; shell = $true; githubWrite = $false }

    $noHosts = & $perm ($base4 + @{ network = $true })
    $v1 = Test-WorkPacket -Packet $noHosts
    Assert-That (-not $v1.valid -and (@($v1.errors) -join ';') -match 'names no hosts') 'network true with no allowlist is an invalid packet'
    $hostsNoNet = & $perm ($base4 + @{ network = $false; networkAllowlist = @('api.nuget.org') })
    $v2 = Test-WorkPacket -Packet $hostsNoNet
    Assert-That (-not $v2.valid -and (@($v2.errors) -join ';') -match 'network is false') 'an allowlist with network false is invalid, not silently ignored'
    $wildcard = & $perm ($base4 + @{ network = $true; networkAllowlist = @('*.example.com') })
    $v3 = Test-WorkPacket -Packet $wildcard
    Assert-That (-not $v3.valid -and (@($v3.errors) -join ';') -match 'not a host name') 'a wildcard entry is not a host'
    $plain = & $perm ($base4 + @{ network = $false })
    Assert-That ((Test-WorkPacket -Packet $plain).valid) '(control) network false with no allowlist is valid'
    Assert-That (-not $plain.permissions.Contains('networkAllowlist')) 'a packet that does not ask for the network gains no allowlist field'

    foreach ($case in @(
            @{ h = 'api.nuget.org'; e = $true }, @{ h = 'registry.npmjs.org'; e = $true }, @{ h = 'localhost'; e = $false },
            @{ h = 'https://api.nuget.org'; e = $false }, @{ h = 'api.nuget.org:443'; e = $false }, @{ h = '*.nuget.org'; e = $false },
            @{ h = 'api.nuget.org/v3'; e = $false }, @{ h = ''; e = $false })) {
        Assert-That ((Test-NetworkAllowlistHost -HostName $case.h) -eq $case.e) ("host '{0}' should be {1}" -f $case.h, $case.e)
    }
    Assert-That ((Get-NetworkAllowlistFingerprint -Allowlist @('B.org', 'a.org', 'a.org')) -eq (Get-NetworkAllowlistFingerprint -Allowlist @('a.org', 'b.org'))) 'the fingerprint ignores order, case and duplicates'
    Assert-That ((Get-NetworkAllowlistFingerprint -Allowlist @('a.org')) -ne (Get-NetworkAllowlistFingerprint -Allowlist @('a.org', 'b.org'))) 'adding a host changes the fingerprint'
    $threw = $false; try { $null = New-NetworkAllowlistApproval -Allowlist @('https://x.org') -ApprovedBy 'owner' } catch { $threw = $true }
    Assert-That $threw 'an approval refuses a non-host entry'

    $denied = Resolve-PacketNetworkAccess -Packet $plain
    Assert-That (-not $denied.granted -and $denied.state -eq 'denied') 'network false is denied'
    $askOnly = & $perm ($base4 + @{ network = $true; networkAllowlist = @('api.nuget.org') })
    $awaiting = Resolve-PacketNetworkAccess -Packet $askOnly
    Assert-That (-not $awaiting.granted -and $awaiting.state -eq 'awaiting-owner-approval') 'an unapproved allowlist waits for the owner'
    $approval = New-NetworkAllowlistApproval -Allowlist @('api.nuget.org') -ApprovedBy 'owner'
    $approvedPacket = & $perm ($base4 + @{ network = $true; networkAllowlist = @('api.nuget.org'); networkApproval = $approval })
    $approved = Resolve-PacketNetworkAccess -Packet $approvedPacket
    Assert-That ($approved.granted -and $approved.state -eq 'approved') 'an approved allowlist is granted'
    $roundTrip = ($approvedPacket | ConvertTo-Json -Depth 10) | ConvertFrom-Json
    Assert-That ((Resolve-PacketNetworkAccess -Packet $roundTrip).granted) 'the approval survives a save and read (JSON round trip)'
    $grown = & $perm ($base4 + @{ network = $true; networkAllowlist = @('api.nuget.org', 'evil.example.com'); networkApproval = $approval })
    $stale = Resolve-PacketNetworkAccess -Packet $grown
    Assert-That (-not $stale.granted -and $stale.state -eq 'approval-stale') 'a host added after approval makes the approval stale, not covered'

    # --- What each state gives a Claude session ---
    $sDenied = ConvertTo-ClaudePermissionSetting -Packet $plain
    Assert-That (@($sDenied.permissions.deny) -contains 'WebFetch' -and @($sDenied.permissions.deny) -contains 'WebSearch') 'denied: WebFetch and WebSearch are denied'
    $sAwait = ConvertTo-ClaudePermissionSetting -Packet $askOnly
    Assert-That (@($sAwait.permissions.deny) -contains 'WebFetch' -and @($sAwait.permissions.allow | Where-Object { $_ -like 'WebFetch*' }).Count -eq 0) 'awaiting approval: network true alone is not loosened'
    $sStale = ConvertTo-ClaudePermissionSetting -Packet $grown
    Assert-That (@($sStale.permissions.deny) -contains 'WebFetch') 'stale approval: denied'
    $sOk = ConvertTo-ClaudePermissionSetting -Packet $approvedPacket
    Assert-That (@($sOk.permissions.allow) -contains 'WebFetch(domain:api.nuget.org)') 'approved: WebFetch is allowed for the approved host'
    Assert-That (@($sOk.permissions.allow | Where-Object { $_ -like 'WebFetch*' }).Count -eq 1) 'approved: no host beyond the list is allowed'
    Assert-That (@($sOk.permissions.deny) -notcontains 'WebFetch') 'approved: WebFetch is not blanket-denied (a deny would beat the per-host allow)'
    Assert-That (@($sOk.permissions.deny) -contains 'WebSearch') 'approved: WebSearch stays denied'
    foreach ($settings in @($sDenied, $sOk)) {
        Assert-That (@($settings.permissions.deny) -contains 'Bash(curl:*)' -and @($settings.permissions.deny) -contains 'PowerShell(Invoke-WebRequest:*)') 'shell fetchers are denied whether or not the network is granted'
    }

    # --- The owner's approval command ---
    $toolWs = Join-Path $tempRoot 'tool-ws'
    $null = New-Item -ItemType Directory -Path $toolWs -Force
    $toolPacket = New-WorkPacket -TaskId 'net-approve-1' -Repository 'owner/r' -BaseBranch 'main' -BaseSha '' -Objective 'o' -Permissions ($base4 + @{ network = $true; networkAllowlist = @('api.nuget.org') })
    $null = Save-WorkPacket -WorkspaceRoot $toolWs -Packet $toolPacket
    $null = & $approvePath -TaskId 'net-approve-1' -ApprovedBy 'owner' -WorkspaceRoot $toolWs -WhatIf
    $afterWhatIf = Read-WorkPacket -WorkspaceRoot $toolWs -TaskId 'net-approve-1'
    Assert-That ((Resolve-PacketNetworkAccess -Packet $afterWhatIf).state -eq 'awaiting-owner-approval') '-WhatIf writes nothing'
    $toolResult = & $approvePath -TaskId 'net-approve-1' -ApprovedBy 'owner' -WorkspaceRoot $toolWs -Confirm:$false
    $afterApprove = Read-WorkPacket -WorkspaceRoot $toolWs -TaskId 'net-approve-1'
    Assert-That ($null -ne $toolResult -and $toolResult.state -eq 'approved') 'the command reports the approved state'
    Assert-That ((Resolve-PacketNetworkAccess -Packet $afterApprove).granted) 'the saved packet is granted after approval'
    Assert-That ((Test-WorkPacket -Packet $afterApprove).valid) 'the approved packet is still a valid packet'
    $plainPacket = New-WorkPacket -TaskId 'net-approve-2' -Repository 'owner/r' -BaseBranch 'main' -BaseSha '' -Objective 'o' -Permissions ($base4 + @{ network = $false })
    $null = Save-WorkPacket -WorkspaceRoot $toolWs -Packet $plainPacket
    $refused = $false
    try { $null = & $approvePath -TaskId 'net-approve-2' -ApprovedBy 'owner' -WorkspaceRoot $toolWs -Confirm:$false } catch { $refused = $true }
    Assert-That $refused 'the command refuses a packet that does not ask for the network'
}
finally {
    $env:REPO_MGMT_OUTPUT_ROOT = $savedOutputRoot
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ("Envelope cloud and network: {0} passed, {1} failed" -f $passed, $failures.Count)
foreach ($f in $failures) { Write-Host "  FAIL: $f" }
if ($failures.Count -gt 0 -and $FailOnError) { exit 1 }
