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
- `GET /api/operations/repos`
- `GET /api/operations/repos/:repoId`
- `POST /api/operations/prompt/refine`
- `GET /api/operations/prompt/history`
- `POST /api/ai/docs/improve/preview`
- `GET /api/ai/docs/improve/history`
- `GET /api/ai/docs/templates`
- `GET /api/readme/content`
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
- `GET /api/operations/repos` returns the repo-specific indexed portfolio records consumed by the Operations tab, with a warm assessment-cache fallback when the persisted index is not available yet.
- `GET /api/operations/repos/:repoId` returns full Operations detail for one repo, including docs/roadmap audit findings, structure findings, and dispatch context used by the audit findings panel.
- `POST /api/operations/prompt/refine` builds on the existing `/api/copilot-task/preview` packet, applies operator-directed task/constraint/emphasis refinements, and returns a refined prompt plus warnings for dispatch review while persisting a per-repo refinement record.
- `GET /api/operations/prompt/history` returns the most recent per-repo refinement records written by the prompt-refine route and merges any linked dispatch records written when `/api/roadmap/dispatch/execute` is called with a refinement run ID.
- `POST /api/ai/docs/improve/preview` generates a preview-only AI README/ROADMAP improvement (current vs proposed content, change summary, estimated score movement, warnings). Provider selection prefers a configured Anthropic/OpenAI key and degrades to a deterministic offline heuristic provider; no file is ever written by this route. Each preview appends a metadata record to `output/ai-doc-improvements/`.
- `GET /api/ai/docs/improve/history` returns per-repo improvement-cycle metadata records, newest first, with an optional `docType` filter.
- `GET /api/ai/docs/templates` serves the built-in README/ROADMAP improvement templates from `backend/config/ai-doc-templates.json`.
- `GET /api/readme/content` returns README markdown for a repo (or explicit path), used by the Operations repo-detail document viewer.
- `POST /api/export` writes timestamped HTML and CSV reports into the repo-local `reports/` folder. When `portfolioEntries` are provided, it produces a Collection Status Report with lifecycle, blocker, recommended-action, and top-work fields.
- `GET /api/reports/:reportName` serves a saved report file back to the browser so the HTML report can open in a new tab.
- `POST /api/github/status` resolves auth in this order: request token, `GITHUB_TOKEN`, saved fallback token.
- `GET /api/status` includes the configured default GitHub user in response metadata so the frontend can bootstrap GitHub scans without prompting for a token.
- This host is intentionally minimal and intended as a migration bridge before a full production host.
