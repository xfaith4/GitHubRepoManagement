// @vitest-environment jsdom
//
// DOM tests for the work-item trace modal (Release 3.1).
//
// The pure view logic is covered in lib/workItemTrace.test.ts; what these
// assert is the property that logic exists to serve: a stage nothing ever
// recorded must render visibly differently from a stage the chain simply has
// not reached. If both render as a quiet grey row, a stalled loop looks like a
// young one and the trace stops being decision-grade.
import { describe, it, expect, vi, afterEach, beforeEach } from 'vitest';
import { render, screen, cleanup, waitFor, fireEvent } from '@testing-library/react';
import '@testing-library/jest-dom/vitest';
import React from 'react';
import type { WorkItemTrace } from '../lib/workItemTrace';

const getWorkItemTrace = vi.fn();
vi.mock('../services/apiClient', () => ({
  getWorkItemTrace: (id: string) => getWorkItemTrace(id),
}));

// Imported after the mock so the component picks it up.
const { default: WorkItemTraceModal } = await import('./WorkItemTraceModal');

const stage = (key: string, order: number, status: string, label: string, detail = '') => ({
  stage: key, order, status, label, detail, at: null, artifact: null, evidence: null,
});

const traceWithGap: WorkItemTrace = {
  traceId: '20260810-000100-abcd1234',
  status: 'active',
  currentStage: 'writeBack',
  completeStageCount: 6,
  stageCount: 7,
  hasGaps: true,
  gaps: ['writeBack'],
  identity: {
    packetId: 'pkt-1',
    dispatchRunId: '20260810-000100-abcd1234',
    repoName: 'demo',
    itemText: 'Add the operator export route',
    prUrl: 'https://github.com/o/demo/pull/7',
  },
  stages: [
    stage('rank', 1, 'complete', 'Rank'),
    stage('prompt', 2, 'complete', 'Prompt'),
    stage('dispatch', 3, 'complete', 'Dispatch'),
    stage('agentRun', 4, 'complete', 'Agent run'),
    stage('actions', 5, 'complete', 'Actions result'),
    stage('mergeReadiness', 6, 'complete', 'Merge readiness'),
    stage('writeBack', 7, 'missing', 'Roadmap write-back', 'The pull request is merged but the roadmap still shows this item as open.'),
  ],
};

const traceNotStarted: WorkItemTrace = {
  ...traceWithGap,
  status: 'active',
  currentStage: 'agentRun',
  completeStageCount: 3,
  hasGaps: false,
  gaps: [],
  stages: [
    stage('rank', 1, 'complete', 'Rank'),
    stage('prompt', 2, 'complete', 'Prompt'),
    stage('dispatch', 3, 'complete', 'Dispatch'),
    stage('agentRun', 4, 'pending', 'Agent run'),
    stage('actions', 5, 'pending', 'Actions result'),
    stage('mergeReadiness', 6, 'pending', 'Merge readiness'),
    stage('writeBack', 7, 'pending', 'Roadmap write-back'),
  ],
};

beforeEach(() => { getWorkItemTrace.mockReset(); });
afterEach(cleanup);

const stageRow = (key: string) =>
  document.querySelector(`[data-testid="work-item-trace-stage"][data-stage="${key}"]`) as HTMLElement;

describe('WorkItemTraceModal', () => {
  it('renders every stage of the chain in order', async () => {
    getWorkItemTrace.mockResolvedValue(traceWithGap);
    render(<WorkItemTraceModal traceId="20260810-000100-abcd1234" onClose={() => {}} />);

    await waitFor(() => expect(screen.getAllByTestId('work-item-trace-stage')).toHaveLength(7));
    const labels = screen.getAllByTestId('work-item-trace-stage').map(el => el.getAttribute('data-stage'));
    expect(labels).toEqual(['rank', 'prompt', 'dispatch', 'agentRun', 'actions', 'mergeReadiness', 'writeBack']);
  });

  it('marks a broken link differently from a stage the chain has not reached', async () => {
    getWorkItemTrace.mockResolvedValue(traceWithGap);
    const { unmount } = render(<WorkItemTraceModal traceId="t" onClose={() => {}} />);
    await waitFor(() => expect(stageRow('writeBack')).toBeInTheDocument());

    const gapRow = stageRow('writeBack');
    expect(gapRow).toHaveAttribute('data-stage-status', 'missing');
    expect(gapRow).toHaveTextContent('No record');
    expect(screen.getByTestId('work-item-trace-gap-count')).toHaveTextContent('1 broken link');
    const gapClasses = gapRow.innerHTML;
    unmount();

    getWorkItemTrace.mockResolvedValue(traceNotStarted);
    render(<WorkItemTraceModal traceId="t" onClose={() => {}} />);
    await waitFor(() => expect(stageRow('writeBack')).toBeInTheDocument());

    const pendingRow = stageRow('writeBack');
    expect(pendingRow).toHaveAttribute('data-stage-status', 'pending');
    expect(pendingRow).toHaveTextContent('Not started');
    expect(screen.queryByTestId('work-item-trace-gap-count')).not.toBeInTheDocument();
    // Same stage, same position — the only difference must be how it reads.
    expect(pendingRow.innerHTML).not.toEqual(gapClasses);
  });

  it('summarizes where the item stands', async () => {
    getWorkItemTrace.mockResolvedValue(traceNotStarted);
    render(<WorkItemTraceModal traceId="t" onClose={() => {}} />);
    await waitFor(() =>
      expect(screen.getByTestId('work-item-trace-summary')).toHaveTextContent('3/7 stages complete — waiting at agent run.'),
    );
  });

  // An unknown id 404s. Rendering that as an empty trace would say "nothing
  // happened" when the truth is "this id matches nothing".
  it('shows the failure instead of an empty trace', async () => {
    getWorkItemTrace.mockRejectedValue(new Error("No work item matches id 'nope'."));
    render(<WorkItemTraceModal traceId="nope" onClose={() => {}} />);

    await waitFor(() => expect(screen.getByTestId('work-item-trace-error')).toHaveTextContent('No work item matches'));
    expect(screen.queryAllByTestId('work-item-trace-stage')).toHaveLength(0);
  });

  it('re-fetches on refresh', async () => {
    getWorkItemTrace.mockResolvedValue(traceWithGap);
    render(<WorkItemTraceModal traceId="t" onClose={() => {}} />);
    await waitFor(() => expect(getWorkItemTrace).toHaveBeenCalledTimes(1));

    fireEvent.click(screen.getByText('Refresh'));
    await waitFor(() => expect(getWorkItemTrace).toHaveBeenCalledTimes(2));
  });
});
