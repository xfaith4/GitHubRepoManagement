// Lane 0.11 — why prompt refinement is unavailable, said precisely.
//
// The banner used to fire on `hasRoadmap` alone while claiming refinement
// "requires a ROADMAP.md with at least one pending item". Two different
// failures therefore produced the same sentence, and one of them was a lie: a
// repository with a full roadmap that simply uses tables instead of checkboxes
// was told it had no roadmap at all. The operator then goes looking for a
// missing file instead of running the repair that would actually help.
//
// Each condition below has a different next action, so each gets its own text.

export interface RefineReadinessInput {
  hasRoadmap: boolean;
  roadmapState?: 'missing' | 'complete' | 'pending' | 'parse-error';
  pendingCount?: number | null;
}

/**
 * The reason refinement cannot run, or null when it can.
 * Ordered most-fundamental first: no file, then an unreadable plan, then a
 * finished one, then a readable plan with nothing left to pick.
 */
export function describeRefineBlocker(entry: RefineReadinessInput | null | undefined): string | null {
  if (!entry) return null;

  if (!entry.hasRoadmap || entry.roadmapState === 'missing') {
    return 'This repository has no ROADMAP.md. Prompt refinement is built from one, so create a roadmap first.';
  }
  if (entry.roadmapState === 'parse-error') {
    return 'This roadmap has no "- [ ] task" checklist items, so there is no task to refine. Run the roadmap repair preview to convert it to the contract format.';
  }
  if (entry.roadmapState === 'complete') {
    return 'Every item on this roadmap is complete, so there is no pending task to refine. Add the next release before dispatching.';
  }
  if ((entry.pendingCount ?? 0) <= 0) {
    return 'This roadmap parsed, but no pending item was found to build a prompt from.';
  }
  return null;
}

export function canRefinePrompt(entry: RefineReadinessInput | null | undefined): boolean {
  return Boolean(entry) && describeRefineBlocker(entry) === null;
}
