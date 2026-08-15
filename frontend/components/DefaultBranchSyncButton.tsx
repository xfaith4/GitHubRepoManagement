import React, { useState } from 'react';
import { syncDefaultBranch, type DefaultBranchSyncResult } from '../services/apiClient';

/**
 * Release 3.4 milestone 1, step 10 — the operator-facing control for
 * `Sync-RepoDefaultBranch`.
 *
 * Release 3.1 shipped a guard that refuses to branch from a stale clone, and
 * PR #134 shipped the operation that fixes one. Until this control existed the
 * operator could be told "your clone is 8 commits behind, run git pull" by a
 * product that could perform exactly that operation and offered no way to ask
 * for it.
 *
 * The component holds no policy of its own. `behind` fast-forwards; every other
 * state refuses with the module's own category and remedy, rendered verbatim —
 * a refusal here is information, not an error, which is why it renders inline
 * rather than as a thrown failure.
 */
interface DefaultBranchSyncButtonProps {
  repoName?: string;
  repoPath?: string;
  /** Called after a sync that actually moved the branch, so the caller can reload. */
  onSynced?: () => void;
  className?: string;
}

type Phase = 'idle' | 'syncing' | 'done';

const DefaultBranchSyncButton = ({ repoName, repoPath, onSynced, className }: DefaultBranchSyncButtonProps) => {
  const [phase, setPhase] = useState<Phase>('idle');
  const [result, setResult] = useState<DefaultBranchSyncResult | null>(null);
  const [error, setError] = useState<string | null>(null);

  const disabled = phase === 'syncing' || (!repoName && !repoPath);

  const run = async () => {
    setPhase('syncing');
    setError(null);
    setResult(null);
    try {
      // Clicking the control IS the approval — the operator asked for this
      // transition explicitly. The flag stays an input rather than a default so
      // that a caller which has not asked still refuses as `approval-required`.
      const r = await syncDefaultBranch({ repoName, repoPath }, true);
      setResult(r);
      if (r.synced && r.toSha && r.toSha !== r.fromSha) {
        onSynced?.();
      }
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setPhase('done');
    }
  };

  return (
    <div className={className}>
      <button
        type="button"
        onClick={run}
        disabled={disabled}
        data-testid="sync-default-branch"
        // A disabled control names its unmet precondition (Release 3.1
        // guardrail): without a repo there is nothing to sync.
        title={
          !repoName && !repoPath
            ? 'No repository selected — nothing to sync.'
            : 'Fetch and fast-forward the default branch. Only a branch that is behind can move; nothing is merged, rebased or forced.'
        }
        className="px-3 py-1.5 text-sm rounded border border-gray-600 text-gray-300 hover:text-white hover:border-gray-400 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
      >
        {phase === 'syncing' ? 'Syncing…' : 'Sync default branch'}
      </button>

      {error && (
        <p data-testid="sync-error" className="mt-2 text-xs text-red-300">
          {error}
        </p>
      )}

      {result && !error && (
        <p
          data-testid={result.refused ? 'sync-refused' : 'sync-ok'}
          className={`mt-2 text-xs ${result.refused ? 'text-amber-300' : 'text-emerald-300'}`}
        >
          {/* Status is not carried by colour alone — the category is named in
              text, so a screen reader and a monochrome display both get it. */}
          <span className="font-semibold">{result.refused ? `Refused (${result.category})` : 'Synced'}</span>
          {' — '}
          {result.reason}
          {result.refused && result.remedy ? ` ${result.remedy}` : ''}
        </p>
      )}
    </div>
  );
};

export default DefaultBranchSyncButton;
