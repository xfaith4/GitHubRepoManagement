import React, { useState, useCallback, useEffect } from 'react';
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
    label: 'Blocked',
    badgeClass: 'bg-red-900/40 text-red-300 border-red-700/40',
    dotClass: 'bg-red-400',
  },
  complete: {
    label: 'Complete',
    badgeClass: 'bg-indigo-900/40 text-indigo-300 border-indigo-700/40',
    dotClass: 'bg-indigo-400',
  },
};

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
      <div className="flex-1 rounded-lg border border-dashed border-gray-700 bg-gray-900/40 flex items-center justify-center min-h-[120px] text-gray-600 text-sm">
        <div className="text-center">
          <div className="text-2xl mb-1">○</div>
          <div>{slotLabel} — Empty</div>
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
// Queue row for ranked ready repos
// ---------------------------------------------------------------------------
function QueueRow({
  entry,
  rank,
  onAssign,
  isBusy,
  lanesAvailable,
}: {
  entry: ExecutionLaneEntry;
  rank: number;
  onAssign: (repoName: string) => void;
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
        <button
          onClick={() => onAssign(entry.repoName)}
          disabled={isBusy || !lanesAvailable}
          className="text-xs px-2.5 py-1 rounded border border-blue-700/50 bg-blue-900/30 text-blue-300 hover:bg-blue-800/50 disabled:opacity-40 transition-colors"
          title={!lanesAvailable ? 'Both lanes are occupied' : `Dispatch ${entry.repoName} to next available lane`}
        >
          Dispatch
        </button>
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
// State counts panel
// ---------------------------------------------------------------------------
function StateCounts({ counts, total }: { counts: ExecutionQueueSummary['stateCounts']; total: number }) {
  const items: Array<{ key: ExecutionState; label: string }> = [
    { key: 'running', label: 'Running' },
    { key: 'ready', label: 'Ready' },
    { key: 'blocked', label: 'Blocked' },
    { key: 'complete', label: 'Complete' },
    { key: 'idle', label: 'Idle' },
  ];
  return (
    <div className="flex flex-wrap gap-2">
      {items.map(({ key, label }) => (
        <div
          key={key}
          className={`inline-flex items-center gap-1.5 px-2 py-1 rounded border text-xs ${STATE_CONFIG[key].badgeClass}`}
        >
          <span className={`inline-block w-1.5 h-1.5 rounded-full ${STATE_CONFIG[key].dotClass}`} />
          <span className="font-medium">{counts[key] ?? 0}</span>
          <span className="opacity-70">{label}</span>
        </div>
      ))}
      <div className="inline-flex items-center gap-1.5 px-2 py-1 rounded border border-gray-700 text-gray-400 text-xs">
        <span className="font-medium">{total}</span>
        <span className="opacity-70">Total</span>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Main ExecutionQueuePanel
// ---------------------------------------------------------------------------
interface ExecutionQueuePanelProps {
  onDispatchPreviewTask?: (repoName: string) => void;
}

type PanelTab = 'lanes' | 'queue' | 'history';

const ExecutionQueuePanel: React.FC<ExecutionQueuePanelProps> = ({ onDispatchPreviewTask }) => {
  const [queueData, setQueueData] = useState<ExecutionQueueSummary | null>(null);
  const [loading, setLoading] = useState(true);
  const [syncing, setSyncing] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [actionError, setActionError] = useState<string | null>(null);
  const [activeTab, setActiveTab] = useState<PanelTab>('lanes');

  const loadQueue = useCallback(async () => {
    try {
      const data = await getExecutionQueue();
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
  }, [loadQueue]);

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

  const lanesAvailable = (queueData?.activeLaneCount ?? 0) < 2;

  const tabs: Array<{ id: PanelTab; label: string; count?: number }> = [
    { id: 'lanes', label: 'Active Lanes', count: queueData?.activeLaneCount ?? 0 },
    { id: 'queue', label: 'Ready Queue', count: queueData?.rankedQueue?.length ?? 0 },
    { id: 'history', label: 'History', count: queueData?.recentHistory?.length ?? 0 },
  ];

  return (
    <div className="flex flex-col h-full min-h-0 text-sm">
      {/* Header */}
      <div className="flex items-center justify-between px-4 py-3 border-b border-gray-700 flex-shrink-0">
        <div>
          <h2 className="text-base font-semibold text-white">Execution Queue</h2>
          <p className="text-xs text-gray-500 mt-0.5">Two-lane Copilot dispatch console</p>
        </div>
        <div className="flex items-center gap-2">
          {queueData && (
            <StateCounts counts={queueData.stateCounts} total={queueData.totalRepos} />
          )}
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
      {error && (
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

      {/* Tab bar */}
      <div className="flex items-center gap-0 px-4 pt-3 border-b border-gray-700 flex-shrink-0">
        {tabs.map(tab => (
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

      {/* Content */}
      <div className="flex-1 overflow-y-auto min-h-0 px-4 py-4">
        {loading && !queueData && (
          <div className="flex items-center justify-center py-12 text-gray-500 gap-2">
            <SpinnerIcon className="w-4 h-4" />
            <span>Loading execution queue...</span>
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

        {queueData && activeTab === 'lanes' && (
          <div className="space-y-4">
            <div className="text-xs text-gray-500 mb-1">
              {queueData.activeLaneCount === 0
                ? 'No active lanes — dispatch from the Ready Queue below.'
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

            {/* Quick-dispatch from ranked queue if lanes available */}
            {lanesAvailable && queueData.rankedQueue.length > 0 && (
              <div className="mt-4">
                <div className="text-xs font-medium text-gray-400 uppercase tracking-wide mb-2">
                  Top Candidates
                </div>
                <div className="space-y-1.5">
                  {queueData.rankedQueue.slice(0, 3).map((entry, i) => (
                    <QueueRow
                      key={entry.repoName}
                      entry={entry}
                      rank={i + 1}
                      onAssign={repoName => {
                        if (onDispatchPreviewTask) {
                          onDispatchPreviewTask(repoName);
                        } else {
                          void handleAssign(repoName);
                        }
                      }}
                      isBusy={busy}
                      lanesAvailable={lanesAvailable}
                    />
                  ))}
                </div>
              </div>
            )}
          </div>
        )}

        {queueData && activeTab === 'queue' && (
          <div className="space-y-1.5">
            {queueData.rankedQueue.length === 0 ? (
              <div className="text-center py-8 text-gray-500">
                No repos in the ready queue.
                {queueData.stateCounts.idle > 0 && (
                  <p className="mt-1 text-xs">Click Sync to refresh from current audit data.</p>
                )}
              </div>
            ) : (
              queueData.rankedQueue.map((entry, i) => (
                <QueueRow
                  key={entry.repoName}
                  entry={entry}
                  rank={i + 1}
                  onAssign={repoName => {
                    if (onDispatchPreviewTask) {
                      onDispatchPreviewTask(repoName);
                    } else {
                      void handleAssign(repoName);
                    }
                  }}
                  isBusy={busy}
                  lanesAvailable={lanesAvailable}
                />
              ))
            )}

            {/* All entries — non-ready states */}
            {queueData.entries.filter(e => e.executionState !== 'ready').length > 0 && (
              <div className="mt-4">
                <div className="text-xs font-medium text-gray-600 uppercase tracking-wide mb-2 pt-2 border-t border-gray-800">
                  Other repos
                </div>
                <div className="space-y-1.5">
                  {queueData.entries
                    .filter(e => e.executionState !== 'ready')
                    .sort((a, b) => b.priorityScore - a.priorityScore)
                    .map(entry => (
                      <div key={entry.repoName} className="flex items-center gap-3 px-4 py-2 border border-gray-800/50 rounded-lg text-xs">
                        <div className="flex-1 min-w-0">
                          <span className="text-gray-300 truncate mr-2">{entry.repoName}</span>
                          <StateBadge state={entry.executionState} />
                        </div>
                        {entry.executionState === 'blocked' && (
                          <button
                            onClick={() => void handleRequeue(entry.repoName)}
                            disabled={busy}
                            className="px-2 py-0.5 rounded border border-yellow-700/50 bg-yellow-900/20 text-yellow-300 hover:bg-yellow-800/40 disabled:opacity-40 transition-colors"
                            title="Force requeue this repo"
                          >
                            Requeue
                          </button>
                        )}
                      </div>
                    ))}
                </div>
              </div>
            )}
          </div>
        )}

        {queueData && activeTab === 'history' && (
          <div>
            {queueData.recentHistory.length === 0 ? (
              <div className="text-center py-8 text-gray-500">No execution history yet.</div>
            ) : (
              <div className="divide-y divide-gray-800 rounded border border-gray-800 bg-gray-900/30 px-3 py-1">
                {[...queueData.recentHistory].reverse().map((item) => (
                  <HistoryRow key={`${item.repoName}-${item.timestamp}`} item={item} />
                ))}
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
