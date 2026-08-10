// @vitest-environment jsdom
//
// DOM tests for the tab strip (ROADMAP Lane 0.8). lib/viewTabs.test.ts proves
// the class/badge helpers; these prove the strip renders every VIEW_META tab,
// selection actually fires, and the per-view subtitle tracks the active view —
// the operator-visible contract the Lane 0.5 inversion violated.
import { describe, it, expect, vi, afterEach } from 'vitest';
import { render, screen, fireEvent, cleanup } from '@testing-library/react';
import '@testing-library/jest-dom/vitest';
import React from 'react';
import DashboardViewTabs from './DashboardViewTabs';
import { VIEW_META } from '../viewMeta';

afterEach(cleanup);

describe('DashboardViewTabs', () => {
  it('renders one tab per VIEW_META entry — no view is unreachable', () => {
    render(<DashboardViewTabs activeView="repos" onSelectView={() => {}} />);
    for (const { label } of VIEW_META) {
      expect(screen.getByRole('button', { name: label })).toBeInTheDocument();
    }
  });

  it('fires onSelectView with the clicked view key', () => {
    const onSelectView = vi.fn();
    render(<DashboardViewTabs activeView="repos" onSelectView={onSelectView} />);
    fireEvent.click(screen.getByRole('button', { name: 'Insights' }));
    expect(onSelectView).toHaveBeenCalledWith('insights');
  });

  it('shows the subtitle for the ACTIVE view, so operators self-orient', () => {
    render(<DashboardViewTabs activeView="insights" onSelectView={() => {}} />);
    expect(screen.getByTestId('view-subtitle').textContent).toContain('Read-only analytics');
  });

  it('renders a badge only for tabs that declare one', () => {
    render(
      <DashboardViewTabs
        activeView="repos"
        onSelectView={() => {}}
        badges={{ 'work-queue': { count: 4 } }}
      />
    );
    expect(screen.getByTestId('work-queue-tab-badge')).toHaveTextContent('4');
    expect(screen.queryByTestId('insights-tab-badge')).not.toBeInTheDocument();
  });
});
