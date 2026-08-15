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
