// @vitest-environment jsdom
//
// Release 3.2 milestone 1 — the scan progress chip.
//
// The worker's cancel semantics are proven in the api-host smoke against a
// real delayed worker; what only a DOM test can prove is that the operator
// SEES the running scan, that Cancel calls the cancel route, that the pending
// cancel is disabled WITH its reason (3.5: a disabled control says why), and
// that silence — never-run, completed — renders nothing rather than noise.
import { describe, it, expect, vi, afterEach } from 'vitest';
import { render, screen, fireEvent, cleanup, waitFor } from '@testing-library/react';
import '@testing-library/jest-dom/vitest';
import React from 'react';
import ScanProgressChip from './ScanProgressChip';
import * as apiClient from '../services/apiClient';
import type { BackgroundScanStatus } from '../types';

vi.mock('../services/apiClient', () => ({
  getPortfolioScanStatus: vi.fn(),
  cancelPortfolioScan: vi.fn(),
}));

const mockedGet = vi.mocked(apiClient.getPortfolioScanStatus);
const mockedCancel = vi.mocked(apiClient.cancelPortfolioScan);

function status(overrides: Partial<BackgroundScanStatus> = {}): BackgroundScanStatus {
  return {
    state: 'running',
    phase: 'inventory',
    phasesDone: 0,
    phaseTotal: 4,
    reposDone: 12,
    reposTotal: 75,
    startedAt: new Date().toISOString(),
    updatedAt: new Date().toISOString(),
    processId: 4242,
    cancelRequested: false,
    error: null,
    ...overrides,
  };
}

afterEach(() => {
  cleanup();
  vi.clearAllMocks();
});

describe('ScanProgressChip', () => {
  it('shows a running scan with phase, repo progress and a cancel control', async () => {
    mockedGet.mockResolvedValue(status());
    render(<ScanProgressChip />);
    await waitFor(() => expect(screen.getByRole('status')).toHaveTextContent('Scanning — inventory (12/75 repos, phase 1/4)'));
    expect(screen.getByRole('button', { name: 'Cancel portfolio scan' })).toBeEnabled();
  });

  it('cancel calls the cancel route and disables itself with the reason', async () => {
    mockedGet.mockResolvedValue(status());
    mockedCancel.mockResolvedValue({ cancelRequested: true });
    render(<ScanProgressChip />);
    const button = await screen.findByRole('button', { name: 'Cancel portfolio scan' });
    fireEvent.click(button);
    await waitFor(() => expect(mockedCancel).toHaveBeenCalledTimes(1));
    await waitFor(() => expect(screen.getByRole('button', { name: 'Cancel portfolio scan' })).toBeDisabled());
    expect(screen.getByRole('button', { name: 'Cancel portfolio scan' })).toHaveAttribute(
      'title',
      'Cancel already requested; the scan stops at its next phase boundary.'
    );
    expect(screen.getByRole('button', { name: 'Cancel portfolio scan' })).toHaveTextContent('Cancelling…');
  });

  it('a recent cancelled outcome stays visible with what was kept', async () => {
    mockedGet.mockResolvedValue(status({ state: 'cancelled', phasesDone: 2, updatedAt: new Date().toISOString() }));
    render(<ScanProgressChip />);
    await waitFor(() => expect(screen.getByRole('status')).toHaveTextContent('Scan cancelled (2/4 phases kept)'));
  });

  it('a failed outcome carries its error in the title', async () => {
    mockedGet.mockResolvedValue(status({ state: 'failed', error: 'Status scan failed: disk on fire', updatedAt: new Date().toISOString() }));
    render(<ScanProgressChip />);
    await waitFor(() => expect(screen.getByRole('status')).toHaveTextContent('Scan failed'));
    expect(screen.getByRole('status')).toHaveAttribute('title', 'Status scan failed: disk on fire');
  });

  it('never-run and completed render nothing', async () => {
    mockedGet.mockResolvedValue(status({ state: 'never-run' }));
    const { container, unmount } = render(<ScanProgressChip />);
    await waitFor(() => expect(mockedGet).toHaveBeenCalled());
    expect(container).toBeEmptyDOMElement();
    unmount();

    mockedGet.mockResolvedValue(status({ state: 'completed', phasesDone: 4 }));
    const second = render(<ScanProgressChip />);
    await waitFor(() => expect(mockedGet).toHaveBeenCalledTimes(2));
    expect(second.container).toBeEmptyDOMElement();
  });

  it('a stale abnormal outcome (older than the note window) renders nothing', async () => {
    mockedGet.mockResolvedValue(status({ state: 'aborted', updatedAt: new Date(Date.now() - 6 * 60 * 1000).toISOString() }));
    const { container } = render(<ScanProgressChip />);
    await waitFor(() => expect(mockedGet).toHaveBeenCalled());
    expect(container).toBeEmptyDOMElement();
  });
});
