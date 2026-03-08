function Invoke-ReconcileMatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$LocalItems,
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$GitHubItems
    )

    $comparison = Compare-LocalAndGitHub -LocalItems $LocalItems -GitHubItems $GitHubItems
    $duplicates = Get-PotentialLocalDuplicates -LocalItems $LocalItems

    return [pscustomobject]@{
        Comparison = @($comparison)
        PotentialDuplicates = @($duplicates)
    }
}
