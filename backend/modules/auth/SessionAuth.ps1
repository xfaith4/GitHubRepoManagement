# ── Portal user login: password credential + signed session cookie ───────────
# Release 2.7 — human login layer that composes with the Release 2.2 API key.
#
# Model: one operator password (PBKDF2-SHA256, per-install salt) is exchanged at
# /api/auth/login for a short-lived, HMAC-signed, stateless session token set as
# an HttpOnly cookie. The host authorizes a request when it carries EITHER a
# valid API key (automation) OR a valid session cookie (a logged-in human).
#
# All secrets live under backend/modules/output/auth/ which is gitignored — the
# password hash and the cookie-signing key never enter source control.

$script:SessionCookieName = 'rmsid'

function Get-AuthDataDir {
    param([Parameter(Mandatory = $true)][string]$WorkspaceRoot)
    $dir = Join-Path $WorkspaceRoot 'backend\modules\output\auth'
    if (-not (Test-Path -LiteralPath $dir)) { $null = New-Item -ItemType Directory -Path $dir -Force }
    return $dir
}

function Get-CredentialStorePath {
    param([Parameter(Mandatory = $true)][string]$WorkspaceRoot)
    return (Join-Path (Get-AuthDataDir -WorkspaceRoot $WorkspaceRoot) 'portal-credential.json')
}

function Test-BytesEqual {
    # Constant-time comparison — avoids leaking match length via timing.
    param([byte[]]$A, [byte[]]$B)
    if ($null -eq $A -or $null -eq $B) { return $false }
    if ($A.Length -ne $B.Length) { return $false }
    $diff = 0
    for ($i = 0; $i -lt $A.Length; $i++) { $diff = $diff -bor ($A[$i] -bxor $B[$i]) }
    return ($diff -eq 0)
}

function Get-Pbkdf2Hash {
    param(
        [Parameter(Mandatory = $true)][string]$Password,
        [Parameter(Mandatory = $true)][byte[]]$Salt,
        [Parameter(Mandatory = $true)][int]$Iterations,
        [int]$Length = 32
    )
    $kdf = [System.Security.Cryptography.Rfc2898DeriveBytes]::new(
        $Password, $Salt, $Iterations, [System.Security.Cryptography.HashAlgorithmName]::SHA256)
    try { return $kdf.GetBytes($Length) } finally { $kdf.Dispose() }
}

function Test-PortalPasswordConfigured {
    param([Parameter(Mandatory = $true)][string]$WorkspaceRoot)
    $path = Get-CredentialStorePath -WorkspaceRoot $WorkspaceRoot
    if (-not (Test-Path -LiteralPath $path)) { return $false }
    try {
        $c = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        return (($c.PSObject.Properties.Name -contains 'hash') -and -not [string]::IsNullOrWhiteSpace([string]$c.hash))
    }
    catch { return $false }
}

function Set-PortalPassword {
    param(
        [Parameter(Mandatory = $true)][string]$WorkspaceRoot,
        [Parameter(Mandatory = $true)][string]$Password
    )
    if ([string]::IsNullOrWhiteSpace($Password) -or $Password.Length -lt 8) {
        throw 'Password must be at least 8 characters.'
    }
    $salt = New-Object byte[] 16
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($salt) } finally { $rng.Dispose() }
    $iterations = 210000
    $hash = Get-Pbkdf2Hash -Password $Password -Salt $salt -Iterations $iterations -Length 32

    $obj = [ordered]@{
        v          = 1
        algo       = 'pbkdf2-sha256'
        iterations = $iterations
        salt       = [Convert]::ToBase64String($salt)
        hash       = [Convert]::ToBase64String($hash)
        updatedAt  = (Get-Date).ToString('o')
    }
    $path = Get-CredentialStorePath -WorkspaceRoot $WorkspaceRoot
    ($obj | ConvertTo-Json) | Set-Content -LiteralPath $path -Encoding UTF8
    return $true
}

function Test-PortalPassword {
    param(
        [Parameter(Mandatory = $true)][string]$WorkspaceRoot,
        [Parameter(Mandatory = $true)][string]$Password
    )
    $path = Get-CredentialStorePath -WorkspaceRoot $WorkspaceRoot
    if (-not (Test-Path -LiteralPath $path)) { return $false }
    try { $c = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json } catch { return $false }
    if (($c.PSObject.Properties.Name -notcontains 'hash') -or [string]::IsNullOrWhiteSpace([string]$c.hash)) { return $false }
    try {
        $salt = [Convert]::FromBase64String([string]$c.salt)
        $expected = [Convert]::FromBase64String([string]$c.hash)
        $iterations = [int]$c.iterations
        $actual = Get-Pbkdf2Hash -Password $Password -Salt $salt -Iterations $iterations -Length $expected.Length
        return (Test-BytesEqual -A $actual -B $expected)
    }
    catch { return $false }
}

function Get-SessionSigningKey {
    param([Parameter(Mandatory = $true)][string]$WorkspaceRoot)
    $path = Join-Path (Get-AuthDataDir -WorkspaceRoot $WorkspaceRoot) 'session-signing.key'
    if (Test-Path -LiteralPath $path) {
        try {
            $b64 = (Get-Content -LiteralPath $path -Raw).Trim()
            if (-not [string]::IsNullOrWhiteSpace($b64)) { return [Convert]::FromBase64String($b64) }
        }
        catch { }
    }
    $key = New-Object byte[] 32
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($key) } finally { $rng.Dispose() }
    [Convert]::ToBase64String($key) | Set-Content -LiteralPath $path -Encoding ASCII
    return $key
}

function ConvertTo-Base64Url {
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)
    return ([Convert]::ToBase64String($Bytes)).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}

function ConvertFrom-Base64Url {
    param([Parameter(Mandatory = $true)][string]$Text)
    $t = $Text.Replace('-', '+').Replace('_', '/')
    switch ($t.Length % 4) { 2 { $t += '==' } 3 { $t += '=' } }
    return [Convert]::FromBase64String($t)
}

function Get-Hmac {
    param([Parameter(Mandatory = $true)][byte[]]$Key, [Parameter(Mandatory = $true)][byte[]]$Message)
    $h = [System.Security.Cryptography.HMACSHA256]::new($Key)
    try { return $h.ComputeHash($Message) } finally { $h.Dispose() }
}

function New-SessionToken {
    # payloadB64url.signatureB64url — signature = HMAC-SHA256(signingKey, payloadB64url)
    param(
        [Parameter(Mandatory = $true)][string]$WorkspaceRoot,
        [int]$TtlHours = 12,
        [string]$Subject = 'operator'
    )
    $now = [System.DateTimeOffset]::UtcNow
    $payload = [ordered]@{
        sub = $Subject
        iat = $now.ToUnixTimeSeconds()
        exp = $now.AddHours($TtlHours).ToUnixTimeSeconds()
    }
    $payloadJson = ($payload | ConvertTo-Json -Compress)
    $payloadB64 = ConvertTo-Base64Url -Bytes ([System.Text.Encoding]::UTF8.GetBytes($payloadJson))
    $key = Get-SessionSigningKey -WorkspaceRoot $WorkspaceRoot
    $sig = Get-Hmac -Key $key -Message ([System.Text.Encoding]::ASCII.GetBytes($payloadB64))
    return ('{0}.{1}' -f $payloadB64, (ConvertTo-Base64Url -Bytes $sig))
}

function Test-SessionToken {
    param(
        [Parameter(Mandatory = $true)][string]$WorkspaceRoot,
        [string]$Token
    )
    if ([string]::IsNullOrWhiteSpace($Token)) { return $false }
    $parts = $Token.Split('.')
    if ($parts.Count -ne 2) { return $false }
    try {
        $payloadB64 = $parts[0]
        $key = Get-SessionSigningKey -WorkspaceRoot $WorkspaceRoot
        $expectedSig = Get-Hmac -Key $key -Message ([System.Text.Encoding]::ASCII.GetBytes($payloadB64))
        $providedSig = ConvertFrom-Base64Url -Text $parts[1]
        if (-not (Test-BytesEqual -A $expectedSig -B $providedSig)) { return $false }
        $payloadJson = [System.Text.Encoding]::UTF8.GetString((ConvertFrom-Base64Url -Text $payloadB64))
        $payload = $payloadJson | ConvertFrom-Json
        if ($payload.PSObject.Properties.Name -notcontains 'exp') { return $false }
        $now = [System.DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        return ([long]$payload.exp -ge $now)
    }
    catch { return $false }
}

function Get-RequestSessionToken {
    param([Parameter(Mandatory = $true)][object]$Request)
    if (-not $Request.Headers.ContainsKey('cookie')) { return '' }
    $cookieHeader = [string]$Request.Headers['cookie']
    foreach ($pair in $cookieHeader.Split(';')) {
        $kv = $pair.Trim()
        $eq = $kv.IndexOf('=')
        if ($eq -gt 0 -and $kv.Substring(0, $eq).Trim() -eq $script:SessionCookieName) {
            return $kv.Substring($eq + 1).Trim()
        }
    }
    return ''
}

function Test-RequestSessionValid {
    param(
        [Parameter(Mandatory = $true)][object]$Request,
        [Parameter(Mandatory = $true)][string]$WorkspaceRoot
    )
    $tok = Get-RequestSessionToken -Request $Request
    if ([string]::IsNullOrWhiteSpace($tok)) { return $false }
    return (Test-SessionToken -WorkspaceRoot $WorkspaceRoot -Token $tok)
}

function New-SessionCookieHeader {
    param([Parameter(Mandatory = $true)][string]$Token, [int]$TtlHours = 12, [bool]$Secure = $true)
    $attrs = ('{0}={1}; Path=/; HttpOnly; SameSite=Strict; Max-Age={2}' -f $script:SessionCookieName, $Token, ($TtlHours * 3600))
    if ($Secure) { $attrs += '; Secure' }
    return "Set-Cookie: $attrs"
}

function New-SessionClearCookieHeader {
    param([bool]$Secure = $true)
    $attrs = ('{0}=; Path=/; HttpOnly; SameSite=Strict; Max-Age=0' -f $script:SessionCookieName)
    if ($Secure) { $attrs += '; Secure' }
    return "Set-Cookie: $attrs"
}
