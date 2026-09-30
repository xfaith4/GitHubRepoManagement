import { describe, it, expect } from 'vitest';
import { buildHoldGroups, describeHoldCount, groupHoldsByRepo } from './repoHolds';

const clean = {
  repoId: 'r1',
  repoName: 'alpha',
  hasReadme: true,
  hasRoadmap: true,
  roadmapState: 'pending' as const,
  localDirtyCount: 0,
  dispatchReadiness: 'ready' as const,
  executionState: 'idle' as const,
};

describe('buildHoldGroups — every hold names its rule and its reason', () => {
  it('finds nothing to hold on a clean repository', () => {
    const g = buildHoldGroups([clean]);
    expect(g.blocking).toHaveLength(0);
    expect(g.actionable).toHaveLength(0);
    expect(g.ambient).toHaveLength(0);
  });

  it('holds a dirty tree as actionable and marks it always-held', () => {
    const g = buildHoldGroups([{ ...clean, localDirtyCount: 1993 }]);
    expect(g.actionable).toHaveLength(1);
    const hold = g.actionable[0];
    expect(hold.rule).toBe('working-tree-dirty');
    expect(hold.reason).toContain('1993 uncommitted files');
    expect(hold.reason).toContain('destructive');
    expect(hold.alwaysHeld).toBe(true);
  });

  it('puts a missing roadmap in the quiet ambient list, always held', () => {
    const g = buildHoldGroups([{ ...clean, roadmapState: 'missing' }]);
    expect(g.actionable).toHaveLength(0);
    expect(g.ambient).toHaveLength(1);
    expect(g.ambient[0].rule).toBe('roadmap-missing');
    expect(g.ambient[0].reason).toContain('authors a new contract');
    expect(g.ambient[0].alwaysHeld).toBe(true);
  });

  it('promotes ANY hold to blocking when the repository occupies a lane', () => {
    // An ambient gap on a repo that is mid-run is no longer ambient — it is
    // the reason the lane is not moving, so it must never be collapsed.
    const g = buildHoldGroups([{ ...clean, roadmapState: 'missing', executionState: 'running' }]);
    expect(g.ambient).toHaveLength(0);
    expect(g.blocking).toHaveLength(1);
    expect(g.blocking[0].rule).toBe('roadmap-missing');
  });

  it('treats an explicitly blocked execution state as blocking', () => {
    const g = buildHoldGroups([{ ...clean, localDirtyCount: 3, executionState: 'blocked' }]);
    expect(g.blocking).toHaveLength(1);
    expect(g.actionable).toHaveLength(0);
  });

  it('carries the dispatch check its own explanation', () => {
    const g = buildHoldGroups([{
      ...clean,
      dispatchReadiness: 'blocked',
      dispatchReadinessExplanation: 'Stage 1 is incomplete.',
    }]);
    expect(g.actionable[0].reason).toBe('Stage 1 is incomplete.');
  });

  it('names a missing explanation as the defect rather than inventing one', () => {
    const g = buildHoldGroups([{ ...clean, dispatchReadiness: 'blocked' }]);
    expect(g.actionable[0].reason).toContain('did not record why');
  });

  it('never describes a no-checklist roadmap as damaged', () => {
    const g = buildHoldGroups([{ ...clean, roadmapState: 'no-checklist' }]);
    expect(g.actionable[0].reason).toContain('sound');
    expect(g.actionable[0].reason).not.toMatch(/parse|unreadable|damaged|broken/i);
  });

  it('reports CI red with the workflow that failed', () => {
    const g = buildHoldGroups([{
      ...clean,
      latestWorkflowRunConclusion: 'failure',
      latestWorkflowRunName: 'smoke',
    }]);
    expect(g.actionable[0].rule).toBe('ci-red');
    expect(g.actionable[0].reason).toContain('(smoke)');
  });
});

describe('groupHoldsByRepo — one card per repository', () => {
  it('folds every code a repository carries into one card', () => {
    // The Release 4.0 defect: one running repository with four hold codes
    // rendered four "Blocking a lane" cards.
    const g = buildHoldGroups([
      {
        ...clean,
        executionState: 'running',
        localDirtyCount: 3,
        latestWorkflowRunConclusion: 'failure',
        roadmapState: 'parse-error',
        dispatchReadiness: 'blocked',
        dispatchReadinessExplanation: 'blocked for a reason',
      },
      { ...clean, repoId: 'r2', repoName: 'bravo', executionState: 'running', localDirtyCount: 1 },
    ]);
    expect(g.blocking).toHaveLength(5);
    const cards = groupHoldsByRepo(g.blocking);
    expect(cards.map(c => c.repoName)).toEqual(['alpha', 'bravo']);
    expect(cards[0].holds.map(h => h.rule)).toEqual(['working-tree-dirty', 'ci-red', 'roadmap-parse-error', 'dispatch-blocked']);
    expect(cards[0].alwaysHeld).toBe(true);
    expect(cards[0].severity).toBe('blocking');
  });

  it('is empty for no holds', () => {
    expect(groupHoldsByRepo([])).toEqual([]);
  });
});

describe('describeHoldCount', () => {
  it('agrees with itself in the singular', () => {
    expect(describeHoldCount(1)).toBe('1 needs you');
    expect(describeHoldCount(4)).toBe('4 need you');
  });
});
