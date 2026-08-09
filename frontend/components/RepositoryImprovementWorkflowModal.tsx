import React, { useEffect, useMemo, useState } from 'react';
import type { DispatchExecuteResult, DocAuditEntry, RepositoryImprovementPreview } from '../types';
import { executeRoadmapDispatch, previewRepositoryImprovement } from '../services/apiClient';
import { SpinnerIcon } from './icons';

interface RepositoryImprovementWorkflowModalProps {
  isOpen: boolean;
  repos: DocAuditEntry[];
  initialRepoName?: string | null;
  onClose: () => void;
  onDispatchComplete?: (result: DispatchExecuteResult) => void;
}

type Phase = 'select' | 'scanning' | 'review' | 'dispatching' | 'done';

const steps = ['Repository', 'Scan', 'Task review', 'PR handoff'];

const RepositoryImprovementWorkflowModal: React.FC<RepositoryImprovementWorkflowModalProps> = ({
  isOpen,
  repos,
  initialRepoName,
  onClose,
  onDispatchComplete,
}) => {
  const sortedRepos = useMemo(() => [...repos].sort((a, b) => a.repoName.localeCompare(b.repoName)), [repos]);
  const [repoName, setRepoName] = useState('');
  const [phase, setPhase] = useState<Phase>('select');
  const [preview, setPreview] = useState<RepositoryImprovementPreview | null>(null);
  const [prompt, setPrompt] = useState('');
  const [dispatchResult, setDispatchResult] = useState<DispatchExecuteResult | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!isOpen) return;
    const initial = initialRepoName && sortedRepos.some(repo => repo.repoName === initialRepoName)
      ? initialRepoName
      : sortedRepos[0]?.repoName ?? '';
    setRepoName(initial);
    setPhase('select');
    setPreview(null);
    setPrompt('');
    setDispatchResult(null);
    setError(null);
  }, [isOpen, initialRepoName, sortedRepos]);

  if (!isOpen) return null;

  const selectedRepo = sortedRepos.find(repo => repo.repoName === repoName);
  const activeStep = phase === 'select' ? 0 : phase === 'scanning' ? 1 : phase === 'review' ? 2 : 3;

  const runScan = async () => {
    if (!selectedRepo?.repoPath) return;
    setPhase('scanning');
    setError(null);
    setPreview(null);
    try {
      const result = await previewRepositoryImprovement(selectedRepo.repoName, selectedRepo.repoPath);
      setPreview(result);
      setPrompt(result.task?.generatedPrompt ?? '');
      setPhase('review');
    } catch (scanError) {
      setError(scanError instanceof Error ? scanError.message : String(scanError));
      setPhase('select');
    }
  };

  const dispatch = async () => {
    if (!preview || !prompt.trim()) return;
    setPhase('dispatching');
    setError(null);
    try {
      const result = await executeRoadmapDispatch(preview.repoName, prompt.trim(), { localPath: preview.repoPath });
      setDispatchResult(result);
      setPhase('done');
      onDispatchComplete?.(result);
    } catch (dispatchError) {
      setError(dispatchError instanceof Error ? dispatchError.message : String(dispatchError));
      setPhase('review');
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/70 p-4">
      <div className="mobile-sheet flex max-h-[92vh] w-full max-w-5xl flex-col rounded-xl border border-gray-700 bg-gray-900 shadow-2xl">
        <div className="flex items-start justify-between border-b border-gray-700 px-5 py-4">
          <div>
            <h2 className="text-lg font-semibold text-white">Guided repository improvement</h2>
            <p className="mt-1 text-sm text-gray-400">Scan README and ROADMAP, review the exact task, then dispatch it to a pull request.</p>
          </div>
          <button onClick={onClose} className="text-lg leading-none text-gray-400 hover:text-white" aria-label="Close">✕</button>
        </div>

        <div className="border-b border-gray-800 px-5 py-3">
          <ol className="grid grid-cols-2 gap-2 sm:grid-cols-4">
            {steps.map((label, index) => (
              <li key={label} className={`rounded-md border px-3 py-2 text-xs ${index === activeStep ? 'border-indigo-500 bg-indigo-950/50 text-indigo-200' : index < activeStep ? 'border-emerald-800/60 bg-emerald-950/20 text-emerald-300' : 'border-gray-700 text-gray-500'}`}>
                <span className="mr-1.5 font-semibold">{index < activeStep ? '✓' : index + 1}</span>{label}
              </li>
            ))}
          </ol>
        </div>

        <div className="flex-1 overflow-y-auto px-5 py-5">
          {error && <div className="mb-4 rounded-lg border border-red-700/50 bg-red-950/30 px-4 py-3 text-sm text-red-200">{error}</div>}

          {phase === 'select' && (
            <section className="mx-auto max-w-2xl">
              <h3 className="text-base font-semibold text-white">Choose a repository</h3>
              <p className="mt-1 text-sm text-gray-400">The scan is read-only. No task or branch is created until you approve execution.</p>
              <label className="mt-5 block text-xs font-medium uppercase tracking-wide text-gray-400" htmlFor="improvement-repo">Repository</label>
              <select id="improvement-repo" value={repoName} onChange={event => setRepoName(event.target.value)} className="mt-2 w-full rounded-md border border-gray-600 bg-gray-950 px-3 py-2.5 text-sm text-white">
                {sortedRepos.map(repo => <option key={`${repo.repoName}:${repo.repoPath}`} value={repo.repoName}>{repo.repoName}</option>)}
              </select>
              {selectedRepo && <p className="mt-2 break-all text-xs text-gray-500">{selectedRepo.repoPath}</p>}
            </section>
          )}

          {(phase === 'scanning' || phase === 'dispatching') && (
            <div className="flex items-center justify-center gap-3 py-16 text-gray-300">
              <SpinnerIcon className="h-5 w-5 animate-spin" />
              <span>{phase === 'scanning' ? 'Scanning README and ROADMAP…' : 'Dispatching the approved task to Copilot…'}</span>
            </div>
          )}

          {phase === 'review' && preview && (
            <div className="space-y-5">
              <div className="grid gap-3 sm:grid-cols-2">
                {[{ label: 'README.md', data: preview.readme }, { label: 'ROADMAP.md', data: preview.roadmap }].map(({ label, data }) => (
                  <div key={label} className="rounded-lg border border-gray-700 bg-gray-950/50 p-4">
                    <div className="flex items-center justify-between">
                      <h3 className="font-semibold text-white">{label}</h3>
                      <span className={`rounded-full border px-2 py-0.5 text-xs ${data.findingCount === 0 ? 'border-emerald-700/60 text-emerald-300' : 'border-amber-700/60 text-amber-300'}`}>{data.findingCount === 0 ? 'Pass' : `${data.findingCount} finding${data.findingCount === 1 ? '' : 's'}`}</span>
                    </div>
                    <p className="mt-2 text-xs text-gray-500">{data.exists ? data.path : 'File not found'}</p>
                    {data.findings.map((finding, index) => (
                      <div key={`${finding.ruleId ?? finding.file}:${index}`} className="mt-3 border-l-2 border-amber-700 pl-3 text-sm">
                        <p className="text-gray-200">{finding.message}</p>
                        <p className="mt-1 text-xs text-gray-400">{finding.recommendedAction}</p>
                      </div>
                    ))}
                  </div>
                ))}
              </div>

              {!preview.needsImprovement ? (
                <div className="rounded-lg border border-emerald-700/50 bg-emerald-950/20 p-5 text-center">
                  <h3 className="font-semibold text-emerald-200">No improvement task is needed</h3>
                  <p className="mt-1 text-sm text-emerald-300/80">README and ROADMAP passed the configured checks. Nothing will be dispatched.</p>
                </div>
              ) : preview.task && (
                <section>
                  <div className="flex flex-wrap items-end justify-between gap-2">
                    <div><h3 className="font-semibold text-white">Review improvement task</h3><p className="mt-1 text-sm text-gray-400">Edit the prompt if needed. This exact text is sent to Copilot.</p></div>
                    <span className="text-xs text-gray-500">{preview.task.summary}</span>
                  </div>
                  <textarea value={prompt} onChange={event => setPrompt(event.target.value)} rows={15} className="mt-3 w-full rounded-lg border border-gray-600 bg-gray-950 p-3 font-mono text-xs leading-5 text-gray-200 focus:border-indigo-500 focus:outline-none" />
                  <p className="mt-2 text-xs text-gray-500">Execution consumes agent quota and asks Copilot to create a branch and pull request. Review the resulting PR before merging.</p>
                </section>
              )}
            </div>
          )}

          {phase === 'done' && dispatchResult && (
            <div className="mx-auto max-w-2xl rounded-lg border border-emerald-700/50 bg-emerald-950/20 p-6 text-center">
              <div className="text-2xl text-emerald-300">✓</div>
              {/* Release 3.0 — the host enqueues; the operator-session runner
                  creates the agent task. Saying "dispatched" here overstated
                  what happened even before that change, since the wizard's last
                  step could not succeed from the service at all. */}
              <h3 className="mt-2 text-lg font-semibold text-white">Task queued for the operator runner</h3>
              <p className="mt-2 text-sm text-gray-300">{dispatchResult.message}</p>
              <dl className="mt-4 grid grid-cols-1 gap-2 text-left text-xs sm:grid-cols-2"><div><dt className="text-gray-500">Repository</dt><dd className="mt-1 text-gray-200">{dispatchResult.githubRepo}</dd></div><div><dt className="text-gray-500">Run ID</dt><dd className="mt-1 break-all text-gray-200">{dispatchResult.runId || dispatchResult.agentRunId}</dd></div></dl>
              <p className="mt-4 text-xs text-gray-400">The task runner creates the GitHub agent task in your own session — the portal cannot, because <code>gh agent-task</code> needs an OAuth credential a service cannot hold. Start it with <code>pwsh -File scripts/Invoke-RoadmapTaskRunner.ps1</code> if it is not already running. Track progress in Copilot Execution Lanes or GitHub; the pull request remains a review gate and is not merged automatically.</p>
            </div>
          )}
        </div>

        <div className="flex flex-wrap items-center justify-between gap-3 border-t border-gray-700 px-5 py-4">
          <button onClick={onClose} className="rounded border border-gray-600 bg-gray-800 px-3 py-2 text-sm text-gray-200 hover:bg-gray-700">{phase === 'done' ? 'Close' : 'Cancel'}</button>
          {phase === 'select' && <button onClick={runScan} disabled={!selectedRepo?.repoPath} className="rounded border border-indigo-500 bg-indigo-700 px-4 py-2 text-sm font-medium text-white hover:bg-indigo-600 disabled:opacity-50">Scan selected repo</button>}
          {phase === 'review' && preview && <div className="flex gap-2"><button onClick={runScan} className="rounded border border-gray-600 px-3 py-2 text-sm text-gray-200 hover:bg-gray-800">Scan again</button>{preview.needsImprovement && <button onClick={dispatch} disabled={!prompt.trim()} className="rounded border border-emerald-600 bg-emerald-700 px-4 py-2 text-sm font-medium text-white hover:bg-emerald-600 disabled:opacity-50">Approve and create PR task</button>}</div>}
        </div>
      </div>
    </div>
  );
};

export default RepositoryImprovementWorkflowModal;
