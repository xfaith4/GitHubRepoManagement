// Agent Ops data (2026-09-27) — one instance, owned by Dashboard.
//
// Two poll loops: the fast one (runs, runner presence, packages) every 15 s
// while the view is open and every 30 s otherwise, so the tab badge stays
// honest without doubling the load of the always-on activity pill; the slow
// one (ranked queue, roadmap index, provider availability) every 60 s. Each
// keeps its last good answer on error, as AgentActivityIndicator does — an
// unreachable host must not blank a board that was showing live work.
import { useCallback, useMemo, useState } from 'react';
import { usePollLoop } from './usePollLoop';
import {
  getAgentRuns,
  getExecutionQueue,
  getPackagedItems,
  getProviderAvailability,
  getRoadmapIndex,
  getRunnerPresence,
} from '../services/apiClient';
import type { AgentRun, ExecutionLaneEntry, ProviderAvailability, RoadmapEntry } from '../types';
import type { PackagedItem } from '../lib/packagedItems';
import type { RunnerPresencePayload } from '../lib/runnerPresence';
import type { ViewKey } from '../viewMeta';

export interface AgentOpsData {
  runs: AgentRun[];
  runner: RunnerPresencePayload | null;
  packages: PackagedItem[];
  queue: ExecutionLaneEntry[];
  roadmap: RoadmapEntry[];
  providers: ProviderAvailability[];
  /** When the fast loop last answered, for "Updated Xs ago". 0 until it has. */
  updatedAtMs: number;
  /** The fast loop has answered at least once. */
  loaded: boolean;
  /** The last fast-loop failure, kept beside the last good answer. */
  error: string | null;
  /** Re-run both loops now. */
  refresh: () => void;
}

const FAST_ACTIVE_MS = 15_000;
const FAST_IDLE_MS = 30_000;
const SLOW_MS = 60_000;

export function useAgentOpsData(options: { activeView: ViewKey }): AgentOpsData {
  // The hook, not Dashboard, knows which view it serves; Dashboard keeps no
  // per-view logic above its tab strip (the tab-panel tripwire).
  const active = options.activeView === 'agent-ops';
  const [runs, setRuns] = useState<AgentRun[]>([]);
  const [runner, setRunner] = useState<RunnerPresencePayload | null>(null);
  const [packages, setPackages] = useState<PackagedItem[]>([]);
  const [queue, setQueue] = useState<ExecutionLaneEntry[]>([]);
  const [roadmap, setRoadmap] = useState<RoadmapEntry[]>([]);
  const [providers, setProviders] = useState<ProviderAvailability[]>([]);
  const [updatedAtMs, setUpdatedAtMs] = useState(0);
  const [loaded, setLoaded] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const fast = usePollLoop(async (signal) => {
    const [runsResult, presence, packaged] = await Promise.allSettled([
      getAgentRuns({ limit: 60 }, { signal }),
      getRunnerPresence({ signal }),
      getPackagedItems('pending-approval', 50),
    ]);
    if (signal.aborted) return;
    if (runsResult.status === 'fulfilled') setRuns(runsResult.value.items);
    if (presence.status === 'fulfilled') setRunner(presence.value);
    if (packaged.status === 'fulfilled') setPackages(packaged.value.items);
    setLoaded(true);
    setUpdatedAtMs(Date.now());
    const failed = [runsResult, presence, packaged].find((r): r is PromiseRejectedResult => r.status === 'rejected');
    if (failed) {
      const reason = failed.reason instanceof Error ? failed.reason.message : String(failed.reason);
      setError(reason);
      throw failed.reason; // the helper backs off; the board keeps its last answer
    }
    setError(null);
  }, { intervalMs: active ? FAST_ACTIVE_MS : FAST_IDLE_MS });

  const slow = usePollLoop(async (signal) => {
    const [queueResult, index, availability] = await Promise.allSettled([
      getExecutionQueue(),
      getRoadmapIndex(),
      getProviderAvailability(),
    ]);
    if (signal.aborted) return;
    if (queueResult.status === 'fulfilled') setQueue(queueResult.value.rankedQueue ?? []);
    if (index.status === 'fulfilled') setRoadmap(index.value.entries ?? []);
    if (availability.status === 'fulfilled') setProviders(availability.value);
  }, { intervalMs: SLOW_MS });

  // Both runNow callbacks are stable (usePollLoop memoises them with no
  // dependencies), so refresh keeps one identity for the life of the hook.
  const fastRunNow = fast.runNow;
  const slowRunNow = slow.runNow;
  const refresh = useCallback(() => {
    fastRunNow();
    slowRunNow();
  }, [fastRunNow, slowRunNow]);

  return useMemo(() => ({
    runs, runner, packages, queue, roadmap, providers, updatedAtMs, loaded, error, refresh,
  }), [runs, runner, packages, queue, roadmap, providers, updatedAtMs, loaded, error, refresh]);
}

export default useAgentOpsData;
