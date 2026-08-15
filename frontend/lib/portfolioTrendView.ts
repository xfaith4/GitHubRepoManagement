// Presentation helpers for the Insights surface (Release 2.3 analytics).
//
// Extracted from Dashboard.tsx when the Insights block moved inside its own tab
// panel. They live here rather than beside the component for the same reason
// `valueTier` and `viewTabs` do: the sparkline geometry is arithmetic with real
// edge cases (a single point, a perfectly flat series, an empty series) and
// those are worth asserting directly rather than through a rendered chart.

import { type PortfolioTrendPoint, type PortfolioTrendResult, type RepoLifecycleState, type ExecutionMetrics } from '../types';

export const LIFECYCLE_STYLES: Record<RepoLifecycleState, string> = {
  discovered: 'bg-slate-800 text-slate-200 border-slate-600',
  'needs-readme': 'bg-amber-900/40 text-amber-200 border-amber-700/50',
  'needs-roadmap': 'bg-amber-900/40 text-amber-200 border-amber-700/50',
  'needs-roadmap-repair': 'bg-orange-900/40 text-orange-200 border-orange-700/50',
  'needs-structure': 'bg-orange-900/40 text-orange-200 border-orange-700/50',
  'ready-for-work': 'bg-emerald-900/40 text-emerald-200 border-emerald-700/50',
  running: 'bg-blue-900/40 text-blue-200 border-blue-700/50',
  completed: 'bg-violet-900/40 text-violet-200 border-violet-700/50',
  monitored: 'bg-cyan-900/40 text-cyan-200 border-cyan-700/50',
  archived: 'bg-gray-800 text-gray-300 border-gray-600',
  'parse-error': 'bg-red-900/40 text-red-200 border-red-700/50',
};

export interface TrendSeriesPalette {
  stroke: string;
  fill: string;
  textClass: string;
  badgeClass: string;
}

export const TREND_SERIES_COLORS: Record<string, TrendSeriesPalette> = {
  emerald: {
    stroke: '#34d399',
    fill: 'rgba(16, 185, 129, 0.18)',
    textClass: 'text-emerald-200',
    badgeClass: 'border-emerald-700/50 bg-emerald-900/30 text-emerald-100',
  },
  sky: {
    stroke: '#38bdf8',
    fill: 'rgba(14, 165, 233, 0.16)',
    textClass: 'text-sky-200',
    badgeClass: 'border-sky-700/50 bg-sky-900/30 text-sky-100',
  },
  amber: {
    stroke: '#fbbf24',
    fill: 'rgba(245, 158, 11, 0.16)',
    textClass: 'text-amber-200',
    badgeClass: 'border-amber-700/50 bg-amber-900/30 text-amber-100',
  },
  slate: {
    stroke: '#94a3b8',
    fill: 'rgba(148, 163, 184, 0.14)',
    textClass: 'text-slate-200',
    badgeClass: 'border-slate-700/50 bg-slate-900/30 text-slate-100',
  },
};

/** Palette for a series colour name, falling back rather than rendering nothing. */
export function trendSeriesPalette(color: string | undefined): TrendSeriesPalette {
  return TREND_SERIES_COLORS[color ?? ''] ?? TREND_SERIES_COLORS.emerald;
}

/** Lifecycle chip classes, falling back to `discovered` for an unknown state. */
export function lifecycleStyle(state: RepoLifecycleState | string | undefined): string {
  return LIFECYCLE_STYLES[state as RepoLifecycleState] ?? LIFECYCLE_STYLES.discovered;
}

export function formatLifecycleLabel(state: RepoLifecycleState | string): string {
  return String(state).replaceAll('-', ' ');
}

export function formatTrendStatusLabel(status: PortfolioTrendResult['trendStatus']): string {
  return status === 'history-backed' ? 'History backed' : 'Current snapshot';
}

export function formatTrendSeedSourceLabel(source: PortfolioTrendResult['seedSource']): string {
  return source === 'portfolio-index' ? 'Portfolio index' : 'Assessment cache';
}

export function formatTrendDateLabel(date: string): string {
  const parsed = new Date(`${date}T00:00:00`);
  if (Number.isNaN(parsed.getTime())) {
    return date;
  }
  return parsed.toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
}

export function formatTrendSeriesValue(key: string, value: number): string {
  if (key === 'avgMaturityScore') {
    return `${Math.round(value)}%`;
  }
  return Math.round(value).toString();
}

export function formatTrendSeriesDelta(key: string, delta: number): string {
  const rounded = key === 'avgMaturityScore'
    ? Math.round(delta * 10) / 10
    : Math.round(delta);
  const sign = rounded > 0 ? '+' : '';
  return key === 'avgMaturityScore' ? `${sign}${rounded}%` : `${sign}${rounded}`;
}

export interface TrendGeometry {
  coordinates: Array<{ x: number; y: number; point: PortfolioTrendPoint }>;
  polyline: string;
  areaPath: string;
  min: number;
  max: number;
  firstValue: number;
  lastValue: number;
  pointCount: number;
  startDate: string;
  endDate: string;
}

/**
 * Project a trend series into SVG coordinates.
 *
 * Two edge cases are deliberate rather than incidental:
 *  - An **empty** series is substituted with one zero-valued point at today's
 *    date, so the chart renders a flat baseline instead of `Math.min()` of
 *    nothing returning `Infinity` and producing `NaN` path data.
 *  - A **flat** series (every value identical) has zero range, so every point
 *    is pinned at the vertical midpoint rather than dividing by zero.
 */
export function buildTrendGeometry(
  points: PortfolioTrendPoint[],
  width = 320,
  height = 92,
  padding = 10
): TrendGeometry {
  const safePoints = points.length > 0
    ? points
    : [{ date: new Date().toISOString().slice(0, 10), value: 0 } as PortfolioTrendPoint];
  const values = safePoints.map(point => Number(point.value ?? 0));
  const min = Math.min(...values);
  const max = Math.max(...values);
  const rawRange = max - min;
  const innerWidth = Math.max(width - padding * 2, 1);
  const innerHeight = Math.max(height - padding * 2, 1);
  const coordinates = safePoints.map((point, index) => {
    const ratioX = safePoints.length === 1 ? 0.5 : index / (safePoints.length - 1);
    const normalized = rawRange === 0 ? 0.5 : (Number(point.value ?? 0) - min) / rawRange;
    return {
      x: padding + ratioX * innerWidth,
      y: padding + (1 - normalized) * innerHeight,
      point,
    };
  });
  const polyline = coordinates.map(({ x, y }) => `${x},${y}`).join(' ');
  const baselineY = height - padding;
  const areaPath = coordinates.length === 1
    ? `M ${coordinates[0].x} ${baselineY} L ${coordinates[0].x} ${coordinates[0].y} L ${coordinates[0].x} ${baselineY} Z`
    : `M ${coordinates[0].x} ${baselineY} L ${coordinates.map(({ x, y }) => `${x} ${y}`).join(' L ')} L ${coordinates[coordinates.length - 1].x} ${baselineY} Z`;

  return {
    coordinates,
    polyline,
    areaPath,
    min,
    max,
    firstValue: values[0],
    lastValue: values[values.length - 1],
    pointCount: safePoints.length,
    startDate: safePoints[0].date,
    endDate: safePoints[safePoints.length - 1].date,
  };
}

export const EMPTY_EXECUTION_METRICS: ExecutionMetrics = {
  completedToday: 0,
  completedThisWeek: 0,
  totalCompleted: 0,
  totalCancelled: 0,
  avgCurrentRunMins: 0,
  errorRatePct: 0,
  stateCounts: {
    idle: 0,
    ready: 0,
    running: 0,
    blocked: 0,
    complete: 0,
  },
};

/**
 * Whether the execution ledger has ever recorded anything.
 *
 * Drives an explanatory empty state rather than hiding the card: a throughput
 * panel that disappears when idle makes new queue movement invisible until
 * someone happens to look.
 */
export function hasExecutionActivity(metrics: ExecutionMetrics): boolean {
  return metrics.totalCompleted > 0 ||
    metrics.totalCancelled > 0 ||
    metrics.stateCounts.running > 0 ||
    metrics.stateCounts.ready > 0 ||
    metrics.stateCounts.blocked > 0 ||
    metrics.stateCounts.complete > 0;
}

export interface TrendSummaryCard {
  label: string;
  value: string;
  accent: string;
  /**
   * Coverage note rendered under the value ("of 52 assessed"). Present only
   * when the metric was computed over fewer repos than the portfolio holds —
   * a partial sample must say so rather than pose as the whole (Release 3.5).
   */
  hint?: string;
}

/**
 * A percentage tile's text. null means the metric was never computed, and the
 * honest render is an em dash — a `0%` here is indistinguishable from a
 * measured zero, which is the Release 3.5 milestone 4c defect.
 */
function formatPercentTile(value: number | null): string {
  return value == null ? '—' : `${Math.round(value)}%`;
}

function coverageHint(assessed: number, total: number, value: number | null): string | undefined {
  if (value == null) return 'not yet assessed';
  if (assessed > 0 && total > 0 && assessed < total) return `of ${assessed} assessed`;
  return undefined;
}

/** The five KPI tiles above the trend charts. Empty when no trend is loaded. */
export function buildTrendSummaryCards(trend: PortfolioTrendResult | null | undefined): TrendSummaryCard[] {
  if (!trend) return [];
  const s = trend.summary;
  return [
    { label: 'Avg Maturity', value: formatPercentTile(s.averageMaturityScore), accent: 'text-emerald-200', hint: coverageHint(s.maturityAssessedCount, s.totalRepos, s.averageMaturityScore) },
    { label: 'Docs Health', value: formatPercentTile(s.averageDocumentationHealthScore), accent: 'text-sky-200', hint: coverageHint(s.docsHealthAssessedCount, s.totalRepos, s.averageDocumentationHealthScore) },
    { label: 'Ready Now', value: s.readyForWorkCount.toString(), accent: 'text-blue-200' },
    { label: 'Improved This Week', value: s.improvedThisWeek.toString(), accent: 'text-cyan-200' },
    { label: 'Visible Window', value: `${trend.availableDays}d`, accent: 'text-amber-200' },
  ];
}
