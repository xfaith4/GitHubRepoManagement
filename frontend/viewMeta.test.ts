import { describe, it, expect } from 'vitest';
import { VIEW_META, VIEW_META_BY_KEY, type ViewKey } from './viewMeta';

const EXPECTED_KEYS: ViewKey[] = [
  // Release 3.6 M3 — `today` leads: it is the default landing, and the tab
  // order is the order an operator should consider the views in.
  'today',
  'repos',
  'insights',
  'operations',
  'work-queue',
  'execution-queue',
  'dependencies',
];

describe('viewMeta — the single source of truth for the view tabs', () => {
  it('defines exactly the expected views in order, with the Today landing first', () => {
    expect(VIEW_META.map(v => v.key)).toEqual(EXPECTED_KEYS);
    expect(VIEW_META[0].key).toBe('today');
  });

  it('gives every view a non-empty label, short label, and subtitle', () => {
    for (const v of VIEW_META) {
      expect(v.label.length).toBeGreaterThan(0);
      expect(v.short.length).toBeGreaterThan(0);
      expect(v.subtitle.length).toBeGreaterThan(0);
    }
  });

  it('poses a question for every view — a label names a place, a question names the reason to go there', () => {
    for (const v of VIEW_META) {
      expect(v.question.length).toBeGreaterThan(0);
      expect(v.question.trim().endsWith('?')).toBe(true);
      // The question must not merely restate the label.
      expect(v.question.toLowerCase()).not.toBe(v.label.toLowerCase());
    }
    expect(new Set(VIEW_META.map(v => v.question)).size).toBe(VIEW_META.length);
    expect(VIEW_META_BY_KEY['today'].question).toBe('What should I do next, and why?');
  });

  it('renamed the two colliding queues to distinct, self-describing names', () => {
    expect(VIEW_META_BY_KEY['work-queue'].label).toBe('Doc Readiness Queue');
    // Lane 0.17 — the dispatch ledger is a board, not an execution monitor;
    // the label must not claim telemetry the page does not have.
    expect(VIEW_META_BY_KEY['execution-queue'].label).toBe('Dispatch Board');
    // The old ambiguous names must be gone.
    const labels = VIEW_META.map(v => v.label);
    expect(labels).not.toContain('Work Queue');
    expect(labels).not.toContain('Execution Queue');
    expect(labels).not.toContain('Copilot Execution Lanes');
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
