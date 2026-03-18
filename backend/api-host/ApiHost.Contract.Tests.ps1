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
}
