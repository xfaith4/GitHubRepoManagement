import { describe, it, expect } from 'vitest';
import { assessUnattendedReadiness, describeAssessedAt } from './unattendedReadiness';

const ready = {
  hasReadme: true,
  hasRoadmap: true,
  roadmapState: 'pending' as const,
  localDirtyCount: 0,
  hasCiSignal: true,
};

describe('assessUnattendedReadiness — measures whether an agent can work unasked', () => {
  it('counts four ready checks when everything an agent needs is present', () => {
    const r = assessUnattendedReadiness(ready);
    expect(r.ready).toBe(4);
    expect(r.measured).toBe(4);
    expect(r.summary).toBe('4 of 4 ready');
  });

  it('names the missing document rather than scoring it away', () => {
    const r = assessUnattendedReadiness({ ...ready, hasReadme: false });
    const docs = r.factors.find(f => f.key === 'docs');
    expect(docs?.state).toBe('not-ready');
    expect(docs?.detail).toContain('README.md is missing');
    expect(r.ready).toBe(3);
  });

  it('treats an absent CI signal as unmeasured, never as a failure', () => {
    const r = assessUnattendedReadiness({ ...ready, hasCiSignal: undefined });
    const ci = r.factors.find(f => f.key === 'ci');
    expect(ci?.state).toBe('unmeasured');
    // The denominator drops to what actually ran — 3 of 3, not 3 of 4.
    expect(r.summary).toBe('3 of 3 ready · ci present unmeasured');
    expect(r.ready).toBe(3);
    expect(r.measured).toBe(3);
  });

  it('says nothing has been measured rather than reporting zero', () => {
    const r = assessUnattendedReadiness({});
    expect(r.ready).toBe(0);
    expect(r.measured).toBe(0);
    expect(r.summary).toBe('unmeasured — no check has run for this repository');
  });

  it('never calls a no-checklist roadmap damaged', () => {
    const r = assessUnattendedReadiness({ ...ready, roadmapState: 'no-checklist' });
    const roadmap = r.factors.find(f => f.key === 'roadmap-machine-readable');
    expect(roadmap?.state).toBe('not-ready');
    expect(roadmap?.detail).toContain('sound');
    expect(roadmap?.detail).not.toMatch(/parse|unreadable|damaged|broken/i);
  });

  it('reports a parse error as a parse error', () => {
    const r = assessUnattendedReadiness({ ...ready, roadmapState: 'parse-error' });
    const roadmap = r.factors.find(f => f.key === 'roadmap-machine-readable');
    expect(roadmap?.detail).toContain('could not be parsed');
  });

  it('counts a dirty tree as not ready and says how dirty', () => {
    const r = assessUnattendedReadiness({ ...ready, localDirtyCount: 1993 });
    const tree = r.factors.find(f => f.key === 'clean-tree');
    expect(tree?.state).toBe('not-ready');
    expect(tree?.detail).toContain('1993 uncommitted files');
  });

  it('will not call an unread working tree clean', () => {
    const r = assessUnattendedReadiness({ ...ready, localDirtyCount: undefined });
    expect(r.factors.find(f => f.key === 'clean-tree')?.state).toBe('unmeasured');
  });
});

describe('describeAssessedAt — a fact beside the score, not a warning', () => {
  it('states the age when it is known', () => {
    expect(describeAssessedAt({ indexGeneratedAt: '2026-09-01T00:00:00Z', indexAgeHours: 5 }))
      .toBe('assessed 5 hours ago');
  });

  it('rolls over to days', () => {
    expect(describeAssessedAt({ indexGeneratedAt: '2026-08-20T00:00:00Z', indexAgeHours: 72 }))
      .toBe('assessed 3 days ago');
  });

  it('admits when the time was never recorded', () => {
    expect(describeAssessedAt(null)).toBe('assessed — time not recorded');
    expect(describeAssessedAt({ indexGeneratedAt: null, indexAgeHours: null }))
      .toBe('assessed — time not recorded');
  });
});
