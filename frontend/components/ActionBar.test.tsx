// @vitest-environment jsdom
//
// DOM tests for the implicit-bulk confirmation flow (ROADMAP Lane 0.8).
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

describe('ActionBar implicit-bulk confirmation', () => {
  it('confirms before an implicit-scope Pull and names the count', () => {
    const confirm = vi.spyOn(window, 'confirm').mockReturnValue(true);
    const { onAction } = renderActionBar();
    fireEvent.click(screen.getByRole('button', { name: 'Pull' }));
    expect(confirm).toHaveBeenCalledTimes(1);
    expect(confirm.mock.calls[0][0]).toContain('git pull');
    expect(confirm.mock.calls[0][0]).toContain('75 repositories');
    expect(onAction).toHaveBeenCalledWith('update', undefined);
  });

  // The half that pure-logic tests cannot see: a dismissed dialog must stop
  // the action, not merely have been shown.
  it('does NOT run the action when the operator cancels', () => {
    vi.spyOn(window, 'confirm').mockReturnValue(false);
    const { onAction } = renderActionBar();
    fireEvent.click(screen.getByRole('button', { name: 'Pull' }));
    fireEvent.click(screen.getByRole('button', { name: 'Fetch' }));
    expect(onAction).not.toHaveBeenCalled();
  });

  it('skips the dialog when the operator selected repos explicitly', () => {
    const confirm = vi.spyOn(window, 'confirm').mockReturnValue(false);
    const { onAction } = renderActionBar({ selectedRepos: new Set(['repo-a', 'repo-b']) });
    fireEvent.click(screen.getByRole('button', { name: 'Pull' }));
    expect(confirm).not.toHaveBeenCalled();
    expect(onAction).toHaveBeenCalledWith('update', ['repo-a', 'repo-b']);
  });

  // Settled 2026-08-10: read-only stays one click, however large the scope.
  it('runs the read-only Report without a dialog', () => {
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
