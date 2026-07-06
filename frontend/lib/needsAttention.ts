// Shared "Needs Attention" predicate (Release 2.6 Phase 1; extracted to a pure,
// unit-tested module in Release 2.7 Phase D to remove the Dashboard/RepoGrid
// duplication).
//
// "Needs Attention" = a repo with an ACTIONABLE problem. Ambient/baseline
// conditions — no CI configured, a merely-pending roadmap, missing-roadmap /
// needs-doc-standardization, staleness, duplicates, roadmap-flagged — are
// deliberately EXCLUDED so the signal stays a meaningful subset rather than
// ~100% of the portfolio. Those conditions have their own dedicated filters.

export interface NeedsAttentionInput {
  status?: string;
  uncommittedChanges?: number;
  lastBuildStatus?: 'success' | 'failure' | 'in_progress' | 'none';
  dispatchReadiness?: string;
  roadmapState?: 'missing' | 'complete' | 'pending' | 'parse-error';
}

export function isRepoNeedsAttention(repo: NeedsAttentionInput): boolean {
  return (
    repo.status === 'dirty' ||
    (repo.uncommittedChanges ?? 0) > 0 ||
    repo.lastBuildStatus === 'failure' ||
    repo.dispatchReadiness === 'blocked' ||
    repo.dispatchReadiness === 'parse-error' ||
    repo.roadmapState === 'parse-error'
  );
}
