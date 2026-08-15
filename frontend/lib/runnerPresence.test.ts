import { describe, it, expect } from 'vitest';
import { resolveRunnerPresence, resolveDispatchGate, runnerStartCommand } from './runnerPresence';

describe('resolveRunnerPresence', () => {
  it('reports a live runner and does not warn', () => {
    const view = resolveRunnerPresence({
      state: 'present',
      present: true,
      hostname: 'WORKSTATION',
      user: 'ben',
      secondsSinceBeat: 4,
    });
    expect(view.severity).toBe('ok');
    expect(view.detail).toContain('WORKSTATION\\ben');
    expect(view.warnBeforeQueueing).toBe(false);
    expect(view.needsAttention).toBe(false);
  });

  it('warns when the runner has stopped reporting in', () => {
    const view = resolveRunnerPresence({
      state: 'stale',
      present: false,
      message: 'The last runner heartbeat was 900s ago.',
      strandedCount: 3,
    });
    expect(view.severity).toBe('warning');
    expect(view.warnBeforeQueueing).toBe(true);
    expect(view.detail).toContain('900s ago');
    expect(view.detail).toContain('3 tasks already queued');
  });

  it('names the command that fixes an absent runner', () => {
    const view = resolveRunnerPresence({ state: 'absent', present: false });
    expect(view.severity).toBe('error');
    expect(view.detail).toContain(runnerStartCommand());
    expect(view.warnBeforeQueueing).toBe(true);
  });

  it('escalates an absent runner to needing attention once work is stranded', () => {
    expect(resolveRunnerPresence({ state: 'absent', strandedCount: 0 }).needsAttention).toBe(false);
    expect(resolveRunnerPresence({ state: 'absent', strandedCount: 1 }).needsAttention).toBe(true);
  });

  it('pluralises a single stranded task correctly', () => {
    const view = resolveRunnerPresence({ state: 'absent', strandedCount: 1 });
    expect(view.detail).toContain('1 task already queued');
    expect(view.detail).not.toContain('1 tasks');
  });

  // The false-green this surface exists to prevent. Unlike an automation badge,
  // acting on a wrong "ready" costs the operator a wizard's worth of refinement
  // work before the dead end shows up.
  it('never reports ready when the status call failed', () => {
    const view = resolveRunnerPresence(null);
    expect(view.severity).toBe('unknown');
    expect(view.severity).not.toBe('ok');
    expect(view.warnBeforeQueueing).toBe(true);
  });

  it('treats an unrecognized state as absent rather than present', () => {
    const view = resolveRunnerPresence({ state: 'something-else' });
    expect(view.severity).toBe('error');
    expect(view.warnBeforeQueueing).toBe(true);
  });
});

// Release 3.1 — nothing may be queued into an empty room. Six entries reached
// `queued` between 2026-08-01 and 2026-08-11 through a control that stayed
// enabled whatever the runner was doing.
describe('resolveDispatchGate', () => {
  it('allows queueing when a runner is alive', () => {
    const gate = resolveDispatchGate({ state: 'present', present: true });
    expect(gate.canQueue).toBe(true);
    expect(gate.unmetPrecondition).toBe('');
  });

  it('blocks queueing when no runner has reported in, and names the precondition', () => {
    const gate = resolveDispatchGate({ state: 'absent', present: false });
    expect(gate.canQueue).toBe(false);
    // A disabled control with no reason is worse than a failing one: the
    // operator cannot tell broken from not-yet-applicable.
    expect(gate.unmetPrecondition).toContain(runnerStartCommand());
    expect(gate.overrideLabel).not.toBe('');
  });

  it('blocks queueing when the runner has stalled', () => {
    expect(resolveDispatchGate({ state: 'stale', present: false }).canQueue).toBe(false);
  });

  it('counts the existing pile in the precondition', () => {
    const gate = resolveDispatchGate({ state: 'absent', present: false, strandedCount: 6 });
    expect(gate.unmetPrecondition).toContain('6 tasks already queued');
    const one = resolveDispatchGate({ state: 'absent', present: false, strandedCount: 1 });
    expect(one.unmetPrecondition).toContain('1 task already queued');
    expect(one.unmetPrecondition).not.toContain('1 tasks');
  });

  // A failed status call is not evidence that nothing is listening. Blocking on
  // it would dead-end the operator over a hiccup on a different route — the same
  // dead end this gate exists to remove, arrived at from the other side.
  it('does not block when presence could not be read', () => {
    expect(resolveDispatchGate(null).canQueue).toBe(true);
  });
});

// Release 3.5 milestone 6 — the queue-age alarm. A task unclaimed past a day
// escalates the header regardless of presence: a present runner that claims
// nothing is the same operator problem as an absent one.
describe('queue-age alarm', () => {
  const now = Date.parse('2026-08-15T12:00:00Z');

  it('escalates a PRESENT runner whose oldest queued task has waited past a day', () => {
    const view = resolveRunnerPresence(
      { state: 'present', present: true, oldestQueuedAt: '2026-08-13T10:00:00Z' },
      now,
    );
    expect(view.severity).toBe('warning');
    expect(view.label).toBe('Queue stalled');
    expect(view.queueAgeAlarmHours).toBe(50);
    expect(view.needsAttention).toBe(true);
  });

  it('stays quiet under the 24h threshold', () => {
    const view = resolveRunnerPresence(
      { state: 'present', present: true, oldestQueuedAt: '2026-08-15T02:00:00Z' },
      now,
    );
    expect(view.severity).toBe('ok');
    expect(view.queueAgeAlarmHours).toBeNull();
  });

  it('carries the alarm on an absent runner too', () => {
    const view = resolveRunnerPresence(
      { state: 'absent', strandedCount: 0, oldestQueuedAt: '2026-08-13T10:00:00Z' },
      now,
    );
    expect(view.severity).toBe('error');
    expect(view.queueAgeAlarmHours).toBe(50);
    expect(view.needsAttention).toBe(true);
  });

  it('an unparseable or absent timestamp never alarms', () => {
    expect(resolveRunnerPresence({ state: 'present', present: true, oldestQueuedAt: 'garbage' }, now).queueAgeAlarmHours).toBeNull();
    expect(resolveRunnerPresence({ state: 'present', present: true }, now).queueAgeAlarmHours).toBeNull();
  });
});
