import React from 'react';
import {
  type ExecutionMetrics,
  type PortfolioAssessmentEntry,
  type PortfolioAssessmentResult,
  type PortfolioTrendResult,
  type RepoStatus,
} from '../types';
import SummaryCard from './SummaryCard';
import ProvenanceNotice from './ProvenanceNotice';
import PortfolioMissionSection, { type PortfolioMission } from './PortfolioMissionSection';
import ChangeHistoryPanel from './ChangeHistoryPanel';
import { SpinnerIcon, IssuesIcon, ProjectsIcon, BranchIcon, HealthIcon } from './icons';
import {
  buildTrendGeometry,
  buildTrendSummaryCards,
  EMPTY_EXECUTION_METRICS,
  formatLifecycleLabel,
  formatTrendDateLabel,
  formatTrendSeedSourceLabel,
  formatTrendSeriesDelta,
  formatTrendSeriesValue,
  formatTrendStatusLabel,
  hasExecutionActivity,
  lifecycleStyle,
  trendSeriesPalette,
} from '../lib/portfolioTrendView';

/** The four extended KPI tiles, shown only when the scan carried extended data. */
export interface InsightsExtendedSummary {
  totalIssues: number;
  totalProjects: number;
  totalStaleBranches: number;
  avgHealthScore: number;
}

/**
 * The mission rollup, plus the documentation-health and ranking fields only this
 * view renders.
 *
 * Declared rather than inferred, for the same reason `PortfolioMission` is: a
 * dropped field then fails at the call site instead of rendering as `undefined`
 * inside a progress bar, where `width: undefined%` is silently a zero-width bar
 * rather than a visible error.
 */
export interface InsightsPortfolioMission extends PortfolioMission {
  averageReadmeScore: number;
  averageRoadmapScore: number;
  averageDocumentationHealthScore: number;
  ciCoverage: number;
  testCoverage: number;
  docsNeedingAttention: number;
  topEntries: PortfolioAssessmentEntry[];
}

interface InsightsViewProps {
  repos: RepoStatus[];
  /** True when the current scan came from a local workspace rather than GitHub. */
  isLocalSource: boolean;
  extendedSummary: InsightsExtendedSummary;

  executionMetrics: ExecutionMetrics | null;
  executionMetricsLoading: boolean;
  executionMetricsRefreshing: boolean;
  executionMetricsError: string | null;
  executionMetricsUpdatedAt: string | null;
  onRefreshExecutionMetrics: () => void;

  portfolioMission: InsightsPortfolioMission | null;
  portfolioAssessment: PortfolioAssessmentResult | null;
  portfolioAssessmentLoading: boolean;
  portfolioAssessmentError: string | null;
  onRetryAssessment: () => void;

  portfolioTrend: PortfolioTrendResult | null;
  portfolioTrendLoading: boolean;
  portfolioTrendError: string | null;
  onRetryTrend: () => void;
}

/**
 * The Insights tab body: throughput, mission, documentation health, portfolio
 * analytics, index-backed assessment, and change history.
 *
 * Extracted from Dashboard.tsx to fix a navigation defect, not merely to shorten
 * a file. Every one of these widgets used to render in a container that sat
 * ABOVE `<DashboardViewTabs>`, while the Insights tab panel held a single
 * sentence pointing back upward. Clicking "Insights" therefore inserted ~560
 * lines above the control the operator had just clicked, pushing the tab bar
 * off-screen — the tab metaphor inverted for one of six tabs. Living in its own
 * component makes it structurally impossible to reintroduce: the content can
 * only render where the panel renders it.
 */
const InsightsView: React.FC<InsightsViewProps> = ({
  repos,
  isLocalSource,
  extendedSummary,
  executionMetrics,
  executionMetricsLoading,
  executionMetricsRefreshing,
  executionMetricsError,
  executionMetricsUpdatedAt,
  onRefreshExecutionMetrics,
  portfolioMission,
  portfolioAssessment,
  portfolioAssessmentLoading,
  portfolioAssessmentError,
  onRetryAssessment,
  portfolioTrend,
  portfolioTrendLoading,
  portfolioTrendError,
  onRetryTrend,
}) => {
  const metrics = executionMetrics ?? EMPTY_EXECUTION_METRICS;
  const executionActive = hasExecutionActivity(metrics);
  const trendSummaryCards = buildTrendSummaryCards(portfolioTrend);

  return (
    <div data-testid="insights-view" className="px-4 py-4">
      <div className="rounded-lg border border-gray-700 bg-gray-900/40 px-4 py-3 text-sm text-gray-300">
        Insights is read-only analytics — portfolio trends, throughput, and documentation health. The Repository Grid tab stays the primary operational workflow.
      </div>

      {/* Portfolio Mission, Documentation Health, and Portfolio Analytics all
          read the persisted assessment/trend indexes rather than the live scan.
          One notice covers the whole tab — three separate banners on one screen
          would be noise, and the provenance is identical for all of them. */}
      <ProvenanceNotice
        testId="insights-provenance-notice"
        className="mt-4"
        liveRepoCount={repos.length}
        persistedEntryCount={portfolioAssessment?.entries?.length ?? 0}
        persistedGeneratedAt={portfolioAssessment?.generatedAt ?? portfolioTrend?.generatedAt}
      />

      <section className="mt-4 rounded-lg border border-gray-700 bg-gray-800/60 px-4 py-4">
        <div className="flex items-start justify-between gap-3 flex-wrap">
          <div>
            <h2 className="text-lg font-semibold text-white">Execution Throughput</h2>
            <p className="text-sm text-gray-400 mt-1">
              Live rollup from the execution ledger: completions, queue pressure, and in-flight duration.
            </p>
          </div>
          <div className="flex items-center gap-2 text-xs text-gray-500">
            {executionMetricsRefreshing && !executionMetricsLoading && <span>Refreshing…</span>}
            {executionMetricsUpdatedAt && (
              <span>
                Updated {new Date(executionMetricsUpdatedAt).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
              </span>
            )}
            <button
              onClick={onRefreshExecutionMetrics}
              disabled={executionMetricsLoading || executionMetricsRefreshing}
              title={executionMetricsLoading || executionMetricsRefreshing ? 'Execution metrics are already being fetched.' : 'Re-fetches execution metrics.'}
              className="px-2.5 py-1 rounded border border-gray-600 bg-gray-700/60 text-gray-200 hover:bg-gray-600/70 disabled:opacity-50 transition-colors"
            >
              Refresh
            </button>
          </div>
        </div>

        {executionMetricsLoading && executionMetrics === null ? (
          <div className="flex items-center gap-3 py-8 text-sm text-gray-400 justify-center">
            <SpinnerIcon className="w-5 h-5 animate-spin" />
            <span>Loading execution metrics…</span>
          </div>
        ) : executionMetrics === null ? (
          <div className="mt-4 rounded-lg border border-red-700/40 bg-red-900/20 px-4 py-3 text-sm text-red-200">
            {executionMetricsError ?? 'Execution metrics are unavailable.'}
          </div>
        ) : (
          <>
            <div className="mt-4 grid grid-cols-2 md:grid-cols-3 xl:grid-cols-6 gap-3">
              <div className="rounded-lg border border-green-700/30 bg-green-900/10 px-3 py-3">
                <div className="text-xs uppercase tracking-wide text-green-200/80">Done Today</div>
                <div className="mt-1 text-2xl font-semibold text-green-200">{metrics.completedToday}</div>
              </div>
              <div className="rounded-lg border border-blue-700/30 bg-blue-900/10 px-3 py-3">
                <div className="text-xs uppercase tracking-wide text-blue-200/80">Done This Week</div>
                <div className="mt-1 text-2xl font-semibold text-blue-200">{metrics.completedThisWeek}</div>
              </div>
              <div className="rounded-lg border border-indigo-700/30 bg-indigo-900/10 px-3 py-3">
                <div className="text-xs uppercase tracking-wide text-indigo-200/80">Running Now</div>
                <div className="mt-1 text-2xl font-semibold text-indigo-200">{metrics.stateCounts.running}</div>
              </div>
              <div className="rounded-lg border border-yellow-700/30 bg-yellow-900/10 px-3 py-3">
                <div className="text-xs uppercase tracking-wide text-yellow-200/80">Ready Queue</div>
                <div className="mt-1 text-2xl font-semibold text-yellow-200">{metrics.stateCounts.ready}</div>
              </div>
              <div className="rounded-lg border border-red-700/30 bg-red-900/10 px-3 py-3">
                <div className="text-xs uppercase tracking-wide text-red-200/80">Error Rate</div>
                <div className={`mt-1 text-2xl font-semibold ${metrics.errorRatePct > 20 ? 'text-red-200' : 'text-gray-100'}`}>
                  {metrics.errorRatePct.toFixed(0)}%
                </div>
              </div>
              <div className="rounded-lg border border-gray-700 bg-gray-900/50 px-3 py-3">
                <div className="text-xs uppercase tracking-wide text-gray-400">Avg Active Run</div>
                <div className="mt-1 text-2xl font-semibold text-gray-100">
                  {metrics.avgCurrentRunMins > 0 ? `${metrics.avgCurrentRunMins.toFixed(0)}m` : '0m'}
                </div>
              </div>
            </div>

            <div className="mt-4 grid grid-cols-2 lg:grid-cols-4 gap-3">
              <div className="rounded-lg border border-gray-700/60 bg-gray-900/40 px-3 py-2">
                <div className="text-xs text-gray-500">Completed</div>
                <div className="mt-1 text-lg font-semibold text-gray-100">{metrics.totalCompleted}</div>
              </div>
              <div className="rounded-lg border border-gray-700/60 bg-gray-900/40 px-3 py-2">
                <div className="text-xs text-gray-500">Cancelled / Failed</div>
                <div className="mt-1 text-lg font-semibold text-gray-100">{metrics.totalCancelled}</div>
              </div>
              <div className="rounded-lg border border-gray-700/60 bg-gray-900/40 px-3 py-2">
                <div className="text-xs text-gray-500">Blocked</div>
                <div className="mt-1 text-lg font-semibold text-gray-100">{metrics.stateCounts.blocked}</div>
              </div>
              <div className="rounded-lg border border-gray-700/60 bg-gray-900/40 px-3 py-2">
                <div className="text-xs text-gray-500">Idle / Complete</div>
                <div className="mt-1 text-lg font-semibold text-gray-100">
                  {metrics.stateCounts.idle} / {metrics.stateCounts.complete}
                </div>
              </div>
            </div>

            {!executionActive && (
              <div className="mt-4 rounded-lg border border-gray-700/60 bg-gray-900/40 px-4 py-3 text-sm text-gray-400">
                No execution activity has been recorded yet. The card stays visible so new queue movement is obvious as soon as the ledger changes.
              </div>
            )}

            {executionMetricsError && (
              <div className="mt-4 rounded-lg border border-amber-700/40 bg-amber-900/20 px-4 py-3 text-sm text-amber-100">
                Refresh failed; showing the last successful metrics snapshot. {executionMetricsError}
              </div>
            )}
          </>
        )}
      </section>

      {(portfolioMission || portfolioAssessmentLoading || portfolioAssessmentError) && (
        <div className="mt-4 space-y-4">
          <div className="grid grid-cols-1 xl:grid-cols-[1.5fr,1fr] gap-4">
            <PortfolioMissionSection
              mission={portfolioMission}
              loading={portfolioAssessmentLoading}
              error={portfolioAssessmentError}
              onRetry={onRetryAssessment}
            />
            <section className="bg-gray-800/60 border border-gray-700 rounded-lg px-4 py-4">
              <div>
                <h2 className="text-lg font-semibold text-white">Documentation Health</h2>
                <p className="text-sm text-gray-400 mt-1">README, ROADMAP, and readiness quality derived from the indexed assessment.</p>
              </div>

              {portfolioMission ? (
                <div className="space-y-3 mt-4">
                  {[
                    { label: 'README Score', value: portfolioMission.averageReadmeScore, accent: 'bg-blue-500' },
                    { label: 'ROADMAP Score', value: portfolioMission.averageRoadmapScore, accent: 'bg-indigo-500' },
                    { label: 'Docs Health', value: portfolioMission.averageDocumentationHealthScore, accent: 'bg-emerald-500' },
                  ].map(metric => (
                    <div key={metric.label}>
                      <div className="flex items-center justify-between text-sm mb-1">
                        <span className="text-gray-300">{metric.label}</span>
                        <span className="text-white font-medium">{metric.value}%</span>
                      </div>
                      <div className="h-2 rounded-full bg-gray-900 overflow-hidden border border-gray-700">
                        <div className={`h-full ${metric.accent}`} style={{ width: `${metric.value}%` }} />
                      </div>
                    </div>
                  ))}

                  <div className="grid grid-cols-3 gap-3 pt-2">
                    <div className="rounded-lg border border-gray-700 bg-gray-900/50 px-3 py-3 text-center">
                      <div className="text-lg font-semibold text-sky-300">{portfolioMission.ciCoverage}</div>
                      <div className="mt-1 text-xs text-gray-400">CI Signals</div>
                    </div>
                    <div className="rounded-lg border border-gray-700 bg-gray-900/50 px-3 py-3 text-center">
                      <div className="text-lg font-semibold text-fuchsia-300">{portfolioMission.testCoverage}</div>
                      <div className="mt-1 text-xs text-gray-400">Test Signals</div>
                    </div>
                    <div className="rounded-lg border border-gray-700 bg-gray-900/50 px-3 py-3 text-center">
                      <div className="text-lg font-semibold text-amber-300">{portfolioMission.docsNeedingAttention}</div>
                      <div className="mt-1 text-xs text-gray-400">Repos With Findings</div>
                    </div>
                  </div>
                </div>
              ) : portfolioAssessmentLoading ? (
                <div className="flex items-center gap-3 py-8 text-gray-400 justify-center">
                  <SpinnerIcon className="w-5 h-5 animate-spin" />
                  <span>Computing documentation health…</span>
                </div>
              ) : (
                <div className="mt-4 rounded-lg border border-amber-700/40 bg-amber-900/20 px-4 py-3 text-sm text-amber-100">
                  {/* Release 3.1 "enabled means available": this panel named a
                      precondition and offered no way to satisfy it. An instruction
                      the surface cannot carry out is worse than no instruction. */}
                  <div>Documentation Health is unavailable until a portfolio assessment succeeds.</div>
                  {portfolioAssessmentError && (
                    <div className="mt-1 text-xs text-amber-200/80">Last attempt failed: {portfolioAssessmentError}</div>
                  )}
                  <div className="mt-2">
                    <button
                      onClick={onRetryAssessment}
                      disabled={portfolioAssessmentLoading}
                      data-testid="insights-run-assessment"
                      title={portfolioAssessmentLoading ? 'An assessment is already running.' : 'Runs a full portfolio assessment and seeds this panel.'}
                      className="inline-flex items-center gap-1.5 rounded border border-amber-600/60 bg-amber-900/30 px-2.5 py-1 text-xs text-amber-100 hover:bg-amber-900/50 disabled:opacity-50"
                    >
                      {portfolioAssessmentLoading && <SpinnerIcon className="w-3 h-3 animate-spin" />}
                      {portfolioAssessmentLoading ? 'Running assessment…' : 'Run portfolio assessment'}
                    </button>
                  </div>
                </div>
              )}
            </section>
          </div>

          <section className="bg-gray-800/60 border border-gray-700 rounded-lg px-4 py-4">
            <div className="flex items-start justify-between gap-4 flex-wrap">
              <div>
                <h2 className="text-lg font-semibold text-white">Portfolio Analytics</h2>
                <p className="text-sm text-gray-400 mt-1">Release 2.3 scaffold for portfolio momentum: current KPIs now, history-backed trend lines as the SQLite capture window fills in.</p>
              </div>
              {portfolioTrend && (
                <div className="flex flex-wrap items-center justify-end gap-2 text-xs">
                  <span className={`inline-flex rounded-full border px-2.5 py-1 font-medium ${portfolioTrend.trendStatus === 'history-backed' ? 'border-emerald-700/50 bg-emerald-900/30 text-emerald-100' : 'border-amber-700/50 bg-amber-900/30 text-amber-100'}`}>
                    {formatTrendStatusLabel(portfolioTrend.trendStatus)}
                  </span>
                  <span className="inline-flex rounded-full border border-gray-600 bg-gray-900/70 px-2.5 py-1 font-medium text-gray-200">
                    {formatTrendSeedSourceLabel(portfolioTrend.seedSource)}
                  </span>
                  <span className="text-gray-500">
                    Generated {new Date(portfolioTrend.generatedAt).toLocaleTimeString()}
                  </span>
                </div>
              )}
            </div>

            {portfolioTrend ? (
              <>
                <div className="grid grid-cols-2 lg:grid-cols-5 gap-3 mt-4">
                  {trendSummaryCards.map(metric => (
                    <div key={metric.label} className="rounded-lg border border-gray-700 bg-gray-900/50 px-3 py-3">
                      <div className={`text-lg font-semibold ${metric.accent}`}>{metric.value}</div>
                      <div className="mt-1 text-xs text-gray-400">{metric.label}</div>
                    </div>
                  ))}
                </div>

                <div className="mt-4 grid grid-cols-1 xl:grid-cols-[1.35fr,1fr] gap-4">
                  <div className="space-y-3">
                    {portfolioTrend.series.map(series => {
                      const palette = trendSeriesPalette(series.color);
                      const geometry = buildTrendGeometry(series.points);
                      const delta = geometry.lastValue - geometry.firstValue;
                      const deltaLabel = geometry.pointCount > 1
                        ? `${formatTrendSeriesDelta(series.key, delta)} vs start`
                        : 'Snapshot seed';

                      return (
                        <div key={series.key} className="rounded-xl border border-gray-700 bg-gray-900/50 px-4 py-4">
                          <div className="flex items-start justify-between gap-3 flex-wrap">
                            <div>
                              <div className="text-sm text-gray-400">{series.label}</div>
                              <div className={`mt-1 text-2xl font-semibold ${palette.textClass}`}>
                                {formatTrendSeriesValue(series.key, geometry.lastValue)}
                              </div>
                            </div>
                            <span className={`inline-flex rounded-full border px-2.5 py-1 text-xs font-medium ${palette.badgeClass}`}>
                              {deltaLabel}
                            </span>
                          </div>

                          <div className="mt-4 rounded-lg border border-gray-800 bg-gray-950/70 px-3 py-3">
                            <div className="flex items-center justify-between text-[11px] text-gray-500">
                              <span>{formatTrendDateLabel(geometry.startDate)}</span>
                              <span>{geometry.pointCount} point{geometry.pointCount === 1 ? '' : 's'} · {portfolioTrend.availableDays}d window</span>
                              <span>{formatTrendDateLabel(geometry.endDate)}</span>
                            </div>
                            <svg viewBox="0 0 320 92" className="mt-3 h-24 w-full" aria-hidden="true">
                              <line x1="10" y1="82" x2="310" y2="82" stroke="rgba(148, 163, 184, 0.18)" strokeWidth="1" />
                              <path d={geometry.areaPath} fill={palette.fill} />
                              {geometry.coordinates.length > 1 && (
                                <polyline
                                  points={geometry.polyline}
                                  fill="none"
                                  stroke={palette.stroke}
                                  strokeWidth="3"
                                  strokeLinejoin="round"
                                  strokeLinecap="round"
                                />
                              )}
                              {geometry.coordinates.map((coord, index) => (
                                <circle
                                  key={`${series.key}-${coord.point.date}-${index}`}
                                  cx={coord.x}
                                  cy={coord.y}
                                  r={index === geometry.coordinates.length - 1 ? 4 : 2.5}
                                  fill={palette.stroke}
                                  opacity={index === geometry.coordinates.length - 1 ? 1 : 0.6}
                                />
                              ))}
                            </svg>
                            <div className="mt-2 flex items-center justify-between text-xs text-gray-400">
                              <span>Low {formatTrendSeriesValue(series.key, geometry.min)}</span>
                              <span>High {formatTrendSeriesValue(series.key, geometry.max)}</span>
                            </div>
                          </div>
                        </div>
                      );
                    })}
                  </div>

                  <div className="space-y-3">
                    <div className="rounded-xl border border-gray-700 bg-gray-900/50 px-4 py-4">
                      <div className="flex items-start justify-between gap-3">
                        <div>
                          <h3 className="text-base font-semibold text-white">Repo Momentum</h3>
                          <p className="text-sm text-gray-400 mt-1">Per-repo maturity sparkline seeds for the highest-value candidates.</p>
                        </div>
                        <span className="text-xs text-gray-500">{portfolioTrend.repoSparklines.length} repo{portfolioTrend.repoSparklines.length === 1 ? '' : 's'}</span>
                      </div>

                      {portfolioTrend.repoSparklines.length > 0 ? (
                        <div className="mt-4 space-y-3">
                          {portfolioTrend.repoSparklines.map(repoSparkline => {
                            const sparkline = buildTrendGeometry(repoSparkline.points, 180, 46, 6);
                            return (
                              <div key={repoSparkline.repoName} className="rounded-lg border border-gray-700 bg-gray-950/60 px-3 py-3">
                                <div className="flex items-start justify-between gap-3">
                                  <div className="min-w-0">
                                    <div className="flex items-center gap-2 flex-wrap">
                                      <span className="text-sm font-medium text-white">{repoSparkline.repoName}</span>
                                      <span className={`inline-flex rounded-full border px-2 py-0.5 text-[11px] capitalize ${lifecycleStyle(repoSparkline.lifecycleState)}`}>
                                        {formatLifecycleLabel(repoSparkline.lifecycleState)}
                                      </span>
                                    </div>
                                    <div className="mt-1 text-xs text-gray-500">{repoSparkline.maturityLevel}</div>
                                  </div>
                                  <div className="w-40 sm:w-44 flex-shrink-0">
                                    <div className="flex items-center justify-between text-[11px] text-gray-500">
                                      <span>{formatTrendDateLabel(sparkline.startDate)}</span>
                                      <span className="font-medium text-emerald-200">{repoSparkline.currentScore}%</span>
                                    </div>
                                    <svg viewBox="0 0 180 46" className="mt-1 h-11 w-full" aria-hidden="true">
                                      <line x1="6" y1="40" x2="174" y2="40" stroke="rgba(148, 163, 184, 0.18)" strokeWidth="1" />
                                      <path d={sparkline.areaPath} fill="rgba(16, 185, 129, 0.16)" />
                                      {sparkline.coordinates.length > 1 && (
                                        <polyline
                                          points={sparkline.polyline}
                                          fill="none"
                                          stroke="#34d399"
                                          strokeWidth="2.5"
                                          strokeLinejoin="round"
                                          strokeLinecap="round"
                                        />
                                      )}
                                      {sparkline.coordinates.map((coord, index) => (
                                        <circle
                                          key={`${repoSparkline.repoName}-${coord.point.date}-${index}`}
                                          cx={coord.x}
                                          cy={coord.y}
                                          r={index === sparkline.coordinates.length - 1 ? 3.5 : 2.25}
                                          fill="#34d399"
                                          opacity={index === sparkline.coordinates.length - 1 ? 1 : 0.55}
                                        />
                                      ))}
                                    </svg>
                                  </div>
                                </div>
                                <div className="mt-2 text-xs text-gray-400 line-clamp-2">
                                  Next focus: <span className="text-gray-200">{repoSparkline.topValueItemText || repoSparkline.recommendedAction}</span>
                                </div>
                              </div>
                            );
                          })}
                        </div>
                      ) : (
                        <div className="mt-4 rounded-lg border border-dashed border-gray-700 bg-gray-950/40 px-4 py-4 text-sm text-gray-400">
                          No repo sparkline candidates are available yet. Refresh the indexed assessment once the portfolio has value-ranked items.
                        </div>
                      )}
                    </div>

                    <div className="rounded-xl border border-gray-700 bg-gray-900/50 px-4 py-4">
                      <div className="flex items-start justify-between gap-3">
                        <div>
                          <h3 className="text-base font-semibold text-white">Top Candidates</h3>
                          <p className="text-sm text-gray-400 mt-1">Current value-ranked queue from the assessment seed.</p>
                        </div>
                        <span className="text-xs text-gray-500">{portfolioTrend.topCandidates.length} repo{portfolioTrend.topCandidates.length === 1 ? '' : 's'}</span>
                      </div>

                      {portfolioTrend.topCandidates.length > 0 ? (
                        <div className="mt-4 space-y-2">
                          {portfolioTrend.topCandidates.map((candidate, index) => (
                            <div key={`${candidate.repoName}-${candidate.maturityLevel}`} className="rounded-lg border border-gray-700 bg-gray-950/60 px-3 py-3">
                              <div className="flex items-start gap-3">
                                <span className="inline-flex h-6 w-6 flex-shrink-0 items-center justify-center rounded-full bg-cyan-900/40 text-xs font-semibold text-cyan-100 border border-cyan-700/40">
                                  {index + 1}
                                </span>
                                <div className="min-w-0 flex-1">
                                  <div className="flex items-start justify-between gap-3">
                                    <div className="min-w-0">
                                      <div className="text-sm font-medium text-white">{candidate.repoName}</div>
                                      <div className="mt-1 text-xs text-gray-400 line-clamp-2">{candidate.topValueItemText}</div>
                                    </div>
                                    <div className="text-right">
                                      <div className="text-sm font-semibold text-cyan-200">{candidate.valueScore}</div>
                                      <div className="text-[11px] text-gray-500">Value score</div>
                                    </div>
                                  </div>
                                  <div className="mt-2 flex flex-wrap gap-2 text-[11px]">
                                    <span className={`inline-flex rounded-full border px-2 py-0.5 capitalize ${lifecycleStyle(candidate.lifecycleState)}`}>
                                      {formatLifecycleLabel(candidate.lifecycleState)}
                                    </span>
                                    <span className="inline-flex rounded-full border border-gray-600 bg-gray-900/70 px-2 py-0.5 text-gray-200">
                                      {candidate.maturityLevel}
                                    </span>
                                    <span className="inline-flex rounded-full border border-emerald-700/40 bg-emerald-900/20 px-2 py-0.5 text-emerald-200">
                                      {candidate.maturityScore}% maturity
                                    </span>
                                    <span className="inline-flex rounded-full border border-blue-700/40 bg-blue-900/20 px-2 py-0.5 text-blue-200">
                                      {candidate.documentationHealthScore}% docs
                                    </span>
                                  </div>
                                  <div className="mt-2 text-xs text-gray-500">{candidate.recommendedAction}</div>
                                </div>
                              </div>
                            </div>
                          ))}
                        </div>
                      ) : (
                        <div className="mt-4 rounded-lg border border-dashed border-gray-700 bg-gray-950/40 px-4 py-4 text-sm text-gray-400">
                          Trend scaffolding is active, but no candidate repos are ranked yet.
                        </div>
                      )}
                    </div>
                  </div>
                </div>

                {(portfolioTrend.note || portfolioTrendError) && (
                  <div className="mt-4 grid grid-cols-1 lg:grid-cols-2 gap-3">
                    {portfolioTrend.note && (
                      <div className="rounded-lg border border-blue-700/30 bg-blue-900/20 px-4 py-3 text-sm text-blue-100">
                        {portfolioTrend.note}
                      </div>
                    )}
                    {portfolioTrendError && (
                      <div className="rounded-lg border border-amber-700/40 bg-amber-900/20 px-4 py-3 text-sm text-amber-100">
                        Refresh failed; showing the last successful analytics snapshot. {portfolioTrendError}
                      </div>
                    )}
                  </div>
                )}
              </>
            ) : portfolioTrendLoading ? (
              <div className="flex items-center gap-3 py-8 text-gray-400 justify-center">
                <SpinnerIcon className="w-5 h-5 animate-spin" />
                <span>Loading portfolio analytics…</span>
              </div>
            ) : (
              <div className="mt-4 rounded-lg border border-amber-700/40 bg-amber-900/20 px-4 py-3 text-sm text-amber-100">
                Portfolio analytics are unavailable. {portfolioTrendError ?? 'Refresh the portfolio assessment to seed the Release 2.3 trend view.'}
                {/* The text told the operator to refresh the assessment while the
                    only button retried the trend fetch. Both controls now exist,
                    and each says which of the two things it does. */}
                <div className="mt-2 flex flex-wrap items-center gap-2">
                  <button
                    onClick={onRetryTrend}
                    title="Re-fetches the trend series without recomputing the assessment behind it."
                    className="px-2.5 py-1 rounded border border-amber-600/60 bg-amber-900/30 text-xs text-amber-100 hover:bg-amber-900/50"
                  >
                    Retry trend fetch
                  </button>
                  <button
                    onClick={onRetryAssessment}
                    disabled={portfolioAssessmentLoading}
                    data-testid="insights-trend-run-assessment"
                    title={portfolioAssessmentLoading ? 'An assessment is already running.' : 'Runs the portfolio assessment that seeds this trend view.'}
                    className="inline-flex items-center gap-1.5 rounded border border-amber-600/60 bg-amber-900/30 px-2.5 py-1 text-xs text-amber-100 hover:bg-amber-900/50 disabled:opacity-50"
                  >
                    {portfolioAssessmentLoading && <SpinnerIcon className="w-3 h-3 animate-spin" />}
                    {portfolioAssessmentLoading ? 'Running assessment…' : 'Run portfolio assessment'}
                  </button>
                </div>
              </div>
            )}
          </section>

          {portfolioMission && portfolioMission.topEntries.length > 0 && (
            <section className="bg-gray-800/60 border border-gray-700 rounded-lg px-4 py-4">
              <div>
                <h2 className="text-lg font-semibold text-white">Index-Backed Assessment</h2>
                <p className="text-sm text-gray-400 mt-1">Highest-value and highest-friction repos surfaced from the portfolio assessment order.</p>
              </div>

              <div className="mt-4 space-y-3">
                {portfolioMission.topEntries.map(entry => (
                  <div key={`${entry.repoName}-${entry.sourceCoverage}`} className="rounded-lg border border-gray-700 bg-gray-900/40 px-4 py-3">
                    <div className="flex items-start justify-between gap-3 flex-wrap">
                      <div>
                        <div className="flex items-center gap-2 flex-wrap">
                          <span className="text-white font-medium">{entry.repoName}</span>
                          <span className={`inline-flex rounded-full border px-2 py-0.5 text-xs capitalize ${lifecycleStyle(entry.lifecycleState)}`}>
                            {formatLifecycleLabel(entry.lifecycleState)}
                          </span>
                          <span className="inline-flex rounded-full border border-gray-600 px-2 py-0.5 text-xs text-gray-300 bg-gray-800">
                            {entry.maturityLevel}
                          </span>
                          <span className="inline-flex rounded-full border border-cyan-700/40 px-2 py-0.5 text-xs text-cyan-200 bg-cyan-900/20">
                            {entry.dispatchReadiness}
                          </span>
                        </div>
                        <div className="text-sm text-gray-300 mt-2">{entry.recommendedAction}</div>
                        {(entry.topValueItem?.text || entry.nextPendingItemText) && (
                          <div className="text-xs text-gray-400 mt-2">
                            Next focus: <span className="text-gray-200">{entry.topValueItem?.text ?? entry.nextPendingItemText}</span>
                          </div>
                        )}
                        {entry.dispatchReadinessExplanation && (
                          <div className="text-xs text-gray-500 mt-1">{entry.dispatchReadinessExplanation}</div>
                        )}
                      </div>

                      <div className="grid grid-cols-2 gap-2 min-w-[220px]">
                        <div className="rounded border border-gray-700 bg-gray-800/60 px-3 py-2 text-center">
                          <div className="text-sm font-semibold text-blue-200">{entry.readmeScore ?? 0}%</div>
                          <div className="text-[11px] text-gray-500 mt-0.5">README</div>
                        </div>
                        <div className="rounded border border-gray-700 bg-gray-800/60 px-3 py-2 text-center">
                          <div className="text-sm font-semibold text-indigo-200">{entry.roadmapScore ?? 0}%</div>
                          <div className="text-[11px] text-gray-500 mt-0.5">ROADMAP</div>
                        </div>
                        <div className="rounded border border-gray-700 bg-gray-800/60 px-3 py-2 text-center">
                          <div className="text-sm font-semibold text-emerald-200">{entry.documentationHealthScore ?? 0}%</div>
                          <div className="text-[11px] text-gray-500 mt-0.5">Docs Health</div>
                        </div>
                        <div className="rounded border border-gray-700 bg-gray-800/60 px-3 py-2 text-center">
                          <div className="text-sm font-semibold text-cyan-200">{entry.openPrCount ?? 0}</div>
                          <div className="text-[11px] text-gray-500 mt-0.5">Open PRs</div>
                        </div>
                      </div>
                    </div>
                  </div>
                ))}
              </div>
            </section>
          )}
        </div>
      )}

      {repos.length === 0 && isLocalSource && (
        <div className="mt-4 bg-yellow-900/20 border border-yellow-700/60 rounded-lg px-4 py-3 text-sm text-yellow-100">
          No repositories found. Confirm the workspace path contains git repositories and adjust scan depth if your repos are nested.
        </div>
      )}

      {repos.some(r => r.extended) && (
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4 mt-4">
          <SummaryCard
            title="Open Issues"
            value={extendedSummary.totalIssues}
            color="yellow"
            icon={<IssuesIcon className="w-6 h-6" />}
          />
          <SummaryCard
            title="Active Projects"
            value={extendedSummary.totalProjects}
            color="purple"
            icon={<ProjectsIcon className="w-6 h-6" />}
          />
          <SummaryCard
            title="Stale Branches"
            value={extendedSummary.totalStaleBranches}
            color="orange"
            icon={<BranchIcon className="w-6 h-6" />}
          />
          <SummaryCard
            title="Avg Health Score"
            value={`${extendedSummary.avgHealthScore}%`}
            color="green"
            icon={<HealthIcon className="w-6 h-6" />}
          />
        </div>
      )}

      <ChangeHistoryPanel repos={repos} />
    </div>
  );
};

export default InsightsView;
