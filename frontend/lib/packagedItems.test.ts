import { describe, it, expect } from 'vitest';
import {
  canApprove,
  canReject,
  canTransition,
  countAwaitingDecision,
  describePackagedItemStatus,
  sortPackagedItems,
  groupPackagedItemAttempts,
  type PackagedItem,
} from './packagedItems';

const item = (status: string, packagedAt = '2026-08-09T10:00:00Z'): PackagedItem => ({
  packetId: `pkt-${status}-${packagedAt}`,
  status,
  packagedAt,
});

describe('canTransition — mirrors Test-PackagedItemTransition', () => {
  it('allows approve and reject only from pending-approval', () => {
    expect(canTransition('pending-approval', 'approved')).toBe(true);
    expect(canTransition('pending-approval', 'rejected')).toBe(true);
  });

  // The invariant the backend 409s on: a dispatched packet is terminal, so it
  // must never be dispatchable a second time from the UI either.
  it('treats dispatched and rejected as terminal', () => {
    expect(canTransition('dispatched', 'approved')).toBe(false);
    expect(canTransition('dispatched', 'rejected')).toBe(false);
    expect(canTransition('rejected', 'approved')).toBe(false);
  });

  it('allows a retry after a failed dispatch', () => {
    expect(canTransition('dispatch-failed', 'approved')).toBe(true);
    expect(canTransition('dispatch-failed', 'rejected')).toBe(true);
  });

  it('does not let an approved packet be approved again', () => {
    expect(canTransition('approved', 'approved')).toBe(false);
  });

  // Opt in, never opt out: an unrecognized status offers nothing rather than
  // being treated as probably-safe.
  it('offers nothing for an unknown or missing status', () => {
    expect(canTransition('half-baked', 'approved')).toBe(false);
    expect(canTransition('', 'approved')).toBe(false);
    expect(canTransition(undefined, 'approved')).toBe(false);
  });
});

describe('canApprove / canReject', () => {
  it('gates the buttons on the same matrix the backend enforces', () => {
    expect(canApprove(item('pending-approval'))).toBe(true);
    expect(canReject(item('pending-approval'))).toBe(true);
    expect(canApprove(item('dispatched'))).toBe(false);
    expect(canReject(item('dispatched'))).toBe(false);
    expect(canApprove(null)).toBe(false);
  });
});

describe('describePackagedItemStatus', () => {
  // Guardrail: approval enqueues to the operator runner, which stops at a
  // reviewed branch. A "done"/"merged" label here would be a decorative badge
  // claiming something the system never did.
  it('does not describe a dispatched packet as complete or merged', () => {
    const view = describePackagedItemStatus('dispatched');
    expect(view.severity).toBe('ok');
    expect(view.label.toLowerCase()).not.toMatch(/done|complete|merged/);
    expect(view.detail).toMatch(/nothing is pushed or merged/i);
  });

  it('marks a pending packet as needing a decision', () => {
    expect(describePackagedItemStatus('pending-approval').severity).toBe('pending');
  });

  it('marks a failed dispatch as an error', () => {
    expect(describePackagedItemStatus('dispatch-failed').severity).toBe('error');
  });

  it('names an unrecognized status instead of guessing', () => {
    const view = describePackagedItemStatus('weird');
    expect(view.label).toContain('weird');
    expect(view.severity).toBe('muted');
  });
});

describe('sortPackagedItems', () => {
  it('puts what needs a decision first, then newest within a group', () => {
    const sorted = sortPackagedItems([
      item('dispatched', '2026-08-09T12:00:00Z'),
      item('pending-approval', '2026-08-09T09:00:00Z'),
      item('rejected', '2026-08-09T13:00:00Z'),
      item('pending-approval', '2026-08-09T11:00:00Z'),
      item('dispatch-failed', '2026-08-09T08:00:00Z'),
    ]);
    expect(sorted.map(i => i.status)).toEqual([
      'pending-approval',
      'pending-approval',
      'dispatch-failed',
      'dispatched',
      'rejected',
    ]);
    expect(sorted[0].packagedAt).toBe('2026-08-09T11:00:00Z');
  });

  it('does not mutate the input', () => {
    const input = [item('dispatched'), item('pending-approval')];
    sortPackagedItems(input);
    expect(input[0].status).toBe('dispatched');
  });
});

describe('countAwaitingDecision', () => {
  it('counts only packets the operator can still act on', () => {
    expect(
      countAwaitingDecision([
        item('pending-approval'),
        item('pending-approval'),
        item('dispatched'),
        item('rejected'),
        item('dispatch-failed'),
      ])
    ).toBe(3);
  });

  it('is zero for an empty queue', () => {
    expect(countAwaitingDecision([])).toBe(0);
  });
});

// Release 3.5 milestone 6 — a retry loop renders as one piece of work with an
// attempt count, not as a backlog of thirteen.
describe('groupPackagedItemAttempts', () => {
  const attempt = (packetId: string, repoName: string, itemText: string, packagedAt: string, status = 'pending-approval'): PackagedItem => ({
    packetId,
    repoName,
    status,
    packagedAt,
    packet: { repoName, itemText },
  });

  it('collapses same-work attempts behind the newest and counts the rest', () => {
    const groups = groupPackagedItemAttempts([
      attempt('p1', 'RepoA', 'Add the export route', '2026-08-09T08:00:00Z'),
      attempt('p2', 'RepoA', 'Add the export route', '2026-08-10T08:00:00Z'),
      attempt('p3', 'RepoA', 'Add the export route', '2026-08-11T08:00:00Z'),
      attempt('p4', 'RepoB', 'Different work', '2026-08-11T09:00:00Z'),
    ]);
    expect(groups).toHaveLength(2);
    const repoA = groups.find(g => g.latest.repoName === 'RepoA')!;
    expect(repoA.latest.packetId).toBe('p3'); // newest is the face
    expect(repoA.earlierAttempts.map(a => a.packetId)).toEqual(['p2', 'p1']);
  });

  it('never merges without an item text — no work identity, no guessing', () => {
    const a = attempt('p1', 'RepoA', '', '2026-08-09T08:00:00Z');
    const b = attempt('p2', 'RepoA', '', '2026-08-10T08:00:00Z');
    expect(groupPackagedItemAttempts([a, b])).toHaveLength(2);
  });

  it('actionable status still leads even when an older attempt is newer by time', () => {
    const groups = groupPackagedItemAttempts([
      attempt('old-pending', 'RepoA', 'Work', '2026-08-09T08:00:00Z', 'pending-approval'),
      attempt('new-dispatched', 'RepoA', 'Work', '2026-08-11T08:00:00Z', 'dispatched'),
    ]);
    expect(groups).toHaveLength(1);
    // sortPackagedItems ranks pending-approval first; the face is the row the
    // operator can act on.
    expect(groups[0].latest.packetId).toBe('old-pending');
  });
});
