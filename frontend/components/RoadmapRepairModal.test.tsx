// @vitest-environment jsdom
//
// Proof of value (2026-10-16) — the repair modal reaches GitHub, and every
// answer the operator gives is recorded with the time it took.
//
// The failures these prevent: a "PR" button that could only ever build a
// dry-run plan because the modal never sent the proposal; a PR opened with the
// generated text after the operator edited it; and a rejection recorded with no
// reason, which teaches the product nothing.
import { afterEach, describe, expect, it, vi } from 'vitest';
import { cleanup, render, screen, fireEvent, waitFor } from '@testing-library/react';
import '@testing-library/jest-dom/vitest';
import React from 'react';
import RoadmapRepairModal, { formatReviewSeconds } from './RoadmapRepairModal';
import * as apiClient from '../services/apiClient';
import type { RoadmapRepairPreview } from '../types';

vi.mock('../services/apiClient', () => ({
  previewRoadmapRepair: vi.fn(),
  applyRoadmapRepair: vi.fn(),
  getRoadmapRepairHistory: vi.fn(),
  submitRoadmapRepairPr: vi.fn(),
  recordDeliveryDecision: vi.fn(),
}));

const mockedPreview = vi.mocked(apiClient.previewRoadmapRepair);
const mockedSubmit = vi.mocked(apiClient.submitRoadmapRepairPr);
const mockedDecision = vi.mocked(apiClient.recordDeliveryDecision);

afterEach(() => { cleanup(); vi.clearAllMocks(); });

function readyPreview(): RoadmapRepairPreview {
  return {
    previewId: 'preview-1',
    repoName: 'fixture-repo',
    roadmapPath: 'F:\\repos\\fixture-repo\\ROADMAP.md',
    previewState: 'repair-preview-ready',
    originalMaturityLevel: 'L2-Structured',
    completedItemCount: 3,
    pendingItemCount: 2,
    repairActions: [{ actionId: 'a1', severity: 'warning', description: 'Add a goal', affectsSection: 'Release 1' }],
    currentContent: '# Roadmap\n',
    proposedContent: '# Roadmap\n\n## Release 1\n',
    blockReason: null,
  } as unknown as RoadmapRepairPreview;
}

function dryRun() {
  return {
    dryRun: true,
    created: false,
    prUrl: null,
    plan: { repoName: 'fixture-repo', previewId: 'preview-1', branch: 'roadmap-repair/x', baseBranch: 'main', title: 't', body: 'b' },
    note: 'dry-run',
    baseFreshness: null,
  };
}

async function openReady() {
  mockedPreview.mockResolvedValue(readyPreview());
  render(<RoadmapRepairModal isOpen repoName="fixture-repo" onClose={() => {}} />);
  await screen.findByText(/Repair preview is ready/);
}

describe('RoadmapRepairModal — the live PR and the recorded decision', () => {
  it('offers the live PR only after the dry-run plan has been seen', async () => {
    await openReady();
    const open = screen.getByTestId('repair-open-pr');
    expect(open).toBeDisabled();
    expect(open).toHaveAttribute('title', expect.stringMatching(/Preview the PR plan first/));
  });

  it('opens the PR with the operator-edited text, createPr, and the measured review time', async () => {
    await openReady();
    mockedSubmit.mockResolvedValueOnce(dryRun());
    fireEvent.click(screen.getByText('Preview repair PR'));
    await waitFor(() => expect(screen.getByTestId('repair-open-pr')).not.toBeDisabled());

    // The operator edits the proposal in the Diff tab before approving it.
    fireEvent.click(screen.getByText('Diff Preview'));
    const editor = screen.getByRole('textbox');
    fireEvent.change(editor, { target: { value: '# Roadmap\n\n## Release 1 - edited\n' } });
    fireEvent.click(screen.getByText('Repair Plan'));

    mockedSubmit.mockResolvedValueOnce({ ...dryRun(), dryRun: false, created: true, prUrl: 'https://github.com/o/fixture-repo/pull/7', decisionId: 'd1' });
    fireEvent.click(screen.getByTestId('repair-open-pr'));
    fireEvent.click(screen.getByTestId('repair-open-pr-submit'));

    await screen.findByTestId('repair-pr-opened');
    const live = mockedSubmit.mock.calls[1];
    expect(live[0]).toBe('fixture-repo');
    expect(live[1]).toBe('preview-1');
    expect(live[2]).toBe(true);
    expect(live[3]).toMatchObject({
      proposedContent: '# Roadmap\n\n## Release 1 - edited\n',
      roadmapPath: 'F:\\repos\\fixture-repo\\ROADMAP.md',
      edited: true,
      operatorSecondsBasis: 'measured-in-console',
      proposal: { previewState: 'repair-preview-ready', originalMaturityLevel: 'L2-Structured', repairActionCount: 1 },
    });
    expect(typeof live[3]?.operatorSeconds).toBe('number');
    expect(screen.getByRole('link', { name: 'https://github.com/o/fixture-repo/pull/7' })).toBeInTheDocument();
    // A decision is final in this modal: no second PR, no reject after accept.
    expect(screen.queryByTestId('repair-open-pr')).not.toBeInTheDocument();
    expect(screen.queryByTestId('repair-reject')).not.toBeInTheDocument();
  });

  it('shows the server refusal instead of a success when the live PR is refused', async () => {
    await openReady();
    mockedSubmit.mockResolvedValueOnce(dryRun());
    fireEvent.click(screen.getByText('Preview repair PR'));
    await waitFor(() => expect(screen.getByTestId('repair-open-pr')).not.toBeDisabled());
    mockedSubmit.mockRejectedValueOnce(new Error('The working tree has uncommitted changes.'));
    fireEvent.click(screen.getByTestId('repair-open-pr'));
    fireEvent.click(screen.getByTestId('repair-open-pr-submit'));
    expect(await screen.findByTestId('repair-open-pr-error')).toHaveTextContent('uncommitted changes');
    expect(screen.queryByTestId('repair-pr-opened')).not.toBeInTheDocument();
  });

  it('requires a reason to reject, and records the rejection with its review time', async () => {
    await openReady();
    fireEvent.click(screen.getByTestId('repair-reject'));
    const submit = screen.getByTestId('repair-reject-submit');
    expect(submit).toBeDisabled();
    expect(submit).toHaveAttribute('title', expect.stringMatching(/needs a reason/));

    mockedDecision.mockResolvedValueOnce({ decisionId: 'd2' });
    fireEvent.change(screen.getByLabelText(/not worth a pull request/), { target: { value: 'drops every phase' } });
    fireEvent.click(screen.getByTestId('repair-reject-submit'));
    await screen.findByTestId('repair-rejected');
    expect(mockedDecision).toHaveBeenCalledWith(expect.objectContaining({
      repoName: 'fixture-repo',
      decision: 'reject',
      previewId: 'preview-1',
      reason: 'drops every phase',
      operatorSecondsBasis: 'measured-in-console',
    }));
    expect(mockedSubmit).not.toHaveBeenCalled();
  });

  it('formats review time the way an operator reads it', () => {
    expect(formatReviewSeconds(0)).toBe('0s');
    expect(formatReviewSeconds(59)).toBe('59s');
    expect(formatReviewSeconds(192)).toBe('3m 12s');
  });
});
