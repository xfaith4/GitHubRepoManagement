import React, { useMemo, useState } from 'react';
import type { OperationsRepoEntry } from '../types';
import {
  type FoundationConclusionKind,
  FOUNDATION_CONCLUSIONS,
  describeConclusion,
  type ConclusionBasis,
} from '../lib/foundationConclusion';
import { buildOrientation, buildTodayRows, type TodayRankingInput, type TodayRow } from '../lib/todayRanking';
import { describeAssessedAt } from '../lib/unattendedReadiness';
import { buildHoldGroups, describeHoldCount, type RepoHold } from '../lib/repoHolds';

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
  attention: 'bg-status-warn/20 border-status-warn/50 text-status-warn-text',
  healthy: 'bg-status-ok/15 border-status-ok/45 text-status-ok-text',
  unknown: 'bg-text/6 border-text/18 text-text/70',
};

// Effort carries NO status colour any more. It used to run emerald → amber →
// orange, which said a large task was a warning and a very large one was
// nearly an error. A big job is not a problem, it is a big job — and spending
// three status hues on it left less contrast for the states that ARE problems.
// Size is carried by the label, which already says "3 work units".
const EFFORT_TEXT: Record<'small' | 'medium' | 'large' | 'unknown', string> = {
  small: 'text-text/70',
  medium: 'text-text/70',
  large: 'text-text/70',
  unknown: 'text-text/45',
};

export interface TodayViewProps {
  entries: OperationsRepoEntry[];
  /** Opens the repository — the outcome card is the detail behind a row. */
  onOpenRepo?: (repoId: string, repoName: string) => void;
  /** Runs a row's preview-first action. Omitted renders the label without a button. */
  onRunAction?: (row: TodayRow) => void;
  isLoading?: boolean;
  /**
   * The freshness payload the ranking was drawn from.
   *
   * Rendered ONLY as the quiet "assessed N hours ago" stamp beside each
   * readiness figure (operator decision, 2026-09-01: a stale readiness score
   * is the one number an operator would act on and be wrong about, so the
   * timestamp has to be visible). It is a fact, never a colour and never a
   * banner — the staleness banner was removed by operator decision
   * (2026-08-30) because a landing page that opens with a warning reads as a
   * broken product. Do not reintroduce one here.
   *
   * A new object also marks the ranking as re-drawn, which re-arms the scan
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
    // Readiness signals for the fourth sort key. Forwarded raw so the ranking
    // assesses them itself and the table cannot disagree with the sort.
    hasReadme: entry.hasReadme,
    hasRoadmap: entry.hasRoadmap,
    roadmapState: entry.roadmapState,
    localDirtyCount: entry.localDirtyCount,
    hasCiSignal: entry.hasCiSignal,
  };
}

/**
 * One hold. The rail is the only colour it carries, and the reason sits beside
 * the name rather than behind a hover — a badge without its reason is a
 * regression.
 */
const HoldCard: React.FC<{ hold: RepoHold; onOpenRepo?: (id: string, name: string) => void }> = ({ hold, onOpenRepo }) => {
  const rail =
    hold.severity === 'blocking' ? 'bg-status-crit' : hold.severity === 'actionable' ? 'bg-status-warn' : 'bg-text/25';
  return (
    <div
      data-testid={`today-hold-${hold.rule}`}
      data-severity={hold.severity}
      className="grid grid-cols-[3px_minmax(0,1fr)] overflow-hidden rounded-lg bg-surface ring-1 ring-hairline"
    >
      <div className={rail} aria-hidden="true" />
      <div className="min-w-0 px-3 py-2.5">
        <div className="flex flex-wrap items-center gap-2">
          {onOpenRepo ? (
            <button
              type="button"
              onClick={() => onOpenRepo(hold.repoId, hold.repoName)}
              className="font-mono text-[13px] font-medium text-text hover:text-accent-300"
            >
              {hold.repoName}
            </button>
          ) : (
            <span className="font-mono text-[13px] font-medium text-text">{hold.repoName}</span>
          )}
          <span className="rounded-md bg-text/8 px-2 py-0.5 font-mono text-[11px] text-text/62">{hold.rule}</span>
          {hold.alwaysHeld && (
            <span className="rounded-md bg-accent-800 px-2 py-0.5 text-[11px] text-accent-100">always held</span>
          )}
        </div>
        <p className="mt-1 text-[12.5px] text-text/78">{hold.reason}</p>
      </div>
    </div>
  );
};

export const TodayView: React.FC<TodayViewProps> = ({ entries, onOpenRepo, onRunAction, isLoading = false, basis, onRunScan }) => {
  const [filter, setFilter] = useState<FoundationConclusionKind | null>(null);
  // Actionable holds start collapsed; blocking ones are never collapsible, so
  // this state does not reach them.
  const [holdsOpen, setHoldsOpen] = useState(false);
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
  const holds = useMemo(() => buildHoldGroups(entries), [entries]);
  const assessedAt = useMemo(() => describeAssessedAt(basis), [basis]);

  return (
    <div className="p-4 space-y-4">
      {/* No staleness banner here, deliberately. Lane 0.13 shipped one and the
          operator removed it (2026-08-30): the landing page opening with an
          amber warning reads as a broken product, which costs more confidence
          than the verdict earns. The verdict still rides every payload as
          `basis`; the remedy survives as the quiet scan control in the filter
          row below. Do not reintroduce a warning banner on this view. */}

      {/* Orientation — what this product evaluated and what it concluded. */}
      <p data-testid="today-orientation" className="text-[12.5px] text-text/78 leading-relaxed max-w-[66ch]">
        {orientation}
      </p>

      {/* Needs you.
          Blocking holds are rendered unconditionally: a lane is already
          running and stuck, and that is the one thing a landing screen must
          never put behind a click. Everything else actionable collapses to a
          single quiet line, so the first paint is never a wall of red — the
          staleness banner was removed for exactly that reason (2026-08-30) and
          this section must not reintroduce the same failure in another form. */}
      {(holds.blocking.length > 0 || holds.actionable.length > 0) && (
        <section data-testid="today-needs-you" className="flex flex-col gap-2">
          {holds.blocking.length > 0 && (
            <>
              <div className="flex items-baseline gap-2.5">
                <h2 className="text-[15px] font-medium text-text">Blocking a lane</h2>
                <span className="text-[11px] text-text/50">
                  work is already under way and stopped — never collapsed
                </span>
              </div>
              {holds.blocking.map(hold => (
                <HoldCard key={`${hold.repoId}-${hold.rule}`} hold={hold} onOpenRepo={onOpenRepo} />
              ))}
            </>
          )}

          {holds.actionable.length > 0 && (
            <>
              <button
                type="button"
                onClick={() => setHoldsOpen(open => !open)}
                aria-expanded={holdsOpen}
                data-testid="today-holds-toggle"
                className="flex w-full items-center gap-2.5 rounded-lg bg-surface px-3 py-2 text-left ring-1 ring-hairline hover:bg-text/6"
              >
                <span aria-hidden="true" className="font-mono text-[11px] text-text/45">
                  {holdsOpen ? '▾' : '▸'}
                </span>
                <span className="text-[13px] font-medium text-text">
                  {describeHoldCount(holds.actionable.length)}
                </span>
                <span className="text-[11.5px] text-text/55">
                  {holdsOpen ? 'every hold states its rule' : 'open to see each hold and its rule'}
                </span>
              </button>
              {holdsOpen &&
                holds.actionable.map(hold => (
                  <HoldCard key={`${hold.repoId}-${hold.rule}`} hold={hold} onOpenRepo={onOpenRepo} />
                ))}
            </>
          )}
        </section>
      )}

      {/* Every conclusion filters the same way. */}
      <div className="flex gap-2 flex-wrap items-center">
        <button
          type="button"
          onClick={() => setFilter(null)}
          aria-pressed={filter === null}
          className={`text-xs px-3 py-1.5 rounded-full border transition-colors ${filter === null ? 'bg-transparent border-accent text-accent' : 'bg-transparent border-text/18 text-text/70 hover:border-text/35 hover:text-text'}`}
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
              className={`text-xs px-3 py-1.5 rounded-full border transition-colors ${filter === kind ? 'bg-transparent border-accent text-accent' : `${TONE_PILL[presentation.tone]} hover:brightness-125`}`}
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
                className="text-[11.5px] px-2.5 py-1 rounded-md border border-accent/55 bg-transparent text-accent hover:bg-accent/10 disabled:opacity-50 transition-colors"
              >
                {scanRequest === 'starting' ? 'Starting scan…' : 'Run portfolio scan'}
              </button>
            )}
            {scanRequest === 'started' && (
              <span data-testid="today-scan-note" className="text-[11.5px] text-text/55">
                Scan started — this ranking refreshes when it completes.
              </span>
            )}
            {scanRequest === 'already-running' && (
              <span data-testid="today-scan-note" className="text-[11.5px] text-text/55">
                A scan is already running — this ranking refreshes when it completes.
              </span>
            )}
            {scanRequest === 'failed' && scanRequestError && (
              <span data-testid="today-scan-note" className="text-[11.5px] text-status-crit-text">
                {scanRequestError}
              </span>
            )}
          </div>
        )}
      </div>

      {isLoading && <p className="text-xs text-text/45">Loading the portfolio…</p>}

      {!isLoading && rows.length === 0 && (
        <p data-testid="today-empty" className="text-[12.5px] text-text/62">
          {allRows.length === 0
            ? 'No repositories are indexed yet.'
            : `No repository concluded ${filter ? describeConclusion(filter).label.toLowerCase() : ''}. Clear the filter to see the rest.`}
        </p>
      )}

      {rows.length > 0 && (
        <div className="overflow-x-auto rounded-lg ring-1 ring-hairline">
          <table className="w-full text-left border-collapse" data-testid="today-table">
            <thead>
              <tr className="bg-text/6 text-[10px] uppercase tracking-[.1em] text-text/55">
                <th scope="col" className="px-3 py-2 font-semibold w-12">#</th>
                <th scope="col" className="px-3 py-2 font-semibold">Repository</th>
                <th scope="col" className="px-3 py-2 font-semibold">Why now</th>
                <th scope="col" className="px-3 py-2 font-semibold">Next action</th>
                <th scope="col" className="px-3 py-2 font-semibold">Effort</th>
                <th scope="col" className="px-3 py-2 font-semibold">Ready for unattended work</th>
              </tr>
            </thead>
            <tbody>
              {rows.map(row => {
                const presentation = describeConclusion(
                  row.conclusion === 'unknown' ? 'insufficiently-understood' : row.conclusion
                );
                return (
                  <tr key={row.repoId} className="border-t border-text/8 align-top hover:bg-text/5">
                    <td className="px-3 py-3 font-mono text-xs text-text/45 tabular-nums">{row.rank}</td>
                    <td className="px-3 py-3">
                      {/* A greyed control with nothing behind it is worse than
                          no control: when there is nowhere to go, this is just
                          the repository's name. */}
                      {onOpenRepo ? (
                        <button
                          type="button"
                          onClick={() => onOpenRepo(row.repoId, row.repoName)}
                          title={`Open ${row.repoName} to see the outcome behind this row.`}
                          className="font-mono text-[13px] text-text font-medium hover:text-accent-300 text-left"
                        >
                          {row.repoName}
                        </button>
                      ) : (
                        <span className="font-mono text-[13px] text-text font-medium">{row.repoName}</span>
                      )}
                      <div className="mt-1">
                        <span className={`text-[11px] px-2 py-0.5 rounded border ${TONE_PILL[presentation.tone]}`}>
                          {row.conclusion === 'unknown' ? 'Not concluded' : presentation.label}
                        </span>
                      </div>
                    </td>
                    <td className="px-3 py-3 text-[12.5px] text-text/78 leading-relaxed max-w-md">
                      {row.whyNow}
                      <div data-testid="today-rank-basis" className="mt-1 text-xs text-text/60">
                        Rank basis: {row.rankBasis.join(' · ')}
                      </div>
                      {row.pinReason && (
                        // Shown only on rows that outrank higher-value work.
                        // Without it the ordering reads as broken: a value-72
                        // row above a value-90 row looks like a bad sort rather
                        // than a deliberate one. The sort is right; it was the
                        // reason that was missing.
                        <span
                          data-testid="today-pin-reason"
                          className="mt-1.5 flex items-start gap-1.5 rounded-md border border-status-warn/45 bg-status-warn/15 px-2 py-1 text-[12px] text-status-warn-text"
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
                          className="text-xs px-2.5 py-1 rounded-md border border-accent bg-transparent text-accent hover:bg-accent/10 disabled:border-text/18 disabled:text-text/40 transition-colors text-left"
                        >
                          {row.nextActionLabel}
                        </button>
                      ) : (
                        <span className="text-xs text-text/45">None warranted</span>
                      )}
                    </td>
                    <td className="px-3 py-3">
                      <span className={`text-xs ${EFFORT_TEXT[row.effort?.band ?? 'unknown']}`}>
                        {row.effort?.label ?? 'Effort not estimated'}
                      </span>
                    </td>
                    {/* Readiness for UNATTENDED WORK — four named checks, not a
                        score. The `value` figure that used to sit here came
                        from the item value model (impact, unblock potential,
                        risk reduction), which ranks repositories by worth. Every
                        repository here is useful, so nothing may rank by
                        usefulness; what can be measured is whether an agent can
                        work without asking. The assessed stamp rides beside it
                        because a stale readiness figure is the one number an
                        operator would act on and be wrong about. */}
                    <td className="px-3 py-3">
                      <span
                        data-testid="today-readiness"
                        className="font-mono text-xs text-text/78"
                        title={row.readiness.factors.map(f => `${f.label}: ${f.detail}`).join('\n')}
                      >
                        {row.readiness.summary}
                      </span>
                      <div className="mt-0.5 text-[11px] text-text/45">{assessedAt}</div>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}

      {/* Gaps.
          True of much of the portfolio and blocking nothing right now — no
          README, no ROADMAP, docs below the standard. `needsAttention.ts`
          excludes these from the attention signal on purpose, so that the
          signal stays "a meaningful subset rather than ~100% of the
          portfolio". They are still worth seeing: each one is a question an
          agent would otherwise have to ask. They are not worth alarming
          about, so this list carries no status colour at all. */}
      {holds.ambient.length > 0 && (
        <section data-testid="today-gaps" className="rounded-lg p-3 ring-1 ring-text/12">
          <div className="flex items-baseline gap-2.5">
            <h2 className="text-[13px] font-medium text-text/78">Gaps</h2>
            <span className="text-[11px] text-text/50">
              {holds.ambient.length} {holds.ambient.length === 1 ? 'gap' : 'gaps'} that would make an agent ask —
              blocking nothing right now
            </span>
          </div>
          <ul className="mt-2 flex flex-col gap-1.5">
            {holds.ambient.map(hold => (
              <li
                key={`${hold.repoId}-${hold.rule}`}
                data-testid={`today-gap-${hold.rule}`}
                className="flex flex-wrap items-baseline gap-x-2 gap-y-0.5 text-[12px]"
              >
                <span className="font-mono text-text/70">{hold.repoName}</span>
                <span className="font-mono text-[11px] text-text/45">{hold.rule}</span>
                <span className="text-text/62">{hold.reason}</span>
              </li>
            ))}
          </ul>
        </section>
      )}
    </div>
  );
};

export default TodayView;
