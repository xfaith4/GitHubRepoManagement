import { describe, it, expect } from 'vitest';
import {
  bulkActionDisabledReason,
  bulkConfirmationMessage,
  isMutatingBulkAction,
  requiresBulkConfirmation,
  type BulkActionKind,
} from './bulkScope';

describe('isMutatingBulkAction', () => {
  it('classifies the two git write actions as mutating', () => {
    expect(isMutatingBulkAction('update')).toBe(true);
    expect(isMutatingBulkAction('sync')).toBe(true);
  });

  it('classifies the read-only actions as non-mutating', () => {
    expect(isMutatingBulkAction('export')).toBe(false);
    expect(isMutatingBulkAction('docreview')).toBe(false);
    expect(isMutatingBulkAction('roadmap-scan')).toBe(false);
  });
});

describe('requiresBulkConfirmation', () => {
  // The case the guard exists for: one click, nothing selected, 75 repos.
  it('confirms a mutating action with nothing selected', () => {
    expect(requiresBulkConfirmation('update', 0, 75)).toBe(true);
    expect(requiresBulkConfirmation('sync', 0, 75)).toBe(true);
  });

  // An explicit selection IS the operator naming the scope. Re-asking adds
  // friction with no information in it, which is how confirmations get ignored.
  it('does not confirm when the operator selected rows explicitly', () => {
    expect(requiresBulkConfirmation('update', 1, 75)).toBe(false);
    expect(requiresBulkConfirmation('update', 75, 75)).toBe(false);
  });

  // Settled 2026-08-10: Report is read-only and reversible, so it keeps its
  // single click. Spending the dialog here would devalue the one that matters.
  it('never confirms a read-only action, however large the scope', () => {
    expect(requiresBulkConfirmation('export', 0, 999)).toBe(false);
    expect(requiresBulkConfirmation('docreview', 0, 999)).toBe(false);
    expect(requiresBulkConfirmation('roadmap-scan', 0, 999)).toBe(false);
  });

  it('does not confirm when nothing is in scope', () => {
    expect(requiresBulkConfirmation('update', 0, 0)).toBe(false);
  });

  // No threshold: two repositories is still two working trees the operator did
  // not name. The rule is "mutating + implicit", not "mutating + big".
  it('confirms even a small implicit scope', () => {
    expect(requiresBulkConfirmation('update', 0, 1)).toBe(true);
    expect(requiresBulkConfirmation('update', 0, 2)).toBe(true);
  });
});

describe('bulkConfirmationMessage', () => {
  it('names the command and the count', () => {
    const message = bulkConfirmationMessage('update', 47);
    expect(message).toContain('git pull');
    expect(message).toContain('47 repositories');
  });

  it('names the fetch command distinctly', () => {
    expect(bulkConfirmationMessage('sync', 12)).toContain('git fetch --all --prune');
  });

  it('uses the singular for one repository', () => {
    const message = bulkConfirmationMessage('update', 1);
    expect(message).toContain('1 repository');
    expect(message).not.toContain('1 repositories');
  });

  // "Are you sure?" without a number is the dialog people learn to click
  // through. The count is the whole point of showing it.
  it('always carries a number', () => {
    for (const action of ['update', 'sync'] as BulkActionKind[]) {
      expect(bulkConfirmationMessage(action, 8)).toMatch(/\b8\b/);
    }
  });
});

// Release 3.5 milestone 7 - empty selection no longer means "everything".
describe('bulkActionDisabledReason', () => {
  it('disables a mutating action with no selection, naming the remedy', () => {
    const reason = bulkActionDisabledReason('update', 0, 75);
    expect(reason).toContain('Select repositories first');
    expect(reason).toContain('git pull');
  });

  it('allows a mutating action once anything is selected', () => {
    expect(bulkActionDisabledReason('sync', 1, 75)).toBeNull();
  });

  it('never disables read-only actions', () => {
    expect(bulkActionDisabledReason('export', 0, 75)).toBeNull();
    expect(bulkActionDisabledReason('roadmap-scan', 0, 75)).toBeNull();
  });
});
