// @vitest-environment jsdom
//
// Lane 0.17 — the preview modal is the confirm step of dispatch, and its
// error hints must match the failure.
//
// The failures these prevent: a "Dispatch" flow that dead-ends at Copy/Close
// with the lane assignment unreachable; and a network failure captioned with
// "run a roadmap scan" — a remedy that cannot fix it.
import { afterEach, describe, expect, it, vi } from 'vitest';
import { cleanup, render, screen, fireEvent, waitFor } from '@testing-library/react';
import '@testing-library/jest-dom/vitest';
import React from 'react';
import CopilotTaskPreviewModal from './CopilotTaskPreviewModal';
import * as apiClient from '../services/apiClient';
import type { CopilotTaskPacket } from '../types';

vi.mock('../services/apiClient', () => ({
  previewCopilotTaskPacket: vi.fn(),
  getCopilotTaskHistory: vi.fn(),
}));

const mockedPreview = vi.mocked(apiClient.previewCopilotTaskPacket);
const mockedHistory = vi.mocked(apiClient.getCopilotTaskHistory);

afterEach(() => { cleanup(); vi.clearAllMocks(); });

function packet(): CopilotTaskPacket {
  return {
    packetVersion: '1.0',
    runId: 'run-123',
    createdAt: '2026-08-30T12:00:00Z',
    repoContext: { repoName: 'fixture-repo', roadmapPath: 'F:\\repos\\fixture-repo\\ROADMAP.md' },
    readmeContext: { summary: '', headings: [], hasSetupGuidance: false, hasUsageGuidance: false, hasArchitectureGuidance: false },
    roadmapContext: { releaseGoal: '', pendingMilestones: [], completedMilestones: [], acceptanceCriteria: [], outOfScope: [] },
    selectedRoadmapItem: { text: 'Ship the widget', section: 'Release 1.0' },
    followUpCandidates: [],
    docFindings: [],
    valueContext: { selectedBy: 'roadmap-order', selectedIsTopValueItem: false, rationale: [] },
    constraints: [],
    acceptanceCriteria: ['It works'],
    guardrails: [{ rule: 'No force-push' }],
    generatedPrompt: 'Do the thing.',
  };
}

describe('CopilotTaskPreviewModal — dispatch action and honest error hints', () => {
  it('offers "Dispatch to Lane" when a dispatch callback is provided and the packet loads', async () => {
    mockedPreview.mockResolvedValue(packet());
    mockedHistory.mockResolvedValue([]);
    const onDispatch = vi.fn().mockResolvedValue({ success: true });

    render(<CopilotTaskPreviewModal isOpen repoName="fixture-repo" onClose={vi.fn()} onDispatch={onDispatch} />);

    const button = await screen.findByRole('button', { name: /Dispatch to Lane/ });
    fireEvent.click(button);
    await waitFor(() => expect(onDispatch).toHaveBeenCalledWith('fixture-repo'));
    expect(await screen.findByText(/Dispatched to a lane/)).toBeInTheDocument();
    // The action is done — it must not be offered twice.
    expect(screen.queryByRole('button', { name: /Dispatch to Lane/ })).not.toBeInTheDocument();
  });

  it('renders the backend refusal inline when dispatch fails', async () => {
    mockedPreview.mockResolvedValue(packet());
    mockedHistory.mockResolvedValue([]);
    const onDispatch = vi.fn().mockResolvedValue({ success: false, error: 'Both lane slots are occupied' });

    render(<CopilotTaskPreviewModal isOpen repoName="fixture-repo" onClose={vi.fn()} onDispatch={onDispatch} />);

    fireEvent.click(await screen.findByRole('button', { name: /Dispatch to Lane/ }));
    expect(await screen.findByRole('alert')).toHaveTextContent('Both lane slots are occupied');
  });

  it('offers no dispatch action without a callback — preview-only contexts stay preview-only', async () => {
    mockedPreview.mockResolvedValue(packet());
    mockedHistory.mockResolvedValue([]);

    render(<CopilotTaskPreviewModal isOpen repoName="fixture-repo" onClose={vi.fn()} />);

    await screen.findByText('Ship the widget');
    expect(screen.queryByRole('button', { name: /Dispatch to Lane/ })).not.toBeInTheDocument();
  });

  it('shows the roadmap-scan hint only for roadmap errors', async () => {
    mockedPreview.mockRejectedValue(new Error("Roadmap file not found for repo 'fixture-repo'."));
    mockedHistory.mockResolvedValue([]);

    render(<CopilotTaskPreviewModal isOpen repoName="fixture-repo" onClose={vi.fn()} />);

    expect(await screen.findByText('Failed to build task packet')).toBeInTheDocument();
    expect(screen.getByText(/Ensure a roadmap scan has been run/)).toBeInTheDocument();
  });

  it('a network failure gets a connectivity hint, never "run a roadmap scan"', async () => {
    mockedPreview.mockRejectedValue(new TypeError('Failed to fetch'));
    mockedHistory.mockResolvedValue([]);

    render(<CopilotTaskPreviewModal isOpen repoName="fixture-repo" onClose={vi.fn()} />);

    expect(await screen.findByText('Failed to build task packet')).toBeInTheDocument();
    expect(screen.queryByText(/Ensure a roadmap scan has been run/)).not.toBeInTheDocument();
    expect(screen.getByText(/check that the portal is reachable/)).toBeInTheDocument();
  });
});
