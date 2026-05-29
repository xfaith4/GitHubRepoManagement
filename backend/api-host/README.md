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
- `GET /api/portfolio/assessment`
- `POST /api/reconcile`
- `POST /api/docreview/run`
- `GET /api/report/artifacts`
- `GET /api/artifacts/:repoName`
- `GET /api/settings`
- `POST /api/settings`
- `POST /api/init` (accepted placeholder)
- `POST /api/update`
- `POST /api/sync`
- `POST /api/export`
- `GET /api/reports/:reportName`
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
- `GET /health/ready` and `GET /health/dependencies` always return HTTP 200 and surface degraded state in the response payload.
- `GET /api/portfolio/assessment` returns the normalized portfolio lifecycle/readiness model used by Portfolio Mission, Work Queue ranking, and collection reporting.
- `POST /api/export` writes timestamped HTML and CSV reports into the repo-local `reports/` folder. When `portfolioEntries` are provided, it produces a Collection Status Report with lifecycle, blocker, recommended-action, and top-work fields.
- `GET /api/reports/:reportName` serves a saved report file back to the browser so the HTML report can open in a new tab.
- `POST /api/github/status` resolves auth in this order: request token, `GITHUB_TOKEN`, saved fallback token.
- `GET /api/status` includes the configured default GitHub user in response metadata so the frontend can bootstrap GitHub scans without prompting for a token.
- This host is intentionally minimal and intended as a migration bridge before a full production host.
