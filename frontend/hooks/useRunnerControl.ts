import { useCallback, useEffect, useRef, useState } from 'react';
import { getRunnerPresence, startRunner, stopRunner } from '../services/apiClient';
import { usePollLoop } from './usePollLoop';
import {
  resolveRunnerPresence,
  runnerStartCommand,
  type RunnerPresencePayload,
  type RunnerPresenceView,
} from '../lib/runnerPresence';

/**
 * Lane 0.20 — one runner state, one pair of controls, shared by every surface.
 *
 * The header pill and the Insights pane are two windows onto the same fact, and
 * the fastest way to make an operator distrust both is to let them disagree.
 * Polling, the start and stop calls, and the honesty rules about what a start
 * is allowed to claim all live here so there is exactly one implementation.
 *
 * The honesty rule, since it is the part easiest to lose: a start request is
 * NOT a started runner. The scheduled task runs as the operator with
 * LogonType=Interactive, so while they are logged out Task Scheduler accepts
 * the request and nothing happens. This hook therefore reports `pending` after
 * a request and only clears it when the heartbeat actually shows a runner — and
 * if it never does, it says so rather than leaving a hopeful spinner.
 */

const POLL_MS = 30_000;
/** How long to keep watching for the heartbeat after a start request. */
const START_WATCH_MS = 45_000;
/** How often to re-check while watching — the runner beats far faster than the idle poll. */
const START_WATCH_INTERVAL_MS = 3_000;

export type RunnerActionState = 'idle' | 'starting' | 'stopping';

export interface RunnerControlState {
  payload: RunnerPresencePayload | null;
  view: RunnerPresenceView;
  /**
   * The clock reading taken when `payload` was fetched.
   *
   * Callers rendering an age ("oldest queued 3h") must measure against this
   * rather than reading the clock themselves: a clock read during render is
   * impure, and measuring a fetched timestamp against a later `now` quietly
   * reports an age the payload never claimed.
   */
  readAtMs: number;
  loaded: boolean;
  action: RunnerActionState;
  /**
   * What the last action actually produced, in the operator's terms. Null when
   * nothing has been attempted since the last state change.
   */
  actionNote: string | null;
  /**
   * Set only when a start attempt FAILED. Carries the command as the fallback
   * remedy — the console tried and could not, so now the operator gets the
   * thing they used to be given first.
   */
  failureCommand: string | null;
  start: () => Promise<void>;
  stop: () => Promise<void>;
  refresh: () => Promise<void>;
}

export function useRunnerControl(): RunnerControlState {
  const [payload, setPayload] = useState<RunnerPresencePayload | null>(null);
  const [readAtMs, setReadAtMs] = useState(0);
  const [loaded, setLoaded] = useState(false);
  const [action, setAction] = useState<RunnerActionState>('idle');
  const [actionNote, setActionNote] = useState<string | null>(null);
  const [failureCommand, setFailureCommand] = useState<string | null>(null);
  const cancelled = useRef(false);
  // Held in a ref as well as state because the start watcher reads it from
  // inside a loop that closed over its own render.
  const latest = useRef<RunnerPresencePayload | null>(null);

  const read = useCallback(async (signal?: AbortSignal): Promise<RunnerPresencePayload | null> => {
    try {
      const data = await getRunnerPresence({ signal });
      if (!cancelled.current) { setPayload(data); setReadAtMs(Date.now()); setLoaded(true); }
      latest.current = data;
      return data;
    } catch {
      if (!cancelled.current) { setPayload(null); setReadAtMs(Date.now()); setLoaded(true); }
      latest.current = null;
      return null;
    }
  }, []);

  useEffect(() => {
    cancelled.current = false;
    return () => { cancelled.current = true; };
  }, []);

  usePollLoop((signal) => read(signal), { intervalMs: POLL_MS });

  const start = useCallback(async () => {
    setAction('starting');
    setActionNote(null);
    setFailureCommand(null);
    try {
      const result = await startRunner();
      if (cancelled.current) return;
      setActionNote(
        result.holdReleased
          ? 'Hold released and a runner requested. Watching for it to report in…'
          : 'Runner requested. Watching for it to report in…'
      );

      // Watch for the heartbeat rather than declaring victory. The request
      // succeeding proves Task Scheduler accepted it, nothing more.
      const deadline = Date.now() + START_WATCH_MS;
      let seen = false;
      while (Date.now() < deadline && !cancelled.current) {
        await new Promise(resolve => setTimeout(resolve, START_WATCH_INTERVAL_MS));
        const fresh = await read();
        if (fresh && (fresh.state === 'present' || fresh.present === true)) { seen = true; break; }
      }
      if (cancelled.current) return;
      setActionNote(
        seen
          ? 'Runner is up and claiming queued work.'
          : 'The start was accepted but no runner has reported in. The runner needs the operator account signed in on this machine — queued work waits until it is.'
      );
    } catch (error) {
      if (cancelled.current) return;
      // The error the attempt actually produced, not a paraphrase of it.
      setActionNote(error instanceof Error ? error.message : 'The start request failed.');
      setFailureCommand(runnerStartCommand(latest.current));
    } finally {
      if (!cancelled.current) setAction('idle');
    }
  }, [read]);

  const stop = useCallback(async () => {
    setAction('stopping');
    setActionNote(null);
    setFailureCommand(null);
    try {
      await stopRunner('Stopped from the console.');
      if (cancelled.current) return;
      setActionNote(
        'Runners held. One already working finishes its current task before exiting — abandoning it mid-run would leave a claimed item with no owner.'
      );
      await read();
    } catch (error) {
      if (cancelled.current) return;
      setActionNote(error instanceof Error ? error.message : 'The stop request failed.');
    } finally {
      if (!cancelled.current) setAction('idle');
    }
  }, [read]);

  const refresh = useCallback(async () => { await read(); }, [read]);

  return {
    payload,
    // Measured against the fetch clock for the same reason as readAtMs: the
    // queue-age alarm must describe the payload it was computed from.
    view: resolveRunnerPresence(payload, readAtMs || undefined),
    readAtMs,
    loaded,
    action,
    actionNote,
    failureCommand,
    start,
    stop,
    refresh,
  };
}

export default useRunnerControl;
