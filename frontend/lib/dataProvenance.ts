// Shared data-provenance reconciliation.
//
// The portal reads from two independent sources that can legitimately disagree:
//
//   1. The LIVE workspace scan (`repos`) — what exists on disk right now.
//   2. The PERSISTED indexes in `output/index/` (doc-readiness audit, roadmap
//      audit, portfolio assessment/trend) — written by whichever scan last
//      completed, and deliberately append-only so history survives.
//
// When a live scan returns 0 repositories but the persisted indexes still hold
// entries from an earlier run, the UI would otherwise show "0 repos" in the
// header next to populated maturity buckets and a "68% Avg Maturity" KPI — the
// figures are all real, but presenting them side by side without provenance
// reads as the tool contradicting itself. These helpers classify that state so
// every consumer labels it the same way instead of each view guessing.

export type ProvenanceState =
  /** Live scan found repos — persisted figures are same-generation. */
  | 'live'
  /** Live scan found nothing, but persisted indexes hold earlier results. */
  | 'stale-only'
  /** Nothing anywhere — a genuine first-run empty state. */
  | 'empty';

export interface ProvenanceInput {
  /** Repo count from the current scan (the `repos` prop). */
  liveRepoCount: number;
  /** Entry count in the persisted index backing the figures being shown. */
  persistedEntryCount: number;
  /** ISO timestamp the persisted index was generated, when known. */
  persistedGeneratedAt?: string | null;
}

export interface Provenance {
  state: ProvenanceState;
  /**
   * True only for 'stale-only' — the case where displayed figures describe a
   * different repo set than the header count. Consumers must show provenance.
   */
  isMismatch: boolean;
  /** Operator-facing explanation, or null when there is nothing to explain. */
  message: string | null;
}

/**
 * Classify the relationship between the live scan and a persisted index.
 *
 * `formatTimestamp` is injected so the sentence stays deterministic under test;
 * callers pass a locale formatter.
 */
export function resolveProvenance(
  input: ProvenanceInput,
  formatTimestamp: (iso: string) => string = iso => iso
): Provenance {
  // An unknown live count must never produce a warning — a false "carried-over
  // data" banner over correct figures is worse than no banner at all.
  if (!Number.isFinite(input.liveRepoCount)) {
    return { state: 'live', isMismatch: false, message: null };
  }

  const live = Math.max(0, input.liveRepoCount);
  const persisted = Number.isFinite(input.persistedEntryCount)
    ? Math.max(0, input.persistedEntryCount)
    : 0;

  if (live > 0) {
    return { state: 'live', isMismatch: false, message: null };
  }

  if (persisted === 0) {
    return { state: 'empty', isMismatch: false, message: null };
  }

  const when = input.persistedGeneratedAt
    ? formatTimestamp(input.persistedGeneratedAt)
    : null;
  const suffix = when ? ` (last completed scan: ${when})` : ' (from the last completed scan)';

  return {
    state: 'stale-only',
    isMismatch: true,
    message:
      `The current scan found no repositories, so the ${persisted} ` +
      `${persisted === 1 ? 'entry' : 'entries'} below are carried over from earlier run data${suffix}. ` +
      'They may no longer match the workspace — re-scan to reconcile.',
  };
}

/**
 * Whether repo-acting bulk operations (Pull / Fetch / Report / Doc Review /
 * Roadmap Scan) can do anything. With no repositories in scope these are no-ops
 * at best, so they are disabled and the operator is pointed at the real blocker
 * instead of being allowed to click into nothing.
 *
 * Deliberately excludes navigational/recovery controls (Refresh, Settings,
 * Help, API docs) — those are the escape hatch out of the empty state.
 */
export function canRunRepoActions(liveRepoCount: number, isActionRunning: boolean): boolean {
  return liveRepoCount > 0 && !isActionRunning;
}

/** Hint explaining why repo actions are unavailable, or null when they are. */
export function repoActionsBlockedReason(liveRepoCount: number): string | null {
  return liveRepoCount > 0
    ? null
    : 'No repositories are in scope. Scan a workspace first — set the workspace path in Settings, then Refresh.';
}
