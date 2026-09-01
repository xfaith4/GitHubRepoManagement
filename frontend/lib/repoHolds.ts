// What needs a human, and why (operator decision, 2026-09-01).
//
// The landing screen shows holds, but it must not OPEN as a wall of red — the
// staleness banner was removed for exactly that reason (2026-08-30). So holds
// are sorted into three severities and the view collapses two of them:
//
//   blocking    a hold on a repository that currently occupies an execution
//               lane. Work is already under way and stuck, so this is the one
//               thing a landing screen must never hide. NEVER collapsed.
//   actionable  a real problem with a remedy — dirty tree, CI red, an
//               unparseable roadmap. Collapsed behind a count by default.
//   ambient     a gap that is true of much of the portfolio and blocks nothing
//               right now — no README, no ROADMAP. A quiet list, never styled
//               as an alarm.
//
// The ambient/actionable split is `needsAttention.ts`'s rule, kept: missing
// documentation is deliberately excluded from the attention signal so it stays
// "a meaningful subset rather than ~100% of the portfolio". Showing those gaps
// is useful; showing them as alarms is what makes a console cry wolf.
//
// Every hold carries the rule that produced it AND one sentence in that rule's
// own vocabulary. A badge without its reason is a regression: the operator has
// to be able to read what happened without opening the repository.

import type { OperationsRepoEntry } from '../types';

export type HoldSeverity = 'blocking' | 'actionable' | 'ambient';

export interface RepoHold {
  repoId: string;
  repoName: string;
  /** The rule that produced this hold, named as the rule names itself. */
  rule: string;
  /** One sentence, in the same vocabulary the rule uses. */
  reason: string;
  severity: HoldSeverity;
  /**
   * True when the remedy is destructive or authors a new contract. Such a step
   * is always held for a human and always says so — it is never auto-resolved,
   * regardless of how ready the repository otherwise looks.
   */
  alwaysHeld: boolean;
}

export interface HoldGroups {
  /** Never collapsed. */
  blocking: RepoHold[];
  /** Collapsed behind a count. */
  actionable: RepoHold[];
  /** A quiet list below, never alarm-coloured. */
  ambient: RepoHold[];
}

/**
 * A repository occupying a lane, or explicitly blocked from executing, has
 * work already under way. A hold on it is stopping that work.
 */
function occupiesLane(entry: Partial<OperationsRepoEntry>): boolean {
  return entry.executionState === 'running' || entry.executionState === 'blocked';
}

function holdsFor(entry: Partial<OperationsRepoEntry>): Array<Omit<RepoHold, 'repoId' | 'repoName' | 'severity'> & { ambient: boolean }> {
  const out: Array<Omit<RepoHold, 'repoId' | 'repoName' | 'severity'> & { ambient: boolean }> = [];

  const dirty = entry.localDirtyCount;
  if (typeof dirty === 'number' && dirty > 0) {
    out.push({
      rule: 'working-tree-dirty',
      reason: `${dirty} uncommitted ${dirty === 1 ? 'file' : 'files'} block dispatch. Discarding them is destructive, so this is always held for you.`,
      alwaysHeld: true,
      ambient: false,
    });
  }

  if (entry.latestWorkflowRunConclusion === 'failure') {
    const name = entry.latestWorkflowRunName ? ` (${entry.latestWorkflowRunName})` : '';
    out.push({
      rule: 'ci-red',
      reason: `The latest workflow run${name} concluded failure, so nothing here will merge on green.`,
      alwaysHeld: false,
      ambient: false,
    });
  }

  if (entry.roadmapState === 'parse-error') {
    out.push({
      rule: 'roadmap-parse-error',
      reason: 'ROADMAP.md could not be parsed, so no item in it can be ranked or dispatched.',
      alwaysHeld: false,
      ambient: false,
    });
  }

  if (entry.roadmapState === 'no-checklist') {
    // Sound document, no `- [ ]` items. Never call this damaged — that wording
    // sent operators to repair files that were working correctly.
    out.push({
      rule: 'roadmap-no-checklist',
      reason: 'The roadmap is sound but records no "- [ ]" items, so there is nothing in it to dispatch.',
      alwaysHeld: false,
      ambient: false,
    });
  }

  if (entry.dispatchReadiness === 'blocked') {
    out.push({
      rule: 'dispatch-blocked',
      reason:
        entry.dispatchReadinessExplanation?.trim() ||
        'Dispatch is blocked and the readiness check did not record why — that missing explanation is itself the defect.',
      alwaysHeld: false,
      ambient: false,
    });
  }

  // ---- ambient: true of much of the portfolio, blocking nothing right now ----

  if (entry.roadmapState === 'missing') {
    out.push({
      rule: 'roadmap-missing',
      reason: 'No ROADMAP.md exists. Creating one authors a new contract, so it is always held for your approval.',
      alwaysHeld: true,
      ambient: true,
    });
  }

  if (entry.hasReadme === false) {
    out.push({
      rule: 'readme-missing',
      reason: 'No README.md exists, so an agent has no statement of purpose to work from.',
      alwaysHeld: false,
      ambient: true,
    });
  }

  if (entry.dispatchReadiness === 'needs-doc-standardization') {
    out.push({
      rule: 'needs-doc-standardization',
      reason:
        entry.dispatchReadinessExplanation?.trim() ||
        'Documentation does not yet meet the standard an unattended run relies on.',
      alwaysHeld: false,
      ambient: true,
    });
  }

  return out;
}

export function buildHoldGroups(entries: Array<Partial<OperationsRepoEntry>>): HoldGroups {
  const groups: HoldGroups = { blocking: [], actionable: [], ambient: [] };

  for (const entry of entries) {
    const inLane = occupiesLane(entry);
    for (const hold of holdsFor(entry)) {
      // A lane being stuck outranks the ambient/actionable split: an ambient
      // gap on a repository that is mid-run is no longer ambient, it is the
      // reason the lane is not moving.
      const severity: HoldSeverity = inLane ? 'blocking' : hold.ambient ? 'ambient' : 'actionable';
      groups[severity].push({
        repoId: entry.repoId ?? entry.repoName ?? 'unknown',
        repoName: entry.repoName ?? 'unknown',
        rule: hold.rule,
        reason: hold.reason,
        severity,
        alwaysHeld: hold.alwaysHeld,
      });
    }
  }

  return groups;
}

/** "4 need you" / "1 needs you" — the collapsed summary's own words. */
export function describeHoldCount(count: number): string {
  return count === 1 ? '1 needs you' : `${count} need you`;
}
