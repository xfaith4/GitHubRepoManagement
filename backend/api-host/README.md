# API Host

Minimal local PowerShell API host for adapter contracts.

## Script

- `Start-RepoManagementApiHost.ps1`

## Routes

- `GET /health/live`
- `GET /health/ready`
- `GET /health/dependencies`
- `GET /metrics`
- `GET /api/status`
- `POST /api/reconcile`
- `POST /api/docreview/run`
- `GET /api/report/artifacts`
- `GET /api/artifacts/:repoName`
- `GET /api/settings`
- `POST /api/settings`
- `POST /api/init` (accepted placeholder)
- `POST /api/update`
- `POST /api/sync`
- `POST /api/export` (accepted placeholder)
- `POST /api/archive` (accepted placeholder)
- `POST /api/github/status`

## Start

```powershell
.\backend\api-host\Start-RepoManagementApiHost.ps1 -BindAddress '127.0.0.1' -Port 7071
```

## Smoke Test

```powershell
.\scripts\Invoke-ApiHostSmokeTest.ps1
```

Notes:
- Host uses `TcpListener` loopback binding.
- CORS headers are enabled for local frontend integration.
- This host is intentionally minimal and intended as a migration bridge before a full production host.
