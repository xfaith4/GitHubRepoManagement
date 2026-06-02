import React, { useEffect, useMemo, useState } from 'react';
import {
  type OperationsRepoDetail,
  type OperationsRepoEntry,
  type OperationsReposResult,
  type PortfolioValueTier,
  type ReadmeContent,
  type RepoLifecycleState,
  type RoadmapContent,
} from '../types';
import { getOperationsRepoDetail, getReadmeContent, getRoadmapContent } from '../services/apiClient';
import { BranchIcon, DatabaseIcon, HealthIcon, PullRequestIcon, RefreshIcon, RoadmapIcon, SpinnerIcon } from './icons';

interface OperationsWorkspaceViewProps {
  operationsRepos: OperationsReposResult | null;
  loading: boolean;
  error?: string | null;
  onRefresh: () => void;
  onViewRoadmap?: (repoName: string) => void;
  onPreviewTask?: (repoName: string, roadmapPath?: string) => void;
  onViewGitStatus?: (repoName: string, localPath?: string) => void;
  showIndexedPortfolioNote?: boolean;
}

const LIFECYCLE_STYLES: Record<RepoLifecycleState, string> = {
  discovered: 'bg-slate-800 text-slate-200 border-slate-600',
  'needs-readme': 'bg-amber-900/40 text-amber-200 border-amber-700/50',
  'needs-roadmap': 'bg-amber-900/40 text-amber-200 border-amber-700/50',
  'needs-roadmap-repair': 'bg-orange-900/40 text-orange-200 border-orange-700/50',
  'needs-structure': 'bg-orange-900/40 text-orange-200 border-orange-700/50',
  'ready-for-work': 'bg-emerald-900/40 text-emerald-200 border-emerald-700/50',
  running: 'bg-blue-900/40 text-blue-200 border-blue-700/50',
  completed: 'bg-violet-900/40 text-violet-200 border-violet-700/50',
  monitored: 'bg-cyan-900/40 text-cyan-200 border-cyan-700/50',
  archived: 'bg-gray-800 text-gray-300 border-gray-600',
  'parse-error': 'bg-red-900/40 text-red-200 border-red-700/50',
};

const VALUE_TIER_STYLES: Record<PortfolioValueTier, string> = {
  highest: 'bg-emerald-900/40 text-emerald-200 border-emerald-700/50',
  high: 'bg-cyan-900/40 text-cyan-200 border-cyan-700/50',
  medium: 'bg-indigo-900/40 text-indigo-200 border-indigo-700/50',
  low: 'bg-slate-800 text-slate-200 border-slate-600',
  deferred: 'bg-amber-900/40 text-amber-200 border-amber-700/50',
  unscored: 'bg-gray-800 text-gray-300 border-gray-600',
};

function formatLifecycleLabel(state: RepoLifecycleState): string {
  return state.replaceAll('-', ' ');
}

function formatDate(value?: string | null): string {
  if (!value) return 'n/a';
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) return value;
  return parsed.toLocaleString();
}

function formatBytes(value?: number): string {
  if (!value || value <= 0) return '0 B';
  if (value < 1024) return `${value} B`;
  if (value < 1024 * 1024) return `${(value / 1024).toFixed(1)} KB`;
  return `${(value / (1024 * 1024)).toFixed(1)} MB`;
}

function getLifecyclePriority(state: RepoLifecycleState): number {
  switch (state) {
    case 'ready-for-work':
      return 0;
    case 'needs-readme':
      return 1;
    case 'needs-roadmap':
      return 2;
    case 'needs-roadmap-repair':
      return 3;
    case 'needs-structure':
      return 4;
    case 'running':
      return 5;
    case 'parse-error':
      return 6;
    case 'discovered':
      return 7;
    case 'monitored':
      return 8;
    case 'completed':
      return 9;
    case 'archived':
      return 10;
    default:
      return 99;
  }
}

function buildDirtySummary(entry: OperationsRepoEntry): string {
  const modified = entry.localModifiedCount ?? 0;
  const untracked = entry.localUntrackedCount ?? 0;
  const dirty = entry.localDirtyCount ?? (modified + untracked);
  if (dirty <= 0) {
    return 'Clean worktree';
  }

  return `${dirty} changed file${dirty === 1 ? '' : 's'} (${modified} modified, ${untracked} untracked)`;
}

const OperationsWorkspaceView: React.FC<OperationsWorkspaceViewProps> = ({
  operationsRepos,
  loading,
  error,
  onRefresh,
  onViewRoadmap,
  onPreviewTask,
  onViewGitStatus,
  showIndexedPortfolioNote = false,
}) => {
  const [filterText, setFilterText] = useState('');
  const [selectedRepoId, setSelectedRepoId] = useState<string | null>(null);
  const [docTab, setDocTab] = useState<'readme' | 'roadmap'>('readme');
  const [docsLoading, setDocsLoading] = useState(false);
  const [docsError, setDocsError] = useState<string | null>(null);
  const [detailLoading, setDetailLoading] = useState(false);
  const [detailError, setDetailError] = useState<string | null>(null);
  const [selectedDetail, setSelectedDetail] = useState<OperationsRepoDetail | null>(null);
  const [readmeContent, setReadmeContent] = useState<ReadmeContent | null>(null);
  const [roadmapContent, setRoadmapContent] = useState<RoadmapContent | null>(null);

  const filteredEntries = useMemo(() => {
    const lower = filterText.trim().toLowerCase();
    const base: OperationsRepoEntry[] = operationsRepos?.entries ?? [];
    const filtered = lower
      ? base.filter((entry: OperationsRepoEntry) =>
          entry.repoName.toLowerCase().includes(lower) ||
          entry.githubFullName.toLowerCase().includes(lower) ||
          entry.recommendedAction.toLowerCase().includes(lower) ||
          entry.lifecycleState.toLowerCase().includes(lower) ||
          (entry.topValueItem?.text ?? '').toLowerCase().includes(lower),
        )
      : base;

    return [...filtered].sort((left, right) => {
      const lifecycleDelta = getLifecyclePriority(left.lifecycleState) - getLifecyclePriority(right.lifecycleState);
      if (lifecycleDelta !== 0) return lifecycleDelta;

      const valueDelta = (right.topValueItem?.valueScore ?? -1) - (left.topValueItem?.valueScore ?? -1);
      if (valueDelta !== 0) return valueDelta;

      return left.repoName.localeCompare(right.repoName);
    });
  }, [filterText, operationsRepos]);

  useEffect(() => {
    if (filteredEntries.length === 0) {
      setSelectedRepoId(null);
      return;
    }

    const hasSelection = filteredEntries.some(entry => entry.repoId === selectedRepoId);
    if (!hasSelection) {
      setSelectedRepoId(filteredEntries[0].repoId);
    }
  }, [filteredEntries, selectedRepoId]);

  const selectedEntry = useMemo(
    () => filteredEntries.find(entry => entry.repoId === selectedRepoId) ?? filteredEntries[0] ?? null,
    [filteredEntries, selectedRepoId],
  );

  useEffect(() => {
    if (!selectedEntry) {
      setSelectedDetail(null);
      setDetailError(null);
      setDetailLoading(false);
      setReadmeContent(null);
      setRoadmapContent(null);
      setDocsError(null);
      setDocsLoading(false);
      return;
    }

    let cancelled = false;
    setDocsLoading(true);
    setDocsError(null);
    setDetailLoading(true);
    setDetailError(null);

    Promise.allSettled([
      getOperationsRepoDetail(selectedEntry.repoId),
      selectedEntry.hasReadme ? getReadmeContent(selectedEntry.repoName) : Promise.resolve(null),
      selectedEntry.hasRoadmap ? getRoadmapContent(selectedEntry.repoName) : Promise.resolve(null),
    ])
      .then(([detailResult, readmeResult, roadmapResult]) => {
        if (cancelled) return;

        setSelectedDetail(detailResult.status === 'fulfilled' ? detailResult.value : null);
        if (detailResult.status === 'rejected') {
          setDetailError(detailResult.reason instanceof Error ? detailResult.reason.message : 'Failed to load operations detail.');
        }

        setReadmeContent(readmeResult.status === 'fulfilled' ? readmeResult.value : null);
        setRoadmapContent(roadmapResult.status === 'fulfilled' ? roadmapResult.value : null);

        const messages: string[] = [];
        if (readmeResult.status === 'rejected' && selectedEntry.hasReadme) {
          messages.push(`README: ${readmeResult.reason instanceof Error ? readmeResult.reason.message : 'failed to load'}`);
        }
        if (roadmapResult.status === 'rejected' && selectedEntry.hasRoadmap) {
          messages.push(`ROADMAP: ${roadmapResult.reason instanceof Error ? roadmapResult.reason.message : 'failed to load'}`);
        }
        setDocsError(messages.length > 0 ? messages.join(' • ') : null);
      })
      .finally(() => {
        if (!cancelled) {
          setDocsLoading(false);
          setDetailLoading(false);
        }
      });

    return () => {
      cancelled = true;
    };
  }, [selectedEntry]);

  return (
    <div className="px-4 sm:px-6 lg:px-8 py-4">
      <div className="flex items-start justify-between gap-4 flex-wrap">
        <div>
          <h2 className="text-lg font-semibold text-white">Operations Workspace</h2>
          <p className="text-sm text-gray-400 mt-0.5">
            Select a repo from the indexed portfolio, inspect its current state, and stage the next dispatch workflow from one place.
          </p>
          {operationsRepos && (
            <div className="mt-2 text-xs text-gray-500">
              Indexed entries: <span className="text-gray-300">{operationsRepos.count}</span>
              {' '}• Updated: <span className="text-gray-300">{formatDate(operationsRepos.generatedAt)}</span>
              {' '}• Source: <span className="text-gray-300">{operationsRepos.cacheSource}</span>
            </div>
          )}
        </div>
        <button
          onClick={onRefresh}
          disabled={loading}
          className="inline-flex items-center gap-2 rounded-md border border-gray-600 bg-gray-800 px-3 py-1.5 text-sm text-gray-200 hover:bg-gray-700 disabled:opacity-50 transition-colors"
        >
          {loading ? <SpinnerIcon className="w-4 h-4" /> : <RefreshIcon className="w-4 h-4" />}
          Refresh
        </button>
      </div>

      {showIndexedPortfolioNote && (
        <div className="mt-4 rounded-lg border border-indigo-700/40 bg-indigo-950/30 px-4 py-3 text-sm text-indigo-100">
          Operations always uses the local indexed portfolio, even when the main repository grid is currently showing a GitHub API view.
        </div>
      )}

      <div className="mt-4 flex flex-wrap gap-3">
        <input
          type="text"
          placeholder="Filter operations repos..."
          value={filterText}
          onChange={(event: React.ChangeEvent<HTMLInputElement>) => setFilterText(event.target.value)}
          className="block w-full max-w-sm rounded-md border border-gray-600 bg-gray-900 px-3 py-2 text-sm text-white shadow-sm focus:border-blue-500 focus:outline-none focus:ring-blue-500"
        />
        <div className="inline-flex items-center rounded-md border border-gray-700 bg-gray-900/50 px-3 py-2 text-sm text-gray-400">
          Showing {filteredEntries.length} of {operationsRepos?.count ?? 0}
        </div>
      </div>

      {error && (
        <div className="mt-4 rounded-lg border border-red-700/40 bg-red-950/30 px-4 py-3 text-sm text-red-100">
          {error}
        </div>
      )}

      {loading && !operationsRepos && (
        <div className="mt-6 flex items-center justify-center gap-3 rounded-lg border border-gray-700 bg-gray-900/40 px-4 py-10 text-gray-400">
          <SpinnerIcon className="w-5 h-5" />
          <span>Loading indexed operations workspace…</span>
        </div>
      )}

      {!loading && filteredEntries.length === 0 && (
        <div className="mt-6 rounded-lg border border-gray-700 bg-gray-900/40 px-4 py-10 text-center text-sm text-gray-500">
          No operations-ready portfolio records matched the current filter.
        </div>
      )}

      {filteredEntries.length > 0 && (
        <div className="mt-6 grid gap-4 xl:grid-cols-[minmax(0,1.15fr)_minmax(0,1fr)]">
          <section className="overflow-hidden rounded-lg border border-gray-700 bg-gray-900/40">
            <div className="overflow-x-auto">
              <table className="min-w-full divide-y divide-gray-700">
                <thead className="bg-gray-800/80">
                  <tr>
                    <th className="px-4 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-300">Repository</th>
                    <th className="px-4 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-300">Lifecycle</th>
                    <th className="px-4 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-300">Top Work</th>
                    <th className="px-4 py-3 text-left text-xs font-medium uppercase tracking-wider text-gray-300">Health</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-gray-800 bg-gray-950/30">
                  {filteredEntries.map((entry: OperationsRepoEntry) => {
                    const isSelected = selectedEntry?.repoId === entry.repoId;
                    const valueTier = entry.topValueItem?.valueTier ?? 'unscored';
                    const valueTierClass = VALUE_TIER_STYLES[valueTier];
                    return (
                      <tr
                        key={entry.repoId}
                        onClick={() => setSelectedRepoId(entry.repoId)}
                        className={`cursor-pointer transition-colors ${isSelected ? 'bg-blue-900/20' : 'hover:bg-gray-800/50'}`}
                      >
                        <td className="px-4 py-3 align-top">
                          <div className="text-sm font-semibold text-white">{entry.repoName}</div>
                          <div className="mt-1 text-xs text-gray-400">
                            {entry.githubFullName || entry.sourceCoverage}
                          </div>
                          {entry.localPath && (
                            <div className="mt-1 max-w-md truncate text-xs text-gray-500" title={entry.localPath}>
                              {entry.localPath}
                            </div>
                          )}
                        </td>
                        <td className="px-4 py-3 align-top">
                          <span className={`inline-flex rounded-full border px-2 py-0.5 text-xs capitalize ${LIFECYCLE_STYLES[entry.lifecycleState] ?? LIFECYCLE_STYLES.discovered}`}>
                            {formatLifecycleLabel(entry.lifecycleState)}
                          </span>
                          <div className="mt-2 text-xs text-gray-400">{entry.recommendedAction}</div>
                        </td>
                        <td className="px-4 py-3 align-top">
                          {entry.topValueItem ? (
                            <>
                              <div className="inline-flex items-center gap-2">
                                <span className={`inline-flex rounded-full border px-2 py-0.5 text-xs ${valueTierClass}`}>
                                  {entry.topValueItem.valueScore}
                                </span>
                                <span className="text-xs text-gray-300">{entry.topValueItem.valueTier}</span>
                              </div>
                              <div className="mt-2 text-sm text-gray-200">{entry.topValueItem.text}</div>
                            </>
                          ) : (
                            <div className="text-xs text-gray-500">
                              {entry.pendingItemCount > 0 ? `${entry.pendingItemCount} pending roadmap items` : 'No ranked roadmap work'}
                            </div>
                          )}
                        </td>
                        <td className="px-4 py-3 align-top">
                          <div className="text-xs text-gray-400">README {entry.readmeScore}</div>
                          <div className="text-xs text-gray-400">ROADMAP {entry.roadmapScore}</div>
                          <div className="text-xs text-gray-400">Docs {entry.documentationHealthScore}</div>
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          </section>

          <section className="rounded-lg border border-gray-700 bg-gray-900/40 p-4">
            {selectedEntry ? (
              <div className="space-y-4">
                <div className="flex items-start justify-between gap-3 flex-wrap">
                  <div>
                    <div className="flex items-center gap-2 flex-wrap">
                      <h3 className="text-xl font-semibold text-white">{selectedEntry.repoName}</h3>
                      <span className={`inline-flex rounded-full border px-2 py-0.5 text-xs capitalize ${LIFECYCLE_STYLES[selectedEntry.lifecycleState] ?? LIFECYCLE_STYLES.discovered}`}>
                        {formatLifecycleLabel(selectedEntry.lifecycleState)}
                      </span>
                    </div>
                    <p className="mt-2 text-sm text-gray-300">{selectedEntry.recommendedAction}</p>
                  </div>
                  <div className="flex flex-wrap gap-2">
                    {selectedEntry.localPath && onViewGitStatus && (
                      <button
                        onClick={() => onViewGitStatus(selectedEntry.repoName, selectedEntry.localPath)}
                        className="rounded-md border border-gray-600 bg-gray-800 px-3 py-1.5 text-sm text-gray-200 hover:bg-gray-700 transition-colors"
                      >
                        Git Status
                      </button>
                    )}
                    {selectedEntry.hasRoadmap && onViewRoadmap && (
                      <button
                        onClick={() => onViewRoadmap(selectedEntry.repoName)}
                        className="inline-flex items-center gap-2 rounded-md border border-gray-600 bg-gray-800 px-3 py-1.5 text-sm text-gray-200 hover:bg-gray-700 transition-colors"
                      >
                        <RoadmapIcon className="w-4 h-4" />
                        View ROADMAP
                      </button>
                    )}
                    {selectedEntry.hasRoadmap && onPreviewTask && (
                      <button
                        onClick={() => onPreviewTask(selectedEntry.repoName, selectedEntry.roadmapPath || undefined)}
                        className="rounded-md border border-blue-700/50 bg-blue-950/40 px-3 py-1.5 text-sm text-blue-100 hover:bg-blue-900/50 transition-colors"
                      >
                        Preview Task Packet
                      </button>
                    )}
                  </div>
                </div>

                <div className="grid gap-3 sm:grid-cols-3">
                  <div className="rounded-lg border border-gray-700 bg-gray-950/40 p-3">
                    <div className="text-xs uppercase tracking-wide text-gray-500">README Score</div>
                    <div className="mt-1 text-2xl font-semibold text-white">{selectedEntry.readmeScore}</div>
                  </div>
                  <div className="rounded-lg border border-gray-700 bg-gray-950/40 p-3">
                    <div className="text-xs uppercase tracking-wide text-gray-500">ROADMAP Score</div>
                    <div className="mt-1 text-2xl font-semibold text-white">{selectedEntry.roadmapScore}</div>
                  </div>
                  <div className="rounded-lg border border-gray-700 bg-gray-950/40 p-3">
                    <div className="text-xs uppercase tracking-wide text-gray-500">Docs Health</div>
                    <div className="mt-1 text-2xl font-semibold text-white">{selectedEntry.documentationHealthScore}</div>
                  </div>
                </div>

                <div className="grid gap-4 lg:grid-cols-2">
                  <div className="rounded-lg border border-gray-700 bg-gray-950/40 p-4">
                    <div className="flex items-center gap-2 text-sm font-semibold text-white">
                      <DatabaseIcon className="w-4 h-4 text-blue-300" />
                      Repository Context
                    </div>
                    <dl className="mt-3 space-y-2 text-sm">
                      <div>
                        <dt className="text-gray-500">Local Path</dt>
                        <dd className="mt-0.5 break-all text-gray-200">{selectedEntry.localPath || 'n/a'}</dd>
                      </div>
                      <div>
                        <dt className="text-gray-500">GitHub</dt>
                        <dd className="mt-0.5 text-gray-200">
                          {selectedEntry.htmlUrl ? (selectedEntry.githubFullName || selectedEntry.htmlUrl) : 'n/a'}
                        </dd>
                      </div>
                      <div className="grid gap-3 sm:grid-cols-2">
                        <div>
                          <dt className="text-gray-500">Default Branch</dt>
                          <dd className="mt-0.5 text-gray-200">{selectedEntry.defaultBranch || 'n/a'}</dd>
                        </div>
                        <div>
                          <dt className="text-gray-500">Current Branch</dt>
                          <dd className="mt-0.5 text-gray-200">{selectedEntry.currentBranch || 'n/a'}</dd>
                        </div>
                      </div>
                      <div>
                        <dt className="text-gray-500">Last Commit</dt>
                        <dd className="mt-0.5 text-gray-200">{formatDate(selectedEntry.localLastCommitDate)}</dd>
                      </div>
                      <div className="grid gap-3 sm:grid-cols-2">
                        <div>
                          <dt className="text-gray-500">Created</dt>
                          <dd className="mt-0.5 text-gray-200">{formatDate(selectedEntry.createdAt)}</dd>
                        </div>
                        <div>
                          <dt className="text-gray-500">Updated</dt>
                          <dd className="mt-0.5 text-gray-200">{formatDate(selectedEntry.updatedAt)}</dd>
                        </div>
                      </div>
                    </dl>
                  </div>

                  <div className="rounded-lg border border-gray-700 bg-gray-950/40 p-4">
                    <div className="flex items-center gap-2 text-sm font-semibold text-white">
                      <BranchIcon className="w-4 h-4 text-emerald-300" />
                      Work Readiness
                    </div>
                    <dl className="mt-3 space-y-2 text-sm">
                      <div>
                        <dt className="text-gray-500">Dispatch Readiness</dt>
                        <dd className="mt-0.5 text-gray-200">{selectedDetail?.dispatchContext.dispatchReadiness ?? selectedEntry.dispatchReadiness}</dd>
                        {(selectedDetail?.dispatchContext.dispatchReadinessExplanation || selectedEntry.dispatchReadinessExplanation) && (
                          <div className="mt-1 text-xs text-gray-500">{selectedDetail?.dispatchContext.dispatchReadinessExplanation ?? selectedEntry.dispatchReadinessExplanation}</div>
                        )}
                      </div>
                      <div>
                        <dt className="text-gray-500">Dirty State</dt>
                        <dd className="mt-0.5 text-gray-200">{buildDirtySummary(selectedEntry)}</dd>
                      </div>
                      <div>
                        <dt className="text-gray-500">Pending Roadmap Work</dt>
                        <dd className="mt-0.5 text-gray-200">
                          {selectedDetail?.dispatchContext.topValueItem?.text ?? selectedDetail?.dispatchContext.nextPendingItemText ?? selectedEntry.topValueItem?.text ?? selectedEntry.nextPendingItemText ?? 'No pending roadmap item'}
                        </dd>
                        {(selectedDetail?.dispatchContext.topValueItem ?? selectedEntry.topValueItem) && (
                          <div className="mt-1 text-xs text-gray-500">
                            Value score {(selectedDetail?.dispatchContext.topValueItem ?? selectedEntry.topValueItem)?.valueScore} • {(selectedDetail?.dispatchContext.topValueItem ?? selectedEntry.topValueItem)?.valueTier}
                          </div>
                        )}
                      </div>
                      <div>
                        <dt className="text-gray-500">Pending Item Count</dt>
                        <dd className="mt-0.5 text-gray-200">{selectedDetail?.dispatchContext.pendingItemCount ?? selectedEntry.pendingItemCount}</dd>
                      </div>
                    </dl>
                  </div>
                </div>

                <div className="grid gap-4 lg:grid-cols-2">
                  <div className="rounded-lg border border-gray-700 bg-gray-950/40 p-4 lg:col-span-2">
                    <div className="flex items-center justify-between gap-3 flex-wrap">
                      <div className="text-sm font-semibold text-white">README and ROADMAP Viewers</div>
                      <div className="inline-flex rounded-md border border-gray-700 bg-gray-900/60 p-1 text-xs">
                        <button
                          onClick={() => setDocTab('readme')}
                          className={`rounded px-2 py-1 transition-colors ${docTab === 'readme' ? 'bg-blue-900/50 text-blue-100' : 'text-gray-300 hover:bg-gray-800'}`}
                        >
                          README
                        </button>
                        <button
                          onClick={() => setDocTab('roadmap')}
                          className={`rounded px-2 py-1 transition-colors ${docTab === 'roadmap' ? 'bg-blue-900/50 text-blue-100' : 'text-gray-300 hover:bg-gray-800'}`}
                        >
                          ROADMAP
                        </button>
                      </div>
                    </div>

                    {docsLoading ? (
                      <div className="mt-3 flex items-center gap-2 text-sm text-gray-400">
                        <SpinnerIcon className="w-4 h-4" />
                        Loading repository documents…
                      </div>
                    ) : (
                      <>
                        {docsError && (
                          <div className="mt-3 rounded-md border border-amber-700/40 bg-amber-950/20 px-3 py-2 text-xs text-amber-200">
                            {docsError}
                          </div>
                        )}
                        {docTab === 'readme' ? (
                          selectedEntry.hasReadme && readmeContent ? (
                            <div className="mt-3">
                              <div className="mb-2 text-xs text-gray-500">
                                {readmeContent.path || 'README path unavailable'} • {formatBytes(readmeContent.sizeBytes)} • updated {formatDate(readmeContent.lastModified)}
                              </div>
                              <pre className="max-h-72 overflow-auto rounded-md border border-gray-800 bg-gray-900/60 p-3 text-xs text-gray-200 whitespace-pre-wrap break-words">
                                {readmeContent.content}
                              </pre>
                            </div>
                          ) : (
                            <div className="mt-3 rounded-md border border-gray-800 bg-gray-900/40 px-3 py-2 text-sm text-gray-400">
                              README is not available for this repository.
                            </div>
                          )
                        ) : (
                          selectedEntry.hasRoadmap && roadmapContent ? (
                            <div className="mt-3">
                              <div className="mb-2 text-xs text-gray-500">
                                {roadmapContent.path || 'ROADMAP path unavailable'} • {formatBytes(roadmapContent.sizeBytes)} • updated {formatDate(roadmapContent.lastModified)}
                              </div>
                              <pre className="max-h-72 overflow-auto rounded-md border border-gray-800 bg-gray-900/60 p-3 text-xs text-gray-200 whitespace-pre-wrap break-words">
                                {roadmapContent.content}
                              </pre>
                            </div>
                          ) : (
                            <div className="mt-3 rounded-md border border-gray-800 bg-gray-900/40 px-3 py-2 text-sm text-gray-400">
                              ROADMAP is not available for this repository.
                            </div>
                          )
                        )}
                      </>
                    )}
                  </div>

                  <div className="rounded-lg border border-gray-700 bg-gray-950/40 p-4">
                    <div className="flex items-center gap-2 text-sm font-semibold text-white">
                      <PullRequestIcon className="w-4 h-4 text-cyan-300" />
                      GitHub Signals
                    </div>
                    <dl className="mt-3 space-y-2 text-sm">
                      <div className="grid gap-3 sm:grid-cols-2">
                        <div>
                          <dt className="text-gray-500">Open PRs</dt>
                          <dd className="mt-0.5 text-gray-200">{selectedEntry.openPrCount}</dd>
                        </div>
                        <div>
                          <dt className="text-gray-500">Pending Review PRs</dt>
                          <dd className="mt-0.5 text-gray-200">{selectedEntry.pendingReviewPrCount}</dd>
                        </div>
                      </div>
                      <div>
                        <dt className="text-gray-500">Latest Actions Run</dt>
                        <dd className="mt-0.5 text-gray-200">
                          {selectedEntry.latestWorkflowRunName || selectedEntry.latestWorkflowRunStatus
                            ? `${selectedEntry.latestWorkflowRunName ?? 'Workflow'} • ${selectedEntry.latestWorkflowRunStatus ?? 'unknown'}${selectedEntry.latestWorkflowRunConclusion ? ` / ${selectedEntry.latestWorkflowRunConclusion}` : ''}`
                            : 'n/a'}
                        </dd>
                        {selectedEntry.latestWorkflowRunTimestamp && (
                          <div className="mt-1 text-xs text-gray-500">{formatDate(selectedEntry.latestWorkflowRunTimestamp)}</div>
                        )}
                      </div>
                      <div>
                        <dt className="text-gray-500">GitHub Pages</dt>
                        <dd className="mt-0.5 text-gray-200">
                          {selectedEntry.hasPages && selectedEntry.pagesUrl ? selectedEntry.pagesUrl : 'Not configured'}
                        </dd>
                      </div>
                    </dl>
                  </div>

                  <div className="rounded-lg border border-gray-700 bg-gray-950/40 p-4">
                    <div className="flex items-center gap-2 text-sm font-semibold text-white">
                      <HealthIcon className="w-4 h-4 text-amber-300" />
                      Audit Findings and Blockers
                    </div>

                    {detailLoading ? (
                      <div className="mt-3 flex items-center gap-2 text-sm text-gray-400">
                        <SpinnerIcon className="w-4 h-4" />
                        Loading audit findings...
                      </div>
                    ) : (
                      <div className="mt-3 space-y-3 text-sm">
                        {detailError && (
                          <div className="rounded-md border border-amber-700/40 bg-amber-950/20 px-3 py-2 text-xs text-amber-200">
                            {detailError}
                          </div>
                        )}

                        <div>
                          <div className="mb-2 text-xs uppercase tracking-wide text-gray-500">README Findings</div>
                          {(() => {
                            const readmeFindings = (selectedDetail?.docAudit.findings ?? []).filter(finding => /readme/i.test(finding.file));
                            if (readmeFindings.length === 0) {
                              return <div className="rounded-md border border-gray-800 bg-gray-900/40 px-3 py-2 text-gray-400">No README-specific findings from the latest docs audit.</div>;
                            }

                            return (
                              <ul className="space-y-2 text-gray-200">
                                {readmeFindings.map((finding, index) => (
                                  <li key={`${finding.file}:${finding.message}:${index}`} className="rounded-md border border-gray-800 bg-gray-900/60 px-3 py-2">
                                    <div className="text-xs text-gray-400">{finding.severity} • {finding.file}</div>
                                    <div className="mt-1">{finding.message}</div>
                                    {finding.recommendedAction && <div className="mt-1 text-xs text-gray-400">{finding.recommendedAction}</div>}
                                  </li>
                                ))}
                              </ul>
                            );
                          })()}
                        </div>

                        <div>
                          <div className="mb-2 text-xs uppercase tracking-wide text-gray-500">ROADMAP Findings</div>
                          {selectedDetail?.roadmapAudit.auditFindings && selectedDetail.roadmapAudit.auditFindings.length > 0 ? (
                            <ul className="space-y-2 text-gray-200">
                              {selectedDetail.roadmapAudit.auditFindings.map((finding, index) => (
                                <li key={`${finding.ruleId}:${finding.message}:${index}`} className="rounded-md border border-gray-800 bg-gray-900/60 px-3 py-2">
                                  <div className="text-xs text-gray-400">{finding.severity} • {finding.ruleId}</div>
                                  <div className="mt-1">{finding.message}</div>
                                  {finding.recommendedAction && <div className="mt-1 text-xs text-gray-400">{finding.recommendedAction}</div>}
                                </li>
                              ))}
                            </ul>
                          ) : (
                            <div className="rounded-md border border-gray-800 bg-gray-900/40 px-3 py-2 text-gray-400">No ROADMAP audit findings are available.</div>
                          )}
                        </div>

                        <div>
                          <div className="mb-2 text-xs uppercase tracking-wide text-gray-500">Structure Findings</div>
                          {(selectedDetail?.documentationContext.structureFindings ?? selectedEntry.structureFindings).length > 0 ? (
                            <ul className="space-y-2 text-gray-200">
                              {(selectedDetail?.documentationContext.structureFindings ?? selectedEntry.structureFindings).map((finding, index) => (
                                <li key={`${finding.kind}:${finding.target}:${index}`} className="rounded-md border border-gray-800 bg-gray-900/60 px-3 py-2">
                                  <div className="text-xs text-gray-400">{finding.severity} • {finding.category}</div>
                                  <div className="mt-1">{finding.target}</div>
                                  <div className="mt-1 text-xs text-gray-400">{finding.recommendedAction}</div>
                                </li>
                              ))}
                            </ul>
                          ) : (
                            <div className="rounded-md border border-gray-800 bg-gray-900/40 px-3 py-2 text-gray-400">No structure findings are currently recorded.</div>
                          )}
                        </div>

                        <div>
                          <div className="mb-2 text-xs uppercase tracking-wide text-gray-500">Dispatch Blockers</div>
                          {(selectedDetail?.dispatchContext.blockingReasons ?? selectedEntry.blockingReasons).length > 0 ? (
                            <ul className="space-y-2 text-gray-200">
                              {(selectedDetail?.dispatchContext.blockingReasons ?? selectedEntry.blockingReasons).map((reason: string) => (
                                <li key={reason} className="rounded-md border border-gray-800 bg-gray-900/60 px-3 py-2">
                                  {reason}
                                </li>
                              ))}
                            </ul>
                          ) : (
                            <div className="rounded-md border border-emerald-800/40 bg-emerald-950/20 px-3 py-2 text-emerald-100">
                              No dispatch blockers recorded for this repo in the current assessment context.
                            </div>
                          )}
                        </div>
                      </div>
                    )}

                    {(selectedDetail?.dispatchContext.topValueItem ?? selectedEntry.topValueItem)?.valueRationale && (selectedDetail?.dispatchContext.topValueItem ?? selectedEntry.topValueItem)!.valueRationale.length > 0 && (
                      <div className="mt-4">
                        <div className="text-xs uppercase tracking-wide text-gray-500">Why this work ranks highly</div>
                        <ul className="mt-2 space-y-2 text-sm text-gray-300">
                          {(selectedDetail?.dispatchContext.topValueItem ?? selectedEntry.topValueItem)!.valueRationale.map((reason: string) => (
                            <li key={reason} className="rounded-md border border-gray-800 bg-gray-900/40 px-3 py-2">
                              {reason}
                            </li>
                          ))}
                        </ul>
                      </div>
                    )}
                  </div>
                </div>
              </div>
            ) : (
              <div className="flex h-full min-h-[320px] items-center justify-center text-sm text-gray-500">
                Select a repo from the Operations table to open its workspace.
              </div>
            )}
          </section>
        </div>
      )}
    </div>
  );
};

export default OperationsWorkspaceView;
