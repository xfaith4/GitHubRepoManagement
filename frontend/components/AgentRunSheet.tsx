/**
 * Release 2.9 — the tap-through agent-run list.
 *
 * The activity indicator has said "3 agent runs" since Release 2.5, and until
 * now the only way to learn WHICH three was to hover it — which does nothing
 * on a phone — or to open Operations, pick a repository, and find the runs
 * panel inside it. On the device the operator is most likely to be holding
 * when they want that answer, the answer was unreachable.
 *
 * This is the list behind the pill. It reuses the `mobile-sheet` class from
 * the Release 2.5 foundation, so on a phone it takes the whole viewport and on
 * a desktop it is an ordinary centered dialog.
 *
 * It shows what someone checking on work in progress actually needs: which
 * repository, what state, what the agent was asked to do, and a way through to
 * the pull request if one exists. It is deliberately read-only — a sheet
 * opened from a status pill is a place to look, not a place to dispatch from.
 */
import { useEffect, useState } from 'react';
import { getAgentRuns } from '../services/apiClient';
import type { AgentRun } from '../types';

interface AgentRunSheetProps {
  onClose: () => void;
}

const STATUS_STYLES: Record<string, string> = {
  active: 'bg-green-900/50 text-green-300 border-green-700',
  dispatched: 'bg-blue-900/50 text-blue-300 border-blue-700',
  completed: 'bg-gray-700 text-gray-300 border-gray-600',
  failed: 'bg-red-900/50 text-red-300 border-red-700',
  blocked: 'bg-amber-900/50 text-amber-300 border-amber-700',
};

function formatWhen(value: string | null | undefined): string {
  if (!value) return '';
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) return '';
  return parsed.toLocaleString();
}

const AgentRunSheet = ({ onClose }: AgentRunSheetProps) => {
  const [runs, setRuns] = useState<AgentRun[] | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    getAgentRuns({ limit: 25 })
      .then(result => { if (!cancelled) { setRuns(result.items); setError(null); } })
      .catch(err => { if (!cancelled) setError(err instanceof Error ? err.message : 'Could not load agent runs.'); });
    return () => { cancelled = true; };
  }, []);

  // Escape closes, because a full-screen sheet with no visible page behind it
  // needs a way out that is not a hunt for the X.
  useEffect(() => {
    const onKey = (event: KeyboardEvent) => { if (event.key === 'Escape') onClose(); };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [onClose]);

  return (
    <div className="fixed inset-0 z-50 bg-black/70 flex items-center justify-center p-4" data-testid="agent-run-sheet-overlay">
      <div
        role="dialog"
        aria-modal="true"
        aria-labelledby="agent-run-sheet-title"
        data-testid="agent-run-sheet"
        className="mobile-sheet bg-gray-900 border border-gray-700 rounded-lg w-full max-w-2xl max-h-[85vh] flex flex-col"
      >
        <div className="flex items-center justify-between px-4 py-3 border-b border-gray-700">
          <h2 id="agent-run-sheet-title" className="text-sm font-semibold text-gray-100">Agent runs</h2>
          <button
            type="button"
            onClick={onClose}
            aria-label="Close agent runs"
            data-testid="agent-run-sheet-close"
            className="px-2 text-gray-400 hover:text-gray-100"
          >
            ✕
          </button>
        </div>

        <div className="overflow-y-auto px-4 py-3 flex-1">
          {error ? (
            <p role="alert" className="text-sm text-red-300" data-testid="agent-run-sheet-error">{error}</p>
          ) : runs === null ? (
            <p className="text-sm text-gray-400" role="status" data-testid="agent-run-sheet-loading">Loading agent runs…</p>
          ) : runs.length === 0 ? (
            // An empty list states what it means and what would change it,
            // rather than showing a blank panel that reads as broken.
            <p className="text-sm text-gray-400" data-testid="agent-run-sheet-empty">
              No agent runs recorded yet. Dispatch a packaged roadmap item and its run appears here.
            </p>
          ) : (
            <ul className="divide-y divide-gray-800" data-testid="agent-run-sheet-list">
              {runs.map(run => (
                <li key={run.runId} className="py-3" data-testid="agent-run-sheet-item">
                  <div className="flex items-start justify-between gap-3">
                    <span className="text-sm text-gray-100 font-medium break-words">{run.repoName}</span>
                    <span
                      className={`shrink-0 px-2 py-0.5 rounded-full border text-xs ${STATUS_STYLES[String(run.status)] ?? 'bg-gray-700 text-gray-300 border-gray-600'}`}
                    >
                      {run.status}
                    </span>
                  </div>
                  {run.selectedTaskText ? (
                    <p className="mt-1 text-xs text-gray-400 break-words">{run.selectedTaskText}</p>
                  ) : null}
                  <div className="mt-1 flex flex-wrap items-center gap-x-3 gap-y-1 text-xs text-gray-500">
                    {run.branch ? <span className="break-all">{run.branch}</span> : null}
                    {formatWhen(run.updatedAt) ? <span>updated {formatWhen(run.updatedAt)}</span> : null}
                    {run.prUrl ? (
                      <a
                        href={run.prUrl}
                        target="_blank"
                        rel="noopener noreferrer"
                        role="button"
                        className="text-blue-400 hover:text-blue-300 underline"
                      >
                        {run.prNumber ? `PR #${run.prNumber}` : 'Pull request'}
                      </a>
                    ) : null}
                  </div>
                </li>
              ))}
            </ul>
          )}
        </div>
      </div>
    </div>
  );
};

export default AgentRunSheet;
