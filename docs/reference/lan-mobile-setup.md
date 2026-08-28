# LAN / Mobile Setup (Release 2.5)

Use the dashboard from an Android phone (or any device) on your local network.

> **Security note.** The API host **refuses to bind a non-loopback address
> without API auth** (Release 2.2 bind guard). `Start-App.ps1` binds `0.0.0.0`
> by default and acknowledges the single-operator interim exposure with a
> warning. Before sharing with teammates, enable auth (below).

## 1. Bind address

`Start-App.ps1` defaults to `-ApiHost 0.0.0.0` (all interfaces). To pin a
specific interface:

```powershell
./Start-App.ps1 -ApiHost 0.0.0.0 -ApiPort 7071
```

Loopback-only (desktop): `-ApiHost 127.0.0.1`.

## 2. Enable API auth before sharing

**For the installed service, use the script.** It does the whole sequence in
the order that never leaves the API exposed without a key, and verifies the
result instead of assuming it:

```powershell
# From an ELEVATED PowerShell 7 prompt, in the workspace root
pwsh -File .\scripts\Enable-SharedLanAccess.ps1 -WhatIf   # preview the plan
pwsh -File .\scripts\Enable-SharedLanAccess.ps1           # key, firewall, rebind, verify
```

It requires elevation because the service runs as LocalSystem, so the variables
must be **Machine** scope. It prints the key once and reverts in three commands
(shown at the end of its own output).

### Doing it by hand

Set **both** environment variables, and the key first:

```powershell
[Environment]::SetEnvironmentVariable('REPO_MGMT_API_KEY', '<64-hex key>', 'Machine')
[Environment]::SetEnvironmentVariable('REPO_MGMT_REQUIRE_API_KEY', 'true', 'Machine')
```

The environment is the right home for a key on a shared host. An `auth` block
in `backend/config/settings.json` also works —

```json
{
  "auth": { "requireApiKey": true, "apiKeyEnvVar": "REPO_MGMT_API_KEY" }
}
```

— but **never put the key itself there.** That file is listed in `.gitignore`
yet is still tracked (it was committed before the ignore rule), so the entry has
no effect and a key stored in it shows up in `git status`. The host warns when
it finds one.

If auth is enabled with no key configured anywhere, the host generates one and
stores it at `output/auth/api-key`, which is genuinely outside version control.
That keeps a first run working; pinning your own key via the environment is
still what you want for a host other devices talk to.

On the phone, paste the key once — the frontend stores it and sends it as
`X-Api-Key` on every request. With auth enforced, the bind guard no longer needs
the insecure-bind acknowledgment.

Optional hardening (also in `network`):

```json
{
  "network": {
    "allowedOrigins": ["http://192.168.1.50:7071"],
    "rateLimit": { "maxRequests": 120, "windowSeconds": 60 }
  }
}
```

## 3. Firewall rule (Windows)

Allow inbound TCP on the API port for private networks:

```powershell
New-NetFirewallRule -DisplayName "RepoManager API 7071" -Direction Inbound `
  -Action Allow -Protocol TCP -LocalPort 7071 -Profile Private
```

## 4. Phone URL

Find the host machine's LAN IP (`ipconfig` → IPv4). On the phone's browser:

```text
http://<host-lan-ip>:7071
```

Then **Add to Home screen** — the web app manifest makes it launch
standalone (Release 2.5 Phase 4).
