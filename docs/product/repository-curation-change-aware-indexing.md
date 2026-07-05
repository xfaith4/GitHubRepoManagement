# Release 2.3 Phase 5 — Repository Curation and Change-Aware Indexing

## Goal

Let operators maintain a curated portfolio subset (`Favorite`,
`Portfolio Candidate`, `Archived / Ignore`) and make startup scan behavior
incremental by default so unchanged repositories are reused from cache
instead of being fully reindexed.

## Why This Is a Real Architectural Slice

- The current Repository Grid boots from `GET /api/status?stale=true`
  followed by `GET /api/status?refresh=true` in
  [frontend/App.tsx](../../frontend/App.tsx).
  That second call is still a full status scan.
- The richer portfolio-aware surfaces already run from the persisted
  portfolio index (`output/index/repos.index.json`) through
  `GET /api/portfolio/assessment` and `GET /api/operations/repos`.
- Curation is operator-authored metadata, not derived scan output. It
  should not live only inside transient status-cache rows.
- The existing differential assessment path already proves that cached-row
  reuse is viable, but it still lacks commit SHA in the status contract and
  still merges repos by repo name in some places.

## Architecture Fit

- Keep scan aggregation centered in
  [Portfolio.Assessment.ps1](../../backend/modules/portfolio/Portfolio.Assessment.ps1)
  and the persisted portfolio index.
- Keep low-cost local signal collection in
  [Adapters.ps1](../../backend/adapters/Adapters.ps1)
  and
  [Start-RepoManagementApiHost.ps1](../../backend/api-host/Start-RepoManagementApiHost.ps1);
  extend that seam instead of creating a second scanner.
- Use the existing stable repo identity seam (`scanFingerprint` /
  local path / GitHub full name -> `repoId`) from
  [Start-RepoManagementApiHost.ps1](../../backend/api-host/Start-RepoManagementApiHost.ps1)
  rather than repo name alone.
- Preserve the current `RepoGrid` UI contract in Phase 5. Prefer backend
  field additions and a thin client mapping layer over a full grid rewrite.

## Implementation Phases

### Phase 5A — Curation Data Model and Persistence Boundary

- Add a stable operator curation store keyed by `repoId`.
- Preferred primary store: SQLite `repo_curation`.
- Acceptable fallback/mirror: `output/index/repo-curation.json`.
- Mirror curation fields into persisted index rows for fast reads:
  `curationState`, `curationUpdatedAt`.
- Also persist scan metadata needed for change-aware reuse:
  `lastIndexedCommitSha`, `lastIndexedCommitDate`, `lastIndexedBranch`,
  `lastScannedAt`, `lastMetadataHash`, `lastScanStatus`, `lastScanError`.

### Phase 5B — Incremental Change-Detection Pipeline

- Extend the status/probe boundary to collect:
  `headCommitSha`, `lastCommitDate`, `branch`, and a lightweight metadata
  hash.
- Compare probe results with cached index metadata per repo.
- Mark each repo:
  `unchanged`, `new-commits`, `metadata-changed`, `needs-rescan`, or
  `scan-failed`.
- Only run full reassessment when:
  - commit SHA changed
  - metadata hash changed
  - cache row is missing
  - cache schema/version is invalid
  - operator forced refresh

### Phase 5C — Route Contracts and Index Merge Behavior

- Extend `GET /api/status` to surface probe fields needed for cache
  decisions and UI change badges.
- Extend `GET /api/portfolio/assessment` so differential startup refresh
  can return reuse/reindex decisions and merged curation state.
- Extend `GET /api/operations/repos` so index-backed rows expose curation
  and change state without frontend recomputation.
- Add an explicit curation write route, preferably repo-scoped:
  `POST /api/operations/repos/{repoId}/curation`
  with body:

```json
{
  "curationState": "none | favorite | portfolio-candidate | archived-ignore"
}
```

- Merge unchanged repos from cached index rows by stable repo identity, not
  by `repoName` alone.

## Execution-Ready API Contract (Detailed)

The following routes are intentionally small-surface additions on existing
contracts so implementation can proceed without broad frontend rewrites.

### 1) Differential assessment read with curation + change state

- Method + path:
  `GET /api/portfolio/assessment?scanMode=differential&includeCuration=true`
- Purpose:
  Return portfolio rows with curation and change-awareness fields, plus
  startup reuse/reindex counters for observability.

Response shape:

```json
{
  "success": true,
  "data": {
    "generatedAt": "2026-07-05T02:30:00Z",
    "cacheSource": "fresh-scan|cache|memory|disk",
    "repos": [
      {
        "repoId": "string",
        "repoName": "string",
        "localPath": "string|null",
        "sourceCoverage": "local|github|local+github",
        "curationState": "none|favorite|portfolio-candidate|archived-ignore",
        "curationUpdatedAt": "ISO-8601|null",
        "changeState": "unchanged|new-commits|metadata-changed|needs-rescan|scan-failed",
        "changedSinceScan": true,
        "headCommitSha": "string|null",
        "headCommitDate": "ISO-8601|null",
        "headBranch": "string|null",
        "lastIndexedCommitSha": "string|null",
        "lastIndexedCommitDate": "ISO-8601|null",
        "lastIndexedBranch": "string|null",
        "lastMetadataHash": "string|null",
        "lastScannedAt": "ISO-8601|null",
        "lastScanStatus": "ok|failed|stale",
        "lastScanError": "string|null",
        "scanDecisionReason": "reused-cache|new-commit|metadata-changed|cache-miss|cache-invalid|forced-refresh"
      }
    ],
    "scanSummary": {
      "reused": 0,
      "reindexed": 0,
      "failed": 0,
      "durationMs": 0
    }
  }
}
```

### 2) Curation write endpoint

- Method + path:
  `POST /api/operations/repos/{repoId}/curation`
- Purpose:
  Persist operator-authored curation state for a repository identity without
  requiring a full reindex.

Request body:

```json
{
  "curationState": "favorite|portfolio-candidate|archived-ignore|none",
  "reason": "optional-string"
}
```

Response body:

```json
{
  "success": true,
  "data": {
    "repoId": "string",
    "curationState": "favorite|portfolio-candidate|archived-ignore|none",
    "updatedAt": "2026-07-05T02:30:00Z"
  }
}
```

### 3) Explicit full refresh endpoint

- Method + path:
  `POST /api/portfolio/assessment/refresh-all`
- Purpose:
  Force full reassessment for all repos (non-default path), with decision
  reasons marked `forced-refresh`.

Request body:

```json
{
  "includeGithub": true,
  "reason": "operator-request"
}
```

Response body:

```json
{
  "success": true,
  "data": {
    "generatedAt": "ISO-8601",
    "scanSummary": {
      "reused": 0,
      "reindexed": 0,
      "failed": 0,
      "durationMs": 0
    }
  }
}
```

### 4) Optional curation list/read endpoint

- Method + path:
  `GET /api/operations/repos/curation`
- Purpose:
  Fetch curation map for UI bootstrap if assessment data is not yet loaded.

Response shape:

```json
{
  "success": true,
  "data": {
    "items": [
      {
        "repoId": "string",
        "curationState": "none|favorite|portfolio-candidate|archived-ignore",
        "updatedAt": "ISO-8601"
      }
    ]
  }
}
```

## Backend Mapping Notes

- Primary aggregation: `Invoke-PortfolioAssessment` and
  `Save-PortfolioIndexArtifacts` in
  [Portfolio.Assessment.ps1](../../backend/modules/portfolio/Portfolio.Assessment.ps1).
- Persistence seam: SQLite capability and table migration paths in
  [Persistence.Store.ps1](../../backend/modules/persistence/Persistence.Store.ps1).
- API route entrypoints: API host route handlers in
  [Start-RepoManagementApiHost.ps1](../../backend/api-host/Start-RepoManagementApiHost.ps1).
- UI consumer surfaces:
  [RepoGrid.tsx](../../frontend/components/RepoGrid.tsx),
  [Dashboard.tsx](../../frontend/components/Dashboard.tsx), and
  [apiClient.ts](../../frontend/services/apiClient.ts).

### Phase 5D — Curation and Change-Aware UI

- Add row-level curation actions in the Repository Grid:
  `Favorite`, `Portfolio Candidate`, `Archived / Ignore`, `Clear`.
- Add grid filters:
  `Favorites only`, `Portfolio Candidates`, `Hide Archived / Ignore`.
- Add change-state badges:
  `New commits`, `Unchanged`, `Needs rescan`, `Scan failed`.
- Add sort/group presets that prioritize:
  1. curated repos
  2. recently changed repos
  3. remaining unchanged inventory

### Phase 5E — Startup Prioritization and Manual Refresh Controls

- Replace the current startup pattern:
  `status stale -> status refresh`
  with:
  1. cached index/ops payload render
  2. background change probe
  3. differential reassessment only for changed repos
- Keep the grid interactive while the probe runs.
- Load curated + recently changed repos first; hydrate the long tail later.
- Keep `Refresh All` explicit and operator-driven; it should bypass
  incremental protections and log `forced-refresh`.

## Data Model Changes

- Stable repo identity:
  `repoId` derived from `scanFingerprint`, else normalized local path,
  else normalized GitHub full name.
- Curation state:
  `none | favorite | portfolio-candidate | archived-ignore`
- Probe/index reuse fields:
  `lastIndexedCommitSha`, `lastIndexedCommitDate`, `lastIndexedBranch`,
  `lastMetadataHash`, `lastScannedAt`
- Per-repo outcome fields:
  `lastScanStatus`, `lastScanError`, `changeState`, `changedSinceScan`

## UI Changes

- Add curation controls to row actions and row details.
- Add curated-only / candidate / ignore suppression filters.
- Add quick filters for `new-commits`, `needs-rescan`, `scan-failed`.
- Make curated + recently changed repos visible before the unchanged
  long-tail inventory finishes hydrating.
- Add explicit `Refresh All` with confirmation copy that it forces a full
  rescan.

## Indexing and Cache Logic Changes

- Add a cheap change probe before full assessment.
- Reuse cached assessment/index rows when commit SHA and metadata hash are
  unchanged.
- Trigger full reassessment only on changed SHA/metadata, cache miss,
  forced refresh, schema mismatch, or invalid/error state.
- Persist per-repo decision reason:
  `reused-cache`, `new-commit`, `metadata-changed`, `forced-refresh`,
  `cache-miss`, `cache-invalid`.
- Surface startup summary counts in API + UI:
  `reused`, `reindexed`, `failed`, `durationMs`.

## Validation Criteria

- With a warm index and no repo changes, ordinary startup logs
  `reused = N`, `reindexed = 0`, and no default full reassessment runs.
- After a new commit lands in exactly one repo, only that repo shows
  `New commits` / `Needs rescan`, and only that repo is fully reindexed.
- Curation selections survive process restart and appear in the Repository
  Grid, Operations view, and persisted index payloads without requiring a
  repo rescan.
- `Refresh All` forces full reassessment and emits `forced-refresh`
  reasons for each reindexed repository.
- Smoke/API coverage fails if unchanged repos are fully reindexed during
  ordinary startup.

## Test Matrix (Phase 5F)

1. Warm-cache no-change startup: verify `reindexed=0` and most repos
  report `changeState=unchanged`.
2. Single-repo new commit: verify exactly one repo reports `new-commits`
  and exactly one repo is reindexed.
3. Metadata-only change (no commit): verify `metadata-changed` path triggers
  selective reindex.
4. Forced refresh: verify all repos emit `scanDecisionReason=forced-refresh`.
5. Curation persistence restart test: verify favorite/candidate/ignore
  states survive process restart and appear in index-backed responses.

## Out of Scope

- Native mobile/offline caching behavior.
- Multi-user sync of favorites across machines.
- GitHub-side labels or stars as a replacement for local curation state.
