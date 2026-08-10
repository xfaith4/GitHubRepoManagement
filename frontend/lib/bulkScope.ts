// Implicit bulk-scope guarding (ROADMAP Lane 0.5).
//
// With no rows selected, the action bar's repo actions apply to the ENTIRE
// filtered set — 75 repositories on a real workspace. The amber callout is
// honest about that, but a banner is not a gate: one click still runs bulk git
// across the whole portfolio.
//
// The decision of WHICH actions deserve friction is a product call, settled
// 2026-08-10: mutating actions always confirm and name the count; read-only ones
// stay one click. A read-only action that cannot damage anything does not earn
// a dialog, and spending the operator's attention on it would train them to
// dismiss the dialog that matters.
//
// Pure on purpose — the component owns `window.confirm`, this owns the rule.

export type BulkActionKind =
  /** `git pull` across the scope — writes to working trees. */
  | 'update'
  /** `git fetch --all --prune` across the scope — writes refs, prunes remotes. */
  | 'sync'
  /** Generates a status report. Reads only. */
  | 'export'
  /** Doc Review inventory + queue planning. Reads only. */
  | 'docreview'
  /** Roadmap index scan. Reads only. */
  | 'roadmap-scan';

/**
 * Actions that change something on disk. Listed by name rather than inferred,
 * so a new bulk action is a deliberate decision on both sides of the line
 * instead of silently defaulting to "no confirmation needed".
 */
const MUTATING_BULK_ACTIONS: readonly BulkActionKind[] = ['update', 'sync'];

const ACTION_LABELS: Record<BulkActionKind, string> = {
  update: 'git pull',
  sync: 'git fetch --all --prune',
  export: 'a status report',
  docreview: 'Doc Review',
  'roadmap-scan': 'a roadmap scan',
};

export function isMutatingBulkAction(action: BulkActionKind): boolean {
  return MUTATING_BULK_ACTIONS.includes(action);
}

/**
 * Whether this click needs an explicit confirmation.
 *
 * Three conditions, all required:
 *  - **Nothing is selected.** An explicit selection is the operator already
 *    naming the scope; re-asking would be friction with no information in it.
 *  - **The action mutates.** Read-only actions stay one click.
 *  - **Something is in scope.** Confirming "this will run on 0 repositories" is
 *    noise, and the buttons are disabled in that state anyway.
 */
export function requiresBulkConfirmation(
  action: BulkActionKind,
  selectionCount: number,
  repoCount: number
): boolean {
  if (selectionCount > 0) return false;
  if (!isMutatingBulkAction(action)) return false;
  return repoCount > 0;
}

/**
 * The confirmation prompt. Names the command and the count, because "are you
 * sure?" without a number is exactly the dialog people learn to click through.
 */
export function bulkConfirmationMessage(action: BulkActionKind, repoCount: number): string {
  const label = ACTION_LABELS[action] ?? 'this action';
  const noun = repoCount === 1 ? 'repository' : 'repositories';
  return `No repositories are selected, so this will run ${label} on all ${repoCount} ${noun} in the current filter.\n\nContinue?`;
}
