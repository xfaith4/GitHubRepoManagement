Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-DocReviewGitRepo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoPath
    )

    if (-not (Test-Path -LiteralPath $RepoPath -PathType Container)) {
        return $false
    }

    try {
        $null = (& git -C $RepoPath rev-parse --is-inside-work-tree 2>$null)
        return ($LASTEXITCODE -eq 0)
    }
    catch {
        return $false
    }
}

function Get-DocReviewWorkingTreeDirtyCount {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoPath
    )

    $output = (& git -C $RepoPath status --porcelain 2>&1) | Out-String
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to inspect git status for '$RepoPath': $output"
    }

    $lines = @($output -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    return [int]$lines.Count
}

function Ensure-DocReviewBranch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoPath,

        [Parameter(Mandatory = $true)]
        [string]$BranchName
    )

    $verifyOutput = (& git -C $RepoPath rev-parse --verify --quiet ("refs/heads/{0}" -f $BranchName) 2>&1) | Out-String
    $exists = ($LASTEXITCODE -eq 0)

    if ($exists) {
        $checkoutOutput = (& git -C $RepoPath checkout $BranchName 2>&1) | Out-String
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to checkout existing branch '$BranchName' in '$RepoPath': $checkoutOutput"
        }
    }
    else {
        $createOutput = (& git -C $RepoPath checkout -b $BranchName 2>&1) | Out-String
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to create branch '$BranchName' in '$RepoPath': $createOutput"
        }
    }
}

Export-ModuleMember -Function @(
    'Test-DocReviewGitRepo',
    'Get-DocReviewWorkingTreeDirtyCount',
    'Ensure-DocReviewBranch'
)
