import { describe, it, expect } from 'vitest';
import { resolveRunnerPresence, runnerStartCommand } from './runnerPresence';

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
