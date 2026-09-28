// @vitest-environment jsdom
//
// Agent Ops (2026-09-27) — the operator's one page for agent work.
//
// The failures these prevent: an empty board that reads as broken, decisions
// rendered in an arbitrary order or without their button, a stop control that
// fires without confirmation or fires without telling the host to interrupt,
// and a held runner rendered as a fault instead of a deliberate stop.
import { describe, it, expect, vi, afterEach } from 'vitest';
import { render, screen, within, fireEvent, cleanup, waitFor } from '@testing-library/react';
import '@testing-library/jest-dom/vitest';
import React from 'react';
import AgentOpsView from './AgentOpsView';
import type { AgentOpsData } from '../hooks/useAgentOpsData';
import type { AgentRun } from '../types';
import type { PackagedItem } from '../lib/packagedItems';
import type { RunnerPresencePayload } from '../lib/runnerPresence';
import * as apiClient from '../services/apiClient';

vi.mock('../services/apiClient', () => ({
  approveAgentRun: vi.fn(),
  approvePackagedItem: vi.fn(),
  cancelExecutionTask: vi.fn(),
  executeMergeReadinessMerge: vi.fn(),
  getAgentRunDetail: vi.fn(),
  getMergeReadiness: vi.fn(),
  refreshAgentRun: vi.fn(),
  rejectPackagedItem: vi.fn(),
  startRunner: vi.fn(),
  stopRunner: vi.fn(),
}));
const mocked = vi.mocked(apiClient);

const NOW = Date.parse('2026-09-27T12:00:00Z');
const minutesAgo = (m: number) => new Date(NOW - m * 60_000).toISOString();

function run(overrides: Partial<AgentRun> = {}): AgentRun {
  return {
    runId: 'run-1',
    repoName: 'alpha',
    providerTool: 'claude',
    status: 'active',
    selectedTaskText: 'Do the thing',
    createdAt: minutesAgo(30),
    updatedAt: minutesAgo(5),
    ...overrides,
  } as AgentRun;
}

const present: RunnerPresencePayload = { state: 'present', present: true, hostname: 'BEN-WS', user: 'ben', lastHeartbeatAt: minutesAgo(0) };

function data(overrides: Partial<AgentOpsData> = {}): AgentOpsData {
  return {
    runs: [],
    runner: present,
    packages: [],
    queue: [],
    roadmap: [],
    providers: [],
    updatedAtMs: NOW - 12_000,
    loaded: true,
    error: null,
    refresh: vi.fn(),
    ...overrides,
  };
}

afterEach(() => { cleanup(); vi.clearAllMocks(); });

describe('AgentOpsView — empty state', () => {
  it('explains an empty board instead of rendering blanks', () => {
    render(<AgentOpsView data={data()} nowMs={NOW} />);
    expect(screen.getByTestId('agent-ops-actions-empty')).toHaveTextContent('Nothing needs you right now. New decisions appear here as runs reach an operator gate.');
    expect(screen.getByTestId('agent-ops-inflight-empty')).toHaveTextContent('No runs in flight');
    expect(screen.getByText(/Nothing ranked for dispatch/)).toBeInTheDocument();
    expect(screen.getByText(/No roadmap index yet/)).toBeInTheDocument();
    expect(screen.getByText('Updated 12s ago')).toBeInTheDocument();
    expect(screen.getByTestId('agent-ops-runner')).toHaveTextContent('Runner ready');
    expect(screen.getByRole('button', { name: /All work stop/ })).toBeInTheDocument();
  });
});

describe('AgentOpsView — operator actions', () => {
  const runs = [
    run({ runId: 'ci', repoName: 'auditor', deliveryState: 'CI_FAILED', prNumber: 8, selectedTaskText: 'Rule: flag queues' }),
    run({ runId: 'approve', repoName: 'pilot', deliveryState: 'READY_FOR_OPERATOR', prNumber: 22, verifiedHeadSha: '9f3c2a1ff', selectedTaskText: 'Persist run history' }),
    run({ runId: 'merge', repoName: 'mgmt', repoId: 'repo:mgmt', deliveryState: 'OPERATOR_APPROVED', prNumber: 212, operatorApproval: { sha: 'e44a9b0', at: minutesAgo(8), actor: 'ben' }, selectedTaskText: 'Approval binds to SHA' }),
    run({ runId: 'working', repoName: 'core', deliveryState: 'AGENT_RUNNING', selectedTaskText: 'Jittered backoff' }),
  ];
  const packages: PackagedItem[] = [
    { packetId: 'pk-88', status: 'pending-approval', repoName: 'auditor', packagedAt: minutesAgo(35), packet: { itemText: 'Rule: detect orphaned users', valueScore: 82, maturityLevel: 'L3' } } as PackagedItem,
  ];

  it('renders one card per decision, in the handoff order, each with its consequence button', () => {
    render(<AgentOpsView data={data({ runs, packages })} nowMs={NOW} />);
    const cards = screen.getAllByTestId('agent-ops-action');
    expect(cards.map(c => c.getAttribute('data-kind'))).toEqual(['approve-sha', 'merge', 'ci-failed', 'package-approval']);
    expect(within(cards[0]).getByRole('button', { name: 'Approve 9f3c2a1' })).toBeInTheDocument();
    expect(within(cards[0]).getByRole('button', { name: 'Details' })).toBeInTheDocument();
    expect(within(cards[1]).getByRole('button', { name: 'Merge PR #212' })).toBeInTheDocument();
    expect(within(cards[2]).getByRole('button', { name: 'Re-evaluate run' })).toBeInTheDocument();
    expect(within(cards[2]).getByRole('button', { name: 'Cancel' })).toBeInTheDocument();
    expect(within(cards[3]).getByRole('button', { name: 'Approve & queue' })).toBeInTheDocument();
    expect(within(cards[3]).getByRole('button', { name: 'Reject' })).toBeInTheDocument();
    // The count on the section header is the number of cards.
    expect(screen.getByText('Operator actions').parentElement).toHaveTextContent('4');
    // The run doing ordinary work is in flight, not a decision.
    expect(screen.getAllByTestId('agent-ops-run')).toHaveLength(4);
  });

  it('approves with the verified sha, refreshes the board, and shows a refusal inline', async () => {
    mocked.approveAgentRun.mockResolvedValueOnce(run() as never);
    const d = data({ runs, packages });
    render(<AgentOpsView data={d} nowMs={NOW} />);
    fireEvent.click(screen.getByRole('button', { name: 'Approve 9f3c2a1' }));
    await waitFor(() => expect(mocked.approveAgentRun).toHaveBeenCalledWith('approve', '9f3c2a1ff'));
    await waitFor(() => expect(d.refresh).toHaveBeenCalled());

    mocked.executeMergeReadinessMerge.mockRejectedValueOnce(new Error('MERGE-HEAD-MOVED: the approved sha is no longer the head.'));
    fireEvent.click(screen.getByRole('button', { name: 'Merge PR #212' }));
    expect(await screen.findByRole('alert')).toHaveTextContent('MERGE-HEAD-MOVED');
    expect(mocked.executeMergeReadinessMerge).toHaveBeenCalledWith('repo:mgmt');
  });
});

describe('AgentOpsView — All work stop', () => {
  const runs = [
    run({ runId: 'a', repoName: 'alpha', deliveryState: 'AGENT_RUNNING' }),
    run({ runId: 'b', repoName: 'bravo', deliveryState: 'CI_PENDING', providerTool: 'copilot' }),
    run({ runId: 'w', repoName: 'charlie', deliveryState: 'CAPACITY_WAIT' }),
  ];

  it('confirms before stopping, focuses Keep running, and sends the interrupt with the reason', async () => {
    mocked.stopRunner.mockResolvedValueOnce({ held: true, stoppedAt: minutesAgo(0), interrupted: [{ runId: 'a', repoName: 'alpha', provider: 'claude', fromState: 'AGENT_RUNNING', remote: false }] });
    const d = data({ runs });
    render(<AgentOpsView data={d} nowMs={NOW} />);

    fireEvent.click(screen.getByRole('button', { name: /All work stop/ }));
    const dialog = screen.getByRole('dialog', { name: 'Stop all agent work?' });
    expect(dialog).toHaveTextContent('2 runs are mid-flight (alpha, bravo). They will be interrupted now.');
    expect(dialog).toHaveTextContent('Interrupted runs keep their branch and workspace. Nothing is pushed or merged.');
    expect(dialog).toHaveTextContent(/Copilot runs cannot be killed from here/);
    expect(within(dialog).getByRole('button', { name: 'Keep running' })).toHaveFocus();
    expect(mocked.stopRunner).not.toHaveBeenCalled();

    fireEvent.change(screen.getByTestId('agent-ops-stop-reason'), { target: { value: 'bad prompt in the batch' } });
    fireEvent.click(screen.getByTestId('agent-ops-stop-confirm'));
    await waitFor(() => expect(mocked.stopRunner).toHaveBeenCalledWith('bad prompt in the batch', { interrupt: true }));
    await waitFor(() => expect(screen.queryByRole('dialog', { name: 'Stop all agent work?' })).not.toBeInTheDocument());
    expect(d.refresh).toHaveBeenCalled();
    expect(mocked.cancelExecutionTask).not.toHaveBeenCalled();
  });

  it('Keep running closes without calling the host', () => {
    render(<AgentOpsView data={data({ runs })} nowMs={NOW} />);
    fireEvent.click(screen.getByRole('button', { name: /All work stop/ }));
    fireEvent.click(screen.getByRole('button', { name: 'Keep running' }));
    expect(screen.queryByRole('dialog', { name: 'Stop all agent work?' })).not.toBeInTheDocument();
    expect(mocked.stopRunner).not.toHaveBeenCalled();
  });

  it('falls back to per-repo cancels, and says so, when the host predates mid-run interrupts', async () => {
    mocked.stopRunner.mockResolvedValueOnce({ held: true, stoppedAt: minutesAgo(0) });
    mocked.cancelExecutionTask.mockResolvedValue({ success: true });
    const held: RunnerPresencePayload = { ...present, state: 'absent', present: false, stoppedByOperator: true, stoppedAt: minutesAgo(0), stopInterruptedCount: 0 };
    const d = data({ runs });
    const { rerender } = render(<AgentOpsView data={d} nowMs={NOW} />);
    fireEvent.click(screen.getByRole('button', { name: /All work stop/ }));
    fireEvent.click(screen.getByTestId('agent-ops-stop-confirm'));
    await waitFor(() => expect(mocked.cancelExecutionTask).toHaveBeenCalledTimes(2));
    expect(mocked.cancelExecutionTask).toHaveBeenCalledWith('alpha', 'All work stop');
    expect(mocked.cancelExecutionTask).toHaveBeenCalledWith('bravo', 'All work stop');
    rerender(<AgentOpsView data={{ ...d, runner: held }} nowMs={NOW} />);
    expect(await screen.findByTestId('agent-ops-held-banner')).toHaveTextContent('This host predates mid-run interrupts');
  });
});

describe('AgentOpsView — held runners', () => {
  const held: RunnerPresencePayload = {
    state: 'absent',
    present: false,
    stoppedByOperator: true,
    stoppedAt: minutesAgo(2),
    stoppedBy: 'operator',
    stopReason: 'bad prompt',
    stopInterruptedCount: 2,
  };
  const runs = [
    run({ runId: 's1', repoName: 'alpha', deliveryState: 'STOPPED', stoppedFrom: 'AGENT_RUNNING' }),
    run({ runId: 's2', repoName: 'bravo', deliveryState: 'STOPPED', stoppedFrom: 'PROVIDER_SELECTED', stoppedRemote: true, providerTool: 'copilot' }),
  ];

  it('shows the banner, swaps the stop button for Resume, and tags stopped runs with where they were', async () => {
    mocked.startRunner.mockResolvedValueOnce({ requested: true, holdReleased: true, taskTriggered: true, requeued: ['s1'] });
    const packages: PackagedItem[] = [
      { packetId: 'pk-1', status: 'pending-approval', repoName: 'auditor', packagedAt: minutesAgo(5), packet: { itemText: 'A packaged item', valueScore: 50 } } as PackagedItem,
    ];
    const d = data({ runs, runner: held, packages });
    render(<AgentOpsView data={d} nowMs={NOW} />);

    // Approving a package queues work, and nothing would claim it while the
    // runners are held: the control is disabled and names the precondition.
    const approveQueue = screen.getByRole('button', { name: 'Approve & queue' });
    expect(approveQueue).toBeDisabled();
    expect(approveQueue).toHaveAttribute('title', expect.stringContaining('Runners stopped'));
    expect(screen.getByTestId('agent-ops-gate-note')).toHaveTextContent('nothing would pick this up');

    expect(screen.getByTestId('agent-ops-held-banner')).toHaveTextContent('All work stopped 2m ago: 2 runs interrupted · “bad prompt”. Runners are held, so no new work is claimed.');
    expect(screen.queryByRole('button', { name: /All work stop/ })).not.toBeInTheDocument();
    expect(screen.getByTestId('agent-ops-runner')).toHaveTextContent('Runners stopped');

    const cards = screen.getAllByTestId('agent-ops-action');
    expect(cards[0]).toHaveAttribute('data-kind', 'runner-held');
    expect(cards[0]).toHaveTextContent('All work is stopped');

    const rows = screen.getAllByTestId('agent-ops-run');
    expect(rows[0]).toHaveTextContent('STOPPED · AGENT_RUNNING');
    expect(rows[1]).toHaveTextContent('STOPPED · PROVIDER_SELECTED · remote');

    fireEvent.click(screen.getAllByRole('button', { name: /Resume runners/ })[0]);
    await waitFor(() => expect(mocked.startRunner).toHaveBeenCalled());
    await waitFor(() => expect(d.refresh).toHaveBeenCalled());
  });
});

describe('AgentOpsView — run drawer', () => {
  it('opens on a row, shows the state list with the off-path arrow and the log, and closes on Escape', async () => {
    mocked.getAgentRunDetail.mockResolvedValueOnce({
      run: run(),
      events: [
        { schemaVersion: '1', eventId: 'e1', timestamp: minutesAgo(9), eventType: 'run.started', runId: 'ci', repoName: 'auditor', actor: 'system', summary: 'Agent started' },
        { schemaVersion: '1', eventId: 'e2', timestamp: minutesAgo(1), eventType: 'run.updated', runId: 'ci', repoName: 'auditor', actor: 'system', summary: 'CI failed: 3 Pester tests' },
      ],
    });
    mocked.getMergeReadiness.mockResolvedValueOnce(null);
    const runs = [run({ runId: 'ci', repoName: 'auditor', deliveryState: 'CI_FAILED', prNumber: 8, prUrl: 'https://github.com/x/auditor/pull/8', branch: 'copilot/queue-overflow', selectedTaskText: 'Rule: flag queues' })];
    render(<AgentOpsView data={data({ runs })} nowMs={NOW} />);

    fireEvent.click(screen.getByTestId('agent-ops-run'));
    const drawer = await screen.findByTestId('agent-ops-drawer');
    expect(within(drawer).getByRole('heading', { name: 'Rule: flag queues' })).toBeInTheDocument();
    expect(within(drawer).getByText('copilot/queue-overflow')).toBeInTheDocument();
    const states = within(drawer).getByTestId('agent-ops-drawer-states');
    expect(within(states).getByText(/CI_PENDING\s+→\s+CI_FAILED/)).toBeInTheDocument();
    const link = within(drawer).getByRole('link', { name: /PR #8/ });
    expect(link).toHaveAttribute('href', 'https://github.com/x/auditor/pull/8');
    expect(link).toHaveAttribute('rel', expect.stringContaining('noopener'));
    // Newest first.
    const log = await within(drawer).findByText('CI failed: 3 Pester tests');
    expect(log.compareDocumentPosition(within(drawer).getByText('Agent started')) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();

    fireEvent.keyDown(document, { key: 'Escape' });
    await waitFor(() => expect(screen.queryByTestId('agent-ops-drawer')).not.toBeInTheDocument());
  });
});
