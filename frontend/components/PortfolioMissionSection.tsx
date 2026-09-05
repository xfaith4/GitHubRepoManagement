import React from 'react';
import { type PortfolioSignalSource } from '../types';
import { SpinnerIcon } from './icons';

const SIGNAL_SOURCE_STYLES: Record<PortfolioSignalSource, string> = {
  cache: 'bg-slate-800 text-slate-200 border-slate-600',
  'fresh-scan': 'bg-emerald-900/40 text-emerald-200 border-emerald-700/50',
  ledger: 'bg-blue-900/40 text-blue-200 border-blue-700/50',
  api: 'bg-indigo-900/40 text-indigo-200 border-indigo-700/50',
  unavailable: 'bg-gray-800 text-gray-300 border-gray-600',
  'not-evaluated': 'bg-gray-800 text-gray-300 border-gray-600',
  'no-token': 'bg-amber-900/40 text-amber-200 border-amber-700/50',
  'no-owner-configured': 'bg-amber-900/40 text-amber-200 border-amber-700/50',
  error: 'bg-red-900/40 text-red-200 border-red-700/50',
};

function formatSignalLabel(key: string): string {
  switch (key) {
    case 'docAudit':
      return 'Docs';
    case 'roadmapAudit':
      return 'Roadmap';
    default:
      return key.charAt(0).toUpperCase() + key.slice(1);
  }
}

// Each tile's hover definition. Only the counts whose meaning is not obvious
// from the label carry one.
const METRIC_TOOLTIPS: Record<string, string> = {
  'Dirty Worktrees': 'Repos with uncommitted or untracked changes in the working tree.',
  'Missing README': 'Repos with no README file.',
  'Missing ROADMAP': 'Repos with no ROADMAP file.',
  'Weak ROADMAP': 'Repos whose ROADMAP is below the L3 contract-ready maturity bar.',
  'Failing Actions': 'Repos whose latest GitHub Actions run concluded in failure.',
  'Dispatch blocked': 'Repos blocked from dispatch (missing docs/roadmap or a parse error).',
  'Open PRs': 'Repos with at least one open pull request.',
  'Pages Enabled': 'Repos with GitHub Pages enabled.',
};

/**
 * The mission rollup the Dashboard derives from a portfolio assessment. Named
 * here rather than left inferred, so this section's contract is explicit and a
 * dropped field fails at the call site instead of rendering as `undefined`.
 */
export interface PortfolioMission {
  generatedAt: string;
  cacheSource: 'memory' | 'fresh-scan';
  cacheAgeSeconds: number;
  signalSources: Partial<Record<string, PortfolioSignalSource>>;
  totalRepos: number;
  localOnly: number;
  githubOnly: number;
  linked: number;
  missingRoadmap: number;
  missingReadme: number;
  weakRoadmap: number;
  ready: number;
  running: number;
  blocked: number;
  completed: number;
  dirtyWorktrees: number;
  openPrs: number;
  pagesEnabled: number;
  failingActions: number;
}

import type { PortfolioMetric } from '../types';

interface PortfolioMissionSectionProps {
  mission: PortfolioMission | null;
  /**
   * Release 3.5 milestone 1 — the snapshot's scanned-repo count, so the
   * "Assessed" tile can state its coverage against the real denominator
   * instead of presenting the assessment subset as the portfolio (the
   * review's "Total 27" on a 76-repo workspace).
   */
  scanTotalMetric?: PortfolioMetric | null;
  loading: boolean;
  error?: string | null;
  onRetry: () => void;
}

/**
 * Index-backed collection state for the current portfolio scan (extracted from
 * Dashboard.tsx in Release 2.7 Phase D).
 *
 * Renders one of three states, and never a silently empty panel: the metrics
 * when the assessment resolved, a spinner while it is in flight, and an
 * explicit unavailable notice otherwise — the caller decides whether to mount
 * this at all.
 */
const PortfolioMissionSection: React.FC<PortfolioMissionSectionProps> = ({
  mission,
  scanTotalMetric = null,
  loading,
  error,
  onRetry,
}) => (
  <section className="bg-gray-800/60 border border-gray-700 rounded-lg px-4 py-4">
    <div className="flex items-start justify-between gap-4 flex-wrap">
      <div>
        <h2 className="text-lg font-semibold text-white">Portfolio Mission</h2>
        <p className="text-sm text-gray-400 mt-1">Index-backed collection state for the current portfolio scan.</p>
      </div>
      {mission && (
        <div className="text-xs text-gray-500 text-right">
          <div>Generated {new Date(mission.generatedAt).toLocaleTimeString()}</div>
          <div>{mission.cacheSource === 'memory' ? 'Memory cache' : 'Fresh scan'}{mission.cacheAgeSeconds > 0 ? ` · ${Math.round(mission.cacheAgeSeconds)}s old` : ''}</div>
        </div>
      )}
      <button
        onClick={onRetry}
        className="px-2.5 py-1 rounded border border-gray-600 bg-gray-700/60 text-xs text-gray-200 hover:bg-gray-600/70"
      >
        Retry
      </button>
    </div>

    {mission ? (
      <>
        <div className="flex flex-wrap gap-2 mt-3">
          {Object.entries(mission.signalSources).map(([key, value]) => {
            if (!value) {
              return null;
            }

            const source = value as PortfolioSignalSource;
            return (
              <span key={key} className={`inline-flex items-center gap-1.5 rounded-full border px-2.5 py-1 text-xs font-medium ${SIGNAL_SOURCE_STYLES[source] ?? SIGNAL_SOURCE_STYLES.unavailable}`}>
                <span className="text-gray-300">{formatSignalLabel(key)}</span>
                <span>{source}</span>
              </span>
            );
          })}
        </div>

        <div className="grid grid-cols-2 md:grid-cols-4 xl:grid-cols-6 gap-3 mt-4">
          {[
            // Release 3.5 — this is the ASSESSED set, and it says so. The
            // scanned total comes from the snapshot when available.
            { label: scanTotalMetric?.value != null ? `Assessed (of ${scanTotalMetric.value} scanned)` : 'Assessed', value: mission.totalRepos, accent: 'text-white' },
            { label: 'Local Only', value: mission.localOnly, accent: 'text-slate-200' },
            { label: 'Linked', value: mission.linked, accent: 'text-emerald-300' },
            { label: 'GitHub Only', value: mission.githubOnly, accent: 'text-indigo-300' },
            { label: 'Missing ROADMAP', value: mission.missingRoadmap, accent: 'text-amber-300' },
            { label: 'Missing README', value: mission.missingReadme, accent: 'text-amber-300' },
            { label: 'Weak ROADMAP', value: mission.weakRoadmap, accent: 'text-orange-300' },
            { label: 'Work-ready (L3+)', value: mission.ready, accent: 'text-emerald-300' },
            { label: 'Running', value: mission.running, accent: 'text-blue-300' },
            { label: 'Dispatch blocked', value: mission.blocked, accent: 'text-red-300' },
            { label: 'Completed', value: mission.completed, accent: 'text-violet-300' },
            { label: 'Dirty Worktrees', value: mission.dirtyWorktrees, accent: 'text-yellow-300' },
            { label: 'Open PRs', value: mission.openPrs, accent: 'text-cyan-300' },
            { label: 'Pages Enabled', value: mission.pagesEnabled, accent: 'text-teal-300' },
            { label: 'Failing Actions', value: mission.failingActions, accent: 'text-rose-300' },
          ].map(metric => (
            <div
              key={metric.label}
              title={METRIC_TOOLTIPS[metric.label]}
              className="rounded-lg border border-gray-700 bg-gray-900/50 px-3 py-3"
            >
              <div className={`text-lg font-semibold ${metric.accent}`}>{metric.value}</div>
              <div className="mt-1 text-xs text-gray-400">{metric.label}</div>
              {metric.label === 'Dispatch blocked' && <div className="text-xs text-gray-400">of {mission.totalRepos} assessed repositories</div>}
            </div>
          ))}
        </div>
      </>
    ) : loading ? (
      <div className="flex items-center gap-3 py-8 text-gray-400 justify-center">
        <SpinnerIcon className="w-5 h-5 animate-spin" />
        <span>Loading portfolio assessment…</span>
      </div>
    ) : (
      <div className="mt-4 rounded-lg border border-amber-700/40 bg-amber-900/20 px-4 py-3 text-sm text-amber-100">
        Portfolio Mission is unavailable. {error ?? 'Assessment data was not returned.'}
      </div>
    )}
  </section>
);

export default PortfolioMissionSection;
