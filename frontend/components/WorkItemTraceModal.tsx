import React, { useEffect, useState } from 'react';
import { getWorkItemTrace } from '../services/apiClient';
import {
  describeTraceStageStatus,
  describeTraceStatus,
  sortTraceStages,
  summarizeTrace,
  traceEvidenceRows,
  traceIdentityPairs,
  type TraceSeverity,
  type WorkItemTrace,
} from '../lib/workItemTrace';

interface WorkItemTraceModalProps {
  /** Any id the chain minted: packetId, packaging runId, dispatch runId, agent-run id. */
  traceId: string;
  onClose: () => void;
}

const SEVERITY_CLASSES: Record<TraceSeverity, string> = {
  ok: 'border-emerald-700/50 bg-emerald-900/20 text-emerald-200',
  active: 'border-sky-700/50 bg-sky-900/20 text-sky-200',
  error: 'border-red-700/60 bg-red-900/25 text-red-100',
  // A gap gets amber and its own label — it is neither progress nor failure,
  // it is a link in the chain that nothing ever recorded.
  gap: 'border-amber-600/60 bg-amber-900/25 text-amber-100',
  idle: 'border-slate-700/60 bg-slate-800/40 text-slate-400',
};

const RAIL_CLASSES: Record<TraceSeverity, string> = {
  ok: 'bg-emerald-500',
  active: 'bg-sky-500',
  error: 'bg-red-500',
  gap: 'bg-amber-500',
  idle: 'bg-slate-600',
};

/**
 * One work item's whole life, in one place.
 *
 * Before this view, answering "what happened to this item?" meant reading the
 * packaging ledger, the dispatch queue, the runner's run summary, the agent-run
 * record and the merge-readiness snapshot, and inferring the links between
 * them. The trace makes the join explicit — and, more usefully, names the links
 * that are broken instead of leaving a blank that reads like "not yet".
 */
const WorkItemTraceModal: React.FC<WorkItemTraceModalProps> = ({ traceId, onClose }) => {
  const [trace, setTrace] = useState<WorkItemTrace | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [reloadToken, setReloadToken] = useState(0);

  // The fetch is the effect; every setState here happens after an await, so the
  // effect never triggers a synchronous cascading render. `cancelled` keeps a
  // slow response from writing state into an unmounted modal — closing the
  // modal mid-request is the ordinary case, not an edge one.
  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const data = await getWorkItemTrace(traceId);
        if (cancelled) return;
        setTrace(data);
        setError(null);
      } catch (e) {
        if (cancelled) return;
        setTrace(null);
        setError(e instanceof Error ? e.message : 'Could not load the trace for this work item.');
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();
    return () => { cancelled = true; };
  }, [traceId, reloadToken]);

  const reload = () => {
    setLoading(true);
    setReloadToken(token => token + 1);
  };

  const stages = sortTraceStages(trace?.stages ?? []);
  const rollup = describeTraceStatus(trace?.status ?? '');

  return (
    <div className="fixed inset-0 bg-black/70 flex items-center justify-center z-50 p-4">
      <div
        data-testid="work-item-trace-modal"
        className="mobile-sheet bg-gray-900 border border-gray-700 rounded-xl shadow-2xl w-full max-w-3xl max-h-[90vh] flex flex-col"
      >
        <div className="flex items-center justify-between gap-3 px-5 py-4 border-b border-gray-700 flex-shrink-0">
          <div className="min-w-0">
            <h2 className="text-base font-semibold text-white">Work item trace</h2>
            <p className="mt-0.5 break-all font-mono text-xs text-gray-400">{traceId}</p>
          </div>
          <div className="flex flex-shrink-0 items-center gap-2">
            <button
              onClick={reload}
              disabled={loading}
              className="rounded border border-gray-600 px-2.5 py-1 text-xs font-medium text-gray-200 transition-colors hover:bg-gray-700 disabled:cursor-not-allowed disabled:opacity-50"
            >
              {loading ? 'Loading…' : 'Refresh'}
            </button>
            <button
              onClick={onClose}
              aria-label="Close"
              className="text-lg leading-none text-gray-400 transition-colors hover:text-white"
            >
              ✕
            </button>
          </div>
        </div>

        <div className="flex-1 overflow-y-auto px-5 py-4">
          {loading && (
            <p data-testid="work-item-trace-loading" className="py-10 text-center text-sm text-gray-400">
              Joining the stage ledgers…
            </p>
          )}

          {!loading && error && (
            <div role="alert" data-testid="work-item-trace-error" className="rounded border border-red-800/50 bg-red-900/20 px-4 py-3 text-sm text-red-200">
              {error}
            </div>
          )}

          {!loading && !error && trace && (
            <>
              <div className="mb-4 rounded-lg border border-gray-700 bg-gray-800/40 px-4 py-3">
                <div className="flex flex-wrap items-center gap-2">
                  <span
                    data-testid="work-item-trace-status"
                    className={`rounded border px-2 py-0.5 text-xs font-semibold ${SEVERITY_CLASSES[rollup.severity]}`}
                  >
                    {rollup.label}
                  </span>
                  {trace.hasGaps && (
                    <span
                      data-testid="work-item-trace-gap-count"
                      className={`rounded border px-2 py-0.5 text-xs font-semibold ${SEVERITY_CLASSES.gap}`}
                    >
                      {trace.gaps.length} broken link{trace.gaps.length === 1 ? '' : 's'}
                    </span>
                  )}
                  {trace.identity?.repoName && (
                    <span className="rounded border border-gray-600 px-2 py-0.5 text-xs text-gray-300">
                      {trace.identity.repoName}
                    </span>
                  )}
                </div>
                <p data-testid="work-item-trace-summary" className="mt-2 text-sm text-gray-200">
                  {summarizeTrace(trace)}
                </p>
                {trace.identity?.itemText && (
                  <p className="mt-1 break-words text-sm text-gray-400">{trace.identity.itemText}</p>
                )}
                <div className="mt-2 flex flex-wrap items-center gap-x-4 gap-y-1 text-[11px] text-gray-500">
                  {traceIdentityPairs(trace).map(pair => (
                    <span key={pair.label}>
                      {pair.label}: <code className="rounded bg-gray-800 px-1 py-0.5 text-gray-300">{pair.value}</code>
                    </span>
                  ))}
                  {trace.identity?.prUrl && (
                    <a
                      href={trace.identity.prUrl}
                      target="_blank"
                      rel="noreferrer"
                      className="text-sky-400 underline hover:text-sky-300"
                    >
                      Pull request
                    </a>
                  )}
                </div>
              </div>

              <ol className="space-y-2">
                {stages.map(stage => {
                  const view = describeTraceStageStatus(String(stage.status));
                  const rows = traceEvidenceRows(stage);
                  return (
                    <li
                      key={String(stage.stage)}
                      data-testid="work-item-trace-stage"
                      data-stage={String(stage.stage)}
                      data-stage-status={String(stage.status)}
                      className="flex gap-3 rounded-lg border border-gray-700 bg-gray-900/60 p-3"
                    >
                      <div className="flex flex-col items-center pt-1">
                        <span className={`h-2.5 w-2.5 flex-shrink-0 rounded-full ${RAIL_CLASSES[view.severity]}`} />
                        <span className="mt-1 flex-1 w-px bg-gray-700" />
                      </div>
                      <div className="min-w-0 flex-1">
                        <div className="flex flex-wrap items-center gap-2">
                          <span className="text-sm font-medium text-gray-100">
                            {stage.order}. {stage.label}
                          </span>
                          <span className={`rounded border px-1.5 py-0.5 text-[11px] font-semibold ${SEVERITY_CLASSES[view.severity]}`}>
                            {view.label}
                          </span>
                          {stage.at && <span className="text-[11px] text-gray-500">{stage.at}</span>}
                        </div>
                        <p className="mt-1 break-words text-xs text-gray-300">{stage.detail}</p>
                        {rows.length > 0 && (
                          <dl className="mt-1.5 grid grid-cols-1 gap-x-4 gap-y-0.5 text-[11px] text-gray-400 sm:grid-cols-2">
                            {rows.map(row => (
                              <div key={row.label} className="flex gap-1">
                                <dt className="flex-shrink-0 text-gray-500">{row.label}:</dt>
                                <dd className="min-w-0 break-words text-gray-300">{row.value}</dd>
                              </div>
                            ))}
                          </dl>
                        )}
                        {stage.artifact && (
                          <p className="mt-1 break-all font-mono text-[11px] text-gray-600">{stage.artifact}</p>
                        )}
                      </div>
                    </li>
                  );
                })}
              </ol>
            </>
          )}
        </div>
      </div>
    </div>
  );
};

export default WorkItemTraceModal;
