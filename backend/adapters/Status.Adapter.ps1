function Get-StatusAdapterResult {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string[]]$LocalRoots = @('G:\Development'),

        [Parameter()]
        [int]$MaxDepth = 2,

        [Parameter()]
        [switch]$IncludeNonGitFolders,

        [Parameter()]
        [string]$LogPath
    )

    $correlationId = [guid]::NewGuid().ToString('n')
    $operation = 'status.scan'

    try {
        $callerLocalRoots = @($LocalRoots)
        $callerMaxDepth = $MaxDepth
        $callerIncludeNonGitFolders = $IncludeNonGitFolders

        . (Join-Path $PSScriptRoot '..\modules\common\Logging.ps1')
        . (Join-Path $PSScriptRoot 'Adapter.Common.ps1')
        . (Join-Path $PSScriptRoot '..\modules\reconcile\Invoke-Reconciliation.ps1') -LoadFunctionsOnly

        # Restore caller values after dot-sourcing legacy script with overlapping params.
        $LocalRoots = $callerLocalRoots
        $MaxDepth = $callerMaxDepth
        $IncludeNonGitFolders = $callerIncludeNonGitFolders

        $ignoreDirNames = @(
            'node_modules','vendor','dist','build','out','.vs','.idea','.vscode',
            'bin','obj','.venv','venv','__pycache__','.next','.pytest_cache'
        )
        $ignorePathRegex = @('[/\\]\.git([/\\]|$)')

        Write-StructuredLog -Level Info -Component adapter.status -Operation $operation -CorrelationId $correlationId -Message 'Starting status scan adapter call' -Details @{ LocalRoots = $LocalRoots; MaxDepth = $MaxDepth } -LogPath $LogPath

        $items = Get-LocalFolderInventory `
            -Roots $LocalRoots `
            -IgnoreDirNames $ignoreDirNames `
            -IgnorePathRegex $ignorePathRegex `
            -MaxDepth $MaxDepth `
            -IncludeNonGitFolders:$IncludeNonGitFolders

        $repos = @(
            @($items) | Where-Object { $_.IsGitRepo } | ForEach-Object {
                $modifiedCount = if ($null -ne $_.ModifiedCount) { [int]$_.ModifiedCount } else { 0 }
                $untrackedCount = if ($null -ne $_.UntrackedCount) { [int]$_.UntrackedCount } else { 0 }
                $dirty = $modifiedCount + $untrackedCount
                [pscustomobject]@{
                    name = $_.GitRepoName
                    folderName = $_.FolderName
                    path = $_.LocalPath
                    branch = $_.CurrentBranch
                    lastCommitDate = $_.LastCommitDate
                    modifiedCount = $modifiedCount
                    untrackedCount = $untrackedCount
                    dirtyCount = $dirty
                    status = if ($dirty -gt 0) { 'dirty' } else { 'clean' }
                    originUrl = $_.GitOriginUrl
                }
            }
        )

        Write-StructuredLog -Level Info -Component adapter.status -Operation $operation -CorrelationId $correlationId -Message 'Status scan adapter call completed' -Details @{ RepoCount = @($repos).Count; ItemCount = @($items).Count } -LogPath $LogPath

        return New-AdapterResponse -Operation $operation -CorrelationId $correlationId -Success $true -Data ([pscustomobject]@{ repos = $repos }) -Meta @{ localRoots = $LocalRoots; maxDepth = $MaxDepth }
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
