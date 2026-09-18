// Lane 0.21 (L21-POLL) — React wrapper over the one poll helper.
//
// The task and any interval function are read through refs, so the loop
// always calls the latest closure without restarting; the loop itself restarts
// only when `enabled` or a numeric interval changes. Returns `runNow` for the
// sites that also refresh on a button press.
import { useEffect, useRef, useCallback } from 'react';
import { startPollLoop, type PollLoopHandle, type PollLoopOptions, type PollTask } from '../lib/pollLoop';

export interface UsePollLoopOptions extends PollLoopOptions {
  /** `false` stops the loop and starts nothing. Default `true`. */
  enabled?: boolean;
}

export function usePollLoop(task: PollTask, options: UsePollLoopOptions): { runNow: () => void } {
  const taskRef = useRef<PollTask>(task);
  const optionsRef = useRef<UsePollLoopOptions>(options);
  const handleRef = useRef<PollLoopHandle | null>(null);
  // Written in an effect, not during render (react-hooks/refs): this effect is
  // declared first, so it runs before the loop effect below on every commit.
  useEffect(() => {
    taskRef.current = task;
    optionsRef.current = options;
  });

  const enabled = options.enabled ?? true;
  const intervalKey = typeof options.intervalMs === 'number' ? options.intervalMs : 'fn';

  useEffect(() => {
    if (!enabled) return;
    const current = optionsRef.current;
    const loop = startPollLoop(
      (signal, handle) => taskRef.current(signal, handle),
      {
        ...current,
        intervalMs: typeof current.intervalMs === 'function'
          ? (last) => {
            const option = optionsRef.current.intervalMs;
            return typeof option === 'function' ? option(last) : option;
          }
          : current.intervalMs,
        onError: (error) => optionsRef.current.onError?.(error),
      },
    );
    handleRef.current = loop;
    return () => {
      loop.stop();
      if (handleRef.current === loop) handleRef.current = null;
    };
  }, [enabled, intervalKey]);

  const runNow = useCallback(() => { handleRef.current?.runNow(); }, []);
  return { runNow };
}
