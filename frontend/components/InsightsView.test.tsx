// @vitest-environment jsdom
//
// DOM tests for the Insights tab body (ROADMAP Lane 0.8). The Lane 0.5
// module-smoke tripwire asserts SOURCE ORDER (InsightsView mounts after the
// tab strip); these assert the BEHAVIOR that order is a proxy for — the panel
// actually renders its content, keeps empty states visible and explanatory,
// and wires the retry path to the caller.
import { describe, it, expect, vi, afterEach } from 'vitest';
import { render, screen, fireEvent, cleanup, within, act } from '@testing-library/react';
import '@testing-library/jest-dom/vitest';
import React from 'react';
import InsightsView from './InsightsView';
import { EMPTY_EXECUTION_METRICS } from '../lib/portfolioTrendView';
import type { PortfolioTrendResult } from '../types';

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
});

// Captures what the trend sparklines observe, so a test can hand them a width.
type ResizeCallback = (entries: Array<{ contentRect: { width: number } }>) => void;
const resizeObservers: FakeResizeObserver[] = [];
class FakeResizeObserver {
  observed: Element[] = [];
  constructor(private readonly callback: ResizeCallback) { resizeObservers.push(this); }
  observe(el: Element) { this.observed.push(el); }
  unobserve() { /* unused */ }
  disconnect() { /* unused */ }
  resize(width: number) { this.callback([{ contentRect: { width } }]); }
}

const TREND_FIXTURE: PortfolioTrendResult = {
  trendStatus: 'history-backed',
  seedSource: 'portfolio-index',
  requestedDays: 90,
  availableDays: 33,
  generatedAt: '2026-09-04T00:00:00.000Z',
  summary: {
    totalRepos: 59,
    readyForWorkCount: 8,
    runningCount: 0,
    blockedCount: 0,
    completedCount: 0,
    averageMaturityScore: 35,
    averageDocumentationHealthScore: 50,
    maturityAssessedCount: 59,
    docsHealthAssessedCount: 59,
    improvedThisWeek: 1,
  },
  series: [
    { key: 'avgMaturityScore', label: 'Avg Maturity', color: 'emerald', points: [{ date: '2026-08-01', value: 30 }, { date: '2026-09-04', value: 35 }] },
    { key: 'readyRepos', label: 'Work-ready (L3+)', color: 'sky', points: [{ date: '2026-08-01', value: 18 }, { date: '2026-09-04', value: 8 }] },
  ],
  topCandidates: [],
  repoSparklines: [],
};

function renderEmptyInsights(overrides: Partial<React.ComponentProps<typeof InsightsView>> = {}) {
  const handlers = {
    onRefreshExecutionMetrics: vi.fn(),
    onRetryAssessment: vi.fn(),
    onRetryTrend: vi.fn(),
  };
  render(
    <InsightsView
      repos={[]}
      isLocalSource={true}
      extendedSummary={{ totalIssues: 0, totalProjects: 0, totalStaleBranches: 0, avgHealthScore: 0 }}
      executionMetrics={null}
      executionMetricsLoading={false}
      executionMetricsRefreshing={false}
      executionMetricsError={null}
      executionMetricsUpdatedAt={null}
      portfolioMission={null}
      portfolioAssessment={null}
      portfolioAssessmentLoading={false}
      portfolioAssessmentError={null}
      portfolioTrend={null}
      portfolioTrendLoading={false}
      portfolioTrendError={null}
      {...handlers}
      {...overrides}
    />
  );
  return handlers;
}

describe('InsightsView', () => {
  it('renders the panel body — the DOM half of the Lane 0.5 tab contract', () => {
    renderEmptyInsights();
    expect(screen.getByTestId('insights-view')).toBeInTheDocument();
    expect(screen.getByText(/Insights is read-only analytics/)).toBeInTheDocument();
  });

  // The series charts used a fixed 320-unit viewBox, which the SVG default
  // aspect handling scaled to the box height and centred: a ~330px line in
  // the middle of a ~1200px card. Each series now draws in its card's
  // measured width.
  it('draws each trend series across the measured width of its card', () => {
    vi.stubGlobal('ResizeObserver', FakeResizeObserver);
    // The analytics block is shown once any assessment context exists; the
    // error is the cheapest context, as the retry tests above use it.
    renderEmptyInsights({ portfolioTrend: TREND_FIXTURE, portfolioAssessmentError: 'assessment failed' });

    for (const key of ['avgMaturityScore', 'readyRepos']) {
      const wrapper = screen.getByTestId(`trend-sparkline-${key}`);
      const observer = resizeObservers.find(o => o.observed.includes(wrapper));
      expect(observer).toBeDefined();
      act(() => observer!.resize(1180));
      const svg = wrapper.querySelector('svg');
      expect(svg).toHaveAttribute('viewBox', '0 0 1180 96');
      expect(svg!.querySelector('line')).toHaveAttribute('x2', '1170');
    }
  });

  // An idle ledger (loaded, all zeros) keeps its card VISIBLE with an
  // explanation. A throughput panel that disappears when idle makes new queue
  // movement invisible. A ledger that never LOADED is the different,
  // red-bordered "unavailable" state — asserted separately below.
  it('explains an empty execution ledger instead of hiding the card', () => {
    renderEmptyInsights({ executionMetrics: EMPTY_EXECUTION_METRICS });
    expect(screen.getByText(/No execution activity has been recorded yet/)).toBeInTheDocument();
  });

  it('distinguishes metrics that never loaded from an idle ledger', () => {
    renderEmptyInsights({ executionMetricsError: 'ledger endpoint unreachable' });
    expect(screen.getByText(/ledger endpoint unreachable/)).toBeInTheDocument();
    expect(screen.queryByText(/No execution activity has been recorded yet/)).not.toBeInTheDocument();
  });

  // The analytics block only mounts once there is assessment context (a
  // mission, a load in flight, or an error); with context but no trend it must
  // say so and offer a retry wired to the TREND loader, not the assessment's.
  it('offers a wired trend retry when portfolio analytics are unavailable', () => {
    const { onRetryTrend } = renderEmptyInsights({ portfolioAssessmentError: 'assessment failed' });
    const unavailableBox = screen.getByText(/Portfolio analytics are unavailable/);
    fireEvent.click(within(unavailableBox).getByRole('button', { name: 'Retry trend fetch' }));
    expect(onRetryTrend).toHaveBeenCalledTimes(1);
  });

  // Release 3.1 "enabled means available". This panel told the operator to
  // refresh the portfolio assessment while its only button re-fetched the
  // trend — the instruction and the control disagreed, and the button was
  // named just "Retry", so neither said which of the two it did. Both actions
  // now exist and each is named for the one thing it does.
  it('also offers the assessment run its own text tells the operator to do', () => {
    const { onRetryAssessment, onRetryTrend } = renderEmptyInsights({ portfolioAssessmentError: 'assessment failed' });
    const unavailableBox = screen.getByText(/Portfolio analytics are unavailable/);
    fireEvent.click(within(unavailableBox).getByRole('button', { name: 'Run portfolio assessment' }));
    expect(onRetryAssessment).toHaveBeenCalledTimes(1);
    expect(onRetryTrend).not.toHaveBeenCalled();
  });

  // Documentation Health named a precondition and offered nothing that could
  // satisfy it. An instruction a surface cannot carry out is worse than none.
  it('gives Documentation Health a control that runs the assessment it waits for', () => {
    const { onRetryAssessment } = renderEmptyInsights({ portfolioAssessmentError: 'assessment failed' });
    fireEvent.click(screen.getByTestId('insights-run-assessment'));
    expect(onRetryAssessment).toHaveBeenCalledTimes(1);
  });

  // Documentation Health swaps to a spinner while an assessment runs, so its
  // control has no disabled state to reach. The analytics panel's copy of the
  // action does, and it must name the reason rather than just grey out.
  it('disables the analytics assessment control while one is already running, and says so', () => {
    renderEmptyInsights({ portfolioAssessmentLoading: true, portfolioAssessmentError: 'assessment failed' });
    const control = screen.getByTestId('insights-trend-run-assessment');
    expect(control).toBeDisabled();
    expect(control).toHaveAttribute('title', expect.stringContaining('already running'));
  });

  // A failed refresh must degrade to "stale but labeled", never silently
  // presenting old numbers as current.
  it('labels stale metrics when a refresh fails but a snapshot exists', () => {
    renderEmptyInsights({
      executionMetrics: {
        ...EMPTY_EXECUTION_METRICS,
        completedToday: 1,
        completedThisWeek: 2,
        totalCompleted: 3,
        avgCurrentRunMins: 5,
        stateCounts: { ...EMPTY_EXECUTION_METRICS.stateCounts, ready: 1, running: 1, complete: 3 },
      },
      executionMetricsError: 'metrics endpoint timed out',
    });
    expect(screen.getByText(/showing the last successful metrics snapshot/)).toBeInTheDocument();
    expect(screen.getByText(/metrics endpoint timed out/)).toBeInTheDocument();
  });
});

it('distinguishes ledger blockers from assessed repository blockers', () => {
  renderEmptyInsights({ executionMetrics: { ...EMPTY_EXECUTION_METRICS, stateCounts: { idle: 2, ready: 3, running: 1, blocked: 4, complete: 5 } } });
  expect(screen.getByText('Execution blocked')).toBeVisible();
  expect(screen.getByText('of 15 ledger repositories')).toBeVisible();
});
