import React, { useState, useEffect, useCallback } from 'react';
import { type RepoGitStatusDetail, type GitStatusFile, type GitCommitRef } from '../types';
import { getRepoGitStatusDetail, stashRepoChanges, discardRepoChanges, startUpdate } from '../services/apiClient';
import { SpinnerIcon } from './icons';
import DefaultBranchSyncButton from './DefaultBranchSyncButton';

// ── Types ─────────────────────────────────────────────────────────────────────

interface RepoGitStatusModalProps {
  isOpen: boolean;
  repoName: string | null;
  localPath?: string | null;
  onClose: () => void;
  onStatusChanged?: () => void;
}

type Phase = 'idle' | 'loading' | 'loaded' | 'acting' | 'error';

type DiscardMode = 'tracked' | 'all';

// ── Status badge helpers ──────────────────────────────────────────────────────

function statusBadge(status: string) {
  const cfg: Record<string, { cls: string; label: string }> = {
    M: { cls: 'bg-yellow-800/70 text-yellow-200', label: 'M' },
    A: { cls: 'bg-green-800/70 text-green-200',  label: 'A' },
    D: { cls: 'bg-red-800/70 text-red-200',      label: 'D' },
    R: { cls: 'bg-blue-800/70 text-blue-200',    label: 'R' },
    C: { cls: 'bg-blue-800/70 text-blue-200',    label: 'C' },
    '?': { cls: 'bg-gray-700 text-gray-400',     label: '?' },
  };
  const c = cfg[status] ?? { cls: 'bg-gray-700 text-gray-400', label: status };
  return (
    <span className={`inline-flex items-center justify-center w-5 h-5 rounded text-xs font-bold font-mono shrink-0 ${c.cls}`}>
      {c.label}
    </span>
  );
}

// ── FileGroup section ─────────────────────────────────────────────────────────

interface FileGroupProps {
  title: string;
  files: GitStatusFile[];
  borderColor: string;
}

function FileGroup({ title, files, borderColor }: FileGroupProps) {
  if (files.length === 0) return null;
  return (
    <div className={`mb-3 border-l-4 ${borderColor} pl-3`}>
      <div className="text-xs font-semibold text-gray-400 uppercase tracking-wide mb-1">
        {title} ({files.length})
      </div>
      <div className="space-y-0.5 max-h-40 overflow-y-auto">
        {files.map((f, i) => (
          <div key={i} className="flex items-center gap-2 py-0.5">
            {statusBadge(f.status)}
            <span className="text-sm text-gray-300 font-mono break-all">
              {f.origPath ? <><span className="line-through text-gray-500">{f.origPath}</span> → {f.path}</> : f.path}
            </span>
          </div>
        ))}
      </div>
    </div>
  );
}

// ── CommitList section ────────────────────────────────────────────────────────

interface CommitListProps {
  commits: GitCommitRef[];
  label: string;
  bannerCls: string;
}

function CommitList({ commits, label, bannerCls }: CommitListProps) {
  if (commits.length === 0) return null;
  return (
    <div className={`mb-3 rounded px-3 py-2 ${bannerCls}`}>
      <div className="text-xs font-semibold mb-1">{label}</div>
      <div className="space-y-0.5 max-h-28 overflow-y-auto">
        {commits.map((c, i) => (
          <div key={i} className="text-xs font-mono">
            <span className="text-gray-400">{c.hash.slice(0, 7)}</span>{' '}
            <span className="text-gray-200">{c.message}</span>
          </div>
        ))}
      </div>
    </div>
  );
}

// ── Main Modal ────────────────────────────────────────────────────────────────

const RepoGitStatusModal = ({ isOpen, repoName, localPath, onClose, onStatusChanged }: RepoGitStatusModalProps) => {
  const [phase, setPhase] = useState<Phase>('idle');
  const [detail, setDetail] = useState<RepoGitStatusDetail | null>(null);
  const [errorMsg, setErrorMsg] = useState<string>('');
  const [actionMsg, setActionMsg] = useState<string>('');
  const [showDiscardPanel, setShowDiscardPanel] = useState<boolean>(false);
  const [discardConfirmMode, setDiscardConfirmMode] = useState<DiscardMode | null>(null);

  const load = useCallback(async () => {
    if (!repoName) return;
    setPhase('loading');
    setErrorMsg('');
    setShowDiscardPanel(false);
    setDiscardConfirmMode(null);
    try {
      const d = await getRepoGitStatusDetail(repoName, localPath ?? undefined);
      setDetail(d);
      setPhase('loaded');
    } catch (err) {
      setErrorMsg(err instanceof Error ? err.message : 'Failed to load git status');
      setPhase('error');
    }
  }, [repoName, localPath]);

  useEffect(() => {
    if (isOpen && repoName) {
      load();
    } else if (!isOpen) {
      setPhase('idle');
      setDetail(null);
      setErrorMsg('');
      setActionMsg('');
      setShowDiscardPanel(false);
      setDiscardConfirmMode(null);
    }
  }, [isOpen, repoName, load]);

  if (!isOpen || !repoName) return null;

  const handlePull = async () => {
    if (!detail) return;
    setPhase('acting');
    setActionMsg('Pulling latest changes…');
    try {
      await startUpdate(undefined, [detail.localPath]);
      onStatusChanged?.();
      await load();
    } catch (err) {
      setErrorMsg(err instanceof Error ? err.message : 'Pull failed');
      setPhase('error');
    }
  };

  const handleStash = async () => {
    if (!detail) return;
    setPhase('acting');
    setActionMsg('Stashing changes…');
    try {
      const result = await stashRepoChanges(repoName, detail.localPath);
      if (!result.success) throw new Error(result.output || 'Stash failed');
      onStatusChanged?.();
      await load();
    } catch (err) {
      setErrorMsg(err instanceof Error ? err.message : 'Stash failed');
      setPhase('error');
    }
  };

  const handleDiscard = async (mode: DiscardMode) => {
    if (!detail) return;
    setPhase('acting');
    setActionMsg(mode === 'all' ? 'Discarding all changes including untracked…' : 'Discarding unstaged changes…');
    try {
      const result = await discardRepoChanges(repoName, mode === 'all', detail.localPath);
      if (!result.success) throw new Error(result.output || 'Discard failed');
      onStatusChanged?.();
      await load();
    } catch (err) {
      setErrorMsg(err instanceof Error ? err.message : 'Discard failed');
      setPhase('error');
    }
  };

  const hasChanges = detail && (detail.stagedCount + detail.unstagedCount + detail.untrackedCount + detail.conflictedCount) > 0;
  const canPull    = detail && detail.unpulledCount > 0;
  const canStash   = detail && (detail.stagedCount + detail.unstagedCount + detail.untrackedCount) > 0;

  const scannedLabel = detail?.scannedAt
    ? new Date(detail.scannedAt).toLocaleTimeString()
    : '';

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4">
      {/* Backdrop */}
      <div className="absolute inset-0 bg-black/60" onClick={onClose} />

      {/* Panel */}
      <div className="mobile-sheet relative z-10 w-full max-w-2xl bg-gray-900 border border-gray-700 rounded-xl shadow-2xl flex flex-col max-h-[90vh]">
        {/* Header */}
        <div className="flex items-start justify-between px-6 py-4 border-b border-gray-700 shrink-0">
          <div>
            <h2 className="text-lg font-semibold text-white">{repoName}</h2>
            {detail && (
              <div className="text-xs text-gray-400 mt-0.5">
                branch: <span className="text-gray-200 font-mono">{detail.branch}</span>
                {detail.upstream && (
                  <> · upstream: <span className="text-gray-200 font-mono">{detail.upstream}</span></>
                )}
                {detail.isMidMerge && <span className="ml-2 text-yellow-300 font-semibold">⚠ Mid-merge</span>}
                {detail.isMidRebase && <span className="ml-2 text-yellow-300 font-semibold">⚠ Mid-rebase</span>}
              </div>
            )}
            {scannedLabel && (
              <div className="text-xs text-gray-500 mt-0.5">Scanned at {scannedLabel}</div>
            )}
          </div>
          <button onClick={onClose} className="text-gray-500 hover:text-gray-200 transition-colors text-xl leading-none ml-4">✕</button>
        </div>

        {/* Body */}
        <div className="flex-1 overflow-y-auto px-6 py-4">

          {/* Loading */}
          {phase === 'loading' && (
            <div className="flex items-center gap-3 text-gray-400 py-8 justify-center">
              <SpinnerIcon className="w-5 h-5" />
              <span>Loading git status…</span>
            </div>
          )}

          {/* Acting */}
          {phase === 'acting' && (
            <div className="flex items-center gap-3 text-gray-400 py-8 justify-center">
              <SpinnerIcon className="w-5 h-5" />
              <span>{actionMsg}</span>
            </div>
          )}

          {/* Error */}
          {phase === 'error' && (
            <div className="rounded-lg bg-red-900/30 border border-red-700/50 px-4 py-3 text-sm text-red-300">
              <div className="font-semibold mb-1">Error</div>
              <div className="font-mono text-xs break-all">{errorMsg}</div>
              <button
                onClick={load}
                className="mt-3 text-xs text-blue-400 hover:text-blue-300 underline"
              >
                Retry
              </button>
            </div>
          )}

          {/* Loaded */}
          {phase === 'loaded' && detail && (
            <>
              {/* No changes */}
              {!hasChanges && detail.unpulledCount === 0 && detail.unpushedCount === 0 && (
                <div className="text-center py-8 text-gray-400 text-sm">
                  Working tree is clean — nothing to show.
                </div>
              )}

              {/* Unpulled commits */}
              <CommitList
                commits={detail.unpulledCommits}
                label={`${detail.unpulledCount} commit${detail.unpulledCount !== 1 ? 's' : ''} to pull`}
                bannerCls="bg-purple-900/30 border border-purple-700/40 text-purple-200"
              />

              {/* Unpushed commits */}
              <CommitList
                commits={detail.unpushedCommits}
                label={`${detail.unpushedCount} commit${detail.unpushedCount !== 1 ? 's' : ''} ready to push`}
                bannerCls="bg-blue-900/30 border border-blue-700/40 text-blue-200"
              />

              {/* Conflicted */}
              <FileGroup
                title="Conflicts"
                files={detail.conflictedFiles}
                borderColor="border-red-500"
              />

              {/* Staged */}
              <FileGroup
                title="Staged"
                files={detail.stagedFiles}
                borderColor="border-green-500"
              />

              {/* Unstaged */}
              <FileGroup
                title="Unstaged"
                files={detail.unstagedFiles}
                borderColor="border-yellow-500"
              />

              {/* Untracked */}
              <FileGroup
                title="Untracked"
                files={detail.untrackedFiles}
                borderColor="border-gray-500"
              />

              {detail.stashCount > 0 && (
                <div className="text-xs text-gray-500 mt-1">
                  {detail.stashCount} stash {detail.stashCount === 1 ? 'entry' : 'entries'} exist for this repo
                </div>
              )}

              {/* Discard confirmation sub-panel */}
              {showDiscardPanel && (
                <div className="mt-4 rounded-lg bg-gray-800 border border-red-800/50 px-4 py-3">
                  <div className="text-xs font-semibold text-red-400 mb-2">⚠ This cannot be undone</div>
                  {discardConfirmMode === null ? (
                    <div className="flex flex-col gap-2">
                      <button
                        onClick={() => setDiscardConfirmMode('tracked')}
                        className="text-left text-sm text-yellow-300 hover:text-yellow-100 border border-yellow-800/50 rounded px-3 py-1.5 hover:bg-yellow-900/20 transition-colors"
                      >
                        Discard unstaged only (tracked files)
                      </button>
                      <button
                        onClick={() => setDiscardConfirmMode('all')}
                        className="text-left text-sm text-red-300 hover:text-red-100 border border-red-800/50 rounded px-3 py-1.5 hover:bg-red-900/20 transition-colors"
                      >
                        Discard everything (including untracked files)
                      </button>
                      <button
                        onClick={() => setShowDiscardPanel(false)}
                        className="text-xs text-gray-500 hover:text-gray-300 mt-1"
                      >
                        Cancel
                      </button>
                    </div>
                  ) : (
                    <div>
                      <div className="text-sm text-gray-200 mb-3">
                        {discardConfirmMode === 'all'
                          ? 'This will permanently delete all uncommitted changes AND untracked files. Are you sure?'
                          : 'This will permanently revert all unstaged changes to tracked files. Are you sure?'}
                      </div>
                      <div className="flex gap-2">
                        <button
                          onClick={() => handleDiscard(discardConfirmMode)}
                          className="px-3 py-1.5 text-sm bg-red-700 hover:bg-red-600 text-white rounded transition-colors"
                        >
                          Yes, discard
                        </button>
                        <button
                          onClick={() => setDiscardConfirmMode(null)}
                          className="px-3 py-1.5 text-sm bg-gray-700 hover:bg-gray-600 text-gray-200 rounded transition-colors"
                        >
                          Go back
                        </button>
                      </div>
                    </div>
                  )}
                </div>
              )}
            </>
          )}
        </div>

        {/* Footer actions */}
        {phase === 'loaded' && detail && (
          <div className="px-6 py-3 border-t border-gray-700 shrink-0 flex flex-wrap items-center gap-2">
            <button
              onClick={handlePull}
              disabled={!canPull}
              className="px-3 py-1.5 text-sm rounded border transition-colors
                disabled:opacity-40 disabled:cursor-not-allowed
                border-purple-600 text-purple-300 hover:bg-purple-900/30 hover:text-purple-100"
              title={canPull ? `Pull ${detail.unpulledCount} commit(s)` : 'No commits to pull'}
            >
              Pull{detail.unpulledCount > 0 ? ` (${detail.unpulledCount})` : ''}
            </button>

            <button
              onClick={handleStash}
              disabled={!canStash}
              className="px-3 py-1.5 text-sm rounded border transition-colors
                disabled:opacity-40 disabled:cursor-not-allowed
                border-blue-600 text-blue-300 hover:bg-blue-900/30 hover:text-blue-100"
              title={canStash ? 'Stash all local changes' : 'No changes to stash'}
            >
              Stash Changes
            </button>

            <button
              onClick={() => { setShowDiscardPanel(prev => !prev); setDiscardConfirmMode(null); }}
              disabled={!hasChanges}
              title={!hasChanges ? 'The working tree is clean, so there is nothing to discard.' : 'Choose what to discard from the working tree.'}
              className="px-3 py-1.5 text-sm rounded border transition-colors
                disabled:opacity-40 disabled:cursor-not-allowed
                border-red-700 text-red-400 hover:bg-red-900/30 hover:text-red-200"
            >
              Discard… ▼
            </button>

            <button
              onClick={load}
              className="ml-auto px-3 py-1.5 text-sm rounded border border-gray-600 text-gray-400 hover:text-gray-200 hover:border-gray-400 transition-colors"
              title="Refresh"
            >
              ↺
            </button>

            {/* Release 3.4 step 10 — the remedy belongs next to the diagnosis.
                Placed here rather than on every grid row deliberately: the
                2026-08-14 UI review found nine equal-weight buttons per row
                already, and Release 3.5 is scheduled to reduce that, not add
                to it. */}
            <DefaultBranchSyncButton
              repoName={repoName ?? undefined}
              repoPath={localPath ?? undefined}
              onSynced={() => { load(); onStatusChanged?.(); }}
            />

            <button
              onClick={onClose}
              className="px-3 py-1.5 text-sm rounded border border-gray-600 text-gray-400 hover:text-gray-200 hover:border-gray-400 transition-colors"
            >
              Close
            </button>
          </div>
        )}

        {/* Footer for non-loaded phases */}
        {(phase === 'loading' || phase === 'acting' || phase === 'error') && (
          <div className="px-6 py-3 border-t border-gray-700 shrink-0 flex justify-end">
            <button
              onClick={onClose}
              className="px-3 py-1.5 text-sm rounded border border-gray-600 text-gray-400 hover:text-gray-200 transition-colors"
            >
              Close
            </button>
          </div>
        )}
      </div>
    </div>
  );
};

export default RepoGitStatusModal;
