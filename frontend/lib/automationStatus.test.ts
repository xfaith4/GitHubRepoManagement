import { describe, it, expect } from 'vitest';
import {
  resolveAutomationStatus,
  formatMinutesAgo,
  type AutomationHealthPayload,
} from './automationStatus';

const healthy: AutomationHealthPayload = {
  enabled: true,
  intervalMinutes: 60,
  runCount: 4,
  lastRunAt: '2026-08-08T12:00:00.0000000Z',
  lastOutcome: 'ok',
  lastErrorCount: 0,
  minutesSinceLastRun: 12,
  overdue: false,
  consecutiveFailures: 0,
  healthy: true,
  alert: null,
};

describe('resolveAutomationStatus', () => {
  it('reports healthy with the last-run time when there is no alert', () => {
    const view = resolveAutomationStatus(healthy);
    expect(view.severity).toBe('ok');
    expect(view.needsAttention).toBe(false);
    expect(view.detail).toContain('12m ago');
    expect(view.detail).toContain('60 minutes');
  });

  it('never reports healthy when the payload is missing', () => {
    // The whole point of this surface is to make a stopped scheduler visible.
    // A failed status call reporting "healthy" would be the same false-green.
    for (const missing of [null, undefined]) {
      const view = resolveAutomationStatus(missing);
      expect(view.severity).toBe('unknown');
      expect(view.severity).not.toBe('ok');
      expect(view.needsAttention).toBe(false);
    }
  });

  it('treats disabled automation as off, not as a failure', () => {
    const view = resolveAutomationStatus({ ...healthy, enabled: false });
    expect(view.severity).toBe('off');
    expect(view.needsAttention).toBe(false);
  });

  it('escalates an error alert to the failing state and surfaces its message', () => {
    const view = resolveAutomationStatus({
      ...healthy,
      overdue: true,
      healthy: false,
      alert: {
        severity: 'error',
        code: 'automation-overdue',
        message: 'No automation run in 300 minutes; the configured interval is 60 minutes.',
      },
    });
    expect(view.severity).toBe('error');
    expect(view.label).toBe('Automation failing');
    expect(view.needsAttention).toBe(true);
    expect(view.code).toBe('automation-overdue');
    expect(view.detail).toContain('300 minutes');
  });

  it('renders a warning alert as degraded rather than failing', () => {
    const view = resolveAutomationStatus({
      ...healthy,
      healthy: false,
      alert: { severity: 'warning', code: 'automation-run-partial', message: 'The last run completed with 2 error(s).' },
    });
    expect(view.severity).toBe('warning');
    expect(view.label).toBe('Automation degraded');
    expect(view.needsAttention).toBe(true);
  });

  it('ignores an alert object with no message rather than rendering an empty banner', () => {
    const view = resolveAutomationStatus({ ...healthy, alert: { severity: 'error', code: 'x' } });
    expect(view.severity).toBe('ok');
    expect(view.needsAttention).toBe(false);
  });

  it('describes an enabled-but-never-run scheduler without a last-run time', () => {
    const view = resolveAutomationStatus({
      enabled: true,
      intervalMinutes: 30,
      runCount: 0,
      minutesSinceLastRun: null,
      alert: null,
    });
    expect(view.severity).toBe('ok');
    expect(view.detail).toBe('Enabled on a 30-minute interval.');
  });
});

// Two schedulers now report health (doc refinement and Phase C packaging), so
// the label has to say WHICH one stopped. Identical badges would make a dead
// packaging cron indistinguishable from a dead doc cron at a glance.
describe('resolveAutomationStatus — subject labelling', () => {
  it('names the subject in every state', () => {
    expect(resolveAutomationStatus(null, 'Packaging').label).toBe('Packaging unknown');
    expect(resolveAutomationStatus({ enabled: false }, 'Packaging').label).toBe('Packaging off');
    expect(resolveAutomationStatus({ enabled: true, intervalMinutes: 60, runCount: 1, minutesSinceLastRun: 5 }, 'Packaging').label)
      .toBe('Packaging healthy');
    expect(
      resolveAutomationStatus(
        { enabled: true, alert: { severity: 'error', code: 'packaging-overdue', message: 'stopped' } },
        'Packaging'
      ).label
    ).toBe('Packaging failing');
  });

  it('defaults to Automation so existing callers are unchanged', () => {
    expect(resolveAutomationStatus(null).label).toBe('Automation unknown');
    expect(resolveAutomationStatus({ enabled: false }).label).toBe('Automation off');
  });

  it('passes the backend alert code through so the two schedulers stay distinguishable', () => {
    const view = resolveAutomationStatus(
      { enabled: true, alert: { severity: 'error', code: 'packaging-overdue', message: 'no packaging run in 300 minutes' } },
      'Packaging'
    );
    expect(view.code).toBe('packaging-overdue');
    expect(view.detail).toContain('no packaging run');
  });
});

describe('formatMinutesAgo', () => {
  it('formats sub-hour, hour, and day scales', () => {
    expect(formatMinutesAgo(0)).toBe('just now');
    expect(formatMinutesAgo(0.4)).toBe('just now');
    expect(formatMinutesAgo(45)).toBe('45m ago');
    expect(formatMinutesAgo(60)).toBe('1h ago');
    expect(formatMinutesAgo(200)).toBe('3h 20m ago');
    expect(formatMinutesAgo(1440)).toBe('1d ago');
    expect(formatMinutesAgo(1500)).toBe('1d 1h ago');
  });

  it('returns unknown for absent or non-finite input instead of NaN', () => {
    expect(formatMinutesAgo(null)).toBe('unknown');
    expect(formatMinutesAgo(undefined)).toBe('unknown');
    expect(formatMinutesAgo(Number.NaN)).toBe('unknown');
  });

  it('never renders a negative duration', () => {
    expect(formatMinutesAgo(-30)).toBe('just now');
  });
});
