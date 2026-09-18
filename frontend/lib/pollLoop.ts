// Lane 0.21 (L21-POLL) — the one poll helper.
//
// Every recurring fetch in the frontend runs through `startPollLoop` (or the
// `usePollLoop` hook over it). The rules it holds, and the reason for each:
//
// - The next call starts only when the previous one has settled — a
//   `setTimeout` chain, never `setInterval`. `/api/agent-runs` was fetched
//   seven times in one load because intervals fire whether or not the last
//   answer has arrived, so a slow host got slower.
// - Every call carries an `AbortSignal` that fires at `timeoutMs`. A call that
//   never settles is counted as a timeout and the loop moves on.
// - The gap doubles after a slow, timed-out or failed call, up to
//   `maxIntervalMs`, and snaps back to the base interval after a fast success.
// - Nothing is called while the document is hidden; the loop resumes the
//   moment it is visible again.
//
// `frontend/lib/pollLoop.test.ts` proves each rule and scans the tree for any
// poll that bypasses this file.

export type PollOutcome = 'none' | 'ok' | 'slow' | 'timeout' | 'error';

export type PollTask = (signal: AbortSignal, loop: PollLoopHandle) => unknown;

export interface PollLoopOptions {
  /** Gap between one call settling and the next starting, or a function of the last outcome. */
  intervalMs: number | ((last: PollOutcome) => number);
  /** Per-call abort deadline. Default 15 000 ms. */
  timeoutMs?: number;
  /** Ceiling for the backed-off gap. Default 120 000 ms. */
  maxIntervalMs?: number;
  /** A call slower than this backs the loop off. Default: half the interval, at least 500 ms. */
  slowMs?: number;
  /** Delay before the first call. Default 0 (still asynchronous, never inside the caller's frame). */
  initialDelayMs?: number;
  /** Visibility probe. Default `document.hidden`; `false` when there is no document. */
  isHidden?: () => boolean;
  /** Where `visibilitychange` is heard. Default `document`; `null` disables the listener. */
  visibilityTarget?: EventTarget | null;
  /** Called with every rejection. The loop never stops on an error. */
  onError?: (error: unknown) => void;
}

export interface PollLoopStats {
  calls: number;
  ok: number;
  slow: number;
  timeouts: number;
  errors: number;
  skippedHidden: number;
}

export interface PollLoopHandle {
  /** End the loop: abort the call in flight, cancel the pending timer, drop the listener. */
  stop(): void;
  /** Call now if idle; if a call is in flight, run exactly one more when it settles. */
  runNow(): void;
  readonly stopped: boolean;
  readonly inFlight: boolean;
  /** The gap chosen after the last settle (0 until the first call has settled). */
  readonly nextDelayMs: number;
  readonly lastOutcome: PollOutcome;
  readonly stats: Readonly<PollLoopStats>;
}

const DEFAULT_TIMEOUT_MS = 15_000;
const DEFAULT_MAX_INTERVAL_MS = 120_000;

function defaultIsHidden(): boolean {
  // `visibilityState`, not `hidden`: a `prerender` document (jsdom's default,
  // and a browser's pre-rendered tab) is not a hidden one, and `hidden` says
  // true for both.
  return typeof document !== 'undefined' && document.visibilityState === 'hidden';
}

function baseInterval(option: PollLoopOptions['intervalMs'], last: PollOutcome): number {
  const value = typeof option === 'function' ? option(last) : option;
  return Number.isFinite(value) && value > 0 ? value : 0;
}

export function startPollLoop(task: PollTask, options: PollLoopOptions): PollLoopHandle {
  const timeoutMs = options.timeoutMs ?? DEFAULT_TIMEOUT_MS;
  const maxIntervalMs = options.maxIntervalMs ?? DEFAULT_MAX_INTERVAL_MS;
  const isHidden = options.isHidden ?? defaultIsHidden;
  const visibilityTarget = options.visibilityTarget === undefined
    ? (typeof document !== 'undefined' ? document : null)
    : options.visibilityTarget;

  let stopped = false;
  let inFlight = false;
  let rerunRequested = false;
  let backoffLevel = 0;
  let nextDelayMs = 0;
  let lastOutcome: PollOutcome = 'none';
  let timer: ReturnType<typeof setTimeout> | null = null;
  let controller: AbortController | null = null;
  const stats: PollLoopStats = { calls: 0, ok: 0, slow: 0, timeouts: 0, errors: 0, skippedHidden: 0 };

  const clearTimer = () => {
    if (timer !== null) { clearTimeout(timer); timer = null; }
  };

  const schedule = (delayMs: number) => {
    if (stopped) return;
    clearTimer();
    timer = setTimeout(tick, Math.max(0, delayMs));
  };

  const gapAfter = (outcome: PollOutcome): number => {
    const base = baseInterval(options.intervalMs, outcome);
    if (outcome === 'ok') backoffLevel = 0; else backoffLevel += 1;
    const backedOff = base * 2 ** backoffLevel;
    return Math.min(Number.isFinite(backedOff) ? backedOff : maxIntervalMs, maxIntervalMs);
  };

  const settle = (outcome: PollOutcome) => {
    inFlight = false;
    controller = null;
    lastOutcome = outcome;
    if (stopped) return;
    if (rerunRequested) {
      rerunRequested = false;
      nextDelayMs = 0;
      schedule(0);
      return;
    }
    nextDelayMs = gapAfter(outcome);
    schedule(nextDelayMs);
  };

  const tick = () => {
    timer = null;
    if (stopped || inFlight) return;
    if (isHidden()) {
      // Silence, not a skipped beat: the listener below wakes the loop the
      // moment the page is visible, and this re-check covers a target that
      // never fires the event.
      stats.skippedHidden += 1;
      schedule(Math.max(baseInterval(options.intervalMs, lastOutcome), 1_000));
      return;
    }

    inFlight = true;
    stats.calls += 1;
    const ownController = new AbortController();
    controller = ownController;
    const startedAt = Date.now();
    const slowMs = options.slowMs ?? (typeof options.intervalMs === 'number' ? Math.max(500, options.intervalMs / 2) : 1_000);
    let settled = false;
    let timeoutHandle: ReturnType<typeof setTimeout> | null = null;

    const finish = (outcome: PollOutcome) => {
      if (settled) return;
      settled = true;
      if (timeoutHandle !== null) { clearTimeout(timeoutHandle); timeoutHandle = null; }
      if (outcome === 'ok') {
        if (Date.now() - startedAt >= slowMs) { outcome = 'slow'; stats.slow += 1; } else { stats.ok += 1; }
      } else if (outcome === 'timeout') {
        stats.timeouts += 1;
      } else if (outcome === 'error') {
        stats.errors += 1;
      }
      settle(outcome);
    };

    timeoutHandle = setTimeout(() => {
      if (settled) return;
      ownController.abort();
      finish('timeout');
    }, timeoutMs);

    let result: unknown;
    try {
      result = task(ownController.signal, handle);
    } catch (error) {
      options.onError?.(error);
      finish('error');
      return;
    }
    Promise.resolve(result).then(
      () => finish('ok'),
      (error: unknown) => {
        if (settled) return; // an abort after the timeout already settled this call
        options.onError?.(error);
        finish('error');
      },
    );
  };

  const onVisibilityChange = () => {
    if (stopped || inFlight) return;
    if (!isHidden()) schedule(0);
  };
  if (visibilityTarget) visibilityTarget.addEventListener('visibilitychange', onVisibilityChange);

  const handle: PollLoopHandle = {
    stop() {
      if (stopped) return;
      stopped = true;
      clearTimer();
      if (controller) controller.abort();
      if (visibilityTarget) visibilityTarget.removeEventListener('visibilitychange', onVisibilityChange);
    },
    runNow() {
      if (stopped) return;
      if (inFlight) { rerunRequested = true; return; }
      schedule(0);
    },
    get stopped() { return stopped; },
    get inFlight() { return inFlight; },
    get nextDelayMs() { return nextDelayMs; },
    get lastOutcome() { return lastOutcome; },
    get stats() { return stats; },
  };

  schedule(options.initialDelayMs ?? 0);
  return handle;
}
