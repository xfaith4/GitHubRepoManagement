import React from 'react';
import SummaryCard from './SummaryCard';

export interface PortfolioSummaryCounts {
  total: number;
  needsAttention: number;
  /**
   * `null` when the source cannot observe a working tree. The GitHub API path
   * hardcodes `status: 'clean'` and `uncommittedChanges: 0` because a remote
   * repository has no checkout, so counting them produced a confident `0` that
   * read as "nothing is dirty" instead of "not observable here".
   */
  dirty: number | null;
  stale: number;
  commitsThisWeek: number;
}

/** Release 3.5 milestone 3 -- the scope these counts were computed over. */
export interface PortfolioScopeCounts {
  inScope: number;
  vendored: number;
  archived: number;
  excludedPath: number;
}

interface PortfolioSummarySectionProps {
  /** What the numbers below describe — the live scan or an indexed source. */
  sourceLabel: string;
  /** Repo count + scan duration for this scan, when the source reports them. */
  scanMetaLabel?: string | null;
  dataLastUpdated?: Date | null;
  /** GitHub API budget; only shown for a GitHub-backed source. */
  rateLimit?: { remaining: number; limit: number } | null;
  summary: PortfolioSummaryCounts;
  /** When present, the tile row states its scope beneath the counts. */
  scope?: PortfolioScopeCounts | null;
}

/**
 * The page header and the five headline counts (Release 2.7 Phase D — extracted
 * from Dashboard.tsx). Presentation only: every number is computed by the
 * caller, so this renders whatever it is handed and owns no data fetching.
 */
const PortfolioSummarySection: React.FC<PortfolioSummarySectionProps> = ({
  sourceLabel,
  scanMetaLabel,
  dataLastUpdated,
  rateLimit,
  summary,
  scope,
}) => (
  <div className="container mx-auto px-4 sm:px-6 lg:px-8 pt-6">
    <section className="rounded-lg border border-gray-700 bg-gray-800/60 px-4 py-4">
      <div className="flex items-start justify-between gap-4 flex-wrap">
        <div>
          <h1 className="text-xl font-semibold text-white">Repository Management</h1>
          <p className="text-sm text-gray-300 mt-1">{sourceLabel}</p>
          <div className="text-xs text-gray-400 mt-2 flex flex-wrap items-center gap-3">
            {scanMetaLabel && <span>{scanMetaLabel}</span>}
            {dataLastUpdated && (
              <span>
                Last scan: <strong>{dataLastUpdated.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}</strong>
              </span>
            )}
            {rateLimit && (
              <span>
                Rate limit {rateLimit.remaining}/{rateLimit.limit}
              </span>
            )}
          </div>
        </div>
        <div className="text-xs text-gray-500">
          Use the view tabs below for Repository Grid and Insights.
        </div>
      </div>

      <div className="grid grid-cols-2 md:grid-cols-5 gap-3 mt-4">
        <SummaryCard title="Total Repositories" value={summary.total} color="blue" />
        <SummaryCard title="Needs Attention" value={summary.needsAttention} color="yellow" tooltip="Repos with an actionable problem: uncommitted changes, a failing build, a blocked or parse-error dispatch state, or an unparseable roadmap. Excludes baseline gaps like 'no CI yet' or a roadmap that merely has pending items." />
        <SummaryCard
          title="Dirty Repositories"
          value={summary.dirty}
          color="red"
          unavailableReason="Needs a local checkout — the GitHub API cannot see a working tree."
        />
        <SummaryCard title="Stale Repositories" value={summary.stale} color="red" />
        <SummaryCard title="Commits This Week" value={summary.commitsThisWeek} color="green" />
      </div>
      {/* Release 3.5 milestone 7 -- scan completion is announced to screen
          readers, not just painted. The region re-renders when a scan lands
          (dataLastUpdated changes), and aria-live announces the change. */}
      {dataLastUpdated && (
        <span className="sr-only" role="status" aria-live="polite" data-testid="scan-completion-announcement">
          Scan complete: {summary.total} repositories as of {dataLastUpdated.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}.
        </span>
      )}
      {/* Release 3.5 milestone 3 -- every count above states its scope. A
          number computed over a set the operator cannot name is the defect
          this release exists to remove. */}
      {scope && (scope.vendored + scope.archived + scope.excludedPath) > 0 && (
        <p className="mt-2 text-xs text-gray-400" data-testid="scope-statement">
          Counts cover <strong>{scope.inScope} in-scope</strong> repositories · {scope.vendored + scope.archived + scope.excludedPath} excluded from portfolio math
          ({[scope.vendored > 0 ? `${scope.vendored} vendored` : null, scope.archived > 0 ? `${scope.archived} archived` : null, scope.excludedPath > 0 ? `${scope.excludedPath} temp/worktree` : null].filter(Boolean).join(' · ')})
          — visible in the grid via the "Hide out-of-scope" toggle.
        </p>
      )}
    </section>
  </div>
);

export default PortfolioSummarySection;
