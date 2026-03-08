function Invoke-DocReviewAdapter {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$RootPath = 'G:\Development\20_Staging',

        [Parameter()]
        [int]$MaxDepth = 3,

        [Parameter()]
        [string]$TargetRepo,

        [Parameter()]
        [string]$OutDir,

        [Parameter()]
        [switch]$GenerateQueue = $true,

        [Parameter()]
        [switch]$GenerateBatchPlan,

        [Parameter()]
        [string]$LogPath
    )

    $correlationId = [guid]::NewGuid().ToString('n')
    $operation = 'docreview.run'

    try {
        . (Join-Path $PSScriptRoot '..\modules\common\Logging.ps1')
        . (Join-Path $PSScriptRoot 'Adapter.Common.ps1')

        if (-not $OutDir) {
            $OutDir = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'output\docreview-adapter'
        }
        $inventoryDir = Join-Path $OutDir 'inventory'
        $queueDir = Join-Path $OutDir 'queue'
        $workitemsDir = Join-Path $OutDir 'workitems'

        $null = New-Item -ItemType Directory -Force -Path $inventoryDir
        $null = New-Item -ItemType Directory -Force -Path $queueDir
        $null = New-Item -ItemType Directory -Force -Path $workitemsDir

        Write-StructuredLog -Level Info -Component adapter.docreview -Operation $operation -CorrelationId $correlationId -Message 'Starting doc-review adapter run' -Details @{ RootPath = $RootPath; OutDir = $OutDir; GenerateQueue = $GenerateQueue.IsPresent; GenerateBatchPlan = $GenerateBatchPlan.IsPresent; TargetRepo = $TargetRepo } -LogPath $LogPath

        & (Join-Path $PSScriptRoot '..\modules\docreview\Invoke-DocReviewInventory.ps1') `
            -RootPath $RootPath `
            -OutDir $inventoryDir `
            -MaxDepth $MaxDepth

        $manifestPath = Join-Path $inventoryDir 'doc-review-manifest.json'

        if ($GenerateQueue) {
            & (Join-Path $PSScriptRoot '..\modules\docreview\Build-DocReviewQueue.ps1') `
                -ManifestPath $manifestPath `
                -OutDir $queueDir `
                -MaxFilesPerBatch 5
        }

        if ($GenerateBatchPlan -and -not [string]::IsNullOrWhiteSpace($TargetRepo)) {
            & (Join-Path $PSScriptRoot '..\modules\docreview\Invoke-DocReviewBatchPlan.ps1') `
                -ManifestPath $manifestPath `
                -TargetRepo $TargetRepo `
                -OutDir $workitemsDir
        }

        Write-StructuredLog -Level Info -Component adapter.docreview -Operation $operation -CorrelationId $correlationId -Message 'Doc-review adapter run completed' -Details @{ ManifestPath = $manifestPath } -LogPath $LogPath

        return New-AdapterResponse -Operation $operation -CorrelationId $correlationId -Success $true -Data ([pscustomobject]@{
            inventoryManifestPath = $manifestPath
            inventorySummaryCsvPath = (Join-Path $inventoryDir 'doc-review-summary.csv')
            inventoryReportPath = (Join-Path $inventoryDir 'doc-review-report.md')
            queuePath = if ($GenerateQueue) { Join-Path $queueDir 'doc-review-queue.json' } else { $null }
            workitemsRoot = if ($GenerateBatchPlan -and $TargetRepo) { Join-Path $workitemsDir $TargetRepo } else { $null }
        }) -Meta @{ outDir = $OutDir }
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
