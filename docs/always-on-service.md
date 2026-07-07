# Always-on portal (Windows service)

Run the portal as a permanent Windows service so it is **always up**: starts at
boot before anyone logs in, restarts automatically if it crashes, and captures
its own logs. A single pwsh process serves both the API and the compiled
dashboard (`frontend/dist`) — no Vite/Node runtime is needed at service time.

## Why a service (vs. `Start-App.ps1`)

`Start-App.ps1` launches a hidden, session-tied process. It dies on logout, does
**not** survive a reboot, and has **no crash restart**. A Windows service fixes
all three. PowerShell scripts can't be services directly, so we wrap the host
with [Shawl](https://github.com/mtkennerly/shawl) — a tiny supervisor .exe that
the Service Control Manager can drive.

## One-time prerequisites

**Shawl** (the service wrapper) — install via winget:

```powershell
winget install --id mtkennerly.shawl
```

Or download `shawl.exe` from the releases page into `tools\`, or pass `-ShawlPath`.

**Frontend bundle** — the installer builds `frontend/dist` automatically if it's
missing (needs `npm`). Pass `-SkipBuild` to install an API-only service.

## Install (run in an **elevated** PowerShell)

```powershell
# LAN-reachable, protected by an auto-generated API key (secure by default):
.\scripts\Install-RepoManagementService.ps1

# Provide your own API key instead of an auto-generated one:
.\scripts\Install-RepoManagementService.ps1 -ApiKey '<64-hex-key>'

# Local-only:
.\scripts\Install-RepoManagementService.ps1 -BindAddress 127.0.0.1

# Explicitly run OPEN (no auth) on a fully trusted segment:
.\scripts\Install-RepoManagementService.ps1 -AllowInsecureBind

# With a GitHub token for authenticated features:
.\scripts\Install-RepoManagementService.ps1 -GitHubToken $env:GITHUB_TOKEN
```

By default a network bind is **protected**: the installer turns on the API-key
gate and prints the key (paste it into the dashboard once, or use it for
automation). It enables auth by injecting `REPO_MGMT_REQUIRE_API_KEY` +
`REPO_MGMT_API_KEY` for the service process only — `settings.json` stays open, so
the smoke suite (which assumes an open host) is unaffected.

The installer is **idempotent** — re-run it any time to apply new settings; it
stops, removes, and recreates the service, then verifies `/health/live`.

## HTTPS

The host terminates TLS natively (Release 2.2): give it a `.pfx` and it wraps
every connection in TLS — no reverse proxy needed. It's off until a certificate
is configured.

**1. Create a certificate** (elevated shell). For a single-operator LAN, a
self-signed cert with the host's IP in the SAN is the pragmatic choice:

```powershell
.\scripts\New-RepoManagementTlsCertificate.ps1 `
    -DnsName 'repo-portal','repo-portal.local' `
    -IpAddress '192.168.50.200','127.0.0.1' `
    -TrustLocally
```

`-TrustLocally` trusts it on this machine (no warning here). For phones/other
PCs, import the exported `.cer` into their trusted-root store. Copy the printed
PFX password.

**2. Install the service with TLS (auth on by default):**

```powershell
.\scripts\Install-RepoManagementService.ps1 `
    -PfxPath ".\backend\config\tls\portal.pfx" -PfxPassword '<password>'
```

The PFX path and password are injected as `REPO_MGMT_TLS_PFX` /
`REPO_MGMT_TLS_PFX_PASSWORD` for the service only (kept out of `settings.json`).
The portal is now at `https://<host>:7071`, protected by the API key.

**Real, universally-trusted certificate:** if you have a public domain name, use
an ACME client (e.g. [win-acme](https://www.win-acme.com/)) to obtain and
auto-renew a PFX, then pass that PFX to the installer — the host loads it the
same way, and you get zero browser warnings anywhere. Self-signed certs don't
auto-renew, so re-run the generator + installer before the expiry date.

> TLS ≠ auth. HTTPS encrypts the traffic; it does **not** restrict *who* can
> call. Pair it with the API key / login below — the installer turns auth on for
> you by default.

## Manage

```powershell
Get-Service RepoMgmtPortal            # status
Restart-Service RepoMgmtPortal        # restart
Stop-Service RepoMgmtPortal           # stop (auto-restarts at next boot)
.\scripts\Uninstall-RepoManagementService.ps1   # remove entirely
```

Logs: `backend\modules\output\logs\` — `apihost.log` (structured host log) and
`shawl_for_RepoMgmtPortal_*.log` (captured stdout/stderr).

## Authentication

The portal has two complementary credentials. The gate is turned ON by enabling
auth (the installer does this by default for a network bind, via
`REPO_MGMT_REQUIRE_API_KEY`); once on, a request is authorized by **either**:

- **API key** — the automation / machine credential. Sent as `X-Api-Key: <key>`
  or `Authorization: Bearer <key>`. The installer prints it; paste it into the
  dashboard once (stored in the browser) or use it from scripts.
- **Session login** — the human credential. Set an operator password, then people
  sign in at a login screen and get a short-lived `HttpOnly; SameSite=Strict`
  session cookie (no secret in browser storage). A **Sign out** button clears it.

**Set the login password** (no elevation needed), then restart so the host picks
it up:

```powershell
.\scripts\Set-PortalLogin.ps1        # prompts securely (min 8 chars)
Restart-Service RepoMgmtPortal
```

The password is stored only as a PBKDF2-SHA256 hash under
`backend\modules\output\auth\` (gitignored); the cookie-signing key lives there
too. A configured password does **not** by itself enable the gate — auth must be
on (installer default, or `REPO_MGMT_REQUIRE_API_KEY`), which keeps the
open-by-default config the smoke suite relies on unchanged.

### Locking a running Start-App instance right now

Before you install the service, you can lock an interactive `Start-App.ps1`
session by enabling auth for that launch only (leaves `settings.json` and the
smokes untouched):

```powershell
$env:REPO_MGMT_REQUIRE_API_KEY = 'true'
$env:REPO_MGMT_API_KEY = '<64-hex-key>'
.\Start-App.ps1
```

Then open the dashboard and paste the key on the entry screen (or set a password
with `Set-PortalLogin.ps1` and sign in).

## Service account

Defaults to **LocalSystem**: no password, fully unattended, can read local repos.
The host binds a raw TCP socket (not http.sys), so no URL-ACL reservation is
needed and a least-privilege account also works — pass `-Credential` to use one.
Note: a LocalSystem service does **not** inherit your user's environment, so the
`GITHUB_TOKEN` must be supplied via `-GitHubToken` (or a machine-scoped env var).
