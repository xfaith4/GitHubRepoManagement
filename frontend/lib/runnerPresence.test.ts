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

  // Lane 0.20 — inverted deliberately. This used to assert the detail CONTAINED
  // the start command; the console handing over a terminal command is the defect
  // the lane exists to remove, so the assertion now guards the other direction.
  it('offers the action for an absent runner instead of a command to paste', () => {
    const view = resolveRunnerPresence({ state: 'absent', present: false });
    expect(view.severity).toBe('error');
    expect(view.detail).not.toContain('pwsh');
    expect(view.control.kind).toBe('start');
    expect(view.control.label).toBe('Start runner');
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
    // operator cannot tell broken from not-yet-applicable. Lane 0.20 — the
    // reason names the action, not a shell command.
    expect(gate.unmetPrecondition).toContain('nothing would pick this up');
    expect(gate.unmetPrecondition).toContain('Start runner');
    expect(gate.unmetPrecondition).not.toContain('pwsh');
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

// The header's Copy button handed `pwsh -File scripts/Invoke-RoadmapTaskRunner.ps1`
// to an elevated terminal that opened in the user profile, and pwsh answered
// "not recognized as the name of a script file". The host knows the workspace
// root; the operator should never have to supply it.
describe('runnerStartCommand', () => {
  const absolute = 'pwsh -File "F:\\Development\\GitHubRepoManagement\\scripts\\Invoke-RoadmapTaskRunner.ps1"';
  const relative = 'pwsh -File scripts/Invoke-RoadmapTaskRunner.ps1';

  it('prefers the absolute command the host built from its workspace root', () => {
    expect(runnerStartCommand({ state: 'absent', startCommand: absolute })).toBe(absolute);
  });

  // Lane 0.20 — the command is now the FALLBACK, reached only when the console
  // tried to start a runner and could not, so no routine surface may print it.
  // It still has to be the absolute form when it is printed: the relative one
  // fails in any shell that did not open inside the repo.
  it('stays off the surfaces entirely, while remaining absolute for the failure path', () => {
    const payload = { state: 'absent', present: false, startCommand: absolute };
    expect(resolveRunnerPresence(payload).detail).not.toContain(absolute);
    expect(resolveRunnerPresence(payload).detail).not.toContain(relative);
    expect(resolveDispatchGate(payload).unmetPrecondition).not.toContain('pwsh');
    expect(runnerStartCommand(payload)).toBe(absolute);
  });

  it('falls back to the relative form only when the host did not say where the repo is', () => {
    expect(runnerStartCommand(null)).toBe(relative);
    expect(runnerStartCommand({ state: 'absent' })).toBe(relative);
    expect(runnerStartCommand({ state: 'absent', startCommand: '   ' })).toBe(relative);
  });
});

// ── H38-19 — the backlog reads per provider, not as a hardcoded pair ────────
// queuedClaude/queuedCopilot stay on the payload and keep their meaning; these
// cover the new map and, just as importantly, that a payload without it is
// unchanged. A view that quietly gained or lost a field would break every
// surface that reads it.
describe('resolveRunnerPresence — queuedByProvider (H38-19)', () => {
  it('summarizes the non-zero providers when the map is present', () => {
    const view = resolveRunnerPresence({
      state: 'present',
      present: true,
      queuedTotal: 3,
      queuedClaude: 2,
      queuedCopilot: 1,
      queuedByProvider: { claude: 2, codex: 0, copilot: 1, auto: 0 },
    });
    expect(view.queuedByProviderSummary).toBe('claude 2 · copilot 1');
  });

  it('reports every queued provider including auto, in payload order', () => {
    const view = resolveRunnerPresence({
      state: 'present',
      present: true,
      queuedByProvider: { claude: 1, codex: 4, copilot: 0, auto: 2 },
    });
    expect(view.queuedByProviderSummary).toBe('claude 1 · codex 4 · auto 2');
  });

  it('is null when nothing is queued, rather than an empty string', () => {
    const view = resolveRunnerPresence({
      state: 'present',
      present: true,
      queuedByProvider: { claude: 0, codex: 0, copilot: 0, auto: 0 },
    });
    expect(view.queuedByProviderSummary).toBeNull();
  });

  it('is null on a payload with no map at all — the pre-H38-18 host', () => {
    const view = resolveRunnerPresence({
      state: 'present',
      present: true,
      queuedTotal: 2,
      queuedClaude: 2,
      queuedCopilot: 0,
    });
    expect(view.queuedByProviderSummary).toBeNull();
  });

  // The golden: a payload with no queuedByProvider must produce exactly the
  // view it produced before this change, field for field. Captured from the
  // pre-change implementation.
  it('leaves every pre-existing field untouched when the map is absent', () => {
    const view = resolveRunnerPresence({
      state: 'stale',
      present: false,
      message: 'The last runner heartbeat was 900s ago.',
      strandedCount: 3,
    });
    expect({
      severity: view.severity,
      label: view.label,
      detail: view.detail,
      needsAttention: view.needsAttention,
      warnBeforeQueueing: view.warnBeforeQueueing,
      queueAgeAlarmHours: view.queueAgeAlarmHours,
    }).toEqual({
      severity: 'warning',
      label: 'Runner stalled',
      detail: 'The last runner heartbeat was 900s ago. 3 tasks already queued and waiting.',
      needsAttention: true,
      warnBeforeQueueing: true,
      queueAgeAlarmHours: null,
    });
  });
});

// ── Lane 0.20 — the kill switch, and the action that replaced the command ────
// A held runner and a dead runner produce an identical heartbeat (none) and
// mean opposite things. Rendering a deliberate stop as a fault would push the
// operator to undo what they just chose, and would teach them to discount the
// alarm colour on the one surface that most needs to keep it.
describe('the operator hold', () => {
  const held = {
    state: 'absent',
    present: false,
    stoppedByOperator: true,
    stoppedBy: 'ben',
    stoppedAt: '2026-09-13T18:00:00.000Z',
    stopReason: 'Stopped from the console.',
  };

  it('reads as deliberate, not as a fault', () => {
    const view = resolveRunnerPresence(held);
    expect(view.severity).toBe('warning');
    expect(view.label).toBe('Runners stopped');
    expect(view.stoppedByOperator).toBe(true);
    // Deliberate, so no alarm — but nothing is being worked, so it must still
    // warn anything about to queue into the silence.
    expect(view.needsAttention).toBe(false);
    expect(view.warnBeforeQueueing).toBe(true);
  });

  it('attributes the hold so the operator can tell it was theirs', () => {
    expect(resolveRunnerPresence(held).detail).toContain('ben');
    expect(resolveRunnerPresence(held).detail).toContain('until you resume');
  });

  it('takes precedence over the stale reading of the same missing heartbeat', () => {
    const view = resolveRunnerPresence({ ...held, state: 'stale', message: 'heartbeat 900s ago' });
    expect(view.label).toBe('Runners stopped');
    expect(view.detail).not.toContain('900s');
  });

  it('offers resume rather than start, because there is one start path', () => {
    expect(resolveRunnerPresence(held).control).toEqual({
      kind: 'start',
      label: 'Resume runners',
      unavailableReason: '',
    });
  });

  it('still blocks queueing, naming the action', () => {
    const gate = resolveDispatchGate(held);
    expect(gate.canQueue).toBe(false);
    expect(gate.unmetPrecondition).toContain('Resume runners');
    expect(gate.unmetPrecondition).not.toContain('pwsh');
  });
});

describe('the control a state offers', () => {
  it('offers stop while a runner is alive', () => {
    expect(resolveRunnerPresence({ state: 'present', present: true }).control).toEqual({
      kind: 'stop',
      label: 'Stop runners',
      unavailableReason: '',
    });
  });

  // A button for a task nobody registered fails every press. Saying so beats
  // offering it, because the operator otherwise reads the failure as the
  // console being broken rather than the installer never having been run.
  it('withholds the control, with a reason, when no runner task is registered', () => {
    const view = resolveRunnerPresence({ state: 'absent', present: false, startable: false });
    expect(view.control.kind).toBe('none');
    expect(view.control.unavailableReason).toContain('Install-RoadmapTaskRunner.ps1');
  });

  // `startable` absent means a host that predates this packet, not a host with
  // no task. Treating silence as "false" would disable the button against every
  // installation that has not restarted its service yet.
  it('treats a host that cannot answer as able to start, not as unable', () => {
    expect(resolveRunnerPresence({ state: 'absent', present: false }).control.kind).toBe('start');
  });

  it('offers nothing when the status call itself failed', () => {
    expect(resolveRunnerPresence(null).control.kind).toBe('none');
    expect(resolveRunnerPresence(null).detail).not.toContain('pwsh');
  });
});
