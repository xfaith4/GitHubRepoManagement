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

1. **Shawl** (the wrapper):
   ```powershell
   winget install --id mtkennerly.shawl
   ```
   Or download `shawl.exe` from the releases page and drop it in `tools\`, or
   pass `-ShawlPath`.
2. **Frontend bundle** — the installer builds `frontend/dist` automatically if
   it's missing (needs `npm`). Pass `-SkipBuild` to install an API-only service.

## Install (run in an **elevated** PowerShell)

```powershell
# LAN-reachable, single operator, accepting the unauthenticated bind:
.\scripts\Install-RepoManagementService.ps1 -AllowInsecureBind

# Local-only (no acknowledgment needed):
.\scripts\Install-RepoManagementService.ps1 -BindAddress 127.0.0.1

# With a GitHub token for authenticated features:
.\scripts\Install-RepoManagementService.ps1 -AllowInsecureBind -GitHubToken $env:GITHUB_TOKEN
```

The installer is **idempotent** — re-run it any time to apply new settings; it
stops, removes, and recreates the service, then verifies `/health/live`.

## Manage

```powershell
Get-Service RepoMgmtPortal            # status
Restart-Service RepoMgmtPortal        # restart
Stop-Service RepoMgmtPortal           # stop (auto-restarts at next boot)
.\scripts\Uninstall-RepoManagementService.ps1   # remove entirely
```

Logs: `backend\modules\output\logs\` — `apihost.log` (structured host log) and
`shawl_for_RepoMgmtPortal_*.log` (captured stdout/stderr).

## Security note (do not skip)

There is **no `auth` block** in `backend\config\settings.json` today, so a
non-loopback bind serves the dashboard **unauthenticated** on the network. That's
tolerable for a single-operator LAN behind `-AllowInsecureBind`, but before you
share it more widely set `auth.requireApiKey=true` (plus an `apiKey` or
`apiKeyEnvVar`) in `settings.json` and re-run the installer — the guard will then
stop injecting `REPO_MGMT_ALLOW_INSECURE_BIND`.

## Service account

Defaults to **LocalSystem**: no password, fully unattended, can read local repos.
The host binds a raw TCP socket (not http.sys), so no URL-ACL reservation is
needed and a least-privilege account also works — pass `-Credential` to use one.
Note: a LocalSystem service does **not** inherit your user's environment, so the
`GITHUB_TOKEN` must be supplied via `-GitHubToken` (or a machine-scoped env var).
