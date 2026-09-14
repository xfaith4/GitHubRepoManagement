import { useState, useEffect, useRef, useCallback } from 'react';

export interface BackendLogEntry {
  ts: string;
  level: 'INFO' | 'WARN' | 'ERROR' | 'TRACE';
  msg: string;
}

const USE_MOCK_API = (() => {
  const env = typeof import.meta !== 'undefined' ? import.meta.env : undefined;
  return ((env?.VITE_USE_MOCK_API as string | undefined) ?? 'false') === 'true';
})();

/**
 * Polls GET /api/log/tail to surface real backend log activity in the dashboard.
 * When `enabled` is false the hook is idle and returns an empty array.
 * `sinceMs` is set to the moment `enabled` flips to true so only new lines are
 * returned (not the entire history). Pass `includeHistory: true` to load the
 * last 100 lines on first activation regardless of timestamp.
 */
export function useBackendLog(
  enabled: boolean,
  { pollIntervalMs = 2500, includeHistory = false } = {}
) {
  const [entries, setEntries] = useState<BackendLogEntry[]>([]);
  const cursorRef = useRef<number>(0);
  const activeRef = useRef(false);

  const reset = useCallback(() => {
    setEntries([]);
    cursorRef.current = includeHistory ? Date.now() - 60_000 : Date.now();
  }, [includeHistory]);

  useEffect(() => {
    if (!enabled) {
      activeRef.current = false;
      return;
    }

    // Re-initialise cursor when enabled flips on
    if (!activeRef.current) {
      activeRef.current = true;
      reset();
    }

    if (USE_MOCK_API) return;

    let cancelled = false;

    const poll = async () => {
      try {
        const url = `/api/log/tail?lines=100&since=${cursorRef.current}`;
        const res = await fetch(url);
        if (!res.ok || cancelled) return;
        const data = await res.json();
        const incoming: BackendLogEntry[] = Array.isArray(data?.entries) ? data.entries : [];
        if (incoming.length > 0 && !cancelled) {
          setEntries(prev => [...prev, ...incoming]);
          cursorRef.current = Date.now();
        }
      } catch {
        // Backend offline — silently skip; health ping shows the disconnect
      }
    };

    poll();
    const id = setInterval(poll, pollIntervalMs);
    return () => {
      cancelled = true;
      clearInterval(id);
    };
  }, [enabled, pollIntervalMs, reset]);

  return { entries, reset };
}
