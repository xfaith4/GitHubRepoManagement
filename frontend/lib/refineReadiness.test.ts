import { describe, it, expect } from 'vitest';
import { canRefinePrompt, describeRefineBlocker, type RefineReadinessInput } from './refineReadiness';

const entry = (over: Partial<RefineReadinessInput> = {}): RefineReadinessInput => ({
  hasRoadmap: true,
  roadmapState: 'pending',
  pendingCount: 4,
  ...over,
});

describe('describeRefineBlocker — the reason has to be the real one', () => {
  it('lets a roadmap with pending work through', () => {
    expect(describeRefineBlocker(entry())).toBeNull();
    expect(canRefinePrompt(entry())).toBe(true);
  });

  it('never tells a repo with a roadmap that it has none', () => {
    // The reported case: CupHandleDetectionv2 has a 179-line ROADMAP.md written
    // as tables rather than checkboxes. Saying "does not have a roadmap" sends
    // the operator to create a file that already exists.
    const blocked = describeRefineBlocker(entry({ roadmapState: 'no-checklist', pendingCount: 0 }));
    expect(blocked).not.toBeNull();
    expect(blocked).not.toMatch(/has no ROADMAP\.md/);
    expect(blocked).toMatch(/checklist items/);
    expect(blocked).toMatch(/repair preview/);
  });

  it('separates a sound roadmap without checklist items from an unreadable file', () => {
    // These two used to be one state, and the shared sentence told the operator
    // a 216 KB working roadmap 'could not be parsed'. Each now names its own
    // next action: convert the plan, or fix the file.
    const noChecklist = describeRefineBlocker(entry({ roadmapState: 'no-checklist', pendingCount: 0 }));
    const unreadable = describeRefineBlocker(entry({ roadmapState: 'parse-error', pendingCount: 0 }));
    expect(noChecklist).not.toBe(unreadable);
    expect(noChecklist).toMatch(/checklist items/);
    expect(noChecklist).toMatch(/repair preview/);
    expect(noChecklist).not.toMatch(/could not be read/);
    expect(unreadable).toMatch(/could not be read/);
    expect(unreadable).not.toMatch(/repair preview/);
  });

  it('says "no roadmap" only when there is genuinely no roadmap', () => {
    for (const missing of [entry({ hasRoadmap: false }), entry({ roadmapState: 'missing' })]) {
      expect(describeRefineBlocker(missing)).toMatch(/has no ROADMAP\.md/);
    }
  });

  it('distinguishes a finished roadmap from an unreadable one', () => {
    const done = describeRefineBlocker(entry({ roadmapState: 'complete', pendingCount: 0 }));
    expect(done).toMatch(/complete/);
    expect(done).not.toMatch(/checklist items/);
    expect(done).not.toMatch(/has no ROADMAP\.md/);
  });

  it('still blocks a parsed roadmap that yielded no pending item', () => {
    expect(describeRefineBlocker(entry({ pendingCount: 0 }))).toMatch(/no pending item/);
    expect(describeRefineBlocker(entry({ pendingCount: null }))).toMatch(/no pending item/);
    expect(canRefinePrompt(entry({ pendingCount: 0 }))).toBe(false);
  });

  it('gives every blocked state a distinct sentence, so the next action differs', () => {
    const reasons = [
      describeRefineBlocker(entry({ hasRoadmap: false })),
      describeRefineBlocker(entry({ roadmapState: 'no-checklist', pendingCount: 0 })),
      describeRefineBlocker(entry({ roadmapState: 'parse-error', pendingCount: 0 })),
      describeRefineBlocker(entry({ roadmapState: 'complete', pendingCount: 0 })),
      describeRefineBlocker(entry({ pendingCount: 0 })),
    ];
    expect(new Set(reasons).size).toBe(reasons.length);
    for (const reason of reasons) expect(reason && reason.length).toBeGreaterThan(30);
  });

  it('treats an absent entry as nothing to say rather than a blocker', () => {
    expect(describeRefineBlocker(null)).toBeNull();
    expect(describeRefineBlocker(undefined)).toBeNull();
    expect(canRefinePrompt(null)).toBe(false);
  });
});
