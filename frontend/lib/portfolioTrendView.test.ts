import { describe, it, expect } from 'vitest';
import {
  buildTrendGeometry,
  buildTrendSummaryCards,
  EMPTY_EXECUTION_METRICS,
  formatLifecycleLabel,
  formatTrendSeedSourceLabel,
  formatTrendSeriesDelta,
  formatTrendSeriesValue,
  formatTrendStatusLabel,
  formatTrendDateLabel,
  hasExecutionActivity,
  lifecycleStyle,
  trendSeriesPalette,
  LIFECYCLE_STYLES,
  TREND_SERIES_COLORS,
} from './portfolioTrendView';
import type { PortfolioTrendPoint, PortfolioTrendResult } from '../types';

const pt = (date: string, value: number): PortfolioTrendPoint => ({ date, value } as PortfolioTrendPoint);

describe('buildTrendGeometry', () => {
  it('projects a normal series inside the padded box', () => {
    const g = buildTrendGeometry([pt('2026-08-01', 10), pt('2026-08-02', 20), pt('2026-08-03', 30)]);
    expect(g.pointCount).toBe(3);
    expect(g.min).toBe(10);
    expect(g.max).toBe(30);
    expect(g.firstValue).toBe(10);
    expect(g.lastValue).toBe(30);
    expect(g.startDate).toBe('2026-08-01');
    expect(g.endDate).toBe('2026-08-03');
    // Highest value sits at the top of the padded box, lowest at the bottom.
    expect(g.coordinates[2].y).toBeCloseTo(10);
    expect(g.coordinates[0].y).toBeCloseTo(82);
    for (const c of g.coordinates) {
      expect(c.x).toBeGreaterThanOrEqual(10);
      expect(c.x).toBeLessThanOrEqual(310);
    }
  });

  // An empty series used to reach Math.min() of nothing → Infinity → NaN in the
  // path data, which renders as a silently blank chart rather than an error.
  it('substitutes a baseline point for an empty series instead of producing NaN', () => {
    const g = buildTrendGeometry([]);
    expect(g.pointCount).toBe(1);
    expect(Number.isFinite(g.min)).toBe(true);
    expect(Number.isFinite(g.max)).toBe(true);
    expect(g.areaPath).not.toMatch(/NaN/);
    expect(g.polyline).not.toMatch(/NaN/);
  });

  // A flat series has zero range; dividing by it would produce NaN for every y.
  it('pins a perfectly flat series to the vertical midpoint', () => {
    const g = buildTrendGeometry([pt('2026-08-01', 42), pt('2026-08-02', 42), pt('2026-08-03', 42)]);
    expect(g.areaPath).not.toMatch(/NaN/);
    const ys = g.coordinates.map(c => c.y);
    expect(new Set(ys).size).toBe(1);
    expect(ys[0]).toBeCloseTo(46);
  });

  it('centres a single point rather than dividing by zero on the x axis', () => {
    const g = buildTrendGeometry([pt('2026-08-01', 5)]);
    expect(g.coordinates).toHaveLength(1);
    expect(g.coordinates[0].x).toBeCloseTo(160);
    expect(g.polyline).not.toMatch(/NaN/);
    expect(g.areaPath).not.toMatch(/NaN/);
  });

  it('honours a custom viewport for the repo sparklines', () => {
    const g = buildTrendGeometry([pt('2026-08-01', 0), pt('2026-08-02', 1)], 180, 46, 6);
    expect(g.coordinates[0].x).toBeCloseTo(6);
    expect(g.coordinates[1].x).toBeCloseTo(174);
  });

  it('treats a null value as zero rather than NaN', () => {
    const g = buildTrendGeometry([pt('2026-08-01', null as unknown as number), pt('2026-08-02', 10)]);
    expect(g.min).toBe(0);
    expect(g.areaPath).not.toMatch(/NaN/);
  });
});

describe('trend formatting', () => {
  it('renders maturity as a percentage and counts as integers', () => {
    expect(formatTrendSeriesValue('avgMaturityScore', 67.4)).toBe('67%');
    expect(formatTrendSeriesValue('readyForWorkCount', 3.6)).toBe('4');
  });

  it('signs a positive delta but never a negative one twice', () => {
    expect(formatTrendSeriesDelta('avgMaturityScore', 2.34)).toBe('+2.3%');
    expect(formatTrendSeriesDelta('avgMaturityScore', -2.34)).toBe('-2.3%');
    expect(formatTrendSeriesDelta('readyForWorkCount', 3)).toBe('+3');
    expect(formatTrendSeriesDelta('readyForWorkCount', -3)).toBe('-3');
  });

  it('shows no sign for a zero delta', () => {
    expect(formatTrendSeriesDelta('readyForWorkCount', 0)).toBe('0');
  });

  it('distinguishes real history from a snapshot seed', () => {
    expect(formatTrendStatusLabel('history-backed')).toBe('History backed');
    expect(formatTrendStatusLabel('snapshot-seed' as PortfolioTrendResult['trendStatus'])).toBe('Current snapshot');
    expect(formatTrendSeedSourceLabel('portfolio-index')).toBe('Portfolio index');
    expect(formatTrendSeedSourceLabel('assessment-cache' as PortfolioTrendResult['seedSource'])).toBe('Assessment cache');
  });

  it('falls back to the raw string for an unparseable date', () => {
    expect(formatTrendDateLabel('not-a-date')).toBe('not-a-date');
  });

  it('humanises a lifecycle state', () => {
    expect(formatLifecycleLabel('needs-roadmap-repair')).toBe('needs roadmap repair');
  });
});

describe('palette and style fallbacks', () => {
  // A chart with no stroke colour renders invisibly — worse than a wrong colour.
  it('falls back to a real palette for an unknown series colour', () => {
    expect(trendSeriesPalette('fuchsia')).toBe(TREND_SERIES_COLORS.emerald);
    expect(trendSeriesPalette(undefined)).toBe(TREND_SERIES_COLORS.emerald);
    expect(trendSeriesPalette('sky')).toBe(TREND_SERIES_COLORS.sky);
  });

  it('falls back to a real chip style for an unknown lifecycle state', () => {
    expect(lifecycleStyle('brand-new-state')).toBe(LIFECYCLE_STYLES.discovered);
    expect(lifecycleStyle(undefined)).toBe(LIFECYCLE_STYLES.discovered);
    expect(lifecycleStyle('running')).toBe(LIFECYCLE_STYLES.running);
  });
});

describe('hasExecutionActivity', () => {
  it('is false for a ledger that has recorded nothing', () => {
    expect(hasExecutionActivity(EMPTY_EXECUTION_METRICS)).toBe(false);
  });

  it('is true as soon as any counter moves', () => {
    for (const patch of [
      { totalCompleted: 1 },
      { totalCancelled: 1 },
      { stateCounts: { ...EMPTY_EXECUTION_METRICS.stateCounts, running: 1 } },
      { stateCounts: { ...EMPTY_EXECUTION_METRICS.stateCounts, ready: 1 } },
      { stateCounts: { ...EMPTY_EXECUTION_METRICS.stateCounts, blocked: 1 } },
      { stateCounts: { ...EMPTY_EXECUTION_METRICS.stateCounts, complete: 1 } },
    ]) {
      expect(hasExecutionActivity({ ...EMPTY_EXECUTION_METRICS, ...patch })).toBe(true);
    }
  });

  // Idle is not activity: a queue sitting at rest must not light the card up.
  it('ignores the idle count', () => {
    expect(hasExecutionActivity({
      ...EMPTY_EXECUTION_METRICS,
      stateCounts: { ...EMPTY_EXECUTION_METRICS.stateCounts, idle: 9 },
    })).toBe(false);
  });
});

describe('buildTrendSummaryCards', () => {
  const trend = {
    availableDays: 14,
    summary: {
      averageMaturityScore: 66.6,
      averageDocumentationHealthScore: 71.2,
      readyForWorkCount: 4,
      improvedThisWeek: 2,
    },
  } as PortfolioTrendResult;

  it('renders five tiles with rounded percentages', () => {
    const cards = buildTrendSummaryCards(trend);
    expect(cards).toHaveLength(5);
    expect(cards[0]).toMatchObject({ label: 'Avg Maturity', value: '67%' });
    expect(cards[1]).toMatchObject({ label: 'Docs Health', value: '71%' });
    expect(cards[4]).toMatchObject({ label: 'Visible Window', value: '14d' });
  });

  it('renders nothing when no trend is loaded', () => {
    expect(buildTrendSummaryCards(null)).toEqual([]);
    expect(buildTrendSummaryCards(undefined)).toEqual([]);
  });
});
