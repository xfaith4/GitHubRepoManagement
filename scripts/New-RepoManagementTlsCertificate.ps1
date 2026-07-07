<#
.SYNOPSIS
    Generates a self-signed TLS certificate (PFX) for the Repo Management portal.

.DESCRIPTION
    The API host terminates TLS itself (Release 2.2): when a PFX certificate is
    configured, every connection is wrapped in an SslStream. This script produces
    a suitable self-signed certificate with correct Subject Alternative Names
    (both DNS names and IP addresses, so browsers validate an IP-based URL) and a
    serverAuth EKU, then exports it to a password-protected .pfx plus a public
    .cer for trusting on clients.

    Certificate generation uses .NET directly (no PKI module, no elevation, no
    certificate store), so it runs as an ordinary user. Only -TrustLocally — which
    writes to the machine's Trusted Root store — requires an elevated shell.

    This is the pragmatic choice for a single-operator LAN. Clients see a trust
    warning unless the certificate is trusted on that machine — pass -TrustLocally
    to add it to THIS machine's LocalMachine\Root store. For other devices
    (phones, other PCs), import the exported .cer into their trust store.

    For a real, universally-trusted certificate (a public domain name), use an
    ACME client such as win-acme to obtain and auto-renew a PFX, then point the
    installer at that PFX instead — the host loads it the same way.

.PARAMETER DnsName
    DNS name(s) to include in the SAN. Default: 'localhost'.

.PARAMETER IpAddress
    IP address(es) to include in the SAN as iPAddress entries (required for
    browsers to accept an https://<ip> URL). Default: '127.0.0.1'.

.PARAMETER PfxPath
    Output path for the .pfx. Default: backend\config\tls\portal.pfx (gitignored).

.PARAMETER PfxPassword
    Password protecting the .pfx private key. If omitted, a strong random
    password is generated and printed once — copy it, you'll pass it to the
    installer.

.PARAMETER ValidYears
    Certificate validity in years. Default: 5.

.PARAMETER TrustLocally
    Also import the public certificate into this machine's LocalMachine\Root store
    so its own browser trusts the portal without a warning. Requires an elevated
    shell.

.PARAMETER Force
    Overwrite an existing .pfx at PfxPath.

.EXAMPLE
    # Cert for LAN access by IP + a friendly name, trusted on this machine:
    .\scripts\New-RepoManagementTlsCertificate.ps1 `
        -DnsName 'repo-portal','repo-portal.local' `
        -IpAddress '192.168.50.200','127.0.0.1' `
        -TrustLocally
#>
[CmdletBinding()]
param(
    [string[]]$DnsName = @('localhost'),
    [string[]]$IpAddress = @('127.0.0.1'),
    [string]$PfxPath = '',
    [string]$PfxPassword = '',
    [int]$ValidYears = 5,
    [switch]$TrustLocally,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Ok   { param([string]$m) Write-Host "  [OK] $m" -ForegroundColor Green }
function Write-Step { param([string]$m) Write-Host "  $m" -ForegroundColor Cyan }

$repoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($PfxPath)) {
    $PfxPath = Join-Path $repoRoot 'backend\config\tls\portal.pfx'
}
$PfxPath = [System.IO.Path]::GetFullPath($PfxPath)

if ((Test-Path -LiteralPath $PfxPath) -and -not $Force) {
    throw "PFX already exists at $PfxPath. Pass -Force to overwrite."
}
$pfxDir = Split-Path -Parent $PfxPath
if (-not (Test-Path -LiteralPath $pfxDir)) { $null = New-Item -ItemType Directory -Path $pfxDir -Force }

# Generate a random password when none is supplied (printed once below).
$generatedPassword = $false
if ([string]::IsNullOrWhiteSpace($PfxPassword)) {
    $PfxPassword = [System.Guid]::NewGuid().ToString('N') + [System.Guid]::NewGuid().ToString('N').Substring(0, 8)
    $generatedPassword = $true
}

# Collect SAN entries. IPs MUST be iPAddress entries (not DNS) or browsers reject
# an https://<ip> URL even with a matching name.
$dnsList = @($DnsName | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
$ipList = @($IpAddress | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if ($dnsList.Count -eq 0 -and $ipList.Count -eq 0) {
    throw 'Provide at least one -DnsName or -IpAddress.'
}
$cn = if ($dnsList.Count -gt 0) { $dnsList[0] } else { $ipList[0] }

Write-Step "Generating self-signed certificate (CN=$cn)..."
$sanLabel = @(@($dnsList | ForEach-Object { "DNS=$_" }) + @($ipList | ForEach-Object { "IP=$_" })) -join ', '
Write-Step "SAN: $sanLabel"

# --- Build the certificate with .NET (portable, no cert store, no admin) --------
$rsa = [System.Security.Cryptography.RSA]::Create(2048)
try {
    $req = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new(
        "CN=$cn", $rsa,
        [System.Security.Cryptography.HashAlgorithmName]::SHA256,
        [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)

    # End-entity (not a CA).
    $req.CertificateExtensions.Add(
        [System.Security.Cryptography.X509Certificates.X509BasicConstraintsExtension]::new($false, $false, 0, $true))
    # Key usage appropriate for a TLS server.
    $req.CertificateExtensions.Add(
        [System.Security.Cryptography.X509Certificates.X509KeyUsageExtension]::new(
            [System.Security.Cryptography.X509Certificates.X509KeyUsageFlags]'DigitalSignature, KeyEncipherment', $true))
    # EKU: serverAuth (1.3.6.1.5.5.7.3.1) — strict clients require this.
    $ekuOids = [System.Security.Cryptography.OidCollection]::new()
    $null = $ekuOids.Add([System.Security.Cryptography.Oid]::new('1.3.6.1.5.5.7.3.1'))
    $req.CertificateExtensions.Add(
        [System.Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension]::new($ekuOids, $false))
    # Subject Alternative Names.
    $sanBuilder = [System.Security.Cryptography.X509Certificates.SubjectAlternativeNameBuilder]::new()
    foreach ($d in $dnsList) { $sanBuilder.AddDnsName($d) }
    foreach ($ip in $ipList) { $sanBuilder.AddIpAddress([System.Net.IPAddress]::Parse($ip)) }
    $req.CertificateExtensions.Add($sanBuilder.Build())

    $notBefore = [System.DateTimeOffset]::UtcNow.AddMinutes(-5)
    $notAfter = [System.DateTimeOffset]::UtcNow.AddYears($ValidYears)
    $cert = $req.CreateSelfSigned($notBefore, $notAfter)
}
finally { $rsa.Dispose() }

# Export PFX (private key + cert) and a public-only .cer for client trust.
$pfxBytes = $cert.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Pfx, $PfxPassword)
[System.IO.File]::WriteAllBytes($PfxPath, $pfxBytes)
Write-Ok "Exported PFX: $PfxPath"

$cerPath = [System.IO.Path]::ChangeExtension($PfxPath, '.cer')
$cerBytes = $cert.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert)
[System.IO.File]::WriteAllBytes($cerPath, $cerBytes)
Write-Ok "Exported public cert: $cerPath"

if ($TrustLocally) {
    $isAdmin = ([System.Security.Principal.WindowsPrincipal][System.Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Host "  [warn] -TrustLocally needs an elevated shell to write LocalMachine\Root. Skipping trust." -ForegroundColor Yellow
        Write-Host "         Re-run elevated, or import $cerPath manually." -ForegroundColor Yellow
    }
    else {
        $store = [System.Security.Cryptography.X509Certificates.X509Store]::new('Root', 'LocalMachine')
        $store.Open('ReadWrite')
        try { $store.Add([System.Security.Cryptography.X509Certificates.X509Certificate2]::new($cerBytes)) }
        finally { $store.Close() }
        Write-Ok 'Trusted on this machine (LocalMachine\Root) — no browser warning here.'
        Write-Host "  For OTHER devices, import $cerPath into their trusted-root store." -ForegroundColor Gray
    }
}
else {
    Write-Host "  Import $cerPath into client trust stores to avoid warnings." -ForegroundColor Gray
}

Write-Host ''
Write-Host '  Certificate ready.' -ForegroundColor Green
Write-Host "  Thumbprint : $($cert.Thumbprint)" -ForegroundColor Gray
Write-Host "  Valid until: $($cert.NotAfter.ToString('yyyy-MM-dd'))" -ForegroundColor Gray
if ($generatedPassword) {
    Write-Host ''
    Write-Host '  Generated PFX password (save it now — not shown again):' -ForegroundColor Yellow
    Write-Host "    $PfxPassword" -ForegroundColor Yellow
}
Write-Host ''
Write-Host '  Next — install the service with HTTPS:' -ForegroundColor Cyan
Write-Host "    .\scripts\Install-RepoManagementService.ps1 -AllowInsecureBind ``" -ForegroundColor Gray
Write-Host "        -PfxPath `"$PfxPath`" -PfxPassword '<password-above>'" -ForegroundColor Gray
Write-Host ''
