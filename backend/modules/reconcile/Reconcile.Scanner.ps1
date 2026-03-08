function Invoke-ReconcileScan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$LocalRoots,
        [Parameter(Mandatory = $true)]
        [string[]]$IgnoreDirNames,
        [Parameter(Mandatory = $true)]
        [string[]]$IgnorePathRegex,
        [Parameter(Mandatory = $true)]
        [int]$MaxDepth,
        [Parameter(Mandatory = $true)]
        [bool]$IncludeNonGitFolders
    )

    $items = Get-LocalFolderInventory `
        -Roots $LocalRoots `
        -IgnoreDirNames $IgnoreDirNames `
        -IgnorePathRegex $IgnorePathRegex `
        -MaxDepth $MaxDepth `
        -IncludeNonGitFolders:$IncludeNonGitFolders

    if ($null -eq $items) {
        return ,@()
    }

    return ,@($items)
}
