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
const previewRoadmapWriteBack = vi.fn();
const applyRoadmapWriteBack = vi.fn();

class TestWriteBackRefusedError extends Error {
  category: string;
  refusals: Array<{ code: string; message: string; remedy: string }>;
  constructor(message: string, category: string, refusals: Array<{ code: string; message: string; remedy: string }>) {
    super(message);
    this.name = 'WriteBackRefusedError';
    this.category = category;
    this.refusals = refusals;
  }
}

vi.mock('../services/apiClient', () => ({
  getWorkItemTrace: (id: string) => getWorkItemTrace(id),
  previewRoadmapWriteBack: (id: string) => previewRoadmapWriteBack(id),
  applyRoadmapWriteBack: (id: string, previewId: string, content: string) => applyRoadmapWriteBack(id, previewId, content),
  WriteBackRefusedError: TestWriteBackRefusedError,
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

beforeEach(() => {
  getWorkItemTrace.mockReset();
  previewRoadmapWriteBack.mockReset();
  applyRoadmapWriteBack.mockReset();
});
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

describe('WorkItemTraceModal — roadmap write-back', () => {
  const openTrace = async () => {
    getWorkItemTrace.mockResolvedValue(traceWithGap);
    render(<WorkItemTraceModal traceId="t" onClose={() => {}} />);
    await waitFor(() => expect(screen.getByTestId('work-item-write-back')).toBeInTheDocument());
  };

  // The gate's refusal is the product here. Showing only "failed" would leave
  // the operator guessing which of six preconditions is missing.
  it('shows every refusal code with the remedy that would satisfy it', async () => {
    previewRoadmapWriteBack.mockRejectedValue(
      new TestWriteBackRefusedError('Completion cannot be claimed for this item: Pull request #7 is still open.', 'write-back-refused', [
        { code: 'pr-not-merged', message: 'Pull request #7 is still open.', remedy: 'Merge the pull request, then re-check.' },
      ]),
    );
    await openTrace();
    fireEvent.click(screen.getByTestId('work-item-write-back-preview'));

    const refusal = await screen.findByTestId('work-item-write-back-refusal');
    expect(refusal).toHaveTextContent('pr-not-merged');
    expect(refusal).toHaveTextContent('Merge the pull request, then re-check.');
    expect(screen.queryByTestId('work-item-write-back-apply')).not.toBeInTheDocument();
  });

  it('renders the proposed edit as a diff before anything is written', async () => {
    previewRoadmapWriteBack.mockResolvedValue({
      previewId: 'prev-1',
      roadmapPath: 'C:\\repos\\demo\\ROADMAP.md',
      itemText: 'Add the operator export route',
      markedCount: 1,
      proposedContent: '- [x] Add the operator export route',
      diff: [{ line: 7, before: '- [ ] Add the operator export route', after: '- [x] Add the operator export route' }],
    });
    await openTrace();
    fireEvent.click(screen.getByTestId('work-item-write-back-preview'));

    const result = await screen.findByTestId('work-item-write-back-preview-result');
    expect(result).toHaveTextContent('- [ ] Add the operator export route');
    expect(result).toHaveTextContent('+ - [x] Add the operator export route');
    expect(result).toHaveTextContent('Nothing is written until you apply it.');
    expect(applyRoadmapWriteBack).not.toHaveBeenCalled();
  });

  // Applying edits a file in a different repository, so it confirms first.
  it('confirms before applying, and does not apply on cancel', async () => {
    previewRoadmapWriteBack.mockResolvedValue({
      previewId: 'prev-1',
      roadmapPath: 'C:\\repos\\demo\\ROADMAP.md',
      markedCount: 1,
      proposedContent: 'content',
      diff: [{ line: 7, before: 'a', after: 'b' }],
    });
    await openTrace();
    fireEvent.click(screen.getByTestId('work-item-write-back-preview'));
    fireEvent.click(await screen.findByTestId('work-item-write-back-apply'));

    expect(screen.getByTestId('work-item-write-back-confirm-prompt')).toHaveTextContent('C:\\repos\\demo\\ROADMAP.md');
    expect(applyRoadmapWriteBack).not.toHaveBeenCalled();

    fireEvent.click(screen.getByTestId('work-item-write-back-cancel'));
    expect(applyRoadmapWriteBack).not.toHaveBeenCalled();
    expect(screen.queryByTestId('work-item-write-back-confirm-prompt')).not.toBeInTheDocument();
  });

  it('applies on confirm and re-reads the trace', async () => {
    previewRoadmapWriteBack.mockResolvedValue({
      previewId: 'prev-1',
      roadmapPath: 'C:\\repos\\demo\\ROADMAP.md',
      markedCount: 1,
      proposedContent: 'content',
      diff: [{ line: 7, before: 'a', after: 'b' }],
    });
    applyRoadmapWriteBack.mockResolvedValue({ applied: true, markedCount: 1, roadmapPath: 'C:\\repos\\demo\\ROADMAP.md' });
    await openTrace();
    await waitFor(() => expect(getWorkItemTrace).toHaveBeenCalledTimes(1));

    fireEvent.click(screen.getByTestId('work-item-write-back-preview'));
    fireEvent.click(await screen.findByTestId('work-item-write-back-apply'));
    fireEvent.click(screen.getByTestId('work-item-write-back-confirm'));

    await waitFor(() => expect(applyRoadmapWriteBack).toHaveBeenCalledWith('t', 'prev-1', 'content'));
    expect(await screen.findByTestId('work-item-write-back-applied')).toHaveTextContent('Marked 1 item complete');
    // The trace must be re-read: the write-back stage just changed.
    await waitFor(() => expect(getWorkItemTrace).toHaveBeenCalledTimes(2));
  });

  // Apply re-runs the gate server-side. If it refuses at that point, the UI
  // must show the refusal rather than a stale success.
  it('surfaces a refusal that only appears at apply time', async () => {
    previewRoadmapWriteBack.mockResolvedValue({
      previewId: 'prev-1', roadmapPath: 'r.md', markedCount: 1, proposedContent: 'content',
      diff: [{ line: 1, before: 'a', after: 'b' }],
    });
    applyRoadmapWriteBack.mockRejectedValue(
      new TestWriteBackRefusedError('The roadmap changed since this preview was generated.', 'stale-preview', []),
    );
    await openTrace();
    fireEvent.click(screen.getByTestId('work-item-write-back-preview'));
    fireEvent.click(await screen.findByTestId('work-item-write-back-apply'));
    fireEvent.click(screen.getByTestId('work-item-write-back-confirm'));

    expect(await screen.findByTestId('work-item-write-back-refusal')).toHaveTextContent('The roadmap changed since this preview was generated.');
    expect(screen.queryByTestId('work-item-write-back-applied')).not.toBeInTheDocument();
  });
});
