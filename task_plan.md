# Task Plan

## Goal
Start Release 2.3 (Portfolio Analytics, Trend Visualization, and
Distribution) in a truthful way: define the release's first bounded phase
in the roadmap and ship a forward-compatible analytics scaffold that gives
operators a visible portfolio-trend surface now without pretending the full
90-day history pipeline already exists.

## Scope

- Roadmap planning: add a Release 2.3 phase plan that acknowledges the real
  dependency on Release 2.1 history capture while still defining a useful
  Phase 1 scaffold.
- Backend scaffold: add a typed `GET /api/portfolio/trend` route and
  supporting analytics helper that can serve current-snapshot rollups now
  and transparently expand to history-backed trends later.
- Frontend scaffold: add a dashboard analytics panel that consumes the new
  route, renders portfolio-level trend/health data, and explains when only
  a current snapshot is available.
- Validation/docs: wire the route into API docs and smoke coverage; keep the
  scaffold additive and avoid broad persistence or digest-distribution work.

## Phases

| Phase | Status | Notes |
| --- | --- | --- |
| 1. Reconcile Release 2.3 with live code and dependencies | complete | 2.3 has roadmap text only; the real dependency is 2.1 history capture, but a current-snapshot analytics scaffold is still feasible now. |
| 2. Update planning artifacts for the active slice | complete | Repointed the working plan from the finished Release 1.2 work to Release 2.3 Phase 1 scaffold. |
| 3. Implement analytics scaffold | complete | Added the analytics helper/module, `GET /api/portfolio/trend`, typed client, API docs entry, dashboard panel, and repo sparkline rendering with current-snapshot fallback messaging. |
| 4. Validation and roadmap state update | complete | `npm run build`, API-host smoke, and frontend smoke all passed; roadmap + planning artifacts now record the scaffold truthfully. |

## Errors Encountered

| Error | Attempt | Resolution |
| --- | --- | --- |
| Frontend smoke false-negative on the analytics panel | 1 | The panel rendered, but the probe used global text locators against repeated `Avg Maturity` labels. Scoped the Playwright assertions to the `Portfolio Analytics` section and reran smoke successfully. |
