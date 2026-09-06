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
import { normalizeCopilotTaskPacket } from '../lib/copilotTaskPacket';
import type { CopilotTaskPacket } from '../types';

vi.mock('../services/apiClient', () => ({
  previewCopilotTaskPacket: vi.fn(),
  getCopilotTaskHistory: vi.fn(),
  getRunnerPresence: vi.fn(),
}));

const mockedPreview = vi.mocked(apiClient.previewCopilotTaskPacket);
const mockedHistory = vi.mocked(apiClient.getCopilotTaskHistory);
const mockedRunner = vi.mocked(apiClient.getRunnerPresence);

afterEach(() => { cleanup(); vi.clearAllMocks(); });

/** A runner reporting in — the ordinary case, where Dispatch is offered plain. */
function runnerPresent() {
  return { state: 'present', present: true, hostname: 'BENCH', user: 'ben' };
}

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
  it('dispatches the prompt the operator just read, and names the run it became', async () => {
    // Lane 0.17 — the prompt travels with the call. Rebuilding it behind the
    // operator would mean the packet they reviewed is not the one dispatched.
    mockedPreview.mockResolvedValue(packet());
    mockedHistory.mockResolvedValue([]);
    mockedRunner.mockResolvedValue(runnerPresent());
    const onDispatch = vi.fn().mockResolvedValue({ success: true, runId: 'dispatch-abc' });

    render(<CopilotTaskPreviewModal isOpen repoName="fixture-repo" onClose={vi.fn()} onDispatch={onDispatch} />);

    const button = await screen.findByRole('button', { name: /^Dispatch$/ });
    fireEvent.click(button);
    await waitFor(() =>
      expect(onDispatch).toHaveBeenCalledWith('fixture-repo', {
        prompt: 'Do the thing.',
        acknowledgeNoRunner: undefined,
      })
    );
    expect(await screen.findByText(/Queued as run dispatch-abc/)).toBeInTheDocument();
    // The action is done — it must not be offered twice.
    expect(screen.queryByRole('button', { name: /^Dispatch$/ })).not.toBeInTheDocument();
  });

  it('says the board cannot observe a dispatch that came back without a run id', async () => {
    // A success with no run id is a real outcome, not a formality: the work is
    // queued and the lane still cannot be joined to it. Claiming a clean
    // dispatch there would rebuild the blind spot this release removes.
    mockedPreview.mockResolvedValue(packet());
    mockedHistory.mockResolvedValue([]);
    mockedRunner.mockResolvedValue(runnerPresent());
    const onDispatch = vi.fn().mockResolvedValue({ success: true, runId: null });

    render(<CopilotTaskPreviewModal isOpen repoName="fixture-repo" onClose={vi.fn()} onDispatch={onDispatch} />);

    fireEvent.click(await screen.findByRole('button', { name: /^Dispatch$/ }));
    expect(await screen.findByText(/no run id came back/)).toBeInTheDocument();
    expect(screen.getByText(/cannot observe this one/)).toBeInTheDocument();
  });

  it('refuses to queue into an empty room, and offers the override that names the cost', async () => {
    mockedPreview.mockResolvedValue(packet());
    mockedHistory.mockResolvedValue([]);
    mockedRunner.mockResolvedValue({ state: 'absent', present: false, strandedCount: 3 });
    const onDispatch = vi.fn().mockResolvedValue({ success: true, runId: 'r1', queuedWithoutRunner: true });

    render(<CopilotTaskPreviewModal isOpen repoName="fixture-repo" onClose={vi.fn()} onDispatch={onDispatch} />);

    // The plain Dispatch button is gone; only the deliberate override remains.
    await waitFor(() => expect(screen.getByTestId('preview-dispatch-gate')).toBeInTheDocument());
    expect(screen.queryByRole('button', { name: /^Dispatch$/ })).not.toBeInTheDocument();
    expect(screen.getByTestId('preview-dispatch-gate')).toHaveTextContent('3 tasks already queued');

    fireEvent.click(screen.getByRole('button', { name: /Queue anyway/ }));
    await waitFor(() =>
      expect(onDispatch).toHaveBeenCalledWith('fixture-repo', {
        prompt: 'Do the thing.',
        acknowledgeNoRunner: true,
      })
    );
    expect(await screen.findByText(/stays queued until you start one/)).toBeInTheDocument();
  });

  it('a queued run whose lane refused still reports success — the work is moving either way', async () => {
    // Reporting failure here would tell the operator nothing happened while an
    // agent was already working. The dispatch and the lane are two outcomes.
    mockedPreview.mockResolvedValue(packet());
    mockedHistory.mockResolvedValue([]);
    mockedRunner.mockResolvedValue(runnerPresent());
    const onDispatch = vi.fn().mockResolvedValue({
      success: true,
      runId: 'dispatch-xyz',
      laneWarning: 'Queued, but no lane was occupied: Both execution lanes are occupied.',
    });

    render(<CopilotTaskPreviewModal isOpen repoName="fixture-repo" onClose={vi.fn()} onDispatch={onDispatch} />);

    fireEvent.click(await screen.findByRole('button', { name: /^Dispatch$/ }));
    expect(await screen.findByText(/Queued as run dispatch-xyz/)).toBeInTheDocument();
    expect(screen.getByText(/Both execution lanes are occupied/)).toBeInTheDocument();
    // Not an error: no alert role, because nothing failed.
    expect(screen.queryByRole('alert')).not.toBeInTheDocument();
  });

  it('renders the backend refusal inline when dispatch fails', async () => {
    mockedPreview.mockResolvedValue(packet());
    mockedHistory.mockResolvedValue([]);
    mockedRunner.mockResolvedValue(runnerPresent());
    const onDispatch = vi.fn().mockResolvedValue({ success: false, error: 'Both lane slots are occupied' });

    render(<CopilotTaskPreviewModal isOpen repoName="fixture-repo" onClose={vi.fn()} onDispatch={onDispatch} />);

    fireEvent.click(await screen.findByRole('button', { name: /^Dispatch$/ }));
    expect(await screen.findByRole('alert')).toHaveTextContent('Both lane slots are occupied');
  });

  it('offers no dispatch action without a callback — preview-only contexts stay preview-only', async () => {
    mockedPreview.mockResolvedValue(packet());
    mockedHistory.mockResolvedValue([]);

    render(<CopilotTaskPreviewModal isOpen repoName="fixture-repo" onClose={vi.fn()} />);

    await screen.findByText('Ship the widget');
    expect(screen.queryByRole('button', { name: /^Dispatch$/ })).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /Queue anyway/ })).not.toBeInTheDocument();
    // A preview-only caller must not even read runner presence: nothing here
    // can queue work, so there is no gate to evaluate.
    expect(mockedRunner).not.toHaveBeenCalled();
  });

  it('shows the roadmap-scan hint only for roadmap errors', async () => {
    mockedPreview.mockRejectedValue(new Error("Roadmap file not found for repo 'fixture-repo'."));
    mockedHistory.mockResolvedValue([]);

    render(<CopilotTaskPreviewModal isOpen repoName="fixture-repo" onClose={vi.fn()} />);

    expect(await screen.findByText('Failed to build task packet')).toBeInTheDocument();
    expect(screen.getByText(/Ensure a roadmap scan has been run/)).toBeInTheDocument();
  });

  it('renders a sparse packet the way the live backend actually sent one — null arrays, no crash', async () => {
    // Lane 0.17 follow-up — the live service serialized empty arrays as JSON
    // null (valueContext.rationale in the field); the normalizer at the API
    // edge is what stands between that payload and a portal-wide crash.
    const rawSparse = {
      packetVersion: '1.0',
      runId: 'run-field-1',
      createdAt: '2026-08-31T00:00:00Z',
      repoContext: { repoName: 'test-nextgs', roadmapPath: 'F:\\repos\\test-nextgs\\ROADMAP.md' },
      readmeContext: { summary: null, headings: null, hasSetupGuidance: false, hasUsageGuidance: false, hasArchitectureGuidance: false },
      roadmapContext: { releaseGoal: null, pendingMilestones: null, completedMilestones: null, acceptanceCriteria: null, outOfScope: null },
      selectedRoadmapItem: { text: 'Store an API key in Settings', section: 'Release 1.0', tags: null },
      followUpCandidates: null,
      docFindings: null,
      valueContext: { topValueItemText: null, valueTier: null, selectedBy: 'roadmap-order', selectedIsTopValueItem: false, rationale: null },
      constraints: null,
      acceptanceCriteria: null,
      guardrails: null,
      generatedPrompt: 'Do the thing.',
    };
    mockedPreview.mockResolvedValue(normalizeCopilotTaskPacket(rawSparse));
    mockedHistory.mockResolvedValue([]);

    render(<CopilotTaskPreviewModal isOpen repoName="test-nextgs" onClose={vi.fn()} />);

    expect(await screen.findByText('Store an API key in Settings')).toBeInTheDocument();
    expect(screen.getByText(/Acceptance Criteria/)).toBeInTheDocument();
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
