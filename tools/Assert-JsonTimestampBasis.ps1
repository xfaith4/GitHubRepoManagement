function Assert-JsonTimestampBasis {
    [CmdletBinding()]
    [OutputType([int])]
    param([Parameter(Mandatory = $true)][string]$Json, [string]$Context = 'JSON')
    # Inspect wire tokens BEFORE ConvertFrom-Json can turn dates into DateTime.
    $pattern = '"(?<name>[^"\\]*(?:\\.[^"\\]*)*)"\s*:\s*(?<value>"(?:[^"\\]|\\.)*"|null|true|false|-?[0-9.]+)'
    $checked = 0
    foreach ($match in [regex]::Matches($Json, $pattern)) {
        $name = $match.Groups['name'].Value
        if ($name -cnotmatch '(At|AtUtc|Timestamp|asOf)$') { continue }
        $token = $match.Groups['value'].Value
        if ($token -eq 'null' -or $token -eq '""') { continue }
        $checked++
        $parsed = [datetimeoffset]::MinValue
        if ($token -notmatch '^"\d{4}-\d{2}-\d{2}T[^"\\]*(Z|[+-]\d{2}:\d{2})"$' -or
            -not [datetimeoffset]::TryParse($token.Trim('"'), [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$parsed)) {
            throw "$Context.$name has an invalid or unspecified timezone basis: $token"
        }
    }
    return $checked
}
