// Lane 0.21 (L21-POLL) — polls never pile up behind a slow host.
//
// Finding: `/api/agent-runs` returned the same 147 KB seven times in one page
// load, because every poll site ran on `setInterval`, which fires whether or
// not the previous call has come back. The rule this file enforces: one poll
// helper, a `setTimeout` chain that starts the next call only when the last
// one settles, a per-call abort timeout, back-off while calls are slow, and
// silence while the document is hidden. The last test finds the poll sites
// itself — a hand-kept list would drift the day someone adds one.
import { describe, it, expect, vi, afterEach } from 'vitest';
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, relative, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import { startPollLoop, type PollLoopHandle, type PollOutcome } from './pollLoop';

afterEach(() => {
  vi.useRealTimers();
});

function delay(ms: number): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, ms));
}

describe('startPollLoop — one call in flight, ever', () => {
  it('a slow host never has two calls in flight', async () => {
    vi.useFakeTimers();
    let inFlight = 0;
    let maxInFlight = 0;
    let calls = 0;
    const loop = startPollLoop(async () => {
      calls += 1;
      inFlight += 1;
      maxInFlight = Math.max(maxInFlight, inFlight);
      await delay(5_000); // five times slower than the interval
      inFlight -= 1;
    }, { intervalMs: 1_000, isHidden: () => false, visibilityTarget: null });

    await vi.advanceTimersByTimeAsync(30_000);
    loop.stop();

    expect(calls).toBeGreaterThanOrEqual(2);
    expect(maxInFlight).toBe(1);
  });

  it('the next call starts only after the previous one settles, then waits the interval', async () => {
    vi.useFakeTimers();
    const t0 = Date.now();
    const starts: number[] = [];
    const loop = startPollLoop(async () => {
      starts.push(Date.now() - t0);
      await delay(300); // fast: under the slow threshold, so no back-off
    }, { intervalMs: 1_000, slowMs: 500, isHidden: () => false, visibilityTarget: null });

    await vi.advanceTimersByTimeAsync(0);
    expect(starts).toEqual([0]);
    await vi.advanceTimersByTimeAsync(1_299);
    expect(starts).toEqual([0]); // 300 ms call + 1 000 ms gap = 1 300 ms
    await vi.advanceTimersByTimeAsync(1);
    expect(starts).toEqual([0, 1_300]);
    loop.stop();
  });
});

describe('startPollLoop — back-off, timeout, stop', () => {
  it('slow calls double the gap up to the cap; a fast call resets it', async () => {
    vi.useFakeTimers();
    let durationMs = 800; // over the 500 ms slow threshold
    const settled: number[] = [];
    const handle: PollLoopHandle = startPollLoop(async () => {
      await delay(durationMs);
      settled.push(Date.now());
    }, { intervalMs: 1_000, slowMs: 500, maxIntervalMs: 4_000, isHidden: () => false, visibilityTarget: null });

    await vi.advanceTimersByTimeAsync(800);
    expect(settled.length).toBe(1);
    expect(handle.nextDelayMs).toBe(2_000);
    expect(handle.stats.slow).toBe(1);

    await vi.advanceTimersByTimeAsync(2_000 + 800);
    expect(settled.length).toBe(2);
    expect(handle.nextDelayMs).toBe(4_000);

    await vi.advanceTimersByTimeAsync(4_000 + 800);
    expect(settled.length).toBe(3);
    expect(handle.nextDelayMs).toBe(4_000); // capped

    durationMs = 0;
    // The fast call's own zero-delay timer lands on the tick boundary; one
    // more millisecond lets the fake clock run it.
    await vi.advanceTimersByTimeAsync(4_000 + 1);
    expect(settled.length).toBe(4);
    expect(handle.nextDelayMs).toBe(1_000); // reset on a fast call
    handle.stop();
  });

  it('a call that never settles is aborted at the timeout and the loop goes on', async () => {
    vi.useFakeTimers();
    const signals: AbortSignal[] = [];
    const loop = startPollLoop((signal) => {
      signals.push(signal);
      return new Promise<never>(() => { /* never settles */ });
    }, { intervalMs: 1_000, timeoutMs: 1_000, isHidden: () => false, visibilityTarget: null });

    await vi.advanceTimersByTimeAsync(0);
    expect(signals.length).toBe(1);
    expect(signals[0].aborted).toBe(false);
    await vi.advanceTimersByTimeAsync(1_000);
    expect(signals[0].aborted).toBe(true);
    expect(loop.stats.timeouts).toBe(1);
    // A timeout counts as slow: the next call comes after a doubled gap.
    await vi.advanceTimersByTimeAsync(2_000);
    expect(signals.length).toBe(2);
    loop.stop();
  });

  it('an error is reported, counted and backed off from; it never ends the loop', async () => {
    vi.useFakeTimers();
    const errors: unknown[] = [];
    let calls = 0;
    const loop = startPollLoop(async () => {
      calls += 1;
      throw new Error(`boom ${calls}`);
    }, { intervalMs: 1_000, isHidden: () => false, visibilityTarget: null, onError: e => errors.push(e) });

    await vi.advanceTimersByTimeAsync(0);
    expect(calls).toBe(1);
    expect(errors.length).toBe(1);
    expect(loop.stats.errors).toBe(1);
    expect(loop.nextDelayMs).toBe(2_000);
    await vi.advanceTimersByTimeAsync(2_000);
    expect(calls).toBe(2);
    loop.stop();
  });

  it('stop() aborts the call in flight and schedules nothing more', async () => {
    vi.useFakeTimers();
    let calls = 0;
    let lastSignal: AbortSignal | null = null;
    const loop = startPollLoop((signal) => {
      calls += 1;
      lastSignal = signal;
      return delay(10_000);
    }, { intervalMs: 1_000, isHidden: () => false, visibilityTarget: null });

    await vi.advanceTimersByTimeAsync(0);
    expect(calls).toBe(1);
    loop.stop();
    expect(loop.stopped).toBe(true);
    expect(lastSignal!.aborted).toBe(true);
    await vi.advanceTimersByTimeAsync(60_000);
    expect(calls).toBe(1);
  });

  it('a task can end its own loop through the handle it is given', async () => {
    vi.useFakeTimers();
    let calls = 0;
    startPollLoop((_signal, loop) => {
      calls += 1;
      if (calls === 2) loop.stop();
    }, { intervalMs: 1_000, isHidden: () => false, visibilityTarget: null });

    await vi.advanceTimersByTimeAsync(60_000);
    expect(calls).toBe(2);
  });

  it('runNow() runs at once when idle and once more after the call in flight', async () => {
    vi.useFakeTimers();
    let calls = 0;
    const loop = startPollLoop(async () => {
      calls += 1;
      await delay(500);
    }, { intervalMs: 10_000, slowMs: 1_000, isHidden: () => false, visibilityTarget: null });

    await vi.advanceTimersByTimeAsync(500);
    expect(calls).toBe(1);
    loop.runNow();
    await vi.advanceTimersByTimeAsync(0);
    expect(calls).toBe(2); // idle: immediate
    loop.runNow(); // in flight: remembered, not stacked
    loop.runNow();
    await vi.advanceTimersByTimeAsync(500 + 1); // the follow-up lands on the settle boundary
    expect(calls).toBe(3); // exactly one follow-up
    loop.stop();
  });
});

describe('startPollLoop — a hidden document makes no calls', () => {
  it('skips every tick while hidden and resumes on visibilitychange', async () => {
    vi.useFakeTimers();
    let hidden = true;
    const target = new EventTarget();
    let calls = 0;
    const loop = startPollLoop(() => { calls += 1; }, {
      intervalMs: 1_000,
      isHidden: () => hidden,
      visibilityTarget: target,
    });

    await vi.advanceTimersByTimeAsync(60_000);
    expect(calls).toBe(0);
    expect(loop.stats.skippedHidden).toBeGreaterThan(0);

    hidden = false;
    target.dispatchEvent(new Event('visibilitychange'));
    await vi.advanceTimersByTimeAsync(0);
    expect(calls).toBe(1);
    loop.stop();
  });
});

describe('startPollLoop — interval as a function of the last outcome', () => {
  it('re-reads the interval after every settle', async () => {
    vi.useFakeTimers();
    let ok = true;
    const seen: PollOutcome[] = [];
    const loop = startPollLoop(async () => {
      if (!ok) throw new Error('down');
    }, {
      intervalMs: (last) => { seen.push(last); return last === 'ok' ? 250 : 5_000; },
      isHidden: () => false,
      visibilityTarget: null,
      onError: () => { /* counted */ },
    });

    await vi.advanceTimersByTimeAsync(0);
    expect(loop.nextDelayMs).toBe(250);
    ok = false;
    await vi.advanceTimersByTimeAsync(250);
    // An error is also a back-off step: 5 000 ms from the function, doubled once.
    expect(loop.nextDelayMs).toBe(10_000);
    expect(seen).toEqual(['ok', 'error']);
    loop.stop();
  });
});

// ── Every poll site uses the helper ─────────────────────────────────────────
// The scan walks frontend/ itself. Two shapes are forbidden outside the helper:
// any `setInterval(`, and a function that re-schedules itself with
// `setTimeout(` (the hand-rolled poll chain). One-shot timers — debounces,
// deferred first reads, toasts — are not polls and stay allowed.

const FRONTEND_ROOT = fileURLToPath(new URL('..', import.meta.url));
const SKIP_DIRS = new Set(['node_modules', 'dist', 'coverage']);
const HELPER_PATH = join('lib', 'pollLoop.ts');

function listSourceFiles(dir: string, out: string[] = []): string[] {
  for (const entry of readdirSync(dir)) {
    const full = join(dir, entry);
    const stat = statSync(full);
    if (stat.isDirectory()) {
      if (!SKIP_DIRS.has(entry) && !entry.startsWith('.')) listSourceFiles(full, out);
      continue;
    }
    if (!/\.(ts|tsx)$/.test(entry) || /\.test\.(ts|tsx)$/.test(entry) || /\.d\.ts$/.test(entry)) continue;
    const rel = relative(FRONTEND_ROOT, full);
    if (rel === HELPER_PATH) continue;
    out.push(rel.split(sep).join('/'));
  }
  return out;
}

/** Index of the brace that closes the one at `openIndex`, skipping strings and comments. */
function matchBrace(text: string, openIndex: number): number {
  let depth = 0;
  for (let i = openIndex; i < text.length; i += 1) {
    const ch = text[i];
    const next = text[i + 1];
    if (ch === '/' && next === '/') { i = text.indexOf('\n', i); if (i < 0) return text.length; continue; }
    if (ch === '/' && next === '*') { const end = text.indexOf('*/', i + 2); i = end < 0 ? text.length : end + 1; continue; }
    if (ch === '\'' || ch === '"' || ch === '`') {
      for (i += 1; i < text.length && text[i] !== ch; i += 1) if (text[i] === '\\') i += 1;
      continue;
    }
    if (ch === '{') depth += 1;
    if (ch === '}') { depth -= 1; if (depth === 0) return i; }
  }
  return text.length;
}

const FUNCTION_HEAD = /(?:\bfunction\s+([A-Za-z_$][\w$]*)\s*\(|\b(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=\s*(?:async\s*)?(?:\([^)]*\)|[A-Za-z_$][\w$]*)\s*=>\s*\{|\b(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=\s*(?:async\s+)?function\b[^{]*\{)/g;

function selfReschedulingFunctions(text: string): string[] {
  const found: string[] = [];
  for (const m of text.matchAll(FUNCTION_HEAD)) {
    const name = m[1] ?? m[2] ?? m[3];
    if (!name) continue;
    const open = text.indexOf('{', m.index! + m[0].length - 1);
    if (open < 0) continue;
    const body = text.slice(open, matchBrace(text, open) + 1);
    const reschedule = new RegExp(`\\bsetTimeout\\s*\\(\\s*(?:(?:async\\s*)?\\(\\s*\\)\\s*=>\\s*(?:\\{\\s*(?:void\\s+)?)?)?${name}\\b`);
    if (reschedule.test(body)) found.push(name);
  }
  return found;
}

describe('every poll site uses the helper (the scan finds the sites itself)', () => {
  const files = listSourceFiles(FRONTEND_ROOT);

  it('scans a real tree', () => {
    expect(files.length).toBeGreaterThan(20);
    expect(files).not.toContain(HELPER_PATH.split(sep).join('/'));
  });

  it('no setInterval outside lib/pollLoop.ts', () => {
    const offenders = files.filter(f => /\bsetInterval\s*\(/.test(readFileSync(join(FRONTEND_ROOT, f), 'utf8')));
    expect(offenders, `setInterval found in: ${offenders.join(', ')} — use startPollLoop / usePollLoop`).toEqual([]);
  });

  it('no function re-schedules itself with setTimeout outside lib/pollLoop.ts', () => {
    const offenders: string[] = [];
    for (const f of files) {
      const names = selfReschedulingFunctions(readFileSync(join(FRONTEND_ROOT, f), 'utf8'));
      if (names.length > 0) offenders.push(`${f} (${names.join(', ')})`);
    }
    expect(offenders, `hand-rolled poll chains in: ${offenders.join('; ')} — use startPollLoop / usePollLoop`).toEqual([]);
  });

  it('the scan itself recognises the two forbidden shapes', () => {
    expect(selfReschedulingFunctions('const poll = async () => { await x(); setTimeout(poll, 5000); };')).toEqual(['poll']);
    expect(selfReschedulingFunctions('async function tick() { timer = setTimeout(tick, 2500); }')).toEqual(['tick']);
    expect(selfReschedulingFunctions('const read = async () => { await y(); };\nconst first = setTimeout(() => { void read(); }, 0);')).toEqual([]);
    expect(selfReschedulingFunctions('function show() { setTimeout(() => setOpen(false), 3000); }')).toEqual([]);
  });
});
