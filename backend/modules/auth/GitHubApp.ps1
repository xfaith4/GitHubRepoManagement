<#
.SYNOPSIS
    Release 2.2 — GitHub App authentication helpers: RS256 JWT minting and
    installation-token exchange.

.DESCRIPTION
    The JWT minting (New-GitHubAppJwt) is fully offline-testable. The token
    exchange (Get-GitHubAppInstallationToken) makes a live call to GitHub and
    therefore requires a registered GitHub App + installation (operator step).

    Requires .NET 5+ / PowerShell 7 for RSA.ImportFromPem; degrades gracefully
    (Test-RsaPemSupported) on older runtimes.
#>

function ConvertTo-Base64Url {
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)
    return [Convert]::ToBase64String($Bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}

function ConvertFrom-Base64Url {
    param([Parameter(Mandatory = $true)][string]$Text)
    $s = $Text.Replace('-', '+').Replace('_', '/')
    switch ($s.Length % 4) { 2 { $s += '==' } 3 { $s += '=' } }
    return [Convert]::FromBase64String($s)
}

function Test-RsaPemSupported {
    try {
        $rsa = [System.Security.Cryptography.RSA]::Create()
        try { return ($null -ne ($rsa | Get-Member -Name 'ImportFromPem' -MemberType Method)) }
        finally { $rsa.Dispose() }
    } catch { return $false }
}

function New-GitHubAppJwt {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$AppId,
        [Parameter(Mandatory = $true)][string]$PrivateKeyPem,
        [int]$TtlSeconds = 540
    )
    if (-not (Test-RsaPemSupported)) { throw 'RSA PEM import requires .NET 5+/PowerShell 7 (RSA.ImportFromPem).' }
    $now = [System.DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $headerJson = '{"alg":"RS256","typ":"JWT"}'
    $payloadJson = (@{ iat = ($now - 60); exp = ($now + $TtlSeconds); iss = $AppId } | ConvertTo-Json -Compress)
    $headerB64 = ConvertTo-Base64Url ([System.Text.Encoding]::UTF8.GetBytes($headerJson))
    $payloadB64 = ConvertTo-Base64Url ([System.Text.Encoding]::UTF8.GetBytes($payloadJson))
    $signingInput = "$headerB64.$payloadB64"
    $rsa = [System.Security.Cryptography.RSA]::Create()
    try {
        $rsa.ImportFromPem($PrivateKeyPem)
        $sig = $rsa.SignData(
            [System.Text.Encoding]::ASCII.GetBytes($signingInput),
            [System.Security.Cryptography.HashAlgorithmName]::SHA256,
            [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
    } finally { $rsa.Dispose() }
    return "$signingInput." + (ConvertTo-Base64Url $sig)
}

# Decodes a JWT's header/payload (no signature verification) — for diagnostics
# and tests that assert claim structure.
function ConvertFrom-JwtClaims {
    param([Parameter(Mandatory = $true)][string]$Jwt)
    $parts = $Jwt.Split('.')
    if ($parts.Count -ne 3) { throw 'Malformed JWT (expected 3 dot-separated segments).' }
    return [pscustomobject]@{
        header  = [System.Text.Encoding]::UTF8.GetString((ConvertFrom-Base64Url $parts[0])) | ConvertFrom-Json
        payload = [System.Text.Encoding]::UTF8.GetString((ConvertFrom-Base64Url $parts[1])) | ConvertFrom-Json
    }
}

# Live installation-token exchange — needs a registered GitHub App (operator).
function Get-GitHubAppInstallationToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Jwt,
        [Parameter(Mandatory = $true)][string]$InstallationId
    )
    $uri = "https://api.github.com/app/installations/$InstallationId/access_tokens"
    $resp = Invoke-RestMethod -Uri $uri -Method Post -Headers @{
        Authorization = "Bearer $Jwt"
        Accept        = 'application/vnd.github+json'
        'User-Agent'  = 'repo-management-host'
    }
    return [string]$resp.token
}

# Reports whether a GitHub App is configured well enough to mint a JWT.
function Get-GitHubAppReadiness {
    param([object]$GitHubApp)
    $appId = ''
    $installationId = ''
    $privateKeyPath = ''
    if ($null -ne $GitHubApp) {
        if ($GitHubApp -is [System.Collections.IDictionary]) {
            if ($GitHubApp.Contains('appId')) { $appId = [string]$GitHubApp['appId'] }
            if ($GitHubApp.Contains('installationId')) { $installationId = [string]$GitHubApp['installationId'] }
            if ($GitHubApp.Contains('privateKeyPath')) { $privateKeyPath = [string]$GitHubApp['privateKeyPath'] }
        }
    }
    $keyPresent = (-not [string]::IsNullOrWhiteSpace($privateKeyPath)) -and (Test-Path -LiteralPath $privateKeyPath)
    return [pscustomobject]@{
        configured  = ((-not [string]::IsNullOrWhiteSpace($appId)) -and (-not [string]::IsNullOrWhiteSpace($installationId)))
        canMintJwt  = ((-not [string]::IsNullOrWhiteSpace($appId)) -and $keyPresent -and (Test-RsaPemSupported))
        appId       = $appId
        keyPresent  = [bool]$keyPresent
        rsaSupported = [bool](Test-RsaPemSupported)
    }
}
