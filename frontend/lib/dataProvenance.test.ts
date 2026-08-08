import { describe, it, expect } from 'vitest';
import {
  resolveProvenance,
  canRunRepoActions,
  repoActionsBlockedReason,
  isKnownEmptyScope,
  isCarriedOverCount,
} from './dataProvenance';

// Fixed formatter so assertions do not depend on the runner's locale.
const fmt = (iso: string) => `FORMATTED:${iso}`;

describe('resolveProvenance', () => {
  it('reports "live" whenever the current scan found repositories', () => {
    const p = resolveProvenance({ liveRepoCount: 47, persistedEntryCount: 25 }, fmt);
    expect(p.state).toBe('live');
    expect(p.isMismatch).toBe(false);
    expect(p.message).toBeNull();
  });

  it('reports "live" even when persisted indexes are empty', () => {
    // A first scan that has not yet written an index is not a mismatch.
    const p = resolveProvenance({ liveRepoCount: 3, persistedEntryCount: 0 }, fmt);
    expect(p.state).toBe('live');
    expect(p.isMismatch).toBe(false);
  });

  it('reports "empty" when neither source has anything', () => {
    const p = resolveProvenance({ liveRepoCount: 0, persistedEntryCount: 0 }, fmt);
    expect(p.state).toBe('empty');
    expect(p.isMismatch).toBe(false);
    expect(p.message).toBeNull();
  });

  it('flags the mismatch that made the portal look broken: 0 live, populated index', () => {
    const p = resolveProvenance(
      { liveRepoCount: 0, persistedEntryCount: 25, persistedGeneratedAt: '2026-08-01T10:00:00Z' },
      fmt
    );
    expect(p.state).toBe('stale-only');
    expect(p.isMismatch).toBe(true);
    expect(p.message).toContain('25 entries');
    expect(p.message).toContain('FORMATTED:2026-08-01T10:00:00Z');
    expect(p.message).toContain('re-scan');
  });

  it('singularizes a one-entry carryover', () => {
    const p = resolveProvenance({ liveRepoCount: 0, persistedEntryCount: 1 }, fmt);
    expect(p.message).toContain('1 entry');
    expect(p.message).not.toContain('1 entries');
  });

  it('omits the timestamp clause when generatedAt is unknown', () => {
    const p = resolveProvenance({ liveRepoCount: 0, persistedEntryCount: 4 }, fmt);
    expect(p.isMismatch).toBe(true);
    expect(p.message).toContain('from the last completed scan');
    expect(p.message).not.toContain('FORMATTED');
  });

  it('treats negative counts as zero rather than producing a false mismatch', () => {
    expect(resolveProvenance({ liveRepoCount: -1, persistedEntryCount: -5 }, fmt).state).toBe('empty');
  });

  it('never warns when the live count is unknown (undefined / NaN prop)', () => {
    // A false "carried-over data" banner over correct figures is worse than none.
    const undef = resolveProvenance(
      { liveRepoCount: undefined as unknown as number, persistedEntryCount: 25 },
      fmt
    );
    expect(undef.isMismatch).toBe(false);
    expect(resolveProvenance({ liveRepoCount: NaN, persistedEntryCount: 25 }, fmt).isMismatch).toBe(false);
  });

  it('treats an unknown persisted count as zero', () => {
    const p = resolveProvenance(
      { liveRepoCount: 0, persistedEntryCount: undefined as unknown as number },
      fmt
    );
    expect(p.state).toBe('empty');
  });

  it('defaults to the raw ISO string when no formatter is injected', () => {
    const p = resolveProvenance({
      liveRepoCount: 0,
      persistedEntryCount: 2,
      persistedGeneratedAt: '2026-08-01T10:00:00Z',
    });
    expect(p.message).toContain('2026-08-01T10:00:00Z');
  });
});

describe('canRunRepoActions', () => {
  it('allows repo actions when repos are in scope and nothing is running', () => {
    expect(canRunRepoActions(12, false)).toBe(true);
  });

  it('blocks repo actions with no repositories in scope', () => {
    expect(canRunRepoActions(0, false)).toBe(false);
  });

  it('blocks repo actions while another operation is running', () => {
    expect(canRunRepoActions(12, true)).toBe(false);
  });
});

describe('isKnownEmptyScope', () => {
  it('is true only for a known zero', () => {
    expect(isKnownEmptyScope(0)).toBe(true);
  });

  it('is false for a populated scope', () => {
    expect(isKnownEmptyScope(7)).toBe(false);
  });

  it('is false when the count is unknown, so nothing gets disabled by omission', () => {
    expect(isKnownEmptyScope(undefined)).toBe(false);
    expect(isKnownEmptyScope(NaN)).toBe(false);
  });
});

describe('isCarriedOverCount', () => {
  it('flags a populated badge count under a known-empty live scope', () => {
    expect(isCarriedOverCount(0, 15)).toBe(true);
  });

  it('does not flag a zero badge count', () => {
    expect(isCarriedOverCount(0, 0)).toBe(false);
  });

  it('does not flag when the live scan found repos', () => {
    expect(isCarriedOverCount(40, 15)).toBe(false);
  });

  it('does not flag when the live count is unknown', () => {
    expect(isCarriedOverCount(undefined, 15)).toBe(false);
  });
});

describe('repoActionsBlockedReason', () => {
  it('explains the real blocker when nothing is in scope', () => {
    expect(repoActionsBlockedReason(0)).toMatch(/Scan a workspace first/);
  });

  it('returns null when actions are available', () => {
    expect(repoActionsBlockedReason(5)).toBeNull();
  });
});
