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
import { render, screen, fireEvent, cleanup } from '@testing-library/react';
import '@testing-library/jest-dom/vitest';
import React from 'react';
import type { OperationsReposResult, OperationsRepoEntry } from '../types';

vi.mock('../services/apiClient', () => ({
  getRunnerPresence: vi.fn().mockResolvedValue({ present: false, runs: [] }),
  getAiDocTemplates: vi.fn().mockResolvedValue({ templates: [] }),
  getOperationsRepoDetail: vi.fn().mockResolvedValue(null),
  getOperationsPromptHistory: vi.fn().mockResolvedValue({ entries: [] }),
  getAiDocImprovementHistory: vi.fn().mockResolvedValue({ entries: [] }),
  getAgentRuns: vi.fn().mockResolvedValue({ runs: [] }),
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
  executeRoadmapDispatch: vi.fn(),
}));

import OperationsWorkspaceView from './OperationsWorkspaceView';

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
