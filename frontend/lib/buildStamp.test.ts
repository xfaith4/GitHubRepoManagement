import { describe, expect, it } from 'vitest';
import { resolveBuildStamp } from './buildStamp';

const BUILT = '2026-09-05T12:00:00.000Z';

describe('resolveBuildStamp', () => {
  it('reports a single version when UI and host agree', () => {
    const view = resolveBuildStamp('a1b2c3d', BUILT, {
      commit: 'a1b2c3d',
      branch: 'main',
      startedAtUtc: BUILT,
    });
    expect(view.state).toBe('matched');
    expect(view.label).toBe('a1b2c3d');
    expect(view.drifted).toBe(false);
  });

  it('names BOTH commits when the host runs different code', () => {
    // The case the chip exists for: a rebuilt bundle in front of a host that
    // was never restarted looks identical to a fully updated portal.
    const view = resolveBuildStamp('a1b2c3d', BUILT, {
      commit: 'e4f5a6b',
      branch: 'main',
      startedAtUtc: BUILT,
    });
    expect(view.state).toBe('mismatched');
    expect(view.drifted).toBe(true);
    expect(view.label).toContain('a1b2c3d');
    expect(view.label).toContain('e4f5a6b');
    expect(view.detail).toContain('restarted');
  });

  it('does not claim agreement when the host did not answer', () => {
    const view = resolveBuildStamp('a1b2c3d', BUILT, null);
    expect(view.state).toBe('api-unknown');
    expect(view.drifted).toBe(false);
    expect(view.detail).toContain('unknown');
  });

  it('treats a host that reports no commit as unknown, not as a match', () => {
    const view = resolveBuildStamp('a1b2c3d', BUILT, { commit: null, startedAtUtc: null });
    expect(view.state).toBe('api-unknown');
    expect(view.drifted).toBe(false);
  });

  it('says so when the bundle was built outside a checkout', () => {
    const view = resolveBuildStamp(null, BUILT, { commit: 'e4f5a6b', startedAtUtc: BUILT });
    expect(view.state).toBe('ui-unknown');
    expect(view.detail).toContain('outside a git checkout');
  });

  it('renders an unparseable timestamp as unknown rather than Invalid Date', () => {
    const view = resolveBuildStamp('a1b2c3d', 'not a time', {
      commit: 'a1b2c3d',
      startedAtUtc: 'also not a time',
    });
    expect(view.detail).not.toContain('Invalid Date');
    expect(view.detail).toContain('unknown');
  });
});
