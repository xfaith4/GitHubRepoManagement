import React, { useState, useCallback, useEffect } from 'react';
import { withPanelTimeout } from '../lib/asyncPanel';
import { type ExecutionQueueSummary, type ExecutionLaneEntry, type ExecutionHistoryRecord, type ExecutionState } from '../types';
import { SpinnerIcon } from './icons';
import { getExecutionQueue, syncExecutionQueue, assignExecutionLane, completeExecutionTask, cancelExecutionTask, requeueExecution } from '../services/apiClient';

// ---------------------------------------------------------------------------
// State badge configuration
// ---------------------------------------------------------------------------
const STATE_CONFIG: Record<ExecutionState, { label: string; badgeClass: string; dotClass: string }> = {
  idle: {
    label: 'Idle',
    badgeClass: 'bg-gray-800 text-gray-400 border-gray-600',
    dotClass: 'bg-gray-500',
  },
  ready: {
    label: 'Ready',
    badgeClass: 'bg-green-900/40 text-green-300 border-green-700/40',
    dotClass: 'bg-green-400',
  },
  running: {
    label: 'Running',
    badgeClass: 'bg-blue-900/40 text-blue-300 border-blue-700/40',
    dotClass: 'bg-blue-400 animate-pulse',
  },
  blocked: {
    label: 'Execution blocked',
    badgeClass: 'bg-red-900/40 text-red-300 border-red-700/40',
    dotClass: 'bg-red-400',
  },
  complete: {
    label: 'Complete',
    badgeClass: 'bg-indigo-900/40 text-indigo-300 border-indigo-700/40',
    dotClass: 'bg-indigo-400',
  },
};

const STATE_ORDER: ExecutionState[] = ['running', 'ready', 'blocked', 'complete', 'idle'];

function StateBadge({ state }: { state: ExecutionState }) {
  const cfg = STATE_CONFIG[state] ?? STATE_CONFIG['idle'];
  return (
    <span className={`inline-flex items-center gap-1 px-1.5 py-0.5 rounded border text-xs font-medium ${cfg.badgeClass}`}>
      <span className={`inline-block w-1.5 h-1.5 rounded-full ${cfg.dotClass}`} />
      {cfg.label}
    </span>
  );
}

// ---------------------------------------------------------------------------
// Lane slot card
// ---------------------------------------------------------------------------
function LaneCard({
  slotLabel,
  entry,
  onCancel,
  onComplete,
  isBusy,
}: {
  slotLabel: string;
  entry: ExecutionLaneEntry | null;
  onCancel: (repoName: string) => void;
  onComplete: (repoName: string) => void;
  isBusy: boolean;
}) {
  if (!entry) {
    return (
      <div
        data-testid="execution-lane-empty"
        className="flex-1 rounded-lg border border-dashed border-gray-700 bg-gray-900/40 flex items-center justify-center min-h-[120px] text-gray-500 text-sm"
      >
        <div className="text-center px-3">
          <div className="text-2xl mb-1">○</div>
          <div className="font-medium text-gray-400">{slotLabel} — Empty</div>
          <div className="text-xs text-gray-500 mt-1">
            Dispatch a repo from the queue below to start work in this lane.
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="flex-1 rounded-lg border border-blue-700/50 bg-blue-900/10 p-4 min-h-[120px]">
      <div className="flex items-start justify-between gap-2 mb-2">
        <div className="font-medium text-sm text-white truncate flex-1">{entry.repoName}</div>
        <div className="flex-shrink-0 flex items-center gap-1.5">
          <StateBadge state={entry.executionState} />
          <span className="text-xs text-gray-500">#{entry.laneSlot}</span>
        </div>
      </div>

      {entry.currentTaskText && (
        <div className="text-xs text-gray-300 mb-1 line-clamp-2 leading-relaxed">
          <span className="text-gray-500">Task: </span>
          {entry.currentTaskText}
        </div>
      )}
      {entry.currentTaskSection && (
        <div className="text-xs text-gray-500 mb-2">{entry.currentTaskSection}</div>
      )}
      {entry.assignedAt && (
        <div className="text-xs text-gray-600">
          Started {new Date(entry.assignedAt).toLocaleTimeString()}
        </div>
      )}

      <div className="flex gap-1.5 mt-3">
        <button
          onClick={() => onComplete(entry.repoName)}
          disabled={isBusy}
          className="text-xs px-2 py-1 rounded border border-green-700/50 bg-green-900/30 text-green-300 hover:bg-green-800/50 disabled:opacity-40 transition-colors"
          title="Mark task complete"
        >
          Complete
        </button>
        <button
          onClick={() => onCancel(entry.repoName)}
          disabled={isBusy}
          className="text-xs px-2 py-1 rounded border border-red-700/50 bg-red-900/30 text-red-300 hover:bg-red-800/50 disabled:opacity-40 transition-colors"
          title="Cancel / fail task"
        >
          Cancel
        </button>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// State filter tiles — Lane 0.17: the counts are the filters. Each tile
// filters the ledger list below; counts always describe the whole ledger,
// never the filtered subset.
// ---------------------------------------------------------------------------
function StateFilterTiles({
  counts,
  total,
  activeFilter,
  onFilterChange,
}: {
  counts: ExecutionQueueSummary['stateCounts'];
  total: number;
  activeFilter: ExecutionState | null;
  onFilterChange: (state: ExecutionState | null) => void;
}) {
  return (
    <div className="flex flex-wrap gap-2" role="group" aria-label="Filter queue by state">
      {STATE_ORDER.map(key => {
        const cfg = STATE_CONFIG[key];
        const selected = activeFilter === key;
        return (
          <button
            key={key}
            type="button"
            aria-pressed={selected}
            onClick={() => onFilterChange(selected ? null : key)}
            className={`inline-flex items-center gap-1.5 px-2.5 py-1 rounded border text-sm transition-colors ${cfg.badgeClass} ${
              selected ? 'ring-2 ring-blue-400/70 opacity-100' : 'opacity-70 hover:opacity-100'
            }`}
            title={selected ? `Showing ${cfg.label} — click to show all` : `Show only ${cfg.label}`}
          >
            <span className={`inline-block w-1.5 h-1.5 rounded-full ${cfg.dotClass}`} />
            <span className="font-medium">{counts[key] ?? 0}</span>
            <span className="opacity-80">{cfg.label}</span>
            {key === 'blocked' && <span>of {total} ledger repositories</span>}
          </button>
        );
      })}
      <button
        type="button"
        aria-pressed={activeFilter === null}
        onClick={() => onFilterChange(null)}
        className={`inline-flex items-center gap-1.5 px-2.5 py-1 rounded border border-gray-700 text-gray-400 text-sm transition-colors ${
          activeFilter === null ? 'ring-2 ring-blue-400/70 opacity-100' : 'opacity-70 hover:opacity-100'
        }`}
        title="Show every repo in the ledger"
      >
        <span className="font-medium">{total}</span>
        <span className="opacity-80">Total</span>
      </button>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Queue row — one row shape for every ledger state; the action follows the
// state (Dispatch for ready, Requeue for blocked, none otherwise).
// ---------------------------------------------------------------------------
function QueueRow({
  entry,
  rank,
  onDispatch,
  onRequeue,
  isBusy,
  lanesAvailable,
}: {
  entry: ExecutionLaneEntry;
  rank: number;
  onDispatch: (entry: ExecutionLaneEntry) => void;
  onRequeue: (repoName: string) => void;
  isBusy: boolean;
  lanesAvailable: boolean;
}) {
  return (
    <div className="flex items-center gap-3 px-4 py-2.5 border border-gray-700/50 rounded-lg bg-gray-800/40 hover:bg-gray-700/40 transition-colors">
      <span className="text-xs text-gray-500 w-5 text-right flex-shrink-0">#{rank}</span>
      <div className="flex-1 min-w-0">
        <div className="flex items-center gap-2">
          <span className="text-sm font-medium text-white truncate">{entry.repoName}</span>
          <StateBadge state={entry.executionState} />
          <span className="text-xs text-gray-500 ml-auto flex-shrink-0" title="Priority score">
            ↑{entry.priorityScore}
          </span>
        </div>
        {entry.currentTaskText && (
          <div className="text-xs text-gray-400 truncate mt-0.5" title={entry.currentTaskText}>
            {entry.currentTaskText}
          </div>
        )}
        {entry.errorMessage && (
          <div className="text-xs text-red-400 truncate mt-0.5" title={entry.errorMessage}>
            ⚠ {entry.errorMessage}
          </div>
        )}
      </div>
      <div className="flex-shrink-0">
        {entry.executionState === 'ready' && (
          <button
            onClick={() => onDispatch(entry)}
            disabled={isBusy || !lanesAvailable}
            className="text-xs px-2.5 py-1 rounded border border-blue-700/50 bg-blue-900/30 text-blue-300 hover:bg-blue-800/50 disabled:opacity-40 transition-colors"
            title={!lanesAvailable ? 'Both lanes are occupied' : `Preview and dispatch ${entry.repoName}`}
          >
            Dispatch
          </button>
        )}
        {entry.executionState === 'blocked' && (
          <button
            onClick={() => onRequeue(entry.repoName)}
            disabled={isBusy}
            className="text-xs px-2.5 py-1 rounded border border-yellow-700/50 bg-yellow-900/20 text-yellow-300 hover:bg-yellow-800/40 disabled:opacity-40 transition-colors"
            title="Force requeue this repo"
          >
            Requeue
          </button>
        )}
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// History item row
// ---------------------------------------------------------------------------
function HistoryRow({ item }: { item: ExecutionHistoryRecord }) {
  const eventColors: Record<string, string> = {
    assigned: 'text-blue-400',
    completed: 'text-green-400',
    cancelled: 'text-red-400',
    requeued: 'text-yellow-400',
  };
  const color = eventColors[item.event] ?? 'text-gray-400';
  return (
    <div className="flex items-start gap-2 text-xs py-1 border-b border-gray-800 last:border-0">
      <span className="text-gray-600 flex-shrink-0 w-20">
        {new Date(item.timestamp).toLocaleTimeString()}
      </span>
      <span className={`font-medium flex-shrink-0 w-16 ${color}`}>{item.event}</span>
      <span className="text-gray-300 truncate flex-1">{item.repoName}</span>
      {item.taskText && (
        <span className="text-gray-500 truncate max-w-[200px]" title={item.taskText}>
          {item.taskText}
        </span>
      )}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Main ExecutionQueuePanel — Lane 0.17: one board, not three tabs. The two
// lanes stay pinned (they are the page's unique answer to "what is in
// progress?"); beneath them one ranked ledger list is filtered by the state
// tiles; History is the only remaining tab.
// ---------------------------------------------------------------------------
interface ExecutionQueuePanelProps {
  onDispatchPreviewTask?: (repoName: string, roadmapPath?: string) => void;
  /** Bump to reload the queue after an external action (e.g. a dispatch from the preview modal). */
  refreshToken?: number;
}

type PanelTab = 'queue' | 'history';

const ExecutionQueuePanel: React.FC<ExecutionQueuePanelProps> = ({ onDispatchPreviewTask, refreshToken }) => {
  const [queueData, setQueueData] = useState<ExecutionQueueSummary | null>(null);
  const [loading, setLoading] = useState(true);
  const [syncing, setSyncing] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [actionError, setActionError] = useState<string | null>(null);
  const [activeTab, setActiveTab] = useState<PanelTab>('queue');
  const [stateFilter, setStateFilter] = useState<ExecutionState | null>('ready');

  const loadQueue = useCallback(async () => {
    try {
      // Release 3.5 milestone 5 — a hung fetch becomes an error at 10s
      // instead of a spinner that outlives the request behind it.
      const data = await withPanelTimeout(getExecutionQueue(), '/api/execution/queue');
      setQueueData(data);
      setError(null);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load execution queue');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void loadQueue();
  }, [loadQueue, refreshToken]);

  const handleSync = useCallback(async () => {
    setSyncing(true);
    setActionError(null);
    try {
      const data = await syncExecutionQueue();
      setQueueData(data);
    } catch (err) {
      setActionError(err instanceof Error ? err.message : 'Sync failed');
    } finally {
      setSyncing(false);
    }
  }, []);

  const handleAssign = useCallback(async (repoName: string) => {
    setBusy(true);
    setActionError(null);
    try {
      const result = await assignExecutionLane(repoName);
      if (!result.success) {
        setActionError(result.error ?? 'Failed to assign lane');
      }
      await loadQueue();
    } catch (err) {
      setActionError(err instanceof Error ? err.message : 'Assign failed');
    } finally {
      setBusy(false);
    }
  }, [loadQueue]);

  const handleComplete = useCallback(async (repoName: string) => {
    setBusy(true);
    setActionError(null);
    try {
      const result = await completeExecutionTask(repoName, { hasRemainingWork: true });
      if (!result.success) {
        setActionError(result.error ?? 'Failed to complete task');
      }
      await loadQueue();
    } catch (err) {
      setActionError(err instanceof Error ? err.message : 'Complete failed');
    } finally {
      setBusy(false);
    }
  }, [loadQueue]);

  const handleCancel = useCallback(async (repoName: string) => {
    setBusy(true);
    setActionError(null);
    try {
      const result = await cancelExecutionTask(repoName, 'cancelled');
      if (!result.success) {
        setActionError(result.error ?? 'Failed to cancel task');
      }
      await loadQueue();
    } catch (err) {
      setActionError(err instanceof Error ? err.message : 'Cancel failed');
    } finally {
      setBusy(false);
    }
  }, [loadQueue]);

  const handleRequeue = useCallback(async (repoName: string) => {
    setBusy(true);
    setActionError(null);
    try {
      const result = await requeueExecution(repoName, true);
      if (!result.success) {
        setActionError(result.error ?? 'Failed to requeue');
      }
      await loadQueue();
    } catch (err) {
      setActionError(err instanceof Error ? err.message : 'Requeue failed');
    } finally {
      setBusy(false);
    }
  }, [loadQueue]);

  const handleDispatch = useCallback((entry: ExecutionLaneEntry) => {
    if (onDispatchPreviewTask) {
      // Lane 0.17 — carry the ledger's known roadmap path into the preview so
      // the packet build never depends on a warm roadmap cache.
      onDispatchPreviewTask(entry.repoName, entry.roadmapPath || undefined);
    } else {
      void handleAssign(entry.repoName);
    }
  }, [onDispatchPreviewTask, handleAssign]);

  const lanesAvailable = (queueData?.activeLaneCount ?? 0) < 2;
  const recentHistory = Array.isArray(queueData?.recentHistory) ? queueData.recentHistory : [];
  const allEntries = Array.isArray(queueData?.entries) ? queueData.entries : [];
  const rankedEntries = [...allEntries].sort((a, b) => b.priorityScore - a.priorityScore);
  const visibleEntries = stateFilter === null
    ? rankedEntries
    : rankedEntries.filter(e => e.executionState === stateFilter);

  return (
    <div className="flex flex-col h-full min-h-0 text-sm">
      {/* Header — the view header above the panel already carries the question
          and subtitle; repeating them here was pure noise. */}
      <div className="flex items-center justify-between px-4 py-3 border-b border-gray-700 flex-shrink-0">
        <h2 className="text-base font-semibold text-white">Dispatch Board</h2>
        <div className="flex items-center gap-2">
          <button
            onClick={handleSync}
            disabled={syncing || busy}
            className="flex items-center gap-1.5 px-3 py-1.5 rounded border border-gray-600 bg-gray-800 text-gray-300 hover:bg-gray-700 disabled:opacity-50 text-xs transition-colors"
            title="Sync ledger from current audit data"
          >
            {syncing ? <SpinnerIcon className="w-3 h-3" /> : null}
            Sync
          </button>
          <button
            onClick={loadQueue}
            disabled={loading || busy}
            className="flex items-center gap-1.5 px-3 py-1.5 rounded border border-gray-600 bg-gray-800 text-gray-300 hover:bg-gray-700 disabled:opacity-50 text-xs transition-colors"
            title="Refresh queue"
          >
            {loading ? <SpinnerIcon className="w-3 h-3" /> : null}
            Refresh
          </button>
        </div>
      </div>

      {/* Error banners */}
      {error && queueData && (
        <div className="mx-4 mt-3 px-3 py-2 rounded border border-red-700/50 bg-red-900/20 text-red-300 text-xs flex-shrink-0">
          {error}
        </div>
      )}
      {actionError && (
        <div className="mx-4 mt-3 px-3 py-2 rounded border border-orange-700/50 bg-orange-900/20 text-orange-300 text-xs flex-shrink-0 flex items-start justify-between gap-2">
          <span>{actionError}</span>
          <button onClick={() => setActionError(null)} className="text-orange-400 hover:text-orange-200 flex-shrink-0">✕</button>
        </div>
      )}

      {/* Content */}
      <div className="flex-1 overflow-y-auto min-h-0 px-4 py-4">
        {loading && !queueData && (
          <div className="flex items-center justify-center py-12 text-gray-500 gap-2">
            <SpinnerIcon className="w-4 h-4" />
            <span>Loading execution queue...</span>
          </div>
        )}

        {/* Release 3.5 milestone 5 — a failure names its endpoint and offers
            retry; it must never be mistaken for an empty queue. */}
        {!loading && !queueData && error && (
          <div className="text-center py-12 text-sm" data-testid="execution-queue-error-state">
            <p className="mb-1 text-red-300">Execution queue failed to load.</p>
            <p className="text-gray-500 text-xs mb-3">{error}</p>
            <button
              onClick={() => { setLoading(true); void loadQueue(); }}
              className="px-4 py-2 rounded border border-gray-600 bg-gray-700 hover:bg-gray-600 text-gray-200 text-sm transition-colors"
            >
              Retry
            </button>
          </div>
        )}

        {!loading && !queueData && !error && (
          <div className="text-center py-12 text-gray-500">
            <p className="mb-3">No execution queue data yet.</p>
            <button
              onClick={handleSync}
              className="px-4 py-2 rounded border border-blue-700/50 bg-blue-900/30 text-blue-300 hover:bg-blue-800/50 text-sm transition-colors"
            >
              Sync from Audit Data
            </button>
          </div>
        )}

        {queueData && (
          <div className="space-y-4">
            {/* Lanes strip — always visible; the WIP limit is the page's core answer. */}
            <div>
              <div className="text-xs text-gray-500 mb-2">
                {queueData.activeLaneCount === 0
                  ? 'No active lanes — dispatch from the queue below.'
                  : `${queueData.activeLaneCount} of 2 lanes occupied.`}
              </div>
              <div className="flex gap-4">
                <LaneCard
                  slotLabel="Lane 1"
                  entry={queueData.lanes.lane1}
                  onCancel={handleCancel}
                  onComplete={handleComplete}
                  isBusy={busy}
                />
                <LaneCard
                  slotLabel="Lane 2"
                  entry={queueData.lanes.lane2}
                  onCancel={handleCancel}
                  onComplete={handleComplete}
                  isBusy={busy}
                />
              </div>
            </div>

            {/* Tab bar — Queue (the one filtered ledger list) and History. */}
            <div className="flex items-center gap-0 border-b border-gray-700">
              {([
                { id: 'queue' as PanelTab, label: 'Queue' },
                { id: 'history' as PanelTab, label: 'History', count: recentHistory.length },
              ]).map(tab => (
                <button
                  key={tab.id}
                  onClick={() => setActiveTab(tab.id)}
                  className={`px-4 py-2 text-xs font-medium border-b-2 transition-colors ${
                    activeTab === tab.id
                      ? 'border-blue-500 text-blue-300'
                      : 'border-transparent text-gray-500 hover:text-gray-300'
                  }`}
                >
                  {tab.label}
                  {tab.count !== undefined && (
                    <span className={`ml-1.5 px-1.5 py-0.5 rounded text-xs ${activeTab === tab.id ? 'bg-blue-900/50 text-blue-300' : 'bg-gray-800 text-gray-500'}`}>
                      {tab.count}
                    </span>
                  )}
                </button>
              ))}
            </div>

            {activeTab === 'queue' && (
              <div className="space-y-3">
                <StateFilterTiles
                  counts={queueData.stateCounts}
                  total={queueData.totalRepos}
                  activeFilter={stateFilter}
                  onFilterChange={setStateFilter}
                />

                {visibleEntries.length === 0 ? (
                  <div className="text-center py-8 text-gray-500">
                    {stateFilter === null
                      ? 'The ledger is empty — click Sync to build it from current audit data.'
                      : `No repos in the ${STATE_CONFIG[stateFilter].label} state.`}
                  </div>
                ) : (
                  <div className="space-y-1.5">
                    {visibleEntries.map((entry, i) => (
                      <QueueRow
                        key={entry.repoName}
                        entry={entry}
                        rank={i + 1}
                        onDispatch={handleDispatch}
                        onRequeue={repoName => { void handleRequeue(repoName); }}
                        isBusy={busy}
                        lanesAvailable={lanesAvailable}
                      />
                    ))}
                  </div>
                )}
              </div>
            )}

            {activeTab === 'history' && (
              <div>
                {recentHistory.length === 0 ? (
                  <div className="text-center py-8 text-gray-500">No execution history yet.</div>
                ) : (
                  <div className="divide-y divide-gray-800 rounded border border-gray-800 bg-gray-900/30 px-3 py-1">
                    {[...recentHistory].reverse().map((item) => (
                      <HistoryRow key={`${item.repoName}-${item.timestamp}`} item={item} />
                    ))}
                  </div>
                )}
              </div>
            )}
          </div>
        )}
      </div>

      {/* Footer */}
      {queueData && (
        <div className="flex-shrink-0 px-4 py-2 border-t border-gray-800 text-xs text-gray-600 text-right">
          Updated {new Date(queueData.updatedAt).toLocaleTimeString()}
        </div>
      )}
    </div>
  );
};

export default ExecutionQueuePanel;
