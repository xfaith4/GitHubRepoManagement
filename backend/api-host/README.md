# API Host

Minimal local PowerShell API host for adapter contracts.

## Script

- `Start-RepoManagementApiHost.ps1`

## Routes

- `GET /health/live`
- `GET /health/ready`
- `GET /health/dependencies`
- `GET /metrics`
- `GET /api/persistence/status`
- Every accepted request has a bounded host deadline (180 seconds by default,
  configurable via `REPO_MGMT_REQUEST_TIMEOUT_SECONDS`, clamped to 30-3600).
  Deadline incidents are appended to
  `output/logs/request-timeouts.jsonl`; the host then exits so the installed
  Shawl/SCM recovery policy can replace the wedged process.
- `GET /api/status`
- `GET /api/portfolio/assessment`
- `GET /api/operations/repos`
- `GET /api/operations/repos/:repoId`
- `POST /api/operations/repos/:repoId/curation`
- `POST /api/operations/prompt/refine`
- `GET /api/operations/prompt/history`
- `GET /api/roadmap/index`
- `GET /api/roadmap/content`
- `POST /api/roadmap/scan`
- `POST /api/roadmap/dispatch/check`
- `POST /api/roadmap/dispatch/execute`
- `POST /api/ai/docs/improve/preview`
- `POST /api/ai/docs/improve/apply`
- `GET /api/ai/docs/improve/history`
- `GET /api/ai/docs/templates`
- `GET /api/agent-runs`
- `GET /api/agent-runs/:runId`
- `POST /api/agent-runs/:runId/refresh`
- `GET /api/merge-readiness/:repoId`
- `POST /api/merge-readiness/:repoId/evaluate`
- `POST /api/merge-readiness/:repoId/merge`
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
- `GET /api/persistence/status` reports the Release 2.1 SQLite persistence layer: provider capability detection (OS-shipped `winsqlite3.dll` on Windows, `libsqlite3` on WSL/Linux/macOS — no external dependency), `output/app.db` bootstrap state, schema tables, and the count of agent-run events mirrored by the dual-write seam. JSON/JSONL stores remain authoritative during the rollout; a missing SQLite provider degrades gracefully.
- `GET /api/portfolio/assessment` returns the normalized portfolio lifecycle/readiness model used by Portfolio Mission, Work Queue ranking, and collection reporting.
- `GET /api/operations/repos` returns the repo-specific indexed portfolio records consumed by the Operations tab, with a warm assessment-cache fallback when the persisted index is not available yet.
- `GET /api/operations/repos/:repoId` returns full Operations detail for one repo, including docs/roadmap audit findings, structure findings, and dispatch context used by the audit findings panel.
- `POST /api/operations/repos/:repoId/curation` persists operator-authored curation state (`none`, `favorite`, `portfolio-candidate`, `archived-ignore`) keyed by stable repo identity; writes primary data to SQLite when available and mirrors to `output/index/repo-curation.json`.
- `POST /api/operations/prompt/refine` builds on the existing `/api/copilot-task/preview` packet, applies operator-directed task/constraint/emphasis refinements, and returns a refined prompt plus warnings for dispatch review while persisting a per-repo refinement record.
- `GET /api/operations/prompt/history` returns the most recent per-repo refinement records written by the prompt-refine route and merges any linked dispatch records written when `/api/roadmap/dispatch/execute` is called with a refinement run ID.
- `POST /api/roadmap/scan` now carries active-release phase-plan rows, release budget-guardrail annotations, and `estimatedSessionWorkUnits` into each roadmap entry when those sections are present in the roadmap template.
- `POST /api/roadmap/dispatch/execute` enforces the Release 2.0 quota guard before any GitHub dependency is required, writes `quota.warning` / `quota.exhausted` telemetry when applicable, records a monitored agent-run ledger entry on successful dispatch, and returns the planning/estimate metadata used for that decision.
- `POST /api/ai/docs/improve/preview` generates a preview-only AI README/ROADMAP improvement (current vs proposed content, change summary, estimated score movement, warnings). Provider selection prefers a configured Anthropic/OpenAI key and degrades to a deterministic offline heuristic provider; no file is ever written by this route. Each preview appends a metadata record to `output/ai-doc-improvements/`.
- `POST /api/ai/docs/improve/apply` writes operator-approved proposed content to the repo's README.md or ROADMAP.md — the only AI documentation route that mutates a file. It backs up the current file to `output/ai-doc-improvements/backups/<repo>/`, writes a restore-metadata JSON (content hashes + ready-to-run restore command), appends an append-only `applied=true` history record, and refuses targets whose file name does not match the doc type.
- `GET /api/ai/docs/improve/history` returns per-repo improvement-cycle metadata records, newest first, with an optional `docType` filter.
- `GET /api/ai/docs/templates` serves the built-in README/ROADMAP improvement templates from `backend/config/ai-doc-templates.json`.
- `GET /api/agent-runs` lists agent-run ledger records (status/repoName filters, newest first, status rollup). Runs are created automatically by `POST /api/roadmap/dispatch/execute`; editable state lives in `output/agent-runs/runs/<runId>.json` and lifecycle history in the append-only `output/agent-runs/events.jsonl` stream with tier-1 metrics per `standards/roadmap/ROADMAP_BUDGET_MODEL.md`.
- `GET /api/agent-runs/:runId` returns one run plus its lifecycle events; 404 for unknown run IDs.
- `POST /api/agent-runs/:runId/refresh` re-queries GitHub for the associated branch, PR, and head-branch Actions state, updates the ledger, and records validation events when the observed Actions conclusion changes.
- `GET /api/merge-readiness/:repoId` returns the stored merge-readiness snapshot for a repo, and the `POST /api/merge-readiness/:repoId/evaluate` / `POST /api/merge-readiness/:repoId/merge` routes keep merge decisions server-gated on a fresh evaluation.
- `GET /api/readme/content` returns README markdown for a repo (or explicit path), used by the Operations repo-detail document viewer.
- `POST /api/export` writes timestamped HTML and CSV reports into the repo-local `reports/` folder. When `portfolioEntries` are provided, it produces a Collection Status Report with lifecycle, blocker, recommended-action, and top-work fields.
- `GET /api/reports/:reportName` serves a saved report file back to the browser so the HTML report can open in a new tab.
- `POST /api/github/status` resolves auth from the environment variable named by `secrets.gitHubTokenEnvVar` (default `GITHUB_TOKEN`), then the `gh` CLI credential. A token supplied in the request body is rejected with `400` — the host never accepts a token over the wire, and never stores one.
- `GET /api/auth/github/status` reports which variable name is configured, whether it resolved in the host's own process, and the environment scope it came from. Add `?validate=1` to spend one GitHub call confirming the token is live and reporting its expiry.
- `GET /api/status` includes the configured default GitHub user in response metadata so the frontend can bootstrap GitHub scans without prompting for a token.
- This host is intentionally minimal and intended as a migration bridge before a full production host.
