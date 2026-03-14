# Product Roadmap

Updated: 2026-03-13

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

## Active / Next

- [ ] Add smoke test coverage for roadmap API routes (`/api/roadmap/index`, `/api/roadmap/content`, `/api/roadmap/scan`) in `Invoke-ApiHostSmokeTest.ps1`.
- [ ] Document `/api/roadmap/*` and `/api/log/tail` routes in `docs/reference/contracts.md`.
- [ ] Ops log rolling: cap `operations.jsonl` at 500 lines to prevent unbounded growth on long-running instances.

## Near-Term Priorities (Must)

- Add incremental scan mode for large root paths (skip unchanged directories).
- Add stricter API contract tests for all routes and error categories (validation, timeout, dependency failure categories).
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
- [ ] Check for stale `evidence/baseline/` artifacts older than 30 days; run `Invoke-RetentionCleanup.ps1`.
- [ ] Assess open technical debt items; promote to active or close each one.

## Definition of Done for New Features

- Route/module behavior documented in docs.
- Contract updates reflected in `docs/reference/contracts.md`.
- Smoke or regression test coverage added or updated.
- Structured logs and metric hooks included.
- Roadmap item marked complete with date.

You are a senior backend and performance engineer specializing in local tooling, inventory systems, caching, and operator dashboards.

Your task is to redesign repository scanning in this application so the dashboard is usable immediately on launch, while backend inventory remains fresh over time.

## User intent

The current repo scan takes too long across my workspace. The page should not sit there feeling dead while it crawls the filesystem.

I want:

1. cached repo inventory available immediately when the dashboard loads,
2. backend refresh to continue in the background,
3. the UI to show the last known good data right away,
4. the cache to stay updated without forcing a full cold scan every time.

## Known repo context you must respect

- The app already performs local repository discovery and git metadata scanning.
- Scan cost across large workspace roots is a known architectural risk.
- The roadmap/backlog already mentions incremental scan mode to reduce full traversal cost.
- The architecture favors persisted artifacts/cache on disk for expensive operations.
- This is a Windows-first local tool, not a cloud service.

## Core objective

Implement a cache-first inventory model with background refresh.

The dashboard should:

- load quickly from persisted cache or last snapshot,
- clearly indicate the age/freshness of cached data,
- continue receiving backend updates as the refresh progresses,
- remain usable even while a full scan is running.

## Required behavior

### 1. Cache-first startup

On app/API start or initial dashboard load:

- return the latest cached inventory snapshot immediately if one exists,
- include metadata such as:
  - generatedAt
  - scanStartedAt / scanCompletedAt
  - cacheAge
  - scanStatus
  - partial/full snapshot indicator

### 2. Background refresh

A backend refresh process should update inventory asynchronously:

- start automatically when appropriate,
- avoid blocking initial page usability,
- publish progress/events to the dashboard operation log or status surface,
- safely update the cache when complete.

### 3. Incremental refresh strategy

Avoid unnecessary full rescans when possible.

Evaluate and implement the best realistic model for this repo, such as:

- root-level directory snapshot and delta detection,
- per-repo cached metadata with targeted refresh,
- background staged refresh (shallow first, deep second),
- time-based freshness policy,
- optional manual “force full rescan” action

If true incremental correctness is too large for one pass, implement the best coherent stepwise version and update the roadmap accordingly.

### 4. Stable persisted cache

Persist cache on disk in a clean, inspectable format.

Consider:

- JSON snapshot(s)
- state file(s) per workspace root
- summary index + per-repo detail cache
- cache versioning/schema marker

The cache must be robust against:

- interrupted scans
- stale or partial data
- path removals
- git command failures on individual repos

### 5. Usable UI state model

The dashboard should distinguish between:

- cached data loaded
- refresh in progress
- refresh completed
- refresh failed
- no cache yet / first run

It should never feel frozen just because scanning is expensive.

## Investigation scope

Inspect and understand:

- current scan/inventory API flow
- current repo model/schema
- current settings and workspace path handling
- any existing metrics/logging around scans
- operation log integration opportunities
- any existing artifact/cache/output directories or conventions

## Implementation expectations

You must:

- add backend cache read/write logic,
- add a freshness/status contract to the relevant API response,
- run refresh asynchronously instead of blocking the first useful response,
- update frontend state handling so cached data appears immediately,
- surface refresh progress in the dashboard,
- document cache behavior and manual refresh semantics

## Preferred architecture

Favor a design like this unless repo realities strongly suggest otherwise:

- `inventory cache service`
  - load last snapshot
  - validate schema/version
  - expose quick status
- `scan orchestrator`
  - determine whether refresh is needed
  - run background scan
  - update operation log/progress
  - atomically publish new snapshot
- `frontend`
  - render cached snapshot immediately
  - subscribe/poll for refresh status changes
  - refresh table/cards when new snapshot is ready

## Quality constraints

The cache system must:

- never corrupt the last known good snapshot
- use atomic write/rename for snapshot replacement when practical
- preserve usable data if a refresh crashes midway
- tolerate missing/inaccessible roots gracefully
- not require GitHub API availability for local inventory usefulness

## UX constraints

The user should be able to open the app and immediately:

- see existing repo data,
- filter and browse,
- know whether the displayed data is cached or freshly refreshed,
- manually trigger refresh if desired

## Nice-to-have behavior

If practical, add:

- refresh debounce/cooldown to avoid redundant full scans,
- separate shallow inventory vs full metadata refresh,
- last scan duration and repo count stats,
- stale-data banner if cache age exceeds threshold,
- a manual “force rescan” option distinct from normal refresh

## Deliverables

Produce:

1. backend cache implementation and scan orchestration changes,
2. API response changes for cache/freshness/refresh status,
3. frontend changes for instant-load + background-refresh UX,
4. documentation updates,
5. a short summary covering:
   - previous bottleneck
   - caching strategy chosen
   - refresh strategy chosen
   - remaining scale risks or next hardening steps

## Guardrails

Do not:

- keep the dashboard blocked on a full scan before rendering useful data,
- fake freshness without exposing timestamps/status,
- overwrite good cache data with incomplete or failed scan results,
- implement an overcomplicated database solution unless the repo clearly needs it,
- leave the cache contract undocumented.

## Decision rule

Prefer a simple, durable cache-first model that materially improves startup usability now, with room for future incremental-scan hardening.

Begin by auditing the existing scan path, data model, and response flow, then implement a cache-backed immediate-load + background-refresh solution.

You are a senior full-stack engineer, local tooling architect, and Windows-first operator-experience specialist working inside this repository.

Your task is to harden the GitHubRepoManagement application in two major ways:

1. eliminate the need for two visible terminal windows to run the app,
2. make repository data available immediately through cache-first loading with background refresh.

Treat this as a coordinated runtime/UX/backend hardening pass, not two disconnected tweaks.

## User intent

Today the app feels rough because:
- it depends on separate backend/frontend terminal windows,
- terminal activity is outside the app instead of inside the dashboard,
- initial repository scanning takes too long and blocks usability.

I want the app to behave more like a unified operator tool:
- one launcher,
- optional silent/background runtime,
- dashboard-native operation log,
- cached repo data available immediately,
- backend refresh continuing in the background.

## Repo-aware context

Use the repository’s current docs and code reality to guide implementation:
- current startup flows and scripts
- operation log/log panel behavior
- current API host behavior
- current inventory scan behavior
- current structured logging/metrics/health direction
- known placeholder/streaming gaps
- roadmap/backlog items related to incremental scan, observability, and operationalization

## Primary goals

### Goal A — Startup/runtime unification

- one command or launcher starts the app
- no normal-path dependence on two visible consoles
- backend and frontend can run hidden/backgrounded where feasible on Windows
- debug mode remains available for developers

### Goal B — Dashboard-native runtime telemetry

- all meaningful activity appears in the dashboard `Operation Log`
- startup, readiness, operations, warnings, and failures are surfaced there
- replace placeholder/unwired log behavior with a real backend-driven mechanism

### Goal C — Cache-first repository inventory

- last known good repo inventory loads immediately
- backend continues background refresh
- UI remains usable during refresh
- freshness state is visible and honest

## Required execution order

### Phase 1 — Audit current state

Inspect:
- startup scripts and package scripts
- backend host startup and routing
- frontend log panel and status loading flow
- current scan/inventory pipeline
- settings/config for workspace roots and ports
- any existing output/cache/log folders and conventions

### Phase 2 — Runtime/logging hardening

Implement:
- single launcher strategy
- silent/background mode where feasible
- explicit debug mode
- backend event/log transport for dashboard operation log
- structured event model
- startup readiness visibility

### Phase 3 — Cache-first scan hardening

Implement:
- persisted inventory snapshot cache
- immediate return of cached data
- asynchronous refresh pipeline
- refresh progress/status events
- atomic cache update behavior
- UI freshness indicators

### Phase 4 — UX and docs completion

Update:
- operation log UX
- startup instructions
- silent/debug mode instructions
- cache and refresh behavior docs
- any roadmap items that should reflect new operational review/hardening work

## Required contracts

### Operation log event shape

Prefer a structured schema including:
- timestamp
- level
- component
- operation
- correlationId
- message
- details

### Inventory/status response shape

Expose fields such as:
- data source: cache | live | partial
- generatedAt
- scanStatus
- refreshInProgress
- lastSuccessfulScanAt
- cacheAgeSeconds
- repoCount
- warnings/errors if degraded

## Windows-specific expectations

Favor stable Windows process orchestration patterns over clever but fragile tricks.
Use hidden child processes only when reliable.
If one runtime cannot safely run hidden in a robust way, implement the best pragmatic fallback and document it clearly.

## Quality bar

Your implementation must:
- materially improve startup ergonomics
- materially improve first-render usability
- not lose logs when running silently
- not corrupt cache snapshots
- not leave placeholder endpoints or half-integrated UI behavior
- preserve developer operability

## Deliverables

Produce:
1. concrete code changes,
2. launcher/runtime updates,
3. backend logging/event updates,
4. backend cache/refresh updates,
5. frontend updates for operation log and cache-aware loading,
6. documentation updates,
7. a concise implementation summary in this format:

### Runtime/startup changes

### Operation log changes

### Cache/refresh changes

### UX changes

### Docs/roadmap changes

### Remaining risks / next hardening opportunities

## Guardrails

Do not:
- leave the user dependent on two visible shell windows,
- keep terminal output as the primary observability surface,
- block first render on full repo scan,
- fake cache freshness,
- overwrite good cache with failed scan output,
- stop at analysis only.

Make the best coherent end-to-end implementation you can in one pass, prioritizing reliability, usability, and closure.
