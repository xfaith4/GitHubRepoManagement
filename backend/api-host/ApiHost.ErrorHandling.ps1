function Get-ErrorCategory {
    param([string]$Message)

    if ([string]::IsNullOrWhiteSpace($Message)) { return 'internal' }
    $text = $Message.ToLowerInvariant()
    if ($text -match 'validation|invalid|missing required|cannot bind|is required') { return 'validation' }
    if ($text -match 'timeout|timed out') { return 'timeout' }
    if ($text -match 'gh|github|network|dns|socket|connection|api') { return 'dependency' }
    return 'internal'
}

function Get-ErrorStatusCode {
    param(
        [string]$Message,
        [int]$DefaultStatusCode = 500
    )

    $category = Get-ErrorCategory -Message $Message
    if ($category -eq 'validation') {
        return 400
    }

    return $DefaultStatusCode
}
