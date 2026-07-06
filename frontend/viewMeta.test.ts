import { describe, it, expect } from 'vitest';
import { VIEW_META, VIEW_META_BY_KEY, type ViewKey } from './viewMeta';

const EXPECTED_KEYS: ViewKey[] = [
  'repos',
  'insights',
  'operations',
  'work-queue',
  'execution-queue',
  'dependencies',
];

describe('viewMeta — the six-view single source of truth', () => {
  it('defines exactly the six expected views in order', () => {
    expect(VIEW_META.map(v => v.key)).toEqual(EXPECTED_KEYS);
  });

  it('gives every view a non-empty label, short label, and subtitle', () => {
    for (const v of VIEW_META) {
      expect(v.label.length).toBeGreaterThan(0);
      expect(v.short.length).toBeGreaterThan(0);
      expect(v.subtitle.length).toBeGreaterThan(0);
    }
  });

  it('renamed the two colliding queues to distinct, self-describing names', () => {
    expect(VIEW_META_BY_KEY['work-queue'].label).toBe('Doc Readiness Queue');
    expect(VIEW_META_BY_KEY['execution-queue'].label).toBe('Copilot Execution Lanes');
    // The old ambiguous names must be gone.
    const labels = VIEW_META.map(v => v.label);
    expect(labels).not.toContain('Work Queue');
    expect(labels).not.toContain('Execution Queue');
  });

  it('has unique labels and unique keys', () => {
    expect(new Set(VIEW_META.map(v => v.key)).size).toBe(VIEW_META.length);
    expect(new Set(VIEW_META.map(v => v.label)).size).toBe(VIEW_META.length);
  });

  it('by-key lookup is consistent with the array', () => {
    for (const v of VIEW_META) {
      expect(VIEW_META_BY_KEY[v.key]).toBe(v);
    }
  });
});
