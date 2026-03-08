Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-DocReviewPathContainsArchiveOrExample {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$Files
    )

    $patterns = @(
        '\\archive\\',
        '\\_Archive\\',
        '\\examples\\',
        'run-ui-validate-',
        'ui-auto-validate-'
    )

    foreach ($file in @($Files)) {
        $normalized = ($file ?? '').Replace('/', '\')
        foreach ($pattern in $patterns) {
            if ($normalized -imatch [regex]::Escape($pattern)) {
                return $true
            }
        }
    }

    return $false
}

function Test-DocReviewPacketExists {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PacketPath
    )

    return (Test-Path -LiteralPath $PacketPath -PathType Leaf)
}

function Get-DocReviewMissingTargetFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoPath,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$Files
    )

    $missing = New-Object System.Collections.Generic.List[string]
    foreach ($relativePath in @($Files)) {
        $fullPath = Join-Path -Path $RepoPath -ChildPath $relativePath
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
            $missing.Add($relativePath)
        }
    }
    return @($missing)
}

Export-ModuleMember -Function @(
    'Test-DocReviewPathContainsArchiveOrExample',
    'Test-DocReviewPacketExists',
    'Get-DocReviewMissingTargetFiles'
)
