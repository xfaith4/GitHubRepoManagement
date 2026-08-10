import React, { useEffect, useState } from 'react';
import {
  applyRoadmapWriteBack,
  getWorkItemTrace,
  previewRoadmapWriteBack,
  WriteBackRefusedError,
} from '../services/apiClient';
import {
  describeTraceStageStatus,
  describeTraceStatus,
  sortTraceStages,
  summarizeTrace,
  summarizeWriteBackPreview,
  traceEvidenceRows,
  traceIdentityPairs,
  type TraceSeverity,
  type WorkItemTrace,
  type WriteBackPreview,
  type WriteBackRefusal,
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

  // Write-back is a separate, explicitly operator-driven step, so it keeps its
  // own state rather than folding into the trace fetch.
  const [wbBusy, setWbBusy] = useState(false);
  const [wbPreview, setWbPreview] = useState<WriteBackPreview | null>(null);
  const [wbRefusals, setWbRefusals] = useState<WriteBackRefusal[] | null>(null);
  const [wbError, setWbError] = useState<string | null>(null);
  const [wbApplied, setWbApplied] = useState<string | null>(null);
  const [wbConfirming, setWbConfirming] = useState(false);

  const reload = () => {
    setLoading(true);
    setReloadToken(token => token + 1);
  };

  const resetWriteBack = () => {
    setWbPreview(null);
    setWbRefusals(null);
    setWbError(null);
    setWbConfirming(false);
  };

  const runPreview = async () => {
    setWbBusy(true);
    resetWriteBack();
    setWbApplied(null);
    try {
      setWbPreview(await previewRoadmapWriteBack(traceId));
    } catch (e) {
      if (e instanceof WriteBackRefusedError) {
        setWbRefusals(e.refusals.length > 0 ? e.refusals : null);
        setWbError(e.message);
      } else {
        setWbError(e instanceof Error ? e.message : 'The completion preview failed.');
      }
    } finally {
      setWbBusy(false);
    }
  };

  // Applying edits a file in a DIFFERENT repository, so it confirms first —
  // the bulk-scope rule is that mutating actions always confirm.
  const runApply = async () => {
    if (!wbPreview?.previewId) return;
    setWbBusy(true);
    setWbError(null);
    try {
      const result = await applyRoadmapWriteBack(traceId, wbPreview.previewId, String(wbPreview.proposedContent ?? ''));
      setWbApplied(summarizeWriteBackPreview({ ...result, applied: true }));
      setWbPreview(null);
      setWbConfirming(false);
      reload();
    } catch (e) {
      if (e instanceof WriteBackRefusedError) {
        setWbRefusals(e.refusals.length > 0 ? e.refusals : null);
        setWbError(e.message);
      } else {
        setWbError(e instanceof Error ? e.message : 'Applying the completion edit failed.');
      }
      setWbConfirming(false);
    } finally {
      setWbBusy(false);
    }
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

              {/* The write-back gate, as a surface. The trace's last stage is
                  the only one an operator can act on from here, and doing so
                  edits a file in the MANAGED repo — never this one. */}
              <section data-testid="work-item-write-back" className="mt-4 rounded-lg border border-gray-700 bg-gray-800/40 px-4 py-3">
                <div className="flex flex-wrap items-center justify-between gap-2">
                  <div className="min-w-0">
                    <h3 className="text-sm font-semibold text-gray-100">Roadmap completion</h3>
                    <p className="mt-0.5 text-xs text-gray-400">
                      Marking this item complete requires a merged pull request with a successful validation run.
                      Code churn and a green check on an open PR are not completion.
                    </p>
                  </div>
                  <button
                    data-testid="work-item-write-back-preview"
                    onClick={() => { runPreview(); }}
                    disabled={wbBusy}
                    className="flex-shrink-0 rounded border border-gray-600 px-2.5 py-1 text-xs font-medium text-gray-200 transition-colors hover:bg-gray-700 disabled:cursor-not-allowed disabled:opacity-50"
                  >
                    {wbBusy ? 'Checking…' : 'Propose completion edit'}
                  </button>
                </div>

                {wbApplied && (
                  <p role="status" data-testid="work-item-write-back-applied" className="mt-2 rounded border border-emerald-800/50 bg-emerald-900/20 px-3 py-2 text-xs text-emerald-200">
                    {wbApplied}
                  </p>
                )}

                {wbError && (
                  <div role="alert" data-testid="work-item-write-back-refusal" className={`mt-2 rounded border px-3 py-2 text-xs ${SEVERITY_CLASSES.gap}`}>
                    <p className="font-medium">{wbError}</p>
                    {wbRefusals && (
                      <ul className="mt-1.5 space-y-1">
                        {wbRefusals.map(refusal => (
                          <li key={refusal.code}>
                            <code className="rounded bg-gray-900/60 px-1 py-0.5">{refusal.code}</code>{' '}
                            <span className="text-amber-200/90">{refusal.remedy}</span>
                          </li>
                        ))}
                      </ul>
                    )}
                  </div>
                )}

                {wbPreview && (
                  <div data-testid="work-item-write-back-preview-result" className="mt-2">
                    <p className="text-xs text-gray-300">{summarizeWriteBackPreview(wbPreview)}</p>
                    <div className="mt-1.5 overflow-x-auto rounded border border-gray-700 bg-gray-900/70">
                      <table className="w-full text-left font-mono text-[11px]">
                        <tbody>
                          {(wbPreview.diff ?? []).map(line => (
                            <React.Fragment key={line.line}>
                              <tr className="text-red-300/80">
                                <td className="w-12 select-none px-2 py-0.5 text-gray-600">{line.line}</td>
                                <td className="px-2 py-0.5">- {line.before}</td>
                              </tr>
                              <tr className="text-emerald-300/90">
                                <td className="select-none px-2 py-0.5" />
                                <td className="px-2 py-0.5">+ {line.after}</td>
                              </tr>
                            </React.Fragment>
                          ))}
                        </tbody>
                      </table>
                    </div>
                    <div className="mt-2 flex flex-wrap items-center gap-2">
                      {!wbConfirming ? (
                        <button
                          data-testid="work-item-write-back-apply"
                          onClick={() => setWbConfirming(true)}
                          disabled={wbBusy}
                          className="rounded border border-emerald-600/60 bg-emerald-900/30 px-2.5 py-1 text-xs font-semibold text-emerald-100 transition-colors hover:bg-emerald-800/40 disabled:cursor-not-allowed disabled:opacity-50"
                        >
                          Apply to the roadmap
                        </button>
                      ) : (
                        <>
                          <span data-testid="work-item-write-back-confirm-prompt" className="text-xs text-amber-200">
                            This writes to {wbPreview.roadmapPath}. Apply it?
                          </span>
                          <button
                            data-testid="work-item-write-back-confirm"
                            onClick={() => { runApply(); }}
                            disabled={wbBusy}
                            className="rounded border border-emerald-600/60 bg-emerald-900/30 px-2.5 py-1 text-xs font-semibold text-emerald-100 transition-colors hover:bg-emerald-800/40 disabled:cursor-not-allowed disabled:opacity-50"
                          >
                            {wbBusy ? 'Applying…' : 'Confirm'}
                          </button>
                          <button
                            data-testid="work-item-write-back-cancel"
                            onClick={() => setWbConfirming(false)}
                            disabled={wbBusy}
                            className="rounded border border-gray-600 px-2.5 py-1 text-xs font-medium text-gray-200 transition-colors hover:bg-gray-700 disabled:cursor-not-allowed disabled:opacity-50"
                          >
                            Cancel
                          </button>
                        </>
                      )}
                    </div>
                  </div>
                )}
              </section>
            </>
          )}
        </div>
      </div>
    </div>
  );
};

export default WorkItemTraceModal;
