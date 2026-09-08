// @vitest-environment jsdom
//
// Operations workspace — focus, not selection.
//
// The failure this prevents: the repository being worked on rendered in 46% of
// the page while the picker held the other 54% forever, turning a dozen
// stacked panels into one long scroll. Collapsing the list on SELECTION could
// not work — a repo is always selected (the effect falls back to the first
// row), so the list would have collapsed on first paint with no way back.
// Focus is the operator's own act, and it is reversible.
import { describe, it, expect, vi, afterEach, beforeEach } from 'vitest';
import { render, screen, fireEvent, cleanup, waitFor } from '@testing-library/react';
import '@testing-library/jest-dom/vitest';
import React from 'react';
import type { OperationsReposResult, OperationsRepoEntry } from '../types';

vi.mock('../services/apiClient', () => ({
  getRunnerPresence: vi.fn().mockResolvedValue({ present: false, runs: [] }),
  getAiDocTemplates: vi.fn().mockResolvedValue({ templates: [] }),
  getOperationsRepoDetail: vi.fn().mockResolvedValue(null),
  getOperationsPromptHistory: vi.fn().mockResolvedValue({ entries: [] }),
  getAiDocImprovementHistory: vi.fn().mockResolvedValue({ entries: [] }),
  // The client reads result.items; a mock keyed `runs` left agentRuns
  // undefined and crashed the whole view on agentRuns.length.
  getAgentRuns: vi.fn().mockResolvedValue({ items: [] }),
  getMergeReadiness: vi.fn().mockResolvedValue(null),
  getReadmeContent: vi.fn().mockResolvedValue({ content: '' }),
  getRoadmapContent: vi.fn().mockResolvedValue({ content: '' }),
  getPortfolioScanStatus: vi.fn().mockResolvedValue({ state: 'completed' }),
  startPortfolioScan: vi.fn().mockResolvedValue({ started: true, alreadyRunning: false, scan: { state: 'completed' } }),
  applyAiDocImprovement: vi.fn(),
  previewAiDocImprovement: vi.fn(),
  refineOperationsPrompt: vi.fn(),
  refreshAgentRun: vi.fn(),
  evaluateMergeReadiness: vi.fn(),
  executeMergeReadinessMerge: vi.fn(),
  approveAgentRun: vi.fn(),
  executeRoadmapDispatch: vi.fn(),
}));

import OperationsWorkspaceView from './OperationsWorkspaceView';
import { approveAgentRun, getMergeReadiness } from '../services/apiClient';

afterEach(() => cleanup());
beforeEach(() => vi.clearAllMocks());

function entry(name: string, over: Partial<OperationsRepoEntry> = {}): OperationsRepoEntry {
  return {
    repoId: `repo:${name}`,
    repoName: name,
    lifecycleState: 'discovered',
    sourceCoverage: 'local',
    localPath: `F:/repos/${name}`,
    roadmapState: 'missing',
    dispatchReadiness: 'missing-roadmap',
    executionState: 'idle',
    maturityLevel: 'L0-Absent',
    structureFindings: [],
    blockingReasons: [],
    topValueItem: null,
    ...over,
  } as unknown as OperationsRepoEntry;
}

function payload(...names: string[]): OperationsReposResult {
  return {
    entries: names.map(n => entry(n)),
    generatedAt: '2026-09-01T00:00:00Z',
    count: names.length,
    cacheSource: 'portfolio-index',
    summary: null,
    basis: { indexStale: false, indexAgeHours: 1, indexGeneratedAt: '2026-09-01T00:00:00Z', reasons: [] },
  } as unknown as OperationsReposResult;
}

const noop = () => {};

describe('OperationsWorkspaceView — the list is a picker, the repo is the work', () => {
  it('opens on the list, with no repository taking the page', () => {
    render(<OperationsWorkspaceView operationsRepos={payload('alpha', 'bravo')} loading={false} onRefresh={noop} />);

    // Both rows are pickable, and nothing has claimed the page yet.
    expect(screen.getAllByText('alpha').length).toBeGreaterThan(0);
    expect(screen.getAllByText('bravo').length).toBeGreaterThan(0);
    expect(screen.queryByTestId('operations-back-to-list')).not.toBeInTheDocument();
  });

  it('gives the whole page to a repository when one is clicked', () => {
    render(<OperationsWorkspaceView operationsRepos={payload('alpha', 'bravo')} loading={false} onRefresh={noop} />);

    fireEvent.click(screen.getAllByText('alpha')[0]);

    // The way back exists, and it names the repository that has the page.
    const back = screen.getByTestId('operations-back-to-list');
    expect(back).toBeInTheDocument();
    expect(back).toHaveTextContent('All repositories');
  });

  it('returns to the picker, which is the part collapsing-on-selection could not do', () => {
    render(<OperationsWorkspaceView operationsRepos={payload('alpha', 'bravo')} loading={false} onRefresh={noop} />);

    fireEvent.click(screen.getAllByText('alpha')[0]);
    expect(screen.getByTestId('operations-back-to-list')).toBeInTheDocument();

    fireEvent.click(screen.getByTestId('operations-back-to-list'));
    expect(screen.queryByTestId('operations-back-to-list')).not.toBeInTheDocument();
    expect(screen.getAllByText('bravo').length).toBeGreaterThan(0);
  });
});

// ── Release 3.8 M4 (H38-25) — approve the SHA you see ───────────────────────
// A pull request keeps its number across a force-push. An operator looking at
// "Ready to merge" is therefore reading a claim about a COMMIT, and the screen
// has to say which one -- otherwise approving is an act of faith in a number
// that outlived the rewrite invalidating it.
const baseEvidence = {
  prState: 'open',
  prDraft: false,
  mergeable: true,
  mergeableState: 'clean',
  actionsStatus: 'completed',
  actionsConclusion: 'success',
  actionsWorkflowName: 'CI',
  verifiedHeadSha: null as string | null,
  approvedSha: null as string | null,
  currentHeadSha: null as string | null,
  localDirtyCount: 0,
  auditBlockerCount: 0,
};

function readiness(evidenceOver: Record<string, unknown> = {}, over: Record<string, unknown> = {}) {
  return {
    repoId: 'repo:alpha',
    repoName: 'alpha',
    runId: 'run-1',
    prUrl: 'https://github.com/o/alpha/pull/4',
    prNumber: 4,
    ready: false,
    blockers: [],
    evidence: { ...baseEvidence, ...evidenceOver },
    evaluatedAt: '2026-09-08T00:00:00Z',
    ...over,
  };
}

async function focusAlphaWith(evaluation: unknown) {
  vi.mocked(getMergeReadiness).mockResolvedValue(evaluation as never);
  render(<OperationsWorkspaceView operationsRepos={payload('alpha', 'bravo')} loading={false} onRefresh={noop} />);
  fireEvent.click(screen.getAllByText('alpha')[0]);
  await waitFor(() => expect(screen.getByTestId('merge-verified-head')).toBeInTheDocument());
}

describe('OperationsWorkspaceView — approval names a commit', () => {
  it('says so plainly when no commit has been verified', async () => {
    await focusAlphaWith(readiness());

    expect(screen.getByTestId('merge-verified-head')).toHaveTextContent('Not yet verified');
    // Nothing to approve, so nothing offering to.
    expect(screen.queryByTestId('merge-approve-button')).not.toBeInTheDocument();
  });

  it('offers to approve the verified commit, by name', async () => {
    await focusAlphaWith(readiness({ verifiedHeadSha: 'abcdef1234567890' }));

    expect(screen.getByTestId('merge-verified-head')).toHaveTextContent('Verified head: abcdef1');
    const approve = screen.getByTestId('merge-approve-button');
    expect(approve).toHaveTextContent('Approve abcdef1');

    fireEvent.click(approve);
    // The runId and the exact sha, never "whatever is current" -- the server
    // refuses anything else, and sending the seen value is what makes that
    // refusal a safeguard rather than a formality.
    await waitFor(() => expect(vi.mocked(approveAgentRun)).toHaveBeenCalledWith('run-1', 'abcdef1234567890'));
  });

  it('shows the approval once it exists, and stops offering to make it again', async () => {
    await focusAlphaWith(readiness(
      { verifiedHeadSha: 'abcdef1234567890', approvedSha: 'abcdef1234567890', currentHeadSha: 'abcdef1234567890' },
      { ready: true },
    ));

    expect(screen.getByTestId('merge-approved')).toHaveTextContent('Approved abcdef1');
    expect(screen.queryByTestId('merge-approve-button')).not.toBeInTheDocument();
    expect(screen.getByTestId('merge-pr-button')).not.toBeDisabled();
  });

  it('disables the merge when the head moved out from under the approval', async () => {
    await focusAlphaWith(readiness(
      { verifiedHeadSha: 'abcdef1234567890', approvedSha: 'abcdef1234567890', currentHeadSha: '9999999999999999' },
      { ready: true },
    ));

    const merge = screen.getByTestId('merge-pr-button');
    expect(merge).toBeDisabled();
    expect(merge).toHaveAttribute('title', 'Head moved since approval');
    expect(screen.getByTestId('merge-head-drifted')).toBeInTheDocument();
  });
});
