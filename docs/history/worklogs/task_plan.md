# Task Plan

## Goal

Implement Release 2.3 Phase 5D-5F — the remaining repository-curation and
change-aware-indexing slice: curation/decision UI polish with a badge
legend, startup prioritization with an explicit confirm-gated Refresh All
backed by `POST /api/portfolio/assessment/refresh-all`, and observability
plus smoke assertions proving unchanged repositories are reused (not
reindexed) on ordinary startup.

## Scope

- Backend: refresh-all route sharing the assessment handler with forced
  `forced-refresh` decision reasons; `includeCuration=true` merging live
  curation onto assessment entries on both cache-hit and fresh paths; a
  per-scan `scan-summary` observability log line.
- Defect fixes found while surveying 5A-5C: stable `repoId` derivation
  (localPath → GitHub full name → repo name, fingerprint last) so curation
  survives repo changes; parenthesized `[string]` cast in the curation
  index-mirror call that previously persisted a mangled literal.
- Frontend: curation row actions/filters/badges + badge legend + scan
  decision details in RepoGrid; priority-order default sort (favorites →
  candidates → recently changed → unchanged); differential-by-default
  dashboard assessment loads; Refresh All with inline confirmation; Help
  and API-docs copy.
- Smoke: module-smoke curation identity/persistence sections; api-host
  assertions for the curation POST contract, warm-differential
  `reindexed=0` reuse proof, and refresh-all forced-refresh contract.

## Phases

| Phase | Status | Notes |
| --- | --- | --- |
| 1. Survey 5A-5C implementation state | complete | Found curation had no UI consumers, no smoke coverage despite roadmap claims, an unstable fingerprint-first repoId, and a mangled-cast bug in the index mirror. |
| 2. Backend refresh-all + includeCuration + fixes | complete | Route key mapping shares the assessment handler; curation merge helper `Add-PortfolioCurationToAssessments`; scan-summary trace line. |
| 3. Frontend 5D/5E | complete | Curation controls in row Details, quick filters, legend panel, priority sort default, scan-summary line, confirm-gated Refresh All, differential-by-default loads. |
| 4. Smoke 5F | complete | Module-smoke curation sections pass; api-host smoke asserts reuse proof + refresh-all + curation round-trip with cleanup. |
| 5. Verification + docs | complete | Build, tsc (pre-existing errors only), parser checks, module smoke, api-host smoke on alternate port 7099, roadmap validator; ROADMAP/CHANGELOG/progress updated. |

## Errors Encountered

| Error | Attempt | Resolution |
| --- | --- | --- |
| `apiClient.ts` mock `OperationsRepoEntry` missing required `curationState` | 1 | Added `curationState: 'none'` / `curationUpdatedAt: null` to the mock factory. |
| Port 7071 held by the operator's live dev host (pre-change build) | 1 | Ran the api-host smoke on port 7099 instead of killing the operator's instance. |
| First api-host smoke run failed: curated repo missing from refresh-all entries | 2 | Root cause was a Phase 3A-era defect — assessments read `localPath` while status repos expose `path`, so every index row had an empty localPath and fresh-assessment repoIds (`repo:name`) disagreed with index repoIds (`gh:owner/name`). Fixed the field read (+ htmlUrl-derived gh fallback in the curation merge helper); smoke rerun passed with the curation round-trip exercised. Smoke-created curation residue cleaned from DB + mirror. |
