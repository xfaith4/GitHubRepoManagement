// @vitest-environment jsdom
//
// Lane 0.17 — the Dispatch Board: one filtered ledger list instead of three
// overlapping tabs, state tiles that filter instead of merely counting, and
// a Dispatch action that carries the ledger's known roadmap path.
//
// The failures these prevent: a page that says "27 Ready" while showing
// three rows; state counts with no way to see the repos they count; and a
// dispatch that drops the roadmap path the ledger already knows, leaving the
// packet build to fail on a cold cache.
import { afterEach, describe, expect, it, vi } from 'vitest';
import { cleanup, render, screen, within, fireEvent } from '@testing-library/react';
import '@testing-library/jest-dom/vitest';
import React from 'react';
import ExecutionQueuePanel from './ExecutionQueuePanel';
import * as apiClient from '../services/apiClient';
import type { ExecutionQueueSummary, ExecutionLaneEntry, ExecutionLaneObservation, ExecutionState } from '../types';

vi.mock('../services/apiClient', () => ({
  getExecutionQueue: vi.fn(),
  syncExecutionQueue: vi.fn(),
  assignExecutionLane: vi.fn(),
  completeExecutionTask: vi.fn(),
  cancelExecutionTask: vi.fn(),
  requeueExecution: vi.fn(),
}));

const mockedGetQueue = vi.mocked(apiClient.getExecutionQueue);
const mockedComplete = vi.mocked(apiClient.completeExecutionTask);

afterEach(() => { cleanup(); vi.clearAllMocks(); });

function entry(repoName: string, executionState: ExecutionState, priorityScore: number, over: Partial<ExecutionLaneEntry> = {}): ExecutionLaneEntry {
  return {
    repoName,
    executionState,
    priorityScore,
    retryCount: 0,
    updatedAt: '2026-08-30T12:00:00Z',
    ...over,
  };
}

function summary(over: Partial<ExecutionQueueSummary> = {}): ExecutionQueueSummary {
  const entries = [
    entry('ready-one', 'ready', 200, { roadmapPath: 'F:\\repos\\ready-one\\ROADMAP.md', repoPath: 'F:\\repos\\ready-one', currentTaskText: 'Ship the widget' }),
    entry('ready-two', 'ready', 184),
    entry('ready-three', 'ready', 150),
    entry('ready-four', 'ready', 120),
    entry('blocked-repo', 'blocked', 40, { errorMessage: 'parse-error' }),
    entry('idle-repo', 'idle', 10),
    entry('complete-repo', 'complete', 5),
  ];
  return {
    schemaVersion: '1.0',
    updatedAt: '2026-08-30T12:00:00Z',
    totalRepos: entries.length,
    stateCounts: { idle: 1, ready: 4, running: 0, blocked: 1, complete: 1 },
    activeLaneCount: 0,
    lanes: { lane1: null, lane2: null },
    rankedQueue: entries.filter(e => e.executionState === 'ready'),
    entries,
    recentHistory: [
      { repoName: 'ready-one', event: 'assigned', timestamp: '2026-08-30T11:00:00Z' },
    ],
    ...over,
  };
}

describe('ExecutionQueuePanel — the Dispatch Board', () => {
  it('defaults to the Ready filter and shows EVERY ready repo, not a three-row teaser', async () => {
    mockedGetQueue.mockResolvedValue(summary());
    render(<ExecutionQueuePanel />);

    expect(await screen.findByText('ready-one')).toBeInTheDocument();
    expect(screen.getByText('ready-four')).toBeInTheDocument();
    // Non-ready states are filtered out, not silently hidden forever — their
    // tiles carry the counts.
    expect(screen.queryByText('blocked-repo')).not.toBeInTheDocument();

    const readyTile = screen.getByRole('button', { name: /4\s*Ready/ });
    expect(readyTile).toHaveAttribute('aria-pressed', 'true');
  });

  it('state tiles filter the list; the active tile clicked again shows all', async () => {
    mockedGetQueue.mockResolvedValue(summary());
    render(<ExecutionQueuePanel />);
    await screen.findByText('ready-one');

    const blockedTile = screen.getByRole('button', { name: /1\s*Execution blocked/ });
    fireEvent.click(blockedTile);
    expect(screen.getByText('blocked-repo')).toBeInTheDocument();
    expect(screen.queryByText('ready-one')).not.toBeInTheDocument();
    expect(blockedTile).toHaveAttribute('aria-pressed', 'true');

    // Clicking the selected tile clears the filter — everything renders.
    fireEvent.click(blockedTile);
    expect(screen.getByText('ready-one')).toBeInTheDocument();
    expect(screen.getByText('blocked-repo')).toBeInTheDocument();
    expect(screen.getByText('idle-repo')).toBeInTheDocument();
    expect(screen.getByText('complete-repo')).toBeInTheDocument();
  });

  it('the Total tile shows the whole ledger', async () => {
    mockedGetQueue.mockResolvedValue(summary());
    render(<ExecutionQueuePanel />);
    await screen.findByText('ready-one');

    fireEvent.click(screen.getByRole('button', { name: /7\s*Total/ }));
    expect(screen.getByText('complete-repo')).toBeInTheDocument();
    expect(screen.getByText('idle-repo')).toBeInTheDocument();
  });

  it('Dispatch passes the repo name AND the ledger roadmap and repo paths to the preview', async () => {
    mockedGetQueue.mockResolvedValue(summary());
    const onDispatch = vi.fn();
    render(<ExecutionQueuePanel onDispatchPreviewTask={onDispatch} />);
    await screen.findByText('ready-one');

    const row = screen.getByText('ready-one').closest('div[class*="rounded-lg"]') as HTMLElement;
    fireEvent.click(within(row).getByRole('button', { name: 'Dispatch' }));
    // Lane 0.17 — repoPath travels too, so a real dispatch can locate the repo
    // on disk without depending on a warm roadmap cache.
    expect(onDispatch).toHaveBeenCalledWith('ready-one', 'F:\\repos\\ready-one\\ROADMAP.md', 'F:\\repos\\ready-one');
  });

  it('a ledger entry without a roadmap path dispatches with undefined, never an empty string', async () => {
    mockedGetQueue.mockResolvedValue(summary());
    const onDispatch = vi.fn();
    render(<ExecutionQueuePanel onDispatchPreviewTask={onDispatch} />);
    await screen.findByText('ready-two');

    const row = screen.getByText('ready-two').closest('div[class*="rounded-lg"]') as HTMLElement;
    fireEvent.click(within(row).getByRole('button', { name: 'Dispatch' }));
    expect(onDispatch).toHaveBeenCalledWith('ready-two', undefined, undefined);
  });

  it('the lanes strip stays pinned above the queue — empty lanes say how to fill them', async () => {
    mockedGetQueue.mockResolvedValue(summary());
    render(<ExecutionQueuePanel />);
    await screen.findByText('ready-one');

    const emptyLanes = screen.getAllByTestId('execution-lane-empty');
    expect(emptyLanes).toHaveLength(2);
    expect(emptyLanes[0]).toHaveTextContent(/queue below/i);
  });

  // ---------------------------------------------------------------------
  // Lane 0.17 — observed run state on the lane card.
  //
  // These pin the difference the release exists to create: before it, every
  // one of these lanes rendered identically as "Running", because the only
  // fact the card had was that nobody had clicked Complete yet.
  // ---------------------------------------------------------------------
  function runningLane(over: Partial<ExecutionLaneObservation> = {}): ExecutionLaneEntry {
    return entry('lane-repo', 'running', 200, {
      laneSlot: 1,
      assignedAt: '2026-08-30T11:00:00Z',
      currentTaskText: 'Ship the widget',
      dispatchRunId: 'dispatch-abc',
      observation: {
        linked: true,
        dispatchRunId: 'dispatch-abc',
        verdict: 'working',
        verdictLabel: 'Working',
        verdictDetail: 'The agent is working on draft PR #18.',
        stalled: false,
        suggestedAction: 'wait',
        sources: ['run-summary', 'agent-run'],
        lastObservedAt: '2026-08-30T11:55:00Z',
        ...over,
      },
    });
  }

  function laneSummary(laneEntry: ExecutionLaneEntry) {
    const base = summary();
    return {
      ...base,
      activeLaneCount: 1,
      lanes: { lane1: laneEntry, lane2: null },
      entries: [laneEntry, ...base.entries],
    };
  }

  it('a working lane reports the run, its PR and when it was last observed', async () => {
    mockedGetQueue.mockResolvedValue(laneSummary(runningLane({
      pr: { number: 18, url: 'https://github.com/x/y/pull/18', state: 'open', draft: true },
      actions: { status: 'completed', conclusion: 'success' },
    })));
    render(<ExecutionQueuePanel />);
    await screen.findByText('lane-repo');

    const observed = screen.getByTestId('lane-observation');
    expect(within(observed).getByTestId('lane-observation-verdict')).toHaveTextContent('Working');
    expect(within(observed).getByRole('link', { name: /PR #18 \(draft\)/ })).toHaveAttribute(
      'href',
      'https://github.com/x/y/pull/18'
    );
    expect(observed).toHaveTextContent('Checks: success');
    expect(observed).toHaveTextContent('Run dispatch-abc');
    expect(observed).toHaveTextContent(/last observed/);
  });

  it('a stalled lane says Stuck — the question the board exists to answer', async () => {
    mockedGetQueue.mockResolvedValue(laneSummary(runningLane({
      stalled: true,
      verdictLabel: 'Stuck',
      verdictDetail: 'Queued — no runner has claimed this task yet. Nothing has moved for 3 hours.',
      verdict: 'queued',
      stalledAfterMinutes: 15,
    })));
    render(<ExecutionQueuePanel />);
    await screen.findByText('lane-repo');

    expect(screen.getByTestId('lane-observation-verdict')).toHaveTextContent('Stuck');
    expect(screen.getByTestId('lane-observation')).toHaveTextContent(/Nothing has moved for 3 hours/);
  });

  it('a hand-occupied lane admits it is bookkeeping instead of borrowing a run it does not have', async () => {
    mockedGetQueue.mockResolvedValue(laneSummary(entry('lane-repo', 'running', 200, {
      laneSlot: 1,
      assignedAt: '2026-08-30T11:00:00Z',
      observation: {
        linked: false,
        verdict: 'unlinked',
        verdictLabel: 'Bookkeeping',
        verdictDetail: 'No agent run is linked to this lane — it was occupied by hand 42 minutes ago.',
        stalled: false,
        suggestedAction: 'none',
        sources: [],
      },
    })));
    render(<ExecutionQueuePanel />);
    await screen.findByText('lane-repo');

    const observed = screen.getByTestId('lane-observation');
    expect(observed).toHaveTextContent('Bookkeeping');
    expect(observed).toHaveTextContent(/occupied by hand/);
    // No run id line: there is no run, and inventing provenance is the defect.
    expect(observed).not.toHaveTextContent(/^Run /m);
    expect(observed).not.toHaveTextContent(/last observed/);
  });

  it('a merged run points at Complete without pressing it', async () => {
    mockedGetQueue.mockResolvedValue(laneSummary(runningLane({
      verdict: 'finished',
      verdictLabel: 'Merged',
      verdictDetail: 'PR #18 is merged.',
      suggestedAction: 'complete',
      pr: { number: 18, url: 'https://github.com/x/y/pull/18', state: 'merged', draft: false },
    })));
    render(<ExecutionQueuePanel />);
    await screen.findByText('lane-repo');

    expect(screen.getByText('Merged — completing frees the lane.')).toBeInTheDocument();
    // The lane is still occupied: the verdict informs the operator, it does
    // not close the lane for them.
    expect(screen.getByRole('button', { name: 'Complete' })).toBeEnabled();
    expect(mockedComplete).not.toHaveBeenCalled();
  });

  it('blocked rows offer Requeue, not Dispatch', async () => {
    mockedGetQueue.mockResolvedValue(summary());
    render(<ExecutionQueuePanel />);
    await screen.findByText('ready-one');

    fireEvent.click(screen.getByRole('button', { name: /1\s*Execution blocked/ }));
    const row = screen.getByText('blocked-repo').closest('div[class*="rounded-lg"]') as HTMLElement;
    expect(within(row).getByRole('button', { name: 'Requeue' })).toBeInTheDocument();
    expect(within(row).queryByRole('button', { name: 'Dispatch' })).not.toBeInTheDocument();
  });
});

it('names execution blockers and their ledger denominator', async () => {
  mockedGetQueue.mockResolvedValue(summary());
  render(<ExecutionQueuePanel />);
  await screen.findByText('ready-one');
  expect(screen.getByRole('button', { name: /1\s*Execution blocked\s*of\s*7\s*ledger repositories/ })).toBeVisible();
});
