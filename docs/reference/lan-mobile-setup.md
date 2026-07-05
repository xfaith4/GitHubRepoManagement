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

Add an `auth` block to `backend/config/settings.json`:

```json
{
  "auth": { "requireApiKey": true, "apiKeyEnvVar": "REPO_MGMT_API_KEY" }
}
```

Set the key in the environment (`REPO_MGMT_API_KEY`) or let the host generate
one on first run (written to `auth.apiKey`). On the phone, paste the key once —
the frontend stores it and sends it as `X-Api-Key` on every request. With auth
enforced, the bind guard no longer needs the insecure-bind acknowledgment.

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

```
http://<host-lan-ip>:7071
```

Then **Add to Home screen** — the web app manifest makes it launch
standalone (Release 2.5 Phase 4).
