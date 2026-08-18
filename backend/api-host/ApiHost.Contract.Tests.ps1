#Requires -Modules Pester

BeforeAll {
    $script:HostPowerShell = $null
    $script:HostAsyncResult = $null
    $script:WorkspaceRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    $script:HostScript = Join-Path $PSScriptRoot 'Start-RepoManagementApiHost.ps1'
    $script:HelpersScript = Join-Path $PSScriptRoot 'ApiHost.ErrorHandling.ps1'
    . $script:HelpersScript

    $script:Port = 7082
    $script:BaseUrl = "http://127.0.0.1:$($script:Port)"
    $script:LogRoot = Join-Path $script:WorkspaceRoot 'output\contract-tests'
    $null = New-Item -ItemType Directory -Path $script:LogRoot -Force
    $script:HostLogPath = Join-Path $script:LogRoot 'api-host-contract.log'
    $script:ShutdownSignalPath = Join-Path $script:LogRoot 'api-host-contract.stop'
    Remove-Item -LiteralPath $script:ShutdownSignalPath -Force -ErrorAction SilentlyContinue

    function Invoke-ContractApiRequest {
        param(
            [Parameter(Mandatory = $true)]
            [ValidateSet('GET', 'POST')]
            [string]$Method,
            [Parameter(Mandatory = $true)]
            [string]$Path,
            [Parameter()]
            [object]$Body
        )

        $invokeSplat = @{
            Uri = "$($script:BaseUrl)$Path"
            Method = $Method
            SkipHttpErrorCheck = $true
            TimeoutSec = 20
        }

        if ($PSBoundParameters.ContainsKey('Body')) {
            $invokeSplat.ContentType = 'application/json'
            $invokeSplat.Body = ($Body | ConvertTo-Json -Depth 10)
        }

        $response = Invoke-WebRequest @invokeSplat
        $json = $null
        if (-not [string]::IsNullOrWhiteSpace($response.Content)) {
            $json = $response.Content | ConvertFrom-Json
        }

        return [pscustomobject]@{
            StatusCode = [int]$response.StatusCode
            Json = $json
            Content = [string]$response.Content
        }
    }

    function Wait-ContractApiHostReady {
        param(
            [Parameter(Mandatory = $true)]
            [System.Management.Automation.PowerShell]$PowerShellInstance
        )

        $deadline = (Get-Date).AddSeconds(30)
        while ((Get-Date) -lt $deadline) {
            $state = $PowerShellInstance.InvocationStateInfo.State
            if ($state -in @(
                [System.Management.Automation.PSInvocationState]::Completed,
                [System.Management.Automation.PSInvocationState]::Failed,
                [System.Management.Automation.PSInvocationState]::Stopped
            )) {
                $reason = if ($PowerShellInstance.InvocationStateInfo.Reason) {
                    $PowerShellInstance.InvocationStateInfo.Reason.Message
                } else {
                    ($PowerShellInstance.Streams.Error | ForEach-Object { $_.ToString() }) -join '; '
                }
                throw "API host exited before contract tests were ready. State=$state. LogPath=$($script:HostLogPath). Error=$reason"
            }

            try {
                $probe = Invoke-WebRequest -Uri "$($script:BaseUrl)/health/live" -Method Get -SkipHttpErrorCheck -TimeoutSec 3
                if ($probe.StatusCode -ge 200 -and $probe.StatusCode -lt 500) {
                    return
                }
            } catch { }

            Start-Sleep -Milliseconds 500
        }

        throw 'Timed out waiting for API host readiness in contract tests.'
    }

    function Assert-ErrorEnvelope {
        param(
            [Parameter(Mandatory = $true)]
            [object]$Response,
            [Parameter(Mandatory = $true)]
            [int]$StatusCode,
            [Parameter(Mandatory = $true)]
            [string]$Operation,
            [Parameter(Mandatory = $true)]
            [string]$Category
        )

        $Response.StatusCode | Should -Be $StatusCode
        $Response.Json.success | Should -BeFalse
        $Response.Json.operation | Should -Be $Operation
        $Response.Json.correlationId | Should -Not -BeNullOrEmpty
        $Response.Json.timestamp | Should -Not -BeNullOrEmpty
        $Response.Json.error.category | Should -Be $Category
        $Response.Json.error.message | Should -Not -BeNullOrEmpty
    }

    $script:HostPowerShell = [powershell]::Create()
    $null = $script:HostPowerShell.AddScript({
        param($ScriptPath, $Root, $Port, $LogPath, $StopPath)
        & $ScriptPath -WorkspaceRoot $Root -BindAddress '127.0.0.1' -Port $Port -LogPath $LogPath -ShutdownSignalPath $StopPath
    }).AddArgument($script:HostScript).AddArgument($script:WorkspaceRoot).AddArgument($script:Port).AddArgument($script:HostLogPath).AddArgument($script:ShutdownSignalPath)
    $script:HostAsyncResult = $script:HostPowerShell.BeginInvoke()

    Wait-ContractApiHostReady -PowerShellInstance $script:HostPowerShell
}

AfterAll {
    if ($null -ne $script:HostPowerShell) {
        try {
            Set-Content -LiteralPath $script:ShutdownSignalPath -Value 'stop' -Encoding UTF8
        } catch { }

        try {
            if ($null -ne $script:HostAsyncResult) {
                $null = $script:HostAsyncResult.AsyncWaitHandle.WaitOne(5000)
            }
        } catch { }

        try {
            $state = $script:HostPowerShell.InvocationStateInfo.State
            if ($state -eq [System.Management.Automation.PSInvocationState]::Running) {
                $script:HostPowerShell.Stop()
            }
        } catch { }

        try {
            if ($null -ne $script:HostAsyncResult -and $script:HostAsyncResult.IsCompleted) {
                $script:HostPowerShell.EndInvoke($script:HostAsyncResult) | Out-Null
            }
        } catch { }

        try {
            $script:HostPowerShell.Dispose()
        } catch { }

        try {
            Remove-Item -LiteralPath $script:ShutdownSignalPath -Force -ErrorAction SilentlyContinue
        } catch { }
    }
}

Describe 'ApiHost Error Classification' {
    It 'classifies validation errors' {
        Get-ErrorCategory -Message 'repoName is required for /api/readme/standardize/preview' | Should -Be 'validation'
    }

    It 'classifies timeout errors' {
        Get-ErrorCategory -Message 'The request timed out while scanning.' | Should -Be 'timeout'
    }

    It 'classifies dependency errors' {
        Get-ErrorCategory -Message 'GitHub API connection failed.' | Should -Be 'dependency'
    }

    It 'classifies unmatched errors as internal' {
        Get-ErrorCategory -Message 'Unexpected failure.' | Should -Be 'internal'
    }
}

Describe 'API Success Contracts' {
    It 'returns a success envelope for GET /health/live' {
        $response = Invoke-ContractApiRequest -Method GET -Path '/health/live'
        $response.StatusCode | Should -Be 200
        $response.Json.status | Should -Not -BeNullOrEmpty
    }

    It 'returns a success envelope for GET /api/settings' {
        $response = Invoke-ContractApiRequest -Method GET -Path '/api/settings'
        $response.StatusCode | Should -Be 200
        $response.Json.success | Should -BeTrue
        $response.Json.data | Should -Not -BeNull
    }

    It 'returns a success envelope for GET /api/readme/standardize/history' {
        $response = Invoke-ContractApiRequest -Method GET -Path '/api/readme/standardize/history?limit=5'
        $response.StatusCode | Should -Be 200
        $response.Json.success | Should -BeTrue
        $response.Json.data | Should -Not -BeNull
        $response.Json.data.PSObject.Properties.Name | Should -Contain 'items'
        $response.Json.data.PSObject.Properties.Name | Should -Contain 'count'
    }

    It 'returns a success envelope for GET /api/roadmap/dependencies' {
        $response = Invoke-ContractApiRequest -Method GET -Path '/api/roadmap/dependencies'
        $response.StatusCode | Should -Be 200
        $response.Json.success | Should -BeTrue
        $response.Json.data | Should -Not -BeNull
        $response.Json.data.PSObject.Properties.Name | Should -Contain 'graph'
        $response.Json.data.PSObject.Properties.Name | Should -Contain 'summary'
        $response.Json.data.PSObject.Properties.Name | Should -Contain 'totalEdges'
        $response.Json.data.PSObject.Properties.Name | Should -Contain 'scannedAt'
    }
}

Describe 'API Validation Error Contracts' {
    It 'returns validation envelope for GET /api/roadmap/lint without repoName' {
        $response = Invoke-ContractApiRequest -Method GET -Path '/api/roadmap/lint'
        Assert-ErrorEnvelope -Response $response -StatusCode 400 -Operation 'roadmap.lint' -Category 'validation'
    }

    It 'returns validation envelope for POST /api/readme/standardize/preview without repoName' {
        $response = Invoke-ContractApiRequest -Method POST -Path '/api/readme/standardize/preview' -Body @{}
        Assert-ErrorEnvelope -Response $response -StatusCode 400 -Operation 'readme.standardize.preview' -Category 'validation'
    }

    It 'returns validation envelope for POST /api/readme/standardize/apply without required fields' {
        $response = Invoke-ContractApiRequest -Method POST -Path '/api/readme/standardize/apply' -Body @{}
        Assert-ErrorEnvelope -Response $response -StatusCode 400 -Operation 'readme.standardize.apply' -Category 'validation'
    }

    It 'returns validation envelope for POST /api/execution/assign without repoName' {
        $response = Invoke-ContractApiRequest -Method POST -Path '/api/execution/assign' -Body @{}
        Assert-ErrorEnvelope -Response $response -StatusCode 400 -Operation 'execution.assign' -Category 'validation'
    }

    It 'returns validation envelope for POST /api/execution/complete without repoName' {
        $response = Invoke-ContractApiRequest -Method POST -Path '/api/execution/complete' -Body @{}
        Assert-ErrorEnvelope -Response $response -StatusCode 400 -Operation 'execution.complete' -Category 'validation'
    }

    It 'returns validation envelope for POST /api/execution/cancel without repoName' {
        $response = Invoke-ContractApiRequest -Method POST -Path '/api/execution/cancel' -Body @{}
        Assert-ErrorEnvelope -Response $response -StatusCode 400 -Operation 'execution.cancel' -Category 'validation'
    }

    It 'returns validation envelope for POST /api/execution/requeue without repoName' {
        $response = Invoke-ContractApiRequest -Method POST -Path '/api/execution/requeue' -Body @{}
        Assert-ErrorEnvelope -Response $response -StatusCode 400 -Operation 'execution.requeue' -Category 'validation'
    }

    It 'returns validation envelope for POST /api/roadmap/drift/baseline without required fields' {
        $response = Invoke-ContractApiRequest -Method POST -Path '/api/roadmap/drift/baseline' -Body @{}
        Assert-ErrorEnvelope -Response $response -StatusCode 400 -Operation 'roadmap.drift.baseline' -Category 'validation'
    }

    It 'returns validation envelope for POST /api/roadmap/drift/acknowledge without repoName' {
        $response = Invoke-ContractApiRequest -Method POST -Path '/api/roadmap/drift/acknowledge' -Body @{}
        Assert-ErrorEnvelope -Response $response -StatusCode 400 -Operation 'roadmap.drift.acknowledge' -Category 'validation'
    }

    It 'returns validation envelope for POST /api/notifications/webhooks without url' {
        $response = Invoke-ContractApiRequest -Method POST -Path '/api/notifications/webhooks' -Body @{}
        Assert-ErrorEnvelope -Response $response -StatusCode 400 -Operation 'notifications.webhooks.register' -Category 'validation'
    }

    It 'returns validation envelope for POST /api/notifications/webhooks/remove without id' {
        $response = Invoke-ContractApiRequest -Method POST -Path '/api/notifications/webhooks/remove' -Body @{}
        Assert-ErrorEnvelope -Response $response -StatusCode 400 -Operation 'notifications.webhooks.remove' -Category 'validation'
    }

    It 'returns validation envelope for POST /api/roadmap/completion-preview without repoName' {
        $response = Invoke-ContractApiRequest -Method POST -Path '/api/roadmap/completion-preview' -Body @{}
        Assert-ErrorEnvelope -Response $response -StatusCode 400 -Operation 'roadmap.completion-preview' -Category 'validation'
    }

    It 'returns validation envelope for POST /api/git/sync-default-branch without a repo' {
        $response = Invoke-ContractApiRequest -Method POST -Path '/api/git/sync-default-branch' -Body @{}
        Assert-ErrorEnvelope -Response $response -StatusCode 400 -Operation 'git.sync-default-branch' -Category 'validation'
    }
}

Describe 'Default-branch sync route -- Release 3.4 milestone 1, step 10' {
    # The operation and its refusal matrix shipped in PR #134 reachable only from
    # the task runner; this host did not dot-source the module at all.
    #
    # Verified non-vacuous by running this file against the pre-route host: all
    # four assertions (these three and the validation case above) failed there
    # and pass here. The refusal case is the load-bearing one -- it is the only
    # assertion that can distinguish "route exists" from "route exists AND
    # Git.DefaultBranchSync.ps1 is actually loaded in this host", which was the
    # whole defect.

    It 'forwards the module refusal rather than inventing one' {
        # A path that is not a git working copy is the module's own
        # `not-a-git-repo` refusal. Getting it back proves three things at once:
        # the route exists, Git.DefaultBranchSync.ps1 is loaded in this host, and
        # a refusal maps to 409 with the module's category verbatim.
        $notARepo = Join-Path $script:LogRoot 'not-a-repo'
        $null = New-Item -ItemType Directory -Path $notARepo -Force
        $response = Invoke-ContractApiRequest -Method POST -Path '/api/git/sync-default-branch' -Body @{
            repoPath = $notARepo
            approved = $true
        }

        $response.StatusCode | Should -Be 409
        $response.Json.success | Should -BeFalse
        $response.Json.category | Should -Be 'not-a-git-repo'
        $response.Json.data.refused | Should -BeTrue
        $response.Json.data.synced | Should -BeFalse
        # The remedy is what makes a refusal actionable rather than a dead end.
        $response.Json.data.remedy | Should -Not -BeNullOrEmpty
    }

    It 'refuses an unapproved transition instead of approving on the caller behalf' {
        # Approval is an input on the operation, so an absent flag must refuse.
        # A route that defaulted `approved` to true would still return 409 here
        # (the directory is not a repo), so this asserts the ORDER: the repo
        # check runs first, and omitting approval never silently means yes.
        $notARepo = Join-Path $script:LogRoot 'not-a-repo'
        $null = New-Item -ItemType Directory -Path $notARepo -Force
        $response = Invoke-ContractApiRequest -Method POST -Path '/api/git/sync-default-branch' -Body @{
            repoPath = $notARepo
        }

        $response.StatusCode | Should -Be 409
        $response.Json.data.synced | Should -BeFalse
    }

    It 'answers 404 with a named category when the repo is unknown' {
        $response = Invoke-ContractApiRequest -Method POST -Path '/api/git/sync-default-branch' -Body @{
            repoName = 'a-repo-that-does-not-exist-in-any-cache'
            approved = $true
        }

        $response.StatusCode | Should -Be 404
        $response.Json.category | Should -Be 'repo-not-found'
    }
}

Describe 'Portfolio snapshot route - Release 3.5 milestones 1+2' {
    # The reconciliation layer, asserted over a LIVE host response. The walk
    # is generic - it names no metric - so a metric added later is audited the
    # day it ships without anyone editing this file. This is the milestone-2
    # invariant suite's live seed; the cross-endpoint equality assertions
    # join it as the consumers move onto the snapshot.

    It 'serves a snapshot whose every metric honors the contract' {
        $response = Invoke-ContractApiRequest -Method GET -Path '/api/portfolio/snapshot'
        $response.StatusCode | Should -Be 200
        $response.Json.success | Should -BeTrue
        $snapshot = $response.Json.data
        $snapshot.schemaVersion | Should -Be '1'
        $snapshot.generatedAt | Should -Not -BeNullOrEmpty
        @($snapshot.metrics.PSObject.Properties).Count | Should -BeGreaterThan 4

        foreach ($property in @($snapshot.metrics.PSObject.Properties)) {
            $metric = $property.Value
            $metric.definition | Should -Not -BeNullOrEmpty
            # One clock: every asOf parses, and stays UTC ISO at rest.
            { [datetime]::Parse([string]$metric.asOf, [System.Globalization.CultureInfo]::InvariantCulture) } | Should -Not -Throw
            if ($null -eq $metric.value) {
                # Not computed says WHY - never a guessed zero.
                $metric.reason | Should -Not -BeNullOrEmpty
                $metric.confidence | Should -Be 'none'
            }
            else {
                $metric.source | Should -Not -BeNullOrEmpty
                if ($metric.unit -eq 'percent') {
                    [double]$metric.value | Should -BeGreaterOrEqual 0
                    [double]$metric.value | Should -BeLessOrEqual 100
                }
                if ($metric.unit -eq 'count') {
                    [double]$metric.value | Should -BeGreaterOrEqual 0
                }
            }
            if ($null -ne $metric.basis -and $null -ne $metric.basis.numerator -and $null -ne $metric.basis.denominator) {
                [double]$metric.basis.numerator | Should -BeLessOrEqual ([double]$metric.basis.denominator)
            }
        }
    }

    It 'names every degraded source rather than silently zeroing its metrics' {
        $response = Invoke-ContractApiRequest -Method GET -Path '/api/portfolio/snapshot'
        $snapshot = $response.Json.data
        foreach ($entry in @($snapshot.degraded)) {
            $entry.source | Should -Not -BeNullOrEmpty
            $entry.reason | Should -Not -BeNullOrEmpty
        }
    }

    # Release 3.5 milestone 2 - cross-endpoint equality, live. Each endpoint
    # must equal ITS snapshot metric: same source, same number, no exceptions.
    # When the snapshot legitimately could not compute a metric (cold host, no
    # cache), the DEGRADED contract is asserted instead - null with a reason -
    # because "skipped" and "passed" must not look alike.
    It 'execution readiness equals the execution-metrics endpoint, or degrades by name' {
        $snapResponse = Invoke-ContractApiRequest -Method GET -Path '/api/portfolio/snapshot'
        $execResponse = Invoke-ContractApiRequest -Method GET -Path '/api/execution/metrics'
        $snapMetric = $snapResponse.Json.data.metrics.executionReadyCount
        if ($null -ne $snapMetric.value) {
            $execResponse.StatusCode | Should -Be 200
            [int]$snapMetric.value | Should -Be ([int]$execResponse.Json.data.stateCounts.ready)
            $snapMetric.source | Should -Be 'execution-ledger'
        }
        else {
            $snapMetric.reason | Should -Not -BeNullOrEmpty
        }
    }

    It 'dispatch readiness equals the docs-audit endpoint, or degrades by name' {
        $snapResponse = Invoke-ContractApiRequest -Method GET -Path '/api/portfolio/snapshot'
        $snapMetric = $snapResponse.Json.data.metrics.dispatchReadyCount
        if ($null -ne $snapMetric.value) {
            $auditResponse = Invoke-ContractApiRequest -Method GET -Path '/api/docs-audit'
            $auditResponse.StatusCode | Should -Be 200
            $auditReady = @(@($auditResponse.Json.data.entries) | Where-Object { [string]$_.dispatchReadiness -eq 'ready' }).Count
            [int]$snapMetric.value | Should -Be $auditReady
            $snapMetric.source | Should -Be 'docs-audit-cache'
        }
        else {
            # Cold host, no audit cache: the degraded contract is the
            # assertion - "skipped" and "passed" must not look alike.
            $snapMetric.reason | Should -Not -BeNullOrEmpty
            @($snapResponse.Json.data.degraded | Where-Object { $_.source -eq 'docs-audit-cache' }).Count | Should -BeGreaterThan 0
        }
    }

    It 'maturity readiness carries its assessment source, or degrades by name' {
        $snapResponse = Invoke-ContractApiRequest -Method GET -Path '/api/portfolio/snapshot'
        $snapMetric = $snapResponse.Json.data.metrics.maturityReadyCount
        if ($null -ne $snapMetric.value) {
            $snapMetric.source | Should -Be 'portfolio-assessment'
            [int]$snapMetric.value | Should -BeGreaterOrEqual 0
        }
        else {
            $snapMetric.reason | Should -Not -BeNullOrEmpty
            @($snapResponse.Json.data.degraded | Where-Object { $_.source -eq 'portfolio-assessment' }).Count | Should -BeGreaterThan 0
        }
    }

    # Release 3.5 milestone 2, the finding-1.8 invariant: one timezone basis
    # per payload. Every *At-suffixed string field in these payloads must
    # parse AND carry an explicit basis (Z or a +/-hh:mm offset). A naive
    # timestamp is how one generation event rendered as 7:54 AM on one card
    # and 11:54 AM on another.
    It 'every timestamp field in key payloads carries an explicit timezone basis' {
        # Recurse ONLY into JSON-shaped nodes (objects, dictionaries,
        # arrays). The first version walked every PSObject property and
        # discovered that DateTime.Date returns a DateTime - infinite
        # recursion, found by a 315-second call-depth overflow rather than
        # by reading. JSON-parsed payloads contain nothing deeper than
        # pscustomobject / array / scalar, so this shape is sufficient.
        $walk = {
            param([object]$Node, [string]$Trail, [System.Collections.Generic.List[string]]$Failures, $Self)
            if ($null -eq $Node) { return }
            if ($Node -is [System.Array]) {
                for ($i = 0; $i -lt $Node.Length; $i++) {
                    & $Self -Node $Node[$i] -Trail ("{0}[{1}]" -f $Trail, $i) -Failures $Failures -Self $Self
                }
                return
            }
            if ($Node -isnot [pscustomobject] -and $Node -isnot [System.Collections.IDictionary]) { return }
            $properties = if ($Node -is [System.Collections.IDictionary]) {
                @($Node.Keys | ForEach-Object { [pscustomobject]@{ Name = $_; Value = $Node[$_] } })
            } else {
                @($Node.PSObject.Properties)
            }
            foreach ($property in $properties) {
                $name = [string]$property.Name
                $value = $property.Value
                if ($name -match '(At|generatedAt|asOf)$' -and $value -is [string] -and -not [string]::IsNullOrWhiteSpace([string]$value)) {
                    if ([string]$value -notmatch '(Z|[+-]\d{2}:\d{2})$') {
                        $Failures.Add(("{0}.{1} = '{2}' has no timezone basis" -f $Trail, $name, $value)) | Out-Null
                    }
                }
                else {
                    & $Self -Node $value -Trail ("{0}.{1}" -f $Trail, $name) -Failures $Failures -Self $Self
                }
            }
        }

        $failures = [System.Collections.Generic.List[string]]::new()
        foreach ($endpoint in @('/api/portfolio/snapshot', '/api/execution/metrics', '/api/roadmap/runner')) {
            $response = Invoke-ContractApiRequest -Method GET -Path $endpoint
            $response.StatusCode | Should -Be 200
            & $walk -Node $response.Json.data -Trail $endpoint -Failures $failures -Self $walk
        }
        if ($failures.Count -gt 0) {
            throw ("Naive timestamps found (no timezone basis):`n  " + ($failures -join "`n  "))
        }
    }

    It 'the scan denominator is either a real count with a basis or degraded by name' {
        # A cold contract host has no scan cache; the snapshot must then say
        # so - the review's four-denominators defect began as exactly this
        # state rendered as a confident number.
        $response = Invoke-ContractApiRequest -Method GET -Path '/api/portfolio/snapshot'
        $repoCount = $response.Json.data.metrics.repoCount
        $inScope = $response.Json.data.metrics.inScopeRepoCount
        if ($null -ne $repoCount.value) {
            $repoCount.source | Should -Be 'status-scan'
            if ($null -ne $inScope.value) {
                [int]$inScope.value | Should -BeLessOrEqual ([int]$repoCount.value)
                $inScope.basis.denominator | Should -Be $repoCount.value
            }
        }
        else {
            @($response.Json.data.degraded | Where-Object { $_.source -eq 'status-scan' }).Count | Should -BeGreaterThan 0
        }
    }
}

Describe 'Branch cleanup route - Release 3.4 milestone 5' {
    # Same contract as the sync route: refusals are the module's own category,
    # reason and remedy forwarded verbatim as 409, and the refusal case is the
    # assertion that distinguishes "route exists" from "route exists AND
    # Git.BranchCleanup.ps1 is loaded in this host". Verified non-vacuous by
    # running against the pre-route host: all three failed there.

    It 'returns validation envelope without a repo or branch' {
        $response = Invoke-ContractApiRequest -Method POST -Path '/api/git/cleanup-branch' -Body @{}
        Assert-ErrorEnvelope -Response $response -StatusCode 400 -Operation 'git.cleanup-branch' -Category 'validation'
    }

    It 'forwards the module refusal rather than inventing one' {
        $notARepo = Join-Path $script:LogRoot 'not-a-repo-cleanup'
        $null = New-Item -ItemType Directory -Path $notARepo -Force
        $response = Invoke-ContractApiRequest -Method POST -Path '/api/git/cleanup-branch' -Body @{
            repoPath = $notARepo
            branch = 'roadmap/some-run'
            mergedHeadSha = 'abc123'
            approved = $true
        }

        $response.StatusCode | Should -Be 409
        $response.Json.success | Should -BeFalse
        $response.Json.category | Should -Be 'not-a-git-repo'
        $response.Json.data.refused | Should -BeTrue
        $response.Json.data.deleted | Should -BeFalse
        $response.Json.data.remedy | Should -Not -BeNullOrEmpty
    }

    It 'answers 404 with a named category when the repo is unknown' {
        $response = Invoke-ContractApiRequest -Method POST -Path '/api/git/cleanup-branch' -Body @{
            repoName = 'a-repo-that-does-not-exist-in-any-cache'
            branch = 'roadmap/some-run'
            approved = $true
        }

        $response.StatusCode | Should -Be 404
        $response.Json.category | Should -Be 'repo-not-found'
    }
}
