# GitHub Repo Management — Roadmap

> Full planning detail: [docs/planning/roadmap.md](docs/planning/roadmap.md)

## Recently Completed

- [x] Unified API host and adapter layer (status, reconcile, doc-review, git ops).
- [x] Dual GitHub inventory adapter (`gh` CLI + direct REST API fallback).
- [x] Structured logging, metrics endpoint, health/dependency checks, retention tooling.
- [x] ROADMAP file scanner — indexes ROADMAP*.md across all local repos; viewer in dashboard.
- [x] Roadmap index cached (TTL 300 s); `/api/roadmap/index`, `/api/roadmap/content`, `/api/roadmap/scan` routes.
- [x] Dashboard ROADMAP badges per repo row; `RoadmapViewerModal` with Scan All and Refresh.
- [x] Single-entrypoint launcher (`Start-App.ps1`, `start-silent.bat`) — hidden background processes, PID tracking.
- [x] Structured operations log (JSONL); `GET /api/log/tail` polled by dashboard Operation Log panel.
- [x] Backend connectivity indicator (`useHealthPing`) shown in dashboard header.
- [x] CI smoke workflow covering module, adapter, and API host smoke tests.

## Active / Next

- [ ] Smoke test coverage for roadmap API routes in `Invoke-ApiHostSmokeTest.ps1`.
- [ ] Document `/api/roadmap/*` and `/api/log/tail` in `docs/reference/contracts.md`.
- [ ] Ops log rolling: cap `operations.jsonl` at 500 lines.

## Near-Term (Must)

- Add incremental scan mode for large root paths (skip unchanged directories).
- Stricter API contract tests for all routes and error categories.
- CI checks for link validation and documentation integrity.

## Mid-Term (Should)

- Phase 2 ROADMAP AI Agent: parse `[x]` tasks, refine via Claude API, enable "Run AI Agent" button.
- Scheduled roadmap scan (`RoadmapScan` task, daily 03:00).
- Expand artifact browser metadata and comparative reconciliation analytics.
- Notification hooks for scheduled-run failures.

## Long-Term (Could)

- Saved operator filters/views persisted in `settings.json`.
- Policy-as-code checks for repository standards enforcement.
- Automate queue-to-workitem Copilot prompt preparation.
