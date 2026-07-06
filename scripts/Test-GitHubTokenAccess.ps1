<#
Non-destructive GitHub token access probe.
- Reads the token from $env:GitHubRepoManagerKey (never printed).
- Confirms identity + token scopes.
- Enumerates every accessible repo and reports read (pull) / write (push) /
  admin capability from GitHub's authoritative per-repo permissions object.
- Makes NO mutating call.
#>
[CmdletBinding()]
param([string]$EnvVar = 'GitHubRepoManagerKey', [int]$ShowReadOnlyMax = 40)

$ErrorActionPreference = 'Stop'
$tok = [Environment]::GetEnvironmentVariable($EnvVar)
if ([string]::IsNullOrWhiteSpace($tok)) {
    Write-Host ("RESULT: {0} is NOT SET in this shell." -f $EnvVar) -ForegroundColor Red
    exit 2
}
Write-Host ("reading env var: {0}" -f $EnvVar) -ForegroundColor DarkGray
Write-Host ("token present (length {0}, prefix-class {1})" -f $tok.Length, ($(if ($tok -like 'github_pat_*') { 'fine-grained-PAT' } elseif ($tok -like 'ghp_*') { 'classic-PAT' } elseif ($tok -like 'gho_*') { 'oauth' } else { 'other' }))) -ForegroundColor DarkGray

$headers = @{
    Authorization          = "Bearer $tok"
    'User-Agent'           = 'repo-mgmt-access-test'
    Accept                 = 'application/vnd.github+json'
    'X-GitHub-Api-Version' = '2022-11-28'
}

# 1) Identity + scopes -------------------------------------------------------
$u = Invoke-WebRequest -Uri 'https://api.github.com/user' -Headers $headers -SkipHttpErrorCheck
Write-Host ("`nGET /user -> HTTP {0}" -f [int]$u.StatusCode) -ForegroundColor Cyan
if ([int]$u.StatusCode -ne 200) {
    Write-Host "  token rejected — cannot continue." -ForegroundColor Red
    Write-Host ("  body: {0}" -f ($u.Content)) -ForegroundColor DarkGray
    exit 1
}
$login = ($u.Content | ConvertFrom-Json).login
$scopes = ($u.Headers['X-OAuth-Scopes'] | Out-String).Trim()
$rl = ($u.Headers['X-RateLimit-Remaining'] | Out-String).Trim()
Write-Host ("  authenticated as : {0}" -f $login) -ForegroundColor Green
Write-Host ("  classic scopes   : {0}" -f $(if ($scopes) { $scopes } else { '(none reported — fine-grained token; per-repo perms below are authoritative)' }))
Write-Host ("  rate remaining   : {0}" -f $rl) -ForegroundColor DarkGray

# 2) Enumerate accessible repos ---------------------------------------------
$all = New-Object System.Collections.Generic.List[object]
$page = 1
while ($true) {
    $uri = "https://api.github.com/user/repos?per_page=100&page=$page&affiliation=owner,collaborator,organization_member"
    $batch = Invoke-RestMethod -Uri $uri -Headers $headers
    $count = @($batch).Count
    if ($count -eq 0) { break }
    foreach ($r in $batch) { $all.Add($r) }
    if ($count -lt 100) { break }
    $page++
    if ($page -gt 50) { Write-Host '  (stopped paginating at 5000 repos)' -ForegroundColor Yellow; break }
}

$total = $all.Count
$write = @($all | Where-Object { $_.permissions.push }).Count
$read = @($all | Where-Object { $_.permissions.pull }).Count
$admin = @($all | Where-Object { $_.permissions.admin }).Count
$priv = @($all | Where-Object { $_.private }).Count
$arch = @($all | Where-Object { $_.archived }).Count
$readOnly = @($all | Where-Object { -not $_.permissions.push -and -not $_.archived })

Write-Host ("`n=== Access summary ===") -ForegroundColor White
Write-Host ("  accessible repos : {0}  ({1} private, {2} archived)" -f $total, $priv, $arch)
Write-Host ("  READ  (pull)     : {0}/{1}" -f $read, $total) -ForegroundColor Green
Write-Host ("  WRITE (push)     : {0}/{1}" -f $write, $total) -ForegroundColor $(if ($write -eq $total) { 'Green' } else { 'Yellow' })
Write-Host ("  ADMIN            : {0}/{1}" -f $admin, $total) -ForegroundColor DarkGray

if ($readOnly.Count -gt 0) {
    Write-Host ("`n  Non-archived repos WITHOUT write (push=false): {0}" -f $readOnly.Count) -ForegroundColor Yellow
    $readOnly | Select-Object -First $ShowReadOnlyMax | ForEach-Object {
        Write-Host ("    - {0}  (pull={1})" -f $_.full_name, $_.permissions.pull) -ForegroundColor DarkYellow
    }
    if ($readOnly.Count -gt $ShowReadOnlyMax) { Write-Host ("    ... and {0} more" -f ($readOnly.Count - $ShowReadOnlyMax)) -ForegroundColor DarkYellow }
} else {
    Write-Host ("`n  Every non-archived accessible repo has WRITE (push) access.") -ForegroundColor Green
}

# A couple of concrete examples so the result is verifiable at a glance.
Write-Host ("`n  sample writable repos:") -ForegroundColor DarkGray
$all | Where-Object { $_.permissions.push -and -not $_.archived } | Select-Object -First 5 | ForEach-Object {
    Write-Host ("    + {0}  (push={1}, admin={2})" -f $_.full_name, $_.permissions.push, $_.permissions.admin) -ForegroundColor DarkGray
}
exit 0
