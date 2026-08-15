// @vitest-environment jsdom
//
// DOM tests for the bulk-scope rules (Lane 0.8, reworked by Release 3.5 M7).
// lib/bulkScope.test.ts proves the RULE; these prove the WIRING — that the
// component actually consults the rule, shows the dialog, and that "Cancel"
// really stops the action. A component that never calls the guard passes every
// pure-logic test and still runs bulk git across 75 working trees.
import { describe, it, expect, vi, afterEach } from 'vitest';
import { render, screen, fireEvent, cleanup } from '@testing-library/react';
import '@testing-library/jest-dom/vitest';
import React from 'react';
import ActionBar from './ActionBar';

afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
});

function renderActionBar(overrides: Partial<React.ComponentProps<typeof ActionBar>> = {}) {
  const handlers = {
    onAction: vi.fn(),
    onExport: vi.fn(),
    onRefresh: vi.fn(),
    onInitClick: vi.fn(),
    onDocReviewClick: vi.fn(),
    onApiDocsClick: vi.fn(),
    onHelpClick: vi.fn(),
  };
  render(
    <ActionBar
      {...handlers}
      isActionRunning={false}
      currentOperation={null}
      settings={null}
      selectedRepos={new Set<string>()}
      repoCount={75}
      {...overrides}
    />
  );
  return handlers;
}

describe('ActionBar bulk scope (Release 3.5 milestone 7)', () => {
  // Supersedes the Lane 0.5 confirm dialog: a mutating bulk action with no
  // selection is DISABLED, not confirmed. A confirm without a selection is
  // the dialog people learn to click through, and the review called the old
  // default the footgun it was.
  it('disables Pull and Fetch with nothing selected, and no dialog appears', () => {
    const confirm = vi.spyOn(window, 'confirm').mockReturnValue(true);
    const { onAction } = renderActionBar();
    const pull = screen.getByRole('button', { name: 'Pull' });
    const fetch = screen.getByRole('button', { name: 'Fetch' });
    expect(pull).toBeDisabled();
    expect(fetch).toBeDisabled();
    fireEvent.click(pull);
    fireEvent.click(fetch);
    expect(confirm).not.toHaveBeenCalled();
    expect(onAction).not.toHaveBeenCalled();
  });

  it('the disabled mutating action names its precondition (select first)', () => {
    renderActionBar();
    const pull = screen.getByRole('button', { name: 'Pull' });
    expect(pull).toHaveAttribute('title', expect.stringContaining('Select repositories first'));
  });

  it('runs immediately on an explicit selection, no dialog', () => {
    const confirm = vi.spyOn(window, 'confirm').mockReturnValue(false);
    const { onAction } = renderActionBar({ selectedRepos: new Set(['repo-a', 'repo-b']) });
    fireEvent.click(screen.getByRole('button', { name: 'Pull' }));
    expect(confirm).not.toHaveBeenCalled();
    expect(onAction).toHaveBeenCalledWith('update', ['repo-a', 'repo-b']);
  });

  // Settled 2026-08-10 and unchanged: read-only stays one click over the
  // whole filter, however large - a report over everything is the point.
  it('runs the read-only Report without a dialog or a selection', () => {
    const confirm = vi.spyOn(window, 'confirm').mockReturnValue(false);
    const { onExport } = renderActionBar({ repoCount: 999 });
    fireEvent.click(screen.getByRole('button', { name: 'Report' }));
    expect(confirm).not.toHaveBeenCalled();
    expect(onExport).toHaveBeenCalledTimes(1);
  });

  it('disables repo actions and names the blocker when nothing is in scope', () => {
    const { onAction } = renderActionBar({ repoCount: 0 });
    const pull = screen.getByRole('button', { name: 'Pull' });
    expect(pull).toBeDisabled();
    fireEvent.click(pull);
    expect(onAction).not.toHaveBeenCalled();
    expect(screen.getByTestId('no-repos-hint')).toBeInTheDocument();
  });

  it('names the missing workspace root instead of the generic remedy', () => {
    renderActionBar({ repoCount: 0, missingRoots: ['F:\\Development\\20_Staging'] });
    expect(screen.getByTestId('no-repos-hint').textContent).toContain('F:\\Development\\20_Staging');
  });
});
