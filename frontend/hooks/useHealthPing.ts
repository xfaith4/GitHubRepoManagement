import { useState, useEffect, useRef } from 'react';
import { usePollLoop } from './usePollLoop';

export type BackendHealth = 'connecting' | 'online' | 'offline';

const USE_MOCK_API = (() => {
  const env = typeof import.meta !== 'undefined' ? import.meta.env : undefined;
  return ((env?.VITE_USE_MOCK_API as string | undefined) ?? 'false') === 'true';
})();

const HEALTH_URL = (() => {
  const env = typeof import.meta !== 'undefined' ? import.meta.env : undefined;
  const viteUrl = (env?.VITE_API_URL as string | undefined) ?? (env?.REACT_APP_API_URL as string | undefined);
  if (viteUrl) {
    return `${viteUrl.replace(/\/api\/?$/, '')}/health/live`;
  }
  return '/health/live';
})();

/**
 * Polls GET /health/live at the given interval and exposes a simple
 * connectivity state so the dashboard can surface backend status without
 * any manual terminal inspection.
 */
export function useHealthPing(intervalMs = 15_000): BackendHealth {
  const [health, setHealth] = useState<BackendHealth>('connecting');
  const initialised = useRef(false);

  useEffect(() => {
    if (USE_MOCK_API) setHealth('online');
  }, []);

  usePollLoop(async (signal) => {
    try {
      const res = await fetch(HEALTH_URL, { method: 'GET', signal });
      setHealth(res.ok ? 'online' : 'offline');
    } catch {
      // A timed-out or refused ping is the disconnect this hook exists to show.
      setHealth('offline');
    } finally {
      if (!initialised.current) initialised.current = true;
    }
  }, { enabled: !USE_MOCK_API, intervalMs, timeoutMs: 5_000 });

  return health;
}
