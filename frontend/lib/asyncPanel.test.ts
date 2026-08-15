// Release 3.5 milestone 5 — the async panel rules, proven on the pure
// transitions. Each test names the review finding it prevents from returning.
import { describe, it, expect, vi, afterEach } from 'vitest';
import {
  panelIdle,
  panelLoading,
  panelSuccess,
  panelFailure,
  withPanelTimeout,
  AsyncPanelTimeoutError,
  type AsyncPanelState,
} from './asyncPanel';

afterEach(() => {
  vi.useRealTimers();
});

describe('asyncPanel transitions', () => {
  it('a failure with nothing to fall back on is an error naming its endpoint', () => {
    // Finding: five permanent spinners with no error state. And the silent
    // `.catch(() => {})` that rendered a fetch failure as a clean empty state.
    const s = panelFailure(panelIdle<string[]>(), { message: 'boom', endpoint: '/api/roadmap/dependencies' }, '2026-08-15T12:00:00Z');
    expect(s.phase).toBe('error');
    expect(s.error?.endpoint).toBe('/api/roadmap/dependencies');
    expect(s.data).toBeNull();
  });

  it('a refresh failure after a success keeps the last good value and its age', () => {
    // Finding: "on refresh failure render the last good value greyed with its
    // age — stale truth beats a lie of omission."
    let s: AsyncPanelState<string[]> = panelIdle();
    s = panelSuccess(s, ['a', 'b'], false, '2026-08-15T11:54:00Z');
    s = panelLoading(s);
    expect(s.data).toEqual(['a', 'b']); // loading must not blank the panel
    s = panelFailure(s, { message: 'down', endpoint: '/api/x' }, '2026-08-15T11:56:00Z');
    expect(s.phase).toBe('stale');
    expect(s.data).toEqual(['a', 'b']);
    expect(s.lastGoodAt).toBe('2026-08-15T11:54:00Z');
    expect(s.failedAt).toBe('2026-08-15T11:56:00Z');
  });

  it('empty means computed-and-found-nothing, never not-computed', () => {
    // Finding: the Dependencies panel rendered one message for both. `empty`
    // is only reachable THROUGH a success, so it always carries lastGoodAt —
    // the computed-at stamp the old empty state dropped.
    const s = panelSuccess(panelIdle<string[]>(), [], true, '2026-08-15T12:00:00Z');
    expect(s.phase).toBe('empty');
    expect(s.lastGoodAt).toBe('2026-08-15T12:00:00Z');
    // And idle (not computed) is a distinct phase with no timestamp to claim.
    expect(panelIdle().phase).toBe('idle');
  });

  it('recovery from stale returns to success and clears the failure', () => {
    let s: AsyncPanelState<number> = panelSuccess(panelIdle(), 1, false, 't1');
    s = panelFailure(s, { message: 'x', endpoint: '/e' }, 't2');
    expect(s.phase).toBe('stale');
    s = panelSuccess(s, 2, false, 't3');
    expect(s.phase).toBe('success');
    expect(s.data).toBe(2);
    expect(s.failedAt).toBeNull();
    expect(s.error).toBeNull();
  });
});

describe('withPanelTimeout', () => {
  it('a hung fetch becomes an error at the deadline, naming the endpoint', async () => {
    // Finding: "a hung fetch and a slow fetch are indistinguishable forever."
    vi.useFakeTimers();
    const hung = new Promise<never>(() => { /* never settles */ });
    const guarded = withPanelTimeout(hung, '/api/execution/queue', 10_000);
    const outcome = expect(guarded).rejects.toBeInstanceOf(AsyncPanelTimeoutError);
    await vi.advanceTimersByTimeAsync(10_001);
    await outcome;
  });

  it('a fetch that answers in time passes through untouched', async () => {
    await expect(withPanelTimeout(Promise.resolve(42), '/api/x')).resolves.toBe(42);
  });
});
