/**
 * Release 3.5 milestone 5 — one async state model for every panel.
 *
 * The review found five panels sitting in permanent spinners with no timeout,
 * no error state, no last-known-good and no retry — and one of them rendered a
 * *fetch failure* as "No cross-repo dependencies detected", the worst possible
 * empty state: a detection failure posing as a clean bill of health.
 *
 * The model's rules:
 *  - `empty` means COMPUTED AND FOUND NOTHING, and must carry when it was
 *    computed. "Not computed" is `idle`/`error`, never `empty`.
 *  - A refresh failure after a success keeps the last good data and becomes
 *    `stale` — a stale truth with its age stated beats a lie of omission.
 *  - A failure with nothing to fall back on is `error`, naming the endpoint
 *    and offering retry. A hung fetch becomes `error` at the timeout; a hung
 *    fetch and a slow fetch must not be indistinguishable forever.
 *
 * Pure transition functions so every rule above is unit-testable without a
 * component; the hook is a thin shell over them.
 */
import { useCallback, useRef, useState } from 'react';

export type AsyncPanelPhase = 'idle' | 'loading' | 'success' | 'empty' | 'stale' | 'error';

export interface AsyncPanelError {
  message: string;
  endpoint: string;
  status?: number;
}

export interface AsyncPanelState<T> {
  phase: AsyncPanelPhase;
  /** Last good payload — present in success/empty/stale, kept through loading. */
  data: T | null;
  /** When the last good payload was fetched (ISO). */
  lastGoodAt: string | null;
  error: AsyncPanelError | null;
  /** When the most recent refresh failed (ISO) — the age the stale banner states. */
  failedAt: string | null;
}

export function panelIdle<T>(): AsyncPanelState<T> {
  return { phase: 'idle', data: null, lastGoodAt: null, error: null, failedAt: null };
}

export function panelLoading<T>(prev: AsyncPanelState<T>): AsyncPanelState<T> {
  // Loading never discards the last good payload: a refresh renders the data
  // it is refreshing, not a spinner where information used to be.
  return { ...prev, phase: 'loading', error: null };
}

export function panelSuccess<T>(prev: AsyncPanelState<T>, data: T, isEmpty: boolean, at: string): AsyncPanelState<T> {
  return {
    phase: isEmpty ? 'empty' : 'success',
    data,
    lastGoodAt: at,
    error: null,
    failedAt: null,
  };
}

export function panelFailure<T>(prev: AsyncPanelState<T>, error: AsyncPanelError, at: string): AsyncPanelState<T> {
  if (prev.data != null && prev.lastGoodAt != null) {
    // Stale truth beats a lie of omission: keep the last good value, state
    // its age, and record when the refresh failed.
    return { ...prev, phase: 'stale', error, failedAt: at };
  }
  return { phase: 'error', data: null, lastGoodAt: null, error, failedAt: at };
}

/** A fetch that has not answered by the deadline is an error, not a mood. */
export const ASYNC_PANEL_TIMEOUT_MS = 10_000;

export class AsyncPanelTimeoutError extends Error {
  endpoint: string;
  constructor(endpoint: string, timeoutMs: number) {
    super(`${endpoint} did not answer within ${Math.round(timeoutMs / 1000)}s.`);
    this.name = 'AsyncPanelTimeoutError';
    this.endpoint = endpoint;
  }
}

export function withPanelTimeout<T>(promise: Promise<T>, endpoint: string, timeoutMs: number = ASYNC_PANEL_TIMEOUT_MS): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    const timer = setTimeout(() => reject(new AsyncPanelTimeoutError(endpoint, timeoutMs)), timeoutMs);
    promise.then(
      value => { clearTimeout(timer); resolve(value); },
      err => { clearTimeout(timer); reject(err); },
    );
  });
}

export interface UseAsyncPanelResult<T> {
  state: AsyncPanelState<T>;
  /** Kick a load/refresh. Concurrent calls collapse onto the newest. */
  load: () => Promise<void>;
}

export function useAsyncPanel<T>(
  fetcher: () => Promise<T>,
  endpoint: string,
  isEmpty: (data: T) => boolean,
  timeoutMs: number = ASYNC_PANEL_TIMEOUT_MS,
): UseAsyncPanelResult<T> {
  const [state, setState] = useState<AsyncPanelState<T>>(panelIdle<T>());
  // Only the newest in-flight load may write state; an older response landing
  // late must not overwrite a newer one.
  const loadSeq = useRef(0);

  const load = useCallback(async () => {
    const seq = ++loadSeq.current;
    setState(prev => panelLoading(prev));
    try {
      const data = await withPanelTimeout(fetcher(), endpoint, timeoutMs);
      if (loadSeq.current !== seq) return;
      setState(prev => panelSuccess(prev, data, isEmpty(data), new Date().toISOString()));
    } catch (err) {
      if (loadSeq.current !== seq) return;
      const message = err instanceof Error ? err.message : String(err);
      setState(prev => panelFailure(prev, { message, endpoint }, new Date().toISOString()));
    }
  }, [fetcher, endpoint, isEmpty, timeoutMs]);

  return { state, load };
}
