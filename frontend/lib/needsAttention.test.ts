import { describe, it, expect } from 'vitest';
import { isRepoNeedsAttention, type NeedsAttentionInput } from './needsAttention';

// A clean baseline repo that should NOT need attention (the ambient state most
// of the portfolio is in).
const clean: NeedsAttentionInput = {
  status: 'clean',
  uncommittedChanges: 0,
  lastBuildStatus: 'success',
  dispatchReadiness: 'ready',
  roadmapState: 'pending',
};

describe('isRepoNeedsAttention — acute problems flag', () => {
  it('flags a dirty working tree', () => {
    expect(isRepoNeedsAttention({ ...clean, status: 'dirty' })).toBe(true);
  });

  it('flags uncommitted changes even when status is clean', () => {
    expect(isRepoNeedsAttention({ ...clean, uncommittedChanges: 3 })).toBe(true);
  });

  it('flags a failing build', () => {
    expect(isRepoNeedsAttention({ ...clean, lastBuildStatus: 'failure' })).toBe(true);
  });

  it('flags blocked or parse-error dispatch readiness', () => {
    expect(isRepoNeedsAttention({ ...clean, dispatchReadiness: 'blocked' })).toBe(true);
    expect(isRepoNeedsAttention({ ...clean, dispatchReadiness: 'parse-error' })).toBe(true);
  });

  it('flags an unparseable roadmap', () => {
    expect(isRepoNeedsAttention({ ...clean, roadmapState: 'parse-error' })).toBe(true);
  });

  it('flags a sound roadmap that records no checklist items', () => {
    // Actionable, but for a different reason than an unreadable file: there is
    // nothing to rank or dispatch until its plan becomes '- [ ]' items.
    expect(isRepoNeedsAttention({ ...clean, roadmapState: 'no-checklist' })).toBe(true);
    expect(isRepoNeedsAttention({ ...clean, dispatchReadiness: 'no-checklist' })).toBe(true);
  });
});

describe('isRepoNeedsAttention — ambient conditions do NOT flag', () => {
  it('does not flag a fully clean repo', () => {
    expect(isRepoNeedsAttention(clean)).toBe(false);
  });

  it('does not flag "no CI configured" (lastBuildStatus none)', () => {
    expect(isRepoNeedsAttention({ ...clean, lastBuildStatus: 'none' })).toBe(false);
  });

  it('does not flag a merely-pending roadmap', () => {
    expect(isRepoNeedsAttention({ ...clean, roadmapState: 'pending' })).toBe(false);
  });

  it('does not flag baseline doc gaps (missing-roadmap / needs-doc-standardization)', () => {
    expect(isRepoNeedsAttention({ ...clean, dispatchReadiness: 'missing-roadmap' })).toBe(false);
    expect(isRepoNeedsAttention({ ...clean, dispatchReadiness: 'needs-doc-standardization' })).toBe(false);
  });

  it('tolerates undefined optional fields', () => {
    expect(isRepoNeedsAttention({})).toBe(false);
  });
});
