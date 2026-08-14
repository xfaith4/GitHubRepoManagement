import React, { useState, useEffect, useCallback } from 'react';
import { type RoadmapContent, type RoadmapTaskPreview, type RoadmapTaskHistoryItem } from '../types';
import { getRoadmapContent, triggerRoadmapScan, previewRoadmapTask, startRoadmapTask, approveRoadmapTask, getRoadmapTaskHistory, getRunnerPresence } from '../services/apiClient';
import { resolveDispatchGate, type RunnerPresencePayload } from '../lib/runnerPresence';

interface RoadmapViewerModalProps {
  isOpen: boolean;
  repoName: string | null;
  defaultOwner?: string | null;
  onClose: () => void;
  onScanComplete?: (count: number) => void;
}

const RoadmapViewerModal: React.FC<RoadmapViewerModalProps> = ({ isOpen, repoName, defaultOwner, onClose, onScanComplete }) => {
  const [content, setContent] = useState<RoadmapContent | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [scanning, setScanning] = useState(false);
  const [scanMessage, setScanMessage] = useState<string | null>(null);
  const [repositoryInput, setRepositoryInput] = useState('');
  const [baseBranch, setBaseBranch] = useState('main');
  const [customAgent, setCustomAgent] = useState('');
  const [taskRunning, setTaskRunning] = useState(false);
  const [taskPreview, setTaskPreview] = useState<RoadmapTaskPreview | null>(null);
  const [taskMessage, setTaskMessage] = useState<string | null>(null);
  const [taskHistory, setTaskHistory] = useState<RoadmapTaskHistoryItem[]>([]);
  const [historyLoading, setHistoryLoading] = useState(false);
  const [approvingRunId, setApprovingRunId] = useState<string | null>(null);
  // Release 3.1 — "Start task" reaches the runner queue through
  // /api/roadmap-agent/start, which now refuses when nothing can claim the work.
  // Without this the button stays enabled and dead-ends on a 409.
  const [runnerPresence, setRunnerPresence] = useState<RunnerPresencePayload | null>(null);

  const loadContent = useCallback(async (name: string) => {
    setLoading(true);
    setError(null);
    setContent(null);
    try {
      const result = await getRoadmapContent(name);
      setContent(result);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load roadmap content.');
    } finally {
      setLoading(false);
    }
  }, []);

  // Declared before the effect that calls it — the effect previously
  // referenced this via hoisting-by-closure, which the react-hooks immutability
  // rule rejects because the early reference cannot track later changes.
  const loadHistory = useCallback(async () => {
    setHistoryLoading(true);
    try {
      const items = await getRoadmapTaskHistory(10);
      setTaskHistory(items);
    } catch {
      setTaskHistory([]);
    } finally {
      setHistoryLoading(false);
    }
  }, []);

  useEffect(() => {
    if (isOpen && repoName) {
      setTaskMessage(null);
      setTaskPreview(null);
      loadContent(repoName);
      setScanMessage(null);
      // Resolves null on failure rather than throwing, and resolveDispatchGate
      // treats an unknown reading as "allow" — only a positive absent/stale
      // reading disables the control.
      getRunnerPresence().then(setRunnerPresence);

      const owner = (defaultOwner ?? '').trim();
      if (owner) {
        setRepositoryInput(`${owner}/${repoName}`);
      } else if (!repositoryInput) {
        setRepositoryInput(`OWNER/${repoName}`);
      }

      void loadHistory();
    }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isOpen, repoName, defaultOwner, loadContent, loadHistory]);

  const handleScanAll = async () => {
    setScanning(true);
    setScanMessage('Scanning all repositories for ROADMAP files...');
    try {
      const result = await triggerRoadmapScan();
      setScanMessage(`Scan complete. Found ${result.count} ROADMAP ${result.count === 1 ? 'file' : 'files'} across your repositories.`);
      if (onScanComplete) onScanComplete(result.count);
    } catch (err) {
      setScanMessage('Scan failed: ' + (err instanceof Error ? err.message : 'Unknown error'));
    } finally {
      setScanning(false);
    }
  };
  const handlePreviewTask = async () => {
    setTaskMessage(null);
    setTaskPreview(null);
    setTaskRunning(true);
    try {
      const roadmapPath = content?.path?.trim() ? content.path : undefined;
      const preview = await previewRoadmapTask({
        repository: repositoryInput.trim(),
        baseBranch: baseBranch.trim() || undefined,
        customAgent: customAgent.trim() || undefined,
        roadmapPath,
      });
      setTaskPreview(preview);
      setTaskMessage(`Preview ready for ${preview.selectedTask.text}`);
      await loadHistory();
    } catch (err) {
      setTaskMessage(err instanceof Error ? err.message : 'Roadmap preview failed.');
    } finally {
      setTaskRunning(false);
    }
  };

  const handleStartTask = async () => {
    setTaskMessage(null);
    setTaskRunning(true);
    try {
      const roadmapPath = content?.path?.trim() ? content.path : undefined;
      const result = await startRoadmapTask({
        repository: repositoryInput.trim(),
        baseBranch: baseBranch.trim() || undefined,
        customAgent: customAgent.trim() || undefined,
        roadmapPath,
        follow: false
      });
      const runId = result.latestHistory?.runId ? ` (run ${result.latestHistory.runId})` : '';
      setTaskMessage(`${result.message}${runId}`);
      await loadHistory();
    } catch (err) {
      setTaskMessage(err instanceof Error ? err.message : 'Roadmap task start failed.');
    } finally {
      setTaskRunning(false);
    }
  };

  const handleApprovePush = async (runId: string) => {
    setTaskMessage(null);
    setApprovingRunId(runId);
    try {
      const result = await approveRoadmapTask(runId);
      setTaskMessage(`${result.message}${result.branch ? ` (branch ${result.branch})` : ''}`);
      await loadHistory();
    } catch (err) {
      setTaskMessage(err instanceof Error ? err.message : 'Approve & push failed.');
    } finally {
      setApprovingRunId(null);
    }
  };

  if (!isOpen) return null;

  const formatDate = (iso: string) => {
    try { return new Date(iso).toLocaleString(); } catch { return iso; }
  };

  const formatSize = (bytes: number) => {
    if (bytes < 1024) return `${bytes} B`;
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
    return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  };

  const isTaskError = taskMessage !== null && /failed|error|not found|not installed|required/i.test(taskMessage);
  const hasLocalRoadmap = Boolean(content?.path);
  const dispatchGate = resolveDispatchGate(runnerPresence);

  return (
    <div className="fixed inset-0 bg-black/60 backdrop-blur-sm flex items-center justify-center z-50 p-4">
      <div className="mobile-sheet bg-gray-900 border border-gray-700 rounded-xl shadow-2xl w-full max-w-4xl max-h-[90vh] flex flex-col">
        {/* Header */}
        <div className="flex items-center justify-between px-5 py-4 border-b border-gray-700 flex-shrink-0">
          <div className="flex items-center gap-3">
            <span className="text-lg font-semibold text-gray-100">ROADMAP</span>
            {repoName && (
              <span className="text-sm text-blue-400 font-mono bg-blue-900/30 px-2 py-0.5 rounded">{repoName}</span>
            )}
          </div>
          <div className="flex items-center gap-2">
            <button
              onClick={handleScanAll}
              disabled={scanning}
              title="Re-scan all repos for ROADMAP files"
              className="text-xs px-3 py-1.5 rounded bg-gray-700 hover:bg-gray-600 text-gray-200 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
            >
              {scanning ? 'Scanning...' : 'Scan All ROADMAPs'}
            </button>
            <button
              onClick={() => repoName && loadContent(repoName)}
              disabled={loading}
              title="Refresh roadmap content"
              className="text-xs px-3 py-1.5 rounded bg-gray-700 hover:bg-gray-600 text-gray-200 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
            >
              Refresh
            </button>
            {!dispatchGate.canQueue && (
              <span data-testid="roadmap-viewer-precondition" className="max-w-md text-xs text-amber-300/90">
                {dispatchGate.unmetPrecondition}
              </span>
            )}
            <button
              onClick={handleStartTask}
              disabled={taskRunning || loading || !repositoryInput.trim() || !dispatchGate.canQueue}
              data-testid="roadmap-viewer-start-task"
              title={dispatchGate.canQueue
                ? 'Queue the next roadmap task for the local Claude Code runner'
                : dispatchGate.unmetPrecondition}
              className="text-xs px-3 py-1.5 rounded bg-indigo-800 hover:bg-indigo-700 text-indigo-100 border border-indigo-700 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
            >
              {taskRunning ? 'Working...' : 'Run AI Agent'}
            </button>
            <button
              onClick={onClose}
              className="ml-1 text-gray-400 hover:text-gray-100 transition-colors text-xl leading-none"
              aria-label="Close"
            >
              ×
            </button>
          </div>
        </div>

        {/* Scan message bar */}
        {scanMessage && (
          <div className={`px-5 py-2 text-xs border-b border-gray-700 flex-shrink-0 ${scanMessage.startsWith('Scan failed') ? 'text-red-300 bg-red-900/20' : 'text-green-300 bg-green-900/20'}`}>
            {scanMessage}
          </div>
        )}

        <div className="px-5 py-3 border-b border-gray-700 bg-gray-950/40 flex-shrink-0 space-y-2">
          <div className="text-xs font-semibold text-gray-300">Roadmap Task (local Claude Code)</div>
          <div className="text-xs text-gray-500">
            Preview picks the next roadmap item; Queue Task adds it to the local task queue. A runner you start yourself (scripts/Invoke-RoadmapTaskRunner.ps1) executes it with Claude Code on the local repo and stops for your review before anything is pushed.
          </div>
          <div className="grid grid-cols-1 md:grid-cols-3 gap-2">
            <input
              value={repositoryInput}
              onChange={(e) => setRepositoryInput(e.target.value)}
              placeholder="owner/repo"
              className="rounded bg-gray-800 border border-gray-600 px-2 py-1.5 text-xs text-gray-100"
            />
            <input
              value={baseBranch}
              onChange={(e) => setBaseBranch(e.target.value)}
              placeholder="base branch"
              className="rounded bg-gray-800 border border-gray-600 px-2 py-1.5 text-xs text-gray-100"
            />
            <input
              value={customAgent}
              onChange={(e) => setCustomAgent(e.target.value)}
              placeholder="custom agent (optional)"
              className="rounded bg-gray-800 border border-gray-600 px-2 py-1.5 text-xs text-gray-100"
            />
          </div>
          <div className="flex items-center gap-2">
            <button
              onClick={handlePreviewTask}
              disabled={taskRunning || loading || !repositoryInput.trim()}
              title={!repositoryInput.trim() ? 'Enter a repository name first.' : taskRunning ? 'A task is already running for this repository.' : loading ? 'The roadmap is still loading.' : 'Builds a task preview without queueing anything.'}
              className="text-xs px-3 py-1.5 rounded bg-indigo-700 hover:bg-indigo-600 text-white disabled:opacity-50 disabled:cursor-not-allowed"
            >
              {taskRunning ? 'Working...' : 'Preview Task'}
            </button>
            <button
              onClick={handleStartTask}
              disabled={taskRunning || loading || !repositoryInput.trim()}
              title={!repositoryInput.trim() ? 'Enter a repository name first.' : taskRunning ? 'A task is already running for this repository.' : loading ? 'The roadmap is still loading.' : 'Queues this task for the local runner.'}
              className="text-xs px-3 py-1.5 rounded bg-green-700 hover:bg-green-600 text-white disabled:opacity-50 disabled:cursor-not-allowed"
            >
              Queue Task
            </button>
            <button
              onClick={() => void loadHistory()}
              disabled={historyLoading}
              className="text-xs px-3 py-1.5 rounded bg-gray-700 hover:bg-gray-600 text-gray-200 disabled:opacity-50"
            >
              {historyLoading ? 'Loading history...' : 'Refresh History'}
            </button>
          </div>

          {taskMessage && (
            <div className={`text-xs rounded px-3 py-2 border ${isTaskError ? 'bg-red-950/60 border-red-700/60 text-red-100' : 'bg-blue-900/30 border-blue-700/40 text-blue-200'}`}>
              <div className="font-semibold mb-1">
                {isTaskError ? 'Task issue' : 'Task'}
              </div>
              <div>{taskMessage}</div>
              {isTaskError && hasLocalRoadmap && (
                <div className="mt-1 text-red-200/80">
                  The local roadmap is loaded below from {content?.path} and is passed into the task-preview flow. If this warning persists, the failure is elsewhere in the roadmap-agent or dispatch path, not in local roadmap loading.
                </div>
              )}
            </div>
          )}

          {taskPreview && (
            <div className="rounded border border-gray-700 p-2 bg-gray-900/50">
              <div className="text-xs text-gray-300 mb-1">
                Next task: <span className="text-indigo-300">{taskPreview.selectedTask.text}</span>
              </div>
              <textarea
                value={taskPreview.generatedTaskDescription}
                readOnly
                className="w-full h-24 rounded bg-gray-950 border border-gray-700 px-2 py-1.5 text-xs text-gray-200"
              />
            </div>
          )}

          <div className="rounded border border-gray-700 p-2 bg-gray-900/30">
            <div className="text-xs font-semibold text-gray-300 mb-1">Recent Task History</div>
            {taskHistory.length === 0 ? (
              <div className="text-xs text-gray-500">No roadmap task runs found yet.</div>
            ) : (
              <div className="max-h-24 overflow-auto space-y-1">
                {taskHistory.map(item => (
                  <div key={item.runId} className="text-xs border-b border-gray-800 pb-1">
                    <div className="flex justify-between items-center gap-2">
                      <span className="font-mono text-gray-400">{item.runId}</span>
                      <span className="flex items-center gap-2">
                        <span className={item.status === 'failed' ? 'text-red-400' : item.status === 'awaiting-review' ? 'text-amber-300' : 'text-green-400'}>{item.status}</span>
                        {item.status === 'awaiting-review' && (
                          <button
                            onClick={() => void handleApprovePush(item.runId)}
                            disabled={approvingRunId !== null}
                            title="Push the reviewed branch to origin (nothing is merged)"
                            className="px-2 py-0.5 rounded bg-emerald-800 hover:bg-emerald-700 text-emerald-100 border border-emerald-700 disabled:opacity-50 disabled:cursor-not-allowed"
                          >
                            {approvingRunId === item.runId ? 'Pushing...' : 'Approve & push'}
                          </button>
                        )}
                      </span>
                    </div>
                    <div className="text-gray-300 truncate" title={item.repository}>{item.repository}</div>
                    <div className="text-gray-500 truncate" title={item.selectedTask}>{item.selectedTask}</div>
                  </div>
                ))}
              </div>
            )}
          </div>
        </div>

        {/* File meta */}
        {content && !loading && (
          <div className="px-5 py-2 border-b border-gray-700 flex-shrink-0 flex flex-wrap gap-4 text-xs text-gray-400">
            <span>Last modified: <span className="text-gray-300">{formatDate(content.lastModified)}</span></span>
            <span>Size: <span className="text-gray-300">{formatSize(content.sizeBytes)}</span></span>
            <span className="text-gray-500">Local roadmap:</span>
            <span className="font-mono text-gray-500 truncate max-w-xs" title={content.path}>{content.path}</span>
          </div>
        )}

        {/* Content area */}
        <div className="flex-1 overflow-auto p-5 min-h-0">
          {loading && (
            <div className="flex items-center gap-2 text-sm text-gray-400">
              <span className="inline-block w-4 h-4 border-2 border-blue-500 border-t-transparent rounded-full animate-spin" />
              Loading roadmap...
            </div>
          )}
          {error && !loading && (
            <div className="text-sm text-red-400 bg-red-900/20 border border-red-700/50 rounded px-4 py-3">
              {error}
            </div>
          )}
          {content && !loading && (
            <pre className="font-mono text-xs text-gray-200 whitespace-pre-wrap break-words leading-relaxed">
              {content.content}
            </pre>
          )}
          {!content && !loading && !error && (
            <div className="text-sm text-gray-500">No roadmap selected.</div>
          )}
        </div>
      </div>
    </div>
  );
};

export default RoadmapViewerModal;
