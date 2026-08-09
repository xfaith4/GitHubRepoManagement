import React from 'react';
import SummaryCard from './SummaryCard';

export interface PortfolioSummaryCounts {
  total: number;
  needsAttention: number;
  dirty: number;
  stale: number;
  commitsThisWeek: number;
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
        <SummaryCard title="Dirty Repositories" value={summary.dirty} color="red" />
        <SummaryCard title="Stale Repositories" value={summary.stale} color="red" />
        <SummaryCard title="Commits This Week" value={summary.commitsThisWeek} color="green" />
      </div>
    </section>
  </div>
);

export default PortfolioSummarySection;
