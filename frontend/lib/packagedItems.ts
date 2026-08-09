// Packaged roadmap-item approval queue (Release 2.7 Phase C, operator UI).
//
// A scheduled packaging run stops at the approval gate: it ranks each curated
// repo's pending roadmap work, packages the top item, and queues it. Until this
// module existed, approving one meant POSTing to
// /api/automation/packages/approve by hand — the loop worked but the queue was
// less discoverable than a doc-improve preview sitting in the AI Docs panel.
//
// The state machine is defined server-side in Test-PackagedItemTransition and
// mirrored here. Mirrored, not reinvented: the UI must never offer an action
// the backend will refuse with a 409, and must never hide one it would allow.

export type PackagedItemStatus =
  | 'pending-approval'
  | 'approved'
  | 'dispatched'
  | 'dispatch-failed'
  | 'rejected';

export interface PackagedItemPacket {
  packetId?: string;
  repoName?: string;
  repoPath?: string;
  roadmapPath?: string;
  githubRepo?: string;
  branch?: string;
  baseBranch?: string;
  maturityLevel?: string;
  curationState?: string;
  itemText?: string;
  itemSection?: string;
  valueScore?: number;
  valueTier?: string;
  valueRationale?: string[];
  estimatedWorkUnits?: number;
  generatedPrompt?: string;
  repairPlan?: Record<string, unknown> | null;
  dispatchTarget?: string;
}

export interface PackagedItemHistoryEntry {
  status?: string;
  at?: string;
  actor?: string;
  note?: string;
}

export interface PackagedItem {
  packetId: string;
  runId?: string;
  repoName?: string;
  status: string;
  packagedAt?: string;
  updatedAt?: string;
  updatedBy?: string;
  note?: string;
  dispatchRunId?: string;
  packet?: PackagedItemPacket | null;
  history?: PackagedItemHistoryEntry[];
}

/**
 * Which statuses may follow a given one.
 *
 * Byte-for-byte the `$allowed` map in `Test-PackagedItemTransition`
 * (backend/modules/automation/Automation.RoadmapPackaging.ps1). `dispatched`
 * and `rejected` are terminal — that is what stops a packet being dispatched
 * twice — and an unrecognized status allows nothing, so the UI opts in the same
 * way packaging scope does rather than defaulting to "probably fine".
 */
const ALLOWED_TRANSITIONS: Record<string, readonly string[]> = {
  'pending-approval': ['approved', 'rejected', 'pending-approval'],
  approved: ['dispatched', 'dispatch-failed'],
  'dispatch-failed': ['approved', 'rejected'],
  dispatched: [],
  rejected: [],
};

/** True when the backend would accept this transition. */
export function canTransition(from: string | undefined | null, to: string): boolean {
  if (!from) return false;
  const allowed = ALLOWED_TRANSITIONS[from];
  if (!allowed) return false;
  return allowed.includes(to);
}

/** True when the operator may approve (and thereby dispatch) this packet. */
export function canApprove(item: Pick<PackagedItem, 'status'> | null | undefined): boolean {
  return canTransition(item?.status, 'approved');
}

/** True when the operator may reject this packet. */
export function canReject(item: Pick<PackagedItem, 'status'> | null | undefined): boolean {
  return canTransition(item?.status, 'rejected');
}

export type PackagedItemSeverity = 'pending' | 'ok' | 'error' | 'muted';

export interface PackagedItemStatusView {
  label: string;
  severity: PackagedItemSeverity;
  /** One sentence stating what state the work is actually in. */
  detail: string;
}

/**
 * Label a packet's status honestly.
 *
 * `dispatched` deliberately does NOT read as "done": approval enqueues to the
 * operator runner, so the work reaches a branch with committed changes awaiting
 * review — not an open PR, and never a merge. A badge reading "Complete" here
 * would be the decorative-badge failure the roadmap's guardrails forbid.
 */
export function describePackagedItemStatus(status: string | undefined | null): PackagedItemStatusView {
  switch (status) {
    case 'pending-approval':
      return {
        label: 'Awaiting approval',
        severity: 'pending',
        detail: 'Packaged and priced against the budget guard. Nothing runs until you approve it.',
      };
    case 'approved':
      return {
        label: 'Approved',
        severity: 'ok',
        detail: 'Approved but not yet enqueued for the operator runner.',
      };
    case 'dispatched':
      return {
        label: 'Queued for the runner',
        severity: 'ok',
        detail: 'Enqueued for Invoke-RoadmapTaskRunner.ps1 in your session. It stops at a reviewed branch — nothing is pushed or merged.',
      };
    case 'dispatch-failed':
      return {
        label: 'Dispatch failed',
        severity: 'error',
        detail: 'Approved, but enqueueing failed. Retry the approval once the cause is fixed.',
      };
    case 'rejected':
      return {
        label: 'Rejected',
        severity: 'muted',
        detail: 'Rejected by an operator. The packet is closed and will not be dispatched.',
      };
    default:
      return {
        label: status ? `Unknown (${status})` : 'Unknown',
        severity: 'muted',
        detail: 'This packet is in a state the console does not recognize; no action is offered.',
      };
  }
}

/**
 * Sort the queue so what needs a decision is first.
 *
 * Within a group, newest-first — a stale packet that was never approved should
 * not push today's ranked work below the fold.
 */
export function sortPackagedItems(items: readonly PackagedItem[]): PackagedItem[] {
  const rank = (item: PackagedItem): number => {
    if (item.status === 'pending-approval') return 0;
    if (item.status === 'dispatch-failed') return 1;
    if (item.status === 'approved') return 2;
    if (item.status === 'dispatched') return 3;
    return 4;
  };
  return [...items].sort((a, b) => {
    const byRank = rank(a) - rank(b);
    if (byRank !== 0) return byRank;
    return String(b.packagedAt ?? '').localeCompare(String(a.packagedAt ?? ''));
  });
}

/** How many packets are waiting on an operator decision. */
export function countAwaitingDecision(items: readonly PackagedItem[]): number {
  return items.filter(item => canApprove(item)).length;
}
