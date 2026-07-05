# Task Plan

## Goal
Define Release 2.3 Phase 5 — Repository Curation and Change-Aware
Indexing — as an implementation-ready roadmap slice that fits the current
Repository Grid, startup refresh, persisted portfolio index, and
Operations workspace architecture without implementing feature code yet.

## Scope

- Reconcile the live startup path (`/api/status` stale + refresh) with the
  persisted portfolio index and existing differential assessment route.
- Specify the curation persistence boundary: stable repo identity,
  operator-authored curation state, mirrored index fields, and
  commit-aware scan metadata.
- Specify UI, API, indexing/cache, startup, and validation requirements
  for Favorites, Portfolio Candidates, Archived/Ignore, and recently
  changed prioritization.
- Update roadmap/planning artifacts only; do not implement backend or
  frontend feature code in this task.

## Phases

| Phase | Status | Notes |
| --- | --- | --- |
| 1. Audit current repo architecture and existing roadmap draft | complete | Confirmed the feature already had a latent Release 2.3 Phase 5 draft, but the official phase table stopped at Phase 4 and the live startup path still does a full `/api/status?refresh=true` scan. |
| 2. Reconcile architecture boundaries for curation + change awareness | complete | Chose stable repo identity plus an operator-authored curation store merged into the portfolio index, rather than treating transient status-cache rows as the source of truth. |
| 3. Update roadmap/planning artifacts with implementation phases | complete | ROADMAP now carries integrated phase-table placement, subphases, data-model/UI/cache sections, and validation criteria for proving unchanged repos are reused. |
| 4. Validate consistency and document outcomes | complete | Planning-only pass complete; no product code changed. |

## Errors Encountered

| Error | Attempt | Resolution |
| --- | --- | --- |
| None | 1 | Planning pass stayed within documentation artifacts; no runtime or verification blocker was encountered. |
