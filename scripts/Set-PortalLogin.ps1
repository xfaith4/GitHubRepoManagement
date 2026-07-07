<#
.SYNOPSIS
    Sets (or changes) the operator password used to log in to the portal.

.DESCRIPTION
    Writes a PBKDF2-SHA256 hash of the password to a gitignored credential store
    under backend\modules\output\auth\. After setting it, restart the API host (or
    the Windows service) so it picks up that login is now configured; browsers can
    then sign in at the login screen instead of pasting the API key.

    The password is never stored or echoed in plaintext — only its salted hash.

.PARAMETER Password
    The new password (min 8 chars). If omitted, you're prompted securely.

.PARAMETER WorkspaceRoot
    Repository root. Defaults to the parent of this script's directory.

.EXAMPLE
    .\scripts\Set-PortalLogin.ps1
    # prompts for the password without echoing it

.EXAMPLE
    .\scripts\Set-PortalLogin.ps1 -Password (Read-Host -AsSecureString)
#>
[CmdletBinding()]
param(
    [object]$Password,
    [string]$WorkspaceRoot = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($WorkspaceRoot)) {
    $WorkspaceRoot = Split-Path -Parent $PSScriptRoot
}
$WorkspaceRoot = [System.IO.Path]::GetFullPath($WorkspaceRoot)

. (Join-Path $WorkspaceRoot 'backend\modules\auth\SessionAuth.ps1')

# Resolve the password to a plain string from any of: SecureString, plain string,
# or an interactive secure prompt. It stays in memory only long enough to hash.
function Resolve-PlainPassword {
    param([object]$Value)
    if ($null -eq $Value -or ($Value -is [string] -and [string]::IsNullOrEmpty($Value))) {
        $secure = Read-Host -Prompt 'New portal password (min 8 chars)' -AsSecureString
        $confirm = Read-Host -Prompt 'Confirm password' -AsSecureString
        $p1 = [System.Net.NetworkCredential]::new('', $secure).Password
        $p2 = [System.Net.NetworkCredential]::new('', $confirm).Password
        if ($p1 -ne $p2) { throw 'Passwords did not match.' }
        return $p1
    }
    if ($Value -is [System.Security.SecureString]) {
        return [System.Net.NetworkCredential]::new('', $Value).Password
    }
    return [string]$Value
}

$plain = Resolve-PlainPassword -Value $Password
$null = Set-PortalPassword -WorkspaceRoot $WorkspaceRoot -Password $plain

Write-Host ''
Write-Host '  [OK] Portal login password set.' -ForegroundColor Green
Write-Host "  Stored (hashed) at: $(Get-CredentialStorePath -WorkspaceRoot $WorkspaceRoot)" -ForegroundColor Gray
Write-Host '  Restart the API host / service, then sign in from the browser login screen.' -ForegroundColor Gray
Write-Host ''
