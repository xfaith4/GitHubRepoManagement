function Invoke-ReconcileAdapter {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string[]]$LocalRoots = @('G:\Development'),

        [Parameter()]
        [string]$GitHubOwner,

        [Parameter()]
        [ValidateSet('User','Org','Auto')]
        [string]$OwnerType = 'Auto',

        [Parameter()]
        [string]$OutDir,

        [Parameter()]
        [int]$MaxDepth = 3,

        [Parameter()]
        [switch]$IncludeNonGitFolders = $true,

        [Parameter()]
        [string]$LogPath
    )

    $correlationId = [guid]::NewGuid().ToString('n')
    $operation = 'reconcile.run'

    try {
        . (Join-Path $PSScriptRoot '..\modules\common\Logging.ps1')
        . (Join-Path $PSScriptRoot 'Adapter.Common.ps1')

        if (-not $OutDir) {
            $OutDir = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'output\reconcile-adapter'
        }

        Write-StructuredLog -Level Info -Component adapter.reconcile -Operation $operation -CorrelationId $correlationId -Message 'Starting reconcile adapter call' -Details @{ LocalRoots = $LocalRoots; GitHubOwner = $GitHubOwner; OutDir = $OutDir } -LogPath $LogPath

        $result = & (Join-Path $PSScriptRoot '..\modules\reconcile\Invoke-Reconciliation.Modular.ps1') `
            -LocalRoots $LocalRoots `
            -GitHubOwner $GitHubOwner `
            -OwnerType $OwnerType `
            -OutDir $OutDir `
            -MaxDepth $MaxDepth `
            -IncludeNonGitFolders:$IncludeNonGitFolders `
            -LogPath $LogPath

        Write-StructuredLog -Level Info -Component adapter.reconcile -Operation $operation -CorrelationId $correlationId -Message 'Reconcile adapter call completed' -Details @{ JsonPath = $result.JsonPath; ComparisonCount = $result.ComparisonCount } -LogPath $LogPath

        return New-AdapterResponse -Operation $operation -CorrelationId $correlationId -Success $true -Data $result -Meta @{ outDir = $OutDir }
    }
    catch {
        $errorMessage = $_.Exception.Message
        return New-AdapterResponse `
            -Operation $operation `
            -CorrelationId $correlationId `
            -Success $false `
            -Error $errorMessage `
            -Meta @{ errorCategory = (Get-ErrorCategory -Message $errorMessage) }
    }
}
