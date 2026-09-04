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
  // Lane 0.15 — "never render 'not computed' as a number". In GitHub mode the
  // backend hardcodes status 'clean' and uncommittedChanges 0 (a remote repo
  // has no checkout), so this tile counted a confident 0 and the operator read
  // "nothing is dirty" where the truth was "not observable here".
  it('renders an unmeasurable count as unavailable, never as zero', () => {
    render(
      <PortfolioSummarySection
        sourceLabel="GitHub API: xfaith4"
        summary={{ ...summary, dirty: null }}
      />
    );
    const card = screen.getByTestId('summary-dirty-repositories');
    expect(card).toHaveAttribute('data-unavailable', 'true');
    expect(card.querySelector('p')?.textContent?.trim()).toBe('—');
    expect(card.textContent).toContain('Needs a local checkout');
  });

  it('still renders a real zero as zero when the source can measure it', () => {
    render(
      <PortfolioSummarySection
        sourceLabel="Local workspace"
        summary={{ ...summary, dirty: 0 }}
      />
    );
    const card = screen.getByTestId('summary-dirty-repositories');
    expect(card).not.toHaveAttribute('data-unavailable');
    expect(card.querySelector('p')?.textContent?.trim()).toBe('0');
    expect(card.textContent).not.toContain('Needs a local checkout');
  });

  // Tripwire: whatever the tile row grows to, a null must never reach the
  // operator as a digit. This asserts the rule over every rendered card rather
  // than over the one tile the audit happened to name.
  it('no tile in the row paints a number for a null count', () => {
    const allNull = { total: 52, needsAttention: 4, dirty: null, stale: 7, commitsThisWeek: 12 };
    const { container } = render(
      <PortfolioSummarySection sourceLabel="GitHub API: xfaith4" summary={allNull} />
    );
    const cards = Array.from(container.querySelectorAll('[data-testid^="summary-"]'));
    expect(cards.length).toBeGreaterThanOrEqual(5);
    for (const card of cards) {
      const rendered = card.querySelector('p')?.textContent?.trim() ?? '';
      if (card.getAttribute('data-unavailable') === 'true') {
        // An unavailable tile shows an em dash where the count would go.
        expect(rendered).toBe('—');
      } else {
        expect(rendered).not.toBe('—');
      }
    }
    expect(cards.filter(c => c.getAttribute('data-unavailable') === 'true')).toHaveLength(1);
  });

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
