// @vitest-environment jsdom
//
// Release 3.4 milestone 1, step 10 — DOM tests for the default-branch sync
// control.
//
// The module's own decision matrix is asserted in the PowerShell module smoke,
// and the route contract in ApiHost.Contract.Tests.ps1. What neither can prove
// is the thing that was actually missing for a whole release: that a control
// exists, calls the operation, and renders a REFUSAL as readable information
// instead of swallowing it. A component that renders only the success path
// passes every backend test and still leaves the operator staring at a button
// that appears to do nothing.
import { describe, it, expect, vi, afterEach } from 'vitest';
import { render, screen, fireEvent, cleanup, waitFor } from '@testing-library/react';
import '@testing-library/jest-dom/vitest';
import React from 'react';
import DefaultBranchSyncButton from './DefaultBranchSyncButton';
import * as apiClient from '../services/apiClient';

afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
});

function result(overrides: Partial<apiClient.DefaultBranchSyncResult> = {}): apiClient.DefaultBranchSyncResult {
  return {
    synced: false,
    refused: false,
    category: '',
    reason: '',
    remedy: '',
    state: 'current',
    branch: 'main',
    remote: 'origin',
    fromSha: 'aaa',
    toSha: 'aaa',
    repoPath: 'C:/repo',
    ...overrides,
  };
}

describe('DefaultBranchSyncButton', () => {
  it('approves the transition explicitly rather than letting the route default it', async () => {
    const spy = vi.spyOn(apiClient, 'syncDefaultBranch').mockResolvedValue(result({ synced: true }));
    render(<DefaultBranchSyncButton repoName="demo" />);

    fireEvent.click(screen.getByTestId('sync-default-branch'));

    // Clicking IS the approval. If this ever passes `false` the operation
    // refuses as `approval-required` and the button silently does nothing.
    await waitFor(() => expect(spy).toHaveBeenCalledWith({ repoName: 'demo', repoPath: undefined }, true));
  });

  it('renders a refusal with its category and remedy instead of hiding it', async () => {
    vi.spyOn(apiClient, 'syncDefaultBranch').mockResolvedValue(result({
      refused: true,
      category: 'default-branch-ahead',
      reason: 'This clone is 2 commits ahead of origin/main.',
      remedy: 'Open a pull request for those commits.',
      state: 'ahead',
    }));
    render(<DefaultBranchSyncButton repoName="demo" />);

    fireEvent.click(screen.getByTestId('sync-default-branch'));

    const refusal = await screen.findByTestId('sync-refused');
    // The category is in the text, not only in the colour — status must not be
    // conveyed by colour alone.
    expect(refusal).toHaveTextContent('default-branch-ahead');
    expect(refusal).toHaveTextContent('2 commits ahead');
    expect(refusal).toHaveTextContent('Open a pull request');
  });

  it('does not report a move when nothing moved', async () => {
    // `current` is a success, not a refusal — but the branch did not move, so a
    // caller must not be told to reload as though it had.
    const onSynced = vi.fn();
    vi.spyOn(apiClient, 'syncDefaultBranch').mockResolvedValue(result({
      synced: true,
      reason: 'Already at origin/main.',
      fromSha: 'same',
      toSha: 'same',
    }));
    render(<DefaultBranchSyncButton repoName="demo" onSynced={onSynced} />);

    fireEvent.click(screen.getByTestId('sync-default-branch'));

    await screen.findByTestId('sync-ok');
    expect(onSynced).not.toHaveBeenCalled();
  });

  it('reports a move when the branch actually advanced', async () => {
    const onSynced = vi.fn();
    vi.spyOn(apiClient, 'syncDefaultBranch').mockResolvedValue(result({
      synced: true,
      fromSha: 'old',
      toSha: 'new',
      state: 'behind',
      reason: 'Fast-forwarded main to origin/main.',
    }));
    render(<DefaultBranchSyncButton repoName="demo" onSynced={onSynced} />);

    fireEvent.click(screen.getByTestId('sync-default-branch'));

    await waitFor(() => expect(onSynced).toHaveBeenCalledTimes(1));
  });

  it('surfaces a transport failure rather than reading it as a refusal', async () => {
    vi.spyOn(apiClient, 'syncDefaultBranch').mockRejectedValue(new Error('Failed to fetch'));
    render(<DefaultBranchSyncButton repoName="demo" />);

    fireEvent.click(screen.getByTestId('sync-default-branch'));

    expect(await screen.findByTestId('sync-error')).toHaveTextContent('Failed to fetch');
    expect(screen.queryByTestId('sync-refused')).toBeNull();
  });

  it('disables itself and names the reason when there is no repo', () => {
    render(<DefaultBranchSyncButton />);
    const button = screen.getByTestId('sync-default-branch');

    expect(button).toBeDisabled();
    // Release 3.1 guardrail: a disabled control states its unmet precondition.
    expect(button).toHaveAttribute('title', expect.stringContaining('nothing to sync'));
  });
});
