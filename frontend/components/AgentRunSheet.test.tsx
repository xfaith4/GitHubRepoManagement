// @vitest-environment jsdom
//
// Release 2.9 — the tap-through agent-run list.
//
// The indicator has said "3 agent runs" since Release 2.5 while the answer to
// "which three?" lived only in a hover title. These assert the answer is now
// reachable by activation, that it says what each run IS rather than just
// counting them, and that an empty list explains itself instead of rendering
// a blank panel that reads as broken.
import { describe, it, expect, vi, afterEach } from 'vitest';
import { render, screen, fireEvent, cleanup, waitFor } from '@testing-library/react';
import '@testing-library/jest-dom/vitest';
import React from 'react';
import AgentRunSheet from './AgentRunSheet';
import AgentActivityIndicator from './AgentActivityIndicator';
import * as apiClient from '../services/apiClient';
import type { AgentRun } from '../types';

vi.mock('../services/apiClient', () => ({ getAgentRuns: vi.fn() }));
const mockedGetAgentRuns = vi.mocked(apiClient.getAgentRuns);

function run(overrides: Partial<AgentRun> = {}): AgentRun {
  return {
    runId: 'run-1',
    repoName: 'INcendiary',
    providerTool: 'claude',
    status: 'active',
    branch: 'roadmap-item/add-ci-validation',
    selectedTaskText: 'Add CI validation for 21_event-history.yaml',
    prUrl: 'https://github.com/xfaith4/INcendiary/pull/7',
    prNumber: 7,
    createdAt: '2026-08-18T22:20:00Z',
    updatedAt: '2026-08-18T22:40:00Z',
    ...overrides,
  } as AgentRun;
}

afterEach(() => { cleanup(); vi.clearAllMocks(); });

describe('AgentRunSheet', () => {
  it('names each run: repository, state, task and a way to the PR', async () => {
    mockedGetAgentRuns.mockResolvedValue({ items: [run()] } as never);
    render(<AgentRunSheet onClose={vi.fn()} />);

    expect(await screen.findByText('INcendiary')).toBeInTheDocument();
    expect(screen.getByText('active')).toBeInTheDocument();
    expect(screen.getByText('Add CI validation for 21_event-history.yaml')).toBeInTheDocument();
    const prLink = screen.getByRole('button', { name: 'PR #7' });
    expect(prLink).toHaveAttribute('href', 'https://github.com/xfaith4/INcendiary/pull/7');
    // A link that opens a new tab must not hand the opener over with it.
    expect(prLink).toHaveAttribute('rel', expect.stringContaining('noopener'));
  });

  it('an empty list says what it means and what would change it', async () => {
    mockedGetAgentRuns.mockResolvedValue({ items: [] } as never);
    render(<AgentRunSheet onClose={vi.fn()} />);
    const empty = await screen.findByTestId('agent-run-sheet-empty');
    expect(empty).toHaveTextContent('No agent runs recorded yet');
    expect(empty).toHaveTextContent('Dispatch a packaged roadmap item');
  });

  it('a load failure is reported, never rendered as an empty list', async () => {
    mockedGetAgentRuns.mockRejectedValue(new Error('backend unreachable'));
    render(<AgentRunSheet onClose={vi.fn()} />);
    expect(await screen.findByRole('alert')).toHaveTextContent('backend unreachable');
    expect(screen.queryByTestId('agent-run-sheet-empty')).not.toBeInTheDocument();
  });

  it('is a labelled dialog that closes by button and by Escape', async () => {
    mockedGetAgentRuns.mockResolvedValue({ items: [run()] } as never);
    const onClose = vi.fn();
    render(<AgentRunSheet onClose={onClose} />);

    const dialog = screen.getByRole('dialog');
    expect(dialog).toHaveAttribute('aria-modal', 'true');
    expect(dialog).toHaveAccessibleName('Agent runs');
    // The phone gets the full viewport; the class carries that from 2.5.
    expect(dialog.className).toContain('mobile-sheet');

    fireEvent.click(screen.getByTestId('agent-run-sheet-close'));
    expect(onClose).toHaveBeenCalledTimes(1);

    fireEvent.keyDown(window, { key: 'Escape' });
    expect(onClose).toHaveBeenCalledTimes(2);
  });

  // Issue #338: mounted inside the blurred sticky header, a fixed overlay was
  // header-sized and the close button sat above the viewport. The overlay must
  // live directly under <body>, whatever renders the sheet.
  it('renders its overlay under <body>, outside the element that mounts it', async () => {
    mockedGetAgentRuns.mockResolvedValue({ items: [run()] } as never);
    const header = document.createElement('header');
    header.className = 'sticky top-0 backdrop-blur-md';
    document.body.appendChild(header);
    render(<AgentRunSheet onClose={vi.fn()} />, { container: header });

    const overlay = screen.getByTestId('agent-run-sheet-overlay');
    expect(overlay.parentElement).toBe(document.body);
    expect(header.contains(overlay)).toBe(false);
    header.remove();
  });

  it('closes on a backdrop click and not on a click inside the dialog', async () => {
    mockedGetAgentRuns.mockResolvedValue({ items: [run()] } as never);
    const onClose = vi.fn();
    render(<AgentRunSheet onClose={onClose} />);

    fireEvent.click(screen.getByRole('dialog'));
    fireEvent.click(await screen.findByText('INcendiary'));
    expect(onClose).not.toHaveBeenCalled();

    fireEvent.click(screen.getByTestId('agent-run-sheet-overlay'));
    expect(onClose).toHaveBeenCalledTimes(1);
  });

  // Issue #339: a run the local runner closed says why.
  it('shows why a failed run ended', async () => {
    mockedGetAgentRuns.mockResolvedValue({
      items: [run({ status: 'failed', prUrl: null, prNumber: null, outcome: 'runner-failed', outcomeDetail: 'verification failed: 2 tests' })],
    } as never);
    render(<AgentRunSheet onClose={vi.fn()} />);
    expect(await screen.findByTestId('agent-run-sheet-outcome')).toHaveTextContent('verification failed: 2 tests');
  });
});

describe('AgentActivityIndicator tap-through', () => {
  it('is activatable and opens the run list', async () => {
    mockedGetAgentRuns.mockResolvedValue({ items: [run()] } as never);
    render(<AgentActivityIndicator />);

    const pill = await screen.findByTestId('agent-activity-indicator');
    // It was a <span> through Release 2.5-3.5: visible, countable, and dead
    // to a finger.
    expect(pill.tagName).toBe('BUTTON');
    expect(pill).toHaveAttribute('aria-haspopup', 'dialog');
    expect(pill).toHaveAccessibleName(expect.stringContaining('Open the agent run list'));

    fireEvent.click(pill);
    await waitFor(() => expect(screen.getByRole('dialog')).toBeInTheDocument());
    expect(await screen.findByText('INcendiary')).toBeInTheDocument();
  });
});
