import React, { useMemo, useState } from 'react';
import type { OperationsRepoEntry } from '../types';
import {
  type FoundationConclusionKind,
  FOUNDATION_CONCLUSIONS,
  describeConclusion,
  type ConclusionBasis,
} from '../lib/foundationConclusion';
import { buildOrientation, buildTodayRows, type TodayRankingInput, type TodayRow } from '../lib/todayRanking';

// Release 3.6 milestone 3 — the first interaction.
//
// The default view is a ranked table: what to do first, why now, one action per
// row, and what it will cost. Above it, one paragraph naming what the product
// evaluated and what it concluded — so a newcomer can tell from the first
// screen what this console is for.
//
// Every conclusion is filterable, `appropriate as-is` included. A repository
// with nothing to do is an outcome, not an omission.

const TONE_PILL: Record<'attention' | 'healthy' | 'unknown', string> = {
  attention: 'bg-amber-900/40 border-amber-600 text-amber-200',
  healthy: 'bg-emerald-900/30 border-emerald-600 text-emerald-200',
  unknown: 'bg-slate-800 border-slate-600 text-slate-300',
};

const EFFORT_TEXT: Record<'small' | 'medium' | 'large' | 'unknown', string> = {
  small: 'text-emerald-300',
  medium: 'text-amber-300',
  large: 'text-orange-300',
  unknown: 'text-gray-500',
};

export interface TodayViewProps {
  entries: OperationsRepoEntry[];
  /** Opens the repository — the outcome card is the detail behind a row. */
  onOpenRepo?: (repoId: string, repoName: string) => void;
  /** Runs a row's preview-first action. Omitted renders the label without a button. */
  onRunAction?: (row: TodayRow) => void;
  isLoading?: boolean;
  /**
   * The freshness payload the ranking was drawn from. NOT rendered: the
   * staleness banner was removed by operator decision (2026-08-30) — the
   * landing page must not open with a warning; do not reintroduce one here.
   * A new object marks the ranking as re-drawn, which re-arms the scan
   * control below.
   */
  basis?: ConclusionBasis;
  /**
   * Starts the background portfolio scan behind the toolbar control. Resolves
   * once the scan is started (not finished); progress lives in the header
   * chip. Omitted renders no control — a control with nothing behind it is
   * worse than no control.
   */
  onRunScan?: () => Promise<{ started: boolean; alreadyRunning: boolean }>;
}

function toRankingInput(entry: OperationsRepoEntry): TodayRankingInput {
  return {
    repoId: entry.repoId,
    repoName: entry.repoName,
    outcome: entry.outcome ?? null,
    topValueItem: entry.topValueItem
      ? { text: entry.topValueItem.text, valueScore: entry.topValueItem.valueScore, valueTier: entry.topValueItem.valueTier }
      : null,
    estimatedSessionWorkUnits: entry.estimatedSessionWorkUnits ?? null,
    pendingCount: entry.pendingCount,
    curationState: entry.curationState,
    lifecycleState: entry.lifecycleState,
  };
}

export const TodayView: React.FC<TodayViewProps> = ({ entries, onOpenRepo, onRunAction, isLoading = false, basis, onRunScan }) => {
  const [filter, setFilter] = useState<FoundationConclusionKind | null>(null);
  const [scanRequest, setScanRequest] = useState<'idle' | 'starting' | 'started' | 'already-running' | 'failed'>('idle');
  const [scanRequestError, setScanRequestError] = useState<string | null>(null);

  // A new basis means the ranking was re-drawn (the post-scan refresh, or any
  // other reload). If the index is still stale the button must come back —
  // otherwise one click is all the operator ever gets without a page reload.
  // Adjusted during render, not in an effect, so the stale note never paints.
  const [seenBasis, setSeenBasis] = useState<ConclusionBasis | undefined>(basis);
  if (seenBasis !== basis) {
    setSeenBasis(basis);
    if (scanRequest === 'started' || scanRequest === 'already-running') setScanRequest('idle');
  }

  const handleRunScan = async () => {
    if (!onRunScan) return;
    setScanRequest('starting');
    setScanRequestError(null);
    try {
      const result = await onRunScan();
      setScanRequest(result.alreadyRunning ? 'already-running' : 'started');
    } catch (err) {
      setScanRequest('failed');
      setScanRequestError(err instanceof Error ? err.message : 'The scan could not be started.');
    }
  };

  const allRows = useMemo(() => buildTodayRows(entries.map(toRankingInput)), [entries]);
  const orientation = useMemo(() => buildOrientation(allRows), [allRows]);
  const counts = useMemo(() => {
    const acc: Record<string, number> = {};
    for (const row of allRows) acc[row.conclusion] = (acc[row.conclusion] ?? 0) + 1;
    return acc;
  }, [allRows]);
  const rows = useMemo(() => (filter ? allRows.filter(row => row.conclusion === filter) : allRows), [allRows, filter]);

  return (
    <div className="p-4 space-y-4">
      {/* No staleness banner here, deliberately. Lane 0.13 shipped one and the
          operator removed it (2026-08-30): the landing page opening with an
          amber warning reads as a broken product, which costs more confidence
          than the verdict earns. The verdict still rides every payload as
          `basis`; the remedy survives as the quiet scan control in the filter
          row below. Do not reintroduce a warning banner on this view. */}

      {/* Orientation — what this product evaluated and what it concluded. */}
      <p data-testid="today-orientation" className="text-sm text-gray-300 leading-relaxed max-w-4xl">
        {orientation}
      </p>

      {/* Every conclusion filters the same way. */}
      <div className="flex gap-2 flex-wrap items-center">
        <button
          type="button"
          onClick={() => setFilter(null)}
          aria-pressed={filter === null}
          className={`text-xs px-3 py-1.5 rounded-full border transition-colors ${filter === null ? 'bg-indigo-600 border-indigo-500 text-white' : 'bg-gray-800 border-gray-700 text-gray-300 hover:border-gray-500'}`}
        >
          All {allRows.length}
        </button>
        {FOUNDATION_CONCLUSIONS.map(kind => {
          const presentation = describeConclusion(kind);
          const count = counts[kind] ?? 0;
          return (
            <button
              key={kind}
              type="button"
              onClick={() => setFilter(filter === kind ? null : kind)}
              aria-pressed={filter === kind}
              className={`text-xs px-3 py-1.5 rounded-full border transition-colors ${filter === kind ? 'bg-indigo-600 border-indigo-500 text-white' : `${TONE_PILL[presentation.tone]} hover:brightness-125`}`}
            >
              {presentation.label} {count}
            </button>
          );
        })}
        {onRunScan && (
          <div className="ml-auto flex items-center gap-2">
            {scanRequest !== 'started' && scanRequest !== 'already-running' && (
              <button
                type="button"
                onClick={handleRunScan}
                disabled={scanRequest === 'starting'}
                title="Rebuild the index behind this ranking. Progress shows in the header; the ranking refreshes when the scan completes."
                className="text-sm px-3 py-1.5 rounded border border-gray-600 bg-gray-800 text-gray-300 hover:border-gray-500 hover:text-white disabled:opacity-50 transition-colors"
              >
                {scanRequest === 'starting' ? 'Starting scan…' : 'Run portfolio scan'}
              </button>
            )}
            {scanRequest === 'started' && (
              <span data-testid="today-scan-note" className="text-sm text-gray-400">
                Scan started — this ranking refreshes when it completes.
              </span>
            )}
            {scanRequest === 'already-running' && (
              <span data-testid="today-scan-note" className="text-sm text-gray-400">
                A scan is already running — this ranking refreshes when it completes.
              </span>
            )}
            {scanRequest === 'failed' && scanRequestError && (
              <span data-testid="today-scan-note" className="text-sm text-red-300">
                {scanRequestError}
              </span>
            )}
          </div>
        )}
      </div>

      {isLoading && <p className="text-xs text-gray-500">Loading the portfolio…</p>}

      {!isLoading && rows.length === 0 && (
        <p data-testid="today-empty" className="text-sm text-gray-400">
          {allRows.length === 0
            ? 'No repositories are indexed yet.'
            : `No repository concluded ${filter ? describeConclusion(filter).label.toLowerCase() : ''}. Clear the filter to see the rest.`}
        </p>
      )}

      {rows.length > 0 && (
        <div className="overflow-x-auto border border-gray-700 rounded-lg">
          <table className="w-full text-left border-collapse" data-testid="today-table">
            <thead>
              <tr className="bg-gray-800/70 text-[11px] uppercase tracking-wide text-gray-400">
                <th scope="col" className="px-3 py-2 font-semibold w-12">#</th>
                <th scope="col" className="px-3 py-2 font-semibold">Repository</th>
                <th scope="col" className="px-3 py-2 font-semibold">Why now</th>
                <th scope="col" className="px-3 py-2 font-semibold">Next action</th>
                <th scope="col" className="px-3 py-2 font-semibold">Effort</th>
              </tr>
            </thead>
            <tbody>
              {rows.map(row => {
                const presentation = describeConclusion(
                  row.conclusion === 'unknown' ? 'insufficiently-understood' : row.conclusion
                );
                return (
                  <tr key={row.repoId} className="border-t border-gray-700/70 align-top hover:bg-gray-800/40">
                    <td className="px-3 py-3 text-xs text-gray-500 tabular-nums">{row.rank}</td>
                    <td className="px-3 py-3">
                      {/* A greyed control with nothing behind it is worse than
                          no control: when there is nowhere to go, this is just
                          the repository's name. */}
                      {onOpenRepo ? (
                        <button
                          type="button"
                          onClick={() => onOpenRepo(row.repoId, row.repoName)}
                          title={`Open ${row.repoName} to see the outcome behind this row.`}
                          className="text-sm text-white font-medium hover:text-indigo-300 text-left"
                        >
                          {row.repoName}
                        </button>
                      ) : (
                        <span className="text-sm text-white font-medium">{row.repoName}</span>
                      )}
                      <div className="mt-1">
                        <span className={`text-[11px] px-2 py-0.5 rounded border ${TONE_PILL[presentation.tone]}`}>
                          {row.conclusion === 'unknown' ? 'Not concluded' : presentation.label}
                        </span>
                      </div>
                    </td>
                    <td className="px-3 py-3 text-xs text-gray-300 leading-relaxed max-w-md" title={row.rankBasis.join(' · ')}>
                      {row.whyNow}
                      {row.pinReason && (
                        // Shown only on rows that outrank higher-value work.
                        // Without it the ordering reads as broken: a value-72
                        // row above a value-90 row looks like a bad sort rather
                        // than a deliberate one. The sort is right; it was the
                        // reason that was missing.
                        <span
                          data-testid="today-pin-reason"
                          className="mt-1.5 flex items-start gap-1.5 rounded border border-amber-700/40 bg-amber-900/20 px-2 py-1 text-sm text-amber-200"
                        >
                          <span aria-hidden="true">▲</span>
                          <span>{row.pinReason}</span>
                        </span>
                      )}
                    </td>
                    <td className="px-3 py-3">
                      {row.nextActionLabel ? (
                        <button
                          type="button"
                          onClick={() => onRunAction?.(row)}
                          disabled={!onRunAction}
                          title={
                            onRunAction
                              ? `${row.nextActionRoute ?? 'This action'} — previews first; nothing is applied.`
                              : 'This view is read-only here, so the action cannot be started from this row.'
                          }
                          className="text-xs px-2.5 py-1.5 bg-indigo-600 hover:bg-indigo-500 disabled:bg-gray-700 disabled:text-gray-400 text-white rounded transition-colors text-left"
                        >
                          {row.nextActionLabel}
                        </button>
                      ) : (
                        <span className="text-xs text-gray-500">None warranted</span>
                      )}
                    </td>
                    <td className="px-3 py-3">
                      <span className={`text-xs ${EFFORT_TEXT[row.effort?.band ?? 'unknown']}`}>
                        {row.effort?.label ?? 'Effort not estimated'}
                      </span>
                      {row.valueScore !== null && (
                        <div className="text-[11px] text-gray-500 mt-0.5">value {row.valueScore}</div>
                      )}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
};

export default TodayView;
