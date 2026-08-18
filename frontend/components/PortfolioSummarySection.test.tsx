// @vitest-environment jsdom
//
// Release 3.5 — the KPI header's two honesty features: the scope statement
// (counts name the set they cover) and the scan-completion announcement
// (milestone 7: a finished scan is announced to screen readers, not just
// painted).
import { describe, it, expect, afterEach } from 'vitest';
import { render, screen, cleanup } from '@testing-library/react';
import '@testing-library/jest-dom/vitest';
import React from 'react';
import PortfolioSummarySection from './PortfolioSummarySection';

afterEach(() => cleanup());

const summary = { total: 52, needsAttention: 4, dirty: 3, stale: 7, commitsThisWeek: 12 };

describe('PortfolioSummarySection', () => {
  it('announces scan completion via a polite live region', () => {
    render(
      <PortfolioSummarySection
        sourceLabel="Local workspace"
        summary={summary}
        dataLastUpdated={new Date('2026-08-17T12:00:00')}
      />
    );
    const region = screen.getByTestId('scan-completion-announcement');
    expect(region).toHaveAttribute('role', 'status');
    expect(region).toHaveAttribute('aria-live', 'polite');
    expect(region.textContent).toContain('52 repositories');
  });

  it('does not claim a scan completed when none has', () => {
    render(<PortfolioSummarySection sourceLabel="Local workspace" summary={summary} />);
    expect(screen.queryByTestId('scan-completion-announcement')).toBeNull();
  });

  it('states the scope of its counts when repos are excluded', () => {
    render(
      <PortfolioSummarySection
        sourceLabel="Local workspace"
        summary={summary}
        scope={{ inScope: 52, vendored: 14, archived: 6, excludedPath: 4 }}
      />
    );
    const statement = screen.getByTestId('scope-statement');
    expect(statement.textContent).toContain('52 in-scope');
    expect(statement.textContent).toContain('24 excluded');
    expect(statement.textContent).toContain('14 vendored');
  });

  it('omits the scope statement when nothing is excluded — no caveat without a cause', () => {
    render(
      <PortfolioSummarySection
        sourceLabel="Local workspace"
        summary={summary}
        scope={{ inScope: 52, vendored: 0, archived: 0, excludedPath: 0 }}
      />
    );
    expect(screen.queryByTestId('scope-statement')).toBeNull();
  });
});
