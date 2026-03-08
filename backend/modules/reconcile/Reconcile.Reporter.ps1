function Invoke-ReconcileReportExport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$OutDir,
        [Parameter(Mandatory = $true)]
        [string[]]$LocalRoots,
        [Parameter()]
        [string]$GitHubOwner,
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$LocalItems,
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$GitHubItems,
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Comparison,
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$PotentialDuplicates
    )

    if (-not (Get-Command -Name Test-ReconciliationArtifactShape -ErrorAction SilentlyContinue)) {
        . (Join-Path (Split-Path -Parent $PSScriptRoot) 'common\Validation.ps1')
    }

    $shape = Test-ReconciliationArtifactShape `
        -LocalItems $LocalItems `
        -GitHubItems $GitHubItems `
        -Comparison $Comparison `
        -PotentialDuplicates $PotentialDuplicates

    if (-not $shape.IsValid) {
        throw "Validation failed before artifact write: $($shape.Reason)"
    }

    $null = New-Item -ItemType Directory -Path $OutDir -Force -ErrorAction Stop

    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $jsonPath = Join-Path -Path $OutDir -ChildPath ("repo-reconciliation_{0}.json" -f $stamp)
    $csvPath = Join-Path -Path $OutDir -ChildPath ("repo-reconciliation_{0}.csv" -f $stamp)
    $dupesCsvPath = Join-Path -Path $OutDir -ChildPath ("repo-duplicates_{0}.csv" -f $stamp)

    [pscustomobject]@{
        GeneratedAt         = (Get-Date).ToString('o')
        LocalRoots          = @($LocalRoots)
        GitHubOwner         = $GitHubOwner
        LocalItemsCount     = @($LocalItems).Count
        GitHubItemsCount    = @($GitHubItems).Count
        MatchedCount        = @($Comparison | Where-Object { $_.Status -eq 'Matched' }).Count
        LocalOnlyCount      = @($Comparison | Where-Object { $_.Status -eq 'LocalOnly' }).Count
        GitHubOnlyCount     = @($Comparison | Where-Object { $_.Status -eq 'GitHubOnly' }).Count
        DuplicateCount      = @($PotentialDuplicates).Count
        LocalItems          = @($LocalItems)
        GitHubItems         = @($GitHubItems)
        Comparison          = @($Comparison)
        PotentialDuplicates = @($PotentialDuplicates)
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

    $Comparison | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8
    $PotentialDuplicates | Export-Csv -LiteralPath $dupesCsvPath -NoTypeInformation -Encoding UTF8

    return [pscustomobject]@{
        JsonPath = $jsonPath
        CsvPath = $csvPath
        DuplicatesCsvPath = $dupesCsvPath
    }
}
