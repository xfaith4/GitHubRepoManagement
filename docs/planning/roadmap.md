# Product Roadmap

Updated: 2026-03-15

This roadmap tracks forward work for the current standalone GitHub Repo Management platform.

Cross-reference:

- [Architecture](../architecture/architecture.md)
- [Platform Status](platform-status.md)
- [Features](../reference/features.md)
- [Contracts](../reference/contracts.md)

## Recently Completed

- [x] Unified API host and adapter layer (status, reconcile, doc-review, git ops).
- [x] Dual GitHub inventory adapter (`gh` CLI + direct REST API fallback).
- [x] Structured logging, metrics endpoint, health/dependency checks, retention tooling.
- [x] ROADMAP file scanner — indexes ROADMAP*.md across all local repos; viewer in dashboard.
- [x] Roadmap index cached (TTL 300 s, memory + disk); `/api/roadmap/index`, `/api/roadmap/content`, `/api/roadmap/scan` routes.
- [x] Dashboard ROADMAP badges per repo row; `RoadmapViewerModal` with Scan All and Refresh.
- [x] Single-entrypoint launcher (`Start-App.ps1`, `start-silent.bat`) — hidden background processes, PID tracking, `Stop-App.ps1`.
- [x] Structured operations log (JSONL) emitted by API host; `GET /api/log/tail` polled by dashboard.
- [x] Dashboard Operation Log panel fed by real backend events via `useBackendLog` polling hook.
- [x] Backend connectivity indicator (`useHealthPing`) shown in dashboard header.
- [x] CI smoke workflow (`ci-smoke.yml`) covering module, adapter, and API host smoke tests.
- [x] Roadmap task automation scripts: `scripts/Start-RoadmapCopilotTask.ps1` and `scripts/Start-GitHubCopilotTask.ps1` with `-PreviewOnly` mode.
- [x] Persistent roadmap task history and API call logging written under `output/roadmap-task-history/` (`history.jsonl`, per-run events and summaries).
- [x] New API routes for roadmap task automation and history: `POST /api/roadmap-agent/preview`, `POST /api/roadmap-agent/start`, `GET /api/roadmap-agent/history`.
- [x] `RoadmapViewerModal` UI now supports previewing and starting roadmap tasks plus viewing recent roadmap task history.
- [x] Local status scanning now captures `lastCommitMessage`, `lastCommitAuthor`, `commitsLastWeek`, and `commitsLastMonth`.
- [x] GitHub status route now computes open PR counts via GitHub search (API and gh paths) instead of returning hardcoded zero.
- [x] Status cache schema versioning added to invalidate stale cache payloads after contract expansion.
- [x] Dedicated API contract test suite added for route success envelopes, validation failures, and error category handling.

## Active / Next

- [x] Add smoke test coverage for roadmap API routes (`/api/roadmap/index`, `/api/roadmap/content`, `/api/roadmap/scan`) in `Invoke-ApiHostSmokeTest.ps1`.
- [ ] Add smoke test coverage for roadmap-agent routes (`/api/roadmap-agent/preview`, `/api/roadmap-agent/start`, `/api/roadmap-agent/history`).
- [ ] Ops log rolling: cap `operations.jsonl` at 500 lines to prevent unbounded growth on long-running instances.

## Near-Term Priorities (Must)

- Add incremental scan mode for large root paths (skip unchanged directories).
- Maintain strict API contract tests for route envelopes and error categories (validation, timeout, dependency, internal).
- Add CI checks for link validation and documentation integrity.

## Mid-Term Priorities (Should)

- Phase 2 ROADMAP AI Agent: parse confirmed `[x]` tasks, call Claude API, return refined PR description; enable "Run AI Agent" button in `RoadmapViewerModal`.
- Scheduled roadmap scan via `Register-ScheduledTasks.Template.ps1` (`RoadmapScan` task, daily 03:00).
- Expand artifact browser metadata (retention days, size trend, run correlation ID).
- Add comparative reconciliation run analytics.
- Notification hooks for scheduled-run failures (webhook or email).

## Long-Term Priorities (Could)

- Saved operator filters/views persisted in `settings.json`.
- Policy-as-code checks for repository standards enforcement.
- Automate queue-to-workitem Copilot prompt preparation with paged dispatch outputs.

## Technical Debt

- Reduce duplication between status scan and reconciliation scan paths (share repo enumeration logic).
- Add stronger schema validation for doc-review queue/batch outputs.
- Normalize historical evidence layout and lifecycle conventions.
- Frontend: `Clone (Planned)` and `Archive (Planned)` buttons are permanently disabled — implement or remove.
- `Invoke-DocReviewExecution.ps1` Validate and Complete modes throw "not implemented" — document scope or roadmap.

## Operational Review Process

### Weekly

- [ ] Run full smoke suite: `Invoke-ModuleSmokeTest`, `Invoke-AdapterSmokeTest`, `Invoke-ApiHostSmokeTest`.
- [ ] Confirm `docs/planning/roadmap.md` reflects actual codebase state (no phantom checkmarks).
- [ ] Review `backend/modules/output/logs/operations.jsonl` for unexpected ERROR entries.

### On every feature merge

- [ ] Smoke test added or updated for the new route/module.
- [ ] `docs/reference/contracts.md` updated if a route was added or changed.
- [ ] Roadmap item moved to "Recently Completed" with the merge date.

### Monthly

- [ ] Review `docs/planning/platform-status.md` — update version, key metrics, known issues.
- [ ] Check for stale generated artifacts under `output/` and `backend/modules/output/`; run `Invoke-RetentionCleanup.ps1`.
- [ ] Assess open technical debt items; promote to active or close each one.

## Definition of Done for New Features

- Route/module behavior documented in docs.
- Contract updates reflected in `docs/reference/contracts.md`.
- Smoke or regression test coverage added or updated.
- Structured logs and metric hooks included.
- Roadmap item marked complete with date.
