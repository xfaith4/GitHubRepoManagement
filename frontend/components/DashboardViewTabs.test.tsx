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
      expect(screen.getByRole('tab', { name: label })).toBeInTheDocument();
    }
  });

  it('fires onSelectView with the clicked view key', () => {
    const onSelectView = vi.fn();
    render(<DashboardViewTabs activeView="repos" onSelectView={onSelectView} />);
    fireEvent.click(screen.getByRole('tab', { name: 'Insights' }));
    expect(onSelectView).toHaveBeenCalledWith('insights');
  });

  it('shows the subtitle for the ACTIVE view, so operators self-orient', () => {
    render(<DashboardViewTabs activeView="insights" onSelectView={() => {}} />);
    expect(screen.getByTestId('view-subtitle').textContent).toContain('Read-only analytics');
  });

  // Audit follow-up: the strip is a real tablist, so the seven views cost one
  // Tab stop instead of seven, and arrows move between them.
  it('exposes a labelled tablist with exactly one tab in the Tab order', () => {
    render(<DashboardViewTabs activeView="repos" onSelectView={() => {}} />);
    expect(screen.getByRole('tablist', { name: 'Views' })).toBeInTheDocument();
    const reachable = screen.getAllByRole('tab').filter(tab => tab.getAttribute('tabindex') === '0');
    expect(reachable).toHaveLength(1);
    expect(reachable[0]).toHaveAttribute('aria-selected', 'true');
  });

  it('points each tab at the panel it controls', () => {
    render(<DashboardViewTabs activeView="repos" onSelectView={() => {}} />);
    const tab = screen.getByRole('tab', { name: 'Insights' });
    expect(tab).toHaveAttribute('id', 'view-tab-insights');
    expect(tab).toHaveAttribute('aria-controls', 'view-panel-insights');
  });

  it('moves focus with arrows without switching the view', () => {
    const onSelectView = vi.fn();
    render(<DashboardViewTabs activeView={VIEW_META[0].key} onSelectView={onSelectView} />);
    const tablist = screen.getByRole('tablist');

    fireEvent.keyDown(tablist, { key: 'ArrowRight' });

    // Focus moved to the next tab; the view did NOT change, because switching
    // a view here starts work and arrowing past a tab must not trigger it.
    expect(screen.getByRole('tab', { name: VIEW_META[1].label })).toHaveFocus();
    expect(onSelectView).not.toHaveBeenCalled();
  });

  it('activates the focused tab on Enter', () => {
    const onSelectView = vi.fn();
    render(<DashboardViewTabs activeView={VIEW_META[0].key} onSelectView={onSelectView} />);
    const tablist = screen.getByRole('tablist');

    fireEvent.keyDown(tablist, { key: 'ArrowRight' });
    fireEvent.keyDown(tablist, { key: 'Enter' });

    expect(onSelectView).toHaveBeenCalledWith(VIEW_META[1].key);
  });

  it('wraps at both ends so the strip has no dead edge', () => {
    render(<DashboardViewTabs activeView={VIEW_META[0].key} onSelectView={() => {}} />);
    const tablist = screen.getByRole('tablist');
    const last = VIEW_META[VIEW_META.length - 1];

    fireEvent.keyDown(tablist, { key: 'ArrowLeft' });
    expect(screen.getByRole('tab', { name: last.label })).toHaveFocus();

    fireEvent.keyDown(tablist, { key: 'ArrowRight' });
    expect(screen.getByRole('tab', { name: VIEW_META[0].label })).toHaveFocus();
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
