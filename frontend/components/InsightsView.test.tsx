// @vitest-environment jsdom
//
// DOM tests for the Insights tab body (ROADMAP Lane 0.8). The Lane 0.5
// module-smoke tripwire asserts SOURCE ORDER (InsightsView mounts after the
// tab strip); these assert the BEHAVIOR that order is a proxy for — the panel
// actually renders its content, keeps empty states visible and explanatory,
// and wires the retry path to the caller.
import { describe, it, expect, vi, afterEach } from 'vitest';
import { render, screen, fireEvent, cleanup, within } from '@testing-library/react';
import '@testing-library/jest-dom/vitest';
import React from 'react';
import InsightsView from './InsightsView';
import { EMPTY_EXECUTION_METRICS } from '../lib/portfolioTrendView';

afterEach(cleanup);

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
  it('offers a wired Retry when portfolio analytics are unavailable', () => {
    const { onRetryTrend } = renderEmptyInsights({ portfolioAssessmentError: 'assessment failed' });
    const unavailableBox = screen.getByText(/Portfolio analytics are unavailable/);
    fireEvent.click(within(unavailableBox).getByRole('button', { name: 'Retry' }));
    expect(onRetryTrend).toHaveBeenCalledTimes(1);
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
